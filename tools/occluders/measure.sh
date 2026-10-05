#!/usr/bin/env bash
# Frame cost and stills at the occluder bookmarks, three ways from the same cameras:
#   on   - occlusion culling with the extra occluders (Occluders, MountainOccluder)
#   off  - OCCLUDERS=0: occlusion culling with the building occluders only (the before)
#   none - OCCLUSION=0: no occlusion culling at all (to diff: anything in "on" missing from "none"
#          was culled in plain sight)
#
#   GODOT=/path/to/godot tools/occluders/measure.sh <out_dir> [on|off|none ...]
#
# Each mode is one load of the city (still_shot.gd SHOTS=), opengl3 under Xvfb, DIFF=1 so the
# frames compare pixel for pixel (tools/glshot/img_diff.py). The GEO / GEO_n lines in
# <out_dir>/<mode>.log are each shot's triangles, draw calls and objects.
set -u
OUT=${1:?usage: measure.sh <out_dir> [modes]}
shift
GODOT=${GODOT:?set GODOT}
modes=("$@")
[ ${#modes[@]} -eq 0 ] && modes=(on off none)
cd "$(dirname "$0")/../.."
mkdir -p "$OUT"
# x,y,z,yaw,pitch@hour[@fov]: 0 the basin at street level looking north at the front range; 1 the
# hills bookmark's view from the air; 2 down in a canyon of the front range; 3 the valley looking
# south at the range; 4 under the 110 on 5th St; 5 on the 110's deck; 6 down in the river; 7 a
# suburban street by a sound wall; 8 downtown at noon.
# Heights are above the ground there (EYE_AGL=1); the river's is down in the channel, under the
# land level the plan gives.
SHOTS_DEFAULT="300,2,600,0,6@13;300,260,-650,0,-6@15;420,2,-1500,0,-2@15;300,2,-2900,180,-2@15;2045,1.7,2,60,10@13;1989,12.0,160,-6,-3@13;4584.8,-5.4,1191.5,-177,2@13;-527.9,1.7,183.5,-90,0@13;2359.4,2,880,0,12@12"
SHOTS=${SHOTS:-$SHOTS_DEFAULT}
first=${SHOTS%%;*}
rest=${SHOTS#*;}
cam=${first%%@*}
for mode in "${modes[@]}"; do
	envs=(OUT="$OUT/$mode.png" FRAMES=${FRAMES:-40} SHOT_FRAMES=${SHOT_FRAMES:-30} DIFF=1 EYE_AGL=1 EYE="$cam" SHOTS="$rest")
	case $mode in
		off) envs+=(OCCLUDERS=0) ;;
		none) envs+=(OCCLUSION=0) ;;
	esac
	start=$(date +%s)
	env "${envs[@]}" LIBGL_ALWAYS_SOFTWARE=1 timeout 2400 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" \
		--rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
		--script tools/glshot/still_shot.gd --resolution 960x540 \
		-- --spawn=300,600,0,6 --hour=13 --weather=clear --nohud --quality=0 > "$OUT/$mode.log" 2>&1
	echo "$mode: $(( $(date +%s) - start )) s"
	grep -E "^GEO" "$OUT/$mode.log"
done
