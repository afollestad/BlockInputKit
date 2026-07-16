import AppKit

struct BlockInputCompletionToken: Equatable, Sendable {
    var trigger: BlockInputCompletionTrigger
    var replacementRange: NSRange
    var query: String
    var rawQuery: String
    var fileQuery: BlockInputCompletionFileQuery?
}

struct BlockInputCompletionSession: Equatable {
    var id: UUID
    var blockID: BlockInputBlockID
    var token: BlockInputCompletionToken
    var sourceText: String
    var sourceKind: BlockInputBlockKind
    var anchorWindowRect: NSRect
    var suggestions: [BlockInputCompletionSuggestion]
    var highlightedIndex: Int
    var isLoading: Bool
}

extension BlockInputView {
    static let overlayCompletionPopupVerticalOffset: CGFloat = 8

    /// Dismisses the completion popup when the editor view changes size.
    public override func setFrameSize(_ newSize: NSSize) {
        let previousWidth = frame.width
        let sizeChanged = frame.size != newSize
        super.setFrameSize(newSize)
        updateEditorChromeLayers()
        if sizeChanged {
            dismissCompletionPopup()
            invalidateVisibleCursorRects()
        }
        guard heightSizing != nil else {
            return
        }
        clampVerticalScrollOffsetIfNeeded()
        if abs(previousWidth - newSize.width) > 0.5 {
            invalidatePreferredHeight()
        }
    }

    func refreshCompletionSession(
        item: BlockInputBlockItem,
        blockID: BlockInputBlockID
    ) {
        guard isEditable,
              completionProvider != nil,
              let block = block(withID: blockID),
              BlockInputBlockItem.supportsInlineMarkdownStyling(block.kind),
              item.currentSelectedRange.length == 0 else {
            dismissCompletionPopup()
            return
        }
        let selectedRange = item.currentSelectedRange
        let text = item.currentText
        guard let token = completionToken(
            in: text,
            selectedRange: selectedRange,
            blockID: blockID,
            blockKind: block.kind
        ) else {
            dismissCompletionPopup()
            return
        }

        let anchorWindowRect = item.anchorWindowRect(forUTF16Offset: selectedRange.location)
        if updateUnchangedCompletionSession(blockID: blockID, block: block, token: token, sourceText: text, anchorWindowRect: anchorWindowRect) {
            return
        }
        if let session = continuousCompletionSession(
            blockID: blockID,
            block: block,
            token: token,
            sourceText: text,
            anchorWindowRect: anchorWindowRect
        ) {
            completionSession = session
            showCompletionPopup(for: session)
            requestCompletionSuggestions(for: session)
            return
        }

        let session = newCompletionSession(
            blockID: blockID,
            block: block,
            token: token,
            sourceText: text,
            anchorWindowRect: anchorWindowRect
        )
        completionSession = session
        showCompletionPopup(for: session)
        requestCompletionSuggestions(for: session)
    }

    func handleCompletionCommand(_ selector: Selector) -> Bool {
        guard isEditable,
              completionSession != nil else {
            return false
        }
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            moveCompletionHighlight(delta: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveCompletionHighlight(delta: 1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismissCompletionPopup()
            return true
        case #selector(NSResponder.insertTab(_:)):
            return acceptHighlightedCompletionSuggestion(consumesWhenMissing: true)
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            return acceptHighlightedCompletionSuggestion(consumesWhenMissing: false, allowsExactMatchPassthrough: true)
        default:
            return false
        }
    }

    func handleCompletionKeyDown(_ event: NSEvent) -> Bool {
        guard isEditable,
              completionSession != nil else {
            return false
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isSubset(of: [.numericPad, .function]) else {
            return false
        }
        switch event.specialKey {
        case .upArrow:
            moveCompletionHighlight(delta: -1)
            return true
        case .downArrow:
            moveCompletionHighlight(delta: 1)
            return true
        default:
            break
        }
        guard let characters = event.charactersIgnoringModifiers else {
            return false
        }
        switch characters {
        case "\u{1B}":
            dismissCompletionPopup()
            return true
        case "\t":
            return acceptHighlightedCompletionSuggestion(consumesWhenMissing: true)
        case "\r", "\n":
            return acceptHighlightedCompletionSuggestion(consumesWhenMissing: false, allowsExactMatchPassthrough: true)
        default:
            return false
        }
    }

    func dismissCompletionPopup() {
        completionRequestTask?.cancel()
        completionRequestTask = nil
        completionSession = nil
        completionPopupEventCaptureView.removeFromSuperview()
        completionPopupView?.removeFromSuperview()
        completionPopupView = nil
        removeCompletionPopupDismissalMonitor()
        publishEditorInteractionUIChangeIfNeeded()
        updateInlineHintsForVisibleItems()
    }

    func positionCompletionPopup() {
        guard let session = completionSession,
              let popup = completionPopupView else {
            return
        }
        presentCompletionPopup(popup, for: session, state: completionPopupState(for: session))
    }

    private func completionPopupLayout(
        for session: BlockInputCompletionSession,
        state: BlockInputCompletionPopupState
    ) -> BlockInputCompletionPopupOverlay {
        let height = BlockInputCompletionPopupView.measuredHeight(for: state)
        switch completionPopupPlacement {
        case .caret:
            return caretCompletionPopupLayout(for: session, height: height)
        case .overlay:
            let defaultLayout = defaultOverlayCompletionPopupLayout(height: height)
            let context = BlockInputCompletionPopupOverlayContext(
                editorView: self,
                defaultContainer: defaultLayout.container,
                defaultFrame: defaultLayout.frame,
                popupSize: defaultLayout.frame.size
            )
            return completionPopupConfiguration.overlayProvider?(context) ?? defaultLayout
        }
    }

    private func caretCompletionPopupLayout(
        for session: BlockInputCompletionSession,
        height: CGFloat
    ) -> BlockInputCompletionPopupOverlay {
        let availableWidth = max(0, bounds.width - 24)
        let width = min(max(260, bounds.width * 0.45), availableWidth)
        let anchor = convert(session.anchorWindowRect.origin, from: nil)
        let popupX = min(max(anchor.x - 12, bounds.minX + 12), max(bounds.minX + 12, bounds.maxX - width - 12))
        let preferredY = anchor.y - height - 8
        let popupY = preferredY >= bounds.minY + 12
            ? preferredY
            : min(max(anchor.y + 18, bounds.minY + 12), max(bounds.minY + 12, bounds.maxY - height - 12))
        return BlockInputCompletionPopupOverlay(
            container: self,
            frame: NSRect(x: popupX, y: popupY, width: width, height: height)
        )
    }

    private func defaultOverlayCompletionPopupLayout(height: CGFloat) -> BlockInputCompletionPopupOverlay {
        let container = defaultOverlayCompletionPopupContainer()
        let overlayLeft = convert(NSPoint(x: bounds.minX, y: bounds.maxY), to: container)
        let overlayRight = convert(NSPoint(x: bounds.maxX, y: bounds.maxY), to: container)
        let width = max(0, abs(overlayRight.x - overlayLeft.x))
        let popupX = min(overlayLeft.x, overlayRight.x)
        let popupY = container.isFlipped
            ? overlayLeft.y - height - Self.overlayCompletionPopupVerticalOffset
            : overlayLeft.y + Self.overlayCompletionPopupVerticalOffset
        return BlockInputCompletionPopupOverlay(
            container: container,
            frame: NSRect(x: popupX, y: popupY, width: width, height: height)
        )
    }

    private func defaultOverlayCompletionPopupContainer() -> NSView {
        if let contentView = window?.contentView,
           contentView !== self {
            return contentView
        }
        return superview ?? self
    }

    private func completionToken(
        in text: String,
        selectedRange: NSRange,
        blockID: BlockInputBlockID,
        blockKind: BlockInputBlockKind
    ) -> BlockInputCompletionToken? {
        guard selectedRange.length == 0,
              BlockInputBlockItem.supportsInlineMarkdownStyling(blockKind) else {
            return nil
        }
        let nsText = text as NSString
        let textLength = nsText.length
        let caretOffset = min(max(selectedRange.location, 0), textLength)
        let tokenStart = BlockInputCompletionTokenParsing.tokenStart(before: caretOffset, in: nsText)
        guard tokenStart < caretOffset,
              let trigger = completionTrigger(at: tokenStart, in: text) else {
            return nil
        }
        guard trigger != .slashCommand || BlockInputCompletionTokenParsing.allowsSlashCommandToken(
            startingAt: tokenStart,
            availability: slashCommandAvailability,
            isDocumentStartBlock: index(of: blockID) == 0
        ) else {
            return nil
        }
        let replacementRange = NSRange(location: tokenStart, length: caretOffset - tokenStart)
        guard !completionRangeIntersectsExcludedInlineRanges(replacementRange, in: text) else {
            return nil
        }
        let rawQuery = (text as NSString).substring(with: NSRange(location: tokenStart + 1, length: caretOffset - tokenStart - 1))
        let fileQuery = trigger == .mention ? BlockInputCompletionFileQuery.parsing(rawQuery) : nil
        return BlockInputCompletionToken(
            trigger: trigger,
            replacementRange: replacementRange,
            query: fileQuery?.remainder ?? rawQuery,
            rawQuery: rawQuery,
            fileQuery: fileQuery
        )
    }

    private func completionTrigger(at tokenStart: Int, in text: String) -> BlockInputCompletionTrigger? {
        switch (text as NSString).substring(with: NSRange(location: tokenStart, length: 1)) {
        case "@":
            return .mention
        case "/":
            return .slashCommand
        default:
            return nil
        }
    }

    private func completionRangeIntersectsExcludedInlineRanges(_ range: NSRange, in text: String) -> Bool {
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        if inlineCodeRanges.contains(where: { $0.intersectionLength(with: range) > 0 }) {
            return true
        }
        let linkSourceRanges = BlockInputInlineMarkdownParsing.linkSourceRanges(in: text, excluding: inlineCodeRanges)
        return linkSourceRanges.contains { linkRange in
            linkRange.intersectionLength(with: range) > 0
        }
    }

    private func requestCompletionSuggestions(for session: BlockInputCompletionSession) {
        let requestIdentity = session.requestIdentity
        guard completionSession?.requestIdentity == requestIdentity else {
            return
        }
        completionRequestTask?.cancel()
        guard let request = completionRequest(
            trigger: session.token.trigger,
            query: session.token.query,
            blockID: session.blockID,
            replacementRange: session.token.replacementRange,
            rawQuery: session.token.rawQuery,
            fileQuery: session.token.fileQuery,
            refreshesDocumentFromStore: false
        ) else {
            dismissCompletionPopup()
            return
        }
        completionRequestTask = Task.detached(
            priority: .userInitiated
        ) { [weak self, provider = request.provider, context = request.context, requestIdentity] in
            let suggestions = await provider.suggestions(for: context)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run { [weak self] in
                guard !Task.isCancelled,
                      let self else {
                    return
                }
                guard var current = completionSession,
                      current.requestIdentity == requestIdentity else {
                    return
                }
                guard let currentBlock = block(withID: current.blockID),
                      current.sourceText == currentBlock.text,
                      current.sourceKind == currentBlock.kind else {
                    dismissCompletionPopup()
                    return
                }
                current.suggestions = suggestions
                current.highlightedIndex = suggestions.isEmpty ? 0 : min(current.highlightedIndex, suggestions.count - 1)
                current.isLoading = false
                completionSession = current
                showCompletionPopup(for: current)
                completionRequestTask = nil
            }
        }
    }

    func refreshCompletionPopupPresentation() {
        guard let completionSession else {
            positionCompletionPopup()
            return
        }
        showCompletionPopup(for: completionSession)
    }

    private func showCompletionPopup(for session: BlockInputCompletionSession) {
        let popup = completionPopupView ?? BlockInputCompletionPopupView()
        completionPopupView = popup
        presentCompletionPopup(popup, for: session, state: completionPopupState(for: session))
        installCompletionPopupDismissalMonitor()
        publishEditorInteractionUIChangeIfNeeded()
        updateInlineHintsForVisibleItems()
    }

    private func completionPopupState(for session: BlockInputCompletionSession) -> BlockInputCompletionPopupState {
        BlockInputCompletionPopupState(
            suggestions: session.suggestions,
            highlightedIndex: session.highlightedIndex,
            isLoading: session.isLoading,
            sessionID: session.id
        )
    }

    private func presentCompletionPopup(
        _ popup: BlockInputCompletionPopupView,
        for session: BlockInputCompletionSession,
        state: BlockInputCompletionPopupState
    ) {
        blockInputWithoutCompletionPopupAnimations {
            let popupLayout = completionPopupLayout(for: session, state: state)
            let popupContainer = popupLayout.container
            let previousFrame = popup.frame
            popup.appearance = effectiveAppearance

            if popup.superview !== popupContainer {
                popup.removeFromSuperview()
                popupContainer.addSubview(popup, positioned: .above, relativeTo: nil)
            }
            popup.frame = popupLayout.frame
            popup.configure(
                state: state,
                style: completionPopupConfiguration.style,
                onSelect: { [weak self] suggestion in
                    self?.acceptCompletionSuggestionFromPopup(suggestion)
                },
                onHighlight: { [weak self] index in
                    self?.highlightCompletionSuggestion(at: index)
                }
            )
            if previousFrame != popup.frame {
                popup.suppressHoverUntilPointerMoves()
            }

            completionPopupEventCaptureView.configure(popup: popup)
            completionPopupEventCaptureView.appearance = effectiveAppearance
            completionPopupEventCaptureView.autoresizingMask = [.width, .height]
            completionPopupEventCaptureView.frame = popupContainer.bounds
            if completionPopupEventCaptureView.superview !== popupContainer ||
                popupContainer.subviews.last !== completionPopupEventCaptureView {
                completionPopupEventCaptureView.removeFromSuperview()
                popupContainer.addSubview(completionPopupEventCaptureView, positioned: .above, relativeTo: nil)
            }

            popup.needsLayout = true
            popup.layoutSubtreeIfNeeded()
            popup.displayIfNeeded()
        }
    }

    private func moveCompletionHighlight(delta: Int) {
        guard var session = completionSession,
              !session.suggestions.isEmpty else {
            return
        }
        session.highlightedIndex = min(max(0, session.highlightedIndex + delta), session.suggestions.count - 1)
        completionSession = session
        completionPopupView?.suppressHoverUntilPointerMoves()
        showCompletionPopup(for: session)
    }

    private func highlightCompletionSuggestion(at index: Int) {
        guard var session = completionSession,
              session.suggestions.indices.contains(index),
              session.highlightedIndex != index else {
            return
        }
        session.highlightedIndex = index
        completionSession = session
        showCompletionPopup(for: session)
    }

    private func acceptHighlightedCompletionSuggestion(
        consumesWhenMissing: Bool,
        allowsExactMatchPassthrough: Bool = false
    ) -> Bool {
        guard let session = completionSession else {
            return false
        }
        guard let suggestion = session.suggestions[safe: session.highlightedIndex] else {
            return consumesWhenMissing
        }
        if allowsExactMatchPassthrough,
           shouldPassthroughCompletionReturn() {
            return false
        }
        acceptCompletionSuggestionFromPopup(suggestion)
        return true
    }

    private func acceptCompletionSuggestionFromPopup(_ suggestion: BlockInputCompletionSuggestion) {
        guard isEditable,
              let session = completionSession else {
            return
        }
        dismissCompletionPopup()
        guard let block = block(withID: session.blockID),
              block.text == session.sourceText,
              block.kind == session.sourceKind else {
            return
        }
        guard completionReplacementText(in: session) != nil else {
            return
        }
        guard acceptCompletionSuggestion(
            suggestion,
            in: session.blockID,
            replacing: session.token.replacementRange
        ) != nil else {
            return
        }
        restoreVisibleSelection()
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}
