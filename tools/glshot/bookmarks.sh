#!/usr/bin/env bash
# The fixed camera bookmarks every visual change is judged on, before and after.
#
#   GODOT=/path/to/godot tools/glshot/bookmarks.sh <out_dir> [bookmark ...]
#
# With no names it shoots all seven: downtown_noon, downtown_night_rain, hills, freeway, masjid,
# esplanade_sunset, hero. Each is `<out_dir>/<name>.png`, 960x540 (the hero 720x720), through
# the opengl3 (Compatibility) renderer under Xvfb + llvmpipe: judge geometry and materials on
# them, not lighting - see forward_shot.sh for the real Forward+ look. Every render takes the
# shared lock `$LOCK` (default /tmp/rando_render.lock) so two agents never run two cities at once
# (each is several GB of RAM). Set FORWARD=1 to render through lavapipe (Forward+, ~6 min each).
set -u
OUT=${1:?usage: bookmarks.sh <out_dir> [bookmark ...]}
shift
GODOT=${GODOT:?set GODOT to the Godot 4.7.2 binary}
LOCK=${LOCK:-/tmp/rando_render.lock}
FORWARD=${FORWARD:-0}
mkdir -p "$OUT"
cd "$(dirname "$0")/../.."

# name | extra env | game args (spawn is x,z,yaw,pitch[,height])
BOOKMARKS=(
	"downtown_noon||--spawn=589.2,860,0,12,2 --hour=12 --weather=clear"
	"downtown_night_rain||--spawn=589.2,860,0,12,2 --hour=21.5 --weather=rain"
	"hills||--spawn=300,-1150,180,-12,520 --hour=15 --weather=clear"
	"freeway||--spawn=200,712,-90,-4,30 --hour=13 --weather=clear"
	"masjid||--spawn=-272,252,-31.8,-23.7,32 --hour=11 --weather=clear"
	"esplanade_sunset|EYE=-441.66,9.94,3534.58,-178,-1.5 FOV=44|--spawn=-441.7,3534.6,-178,-1.5 --hour=18.6 --weather=clear"
	"hero|||"
)

want=("$@")
driver=opengl3
[ "$FORWARD" = "1" ] && driver=vulkan
for entry in "${BOOKMARKS[@]}"; do
	IFS='|' read -r name extra args _ <<<"$entry"
	if [ ${#want[@]} -gt 0 ] && [[ ! " ${want[*]} " == *" $name "* ]]; then
		continue
	fi
	png="$OUT/$name.png"
	rm -f "$png"
	start=$(date +%s)
	if [ "$name" = "hero" ]; then
		env OUT="$png" WEAPON=0 AIM=1 YAW=35 CAM_AT=head CAM_DIST=1.6 LIBGL_ALWAYS_SOFTWARE=1 \
			flock "$LOCK" timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" \
			--rendering-driver $driver --display-driver x11 --audio-driver Dummy --path . \
			--script tools/glshot/hero_shot.gd --resolution 720x720 > "$OUT/$name.log" 2>&1
	else
		# shellcheck disable=SC2086
		env OUT="$png" FRAMES=${FRAMES:-45} $extra LIBGL_ALWAYS_SOFTWARE=1 \
			flock "$LOCK" timeout 1500 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" \
			--rendering-driver $driver --display-driver x11 --audio-driver Dummy --path . \
			--script tools/glshot/still_shot.gd --resolution 960x540 \
			-- $args --nohud --quality=0 > "$OUT/$name.log" 2>&1
	fi
	if [ -f "$png" ]; then
		echo "$name ok ($(( $(date +%s) - start )) s)"
	else
		echo "$name FAILED (see $OUT/$name.log)"
	fi
done
