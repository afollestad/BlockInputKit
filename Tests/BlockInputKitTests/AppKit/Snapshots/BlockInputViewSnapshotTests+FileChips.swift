import AppKit
import XCTest
@testable import BlockInputKit

extension BlockInputViewSnapshotTests {
    func makeFileChipSnapshotView(for snapshotCase: FileChipSnapshotCase) -> NSView {
        let view = BlockInputView(frame: NSRect(origin: .zero, size: snapshotCase.size))
        view.appearance = NSAppearance(named: snapshotCase.appearance)
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", text: "Linked [../README.md](<file:///tmp/README.md>) from the launch folder")
            ]),
            allowsBlockReordering: false,
            dropIndicatorColor: .systemBlue
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        return view
    }

    /// A chip on a wrapped, line-spaced paragraph: the case where the gap between the chip fill
    /// and the next line's glyphs is what the spacing is meant to open up.
    func makeLineSpacedFileChipSnapshotView(for snapshotCase: FileChipSnapshotCase) -> NSView {
        let view = BlockInputView(frame: NSRect(origin: .zero, size: snapshotCase.size))
        view.appearance = NSAppearance(named: snapshotCase.appearance)
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(
                    id: "paragraph",
                    text: "Linked [../README.md](<file:///tmp/README.md>) from the launch folder, "
                        + "with enough trailing prose to wrap onto a second and third rendered line."
                )
            ]),
            allowsBlockReordering: false,
            dropIndicatorColor: .systemBlue,
            style: BlockInputStyle(baseText: BlockInputTextStyle(lineSpacing: 3))
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        return view
    }

    func makeSelectedFileChipSnapshotView(for snapshotCase: FileChipSnapshotCase) -> NSView {
        let view = BlockInputView(frame: NSRect(origin: .zero, size: snapshotCase.size))
        view.appearance = NSAppearance(named: snapshotCase.appearance)
        let blockID: BlockInputBlockID = "paragraph"
        let text = "Linked [../README.md](<file:///tmp/README.md>) from the launch folder"
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            allowsBlockReordering: false,
            dropIndicatorColor: .systemBlue
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        let hasFileChip = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: text,
            excluding: BlockInputCodeParsing.inlineCodeRanges(in: text).map(\.fullRange)
        )
        .contains { $0.inlineChipKind(in: text) != nil }
        guard hasFileChip else {
            XCTFail("Expected a selected file-chip snapshot range.")
            return view
        }
        let fromRange = (text as NSString).range(of: " from")
        let selectedRange = NSRange(location: 0, length: NSMaxRange(fromRange))
        view.applySelection(.text(BlockInputTextRange(blockID: blockID, range: selectedRange)), notify: false)
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        return view
    }

    func makeWholeSelectedFileChipSnapshotView(for snapshotCase: FileChipSnapshotCase) -> NSView {
        let view = BlockInputView(frame: NSRect(origin: .zero, size: snapshotCase.size))
        view.appearance = NSAppearance(named: snapshotCase.appearance)
        let blockID: BlockInputBlockID = "paragraph"
        let text = "[.agents/checks/javascript-rules.md](<file:///tmp/.agents/checks/javascript-rules.md>) "
        let chipStyle = BlockInputInlineChipStyle(
            fillColor: NSColor(srgbRed: 0.55, green: 0.42, blue: 0.14, alpha: 1),
            strokeColor: nil,
            foregroundColor: .white,
            cornerRadius: 5
        )
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: blockID, text: text)
            ]),
            allowsBlockReordering: false,
            dropIndicatorColor: .systemBlue,
            style: BlockInputStyle(
                selectionBackgroundColor: NSColor(calibratedWhite: 0.36, alpha: 1),
                fileChip: chipStyle
            )
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        view.applySelection(.blocks([blockID]), notify: false)
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        return view
    }
}

struct FileChipSnapshotCase {
    var name: String
    var appearance: NSAppearance.Name
    var size: CGSize

    static let matrix: [Self] = [
        Self(name: "file-chip-light", appearance: .aqua, size: CGSize(width: 620, height: 120)),
        Self(name: "file-chip-dark", appearance: .darkAqua, size: CGSize(width: 620, height: 120))
    ]
}
