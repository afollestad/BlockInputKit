import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputProvisionalTextTests: XCTestCase {
    func testCumulativeCursorUpdatesCommitAsOneUndoableTextEdit() throws {
        let blockID: BlockInputBlockID = "paragraph"
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(
            document: BlockInputDocument(blocks: [BlockInputBlock(id: blockID, text: "Hello world")]),
            undoController: undoController
        )
        mounted.view.applySelection(
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)),
            notify: true
        )

        let session = try startedSession(in: mounted.view)
        XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: " t"), .applied)
        XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: " there"), .applied)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Hello there world")
        XCTAssertEqual(mounted.view.finishProvisionalTextReplacement(session, disposition: .commit), .committed)

        let undo = try XCTUnwrap(mounted.view.undoTextEditInActiveBlock())
        XCTAssertEqual(undo.actionName, "Text Edit")
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Hello world")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)))

        XCTAssertNotNil(mounted.view.redoTextEditInActiveBlock())
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Hello there world")
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 11)))
        XCTAssertNil(mounted.view.undoStructuralEdit())
    }

    func testTextSelectionCancelRestoresExactBlockSelectionAndNoUndo() throws {
        let blockID: BlockInputBlockID = "paragraph"
        let range = NSRange(location: 6, length: 6)
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Hello cruel world")
        ])
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: blockID, range: range)),
            notify: true
        )

        let session = try startedSession(in: mounted.view)
        XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: "kind "), .applied)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "Hello kind world")
        XCTAssertEqual(mounted.view.finishProvisionalTextReplacement(session, disposition: .cancel), .cancelled)

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Hello cruel world")
        XCTAssertEqual(mounted.view.selection, .text(BlockInputTextRange(blockID: blockID, range: range)))
        XCTAssertNil(mounted.view.undoTextEditInActiveBlock())
        XCTAssertNil(mounted.view.undoStructuralEdit())
    }

    func testCancelRestoresNilSelectionAfterUsingFallbackDocumentEndCaret() throws {
        let blockID: BlockInputBlockID = "paragraph"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ])
        XCTAssertNil(mounted.view.selection)

        let session = try startedSession(in: mounted.view)
        XCTAssertEqual(
            mounted.view.selection,
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5))
        )
        XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: " world"), .applied)
        XCTAssertEqual(mounted.view.finishProvisionalTextReplacement(session, disposition: .cancel), .cancelled)

        XCTAssertEqual(mounted.view.document.blocks[0].text, "Hello")
        XCTAssertNil(mounted.view.selection)
        XCTAssertFalse(mounted.view.isEditorFirstResponder)
        XCTAssertFalse(mounted.window.firstResponder is BlockInputTextView)
        XCTAssertNil(mounted.view.undoTextEditInActiveBlock())
    }

    func testForeignMarkedTextViewIsNotCommittedWhenSessionBegins() throws {
        let blockID: BlockInputBlockID = "paragraph"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ])
        mounted.view.applySelection(
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)),
            notify: true
        )
        let foreignTextView = ProvisionalForeignMarkedTextView(frame: .zero)
        mounted.view.addSubview(foreignTextView)
        XCTAssertTrue(mounted.window.makeFirstResponder(foreignTextView))

        _ = try startedSession(in: mounted.view)

        XCTAssertFalse(foreignTextView.didUnmarkText)
    }

    func testAuthorizedSessionContinuesAfterEditorBecomesReadOnly() throws {
        let blockID: BlockInputBlockID = "paragraph"
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ]))
        let undoController = BlockInputUndoController()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: store,
            undoController: undoController
        ))
        mounted.view.applySelection(
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)),
            notify: true
        )
        let session = try startedSession(in: mounted.view)

        mounted.view.configure(BlockInputConfiguration(
            documentStore: store,
            isEditable: false,
            undoController: undoController
        ))
        XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: " dictated"), .applied)
        XCTAssertEqual(store.block(withID: blockID)?.text, "Hello dictated")
        XCTAssertEqual(mounted.view.finishProvisionalTextReplacement(session, disposition: .commit), .committed)

        XCTAssertEqual(
            mounted.view.beginProvisionalTextReplacement(),
            .unavailable(.editorReadOnly)
        )
    }

    func testListIndentationIsRecomputedFromOriginalRangeForEachUpdate() throws {
        let blockID: BlockInputBlockID = "list"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(
                id: blockID,
                kind: .bulletedListItem,
                text: "one\ntwo",
                lineIndentationLevels: [0, 2]
            )
        ])
        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 4, length: 3))),
            notify: true
        )
        let session = try startedSession(in: mounted.view)

        XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: "spoken\nwords"), .applied)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "one\nspoken\nwords")
        XCTAssertEqual(mounted.view.document.blocks[0].lineIndentationLevels, [0, 2, 2])

        XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: "voice"), .applied)
        XCTAssertEqual(mounted.view.document.blocks[0].text, "one\nvoice")
        XCTAssertEqual(mounted.view.document.blocks[0].lineIndentationLevels, [0, 2])
        XCTAssertEqual(mounted.view.finishProvisionalTextReplacement(session, disposition: .commit), .committed)
    }

    func testSynchronousAndDelayedSelfAuthoredStoreEchoesDoNotInvalidateSession() async throws {
        for echoMode in [ProvisionalEchoStore.EchoMode.synchronous, .delayed] {
            let blockID: BlockInputBlockID = "paragraph"
            let store = ProvisionalEchoStore(
                blocks: [BlockInputBlock(id: blockID, text: "Hello")],
                echoMode: echoMode
            )
            let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
            mounted.view.applySelection(
                .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)),
                notify: true
            )
            let session = try startedSession(in: mounted.view)

            XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: " one"), .applied)
            if echoMode == .delayed {
                await Task.yield()
            }
            XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: " two"), .applied)
            if echoMode == .delayed {
                await Task.yield()
            }
            XCTAssertEqual(mounted.view.finishProvisionalTextReplacement(session, disposition: .commit), .committed)
            XCTAssertEqual(store.block(withID: blockID)?.text, "Hello two")
        }
    }

    func testExternalStoreReplacementAndDeletionInvalidatePromptly() throws {
        for mutation in [ExternalMutation.replacement, .deletion] {
            let blockID: BlockInputBlockID = "paragraph"
            let store = ProvisionalEchoStore(
                blocks: [BlockInputBlock(id: blockID, text: "Hello")],
                echoMode: .none
            )
            let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
            mounted.view.applySelection(
                .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)),
                notify: true
            )
            let session = try startedSession(in: mounted.view)

            switch mutation {
            case .replacement:
                store.externallyReplace(BlockInputBlock(id: blockID, text: "External"))
            case .deletion:
                store.externallyDelete(blockID)
            }

            XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: " voice"), .invalidated)
            XCTAssertEqual(
                mounted.view.finishProvisionalTextReplacement(session, disposition: .commit),
                .invalidated
            )
        }
    }

    func testReentrantStoreReplacementInvalidatesBeforeMutatingNewEditorState() throws {
        let blockID: BlockInputBlockID = "paragraph"
        let originalStore = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ]))
        let replacementStore = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Replacement")
        ]))
        var mountedView: BlockInputView?
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: originalStore,
            onDocumentMutation: { _ in
                mountedView?.configure(BlockInputConfiguration(documentStore: replacementStore))
            }
        ))
        mountedView = mounted.view
        mounted.view.applySelection(
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)),
            notify: true
        )
        let session = try startedSession(in: mounted.view)

        XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: " voice"), .invalidated)
        XCTAssertEqual(mounted.view.documentStore?.block(withID: blockID)?.text, "Replacement")
        XCTAssertEqual(mounted.view.document.blocks.first?.text, "Replacement")
    }

    func testSelectionCallbackStoreReplacementInvalidatesUpdateBeforeTouchingNewEditorState() throws {
        let blockID: BlockInputBlockID = "paragraph"
        let originalStore = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ]))
        let replacementStore = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Replacement")
        ]))
        var mountedView: BlockInputView?
        var replacesStore = false
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: originalStore,
            onSelectionChange: { _ in
                guard replacesStore else { return }
                mountedView?.configure(BlockInputConfiguration(documentStore: replacementStore))
            }
        ))
        mountedView = mounted.view
        mounted.view.applySelection(
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)),
            notify: true
        )
        let session = try startedSession(in: mounted.view)
        replacesStore = true

        XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: " voice"), .invalidated)
        XCTAssertEqual(mounted.view.documentStore?.block(withID: blockID)?.text, "Replacement")
        XCTAssertEqual(mounted.view.document.blocks.first?.text, "Replacement")
        XCTAssertEqual(mounted.view.visibleBlockItemForTesting(at: 0)?.representedBlockID, blockID)
    }

    func testSelectionCallbackStoreReplacementInvalidatesCancelBeforeTouchingNewEditorState() throws {
        let blockID: BlockInputBlockID = "paragraph"
        let originalStore = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ]))
        let replacementStore = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Replacement")
        ]))
        var mountedView: BlockInputView?
        var replacesStore = false
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: originalStore,
            onSelectionChange: { _ in
                guard replacesStore else { return }
                mountedView?.configure(BlockInputConfiguration(documentStore: replacementStore))
            }
        ))
        mountedView = mounted.view
        mounted.view.applySelection(
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)),
            notify: true
        )
        let session = try startedSession(in: mounted.view)
        XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: " voice"), .applied)
        replacesStore = true

        XCTAssertEqual(
            mounted.view.finishProvisionalTextReplacement(session, disposition: .cancel),
            .invalidated
        )
        XCTAssertEqual(mounted.view.documentStore?.block(withID: blockID)?.text, "Replacement")
        XCTAssertEqual(mounted.view.document.blocks.first?.text, "Replacement")
        XCTAssertEqual(mounted.view.visibleBlockItemForTesting(at: 0)?.representedBlockID, blockID)
    }

    func testSynchronousStoreReorderUsesTheTargetBlocksResolvedIndex() throws {
        let blockID: BlockInputBlockID = "paragraph"
        let siblingID: BlockInputBlockID = "sibling"
        let store = ProvisionalEchoStore(
            blocks: [
                BlockInputBlock(id: blockID, text: "Hello"),
                BlockInputBlock(id: siblingID, text: "Sibling")
            ],
            echoMode: .synchronous,
            movesReplacedBlockToEnd: true
        )
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        mounted.view.applySelection(
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)),
            notify: true
        )
        let session = try startedSession(in: mounted.view)

        XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: " voice"), .applied)

        XCTAssertEqual(mounted.view.document.blocks.map(\.id), [siblingID, blockID])
        XCTAssertEqual(mounted.view.visibleBlockItemForTesting(at: 0)?.representedBlockID, siblingID)
        XCTAssertEqual(mounted.view.visibleBlockItemForTesting(at: 1)?.representedBlockID, blockID)
        XCTAssertEqual(mounted.view.finishProvisionalTextReplacement(session, disposition: .commit), .committed)
    }

    func testFallbackBeginFailsIfSelectionCallbackReplacesStore() {
        let blockID: BlockInputBlockID = "paragraph"
        let originalStore = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ]))
        let replacementStore = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Replacement")
        ]))
        var mountedView: BlockInputView?
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: originalStore,
            onSelectionChange: { _ in
                mountedView?.configure(BlockInputConfiguration(documentStore: replacementStore))
            }
        ))
        mountedView = mounted.view

        XCTAssertEqual(
            mounted.view.beginProvisionalTextReplacement(),
            .unavailable(.targetBlockUnavailable)
        )
        XCTAssertEqual(mounted.view.documentStore?.block(withID: blockID)?.text, "Replacement")
        XCTAssertNil(mounted.view.selection)
        XCTAssertFalse(mounted.view.isEditorFirstResponder)
    }

    func testDetachInvalidatesActiveSession() throws {
        let blockID: BlockInputBlockID = "paragraph"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ])
        mounted.view.applySelection(
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5)),
            notify: true
        )
        let session = try startedSession(in: mounted.view)

        mounted.window.contentView = NSView()

        XCTAssertEqual(mounted.view.updateProvisionalTextReplacement(session, text: " voice"), .invalidated)
        XCTAssertEqual(
            mounted.view.finishProvisionalTextReplacement(session, disposition: .commit),
            .invalidated
        )
    }

    func testUnsupportedSelectionAndBlockKindAreRejected() {
        let firstID: BlockInputBlockID = "first"
        let secondID: BlockInputBlockID = "second"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: firstID, text: "One"),
            BlockInputBlock(id: secondID, text: "Two")
        ])
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: true)
        XCTAssertEqual(
            mounted.view.beginProvisionalTextReplacement(),
            .unavailable(.unsupportedSelection)
        )

        let table = BlockInputBlock(id: "table", kind: .table, text: "| A |\n| --- |\n| B |")
        let tableMounted = makeMountedBlockInputView(blocks: [table])
        tableMounted.view.applySelection(.blocks([table.id]), notify: true)
        XCTAssertEqual(
            tableMounted.view.beginProvisionalTextReplacement(),
            .unavailable(.unsupportedSelection)
        )

        let image = BlockInputBlock(
            id: "image",
            kind: .image(BlockInputImage(source: "image.png", altText: "Alt"))
        )
        let imageMounted = makeMountedBlockInputView(blocks: [image])
        imageMounted.view.applySelection(
            .cursor(BlockInputCursor(blockID: image.id, utf16Offset: 0)),
            notify: true
        )
        XCTAssertEqual(
            imageMounted.view.beginProvisionalTextReplacement(),
            .unavailable(.unsupportedBlockKind)
        )
    }

    func testMissingBlockAndInvalidUTF16RangeAreRejected() {
        let blockID: BlockInputBlockID = "paragraph"
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "Hello")
        ])
        mounted.view.applySelection(
            .cursor(BlockInputCursor(blockID: "missing", utf16Offset: 0)),
            notify: true
        )
        XCTAssertEqual(
            mounted.view.beginProvisionalTextReplacement(),
            .unavailable(.targetBlockUnavailable)
        )

        mounted.view.applySelection(
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 4, length: 2))),
            notify: true
        )
        XCTAssertEqual(
            mounted.view.beginProvisionalTextReplacement(),
            .unavailable(.invalidSelectionRange)
        )
    }

    func testFallbackRejectsDocumentWithoutEditableTextBlocks() {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: "rule", kind: .horizontalRule)
        ])
        XCTAssertNil(mounted.view.selection)

        XCTAssertEqual(
            mounted.view.beginProvisionalTextReplacement(),
            .unavailable(.noEditableTextBlock)
        )
    }

}

private enum ExternalMutation {
    case replacement
    case deletion
}
