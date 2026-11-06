#!/bin/bash
# Exports the REAL main build with tools/web_probe/web_autoprobe.gd as an extra autoload into
# build/web_autoprobe, then puts project.godot back (web-build-5).
#   GODOT=/path/to/godot tools/web_probe/export_probe.sh
#   WEB_ROOT=build/web_autoprobe QS='?spawn=...&ap_settle=300&ap_every=120' LOG=ap.log \
#     KEY=k WAIT=420000 node tools/webshot/webshot.js; build/wb5-style decode of the PROBE_IMG lines.
# MAIN=res://... exports another main scene (tools/web_probe/fx_room.tscn); AUTOPROBE=0 leaves
# the autoload out; OUTDIR another folder.
set -e
cd "$(dirname "$0")/../.."
cp project.godot /tmp/web_autoprobe_project.godot
trap 'cp /tmp/web_autoprobe_project.godot project.godot' EXIT
if [ -n "$MAIN" ]; then
  sed -i "s#^run/main_scene=.*#run/main_scene=\"$MAIN\"#" project.godot
fi
if [ "${AUTOPROBE:-1}" != "0" ]; then
  sed -i 's#^\[autoload\]$#[autoload]\n\nWebAutoProbe="*res://tools/web_probe/web_autoprobe.gd"#' project.godot
  grep -q WebAutoProbe project.godot
fi
OUTDIR=${OUTDIR:-build/web_autoprobe}
mkdir -p "$OUTDIR"
"$GODOT" --headless --path . --export-release "Web" "$OUTDIR/index.html"
