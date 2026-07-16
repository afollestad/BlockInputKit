## Mutation Tests

- For document-store behavior, assert the granular store operation used by the editor, not only the final document snapshot.
- Cover provisional-text cursor/selection replacement, exact cancellation, single-step undo, same-store read-only continuation, self-authored store echoes, and external target invalidation with mounted views.
- Cover Return, Delete, Merge, Indent, Undo, typing shortcut, file insertion, and markdown insertion paths through AppKit command or mounted-view tests when responder behavior matters.
- Keep coverage for large-document mutation paths that should publish `onDocumentMutation` without synchronously reading full document snapshots.
