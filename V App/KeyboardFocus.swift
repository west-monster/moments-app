import SwiftUI

/// The text fields of the add / edit memory forms, used both as `@FocusState`
/// values and as scroll targets.
enum MemoryFormField: Hashable {
    case name
    case notes
}

extension View {
    /// Keeps the focused field clear of the keyboard.
    ///
    /// `Form` already insets itself when the keyboard appears, but it decides on
    /// its own which row stays visible, so a field low in the form — or the
    /// description as it grows line by line — could still end up behind the
    /// keyboard. Scrolling to the focused row explicitly makes it deterministic.
    ///
    /// The row is anchored to the bottom of the visible area, plus a small fixed
    /// inset so the keyboard doesn't shave its lower border.
    ///
    /// The inset is deliberately a fixed number of points and not a proportional
    /// anchor: `.bottom` already lands the row where it belongs, just a few
    /// points too low, and backing the anchor off by a percentage of the viewport
    /// overshoots into the scroll view's travel limit — the row then jumps far
    /// higher than intended and leaves an obvious gap above the keyboard.
    ///
    /// The delay is unavoidable rather than tuned: the scroll has to happen
    /// after the keyboard's own inset animation has landed, otherwise it targets
    /// the pre-keyboard layout and lands short. `revision` re-triggers it while
    /// a field is already focused, which is what covers the growing description.
    func scrollsFocusedFieldAboveKeyboard(
        _ field: MemoryFormField?,
        revision: String,
        in proxy: ScrollViewProxy
    ) -> some View {
        modifier(ScrollFocusedFieldModifier(field: field, revision: revision, proxy: proxy))
    }
}

private struct ScrollFocusedFieldModifier: ViewModifier {
    /// Breathing room between the focused field and the keyboard. Small on
    /// purpose: enough that nothing is clipped, not enough to read as a gap.
    private static let clearance: CGFloat = 10

    let field: MemoryFormField?
    let revision: String
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, Self.clearance)
            .onChange(of: field) { _, newValue in
                scroll(to: newValue, afterKeyboard: true)
            }
            .onChange(of: revision) { _, _ in
                // Already focused and typing: the keyboard is up, so re-scroll
                // immediately as the field grows.
                scroll(to: field, afterKeyboard: false)
            }
    }

    private func scroll(to field: MemoryFormField?, afterKeyboard: Bool) {
        guard let field else { return }
        Task { @MainActor in
            if afterKeyboard {
                try? await Task.sleep(for: .milliseconds(350))
            }
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(field, anchor: .bottom)
            }
        }
    }
}
