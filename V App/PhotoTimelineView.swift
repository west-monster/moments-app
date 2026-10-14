import SwiftUI
import UIKit

// MARK: - Timeline row

/// One entry in the chronological timeline layout: a connecting rail with a
/// dot, a thumbnail, and the memory's date / message / tag. Used by
/// `ContentView`'s timeline feed layout.
struct TimelineRow: View {
    let memory: Memory
    let isFirst: Bool
    let isLast: Bool
    var onTap: () -> Void

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "EEE d"
        return formatter.string(from: memory.date).uppercased()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            rail
            content
        }
        .padding(.horizontal, 20)
    }

    // Continuous vertical line with a dot at the entry point.
    private var rail: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : AppTheme.divider)
                    .frame(width: 2, height: 18)
                Rectangle()
                    .fill(isLast ? Color.clear : AppTheme.divider)
                    .frame(width: 2)
            }

            Circle()
                .fill(AppTheme.accent)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(AppTheme.background, lineWidth: 2).padding(-2))
                .padding(.top, 12)
        }
        .frame(width: 12)
    }

    private var content: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                TimelineThumb(memory: memory)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dayLabel)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(AppTheme.textSecondary)

                    if !memory.message.isEmpty {
                        Text(memory.message)
                            .font(.system(.subheadline, design: .default).weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if let tag = MemoryTag(rawValue: memory.tag), tag != .none {
                        HStack(spacing: 4) {
                            Image(systemName: tag.icon)
                            Text(tag.label)
                        }
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Async thumbnail

private struct TimelineThumb: View {
    let memory: Memory
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(AppTheme.cardBackground)
                    .overlay { ProgressView() }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: memory.imageFileName) {
            let name = memory.imageFileName
            guard !name.isEmpty else {
                image = nil
                return
            }
            image = await Task.detached(priority: .userInitiated) {
                // Downsampled to the 64pt box (3x) — loading the full-size
                // photo for a thumbnail also evicted everything else from the
                // shared image cache.
                LocalStore.shared.loadDownscaledImage(named: name, maxPixel: 200)
            }.value
        }
    }
}
