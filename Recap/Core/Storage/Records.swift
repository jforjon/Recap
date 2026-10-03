import Foundation
import SwiftData

// The persisted shapes. Screens never see these — `StorageService` converts them
// to the `Note` / `Project` / `PersonalNote` value types at the seam, so the
// views are unchanged from when the same structs were decoded from Postgres.
//
// CloudKit sets the rules here: every attribute has a default or is optional,
// nothing is `.unique`, and there are no relationships at all. Links are plain
// UUID attributes (`projectId`, `noteId`) — the same columns the Postgres rows
// had — and the cascades Postgres used to do are done by hand in
// `StorageService`. Each record keeps its own app-generated `id` rather than
// relying on `persistentModelID`, so a later move back to a server can reuse it
// as the row id. Enums are stored as their raw strings so a value CloudKit
// syncs in from a newer build can't fail to decode.

@Model
final class NoteRecord {
    var id: UUID = UUID()
    var projectId: UUID?
    var title: String = ""
    var eventName: String?
    var speakerContext: String?
    var category: String?
    var personalReaction: String?
    var reactionType: String?
    var summary: String?
    var transcript: String?
    /// `[TranscriptSegment]` as JSON. External storage because a long talk's
    /// segments can approach CloudKit's 1 MB record limit; out of the record it
    /// syncs as an asset instead.
    @Attribute(.externalStorage) var transcriptSegmentsData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID, createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var transcriptSegments: [TranscriptSegment]? {
        get { transcriptSegmentsData.flatMap { try? JSONDecoder().decode([TranscriptSegment].self, from: $0) } }
        set { transcriptSegmentsData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

@Model
final class ProjectRecord {
    var id: UUID = UUID()
    var name: String = ""
    /// The project summary — named `notes` after its Postgres column.
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

@Model
final class PersonalNoteRecord {
    var id: UUID = UUID()
    /// Exactly one of `projectId` / `noteId` is set — what Postgres enforced with
    /// a `num_nonnulls` check is now guaranteed by `PersonalNoteOwner`.
    var projectId: UUID?
    var noteId: UUID?
    var content: String = ""
    var type: String = PersonalNoteType.text.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), owner: PersonalNoteOwner, content: String,
         type: PersonalNoteType, createdAt: Date = Date()) {
        self.id = id
        self.projectId = owner.projectId
        self.noteId = owner.noteId
        self.content = content
        self.type = type.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

// MARK: - Record → value

extension Note {
    init(_ record: NoteRecord) {
        self.init(
            id: record.id,
            projectId: record.projectId,
            title: record.title,
            eventName: record.eventName,
            speakerContext: record.speakerContext,
            category: record.category.flatMap(NoteCategory.init(rawValue:)),
            personalReaction: record.personalReaction,
            reactionType: record.reactionType.flatMap(ReactionType.init(rawValue:)),
            summary: record.summary,
            transcript: record.transcript,
            transcriptSegments: record.transcriptSegments,
            createdAt: ISODate.string(record.createdAt)
        )
    }
}

extension Project {
    init(_ record: ProjectRecord) {
        self.init(
            id: record.id,
            name: record.name,
            notes: record.notes,
            createdAt: ISODate.string(record.createdAt),
            updatedAt: ISODate.string(record.updatedAt)
        )
    }
}

extension PersonalNote {
    init(_ record: PersonalNoteRecord) {
        self.init(
            id: record.id,
            projectId: record.projectId,
            noteId: record.noteId,
            content: record.content,
            type: PersonalNoteType(rawValue: record.type) ?? .text,
            createdAt: ISODate.string(record.createdAt)
        )
    }
}

// MARK: - Partial updates

extension NoteRecord {
    /// Applies a `JSONObject` keyed by the old Postgres column names. An unknown
    /// key throws rather than being dropped, so a typo can't silently lose an edit.
    func apply(_ fields: JSONObject) throws {
        for (key, value) in fields {
            switch key {
            case "title": title = value.stringValue ?? ""
            case "summary": summary = value.stringValue
            case "transcript": transcript = value.stringValue
            case "event_name": eventName = value.stringValue
            case "speaker_context": speakerContext = value.stringValue
            case "category": category = value.stringValue
            case "personal_reaction": personalReaction = value.stringValue
            case "reaction_type": reactionType = value.stringValue
            case "project_id": projectId = try value.uuid(key)
            default: throw StorageError(message: "Unknown note field: \(key)")
            }
        }
        updatedAt = Date()
    }
}

extension ProjectRecord {
    func apply(_ fields: JSONObject) throws {
        for (key, value) in fields {
            switch key {
            case "name": name = value.stringValue ?? ""
            case "notes": notes = value.stringValue
            default: throw StorageError(message: "Unknown project field: \(key)")
            }
        }
        updatedAt = Date()
    }
}

private extension JSONValue {
    func uuid(_ key: String) throws -> UUID? {
        guard let string = stringValue else { return nil }
        guard let id = UUID(uuidString: string) else {
            throw StorageError(message: "\(key) is not a valid id: \(string)")
        }
        return id
    }
}

// MARK: - Dates

/// The value types carry `created_at` as an ISO 8601 string, exactly as Postgres
/// returned it, so `formatShortDate` and the string sorts in the views still work.
enum ISODate {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(_ string: String) -> Date? {
        formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
