import Foundation
import Observation

struct RecordingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Orchestrates chunked on-device recording, background upload/transcription,
/// and note saving. Every chunk hits disk before any network call — losing
/// connectivity mid-recording never loses audio, it just delays processing.
@MainActor
@Observable
final class RecordingManager {
    enum Phase {
        case idle
        case recording
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: Int = 0

    private let recorder = AudioChunkRecorder()
    private let store = RecordingQueueStore.shared

    private var activeSession: RecordingSession?
    private var startedAt: Date?
    private var elapsedTimerTask: Task<Void, Never>?
    private var chunkRotationTask: Task<Void, Never>?

    private static let chunkDurationSeconds = 180

    init() {
        Task { await processPendingSessions() }
    }

    // MARK: - API keys gate

    func checkHasKeys() async -> Bool {
        guard let settings = try? await StorageService.getUserSettings() else { return false }
        return !(settings.openaiApiKey ?? "").isEmpty && !(settings.anthropicApiKey ?? "").isEmpty
    }

    // MARK: - Controls

    func startRecording(projectId: UUID? = nil) async throws {
        guard phase == .idle else { return }

        guard await recorder.requestPermission() else {
            throw RecordingError(message: "Microphone access is required to record.")
        }
        try recorder.configureSession()

        let session = RecordingSession(
            id: UUID(),
            projectId: projectId,
            createdAt: Date(),
            chunks: [],
            status: .recording
        )
        activeSession = session
        store.upsert(session)

        try startNextChunk(index: 0)

        startedAt = Date()
        elapsed = 0
        phase = .recording

        startElapsedTimer()
        startChunkRotation()
    }

    func stopRecording() {
        guard phase == .recording, var session = activeSession else { return }
        stopElapsedTimer()
        stopChunkRotation()
        finishCurrentChunk(into: &session)

        session.status = .processing
        store.upsert(session)
        activeSession = nil
        recorder.deactivateSession()

        phase = .idle
        elapsed = 0

        Task { await process(sessionId: session.id) }
    }

    func discardRecording() {
        guard let sessionId = activeSession?.id else { return }
        stopElapsedTimer()
        stopChunkRotation()
        recorder.stopAndDeleteChunk()
        recorder.deactivateSession()
        store.remove(sessionId)
        activeSession = nil
        phase = .idle
        elapsed = 0
    }

    // MARK: - Chunk rotation

    private func startNextChunk(index: Int) throws {
        guard let session = activeSession else { return }
        let url = store.chunkFileURL(sessionId: session.id, fileName: "chunk_\(index).m4a")
        try recorder.startChunk(at: url)
    }

    private func finishCurrentChunk(into session: inout RecordingSession) {
        guard let url = recorder.stopChunk() else { return }
        let chunk = RecordingChunk(
            id: UUID(),
            index: session.chunks.count,
            fileName: url.lastPathComponent,
            status: .pending,
            transcript: nil
        )
        session.chunks.append(chunk)
    }

    private func rotateChunk() {
        guard var session = activeSession else { return }
        finishCurrentChunk(into: &session)
        activeSession = session
        store.upsert(session)
        try? startNextChunk(index: session.chunks.count)

        let sessionId = session.id
        Task { await uploadPendingChunks(sessionId: sessionId) }
    }

    private func startChunkRotation() {
        chunkRotationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.chunkDurationSeconds))
                if Task.isCancelled { return }
                self.rotateChunk()
            }
        }
    }

    private func stopChunkRotation() {
        chunkRotationTask?.cancel()
        chunkRotationTask = nil
    }

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

    // MARK: - Background processing (upload -> transcribe -> summarize -> save)

    /// Call on app launch — resumes any recording that didn't finish uploading/saving last time.
    func processPendingSessions() async {
        for session in store.pendingSessions() {
            await process(sessionId: session.id)
        }
    }

    private func uploadPendingChunks(sessionId: UUID) async {
        guard var session = store.session(sessionId) else { return }
        guard let token = try? await currentAccessToken() else { return }

        for i in session.chunks.indices where session.chunks[i].status != .transcribed {
            let url = store.chunkFileURL(sessionId: session.id, fileName: session.chunks[i].fileName)
            do {
                session.chunks[i].transcript = try await TranscriptionClient.transcribe(fileURL: url, accessToken: token)
                session.chunks[i].status = .transcribed
            } catch {
                session.chunks[i].status = .failed
            }
            store.upsert(session)
        }
    }

    private func process(sessionId: UUID) async {
        await uploadPendingChunks(sessionId: sessionId)

        guard let session = store.session(sessionId) else { return }
        guard session.allChunksTranscribed else {
            return // some chunks still pending/failed — retried next launch or reconnect
        }

        let fullTranscript = session.chunks
            .sorted { $0.index < $1.index }
            .compactMap(\.transcript)
            .joined(separator: " ")

        guard
            let token = try? await currentAccessToken(),
            let userId = try? await SupabaseService.client.auth.session.user.id
        else { return }

        var title = "Untitled recording"
        var summaryText = "Summary could not be generated. The recording was saved so the audio is not lost."
        var category: NoteCategory?

        do {
            let result = try await SummaryClient.generateSummary(transcript: fullTranscript, accessToken: token)
            title = result.title
            summaryText = result.summary
            category = result.category
        } catch {
            summaryText = "Summary could not be generated: \(error.localizedDescription). The recording was saved so the audio is not lost."
        }

        let insert = NoteInsert(
            userId: userId,
            projectId: session.projectId,
            title: title,
            summary: summaryText,
            transcript: fullTranscript.isEmpty ? nil : fullTranscript,
            eventName: nil,
            speakerContext: nil,
            category: category,
            personalReaction: nil,
            reactionType: nil
        )

        do {
            _ = try await StorageService.saveNote(insert)
            store.remove(session.id)
        } catch {
            // Save failed — session stays in the queue, retried on next launch.
        }
    }

    private func currentAccessToken() async throws -> String {
        try await SupabaseService.client.auth.session.accessToken
    }
}
