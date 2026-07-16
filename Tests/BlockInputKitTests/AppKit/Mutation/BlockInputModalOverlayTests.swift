import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputModalOverlayTests: XCTestCase {
    func testPresentedEditorInteractionUITracksLinkAndImageModals() {
        let mounted = makeHostedEditor()

        XCTAssertFalse(mounted.view.hasPresentedEditorInteractionUI)

        mounted.view.showLinkModal(context: linkContext(in: mounted))
        XCTAssertTrue(mounted.view.hasPresentedEditorInteractionUI)

        mounted.view.dismissLinkModal(restoreFocus: false)
        XCTAssertFalse(mounted.view.hasPresentedEditorInteractionUI)

        mounted.view.showImageModal(context: imageContext(in: mounted))
        XCTAssertTrue(mounted.view.hasPresentedEditorInteractionUI)

        mounted.view.dismissImageModal(restoreFocus: false)
        XCTAssertFalse(mounted.view.hasPresentedEditorInteractionUI)
    }

    func testLinkModalOverlayProviderControlsContainerAndFrame() throws {
        let customFrame = NSRect(x: 24, y: 30, width: 312, height: 156)
        var capturedKind: BlockInputModalKind?
        var capturedDefaultFrame: NSRect?
        let mounted = makeHostedEditor { container in
            { context in
                capturedKind = context.kind
                capturedDefaultFrame = context.defaultFrame
                return BlockInputModalOverlay(container: container, frame: customFrame)
            }
        }

        mounted.view.showLinkModal(context: linkContext(in: mounted))

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertTrue(modal.superview === mounted.overlayContainer)
        XCTAssertTrue(mounted.overlayContainer.subviews.last === modal)
        XCTAssertEqual(modal.frame, customFrame)
        XCTAssertLessThan(mounted.host.convert(modal.frame, from: mounted.overlayContainer).minX, mounted.view.frame.minX)
        XCTAssertEqual(capturedKind, .link)
        XCTAssertGreaterThanOrEqual(capturedDefaultFrame?.width ?? 0, 300)
        XCTAssertGreaterThanOrEqual(capturedDefaultFrame?.height ?? 0, 148)
    }

    func testImageModalOverlayProviderControlsContainerAndFrame() throws {
        let customFrame = NSRect(x: 40, y: 48, width: 320, height: 160)
        var capturedKind: BlockInputModalKind?
        let mounted = makeHostedEditor { container in
            { context in
                capturedKind = context.kind
                return BlockInputModalOverlay(container: container, frame: customFrame)
            }
        }

        mounted.view.showImageModal(context: imageContext(in: mounted))

        let modal = try XCTUnwrap(mounted.view.imageModalView)
        XCTAssertTrue(modal.superview === mounted.overlayContainer)
        XCTAssertTrue(mounted.overlayContainer.subviews.last === modal)
        XCTAssertEqual(modal.frame, customFrame)
        XCTAssertEqual(capturedKind, .image)
    }

    func testModalOverlayContextComputesHostClampedFrame() throws {
        let mounted = makeHostedEditor { container in
            { context in
                BlockInputModalOverlay(container: container, frame: context.modalFrame(in: container))
            }
        }
        let context = linkContext(
            in: mounted,
            anchorHostRect: NSRect(x: mounted.host.bounds.maxX - 8, y: mounted.host.bounds.maxY - 8, width: 40, height: 18)
        )

        mounted.view.showLinkModal(context: context)

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertGreaterThanOrEqual(modal.frame.minX, mounted.overlayContainer.bounds.minX + 12)
        XCTAssertLessThanOrEqual(modal.frame.maxX, mounted.overlayContainer.bounds.maxX - 12)
        XCTAssertGreaterThanOrEqual(modal.frame.minY, mounted.overlayContainer.bounds.minY + 12)
        XCTAssertLessThanOrEqual(modal.frame.maxY, mounted.overlayContainer.bounds.maxY - 12)
    }

    func testModalOverlayContextComputesFlippedHostClampedFrame() throws {
        let mounted = makeHostedEditor(overlayContainerIsFlipped: true) { container in
            { context in
                BlockInputModalOverlay(container: container, frame: context.modalFrame(in: container))
            }
        }
        let context = linkContext(
            in: mounted,
            anchorHostRect: NSRect(x: mounted.host.bounds.maxX - 8, y: mounted.host.bounds.maxY - 8, width: 40, height: 18)
        )

        mounted.view.showLinkModal(context: context)

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertTrue(mounted.overlayContainer.isFlipped)
        XCTAssertGreaterThanOrEqual(modal.frame.minX, mounted.overlayContainer.bounds.minX + 12)
        XCTAssertLessThanOrEqual(modal.frame.maxX, mounted.overlayContainer.bounds.maxX - 12)
        XCTAssertGreaterThanOrEqual(modal.frame.minY, mounted.overlayContainer.bounds.minY + 12)
        XCTAssertLessThanOrEqual(modal.frame.maxY, mounted.overlayContainer.bounds.maxY - 12)
    }

    func testDefaultModalOverlayKeepsModalInEditor() throws {
        let mounted = makeHostedEditor()

        mounted.view.showLinkModal(context: linkContext(in: mounted))

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        XCTAssertTrue(modal.superview === mounted.view)
        XCTAssertGreaterThanOrEqual(modal.frame.minX, mounted.view.bounds.minX + 12)
    }

    func testRehostedLinkModalDismissalTreatsModalClicksAsInside() throws {
        let mounted = makeHostedEditor { container in
            { context in
                BlockInputModalOverlay(container: container, frame: context.modalFrame(in: container))
            }
        }
        mounted.view.showLinkModal(
            context: linkContext(in: mounted),
            urlString: "https://example.com"
        )

        let modal = try XCTUnwrap(mounted.view.linkModalView)
        let modalPoint = modal.convert(NSPoint(x: modal.bounds.midX, y: modal.bounds.midY), to: nil)
        let mouseDown = try mouseDownEvent(location: modalPoint, windowNumber: mounted.window.windowNumber)

        XCTAssertFalse(mounted.view.dismissLinkModalIfMouseDownMovedFocusOutside(mouseDown))
        XCTAssertNotNil(mounted.view.linkModalView)
    }

    func testRehostedModalIsRemovedWhenEditorDetaches() throws {
        let mounted = makeHostedEditor { container in
            { context in
                BlockInputModalOverlay(container: container, frame: context.modalFrame(in: container))
            }
        }
        mounted.view.showLinkModal(context: linkContext(in: mounted))
        let modal = try XCTUnwrap(mounted.view.linkModalView)

        mounted.view.removeFromSuperview()

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertNil(modal.superview)
    }

    func testOpeningOneMutationModalDismissesTheOtherAndCompletionPopup() throws {
        let mounted = makeHostedEditor { container in
            { context in
                BlockInputModalOverlay(container: container, frame: context.modalFrame(in: container))
            }
        }
        let popup = BlockInputCompletionPopupView()
        mounted.view.completionPopupView = popup
        mounted.view.addSubview(popup)

        mounted.view.showLinkModal(context: linkContext(in: mounted))
        let linkModal = try XCTUnwrap(mounted.view.linkModalView)
        mounted.view.showImageModal(context: imageContext(in: mounted))

        XCTAssertNil(mounted.view.linkModalView)
        XCTAssertNil(linkModal.superview)
        XCTAssertNil(mounted.view.completionPopupView)
        XCTAssertNil(popup.superview)
        XCTAssertNotNil(mounted.view.imageModalView)
    }

    private func makeHostedEditor(
        overlayContainerIsFlipped: Bool = false,
        modalOverlayProvider: ((NSView) -> (@MainActor (BlockInputModalOverlayContext) -> BlockInputModalOverlay?))? = nil
    ) -> HostedModalMount {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let host = ModalOverlayHostView(frame: window.contentView?.bounds ?? window.frame)
        let overlayContainer: NSView = overlayContainerIsFlipped
            ? FlippedModalOverlayContainerView(frame: host.bounds)
            : NSView(frame: host.bounds)
        let view = BlockInputView(frame: NSRect(x: 160, y: 190, width: 190, height: 84))
        window.contentView = host
        host.addSubview(view)
        host.addSubview(overlayContainer, positioned: .above, relativeTo: view)
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", text: "Open docs")
            ]),
            modalOverlayProvider: modalOverlayProvider?(overlayContainer)
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        return HostedModalMount(window: window, host: host, overlayContainer: overlayContainer, view: view)
    }

    private func linkContext(
        in mounted: HostedModalMount,
        anchorHostRect: NSRect = NSRect(x: 200, y: 230, width: 96, height: 22)
    ) -> BlockInputLinkContext {
        let windowRect = mounted.host.convert(anchorHostRect, to: nil)
        return BlockInputLinkContext(
            blockID: "paragraph",
            mode: .create(NSRange(location: 5, length: 4)),
            sourceRange: NSRange(location: 5, length: 4),
            sourceText: "Open docs",
            anchorWindowRect: windowRect
        )
    }

    private func imageContext(in mounted: HostedModalMount) -> BlockInputImageContext {
        let windowRect = mounted.host.convert(NSRect(x: 200, y: 230, width: 96, height: 22), to: nil)
        return BlockInputImageContext(
            blockID: "paragraph",
            selectedRange: NSRange(location: 5, length: 4),
            sourceText: "Open docs",
            anchorWindowRect: windowRect
        )
    }
}

private struct HostedModalMount {
    var window: NSWindow
    var host: NSView
    var overlayContainer: NSView
    var view: BlockInputView
}

private final class ModalOverlayHostView: NSView {
    override var isFlipped: Bool {
        true
    }
}

private final class FlippedModalOverlayContainerView: NSView {
    override var isFlipped: Bool {
        true
    }
}
