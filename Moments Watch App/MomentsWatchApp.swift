import SwiftUI

@main
struct MomentsWatchApp: App {
    @StateObject private var store = WatchMemoryStore()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(store)
                .tint(AccentPalette.accent)
        }
    }
}
