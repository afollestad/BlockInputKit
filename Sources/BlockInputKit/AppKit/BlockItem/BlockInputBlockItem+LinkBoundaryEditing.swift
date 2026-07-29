import AppKit

extension BlockInputBlockItem {
    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        guard isEditable else {
            return false
        }
        guard let blockID else {
            return true
        }
        // NSTextView reports the final selection before textDidChange, so capture
        // the affected pre-edit range here for undo selection restoration.
        selectionBeforeTextChange = affectedCharRange.length == 0
            ? .cursor(BlockInputCursor(blockID: blockID, utf16Offset: affectedCharRange.location))
            : .text(BlockInputTextRange(blockID: blockID, range: affectedCharRange))
        if applyLinkAwareDeletionIfNeeded(
            affectedCharRange: affectedCharRange,
            replacementString: replacementString,
            selectionBefore: selectionBeforeTextChange,
            blockID: blockID
        ) {
            selectionBeforeTextChange = nil
            return false
        }
        return true
    }

    func textView(
        _ textView: NSTextView,
        willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
        toCharacterRange newSelectedCharRange: NSRange
    ) -> NSRange {
        let newSelectedCharRange = clampedInlineImageSelection(
            newSelectedCharRange,
            from: oldSelectedCharRange,
            in: textView
        )
        guard !isConfiguringBlock,
              !isUpdatingBlockSelectionDrag,
              isTrackingBlockSelectionDrag,
              let event = currentBlockSelectionDragEvent() else {
            return newSelectedCharRange
        }
        let blockTextView = textView as? BlockInputTextView
        blockTextView?.rememberBlockSelectionDragRange(newSelectedCharRange)
        guard updateBlockSelectionDrag(with: event, selectedRange: newSelectedCharRange) else {
            return newSelectedCharRange
        }
        return blockTextView?.collapsedBlockSelectionDragNativeRange() ?? oldSelectedCharRange
    }

    func requestLinkBoundaryDeletion(_ direction: BlockInputLinkBoundaryDeletionDirection) -> Bool {
        guard isEditable,
              let blockID else {
            return false
        }
        return delegate?.blockItem(self, blockID: blockID, didRequestLinkBoundaryDeletion: direction) ?? false
    }

    func applyLinkAwareDeletionIfNeeded(
        affectedCharRange: NSRange,
        replacementString: String?,
        selectionBefore: BlockInputSelection?,
        blockID: BlockInputBlockID
    ) -> Bool {
        guard replacementString == "",
              affectedCharRange.length > 0,
              let block = renderedBlock,
              BlockInputBlockItem.supportsInlineMarkdownStyling(block.kind),
              let expandedRange = linkSourceExpandedDeletionRange(affectedCharRange, in: textView.string) else {
            return false
        }
        let updatedText = NSMutableString(string: textView.string)
        updatedText.deleteCharacters(in: expandedRange)
        replaceCurrentTextFromEditorCorrection(
            updatedText as String,
            selectedRange: NSRange(location: expandedRange.location, length: 0)
        )
        delegate?.blockItem(
            self,
            blockID: blockID,
            didChangeText: textView.string,
            selectionBefore: selectionBefore
        )
        return true
    }

    private func linkSourceExpandedDeletionRange(_ affectedRange: NSRange, in text: String) -> NSRange? {
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        let overlappingLinks = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: inlineCodeRanges,
            fileBaseURL: fileBaseURL
        )
            .filter { range in
                switch range.style {
                case .link:
                    guard range.fullRange.intersectionLength(with: affectedRange) > 0 else {
                        return false
                    }
                    // Edits wholly inside the visible label are normal text edits; only expand deletions crossing hidden source.
                    return affectedRange.location < range.contentRange.location ||
                        NSMaxRange(affectedRange) > NSMaxRange(range.contentRange)
                case .inlineImage:
                    // Images have no editable interior, so any intersecting deletion removes the whole span.
                    return range.fullRange.intersectionLength(with: affectedRange) > 0
                case .bold, .italic, .underline, .strikethrough, .rawSlashCommand, .rawFileMention:
                    return false
                }
            }
        guard !overlappingLinks.isEmpty else {
            return nil
        }
        let location = min(affectedRange.location, overlappingLinks.map(\.fullRange.location).min() ?? affectedRange.location)
        let upperBound = max(NSMaxRange(affectedRange), overlappingLinks.map { NSMaxRange($0.fullRange) }.max() ?? NSMaxRange(affectedRange))
        let expandedRange = NSRange(location: location, length: upperBound - location)
        return expandedRange == affectedRange ? nil : expandedRange
    }

    /// Clamps a caret landing strictly inside an inline image's hidden source to the
    /// nearest span edge; typing there would silently break the image syntax.
    func clampedInlineImageSelection(
        _ proposedRange: NSRange,
        from previousRange: NSRange,
        in textView: NSTextView
    ) -> NSRange {
        guard proposedRange.length == 0,
              !isConfiguringBlock,
              let blockTextView = textView as? BlockInputTextView,
              blockTextView.rendersInlineImages,
              textView.string.containsInlineImageCandidate else {
            return proposedRange
        }
        let direction: BlockInputHorizontalMovementDirection = proposedRange.location >= previousRange.location
            ? .rightward
            : .leftward
        guard let clampedOffset = blockTextView.inlineLinkNavigation().clampedInlineImageCaretOffset(
            proposedRange.location,
            direction: direction
        ) else {
            return proposedRange
        }
        return NSRange(location: clampedOffset, length: 0)
    }
}

extension String {
    /// Cheap prefilter so selection changes only pay for inline-image parsing
    /// when the text can actually contain one.
    var containsInlineImageCandidate: Bool {
        contains("![") || range(of: "<img", options: .caseInsensitive) != nil
    }
}
