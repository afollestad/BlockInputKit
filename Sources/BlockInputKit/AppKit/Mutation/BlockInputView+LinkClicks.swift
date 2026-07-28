import AppKit

extension BlockInputView {
    func handleLinkClick(
        blockID: BlockInputBlockID,
        selectedRange: NSRange,
        clickedLinkRange: BlockInputInlineMarkdownRange? = nil,
        event: NSEvent
    ) -> Bool {
        // Command-clicked or read-only mention chips open their file directly.
        // Plain clicks fall through to the modal path, which presents the
        // file-mention mode: it edits the literal `@path` token and never
        // writes link markdown, which hosts rely on staying plain text.
        if let clickedLinkRange,
           clickedLinkRange.style == .rawFileMention,
           let destination = clickedLinkRange.linkDestination,
           event.modifierFlags.contains(.command) || !isEditable {
            let didOpen = linkURLOpener(destination)
            if didOpen {
                dismissLinkModal(restoreFocus: false)
            }
            return didOpen
        }
        guard let context = linkContext(
            blockID: blockID,
            selectedRange: selectedRange,
            clickedLinkRange: clickedLinkRange,
            event: event,
            prefersClickedOffset: true
        ),
              case let .edit(linkRange) = context.mode,
              let destination = linkRange.linkDestination else {
            return false
        }
        if routeSlashCommandChipClick(
            context: context,
            linkRange: linkRange,
            destination: destination,
            blockID: blockID,
            event: event
        ) {
            return true
        }
        if event.modifierFlags.contains(.command) {
            let didOpen = linkURLOpener(destination)
            if didOpen {
                dismissLinkModal(restoreFocus: false)
            }
            return didOpen
        }
        guard isEditable else {
            return false
        }
        showLinkModal(context: context)
        return true
    }

    private func routeSlashCommandChipClick(
        context: BlockInputLinkContext,
        linkRange: BlockInputInlineMarkdownRange,
        destination: URL,
        blockID: BlockInputBlockID,
        event: NSEvent
    ) -> Bool {
        guard linkRange.inlineChipKind(in: context.sourceText) == .slashCommand,
              let action = slashCommandChipClickHandler?(BlockInputSlashCommandChipClickContext(
                label: linkText(in: context.sourceText, range: linkRange),
                uri: destination,
                blockID: blockID,
                sourceRange: linkRange.fullRange,
                editorView: self,
                event: event,
                clickKind: slashCommandChipClickKind(for: event)
              )) else {
            return false
        }
        switch action {
        case .showLinkModal:
            guard isEditable else {
                return false
            }
            showLinkModal(context: context)
            return true
        case .openURL:
            _ = linkURLOpener(destination)
            dismissLinkModal(restoreFocus: false)
            return true
        case .hostHandled:
            dismissLinkModal(restoreFocus: false)
            return true
        }
    }

    private func slashCommandChipClickKind(for event: NSEvent) -> BlockInputSlashCommandChipClickKind {
        event.modifierFlags.contains(.command) ? .commandClick : .plainClick
    }
}
