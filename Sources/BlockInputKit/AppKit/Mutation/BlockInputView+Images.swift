import AppKit

struct BlockInputImageContext: Equatable {
    let blockID: BlockInputBlockID
    let selectedRange: NSRange
    let sourceText: String
    let anchorWindowRect: NSRect
}

private struct BlockInputImageDeletionContext {
    let blockID: BlockInputBlockID
    let index: Int?
}

extension BlockInputView {
    func imageContextMenuItems(blockID: BlockInputBlockID, selectedRange: NSRange, event: NSEvent) -> [NSMenuItem] {
        guard isEditable else {
            return []
        }
        guard let block = block(withID: blockID) else {
            return []
        }
        if case .image = block.kind {
            let deleteItem = NSMenuItem(title: "Delete Image", action: #selector(blockInputDeleteImageFromMenu(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = BlockInputImageDeletionContext(
                blockID: blockID,
                index: indexPathForContextEvent(event)?.item
            )
            return [deleteItem]
        }
        guard let context = imageContext(blockID: blockID, selectedRange: selectedRange, event: event) else {
            return []
        }
        let insertItem = NSMenuItem(title: "Insert Image", action: #selector(blockInputInsertImageFromMenu(_:)), keyEquivalent: "")
        insertItem.target = self
        insertItem.representedObject = context
        return [insertItem]
    }

    @objc(blockInputInsertImageFromMenu:)
    func blockInputInsertImageFromMenu(_ sender: Any?) {
        guard let context = (sender as? NSMenuItem)?.representedObject as? BlockInputImageContext else {
            return
        }
        _ = performCommand(.insertImage(BlockInputInsertImageCommand(presentation: .modal)), context: .init(imageContext: context))
    }

    @objc(blockInputDeleteImageFromMenu:)
    func blockInputDeleteImageFromMenu(_ sender: Any?) {
        guard let context = (sender as? NSMenuItem)?.representedObject as? BlockInputImageDeletionContext else {
            return
        }
        _ = performCommand(
            .deleteImage,
            context: .init(imageBlockID: context.blockID, imageIndex: context.index)
        )
    }

    func showImageModal(
        context: BlockInputImageContext,
        source: String? = nil,
        altText: String? = nil
    ) {
        guard isEditable else {
            return
        }
        performEditorInteractionUIChanges {
            dismissLinkModal(restoreFocus: false)
            dismissCompletionPopup()
            let modal = imageModalView ?? BlockInputImageModalView()
            modal.configure(urlString: source ?? "", altText: altText ?? "")
            configureImageModalActions(modal, context: context)
            imageModalView = modal
            imageModalContext = context
            hostMutationModal(modal, kind: .image, anchoredTo: context.anchorWindowRect, minimumSize: NSSize(width: 300, height: 148))
            modal.focusInitialField()
        }
    }

    func dismissImageModal(restoreFocus: Bool) {
        let context = imageModalContext
        imageModalView?.removeFromSuperview()
        imageModalView = nil
        imageModalContext = nil
        publishEditorInteractionUIChangeIfNeeded()
        guard restoreFocus,
              let context else {
            return
        }
        focus(blockID: context.blockID, utf16Offset: context.selectedRange.location)
    }

    func imageModalContainsCurrentResponder() -> Bool {
        guard let responder = window?.firstResponder,
              let modal = imageModalView else {
            return false
        }
        return modal.containsResponder(responder)
    }

    @discardableResult
    func insertImage(_ image: BlockInputImage, context: BlockInputImageContext) -> BlockInputSelection? {
        guard isEditable else {
            return nil
        }
        guard let index = index(of: context.blockID),
              let block = block(at: index),
              block.text == context.sourceText else {
            return nil
        }
        if imagePresentation.usesTextLinks {
            return insertImageText(image, block: block, index: index, selectedRange: context.selectedRange)
        }
        if !block.kind.supportsImageSyntaxSplitting {
            return insertImageBlocks([BlockInputBlock(kind: .image(image))], at: index + 1)
        }
        return splitBlockAndInsertImage(image, block: block, index: index, selectedRange: context.selectedRange)
    }

    @discardableResult
    func insertImageFileURLs(_ fileURLs: [URL], below blockID: BlockInputBlockID) -> BlockInputSelection? {
        guard isEditable else {
            return nil
        }
        if imagePresentation.usesTextLinks {
            let textBlocks = fileURLs.compactMap(Self.imageTextBlock(for:))
            guard !textBlocks.isEmpty,
                  let index = index(of: blockID) else {
                return nil
            }
            return insertImageTextBlocks(textBlocks, at: index + 1)
        }
        let imageBlocks = fileURLs.compactMap(Self.imageBlock(for:))
        guard !imageBlocks.isEmpty,
              let index = index(of: blockID) else {
            return nil
        }
        return insertImageBlocks(imageBlocks, at: index + 1)
    }

    @discardableResult
    func insertImageReferences(_ references: [BlockInputFileDropReference], below blockID: BlockInputBlockID) -> BlockInputSelection? {
        guard isEditable else {
            return nil
        }
        if imagePresentation.usesTextLinks {
            let textBlocks = references.compactMap { reference -> BlockInputBlock? in
                guard reference.kind == .image else {
                    return nil
                }
                return Self.imageTextBlock(for: reference)
            }
            guard !textBlocks.isEmpty,
                  let index = index(of: blockID) else {
                return nil
            }
            return insertImageTextBlocks(textBlocks, at: index + 1)
        }
        let imageBlocks = references.compactMap { reference -> BlockInputBlock? in
            guard reference.kind == .image else {
                return nil
            }
            return Self.block(for: reference)
        }
        guard !imageBlocks.isEmpty,
              let index = index(of: blockID) else {
            return nil
        }
        return insertImageBlocks(imageBlocks, at: index + 1)
    }

    static func imageBlock(for url: URL) -> BlockInputBlock? {
        guard url.isFileURL,
              imageFileExtensions.contains(url.pathExtension.lowercased()) else {
            return nil
        }
        return BlockInputBlock(kind: .image(BlockInputImage(source: url.absoluteString, altText: url.deletingPathExtension().lastPathComponent)))
    }

    static func imageTextBlock(for url: URL) -> BlockInputBlock? {
        guard let imageBlock = imageBlock(for: url),
              case let .image(image) = imageBlock.kind else {
            return nil
        }
        return BlockInputBlock(text: markdownImageInsertionSource(for: image))
    }

    static func imageTextBlock(for reference: BlockInputFileDropReference) -> BlockInputBlock? {
        guard reference.kind == .image,
              let source = normalizedDropSource(reference.source) else {
            return nil
        }
        return BlockInputBlock(text: markdownImageInsertionSource(for: BlockInputImage(source: source, altText: reference.label)))
    }

    static func markdownImageSource(for image: BlockInputImage) -> String {
        BlockInputMarkdownImporter.markdown(for: image)
    }

    static func markdownImageInsertionSource(for image: BlockInputImage) -> String {
        "\(markdownImageSource(for: image)) "
    }

    private func configureImageModalActions(_ modal: BlockInputImageModalView, context: BlockInputImageContext) {
        modal.onInsert = { [weak self] urlString, altText in
            guard let self,
                  let source = BlockInputImageModalView.validImageURLString(urlString) else {
                return
            }
            _ = insertImage(BlockInputImage(source: source, altText: altText), context: context)
            dismissImageModal(restoreFocus: false)
        }
        modal.onCancel = { [weak self] in
            self?.dismissImageModal(restoreFocus: true)
        }
        modal.onFocusCheck = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard self?.imageModalContainsCurrentResponder() == false else {
                    return
                }
                self?.dismissImageModal(restoreFocus: false)
            }
        }
    }

    func imageContext(blockID: BlockInputBlockID, selectedRange: NSRange, event: NSEvent) -> BlockInputImageContext? {
        guard let block = block(withID: blockID),
              block.kind.supportsImageSyntaxSplitting,
              let item = visibleItem(for: blockID, refreshConfiguration: false) else {
            return nil
        }
        let clickedOffset = item.utf16Offset(atWindowLocation: event.locationInWindow)
        let range = selectedRange.containsOrTouches(clickedOffset)
            ? selectedRange
            : NSRange(location: clickedOffset, length: 0)
        return BlockInputImageContext(
            blockID: blockID,
            selectedRange: clampedRange(range, in: block.text),
            sourceText: block.text,
            anchorWindowRect: item.anchorWindowRect(forUTF16Range: range)
        )
    }

    func imageContextForActiveSelection() -> BlockInputImageContext? {
        guard let blockID = activeBlockID,
              let block = block(withID: blockID),
              block.kind.supportsImageSyntaxSplitting,
              let item = visibleItem(for: blockID, refreshConfiguration: false) else {
            return nil
        }
        let selectedRange: NSRange
        switch selection {
        case let .text(textRange) where textRange.blockID == blockID:
            selectedRange = textRange.range
        case let .cursor(cursor) where cursor.blockID == blockID:
            selectedRange = NSRange(location: cursor.utf16Offset, length: 0)
        default:
            selectedRange = item.currentSelectedRange
        }
        let clampedSelection = clampedRange(selectedRange, in: block.text)
        return BlockInputImageContext(
            blockID: blockID,
            selectedRange: clampedSelection,
            sourceText: block.text,
            anchorWindowRect: item.anchorWindowRect(forUTF16Range: clampedSelection)
        )
    }

    private func splitBlockAndInsertImage(
        _ image: BlockInputImage,
        block: BlockInputBlock,
        index: Int,
        selectedRange: NSRange
    ) -> BlockInputSelection? {
        let range = clampedRange(selectedRange, in: block.text)
        let text = block.text as NSString
        let prefix = text.substring(to: range.location)
        let suffix = text.substring(from: NSMaxRange(range))
        var replacementBlocks: [BlockInputBlock] = []
        if !prefix.isEmpty {
            replacementBlocks.append(textFragmentBlock(id: block.id, kind: block.kind, text: prefix, template: block))
        }
        let imageBlockID = prefix.isEmpty ? block.id : BlockInputBlockID.unique()
        replacementBlocks.append(BlockInputBlock(id: imageBlockID, kind: .image(image)))
        if !suffix.isEmpty {
            replacementBlocks.append(textFragmentBlock(kind: block.kind, text: suffix, template: block))
        }
        return replaceBlock(block, at: index, with: replacementBlocks, actionName: "Insert Image")
    }

    private func insertImageText(
        _ image: BlockInputImage,
        block: BlockInputBlock,
        index: Int,
        selectedRange: NSRange
    ) -> BlockInputSelection? {
        guard block.kind.supportsImageSyntaxSplitting else {
            return insertImageTextBlocks([BlockInputBlock(text: Self.markdownImageInsertionSource(for: image))], at: index + 1)
        }
        let beforeBlock = block
        let beforeSelection = selection
        let range = clampedRange(selectedRange, in: block.text)
        let markdown = Self.markdownImageInsertionSource(for: image, in: block.text, replacing: range)
        let mutableText = NSMutableString(string: block.text)
        mutableText.replaceCharacters(in: range, with: markdown)
        var afterBlock = block
        afterBlock.text = mutableText as String
        let afterSelection = BlockInputSelection.cursor(BlockInputCursor(
            blockID: afterBlock.id,
            utf16Offset: range.location + (markdown as NSString).length
        ))
        guard applyGranularBlockReplacement(afterBlock, at: index, selection: afterSelection) else {
            return nil
        }
        undoController?.registerBlockReplacementStructuralEdit(
            actionName: "Insert Image",
            beforeBlock: beforeBlock,
            afterBlock: afterBlock,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        return afterSelection
    }

    private static func markdownImageInsertionSource(
        for image: BlockInputImage,
        in text: String,
        replacing range: NSRange
    ) -> String {
        var source = markdownImageInsertionSource(for: image)
        if source.hasSuffix(" "),
           isWhitespace(at: NSMaxRange(range), in: text) {
            source.removeLast()
        }
        return source
    }

    private static func isWhitespace(at utf16Offset: Int, in text: String) -> Bool {
        let nsText = text as NSString
        guard utf16Offset >= 0,
              utf16Offset < nsText.length,
              let scalar = UnicodeScalar(Int(nsText.character(at: utf16Offset))) else {
            return false
        }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private func replaceBlock(
        _ beforeBlock: BlockInputBlock,
        at index: Int,
        with replacementBlocks: [BlockInputBlock],
        actionName: String
    ) -> BlockInputSelection? {
        guard let afterBlock = replacementBlocks.first else {
            return nil
        }
        let insertedBlocks = Array(replacementBlocks.dropFirst())
        let beforeSelection = selection
        let insertionIndex = index + 1
        if canSynchronizeCacheForGranularInsertion(insertedBlockCount: insertedBlocks.count) {
            guard replaceCachedBlock(afterBlock, at: index),
                  document.insertBlocks(insertedBlocks, at: insertionIndex) != nil else {
                return nil
            }
        } else {
            markDocumentCacheUnsynchronized()
        }
        let imageBlock = replacementBlocks.first { $0.kind.isImage }
        let afterSelection = imageBlock.map { BlockInputSelection.blocks([$0.id]) }
        syncDocumentStore(.replaceBlock(afterBlock))
        if !insertedBlocks.isEmpty {
            syncDocumentStore(.insertBlocks(insertedBlocks, insertionIndex: insertionIndex))
        }
        applySelection(afterSelection, notify: true)
        undoController?.registerBlockReplacementInsertionStructuralEdit(BlockInputReplaceInsertEdit(
            actionName: actionName,
            beforeBlock: beforeBlock,
            afterBlock: afterBlock,
            insertedBlocks: insertedBlocks,
            insertionIndex: insertionIndex,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        ))
        reloadDataKeepingFocus()
        publishDocumentChange()
        return afterSelection
    }

    private func insertImageBlocks(_ imageBlocks: [BlockInputBlock], at insertionIndex: Int) -> BlockInputSelection? {
        performStructuralEdit(
            named: imageBlocks.count == 1 ? "Insert Image" : "Insert Images",
            storeSyncAction: { _, _, _ in .insertBlocks(imageBlocks, insertionIndex: insertionIndex) },
            edit: { document in
                guard document.insertBlocks(imageBlocks, at: insertionIndex) != nil,
                      let firstImage = imageBlocks.first else {
                    return nil
                }
                return .blocks([firstImage.id])
            }
        )
    }

    private func insertImageTextBlocks(_ textBlocks: [BlockInputBlock], at insertionIndex: Int) -> BlockInputSelection? {
        performStructuralEdit(
            named: textBlocks.count == 1 ? "Insert Image" : "Insert Images",
            storeSyncAction: { _, _, _ in .insertBlocks(textBlocks, insertionIndex: insertionIndex) },
            edit: { document in
                guard document.insertBlocks(textBlocks, at: insertionIndex) != nil,
                      let firstBlock = textBlocks.first else {
                    return nil
                }
                return .cursor(BlockInputCursor(blockID: firstBlock.id, utf16Offset: firstBlock.utf16Length))
            }
        )
    }

    private func indexPathForContextEvent(_ event: NSEvent) -> IndexPath? {
        let collectionLocation = collectionView.convert(event.locationInWindow, from: nil)
        return collectionView.indexPathForItem(at: collectionLocation)
    }

    private func textFragmentBlock(
        id: BlockInputBlockID = .unique(),
        kind: BlockInputBlockKind,
        text: String,
        template: BlockInputBlock
    ) -> BlockInputBlock {
        BlockInputBlock(
            id: id,
            kind: kind,
            text: text,
            indentationLevel: template.indentationLevel,
            lineIndentationLevels: template.lineIndentationLevels
        )
    }

}

private func clampedRange(_ range: NSRange, in text: String) -> NSRange {
    let length = (text as NSString).length
    let location = min(max(range.location, 0), length)
    let end = min(max(NSMaxRange(range), location), length)
    return NSRange(location: location, length: end - location)
}

private let imageFileExtensions: Set<String> = [
    "apng", "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png", "tif", "tiff", "webp"
]
