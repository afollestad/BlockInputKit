import Foundation

/// Visual inline Markdown style supported by the AppKit block renderer.
enum BlockInputInlineMarkdownStyle: Hashable {
    case bold
    case italic
    case underline
    case strikethrough
    case link
    case inlineImage
    case rawSlashCommand
    case rawFileMention
}

/// UTF-16 ranges for one visual inline Markdown span.
///
/// The full range includes Markdown delimiters or HTML tags, while the content
/// range is the editable text that receives the visual style.
struct BlockInputInlineMarkdownRange: Equatable {
    let style: BlockInputInlineMarkdownStyle
    let fullRange: NSRange
    let contentRange: NSRange
    let delimiterRanges: [NSRange]
    /// Populated only for `.link` ranges so click handling can use the already-validated destination.
    let linkDestination: URL?
    /// Original unescaped Markdown destination text.
    let linkRawDestination: String?
    /// Populated only for `.inlineImage` ranges: source, alt text, and any declared dimensions.
    let image: BlockInputImage?

    init(
        style: BlockInputInlineMarkdownStyle,
        fullRange: NSRange,
        contentRange: NSRange,
        delimiterRanges: [NSRange],
        linkDestination: URL? = nil,
        linkRawDestination: String? = nil,
        image: BlockInputImage? = nil
    ) {
        self.style = style
        self.fullRange = fullRange
        self.contentRange = contentRange
        self.delimiterRanges = delimiterRanges
        self.linkDestination = linkDestination
        self.linkRawDestination = linkRawDestination
        self.image = image
    }
}

/// Dependency-free row-local scanner for visual inline Markdown styling.
///
/// The scanner intentionally keeps source text unchanged and returns only
/// `NSRange` values that AppKit can apply to the mounted row's text storage.
enum BlockInputInlineMarkdownParsing {
    static func inlineMarkdownRanges(
        in text: String,
        excluding excludedRanges: [NSRange] = [],
        fileBaseURL: URL? = nil,
        rawSlashCommandChips: Bool = false,
        rawFileMentionChips: Bool = false,
        slashCommandAvailability: BlockInputSlashCommandAvailability = .documentStart,
        isDocumentStartBlock: Bool = false,
        inlineImages: Bool = true
    ) -> [BlockInputInlineMarkdownRange] {
        let nsText = text as NSString
        guard nsText.length > 0 else {
            return []
        }
        let excludedRangeLookup = BlockInputExcludedRangeLookup(
            textLength: nsText.length,
            ranges: excludedRanges
        )
        let nonRawRangeGroups = nonRawMarkdownRangeGroups(
            in: nsText,
            excluding: excludedRangeLookup,
            fileBaseURL: fileBaseURL,
            inlineImages: inlineImages
        )
        // Raw token passes must not fire inside link source text or across
        // markdown delimiters, so they build one shared stricter exclusion.
        var rawExcludedRangeLookup: BlockInputExcludedRangeLookup?
        if rawSlashCommandChips || rawFileMentionChips {
            let excludedLinkSourceRanges = linkSourceRanges(in: nsText, excluding: excludedRangeLookup)
            rawExcludedRangeLookup = BlockInputExcludedRangeLookup(
                textLength: nsText.length,
                ranges: excludedRanges + excludedLinkSourceRanges + nonRawRangeGroups.delimiterRanges
            )
        }
        let rawSlashRanges: [BlockInputInlineMarkdownRange]
        if rawSlashCommandChips, let rawExcludedRangeLookup {
            rawSlashRanges = rawSlashCommandRanges(
                in: nsText,
                excluding: rawExcludedRangeLookup,
                availability: slashCommandAvailability,
                isDocumentStartBlock: isDocumentStartBlock
            )
        } else {
            rawSlashRanges = []
        }
        let mentionRanges: [BlockInputInlineMarkdownRange]
        if rawFileMentionChips, let rawExcludedRangeLookup {
            mentionRanges = rawFileMentionRanges(
                in: nsText,
                excluding: rawExcludedRangeLookup
            )
        } else {
            mentionRanges = []
        }
        return mergedByContentLocation(nonRawRangeGroups.including(
            rawSlashRanges: rawSlashRanges,
            rawFileMentionRanges: mentionRanges
        ))
    }

    private static func nonRawMarkdownRangeGroups(
        in text: NSString,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup,
        fileBaseURL: URL?,
        inlineImages: Bool
    ) -> BlockInputInlineMarkdownRangeGroups {
        let links = linkRanges(in: text, excluding: excludedRangeLookup, fileBaseURL: fileBaseURL, inlineImages: inlineImages)
        return BlockInputInlineMarkdownRangeGroups(
            links: links,
            htmlImages: inlineImages
                ? htmlInlineImageRanges(in: text, excluding: excludedRangeLookup, avoiding: links.map(\.fullRange))
                : [],
            composedAsterisks: composedDelimiterRanges(
                in: text,
                delimiter: tripleAsterisk,
                styles: [.bold, .italic],
                excluding: excludedRangeLookup
            ),
            bold: delimiterRanges(in: text, delimiter: doubleAsterisk, style: .bold, excluding: excludedRangeLookup),
            strikethrough: delimiterRanges(in: text, delimiter: doubleTilde, style: .strikethrough, excluding: excludedRangeLookup),
            underlineTags: underlineRanges(
                in: text,
                openingTag: underlineOpeningTag,
                closingTag: underlineClosingTag,
                excluding: excludedRangeLookup
            ),
            insertTags: underlineRanges(in: text, openingTag: insertOpeningTag, closingTag: insertClosingTag, excluding: excludedRangeLookup),
            italicAsterisks: delimiterRanges(in: text, delimiter: singleAsterisk, style: .italic, excluding: excludedRangeLookup),
            italicUnderscores: delimiterRanges(in: text, delimiter: singleUnderscore, style: .italic, excluding: excludedRangeLookup)
        )
    }

    private static let asterisk: unichar = 0x2A
    private static let underscore: unichar = 0x5F
    private static let tilde: unichar = 0x7E
    private static let lineFeed: unichar = 0x0A
    private static let carriageReturn: unichar = 0x0D
    private static let singleAsterisk = "*"
    private static let doubleAsterisk = "**"
    private static let tripleAsterisk = "***"
    private static let singleUnderscore = "_"
    private static let doubleTilde = "~~"
    private static let underlineOpeningTag = "<u>"
    private static let underlineClosingTag = "</u>"
    private static let insertOpeningTag = "<ins>"
    private static let insertClosingTag = "</ins>"

    private static func composedDelimiterRanges(
        in text: NSString,
        delimiter: String,
        styles: [BlockInputInlineMarkdownStyle],
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup
    ) -> [BlockInputInlineMarkdownRange] {
        guard let firstStyle = styles.first else {
            return []
        }
        return delimiterRanges(in: text, delimiter: delimiter, style: firstStyle, excluding: excludedRangeLookup)
            .flatMap { range in
                // A supported composed delimiter, currently ***, owns the full
                // delimiter run and emits one visual range for each style.
                styles.map { style in
                    BlockInputInlineMarkdownRange(
                        style: style,
                        fullRange: range.fullRange,
                        contentRange: range.contentRange,
                        delimiterRanges: range.delimiterRanges
                    )
                }
            }
    }

    private static func delimiterRanges(
        in text: NSString,
        delimiter: String,
        style: BlockInputInlineMarkdownStyle,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup
    ) -> [BlockInputInlineMarkdownRange] {
        let delimiterCharacter = delimiterScannerCharacter(for: delimiter)
        let delimiterLength = delimiter.utf16.count
        var ranges: [BlockInputInlineMarkdownRange] = []
        var location = 0
        while location < text.length {
            guard text.character(at: location) == delimiterCharacter else {
                location += 1
                continue
            }
            let runLength = repeatedCharacterLength(in: text, from: location, character: delimiterCharacter)
            // Exact delimiter runs keep ** from also becoming *; supported
            // composed runs such as *** are parsed by their dedicated pass.
            guard runLength == delimiterLength,
                  !excludedRangeLookup.intersects(NSRange(location: location, length: delimiterLength)) else {
                location += runLength
                continue
            }
            let contentStart = location + delimiterLength
            let closingDelimiterSearch = closingDelimiterSearch(
                in: text,
                from: contentStart,
                delimiterCharacter: delimiterCharacter,
                delimiterLength: delimiterLength,
                excluding: excludedRangeLookup
            )
            if let closingLocation = closingDelimiterSearch.closingLocation, closingLocation > contentStart {
                let fullRange = NSRange(location: location, length: closingLocation - location + delimiterLength)
                let contentRange = NSRange(location: contentStart, length: closingLocation - contentStart)
                ranges.append(BlockInputInlineMarkdownRange(
                    style: style,
                    fullRange: fullRange,
                    contentRange: contentRange,
                    delimiterRanges: [
                        NSRange(location: location, length: delimiterLength),
                        NSRange(location: closingLocation, length: delimiterLength)
                    ]
                ))
                location = closingLocation + delimiterLength
            } else {
                location = max(location + runLength, closingDelimiterSearch.resumeLocation)
            }
        }
        return ranges
    }

    private static func delimiterScannerCharacter(for delimiter: String) -> unichar {
        switch delimiter {
        case singleUnderscore:
            return underscore
        case doubleTilde:
            return tilde
        case singleAsterisk, doubleAsterisk, tripleAsterisk:
            return asterisk
        default:
            return 0
        }
    }

    private static func closingDelimiterSearch(
        in text: NSString,
        from startLocation: Int,
        delimiterCharacter: unichar,
        delimiterLength: Int,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup
    ) -> BlockInputClosingSearch {
        var location = startLocation
        while location < text.length {
            let character = text.character(at: location)
            if character == lineFeed || character == carriageReturn {
                return BlockInputClosingSearch(closingLocation: nil, resumeLocation: location + 1)
            }
            guard character == delimiterCharacter else {
                location += 1
                continue
            }
            let runLength = repeatedCharacterLength(in: text, from: location, character: delimiterCharacter)
            let delimiterRange = NSRange(location: location, length: delimiterLength)
            guard runLength == delimiterLength, !excludedRangeLookup.intersects(delimiterRange) else {
                location += runLength
                continue
            }
            return BlockInputClosingSearch(closingLocation: location, resumeLocation: location)
        }
        return BlockInputClosingSearch(closingLocation: nil, resumeLocation: text.length)
    }

    private static func underlineRanges(
        in text: NSString,
        openingTag: String,
        closingTag: String,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup
    ) -> [BlockInputInlineMarkdownRange] {
        var ranges: [BlockInputInlineMarkdownRange] = []
        var location = 0
        while location < text.length {
            guard matches(openingTag, in: text, at: location),
                  !excludedRangeLookup.intersects(NSRange(location: location, length: openingTag.utf16.count)) else {
                location += 1
                continue
            }
            let contentStart = location + openingTag.utf16.count
            let closingUnderlineSearch = closingUnderlineSearch(
                in: text,
                from: contentStart,
                closingTag: closingTag,
                excluding: excludedRangeLookup
            )
            if let closingLocation = closingUnderlineSearch.closingLocation, closingLocation > contentStart {
                let fullRange = NSRange(location: location, length: closingLocation - location + closingTag.utf16.count)
                let contentRange = NSRange(location: contentStart, length: closingLocation - contentStart)
                ranges.append(BlockInputInlineMarkdownRange(
                    style: .underline,
                    fullRange: fullRange,
                    contentRange: contentRange,
                    delimiterRanges: [
                        NSRange(location: location, length: openingTag.utf16.count),
                        NSRange(location: closingLocation, length: closingTag.utf16.count)
                    ]
                ))
                location = closingLocation + closingTag.utf16.count
            } else {
                location = max(location + openingTag.utf16.count, closingUnderlineSearch.resumeLocation)
            }
        }
        return ranges
    }

    private static func closingUnderlineSearch(
        in text: NSString,
        from startLocation: Int,
        closingTag: String,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup
    ) -> BlockInputClosingSearch {
        var location = startLocation
        while location < text.length {
            let character = text.character(at: location)
            if character == lineFeed || character == carriageReturn {
                return BlockInputClosingSearch(closingLocation: nil, resumeLocation: location + 1)
            }
            let closingRange = NSRange(location: location, length: closingTag.utf16.count)
            if matches(closingTag, in: text, at: location), !excludedRangeLookup.intersects(closingRange) {
                return BlockInputClosingSearch(closingLocation: location, resumeLocation: location)
            }
            location += 1
        }
        return BlockInputClosingSearch(closingLocation: nil, resumeLocation: text.length)
    }

    private static func repeatedCharacterLength(in text: NSString, from location: Int, character: unichar) -> Int {
        var length = 0
        while location + length < text.length,
              text.character(at: location + length) == character {
            length += 1
        }
        return max(length, 1)
    }

    private static func matches(_ needle: String, in text: NSString, at location: Int) -> Bool {
        let length = needle.utf16.count
        guard location + length <= text.length else {
            return false
        }
        return text.substring(with: NSRange(location: location, length: length)).lowercased() == needle
    }

    private static func mergedByContentLocation(
        _ rangeGroups: [[BlockInputInlineMarkdownRange]]
    ) -> [BlockInputInlineMarkdownRange] {
        var indices = Array(repeating: 0, count: rangeGroups.count)
        var mergedRanges: [BlockInputInlineMarkdownRange] = []
        while let groupIndex = nextRangeGroupIndex(in: rangeGroups, indices: indices) {
            mergedRanges.append(rangeGroups[groupIndex][indices[groupIndex]])
            indices[groupIndex] += 1
        }
        return mergedRanges
    }

    private static func nextRangeGroupIndex(
        in rangeGroups: [[BlockInputInlineMarkdownRange]],
        indices: [Int]
    ) -> Int? {
        var selectedGroupIndex: Int?
        for groupIndex in rangeGroups.indices where indices[groupIndex] < rangeGroups[groupIndex].count {
            guard let currentGroupIndex = selectedGroupIndex else {
                selectedGroupIndex = groupIndex
                continue
            }
            let candidate = rangeGroups[groupIndex][indices[groupIndex]]
            let current = rangeGroups[currentGroupIndex][indices[currentGroupIndex]]
            if isOrderedBefore(candidate, current) {
                selectedGroupIndex = groupIndex
            }
        }
        return selectedGroupIndex
    }

    private static func isOrderedBefore(
        _ first: BlockInputInlineMarkdownRange,
        _ second: BlockInputInlineMarkdownRange
    ) -> Bool {
        if first.contentRange.location == second.contentRange.location {
            return first.contentRange.length > second.contentRange.length
        }
        return first.contentRange.location < second.contentRange.location
    }
}

/// Closing delimiter lookup result plus the next safe scan location.
///
/// When a line has no closing marker, later openers on that same line cannot
/// close either; resuming after the line keeps malformed rows linear to scan.
private struct BlockInputClosingSearch {
    let closingLocation: Int?
    let resumeLocation: Int
}

private struct BlockInputInlineMarkdownRangeGroups {
    let links: [BlockInputInlineMarkdownRange]
    let htmlImages: [BlockInputInlineMarkdownRange]
    let composedAsterisks: [BlockInputInlineMarkdownRange]
    let bold: [BlockInputInlineMarkdownRange]
    let strikethrough: [BlockInputInlineMarkdownRange]
    let underlineTags: [BlockInputInlineMarkdownRange]
    let insertTags: [BlockInputInlineMarkdownRange]
    let italicAsterisks: [BlockInputInlineMarkdownRange]
    let italicUnderscores: [BlockInputInlineMarkdownRange]

    var delimiterRanges: [NSRange] {
        nonRawGroups.flatMap { ranges in
            ranges.flatMap { $0.delimiterRanges }
        }
    }

    func including(
        rawSlashRanges: [BlockInputInlineMarkdownRange],
        rawFileMentionRanges: [BlockInputInlineMarkdownRange]
    ) -> [[BlockInputInlineMarkdownRange]] {
        [
            links,
            htmlImages,
            rawSlashRanges,
            rawFileMentionRanges,
            composedAsterisks,
            bold,
            strikethrough,
            underlineTags,
            insertTags,
            italicAsterisks,
            italicUnderscores
        ]
    }

    private var nonRawGroups: [[BlockInputInlineMarkdownRange]] {
        [
            links,
            htmlImages,
            composedAsterisks,
            bold,
            strikethrough,
            underlineTags,
            insertTags,
            italicAsterisks,
            italicUnderscores
        ]
    }
}
