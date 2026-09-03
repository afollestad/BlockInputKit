import AppKit

extension BlockInputBlockItem {
    static func height(
        for block: BlockInputBlock,
        textWidth: CGFloat,
        style: BlockInputStyle = .default,
        fileBaseURL: URL? = nil,
        rawSlashCommandChips: Bool = false,
        rawFileMentionChips: Bool = false,
        slashCommandAvailability: BlockInputSlashCommandAvailability = .documentStart,
        isDocumentStartBlock: Bool = false,
        blockVerticalInsetMultiplier: CGFloat = 1,
        inlineImageSizes: BlockInputInlineImageSizes = .empty
    ) -> CGFloat {
        let text = block.text.isEmpty ? " " : block.text
        let availableTextWidth = max(textWidth - perLineContentIndent(for: block), 120)
        let font = font(for: block.kind, style: style)
        let metrics = verticalMetrics(for: block, blockVerticalInsetMultiplier: blockVerticalInsetMultiplier)
        if block.kind == .table,
           let table = BlockInputTable(markdown: block.text) {
            return max(
                metrics.minimumHeight,
                BlockInputTableView.height(
                    for: table,
                    width: availableTextWidth,
                    style: style,
                    blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
                )
                    + (scaledTableExternalVerticalInset(for: blockVerticalInsetMultiplier) * 2)
            )
        }
        if case let .image(image) = block.kind {
            return imageHeight(
                for: image,
                textWidth: availableTextWidth,
                defaultAspectRatio: style.imageBlock.placeholderAspectRatio ?? 16.0 / 9.0,
                blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
            )
        }
        if case .code = block.kind {
            return codeBlockHeight(text: text, availableTextWidth: availableTextWidth, font: font, metrics: metrics)
        }
        let textConfiguration = BlockInputTextHeightConfiguration(
            style: style,
            fileBaseURL: fileBaseURL,
            rawSlashCommandChips: rawSlashCommandChips,
            rawFileMentionChips: rawFileMentionChips,
            slashCommandAvailability: slashCommandAvailability,
            isDocumentStartBlock: isDocumentStartBlock,
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier,
            inlineImageSizes: inlineImageSizes
        )
        return textBlockHeight(textHeightContext(
            for: block,
            text: text,
            availableTextWidth: availableTextWidth,
            font: font,
            metrics: metrics,
            configuration: textConfiguration
        ))
    }

    private static func textHeightContext(
        for block: BlockInputBlock,
        text: String,
        availableTextWidth: CGFloat,
        font: NSFont,
        metrics: BlockInputBlockItemVerticalMetrics,
        configuration: BlockInputTextHeightConfiguration
    ) -> BlockInputTextHeightContext {
        let inlineCodeRanges = inlineCodeRangesForHeight(for: block, text: text)
        let inlineMarkdownRanges = inlineMarkdownRangesForHeight(
            for: block,
            text: text,
            inlineCodeRanges: inlineCodeRanges,
            configuration: configuration
        )
        let hiddenDelimiterRanges = (
            inlineCodeRanges.flatMap(\.delimiterRanges)
                + inlineMarkdownRanges.flatMap(\.delimiterRanges)
        ).sorted { first, second in
            first.location < second.location
        }
        let frontMatterReserve = block.kind == .frontMatter
            ? (scaledFrontMatterDividerVerticalInset(for: configuration.blockVerticalInsetMultiplier) * 2) + frontMatterDividerHeight
            : 0
        return BlockInputTextHeightContext(
            text: text,
            availableTextWidth: availableTextWidth,
            font: font,
            metrics: metrics,
            hiddenDelimiterRanges: hiddenDelimiterRanges,
            inlineCodeRanges: inlineCodeRanges,
            containsInlineChip: inlineMarkdownRanges.contains { $0.inlineChipKind(in: text) != nil },
            containsInlineImage: inlineMarkdownRanges.contains { $0.style == .inlineImage },
            frontMatterReserve: frontMatterReserve,
            lineSpacing: lineSpacing(for: block.kind, style: configuration.style),
            style: configuration.style,
            block: block,
            fileBaseURL: configuration.fileBaseURL,
            rawSlashCommandChips: configuration.rawSlashCommandChips,
            rawFileMentionChips: configuration.rawFileMentionChips,
            slashCommandAvailability: configuration.slashCommandAvailability,
            isDocumentStartBlock: configuration.isDocumentStartBlock,
            inlineImageSizes: configuration.inlineImageSizes
        )
    }

    private static func codeBlockHeight(
        text: String,
        availableTextWidth: CGFloat,
        font: NSFont,
        metrics: BlockInputBlockItemVerticalMetrics
    ) -> CGFloat {
        let codeWidth = max(unwrappedTextWidth(for: text, font: font), availableTextWidth)
        let horizontalScrollerReserve = codeWidth > availableTextWidth ? codeHorizontalScrollerReserve : 0
        return max(
            metrics.minimumHeight,
            textKitHeight(for: text, width: codeWidth, font: font)
                + metrics.topContentInset
                + metrics.bottomContentInset
                + horizontalScrollerReserve
                + 2
        )
    }

    private static func textBlockHeight(_ context: BlockInputTextHeightContext) -> CGFloat {
        if context.inlineCodeRanges.isEmpty,
           !context.containsInlineChip,
           !context.containsInlineImage,
           isShortSingleLine(context.text, likelyFitting: context.availableTextWidth, font: context.font) {
            return max(
                context.metrics.minimumHeight + context.frontMatterReserve,
                // No spacing term: TextKit puts `lineSpacing` between lines only, so a
                // single-line row measures exactly as it renders.
                singleLineTextHeight(font: context.font)
                    + context.metrics.topContentInset
                    + context.metrics.bottomContentInset
                    + context.frontMatterReserve
                    + 2
            )
        }
        let boundingHeight = boundingRectHeight(context)
        let textKitHeight = textKitHeight(
            for: context.text,
            width: context.availableTextWidth,
            font: context.font,
            hiddenDelimiterRanges: context.hiddenDelimiterRanges,
            inlineCodeRanges: context.inlineCodeRanges,
            style: context.style,
            lineSpacing: context.lineSpacing,
            inlineChipMeasurement: context.containsInlineChip || context.containsInlineImage
                ? BlockInputInlineChipHeightMeasurement(
                    block: context.block,
                    fileBaseURL: context.fileBaseURL,
                    rawSlashCommandChips: context.rawSlashCommandChips,
                    rawFileMentionChips: context.rawFileMentionChips,
                    slashCommandAvailability: context.slashCommandAvailability,
                    isDocumentStartBlock: context.isDocumentStartBlock,
                    inlineImageSizes: context.inlineImageSizes,
                    inlineImageMaximumWidth: context.availableTextWidth
                )
                : nil
        )
        let measuredTextHeight = context.hiddenDelimiterRanges.isEmpty
            ? max(ceil(boundingHeight), textKitHeight)
            : textKitHeight
        return max(
            context.metrics.minimumHeight + context.frontMatterReserve,
            measuredTextHeight
                + context.metrics.topContentInset
                + context.metrics.bottomContentInset
                + context.frontMatterReserve
                + 2
        )
    }

    /// `NSString` wrapping height, carrying the block's line spacing so it stays comparable with
    /// the TextKit measurement it is maxed against.
    private static func boundingRectHeight(_ context: BlockInputTextHeightContext) -> CGFloat {
        var attributes: [NSAttributedString.Key: Any] = [.font: context.font]
        if context.lineSpacing > 0 {
            attributes[.paragraphStyle] = paragraphStyle(indentationLevel: 0, lineSpacing: context.lineSpacing)
        }
        return (context.text as NSString).boundingRect(
            with: NSSize(width: context.availableTextWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).height
    }

    private static func isShortSingleLine(_ text: String, likelyFitting width: CGFloat, font: NSFont) -> Bool {
        guard text.rangeOfCharacter(from: .newlines) == nil else {
            return false
        }
        guard text.utf16.count <= 24 else {
            return false
        }
        let conservativeCharacterWidth = max(font.pointSize * 0.75, 1)
        return CGFloat(text.utf16.count) * conservativeCharacterWidth <= width
    }

    /// Deliberately spacing-free: `NSParagraphStyle.lineSpacing` grows the gaps *between* lines
    /// and leaves the last one alone, so a one-line height must not carry it.
    private static func singleLineTextHeight(font: NSFont) -> CGFloat {
        let boundingRect = (" " as NSString).boundingRect(
            with: NSSize(width: 120, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(boundingRect.height)
    }

    private static func textKitHeight(
        for text: String,
        width: CGFloat,
        font: NSFont,
        hiddenDelimiterRanges: [NSRange] = [],
        inlineCodeRanges: [BlockInputInlineCodeRange] = [],
        style: BlockInputStyle = .default,
        lineSpacing: CGFloat = 0,
        inlineChipMeasurement: BlockInputInlineChipHeightMeasurement? = nil
    ) -> CGFloat {
        var baseAttributes: [NSAttributedString.Key: Any] = [.font: font]
        if lineSpacing > 0 {
            baseAttributes[.paragraphStyle] = paragraphStyle(indentationLevel: 0, lineSpacing: lineSpacing)
        }
        let textStorage = NSTextStorage(string: text, attributes: baseAttributes)
        let layoutManager = NSLayoutManager()
        let delimiterGlyphs = hiddenDelimiterRanges.isEmpty ? nil : BlockInputDelimiterGlyphs()
        layoutManager.delegate = delimiterGlyphs
        let textContainer = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        applyInlineCodeHeightAttributes(
            inlineCodeRanges,
            font: font,
            style: style,
            textStorage: textStorage,
            fullRange: fullRange
        )
        if let inlineChipMeasurement {
            applyInlineMarkdownAttributes(
                for: inlineChipMeasurement.block,
                textStorage: textStorage,
                style: style,
                fileBaseURL: inlineChipMeasurement.fileBaseURL,
                rawSlashCommandChips: inlineChipMeasurement.rawSlashCommandChips,
                rawFileMentionChips: inlineChipMeasurement.rawFileMentionChips,
                slashCommandAvailability: inlineChipMeasurement.slashCommandAvailability,
                isDocumentStartBlock: inlineChipMeasurement.isDocumentStartBlock,
                inlineImageSizes: inlineChipMeasurement.inlineImageSizes,
                inlineImageMaximumWidth: inlineChipMeasurement.inlineImageMaximumWidth
            )
        }
        for delimiterRange in hiddenDelimiterRanges {
            let clampedDelimiterRange = NSIntersectionRange(delimiterRange, fullRange)
            guard clampedDelimiterRange.length > 0 else {
                continue
            }
            textStorage.addAttribute(.blockInputHiddenDelimiter, value: true, range: clampedDelimiterRange)
        }
        return withExtendedLifetime(delimiterGlyphs) {
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            return ceil(max(usedRect.maxY, singleLineTextHeight(font: font)))
        }
    }

    private static func inlineCodeRangesForHeight(for block: BlockInputBlock, text: String) -> [BlockInputInlineCodeRange] {
        guard supportsInlineCodeStyling(block.kind) else {
            return []
        }
        return BlockInputCodeParsing.inlineCodeRanges(in: text)
    }

    private static func applyInlineCodeHeightAttributes(
        _ inlineCodeRanges: [BlockInputInlineCodeRange],
        font: NSFont,
        style: BlockInputStyle,
        textStorage: NSTextStorage,
        fullRange: NSRange
    ) {
        guard !inlineCodeRanges.isEmpty else {
            return
        }
        let inlineFont = inlineCodeFont(for: font, style: style)
        let delimiterFont = inlineCodeDelimiterFont(for: font)
        for inlineCodeRange in inlineCodeRanges {
            let spanRange = NSIntersectionRange(inlineCodeRange.fullRange, fullRange)
            if spanRange.length > 0 {
                textStorage.addAttribute(.blockInputInlineCode, value: true, range: spanRange)
            }
            let contentRange = NSIntersectionRange(inlineCodeRange.contentRange, fullRange)
            if contentRange.length > 0 {
                textStorage.addAttribute(.font, value: inlineFont, range: contentRange)
            }
            for delimiterRange in inlineCodeRange.delimiterRanges {
                let clampedDelimiterRange = NSIntersectionRange(delimiterRange, fullRange)
                guard clampedDelimiterRange.length > 0 else {
                    continue
                }
                textStorage.addAttribute(.font, value: delimiterFont, range: clampedDelimiterRange)
            }
        }
    }

    private static func inlineMarkdownRangesForHeight(
        for block: BlockInputBlock,
        text: String,
        inlineCodeRanges: [BlockInputInlineCodeRange],
        configuration: BlockInputTextHeightConfiguration
    ) -> [BlockInputInlineMarkdownRange] {
        guard supportsInlineMarkdownStyling(block.kind) else {
            return []
        }
        return BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: inlineCodeRanges.map(\.fullRange),
            fileBaseURL: configuration.fileBaseURL,
            rawSlashCommandChips: configuration.rawSlashCommandChips,
            rawFileMentionChips: configuration.rawFileMentionChips,
            slashCommandAvailability: configuration.slashCommandAvailability,
            isDocumentStartBlock: configuration.isDocumentStartBlock
        )
    }

    private static func unwrappedTextWidth(for text: String, font: NSFont) -> CGFloat {
        text.components(separatedBy: .newlines)
            .map { line in
                let measuredLine = line.isEmpty ? " " : line
                return ceil((measuredLine as NSString).size(withAttributes: [.font: font]).width)
            }
            .max() ?? 120
    }
}

private struct BlockInputTextHeightContext {
    var text: String
    var availableTextWidth: CGFloat
    var font: NSFont
    var metrics: BlockInputBlockItemVerticalMetrics
    var hiddenDelimiterRanges: [NSRange]
    var inlineCodeRanges: [BlockInputInlineCodeRange]
    var containsInlineChip: Bool
    var containsInlineImage: Bool
    var frontMatterReserve: CGFloat
    /// Mirrors `BlockInputBlockItem.lineSpacing(for:style:)` so offscreen heights match rows
    /// laid out with the same paragraph style.
    var lineSpacing: CGFloat
    var style: BlockInputStyle
    var block: BlockInputBlock
    var fileBaseURL: URL?
    var rawSlashCommandChips: Bool
    var rawFileMentionChips: Bool
    var slashCommandAvailability: BlockInputSlashCommandAvailability
    var isDocumentStartBlock: Bool
    var inlineImageSizes: BlockInputInlineImageSizes
}

private struct BlockInputInlineChipHeightMeasurement {
    var block: BlockInputBlock
    var fileBaseURL: URL?
    var rawSlashCommandChips: Bool
    var rawFileMentionChips: Bool
    var slashCommandAvailability: BlockInputSlashCommandAvailability
    var isDocumentStartBlock: Bool
    var inlineImageSizes: BlockInputInlineImageSizes
    var inlineImageMaximumWidth: CGFloat
}

private struct BlockInputTextHeightConfiguration {
    var style: BlockInputStyle
    var fileBaseURL: URL?
    var rawSlashCommandChips: Bool
    var rawFileMentionChips: Bool
    var slashCommandAvailability: BlockInputSlashCommandAvailability
    var isDocumentStartBlock: Bool
    var blockVerticalInsetMultiplier: CGFloat
    var inlineImageSizes: BlockInputInlineImageSizes
}
