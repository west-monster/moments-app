import SwiftUI
import UIKit

struct MemoryCardView: View {
    let memory: Memory
    var onTap: () -> Void

    @State private var loadedImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let uiImage = loadedImage {
                GeometryReader { geo in
                    let side = geo.size.width
                    let crop = SquareCropGeometry(imageSize: uiImage.size, side: side)

                    Color.clear
                        .overlay {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .offset(crop.offset(cropX: memory.cropOffsetX, cropY: memory.cropOffsetY))
                        }
                        .frame(width: side, height: side)
                        .clipped()
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if memory.allImageFileNames.count > 1 {
                        HStack(spacing: 3) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 11, weight: .semibold))
                            Text("\(memory.allImageFileNames.count)")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(10)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 36))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                if !memory.message.isEmpty {
                    Text(memory.message)
                        .font(AppTheme.Font.message)
                        .foregroundStyle(AppTheme.onHighlight)
                        .lineSpacing(3)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(AppTheme.highlight)
                }

                if !memory.notes.isEmpty {
                    Text(memory.notes)
                        .font(AppTheme.Font.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                }

                HStack(spacing: 5) {
                    if let t = MemoryTag(rawValue: memory.tag), t != .none {
                        HStack(spacing: 3) {
                            Image(systemName: t.icon)
                                .font(AppTheme.Font.caption)
                            Text(t.label)
                                .font(AppTheme.Font.caption)
                                .tracking(1)
                                .textCase(.uppercase)
                        }
                        .foregroundStyle(AppTheme.accent)

                        Text("·")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Text(memory.formattedDate)
                        .font(AppTheme.Font.caption)
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .task(id: memory.persistentModelID) {
            let fileName = memory.imageFileName
            guard !fileName.isEmpty else { return }
            let image = await Task.detached {
                LocalStore.shared.loadImage(named: fileName)
            }.value
            loadedImage = image
        }
        .onTapGesture { onTap() }
    }
}
