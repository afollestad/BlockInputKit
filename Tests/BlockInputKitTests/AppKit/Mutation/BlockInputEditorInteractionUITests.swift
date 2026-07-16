import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputEditorInteractionUITests: XCTestCase {
    func testPresentedEditorInteractionUITracksCompletionPopup() async throws {
        var interactionStates: [Bool] = []
        let provider = DelayedPopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "@read")
            ]),
            completionProvider: provider,
            onEditorInteractionUIChange: { interactionStates.append($0) }
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: "block")
        let requestTask = mounted.view.completionRequestTask
        while !provider.isWaiting {
            await Task.yield()
        }

        XCTAssertEqual(mounted.view.completionSession?.isLoading, true)
        XCTAssertTrue(mounted.view.hasPresentedEditorInteractionUI)
        XCTAssertEqual(interactionStates, [true])
        XCTAssertTrue(mounted.view.handleCompletionCommand(#selector(NSResponder.cancelOperation(_:))))
        XCTAssertFalse(mounted.view.hasPresentedEditorInteractionUI)
        XCTAssertEqual(interactionStates, [true, false])

        provider.resume()
        await requestTask?.value
        XCTAssertFalse(mounted.view.hasPresentedEditorInteractionUI)
        XCTAssertEqual(interactionStates, [true, false])
    }

    func testSynchronousPresentationCallbackCanDismissBeforeRequestStarts() throws {
        var interactionStates: [Bool] = []
        weak var interactionView: BlockInputView?
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "@read")
            ]),
            completionProvider: provider,
            onEditorInteractionUIChange: { isPresented in
                interactionStates.append(isPresented)
                if isPresented {
                    interactionView?.dismissCompletionPopup()
                }
            }
        ))
        interactionView = mounted.view
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        interactionStates.removeAll()

        mounted.view.refreshCompletionSession(item: item, blockID: "block")

        XCTAssertEqual(interactionStates, [true, false])
        XCTAssertFalse(mounted.view.hasPresentedEditorInteractionUI)
        XCTAssertNil(mounted.view.completionRequestTask)
        XCTAssertTrue(provider.contexts.isEmpty)
    }

    func testSynchronousPresentationCallbackCanRefreshSameSessionQuery() async throws {
        var didMutateQuery = false
        weak var interactionTextView: BlockInputTextView?
        let provider = PopupCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "@rea")
            ]),
            completionProvider: provider,
            onEditorInteractionUIChange: { isPresented in
                guard isPresented, !didMutateQuery else { return }
                didMutateQuery = true
                interactionTextView?.insertText("d", replacementRange: NSRange(location: 4, length: 0))
            }
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        interactionTextView = textView
        XCTAssertTrue(mounted.window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        if !didMutateQuery {
            mounted.view.refreshCompletionSession(item: item, blockID: "block")
        }
        let requestTask = mounted.view.completionRequestTask

        await requestTask?.value

        XCTAssertTrue(didMutateQuery)
        XCTAssertEqual(mounted.view.completionSession?.token.rawQuery, "read")
        XCTAssertEqual(provider.contexts.map(\.rawQuery), ["read"])
    }

    func testAggregateInteractionUICallbackDoesNotToggleBetweenMutationModals() {
        var interactionStates: [Bool] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "Open docs")
            ]),
            onEditorInteractionUIChange: { interactionStates.append($0) }
        ))
        let linkContext = BlockInputLinkContext(
            blockID: "block",
            mode: .create(NSRange(location: 5, length: 4)),
            sourceRange: NSRange(location: 5, length: 4),
            sourceText: "Open docs",
            anchorWindowRect: .zero
        )
        let imageContext = BlockInputImageContext(
            blockID: "block",
            selectedRange: NSRange(location: 5, length: 4),
            sourceText: "Open docs",
            anchorWindowRect: .zero
        )

        mounted.view.showLinkModal(context: linkContext)
        XCTAssertEqual(interactionStates, [true])

        mounted.view.showImageModal(context: imageContext)
        XCTAssertTrue(mounted.view.hasPresentedEditorInteractionUI)
        XCTAssertEqual(interactionStates, [true])

        mounted.view.dismissImageModal(restoreFocus: false)
        XCTAssertFalse(mounted.view.hasPresentedEditorInteractionUI)
        XCTAssertEqual(interactionStates, [true, false])
    }

    func testRoutineConfigureDoesNotRepublishUnchangedInteractionUIState() {
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: "block", text: "Open docs")
        ]))
        var firstCallbackStates: [Bool] = []
        var secondCallbackStates: [Bool] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            documentStore: store,
            onEditorInteractionUIChange: { firstCallbackStates.append($0) }
        ))
        let context = BlockInputLinkContext(
            blockID: "block",
            mode: .create(NSRange(location: 5, length: 4)),
            sourceRange: NSRange(location: 5, length: 4),
            sourceText: "Open docs",
            anchorWindowRect: .zero
        )
        mounted.view.showLinkModal(context: context)

        mounted.view.configure(BlockInputConfiguration(
            documentStore: store,
            onEditorInteractionUIChange: { secondCallbackStates.append($0) }
        ))

        XCTAssertEqual(firstCallbackStates, [true])
        XCTAssertTrue(secondCallbackStates.isEmpty)

        mounted.view.dismissLinkModal(restoreFocus: false)
        XCTAssertEqual(firstCallbackStates, [true])
        XCTAssertEqual(secondCallbackStates, [false])
    }

    func testDetachDismissesInteractionUIAndPublishesOneTransition() {
        var interactionStates: [Bool] = []
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "Open docs")
            ]),
            onEditorInteractionUIChange: { interactionStates.append($0) }
        ))
        mounted.view.showLinkModal(context: BlockInputLinkContext(
            blockID: "block",
            mode: .create(NSRange(location: 5, length: 4)),
            sourceRange: NSRange(location: 5, length: 4),
            sourceText: "Open docs",
            anchorWindowRect: .zero
        ))

        mounted.view.removeFromSuperview()

        XCTAssertFalse(mounted.view.hasPresentedEditorInteractionUI)
        XCTAssertEqual(interactionStates, [true, false])
    }

    func testDetachDismissesCompletionUIAndPublishesOneTransition() async throws {
        var interactionStates: [Bool] = []
        let provider = DelayedPopupCompletionProvider(suggestions: [])
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "@read")
            ]),
            completionProvider: provider,
            onEditorInteractionUIChange: { interactionStates.append($0) }
        ))
        let item = try XCTUnwrap(mounted.view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        mounted.view.refreshCompletionSession(item: item, blockID: "block")
        let requestTask = mounted.view.completionRequestTask
        while !provider.isWaiting {
            await Task.yield()
        }

        mounted.view.removeFromSuperview()

        XCTAssertFalse(mounted.view.hasPresentedEditorInteractionUI)
        XCTAssertNil(mounted.view.completionRequestTask)
        XCTAssertEqual(interactionStates, [true, false])
        provider.resume()
        await requestTask?.value
    }
}
