#!/bin/bash
# The web build's bookmarks, ONE tab at a time (a tab is ~6 GB with SwiftShader's GPU process).
#   tools/webshot/bookmarks.sh <outdir> [name ...]     (default: all; ~15-25 min each)
# Export first: godot --headless --path . --export-release "Web" build/web/index.html
# Per bookmark: <name>.png, <name>.log (the whole console, [probe] lines, the JS heap), <name>.out.
# KEY=k is the gesture (Web Audio starts, nothing fires); 7 minutes of streaming before it.
OUT=${1:?outdir}; shift
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
cd "$(dirname "$0")"
declare -A QS=(
  [downtown_noon]='?spawn=2359.4,880,0,12,2&hour=12&weather=clear&nohud'
  [night_street]='?spawn=2359.4,880,0,12,2&hour=21.5&weather=clear&nohud'
  [rain]='?spawn=2359.4,880,0,12,2&hour=13&weather=rain&nohud'
  [golden]='?spawn=2359.4,880,0,12,2&hour=18.5&weather=clear&nohud'
  [storm]='?spawn=2359.4,880,0,12,2&hour=16&weather=storm&nohud'
  [hills]='?spawn=300,-650,0,-6,260&hour=15&weather=clear&nohud'
  [macarthur]='?spawn=300,430,0,-8&hour=12&weather=clear&nohud'
  [beach]='?spawn=-925,-310,62,-4&hour=15&weather=clear&nohud'
  # Wave 5-8's night and weather shaders (refcams bonfire_night, port_night, arena_night,
  # brush_fire), added by web-review-5.
  [beach_night]='?spawn=-862.6,-56.7,44,-5&hour=21&weather=clear&nohud'
  [port_night]='?spawn=3182,6490,101,10&hour=22&weather=clear&nohud'
  [arena_night]='?spawn=2183,1139,36,22&hour=21&weather=clear&nohud'
  [santa_ana]='?spawn=7,420,3,-4&hour=18.5&weather=santa_ana&nohud'
)
NAMES=("$@"); [ ${#NAMES[@]} -eq 0 ] && NAMES=(downtown_noon night_street rain golden storm hills macarthur beach beach_night port_night arena_night santa_ana)
for n in "${NAMES[@]}"; do
  QS="${QS[$n]}" SHOT="$OUT/$n.png" LOG="$OUT/$n.log" PROBE=1 KEY=k WAIT=${WAIT:-420000} \
    SHOT_TIMEOUT=1200000 timeout 2400 node webshot.js > "$OUT/$n.out" 2>&1
  echo "$n: exit $? $(grep -cviE 'AudioContext|occlusion|_print_warning|\[log\]|\[probe\]|\[heap\]' "$OUT/$n.log") unexpected console lines"
done
