import SwiftUI

struct LibraryView: View {
    let recordingManager: RecordingManager

    @State private var notes: [Note] = []
    @State private var projects: [ProjectWithNoteCount] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var isCreatingProject = false

    var body: some View {
        NavigationStack {
            List {
                if !projects.isEmpty {
                    Section("Projects") {
                        ForEach(projects) { item in
                            NavigationLink(value: item.project) {
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.orange)
                                    Text(item.project.name)
                                    Spacer()
                                    Text("\(item.noteCount)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await deleteProject(item.project.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section("Recordings") {
                    if notes.isEmpty && !isLoading {
                        Text("No recordings yet. Start one below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(notes) { note in
                        NavigationLink(value: note) {
                            noteRow(note)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await deleteNote(note.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Section {
                    Button("New project") {
                        showNewProject = true
                    }
                    .buttonStyle(.appSecondary)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, Spacing.xs)
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: Note.self) { note in
                NoteDetailView(noteId: note.id)
            }
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(projectId: project.id, recordingManager: recordingManager)
            }
            .refreshable { await load() }
            .task { await load() }
            .alert("New project", isPresented: $showNewProject) {
                TextField("Project name", text: $newProjectName)
                Button("Cancel", role: .cancel) { newProjectName = "" }
                Button("Create") { Task { await createProject() } }
                    .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty || isCreatingProject)
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
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
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(note.title)
                .font(.body.weight(.medium))
        }
    }

    private func load() async {
        isLoading = true
        do {
            async let notesResult = StorageService.getStandaloneNotes()
            async let projectsResult = StorageService.getProjectsWithNoteCounts()
            notes = try await notesResult
            projects = try await projectsResult
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func createProject() async {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreatingProject = true
        defer { isCreatingProject = false }
        do {
            _ = try await StorageService.createProject(name: name)
            newProjectName = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteNote(_ id: UUID) async {
        notes.removeAll { $0.id == id }
        do {
            try await StorageService.deleteNote(id)
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    private func deleteProject(_ id: UUID) async {
        projects.removeAll { $0.project.id == id }
        do {
            try await StorageService.deleteProject(id)
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }
}
