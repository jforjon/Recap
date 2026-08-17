import Foundation
import Observation
import Network
import UIKit

struct RecordingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Orchestrates on-device live transcription and durable note saving. Speech is
/// transcribed entirely on device (no network, no third-party API), and the
/// transcript is persisted to disk as it's spoken — so losing signal, locking the
/// phone, or the app being killed never loses work. The note is uploaded to
/// Supabase when possible and retried on launch, reconnect, and foreground.
@MainActor
@Observable
final class RecordingManager {
    enum Phase {
        case idle
        case recording
    }

    /// A finished recording that hasn't reached Supabase yet.
    ///
    /// The upload takes a moment — longer with no signal, forever until the user
    /// signs in — and a recording that is invisible until it lands reads as lost.
    /// Lists render these as rows, so a recording appears the instant it is sent.
    struct PendingUpload: Identifiable, Equatable {
        let id: UUID
        let projectId: UUID?
        /// The placeholder date title; the real one is generated after the save.
        let title: String
        let createdAt: Date
        /// An attempt has already failed. It stays queued and retries on
        /// reconnect, foreground and launch — this only changes what the row says.
        var isWaiting: Bool
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: Int = 0
    /// Live transcript (committed + in-progress) shown while recording.
    private(set) var liveTranscript = ""
    /// Current smoothed loudness (0...1), driving the live waveform's amplitude.
    /// Not a history: the bars oscillate in place rather than scrolling, so only
    /// the present level matters.
    private(set) var audioLevel: CGFloat = 0
    /// Recordings queued for upload, newest last.
    private(set) var pendingUploads: [PendingUpload] = []
    /// Bumped whenever a recording lands in Supabase, or is renamed by the
    /// enricher afterwards, so any open list reloads instead of waiting for a
    /// pull-to-refresh.
    private(set) var savedVersion = 0
    /// The note behind the most recent `savedVersion` bump. Lists insert it
    /// directly so the row never blinks out between "Saving…" and the reload.
    private(set) var lastSaved: Note?

    private let transcriber = LiveTranscriber()
    private let store = PendingNoteStore.shared

    private var activeSessionId: UUID?
    private var activeProjectId: UUID?
    private var startedAt: Date?
    private var elapsedTimerTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?

    init() {
        transcriber.onUpdate = { [weak self] finalized, volatile in
            guard let self else { return }
            self.liveTranscript = Self.compose(finalized: finalized, volatile: volatile)
            // Persist only committed text — the volatile tail is still changing.
            if let id = self.activeSessionId {
                self.store.updateTranscript(id, transcript: finalized,
                                            segments: self.transcriber.segments)
            }
        }

        transcriber.onAudioLevel = { [weak self] level in
            self?.pushAudioLevel(CGFloat(level))
        }

        // Anything left queued from a previous launch is shown straight away,
        // before the retry below has had a chance to clear it.
        reloadPendingUploads()
        Task { await processPendingNotes() }
        startNetworkMonitor()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.processPendingNotes() }
        }
    }

    // MARK: - Controls

    func startRecording(projectId: UUID? = nil, language: String? = nil) async throws {
        guard phase == .idle else { return }

        let id = UUID()
        let session = PendingNote(
            id: id,
            projectId: projectId,
            createdAt: Date(),
            title: Self.defaultTitle(for: Date()),
            transcript: "",
            status: .recording,
            segments: nil
        )
        store.upsert(session)
        activeSessionId = id
        activeProjectId = projectId
        liveTranscript = ""
        resetAudioLevel()

        // Named by the pending id for now; renamed to the Supabase id once the
        // note is saved, which is what every screen looks it up by afterwards.
        let audioURL = AudioStore.newFileURL(for: id)

        do {
            try await transcriber.start(languageCode: language, audioURL: audioURL)
        } catch {
            store.remove(id)
            activeSessionId = nil
            activeProjectId = nil
            throw error
        }

        startedAt = Date()
        elapsed = 0
        phase = .recording
        startElapsedTimer()
    }

    func stopRecording() {
        guard phase == .recording, let id = activeSessionId else { return }
        stopElapsedTimer()
        phase = .idle
        elapsed = 0
        activeSessionId = nil
        activeProjectId = nil
        resetAudioLevel()

        // Queued synchronously, so the row is on screen by the time the capture
        // screen finishes dismissing — flushing the transcriber and the upload
        // itself both happen after this.
        if let note = store.note(id) {
            pendingUploads.append(
                PendingUpload(id: id, projectId: note.projectId,
                              title: note.title, createdAt: note.createdAt,
                              isWaiting: false)
            )
        }

        Task {
            let transcript = await transcriber.finish()
            store.updateTranscript(id, transcript: transcript, segments: transcriber.segments)
            store.setStatus(id, .pendingUpload)
            liveTranscript = ""
            await uploadPendingNote(id)
        }
    }

    func discardRecording() {
        guard let id = activeSessionId else { return }
        stopElapsedTimer()
        phase = .idle
        elapsed = 0
        liveTranscript = ""
        activeSessionId = nil
        activeProjectId = nil
        resetAudioLevel()

        Task {
            await transcriber.cancel()
            store.remove(id)
        }
    }

    // MARK: - Durable upload / retry

    /// Saves any queued recordings to Supabase. Recordings interrupted mid-capture
    /// (app killed) are recovered here: their persisted transcript is treated as
    /// final and uploaded. Skips the currently-active recording.
    func processPendingNotes() async {
        reloadPendingUploads()
        for note in store.pendingNotes() where note.id != activeSessionId {
            if note.status == .recording {
                store.setStatus(note.id, .pendingUpload)
            }
            await uploadPendingNote(note.id)
        }
    }

    private func uploadPendingNote(_ id: UUID) async {
        guard let note = store.note(id) else {
            dropPendingUpload(id)
            return
        }
        let transcript = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing was actually captured — drop it rather than save an empty note.
        guard !transcript.isEmpty else {
            AudioStore.delete(id)
            store.remove(id)
            dropPendingUpload(id)
            return
        }
        guard let userId = try? await SupabaseService.client.auth.session.user.id else {
            markPendingUploadWaiting(id) // not signed in / offline — stays queued
            return
        }

        // Saved transcript-only: no summary yet (the user opts into that later).
        let insert = NoteInsert(
            userId: userId,
            projectId: note.projectId,
            title: note.title,
            summary: "",
            transcript: transcript,
            transcriptSegments: note.segments,
            eventName: nil,
            speakerContext: nil,
            category: nil,
            personalReaction: nil,
            reactionType: nil
        )

        do {
            let saved = try await StorageService.saveNote(insert)
            // The audio was written under the local pending id; move it to the
            // server id now that one exists, so the detail screen can find it.
            AudioStore.rename(from: id, to: saved.id)
            store.remove(id)
            // The real row replaces the "Saving…" one in the same update, so the
            // recording never disappears from the list in between.
            dropPendingUpload(id)
            publish(saved)

            // Detached from the save: naming needs a key and a connection, and
            // the recording must be safe on the server before either is asked
            // for. If this fails the note simply keeps its date title, and the
            // detail screen tries again next time it's opened.
            Task {
                if let enriched = await NoteEnricher.enrichIfNeeded(saved) {
                    publish(enriched)
                }
            }
        } catch {
            // Left in the queue; retried on next launch / reconnect / foreground.
            markPendingUploadWaiting(id)
        }
    }

    /// Announces a note that lists should show without waiting for a refresh.
    private func publish(_ note: Note) {
        lastSaved = note
        savedVersion += 1
    }

    // MARK: - Pending rows

    /// Rebuilds the rows from the durable queue, which is the source of truth —
    /// the in-memory list is only what the UI reads.
    private func reloadPendingUploads() {
        pendingUploads = store.pendingNotes()
            .filter { $0.id != activeSessionId }
            .sorted { $0.createdAt < $1.createdAt }
            .map { note in
                PendingUpload(
                    id: note.id,
                    projectId: note.projectId,
                    title: note.title,
                    createdAt: note.createdAt,
                    // Queued from an earlier session or attempt: something
                    // already stopped it from landing.
                    isWaiting: pendingUploads.first { $0.id == note.id }?.isWaiting ?? true
                )
            }
    }

    private func dropPendingUpload(_ id: UUID) {
        pendingUploads.removeAll { $0.id == id }
    }

    private func markPendingUploadWaiting(_ id: UUID) {
        guard let index = pendingUploads.firstIndex(where: { $0.id == id }) else { return }
        pendingUploads[index].isWaiting = true
    }

    // MARK: - Timers & monitors

    private func startElapsedTimer() {
        elapsedTimerTask = Task { [weak self] in
            guard let self, let startedAt = self.startedAt else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self.elapsed = Int(Date().timeIntervalSince(startedAt))
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimerTask?.cancel()
        elapsedTimerTask = nil
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.processPendingNotes() }
        }
        monitor.start(queue: DispatchQueue(label: "com.echo.network-monitor"))
        pathMonitor = monitor
    }

    // MARK: - Waveform

    private func pushAudioLevel(_ level: CGFloat) {
        // Fast attack, slower decay so the bars pop on speech but settle smoothly.
        audioLevel = level > audioLevel
            ? audioLevel * 0.4 + level * 0.6
            : audioLevel * 0.7 + level * 0.3
    }

    private func resetAudioLevel() {
        audioLevel = 0
    }

    // MARK: - Helpers

    private static func compose(finalized: String, volatile: String) -> String {
        if volatile.isEmpty { return finalized }
        if finalized.isEmpty { return volatile }
        return finalized + " " + volatile
    }

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Recording · \(formatter.string(from: date))"
    }
}
