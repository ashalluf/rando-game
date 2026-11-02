# shots/rc2-rain-day

Refcam `rain_day` (tools/refcams/cameras_w5.json): Wilshire in midtown, 14:00, rain. opengl3 (Compatibility) stills.

- `01_before_rain_day_main_framing_v0.jpg` - main bb03d731, the first framing tried (a lamp pole dead centre; later moved 2.5 m back onto the pavement's inner edge).
- `02_before_rain_day.jpg` - the final camera row, RAIN_DAY=0 (= main's look; staged cars are the tool's): crisp sun shadows of the lamp pole and palms under a rain sky, the wet road mirroring bright sky kerb to kerb, neon turf, a police helicopter's sweep searchlight at 14:00 (top left), grey lens-drop discs, a flat grey sky.
- `03_after_rain_day.jpg` - RainDay on: overcast diffuse light (no hard shadows), the wet road darker with the sky down its middle and the fronts mirrored along its sides, soaked turf and paving, no searchlight, few lens drops, a heavy mottled rain deck. The bus at its stop is the load's own traffic.
- `04_crop_traffic_spray_before_over_after.jpg` - the far traffic, before over after: tyre spray now reaches cars 95 m off (it stopped at 55 m).
- `05_crop_wet_road_and_paving_before_over_after.jpg` - the near paving and carriageway: darker soaked paving with a sheen (not a mirror), the road darker. (The pink-brown blob is a StreetWear stain, not rain; the bus is live traffic.)
- `06_crop_sky_and_light_before_over_after.jpg` - the sky and the tower: the flat grey deck becomes heavy masses and thin places; the helicopter searchlight (top left, before) is gone.
- `07_forwardplus_sky_rain_deck_off_over_on.jpg` - Forward+ (lavapipe), tools/sky/sky_shot.gd at coverage 0.92: rain_deck 0 over 1 - the volume path takes the masses too. (The street scene itself was OOM-killed on lavapipe at ~14 GB, home block only, so the street's lighting is unproven on Forward+.)
- `08_ten_refcams_off_over_on.jpg` - the ten original refcams, RAIN_DAY=0 over on: identical but for live traffic (street_noon's bus, the freeway's truck, street_night's bus).
- `09_after_rain_day_final_merged.jpg` - the final branch (merged with main batch 34): the same row, no bus at the stop this time so the deco frontage shows. p5/p50/p95 41/121/163.
