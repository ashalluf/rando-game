#!/usr/bin/env bash
# Screenshot the game through the REAL Forward+ renderer, headless, with no GPU.
#
#   tools/glshot/forward_shot.sh out.png "--spawn=700,420,180,-16,16 --hour=11 --nohud" [WxH] [frames]
#
# The other scripts in this folder use --rendering-driver opengl3, which is the Compatibility
# renderer: no SDFGI, no SSR, no TAA, no volumetric fog, flat lighting. That is NOT what the
# owner's Mac draws, and judging a lighting or material change on it is judging the wrong thing.
#
# lavapipe (Mesa's software Vulkan driver, package mesa-vulkan-drivers) gives Godot a Vulkan
# device with no hardware, so --rendering-driver vulkan runs the full Forward+ pipeline on the
# CPU. Everything in the city scene's Environment then actually applies.
#
# It is SLOW - about six minutes for one 960x540 frame set - so use it to check a finished
# change, not to iterate. Use city_shot.gd on opengl3 for the fast loop.
#
# If Godot says it cannot find a Vulkan device, the driver is missing:
#   apt-get update && apt-get install -y mesa-vulkan-drivers
# and check /usr/share/vulkan/icd.d/lvp_icd.json exists.
set -euo pipefail

OUT=${1:?usage: forward_shot.sh out.png "<game args>" [WxH] [frames]}
ARGS=${2:-"--nohud"}
RES=${3:-960x540}
FRAMES=${4:-25}
GODOT=${GODOT:-$(command -v godot || echo "")}
if [ -z "$GODOT" ]; then
	echo "set GODOT to the Godot 4.7.2 binary" >&2
	exit 1
fi
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

OUT="$OUT" FRAMES="$FRAMES" xvfb-run -a -s "-screen 0 1280x720x24" \
	"$GODOT" --rendering-driver vulkan --display-driver x11 --audio-driver Dummy \
	--path "$REPO" --script tools/glshot/city_shot.gd --resolution "$RES" -- $ARGS
