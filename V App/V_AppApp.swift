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
    ///
    /// Page dots are set here too: `UIPageControl.appearance()` is process-wide
    /// state, and doing it from `MemoryDetailView.init` re-applied it on every
    /// body evaluation of a view that only happens to contain a pager.
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

        // Native page dots tinted with the app accent.
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(AppTheme.accent)
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(AppTheme.accent).withAlphaComponent(0.25)
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Memory.self])
        let configuration = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Ask the configuration where the store actually is instead of
            // guessing: with App Groups entitlements SwiftData puts it in the
            // group container, not the app's own Application Support, so the
            // old hardcoded path deleted nothing and this retry failed too.
            removeStore(at: configuration.url)
            if let recovered = try? ModelContainer(for: schema, configurations: [configuration]) {
                return recovered
            }
            // Last resort: run from memory rather than crash on every launch.
            // `ContentView` repopulates the library from `memories.json`, and
            // keeps writing that snapshot, so the app stays usable.
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
            } catch {
                fatalError("Failed to create ModelContainer even in-memory: \(error)")
            }
        }
    }()

    /// Deletes a SwiftData store together with its SQLite sidecar files —
    /// leaving `-wal`/`-shm` behind can resurrect the broken state.
    private static func removeStore(at url: URL) {
        let directory = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        for fileName in [name, name + "-wal", name + "-shm"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Dark mode disabled for now — the whole app renders light.
                .preferredColorScheme(.light)
        }
        .modelContainer(sharedModelContainer)
    }
}
