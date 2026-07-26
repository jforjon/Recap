import SwiftUI
import UIKit
import Supabase

struct ProjectDetailView: View {
    let projectId: UUID
    let recordingManager: RecordingManager
    let nav: AppNavigationModel

    @State private var project: Project?
    @State private var notes: [Note] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isGeneratingSummary = false
    @State private var isStartingRecording = false
    @State private var showDeleteProjectConfirm = false
    @State private var showDeleteSummaryConfirm = false
    @State private var showDeletePersonalNotesConfirm = false
    @State private var copiedSummary = false

    var body: some View {
        // Bind the list selection to the shared navigation model so tapping a row
        // becomes a real NavigationSplitView navigation — a push on compact
        // (iPhone) and a detail-column swap on regular width (iPad). A plain
        // Button that only mutated `detailSelection` never pushed on iPhone.
        @Bindable var nav = nav
        List(selection: $nav.detailSelection) {
            Section("Recordings") {
                if notes.isEmpty && !isLoading {
                    Text("No recordings yet.")
                        .foregroundStyle(AppColors.neutral500)
                }
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        if let category = note.category {
                            AppChip(text: category.displayText, dotColor: category.dotColor)
                        }
                        Text(note.title)
                            .appTextStyle(.bodyMedium)
                            .foregroundStyle(AppColors.neutral800)
                    }
                    .tag(AppNavigationModel.DetailSelection.note(note.id))
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task { await removeFromProject(note.id) }
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                        .tint(AppColors.warning500)
                    }
                }
            }

            Section("Personal notes") {
                Text("Open personal notes")
                    .tag(AppNavigationModel.DetailSelection.personalNotes(projectId: projectId, projectName: project?.name ?? ""))
                Button("Delete all personal notes", role: .destructive) {
                    showDeletePersonalNotesConfirm = true
                }
            }

            Section {
                if let summary = project?.notes, !summary.isEmpty {
                    Text(summary)
                        .appTextStyle(.body)
                        .foregroundStyle(AppColors.neutral800)
                } else {
                    Text("No summary yet.")
                        .foregroundStyle(AppColors.neutral500)
                }
                Button(isGeneratingSummary ? "Generating…" : (project?.notes?.isEmpty == false ? "Update summary" : "Generate summary")) {
                    Task { await generateSummary() }
                }
                .buttonStyle(.appSecondary)
                .disabled(isGeneratingSummary || notes.isEmpty)

                if let summary = project?.notes, !summary.isEmpty {
                    Button(copiedSummary ? "Copied" : "Copy summary") {
                        UIPasteboard.general.string = summary
                        copiedSummary = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedSummary = false
                        }
                    }
                    Button("Delete summary", role: .destructive) {
                        showDeleteSummaryConfirm = true
                    }
                }
            } header: {
                Text("Summary")
            }

            Section {
                Button(isStartingRecording ? "Starting…" : "Start recording") {
                    Task { await startRecording() }
                }
                .buttonStyle(.appPrimary)
                .disabled(isStartingRecording || recordingManager.phase == .recording)
                .listRowInsets(EdgeInsets())
                .padding(.vertical, Spacing.xs)
            }
        }
        .recapBackground()
        .navigationTitle(project?.name ?? "Project")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showDeleteProjectConfirm = true
                    } label: {
                        Label("Delete project", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "Delete this project and all its recordings? This cannot be undone.",
            isPresented: $showDeleteProjectConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await deleteProject() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete the summary?",
            isPresented: $showDeleteSummaryConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await deleteSummary() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete all personal notes?",
            isPresented: $showDeletePersonalNotesConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await deleteAllPersonalNotes() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        isLoading = true
        do {
            async let projectResult = StorageService.getProjectById(projectId)
            async let notesResult = StorageService.getNotesByProjectId(projectId)
            project = try await projectResult
            notes = try await notesResult
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func generateSummary() async {
        isGeneratingSummary = true
        defer { isGeneratingSummary = false }
        do {
            let token = try await SupabaseService.client.auth.session.accessToken
            let summary = try await ProjectSummaryClient.generateProjectSummary(projectId: projectId, accessToken: token)
            project = try await StorageService.updateProject(projectId, fields: ["notes": .string(summary)])
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSummary() async {
        do {
            project = try await StorageService.updateProject(projectId, fields: ["notes": .null])
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAllPersonalNotes() async {
        do {
            try await StorageService.deleteAllPersonalNotes(projectId: projectId)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func removeFromProject(_ noteId: UUID) async {
        notes.removeAll { $0.id == noteId }
        do {
            _ = try await StorageService.updateNote(noteId, fields: ["project_id": .null])
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
            await load()
        }
    }

    private func deleteProject() async {
        do {
            try await StorageService.deleteProject(projectId)
            nav.detailSelection = nil
            nav.sidebarSelection = .library
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func startRecording() async {
        isStartingRecording = true
        defer { isStartingRecording = false }
        do {
            try await recordingManager.startRecording(
                projectId: projectId,
                language: SpokenLanguageStore.defaultLanguage
            )
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
