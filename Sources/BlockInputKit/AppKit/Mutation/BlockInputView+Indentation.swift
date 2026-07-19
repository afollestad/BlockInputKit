import AppKit

extension BlockInputView {
    enum IndentationDirection {
        case indent
        case outdent
    }

    func performBlockIndentationEdit(
        named actionName: String,
        item: BlockInputBlockItem,
        blockID: BlockInputBlockID,
        selectedRange: NSRange,
        direction: IndentationDirection
    ) -> BlockInputSelection? {
        guard isEditable else {
            return nil
        }
        if !isDocumentCacheSynchronized {
            refreshDocumentFromStore()
        }
        guard let index = index(of: blockID),
              let beforeBlock = block(at: index),
              beforeBlock.kind.supportsIndentation else {
            return nil
        }
        let beforeSelection = selection
        let beforeDocument = document
        guard let indentationResult = indentedBlock(
            from: beforeBlock,
            blockID: blockID,
            selectedRange: selectedRange,
            direction: direction
        ) else {
            return nil
        }
        var afterBlock = indentationResult.0
        let afterSelection = indentationResult.1
        var afterDocument = document
        afterDocument.blocks[index] = afterBlock
        if afterBlock.kind.isNumberedListItem {
            afterDocument.normalizeNumberedListStartsAround(index)
        }
        afterBlock = afterDocument.blocks[index]
        let changedBlocks = changedBlocksAfterIndentation(
            before: beforeDocument,
            after: afterDocument,
            around: index
        )
        guard !changedBlocks.isEmpty else {
            applySelection(afterSelection, notify: beforeSelection != afterSelection)
            return nil
        }
        let edit = BlockInputIndentationEdit(
            beforeDocument: beforeDocument,
            afterDocument: afterDocument,
            beforeBlock: beforeBlock,
            afterBlock: afterBlock,
            changedBlocks: changedBlocks,
            beforeSelection: beforeSelection,
            afterSelection: afterSelection,
            blockIndex: index
        )
        applyIndentationEdit(edit, named: actionName, item: item)
        return afterSelection
    }

    private func applyIndentationEdit(
        _ edit: BlockInputIndentationEdit,
        named actionName: String,
        item: BlockInputBlockItem
    ) {
        // Most indentation edits replace one block; ordered-list renumbering may
        // add sibling replacements so markers stay visually consistent.
        for changedBlock in edit.changedBlocks {
            syncDocumentStore(.replaceBlock(changedBlock))
        }
        document = edit.afterDocument
        applySelection(edit.afterSelection, notify: true)
        registerIndentationUndo(actionName: actionName, edit: edit)
        if edit.changedBlocks.count == 1 {
            updateVisibleItemAfterIndentation(
                item,
                beforeBlock: edit.beforeBlock,
                afterBlock: edit.afterBlock,
                afterSelection: edit.afterSelection,
                index: edit.blockIndex
            )
        } else {
            reloadDataKeepingFocus()
        }
        publishDocumentChange()
    }

    private func changedBlocksAfterIndentation(
        before beforeDocument: BlockInputDocument,
        after afterDocument: BlockInputDocument,
        around index: Int
    ) -> [BlockInputBlock] {
        guard beforeDocument.blocks.indices.contains(index),
              afterDocument.blocks.indices.contains(index) else {
            return changedBlocksByID(before: beforeDocument, after: afterDocument)
        }
        let beforeBlock = beforeDocument.blocks[index]
        let afterBlock = afterDocument.blocks[index]
        guard beforeBlock.kind.isNumberedListItem || afterBlock.kind.isNumberedListItem else {
            return beforeBlock == afterBlock ? [] : [afterBlock]
        }
        guard let listRange = afterDocument.listRangeForIndentationChange(around: index) else {
            return beforeBlock == afterBlock ? [] : [afterBlock]
        }
        return listRange.compactMap { changedIndex in
            guard beforeDocument.blocks.indices.contains(changedIndex) else {
                return afterDocument.blocks[changedIndex]
            }
            return beforeDocument.blocks[changedIndex] == afterDocument.blocks[changedIndex]
                ? nil
                : afterDocument.blocks[changedIndex]
        }
    }

    private func registerIndentationUndo(
        actionName: String,
        edit: BlockInputIndentationEdit
    ) {
        if edit.changedBlocks.count == 1 {
            undoController?.registerBlockReplacementStructuralEdit(
                actionName: actionName,
                beforeBlock: edit.beforeBlock,
                afterBlock: edit.afterBlock,
                selectionBefore: edit.beforeSelection,
                selectionAfter: edit.afterSelection
            )
            return
        }
        undoController?.registerStructuralEdit(
            actionName: actionName,
            beforeDocument: edit.beforeDocument,
            afterDocument: edit.afterDocument,
            selectionBefore: edit.beforeSelection,
            selectionAfter: edit.afterSelection
        )
    }

    private func updateVisibleItemAfterIndentation(
        _ item: BlockInputBlockItem,
        beforeBlock: BlockInputBlock,
        afterBlock: BlockInputBlock,
        afterSelection: BlockInputSelection,
        index: Int
    ) {
        guard item.representedBlockID == afterBlock.id else {
            return
        }
        refreshIndentedItem(item, for: afterBlock)
        if case let .cursor(cursor) = afterSelection {
            item.setSelectedRange(NSRange(location: cursor.utf16Offset, length: 0))
        }
        item.view.needsLayout = true
        item.view.layoutSubtreeIfNeeded()
        if heightChangesAfterIndentation(item: item, beforeBlock: beforeBlock, afterBlock: afterBlock) {
            resizeVisibleItem(item, for: afterBlock)
            invalidateLayoutForBlock(at: index, editedItem: item, block: afterBlock)
        }
    }

    private func refreshIndentedItem(_ item: BlockInputBlockItem, for block: BlockInputBlock) {
        guard item.currentText != block.text else {
            item.updateTextDependentChrome(for: block)
            return
        }
        item.configure(
            block: block,
            allowsReordering: allowsBlockReordering,
            editorHorizontalInset: editorHorizontalInset,
            accentColor: dropIndicatorColor,
            style: style,
            isSelected: isBlockSelected(block.id),
            delegate: self
        )
    }

    private func heightChangesAfterIndentation(
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
        return abs(beforeHeight - afterHeight) > 0.5
    }

    private func indentedBlock(
        from beforeBlock: BlockInputBlock,
        blockID: BlockInputBlockID,
        selectedRange: NSRange,
        direction: IndentationDirection
    ) -> (BlockInputBlock, BlockInputSelection)? {
        var afterBlock = beforeBlock
        let selectedOffset = min(max(selectedRange.location, 0), beforeBlock.utf16Length)
        if beforeBlock.text.contains("\n") || !beforeBlock.lineIndentationLevels.isEmpty {
            let lineIndex = beforeBlock.lineIndex(containingUTF16Offset: selectedOffset)
            guard updateLineIndentation(in: &afterBlock, lineIndex: lineIndex, direction: direction) else {
                return nil
            }
        } else {
            guard updateBlockIndentation(in: &afterBlock, direction: direction) else {
                return nil
            }
        }
        let selection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: blockID,
            utf16Offset: selectedOffset
        ))
        return (afterBlock, selection)
    }

    private func updateLineIndentation(
        in block: inout BlockInputBlock,
        lineIndex: Int,
        direction: IndentationDirection
    ) -> Bool {
        let currentLevel = block.indentationLevel(forLine: lineIndex)
        switch direction {
        case .indent:
            block.setIndentationLevel(currentLevel + 1, forLine: lineIndex)
            return true
        case .outdent:
            guard currentLevel > 0 else {
                return false
            }
            block.setIndentationLevel(currentLevel - 1, forLine: lineIndex)
            return true
        }
    }

    private func updateBlockIndentation(
        in block: inout BlockInputBlock,
        direction: IndentationDirection
    ) -> Bool {
        switch direction {
        case .indent:
            block.indentationLevel += 1
            return true
        case .outdent:
            guard block.indentationLevel > 0 else {
                return false
            }
            block.indentationLevel = max(0, block.indentationLevel - 1)
            return true
        }
    }

}

private struct BlockInputIndentationEdit {
    var beforeDocument: BlockInputDocument
    var afterDocument: BlockInputDocument
    var beforeBlock: BlockInputBlock
    var afterBlock: BlockInputBlock
    var changedBlocks: [BlockInputBlock]
    var beforeSelection: BlockInputSelection?
    var afterSelection: BlockInputSelection
    var blockIndex: Int
}

private extension BlockInputDocument {
    func listRangeForIndentationChange(around index: Int) -> Range<Int>? {
        guard !blocks.isEmpty else {
            return nil
        }
        let clampedIndex = min(max(index, 0), blocks.count - 1)
        guard blocks[clampedIndex].kind.isListItem else {
            return nil
        }
        var lowerBound = clampedIndex
        while lowerBound > 0, blocks[lowerBound - 1].kind.isListItem {
            lowerBound -= 1
        }
        var upperBound = clampedIndex + 1
        while upperBound < blocks.count, blocks[upperBound].kind.isListItem {
            upperBound += 1
        }
        return lowerBound..<upperBound
    }
}

private extension BlockInputBlockKind {
    var isNumberedListItem: Bool {
        if case .numberedListItem = self {
            return true
        }
        return false
    }

    var isListItem: Bool {
        switch self {
        case .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .paragraph, .heading, .code, .horizontalRule, .frontMatter, .quote, .table, .image, .rawMarkdown:
            return false
        }
    }
}
