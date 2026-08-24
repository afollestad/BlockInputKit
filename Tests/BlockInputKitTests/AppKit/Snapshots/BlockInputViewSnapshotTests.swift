import AppKit
import SnapshotTesting
import XCTest
@testable import BlockInputKit

@MainActor
final class BlockInputViewSnapshotTests: XCTestCase {
    func testRepresentativeDocumentSnapshots() {
        for snapshotCase in SnapshotCase.representativeMatrix {
            assertSnapshot(
                of: makeSnapshotView(for: snapshotCase),
                as: appKitSnapshotImage(),
                named: snapshotCase.name
            )
        }
    }

    func testListMarkerAlignmentSnapshots() {
        for snapshotCase in ListMarkerSnapshotCase.matrix {
            assertSnapshot(
                of: ListMarkerAlignmentSnapshotView(snapshotCase: snapshotCase),
                as: appKitSnapshotImage(),
                named: snapshotCase.name
            )
        }
    }

    func testLinkEditModalSnapshots() {
        for snapshotCase in LinkModalSnapshotCase.matrix {
            assertSnapshot(
                of: makeLinkModalSnapshotView(for: snapshotCase),
                as: appKitSnapshotImage(),
                named: snapshotCase.name
            )
        }
    }

    func testCompletionPopupSnapshots() {
        for snapshotCase in CompletionPopupSnapshotCase.matrix {
            assertSnapshot(
                of: CompletionPopupSnapshotView(snapshotCase: snapshotCase),
                as: appKitSnapshotImage(),
                named: snapshotCase.name
            )
        }
    }

    func testCompletionPopupPlacementSnapshots() async throws {
        for snapshotCase in CompletionPopupPlacementSnapshotCase.matrix {
            let mounted = try await makeCompletionPlacementSnapshotView(for: snapshotCase)
            assertSnapshot(
                of: mounted.snapshotView,
                as: appKitSnapshotImage(),
                named: snapshotCase.name
            )
        }
    }

    func testFileChipSnapshots() {
        for snapshotCase in FileChipSnapshotCase.matrix {
            assertSnapshot(
                of: makeFileChipSnapshotView(for: snapshotCase),
                as: appKitSnapshotImage(),
                named: snapshotCase.name
            )
        }
    }

    func testLineSpacedFileChipSnapshots() {
        for snapshotCase in FileChipSnapshotCase.matrix {
            assertSnapshot(
                of: makeLineSpacedFileChipSnapshotView(for: snapshotCase),
                as: appKitSnapshotImage(),
                named: "line-spaced-\(snapshotCase.name)"
            )
        }
    }

    func testSelectedFileChipSnapshots() {
        for snapshotCase in FileChipSnapshotCase.matrix {
            assertSnapshot(
                of: makeSelectedFileChipSnapshotView(for: snapshotCase),
                as: appKitSnapshotImage(),
                named: "selected-\(snapshotCase.name)"
            )
        }
    }

    func testWholeSelectedFileChipSnapshots() {
        for snapshotCase in FileChipSnapshotCase.matrix {
            assertSnapshot(
                of: makeWholeSelectedFileChipSnapshotView(for: snapshotCase),
                as: appKitSnapshotImage(),
                named: "whole-selected-\(snapshotCase.name)"
            )
        }
    }

    func testCustomYellowChipStyleSnapshot() {
        assertSnapshot(
            of: makeCustomYellowChipStyleSnapshotView(),
            as: appKitSnapshotImage(),
            named: "custom-yellow-chip-style"
        )
    }

    private func makeSnapshotView(for snapshotCase: SnapshotCase) -> NSView {
        let view = BlockInputView(frame: NSRect(origin: .zero, size: snapshotCase.size))
        view.appearance = NSAppearance(named: snapshotCase.appearance)
        view.configure(BlockInputConfiguration(
            document: .snapshotRepresentative,
            // Snapshot the steady-state editor surface; hover-only drag chrome is covered by layout tests.
            allowsBlockReordering: false,
            dropIndicatorColor: .systemBlue
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        return view
    }

    private func makeLinkModalSnapshotView(for snapshotCase: LinkModalSnapshotCase) -> NSView {
        let view = BlockInputView(frame: NSRect(origin: .zero, size: snapshotCase.size))
        view.appearance = NSAppearance(named: snapshotCase.appearance)
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", text: "Open [Documentation](https://example.com/docs)")
            ]),
            allowsBlockReordering: false,
            dropIndicatorColor: .systemBlue
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        guard let linkRange = BlockInputInlineMarkdownParsing.inlineMarkdownRanges(
            in: view.document.blocks[0].text
        ).first(where: { $0.style == .link }) else {
            XCTFail("Expected a snapshot link range.")
            return view
        }
        let anchorWindowRect = view.visibleBlockItemForTesting(at: 0)?.anchorWindowRect(forUTF16Range: linkRange.contentRange) ?? .zero
        let context = BlockInputLinkContext(
            blockID: "paragraph",
            mode: .edit(linkRange),
            sourceRange: NSRange(location: 6, length: 0),
            sourceText: view.document.blocks[0].text,
            anchorWindowRect: anchorWindowRect
        )
        view.showLinkModal(context: context)
        view.linkModalView?.window?.makeFirstResponder(view.linkModalView)
        return view
    }

    private func makeCompletionPlacementSnapshotView(
        for snapshotCase: CompletionPopupPlacementSnapshotCase
    ) async throws -> (snapshotView: NSView, window: NSWindow) {
        let provider = SnapshotCompletionProvider(suggestions: [
            .fileLink(label: "Sources/BlockInputView.swift", fileURL: URL(fileURLWithPath: "/tmp/BlockInputView.swift")),
            .fileLink(label: "../Package.swift", fileURL: URL(fileURLWithPath: "/tmp/Package.swift")),
            .fileLink(label: ".../README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        ])
        let hostExtraHeight: CGFloat = snapshotCase.placement == .overlay ? 180 : 0
        let windowSize = CGSize(width: snapshotCase.size.width, height: snapshotCase.size.height + hostExtraHeight)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = BlockInputView(frame: NSRect(origin: .zero, size: snapshotCase.size))
        view.appearance = NSAppearance(named: snapshotCase.appearance)
        let snapshotView: NSView
        if snapshotCase.placement == .overlay {
            let host = NSView(frame: NSRect(origin: .zero, size: windowSize))
            host.appearance = NSAppearance(named: snapshotCase.appearance)
            host.wantsLayer = true
            host.layer?.backgroundColor = snapshotBackgroundColor(for: snapshotCase.appearance).cgColor
            host.addSubview(view)
            window.contentView = host
            snapshotView = host
        } else {
            window.contentView = view
            snapshotView = view
        }
        view.configure(BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: "paragraph", text: "Mention @read in this paragraph.")
            ]),
            allowsBlockReordering: false,
            dropIndicatorColor: .systemBlue,
            completionProvider: provider,
            completionPopupPlacement: snapshotCase.placement
        ))
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        let item = try XCTUnwrap(view.visibleBlockItemForTesting(at: 0))
        let textView = try XCTUnwrap(item.testingTextView)
        textView.setSelectedRange(NSRange(location: ("Mention @read" as NSString).length, length: 0))
        view.refreshCompletionSession(item: item, blockID: "paragraph")
        await view.completionRequestTask?.value
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        view.completionPopupView?.layoutSubtreeIfNeeded()
        return (snapshotView, window)
    }

    private func snapshotBackgroundColor(for appearance: NSAppearance.Name) -> NSColor {
        appearance == .darkAqua ? NSColor(calibratedWhite: 0.11, alpha: 1) : NSColor.white
    }
}

private struct SnapshotCase {
    var name: String
    var appearance: NSAppearance.Name
    var size: CGSize

    static let representativeMatrix: [Self] = [
        Self(name: "light-default", appearance: .aqua, size: CGSize(width: 680, height: 460)),
        Self(name: "dark-default", appearance: .darkAqua, size: CGSize(width: 680, height: 460)),
        Self(name: "light-large", appearance: .aqua, size: CGSize(width: 920, height: 620)),
        Self(name: "dark-large", appearance: .darkAqua, size: CGSize(width: 920, height: 620))
    ]

}

private struct LinkModalSnapshotCase {
    var name: String
    var appearance: NSAppearance.Name
    var size: CGSize

    static let matrix: [Self] = [
        Self(name: "link-modal-light", appearance: .aqua, size: CGSize(width: 620, height: 280)),
        Self(name: "link-modal-dark", appearance: .darkAqua, size: CGSize(width: 620, height: 280))
    ]
}

private struct CompletionPopupSnapshotCase {
    var name: String
    var appearance: NSAppearance.Name
    var state: BlockInputCompletionPopupState

    static let matrix: [Self] = [
        Self(
            name: "completion-popup-loading",
            appearance: .aqua,
            state: BlockInputCompletionPopupState(suggestions: [], highlightedIndex: 0, isLoading: true)
        ),
        Self(
            name: "completion-popup-empty",
            appearance: .aqua,
            state: BlockInputCompletionPopupState(suggestions: [], highlightedIndex: 0, isLoading: false)
        ),
        Self(
            name: "completion-popup-populated",
            appearance: .aqua,
            state: BlockInputCompletionPopupState(
                suggestions: [
                    .fileLink(label: "Sources/BlockInputKit/README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md")),
                    .fileLink(label: "../Package.swift", fileURL: URL(fileURLWithPath: "/tmp/Package.swift")),
                    .fileLink(label: ".../Sources/AppKit/BlockInputView.swift", fileURL: URL(fileURLWithPath: "/tmp/BlockInputView.swift"))
                ],
                highlightedIndex: 1,
                isLoading: false
            )
        )
    ]
}

private struct CompletionPopupPlacementSnapshotCase {
    var name: String
    var appearance: NSAppearance.Name
    var size: CGSize
    var placement: BlockInputCompletionPopupPlacement

    static let matrix: [Self] = [
        Self(name: "completion-placement-caret", appearance: .aqua, size: CGSize(width: 560, height: 220), placement: .caret),
        Self(name: "completion-placement-overlay", appearance: .aqua, size: CGSize(width: 560, height: 220), placement: .overlay)
    ]
}

private final class CompletionPopupSnapshotView: NSView {
    private let popupView = BlockInputCompletionPopupView()
    private let snapshotCase: CompletionPopupSnapshotCase
    private let backgroundColor: NSColor

    init(snapshotCase: CompletionPopupSnapshotCase) {
        self.snapshotCase = snapshotCase
        backgroundColor = snapshotCase.appearance == .darkAqua
            ? NSColor(calibratedWhite: 0.11, alpha: 1)
            : NSColor.white
        super.init(frame: NSRect(origin: .zero, size: CGSize(width: 420, height: 120)))
        appearance = NSAppearance(named: snapshotCase.appearance)
        popupView.configure(state: snapshotCase.state, style: .default, onSelect: { _ in }, onHighlight: { _ in })
        addSubview(popupView)
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
        let popupHeight = BlockInputCompletionPopupView.measuredHeight(for: snapshotCase.state)
        popupView.frame = NSRect(x: 20, y: bounds.maxY - popupHeight - 20, width: 380, height: popupHeight)
    }
}

private final class SnapshotCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    private let suggestions: [BlockInputCompletionSuggestion]

    init(suggestions: [BlockInputCompletionSuggestion]) {
        self.suggestions = suggestions
    }

    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        suggestions
    }
}

private extension BlockInputDocument {
    // One document intentionally covers all built-in block renderers so the
    // appearance/size matrix stays small and stable.
    static let snapshotRepresentative = BlockInputDocument(blocks: [
        BlockInputBlock(id: "frontmatter", kind: .frontMatter, text: "title: Demo\npublished: true\nbad line"),
        BlockInputBlock(id: "heading", kind: .heading(level: 1), text: "BlockInputKit demo"),
        BlockInputBlock(id: "paragraph", kind: .paragraph, text: "Each visible block owns its own AppKit text input."),
        BlockInputBlock(id: "table", kind: .table, text: """
        | Feature | Status |
        | --- | :---: |
        | Tables | Rendering |
        | Horizontal overflow | Stable |
        """),
        BlockInputBlock(id: "quote", kind: .quote, text: "Focus, selection, return, delete, and Cmd+A coordinate across blocks."),
        BlockInputBlock(id: "code", kind: .code(language: "swift"), text: "let editor = BlockInputView()\neditor.focusEditor()"),
        BlockInputBlock(
            id: "bullets",
            kind: .bulletedListItem,
            text: "Hover rows to reveal reorder handles\nNested bullet\nDeep nested bullet",
            lineIndentationLevels: [0, 1, 2]
        ),
        BlockInputBlock(
            id: "numbers",
            kind: .numberedListItem(start: 1),
            text: "Toggle reordering from the toolbar\nNested ordered item\nDeep nested ordered item",
            lineIndentationLevels: [0, 1, 2]
        ),
        BlockInputBlock(id: "check-open", kind: .checklistItem(isChecked: false), text: "Checklist data round-trips through Markdown"),
        BlockInputBlock(id: "check-done", kind: .checklistItem(isChecked: true), text: "Checked state renders without Markdown text"),
        BlockInputBlock(id: "rule", kind: .horizontalRule),
        BlockInputBlock(id: "tail", kind: .paragraph, text: "Try inline code: `@av`")
    ])
}
