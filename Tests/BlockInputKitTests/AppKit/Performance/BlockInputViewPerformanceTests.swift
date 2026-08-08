import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewPerformanceTests: XCTestCase {
    func testLargeDocumentKeepsMountedCollectionItemsBounded() {
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(text: "Block \(index)")
        })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = BlockInputView(frame: window.contentView?.bounds ?? window.frame)
        window.contentView = view

        view.configure(BlockInputConfiguration(document: document))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()

        let mountedItemCount = view.collectionView.visibleItems().count
        XCTAssertEqual(view.collectionView(view.collectionView, numberOfItemsInSection: 0), 100_000)
        XCTAssertGreaterThan(mountedItemCount, 0)
        XCTAssertLessThan(mountedItemCount, 100)
    }

    func testStoreBackedTypingDoesNotReadFullDocumentSnapshot() throws {
        let (blockID, document) = largeDocument(targetText: "Editable")
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView()
        var publishedMutations: [BlockInputDocumentChange] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentMutation: { publishedMutations.append($0) }
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: blockID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        store.resetCounts()

        textView.string = "Editable text"
        textView.setSelectedRange(NSRange(location: 13, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        view.blockItem(item, didChangeSelectionIn: blockID, selectedRange: nil)

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.block(withID: blockID)?.text, "Editable text")
        XCTAssertEqual(publishedMutations, [.replaceBlock(try XCTUnwrap(store.block(withID: blockID)))])
    }

    func testStoreBackedTypingRefreshesStaleCacheBeforePublishingDocument() throws {
        let blockID = BlockInputBlockID(rawValue: "target")
        let insertedID = BlockInputBlockID(rawValue: "inserted")
        let store = DocumentReadCountingStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Editable")
        ]))
        let view = BlockInputView()
        var publishedDocument: BlockInputDocument?
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onDocumentChange: { publishedDocument = $0 }
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: blockID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: insertedID, text: "Inserted"),
            BlockInputBlock(id: blockID, text: "Editable")
        ]))
        store.resetCounts()

        textView.string = "Editable text"
        textView.setSelectedRange(NSRange(location: 13, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(publishedDocument?.blocks.map(\.id), [insertedID, blockID])
        XCTAssertEqual(publishedDocument?.block(withID: blockID)?.text, "Editable text")
    }

    func testStoreBackedFocusAndSelectionDoNotReadFullDocumentSnapshot() throws {
        let (blockID, document) = largeDocument(targetText: "Selectable")
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView()
        var publishedSelections: [BlockInputSelection?] = []
        view.configure(BlockInputConfiguration(
            documentStore: store,
            onSelectionChange: { publishedSelections.append($0) }
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: blockID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        store.resetCounts()

        textView.setSelectedRange(NSRange(location: 2, length: 4))
        view.blockItemDidBeginEditing(item, blockID: blockID)
        view.blockItem(item, didChangeSelectionIn: blockID, selectedRange: nil)

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [])
        XCTAssertEqual(
            publishedSelections.last ?? nil,
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 2, length: 4)))
        )
    }

    func testStoreBackedSingleLineTypingDoesNotInvalidateLayout() throws {
        let context = try typingLayoutTestContext()
        let textView = try XCTUnwrap(context.item.testingTextView)

        textView.string = "Second edited"
        textView.setSelectedRange(NSRange(location: 13, length: 0))
        context.item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(context.store.block(withID: context.blockID)?.text, "Second edited")
        XCTAssertEqual(context.layout.invalidatedItemIndexPaths, [])
        XCTAssertFalse(context.layout.didInvalidateDelegateMetrics)
        XCTAssertFalse(context.layout.didInvalidateEverything)
    }

    func testStoreBackedIndentDoesNotReadFullDocumentSnapshotOrInvalidateLayout() throws {
        let targetIndex = 50_000
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                kind: .bulletedListItem,
                text: index == targetIndex ? "Editable" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        let layout = TrackingCollectionViewFlowLayout()
        view.collectionView.collectionViewLayout = layout
        view.configure(BlockInputConfiguration(documentStore: store))
        let item = BlockInputBlockItem.configuredForTesting(
            block: try XCTUnwrap(store.block(withID: blockID)),
            allowsReordering: true,
            delegate: view
        )
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        store.resetCounts()
        layout.reset()

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replacedBlockIDs, [blockID])
        XCTAssertEqual(store.block(withID: blockID)?.indentationLevel, 1)
        XCTAssertEqual(view.document.block(withID: blockID)?.indentationLevel, 1)
        XCTAssertFalse(layout.didInvalidateDelegateMetrics)
        XCTAssertFalse(layout.didInvalidateEverything)
    }

    func testStoreBackedReturnAfterHeadingDoesNotReadFullDocumentSnapshot() {
        let targetIndex = 50_000
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                kind: index == targetIndex ? .heading(level: 2) : .paragraph,
                text: index == targetIndex ? "Heading" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(
            documentStore: store,
            undoController: BlockInputUndoController()
        ))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 7)), notify: false)
        store.resetCounts()

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].index, targetIndex + 1)
        XCTAssertEqual(store.insertedBlockBatches[0].blocks.first?.kind, .paragraph)
    }

    func testStoreBackedReturnAtEndOfListItemDoesNotReadFullDocumentSnapshot() {
        let targetIndex = 50_000
        let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
        let document = BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "block-\(index)"),
                kind: index == targetIndex ? .bulletedListItem : .paragraph,
                text: index == targetIndex ? "List item" : "Block \(index)"
            )
        })
        let store = DocumentReadCountingStore(document: document)
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(documentStore: store))
        view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 9)), notify: false)
        store.resetCounts()

        _ = view.insertBlockBelowCurrentBlock()

        XCTAssertEqual(store.documentReadCount, 0)
        XCTAssertEqual(store.replaceDocumentCount, 0)
        XCTAssertEqual(store.insertedBlockBatches.count, 1)
        XCTAssertEqual(store.insertedBlockBatches[0].index, targetIndex + 1)
        XCTAssertEqual(store.insertedBlockBatches[0].blocks.first?.kind, .bulletedListItem)
    }

    func testStoreBackedIndentInvalidatesLayoutWhenWrappingHeightChanges() throws {
        let blockID = BlockInputBlockID(rawValue: "second")
        let text = Array(repeating: "wrapped content", count: 6).joined(separator: " ")
        let block = BlockInputBlock(id: blockID, kind: .bulletedListItem, text: text)
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", text: "First"),
            block,
            BlockInputBlock(id: "third", text: "Third")
        ]))
        // Narrow enough that one indent step pushes this text past a wrap boundary,
        // which is the height change the invalidation under test depends on.
        let itemWidth: CGFloat = 228
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: itemWidth, height: 480))
        let layout = TrackingCollectionViewFlowLayout()
        view.collectionView.collectionViewLayout = layout
        view.configure(BlockInputConfiguration(documentStore: store))
        layout.reset()
        let item = BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: true,
            delegate: view
        )
        let textWidth = BlockInputBlockItem.measuredTextWidth(
            for: itemWidth,
            block: block,
            allowsReordering: true
        )
        let startingHeight = BlockInputBlockItem.height(for: block, textWidth: textWidth)
        item.view.frame = NSRect(x: 0, y: 0, width: itemWidth, height: startingHeight)
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))

        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))

        let updatedBlock = try XCTUnwrap(store.block(withID: blockID))
        let updatedTextWidth = BlockInputBlockItem.measuredTextWidth(
            for: itemWidth,
            block: updatedBlock,
            allowsReordering: true
        )
        let expectedHeight = BlockInputBlockItem.height(for: updatedBlock, textWidth: updatedTextWidth)
        XCTAssertGreaterThan(expectedHeight, startingHeight)
        XCTAssertEqual(item.view.frame.height, expectedHeight, accuracy: 0.5)
        XCTAssertTrue(layout.didInvalidateDelegateMetrics)
        XCTAssertFalse(layout.didInvalidateEverything)
    }

    func testStoreBackedTypingInvalidatesEditedItemWhenHeightChanges() throws {
        let context = try typingLayoutTestContext()
        let textView = try XCTUnwrap(context.item.testingTextView)

        textView.string = "Second\nedited"
        textView.setSelectedRange(NSRange(location: 13, length: 0))
        context.item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(context.store.block(withID: context.blockID)?.text, "Second\nedited")
        XCTAssertEqual(
            context.item.view.frame.height,
            BlockInputBlockItem.height(
                for: BlockInputBlock(id: context.blockID, text: "Second\nedited"),
                textWidth: 664
            ),
            accuracy: 0.5
        )
        XCTAssertEqual(context.layout.invalidatedItemIndexPaths, [])
        XCTAssertTrue(context.layout.didInvalidateDelegateMetrics)
        XCTAssertFalse(context.layout.didInvalidateEverything)
    }

    func testStoreBackedQuoteTypingResizesVisibleItemWhenHeightChanges() throws {
        let quoteBlock = BlockInputBlock(id: "second", kind: .quote, text: "Second")
        let context = try typingLayoutTestContext(block: quoteBlock)
        let textView = try XCTUnwrap(context.item.testingTextView)

        textView.string = "Second\nedited\nagain"
        textView.setSelectedRange(NSRange(location: 19, length: 0))
        context.item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(context.store.block(withID: context.blockID)?.text, "Second\nedited\nagain")
        XCTAssertEqual(
            context.item.view.frame.height,
            BlockInputBlockItem.height(
                for: BlockInputBlock(id: context.blockID, kind: .quote, text: "Second\nedited\nagain"),
                textWidth: 664
            ),
            accuracy: 0.5
        )
        XCTAssertTrue(context.layout.didInvalidateDelegateMetrics)
        XCTAssertFalse(context.layout.didInvalidateEverything)
    }

    func testStoreBackedQuoteTypingShrinksVisibleItemWhenLinesAreRemoved() throws {
        let quoteBlock = BlockInputBlock(id: "second", kind: .quote, text: "First\nSecond\nThird\nFourth")
        let context = try typingLayoutTestContext(block: quoteBlock)
        let textView = try XCTUnwrap(context.item.testingTextView)
        let startingHeight = BlockInputBlockItem.height(for: quoteBlock, textWidth: 664)
        context.item.view.frame.size.height = startingHeight

        textView.string = "First\nSecond"
        textView.setSelectedRange(NSRange(location: 12, length: 0))
        context.item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        let expectedHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(id: context.blockID, kind: .quote, text: "First\nSecond"),
            textWidth: 664
        )
        XCTAssertLessThan(expectedHeight, startingHeight)
        XCTAssertEqual(context.item.view.frame.height, expectedHeight, accuracy: 0.5)
        XCTAssertTrue(context.layout.didInvalidateDelegateMetrics)
        XCTAssertFalse(context.layout.didInvalidateEverything)
    }

    func testMountedQuoteTypingShrinksCollectionRowWhenLinesAreRemoved() throws {
        let quoteID = BlockInputBlockID(rawValue: "quote")
        let nextID = BlockInputBlockID(rawValue: "next")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: quoteID, kind: .quote, text: "First\nSecond\nThird\nFourth"),
            BlockInputBlock(id: nextID, kind: .paragraph, text: "Next")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let nextItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let nextInitialMinY = nextItem.view.frame.minY

        textView.string = "First\nSecond"
        textView.setSelectedRange(NSRange(location: 12, length: 0))
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let expectedHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(id: quoteID, kind: .quote, text: "First\nSecond"),
            textWidth: 664
        )
        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let updatedNextItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        XCTAssertEqual(updatedItem.view.frame.height, expectedHeight, accuracy: 0.5)
        XCTAssertLessThan(
            updatedNextItem.view.frame.minY,
            nextInitialMinY,
            "updatedItem=\(updatedItem.view.frame) updatedNext=\(updatedNextItem.view.frame) initialNextMinY=\(nextInitialMinY)"
        )
    }

    func testMountedQuoteTypingMovesFollowingRowsWhenBlockGrows() throws {
        let quoteID = BlockInputBlockID(rawValue: "quote")
        let nextID = BlockInputBlockID(rawValue: "next")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: quoteID, kind: .quote, text: "First"),
            BlockInputBlock(id: nextID, kind: .paragraph, text: "Next")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let nextItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        let nextInitialMinY = nextItem.view.frame.minY

        textView.string = "First\nSecond\nThird\nFourth"
        textView.setSelectedRange(NSRange(location: 25, length: 0))
        mounted.window.makeFirstResponder(textView)
        item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        mounted.view.collectionView.layoutSubtreeIfNeeded()

        let expectedHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(id: quoteID, kind: .quote, text: "First\nSecond\nThird\nFourth"),
            textWidth: 664
        )
        let updatedItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let updatedNextItem = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 1))
        XCTAssertEqual(updatedItem.view.frame.height, expectedHeight, accuracy: 0.5)
        XCTAssertGreaterThan(updatedNextItem.view.frame.minY, nextInitialMinY)
        XCTAssertTrue(mounted.window.firstResponder === textView)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: quoteID, utf16Offset: 25)))
    }

    func testLargeDocumentTableAppendRowSkipsDelegateMetricsInvalidation() throws {
        var blocks = [BlockInputBlock(
            id: "table",
            kind: .table,
            text: BlockInputTable.normalized(
                header: ["H1", "H2"],
                bodyRows: [["one", "two"]],
                alignments: [.left, .left]
            ).markdown
        )]
        blocks.append(contentsOf: (0..<largeDocumentCacheMutationLimit).map { BlockInputBlock(text: "Block \($0)") })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = BlockInputView(frame: window.contentView?.bounds ?? window.frame)
        let layout = TrackingCollectionViewFlowLayout()
        view.collectionView.collectionViewLayout = layout
        window.contentView = view
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: blocks)))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        let item = try XCTUnwrap(view.collectionView.item(at: IndexPath(item: 0, section: 0)) as? BlockInputBlockItem)
        let heightBefore = item.view.frame.height
        layout.reset()

        XCTAssertTrue(view.appendTableBodyRow(blockID: "table"))

        // Height-changing replacements above the large-document limit must stay on the
        // frame-only path; a delegate-metrics refresh re-measures every row.
        XCTAssertFalse(layout.didInvalidateDelegateMetrics)
        XCTAssertGreaterThan(item.view.frame.height, heightBefore)
    }

    func testStoreBackedListInlineReturnInvalidatesFullLayout() throws {
        let context = try typingLayoutTestContext(block: BlockInputBlock(
            id: "second",
            kind: .bulletedListItem,
            text: "Second"
        ))
        let textView = try XCTUnwrap(context.item.testingTextView)

        textView.string = "Second\nitem"
        textView.setSelectedRange(NSRange(location: 11, length: 0))
        context.item.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(context.store.block(withID: context.blockID)?.text, "Second\nitem")
        XCTAssertEqual(context.layout.invalidatedItemIndexPaths, [])
        XCTAssertTrue(context.layout.didInvalidateDelegateMetrics)
        XCTAssertFalse(context.layout.didInvalidateEverything)
    }
}

private func largeDocument(targetText: String) -> (BlockInputBlockID, BlockInputDocument) {
    let targetIndex = 50_000
    let blockID = BlockInputBlockID(rawValue: "block-\(targetIndex)")
    let document = BlockInputDocument(blocks: (0..<100_000).map { index in
        BlockInputBlock(
            id: BlockInputBlockID(rawValue: "block-\(index)"),
            text: index == targetIndex ? targetText : "Block \(index)"
        )
    })
    return (blockID, document)
}

@MainActor
private func typingLayoutTestContext(
    block: BlockInputBlock = BlockInputBlock(id: "second", text: "Second"),
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> TypingLayoutTestContext {
    let blockID = block.id
    let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
        BlockInputBlock(id: "first", text: "First"),
        block,
        BlockInputBlock(id: "third", text: "Third")
    ]))
    let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
    let layout = TrackingCollectionViewFlowLayout()
    view.collectionView.collectionViewLayout = layout
    view.configure(BlockInputConfiguration(documentStore: store))
    layout.reset()
    let item = BlockInputBlockItem.configuredForTesting(
        block: try XCTUnwrap(store.block(withID: blockID), file: file, line: line),
        allowsReordering: true,
        delegate: view
    )
    item.view.frame = NSRect(x: 0, y: 0, width: 720, height: 44)
    return TypingLayoutTestContext(blockID: blockID, store: store, view: view, layout: layout, item: item)
}

private struct TypingLayoutTestContext {
    let blockID: BlockInputBlockID
    let store: BlockInputMemoryDocumentStore
    let view: BlockInputView
    let layout: TrackingCollectionViewFlowLayout
    let item: BlockInputBlockItem
}
