import SwiftUI
import UIKit
import Supabase

struct ProjectDetailView: View {
    let projectId: UUID
    let recordingManager: RecordingManager
    let nav: AppNavigationModel
    let importManager: AudioImportManager
    @Environment(\.dismiss) private var dismiss

    /// The "big parts" of a project, surfaced as chip navigation to match the
    /// recording detail screen.
    private enum ProjectTab: String, CaseIterable, Identifiable {
        case recordings, notes, summary, export
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recordings: "Recordings"
            case .notes: "Notes"
            case .summary: "Summary"
            case .export: "Export"
            }
        }
    }

    @State private var selectedTab: ProjectTab = .recordings

    @State private var project: Project?
    @State private var notes: [Note] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isGeneratingSummary = false
    @State private var showDeleteProjectConfirm = false
    @State private var showDeleteSummaryConfirm = false
    @State private var copiedSummary = false
    @State private var showRenameProject = false
    @State private var renameDraft = ""
    @State private var isStartingRecording = false
    @State private var showImportPicker = false

    // Export. A project export folds in each recording's own personal notes, so
    // it needs the whole account's set grouped by owner.
    @State private var exportOptions = MarkdownExport.Options()
    @State private var projectPersonalNotes: [PersonalNote] = []
    @State private var personalNotesByRecording: [UUID: [PersonalNote]] = [:]

    var body: some View {
        Group {
            if let project {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(project.name)
                            .appTextStyle(.heading)
                            .foregroundStyle(AppColors.neutral800)
                        chipBar
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    .padding(.bottom, Spacing.sm)

                    tabContent
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
        .safeAreaInset(edge: .bottom) {
            // Recording only belongs to the Recordings tab — Notes has its own
            // composer and Summary has no capture affordance. Nothing is stranded
            // by switching tabs: capture itself lives on its own full screen.
            if selectedTab == .recordings {
                recordingBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Files imported from here are filed into this project on arrival.
                    AppMenuButton(title: "Import audio file", systemImage: "square.and.arrow.down") {
                        showImportPicker = true
                    }
                    AppMenuButton(title: "Rename project", systemImage: "pencil") {
                        renameDraft = project?.name ?? ""
                        showRenameProject = true
                    }
                    // Personal notes are deleted one at a time by swiping a row,
                    // so there's no bulk action here.
                    AppMenuButton(title: "Delete project", systemImage: "trash", role: .destructive) {
                        showDeleteProjectConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        // A finished import has written a new note straight to the database.
        .onChange(of: importManager.completedVersion) { Task { await load() } }
        // A recording made here has landed. Inserted directly so the row doesn't
        // blink out as its "Saving…" placeholder is removed.
        .onChange(of: recordingManager.savedVersion) {
            if let saved = recordingManager.lastSaved, saved.projectId == projectId {
                if let index = notes.firstIndex(where: { $0.id == saved.id }) {
                    notes[index] = saved
                } else {
                    notes.insert(saved, at: 0)
                }
            }
            Task { await load() }
        }
        .audioImporter(isPresented: $showImportPicker,
                       importManager: importManager,
                       projectId: projectId)
        .alert("Rename project", isPresented: $showRenameProject) {
            TextField("Project name", text: $renameDraft)
            Button("Save") { Task { await renameProject() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete project?", isPresented: $showDeleteProjectConfirm) {
            Button("Delete", role: .destructive) { Task { await deleteProject() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the project and all its recordings. This can't be undone.")
        }
        .alert("Delete summary?", isPresented: $showDeleteSummaryConfirm) {
            Button("Delete", role: .destructive) { Task { await deleteSummary() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isRecordingInFlight: Bool {
        if case .recording = recordingManager.phase { return true }
        return false
    }

    /// Recordings made here that haven't reached the server yet.
    private var pendingUploads: [RecordingManager.PendingUpload] {
        recordingManager.pendingUploads
            .filter { $0.projectId == projectId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Persistent "Start recording" bar pinned to the bottom of the project
    /// screen — mirrors the Library bar (including the language selector), but
    /// files recordings under this project.
    private var recordingBar: some View {
        RecordingBarView(recordingManager: recordingManager, projectId: projectId)
            .padding(.top, Spacing.s3)
            .padding(.bottom, Spacing.s2)
            .background(
                AppColors.background
                    .overlay(AppColors.separator.frame(height: 1), alignment: .top)
                    .ignoresSafeArea(edges: .bottom)
            )
    }

    // MARK: - Chip navigation

    private var chipBar: some View {
        SegmentedChipBar(tabs: ProjectTab.allCases, title: \.title, selection: $selectedTab)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .recordings:
            recordingsTab
        case .notes:
            PersonalNotesContent(owner: .project(projectId))
        case .summary:
            ScrollView { summaryTab.padding() }
        case .export:
            ScrollView { exportTab.padding() }
                .recapBackground()
        }
    }

    // MARK: - Sections

    private var recordingsTab: some View {
        // Tapping a row sets the shared navigation model, which becomes a push on
        // compact (iPhone) and a detail-column swap on regular width (iPad).
        List {
            Section {
                if notes.isEmpty && !isLoading {
                    EmptyStateView(
                        icon: "waveform",
                        title: "No recordings yet",
                        message: "Record straight into this project, or add existing recordings from your Library.",
                        action: isRecordingInFlight ? nil : .init(
                            title: isStartingRecording ? "Starting…" : "Start recording",
                            systemImage: "mic.fill"
                        ) {
                            Task { await startRecording() }
                        }
                    )
                    .recapCardRow()
                }
                ForEach(pendingUploads) { upload in
                    PendingRecordingRow(upload: upload)
                }
                ForEach(importManager.inFlight) { progress in
                    ImportProgressRow(progress: progress) {
                        importManager.dismiss(progress.id)
                    }
                }
                ForEach(notes) { note in
                    Button {
                        nav.detailSelection = .note(note.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let category = note.category {
                                AppChip(text: category.displayText, dotColor: category.dotColor)
                            }
                            Text(note.title)
                                .appTextStyle(.bodyMedium)
                                .foregroundStyle(AppColors.neutral800)
                        }
                    }
                    .buttonStyle(.plain)
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
        }
        .listStyle(.plain)
        .recapBackground()
    }

    @ViewBuilder
    private var exportTab: some View {
        if let project {
            ExportTabView(
                options: $exportOptions,
                filename: MarkdownExport.filename(for: project.name),
                document: MarkdownExport.document(
                    for: project,
                    recordings: notes,
                    projectNotes: projectPersonalNotes,
                    notesByRecording: personalNotesByRecording,
                    options: exportOptions
                ),
                hasSummary: !(project.notes ?? "").isEmpty
                    || notes.contains { !($0.summary ?? "").isEmpty },
                hasNotes: !projectPersonalNotes.isEmpty || !personalNotesByRecording.isEmpty,
                hasTranscript: notes.contains { !($0.transcript ?? "").isEmpty },
                hasTimings: notes.contains { !($0.transcriptSegments ?? []).isEmpty }
            )
        }
    }

    @ViewBuilder
    private var summaryTab: some View {
        if let summary = project?.notes, !summary.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("SUMMARY")
                    .appTextStyle(.label)
                    .foregroundStyle(AppColors.neutral600)

                MarkdownText(markdown: summary)

                Button(isGeneratingSummary ? "Generating…" : "Update summary") {
                    Task { await generateSummary() }
                }
                .buttonStyle(.appSecondary)
                .disabled(isGeneratingSummary || notes.isEmpty)

                HStack(spacing: Spacing.s5) {
                    Button(copiedSummary ? "Copied" : "Copy summary") {
                        UIPasteboard.general.string = summary
                        copiedSummary = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedSummary = false
                        }
                    }
                    .buttonStyle(.appSecondarySmall)

                    Button("Delete summary") {
                        showDeleteSummaryConfirm = true
                    }
                    .buttonStyle(.appDestructiveSmall)
                }
                .padding(.top, Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if notes.isEmpty {
            // Nothing to summarise yet — point at the real prerequisite rather
            // than offering a button that would be disabled.
            EmptyStateView(
                icon: "sparkles",
                title: "Nothing to summarise yet",
                message: "Add a recording to this project first, then Recap can pull the key points together."
            )
        } else {
            EmptyStateView(
                icon: "sparkles",
                title: "No summary yet",
                message: "Generate an AI summary across this project’s \(notes.count) recording\(notes.count == 1 ? "" : "s").",
                action: .init(
                    title: isGeneratingSummary ? "Generating…" : "Generate summary",
                    systemImage: "sparkles"
                ) {
                    Task { await generateSummary() }
                }
            )
        }
    }

    private var loadErrorState: some View {
        VStack(spacing: Spacing.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(AppColors.textTertiary)
            Text("This project couldn't be loaded.")
                .appTextStyle(.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await load() } }
                .buttonStyle(.appSecondary)
                .frame(maxWidth: 200)
        }
        .padding(Spacing.s6)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        do {
            async let projectResult = StorageService.getProjectById(projectId)
            async let notesResult = StorageService.getNotesByProjectId(projectId)
            async let personalResult = StorageService.getAllPersonalNotes()
            project = try await projectResult
            notes = try await notesResult

            // Export-only, so a failure here shouldn't take the whole screen down.
            let personal = (try? await personalResult) ?? []
            projectPersonalNotes = personal.filter { $0.projectId == projectId }
            let recordingIds = Set(notes.map(\.id))
            personalNotesByRecording = Dictionary(
                grouping: personal.filter { $0.noteId.map(recordingIds.contains) ?? false }
            ) { $0.noteId! }
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func renameProject() async {
        let name = renameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            project = try await StorageService.updateProject(projectId, fields: ["name": .string(name)])
            nav.projectsVersion += 1
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func generateSummary() async {
        isGeneratingSummary = true
        defer { isGeneratingSummary = false }
        do {
            guard let project else { return }
            let summary = try await ProjectSummaryClient.generateProjectSummary(
                projectName: project.name,
                notes: notes
            )
            self.project = try await StorageService.updateProject(projectId, fields: ["notes": .string(summary)])
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

    /// Starts a project recording from the empty-state CTA, using the same
    /// language resolution as the bar (chosen default, else first configured).
    private func startRecording() async {
        guard !isStartingRecording else { return }
        isStartingRecording = true
        defer { isStartingRecording = false }

        let languages = SpokenLanguageStore.selected
        let language = languages.isEmpty
            ? nil
            : (SpokenLanguageStore.defaultLanguage ?? languages.first)
        do {
            try await recordingManager.startRecording(projectId: projectId, language: language)
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
            nav.sidebarSelection = .library  // swaps content back to Library on iPad
            nav.projectsVersion += 1          // reload the Library project list
            dismiss()                         // pop back to Library on iPhone
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

}
