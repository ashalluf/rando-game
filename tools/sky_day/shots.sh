#!/bin/bash
# The day sky review's stills (docs/HANDOFF.md "The day sky"): tools/sky/sky_shot.gd over a set of
# views, one launch each, both renderers if asked. Usage:
#   GODOT=/path/godot tools/sky_day/shots.sh <outdir> [vulkan|opengl3] [view ...]
# A view is name:hour:yaw:pitch:cam_y[:fov]. With no views given, DAY views (09:00-16:00) are shot;
# VIEWS=hold shoots the other hours (the bit-identical proof, HOLD_TIME=1). Extra env (PARAMS=,
# SKY_DAY=0, COVERAGE=) is passed through to sky_shot.gd. SIZE=WxH (default 960x540).
set -u
out=${1:?outdir}; drv=${2:-vulkan}; shift 2 || shift $#
mkdir -p "$out"
G=${GODOT:-/home/user/Godot_v4.7.2-stable_linux.x86_64}
SIZE=${SIZE:-960x540}
day=(noon_sun:12:180:40:2 noon_north:12:0:4:2 noon_east:12:90:8:2 noon_air:12:200:-6:400
     h09_east:9:100:14:2 h10_sun:10.5:135:30:2 h14_west:14:250:10:2 h16_west:16:265:6:2 h15_air:15:250:-4:300)
hold=(h0530:5.5:90:6:2 h0700:7:90:8:2 h0830:8.5:100:12:2 h1630:16.5:265:6:2 h1800:18:270:4:2 h1900:19:270:6:2 h2200:22:0:20:2 h0300:3:180:20:2)
if [ $# -gt 0 ]; then views=("$@"); elif [ "${VIEWS:-day}" = hold ]; then views=("${hold[@]}"); else views=("${day[@]}"); fi
ICD=""
[ "$drv" = vulkan ] && ICD=/usr/share/vulkan/icd.d/lvp_icd.json
for v in "${views[@]}"; do
	IFS=: read -r name hour yaw pitch cy fov <<< "$v"
	VK_ICD_FILENAMES=$ICD OUT="$out/$name.png" HOUR=$hour YAW=$yaw PITCH=$pitch CAM_Y=$cy FOV=${fov:-70} \
		HOLD_TIME=${HOLD_TIME:-1} timeout 900 xvfb-run -a -s "-screen 0 ${SIZE}x24" "$G" \
		--rendering-driver "$drv" --display-driver x11 --audio-driver Dummy --path . \
		--script tools/sky/sky_shot.gd --resolution "$SIZE" -- --quality=0 2>&1 | grep -E "SKY wrote|ERROR" | head -5
done
