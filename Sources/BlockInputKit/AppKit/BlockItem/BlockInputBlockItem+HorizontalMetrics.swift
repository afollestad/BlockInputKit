import AppKit

struct BlockInputBlockItemHorizontalMetrics {
    var handleLeading: CGFloat
    var handleWidth: CGFloat
    var kindLabelLeading: CGFloat
    var kindLabelWidth: CGFloat
    var scrollViewLeading: CGFloat
    var scrollViewTrailingInset: CGFloat
    var scrollViewWidth: CGFloat
    var textContainerWidth: CGFloat
    var glyphLeadingX: CGFloat
}

extension BlockInputBlockItem {
    static let tableSurfaceLeadingInset: CGFloat = textContainerContentLeading
    static let tableSurfaceTrailingInset: CGFloat = tableSurfaceLeadingInset
    private static let minimumWrappingViewportWidth: CGFloat = 24

    static func horizontalMetrics(
        for itemWidth: CGFloat,
        block: BlockInputBlock,
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset,
        style: BlockInputStyle = .default
    ) -> BlockInputBlockItemHorizontalMetrics {
        let clampedItemWidth = max(itemWidth, 0)
        let handleLeading = handleLeadingInset(
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset
        )
        let handleWidth = allowsReordering ? Self.handleWidth : 0
        let kindLabelLeading = kindLabelLeadingConstant(
            for: block,
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset
        )
        let kindLabelWidth = kindLabelWidthConstant(for: block, style: style)
        let scrollViewLeading = textLeadingConstant(
            for: block,
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset
        )
        let scrollViewTrailingInset = horizontalContentTrailingInset(
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset
        )
        let scrollViewMinX = handleLeading + handleWidth + kindLabelLeading + kindLabelWidth + scrollViewLeading
        guard clampedItemWidth > 0 else {
            return BlockInputBlockItemHorizontalMetrics(
                handleLeading: handleLeading,
                handleWidth: handleWidth,
                kindLabelLeading: kindLabelLeading,
                kindLabelWidth: kindLabelWidth,
                scrollViewLeading: scrollViewLeading,
                scrollViewTrailingInset: scrollViewTrailingInset,
                scrollViewWidth: 0,
                textContainerWidth: 1,
                glyphLeadingX: scrollViewMinX + textContainerContentLeading
            )
        }
        let normalScrollViewWidth = clampedItemWidth - scrollViewMinX - scrollViewTrailingInset
        guard normalScrollViewWidth >= minimumWrappingViewportWidth else {
            return collapsedHorizontalMetrics(itemWidth: clampedItemWidth)
        }

        return BlockInputBlockItemHorizontalMetrics(
            handleLeading: handleLeading,
            handleWidth: handleWidth,
            kindLabelLeading: kindLabelLeading,
            kindLabelWidth: kindLabelWidth,
            scrollViewLeading: scrollViewLeading,
            scrollViewTrailingInset: scrollViewTrailingInset,
            scrollViewWidth: normalScrollViewWidth,
            textContainerWidth: wrappingTextWidth(forScrollViewWidth: normalScrollViewWidth),
            glyphLeadingX: scrollViewMinX + textContainerContentLeading
        )
    }

    /// Room the glyph column gets inside a text scroll view of `scrollViewWidth`.
    ///
    /// `NSTextView` keeps `textContainerInset.width` plus the container's line-fragment
    /// padding — together `textContainerContentLeading` — clear on each side, so measuring
    /// with only the padding subtracted reports a column 2 × `textContainerInset.width`
    /// wider than the mounted view wraps at. The block then renders one line taller than
    /// its measured height and the collection view clips that line.
    private static func wrappingTextWidth(forScrollViewWidth scrollViewWidth: CGFloat) -> CGFloat {
        max(scrollViewWidth - 2 * textContainerContentLeading, 1)
    }

    private static func collapsedHorizontalMetrics(itemWidth: CGFloat) -> BlockInputBlockItemHorizontalMetrics {
        BlockInputBlockItemHorizontalMetrics(
            handleLeading: 0,
            handleWidth: 0,
            kindLabelLeading: 0,
            kindLabelWidth: 0,
            scrollViewLeading: 0,
            scrollViewTrailingInset: 0,
            scrollViewWidth: itemWidth,
            textContainerWidth: wrappingTextWidth(forScrollViewWidth: itemWidth),
            glyphLeadingX: min(textContainerContentLeading, max(itemWidth - 1, 0))
        )
    }

    static func horizontalContentTrailingInset(
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset
    ) -> CGFloat {
        horizontalChromeWidth(
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset
        )
    }

    static func measuredTextWidth(
        for itemWidth: CGFloat,
        block: BlockInputBlock,
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset,
        style: BlockInputStyle = .default
    ) -> CGFloat {
        let scrollViewWidth = textScrollViewWidth(
            for: itemWidth,
            block: block,
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset,
            style: style
        )
        if block.kind.isImage {
            return max(scrollViewWidth - (2 * imageSurfaceHorizontalInset), 120)
        }
        return horizontalMetrics(
            for: itemWidth,
            block: block,
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset,
            style: style
        ).textContainerWidth
    }

    static func codeBackgroundLeadingInset(
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset
    ) -> CGFloat {
        horizontalChromeWidth(
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset
        ) + textContainerContentLeading
    }

    static func codeBackgroundTrailingInset(
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset
    ) -> CGFloat {
        codeBackgroundLeadingInset(
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset
        )
    }

    static func horizontalRuleTrailingInset(allowsReordering _: Bool) -> CGFloat {
        horizontalRuleInnerInset
    }

    static func textScrollViewWidth(
        for itemWidth: CGFloat,
        block: BlockInputBlock,
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset,
        style: BlockInputStyle = .default
    ) -> CGFloat {
        horizontalMetrics(
            for: itemWidth,
            block: block,
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset,
            style: style
        ).scrollViewWidth
    }

    private static func kindLabelLeadingConstant(
        for block: BlockInputBlock,
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat
    ) -> CGFloat {
        let contentIndent = contentIndent(for: block)
        switch block.kind {
        case .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return markerAlignmentLeadingConstant(
                allowsReordering: allowsReordering,
                editorHorizontalInset: editorHorizontalInset
            ) + contentIndent
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            return contentIndent
        }
    }

    private static func kindLabelWidthConstant(for block: BlockInputBlock, style: BlockInputStyle) -> CGFloat {
        guard block.kind.needsMeasuredMarkerLane else {
            return 0
        }
        if block.kind == .quote {
            return 0
        }
        return markerGutterWidth(for: block, style: style) + perLineContentIndent(for: block)
    }

    private static func textLeadingConstant(
        for block: BlockInputBlock,
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat
    ) -> CGFloat {
        if block.kind == .quote {
            return quoteTextLeading
        }
        if block.kind.supportsIndentation {
            return listTextLeading - perLineContentIndent(for: block)
        }
        return textScrollViewEdgeInset(
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset
        ) - handleTrailingX(
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset
        ) - contentIndent(for: block)
    }

    static func horizontalChromeWidth(
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset
    ) -> CGFloat {
        textScrollViewEdgeInset(
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset
        )
    }

    static func textScrollViewEdgeInset(
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat
    ) -> CGFloat {
        max(
            visualContentInset(
                allowsReordering: allowsReordering,
                editorHorizontalInset: editorHorizontalInset
            ) - textContainerContentLeading,
            0
        )
    }

    static func handleLeadingInset(
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat
    ) -> CGFloat {
        guard allowsReordering else {
            return 0
        }
        return max(
            (visualContentInset(
                allowsReordering: allowsReordering,
                editorHorizontalInset: editorHorizontalInset
            ) - handleWidth) / 2,
            0
        )
    }

    static func handleTrailingX(
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat
    ) -> CGFloat {
        guard allowsReordering else {
            return 0
        }
        return handleLeadingInset(
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset
        ) + handleWidth
    }

    static func visualContentInset(
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat
    ) -> CGFloat {
        // The configured inset describes the visual glyph/chrome column, not the scroll-view frame edge.
        // Reordering centers its handle inside that gutter when possible, then grows only to the handle minimum.
        let configuredInset = max(editorHorizontalInset, textContainerContentLeading)
        guard allowsReordering else {
            return configuredInset
        }
        return max(configuredInset, horizontalChromeWidthWithHandle)
    }

    private static func markerAlignmentLeadingConstant(
        allowsReordering: Bool,
        editorHorizontalInset: CGFloat
    ) -> CGFloat {
        visualContentInset(allowsReordering: allowsReordering, editorHorizontalInset: editorHorizontalInset)
            - handleTrailingX(
                allowsReordering: allowsReordering,
                editorHorizontalInset: editorHorizontalInset
            )
    }
}

private extension BlockInputBlockKind {
    var needsMeasuredMarkerLane: Bool {
        switch self {
        case .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            return false
        }
    }
}
