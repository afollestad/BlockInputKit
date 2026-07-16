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
        if documentStoreChanged || previousDocument != configuredDocument {
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
        reloadConfiguredDocument(restoresFocus: restoresFocus)
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
        selectAllBehavior = configuration.selectAllBehavior
        completionReturnBehavior = configuration.completionReturnBehavior
        dropIndicatorColor = configuration.dropIndicatorColor
        imagePresentation = configuration.imagePresentation
        applyEditorSurfaceStyle()
        updateCollectionDraggedTypes()
        configureHeightSizing(configuration.heightSizing)
    }

    private func reloadConfiguredDocument(restoresFocus: Bool) {
        if restoresFocus {
            reloadDataKeepingFocus()
        } else {
            reloadDataWithoutRestoringFocus()
        }
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
