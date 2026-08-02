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

/// Photo and metadata storage in the app's Documents directory.
///
/// Reachable from background decode/encode tasks, hence `@unchecked Sendable`:
/// `NSCache` and `FileManager` are themselves thread-safe, and the only other
/// mutable state (`variantSizes`) is behind `variantLock`.
final class LocalStore: @unchecked Sendable {
    static let shared = LocalStore()

    private let fileManager = FileManager.default
    private var cache = NSCache<NSString, UIImage>()

    /// Serialises metadata snapshot writes off the main thread, in call order.
    private let metadataQueue = DispatchQueue(label: "axo.V-App.LocalStore.metadata", qos: .utility)

    /// Downscaled entries are cached under `name#maxPixel`, which `NSCache`
    /// can't enumerate, so `deleteImage` has to rebuild the derived keys to
    /// evict them. Only the handful of sizes the app actually asks for is
    /// tracked: the previous per-file list of keys grew with the library and
    /// was never pruned when `NSCache` dropped an entry on its own, so it kept
    /// dead keys for the lifetime of the process. Written from background
    /// decode tasks.
    private let variantLock = NSLock()
    private var variantSizes: Set<Int> = []

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
    /// made photos past the first few fail to appear).
    ///
    /// Pass `caching: false` for a one-off bulk read such as the PDF export:
    /// print-sized decodes of a whole album would otherwise fill the shared
    /// cache and evict every thumbnail the UI is using.
    func loadDownscaledImage(named fileName: String, maxPixel: CGFloat, caching: Bool = true) -> UIImage? {
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
        guard caching else { return image }
        cache.setObject(image, forKey: key)
        variantLock.lock()
        variantSizes.insert(Int(maxPixel))
        variantLock.unlock()
        return image
    }

    func deleteImage(named fileName: String) {
        cache.removeObject(forKey: fileName as NSString)

        variantLock.lock()
        let sizes = variantSizes
        variantLock.unlock()
        for size in sizes {
            cache.removeObject(forKey: "\(fileName)#\(size)" as NSString)
        }

        let url = imagesURL.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Metadata export/import

    struct ExportedMemory: Codable, Sendable {
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

    /// Writes the recovery snapshot. Reading the models has to happen here (they
    /// are main-actor bound) but the encode and the disk write are handed to a
    /// serial background queue — doing them inline meant every heart tap
    /// re-encoded the whole library on the main thread.
    ///
    /// Pass `waitUntilDone` when the app is heading to the background and the
    /// write has to land before the process is suspended.
    func exportMetadata(from memories: [Memory], waitUntilDone: Bool = false) {
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
        let destination = metadataFileURL
        let write = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(items) else { return }
            try? data.write(to: destination, options: .atomic)
        }

        if waitUntilDone {
            metadataQueue.sync(execute: write)
        } else {
            metadataQueue.async(execute: write)
        }
    }

    func loadMetadata() -> [ExportedMemory] {
        guard let data = try? Data(contentsOf: metadataFileURL),
              let items = try? JSONDecoder().decode([ExportedMemory].self, from: data) else {
            return []
        }
        return items
    }
}
