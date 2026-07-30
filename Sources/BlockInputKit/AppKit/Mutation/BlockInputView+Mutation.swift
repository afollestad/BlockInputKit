import AppKit

let largeDocumentCacheMutationLimit = 10_000

extension BlockInputView {
    enum StoreSyncAction {
        case replaceDocument
        case replaceBlock(BlockInputBlock)
        case insertBlocks([BlockInputBlock], insertionIndex: Int)
        case deleteBlocks([BlockInputBlockID])
        case moveBlock(BlockInputBlockID, targetIndex: Int)
        case moveBlockAndReplaceChangedBlocks(BlockInputBlockID, targetIndex: Int, changedBlocks: [BlockInputBlock])
        case numberedListMarkerTransaction(BlockInputNumberedListMarkerTransaction)
        case moveBlockAndApplyMarkerTransaction(BlockInputBlockID, targetIndex: Int, transaction: BlockInputNumberedListMarkerTransaction)
    }

    func publishDocumentChange() {
        updatePlaceholderVisibility()
        guard let onDocumentChange else {
            return
        }
        guard shouldDeferDocumentChangeSnapshot else {
            // A threshold-crossing edit can supersede an older deferred snapshot
            // while the duplicate cache is still stale.
            cancelPendingDocumentSnapshot()
            if !isDocumentCacheSynchronized {
                refreshDocumentFromStore()
            }
            onDocumentChange(document)
            return
        }
        scheduleDeferredDocumentSnapshot()
    }

    func refreshDocumentFromStore() {
        if let documentStore {
            document = BlockInputDocument(
                blocks: (0..<documentStore.loadedBlockCount).compactMap { documentStore.block(at: $0) }
            ).detachedStorage()
            isDocumentCacheSynchronized = true
        }
    }

    func canSynchronizeCacheForGranularInsertion(insertedBlockCount: Int) -> Bool {
        guard documentStore != nil else {
            return true
        }
        guard isDocumentCacheSynchronized else {
            return false
        }
        // Above this size, duplicating the store mutation with a local array
        // insert is visible in the 100k demo's repeated list-item Return path.
        return document.blocks.count + insertedBlockCount <= largeDocumentCacheMutationLimit
    }

    func canSynchronizeCacheForGranularDeletion(deletedBlockCount: Int) -> Bool {
        guard documentStore != nil else {
            return true
        }
        guard isDocumentCacheSynchronized else {
            return false
        }
        return document.blocks.count - deletedBlockCount <= largeDocumentCacheMutationLimit
    }

    func markDocumentCacheUnsynchronized() {
        isDocumentCacheSynchronized = false
    }

    @discardableResult
    func replaceCachedBlock(_ block: BlockInputBlock, at index: Int) -> Bool {
        if document.blocks.indices.contains(index),
           document.blocks[index].id == block.id {
            document.blocks[index] = block
            return true
        }

        guard isDocumentCacheSynchronized else {
            return false
        }
        refreshDocumentFromStore()
        guard document.blocks.indices.contains(index),
              document.blocks[index].id == block.id else {
            return false
        }
        document.blocks[index] = block
        return true
    }

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
        invalidatePreferredHeight()
    }

    func deleteVisibleBlock(at index: Int, deletedBlockIDs: [BlockInputBlockID] = []) {
        let indexPath = IndexPath(item: index, section: 0)
        if shouldDeferGranularCountLayout {
            reconfigureMountedBlocksAfterGranularCountChange(startingAt: index)
            return
        }
        collectionView.deleteItems(at: [indexPath])
        collectionView.layoutSubtreeIfNeeded()
        restoreMountedSelection()
        invalidatePreferredHeight()
    }

    var shouldDeferGranularCountLayout: Bool {
        blockCount > largeDocumentCacheMutationLimit
    }

    func reconfigureMountedBlocksAfterGranularCountChange(startingAt index: Int) {
        let intendedSelection = selection
        let indexedItems = collectionView.visibleItems().compactMap { item -> (index: Int, item: BlockInputBlockItem)? in
            guard let blockItem = item as? BlockInputBlockItem,
                  let itemIndex = collectionView.indexPath(for: item)?.item,
                  itemIndex >= index,
                  let block = block(at: itemIndex) else {
                return nil
            }
            configureBlockItem(blockItem, block: block, blockIndex: itemIndex)
            // The mounted item may now represent a different block kind; keep
            // its frame height in sync before manually reflowing visible rows.
            resizeVisibleItem(blockItem, for: block)
            return (itemIndex, blockItem)
        }.sorted { $0.index < $1.index }
        guard let first = indexedItems.first else {
            if selection != intendedSelection {
                applySelection(intendedSelection, notify: false)
            }
            restoreMountedSelection()
            return
        }
        reflowVisibleItemsAfterHeightChange(startingAt: first.index)
        if selection != intendedSelection {
            applySelection(intendedSelection, notify: false)
        }
        restoreMountedSelection()
        invalidatePreferredHeight()
    }

    @discardableResult
    func reconfigureVisibleReplacement(
        _ block: BlockInputBlock,
        at index: Int,
        requiresDeferredLayout: Bool = true,
        invalidatesLayoutMetrics: Bool = false
    ) -> Bool {
        let indexPath = IndexPath(item: index, section: 0)
        guard !requiresDeferredLayout || shouldDeferGranularCountLayout,
              let item = collectionView.item(at: indexPath) as? BlockInputBlockItem else {
            return false
        }
        configureBlockItem(item, block: block, blockIndex: index)
        // Metrics invalidation re-queries every row's size, so large documents stay on
        // the cheap frame-only path even when a replacement changes height; their minor
        // content-size drift is imperceptible against a 10k+ row scroll range.
        if invalidatesLayoutMetrics
            || (!shouldDeferGranularCountLayout && flowLayoutHeightIsStale(for: block, at: index)) {
            invalidateLayoutForBlock(at: index, editedItem: item, block: block)
        } else {
            resizeVisibleItem(item, for: block)
            reflowVisibleItemsAfterHeightChange(startingAt: index)
        }
        restoreMountedSelection()
        invalidatePreferredHeight()
        return true
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

    func hideReorderHandles(except hoveredItem: BlockInputBlockItem? = nil) {
        for item in collectionView.visibleItems() {
            guard let blockItem = item as? BlockInputBlockItem,
                  blockItem !== hoveredItem else {
                continue
            }
            blockItem.setReorderHandleVisible(false, animated: false)
        }
    }

    func performStructuralEdit(
        named actionName: String,
        selectionBeforeOverride: BlockInputSelection? = nil,
        storeSyncAction: (
            _ beforeDocument: BlockInputDocument,
            _ afterDocument: BlockInputDocument,
            _ afterSelection: BlockInputSelection
        ) -> StoreSyncAction = { _, _, _ in .replaceDocument },
        edit: (inout BlockInputDocument) -> BlockInputSelection?
    ) -> BlockInputSelection? {
        guard isEditable else { return nil }
        refreshDocumentFromStore()
        let beforeDocument = document
        let beforeSelection = selectionBeforeOverride ?? selection
        guard let afterSelection = edit(&document) else {
            return nil
        }
        guard beforeDocument != document else {
            applySelection(afterSelection, notify: beforeSelection != afterSelection)
            return nil
        }
        let action = storeSyncAction(beforeDocument, document, afterSelection)
        guard canSynchronizeDocumentStore(action) else {
            document = beforeDocument
            return nil
        }
        syncDocumentStore(action)
        applySelection(afterSelection, notify: true)
        undoController?.registerStructuralEdit(
            actionName: actionName,
            beforeDocument: beforeDocument,
            afterDocument: document,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        reloadDataKeepingFocus()
        publishDocumentChange()
        return afterSelection
    }

    func applyUndoResult(_ result: BlockInputUndoResult, storeSyncAction: StoreSyncAction? = nil) {
        guard isEditable else { return }
        syncDocumentStore(storeSyncAction ?? defaultStoreSyncAction(for: result))
        let restoredSelection = result.selection.flatMap { selection -> BlockInputSelection? in
            containsValidSelection(selection) ? selection : nil
        }
        applySelection(restoredSelection, notify: true)
        reloadDataKeepingFocus()
        publishDocumentChange()
    }

    @discardableResult
    func applyGranularUndoResult(_ result: BlockInputUndoResult) -> Bool {
        guard isEditable else { return false }
        if let movedBlockID = result.movedBlockID,
           let moveIndex = result.moveIndex {
            return applyGranularMoveUndo(
                blockID: movedBlockID,
                to: moveIndex,
                changedBlocks: result.replacedBlocks ?? [],
                markerTransaction: result.markerTransaction,
                selection: result.selection
            )
        }

        if let replacedBlock = result.replacedBlock,
           let replacementIndex = index(of: replacedBlock.id) {
            return applyGranularReplacementUndoResult(result, replacement: replacedBlock, replacementIndex: replacementIndex)
        }

        if let replacedBlocks = result.replacedBlocks,
           !replacedBlocks.isEmpty,
           result.insertedBlocks == nil,
           result.deletedBlockIDs == nil,
           result.markerTransaction == nil {
            return applyGranularBlockReplacements(replacedBlocks, selection: result.selection)
        }

        if let insertedBlocks = result.insertedBlocks,
           let insertionIndex = result.insertionIndex {
            return applyGranularInsertionUndo(
                insertedBlocks,
                at: insertionIndex,
                changedBlocks: result.replacedBlocks ?? [],
                markerTransaction: result.markerTransaction,
                selection: result.selection
            )
        }

        if let deletedBlockIDs = result.deletedBlockIDs,
           let firstDeletedBlockID = deletedBlockIDs.first,
           let deletionIndex = index(of: firstDeletedBlockID) {
            return applyGranularDeletionUndo(
                deletedBlockIDs,
                at: deletionIndex,
                changedBlocks: result.replacedBlocks ?? [],
                markerTransaction: result.markerTransaction,
                selection: result.selection
            )
        }

        if let markerTransaction = result.markerTransaction,
           documentStore is BlockInputMarkerAdjustingStore {
            return applyGranularMarkerTransactionUndo(markerTransaction, selection: result.selection)
        }

        return false
    }

    private func applyGranularMarkerTransactionUndo(
        _ markerTransaction: BlockInputNumberedListMarkerTransaction,
        selection: BlockInputSelection?
    ) -> Bool {
        syncDocumentStore(.numberedListMarkerTransaction(markerTransaction))
        applySelection(validUndoSelection(selection), notify: true)
        reloadDataKeepingFocus()
        publishDocumentChange()
        return true
    }

    private func applyGranularReplacementUndoResult(
        _ result: BlockInputUndoResult,
        replacement: BlockInputBlock,
        replacementIndex: Int
    ) -> Bool {
        if let insertedBlocks = result.insertedBlocks,
           let insertionIndex = result.insertionIndex {
            return applyGranularReplacementInsertionUndo(
                ReplacementInsertionUndoContext(
                    replacement: replacement,
                    replacementIndex: replacementIndex,
                    insertedBlocks: insertedBlocks,
                    insertionIndex: insertionIndex,
                    changedBlocks: result.replacedBlocks ?? [],
                    markerTransaction: result.markerTransaction
                ),
                selection: result.selection
            )
        }
        if let deletedBlockIDs = result.deletedBlockIDs,
           let firstDeletedBlockID = deletedBlockIDs.first,
           let deletionIndex = index(of: firstDeletedBlockID) {
            return applyGranularReplacementDeletionUndo(
                ReplacementDeletionUndoContext(
                    replacement: replacement,
                    replacementIndex: replacementIndex,
                    deletedBlockIDs: deletedBlockIDs,
                    deletionIndex: deletionIndex,
                    changedBlocks: result.replacedBlocks ?? [],
                    markerTransaction: result.markerTransaction
                ),
                selection: result.selection
            )
        }
        return applyGranularReplacementUndo(replacement, at: replacementIndex, selection: result.selection)
    }

    func applyGranularBlockReplacement(
        _ block: BlockInputBlock,
        at index: Int,
        selection: BlockInputSelection?,
        authorizedProvisionalSession: BlockInputProvisionalTextSession? = nil
    ) -> Bool {
        guard isEditable || isActiveProvisionalTextSession(authorizedProvisionalSession) else { return false }
        syncDocumentStore(.replaceBlock(block))
        guard canContinueAuthorizedProvisionalReplacement(
            authorizedProvisionalSession,
            expectedBlock: block
        ) else {
            return false
        }
        guard let resolvedIndex = authorizedProvisionalSession == nil ? index : self.index(of: block.id) else { return false }
        _ = replaceCachedBlock(block, at: resolvedIndex)
        applySelection(validUndoSelection(selection), notify: true)
        guard canContinueAuthorizedProvisionalReplacement(
            authorizedProvisionalSession,
            expectedBlock: block
        ) else {
            return false
        }
        return presentGranularBlockReplacement(
            block,
            at: resolvedIndex,
            authorizedProvisionalSession: authorizedProvisionalSession
        )
    }

    func applyGranularBlockReplacements(
        _ blocks: [BlockInputBlock],
        selection: BlockInputSelection?
    ) -> Bool {
        guard isEditable else { return false }
        guard !blocks.isEmpty else {
            applySelection(validUndoSelection(selection), notify: true)
            return true
        }
        for block in blocks {
            guard let index = index(of: block.id) else {
                return false
            }
            syncDocumentStore(.replaceBlock(block))
            _ = replaceCachedBlock(block, at: index)
        }
        applySelection(validUndoSelection(selection), notify: true)
        reloadDataKeepingFocus()
        publishDocumentChange()
        invalidatePreferredHeight()
        return true
    }

    func applyGranularReplacementUndo(
        _ block: BlockInputBlock,
        at index: Int,
        selection: BlockInputSelection?
    ) -> Bool {
        applyGranularBlockReplacement(block, at: index, selection: selection)
    }

    func validUndoSelection(_ selection: BlockInputSelection?) -> BlockInputSelection? {
        selection.flatMap { containsValidSelection($0) ? $0 : nil }
    }

    /// Resolves granular insertion indexes before document/store mutations so frontmatter stays pinned.
    func frontMatterPreservingInsertionIndex(
        _ index: Int,
        afterReplacing replacement: BlockInputBlock? = nil,
        at replacementIndex: Int? = nil
    ) -> Int {
        let clampedIndex = min(max(index, 0), document.blocks.count)
        guard clampedIndex == 0 else {
            return clampedIndex
        }
        if let replacement,
           let replacementIndex,
           replacementIndex == document.blocks.startIndex,
           document.blocks.indices.contains(replacementIndex) {
            return replacement.kind == .frontMatter ? 1 : 0
        }
        return document.blocks.first?.kind == .frontMatter ? 1 : 0
    }
}
