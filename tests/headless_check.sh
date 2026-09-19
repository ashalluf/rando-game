#!/usr/bin/env bash
# Headless project check: import, then run the smoke test.
# Usage: GODOT=/path/to/godot tests/headless_check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
echo "== Godot version"; "$GODOT" --headless --version
echo "== Import"; "$GODOT" --headless --path . --import
echo "== Smoke test"; "$GODOT" --headless --path . -s res://tests/smoke_test.gd
