import SwiftUI
import UIKit

/// Fixed palette, compiled into both the app and the widget. No user
/// selection: mint carries the accent on dark surfaces, bright blue on light
/// ones (mint has too little contrast on white), and the highlight block is
/// always bright blue.
enum AccentPalette {
    /// Vivid blue for buttons, icons, and pills.
    static let brightBlue = Color(red: 0.11, green: 0.45, blue: 0.95)
    /// App/widget background (white).
    static let appBackground = Color.white
    static let mint = Color(red: 0.31, green: 1.0, blue: 0.77)
    /// Dark ink for text sitting on mint.
    static let inkOnMint = Color(red: 0.02, green: 0.2, blue: 0.17)

    /// Accent for icons, eyebrows, dividers, and pill buttons: mint on dark
    /// surfaces, bright blue on light ones. watchOS is always dark and has
    /// no trait-based dynamic `UIColor`, so it resolves to mint directly.
    static let accent: Color = {
        #if os(watchOS)
        mint
        #else
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(mint) : UIColor(brightBlue)
        })
        #endif
    }()

    /// Text/icon color on top of `accent`.
    static let onAccent: Color = {
        #if os(watchOS)
        inkOnMint
        #else
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(inkOnMint) : UIColor.white
        })
        #endif
    }()

    /// Highlight block — bright blue with white ink.
    static let highlight = brightBlue
    static let onHighlight = Color.white
}
