#!/bin/bash
# Cycles preview sheet of exported crowd rigs (tools/crowd/preview.py has the views and modes).
#
#   tools/crowd/preview.sh out.png crowd_a,crowd_h [front,side,back] [0.25]
#   FLAT=1 tools/crowd/preview.sh ...     geometry only
#   REGION=1 tools/crowd/preview.sh ...   the region vertex colours
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
HERO_BUILD="${HERO_BUILD:-$REPO/build/hero_src}"
BLENDER="${BLENDER:-$HERO_BUILD/blender/blender-4.2.23-linux-x64/blender}"
"$BLENDER" -b --factory-startup -t "${THREADS:-2}" --python "$HERE/preview.py" -- "$@" 2>&1 | grep -E "PREVIEW|Error|Traceback"
