import Foundation
import SwiftData

/// The app's one `ModelContainer`: a SwiftData store on the device, mirrored to
/// the user's private CloudKit database so it survives a lost phone and appears
/// on their other devices. There is no account and no server — the user's
/// iCloud account is the only identity, and the developer can't see any of it.
enum RecapStore {
    static let cloudKitContainer = "iCloud.com.jonchambers.recap"

    static let container: ModelContainer = makeContainer()

    private static let schema = Schema([
        NoteRecord.self,
        ProjectRecord.self,
        PersonalNoteRecord.self,
    ])

    private static func makeContainer() -> ModelContainer {
        #if DEBUG
        if DemoMode.isOn { return DemoStore.makeContainer(schema: schema) }
        #endif

        do {
            let synced = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudKitContainer))
            return try ModelContainer(for: schema, configurations: synced)
        } catch {
            // CloudKit couldn't be set up — most likely a build signed without
            // the entitlement. Same store file, just not mirrored: the app keeps
            // working and nothing written here is lost when sync comes back.
            print("RecapStore: CloudKit unavailable, using a local-only store — \(error)")
        }

        do {
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Could not open the recap store: \(error)")
        }
    }
}
