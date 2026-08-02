import SwiftUI
import SwiftData
import UIKit

struct MemoryDetailView: View {
    @Query(sort: \Memory.order, order: .reverse) private var allMemories: [Memory]
    let startID: PersistentIdentifier
    /// The tab the memory was opened from — the pager reproduces exactly the
    /// set that tab was showing, in the same order.
    let scope: AppTab
    let filterTag: MemoryTag
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// The page is tracked by the memory's own identity, not by its position.
    ///
    /// With an `Int` position the `TabView`'s selection silently stopped
    /// updating — the tag type has to match the identity the `ForEach` uses, and
    /// that is `persistentModelID`. Swiping moved the page visually while the
    /// binding stayed on the memory you opened, so Edit, Share and Delete all
    /// acted on the wrong one. Identity also survives the array shifting under a
    /// delete, which an index does not.
    @State private var currentID: PersistentIdentifier
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @State private var showShareSheet = false

    init(startID: PersistentIdentifier, scope: AppTab = .library, filterTag: MemoryTag = .none) {
        self.startID = startID
        self.scope = scope
        self.filterTag = filterTag
        _currentID = State(initialValue: startID)
    }

    /// The memories the pager swipes through — the same set, in the same order,
    /// that the tab the user tapped from was showing.
    private var memories: [Memory] {
        scope.memories(from: allMemories, tag: filterTag)
    }

    /// The memory currently on screen; what Edit, Share and Delete act on.
    private var currentMemory: Memory? {
        memories.first { $0.persistentModelID == currentID }
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
                    TabView(selection: $currentID) {
                        ForEach(memories, id: \.persistentModelID) { memory in
                            MemoryPageView(
                                memory: memory,
                                photoSide: side,
                                onShare: { showShareSheet = true },
                                onEdit: { showEditSheet = true },
                                onDelete: { showDeleteConfirmation = true }
                            )
                            .tag(memory.persistentModelID)
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
            if let memory = currentMemory {
                EditMemoryView(memory: memory)
                    .presentationSizing(.page)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let memory = currentMemory {
                ShareCardView(memory: memory)
                    .presentationSizing(.page)
            }
        }
    }

    // MARK: - Delete

    private func deleteMemory() {
        let list = memories
        guard let index = list.firstIndex(where: { $0.persistentModelID == currentID }) else { return }
        let memory = list[index]
        let fileNames = memory.allImageFileNames

        // Resolved before the delete: reading `memories` afterwards depends on
        // whether the @Query has already refreshed, which isn't guaranteed
        // within this call. The page moves to the memory that slides into this
        // slot, or back one when this was the last.
        let successor = index + 1 < list.count ? list[index + 1] : (index > 0 ? list[index - 1] : nil)
        let successorID = successor?.persistentModelID

        modelContext.delete(memory)
        // Persisted before the photos leave disk. Relying on the autosave meant
        // a suspend in between left the memory in the store with its images
        // already gone — a card that could never render again.
        do {
            try modelContext.save()
        } catch {
            // The row survived, so its photos have to as well.
            modelContext.rollback()
            return
        }

        for name in fileNames {
            LocalStore.shared.deleteImage(named: name)
        }

        guard let successorID else {
            dismiss()
            return
        }
        withAnimation {
            currentID = successorID
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

    /// A decoded photo together with the crop stored for it. The crop travels
    /// with the image instead of being looked up by position: a photo whose file
    /// fails to decode is dropped from this array, so its index no longer lines
    /// up with `memory.allImageFileNames` and every later photo would be framed
    /// with its neighbour's crop.
    private struct LoadedPhoto {
        let image: UIImage
        let crop: CGPoint
    }

    @State private var photos: [LoadedPhoto] = []
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
            let crops = names.indices.map { memory.cropOffset(at: $0) }
            let loaded = await Task.detached(priority: .userInitiated) {
                // Downsampled so a full carousel of large photos can't exhaust
                // memory and drop the later ones. The source index is carried
                // through so the crop can be matched back to the right photo.
                names.enumerated().compactMap { index, name -> (UIImage, Int)? in
                    LocalStore.shared.loadDownscaledImage(named: name, maxPixel: 1400).map { ($0, index) }
                }
            }.value
            photos = loaded.map { LoadedPhoto(image: $0.0, crop: crops[$0.1]) }
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
            if photos.count > 1 {
                TabView(selection: $photoIndex) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                        photoPage(croppedPhoto(photo, side: side))
                            .tag(index)
                    }
                }
                .tabViewStyle(.page)
            } else if let photo = photos.first {
                photoPage(croppedPhoto(photo, side: side))
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
    private func croppedPhoto(_ photo: LoadedPhoto, side: CGFloat) -> some View {
        let img = photo.image
        let position = photo.crop
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
