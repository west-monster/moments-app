import UIKit
import ImageIO

extension UIImage {
    /// Aspect-preserving downscale so the longest side is at most `maxSide`;
    /// returns `self` when already small enough. Shared by the transports
    /// that ship photos off-device (watch sync, future exports).
    func downscaled(maxSide: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxSide, largest > 0 else { return self }
        let scale = maxSide / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

final class LocalStore {
    static let shared = LocalStore()

    private let fileManager = FileManager.default
    private var cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 50
        ensureDirectories()
    }

    // MARK: - Directories

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    var imagesURL: URL {
        documentsURL.appendingPathComponent("Images")
    }

    var metadataURL: URL {
        documentsURL.appendingPathComponent("Metadata")
    }

    private var metadataFileURL: URL {
        metadataURL.appendingPathComponent("memories.json")
    }

    private func ensureDirectories() {
        for url in [imagesURL, metadataURL] {
            if !fileManager.fileExists(atPath: url.path) {
                try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Images

    func saveImage(_ image: UIImage, quality: CGFloat = 0.82) -> String? {
        let fileName = UUID().uuidString + ".jpg"
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        let url = imagesURL.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        cache.setObject(image, forKey: fileName as NSString)
        return fileName
    }

    func loadImage(named fileName: String) -> UIImage? {
        if let cached = cache.object(forKey: fileName as NSString) {
            return cached
        }
        let url = imagesURL.appendingPathComponent(fileName)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: fileName as NSString)
        return image
    }

    /// Decodes a downsampled version straight from disk (ImageIO thumbnail), so
    /// showing many photos at once — e.g. a memory's full carousel — never
    /// loads them all at full resolution and runs the app out of memory (which
    /// made photos past the first few fail to appear). For display only; the
    /// share card and PDF export still use `loadImage` for full resolution.
    func loadDownscaledImage(named fileName: String, maxPixel: CGFloat) -> UIImage? {
        let key = "\(fileName)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let url = imagesURL.appendingPathComponent(fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return loadImage(named: fileName)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return loadImage(named: fileName)
        }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }

    func deleteImage(named fileName: String) {
        cache.removeObject(forKey: fileName as NSString)
        let url = imagesURL.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Metadata export/import

    struct ExportedMemory: Codable {
        let imageFileName: String
        let message: String
        let notes: String
        let date: String
        let order: Int
        let cropOffsetX: Double
        let cropOffsetY: Double
        var tag: String = ""
        var extraImageFileNames: [String] = []
        // Optional so snapshots written before per-photo crops still decode.
        var extraCropOffsetsX: [Double]?
        var extraCropOffsetsY: [Double]?
        // Optional so snapshots written before favorites still decode.
        var isFavorite: Bool?
    }

    func exportMetadata(from memories: [Memory]) {
        let formatter = ISO8601DateFormatter()
        let items = memories.map { m in
            ExportedMemory(
                imageFileName: m.imageFileName,
                message: m.message,
                notes: m.notes,
                date: formatter.string(from: m.date),
                order: m.order,
                cropOffsetX: m.cropOffsetX,
                cropOffsetY: m.cropOffsetY,
                tag: m.tag,
                extraImageFileNames: m.extraImageFileNames,
                extraCropOffsetsX: m.extraCropOffsetsX,
                extraCropOffsetsY: m.extraCropOffsetsY,
                isFavorite: m.isFavorite
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: metadataFileURL, options: .atomic)
    }

    func loadMetadata() -> [ExportedMemory] {
        guard let data = try? Data(contentsOf: metadataFileURL),
              let items = try? JSONDecoder().decode([ExportedMemory].self, from: data) else {
            return []
        }
        return items
    }
}
