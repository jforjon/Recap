import SwiftUI
import Supabase

struct LibraryContentView: View {
    let nav: AppNavigationModel
    let authManager: AuthManager

    enum Filter: String, CaseIterable, Hashable {
        case all = "All"
        case projects = "Projects"
        case recordings = "Recordings"
    }

    @State private var notes: [Note] = []
    @State private var projects: [ProjectWithNoteCount] = []
    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showNewProject = false
    @State private var pendingDeleteProject: ProjectWithNoteCount?

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.detailSelection) {
            Section {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Library")
                            .font(.system(size: 32, weight: .bold))
                            .tracking(-0.8)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("\(notes.count) NOTES")
                            .appTextStyle(.mono)
                            .foregroundStyle(AppColors.textFaint)
                    }
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

                if isEmptyState {
                    emptyState.recapCardRow()
                }

                // Projects
                if showsProjects {
                    ForEach(filteredProjects) { item in
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
                    ForEach(filteredNotes) { note in
                        noteRow(note)
                            .tag(AppNavigationModel.DetailSelection.note(note.id))
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
                Button {
                    showNewProject = true
                } label: {
                    Image(systemName: "folder.badge.plus")
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
            TextField("Search", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(AppColors.textPrimary)
                .tint(AppColors.accent)
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

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(searchText.isEmpty ? "Nothing here yet" : "No matches")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
            Text(searchText.isEmpty ? "Start a recording below." : "Try a different search.")
                .appTextStyle(.small)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.s6)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
    }

    private func noteRow(_ note: Note) -> some View {
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
        }
    }

    // MARK: - Filtering

    private var showsProjects: Bool { filter == .all || filter == .projects }
    private var showsRecordings: Bool { filter == .all || filter == .recordings }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredNotes: [Note] {
        guard showsRecordings else { return [] }
        guard !query.isEmpty else { return notes }
        return notes.filter { $0.title.lowercased().contains(query) }
    }

    private var filteredProjects: [ProjectWithNoteCount] {
        guard showsProjects else { return [] }
        guard !query.isEmpty else { return projects }
        return projects.filter { $0.project.name.lowercased().contains(query) }
    }

    private var isEmptyState: Bool {
        !isLoading && filteredNotes.isEmpty && filteredProjects.isEmpty
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        do {
            async let notesResult = StorageService.getStandaloneNotes()
            async let projectsResult = StorageService.getProjectsWithNoteCounts()
            notes = try await notesResult
            projects = try await projectsResult
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
                        Button("Cancel") { dismiss() }.tint(AppColors.accent)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") { finish() }.tint(AppColors.accent)
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
                Text("No recordings to add yet.")
                    .appTextStyle(.body)
                    .foregroundStyle(AppColors.neutral500)
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
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.labelWhite.opacity(0.25))
            }
            Text(note.title)
                .appTextStyle(.bodyMedium)
                .foregroundStyle(AppColors.neutral800)
        }
        .padding(Spacing.s3 + 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AppColors.accent.opacity(0.12) : AppColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isSelected ? AppColors.accent.opacity(0.55) : AppColors.separator,
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
                .tint(AppColors.accent)
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
