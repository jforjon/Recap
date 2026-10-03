import Foundation

enum PersonalNoteType: String, Codable {
    case text, voice
}

/// What a personal-note feed hangs off. A note carries exactly one of these.
enum PersonalNoteOwner: Hashable {
    case project(UUID)
    case recording(UUID)

    var projectId: UUID? {
        if case let .project(id) = self { return id }
        return nil
    }

    var noteId: UUID? {
        if case let .recording(id) = self { return id }
        return nil
    }
}

struct PersonalNote: Codable, Identifiable, Hashable {
    let id: UUID
    /// Set when the note belongs to a project's feed.
    let projectId: UUID?
    /// Set when the note belongs to a single recording's feed.
    let noteId: UUID?
    var content: String
    var type: PersonalNoteType
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case noteId = "note_id"
        case content
        case type
        case createdAt = "created_at"
    }
}
