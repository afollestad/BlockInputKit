import AppKit

extension NSLayoutManager {
    /// The box the glyphs of a line actually occupy, with any `lineSpacing` trailing the fragment
    /// removed.
    ///
    /// `NSParagraphStyle.lineSpacing` grows a fragment beyond its natural line height and folds
    /// that into `lineFragmentUsedRect`, keeping the baseline where it was — so the extra space
    /// sits below the glyphs and only on lines that have a line after them. Chrome that vertically
    /// centers on a line (inline chip fills, list markers, the quote bar) sinks by half the spacing
    /// if it centers on the used rect, so it must use this instead. Geometry that only spans a line
    /// (selection chrome, caret rects) keeps the full fragment, which is what makes a wrapped
    /// selection read as continuous.
    func blockInputGlyphLineRect(forGlyphAt glyphIndex: Int, effectiveRange: NSRangePointer? = nil) -> NSRect {
        var lineGlyphRange = NSRange()
        var usedRect = lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
        effectiveRange?.pointee = lineGlyphRange
        guard let glyphLineHeight = blockInputUnspacedLineHeight(forGlyphRange: lineGlyphRange),
              usedRect.height - glyphLineHeight > 0.01 else {
            return usedRect
        }
        usedRect.size.height = glyphLineHeight
        return usedRect
    }

    /// Height this line would have without line spacing, or nil when it carries none.
    ///
    /// TextKit does not spend the configured spacing uniformly — the first fragment of a paragraph
    /// can take the full value while later ones take slightly less — so the unspaced height is
    /// recovered from the fonts on the line rather than by subtracting the spacing. The tallest run
    /// wins, because a line beginning with a chip's smaller font is otherwise read short.
    private func blockInputUnspacedLineHeight(forGlyphRange glyphRange: NSRange) -> CGFloat? {
        guard let textStorage,
              textStorage.length > 0,
              glyphRange.length > 0 else {
            return nil
        }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0,
              NSMaxRange(characterRange) <= textStorage.length,
              let paragraphStyle = textStorage.attribute(
                  .paragraphStyle,
                  at: characterRange.location,
                  effectiveRange: nil
              ) as? NSParagraphStyle,
              paragraphStyle.lineSpacing > 0 else {
            return nil
        }
        var lineHeight: CGFloat = 0
        textStorage.enumerateAttribute(.font, in: characterRange) { font, _, _ in
            guard let font = font as? NSFont else {
                return
            }
            lineHeight = max(lineHeight, defaultLineHeight(for: font))
        }
        return lineHeight > 0 ? lineHeight : nil
    }
}
