import AppKit
import XCTest
@testable import BlockInputKit

final class BlockInputConfigurationTests: XCTestCase {
    func testDocumentUsesConfiguredStoreWhenProvided() {
        let directID = BlockInputBlockID(rawValue: "direct")
        let storeID = BlockInputBlockID(rawValue: "store")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: storeID, text: "Store")
        ]))

        let configuration = BlockInputConfiguration(
            document: BlockInputDocument(blocks: [
                BlockInputBlock(id: directID, text: "Direct")
            ]),
            documentStore: store
        )

        XCTAssertEqual(configuration.document.blocks.map(\.id), [storeID])
    }

    func testDefaultConfigurationCreatesMemoryStoreFromDocument() {
        let blockID = BlockInputBlockID(rawValue: "direct")

        let configuration = BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, text: "Direct")
        ]))

        XCTAssertTrue(configuration.documentStore is BlockInputMemoryDocumentStore)
        XCTAssertEqual(configuration.document.blocks.map(\.id), [blockID])
        XCTAssertEqual(configuration.editorHorizontalInset, BlockInputConfiguration.defaultEditorHorizontalInset)
        XCTAssertEqual(configuration.editorVerticalInset, BlockInputConfiguration.defaultEditorVerticalInset)
        XCTAssertEqual(configuration.blockVerticalInsetMultiplier, 1)
        XCTAssertNil(configuration.placeholder)
        XCTAssertTrue(configuration.isEditable)
        XCTAssertNil(configuration.disabledCursor)
        XCTAssertNil(configuration.inlineHintProvider)
        XCTAssertFalse(configuration.rawSlashCommandChips)
        XCTAssertTrue(configuration.allowsDrops)
        XCTAssertEqual(configuration.selectAllBehavior, .focusedContentThenDocument)
        XCTAssertNil(configuration.heightSizing)
        XCTAssertEqual(configuration.completionReturnBehavior, .acceptHighlightedSuggestion)
        XCTAssertEqual(configuration.slashCommandAvailability, .documentStart)
        XCTAssertNil(configuration.slashCommandChipClickHandler)
        XCTAssertNil(configuration.onEditorInteractionUIChange)
    }

    @MainActor
    func testHeightSizingInitializerPreservesValues() {
        var reportedHeight: CGFloat?
        let trailingClosureSizing = BlockInputEditorHeightSizing(defaultVisibleLineCount: 2) { height in
            reportedHeight = height
        }
        let sizing = BlockInputEditorHeightSizing(
            defaultVisibleLineCount: 3,
            maximumVisibleLineCount: 8,
            onPreferredHeightChange: { _ in }
        )

        trailingClosureSizing.onPreferredHeightChange?(42)
        XCTAssertEqual(reportedHeight, 42)
        XCTAssertEqual(sizing.defaultVisibleLineCount, 3)
        XCTAssertEqual(sizing.maximumVisibleLineCount, 8)
        XCTAssertNotNil(sizing.onPreferredHeightChange)
        XCTAssertEqual(sizing.animation, .default)
        XCTAssertNil(sizing.onPreferredHeightTransition)
    }

    @MainActor
    func testHeightSizingTransitionInitializerPreservesValues() {
        var reportedTransition: BlockInputEditorHeightTransition?
        let sizing = BlockInputEditorHeightSizing(
            defaultVisibleLineCount: 3,
            maximumVisibleLineCount: 8,
            animation: BlockInputEditorHeightAnimation(duration: 0.1, curve: .linear),
            onPreferredHeightTransition: { reportedTransition = $0 }
        )

        XCTAssertEqual(sizing.defaultVisibleLineCount, 3)
        XCTAssertEqual(sizing.maximumVisibleLineCount, 8)
        XCTAssertNil(sizing.onPreferredHeightChange)
        XCTAssertEqual(sizing.animation, BlockInputEditorHeightAnimation(duration: 0.1, curve: .linear))
        XCTAssertNotNil(sizing.onPreferredHeightTransition)

        let transition = BlockInputEditorHeightTransition(
            previousHeight: 20,
            targetHeight: 40,
            animation: .default,
            isInitial: false
        )
        sizing.onPreferredHeightTransition?(transition)
        XCTAssertEqual(reportedTransition, transition)
    }

    func testBlockVerticalInsetMultiplierSanitizesInvalidValues() {
        XCTAssertEqual(BlockInputConfiguration(blockVerticalInsetMultiplier: 0.5).blockVerticalInsetMultiplier, 0.5)
        XCTAssertEqual(BlockInputConfiguration(blockVerticalInsetMultiplier: -1).blockVerticalInsetMultiplier, 0)
        XCTAssertEqual(BlockInputConfiguration(blockVerticalInsetMultiplier: .nan).blockVerticalInsetMultiplier, 1)

        var configuration = BlockInputConfiguration()
        configuration.blockVerticalInsetMultiplier = -CGFloat.infinity
        XCTAssertEqual(configuration.blockVerticalInsetMultiplier, 1)
    }

    @MainActor
    func testViewAppliesConfiguredIntegrationSurfaces() throws {
        let undoController = BlockInputUndoController()
        let view = BlockInputView()
        let onDocumentMutation: (BlockInputDocumentChange) -> Void = { _ in }
        let onDocumentChange: (BlockInputDocument) -> Void = { _ in }
        let onFocusChange: (Bool) -> Void = { _ in }
        let inlineHintProvider: BlockInputInlineHintProvider = { _ in BlockInputInlineHint(text: "hint") }

        view.configure(BlockInputConfiguration(
            allowsBlockReordering: false,
            allowsDrops: false,
            editorHorizontalInset: 28,
            editorVerticalInset: 14,
            blockVerticalInsetMultiplier: 0.75,
            placeholder: "Message",
            isEditable: false,
            disabledCursor: .operationNotAllowed,
            inlineHintProvider: inlineHintProvider,
            rawSlashCommandChips: true,
            dropIndicatorColor: .systemPink,
            selectAllBehavior: .document,
            heightSizing: BlockInputEditorHeightSizing(defaultVisibleLineCount: 2, maximumVisibleLineCount: 5),
            undoController: undoController,
            onDocumentMutation: onDocumentMutation,
            onDocumentChange: onDocumentChange,
            documentChangeSnapshotDelay: 0.01,
            onFocusChange: onFocusChange
        ))

        XCTAssertFalse(view.allowsBlockReordering)
        XCTAssertFalse(view.allowsDrops)
        XCTAssertEqual(view.editorHorizontalInset, 28)
        XCTAssertEqual(view.editorVerticalInset, 14)
        XCTAssertEqual(view.blockVerticalInsetMultiplier, 0.75)
        XCTAssertEqual(view.placeholder, "Message")
        XCTAssertFalse(view.isEditable)
        XCTAssertEqual(view.disabledCursor, .operationNotAllowed)
        XCTAssertNotNil(view.inlineHintProvider)
        XCTAssertTrue(view.rawSlashCommandChips)
        XCTAssertEqual(view.selectAllBehavior, .document)
        let sectionInset = try XCTUnwrap((view.collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)?.sectionInset)
        XCTAssertEqual(sectionInset.top, 14)
        XCTAssertEqual(sectionInset.bottom, 14)
        XCTAssertEqual(sectionInset.left, 0)
        XCTAssertEqual(sectionInset.right, 0)
        XCTAssertEqual(view.dropIndicatorColor, .systemPink)
        XCTAssertEqual(view.heightSizing?.defaultVisibleLineCount, 2)
        XCTAssertEqual(view.heightSizing?.maximumVisibleLineCount, 5)
        XCTAssertTrue(view.undoController === undoController)
        XCTAssertNotNil(view.onDocumentMutation)
        XCTAssertNotNil(view.onDocumentChange)
        XCTAssertEqual(view.documentChangeSnapshotDelay, 0.01)
        XCTAssertNotNil(view.onFocusChange)
    }

    @MainActor
    func testViewAppliesEditorInteractionUICallback() {
        let view = BlockInputView()

        view.configure(BlockInputConfiguration(onEditorInteractionUIChange: { _ in }))

        XCTAssertNotNil(view.onEditorInteractionUIChange)
    }

    @MainActor
    func testViewAppliesConfiguredCompletionSurfaces() {
        let provider = ConfigurationCompletionProvider()
        let view = BlockInputView()
        let container = NSView()
        let popupStyle = BlockInputCompletionPopupStyle(
            backgroundColor: .systemRed,
            borderColor: .systemBlue,
            highlightedRowBackgroundColor: .systemGreen,
            highlightedRowCornerRadius: 8,
            cornerRadius: 12,
            borderWidth: 2
        )

        view.configure(BlockInputConfiguration(
            completionProvider: provider,
            completionReturnBehavior: .passthroughExactMatch,
            slashCommandAvailability: .anywhere,
            slashCommandChipClickHandler: { _ in .hostHandled },
            completionPopupConfiguration: BlockInputCompletionPopupConfiguration(
                placement: .overlay,
                style: popupStyle,
                overlayProvider: { context in
                    BlockInputCompletionPopupOverlay(container: container, frame: context.defaultFrame)
                }
            )
        ))

        XCTAssertTrue(view.completionProvider === provider)
        XCTAssertEqual(view.completionReturnBehavior, .passthroughExactMatch)
        XCTAssertEqual(view.slashCommandAvailability, .anywhere)
        XCTAssertNotNil(view.slashCommandChipClickHandler)
        XCTAssertEqual(view.completionPopupPlacement, .overlay)
        XCTAssertEqual(view.completionPopupConfiguration.style.backgroundColor, .systemRed)
        XCTAssertEqual(view.completionPopupConfiguration.style.borderColor, .systemBlue)
        XCTAssertEqual(view.completionPopupConfiguration.style.highlightedRowBackgroundColor, .systemGreen)
        XCTAssertEqual(view.completionPopupConfiguration.style.highlightedRowCornerRadius, 8)
        XCTAssertEqual(view.completionPopupConfiguration.style.cornerRadius, 12)
        XCTAssertEqual(view.completionPopupConfiguration.style.borderWidth, 2)
        let overlay = view.completionPopupConfiguration.overlayProvider?(BlockInputCompletionPopupOverlayContext(
            editorView: view,
            defaultContainer: view,
            defaultFrame: .zero,
            popupSize: .zero
        ))
        XCTAssertTrue(overlay?.container === container)
    }

    func testCompletionPopupPlacementParameterBuildsPopupConfiguration() {
        var configuration = BlockInputConfiguration(completionPopupPlacement: .overlay)

        XCTAssertEqual(configuration.completionPopupConfiguration.placement, .overlay)
        XCTAssertEqual(configuration.completionPopupPlacement, .overlay)

        configuration.completionPopupPlacement = .caret

        XCTAssertEqual(configuration.completionPopupConfiguration.placement, .caret)
    }

    func testCompletionPopupStyleClampsNegativeMetrics() {
        let style = BlockInputCompletionPopupStyle(highlightedRowCornerRadius: -6, cornerRadius: -4, borderWidth: -1)

        XCTAssertEqual(style.highlightedRowCornerRadius, 0)
        XCTAssertEqual(style.cornerRadius, 0)
        XCTAssertEqual(style.borderWidth, 0)
    }

    func testCompletionPopupStyleDefaultsHighlightedRowCornerRadiusToPopupRadius() {
        var style = BlockInputCompletionPopupStyle(cornerRadius: 12)

        XCTAssertNil(style.highlightedRowCornerRadius)
        XCTAssertEqual(style.resolvedHighlightedRowCornerRadius, 12)

        style.cornerRadius = 7

        XCTAssertEqual(style.resolvedHighlightedRowCornerRadius, 7)
    }

    @MainActor
    func testDefaultUndoControllerResetsWhenViewReconfiguresToNewStore() throws {
        let blockID = BlockInputBlockID(rawValue: "list")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "First")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        item.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(item.requestIndent())
        XCTAssertEqual(view.document.blocks[0].indentationLevel, 1)

        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "Second")
        ])))

        XCTAssertNil(view.undoStructuralEdit())
        XCTAssertEqual(view.document.blocks[0].text, "Second")
        XCTAssertEqual(view.document.blocks[0].indentationLevel, 0)
    }

    @MainActor
    func testDefaultUndoControllerSurvivesEquivalentDefaultStoreReconfigure() throws {
        let blockID = BlockInputBlockID(rawValue: "list")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "First")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        item.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(item.requestIndent())
        XCTAssertEqual(view.document.blocks[0].indentationLevel, 1)

        view.configure(BlockInputConfiguration(document: view.document))

        XCTAssertNotNil(view.undoStructuralEdit())
        XCTAssertEqual(view.document.blocks[0].text, "First")
        XCTAssertEqual(view.document.blocks[0].indentationLevel, 0)
    }

    @MainActor
    func testDefaultUndoControllerResetsWhenDefaultConfigurationStoreIsReplaced() throws {
        let blockID = BlockInputBlockID(rawValue: "list")
        let view = BlockInputView()
        view.configure(BlockInputConfiguration(document: BlockInputDocument(blocks: [
            BlockInputBlock(id: blockID, kind: .bulletedListItem, text: "First")
        ])))
        let item = BlockInputBlockItem.configuredForTesting(
            block: view.document.blocks[0],
            allowsReordering: true,
            delegate: view
        )
        item.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(item.requestIndent())
        XCTAssertEqual(view.document.blocks[0].indentationLevel, 1)

        var configuration = BlockInputConfiguration(document: view.document)
        configuration.documentStore = BlockInputMemoryDocumentStore(document: view.document)
        view.configure(configuration)

        XCTAssertNil(view.undoStructuralEdit())
        XCTAssertEqual(view.document.blocks[0].text, "First")
        XCTAssertEqual(view.document.blocks[0].indentationLevel, 1)
    }
}

private final class ConfigurationCompletionProvider: BlockInputCompletionProvider, @unchecked Sendable {
    func suggestions(for context: BlockInputCompletionContext) async -> [BlockInputCompletionSuggestion] {
        []
    }
}
