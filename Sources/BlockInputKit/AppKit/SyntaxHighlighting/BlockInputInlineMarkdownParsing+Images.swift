import Foundation

extension BlockInputInlineMarkdownParsing {
    /// Scans raw `<img …>` tags into `.inlineImage` ranges. Markdown `![alt](src)`
    /// images are handled by the link scanner, which already owns that grammar;
    /// `avoiding` carries the link spans so a tag inside one cannot double-emit.
    static func htmlInlineImageRanges(
        in text: NSString,
        excluding excludedRangeLookup: BlockInputExcludedRangeLookup,
        avoiding avoidedRanges: [NSRange] = []
    ) -> [BlockInputInlineMarkdownRange] {
        guard (text as String).localizedCaseInsensitiveContains("<img") else {
            return []
        }
        return BlockInputImageSyntaxParser.htmlImageMatches(in: text as String).compactMap { match in
            guard match.image.source.isRemoteInlineImageSource,
                  !excludedRangeLookup.intersects(match.range),
                  !avoidedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else {
                return nil
            }
            let hiddenRange = NSRange(location: match.range.location + 1, length: match.range.length - 1)
            return BlockInputInlineMarkdownRange(
                style: .inlineImage,
                fullRange: match.range,
                contentRange: NSRange(location: match.range.location, length: 1),
                delimiterRanges: [hiddenRange],
                linkRawDestination: match.image.source,
                image: match.image
            )
        }
    }
}

extension String {
    /// Inline rendering is limited to remote sources; file and relative paths keep
    /// their existing chip/plain-text behavior so local-image UX stays host-owned.
    var isRemoteInlineImageSource: Bool {
        guard let url = URL(string: self),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}
