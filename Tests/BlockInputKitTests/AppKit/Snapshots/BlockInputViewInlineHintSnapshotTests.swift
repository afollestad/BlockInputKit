import AppKit
import SnapshotTesting
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewInlineHintSnapshotTests: XCTestCase {
    func testInlineHintSnapshot() {
        let blockID = BlockInputBlockID(rawValue: "command")
        let text = BlockInputCompletionSuggestion.slashCommand(
            title: "Review GitHub PR",
            uri: "demo://review-github-pr",
            label: "review-github-pr"
        ).insertionText
        let mounted = makeInlineHintSnapshotView(blockID: blockID, text: text)
        let view = mounted.view

        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        view.focus(blockID: blockID, utf16Offset: (text as NSString).length)
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        view.updateInlineHintsForVisibleItems()

        assertSnapshot(
            of: view,
            as: appKitSnapshotImage(),
            named: "inline-hint-light"
        )
    }

    func testBareRawSlashCommandInlineHintSnapshot() {
        let blockID = BlockInputBlockID(rawValue: "command")
        let text = "/review-github-pr"
        let argumentHints = BlockInputSlashCommandArgumentHints(["review-github-pr": "[PR URL]"])
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = BlockInputView(frame: NSRect(origin: .zero, size: CGSize(width: 620, height: 180)))
        view.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            allowsBlockReordering: false,
            inlineHintProvider: { argumentHints.inlineHint(for: $0) },
            rawSlashCommandChips: true,
            dropIndicatorColor: .systemBlue
        ))

        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        view.focus(blockID: blockID, utf16Offset: (text as NSString).length)
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        view.updateInlineHintsForVisibleItems()

        assertSnapshot(
            of: view,
            as: appKitSnapshotImage(),
            named: "bare-raw-inline-hint-light"
        )
    }

    private func makeInlineHintSnapshotView(blockID: BlockInputBlockID, text: String) -> (view: BlockInputView, window: NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = BlockInputView(frame: NSRect(origin: .zero, size: CGSize(width: 620, height: 180)))
        view.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            allowsBlockReordering: false,
            inlineHintProvider: { _ in BlockInputInlineHint(text: "[PR URL]") },
            dropIndicatorColor: .systemBlue
        ))
        return (view, window)
    }
}
