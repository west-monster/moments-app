import UIKit

struct PDFMemorySnapshot {
    let message: String
    let notes: String
    let formattedDate: String
    let images: [UIImage]
    let tag: String
}

enum PDFExporter {
    static func snapshots(from memories: [Memory]) -> [PDFMemorySnapshot] {
        memories.map { m in
            PDFMemorySnapshot(
                message: m.message,
                notes: m.notes,
                formattedDate: m.formattedDate,
                images: m.allImages,
                tag: m.tag
            )
        }
    }

    static func generate(from snapshots: [PDFMemorySnapshot], title: String) -> URL? {
        guard !snapshots.isEmpty else { return nil }

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2
        let accentColor = UIColor(red: 0.33, green: 0.53, blue: 1.0, alpha: 1.0)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()
            drawCoverPage(context.cgContext, title: title, accent: accentColor, w: pageWidth, h: pageHeight)

            for snapshot in snapshots {
                context.beginPage()
                drawMemoryPage(context.cgContext, snapshot: snapshot, margin: margin, contentWidth: contentWidth, accent: accentColor, w: pageWidth, h: pageHeight)
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Moments-\(dateStr).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func drawCoverPage(_ ctx: CGContext, title: String, accent: UIColor, w: CGFloat, h: CGFloat) {
        let textColor = UIColor(white: 0.13, alpha: 1.0)

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: accent,
            .kern: 3
        ]
        let subtitle = String(localized: "feed.header").uppercased()
        let subSize = (subtitle as NSString).size(withAttributes: subtitleAttrs)
        (subtitle as NSString).draw(at: CGPoint(x: (w - subSize.width) / 2, y: h / 2 - 80), withAttributes: subtitleAttrs)

        ctx.setFillColor(accent.cgColor)
        ctx.fill(CGRect(x: w / 2 - 25, y: h / 2 - 55, width: 50, height: 3))

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 36, weight: .black),
            .foregroundColor: textColor
        ]
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        (title as NSString).draw(at: CGPoint(x: (w - titleSize.width) / 2, y: h / 2 - 25), withAttributes: titleAttrs)
    }

    private static func drawMemoryPage(_ ctx: CGContext, snapshot: PDFMemorySnapshot, margin: CGFloat, contentWidth: CGFloat, accent: UIColor, w: CGFloat, h: CGFloat) {
        let textColor = UIColor(white: 0.13, alpha: 1.0)
        let secondaryColor = UIColor(white: 0.5, alpha: 1.0)
        let serifFont = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withDesign(.serif) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body), size: 18)

        let images = snapshot.images
        let messageStyle = NSMutableParagraphStyle()
        messageStyle.alignment = .center
        messageStyle.lineSpacing = 5
        let messageAttrs: [NSAttributedString.Key: Any] = [
            .font: serifFont,
            .foregroundColor: textColor,
            .paragraphStyle: messageStyle
        ]
        let notesStyle = NSMutableParagraphStyle()
        notesStyle.alignment = .center
        notesStyle.lineSpacing = 4
        let notesAttrs: [NSAttributedString.Key: Any] = [
            .font: serifFont.withSize(13),
            .foregroundColor: secondaryColor,
            .paragraphStyle: notesStyle
        ]
        var dateStr = snapshot.formattedDate.uppercased()
        if let t = MemoryTag(rawValue: snapshot.tag), t != .none {
            dateStr = t.label.uppercased() + "  ·  " + dateStr
        }
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: secondaryColor,
            .kern: 2
        ]

        var totalHeight: CGFloat = 0
        var imageBlockH: CGFloat = 0

        if images.count == 1, let image = images.first {
            let aspect = image.size.width / image.size.height
            let imgH = min(contentWidth / aspect, h * 0.55)
            imageBlockH = imgH
            totalHeight += imgH + 30
        } else if images.count >= 2 {
            let count = min(images.count, 6)
            let gap: CGFloat = 6
            let rows = (count + 1) / 2
            let cellW = (contentWidth - gap) / 2
            let maxGridH = h * 0.55
            let cellH = min(cellW * 0.75, (maxGridH - gap * CGFloat(rows - 1)) / CGFloat(rows))
            imageBlockH = CGFloat(rows) * cellH + CGFloat(rows - 1) * gap
            totalHeight += imageBlockH + 30
        }

        totalHeight += 2 + 18

        var messageBounds = CGRect.zero
        if !snapshot.message.isEmpty {
            messageBounds = (snapshot.message as NSString).boundingRect(
                with: CGSize(width: contentWidth - 40, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, attributes: messageAttrs, context: nil
            )
            totalHeight += messageBounds.height + 10 + 20
        }

        var notesBounds = CGRect.zero
        if !snapshot.notes.isEmpty {
            notesBounds = (snapshot.notes as NSString).boundingRect(
                with: CGSize(width: contentWidth - 60, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, attributes: notesAttrs, context: nil
            )
            totalHeight += notesBounds.height + 10 + 20
        }

        let dateSize = (dateStr as NSString).size(withAttributes: dateAttrs)
        totalHeight += dateSize.height

        var y = max(margin, (h - totalHeight) / 2)

        if images.count == 1, let image = images.first {
            let aspect = image.size.width / image.size.height
            let imgW = contentWidth
            let imgH = min(imgW / aspect, h * 0.55)
            let finalW = imgH == h * 0.55 ? imgH * aspect : imgW
            let imgRect = CGRect(x: margin + (contentWidth - finalW) / 2, y: y, width: finalW, height: imgH)

            ctx.saveGState()
            UIBezierPath(roundedRect: imgRect, cornerRadius: 8).addClip()
            image.draw(in: imgRect)
            ctx.restoreGState()

            y += imgH + 30
        } else if images.count >= 2 {
            let count = min(images.count, 6)
            let gap: CGFloat = 6
            let cols = 2
            let rows = (count + 1) / 2
            let cellW = (contentWidth - gap) / 2
            let maxGridH = h * 0.55
            let cellH = min(cellW * 0.75, (maxGridH - gap * CGFloat(rows - 1)) / CGFloat(rows))

            let gridW = CGFloat(cols) * cellW + gap
            let startX = margin + (contentWidth - gridW) / 2

            for i in 0..<count {
                let col = i % cols
                let row = i / cols
                let cellX = startX + CGFloat(col) * (cellW + gap)
                let cellY = y + CGFloat(row) * (cellH + gap)
                let cellRect = CGRect(x: cellX, y: cellY, width: cellW, height: cellH)

                ctx.saveGState()
                UIBezierPath(roundedRect: cellRect, cornerRadius: 6).addClip()

                let img = images[i]
                let imgAspect = img.size.width / img.size.height
                let cellAspect = cellW / cellH
                var drawRect: CGRect
                if imgAspect > cellAspect {
                    let drawH = cellH
                    let drawW = drawH * imgAspect
                    drawRect = CGRect(x: cellX - (drawW - cellW) / 2, y: cellY, width: drawW, height: drawH)
                } else {
                    let drawW = cellW
                    let drawH = drawW / imgAspect
                    drawRect = CGRect(x: cellX, y: cellY - (drawH - cellH) / 2, width: drawW, height: drawH)
                }
                img.draw(in: drawRect)
                ctx.restoreGState()
            }

            y += imageBlockH + 30
        }

        ctx.setFillColor(accent.cgColor)
        ctx.fill(CGRect(x: w / 2 - 18, y: y, width: 36, height: 2))
        y += 18

        if !snapshot.message.isEmpty {
            (snapshot.message as NSString).draw(in: CGRect(x: margin + 20, y: y, width: contentWidth - 40, height: messageBounds.height + 10), withAttributes: messageAttrs)
            y += messageBounds.height + 10 + 20
        }

        if !snapshot.notes.isEmpty {
            (snapshot.notes as NSString).draw(in: CGRect(x: margin + 30, y: y, width: contentWidth - 60, height: notesBounds.height + 10), withAttributes: notesAttrs)
            y += notesBounds.height + 10 + 20
        }

        (dateStr as NSString).draw(at: CGPoint(x: (w - dateSize.width) / 2, y: y), withAttributes: dateAttrs)
    }
}
