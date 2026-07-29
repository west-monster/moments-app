import UIKit

/// Plain-value description of a memory. Holds photo *file names* rather than
/// decoded images: `generate` resolves them one memory at a time while it
/// draws, so exporting never decodes a whole library into memory at once (and
/// nothing heavy happens on the main actor just to build the snapshots).
struct PDFMemorySnapshot: Sendable {
    let message: String
    let notes: String
    let formattedDate: String
    let imageFileNames: [String]
    /// Square-crop position per photo, aligned with `imageFileNames`, so the
    /// print reuses the framing chosen in the app.
    let crops: [CGPoint]
    let tag: String
}

enum PDFExporter {

    // MARK: - Page geometry

    /// A4 in points — the paper this album actually gets printed on.
    private static let pageSize = CGSize(width: 595.28, height: 841.89)
    /// ≈14mm, inside the non-printable edge of common home printers.
    private static let margin: CGFloat = 40
    /// Strip at the foot of each page reserved for the page number.
    private static let footerHeight: CGFloat = 18
    private static let gutter: CGFloat = 8
    /// Photos on one page before the rest flow onto a continuation page.
    private static let photosPerPage = 6

    /// Printable area, footer excluded.
    private static var contentRect: CGRect {
        CGRect(x: margin,
               y: margin,
               width: pageSize.width - margin * 2,
               height: pageSize.height - margin * 2 - footerHeight)
    }

    private static let inkColor = UIColor(white: 0.13, alpha: 1)
    private static let secondaryColor = UIColor(white: 0.45, alpha: 1)

    private static func serifFont(_ size: CGFloat) -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withDesign(.serif)
            ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        return UIFont(descriptor: descriptor, size: size)
    }

    // MARK: - Input

    static func snapshots(from memories: [Memory]) -> [PDFMemorySnapshot] {
        memories.map { m in
            let names = m.allImageFileNames
            return PDFMemorySnapshot(
                message: m.message,
                notes: m.notes,
                formattedDate: m.formattedDate,
                imageFileNames: names,
                crops: names.indices.map { m.cropOffset(at: $0) },
                tag: m.tag
            )
        }
    }

    private struct LoadedPhoto {
        let image: UIImage
        let crop: CGPoint
    }

    private static func loadFirst(_ snapshot: PDFMemorySnapshot) -> LoadedPhoto? {
        guard let name = snapshot.imageFileNames.first,
              let image = LocalStore.shared.loadImage(named: name) else { return nil }
        return LoadedPhoto(image: image, crop: snapshot.crops.first ?? CGPoint(x: 0.5, y: 0.5))
    }

    private static func load(_ snapshot: PDFMemorySnapshot) -> [LoadedPhoto] {
        snapshot.imageFileNames.enumerated().compactMap { index, name in
            guard let image = LocalStore.shared.loadImage(named: name) else { return nil }
            let crop = snapshot.crops.indices.contains(index)
                ? snapshot.crops[index]
                : CGPoint(x: 0.5, y: 0.5)
            return LoadedPhoto(image: image, crop: crop)
        }
    }

    // MARK: - Document

    static func generate(from snapshots: [PDFMemorySnapshot], title: String) -> URL? {
        guard !snapshots.isEmpty else { return nil }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let accent = AppTheme.accentUIColor

        let data = renderer.pdfData { context in
            context.beginPage()
            // Only the one photo the cover shows — `load` would decode the
            // whole first memory's gallery just to take its first element.
            drawCover(context.cgContext, title: title, hero: loadFirst(snapshots[0]), accent: accent)

            var pageNumber = 1
            var index = 0

            while index < snapshots.count {
                let snapshot = snapshots[index]
                let photos = load(snapshot)

                // Adaptive packing: two single-photo memories share a sheet;
                // anything with a gallery gets the page to itself. Both sides
                // are judged on the declared photo count — using the *loaded*
                // count here would drop a gallery whose files failed to decode
                // into a half page.
                if snapshot.imageFileNames.count <= 1,
                   index + 1 < snapshots.count,
                   snapshots[index + 1].imageFileNames.count <= 1 {
                    let next = snapshots[index + 1]
                    context.beginPage()
                    drawPairedPage(context.cgContext,
                                   first: (snapshot, photos),
                                   second: (next, load(next)),
                                   accent: accent)
                    drawPageNumber(pageNumber)
                    pageNumber += 1
                    index += 2
                    continue
                }

                context.beginPage()
                drawMemoryPage(context.cgContext,
                               snapshot: snapshot,
                               photos: Array(photos.prefix(photosPerPage)),
                               accent: accent)
                drawPageNumber(pageNumber)
                pageNumber += 1

                // Photos past the first page flow onto continuation sheets.
                var start = photosPerPage
                while start < photos.count {
                    let chunk = Array(photos[start..<min(start + photosPerPage, photos.count)])
                    context.beginPage()
                    drawOverflowPage(context.cgContext, snapshot: snapshot, photos: chunk, accent: accent)
                    drawPageNumber(pageNumber)
                    pageNumber += 1
                    start += photosPerPage
                }

                index += 1
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Moments-\(formatter.string(from: Date())).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Cover

    /// Full-bleed hero photo over the top of the sheet, title block beneath —
    /// an album cover rather than one line of type on an empty page.
    private static func drawCover(_ ctx: CGContext, title: String, hero: LoadedPhoto?, accent: UIColor) {
        var y: CGFloat

        if let hero {
            let heroHeight = pageSize.height * 0.58
            drawFilled(ctx, image: hero.image, crop: hero.crop,
                       in: CGRect(x: 0, y: 0, width: pageSize.width, height: heroHeight),
                       cornerRadius: 0)
            y = heroHeight + 54
        } else {
            y = pageSize.height * 0.36
        }

        let eyebrowAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: accent,
            .kern: 3
        ]
        let eyebrow = String(localized: "feed.header").uppercased() as NSString
        let eyebrowSize = eyebrow.size(withAttributes: eyebrowAttrs)
        eyebrow.draw(at: CGPoint(x: (pageSize.width - eyebrowSize.width) / 2, y: y), withAttributes: eyebrowAttrs)
        y += eyebrowSize.height + 14

        ctx.setFillColor(accent.cgColor)
        ctx.fill(CGRect(x: pageSize.width / 2 - 26, y: y, width: 52, height: 3))
        y += 26

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center
        titleStyle.lineSpacing = 2
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 38, weight: .black),
            .foregroundColor: inkColor,
            .paragraphStyle: titleStyle
        ]
        let titleWidth = pageSize.width - margin * 2
        let titleHeight = (title as NSString).boundingRect(
            with: CGSize(width: titleWidth, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin, attributes: titleAttrs, context: nil
        ).height
        (title as NSString).draw(
            in: CGRect(x: margin, y: y, width: titleWidth, height: titleHeight + 6),
            withAttributes: titleAttrs
        )
    }

    // MARK: - Pages

    /// One memory filling the sheet: the photo grid takes every point the
    /// caption doesn't need.
    private static func drawMemoryPage(_ ctx: CGContext, snapshot: PDFMemorySnapshot, photos: [LoadedPhoto], accent: UIColor) {
        let content = contentRect
        let caption = makeCaption(for: snapshot, width: content.width, compact: false)

        guard !photos.isEmpty else {
            drawCaption(ctx, caption, top: content.midY - caption.height / 2, in: content, accent: accent)
            return
        }

        let photoHeight = max(content.height - caption.height - 28, content.height * 0.45)
        let photoRect = CGRect(x: content.minX, y: content.minY, width: content.width, height: photoHeight)
        drawGrid(ctx, photos: photos, in: photoRect)
        drawCaption(ctx, caption, top: photoRect.maxY + 28, in: content, accent: accent)
    }

    /// Two single-photo memories stacked on one sheet, split by a hairline.
    private static func drawPairedPage(
        _ ctx: CGContext,
        first: (PDFMemorySnapshot, [LoadedPhoto]),
        second: (PDFMemorySnapshot, [LoadedPhoto]),
        accent: UIColor
    ) {
        let content = contentRect
        let separatorGap: CGFloat = 34
        let blockHeight = (content.height - separatorGap) / 2

        drawBlock(ctx, snapshot: first.0, photos: first.1, accent: accent,
                  in: CGRect(x: content.minX, y: content.minY, width: content.width, height: blockHeight))

        let separatorY = content.minY + blockHeight + separatorGap / 2
        ctx.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
        ctx.fill(CGRect(x: content.minX + content.width * 0.3, y: separatorY, width: content.width * 0.4, height: 0.7))

        drawBlock(ctx, snapshot: second.0, photos: second.1, accent: accent,
                  in: CGRect(x: content.minX, y: content.minY + blockHeight + separatorGap, width: content.width, height: blockHeight))
    }

    /// Half-sheet unit used by the paired layout.
    private static func drawBlock(_ ctx: CGContext, snapshot: PDFMemorySnapshot, photos: [LoadedPhoto], accent: UIColor, in rect: CGRect) {
        let caption = makeCaption(for: snapshot, width: rect.width, compact: true)

        guard !photos.isEmpty else {
            drawCaption(ctx, caption, top: rect.midY - caption.height / 2, in: rect, accent: accent)
            return
        }

        let photoHeight = max(rect.height - caption.height - 18, rect.height * 0.4)
        let photoRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: photoHeight)
        drawGrid(ctx, photos: photos, in: photoRect)
        drawCaption(ctx, caption, top: photoRect.maxY + 18, in: rect, accent: accent)
    }

    /// Continuation sheet: a small caption naming the memory, then the rest of
    /// its photos filling everything below.
    private static func drawOverflowPage(_ ctx: CGContext, snapshot: PDFMemorySnapshot, photos: [LoadedPhoto], accent: UIColor) {
        let content = contentRect

        let headerStyle = NSMutableParagraphStyle()
        headerStyle.alignment = .center
        headerStyle.lineBreakMode = .byTruncatingTail
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: secondaryColor,
            .kern: 2,
            .paragraphStyle: headerStyle
        ]
        let header = (snapshot.message.isEmpty ? snapshot.formattedDate : snapshot.message)
            .replacingOccurrences(of: "\n", with: " ")
            .uppercased() as NSString
        let headerHeight: CGFloat = 14
        header.draw(in: CGRect(x: content.minX, y: content.minY, width: content.width, height: headerHeight),
                    withAttributes: headerAttrs)

        ctx.setFillColor(accent.cgColor)
        ctx.fill(CGRect(x: pageSize.width / 2 - 18, y: content.minY + headerHeight + 8, width: 36, height: 2))

        let top = content.minY + headerHeight + 26
        drawGrid(ctx, photos: photos, in: CGRect(x: content.minX, y: top, width: content.width, height: content.maxY - top))
    }

    private static func drawPageNumber(_ number: Int) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: UIColor(white: 0.62, alpha: 1),
            .kern: 1
        ]
        let text = "\(number)" as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: (pageSize.width - size.width) / 2,
                              y: pageSize.height - margin / 2 - size.height),
                  withAttributes: attrs)
    }

    // MARK: - Photo grid

    /// Bounds on how far a cell may depart from a square. Cells are aspect-
    /// filled, so an extreme cell doesn't stretch the photo — it crops it to a
    /// sliver, which is worse. Two photos therefore stack as wide bands rather
    /// than splitting into two tall columns.
    private static let minCellAspect: CGFloat = 0.62
    private static let maxCellAspect: CGFloat = 1.35

    private static func columnCount(for count: Int) -> Int {
        switch count {
        case 1, 2: return 1
        default: return 2
        }
    }

    /// Cells filling `rect`, clamped to a printable aspect and centred in the
    /// band when the clamp leaves room. An odd photo on the last row spans the
    /// full width so a page never ends on a gap.
    private static func cellRects(count: Int, in rect: CGRect) -> [CGRect] {
        guard count > 0, rect.width > 0, rect.height > 0 else { return [] }
        let columns = columnCount(for: count)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let cellWidth = (rect.width - gutter * CGFloat(columns - 1)) / CGFloat(columns)

        let available = (rect.height - gutter * CGFloat(rows - 1)) / CGFloat(rows)
        let cellHeight = min(max(available, cellWidth * minCellAspect), cellWidth * maxCellAspect)

        let gridHeight = cellHeight * CGFloat(rows) + gutter * CGFloat(rows - 1)
        let top = rect.minY + max(0, (rect.height - gridHeight) / 2)

        return (0..<count).map { index in
            let row = index / columns
            let column = index % columns
            let y = top + CGFloat(row) * (cellHeight + gutter)
            let isOddLast = index == count - 1 && count % columns == 1 && columns > 1
            if isOddLast {
                return CGRect(x: rect.minX, y: y, width: rect.width, height: cellHeight)
            }
            return CGRect(x: rect.minX + CGFloat(column) * (cellWidth + gutter),
                          y: y, width: cellWidth, height: cellHeight)
        }
    }

    private static func drawGrid(_ ctx: CGContext, photos: [LoadedPhoto], in rect: CGRect) {
        for (cell, photo) in zip(cellRects(count: photos.count, in: rect), photos) {
            drawFilled(ctx, image: photo.image, crop: photo.crop, in: cell)
        }
    }

    /// Aspect-fills `rect` and clips, positioning the overflow with the crop
    /// the user set in the app — the same math as `SquareCropGeometry`, so the
    /// print matches what the memory looks like on screen.
    private static func drawFilled(_ ctx: CGContext, image: UIImage, crop: CGPoint, in rect: CGRect, cornerRadius: CGFloat = 6) {
        guard image.size.width > 0, image.size.height > 0, rect.width > 0, rect.height > 0 else { return }

        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(
            x: rect.minX - (drawSize.width - rect.width) * crop.x,
            y: rect.minY - (drawSize.height - rect.height) * crop.y
        )

        ctx.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        image.draw(in: CGRect(origin: origin, size: drawSize))
        ctx.restoreGState()
    }

    // MARK: - Caption

    private struct Caption {
        let message: NSAttributedString?
        let messageHeight: CGFloat
        let notes: NSAttributedString?
        let notesHeight: CGFloat
        let meta: NSAttributedString
        let metaHeight: CGFloat
        /// Total height including the accent rule and the gaps around it.
        let height: CGFloat
    }

    private static func makeCaption(for snapshot: PDFMemorySnapshot, width: CGFloat, compact: Bool) -> Caption {
        let ruleBlock: CGFloat = 2 + 16          // rule + gap beneath it
        let messageGap: CGFloat = 12
        let notesGap: CGFloat = 8

        /// Natural height, capped at `maxLines`. Without a cap a long
        /// description pushes the caption past the bottom of the sheet and over
        /// the page number; the paragraph style truncates instead.
        func height(_ string: NSAttributedString, _ available: CGFloat, maxLines: Int) -> CGFloat {
            let natural = ceil(string.boundingRect(
                with: CGSize(width: available, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, context: nil
            ).height)
            let font = string.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            let lineHeight = font?.lineHeight ?? 16
            let spacing = compact ? 3.0 : 5.0
            let cap = ceil(lineHeight * CGFloat(maxLines) + spacing * CGFloat(maxLines - 1))
            return min(natural, cap)
        }

        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineSpacing = compact ? 3 : 5
        centered.lineBreakMode = .byTruncatingTail

        var total = ruleBlock

        var message: NSAttributedString?
        var messageHeight: CGFloat = 0
        if !snapshot.message.isEmpty {
            message = NSAttributedString(string: snapshot.message, attributes: [
                .font: serifFont(compact ? 15 : 20),
                .foregroundColor: inkColor,
                .paragraphStyle: centered
            ])
            messageHeight = height(message!, width, maxLines: compact ? 2 : 3)
            total += messageHeight + messageGap
        }

        var notes: NSAttributedString?
        var notesHeight: CGFloat = 0
        if !snapshot.notes.isEmpty {
            notes = NSAttributedString(string: snapshot.notes, attributes: [
                .font: serifFont(compact ? 11 : 13),
                .foregroundColor: secondaryColor,
                .paragraphStyle: centered
            ])
            notesHeight = height(notes!, width * 0.9, maxLines: compact ? 2 : 4)
            total += notesHeight + notesGap
        }

        var metaText = snapshot.formattedDate.uppercased()
        if let tag = MemoryTag(rawValue: snapshot.tag), tag != .none {
            metaText = tag.label.uppercased() + "  ·  " + metaText
        }
        let metaStyle = NSMutableParagraphStyle()
        metaStyle.alignment = .center
        let meta = NSAttributedString(string: metaText, attributes: [
            .font: UIFont.systemFont(ofSize: compact ? 8 : 9, weight: .bold),
            .foregroundColor: secondaryColor,
            .kern: 2,
            .paragraphStyle: metaStyle
        ])
        let metaHeight = height(meta, width, maxLines: 1)
        total += metaHeight

        return Caption(message: message, messageHeight: messageHeight,
                       notes: notes, notesHeight: notesHeight,
                       meta: meta, metaHeight: metaHeight,
                       height: total)
    }

    private static func drawCaption(_ ctx: CGContext, _ caption: Caption, top: CGFloat, in rect: CGRect, accent: UIColor) {
        var y = top

        ctx.setFillColor(accent.cgColor)
        ctx.fill(CGRect(x: rect.midX - 18, y: y, width: 36, height: 2))
        y += 2 + 16

        if let message = caption.message {
            message.draw(with: CGRect(x: rect.minX, y: y, width: rect.width, height: caption.messageHeight + 4),
                         options: .usesLineFragmentOrigin, context: nil)
            y += caption.messageHeight + 12
        }

        if let notes = caption.notes {
            let inset = rect.width * 0.05
            notes.draw(with: CGRect(x: rect.minX + inset, y: y, width: rect.width * 0.9, height: caption.notesHeight + 4),
                       options: .usesLineFragmentOrigin, context: nil)
            y += caption.notesHeight + 8
        }

        caption.meta.draw(with: CGRect(x: rect.minX, y: y, width: rect.width, height: caption.metaHeight + 4),
                          options: .usesLineFragmentOrigin, context: nil)
    }
}
