import AppKit

extension BlockInputView: BlockInputBlockItemDelegate {
    func blockItemDidBeginEditing(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) {
        guard index(of: blockID) != nil else {
            return
        }
        let previousActiveBlockID = currentSelectionOwnerBlockID()
        publishFocusChange(true)
        let offset = item.currentSelectedRange.location
        applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: offset)), notify: true)
        if let previousActiveBlockID,
           previousActiveBlockID != blockID {
            refreshSelectionDependentAttributesForVisibleItem(blockID: previousActiveBlockID)
        }
    }

    func blockItemDidEndEditing(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) {
        dismissCompletionPopup()
        item.textView.clearInlineHint()
        publishFocusLossIfNeeded()
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didChangeText text: String,
        selectionBefore capturedSelectionBefore: BlockInputSelection?
    ) {
        guard let index = index(of: blockID),
              let beforeBlock = block(at: index),
              beforeBlock.id == blockID else {
            return
        }
        let beforeText = beforeBlock.text
        guard beforeText != text else {
            return
        }
        if discardReadOnlyTextChangeIfNeeded(item: item, block: beforeBlock) { return }
        if beforeBlock.kind == .horizontalRule {
            configureBlockItem(item, block: beforeBlock)
            return
        }
        replaceCachedBlock(beforeBlock, at: index)
        let resolvedChange = resolvedInlineChipBoundaryTextChange(
            item: item,
            beforeBlock: beforeBlock,
            proposedText: text,
            selectionBefore: capturedSelectionBefore
        )
        if let shortcutSelection = applyTypingShortcutIfNeeded(
            blockID: blockID,
            proposedText: resolvedChange.text,
            proposedUTF16Offset: resolvedChange.proposedOffset,
            selectionBefore: capturedSelectionBefore
        ) {
            // Shortcuts can insert a new focused block and reload collection items,
            // so only reconfigure this item if it still owns the edited block.
            if case let .cursor(cursor) = shortcutSelection,
               cursor.blockID == blockID,
               item.representedBlockID == blockID {
                if let block = block(withID: blockID) {
                    configureBlockItem(item, block: block)
                }
                item.setSelectedRange(NSRange(location: cursor.utf16Offset, length: 0))
            }
            return
        }
        applyPlainTextChange(
            item: item,
            blockIndex: index,
            change: PlainTextChangeContext(
                beforeBlock: beforeBlock,
                afterText: resolvedChange.text,
                proposedOffset: resolvedChange.proposedOffset,
                selectionBefore: capturedSelectionBefore
            )
        )
        refreshCompletionSession(item: item, blockID: blockID)
    }

    private func applyPlainTextChange(
        item: BlockInputBlockItem,
        blockIndex index: Int,
        change: PlainTextChangeContext
    ) {
        let beforeSelection = change.selectionBefore ?? selection
        var afterBlock = change.beforeBlock
        afterBlock.text = change.afterText
        if let lineIndentationLevels = lineIndentationLevelsAfterTextChange(
            beforeBlock: change.beforeBlock,
            afterText: change.afterText,
            selectionBefore: change.selectionBefore
        ) {
            afterBlock.lineIndentationLevels = lineIndentationLevels
        }
        let didReplaceCachedBlock = replaceCachedBlock(afterBlock, at: index)
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: change.beforeBlock.id,
            utf16Offset: change.proposedOffset
        ))
        applySelection(afterSelection, notify: true)
        undoController?.registerTextEdit(
            blockID: change.beforeBlock.id,
            beforeText: change.beforeBlock.text,
            afterText: change.afterText,
            beforeLineIndentationLevels: change.beforeBlock.lineIndentationLevels,
            afterLineIndentationLevels: afterBlock.lineIndentationLevels,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        item.updateTextDependentChrome(for: afterBlock)
        let invalidatesLayout = shouldInvalidateLayoutForTextChange(
            item: item,
            beforeBlock: change.beforeBlock,
            afterBlock: afterBlock
        )
        if invalidatesLayout {
            resizeVisibleItem(item, for: afterBlock)
            invalidateLayoutForBlock(at: index, editedItem: item, block: afterBlock)
        }
        if invalidatesLayout {
            scrollActiveTextSelectionToVisibleIfNeeded()
        }
        syncDocumentStore(.replaceBlock(afterBlock))
        if !didReplaceCachedBlock && isDocumentCacheSynchronized {
            refreshDocumentFromStore()
        }
        publishDocumentChange()
    }

    func shouldInvalidateLayoutForTextChange(
        item: BlockInputBlockItem,
        beforeBlock: BlockInputBlock,
        afterBlock: BlockInputBlock
    ) -> Bool {
        let itemWidth = item.view.bounds.width > 0 ? item.view.bounds.width : collectionView.bounds.width
        let beforeHeight = measuredBlockItemHeight(
            for: beforeBlock,
            itemWidth: itemWidth,
            isDocumentStartBlock: item.isDocumentStartBlock
        )
        let afterHeight = measuredBlockItemHeight(
            for: afterBlock,
            itemWidth: itemWidth,
            isDocumentStartBlock: item.isDocumentStartBlock
        )
        let isStaleCodeBlockHeight: Bool
        if case .code = afterBlock.kind {
            isStaleCodeBlockHeight = abs(item.view.frame.height - afterHeight) > 0.5
        } else {
            isStaleCodeBlockHeight = false
        }
        return abs(beforeHeight - afterHeight) > 0.5
            || isStaleCodeBlockHeight
    }

    func blockItemDidRequestReturn(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool {
        guard isEditable else {
            return false
        }
        guard let block = block(withID: blockID) else {
            return true
        }
        let currentBlock = BlockInputBlock(
            id: block.id,
            kind: block.kind,
            text: item.currentText,
            indentationLevel: block.indentationLevel,
            lineIndentationLevels: block.lineIndentationLevels
        )
        let selectedRange = inlineChipBoundaryAdjustedRange(item.currentSelectedRange, in: currentBlock)
        if block.kind.acceptsInlineReturn,
           !(selectedRange.length == 0 &&
             selectedRange.location == 0 &&
             currentBlock.canMoveDownOnLeadingReturn),
           !currentBlock.requiresStructuralReturnHandling(
               utf16Offset: selectedRange.location,
               selectedUTF16Length: selectedRange.length
           ) {
            return false
        }
        if selectedRange.length == 0 {
            applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: selectedRange.location)), notify: false)
        } else {
            applySelection(.text(BlockInputTextRange(blockID: blockID, range: selectedRange)), notify: false)
        }
        insertBlockBelowCurrentBlock()
        return true
    }

    func blockItemDidRequestMergeWithPreviousBlock(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool {
        guard isEditable else {
            return false
        }
        guard item.currentSelectedRange.location == 0,
              item.currentSelectedRange.length == 0 else {
            return false
        }
        applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)
        return mergeBlockIntoPrevious(blockID: blockID) != nil
    }

    func blockItemDidRequestDeleteEmptyBlock(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool {
        guard isEditable else {
            return false
        }
        guard let block = block(withID: blockID) else {
            return false
        }
        if block.kind == .horizontalRule {
            return deleteSelectedHorizontalRuleForBackspaceOrDelete() != nil
        }
        guard block.isEmpty else {
            return false
        }
        applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)
        return deleteCurrentEmptyBlockForBackspaceOrDelete() != nil
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestLinkBoundaryDeletion direction: BlockInputLinkBoundaryDeletionDirection
    ) -> Bool {
        guard isEditable else {
            return false
        }
        return deleteLinkAtBoundary(item: item, blockID: blockID, direction: direction)
    }

    func blockItemDidRevealReorderHandle(_ item: BlockInputBlockItem) {
        hideReorderHandles(except: item)
    }

    func blockItemDidRequestUnwrapBlock(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool {
        guard isEditable else {
            return false
        }
        guard let currentBlock = block(withID: blockID) else {
            return false
        }
        if currentBlock.kind == .horizontalRule,
           selection == .blocks([blockID]) {
            return deleteSelectedHorizontalRuleForBackspaceOrDelete() != nil
        }
        if currentBlock.kind == .frontMatter, currentBlock.isEmpty {
            return false
        }
        guard currentBlock.kind.canUnwrapToParagraph else {
            return false
        }
        applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)
        guard let unwrapSelection = unwrapBlockToParagraph(blockID: blockID) else {
            return false
        }
        guard item.representedBlockID == blockID else {
            return true
        }
        if let updatedBlock = block(withID: blockID) {
            configureBlockItem(item, block: updatedBlock)
        }
        if case let .cursor(cursor) = unwrapSelection, cursor.blockID == blockID {
            item.setSelectedRange(NSRange(location: cursor.utf16Offset, length: 0))
        }
        return true
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestUndoShortcut shortcut: BlockInputUndoShortcut
    ) -> Bool {
        guard isEditable else {
            return false
        }
        return performCommand(BlockInputEditorCommand(shortcut), context: BlockInputResolvedCommandContext(preferredBlockID: blockID))
    }

    func blockItemDidRequestCopyActiveSelection(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool {
        performCommand(.copy)
    }

    func blockItemDidRequestCutActiveSelection(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool {
        guard isEditable else {
            return false
        }
        return performCommand(.cut)
    }

    func blockItemDidRequestPasteActiveSelection(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool {
        guard isEditable else {
            return false
        }
        return performCommand(.paste)
    }

    func blockItemDidRequestDeleteActiveSelection(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) -> Bool {
        guard isEditable else {
            return false
        }
        guard selection == .blocks([blockID]),
              block(withID: blockID)?.kind == .table else {
            return false
        }
        return deleteSelectedBlocksForBackspaceOrDelete() != nil
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestTextFormattingShortcut shortcut: BlockInputTextFormattingShortcut
    ) -> Bool {
        guard isEditable else {
            return false
        }
        if item.currentSelectedRange.length > 0,
           !usesEditorLevelTextFormattingSelection {
            applySelection(.text(BlockInputTextRange(blockID: blockID, range: item.currentSelectedRange)), notify: false)
        }
        return performCommand(BlockInputEditorCommand(shortcut))
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        didRequestKeyboardShortcut shortcut: BlockInputKeyboardShortcut,
        selectedRange: NSRange,
        focusSource: BlockInputKeyboardShortcutFocusSource,
        isRepeat: Bool,
        performDefault: @escaping @MainActor (BlockInputKeyboardShortcut) -> Bool
    ) -> BlockInputKeyboardShortcutDispatchResult {
        dispatchKeyboardShortcut(
            shortcut,
            focusSource: focusSource,
            isRepeat: isRepeat,
            selectionOverride: keyboardShortcutSelection(blockID: blockID, selectedRange: selectedRange),
            activeBlockOverride: keyboardShortcutBlock(item: item, blockID: blockID, focusSource: focusSource),
            performDefault: performDefault
        )
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        textFormattingMenuItemStatesForSelectedRange selectedRange: NSRange
    ) -> [BlockInputTextFormattingMenuItemState] {
        textFormattingContextMenuItemStates(selectedRange: selectedRange, in: blockID)
    }

    func blockItem(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        textFormattingMenuItemStatesForContextEvent event: NSEvent
    ) -> [BlockInputTextFormattingMenuItemState] {
        textFormattingContextMenuItemStates(for: event)
    }

    func blockItemDidRequestToggleChecklist(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) {
        guard isEditable else {
            return
        }
        _ = toggleChecklistItem(blockID: blockID)
    }

    func blockItemDidBeginReordering(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) {
        _ = cancelMultiBlockSelectionForReorderStart()
    }

    func blockItemDidRequestSelectHorizontalRule(_ item: BlockInputBlockItem, blockID: BlockInputBlockID) {
        refreshDocumentFromStore()
        let selectedIndex = collectionView.indexPath(for: item)?.item
        let selectedKind = selectedIndex.flatMap { block(at: $0)?.kind } ?? block(withID: blockID)?.kind
        guard selectedKind == .horizontalRule || selectedKind?.isImage == true else {
            return
        }
        selectedHorizontalRuleIndex = selectedIndex
        hideDropIndicator()
        blockSelectionExpansion = nil
        applySelection(.blocks([blockID]), notify: true)
        selectOnlyVisibleBlockItem(item)
        window?.makeFirstResponder(self)
        selectOnlyVisibleBlockItem(item)
        publishFocusChange(true)
    }

    func blockItemDidRequestIndent(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        selectedRange: NSRange
    ) {
        guard isEditable else {
            return
        }
        _ = performBlockIndentationEdit(
            named: "Indent Block",
            item: item,
            blockID: blockID,
            selectedRange: selectedRange,
            direction: .indent
        )
    }

    func blockItemDidRequestOutdent(
        _ item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        selectedRange: NSRange
    ) {
        guard isEditable else {
            return
        }
        _ = performBlockIndentationEdit(
            named: "Outdent Block",
            item: item,
            blockID: blockID,
            selectedRange: selectedRange,
            direction: .outdent
        )
    }

    private func lineIndentationLevelsAfterTextChange(
        beforeBlock: BlockInputBlock,
        afterText: String,
        selectionBefore: BlockInputSelection?
    ) -> [Int]? {
        guard beforeBlock.kind.supportsIndentation else {
            return nil
        }
        guard let editRange = editRange(in: beforeBlock.id, selectionBefore: selectionBefore) else {
            return nil
        }
        return beforeBlock.lineIndentationLevelsAfterReplacingText(
            utf16Offset: editRange.location,
            selectedUTF16Length: editRange.length,
            updatedText: afterText
        )
    }

    private func editRange(
        in blockID: BlockInputBlockID,
        selectionBefore: BlockInputSelection?
    ) -> NSRange? {
        switch selectionBefore {
        case let .cursor(cursor) where cursor.blockID == blockID:
            return NSRange(location: cursor.utf16Offset, length: 0)
        case let .text(range) where range.blockID == blockID:
            return range.range
        default:
            return nil
        }
    }

}

private struct PlainTextChangeContext {
    var beforeBlock: BlockInputBlock
    var afterText: String
    var proposedOffset: Int
    var selectionBefore: BlockInputSelection?
}
