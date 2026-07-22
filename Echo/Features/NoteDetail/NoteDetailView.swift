import SwiftUI
import Supabase

struct NoteDetailView: View {
    let noteId: UUID
    let nav: AppNavigationModel

    @State private var note: Note?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var speakerContextDraft = ""
    @State private var isSavingSpeakerContext = false
    @State private var showDeleteConfirm = false
    @State private var showMoveToProject = false
    @State private var projects: [ProjectWithNoteCount] = []

    var body: some View {
        ScrollView {
            if let note {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text(note.title)
                        .appTextStyle(.heading)
                        .foregroundStyle(AppColors.neutral800)

                    HStack {
                        Picker("Category", selection: categoryBinding) {
                            Text("Other").tag(NoteCategory?.none)
                            Text("Talk").tag(NoteCategory?.some(.talk))
                            Text("Training").tag(NoteCategory?.some(.training))
                            Text("Panel").tag(NoteCategory?.some(.panel))
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        Text(formatShortDate(note.createdAt))
                            .appTextStyle(.mono)
                            .foregroundStyle(AppColors.neutral500)
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("SPEAKER & CONTEXT")
                            .appTextStyle(.label)
                            .foregroundStyle(AppColors.neutral600)
                        AppTextField(title: "Speaker, role, event context…", text: $speakerContextDraft)
                        Button(isSavingSpeakerContext ? "Saving…" : "Save") {
                            Task { await saveSpeakerContext() }
                        }
                        .buttonStyle(.appSecondary)
                        .disabled(isSavingSpeakerContext)
                    }

                    Divider().background(AppColors.neutral300)

                    Text(note.summary)
                        .appTextStyle(.body)
                        .foregroundStyle(AppColors.neutral800)
                }
                .padding()
            } else if isLoading {
                ProgressView()
                    .padding()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await loadProjects(); showMoveToProject = true }
                    } label: {
                        Label("Move to project", systemImage: "folder")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete note", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await load() }
        .confirmationDialog("Delete this note? This cannot be undone.", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteNote() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showMoveToProject) {
            NavigationStack {
                List(projects) { item in
                    Button(item.project.name) {
                        Task { await moveToProject(item.project.id) }
                    }
                }
                .navigationTitle("Move to project")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showMoveToProject = false }
                    }
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var categoryBinding: Binding<NoteCategory?> {
        Binding(
            get: { note?.category },
            set: { newValue in
                Task { await updateCategory(newValue) }
            }
        )
    }

    private func load() async {
        isLoading = true
        do {
            let loaded = try await StorageService.getNoteById(noteId)
            note = loaded
            speakerContextDraft = loaded.speakerContext ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadProjects() async {
        do {
            projects = try await StorageService.getProjectsWithNoteCounts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateCategory(_ category: NoteCategory?) async {
        do {
            let fields: JSONObject = ["category": category.map { .string($0.rawValue) } ?? .null]
            note = try await StorageService.updateNote(noteId, fields: fields)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveSpeakerContext() async {
        isSavingSpeakerContext = true
        defer { isSavingSpeakerContext = false }
        do {
            let trimmed = speakerContextDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let fields: JSONObject = ["speaker_context": trimmed.isEmpty ? .null : .string(trimmed)]
            note = try await StorageService.updateNote(noteId, fields: fields)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveToProject(_ projectId: UUID) async {
        do {
            note = try await StorageService.updateNote(noteId, fields: ["project_id": .string(projectId.uuidString)])
            showMoveToProject = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteNote() async {
        do {
            try await StorageService.deleteNote(noteId)
            nav.detailSelection = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
