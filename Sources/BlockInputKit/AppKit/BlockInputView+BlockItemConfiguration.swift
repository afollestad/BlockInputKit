extension BlockInputView {
    func configureBlockItem(_ item: BlockInputBlockItem, block: BlockInputBlock, blockIndex: Int? = nil) {
        let resolvedBlockIndex = blockIndex ?? index(of: block.id)
        item.configure(
            block: block,
            allowsReordering: allowsBlockReordering,
            allowsDrops: allowsDrops,
            editorHorizontalInset: editorHorizontalInset,
            accentColor: dropIndicatorColor,
            style: style,
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier,
            imageLoadingContext: imageLoadingContext,
            fileBaseURL: fileBaseURL,
            isEditable: isEditable,
            disabledCursor: disabledCursor,
            inlineHint: inlineHint(for: item, block: block, blockIndex: resolvedBlockIndex),
            rawSlashCommandChips: rawSlashCommandChips,
            rawFileMentionChips: rawFileMentionChips,
            selectAllBehavior: selectAllBehavior,
            slashCommandAvailability: slashCommandAvailability,
            isDocumentStartBlock: resolvedBlockIndex == 0,
            isSelected: isBlockSelected(block.id),
            delegate: self
        )
    }

    var imageLoadingContext: BlockInputImageBlockLoadingContext {
        BlockInputImageBlockLoadingContext(
            loader: imageLoader,
            diskCache: imageDiskCache,
            baseURL: imageBaseURL,
            allowsRemoteLoading: allowsRemoteImageLoading,
            maximumSourceBytes: maximumImageSourceBytes,
            maximumPixelDimension: maximumImagePixelDimension
        )
    }
}
