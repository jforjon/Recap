import SwiftUI

@main
struct RecapApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // The app is dark-mode only for now, so pin it regardless of the
                // device's system appearance.
                .preferredColorScheme(.dark)
        }
    }
}
