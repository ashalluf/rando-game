#!/bin/bash
# The night street bookmarks on Forward+ (lavapipe), the FULL blocks round each place only
# (fwd_block_shot.tscn BLOCKS=home + the block across the street; no far city, no traffic):
#   GODOT=... tools/night_street/shoot_fwd.sh <outdir> [extra env assignments...]
# Place by place: Broadway, Wilshire, suburb, beach; each 21:00 clear, 00:30 clear, 21:00 rain,
# 00:30 rain -> <outdir>/f.png, f_1..15.png. Needs lavapipe (lvp_icd.json).
set -e
out=${1:?outdir}; shift || true
mkdir -p "$out"
S=""
# PLACES picks some (default all four: bw wil sub beach). Downtown's blocks run lavapipe out of
# memory on a 15 GB box even alone (13.6 GB); the suburb and the beach town fit.
declare -A EYES=([bw]="2984,1.7,170,180,4" [wil]="715,1.7,312,-147,10" [sub]="1801.8,1.7,4135.2,-90,3" [beach]="-705.2,1.7,597.9,-90,3")
for pl in ${PLACES:-bw wil sub beach}; do
	e=${EYES[$pl]}
	for w in clear rain; do
		for h in 21.0 0.5; do
			S="$S;$e,$h,$w"
		done
	done
done
S=${S#;}
first=${S%%;*}; rest=${S#*;}
env "$@" OUT="$out/f.png" EYE="$first" SHOTS="$rest" BLOCKS=home FREE_PREV=1 EXTRA=${EXTRA-"0,1;1,0"} \
	FRAMES=${FRAMES:-12} FOV=55 VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
	xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver ${DRIVER:-vulkan} --display-driver x11 \
	--audio-driver Dummy --path . res://tools/glshot/fwd_block_shot.tscn --resolution 960x540 \
	-- --hour=21 --weather=clear
