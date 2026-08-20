import Foundation

extension BlockInputView {
    /// Applies configuration and reloads the editor from its document store.
    public func configure(_ configuration: BlockInputConfiguration) {
        configure(configuration, restoresFocus: true)
    }

    func configure(_ configuration: BlockInputConfiguration, restoresFocus: Bool) {
        let configuredDocumentStore = configuration.documentStore
        let previousDocumentStore = documentStore
        reconcileProvisionalTextReplacementBeforeConfiguration(documentStore: configuredDocumentStore)
        let previousDocument = document
        let wasEditable = isEditable
        let wasDocumentCacheSynchronized = isDocumentCacheSynchronized
        let documentStoreChanged = previousDocumentStore.map { ($0 as AnyObject) !== (configuredDocumentStore as AnyObject) } ?? false
        if documentStoreChanged {
            detachDocumentStoreObservation()
            cancelFileDropTasks()
        }
        documentStore = configuredDocumentStore
        let reusesLargeDocumentCache = previousDocumentStore != nil
            && !documentStoreChanged
            && configuredDocumentStore.loadedBlockCount > largeDocumentCacheMutationLimit
        let configuredDocument = reusesLargeDocumentCache ? previousDocument : configuration.document.detachedStorage()
        let documentChanged = documentStoreChanged || previousDocument != configuredDocument
        document = configuredDocument
        isDocumentCacheSynchronized = reusesLargeDocumentCache ? wasDocumentCacheSynchronized : true
        reconcileProvisionalTextReplacementAfterConfiguration()
        configureStyle(configuration)
        configureEditorSurface(configuration)
        dismissMutationUIIfNeeded(wasEditable: wasEditable)
        configureImageLoading(configuration)
        configureUndoController(
            previousDocumentStore: previousDocumentStore,
            previousDocument: previousDocument,
            documentStoreChanged: documentStoreChanged,
            configuration: configuration,
            configuredDocument: configuredDocument
        )
        configureCommandDispatcher(configuration.commandDispatcher)
        keyboardShortcuts = configuration.keyboardShortcuts
        configureCompletion(configuration)
        if documentChanged {
            dismissCompletionPopup()
            cancelFileDropTasks()
        }
        configureHostCallbacks(configuration)
        if documentStoreChanged || configuration.onDocumentChange == nil {
            cancelPendingDocumentSnapshot()
        }
        updateDropIndicatorColor()
        hideDropIndicator()
        invalidateReadOnlyCursorRects()
        clearStaleFocusState()
        reloadConfiguredDocument(restoresFocus: restoresFocus, reusesMountedItems: previousDocumentStore != nil && !documentChanged)
        attachDocumentStoreObservationIfNeeded()
        invalidatePreferredHeight()
    }

    private func configureHeightSizing(_ sizing: BlockInputEditorHeightSizing?) {
        heightSizing = sizing
        if sizing == nil {
            lastReportedPreferredHeight = nil
            isPreferredHeightCallbackScheduled = false
            invalidateIntrinsicContentSize()
        }
    }

    private func configureEditorSurface(_ configuration: BlockInputConfiguration) {
        allowsBlockReordering = configuration.allowsBlockReordering
        allowsDrops = configuration.allowsDrops
        editorHorizontalInset = configuration.editorHorizontalInset
        editorVerticalInset = configuration.editorVerticalInset
        blockVerticalInsetMultiplier = configuration.blockVerticalInsetMultiplier
        placeholder = configuration.placeholder
        isEditable = configuration.isEditable
        disabledCursor = configuration.disabledCursor
        inlineHintProvider = configuration.inlineHintProvider
        rawSlashCommandChips = configuration.rawSlashCommandChips
        rawFileMentionChips = configuration.rawFileMentionChips
        selectAllBehavior = configuration.selectAllBehavior
        completionReturnBehavior = configuration.completionReturnBehavior
        dropIndicatorColor = configuration.dropIndicatorColor
        imagePresentation = configuration.imagePresentation
        applyEditorSurfaceStyle()
        updateCollectionDraggedTypes()
        configureHeightSizing(configuration.heightSizing)
    }

    /// Brings the collection view in line with the configuration just applied.
    ///
    /// A first configuration has to populate the collection view and a swapped store or a changed
    /// document has to rebuild it; every other call can reuse the rows already mounted. The store
    /// pushes its own changes through `handleDocumentStoreChange`, so nothing depends on this path
    /// to notice them.
    ///
    /// A SwiftUI host rebuilds its `BlockInputConfiguration` on every `body` pass, so most
    /// `updateNSView` calls arrive with an unchanged document. Reloading anyway is worse than
    /// wasted work: `reloadData` hides every mounted cell for reuse, and hiding the cell holding
    /// first responder sends AppKit on a window-wide `nextValidKeyView` search that re-enters
    /// SwiftUI's in-flight graph update through a sibling `NSHostingView`. AttributeGraph reports
    /// that as a dependency cycle, and printing the cycle can hang the main thread for tens of
    /// seconds. Refreshing the mounted items applies the same configuration without recycling one.
    private func reloadConfiguredDocument(restoresFocus: Bool, reusesMountedItems: Bool) {
        if reusesMountedItems, refreshMountedItemsForConfiguration() {
            return
        }
        if restoresFocus {
            reloadDataKeepingFocus()
        } else {
            reloadDataWithoutRestoringFocus()
        }
    }

    /// Reapplies the configuration to the already-mounted items, reporting `false` when the mounted
    /// row count no longer matches the data source and only a reload can reconcile it.
    ///
    /// Every setting a reload would push into a cell — style, insets, editability, chip rendering,
    /// inline hints — reaches it through `configureBlockItem` just the same, at the cost of the
    /// visible rows rather than the whole document. Rows scrolled out of view are configured when
    /// they mount, so they pick the same values up then.
    ///
    /// No focus restore belongs here: `BlockInputBlockItem.configure` reassigns `textView.string`
    /// only when the text differs, so an unchanged document leaves every caret, text selection, and
    /// the window's first responder exactly where the user left them.
    private func refreshMountedItemsForConfiguration() -> Bool {
        // With no rows mounted there is nothing to refresh and nothing a reload would fix either:
        // the data source is queried from scratch on the first layout that mounts a row. Skipping
        // the row-count guard here also keeps the reconfiguration free of document-store reads.
        let mountedItems = collectionView.visibleItems()
        if !mountedItems.isEmpty {
            guard collectionView.numberOfItems(inSection: 0) == blockCount + (showsProgressiveLoadingRow ? 1 : 0) else {
                return false
            }
            for item in mountedItems {
                if let loadingItem = item as? BlockInputLoadingItem {
                    loadingItem.configure(error: progressiveStoreError, surfaceStyle: style.editorSurface)
                    continue
                }
                guard let blockItem = item as? BlockInputBlockItem,
                      let index = collectionView.indexPath(for: item)?.item,
                      let block = block(at: index) else {
                    continue
                }
                configureBlockItem(blockItem, block: block, blockIndex: index)
            }
            collectionView.collectionViewLayout?.invalidateLayout()
        }
        updatePlaceholderVisibility()
        return true
    }

    private func configureCommandDispatcher(_ dispatcher: BlockInputEditorCommandDispatcher?) {
        if commandDispatcher !== dispatcher {
            commandDispatcher?.unbind(from: self)
        }
        commandDispatcher = dispatcher
        dispatcher?.bind(to: self)
    }

    private func configureHostCallbacks(_ configuration: BlockInputConfiguration) {
        onDocumentMutation = configuration.onDocumentMutation
        onDocumentChange = configuration.onDocumentChange
        documentChangeSnapshotDelay = configuration.documentChangeSnapshotDelay
        onSelectionChange = configuration.onSelectionChange
        onFocusChange = configuration.onFocusChange
        onEditorInteractionUIChange = configuration.onEditorInteractionUIChange
        fileDropHandler = configuration.fileDropHandler
        linkURLOpener = configuration.urlOpener
        modalOverlayProvider = configuration.modalOverlayProvider
        refreshMutationModalPresentation()
    }

    func configureUndoController(
        previousDocumentStore: (any BlockInputDocumentStore)?,
        previousDocument: BlockInputDocument,
        documentStoreChanged: Bool,
        configuration: BlockInputConfiguration,
        configuredDocument: BlockInputDocument
    ) {
        if let configuredUndoController = configuration.undoController {
            undoController = configuredUndoController
        } else {
            if let previousDocumentStore,
               documentStoreChanged,
               shouldResetFallbackUndoController(
                   previousDocumentStore: previousDocumentStore,
                   previousDocument: previousDocument,
                   configuration: configuration,
                   configuredDocument: configuredDocument
               ) {
                fallbackUndoController = BlockInputUndoController()
            }
            undoController = fallbackUndoController
        }
    }

    private func configureStyle(_ configuration: BlockInputConfiguration) {
        style = configuration.style
        if style.imageBlock.placeholderAspectRatio == nil {
            style.imageBlock.placeholderAspectRatio = configuration.defaultImagePlaceholderAspectRatio
        }
    }

    private func configureImageLoading(_ configuration: BlockInputConfiguration) {
        imageLoader = configuration.imageLoader
        imageDiskCache = configuration.imageDiskCache
        imageBaseURL = configuration.imageBaseURL
        fileBaseURL = configuration.fileBaseURL
        allowsRemoteImageLoading = configuration.allowsRemoteImageLoading
        maximumImageSourceBytes = configuration.maximumImageSourceBytes
        maximumImagePixelDimension = configuration.maximumImagePixelDimension
        defaultImagePlaceholderAspectRatio = configuration.defaultImagePlaceholderAspectRatio
    }

    func shouldResetFallbackUndoController(
        previousDocumentStore: any BlockInputDocumentStore,
        previousDocument: BlockInputDocument,
        configuration: BlockInputConfiguration,
        configuredDocument: BlockInputDocument
    ) -> Bool {
        if configuration.usesDefaultDocumentStore,
           previousDocumentStore is BlockInputMemoryDocumentStore,
           previousDocument == configuredDocument {
            return false
        }
        return true
    }

    func configureCompletion(_ configuration: BlockInputConfiguration) {
        let previousCompletionProvider = completionProvider
        let previousCompletionPopupPlacement = completionPopupPlacement
        let previousSlashCommandAvailability = slashCommandAvailability
        completionProvider = configuration.completionProvider
        slashCommandAvailability = configuration.slashCommandAvailability
        slashCommandChipClickHandler = configuration.slashCommandChipClickHandler
        completionPopupConfiguration = configuration.completionPopupConfiguration
        if !isEditable ||
            completionProvider == nil ||
            previousCompletionPopupPlacement != completionPopupPlacement ||
            previousSlashCommandAvailability != slashCommandAvailability ||
            !Self.sameCompletionProvider(previousCompletionProvider, completionProvider) {
            dismissCompletionPopup()
        } else {
            refreshCompletionPopupPresentation()
        }
    }

    private static func sameCompletionProvider(
        _ lhs: (any BlockInputCompletionProvider)?,
        _ rhs: (any BlockInputCompletionProvider)?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return (lhs as AnyObject) === (rhs as AnyObject)
        default:
            return false
        }
    }
}

extension BlockInputView {
    func detachDocumentStoreObservation() {
        pendingProgressivePreloadWorkItem?.cancel()
        pendingProgressivePreloadWorkItem = nil
        progressiveLoadTask?.cancel()
        progressiveLoadTask = nil
        documentStoreObservation?.cancel()
        documentStoreObservation = nil
        progressiveStoreError = nil
    }

    func attachDocumentStoreObservationIfNeeded() {
        guard documentStoreObservation == nil,
              let documentStore else {
            return
        }
        let observedStore = documentStore as AnyObject
        documentStoreObservation = documentStore.observeChanges { [weak self, weak observedStore] change in
            guard let self,
                  let observedStore,
                  self.isCurrentDocumentStore(observedStore) else {
                return
            }
            self.handleDocumentStoreChange(change)
        }
    }
}
