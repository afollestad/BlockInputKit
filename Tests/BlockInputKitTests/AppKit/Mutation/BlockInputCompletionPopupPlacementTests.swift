import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputCompletionPopupPlacementTests: XCTestCase {
    func testPopupPlacementSupportsCaretAndOverlayFrames() async throws {
        let provider = PlacementCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let caret = try await startRootCompletion(provider: provider, placement: .caret)
        let top = try await startHostedCompletion(provider: provider, placement: .overlay)

        let caretFrame = try XCTUnwrap(caret.view.completionPopupView?.frame)
        let topFrame = try XCTUnwrap(top.view.completionPopupView?.frame)
        let overlay = top.view.convert(NSPoint(x: top.view.bounds.minX, y: top.view.bounds.maxY), to: top.host)

        XCTAssertTrue(top.view.completionPopupView?.superview === top.host)
        XCTAssertEqual(topFrame.minX, overlay.x, accuracy: 0.5)
        XCTAssertEqual(topFrame.width, top.view.bounds.width, accuracy: 0.5)
        XCTAssertEqual(topFrame.minY, overlay.y + BlockInputView.overlayCompletionPopupVerticalOffset, accuracy: 0.5)
        XCTAssertNotEqual(caretFrame.width, topFrame.width)
    }

    func testOverlayPopupAnchorsBottomEdgeAboveEditorInFlippedHost() async throws {
        let provider = PlacementCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let mounted = try await startHostedCompletion(
            provider: provider,
            placement: .overlay,
            flippedHost: true
        )

        let popupFrame = try XCTUnwrap(mounted.view.completionPopupView?.frame)
        let overlay = mounted.view.convert(NSPoint(x: mounted.view.bounds.minX, y: mounted.view.bounds.maxY), to: mounted.host)

        XCTAssertTrue(mounted.view.completionPopupView?.superview === mounted.host)
        XCTAssertEqual(popupFrame.minX, overlay.x, accuracy: 0.5)
        XCTAssertEqual(popupFrame.width, mounted.view.bounds.width, accuracy: 0.5)
        XCTAssertEqual(
            popupFrame.maxY,
            overlay.y - BlockInputView.overlayCompletionPopupVerticalOffset,
            accuracy: 0.5
        )
    }

    func testOverlayProviderControlsContainerAndFrame() async throws {
        let provider = PlacementCompletionProvider(suggestions: [
            .fileLink(label: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let customFrame = NSRect(x: 18, y: 420, width: 480, height: 64)
        let mounted = try await startHostedCompletion(
            provider: provider,
            placement: .overlay,
            overlayProviderFrame: customFrame
        )

        let container = try XCTUnwrap(mounted.configuredContainer)
        let popupFrame = try XCTUnwrap(mounted.view.completionPopupView?.frame)

        XCTAssertTrue(mounted.view.completionPopupView?.superview === container)
        XCTAssertEqual(popupFrame, customFrame)
        XCTAssertGreaterThan(mounted.capturedDefaultFrame?.height ?? 0, 0)
    }

    private func startRootCompletion(
        provider: any BlockInputCompletionProvider,
        placement: BlockInputCompletionPopupPlacement
    ) async throws -> (view: BlockInputView, window: NSWindow) {
        let mounted = makeMountedBlockInputView(configuration: BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "@read")
            ]),
            completionProvider: provider,
            completionPopupPlacement: placement
        ))
        try startCompletion(in: mounted.view)
        await mounted.view.completionRequestTask?.value
        mounted.view.layoutSubtreeIfNeeded()
        return mounted
    }

    private func startHostedCompletion(
        provider: any BlockInputCompletionProvider,
        placement: BlockInputCompletionPopupPlacement,
        flippedHost: Bool = false,
        overlayProviderFrame: NSRect? = nil
    ) async throws -> HostedCompletionMount {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let host = CompletionPopupHostView(
            frame: window.contentView?.bounds ?? window.frame,
            flipped: flippedHost
        )
        let editorFrame = flippedHost
            ? NSRect(x: 40, y: 152, width: 620, height: 320)
            : NSRect(x: 40, y: 72, width: 620, height: 320)
        let view = BlockInputView(frame: editorFrame)
        let configuredContainer = overlayProviderFrame.map { _ in NSView(frame: host.bounds) }
        let capturedOverlayContext = CapturedOverlayContext()
        window.contentView = host
        host.addSubview(view)
        if let configuredContainer {
            host.addSubview(configuredContainer, positioned: .above, relativeTo: view)
        }
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "block", text: "@read")
            ]),
            completionProvider: provider,
            completionPopupConfiguration: popupConfiguration(
                placement: placement,
                configuredContainer: configuredContainer,
                overlayProviderFrame: overlayProviderFrame,
                capturedOverlayContext: capturedOverlayContext
            )
        ))
        try startCompletion(in: view)
        await view.completionRequestTask?.value
        host.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        return HostedCompletionMount(
            host: host,
            view: view,
            window: window,
            configuredContainer: configuredContainer,
            capturedDefaultFrame: capturedOverlayContext.defaultFrame
        )
    }

    private func popupConfiguration(
        placement: BlockInputCompletionPopupPlacement,
        configuredContainer: NSView?,
        overlayProviderFrame: NSRect?,
        capturedOverlayContext: CapturedOverlayContext
    ) -> BlockInputCompletionPopupConfiguration {
        guard let configuredContainer, let overlayProviderFrame else {
            return BlockInputCompletionPopupConfiguration(placement: placement)
        }
        return BlockInputCompletionPopupConfiguration(
            placement: placement,
            overlayProvider: { context in
                capturedOverlayContext.defaultFrame = context.defaultFrame
                return BlockInputCompletionPopupOverlay(
                    container: configuredContainer,
                    frame: overlayProviderFrame
                )
            }
        )
    }

    private func startCompletion(in view: BlockInputView) throws {
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: ("@read" as NSString).length, length: 0))
        view.refreshCompletionSession(item: item, blockID: "block")
    }
}

private struct HostedCompletionMount {
    var host: NSView
    var view: BlockInputView
    var window: NSWindow
    var configuredContainer: NSView?
    var capturedDefaultFrame: NSRect?
}

private final class CapturedOverlayContext {
    var defaultFrame: NSRect?
}

private final class CompletionPopupHostView: NSView {
    private let isHostFlipped: Bool

    override var isFlipped: Bool {
        isHostFlipped
    }

    init(frame frameRect: NSRect, flipped: Bool) {
        isHostFlipped = flipped
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class PlacementCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private let suggestions: [BlockInputCompletionSuggestion]

    init(suggestions: [BlockInputCompletionSuggestion]) {
        self.suggestions = suggestions
    }

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        suggestions
    }
}
