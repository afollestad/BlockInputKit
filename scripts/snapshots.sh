#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/snapshots.sh <verify|record> [test_identifier ...]

Defaults to the representative AppKit snapshot suites when no identifiers are provided.

Examples:
  ./scripts/snapshots.sh verify
  ./scripts/snapshots.sh record
  ./scripts/snapshots.sh verify BlockInputKitTests/BlockInputViewSnapshotTests
  ./scripts/snapshots.sh record BlockInputKitTests/BlockInputViewSnapshotTests
EOF
}

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 1
fi

mode=$1
shift

case "$mode" in
  verify|record)
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

if [ "$#" -eq 0 ]; then
  set -- \
    "BlockInputKitTests/BlockInputViewSnapshotTests" \
    "BlockInputKitTests/BlockInputInlineImageSnapshotTests" \
    "BlockInputKitTests/BlockInputViewReadOnlySnapshotTests"
fi

tmp_args=$(mktemp)
trap 'rm -f "$tmp_args"' EXIT

swift_filters=()
for test_name in "$@"; do
  printf '%s\0' "-only-testing:$test_name" >> "$tmp_args"
  swift_filters+=("${test_name//\//.}")
done
swift_filter=$(
  IFS='|'
  echo "${swift_filters[*]}"
)

run_tests() {
  if command -v xcsift >/dev/null 2>&1; then
    (
      set +e
      xargs -0 xcodebuild \
        -scheme BlockInputKit-Package \
        -destination 'platform=macOS' \
        -derivedDataPath .build/xcode \
        test < "$tmp_args" 2>&1 | xcsift -f toon -w
      statuses=("${PIPESTATUS[@]}")

      status=0
      for pipeline_status in "${statuses[@]}"; do
        if [ "$pipeline_status" -ne 0 ]; then
          status=$pipeline_status
        fi
      done
      exit "$status"
    )
  else
    xargs -0 xcodebuild \
      -scheme BlockInputKit-Package \
      -destination 'platform=macOS' \
      -derivedDataPath .build/xcode \
      test < "$tmp_args"
  fi
}

record_tests() {
  env SNAPSHOT_TESTING_RECORD=all swift test --filter "$swift_filter"
}

if [ "$mode" = "verify" ]; then
  run_tests
  echo "Snapshot verification passed."
  exit 0
fi

# Point-Free SnapshotTesting exits non-zero after recording new references.
# Verify immediately afterward so the script only succeeds when baselines are usable.
set +e
record_tests
record_status=$?
set -e

if [ "$record_status" -ne 0 ]; then
  echo "Snapshot record command exited $record_status; verifying recorded references..."
fi

run_tests
echo "Snapshots recorded and verified."
