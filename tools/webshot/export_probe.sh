#!/bin/bash
# Exports the REAL main build with tools/webshot/web_autoprobe.gd as an extra autoload into
# build/web_autoprobe, then puts project.godot back (web-build-5).
#   GODOT=/path/to/godot tools/webshot/export_probe.sh
#   WEB_ROOT=build/web_autoprobe QS='?spawn=...&ap_settle=300&ap_every=120' LOG=ap.log \
#     KEY=k WAIT=420000 node tools/webshot/webshot.js; python3 decodes the PROBE_IMG lines.
set -e
cd "$(dirname "$0")/../.."
cp project.godot /tmp/web_autoprobe_project.godot
trap 'cp /tmp/web_autoprobe_project.godot project.godot' EXIT
python3 - <<'EOF'
s = open('project.godot').read()
s = s.replace('[autoload]\n', '[autoload]\n\nWebAutoProbe="*res://tools/webshot/web_autoprobe.gd"\n', 1)
open('project.godot', 'w').write(s)
EOF
grep -q WebAutoProbe project.godot
mkdir -p build/web_autoprobe
"$GODOT" --headless --path . --export-release "Web" build/web_autoprobe/index.html
