#!/bin/bash
# Builds the crowd (crowd_config.json) with the hero's pipeline: Blender 4.2, MPFB 2 and the CC0
# MakeHuman assets (tools/hero/setup.sh fetches them into build/hero_src, git-ignored).
#
#   tools/crowd/build.sh                  every character
#   tools/crowd/build.sh crowd_c crowd_f  just those
#   FROM=crowd_atlas tools/crowd/build.sh  from the atlas step on (the .blend from the last build)
#
# Per character, three steps (a minute or two each):
#   build_character.py (Blender)   MPFB human, clothes, hair, bind pose, budgets, atlas plan
#   crowd_atlas.py     (python3)   the body, normal and hair atlases
#   crowd_export.py    (Blender)   clips retargeted, assets/models/<name>.glb
# Then, in the repo: `godot --headless --path . --import`, `python3 tools/fix_texture_imports.py
# assets/models` (put back any unrelated .import it touches) and commit the .glb files, the
# crowd_*_body / _body_nrm / _hair textures Godot extracts and every .import.
# Set THREADS (default 2) for Blender, and LOCK to a file to serialise with other heavy jobs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
export HERO_BUILD="${HERO_BUILD:-$REPO/build/hero_src}"
export BLENDER_USER_RESOURCES="$HERO_BUILD/blender_user"
BLENDER="${BLENDER:-$HERO_BUILD/blender/blender-4.2.23-linux-x64/blender}"
if [ ! -x "$BLENDER" ] || [ ! -d "$BLENDER_USER_RESOURCES/extensions/user_default/mpfb" ]; then
	BLENDER="$BLENDER" "$REPO/tools/hero/setup.sh"
fi
THREADS="${THREADS:-2}"
RUN=()
if [ -n "${LOCK:-}" ]; then RUN=(flock "$LOCK"); fi
NAMES=("$@")
if [ ${#NAMES[@]} = 0 ]; then
	mapfile -t NAMES < <(python3 -c "import sys; sys.path.insert(0, '$HERE'); import crowd_common as C; print('\n'.join(C.names()))")
fi
FILTER='^(CROWD|RETARGET|EXPORTED|ATLAS)|Traceback|Error'
for n in "${NAMES[@]}"; do
	mkdir -p "$HERO_BUILD/crowd/$n"
	started=0
	for s in build_character crowd_atlas crowd_export; do
		if [ "$s" = "${FROM:-build_character}" ]; then started=1; fi
		[ $started = 1 ] || continue
		log="$HERO_BUILD/crowd/$n/$s.log"
		status=0
		if [ $s = crowd_atlas ]; then
			"${RUN[@]}" python3 "$HERE/$s.py" "$n" > "$log" 2>&1 || status=$?
		else
			"${RUN[@]}" "$BLENDER" -b -t "$THREADS" --python-exit-code 1 --python "$HERE/$s.py" -- "$n" > "$log" 2>&1 || status=$?
		fi
		grep -E "$FILTER" "$log" || true
		rm -f "$HERO_BUILD"/crowd/"$n"/*.blend1
		if [ $status != 0 ]; then echo "== $n: $s FAILED, full log: $log"; exit 1; fi
	done
	echo "== $n done: $REPO/assets/models/$n.glb"
done
