#!/bin/bash
# The RoadWear stills (opengl3, one load): a downtown avenue, an old midtown street, an industrial
# street, a car park, a pothole close up at noon and in the rain, and 30 m up over midtown.
#   OUT=/tmp/rw.png tools/road_wear/shots.sh            (ROAD_WEAR=0 for the before side)
# Extra env passes through to still_shot.gd. GODOT defaults to `godot`.
set -e
cd "$(dirname "$0")/../.."
OUT=${OUT:-/tmp/road_wear.png}
SHOTS=${SHOTS:-"2239.5,1.6,640,180,-7@13;1786.3,1.6,2100,180,-7@13;2493.6,1.6,2320,180,-7@13;1786.3,30,2090,180,-55@13"}
export OUT SHOTS EYE_AGL=1 SHOT_FRAMES=${SHOT_FRAMES:-30}
xvfb-run -a -s "-screen 0 1280x720x24" ${GODOT:-godot} --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy \
	--path . --script tools/glshot/still_shot.gd --resolution 1280x720 -- --spawn=2239.5,640,180,-7 --hour=13 --nohud --weather=clear "$@"
