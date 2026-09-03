import Foundation

struct BlockInputInlineCodeRange: Equatable {
    let fullRange: NSRange
    let contentRange: NSRange
    let delimiterRanges: [NSRange]
}

struct BlockInputCodeFenceOpening: Equatable {
    let language: String?
}

enum BlockInputCodeParsing {
    /// Single-backtick code spans, paired the way CommonMark pairs them: an opener matches the
    /// next lone backtick, a line ending inside the span is content, and an unmatched backtick is
    /// literal, as is everything after it. Pairing used to stop at a line ending, which
    /// stranded a closer on the next line; that stray backtick then opened a bogus span and
    /// shifted every later pairing on its line — the stored Markdown renders them paired, so the
    /// editor has to as well. Runs of two or more backticks are neither openers nor closers.
    static func inlineCodeRanges(in text: String) -> [BlockInputInlineCodeRange] {
        let nsText = text as NSString
        guard nsText.length > 0 else {
            return []
        }
        var ranges: [BlockInputInlineCodeRange] = []
        var location = 0
        while location < nsText.length {
            guard nsText.character(at: location) == Self.backtick else {
                location += 1
                continue
            }
            let delimiterLength = consecutiveBackticks(in: nsText, from: location)
            guard delimiterLength == 1 else {
                location += delimiterLength
                continue
            }
            let openingLocation = location
            let contentStart = openingLocation + 1
            if let closingLocation = closingSingleBacktickLocation(in: nsText, from: contentStart),
               closingLocation > contentStart {
                ranges.append(BlockInputInlineCodeRange(
                    fullRange: NSRange(location: openingLocation, length: closingLocation - openingLocation + 1),
                    contentRange: NSRange(location: contentStart, length: closingLocation - contentStart),
                    delimiterRanges: [
                        NSRange(location: openingLocation, length: 1),
                        NSRange(location: closingLocation, length: 1)
                    ]
                ))
                location = closingLocation + 1
            } else {
                // The closer search reached the end of the text without finding another lone
                // backtick, so no later opener can close either; scanning on would rescan the
                // tail once per stray backtick.
                break
            }
        }
        return ranges
    }

    static func codeFenceOpening(in text: String) -> BlockInputCodeFenceOpening? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"),
              trimmed.rangeOfCharacter(from: .newlines) == nil else {
            return nil
        }
        let languageStart = trimmed.index(trimmed.startIndex, offsetBy: 3)
        let language = String(trimmed[languageStart...])
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLanguage.contains("`") else {
            return nil
        }
        return BlockInputCodeFenceOpening(language: trimmedLanguage.isEmpty ? nil : trimmedLanguage)
    }

    private static let backtick: unichar = 0x60

    private static func consecutiveBackticks(in text: NSString, from location: Int) -> Int {
        var length = 0
        while location + length < text.length,
              text.character(at: location + length) == backtick {
            length += 1
        }
        return max(length, 1)
    }

    private static func closingSingleBacktickLocation(in text: NSString, from startLocation: Int) -> Int? {
        var location = startLocation
        while location < text.length {
            guard text.character(at: location) == backtick else {
                location += 1
                continue
            }
            let delimiterLength = consecutiveBackticks(in: text, from: location)
            guard delimiterLength == 1 else {
                location += delimiterLength
                continue
            }
            return location
        }
        return nil
    }
}
