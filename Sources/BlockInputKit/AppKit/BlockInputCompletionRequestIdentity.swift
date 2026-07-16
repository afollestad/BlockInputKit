import Foundation

struct BlockInputCompletionRequestIdentity: Equatable, Sendable {
    let sessionID: UUID
    let blockID: BlockInputBlockID
    let token: BlockInputCompletionToken
    let sourceText: String
    let sourceKind: BlockInputBlockKind
}

extension BlockInputCompletionSession {
    var requestIdentity: BlockInputCompletionRequestIdentity {
        BlockInputCompletionRequestIdentity(
            sessionID: id,
            blockID: blockID,
            token: token,
            sourceText: sourceText,
            sourceKind: sourceKind
        )
    }
}
