import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewUndoTests: XCTestCase {
    func testViewUndoAndRedoStructuralEditPublishesDocumentChange() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        var publishedDocuments: [BlockInputDocument] = []
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            undoController: undoController,
            onDocumentChange: { publishedDocuments.append($0) }
        ))
        view.focus(blockID: blockID, utf16Offset: 5)
        _ = view.insertBlockBelowCurrentBlock()

        let undo = view.undoStructuralEdit()
        XCTAssertEqual(view.document.blocks.map(\.id), [blockID])
        XCTAssertEqual(undo?.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)))
        XCTAssertEqual(publishedDocuments.last, view.document)

        let redo = view.redoStructuralEdit()
        XCTAssertEqual(view.document.blocks.count, 2)
        XCTAssertEqual(redo?.selection, .cursor(BlockInputCursor(blockID: view.document.blocks[1].id, utf16Offset: 0)))
        XCTAssertEqual(publishedDocuments.last, view.document)
    }

    func testChecklistToggleUsesStructuralUndoStack() {
        let blockID = BlockInputBlockID(rawValue: "check")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .checklistItem(isChecked: false), text: "Done")
            ]),
            undoController: undoController
        ))
        view.focus(blockID: blockID, utf16Offset: 0)

        _ = view.toggleChecklistItem()
        let undo = view.undoStructuralEdit()
        let redo = view.redoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Toggle Checklist")
        XCTAssertEqual(redo?.actionName, "Toggle Checklist")
        XCTAssertEqual(view.document.blocks[0].kind, .checklistItem(isChecked: true))
    }

    func testSelectedHorizontalRuleDeleteUsesStructuralUndoStack() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let ruleID = BlockInputBlockID(rawValue: "rule")
        let secondID = BlockInputBlockID(rawValue: "second")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: ruleID, kind: .horizontalRule),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            undoController: undoController
        ))
        view.applySelection(.blocks([ruleID]), notify: false)

        _ = view.deleteSelectedHorizontalRuleForBackspaceOrDelete()
        let undo = view.undoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Delete Block")
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, ruleID, secondID])
        XCTAssertEqual(view.document.blocks[1].kind, .horizontalRule)
        XCTAssertEqual(undo?.selection, .blocks([ruleID]))

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(redo?.actionName, "Delete Block")
        XCTAssertEqual(view.document.blocks.map(\.id), [firstID, secondID])
        XCTAssertEqual(redo?.selection, .cursor(BlockInputCursor(blockID: firstID, utf16Offset: 5)))
    }

    func testUnwrapBlockUsesStructuralUndoStack() throws {
        let blockID = BlockInputBlockID(rawValue: "quote")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .quote, text: "Quoted")
            ]),
            undoController: undoController
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))

        let undo = view.undoStructuralEdit()
        XCTAssertEqual(view.document.blocks[0].kind, .quote)
        XCTAssertEqual(view.document.blocks[0].text, "Quoted")

        let redo = view.redoStructuralEdit()

        XCTAssertEqual(undo?.actionName, "Unformat Block")
        XCTAssertEqual(redo?.actionName, "Unformat Block")
        XCTAssertEqual(view.document.blocks[0].kind, .paragraph)
        XCTAssertEqual(view.document.blocks[0].text, ">Quoted")
    }

    func testUndoStructuralEditWithNilSelectionCanRefocusEditor() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            undoController: undoController
        ))
        _ = view.insertBlockBelowCurrentBlock()

        let undo = view.undoStructuralEdit()
        view.focusEditor()

        XCTAssertNil(undo?.selection)
        XCTAssertEqual(view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testViewUndoAndRedoTextEditPublishesDocumentChange() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        var publishedDocuments: [BlockInputDocument] = []
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            undoController: undoController,
            onDocumentChange: { publishedDocuments.append($0) }
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.string = "Edited"
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let undo = view.undoTextEditInActiveBlock()
        XCTAssertEqual(view.document.blocks[0].text, "First")
        XCTAssertEqual(undo?.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)))
        XCTAssertEqual(publishedDocuments.last, view.document)

        let redo = view.redoTextEditInActiveBlock()
        XCTAssertEqual(view.document.blocks[0].text, "Edited")
        XCTAssertEqual(redo?.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 6)))
        XCTAssertEqual(publishedDocuments.last, view.document)
    }

    func testCommandZAndCommandShiftZRouteTextUndoFromTextFocus() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            undoController: BlockInputUndoController()
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.string = "Edited"
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandZEvent()))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "First")

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandShiftZEvent()))

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Edited")
    }

    func testCommandZFromTextFocusFallsBackToStructuralUndo() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            undoController: BlockInputUndoController()
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        mounted.view.focus(blockID: blockID, utf16Offset: 5)
        _ = mounted.view.insertBlockBelowCurrentBlock()

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandZEvent()))

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [blockID])

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandShiftZEvent()))

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
    }

    func testCommandZUndoesStructuralEditBeforeEarlierTextUndo() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Test word")
            ]),
            undoController: BlockInputUndoController()
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)

        _ = item.textView(textView, shouldChangeTextIn: NSRange(location: 4, length: 5), replacementString: "")
        textView.string = "Test"
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))

        XCTAssertEqual(mounted.view.document.blocks[0].indentationLevel, 1)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Test")

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandZEvent()))
        XCTAssertEqual(mounted.view.document.blocks[0].indentationLevel, 0)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Test")

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandZEvent()))
        XCTAssertEqual(mounted.view.document.blocks[0].indentationLevel, 0)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Test word")
    }

    func testCommandShiftZRedoesStructuralUndoBeforeEarlierTextUndo() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Test word")
            ]),
            undoController: BlockInputUndoController()
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        _ = item.textView(textView, shouldChangeTextIn: NSRange(location: 4, length: 5), replacementString: "")
        textView.string = "Test"
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(mounted.view.document.blocks[0].indentationLevel, 1)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Test")

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandZEvent()))
        XCTAssertEqual(mounted.view.document.blocks[0].indentationLevel, 1)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Test word")

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandZEvent()))
        XCTAssertEqual(mounted.view.document.blocks[0].indentationLevel, 0)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Test word")

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandShiftZEvent()))
        XCTAssertEqual(mounted.view.document.blocks[0].indentationLevel, 1)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Test word")

        XCTAssertTrue(textView.performKeyEquivalent(with: try commandShiftZEvent()))
        XCTAssertEqual(mounted.view.document.blocks[0].indentationLevel, 1)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Test")
    }

    func testCommandZAndCommandShiftZRouteStructuralUndoFromEditorFocus() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            undoController: BlockInputUndoController()
        )
        mounted.view.focus(blockID: blockID, utf16Offset: 5)
        _ = mounted.view.insertBlockBelowCurrentBlock()
        mounted.window.makeFirstResponder(mounted.view)

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandZEvent()))

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [blockID])

        XCTAssertTrue(mounted.view.performKeyEquivalent(with: try commandShiftZEvent()))

        XCTAssertEqual(mounted.view.document.blocks.count, 2)
    }

    func testUndoAndRedoActionsRouteThroughCustomUndoStacks() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            undoController: BlockInputUndoController()
        )
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        mounted.window.makeFirstResponder(textView)
        textView.string = "Edited"
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertTrue(textView.tryToPerform(#selector(BlockInputTextView.blockInputUndo(_:)), with: nil))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "First")

        XCTAssertTrue(textView.tryToPerform(#selector(BlockInputTextView.blockInputRedo(_:)), with: nil))
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Edited")
    }

    func testUndoTextEditRestoresVisibleTextSelectionAfterReload() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            undoController: undoController
        )
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 1, length: 3)
        )), notify: false)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        _ = item.textView(textView, shouldChangeTextIn: NSRange(location: 1, length: 3), replacementString: "dit")
        textView.string = "Edited"
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        _ = mounted.view.undoTextEditInActiveBlock()
        waitForNextMainLoopTurn()

        let restoredItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertEqual(restoredItem.testingTextView?.selectedRange(), NSRange(location: 1, length: 3))
    }

    func testFocusEditorPreservesVisibleTextSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            undoController: BlockInputUndoController()
        )
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 1, length: 3)
        )), notify: false)

        mounted.view.focusEditor()

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertEqual(item.testingTextView?.selectedRange(), NSRange(location: 1, length: 3))
    }

    func testFocusEditorPreservesVisibleBlockSelectionAsEditorResponder() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            undoController: BlockInputUndoController()
        )
        mounted.view.applySelection(.blocks([blockID]), notify: false)

        mounted.view.focusEditor()

        XCTAssertEqual(mounted.view.selection, .blocks([blockID]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
    }

    func testWindowCanMakeEditorFirstResponderWithBlockSelection() {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            undoController: BlockInputUndoController()
        )
        mounted.view.applySelection(.blocks([blockID]), notify: false)

        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))
        XCTAssertEqual(mounted.view.selection, .blocks([blockID]))
        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
    }

}
