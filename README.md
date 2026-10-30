# shots/foot-ik: crowd foot placement (CrowdFeet)

Before = `FOOT_IK=0`, after = the branch. opengl3 (Compatibility) stills, 11:00 clear, from
`tools/glshot/still_shot.gd FEET=kerb|stairs|slope` (people staged standing, `tools/foot_ik/stage.gd`)
and the bare lab `tools/foot_ik/foot_lab.tscn`.

- `01_before_city_kerb_noon.jpg` / `02_after_...`: block (0,0)'s west kerb, `FEET_AT=13.2,100.1`.
  Before, the woman on the left (side-on at the edge) has her outer foot hanging ~15-20 cm in the air
  over the gutter; after it is down on the road and her other knee takes the step.
- `03` / `04` / `05`: the Esplanade's first beach stair (`FEET=stairs`), seen from the sand. Before,
  everyone's feet are at one height above the treads (the body stands on the walkable ramp the stairs
  collide as); after, each foot is on its own tread (the treads are now on a feet-only physics layer
  under the ramp). `05` is the close-up, before left, after right.
- `06` / `07` / `08`: a 15 % hillside beside Canyon 10 (`FEET_AT=674.4,-1003.5`). Subtle at this grade:
  the man facing uphill steps his back foot onto the rising ground instead of into it.
- `09`: lab kerb (15 cm), before top, after bottom. `10`: lab ramp (14 degrees), before left.
  `11`: lab stairs (17 x 30 cm), before left. `12` / `13`: a walker up the 14-degree ramp, before /
  after (headless numbers: planted-ankle error up the ramp 3.4 cm mean, 7.5 cm worst -> 1.0 / 3.4 cm;
  down it 2.3 / 6.3 -> 1.5 / 5.6).
