import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
struct ListMarkerSnapshotCase {
    var name: String
    var appearance: NSAppearance.Name
    var size: CGSize
    var font: NSFont
    var itemHeight: CGFloat

    static let matrix: [Self] = [
        Self(
            name: "list-marker-alignment-light",
            appearance: .aqua,
            size: CGSize(width: 520, height: 96),
            font: .preferredFont(forTextStyle: .body),
            itemHeight: 40
        ),
        Self(
            name: "list-marker-alignment-dark",
            appearance: .darkAqua,
            size: CGSize(width: 520, height: 96),
            font: .preferredFont(forTextStyle: .body),
            itemHeight: 40
        ),
        Self(
            name: "list-marker-alignment-light-large",
            appearance: .aqua,
            size: CGSize(width: 760, height: 140),
            font: .systemFont(ofSize: 24),
            itemHeight: 58
        ),
        Self(
            name: "list-marker-alignment-dark-large",
            appearance: .darkAqua,
            size: CGSize(width: 760, height: 140),
            font: .systemFont(ofSize: 24),
            itemHeight: 58
        )
    ]
}

final class ListMarkerAlignmentSnapshotView: NSView {
    private let delegate = BlockInputView()
    private let stackView = NSStackView()
    private let items: [BlockInputBlockItem]
    private let backgroundColor: NSColor
    private let snapshotCase: ListMarkerSnapshotCase

    init(snapshotCase: ListMarkerSnapshotCase) {
        self.snapshotCase = snapshotCase
        backgroundColor = snapshotCase.appearance == .darkAqua
            ? NSColor(calibratedWhite: 0.11, alpha: 1)
            : NSColor.white
        items = [
            Self.makeItem(
                block: BlockInputBlock(
                    id: "bullet",
                    kind: .bulletedListItem,
                    text: "Hover rows to reveal reorder handles",
                    lineIndentationLevels: [0]
                ),
                delegate: delegate
            ),
            Self.makeItem(
                block: BlockInputBlock(
                    id: "number",
                    kind: .numberedListItem(start: 1),
                    text: "Toggle reordering from the toolbar",
                    lineIndentationLevels: [0]
                ),
                delegate: delegate
            )
        ]
        super.init(frame: NSRect(origin: .zero, size: snapshotCase.size))
        appearance = NSAppearance(named: snapshotCase.appearance)
        configureStackView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }

    override func layout() {
        super.layout()
        items.forEach { item in
            Self.applyFont(snapshotCase.font, to: item)
            item.view.layoutSubtreeIfNeeded()
            item.updateMarkerLineYOffsets()
        }
    }

    private static func makeItem(
        block: BlockInputBlock,
        delegate: BlockInputBlockItemDelegate
    ) -> BlockInputBlockItem {
        BlockInputBlockItem.configuredForTesting(
            block: block,
            allowsReordering: false,
            delegate: delegate
        )
    }

    private static func applyFont(_ font: NSFont, to item: BlockInputBlockItem) {
        guard let textView = item.testingTextView,
              let markerView = item.testingMarkerView else {
            return
        }
        textView.font = font
        textView.textStorage?.addAttribute(
            .font,
            value: font,
            range: NSRange(location: 0, length: (textView.string as NSString).length)
        )
        markerView.font = font
    }

    private func configureStackView() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        addSubview(stackView)
        items.forEach { item in
            item.view.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(item.view)
            NSLayoutConstraint.activate([
                item.view.widthAnchor.constraint(equalTo: stackView.widthAnchor),
                item.view.heightAnchor.constraint(equalToConstant: snapshotCase.itemHeight)
            ])
        }
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
