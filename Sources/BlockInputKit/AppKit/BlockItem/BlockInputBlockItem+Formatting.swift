import AppKit

extension BlockInputBlockItem {
    static func verticalMetrics(
        for block: BlockInputBlock,
        blockVerticalInsetMultiplier: CGFloat = 1
    ) -> BlockInputBlockItemVerticalMetrics {
        let metrics: BlockInputBlockItemVerticalMetrics
        switch block.kind {
        case .bulletedListItem, .numberedListItem:
            metrics = .textList
        case .checklistItem:
            metrics = .checklist
        case .paragraph:
            metrics = .textBlock
        case .quote:
            metrics = .quote
        case .heading, .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            metrics = .standard
        }
        return metrics.scaled(by: blockVerticalInsetMultiplier)
    }

    static func prefix(for kind: BlockInputBlockKind, indentationLevel: Int) -> String {
        switch kind {
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return ""
        case .bulletedListItem:
            return unorderedListMarker(indentationLevel: indentationLevel)
        case let .numberedListItem(start):
            return orderedListMarker(start: start, indentationLevel: indentationLevel)
        case let .checklistItem(isChecked):
            return isChecked ? "[x]" : "[ ]"
        }
    }

    static func font(for kind: BlockInputBlockKind, style: BlockInputStyle = .default) -> NSFont {
        let defaultBaseFont = NSFont.preferredFont(forTextStyle: .body)
        let customBaseFont = style.baseText.font
        let baseFont = customBaseFont ?? defaultBaseFont
        let scale = customBaseFont.map { $0.pointSize / max(defaultBaseFont.pointSize, 1) } ?? 1
        switch kind {
        case let .heading(level):
            let clampedLevel = min(max(level, 1), 6)
            let sizes: [CGFloat] = [26, 23, 20, 18, 16, 15]
            guard customBaseFont != nil else {
                return .systemFont(ofSize: sizes[clampedLevel - 1], weight: .semibold)
            }
            let headingFont = NSFontManager.shared.convert(baseFont, toSize: sizes[clampedLevel - 1] * scale)
            return NSFontManager.shared.convert(headingFont, toHaveTrait: .boldFontMask)
        case .code, .frontMatter, .rawMarkdown:
            if case .code = kind, let font = style.codeBlock.font {
                return font
            }
            guard customBaseFont != nil else {
                return .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            }
            return .monospacedSystemFont(ofSize: NSFont.systemFontSize * scale, weight: .regular)
        case .paragraph, .horizontalRule, .quote, .bulletedListItem, .numberedListItem, .checklistItem, .table, .image:
            return baseFont
        }
    }

    /// Single owner of which block kinds carry `BlockInputTextStyle.lineSpacing`.
    ///
    /// Rendering and every offscreen measurement path read this, so they cannot drift.
    /// Code keeps its own monospace rhythm and horizontal-scroll geometry, and table
    /// cells measure through `BlockInputTableView+Measurement.swift`, which never sees
    /// the paragraph style this spacing rides on — spacing either would render taller
    /// than it measures.
    static func lineSpacing(for kind: BlockInputBlockKind, style: BlockInputStyle) -> CGFloat {
        switch kind {
        case .paragraph, .heading, .quote, .bulletedListItem, .numberedListItem, .checklistItem, .rawMarkdown:
            return max(0, style.baseText.lineSpacing)
        case .code, .table, .frontMatter, .horizontalRule, .image:
            return 0
        }
    }

    static func contentIndent(for block: BlockInputBlock) -> CGFloat {
        guard block.kind.supportsIndentation,
              block.lineIndentationLevels.isEmpty else {
            return 0
        }
        return contentIndent(forIndentationLevel: block.indentationLevel)
    }

    static func measuredContentIndent(for block: BlockInputBlock) -> CGFloat {
        guard block.kind.supportsIndentation else {
            return 0
        }
        let indentationLevel = block.lineIndentationLevels.max() ?? block.indentationLevel
        return contentIndent(forIndentationLevel: indentationLevel)
    }

    static func perLineContentIndent(for block: BlockInputBlock) -> CGFloat {
        guard block.kind.supportsIndentation,
              !block.lineIndentationLevels.isEmpty else {
            return 0
        }
        return measuredContentIndent(for: block)
    }

    static func contentIndent(forIndentationLevel indentationLevel: Int) -> CGFloat {
        CGFloat(max(0, indentationLevel)) * 24
    }

    static func prefixes(for block: BlockInputBlock) -> String {
        prefixes(
            for: block.kind,
            indentationLevel: block.indentationLevel,
            lineIndentationLevels: block.lineIndentationLevels,
            text: block.text
        )
    }

    static func prefixes(for kind: BlockInputBlockKind, indentationLevel: Int, text: String) -> String {
        prefixes(
            for: kind,
            indentationLevel: indentationLevel,
            lineIndentationLevels: [],
            text: text
        )
    }

    static func prefixes(
        for kind: BlockInputBlockKind,
        indentationLevel: Int,
        lineIndentationLevels: [Int],
        text: String
    ) -> String {
        let markerPrefix = prefix(for: kind, indentationLevel: indentationLevel)
        guard kind.repeatsPrefixForTextLines, !markerPrefix.isEmpty else {
            return markerPrefix
        }
        if case let .numberedListItem(start) = kind, !lineIndentationLevels.isEmpty {
            return numberedListMarkers(
                start: start,
                indentationLevel: indentationLevel,
                lineIndentationLevels: lineIndentationLevels,
                lineCount: lineCount(for: text)
            )
        }
        if !lineIndentationLevels.isEmpty {
            return (0..<lineCount(for: text))
                .map { lineOffset in
                    let lineIndentation = lineIndentationLevels.indices.contains(lineOffset)
                        ? lineIndentationLevels[lineOffset]
                        : indentationLevel
                    return prefix(for: kind, indentationLevel: lineIndentation)
                }
                .joined(separator: "\n")
        }
        if case let .numberedListItem(start) = kind {
            return (0..<lineCount(for: text))
                .map { lineOffset in
                    prefix(for: .numberedListItem(start: start + lineOffset), indentationLevel: indentationLevel)
                }
                .joined(separator: "\n")
        }
        return repeatedPrefix(markerPrefix, lineCount: lineCount(for: text))
    }

    static func markerLines(for block: BlockInputBlock) -> [BlockInputMarkerView.MarkerLine] {
        switch block.kind {
        case let .checklistItem(isChecked):
            let lineCount = lineCount(for: block.text)
            guard lineCount > 1 else {
                return []
            }
            let checkboxState: BlockInputMarkerView.CheckboxState = isChecked ? .checked : .unchecked
            return (0..<lineCount).map { lineIndex in
                if lineIndex == 0 {
                    return BlockInputMarkerView.MarkerLine(text: "", indentationLevel: 0)
                }
                return BlockInputMarkerView.MarkerLine(
                    text: "",
                    indentationLevel: markerIndentationLevel(for: block, lineIndex: lineIndex),
                    checkboxState: checkboxState
                )
            }
        default:
            let prefixes = prefixes(for: block)
            guard !prefixes.isEmpty else {
                return []
            }
            return BlockInputLineBreaks.lines(in: prefixes)
                .enumerated()
                .map { lineIndex, marker in
                    BlockInputMarkerView.MarkerLine(
                        text: marker,
                        indentationLevel: markerIndentationLevel(for: block, lineIndex: lineIndex)
                    )
                }
        }
    }

    private static func repeatedPrefix(_ prefix: String, lineCount: Int) -> String {
        Array(repeating: prefix, count: max(1, lineCount)).joined(separator: "\n")
    }

    private static func lineCount(for text: String) -> Int {
        BlockInputLineBreaks.lineCount(in: text)
    }

    private static func numberedListMarkers(
        start: Int,
        indentationLevel: Int,
        lineIndentationLevels: [Int],
        lineCount: Int
    ) -> String {
        var countersByLevel: [Int: Int] = [:]
        let baselineIndentationLevel = lineIndentationLevels.first ?? indentationLevel
        return (0..<lineCount)
            .map { lineOffset in
                let lineIndentation = lineIndentationLevels.indices.contains(lineOffset)
                    ? lineIndentationLevels[lineOffset]
                    : indentationLevel
                countersByLevel = countersByLevel.filter { $0.key <= lineIndentation }
                let counter = countersByLevel[lineIndentation, default: 0]
                countersByLevel[lineIndentation] = counter + 1
                let markerStart = lineIndentation == baselineIndentationLevel ? start + counter : counter + 1
                return prefix(for: .numberedListItem(start: markerStart), indentationLevel: lineIndentation)
            }
            .joined(separator: "\n")
    }

    private static func markerIndentationLevel(for block: BlockInputBlock, lineIndex: Int) -> Int {
        guard block.kind.supportsIndentation,
              !block.lineIndentationLevels.isEmpty else {
            return 0
        }
        return block.indentationLevel(forLine: lineIndex)
    }

    private static func unorderedListMarker(indentationLevel: Int) -> String {
        ["•", "◦", "▪"][max(0, indentationLevel) % 3]
    }

    private static func orderedListMarker(start: Int, indentationLevel: Int) -> String {
        switch max(0, indentationLevel) % 3 {
        case 1:
            return "\(alphabeticMarker(for: start))."
        case 2:
            return "\(romanMarker(for: start))."
        default:
            return "\(start)."
        }
    }

    private static func alphabeticMarker(for value: Int) -> String {
        let scalarValue = UnicodeScalar("a").value + UInt32(max(value - 1, 0) % 26)
        return UnicodeScalar(scalarValue).map(String.init) ?? "a"
    }

    private static func romanMarker(for value: Int) -> String {
        let markers = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x"]
        return markers[max(value - 1, 0) % markers.count]
    }

    func applyTextAttributes(for block: BlockInputBlock) {
        let font = Self.font(for: block.kind, style: style)
        let foregroundColor = foregroundColor(for: block.kind)
        textView.font = font
        textView.typingAttributes[.font] = font
        guard let textStorage = textView.textStorage else {
            updateTypingAttributesForCurrentSelection()
            return
        }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        guard fullRange.length > 0 else {
            updateTypingAttributesForCurrentSelection()
            return
        }
        textStorage.beginEditing()
        textStorage.addAttribute(.font, value: font, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: foregroundColor, range: fullRange)
        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        textStorage.removeAttribute(.underlineStyle, range: fullRange)
        textStorage.removeAttribute(.strikethroughStyle, range: fullRange)
        textStorage.removeAttribute(.link, range: fullRange)
        textStorage.removeAttribute(.toolTip, range: fullRange)
        textStorage.removeAttribute(.kern, range: fullRange)
        textStorage.removeAttribute(.baselineOffset, range: fullRange)
        textStorage.removeAttribute(.blockInputInlineChip, range: fullRange)
        textStorage.removeAttribute(.blockInputInlineImage, range: fullRange)
        textStorage.removeAttribute(.blockInputHiddenDelimiter, range: fullRange)
        textStorage.removeAttribute(.paragraphStyle, range: fullRange)
        applyBaseParagraphStyle(for: block, textStorage: textStorage, range: fullRange)
        applyCodeBlockAttributes(for: block, textStorage: textStorage)
        applyLineIndentationAttributes(for: block, textStorage: textStorage)
        applyInlineMarkdownAttributes(for: block, textStorage: textStorage)
        applyInlineCodeAttributes(for: block, textStorage: textStorage)
        applyFrontMatterKeyValueAttributes(for: block, textStorage: textStorage)
        applyFrontMatterValidationAttributes(for: block, textStorage: textStorage)
        textStorage.endEditing()
        textView.layoutManager?.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        textView.needsDisplay = true
        updateTypingAttributesForCurrentSelection()
    }

    func updateTypingAttributesForCurrentSelection() {
        guard let block = renderedBlock else {
            return
        }
        var attributes = textView.typingAttributes
        let font = Self.font(for: block.kind, style: style)
        attributes[.font] = font
        attributes.removeValue(forKey: .foregroundColor)
        attributes.removeValue(forKey: .backgroundColor)
        attributes.removeValue(forKey: .underlineStyle)
        attributes.removeValue(forKey: .strikethroughStyle)
        attributes.removeValue(forKey: .link)
        attributes.removeValue(forKey: .toolTip)
        attributes.removeValue(forKey: .kern)
        attributes.removeValue(forKey: .baselineOffset)
        attributes.removeValue(forKey: .blockInputInlineChip)
        attributes.removeValue(forKey: .blockInputInlineImage)
        attributes.removeValue(forKey: .blockInputHiddenDelimiter)
        if let foregroundColor = typingForegroundColor(for: block.kind) {
            attributes[.foregroundColor] = foregroundColor
        }
        let isInlineCodeSelection = currentSelectionIntersectsStyledContent(inlineCodeContentRanges(for: block))
        if isInlineCodeSelection {
            attributes[.font] = inlineCodeFont(for: font)
            attributes[.foregroundColor] = inlineCodeForegroundColor()
            attributes[.backgroundColor] = inlineCodeBackgroundColor()
        } else {
            attributes = Self.applyingInlineMarkdownStyles(
                inlineMarkdownStylesForCurrentSelection(in: block),
                to: attributes,
                baseFont: font
            )
        }
        let lineSpacing = Self.lineSpacing(for: block.kind, style: style)
        if block.kind.supportsIndentation, !block.lineIndentationLevels.isEmpty {
            let lineIndex = block.lineIndex(containingUTF16Offset: textView.selectedRange().location)
            let paragraphStyle = Self.paragraphStyle(
                indentationLevel: block.indentationLevel(forLine: lineIndex),
                lineSpacing: lineSpacing
            )
            attributes[.paragraphStyle] = paragraphStyle
            textView.defaultParagraphStyle = paragraphStyle
        } else if lineSpacing > 0 {
            // `defaultParagraphStyle` is what the extra line fragment lays out with, so an
            // empty block only measures the way it renders when the spacing lives here too.
            let paragraphStyle = Self.paragraphStyle(indentationLevel: 0, lineSpacing: lineSpacing)
            attributes[.paragraphStyle] = paragraphStyle
            textView.defaultParagraphStyle = paragraphStyle
        } else {
            attributes.removeValue(forKey: .paragraphStyle)
            textView.defaultParagraphStyle = nil
        }
        textView.typingAttributes = attributes
    }

    func applyKindLabelAttributes(for block: BlockInputBlock) {
        kindLabel.font = Self.font(for: block.kind, style: style)
        kindLabel.setMarkerLines(Self.markerLines(for: block))
        updateMarkerLineYOffsets()
    }

    /// Carries `lineSpacing` on kinds that opt into it, including the unindented ones the
    /// per-line indentation pass below skips.
    private func applyBaseParagraphStyle(for block: BlockInputBlock, textStorage: NSTextStorage, range: NSRange) {
        let lineSpacing = Self.lineSpacing(for: block.kind, style: style)
        guard lineSpacing > 0 else {
            return
        }
        textStorage.addAttribute(
            .paragraphStyle,
            value: Self.paragraphStyle(indentationLevel: 0, lineSpacing: lineSpacing),
            range: range
        )
    }

    private func applyLineIndentationAttributes(for block: BlockInputBlock, textStorage: NSTextStorage) {
        guard block.kind.supportsIndentation,
              !block.lineIndentationLevels.isEmpty else {
            return
        }
        let lineSpacing = Self.lineSpacing(for: block.kind, style: style)
        let text = textStorage.string as NSString
        var offset = 0
        var lineIndex = 0
        while offset < text.length {
            let lineRange = text.lineRange(for: NSRange(location: offset, length: 0))
            let paragraphStyle = Self.paragraphStyle(
                indentationLevel: block.indentationLevel(forLine: lineIndex),
                lineSpacing: lineSpacing
            )
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
            offset = NSMaxRange(lineRange)
            lineIndex += 1
        }
    }

    static func paragraphStyle(indentationLevel: Int, lineSpacing: CGFloat) -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        let indent = contentIndent(forIndentationLevel: indentationLevel)
        paragraphStyle.firstLineHeadIndent = indent
        paragraphStyle.headIndent = indent
        paragraphStyle.lineSpacing = max(0, lineSpacing)
        return paragraphStyle
    }

    func foregroundColor(for kind: BlockInputBlockKind) -> NSColor {
        if case .code = kind {
            return style.codeBlock.foregroundColor ?? style.baseText.foregroundColor ?? .labelColor
        }
        return readOnlyForegroundColor(style.baseText.foregroundColor ?? .labelColor, for: kind)
    }

    private func typingForegroundColor(for kind: BlockInputBlockKind) -> NSColor? {
        if case .code = kind {
            return style.codeBlock.foregroundColor ?? style.baseText.foregroundColor
        }
        guard !isEditable else {
            return style.baseText.foregroundColor
        }
        return readOnlyForegroundColor(style.baseText.foregroundColor ?? .labelColor, for: kind)
    }
}
