#!/usr/bin/env bash
# gate.sh <worktree> <tag> [SHARDS=3]: the headless check in a worktree, logs and peak RSS in $LOG_DIR.
# The lead's batch gate. Usage: SHARDS=3 tools/fleet/lead/gate.sh /home/user/rando-b4 b10
# (SHARDS=1 is the plain run CI does, ~20 min; SHARDS=3 ~10 min). Never run two at once, never
# edit res://scripts in any worktree while one runs (user://load_cache is shared by project name).
W=${1:?worktree}; TAG=${2:?tag}; LOG_DIR=${LOG_DIR:-/tmp/fleet_gate}; mkdir -p "$LOG_DIR/${TAG}_shards"
GODOT=${GODOT:-/home/user/godot/Godot_v4.7.2-stable_linux.x86_64}
cd "$W" || exit 1
( peak=0; while sleep 2; do r=0; for p in $(pgrep -f Godot_v4.7.2-stable_linux.x86_64); do [ "$(readlink /proc/$p/cwd 2>/dev/null)" = "$W" ] || continue; v=$(awk '/VmRSS/{print $2}' /proc/$p/status 2>/dev/null); r=$((r + ${v:-0})); done; [ "$r" -gt "$peak" ] && peak=$r && echo "$peak" > "$LOG_DIR/peak_rss_${TAG}_kb"; done ) &
MON=$!
SHARDS=${SHARDS:-3} SMOKE_LOG_DIR="$LOG_DIR/${TAG}_shards" GODOT=$GODOT tests/headless_check.sh > "$LOG_DIR/gate_${TAG}.log" 2>&1
echo "EXIT $?" >> "$LOG_DIR/gate_${TAG}.log"
kill $MON
grep -h "^FAIL" "$LOG_DIR/gate_${TAG}.log" "$LOG_DIR/${TAG}_shards"/*.log 2>/dev/null | sort -u
tail -3 "$LOG_DIR/gate_${TAG}.log"
