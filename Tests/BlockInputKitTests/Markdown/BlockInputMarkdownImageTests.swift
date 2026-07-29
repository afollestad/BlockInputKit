import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputMarkdownImageTests: XCTestCase {
    func testParsesMarkdownImageBlock() {
        let document = BlockInputDocument(markdown: "![Alt Text](https://example.com/image.png)")

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(
            document.blocks[0].kind,
            .image(BlockInputImage(source: "https://example.com/image.png", altText: "Alt Text"))
        )
        XCTAssertEqual(document.blocks[0].text, "")
        XCTAssertEqual(document.markdown, "![Alt Text](https://example.com/image.png)")
    }

    func testParsesHTMLImageBlockWithDimensions() {
        let document = BlockInputDocument(markdown: "<img height=\"200\" alt=\"Alt Text\" src=\"https://example.com/image.png\" width=\"320\" />")

        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(
            document.blocks[0].kind,
            .image(BlockInputImage(
                source: "https://example.com/image.png",
                altText: "Alt Text",
                width: 320,
                height: 200,
                sourceStyle: .html
            ))
        )
        XCTAssertEqual(
            document.markdown,
            "<img src=\"https://example.com/image.png\" alt=\"Alt Text\" width=\"320\" height=\"200\" />"
        )
    }

    func testInlineMarkdownImageSplitsParagraph() {
        let document = BlockInputDocument(markdown: "Before ![Alt](image.png) after")

        XCTAssertEqual(document.blocks.map(\.kind), [
            .paragraph,
            .image(BlockInputImage(source: "image.png", altText: "Alt")),
            .paragraph
        ])
        XCTAssertEqual(document.blocks.map(\.text), ["Before", "", "after"])
    }

    func testPreserveSourceTextKeepsMarkdownAndHTMLImagesEditable() {
        let source = """
        Before ![Alt](image.png) after

        <img src="remote.png" alt="Remote" width="50" />
        """

        let document = BlockInputDocument(markdown: source, imageParsingMode: .preserveSourceText)

        XCTAssertEqual(document.blocks.map(\.kind), [.paragraph, .paragraph])
        XCTAssertEqual(document.blocks.map(\.text), [
            "Before ![Alt](image.png) after",
            "<img src=\"remote.png\" alt=\"Remote\" width=\"50\" />"
        ])
        XCTAssertEqual(document.markdown, source)
    }

    func testMarkdownImageWithEscapedDestinationRoundTrips() {
        let document = BlockInputDocument(blocks: [
            BlockInputBlock(kind: .image(BlockInputImage(source: "assets/Photo <1>\\final>draft.png", altText: "A [photo]")))
        ])

        XCTAssertEqual(document.markdown, #"![A \[photo\]](<assets/Photo \<1\>\\final\>draft.png>)"#)
        XCTAssertEqual(BlockInputDocument(markdown: document.markdown).blocks.map(\.kind), document.blocks.map(\.kind))
    }

    func testInlineHTMLImageSplitsHeading() {
        let document = BlockInputDocument(markdown: "## Before <img src=\"image.png\" alt=\"Alt\" /> after")

        XCTAssertEqual(document.blocks.map(\.kind), [
            .heading(level: 2),
            .image(BlockInputImage(source: "image.png", altText: "Alt", sourceStyle: .html)),
            .heading(level: 2)
        ])
        XCTAssertEqual(document.blocks.map(\.text), ["Before", "", "after"])
    }

    func testMultipleInlineImagesSplitIntoAlternatingBlocks() {
        let document = BlockInputDocument(markdown: "A ![One](one.png) B <img src=\"two.png\" /> C")

        XCTAssertEqual(document.blocks.map(\.kind), [
            .paragraph,
            .image(BlockInputImage(source: "one.png", altText: "One")),
            .paragraph,
            .image(BlockInputImage(source: "two.png", sourceStyle: .html)),
            .paragraph
        ])
        XCTAssertEqual(document.blocks.map(\.text), ["A", "", "B", "", "C"])
    }

    func testRemoteImageSharingLineWithTextStaysInlineSourceText() {
        let source = "Before ![Alt](https://example.com/image.png) after"
        let document = BlockInputDocument(markdown: source)

        XCTAssertEqual(document.blocks.map(\.kind), [.paragraph])
        XCTAssertEqual(document.blocks.map(\.text), [source])
        XCTAssertEqual(document.markdown, source)
    }

    func testRemoteHTMLImageSharingLineWithTextStaysInlineSourceText() {
        let source = "Before <img src=\"https://example.com/image.png\" alt=\"Alt\" /> after"
        let document = BlockInputDocument(markdown: source)

        XCTAssertEqual(document.blocks.map(\.kind), [.paragraph])
        XCTAssertEqual(document.blocks.map(\.text), [source])
    }

    func testRemoteImageAloneOnItsLineSplitsIntoImageBlock() {
        let document = BlockInputDocument(markdown: "Text\n![Alt](https://example.com/image.png)\nMore")

        XCTAssertEqual(document.blocks.map(\.kind), [
            .paragraph,
            .image(BlockInputImage(source: "https://example.com/image.png", altText: "Alt")),
            .paragraph
        ])
        XCTAssertEqual(document.blocks.map(\.text), ["Text", "", "More"])
    }

    func testImageSyntaxInsideUnsupportedBlocksStaysLiteral() {
        let source = """
        ```swift
        ![Alt](image.png)
        ```

        <div>![Alt](image.png)</div>
        """

        let document = BlockInputDocument(markdown: source)

        XCTAssertEqual(document.blocks.map(\.kind), [.code(language: "swift"), .rawMarkdown])
        XCTAssertEqual(document.blocks[0].text, "![Alt](image.png)")
        XCTAssertEqual(document.blocks[1].text, "<div>![Alt](image.png)</div>")
    }

    func testStreamingImportMatchesImageParsing() async throws {
        let source = """
        Before ![Alt](image.png) after

        <img src="remote.png" alt="Remote" width="50" />
        """
        var reader = ImageMarkdownLineReader(markdown: source)

        let streamed = try await BlockInputDocument.readingMarkdown(from: &reader)
        let parsed = BlockInputDocument(markdown: source)

        XCTAssertEqual(streamed.blocks.map(\.kind), parsed.blocks.map(\.kind))
        XCTAssertEqual(streamed.blocks.map(\.text), parsed.blocks.map(\.text))
        XCTAssertEqual(streamed.markdown, parsed.markdown)
    }

    func testStreamingImportPreservesImageSourceTextWhenRequested() async throws {
        let source = """
        Before ![Alt](image.png) after

        <img src="remote.png" alt="Remote" width="50" />
        """
        var reader = ImageMarkdownLineReader(markdown: source)

        let streamed = try await BlockInputDocument.readingMarkdown(
            from: &reader,
            imageParsingMode: .preserveSourceText
        )
        let parsed = await BlockInputDocument.parsingMarkdown(source, imageParsingMode: .preserveSourceText)

        XCTAssertEqual(streamed.blocks.map(\.kind), [.paragraph, .paragraph])
        XCTAssertEqual(streamed.blocks.map(\.text), parsed.blocks.map(\.text))
        XCTAssertEqual(streamed.markdown, source)
    }
}

private struct ImageMarkdownLineReader: BlockInputMarkdownLineReader {
    private let lines: [String]
    private var index = 0

    init(markdown: String) {
        self.lines = BlockInputLineBreaks.lines(in: markdown)
    }

    mutating func readMarkdownLine() async throws -> String? {
        guard index < lines.count else {
            return nil
        }
        defer { index += 1 }
        return lines[index]
    }
}
