import Foundation
import SwiftData

/// Mirrors app/lib/storage.ts function-for-function.
///
/// This is the one seam every screen reads and writes through. It used to be
/// Supabase; it is now SwiftData synced through CloudKit (`RecapStore`), with
/// the same names and signatures, so the move changed this file and not its
/// callers. Keep it that way — a later move back to a server should again touch
/// only this file. See "Keeping a way back to a server" in PLAN.md.
///
/// Every call opens its own `ModelContext`. They are cheap, and a fresh one
/// always reads what CloudKit has most recently imported instead of objects a
/// long-lived context cached before the sync landed.
enum StorageService {
    private static func context() -> ModelContext {
        ModelContext(RecapStore.container)
    }

    /// Trims a string and returns nil if the result is empty — mirrors nullableString() in storage.ts.
    static func nullableString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    // MARK: - Notes

    /// Idempotent on `note.id`: saving a recording that is already in the store
    /// returns the stored copy. A crash between this save and the recording
    /// queue being cleared would otherwise turn into a duplicate on next launch.
    static func saveNote(_ note: NoteInsert) async throws -> Note {
        // A note needs a title and some content — either a transcript (the default
        // for a fresh recording) or a summary (added later on demand).
        let hasContent = !note.summary.isEmpty || !(note.transcript ?? "").isEmpty
        guard !note.title.isEmpty, hasContent else {
            throw StorageError(message: "Invalid data before insert — title or content was empty")
        }

        let context = context()
        if let existing = try fetchNote(note.id, in: context) {
            return Note(existing)
        }

        let record = NoteRecord(id: note.id)
        record.projectId = note.projectId
        record.title = note.title
        record.summary = note.summary.isEmpty ? nil : note.summary
        record.transcript = note.transcript
        record.transcriptSegments = note.transcriptSegments
        record.eventName = note.eventName
        record.speakerContext = note.speakerContext
        record.category = note.category?.rawValue
        record.personalReaction = note.personalReaction
        record.reactionType = note.reactionType?.rawValue
        context.insert(record)
        try context.save()
        return Note(record)
    }

    static func getNotes() async throws -> [Note] {
        let descriptor = FetchDescriptor<NoteRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try context().fetch(descriptor).map(Note.init)
    }

    /// Recordings that aren't filed under a project.
    ///
    /// A recording is either in exactly one project or loose — `projectId` is a
    /// single optional, so there is no third state. The Library lists the loose
    /// ones beside the projects themselves, the way a folder listing shows
    /// folders and the files that aren't in one; a filed recording appears on its
    /// project's screen instead.
    static func getStandaloneNotes() async throws -> [Note] {
        let descriptor = FetchDescriptor<NoteRecord>(
            predicate: #Predicate { $0.projectId == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context().fetch(descriptor).map(Note.init)
    }

    static func getNoteById(_ id: UUID) async throws -> Note {
        guard let record = try fetchNote(id, in: context()) else {
            throw StorageError.notFound("Note", id: id)
        }
        return Note(record)
    }

    static func getNotesByProjectId(_ projectId: UUID) async throws -> [Note] {
        let target: UUID? = projectId
        let descriptor = FetchDescriptor<NoteRecord>(
            predicate: #Predicate { $0.projectId == target },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context().fetch(descriptor).map(Note.init)
    }

    /// `fields` mirrors Partial<Note> in storage.ts — only the keys present are updated.
    static func updateNote(_ id: UUID, fields: JSONObject) async throws -> Note {
        guard !fields.isEmpty else {
            throw StorageError.emptyPayload("Update note")
        }
        let context = context()
        guard let record = try fetchNote(id, in: context) else {
            throw StorageError.notFound("Note", id: id)
        }
        try record.apply(fields)
        try context.save()
        return Note(record)
    }

    /// Takes the recording's personal notes with it, as the Postgres foreign
    /// key's `on delete cascade` used to.
    static func deleteNote(_ id: UUID) async throws {
        let context = context()
        let target: UUID? = id
        try context.fetch(FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == id }))
            .forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<PersonalNoteRecord>(predicate: #Predicate { $0.noteId == target }))
            .forEach { context.delete($0) }
        try context.save()
        // Centralised here so no delete path anywhere can orphan an audio file.
        AudioStore.delete(id)
    }

    // MARK: - Projects

    static func createProject(name: String) async throws -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StorageError(message: "Project name is required")
        }
        let context = context()
        let record = ProjectRecord(name: trimmed)
        context.insert(record)
        try context.save()
        return Project(record)
    }

    static func getProjectById(_ id: UUID) async throws -> Project {
        guard let record = try fetchProject(id, in: context()) else {
            throw StorageError.notFound("Project", id: id)
        }
        return Project(record)
    }

    static func getProjectsWithNoteCounts() async throws -> [ProjectWithNoteCount] {
        let context = context()

        let projects = try context.fetch(
            FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        )

        // Only the link is needed to count, not the transcripts.
        var filed = FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.projectId != nil })
        filed.propertiesToFetch = [\.projectId]
        var personal = FetchDescriptor<PersonalNoteRecord>(predicate: #Predicate { $0.projectId != nil })
        personal.propertiesToFetch = [\.projectId]

        var counts: [UUID: Int] = [:]
        for note in try context.fetch(filed) {
            guard let projectId = note.projectId else { continue }
            counts[projectId, default: 0] += 1
        }
        var personalCounts: [UUID: Int] = [:]
        for note in try context.fetch(personal) {
            guard let projectId = note.projectId else { continue }
            personalCounts[projectId, default: 0] += 1
        }

        return projects.map { record in
            ProjectWithNoteCount(
                project: Project(record),
                noteCount: counts[record.id] ?? 0,
                personalNoteCount: personalCounts[record.id] ?? 0
            )
        }
    }

    /// `fields` mirrors Partial<Pick<Project, 'name' | 'notes'>> in storage.ts.
    static func updateProject(_ id: UUID, fields: JSONObject) async throws -> Project {
        guard !fields.isEmpty else {
            throw StorageError.emptyPayload("Update project")
        }
        let context = context()
        guard let record = try fetchProject(id, in: context) else {
            throw StorageError.notFound("Project", id: id)
        }
        try record.apply(fields)
        try context.save()
        return Project(record)
    }

    /// Takes everything in the project with it: its recordings, their personal
    /// notes and saved audio, and the project's own personal notes. That is what
    /// the confirmation dialog promises ("deletes the project and all its
    /// recordings"); a recording the user wants to keep can be moved out first.
    static func deleteProject(_ id: UUID) async throws {
        let context = context()
        let target: UUID? = id
        try context.fetch(FetchDescriptor<ProjectRecord>(predicate: #Predicate { $0.id == id }))
            .forEach { context.delete($0) }

        let recordings = try context.fetch(FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.projectId == target }))
        let recordingIds = recordings.map(\.id)
        recordings.forEach { context.delete($0) }
        for noteId in recordingIds {
            let owner: UUID? = noteId
            try context.fetch(FetchDescriptor<PersonalNoteRecord>(predicate: #Predicate { $0.noteId == owner }))
                .forEach { context.delete($0) }
        }

        try context.fetch(FetchDescriptor<PersonalNoteRecord>(predicate: #Predicate { $0.projectId == target }))
            .forEach { context.delete($0) }
        try context.save()
        recordingIds.forEach(AudioStore.delete)
    }

    // MARK: - User settings
    //
    // Intentionally absent. The Anthropic API key lives in the device Keychain
    // (`AnthropicKeyStore`), and there is no `user_settings` table any more.

    // MARK: - Personal notes

    static func getPersonalNotes(_ owner: PersonalNoteOwner) async throws -> [PersonalNote] {
        let ascending = [SortDescriptor<PersonalNoteRecord>(\.createdAt)]
        let descriptor: FetchDescriptor<PersonalNoteRecord> = switch owner {
        case let .project(id):
            FetchDescriptor(predicate: Self.ownedByProject(id), sortBy: ascending)
        case let .recording(id):
            FetchDescriptor(predicate: Self.ownedByNote(id), sortBy: ascending)
        }
        return try context().fetch(descriptor).map(PersonalNote.init)
    }

    /// Every personal note the user has written, across all projects and
    /// recordings. One query instead of per-owner fetches, because both callers
    /// need the whole set at once: Library search matches against them, and a
    /// project export folds each recording's notes in beside its transcript.
    static func getAllPersonalNotes() async throws -> [PersonalNote] {
        let descriptor = FetchDescriptor<PersonalNoteRecord>(sortBy: [SortDescriptor(\.createdAt)])
        return try context().fetch(descriptor).map(PersonalNote.init)
    }

    static func createPersonalNote(
        owner: PersonalNoteOwner,
        content: String,
        type: PersonalNoteType = .text
    ) async throws -> PersonalNote {
        let context = context()
        let record = PersonalNoteRecord(owner: owner, content: content, type: type)
        context.insert(record)
        try context.save()
        return PersonalNote(record)
    }

    static func updatePersonalNote(_ id: UUID, content: String) async throws {
        let context = context()
        for record in try context.fetch(FetchDescriptor<PersonalNoteRecord>(predicate: #Predicate { $0.id == id })) {
            record.content = content
            record.updatedAt = Date()
        }
        try context.save()
    }

    static func deletePersonalNote(_ id: UUID) async throws {
        let context = context()
        try context.fetch(FetchDescriptor<PersonalNoteRecord>(predicate: #Predicate { $0.id == id }))
            .forEach { context.delete($0) }
        try context.save()
    }

    static func deleteAllPersonalNotes(owner: PersonalNoteOwner) async throws {
        let context = context()
        let predicate = switch owner {
        case let .project(id): Self.ownedByProject(id)
        case let .recording(id): Self.ownedByNote(id)
        }
        try context.fetch(FetchDescriptor(predicate: predicate)).forEach { context.delete($0) }
        try context.save()
    }

    // MARK: - Everything

    /// Posted once everything has been deleted, so screens that are still alive
    /// underneath Settings reload instead of showing what's gone.
    static let didDeleteAllData = Notification.Name("StorageService.didDeleteAllData")

    /// Deletes every recording, project and personal note. CloudKit then removes
    /// them from the user's iCloud and their other devices.
    ///
    /// Object by object rather than `delete(model:)`: a batch delete skips the
    /// change tracking CloudKit mirrors from, so the records would come straight
    /// back from iCloud on the next sync.
    ///
    /// Store only. The caller handles what lives elsewhere on the device: the
    /// Keychain key, the recording queue and saved audio.
    static func deleteAllData() async throws {
        let context = context()
        try context.fetch(FetchDescriptor<NoteRecord>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<ProjectRecord>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<PersonalNoteRecord>()).forEach { context.delete($0) }
        try context.save()
    }

    // MARK: - One-off Supabase import

    /// Posted after the old account's data has been imported, so the Library reloads.
    static let didImport = Notification.Name("StorageService.didImport")

    /// Writes the old Supabase rows into the store, keeping each row's id and
    /// dates. Rows whose id is already here are skipped, so a second run is
    /// harmless. See `SupabaseImport`.
    static func importLegacy(_ export: SupabaseImport.Export) async throws -> SupabaseImport.Summary {
        let context = context()
        var summary = SupabaseImport.Summary()

        for row in export.projects {
            if try fetchProject(row.id, in: context) != nil { summary.skipped += 1; continue }
            let created = SupabaseImport.date(row.created_at) ?? Date()
            let record = ProjectRecord(id: row.id, name: row.name, createdAt: created)
            record.notes = row.notes
            record.updatedAt = SupabaseImport.date(row.updated_at) ?? created
            context.insert(record)
            summary.projects += 1
        }

        for row in export.notes {
            if try fetchNote(row.id, in: context) != nil { summary.skipped += 1; continue }
            let created = SupabaseImport.date(row.created_at) ?? Date()
            let record = NoteRecord(id: row.id, createdAt: created)
            record.updatedAt = SupabaseImport.date(row.updated_at) ?? created
            record.projectId = row.project_id
            record.title = row.title
            record.eventName = row.event_name
            record.speakerContext = row.speaker_context
            record.category = row.category
            record.personalReaction = row.personal_reaction
            record.reactionType = row.reaction_type
            record.summary = nullableString(row.summary)
            record.transcript = row.transcript
            record.transcriptSegments = row.transcript_segments
            context.insert(record)
            summary.notes += 1
        }

        for row in export.personalNotes {
            let owner: PersonalNoteOwner
            if let noteId = row.note_id {
                owner = .recording(noteId)
            } else if let projectId = row.project_id {
                owner = .project(projectId)
            } else {
                continue // Postgres's check constraint made this impossible.
            }
            let id = row.id
            var existing = FetchDescriptor<PersonalNoteRecord>(predicate: #Predicate { $0.id == id })
            existing.fetchLimit = 1
            if try !context.fetch(existing).isEmpty { summary.skipped += 1; continue }
            context.insert(PersonalNoteRecord(
                id: row.id,
                owner: owner,
                content: row.content,
                type: row.type.flatMap(PersonalNoteType.init(rawValue:)) ?? .text,
                createdAt: SupabaseImport.date(row.created_at) ?? Date()
            ))
            summary.personalNotes += 1
        }

        try context.save()
        return summary
    }

    // MARK: - Helpers

    private static func fetchNote(_ id: UUID, in context: ModelContext) throws -> NoteRecord? {
        var descriptor = FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func fetchProject(_ id: UUID, in context: ModelContext) throws -> ProjectRecord? {
        var descriptor = FetchDescriptor<ProjectRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func ownedByProject(_ id: UUID) -> Predicate<PersonalNoteRecord> {
        let target: UUID? = id
        return #Predicate { $0.projectId == target }
    }

    private static func ownedByNote(_ id: UUID) -> Predicate<PersonalNoteRecord> {
        let target: UUID? = id
        return #Predicate { $0.noteId == target }
    }
}
