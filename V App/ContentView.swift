import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memory.order, order: .reverse) private var memories: [Memory]

    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @State private var showSplash = true
    @State private var showAddSheet = false
    @State private var selectedIndex: Int?
    @State private var headerAppeared = false
    @State private var isFirstLaunch = true
    @State private var selectedTag: MemoryTag = .none
    @State private var showExport = false

    private var filteredMemories: [Memory] {
        if selectedTag == .none { return memories }
        return memories.filter { $0.tag == selectedTag.rawValue }
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VergeGridBackground()

            if showSplash {
                SplashView(showSplash: $showSplash, isFirstLaunch: isFirstLaunch)
                    .transition(.opacity)
                    .zIndex(2)
            } else {
                albumFeed
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: showSplash)
        .onAppear {
            isFirstLaunch = !hasLaunchedBefore
            importFromFilesIfNeeded()
            syncData()
        }
        .onChange(of: memories.count) {
            syncData()
        }
        .onChange(of: showSplash) { _, newValue in
            if !newValue && !hasLaunchedBefore {
                hasLaunchedBefore = true
            }
        }
    }

    // MARK: - Feed principal

    private var albumFeed: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    header
                        .padding(.bottom, 8)

                    if !memories.isEmpty {
                        tagFilter
                            .padding(.bottom, 8)
                    }

                    if filteredMemories.isEmpty && !memories.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 32, weight: .thin))
                                .foregroundStyle(AppTheme.textSecondary)
                            Text("filter.empty")
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(.vertical, 40)
                    } else if memories.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(filteredMemories.enumerated()), id: \.element.persistentModelID) { index, memory in
                            MemoryCardView(memory: memory) {
                                if let realIndex = memories.firstIndex(where: { $0.persistentModelID == memory.persistentModelID }) {
                                    selectedIndex = realIndex
                                }
                            }

                            if index < filteredMemories.count - 1 {
                                Rectangle()
                                    .fill(AppTheme.divider)
                                    .frame(height: 1)
                                    .padding(.horizontal, 50)
                                    .padding(.vertical, 12)
                            }
                        }

                        footer
                    }
                }
            }

            if !memories.isEmpty {
                floatingMenu
                    .padding(.trailing, 20)
                    .padding(.bottom, 32)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedIndex != nil },
            set: { if !$0 { selectedIndex = nil } }
        )) {
            if let idx = selectedIndex {
                MemoryDetailView(startIndex: idx)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMemoryView(nextOrder: memories.count)
        }
        .sheet(isPresented: $showExport) {
            ExportAlbumView()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 48)

            AppTheme.sectionTitle(String(localized: "feed.header"))
                .opacity(headerAppeared ? 1 : 0)

            Rectangle()
                .fill(AppTheme.accent)
                .frame(width: headerAppeared ? 36 : 0, height: 2)

            Text("feed.subtitle")
                .font(.system(size: 38, weight: .black))
                .tracking(-1.2)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textPrimary)
                .opacity(headerAppeared ? 1 : 0)
                .offset(y: headerAppeared ? 0 : 20)

            Spacer().frame(height: 20)

            if !memories.isEmpty {
                Rectangle()
                    .fill(AppTheme.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 32)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7, blendDuration: 0).delay(0.1)) {
                headerAppeared = true
            }
        }
    }

    // MARK: - Empty state (solo cuando no hay recuerdos)

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.circle")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(AppTheme.accent)

            Text("add.title")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("add.subtitle")
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("add.button")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(0.5)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppTheme.accent)
                .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 32)
    }

    // MARK: - Floating menu

    private var floatingMenu: some View {
        Menu {
            Button {
                showAddSheet = true
            } label: {
                Label(String(localized: "add.button"), systemImage: "plus.circle")
            }

            Button {
                showExport = true
            } label: {
                Label(String(localized: "export.pdf"), systemImage: "doc.richtext")
            }
        } label: {
            ZStack {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 56, height: 56)
                    .shadow(color: AppTheme.accent.opacity(0.4), radius: 8, y: 4)

                Image(systemName: "house.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Tag filter

    private var tagFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MemoryTag.allCases) { t in
                    Button {
                        withAnimation(.spring(response: 0.3)) { selectedTag = t }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: t.icon)
                                .font(.system(size: 11))
                            Text(t == .none ? String(localized: "filter.all") : t.label)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(selectedTag == t ? .white : AppTheme.textSecondary)
                        .background(selectedTag == t ? AppTheme.accent : AppTheme.cardBackground, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 1)
                .padding(.horizontal, 32)

            Text("footer.count \(memories.count)")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, 8)

            Text("footer.madeWith")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                .padding(.bottom, 100)
        }
        .padding(.top, 12)
    }

    // MARK: - Import from files (recovery + manual loading)

    private func importFromFilesIfNeeded() {
        let exported = LocalStore.shared.loadMetadata()
        guard !exported.isEmpty else { return }

        let existingFileNames = Set(memories.map(\.cloudFileName))
        let formatter = ISO8601DateFormatter()

        for item in exported {
            guard !item.imageFileName.isEmpty,
                  !existingFileNames.contains(item.imageFileName) else { continue }

            let memory = Memory(
                imageFileName: item.imageFileName,
                message: item.message,
                notes: item.notes,
                date: formatter.date(from: item.date) ?? .now,
                order: item.order,
                cropOffsetX: item.cropOffsetX,
                cropOffsetY: item.cropOffsetY,
                tag: item.tag,
                extraImageFileNames: item.extraImageFileNames
            )
            modelContext.insert(memory)
        }
    }

    // MARK: - Sync data to files and widget

    private func syncData() {
        LocalStore.shared.exportMetadata(from: memories)
        WidgetDataProvider.update(with: memories)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Memory.self, inMemory: true)
}
