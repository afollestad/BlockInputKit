import AppKit

/// Collection item that owns one AppKit text input plus block-specific chrome for a single document block.
final class BlockInputBlockItem: NSCollectionViewItem, NSTextViewDelegate {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("BlockInputBlockItem")
    static let chromeFrameAlignmentOffset: CGFloat = 0
    static let checklistButtonBaseLeading: CGFloat = chromeFrameAlignmentOffset

    static let handleWidth: CGFloat = 20
    static let handleLeading: CGFloat = 0
    static let handleTrailingGap: CGFloat = 0
    static let handleHitOutset: CGFloat = 4
    static let defaultTextLeading: CGFloat = 4
    static let horizontalChromeWidthWithHandle: CGFloat = handleLeading + handleWidth + handleTrailingGap
    static let markerGutterWidth: CGFloat = 24
    static let markerChromeWidth: CGFloat = 18
    static let minimumMarkerTextGap: CGFloat = 4
    // Mirrors the NSTextView inset plus line-fragment padding so external chrome starts at the plain-text glyph column.
    static let textContainerContentLeading: CGFloat = 9
    // Mirrors NSTextContainer's default line-fragment padding for offscreen width measurement.
    static let textContainerLineFragmentPadding: CGFloat = 5
    static let markerAlignmentLeading: CGFloat = defaultTextLeading + textContainerContentLeading
    static let listTextLeading: CGFloat = -textContainerContentLeading
    static let quoteBarIdentifier = NSUserInterfaceItemIdentifier("BlockInputQuoteBarView")
    static let quoteBarWidth: CGFloat = 6
    static let minimumQuoteBarHeight: CGFloat = 32
    static let quoteBarVerticalInset: CGFloat = 2
    static let quoteTextLeading: CGFloat = 9
    static let codeTextHorizontalPadding: CGFloat = 6
    static let horizontalRuleInnerInset: CGFloat = defaultTextLeading + 4
    static let frontMatterDividerHeight: CGFloat = 1
    static let frontMatterDividerVerticalInset: CGFloat = 10
    static let tableExternalVerticalInset: CGFloat = 6
    static let imageSurfaceHorizontalInset: CGFloat = textContainerContentLeading
    static let imageExternalVerticalInset: CGFloat = 6

    let handleView = BlockInputDragHandleView()
    let kindLabel = BlockInputMarkerView()
    let checklistButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let quoteBarView = NSView()
    let scrollView = BlockInputBlockItemScrollView()
    let codeBackgroundView = NSView()
    let tableView = BlockInputTableView()
    let imageBlockView = BlockInputImageBlockView()
    let imageCaretView = NSView()
    let horizontalRuleView = BlockInputHorizontalRuleView()
    let frontMatterDividerView = BlockInputFrontMatterDividerView()
    let selectionBackgroundView = BlockInputSelectionBackgroundView()
    let textView = BlockInputTextView(), hiddenDelimiterLayoutDelegate = BlockInputDelimiterGlyphs()
    private var trackingArea: NSTrackingArea?
    private(set) weak var delegate: BlockInputBlockItemDelegate?
    private(set) var blockID: BlockInputBlockID?
    var renderedBlock: BlockInputBlock?
    var selectionBeforeTextChange: BlockInputSelection?
    // Programmatic reuse/configuration can move NSTextView selection; do not
    // report that as user selection, especially on large store-backed docs.
    private var isConfiguringBlock = false
    var blockSelectionChrome: BlockInputBlockSelectionChrome = .none
    var temporarySelectionHighlightRange: NSRange?
    var isTrackingBlockSelectionDrag = false
    var isDraggingBlockSelection = false
    var isUpdatingBlockSelectionDrag = false
    var renderedCodeColorScheme: BlockInputSyntaxColorScheme?
    var style = BlockInputStyle.default
    var imageLoadingContext = BlockInputImageBlockLoadingContext()
    var fileBaseURL: URL?
    var allowsReordering = true
    var allowsDrops = true
    var isEditable = true
    var disabledCursor: NSCursor?
    var rawSlashCommandChips = false
    var rawFileMentionChips = false
    var selectAllBehavior = BlockInputSelectAllBehavior.focusedContentThenDocument
    var slashCommandAvailability = BlockInputSlashCommandAvailability.documentStart
    var isDocumentStartBlock = false
    var editorHorizontalInset = BlockInputConfiguration.defaultEditorHorizontalInset
    var blockVerticalInsetMultiplier: CGFloat = 1
    var handleLeadingConstraint: NSLayoutConstraint?
    var handleWidthConstraint: NSLayoutConstraint?
    var kindLabelLeadingConstraint: NSLayoutConstraint?
    var kindLabelWidthConstraint: NSLayoutConstraint?
    var checklistButtonLeadingConstraint: NSLayoutConstraint?
    var scrollViewLeadingConstraint: NSLayoutConstraint?
    var scrollViewWidthConstraint: NSLayoutConstraint?
    var scrollViewTrailingConstraint: NSLayoutConstraint?
    var scrollViewTopConstraint: NSLayoutConstraint?
    var scrollViewBottomConstraint: NSLayoutConstraint?
    var handleTopConstraint: NSLayoutConstraint?
    var kindLabelTopConstraint: NSLayoutConstraint?
    var checklistButtonTopConstraint: NSLayoutConstraint?
    var quoteBarLeadingConstraint: NSLayoutConstraint?
    var quoteBarTopConstraint: NSLayoutConstraint?
    var quoteBarBottomConstraint: NSLayoutConstraint?
    var horizontalRuleLeadingConstraint: NSLayoutConstraint?
    var horizontalRuleTrailingConstraint: NSLayoutConstraint?
    var tableViewTopConstraint: NSLayoutConstraint?
    var tableViewBottomConstraint: NSLayoutConstraint?
    var frontMatterDividerLeadingConstraint: NSLayoutConstraint?
    var frontMatterDividerTrailingConstraint: NSLayoutConstraint?
    var frontMatterDividerBottomConstraint: NSLayoutConstraint?
    var imageBlockLeadingConstraint: NSLayoutConstraint?
    var imageBlockTrailingConstraint: NSLayoutConstraint?
    var imageBlockWidthConstraint: NSLayoutConstraint?
    var imageBlockTopConstraint: NSLayoutConstraint?
    var imageBlockBottomConstraint: NSLayoutConstraint?
    var imageLoadTask: Task<Void, Never>?
    var imageLoadCacheKey: String?
    private var isHorizontalRule = false
    var isImageBlock = false
    var imageCaretOffset: Int?

    var currentSelectedRange: NSRange {
        tableView.activeCellSelectedSourceRange ?? textView.selectedRange()
    }

    var currentText: String {
        textView.string
    }

    var representedBlockID: BlockInputBlockID? {
        blockID
    }

    override func loadView() {
        let rootView = BlockInputBlockItemRootView()
        rootView.blockItem = self
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        clearConfiguration()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let renderedBlock {
            updateHorizontalConstraints(for: renderedBlock)
        }
        refreshCodeAppearanceIfNeeded()
        updateTextViewDocumentFrame()
        tableView.needsLayout = true
        updateCodeBackgroundFrame()
        updateSelectionChromeFrame()
        updateHoverTrackingArea()
        updateMarkerLineYOffsets()
        updateQuoteBarVerticalExtent()
        if let renderedBlock {
            updateImageBlockLayout(for: renderedBlock)
        }
        updateImageCaretFrame()
        textView.updateInlineHintView()
        view.window?.invalidateCursorRects(for: view)
    }

    override func mouseEntered(with event: NSEvent) {
        delegate?.blockItemDidRevealReorderHandle(self)
        setReorderHandleVisible(true)
    }

    override func mouseExited(with event: NSEvent) {
        setReorderHandleVisible(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard isHorizontalRule || isImageBlock else {
            super.mouseDown(with: event)
            return
        }
        beginBlockSelectionDrag()
        requestSelectCurrentBlock()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isHorizontalRule || isImageBlock,
              updateBlockSelectionDrag(with: event) else {
            super.mouseDragged(with: event)
            return
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isHorizontalRule || isImageBlock else {
            super.mouseUp(with: event)
            return
        }
        finishBlockSelectionDrag()
    }

    func configure(
        block: BlockInputBlock,
        allowsReordering: Bool,
        allowsDrops: Bool = true,
        editorHorizontalInset: CGFloat = BlockInputConfiguration.defaultEditorHorizontalInset,
        accentColor: NSColor = .controlAccentColor,
        style: BlockInputStyle = .default,
        blockVerticalInsetMultiplier: CGFloat = 1,
        imageLoadingContext: BlockInputImageBlockLoadingContext = BlockInputImageBlockLoadingContext(),
        fileBaseURL: URL? = nil,
        isEditable: Bool = true,
        disabledCursor: NSCursor? = nil,
        inlineHint: BlockInputInlineHint? = nil,
        rawSlashCommandChips: Bool = false,
        rawFileMentionChips: Bool = false,
        selectAllBehavior: BlockInputSelectAllBehavior = .focusedContentThenDocument,
        slashCommandAvailability: BlockInputSlashCommandAvailability = .documentStart,
        isDocumentStartBlock: Bool = false,
        isSelected: Bool = false,
        delegate: BlockInputBlockItemDelegate
    ) {
        isConfiguringBlock = true
        defer { isConfiguringBlock = false }
        blockID = block.id
        renderedBlock = block
        self.delegate = delegate
        self.allowsReordering = allowsReordering
        self.allowsDrops = allowsDrops
        self.editorHorizontalInset = editorHorizontalInset
        self.blockVerticalInsetMultiplier = BlockInputConfiguration.sanitizedBlockVerticalInsetMultiplier(blockVerticalInsetMultiplier)
        self.style = style
        self.imageLoadingContext = imageLoadingContext
        self.fileBaseURL = fileBaseURL
        applySlashCommandConfiguration(
            rawSlashCommandChips: rawSlashCommandChips,
            rawFileMentionChips: rawFileMentionChips,
            selectAllBehavior: selectAllBehavior,
            slashCommandAvailability: slashCommandAvailability,
            isDocumentStartBlock: isDocumentStartBlock
        )
        applyReadOnlyConfiguration(isEditable: isEditable, disabledCursor: disabledCursor)
        textView.inlineHint = inlineHint
        selectionBeforeTextChange = nil
        textView.hideFileDropCaret()
        isHorizontalRule = block.kind == .horizontalRule
        isImageBlock = block.kind.isImage
        handleView.blockItem = self
        scrollView.blockItem = self
        horizontalRuleView.blockItem = self
        horizontalRuleView.accentColor = accentColor
        textView.blockItem = self
        textView.setFileDropHandlingEnabled(allowsDrops)
        tableView.blockItem = self
        tableView.delegate = self
        textView.updateFileDropCaretColor(accentColor)
        let text = block.kind == .horizontalRule ? "" : block.text
        if textView.string != text {
            textView.string = text
        }
        configureBlockKindChrome(block: block)
        textView.updateInlineHintView()
        setBlockSelection(isSelected)
        // Frontmatter is pinned to document index 0, so keep the reorder
        // gutter width for alignment without exposing an unusable drag handle.
        let canReorderBlock = isEditable && allowsReordering && block.kind != .frontMatter
        configureReorderHandle(canReorderBlock: canReorderBlock)
        view.window?.invalidateCursorRects(for: view)
        invalidateCursorRects()
        updateHorizontalConstraints(for: block)
    }

    func updateTextDependentChrome(for block: BlockInputBlock) {
        renderedBlock = block
        configureBlockKindChrome(block: block)
        updateHorizontalConstraints(for: block)
        updateSelectionChromeFrame()
    }

    func configureReorderHandle(canReorderBlock: Bool) {
        handleView.isEnabled = canReorderBlock
        handleView.isHidden = !canReorderBlock
        handleView.alphaValue = 0
        handleView.toolTip = canReorderBlock ? "Drag to reorder block" : nil
    }

    func updateHorizontalConstraints(for block: BlockInputBlock) {
        let metrics = Self.horizontalMetrics(
            for: view.bounds.width,
            block: block,
            allowsReordering: allowsReordering,
            editorHorizontalInset: editorHorizontalInset,
            style: style
        )
        handleLeadingConstraint?.constant = metrics.handleLeading
        handleWidthConstraint?.constant = metrics.handleWidth
        kindLabelLeadingConstraint?.constant = metrics.kindLabelLeading
        kindLabelWidthConstraint?.constant = metrics.kindLabelWidth
        scrollViewLeadingConstraint?.constant = metrics.scrollViewLeading
        let usesCollapsedWidth = view.bounds.width > 0 &&
            metrics.handleWidth == 0 &&
            metrics.scrollViewTrailingInset == 0 &&
            abs(metrics.scrollViewWidth - view.bounds.width) <= 0.5
        scrollViewWidthConstraint?.priority = usesCollapsedWidth ? .required : .defaultLow
        scrollViewWidthConstraint?.constant = metrics.scrollViewWidth
        scrollViewTrailingConstraint?.constant = -metrics.scrollViewTrailingInset
        let horizontalRuleInset = min(Self.horizontalRuleInnerInset, max(metrics.scrollViewWidth / 2, 0))
        horizontalRuleLeadingConstraint?.constant = horizontalRuleInset
        horizontalRuleTrailingConstraint?.constant = -horizontalRuleInset
        frontMatterDividerLeadingConstraint?.constant = horizontalRuleInset
        frontMatterDividerTrailingConstraint?.constant = -horizontalRuleInset
        if !block.kind.isImage {
            imageBlockLeadingConstraint?.constant = 0
            imageBlockTrailingConstraint?.constant = 0
            imageBlockWidthConstraint?.constant = metrics.scrollViewWidth
        }
    }

    func updateTableCellEditState(for block: BlockInputBlock) {
        let wasConfiguringBlock = isConfiguringBlock
        isConfiguringBlock = true
        defer { isConfiguringBlock = wasConfiguringBlock }
        renderedBlock = block
        if textView.string != block.text {
            textView.string = block.text
        }
        tableView.needsLayout = true
        updateSelectionChromeFrame()
    }

    func collapseNativeSelectionIfNeeded(at offset: Int? = nil) {
        guard !isHorizontalRule,
              textView.selectedRange().length > 0 || offset != nil else {
            return
        }
        let wasConfiguringBlock = isConfiguringBlock
        isConfiguringBlock = true
        let textLength = (textView.string as NSString).length
        let location = min(max(offset ?? textView.selectedRange().location, 0), textLength)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        updateSelectionDependentAttributesForCurrentSelection()
        isConfiguringBlock = wasConfiguringBlock
    }

    func setSelectionHighlightRange(_ range: NSRange) {
        let wasConfiguringBlock = isConfiguringBlock
        isConfiguringBlock = true
        guard applyTemporarySelectionHighlight(range) else {
            applySelectionChrome(.none)
            isConfiguringBlock = wasConfiguringBlock
            return
        }
        applySelectionChrome(.partial)
        collapseNativeSelectionIfNeeded(at: range.location)
        suppressNativeSelectionDisplayForPartialChrome()
        isConfiguringBlock = wasConfiguringBlock
    }

    func textDidBeginEditing(_ notification: Notification) {
        guard let blockID else { return }
        updateSelectionDependentAttributesForCurrentSelection()
        delegate?.blockItemDidBeginEditing(self, blockID: blockID)
    }

    func textDidEndEditing(_ notification: Notification) {
        guard let blockID else { return }
        updateSelectionDependentAttributesForCurrentSelection()
        delegate?.blockItemDidEndEditing(self, blockID: blockID)
    }

    func textDidChange(_ notification: Notification) {
        guard !isConfiguringBlock else {
            return
        }
        guard let blockID else {
            return
        }
        delegate?.blockItem(
            self,
            blockID: blockID,
            didChangeText: textView.string,
            selectionBefore: selectionBeforeTextChange
        )
        selectionBeforeTextChange = nil
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isConfiguringBlock else {
            return
        }
        guard !(renderedBlock?.kind == .table && !tableView.isHidden) else {
            return
        }
        guard let blockID else {
            return
        }
        updateSelectionDependentAttributesForCurrentSelection()
        delegate?.blockItem(self, didChangeSelectionIn: blockID, selectedRange: nil)
    }

    func textView(
        _ textView: NSTextView,
        willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
        toCharacterRange newSelectedCharRange: NSRange
    ) -> NSRange {
        guard !isConfiguringBlock,
              !isUpdatingBlockSelectionDrag,
              isTrackingBlockSelectionDrag,
              let event = currentBlockSelectionDragEvent() else {
            return newSelectedCharRange
        }
        let blockTextView = textView as? BlockInputTextView
        blockTextView?.rememberBlockSelectionDragRange(newSelectedCharRange)
        guard updateBlockSelectionDrag(with: event, selectedRange: newSelectedCharRange) else {
            return newSelectedCharRange
        }
        return blockTextView?.collapsedBlockSelectionDragNativeRange() ?? oldSelectedCharRange
    }

    private func updateHoverTrackingArea() {
        if let trackingArea {
            view.removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: view.bounds,
            options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        view.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

}

extension BlockInputBlockItem {
    func setBlockSelection(_ isSelected: Bool) {
        let wasConfiguringBlock = isConfiguringBlock
        isConfiguringBlock = true
        defer { isConfiguringBlock = wasConfiguringBlock }

        clearTemporarySelectionHighlight()
        applySelectionChrome(isSelected ? .whole : .none)
        horizontalRuleView.isSelected = isHorizontalRule && isSelected
        if isSelected {
            setImageCaretOffset(nil)
        }
        if isSelected {
            collapseNativeSelectionIfNeeded()
        }
    }

    func replaceCurrentTextFromEditorCorrection(_ text: String, selectedRange: NSRange) {
        let wasConfiguringBlock = isConfiguringBlock
        isConfiguringBlock = true
        textView.string = text
        textView.setSelectedRange(selectedRange)
        updateSelectionDependentAttributesForCurrentSelection()
        isConfiguringBlock = wasConfiguringBlock
    }
}

extension BlockInputBlockItem {
    enum TextLinePosition {
        case first
        case last
    }
}

extension BlockInputBlockItem {
    func clearConfiguration() {
        clearBlockReferencesForReuse()
        resetTextForReuse()
        resetLayoutForReuse()
        resetChromeForReuse()
        view.window?.invalidateCursorRects(for: view)
    }

    private func clearBlockReferencesForReuse() {
        blockID = nil
        renderedBlock = nil
        delegate = nil
        selectionBeforeTextChange = nil
        isHorizontalRule = false
        isImageBlock = false
        setBlockSelection(false)
        handleView.blockItem = nil
        scrollView.blockItem = nil
        horizontalRuleView.blockItem = nil
        horizontalRuleView.resetForReuse()
        tableView.blockItem = nil
        tableView.delegate = nil
        renderedCodeColorScheme = nil
        rawSlashCommandChips = false
        rawFileMentionChips = false
        selectAllBehavior = .focusedContentThenDocument
        slashCommandAvailability = .documentStart
        isDocumentStartBlock = false
        textView.cancelBlockSelectionDrag()
        textView.clearInlineHint()
        textView.blockItem = nil
        finishBlockSelectionDrag()
        setImageCaretOffset(nil)
    }
}
