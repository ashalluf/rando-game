# load-time stills (opengl3 / Compatibility, 1280x720, DIFF=1 still_shot.gd)

The load cache must change nothing on screen. Each pair is the same frame with the cache OFF
(LOAD_CACHE=0: the basin bake and every far-city tile built fresh) and WARM (both read back from
user://load_cache). Pixel diff (tools/glshot/img_diff.py), off vs warm: 0.011 % / 0 % / 0.001 %
of pixels differ, max 6/255 - under the noise floor of two fresh builds of the same frame
(0.022 %, max 10).

- 01 / 02 aerial over the 110 toward downtown, noon (`EYE 1500,260,2400,-30,-14`)
- 03 / 04 Flower St at street level, noon (`2380,3,860,0,2`)
- 05 / 06 beach town toward downtown, 19:30 (`-760,40,-150,-90,-8`)
