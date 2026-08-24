import AppKit

/// Collection view hook that preserves editor-owned drag state and first-click inline link routing.
final class BlockInputCollectionView: NSCollectionView {
    weak var blockInputView: BlockInputView?
    private weak var blockSelectionDragItem: BlockInputBlockItem?

    // Editor chrome can sit behind the collection stack, so cached rendering must preserve transparency.
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        blockInputView?.updateVisibleItemWidthsForCurrentWidth()
        blockInputView?.scheduleProgressivePreloadCheck()
        blockInputView?.updatePlaceholderLayout()
        // A content shrink with no host resize reaches neither of the scroll view's own hooks, so
        // hand the frame write to the scroll view rather than mutating our own frame mid-layout.
        if blockInputView?.hasStaleDocumentHeight == true {
            enclosingScrollView?.needsLayout = true
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        guard let event else {
            return false
        }
        return blockInputView?.isEditable == true || blockInputView?.linkClickTarget(for: event) != nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        blockInputView?.addEditableSurfaceCursorRectIfNeeded(to: self)
        blockInputView?.addDisabledCursorRectIfNeeded(to: self)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard blockInputView?.isEditable == true else {
            super.cursorUpdate(with: event)
            return
        }
        NSCursor.iBeam.set()
    }

    override func mouseDown(with event: NSEvent) {
        if let target = blockInputView?.linkClickTarget(for: event) {
            target.item.textView.mouseDown(with: event)
            return
        }
        blockSelectionDragItem = itemForBlockSelectionDrag(at: event.locationInWindow)
        guard blockSelectionDragItem != nil else {
            guard blockInputView?.focusEditorFromEditableSurfaceClick() == true else {
                super.mouseDown(with: event)
                return
            }
            return
        }
        blockSelectionDragItem?.beginBlockSelectionDrag()
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let blockSelectionDragItem,
              blockSelectionDragItem.updateBlockSelectionDrag(with: event) else {
            super.mouseDragged(with: event)
            return
        }
    }

    override func mouseUp(with event: NSEvent) {
        blockSelectionDragItem?.finishBlockSelectionDrag()
        blockSelectionDragItem = nil
        super.mouseUp(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let blockInputView else {
            return menu.items.isEmpty ? nil : menu
        }
        menu.blockInputPrependingTextFormattingItems(
            blockInputView.textFormattingContextMenuItemStates(for: event).map {
                $0.action.menuItem(target: blockInputView, state: $0.state)
            }
        )
        menu.blockInputPrependingLinkItems(blockInputView.linkContextMenuItems(for: event))
        return menu.items.isEmpty ? nil : menu
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        blockInputView?.hideDropIndicator()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        super.draggingEnded(sender)
        blockInputView?.hideDropIndicator()
    }

    private func itemForBlockSelectionDrag(at windowLocation: NSPoint) -> BlockInputBlockItem? {
        let location = convert(windowLocation, from: nil)
        guard let indexPath = indexPathForItem(at: location),
              let item = item(at: indexPath) as? BlockInputBlockItem else {
            return nil
        }
        return item
    }
}
