import SwiftUI
import SwiftData
import UIKit
import Combine

/// Bottom tab bar sections. Favorites sits leftmost, but Library is the
/// default landing tab so the app never opens on an empty favorites screen.
private enum AppTab {
    case favorites, library, timeline
}

/// A year's worth of memories in the timeline layout, split into months.
private struct TimelineYearGroup: Identifiable {
    let year: Int
    let months: [TimelineMonthGroup]

    var id: Int { year }
    var itemCount: Int { months.reduce(0) { $0 + $1.items.count } }
}

private struct TimelineMonthGroup: Identifiable {
    let month: Int
    let items: [Memory]

    var id: Int { month }

    /// Localized, uppercased month name (e.g. "MAY" / "MAYO").
    var title: String {
        guard let first = items.first else { return "" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MMMM"
        return formatter.string(from: first.date).uppercased()
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Memory.order, order: .reverse) private var memories: [Memory]

    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @State private var showSplash = true
    @State private var showAddSheet = false
    @State private var selectedIndex: Int?
    @State private var isFirstLaunch = true
    @State private var selectedTag: MemoryTag = .none
    @State private var showExport = false
    @State private var selectedTab: AppTab = .library

    private var filteredMemories: [Memory] {
        if selectedTag == .none { return memories }
        return memories.filter { $0.tag == selectedTag.rawValue }
    }

    /// Favorited memories within the active category filter.
    private var favoriteMemories: [Memory] {
        filteredMemories.filter { $0.isFavorite }
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if showSplash {
                SplashView(showSplash: $showSplash, isFirstLaunch: isFirstLaunch)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            } else {
                memoriesScreen
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
        .onChange(of: scenePhase) { _, newValue in
            // Safety net for changes that reach disk without an explicit save
            // (autosaved edits) before the app leaves the foreground.
            if newValue == .background {
                syncData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            // Mirrors every persisted change (including edits, which don't
            // alter the memory count) to the widget and watch. Downstream
            // providers skip work when nothing actually changed.
            syncData()
        }
        .onChange(of: showSplash) { _, newValue in
            if !newValue && !hasLaunchedBefore {
                hasLaunchedBefore = true
            }
        }
    }

    // MARK: - Memories screen (tab bar: Library + Timeline)

    private var memoriesScreen: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $selectedTab) {
                favoritesTab
                    .tag(AppTab.favorites)
                    .tabItem {
                        Label(String(localized: "tab.favorites", defaultValue: "Favorites"), systemImage: "heart")
                    }

                libraryTab
                    .tag(AppTab.library)
                    .tabItem {
                        Label(String(localized: "tab.library", defaultValue: "Library"), systemImage: "square.grid.2x2")
                    }

                timelineTab
                    .tag(AppTab.timeline)
                    .tabItem {
                        Label(String(localized: "tab.timeline", defaultValue: "Timeline"), systemImage: "calendar")
                    }
            }
        }
        .tint(AppTheme.accent)
        .sheet(isPresented: Binding(
            get: { selectedIndex != nil },
            set: { if !$0 { selectedIndex = nil } }
        )) {
            if let idx = selectedIndex {
                MemoryDetailView(startIndex: idx, filterTag: selectedTag)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMemoryView(nextOrder: memories.count)
                // Page-sized on iPad/Mac so the square photo plus the form
                // fit; no effect on iPhone.
                .presentationSizing(.page)
        }
        .sheet(isPresented: $showExport) {
            ExportAlbumView()
        }
    }

    // MARK: - Library tab (grid feed)

    private var libraryTab: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                chipsRow

                if memories.isEmpty {
                    emptyState
                } else if filteredMemories.isEmpty {
                    filterEmptyView
                } else {
                    feedCards
                }
            }
            .frame(maxWidth: AppTheme.Layout.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Timeline tab (chronological)

    private var timelineTab: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                chipsRow

                if memories.isEmpty {
                    emptyState
                } else if filteredMemories.isEmpty {
                    filterEmptyView
                } else {
                    timelineSections
                }
            }
            .frame(maxWidth: AppTheme.Layout.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Favorites tab

    private var favoritesTab: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                chipsRow

                if memories.isEmpty {
                    emptyState
                } else if favoriteMemories.isEmpty {
                    favoritesEmptyView
                } else {
                    ForEach(Array(favoriteMemories.enumerated()), id: \.element.persistentModelID) { _, memory in
                        MemoryCardView(memory: memory) {
                            selectMemory(memory)
                        }
                    }
                }
            }
            .frame(maxWidth: AppTheme.Layout.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private var favoritesEmptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(AppTheme.textSecondary)
            Text("favorites.empty")
                .font(AppTheme.Font.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 32)
    }

    /// Category filter chips, shown on both tabs once there are memories.
    @ViewBuilder
    private var chipsRow: some View {
        if !memories.isEmpty {
            CategoryChips(selected: $selectedTag)
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
    }

    /// Shared header above the tab content: the app name (small, gray) over the
    /// current section's large title. The title cross-fades (blur replace) when
    /// the section changes. Custom (not a native large title) so the app name
    /// can sit above the title and the change can be animated.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("app.name")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(sectionTitle)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                    .id(selectedTab)
                    .transition(.blurReplace)
            }

            Spacer(minLength: 8)

            headerButtons
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.28), value: selectedTab)
    }

    /// Large title for the active section.
    private var sectionTitle: LocalizedStringKey {
        switch selectedTab {
        case .favorites: "tab.favorites"
        case .library: "tab.library"
        case .timeline: "tab.timeline"
        }
    }

    /// Add (+) and an overflow menu (⋮), each inside a gray circle.
    private var headerButtons: some View {
        HStack(spacing: 10) {
            Button { showAddSheet = true } label: {
                navBarIcon("plus")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("toolbar.add"))

            Menu {
                Button { showExport = true } label: {
                    Label("toolbar.export", systemImage: "square.and.arrow.up")
                }
            } label: {
                navBarIcon("ellipsis")
            }
            .accessibilityLabel(Text("toolbar.more"))
        }
    }

    /// Glyph in a gray circle (matches the mockup on iOS 18 and 26).
    private func navBarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(width: 38, height: 38)
            .background(Color(.systemGray5), in: Circle())
    }

    private var filterEmptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(AppTheme.textSecondary)
            Text("filter.empty")
                .font(AppTheme.Font.body)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Feed layout

    @ViewBuilder
    private var feedCards: some View {
        ForEach(Array(filteredMemories.enumerated()), id: \.element.persistentModelID) { _, memory in
            MemoryCardView(memory: memory) {
                selectMemory(memory)
            }
        }

        footer
    }

    // MARK: - Timeline layout

    @ViewBuilder
    private var timelineSections: some View {
        ForEach(timelineGroups) { yearGroup in
            Section {
                ForEach(yearGroup.months) { monthGroup in
                    monthSubheader(monthGroup.title)

                    ForEach(Array(monthGroup.items.enumerated()), id: \.element.persistentModelID) { index, memory in
                        TimelineRow(
                            memory: memory,
                            isFirst: index == 0,
                            isLast: index == monthGroup.items.count - 1
                        ) {
                            selectMemory(memory)
                        }
                    }
                }
            } header: {
                timelineYearHeader(yearGroup.year, count: yearGroup.itemCount)
            }
        }

        Color.clear.frame(height: 40)
    }

    /// Filtered memories grouped by year, then by month, newest first.
    private var timelineGroups: [TimelineYearGroup] {
        let calendar = Calendar.current
        let sorted = filteredMemories.sorted { $0.date > $1.date }
        let byYear = Dictionary(grouping: sorted) { calendar.component(.year, from: $0.date) }

        return byYear.keys.sorted(by: >).map { year in
            let yearItems = byYear[year] ?? []
            let byMonth = Dictionary(grouping: yearItems) { calendar.component(.month, from: $0.date) }
            let months = byMonth.keys.sorted(by: >).map { month in
                TimelineMonthGroup(month: month, items: byMonth[month] ?? [])
            }
            return TimelineYearGroup(year: year, months: months)
        }
    }

    private func monthSubheader(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 46)
            .padding(.trailing, 20)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }

    private func timelineYearHeader(_ year: Int, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(year))
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("\(count)")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.systemGray5), in: Capsule())

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(AppTheme.background)
    }

    private func selectMemory(_ memory: Memory) {
        // Index within the filtered set so the detail pager swipes through the
        // same memories the feed is currently showing.
        if let index = filteredMemories.firstIndex(where: { $0.persistentModelID == memory.persistentModelID }) {
            selectedIndex = index
        }
    }

    // MARK: - Empty state (only when there are no memories at all)

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.circle")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(AppTheme.accent)

            Text("add.title")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("add.subtitle")
                .font(AppTheme.Font.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("add.button")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.vertical, 60)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 4) {
            Text("footer.count \(memories.count)")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)

            Text("footer.madeWith")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 48)
    }

    // MARK: - Recovery from files

    /// SwiftData is the source of truth; `memories.json` is only a recovery
    /// snapshot used when the store comes up empty (e.g. it was reset after a
    /// migration failure — see `V_AppApp`). Reconciling on every launch is
    /// avoided so the two layers can't drift or fight.
    private func importFromFilesIfNeeded() {
        guard memories.isEmpty else { return }

        let exported = LocalStore.shared.loadMetadata()
        guard !exported.isEmpty else { return }

        let formatter = ISO8601DateFormatter()

        for item in exported where !item.imageFileName.isEmpty {
            let memory = Memory(
                imageFileName: item.imageFileName,
                message: item.message,
                notes: item.notes,
                date: formatter.date(from: item.date) ?? .now,
                order: item.order,
                cropOffsetX: item.cropOffsetX,
                cropOffsetY: item.cropOffsetY,
                tag: item.tag,
                extraImageFileNames: item.extraImageFileNames,
                extraCropOffsetsX: item.extraCropOffsetsX ?? [],
                extraCropOffsetsY: item.extraCropOffsetsY ?? [],
                isFavorite: item.isFavorite ?? false
            )
            modelContext.insert(memory)
        }
    }

    // MARK: - Sync data to files and widget

    private func syncData() {
        LocalStore.shared.exportMetadata(from: memories)
        WidgetDataProvider.update(with: memories)
        WatchSyncManager.shared.sync(memories)
    }
}

// MARK: - Category chips

/// Horizontal, scrollable row of category filter chips that scales past a
/// segmented control's few slots. One typographic family; color appears only
/// on the active chip (system tint), everything else in label/secondary. No
/// dividers or shadows; respects Dynamic Type and the system accent color.
///
/// The app's category type is `MemoryTag` (already `String, CaseIterable,
/// Identifiable`), so the chips bind to it directly instead of a parallel
/// `Category` enum disconnected from the stored data.
struct CategoryChips: View {
    @Binding var selected: MemoryTag

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MemoryTag.allCases) { category in
                    chip(category)
                }
            }
            // Padding lives on the content (not the ScrollView) so the first
            // chip aligns with the layout margin while chips still scroll
            // edge-to-edge.
            .padding(.horizontal)
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func chip(_ category: MemoryTag) -> some View {
        let isSelected = selected == category
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selected = category }
        } label: {
            Text(category == .none ? String(localized: "filter.all") : category.label)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 15)
                .padding(.vertical, 7)
                .background {
                    Capsule().fill(isSelected ? AppTheme.accent : Color(.systemGray5))
                }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Memory.self, inMemory: true)
}
