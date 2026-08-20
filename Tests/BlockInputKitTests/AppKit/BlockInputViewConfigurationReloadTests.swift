import AppKit
import XCTest
@testable import BlockInputKit

/// Covers `configure`'s choice between refreshing the mounted items and reloading the collection
/// view. Both reload helpers bump `focusRestoreGeneration`, so an unchanged generation is the
/// signal that no cell was recycled — which is what keeps a SwiftUI-driven reconfiguration out of
/// AppKit's window-wide key-view search.
@MainActor
final class BlockInputViewConfigurationReloadTests: XCTestCase {
    func testReconfiguringWithUnchangedDocumentSkipsReload() throws {
        let store = makeStore()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        let generation = mounted.view.focusRestoreGeneration

        mounted.view.configure(BlockInputConfiguration(documentStore: store))

        XCTAssertEqual(mounted.view.focusRestoreGeneration, generation)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertEqual(item.testingTextView?.string, "First")
    }

    func testReconfiguringWithUnchangedDocumentStillAppliesEditabilityToMountedItems() throws {
        let store = makeStore()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        let generation = mounted.view.focusRestoreGeneration

        mounted.view.configure(BlockInputConfiguration(documentStore: store, isEditable: false))

        XCTAssertEqual(mounted.view.focusRestoreGeneration, generation)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertFalse(item.isEditable)
        XCTAssertEqual(item.testingTextView?.isEditable, false)
    }

    func testReconfiguringWithUnchangedDocumentStillAppliesStyleToMountedItems() throws {
        // `BlockInputStyle` is not `Equatable`, so a reused row is the only thing standing between
        // a restyled host and stale type on screen.
        let store = makeStore()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        let generation = mounted.view.focusRestoreGeneration

        mounted.view.configure(BlockInputConfiguration(
            documentStore: store,
            style: BlockInputStyle(baseText: BlockInputTextStyle(font: .systemFont(ofSize: 21), foregroundColor: .systemPink))
        ))

        XCTAssertEqual(mounted.view.focusRestoreGeneration, generation)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let textStorage = try XCTUnwrap(textView.textStorage)
        XCTAssertEqual(textView.font?.pointSize, 21)
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemPink)
    }

    func testReconfiguringWithUnchangedDocumentKeepsFocusedTextViewAndCaret() throws {
        let store = makeStore()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        mounted.view.focus(blockID: "first", utf16Offset: 3)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertTrue(mounted.window.firstResponder === textView)

        mounted.view.configure(BlockInputConfiguration(documentStore: store))

        // The same text view instance still holds first responder, so the item survived intact.
        XCTAssertTrue(mounted.window.firstResponder === textView)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testReconfiguringWithNewDocumentStoreReloads() throws {
        let mounted = makeMountedBlockInputView(blocks: [BlockInputBlock(id: "first", text: "First")])
        let generation = mounted.view.focusRestoreGeneration

        mounted.view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", text: "Replaced")
        ])))

        XCTAssertGreaterThan(mounted.view.focusRestoreGeneration, generation)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertEqual(item.testingTextView?.string, "Replaced")
    }

    func testReconfiguringAfterStoreContentChangeRendersTheNewBlocks() throws {
        let store = makeStore()
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(documentStore: store))
        store.replaceDocument(BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", text: "Rewritten"),
            BlockInputBlock(id: "second", text: "Second"),
            BlockInputBlock(id: "third", text: "Third")
        ]))

        mounted.view.configure(BlockInputConfiguration(documentStore: store))

        // Whichever path `configure` takes, the mounted rows must render what the store now holds.
        XCTAssertEqual(mounted.view.blockCount, 3)
        XCTAssertEqual(mounted.view.collectionView.numberOfItems(inSection: 0), 3)
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        XCTAssertEqual(item.testingTextView?.string, "Rewritten")
    }

    private func makeStore() -> BlockInputMemoryDocumentStore {
        BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "first", text: "First"),
            BlockInputBlock(id: "second", text: "Second")
        ]))
    }
}
