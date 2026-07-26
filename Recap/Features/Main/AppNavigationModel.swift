import Foundation
import Observation

/// Drives the 3-column NavigationSplitView. On compact width (iPhone) SwiftUI
/// automatically collapses this into a pushed single-column stack — the same
/// selection state produces both the desktop 3-panel layout and the mobile
/// single-screen flow, mirroring how the web app's layout responds to width.
@Observable
final class AppNavigationModel {
    enum SidebarSelection: Hashable {
        case library
        case project(UUID)
    }

    enum DetailSelection: Hashable {
        case note(UUID)
        case personalNotes(projectId: UUID, projectName: String)
    }

    var sidebarSelection: SidebarSelection? = .library
    var detailSelection: DetailSelection?

    /// Bumped whenever a project is created/deleted anywhere in the app so the
    /// sidebar's project list can refresh without every view needing a callback.
    var projectsVersion = 0
}
