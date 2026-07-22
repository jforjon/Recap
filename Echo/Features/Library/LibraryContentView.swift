import SwiftUI

struct LibraryContentView: View {
    let nav: AppNavigationModel
    var onProjectsChanged: () -> Void = {}

    @State private var notes: [Note] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var isCreatingProject = false

    var body: some View {
        List {
            Section {
                if notes.isEmpty && !isLoading {
                    Text("No recordings yet. Start one below.")
                        .foregroundStyle(AppColors.neutral500)
                }
                ForEach(notes) { note in
                    Button {
                        nav.detailSelection = .note(note.id)
                    } label: {
                        noteRow(note)
                    }
                    .buttonStyle(.plain)
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

    private func load() async {
        isLoading = true
        do {
            notes = try await StorageService.getStandaloneNotes()
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
            onProjectsChanged()
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
}
