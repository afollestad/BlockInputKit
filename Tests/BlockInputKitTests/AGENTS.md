## Test Organization

- Mirror source areas at the folder level when adding test files: `Core`, `AppKit`, `Markdown`, `Completion`, `Undo`, `SwiftUI`, and `Support`.
- Within `AppKit`, use the nearest topical folder for block item, mutation, performance, reordering, selection, and snapshot coverage.
- Put shared test helpers beside the tests that use them most; promote them only when multiple folders need the same helper.
- For keyboard behavior, cover the document model and the AppKit delegate or mounted-view path when both can diverge.
- For document-store behavior, assert the granular store operation used by the editor, not only the final document snapshot.
- For AppKit snapshot tests, keep light/dark and sizing matrices compact and deterministic; add baselines only for representative UI states.

## Determinism

- Await work the editor deferred to the next main-loop turn with `waitForNextMainLoopTurn()`, never a fixed `RunLoop.run(until:)` deadline. The deadline can expire before a loaded machine services the queue, which passes locally and fails in CI. It only covers one main-queue hop, and it settles the queue rather than AppKit's update cycle, so a chained effect, a delayed one, or state computed in `viewDidLayout` — selection chrome frames, segment rects — needs its own signal.
