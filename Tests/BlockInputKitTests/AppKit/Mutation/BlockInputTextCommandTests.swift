import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputTextCommandTests: XCTestCase {
    func testFirstCommandASelectionTypingReplacesFocusedText() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))
        textView.keyDown(with: try keyDownEvent(keyCode: 0, characters: "Z"))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["Z", "Second"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 1)))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 0))
        XCTAssertTrue(mounted.window.firstResponder === textView)
    }

    func testEscalatedAllBlockSelectionTypingReplacesBlocks() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        let firstItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(firstItem.testingTextView)
        mounted.window.makeFirstResponder(textView)
        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))
        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 0, characters: "Z"))
        runSelectionRestoreCycle()

        XCTAssertEqual(mounted.view.document.blocks, [BlockInputBlock(id: firstID, text: "Z")])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 1)))
        let replacementItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let replacementTextView = try XCTUnwrap(replacementItem.testingTextView)
        XCTAssertTrue(mounted.window.firstResponder === replacementTextView)
        XCTAssertEqual(replacementTextView.selectedRange(), NSRange(location: 1, length: 0))
        XCTAssertTrue(replacementItem.testingSelectionBackgroundView.isHidden)
    }

    func testDocumentSelectAllTypingReplacesBlocks() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            selectAllBehavior: .document
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandAEvent()))
        mounted.view.keyDown(with: try keyDownEvent(keyCode: 2, characters: "D"))
        runSelectionRestoreCycle()

        XCTAssertEqual(mounted.view.document.blocks, [BlockInputBlock(id: firstID, text: "D")])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 1)))
    }

    func testEditorOwnedTextSelectionTypingReplacesPartialSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Hello world")
        ])
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 6, length: 5))),
            notify: true
        )

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 7, characters: "X"))
        runSelectionRestoreCycle()

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Hello X")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 7)))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertTrue(mounted.window.firstResponder === textView)
        XCTAssertEqual(textView.string, "Hello X")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 7, length: 0))
    }

    func testMixedSelectionTypingDeletesSelectionAndInsertsAtLeadingCaret() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "Alpha"),
            BlockInputBlock(id: secondID, text: "Middle"),
            BlockInputBlock(id: thirdID, text: "Omega")
        ])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 2, length: 3)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 2))
        )), notify: true)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 7, characters: "X"))

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [firstID])
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["AlXega"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 3)))
    }

    func testMixedSelectionTypingUsesDocumentOrderLeadingCaret() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "abcd"),
            BlockInputBlock(id: secondID, text: "efgh"),
            BlockInputBlock(id: thirdID, text: "ijkl")
        ])
        mounted.view.applySelection(.mixed(BlockInputMixedSelection(
            blockIDs: [secondID],
            leadingTextRange: BlockInputTextRange(blockID: firstID, range: NSRange(location: 1, length: 2)),
            trailingTextRange: BlockInputTextRange(blockID: thirdID, range: NSRange(location: 0, length: 2))
        )), notify: true)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        mounted.view.keyDown(with: try keyDownEvent(keyCode: 8, characters: "C"))

        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["aCkl"])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 2)))
    }

    func testSecondKeystrokeContinuesFromRestoredCaret() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: true)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))
        mounted.view.keyDown(with: try keyDownEvent(keyCode: 0, characters: "A"))
        runSelectionRestoreCycle()
        let textView = try XCTUnwrap(mounted.window.firstResponder as? BlockInputTextView)

        textView.keyDown(with: try keyDownEvent(keyCode: 11, characters: "B"))

        XCTAssertEqual(mounted.view.document.blocks, [BlockInputBlock(id: firstID, text: "AB")])
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 2)))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testTypingOverBlockSelectionRestoresUndoState() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]), undoController: undoController)
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: true)
        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))
        mounted.view.keyDown(with: try keyDownEvent(keyCode: 0, characters: "Z"))

        let undo = mounted.view.undoStructuralEdit()

        XCTAssertNotNil(undo)
        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [firstID, secondID])
        XCTAssertEqual(mounted.view.document.blocks.map(\.text), ["First", "Second"])
        XCTAssertEqual(mounted.view.selection, .blocks([firstID, secondID]))
    }

    func testSingleBlockSelectionTypingPublishesBlockReplacementToStore() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.blocks([blockID]), notify: true)

        view.keyDown(with: try keyDownEvent(keyCode: 0, characters: "Z"))

        XCTAssertEqual(store.document.blocks, [BlockInputBlock(id: blockID, text: "Z")])
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.replaceBlockIDs, [blockID])
    }

    func testMultiBlockSelectionTypingPublishesDocumentReplacementToCompleteStore() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let store = CountingDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ]))
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.blocks([firstID, secondID]), notify: true)

        view.keyDown(with: try keyDownEvent(keyCode: 0, characters: "Z"))

        XCTAssertEqual(store.document.blocks, [BlockInputBlock(id: firstID, text: "Z")])
        XCTAssertEqual(store.replaceDocumentCount, 1)
        XCTAssertEqual(store.replaceBlockIDs, [])
    }

    func testMultiBlockSelectionTypingFailsClosedForIncompleteProgressiveStore() async throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let thirdID = BlockInputBlockID(rawValue: "third")
        let store = BlockInputProgressiveMemoryDocumentStore(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second"),
            BlockInputBlock(id: thirdID, text: "Third")
        ], initialLimit: 2)
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.blocks([firstID, secondID]), notify: true)

        view.keyDown(with: try keyDownEvent(keyCode: 0, characters: "Z"))
        let snapshot = try await store.completeDocumentSnapshot(limit: 10)

        XCTAssertFalse(store.isComplete)
        XCTAssertEqual(view.document.blocks.map(\.text), ["First", "Second"])
        XCTAssertEqual(snapshot.blocks.map(\.text), ["First", "Second", "Third"])
        XCTAssertEqual(view.selection, .blocks([firstID, secondID]))
    }

    func testNonPrintingKeyDoesNotReplaceBlockSelection() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])))
        view.applySelection(.blocks([firstID, secondID]), notify: true)

        view.keyDown(with: try keyDownEvent(keyCode: 122, characters: "\u{F704}"))

        XCTAssertEqual(view.document.blocks.map(\.text), ["First", "Second"])
        XCTAssertEqual(view.selection, .blocks([firstID, secondID]))
    }

    func testDeleteCommandRemovesEmptyBlockThroughDelegatePath() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[1],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        XCTAssertEqual(view.document.blocks.map(\.id), [firstID])
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)))
    }

    func testSelectAllCommandEscalatesThroughDelegatePath() throws {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: firstID, text: "First"),
            BlockInputBlock(id: secondID, text: "Second")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)

        textView.doCommand(by: #selector(NSResponder.selectAll(_:)))
        textView.doCommand(by: #selector(NSResponder.selectAll(_:)))

        XCTAssertEqual(view.selection, .blocks([firstID, secondID]))
    }

}

@MainActor
private func runSelectionRestoreCycle() {
    waitForNextMainLoopTurn()
}
