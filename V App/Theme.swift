import SwiftUI
import UIKit

enum AppTheme {
    /// White app background (light-mode only for now).
    static let background = AccentPalette.appBackground
    static let cardBackground = Color(.secondarySystemBackground)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let divider = Color(.separator)

    /// Fixed editorial accent: mint on dark, bright blue on light.
    static let accent = AccentPalette.accent
    /// Text/icon color for content sitting on the accent (chips, pills).
    static let onAccent = AccentPalette.onAccent
    /// Headline highlight block and its ink.
    static let highlight = AccentPalette.highlight
    static let onHighlight = AccentPalette.onHighlight

    /// Accent for UIKit-based renderers (share card, PDF export). Those
    /// always draw on white, so the light-mode blue is used.
    static var accentUIColor: UIColor { UIColor(AccentPalette.brightBlue) }

    // MARK: - Theme options

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }

        var icon: String {
            switch self {
            case .system: "iphone"
            case .light: "sun.max.fill"
            case .dark: "moon.fill"
            }
        }

        var label: String {
            switch self {
            case .system: String(localized: "theme.system", defaultValue: "System")
            case .light: String(localized: "theme.light", defaultValue: "Light")
            case .dark: String(localized: "theme.dark", defaultValue: "Dark")
            }
        }
    }

    /// Discreet secondary-gray subtitle (replaces the old wide-tracked blue
    /// kicker, which read as a web pattern rather than iOS).
    static func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .default).weight(.medium))
            .foregroundStyle(textSecondary)
    }

    // MARK: - Layout

    /// Readable-width caps so the single-column layout stays comfortable on
    /// iPad and Mac instead of stretching edge to edge.
    enum Layout {
        /// Feed, timeline, and detail content.
        static let contentMaxWidth: CGFloat = 640
        /// Forms and option sheets.
        static let formMaxWidth: CGFloat = 560
    }

    // MARK: - Typography

    /// Centralized, Dynamic Type–aware type scale. Every size is derived from a
    /// semantic text style, so the whole UI scales with the user's preferred
    /// text size and stays consistent across iPhone models.
    ///
    /// One family throughout (SF Pro / system default); hierarchy comes from
    /// weight and size, not from mixing serif/monospace faces.
    enum Font {
        /// Hero titles (splash / feed headline).
        static let hero = SwiftUI.Font.system(.largeTitle, design: .default).weight(.bold)
        /// Section labels (e.g. "MESSAGE", "CATEGORY").
        static let eyebrow = SwiftUI.Font.system(.footnote, design: .default).weight(.semibold)
        /// Primary message text.
        static let message = SwiftUI.Font.system(.title3, design: .default).weight(.semibold)
        /// Secondary / description text.
        static let body = SwiftUI.Font.system(.body, design: .default)
        /// Field input text.
        static let field = SwiftUI.Font.system(.title3, design: .default)
        /// Interactive chips, buttons, captions.
        static let chip = SwiftUI.Font.system(.subheadline, design: .default).weight(.medium)
        /// Metadata (dates, counts).
        static let caption = SwiftUI.Font.system(.caption, design: .default).weight(.medium)
    }
}

/// Editorial headline: the last line sits on a solid accent block, like a
/// magazine cover highlight. Lines are split on the localized string's
/// newlines; single-line text gets the full highlight.
struct HighlightHeadline: View {
    let text: String
    let font: Font
    var tracking: CGFloat = 0

    var body: some View {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        VStack(spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let isHighlighted = index == lines.count - 1
                Text(line)
                    .font(font)
                    .tracking(tracking)
                    .foregroundStyle(isHighlighted ? AppTheme.onHighlight : AppTheme.textPrimary)
                    .padding(.horizontal, isHighlighted ? 8 : 0)
                    .padding(.vertical, isHighlighted ? 1 : 0)
                    .background(isHighlighted ? AppTheme.highlight : .clear)
            }
        }
        .multilineTextAlignment(.center)
    }
}

/// Capsule page indicator for photo carousels, shared by the add/edit forms
/// and the detail pager so the style can't drift between them.
struct PhotoPageIndicator: View {
    let count: Int
    let current: Int
    var inactiveColor: Color = AppTheme.textSecondary.opacity(0.3)

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? AppTheme.accent : inactiveColor)
                    .frame(width: i == current ? 16 : 6, height: 6)
                    .animation(.spring(response: 0.3), value: current)
            }
        }
    }
}

/// Date field for the memory forms. Renders the value with the same
/// `AppTheme.Font.field` type as the text fields (so every form field shares
/// one font size) while keeping the native compact picker as an invisible,
/// fully tappable overlay.
struct FormDateField: View {
    @Binding var date: Date

    var body: some View {
        HStack {
            Text(date.formatted(date: .long, time: .omitted))
                .font(AppTheme.Font.field)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Image(systemName: "calendar")
                .font(AppTheme.Font.chip)
                .foregroundStyle(AppTheme.accent)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .overlay {
            DatePicker(
                String(localized: "form.date.pick"),
                selection: $date,
                in: ...Date.now,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(AppTheme.accent)
            .colorMultiply(.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct VergeGridBackground: View {
    @Environment(\.colorScheme) var colorScheme

    private var lineColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.08)
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
                    context.stroke(path, with: .color(lineColor), lineWidth: 1)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
