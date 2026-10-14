import Foundation

struct WidgetMemoryData: Codable, Sendable {
    let message: String
    let memoryDate: String
    /// File name of a pre-rendered thumbnail stored in the App Group's
    /// `WidgetThumbnails` directory. `nil` when the memory has no image.
    let imageFileName: String?
}
