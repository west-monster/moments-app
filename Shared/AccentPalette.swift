import SwiftUI
import UIKit

/// Fixed Verge-inspired palette, compiled into both the app and the widget.
/// No user selection: mint carries the accent on dark surfaces, electric
/// purple on light ones (mint has too little contrast on white), and the
/// headline highlight block is always electric purple.
enum AccentPalette {
    static let electricPurple = Color(red: 0.32, green: 0.0, blue: 1.0)
    static let mint = Color(red: 0.31, green: 1.0, blue: 0.77)
    /// Dark ink for text sitting on mint.
    static let inkOnMint = Color(red: 0.02, green: 0.2, blue: 0.17)

    /// Accent for icons, eyebrows, dividers, and pill buttons: mint on dark
    /// surfaces, electric purple on light ones. watchOS is always dark and has
    /// no trait-based dynamic `UIColor`, so it resolves to mint directly.
    static let accent: Color = {
        #if os(watchOS)
        mint
        #else
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(mint) : UIColor(electricPurple)
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

    /// Headline highlight block — electric purple with white ink in both
    /// modes, the Verge cover look.
    static let highlight = electricPurple
    static let onHighlight = Color.white
}
