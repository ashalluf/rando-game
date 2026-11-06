# shots/rc5-coyote-night

Refcam5 `coyote_night` (tools/refcams/cameras_w8.json): a suburban street in the south basin at
02:00 clear, eye level in the parking lane looking west along the north kerb. opengl3, 1280x720,
the row's staging (a coyote under the lamp, two raccoons at the kerb carts) on both sides.
Before = `RC5_COYOTE_NIGHT=0` (main's code paths), after = the branch.

- `01_before_coyote_night.jpg` - main: people strolling at 02:00, a pink light cone hanging under
  the lamp against the clear sky, animals that do not read, landscape uplights burning.
- `02_after_coyote_night.jpg` - the branch.
- `03_before_after_animals_x2.jpg` - the coyote and raccoons, before over after (eyeshine).
- `04_before_after_lamp_shaft_x2.jpg` - the lamp: the drawn shaft gone in clear air.
- `05_before_after_houses_people_x2.jpg` - the 2 a.m. walker gone, the house's uplight off on its timer.
- `06_eyeshine_opengl3_top_forwardplus_bottom.jpg` - tools/rc5_coyote_night/eye_shot.gd: coyote,
  raccoon (head down: no shine), deer - opengl3 over Forward+ (lavapipe), the same tapetum colours.

Numbers (refcams report): p5/p50/p95 5/35/105 -> 5/34/105; triangles 5,311,889 -> 5,230,618
(-1.5 %), draws 3,097 -> 3,071.
