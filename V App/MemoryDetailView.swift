import SwiftUI
import SwiftData
import UIKit

struct MemoryDetailView: View {
    @Query(sort: \Memory.order, order: .reverse) private var memories: [Memory]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentIndex: Int
    @State private var contentOpacity: Double = 0
    @State private var dragOffset: CGSize = .zero
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @State private var showShareSheet = false

    init(startIndex: Int) {
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
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
                        singleMemoryView(memory)
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
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(16)
            .opacity(contentOpacity)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 10) {
                Button { showDeleteConfirmation = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Button { showEditSheet = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Button { showShareSheet = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(16)
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
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if currentIndex < memories.count {
                ShareCardView(memory: memories[currentIndex], image: memories[currentIndex].uiImage)
            }
        }
    }

    // MARK: - Single memory page

    private func singleMemoryView(_ memory: Memory) -> some View {
        VStack(spacing: 0) {
            Spacer()

            photoCarousel(for: memory)

            if !memory.message.isEmpty {
                VStack(spacing: 10) {
                    Rectangle()
                        .fill(AppTheme.accent)
                        .frame(width: 28, height: 2)

                    Text(memory.message)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 24)
            }

            if !memory.notes.isEmpty {
                Text(memory.notes)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
            }

            HStack(spacing: 6) {
                if let t = MemoryTag(rawValue: memory.tag), t != .none {
                    Image(systemName: t.icon)
                        .font(.system(size: 10))
                    Text(t.label)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .textCase(.uppercase)

                    Text("·")
                        .font(.system(size: 11, weight: .bold))
                }

                Text(memory.formattedDate)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.top, 12)

            Spacer()
        }
    }

    // MARK: - Photo carousel

    @ViewBuilder
    private func photoCarousel(for memory: Memory) -> some View {
        let images = memory.allImages
        if images.count > 1 {
            TabView {
                ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 12)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: UIScreen.main.bounds.width)
        } else if let uiImage = images.first {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
        }
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<memories.count, id: \.self) { i in
                Capsule()
                    .fill(i == currentIndex ? AppTheme.accent : Color.white.opacity(0.5))
                    .frame(width: i == currentIndex ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.3), value: currentIndex)
            }
        }
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
