import Foundation

extension BlockInputMarkdownImporter {
    static func imageBlocks(
        bySplitting block: BlockInputBlock,
        imageParsingMode: BlockInputMarkdownImageParsingMode = .imageBlocks
    ) -> [BlockInputBlock] {
        guard imageParsingMode == .imageBlocks,
              block.kind.supportsImageSyntaxSplitting else {
            return [block]
        }
        // Images alone on their line become standalone blocks. Remote images sharing
        // a line with text stay in the source so they can render inline (GitHub
        // parity); local/relative sources keep splitting because inline rendering
        // is remote-only and their syntax would otherwise read as raw text.
        let matches = BlockInputImageSyntaxParser.imageMatches(in: block.text)
            .filter { $0.isAloneOnLine(in: block.text) || !$0.image.source.isRemoteInlineImageSource }
        guard !matches.isEmpty else {
            return [block]
        }
        var output: [BlockInputBlock] = []
        var cursor = 0
        let text = block.text as NSString
        for match in matches {
            if match.range.location > cursor {
                var fragment = text.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                if NSMaxRange(match.range) < text.length {
                    fragment = fragment.droppingOneTrailingSeparator()
                }
                appendTextFragment(fragment, from: block, to: &output)
            }
            output.append(BlockInputBlock(kind: .image(match.image)))
            cursor = NSMaxRange(match.range)
            if cursor < text.length,
               let scalar = UnicodeScalar(text.character(at: cursor)),
               CharacterSet.whitespacesAndNewlines.contains(scalar) {
                cursor += 1
            }
        }
        if cursor < text.length {
            appendTextFragment(text.substring(from: cursor), from: block, to: &output)
        }
        return output.isEmpty ? [block] : output
    }

    static func markdown(for image: BlockInputImage) -> String {
        if image.sourceStyle == .markdown, image.width == nil, image.height == nil {
            return "![\(escapedMarkdownAltText(image.altText))](\(escapedMarkdownImageDestination(image.source)))"
        }
        var attributes = [
            "src=\"\(escapedHTMLAttribute(image.source))\""
        ]
        if !image.altText.isEmpty {
            attributes.append("alt=\"\(escapedHTMLAttribute(image.altText))\"")
        }
        if let width = image.width {
            attributes.append("width=\"\(width)\"")
        }
        if let height = image.height {
            attributes.append("height=\"\(height)\"")
        }
        return "<img \(attributes.joined(separator: " ")) />"
    }

    static func imageBlock(fromHTMLLine line: String) -> BlockInputBlock? {
        guard let match = BlockInputImageSyntaxParser.singleHTMLImage(in: line) else {
            return nil
        }
        return BlockInputBlock(kind: .image(match.image))
    }

    private static func appendTextFragment(
        _ fragment: String,
        from block: BlockInputBlock,
        to output: inout [BlockInputBlock]
    ) {
        guard !fragment.isEmpty else {
            return
        }
        output.append(BlockInputBlock(
            kind: block.kind,
            text: fragment,
            indentationLevel: block.indentationLevel,
            lineIndentationLevels: block.lineIndentationLevels
        ))
    }

    private static func escapedMarkdownAltText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func escapedMarkdownImageDestination(_ source: String) -> String {
        if source.contains(where: { $0.isWhitespace || $0 == "(" || $0 == ")" || $0 == "<" || $0 == ">" || $0 == "\\" }) {
            let escapedSource = source
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "<", with: "\\<")
                .replacingOccurrences(of: ">", with: "\\>")
            return "<\(escapedSource)>"
        }
        return source
    }

    private static func escapedHTMLAttribute(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

enum BlockInputImageSyntaxParser {
    static func imageMatches(in text: String) -> [BlockInputImageMatch] {
        let markdownMatches = markdownImageMatches(in: text)
        let htmlMatches = htmlImageMatches(in: text)
        return (markdownMatches + htmlMatches)
            .sorted { $0.range.location < $1.range.location }
            .nonOverlapping()
    }

    static func singleHTMLImage(in line: String) -> BlockInputImageMatch? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = htmlImageMatches(in: trimmed)
        guard matches.count == 1,
              matches[0].range.location == 0,
              matches[0].range.length == (trimmed as NSString).length else {
            return nil
        }
        return matches[0]
    }

    private static func markdownImageMatches(in text: String) -> [BlockInputImageMatch] {
        markdownImageMatches(in: text, pattern: #"!\[((?:\\.|[^\]\n])*)\]\(<((?:\\.|[^>\n])+)>\)"#) +
            markdownImageMatches(in: text, pattern: #"!\[((?:\\.|[^\]\n])*)\]\(((?:\\.|[^)\n])+)\)"#)
    }

    private static func markdownImageMatches(in text: String, pattern: String) -> [BlockInputImageMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges == 3 else {
                return nil
            }
            let altText = nsText.substring(with: match.range(at: 1)).blockInputUnescapedLinkLabel
            let source = nsText.substring(with: match.range(at: 2))
                .blockInputUnescapedLinkDestination
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else {
                return nil
            }
            return BlockInputImageMatch(
                range: match.range,
                image: BlockInputImage(source: source, altText: altText, sourceStyle: .markdown)
            )
        }
    }

    static func htmlImageMatches(in text: String) -> [BlockInputImageMatch] {
        let pattern = #"<img\b([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges == 2 else {
                return nil
            }
            let attributes = attributes(in: nsText.substring(with: match.range(at: 1)))
            guard let source = attributes["src"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !source.isEmpty else {
                return nil
            }
            return BlockInputImageMatch(
                range: match.range,
                image: BlockInputImage(
                    source: source,
                    altText: attributes["alt"] ?? "",
                    width: attributes["width"].flatMap(Int.init),
                    height: attributes["height"].flatMap(Int.init),
                    sourceStyle: .html
                )
            )
        }
    }

    private static func attributes(in source: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }
        let nsSource = source as NSString
        var attributes: [String: String] = [:]
        for match in regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length)) where match.numberOfRanges == 3 {
            let name = nsSource.substring(with: match.range(at: 1)).lowercased()
            var value = nsSource.substring(with: match.range(at: 2))
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            attributes[name] = value
        }
        return attributes
    }
}

struct BlockInputImageMatch: Equatable {
    let range: NSRange
    let image: BlockInputImage

    /// True when the match's line contains nothing but the match and whitespace,
    /// which is what qualifies an image for standalone-block extraction.
    func isAloneOnLine(in text: String) -> Bool {
        let nsText = text as NSString
        guard range.location >= 0, NSMaxRange(range) <= nsText.length else {
            return false
        }
        let lineRange = nsText.lineRange(for: range)
        let leading = NSRange(location: lineRange.location, length: range.location - lineRange.location)
        let trailing = NSRange(location: NSMaxRange(range), length: NSMaxRange(lineRange) - NSMaxRange(range))
        return nsText.isWhitespaceOnly(in: leading) && nsText.isWhitespaceOnly(in: trailing)
    }
}

private extension NSString {
    func isWhitespaceOnly(in range: NSRange) -> Bool {
        guard range.length > 0 else {
            return true
        }
        for offset in range.location..<NSMaxRange(range) {
            guard let scalar = UnicodeScalar(character(at: offset)),
                  CharacterSet.whitespacesAndNewlines.contains(scalar) else {
                return false
            }
        }
        return true
    }
}

private extension Array where Element == BlockInputImageMatch {
    func nonOverlapping() -> [BlockInputImageMatch] {
        var output: [BlockInputImageMatch] = []
        var upperBound = 0
        for match in self where match.range.location >= upperBound {
            output.append(match)
            upperBound = NSMaxRange(match.range)
        }
        return output
    }
}

private extension String {
    func droppingOneTrailingSeparator() -> String {
        guard let last = unicodeScalars.last,
              CharacterSet.whitespacesAndNewlines.contains(last) else {
            return self
        }
        return String(dropLast())
    }
}

extension BlockInputBlockKind {
    var supportsImageSyntaxSplitting: Bool {
        switch self {
        case .paragraph, .heading, .quote, .bulletedListItem, .numberedListItem, .checklistItem:
            return true
        case .code, .horizontalRule, .frontMatter, .table, .image, .rawMarkdown:
            return false
        }
    }
}
