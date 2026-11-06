#!/bin/bash
# Exports the web build with tools/web_hero_rain/hero_rain.tscn as its main scene into
# build/web_hero (the real Web preset, the whole project), then puts project.godot back.
#   GODOT=/path/to/godot tools/web_hero_rain/export_web.sh
#   WEB_ROOT=build/web_hero QS='?hour=13&weather=rain' node tools/webshot/webshot.js
set -e
cd "$(dirname "$0")/../.."
cp project.godot /tmp/web_hero_rain_project.godot
trap 'cp /tmp/web_hero_rain_project.godot project.godot' EXIT
sed -i "s#^run/main_scene=.*#run/main_scene=\"${MAIN:-res://tools/web_hero_rain/hero_rain.tscn}\"#" project.godot
mkdir -p build/web_hero
"$GODOT" --headless --path . --export-release "Web" build/web_hero/index.html
