import AppKit

extension BlockInputView {
    func measuredBlockItemHeight(
        for block: BlockInputBlock,
        itemWidth: CGFloat,
        isDocumentStartBlock: Bool
    ) -> CGFloat {
        let textWidth = BlockInputBlockItem.measuredTextWidth(
            for: itemWidth,
            block: block,
            allowsReordering: allowsBlockReordering,
            editorHorizontalInset: editorHorizontalInset,
            style: style
        )
        return BlockInputBlockItem.height(
            for: block,
            textWidth: textWidth,
            style: style,
            fileBaseURL: fileBaseURL,
            rawSlashCommandChips: rawSlashCommandChips,
            rawFileMentionChips: rawFileMentionChips,
            slashCommandAvailability: slashCommandAvailability,
            isDocumentStartBlock: isDocumentStartBlock,
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier,
            inlineImageSizes: inlineImageStore.sizesSnapshot()
        )
    }
}
