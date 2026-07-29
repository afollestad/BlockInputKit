import AppKit
import SnapshotTesting
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputInlineImageSnapshotTests: XCTestCase {
    func testInlineImageSnapshots() async throws {
        for snapshotCase in InlineImageSnapshotCase.matrix {
            let view = try await makeInlineImageSnapshotView(for: snapshotCase)
            assertSnapshot(
                of: view,
                as: appKitSnapshotImage(),
                named: snapshotCase.name
            )
        }
    }

    private func makeInlineImageSnapshotView(for snapshotCase: InlineImageSnapshotCase) async throws -> NSView {
        let loadedSources = [
            "https://example.com/p1.png": BlockInputImageDimensions(width: 40, height: 20),
            "https://example.com/tall.png": BlockInputImageDimensions(width: 48, height: 72)
        ]
        let view = BlockInputView(frame: NSRect(origin: .zero, size: snapshotCase.size))
        view.appearance = NSAppearance(named: snapshotCase.appearance)
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "badge", text: "Codex flags **![P1](https://example.com/p1.png) Add the required commit trailer** here"),
                BlockInputBlock(id: "tall", text: "Tall inline ![Photo](https://example.com/tall.png) grows this line"),
                BlockInputBlock(id: "pending", text: "Pending ![Later](https://example.com/pending.png) placeholder")
            ]),
            allowsBlockReordering: false,
            dropIndicatorColor: .systemBlue,
            imageLoader: SizedInlineImageLoader(sizesBySource: loadedSources)
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        for source in loadedSources.keys {
            try await waitForInlineImage(source: source, in: view)
        }
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        return view
    }

    private func waitForInlineImage(source: String, in view: BlockInputView) async throws {
        for _ in 0..<40 {
            if view.inlineImageStore.image(forSource: source) != nil {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Inline image did not load for snapshot: \(source)")
    }
}

private struct InlineImageSnapshotCase {
    var name: String
    var appearance: NSAppearance.Name
    var size: CGSize

    static let matrix: [Self] = [
        Self(name: "inline-images-light", appearance: .aqua, size: CGSize(width: 560, height: 260)),
        Self(name: "inline-images-dark", appearance: .darkAqua, size: CGSize(width: 560, height: 260))
    ]
}
