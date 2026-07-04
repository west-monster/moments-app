import SwiftUI
import SwiftData
import UIKit

@Model
final class Memory {
    /// Stored under its previous name (`cloudFileName`) so existing libraries
    /// migrate automatically. Holds the file name of the main image.
    @Attribute(originalName: "cloudFileName") var imageFileName: String = ""
    var message: String = ""
    var notes: String = ""
    var date: Date = Date.now
    var order: Int = 0
    var cropOffsetX: Double = 0.5
    var cropOffsetY: Double = 0.5
    var tag: String = ""
    var extraImageFileNames: [String] = []
    /// Square-crop position (0...1) per extra photo, aligned with
    /// `extraImageFileNames`; missing entries mean centered.
    var extraCropOffsetsX: [Double] = []
    var extraCropOffsetsY: [Double] = []

    init(imageFileName: String = "", message: String = "", notes: String = "", date: Date = .now, order: Int = 0, cropOffsetX: Double = 0.5, cropOffsetY: Double = 0.5, tag: String = "", extraImageFileNames: [String] = [], extraCropOffsetsX: [Double] = [], extraCropOffsetsY: [Double] = []) {
        self.imageFileName = imageFileName
        self.message = message
        self.notes = notes
        self.date = date
        self.order = order
        self.cropOffsetX = cropOffsetX
        self.cropOffsetY = cropOffsetY
        self.tag = tag
        self.extraImageFileNames = extraImageFileNames
        self.extraCropOffsetsX = extraCropOffsetsX
        self.extraCropOffsetsY = extraCropOffsetsY
    }

    var allImageFileNames: [String] {
        var names: [String] = []
        if !imageFileName.isEmpty { names.append(imageFileName) }
        names.append(contentsOf: extraImageFileNames)
        return names
    }

    /// Crop position for the photo at `index` in `allImageFileNames` order
    /// (0 = cover). Centered when never adjusted.
    func cropOffset(at index: Int) -> CGPoint {
        if index == 0 {
            return CGPoint(x: cropOffsetX, y: cropOffsetY)
        }
        let extraIndex = index - 1
        guard extraCropOffsetsX.indices.contains(extraIndex),
              extraCropOffsetsY.indices.contains(extraIndex) else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        return CGPoint(x: extraCropOffsetsX[extraIndex], y: extraCropOffsetsY[extraIndex])
    }

    var uiImage: UIImage? {
        guard !imageFileName.isEmpty else { return nil }
        return LocalStore.shared.loadImage(named: imageFileName)
    }

    var allImages: [UIImage] {
        allImageFileNames.compactMap { LocalStore.shared.loadImage(named: $0) }
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

enum MemoryLimits {
    /// Hard cap on photos per memory. Keeps the detail carousel and the PDF
    /// export (one memory page + overflow grid pages) manageable.
    static let maxPhotos = 20
}

enum MemoryTag: String, CaseIterable, Identifiable {
    case none = ""
    case travel = "travel"
    case family = "family"
    case friends = "friends"
    case couple = "couple"
    case celebration = "celebration"
    case adventure = "adventure"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: String(localized: "tag.none")
        case .travel: String(localized: "tag.travel")
        case .family: String(localized: "tag.family")
        case .friends: String(localized: "tag.friends")
        case .couple: String(localized: "tag.couple")
        case .celebration: String(localized: "tag.celebration")
        case .adventure: String(localized: "tag.adventure")
        }
    }

    var icon: String {
        switch self {
        case .none: "tag"
        case .travel: "airplane"
        case .family: "house.fill"
        case .friends: "person.2.fill"
        case .couple: "heart.fill"
        case .celebration: "party.popper.fill"
        case .adventure: "figure.hiking"
        }
    }
}

// MARK: - Splash content

enum AlbumContent {
    static let dedicatoria = String(localized: "splash.dedication")
    static let titulo = String(localized: "splash.title")
    static let tituloRecurrente = String(localized: "splash.title.returning")
}
