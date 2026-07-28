import AppKit
import Foundation
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputFileMentionRenderingTests: XCTestCase {
    func testMountedMentionChipDrawsBackgroundRect() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", kind: .paragraph, text: "See @/Users/test/RTK.md now")
            ]),
            rawFileMentionChips: true
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertFalse(textView.inlineChipBackgroundRectsForTesting().isEmpty)
    }

    func testCommandClickOnMentionChipOpensFileWithoutModal() throws {
        let mounted = try mountedMentionEditor()
        var openedURL: URL?
        mounted.view.linkURLOpener = {
            openedURL = $0
            return true
        }
        let click = try mentionChipClick(in: mounted.view)

        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "paragraph",
            selectedRange: NSRange(location: click.range.contentRange.location, length: 0),
            clickedLinkRange: click.range,
            event: try mouseDownEvent(
                location: click.windowLocation,
                windowNumber: mounted.window.windowNumber,
                modifierFlags: .command
            )
        ))

        XCTAssertEqual(openedURL, URL(fileURLWithPath: "/Users/test/RTK.md"))
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testPlainClickOnMentionChipShowsFileMentionModal() throws {
        let mounted = try mountedMentionEditor()
        let click = try mentionChipClick(in: mounted.view)

        XCTAssertTrue(mounted.view.handleLinkClick(
            blockID: "paragraph",
            selectedRange: NSRange(location: click.range.contentRange.location, length: 0),
            clickedLinkRange: click.range,
            event: try mouseDownEvent(location: click.windowLocation, windowNumber: mounted.window.windowNumber)
        ))

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertTrue(modal.textField.isHidden)
        XCTAssertEqual(modal.urlField.stringValue, "/Users/test/RTK.md")
    }

    func testMentionModalSaveRewritesLiteralTokenNotLink() throws {
        let mounted = try mountedMentionEditor()
        let click = try mentionChipClick(in: mounted.view)
        _ = mounted.view.handleLinkClick(
            blockID: "paragraph",
            selectedRange: NSRange(location: click.range.contentRange.location, length: 0),
            clickedLinkRange: click.range,
            event: try mouseDownEvent(location: click.windowLocation, windowNumber: mounted.window.windowNumber)
        )
        let modal = try XCTUnwrap(mounted.view.linkModalView)

        modal.urlField.stringValue = "~/other/NOTES.md"
        modal.saveButton.performClick(nil)

        XCTAssertEqual(mounted.view.document.blocks.first?.text, "See @~/other/NOTES.md now")
        XCTAssertNil(mounted.view.linkModalView)
    }

    func testMentionModalSaveRejectsInvalidPath() throws {
        let mounted = try mountedMentionEditor()
        let click = try mentionChipClick(in: mounted.view)
        _ = mounted.view.handleLinkClick(
            blockID: "paragraph",
            selectedRange: NSRange(location: click.range.contentRange.location, length: 0),
            clickedLinkRange: click.range,
            event: try mouseDownEvent(location: click.windowLocation, windowNumber: mounted.window.windowNumber)
        )
        let modal = try XCTUnwrap(mounted.view.linkModalView)

        modal.urlField.stringValue = "not-a-path"
        modal.saveButton.performClick(nil)

        XCTAssertEqual(mounted.view.document.blocks.first?.text, "See @/Users/test/RTK.md now")
    }

    private func mountedMentionEditor() throws -> (view: BlockInputView, window: NSWindow) {
        makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", kind: .paragraph, text: "See @/Users/test/RTK.md now")
            ]),
            rawFileMentionChips: true
        ))
    }

    private func mentionChipClick(
        in view: BlockInputView
    ) throws -> (range: BlockInputInlineMarkdownRange, windowLocation: NSPoint) {
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let chipRect = try XCTUnwrap(textView.inlineChipBackgroundRectsForTesting().first)
        let windowLocation = textView.convert(NSPoint(x: chipRect.midX, y: chipRect.midY), to: nil)
        let range = try XCTUnwrap(textView.inlineChipRange(atWindowLocation: windowLocation))
        return (range, windowLocation)
    }

    func testMountedMentionRendersPlainTextWhenDisabled() throws {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", kind: .paragraph, text: "See @/Users/test/RTK.md now")
            ])
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)

        XCTAssertTrue(textView.inlineChipBackgroundRectsForTesting().isEmpty)
    }
}
