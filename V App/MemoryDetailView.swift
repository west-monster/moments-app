import SwiftUI
import SwiftData
import UIKit

struct MemoryDetailView: View {
    @Query(sort: \Memory.order, order: .reverse) private var allMemories: [Memory]
    let startIndex: Int
    let filterTag: MemoryTag
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var currentIndex: Int
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @State private var showShareSheet = false

    init(startIndex: Int, filterTag: MemoryTag = .none) {
        self.startIndex = startIndex
        self.filterTag = filterTag
        _currentIndex = State(initialValue: startIndex)

        // Native page dots tinted with the system accent.
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(AppTheme.accent)
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(AppTheme.accent).withAlphaComponent(0.25)
    }

    /// The memories the pager swipes through — kept in sync with the feed's
    /// active tag filter so it shows the same set the user tapped from.
    private var memories: [Memory] {
        if filterTag == .none { return allMemories }
        return allMemories.filter { $0.tag == filterTag.rawValue }
    }

    var body: some View {
        Group {
            if memories.isEmpty {
                Color.clear.onAppear { dismiss() }
            } else {
                GeometryReader { geo in
                    // One photo size for every page, measured once here, so the
                    // box is identical across memories.
                    let side = min(geo.size.width - 48, AppTheme.Layout.contentMaxWidth, geo.size.height * 0.5)
                    TabView(selection: $currentIndex) {
                        ForEach(Array(memories.enumerated()), id: \.element.persistentModelID) { index, memory in
                            MemoryPageView(
                                memory: memory,
                                photoSide: side,
                                onShare: { showShareSheet = true },
                                onEdit: { showEditSheet = true },
                                onDelete: { showDeleteConfirmation = true }
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
        }
        .tint(AppTheme.accent)
        // Grabber + swipe-down are the only dismissal (no "X" — avoids a
        // double affordance).
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .confirmationDialog(
            String(localized: "delete.title"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "delete.confirm"), role: .destructive) {
                deleteMemory()
            }
            Button(String(localized: "form.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showEditSheet) {
            if currentIndex < memories.count {
                EditMemoryView(memory: memories[currentIndex])
                    .presentationSizing(.page)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if currentIndex < memories.count {
                ShareCardView(memory: memories[currentIndex])
                    .presentationSizing(.page)
            }
        }
    }

    // MARK: - Delete

    private func deleteMemory() {
        guard currentIndex < memories.count else { return }
        let memory = memories[currentIndex]
        for name in memory.allImageFileNames {
            LocalStore.shared.deleteImage(named: name)
        }
        modelContext.delete(memory)
        if memories.count <= 1 {
            dismiss()
        } else if currentIndex >= memories.count - 1 {
            withAnimation {
                currentIndex = max(0, memories.count - 2)
            }
        }
    }
}

// MARK: - Single memory page

/// One page of the detail pager. Loads its photos off the main thread so
/// swiping between memories doesn't decode full-resolution images in `body`.
private struct MemoryPageView: View {
    let memory: Memory
    /// Fixed photo box size, shared by every page (passed from the container).
    let photoSide: CGFloat
    let onShare: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var images: [UIImage] = []
    @State private var photoIndex = 0

    /// Reserved height for the native page dots below the photo, kept even for
    /// single-photo memories so the photo sits at the same Y everywhere.
    private let dotsReserve: CGFloat = 34

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            photoCarousel

            // Fixed-height text region keeps the photo and the actions at the
            // same vertical position across memories.
            textBlock
                .frame(height: 140, alignment: .top)

            actionRow

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .task(id: memory.persistentModelID) {
            let names = memory.allImageFileNames
            let loaded = await Task.detached(priority: .userInitiated) {
                // Downsampled so a full carousel of large photos can't exhaust
                // memory and drop the later ones.
                names.compactMap { LocalStore.shared.loadDownscaledImage(named: $0, maxPixel: 1400) }
            }.value
            images = loaded
        }
    }

    // MARK: - Text block (centered, single system family)

    private var textBlock: some View {
        VStack(spacing: 8) {
            if !memory.message.isEmpty {
                Text(memory.message)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if !memory.notes.isEmpty {
                Text(memory.notes)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                if let tag = MemoryTag(rawValue: memory.tag), tag != .none {
                    Image(systemName: tag.icon)
                    Text("\(tag.label) · \(memory.formattedDate)")
                } else {
                    Text(memory.formattedDate)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    // MARK: - Actions (flat SF Symbols, inline with the content)

    private var actionRow: some View {
        HStack(spacing: 0) {
            actionButton("square.and.arrow.up", tint: AppTheme.accent, action: onShare)
            Spacer()
            actionButton("pencil", tint: AppTheme.accent, action: onEdit)
            Spacer()
            actionButton("trash", tint: .red, role: .destructive, action: onDelete)
        }
        .padding(.horizontal, 44)
    }

    private func actionButton(
        _ icon: String,
        tint: Color,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Photo carousel

    /// Same-size square using each photo's stored crop, with native page dots
    /// (tinted with the accent) rendered on white below the photo.
    @ViewBuilder
    private var photoCarousel: some View {
        let side = photoSide
        Group {
            if images.count > 1 {
                TabView(selection: $photoIndex) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, img in
                        photoPage(croppedPhoto(img, index: index, side: side))
                            .tag(index)
                    }
                }
                .tabViewStyle(.page)
            } else if let uiImage = images.first {
                photoPage(croppedPhoto(uiImage, index: 0, side: side))
            } else {
                photoPage(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: side, height: side)
                        .overlay { ProgressView() }
                )
            }
        }
        .frame(width: side, height: side + dotsReserve)
    }

    /// Top-aligns the square within its box so the native dots sit in the
    /// reserved space beneath it.
    private func photoPage<Content: View>(_ content: Content) -> some View {
        VStack(spacing: 0) {
            content
            Spacer(minLength: 0)
        }
    }

    private func croppedPhoto(_ img: UIImage, index: Int, side: CGFloat) -> some View {
        let crop = SquareCropGeometry(imageSize: img.size, side: side)
        let position = memory.cropOffset(at: index)
        return Color.clear
            .overlay {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .offset(crop.offset(cropX: position.x, cropY: position.y))
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
