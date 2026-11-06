# shots/rc5-power-plant-dusk

The new wave-8 refcam `power_plant_dusk`: the coastal power plant at 18:50 clear from the wet sand
north of it (eye -713, 1.7 agl, 1115; yaw -141, pitch 9, fov 66). opengl3 stills from
`tools/refcams/refcams.py` (`REFCAMS_JSON=tools/refcams/cameras_w8.json`). "Before" is the same
build with `RC5_POWER_PLANT=0` (the A/B switch puts the plant and the sand exactly as on main).

- `01_before_power_plant_dusk.jpg` - main's look: the window bands flat cream slabs z-fighting the
  wall, moon-grey unlit cladding, lamp dots that light nothing, the damp sand crumpled foil.
- `02_after_power_plant_dusk_round1.jpg` - round 1 (the plant lit, framed glazing).
- `03_closeup_before_over_after_round1.jpg` - the halls close up from an earlier eye, before over after.
- `04_after_power_plant_dusk_final.jpg` - final.
- `05_plant_closeup_before_left_after_right.jpg` - the plant cropped from 01 and 04.
- `06_foreground_sand_before_over_after.jpg` - the foreground sand: foil glitter before, a soft moon path after.
- `07_ten_cameras_switch_off_over_on.jpg` - the ten original refcams, switch off over on: only
  street_noon and freeway flagged, by live traffic alone (a bus, freeway cars; diffs checked).

| refcam power_plant_dusk | p5 | p50 | p95 | p99 | sat | tris | draws |
|---|---|---|---|---|---|---|---|
| before (switch off) | 14 | 38 | 86 | 126 | 0.383 | 4,063,255 | 1,686 |
| after | 14 | 39 | 95 | 120 | 0.375 | 4,052,546 | 1,675 |
