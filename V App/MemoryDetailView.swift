import SwiftUI
import SwiftData
import UIKit

struct MemoryDetailView: View {
    @Query(sort: \Memory.order, order: .reverse) private var allMemories: [Memory]
    let startIndex: Int
    let filterTag: MemoryTag
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentIndex: Int
    @State private var contentOpacity: Double = 0
    @State private var dragOffset: CGSize = .zero
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @State private var showShareSheet = false

    init(startIndex: Int, filterTag: MemoryTag = .none) {
        self.startIndex = startIndex
        self.filterTag = filterTag
        _currentIndex = State(initialValue: startIndex)
    }

    /// The memories the pager swipes through — kept in sync with the feed's
    /// active tag filter so it shows the same set the user tapped from.
    private var memories: [Memory] {
        if filterTag == .none { return allMemories }
        return allMemories.filter { $0.tag == filterTag.rawValue }
    }

    private var dragProgress: CGFloat {
        min(abs(dragOffset.height) / 300, 1.0)
    }

    private var detailBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        ZStack {
            detailBackground
                .ignoresSafeArea()
                .opacity(1 - dragProgress * 0.5)

            if memories.isEmpty {
                Color.clear.onAppear { dismiss() }
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(memories.enumerated()), id: \.element.persistentModelID) { index, memory in
                        MemoryPageView(memory: memory)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .offset(dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 30, coordinateSpace: .global)
                        .onChanged { value in
                            if abs(value.translation.height) > abs(value.translation.width) {
                                dragOffset = CGSize(width: 0, height: value.translation.height)
                            }
                        }
                        .onEnded { value in
                            if abs(value.translation.height) > 120 {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    dragOffset = .zero
                                }
                            }
                        }
                )

                VStack {
                    pageIndicator
                        .padding(.top, 60)
                    Spacer()
                }
                .opacity(contentOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                contentOpacity = 1
            }
        }
        .overlay(alignment: .topTrailing) {
            circleButton("xmark", color: AppTheme.textPrimary) { dismiss() }
                .padding(10)
                .opacity(contentOpacity)
        }
        .overlay(alignment: .bottom) {
            // Bottom-centered so iPadOS window controls (top corners) can't
            // cover it, and the actions stay thumb-reachable on iPhone.
            HStack(spacing: 12) {
                circleButton("trash", color: .red) { showDeleteConfirmation = true }
                circleButton("pencil", color: AppTheme.accent) { showEditSheet = true }
                circleButton("square.and.arrow.up", color: AppTheme.accent) { showShareSheet = true }
            }
            .padding(.bottom, 20)
            .opacity(contentOpacity)
        }
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

    /// Circular glass action button with a 48×48pt tap target around a 40pt
    /// visual circle (HIG minimum is 44pt).
    private func circleButton(_ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        PhotoPageIndicator(count: memories.count, current: currentIndex, inactiveColor: .white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
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
    @State private var images: [UIImage] = []
    @State private var photoIndex = 0
    @State private var pageSize: CGSize = .zero

    /// Photo block height: the square that fits the width on iPhone, capped
    /// by a fraction of the height so iPad/Mac landscape never overflows.
    private var carouselHeight: CGFloat {
        guard pageSize != .zero else { return 360 }
        return min(pageSize.width, AppTheme.Layout.contentMaxWidth, pageSize.height * 0.55)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            photoCarousel

            if !memory.message.isEmpty {
                VStack(spacing: 10) {
                    Rectangle()
                        .fill(AppTheme.accent)
                        .frame(width: 28, height: 2)

                    Text(memory.message)
                        .font(AppTheme.Font.message)
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 24)
            }

            if !memory.notes.isEmpty {
                Text(memory.notes)
                    .font(AppTheme.Font.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
            }

            HStack(spacing: 6) {
                if let t = MemoryTag(rawValue: memory.tag), t != .none {
                    Image(systemName: t.icon)
                        .font(AppTheme.Font.caption)
                    Text(t.label)
                        .font(AppTheme.Font.caption)
                        .tracking(1.5)
                        .textCase(.uppercase)

                    Text("·")
                        .font(AppTheme.Font.caption)
                }

                Text(memory.formattedDate)
                    .font(AppTheme.Font.caption)
                    .tracking(2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.top, 12)

            // Keeps the date clear of the floating action buttons at the
            // bottom of the pager.
            Spacer(minLength: 88)
        }
        .frame(maxWidth: AppTheme.Layout.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { pageSize = proxy.size }
                    .onChange(of: proxy.size) { _, newValue in pageSize = newValue }
            }
        }
        .task(id: memory.persistentModelID) {
            let names = memory.allImageFileNames
            let loaded = await Task.detached(priority: .userInitiated) {
                names.compactMap { LocalStore.shared.loadImage(named: $0) }
            }.value
            images = loaded
        }
    }

    // MARK: - Photo carousel

    /// Every photo renders as the same-size square using its stored crop, so
    /// the pager feels like uniform album pages instead of jumping between
    /// aspect ratios.
    @ViewBuilder
    private var photoCarousel: some View {
        let side = carouselHeight
        if images.count > 1 {
            VStack(spacing: 10) {
                TabView(selection: $photoIndex) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, img in
                        croppedPhoto(img, index: index, side: side)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: side, height: side)

                PhotoPageIndicator(count: images.count, current: photoIndex)
            }
        } else if let uiImage = images.first {
            croppedPhoto(uiImage, index: 0, side: side)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.cardBackground)
                .frame(width: side, height: side)
                .overlay { ProgressView() }
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
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
