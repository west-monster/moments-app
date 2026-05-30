import SwiftUI

enum AppTheme {
    static let background = Color(.systemBackground)
    static let cardBackground = Color(.secondarySystemBackground)
    static let accent = Color(red: 0.33, green: 0.53, blue: 1.0)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let divider = Color(.separator)

    static func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.Font.eyebrow)
            .tracking(3)
            .textCase(.uppercase)
            .foregroundStyle(accent)
    }

    // MARK: - Typography

    /// Centralized, Dynamic Type–aware type scale. Every size is derived from a
    /// semantic text style, so the whole UI scales with the user's preferred
    /// text size and stays consistent across iPhone models.
    enum Font {
        /// Hero titles (splash / feed headline).
        static let hero = SwiftUI.Font.system(.largeTitle, design: .default).weight(.black)
        /// Section eyebrow labels (e.g. "MESSAGE", "CATEGORY").
        static let eyebrow = SwiftUI.Font.system(.subheadline, design: .default).weight(.bold)
        /// Primary editorial message text.
        static let message = SwiftUI.Font.system(.title3, design: .serif).weight(.semibold)
        /// Secondary editorial / description text.
        static let body = SwiftUI.Font.system(.body, design: .serif)
        /// Field input text.
        static let field = SwiftUI.Font.system(.title3, design: .serif)
        /// Interactive chips, buttons, captions.
        static let chip = SwiftUI.Font.system(.subheadline, design: .default).weight(.medium)
        /// Uppercase metadata (dates, counts).
        static let caption = SwiftUI.Font.system(.caption, design: .default).weight(.bold)
    }
}

struct VergeGridBackground: View {
    @Environment(\.colorScheme) var colorScheme

    private var lineColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)
    }

    var body: some View {
        GeometryReader { geo in
            let columns = 5
            let spacing = geo.size.width / CGFloat(columns)
            Canvas { context, size in
                for i in 1..<columns {
                    let x = spacing * CGFloat(i)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(lineColor), lineWidth: 0.33)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
