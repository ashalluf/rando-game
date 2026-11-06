#!/bin/bash
# The night street review's bookmarks (docs/HANDOFF.md "The night street at eye level"):
# Broadway, a midtown boulevard (Wilshire), a suburban street and the beach town, at 21:00 and
# 00:30, clear then rain, sixteen stills from ONE city load on opengl3 (the Compatibility renderer).
#   GODOT=... tools/night_street/shoot.sh <outdir> [extra env assignments...]
# Writes <outdir>/n.png and n_1..15.png; tools/night_street/measure.py <outdir> prints the numbers.
set -e
out=${1:?outdir}; shift || true
mkdir -p "$out"
BW="2984,1.7,170,180,4"
WIL="715,1.7,312,-147,10"
SUB="1801.8,1.7,4135.2,-90,3"
BEACH="-705.2,1.7,597.9,-90,3"
S=""
for w in clear rain; do
	for h in 21.0 0.5; do
		for e in "$BW" "$WIL" "$SUB" "$BEACH"; do
			S="$S;$e@$h@55@$w"
		done
	done
done
S=${S#;}
first=${S%%;*}; rest=${S#*;}
env "$@" OUT="$out/n.png" EYE="${first%%@*}" EYE_AGL=1 SHOTS="$rest" SHOT_FRAMES=${SHOT_FRAMES:-16} \
	FRAMES=${FRAMES:-30} FOV=55 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" \
	--rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
	--script tools/glshot/still_shot.gd --resolution 1280x720 \
	-- --spawn=2984,170,180,4 --hour=21.0 --weather=clear --nohud --quality=0
