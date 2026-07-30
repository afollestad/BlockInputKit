import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewFocusTests: XCTestCase {
    func testWindowCanMakeEditorFirstResponderWithCursorSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        mounted.view.focus(blockID: blockID, utf16Offset: 2)

        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertTrue(mounted.window.firstResponder === textView)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertEqual(
            mounted.view.selection,
            .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2))
        )
    }

    func testWindowCanMakeEditorFirstResponderWithTextSelection() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        mounted.view.applySelection(.text(BlockInputTextRange(
            blockID: blockID,
            range: NSRange(location: 1, length: 3)
        )), notify: false)

        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        XCTAssertTrue(mounted.window.firstResponder === textView)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 3))
        XCTAssertEqual(
            mounted.view.selection,
            .text(BlockInputTextRange(blockID: blockID, range: NSRange(location: 1, length: 3)))
        )
    }

    func testFocusEditorBeforeWindowAttachmentClaimsFocusOnAttach() async throws {
        // A freshly mounted SwiftUI editor can receive focusEditor() before it
        // joins a window, where makeFirstResponder is a silent no-op; the claim
        // must retry (deferred one tick) after attachment.
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])))

        view.focusEditor()
        XCTAssertTrue(view.wantsFocusOnWindowAttach)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()

        for _ in 0..<200 {
            if view.isEditorFirstResponder {
                break
            }
            await Task.yield()
        }
        XCTAssertFalse(view.wantsFocusOnWindowAttach)
        XCTAssertTrue(view.isEditorFirstResponder)
    }

    func testResigningFocusCancelsDeferredWindowAttachClaim() {
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: BlockInputBlockID(rawValue: "first"), text: "First")
        ])))

        view.focusEditor()
        XCTAssertTrue(view.wantsFocusOnWindowAttach)

        _ = view.resignEditorFocus()
        XCTAssertFalse(view.wantsFocusOnWindowAttach)
    }

    func testEditingPublishesFocusChanges() async throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        var focusValues: [Bool] = []
        let lostFocus = expectation(description: "Publishes focus loss")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            onFocusChange: { isFocused in
                focusValues.append(isFocused)
                if !isFocused {
                    lostFocus.fulfill()
                }
            }
        ))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )

        view.blockItemDidBeginEditing(item, blockID: blockID)
        view.blockItemDidEndEditing(item, blockID: blockID)

        await fulfillment(of: [lostFocus], timeout: 1)
        XCTAssertEqual(focusValues, [true, false])
    }

    func testBecomingFirstResponderWithBlockSelectionPublishesFocus() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var focusValues: [Bool] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            onFocusChange: { focusValues.append($0) }
        ))
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)

        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        XCTAssertEqual(focusValues, [true])
    }

    func testBecomingFirstResponderWithCursorSelectionDoesNotPublishTransientFocusLoss() {
        let blockID = BlockInputBlockID(rawValue: "first")
        var focusValues: [Bool] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            onFocusChange: { focusValues.append($0) }
        ))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)), notify: false)

        XCTAssertTrue(mounted.window.makeFirstResponder(mounted.view))

        XCTAssertEqual(focusValues, [true])
    }

    func testFocusEditorWithExistingCursorSelectionPublishesFocus() {
        let blockID = BlockInputBlockID(rawValue: "first")
        var focusValues: [Bool] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "First")
            ]),
            onFocusChange: { focusValues.append($0) }
        ))
        mounted.view.applySelection(.cursor(BlockInputCursor(blockID: blockID, utf16Offset: 2)), notify: false)

        mounted.view.focusEditor()

        XCTAssertTrue(mounted.view.isEditorFirstResponder)
        XCTAssertEqual(focusValues, [true])
    }

    func testFocusEditorWithExistingBlockSelectionPublishesFocus() {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var focusValues: [Bool] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            onFocusChange: { focusValues.append($0) }
        ))
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)

        mounted.view.focusEditor()

        XCTAssertTrue(mounted.window.firstResponder === mounted.view)
        XCTAssertEqual(focusValues, [true])
    }

    func testMovingFromBlockSelectionToTextFocusDoesNotPublishTransientFocusLoss() async {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var focusValues: [Bool] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            onFocusChange: { focusValues.append($0) }
        ))
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.view.focus(blockID: firstID, utf16Offset: 0)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(focusValues, [true])
    }

    func testResigningFirstResponderWithBlockSelectionPublishesFocusLoss() async {
        let firstID = BlockInputBlockID(rawValue: "first")
        let secondID = BlockInputBlockID(rawValue: "second")
        var focusValues: [Bool] = []
        let lostFocus = expectation(description: "Publishes focus loss")
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: firstID, text: "First"),
                BlockInputBlock(id: secondID, text: "Second")
            ]),
            onFocusChange: { isFocused in
                focusValues.append(isFocused)
                if !isFocused {
                    lostFocus.fulfill()
                }
            }
        ))
        mounted.view.applySelection(.blocks([firstID, secondID]), notify: false)
        mounted.window.makeFirstResponder(mounted.view)

        mounted.window.makeFirstResponder(nil)

        await fulfillment(of: [lostFocus], timeout: 1)
        XCTAssertEqual(focusValues, [true, false])
    }

    func testEditableCollectionBackgroundClickFocusesEditor() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        let point = try backgroundPoint(in: mounted.view.collectionView)
        let event = try mouseDownEvent(
            location: mounted.view.collectionView.convert(point, to: nil),
            windowNumber: mounted.window.windowNumber
        )

        mounted.view.collectionView.mouseDown(with: event)

        XCTAssertTrue(mounted.window.firstResponder === textView)
        XCTAssertEqual(mounted.view.selection, .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 0)))
    }

    func testEditableRowScrollSurfaceClickFocusesTextView() throws {
        let blockID = BlockInputBlockID(rawValue: "first")
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(id: blockID, text: "First")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)
        let localPoint = NSPoint(x: scrollView.bounds.maxX - 4, y: scrollView.bounds.midY)
        let windowPoint = scrollView.convert(localPoint, to: nil)
        let mouseDown = try mouseDownEvent(location: windowPoint, windowNumber: mounted.window.windowNumber)
        let mouseUp = try mouseUpEvent(location: windowPoint, windowNumber: mounted.window.windowNumber)

        scrollView.mouseDown(with: mouseDown)
        textView.mouseUp(with: mouseUp)

        XCTAssertTrue(mounted.window.firstResponder === textView)
    }

    func testEditableSurfacesAcceptFirstMouse() throws {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(text: "First")
        ])
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let scrollView = try XCTUnwrap(item.testingTextScrollView)
        let textView = try XCTUnwrap(item.testingTextView)
        let event = try mouseDownEvent(
            location: scrollView.convert(NSPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY), to: nil),
            windowNumber: mounted.window.windowNumber
        )

        XCTAssertTrue(mounted.view.collectionView.acceptsFirstMouse(for: event))
        XCTAssertTrue(scrollView.acceptsFirstMouse(for: event))
        XCTAssertTrue(textView.acceptsFirstMouse(for: event))
    }

    func testEditableSurfaceAddsIBeamCursorRectOnlyWhenEditable() {
        let mounted = makeMountedBlockInputView(blocks: [
            BlockInputBlock(text: "First")
        ])
        let editableProbe = FocusCursorRectProbeView(frame: NSRect(x: 0, y: 0, width: 32, height: 12))

        mounted.view.addEditableSurfaceCursorRectIfNeeded(to: editableProbe)

        XCTAssertEqual(editableProbe.addedCursorRects.count, 1)
        XCTAssertEqual(editableProbe.addedCursorRects.first?.rect, editableProbe.bounds)
        XCTAssertEqual(editableProbe.addedCursorRects.first?.cursor, .iBeam)

        mounted.view.configure(BlockInputConfiguration(
            document: mounted.view.document,
            isEditable: false
        ))
        let readOnlyProbe = FocusCursorRectProbeView(frame: editableProbe.frame)
        mounted.view.addEditableSurfaceCursorRectIfNeeded(to: readOnlyProbe)

        XCTAssertTrue(readOnlyProbe.addedCursorRects.isEmpty)
    }

    private func backgroundPoint(in collectionView: NSCollectionView) throws -> NSPoint {
        let bounds = collectionView.bounds.insetBy(dx: 4, dy: 4)
        let candidates = [
            NSPoint(x: bounds.midX, y: bounds.maxY),
            NSPoint(x: bounds.midX, y: bounds.minY),
            NSPoint(x: bounds.maxX, y: bounds.midY),
            NSPoint(x: bounds.minX, y: bounds.midY)
        ]
        return try XCTUnwrap(candidates.first { collectionView.indexPathForItem(at: $0) == nil })
    }

}

private final class FocusCursorRectProbeView: NSView {
    var addedCursorRects: [(rect: NSRect, cursor: NSCursor)] = []

    override func addCursorRect(_ rect: NSRect, cursor object: NSCursor) {
        addedCursorRects.append((rect, object))
        super.addCursorRect(rect, cursor: object)
    }
}
