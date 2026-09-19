#!/usr/bin/env bash
# Headless project check: import, then run the smoke test.
# Usage: GODOT=/path/to/godot tests/headless_check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
echo "== Godot version"; "$GODOT" --headless --version
echo "== Import"; "$GODOT" --headless --path . --import
echo "== Smoke test"
LOG="$(mktemp)"
set +e
"$GODOT" --headless --path . -s res://tests/smoke_test.gd 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e
if grep -qE "SCRIPT ERROR|Failed to load script|Parse Error" "$LOG"; then
  echo "== Script errors found in the smoke test output"
  STATUS=1
fi
rm -f "$LOG"
exit $STATUS
