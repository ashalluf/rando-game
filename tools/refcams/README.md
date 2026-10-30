# Reference cameras (G1)

Ten fixed views of the city, each with its own hour and weather, shot from ONE load of the city
through opengl3 + Xvfb, measured, and compared run against run. The point: every push (and every
fleet branch the lead merges) gets the same ten frames and the same numbers, so a change that
darkens the night, shifts the grade warm or doubles the triangles of a view is caught by a
number, not by someone happening to look.

| name | view | hour | weather |
|---|---|---|---|
| street_noon | Flower at Olympic, downtown, eye height | 12:00 | clear |
| street_night | the same street | 21:30 | rain |
| sunset | the Esplanade down the coast | 18:36 | clear |
| golden_aerial | downtown from the south-west, 140 m up | 18:18 | clear |
| downtown_aerial | the civic centre, 60 m up | 12:30 | clear |
| beach | the waterline at z 800 | 14:00 | clear |
| hills | the front range from 260 m | 15:00 | clear |
| freeway | the 110's deck by downtown | 13:00 | clear |
| macarthur | MacArthur Park from the south, 120 m up | 11:00 | clear |
| pier_night | the pier and its wheel from the beach | 21:00 | clear |

The table is `cameras.json` (eye = TRUE world x, y, z, yaw, pitch; `agl` = y over the plan's
ground). **Change a camera only on purpose**: the runs before stop being comparable for it.

## Running

```
GODOT=/path/to/godot python3 tools/refcams/refcams.py run build/refcams/<label>
```

One city load (opengl3, llvmpipe, ~3.5 GB) then each camera: the free camera placed, hour and
weather forced (the streets soaked or dried to match), the chunks round it streamed in at once,
`SHOT_FRAMES` (30) frames to adapt, `SETTLE` (6) with the clock all but stopped, the PNG, the GEO
counters. It takes the opengl3 render lock (`/tmp/rando_render_gl.lock`) like bookmarks.sh, so it
never runs beside another city. `--only street_noon,beach` shoots a subset; `--strict` is
still_shot's DIFF mode (shader TIME held, people, cars, aircraft, particles and the player hidden)
for a pixel-exact before/after of one change.

The folder gets `<name>.png` x 10, `frames.json` (Godot's side: GEO counts, the eye used, time
per shot, load time), `report.json` / `report.txt` (the numbers) and `sheet.jpg` (2 x 5 contact
sheet with each shot's p5/p50/p95, saturation, CCT, triangles and draws under it).

Numbers per shot: luminance p1/p5/p50/p95/p99 (PIL "L", 0-255: the measure CLAUDE.md's grade
targets use - a midday street wants about 87/123/175), clipped (>= 250) and crushed (<= 5) share,
mean HSV saturation, mean colour, a colour temperature (McCamy's CCT of the mean linear colour:
it tells a warm frame from a cool one; it is not the light's temperature), and the frame cost
(triangles, draws, objects, camera / shadow split).

## Comparing

```
python3 tools/refcams/refcams.py compare build/refcams/main build/refcams/wt-foo [--out dir]
```

Prints each shot's change (luminance p5/p50/p95, saturation, colour temperature in mireds, triangles %, draws %, mean
pixel difference) and FLAGS every shot past a tolerance (defaults in `TOL` at the top of
refcams.py, every one overridable: `--lum-p50 4 --tris-pct 5` ...). Writes compare.json,
compare.txt, `compare.jpg` (before over after, flagged shots outlined red) and a difference
heat map `diff_<name>.jpg` per flagged shot. Exit code 1 when anything is flagged.

Shader TIME is held at its first instant in every run (water, surf, clouds stand still; `--live`
lets it run): with it running the beach and the pier moved by a third of their pixels between two
runs of one tree. Two runs are still NOT identical: traffic, people and birds move. The
tolerances are set above that noise (see the noise run in docs/HANDOFF.md, the refcams section);
use `--strict` on both sides when a change should be pixel-small.

## How the lead uses it

1. Once per base: `run build/refcams/base` on the tree you merge onto (main or fleet/base).
2. Per branch, after merging it locally and before the gate: `run build/refcams/<slug>`, then
   `compare build/refcams/base build/refcams/<slug>`.
3. A flag is a question, not a failure: a branch that adds a feature to a view SHOULD move its
   triangles; one that only touches the port should move nothing in these ten. Read compare.txt,
   look at compare.jpg and the diff maps, ask the branch about anything unexplained.
4. After a merge lands, its run becomes the next base. Post sheet.jpg with the build number.

Opengl3 is the Compatibility renderer (the web build), not the Mac's Forward+: the numbers track
change, they do not say what the Mac draws (CLAUDE.md, measurement trap 4).
