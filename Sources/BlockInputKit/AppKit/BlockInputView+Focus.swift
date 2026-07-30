import AppKit

extension BlockInputView {
    /// Focuses the editor like a single text field, preserving valid current selections.
    public func focusEditor() {
        // Without a window the selection bookkeeping below still applies, but
        // makeFirstResponder is a silent no-op (a freshly mounted SwiftUI editor
        // updates before attachment) — re-claim on viewDidMoveToWindow.
        wantsFocusOnWindowAttach = window == nil
        refreshDocumentFromStore()
        if tableKeyboardRowSelection != nil {
            if !isBecomingFirstResponder, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            publishFocusChange(true)
            return
        }
        if let selection, containsValidSelection(selection) {
            restoreVisibleSelection()
            if isEditorFirstResponder {
                publishFocusChange(true)
            }
            return
        }
        let cursor = pendingFocus ?? cursorForRestoredFocus()
        focus(blockID: cursor.blockID, utf16Offset: cursor.utf16Offset)
    }

    var isEditorFirstResponder: Bool {
        guard let firstResponder = window?.firstResponder else {
            return false
        }
        if firstResponder === self {
            return true
        }
        var candidateView = firstResponder as? NSView
        while let view = candidateView {
            if view === self {
                return true
            }
            candidateView = view.superview
        }
        return false
    }

    var activeBlockID: BlockInputBlockID? {
        let candidateID: BlockInputBlockID?
        switch selection {
        case let .cursor(cursor):
            candidateID = cursor.blockID
        case let .text(range):
            candidateID = range.blockID
        case let .blocks(ids):
            // Store-backed documents can change under an existing multi-block selection.
            // Keep commands anchored to the last interaction point when possible.
            if let lastFocusedBlockID,
               ids.contains(lastFocusedBlockID),
               index(of: lastFocusedBlockID) != nil {
                return lastFocusedBlockID
            }
            if let validBlockID = ids.first(where: { index(of: $0) != nil }) {
                return validBlockID
            }
            candidateID = nil
        case let .mixed(selection):
            candidateID = selection.leadingTextRange?.blockID
                ?? selection.trailingTextRange?.blockID
                ?? selection.blockIDs.first
        case nil:
            candidateID = lastFocusedBlockID
        }
        if let candidateID, index(of: candidateID) != nil {
            return candidateID
        }
        return block(at: 0)?.id
    }

    func cursorForRestoredFocus() -> BlockInputCursor {
        if let cursor = pendingFocus, index(of: cursor.blockID) != nil {
            return cursor
        }
        if selection != nil,
           let blockID = activeBlockID,
           let block = block(withID: blockID) {
            return BlockInputCursor(blockID: blockID, utf16Offset: block.cursorUTF16Length)
        }
        if let lastFocusedBlockID, let block = block(withID: lastFocusedBlockID) {
            return BlockInputCursor(blockID: lastFocusedBlockID, utf16Offset: block.cursorUTF16Length)
        }
        let firstBlock = block(at: 0) ?? document.blocks[0]
        return BlockInputCursor(blockID: firstBlock.id, utf16Offset: 0)
    }

    @discardableResult
    func resignEditorFocus() -> Bool {
        wantsFocusOnWindowAttach = false
        guard isEditorFirstResponder else {
            return true
        }
        window?.endEditing(for: nil)
        let didResign = window?.makeFirstResponder(nil) ?? false
        let isResigned = !isEditorFirstResponder
        if didResign || isResigned {
            publishFocusLossIfNeeded()
        }
        return didResign || isResigned
    }

    func publishFocusChange(_ isFocused: Bool) {
        guard publishedFocusState != isFocused else {
            return
        }
        publishedFocusState = isFocused
        onFocusChange?(isFocused)
    }

    func publishFocusLossIfNeeded() {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !isEditorFirstResponder else {
                return
            }
            publishFocusChange(false)
        }
    }

    func visibleItem(
        for blockID: BlockInputBlockID,
        refreshConfiguration: Bool = true
    ) -> BlockInputBlockItem? {
        guard let index = index(of: blockID),
              let block = block(at: index) else {
            return nil
        }
        let indexPath = IndexPath(item: index, section: 0)
        if indexPath.item >= collectionView.numberOfItems(inSection: indexPath.section) {
            collectionView.reloadData()
            collectionView.layoutSubtreeIfNeeded()
        }
        guard indexPath.item < collectionView.numberOfItems(inSection: indexPath.section) else {
            return nil
        }
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
        collectionView.layoutSubtreeIfNeeded()
        guard let item = collectionView.item(at: indexPath) as? BlockInputBlockItem else {
            return nil
        }
        if refreshConfiguration {
            configureBlockItem(item, block: block, blockIndex: index)
        }
        return item
    }

    func focusVisibleItem(for cursor: BlockInputCursor) {
        let isImageCursor = block(withID: cursor.blockID)?.kind.isImage == true
        guard let item = isImageCursor
            ? visibleImageItem(for: cursor.blockID)
            : visibleItem(for: cursor.blockID) else {
            pendingFocus = cursor
            return
        }
        if isImageCursor {
            item.setImageCaretOffset(cursor.utf16Offset)
            if !isBecomingFirstResponder, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            pendingFocus = nil
            return
        }
        item.focusText(atUTF16Offset: cursor.utf16Offset)
        pendingFocus = nil
    }

    private func visibleImageItem(for blockID: BlockInputBlockID) -> BlockInputBlockItem? {
        guard let index = activeStandaloneBlockIndex(for: blockID),
              block(at: index)?.kind.isImage == true else {
            return nil
        }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
        collectionView.layoutSubtreeIfNeeded()
        return collectionView.item(at: indexPath) as? BlockInputBlockItem
    }

    func restoreVisibleTextSelection(_ textRange: BlockInputTextRange) {
        guard let item = visibleItem(for: textRange.blockID) else {
            return
        }
        item.focusText(inUTF16Range: textRange.range)
    }

    func restoreVisibleBlockSelection(_ blockIDs: [BlockInputBlockID]) {
        if let firstBlockID = blockIDs.first {
            _ = visibleItem(for: firstBlockID, refreshConfiguration: false)
        }
        if !isBecomingFirstResponder, window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        updateVisibleBlockSelectionHighlights()
    }

    func restoreVisibleSelection() {
        switch selection {
        case let .cursor(cursor):
            focusVisibleItem(for: cursor)
        case let .text(textRange):
            restoreVisibleTextSelection(textRange)
        case let .blocks(blockIDs):
            restoreVisibleBlockSelection(blockIDs)
        case let .mixed(selection):
            restoreVisibleBlockSelection(selectedBlockIDs(in: selection))
        case nil:
            break
        }
    }

    func moveCaretToDocumentBoundary(_ direction: BlockInputVerticalMovementDirection) -> Bool {
        refreshDocumentFromStore()
        let targetIndex = direction == .upward ? 0 : blockCount - 1
        guard let block = block(at: targetIndex) else {
            return false
        }
        if block.kind == .horizontalRule {
            applySelection(.blocks([block.id]), notify: true)
            scrollBlockToVisible(at: targetIndex, direction: direction)
            window?.makeFirstResponder(self)
            publishFocusChange(true)
            return true
        }
        focus(blockID: block.id, utf16Offset: direction == .upward ? 0 : block.cursorUTF16Length)
        return true
    }

    private func scrollBlockToVisible(at index: Int, direction: BlockInputVerticalMovementDirection) {
        let scrollPosition: NSCollectionView.ScrollPosition = direction == .upward ? .top : .bottom
        collectionView.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: scrollPosition)
        collectionView.layoutSubtreeIfNeeded()
    }

    func restoreMountedSelection() {
        switch selection {
        case let .cursor(cursor):
            restoreMountedCursorSelection(cursor)
        case let .text(textRange):
            guard let item = mountedBlockItem(for: textRange.blockID) else {
                return
            }
            item.focusText(inUTF16Range: textRange.range)
        case let .blocks(blockIDs):
            if !blockIDs.isEmpty, !isBecomingFirstResponder, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
        case let .mixed(selection):
            if !selectedBlockIDs(in: selection).isEmpty, !isBecomingFirstResponder, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            updateVisibleBlockSelectionHighlights()
        case nil:
            break
        }
    }

    private func restoreMountedCursorSelection(_ cursor: BlockInputCursor) {
        let item = block(withID: cursor.blockID)?.kind.isImage == true
            ? mountedImageItem(for: cursor.blockID)
            : mountedBlockItem(for: cursor.blockID)
        guard let item else {
            pendingFocus = cursor
            return
        }
        if block(withID: cursor.blockID)?.kind.isImage == true {
            item.setImageCaretOffset(cursor.utf16Offset)
            if !isBecomingFirstResponder, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            pendingFocus = nil
            return
        }
        item.focusText(atUTF16Offset: cursor.utf16Offset)
        pendingFocus = nil
    }

    func restoreCursorSelectionIfNeeded(on item: BlockInputBlockItem, block: BlockInputBlock) {
        let cursor: BlockInputCursor?
        if pendingFocus?.blockID == block.id {
            cursor = pendingFocus
        } else if case let .cursor(selectionCursor) = selection,
                  selectionCursor.blockID == block.id {
            cursor = selectionCursor
        } else {
            cursor = nil
        }
        guard let cursor else {
            return
        }
        if block.kind.isImage {
            item.setImageCaretOffset(cursor.utf16Offset)
            if !isBecomingFirstResponder, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            if pendingFocus == cursor {
                pendingFocus = nil
            }
            return
        }
        item.focusText(atUTF16Offset: cursor.utf16Offset)
        if pendingFocus == cursor {
            pendingFocus = nil
        }
    }

    private func mountedImageItem(for blockID: BlockInputBlockID) -> BlockInputBlockItem? {
        guard let index = activeStandaloneBlockIndex(for: blockID),
              block(at: index)?.kind.isImage == true else {
            return nil
        }
        return collectionView.item(at: IndexPath(item: index, section: 0)) as? BlockInputBlockItem
    }

    private func mountedBlockItem(for blockID: BlockInputBlockID) -> BlockInputBlockItem? {
        guard let index = index(of: blockID),
              let block = block(at: index) else {
            return nil
        }
        let indexPath = IndexPath(item: index, section: 0)
        guard let item = collectionView.item(at: indexPath) as? BlockInputBlockItem else {
            return nil
        }
        configureBlockItem(item, block: block, blockIndex: index)
        return item
    }

    func reloadDataKeepingFocus() {
        focusRestoreGeneration += 1
        let generation = focusRestoreGeneration
        collectionView.reloadData()
        collectionView.collectionViewLayout?.invalidateLayout()
        updatePlaceholderVisibility()
        if selection != nil {
            // AppKit may recreate items either immediately or on the next pass;
            // restoring in both places keeps cursor/text selection stable.
            restoreVisibleSelection()
            DispatchQueue.main.async { [weak self] in
                guard let self, focusRestoreGeneration == generation else {
                    return
                }
                collectionView.layoutSubtreeIfNeeded()
                restoreVisibleSelection()
                updatePlaceholderVisibility()
                invalidatePreferredHeight()
            }
        }
        invalidatePreferredHeight()
    }

    func reloadDataWithoutRestoringFocus() {
        focusRestoreGeneration += 1
        collectionView.reloadData()
        collectionView.collectionViewLayout?.invalidateLayout()
        collectionView.layoutSubtreeIfNeeded()
        updatePlaceholderVisibility()
        invalidatePreferredHeight()
    }

    func clearStaleFocusState() {
        if let selection, !containsValidSelection(selection) {
            applySelection(nil, notify: true)
        }
        if let cursor = pendingFocus, !containsValidCursor(cursor) {
            pendingFocus = nil
        }
        if let lastFocusedBlockID, index(of: lastFocusedBlockID) == nil {
            self.lastFocusedBlockID = nil
        }
    }

}
