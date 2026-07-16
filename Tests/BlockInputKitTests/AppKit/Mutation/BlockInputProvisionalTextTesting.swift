import AppKit
import XCTest
@testable import BlockInputKit

@MainActor
func startedSession(in view: BlockInputView) throws -> BlockInputProvisionalTextSession {
    guard case let .started(session) = view.beginProvisionalTextReplacement() else {
        XCTFail("Expected provisional text replacement to begin")
        throw ProvisionalTextTestError.didNotStart
    }
    return session
}

final class ProvisionalForeignMarkedTextView: NSTextView {
    private(set) var didUnmarkText = false

    override func hasMarkedText() -> Bool {
        true
    }

    override func unmarkText() {
        didUnmarkText = true
    }
}

final class ProvisionalEchoStore: BlockInputDocumentStore, @unchecked Sendable {
    enum EchoMode: Equatable {
        case none
        case synchronous
        case delayed
    }

    var loadedBlockCount: Int { blocks.count }
    private var blocks: [BlockInputBlock]
    private var observers: [@MainActor (BlockInputDocumentStoreChange) -> Void] = []
    private let echoMode: EchoMode
    private let movesReplacedBlockToEnd: Bool

    init(
        blocks: [BlockInputBlock],
        echoMode: EchoMode,
        movesReplacedBlockToEnd: Bool = false
    ) {
        self.blocks = blocks
        self.echoMode = echoMode
        self.movesReplacedBlockToEnd = movesReplacedBlockToEnd
    }

    func block(at index: Int) -> BlockInputBlock? {
        blocks.indices.contains(index) ? blocks[index] : nil
    }

    func block(withID id: BlockInputBlockID) -> BlockInputBlock? {
        blocks.first { $0.id == id }
    }

    func index(of id: BlockInputBlockID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    func observeChanges(
        _ observer: @escaping @MainActor (BlockInputDocumentStoreChange) -> Void
    ) -> BlockInputDocumentStoreObservation {
        observers.append(observer)
        return BlockInputDocumentStoreObservation()
    }

    func replaceDocument(_ document: BlockInputDocument) {
        blocks = document.blocks
        emitConfiguredEcho()
    }

    func replaceBlock(_ block: BlockInputBlock) {
        guard let index = index(of: block.id) else {
            return
        }
        blocks[index] = block
        if movesReplacedBlockToEnd {
            blocks.append(blocks.remove(at: index))
        }
        emitConfiguredEcho()
    }

    func externallyReplace(_ block: BlockInputBlock) {
        guard let index = index(of: block.id) else {
            return
        }
        blocks[index] = block
        emitSynchronously()
    }

    func externallyDelete(_ blockID: BlockInputBlockID) {
        blocks.removeAll { $0.id == blockID }
        emitSynchronously()
    }

    private func emitConfiguredEcho() {
        switch echoMode {
        case .none:
            break
        case .synchronous:
            emitSynchronously()
        case .delayed:
            Task { @MainActor [weak self] in
                self?.emitOnMainActor()
            }
        }
    }

    private func emitSynchronously() {
        MainActor.assumeIsolated {
            emitOnMainActor()
        }
    }

    @MainActor
    private func emitOnMainActor() {
        observers.forEach { $0(.replacedDocument) }
    }
}

private enum ProvisionalTextTestError: Error {
    case didNotStart
}
