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
