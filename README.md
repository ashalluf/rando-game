# Crowd life stills (branch wt/crowd-life, HANDOFF 9ba)

opengl3 (Compatibility) stills, 1280x720, `tools/glshot/still_shot.gd` (before = the same EYE
with `CROWD_LIFE=0`) and the crowd lab (`tools/crowd/crowd_lab.tscn`). Motion is the point of
this change; stills only show a frozen instant (see HANDOFF 9ba for where to walk).

| File | What |
|---|---|
| 01_downtown_pavement_before/after | Flower at Olympic, east pavement looking north (`EYE=2368.5,1.8,872,8,-6`). Before: everyone walking. After: a group stopped talking ahead, walkers passing. GEO 7.755 M / 3,625 draws -> 7.783 M / 3,638 |
| 02_group_talking_before/after | West pavement under the street trees (`EYE=2352.5,1.7,878.5,135,-6`): a pair facing each other, one gesturing. 4.20 M / 1,719 -> 4.31 M / 1,732 |
| 03_night_group_under_lamp_after | The east pavement at 21:30: a group of four talking under a street lamp |
| 04_plaza_bench_before/after | A plaza bench (`EYE=2344.5,1.4,836,112,-8`): someone sitting on it, hips on the seat, feet planted (two-bone leg solve) |
| 05_beach_town_jogger_after | Beach town (`--spawn=-500,1000`, `LIFE_FOCUS=jog`): a jogger on the pavement (the CC0 jog, stride scaled to ~3 m/s) |
| 06_beach_town_dog_walker_after | Beach town (`LIFE_FOCUS=dog`): a dog walker with the CC0 Shiba Inu at heel (the lead is not drawn here: it updates on a tick the frozen still skips; see 10) |
| 07_esplanade_before/after | The Esplanade bookmark at 17:12: identical - only three people within 80 m there, none in frame. Joggers and dog walkers are 14 % / 12 % of its walkers |
| 08_lab_props_call_text_cup_bag_smoke | Lab: a call (phone at the ear), texting, a coffee carried upright, a shopping bag hanging plumb, a smoker |
| 09_lab_bench_sitter | Lab: a sitter on the game's bench model |
| 10_lab_dog_on_lead | Lab: a dog walker on the phone, the dog on a red lead to her left hand |
| 11_lab_life_wide | Lab: a wall, two benches, people leaning, sitting, standing |
