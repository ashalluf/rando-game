#!/usr/bin/env bash
# The fast loop: the lawns bookmarks' blocks alone (block_shot.tscn, no far city), a few minutes.
#   GODOT=... tools/lawns_closeup/block.sh <out_dir> [extra env, e.g. LAWNS_CLOSEUP=0 NIGHT=1]
# Shots: 1 the suburb pavement and parkway, 2 front lawns, 3 the city park, 4 the park from 6 m.
set -u
OUT=${1:?out dir}
shift
mkdir -p "$OUT"
cd "$(dirname "$0")/../.."
env "$@" OUT="$OUT/block.png" EYE="-168.3,1.6,52,180,-14" FOV=60 FRAMES=12 GEO=1 \
	SHOTS="-166.5,1.7,70,-62,-16;28,1.7,-330,-135,-12;28,6,-330,-135,-14" LIBGL_ALWAYS_SOFTWARE=1 \
	timeout 1800 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver opengl3 \
	--display-driver x11 --audio-driver Dummy --path . res://tools/glshot/block_shot.tscn \
	--resolution 1280x720 > "$OUT/block.log" 2>&1
grep -E "^(saved|GEO)|SCRIPT ERROR|SHADER ERROR" "$OUT/block.log" | head -20
