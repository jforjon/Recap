import SwiftUI
import Supabase

struct LibraryContentView: View {
    let nav: AppNavigationModel
    let authManager: AuthManager
    let importManager: AudioImportManager
    let recordingManager: RecordingManager

    enum Filter: String, CaseIterable, Hashable {
        case all = "All"
        case projects = "Projects"
        case recordings = "Recordings"
    }

    @State private var notes: [Note] = []
    @State private var projects: [ProjectWithNoteCount] = []
    /// Personal notes for the whole account, grouped by what they hang off, so
    /// search can reach the user's own words as well as the transcripts.
    @State private var notesByRecording: [UUID: [PersonalNote]] = [:]
    @State private var notesByProject: [UUID: [PersonalNote]] = [:]
    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showNewProject = false
    @State private var showImportPicker = false
    @State private var pendingDeleteProject: ProjectWithNoteCount?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    Text("Library")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Spacing.s2)

                    searchBar
                    HStack(spacing: Spacing.s2) {
                        ForEach(Filter.allCases, id: \.self) { option in
                            FilterChip(title: option.rawValue, isActive: filter == option) {
                                filter = option
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .recapCardRow()

                // Above everything: a recording just sent, or an import in
                // flight, is the most recent thing the user did and the thing
                // they'll be watching for.
                if showsRecordings {
                    ForEach(pendingUploads) { upload in
                        PendingRecordingRow(upload: upload)
                            .recapCardRow()
                    }
                }

                ForEach(importManager.inFlight) { progress in
                    ImportProgressRow(progress: progress) {
                        importManager.dismiss(progress.id)
                    }
                    .recapCardRow()
                }

                if isEmptyState && importManager.inFlight.isEmpty && pendingUploads.isEmpty {
                    emptyState.recapCardRow()
                }

                // Projects
                if showsProjects {
                    ForEach(projectHits) { hit in
                        let item = hit.project
                        // The snippet sits outside the Button so the projectCard
                        // press treatment stays on the card itself.
                        VStack(alignment: .leading, spacing: Spacing.s2) {
                            Button {
                                nav.sidebarSelection = .project(item.id)
                            } label: {
                                ProjectCard(
                                    name: item.project.name,
                                    recordingCount: item.noteCount,
                                    noteCount: item.personalNoteCount
                                )
                            }
                            .buttonStyle(.projectCard)

                            matchContext(field: hit.field, snippet: hit.snippet)
                        }
                        .recapCardRow()
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeleteProject = item
                            } label: {
                                Label("Delete project", systemImage: "trash")
                            }
                            .tint(AppColors.destructive)
                        }
                    }
                }

                // Recordings
                if showsRecordings {
                    ForEach(noteHits) { hit in
                        let note = hit.note
                        Button {
                            nav.detailSelection = .note(note.id)
                        } label: {
                            noteRow(note, hit: hit)
                        }
                        .buttonStyle(.plain)
                        .recapCardRow()
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await deleteNote(note.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(AppColors.destructive)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .recapBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    AppMenuButton(title: "New project", systemImage: "folder.badge.plus") {
                        showNewProject = true
                    }
                    AppMenuButton(title: "Import audio file", systemImage: "square.and.arrow.down") {
                        showImportPicker = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .tint(AppColors.textBright)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .tint(AppColors.textBright)
            }
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView(authManager: authManager)
        }
        .audioImporter(isPresented: $showImportPicker, importManager: importManager)
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet(standaloneNotes: notes) {
                nav.projectsVersion += 1
            }
        }
        .alert(
            "Delete project?",
            isPresented: Binding(
                get: { pendingDeleteProject != nil },
                set: { if !$0 { pendingDeleteProject = nil } }
            ),
            presenting: pendingDeleteProject
        ) { project in
            Button("Delete", role: .destructive) {
                Task { await deleteProject(project) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its recordings stay in your Library; personal notes are deleted.")
        }
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: nav.projectsVersion) { Task { await load() } }
        // A finished import has written a new note straight to the database.
        .onChange(of: importManager.completedVersion) { Task { await load() } }
        // A recording has landed (or been renamed by the enricher afterwards).
        // The note is inserted here rather than waiting for the reload, so the
        // row doesn't blink out as the "Saving…" one is removed.
        .onChange(of: recordingManager.savedVersion) {
            if let saved = recordingManager.lastSaved, saved.projectId == nil {
                if let index = notes.firstIndex(where: { $0.id == saved.id }) {
                    notes[index] = saved
                } else {
                    notes.insert(saved, at: 0)
                }
            }
            Task { await load() }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header controls

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(AppColors.labelWhite.opacity(0.45))
            TextField("Search transcripts, summaries, notes", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(AppColors.textPrimary)
                .tint(AppColors.accentGraphic)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.labelWhite.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, 11)
        .background(AppColors.surface)
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            EmptyStateView(
                icon: "waveform",
                title: "Nothing here yet",
                message: "Make your first recording with the button below, or create a project to organize them."
            )
        } else {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No matches",
                message: "Nothing matches “\(searchText)” in any title, transcript, summary or note. Try fewer words."
            )
        }
    }

    private func noteRow(_ note: Note, hit: LibrarySearch.NoteHit) -> some View {
        AppCard {
            HStack {
                if let category = note.category {
                    AppChip(text: category.displayText, dotColor: category.dotColor)
                } else {
                    AppChip(text: "Note")
                }
                Spacer()
                Text(formatShortDate(note.createdAt))
                    .appTextStyle(.mono)
                    .foregroundStyle(AppColors.neutral500)
            }
            Text(note.title)
                .appTextStyle(.bodyMedium)
                .foregroundStyle(AppColors.neutral800)

            matchContext(field: hit.field, snippet: hit.snippet)
        }
    }

    /// Why a row is in the results: which part matched, and the words around it.
    /// Without this, a transcript hit looks like an unrelated recording.
    @ViewBuilder
    private func matchContext(field: LibrarySearch.Field, snippet: AttributedString?) -> some View {
        if let snippet {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                    .appTextStyle(.label)
                    .foregroundStyle(AppColors.neutral500)
                Text(snippet)
                    .appTextStyle(.small)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
    }

    // MARK: - Filtering

    private var showsProjects: Bool { filter == .all || filter == .projects }
    private var showsRecordings: Bool { filter == .all || filter == .recordings }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var noteHits: [LibrarySearch.NoteHit] {
        guard showsRecordings else { return [] }
        return LibrarySearch.notes(
            matching: query,
            in: notes,
            personalNotesByRecording: notesByRecording
        )
    }

    private var projectHits: [LibrarySearch.ProjectHit] {
        guard showsProjects else { return [] }
        return LibrarySearch.projects(
            matching: query,
            in: projects,
            personalNotesByProject: notesByProject
        )
    }

    private var isEmptyState: Bool {
        !isLoading && noteHits.isEmpty && projectHits.isEmpty
    }

    /// Recordings still on their way to the server. Standalone ones only — the
    /// Library lists standalone recordings, and a project's own are shown on the
    /// project screen. They're hidden while searching, since a row with only a
    /// placeholder date title can't match anything the user typed.
    private var pendingUploads: [RecordingManager.PendingUpload] {
        guard query.isEmpty else { return [] }
        return recordingManager.pendingUploads
            .filter { $0.projectId == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        do {
            async let notesResult = StorageService.getStandaloneNotes()
            async let projectsResult = StorageService.getProjectsWithNoteCounts()
            async let personalResult = StorageService.getAllPersonalNotes()
            notes = try await notesResult
            projects = try await projectsResult

            // Grouped once here rather than per keystroke — search re-runs on
            // every character typed.
            let personal = try await personalResult
            notesByRecording = Dictionary(grouping: personal.filter { $0.noteId != nil }) { $0.noteId! }
            notesByProject = Dictionary(grouping: personal.filter { $0.projectId != nil }) { $0.projectId! }
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteNote(_ id: UUID) async {
        notes.removeAll { $0.id == id }
        do {
            try await StorageService.deleteNote(id)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
            await load()
        }
    }

    private func deleteProject(_ item: ProjectWithNoteCount) async {
        projects.removeAll { $0.id == item.id }
        do {
            try await StorageService.deleteProject(item.id)
            nav.projectsVersion += 1
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
            await load()
        }
    }
}

/// Two-step "New project" flow: name the project, then optionally add existing
/// recordings to it (skippable).
private struct NewProjectSheet: View {
    let standaloneNotes: [Note]
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var createdProject: Project?
    @State private var isBusy = false
    @State private var selected: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var addFilter: AddFilter = .all

    enum AddFilter: String, CaseIterable, Hashable {
        case all = "All"
        case selected = "Selected"
        case unselected = "Unselected"
    }

    /// Search-filtered recordings.
    private var searchedNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return standaloneNotes }
        return standaloneNotes.filter { $0.title.lowercased().contains(query) }
    }

    /// Search + selection filter applied.
    private var displayedNotes: [Note] {
        switch addFilter {
        case .all: return searchedNotes
        case .selected: return searchedNotes.filter { selected.contains($0.id) }
        case .unselected: return searchedNotes.filter { !selected.contains($0.id) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let project = createdProject {
                    addRecordingsStep(project)
                } else {
                    nameStep
                }
            }
            .recapBackground()
            .navigationTitle(createdProject == nil ? "New project" : "Add recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if createdProject == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.tint(AppColors.accentGraphic)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") { finish() }.tint(AppColors.accentGraphic)
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text("PROJECT NAME")
                .appTextStyle(.label)
                .foregroundStyle(AppColors.neutral600)
            AppTextField(title: "e.g. Summit 2026", text: $name)
            Spacer()
            Button(isBusy ? "Creating…" : "Create project") {
                Task { await create() }
            }
            .buttonStyle(.appPrimary)
            .disabled(isBusy || name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Spacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func addRecordingsStep(_ project: Project) -> some View {
        VStack(spacing: 0) {
            if standaloneNotes.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "waveform",
                    title: "No recordings yet",
                    message: "Once you’ve made some recordings, you can add them to this project."
                )
                Spacer()
            } else {
                searchBar
                    .padding(.horizontal, Spacing.s4)
                    .padding(.top, Spacing.s3)
                    .padding(.bottom, Spacing.s2)
                HStack(spacing: Spacing.s2) {
                    ForEach(AddFilter.allCases, id: \.self) { option in
                        FilterChip(title: option.rawValue, isActive: addFilter == option) {
                            addFilter = option
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.bottom, Spacing.s2)
                List {
                    Section {
                        Text("Choose recordings to add to “\(project.name)”. You can skip this.")
                            .appTextStyle(.small)
                            .foregroundStyle(AppColors.textSecondary)
                            .recapCardRow()
                        ForEach(displayedNotes) { note in
                            Button { toggle(note.id) } label: {
                                noteRow(note)
                            }
                            .buttonStyle(.plain)
                            .recapCardRow()
                        }
                    }
                }
                .listStyle(.plain)
                .recapBackground()
            }

            Button(selected.isEmpty
                   ? "Add to project"
                   : "Add \(selected.count) recording\(selected.count == 1 ? "" : "s")") {
                Task { await addSelected() }
            }
            .buttonStyle(.appPrimary)
            .disabled(isBusy || selected.isEmpty)
            .padding(Spacing.s5)
        }
    }

    private func noteRow(_ note: Note) -> some View {
        let isSelected = selected.contains(note.id)
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack {
                if let category = note.category {
                    AppChip(text: category.displayText, dotColor: category.dotColor)
                } else {
                    AppChip(text: "Note")
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? AppColors.accentGraphic : AppColors.labelWhite.opacity(0.25))
            }
            Text(note.title)
                .appTextStyle(.bodyMedium)
                .foregroundStyle(AppColors.neutral800)
        }
        .padding(Spacing.s3 + 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AppColors.accentTint : AppColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isSelected ? AppColors.accentGraphic.opacity(0.55) : AppColors.separator,
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(AppColors.labelWhite.opacity(0.45))
            TextField("Search recordings", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(AppColors.textPrimary)
                .tint(AppColors.accentGraphic)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.labelWhite.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, 11)
        .background(AppColors.surface)
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(Capsule())
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func create() async {
        isBusy = true
        defer { isBusy = false }
        do {
            createdProject = try await StorageService.createProject(
                name: name.trimmingCharacters(in: .whitespaces)
            )
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func addSelected() async {
        guard let project = createdProject else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            for id in selected {
                _ = try await StorageService.updateNote(
                    id, fields: ["project_id": .string(project.id.uuidString)]
                )
            }
            finish()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func finish() {
        onFinished()
        dismiss()
    }
}
