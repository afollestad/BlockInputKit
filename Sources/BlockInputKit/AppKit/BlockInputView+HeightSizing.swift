import AppKit

extension BlockInputView {
    /// Provides an intrinsic height only when rendered-content height sizing is enabled.
    public override var intrinsicContentSize: NSSize {
        guard heightSizing != nil else {
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        return NSSize(width: NSView.noIntrinsicMetric, height: preferredHeightForCurrentWidth())
    }

    /// Provides an AppKit fitting height only when rendered-content height sizing is enabled.
    public override var fittingSize: NSSize {
        guard heightSizing != nil else {
            return super.fittingSize
        }
        return NSSize(width: NSView.noIntrinsicMetric, height: preferredHeightForCurrentWidth())
    }

    /// Returns the editor's preferred height for the supplied viewport width.
    ///
    /// When `BlockInputConfiguration.heightSizing` is set, the result is clamped between the configured default and
    /// maximum visible line counts. When height sizing is not configured, this returns the natural rendered content height
    /// for currently loaded blocks.
    public func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        let viewportWidth = max(width, 0)
        guard let heightSizing else {
            return ceil(naturalContentHeight(forWidth: viewportWidth, stoppingAt: nil))
        }
        let minimumHeight = lineLimitedHeight(forLineCount: sanitizedDefaultLineCount(in: heightSizing))
        let maximumHeight = heightSizing.maximumVisibleLineCount.map {
            lineLimitedHeight(forLineCount: sanitizedMaximumLineCount($0, in: heightSizing))
        }
        let naturalHeight = naturalContentHeight(
            forWidth: viewportWidth,
            stoppingAt: maximumHeight
        )
        let cappedHeight = maximumHeight.map { min(naturalHeight, $0) } ?? naturalHeight
        return ceil(max(minimumHeight, cappedHeight))
    }

    func invalidatePreferredHeight() {
        guard heightSizing != nil else {
            return
        }
        invalidateIntrinsicContentSize()
        guard bounds.width > 0 else {
            return
        }
        schedulePreferredHeightCallback()
    }

    func preferredHeightForCurrentWidth() -> CGFloat {
        let width = bounds.width > 0 ? bounds.width : lastMeasuredContentWidthFallback
        return preferredHeight(forWidth: width)
    }

    func clampVerticalScrollOffsetIfNeeded() {
        guard heightSizing != nil else {
            return
        }
        clampVerticalScrollOffsetToDocumentBounds()
    }

    /// Pulls a scrolled-past-the-end offset back to the document's maximum.
    ///
    /// Unlike `clampVerticalScrollOffsetIfNeeded()` this ignores `heightSizing`: a document that
    /// just shrank leaves a stale offset whether or not the host sizes the editor in visible
    /// lines, and clamping to the content maximum is correct either way.
    func clampVerticalScrollOffsetToDocumentBounds() {
        let contentHeight = currentDocumentContentHeight()
        let maximumY = max(0, contentHeight - scrollView.contentSize.height)
        let origin = scrollView.contentView.bounds.origin
        guard origin.y > maximumY + 0.5 else {
            return
        }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maximumY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func scrollActiveTextSelectionToVisibleIfNeeded() {
        scrollActiveTextSelectionToVisibleNow()
        DispatchQueue.main.async { [weak self] in
            self?.scrollActiveTextSelectionToVisibleNow()
        }
    }

    private func scrollActiveTextSelectionToVisibleNow() {
        guard heightSizing != nil,
              window != nil,
              let caret = activeTextSelectionCaret,
              let item = visibleItemForActiveTextSelection(blockID: caret.blockID) else {
            return
        }
        collectionView.layoutSubtreeIfNeeded()
        item.view.layoutSubtreeIfNeeded()
        let caretRect = collectionView.convert(item.anchorWindowRect(forUTF16Offset: caret.utf16Offset), from: nil)
        scrollDocumentRectToVisibleIfNeeded(caretRect)
    }

    private var lastMeasuredContentWidthFallback: CGFloat {
        max(collectionView.bounds.width, scrollView.contentSize.width, 0)
    }

    private var activeTextSelectionCaret: (blockID: BlockInputBlockID, utf16Offset: Int)? {
        switch selection {
        case let .cursor(cursor):
            return (cursor.blockID, cursor.utf16Offset)
        case let .text(textRange):
            return (textRange.blockID, NSMaxRange(textRange.range))
        case .blocks, .mixed, nil:
            return nil
        }
    }

    private func visibleItemForActiveTextSelection(blockID: BlockInputBlockID) -> BlockInputBlockItem? {
        collectionView.visibleItems()
            .compactMap { $0 as? BlockInputBlockItem }
            .first { $0.representedBlockID == blockID }
    }

    private func scrollDocumentRectToVisibleIfNeeded(_ rect: NSRect) {
        guard rect != .zero,
              !rect.isNull,
              !rect.isInfinite,
              scrollView.contentSize.height > 0 else {
            return
        }
        let padding: CGFloat = 4
        let visibleRect = scrollView.contentView.bounds
        let minimumVisibleY = rect.minY - padding
        let maximumVisibleY = rect.maxY + padding
        let targetY: CGFloat
        if maximumVisibleY > visibleRect.maxY {
            targetY = maximumVisibleY - visibleRect.height
        } else if minimumVisibleY < visibleRect.minY {
            targetY = minimumVisibleY
        } else {
            return
        }
        let contentHeight = currentDocumentContentHeight()
        let maximumY = max(0, contentHeight - visibleRect.height)
        let clampedTargetY = min(max(targetY, 0), maximumY)
        guard abs(clampedTargetY - visibleRect.minY) > 0.5 else {
            return
        }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedTargetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func currentDocumentContentHeight() -> CGFloat {
        let layoutHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
        // While typing, mounted item frames can update before the flow layout's content size catches up.
        let visibleItemHeight = collectionView.visibleItems().reduce(CGFloat(0)) { height, item in
            max(height, item.view.frame.maxY)
        }
        return max(layoutHeight, visibleItemHeight, scrollView.contentSize.height)
    }

    private func schedulePreferredHeightCallback() {
        guard !isPreferredHeightCallbackScheduled else {
            return
        }
        isPreferredHeightCallbackScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.publishPreferredHeightIfNeeded()
        }
    }

    private func publishPreferredHeightIfNeeded() {
        isPreferredHeightCallbackScheduled = false
        guard let heightSizing,
              bounds.width > 0 else {
            return
        }
        guard heightSizing.onPreferredHeightChange != nil || heightSizing.onPreferredHeightTransition != nil else {
            return
        }
        let preferredHeight = preferredHeight(forWidth: bounds.width)
        let previousHeight = lastReportedPreferredHeight
        guard previousHeight.map({ abs($0 - preferredHeight) > 0.5 }) ?? true else {
            return
        }
        let isInitial = previousHeight == nil
        lastReportedPreferredHeight = preferredHeight
        heightSizing.onPreferredHeightChange?(preferredHeight)
        heightSizing.onPreferredHeightTransition?(BlockInputEditorHeightTransition(
            previousHeight: previousHeight,
            targetHeight: preferredHeight,
            animation: resolvedPreferredHeightAnimation(heightSizing.animation, isInitial: isInitial),
            isInitial: isInitial
        ))
    }

    private func resolvedPreferredHeightAnimation(
        _ animation: BlockInputEditorHeightAnimation?,
        isInitial: Bool
    ) -> BlockInputEditorHeightAnimation? {
        guard !isInitial,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let animation,
              animation.duration > 0 else {
            return nil
        }
        return animation
    }

    private func naturalContentHeight(forWidth width: CGFloat, stoppingAt maximumHeight: CGFloat?) -> CGFloat {
        let sectionInset = layout.sectionInset
        let horizontalInsets = sectionInset.left + sectionInset.right + scrollView.contentInsets.left + scrollView.contentInsets.right
        let availableWidth = max(width - horizontalInsets, 0)
        var height = sectionInset.top + sectionInset.bottom
        for index in 0..<blockCount {
            guard let block = block(at: index) else {
                continue
            }
            let textWidth = BlockInputBlockItem.measuredTextWidth(
                for: availableWidth,
                block: block,
                allowsReordering: allowsBlockReordering,
                editorHorizontalInset: editorHorizontalInset,
                style: style
            )
            height += BlockInputBlockItem.height(
                for: block,
                textWidth: textWidth,
                style: style,
                fileBaseURL: fileBaseURL,
                rawSlashCommandChips: rawSlashCommandChips,
                rawFileMentionChips: rawFileMentionChips,
                slashCommandAvailability: slashCommandAvailability,
                isDocumentStartBlock: index == 0,
                blockVerticalInsetMultiplier: blockVerticalInsetMultiplier,
                inlineImageSizes: inlineImageStore.sizesSnapshot()
            )
            if let maximumHeight, height >= maximumHeight {
                return height
            }
        }
        if showsProgressiveLoadingRow {
            height += progressiveLoadingRowHeight
        }
        return height
    }

    private func lineLimitedHeight(forLineCount lineCount: Int) -> CGFloat {
        let rowHeight = BlockInputBlockItem.height(
            for: BlockInputBlock(id: "__heightSizingReference__", text: "x"),
            textWidth: 10_000,
            style: style,
            fileBaseURL: fileBaseURL,
            blockVerticalInsetMultiplier: blockVerticalInsetMultiplier
        )
        return (rowHeight * CGFloat(lineCount)) + editorContentTopInset + editorVerticalInset
    }

    private func sanitizedDefaultLineCount(in heightSizing: BlockInputEditorHeightSizing) -> Int {
        max(1, heightSizing.defaultVisibleLineCount)
    }

    private func sanitizedMaximumLineCount(_ maximumLineCount: Int, in heightSizing: BlockInputEditorHeightSizing) -> Int {
        max(sanitizedDefaultLineCount(in: heightSizing), maximumLineCount)
    }
}
