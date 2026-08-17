import SwiftUI

struct AppShellView: View {
    let authManager: AuthManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var recordingManager = RecordingManager()
    @State private var importManager = AudioImportManager()
    @State private var nav = AppNavigationModel()
    @State private var projects: [ProjectWithNoteCount] = []

    /// Screens pushed onto the iPhone navigation stack. On compact width there
    /// is no sidebar: Library is the root and everything else pushes on top.
    private enum CompactRoute: Hashable {
        case project(UUID)
        case note(UUID)
        case personalNotes(projectId: UUID, projectName: String)
    }

    @State private var path: [CompactRoute] = []

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactStack
            } else {
                splitView
            }
        }
        // Capture takes the whole screen wherever it was started from — the
        // Library or a project — so the shell owns the presentation rather than
        // either screen. Dismissal is driven entirely by the phase: the session
        // view's own controls are what end a recording.
        .fullScreenCover(isPresented: .constant(recordingManager.phase == .recording)) {
            RecordingSessionView(recordingManager: recordingManager)
        }
    }

    /// iPad / Mac: the full 3-column layout.
    private var splitView: some View {
        NavigationSplitView {
            sidebar
        } content: {
            content
        } detail: {
            detail
        }
        .tint(AppColors.accentGraphic)
    }

    /// iPhone: Library is the home screen. Projects and notes push on top of it,
    /// so "back" always returns to the Library — there is no separate sidebar
    /// screen to land on. Project/note taps still flow through the shared nav
    /// model; the onChange adapters below turn those selections into pushes.
    private var compactStack: some View {
        NavigationStack(path: $path) {
            LibraryContentView(nav: nav, authManager: authManager,
                               importManager: importManager,
                               recordingManager: recordingManager)
                .safeAreaInset(edge: .bottom) { recordingBar }
                .navigationDestination(for: CompactRoute.self) { route in
                    switch route {
                    case .project(let id):
                        ProjectDetailView(projectId: id, recordingManager: recordingManager, nav: nav, importManager: importManager)
                    case .note(let id):
                        NoteDetailView(noteId: id, nav: nav)
                    case .personalNotes(let projectId, let projectName):
                        PersonalNotesView(projectId: projectId, projectName: projectName)
                    }
                }
        }
        .tint(AppColors.accentGraphic)
        .onChange(of: nav.sidebarSelection) { _, selection in
            if case .project(let id) = selection {
                nav.sidebarSelection = .library // reset so re-tapping re-triggers
                path.append(.project(id))
            }
        }
        .onChange(of: nav.detailSelection) { _, selection in
            switch selection {
            case .note(let id):
                nav.detailSelection = nil
                path.append(.note(id))
            case .personalNotes(let projectId, let projectName):
                nav.detailSelection = nil
                path.append(.personalNotes(projectId: projectId, projectName: projectName))
            case .none:
                break
            }
        }
    }

    /// The persistent "Start recording" bar. Attached only to the Library screen
    /// (below), so it doesn't appear on Settings, project, or note screens.
    private var recordingBar: some View {
        RecordingBarView(recordingManager: recordingManager)
            .padding(.top, Spacing.s3)
            .padding(.bottom, Spacing.s2)
            .background(
                AppColors.background
                    .overlay(AppColors.separator.frame(height: 1), alignment: .top)
                    .ignoresSafeArea(edges: .bottom)
            )
    }

    private var sidebar: some View {
        List(selection: $nav.sidebarSelection) {
            Label("Library", systemImage: "list.bullet")
                .tag(AppNavigationModel.SidebarSelection.library)

            if !projects.isEmpty {
                Section("Projects") {
                    ForEach(projects) { item in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(AppColors.categoryPanel)
                            Text(item.project.name)
                            Spacer()
                            Text("\(item.noteCount)")
                                .appTextStyle(.mono)
                                .foregroundStyle(AppColors.neutral500)
                        }
                        .tag(AppNavigationModel.SidebarSelection.project(item.project.id))
                    }
                }
            }
        }
        .recapBackground()
        .navigationTitle("recap")
        .task { await loadProjects() }
        .onChange(of: nav.projectsVersion) {
            Task { await loadProjects() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch nav.sidebarSelection {
        case .none, .library:
            LibraryContentView(nav: nav, authManager: authManager,
                               importManager: importManager,
                               recordingManager: recordingManager)
                .safeAreaInset(edge: .bottom) { recordingBar }
        case .project(let id):
            ProjectDetailView(projectId: id, recordingManager: recordingManager, nav: nav, importManager: importManager)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch nav.detailSelection {
        case .note(let id):
            NoteDetailView(noteId: id, nav: nav)
        case .personalNotes(let projectId, let projectName):
            PersonalNotesView(projectId: projectId, projectName: projectName)
        case .none:
            ContentUnavailableView("Select a recording", systemImage: "waveform")
        }
    }

    private func loadProjects() async {
        projects = (try? await StorageService.getProjectsWithNoteCounts()) ?? []
    }
}
