# web-build-2: the web build after wave 3 (headless Chromium, SwiftShader, WebGL 2, 960x540)

All `&weather=clear&nohud`; one tab at a time; console clean at every bookmark (only the
occlusion-culling build warning and Chrome's autoplay notice).

- `01_before_main_downtown_noon.jpg` - main's export (pck 582.0 MB), `?spawn=2359.4,880,0,12,2&hour=12`.
- `02_after_downtown_noon.jpg` - this branch's export (pck 550.0 MB: unused assets left out). Same view; the cut changes nothing drawn.
- `03_after_downtown_night_2130.jpg` - same spot at 21:30.
- `04_after_macarthur_park_noon.jpg` - `?spawn=300,430,0,-8&hour=12`.
- `05_after_beach_1500.jpg` - beach life and the power plant on the horizon, `?spawn=-725,610,160,-6&hour=15`.
- `06_after_coast_highway_1400.jpg` - `?spawn=-1034,-1100,0,-4&hour=14`.
- `07_after_power_plant_1600.jpg` - `?spawn=-700,1380,-90,-5&hour=16`.
- `08_after_refinery_1300.jpg` - `?spawn=2700,5440,-120,-18&hour=13`.
- `09_after_refinery_night_2100.jpg` - `?spawn=2700,5440,-120,-8&hour=21`.
- `10_after_walk_of_fame_noon.jpg` - `?spawn=780,-2329.2,90,-6&hour=12` (the camera is pushed in by the wall).
- `11_open_web_esplanade_noon_sky_block.jpg` - OPEN: `?spawn=-441.7,3534.6,-178,-1.5&hour=12`, the sky left of x~425 drawn as a flat gold-red block on SwiftShader only (glow spreads it over the palms).
- `12_open_web_esplanade_glow_off_debug.jpg` - the same with glow off (debug build): the sky block itself, pixel-sharp.
- `13_native_opengl3_esplanade_noon_clean.jpg` - the same view through llvmpipe (city_shot.gd): clean.

The other bookmarks' "before" equal their "after": the only shipping change is the export filter
(files nothing loads), and the code change is a check.
