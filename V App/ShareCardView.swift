import SwiftUI
import UIKit

struct ShareCardView: View {
    let memory: Memory
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        storyCard
                            .padding(.horizontal, 24)

                        Button {
                            shareImage()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(AppTheme.Font.chip)
                                Text("share.button")
                                    .font(AppTheme.Font.chip)
                                    .tracking(0.5)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(AppTheme.accent)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle(String(localized: "share.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "form.cancel")) { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) { appeared = true }
            }
            .task {
                let fileName = memory.imageFileName
                guard !fileName.isEmpty else { return }
                image = await Task.detached(priority: .userInitiated) {
                    LocalStore.shared.loadImage(named: fileName)
                }.value
            }
        }
    }

    // MARK: - Story card preview

    private var storyCard: some View {
        VStack(spacing: 0) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 380)
                    .clipped()
            }

            VStack(spacing: 12) {
                Rectangle()
                    .fill(AppTheme.accent)
                    .frame(width: 28, height: 2)

                if !memory.message.isEmpty {
                    Text(memory.message)
                        .font(AppTheme.Font.message)
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                if !memory.notes.isEmpty {
                    Text(memory.notes)
                        .font(AppTheme.Font.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .lineLimit(3)
                }

                HStack(spacing: 6) {
                    if let t = MemoryTag(rawValue: memory.tag), t != .none {
                        Image(systemName: t.icon)
                            .font(AppTheme.Font.caption)
                        Text(t.label)
                            .font(AppTheme.Font.caption)
                            .tracking(1)
                            .textCase(.uppercase)

                        Text("·")
                            .font(AppTheme.Font.caption)
                    }

                    Text(memory.formattedDate)
                        .font(AppTheme.Font.caption)
                        .tracking(1)
                        .textCase(.uppercase)
                }
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Render & share

    private func shareImage() {
        guard let rendered = renderStoryImage() else { return }
        ShareHelper.present([rendered])
    }

    private func renderStoryImage() -> UIImage? {
        let width: CGFloat = 1080
        let imageHeight: CGFloat = 1200
        let padding: CGFloat = 60
        let accentColor = UIColor(red: 0.33, green: 0.53, blue: 1.0, alpha: 1.0)
        let bgColor = UIColor.systemBackground
        let textColor = UIColor.label
        let secondaryColor = UIColor.secondaryLabel
        let serifDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withDesign(.serif)
            ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)

        var totalHeight: CGFloat = 0
        let textWidth = width - padding * 2

        totalHeight += imageHeight
        totalHeight += 50

        var messageHeight: CGFloat = 0
        if !memory.message.isEmpty {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineSpacing = 6
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont(descriptor: serifDescriptor, size: 44),
                .foregroundColor: textColor,
                .paragraphStyle: style
            ]
            messageHeight = (memory.message as NSString).boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, attributes: attrs, context: nil
            ).height + 10
            totalHeight += messageHeight + 20
        }

        var notesHeight: CGFloat = 0
        if !memory.notes.isEmpty {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineSpacing = 5
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont(descriptor: serifDescriptor, size: 32),
                .foregroundColor: secondaryColor,
                .paragraphStyle: style
            ]
            notesHeight = (memory.notes as NSString).boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, attributes: attrs, context: nil
            ).height + 10
            totalHeight += notesHeight + 16
        }

        totalHeight += 40 + 80

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: totalHeight))
        return renderer.image { ctx in
            bgColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: width, height: totalHeight)))

            var y: CGFloat = 0

            if let img = image {
                let imgRect = CGRect(x: 0, y: 0, width: width, height: imageHeight)
                // Aspect-fill the slot and center-crop, instead of stretching.
                ctx.cgContext.saveGState()
                ctx.cgContext.addRect(imgRect)
                ctx.cgContext.clip()
                let imgAspect = img.size.width / img.size.height
                let slotAspect = imgRect.width / imgRect.height
                var drawRect = imgRect
                if imgAspect > slotAspect {
                    let drawW = imgRect.height * imgAspect
                    drawRect = CGRect(x: imgRect.midX - drawW / 2, y: imgRect.minY, width: drawW, height: imgRect.height)
                } else {
                    let drawH = imgRect.width / imgAspect
                    drawRect = CGRect(x: imgRect.minX, y: imgRect.midY - drawH / 2, width: imgRect.width, height: drawH)
                }
                img.draw(in: drawRect)
                ctx.cgContext.restoreGState()
                y = imageHeight
            }

            y += 30
            accentColor.setFill()
            ctx.fill(CGRect(x: width / 2 - 40, y: y, width: 80, height: 4))
            y += 20

            if !memory.message.isEmpty {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                style.lineSpacing = 6
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont(descriptor: serifDescriptor, size: 44),
                    .foregroundColor: textColor,
                    .paragraphStyle: style
                ]
                (memory.message as NSString).draw(
                    in: CGRect(x: padding, y: y, width: textWidth, height: messageHeight),
                    withAttributes: attrs
                )
                y += messageHeight + 20
            }

            if !memory.notes.isEmpty {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                style.lineSpacing = 5
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont(descriptor: serifDescriptor, size: 32),
                    .foregroundColor: secondaryColor,
                    .paragraphStyle: style
                ]
                (memory.notes as NSString).draw(
                    in: CGRect(x: padding, y: y, width: textWidth, height: notesHeight),
                    withAttributes: attrs
                )
                y += notesHeight + 16
            }

            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: secondaryColor,
                .kern: 3
            ]

            var dateStr = memory.formattedDate.uppercased()
            if let t = MemoryTag(rawValue: memory.tag), t != .none {
                dateStr = t.label.uppercased() + "  ·  " + dateStr
            }
            let dateSize = (dateStr as NSString).size(withAttributes: dateAttrs)
            (dateStr as NSString).draw(
                at: CGPoint(x: (width - dateSize.width) / 2, y: y),
                withAttributes: dateAttrs
            )
        }
    }
}
