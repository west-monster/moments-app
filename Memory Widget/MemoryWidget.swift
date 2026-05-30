import WidgetKit
import SwiftUI
import UIKit

private enum SharedData {
    static let appGroupID = "group.axo.V-App"
    static let thumbnailsDirName = "WidgetThumbnails"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static func loadMemories() -> [WidgetMemoryData] {
        guard let url = containerURL?.appendingPathComponent("widget_memories.json"),
              let data = try? Data(contentsOf: url),
              let memories = try? JSONDecoder().decode([WidgetMemoryData].self, from: data) else {
            return []
        }
        return memories
    }

    static func thumbnail(named name: String) -> UIImage? {
        guard let url = containerURL?
            .appendingPathComponent(thumbnailsDirName, isDirectory: true)
            .appendingPathComponent(name),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }
}

// MARK: - Timeline

struct MemoryEntry: TimelineEntry {
    let date: Date
    let message: String
    let memoryDate: String
    let image: UIImage?
    let isEmpty: Bool

    static let placeholder = MemoryEntry(date: .now, message: String(localized: "widget.placeholder.message"), memoryDate: DateFormatter.localizedString(from: .now, dateStyle: .long, timeStyle: .none).uppercased(), image: nil, isEmpty: false)
    static let empty = MemoryEntry(date: .now, message: "", memoryDate: "", image: nil, isEmpty: true)
}

struct MemoryTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemoryEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (MemoryEntry) -> Void) {
        completion(fetchRandomEntry() ?? .placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoryEntry>) -> Void) {
        let entry = fetchRandomEntry() ?? .empty
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(1800))))
    }

    private func fetchRandomEntry() -> MemoryEntry? {
        let memories = SharedData.loadMemories()
        guard let m = memories.randomElement() else { return nil }

        var image: UIImage?
        if let name = m.imageFileName {
            image = SharedData.thumbnail(named: name)
        }

        return MemoryEntry(date: .now, message: m.message, memoryDate: m.memoryDate, image: image, isEmpty: false)
    }
}

// MARK: - View

struct MemoryWidgetView: View {
    let entry: MemoryEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.isEmpty {
            emptyView
        } else {
            contentView
        }
    }

    private var contentView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Spacer()

                if !entry.message.isEmpty {
                    Text(entry.message)
                        .font(.system(size: family == .systemLarge ? 17 : 14, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .lineSpacing(2)
                }

                Text(entry.memoryDate)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let image = entry.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: family == .systemLarge ? 160 : 130,
                        height: family == .systemLarge ? 160 : 130
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(4)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.33, green: 0.53, blue: 1.0).opacity(0.15))
                    .frame(
                        width: family == .systemLarge ? 160 : 130,
                        height: family == .systemLarge ? 160 : 130
                    )
                    .overlay {
                        Image(systemName: "heart.circle")
                            .font(.system(size: 28, weight: .thin))
                            .foregroundStyle(Color(red: 0.33, green: 0.53, blue: 1.0))
                    }
                    .padding(4)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.circle")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(Color(red: 0.33, green: 0.53, blue: 1.0))

            Text("widget.empty")
                .font(.system(size: 13, weight: .medium, design: .serif))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Widget

struct MemoryWidget: Widget {
    let kind = "MemoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemoryTimelineProvider()) { entry in
            MemoryWidgetView(entry: entry)
                .containerBackground(.fill, for: .widget)
        }
        .configurationDisplayName("widget.name")
        .description("widget.description")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct MemoryWidgetBundle: WidgetBundle {
    var body: some Widget {
        MemoryWidget()
    }
}
