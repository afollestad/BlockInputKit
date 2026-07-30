import AppKit
import SwiftUI
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

    func testPreAttachmentFocusDoesNotHideTheTopContentInset() async throws {
        // Mirrors a SwiftUI editor opened to edit existing text: focusEditor()
        // runs while the view is windowless with a zero-size clip, where a
        // scroll-to-item call would scroll the first row flush to the clip top
        // and permanently hide the top section inset once the window attaches.
        let blockID = BlockInputBlockID(rawValue: "first")
        let view = BlockInputView(frame: .zero)
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: "Comment 1")
            ]),
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 2,
                maximumVisibleLineCount: 10
            )
        ))

        view.focusEditor()

        // The window attaches while SwiftUI still has the view at zero size;
        // the proper height arrives one layout pass later.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(view)
        view.layoutSubtreeIfNeeded()
        view.focusEditor()
        for _ in 0..<20 {
            await Task.yield()
        }

        let height = view.preferredHeight(forWidth: 400)
        view.frame = NSRect(x: 0, y: 0, width: 400, height: height)
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        for _ in 0..<200 {
            if view.isEditorFirstResponder {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(view.scrollView.contentView.bounds.origin.y, 0, accuracy: 0.5)
    }

    func testSwiftUIEditorFocusKeepsTopInsetVisible() async throws {
        // The real SwiftUI mount order: the editor mounts unfocused, then the
        // host's focus request flips the binding true one update later. The
        // focus claim must not leave the clip scrolled past the top inset.
        let configuration = Self.chromedHeightSizedConfiguration(markdown: "Comment 1")
        let focusDriver = FocusDriver()
        let hosting = NSHostingView(rootView: FocusDrivenEditorHost(
            configuration: configuration,
            driver: focusDriver
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 90)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 90),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        focusDriver.isFocused = true
        let view = try XCTUnwrap(firstBlockInputView(in: hosting))
        for _ in 0..<200 {
            window.displayIfNeeded()
            if view.isEditorFirstResponder {
                break
            }
            await Task.yield()
        }
        for _ in 0..<50 {
            await Task.yield()
        }
        window.displayIfNeeded()

        XCTAssertTrue(view.isEditorFirstResponder)
        XCTAssertEqual(view.scrollView.contentView.bounds.origin.y, 0, accuracy: 0.5)
        let firstItem = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        XCTAssertEqual(firstItem.view.frame.minY, view.editorContentTopInset, accuracy: 0.5)
    }

    /// A comment-editor-like configuration: chromed surface plus height sizing.
    private static func chromedHeightSizedConfiguration(markdown: String) -> BlockInputConfiguration {
        var style = BlockInputStyle.default
        style.editorSurface = BlockInputEditorSurfaceStyle(
            editorBackgroundColor: nil,
            scrollBackgroundColor: nil,
            collectionBackgroundColor: nil,
            chrome: BlockInputEditorChromeStyle(
                fillColor: NSColor.textBackgroundColor.withAlphaComponent(0.55),
                strokeColor: NSColor.separatorColor,
                borderWidth: 1,
                cornerRadius: 8,
                clipsContentToShape: true
            )
        )
        return BlockInputConfiguration(
            document: BlockInputDocument(markdown: markdown),
            placeholder: "Edit this comment",
            style: style,
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 2,
                maximumVisibleLineCount: 10
            )
        )
    }

    private func firstBlockInputView(in view: NSView) -> BlockInputView? {
        if let match = view as? BlockInputView {
            return match
        }
        for subview in view.subviews {
            if let match = firstBlockInputView(in: subview) {
                return match
            }
        }
        return nil
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

/// Flips the editor's focus binding after mount, like a host consuming a focus token.
@MainActor
private final class FocusDriver: ObservableObject {
    @Published var isFocused = false
}

private struct FocusDrivenEditorHost: View {
    let configuration: BlockInputConfiguration
    @ObservedObject var driver: FocusDriver

    var body: some View {
        BlockInputEditor(configuration: configuration, isFocused: $driver.isFocused)
    }
}
