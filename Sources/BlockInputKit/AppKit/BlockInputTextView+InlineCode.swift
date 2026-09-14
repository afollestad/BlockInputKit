import AppKit

extension BlockInputTextView {
    /// TextKit can report zero-width bounds and omit native backgrounds when hidden delimiters wrap.
    /// Glyph positions are already valid before drawing, unlike its bounding and selection rects.
    func drawInlineCodeBackgrounds(in dirtyRect: NSRect) {
        guard let textStorage, let layoutManager, let textContainer else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.blockInputInlineCodeBackground, in: fullRange) { value, range, _ in
            guard let color = value as? NSColor else {
                return
            }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            color.setFill()
            var glyphIndex = glyphRange.location
            while glyphIndex < NSMaxRange(glyphRange) {
                var lineRange = NSRange()
                let lineRect = layoutManager.blockInputGlyphLineRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
                let intersection = NSIntersectionRange(glyphRange, lineRange)
                let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let startX = fragmentRect.minX + layoutManager.location(forGlyphAt: intersection.location).x
                let endIndex = NSMaxRange(intersection)
                let endX = endIndex < NSMaxRange(lineRange)
                    ? fragmentRect.minX + layoutManager.location(forGlyphAt: endIndex).x
                    : lineRect.maxX
                let rect = NSRect(x: min(startX, endX), y: lineRect.minY, width: abs(endX - startX), height: lineRect.height)
                    .offsetBy(dx: origin.x, dy: origin.y)
                if rect.intersects(dirtyRect) {
                    rect.fill()
                }
                glyphIndex = max(glyphIndex + 1, NSMaxRange(lineRange))
            }
        }
    }
}

extension NSAttributedString.Key {
    /// Keeps inline code fills out of TextKit's unreliable native background drawing around hidden delimiters.
    static let blockInputInlineCodeBackground = NSAttributedString.Key("BlockInputInlineCodeBackground")
}
