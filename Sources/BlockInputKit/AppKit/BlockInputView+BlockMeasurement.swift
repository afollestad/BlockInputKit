import AppKit

extension BlockInputView {
    /// The item width the flow-layout delegate reports; height comparisons
    /// against the layout's cached metrics must measure with this exact width.
    var availableBlockItemWidth: CGFloat {
        availableBlockItemWidth(for: collectionView.collectionViewLayout)
    }

    func availableBlockItemWidth(for collectionViewLayout: NSCollectionViewLayout?) -> CGFloat {
        let sectionInset = (collectionViewLayout as? NSCollectionViewFlowLayout)?.sectionInset
            ?? NSEdgeInsetsZero
        let scrollViewInsets = collectionView.enclosingScrollView?.contentInsets ?? NSEdgeInsetsZero
        let horizontalInsets = sectionInset.left + sectionInset.right + scrollViewInsets.left + scrollViewInsets.right
        return max(collectionView.bounds.width - horizontalInsets, 0)
    }

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
