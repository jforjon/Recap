import SwiftUI
import Supabase

struct NoteDetailView: View {
    let noteId: UUID
    let nav: AppNavigationModel
    @Environment(\.dismiss) private var dismiss

    /// The "big parts" of a recording, surfaced as a chip navigation instead of
    /// one long scroll.
    private enum DetailTab: String, CaseIterable, Identifiable {
        case infos, transcript, notes, summary, export
        var id: String { rawValue }
        var title: String {
            switch self {
            case .infos: "Infos"
            case .transcript: "Transcript"
            case .notes: "Notes"
            case .summary: "Summary"
            case .export: "Export"
            }
        }
    }

    @State private var selectedTab: DetailTab = .infos

    @State private var note: Note?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var speakerContextDraft = ""
    @State private var isSavingSpeakerContext = false
    @State private var isEditingSpeakerContext = false
    @State private var isGeneratingSummary = false
    @State private var showDeleteConfirm = false
    @State private var showRename = false
    @State private var renameDraft = ""
    @State private var showMoveToProject = false
    @State private var projects: [ProjectWithNoteCount] = []
    @State private var showCreateProject = false
    @State private var newProjectName = ""
    @State private var isSavingProject = false

    // Export. Personal notes are fetched here too, since the export folds them in
    // alongside the summary and transcript.
    @State private var exportOptions = MarkdownExport.Options()
    @State private var personalNotes: [PersonalNote] = []

    // Audio playback
    @State private var showDeleteAudioConfirm = false
    /// Bumped when audio is deleted, to tear down and rebuild the player.
    @State private var audioVersion = 0

    var body: some View {
        Group {
            if let note {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(note.title)
                            .appTextStyle(.heading)
                            .foregroundStyle(AppColors.neutral800)

                        chipBar
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    .padding(.bottom, Spacing.sm)

                    // Two tabs manage their own height rather than sitting in the
                    // shared scroll view: Notes is a feed with its own list and
                    // pinned composer, and Transcript pins the player under a
                    // transcript that scrolls behind it.
                    switch selectedTab {
                    case .notes:
                        PersonalNotesContent(owner: .recording(noteId))
                    case .transcript:
                        transcriptSection(note)
                    default:
                        ScrollView {
                            VStack(alignment: .leading, spacing: Spacing.lg) {
                                switch selectedTab {
                                case .infos: infosSection(note)
                                case .summary: summarySection(note)
                                case .export: exportSection(note)
                                case .notes, .transcript: EmptyView()
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .recapBackground()
                    }
                }
            } else if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppColors.accentGraphic)
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
                // Actions that apply to the whole recording whatever tab you're
                // on. Deleting the audio stays on the Transcript tab, since that
                // is the only tab it affects.
                Menu {
                    AppMenuButton(title: "Rename recording", systemImage: "pencil") {
                        renameDraft = note?.title ?? ""
                        showRename = true
                    }
                    AppMenuButton(title: "Move to project", systemImage: "folder") {
                        Task { await loadProjects(); showMoveToProject = true }
                    }
                    AppMenuButton(title: "Delete recording", systemImage: "trash", role: .destructive) {
                        showDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await load() }
        .alert("Rename recording", isPresented: $showRename) {
            TextField("Title", text: $renameDraft)
            Button("Save") { Task { await rename() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete recording?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await deleteRecording() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The transcript, your notes and the summary go with it. This can't be undone.")
        }
        .alert("Delete the audio?", isPresented: $showDeleteAudioConfirm) {
            Button("Delete audio", role: .destructive) { deleteAudio() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The transcript, your notes and the summary all stay — only the recording itself is removed, freeing up space. This can't be undone.")
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

    // MARK: - Chip navigation

    private var chipBar: some View {
        SegmentedChipBar(tabs: DetailTab.allCases, title: \.title, selection: $selectedTab)
    }

    // MARK: - Sections

    @ViewBuilder
    private func infosSection(_ note: Note) -> some View {
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
    }

    @ViewBuilder
    private func transcriptSection(_ note: Note) -> some View {
        let transcript = transcriptText(note)
        if transcript.isEmpty {
            // Owns its scrolling now that this tab sits outside the shared one.
            ScrollView {
                EmptyStateView(
                    icon: "text.alignleft",
                    title: "No transcript",
                    message: "This recording doesn’t have a transcript. Transcription happens on-device while you record."
                )
                .padding()
            }
            .recapBackground()
        } else {
            SyncedTranscriptView(note: note, showDeleteAudioConfirm: $showDeleteAudioConfirm)
                // Rebuilds the player when the audio is deleted out from under it.
                .id(audioVersion)
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
                    .foregroundStyle(AppColors.accentGraphic)
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
        let summary = note.summary ?? ""
        if !summary.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("SUMMARY")
                    .appTextStyle(.label)
                    .foregroundStyle(AppColors.neutral600)

                MarkdownText(markdown: summary)

                Button(isGeneratingSummary ? "Generating…" : "Regenerate summary") {
                    Task { await generateSummary() }
                }
                .buttonStyle(.appSecondary)
                .disabled(isGeneratingSummary || transcriptText(note).isEmpty)
            }
        } else if transcriptText(note).isEmpty {
            // No transcript means nothing to summarise — name the prerequisite
            // instead of showing a button that can't run.
            EmptyStateView(
                icon: "sparkles",
                title: "Nothing to summarise yet",
                message: "This recording has no transcript, so there’s nothing for Recap to summarise."
            )
        } else {
            EmptyStateView(
                icon: "sparkles",
                title: "No summary yet",
                message: "Let Recap pull the key points out of this recording’s transcript.",
                action: .init(
                    title: isGeneratingSummary ? "Generating…" : "Generate summary",
                    systemImage: "sparkles"
                ) {
                    Task { await generateSummary() }
                }
            )
        }
    }

    private func exportSection(_ note: Note) -> some View {
        ExportTabView(
            options: $exportOptions,
            filename: MarkdownExport.filename(for: note.title),
            document: MarkdownExport.document(
                for: note,
                personalNotes: personalNotes,
                options: exportOptions
            ),
            hasSummary: !(note.summary ?? "").isEmpty,
            hasNotes: !personalNotes.isEmpty,
            hasTranscript: !transcriptText(note).isEmpty,
            hasTimings: !(note.transcriptSegments ?? []).isEmpty
        )
    }

    /// Removes only the audio file. The recording, its transcript, personal notes
    /// and summary are untouched — this is the "keep the notes, reclaim the space"
    /// escape hatch, distinct from "Delete recording" in the overflow menu.
    private func deleteAudio() {
        AudioStore.delete(noteId)
        audioVersion += 1
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
            async let personalResult = StorageService.getPersonalNotes(.recording(noteId))
            let loaded = try await StorageService.getNoteById(noteId)
            note = loaded
            speakerContextDraft = loaded.speakerContext ?? ""
            personalNotes = (try? await personalResult) ?? []

            // Covers a recording saved while offline or before a key was added:
            // it gets its title and speaker the first time it's opened after.
            if let enriched = await NoteEnricher.enrichIfNeeded(loaded) {
                note = enriched
                speakerContextDraft = enriched.speakerContext ?? ""
            }
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
            let result = try await SummaryClient.generateSummary(transcript: transcript)
            var fields: JSONObject = [
                "summary": .string(result.summary),
                "title": .string(result.title),
            ]
            if let category = result.category {
                fields["category"] = .string(category.rawValue)
            }
            // Only fills a blank: a speaker the user typed or corrected by hand
            // outranks anything a regenerated summary comes back with.
            let existingSpeaker = (note.speakerContext ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if existingSpeaker.isEmpty, let speaker = result.speakerContext {
                fields["speaker_context"] = .string(speaker)
            }
            let updated = try await StorageService.updateNote(noteId, fields: fields)
            self.note = updated
            speakerContextDraft = updated.speakerContext ?? ""
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func rename() async {
        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            note = try await StorageService.updateNote(noteId, fields: ["title": .string(title)])
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

    private func deleteRecording() async {
        do {
            try await StorageService.deleteNote(noteId)
            nav.detailSelection = nil       // clears the detail column on iPad
            nav.projectsVersion += 1         // reload the Library so the row drops
            dismiss()                        // pop back to Library on iPhone
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
