#!/bin/bash
# One-time setup for tools/make_road_cars.py: Blender 4.2 LTS into CAR_BUILD (default
# build/car_src, git-ignored, with a .gdignore so Godot does not scan it). About 350 MB of
# download. Safe to re-run: skipped once done. Prints the blender path to use.
#
#   tools/road_cars_setup.sh
#   build/car_src/blender/blender-4.2.23-linux-x64/blender -b --factory-startup \
#       -P tools/make_road_cars.py -- sedan crossover pickup
#
# Point BLENDER at an existing Blender 4.2 (tools/hero/setup.sh fetches the same one) to skip it.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OUT="${CAR_BUILD:-$REPO/build/car_src}"
BLENDER_VERSION=4.2.23
BLENDER_URL="https://download.blender.org/release/Blender4.2/blender-$BLENDER_VERSION-linux-x64.tar.xz"
mkdir -p "$OUT/dl"
touch "$OUT/.gdignore"
BLENDER="${BLENDER:-$OUT/blender/blender-$BLENDER_VERSION-linux-x64/blender}"
if [ ! -x "$BLENDER" ]; then
	if [ ! -s "$OUT/dl/blender.tar.xz" ]; then
		echo "== downloading Blender $BLENDER_VERSION"
		curl -sSL --fail -o "$OUT/dl/blender.tar.xz.part" "$BLENDER_URL"
		mv "$OUT/dl/blender.tar.xz.part" "$OUT/dl/blender.tar.xz"
	fi
	mkdir -p "$OUT/blender"
	tar -xf "$OUT/dl/blender.tar.xz" -C "$OUT/blender"
	rm -f "$OUT/dl/blender.tar.xz"
fi
echo "== road car pipeline ready: $BLENDER"
