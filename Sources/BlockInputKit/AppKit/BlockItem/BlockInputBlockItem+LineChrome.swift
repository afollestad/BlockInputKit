import AppKit

/// Per-line chrome geometry: marker Y offsets and the quote bar's vertical extent.
///
/// Both center chrome on a rendered line box rather than on the row, so both depend on the same
/// two facts: `BlockInputMarkerView` centers each marker inside the height it is handed, and a
/// line fragment's used rect carries the paragraph's trailing line spacing while its glyphs do
/// not. Keeping them together keeps that reasoning in one place.
extension BlockInputBlockItem {
    func updateMarkerLineYOffsets() {
        guard !kindLabel.markerLines.isEmpty,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            kindLabel.setMarkerLineYOffsets([])
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let textLength = (textView.string as NSString).length
        let lineStarts = BlockInputLineBreaks.lineStartOffsets(in: textView.string)
        let metrics = lineStarts.prefix(kindLabel.markerLines.count).enumerated().map { lineIndex, lineStart in
            let lineFragment = markerAlignmentRect(
                lineIndex: lineIndex,
                lineStart: lineStart,
                textLength: textLength,
                layoutManager: layoutManager
            )
            let textPoint = NSPoint(x: 0, y: textView.textContainerOrigin.y + lineFragment.minY)
            let itemPoint = textView.convert(textPoint, to: view)
            let markerPoint = kindLabel.convert(itemPoint, from: view)
            return (yOffset: markerPoint.y, height: lineFragment.height)
        }
        kindLabel.setMarkerLineMetrics(
            yOffsets: metrics.map(\.yOffset),
            heights: metrics.map(\.height)
        )
    }

    func updateQuoteBarVerticalExtent() {
        guard renderedBlock?.kind == .quote,
              !quoteBarView.isHidden,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            quoteBarTopConstraint?.constant = Self.quoteBarVerticalInset
            quoteBarBottomConstraint?.constant = -Self.quoteBarVerticalInset
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let textRect = layoutManager.usedRect(for: textContainer).offsetBy(
            dx: textView.textContainerOrigin.x,
            dy: textView.textContainerOrigin.y
        )
        guard !textRect.isEmpty else {
            quoteBarTopConstraint?.constant = Self.quoteBarVerticalInset
            quoteBarBottomConstraint?.constant = -Self.quoteBarVerticalInset
            return
        }

        let itemTextRect = textView.convert(textRect, to: view)
        let quoteBarHeight = min(
            max(Self.minimumQuoteBarHeight, itemTextRect.height),
            max(0, view.bounds.height - Self.quoteBarVerticalInset * 2)
        )
        let textMidY = quoteBarAlignmentRect(
            itemTextRect: itemTextRect,
            layoutManager: layoutManager,
            textContainer: textContainer
        ).midY
        let quoteBarMinY = min(
            max(view.bounds.minY + Self.quoteBarVerticalInset, textMidY - quoteBarHeight / 2),
            view.bounds.maxY - Self.quoteBarVerticalInset - quoteBarHeight
        )
        let quoteBarMaxY = quoteBarMinY + quoteBarHeight
        let topInset = max(Self.quoteBarVerticalInset, view.bounds.maxY - quoteBarMaxY)
        let bottomInset = max(Self.quoteBarVerticalInset, quoteBarMinY - view.bounds.minY)
        quoteBarTopConstraint?.constant = topInset
        quoteBarBottomConstraint?.constant = -bottomInset
        quoteBarView.frame.origin.y = quoteBarMinY
        quoteBarView.frame.size.height = quoteBarHeight
    }

    private func quoteBarAlignmentRect(
        itemTextRect: NSRect,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect {
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0,
              layoutManager.lineFragmentCount(in: glyphRange) == 1 else {
            return itemTextRect
        }
        let firstLineRect = layoutManager.blockInputGlyphLineRect(forGlyphAt: glyphRange.location).offsetBy(
            dx: textView.textContainerOrigin.x,
            dy: textView.textContainerOrigin.y
        )
        return textView.convert(firstLineRect, to: view)
    }

    private func markerAlignmentRect(
        lineIndex: Int,
        lineStart: Int,
        textLength: Int,
        layoutManager: NSLayoutManager
    ) -> NSRect {
        guard textLength > 0, lineStart < textLength else {
            let extraLineFragmentRect = layoutManager.extraLineFragmentRect
            guard !extraLineFragmentRect.isEmpty else {
                let font = Self.font(for: renderedBlock?.kind ?? .paragraph, style: style)
                let lineHeight = ceil(font.ascender - font.descender + font.leading)
                return NSRect(x: 0, y: CGFloat(lineIndex) * lineHeight, width: 0, height: lineHeight)
            }
            return extraLineFragmentRect
        }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineStart)
        // Markers center within the height returned here, so it must exclude line spacing.
        return layoutManager.blockInputGlyphLineRect(forGlyphAt: glyphIndex)
    }
}

private extension NSLayoutManager {
    func lineFragmentCount(in glyphRange: NSRange) -> Int {
        var lineCount = 0
        enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, stop in
            lineCount += 1
            if lineCount > 1 {
                stop.pointee = true
            }
        }
        return lineCount
    }
}
