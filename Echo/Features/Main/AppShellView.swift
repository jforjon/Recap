import SwiftUI

struct AppShellView: View {
    let authManager: AuthManager
    @State private var recordingManager = RecordingManager()
    @State private var nav = AppNavigationModel()
    @State private var projects: [ProjectWithNoteCount] = []

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            content
        } detail: {
            detail
        }
    }

    private var sidebar: some View {
        List(selection: $nav.sidebarSelection) {
            Label("Library", systemImage: "list.bullet")
                .tag(AppNavigationModel.SidebarSelection.library)
            Label("Settings", systemImage: "gearshape")
                .tag(AppNavigationModel.SidebarSelection.settings)

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
        .navigationTitle("echo")
        .task { await loadProjects() }
        .safeAreaInset(edge: .bottom) {
            RecordingBarView(recordingManager: recordingManager)
                .padding(.bottom, Spacing.s2)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch nav.sidebarSelection {
        case .none, .library:
            LibraryContentView(nav: nav, onProjectsChanged: { Task { await loadProjects() } })
        case .settings:
            SettingsView(authManager: authManager)
        case .project(let id):
            ProjectDetailView(projectId: id, recordingManager: recordingManager, nav: nav)
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
