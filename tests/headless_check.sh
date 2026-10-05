#!/usr/bin/env bash
# Headless project check: import, then run the smoke test.
# Usage: GODOT=/path/to/godot tests/headless_check.sh
#   SHARDS=n   split the smoke test into n processes run side by side (each loads its own city,
#              about 3 GB each; tests/smoke_test.gd deals the parts). 3 on a 4-core, 15 GB box.
#              The pass / fail lines of the shards together are the plain run's.
#   SMOKE_LOG_DIR=dir  keep each shard's full log there (default: a temporary directory).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SHARDS="${SHARDS:-1}"
# Engine-level errors count too. They are printed as plain "ERROR:" rather than "SCRIPT ERROR:",
# so they slipped through this gate for a long time: a passing run was quietly logging 253
# is_inside_tree errors from the traffic spawner and 57 missing-UV errors from the beach. Only
# the specific ones we have diagnosed are listed, so this stays a tripwire rather than noise.
ERRORS='SCRIPT ERROR|SHADER ERROR|Shader compilation failed|Failed to load script|Parse Error|is_finite|must be normalized|UVs are required|is_inside_tree\(\)" is true'
echo "== Godot version"; "$GODOT" --headless --version
echo "== Import"; "$GODOT" --headless --path . --import
if [ "$SHARDS" -le 1 ]; then
  echo "== Smoke test"
  LOG="$(mktemp)"
  set +e
  timeout 900 "$GODOT" --headless --path . res://tests/smoke_test.tscn 2>&1 | tee "$LOG"
  STATUS=${PIPESTATUS[0]}
  set -e
  if [ "$STATUS" = "124" ]; then
    echo "== Smoke test timed out"
  fi
  if grep -qE "$ERRORS" "$LOG"; then
    echo "== Script errors found in the smoke test output"
    STATUS=1
  fi
  rm -f "$LOG"
  exit $STATUS
fi

echo "== Smoke test in $SHARDS shards"
DIR="${SMOKE_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$DIR"
START=$(date +%s)
PIDS=()
for ((i = 0; i < SHARDS; i++)); do
  SMOKE_SHARD="$i/$SHARDS" timeout 900 "$GODOT" --headless --path . res://tests/smoke_test.tscn > "$DIR/shard_$i.log" 2>&1 &
  PIDS+=($!)
done
STATUS=0
TOTAL=0
for ((i = 0; i < SHARDS; i++)); do
  set +e
  wait "${PIDS[$i]}"
  CODE=$?
  set -e
  LOG="$DIR/shard_$i.log"
  CHECKS=$(grep -cE "^(PASS|FAIL) " "$LOG" || true)
  TOTAL=$((TOTAL + CHECKS))
  echo "== Shard $i/$SHARDS: exit $CODE, $CHECKS checks, $(grep -m1 "^SMOKE PARTS" "$LOG" || echo "no parts line")"
  grep -E "^FAIL |^SMOKE TEST|^SMOKE TIME|SMOKE TEST TIMED OUT" "$LOG" || true
  [ "$CODE" = "124" ] && echo "== Shard $i timed out"
  if grep -qE "$ERRORS" "$LOG"; then
    echo "== Script errors found in shard $i:"
    grep -E "$ERRORS" "$LOG" | head -20
    CODE=1
  fi
  if [ "$CODE" != "0" ]; then STATUS=1; fi
done
echo "== $TOTAL checks in $SHARDS shards, $(( $(date +%s) - START )) s; logs in $DIR"
if [ "$STATUS" = "0" ]; then
  echo "SMOKE TEST PASSED ($TOTAL checks, $SHARDS shards)"
else
  echo "SMOKE TEST FAILED (see the FAIL lines above)"
fi
exit $STATUS
