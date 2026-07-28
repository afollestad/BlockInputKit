import AppKit

extension BlockInputView {
    /// Replaces an existing `@path` mention token with a new literal token.
    /// Mentions never serialize as Markdown links; hosts rely on the token
    /// staying plain text.
    func applyFileMentionEdit(context: BlockInputLinkContext, path: String) -> Bool {
        guard isEditable,
              case .edit(let mentionRange) = context.mode,
              mentionRange.style == .rawFileMention,
              BlockInputCompletionTokenParsing.isValidRawFileMentionPath(path),
              let index = index(of: context.blockID),
              var block = block(at: index) else {
            return false
        }
        let token = "@\(path)"
        let replacement = BlockInputLinkReplacement(
            text: token,
            selectedUTF16Length: (token as NSString).length,
            selectsResultingText: false,
            actionName: "Edit File Mention"
        )
        return replaceLinkSource(context: context, block: &block, index: index, replacement: replacement)
    }

    func fileMentionRange(in text: String, containing range: NSRange) -> BlockInputInlineMarkdownRange? {
        BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange),
            fileBaseURL: fileBaseURL,
            rawFileMentionChips: true
        )
        .filter { $0.style == .rawFileMention }
        .first { $0.fullRange.intersectionLength(with: range) > 0 || $0.fullRange.containsOrTouches(range.location) }
    }
}
