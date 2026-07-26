import Foundation

enum PendingNoteStatus: String, Codable {
    case recording      // still capturing; transcript persisted incrementally
    case pendingUpload  // recording finished, note not yet saved to Supabase
}

/// A recording's transcript, persisted to disk as it's produced so nothing is
/// ever lost to a crash or a network outage. There is no audio — the transcript
/// itself is the durable artifact. Removed only once the note is saved to Supabase.
struct PendingNote: Codable, Identifiable {
    let id: UUID
    var projectId: UUID?
    let createdAt: Date
    var title: String
    var transcript: String
    var status: PendingNoteStatus
}
