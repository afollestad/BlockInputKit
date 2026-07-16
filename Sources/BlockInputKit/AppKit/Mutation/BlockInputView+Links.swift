import AppKit

/// Captures the source location a link popover or paste operation is allowed to mutate.
struct BlockInputLinkContext: Equatable {
    enum Mode: Equatable {
        /// Wrap or replace this source range with new Markdown link source.
        case create(NSRange)
        /// Replace this already-parsed Markdown link, after confirming the same link is still present.
        case edit(BlockInputInlineMarkdownRange)
    }

    let blockID: BlockInputBlockID
    let mode: Mode
    let sourceRange: NSRange
    /// Snapshot of the block text when the context was created, used to fail closed if a modal action becomes stale.
    let sourceText: String
    let anchorWindowRect: NSRect
}

extension BlockInputView {
    /// Builds the immutable source context for link UI and paste actions.
    func linkContext(
        blockID: BlockInputBlockID,
        selectedRange: NSRange,
        clickedLinkRange: BlockInputInlineMarkdownRange? = nil,
        event: NSEvent?,
        prefersClickedOffset: Bool
    ) -> BlockInputLinkContext? {
        guard let block = block(withID: blockID),
              supportsInlineLinkMutation(in: block, range: selectedRange) else {
            return nil
        }
        let item = visibleItem(for: blockID, refreshConfiguration: false)
        if let clickedContext = clickedLinkContext(
            blockID: blockID,
            block: block,
            item: item,
            clickedLinkRange: clickedLinkRange,
            event: event
        ) {
            return clickedContext
        }
        let clickedOffset: Int?
        if let event,
           let item {
            clickedOffset = item.utf16Offset(atWindowLocation: event.locationInWindow)
        } else {
            clickedOffset = nil
        }

        let range = linkInsertionRange(
            selectedRange: selectedRange,
            clickedOffset: clickedOffset,
            prefersClickedOffset: prefersClickedOffset
        )
        let linkLookupRange = prefersClickedOffset && clickedOffset != nil
            ? NSRange(location: clickedOffset ?? range.location, length: 0)
            : range
        guard supportsInlineLinkMutation(in: block, range: linkLookupRange) else {
            return nil
        }
        if let linkRange = linkRange(in: block.text, containing: linkLookupRange) {
            return linkEditContext(
                blockID: blockID,
                block: block,
                item: item,
                linkRange: linkRange,
                sourceRange: range
            )
        }
        let anchorRect = item?.anchorWindowRect(forUTF16Range: range) ?? .zero
        return BlockInputLinkContext(
            blockID: blockID,
            mode: .create(range),
            sourceRange: range,
            sourceText: block.text,
            anchorWindowRect: anchorRect
        )
    }

    func linkContextForActiveSelection(
        blockID blockIDOverride: BlockInputBlockID? = nil,
        urlPasteSelectedRangeOverride: NSRange? = nil
    ) -> BlockInputLinkContext? {
        guard let target = linkPasteTarget(
            blockID: blockIDOverride,
            selectedRangeOverride: urlPasteSelectedRangeOverride
        ) else {
            return nil
        }
        return linkContext(blockID: target.blockID, selectedRange: target.range, event: nil, prefersClickedOffset: false)
    }

    func linkContextMenuItems(for event: NSEvent) -> [NSMenuItem] {
        let collectionLocation = collectionView.convert(event.locationInWindow, from: nil)
        guard let indexPath = collectionView.indexPathForItem(at: collectionLocation),
              let item = collectionView.item(at: indexPath) as? BlockInputBlockItem else {
            return []
        }
        return item.linkContextMenuItems(for: event, selectedRange: item.currentSelectedRange)
    }

    func linkContextMenuItems(blockID: BlockInputBlockID, selectedRange: NSRange, event: NSEvent) -> [NSMenuItem] {
        guard isEditable else { return [] }
        let tableItems = tableContextMenuItems(blockID: blockID, selectedRange: selectedRange, event: event)
        let imageItems = imageContextMenuItems(blockID: blockID, selectedRange: selectedRange, event: event)
        guard let context = linkContext(
            blockID: blockID,
            selectedRange: selectedRange,
            event: event,
            prefersClickedOffset: true
        ) else {
            return imageItems + tableItems
        }
        let insertItem = NSMenuItem(title: "Insert Link", action: #selector(blockInputInsertLinkFromMenu(_:)), keyEquivalent: "")
        insertItem.target = self
        insertItem.representedObject = context
        guard case .edit = context.mode,
              context.sourceRange.length == 0 else {
            return [insertItem] + imageItems + tableItems
        }
        let removeItem = NSMenuItem(title: "Remove Link", action: #selector(blockInputRemoveLinkFromMenu(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.representedObject = context
        return [insertItem] + imageItems + tableItems + [removeItem]
    }

    @objc(blockInputInsertLinkFromMenu:)
    func blockInputInsertLinkFromMenu(_ sender: Any?) {
        guard let context = (sender as? NSMenuItem)?.representedObject as? BlockInputLinkContext else {
            return
        }
        _ = performCommand(.insertLink(BlockInputInsertLinkCommand(presentation: .modal)), context: .init(linkContext: context))
    }

    @objc(blockInputRemoveLinkFromMenu:)
    func blockInputRemoveLinkFromMenu(_ sender: Any?) {
        guard let context = (sender as? NSMenuItem)?.representedObject as? BlockInputLinkContext else {
            return
        }
        _ = performCommand(.removeLink, context: .init(linkContext: context))
        dismissLinkModal(restoreFocus: false)
    }

    /// Presents the single editor-owned link modal and binds its actions to the captured source context.
    func showLinkModal(context: BlockInputLinkContext, text prefilledText: String? = nil, urlString prefilledURLString: String? = nil) {
        guard isEditable, let block = block(withID: context.blockID) else { return }
        performEditorInteractionUIChanges {
            dismissImageModal(restoreFocus: false)
            dismissCompletionPopup()
            removeLinkModalDismissalMonitors()
            let modal = linkModalView ?? BlockInputLinkModalView()
            let mode: BlockInputLinkModalMode
            let text: String
            let urlString: String
            switch context.mode {
            case .create(let range):
                mode = .create
                text = prefilledText ?? (range.length > 0 ? linkCreationText(in: block, range: range) : "")
                urlString = prefilledURLString ?? ""
            case .edit(let linkRange):
                mode = .edit
                text = prefilledText ?? linkText(in: block, range: linkRange)
                urlString = prefilledURLString ?? linkRange.linkRawDestination ?? linkRange.linkDestination?.absoluteString ?? ""
            }
            modal.fileBaseURL = fileBaseURL
            modal.configure(mode: mode, text: text, urlString: urlString)
            configureLinkModalActions(modal, context: context, mode: mode)
            linkModalView = modal
            linkModalContext = context
            linkModalRetargetMouseDownWindowLocation = nil
            hostMutationModal(modal, kind: .link, anchoredTo: context.anchorWindowRect, minimumSize: NSSize(width: 300, height: 148))
            installLinkModalDismissalMonitors()
            modal.focusInitialField()
        }
    }

    private func configureLinkModalActions(
        _ modal: BlockInputLinkModalView,
        context: BlockInputLinkContext,
        mode: BlockInputLinkModalMode
    ) {
        modal.onSave = { [weak self] text, urlString in
            guard let self else { return }
            guard applyLinkEdit(
                context: context,
                text: text,
                urlString: urlString,
                actionName: mode == .create ? "Insert Link" : "Edit Link"
            ) else {
                dismissLinkModal(restoreFocus: false)
                return
            }
            dismissLinkModal(restoreFocus: false)
        }
        modal.onRemove = { [weak self] in
            guard let self else { return }
            _ = removeLink(context: context)
            dismissLinkModal(restoreFocus: false)
        }
        modal.onOpen = { [weak self, weak modal] urlString in
            let allowsCustomSchemes = modal?.textField.stringValue.hasPrefix("/") == true
            guard let self,
                  let url = BlockInputLinkURL.supportedURL(
                    from: urlString,
                    allowsCustomSchemes: allowsCustomSchemes,
                    fileBaseURL: fileBaseURL
                  ) else { return }
            _ = linkURLOpener(url)
        }
        modal.onCancel = { [weak self] in
            self?.dismissLinkModal(restoreFocus: true)
        }
        modal.onFocusCheck = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.dismissLinkModalIfFocusMovedOutside()
            }
        }
    }

    func dismissLinkModal(restoreFocus: Bool) {
        let context = linkModalContext
        removeLinkModalDismissalMonitors()
        linkModalView?.removeFromSuperview()
        linkModalView = nil
        linkModalContext = nil
        linkModalRetargetMouseDownWindowLocation = nil
        publishEditorInteractionUIChangeIfNeeded()
        guard restoreFocus,
              let context,
              let block = block(withID: context.blockID) else {
            return
        }
        switch context.mode {
        case .create(let range):
            if range.length > 0 {
                let clampedRange = block.text.blockInputLinkClampedRange(range)
                applySelection(.text(BlockInputTextRange(blockID: context.blockID, range: clampedRange)), notify: true)
                restoreVisibleSelection()
            } else {
                focus(blockID: context.blockID, utf16Offset: min(NSMaxRange(range), block.utf16Length))
            }
        case .edit(let linkRange):
            let clampedRange = block.text.blockInputLinkClampedRange(linkRange.contentRange)
            applySelection(.text(BlockInputTextRange(blockID: context.blockID, range: clampedRange)), notify: true)
            restoreVisibleSelection()
        }
    }

    /// Handles supported URL paste by editing an existing link or inserting Markdown without selecting the result.
    @discardableResult
    func pasteURLString(_ urlString: String, blockID: BlockInputBlockID? = nil, selectedRange: NSRange? = nil) -> Bool {
        guard isEditable else { return false }
        guard BlockInputLinkURL.supportedURL(from: urlString) != nil else {
            return false
        }
        if pasteURLIntoMarkdownImageDestinationIfNeeded(urlString, blockID: blockID, selectedRange: selectedRange) {
            return true
        }
        guard
              let context = linkContextForActiveSelection(blockID: blockID, urlPasteSelectedRangeOverride: selectedRange),
              let block = block(withID: context.blockID) else {
            return false
        }
        switch context.mode {
        case .edit(let linkRange):
            return applyLinkEdit(
                context: context,
                text: linkText(in: block, range: linkRange),
                urlString: urlString,
                actionName: "Edit Link",
                selectsResultingText: false
            )
        case .create(let range):
            let label: String
            if range.length > 0 {
                label = linkCreationText(in: block, range: range)
            } else {
                label = urlString
            }
            return applyLinkEdit(
                context: context,
                text: label,
                urlString: urlString,
                actionName: "Insert Link",
                selectsResultingText: false
            )
        }
    }

    @discardableResult
    func applyLinkEdit(
        context: BlockInputLinkContext,
        text: String,
        urlString: String,
        actionName: String,
        selectsResultingText: Bool = true
    ) -> Bool {
        guard isEditable else { return false }
        guard let destination = BlockInputLinkURL.supportedURL(
                from: urlString,
                allowsCustomSchemes: text.hasPrefix("/"),
                fileBaseURL: fileBaseURL
              ),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = index(of: context.blockID),
              var block = block(at: index) else {
            return false
        }
        let escapedLabel = BlockInputLinkURL.escapedLabel(text)
        let markdownDestination = BlockInputLinkURL.markdownDestination(from: urlString, resolvedURL: destination)
        let replacement = BlockInputLinkReplacement(
            text: BlockInputLinkURL.markdownLink(escapedLabel: escapedLabel, destination: markdownDestination),
            selectedUTF16Length: (escapedLabel as NSString).length,
            selectsResultingText: selectsResultingText,
            actionName: actionName
        )
        return replaceLinkSource(context: context, block: &block, index: index, replacement: replacement)
    }

    @discardableResult
    func removeLink(context: BlockInputLinkContext) -> Bool {
        guard isEditable else { return false }
        guard case .edit(let linkRange) = context.mode,
              let index = index(of: context.blockID),
              var block = block(at: index) else {
            return false
        }
        let text = linkText(in: block, range: linkRange)
        let replacement = BlockInputLinkReplacement(
            text: text,
            selectedUTF16Length: (text as NSString).length,
            selectsResultingText: true,
            actionName: "Remove Link"
        )
        return replaceLinkSource(context: context, block: &block, index: index, replacement: replacement)
    }

    func linkRange(in text: String, containing range: NSRange) -> BlockInputInlineMarkdownRange? {
        let clampedRange = text.blockInputLinkClampedRange(range)
        return BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange),
            fileBaseURL: fileBaseURL
        )
        .filter { $0.style == .link }
        .first { linkRange in
            if clampedRange.length == 0 {
                if linkRange.inlineChipKind(in: text) != nil {
                    return linkRange.fullRange.location <= clampedRange.location &&
                        clampedRange.location < NSMaxRange(linkRange.fullRange)
                }
                return linkRange.contentRange.containsOrTouches(clampedRange.location)
            }
            return linkRange.contentRange.intersectionLength(with: clampedRange) > 0 ||
                linkRange.fullRange.intersectionLength(with: clampedRange) == clampedRange.length
        }
    }

    func linkText(in text: String, range: BlockInputInlineMarkdownRange) -> String {
        (text as NSString).substring(with: text.blockInputLinkClampedRange(range.contentRange)).blockInputUnescapedLinkLabel
    }

    func linkText(in block: BlockInputBlock, range: BlockInputInlineMarkdownRange) -> String {
        linkText(in: block, sourceRange: range.contentRange).blockInputUnescapedLinkLabel
    }

    private func replaceLinkSource(
        context: BlockInputLinkContext,
        block: inout BlockInputBlock,
        index: Int,
        replacement: BlockInputLinkReplacement
    ) -> Bool {
        let beforeBlock = block
        let beforeSelection = selection
        // Modal actions fail closed if typing, undo, or another edit changed the backing text while the modal was open.
        guard block.text == context.sourceText else {
            return false
        }
        let replacementRange: NSRange
        switch context.mode {
        case .create(let range):
            replacementRange = block.text.blockInputLinkClampedRange(range)
        case .edit(let existingLinkRange):
            guard existingLinkRange == linkRange(in: block.text, containing: existingLinkRange.contentRange) else {
                return false
            }
            replacementRange = block.text.blockInputLinkClampedRange(existingLinkRange.fullRange)
        }
        if block.kind == .table {
            return replaceTableCellLinkSource(BlockInputTableCellLinkReplacement(
                block: block,
                beforeBlock: beforeBlock,
                beforeSelection: beforeSelection,
                index: index,
                replacementRange: replacementRange,
                replacement: replacement
            ))
        }
        let mutableText = NSMutableString(string: block.text)
        mutableText.replaceCharacters(in: replacementRange, with: replacement.text)
        block.text = mutableText as String
        let afterSelection = linkReplacementSelection(block: block, replacementRange: replacementRange, replacement: replacement)
        _ = applyGranularBlockReplacement(block, at: index, selection: afterSelection)
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: replacement.actionName,
            beforeBlock: beforeBlock,
            afterBlock: block,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        return true
    }

    private func linkReplacementSelection(
        block: BlockInputBlock,
        replacementRange: NSRange,
        replacement: BlockInputLinkReplacement
    ) -> BlockInputSelection {
        if replacement.selectsResultingText {
            let contentOffset = replacement.actionName == "Remove Link" ? replacementRange.location : replacementRange.location + 1
            return .text(BlockInputTextRange(
                blockID: block.id,
                range: NSRange(location: contentOffset, length: replacement.selectedUTF16Length)
            ))
        }
        let cursorOffset = replacementRange.location + (replacement.text as NSString).length
        return .cursor(BlockInputCursor(blockID: block.id, utf16Offset: cursorOffset))
    }

    private func supportsInlineLinkMutation(in block: BlockInputBlock, range: NSRange) -> Bool {
        if block.kind.supportsImageSyntaxSplitting,
           block.text.blockInputMarkdownImageDestinationRange(containing: range) != nil {
            return false
        }
        if BlockInputBlockItem.supportsInlineMarkdownStyling(block.kind) {
            return true
        }
        guard block.kind == .table,
              let table = BlockInputTable(markdown: block.text) else {
            return false
        }
        guard let position = table.cellPosition(containingSourceRange: range) else {
            return false
        }
        return table.localRange(forSourceRange: range, in: position) != nil
    }

    private func linkInsertionRange(
        selectedRange: NSRange,
        clickedOffset: Int?,
        prefersClickedOffset: Bool
    ) -> NSRange {
        guard prefersClickedOffset,
              let clickedOffset,
              !selectedRange.containsOrTouches(clickedOffset) else {
            return selectedRange
        }
        return NSRange(location: clickedOffset, length: 0)
    }

    private func linkCreationText(in block: BlockInputBlock, range: NSRange) -> String {
        linkText(in: block, sourceRange: range)
    }

    func linkText(in block: BlockInputBlock, sourceRange: NSRange) -> String {
        if block.kind == .table,
           let table = BlockInputTable(markdown: block.text),
           let position = table.cellPosition(containingSourceRange: sourceRange),
           let localRange = table.localRange(forSourceRange: sourceRange, in: position),
           let cell = table.cell(at: position) {
            return (cell.text as NSString).substring(with: cell.text.blockInputLinkClampedRange(localRange))
        }
        return (block.text as NSString).substring(with: block.text.blockInputLinkClampedRange(sourceRange))
    }
}

/// Replacement payload used by link mutations to keep source text and resulting selection decisions together.
struct BlockInputLinkReplacement {
    var text: String
    var selectedUTF16Length: Int
    var selectsResultingText: Bool
    var actionName: String
}
