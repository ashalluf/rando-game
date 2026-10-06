#!/usr/bin/env bash
# Polls the remote's shots/* heads; prints one line per poll when any moved.
SP="${SP:-/tmp/fleet_lead}"; mkdir -p "$SP"
cd /home/user/rando-game
BASE="$SP/shots_seen.txt"
[ -f "$BASE" ] || git ls-remote origin 'refs/heads/shots/*' | sort > "$BASE"
while true; do
  NOW=$(git ls-remote origin 'refs/heads/shots/*' 2>/dev/null | sort)
  if [ -n "$NOW" ]; then
    CHANGED=$(comm -13 "$BASE" <(echo "$NOW") | awk '{print $2}' | sed 's#refs/heads/shots/##' | tr '\n' ' ')
    if [ -n "$CHANGED" ]; then
      echo "SHOTS $(date -u +%H:%M): $CHANGED"
      echo "$NOW" > "$BASE"
    fi
  fi
  sleep 180
done
