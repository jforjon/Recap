import Foundation

/// Where a recording's audio is kept, if at all.
///
/// Off is the default and stays the default: the app has always promised audio is
/// never written anywhere, so keeping it has to be something the user chooses.
enum AudioStorageLocation: String, CaseIterable, Identifiable, Sendable {
    case off, phone, cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Don't save audio"
        case .phone: "On this iPhone"
        case .cloud: "In iCloud"
        }
    }

    var detail: String {
        switch self {
        case .off: "Only the transcript is kept. Nothing to play back."
        case .phone: "Stays on this device. Lost if you delete the app."
        case .cloud: "Syncs to your other devices and uses your iCloud storage, not recap's."
        }
    }
}

/// Owns the audio files: where they live, moving them when the user changes their
/// mind, and getting them back out of iCloud when the system has evicted them.
///
/// Files are named by note id. During recording that's the pending note's local
/// id; once the note reaches Supabase it is renamed to the server id, which is
/// what every screen afterwards looks it up by.
enum AudioStore {
    private static let locationKey = "audio.storageLocation"
    private static let folderName = "Audio"

    struct AudioError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Setting

    static var location: AudioStorageLocation {
        get {
            guard let raw = UserDefaults.standard.string(forKey: locationKey) else { return .off }
            return AudioStorageLocation(rawValue: raw) ?? .off
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: locationKey) }
    }

    static var isEnabled: Bool { location != .off }

    /// iCloud can be switched off system-wide or the user may not be signed in, in
    /// which case the container simply doesn't exist and we fall back to local.
    static var isCloudAvailable: Bool { cloudDirectory() != nil }

    // MARK: - Directories

    private static func localDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Deliberately *not* under `Documents` in the container, so recordings don't
    /// appear in the Files app where they could be deleted out from under the
    /// transcript that references them.
    private static func cloudDirectory() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let directory = container.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func directory(for location: AudioStorageLocation) -> URL? {
        switch location {
        case .off: nil
        case .phone: localDirectory()
        case .cloud: cloudDirectory() ?? localDirectory()  // graceful fallback
        }
    }

    private static func filename(_ id: UUID) -> String { "\(id.uuidString).m4a" }

    // MARK: - Lookup

    /// The audio for a note, wherever it happens to live. Both locations are
    /// checked because the setting may have changed since it was recorded.
    static func existingURL(for id: UUID) -> URL? {
        let name = filename(id)
        for directory in [localDirectory(), cloudDirectory()].compactMap({ $0 }) {
            let candidate = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            // An evicted iCloud file is present only as a `.name.icloud` placeholder.
            let placeholder = directory.appendingPathComponent(".\(name).icloud")
            if FileManager.default.fileExists(atPath: placeholder.path) { return candidate }
        }
        return nil
    }

    static func hasAudio(for id: UUID) -> Bool { existingURL(for: id) != nil }

    /// Where a new recording should be written. Nil when saving is switched off.
    static func newFileURL(for id: UUID) -> URL? {
        guard let directory = directory(for: location) else { return nil }
        return directory.appendingPathComponent(filename(id))
    }

    /// Where an imported file should be kept. Unlike `newFileURL` this never
    /// returns nil: the user was asked about this specific file and said yes, so
    /// their global "don't save audio" default doesn't apply. With saving off
    /// entirely, it lands on the device rather than in iCloud they never chose.
    static func importDestination(for id: UUID) -> URL? {
        let directory = directory(for: location) ?? localDirectory()
        return directory.appendingPathComponent(filename(id))
    }

    // MARK: - Mutation

    /// Called once a pending recording gets its real Supabase id.
    static func rename(from oldId: UUID, to newId: UUID) {
        guard let source = existingURL(for: oldId) else { return }
        let destination = source.deletingLastPathComponent().appendingPathComponent(filename(newId))
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: source, to: destination)
    }

    static func delete(_ id: UUID) {
        let name = filename(id)
        for directory in [localDirectory(), cloudDirectory()].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    // MARK: - iCloud availability

    /// iOS evicts the local copy of a synced file to reclaim space, leaving a
    /// placeholder. Playback has to ask for it back and wait, so this is awaited
    /// before handing the URL to the player.
    static func ensureDownloaded(_ url: URL) async throws {
        if FileManager.default.fileExists(atPath: url.path) { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)

        // Poll rather than use NSMetadataQuery: this runs once, on tapping play,
        // and a query object would outlive the need for it.
        for _ in 0..<120 {
            try await Task.sleep(for: .milliseconds(250))
            if FileManager.default.fileExists(atPath: url.path) { return }
        }
        throw AudioError(message: "This recording is still downloading from iCloud. Try again in a moment.")
    }

    // MARK: - Housekeeping

    static func totalBytes() -> Int64 {
        var total: Int64 = 0
        for directory in [localDirectory(), cloudDirectory()].compactMap({ $0 }) {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey]
            )) ?? []
            for file in contents {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                total += Int64(size)
            }
        }
        return total
    }

    static func formattedTotal() -> String {
        ByteCountFormatter.string(fromByteCount: totalBytes(), countStyle: .file)
    }

    /// Moves every saved recording to the newly chosen location. Files that fail
    /// to move are left where they are — `existingURL` checks both directories, so
    /// a partial migration still plays back correctly rather than losing audio.
    static func migrateAll(to newLocation: AudioStorageLocation) async {
        guard let destination = directory(for: newLocation) else { return }
        let sources = [localDirectory(), cloudDirectory()]
            .compactMap { $0 }
            .filter { $0 != destination }

        for source in sources {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil
            )) ?? []

            for file in contents where file.pathExtension == "m4a" {
                // Pull it local first: an evicted iCloud file can't be moved.
                try? await ensureDownloaded(file)
                let target = destination.appendingPathComponent(file.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.moveItem(at: file, to: target)
            }
        }
    }
}
