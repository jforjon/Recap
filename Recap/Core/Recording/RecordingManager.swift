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

    private(set) var phase: Phase = .idle
    private(set) var elapsed: Int = 0
    /// Live transcript (committed + in-progress) shown while recording.
    private(set) var liveTranscript = ""
    /// Rolling loudness history (0...1, oldest first) driving the live waveform.
    private(set) var audioLevels: [CGFloat] = Array(repeating: 0, count: barCount)

    private static let barCount = 40

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
                self.store.updateTranscript(id, transcript: finalized)
            }
        }

        transcriber.onAudioLevel = { [weak self] level in
            self?.pushAudioLevel(CGFloat(level))
        }

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
            status: .recording
        )
        store.upsert(session)
        activeSessionId = id
        activeProjectId = projectId
        liveTranscript = ""
        resetAudioLevels()

        do {
            try await transcriber.start(languageCode: language)
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
        resetAudioLevels()

        Task {
            let transcript = await transcriber.finish()
            store.updateTranscript(id, transcript: transcript)
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
        resetAudioLevels()

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
        for note in store.pendingNotes() where note.id != activeSessionId {
            if note.status == .recording {
                store.setStatus(note.id, .pendingUpload)
            }
            await uploadPendingNote(note.id)
        }
    }

    private func uploadPendingNote(_ id: UUID) async {
        guard let note = store.note(id) else { return }
        let transcript = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing was actually captured — drop it rather than save an empty note.
        guard !transcript.isEmpty else {
            store.remove(id)
            return
        }
        guard let userId = try? await SupabaseService.client.auth.session.user.id else {
            return // not signed in / offline — stays queued for a later retry
        }

        // Saved transcript-only: no summary yet (the user opts into that later).
        let insert = NoteInsert(
            userId: userId,
            projectId: note.projectId,
            title: note.title,
            summary: "",
            transcript: transcript,
            eventName: nil,
            speakerContext: nil,
            category: nil,
            personalReaction: nil,
            reactionType: nil
        )

        do {
            _ = try await StorageService.saveNote(insert)
            store.remove(id)
        } catch {
            // Left in the queue; retried on next launch / reconnect / foreground.
        }
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
        let previous = audioLevels.last ?? 0
        // Fast attack, slower decay so the bars pop on speech but settle smoothly.
        let smoothed = level > previous
            ? previous * 0.4 + level * 0.6
            : previous * 0.7 + level * 0.3
        var next = audioLevels
        next.removeFirst()
        next.append(smoothed)
        audioLevels = next
    }

    private func resetAudioLevels() {
        audioLevels = Array(repeating: 0, count: Self.barCount)
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
