import Foundation

/// Provides visual-only argument hints for slash commands.
///
/// Use this with ``BlockInputConfiguration/inlineHintProvider`` when slash commands should show expected arguments
/// after the active caret without inserting those hints into the document.
public struct BlockInputSlashCommandArgumentHints: Sendable {
    /// Whether hints should only appear in the document-start block.
    public var requiresDocumentStart: Bool

    private var hintsByCommand: [String: String]

    /// Creates slash-command argument hints from command/hint pairs.
    ///
    /// Commands are normalized by trimming whitespace, removing a leading slash, and lowercasing. Empty commands and
    /// empty hints are ignored. When the same command appears more than once, the first non-empty hint wins.
    public init(
        commandHints: [(command: String, hint: String)],
        requiresDocumentStart: Bool = true
    ) {
        self.requiresDocumentStart = requiresDocumentStart
        hintsByCommand = Self.normalizedHints(from: commandHints)
    }

    /// Creates slash-command argument hints from a command-to-hint map.
    ///
    /// Commands are normalized by trimming whitespace, removing a leading slash, and lowercasing. Empty commands and
    /// empty hints are ignored.
    public init(
        _ commandHints: [String: String],
        requiresDocumentStart: Bool = true
    ) {
        self.init(
            commandHints: commandHints.map { (command: $0.key, hint: $0.value) },
            requiresDocumentStart: requiresDocumentStart
        )
    }

    /// Returns the inline hint for the active slash-command context, when one is available.
    public func inlineHint(for context: BlockInputInlineHintContext) -> BlockInputInlineHint? {
        guard !requiresDocumentStart || context.isDocumentStartBlock,
              context.selectedRange.length == 0 else {
            return nil
        }
        let text = context.block.text as NSString
        let caretOffset = min(max(context.cursor.utf16Offset, 0), text.length)
        guard caretOffset == text.length else {
            return nil
        }
        let prefix = text.substring(to: caretOffset)
        guard let parsedCommand = Self.parsedSlashCommandPrefix(prefix),
              let hint = hintsByCommand[parsedCommand.command],
              !hint.isEmpty else {
            return nil
        }
        let isBareCommand = parsedCommand.trailingText.isEmpty
        return BlockInputInlineHint(text: isBareCommand ? " \(hint)" : hint)
    }

    private static func normalizedHints(from commandHints: [(command: String, hint: String)]) -> [String: String] {
        commandHints.reduce(into: [:]) { result, entry in
            guard let command = normalizedCommand(entry.command) else {
                return
            }
            let hint = entry.hint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hint.isEmpty,
                  result[command] == nil else {
                return
            }
            result[command] = hint
        }
    }

    private static func normalizedCommand(_ command: String) -> String? {
        var normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("/") {
            normalized.removeFirst()
        }
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func parsedSlashCommandPrefix(_ prefix: String) -> ParsedSlashCommandPrefix? {
        if let rawPrefix = parsedRawSlashCommandPrefix(prefix) {
            return rawPrefix
        }
        return parsedLinkBackedSlashCommandPrefix(prefix)
    }

    private static func parsedRawSlashCommandPrefix(_ prefix: String) -> ParsedSlashCommandPrefix? {
        guard prefix.hasPrefix("/") else {
            return nil
        }
        let commandAndTrailingText = prefix.dropFirst()
        let commandEnd = commandAndTrailingText.firstIndex(where: \.isWhitespace) ?? commandAndTrailingText.endIndex
        guard let command = normalizedCommand(String(commandAndTrailingText[..<commandEnd])) else {
            return nil
        }
        let trailingText = String(commandAndTrailingText[commandEnd...])
        guard containsOnlyInlineHintWhitespace(trailingText) else {
            return nil
        }
        return ParsedSlashCommandPrefix(command: command, trailingText: trailingText)
    }

    private static func parsedLinkBackedSlashCommandPrefix(_ prefix: String) -> ParsedSlashCommandPrefix? {
        guard prefix.hasPrefix("[/"),
              let labelEnd = prefix.range(of: "]("),
              let command = normalizedCommand(String(prefix[prefix.index(prefix.startIndex, offsetBy: 2)..<labelEnd.lowerBound])) else {
            return nil
        }
        let destinationStart = labelEnd.upperBound
        guard let destinationEnd = closingLinkDestinationIndex(in: prefix, startingAt: destinationStart) else {
            return nil
        }
        let trailingText = String(prefix[prefix.index(after: destinationEnd)...])
        guard containsOnlyInlineHintWhitespace(trailingText) else {
            return nil
        }
        return ParsedSlashCommandPrefix(command: command, trailingText: trailingText)
    }

    private static func containsOnlyInlineHintWhitespace(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }

    private static func closingLinkDestinationIndex(in text: String, startingAt start: String.Index) -> String.Index? {
        var index = start
        while index < text.endIndex {
            if text[index] == ")",
               !isEscapedCharacter(at: index, in: text) {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func isEscapedCharacter(at index: String.Index, in text: String) -> Bool {
        var slashCount = 0
        var current = index
        while current > text.startIndex {
            let previous = text.index(before: current)
            guard text[previous] == "\\" else {
                break
            }
            slashCount += 1
            current = previous
        }
        return slashCount % 2 == 1
    }
}

private struct ParsedSlashCommandPrefix {
    var command: String
    var trailingText: String
}
