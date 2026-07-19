## Block Item Reuse

- Preserve collection-view reuse assumptions: every item configuration must fully reset text, chrome, selection, drag handles, horizontal-rule state, and callbacks that can survive reuse.
- Reset frontmatter divider visibility and validation warning text attributes during reuse; stale frontmatter chrome must not leak into raw Markdown or paragraph rows.
- Suppress item delegate callbacks during programmatic block-item configuration; visible-row reuse in large documents must not report caret movement or force store index rebuilds.

## Chrome And Metrics

- Keep list marker rendering in `BlockInputMarkerView`; it custom-draws per-line markers so mixed-indent list items do not share one text-field alignment edge.
- Keep code-block background and whole-block selection widths aligned; code surfaces hug content with the AppKit code-surface minimum instead of filling the full row.
- Keep item height measurement cached or otherwise bounded to visible/layout-requested rows.
- Keep bare slash-command hint separation matched to one normally rendered ASCII space: following document whitespace must not gain extra kern, while bare hints prepend that literal character without moving the caret or mutating the document. File chips retain adjacent-whitespace spacing.
- Keep offscreen height measurement in parity with mounted inline-chip fonts and spacing, including raw slash-command availability and document-start rules, so near-boundary wrapping cannot clip a row.
- When shared row chrome metrics, default insets, or marker alignment change, record and verify the AppKit snapshot suite.
- Keep table rendered and offscreen measurement in parity: column widths, row heights, padding, borders, header styling, alignments, wrapping, and horizontal scroller reserve must match.
- Reset table cells, delegates, hover append controls, row-selection chrome, focus state, tracking areas, and horizontal scroll state during item reuse.
- Keep table hover controls, row-selection chrome, link hit testing, and caret/selection anchors aligned to the horizontally scrolled table document and clipped to the visible viewport.
