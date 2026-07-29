import AppKit

extension BlockInputTableView {
    /// Shared rendered/offscreen table measurement path; keep this in parity
    /// with `layoutTable()` so wrapped cell edits move following blocks
    /// immediately and snapshot tests stay deterministic.
    static func layoutMetrics(
        for table: BlockInputTable,
        viewportWidth: CGFloat,
        style: BlockInputStyle,
        blockVerticalInsetMultiplier: CGFloat = 1
    ) -> BlockInputTableLayoutMetrics {
        let rows = rowModels(for: table)
        let columnWidths = (0..<table.columnCount).map { columnIndex in
            columnWidth(columnIndex, rows: rows, style: style)
        }
        let naturalWidth = columnWidths.reduce(0, +)
        let viewportWidth = tableViewportWidth(naturalWidth: naturalWidth, proposedWidth: viewportWidth)
        let rowHeights = rows.enumerated().map { rowIndex, row in
            (0..<table.columnCount).map { columnIndex in
                measuredCellHeight(
                    row[columnIndex].text,
                    isHeader: rowIndex == 0,
                    width: columnWidths[columnIndex],
                    alignment: textAlignment(for: table.alignments[columnIndex]),
                    style: style,
                    blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
                )
            }.max() ?? 0
        }
        let tableHeight = rowHeights.reduce(0, +)
        let scrollerReserve = naturalWidth > viewportWidth + 0.5 ? horizontalScrollbarReserve : 0
        return BlockInputTableLayoutMetrics(
            columnWidths: columnWidths,
            rowHeights: rowHeights,
            naturalWidth: naturalWidth,
            viewportWidth: viewportWidth,
            tableHeight: tableHeight,
            height: ceil(tableHeight + scrollerReserve)
        )
    }

    static func rowModels(for table: BlockInputTable) -> [[BlockInputTable.Cell]] {
        [table.header] + table.bodyRows
    }

    static func columnWidth(
        _ columnIndex: Int,
        rows: [[BlockInputTable.Cell]],
        style: BlockInputStyle
    ) -> CGFloat {
        let naturalWidth = rows.enumerated().map { rowIndex, row in
            measuredUnwrappedTextWidth(row[columnIndex].text, isHeader: rowIndex == 0, style: style)
        }.max() ?? 0
        let paddedWidth = ceil(naturalWidth + cellHorizontalPadding * 2)
        return min(max(paddedWidth, minimumColumnWidth), maximumColumnWidth)
    }

    static func tableViewportWidth(naturalWidth: CGFloat, proposedWidth: CGFloat) -> CGFloat {
        let proposedWidth = proposedWidth > 0 ? proposedWidth : fallbackViewportWidth
        return min(naturalWidth, max(proposedWidth, 0))
    }

    static func measuredUnwrappedTextWidth(_ text: String, isHeader: Bool, style: BlockInputStyle) -> CGFloat {
        let attributed = attributedString(text, isHeader: isHeader, alignment: .left, style: style)
        return ceil(measuredTextRect(for: attributed, width: 100_000).width)
    }

    static func measuredCellHeight(
        _ text: String,
        isHeader: Bool,
        width: CGFloat,
        alignment: NSTextAlignment,
        style: BlockInputStyle,
        blockVerticalInsetMultiplier: CGFloat = 1
    ) -> CGFloat {
        let attributed = attributedString(text, isHeader: isHeader, alignment: alignment, style: style)
        let textWidth = max(width - cellHorizontalPadding * 2, 0)
        let minimumHeight = lineHeight(isHeader: isHeader, style: style)
        let verticalPadding = scaledCellVerticalPadding(for: blockVerticalInsetMultiplier)
        return ceil(max(measuredTextRect(for: attributed, width: textWidth).height, minimumHeight) + verticalPadding * 2)
    }

    static func attributedString(
        _ text: String,
        isHeader: Bool,
        alignment: NSTextAlignment,
        style: BlockInputStyle,
        usesPlaceholder: Bool = true,
        appliesInlineMarkdown: Bool = true,
        isEditable: Bool = true
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        let string = usesPlaceholder ? displayText(text) : text
        let storage = NSTextStorage(
            string: string,
            attributes: [
                .font: font(isHeader: isHeader, style: style),
                .foregroundColor: style.baseText.foregroundColor ?? NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        if appliesInlineMarkdown {
            // Table cells keep alt-label link rendering for image syntax; the cell
            // text views have no inline-image draw/measure support yet.
            BlockInputBlockItem.applyInlineMarkdownAttributes(
                for: BlockInputBlock(kind: .paragraph, text: string),
                textStorage: storage,
                style: style,
                inlineImages: false
            )
        }
        if !isEditable {
            BlockInputReadOnlyStyle.applyDisabledForeground(to: storage)
        }
        return storage
    }

    private static func measuredTextRect(for attributed: NSAttributedString, width: CGFloat) -> NSRect {
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let delimiterGlyphs = BlockInputDelimiterGlyphs()
        layoutManager.delegate = delimiterGlyphs
        let textContainer = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        return withExtendedLifetime(delimiterGlyphs) {
            layoutManager.ensureLayout(for: textContainer)
            return layoutManager.usedRect(for: textContainer)
        }
    }

    static func font(isHeader: Bool, style: BlockInputStyle) -> NSFont {
        let baseFont = BlockInputBlockItem.font(for: .paragraph, style: style)
        guard isHeader else {
            return baseFont
        }
        return NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
    }

    static func lineHeight(isHeader: Bool, style: BlockInputStyle) -> CGFloat {
        let font = font(isHeader: isHeader, style: style)
        return ceil(font.ascender - font.descender + font.leading)
    }

    static func scaledCellVerticalPadding(for blockVerticalInsetMultiplier: CGFloat) -> CGFloat {
        BlockInputBlockItem.scaledVerticalInset(
            cellVerticalPadding,
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
        )
    }

    static func displayText(_ text: String) -> String {
        text.isEmpty ? " " : text
    }

    static func textAlignment(for alignment: BlockInputTable.Alignment) -> NSTextAlignment {
        switch alignment {
        case .left:
            return .left
        case .center:
            return .center
        case .right:
            return .right
        }
    }

    static var horizontalScrollbarReserve: CGFloat {
        ceil(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay))
    }
}
