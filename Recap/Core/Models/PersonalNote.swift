import Foundation

enum PersonalNoteType: String, Codable {
    case text, voice
}

struct PersonalNote: Codable, Identifiable, Hashable {
    let id: UUID
    let projectId: UUID
    let userId: UUID
    var content: String
    var type: PersonalNoteType
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case userId = "user_id"
        case content
        case type
        case createdAt = "created_at"
    }
}
