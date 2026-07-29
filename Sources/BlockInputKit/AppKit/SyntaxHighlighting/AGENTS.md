## Syntax Highlighting

- Keep the lite highlighter dependency-free and regex-based; do not add external parser or highlighter packages here.
- Keep inline Markdown parsing dependency-free, row-local, and based on UTF-16 `NSRange` values so AppKit formatting, typing attributes, and tests share one scanner.
- Keep highlighting bounded for large visible documents; avoid document-wide work from row height measurement paths.
- Preserve original language hints for Markdown export and clipboard behavior; normalize aliases only for highlighter lookup.
- Keep parsing helpers shared and side-effect free so AppKit rendering, Return shortcuts, and Markdown paths can use the same rules.
- **Keep `.inlineImage` emission deterministic from text alone.** Only remote (`http`/`https`) sources emit `.inlineImage`; file and relative destinations keep their chip/link/plain-text behavior. Navigation, deletion, hit testing, and attribute application all re-parse independently, so which characters are hidden must never depend on load state — load state may only change sizes. Table-cell parse calls pass `inlineImages: false` and must keep doing so until cells render images.
