import SwiftUI

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
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
        .recapBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .confirmationDialog(
            "Delete this project? Its recordings stay in your Library; personal notes are deleted.",
            isPresented: Binding(
                get: { pendingDeleteProject != nil },
                set: { if !$0 { pendingDeleteProject = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let project = pendingDeleteProject {
                    Task { await deleteProject(project) }
                }
                pendingDeleteProject = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteProject = nil }
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
