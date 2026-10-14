import SwiftUI

/// Math for panning a photo inside a square crop: how much the aspect-filled
/// image overflows the square, and the offset a given crop position produces.
/// Shared by the add/edit forms (interactive crop) and the feed card (display),
/// so the framing logic can't drift between views.
struct SquareCropGeometry {
    let overflowX: CGFloat
    let overflowY: CGFloat

    init(imageSize: CGSize, side: CGFloat) {
        let aspect = imageSize.width / imageSize.height
        let isPortrait = aspect < 1
        let scaledW = isPortrait ? side : side * aspect
        let scaledH = isPortrait ? side / aspect : side
        overflowX = max(scaledW - side, 0)
        overflowY = max(scaledH - side, 0)
    }

    /// Offset to apply to the aspect-filled image for a crop position in 0...1
    /// (0.5 is centered).
    func offset(cropX: CGFloat, cropY: CGFloat) -> CGSize {
        CGSize(width: overflowX * (0.5 - cropX), height: overflowY * (0.5 - cropY))
    }

    /// New crop position after a drag, clamped to 0...1.
    func cropPosition(startX: CGFloat, startY: CGFloat, translation: CGSize) -> (x: CGFloat, y: CGFloat) {
        var x = startX
        var y = startY
        if overflowX > 0 {
            x = min(max(startX - translation.width / overflowX, 0), 1)
        }
        if overflowY > 0 {
            y = min(max(startY - translation.height / overflowY, 0), 1)
        }
        return (x, y)
    }
}
