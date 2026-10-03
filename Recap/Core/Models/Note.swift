import Foundation

enum NoteCategory: String, Codable, CaseIterable {
    case talk, training, panel
}

enum ReactionType: String, Codable {
    case voice, text
}

struct Note: Codable, Identifiable, Hashable {
    let id: UUID
    var projectId: UUID?
    var title: String
    var eventName: String?
    var speakerContext: String?
    var category: NoteCategory?
    var personalReaction: String?
    var reactionType: ReactionType?
    var summary: String?
    var transcript: String?
    /// Word-timed transcript, present only for recordings made after timing
    /// capture shipped. `transcript` remains the source of truth for search,
    /// export and summaries; this drives synced playback and paragraph breaks.
    var transcriptSegments: [TranscriptSegment]?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case title
        case eventName = "event_name"
        case speakerContext = "speaker_context"
        case category
        case personalReaction = "personal_reaction"
        case reactionType = "reaction_type"
        case summary
        case transcript
        case transcriptSegments = "transcript_segments"
        case createdAt = "created_at"
    }
}

/// Payload for inserting a new note — mirrors toInsertPayload() in storage.ts.
struct NoteInsert {
    /// Chosen by the caller so a recording keeps the id it was captured under —
    /// its audio file is already named by it — and so saving the same recording
    /// twice finds the first copy instead of making a second.
    var id = UUID()
    let projectId: UUID?
    let title: String
    let summary: String
    let transcript: String?
    var transcriptSegments: [TranscriptSegment]?
    let eventName: String?
    let speakerContext: String?
    let category: NoteCategory?
    let personalReaction: String?
    let reactionType: ReactionType?
}
