import AppKit

// Selection-state application and the visible-row selection chrome it drives;
// focus claiming and restoration live in `BlockInputView+Focus.swift`.
extension BlockInputView {
    func applySelection(_ selection: BlockInputSelection?, notify: Bool) {
        let selection = normalizedTableSelection(selection)
        BlockInputSelectionDebug.emit("apply selection=\(String(describing: selection)) notify=\(notify)")
        dismissLinkModalIfSelectionMovedOutside(selection)
        self.selection = selection
        horizontalSelectionExpansion = nil
        tableKeyboardRowSelection = nil
        preferredNavigationX = nil
        switch selection {
        case let .cursor(cursor):
            lastFocusedBlockID = cursor.blockID
            pendingFocus = cursor
            if let selectedIndex = selectedHorizontalRuleIndex,
               block(at: selectedIndex)?.id == cursor.blockID,
               block(at: selectedIndex)?.kind.isSelectableStandaloneBlock == true {
                selectedHorizontalRuleIndex = selectedIndex
            } else {
                selectedHorizontalRuleIndex = nil
            }
            lastNativeTextSelectionExpansion = nil
            blockSelectionExpansion = nil
        case let .text(range):
            lastFocusedBlockID = range.blockID
            pendingFocus = nil
            selectedHorizontalRuleIndex = nil
            blockSelectionExpansion = nil
        case let .blocks(blockIDs):
            lastFocusedBlockID = blockIDs.first
            pendingFocus = nil
            lastNativeTextSelectionExpansion = nil
        case let .mixed(mixedSelection):
            lastFocusedBlockID = mixedSelection.leadingTextRange?.blockID
                ?? mixedSelection.trailingTextRange?.blockID
                ?? mixedSelection.blockIDs.first
            pendingFocus = nil
            selectedHorizontalRuleIndex = nil
            lastNativeTextSelectionExpansion = nil
        case nil:
            pendingFocus = nil
            selectedHorizontalRuleIndex = nil
            lastNativeTextSelectionExpansion = nil
            blockSelectionExpansion = nil
        }
        if notify {
            onSelectionChange?(selection)
        }
        updateVisibleBlockSelectionHighlights()
        updateInlineHintsForVisibleItems()
    }

    func isBlockSelected(_ blockID: BlockInputBlockID) -> Bool {
        guard let blockIDs = selection?.wholeSelectedBlockIDs else {
            return false
        }
        return blockIDs.contains(blockID)
    }

    var selectedBlockCount: Int {
        selection?.wholeSelectedBlockIDs.count ?? 0
    }

    func updateVisibleBlockSelectionHighlights() {
        let activeImageCursorIndex = activeImageCursorIndexForSelection()
        for item in collectionView.visibleItems().compactMap({ $0 as? BlockInputBlockItem }) {
            guard let blockID = item.representedBlockID else {
                item.setBlockSelection(false)
                item.setImageCaretOffset(nil)
                continue
            }
            item.setBlockSelection(isBlockSelected(blockID))
            if case let .cursor(cursor) = selection,
               cursor.blockID == blockID,
               activeImageCursorIndex == collectionView.indexPath(for: item)?.item {
                item.setImageCaretOffset(cursor.utf16Offset)
            } else {
                item.setImageCaretOffset(nil)
            }
            if let range = selection?.partialTextRange(for: blockID) {
                item.setSelectionHighlightRange(range.range)
            } else if let range = selection?.textRange(for: blockID) {
                item.setFocusedTextSelectionHighlightRange(range.range)
            } else if shouldCollapseNativeTextSelection(in: blockID) {
                // Editor-level selections use custom row chrome. Collapse any leftover AppKit range so an inactive
                // gray `NSTextView` selection cannot drift over the blue multi-selection background.
                item.collapseNativeSelectionIfNeeded()
            }
        }
    }

    private func activeImageCursorIndexForSelection() -> Int? {
        guard case let .cursor(cursor) = selection,
              block(withID: cursor.blockID)?.kind.isImage == true else {
            return nil
        }
        return activeStandaloneBlockIndex(for: cursor.blockID)
    }

    private func shouldCollapseNativeTextSelection(in blockID: BlockInputBlockID) -> Bool {
        switch selection {
        case .blocks, .mixed, nil:
            return true
        case let .cursor(cursor):
            return cursor.blockID != blockID
        case let .text(textRange):
            return textRange.blockID != blockID
        }
    }

    func selectedBlockIDs(in selection: BlockInputMixedSelection) -> [BlockInputBlockID] {
        var blockIDs = selection.blockIDs
        if let blockID = selection.leadingTextRange?.blockID, !blockIDs.contains(blockID) {
            blockIDs.append(blockID)
        }
        if let blockID = selection.trailingTextRange?.blockID, !blockIDs.contains(blockID) {
            blockIDs.append(blockID)
        }
        return blockIDs.sorted { lhs, rhs in
            (index(of: lhs) ?? Int.max) < (index(of: rhs) ?? Int.max)
        }
    }

    func selectOnlyVisibleBlockItem(_ selectedItem: BlockInputBlockItem) {
        for item in collectionView.visibleItems().compactMap({ $0 as? BlockInputBlockItem }) {
            item.setBlockSelection(item === selectedItem)
        }
    }
}
