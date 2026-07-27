import Foundation

/// Inline Markdown link variants that render as chips instead of normal links.
enum BlockInputInlineChipKind: Equatable {
    case fileLink
    case slashCommand
    case rawSlashCommand
    case rawFileMention
}

extension BlockInputInlineMarkdownRange {
    func inlineChipKind(in text: String) -> BlockInputInlineChipKind? {
        if style == .rawSlashCommand {
            return .rawSlashCommand
        }
        if style == .rawFileMention {
            return .rawFileMention
        }
        guard style == .link,
              let linkDestination else {
            return nil
        }
        if linkDestination.isFileURL {
            return .fileLink
        }
        return slashCommandChipLabel(in: text) == nil ? nil : .slashCommand
    }

    func slashCommandChipLabel(in text: String) -> String? {
        if style == .rawSlashCommand {
            return linkLabel(in: text)
        }
        let label = linkLabel(in: text)
        guard label.hasPrefix("/") else {
            return nil
        }
        return label
    }

    func linkLabel(in text: String) -> String {
        (text as NSString)
            .substring(with: text.blockInputLinkClampedRange(contentRange))
            .blockInputUnescapedLinkLabel
    }
}

extension BlockInputStyle {
    func inlineChipStyle(for kind: BlockInputInlineChipKind) -> BlockInputInlineChipStyle {
        switch kind {
        case .fileLink, .rawFileMention:
            return fileChip
        case .slashCommand:
            return slashCommandChip
        case .rawSlashCommand:
            return rawSlashCommandChip
        }
    }
}
