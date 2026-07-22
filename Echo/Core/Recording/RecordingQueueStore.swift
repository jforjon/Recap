import Foundation

/// Persists recording sessions + their audio chunk files under Documents/Recordings.
/// This is the durability layer: nothing here is deleted until a note is
/// fully saved to Supabase, so a recording survives app kills and network loss.
final class RecordingQueueStore {
    static let shared = RecordingQueueStore()

    private let fileManager = FileManager.default
    private let manifestURL: URL
    private let recordingsDir: URL

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingsDir = documents.appendingPathComponent("Recordings", isDirectory: true)
        manifestURL = documents.appendingPathComponent("recording_queue.json")
        try? fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
    }

    // MARK: - File paths

    func sessionDirectory(_ sessionId: UUID) -> URL {
        let dir = recordingsDir.appendingPathComponent(sessionId.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func chunkFileURL(sessionId: UUID, fileName: String) -> URL {
        sessionDirectory(sessionId).appendingPathComponent(fileName)
    }

    // MARK: - Manifest read/write

    func loadAll() -> [RecordingSession] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder().decode([RecordingSession].self, from: data)) ?? []
    }

    private func saveAll(_ sessions: [RecordingSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    func upsert(_ session: RecordingSession) {
        var all = loadAll()
        if let index = all.firstIndex(where: { $0.id == session.id }) {
            all[index] = session
        } else {
            all.append(session)
        }
        saveAll(all)
    }

    func session(_ id: UUID) -> RecordingSession? {
        loadAll().first { $0.id == id }
    }

    /// Deletes the session's audio files and removes it from the manifest —
    /// only call this once the note is safely saved to Supabase.
    func remove(_ sessionId: UUID) {
        var all = loadAll()
        all.removeAll { $0.id == sessionId }
        saveAll(all)
        try? fileManager.removeItem(at: sessionDirectory(sessionId))
    }

    /// Sessions that still have work to do — retried on launch and after regaining connectivity.
    func pendingSessions() -> [RecordingSession] {
        loadAll().filter { $0.status != .done }
    }
}
