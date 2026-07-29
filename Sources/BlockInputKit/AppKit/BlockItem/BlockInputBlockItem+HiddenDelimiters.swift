import AppKit

/// Layout-manager delegate that collapses attributed Markdown source delimiters into zero-width glyphs.
final class BlockInputDelimiterGlyphs: NSObject, NSLayoutManagerDelegate {
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard glyphRange.length > 0,
              let textStorage = layoutManager.textStorage else {
            return 0
        }
        var glyphBuffer = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        var propertyBuffer = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var characterIndexBuffer = Array(UnsafeBufferPointer(start: charIndexes, count: glyphRange.length))
        var hasHiddenDelimiter = false
        for index in propertyBuffer.indices {
            let characterIndex = characterIndexBuffer[index]
            guard characterIndex >= 0,
                  characterIndex < textStorage.length,
                  textStorage.attribute(.blockInputHiddenDelimiter, at: characterIndex, effectiveRange: nil) as? Bool == true else {
                continue
            }
            // Clear foreground hides delimiter drawing, but null glyphs remove
            // their advance so hidden Markdown markers do not read as spaces.
            propertyBuffer[index].insert(.null)
            hasHiddenDelimiter = true
        }
        guard hasHiddenDelimiter else {
            return 0
        }
        layoutManager.setGlyphs(
            &glyphBuffer,
            properties: &propertyBuffer,
            characterIndexes: &characterIndexBuffer,
            font: font,
            forGlyphRange: glyphRange
        )
        return glyphRange.length
    }

    /// Grows line fragments that carry inline images taller than the text. Images
    /// center on the cap-height midline (GitHub's `vertical-align: middle`), so a
    /// tall image needs room both above the baseline and below it.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        guard let textStorage = layoutManager.textStorage else {
            return false
        }
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var neededAscent: CGFloat = 0
        var neededDescent: CGFloat = 0
        textStorage.enumerateAttribute(.blockInputInlineImage, in: characterRange) { value, _, _ in
            guard let run = value as? BlockInputInlineImageRun else {
                return
            }
            neededAscent = max(neededAscent, run.ascent)
            neededDescent = max(neededDescent, run.baselineDrop)
        }
        let ascentDelta = max(0, ceil(neededAscent - baselineOffset.pointee))
        let availableDescent = lineFragmentRect.pointee.height - baselineOffset.pointee
        let descentDelta = max(0, ceil(neededDescent - availableDescent))
        guard ascentDelta > 0 || descentDelta > 0 else {
            return false
        }
        lineFragmentRect.pointee.size.height += ascentDelta + descentDelta
        lineFragmentUsedRect.pointee.size.height += ascentDelta + descentDelta
        baselineOffset.pointee += ascentDelta
        return true
    }
}

extension NSAttributedString.Key {
    /// Marks visual inline chip content so adjacent virtual hints can fall back to the normal typing font.
    static let blockInputInlineChip = NSAttributedString.Key("BlockInputInlineChip")
    /// Marks source delimiters/tags that should stay in storage but collapse out of visual layout.
    static let blockInputHiddenDelimiter = NSAttributedString.Key("BlockInputHiddenDelimiter")
}
