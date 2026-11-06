#!/bin/bash
# A frame strip of one car (tools/glshot/car_shot.gd, a launch a frame): the camera orbits the car
# by STEP degrees a frame at DIST metres, FRAMES frames, written as OUT_DIR/f.png, f_1.png, ...
# so tools/specular_aliasing/strip.py measure / compare read it like a city strip.
#   GODOT=... OUT_DIR=build/strip/car_on TYPE=0 DIST=22 STEP=0.06 FRAMES=8 tools/specular_aliasing/car_strip.sh
# Extra env (SPECULAR_AA=0 for the before) passes through to Godot.
set -e
OUT_DIR=${OUT_DIR:-build/strip/car}
TYPE=${TYPE:-0}; DIST=${DIST:-22}; STEP=${STEP:-0.06}; FRAMES=${FRAMES:-8}; FOV=${FOV:-24}
AZ0=${AZ0:-35}; HEIGHT=${HEIGHT:-2.2}; RES=${RES:-1280x720}
mkdir -p "$OUT_DIR"
for k in $(seq 0 $((FRAMES - 1))); do
	read cx cz <<< $(python3 -c "import math; a=math.radians($AZ0 + $k * $STEP); print('%.5f %.5f' % ($DIST * math.sin(a), $DIST * math.cos(a)))")
	name=$([ "$k" = 0 ] && echo f || echo "f_$k")
	OUT="$OUT_DIR/tmp" xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --rendering-driver opengl3 --display-driver x11 \
		--audio-driver Dummy --path . --script tools/glshot/car_shot.gd --resolution "$RES" -- --type=$TYPE \
		--cam=$cx,$HEIGHT,$cz --look=0,0.7,0 --fov=$FOV ${CAR_ARGS:-} > "$OUT_DIR/run_$k.log" 2>&1
	mv "$OUT_DIR"/tmp_*.png "$OUT_DIR/$name.png"
done
echo "car strip: $FRAMES frames in $OUT_DIR"
