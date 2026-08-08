import AppKit

extension BlockInputBlockItem {
    static var codeHorizontalScrollerReserve: CGFloat {
        floor(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay) / 2)
    }

    func configureTextScrolling(for block: BlockInputBlock) {
        switch block.kind {
        case .code:
            configureCodeTextScrolling()
        case .table:
            configureWrappingTextScrolling()
        case .paragraph, .heading, .horizontalRule, .frontMatter, .quote, .bulletedListItem, .numberedListItem, .checklistItem,
             .image, .rawMarkdown:
            configureWrappingTextScrolling()
        }
    }

    func configureWrappingTextScrolling() {
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        setWrappingContainerWidth(scrollView.contentView.bounds.width)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func configureCodeTextScrolling() {
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = []
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    func textScrollViewDidChangeVisibleBounds() {
        guard case .code = renderedBlock?.kind else {
            return
        }
        updateCodeBackgroundFrame()
        updateSelectionChromeFrame()
    }

    var visibleTextViewportInItemCoordinates: NSRect {
        let viewport = scrollView.contentView.convert(scrollView.contentView.bounds, to: view)
        guard case .code = renderedBlock?.kind,
              !codeBackgroundView.isHidden else {
            return viewport
        }
        let clippedViewport = viewport.intersection(codeBackgroundView.frame)
        return clippedViewport.isNull ? viewport : clippedViewport
    }

    func updateTextViewDocumentFrame() {
        let contentBounds = scrollView.contentView.bounds
        guard !(renderedBlock?.kind == .table && !tableView.isHidden) else {
            return
        }
        guard contentBounds.width > 0, contentBounds.height > 0 else {
            return
        }
        let isCodeBlock: Bool
        if case .code = renderedBlock?.kind {
            isCodeBlock = true
        } else {
            isCodeBlock = false
        }
        if !isCodeBlock {
            setWrappingContainerWidth(contentBounds.width)
        }
        let fittingHeight = fittingTextHeight(defaultingTo: contentBounds.height)
        let fittingWidth = fittingTextWidth(defaultingTo: contentBounds.width)
        let targetWidth = isCodeBlock ? max(contentBounds.width, fittingWidth) : contentBounds.width
        let horizontalScrollerReserve = isCodeBlock && targetWidth > contentBounds.width
            ? Self.codeHorizontalScrollerReserve
            : 0
        let targetSize = NSSize(
            width: targetWidth,
            height: max(contentBounds.height, fittingHeight + horizontalScrollerReserve)
        )
        if abs(textView.frame.width - targetSize.width) > 0.5 ||
            abs(textView.frame.height - targetSize.height) > 0.5 {
            textView.frame = NSRect(origin: .zero, size: targetSize)
        }
        let maximumX = max(0, targetSize.width - contentBounds.width)
        let targetOrigin = NSPoint(
            x: isCodeBlock ? min(max(contentBounds.origin.x, 0), maximumX) : 0,
            y: 0
        )
        if scrollView.contentView.bounds.origin != targetOrigin {
            scrollView.contentView.scroll(to: targetOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    /// Assigns the wrapping container the width `widthTracksTextView` would derive from a
    /// text view spanning `viewportWidth`. Writing the viewport width straight through
    /// instead left the container 2 × `textContainerInset.width` too wide until the next
    /// frame change reset it, so the same block wrapped differently depending on whether
    /// this layout pass happened to resize the text view.
    private func setWrappingContainerWidth(_ viewportWidth: CGFloat) {
        textView.textContainer?.containerSize = NSSize(
            width: max(viewportWidth - 2 * textView.textContainerInset.width, 1),
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    private func fittingTextHeight(defaultingTo fallback: CGFloat) -> CGFloat {
        textView.layoutManager.flatMap { layoutManager -> CGFloat? in
            guard let textContainer = textView.textContainer else {
                return nil
            }
            layoutManager.ensureLayout(for: textContainer)
            return ceil(layoutManager.usedRect(for: textContainer).maxY + textView.textContainerInset.height * 2)
        } ?? fallback
    }

    private func fittingTextWidth(defaultingTo fallback: CGFloat) -> CGFloat {
        textView.layoutManager.flatMap { layoutManager -> CGFloat? in
            guard let textContainer = textView.textContainer else {
                return nil
            }
            layoutManager.ensureLayout(for: textContainer)
            return ceil(layoutManager.usedRect(for: textContainer).maxX + textView.textContainerInset.width * 2)
        } ?? fallback
    }
}
