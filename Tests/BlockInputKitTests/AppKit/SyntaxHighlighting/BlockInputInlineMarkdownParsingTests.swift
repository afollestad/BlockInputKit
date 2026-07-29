import XCTest
@testable import BlockInputKit

final class BlockInputInlineMarkdownParsingTests: XCTestCase {
    func testParsesSupportedInlineMarkdownRangesWithMultiWordContent() {
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: "*some text* **bold text** <u>underlined text</u> ~~struck text~~"
        )

        XCTAssertEqual(ranges.map(\.style), [.italic, .bold, .underline, .strikethrough])
        XCTAssertEqual(ranges.map { content(in: "*some text* **bold text** <u>underlined text</u> ~~struck text~~", range: $0.contentRange) }, [
            "some text",
            "bold text",
            "underlined text",
            "struck text"
        ])
    }

    func testParsesMultipleSpans() {
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "*one* and *two*")

        XCTAssertEqual(ranges.map(\.contentRange), [
            NSRange(location: 1, length: 3),
            NSRange(location: 11, length: 3)
        ])
    }

    func testParsesSupportedInlineLinks() throws {
        let text = "Open [web](https://example.com) and [file](file:///tmp/demo.md)"
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text)
            .filter { $0.style == .link }

        XCTAssertEqual(ranges.map { content(in: text, range: $0.contentRange) }, ["web", "file"])
        XCTAssertEqual(ranges.map { $0.linkDestination?.scheme }, ["https", "file"])
        XCTAssertEqual(ranges.first?.delimiterRanges, [
            NSRange(location: 5, length: 1),
            NSRange(location: 9, length: 2),
            NSRange(location: 11, length: 19),
            NSRange(location: 30, length: 1)
        ])
    }

    func testParsesImageMarkdownLinks() throws {
        let text = "Open ![alt](https://example.com/image.png) and ![file](file:///tmp/image.png)"
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text)
        // Remote image sources render inline; file destinations keep their chip rendering.
        let imageRange = try XCTUnwrap(ranges.first { $0.style == .inlineImage })
        let fileRange = try XCTUnwrap(ranges.first { $0.style == .link })

        XCTAssertEqual(content(in: text, range: imageRange.fullRange), "![alt](https://example.com/image.png)")
        XCTAssertEqual(content(in: text, range: imageRange.contentRange), "!")
        XCTAssertEqual(imageRange.image, BlockInputImage(source: "https://example.com/image.png", altText: "alt"))
        XCTAssertEqual(imageRange.delimiterRanges.count, 1)
        XCTAssertEqual(
            imageRange.delimiterRanges.first.map { content(in: text, range: $0) },
            "[alt](https://example.com/image.png)"
        )
        XCTAssertEqual(content(in: text, range: fileRange.contentRange), "file")
        XCTAssertEqual(fileRange.linkDestination?.scheme, "file")
        XCTAssertEqual(fileRange.inlineChipKind(in: text), .fileLink)
    }

    func testParsesEscapedLinkLabelDelimitersAsHiddenSource() throws {
        let text = "Open [a\\[b\\]c](https://example.com)"
        let range = try XCTUnwrap(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text)
            .first { $0.style == .link })

        XCTAssertEqual(content(in: text, range: range.contentRange), "a\\[b\\]c")
        XCTAssertTrue(range.delimiterRanges.contains(NSRange(location: 7, length: 1)))
        XCTAssertTrue(range.delimiterRanges.contains(NSRange(location: 10, length: 1)))
    }

    func testParsesEscapedLinkDestinationParentheses() throws {
        let text = "Open [docs](https://example.com/a\\(b\\))"
        let range = try XCTUnwrap(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text)
            .first { $0.style == .link })

        XCTAssertEqual(content(in: text, range: range.contentRange), "docs")
        XCTAssertEqual(range.linkDestination?.absoluteString, "https://example.com/a(b)")
    }

    func testParsesAngleBracketFileLinkDestinations() throws {
        let text = "Open [file](<file:///tmp/a%20b(1).md>)"
        let range = try XCTUnwrap(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text)
            .first { $0.style == .link })

        XCTAssertEqual(content(in: text, range: range.contentRange), "file")
        XCTAssertEqual(range.linkDestination?.absoluteString, "file:///tmp/a%20b(1).md")
    }

    func testParsesSlashCommandChipLinksWithHostURIs() throws {
        let text = "Run [/table](host-app://commands/table)"
        let range = try XCTUnwrap(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text)
            .first { $0.style == .link })

        XCTAssertEqual(range.linkDestination?.absoluteString, "host-app://commands/table")
        XCTAssertEqual(range.inlineChipKind(in: text), .slashCommand)
        XCTAssertEqual(range.slashCommandChipLabel(in: text), "/table")
    }

    func testParsesRawSlashCommandChipsWhenEnabled() throws {
        let text = "Run /table now"
        let range = try XCTUnwrap(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            rawSlashCommandChips: true,
            slashCommandAvailability: .anywhere
        ).first { $0.style == .rawSlashCommand })

        XCTAssertEqual(range.fullRange, NSRange(location: 4, length: 6))
        XCTAssertEqual(range.contentRange, range.fullRange)
        XCTAssertEqual(range.delimiterRanges, [])
        XCTAssertEqual(range.inlineChipKind(in: text), .rawSlashCommand)
        XCTAssertEqual(range.slashCommandChipLabel(in: text), "/table")
    }

    func testRawSlashCommandChipsFollowDocumentStartAvailability() {
        XCTAssertEqual(
            BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
                in: "/table and /quote",
                rawSlashCommandChips: true,
                slashCommandAvailability: .documentStart,
                isDocumentStartBlock: true
            ).filter { $0.style == .rawSlashCommand }.map(\.contentRange),
            [NSRange(location: 0, length: 6)]
        )
        XCTAssertTrue(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: "/table",
            rawSlashCommandChips: true,
            slashCommandAvailability: .documentStart,
            isDocumentStartBlock: false
        ).filter { $0.style == .rawSlashCommand }.isEmpty)
    }

    func testRawSlashCommandChipsAreExcludedInsideLinksImagesInlineCodeAndInlineMarkdownDelimiters() {
        let text = "Skip [/link](demo://command) ![/image](image.png) `/code` <u>underline</u>, <ins>inserted</ins> but keep /table"
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: inlineCodeRanges,
            rawSlashCommandChips: true,
            slashCommandAvailability: .anywhere
        ).filter { $0.style == .rawSlashCommand }

        XCTAssertEqual(ranges.map { content(in: text, range: $0.contentRange) }, ["/table"])
    }

    func testRawSlashCommandChipsStillApplyInsideInlineMarkdownContent() {
        let text = "<u>run /table here</u> and *use /quote here*"
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            rawSlashCommandChips: true,
            slashCommandAvailability: .anywhere
        )
        .filter { $0.style == .rawSlashCommand }

        XCTAssertEqual(ranges.map { content(in: text, range: $0.contentRange) }, ["/table", "/quote"])
    }

    func testNonSlashCustomSchemeLinksStayUnsupported() {
        let text = "Run [table](host-app://commands/table)"

        XCTAssertTrue(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text).filter { $0.style == .link }.isEmpty)
    }

    func testFileLinksTakeChipPrecedenceOverSlashLabels() throws {
        let text = "Open [/tmp/file.md](file:///tmp/file.md)"
        let range = try XCTUnwrap(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text)
            .first { $0.style == .link })

        XCTAssertEqual(range.inlineChipKind(in: text), .fileLink)
    }

    func testAngleBracketLinkDestinationsUnescapeEscapedAngles() throws {
        let text = #"Open [file](<file:///tmp/A\>B.md>)"#
        let range = try XCTUnwrap(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text)
            .first { $0.style == .link })

        XCTAssertEqual(range.linkRawDestination, "file:///tmp/A>B.md")
        XCTAssertEqual(range.inlineChipKind(in: text), .fileLink)
    }

    func testReportsLinkSourceRangesForCompletionExclusion() {
        let text = [
            "Open [@read](mailto:user@example.com)",
            "[file](@read)",
            "[@empty]()",
            "[](@dest)",
            "![@image](file:///tmp/image.png)",
            "![image](@dest)"
        ].joined(separator: " and ")
        let sourceRanges = BlockInputInlineMarkdownParsing.linkSourceRanges(in: text)

        XCTAssertEqual(sourceRanges.map { content(in: text, range: $0) }, [
            "[@read](mailto:user@example.com)",
            "[file](@read)",
            "[@empty]()",
            "[](@dest)",
            "![@image](file:///tmp/image.png)",
            "![image](@dest)"
        ])
    }

    func testRejectsUnsupportedInlineLinks() {
        let examples = [
            "[] (https://example.com)",
            "[](https://example.com)",
            "[text]()",
            "[text](mailto:user@example.com)",
            "[text](https://)",
            "[text](https:example.com)",
            "[text](file:)",
            "[   ](https://example.com)",
            "[text](https://example.com\nnext)",
            "[[nested](https://example.com)](https://outer.com)",
            "[a[b](https://inner.com)](https://outer.com)"
        ]

        for example in examples {
            XCTAssertTrue(
                BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: example).filter { $0.style == .link }.isEmpty,
                "Expected no link ranges for \(example)"
            )
        }
    }

    func testExcludesInlineLinksInsideInlineCode() {
        let text = "`[code](https://example.com)` [text](https://example.com)"
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: inlineCodeRanges)
            .filter { $0.style == .link }

        XCTAssertEqual(ranges.map { content(in: text, range: $0.contentRange) }, ["text"])
    }

    func testBoldPrecedenceSkipsSingleStarInsideDoubleStarDelimiters() {
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "**bold text**")

        XCTAssertEqual(ranges, [
            BlockInputInlineMarkdownRange(
                style: .bold,
                fullRange: NSRange(location: 0, length: 13),
                contentRange: NSRange(location: 2, length: 9),
                delimiterRanges: [
                    NSRange(location: 0, length: 2),
                    NSRange(location: 11, length: 2)
                ]
            )
        ])
    }

    func testUnderscoreDelimitersMatchAsteriskBehavior() {
        let text = "_italic text_"
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text)

        XCTAssertEqual(ranges.map(\.style), [.italic])
        XCTAssertEqual(ranges.map { content(in: text, range: $0.contentRange) }, [
            "italic text"
        ])
        XCTAssertEqual(ranges.map(\.delimiterRanges), [
            [NSRange(location: 0, length: 1), NSRange(location: 12, length: 1)]
        ])
    }

    func testAllowsComposedOverlappingStyles() {
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "*some **bold** text*")

        XCTAssertEqual(ranges.map(\.style), [.italic, .bold])
        XCTAssertEqual(ranges.map { content(in: "*some **bold** text*", range: $0.contentRange) }, [
            "some **bold** text",
            "bold"
        ])
    }

    func testParsesTripleAsteriskAsBoldAndItalic() {
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "***bold and italic***")
        let expectedContentRange = NSRange(location: 3, length: 15)
        let expectedDelimiterRanges = [
            NSRange(location: 0, length: 3),
            NSRange(location: 18, length: 3)
        ]

        XCTAssertEqual(ranges, [
            BlockInputInlineMarkdownRange(
                style: .bold,
                fullRange: NSRange(location: 0, length: 21),
                contentRange: expectedContentRange,
                delimiterRanges: expectedDelimiterRanges
            ),
            BlockInputInlineMarkdownRange(
                style: .italic,
                fullRange: NSRange(location: 0, length: 21),
                contentRange: expectedContentRange,
                delimiterRanges: expectedDelimiterRanges
            )
        ])
    }

    func testParsesNestedInlineMarkdownExamples() {
        let examples: [InlineMarkdownNestedParsingCase] = [
            InlineMarkdownNestedParsingCase(
                text: "**_bold and italic_**",
                styles: [.bold, .italic],
                contents: ["_bold and italic_", "bold and italic"]
            ),
            InlineMarkdownNestedParsingCase(
                text: "**<u>bold and underlined</u>**",
                styles: [.bold, .underline],
                contents: ["<u>bold and underlined</u>", "bold and underlined"]
            ),
            InlineMarkdownNestedParsingCase(
                text: "~~*strikethrough and italic*~~",
                styles: [.strikethrough, .italic],
                contents: ["*strikethrough and italic*", "strikethrough and italic"]
            )
        ]

        for example in examples {
            let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: example.text)

            XCTAssertEqual(ranges.map(\.style), example.styles, "Unexpected styles for \(example.text).")
            XCTAssertEqual(
                ranges.map { content(in: example.text, range: $0.contentRange) },
                example.contents,
                "Unexpected content ranges for \(example.text)."
            )
        }
    }

    func testIgnoresInvalidSpans() {
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "*"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "**"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "****"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "____"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "__bold text__"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "~~~struck~~~"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "___text___"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "<u></u>"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "<u class=\"x\">text</u>"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "<ins></ins>"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "<ins class=\"x\">text</ins>"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "<ins>text</u>"), [])
    }

    func testDoesNotCrossLineBoundaries() {
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "*some\ntext*"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "**some\ntext**"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "_some\ntext_"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "<u>some\ntext</u>"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "<ins>some\ntext</ins>"), [])
        XCTAssertEqual(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "~~some\ntext~~"), [])
    }

    func testExcludesInlineCodeRanges() throws {
        let text = "Use `*code*` and *text*"
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: inlineCodeRanges)

        XCTAssertEqual(ranges.map(\.style), [.italic])
        XCTAssertEqual(content(in: text, range: try XCTUnwrap(ranges.first?.contentRange)), "text")
    }

    func testExcludesInlineCodeRangesForUnderscores() throws {
        let text = "Use `_code_` and _text_"
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: inlineCodeRanges)

        XCTAssertEqual(ranges.map(\.style), [.italic])
        XCTAssertEqual(content(in: text, range: try XCTUnwrap(ranges.first?.contentRange)), "text")
    }

    func testExcludesInlineCodeRangesForComposedDelimiters() {
        let text = "Use `***code***` and ***text***"
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: inlineCodeRanges)

        XCTAssertEqual(ranges.map(\.style), [.bold, .italic])
        XCTAssertEqual(ranges.map { content(in: text, range: $0.contentRange) }, ["text", "text"])
    }

    func testLargeInputWithManyExcludedRangesFindsOnlyOutsideSpans() throws {
        let chunkCount = 2_500
        let text = (0..<chunkCount)
            .map { "`*code \($0)*` *text \($0)*" }
            .joined(separator: " ")
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)

        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: inlineCodeRanges)

        XCTAssertEqual(ranges.count, chunkCount)
        XCTAssertEqual(content(in: text, range: try XCTUnwrap(ranges.first?.contentRange)), "text 0")
        XCTAssertEqual(content(in: text, range: try XCTUnwrap(ranges.last?.contentRange)), "text \(chunkCount - 1)")
    }

    func testLargeInputWithUnmatchedOpenersDoesNotCreateRanges() {
        let text = Array(repeating: "<u>unclosed", count: 2_500).joined(separator: " ")

        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text)

        XCTAssertEqual(ranges, [])
    }

    func testParsesOuterSpansAroundInlineCodeContent() throws {
        let text = "*some `code` text*"
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: inlineCodeRanges)

        XCTAssertEqual(ranges.map(\.style), [.italic])
        XCTAssertEqual(content(in: text, range: try XCTUnwrap(ranges.first?.contentRange)), "some `code` text")
    }

    func testUnderlineTagsAreCaseInsensitiveExactTags() throws {
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: "<U>some text</U> and <INS>inserted text</INS>")

        XCTAssertEqual(ranges.map(\.style), [.underline, .underline])
        XCTAssertEqual(ranges.map { content(in: "<U>some text</U> and <INS>inserted text</INS>", range: $0.contentRange) }, [
            "some text",
            "inserted text"
        ])
    }
}

private func content(in text: String, range: NSRange) -> String {
    (text as NSString).substring(with: range)
}

private struct InlineMarkdownNestedParsingCase {
    let text: String
    let styles: [BlockInputInlineMarkdownStyle]
    let contents: [String]
}
