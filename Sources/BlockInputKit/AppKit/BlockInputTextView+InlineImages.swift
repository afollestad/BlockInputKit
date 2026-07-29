import AppKit

extension BlockInputTextView {
    /// Draws inline images over their reserved advances. The anchor glyph is
    /// clear-colored and the rest of the source is collapsed, so the image is
    /// the only visible representation of the span.
    func drawInlineImages(in dirtyRect: NSRect) {
        guard let layoutManager,
              let textContainer,
              let textStorage,
              textStorage.length > 0 else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.blockInputInlineImage, in: fullRange) { value, range, _ in
            guard let run = value as? BlockInputInlineImageRun else {
                return
            }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else {
                return
            }
            let glyphIndex = glyphRange.location
            let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            // location(forGlyphAt:).y is the baseline within the line fragment; the
            // image centers on the cap-height midline, dipping `baselineDrop` below it.
            let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
            let imageRect = NSRect(
                x: lineFragmentRect.minX + glyphLocation.x + textContainerOrigin.x,
                y: lineFragmentRect.minY + glyphLocation.y + run.baselineDrop - run.displaySize.height + textContainerOrigin.y,
                width: run.displaySize.width,
                height: run.displaySize.height
            )
            guard imageRect.intersects(dirtyRect) else {
                return
            }
            if run.isLoaded, let image = blockItem?.inlineImageStore?.image(forSource: run.image.source) {
                image.draw(
                    in: imageRect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high.rawValue]
                )
            } else {
                let hasFailed = blockItem?.inlineImageStore?.hasFailed(source: run.image.source) == true
                drawInlineImagePlaceholder(in: imageRect, hasFailed: hasFailed)
            }
        }
    }

    private func drawInlineImagePlaceholder(in rect: NSRect, hasFailed: Bool) {
        let cornerRadius = min(4, rect.height / 4)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.26).setFill()
        NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        let stroke = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        stroke.lineWidth = 1
        stroke.stroke()
        guard hasFailed else {
            return
        }
        let symbolSide = min(12, rect.height * 0.6, rect.width * 0.6)
        guard symbolSide >= 6,
              let symbol = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: nil
              ) else {
            return
        }
        let symbolRect = NSRect(
            x: rect.midX - symbolSide / 2,
            y: rect.midY - symbolSide / 2,
            width: symbolSide,
            height: symbolSide
        )
        NSColor.secondaryLabelColor.set()
        symbol.isTemplate = true
        symbol.draw(
            in: symbolRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 0.8,
            respectFlipped: true,
            hints: nil
        )
    }
}
