#!/usr/bin/env bash
# drop.sh <slug> <path in shots/<slug>>...  -> $SP/drops/<slug>.jpg, a 2x2 (or 2xN) sheet
SP="${SP:-/tmp/fleet_lead}"; mkdir -p "$SP"; slug=$1; shift
cd /home/user/rando-game
git fetch -q origin "shots/$slug:refs/remotes/origin/shots/$slug" 2>/dev/null
D="$SP/drops/src_$slug"; mkdir -p "$D" "$SP/drops"; names=()
for f in "$@"; do n="$(basename "$f")"; git show "origin/shots/$slug:$f" > "$D/$n" && names+=("$n"); done
python3 tools/fleet/sheet.py "$SP/drops/$slug.jpg" "$D" "${names[@]}" && echo "$SP/drops/$slug.jpg"
