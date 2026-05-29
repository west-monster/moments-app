import UIKit

final class LocalStore {
    static let shared = LocalStore()

    private let fileManager = FileManager.default
    private var cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 20
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
    }

    func exportMetadata(from memories: [Memory]) {
        let formatter = ISO8601DateFormatter()
        let items = memories.map { m in
            ExportedMemory(
                imageFileName: m.cloudFileName,
                message: m.message,
                notes: m.notes,
                date: formatter.string(from: m.date),
                order: m.order,
                cropOffsetX: m.cropOffsetX,
                cropOffsetY: m.cropOffsetY,
                tag: m.tag,
                extraImageFileNames: m.extraImageFileNames
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
