import AppKit

extension BlockInputView {
    func setupCollectionView() {
        wantsLayer = true
        applyEditorSurfaceStyle()

        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        editorVerticalInset = BlockInputConfiguration.defaultEditorVerticalInset

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.blockInputView = self
        collectionView.isSelectable = false
        collectionView.register(
            BlockInputBlockItem.self,
            forItemWithIdentifier: BlockInputBlockItem.reuseIdentifier
        )
        collectionView.register(
            BlockInputLoadingItem.self,
            forItemWithIdentifier: BlockInputLoadingItem.reuseIdentifier
        )
        updateCollectionDraggedTypes()
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        installSelectionExpansionKeyMonitor()

        setupDropIndicator()
        setupScrollView()
        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setupEditorChromeView()
    }

    private func setupDropIndicator() {
        dropIndicatorView.wantsLayer = true
        dropIndicatorView.layer?.cornerRadius = 1
        dropIndicatorView.layer?.zPosition = 10
        updateDropIndicatorColor()
        dropIndicatorView.isHidden = true
        dropIndicatorView.setAccessibilityElement(false)
        collectionView.addSubview(dropIndicatorView, positioned: .above, relativeTo: nil)
        configurePlaceholderLabel()
        collectionView.addSubview(placeholderLabel, positioned: .above, relativeTo: nil)
    }

    private func setupScrollView() {
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.blockInputView = self
        scrollView.documentView = collectionView
        scrollView.onContentBoundsDidChange = { [weak self] in
            self?.handleDocumentScrollContentBoundsChange()
        }
    }

    private func handleDocumentScrollContentBoundsChange() {
        syncCollectionViewDocumentSizeForVisibleBounds()
        scheduleProgressivePreloadCheck()
        dismissCompletionPopup()
    }

    private func setupEditorChromeView() {
        editorChromeView.drawsStroke = false
        editorChromeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(editorChromeView, positioned: .below, relativeTo: scrollView)

        editorChromeStrokeOverlayView.drawsFill = false
        // Preserve the previous stroke density while keeping every edge in one overlay layer.
        editorChromeStrokeOverlayView.strokePassCount = 2
        editorChromeStrokeOverlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(editorChromeStrokeOverlayView, positioned: .above, relativeTo: nil)

        NSLayoutConstraint.activate(chromeConstraints(for: editorChromeView) + chromeConstraints(for: editorChromeStrokeOverlayView))
    }

    func updateCollectionDraggedTypes() {
        if allowsDrops {
            collectionView.registerForDraggedTypes([.blockInputBlockID, .fileURL])
        } else {
            collectionView.unregisterDraggedTypes()
        }
    }

    private func chromeConstraints(for view: NSView) -> [NSLayoutConstraint] {
        [
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
    }
}
