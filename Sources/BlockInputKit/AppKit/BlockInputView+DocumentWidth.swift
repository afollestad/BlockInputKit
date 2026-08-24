import AppKit

extension BlockInputView {
    /// Matches the document view to the viewport width and to the height its content needs.
    ///
    /// The height write used to be `max(frame.height, visibleHeight)` behind a width-only guard,
    /// so the document frame ratcheted upward: deleting a wrapped line left the taller frame in
    /// place and the editor kept a scroll range for content that no longer existed. The height is
    /// now recomputed from the layout's content size and may shrink, floored at the viewport so a
    /// scrolling document is never pulled out from under the user.
    ///
    /// This runs from the clip view's `boundsDidChange` observer, which fires on every scroll
    /// tick, so the no-op guard must be evaluated before any frame write — an unguarded write
    /// re-triggers layout and loops.
    func syncCollectionViewDocumentSizeForVisibleBounds() {
        let visibleWidth = max(scrollView.contentView.bounds.width, 0)
        guard visibleWidth > 0 else {
            return
        }
        let visibleHeight = max(scrollView.contentView.bounds.height, 0)
        let widthChanged = abs(collectionView.frame.width - visibleWidth) > 0.5
            || abs(collectionView.bounds.width - visibleWidth) > 0.5
        let targetHeight = targetDocumentHeight(forVisibleHeight: visibleHeight)
        let isShrinkingHeight = collectionView.frame.height - targetHeight > 0.5
        let heightChanged = isShrinkingHeight || targetHeight - collectionView.frame.height > 0.5
        updateDocumentScrollElasticity(contentHeight: targetHeight, visibleHeight: visibleHeight)
        guard widthChanged || heightChanged else {
            return
        }
        var frame = collectionView.frame
        frame.size.width = widthChanged ? visibleWidth : frame.width
        frame.size.height = targetHeight
        collectionView.frame = frame
        collectionView.needsLayout = true
        // Width changes rewrap every row; a height-only reconciliation must not invalidate the
        // preferred height, which is derived from the same content metrics every mutation path
        // already invalidates from — doing it here would feed a layout pass back into itself.
        if widthChanged {
            collectionView.collectionViewLayout?.invalidateLayout()
            updateVisibleItemWidthsForCurrentWidth()
            updatePlaceholderLayout()
            invalidatePreferredHeight()
        }
        if isShrinkingHeight {
            // Nothing else clamps on the scroll path, so a stale offset would otherwise stay
            // parked until the next layout pass.
            clampVerticalScrollOffsetToDocumentBounds()
        }
    }

    /// True when the document view's height no longer matches what its content needs, in either
    /// direction.
    ///
    /// Lets a layout pass that cannot safely write the frame — the document view's own
    /// `layout()` — defer the write to the scroll view instead.
    var hasStaleDocumentHeight: Bool {
        let visibleHeight = max(scrollView.contentView.bounds.height, 0)
        return abs(collectionView.frame.height - targetDocumentHeight(forVisibleHeight: visibleHeight)) > 0.5
    }

    func updateVisibleItemWidthsForCurrentWidth() {
        let itemWidth = currentCollectionItemWidth()
        guard itemWidth > 0 else {
            return
        }
        let indexedItems = collectionView.visibleItems().compactMap { item -> (index: Int, item: BlockInputBlockItem)? in
            guard let blockItem = item as? BlockInputBlockItem,
                  let index = collectionView.indexPath(for: blockItem)?.item,
                  block(at: index) != nil else {
                return nil
            }
            return (index, blockItem)
        }.sorted { $0.index < $1.index }
        let staleItems = indexedItems.filter {
            abs($0.item.view.frame.minX) > 0.5 ||
                abs($0.item.view.frame.width - itemWidth) > 0.5
        }
        guard let firstIndex = staleItems.first?.index else {
            return
        }
        for indexedItem in staleItems {
            guard let block = block(at: indexedItem.index) else {
                continue
            }
            var itemFrame = indexedItem.item.view.frame
            itemFrame.origin.x = 0
            itemFrame.size.width = itemWidth
            indexedItem.item.view.frame = itemFrame
            resizeVisibleItem(indexedItem.item, for: block)
            indexedItem.item.view.needsLayout = true
            indexedItem.item.view.layoutSubtreeIfNeeded()
        }
        reflowVisibleItemsAfterHeightChange(startingAt: firstIndex)
    }

    /// Height the document view needs, floored at the viewport.
    ///
    /// Deliberately not `currentDocumentContentHeight()`: that one maxes with the scroll view's
    /// content size, which is the very pin this reconciliation exists to remove.
    private func targetDocumentHeight(forVisibleHeight visibleHeight: CGFloat) -> CGFloat {
        let layoutHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
        return max(layoutHeight, visibleHeight)
    }

    /// Rubber-banding reads as "the editor scrolls" on a document that fits, and every nested
    /// scroll view already opts out, so elasticity follows whether the content overflows.
    private func updateDocumentScrollElasticity(contentHeight: CGFloat, visibleHeight: CGFloat) {
        let overflows = contentHeight - visibleHeight > 0.5
        let elasticity: NSScrollView.Elasticity = overflows ? .allowed : .none
        guard scrollView.verticalScrollElasticity != elasticity else {
            return
        }
        scrollView.verticalScrollElasticity = elasticity
    }

    private func currentCollectionItemWidth() -> CGFloat {
        let sectionInset = layout.sectionInset
        let scrollViewInsets = collectionView.enclosingScrollView?.contentInsets ?? NSEdgeInsetsZero
        let horizontalInsets = sectionInset.left + sectionInset.right + scrollViewInsets.left + scrollViewInsets.right
        return max(collectionView.bounds.width - horizontalInsets, 0)
    }
}
