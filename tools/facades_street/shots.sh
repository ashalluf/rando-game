#!/bin/bash
# Street-level stills for the facades-street pass (opengl3 under Xvfb, one city load):
#   GODOT=... OUT=/path/name.png SPAWN=x,z SHOTS="x,y,z,yaw,pitch@hour[@fov];..." tools/facades_street/shots.sh
# The first SHOTS entry is the main EYE (saved as OUT); the rest are saved as OUT_1, OUT_2, ...
# Heights are metres above the ground (EYE_AGL=1). FACADES_STREET=0 in the environment is the before.
set -e
cd "$(dirname "$0")/../.."
first="${SHOTS%%;*}"
rest=""
[[ "$SHOTS" == *";"* ]] && rest="${SHOTS#*;}"
eye="${first%%@*}"
hour="$(echo "$first" | cut -d@ -f2)"
EYE="$eye" EYE_AGL=1 SHOTS="$rest" OUT="$OUT" FRAMES="${FRAMES:-40}" SHOT_FRAMES="${SHOT_FRAMES:-24}" \
	xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver opengl3 --display-driver x11 \
	--audio-driver Dummy --path . --script tools/glshot/still_shot.gd --resolution 1280x720 \
	-- --spawn="$SPAWN",0,0 --hour="${hour:-12}" --nohud
