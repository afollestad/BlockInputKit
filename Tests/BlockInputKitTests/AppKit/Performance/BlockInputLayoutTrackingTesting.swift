import AppKit

/// Records which invalidation shapes a collection-view layout received so hot-path
/// tests can assert that bounded edits avoid full or delegate-metrics invalidation.
final class TrackingCollectionViewFlowLayout: NSCollectionViewFlowLayout {
    private(set) var invalidatedItemIndexPaths: [IndexPath] = []
    private(set) var didInvalidateEverything = false
    private(set) var didInvalidateDelegateMetrics = false

    func reset() {
        invalidatedItemIndexPaths = []
        didInvalidateEverything = false
        didInvalidateDelegateMetrics = false
    }

    override func invalidateLayout() {
        didInvalidateEverything = true
        super.invalidateLayout()
    }

    override func invalidateLayout(with context: NSCollectionViewLayoutInvalidationContext) {
        invalidatedItemIndexPaths.append(contentsOf: context.invalidatedItemIndexPaths ?? [])
        didInvalidateDelegateMetrics =
            didInvalidateDelegateMetrics
            || (context as? NSCollectionViewFlowLayoutInvalidationContext)?.invalidateFlowLayoutDelegateMetrics == true
        super.invalidateLayout(with: context)
    }
}
