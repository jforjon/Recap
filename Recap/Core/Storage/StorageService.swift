import Foundation
import Supabase

/// Mirrors app/lib/storage.ts function-for-function.
enum StorageService {
    private static var db: SupabaseClient { SupabaseService.client }

    static func currentUserId() async throws -> UUID {
        guard let session = try? await db.auth.session else {
            throw StorageError.notAuthenticated()
        }
        return session.user.id
    }

    /// Trims a string and returns nil if the result is empty — mirrors nullableString() in storage.ts.
    static func nullableString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    // MARK: - Notes

    static func saveNote(_ note: NoteInsert) async throws -> Note {
        // A note needs a title and some content — either a transcript (the default
        // for a fresh recording) or a summary (added later on demand).
        let hasContent = !note.summary.isEmpty || !(note.transcript ?? "").isEmpty
        guard !note.title.isEmpty, hasContent else {
            throw StorageError(message: "Invalid data before insert — title or content was empty")
        }

        return try await db.from("notes")
            .insert(note)
            .select()
            .single()
            .execute()
            .value
    }

    static func getNotes() async throws -> [Note] {
        let userId = try await currentUserId()
        return try await db.from("notes")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Same query as getNotes() — kept as a separate name to mirror storage.ts's getStandaloneNotes().
    static func getStandaloneNotes() async throws -> [Note] {
        try await getNotes()
    }

    static func getNoteById(_ id: UUID) async throws -> Note {
        do {
            return try await db.from("notes")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
        } catch {
            // A cancelled request (e.g. SwiftUI restarting a `.task` during a
            // NavigationSplitView push) is not a missing row — let it propagate so
            // callers' `isCancellation` guards can ignore it instead of surfacing a
            // bogus "not found" alert.
            if error.isCancellation { throw error }
            throw StorageError.notFound("Note", id: id)
        }
    }

    static func getNotesByProjectId(_ projectId: UUID) async throws -> [Note] {
        let userId = try await currentUserId()
        return try await db.from("notes")
            .select()
            .eq("user_id", value: userId)
            .eq("project_id", value: projectId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// `fields` mirrors Partial<Note> in storage.ts — only the keys present are updated.
    static func updateNote(_ id: UUID, fields: JSONObject) async throws -> Note {
        guard !fields.isEmpty else {
            throw StorageError.emptyPayload("Update note")
        }
        do {
            return try await db.from("notes")
                .update(fields)
                .eq("id", value: id)
                .select()
                .single()
                .execute()
                .value
        } catch {
            if error.isCancellation { throw error }
            throw StorageError.notFound("Note", id: id)
        }
    }

    static func deleteNote(_ id: UUID) async throws {
        try await db.from("notes")
            .delete()
            .eq("id", value: id)
            .execute()
        // Centralised here so no delete path anywhere can orphan an audio file.
        AudioStore.delete(id)
    }

    // MARK: - Projects

    static func createProject(name: String) async throws -> Project {
        let userId = try await currentUserId()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StorageError(message: "Project name is required")
        }

        struct Payload: Encodable {
            let userId: UUID
            let name: String
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case name
            }
        }

        return try await db.from("projects")
            .insert(Payload(userId: userId, name: trimmed))
            .select()
            .single()
            .execute()
            .value
    }

    static func getProjectById(_ id: UUID) async throws -> Project {
        do {
            return try await db.from("projects")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
        } catch {
            if error.isCancellation { throw error }
            throw StorageError.notFound("Project", id: id)
        }
    }

    static func getProjectsWithNoteCounts() async throws -> [ProjectWithNoteCount] {
        let userId = try await currentUserId()

        let projects: [Project] = try await db.from("projects")
            .select()
            .eq("user_id", value: userId)
            .order("updated_at", ascending: false)
            .execute()
            .value

        struct ProjectIdRow: Decodable {
            let projectId: UUID?
            enum CodingKeys: String, CodingKey {
                case projectId = "project_id"
            }
        }

        async let noteRowsResult: [ProjectIdRow] = db.from("notes")
            .select("project_id")
            .eq("user_id", value: userId)
            .not("project_id", operator: .`is`, value: "null")
            .execute()
            .value

        async let personalRowsResult: [ProjectIdRow] = db.from("personal_notes")
            .select("project_id")
            .eq("user_id", value: userId)
            .execute()
            .value

        let noteRows = try await noteRowsResult
        let personalRows = try await personalRowsResult

        var counts: [UUID: Int] = [:]
        for row in noteRows {
            guard let projectId = row.projectId else { continue }
            counts[projectId, default: 0] += 1
        }
        var personalCounts: [UUID: Int] = [:]
        for row in personalRows {
            guard let projectId = row.projectId else { continue }
            personalCounts[projectId, default: 0] += 1
        }

        return projects.map { project in
            ProjectWithNoteCount(
                project: project,
                noteCount: counts[project.id] ?? 0,
                personalNoteCount: personalCounts[project.id] ?? 0
            )
        }
    }

    /// `fields` mirrors Partial<Pick<Project, 'name' | 'notes'>> in storage.ts.
    static func updateProject(_ id: UUID, fields: JSONObject) async throws -> Project {
        guard !fields.isEmpty else {
            throw StorageError.emptyPayload("Update project")
        }
        do {
            return try await db.from("projects")
                .update(fields)
                .eq("id", value: id)
                .select()
                .single()
                .execute()
                .value
        } catch {
            if error.isCancellation { throw error }
            throw StorageError.notFound("Project", id: id)
        }
    }

    static func deleteProject(_ id: UUID) async throws {
        try await db.from("projects")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - User settings
    //
    // Intentionally absent: the Anthropic API key used to be read and written
    // here as a plain-text `user_settings.anthropic_api_key` column. It now
    // lives in the device Keychain — see `AnthropicKeyStore`. This diverges from
    // app/lib/storage.ts on purpose; the web app should drop the column too.

    // MARK: - Personal notes

    static func getPersonalNotes(_ owner: PersonalNoteOwner) async throws -> [PersonalNote] {
        let base = db.from("personal_notes").select()
        let filtered = switch owner {
        case let .project(id): base.eq("project_id", value: id)
        case let .recording(id): base.eq("note_id", value: id)
        }
        return try await filtered
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// Every personal note the user has written, across all projects and
    /// recordings. One query instead of per-owner fetches, because both callers
    /// need the whole set at once: Library search matches against them, and a
    /// project export folds each recording's notes in beside its transcript.
    static func getAllPersonalNotes() async throws -> [PersonalNote] {
        let userId = try await currentUserId()
        return try await db.from("personal_notes")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    static func createPersonalNote(
        owner: PersonalNoteOwner,
        content: String,
        type: PersonalNoteType = .text
    ) async throws -> PersonalNote {
        let userId = try await currentUserId()

        // Optionals synthesize to `encodeIfPresent`, so the unused column is
        // omitted from the insert and keeps its NULL default.
        struct Payload: Encodable {
            let projectId: UUID?
            let noteId: UUID?
            let userId: UUID
            let content: String
            let type: PersonalNoteType
            enum CodingKeys: String, CodingKey {
                case projectId = "project_id"
                case noteId = "note_id"
                case userId = "user_id"
                case content
                case type
            }
        }

        let payload = Payload(
            projectId: owner.projectId,
            noteId: owner.noteId,
            userId: userId,
            content: content,
            type: type
        )

        return try await db.from("personal_notes")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    static func updatePersonalNote(_ id: UUID, content: String) async throws {
        try await db.from("personal_notes")
            .update(["content": AnyJSON.string(content)])
            .eq("id", value: id)
            .execute()
    }

    static func deletePersonalNote(_ id: UUID) async throws {
        try await db.from("personal_notes")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    static func deleteAllPersonalNotes(owner: PersonalNoteOwner) async throws {
        let base = db.from("personal_notes").delete()
        let filtered = switch owner {
        case let .project(id): base.eq("project_id", value: id)
        case let .recording(id): base.eq("note_id", value: id)
        }
        try await filtered.execute()
    }
}
