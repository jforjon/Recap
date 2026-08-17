import Foundation
import Observation

/// A queued audio-file import. Persisted so a long transcription survives the
/// app being killed and resumes on next launch, the same guarantee live
/// recordings already get from `PendingNoteStore`.
struct AudioImportJob: Codable, Identifiable, Sendable {
    let id: UUID
    var projectId: UUID?
    var title: String
    /// Filename inside the imports working directory. The picked file is copied
    /// there immediately, because a security-scoped URL from the Files app is
    /// only valid for the moment the user chose it.
    var filename: String
    var languageCode: String?
    var keepAudio: Bool
    var createdAt: Date
}

/// Imports audio files: copies them somewhere durable, transcribes them on
/// device in the background, and saves the result as an ordinary recording.
///
/// Serial by design — transcription is CPU-heavy and two at once would make both
/// slower and drain the battery faster, for no gain.
@MainActor
@Observable
final class AudioImportManager {
    struct Progress: Identifiable {
        let id: UUID
        let title: String
        var fraction: Double
        var failure: String?
    }

    /// Imports currently queued or running, shown as rows in the Library.
    private(set) var inFlight: [Progress] = []
    /// Bumped when an import finishes, so the Library reloads and picks it up.
    private(set) var completedVersion = 0

    private let manifestURL: URL
    private let workingDirectory: URL
    private var isProcessing = false

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        manifestURL = documents.appendingPathComponent("audio_imports.json")
        workingDirectory = documents.appendingPathComponent("Imports", isDirectory: true)
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        // Anything left in the manifest was interrupted — pick it back up.
        let queued = load()
        inFlight = queued.map { Progress(id: $0.id, title: $0.title, fraction: 0) }
        Task { await processQueue() }
    }

    // MARK: - Public API

    /// Whether the picked file looks importable before any work is queued.
    static func isSupported(_ url: URL) -> Bool {
        ["m4a", "mp3", "wav", "aiff", "aif", "caf", "aac", "mp4", "m4b"]
            .contains(url.pathExtension.lowercased())
    }

    /// Copies the picked file somewhere durable and queues it. Returns
    /// immediately — the transcription runs in the background.
    func enqueue(
        pickedURL: URL,
        projectId: UUID?,
        languageCode: String?,
        keepAudio: Bool
    ) throws {
        // A URL handed over by the Files app is security-scoped and stops being
        // readable as soon as this call returns, so the copy cannot be deferred.
        let scoped = pickedURL.startAccessingSecurityScopedResource()
        defer { if scoped { pickedURL.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        let filename = "\(id.uuidString).\(pickedURL.pathExtension)"
        let destination = workingDirectory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: pickedURL, to: destination)

        let job = AudioImportJob(
            id: id,
            projectId: projectId,
            title: pickedURL.deletingPathExtension().lastPathComponent,
            filename: filename,
            languageCode: languageCode,
            keepAudio: keepAudio,
            createdAt: Date()
        )
        save(load() + [job])
        inFlight.append(Progress(id: id, title: job.title, fraction: 0))
        Task { await processQueue() }
    }

    /// Clears a failed row once the user has seen it.
    func dismiss(_ id: UUID) {
        inFlight.removeAll { $0.id == id }
        save(load().filter { $0.id != id })
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    // MARK: - Queue

    private func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        while let job = load().first(where: { job in
            // Skip anything already parked with an error awaiting dismissal.
            inFlight.first { $0.id == job.id }?.failure == nil
        }) {
            await run(job)
        }
    }

    private func run(_ job: AudioImportJob) async {
        let url = workingDirectory.appendingPathComponent(job.filename)

        do {
            let output = try await AudioFileTranscriber.transcribe(
                url: url,
                languageCode: job.languageCode
            ) { [weak self] fraction in
                Task { @MainActor in self?.updateProgress(job.id, fraction) }
            }

            guard let userId = try? await SupabaseService.client.auth.session.user.id else {
                throw AudioFileTranscriber.TranscribeError(
                    message: "You need to be signed in to save an imported recording."
                )
            }

            let saved = try await StorageService.saveNote(
                NoteInsert(
                    userId: userId,
                    projectId: job.projectId,
                    title: job.title,
                    summary: "",
                    transcript: output.transcript,
                    transcriptSegments: output.segments,
                    eventName: nil,
                    speakerContext: nil,
                    category: nil,
                    personalReaction: nil,
                    reactionType: nil
                )
            )

            if job.keepAudio, let destination = AudioStore.importDestination(for: saved.id) {
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.moveItem(at: url, to: destination)
            }

            finish(job.id)
        } catch {
            // Kept in the manifest with the error shown, so the user can see why
            // and dismiss it rather than the file vanishing silently.
            fail(job.id, message: error.localizedDescription)
        }
    }

    private func updateProgress(_ id: UUID, _ fraction: Double) {
        guard let index = inFlight.firstIndex(where: { $0.id == id }) else { return }
        inFlight[index].fraction = fraction
    }

    private func finish(_ id: UUID) {
        inFlight.removeAll { $0.id == id }
        save(load().filter { $0.id != id })
        try? FileManager.default.removeItem(at: fileURL(for: id))
        completedVersion += 1
    }

    private func fail(_ id: UUID, message: String) {
        guard let index = inFlight.firstIndex(where: { $0.id == id }) else { return }
        inFlight[index].failure = message
    }

    private func fileURL(for id: UUID) -> URL {
        let match = load().first { $0.id == id }
        return workingDirectory.appendingPathComponent(match?.filename ?? id.uuidString)
    }

    // MARK: - Manifest

    private func load() -> [AudioImportJob] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder().decode([AudioImportJob].self, from: data)) ?? []
    }

    private func save(_ jobs: [AudioImportJob]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
