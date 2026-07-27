import Foundation

/// Raw token scanners for chip-rendered literals: `/command` slash tokens and
/// `@`-prefixed file path mentions. Both keep source text unchanged and emit
/// delimiter-free ranges over the literal token.
extension BlockInputInlineMarkdownParsing {
    static func rawSlashCommandRanges(
        in text: NSString,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup,
        availability: BlockInputSlashCommandAvailability,
        isDocumentStartBlock: Bool
    ) -> [BlockInputInlineMarkdownRange] {
        var ranges: [BlockInputInlineMarkdownRange] = []
        var location = 0
        while location < text.length {
            guard let tokenRange = BlockInputCompletionTokenParsing.rawSlashCommandTokenRange(
                startingAt: location,
                in: text,
                availability: availability,
                isDocumentStartBlock: isDocumentStartBlock
            ) else {
                location += 1
                continue
            }
            guard !excludedRangeLookup.intersects(tokenRange) else {
                location = NSMaxRange(tokenRange)
                continue
            }
            ranges.append(BlockInputInlineMarkdownRange(
                style: .rawSlashCommand,
                fullRange: tokenRange,
                contentRange: tokenRange,
                delimiterRanges: []
            ))
            location = NSMaxRange(tokenRange)
        }
        return ranges
    }

    static func rawFileMentionRanges(
        in text: NSString,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup
    ) -> [BlockInputInlineMarkdownRange] {
        var ranges: [BlockInputInlineMarkdownRange] = []
        var location = 0
        while location < text.length {
            guard let tokenRange = BlockInputCompletionTokenParsing.rawFileMentionTokenRange(
                startingAt: location,
                in: text
            ) else {
                location += 1
                continue
            }
            guard !excludedRangeLookup.intersects(tokenRange) else {
                location = NSMaxRange(tokenRange)
                continue
            }
            ranges.append(BlockInputInlineMarkdownRange(
                style: .rawFileMention,
                fullRange: tokenRange,
                contentRange: tokenRange,
                delimiterRanges: []
            ))
            location = NSMaxRange(tokenRange)
        }
        return ranges
    }
}
