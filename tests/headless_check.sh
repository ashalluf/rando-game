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
timeout 600 "$GODOT" --headless --path . res://tests/smoke_test.tscn 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e
if [ "$STATUS" = "124" ]; then
  echo "== Smoke test timed out"
fi
# Engine-level errors count too. They are printed as plain "ERROR:" rather than "SCRIPT ERROR:",
# so they slipped through this gate for a long time: a passing run was quietly logging 253
# is_inside_tree errors from the traffic spawner and 57 missing-UV errors from the beach. Only
# the specific ones we have diagnosed are listed, so this stays a tripwire rather than noise.
if grep -qE "SCRIPT ERROR|SHADER ERROR|Shader compilation failed|Failed to load script|Parse Error|is_finite|must be normalized|UVs are required|is_inside_tree\(\)\" is true" "$LOG"; then
  echo "== Script errors found in the smoke test output"
  STATUS=1
fi
rm -f "$LOG"
exit $STATUS
