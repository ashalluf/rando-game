#!/bin/bash
# Fetches the CC0 sources of the crowd's everyday clips and the dog into build/ual_src/
# (git-ignored, with a .gdignore so Godot does not import them):
#   Quaternius - Universal Animation Library 1 and 2, the free [Standard] files (itch.io, CC0)
#   Quaternius - Ultimate Animated Animals, ShibaInu.gltf (Google Drive, CC0)
# Then: godot --headless --path . -s tools/crowd/life_clips.gd   (writes assets/models/crowd_life/)
# The dog's .glb in assets/models/dog_shiba.glb is ShibaInu.gltf rewritten by GLTFDocument.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$REPO/build/ual_src"
TMP="$(mktemp -d)"
mkdir -p "$OUT/animals"
touch "$OUT/.gdignore"

# itch.io free download: the page's CSRF token -> a download page -> a signed file URL.
itch() {
	local user=$1 slug=$2
	local cj="$TMP/$slug.cj"
	curl -s -c "$cj" -b "$cj" -L "https://$user.itch.io/$slug" -o "$TMP/$slug.html"
	local tok dl id url
	tok=$(grep -o -E 'name="csrf_token" value="[^"]+"' "$TMP/$slug.html" | sed 's/.*value="//;s/"$//')
	dl=$(curl -s -c "$cj" -b "$cj" -X POST --data-urlencode "csrf_token=$tok" "https://$user.itch.io/$slug/download_url" \
		| python3 -c "import sys,json;print(json.load(sys.stdin)['url'])")
	curl -s -c "$cj" -b "$cj" "$dl" -o "$TMP/$slug.dl.html"
	id=$(grep -o -E 'data-upload_id="[0-9]+"' "$TMP/$slug.dl.html" | head -1 | grep -o '[0-9]*')
	tok=$(grep -o -E 'name="csrf_token" value="[^"]+"' "$TMP/$slug.dl.html" | sed 's/.*value="//;s/"$//')
	url=$(curl -s -c "$cj" -b "$cj" -X POST --data-urlencode "csrf_token=$tok" "https://$user.itch.io/$slug/file/$id?source=game_download" \
		| python3 -c "import sys,json;print(json.load(sys.stdin)['url'])")
	curl -sL "$url" -o "$TMP/$slug.zip"
	unzip -oq "$TMP/$slug.zip" -d "$TMP/$slug"
}
itch quaternius universal-animation-library
itch quaternius universal-animation-library-2
cp "$TMP"/universal-animation-library/*/Unreal-Godot/UAL1_Standard.glb "$OUT/"
cp "$TMP"/universal-animation-library-2/*/Unreal-Godot/UAL2_Standard.glb "$OUT/"
cp "$TMP"/universal-animation-library/*/License.txt "$OUT/UAL_License.txt"
# Ultimate Animated Animals (glTF folder of the pack's public Drive share).
curl -sL "https://drive.google.com/uc?export=download&id=1XWUVbmMbiG9E90OqrumueD_pBdnYdyHZ" -o "$OUT/animals/ShibaInu.gltf"
curl -sL "https://drive.google.com/uc?export=download&id=1F2uy8T2fRpdc6gZ4mnS02_C2E63WvKtn" -o "$OUT/animals/License.txt"
rm -rf "$TMP"
ls -la "$OUT" "$OUT/animals"
