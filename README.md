# shots/fwd-review-c

Forward+ review (fleet session fwd-review-c) of the weather (marine layer, Santa Ana, heat haze),
Broadway's theatre district, the four-level stack and the minimap / full-screen map.

Every `_fwd` still is the REAL Forward+ renderer (Vulkan on lavapipe), not opengl3: a small scene
of FULL city blocks round the eye with the city's own WorldEnvironment, Sun, DayNight and Weather
(`tools/glshot/fwd_block_shot.tscn`, `--hour=` / `--weather=`). No far city, no horizon plane and
no ocean, so the distance past the built blocks is sky. 1280x720. EYEs are x,y,z,yaw,pitch (y over
the ground). The map stills are opengl3 at 3840x2160 (2D only; the Mac's Retina window is ~2,234
lines), `tools/minimap/map_shot.gd`.

Broadway at 21:00 (fixed: the palace shop windows read as flat warm-grey boards)
- `01_before_broadway_2100_empress_fwd.jpg` / `02_after_...` - the Empress, EYE 2981,1.7,234.8,-90,10.
- `03_before_broadway_2100_lapaloma_fwd.jpg` / `04_after_...` - La Paloma, EYE 2998,1.7,255.4,90,12.
  After: dark glass (a dielectric), about half the shops shut, an open one lit from its ceiling.
- `05_broadway_2100_south_from_6th_fwd.jpg` / `06_after_...` - south from 6th, EYE 2984,1.7,170,180,4
  (06 is the first pass of the fix, open shops at half the final level).

Weather (no fault found on Forward+)
- `07_marine_0900_under_deck_flower_fwd.jpg` - under the deck at 09:00, towers into the grey ceiling.
- `08_marine_0900_under_deck_south_fwd.jpg` - the same, south.
- `09_marine_0900_above_deck_fwd.jpg` - 650 m up: the deck top (its tint matches the cumulus: the grade).
- `10_santa_ana_1500_flower_fwd.jpg`, `11_santa_ana_1500_toward_fire_fwd.jpg` - Santa Ana afternoon.
- `12_santa_ana_2200_fire_glow_fwd.jpg` - the fire's glow behind downtown at 22:00.
- `13_santa_ana_2200_fire_close_no_terrain_fwd.jpg` - the fire card close up (this tool builds no
  hill terrain round it, so its foot hangs in the air: not how the game draws it).

The four-level stack at noon (no fault found on Forward+)
- `14_stack_noon_under_fwd.jpg` (EYE 2175,1.8,-1330,140,16), `15_stack_noon_on_connector_fwd.jpg`
  (2248.94,43.62,-1362.84,74.2,-3), `16_stack_noon_aerial_fwd.jpg` (2440,290,-1080,45,-33).

The map at 4K (fixed: fixed-pixel minimap and marks)
- `17_before_hud_minimap_4k.jpg` / `18_after_...` - the clean HUD; `25_before_...` / `24_after_minimap_4k_native_crop.jpg` native pixels.
- `19_before_fullmap_downtown_4k.jpg` / `20_after_...`, `23_after_fullmap_4k_native_crop.jpg` native.
- `21_before_fullmap_basin_4k.jpg` / `22_after_...`.
