# Stills: NPC polish (branch wt/npc-polish, HANDOFF 9bp)

All opengl3 (Compatibility) stills. Pairs are before | after from the same camera.

| File | What |
|---|---|
| pigeon_close_before_after.jpg | `bird_shot.gd SPECIES=pigeon ONLY=0 CAM=0.45,0.28,-0.6 LOOK=0,0.11,0 FOV=30`: a standing pigeon at ~0.75 m - smoother loft, welded normals, folded wing shaded with the body |
| pigeon_underwing_before_after.jpg | `ONLY=5 CAM=0.05,0.02,-0.45 LOOK=0,0.39,0 FOV=50`: a gliding pigeon from below - grey underwing instead of the pale upper side |
| bird_lineup_after.jpg | `bird_shot.gd`: every species in every pose (gull underwing white) |
| turnout_before_after.jpg | `crowd_lineup.gd CREW=fire LIGHT=street CLIP=Idle`, rigs a, d, f, h, j: flat tan -> khaki turnout with triple trim, yoke, knee patches, gloves, boots |
| turnout_night_before_after.jpg | the same with `NIGHT=1` (lamp_factor 1, a sodium lamp): the trim is retroreflective toward the camera |
| medic_front_before_after.jpg / medic_side_before_after.jpg | `CREW=medic`: light blue tee -> navy uniform, shoulder patch, placket, badge, duty belt, cargo pockets, black boots |
| hose_day_before.jpg / hose_day_after.jpg | `still_shot.gd EMERGENCY=hose --hour=12.5 --spawn=2359.4,880,0,12,2` |
| hose_night_after.jpg | the same frame at 21:30 (`SHOTS=@21.5`) |
| medic_scene_before.jpg / medic_scene_after.jpg | `EMERGENCY=medic --hour=12.5` |
| bus_9bm_fix_noon.jpg / bus_9bm_fix_dusk_blocked.jpg | `BIG=bus --hour=12` and 18:18 from the stop's own eye: the 9bm windscreen fix holds at noon (a pedestrian blocks it at dusk) |
| bus_front_noon_before_after.jpg / bus_front_dusk_before_after.jpg / bus_front_night_before_after.jpg | `BIG=bus` with `EYE=2392.06,1.7,814.99,72.86,0` at 12:00, 18:18, 20:30: the cabin lamp on lamp_factor at 2.0 |
