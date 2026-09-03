import AppKit

extension BlockInputBlockItem {
    func applyInlineCodeAttributes(for block: BlockInputBlock, textStorage: NSTextStorage) {
        guard Self.supportsInlineCodeStyling(block.kind) else {
            return
        }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseFont = Self.font(for: block.kind, style: style)
        let inlineFont = inlineCodeFont(for: baseFont)
        let delimiterFont = Self.inlineCodeDelimiterFont(for: baseFont)
        let foregroundColor = inlineCodeForegroundColor()
        let backgroundColor = inlineCodeBackgroundColor()
        for inlineCodeRange in BlockInputCodeParsing.inlineCodeRanges(in: textStorage.string) {
            let spanRange = NSIntersectionRange(inlineCodeRange.fullRange, fullRange)
            if spanRange.length > 0 {
                textStorage.addAttribute(.blockInputInlineCode, value: true, range: spanRange)
            }
            let contentRange = NSIntersectionRange(inlineCodeRange.contentRange, fullRange)
            if contentRange.length > 0 {
                textStorage.addAttributes(
                    [
                        .font: inlineFont,
                        .foregroundColor: foregroundColor,
                        .backgroundColor: backgroundColor
                    ],
                    range: contentRange
                )
            }
            for delimiterRange in inlineCodeRange.delimiterRanges {
                let clampedDelimiterRange = NSIntersectionRange(delimiterRange, fullRange)
                guard clampedDelimiterRange.length > 0 else {
                    continue
                }
                textStorage.addAttributes(
                    [
                        .font: delimiterFont,
                        .foregroundColor: NSColor.clear,
                        .blockInputHiddenDelimiter: true
                    ],
                    range: clampedDelimiterRange
                )
            }
        }
    }

    func inlineCodeContentRanges(for block: BlockInputBlock) -> [NSRange] {
        guard Self.supportsInlineCodeStyling(block.kind) else {
            return []
        }
        return BlockInputCodeParsing.inlineCodeRanges(in: textView.string).map(\.contentRange)
    }

    static func supportsInlineCodeStyling(_ kind: BlockInputBlockKind) -> Bool {
        switch kind {
        case .paragraph, .heading, .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            return false
        }
    }

    static func inlineCodeFont(for font: NSFont, style: BlockInputStyle = .default) -> NSFont {
        style.inlineCode.font ?? defaultInlineCodeFont(for: font)
    }

    func inlineCodeFont(for font: NSFont) -> NSFont {
        Self.inlineCodeFont(for: font, style: style)
    }

    func inlineCodeForegroundColor() -> NSColor {
        style.inlineCode.foregroundColor ?? style.baseText.foregroundColor ?? .labelColor
    }

    func inlineCodeBackgroundColor() -> NSColor {
        style.inlineCode.backgroundColor ?? Self.inlineCodeBackgroundColor
    }

    private static func defaultInlineCodeFont(for font: NSFont) -> NSFont {
        .monospacedSystemFont(ofSize: font.pointSize * 0.94, weight: .regular)
    }

    static var inlineCodeBackgroundColor: NSColor {
        NSColor.quaternaryLabelColor
    }

    static func inlineCodeDelimiterFont(for font: NSFont) -> NSFont {
        .monospacedSystemFont(ofSize: max(font.pointSize * 0.1, 1), weight: .regular)
    }
}
