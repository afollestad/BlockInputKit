import AppKit

private let inlineChipAdjacentWhitespaceKern: CGFloat = 5

extension BlockInputBlockItem {
    func applyInlineMarkdownAttributes(for block: BlockInputBlock, textStorage: NSTextStorage) {
        Self.applyInlineMarkdownAttributes(
            for: block,
            textStorage: textStorage,
            style: style,
            fileBaseURL: fileBaseURL,
            rawSlashCommandChips: rawSlashCommandChips,
            slashCommandAvailability: slashCommandAvailability,
            isDocumentStartBlock: isDocumentStartBlock
        )
    }

    static func applyInlineMarkdownAttributes(
        for block: BlockInputBlock,
        textStorage: NSTextStorage,
        style: BlockInputStyle,
        fileBaseURL: URL? = nil,
        rawSlashCommandChips: Bool = false,
        slashCommandAvailability: BlockInputSlashCommandAvailability = .documentStart,
        isDocumentStartBlock: Bool = false
    ) {
        guard Self.supportsInlineMarkdownStyling(block.kind) else {
            return
        }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: textStorage.string).map(\.fullRange)
        let markdownRanges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: textStorage.string,
            excluding: inlineCodeRanges,
            fileBaseURL: fileBaseURL,
            rawSlashCommandChips: rawSlashCommandChips,
            slashCommandAvailability: slashCommandAvailability,
            isDocumentStartBlock: isDocumentStartBlock
        )
        let baseFont = Self.font(for: block.kind, style: style)
        for markdownRange in markdownRanges {
            let inlineChipKind = markdownRange.inlineChipKind(in: textStorage.string)
            let inlineChipStyle = inlineChipKind.map { style.inlineChipStyle(for: $0) }
            Self.applyInlineMarkdownContentAttributes(
                for: markdownRange,
                excluding: inlineCodeRanges,
                fullRange: fullRange,
                textStorage: textStorage,
                baseFont: baseFont,
                inlineChipStyle: inlineChipStyle
            )
            for delimiterRange in markdownRange.delimiterRanges {
                let clampedDelimiterRange = NSIntersectionRange(delimiterRange, fullRange)
                guard clampedDelimiterRange.length > 0 else {
                    continue
                }
                textStorage.addAttributes(
                    [
                        .font: Self.inlineMarkdownDelimiterFont(for: Self.font(for: block.kind, style: style)),
                        .foregroundColor: NSColor.clear,
                        .blockInputHiddenDelimiter: true
                    ],
                    range: clampedDelimiterRange
                )
            }
            if let inlineChipKind {
                Self.applyInlineChipSpacing(
                    for: markdownRange,
                    kind: inlineChipKind,
                    in: textStorage
                )
            }
        }
    }

    private static func applyInlineMarkdownContentAttributes(
        for markdownRange: BlockInputInlineMarkdownRange,
        excluding inlineCodeRanges: [NSRange],
        fullRange: NSRange,
        textStorage: NSTextStorage,
        baseFont: NSFont,
        inlineChipStyle: BlockInputInlineChipStyle?
    ) {
        for contentRange in markdownRange.contentRange.subtractingSorted(inlineCodeRanges) {
            let clampedContentRange = NSIntersectionRange(contentRange, fullRange)
            guard clampedContentRange.length > 0 else {
                continue
            }
            if let inlineChipStyle {
                Self.applyInlineChip(to: clampedContentRange, in: textStorage, baseFont: baseFont, style: inlineChipStyle)
            } else {
                Self.apply(markdownRange.style, to: clampedContentRange, in: textStorage, baseFont: baseFont)
            }
            if let destination = markdownRange.linkDestination {
                textStorage.addAttribute(.link, value: destination, range: clampedContentRange)
                textStorage.addAttribute(.toolTip, value: destination.absoluteString, range: clampedContentRange)
            }
        }
    }

    func inlineMarkdownStylesForCurrentSelection(in block: BlockInputBlock) -> Set<BlockInputInlineMarkdownStyle> {
        let selectedRange = textView.selectedRange()
        guard Self.supportsInlineMarkdownStyling(block.kind),
              !currentSelectionIntersectsStyledContent(inlineCodeContentRanges(for: block)) else {
            return []
        }
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: textView.string).map(\.fullRange)
        let markdownRanges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: textView.string,
            excluding: inlineCodeRanges,
            fileBaseURL: fileBaseURL
        )
        return Set(markdownRanges.compactMap { markdownRange in
            selectedRange.intersectsStyledContent(markdownRange.contentRange) ? markdownRange.style : nil
        })
    }

    func currentSelectionIntersectsStyledContent(_ ranges: [NSRange]) -> Bool {
        let selectedRange = textView.selectedRange()
        return ranges.contains { selectedRange.intersectsStyledContent($0) }
    }

    static func supportsInlineMarkdownStyling(_ kind: BlockInputBlockKind) -> Bool {
        switch kind {
        case .paragraph, .heading, .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            return false
        }
    }

    private static func apply(
        _ style: BlockInputInlineMarkdownStyle,
        to range: NSRange,
        in textStorage: NSTextStorage,
        baseFont: NSFont
    ) {
        switch style {
        case .bold:
            applyFontTrait(.boldFontMask, to: range, in: textStorage, baseFont: baseFont)
        case .italic:
            applyFontTrait(.italicFontMask, to: range, in: textStorage, baseFont: baseFont)
        case .underline:
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .strikethrough:
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .link:
            textStorage.addAttributes(
                [
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: range
            )
        case .rawSlashCommand:
            applyInlineChip(to: range, in: textStorage, baseFont: baseFont, style: .init())
        }
    }

    private static func applyInlineChip(
        to range: NSRange,
        in textStorage: NSTextStorage,
        baseFont: NSFont,
        style: BlockInputInlineChipStyle
    ) {
        let chipFont = inlineChipFont(for: baseFont)
        textStorage.addAttributes(
            [
                .font: chipFont,
                .foregroundColor: style.foregroundColor,
                .baselineOffset: inlineChipBaselineOffset(baseFont: baseFont, chipFont: chipFont),
                .blockInputInlineChip: true
            ],
            range: range
        )
    }

    private static func inlineChipFont(for baseFont: NSFont) -> NSFont {
        .monospacedSystemFont(ofSize: max(baseFont.pointSize * 0.94, 1), weight: .regular)
    }

    private static func inlineChipBaselineOffset(baseFont: NSFont, chipFont: NSFont) -> CGFloat {
        max(0, ceil(baseFont.ascender - chipFont.ascender))
    }

    private static func applyInlineChipSpacing(
        for markdownRange: BlockInputInlineMarkdownRange,
        kind: BlockInputInlineChipKind,
        in textStorage: NSTextStorage
    ) {
        let text = textStorage.string as NSString
        applyInlineChipWhitespaceSpacing(
            at: markdownRange.fullRange.location - 1,
            text: text,
            textStorage: textStorage
        )

        switch kind {
        case .fileLink:
            applyInlineChipWhitespaceSpacing(
                at: NSMaxRange(markdownRange.fullRange),
                text: text,
                textStorage: textStorage
            )
        case .slashCommand, .rawSlashCommand:
            break
        }
    }

    private static func applyInlineChipWhitespaceSpacing(
        at location: Int,
        text: NSString,
        textStorage: NSTextStorage
    ) {
        guard location >= 0,
              location < text.length,
              Self.isInlineChipAdjacentSpacerCharacter(text.character(at: location)) else {
            return
        }
        textStorage.addAttribute(
            .kern,
            value: inlineChipAdjacentWhitespaceKern,
            range: NSRange(location: location, length: 1)
        )
    }

    private static func isInlineChipAdjacentSpacerCharacter(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(Int(character)) else {
            return false
        }
        return CharacterSet.whitespaces.contains(scalar)
    }

    private static func applyFontTrait(
        _ trait: NSFontTraitMask,
        to range: NSRange,
        in textStorage: NSTextStorage,
        baseFont: NSFont
    ) {
        var fontUpdates: [(NSFont, NSRange)] = []
        textStorage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? baseFont
            fontUpdates.append((NSFontManager.shared.convert(font, toHaveTrait: trait), subrange))
        }
        for (font, subrange) in fontUpdates {
            textStorage.addAttribute(.font, value: font, range: subrange)
        }
    }

    static func applyingInlineMarkdownStyles(
        _ styles: Set<BlockInputInlineMarkdownStyle>,
        to attributes: [NSAttributedString.Key: Any],
        baseFont: NSFont
    ) -> [NSAttributedString.Key: Any] {
        var attributes = attributes
        for style in styles.sortedByAttributeOrder {
            switch style {
            case .bold:
                attributes[.font] = NSFontManager.shared.convert((attributes[.font] as? NSFont) ?? baseFont, toHaveTrait: .boldFontMask)
            case .italic:
                attributes[.font] = NSFontManager.shared.convert((attributes[.font] as? NSFont) ?? baseFont, toHaveTrait: .italicFontMask)
            case .underline:
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case .strikethrough:
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case .link:
                attributes[.foregroundColor] = NSColor.linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case .rawSlashCommand:
                break
            }
        }
        return attributes
    }

    private static func inlineMarkdownDelimiterFont(for font: NSFont) -> NSFont {
        .systemFont(ofSize: max(font.pointSize * 0.1, 1), weight: .regular)
    }
}

private extension Set where Element == BlockInputInlineMarkdownStyle {
    var sortedByAttributeOrder: [BlockInputInlineMarkdownStyle] {
        [.bold, .italic, .underline, .strikethrough, .link, .rawSlashCommand].filter { contains($0) }
    }
}

private extension NSRange {
    func intersectsStyledContent(_ range: NSRange) -> Bool {
        if length == 0 {
            // Insertion immediately before a closing delimiter is still inside
            // the visual span, so typed text should inherit the active style.
            return location >= range.location && location <= NSMaxRange(range)
        }
        return NSIntersectionRange(self, range).length > 0
    }

    func subtractingSorted(_ excludedRanges: [NSRange]) -> [NSRange] {
        // Inline-code ranges are emitted in source order, so binary search can
        // skip non-overlapping code spans before subtracting intersections.
        var remainingRanges = [self]
        let upperBound = NSMaxRange(self)
        var excludedRangeIndex = excludedRanges.firstPossibleIntersectionIndex(with: self)
        while excludedRangeIndex < excludedRanges.count {
            let excludedRange = excludedRanges[excludedRangeIndex]
            if excludedRange.location >= upperBound {
                break
            }
            remainingRanges = remainingRanges.flatMap { $0.subtracting(excludedRange) }
            if remainingRanges.isEmpty {
                break
            }
            excludedRangeIndex += 1
        }
        return remainingRanges
    }

    func subtracting(_ excludedRange: NSRange) -> [NSRange] {
        let intersection = NSIntersectionRange(self, excludedRange)
        guard intersection.length > 0 else {
            return [self]
        }
        var ranges: [NSRange] = []
        if intersection.location > location {
            ranges.append(NSRange(location: location, length: intersection.location - location))
        }
        let intersectionUpperBound = NSMaxRange(intersection)
        if intersectionUpperBound < NSMaxRange(self) {
            ranges.append(NSRange(location: intersectionUpperBound, length: NSMaxRange(self) - intersectionUpperBound))
        }
        return ranges
    }
}

private extension [NSRange] {
    func firstPossibleIntersectionIndex(with range: NSRange) -> Int {
        var lowerBound = 0
        var upperBound = count
        while lowerBound < upperBound {
            let middleIndex = (lowerBound + upperBound) / 2
            if NSMaxRange(self[middleIndex]) <= range.location {
                lowerBound = middleIndex + 1
            } else {
                upperBound = middleIndex
            }
        }
        return lowerBound
    }
}
