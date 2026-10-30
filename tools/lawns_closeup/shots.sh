#!/usr/bin/env bash
# The lawns-closeup bookmarks from ONE city load (opengl3 under Xvfb, ~10 min):
#   GODOT=... tools/lawns_closeup/shots.sh <out_dir> [extra env, e.g. LAWNS_CLOSEUP=0]
# Shots: 1 suburb pavement / parkway (noon), 2 front lawns (noon), 3 city park (noon),
# 4 campus quad (noon), 5 a long park lawn from 6 m (the blade-to-lawn hand-over), 6 front lawns
# at golden hour, 7 at night, 8 the park in the morning (sprinklers). Heights above the ground.
set -u
OUT=${1:?out dir}
shift
mkdir -p "$OUT"
cd "$(dirname "$0")/../.."
S1="-168.3,1.6,52,180,-14@12"
S2="-166.5,1.7,70,-62,-16@12"
S3="28,1.7,-330,-135,-12@12"
S4="-622,1.7,-560,-150,-12@12"
S5="-449,6.0,1230,180,-10@12"
S6="-166.5,1.7,70,-62,-16@18.4"
S7="-166.5,1.7,70,-62,-16@21.5"
S8="28,1.7,-330,-135,-12@7.2"
env "$@" OUT="$OUT/lawn.png" EYE="${S1%@*}" EYE_AGL=1 FRAMES=40 SHOT_FRAMES=30 \
	SHOTS="$S1;$S2;$S3;$S4;$S5;$S6;$S7;$S8" LIBGL_ALWAYS_SOFTWARE=1 \
	timeout 2400 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver opengl3 \
	--display-driver x11 --audio-driver Dummy --path . --script tools/glshot/still_shot.gd \
	--resolution 1280x720 -- --spawn=-168,52,180,-14 --hour=12 --weather=clear --nohud --quality=0 \
	> "$OUT/shots.log" 2>&1
grep -E "^(saved|GEO)" "$OUT/shots.log"
