import AppKit

/// Vertical-only editor scroll owner. Nested block views may scroll horizontally, but the document clip view must not.
final class BlockInputDocumentScrollView: NSScrollView {
    var onContentBoundsDidChange: (() -> Void)?
    weak var blockInputView: BlockInputView?

    // Editor chrome can sit behind the scroll stack, so cached rendering must preserve transparency.
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureBoundsObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureBoundsObservation()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureBoundsObservation() {
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        blockInputView?.addEditableSurfaceCursorRectIfNeeded(to: self)
        blockInputView?.addDisabledCursorRectIfNeeded(to: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        blockInputView?.isEditable == true
    }

    override func cursorUpdate(with event: NSEvent) {
        guard blockInputView?.isEditable == true else {
            super.cursorUpdate(with: event)
            return
        }
        NSCursor.iBeam.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard blockInputView?.focusEditorFromEditableSurfaceClick() != true else {
            return
        }
        super.mouseDown(with: event)
    }

    override func layout() {
        super.layout()
        blockInputView?.updateCollectionViewWidthForVisibleBounds()
        blockInputView?.clampVerticalScrollOffsetIfNeeded()
    }

    @objc
    private func contentBoundsDidChange() {
        defer {
            onContentBoundsDidChange?()
        }
        guard contentView.bounds.origin.x != 0 else {
            return
        }
        contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.origin.y))
        reflectScrolledClipView(contentView)
    }
}
