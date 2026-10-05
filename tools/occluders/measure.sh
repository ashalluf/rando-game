#!/usr/bin/env bash
# Frame cost and stills at the occluder bookmarks, from ONE load of the city (still_shot.gd SHOTS=,
# opengl3 under Xvfb, DIFF=1 so frames compare pixel for pixel). Every shot's held frame is counted
# and saved three ways (OCC_AB=1):
#   <shot>.png          occlusion culling with the extra occluders (Occluders, MountainOccluder)
#   <shot>_noextra.png  the extra occluders hidden: the building occluders alone (the before)
#   <shot>_nocull.png   no occlusion culling at all
# Then the pixel diffs: shot against nocull must be identical (anything missing was culled in
# plain sight), and noextra against nocull is the old occluders' own record.
#
#   GODOT=/path/to/godot tools/occluders/measure.sh <out_dir>
#
# Separate loads would not do: chunks build within a time budget a frame, so two runs never
# stream the same chunks by the same frame.
set -u
OUT=${1:?usage: measure.sh <out_dir>}
GODOT=${GODOT:?set GODOT}
cd "$(dirname "$0")/../.."
mkdir -p "$OUT"
# x,y,z,yaw,pitch@hour[@fov]: 0 the basin at street level looking north at the front range; 1 the
# hills bookmark's view from the air; 2 the front range looking north over the valley at the back
# range; 3 the valley looking south at the front range; 4 under the 110 on 5th St; 5 on the 110's
# deck; 6 down in the river; 7 a suburban street by a sound wall; 8 downtown at noon.
# Heights are above the ground there (EYE_AGL=1); the river's is down in the channel, under the
# land level the plan gives.
SHOTS_DEFAULT="300,2,600,0,6@13;300,260,-650,0,-6@15;420,2,-1500,0,-2@15;300,2,-2900,180,-2@15;2045,1.7,2,60,10@13;1989,12.0,160,-6,-3@13;4584.8,-5.4,1191.5,-177,2@13;-527.9,1.7,183.5,-90,0@13;2359.4,2,880,0,12@12"
SHOTS=${SHOTS:-$SHOTS_DEFAULT}
first=${SHOTS%%;*}
rest=${SHOTS#*;}
cam=${first%%@*}
start=$(date +%s)
env OUT="$OUT/shot.png" FRAMES=${FRAMES:-40} SHOT_FRAMES=${SHOT_FRAMES:-24} DIFF=1 OCC_AB=1 EYE_AGL=1 EYE="$cam" SHOTS="$rest" \
	LIBGL_ALWAYS_SOFTWARE=1 timeout 7200 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" \
	--rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
	--script tools/glshot/still_shot.gd --resolution 960x540 \
	-- --spawn=300,600,0,6 --hour=13 --weather=clear --nohud --quality=0 > "$OUT/shot.log" 2>&1
echo "load + shots: $(( $(date +%s) - start )) s"
grep -E "^GEO" "$OUT/shot.log"
for f in "$OUT"/shot.png "$OUT"/shot_[0-9].png; do
	[ -f "$f" ] || continue
	b=${f%.png}
	echo "$(basename "$b"): with vs no culling: $(python3 tools/glshot/img_diff.py "$f" "${b}_nocull.png" "${b}_heat.png")"
	echo "$(basename "$b"): before vs no culling: $(python3 tools/glshot/img_diff.py "${b}_noextra.png" "${b}_nocull.png")"
done
