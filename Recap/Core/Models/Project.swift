import Foundation

struct Project: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    var notes: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// A project alongside how many recordings belong to it — mirrors ProjectWithNoteCount in storage.ts.
struct ProjectWithNoteCount: Identifiable, Hashable {
    let project: Project
    let noteCount: Int          // recordings filed under this project
    var personalNoteCount: Int = 0
    var id: UUID { project.id }
}
