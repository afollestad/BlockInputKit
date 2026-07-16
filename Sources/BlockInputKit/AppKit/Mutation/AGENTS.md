## Store Sync

- Keep document-store synchronization granular when a single block replacement, insertion, deletion, or move accurately describes the mutation; fall back to full document replacement for multi-step structural edits.
- Keep large-document structural undo/redo on granular store operations when the undo payload describes a single block replacement, insertion, deletion, or move.
- Publish large-document edit notifications through `onDocumentMutation` for hot paths; keep full `onDocumentChange` snapshots deferred/coalesced so Return, Delete, Undo, and Redo do not materialize full snapshots synchronously.
- For progressive stores, full snapshot callbacks should use `completeDocumentSnapshot(limit:)` without forcing editor row population; hot edit paths should stay on loaded-block reads and granular mutations.
- Do not replace an incomplete progressive store with a loaded-prefix document; use granular mutations or wait until the store is complete.

## Editing Operations

- Keep host-driven provisional text cumulative from its original range, store-first validated, and on the existing granular replacement path. Interim updates must not add undo history; commit adds one text edit, while cancel restores the exact original selection without undo.
- Let an issued provisional-text token continue through a same-store read-only reconfiguration, but invalidate it on unexpected target-block changes, store replacement, or editor detach.

- Keep large-document same-row replacements, such as empty quote to paragraph, on mounted item reconfiguration instead of `reloadItems`; benchmark this with `--benchmark-100k-mutations`.
- Keep multiline quote/code exits on granular replacement-plus-insertion operations; pressing Return on an empty inline line should not fall back to full document structural edits.
- For non-large replacement-plus-insertion edits, do not mix `reloadItems` and `insertItems` after the document count has changed; reload the visible layout coherently to avoid overlapping rows.
- When remapping mounted collection items after large-document insert/delete, resize each item for its new block before manually reflowing visible rows; otherwise mixed paragraph/heading runs can show uneven spacing or clipped text.
- Keep front-of-paragraph Backspace/Delete merges granular: replace the previous block and delete the current block.
- When indenting ordered-list blocks, normalize only the affected list run and publish replacement mutations for every block whose visible marker changes.
- For marker-adjusting document stores, publish numbered-list marker transactions instead of marker-only block replacements on hot large-document paths.
- Keep table row, column, cell, and table-delete mutations on granular store sync and structural undo where a single block replacement, insertion, or deletion describes the edit.
- Table-cell formatting and links should share normal inline mutation logic through source-range adapters; never apply formatting to table delimiters, separator rows, pipes, padding, or ranges crossing cells.
- Table-cell hot edits should use `.replaceBlock` and must not read complete snapshots for store-backed documents.
- Host-driven local file pickers should call `BlockInputView.insertLocalFileURLs(...)` so picker insertion stays aligned with file-drop behavior and `BlockInputConfiguration.imagePresentation`.

## Shortcuts

- Keep host `keyboardShortcuts` after modal/completion/IME priority but before editor defaults; route Return, selector,
  key-equivalent, table-cell, image-caret, and block-selection paths through one dispatch layer.
- Keep clipboard shortcuts intentionally asymmetric: Cmd+C may use a direct key-equivalent path for editor/block selections, but paste should stay on AppKit `NSText`/responder actions to preserve native insertion semantics.
- Preserve Cmd+Up/Cmd+Down as document-boundary caret movement; they must not extend block selection.
- Keep final-cell table Tab routed through the structural `Insert Row` mutation path; hover plus controls stay on the append-row path.
- Keep text-formatting shortcuts editor-owned source mutations; consume Cmd+B/I/U and Cmd+Shift+X so AppKit rich-text toggles cannot affect editor state.
