#!/usr/bin/env bash
# Runs the first-use probe under lavapipe (Forward+ on the CPU). Env passes through
# (WARM, EVENTS, FRAMES, LANDMARKS). The on-disk shader and pipeline caches are emptied first
# (a first launch) unless KEEP_CACHE=1. Usage: tools/shader_warm/run_probe.sh [WxH]
set -eu
GODOT=${GODOT:-$(command -v godot || echo /home/user/Godot_v4.7.2-stable_linux.x86_64)}
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if [ "${KEEP_CACHE:-0}" != "1" ]; then
	rm -rf "$HOME/.local/share/godot/app_userdata/Rando Game/shader_cache" \
		"$HOME/.local/share/godot/app_userdata/Rando Game/vulkan"
fi
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver vulkan --display-driver x11 \
	--audio-driver Dummy --path "$REPO" res://tools/shader_warm/first_use_probe.tscn --resolution "${1:-480x270}"
