import Foundation
import XCTest
@testable import BlockInputKit

final class BlockInputInlineFileMentionParsingTests: XCTestCase {
    func testParsesAbsolutePathMentionWhenEnabled() throws {
        let text = "See @/Users/test/.claude/RTK.md for details"
        let range = try XCTUnwrap(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            rawFileMentionChips: true
        ).first { $0.style == .rawFileMention })

        XCTAssertEqual(range.fullRange, NSRange(location: 4, length: 27))
        XCTAssertEqual(range.contentRange, range.fullRange)
        XCTAssertEqual(range.delimiterRanges, [])
        XCTAssertEqual(range.inlineChipKind(in: text), .rawFileMention)
        XCTAssertEqual(range.linkDestination, URL(fileURLWithPath: "/Users/test/.claude/RTK.md"))
        XCTAssertEqual(range.linkRawDestination, "/Users/test/.claude/RTK.md")
    }

    func testHomeRelativeMentionExpandsTildeInDestination() throws {
        let range = try XCTUnwrap(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: "Read @~/notes.md today",
            rawFileMentionChips: true
        ).first { $0.style == .rawFileMention })

        XCTAssertEqual(
            range.linkDestination,
            URL(fileURLWithPath: NSString(string: "~/notes.md").expandingTildeInPath)
        )
        XCTAssertEqual(range.linkRawDestination, "~/notes.md")
    }

    func testParsesHomeRelativePathMention() {
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: "Read @~/notes.md today",
            rawFileMentionChips: true
        ).filter { $0.style == .rawFileMention }

        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges.first?.fullRange, NSRange(location: 5, length: 11))
    }

    func testMentionsAreOffByDefault() {
        XCTAssertTrue(BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: "See @/Users/test/file.md"
        ).filter { $0.style == .rawFileMention }.isEmpty)
    }

    func testRejectsNonPathAndMidWordMentions() {
        let text = "email user@host.com, mention @channel, dangling @/ and @~/ ends"
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            rawFileMentionChips: true
        ).filter { $0.style == .rawFileMention }

        XCTAssertTrue(ranges.isEmpty)
    }

    func testMentionsAreExcludedInsideLinksAndInlineCode() {
        let text = "Skip [@/linked](demo://x) `@/code/path` but keep @/kept/path"
        let inlineCodeRanges = BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: inlineCodeRanges,
            rawFileMentionChips: true
        ).filter { $0.style == .rawFileMention }

        XCTAssertEqual(ranges.map { content(in: text, range: $0.contentRange) }, ["@/kept/path"])
    }

    func testMentionsStillApplyInsideInlineMarkdownContent() {
        // Like raw slash commands, a token that runs into a closing delimiter
        // consumes it and is excluded; mentions need trailing whitespace.
        let text = "**read @/bold/path now** and *see @~/italic/path here*"
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            rawFileMentionChips: true
        ).filter { $0.style == .rawFileMention }

        XCTAssertEqual(
            ranges.map { content(in: text, range: $0.contentRange) },
            ["@/bold/path", "@~/italic/path"]
        )
    }

    func testMentionAndRawSlashCommandPassesCoexist() {
        let text = "/table then @/some/path"
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            rawSlashCommandChips: true,
            rawFileMentionChips: true,
            slashCommandAvailability: .anywhere
        )

        XCTAssertEqual(ranges.filter { $0.style == .rawSlashCommand }.count, 1)
        XCTAssertEqual(ranges.filter { $0.style == .rawFileMention }.count, 1)
    }

    func testMentionTokenEndsAtWhitespaceAndPunctuationBoundaries() {
        let text = "open @/a/b.md (then @/c/d)"
        let ranges = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            rawFileMentionChips: true
        ).filter { $0.style == .rawFileMention }

        XCTAssertEqual(
            ranges.map { content(in: text, range: $0.contentRange) },
            ["@/a/b.md", "@/c/d)"]
        )
    }

    func testValidRawFileMentionPaths() {
        XCTAssertTrue(BlockInputCompletionTokenParsing.isValidRawFileMentionPath("/Users/test/RTK.md"))
        XCTAssertTrue(BlockInputCompletionTokenParsing.isValidRawFileMentionPath("~/notes.md"))
        XCTAssertFalse(BlockInputCompletionTokenParsing.isValidRawFileMentionPath(""))
        XCTAssertFalse(BlockInputCompletionTokenParsing.isValidRawFileMentionPath("/"))
        XCTAssertFalse(BlockInputCompletionTokenParsing.isValidRawFileMentionPath("~/"))
        XCTAssertFalse(BlockInputCompletionTokenParsing.isValidRawFileMentionPath("relative/path.md"))
        XCTAssertFalse(BlockInputCompletionTokenParsing.isValidRawFileMentionPath("/path with space.md"))
        XCTAssertFalse(BlockInputCompletionTokenParsing.isValidRawFileMentionPath("~x/notes.md"))
    }

    func testMentionChipUsesFileChipStyle() {
        let style = BlockInputStyle.default
        XCTAssertEqual(
            style.inlineChipStyle(for: .rawFileMention).fillColor,
            style.inlineChipStyle(for: .fileLink).fillColor
        )
    }
}

private func content(in text: String, range: NSRange) -> String {
    (text as NSString).substring(with: range)
}
