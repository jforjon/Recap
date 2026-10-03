import SwiftUI

/// There is no sign-in: the app opens straight into the shell. The user's
/// iCloud account is the only identity, and the store syncs through it.
struct ContentView: View {
    var body: some View {
        AppShellView()
    }
}

#Preview {
    ContentView()
}
