import AppKit

extension BlockInputTextView {
    /// Keeps plain left/right movement aligned with the visible link/chip boundary, not hidden Markdown source bytes.
    func handleLinkBoundaryMovementCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(moveLeft(_:)):
            return moveAcrossHiddenLinkBoundary(.leftward)
        case #selector(moveRight(_:)):
            return moveAcrossHiddenLinkBoundary(.rightward)
        default:
            return false
        }
    }

    func handleLinkBoundaryMovementShortcut(_ event: NSEvent) -> Bool {
        guard let direction = event.plainHorizontalMovementDirection else {
            return false
        }
        return moveAcrossHiddenLinkBoundary(direction)
    }

    private func moveAcrossHiddenLinkBoundary(_ direction: BlockInputHorizontalMovementDirection) -> Bool {
        let selectedRange = selectedRange()
        guard selectedRange.length == 0,
              supportsInlineLinkNavigation,
              let target = inlineLinkNavigation().characterBoundaryTarget(
                from: selectedRange.location,
                direction: direction
              ) else {
            return false
        }
        setSelectedRanges([NSValue(range: target.range)], affinity: target.affinity, stillSelecting: false)
        scrollRangeToVisible(target.range)
        blockItem?.updateSelectionDependentAttributesForCurrentSelection()
        return true
    }

    func moveWordAcrossInlineLinkSource(_ direction: BlockInputWordMovementDirection) -> Bool {
        let selectedRange = selectedRange()
        guard selectedRange.length == 0,
              supportsInlineLinkNavigation,
              let target = inlineLinkNavigation().wordBoundaryTarget(
                from: selectedRange.location,
                direction: direction
              ) else {
            return false
        }
        setSelectedRange(target.range)
        scrollRangeToVisible(target.range)
        blockItem?.updateSelectionDependentAttributesForCurrentSelection()
        return true
    }

    func modifyWordSelectionAcrossInlineLinkSource(
        _ direction: BlockInputWordMovementDirection,
        previousRange: NSRange
    ) -> Bool {
        guard supportsInlineLinkNavigation,
              let target = inlineLinkNavigation().wordBoundaryTarget(
                from: previousRange.activeWordSelectionOffset(for: direction),
                direction: direction
              ) else {
            return false
        }
        let anchor = previousRange.wordSelectionAnchor(for: direction)
        let range = NSRange(
            location: min(anchor, target.range.location),
            length: abs(target.range.location - anchor)
        )
        setSelectedRange(range)
        scrollRangeToVisible(range)
        if blockItem?.isTableCellTextView(self) != true {
            requestWordSelectionAdjustmentFromOwningBlock(
                direction,
                previousSelectedRange: previousRange,
                selectedRange: range
            )
        }
        blockItem?.updateSelectionDependentAttributesForCurrentSelection()
        return true
    }

    func inlineLinkNavigation() -> BlockInputInlineLinkNavigation {
        BlockInputInlineLinkNavigation(
            text: string,
            fileBaseURL: blockItem?.fileBaseURL,
            inlineImages: rendersInlineImages
        )
    }

    private var supportsInlineLinkNavigation: Bool {
        blockItem?.supportsInlineMarkdownLinkRendering(for: self) == true
    }
}
