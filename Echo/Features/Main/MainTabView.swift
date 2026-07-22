import SwiftUI

struct MainTabView: View {
    let authManager: AuthManager
    @State private var recordingManager = RecordingManager()

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                LibraryView(recordingManager: recordingManager)
                    .tabItem { Label("Library", systemImage: "list.bullet") }

                SettingsView(authManager: authManager)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }

            RecordingBarView(recordingManager: recordingManager)
                .padding(.bottom, 8)
        }
    }
}
