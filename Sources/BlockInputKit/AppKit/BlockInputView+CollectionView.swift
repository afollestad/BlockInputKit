import AppKit

extension BlockInputView: NSCollectionViewDataSource {
    /// Returns the editor's single collection-view section.
    public func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    /// Returns the number of loaded block rows plus the progressive loading row when visible.
    public func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        blockCount + (showsProgressiveLoadingRow ? 1 : 0)
    }

    /// Creates or reuses the collection item for a block row or the progressive loading row.
    public func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        if isProgressiveLoadingIndex(indexPath.item) {
            let item = collectionView.makeItem(
                withIdentifier: BlockInputLoadingItem.reuseIdentifier,
                for: indexPath
            )
            (item as? BlockInputLoadingItem)?.configure(error: progressiveStoreError, surfaceStyle: style.editorSurface)
            scheduleProgressivePreloadCheck(requiresMountedPreloadWindow: false)
            return item
        }
        let item = collectionView.makeItem(
            withIdentifier: BlockInputBlockItem.reuseIdentifier,
            for: indexPath
        )
        guard let blockItem = item as? BlockInputBlockItem else {
            return item
        }
        guard let block = block(at: indexPath.item) else {
            blockItem.clearConfiguration()
            return blockItem
        }
        configureBlockItem(blockItem, block: block, blockIndex: indexPath.item)
        restoreCursorSelectionIfNeeded(on: blockItem, block: block)
        return blockItem
    }
}

extension BlockInputView: NSCollectionViewDelegateFlowLayout {
    /// Returns the measured size for a block row or the progressive loading row.
    public func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        let sectionInset = (collectionViewLayout as? NSCollectionViewFlowLayout)?.sectionInset
            ?? NSEdgeInsetsZero
        let scrollViewInsets = collectionView.enclosingScrollView?.contentInsets ?? NSEdgeInsetsZero
        let horizontalInsets = sectionInset.left + sectionInset.right + scrollViewInsets.left + scrollViewInsets.right
        let availableWidth = max(collectionView.bounds.width - horizontalInsets, 0)
        if isProgressiveLoadingIndex(indexPath.item) {
            return NSSize(width: availableWidth, height: progressiveLoadingRowHeight)
        }
        guard let block = block(at: indexPath.item) else {
            return NSSize(width: availableWidth, height: 32)
        }
        return NSSize(width: availableWidth, height: measuredBlockItemHeight(for: block, itemWidth: availableWidth))
    }
}

extension BlockInputView {
    var showsProgressiveLoadingRow: Bool {
        guard let documentStore else {
            return false
        }
        return !documentStore.isComplete || progressiveStoreError != nil
    }

    func isProgressiveLoadingIndex(_ index: Int) -> Bool {
        showsProgressiveLoadingRow && index == blockCount
    }

    func requestNextProgressiveBatchIfNeeded() {
        guard let documentStore = documentStoreForNextProgressiveBatchRequest() else {
            return
        }
        let batchLimit = progressiveLoadBatchLimit
        let loadedCountBeforeRequest = documentStore.loadedBlockCount
        progressiveLoadTask = Task { @MainActor [weak self, documentStore] in
            do {
                try await documentStore.loadNextBlockBatch(limit: batchLimit)
            } catch is CancellationError {
            } catch {
                guard let self,
                      self.isCurrentDocumentStore(documentStore as AnyObject) else {
                    return
                }
                self.progressiveStoreError = error.localizedDescription
                self.collectionView.reloadData()
            }
            guard let self,
                  self.isCurrentDocumentStore(documentStore as AnyObject) else {
                return
            }
            self.progressiveLoadTask = nil
            if documentStore.loadedBlockCount > loadedCountBeforeRequest,
               self.isProgressiveLoadingRowVisibleOrWithinPreloadWindow() {
                self.scheduleProgressivePreloadCheck()
                self.invalidatePreferredHeight()
            }
        }
    }

    func documentStoreForNextProgressiveBatchRequest() -> (any BlockInputDocumentStore)? {
        // Scroll and layout events can fire repeatedly near the bottom of large documents.
        // Keep this guard cheap so those events avoid collection geometry work while a load is blocked.
        guard progressiveLoadTask == nil,
              progressiveStoreError == nil,
              let documentStore,
              !documentStore.isComplete,
              !documentStore.isLoading else {
            return nil
        }
        return documentStore
    }

    func isCurrentDocumentStore(_ store: AnyObject) -> Bool {
        guard let documentStore else {
            return false
        }
        return (documentStore as AnyObject) === store
    }

    func handleDocumentStoreChange(_ change: BlockInputDocumentStoreChange) {
        reconcileProvisionalTextReplacementAfterStoreChange(change)
        switch change {
        case .loadingStateChanged:
            updatePlaceholderVisibility()
        case .appendedBlocks(let batch):
            progressiveStoreError = nil
            updateDocumentCacheAfterProgressiveBatch(batch)
            appendProgressiveBatch(batch)
            updatePlaceholderVisibility()
            if batch.isComplete,
               pendingDocumentSnapshotWorkItem != nil {
                scheduleDeferredDocumentSnapshot()
            }
        case .replacedDocument:
            progressiveStoreError = nil
            refreshDocumentFromStore()
            reloadDataKeepingFocus()
            if documentStore?.isComplete == true,
               pendingDocumentSnapshotWorkItem != nil {
                scheduleDeferredDocumentSnapshot()
            }
        case .failed(let error):
            progressiveStoreError = error
            collectionView.reloadData()
            updatePlaceholderVisibility()
        }
    }

    func updateDocumentCacheAfterProgressiveBatch(_ batch: BlockInputDocumentStoreBatch) {
        guard isDocumentCacheSynchronized else {
            return
        }
        let updatedCount = document.blocks.count + batch.blocks.count
        guard document.blocks.count == batch.startIndex,
              updatedCount <= largeDocumentCacheMutationLimit else {
            markDocumentCacheUnsynchronized()
            return
        }
        document.blocks.append(contentsOf: batch.blocks)
    }

    func appendProgressiveBatch(_ batch: BlockInputDocumentStoreBatch) {
        let previousLoadingIndex = batch.startIndex
        let insertedCount = batch.blocks.count
        guard insertedCount > 0 else {
            collectionView.reloadData()
            invalidatePreferredHeight()
            return
        }
        collectionView.performBatchUpdates {
            if previousLoadingIndex < collectionView.numberOfItems(inSection: 0) {
                collectionView.deleteItems(at: [IndexPath(item: previousLoadingIndex, section: 0)])
            }
            let inserted = (0..<insertedCount).map { IndexPath(item: batch.startIndex + $0, section: 0) }
            collectionView.insertItems(at: Set(inserted))
            if !batch.isComplete {
                collectionView.insertItems(at: [IndexPath(item: batch.startIndex + insertedCount, section: 0)])
            }
        } completionHandler: { [weak self] _ in
            guard let self else {
                return
            }
            self.restoreMountedSelection()
            self.updatePlaceholderVisibility()
            self.invalidatePreferredHeight()
        }
    }
}

extension BlockInputView: NSCollectionViewDelegate {
    /// Provides a block pasteboard item when drag reordering can begin from the requested row.
    public func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard isEditable, allowsDrops, allowsBlockReordering else { return nil }
        guard let block = block(at: indexPath.item),
              block.kind != .frontMatter else {
            return nil
        }
        _ = cancelMultiBlockSelectionForReorderStart()
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(block.id.rawValue, forType: .blockInputBlockID)
        return pasteboardItem
    }

    /// Configures the drag session used for block reordering.
    public func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forItemsAt indexPaths: Set<IndexPath>
    ) {
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }

    /// Validates block-reorder and file-drop targets and updates the drop indicator.
    public func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        guard isEditable, allowsDrops else { hideDropIndicator(); return [] }
        if canAcceptBlockReorderDrop(draggingInfo) {
            let insertionIndex = resolvedDropInsertionIndex(
                from: draggingInfo,
                proposedItemIndex: proposedDropIndexPath.pointee.item
            )
            let blockID = draggingInfo.draggingPasteboard.string(forType: .blockInputBlockID)
                .map(BlockInputBlockID.init(rawValue:))
            let location = collectionView.convert(draggingInfo.draggingLocation, from: nil)
            let targetIndex = blockID.flatMap {
                collectionDropTargetIndex(
                    forBlockID: $0,
                    proposedItemIndex: insertionIndex,
                    location: location
                )
            }
            guard let blockID,
                  let targetIndex,
                  index(of: blockID) != targetIndex,
                  canMoveBlockWithoutDisplacingFrontMatter(blockID: blockID, targetIndex: targetIndex) else {
                hideDropIndicator()
                return []
            }
            let indicatorIndex = dropIndicatorInsertionIndex(forBlockID: blockID, targetIndex: targetIndex)
            proposedDropIndexPath.pointee = NSIndexPath(forItem: indicatorIndex, inSection: 0)
            proposedDropOperation.pointee = .before
            showDropIndicator(atInsertionIndex: indicatorIndex)
            return .move
        }
        if let target = collectionFileDropTarget(for: draggingInfo) {
            proposedDropIndexPath.pointee = NSIndexPath(forItem: target.insertionIndex, inSection: 0)
            proposedDropOperation.pointee = .before
            showDropIndicator(atInsertionIndex: target.insertionIndex)
            return .copy
        }
        hideDropIndicator()
        return []
    }

    /// Applies an accepted block reorder or collection-view file drop.
    public func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        hideDropIndicator()
        guard isEditable, allowsDrops else { return false }
        let resolvedInsertionIndex = resolvedDropInsertionIndex(
            from: draggingInfo,
            proposedItemIndex: indexPath.item
        )
        if canAcceptBlockReorderDrop(draggingInfo) {
            guard let rawID = draggingInfo.draggingPasteboard.string(forType: .blockInputBlockID) else {
                return false
            }
            let blockID = BlockInputBlockID(rawValue: rawID)
            guard let sourceIndex = index(of: blockID),
                  let targetIndex = collectionDropTargetIndex(
                      forBlockID: blockID,
                      proposedItemIndex: resolvedInsertionIndex,
                      location: collectionView.convert(draggingInfo.draggingLocation, from: nil)
                  ),
                  targetIndex != sourceIndex,
                  canMoveBlockWithoutDisplacingFrontMatter(blockID: blockID, targetIndex: targetIndex) else {
                return false
            }
            return moveBlock(blockID: blockID, to: targetIndex) != nil
        }
        if let target = collectionFileDropTarget(for: draggingInfo) {
            if fileDropHandler != nil {
                return handleDroppedFileURLs(target.fileURLs, placement: .documentEnd)
            }
            return insertDroppedFileURLs(target.fileURLs, at: target.insertionIndex) != nil
        }
        return false
    }

    private func canMoveBlockWithoutDisplacingFrontMatter(blockID: BlockInputBlockID, targetIndex: Int) -> Bool {
        guard let sourceIndex = index(of: blockID) else {
            return false
        }
        if block(at: sourceIndex)?.kind == .frontMatter {
            return false
        }
        return !(block(at: 0)?.kind == .frontMatter && targetIndex == 0)
    }

    func collectionDropTargetIndex(
        forBlockID blockID: BlockInputBlockID,
        proposedItemIndex: Int,
        location: NSPoint? = nil
    ) -> Int? {
        guard let sourceIndex = index(of: blockID) else {
            return nil
        }
        if sourceIndex < proposedItemIndex {
            if proposedItemIndex == sourceIndex + 1 {
                guard location == nil else {
                    return sourceIndex
                }
            }
            let adjustedIndex = max(0, proposedItemIndex - 1)
            if adjustedIndex == sourceIndex, proposedItemIndex < blockCount {
                return proposedItemIndex
            }
            return adjustedIndex
        }
        return proposedItemIndex
    }

    func dropIndicatorInsertionIndex(
        forBlockID blockID: BlockInputBlockID,
        targetIndex: Int
    ) -> Int {
        guard let sourceIndex = index(of: blockID),
              sourceIndex < targetIndex else {
            return clampedInsertionIndex(targetIndex)
        }
        return clampedInsertionIndex(targetIndex + 1)
    }

    func canAcceptBlockReorderDrop(_ draggingInfo: NSDraggingInfo) -> Bool {
        guard isEditable, allowsDrops, allowsBlockReordering,
              let rawID = draggingInfo.draggingPasteboard.string(forType: .blockInputBlockID),
              let index = index(of: BlockInputBlockID(rawValue: rawID)),
              block(at: index)?.kind != .frontMatter else {
            return false
        }
        return true
    }

    func collectionFileDropTarget(for draggingInfo: NSDraggingInfo) -> BlockInputCollectionFileDropTarget? {
        guard isEditable, allowsDrops, draggingInfo.draggingPasteboard.string(forType: .blockInputBlockID) == nil,
              !showsProgressiveLoadingRow else {
            return nil
        }
        let fileURLs = Self.fileURLs(from: draggingInfo.draggingPasteboard)
        guard !fileURLs.isEmpty,
              fileURLs.contains(where: { Self.imageBlock(for: $0) != nil || Self.fileLinkBlock(for: $0) != nil }) else {
            return nil
        }
        let location = collectionView.convert(draggingInfo.draggingLocation, from: nil)
        guard collectionView.visibleRect.contains(location),
              collectionLocationIsInBottomBlankSpace(location) else {
            return nil
        }
        return BlockInputCollectionFileDropTarget(fileURLs: fileURLs, insertionIndex: blockCount)
    }

    func resolvedDropInsertionIndex(
        from draggingInfo: NSDraggingInfo,
        proposedItemIndex: Int
    ) -> Int {
        let location = collectionView.convert(draggingInfo.draggingLocation, from: nil)
        return dropInsertionIndex(forLocation: location, fallbackIndex: proposedItemIndex)
    }

    func dropInsertionIndex(forLocation location: NSPoint, fallbackIndex: Int) -> Int {
        let fallbackIndex = clampedInsertionIndex(fallbackIndex)
        guard blockCount > 0 else {
            return 0
        }

        // Resolve against visible layout attributes only so drag validation stays cheap for large documents.
        let searchRect = collectionView.visibleRect.insetBy(dx: 0, dy: -80)
        let attributes = collectionView.collectionViewLayout?
            .layoutAttributesForElements(in: searchRect)
            .filter { $0.representedElementCategory == .item }
            .compactMap { attribute -> (indexPath: IndexPath, frame: NSRect)? in
                guard let indexPath = attribute.indexPath else {
                    return nil
                }
                return (indexPath, attribute.frame)
            }
            .sorted { $0.frame.minY < $1.frame.minY } ?? []
        guard !attributes.isEmpty else {
            return fallbackIndex
        }

        for attribute in attributes where location.y < attribute.frame.midY {
            return clampedInsertionIndex(attribute.indexPath.item)
        }
        guard let lastItem = attributes.last?.indexPath.item else {
            return fallbackIndex
        }
        return clampedInsertionIndex(lastItem + 1)
    }

    func showDropIndicator(atInsertionIndex insertionIndex: Int) {
        guard let frame = dropIndicatorFrame(forInsertionIndex: insertionIndex) else {
            hideDropIndicator()
            return
        }
        dropIndicatorView.frame = frame
        dropIndicatorView.isHidden = false
        if dropIndicatorView.superview == nil {
            collectionView.addSubview(dropIndicatorView, positioned: .above, relativeTo: nil)
        }
    }

    func hideDropIndicator() {
        dropIndicatorView.isHidden = true
    }

    func updateDropIndicatorColor() {
        dropIndicatorView.layer?.backgroundColor = dropIndicatorColor.cgColor
    }

    func dropIndicatorFrame(forInsertionIndex insertionIndex: Int) -> NSRect? {
        guard blockCount > 0 else {
            return NSRect(x: 12, y: 8, width: max(collectionView.bounds.width - 24, 1), height: 2)
        }

        let yPosition: CGFloat
        if insertionIndex < blockCount,
           let attributes = collectionView.layoutAttributesForItem(
            at: IndexPath(item: clampedInsertionIndex(insertionIndex), section: 0)
           ) {
            yPosition = attributes.frame.minY
        } else if let attributes = collectionView.layoutAttributesForItem(
            at: IndexPath(item: blockCount - 1, section: 0)
        ) {
            yPosition = attributes.frame.maxY
        } else {
            return nil
        }

        return NSRect(
            x: 12,
            y: yPosition - 1,
            width: max(collectionView.bounds.width - 24, 1),
            height: 2
        )
    }

    private func clampedInsertionIndex(_ index: Int) -> Int {
        min(max(index, 0), blockCount)
    }

    private func collectionLocationIsInBottomBlankSpace(_ location: NSPoint) -> Bool {
        guard blockCount > 0 else {
            return true
        }
        guard let attributes = collectionView.layoutAttributesForItem(
            at: IndexPath(item: blockCount - 1, section: 0)
        ) else {
            return false
        }
        return location.y >= attributes.frame.maxY
    }
}

struct BlockInputCollectionFileDropTarget {
    var fileURLs: [URL]
    var insertionIndex: Int
}
