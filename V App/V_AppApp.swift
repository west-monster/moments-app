import SwiftUI
import SwiftData

@main
struct V_AppApp: App {
    @AppStorage("appearance") private var appearance = AppTheme.Appearance.system

    init() {
        WatchSyncManager.shared.activate()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Memory.self])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: storeURL)
            do {
                return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
            } catch {
                fatalError("Failed to create ModelContainer even in-memory: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
