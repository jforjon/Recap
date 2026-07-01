import SwiftUI

/// Wireframe only — replace with the real Library/Settings navigation once those screens exist.
struct MainTabView: View {
    let authManager: AuthManager

    var body: some View {
        TabView {
            Text("Library — coming soon")
                .tabItem { Label("Library", systemImage: "list.bullet") }

            VStack(spacing: 16) {
                Text("Settings — coming soon")
                Button("Sign out") {
                    Task { try? await authManager.signOut() }
                }
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
