import AppKit

/// Layout-manager delegate that collapses attributed Markdown source delimiters into zero-width
/// glyphs and keeps an inline code span on one line.
///
/// It is the delegate of every mounted text view, of table cells, and of the offscreen height
/// measurement alike, which is what keeps rendering and measurement wrapping at the same places:
/// a break rule that lived only on the mounted side would render a line the measured height had
/// no room for.
final class BlockInputDelimiterGlyphs: NSObject, NSLayoutManagerDelegate {
    /// Refuses a word break inside an inline code span, so a span that does not fit moves to
    /// the next line whole, the way a chip does. Breaks before the opening backtick and after
    /// the closing one stay allowed; a span wider than the whole line still breaks by character,
    /// because TextKit falls back to that once no word break fits.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
        !Self.isInsideInlineCodeSpan(at: charIndex, in: layoutManager)
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldBreakLineByHyphenatingBeforeCharacterAt charIndex: Int
    ) -> Bool {
        !Self.isInsideInlineCodeSpan(at: charIndex, in: layoutManager)
    }

    /// A break before `charIndex` splits a span only when the characters on both sides of it
    /// carry the span attribute.
    private static func isInsideInlineCodeSpan(at charIndex: Int, in layoutManager: NSLayoutManager) -> Bool {
        guard charIndex > 0,
              let textStorage = layoutManager.textStorage,
              charIndex < textStorage.length else {
            return false
        }
        return textStorage.attribute(.blockInputInlineCode, at: charIndex - 1, effectiveRange: nil) as? Bool == true
            && textStorage.attribute(.blockInputInlineCode, at: charIndex, effectiveRange: nil) as? Bool == true
    }

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
    /// Marks an inline code span, delimiters included, so `BlockInputDelimiterGlyphs` can refuse
    /// line breaks inside it. Applied by both the mounted styling and the offscreen measurement.
    static let blockInputInlineCode = NSAttributedString.Key("BlockInputInlineCode")
}
