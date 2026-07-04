import SwiftUI
import SwiftData
import UIKit
import Combine

/// Ways to view the memory collection.
enum FeedLayout: String {
    case feed
    case timeline
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Memory.order, order: .reverse) private var memories: [Memory]

    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @State private var showSplash = true
    @State private var showAddSheet = false
    @State private var selectedIndex: Int?
    @State private var headerAppeared = false
    @State private var isFirstLaunch = true
    @State private var selectedTag: MemoryTag = .none
    @State private var showExport = false
    @State private var showFilterMenu = false
    @State private var showThemeMenu = false
    @AppStorage("feedLayout") private var layout = FeedLayout.feed

    @AppStorage("appearance") private var appearance = AppTheme.Appearance.system

    @State private var topInset: CGFloat = 0

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
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            } else {
                albumFeed
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: showSplash)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { topInset = proxy.safeAreaInsets.top }
                    .onChange(of: proxy.safeAreaInsets.top) { _, newValue in topInset = newValue }
            }
        )
        .overlay {
            // Opaque safe-area cap sized to the status bar / notch / Dynamic
            // Island, drawn above all content so nothing is clipped by it.
            VStack(spacing: 0) {
                AppTheme.background
                    .frame(height: topInset)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
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

    // MARK: - Feed principal

    private var albumFeed: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                feedScroll
                    .opacity(layout == .feed ? 1 : 0)
                    .allowsHitTesting(layout == .feed)

                timelineScroll
                    .opacity(layout == .timeline ? 1 : 0)
                    .allowsHitTesting(layout == .timeline)
            }
            .animation(.easeInOut(duration: 0.3), value: layout)

            bottomToolbar
                .padding(.bottom, 24)

            filterMenuOverlay
            themeMenuOverlay
        }
        .fullScreenCover(isPresented: Binding(
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

    private var feedScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                header
                    .padding(.bottom, 8)

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

    private var timelineScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                header
                    .padding(.bottom, 8)

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

    // MARK: - Feed layouts

    @ViewBuilder
    private var feedCards: some View {
        ForEach(Array(filteredMemories.enumerated()), id: \.element.persistentModelID) { index, memory in
            MemoryCardView(memory: memory) {
                selectMemory(memory)
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

        Color.clear.frame(height: 96)
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
            .font(AppTheme.Font.caption)
            .tracking(2)
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
                .font(.system(.title, design: .default).weight(.black))
                .foregroundStyle(AppTheme.textPrimary)

            Text("\(count)")
                .font(AppTheme.Font.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppTheme.cardBackground, in: Capsule())

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 48)

            AppTheme.sectionTitle(String(localized: "feed.header"))
                .opacity(headerAppeared ? 1 : 0)

            Rectangle()
                .fill(AppTheme.accent)
                .frame(width: headerAppeared ? 36 : 0, height: 2)

            HighlightHeadline(text: String(localized: "feed.subtitle"), font: AppTheme.Font.hero, tracking: -1.2)
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
                .font(.system(.title2, design: .default).weight(.bold))
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
                        .font(AppTheme.Font.chip)
                    Text("add.button")
                        .font(AppTheme.Font.chip)
                        .tracking(0.5)
                }
                .foregroundStyle(AppTheme.onAccent)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppTheme.accent)
                .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 32)
    }

    // MARK: - Bottom toolbar

    /// Editorial floating pill: solid surface with a hard 1px border instead
    /// of translucent material; the add button is the single accent-filled
    /// element. Compact width (iPhone) shows icons only; regular width
    /// (iPad/Mac) adds monospaced eyebrow labels under each icon.
    private var bottomToolbar: some View {
        HStack(spacing: horizontalSizeClass == .regular ? 2 : 4) {
            toolbarItem("plus", "toolbar.add", tint: AppTheme.onAccent, labelTint: AppTheme.accent, iconBackground: AppTheme.accent) {
                showAddSheet = true
            }
            toolbarItem(layout == .feed ? "calendar.day.timeline.left" : "square.grid.2x2.fill", "toolbar.view") {
                layout = layout == .feed ? .timeline : .feed
            }
            toolbarItem("line.3.horizontal.decrease", "toolbar.filter") { open($showFilterMenu) }
            toolbarItem("circle.lefthalf.filled", "toolbar.theme") { open($showThemeMenu) }
            toolbarItem("doc.richtext", "toolbar.export") { showExport = true }
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 10 : 6)
        .padding(.vertical, horizontalSizeClass == .regular ? 7 : 6)
        .background(toolbarSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 10, y: 4)
    }

    private var toolbarSurface: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground)
    }

    /// Button icons take the purple highlight color in light mode, pairing
    /// the bar with the headline blocks; in dark they stay near-white.
    private var toolbarForeground: Color {
        colorScheme == .dark ? AppTheme.textPrimary : AccentPalette.electricPurple
    }

    private var toolbarSecondaryForeground: Color {
        AppTheme.textSecondary
    }

    @ViewBuilder
    private func toolbarItem(
        _ icon: String,
        _ labelKey: LocalizedStringKey,
        tint: Color? = nil,
        labelTint: Color? = nil,
        iconBackground: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let iconView = Image(systemName: icon)
            .font(.system(size: horizontalSizeClass == .regular ? 19 : 17, weight: .semibold))
            .foregroundStyle(tint ?? toolbarForeground)
            .frame(width: 34, height: 34)
            .background(iconBackground ?? .clear, in: Circle())

        Button(action: action) {
            if horizontalSizeClass == .regular {
                VStack(spacing: 4) {
                    iconView
                    Text(labelKey)
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(labelTint ?? toolbarSecondaryForeground)
                }
                .frame(width: 80, height: 58)
                .contentShape(Rectangle())
            } else {
                iconView
                    .frame(width: 54, height: 46)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(MenuPressStyle())
    }

    private func open(_ flag: Binding<Bool>) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { flag.wrappedValue = true }
    }

    private func close(_ flag: Binding<Bool>) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { flag.wrappedValue = false }
    }

    // MARK: - Filter slide-up menu

    @ViewBuilder
    private var filterMenuOverlay: some View {
        if showFilterMenu {
            SlideUpMenu(isPresented: $showFilterMenu) {
                let tags = Array(MemoryTag.allCases.reversed())
                VStack(spacing: 0) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { index, t in
                        Button {
                            withAnimation(.spring(response: 0.3)) { selectedTag = t }
                            close($showFilterMenu)
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: t.icon)
                                    .font(.system(size: 19, weight: .medium))
                                    .frame(width: 28)

                                Text(t == .none ? String(localized: "filter.all") : t.label)
                                    .font(.system(.body, design: .default).weight(.medium))

                                Spacer()

                                if selectedTag == t {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .foregroundStyle(selectedTag == t ? AppTheme.accent : AppTheme.textPrimary)
                            .contentShape(Rectangle())
                            .padding(.horizontal, 22)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(MenuPressStyle())
                        .staggered(index)
                    }
                }
            }
        }
    }

    // MARK: - Theme slide-up menu

    @ViewBuilder
    private var themeMenuOverlay: some View {
        if showThemeMenu {
            SlideUpMenu(isPresented: $showThemeMenu) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(String(localized: "theme.appearance", defaultValue: "Appearance"))
                        .font(AppTheme.Font.eyebrow)
                        .tracking(2)
                        .foregroundStyle(AppTheme.accent)
                        .staggered(0)

                    HStack(spacing: 10) {
                        ForEach(Array(AppTheme.Appearance.allCases.enumerated()), id: \.offset) { index, mode in
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { appearance = mode }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 20, weight: .medium))
                                    Text(mode.label)
                                        .font(AppTheme.Font.chip)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(appearance == mode ? AppTheme.onAccent : AppTheme.textPrimary)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(appearance == mode ? AppTheme.accent : AppTheme.cardBackground)
                                )
                            }
                            .buttonStyle(MenuPressStyle())
                            .staggered(index + 1)
                        }
                    }

                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
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
                .font(AppTheme.Font.caption)
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, 8)

            Text("footer.madeWith")
                .font(.system(.caption, design: .serif).weight(.medium))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                .padding(.bottom, 100)
        }
        .padding(.top, 12)
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
                extraCropOffsetsY: item.extraCropOffsetsY ?? []
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

#Preview {
    ContentView()
        .modelContainer(for: Memory.self, inMemory: true)
}

// MARK: - Slide-up container

/// Dimmed backdrop + bottom sheet with an interactive drag-to-dismiss that
/// follows the finger, plus a rubber-band spring when released below the
/// dismiss threshold. The sheet's contents animate in via the `.staggered`
/// modifier applied by callers.
private struct SlideUpMenu<Content: View>: View {
    @Binding var isPresented: Bool
    private let content: Content

    @State private var dragY: CGFloat = 0

    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .opacity(0.35 * (1 - dragProgress))
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture { close() }

            VStack(spacing: 0) {
                Capsule()
                    .fill(AppTheme.textSecondary.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                content
            }
            .padding(.bottom, 12)
            .frame(maxWidth: AppTheme.Layout.formMaxWidth)
            .background(AppTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AppTheme.divider, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
            .offset(y: dragY)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Follow downward drags 1:1; rubber-band upward pulls.
                        dragY = value.translation.height > 0
                            ? value.translation.height
                            : value.translation.height / 4
                    }
                    .onEnded { value in
                        if value.translation.height > 90 || value.predictedEndTranslation.height > 200 {
                            close()
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { dragY = 0 }
                        }
                    }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .zIndex(20)
    }

    private var dragProgress: CGFloat {
        min(max(dragY, 0) / 400, 1)
    }

    private func close() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            isPresented = false
        }
    }
}

// MARK: - Staggered reveal

/// Fades and lifts a view into place with a delay proportional to its index,
/// producing a cascading reveal for menu rows.
private struct StaggeredItem: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85).delay(Double(index) * 0.03)) {
                    shown = true
                }
            }
            .onDisappear { shown = false }
    }
}

private extension View {
    func staggered(_ index: Int) -> some View {
        modifier(StaggeredItem(index: index))
    }
}

// MARK: - Press feedback

/// Subtle scale + dim while a menu row / control is held.
private struct MenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
