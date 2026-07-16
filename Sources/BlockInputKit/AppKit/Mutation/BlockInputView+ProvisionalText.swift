import AppKit

/// Opaque identity for one host-driven provisional text replacement.
public struct BlockInputProvisionalTextSession: Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Result of attempting to begin a provisional text replacement.
public enum BlockInputProvisionalTextBeginResult: Equatable, Sendable {
    /// The transaction began and may receive cumulative text updates.
    case started(BlockInputProvisionalTextSession)
    /// The editor cannot begin a transaction for the supplied reason.
    case unavailable(BlockInputProvisionalTextUnavailable)
}

/// Reasons a provisional text replacement cannot begin.
public enum BlockInputProvisionalTextUnavailable: Error, Equatable, Sendable {
    /// The editor is not attached to a window.
    case editorNotMounted
    /// The editor is configured as read-only.
    case editorReadOnly
    /// Another provisional replacement is already active.
    case sessionAlreadyActive
    /// An editor-owned link or image mutation modal is visible.
    case mutationUIVisible
    /// The current block or text selection cannot be replaced provisionally.
    case unsupportedSelection
    /// The target block is no longer loaded.
    case targetBlockUnavailable
    /// The target block does not expose directly editable source text.
    case unsupportedBlockKind
    /// The target UTF-16 range is outside the current block text.
    case invalidSelectionRange
    /// No loaded text-editable block can provide a fallback caret.
    case noEditableTextBlock
}

/// Result of applying one cumulative provisional text update.
public enum BlockInputProvisionalTextUpdateResult: Equatable, Sendable {
    /// The target block and selection were updated.
    case applied
    /// The supplied cumulative text already matches the current update.
    case unchanged
    /// The token or its snapshotted target is no longer valid.
    case invalidated
}

/// How an active provisional replacement should finish.
public enum BlockInputProvisionalTextDisposition: Equatable, Sendable {
    /// Keep the latest text and register one text-edit undo operation.
    case commit
    /// Restore the original block and selection without registering undo history.
    case cancel
}

/// Result of finishing a provisional text replacement.
public enum BlockInputProvisionalTextFinishResult: Equatable, Sendable {
    /// The latest text was committed and one text-edit undo operation was registered.
    case committed
    /// The original block and selection were restored without adding undo history.
    case cancelled
    /// The transaction finished without changing the original block.
    case unchanged
    /// The token or its snapshotted target was no longer valid.
    case invalidated
}

extension BlockInputView {
    /// Begins a single-block provisional replacement at the current cursor or text selection.
    public func beginProvisionalTextReplacement() -> BlockInputProvisionalTextBeginResult {
        guard window != nil else {
            return .unavailable(.editorNotMounted)
        }
        guard isEditable else {
            return .unavailable(.editorReadOnly)
        }
        guard provisionalTextReplacementState == nil else {
            return .unavailable(.sessionAlreadyActive)
        }
        guard linkModalView == nil, imageModalView == nil else {
            return .unavailable(.mutationUIVisible)
        }

        commitMarkedTextForProvisionalReplacementIfNeeded()
        dismissCompletionPopup()

        let originalSelection = selection
        guard let target = provisionalTextTarget() else {
            return .unavailable(provisionalTextTargetUnavailableReason())
        }
        guard target.range.location >= 0,
              target.range.length >= 0,
              target.range.location <= target.block.utf16Length,
              target.range.length <= target.block.utf16Length - target.range.location else {
            return .unavailable(.invalidSelectionRange)
        }

        let resolvedSelection = provisionalTextSelection(
            blockID: target.block.id,
            range: target.range
        )
        let session = BlockInputProvisionalTextSession()
        provisionalTextReplacementState = ProvisionalTextReplacementState(
            session: session,
            documentStoreIdentity: documentStore.map { ObjectIdentifier($0 as AnyObject) },
            originalBlock: target.block,
            originalRange: target.range,
            originalSelection: originalSelection,
            expectedBlock: target.block,
            latestSelection: resolvedSelection
        )
        if originalSelection == nil,
           !establishProvisionalFallbackSelection(
               resolvedSelection,
               originalSelection: originalSelection,
               session: session
           ) {
            return .unavailable(.targetBlockUnavailable)
        }
        return .started(session)
    }

    /// Replaces the snapshotted range with cumulative provisional text.
    public func updateProvisionalTextReplacement(
        _ session: BlockInputProvisionalTextSession,
        text: String
    ) -> BlockInputProvisionalTextUpdateResult {
        guard var state = validProvisionalTextReplacementState(for: session) else {
            return .invalidated
        }
        let originalText = state.originalBlock.text as NSString
        let updatedText = originalText.replacingCharacters(in: state.originalRange, with: text)
        var replacement = state.originalBlock
        let updatedIndentation = state.originalBlock.lineIndentationLevelsAfterReplacingText(
            utf16Offset: state.originalRange.location,
            selectedUTF16Length: state.originalRange.length,
            updatedText: updatedText
        )
        replacement.text = updatedText
        if let updatedIndentation {
            replacement.lineIndentationLevels = updatedIndentation
        }
        guard replacement != state.expectedBlock else {
            return .unchanged
        }
        guard let index = index(of: replacement.id) else {
            invalidateProvisionalTextReplacement()
            return .invalidated
        }

        let insertedLength = (text as NSString).length
        let afterSelection: BlockInputSelection = .cursor(BlockInputCursor(
            blockID: replacement.id,
            utf16Offset: state.originalRange.location + insertedLength
        ))
        state.expectedBlock = replacement
        state.latestSelection = afterSelection
        provisionalTextReplacementState = state
        guard applyGranularBlockReplacement(
            replacement,
            at: index,
            selection: afterSelection,
            authorizedProvisionalSession: session
        ) else {
            invalidateProvisionalTextReplacement()
            return .invalidated
        }
        return .applied
    }

    /// Commits or cancels an active provisional text replacement.
    public func finishProvisionalTextReplacement(
        _ session: BlockInputProvisionalTextSession,
        disposition: BlockInputProvisionalTextDisposition
    ) -> BlockInputProvisionalTextFinishResult {
        guard var state = validProvisionalTextReplacementState(for: session) else {
            return .invalidated
        }
        switch disposition {
        case .commit:
            provisionalTextReplacementState = nil
            guard state.expectedBlock != state.originalBlock else {
                return .unchanged
            }
            undoController?.registerTextEdit(
                blockID: state.originalBlock.id,
                beforeText: state.originalBlock.text,
                afterText: state.expectedBlock.text,
                beforeLineIndentationLevels: state.originalBlock.lineIndentationLevels,
                afterLineIndentationLevels: state.expectedBlock.lineIndentationLevels,
                selectionBefore: state.originalSelection,
                selectionAfter: state.latestSelection
            )
            return .committed
        case .cancel:
            guard let index = index(of: state.originalBlock.id) else {
                invalidateProvisionalTextReplacement()
                return .invalidated
            }
            state.expectedBlock = state.originalBlock
            state.latestSelection = state.originalSelection
            provisionalTextReplacementState = state
            guard applyGranularBlockReplacement(
                state.originalBlock,
                at: index,
                selection: state.originalSelection,
                authorizedProvisionalSession: session
            ) else {
                invalidateProvisionalTextReplacement()
                return .invalidated
            }
            provisionalTextReplacementState = nil
            restoreNativeStateAfterProvisionalCancellation(originalSelection: state.originalSelection)
            return .cancelled
        }
    }
}

extension BlockInputView {
    func isActiveProvisionalTextSession(_ session: BlockInputProvisionalTextSession?) -> Bool {
        guard let session else {
            return false
        }
        return provisionalTextReplacementState?.session == session
    }

    func canContinueProvisionalTextMutation(
        _ session: BlockInputProvisionalTextSession,
        expectedBlock: BlockInputBlock
    ) -> Bool {
        guard let state = provisionalTextReplacementState,
              state.session == session,
              currentDocumentStoreIdentity == state.documentStoreIdentity else {
            if provisionalTextReplacementState?.session == session {
                invalidateProvisionalTextReplacement()
            }
            return false
        }
        guard documentStore == nil || block(withID: expectedBlock.id) == expectedBlock else {
            invalidateProvisionalTextReplacement()
            return false
        }
        return true
    }

    func presentGranularBlockReplacement(
        _ block: BlockInputBlock,
        at index: Int,
        authorizedProvisionalSession: BlockInputProvisionalTextSession?
    ) -> Bool {
        // Image dimensions can resolve or undo after mounting; refresh flow metrics so scroll bounds include the full block height.
        if reconfigureVisibleReplacement(
            block,
            at: index,
            requiresDeferredLayout: false,
            invalidatesLayoutMetrics: block.kind.isImage
        ) {
            guard canContinueAuthorizedProvisionalReplacement(
                authorizedProvisionalSession,
                expectedBlock: block
            ) else {
                return false
            }
            publishDocumentChange()
            guard canContinueAuthorizedProvisionalReplacement(
                authorizedProvisionalSession,
                expectedBlock: block
            ) else {
                return false
            }
            invalidatePreferredHeight()
            return true
        }
        collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        guard canContinueAuthorizedProvisionalReplacement(
            authorizedProvisionalSession,
            expectedBlock: block
        ) else {
            return false
        }
        collectionView.layoutSubtreeIfNeeded()
        restoreMountedSelection()
        guard canContinueAuthorizedProvisionalReplacement(
            authorizedProvisionalSession,
            expectedBlock: block
        ) else {
            return false
        }
        publishDocumentChange()
        guard canContinueAuthorizedProvisionalReplacement(
            authorizedProvisionalSession,
            expectedBlock: block
        ) else {
            return false
        }
        invalidatePreferredHeight()
        return true
    }

    func canContinueAuthorizedProvisionalReplacement(
        _ session: BlockInputProvisionalTextSession?,
        expectedBlock: BlockInputBlock
    ) -> Bool {
        guard let session else { return true }
        return canContinueProvisionalTextMutation(session, expectedBlock: expectedBlock)
    }

    func invalidateProvisionalTextReplacement() {
        provisionalTextReplacementState = nil
    }

    func reconcileProvisionalTextReplacementBeforeConfiguration(
        documentStore configuredDocumentStore: (any BlockInputDocumentStore)?
    ) {
        guard let state = provisionalTextReplacementState else {
            return
        }
        let configuredIdentity = configuredDocumentStore.map { ObjectIdentifier($0 as AnyObject) }
        if configuredIdentity != state.documentStoreIdentity {
            invalidateProvisionalTextReplacement()
        }
    }

    func reconcileProvisionalTextReplacementAfterConfiguration() {
        validateExpectedProvisionalTextBlock()
    }

    func reconcileProvisionalTextReplacementAfterStoreChange(_ change: BlockInputDocumentStoreChange) {
        guard case .replacedDocument = change else {
            return
        }
        validateExpectedProvisionalTextBlock()
    }

    private func validProvisionalTextReplacementState(
        for session: BlockInputProvisionalTextSession
    ) -> ProvisionalTextReplacementState? {
        guard let state = provisionalTextReplacementState,
              state.session == session,
              currentDocumentStoreIdentity == state.documentStoreIdentity,
              block(withID: state.originalBlock.id) == state.expectedBlock else {
            if provisionalTextReplacementState?.session == session {
                invalidateProvisionalTextReplacement()
            }
            return nil
        }
        return state
    }

    private func validateExpectedProvisionalTextBlock() {
        guard let state = provisionalTextReplacementState else {
            return
        }
        guard currentDocumentStoreIdentity == state.documentStoreIdentity,
              block(withID: state.originalBlock.id) == state.expectedBlock else {
            invalidateProvisionalTextReplacement()
            return
        }
    }

    private var currentDocumentStoreIdentity: ObjectIdentifier? {
        documentStore.map { ObjectIdentifier($0 as AnyObject) }
    }

    private func provisionalTextTarget() -> (block: BlockInputBlock, range: NSRange)? {
        switch selection {
        case let .cursor(cursor):
            guard let block = block(withID: cursor.blockID),
                  block.kind.supportsProvisionalTextReplacement else {
                return nil
            }
            return (block, NSRange(location: cursor.utf16Offset, length: 0))
        case let .text(textRange):
            guard let block = block(withID: textRange.blockID),
                  block.kind.supportsProvisionalTextReplacement else {
                return nil
            }
            return (block, textRange.range)
        case .blocks, .mixed:
            return nil
        case nil:
            return provisionalTextFallbackTarget()
        }
    }

    private func provisionalTextFallbackTarget() -> (block: BlockInputBlock, range: NSRange)? {
        if let lastFocusedBlockID,
           let block = block(withID: lastFocusedBlockID),
           block.kind.supportsProvisionalTextReplacement {
            return (block, NSRange(location: block.utf16Length, length: 0))
        }
        for index in stride(from: blockCount - 1, through: 0, by: -1) {
            if let block = block(at: index), block.kind.supportsProvisionalTextReplacement {
                return (block, NSRange(location: block.utf16Length, length: 0))
            }
        }
        return nil
    }

    private func provisionalTextTargetUnavailableReason() -> BlockInputProvisionalTextUnavailable {
        switch selection {
        case let .cursor(cursor):
            guard let block = block(withID: cursor.blockID) else {
                return .targetBlockUnavailable
            }
            return block.kind.supportsProvisionalTextReplacement ? .invalidSelectionRange : .unsupportedBlockKind
        case let .text(range):
            guard let block = block(withID: range.blockID) else {
                return .targetBlockUnavailable
            }
            return block.kind.supportsProvisionalTextReplacement ? .invalidSelectionRange : .unsupportedBlockKind
        case .blocks, .mixed:
            return .unsupportedSelection
        case nil:
            return .noEditableTextBlock
        }
    }

    private func provisionalTextSelection(
        blockID: BlockInputBlockID,
        range: NSRange
    ) -> BlockInputSelection {
        if range.length == 0 {
            return .cursor(BlockInputCursor(blockID: blockID, utf16Offset: range.location))
        }
        return .text(BlockInputTextRange(blockID: blockID, range: range))
    }

    private func commitMarkedTextForProvisionalReplacementIfNeeded() {
        guard let textView = window?.firstResponder as? BlockInputTextView,
              isEditorFirstResponder,
              textView.hasMarkedText() else {
            return
        }
        textView.unmarkText()
    }

    private func restoreNativeStateAfterProvisionalCancellation(originalSelection: BlockInputSelection?) {
        guard originalSelection == nil, isEditorFirstResponder else {
            return
        }
        _ = resignEditorFocus()
    }

    private func establishProvisionalFallbackSelection(
        _ resolvedSelection: BlockInputSelection,
        originalSelection: BlockInputSelection?,
        session: BlockInputProvisionalTextSession
    ) -> Bool {
        applySelection(resolvedSelection, notify: true)
        guard validProvisionalTextReplacementState(for: session) != nil else {
            restoreSelectionAfterUnavailableFallback(originalSelection)
            return false
        }
        restoreMountedSelection()
        guard validProvisionalTextReplacementState(for: session) != nil else {
            restoreSelectionAfterUnavailableFallback(originalSelection)
            return false
        }
        return true
    }

    private func restoreSelectionAfterUnavailableFallback(_ originalSelection: BlockInputSelection?) {
        applySelection(originalSelection, notify: false)
        restoreNativeStateAfterProvisionalCancellation(originalSelection: originalSelection)
    }
}

struct ProvisionalTextReplacementState {
    var session: BlockInputProvisionalTextSession
    var documentStoreIdentity: ObjectIdentifier?
    var originalBlock: BlockInputBlock
    var originalRange: NSRange
    var originalSelection: BlockInputSelection?
    var expectedBlock: BlockInputBlock
    var latestSelection: BlockInputSelection?
}

private extension BlockInputBlockKind {
    var supportsProvisionalTextReplacement: Bool {
        switch self {
        case .horizontalRule, .table, .image:
            return false
        case .paragraph, .heading, .code, .frontMatter, .quote,
             .bulletedListItem, .numberedListItem, .checklistItem, .rawMarkdown:
            return true
        }
    }
}
