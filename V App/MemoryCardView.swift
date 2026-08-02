import SwiftUI
import SwiftData
import UIKit

struct MemoryCardView: View {
    let memory: Memory
    var onTap: () -> Void

    @Environment(\.modelContext) private var modelContext
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
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .topLeading) { heartButton }
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
                        // Read as "3 photos" rather than the glyph's own name.
                        .accessibilityElement()
                        .accessibilityLabel(photoCountLabel)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .topLeading) { heartButton }
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 36))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                if !memory.message.isEmpty {
                    Text(memory.message)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(2)
                }

                if !memory.notes.isEmpty {
                    Text(memory.notes)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(3)
                }

                HStack(spacing: 5) {
                    if let t = MemoryTag(rawValue: memory.tag), t != .none {
                        HStack(spacing: 4) {
                            Image(systemName: t.icon)
                            Text(t.label)
                        }

                        Text("·")
                    }

                    Text(memory.formattedDate)
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        // Without an explicit shape the tap region overflows the card and
        // swallows taps meant for the category chips sitting above it.
        .contentShape(Rectangle())
        // The card opens on a bare `onTapGesture`, which carries no button
        // trait, so VoiceOver announced its contents with no way to act on
        // them. Combining the children gives one element per memory; the heart,
        // which is no longer separately focusable, comes back as a custom
        // action — the standard pattern for a card with a secondary control.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .accessibilityAction(named: favoriteActionLabel) { toggleFavorite() }
        // Keyed on the file name, not the model ID: editing a memory's photo
        // keeps the same ID, so keying on that left the card showing the old
        // image until the view was rebuilt.
        .task(id: memory.imageFileName) {
            let fileName = memory.imageFileName
            guard !fileName.isEmpty else {
                loadedImage = nil
                return
            }
            let image = await Task.detached {
                LocalStore.shared.loadDownscaledImage(named: fileName, maxPixel: 1200)
            }.value
            loadedImage = image
        }
        .onTapGesture { onTap() }
    }

    private var photoCountLabel: Text {
        Text("a11y.photoCount \(memory.allImageFileNames.count)")
    }

    /// Each branch builds its own `Text` so the literal binds to
    /// `LocalizedStringKey`; a ternary between two string literals resolves to
    /// `Text(String)` instead, which renders the key verbatim.
    private var favoriteActionLabel: Text {
        memory.isFavorite
            ? Text("a11y.favorite.remove")
            : Text("a11y.favorite.add")
    }

    private func toggleFavorite() {
        withAnimation(.snappy(duration: 0.25)) {
            memory.isFavorite.toggle()
        }
        try? modelContext.save()
    }

    /// Favorite toggle in the top-left corner of the photo. Its own button, so
    /// tapping the heart doesn't open the memory. Hidden from VoiceOver, which
    /// reaches it through the card's custom action instead.
    private var heartButton: some View {
        Button {
            toggleFavorite()
        } label: {
            Image(systemName: memory.isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(memory.isFavorite ? .red : .white)
                .padding(8)
                .background(.black.opacity(0.3), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityHidden(true)
    }
}
