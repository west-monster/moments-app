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

    private var usedTags: [MemoryTag] {
        let tags = Set(memories.compactMap { MemoryTag(rawValue: $0.tag) }.filter { $0 != .none })
        return MemoryTag.allCases.filter { tags.contains($0) }
    }

    private var filteredMemories: [Memory] {
        memories.filter { m in
            if m.tag.isEmpty {
                return includeUntagged
            }
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
                                .font(.system(size: 11, weight: .bold))
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
                                    count: memories.filter { $0.tag.isEmpty }.count,
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
                                    .font(.system(size: 13, weight: .medium))
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
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }

                VStack(spacing: 8) {
                    Rectangle()
                        .fill(AppTheme.divider)
                        .frame(height: 1)

                    Text("export.count \(filteredMemories.count)")
                        .font(.system(size: 12, weight: .medium))
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
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Text("export.pdf")
                                .font(.system(size: 15, weight: .semibold))
                                .tracking(0.5)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(filteredMemories.isEmpty ? AppTheme.textSecondary : AppTheme.accent)
                        .clipShape(Capsule())
                    }
                    .disabled(filteredMemories.isEmpty || isExporting)
                    .padding(.horizontal, 20)
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
                selectedTags = Set(usedTags.map(\.rawValue))
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Text("\(count)")
                .font(.system(size: 13, weight: .semibold))
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
                    let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    ac.completionWithItemsHandler = { _, _, _, _ in
                        isExporting = false
                        dismiss()
                    }
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = scene.keyWindow?.rootViewController {
                        var top = root
                        while let presented = top.presentedViewController { top = presented }
                        top.present(ac, animated: true)
                    } else {
                        isExporting = false
                    }
                } else {
                    isExporting = false
                }
            }
        }
    }
}
