#!/bin/bash
# One-time setup for the hero pipeline: Blender 4.2 LTS, the MPFB 2 extension and the CC0
# MakeHuman system asset pack, all into HERO_BUILD (default build/hero_src, git-ignored).
# About 700 MB of downloads and 2 GB on disk. Safe to re-run: every step is skipped once done.
#
#   tools/hero/setup.sh
#
# Links are the ones the hero was built from (docs/ASSETS.md, "The hero"). Point BLENDER at an
# existing Blender 4.2 to skip that download.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="${HERO_BUILD:-$REPO/build/hero_src}"
BLENDER_VERSION=4.2.23
BLENDER_URL="https://download.blender.org/release/Blender4.2/blender-$BLENDER_VERSION-linux-x64.tar.xz"
MPFB_URL="https://extensions.blender.org/download/sha256:4f0a879d64a39bf646fbf5f53601ac678855da329d650617dca5737548239a87/add-on-mpfb-v2.0.17.zip"
ASSETS_URL="https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip"
mkdir -p "$OUT/dl" "$OUT/blender_user"
touch "$OUT/.gdignore"  # Godot scans the whole project folder; keep it out of all of this

fetch() { # url file
	if [ ! -s "$OUT/dl/$2" ]; then
		echo "== downloading $2"
		curl -sSL --fail -o "$OUT/dl/$2.part" "$1"
		mv "$OUT/dl/$2.part" "$OUT/dl/$2"
	fi
}

if [ -z "${BLENDER:-}" ]; then
	BLENDER="$OUT/blender/blender-$BLENDER_VERSION-linux-x64/blender"
	if [ ! -x "$BLENDER" ]; then
		fetch "$BLENDER_URL" blender.tar.xz
		mkdir -p "$OUT/blender"
		tar -xf "$OUT/dl/blender.tar.xz" -C "$OUT/blender"
	fi
fi
export BLENDER_USER_RESOURCES="$OUT/blender_user"

if [ ! -d "$OUT/blender_user/extensions/user_default/mpfb" ]; then
	fetch "$MPFB_URL" mpfb-v2.0.17.zip
	echo "== installing MPFB"
	"$BLENDER" -b --factory-startup --command extension install-file -r user_default -e "$OUT/dl/mpfb-v2.0.17.zip"
fi

DATA="$OUT/blender_user/extensions/.user/user_default/mpfb/data"
if [ ! -d "$DATA/skins/middleage_caucasian_male" ]; then
	fetch "$ASSETS_URL" makehuman_system_assets_cc0.zip
	echo "== unpacking the MakeHuman system assets"
	mkdir -p "$DATA"
	unzip -q -o "$OUT/dl/makehuman_system_assets_cc0.zip" -d "$DATA"
fi
echo "== hero pipeline ready: $BLENDER"
