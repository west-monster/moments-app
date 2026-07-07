import SwiftUI
import SwiftData
import UIKit

@main
struct V_AppApp: App {
    init() {
        WatchSyncManager.shared.activate()
        Self.configureBars()
    }

    /// Solid white bottom bars instead of the iOS 26 liquid-glass material, so
    /// the tab bar / toolbar match the flat pill look on iOS 18 and 26 alike.
    private static func configureBars() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = .white
        tab.shadowColor = UIColor.black.withAlphaComponent(0.08)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let toolbar = UIToolbarAppearance()
        toolbar.configureWithOpaqueBackground()
        toolbar.backgroundColor = .white
        toolbar.shadowColor = UIColor.black.withAlphaComponent(0.08)
        UIToolbar.appearance().standardAppearance = toolbar
        UIToolbar.appearance().scrollEdgeAppearance = toolbar
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
                // Dark mode disabled for now — the whole app renders light.
                .preferredColorScheme(.light)
        }
        .modelContainer(sharedModelContainer)
    }
}
