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
                    let aspect = uiImage.size.width / uiImage.size.height
                    let isPortrait = aspect < 1
                    let scaledW = isPortrait ? side : side * aspect
                    let scaledH = isPortrait ? side / aspect : side
                    let overflowX = max(scaledW - side, 0)
                    let overflowY = max(scaledH - side, 0)

                    Color.clear
                        .overlay {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .offset(
                                    x: overflowX * (0.5 - memory.cropOffsetX),
                                    y: overflowY * (0.5 - memory.cropOffsetY)
                                )
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
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(3)
                }

                if !memory.notes.isEmpty {
                    Text(memory.notes)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                }

                HStack(spacing: 5) {
                    if let t = MemoryTag(rawValue: memory.tag), t != .none {
                        HStack(spacing: 3) {
                            Image(systemName: t.icon)
                                .font(.system(size: 9))
                            Text(t.label)
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .textCase(.uppercase)
                        }
                        .foregroundStyle(AppTheme.accent)

                        Text("·")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Text(memory.formattedDate)
                        .font(.system(size: 11, weight: .bold))
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
            let fileName = memory.cloudFileName
            guard !fileName.isEmpty else { return }
            let image = await Task.detached {
                LocalStore.shared.loadImage(named: fileName)
            }.value
            loadedImage = image
        }
        .onTapGesture { onTap() }
    }
}
