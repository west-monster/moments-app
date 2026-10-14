import SwiftUI
import UIKit

/// Fixed palette, compiled into the app, the widget and the watch app. No user
/// selection: bright blue carries the accent on iOS, which renders light only,
/// and mint on watchOS, which is always dark (mint has too little contrast on
/// white).
enum AccentPalette {
    /// Vivid blue for buttons, icons, and pills.
    static let brightBlue = Color(red: 0.11, green: 0.45, blue: 0.95)
    /// App/widget background (white).
    static let appBackground = Color.white
    static let mint = Color(red: 0.31, green: 1.0, blue: 0.77)
    /// Dark ink for text sitting on mint.
    static let inkOnMint = Color(red: 0.02, green: 0.2, blue: 0.17)

    /// Accent for icons, eyebrows, dividers, and pill buttons: mint on watchOS,
    /// which is always a dark surface, bright blue everywhere else.
    ///
    /// Not a trait-based dynamic `UIColor`: the iOS app renders light only
    /// (`V_AppApp` pins `.preferredColorScheme(.light)`) so the dark branch
    /// could never resolve, and a static color is also safe to read from the
    /// background renderers — a dynamic one has no trait collection to resolve
    /// against off the main thread.
    static let accent: Color = {
        #if os(watchOS)
        mint
        #else
        brightBlue
        #endif
    }()

    /// Text/icon color on top of `accent`.
    static let onAccent: Color = {
        #if os(watchOS)
        inkOnMint
        #else
        .white
        #endif
    }()
}
