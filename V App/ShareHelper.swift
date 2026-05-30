import UIKit

/// Presents the system share sheet from the correct window, regardless of
/// multi-window / iPad layouts. Replaces the previous `connectedScenes.first`
/// lookup, which wasn't guaranteed to return the foreground-active scene.
@MainActor
enum ShareHelper {
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let root = scene?.keyWindow?.rootViewController else { return nil }

        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    static func present(_ items: [Any], completion: (() -> Void)? = nil) {
        guard let top = topViewController() else {
            completion?()
            return
        }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in completion?() }

        // Anchor the popover for iPad / Mac Catalyst.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        top.present(controller, animated: true)
    }
}
