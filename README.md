# shots/buskers - street performers (branch wt/buskers)

All opengl3 (the Compatibility renderer, as the web build), seed 1337, 15:00 unless noted.

City (tools/glshot/still_shot.gd, the same EYE before and after; before = `BUSKERS=0`):
- `01_before_plaza_1500` / `02_after_plaza_drummer_1500` - the downtown plaza by Pershing Square,
  a bucket drummer facing out across the plaza from the fountain.
- `03_before_plaza_south_1500` / `04_after_plaza_living_statue_1500` - the same plaza's other slot:
  a silver living statue on its plinth.
- `05_before_pavement_1500` / `06_after_pavement_mariachi_trio_1500` - a mariachi trio on a downtown
  pavement with its case open, two people stopped to watch. (This frame's violinist is crowd_s in a
  hi-vis vest; that rig has since been taken off the mariachi list.)

Acts alone (tools/buskers/busk_shot.tscn, seconds a frame; flat sky light, not the city's):
- `07_closeup_guitarist_case_amp`, `08_closeup_bucket_drummer`, `09_closeup_living_statue`,
  `10_closeup_mariachi_trio`, `11_breakdancer_toprock_ring`, `12_breakdancer_freeze_ring_claps`
  (the ring stands in the road only in this tool's layout; in the city a breakdancer is on a plaza),
  `13_mariachi_night` (NIGHT=1).

Frame cost (GEO, tris / draws, BUSKERS=0 -> on): plaza drummer 5,646,406 / 2,492 -> 5,708,346 /
2,514; plaza statue 5,477,732 / 2,415 -> 5,542,163 / 2,425; pavement with no act 3,476,383 / 1,531
-> 3,479,440 / 1,533; pavement mariachi trio at 6 m 4,871,292 / 2,794 -> 5,086,697 / 2,773.
