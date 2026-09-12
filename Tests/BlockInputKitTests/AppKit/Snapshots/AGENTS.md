## AppKit Snapshot Tests

- Keep snapshot matrices minimal: prefer representative documents over one fixture per block kind.
- Make fixtures deterministic by pinning view size, appearance, accent color, and visible document content.
- Use `appKitSnapshotImage()` for AppKit image snapshot assertions so local Retina baselines and headless CI rendering stay comparable.
- Verify all suites with the headless renderer using `TEST_RUNNER_BLOCKINPUTKIT_FORCE_FIXED_SCALE_SNAPSHOTS=true ./scripts/test.sh`; Xcode strips `TEST_RUNNER_` when forwarding the variable into test processes.
- Record new baselines intentionally with `./scripts/snapshots.sh record`; run it without filters after broad editor chrome or default inset changes so every snapshot baseline is refreshed, then verify with `./scripts/snapshots.sh verify`.
- Keep snapshot helpers local to this folder unless non-snapshot AppKit tests need them.
