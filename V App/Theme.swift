import SwiftUI
import UIKit

enum AppTheme {
    /// White app background (light-mode only for now).
    static let background = AccentPalette.appBackground
    static let cardBackground = Color(.secondarySystemBackground)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let divider = Color(.separator)

    /// Fixed editorial accent: bright blue on iOS, mint on watchOS.
    static let accent = AccentPalette.accent
    /// Text/icon color for content sitting on the accent (chips, pills).
    static let onAccent = AccentPalette.onAccent

    /// Accent for the UIKit-based renderers (share card, PDF export), which
    /// draw on white and run off the main thread.
    static var accentUIColor: UIColor { UIColor(AccentPalette.brightBlue) }

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
        /// Section labels (e.g. "MESSAGE", "CATEGORY").
        static let eyebrow = SwiftUI.Font.system(.footnote, design: .default).weight(.semibold)
        /// Primary message text.
        static let message = SwiftUI.Font.system(.title3, design: .default).weight(.semibold)
        /// Secondary / description text.
        static let body = SwiftUI.Font.system(.body, design: .default)
        /// Interactive chips, buttons, captions.
        static let chip = SwiftUI.Font.system(.subheadline, design: .default).weight(.medium)
        /// Metadata (dates, counts).
        static let caption = SwiftUI.Font.system(.caption, design: .default).weight(.medium)
    }
}

/// Capsule chip for the category controls: the feed's filter row and the
/// add/edit forms' picker.
///
/// One primitive for both, because the two form copies were byte-identical to
/// each other and had drifted from the filter row in padding and unselected
/// font weight for no reason. What genuinely differs stays with the caller: the
/// label ("All" in the filter row, "None" in the forms), the optional icon, and
/// the unselected fill — the filter row sits on white, the form section on
/// `systemGroupedBackground`, so one fill can't read well on both.
struct CategoryChip: View {
    let label: String
    var icon: String?
    let isSelected: Bool
    /// Fill behind an unselected chip. Defaults to the value that reads on the
    /// app's white background.
    var unselectedFill: Color = Color(.systemGray5)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(label)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? AppTheme.onAccent : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(isSelected ? AppTheme.accent : unselectedFill)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The category picker shared by the add and edit forms — previously the same
/// `Section` and chip builder copied into both files.
struct CategoryFormSection: View {
    @Binding var selected: MemoryTag

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MemoryTag.allCases) { category in
                        CategoryChip(
                            label: category == .none ? String(localized: "tag.none") : category.label,
                            icon: category.icon,
                            isSelected: selected == category,
                            // The section's rows sit on `systemGroupedBackground`,
                            // where systemGray5 reads as grey-on-grey.
                            unselectedFill: Color(.secondarySystemGroupedBackground)
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) { selected = category }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color(.systemGroupedBackground))
        } header: {
            Text("form.section.category").textCase(nil)
        }
    }
}
