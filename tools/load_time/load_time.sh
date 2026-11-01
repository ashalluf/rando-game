#!/usr/bin/env bash
# Times a launch of the game, stage by stage (LoadClock's "LOADING" lines), and quits once loaded.
#   GODOT=/path/to/godot tools/load_time/load_time.sh desktop   # opengl3 under Xvfb, loading screen
#   GODOT=/path/to/godot tools/load_time/load_time.sh headless  # the dummy renderer, no loading screen
# Extra arguments after the mode go to the game (`-- --spawn=...`). Prints the LOADING lines and the
# peak RSS. Never run two at once (a city is 3-7 GB).
set -euo pipefail
cd "$(dirname "$0")/../.."
MODE="${1:-desktop}"; shift || true
GODOT="${GODOT:-godot}"
LOG="${LOG:-/tmp/load_time_${MODE}.log}"
export LOAD_QUIT=1
# /usr/bin/time where there is one, else tools/peak_rss.py (the cloud box has no `time`).
if [ -x /usr/bin/time ]; then TIMER=(/usr/bin/time -v); else TIMER=(python3 tools/peak_rss.py --); fi
if [ "$MODE" = headless ]; then
	"${TIMER[@]}" "$GODOT" --headless --path . "$@" > "$LOG" 2>&1 || true
else
	"${TIMER[@]}" xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 \
		--resolution 1280x720 "$@" > "$LOG" 2>&1 || true
fi
grep -E "^LOADING|^FIRSTMIN|SCRIPT ERROR|Maximum resident|PEAK RSS" "$LOG" || true
