import AppKit

extension BlockInputView {
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            invalidateProvisionalTextReplacement()
            dismissCompletionPopup()
            dismissLinkModal(restoreFocus: false)
            dismissImageModal(restoreFocus: false)
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            return
        }
        invalidateVisibleCursorRects()
        if wantsFocusOnWindowAttach {
            // Deferred one tick so the attach's initial layout pass finishes
            // first — claiming mid-attach churns collection view constraints.
            // The flag is re-checked because a resign in between cancels the claim.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.wantsFocusOnWindowAttach, self.window != nil else {
                    return
                }
                self.wantsFocusOnWindowAttach = false
                self.focusEditor()
            }
        }
    }

    func hostMutationModal(
        _ modal: NSView,
        kind: BlockInputModalKind,
        anchoredTo windowRect: NSRect,
        minimumSize: NSSize
    ) {
        let overlay = mutationModalOverlay(
            kind: kind,
            anchoredTo: windowRect,
            minimumSize: minimumSize,
            fittingSize: modal.fittingSize == .zero ? modal.frame.size : modal.fittingSize
        )
        modal.appearance = effectiveAppearance
        if modal.superview !== overlay.container || overlay.container.subviews.last !== modal {
            modal.removeFromSuperview()
            overlay.container.addSubview(modal, positioned: .above, relativeTo: nil)
        }
        modal.frame = overlay.frame
    }

    func refreshMutationModalPresentation() {
        if let modal = linkModalView,
           let context = linkModalContext {
            hostMutationModal(
                modal,
                kind: .link,
                anchoredTo: context.anchorWindowRect,
                minimumSize: NSSize(width: 300, height: 148)
            )
        }
        if let modal = imageModalView,
           let context = imageModalContext {
            hostMutationModal(
                modal,
                kind: .image,
                anchoredTo: context.anchorWindowRect,
                minimumSize: NSSize(width: 300, height: 148)
            )
        }
    }

    private func mutationModalOverlay(
        kind: BlockInputModalKind,
        anchoredTo windowRect: NSRect,
        minimumSize: NSSize,
        fittingSize: NSSize
    ) -> BlockInputModalOverlay {
        let size = NSSize(width: max(fittingSize.width, minimumSize.width), height: max(fittingSize.height, minimumSize.height))
        let baseContext = BlockInputModalOverlayContext(
            editorView: self,
            kind: kind,
            defaultContainer: self,
            defaultFrame: .zero,
            modalSize: size,
            anchorWindowRect: windowRect
        )
        let defaultFrame = baseContext.modalFrame(in: self)
        let context = BlockInputModalOverlayContext(
            editorView: self,
            kind: kind,
            defaultContainer: self,
            defaultFrame: defaultFrame,
            modalSize: size,
            anchorWindowRect: windowRect
        )
        let defaultOverlay = BlockInputModalOverlay(container: self, frame: defaultFrame)
        return modalOverlayProvider?(context) ?? defaultOverlay
    }
}
