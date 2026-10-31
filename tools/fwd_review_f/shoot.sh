#!/bin/bash
# Forward+ review f: one small scene on lavapipe (Forward+) and on opengl3, the same EYEs.
#   GODOT=... tools/fwd_review_f/shoot.sh <outdir> <eye> "<more eyes;...>" [env assignments...]
# EYE fields: x,y,z,yaw,pitch[,hour[,weather]] (fwd_block_shot.gd). DRIVERS="vulkan opengl3".
# Writes <outdir>/<driver>.png, <driver>_1.png ... and <driver>.log.
set -u
out=${1:?outdir}; eye=${2:?eye}; rest=${3:-}; shift 3 || shift $#
mkdir -p "$out"
cd "$(dirname "$0")/../.."
for drv in ${DRIVERS:-vulkan opengl3}; do
	env "$@" OUT="$out/$drv.png" EYE="$eye" SHOTS="$rest" BLOCKS=${BLOCKS:-home} FREE_PREV=${FREE_PREV:-0} \
		EXTRA=${EXTRA-"0,1;1,0"} FRAMES=${FRAMES:-14} FOV=${FOV:-60} \
		VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json LIBGL_ALWAYS_SOFTWARE=1 \
		timeout ${TIMEOUT:-2400} xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver $drv \
		--display-driver x11 --audio-driver Dummy --path . res://tools/glshot/fwd_block_shot.tscn \
		--resolution 960x540 -- --hour=${HOUR:-12} --weather=${WEATHER:-clear} > "$out/$drv.log" 2>&1
	grep -E "^saved|SCRIPT ERROR|SHADER ERROR" "$out/$drv.log" | head -20
done
