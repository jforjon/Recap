import Foundation

/// Durable, on-disk queue of recording transcripts. This is the durability layer:
/// a transcript is written here as it's spoken and is not removed until the note
/// is fully saved to Supabase, so a recording survives app kills and network loss.
/// No audio is stored — only text, so the footprint is tiny.
final class PendingNoteStore {
    static let shared = PendingNoteStore()

    private let fileManager = FileManager.default
    private let manifestURL: URL
    private let lock = NSLock()

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        manifestURL = documents.appendingPathComponent("pending_notes.json")
    }

    // MARK: - Manifest read/write

    private func loadAllUnlocked() -> [PendingNote] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder().decode([PendingNote].self, from: data)) ?? []
    }

    private func saveAllUnlocked(_ notes: [PendingNote]) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    func loadAll() -> [PendingNote] {
        lock.lock(); defer { lock.unlock() }
        return loadAllUnlocked()
    }

    func upsert(_ note: PendingNote) {
        lock.lock(); defer { lock.unlock() }
        var all = loadAllUnlocked()
        if let index = all.firstIndex(where: { $0.id == note.id }) {
            all[index] = note
        } else {
            all.append(note)
        }
        saveAllUnlocked(all)
    }

    func note(_ id: UUID) -> PendingNote? {
        lock.lock(); defer { lock.unlock() }
        return loadAllUnlocked().first { $0.id == id }
    }

    /// Persists the latest committed transcript for an in-progress recording.
    func updateTranscript(_ id: UUID, transcript: String) {
        mutate(id) { $0.transcript = transcript }
    }

    func setStatus(_ id: UUID, _ status: PendingNoteStatus) {
        mutate(id) { $0.status = status }
    }

    func remove(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        var all = loadAllUnlocked()
        all.removeAll { $0.id == id }
        saveAllUnlocked(all)
    }

    /// Every queued recording — retried on launch, on regaining connectivity, and
    /// when the app returns to the foreground.
    func pendingNotes() -> [PendingNote] {
        loadAll()
    }

    private func mutate(_ id: UUID, _ change: (inout PendingNote) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var all = loadAllUnlocked()
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[index])
        saveAllUnlocked(all)
    }
}
