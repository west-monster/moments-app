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
                    // band is identical across memories.
                    let side = min(geo.size.width, geo.size.height * 0.58)
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
        // Counted before the delete: reading `memories` afterwards depends on
        // whether the @Query has already refreshed, which isn't guaranteed
        // within this call and left the pager on a stale index.
        let remaining = memories.count - 1

        for name in memory.allImageFileNames {
            LocalStore.shared.deleteImage(named: name)
        }
        modelContext.delete(memory)

        if remaining <= 0 {
            dismiss()
        } else if currentIndex > remaining - 1 {
            withAnimation {
                currentIndex = remaining - 1
            }
        }
    }
}

// MARK: - Single memory page

/// One page of the detail pager. Loads its photos off the main thread so
/// swiping between memories doesn't decode full-resolution images in `body`.
private struct MemoryPageView: View {
    let memory: Memory
    /// Fixed photo band height, shared by every page (passed from the
    /// container).
    let photoSide: CGFloat
    let onShare: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var images: [UIImage] = []
    @State private var photoIndex = 0

    /// Reserved height for the native page dots below the photo, kept even for
    /// single-photo memories so the text sits at the same Y everywhere.
    private let dotsReserve: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            // Edge to edge and flush with the top of the sheet — the photo owns
            // the whole upper band, no side margins.
            photoCarousel

            VStack(spacing: 16) {
                // The photo can't fill a tall phone, so the leftover height is
                // split above and below the caption instead of collecting into
                // one hole between the text and the bar.
                Spacer(minLength: 8)

                textBlock

                Spacer(minLength: 8)

                actionRow
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        // Keyed on the file names so editing a memory's photos reloads the
        // carousel; the model ID doesn't change when the photos do.
        .task(id: memory.allImageFileNames) {
            let names = memory.allImageFileNames
            let loaded = await Task.detached(priority: .userInitiated) {
                // Downsampled so a full carousel of large photos can't exhaust
                // memory and drop the later ones.
                names.compactMap { LocalStore.shared.loadDownscaledImage(named: $0, maxPixel: 1400) }
            }.value
            images = loaded
            photoIndex = 0
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

    // MARK: - Actions

    /// Styled after the home screen's floating tab bar: a capsule that hugs its
    /// three items, centered, lifted off the page by a soft shadow. No
    /// hairlines — the tab bar has none either, and the labels under each icon
    /// already mark where one button ends and the next begins.
    private var actionRow: some View {
        HStack(spacing: 2) {
            actionButton("square.and.arrow.up", title: "action.share", tint: AppTheme.accent, action: onShare)
            actionButton("pencil", title: "action.edit", tint: AppTheme.accent, action: onEdit)
            actionButton("trash", title: "action.delete", tint: .red, role: .destructive, action: onDelete)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    private func actionButton(
        _ icon: String,
        title: LocalizedStringKey,
        tint: Color,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(tint)
            .frame(width: 74, height: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Photo carousel

    /// Full-width band using each photo's stored crop, with native page dots
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
                    Rectangle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: side)
                        .overlay { ProgressView() }
                )
            }
        }
        .frame(height: side + dotsReserve)
    }

    /// Top-aligns the photo within its band so the native dots sit in the
    /// reserved space beneath it.
    private func photoPage<Content: View>(_ content: Content) -> some View {
        VStack(spacing: 0) {
            content
            Spacer(minLength: 0)
        }
    }

    /// Aspect-fills the full-width band using the crop stored for the photo, so
    /// the framing matches the rest of the app. No corner radius — the band
    /// runs edge to edge.
    private func croppedPhoto(_ img: UIImage, index: Int, side: CGFloat) -> some View {
        let position = memory.cropOffset(at: index)
        return GeometryReader { geo in
            let scale = max(geo.size.width / max(img.size.width, 1),
                            geo.size.height / max(img.size.height, 1))
            let width = img.size.width * scale
            let height = img.size.height * scale

            Image(uiImage: img)
                .resizable()
                .frame(width: width, height: height)
                .offset(
                    x: -(width - geo.size.width) * position.x,
                    y: -(height - geo.size.height) * position.y
                )
        }
        .frame(height: side)
        .clipped()
    }
}
