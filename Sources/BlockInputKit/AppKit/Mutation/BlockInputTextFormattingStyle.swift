import Foundation

/// A formatted block and the per-block source ranges needed to restore the logical selection.
struct FormattedBlock {
    let block: BlockInputBlock
    let adjustedRanges: [BlockInputBlockID: NSRange]
}

/// Source formatting rules for one inline style shortcut.
struct TextFormattingStyle {
    let openingDelimiter: String
    let closingDelimiter: String
    let markdownStyle: BlockInputInlineMarkdownStyle

    init(_ shortcut: BlockInputTextFormattingShortcut) {
        switch shortcut {
        case .bold:
            openingDelimiter = "**"
            closingDelimiter = "**"
            markdownStyle = .bold
        case .italic:
            openingDelimiter = "_"
            closingDelimiter = "_"
            markdownStyle = .italic
        case .underline:
            openingDelimiter = "<u>"
            closingDelimiter = "</u>"
            markdownStyle = .underline
        case .strikethrough:
            openingDelimiter = "~~"
            closingDelimiter = "~~"
            markdownStyle = .strikethrough
        }
    }

    func formattedRange(in text: String, selectedRange: NSRange) -> FormattingRange? {
        if let enclosingRange = enclosingFormattedRange(in: text, selectedRange: selectedRange) {
            return enclosingRange
        }
        if selectedRangeIncludesDelimiters(in: text, selectedRange: selectedRange) {
            return FormattingRange(
                openingRange: NSRange(location: selectedRange.location, length: openingLength),
                closingRange: NSRange(location: NSMaxRange(selectedRange) - closingLength, length: closingLength),
                contentRange: NSRange(
                    location: selectedRange.location + openingLength,
                    length: selectedRange.length - openingLength - closingLength
                ),
                selectedContentRange: NSRange(
                    location: selectedRange.location + openingLength,
                    length: selectedRange.length - openingLength - closingLength
                )
            )
        }
        if selectionIsSurroundedByDelimiters(in: text, selectedRange: selectedRange) {
            return FormattingRange(
                openingRange: NSRange(location: selectedRange.location - openingLength, length: openingLength),
                closingRange: NSRange(location: NSMaxRange(selectedRange), length: closingLength),
                contentRange: selectedRange,
                selectedContentRange: selectedRange
            )
        }
        return nil
    }

    func addingFormatting(in text: String, selectedRange: NSRange) -> FormattingEdit? {
        guard formattedRange(in: text, selectedRange: selectedRange) == nil else {
            return nil
        }
        let mutableText = NSMutableString(string: text)
        mutableText.insert(closingDelimiter, at: NSMaxRange(selectedRange))
        mutableText.insert(openingDelimiter, at: selectedRange.location)
        return FormattingEdit(
            text: mutableText as String,
            selectedRange: NSRange(location: selectedRange.location + openingLength, length: selectedRange.length)
        )
    }

    func removingFormatting(in text: String, selectedRange: NSRange) -> FormattingEdit? {
        guard let formattedRange = formattedRange(in: text, selectedRange: selectedRange) else {
            return nil
        }
        let mutableText = NSMutableString(string: text)
        mutableText.deleteCharacters(in: formattedRange.closingRange)
        mutableText.deleteCharacters(in: formattedRange.openingRange)
        return FormattingEdit(
            text: mutableText as String,
            selectedRange: NSRange(
                location: formattedRange.selectedContentRange.location - formattedRange.openingRange.length,
                length: formattedRange.selectedContentRange.length
            )
        )
    }

    private var openingLength: Int {
        openingDelimiter.utf16.count
    }

    private var closingLength: Int {
        closingDelimiter.utf16.count
    }

    private func selectedRangeIncludesDelimiters(in text: String, selectedRange: NSRange) -> Bool {
        guard selectedRange.location >= 0,
              selectedRange.length > openingLength + closingLength else {
            return false
        }
        let nsText = text as NSString
        guard NSMaxRange(selectedRange) <= nsText.length else {
            return false
        }
        let openingRange = NSRange(location: selectedRange.location, length: openingLength)
        let closingRange = NSRange(location: NSMaxRange(selectedRange) - closingLength, length: closingLength)
        return nsText.substring(with: openingRange) == openingDelimiter
            && nsText.substring(with: closingRange) == closingDelimiter
    }

    private func selectionIsSurroundedByDelimiters(in text: String, selectedRange: NSRange) -> Bool {
        guard selectedRange.location >= openingLength else {
            return false
        }
        let nsText = text as NSString
        guard NSMaxRange(selectedRange) + closingLength <= nsText.length else {
            return false
        }
        let openingRange = NSRange(location: selectedRange.location - openingLength, length: openingLength)
        let closingRange = NSRange(location: NSMaxRange(selectedRange), length: closingLength)
        return nsText.substring(with: openingRange) == openingDelimiter
            && nsText.substring(with: closingRange) == closingDelimiter
    }

    private func enclosingFormattedRange(in text: String, selectedRange: NSRange) -> FormattingRange? {
        let nsText = text as NSString
        let ranges = blockInputFormattingInlineMarkdownRanges(in: text)
        return ranges
            .filter { $0.style == markdownStyle }
            .compactMap { range in
                let selectedContentRange: NSRange
                if range.contentRange.contains(selectedRange) {
                    selectedContentRange = selectedRange
                } else if NSEqualRanges(selectedRange, range.fullRange) {
                    selectedContentRange = range.contentRange
                } else {
                    return nil
                }
                guard let removalRanges = removalRanges(for: range, in: nsText) else {
                    return nil
                }
                return FormattingRange(
                    openingRange: removalRanges.opening,
                    closingRange: removalRanges.closing,
                    contentRange: range.contentRange,
                    selectedContentRange: selectedContentRange
                )
            }
            .min { lhs, rhs in lhs.contentRange.length < rhs.contentRange.length }
    }

    private func removalRanges(
        for range: BlockInputInlineMarkdownRange,
        in text: NSString
    ) -> (opening: NSRange, closing: NSRange)? {
        guard range.delimiterRanges.count >= 2 else {
            return nil
        }
        let openingRange = range.delimiterRanges[0]
        let closingRange = range.delimiterRanges[1]
        let openingDelimiter = text.substring(with: openingRange).lowercased()
        let closingDelimiter = text.substring(with: closingRange).lowercased()
        guard openingDelimiter == closingDelimiter,
              openingDelimiter == "***" else {
            return (openingRange, closingRange)
        }
        // `***text***` represents nested bold and italic. Remove only the delimiter slice
        // for the requested style so toggling one style preserves the other.
        switch markdownStyle {
        case .bold:
            return (
                opening: NSRange(location: openingRange.location, length: 2),
                closing: NSRange(location: closingRange.location + 1, length: 2)
            )
        case .italic:
            return (
                opening: NSRange(location: openingRange.location + 2, length: 1),
                closing: NSRange(location: closingRange.location, length: 1)
            )
        case .underline, .strikethrough, .link, .rawSlashCommand, .rawFileMention:
            return (openingRange, closingRange)
        }
    }
}

/// Source ranges for an existing formatting span and the selected content inside it.
struct FormattingRange {
    let openingRange: NSRange
    let closingRange: NSRange
    let contentRange: NSRange
    let selectedContentRange: NSRange
}

/// Edited block text plus the selected range that still maps to the user's original content.
struct FormattingEdit {
    let text: String
    let selectedRange: NSRange
}

extension String {
    /// Clamps AppKit UTF-16 selections and optionally trims hidden formatting delimiters from visible text selections.
    func blockInputFormattingClampedRange(
        _ range: NSRange,
        trimsHiddenDelimiters: Bool,
        fileBaseURL: URL? = nil
    ) -> NSRange {
        let text = self as NSString
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), max(text.length - location, 0))
        let clampedRange = NSRange(location: location, length: length)
        guard trimsHiddenDelimiters else {
            return clampedRange
        }
        return blockInputTrimmingInlineMarkdownDelimiterEdges(from: clampedRange, fileBaseURL: fileBaseURL)
    }

    private func blockInputTrimmingInlineMarkdownDelimiterEdges(from range: NSRange, fileBaseURL: URL? = nil) -> NSRange {
        var location = range.location
        var upperBound = NSMaxRange(range)
        let delimiterRanges = blockInputFormattingInlineMarkdownRanges(in: self, fileBaseURL: fileBaseURL)
            .flatMap(\.delimiterRanges)
            .sorted { lhs, rhs in
                if lhs.location == rhs.location {
                    return lhs.length > rhs.length
                }
                return lhs.location < rhs.location
            }
        while location < upperBound,
              let leadingDelimiter = delimiterRanges.first(where: { $0.contains(location) || $0.location == location }),
              NSMaxRange(leadingDelimiter) <= upperBound {
            location = NSMaxRange(leadingDelimiter)
        }
        while location < upperBound,
              let trailingDelimiter = delimiterRanges.last(where: { $0.contains(upperBound - 1) || NSMaxRange($0) == upperBound }),
              trailingDelimiter.location >= location {
            upperBound = trailingDelimiter.location
        }
        return NSRange(location: location, length: max(upperBound - location, 0))
    }
}

private extension NSRange {
    func contains(_ range: NSRange) -> Bool {
        location <= range.location && NSMaxRange(range) <= NSMaxRange(self)
    }

    func contains(_ offset: Int) -> Bool {
        location <= offset && offset < NSMaxRange(self)
    }
}

private func blockInputFormattingInlineMarkdownRanges(in text: String, fileBaseURL: URL? = nil) -> [BlockInputInlineMarkdownRange] {
    let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
    return BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: inlineCodeRanges, fileBaseURL: fileBaseURL)
}
