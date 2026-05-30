import Foundation
import UIKit
import WidgetKit

enum WidgetDataProvider {
    private static let appGroupID = "group.axo.V-App"
    private static let metadataFileName = "widget_memories.json"
    private static let thumbnailsDirName = "WidgetThumbnails"
    private static let thumbnailSize: CGFloat = 300

    /// Plain-value snapshot of a `Memory` so the heavy work can run off the
    /// main actor without touching SwiftData-bound model objects.
    private struct MemorySnapshot: Sendable {
        let message: String
        let memoryDate: String
        let sourceFileName: String
        let cropOffsetX: Double
        let cropOffsetY: Double
    }

    /// Captures the data we need on the main actor, then rebuilds the widget
    /// payload on a background task. Only thumbnails that don't already exist
    /// are regenerated, so adding/removing a memory no longer re-renders the
    /// whole library on the main thread.
    static func update(with memories: [Memory]) {
        let snapshots = memories.map {
            MemorySnapshot(
                message: $0.message,
                memoryDate: $0.formattedDate,
                sourceFileName: $0.imageFileName,
                cropOffsetX: $0.cropOffsetX,
                cropOffsetY: $0.cropOffsetY
            )
        }

        Task.detached(priority: .utility) {
            rebuild(from: snapshots)
        }
    }

    // MARK: - Background rebuild

    private static func rebuild(from snapshots: [MemorySnapshot]) {
        guard let thumbnailsURL = thumbnailsURL() else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)

        var items: [WidgetMemoryData] = []
        var usedThumbnails = Set<String>()

        for snapshot in snapshots {
            var thumbName: String?

            if !snapshot.sourceFileName.isEmpty {
                let name = thumbnailName(for: snapshot)
                usedThumbnails.insert(name)
                let dest = thumbnailsURL.appendingPathComponent(name)

                if !fm.fileExists(atPath: dest.path),
                   let source = LocalStore.shared.loadImage(named: snapshot.sourceFileName),
                   let data = makeThumbnail(source, cropX: snapshot.cropOffsetX, cropY: snapshot.cropOffsetY) {
                    try? data.write(to: dest, options: .atomic)
                }

                if fm.fileExists(atPath: dest.path) {
                    thumbName = name
                }
            }

            items.append(WidgetMemoryData(
                message: snapshot.message,
                memoryDate: snapshot.memoryDate,
                imageFileName: thumbName
            ))
        }

        // Remove thumbnails that no longer back a memory (deleted/edited photos).
        if let existing = try? fm.contentsOfDirectory(at: thumbnailsURL, includingPropertiesForKeys: nil) {
            for url in existing where !usedThumbnails.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        }

        if let metadataURL = metadataURL(),
           let jsonData = try? JSONEncoder().encode(items) {
            try? jsonData.write(to: metadataURL, options: .atomic)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Thumbnail rendering

    /// Deterministic name derived from the source image and its crop, so a
    /// thumbnail is reused until the underlying photo or framing changes.
    private static func thumbnailName(for snapshot: MemorySnapshot) -> String {
        let base = snapshot.sourceFileName.replacingOccurrences(of: ".jpg", with: "")
        let cx = Int((snapshot.cropOffsetX * 1000).rounded())
        let cy = Int((snapshot.cropOffsetY * 1000).rounded())
        return "\(base)_\(cx)_\(cy).jpg"
    }

    private static func makeThumbnail(_ img: UIImage, cropX: Double, cropY: Double) -> Data? {
        let side = min(img.size.width, img.size.height)
        guard side > 0 else { return nil }

        let cropOriginX = (img.size.width - side) * cropX
        let cropOriginY = (img.size.height - side) * cropY
        let scale = thumbnailSize / side

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: thumbnailSize, height: thumbnailSize),
            format: format
        )
        let thumb = renderer.image { _ in
            img.draw(in: CGRect(
                x: -cropOriginX * scale,
                y: -cropOriginY * scale,
                width: img.size.width * scale,
                height: img.size.height * scale
            ))
        }
        return thumb.jpegData(compressionQuality: 0.6)
    }

    // MARK: - App Group locations

    private static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static func metadataURL() -> URL? {
        containerURL()?.appendingPathComponent(metadataFileName)
    }

    private static func thumbnailsURL() -> URL? {
        containerURL()?.appendingPathComponent(thumbnailsDirName, isDirectory: true)
    }
}
