#!/usr/bin/env bash
# Fetches the car radio's source music (all CC0 / public domain; docs/ASSETS.md lists each) into
# the ignored build/radio_src/. Then: python3 tools/radio/make_radio.py (trims, levels, encodes
# assets/audio/radio/*.ogg and synthesises the station idents).
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=build/radio_src
mkdir -p "$OUT"
OGA=https://opengameart.org/sites/default/files
AO=https://archive.org/download
get() { [ -s "$OUT/$2" ] || curl -sSL -m 300 -o "$OUT/$2" "$1"; echo "$2"; }
# Velvet Hour (classical): Musopen's Chopin collection (CC0) and the Open Goldberg Variations (CC0).
get "$AO/musopen-chopin/Waltz%20Op.%2064%20no.%201%20in%20D%20flat%20major.mp3" vel_waltz64.mp3
get "$AO/musopen-chopin/Waltz%20Op.%2070%20no.%201%20in%20G%20flat%20major.mp3" vel_waltz70.mp3
get "$AO/OpenGoldbergVariations/KimikoIshizaka-J.s.Bach--open-GoldbergVariationsBwv988piano-31AriaDaCapoEFine.ogg" vel_aria.ogg
# Palm Static (lo-fi): OpenGameArt, CC0.
get "$OGA/ChillLofi.ogg" lofi_chill.ogg
get "$OGA/Cat%20caffe_0.mp3" lofi_cat.mp3
get "$OGA/A%20cup%20of%20tea_0.mp3" lofi_tea.mp3
# Neon Freeway (synth): OpenGameArt, CC0.
get "$OGA/S31-Night%20Prowler.ogg" syn_prowler.ogg
get "$OGA/Cyberpunk%20Moonlight%20Sonata%20v2.mp3" syn_moonlight.mp3
get "$OGA/The%20Rush_2.mp3" syn_rush.mp3
# Tiki Sunset (lounge): OpenGameArt, CC0.
get "$OGA/enchanted%20tiki%2086_0.mp3" lng_tiki.mp3
get "$OGA/gone_fishin_by_memoraphile_CC0_0.mp3" lng_fishin.mp3
get "$OGA/013_Another_August_0.mp3" lng_august.mp3
