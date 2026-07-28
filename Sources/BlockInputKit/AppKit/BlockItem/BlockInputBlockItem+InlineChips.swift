import AppKit

extension BlockInputBlockItem {
    func updateSelectionDependentAttributesForCurrentSelection() {
        guard let block = renderedBlock,
              containsInlineChip(in: block) else {
            updateTypingAttributesForCurrentSelection()
            return
        }
        applyTextAttributes(for: block)
    }

    private func containsInlineChip(in block: BlockInputBlock) -> Bool {
        guard Self.supportsInlineMarkdownStyling(block.kind) else {
            return false
        }
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: textView.string).map(\.fullRange)
        return BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: textView.string,
            excluding: inlineCodeRanges,
            fileBaseURL: fileBaseURL,
            rawSlashCommandChips: rawSlashCommandChips,
            rawFileMentionChips: rawFileMentionChips,
            slashCommandAvailability: slashCommandAvailability,
            isDocumentStartBlock: isDocumentStartBlock
        )
        .contains { $0.inlineChipKind(in: textView.string) != nil }
    }
}
