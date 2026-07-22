import Foundation

enum ChunkStatus: String, Codable {
    case pending      // recorded to disk, not yet uploaded
    case transcribed  // uploaded and transcribed successfully
    case failed       // upload/transcription failed, will retry
}

struct RecordingChunk: Codable, Identifiable {
    let id: UUID
    let index: Int
    /// File name relative to the session's folder — never a full path, so the
    /// queue survives the app's container path changing between launches.
    let fileName: String
    var status: ChunkStatus
    var transcript: String?
}

enum RecordingSessionStatus: String, Codable {
    case recording   // still capturing chunks
    case processing  // recording stopped, chunks uploading / summary pending
    case done        // note saved, safe to delete local files
}

/// A single recording session, persisted to disk so audio is never lost —
/// even if the app is killed or there's no network for a while.
struct RecordingSession: Codable, Identifiable {
    let id: UUID
    var projectId: UUID?
    let createdAt: Date
    var chunks: [RecordingChunk]
    var status: RecordingSessionStatus

    var allChunksTranscribed: Bool {
        !chunks.isEmpty && chunks.allSatisfy { $0.status == .transcribed }
    }
}
