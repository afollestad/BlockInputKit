import AppKit
import QuartzCore

/// Primary AppKit editor surface for a structured block document.
@MainActor
public final class BlockInputView: NSView {
    /// Current document snapshot cached by the view.
    ///
    /// Store-backed large-document edits may leave this snapshot stale until the
    /// next full refresh; use `BlockInputDocumentStore` callbacks as the source
    /// of truth for large documents.
    public internal(set) var document = BlockInputDocument()
    /// Current block, text, or multi-block selection.
    public internal(set) var selection: BlockInputSelection?
    /// Whether drag reordering is enabled for block items.
    public internal(set) var allowsBlockReordering = true
    /// Whether the editor accepts user-driven drag and drop.
    public internal(set) var allowsDrops = true
    /// Visual horizontal inset used for block content.
    ///
    /// When reordering is enabled, the drag handle is centered inside this inset when possible
    /// and the gutter grows only when the inset is too small for the handle lane.
    public internal(set) var editorHorizontalInset = BlockInputConfiguration.defaultEditorHorizontalInset
    /// Color used for the drag insertion indicator line.
    public internal(set) var dropIndicatorColor = NSColor.controlAccentColor
    /// Subtle text shown when the editor has no meaningful document content.
    public internal(set) var placeholder: String?
    /// Whether editor-owned document mutations are currently enabled.
    public internal(set) var isEditable = true
    /// Cursor shown over non-editable editor surfaces.
    public internal(set) var disabledCursor: NSCursor?
    /// Host hook for visual-only inline hints after the focused caret.
    public internal(set) var inlineHintProvider: BlockInputInlineHintProvider?
    /// Whether raw slash-command tokens render as visual chips.
    public internal(set) var rawSlashCommandChips = false
    /// Whether raw `@`-prefixed file path tokens render as visual chips.
    public internal(set) var rawFileMentionChips = false
    /// Return-key behavior while the editor-owned completion popup is active.
    public internal(set) var completionReturnBehavior = BlockInputCompletionReturnBehavior.acceptHighlightedSuggestion
    /// Visual styling used for text, code, and selection chrome.
    public internal(set) var style = BlockInputStyle.default
    /// Behavior used by editor-owned Cmd+A and select-all commands.
    public internal(set) var selectAllBehavior = BlockInputSelectAllBehavior.focusedContentThenDocument
    /// Multiplier applied to vertical padding inside rendered block rows.
    public internal(set) var blockVerticalInsetMultiplier: CGFloat = 1
    var heightSizing: BlockInputEditorHeightSizing?, lastReportedPreferredHeight: CGFloat?
    var isPreferredHeightCallbackScheduled = false
    var isFlowLayoutShrinkSyncScheduled = false
    var imageLoader: any BlockInputImageLoading = BlockInputDefaultImageLoader()
    var imageDiskCache: (any BlockInputImageDiskCaching)?
    var imageBaseURL: URL?, fileBaseURL: URL?
    var imagePresentation = BlockInputImagePresentation.inlineBlocks
    var allowsRemoteImageLoading = true
    var maximumImageSourceBytes = 20 * 1024 * 1024, maximumImagePixelDimension = 8_192
    var defaultImagePlaceholderAspectRatio: CGFloat = 16.0 / 9.0
    /// Editor-scoped cache for images rendered inline within text lines.
    let inlineImageStore = BlockInputInlineImageStore()

    let scrollView = BlockInputDocumentScrollView()
    let collectionView = BlockInputCollectionView()
    let placeholderLabel = BlockInputPlaceholderLabel(labelWithString: "")
    let editorChromeView = BlockInputEditorChromeView(), editorChromeStrokeOverlayView = BlockInputEditorChromeView()
    let dropIndicatorView = NSView()
    let editorChromeFillLayer = CAShapeLayer()
    let editorChromeStrokeLayer = CAShapeLayer()
    let editorChromeMaskLayer = CAShapeLayer()
    let layout = BlockInputCollectionViewFlowLayout()
    var documentStore: (any BlockInputDocumentStore)?
    var documentStoreObservation: BlockInputDocumentStoreObservation?
    var progressiveLoadTask: Task<Void, Never>?, progressiveLoadBatchLimit = 5_000
    var progressiveStoreError: String?
    var fallbackUndoController = BlockInputUndoController()
    var undoController: BlockInputUndoController?
    var commandDispatcher: BlockInputEditorCommandDispatcher?
    var keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] = [:]
    var isPerformingDefaultKeyboardShortcut = false
    var isIgnoringShortcutDispatch = false
    var ignoredKeyboardShortcutEventIDs: Set<ObjectIdentifier> = []
    var completionProvider: (any BlockInputCompletionProvider)?
    var fileDropHandler: BlockInputFileDropHandler?
    var fileDropTasks: [UUID: Task<Void, Never>] = [:]
    var slashCommandAvailability = BlockInputSlashCommandAvailability.documentStart
    var slashCommandChipClickHandler:
        (@MainActor (BlockInputSlashCommandChipClickContext) -> BlockInputSlashCommandChipClickAction)?
    var completionPopupConfiguration = BlockInputCompletionPopupConfiguration()
    var completionPopupPlacement: BlockInputCompletionPopupPlacement {
        get { completionPopupConfiguration.placement }
        set { completionPopupConfiguration.placement = newValue }
    }
    var onDocumentMutation: ((BlockInputDocumentChange) -> Void)?
    var onDocumentChange: ((BlockInputDocument) -> Void)?
    var documentChangeSnapshotDelay: TimeInterval = 0.25
    var onSelectionChange: ((BlockInputSelection?) -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var onEditorInteractionUIChange: (@MainActor (Bool) -> Void)?
    var lastEditorInteractionUIState = false, editorInteractionUIChangeDeferralDepth = 0
    var provisionalTextReplacementState: ProvisionalTextReplacementState?
    // Large store-backed granular inserts skip updating this duplicate snapshot
    // so repeated Return in 100k-block documents stays on the indexed store path.
    var isDocumentCacheSynchronized = true
    var publishedFocusState = false
    var pendingFocus: BlockInputCursor?
    // A focusEditor() call before window attachment cannot claim first responder
    // (makeFirstResponder is a silent no-op); retried on viewDidMoveToWindow.
    var wantsFocusOnWindowAttach = false
    var lastFocusedBlockID: BlockInputBlockID?
    var selectedHorizontalRuleIndex: Int?
    var preferredNavigationX: CGFloat?
    // Invalidates deferred selection restoration when a later reload should not restore focus.
    var focusRestoreGeneration = 0
    // Avoid re-entering NSWindow first-responder assignment while AppKit is already promoting this view.
    var isBecomingFirstResponder = false
    var documentSnapshotGeneration = 0
    var pendingDocumentSnapshotWorkItem: DispatchWorkItem?
    var pendingProgressivePreloadWorkItem: DispatchWorkItem?
    nonisolated(unsafe) var selectionExpansionKeyMonitor: Any?
    var lastNativeTextSelectionExpansion: BlockInputNativeTextSelectionExpansion?
    var blockSelectionExpansion: BlockInputBlockSelectionExpansion?
    var horizontalSelectionExpansion: BlockInputHorizontalSelectionExpansion?
    var tableKeyboardRowSelection: BlockInputTableKeyboardRowSelection?
    // Configured opener for editor-owned links and Markdown-image preview occurrences.
    var linkURLOpener: BlockInputURLOpener = { NSWorkspace.shared.open($0) }
    // The link modal is editor-owned so it can be anchored to row geometry, clamped inside the editor, and snapshotted.
    var linkModalView: BlockInputLinkModalView?
    // Captured source context for the visible modal; save/remove actions verify it before mutating block text.
    var linkModalContext: BlockInputLinkContext?
    var imageModalView: BlockInputImageModalView?
    var imageModalContext: BlockInputImageContext?
    var modalOverlayProvider: (@MainActor (BlockInputModalOverlayContext) -> BlockInputModalOverlay?)?
    // Local monitors are needed because a child modal view does not receive every outside mouse-down by responder routing.
    nonisolated(unsafe) var linkModalMouseDownMonitor: Any?
    var linkModalRetargetMouseDownWindowLocation: NSPoint?
    var completionSession: BlockInputCompletionSession?
    var completionRequestTask: Task<Void, Never>?
    var completionPopupView: BlockInputCompletionPopupView?
    let completionPopupEventCaptureView = BlockInputCompletionEventCaptureView()
    nonisolated(unsafe) var completionPopupMouseDownMonitor: Any?
    var completionPopupConsumesNextMouseUp = false

    /// Reapplies appearance-dependent surface colors when AppKit changes the effective appearance.
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyEditorSurfaceStyle()
        collectionView.visibleItems().forEach { item in
            (item as? BlockInputLoadingItem)?.applySurfaceStyle(style.editorSurface)
        }
    }

    /// Creates an editor view and installs its collection-view-backed editing surface.
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupCollectionView()
        configureInlineImageStoreCallback()
    }

    /// Creates an editor view from a coder and installs its collection-view-backed editing surface.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCollectionView()
        configureInlineImageStoreCallback()
    }

    deinit {
        progressiveLoadTask?.cancel()
        completionRequestTask?.cancel()
        for task in fileDropTasks.values {
            task.cancel()
        }
        documentStoreObservation?.cancel()
        removeNonisolatedEventMonitors()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
    }

    /// Returns whether the editor can become the first responder.
    public override var acceptsFirstResponder: Bool { true }

    public override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        updateEditorChromeLayers()
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        addDisabledCursorRectIfNeeded(to: self)
    }

    /// Promotes editor focus and restores focus to the active block item when possible.
    public override func becomeFirstResponder() -> Bool {
        isBecomingFirstResponder = true
        defer { isBecomingFirstResponder = false }
        focusEditor()
        publishFocusChange(true)
        return true
    }

    /// Publishes focus loss when AppKit removes first-responder status from the editor.
    public override func resignFirstResponder() -> Bool {
        if !isBecomingFirstResponder {
            publishFocusLossIfNeeded()
        }
        return true
    }

    /// Handles editor-owned key events before forwarding unhandled events to AppKit.
    public override func keyDown(with event: NSEvent) {
        if modalContainsCurrentResponder { super.keyDown(with: event); return }
        switch dispatchKeyboardShortcut(event: event) {
        case .handled:
            return
        case .ignored:
            performKeyboardShortcutContinuationAfterIgnoredEvent(event) {
                performEditorKeyDownDefaults(event)
            }
            return
        case .notRegistered:
            break
        }
        performEditorKeyDownDefaults(event)
    }

    /// Handles selector-based movement and cancellation commands before forwarding unhandled commands to AppKit.
    public override func doCommand(by selector: Selector) {
        if linkModalContainsCurrentResponder() { super.doCommand(by: selector); return }
        if imageModalContainsCurrentResponder() { super.doCommand(by: selector); return }
        if dispatchKeyboardShortcut(selector: selector) == .handled { return }
        if selector == #selector(cancelOperation(_:)), cancelMultiBlockSelection() {
            return
        }
        if selector == #selector(moveUp(_:)), handleMoveUpCommand() { return }
        if selector == #selector(moveDown(_:)), collapseMultiBlockSelection(direction: .downward) { return }
        if handleFocusedTableCellSelectionCommand(selector) { return }
        if handleDocumentBoundaryCommand(selector) || handleLineBoundarySelectionCommand(selector) ||
            handleSelectionExpansionCommand(selector) ||
            handleHorizontalSelectionAdjustmentCommand(selector) ||
            handleWordSelectionAdjustmentCommand(selector) ||
            handleWordMovementCommand(selector) { return }
        super.doCommand(by: selector)
    }

    /// Handles editor keyboard shortcuts before forwarding unhandled key equivalents to AppKit.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if performFocusedModalFieldEditorKeyEquivalent(event) { return true }
        if modalContainsCurrentResponder { return false }
        switch dispatchKeyboardShortcut(event: event) {
        case .handled:
            return true
        case .ignored:
            return performKeyboardShortcutContinuationAfterIgnoredEvent(event) {
                performEditorKeyEquivalentDefaults(event)
            }
        case .notRegistered:
            break
        }
        return performEditorKeyEquivalentDefaults(event)
    }

    /// Selects all editor content or forwards the command to a focused modal field.
    public override func selectAll(_ sender: Any?) {
        if performFocusedModalFieldEditorAction(#selector(NSText.selectAll(_:)), sender: sender) {
            return
        }
        if performCommand(.selectAll) {
            return
        }
        super.selectAll(sender)
    }

    /// Focuses a specific block at a UTF-16 text offset.
    public func focus(blockID: BlockInputBlockID, utf16Offset: Int = 0) {
        refreshDocumentFromStore()
        guard let block = block(withID: blockID) else {
            return
        }
        let cursor = BlockInputCursor(
            blockID: blockID,
            utf16Offset: min(max(utf16Offset, 0), block.cursorUTF16Length)
        )
        pendingFocus = cursor
        applySelection(.cursor(cursor), notify: true)
        focusVisibleItem(for: cursor)
        if isEditorFirstResponder {
            publishFocusChange(true)
        }
    }

    /// Deletes the active block if it is empty, preserving the required focus semantics.
    @discardableResult
    public func deleteCurrentEmptyBlockForBackspaceOrDelete() -> BlockInputSelection? {
        guard isEditable,
              let blockID = activeBlockID else {
            return nil
        }
        if let selection = deleteCurrentEmptyBlockGranularly(blockID: blockID) {
            return selection
        }
        refreshDocumentFromStore()
        return performStructuralEdit(
            named: "Delete Block",
            storeSyncAction: { beforeDocument, afterDocument, _ in
                if beforeDocument.blocks.count == 1,
                   let replacementBlock = afterDocument.block(withID: blockID) {
                    return .replaceBlock(replacementBlock)
                }
                return .deleteBlocks([blockID])
            },
            edit: { document in
                document.deleteEmptyBlockForBackspaceOrDelete(blockID: blockID)
            }
        )
    }

    private func deleteCurrentEmptyBlockGranularly(blockID: BlockInputBlockID) -> BlockInputSelection? {
        guard blockCount > 1,
              let deletionIndex = index(of: blockID),
              let deletedBlock = block(at: deletionIndex),
              deletedBlock.isEmpty else {
            return nil
        }
        let beforeSelection = selection
        let afterSelection: BlockInputSelection?
        if deletionIndex > 0, let previousBlock = block(at: deletionIndex - 1) {
            afterSelection = .cursor(BlockInputCursor(
                blockID: previousBlock.id,
                utf16Offset: previousBlock.cursorUTF16Length
            ))
        } else if let nextBlock = block(at: deletionIndex + 1) {
            afterSelection = .cursor(BlockInputCursor(blockID: nextBlock.id, utf16Offset: 0))
        } else {
            afterSelection = nil
        }

        if canSynchronizeCacheForGranularDeletion(deletedBlockCount: 1) {
            guard document.blocks.indices.contains(deletionIndex),
                  document.blocks[deletionIndex].id == blockID else {
                return nil
            }
            document.blocks.remove(at: deletionIndex)
        } else {
            markDocumentCacheUnsynchronized()
        }
        syncDocumentStore(.deleteBlocks([blockID]))
        applySelection(afterSelection, notify: true)
        undoController?.registerBlockDeletionStructuralEdit(
            actionName: "Delete Block",
            deletedBlocks: [deletedBlock],
            deletionIndex: deletionIndex,
            selectionBefore: beforeSelection,
            selectionAfter: afterSelection
        )
        deleteVisibleBlock(at: deletionIndex, deletedBlockIDs: [blockID])
        publishDocumentChange()
        return afterSelection
    }

    /// Deletes a selected non-text media block after the row itself has focus-like selection.
    @discardableResult
    public func deleteSelectedHorizontalRuleForBackspaceOrDelete() -> BlockInputSelection? {
        guard isEditable else {
            return nil
        }
        refreshDocumentFromStore()
        guard case let .blocks(blockIDs) = selection,
              blockIDs.count == 1,
              let blockID = blockIDs.first else {
            return nil
        }
        let deletionIndex = selectedHorizontalRuleIndex.flatMap { index -> Int? in
            guard block(at: index)?.id == blockID,
                  block(at: index)?.kind.isSelectableStandaloneBlock == true else {
                return nil
            }
            return index
        }
        let selectedKind = deletionIndex.flatMap { block(at: $0)?.kind } ?? block(withID: blockID)?.kind
        guard selectedKind?.isSelectableStandaloneBlock == true else {
            return nil
        }
        return performStructuralEdit(
            named: "Delete Block",
            storeSyncAction: { beforeDocument, afterDocument, _ in
                if beforeDocument.blocks.count == 1,
                   let replacementBlock = afterDocument.block(withID: blockID) {
                    return .replaceBlock(replacementBlock)
                }
                return .replaceDocument
            },
            edit: { document in
                if let deletionIndex {
                    return document.deleteBlock(at: deletionIndex)
                }
                return document.deleteBlock(blockID: blockID)
            }
        )
    }

    /// Moves a block when reordering is enabled.
    @discardableResult
    public func moveBlock(blockID: BlockInputBlockID, to targetIndex: Int) -> BlockInputSelection? {
        guard isEditable, allowsBlockReordering else {
            return nil
        }
        if let selection = moveStoreBackedLargeListBlock(blockID: blockID, to: targetIndex) {
            return selection
        }
        var moveResult: BlockInputMoveResult?
        var moveChangedBlocks: [BlockInputBlock] = []
        return performStructuralEdit(
            named: "Move Block",
            storeSyncAction: { _, _, _ in
                guard let finalIndex = moveResult?.finalIndex else {
                    return .replaceDocument
                }
                let changedBlocks = moveChangedBlocks
                if !changedBlocks.isEmpty {
                    return .moveBlockAndReplaceChangedBlocks(
                        blockID,
                        targetIndex: finalIndex,
                        changedBlocks: changedBlocks
                    )
                }
                return .moveBlock(blockID, targetIndex: finalIndex)
            },
            edit: { document in
                let result = document.moveBlockWithChangedBlocks(blockID: blockID, to: targetIndex)
                moveResult = result
                moveChangedBlocks = result?.changedBlocks ?? []
                return result?.selection
            }
        )
    }

    /// Undoes the most recent structural edit.
    @discardableResult
    public func undoStructuralEdit() -> BlockInputUndoResult? {
        guard isEditable else {
            return nil
        }
        if let result = undoController?.nextGranularStructuralUndoResult(),
           applyGranularUndoResult(result) {
            undoController?.commitGranularStructuralUndo()
            return result
        }
        refreshDocumentFromStore()
        guard let result = undoController?.undoStructuralEdit(in: &document) else {
            return nil
        }
        applyUndoResult(result)
        return result
    }

    /// Redoes the most recent undone structural edit.
    @discardableResult
    public func redoStructuralEdit() -> BlockInputUndoResult? {
        guard isEditable else {
            return nil
        }
        if let result = undoController?.nextGranularStructuralRedoResult(),
           applyGranularUndoResult(result) {
            undoController?.commitGranularStructuralRedo()
            return result
        }
        refreshDocumentFromStore()
        guard let result = undoController?.redoStructuralEdit(in: &document) else {
            return nil
        }
        applyUndoResult(result)
        return result
    }

}

public extension BlockInputView {
    /// Undoes the most recent text edit in the active block.
    @discardableResult
    func undoTextEditInActiveBlock() -> BlockInputUndoResult? {
        guard isEditable,
              let blockID = activeBlockID else {
            return nil
        }
        return undoTextEdit(in: blockID)
    }

    /// Redoes the most recent undone text edit in the active block.
    @discardableResult
    func redoTextEditInActiveBlock() -> BlockInputUndoResult? {
        guard isEditable,
              let blockID = activeBlockID else {
            return nil
        }
        return redoTextEdit(in: blockID)
    }
}

private extension BlockInputView {
    var modalContainsCurrentResponder: Bool {
        linkModalContainsCurrentResponder() || imageModalContainsCurrentResponder()
    }
}
