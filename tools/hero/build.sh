#!/bin/bash
# Builds the player's hero from nothing but CC0 inputs and our own scripts, and writes
# assets/models/hero.glb plus the extra maps the game's hero shaders read (hero_x_*.png).
#
#   tools/hero/build.sh                 everything (about 15 minutes on 4 cores)
#   tools/hero/build.sh tracksuit       one step and everything after it
#   tools/hero/build.sh --only hair     one step alone
#   tools/hero/build.sh --render        after the build, Cycles close-ups into build/hero_src/renders
#
# Then, in the repo: `godot --headless --path . --import`, `python3 tools/fix_texture_imports.py
# assets/models` and commit hero.glb, the extracted hero_hero_* textures, the hero_x_* maps and
# every .import. The first run calls setup.sh (Blender 4.2, MPFB 2.0.17, MakeHuman assets).
# Steps, each a script in this folder, each reading the .blend the one before it saved:
#   body       build_body.py   MPFB base mesh, shape targets, eyes, brows, lashes, shoes, rig
#   tracksuit  tracksuit.py    jacket and trousers, collar, cuffs, piping, zip, tank
#   jewellery  jewellery.py    rope chain, watch, pinky ring
#   shoes      shoes.py        laces, eyelets, tongue; the shoe paint masks
#   hair       hair.py         layered hair cards grown along a combed-back flow
#   texspace   texspace.py     rasterises every UV map to world positions for the texture step
#   textures   prep_textures.py (python3) every map: skin, folds, wrinkle maps, hair, cloth, metal
#   finalize   finalize.py     subdivision, materials, one skinned mesh + shadow twin, game rig names
#   export     retarget.py     idle / walk / run retargeted from our own clips, arms fixed, .glb
# Set THREADS (default 2) for Blender, and LOCK to a file to serialise with other renders.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
export HERO_BUILD="${HERO_BUILD:-$REPO/build/hero_src}"
export BLENDER_USER_RESOURCES="$HERO_BUILD/blender_user"
BLENDER="${BLENDER:-$HERO_BUILD/blender/blender-4.2.23-linux-x64/blender}"
if [ ! -x "$BLENDER" ] || [ ! -d "$BLENDER_USER_RESOURCES/extensions/user_default/mpfb" ]; then
	BLENDER="$BLENDER" "$HERE/setup.sh"
fi
THREADS="${THREADS:-2}"
mkdir -p "$HERO_BUILD/work"
touch "$HERO_BUILD/.gdignore"
RUN=()
if [ -n "${LOCK:-}" ]; then RUN=(flock "$LOCK"); fi
STEPS=(body tracksuit jewellery shoes hair texspace textures finalize export)
FROM="${1:-body}"
ONLY=""
RENDER=0
for a in "$@"; do
	case "$a" in
		--only) ONLY=1 ;;
		--render) RENDER=1 ;;
		--*) ;;
		*) FROM="$a" ;;
	esac
done
FILTER='^(BODY|REPORT|RETARGET|EXPORTED|LANDMARKS|TS |JW |SH |HAIR |TXS |TEX |WROTE)|Traceback|Error'
blender_step() { # script [args...]: stops the build on a Python error inside Blender
	local s="$1"; shift
	local log="$HERO_BUILD/work/${s%.py}.log"
	local status=0
	"${RUN[@]}" "$BLENDER" -b -t "$THREADS" --python-exit-code 1 --python "$HERE/$s" -- "$@" > "$log" 2>&1 || status=$?
	grep -E "$FILTER" "$log" || true
	if [ $status != 0 ]; then echo "== $s FAILED, full log: $log"; exit 1; fi
}
started=0
for s in "${STEPS[@]}"; do
	if [ "$s" = "$FROM" ]; then started=1; fi
	[ $started = 1 ] || continue
	echo "== $s"
	case "$s" in
		body) blender_step build_body.py ;;
		tracksuit) blender_step tracksuit.py ;;
		jewellery) blender_step jewellery.py ;;
		shoes) blender_step shoes.py ;;
		hair) blender_step hair.py ;;
		texspace) blender_step texspace.py ;;
		textures) python3 "$HERE/prep_textures.py" ;;
		finalize) blender_step finalize.py ;;
		export) blender_step retarget.py ;;
	esac
	if [ -n "$ONLY" ]; then break; fi
done
if [ $RENDER = 1 ]; then
	"${RUN[@]}" "$BLENDER" -b -t "$THREADS" --python "$HERE/render.py" -- --glb "$REPO/assets/models/hero.glb" \
		--neutral --out "$HERO_BUILD/renders/hero_" --views front,34,face,chest,lwrist,feet --samples 48 --res 1024 2>&1 | grep -E "WROTE|Traceback|Error" || true
fi
echo "== done: $REPO/assets/models/hero.glb"
