import SwiftUI
import SwiftData
import UIKit

struct ExportAlbumView: View {
    @Query(sort: \Memory.order, order: .reverse) private var memories: [Memory]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTags: Set<String> = []
    @State private var includeUntagged = true
    @State private var isExporting = false
    @State private var appeared = false
    /// `onAppear` fires again whenever the view comes back (returning from the
    /// share sheet, for one), and seeding the default selection there each time
    /// wiped out whatever the user had picked.
    @State private var didSeedSelection = false

    private var usedTags: [MemoryTag] {
        let tags = Set(memories.compactMap { MemoryTag(rawValue: $0.tag) }.filter { $0 != .none })
        return MemoryTag.allCases.filter { tags.contains($0) }
    }

    /// Memories with no category — or with one that no longer maps to a known
    /// `MemoryTag`. Both belong under "Uncategorized": an unrecognised tag gets
    /// no row of its own, so matching on the raw string alone dropped it from
    /// every export, "Select all" included, with nothing on screen to say so.
    private func isUntagged(_ memory: Memory) -> Bool {
        // Spelled out rather than `?? .none`: there, `.none` binds to
        // `Optional.none` and the check collapses to "is nil", which would let
        // genuinely uncategorised memories fall through as tagged.
        guard let tag = MemoryTag(rawValue: memory.tag) else { return true }
        return tag == .none
    }

    private var untaggedCount: Int {
        memories.filter(isUntagged).count
    }

    private var filteredMemories: [Memory] {
        memories.filter { m in
            if isUntagged(m) { return includeUntagged }
            return selectedTags.contains(m.tag)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("export.select")
                                .font(AppTheme.Font.eyebrow)
                                .tracking(2)
                                .foregroundStyle(AppTheme.accent)

                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    includeUntagged.toggle()
                                }
                            } label: {
                                tagRow(
                                    icon: "tag",
                                    label: String(localized: "export.uncategorized"),
                                    count: untaggedCount,
                                    isSelected: includeUntagged
                                )
                            }

                            ForEach(usedTags) { tag in
                                Button {
                                    withAnimation(.spring(response: 0.3)) {
                                        if selectedTags.contains(tag.rawValue) {
                                            selectedTags.remove(tag.rawValue)
                                        } else {
                                            selectedTags.insert(tag.rawValue)
                                        }
                                    }
                                } label: {
                                    tagRow(
                                        icon: tag.icon,
                                        label: tag.label,
                                        count: memories.filter { $0.tag == tag.rawValue }.count,
                                        isSelected: selectedTags.contains(tag.rawValue)
                                    )
                                }
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.cardBackground))

                        HStack {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedTags = Set(usedTags.map(\.rawValue))
                                    includeUntagged = true
                                }
                            } label: {
                                Text("export.selectAll")
                                    .font(AppTheme.Font.chip)
                                    .foregroundStyle(AppTheme.accent)
                            }

                            Spacer()

                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedTags.removeAll()
                                    includeUntagged = false
                                }
                            } label: {
                                Text("export.selectNone")
                                    .font(AppTheme.Font.chip)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: AppTheme.Layout.formMaxWidth)
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: 8) {
                    Rectangle()
                        .fill(AppTheme.divider)
                        .frame(height: 1)

                    Text("export.count \(filteredMemories.count)")
                        .font(AppTheme.Font.chip)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.top, 4)

                    Button {
                        exportPDF()
                    } label: {
                        HStack(spacing: 8) {
                            if isExporting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "doc.richtext")
                                    .font(AppTheme.Font.chip)
                            }
                            Text("export.pdf")
                                .font(.system(.headline, design: .default))
                                .tracking(0.5)
                        }
                        .foregroundStyle(filteredMemories.isEmpty ? .white : AppTheme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(filteredMemories.isEmpty ? AppTheme.textSecondary : AppTheme.accent)
                        .clipShape(Capsule())
                    }
                    .disabled(filteredMemories.isEmpty || isExporting)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: AppTheme.Layout.formMaxWidth)
                    .padding(.bottom, 8)
                }
            }
            .background(AppTheme.background)
            .navigationTitle(String(localized: "export.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "form.cancel")) { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .opacity(appeared ? 1 : 0)
            .onAppear {
                if !didSeedSelection {
                    didSeedSelection = true
                    selectedTags = Set(usedTags.map(\.rawValue))
                }
                withAnimation(.easeOut(duration: 0.4)) { appeared = true }
            }
        }
    }

    private func tagRow(icon: String, label: String, count: Int, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textSecondary.opacity(0.4))

            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 20)

            Text(label)
                .font(.system(.body, design: .default).weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Text("\(count)")
                .font(AppTheme.Font.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppTheme.background, in: Capsule())
        }
        .padding(.vertical, 4)
    }

    private func exportPDF() {
        guard !isExporting, !filteredMemories.isEmpty else { return }
        isExporting = true
        let snapshots = PDFExporter.snapshots(from: filteredMemories)
        let title = String(localized: "feed.subtitle")
        Task.detached {
            let url = PDFExporter.generate(from: snapshots, title: title)
            await MainActor.run {
                if let url {
                    ShareHelper.present([url]) {
                        isExporting = false
                        dismiss()
                    }
                } else {
                    isExporting = false
                }
            }
        }
    }
}
