#!/usr/bin/env bash
# Runs a headless Godot command, samples its RSS twice a second, kills it past LIMIT_MB (11000)
# so the box survives, and prints the peak. Usage: tools/memory_probe/run_probe.sh <godot args...>
# Env: GODOT (godot), LIMIT_MB.
GODOT="${GODOT:-godot}"
LIMIT_MB="${LIMIT_MB:-11000}"
"$GODOT" "$@" &
PID=$!
PEAK=0
while kill -0 $PID 2>/dev/null; do
	RSS=$(awk '/VmRSS/{print int($2/1024)}' /proc/$PID/status 2>/dev/null)
	RSS=${RSS:-0}
	[ "$RSS" -gt "$PEAK" ] && PEAK=$RSS
	if [ "$RSS" -gt "$LIMIT_MB" ]; then
		echo "RUN_PROBE: RSS ${RSS} MB over ${LIMIT_MB} MB, killing"
		kill -9 $PID
	fi
	sleep 0.5
done
wait $PID
STATUS=$?
echo "RUN_PROBE: peak RSS ${PEAK} MB, exit ${STATUS}"
exit $STATUS
