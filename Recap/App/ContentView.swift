import SwiftUI

struct ContentView: View {
    @State private var authManager = AuthManager()

    var body: some View {
        switch authManager.state {
        case .loading:
            ProgressView()
        case .signedOut:
            SignInView(authManager: authManager)
        case .signedIn:
            AppShellView(authManager: authManager)
        }
    }
}

#Preview {
    ContentView()
}
