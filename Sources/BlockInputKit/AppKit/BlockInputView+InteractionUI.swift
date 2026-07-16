import AppKit

extension BlockInputView {
    /// Whether editor-owned completion or mutation UI is currently presented.
    ///
    /// Hosts can use this state to defer app-level interactions while the
    /// completion popup or a link/image modal owns the current editor flow.
    public var hasPresentedEditorInteractionUI: Bool {
        completionSession != nil || linkModalView != nil || imageModalView != nil
    }

    func publishEditorInteractionUIChangeIfNeeded() {
        guard editorInteractionUIChangeDeferralDepth == 0 else {
            return
        }
        let currentState = hasPresentedEditorInteractionUI
        guard currentState != lastEditorInteractionUIState else {
            return
        }
        lastEditorInteractionUIState = currentState
        onEditorInteractionUIChange?(currentState)
    }

    func performEditorInteractionUIChanges(_ changes: () -> Void) {
        editorInteractionUIChangeDeferralDepth += 1
        defer {
            editorInteractionUIChangeDeferralDepth -= 1
            publishEditorInteractionUIChangeIfNeeded()
        }
        changes()
    }
}
