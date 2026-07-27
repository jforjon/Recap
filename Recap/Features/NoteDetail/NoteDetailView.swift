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
    @State private var isEditingSpeakerContext = false
    @State private var isGeneratingSummary = false
    @State private var showDeleteConfirm = false
    @State private var showMoveToProject = false
    @State private var projects: [ProjectWithNoteCount] = []
    @State private var showCreateProject = false
    @State private var newProjectName = ""
    @State private var isSavingProject = false

    var body: some View {
        Group {
            if let note {
                ScrollView {
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

                    speakerSection(note)

                    Divider().background(AppColors.neutral300)

                    summarySection(note)

                    Divider().background(AppColors.neutral300)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("TRANSCRIPT")
                            .appTextStyle(.label)
                            .foregroundStyle(AppColors.neutral600)
                        let transcript = transcriptText(note)
                        Text(transcript.isEmpty ? "No transcript." : transcript)
                            .appTextStyle(.body)
                            .foregroundStyle(transcript.isEmpty ? AppColors.neutral500 : AppColors.neutral800)
                            .textSelection(.enabled)
                    }
                }
                .padding()
                }
                .recapBackground()
            } else if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppColors.accent)
            } else {
                loadErrorState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
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
                    .tint(AppColors.textPrimary)
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete note", systemImage: "trash")
                    }
                    .tint(AppColors.destructive)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await load() }
        .alert("Delete note?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await deleteNote() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .sheet(isPresented: $showMoveToProject, onDismiss: resetMoveToProjectState) {
            NavigationStack {
                Group {
                    if projects.isEmpty || showCreateProject {
                        createProjectForm
                    } else {
                        existingProjectsList
                    }
                }
                .navigationTitle(projects.isEmpty || showCreateProject ? "New project" : "Add to project")
                .navigationBarTitleDisplayMode(.inline)
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

    private var existingProjectsList: some View {
        List {
            ForEach(projects) { item in
                Button(item.project.name) {
                    Task { await moveToProject(item.project.id) }
                }
            }
            Button {
                showCreateProject = true
            } label: {
                Label("New project", systemImage: "plus")
            }
            .foregroundStyle(AppColors.neutral500)
        }
    }

    private var createProjectForm: some View {
        Form {
            TextField("Project name", text: $newProjectName)
                .disabled(isSavingProject)

            HStack {
                if !projects.isEmpty {
                    Button("Back") {
                        showCreateProject = false
                        newProjectName = ""
                    }
                    .disabled(isSavingProject)
                }
                Spacer()
                Button(isSavingProject ? "Creating…" : "Create") {
                    Task { await createAndAssignProject() }
                }
                .buttonStyle(.appPrimary)
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty || isSavingProject)
            }
        }
    }

    private func resetMoveToProjectState() {
        showCreateProject = false
        newProjectName = ""
    }

    /// Read mode by default: shows the saved speaker & context with an Edit/Add
    /// affordance; tapping it reveals the field + Save/Cancel.
    @ViewBuilder
    private func speakerSection(_ note: Note) -> some View {
        let context = (note.speakerContext ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("SPEAKER & CONTEXT")
                    .appTextStyle(.label)
                    .foregroundStyle(AppColors.neutral600)
                Spacer()
                if !isEditingSpeakerContext {
                    Button(context.isEmpty ? "Add" : "Edit") {
                        speakerContextDraft = context
                        isEditingSpeakerContext = true
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                }
            }

            if isEditingSpeakerContext {
                AppTextArea(title: "Speaker, role, event context…", text: $speakerContextDraft)
                HStack(spacing: Spacing.s5) {
                    Spacer()
                    Button("Cancel") {
                        speakerContextDraft = context
                        isEditingSpeakerContext = false
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)

                    Button(isSavingSpeakerContext ? "Saving…" : "Save") {
                        Task { await saveSpeakerContext() }
                    }
                    .buttonStyle(.appSecondarySmall)
                    .disabled(isSavingSpeakerContext)
                }
            } else {
                Text(context.isEmpty ? "No speaker or context added." : context)
                    .appTextStyle(.body)
                    .foregroundStyle(context.isEmpty ? AppColors.neutral500 : AppColors.neutral800)
            }
        }
    }

    @ViewBuilder
    private func summarySection(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("SUMMARY")
                .appTextStyle(.label)
                .foregroundStyle(AppColors.neutral600)

            let summary = note.summary ?? ""
            if !summary.isEmpty {
                MarkdownText(markdown: summary)
            } else {
                Text("No summary yet. Generate one with AI when you want it.")
                    .appTextStyle(.body)
                    .foregroundStyle(AppColors.neutral500)
            }

            Button(isGeneratingSummary
                   ? "Generating…"
                   : (summary.isEmpty ? "Generate summary" : "Regenerate summary")) {
                Task { await generateSummary() }
            }
            .buttonStyle(.appSecondary)
            .disabled(isGeneratingSummary || transcriptText(note).isEmpty)
        }
    }

    private func transcriptText(_ note: Note) -> String {
        (note.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var loadErrorState: some View {
        VStack(spacing: Spacing.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(AppColors.textTertiary)
            Text("This recording couldn't be loaded.")
                .appTextStyle(.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await load() } }
                .buttonStyle(.appSecondary)
                .frame(maxWidth: 200)
        }
        .padding(Spacing.s6)
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
        errorMessage = nil
        // `defer` guarantees the spinner is cleared even if the request is
        // cancelled (SwiftUI restarting the .task) — otherwise it spins forever.
        defer { isLoading = false }
        do {
            let loaded = try await StorageService.getNoteById(noteId)
            note = loaded
            speakerContextDraft = loaded.speakerContext ?? ""
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadProjects() async {
        do {
            projects = try await StorageService.getProjectsWithNoteCounts()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func updateCategory(_ category: NoteCategory?) async {
        do {
            let fields: JSONObject = ["category": category.map { .string($0.rawValue) } ?? .null]
            note = try await StorageService.updateNote(noteId, fields: fields)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func generateSummary() async {
        guard let note else { return }
        let transcript = transcriptText(note)
        guard !transcript.isEmpty else {
            errorMessage = "There's no transcript to summarise yet."
            return
        }
        isGeneratingSummary = true
        defer { isGeneratingSummary = false }
        do {
            let token = try await SupabaseService.client.auth.session.accessToken
            let result = try await SummaryClient.generateSummary(transcript: transcript, accessToken: token)
            var fields: JSONObject = [
                "summary": .string(result.summary),
                "title": .string(result.title),
            ]
            if let category = result.category {
                fields["category"] = .string(category.rawValue)
            }
            self.note = try await StorageService.updateNote(noteId, fields: fields)
        } catch {
            if error.isCancellation { return }
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
            isEditingSpeakerContext = false
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func moveToProject(_ projectId: UUID) async {
        do {
            note = try await StorageService.updateNote(noteId, fields: ["project_id": .string(projectId.uuidString)])
            showMoveToProject = false
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func createAndAssignProject() async {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSavingProject = true
        defer { isSavingProject = false }
        do {
            let project = try await StorageService.createProject(name: name)
            note = try await StorageService.updateNote(noteId, fields: ["project_id": .string(project.id.uuidString)])
            nav.projectsVersion += 1
            showMoveToProject = false
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func deleteNote() async {
        do {
            try await StorageService.deleteNote(noteId)
            nav.detailSelection = nil
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
