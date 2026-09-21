#!/usr/bin/env bash
# Render one screenshot of the city, aiming the camera AT a world point instead of guessing a yaw.
#
#   tools/glshot/shot.sh <name> <cam_x,cam_z> <look_x,look_z> [height] [hour] [frames]
#
# The camera is placed at cam_x,cam_z (held at `height` metres while the world streams in) and
# yawed/pitched so that look_x,look_z is in the middle of the frame. Godot's forward is -Z, so
# yaw = atan2(-dx, -dz) and pitch = -atan2(height - 2, horizontal distance).
# Output goes to $SC/<name>.png ($SC defaults to the scratchpad).
set -u
NAME=$1
CAM=$2
LOOK=$3
HEIGHT=${4:-3}
HOUR=${5:-14}
FRAMES=${6:-60}
SC=${SC:-$(dirname "$0")/../../build/shots}
GODOT=${GODOT:-$SC/Godot_v4.7.2-stable_linux.x86_64}
mkdir -p "$SC"

read -r YAW PITCH <<<"$(python3 - "$CAM" "$LOOK" "$HEIGHT" <<'PY'
import math, sys
cx, cz = (float(v) for v in sys.argv[1].split(","))
lx, lz = (float(v) for v in sys.argv[2].split(","))
h = float(sys.argv[3])
dx, dz = lx - cx, lz - cz
yaw = math.degrees(math.atan2(-dx, -dz))
dist = math.hypot(dx, dz)
pitch = -math.degrees(math.atan2(max(h - 2.0, 0.0), max(dist, 1.0)))
print(f"{yaw:.1f} {pitch:.1f}")
PY
)"

echo "$NAME: cam $CAM h$HEIGHT -> look $LOOK  (yaw $YAW pitch $PITCH)"
OUT=$SC/$NAME.png FRAMES=$FRAMES LIBGL_ALWAYS_SOFTWARE=1 timeout 600 \
	xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" \
	--rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
	--script tools/glshot/city_shot.gd --resolution 1280x720 \
	-- "--spawn=$CAM,$YAW,$PITCH,$HEIGHT" "--hour=$HOUR" > /dev/null 2>&1
[ -f "$SC/$NAME.png" ] && echo "$NAME ok" || echo "$NAME FAILED"
