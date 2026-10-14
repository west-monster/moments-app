import SwiftUI
import UIKit

struct ShareCardView: View {
    let memory: Memory
    @Environment(\.dismiss) private var dismiss
    @State private var photoState = PhotoState.loading
    @State private var appeared = false
    @State private var isRendering = false

    /// Distinguishes "still decoding" from "this memory has no photo". Sharing
    /// waits for the first but proceeds on the second — a memory whose file is
    /// missing used to leave the share button permanently disabled with nothing
    /// on screen explaining why.
    private enum PhotoState {
        case loading
        case ready(UIImage?)

        var image: UIImage? {
            if case .ready(let image) = self { return image }
            return nil
        }

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

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
                                if isRendering {
                                    ProgressView()
                                        .tint(AppTheme.onAccent)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(AppTheme.Font.chip)
                                }
                                Text("share.button")
                                    .font(AppTheme.Font.chip)
                                    .tracking(0.5)
                            }
                            .foregroundStyle(AppTheme.onAccent)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(AppTheme.accent)
                            .clipShape(Capsule())
                        }
                        .disabled(photoState.isLoading || isRendering)
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: AppTheme.Layout.formMaxWidth)
                    .frame(maxWidth: .infinity)
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
            .task(id: memory.imageFileName) {
                let fileName = memory.imageFileName
                guard !fileName.isEmpty else {
                    photoState = .ready(nil)
                    return
                }
                photoState = .loading
                let loaded = await Task.detached(priority: .userInitiated) {
                    // 1600px covers both the on-screen card and the 1080-wide
                    // render; the full-resolution decode was wasted here.
                    LocalStore.shared.loadDownscaledImage(named: fileName, maxPixel: 1600)
                }.value
                photoState = .ready(loaded)
            }
        }
    }

    // MARK: - Story card preview

    private var storyCard: some View {
        VStack(spacing: 0) {
            switch photoState {
            case .loading:
                Rectangle()
                    .fill(AppTheme.cardBackground)
                    .frame(height: photoHeight)
                    .overlay { ProgressView() }
            case .ready(let image):
                if let image {
                    croppedPhoto(image)
                }
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

    private let photoHeight: CGFloat = 380

    /// Aspect-fills the preview band using the crop the user set on the memory,
    /// the same framing the feed card, the detail pager and the PDF use — and
    /// the same the rendered story image applies.
    private func croppedPhoto(_ image: UIImage) -> some View {
        GeometryReader { geo in
            let scale = max(geo.size.width / max(image.size.width, 1),
                            geo.size.height / max(image.size.height, 1))
            let width = image.size.width * scale
            let height = image.size.height * scale

            Image(uiImage: image)
                .resizable()
                .frame(width: width, height: height)
                .offset(
                    x: -(width - geo.size.width) * memory.cropOffsetX,
                    y: -(height - geo.size.height) * memory.cropOffsetY
                )
        }
        .frame(height: photoHeight)
        .clipped()
    }

    // MARK: - Render & share

    private func shareImage() {
        guard !isRendering, !photoState.isLoading else { return }
        isRendering = true

        // Plain values captured here; the 1080-wide render itself runs off the
        // main thread so the button doesn't freeze the sheet.
        let content = StoryContent(
            message: memory.message,
            notes: memory.notes,
            formattedDate: memory.formattedDate,
            tag: memory.tag,
            crop: CGPoint(x: memory.cropOffsetX, y: memory.cropOffsetY)
        )
        let source = photoState.image

        Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                Self.renderStoryImage(content: content, photo: source)
            }.value
            isRendering = false
            if let rendered { ShareHelper.present([rendered]) }
        }
    }

    /// Everything the story render needs from the memory, as plain values.
    private struct StoryContent: Sendable {
        let message: String
        let notes: String
        let formattedDate: String
        let tag: String
        /// Square-crop position of the main photo (0...1), so the shared image
        /// is framed the way the user set it rather than centred.
        let crop: CGPoint
    }

    /// `nonisolated` on purpose: `View` conformance would otherwise infer
    /// main-actor isolation for this method, and the `Task.detached` above would
    /// hop straight back to the main thread — freezing the sheet for the whole
    /// 1080-wide render instead of avoiding it.
    nonisolated private static func renderStoryImage(content: StoryContent, photo: UIImage?) -> UIImage? {
        let memory = content
        let image: UIImage? = photo
        let width: CGFloat = 1080
        let imageHeight: CGFloat = 1200
        let padding: CGFloat = 60
        let accentColor = AppTheme.accentUIColor
        // Resolved for light explicitly: the app is light-only, and dynamic
        // colors have no trait collection to resolve against off the main thread.
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let bgColor = UIColor.systemBackground.resolvedColor(with: lightTraits)
        let textColor = UIColor.label.resolvedColor(with: lightTraits)
        let secondaryColor = UIColor.secondaryLabel.resolvedColor(with: lightTraits)
        let serifDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withDesign(.serif)
            ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)

        var totalHeight: CGFloat = 0
        let textWidth = width - padding * 2

        // Only reserved when there is a photo — counting it unconditionally left
        // a photo-less memory with 1200px of empty canvas above its text.
        if image != nil { totalHeight += imageHeight }
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

            if let img = image, img.size.width > 0, img.size.height > 0 {
                let imgRect = CGRect(x: 0, y: 0, width: width, height: imageHeight)
                // Aspect-fill the slot and position the overflow with the crop
                // the user set on the memory — the same math as
                // `SquareCropGeometry` and `PDFExporter.drawFilled`, so what
                // gets shared matches what the app shows. This used to
                // centre-crop and quietly discard that framing.
                ctx.cgContext.saveGState()
                ctx.cgContext.addRect(imgRect)
                ctx.cgContext.clip()
                let scale = max(imgRect.width / img.size.width, imgRect.height / img.size.height)
                let drawSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                img.draw(in: CGRect(
                    x: imgRect.minX - (drawSize.width - imgRect.width) * memory.crop.x,
                    y: imgRect.minY - (drawSize.height - imgRect.height) * memory.crop.y,
                    width: drawSize.width,
                    height: drawSize.height
                ))
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
