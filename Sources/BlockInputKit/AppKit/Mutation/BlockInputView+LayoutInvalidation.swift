import AppKit

/// Flow-layout invalidation and visible-row reflow for height-changing block mutations.
///
/// These share one problem: `NSCollectionViewFlowLayout` caches row geometry that a mutation has
/// already invalidated, and AppKit neither re-measures nor repositions mounted rows on its own
/// while the document is being edited. Every member here exists to close that gap in a specific
/// direction, so a change to one usually needs the others read alongside it.
extension BlockInputView {
    func invalidateLayoutForBlock(
        at index: Int,
        editedItem: BlockInputBlockItem? = nil,
        block: BlockInputBlock? = nil
    ) {
        if let flowLayout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
            let context = NSCollectionViewFlowLayoutInvalidationContext()
            context.invalidateFlowLayoutDelegateMetrics = true
            flowLayout.invalidateLayout(with: context)
        } else {
            collectionView.collectionViewLayout?.invalidateLayout()
        }
        collectionView.layoutSubtreeIfNeeded()
        if let editedItem, let block {
            resizeVisibleItem(editedItem, for: block)
        }
        reflowVisibleItemsAfterHeightChange(startingAt: index)
        if flowLayoutHeightShrank(for: block, at: index) {
            scheduleFlowLayoutShrinkSync()
        }
        invalidatePreferredHeight()
    }

    /// Re-invalidates the flow layout on the next turn after a row got shorter.
    ///
    /// AppKit swallows layout invalidation issued from inside the text-change notification: the
    /// cached attributes and `collectionViewContentSize` survive it verbatim, no runloop turn or
    /// layout pass revisits them, and the editor keeps a scroll range for lines that were just
    /// deleted. The same invalidation lands normally once the notification has unwound, so it is
    /// re-issued here and paired with the document-size sync that shrinks the frame, clamps the
    /// offset, and drops elasticity. Growth needs none of this: a too-short content size is
    /// corrected by the very next layout pass that measures the taller row.
    private func scheduleFlowLayoutShrinkSync() {
        // A full re-measure of a 10k+ row document is the cost the large-document paths exist to
        // avoid, and their content-size drift is imperceptible against that scroll range.
        guard !shouldDeferGranularCountLayout,
              !isFlowLayoutShrinkSyncScheduled else {
            return
        }
        isFlowLayoutShrinkSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            isFlowLayoutShrinkSyncScheduled = false
            collectionView.collectionViewLayout?.invalidateLayout()
            collectionView.layoutSubtreeIfNeeded()
            syncCollectionViewDocumentSizeForVisibleBounds()
        }
    }

    /// Whether this block now measures *shorter* than the flow layout's cached metric.
    ///
    /// A delegate-metrics invalidation only ever grows `collectionViewContentSize`: the cached
    /// attributes for a row that got shorter survive it verbatim, no matter how many layout passes
    /// or runloop turns follow, so the document keeps a scroll range for lines that no longer
    /// exist. Only a full invalidation drops them. Returns false without a block to measure, so a
    /// caller that cannot name the edited block only ever grows a row and needs no reconciliation.
    private func flowLayoutHeightShrank(for block: BlockInputBlock?, at index: Int) -> Bool {
        guard let block,
              let cachedHeight = collectionView.collectionViewLayout?
                  .layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.size.height else {
            return false
        }
        let measuredHeight = measuredBlockItemHeight(
            for: block,
            itemWidth: availableBlockItemWidth,
            isDocumentStartBlock: index == 0
        )
        return cachedHeight - measuredHeight > 0.5
    }

    /// Whether the flow layout's cached metric no longer matches the block's
    /// measured height. Height-changing replacements (a paragraph becoming a
    /// table, table rows added or removed) must refresh delegate metrics, or
    /// `collectionViewContentSize` keeps the old height and the scroll range
    /// clips the block; height-neutral replacements stay on the cheap path.
    func flowLayoutHeightIsStale(for block: BlockInputBlock, at index: Int) -> Bool {
        guard let cachedHeight = collectionView.collectionViewLayout?
            .layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.size.height else {
            return true
        }
        let measuredHeight = measuredBlockItemHeight(
            for: block,
            itemWidth: availableBlockItemWidth,
            isDocumentStartBlock: index == 0
        )
        return abs(cachedHeight - measuredHeight) > 0.5
    }

    func resizeVisibleItem(_ item: BlockInputBlockItem, for block: BlockInputBlock) {
        let itemWidth = item.view.bounds.width > 0 ? item.view.bounds.width : collectionView.bounds.width
        let height = measuredBlockItemHeight(
            for: block,
            itemWidth: itemWidth,
            isDocumentStartBlock: item.isDocumentStartBlock
        )
        guard abs(item.view.frame.height - height) > 0.5 else {
            return
        }
        item.view.frame.size.height = height
        item.view.needsLayout = true
        item.view.layoutSubtreeIfNeeded()
    }

    func reflowVisibleItemsAfterHeightChange(startingAt index: Int) {
        let indexedItems = collectionView.visibleItems().compactMap { item -> (index: Int, item: NSCollectionViewItem)? in
            guard let itemIndex = collectionView.indexPath(for: item)?.item,
                  itemIndex >= index else {
                return nil
            }
            return (itemIndex, item)
        }.sorted { $0.index < $1.index }
        guard let first = indexedItems.first, first.index == index else {
            return
        }

        // NSCollectionViewFlowLayout can leave stale origins for already-mounted
        // rows after a delegate-height change; fix only the visible run so the
        // edited block does not overlap the next mounted blocks while typing.
        var nextMinY = first.item.view.frame.minY
        for indexedItem in indexedItems {
            var frame = indexedItem.item.view.frame
            frame.origin.y = nextMinY
            indexedItem.item.view.frame = frame
            nextMinY = frame.maxY
        }
    }
}
