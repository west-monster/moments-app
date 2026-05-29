import Foundation
import UIKit
import WidgetKit

enum WidgetDataProvider {
    private static let appGroupID = "group.axo.V-App"
    private static let fileName = "widget_memories.json"

    static func update(with memories: [Memory]) {
        let items = memories.compactMap { memory -> WidgetMemoryData? in
            var base64: String?
            if let img = memory.uiImage {
                let side = min(img.size.width, img.size.height)
                let cropX = (img.size.width - side) * memory.cropOffsetX
                let cropY = (img.size.height - side) * memory.cropOffsetY
                let cropRect = CGRect(x: cropX, y: cropY, width: side, height: side)
                let targetSize: CGFloat = 300
                let scale = targetSize / side
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSize, height: targetSize))
                let thumb = renderer.image { _ in
                    img.draw(in: CGRect(
                        x: -cropRect.origin.x * scale,
                        y: -cropRect.origin.y * scale,
                        width: img.size.width * scale,
                        height: img.size.height * scale
                    ))
                }
                base64 = thumb.jpegData(compressionQuality: 0.6)?.base64EncodedString()
            }

            return WidgetMemoryData(
                message: memory.message,
                memoryDate: memory.formattedDate,
                imageBase64: base64
            )
        }

        guard let jsonData = try? JSONEncoder().encode(items),
              let url = fileURL() else { return }
        try? jsonData.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func fileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }
}
