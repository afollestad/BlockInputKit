import AppKit

extension BlockInputView {
    func configureInlineImageStoreCallback() {
        inlineImageStore.onImageStateChange = { [weak self] source in
            self?.handleInlineImageStateChange(for: source)
        }
    }

    /// Restyles mounted rows that reference the source and invalidates row heights.
    ///
    /// Natural image dimensions change the reserved advance and line height, so
    /// both mounted attributes and offscreen measurement must be refreshed;
    /// blocks that are scrolled out of view re-measure through the invalidated
    /// flow-layout metrics when they come back in.
    private func handleInlineImageStateChange(for source: String) {
        guard !source.isEmpty else {
            return
        }
        for item in collectionView.visibleItems() {
            guard let blockItem = item as? BlockInputBlockItem,
                  let block = blockItem.renderedBlock,
                  block.text.contains(source) else {
                continue
            }
            blockItem.applyTextAttributes(for: block)
        }
        invalidateLayoutForBlock(at: 0)
    }
}
