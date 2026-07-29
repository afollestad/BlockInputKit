import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputInlineImageParsingTests: XCTestCase {
    func testParsesRemoteHTMLImageWithDeclaredDimensions() throws {
        let text = "Badge <img src=\"https://example.com/p1.png\" alt=\"P1\" width=\"40\" height=\"20\"> alert"
        let range = try XCTUnwrap(inlineImageRange(in: text))

        XCTAssertEqual(content(in: text, range: range.contentRange), "<")
        XCTAssertEqual(
            content(in: text, range: range.fullRange),
            "<img src=\"https://example.com/p1.png\" alt=\"P1\" width=\"40\" height=\"20\">"
        )
        XCTAssertEqual(
            range.image,
            BlockInputImage(source: "https://example.com/p1.png", altText: "P1", width: 40, height: 20, sourceStyle: .html)
        )
    }

    func testLocalHTMLImageStaysPlainText() {
        let text = "Badge <img src=\"local.png\" alt=\"P1\"> alert"

        XCTAssertNil(inlineImageRange(in: text))
    }

    func testRelativeMarkdownImageStaysPlainText() {
        let text = "Badge ![P1](images/p1.png) alert"

        XCTAssertTrue(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text).isEmpty)
    }

    func testFileMarkdownImageKeepsLinkChipRendering() throws {
        let text = "Badge ![P1](file:///tmp/p1.png) alert"
        let range = try XCTUnwrap(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text).first)

        XCTAssertNil(inlineImageRange(in: text))
        XCTAssertEqual(range.style, .link)
        XCTAssertEqual(range.inlineChipKind(in: text), .fileLink)
    }

    func testImageSyntaxInsideInlineCodeIsExcluded() {
        let text = "Use `![P1](https://example.com/p1.png)` verbatim"
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)

        XCTAssertNil(inlineImageRange(in: text, excluding: inlineCodeRanges))
    }

    func testInlineImagesFlagDisabledKeepsLegacyRendering() {
        let text = "Badge ![P1](https://example.com/p1.png) alert"
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, inlineImages: false)

        XCTAssertEqual(ranges.map(\.style), [.link])
    }

    func testParsesLinkedImageAsOneInlineImageSpan() throws {
        let text = "CI [![Badge](https://example.com/badge.png)](https://example.com/run) status"
        let range = try XCTUnwrap(inlineImageRange(in: text))

        XCTAssertEqual(
            content(in: text, range: range.fullRange),
            "[![Badge](https://example.com/badge.png)](https://example.com/run)"
        )
        XCTAssertEqual(content(in: text, range: range.contentRange), "[")
        XCTAssertEqual(range.image, BlockInputImage(source: "https://example.com/badge.png", altText: "Badge"))
        XCTAssertEqual(range.linkDestination?.absoluteString, "https://example.com/run")
        XCTAssertEqual(
            BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text).count,
            1
        )
    }

    func testImageInsideBoldSpanCoexistsWithBoldRange() throws {
        let text = "**![P1](https://example.com/p1.png) Fix the trailer**"
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text)

        XCTAssertEqual(ranges.map(\.style).sorted(by: sortStyles), [.bold, .inlineImage].sorted(by: sortStyles))
        let imageRange = try XCTUnwrap(ranges.first { $0.style == .inlineImage })
        XCTAssertEqual(content(in: text, range: imageRange.fullRange), "![P1](https://example.com/p1.png)")
    }

    func testHTMLImageInsideMarkdownImageDestinationDoesNotDoubleEmit() {
        let text = "One ![alt](https://example.com/a.png) two <img src=\"https://example.com/b.png\">"
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text)

        XCTAssertEqual(ranges.filter { $0.style == .inlineImage }.count, 2)
    }

    private func inlineImageRange(
        in text: String,
        excluding excludedRanges: [NSRange] = []
    ) -> BlockInputInlineMarkdownRange? {
        BlockInputInlineMarkdownParsing.inlineMarkdownRanges(in: text, excluding: excludedRanges)
            .first { $0.style == .inlineImage }
    }

    private func content(in text: String, range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }

    private func sortStyles(_ lhs: BlockInputInlineMarkdownStyle, _ rhs: BlockInputInlineMarkdownStyle) -> Bool {
        String(describing: lhs) < String(describing: rhs)
    }
}
