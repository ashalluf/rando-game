# Handoff: Rando Game (written 2026-09-19; section 000000 is the newest state and the handoff to the next account, 2026-10-05)

This is the narrative handoff for whoever picks the project up next, from any Claude Code account
or as a person. `CLAUDE.md` is the rulebook and `docs/GAME_PLAN.md` is the roadmap plus the
decisions log; both stay the source of truth. This file is the story: where things stand, how
the day-to-day work goes, what is fragile, what to do next. Read all three before touching code.

## 000000. Takeover of 2026-10-05: the cloud fleet is stopped (read this first)

Newest. The owner stopped all work on 2026-10-05 at about 08:10 UTC and asked for a handoff to the
next account. Read this section, then CLAUDE.md, then the 9bp-9bt sections (the last ones merged
to main) and, on the integration branches, 9bu-9cy.

### Where everything is

- **`main` = `c11fe7f`, build 345, green.** The latest release is everything through the night
  aerial (HANDOFF 9bt). Nothing after that is on main.
- **`wt/integration-a` = `7542234`** (pushed for you; it descends from main, so it fast-forwards).
  It is main plus 19 fleet branches: audio, hero-moves, port-life, canals, photo-mode,
  police-station, pier, marina, explosions, climbing-plants, building-damage, more-people,
  perf-audit, schools, sky, minimap, weather, broadway and stack-interchange. Street errands
  (`wt/street-life-2`) were merged and then reverted (`d1c7427`): its own jaywalker check fails
  even merged alone onto main.
  - Gate at `d1c7427`: 1,361 passed, 1 failed ("the map draws no closed road"). That was a real
    order bug in `Schools.road_closed()`, fixed by `7542234`.
  - Gate at `7542234`: stopped by the owner's stop at 905 checks. The only failures were the
    blood-pool and stain pair, a flaky check fixed by `82a664c` (below; it cherry-picks cleanly
    onto integration-a). Nothing else has failed on this tree.
  - Numbering: HANDOFF sections go up to 9cm and roadmap rows up to #81.
- **`wt/integration-b` = `82a664c`** (pushed; descends from integration-a). It adds:
  - the follow-up commit of each rebased branch (explosions `7250e8d`, police `bd27e9e`);
  - `tools/cpu_probe.gd.uid`;
  - 12 more branches: construction, murals, signage, hospital, la-trees, car-dealers,
    airport-life, golf, dogs, hill-homes, oil-fields and vacant-lots;
  - the merge fixes listed below, and the blood-check fix `82a664c`.

  **It is not gated and must not go to main as it is.** Its smoke test was OOM-killed right after
  "city scene loads", at **10.9 GB** RSS. Integration-a's was about 3 GB. Another gate was
  running beside it on a 15 GB box, but even alone, 11 GB would not fit a CI runner. One (or
  more) of the 12 batch-3 branches is the cause; it is not found yet.

  Numbering: HANDOFF up to 9cy, roadmap up to #93; the next free ones are **9cz / #94**.

### Fixes made while merging (all on the integration branches, none on main)

- **Schools close roads deterministically** (`7542234`). `Schools.road_closed()` decided only
  the cells of the two blocks beside a road and cached "open". A high school's row can start in
  the next cell over, so a later decision closed a road the map had already drawn. It now decides
  the 3x3 cells round the road first.
- **Nothing claims a hospital's block** (`4cb5d22`). `CityPlan.block()` lets a hospital take a
  block after every other roll. Fire stations, police stations and schools now skip blocks
  marked `"hospital"`. Before, each could claim lots on a block whose `lots()` is empty and
  dispatch from, or bus to, a building that was never built.
- **The far city builds the oil field** (`db98a25`). In `CityChunk`'s capture step list, the oil
  field's case now comes before the canals' generic site case, which would have answered it with
  nothing.
- **Parked cars keep clear of everything.** The keep-clear chain covers bus stops, fire
  stations, police stations, schools and hospitals.
- **The blood check looks while it waits** (`82a664c`). The pool check waited up to 420 ticks
  and only then looked for the body. Debris lives 12 s of real time, so on a loaded box a body
  resting on a car (no pool by design) was freed first and read "0 of 0".
- **New input actions:** `photo_mode` (P / pad right-stick press) and `map` (M / pad Back). No
  clashes with existing bindings.
- **Additive conflicts were kept both sides:** `sfx.gd` sample tables (footsteps, bus, car alarm,
  dogs), the smoke-test lines, the `still_shot.gd` stage blocks, `CityChunk` step lists and lot
  claims, and the `Landmarks` site cases. Read the merge commits if something looks doubled.

### Do this next, in order

1. **Set up** as CLAUDE.md says (Godot 4.7.2 headless, `--import`).
2. **Ship integration-a**, one gate at a time and never two in parallel:
   `git checkout main && git merge --ff-only origin/wt/integration-a && git cherry-pick 82a664c`.
   Then run `tests/headless_check.sh` (25-30 min). If it is green, push main, watch the Actions
   run and tell the owner the build number. The stills for every merged branch are on its
   `shots/<slug>` orphan branch: send the owner a few (`tools/fleet/sheet.py` makes 2x2 sheets).
3. **Find integration-b's memory blow-up.**
   - Check out integration-b and run the smoke test (or just a scene that loads
     `scenes/levels/city.tscn` and waits ~300 frames) under `/usr/bin/time -v` to read peak RSS.
     Do it once with everything on, then with batch 3's systems switched off one at a time.
     The switches (environment, `=0`): `CONSTRUCTION`, `MURALS`, `BOULEVARD_SIGNS`, `HOSPITALS`,
     `LA_TREES`, `CAR_DEALERS`, `AIRPORT_GROUND`, `GOLF` / `GOLF_LIFE`, `DOGS` / `DOG_YARDS`,
     `HILL_HOMES`, `OIL_FIELD`, `VACANT_LOTS`.
   - Suspects by size: dogs (97 files, fur shells), la-trees (code-built trees warmed at load),
     golf and oil-fields (big site builders).
   - Fix the cause, gate, then `git merge origin/wt/integration-b` into main (the cherry-picked
     `82a664c` merges as a no-op) and push.
4. **Branches that are not merged anywhere yet.** "+n" is commits beyond integration-b. Review
   each, then merge it with `tools/fleet/merge_branch.py` off the new main:
   - alleys +6, scooters +5, rooftops +4, ridges +6, stadium +10, service-vehicles +13,
     wilshire-deco +4, reservoir +6, web-build +2;
   - perf-audit: +9 of new work after its merged tools, e.g. "beach town 7.40 -> 4.55 M
     triangles";
   - sky: +1, and the follow-up asked for below;
   - street-life-2: +6. It must merge main first and fix the jaywalker check ("ends on its own
     block") and the bus-queue check ("two walkers stand in the bus stop's queue"), and it
     needs stills.
   - explosions and police-station show as open only because their sessions rebased after the
     merge; their content is in integration-a and their one new commit each is in
     integration-b.
   - `wt/sedan-body` (8 days old) is superseded by the Blender-built bodies; leave it.
5. **No branch was ever pushed** for roadside, traffic-ai, driving-fx or freight-trains (they
   pushed `shots/<slug>` stills only). Their code lives only in those sessions' cloud containers
   on the old account and is probably lost. Redo them from the brief if the owner wants them.
   skate-park never started.

### Review notes from the stills (not fixed)

- The sky's new cumulus read stylised: smooth triangular puffs at golden hour, uniform blobs at
  noon. The sky session was asked to add ragged eroded edges, more size range and grey-violet
  shadowed bodies, but was stopped first. `wt/sky` has one commit beyond the merge.
- The police station night still is very dark (its shot script uses a lighter world without
  lamps). It needs a Forward+ look.
- The hillsides at night from the basin show the estate pads as round grey blobs (switchbacks
  and hill-homes). Worth a look from the air.
- Window lettering on shop glass reads as pseudo-letters ("TSHNEENA"). That is the building
  shader's procedural vinyl, older than this work.
- None of the 31 merged branches has been seen on the owner's Mac (Forward+). Every still was
  opengl3 or lavapipe.

### The fleet, and how to run one again

- **How it ran:**
  - Every session got the shared brief (`git show origin/fleet/brief:BRIEF.md`).
  - Each worked on `wt/<slug>`, put stills on an orphan `shots/<slug>` and wrote a HANDOFF
    section as `## 9b?.`.
  - The lead merged in batches in a scratch worktree with `tools/fleet/merge_branch.py`, which:
    - renumbers HANDOFF sections and roadmap rows;
    - keeps both sides of additive conflicts in the docs and the files it lists, and prints them;
    - stops on anything else.
  - Then it gated the whole batch once with `tools/fleet/headless_check_dir.sh` and
    fast-forwarded main.
- **Lessons:**
  - **Tell sessions to merge main, never rebase.** The brief says "rebase on origin/main before
    your final push", and two branches were rewritten after they had been merged. They then had
    to be cherry-picked by commit subject.
  - **Read every hunk merge_branch.py keeps.** Twice it kept both sides inside an if/elif chain,
    where the order matters (the oil field case above).
  - **Run one gate at a time** until integration-b's memory is fixed.
  - **Usage limits:** 50 sessions hit the five-hour usage limit at 06:31 UTC (it reset at 06:50)
    and showed weekly-limit warnings. Twenty sessions is a saner fleet.
  - **Check that a session pushed its code**, not just its stills. Four never pushed a branch.
- **Tools** in `tools/fleet/`:
  - `merge_branch.py`: set `FLEET_TRAILER` to your commit attribution.
  - `headless_check_dir.sh` (`PROJECT=` a worktree).
  - `gate_slot.sh`: one slot by default.
  - `fleet_status.py`: summarises a saved `list_sessions` dump.
  - `sheet.py`: review sheets.

| slug | where its work is | stills |
|---|---|---|
| beach-life, npc-polish, more-cars, night-city | main | shots/ |
| audio, hero-moves, port-life, canals, photo-mode, pier, marina, climbing-plants, building-damage, more-people, schools, minimap, weather, broadway, stack-interchange | integration-a | shots/ (audio: none) |
| explosions, police-station | integration-a (+1 follow-up each in -b; their branches were rebased) | shots/ |
| perf-audit | integration-a (tools) + 9 newer commits open | none |
| sky | integration-a + 1 open, follow-up requested | shots/ |
| construction, murals, signage, hospital, la-trees, car-dealers, airport-life, golf, dogs, hill-homes, oil-fields, vacant-lots | integration-b (not gated: OOM) | shots/ |
| street-life-2 | open, failing its own checks | none on remote |
| alleys, scooters, rooftops, ridges, stadium, service-vehicles, wilshire-deco, reservoir, web-build | open `wt/<slug>`, not reviewed | shots/ (web-build: none) |
| roadside, traffic-ai, driving-fx, freight-trains | no code branch pushed (only stills) | shots/ |
| skate-park | never started | - |

## 00000. The same day, continued (2026-09-28, the owner came back: "make the graphics a million times better")

Newest. Read this, then 0000 (which is still the full state as of the morning).

**Shipped from the lead's branch** (`wt/boost-fx`):
- **Boost trail** (`BoostTrail`, CLAUDE.md "The boost"): the solid cyan spheres are gone - a
  vapour contrail, a wake of mist off the body toward the camera, streaks of air, dust off the
  ground on a low pass, a vapour ring at take-off and at top speed. Knobs at the top of
  `scripts/player/boost_trail.gd` (`vapour_alpha`, `wake_alpha`, `streak_alpha`, `dust_reach`).
  Tools: `post_room_shot.gd MODE=boost` (test room, seconds), `still_shot.gd BOOST=fly`.
- **Weapon panel** (`WeaponHud`): the "[1] AK-47 [2] Rocket Launcher [3] Shotgun" text line is
  a glass pill with the gun's silhouette, name, infinity sign and slot chips.
- **The sun on the real LA path** (found by the hills agent): it rose SSE, stood ENE at noon 85
  degrees up and was due NORTH at 15:00, so the mountain faces the city looks at were backlit all
  afternoon. Now east - south at 56 degrees - west (`DayNight._arc_basis()`, `latitude_degrees`).
  Every shadow in every bookmark moved: midday shadows now fall north and are longer.

**Then, also from the lead** (each its own push, each passing the check):
- **Brass**: the AK throws a spent case every round (`BrassCasings`, one MultiMesh, simulated in
  GDScript, a tink on the bounce).
- **Pause menu**: frosted glass over the blurred frozen game, with TIME OF DAY presets, WEATHER
  (held or Auto; `Weather.force_state()`), GRAPHICS (held or Auto; `Quality.force_level()`), the
  seed, and a controls card. `post_room_shot.gd MODE=pause`.
- **Combat feedback**: hit markers on the crosshair (`Crosshair.mark_hit()`), red edges and a
  direction arc toward whoever shot you, a low-health heartbeat (`DamageHud`,
  `PlayerHealth.hit_taken`). `MODE=hurt`.
- **Superhero landings** (`LandingFX`): dust ring and camera kick from a jump, a crater and a
  shockwave that knocks people and props from a drop of ~30 m. `MODE=land`.
- **Bullet impact sounds by surface** (Sfx `hit_*`, Kenney's CC0 impacts) and a real brass tink.
- The ocean no longer swells up through the beach (blobs of water on the sand).
- Test-room modes on `post_room_shot.gd` (boost, fire, hurt, land, pause) render in a minute or
  two, against 5-25 minutes for a city still while the render lock is busy: prefer them for
  anything that does not need the city.

**Agents running in worktrees when this was written** (each reports back with before/after
stills; merge main into the branch in its worktree, check, fast-forward, push):
- `wt/crowd-garments`: our own tee / trousers / shirt / jacket for the crowd (the patch in
  `docs/wip/` continued).
- `wt/lot-fill-2`: no bare ground outside downtown/midtown (beach town, campus, freeway sides,
  the empty block south-east of MacArthur Park).
- `wt/hills-air`: the mountains from the air (the dark dashes were Skyline's far chaparral
  mounds; the far ground's colours were linearised twice on Forward+).
- `wt/car-glass`: see-through car windows with a traced cabin, and drivers in traffic.

## 0000. Handoff of 2026-09-28 (read after 00000, then 000 and 00)

The owner is moving to another account; this is where everything stands. **`main` is the whole
state** (32fdd30, build 313 in CI at the time of writing; builds 304-312 green). Nothing is left on
a branch that matters: every agent branch below was merged and its worktree deleted. The one
unfinished piece is a patch in `docs/wip/` (see "In flight").

**Shipped in the second half of 2026-09-27** (each has its own section below; the numbers are the
section, not the build):
- **Buildings in a handful of draws** (9ai): walls, facade detail and roof plant merged per
  building - downtown frame 5,815 -> 3,360 draws, same picture.
- **Road stripes gone**: the long "polished wheel track" strips drew as black (then tan) skid
  stripes down every avenue - the patch shader never matches the road's own tarmac. Removed;
  the braking polish at stop lines stays (`StreetDetail`).
- **Hill ground from standing height** (9ak): shell grass and a brush understory on the near
  hills, the splat shared by the terrain and the shells (`hill_splat.gdshaderinc`).
- **Hills without leopard spots** (000's last bullets; CLAUDE.md terrain note): the brush
  threshold is pushed off the noise mean by the land (steep faces brush, gentle ground grass),
  a 1.1 m octave rags the edges, every octave widens the edge as it fades, the tuft dirt and the
  stand edge are anti-aliased (no grid of squares from the air).
- **Crowd close-up** (9aj): face shapes, stubble / beards, brows in the hair colour, folds,
  per-person trouser dyes, no skin through shirts.
- **Motion blur and depth of field** (9al): a CompositorEffect on Forward+ only (off on the web
  and in stills), gentle far blur while aiming, strong blur behind the weapon wheel.
  Knobs on the player's `CameraRig/Post` (`motion_blur_strength`, `shutter`, `max_blur_px`).
- **MultiMesh batches write one buffer** that the shadow twin shares (no GPU read-back; the
  headless check lost 6,500 error lines).
- **Lots filled, not paved** (9am): podiums (parking decks, retail), forecourts, lawns, pools,
  surface car parks; downtown bare lot ground 44 % -> 2 %, midtown 54 % -> 5 %.
- **Car damage** (9an): `Vehicle.take_hit()` from every gun, blast and crash; bullet holes,
  dents, crazed and shattered glass with a traced cabin behind, broken lamps, smoke, fire
  (the explosion's `fire_puff` shader, spreading to the cabin), explosion, burnt wreck.
  Knobs in `scripts/vehicles/car_damage.gd`.
- **Street-level facades with depth** (9ao): `ShopfrontKit` - real shop frames and doors, pier
  cladding, awnings, lit blade signs, glass posters, recessed entries, curtain-wall caps, thin
  real window frames above.

**Landed (9av):** our own garments for the crowd (tee, trousers / jeans / slim / chinos / leggings
/ shorts, button shirt, zip jacket), modelled by `tools/crowd/garments.py` and painted by
`tools/crowd/garment_paint.py`; eight of the twelve people wear them. The patch that carried them
(`docs/wip/crowd-garments.patch`) is gone.

**Landed (9az):** no bare ground outside downtown and midtown either - `YardFill` gives
beach-town lots yards and walk streets, campus blocks quads, walks and service yards, and the
freeway's right of way ivy, hedges, tree rows, sound walls and maintenance yards; beach town
56 % bare -> 4 %, campus 74 % -> 1 %.

**Needs the owner's eyes on the Mac (Forward+)** - none of this can be judged in the opengl3
stills: the motion blur's strength and the aim / wheel depth of field; car fire and smoke at night;
the crowd's skin subsurface and wet eyes; the parking decks' exposure and the car parks'
chain-link dither; the hills' colours from the air; the storefronts' metal frames and glass
decals. Ask for screenshots with the HUD's FULL mode (F1) so the frame-time line is in them.

**Known and left alone:**
- `Explosion.blast()` shoves a car once per collision shape, so rockets throw cars 2-3x harder
  than `launch_speed` says. That is feel, not a bug; change it only if the owner asks.
- The SUPER body's wheel arches render empty in `car_shot.gd` (seen by the car-damage pass).
- Beach town blocks (~67 % bare ground) and campus blocks were left out of the lot fill (filled
  since: 9az, YardFill).
- Retail podium roofs have no mechanical plant; crowd_j still shows a small sliver of skin at
  the shirt front; the lot fill's cheap code car is plain up close.

**How this session worked** (it keeps paying off; the traps are the expensive part):
- The lead worked on a local branch `mountains` in `/home/user/rando-game` and pushed
  `mountains:main` after every green check (owner: "push to main always"). Each big job was a
  background agent in its own worktree (`git worktree add /home/user/wt/<slug> -b wt/<slug>
  mountains`, plus a copy of `.godot`), committing only there; the lead reviewed the screenshots,
  merged main INTO the agent's branch in its worktree (resolving conflicts there), ran the check
  there, then fast-forwarded `mountains` and pushed.
- **Agents all number their HANDOFF section "the next free one"**, so two or three branches
  arrive claiming the same `9a?`. Renumber on merge (this session: 9ai twice, 9aj three times).
- **Re-import after every merge that adds a `class_name`** (`godot --headless --path . --import`)
  before any still in that checkout, or the city renders as a bare plane with floating cars and
  people ("Parse Error: Identifier ... not declared"). CI always imports, so builds are fine -
  it cost one false alarm this session. The same goes for a fresh worktree.
- **A container restart kills every background process and agent** (it happened once); files
  survive, uncommitted work survives only on disk. Agents now commit in small steps; resume one
  by messaging it with where its worktree stands.
- Renders: one opengl3 still at a time under `flock -o /tmp/rando_render_gl.lock`; NEVER a
  lavapipe (Forward+) render of the city (OOM at ~12 GB), only small scenes; NEVER `pkill` by
  name (other agents run the same binaries). Four cores, so two or three agents at once is the
  practical limit. Each worktree with its `.godot` is ~1.3-1.5 GB; the disk hit 94 % once.
- Quick loops that beat renders: `tools/lot_coverage.gd` (bare ground per district, headless),
  `tools/glshot/hill_ground_shot.tscn` (hill chunks alone, a minute a shot), a CPU top-down of
  `HillPlanting.ground()` for the brush pattern (seconds), `car_shot.gd DAMAGE=...`,
  `tools/glshot/post_room_shot.gd` / `motion_blur_shot.gd` (lavapipe, small scenes),
  `still_shot.gd DIFF=1` + `tools/glshot/img_diff.py` for pixel A/Bs.

**Next, in order:** finish the crowd garments (the patch); fill the beach town and campus
blocks the way the lot fill did downtown; get Mac screenshots and tune the Forward+-only looks
listed above; then the roadmap's open rows (#14 interiors behind street glass, #20 front range
roads and estates).

## 000. Session of 2026-09-27 (read after 0000, then 00)

One orchestrating session plus a local agent and six cloud sessions (one machine each, a
`wt/<slug>` branch each, screenshots on orphan `shots/<slug>` branches). Everything below was
merged into one branch and gated together (499 checks) before the push:
- **Mountains pass 1** (9ab): erosion-noise ranges, B-spline far heights (the contour stripes
  are gone), lit hill detail, far ground at 44 m. Open: the far ground is painted darker than
  the near hill tiles - needs a Mac screenshot from the air (`--spawn=700,-300,0,-14,500`).
- **Palms' LOD ladder** (9aa): -7..-23 % triangles at the bookmarks, same draws.
- **Crowd animation** (wt/crowd-anim): stride-matched gait, eased starts/stops, pivots, head
  look. +~0.5 ms a physics tick for a near crowd.
- **Wet streets** (9za): puddles mirror the lit city at night, rain rings, patchy drying, tyre
  spray. Dry weather costs what it did.
- **Headlight beams** now lie on the road (they were 0.6 m under it on every car) and model
  cars' collision fits the body - ported from wt/sedan-body WITHOUT its new sedan body, which
  still read dated; that branch stays parked.
- **Street wear** (9ac): original generated tags, posters, stickers, wall grime, gum (the gum
  reworked: it read as drilled holes). The per-chunk cap now holds in `_put_basis()`.
- **Encampments x20** (9ae, owner ask #2): skid row ~340 people (was 8), 3,637 camp pieces;
  cart pushers ported onto the new crowd gait (`RoughSleeper._animate_gait()`).
- **Downtown 1:1 re-lay, port on San Pedro Bay, freeways clear of buildings, arena district**
  (9ad, owner ask #3): the embayment shift now lives in `MacroMap._range_heights_at()` so it
  applies under the erosion. Arena district +9-18 % triangles there.
- **Later the same day** (local, after the merge): the erosion no longer pinches every summit
  into a star (`_erode()` amplitude goes to zero with the base slope, each finer order fades
  where the coarser walls cancel the slope; same in `erosion.gdshaderinc`). The far ground's
  dark shell over the near hill tiles was traced with debug renders in a separate worktree
  (`HIDE=Ground`, the plane's and the tiles' albedo / normals / coverage emitted as colour):
  see 9ab's follow-up note for what it turned out to be.
- **Pushed to main after the owner's "push to main always"** (builds 294-300): the far-ground seam
  fix (the plane's SPECULAR 0.15 lost Godot's grazing sky sheen; it now matches the tiles where
  the renderer lights it, and draws their stands), a third erosion order in the heights, trees and
  palms kept off freeway decks, ivy on freeway corridor lots, furnished plazas, airport long-term
  parking under the approach, the road shader mapping vertical faces side-on (the Esplanade's
  seat wall was vertical streaks), the tree LOD ladders (agent, wt/tree-lod-2: -23..-38 % tree
  triangles, crowns back on 60-200 m street trees) and new loft-and-subdivide car bodies (agent,
  wt/cars-aaa: sedan, a new crossover body type, pickup; every traffic car sat 15-27 cm above the
  road until `Vehicle.road_lift()`). Forward+ (lavapipe) city stills are killed by the box's
  memory at 12 GB even with `LIGHT_WORLD=1`; use opengl3 stills and ask the owner for Mac shots.
  Stale class cache trap: after merging a branch that adds a `class_name`, run `--import` before
  any still, or the city renders as a bare plane (Parse Error: Identifier not declared).
- **Hill ground merged, then the leopard spots** (build 305 pushed the hill-ground branch: shell
  grass and brush understory up close). The brush stands still read as round tan-and-olive
  camouflage from 100-500 m. A red/blue debug render (grass red, brush blue; then the fades and
  the threshold as colour) showed it was the stand noise itself - the 3 m bush octave is
  resolved out to ~500 m, and a thresholded 3 m value noise is round blobs - on ground where the
  threshold sat at the noise's mean. Fixed by moving the threshold off the mean with the land
  (brush-dominant steep faces, grass on every gentle bench) and ragging edges with a 1.1 m
  octave; each octave widens the edge as it fades (CLAUDE.md, terrain note). A CPU top-down of
  `HillPlanting.ground()` (near and "far" mode) made the loop seconds instead of renders; the
  script is in the session scratchpad, not the repo. Before/after: hills 150 m out and at ground
  level, EYE=-400,70,-1380,0,-12 / -250,2,-1560,-30,4 on `hill_ground_shot.tscn`.
Tools added: `tools/terrain_preview/` (mountains top-down in seconds), still_shot `HIDE=`.
Cloud sessions cannot be messaged back; read their state with get_session and their shots
branches. Pushes were blocked by the auto-mode safety check until the owner said to push.

## 000d. Pickup reworked, van rebuilt (2026-09-27, branch `wt/cars-aaa`, after the 000c merge)

The lead's follow-up to 000c. Both in `tools/make_road_cars.py` (`-- pickup van`).
- **Pickup proportions.** The merged pickup read as a low rounded sedan greenhouse on a long body
  with a flat box for a face. Now: roof 1.98 m, belt 1.38 m, a near-vertical cab back and a
  square roof edge; a flat bonnet 1.30 m high at the front, its edge and the bed rails creased
  into ONE horizontal line with the belt; an upright face with the lamps set into the top
  corners of a big grille surround, a satin crossbar and slats; wrap-round chrome bumpers; a
  1.71 m bed with squared rails. 5.9 m between the end stations (6.08 m over the bumpers).
- **Why the first cab looked like a sedan's**: `station_list()` let every extra station clear
  its neighbours within 0.3 of the mid step, so of a cluster of stations placed round the cab
  back only the LAST survived and subdivision rolled the corner off over 0.3 m. Fixed (extras
  never clear each other); the sedan and the crossover are unchanged by it (same triangles),
  their extras were far apart. Corners in the side profile now get holding stations and
  `station_creases`.
- **road_van** (5.94 m, 2.03 m, 2.55 m) replaces `car_van` (the last Meshy road body; its grille
  also carried a badge-like shape). A ninth section anchor (the flat roof's edge) with pinned
  tangents gives flat sides and a tight roof edge; short sloped bonnet, steep screen running on
  up a raked roof fairing, sliding door + track on the kerb side (+x), barn doors with hinges,
  tall corner tail lamps, black wrap-round bumpers and rubbing strips, glass only at the cab
  (a real glass slot, so `GEO_GLASS_BELTLINE` / `GEO_GLASS_SPAN` are empty now). `BodyType.VAN`
  keeps its slot and odds; its physics wheels sit under its own axles (`wheel_front` /
  `wheel_rear`, 3.66 m wheelbase), and the police tactical van's light bar moved from
  `-length * 0.28` (over the new screen, where it floated - it floated on the Meshy van too) to
  `-length * 0.17`, on the flat roof.
- **`road` vs `ride`** in `Vehicle._dims()`: `road` is the measured wheel contact (what traffic
  stands cars on), `ride` the model's bottom = road + the far twin's 2 cm tyre gap. With the two
  equal (000c) every road_* body sat 2 cm low against its generated wheels.
- **Silent part drops**: end-view parts whose rays missed (the first pickup's bumpers and valance
  never existed; the van's tail lamps smeared a red streak down the flank) are now dropped AND
  logged; bumpers are `wrap_band()`.
- Numbers: pickup 55.8k triangles, van 51.1k, each + a 7.9k far twin. geo_count at the avenue
  (`--spawn=2359.4,880,0,12,2`, opengl3 800x600, `AB=BodyModel`): 3.92 M tris / 4,167 draws on
  the merge (fe72497) -> 3.87 M / 4,178; the car bodies' own share 266k / 219 -> 213k / 230.
  505 checks pass.

## 000c. Everyday car bodies (2026-09-27, branch `wt/cars-aaa`, VISUAL_ROADMAP #22)

The owner wants "AAA studio PS5 quality"; the Meshy sedan / pickup were crumpled remeshes and the
Blender sedan on `wt/sedan-body` read as a boxy 1980s car. New: `tools/make_road_cars.py`
(Blender 4.2 headless, `tools/road_cars_setup.sh` fetches it into `build/car_src/`), three
original bodies: `road_sedan.glb` (4.95 m fastback, replaces `car_sedan`, also the police
cruiser: `PoliceCar.DOOR_BAND` now 0.300-0.707), `road_crossover.glb` (4.63 m, NEW
`BodyType.CROSSOVER`, appended so no index moves, 220 of `BODY_ODDS`' 1000 - the commonest car in
LA) and `road_pickup.glb` (5.85 m crew cab, replaces `car_pickup`). `car_sedan.glb` /
`car_pickup.glb` are unreferenced now but still in the tree (delete if the new ones stay).
- **Method** (what the last attempt got wrong): the shape is profile curves - a side view
  (roofline, the rail/pillar line, belt, shoulder, sill, floor), a plan view (width) and a few
  insets - lofted through eight-anchor sections into a quad cage, level-2 subdivision, creased
  shoulder; everything else is booleans after subdivision (arches, windows, lamp pockets,
  grilles, 4 mm panel gaps) plus raycast-placed parts. Proportions came from moving the cowl to
  0.48 m behind the front axle (it started 0.70 m: a long RWD bonnet), a fastback deck of 0.4 m
  (a 0.76 m deck read as a notchback), a lower nose and a plan-tapered tail. Cycles previews:
  `--render` (studio gradient, far wheels borrowed for the stance).
- **Budget**: 50-53k triangles per full model (seven slots, importer LODs) and an ~8k far twin
  with two surfaces (paint + vertex-coloured parts) drawn past `Vehicle.body_far_distance`
  (30 m). geo_count at the avenue (`--spawn=2359.4,880,0,12,2`, opengl3 800x600, `AB=BodyModel`):
  4.23 M tris / 4,059 draws before, 4.06 M / 4,167 after; the car bodies' own share 458k / 127
  draws -> 267k / 219. The gap cuts were the expensive part (10.6k triangles at 2 cm steps with a
  box profile; 4 cm steps now).
- **Traffic floated** (found on the way, fixed): street traffic placed every body 0.55 m over the
  relief (0.45 m over the road top), the replica lanes 0.55 m over the road, freeway cars 0.71 m
  over the deck - whatever the body. A parked physics car rests with its origin 0.17-0.30 m over
  the road, so every traffic car's tyres hung 15-27 cm clear of the asphalt (freeway ~0.5 m).
  Now `Vehicle.road_lift()` (= -`ride`, measured: `car_shot.gd` prints CONTACT) at every
  placement; `tests/street_life_checks.gd` checks it. `ride` values for the new bodies are the
  measured contacts (sedan -0.177, crossover -0.196, pickup -0.206).
- Booleans are guarded (a result that loses most of the mesh is rolled back and logged) and
  panel gaps go one strip at a time with the hole-tolerant solver: a union of all strips once
  deleted a whole body, and V-profile gaps meeting edge on edge left it open for every later cut.
- Shots: `tools/glshot/car_shot.gd --each=0,8,1 --views=front3,rear3,side,close,far` (one lock
  wait for a whole set; `--police`, `--night`). Honest verdicts are in the branch report; the
  crossover's and pickup's faces are the weakest parts (plain egg-crate grilles).

## 00. START HERE - handoff to the next account (2026-09-25, newest)

The owner ended work on the previous account on 2026-09-25 and asked for this handoff. Read
this section, then CLAUDE.md (the rulebook), VISUAL_ROADMAP.md (ranked backlog) and
LOOP_LOG.md (what was tried, merged or reverted, with numbers), then the dated sections below.

**The owner and how they work.** Ash plays on a Mac from the GitHub release
(https://github.com/ashalluf/rando-game/releases/latest) and prompts from a phone. Rules that
matter most: push straight to `main` (no PRs); run `tests/headless_check.sh` before every push
and confirm the CI build goes green; **send screenshots constantly** - every change, before and
after, without being asked (the owner's most repeated request: "SCREENSHOTS"); keep messages
short; work fast and in parallel. The north star is 2026 PS5-tier photorealism (GTA VI /
Spider-Man 2 street level) at 60 fps on the Mac, 30 fps floor. Masjid Omar ibn Al-Khattab keeps
its no-fire sanctuary and is always treated respectfully. Real place layouts are fine; real
business names and logos are not.

**State of main.** Green (CI build 290, 72b1247; 291 is docs only). Merged this session:
MacArthur Park on; road patch decals; street clutter; golden-hour LA smog; hill ground splat;
hill road cut banks; hill planting; floating hill props fix (relief added twice); texture
mipmaps; smoothed car normals; perf pass (static boxes merged); pedestrian middle body;
night shopfronts and neon; several CI fixes (traffic U-turn overlap, flaky blood-pool,
shotgun and police checks).

**The owner's open asks, in priority order** (all started, none on main yet):
1. **The hills "look like garbage, not real mountains".** Branch `wt/real-mountains`
   (1 WIP commit, NOT gated): ridged heightfield with canyons, rounded summits, far-range
   contour banding fixed (float height bake), chaparral-dominant grey-olive palette. Last
   render: `hills_02_rounder_chaparral`. Next: finish, run the full check (hill checks: cut
   banks, floating props, planting field), before/after at the hills bookmark and from the
   basin, merge.
2. **Downtown needs ~20x more homeless encampments** ("whatever you think it should be,
   multiply by 20"). Branch `wt/downtown-homeless`: DONE and gated 2026-09-27, ready to merge
   (section 9za): skid-row band, 20x the people as batched static figures, cart pushers.
   Depict with dignity; never near places of worship; use the pedestrian middle body and
   batched static figures to keep the frame cost sane.
3. **San Pedro port must be on the east side of Palos Verdes, not in the middle of the city**
   and **no freeway may go through buildings.** Branch `wt/downtown-relay` (15 commits): the
   downtown 1:1 re-lay itself is done and was gated green on the branch (up to 0aa7731); on top,
   WIP (NOT gated): the port and harbour moved onto San Pedro Bay east of the peninsula (inland
   harbour removed) and the 110 clear of every building, plus a started smoke check. Still to
   do: finish and gate those, fill the empty paved plazas around the arena district (civic
   sites' blocks grew at 1:1 and are mostly bare), merge main in, run the full check, merge.
   The port's containers and cranes are still primitive boxes (roadmap #35).

**Other parked branches** (pushed; merge one at a time after a full check, or delete):
`wt/sedan-body` (Blender-built hi-fi sedan, gated at 97274c0; WIP styling pass - the first
shape read dated; also fixes the headlight beam below the road and the cabin collision box
above the roof), `wt/tree-lod` (palm LOD ladder: -7 to -23 % frame triangles, gated 2026-09-27, see 9aa),
`wt/wet-streets` (streets that dry believably), `wt/street-wear` (graffiti/posters). All WIP,
never gated. `wt/vehicle-grime` and `wt/wall-weathering` were judged not clearly better.

**The autonomous loop** (optional). The owner ran an orchestrator loop: parallel agents in git
worktrees (`/home/user/wt/<slug>`, branches `wt/<slug>`), each owning one roadmap item, merged
to main one at a time after a full check and screenshot review. A Stop hook
(`.claude/hooks/keep-going.sh` + `.claude/settings.json`, blocking stops unless a `STOP` file
exists in the repo root) kept it going. Those files were never committed, so a fresh clone
does not have them; recreate them only if the owner asks for the loop again (the brief is in
the owner's original orchestrator prompt, and the wave protocol is at the top of
VISUAL_ROADMAP.md). Agents dropped every render into a shared scratch `screens/` folder that the
orchestrator forwarded to the owner.

How the box copes (4 cores, 16 GB, one 14.3 GB memory cgroup shared by every agent):
- `tools/glshot/bookmarks.sh <dir> [names]` renders the seven fixed cameras (downtown noon,
  downtown night + rain, hills, freeway, masjid, esplanade sunset, hero). The hills camera is
  `--spawn=300,-650,0,-6,260` (the old one was too far to show the hill ground).
- Locks: opengl3 renders `flock -o /tmp/rando_render_gl.lock`, lavapipe renders
  `flock -o /tmp/rando_render.lock`, headless checks `flock /tmp/rando_test.lock`. Use `-o`:
  plain flock hands the locked fd to the Xvfb that xvfb-run starts, and an orphaned Xvfb then
  holds the lock with nothing rendering.
- A full-city Forward+ (lavapipe) render needs ~13.9 GB and is OOM-killed here once anything
  else runs; judge Forward+ looks on small stand-in scenes or on the owner's Mac.
- Cap every Godot log with `| tail -c ...`: one runaway geo_count log reached 7.5 GB and
  filled the disk (geo_count's AB= mode sets time_scale 0 and spams "must be finite" warnings
  from player.gd:173).
- Test traps found by the loop: re-centre the origin only inside the physics tick (tests await
  `physics_frame` first; CityStreamer.recenter() says why), and the seed-rebuild check puts
  `WorldState.world_offset` back after its second city - both used to throw traffic and far
  chunks hundreds of metres.

## 00a. Crowd animation (2026-09-27, branch `wt/crowd-anim`, VISUAL_ROADMAP #28)

What changed in `Pedestrian` (scripts/npc/pedestrian.gd; the knobs are the "Locomotion" and
"Head look" export groups):
- **The clips' real ground speeds were measured** (`tools/crowd/clip_probe.tscn`: how fast a
  planted foot travels under the in-place clip). The walk is ~0.75 m/s at speed_scale 1 (3
  strides in its 4.2 s), the run ~2.75; the code assumed 1.3 and 5.0 and multiplied the cadence
  by a random `_gait`, so every walker's feet slid at ~0.76 m/s. Now `WALK_CLIP_SPEED` 0.8 (the
  slide minimum in the lab), `RUN_CLIP_SPEED` 2.75, the rate is speed / (clip speed x the
  build's depth scale), and `_gait` only varies the idle. Walk paces are 1.05-1.5 m/s (the
  clip's step is 0.5 m; 2.6 m/s would be four steps a second), the panic run 4.4 +-12 %.
- **Speed is eased** (`_speed`, `walk_accel` / `stop_decel` / `run_accel`) and the body only moves
  the way it FACES (`_steer()`: capped `turn_rate`, slower into bends); a turn over
  `pivot_angle` from below `pivot_speed` is stepped round on the spot (`_pivoting`, walk clip at
  `pivot_cadence`). Pauses are rolled a leg ahead (`_pause_next`) so walkers slow into them;
  kerb waits turn on the spot (`_turn_on_spot()`).
- **The clip follows the speed** (`_animate_gait()` / `_set_clip()`): idle, walk, run with
  hysteresis and cross-fades; walk<->run keeps the same foot (`WALK_LEFT_DOWN`, `RUN_LEFT_DOWN`,
  `WALK_CYCLES`), a walk starts on a footfall. Past lod_mid swaps cut instead of fading.
  `_play_walk()` / `_play_run()` are gone; `_play_idle()` stands someone still (staging).
- **Heads look** (`_post_pose()`, people within `look_range` 26 m only, i.e. strides 1-2): after
  the clip poses the rig, neck (40 %) and head (60 %) turn to a gunshot/blast (`_scare()` sets
  `_look_threat` for `look_threat_seconds`), else a car passing within `look_car_range`
  (`_nearby_cars()`, one shared survey of the `vehicle` group every 15 ticks), else the player
  within `look_player_range`. Same place scales the arm swing per person about the clip mean
  (`arm_swing_spread`) and tips `head_down_share` of people's heads down. `RoughSleeper` opts out
  (`_head_look_ok()`), officers use Avatar and never reach it.
- Far updates are de-synchronised (`_lod_tick` starts at a random phase), so a crowd spawned
  together no longer spikes one tick in eight.
- Checks: `tests/crowd_anim_checks.gd` (start, rate match, about-turn pivot, no sideways
  motion, idle, head turn). The panic check waits 30 ticks (people now accelerate).
- Lab: `tools/crowd/crowd_lab.tscn` - MODE=film SCENARIO=turn|start|look|crowd (opengl3 frames),
  MODE=bench (CPU per physics tick; note Performance.TIME_PHYSICS_PROCESS is the WORST tick of
  the last second, not a mean - the lab times the tick itself), MODE=skate (planted-foot slide).
- Cost (median of 3, ms per physics tick per 100 people): near 2.98 -> 3.90, 50 m 1.02 -> 1.09,
  100 m 0.64 -> 0.74, 200 m 0.40 -> 0.49. The near cost is mostly the head/arm pass (~6 us a
  person) and steering. Not done: the player's Avatar still uses 1.3 / 5.0 (the player moves at
  12 m/s, outside any human gait); no foot IK on slopes or kerbs.
- CLAUDE.md's NPC note still describes the old `_gait` cadence spread; update it when merging.

## 0. Start here (wrap-up of 2026-09-24, the newest state)

Read this section first, then CLAUDE.md, docs/GAME_PLAN.md and the dated sections below. The
day's work is in 9z (hill planting, 2026-09-25), 9t (distance), 9s (1:1 downtown, landed 2026-09-25), 9r (MacArthur Park, encampments),
9q (street life), 9p (the Esplanade), 9o (civic set), 9n (skyline), 9m (sound), 9l (how the
day ran), 9j (blood), 9i (facade kit), 9h (police), 9k (sky), 9g (guns). This section is the
index.

**Main at wrap-up** is green on CI; the release page has the newest build. Merged on
2026-09-24 (about 100 commits): window recesses; the Blender-built hero with real finger bones
in a black tracksuit, chain and watch; the weapon wheel (slow motion, glass UI); Blender-built
AK, rocket launcher and pump shotgun (the gravity gun is gone), a rocket that flies as its
warhead with a smoke trail; heavier gunshot blood (sprays, splats, pools, stained clothes);
police and wanted stars (cruisers, officers, roadblocks, a health bar, "OUT COLD");
air traffic (airliners landing and taking off at the airport, private jets, news and police
helicopters with a searchlight); the facade kit (real mouldings, fire escapes, awnings); a
layered city soundscape; a lens pass (grain, fringing); darker nights with the night GI turned
down; the downtown skyline (19 towers at real heights and silhouettes, one table,
`LandmarkDowntown.TOWERS`); and the civic set (arena district, entertainment plaza, hotel,
convention centre, city hall and park, concert hall, museum, station; one table,
`CivicSites.SITES`). Both tables carry approximate real positions for the 1:1 re-lay.

**The owner's direction** (2026-09-24, in their words): "AAA studio quality ... like a real 2026
released game", RDR2-level; "picking certain 1:1 replica areas and then filling them in between
with whatever" - downtown LA as a whole at 1:1, the Redondo Beach Esplanade curving up into
Palos Verdes at 1:1 street and view ("geographically sound, like south of LAX"; the owner's
three Street View references are described in the Esplanade section), MacArthur Park and
encampments on downtown streets, and "certain areas of the map aren't loading at a distance -
do whatever GTA does". Always send screenshots. No commercial-readiness audit for now.

**In flight at wrap-up** (agent branches; what happened to each is recorded here):

All six agent branches came back at wrap-up. Five are merged to main; one is kept on a
branch. (Four agents each wrote a "9p"; the sections were renumbered at merge, so a "see 9p"
inside one of them means its own section - the headers below are the authority.)

- **Merged: the Redondo Esplanade into Palos Verdes, 1:1** (section 9p). 4.57 km at true scale,
  one data table (`scripts/world/replica_areas.gd`), its own builders, traffic and walkers;
  `-- --no-replica` turns it off. The first preview stills were taken at wrap-up (they read as
  the owner's Street View captures); nothing on Forward+, frame cost not measured.
- **Merged: street life** (9q). Blender-built traffic signals on a shared clock, pedestrians on
  the walking figure, cars queueing at red and yielding, police routed by road to the kerb.
  At merge the police helicopter's sighting ray was made to look past `StreetProps` (the new
  signal mast arms hid the player at the spawn junction - the one failing check on the branch).
- **Merged: MacArthur Park and street encampments** (9r). The encampments are ON (downtown
  building blocks only, knockable pieces, rough sleepers who breathe, cower and ragdoll). The
  park is built but OFF (`LandmarkMacArthurPark.enabled`, a static var) until a traffic leak onto
  its closed roads is found. At merge its closed-road turning rules were ported into street
  life's new car-following model in `traffic.gd` (a closed road ahead forces a turn, or a U-turn
  at a dead end: `t.turn == 2`) - untested with the park on.
- **Landed: downtown at 1:1** (9s, 2026-09-25). The re-lay in `tools/downtown_relay/relay.patch`
  was ported by hand onto main (MacArthur Park on, the masjid, the Esplanade, the distance tiers)
  and gated: the real street grid pinned on every seed, the towers and civic buildings on their
  geocoded points, the 110 / 101 / 10 on their real lines, the park on its real streets, the
  masjid moved south to where the real one is relative to downtown. 9s has what moved.
- **Merged: the distance** (9t). Four tiers that always cover the view to 12 km: near chunks,
  far chunks, the far city (every block within 7 km, recorded from the far chunk's own build)
  and the horizon plane; per-block dissolve handoff. At merge the far-city capture was made to
  skip replica and landmark-site blocks, which never build the seeded block.
- **Merged since (2026-09-24 evening): the AAA pass on the hero** (section 9u). The collar
  shards were holes in the skin, not the collar: the neck hole is now bounded by a ring round the
  neck that decides the jacket, its cut and the hidden skin together (tools/hero/tracksuit.py).
  `hero_shot.gd` has the four measurements that found it (STRETCH, CLEAR_SURF, SURF_COLORS,
  SURF_HIDE). Landing it exposed a real car bug, also fixed: a car went into flight - which banks
  with the stick - on any single tick with all four wheels unloaded, so a hard turn at speed
  banked it on a flat road (`Vehicle.flight_grace`, 0.18 s).
- **Merged since: Masjid Omar ibn Al-Khattab** (section 9v), a replica of the real building with
  an interior, replacing Masjid Al Noor; and the sanctuary rule - no gun fires at it.

**How the box was run** (9l has the detail): agents in git worktrees under
`.claude/worktrees/`, one branch each, merged by the main session after its own headless check;
Forward+ renders serialised on `<scratchpad>/render.lock` and started only with 8 GB free, GL
jobs on `gl2.lock`, full smoke tests two at a time through `<scratchpad>/gate_slot.sh`. A fresh
container has none of that: the scratchpad scripts are gone, recreate what you need (they are
three lines each, described in 9l). The Godot binary is a fresh download (section 5).

**Next, in order:** see section 10 (rewritten at this wrap-up).

## 1. What this is, in one paragraph

A 3D open-world chaos sandbox in Godot 4.7.2 (GDScript, Forward+ on desktop, Compatibility on the
web). Overpowered player (super jumps, unlimited boost, no fall damage), unlimited guns, an endless
seeded city with a west-coast layout (ocean, beach, pier, hills with a big sign, downtown skyline,
campus, airport, port, a peninsula in a bay), drivable cars, flyable jets, pedestrians that
ragdoll, traffic, day/night, a real sky. Everything original: no real names, logos or maps.

## 2. The owner and how they work (this decides everything)

- Prompts from a phone, usually cannot open the Godot editor. Everything must be doable by editing
  text files. Never leave a step that needs a click in the editor.
- Plays two ways: the macOS app from GitHub Releases (https://github.com/ashalluf/rando-game/releases/latest,
  first launch needs "Open Anyway" in Privacy & Security) and the browser build at
  https://ashalluf.github.io/rando-game/ (GitHub Pages, deployed by the same workflow).
- **Push straight to `main`. No branches, no pull requests.** Their explicit decision. Small pushes
  with "How to test" in the commit body and in the chat reply, plus the tunable values most likely
  to need changing. End every push report with the build number (`build-N`, the release tag).
- Standing rules they gave: **high-poly and realistic, never a low-poly look** (2026-09-19, they
  are aiming at consoles); **no more Meshy, Poly Haven only** (2026-09-19: "your Meshy assets
  suck, you can't color them properly"); the rifle is an AK-47; boost replaced sprint; **every Meshy prompt
  asks for the most ultra-realistic result possible**; they want more NPCs, a GTA-5-like skyline,
  a gorgeous sky, hills with roads and estates, a campus, a peninsula in the ocean, a bigger
  airport with flyable jets (all delivered in builds 46 to 51, see section 6).
- They report feel problems in plain words ("jump feels floaty", "can't turn"). Fix by tuning the
  `@export` values at the top of the relevant script and say exactly what changed.
- Tone of replies they like: short, direct, no fluff, tell them what to try. **Always attach
  screenshots in the chat** (owner, 2026-09-19: "so I don't need to do a git fetch every time").

## 3. Repository map

```
project.godot            main scene scenes/levels/city.tscn; autoloads; input map; shader globals
CLAUDE.md                rules and conventions (read first)
docs/GAME_PLAN.md        roadmap, queued requests, current state, decisions log (newest on top)
docs/ASSETS.md           every external asset with source, license, credits spent
docs/HANDOFF.md          this file
scenes/levels/city.tscn  the game: CityStreamer root, WorldEnvironment (sky shader), Sun, Player, DayNight, HUD, pause
scenes/levels/test_box.tscn  greybox test room used by the smoke test
scenes/player/player.tscn    CharacterBody3D + camera rig + weapon mount
scenes/ui/               debug_hud (stats, hints, crosshair, round minimap), pause_menu (Esc, seed)
scripts/player/          player.gd (movement, boost, jumps, vehicles, fall recovery), camera_rig.gd
scripts/weapons/         weapon.gd base, assault_rifle, rocket_launcher, rocket, explosion, shotgun, weapon_fx, weapon_manager (models: assets/models/weapon_*.glb from tools/make_weapons.py)
scripts/world/           city_streamer, city_chunk, city_plan, macro_map, hill_roads, landmarks, building, prop_factory (primitives + model_* merged Poly Haven models), street_props, trash_can, physics_prop, day_night, ferris_wheel
scripts/vehicles/        vehicle.gd (cars), aircraft.gd (jets)
scripts/npc/             pedestrian.gd, ragdoll.gd, traffic.gd, police*.gd, street_route.gd (the police's street routes)
scripts/util/            physics_budget.gd, world_state.gd, sfx.gd (autoloads; sfx.gd also builds the audio buses), ambience.gd (the city's sound, a node in city.tscn)
scripts/ui/              debug_hud, minimap, minimap_frame, minimap_border, crosshair
shaders/                 building, grass, terrain, sky
assets/textures/         CC0 PBR sets from ambientCG (1K JPG)
assets/models/           Meshy .glb models, their .json manifests, extracted textures, .import files, thumbs/
tools/meshy.py           Meshy API pipeline (generate, texture, rig, animate, download)
tools/ambience_audio.py  Freesound CC0 search / verify / fetch and the ambience clip cutter (section 9m)
tools/shrink_glb.py      shrinks embedded textures to 1K JPEG, --desaturate for car paint
tools/smooth_normals.py  re-smooths a .glb's normals by angle (45 deg) and welds; run on the Meshy car bodies
tools/pack_gltf.py       packs a Poly Haven .gltf + .bin + textures into one .glb
tools/decimate_tree.py   reduces Poly Haven trees, bushes and rocks to game size (needs pymeshlab: pip install pymeshlab, apt-get install libopengl0)
tools/webshot/           Playwright screenshot harness for the web build (see section 5)
tests/                   headless_check.sh + smoke_test.tscn/.gd (126 checks)
.github/workflows/godot-check.yml  CI: check, export macOS + web, publish release, deploy Pages
export_presets.cfg       macOS and Web presets (no credentials)
```

## 4. The loop for every change

1. Edit text files. Keep feel numbers as `@export` with a `##` comment.
2. Run the headless check (about 4 minutes):
   ```
   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 tests/headless_check.sh
   ```
   It imports the project and runs `tests/smoke_test.tscn`. It fails on any script error, parse
   error or NaN. Never push red.
3. Optional but recommended for visual work: export the web build and screenshot it (section 5).
4. Update `docs/GAME_PLAN.md` (decisions log entry, newest on top) and `CLAUDE.md` if a convention
   changed. Update `docs/ASSETS.md` for any asset.
5. Commit with a short imperative subject and a body that says why and how to test. Push to
   `main`. The remote also has a mirror branch `claude/new-session-gm161g` that earlier sessions
   force-pushed to keep in sync; it is not needed and can be ignored or deleted.
6. Wait for the workflow (about 2 to 4 minutes). It publishes `build-N`. Tell the owner the number.
   Check it really passed; CI run 46 failed once on a physics-flaky check, fixed in build 50.

## 5. Setting up a fresh session (nothing is preinstalled anywhere)

```
# Godot headless (Linux) and export templates
curl -sSL -o godot.zip "https://downloads.godotengine.org/?version=4.7.2&flavor=stable&slug=linux.x86_64.zip"
unzip -q godot.zip && chmod +x Godot_v4.7.2-stable_linux.x86_64
curl -sSL -o templates.tpz "https://downloads.godotengine.org/?version=4.7.2&flavor=stable&slug=export_templates.tpz"
mkdir -p ~/.local/share/godot/export_templates/4.7.2.stable && unzip -q -j templates.tpz -d ~/.local/share/godot/export_templates/4.7.2.stable
# (github.com downloads were blocked by the proxy in the previous environment; downloads.godotengine.org worked)

# Web build + screenshots
Godot_v4.7.2-stable_linux.x86_64 --headless --path . --export-release "Web" build/web/index.html
cd tools/webshot && npm install && QS='?spawn=8,30,0,-12&showroom&hour=11' SHOT=shot.png node webshot.js
# Chromium: the previous environment had it at /opt/pw-browsers/chromium-*/chrome-linux/chrome;
# edit the executablePath in webshot.js or set PLAYWRIGHT_BROWSERS_PATH. Playwright's own
# `npx playwright install chromium` also works if the network allows it.

# Meshy tooling
pip install pillow
export MESHY_API_KEY=...   # never in the repo; the owner has it
python3 tools/meshy.py balance
```

Screenshot harness facts that cost hours to learn: the web build runs at about 1 FPS under
SwiftShader and Godot clamps frame time, so a 1 ms key tap in Playwright walks the player meters
and a 25 s in-game timer takes minutes of wall time. The harness presses no keys. Place the
camera with `?spawn=x,z,yaw,pitch[,y]` (desktop: `-- --spawn=...`), jump the clock with
`?hour=17.5`, and use `?showroom` to line up every car, pedestrian and jet at the spawn. Web
lighting is flat: judge geometry, materials and layout, not light. Forward+ effects (SDFGI, SSR,
volumetric fog, glow) have never been seen by any Claude session; only the owner's Mac shows them.

**Native renders without a browser (added build 64, `-- --nohud` hides the overlay):** the container has Xvfb and Mesa llvmpipe, so
Godot's real Compatibility renderer runs headless-ish and screenshots in ~20 s instead of the
web harness' minutes. `tools/glshot/building_shot.gd` renders one generated `Building` (env
`OUT`, `BSEED`, `FINISH`, `LOT`, `HMIN`, `HMAX`), `tools/glshot/city_shot.gd` renders the city
scene at a `--spawn` (env `OUT`, `FRAMES`). Both start with
`LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3
--display-driver x11 --audio-driver Dummy --path . --script tools/glshot/<file> --resolution 960x540`
(the usage line in each file has the full command). Use the building one to check any facade or
rooftop change before exporting: the build-64 "cage towers" (window frames at twice the wall
height, because a face center that already held the part's Y got the absolute row height added
again) took a whole session of web screenshots to diagnose and one native render to see.

## 6. Where the game stands (build 139)

Everything in the roadmap is done (milestones 1 to 8) plus the LA-style map, the realism passes,
the "map character" batch, the 2026-09-20 owner batch and the 2026-09-21 PS5 push. Recent builds,
newest first:

- 139: the two finished hi-fi car bodies (222k and 217k triangles) plus their generators.
  **Committed but NOT wired in**: `Vehicle.BODY_MODELS` still points SUPER and HYPER at the old
  `exo_*` pair. Flipping those two lines is the next thing anyone should do, because the `exo_*`
  bodies have no wheel arches at all - their own critic measured the front tyre standing 11.8 cm
  proud of the bodywork with bare sky above its outer 12 cm.
- 138: `docs/ASSETS.md` gains a section for the cars we generate ourselves - neither downloaded
  nor Meshy, so they had fallen through the documentation entirely. Records the six material
  slots every car must expose (`paint`, `glass`, `trim`, `tyre`, `light_front`, `light_rear`),
  because `Vehicle._add_body_model()` binds by name.
- 137: two measurement traps written into CLAUDE.md. Both report success, which is the worst way
  to fail, and both cost real time this session. See section 9.
- 136: `tools/geo_count.gd`, the triangle/draw/object counter the geometry work was measured with.
- 135: the geometry budget. 4.65M -> 10.7M triangles at the spawn camera for **twelve** extra draw
  calls: denser grass blades with a crease, palms rebuilt at real density (40 trunk rings, 60
  frond steps, 4 segments a leaflet), and per-surface subdivision numbers for terrain, ground
  grids and the ocean. Every number is an @export in a "Geometry budget" group on `CityChunk`.
  Nobody has measured the frame rate on real hardware - that needs the owner and the F1 stats line.
- 134: surf and shoaling on the ocean, and three fixed defects: the rain curtain fell UPWARD
  (sign error), the lens rain slid UP the glass (`SCREEN_UV.y` runs downward in a canvas_item
  shader), and the five coast uniforms were never pushed at all, because a child's `_ready()` runs
  before its parent's and `CityStreamer._ready()` is what creates `plan`. That last one only
  looked correct because the shader's hardcoded defaults happen to match `MacroMap` exactly.
- 133: bullets know what they hit. Surface-aware impacts, plus two fixes: every shot at the ground
  was classified METAL (the chunk's `StreetProps` body carries every road, pavement, plaza and car
  park as well as the props - measured 400/400 rays METAL before, 400/400 CONCRETE after), and
  warehouse walls rained glass. `tools/classify_probe.gd` aims rays at each case.
- 132: neon anchored to the buildings it hangs on (blade signs were rendering MIRRORED, and neon
  lifted per-instance by the relief while its structure was lifted once came apart on slopes);
  power lines that reach an actual wall instead of stopping in mid-air; poles no longer driven
  through the freeway deck; twilight that ramps instead of snapping 0 -> 0.22 in one frame twice a
  day; god rays that still point at the sun after twenty minutes of play.
- 131: docs only.
- 130: four measured defects, each found by an agent that went looking rather than by play.
  **Pedestrian clothing had never worked on the Mac build at all**: Forward+ and Mobile hand a
  `source_color` texture back LINEARISED and the Compatibility renderer hands back raw sRGB, and
  every threshold in `character.gdshader` was written against the sRGB numbers, so on desktop the
  shader called every garment skin and recoloured nothing. `Pedestrian._texture_value()` now moves
  the thresholds into the current renderer's space at material build time. Hair recolouring was
  also a no-op (0.8% of head pixels reached it; hair is the dark half of the head, so it is found
  by darkness now) and `pedestrian_c` got no garment split at all, because its jacket and trousers
  are the same warm brown as its skin - skin now has to be bright as well as warm. Plus: chamfered
  buildings were missing cornices, copings, string courses, plinths and parapets on two of every
  four cut corners (a left-handed Basis on those corners meant CULL_BACK threw away exactly the
  outward faces); one loudness reference for every sound plus a hard limiter on the master bus
  (peak-normalised recordings are not equally loud - three takes of the rifle were 9.3 dB apart).
- 129: freeways fly over each other instead of through each other. Nothing in the routing ever
  looked at the other routes, so the Coast and Cross decks met with 1.2 m between two 34 m wide
  carriageways. `Freeway._separate_crossings()` lifts the later route 7.5 m clear, easing in and
  out at `MAX_GRADE` so the flyover is drivable.
- 128: Forward+ headless rendering with no GPU. `tools/glshot/forward_shot.sh` runs Godot through
  lavapipe (Mesa's software Vulkan driver), so SDFGI, SSR, TAA, AgX and volumetric fog can all be
  screenshotted from this container. **This matters more than it sounds**: every visual judgement
  in this project's history before build 128 was made on the Compatibility renderer, which has
  none of those, and that is not the build the owner plays. Six minutes a frame, so use
  `city_shot.gd` on opengl3 to iterate and this to sign off.
- 127: real wheels - correct track, radius and per-type ride height (they were all on a 2.0 m
  track with 0.84 m wheels).
- 126: exotics on the street: supercars, spiders and hypercars, as original marques. The owner
  asked for Ferraris, Bugattis and Rolls-Royces; copying their trade dress is not something this
  project will do, so these are cars in the same classes with their own shapes and names.
- 122 to 125: car jumping is unlimited so cars can be flown continuously; kerbside parking fixed;
  lawns stop glowing at night (twice - the albedo boost, then the missing `night_factor` term,
  because roads are lamp-lit and grass is not); facade relief, neon signage and street clutter.
- 112 to 121: the foliage and colour pass. Five city tree species and four hill species at their
  own measured heights (a shared 6-10.5 m target was stretching a 2.61 m model 3x, which is why
  trees read as bare branches), per-instance leaf thinning, hue and shape variation through
  `INSTANCE_CUSTOM` so fifty apparent variants cost zero extra draw calls, jacaranda boulevards
  that actually bloom lavender, flowers and ground cover at knee height, and lawns that read as
  ground rather than green rectangles.
- 104 to 111: real recorded CC0 sound instead of synthesized tones, and the CC0 audio sources
  recorded in `docs/ASSETS.md`.
- 100 to 103: palm fronds folded and swept forward; more colour on the streets;
  `tools/fetch_polyhaven.py`.
- 99: lane paint on the freeway decks (it was being built face-down and culled).
- 98: traffic on the freeways, both carriageways, riding the deck's height profile.
- 97: the horizon map's mountains match the terrain shader, so ranges have no tide-line.
- 96: no grey wall round the valley or along the city/hills seam (two separate height bugs).
- 95: the basin is ringed by real mountains (front range, back range, east range, peninsula)
  with the horizon plane displaced so they have a silhouette; the inland valley is a city built
  on a plateau; and three long curved **freeways** ride an elevated deck across the city on
  pillars, with barriers, lane paint, sign gantries and off-ramps.
- 93: a car's five night lights are one mesh, not five nodes.
- 92: the sea. Real wave normals (it had none, so it was lit as a flat sheet), tight foam, the
  sky mixed in by fresnel with a sun glare path, the sea-floor box dropped below the troughs,
  and the horizon plane sunk away from the camera so it stops z-fighting the water. Plus a
  subtle lens vignette over the whole frame.
- 91: the trees' leaves move too.
- 90: palms sway in the wind, softer trunk bark.
- 89: the HUD starts clean (F1 cycles clean / stats / hidden), the hills burn gold, lawns run
  from watered to burnt, the baked horizon map is jittered so sprawl reads as a city. (88 was a
  docs-only push; the build number is the workflow run number, so it still burns one.)
- 87: the ground stops tiling visibly; car parks, yards and plazas go through the wear shader.
- 86: lamps come on in a storm, the horizon plane stops painting grass over the sea and sand,
  seven skin tones across the crowd, six palm variants, chunkier pilasters.
- 85: shop names on the storefront sign bands, unlit rooms properly dark at night, pilasters
  on LOD commercial boxes too.
- 84: night lighting (street lamps with real lights and pools of light on the pavement, head
  and tail lights and beams on every car), the characters' arms brought down out of their
  scarecrow A-pose, a rebuilt AK-47 at real proportions, and pilasters and base bands on the
  blank walls of big-box stores and strip malls.
- 83: the horizon. Everything outside the streamed chunks used to be a 4 km flat green plane
  whose own edge was the skyline. It is now 14 km across and shaded from a baked image of the
  whole basin (`MacroMap.bake()`), with relief shading and haze that hands over to the sky.
  Clouds are lit by sampling toward the sun (bright shoulders, grey undersides) with a cirrus
  deck above them; palm trunks carry the frond-base lattice.
- 82: dark asphalt (road and pavement had measured to the same grey), crack and stain noise at
  the right scale, real shopfronts (sign band, bulkhead, mullions, doors), feathered palm
  fronds with smooth normals, and the naked orange pedestrian removed (pedestrian_b came back
  with no clothes on it; a smoke check now measures this).
- 81: glass reflects sky and street by fresnel, rooms exposed for daylight, grime that runs from
  the sills, per-window frame tints, fire-escape ironwork that reads as metal.
- 80: fire escapes on brick walk-ups.
- 79: roof coverings (membrane / gravel / bitumen) and much more rooftop plant.
- 78: far skyline gets parallax windows and floor bands; ground wear toned down; aerial shots
  hold their height in tools/glshot/city_shot.gd.
- 77: balconies on residential facades; muted awning canvas colours.
- 76: pavements get expansion joints and per-slab shade through the same wear shader.
- 75: worn asphalt shader: mottling, resurfacing patches, cracks, oil staining, wet roads.
- 74: interior mapping on every window: real rooms with blinds behind the glass.
- 73: character pass: per-person clothing colour, height and gait, proper skin and cloth
  shading. Further realism is blocked on a Sketchfab API token (see the decisions log).
- 72: real generated palm trees and palm-lined streets across the city.
- 71: cars fly (stabilised air control, boost thrusts along the camera), rebuilt explosions
  (light flash, fireball, smoke, sparks, shockwave, scorch, camera shake), `tools/glshot/fx_shot.gd`.
- 70: cinematic realism pass: AgX tonemapping, sky-coloured ambient, SSIL, aerial-perspective
  and height fog, TAA + FSR 2.2, auto exposure, clearcoat car paint with a realistic palette,
  real grass blades.
- 69: quality levels scale crowds and traffic too; frame-time breakdown on the HUD.
- 68: starts fullscreen (F11 toggles), Meshy textures VRAM-compressed.
- 67: spawn lifted onto the rolling ground, under-ground recovery in city zones, 60 FPS cap.
- 66: populated city: people and parked cars per district (downtown core 2x), traffic density by
  distance from downtown, airport drop-off loop road with 90 crawling cars and a curb crowd.
- 65: animated main character (`Avatar`), ragdolls keep the real model, first lag pass
  (`Quality` node, flat window frames with a draw distance, pedestrian update throttle).
- 64: facade geometry (frames, cornices, awnings), Poly Haven rooftop AC units, `tools/glshot`.
- 63: weather (overcast / rain / storm, lightning, wet streets) and tsunami-size waves.
- 62: shopping plazas, big-box stores, fast-food and gas-station pads, lawns, pocket gardens.
- 61: street detail (stop lines, arrows, street-name signs, poles and cables, bus shelters).
- 60: cars drive forwards, two-tone paint shader, far-box windows, new minimap, unlimited jumps.
- 59: city relief (rolling ground under the blocks), seeded surface variation per district.
- 52 to 58: Poly Haven props, trees, rocks, PBR wall textures, sky haze fix, screenshot rule.
- 51: bigger airport (3 runways, hangars, jet bridges), flyable jets (`Aircraft`), AK-47 bullets
  now hit pedestrians (they were on the wrong physics layer for months of session time).
- 49: campus district and the campus hall landmark ("RANDO U").
- 48: hill road network with carved terrain, estates (villa, pool, palms), peninsula in a bay,
  ocean visible again (it had been rendering as grass under the ground follower plane).
- 47: skyline: taller downtown core, setback and crown towers, spires, the needle, twin towers.
- 46: custom sky shader: sun disc, clouds, golden hour, stars.
- 45: all seven Meshy models regenerated realistically; crowds doubled (160 people, 24 traffic
  cars on desktop; 80 / 14 on the web).
- 44: cars and pedestrians use Meshy models; `?showroom`.
- 43: the "stuck under the world" bugs (three real causes, see the decisions log).
- 42: fall-through recovery, Space jumps the car, round rotating minimap.

Meshy credits: 1,680 at the start, 1,221 after the owner topped up; each car 30, each rigged
pedestrian 44, each jet 30. `docs/ASSETS.md` has the table.

## 7. Architecture in ten bullets

- `CityStreamer` is the scene root: streams `CityChunk`s around the player (FULL near, LOD far),
  keeps a 4000 m ground follower under the player (40 m thick), re-centers the origin when far
  from 0 (`WorldState.world_offset`; everything that must survive that is a 3D child of the root),
  handles `?spawn`, `?showroom`, `surface_height_at()` and `ensure_loaded_at()`.
- `CityPlan` is lazy endless data keyed by block index; `MacroMap` decides zone, district and
  height for any world XZ; `HillRoads` carves roads and mansion pads into the terrain height.
- `CityChunk` builds one block: roads, sidewalks, lots of `Building`s (shader-driven boxes), props
  via `MultiMeshBatch` with breakables on the chunk's `StreetProps` body, parked cars and jets
  spawned under the city root and freed with the chunk unless driven, terrain / water / sand /
  tarmac for other zones, hill roads and estates, landmarks in its rect.
- `Landmarks` is a static list with builders; far copies always exist, detailed ones per chunk.
- `Vehicle` is a VehicleBody3D built in code (box collision, Meshy body model tinted by paint);
  `Aircraft` extends it with an arcade flight model; `TrafficManager` drives kinematic ones.
- `Pedestrian` is a CharacterBody3D wandering a sidewalk ring with a rigged Meshy model
  (`custom_aabb` needed, faces +Z, material sanitized), becomes a box `Ragdoll` when knocked.
- `Player` handles movement, boost, jumps, weapons, riding, exit-spot search, and recovery from
  falling through the world or ending up under hill terrain (terrain has its own physics layer).
- `DayNight` drives the sun, the sky shader's colors and `night_factor`.
- Physics layers: 1 world, 2 player, 4 props, 8 npc, 16 terrain. `Player.AIM_MASK` = 1|4|8.
- `PhysicsBudget` caps live rigid bodies and never freezes vehicles (frozen wheels give NaN).

## 8. Hard-won gotchas (the full list is the decisions log)

- The city ground is not flat: `MacroMap.relief_at()` rolls up to 16 m. Chunk code samples it
  through `_gy()`; the multimesh batch and `_add_slab()` / `_add_prop()` add it for you, nodes
  you position yourself need it added once. Buildings carry a concrete plinth for the slope.
- Never `reparent()` a VehicleBody3D; never freeze one; never give a kinematic one wheels.
- Godot's `engine_force` pushes toward local +Z; the car negates it.
- Physics queries are stale for a frame after an origin shift (`_query_hold`).
- Bodies spawned overlapping a static shape get shot through thin floors; far chunks now carry
  collision for buildings and terrain so nothing sits inside a footprint when detail arrives.
- Every Meshy car model has its nose along +X: `Vehicle.MODEL_YAW` -PI/2 puts it at -Z, the
  physics forward. Car paint is `shaders/car_paint.gdshader` (luminance split), not a tint.
- The Meshy car bodies ship flat-shaded (normals split at 30 degrees and on every UV seam on an
  8k-triangle remesh); they have been through `tools/smooth_normals.py` (45 degrees). A fresh
  Meshy car needs the same, or it comes out faceted.
- Meshy: rigs have a cm skeleton under a 0.01 armature; animated exports drop PBR maps and set
  metallic 1 + emissive; models come out along +X or -X (`MODEL_YAW` tables); car paint needs the
  base color greyscaled (`shrink_glb.py --desaturate`) so the tint works.
- The smoke test is physics-driven and can flake; the driving checks now start on a cleared
  road with traffic and crowds removed, and the jet taxi lane must stay clear of landmark parts.
- The `.import` files and extracted `_N.jpg` textures next to `.glb` files are import output and
  are committed; stale `*_texture_0.png` files from older imports get deleted before committing.
- `project.godot` must stay in Godot's own section order or the editor rewrites it.
- `import_etc2_astc=true` must stay on or the universal macOS export fails.

## 9. Known gaps and things nobody has verified

Rewritten 2026-09-21 at build 130.

- **Two measurement traps that report success.** Both are in CLAUDE.md; both cost time this
  session. (1) Godot serves a CACHED import of a `.glb` or a texture, so a render taken after
  rebuilding a model shows the OLD file - run `--import` in between, and print the model's AABB
  in the shot script to catch it. (2) `--headless` is the dummy rendering server: every
  `Performance` monitor reads exactly zero and `MultiMesh.get_instance_transform()` returns
  identity, so a geometry change of any size measures as no change and an instance-transform
  check measures nothing while reporting a clean bill of health. Use `tools/geo_count.gd` under
  opengl3 with Xvfb.
- **Agent work is not finished work.** Most of what landed in builds 130-139 came from fleets,
  and roughly half of what they produced was wrong in a way only a render or a probe would show:
  rain falling upward, blade signs mirrored, every ground shot classified metal, shut lines that
  measured as cut and were sub-pixel, wheels that were actually the arch lining. The pattern that
  worked was build -> adversarial review -> repair, with the reviewer rendering independently.
  The pattern that failed was trusting a summary. Also: a critic saying `ok: false` means do not
  ship it, and a reviewer's claim you cannot reproduce means do not "fix" it - one seam fix was
  made for a seam that was never there.
- **A human has still never confirmed what the Mac build looks like.** Build 128 made Forward+
  screenshots possible from this container (`tools/glshot/forward_shot.sh`), which closes the
  worst of the gap, but lavapipe is not a GPU and the owner's eyes are still the only real test.
  Build 130's crowd fix is the cautionary tale: a whole subsystem had been broken on desktop only,
  invisibly, because every screenshot taken of it for weeks was the web renderer.
- **Characters are the weakest thing in the game and are blocked on a source.** Three rigs, 8,300
  triangles, one 1024 texture each, no normal or roughness maps. Everything reachable in code -
  arms, clothing colour, skin tone, height, gait, accessories - has now been done, twice. What is
  left needs better models. Poly Haven's "rigged" category is articulated props (clocks, tools),
  not humans. The owner would have to supply a Sketchfab API token
  (sketchfab.com > Settings > Password and API).
- **The surface street grid is still axis-aligned.** The freeways and the hill roads curve; the
  streets between the blocks do not, and the owner has asked about it directly.
  `CityPlan.road_pos()` is one scalar per axis and every consumer (blocks, lots, traffic lanes,
  the minimap) assumes axis-aligned rects, so this is a rewrite of the city plan, not a tweak.
  Decide with the owner before starting it - it is days of work and it moves every seed.
- Ragdolls are one tumbling rigged body, not a simulated skeleton (PhysicalBoneSimulator3D).
- Traffic drives the city grid and the freeways; hill roads and the airport aprons have none.
  Parked cars do not spawn on hill roads. Pedestrians do not walk the campus quad or the hills.
- Jet landing has not been exercised beyond the smoke test's takeoff. Gear is tiny and hidden
  under the model; the flight model is arcade and may need tuning (`aircraft.gd` exports).
- The moon is the sun light re-aimed at night; the sky draws its disc where LIGHT0 points.
- LOD terrain (6 subdivisions) vs FULL (14 or 28) can pop at the swap. Hill road cuts are
  graded banks now (`HillRoads.carve()`, 1:1 cut, 1:1.5 fill). The price was the front range's
  canyon roads and estates: they climbed straight up a slope no road can be graded into (cuts
  up to 320 m, fills up to 170 m, every one a sheer wall) and are now trimmed by
  `_earthwork_ok()` to stubs - all but the canyon road up the pass and its estates (318 mansions
  in the world, 468 before; the headland kept nearly all of its own). Roads and houses back on
  the front range need switchback walks that follow the contours, or gentler foothills, not
  deeper cuts.
- The web build carries all the models and runs slowly on weak machines; caps are lower there.
- The Meshy API key the owner pasted in chat during this project should be rotated. Meshy itself
  is retired (owner, 2026-09-19), so nothing needs the new one.

## 9a. The LA pass, 2026-09-21 afternoon (newest work)

The owner asked for the map to be a miniature of the real Los Angeles, naming PCH, Palos Verdes,
Redondo and Manhattan piers, Santa Monica, Venice, Malibu, Del Amo, Urth Caffe, a masjid, USC and
the 405 / 110 / 105. The basin already had LA's shape; what it had no version of was the coast
road, the chain of beach towns, or any of the named places.

Delivered, all green and on main:
- **Pacific Coast Highway**, from the northern cliffs to the far side of the headland, held 46 m
  in from the waterline so it inherits the shore's own bends. It needed a **coastal shelf** in
  `MacroMap.raw_height_at()` first: up north the front range runs into the water, so the road
  would have been a cutting in a 560 m mountainside. The shelf cuts a 300 m bench at 26 m along
  the shore north of z -700 - mountain, bench, road, sea - fading out southward and never
  touching the headland, whose cliffs into the water are the point of it.
- **Eight named beach towns** (Malibu, Santa Monica, Venice, Playa, El Segundo, Manhattan,
  Hermosa, Redondo) plus Palos Verdes, surfaced through `MacroMap.place_name()`, which the HUD
  prefers over the zone and district names. A **BEACHTOWN district**: denser than the suburbs
  and much lower, heavy weathering, metered kerbs, the palmiest district on the map.
- The headland moved from z 1500 to **1980**, because at 1500 it started exactly where Manhattan,
  Hermosa and Redondo needed coastline.
- A fourth freeway (**110**, downtown to the port) and real numbers on the other three.
- **Six landmarks** built by an agent fleet, each a self-contained `scripts/world/landmark_*.gd`
  wired into `Landmarks`: Venice boardwalk, Manhattan pier, Redondo pier, South Bay Mall,
  Verde Cafe, Masjid Al Noor.
- **The beach follows the shoreline** instead of being a chunk-sized slab, with a two-slope
  profile that breaks at the waterline, and is laid by whichever chunk the waterline crosses
  (`_owns_shoreline()`) regardless of that chunk's zone.

**Naming rule applied, and worth keeping.** Geography and route names are used as-is: Malibu,
Santa Monica, Venice, Manhattan Beach, Redondo, Palos Verdes, PCH, 405, 110, 105. Business and
institution trademarks are not: Del Amo became South Bay Mall, Urth became Verde Cafe, and the
mosque is an original design named Masjid Al Noor rather than a model of a real one. Same rule
the project already used for RANDOWOOD and the exotic marques.

**Two silent errors, both fixed, both had been passing the gate.** `tests/headless_check.sh` only
tripped on "SCRIPT ERROR", and Godot prints engine errors as plain "ERROR", so a run reporting
195 passes was logging 310 of them: the beach generated tangents with no UVs (so its normal map
did nothing) and freeway traffic was positioned before being added to the tree (253 a run, every
car placed against no parent transform). The gate now catches both. **If you add a system, check
the log for bare ERROR lines - a green run is not proof.**

**Depth of field now opens with altitude** (`CameraRig._update_focus`). It was fixed at 260 m,
which reads as a lens on the street and is simply wrong in the air, where the owner spends much
of their time: every pixel past that distance went soft, so aerials looked like watercolours.

**The render pass is half done.** An agent fleet was raising four subsystems - sea, foliage,
facades, colour grade - and was stopped partway because four concurrent Forward+ renders on a
four-core box drove the load average to 45 and starved everything else. The sea and foliage work
IS on main (depth-graded water colour, subsurface scattering through crests, gathered foam,
physically correct fresnel at F0 0.02). **Facades and the colour grade were never started.**

**The colour grade: done, and here is what it actually was.** The symptom was right - a Forward+
aerial was pastel with no value contrast - but the cause was not the fog. Measure a frame instead
of looking at it:

```
python3 -c "from PIL import Image; import numpy as np; g=np.asarray(Image.open('shot.png').convert('L')).astype(float); print([round(float(np.percentile(g,p))) for p in (1,5,50,95,99)])"
```

The midday downtown aerial came back `[51, 78, 103, 137, 214]`: **the whole city lived between 78
and 137 of 255**. The same scene through the opengl3 path measured 51 to 185. The difference is
**AgX**. AgX rolls an enormous range into the screen and, unlike ACES, it is designed to have a
"look" - a contrast curve - applied after it. There was none, so every frame came out as the flat
middle of the AgX curve. The fog made it worse but the fog was never the cause; turning the haze
down alone moved p95 by six levels.

What is on main now:
- A **look LUT**: a `Gradient` / `GradientTexture1D` pair in `city.tscn` wired to
  `Environment.adjustment_color_correction`. Godot runs each channel through it separately after
  tonemapping, so it is a per-channel curve, not a tint: an S with a slope of about 1.6 around a
  0.45 pivot, cool in the toe and warm in the shoulder. `adjustment_contrast` is back to 1.0 -
  the LUT owns contrast now, and stacking the two crushes the toe.
- **Exposure that opens after dark** (`DayNight.day_exposure` 1.25, `night_exposure` 2.1, lerped
  on `night_factor` onto `Environment.tonemap_exposure`). Eye adaptation for free, and it is what
  stops the punchier curve from turning a lamplit street into mud.
- **A key light that out-runs the fill.** `day_sun_energy` 1.0 -> 1.3, `day_ambient_energy`
  0.55 -> 0.30, `ssil_intensity` 1.0 -> 0.5, `sdfgi_energy` 1.1 -> 0.85. A real midday shadow is
  a fifth as bright as the lit side; it was two thirds.
- **Shadows that reach.** `Quality.shadow_distance` was 320 m at HIGH, so everything past three
  blocks was lit but never shadowed - half of every aerial had no contrast available at all. Now
  700 m, carried by four PSSM splits and a fade (`city.tscn`) instead of two.
- **Haze in the distance instead of over everything**: `fog_aerial_perspective` 0.7 -> 0.32,
  density 0.00012 -> 0.00009, volumetric 0.0025 -> 0.0014, and `DayNight` now owns the fog colour
  as three tunables (`day_fog`, `dusk_fog`, `night_fog`) so the far distance goes gold at sunset
  instead of staying blue.

The smoke test guards all of it: the LUT exists, the sun beats the fill by more than 2.5x, and
HIGH shadows reach at least 500 m. The old guard demanded `fog_aerial_perspective > 0.5`, which
had quietly made the washed-out look a requirement; it now only checks the effect is on.

**Fifteen numbers that live in two files.** An audit fanned out over the repo looking for pairs
of constants that have to agree across a file boundary with nothing in code connecting them -
the class of bug where nothing errors and the picture is just wrong. Fifteen survived an
adversarial second pass. The worst by far: `shaders/ocean.gdshader` carries a hand-transcribed,
sRGB-decoded copy of `MacroMap`'s sea palette (`BAKE_OCEAN_DEEP/SHALLOW/SURF`, `BAKE_SURF_WIDTH`
and `bake()`'s `/600.0` shelf ramp), because past `handover_start` the water chunks stop drawing
their own sea and re-draw the far plane's. Re-tune the bake alone and you get a hard-edged
rectangle of differently coloured water about 500 m across, locked to the player, following him
round the bay - which is exactly what that shader's own 25-line header is about.

Two fixes, in this order of preference:
1. **Remove the coupling.** `coast_wobble` (180), `coast_period` (700) and `peninsula_bulge`
   (520) were literals inside `coast_x()`, so the shader had to carry its own copies;
   they are MacroMap fields now and `Weather._push_ocean_shape()` sends them over with the rest.
2. **Guard what cannot be removed.** `tests/smoke_test.gd` now reads the second copy out of the
   other file's source (`Shader.code`, `GDScript.get_script_constant_map()`) rather than writing
   the number a third time, and checks: the ocean shader's sea palette and coastline defaults
   against MacroMap; `valley_height` against `built_amount()`'s 420 m gate; `Commercial.TOP`
   against `CityChunk.SIDEWALK_TOP`; and every per-index table against its enum
   (`MacroMap.ZONE_NAMES`, `Minimap.DISTRICT_COLORS`, `Vehicle.BODY_NAMES/MODELS/ODDS` including
   the sum-to-1000 rule, `Weather`'s five per-state tables, `Quality`'s three per-level ones).
   All six guards were checked by breaking each value and watching the right one fail.

The other nine are in the audit and still unguarded, mostly duplicated geometry: the airport
tarmac top (0.1) is written in four places, the terminal kerb rect and its drop-off lane paths
are two independent sets of coordinates, `StreetDetail.POLE_HEIGHT` is 9.0 and so is the `upole`
cylinder in `PropFactory`, and `Building.gd` places shop-name meshes at 0.845 of the storefront
while `building.gdshader` paints the sign band at 0.76..0.93. **When you add a number that
something in another file has to know, make it a field and push it, or add the guard in the same
commit.**

**Facades: the whole downtown was pixel art, and it was one line.** A Forward+ street render at
10:00 showed every tower as a random checkerboard of gold and black rectangles, one per window
bay, with no glass in it - no highlight, no sky in the panes, no mullion. `building.gdshader`
already had interior mapping, a Schlick fresnel sky reflection and spandrel panels; four things
were burying all of it, and a three-agent diagnostic fleet found them:
- `float on = 0.12 + 0.88 * night_factor` in the `lit` branch. A window the lit roll picked
  still carried a warm emission at ten in the morning, and `lit_ratio` runs to half the bays.
  **That is the checkerboard.** Same daytime floor in `building_lod.gdshader`, so the distant
  towers did it too.
- The inset shadow that sets a pane back into the wall used `max(du - 0.2, dv - 0.18)` whatever
  the window style. Those two numbers are exactly `win_h - 0.07` for style 0 (PUNCHED) and for
  nothing else, so on a curtain wall (win_h 0.475/0.47) it darkened 86 % of the pane by 45 %:
  every bay a dark rectangle with a lighter card floating in it.
- `frame_color` for GLASS was 0.14, darker than the panes it frames, so the grid a curtain-wall
  tower is made of was drawn and then invisible.
- Window pitch took exactly four values and two thirds of downtown shared 1.8 m.

**The whole city was dressed in black, and it took two goes.** First attempt widened the ranges
and kept the mechanism; the mechanism was the bug. `cloth_value` multiplied the SOURCE texture's
own brightness, and pedestrian_a's garments measure 0.21-0.32 with its trousers lower still -
there is no multiple of near-black that is a white shirt. `cloth_value` / `pants_value` are the
garment's own brightness now, 0 to 1, with the source's value kept as *shading* around it.
`CLOTH_VALUE_BAND` also moved to 0.030..0.075: the rigs' trousers sit at about 0.10, which put
them halfway up the old 0.045..0.13 band, so trousers took barely half the recolour however they
were rolled - colour above the waist, black below it.

**Measure the texture, not the code.** Both of those were found by reading a number out of the
asset rather than out of the source:
```
python3 -c "from PIL import Image; import numpy as np; im=np.asarray(Image.open('assets/models/pedestrian_a_0.jpg').convert('RGB')).astype(float)/255; v=im.max(axis=2); print([round(float(np.percentile(v,p)),3) for p in (10,25,50,75,90)])"
```

**Land no longer stands in the sea.** `zone_at()` draws the shoreline as a hard line and
`raw_height_at()` is a noise field that knew nothing about it, so the two disagreed - most
visibly off the Redondo pier, where the coast bulge (a function of z alone) cut clean across the
headland (a circle) and left a sail of hillside hanging over the water. `MacroMap._shore_mask()`
now brings the land down to zero across `shore_rise` metres wherever the zone says water, at the
coastline and around the bay, and the smoke test sweeps the whole coast and the bay for land
above 4 m.

**Practical note on the fleet.** Cap concurrent agents at two on this box, and do not let agents
run Forward+ renders - have them use the fast opengl3 loop and sign off the result yourself.

## 9b. Paused mid-flight on 2026-09-21 (read this first if you are picking up)

The session was paused with three agent fleets running. They were stopped, their finished work is
on `main`, and what was half-written is saved as patches under **`docs/wip/`** with a README
explaining each one and what is unverified about it. `main` is green at 190 checks with none of
them applied, so you can ignore them entirely if you would rather start fresh.

**The single highest-value thing available, and it is two lines.** `Vehicle.BODY_MODELS` still
points `BodyType.SUPER` and `BodyType.HYPER` at `exo_super_coupe.glb` / `exo_hyper_a.glb`. Those
bodies have **no wheel arches at all** - their own critic measured the front tyre standing 11.8 cm
proud of the bodywork with bare sky above its outer 12 cm, and called it "wheels bolted onto the
outside of a slab". The finished replacements are committed and unused:
`hifi_super_coupe.glb` (223k tris) and `hifi_hyper_coupe.glb` (217k tris), both built the right
way (see `docs/ASSETS.md`) and both carrying their own wheels. Swap the two lines, run the check,
look at a showroom render, push.

Order of the rest, hardest-earned first:

1. Finish the wheels patch. The wheel mesh is already on `main` as dead code (see the correction
   at the end of `docs/GAME_PLAN.md`); only the `Vehicle` wiring is missing. The real insight from
   that work: the four Meshy bodies are 88% of traffic and each has its wheel modelled into the
   painted body surface, so it wore the car's paint. Never a missing wheel - a wrong material.
2. Finish the character PBR maps. `pedestrian_b` was never generated. This one deletes a whole
   class of bug, not just a symptom.
3. Finish the signs patch, minding the u/a mirror trap.
4. Re-run the horizon-ground and road-surface tracks; they died at the spend limit and never
   produced anything. `docs/wip/` has no patch for them because there was nothing to save.

**Blocked on the owner:** the monthly spend cap was hit mid-session and killed four fleets. And
nobody has ever measured the frame rate on real hardware - build 135 took the city from 4.65M to
10.7M triangles at the spawn camera, which is a real jump, and the F1 stats line would settle it
in one screenshot.

## 9c. Session of 2026-09-22 (read this first if you are picking up)

This session was handed over so the owner could move to another account. Everything below is on
`main` and green. Nothing is half-applied and there is no `docs/wip/` to reconcile this time.

### What shipped

**The colour grade (builds 155-168).** AgX filmic tonemapping expects a contrast curve applied
*after* it, and there wasn't one, so every frame was the flat middle of the AgX ramp. That curve
is now a Gradient / GradientTexture1D pair on the city Environment's `adjustment_color_correction`
(`scenes/levels/city.tscn`). `adjustment_contrast` deliberately stays at 1.0 - the LUT is the
curve, and stacking a second one on top is what the first attempt got wrong.

`DayNight.moonlight` was added alongside `night_factor` because `night_factor` reaches 1.0 three
degrees after sunset, which is right for switching the lamps on and wrong for the light: driving
exposure and the sun's colour off it washed the whole city lavender at 18:30. `moonlight` is the
slower ramp; `night_factor` still drives lamps, windows and the shader global.

**The volumetric haze (build 169).** The fog volume was 220 m, which is shorter than the first
block of buildings past the camera. Godot clamps the froxel lookup at `volumetric_fog_length`, so
*everything* beyond it got one flat, distance-free curtain - the mountains and the tower two
streets away hazed by the same amount, which is the opposite of aerial perspective. It is 900 m
now with the density cut to match (0.00014 clear), forward anisotropy 0.45, and ambient/sky
injection at zero so the volume is lit by the sun rather than by a flat fill.
`DayNight.haze_gain` scales that density by the sun's height - full on the horizon, a third of it
overhead - because haze is forward scattering through a long path of lit air, which is most of
what a hazy sunset looks like and almost none of what a hazy noon looks like.
**Trap:** `Weather._process()` overwrites `volumetric_fog_density` every frame from
`volumetric_by_state`, so tuning that value in `city.tscn` does nothing at all. That cost an hour.

**Seven geometry and colour-space bugs (final build of the session).** Three of them are the same
mistake, and it is worth internalising because the code makes it easy to make:

> `Basis.scaled()` is a **left** multiply - Godot scales the basis *rows* - so its factors land on
> the **world** axes *after* any rotation, not on the mesh's own axes.

`scripts/world/street_detail.gd:17` documents the rule and `scripts/world/signage.gd:139` has a
`_scale_basis()` helper that avoids it, and three call sites still got it wrong. A probe under
`--headless` settles any instance of this in seconds; what it printed:

```
tipped.scaled(13, 13, 1) -> quad spans 13.0 x 1.0    every street and pier lamp threw a
tipped.scaled(13, 1, 13) -> quad spans 13.0 x 13.0   13 x 1 m BAR, not a 13 m disc of light
yaw.scaled(1, 1, 3)      -> the 3x landed on the stripe's 0.6 m WIDTH, not its 3 m length
sign basis, fit 0.5      -> old: along 1.0, up 0.5   the horizontal fit was on the VERTICAL axis
                            new: along 0.5, up 0.5
```

So: every lamp in the city lit a bar; runway centreline dashes were 3 m long and 1.8 m wide and
the edge lines were white slabs roughly 200 m *across* the runway; and on the two faces of every
building whose along-vector runs down world Z, the shop name kept its full width - running into
the shop next door - while being squashed vertically. The two ladder-crosswalk branches had each
other's basis. All fixed, and `tests/smoke_test.gd` now *measures* the lamp pool's real world
extents rather than trusting the argument order, so it cannot silently revert.

The other two:

- `shaders/terrain.gdshader` `dry_tint` was hinted `source_color`, which Godot sRGB-decodes. It is
  a **multiplier** on sampled grass, so fully-dry hillside rendered at luminance 0.096 - *darker*
  than the live grass beside it at 0.126, and rust rather than gold. This is the same mistake
  commit `890ad3d` fixed in nine places on the ground; check any new tint against which side of
  the decode it is on.
- The 14 km ground follower had `cast_shadow` at its default. At 200 x 200 quads that is 80,000
  triangles drawn into all four shadow cascades every frame, to shadow nothing (it is the plane
  *under* everything). It still receives, which is what matters.

### The one thing still open, and where the evidence points

**A midday aerial reads washed out: p5/p50/p95 went from 49/137/174 to 107/209/227 - a uniform
lift across sky, mountains, far basin, city blocks and near ground alike.** Ruled out, each by
experiment rather than by argument:

- **Volumetric fog.** Disabling it entirely gave a byte-identical histogram. Exonerated.
- **The day/night clock and the camera exposure multiplier.** `tools/glshot/city_shot.gd` now
  prints both with every render; it reported `clock 13:11, night_factor 0.00, exposure multiplier
  1.000, auto true`.
- **Quality stepping.** Every render log says `Quality: high`.

A lift that is uniform across the *sky as well as* the ground is exposure or tone curve, not haze.
Two measurements at the end of the session narrowed it to a specific answer, and both refuted a
guess worth not repeating.

**The guess that was wrong:** that the Compatibility renderer ignores `adjustment_*`, making the
whole washout a harness artifact. It does not ignore it. Same camera, one toggle:

```
grade ON   p1/p5/p50/p95/p99   8  12  185  231  242
grade OFF                      18  27  165  212  230
```

**So the grade is most of the lift, and it is doing exactly what it was written to do**: the LUT
deepens shadows (27 -> 12) and raises everything above its pivot (165 -> 185, 212 -> 231). On a
bright midday frame nearly every pixel sits above that pivot, so the net result is a lift with the
midtones pushed up. The curve's upper half is simply tuned too hot for a noon frame. The knob is
the `Gradient_grade` sub-resource in `scenes/levels/city.tscn`; pulling the 0.62 and 0.78 stops
down toward the identity line (they currently map to 0.722 and 0.886) is the change to try, and
`adjustment_contrast` must stay at 1.0 - the LUT *is* the curve.

**The second finding, and it invalidates every brightness number taken on the fast path.** The
opengl3 render log says, in plain text:

```
WARNING: Auto-exposure is only available when using the Forward+ renderer.
    at: camera_attributes_set_auto_exposure ... [0] _apply_render (res://scripts/util/quality.gd:167)
```

The player camera runs auto exposure at sensitivity 200..620 (`scenes/player/player.tscn`), and on
the owner's Mac that adaptation pulls a bright frame back down. `city_shot.gd` silently drops it.
So a noon frame measured on opengl3 is *brighter than the game* by whatever auto exposure would
have taken off, and no amount of tuning against that path converges. **Judge the grade only on
`tools/glshot/forward_shot.sh`** (real Forward+ via lavapipe, ~6-10 min a frame).

The one render still not done: HEAD through `forward_shot.sh` at a midday camera. A midday city
frame wants p5/p50/p95 near 87/123/175; 78/103/137 is the washed-out look the grade was added to
fix. Take that number *before* touching the gradient stops, because the gap between it and the
opengl3 numbers above is the size of the auto-exposure correction and nobody has ever measured it.

Measure, do not squint:
`python3 -c "from PIL import Image; import numpy as np; g=np.asarray(Image.open('shot.png').convert('L')).astype(float); print([round(float(np.percentile(g,p))) for p in (1,5,50,95,99)])"`

### Practical notes for the next session

- **The container restarts.** It did twice here, killing four agent fleets and a render batch
  mid-flight. The repo and the Godot binary in the scratchpad survived both times. Commit often.
- **The smoke test is now 324 checks (2026-09-24) and the shell timeout in
  `tests/headless_check.sh` is 600 s (it was 420, which the test had outgrown).** Under load from a large fleet it *times out* at
  around 150 checks with zero failures, which looks alarming and is not a failure. Do not run a
  big fan-out and the gate at the same time, and do not read exit code 124 as a pass.
- **The eight-dimension sweep did finish** (56 agents, no errors) and its 26 verified patches are
  on `main` in `2638fec`. Every lead listed above was real: the whitecap threshold was not rare
  but *unreachable*, so the sea had zero foam at every weather state; far buildings were 2.4-7.9x
  brighter than near ones from an un-decoded MultiMesh instance colour; two leaf materials were
  flagged OPAQUE so their black photo background drew solid; ocean chunks and the sea-floor box
  cast shadows from under opaque water; storefront bands never emitted unless the block was
  Commercial. All fixed.
- **One thing the sweep got wrong, and it is the failure mode to watch for in this pattern.** Its
  adversarial verifier approved the patch that *declares* the character normal-map uniforms and
  rejected the two that sample and bind them. Applied as returned, that ships `normal_tex` and
  `normal_strength` as uniforms nothing ever reads: it compiles, it passes the check, and it looks
  from the outside exactly like the feature is in. The wiring was finished by hand
  (`NORMAL_MAP` in the fragment, `Pedestrian._normal_map_for()`, and `pedestrian_c_nrm.png.import`
  which the sweep fixed on `_a` only). **Read a fan-out's patches as a set and ask what is missing,
  not just whether each one is individually correct** - per-finding verification cannot see a hole
  between findings.
- The owner's four reference images are analysed in `docs/GAME_PLAN.md` under "Graphics references
  (owner, 2026-09-21)": a Horizon Zero Dawn forest, a skyline above a cloud sea at sunrise, the
  GTA V Los Angeles overlook, and Miami Ocean Drive at sunset with neon. The unstarted items drawn
  from them are neon signage as a light source, wet-road reflections, layered undergrowth, and a
  bigger, softer sun.

## 9d. The people, 2026-09-22 evening

The owner said the characters "look stupid, their arms are floppy", then "we need entirely new
assets for the humans", and un-retired Meshy for characters only (their key lives outside the
repo; `MESHY_KEY_FILE`). What shipped:

- **New rigs d to l** (`Pedestrian.MODELS`), 16k faces, only the `_anim.glb` committed, each with
  a baked `_nrm.png`. a, b and c stay on disk, unloaded. The player's body is d.
- **The arm fix is now a retarget, not a guess.** Every Meshy rig is bound in whatever pose its
  mesh came out in and the clips assume straight arms, so a fixed shoulder rotation (the old
  `ARM_DROP`) put the new rigs' hands up by their ears. `Pedestrian.fix_arm_pose()` rebuilds
  the arm keys from the rig's rest pose and needs no per-model numbers. Check any new rig with
  `tools/glshot/character_shot.gd` (`MODEL=... YAW=0` and `YAW=90`, `CLIP=run_fast_3_inplace`
  and `CLIP=Idle` too) before adding it to `MODELS`. Measure, too: the first version of it
  looked fine in stills and was still wrong (slumped collarbones, arms trailing the torso's
  lean, hands held off the thighs), which only a bone-by-bone sample over the clip showed.
- **`tools/meshy.py` was throwing the subject away at the texturing step** (a subject-free
  texture prompt), which is why the people asked for as Black, Latino, and in an orange vest
  came back pale and grey. Fixed; j, k and l were made after it and follow their prompts.
- Known flaws in the set: e's jacket sleeves are painted skin-coloured from the elbow down (a
  texture defect from the generator). The outfit recolour now leaves half the crowd in the
  model's own clothes and the skin tints are small: with nine real models the variety comes
  from them, and darkening a pale face with a multiplier gave grey mud, not a darker person.

**Far ground, 2026-09-23.** Anything placed on the ground follower (beyond ~700 m) must go
through `shaders/macro_relief.gdshaderinc`, not `MacroMap.height_at()`: the drawn surface is a
coarse bake plus crags, tens of metres off the real terrain on ridges. `far_canopy.gdshader` is
the worked example: Skyline's hill planting and hill houses go through it, and so does the far
ridge sign (its rigid mode moves the whole name by one amount so it stays level). Other far
landmarks on slopes (the observatory, the hills sign) still stand at `height_at()`; they are
small or low enough that nothing has shown, but they are the next thing to move if it does.
`HIDE=Planting_*,Sky_*` on `tools/glshot/city_shot.gd` hides named nodes, which is how the
floating houses were told apart from the floating trees.

## 9e. Making it run, 2026-09-23

The owner: "I need the game to be playable and not slow without taking away from graphics or
quality at all." What the measurements said and what shipped is in the decisions log (same
date). What a next session needs to know:

- **Measure CPU with a throughput bench, not `Performance.TIME_PHYSICS_PROCESS`.** That monitor is
  the max over the last second of the whole per-frame physics block (all its steps), so it moves
  with how many catch-up steps ran. Wall-clock ms per game second, standing and flying, headless,
  A/B against a `git worktree` of the previous commit, two rounds each: this machine's noise is
  +-10 %, so one run proves nothing.
- **A symbol-carrying Godot for perf** takes 34 minutes: the 4.7.2 source tarball from the GitHub
  release, `scons platform=linuxbsd target=template_release debug_symbols=yes -j4`. Release
  templates refuse `--path` and the working directory (`disable_path_overrides`), so either
  rebuild with `disable_path_overrides=no` or export a pck with the editor binary and pass
  `--main-pack`. `perf` is `apt-get install linux-tools-generic` and then the versioned binary
  under `/usr/lib/linux-tools/*/perf` (the wrapper refuses this kernel); only software events
  (`-e cpu-clock`) exist in this VM.
- **Collision masks cost CPU** (CLAUDE.md, physics layers): static bodies mask 0, detector areas
  not monitorable, placed kinematic bodies without masks. Adding a body with a wide mask is how
  this comes back.
- **Chunk builds are steps** (CLAUDE.md, City): anything new in a chunk build goes in as a step
  or inside one; a big self-seeded job goes through `_run_or_defer()`.
- **Sleep is the single biggest lever and the easiest to lose.** Three separate things had kept
  every parked car in the city simulated every step: VehicleBody3D waking itself in its own
  state callback (`Vehicle.settle()` from PhysicsBudget's *physics* tick is the fix), a weak
  brake letting cars roll, and the ground's collision box being re-placed eight times a second
  (moving a static body wakes all its neighbours). Check the TRUE state with
  `PhysicsServer3D.body_get_state(rid, BODY_STATE_SLEEPING)` - the node's `sleeping` flag reads
  true on a car that is awake - and check it in the release build, where it first showed.
- Driving the release template for perf: it ignores `-s` and refuses `--path` / `--main-pack`,
  but it loads `<binary>.pck` beside itself and honours an `override.cfg` there, so an autoload
  added in `override.cfg` (an absolute path to a scratch script) drives it. Set
  `application/run/flush_stdout_on_print=true` there too, or its prints never arrive. Use
  `perf report --no-inline`: without it, report stalls for many minutes on addr2line.
- After all of that the release build runs at real time on this slow test box, standing and
  flying, and the profile is flat (scripts ~15 %, broadphase updates ~7 %, then animation and
  transform propagation). GPU cost on the Mac is still unmeasured here; the owner's F1 stats
  line is the next evidence to ask for if it still stutters.

## 9f. Stills, rain, fire and the GPU side, 2026-09-23 afternoon (builds 203-208)

The owner asked for Steam-quality gameplay stills and, again, for it to run well "without
taking away from graphics at all". What shipped, newest last:

- **CI had been red for two builds** on "lowest quality trims the crowd": staged chunk builds
  counted crowd room once and kept spawning into a cap Quality had lowered. Walkers now go
  through `CityStreamer.take_crowd_room()`. Two more smoke checks were flaky for the same
  reason - picking `peds[0]` / `peds[1]`, which can be in a chunk that is about to swap - and
  now pick the nearest pedestrians. Check the Actions run after every push; a red run publishes
  nothing and the owner silently keeps the old build.
- **Parked cars on the boardwalk shop roofs**: the shop strip follows the shore across the ends
  of straight streets. `Landmarks.covers()` keeps parking out of it.
- **Explosions** read as fire now (deep orange after one white-hot instant, smoke drawn behind
  the fire, soft particles, per-puff age and tint so it is not one flat cloud). Judge them only
  in Forward+: the Compatibility preview clamps and flattens all of it.
- **Rainy nights**: streets start wet, glossy tarmac with mirror puddles (SSR does the rest -
  check `raintest` style renders with the whole road forced to a mirror if you doubt it works),
  lit drops that fade near the lens, and the lens rain cut from ~1,800 drops to a few dozen at
  the edges. Freeway traffic pitches with the deck.
- **GPU**: `tools/gpu_profile.gd` + `tools/gpu_profile.py` (per-pass timings) and
  `tools/tri_split.gd` (per-category triangles, with and without shadows) are the measuring
  kit. The frame is triangle-bound: opaque, depth pre-pass and sun shadows are ~90 %. Note the
  depth pre-pass is disabled by Godot itself on Apple GPUs (`disable_for_vendors`), so on the
  owner's Mac the opaque and shadow passes are what count. Foliage, props and car bodies now
  cast shadows from lighter twins (CLAUDE.md, Performance): 9.4 M -> 7.7 M triangles on a
  downtown street, with before/after renders of the boardwalk's palm shadows matching.
  What is left, by the same measure: pedestrians 2.4 M (already LOD-biased and shadowless past
  45 m - the next lever is the crowd's own LOD chain), trees' main pass ~1 M (a batch per chunk
  is LOD0 whenever the camera's plane crosses it; smaller tree cells would fix it but cost draw
  calls), street props 0.9 M, cars 1.2 M.
- **Memory**: a city under lavapipe is 6-7 GB; two renders at once thrash the 16 GB box until
  even `ps` hangs. One render at a time. And `pkill -f` with a pattern that also appears later
  in the same shell command kills that shell - use a script file or a `[x]yz` pattern that the
  command line itself cannot match.
- **Later the same day (builds 210-215)**, owner: "the day/night cycle is too fast", "NPCs
  screaming ... limbs flying off from the rocket launcher", "graphics ... while ensuring the game
  is always still playable". Shipped: a 48-minute day; `Pedestrian.alarm()` panic with 12 real
  scream takes; rocket dismemberment (`Ragdoll.dismember()`, `LimbHider`, blood); worn road
  paint; shape-found glass on the sedan / pickup / van (their textures do not darken the
  windows, which is what made white cars look like ice); far pedestrians on welded bodies
  (6.6 M triangles on the street, from 9.4 M in the morning); limbs, far bodies and effect
  materials all prepared during the loading screen so the first rocket does not hitch. The
  `--nohud` flag skips the loading screen, so harness runs pay those costs on first use - do not
  mistake that for a regression. Debris lifetime is wall-clock, so in a 1 fps software render
  limbs vanish after a few frames; `still_shot.gd` raises it.
  Then the "ice-blue cars": with parking seeded (it used the global rng, so no two renders parked
  the same cars) an A/B with `CAR_PARAM=clearcoat_amount=0` showed the pale-blue pickup is dark
  red and the pale-blue sedan grey (`CAR_REPORT=1` prints every car's paint). The lacquer was
  mirroring the sky's lower hemisphere, which was pale haze for 27 degrees under the horizon;
  the cubemap pass now puts the street there. Same shot: glass towers in shade went from 16/255
  to ~75 once their reflection became emission instead of albedo.
- **Builds 216-220, same evening** (owner: "the sickest screenshots ... gameplay stills in
  steam"). Each of these was found by looking at a still and measuring it, not by guessing:
  reflections see the street (cars), glass reflection is emitted (black towers in shade), glass
  mirrors a fake skyline with bowed panes, the fireball has its own hot-core shader, debris is
  small wedges, crosswalk wear is speckled, the far chunks' ground has its colour back (it was
  black in every aerial - `append_from()` drops `set_color()`), far streets glow at night, sand
  is tiled at 2 m (footprints were half a metre), and rainy nights are dark and warm instead of
  daytime grey.
  Harness notes: edit a batch script only when nothing is running it - bash reads a script
  from disk as it goes, and inserting a line mid-run broke one after its last shot. Copy it
  and run the copy.
- **2026-09-24** (owner: "it's looking like gta San Andreas ... I need it to look like RDR2"):
  lock-on aim, guns held by IK, and every window is now a traced recess (`window_recess` in
  `building.gdshader`): set-back glass, lit jambs and sills, head shadow from the sun. The owner
  had been judging the GL previews, which have flat light; send Forward+ stills (or say which
  renderer a picture is from). Four agents were running on worktrees: weapon wheel, weapon
  models, a Blender hero and a Meshy hero; the owner then asked for the hero in a New Jersey
  mob tracksuit, which the current rig wears in the meantime (`Player.avatar_tracksuit`).
  The weapon wheel (hold Tab / LB: quarter-speed time, frosted-glass wheel,
  `scripts/ui/weapon_wheel.gd` + `shaders/glass_ui.gdshader`) came in from its agent branch the
  same night; it has only been judged on opengl3 stills so far.
- Store stills: `tools/glshot/still_shot.gd` (FX_AT / FX_SIDE / FX_TIME for explosions,
  `FX_AT_PED=1 FX_PED_PLACE=1` for limbs). The good ones: the gore shot downtown at 17:25
  (`--spawn=734.9,330,0,-5 --hour=17.4`, FX_AT=13 FX_RADIUS=9 FX_TIME=0.32), the skyline at
  17:45, the boardwalk at 17:50, the freeway at 18:00 and downtown rain at 21:20. The hills are
  still weak (next steps item 3).

## 9g. The guns, 2026-09-24

The owner called the box guns "horrible assets" and asked for RDR2, then swapped the gravity gun
for a shotgun. All three guns are now models from `tools/make_weapons.py` (Blender 4.2, run
headless with two threads; the CLAUDE.md Weapons bullet has the command and the node-name
contract). A full build is one to three minutes a gun, almost all of it the mask bake (a Bevel
node edge mask and local AO, 16 samples); `--nobake` exports flat colours in a second for shape
work. Look at a gun with `tools/glshot/weapon_shot.gd` (`WEAPON=0/1/2`, `YAW`, `PITCH`, `ZOOM`,
`FOCUS`; it lights with the city's own AgX, sun and fill numbers, so a finish judged there holds
in the street) and in the hands with `hero_shot.gd` (`DEBUG=1`). Only the opengl3 path was used.
On a machine shared with other agents, wrap Blender and every Godot render in `flock` on one lock
file; two lavapipe renders at once get OOM-killed.

Open: the rigs have no finger bones, so the hands sit flat on the grips rather than curling round
them (the wrist targets are right; the pose is the limit). The rocket that leaves the launcher is
still `rocket.gd`'s red primitive cylinder, not the olive warhead the model shows in its muzzle.
The shotgun's fire rate and knock numbers are first guesses (`fire_rate` 1.25, nine pellets of
9 impulse, `knock_base` 12 + 5 a pellet).

## 9k. The living sky, 2026-09-24

Owner: "helicopters, police choppers, news choppers, private jets flying thru the sky,
commercial jets taking off and landing at LAX". Built on an agent worktree; the rules are the
Air traffic bullet in CLAUDE.md. What a next session needs to know:

- **Where things fly and why.** Arrivals come up the basin from the south (a downwind leg at
  `AirTraffic.downwind_x`, x 1950), turn onto a 3 degree final along z 960 and land westbound
  on the south runway, touching down about x -210; departures line up at x -35 on the middle
  runway and climb out west over the sea, turning north-west or south-west. The real field's
  arrivals come straight in from the east over the city; ours cannot, because the east range is
  400 m high two kilometres from the fence (measured: `MacroMap.height_at()` along
  z 960 reads 145 m at x 2400 and 330 m at x 3000). A route that crossed it would reach the
  runway 100 m up even at a 5 degree descent.
- **The wanted system is `Police` (section 9h).** AirTraffic reads the most stars any node in
  the "wanted" group reports, and a police helicopter in pursuit whose searchlight holds the
  player with a clear line (`Helicopter.has_eyes_on()`: within 6 degrees of the beam, nothing
  solid between) calls `Police.report_sighting()` every quarter second, so the stars do not
  drop while it has him. Losing the helicopter (out of its light, under a bridge, inside) is
  how you lose the stars.
- **The runway protection zone** (`MacroMap.runway_clear_zone()`, 700 x 90 m off the east end of
  the south runway): `CityPlan.lots()` builds nothing in it, so the near and far city both lose
  the same lots. Without it the glide path met 20-30 m midtown roofs 150-400 m from the fence.
- **Every height the traffic avoids is read, not guessed**: `obstacle_top()` replays the plan's
  own lots and `lot_height()` (like Skyline), adds 10 m of roof plant, reads the freeway decks
  that really pass over a cell (`Freeway.segments_in()` returns its whole 160 m index cells,
  which first put a 24 m "deck" on the runway), and measures the landmarks from the far copies
  CityStreamer keeps. Change the city and the routes follow.
- **The one bug that mattered**: a kinematic body's velocity is derived from its motion per
  step, so spawning an aircraft at the origin and then moving it launched the player at
  ~170 km/s (he left the map in one frame, and every later check ran 60 km away). Aircraft are
  placed before they enter the tree now; anything else that spawns kinematic bodies far from
  where they are created has the same trap.
- **Tuning.** Traffic: `arrival_interval` 70 s, `departure_interval` 76 s, `private_interval`
  55 s, `max_aircraft` 10 (web 6). Approach: `glide_slope_deg` 3, `aim_inset` 190 m,
  `final_turn_radius` 750 m. Jets (`AmbientJet`): `approach_speeds` (92, 72, 61, 54) m/s,
  `rollout_decel` 4.0, `roll_accel` 3.5, `liftoff_speed` 56 - fast for an airliner, because the
  runway is 740 m. News: `news_orbit_radius` 170, `news_orbit_height` 140, `news_linger` 90 s.
  Police: `police_stars` 3, `police_orbit_radius` (80, 96), `police_orbit_height` 62. Helicopter:
  `cruise_speed` 42, `orbit_speed` 17, `searchlight_energy` 22, `searchlight_angle` 6.5.
  Damage: helicopters 80 hp (one rocket), private jets 70, airliners 140.
- **Cost, measured headless on this box**: the routes at load 77 ms (once, in the loading
  screen), a crossing route 7 ms and a private-jet arrival route 18 ms (each built when one
  spawns, every minute or so), a tick of eight aircraft including two police in pursuit
  0.24 ms. The obstacle cells are cached; the lots are only read for route points within
  420 m of the ground.
- **Stills**: `AIR=final|takeoff|news|police AIR_DIST=<m> AIR_SIDE=<m> AIR_CLEAR=1` on
  `tools/glshot/still_shot.gd` (opengl3 only for this work; see the usage in the file).
- **Not done / not verified**: nobody has heard the loops in the game or seen the searchlight
  shaft through real volumetric fog (Forward+ was off limits for this agent). Aircraft do not
  avoid each other: two arrivals are spaced by the schedule only, and a helicopter's route
  over a jet's is not checked. Departures pop into existence behind a fade at the line-up
  point; a watcher sees them appear. Arrivals fade out rather than taxiing to a gate. Smoke
  trails left in the air jump a kilometre on an origin re-centering (CPUParticles in world
  space; the rocket smoke already does this). Nothing shows aircraft on the minimap, and the
  lock-on does not target them. The runway protection zone reads as bare block paving up close
  (a lawn there would read better; the skyline would need the same green plate). The smoke
  log gains four `Parameter "material" is null` lines at shutdown, from the dummy renderer,
  only when the test's shot-down helicopter crashes in the street; a crash away from the street
  and two rockets into the road both leave none, and the gate does not match them, but the
  cause was not pinned down.

## 9h. Police and the wanted level, 2026-09-24 (agent branch)

The owner asked for "a police and star system", GTA-style but original. What is in, and what a
next session needs to know (the rules are the Police note in CLAUDE.md):

- **One node, one property.** `Police` in `scenes/levels/city.tscn`, group `wanted`, `stars` a
  plain int. The police helicopter was built on another branch at the same time and reads that;
  it can also call `report_sighting()` so its eyes keep the stars from dropping.
- **Crimes are hooked where they already happen**, not in the weapons: `Pedestrian.alarm()` (the
  one call every gun and blast already makes), `Pedestrian.knock()` and
  `Vehicle.drop_out_of_traffic()`. A new gun gets reported for free. Anything the police do
  themselves sets `Police.innocent` round the knock; forget that and a cruiser that clips a
  pedestrian gives the player a star.
- **Two driving modes, on purpose.** A physics car driving 200 m through a city grid on an AI
  will get stuck on a kerb, a lamp or a building in the first block; a kinematic car on the lanes
  cannot. So cruisers come in on the lanes (the traffic's own geometry, turning toward the goal
  at each crossing) and only become VehicleBody3D physics within `engage_range` of a player they
  can see - close enough that "steer at them, back out when stuck, stop and get out after three
  tries" is enough AI. Pooling has to strip the VehicleWheel3D nodes before freezing the body.
- **Officers are Pedestrians with an Avatar body.** That buys the knock, the ragdoll, gibs and
  the LOD tiers from Pedestrian and the hand IK from the hero's Avatar, with a `PoliceGun` (a
  Weapon, model and grips only) in the hands. They are taken OUT of the `pedestrian` group after
  `_ready()`, so the crowd cap, `trim_pedestrians()` and alarms never touch them; `LockOn` looks in
  `police` as well.
- **The smoke test turns the police off** for everything except `_test_police`, which checks the
  whole loop in about 25 s of game time: gunfire near a witness gives a star, a cruiser joins
  60+ m out and drives in, officers get out and hurt the player, five stars stays inside the caps,
  going down respawns 30+ m away with the stars and units gone, and out of sight the stars flash
  and drop one at a time.
- **Screenshots:** `STARS=3 POLICE=standoff|pursuit` on `tools/glshot/still_shot.gd` stages the
  units in front of the camera (`Police.stage_for_shot()`), because a software frame takes
  seconds and waiting for cruisers to drive in would take hundreds of them. opengl3 only.
- **Two things that were wrong the first time, both found by measuring.** A knock-down has to be
  judged a tick late (`Police.knocked_down`): `Weapon.tick()` fires, and so knocks the target
  over, before it raises the alarm that says it fired, so judged at once the first kill of any
  spree belonged to nobody - and judged by distance alone, a car nudged at a chunk build gave the
  player a star. And the first officers fired 54 rounds without one reaching the player, because
  every one went into the cruiser they were crouched behind (`_line_of_fire()` and the sideways
  step are the fix; `PoliceOfficer.rounds_fired` / `rounds_hit` are there to measure it again).
- **Known gaps.** (Fixed the same day, section 9o: cruisers now route along the streets and pull
  up at the kerb nearest the player; the next sentence is how it was.) Cruisers under physics
  steered straight at their target with no path finding, so
  a player on a roof or deep inside a block gets a cruiser that noses up to the nearest wall,
  backs off three times and lets its crew out there. There is no ground response off the street
  grid (hills, airport, port): the stars still decay normally, and the helicopter is what covers
  those. Officers are built when they get out (an Avatar each, a small hitch), not pooled. The
  tactical unit has no helmets and nobody has finger bones. The siren is one wail cycle with no
  yelp at close range and no Doppler. Nothing of this has been seen in Forward+ or at 60 fps:
  the light bar's HDR lenses and the night OmniLight are tuned on opengl3 stills only.

## 9i. The facade kit, 2026-09-24 (G2, first real-geometry pass)

Owner: "it's looking like GTA San Andreas ... it must be the same quality as RDR2". The biggest
tell left was that every building is a shaded box. `tools/facade_kit.py` (Blender 4.2, headless)
now models a kit of seventeen pieces into `assets/models/facade_kit.glb`, and `Building` places
them from its seed on every building near the camera. What a next session needs to know:

- **Regenerating it**: `blender -b --python tools/facade_kit.py` (the scratchpad Blender works:
  `.../blender_char/blender/blender-4.2.23-linux-x64/blender`), then `godot --headless --path .
  --import` - the cached-import trap applies to it like any `.glb`. The script prints every
  piece's triangle count and x range; the x range of a roofline run must stay exactly -1..1
  (the smoke test checks it) or the corner mitres break.
- **One mesh fits every building** because `shaders/facade_kit.gdshaderinc` bends it per
  instance: roofline runs are mitred at any corner from `INSTANCE_CUSTOM.r/.g`, surrounds and
  awnings are three-sliced from `.b/.a`. The rules the Blender side has to keep are in the
  generator's header; break them and the geometry still loads, it just folds wrong.
- **Per building, not per chunk.** A chunk-wide batch is one node for the whole block: it is
  never occluded and it fades as one piece 100 m across. Per building, frustum and occlusion
  culling and the distance fade all work.
- **Top-floor clearance.** A classical cornice hangs ~1 m and the top window heads sit
  0.3-0.5 m under the roof line (a slot window's ~0.1 m), so `_add_facade_details` shrinks a
  rich cornice up to a quarter, then falls back to the plain one, and lifts what is left up to
  `KIT_CORNICE_MAX_LIFT` so it stands in front of the parapet rather than over the windows.
- **Measured** (`tools/geo_count.gd`, opengl3, 800x600, one frame, same cameras; the base
  numbers come from a clean export of the parent commit, re-measured twice identically):

  | Camera | Triangles before -> after | Draw calls before -> after | Objects |
  | --- | --- | --- | --- |
  | default spawn (midtown, origin) | 9.70 M -> 8.51 M | 8651 -> 8707 | 23411 -> 23467 |
  | downtown `--spawn=734.9,330,25,-4` (glass towers) | 4.107 M -> 4.115 M | 3050 -> 3071 | 3081 -> 3102 |
  | brick mid-rise `--spawn=-96,-230,-62,10` | 6.95 M -> 6.21 M | 6230 -> 6708 | 6361 -> 6839 |

  Triangles went DOWN because the old procedural balconies and fire escapes drew to 480 m and
  the old roof props had no range at all, while the kit fades at 110-320 m; the near blocks
  carry more geometry than before. Draw calls rise where the kit is (up to ~10 nodes per
  building plus shadows; +8 % on the brick street, nothing downtown, where the glass takes
  none of it). Chunk build: ~3 ms more per building on this box, ~20 ms worst for a big
  brick block with a hundred balconies (headless, warmed; `scratchpad/facade/kit_time.gd`).
- The opengl3 path is flat-lit; nobody has seen the kit on Forward+ yet - the main session
  should, since the shadows from cornices, balconies and awnings are most of what it adds.
  Close-ups: `tools/glshot/building_shot.gd` with `CAM_POS` / `CAM_LOOK` (and `KIT=0` for
  the same seed without the kit), and `tools/glshot/kit_shot.gd` (`SET=wall|roof`) for the
  pieces on their own.
- **Not done**: storefront glazing and interiors as geometry, a kit per LA style (bungalow,
  deco, mission), string courses and plinths as mouldings (still boxes), and a LOD/impostor
  step between the kit's range and the far boxes.

## 9j. Blood, 2026-09-24 (owner: "I want more blood when people get shot")

Built on an agent branch while another agent swapped the gravity gun for a shotgun. What a
rifle round into a person does now, all in `WeaponFX` (tunables `blood_*` at the top of
`scripts/weapons/weapon_fx.gd`) with the body's side in `Ragdoll`:

- **One entry point for every gun**: `WeaponFX.bullet_wound(node, hit, dir, strength, knock)`
  takes the ray hit and duck-types the victim (pedestrian -> `Pedestrian.shot()`, body ->
  `Ragdoll.shot()`, limb -> `blood_gush()`). The rifle's `fire_ray()` calls it with
  `AssaultRifle.blood_strength`. The shotgun (merged in from main the same day) sums each
  person's pellets - bodies already down included - into one call at `Shotgun.blood_per_pellet`
  (0.45) a pellet, capped at `blood_strength_max` (4): a close blast of nine is four rifle
  rounds' worth, a stray pellet a small wound. Called per pellet it would also work: the first
  puts them down and the rest land in the ragdoll, which bleeds more for each.
- **The wound** (`blood()`): backspatter, an exit spray of lit glossy droplet meshes along the
  bullet (a fast jet inside a wider spray), an unshaded mist that dims itself at night
  (`shaders/blood_mist.gdshader`; the lit version was grey dust), a spatter plus creeping runs on any wall within 2.8 m behind (one ray), and
  five drops traced ballistically to where they land, each leaving a splat at the moment it lands.
- **The body**: a pool spreads from under the hips over 8 s once it rests (widened by later
  hits), drag smears while it slides, drips from the exit wound, a per-body stain on the
  clothes (`character.gdshader` `wound_0..3`) that rides the nearest bone and soaks outward.
  Rocket gibs bleed at 2.2, the stumps pump, torn limbs drip in flight and mark where they land.
- **Marks** are generated textures (albedo + normal + ORM) on Decals in Forward+ and on flat alpha
  quads in Compatibility. **Nobody has seen the Decal path yet**: the opengl3 stills show the quad
  fallback, and agents may not run lavapipe. The first Forward+ still of a shooting is the thing
  to check - colour (decal albedo through the atlas), wetness (ORM roughness 0.5 where thick: anything glossier mirrored the sky at the grazing
  angle every road splat is seen at, and measured brighter than the road on opengl3; with SSR
  on Forward+ a little glossier may look better, it is one `lerpf` in `_shade_blood()`) and
  which way the wall runs go (they should run DOWN; the decal V axis is local +Z, set to the wall's
  down direction in `_wall_splatter`).
- Stills: `still_shot.gd` `FX_SHOOT=3 FX_AT=8 FX_AT_PED=1 FX_PED_PLACE=1` (spray at
  `FX_TIME=0.15`; aftermath at `FX_SCALE=1 FX_TIME=9`; `FX_PED_WALL=1.4` for a wall).
- Pre-existing, not from this work: every headless run logs thousands of `Cannot set a buffer on
  a Multimesh` errors and one `get_meta ... 'shadow_twin'` from `multimesh_batch.gd` (the
  shadow-twin commit e2d3a2a; `get_meta(key, null)` is an error when the key is missing). The
  gate does not match them, so it stays green; they are worth a look.

## 9q. Street life, 2026-09-24 (owner: "GTA-level street life")

Signals that work, traffic that queues at them, people who cross on the walking figure, and
police who drive the streets. Built on an agent worktree; the rules are the Street life bullet in
CLAUDE.md. What a next session needs to know:

- **Nothing per signal ticks.** One clock (`TrafficSignals.clock`, advanced by `TrafficManager`,
  pushed as the `signal_clock` shader global) plus a seeded offset per junction. The lens shader
  lights a head from its MultiMesh custom data (offset, axis) and the lamp id baked in UV2; the
  cars ask `TrafficSignals.light()`, the crowd `walk()`. Change the cycle in `TrafficSignals`
  only: `PropFactory.signal_lens_material()` pushes it to the shader and the smoke test checks
  the copy. To stage a light for a test or a still, `TrafficSignals.force()` moves the shared
  clock (so every junction moves with it - fine for one junction at a time).
- **The hardware** is `tools/make_signals.py` (Blender 4.2 headless: `blender -b
  --factory-startup --python tools/make_signals.py`, then `godot --headless --path . --import`,
  commit the `.glb` and its `.import`). Every piece is bevelled with face-area weighted normals.
  Triangles: pole 1,376, arm 404, vehicle head 2,132, bracket 128, pedestrian head 980, button
  328, cabinet 740 (guards in `PropFactory.TRI_BUDGET`). The dimensions the placing code uses are
  `PropFactory.SIGNAL_*`; `tests/street_life_checks.gd` checks them against the loaded bounds.
- **Layout** (`CityChunk._add_signal_corner()`): the far-right pole of each approach carries
  its mast arm, scaled along its length to reach the innermost lane (6.6 m on a 14 m street,
  11.4 m on a 24 m avenue), one head per lane plus a side-mount head at 4.6 m, two pedestrian
  heads at 2.7 m facing back across the two crosswalks ending at that corner, and two buttons.
  One controller cabinet per junction. Each pole is one breakable prop. Draw distances: heads
  420 m (a lit lens is what reads a junction from blocks away), pedestrian heads and the cabinet
  160 m, buttons 70 m.
- **Measured** (`tools/geo_count.gd` `AB=Batch_sig_*,BatchShadow_sig_*`, opengl3, 800x600, the
  spawn camera, one frozen frame with and without): not taken yet - the shared render lock was
  queued for hours. Take it before the next geometry change here.
- **Traffic**: `TrafficManager._drive_streets()` - IDM car following per lane group, the stop
  line / stop sign / busy crosswalk / player's car as stationary cars ahead, a hard no-overlap
  clamp, stand-still once closed up (the IDM alone creeps forever), turns slowed and skipped when
  the target lane is occupied, pull-over for a siren. Tunables at the top of `traffic.gd`, group
  "Street driving": `accel` 2.4, `brake_comfort` 3.6, `brake_max` 9, `min_gap` 2.2, `time_gap`
  1.1, `stop_line_back` 3.7, `turn_speed` 6.5, `stop_sign_wait` 1.0, `amber_margin` 1.25,
  `siren_yield_distance` 40, `siren_shift` 1.2, `player_brake` 6. Signal cycle in
  `TrafficSignals`: `GREEN` 16, `AMBER` 3.5, `ALL_RED` 1.5, `WALK_TIME` 7 (42 s a cycle).
- **Pedestrians**: `cross_chance` 0.3, `cross_pace` 1.2, `kerb_wait` 0.7, `kerb_spread` 1.1,
  `stop_sign_patience` 0.8-2.6 s. They now walk round their ring by its corners
  (`_ring_route()`); straight lines between two sides of a block went through the buildings.
  **A real bug fixed on the way:** the walk steered by `global_position` (scene space) toward
  targets in the chunk's space (true world), so after the first origin shift - flying 1 km out -
  the whole crowd walked off toward points a kilometre away. It reads `position` now; `_scare()`
  converts the threat into the same space.
- **Police**: `StreetRoute` (A* over the intersection grid, `kerb_stop()`, `polyline()`), used
  by both of the cruiser's driving modes. Tunables on `PoliceCar`, group "Routing":
  `route_interval` 0.5 s, `route_moved` 10 m, `ram_range` 35 m, `corner_speed` 9,
  `u_turn_speed` 4, `route_brake` 7, `look_ahead` 6-16 m, `kerb_approach` 26 m. A dispatched
  cruiser stays on the lanes to the kerb point and only then goes onto physics to stop
  (`_pull_up()`). Handing it to physics on the last straight inside `engage_range` was tried and
  reverted: in the full smoke run, after the police and car checks had left wrecks about, the
  physics approach was knocked off the road and stuck 61 m short (175 of 934 samples off the
  carriageway); the lanes cannot be. Probed headless: dispatched 132 m out to a player mid-block,
  0 of 453 samples off a carriageway, parked 0.6 m from the kerb point; to a player at a
  junction centre from 168 m, parked in 10.9 s (the smoke test's engage window is 25 s since
  main raised it); a physics cruiser spawned 127 m out got there by road in 17 s, 0 of 1,060
  samples off - but that follower is the part to watch in a cluttered street (it has no idea of
  obstacles beyond backing off when stuck).
- **Checks** (`tests/street_life_checks.gd`, 16 of them, about 35 s of game time): the model and
  its placing numbers, the shader's copy of the cycle, heads on every signalised full-detail
  junction, the cycle's logic (never both green, an all-red, walking only across a red), live
  traffic never overlapping, a queue of three plus a fast fourth at a red (stops at the line,
  nobody over it, no overlap) and going on green, a car on green waiting for somebody on its
  crosswalk, a walker waiting through the steady hand, stepping out on the walking figure and
  joining the next block, and the cruiser to a mid-block player by road. The old "traffic car
  moved in 1 s" check now takes the farthest any car moved: the nearest car can simply be
  waiting at a red.
- **Stills**: `STREET=queue|crossing` on `tools/glshot/still_shot.gd` (opengl3 only for this
  work). Only two were rendered before the session ended - the render lock was queued for hours:
  `street_look1.png` (the spawn junction at noon, `--spawn=16,22,40,8 --hour=12`: signal heads,
  mast arms and walkers in the frame) and `street_queue_red.png` (`STREET=queue --spawn=14,50,8,4
  --hour=11.5`, framed badly: the camera is on the pavement and the queue is small in the
  distance). Still to take, commands ready: the queue from behind it, `FOV=50 STREET=queue
  --spawn=-0.8,50,-4,-3 --hour=11.5`; the same camera at `--hour=21.5` for the lit heads at
  night; people on the crosswalk, `STREET=crossing STREET_PEDS=10 --spawn=34,9.5,84,2
  --hour=16.5`. None has been seen in Forward+.
- **Bugs found on the way, all fixed:** a new street car was placed from `to_local()` under the
  already-shifted `TrafficManager` after an origin re-centre, so it appeared a whole shift away
  (cars now get their local transform before `add_child()`, which also avoids the kinematic
  velocity trap; loop, freeway and police spawns too); an officer could think once about a
  cruiser `Police.clear()` had already pooled (`is_inside_tree` errors); the smoke test's panic
  check picked the walker standing where the body it had just shot was flying, and the ragdoll
  knocked them down before their speed was read (it now skips anybody within 10 m of a fresh
  ragdoll). The smoke test's seed-rebuild check resets `WorldState.world_offset` under the live,
  still-shifted city, so the street checks run before it; anything positional after that point
  (the air traffic checks) is in a frame that disagrees with the nodes. The street checks put the
  player back where they found him, or the air checks' rocket leaves from a mid-block pavement
  and hits a building.
- **Not done / not verified**: nothing of it has been seen in Forward+ (HDR lamps, glow and the
  lens specular are tuned on opengl3 stills). Turning cars do not cross oncoming traffic with
  any care (a left turn is instant at the junction centre, as before), and cross traffic does not
  yield to a cruiser in the box. Stop-sign junctions stop everyone and then let them go without
  taking turns. Walkers still spawn and live on the ring of the chunk that built them; crossed
  to another block they vanish with their original chunk. Lamps throw no light on the street at
  night (the lenses glow; there is no OmniLight per head, deliberately). A physics cruiser that
  meets a traffic car head on is blocked by it (kinematic cars are immovable to physics) and
  backs off and tries again; traffic only pulls over for a siren on the lanes behind it.
  The geometry cost of the signals (`AB=Batch_sig_*,BatchShadow_sig_*` on geo_count) is not
  measured. **To continue:** take the three stills above and the geo_count A/B, then judge the
  lamps in Forward+ (`forward_shot.sh` at the queue camera, day and night) - the lens `energy`
  (3.2) and `ped_energy` (2.4) in `shaders/traffic_signal.gdshader` are the numbers most likely
  to need a change once glow is on.

## 9n. The downtown skyline, 2026-09-24 (owner: "a 1:1 match of DTLA skyline ... more buildings")

Built on an agent branch; the rules are the Downtown skyline bullet in CLAUDE.md. The decision
that shapes everything: **massing yes, names no.** Which towers stand where, their heights in
real metres, their silhouettes, crowns and facade character follow the real downtown; every name
(code ids `dt_*`, minimap labels) is invented and no crown carries lettering. What a next
session needs to know:

- **Where they are and why there.** The real grid is laid one real block to one game block on
  the default seed's downtown streets: the avenues at x 507.8 / 589.2 / 660.7 / 734.9 / 824.2
  and the streets from z 228 to 907. So the sail stands west of the first avenue; the drums,
  the black twins, the pyramid, the spire and the curved tower down the next column; the dark
  glass, bronze and white slabs and two South Park towers in the next; the round crown and the
  red pair up the hill; the rounded pair, the blue crown and the unfinished cluster to the east.
  City hall (`ziggurat_hall`, 810,160) is the civic branch's and sits north-east of the core, as
  the real one does; nothing of this branch is north of z 244 or west of x 416, so the civic
  centre, the station and the arena district (which another branch is placing west and south
  west of the core) have their ground.
- **The grid is pinned** (`CityPlan.PINNED_ROADS`, `_next_road()`): same roads on every seed,
  so fixed towers never land in a street. The pinned values are the default seed's, bit for bit
  (printed with `var_to_str`), so the default city is unchanged; a check walks another seed.
  If a future change moves the downtown grid, re-derive both the pins and the anchors in
  `Landmarks.all()` together, and the smoke test will say which tower left its block.
- **One mesh per tower.** `TowerMesh` extrudes outlines into tiers; the facade is the ordinary
  building shader in its `uv_facade` mode (UV.x metres round the outline, whole bays per face,
  UV.y 100+ blank wall), so curves get windows, rooms and lit offices. Crowns are a separate
  lit surface (`shaders/tower_crown.gdshader`), obstruction lights reuse the aircraft light
  billboards. A whole tower is 60-1,900 triangles (the balconied South Park towers 3-7k); all
  nineteen are about 25k and build in ~150 ms, once, at load - the far copy and the detailed one
  share the mesh. Each carries an occluder, so the towers now also hide the city behind them.
- **One table** (`LandmarkDowntown.TOWERS`) holds every tower's anchor, radius, height, plan
  (checked against the built geometry by the smoke test), crown, and an APPROXIMATE real position
  in metres east/north of `REAL_ORIGIN` (34.0500 N, 118.2550 W) with an approximate real
  footprint, for the owner's next step: the whole downtown re-laid 1:1 (real blocks, real
  streets, true distances), other real areas as 1:1 replica areas with seeded filler between.
  `real_grid()` rotates a real position into the real street grid's frame (avenues about 45
  degrees east of north). The real positions are from memory of public maps, good to perhaps
  +/-50 m: check them before building on them. `Landmarks.all()` appends the table's rows
  (`LandmarkDowntown.entries()`), so a re-lay changes the table, `CityPlan.PINNED_ROADS` and
  `MacroMap.downtown_core`, and nothing else.
- **The infill** (`MacroMap.downtown_core`, DISTRICTS DOWNTOWN `core_*`): the blocks between the
  towers get 40-205 m towers (median ~75, a quarter over 130 m), no slabs, fewer pocket gardens,
  more stone. The old downtown boost lerped the top to 368 m, so generic towers could out-top
  the landmarks.
- **Measured, and what was not.** Geometry, headless: the nineteen towers are 25k triangles in
  all and 3-5 surfaces plus one light billboard each (so roughly 60-100 draws for the whole
  skyline, casting included), built in ~150 ms at load. CPU, headless, the smoke test's
  downtown teleport (`update_streaming(true)` at 742,423): 10.7 s against 10.3 s on the parent
  commit, on a box loaded by other agents (+4 %, inside the noise). **tools/geo_count.gd, measured after the merge** (opengl3, 800x600, the avenue `-- --spawn=589.2,860,0,12,2`): 6.20 M triangles / 8,078 draws / 20,588 objects on the parent commit 044e076 against 5.20 M / 5,412 / 17,976 with the skyline - cheaper, because the towers' occluders hide the blocks behind them. The south-west aerial (`-50,1250,-43,5,80`) did not finish inside geo_count's 600 s on this box either side; measure it on a quieter one.
- **Not done / not verified**: nothing here has been seen in Forward+ (the renders were all
  opengl3; the box was full of other agents' lavapipe renders). Crown glow and the lit offices
  on curved towers want a Forward+ dusk still. The towers have no interiors or lobbies, no
  street-level retail beyond the storefront band, and the plazas (fountains, sculpture) are a
  few boxes. Bunker Hill is not a hill: the relief is flat under landmarks. Collision is one
  convex hull per tier, so the notches of the round tower's wings are filled in. The generic
  core towers are the city's usual boxes; the next step up is a glass-tower facade kit.

## 9l. How the 2026-09-24 session ran (read if you inherit a half-merged day)

- The owner asks for many big features at once and wants speed, so the work went out to
  background agents in git worktrees (`.claude/worktrees/`, ignored), each told to commit on
  its own branch, merge origin/main before reporting, and never push. The main session merges
  each branch, runs `tests/headless_check.sh`, pushes to main and sends screenshots.
- One 16 GB box is shared, and a Forward+ (lavapipe) city is 6-7 GB, so every render goes
  through `flock <scratchpad>/render.lock <command>`. Headless checks run without the lock.
  An OOM-killed render prints `Killed` in its log and leaves no png. flock is not a queue:
  whoever asks next may win, and on a busy afternoon jobs waited over an hour. A GL
  (opengl3) job is ~4 GB, so the main session runs its own GL-only jobs (geo_count, preview
  stills) under a second lock, `<scratchpad>/gl2.lock`, alongside whatever holds the main
  one; never put a Forward+ job on it (two lavapipe cities do not fit in 16 GB).
- Full smoke tests are ~2.5 GB each, and three of them plus a render OOM-killed a gate (exit
  137, `Killed`, `dmesg` shows `Memory cgroup out of memory`). Every full check now runs
  through `<scratchpad>/gate_slot.sh <command>`, two slots on `gate1.lock` / `gate2.lock`.
  An exit 137 is memory, never the code: rerun it inside a slot.
- A smoke check that fails once under heavy load (five or six Godot processes on the box) is
  rerun in isolation before it is believed: `air_probe.gd`-style scripts that load the city
  and run one checks file (`load("res://tests/air_traffic_checks.gd").new().run(t, city)`
  with a stand-in `t` that has `_check()`) take three minutes instead of fifteen.
- Merges conflict mostly in the docs (every agent appends a decisions-log entry and a handoff
  section): keep both sides and renumber the sections.
- CI's box is slower than this one and drops to Quality LOWEST (thinner crowd, fewer cars), so
  tests that pick "the nearest pedestrian" or "cars[0]" are timing-sensitive there. Two such
  checks failed on build 231 and were hardened; if a check passes here and fails on CI, look
  for that first.
- Merged that day: window recesses, tracksuit then the Blender hero, weapon wheel, Blender guns
  and the shotgun, rocket warhead and smoke trail, far-glass emission, police and wanted stars,
  facade kit, blood, air traffic, the city ambience, the lens pass (grain, fringe), night GI,
  the downtown skyline (9n), and a helicopter fix (an orbit holds its whole ring above the
  tallest thing on it: CI 241 caught the news chopper dipping between towers). In flight when
  this was written: a studio pass on the hero,
  the arena district and civic centre, traffic signals and crosswalks with police routing,
  the Redondo Esplanade into Palos Verdes at 1:1, MacArthur Park with street encampments, and
  GTA-style distance LOD tiers. Next after the civic merge: a 1:1 re-lay of the downtown grid
  (the skyline's `LandmarkDowntown.TOWERS` and the civic `CivicSites` tables both carry
  approximate real positions for it). The unused Meshy hero is
  on branch `worktree-agent-a5cb589744a1759b9` (not chosen).

## 9m. The city's sound, 2026-09-24 (agent branch)

Owner: "the city should SOUND like a real city, AAA-style". Until now the only ambience in the
game was the weather's rain loop: `ambience_city` and `wind` had shipped since build 104 and
nothing ever played them. The rules are the Sfx and Ambience bullets in CLAUDE.md. What a next
session needs to know:

- **Nobody has heard it.** Every level, rate and crossfade was set by measuring the files and by
  maths, under the Dummy audio driver; this container has no speakers and no ears. The first thing
  to ask the owner for is ten minutes of play with the sound on: downtown at noon, a freeway deck,
  the beach, the hills at night, a rocket at close range, the weapon wheel, rain from inside a car.
  The knobs they will ask about are `Ambience.ambience_db` (everything), `layer_db` (per layer),
  `ONE_SHOTS[*].db` / `unit` and the rates in `rates_for()`, `pass_db` / `car_roll_db` (the
  street's own cars) and `blast_duck_db` / `slow_duck_db`.
- **Levels.** Beds are all cut to -22 dB RMS and recorded so in `AMBIENCE_LOUDNESS_DB`, so after
  Sfx's trim they sit level with each other and `layer_db` is the whole mix. With the defaults,
  downtown at noon sums to roughly -28 dBFS RMS against a rifle round's -18 dBFS loudest window
  (point-blank): the city under the gun by about 10 dB, well under its peak. That is a guess on
  paper and the most likely thing to need moving.
- **What plays where** (checked by `tests/ambience_checks.gd`, which is the fastest way to see the
  mix: it prints every level it asserts): downtown noon city 1.0 with ~6 horns a minute; downtown
  night city 0.45, far traffic 0.85; the beach surf 0.83 from the west, 5 gulls a minute, none in a
  storm, louder surf in one; the hills birds 0.6 by day, crickets 1.0 and ~0.9 coyotes a minute at
  night, nothing in rain; the suburbs dogs and birds; the airfield 1.0 (downtown hears 0.08); the
  port hum plus ship horns and cranes; a freeway deck 1.0, 0.22 at 300 m; 400 m up the street
  goes and the wind and gale come in.
- **Sources.** Freesound's HQ previews, each page checked for the CC0 deed and nothing else, and
  each description read: two first picks were dropped on the description alone (credit made a
  condition; an AI-generated siren). `tools/ambience_audio.py` is the whole pipeline - `search`
  (CC0-filtered), `get` (verify the page, save it, fetch the preview into `build/audio_src/`),
  `build` (the clip table: spans, filters, loop cuts, levels) - and prints the loudness numbers
  Sfx wants. Re-run `build` for one clip by name prefix; then `godot --headless --path . --import`.
  The proxy is slow (~70 KB/s), so it fetches only the first 2.6 MB of each preview.
- **Performance.** 16 bed/emitter players (only the ones with a level play; a faded bed stops),
  5 pooled one-shot voices, 3 traffic voices, 2 pass-by voices. The survey measured 0.9 ms
  headless; per frame it only eases gains and moves at most nine voices. Bus effects: one reverb,
  two low-passes (switched off when open), one compressor.
- **Tools and checks.** `tools/lot_coverage.gd` (`FILL=0|lot|1`, rows per district, FREEWAY,
ROW_CELLS, MACARTHUR_SE); `tools/glshot/block_shot.tscn` (a few FULL blocks alone, `EYE`,
`SHOTS`, `BLOCKS`, `GEO=1`, `YARD_FILL=0`); `still_shot.gd` `YARD_FILL=0` (the A/B; `SPLIT=1`
counts `YardGround` / `YardWalls` in the LotFill line). `tests/lot_fill_checks.gd` (25 checks in
the smoke test): bare share before and after round the bookmarks, the right of way out to its
cells, the shader kind tables, the campus plan, the MacArthur plaza, the beach plans (walk
streets, drives, house heights, no yard piece under a house or on another), one mesh each on the
right shader for a beach, a campus and a freeway block, the budgets, a LOD build with no yard
meshes, and a beach and a freeway block built with the fill off being the same block.

**Not done / not verified.** The web build plays the plain mix (sample playback skips bus
  effects: no reverb, no muffle, no ducker). Traffic voices ride only the TrafficManager's street
  and freeway cars - parked cars, police and the airport loop are silent unless driven (the police
  have sirens). The pass-by timing is maths on positions sampled every 0.15 s; it has never been
  heard lining up. The canyon reverb reads eight horizontal rays at camera height, so it does not
  know how tall the walls are (downtown density stands in for that). No interior sound (there are
  no interiors). The crowd walla is one Hawaiian shopping street; a second take would help. The
  near "traffic" bed is still the old IgnasD highway recording.

## 9p. The Esplanade, the first 1:1 replica area, 2026-09-24 (agent branch)

Owner: "we are basically picking certain 1:1 replica areas and then filling them in between with
whatever". The rules are the replica bullets in CLAUDE.md (technical rules and conventions);
the table is `ReplicaAreas.ESPLANADE`. What a next session needs to know:

- **What it is.** Knob Hill down the Redondo Esplanade (1880 m straight, bearing 173, on a 12-16 m
  bluff), the south curve past the Avenue I car park, the Avenue I roundabout, Paseo de la Playa
  (the one compression: 0.8 km for 1.6), Palos Verdes Blvd / Dr N up the peninsula's north face.
  4.57 km in all, 2.9 km of it town. The owner's three Street View captures are the reference; the
  camera spots that reproduce them are under "How to take the stills" below (EYE= values on
  `tools/glshot/still_shot.gd`, a Street View lens ~2.5 m up, vertical FOV ~75 on the portrait
  shots).
- **The map moved to fit it.** The coast between the Redondo pier and Malaga Cove is the
  replica's waterline table; north of it the basin's sine eases onto it over
  `MacroMap.replica_coast_blend`; the Palos Verdes headland is an ellipse (`peninsula_center`,
  `peninsula_axes`, `peninsula_axis_bearing`) whose crest (`peninsula_crest`) was fitted to the
  photos' skyline seen from 1718 Esplanade (mean error a quarter of a degree, probe in the
  session's scratchpad: sample the ridge's elevation angle against azimuth from the camera and
  compare to the traced photo ridge); the bay is south of it. The ocean shader carries the same
  shapes (`ocean.gdshader` main_coast_x / headland_*), pushed by `Weather._push_ocean_shape()`,
  and the smoke test guards the shader defaults. The piers and the airport did not move.
- **Build path.** `CityChunk.begin_build()` asks `block_role()`; role 1 skips the seeded block and
  `ReplicaBuilder.attach()` adds the replica's steps (see CLAUDE.md for the list and the ownership
  rules). Every chunk near the route that is not role 1 (ocean, hills, the blocks beside it) still
  gets the steps for whatever path segments, lots or features it owns.
- **Houses.** `ReplicaHouses`: walls are cut round every opening, reveals, frames, glass on
  `house_glass.gdshader`, garages with panel grooves, hip/gable clay roofs (`roof_clay`, UV along
  the eave and up the slope - triplanar would run the barrels the wrong way on two of four
  hips), coped parapets, balconies (steel or glass), garden walls, planting. The footprint is
  `ReplicaAreas.house_frame(lot)`, used by the kerb parking (no car across a driveway) and by the
  frontage's own overlap test (on the inside of the curve the lots fan in; a house that would hit
  its neighbour is left out). Far chunks draw each house as a `lod_box` plus a roof prism.
- **Traffic.** `ReplicaTraffic` keeps `cars_per_direction` a side within `spawn_max` of the player
  while the player is within 250 m of the route; lane changes happen only where two lanes merge
  into one. Grid cars U-turn when they would drive into the corridor; they cannot turn onto the
  Esplanade yet.
- **People.** `ReplicaWalker` (a Pedestrian that strolls along the walkway or the inland
  pavement rather than round a block's ring) fills most 26 m slots of each pavement a replica
  chunk owns, inside the crowd cap; the backfill blocks carry nobody yet.
- **Verified so far - maths and meshes, NOT pictures.** `tests/replica_checks.gd` (24 checks,
  in the smoke test) and top-down rasters of the built chunk meshes (every surface drawn from
  above by a scratch probe: road, kerbs, mouths, frontage, car park, roundabout, condo, the
  town's end) are all that has looked at it. **No rendered still of it exists yet**: the three
  framing stills and the geo_count before/after were queued on the shared render lock behind a
  dozen jobs and the session ended first. That is the first thing to do next, then compare
  side by side with the owner's three Street View captures and fix what reads wrong.
  The last full headless check on the branch passed 364 of 365. The one failure was "replica
  traffic spawns a car": late in the run the physics budget is full and `_spawn()` quietly
  built nothing. The check now spawns with `force` (0569b16). The replica checks pass 24/24
  against a stand-in city after the fix, but the full check has NOT been re-run since. The
  thousands of "Cannot set a buffer on a Multimesh" lines in that log come from main's shadow
  twins (`MultiMeshBatch.build()`, `twin_mm.buffer = mm.buffer`) under the dummy renderer.
  They were there before this branch and are not on the check's tripwire list.
- **How to take the stills** (opengl3, `tools/glshot/still_shot.gd`, `FRAMES=50`, `--hour=12
  --nohud --quality=0 --weather=clear`, under the render lock):
  1718 Esplanade inner northbound lane, portrait: `EYE=-449.26,14.42,3375.82,-173,-5 FOV=75`
  `--resolution 540x1170 -- --spawn=-449.3,3375.8,-173,-5`; outer lane: `EYE=-446.98,14.42,
  3375.54,-173,-5` (`--spawn=-447.0,3375.5,-173,-5`); 1799 Esplanade at the curve, landscape:
  `EYE=-441.66,9.94,3534.58,-178,-1.5 FOV=44 --resolution 1400x646 -- --spawn=-441.7,3534.6,
  -178,-1.5`. EYE is a true world point and yaw/pitch in degrees (yaw 0 north, 90 west) for a
  free camera; heights are the road top + 2.5 m (a Street View lens), recomputed if the profile
  changes. Frame cost: `tools/geo_count.gd` at `--spawn=-449.3,3375.8,-173,-5` with and without
  `-- --no-replica` (MacroMap then builds the seeded city in its place).
- **Tools and checks.** `tools/lot_coverage.gd` (`FILL=0|lot|1`, rows per district, FREEWAY,
ROW_CELLS, MACARTHUR_SE); `tools/glshot/block_shot.tscn` (a few FULL blocks alone, `EYE`,
`SHOTS`, `BLOCKS`, `GEO=1`, `YARD_FILL=0`); `still_shot.gd` `YARD_FILL=0` (the A/B; `SPLIT=1`
counts `YardGround` / `YardWalls` in the LotFill line). `tests/lot_fill_checks.gd` (25 checks in
the smoke test): bare share before and after round the bookmarks, the right of way out to its
cells, the shader kind tables, the campus plan, the MacArthur plaza, the beach plans (walk
streets, drives, house heights, no yard piece under a house or on another), one mesh each on the
right shader for a beach, a campus and a freeway block, the budgets, a LOD build with no yard
meshes, and a beach and a freeway block built with the fill off being the same block.

**Not done / not verified.** The Knob Hill end is a kerb and
  a pavement (the grid's streets run past it); north of it the pier plaza is the seeded
  landmark's. The roundabout's inside (west) corner, where the ocean-side lines of a right turn
  fold, is covered by the ring's planting rather than modelled. The car park's sea wall is ~5 m
  because the sand is flat at 0.5 m; a raised backshore would make it the real 2-3 m. The Palos
  Verdes hills carry HillRoads' rim road and estates and Skyline's scrub, not the photo's dense
  house cover. Nobody has driven it on a Mac.

## 9o. Downtown's civic set, 2026-09-24 (agent branch)

Owner: "downtown must match real downtown LA, we need staple center we need all day". The
decision: real FORMS in their real places relative to the core, every NAME invented (the naming
rule in CLAUDE.md). The rules are the "Downtown civic set" bullet in CLAUDE.md; what a next
session needs to know:

- **Where things are (default seed 1337; each one fills the block its anchor falls in):**
  arena (352, 475) block 3,4; entertainment plaza (352, 378) block 3,3, north of the arena across
  the street; hotel tower (456, 378) block 4,3; convention centre (352, 596) block 3,5; city hall
  (876, 171) block 9,1; park (876, 59) block 9,0; concert hall (876, -50) block 9,-1; museum
  (782, -50) block 8,-1; station (1091, -50) block 11,-1. Downtown's own grid is narrow there
  (the blocks at x 520-723 are 48-57 m wide), which is why the arena district sits in the
  100 m wide column at x 302-402 and not closer in.
- **One table: `CivicSites.SITES`** (`scripts/world/civic_sites.gd`) holds each landmark's
  anchor, relief radius, footprint (its own frame), yaw (quarter turns, counter-clockwise from
  above), a note on which way it faces, and the REAL building's approximate lat/long, size and
  facing. `Landmarks.all()` takes its entries from it; `CivicSites.build()` puts a pivot at the
  site centre turned by the yaw, with the landmark's own StaticBody3D under it, and the builders
  (`LandmarkArenaDistrict.build(id, site, y0, ...)`, `LandmarkCivicCenter.build(...)`) work in
  a frame centred on the site; their crowd rects and the park's grass go back to the world
  through `CivicSites.to_world()` / `rect_to_world()`. `CivicSites.yaw_override` turns one
  without editing the table (the smoke test turns the station a quarter). For the 1:1 re-layout
  of downtown the real positions share the skyline table's frame (section 9n): `CivicSites
  .real_en(id)` is metres east / NORTH of `LandmarkDowntown.REAL_ORIGIN`, exactly like a tower's
  `real`, `real_metres(id)` the same point with z south, and `real_grid(id)` the point turned
  onto the real street grid the way `LandmarkDowntown.real_grid()` turns a tower. Approximately:

  | id | real east, north (m) | real size (w, h, d) m | game anchor now |
  |---|---|---|---|
  | arena | (-1135, -774) | 200 x 45 x 170 | (352, 475) |
  | live_plaza | (-1061, -597) | 280 x 30 x 180 | (352, 378) |
  | live_hotel | (-987, -531) | 70 x 203 x 35 | (456, 378) |
  | convention_center | (-1245, -1106) | 330 x 25 x 170 | (352, 596) |
  | ziggurat_hall | (1135, 409) | 140 x 138 x 110 | (876, 171) |
  | civic_park | (830, 663) | 500 x 0 x 110 | (876, 59) |
  | concert_hall | (480, 586) | 110 x 40 x 90 | (876, -50) |
  | lattice_museum | (443, 487) | 70 x 36 x 60 | (782, -50) |
  | pueblo_station | (1706, 686) | 260 x 38 x 70 | (1091, -50) |

  None of the sites overlaps a skyline tower: the towers stand east of x 416 and south of z 244,
  and the only civic block inside that corner is the hotel's (x 416-496, z 345-410), which is
  the block west of the five-drums hotel. Two things the re-layout has to decide that the
  tables cannot: the real grid is turned off north (`LandmarkDowntown.GRID_BEARING_DEG`) while
  the game's is axis-aligned, and the real
  footprints are bigger than one of today's blocks, so a 1:1 site needs a block that big (or a
  superblock with its through-roads closed, which traffic and the minimap do not support yet).
  Only quarter-turn yaws are supported, because a site is an axis-aligned block.
- **Block sites are the mechanism to reuse.** A landmark that says `"site": "block"` gets its
  block to itself (`Landmarks.claims()` in `CityPlan.block()` / `lots()`), and its builder reads
  `Landmarks.site_rect()` and fits inside it. The pavement ring, its lamps and trees, the parked
  cars in the kerb lanes and the block's own walkers all stay, which is right: these buildings
  have streets round them. `Landmarks.crowds()` adds plaza crowds as ordinary pedestrians.
- **Scale is compressed on purpose.** One block each: the arena's bowl is ~80 m across (the
  real one is ~200), city hall's tower tops out at ~140 m (real 138), the hotel slab is 196 m
  (real ~200). Merging blocks into superblocks would mean closing road segments, which traffic,
  the police, the minimap and the far tier all assume never happens - not attempted.
- **The toolkit**: `LandmarkGeo` (geometry), `LandmarkMats` (materials), `LedScreen` (screens),
  and six shaders sharing `shaders/landmark_common.gdshaderinc`. Nothing in them is specific to
  these buildings; a new hand-modelled landmark should use them rather than `Landmarks._box()`.
- **The concert hall is a Blender model** (`tools/make_concert_hall.py`, seconds to run, no bake)
  with a `Collision` object the game turns into a trimesh; re-import after regenerating it.
- **Checks** (`tests/civic_checks.gd`, about a second): every one listed and claiming its block,
  no freeway over a site, far versions, geometry inside its own block, collision, rays onto the
  roofs you can land on, crowds on open ground, the table itself, and a quarter turn by yaw.
- **Frame cost.** What each one adds when detailed (own triangles / draw surfaces / prop
  batches): arena 6.0k / 12 / 20, plaza 0.6k / 12 / 17, hotel 1.2k / 5 / 3, convention centre
  2.0k / 5 / 5, city hall 6.7k / 9 / 5, park 0.7k / 6 / 16, concert hall 36.2k (the model) /
  5 / 4, museum 12.9k / 4 / 3, station 2.6k / 13 / 15; a far version is 0.1-1.2k triangles in
  1-10 surfaces and at most one batch. Whole frames at the landmarks (opengl3 stills, the
  STATS line of `tools/glshot/landmark_shot.gd`): plaza by day 3.2 M triangles / 1,853 draws,
  city hall and park 4.4 M / 2,825, concert hall 3.2 M / 1,862, station 2.9 M / 1,892, arena
  at dusk 3.7 M / 2,321, plaza at night 3.1 M / 1,570. The same-camera before/after (`tools/horizon_probe.gd`, 800x600, spawn
  352,405 facing the arena) has only its before side, 5.33 M / 4,054 draws on the parent
  commit: the after run was OOM-killed and then timed out on the shared box. Take it first.
- **Tools and checks.** `tools/lot_coverage.gd` (`FILL=0|lot|1`, rows per district, FREEWAY,
ROW_CELLS, MACARTHUR_SE); `tools/glshot/block_shot.tscn` (a few FULL blocks alone, `EYE`,
`SHOTS`, `BLOCKS`, `GEO=1`, `YARD_FILL=0`); `still_shot.gd` `YARD_FILL=0` (the A/B; `SPLIT=1`
counts `YardGround` / `YardWalls` in the LotFill line). `tests/lot_fill_checks.gd` (25 checks in
the smoke test): bare share before and after round the bookmarks, the right of way out to its
cells, the shader kind tables, the campus plan, the MacArthur plaza, the beach plans (walk
streets, drives, house heights, no yard piece under a house or on another), one mesh each on the
right shader for a beach, a campus and a freeway block, the budgets, a LOD build with no yard
meshes, and a beach and a freeway block built with the fill off being the same block.

**Not done / not verified.** Only judged on the opengl3 path (Compatibility): no Forward+
  render yet, so SSR on the steel and glass, SDFGI under the arena's canopy and the night
  floodlights under AgX are unseen. A detailed landmark is built in ONE chunk step. Warm
  (caches full) on this shared, loaded box: museum 68 ms (its veil is 12.9k triangles), arena
  35, city hall 35, station 15, convention centre 11, the rest under 8; a far version is 1-10 ms.
  Cold, in a bare tree with nothing loaded, the first detailed build was 0.1-0.8 s (the arena's
  palms, trees, textures and LED atlas; a running city has most of that loaded already, but it
  was not measured there). That is a hitch as the block streams in; splitting a builder into
  steps (like `CityChunk`'s own) is the fix. The concert hall's model is paid on the loading
  screen by its far copy. Far versions
  are the same builders at low detail with no LOD chain between. Yaw is quarter turns only.
  Names on the LED slides and signs are invented, but nobody has read every slide for an
  accidental real brand - worth a look.

## 9r. Westlake: MacArthur Park and the encampments, 2026-09-24 (agent branch)

Owner: "you should also have MacArthur Park and a bunch of homeless tents up on random streets in
downtown and people slumped over". The rules are the Westlake bullet in CLAUDE.md. It is depicted
as the street a realistic LA game shows, never as a joke; the code's words are neutral
(`encampment`, `rough_sleeper`, `slumped`). What a next session needs to know:

- **STATE (updated 2026-09-24 evening): the encampments and MacArthur Park are both ON.** The
  leak that held the park off had two causes. (1) In `TrafficManager._drive_street()`, a car
  that had to turn because the road ahead was closed, and found the lane it was turning into
  occupied, gave up the turn and drove straight on - into the closed road and through the lake.
  A forced turn now waits at the centre of the crossing (`t.forced`). (2) The bigger one, and
  test-only: the checks' teleport helpers called `CityStreamer.recenter()` from the process
  phase. The kinematic traffic cars were then put back where the physics server last had them
  at the next sync - the whole shift away, 270-500 m - and the next tick snapped each onto a
  lane with the wrong `along`, dozens of them on the park's closed roads. The game only
  re-centres inside the physics tick (the streamer's `_physics_process`), where it is fine; the
  helpers (westlake, masjid, air traffic, the smoke test's own) now `await physics_frame`
  first. A scratch probe showed 66 and 70 jumps from the process phase, none from the physics
  phase. (3) Also test-only: the smoke test's seed-rebuild check builds a second city, whose
  `_ready()` zeroes the shared `WorldState.world_offset` under the first; every far chunk built
  before it then stood 100-400 m from where the checks after it thought (their relief floors
  over the lake, the helicopter checks' "inf m above the ground"). The check now puts the
  offset back. That is why the isolated check never saw any of it. To work on it, set
  `LandmarkMacArthurPark.enabled = true` before the city scene loads (Landmarks.all() is built
  once) - the westlake checks then run the park's half too. The table rides under the entry's
  `"area"` key: the civic set uses `"site": "block"` for something else (Landmarks.claims()).

- **Where the park is, and why it moves later.** `LandmarkMacArthurPark.SITE` holds the real
  place (34.05861 N, 118.27750 W: 2,300 m west and 1,158 m north of Pershing Square, 460 x 310 m,
  35 acres, Wilshire through the middle at a real heading of 297 degrees, the lake about 4.3 m
  deep) and, separately, where it stands on today's compressed map: west-north-west of the
  downtown core between Park View (x 87), Alvarado (x 517), 6th (z -214) and 7th (z 86), Wilshire
  at z -104. The 1:1 downtown re-lay moves it by editing that table; the grid is not turned to
  Wilshire's real heading (every block is still axis-aligned), `yaw_deg` is there for the day it is.
- **It is ON the grid, not over it.** CityPlan snaps the site to whole blocks and closes every
  road inside the four edges except Wilshire (`road_open()`). Nothing is removed from the plan,
  so road indices, block seeds and every block round the park are exactly what they were. Any
  new system that puts things on roads must ask `road_open()`: the ones that do today are listed
  in the CLAUDE.md bullet. The trap that bit twice: a road always reads open inside the crossing
  road's own width, so probe an arm past `road_width() / 2` (traffic turns and the police's
  `_drivable` both first looked 3-5 m out and turned cars into the park).
- **Per-chunk park.** Each site chunk builds its own part (`site_steps()`); only the fountain jet
  and the boathouse are the landmark proper, built by the chunk holding the anchor, with a far
  copy. Two halves: the north one lawns, the 7-a-side pitch and the bandshell; the south one
  the lake, promenade, palm ring and boathouse on the north shore. Walkers use the park's own
  crowd rects.
- **The lake is below the city's ground box.** CityStreamer's GroundBody is a 14 km box with its
  top at 0; the lake floor is at -1.2. The lake-shaped `LakeSplash` area adds a collision
  exception between the GroundBody and each player or props body in it (`_sink`) and takes it
  away on exit or when the chunk unloads. Wheel rays and ray queries ignore exceptions, so a
  car that lands in the lake rides on the box, chassis awash, and a test ray has to exclude the
  GroundBody by hand (`tests/westlake_checks.gd` shows how). `under_city_ground()` lifts the
  player out below -1.5, so keep `FLOOR_Y` above that.
- **Encampments.** Hash-seeded only (seed, road, block, face): about a third of downtown's
  streets carry most of the camps. A camp is a run of "units" (tent, tent under a tarp, tarp
  mound, cart, bed, sitter, bags, bike, parts, slump) laid along the ground-storey walls
  (`StreetDetail._footprints()`), keeping doorways, 9 m at the corners, 1.3 m round every lamp,
  hydrant, meter, shelter and trash can, and a 2.3 m kerb-side strip that the block's walkers
  are narrowed to. The people are spawned BEFORE the block's walkers (steps right after the camp
  step), or downtown's crowd had used the cap and the camps were empty.
- **The poses.** The rigs only have idle, walk and run, so `RoughSleeper` writes bone rotations
  over a paused idle clip: each pose is a table of segment directions in rig space, solved per
  rig from the idle frame (the fix_arm_pose lesson: no per-model numbers). SIT has two variants
  (knees up, legs out), LIE lies on its side on a mattress or cardboard, SLUMP stands folded
  forward at the hips with the head hanging, swaying. Gunfire: sitting and lying people get up
  and flee, then walk back and settle; slumped people cower in place. Judge poses with
  `tools/glshot/camp_shot.gd` (every pose on a row of rigs against a wall, `SEED` for other rigs,
  `COWER=1`).
- **The kit.** `tools/encampment_kit.py` (Blender 4.2 headless, `-- --no-bake` for the fast shape
  loop) writes `assets/models/encampment_kit.glb`; 68-2,772 triangles a piece, all under their
  `TRI_BUDGET`. Colour and sun-bleach come per instance (MultiMesh colour and custom), so one
  batch per piece kind per chunk draws every tent colour.
- **Numbers to tune** (consts at the top of `Encampment`, `LandmarkMacArthurPark`, exports on
  `RoughSleeper`): `CAMP_STREET_SHARE` 0.34, `FACE_ODDS_CAMP_STREET` 0.72, `FACE_ODDS` 0.12,
  `MAX_CAMPS` 3 a block, `MAX_ITEMS` 34 / `MAX_SLEEPERS` 6 a chunk, `UNITS` weights (slump 7 of
  107, plus 14 % of tents without a chair), `DRAW_DISTANCE` 190 / `SMALL_DRAW_DISTANCE` 120 m;
  `breath_period` 4.6 s, `sway_depth` 3.5 degrees, `breathe_range` 45 m; the park's
  `PALM_RING_STEP` 12.5 m, `FOUNTAIN_HEIGHT` 22 m, `CROWD_NORTH` 14 / `CROWD_SOUTH` 16,
  `WATER_Y` -0.28, `FLOOR_Y` -1.2.
- **Traffic after a re-centre (a main bug this branch fixed).** TrafficManager is shifted with
  everything else on an origin re-centre, but `_spawn_near` and the airport loop placed new cars
  as if it sat at the origin, so after the first re-centre every new car was put down the whole
  offset away along its road. That is what put cars inside the park; it will also have put them
  in the sea and on the wrong streets for anyone who travelled far. Spawns are now relative to
  the node, and a spawn just past a crossing's centre is checked open ahead.
- **NOT DONE, and how to continue.**
  1. **No stills and no frame-cost numbers.** The shared render lock never came free for this
     branch this session, so nothing here has been looked at in a render: not the park, not the
     lake shader, not the kit, not the poses. First job for whoever picks this up: these stills
     (opengl3, under the render lock) - `tools/glshot/camp_shot.gd` (poses and kit
     against a wall; `YAW=38 DIST=6` for the side), and `tools/glshot/city_shot.gd` with
     `HIDE=Visual` at `--spawn=480,70,63,-10,22 --hour=11` (the lake from the south-east),
     `--spawn=300,210,0,-35,120` (the whole park from the south), `--spawn=724,-30,10,-6` at
     `--hour=10.5` and `--hour=22` (a camp street, block 7,-1's east face), and
     `--spawn=461,242,-135,-12 --hour=16` (a camp with four people, block 4,2's north face). Then
     `tools/geo_count.gd` at the same cameras against the branch point (`8dd0269`) for the
     frame cost. Expect to tune: the poses (solved blind from rig data), the lake's colours, the
     kit's bleach and grime, the tent sizes against the pavement.
  2. **The kit glb in the repo is the no-bake build** (UV2 is zero, so no baked AO in the
     shader). Rebuild it with the bake: `blender -b -t 2 --factory-startup --python
     tools/encampment_kit.py`, then `godot --headless --path . --import`, and commit the `.glb`.
  3. Nobody has seen it move: the breathing, the sway, fleeing and settling back are checked by
     the smoke test's numbers only. No swimming (the lake is a wading depth). The site is
     axis-aligned (the real Wilshire runs at 297 degrees). The boathouse and bandshell are code
     massing on the building shader, not Blender models. The police can still dispatch a
     cruiser that starts inside a crossing next to the park and heads into a closed arm (their
     spawn has no look-ahead; traffic's does).
- **The smoke test** (`tests/westlake_checks.gd`, ~30-60 s on a busy box) re-centres the origin
  on every teleport and waits idle frames before a physics query, for the two reasons in its
  `_go()`; copy that pattern for any check that teleports far and then casts rays.
## 9s. Downtown at 1:1: the research, the fit, and the re-lay (researched 2026-09-24, landed 2026-09-25)

Owner: "I want the whole downtown landscape to become a 1:1 replica ... This should be
geographically sound", "you should also have macarthur park".

**LANDED (2026-09-25, branch wt/downtown-relay).** The re-lay (`tools/downtown_relay/relay.patch`,
a diff against 006e57c) no longer applied - main had MacArthur Park on, the masjid replica with
its sanctuary, the Esplanade's coast and headland, the distance tiers - so it was ported by hand
and gated; the headless check passes (472 checks after merging main at f9f3129), `tests/downtown_checks.gd` included. What
moved, and what differs from the patch:

- **Downtown**: the real grid pinned on every seed, the 19 towers and 9 civic sites on their
  geocoded points (worst tower 13.8 m off, the pavement clamp; civic within their tolerances),
  district and core from `DowntownReal`, relief off inside it, all crossings signalled.
- **The masjid** moved south: anchor (1917, 2722.8), the block west of Georgia St, its south
  road (the default seed's 24 m boulevard at z 2785.1) playing Exposition. The patch kept it at
  (-235.7, 139) - 3 km due west of Pershing Square and west of MacArthur Park, i.e. in
  Koreatown - which contradicts reality (the real one is 4.9 km grid-south, by USC, on Georgia's
  line). Now: on the real line within 40 m, west of the 110, south of where the 10 leaves it,
  north of the 105, distance south compressed (the real point is past the port). Sanctuary zone,
  collision and far copy are built at the anchor, so they moved with it; `tests/masjid_checks.gd`
  passes unchanged, and `downtown_checks.gd` holds the place.
- **MacArthur Park**: SITE from `DowntownReal.MACARTHUR` (Park View x 100, Alvarado x 487, 6th
  z 200.2, Wilshire z 312.7, 7th z 404; anchor (293.5, 312.7)). The lake half is 69 m deep and
  the fields half 90 m, because downtown's 6th-Wilshire-7th spacing is used there (the real
  streets fan out west of the 110: the real park is 310 m across, ours 204 m kerb to kerb).
- **Freeways**: the patch's alignments, plus `Freeway._spline()` made centripetal - the uniform
  Catmull-Rom looped the 110 back on itself at the four-level interchange and near Olympic and
  Pico (with a 230 m span next to a 2 km one). The 10 gets its real bend north toward the East LA
  interchange (it was a ruler-straight line). The 105 now swings wide round the masjid's
  neighbourhood - down the west side of the 110 corridor, then east just north of the port - so
  north to south it is the real order: the 10, the masjid, the 105.
- **Port** at the foot of the 110 (x 2050-2750, z 3000-3560), cargo ship (2400, 3420), as in the
  patch. Industrial is east of the 110 only (`industrial_corner` (2150, 2300); the patch had
  (1100, 2300), which made USC / Exposition and the Torrance plain warehouses).
- **Airport approach**: `downwind_x` 1250 and `approach_clear_length` 1150 (the patch's).
- **The north**: the east range out to x 5000, the embayment above the civic centre (patch).
- **Streaming**: the LOD ring stops `lod_reach_metres()` (840 m) out and a LOD chunk left 150 m
  past it is RETIRED (the far city covers the block, per block) - the patch freed it, which the
  distance tiers no longer allow. And a block of the FULL ring further than
  `full_reach_metres()` (240 m, two ordinary blocks) is a LOD chunk: two of downtown's
  125 x 200 m blocks each way is 2.6 times the full-detail area, and at Flower and Olympic the
  frame had 78 % more draw calls than the old avenue before this (73553af).
- **Names**: a seeded street never takes a real downtown name (no second Olive St).

Checks changed, and why: the LOD count at the spawn (the pinned streets cross the whole map, so
blocks round the spawn are 200-440 m deep and the ring stops at 840 m); "every freeway route
curves" now measures the most the heading turns (the real 110 leaves the four-level and meets
the port heading south both times); city hall's roof probe reads the tower's position from the
builder (`LandmarkCivicCenter._hall_tower()`; the turned, bigger site moved it 10 m off the old
probe point); "no deck crosses the core" is measured east of Figueroa (the core rect starts at
the 110, which is Bunker Hill's real west edge). `street_life_checks` prints what stood round
the cruiser when it pulls up off its kerb point: in the early gate runs it stopped 0.2, 2.5, 0.2
and once 4.2 m off (the limit is 3.0); 73553af also accepts the kerb nearest where the player
ends up (block 0,0 is 100 x 200 m now and he can be nudged while the cruiser follows him), and
the last gates read 0.6 m, as main does - watch it. Main's hill-planting check ("nothing
planted on rock or bare cuts") recomputed each shrub's slope from the analytic `height_at()`;
at its hill spot on the 1:1 map two of 445 shrubs read as rock that way and not on the drawn
terrain grid, which is what the planting and the shader use - it now asks the chunk for
`_terrain_height()` (1143a72).

Consequence to know: a pinned road runs the whole map, so every block between z -1726 and 2000,
anywhere in the basin, has downtown's street spacing (164-437 m) on that axis.

**What it costs** (geo_count, opengl3, 800 x 600, `--quality=0`; main = 6330409 with the perf
pass and the pedestrian middle body, branch = the same merged in). Downtown against downtown:

| View | main | branch | change |
|---|---|---|---|
| Avenue (main `589.2,860,0,12,2`, branch `2359.4,880,0,12,2`) | 5.67 M / 4,137 draws / 17.0 k objects | 5.90 M / 4,930 / 21.1 k | +4 % tris, +19 % draws |
| South-west aerial (main `-50,1250,-43,5,80`, branch `1450,2150,-38,4,140`) | 9.95 M / 5,352 / 17.7 k | 7.25 M / 9,006 / 25.3 k | -27 % tris, +68 % draws |
| Same spot, old avenue `589.2,860` | 5.67 M / 4,137 | 7.31 M / 6,447 | (now plain midtown) |
| Same spot, old aerial `-50,1250` | 9.95 M / 5,352 | 4.54 M / 3,451 | |
| Same spot, new avenue `2359.4,880` | 1.38 M / 985 | 5.90 M / 4,930 | (was the edge of town) |
| Same spot, new aerial `1450,2150` | 3.14 M / 3,948 | 7.25 M / 9,006 | (was industrial) |

`SPLIT=1` on `still_shot.gd` (960 x 540, same vantages) puts all of the rise in **Building**:
avenue 445 -> 3,343 draws (every other category went down: cars -325, people -148, props -515),
aerial 1,445 -> 5,664 draws (1,151 -> 9,906 building nodes; everything else flat or down). The
avenue is lined by the 1:1 core's infill towers where the old one looked at the named towers
(Landmark draws); the aerial looks over the 25-block full ring of dense midtown between the 110
and the masjid, which on main was the industrial quarter (warehouses: a few big boxes) - the
patch put industrial east of the 110 only, as it is in reality. Triangles are flat or down; the
draw calls are the known building draw sink of 9x (several meshes per building), now in more
of the frame. Also know: `MacroMap.midtown_radius` is a 1,700 m BAND round downtown's 2.3 x 3.8
km extent (it was an 800 m disc round one point), so MIDTOWN round downtown covers ~30 km2 where
it covered 2, and `TrafficManager.density_at()` runs at full density over the same band. It was
sized to reach MacArthur Park and Koreatown to the west; the south and east of real downtown
are low-rise, so a narrower band there (west 1,700, elsewhere ~800, which keeps the masjid's
block, 703 m out, midtown) is the cheap next step if the Mac's frame rate over South LA drops.
The per-building merge (9x) is the real fix for the draws.

Stills (opengl3, noon, in the landing session's scratchpad `dt/stills/`, B_ = main, A_ =
branch): aerial `B_aerial` / `A_aerial` (spawns above), avenue `B_avenue` / `A_avenue`, civic
`A_civic2` `--spawn=2600,-450,-50,-14,220` (city hall behind Grand Park; `B_civic2` at
`300,654`), arena `A_arena3` `--spawn=2330,1560,43,-18,110` (`B_arena3` at `543.6,659.4`),
masjid `A_masjid` (`1880.7,2809.6,-31.8,-23.7,32`, downtown's skyline behind it the way it
stands from Exposition) / `B_masjid` (`-272,252`), MacArthur `A_macarthur`
`--spawn=300,528,0,-35,120` / `B_macarthur` `308.5,163`. Seen: the arena is a 74 m drum on a
240 x 330 m block of bare plaza (the builder is still a third of real size - below), and north
of the civic centre the embayment leaves the back range at the far-ground rim fade, where it
reads as a pale, half-transparent ridge in the opengl3 stills.

What is left: interiors; Bunker Hill as a hill; Little Tokyo and the east side as real streets;
the real 110/101/10 interchange ramps; the civic builders at real size (the arena's
`ARENA_RADII` is 36-37 m against the real ~90); a Forward+ golden-hour still of the new skyline
(NEEDS MAC CHECK - a full city on lavapipe runs out of memory on the shared box).

The research as it was written before the landing:

**The fit.** 93 Nominatim queries (strictly one per 1.2-3 s, the IP is shared and 429s came
often; every answer is in `tools/downtown_relay/geocode_cache.json`, so NOTHING needs re-querying):
40 landmark / anchor points by address or place, and the OSM way centroids of 45 named streets
and 4 freeways in a downtown box (`limit=10&dedupe=0&bounded=1`: up to ten points ON each street's
centre line per query - `tools/downtown_relay/points.txt` is the query list). `fit2.py` keeps each
street's points where it runs on the core grid, trims them to 18 m of the median and fits the
bearing that minimises the scatter: **37.86 degrees, RMS 2.0 m over 115 centre-line points**;
avenues alone 37.87, streets alone 37.80 + 90, so the grid is square to 0.07 degrees. The old
tables were off: the skyline's 45 degrees, the civic table's 36, and their metres per degree of
latitude (110 574 is the equator's; 110 923 at 34.05 N). Real block spacing, centre line to centre
line: avenues 122-130 m (Figueroa-Flower 125.9, Hill-Broadway 126.6), numbered streets 199-209 m
(5th-6th 200.2, 1st-2nd 164), Wilshire 110 m below 6th, Temple 314 m above 1st, Pico-Venice 437.
City hall to the arena 2 531 m. MacArthur Park's centre is 1 943 m west of Figueroa along
Wilshire. Every value, with its point count and RMS, is in the module's AVENUES / STREETS tables;
`-1` RMS marks a street placed rather than fitted (it runs off the grid - see below).

**What the real grid does that the game's cannot**, all in the module header: east of Main the
streets are on another grid (Alameda swings 500 m across it between Union Station and Little
Tokyo), so only Alameda (where it passes Union Station) and Vignes are pinned there; one road is
one line across the whole map, so Wilshire (pinned, it is MacArthur's axis) also splits the
historic core's 6th-7th blocks, 12th St is left out (it would cut the arena), and Georgia St is
pinned where it is south of Olympic; west of the 110 the streets bend 8 degrees, so MacArthur Park
goes on the straightened Wilshire at its true distance along it (280 m grid-north of the real
park). The 10 is 2.3 km south of Pershing Square, well below Pico (the convention centre is
bounded by Venice, not the 10).

**The placement, and why the basin has to grow.** At 1:1 downtown (the 110 to Vignes, Cesar
Chavez to Venice) is 2.3 x 3.8 km - as big as the whole old basin between the coast, the front
range and the port. Constraints that fixed it: MacArthur Park 2.5 km west of Pershing Square has
to land on city east of the airport and clear of the coast towns and the mosque; the port cannot
sit west of the arena; the civic centre must not be on a mountainside; CityPlan's road 0 is at z 0
and must be a real street. Result (`DowntownReal.GAME_ANCHOR`): **Pershing Square at (2800,
102.7)**, 5th St exactly on z 0, downtown x 1650-3950, z -1750..2020, MacArthur Park at x 100-487
on Wilshire (z 313). In the patch that needs: the east range from x 1900 to 5000; an "embayment"
(`MacroMap.embay_*`) stepping the whole north (front range, valley, back range) back 1 250 m east
of the pass, with the front range at 0.4 height there - the real range ends at the Cahuenga Pass
and only the low Elysian hills stand north of downtown; the port and harbour moved to x 2050-2750,
z 3000-3560, at the foot of the 110; `industrial_corner` (1100, 2300) and the Arts District east of
Vignes industrial; `AirTraffic.downwind_x` 1950 -> 1250 and `approach_clear_length` 700 -> 1150 (the
final turned in over the South Park towers); relief calmed inside downtown; the masjid anchor to
z 139 (6th St now runs where its gate was); the cargo ship to (2400, 3420). The zone map of the
patched basin (100 m a character) is `tools/downtown_relay/zone_map_after.txt`: downtown east-north-
east of the airport (bearing ~76 degrees), the embayment hills 150-220 m high from z -2200.

**Freeways in the patch** (`Freeway._spline()` resamples control points to STEP): the 110 on its
geocoded alignment from the four-level interchange (2157, -1616) down the west edge (u -886 at
8th, -1016 at Olympic, -1089 at Pico) to the 10 interchange (2206, 2650) and into the port; the
101 along the north edge (v -1335) past the civic centre to the four-level, west-south-west on its
real heading - the geocoded point at u -2044 lands exactly on the game's pass - then north through
the pass as the old valley route did (renamed "101 Hollywood Freeway"); the 10 new, from the 110
east along the real line to x 4930; the 105 rerouted south of the airport's clear zone and round
downtown's south-west, crossing the 110 south of the 10 (as the real one does), north of the port.

**Measured.** geo_count at forced HIGH (`-- --quality=0`, or the auto step-down changes what is
drawn mid-run) on the civic merge 006e57c, i.e. the "before": avenue `--spawn=589.2,860,0,12,2`
**5.54 M tris, 3 169 draws, 3 185 objects**; south-west aerial `--spawn=-50,1250,-43,5,80` **9.30 M
tris, 4 470 draws, 4 547 objects**. The "after" was NOT measured. Probe of the patch (headless): all
19 towers within 13.8 m of their geocoded points (the pavement clamp; plans = built extents),
civic sites 1-108 m (city hall and the concert hall 1 m; the LA Live plaza and hotel share one
block and the geocoded point is a POI, so they are placed by `at`), 16 x 18 replica blocks, 2 799
lots, 52 infill lots over 130 m (after lowering the non-core band to 14-80 m and the core to
30-190 m with bigger core lots - with the old bands it was 301), MacroMap setup 180 ms.

**How it was to be landed, step by step** (done, 2026-09-25; kept for the record).
1. Merge origin/main; `git apply --3way tools/downtown_relay/relay.patch` and resolve (it touches
   city_plan, macro_map, freeway, landmark_downtown, civic_sites, landmarks, air_traffic, traffic,
   city_streamer, smoke_test).
2. `mv tools/downtown_relay/downtown_checks.gd.txt tests/downtown_checks.gd` (the patch's smoke
   test already loads it after `_test_downtown`).
3. `godot --headless --path . --import`, then run `tools/downtown_relay/probe.gd.txt` (rename to
   .gd) with `--script`: it prints every pinned road, tower anchor, civic site, route and the lot
   count. Then the headless check inside the gate slot. Expect to fix: the ambience checks
   (downtown noon sampled at Pershing), the air traffic checks (new downwind leg), the freeway
   ramp/crossing checks (five routes), the civic checks' "no deck crosses a site" (the patch was
   laid to keep the 110 west of Georgia and the 101 north of Temple, not yet run), and anything
   that hard-codes the old port (800, 1150).
4. If the MacArthur branch has landed: set its SITE from `DowntownReal.MACARTHUR` - west_x 100
   (Park View), east_x 487 (Alvarado), north_z 200.2 (6th), south_z 404 (7th), wilshire_z 312.7,
   anchor (293.5, 312.7).
5. Measure geo_count at the new avenue `--spawn=2359.4,880,0,12,2` (Flower at Olympic, north) and a
   south-west aerial `--spawn=1450,2150,-38,4,140`, at `--quality=0`, against the numbers above.
   The patch caps the LOD ring at the skyline's start in metres (`CityStreamer._block_distance`),
   because seven of downtown's 200-440 m blocks reach twice as far as the Skyline tier starts and
   both drew the same city; the full-detail ring is still 2 blocks, which in downtown is 2.6x the
   area it was - the first thing to look at if the avenue's draws are up.
6. Stills: SW aerial as above, the avenue as above, the civic centre `--spawn=2600,-450,-50,-4,60`,
   the arena `--spawn=2300,1150,138,-8,30`, a Forward+ golden hour `--hour=18.3` on the aerial.
7. Docs: a CLAUDE.md bullet for DowntownReal (the module header has the substance), and fix the
   skyline and civic bullets' "one real block to one game block" and their stills spawns.

Not done at all: interiors of any of it; Bunker Hill as a hill (the relief is flat); Little Tokyo
and the east side as real streets; the real 110/101/10 interchange ramps (the decks meet with the
freeway code's usual lift); the civic builders at real size (the arena's `ARENA_RADII` is still
36-37 m against the real ~90, so it will look small in its real 240 x 330 m block).
## 9t. The distance, 2026-09-24 (agent branch)

Owner: "it's glaringly obvious that certain areas of the map aren't loading properly at a
distance. I'd like to see this fixed, do whatever GTA does and other grade-A games." The rules
are the Distance bullet in CLAUDE.md. What a next session needs to know:

**What was wrong, found by counting before fixing.** A headless census (every city block of the
plan within 6 km of eight vantage points - downtown roof and street, midtown street, the hills
over the basin, the beach, the airport, the valley, 900 m up - asked which tier draws it) plus
opengl3 panoramas (`tools/glshot/lod_pano.gd`) from the same places:

| Failure | Measured |
| --- | --- |
| The camera's far plane was 2000 m | 65-80 % of the city blocks within 6 km clipped from every vantage (969 of 1487 from downtown); the back range, the valley city and the far coast simply not drawn |
| The old far tier drawn over the chunks | 17-142 blocks drawn twice per vantage; from 900 m up every block the chunks had also wore a coarse far box (`TIERS=1` shows blue over red everywhere) |
| Gap ring | 0-10 holes per vantage in the 500-1000 m ring: the old tier decided visibility per 36-block tile by the tile CENTRE's distance, so a tile half inside the LOD ring drew nothing past it |
| Far massing not the city's | malls, big boxes, commercial pads, pocket-garden yards and the freeway corridor drawn as lot-sized buildings the chunks never build |
| Horizon plane burying the far city | `urban_lift` stood the built-up plane 42 m up past 2.6 km, over every suburb |
| Far buildings brighter than near ones on the Mac | `instance_color_is_srgb` declared in building_lod.gdshader and never set or read: far boxes 1.4-4.3x the near buildings' value |
| The LOD ring bald | LOD chunks plant nothing: no street or park trees 200-700 m out, no scrub on LOD hills |
| The LOD ring could not keep up | LOD chunk build 40 ms (32 of it laying flat ground on the near 2.2 m grid); a 90 m/s flight ended with 3 of 200 LOD chunks standing |
| The plane's own edge | once the far plane was fixed, the 14 km plane's rim showed from the hills as a pale slab across the sea |

**What it is now** (commits on this branch, oldest first): the far plane is 12 km; far chunks'
ground is on an 8 m grid (LOD build 40.3 -> 7.6 ms, worst step 17.6 -> 2.9 ms; startup headless
58 -> 36 s, a teleport 18.7 -> 7.4 s); far boxes decode their colour on Forward+; the far city
(`Skyline`) is a super-LOD of every block within 7 km, handed over per block with a dissolve and
built from the LOD block build itself (capture mode), with plates, painted roads, freeway decks,
port containers, street/park trees and hill planting; the queue is view-weighted; the plane's
rim and the far city's last kilometre hand over to the sky's horizon colour together.

**After, same census:** 0 holes, 0 blocks drawn twice, 0 past the far plane, from every vantage.
The one exception is a teleport: the far city outside `far_city_immediate_radius` (2.5 km) is
built progressively, ~1-2 s of play, nearest and most-in-view first; the loading screen builds
all of it up front on desktop (`finish_far_city()`, ~2.7 s headless for 20,000 blocks, most of
them sea and open hillside).

**Cost, measured.** Geometry per frame is opengl3 + Xvfb (`lod_pano.gd` prints it per view,
four views 90 degrees apart); the flight is headless (`tools/flight_bench.gd`, CPU side only).
The box was shared with four other agents at a load of 7-11 on 4 cores the whole time, so the
flight's wall-clock frame times are noise of +-20 % between two runs of the SAME build.

| Vantage (4 views) | Triangles before | Triangles after | Draws before | Draws after |
| --- | --- | --- | --- | --- |
| Hills over the basin (300,-1150, 520 m) | 515k / 435k / 209k / 255k | 1.37M / 1.34M / 1.27M / 628k | 473 / 299 / 435 / 767 | 710 / 322 / 463 / 782 |
| 900 m up over midtown | 471k / 374k / 236k / 252k | 927k / 511k / 387k / 656k | 538 / 638 / 248 / 102 | 577 / 659 / 283 / 128 |
| Downtown roof (700,250, 260 m) | 756k / 514k / 669k / 565k | 1.80M / 908k / 930k / 986k | 938 / 859 / 768 / 335 | 979 / 884 / 806 / 355 |

Triangles roughly double to triple from a height because the whole basin is now drawn (it was
clipped at 2 km); draw calls are about flat (one MultiMesh per 36-block tile). The far canopy
blob went from 48 to 24 triangles after these were taken, which takes a slice back.

| Flight, 90 m/s at 70 m, wall clock | frames | p50 | p95 | p99 | max | over 100 ms |
| --- | --- | --- | --- | --- | --- | --- |
| Route a (midtown - downtown - port), base, 2 runs | 339 / 351 | 98.9 / 105.7 | 286 / 334 | 402 / 473 | 1054 / 827 | 166 / 183 |
| Route a, this branch | 340 / 355 | 101.9 / 96.5 | 302 / 354 | 445 / 509 | 647 / 917 | 172 / 174 |
| Route b (hills - coast), base | 589 / 606 | 39.1 / 37.1 | 159 / 164 | 376 / 246 | 704 / 533 | 104 / 98 |
| Route b, this branch | 530 / 645 | 42.6 / 35.2 | 244 / 140 | 498 / 188 | 1279 / 612 | 125 / 73 |

So: no measurable change either way inside that noise, while the new side also builds the far
city during the flight (headless has no loading screen). Holes ahead of the flight (city
blocks within 3 km in a 100-degree cone that no tier draws, sampled every 20 frames): route a
112.8 mean / 218 worst -> 23.6 / 102 (the far city past 2.5 km still being built progressively,
which the desktop loading screen does up front), route b 81.3 / 247 -> 0.7 / 12.
The far city's own work: 13,288 blocks (16,776 with sea and hills) in 2.3 s total headless,
per work step p50 0.05 ms, p99 1.4 ms, since the capture was split into build steps.
A fixed-step A/B (`FIXED=1`, same frames both sides, process CPU time from /proc) was set up in
`scratchpad/lod/flight_ab2.sh` but not run before the session ended - run it on a quiet box:
`FIXED=1 [FARCITY=1] ROUTE=a|b godot --headless --path . --script tools/flight_bench.gd -- --nohud`.

**Traps and rules** (also in CLAUDE.md):
- Never give a far-city node a visibility range and never free a chunk except through
  `CityStreamer._retire_chunk()`: both reopen the gap ring.
- The capture build must stay exactly the LOD build. `CityChunk.capturing` intercepts
  `_add_slab`, `_add_cylinder` and `_add_lod_shape` only; everything else in `_block_steps` runs
  as written, so its rolls land in the same order. `tests/distance_checks.gd` compares the two
  box for box - if it fails, something in the block build now depends on a node or on the level.
- A far block's instances carry its visibility in their colour ALPHA. Anything that draws with
  building_lod or far_canopy must keep alpha 1 unless it means to be dissolved (the LOD chunks'
  own batches do).
- The far city's plates carry LINEAR colours (`CityChunk.far_tint()`), like the LOD chunks' far
  ground, and building_lod skips its sRGB decode for them (`INSTANCE_CUSTOM.a` >= 2).
- The retire keeps a chunk drawn for `lod_fade_time` but `CityChunk.retire()` takes its cars,
  people, trash cans and collision at once, which is when they went before. The first smoke run
  without that crashed: a test picked a parked car from a retiring chunk and it vanished
  half a second later.

**Not done / not verified:**
- Nothing here has been seen in Forward+: the box never had 9 GB free while this ran. The
  renders are opengl3, and on opengl3 the horizon plane's hills are a dark brown next to the
  LOD chunks' gold terrain (a tier seam you can see in every hills shot, before and after); it
  was there before this work and may be Compatibility-only - look at a Forward+ hills still
  first.
- Far trees are the right rows at the right density, not the FULL chunk's own trees (those are
  placed with rolls the capture does not make), so a tree can shift a few metres as its block
  turns FULL, 200 m out, under the dissolve.
- Hill roads are not in the far city; the plane paints none. (The airport's runways are: they
  cut its plates into strips.) Inside the LOD ring the airport chunk's runway box (top 0.14)
  still z-fights its apron (top 0.10) past ~700 m on the Compatibility renderer - streaks in the
  opengl3 stills, there before this work, and not expected on Forward+'s reverse-Z depth.
- The far city's towers are shaded boxes (the LOD shader), exactly as the LOD chunks draw them;
  a real impostor tier for towers is the next step up (G7).
- The web build builds the far city progressively from 900 m out (it has no loading screen); on
  a slow machine the far half of the basin arrives over the first seconds.
- Merged with main's downtown skyline and civic set at the end of the session and the headless
  check run once on the merge; the far copies of the named towers are theirs (far landmarks),
  not the far city's. Not rendered after the merge.
- Stills (opengl3, 5120 x 720 panoramas, four views; in the session scratchpad, not the repo,
  and already sent to the owner): before = downtown, hills, high air, airport, beach, freeway;
  after = downtown, hills, high air; `_tiers` = each tier a flat colour (red LOD chunks, blue far
  city, pink landmarks). The after set predates the rim fade, the airport plates and the
  harness far-city build (except `lod_after_highair_tiers`, which has the last two); re-shoot
  the same vantages with `tools/glshot/lod_pano.gd` (usage in its header) to see all of it:
  downtown `--spawn=700,250,0,-8,260`, hills `300,-1150,180,-12,520`, high air
  `500,300,0,-28,900`, airport `-300,780,-90,-5,80`, beach `-850,-300,-90,-3,30`, freeway
  `200,712,-90,-4,30`, all at `--hour=13`.


## 9u. The hero, AAA pass, 2026-09-24 (agent branch, landed 2026-09-24 late)

The owner asked for the Blender hero at "AAA studio level, from scratch, with real fingers".
What changed, in the order the brief listed it:

- **Pipeline in the repo.** `tools/hero/` (setup.sh, build.sh, hero_config.json and one Python
  file per step) rebuilds `assets/models/hero.glb` from the CC0 inputs in about 15 minutes; the
  CLAUDE.md hero bullet has the commands. Blender, MPFB and the asset pack land in
  `build/hero_src/` (ignored, with a `.gdignore` so Godot never scans the Blender install).
- **Fixed flaws.** The collar and neckline were cut face by face and came out torn: every garment
  edge is now a plane cut with a real cross-section band (stand collar, rib cuffs and hems, the
  V-neck of the tank). The dark hole on the left shoulder was the ray bake putting inverted
  normals in the armpit: no normal map is baked any more, they are all derived from a 3D fold
  field (`folds.py`) through the UV layout (`texspace.py` rasterises it to rest-pose points).
  Square shoulders: bound with the arms 62 degrees down instead of MakeHuman's A-pose
  (`rest_pose` in the config) and the shoulder weights blurred. Hair is new (grown cards, not the
  `short04` helmet); the skin is re-tinted and gets a stubble mask; the shoes have laces.
  The first in-game stills of the new model showed three more, none of them modelling: the
  collar tore into shards whenever the idle turned the head (it had the neck's weights: now
  `off_the_head()`), black jagged patches on the back (the decimated shadow twin standing proud
  of the cloth: now pulled 6 mm under it), and a razor-straight edge of painted scalp at the
  temples (a height fade on a vertical hairline: now a fade over distance on the head). The nape
  hair also hung 5 cm onto the neck; strands now stop `nape_below` past the hairline.
  `render.py` hides the twin (in Cycles it is drawn and shows through as white patches).
- **Game shaders.** `HeroLook` puts the skin, hair and tracksuit on `shaders/hero_*.gdshader`
  with the `hero_x_*` maps (pores and stubble tiling on the face, T-zone oil, SSS on Forward+;
  anisotropic hair with dithered cut-out; velour pile and sheen, and rest / bent fold maps mixed
  per joint by the pose).
- **Hands on the guns** (the part that took longest). `tools/grip_fit.gd` measures the hold
  headless and fits it. What it found, which a screenshot would not have shown: (1) the idle
  clip turns the hips and shoulders through 50-75 degrees as it shifts weight, and the support
  hand came off the handguard by up to 23 cm every couple of seconds - `AimTwist` now holds the
  chest against the clip (`Avatar.stance_hold`); (2) with the bladed stance the gun had been
  placed from the clip's shoulder, 18 cm from where the stance put it, so the butt sat 12 cm
  inside the chest - the gun is now placed from the stance's shoulder and the fitter seats the
  butt in the shoulder pocket (the launcher on top of the shoulder); (3) switching guns looked
  like a bug for a while, and was (1); (4) the hip carry could not reach the handguard at all,
  and is now fitted too (`AIM=0 FIT=1`); (5) a report taken three frames after equipping reads
  the gun a third of the way up, and a hand measured against where the gun is a frame later
  missed by 20 cm at walking speed (the fitter now captures both at the same moment). Final
  fit: palms 8-14 mm off the grip side (13 wanted), index tips 11-12 mm from the trigger face,
  right thumbs 20-28 mm off the far side (`thumb_wrap`), support fingertips 2-21 mm off the
  handguard / pump / fore grip, butts within 1 cm of their seats (the launcher 2.5 cm), both
  wrists on their targets aimed and at the hip, standing, walking and running (the hip carry
  and the shotgun keep 5 cm of arm spare for the walk's bob).
- **Performance.** One skinned mesh, 15 surfaces, 120.1k triangles at LOD0 (Godot generates the
  LODs), and a 9k-triangle shadow twin: the body itself casts no shadow.
- **Cycles previews that match the game**: `tools/hero/render.py --hero` rebuilds the hero
  shaders in nodes, `--pose` takes a `grip_fit.gd POSE_OUT` dump and imports the gun where the
  game holds it (views `grip_right`, `grip_left`, `grip_front`, `grip_above`).

**Not yet seen in a render (session ended first):** the last rebuild (collar weights off the
head, shadow twin 6 mm under the cloth, distance-faded hairline, tapered nape) was measured
(collar edges grown past 1 cm in the idle and aim poses 167 -> 42, tank 286 -> 82) but no still
of it exists; the in-game stills in the scratchpad (`aaa/r2_look`, `aaa/r2_hands`) are of the
build before it and show the shards and the patches. First thing next session:
`b_quick2.sh`-style stills (`hero_shot.gd` with `CLIP=Idle SEEK=2.9 CAM_AT=head` for the face,
`SEEK=1.0` for the head turned, `CAM_AT=hands` for the guns) and `tools/hero/render.py --hero
--neutral` / `--pose <grip_fit dump>` in Cycles. No Forward+ still of the hero was taken (the box
never had 9 GB free).

Known gaps: the right thumbs still stop 2-3 cm short of the far side of the grip; nothing on
the hero has been seen on the owner's Mac; the idle's hip turn now shows as the legs pivoting
under a still chest while a gun is held, which reads as shifting weight but has not been judged
in motion; the skin is 60.8k of the 120.1k triangles (face, hands, neck at one subdivision)
and could lose a third without showing. Texture memory: about 31 MB VRAM for the hero's 24
textures (S3TC with mips).

## 9v. Masjid Omar ibn Al-Khattab, 2026-09-24 evening

Owner: "make masjid omar ibn khattab way more detailed and 1:1 accurate ... make it impossible for
the character to shoot anything at it completely ... and give it an interior", with six photos
(aerial from the south, the street elevation, the entrance, the stairs out to Exposition with the
Expo Line station opposite, the prayer hall). The game had an original-design mosque, Masjid Al
Noor, on a suburban parcel; it is replaced on the same parcel, whose south pavement plays
Exposition Boulevard, so the entrance faces the street it faces in life.

- **Real data:** Nominatim gave OSM way 412475901 (building=mosque, height 15.7, start_date
  1993) and its 7-point outline: 49.2 m east-west, a tall west block 17.9 x 18.7 m and an east
  wing 31.3 x 21.3 m standing 2.6 m further out to the street. `REAL_LATLON` is kept for the
  downtown re-lay. Credited in `docs/ASSETS.md` (ODbL).
- **Built in code** (`LandmarkMasjidOmar`), merged one surface per material, cached in static
  vars so re-streaming costs nothing; one trimesh collision body with the doorways open and every
  window closed by its pane. The generator's `_arch_wall()` makes a wall with round-arched
  openings through its thickness (both faces, sill, jambs and intrados), `_surround()` the green
  band, `_opening_fill()` the lattice and glass. The `_Kit` class picks each triangle's winding
  from the normal it is given, so callers only say which way a face looks.
- **Traps met, all fixed:** `:=` on a value read from a Dictionary or Array is a parse error
  (the whole city then fails to compile, and the symptoms show up somewhere else entirely); a
  cornice written as one box is a slab over the whole roof, and a capped cylinder for the drum's
  band a disc across the inside of the dome; `PropFactory.pbr("plaster_white")` can never make a
  white wall (the photo averages 0.27 linear, yellow), so the paint is `_paint()` - the plaster's
  normal and roughness, a written colour.
- **The sanctuary rule** is `Sanctuary` (`scripts/weapons/sanctuary.gd`), checked in
  `Weapon.tick()`; CLAUDE.md has the whole rule. `tests/masjid_checks.gd` covers the building
  (streams in, door open, pane closed, both floors) and the rule (on it, across it, beside it
  with a blast, from inside it through a real rifle, away from it, a rocket fizzling).
- **Stills:** `<scratchpad>/masjid/` (aerial, street, entrance, hall), opengl3. Views (since the
  1:1 downtown moved it, 9s): aerial `--spawn=1880.7,2809.6,-31.8,-23.7,32`, entrance
  `1913.95,2779.1,0,12,1.7`, prayer hall `1901.35,2758.1,0,8,2.6`, all `--hour=11` (before it:
  `-272,252`, `-238.75,221.5`, `-251.35,200.5`). Not yet seen on Forward+.
- **Not done:** the east wing's rooms are one lobby and one domed hall (the real plan is not
  public); no ablution room; the parking lot has no cars. The exterior mesh is 50.7k triangles and the
  collision 9.1k (both counted by the smoke test); the frame cost is not measured -
  `tools/geo_count.gd` at the aerial view is the way to (the interior mesh is hidden past 140 m,
  and it adds five no-shadow lights). The smoke run's "Cannot set a buffer on a Multimesh" traces
  through `masjid_checks.gd` are section 10 item 8's headless noise, from the chunks it streams.

## 9w. Golden hour and the smog, 2026-09-25 (agent branch)

The ask: late afternoon should read like Los Angeles - a warm low sun, an orange-to-pink band
along the horizon fading into a pale brown-grey smog layer over the basin (thick at the horizon
and against the mountains, thin overhead), warm distance haze, long warm shadows with a blue fill.
Midday and night must not move. The rules are in the Day/night bullet of CLAUDE.md.

- **What was wrong.** With the sun ten degrees up (17:36) the sky was already the SUNSET: the
  `dusk` blend is 0.73 there, so the zenith had gone to the dusky violet `dusk_sky_top`, the
  horizon to peach, and the earth's-shadow band (`sunset_band`, violet) stood 17 degrees up all
  round - a sky that only exists once the sun is down. Since the ambient IS the sky, every
  shadow took that lavender. And there was no smog at all: the horizon was a clean gradient.
- **What changed.** `DayNight.golden` (0..1, sun elevation only) and `sun_high` (1 from about
  ten degrees up, 0 on the horizon). While the sun is clearly up the zenith and horizon hold back
  most of their dusk colour (`golden_blue_top`, `golden_pale_horizon`) and the violet band is
  off (`twilight_band_gain`); on the horizon and after, everything is exactly as before. The sky
  shader draws the smog lid (`smog*` uniforms; one branch on a uniform, ~25 ALU on sky pixels
  and radiance texels, only at golden hour) and diffuses and reddens the sun disc inside it; the
  far ground takes the same colour under `smog_lid` metres (mountain feet in it, crests clear);
  the depth fog goes toward the smog colour and 1.45x thicker (`fog_gain`, applied by Weather).
  Sunrise gets `smog_morning` (0.45) of it; weather removes it.
- **Measuring it.** A Forward+ city shot no longer fits this box: lavapipe peaked at 13.9 GB for
  the 80 m aerial and 13.7 GB for the avenue even at `--quality=1`, and the memory cgroup every
  agent's shell shares is 14.3 GB, so all of them were OOM-killed. The Forward+ judgement was a
  light probe instead: the city's own Environment and Sun, a DayNight, Weather's clear-sky fog
  numbers applied by hand, and a field of grey boxes to 7 km, which fits easily. Sky-only probes on
  Compatibility are cheaper still for the sky itself. Neither shows the far ground's smog lid.
- **Needs the Mac.** Not seen on the real city in Forward+ at all: the far ground's smog under
  `smog_lid`, the lid against the real mountains, volumetric fog over the real streets.

## 9x. Frame cost baseline (2026-09-25)

The yardstick the visual waves are judged against (north star: 60 fps at 1440p on the owner's
Mac, 30 the floor). Measured on 20e2169 (street clutter just merged) with the new GEO / `SPLIT=1`
report of `tools/glshot/still_shot.gd`, which every bookmark now prints for the exact frame it
shoots: `SPLIT=1 GODOT=... tools/glshot/bookmarks.sh <dir> <names>`, then `grep -E '^(GEO|SPLIT)'
<dir>/<name>.log`. opengl3 / llvmpipe, 1280x720 window, `--quality=0` (HIGH). Read the columns
right: triangles include the shadow passes; the GL renderer does NOT count shadow draw calls,
so "draws" is the camera pass only - on Forward+ every opaque draw also has a depth pre-pass
twin and one more per shadow cascade it falls in. The counts are steady run to run: downtown
noon and downtown night rain (same camera, other hour and weather) differ by 2.6k triangles
and 6 draws.

| Bookmark | Triangles (camera / shadow) | Draws | Objects |
|---|---|---|---|
| downtown_noon | 8.24 M (5.55 / 2.69) | 4,679 | 4,706 |
| downtown_night_rain | 8.24 M (5.55 / 2.69) | 4,685 | 4,712 |
| freeway | 8.68 M (5.39 / 3.29) | 6,661 | 6,781 |
| esplanade_sunset | 3.19 M (1.84 / 1.35) | 1,309 | 1,309 |
| hills | 1.60 M (1.30 / 0.30) | 1,202 | 1,203 |

Where it goes (`SPLIT`: that category hidden, same frozen frame; triangles, of which shadow,
and draws):

| Category | downtown_noon | freeway | esplanade_sunset | hills |
|---|---|---|---|---|
| Trees, palms, planting | 1.97 M (1.14 sh), 454 | **3.40 M (1.95 sh)**, 735 | **1.98 M (1.18 sh)**, 639 | 0.51 M (0.21 sh), 32 |
| Pedestrians (+ hero) | **1.88 M** (0.34 sh), 510 | 0.51 M, 440 | 0.04 M, 8 | 0.07 M, 23 |
| Vehicles | 1.64 M (0.48 sh), 528 | 1.09 M (0.16 sh), 408 | 0.07 M, 27 | ~0, 5 |
| Far city (Skyline) | 1.33 M, 125 | 1.32 M, 197 | 0.69 M, 114 | **0.81 M**, 120 |
| Street props | 0.71 M (0.35 sh), **1,252** | 0.89 M (0.31 sh), **1,348** | 0.12 M, 281 | ~0, 51 |
| Buildings | 0.23 M, 445 | 0.95 M (0.58 sh), **2,526** | 0.01 M, 24 | 0, 0 |
| Chunk meshes (ground, freeway, boxes) | 0.37 M, 806 | 0.47 M, 908 | 0.24 M, 171 | 0.20 M, 401 |
| Landmarks | 0.07 M, 524 | 0.09 M, 235 | ~0, 20 | 0.01 M, **569** |
| Far ground (LOD chunks) | 0.32 M, 109 | 0.11 M, 79 | 0.02 M, 25 | 0, 0 |

What that says, for whoever picks the next performance pass:
- **Triangles: foliage first.** Trees are the biggest category on three of the four views (39 %
  of the freeway frame, 62 % of the esplanade), and more than half of it is SHADOW even with the
  lighter twins. The cause is known (9f): a batch takes one LOD for every instance from its
  bounds, so every tree in the chunk the camera stands in draws LOD0 (40-60k triangles a tree)
  into the camera and all cascades. Smaller tree cells fix it at the price of draw calls.
  (Tried 2026-09-27: they did not - more triangles AND more draws. The real waste was the palms;
  see 9aa.)
- **Pedestrians downtown (1.88 M -> 1.10 M, done):** the 45-140 m band sat on the unwelded
  models' LOD floor (8,300 triangles a figure for most models at this camera); it now wears a
  welded middle body of ~2,070 from `mid_body_range` (50 m), see the next subsection.
- **Far city (0.7-1.3 M, few draws):** mostly the 24-triangle canopy blobs across the basin.
  Tiles whose blocks are all under chunks are only ~2 of 81 near downtown, so hiding them buys
  little.
- **Draw calls: street props (1,250-1,350 a street frame, a key per batch per chunk) and
  buildings (2,526 on the freeway - several meshes each)** are now the biggest draw sinks.
- Forward+ (lavapipe) per-pass timings were not re-taken: both lavapipe runs of this session
  were OOM-killed (the memory cgroup is shared by every agent on the box).
  `tools/gpu_profile.gd` now also prints the camera / shadow split and honours `MERGE_STATIC`, for a quieter box.

### What landed with it: static boxes merged into one draw per material

`CityChunk._add_slab()` built every solid box (big-box walls, their pilasters, base bands and
parapets, planters, port and airport pads, the crane) as its own MeshInstance3D - 300-530 of them
in every bookmark's streamed ring, most in the LOD chunks, each a draw call and each casting into
the far cascades. The far landmarks were the same: 802 nodes across the basin, mostly boxes and
cylinders (the hills sign 129, the campus hall 106, the pier 71, the mall 61, the ship 51...),
which on the hills bookmark were 569 of the frame's 1,202 draws for 9k triangles. Now a chunk
accumulates its boxes per material and commits one mesh each at the finish (`_commit_boxes()`),
and `MultiMeshBatch.merge_meshes()` merges each far landmark's plain primitives the same way
(802 nodes -> 337; opaque BaseMaterial3D, auto-named, unscripted nodes only; shader materials
such as the ridge sign's rigid seat are left alone because they can read MODEL_MATRIX). The
vertices are the
primitives' own, moved (normals by the inverse transpose), so nothing about the picture changes;
`MERGE_STATIC=0` on `still_shot.gd` / `gpu_profile.gd` turns both off for the A/B.

| Bookmark | Draws before -> after | Objects before -> after | Triangles before -> after |
|---|---|---|---|
| hills | 1,202 -> 942 (-21.6 %) | 1,203 -> 943 | 1,600,573 -> 1,600,573 |
| downtown_noon | 4,679 -> 4,313 (-7.8 %) | 4,706 -> 4,340 | 8,236,628 -> 8,239,364 |
| downtown_night_rain | 4,685 -> 4,319 (-7.8 %) | 4,712 -> 4,346 | 8,239,244 -> 8,241,980 |
| freeway | 6,661 -> 6,485 (-2.6 %) | 6,781 -> 6,605 | 8,683,165 -> 8,686,153 |
| esplanade_sunset | 1,309 -> 1,309 (none in view) | 1,309 -> 1,309 | 3,188,697 -> 3,188,697 |

Camera-pass draws only; the shadow and depth pre-pass draws of the same boxes go too, which the
GL counters cannot show. Triangles move by +0.03 % because a merged mesh is culled as one box.
Pixel diffs (before on 20e2169 or `MERGE_STATIC=0`, after on this commit): the only differences
are things that move with the clock - clouds and their reflection in the glass, wind-swayed
foliage and its shadows, rain, the hero's idle - and the merged geometry itself is identical
(freeway: the big-box store 0.08 % of pixels over 8/255; the road under downtown noon 0.000 %,
max 2; hills without the sky and the hero, 0.058 mean abs). Renders and diff images of this pass
were in the agent's scratchpad, not the repo; `MERGE_STATIC=0` reproduces the "before" side.

### Pedestrian middle body (2026-09-25)

`Pedestrian.far_mesh(mesh, cap)` now builds two welded bodies per model on the loading screen:
`mid_triangles` (~2,070) worn from `mid_body_range` (50 m; 35 m below MEDIUM) and `far_triangles`
(~515, was ~1,040 and in practice drawn at an 18-35 triangle LOD - see CLAUDE.md) from
`lod_far`. downtown_noon (opengl3, 1280x720, `--quality=0`, SPLIT=1), before on 1cbeedf:

| | before | after |
|---|---|---|
| Frame triangles | 8,228,872 | 7,443,628 (-785k, -9.5 %) |
| Camera pass | 5,540,097 | 4,754,853 |
| Shadow pass | 2,688,773 | 2,688,773 (the bodies cast no shadow; tier starts past 45 m) |
| Pedestrians (+ hero) | 1,881,692 | 1,096,448 (-42 %) |
| Draws / objects | 4,307 / 4,334 | 4,307 / 4,334 |

Loading screen: building both bodies for all nine models costs 900 ms on this box against
485 ms for the old far body alone (+415 ms, CPU; the Mac is quicker). The look, judged at
1920x1080 FOV 75 against the model at 15-140 m: the model's own mips turn its many small UV
islands into brown speckle past ~35 m, so the welded bodies (flat texel per mis-mapped
triangle) show the clothes' real colours better than the model does at that range - a yellow
blazer stays yellow at 70 m. Up close (under 10 m) a welded body's face is visibly faceted,
which is why it only starts at 50 m. In the downtown bookmark the only visible change is a few
far figures a shade more saturated.

## 9ai. Buildings in a handful of draws, 2026-09-27 (agent branch `wt/building-draws`)

The brief: 60 fps on the owner's Mac. At the downtown street bookmark the frame issued 5,815 draw
calls and 3,344 of them (57 %) were buildings, from 5,304 nodes. `SPLIT=1` on `still_shot.gd` now
also breaks the Building category down by kind of node (its `BSPLIT` lines), and that said where:

| Kind (camera-pass draws) | Downtown before | after | Freeway before | after |
|---|---|---|---|---|
| Roof boxes and cylinders (a node each) | 1,611 | 99 (`RoofPlant`) | 1,793 | 81 |
| Rooftop air conditioners (a model, a node each) | 858 | 228 (`RoofUnits`, `RoofUnitsRusted`) | 736 | 256 |
| Facade detail MultiMeshes (one per PART) | 337 | 107 (`Frames`, `Details`, `Bays`) | 262 | 103 |
| Box parts (a mesh and a ShaderMaterial per part) | 184 | 81 (`Walls`) | 138 | 77 |
| Facade kit batches (already one per kind) | 366 | 364 | 341 | 341 |
| Shop names (untouched; small kinds move by a few dozen between plain runs) | 19 | 3 | 7 | 0 |
| **Building category** | **3,344** | **869** | **3,270** | **858** |
| Other (the plinths went into the chunk's merged boxes) | 254 | 274 | 472 | 485 |

The whole frame, opengl3 at 960x540, `--quality=0`. The DIFF columns are the same frame with
everything that moves by itself hidden (see the traps), which is what the pixel diffs compare:

| Bookmark | draws before -> after | objects | triangles (GEO) |
|---|---|---|---|
| Downtown noon | 5,815 -> 3,360 (-42 %) | 5,913 -> 3,395 | 7,272,923 -> 6,520,175 |
| Downtown night rain | 5,818 -> 3,363 | 5,916 -> 3,398 | 7,275,377 -> 6,522,629 |
| Freeway | 6,045 -> 3,646 (-40 %) | 6,184 -> 3,699 | 7,005,369 -> 6,399,787 |
| Masjid | 6,025 -> 4,258 (-29 %) | 6,084 -> 4,293 | 8,299,676 -> 7,910,719 |
| Downtown noon, DIFF | 5,183 -> 2,733 | 5,279 -> 2,766 | 6,007,927 -> 5,257,598 |
| Downtown night, DIFF | 5,185 -> 2,735 | 5,281 -> 2,768 | 6,008,121 -> 5,257,792 |
| Freeway, DIFF | 5,604 -> 3,206 | 5,741 -> 3,257 | 6,450,760 -> 5,845,190 |
| Masjid, DIFF | 5,429 -> 3,666 | 5,484 -> 3,697 | 7,459,922 -> 7,071,013 |

The GEO triangle count undercounts a LOD'd MultiMesh (the counter counts its surface once), so
the rooftop units' real camera-pass cost is counted per instance by `ROOF_TRIS=1`: downtown
322,093 -> 409,132, freeway 261,207 -> 268,356, masjid 103,899 -> 182,354 (see below). Building
generation costs 4-13 % more CPU per building headless (about even for the towers).

### What changed

- **Walls: one mesh, one material a building.** The 2026-09-19 reason for a ShaderMaterial per
  part (Compatibility has no per-instance uniforms) is answered by vertex data instead, which every
  renderer has: `Building._append_part()` puts each part's BoxMesh (or chamfered prism) into one
  ArrayMesh at its centre and every vertex carries what that part's uniforms said, as 32-bit floats
  - CUSTOM0 the position in its own part (the VERTEX the shader saw) and has_storefront, CUSTOM1
  part_size and base_height, CUSTOM2 the pitches, floor_height, ground_floor_height, CUSTOM3 base_y
  and crown_start. `building.gdshader` takes them through flat varyings when `part_attributes` is
  on; the landmark towers leave it off. The numbers are computed by the same expressions as before,
  so the shader sees the same floats. StreetWear read each part's numbers back off its material;
  they are on `Building.parts` now.
- **Facade detail: one MultiMesh per kind a building** (`Frames`, `Details` = bands + parapet,
  `Bays`) on `shaders/facade_detail.gdshader`. The catch is the distance fade: a node's visibility
  range is measured from the camera to the CENTRE of its bounds (renderer_scene_cull.cpp, checked
  with a probe), so a node for the whole building would have moved every part's pop distance. Each
  instance carries its part index, the material holds each part's old bounds centre in TRUE world
  space plus its range (`part_ref`, `DETAIL_PARTS` 16), and an instance past its own part's range
  collapses to a point - in the shadow passes too, measured from MAIN_CAM_INV_VIEW_MATRIX as the
  culling was; the SDFGI voxeliser (identity main camera, and it ignored ranges before) is left
  alone. The node keeps a range that only drops the set once every part is past its own reach.
  True world, because the scene is re-centred: the new `origin_shift` global (vec3, project.godot)
  is pushed by a setter on `WorldState.world_offset`, so anything that sets the offset keeps it in
  step.
- **Roof plant: one mesh a building** (`RoofPlant`, `shaders/roof_plant.gdshader`): every box and
  cylinder `_build_prop()` laid (a duct run was nineteen nodes, a solar array eighteen), moved into
  building space, the material in the vertices (albedo and roughness in CUSTOM0, metallic in UV.x),
  with the unshaded beacons in a surface of their own. The rooftop air conditioners are one
  MultiMesh per model variant; their rolls are made in the old order.
- **Plinths** go into the chunk's merged boxes (`Building.plinth_in_chunk`, `CityChunk._merge_box`):
  world-triplanar concrete, the same wherever the box sits; the building keeps the collision.

Both replacement shaders are StandardMaterial3D's own generated code for those materials (from
the 4.7.2 source, `BaseMaterial3D::_update_shader`), line for line, down to the unset textures it
samples - replicating "ALBEDO = colour; ROUGHNESS = r" by hand was 1/255 off, because the
roughness hint's default texture is not white. A colour carried in a vertex has to arrive as the
renderer would have handed the uniform: RD converts a `source_color` uniform to linear on the CPU,
**Compatibility passes it verbatim** (drivers/gles3 material_storage has the conversion commented
out), so `Building._roof_albedo()` asks `RenderingServer.get_current_rendering_method()`. A probe
frame against frame: 0 pixels differ on opengl3.

### What is not identical, and why

City frames, `DIFF=1`, 1280x720 opengl3, before against after (two DIFF runs of the same tree
differ in 7 pixels, by 1-2):

| Bookmark | mean | p99 | p99.9 | max | pixels > 0 | > 2 | > 8 | > 32 |
|---|---|---|---|---|---|---|---|---|
| Downtown noon | 0.042 | 0 | 5 | 117 | 4,812 (0.52 %) | 1,230 | 793 | 428 |
| Downtown night rain | 0.017 | 0 | 1 | 201 | 2,983 (0.32 %) | 761 | 422 | 107 |
| Freeway | 0.017 | 0 | 1 | 148 | 1,646 (0.18 %) | 534 | 335 | 173 |
| Masjid | 0.029 | 0 | 3 | 145 | 2,145 (0.23 %) | 995 | 643 | 317 |

The heatmaps put every one of those pixels on three things, and `tools/building_merge_probe.gd`
(one building at a time, the old nodes rebuilt from the same data beside the new ones, each kind
swapped back alone, at 35-250 m, day and night) says which:

- **Rooftop units, the one intended difference.** A MultiMesh takes one LOD for all its
  instances from its whole box, so a far unit is drawn at the LOD of the building's nearest
  unit: the same or finer, never coarser. 600-1,100 px a building at 230-250 m in the probe, on
  both renderers; the triangle cost is the ROOF_TRIS numbers above. Keeping the units a node each
  would make them exact and cost about 630 draws downtown (buildings about 1,500 instead of 869).
- **Depth ties on the Compatibility renderer.** Coincident faces - the cornice's box band inside
  the kit moulding where both still draw, a billboard's stripe on its panel at 300 m - are
  decided by draw order there (GEQUAL, later wins), and a new shader changes the order. On
  Forward+ (lavapipe, one building) the detail swap is 0 pixels; on opengl3 it is 14-2,257 px a
  building, all on such seams. The stripe is geometrically in front, so where it now wins it is
  the right answer.
- **Float rounding on window edges.** The walls' merged mesh puts each part at its centre inside
  the building's space instead of in a node of its own, so a window edge a hair from a pixel
  centre can land the other side: at most 1,127 px a building on Forward+, of which 6 by more
  than 2/255. The roof plant: at most 14 px on Forward+, none by more than 2/255; 92 on opengl3.
  For scale, moving the OLD nodes by a re-centre (`SHIFT=1`) flips 34,000-98,000 px of the same
  building on opengl3; merged against old, 600-3,400.

The web (Compatibility) is the opengl3 path above, so it draws the same. The merged detail node
is one box for the occlusion culler where it was one per part, so a building half behind another
now draws all of its detail (its triangles fell anyway, and the tie-breaks above show nothing
else moved).

### Traps found on the way

- **Compatibility packs a MultiMesh's INSTANCE_CUSTOM and instance COLOR into half floats**
  (`unpackHalf2x16` in drivers/gles3 scene.glsl); RD keeps them 32-bit. A per-instance position in
  INSTANCE_CUSTOM is off by centimetres on the web, which moved pop distances - hence the part
  table in a uniform array and a part index (a small integer, exact in a half) per instance.
- **`NODE_POSITION_WORLD` in a GLES3 vertex shader is the multimesh INSTANCE's origin**
  (`model_matrix[3]` after the instance transform is folded in); there is no node transform.
- **A node's visibility range is measured to the centre of its world AABB**, not its origin.
- **`load("res://scripts/world/building.gd")` first, from a `--script` tool, walks into a preload
  cycle** ("building.tscn referenced non-existent resource ... building.gd"); load the scene first.
- **A script error in a `--script` tool's coroutine does not quit**: the tree keeps rendering and
  holds the render lock until the outer `timeout`. `building_merge_probe.gd` has a watchdog timer.
- **Two still_shot runs of the same bookmark differ in 41 % of pixels** (clouds, sway, film grain,
  traffic, the clock, all on real time). `DIFF=1` fixes that: shader TIME held at zero through a
  microsecond `time_rollover_secs`, the clock paused at `--hour`, the signals on a fixed clock,
  people, cars, aircraft, particles and the player hidden. Two DIFF runs differ in 7 pixels by 1-2.

### How to check it again

    # after (this branch) and before (its parent), same bookmark, same settings
    env OUT=a.png FRAMES=45 DIFF=1 [SPLIT=1] [ROOF_TRIS=1] LIBGL_ALWAYS_SOFTWARE=1 flock -o /tmp/rando_render_gl.lock \
      xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --display-driver x11 \
      --audio-driver Dummy --path . --script tools/glshot/still_shot.gd --resolution 960x540 \
      -- --spawn=2359.4,880,0,12,2 --hour=12 --weather=clear --nohud --quality=0
    python3 tools/glshot/img_diff.py before.png after.png heat.png
    # the merge itself, one building at a time, old nodes rebuilt from the same data:
    LIBGL_ALWAYS_SOFTWARE=1 flock -o /tmp/rando_render_gl.lock xvfb-run -a -s "-screen 0 1280x720x24" \
      godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
      --script tools/building_merge_probe.gd --resolution 640x360   # SHIFT=1, DIST=, ONLY=, NIGHT=0, SEEDS=, ELEV=

## 9y. Street level at night, 2026-09-25 (agent branch)

The ask: downtown at 21:30 in the rain read as one flat white fluorescent band along every tower
base - every open shop was the building's single `lit_color` at one strength painted flat over
the glass (the storefront fell through to the old flat-tile branch, not the traced room), every
sign band was lit alike, and nothing at street level had colour or threw light on the wet
pavement. The rules are in the Shop signs bullet of CLAUDE.md.

- **What changed.** Each shop's night is rolled from integers (`shop_hash()` in the shader,
  `Building.shop_hash()` bit for bit): about 62 % open, each open shop its own traced room in its
  own light (warm, neutral, cool, sometimes pink or teal) at its own brightness, a third with a
  neon piece (four SDF shapes, five colours) in the bay after the door; closed shops dark with a
  night light, over half behind a roll-down shutter (only with `lamp_factor` over 0.5). Sign
  bands: a closed shop's lightbox is off as often as not, and over half the boards are dark with
  lit channel letters (the board carries a stand-in strip of their colour from 58 m, before the
  letters cull at 75 m, and everywhere the letters are not drawn: web, landmark towers). Open shops throw a pool of their colour on the
  pavement: one additive `shop_spill` batch per FULL chunk (`CityChunk._add_shop_spill()`).
  Everything runs off `lamp_factor`; by day nothing differs (letters keep their cream and faint
  glow, shutters are up).
- **Cost.** One draw per FULL chunk for the spill (additive quads, no shadow, 170 m). The
  shader's new work is on storefront pixels only (a dozen integer hashes, the neon SDF in a
  neon bay); every other building pixel gains one `fwidth`.
- **Needs the Mac.** Judged on opengl3 stills only. On Forward+ the lit rooms and neon go
  through AgX and glow; check the neon is not blown out and the spill still reads on a soaked
  road (SSR will mirror the lit shopfronts too, which the stills cannot show).
- **Found, not fixed (next).** The shader measures the storefront as `fv = world_y /
  ground_floor_height`, a fraction of WORLD height, not of the storefront: on a building standing
  on raised relief the glass shrinks to a sliver and the sign band grows to metres (the huge white
  "RECORDS" lightbox on the brick street, `--spawn=-96,-230,-62,10`). The shop-name `band_y`
  (0.845 of the world height) was written to match it. The fix is `(world_y - base_y) /
  (ground_floor_height - base_y)` plus `band_y = bottom + 0.845 * storefront`, and it changes the
  day look of every raised storefront, so it wants its own before/after.

## 9z. Hill planting on the painted ground, 2026-09-25 (agent branch)

The ask: the hills' planting read as sparse dark dots and lollipop blobs over the new dry-grass /
chaparral / dirt / rock ground. Chaparral should be dense low dark-olive masses on the north
faces and in the gullies, oaks at the gully feet, single shrubs on the grass, nothing on rock
or cuts, and the range from the basin should read as brush-covered.

- **One field, two sides.** `HillPlanting` (`scripts/world/hill_planting.gd`) is the terrain
  shader's splat in GDScript: same `hash12t`, same value noise, same octaves and offsets, same
  thresholds (`MIRRORED`, checked against the shader source by the smoke test). So a shrub is
  planted exactly where the shader paints a brush stand, and never on what it paints as rock,
  a cut or a trail. `hollow()` (mean ground round a point minus the point, per metre) finds
  the gullies and slope feet. Across the front range the field puts brush on 68 % of the
  north faces and 27 % of the south ones.
- **Near (FULL hill chunks).** `CityChunk._plant_hills`, a new build step after
  `_scatter_hills` (its own rng per grid row; three rows a step, about 1 ms each on this box):
  a jittered 6.2 m grid; stand points get the searsia scan cut to ~3k triangles
  (`PropFactory.model_chaparral()`), wide, leaning into the slope, no shadow (the painted stand
  is the shade); deep hollows get an oak (`model_hill_oak()`, the island tree cut to ~20k,
  a few a block, with shadows); open grass a rare lone shrub. About 100-140 shrubs a block on a
  north face. Heights come off the chunk's own terrain grid (`_terrain_height`), not
  `height_at()`.
  Tints are over 1 (`1.75..2.15` brush, `1.35..1.6` oaks): the searsia's leaves are small
  sprites on a black atlas and tree_a's atlas is 75 % black, the mips average that in, and at
  the first tints (0.8) the stands and oaks were black shapes from twenty metres.
- **Far (Skyline).** `_add_hills` asks the same field on a 30 m height lattice: 28 tries a
  block, low mounds draped on the slope that grow into one mass in a stand's heart, dark oaks in
  the hollows, none on roads, pads, rock or cuts. `far_canopy.gdshader` now fixes the normals
  of squashed clumps (the renderer turns MultiMesh normals by the instance basis, not its
  inverse transpose, so a mound two or three times wider than tall drew black) - this also
  lights the far city's street-tree blobs correctly. `macro_ground.gdshader` puts more scrub on
  north faces (`north_scrub`).
- **Cost** (opengl3 geo counts, one run of six views in order, main 940bac8 -> this):
  hills bookmark 1.593 M -> 1.666 M triangles (+4.5 %), 989 -> 986 draws; basin 8.72 -> 8.82 M
  (+1.2 %), 4843 -> 4840 draws; downtown avenue 8.73 -> 8.84 M (+1.2 %), 4704 -> 4702 draws. Down
  among the stands it costs more: north face +14 % triangles / +5 % draws, gully +15 % / +10 %,
  a low slope view +22 % / +9 % (every FULL hill chunk adds a shrub batch and an oak batch with
  its shadow twin). Widening the shrubs afterwards changed no count.
  A far hill block costs ~1 ms to build instead of 0.2 (25 height samples plus the field), which
  is ~2 s more on the loading screen's whole-basin build on this box.
- **Needs the Mac.** Forward+ look of the stands (shrub colour under the real sky light, and
  whether the stands want their shadows back), the far mounds with correct normals at golden
  hour.

## 9aa. The palms' LOD ladder, 2026-09-27 (agent branch wt/tree-lod; roadmap #23, #32)

**What it was.** The branch held an unfinished WIP (69c6662) that split every heavy foliage
batch into distance cells (k-d split of the instance origins, `visibility_parent` hierarchy,
per-cell `lod_bias`), on the theory that a batch draws all its trees at the LOD of the camera's
distance to its box, so the trees of the block you stand in all draw full detail. Measured with
an in-process A/B (the same frozen frame drawn with the cells, then with the same batches
whole): freeway **+650 k triangles and +54 draws with the cells**, downtown noon +5 k (only 3
batches big enough to split - street trees are spread over 5 species and 6 palm variants, so
most batches are a handful of trees already), hills 0 (camera 260 m up, every batch past the
cell range). A whole batch's LOD distance is not its box's nearest point: for a block-wide box
it lands coarser than per-tree, so cells mostly ADD detail. The cells were dropped.

**What the triangles really were.** The palms. `PropFactory.palm()` was 20-27k triangles, and
its generated LODs could not thin it: the simplifier will not merge separate leaflet cards, so
the first LOD kept ~10k and reported ~1.6 m of error, which the renderer only accepts past
~560 m at 960 px (~1.2 km at 1440p). Every street palm, and MacArthur Park's whole ring in the
LOD chunks, drew full detail, and two of the six variants had no shadow stand-in at all.

**What landed.** A hand-built ladder, `PropFactory.PALM_LEVELS`: the same tree from the same
random stream at five levels - `stride` neighbouring leaflets merged into one blade of the same
area, fewer leaflet segments, coarser trunk, boots / coconuts / rib dropped far out, the coarse
levels' tones matched to level 0 (a one-piece leaflet took the tip's tone; the rib's dark share
goes into the leaflets). Triangles per level for the six variants: 20.3-27.3k, 7.8-10.5k,
3.8-5.1k, 406-528, 176-226. All levels live in ONE vertex buffer; the coarser ones are the
mesh's LODs, each at `edge` = its real geometric departure (0.22, 0.35, 0.7, 1.6 m: the width of
the merged leaflets, the dropped parts), so Godot switches under a pixel by its own rule and no
node, draw or script is added. The shadow twin is the ladder from level 1. Building the six
palms takes 650 ms (was 700: no simplifier pass). Smoke check `_check_palm_ladder()`: every
variant has the four LODs at those edges with falling triangle counts, a shadow twin, and every
level keeps level 0's crown extents (within its edge), leaf area (8 %) and tone (2.5 %).

**Numbers** (opengl3 / llvmpipe, `--quality=0`, bookmarks.sh with `SPLIT=1 PALM_AB=1`; before =
origin/main 8b264d1 in a separate worktree, after = this branch; draws = camera pass):

| Bookmark | Before tris (camera / shadow) | After tris (camera / shadow) | Change | Draws before / after |
|---|---|---|---|---|
| downtown_noon | 7,545,694 (4.86 / 2.69 M) | 7,025,920 (4.64 / 2.39 M) | -519,774 (-6.9 %) | 4,307 / 4,307 |
| freeway | 8,966,903 (5.67 / 3.30 M) | 7,738,005 (5.17 / 2.57 M) | -1,228,898 (-13.7 %) | 6,489 / 6,489 |
| masjid | 14,968,754 (10.81 / 4.16 M) | 12,795,652 (9.37 / 3.43 M) | -2,173,102 (-14.5 %) | 5,274 / 5,274 |
| hills | 1,664,763 (1.37 / 0.30 M) | 1,279,843 (1.14 / 0.14 M) | -384,920 (-23.1 %) | 725 / 725 |

Trees category (SPLIT): downtown 1.97 -> 1.45 M, freeway 3.42 -> 2.23 M, masjid 4.92 -> 2.75 M
(the hills row is not comparable: main's split did not count the `hill_*` batches as trees).
Objects and nodes unchanged. For scale, the same frames with every palm at full detail and no
LODs at all (`PALM_AB`): downtown 8.13 M, freeway 13.68 M, masjid 22.80 M, hills 2.73 M.

**Look.** Judged on the same frozen frame with and without the ladder (`PALM_AB=1`, which saves
`<name>_palmfull.png`; runs a minute apart cannot be compared, the foliage sway runs on the
render clock): near palms are identical (level 0), palm shadows identical at a glance, far palms
keep their crown shape, density and colour (crown mean within 1.5/255), and the only difference
is which pixels the sub-pixel leaflets happen to cover - the same shimmer the sway makes frame to
frame. Renders: `treelod_*` in the agent's scratch `screens/`.

**Still open.** The imported trees (`tree_a..d`, jacaranda) are what is left of the foliage
cost besides the palms' near levels. Their generated LODs carry the same kind of inflated error (the jacaranda's 30k-triangle surface reports 5.2 m at its first LOD, so it never
switches); roadmap #36. A leaf-card thinning ladder like this one, or measured geometric errors
written back as the LOD edges, is the next step. Web: the ladder works on Compatibility as is.

## 9ab. Real mountains, pass 1, 2026-09-27 (roadmap #34; owner: "the hills look like garbage")

What was wrong, in the order it showed:
- **Contour stripes on every far range** (the loudest tell, seen from the whole basin). The far
  ground read the bake's height with smoothstep-weighted bilinear, whose derivative is ZERO at
  every texel centre, so the normal went flat every 31 m and each range was a staircase of
  terraces. `macro_sample()` (macro_relief.gdshaderinc) is now a cubic B-spline with its
  analytic derivative (16 fetches); colour stays hardware bilinear. Stripes gone.
- **Shapes: cones, then combed streaks.** The range bases used the map's four-octave noise plus
  a second octave at 2.7x (a couple of hundred metres of bumps at every scale); the WIP cut a
  ridged noise stretched along the slope into that, which read as parallel combing. Now each
  range is a smooth base (`_range_noise`: the map noise's first two octaves, so the summits
  stay put - a fresh noise moved them and hid the ridge sign behind a crest) with erosion noise cut in
  (`MacroMap._erode()` / `_erosion_filter()`, after Fewes): gullies that run down each slope and
  branch off the coarser ones - canyons 440 m apart and their tributaries, up to ~130 m deep on
  the front range, weaker on summits and benches. Two orders in the height, two finer ones as
  shading (`shaders/erosion.gdshaderinc`, near terrain and far ground, off with ground_detail).
  `tools/terrain_preview/terrain_preview.tscn` shows it top-down in seconds.
- **Near hills lit like plastic.** The terrain mesh has no UVs or tangents, so its NORMAL_MAP
  did nothing. terrain.gdshader now builds its detail as world-XZ slopes (ground normal maps,
  brush canopy bumps, fine erosion) and sets NORMAL. Stands follow the land (`topo_weight` 0.8,
  was 0.45 - noise-led camouflage blobs), canyons darker (`drain_shade`), shrub models stop at
  110 m (they drew as black dashes past that).
- **Far ground denser:** GROUND_SUBDIVISIONS 200 -> 320 (44 m a vertex; ridges three km out
  were straight facets). Crags 70 -> 40 m. The plane's sink and crag fade now use distance
  across the ground (from the air the 3D distance put crags right over the streamed chunks).

Cost (this box, contended): a height in the eroded hills ~20-40 us, so the bake at load went
7.6 -> 12 s and a FULL hill tile's heights 14 -> 28 ms - now sampled a few rows a build step
(`CityChunk._sample_terrain()`, 2.5 ms budget); the planting and Skyline read the drainage off
their grids instead of calling `drainage_at()` again. Far ground +125k triangles (206k in all,
no shadow pass). Hill roads and estates planned: unchanged (28 / 318). The ridge sign has a calm
strip the length of its name (`_calm_spots`), everything else is eroded to within 90 m of a
landmark's box.

Still wrong / next (needs the Mac, Forward+):
- ~~The far ground is painted much darker than the streamed hill tiles~~ - FIXED later the same
  day (68604d4 and the commit after it). Traced in a worktree of its own with debug renders
  that emit, on both the plane and the tiles, the albedo, the normal, the coverage (brush /
  slope / drainage as RGB) and then a flat 0.1 grey: albedo, normals and brush share all matched
  across the seam, but lit with the same grey the plane came out at 0.64 of the tiles. It was the
  plane's SPECULAR 0.15 (Godot scales the grazing sky reflection by clamp(50 * F0, 0, 1), so an
  F0 under 0.02 loses most of it); with the tiles' 0.5 / 0.93 it was 0.90. The plane also draws
  the tiles' stands now, and ridge shadows past 500 m. Measured at the sign hill (linear
  brightness, plane / tile): 0.45 -> 0.66 -> 0.64 with the stands, the hard edge mostly gone
  (`<scratchpad>/mt/seam3/crop_ab.jpg`). What is left is resolution: the bake's slope and
  drainage are smoother than a tile's mesh, so the small benches that grow grass on a tile read
  as brush on the plane. Still wants a Mac aerial to confirm under Forward+.
- From the city the front range is front-lit in the afternoon and reads flat on opengl3 (crop
  std 3.9/255). Judge on Forward+ first; if still flat, more canyon shade on the far ground.
- The bake could be threaded (height_at writes last_drain, and ReplicaAreas/HillRoads have lazy
  caches, so it is not thread-safe as it stands).

## 9za. Wet streets that dry believably, 2026-09-25 (agent branch)

The ask: wetness was one global (`road_wetness`) laid evenly over every road, so when the rain
stopped the whole street dried as one sheet. Real streets after rain dry from the wheel tracks
and the crown, puddles shrink from their edges, pavements dry slab by slab, and the gutters hold
a band of running water to the end. The rules are in the Road surfaces bullet of CLAUDE.md.

- **What changed.** Weather publishes a second global, `road_drying` (0 while rain is wetting
  the street, ramped to 1 over `drying_switch_seconds` once the water is leaving). The amount of
  water is still `road_wetness`; drying only changes its shape. `shaders/wet_drying.gdshaderinc`
  turns a per-pixel `hold` into `film` (gloss, goes first) and `damp` (darkening, a little
  later), and is shared by `road`, `road_patch` and `road_paint` so patches and paint dry with
  the tarmac. road.gdshader builds `hold` from blotchy world noise, the puddle field (puddles use
  `sqrt(wetness)` while drying, so they outlast the tarmac and shrink from the rim), the camber,
  two wheel tracks per travel lane and the gutter; pavements drain `pavement_drain` sooner and
  each slab rolls its own pace. A ragged mirror band of running water with a sliding ripple sits
  at each kerb (`gutter_width`, `gutter_ripple`, `gutter_flow`) whenever the street is wet, rain
  included - that is the only change to the soaked look.
- **Kerbs without new data.** A road slab's UV already runs 0..1 across its rect (the lamp
  glow uses it); its width and length in metres come from the ratio of screen derivatives of
  `plan_pos` and the UV (exact, both are linear over the slab). Only a long slab of a street's
  width gets kerbs and lanes; junction squares, skirts (constant UV) and the replica's 6 m grid
  pieces get the noise alone.
- **Degrades to today.** Everything new is inside `road_wetness > 0.01` and `ground_detail`
  (off on the web and at LOW/LOWEST), and while it rains `film` and `damp` equal the old wetness,
  so the soaked-at-night look only gains the gutter. `PropFactory.set_wetness()` now always
  pushes the final 0 (steps under 0.01 were skipped, which could leave 0.009 standing).
- **Cost.** Dry: nothing (one uniform compare). Wet, raining: about 150 ALU and one extra
  normal-map fetch per road fragment (derivatives, two value noises, the gutter ripple). Drying:
  about another 110 ALU (two value noises, the film/damp ramps). Patches and paint: about 110
  ALU while drying, nothing otherwise. Roughly +15-25 % on a wet road fragment.
- **Judge it.** `--weather=clear --wetness=0.45` (web `wetness=0.45`) starts that wet and already
  drying; e.g. `--spawn=16,22,40,8 --hour=10 --weather=clear --wetness=0.6` for the day, the
  `downtown_night_rain` bookmark's spawn at `--hour=21.5` for night. Stills are opengl3.
- **Needs the Mac.** On Forward+ the gutter band and the drying puddles go through SSR: check the
  kerb water mirrors the shopfronts without a hard seam, and that the drying street at night
  still holds the lit windows in its puddles.
- **Finished 2026-09-27** (the branch above was an ungated WIP; this pass gated it and added):
  - `--wetness=` did nothing in a still: the loading frames are seconds long each and dried the
    street before the first frame. It now HOLDS the wetness and drying state (`_wet_hold`).
  - Raindrop rings in the puddles and the gutter while it rains (`rain_intensity` global,
    `rain_ripples()` in road.gdshader). The normal is now a slope sum (asphalt + gutter flow +
    rings) with `NORMAL_MAP_DEPTH` 1; a dry street measures the same as main.
  - The night city in the water (`mirrored_city()`): puddles at your feet mirror what is above
    the frame, which SSR cannot see, so on every renderer they were black. Emitted by Fresnel
    and `lamp_factor`; on Forward+ at `mirror_forward` 0.5 because SSR adds on top. The wet film
    gets only sparse shop-front streaks - the first version streaked every front and combed the
    whole street with even stripes.
  - Tyre spray (`TyreSpray`, a pool of 6 mist emitters Weather hands to the fastest cars near the
    player on a wet street). Judged only in a stand-in scene (`build/`, not committed): a faint
    veil behind the car. Needs the Mac at speed.
  - Cost: `tools/road_cost.gd` (one full-screen street slab, llvmpipe, ratios only). The WIP as
    left was +40 % on a wet road fragment against main's wet road; skipping the gutter noise and
    run-off fetch away from the kerb and the wheel-track noise outside the travel lanes brought
    it to raining +10 %, drying +8 %, night rain +18 % (the mirror is the extra 8 %); a dry
    street costs what main's does. Geometry: none (GEO lines equal within streaming noise).
  - Shots: branch `shots/wet` (before/after sheets and a README).

## 9ac. Street wear, 2026-09-27 (agent branch wt/street-wear)

VISUAL_ROADMAP #27. `StreetWear` (see the CLAUDE.md note under City) lays tags, throw-ups,
roller letters, buff-outs, wheat-paste runs, pole flyers and stickers, freeway-column paint,
grime along the foot of every street wall and gum / spill patches on the pavement, as ONE
transparent batch a FULL chunk. Art is original and generated (`tools/make_street_wear.py`;
the atlas preview goes to `build/`). Findings worth keeping:
- **The first version was invisible** and looked like a shader or batch bug; it was placement.
  On a slope a building's base sits up to a metre under the pavement and everything was
  measured from the base, so the grime and every low tag were under the paving. Heights now
  come from the pavement at the wall (`floor_of`), grime is laid in 6 m lengths that each
  follow it.
- Downtown shop fronts are glass to a 0.6 m bulkhead, so an all-wall rule found almost no room:
  tags now go on the shop piers (`PIER_TAG_SHARE`) and may run over `TAG_SLACK` of glass/frame.
- Instance custom data reads back as zero under `--headless`, so the smoke test counts modes
  from the chunk meta `street_wear_modes`.
- `still_shot.gd` `SHOTS="x,y,z,yaw,pitch@hour;..."` takes several views from one load (a load
  is most of a shot's 8 minutes on this box).
Numbers: downtown blocks 150-250 instances, industrial ~300, cap 520. Frame cost on the
bookmarks: +2 draw calls, +6-8k triangles (~0.1 %); the transparent overdraw of grime strips
is not measurable here. Screens: branch `shots/wear`. **Needs the Mac:** how the paint's
screen-grain and roughness read under Forward+ light, and whether grime wants to be lighter.
Next: tags on the night roll-down shutters (building shader), more storefront-level paint.

## 9ad. The port on the bay, freeways clear, the arena district filled (2026-09-27, wt/downtown-relay)

Owner asks: the San Pedro port stood on an inland harbour in the middle of the city; freeways
drove through buildings downtown; the arena district's civic blocks (grown at 1:1) were bare
paving. On `wt/downtown-relay`, on top of the 1:1 re-lay (9s), merged with main, gate green.

- **Port.** `MacroMap.port_rect` (2750, 5935, 630 x 560) on San Pedro Bay just east of the Palos
  Verdes headland's land end, its south third out in the bay, the berth (`harbor_rect`) and the
  cargo ship (3065, 6522) off its south quay. `bay_east_x` 1600 -> 4700 so the bay wraps the
  headland's south and east; Long Beach's sand east of the port (`bay_beach_depth`). The old
  inland harbour (z 3300) is city. The 110 runs on nearly due south from the 10 to the port's
  north-west corner. Hill/sea chunks on the headland's elliptical shore build both terrain and
  water (`CityChunk._headland_shore()`), or the shore showed as a wall along the chunk line.
  Check: `_port_on_the_bay()` in `tests/downtown_checks.gd` (no enclosed water anywhere in the
  basin, the old harbour is city, open sea off the whole south quay out past the bay mouth, the
  headland within 1.2 km west, the 110 ends at the gate).
- **Freeways.** `Freeway.blocks_rect()`: no lot, plaza or big-box part within 3 m of a deck or
  ramp (commit 2ed81e1); the 405 stops `AIRPORT_KEEP` short of the airport; the 105 keeps its
  line south of downtown. Check: every deck segment within 800 m of downtown against every
  captured box, the towers, civic sites, the masjid, the airport and the port.
- **Arena district.** `ArenaGrounds` (`scripts/world/arena_grounds.gd`): multi-storey car park
  (`garage()`), planting beds, bosques with ring benches, bronze figures, surface lots, a second
  exhibition hall. The arena is real size (glass radii 54 x 45, drum 40 m) with a four-level car
  park on its west. A civic site keeps its table footprint (centred on the real building, which
  the tolerance check holds), so the REST of each block is `ArenaGrounds.leftovers()` (the block
  less every district site in it, owned by the first site in `CivicSites.ORDER`) filled by
  `build_leftovers()`: the arena block's north strip is a grove, beds and figures, its south a
  surface lot; west of the hotel a five-level car park; south of the convention centre a second
  hall. Parked cars are a ~260-triangle code car (`car_mesh()`), not the traffic bodies: those
  are 8,000+ triangles with LODs that stop at half, and 250 of them cost 3 M triangles.
- **Cost** (opengl3 GEO, triangles, same cameras): arena corner 6.57 M -> 7.79 M (+18 %), the
  aerial 6.12 M -> 6.78 M (+11 %), district top-down 4.79 M -> 5.23 M (+9 %), the plaza from the street 6.52 M -> 7.42 M (+14 %); draw calls +1-11 %; most of it trees (+0.5 M, two
  thirds shadow) and the bigger arena. Trees in the groves are spaced 12-14 m and drop out at
  280 m. Stills and sheets: branch `shots/relay`.
- NOT done: the port's containers and cranes are still primitive boxes (roadmap #35); garage
  interiors read as dark bands from the street (the spandrels hide the cars inside, as in life).

## 10. Suggested next steps, in order of impact

Rewritten at the 2026-09-24 wrap-up. The 2026-09-21 list follows it, kept because items 1 and
4-8 of it are still open.

1. **MacArthur Park is on** (9r). What is left there is 9r's own list: the Blender bake of the
   encampment kit, nobody having seen the poses move, the police cruiser that can start inside
   a crossing next to the park. The hero pass that used to be item 1 is merged (section 0).
2. **The 1:1 downtown re-lay - LANDED 2026-09-25** (9s). What is left of it: Bunker Hill as a
   hill, Little Tokyo and the east side as real streets, the real interchange ramps, the civic
   builders at real size (the arena is a third of its real width in its real 240 x 330 m block),
   and a look at the new skyline on Forward+ at golden hour (NEEDS MAC CHECK).
3. **Judge today's work on Forward+.** Almost everything merged on 2026-09-24 was judged on the
   opengl3 preview, because the shared render lock was saturated: the night GI change (was
   night paving orange from SDFGI bouncing emission?), the skyline's crowns at dusk, the civic
   set at night, the lens pass, the concert hall's steel. `tools/glshot/forward_shot.sh` or the
   `still_shot.gd` Forward+ invocation; about eight minutes and 7 GB a shot.
4. **The hills.** In every preview shot the mountains read as flat brown with horizontal bands
   (the station and skyline stills in 9o / 9n show it). Judge it on Forward+ before touching it -
   the preview has no sun shadows and flattens relief - then look at `terrain.gdshader` (near),
   `macro_ground.gdshader` / `MacroMap.bake()` (far) and whether the bands are the carved hill
   roads and mansion pads. Real LA hills are dusty grey-green chaparral in the folds and pale
   gold grass on the open slopes.
   *Near half done 2026-09-24:* `terrain.gdshader` is now a dry grass / chaparral / dirt / rock
   splat by slope, aspect and noise (GAME_PLAN decisions log). Still to judge on Forward+, and
   the far half (`macro_ground.gdshader`, the bake's bands) is untouched.
5. **The hero up close.** The jacket collar clips into the neck when aiming (the AK side shot
   in the scratchpad showed black shards over the throat) and the hair cards read blocky at
   face distance. The AAA pass branch (section 0) was on exactly this.
6. **Build hitches in the civic set**: each landmark builds in one step (museum 68 ms, arena and
   city hall 35 ms warm); split them into chunk build steps like everything else.
7. **Interiors** (item 4 of the old list) remain the biggest change to how the game plays.
8. **Headless log noise.** Every smoke run prints ~5,000 "Cannot set a buffer on a Multimesh
   that is a different size" errors from the shadow twins (`MultiMeshBatch.build()`,
   `twin_mm.buffer = mm.buffer`): under the dummy renderer the instance buffer reads back empty.
   Harmless and not on the gate's tripwire list, but it buries real errors; skip that copy when
   `DisplayServer.get_name() == "headless"` (or copy per instance there).
9. **The suite's length.** With every branch merged the smoke test is ~420 checks; its watchdog is
   840 s (`SMOKE_WATCHDOG` overrides) inside a 900 s timeout in `tests/headless_check.sh`. If CI
   starts timing out, split the checks files into a second scene rather than raising it again.

The 2026-09-21 list:

1. **The 90s cinematic colour grade.** The owner asked for it on 2026-09-21 and deferred it the
   same minute ("we can explore that later tho"), so it is queued rather than started. The spec
   is in `docs/GAME_PLAN.md` under "Owner requests queued" - read it before starting, because the
   obvious implementation (crank saturation and contrast) is the wrong one. It is a post pass: a
   Texture3D LUT built in code on the city Environment's `adjustment_color_correction`, so no
   editor step and one switch to turn it off.
2. **Judge everything on Forward+ from now on.** `tools/glshot/forward_shot.sh`. This is a
   working practice, not a task, and it is first among them because the alternative has already
   cost this project one entirely broken subsystem (see build 130).
3. **The distance - next step up.** The tiers now cover everything (section 9p). What is left is
   quality at range: real impostors for the far city's towers (they are shaded boxes, as the LOD
   chunks draw them), hill roads painted on the horizon plane, and a Forward+ look at a hills
   still to settle the plane-vs-LOD-terrain colour seam the opengl3 stills show.
4. **Interiors.** Windows have traced fake rooms; doors and lobbies do not. A handful of enterable
   ground-floor interiors would be the biggest single step left in making the city feel real, and
   it is the one thing on this list that changes how the game plays rather than how it looks.
5. **Traffic and parked cars on the hill roads**; pedestrians on the campus quad and the pier.
6. **Wind on the bushes and hill scrub.** Palms and tree leaves sway
   (`shaders/foliage.gdshader`, `foliage_tex.gdshader`); `model_shrub()`, `model_scrub()` and the
   hill grass tufts are still dead still and would take the same treatment.
7. **Shop names at a distance.** Each name is a TextMesh and they stop at 75 m. Rasterising the
   whole name list into one atlas at load and sampling it in the fascia branch of the building
   shader would put a name on every band at any distance, with no geometry at all.
8. **Animation blending** for pedestrians (idle / walk / run, turning) and reactions to cars and
   gunfire.

## 11. Quick test script to give the owner after any push

"Grab build-N from the Releases page (or the browser build with ?showroom). Walk, shoot a
pedestrian, take a car across town and into the hills, get out on a slope, fly a jet from the
airport, watch a sunset (Esc shows the clock). Tell me what looks or feels wrong."


## 9ae. Downtown encampments x20, 2026-09-27 (agent branch `wt/downtown-homeless`)

Owner: "downtown needs way more homeless people - whatever you think it should be, multiply by
20". The branch's earlier WIP (two ungated commits) had already made the camps denser: a
skid-row band east of the centre (`Encampment.skid_row()`), whole faces wall to wall there, a
kerb row of carts and bags, camps under the freeway decks near downtown and across from
MacArthur Park, new poses (CHAIR, STAND, PUSH with a loaded cart) and two new kit pieces. What
it lacked was the cost: every person was a live RoughSleeper (237 rigs round skid row).

- **Static figures** (`CampFigure`, `CampFigureMesh`): everyone sitting, lying or slumped is
  baked once per (model, pose) - a RoughSleeper posed off-screen, its welded middle body skinned
  on the CPU - and a chunk's figures are merged into ONE mesh (a surface per material; seeds are
  searched so each model has one look and no cap or pack, so three surfaces a chunk) plus a
  one-surface shadow twin from the far bodies (shadows stop at 60 m). A round, a blast, a bumper
  or gunfire nearby (`Pedestrian.alarm()` -> `CampFigure.wake_near()`, the nearest four within
  26 m) wakes a figure into the live RoughSleeper with the same seed, pose and spot; the mesh
  is rebuilt without it. The loading screen bakes all 45 kinds. Standing people and cart pushers
  stay live, capped per chunk and under the crowd cap.
- **Numbers** (tools/camp_census.gd, 25 detailed chunks): skid row 339 people (8 on main),
  downtown centre 165 (10), the noon bookmark's block 61 (9); pieces round skid row 110 -> 3,637.
  GEO (opengl3): downtown_noon 7.63 M -> 7.59 M tris, 4,285 -> 4,213 draws; a skid-row street
  6.33 M -> 6.63 M (+4.7 %), 4,413 -> 4,664 draws (+5.7 %); skid-row corner 5.28 M -> 5.57 M,
  3,026 -> 3,312 draws. The first cut (a MultiMesh per model and pose) was 722 camp draws at
  the corner; merging, one look per model, no shadow on flat pieces, a 70 m shadow distance and
  fewer loaded carts brought it to ~480. `SPLIT=1` on still_shot.gd now has a Camp category.
- **Not done / to judge on the Mac**: figures within a few metres are the ~2k-triangle middle
  body (fine at street distance, a little flat at arm's length - promoting the nearest few to
  live rigs by distance would fix it); the camp kit is still ~18 MultiMesh keys a chunk; some
  walkers near camps read oddly in stills (arms held out) - not traced, may be the standing
  people's idle clip. Screenshots: branch `shots/homeless`.

## 9af. The scanned trees' measured LOD ladders, 2026-09-27 (agent branch `wt/tree-lod-2`; roadmap #36)

**What was wrong.** The imported Poly Haven trees took `ImporterMesh.generate_lods()` as it
came, and its errors (the simplifier's quadric error with the normals weighed in, scaled by the
mesh size) are wrong both ways on a tree: the trunks and the jacaranda's 30k-triangle twig
cards said 3-10 times their real departure and never switched (5.2 m on the jacaranda's first
twig LOD), while the leaf cards said 7-24 cm as the simplifier DELETED cards - tree_a's leaves
kept 71 % of their cover at the first LOD and 0 % at the last, which they took from ~85 m at
960 px. Canopies thinned and went bare with distance, and so did their shadows: the old
stand-ins were a 45 %-of-triangles cut of those same LODs (tree_a's shadow had 71 % of the
canopy's cover, and its own generated LODs thinned it further).

**What landed.**
- `FoliageLod` (`scripts/world/foliage_lod.gd`) builds, per surface of each tree, a ladder the
  table `scripts/world/foliage_lod_table.gd` names, and `tools/foliage_lods.gd` measures and
  writes that table (`godot --headless --path . --script tools/foliage_lods.gd`, ~5 min;
  `REPORT=1` prints the candidates). Candidates: the generated levels, and THINNED copies of any
  surface of 200+ small pieces (leaf cards, twigs) - every stride-th piece (2..32) in Morton
  order, at the phase that keeps the tone, each grown about its centre so the level's textured
  cover (area times the atlas cut-out) is exactly level 0's, slid back inside the surface's
  bounds; pieces over 3x the median size (limbs) are never thinned. Each is measured against the
  full surface by exact point-to-triangle distance both ways (2,000 area-spread points each way);
  its edge is the larger 98th percentile. Rules: a leaf surface (or one mostly cards) may not
  lose 15 % of its cover (that throws out every generated leaf LOD), a thinned level may not move
  its 1 %/99 % outline further than its edge, and the trade-off front is kept with steps of at
  least 30 %. All levels in one vertex buffer, the coarser ones as LODs, as the palms (9aa).
- `MultiMeshBatch.build()` sets a ladder batch's `lod_bias` to its biggest instance's scale (a
  batch picks its LOD from the node's scale only; street trees are planted at 0.5-1.5x, the
  landmark groves up to 3.6x), and the shadow twin's to `FoliageLod.SHADOW_LOD_SCALE` (0.5) of
  that. The twin itself starts at the coarsest level under `SHADOW_EDGE` (0.22 m at the
  species' tallest street planting, `PropFactory.foliage_planted_scale()`).
- Trees only (`PropFactory.foliage_ladder_files()`: CITY_TREES, HILL_TREES). The knee-high
  plants were measured on ladders too and came out MORE expensive (+0.24 M at downtown noon),
  because their generated LODs save by dropping cover; they keep them, as do the budgeted
  chaparral and gully oaks (their look was tuned on their cut).
- The loading screen builds every species' ladder (tree builds 2.2 s in all here against 0.9 s
  for the generated LODs alone; most are already built by the blocks round the spawn).
- Smoke checks: `_check_foliage_ladders()` (the table still matches every model, LODs at the
  table's edges with falling counts, the shadow twin where it should start, every thinned level
  within 2 % of level 0's cover and 2.5 % of its tone, its outline within its edge) and the
  street-tree batches' bias.

**The counter trap** (CLAUDE.md measurement trap 3). The first A/B said the ladders ADDED
triangles (+0.23 M at downtown noon, +2.5 M on the freeway). They did not: both renderers count
a surface with LODs once per draw call and a surface without LODs once per instance, and the
shadow twins' last levels had no LOD below them where every old stand-in surface had some - so
the same batch counted as one tree before and as forty after. Every ladder surface (and twin
surface) now ends with a copy of its last level, one triangle short, at an edge nothing reaches
(`FoliageLod.COUNTER_EDGE`, 1e6 m): it never draws, and the HUD and `GEO` count the trees the
way they count every other LOD'd batch (one instance a batch - an undercount everywhere, but
the same one on both sides). `TREE_AB=1` on `still_shot.gd` now prints `TRUE` lines that
count every instance at the LOD the renderer picks (its own rule, frustum
culled, shadows once per cascade slice the batch meets - on a controlled scene within one
cascade of the renderer's own draw count); `TREE_AB=2` adds each species alone and the shadow
bias variants. The palms' numbers in 9aa were taken with the same counter (their surfaces all
have LODs both sides, so they counted one palm per batch both sides: the real saving was larger).

**Numbers** (opengl3 / llvmpipe, 1280x720 window, `--quality=0`, the same frozen frame drawn on
the old meshes and on the ladders; trees only, every instance counted):

| Bookmark | Before (camera / shadow) | After (camera / shadow) | Change | Engine GEO, whole frame |
|---|---|---|---|---|
| downtown_noon | 5.47 M (2.26 / 3.21) | 3.41 M (1.44 / 1.98) | -2.06 M (-38 %) | 7.80 M -> 7.52 M (-3.5 %) |
| freeway | 11.38 M (5.61 / 5.77) | 8.80 M (3.72 / 5.08) | -2.58 M (-23 %) | 7.20 M -> 6.90 M (-4.2 %) |
| masjid | 8.11 M (3.71 / 4.41) | 5.75 M (2.09 / 3.66) | -2.36 M (-29 %) | 8.86 M -> 8.50 M (-4.1 %) |
| hills | no tree batch in view or in a shadow slice from 260 m up | | 0 | 1.96 M -> 1.96 M |
| civic centre (`--spawn=2600,-450,-50,-4,60`) | 5.58 M (1.90 / 3.69) | 3.88 M (1.27 / 2.61) | -1.70 M (-31 %) | |

Draws and objects are unchanged everywhere (same batches, same twins). The engine GEO column
counts every LOD'd batch as one instance (trap 3), so it moves by far less than the work does;
it is there so this row compares with the 9x / 9aa tables. The shadow twins' 0.5
bias is worth -0.42 M at downtown noon and -1.14 M on the freeway (TRUE, the same frame at
bias 1); at bias 1 the freeway's tree shadows would cost 0.45 M MORE than the old stand-ins,
which thinned away with distance. Per species at downtown noon (each alone put back on the old
mesh): the jacaranda saves 0.87 M, tree_b 0.41 M, tree_c 0.25 M, tree_a 0.11 M.

**Look.** The same frozen frame on both meshes (`TREE_AB`, so the foliage sway cannot differ):
downtown noon 0.28/255 mean difference, 0.46 % of pixels over 24/255 - the canopies'
self-shadow pattern (the twin is now a cover-keeping thinned level) and sub-pixel speckle on the
furthest crowns; the near tree and its shadow on the pavement are the same at viewing size.
The one change you can see is the fix: from the civic-centre still, the street trees 60-200 m
away were bare trunks on the old meshes (their leaf LOD had reached 0 % cover) and have their
crowns back, and so do the far crowns round the masjid. Renders: `trees2_*.jpg` in the agent's scratch `screens/`.

**Still open.** The knee-high plants still thin with distance (their generated LODs); a
cover-keeping ladder for them needs thinning that works on a few dozen pieces a surface. The
jacaranda's twig surface stops at 13.9k triangles (its limbs are never thinned, the generated
levels past the first lose its twig cards' cover, and the coarse thinned levels moved its
outline); thinning the cards over a generated LOD of the limbs would take it lower. The budgeted chaparral and gully oaks are untouched. Web: LODs work on
Compatibility as they are; not tried in a browser.

## 9ag. The container terminal's kit, 2026-09-27 (agent branch `wt/port-assets`; roadmap #35)

The port on San Pedro Bay (9ad) was still the old primitives: 12 m boxes in six flat colours in
single file, orange slab cranes, a white concrete sheet, a box hull half on the quay. All of it is
now built in code by `PortKit` (`scripts/world/port_kit.gd`); no model files.

- **Containers**: ISO 668 boxes, one mesh with a hand-built LOD ladder (568 / 142 / 12
  triangles) and a box shadow twin. 20 ft and high-cube boxes are the same mesh scaled - the
  vertex shader keeps every vertex near an end at its distance from that end - so the far city,
  the MultiMesh bounds and collision need nothing extra. `shaders/container.gdshader`: ISO
  corrugation (a normal tilt with a three-step parallax march; the flutes hide the grooves at a
  grazing angle), invented liveries and a stroke font (`port_lettering.gdshaderinc`: RANDO,
  KAVELL, TORVAN, ZEPRA, OLVANA, MERIDU, two leasing pools, old brown boxes; owner codes, serials
  and size codes on doors and sides, a CSC plate), rust streaks, repaint patches, road dirt,
  dents, a wet sheen. Two piles abreast a slot, 22 % 20 ft pairs, 45 % high-cubes.
- **Layout kept**: rows, columns, the 30 % truck lanes, the 35 % empty slots, the heights and the
  per-box colour roll are the old rolls in the old order on the block rng; the colour roll now
  picks the shipping line of that hue. Everything new is a private stream.
- **Cranes**: ten ship-to-shore cranes (two a quay chunk; 30.48 m gauge, 60 m outreach, girders
  at 44-47.6 m, A-frame to 80 m, bogies, stairs, lift, machinery house, trolley, cab, spreader;
  3.8k / 1.7k / 0.7k triangles). The three within 95 m of the ship work it (boom down, trolley
  out, a box on most spreaders); the rest stand with booms raised. Built at FULL and LOD; the
  far city draws each as 12 boxes. Yard gantries (RTG, 1.4k triangles) straddle three rows in
  most inland chunks, legs in the 3.9 m aisles. High masts (FULL only), crane rails, a coping
  with bollards and fenders, yard slot outlines, lane dashes, apron lanes. At night the masts
  and cranes lay soft additive light pools on the yard and the apron (FULL and LOD), crane
  cabs, floodlights and the ship's windows glow; by day the pools cost nothing.
- **The ship**: `cargo_ship` moved 6522 -> 6541 (its landward 12 m stood on the yard). A lofted
  hull (flared bow, forecastle, sheer, navy topsides, boot-top, a white sheer line, RANDO in 4 m
  letters down both sides), hatch covers, lashing bridges, a breakwater, the accommodation block
  with window rows lit at night, bridge wings, radar mast, funnel with a teal band, a freefall
  lifeboat. Its deck cargo is the real container mesh, three abreast in each old slot.
- **Streaming cost**: the port block is three build steps now (yard and stacks, paint, cranes),
  every piece lifted by the slab's single relief lift instead of sampling the relief per piece
  (the paint alone sampled it ~2,000 times), and the kit's meshes are built on the loading screen
  (`PortKit.warm()`, ~100 ms). A FULL port chunk: 2.5 ms -> 3.3 ms total, worst step 3.2 ms ->
  1.9 ms; LOD: 1.3 -> 1.0 ms (headless, this box).
- **Frame cost** (`tools/geo_count.gd`, opengl3 800x600, same spawns, before -> after): the
  port from 60 m up (`--spawn=3065,6300,0,-10,60`) 1.31 M -> 1.40 M triangles (+7.5 %), 1,221
  -> 1,283 draws; a far aerial (`--spawn=2400,5550,-135,-24,350`) 2.43 M -> 2.46 M (+1.2 %),
  3,068 -> 3,079 draws; standing in the stacks (`--spawn=3003,6256,-78,3,2`) 767 k -> 895 k
  (+17 %), 640 -> 706 draws (about 18 of the new draws are the night pools, which draw by day
  at zero alpha). The stacks case is the camera's own chunk drawing all ~260 of its boxes
  at the full level (a MultiMesh takes one LOD from its bounds, and the camera is inside them):
  ~150 k triangles, small next to a downtown frame's 7-9 M. Splitting a chunk's boxes into two
  batches would halve that for +2 draws a chunk.
- **Not judged**: everything here was seen on the opengl3 preview only (the lavapipe Forward+
  path is OOM-killed on a city). Needs the Mac: the corrugation's normal tilt under real sun and
  SSR, the roof bleaching, the night look (cab glass, floodlights, masts, accommodation windows),
  and whether the yard tint (0.44) wants to go darker. A container at arm's length is still
  flat-faced corrugation (a normal trick with parallax, no geometry). Straddle carriers, trucks
  and moving cranes are not done. `tools/glshot/port_shot.gd` shows the kit alone in seconds.
## 9ah. The crowd, real people, 2026-09-27 (agent branch `wt/crowd-humans`)

The ask: replace the nine Meshy pedestrians (pedestrian_d..l), which read as plastic mannequins
(roadmap #11: the look is baked into their single photo texture and no shader fixes it), with
realistic people at "AAA studio PS5 quality", made with the hero's pipeline.

- **What shipped.** Twelve people, `assets/models/crowd_a..l.glb` (the roster with each one's
  CC0 sources is in docs/ASSETS.md "The crowd"): young to elderly, men and women, slim to heavy,
  1.55-1.84 m, Black, white, East Asian and two Latino complexions (blends of the pack's skins).
  `Pedestrian.MODELS` is now only these; `OFFICER_MODELS` is five of them (trousers, short hair).
- **How they are built** (`tools/crowd/`, CLAUDE.md "The crowd" has the commands): per row of
  `crowd_config.json`, `build_character.py` makes the MPFB human (phenotype, targets, skin, eyes,
  brows, lashes, library clothes, shoes and hair), binds it like the hero (arms lowered, elbows
  opened) with a relaxed hand baked in and the finger bones folded into the hands (24 bones),
  deletes MakeHuman's masked skin and whatever a garment covers, cuts every part to a triangle
  budget (head and hands keep most of the skin's), then plans the atlases: every source texture's
  used islands (overlapping ones merged: hair cards share strips) cropped, scaled per part and
  skyline-packed into a 2K body atlas and a 1K hair atlas. `crowd_atlas.py` composes them (skin
  blends, dyes, logos painted out, garment AO multiplied in, skin relief from the photo's own
  detail, the scalp under the hair painted in the hair colour); `crowd_export.py` retargets
  idle / walk / run with the hero's code (moved into `tools/hero/retarget_lib.py`, `retarget.py`
  calls it; the crowd's idle has its legs settled 65 % back to its own straight stance, see
  below) and writes the .glb. All twelve: about 25 minutes on a loaded 4-core box.
- **The contract** (checked by `_check_crowd_rigs()` in the smoke test): one skinned `Body`
  surface whose vertex colour is the region split (R top, G bottom, B hair / painted scalp,
  A skin; none = shoes, eyes, and garments marked `keep` like the overalls), and a `Hair` mesh of
  cut-out cards on `shaders/crowd_hair.gdshader`. `character.gdshader`'s new `region_mask` path
  recolours a look exactly from that split, keeping the source's shading as a ratio to each
  region's mean (`Pedestrian._region_means()`, measured once per rig at load; defaults under the
  dummy renderer). The crowd keeps its own hair colours. Every system that swaps materials, cuts
  limbs (`Ragdoll.dismember`, `warm_limbs`), welds middle / far bodies (`far_mesh`, `warm_far_mesh`),
  stains a body or bakes camp figures skips `Pedestrian.is_hair()`; the hair is hidden past
  `mid_body_range`, under a beanie and under the police cap; police and rough sleepers get
  `plain_hair()` (the sleepers' dulled, `RoughSleeper.WORN_HAIR`).
- **Measured.** All on this box (opengl3 / llvmpipe, `--quality=0`), before = the base commit
  74c8567 with the nine generated rigs, after = this branch:
  | | before | after |
  |---|---|---|
  | downtown_noon (SPLIT, 1280x720): frame triangles | 7,790,383 | 7,398,767 (-5.0 %) |
  | - of which pedestrians | 734,703 (266k shadow) | 354,583 (78k shadow), -52 % |
  | - draws / objects | 5,725 / 5,822 | 5,740 / 5,837 (+15: the hair cards) |
  | geo_count at `--spawn=2359.4,880,0,12,2` (800x600) | 5,815,164 tris, 5,199 draws | 5,440,633 tris (-6.4 %), 5,214 draws |
  | Street at eye level, same spot, 4 views (still_shot EYE / SHOTS) | 5.62 / 6.64 / 7.71 / 7.12 M | 5.33 / 6.45 / 7.40 / 6.76 M (-3 to -5 %), +5 to +16 draws |
  | People's share of the loading screen (`tools/crowd/people_load_bench.gd`) | 9 rigs 1,295 ms + 45 camp figures 684 ms = 1,980 ms | 12 rigs 1,052 ms + 60 camp figures 788 ms = 1,841 ms |
  LOD0 is 10.5-12.7k triangles of body plus 0.4-3.8k of hair (the old rigs were 16.6k in one
  piece whose importer LODs stopped at 8.3k: these are welded, so the generated LODs go lower,
  and the shadow pass loses the hair entirely). The welded middle / far bodies build from the new
  rigs unchanged; side by side at 60 m (FOV 75) with the full model they read the same, the hair
  standing in as the painted scalp. Texture memory: a 2K colour + 1K normal + 1K RGBA hair atlas
  per person (about 5.6 MB of VRAM each, S3TC / RGTC with mips: ~67 MB for twelve, against ~18 MB
  for the nine old rigs' 1K colour and normal maps).
  Repo: +49 MB of assets (the glbs embed their atlases and Godot extracts copies).
- **Judged** (opengl3 stills and `tools/glshot/crowd_lineup.gd`, the new side-by-side tool with
  `SHOTS=` for several views per load and `BODY=mid|far`): at street distance (5-30 m) they read as people - real
  proportions and builds, a range of ages and complexions, clothes that sit on the body, and the
  exact recolour gives a varied street without the old rigs' printed-on look; the Meshy rigs had
  more high-frequency texture (a photographed beard, a creased jacket), which at 10 m some will
  prefer. Up close the MakeHuman faces and garments are "good 2014 game", not PS5: soft
  textures, generic faces, relaxed-but-stiff hands, the photographed tees and jeans. Hair cards
  read well on the afro, braid, ponytail and long styles; short02 read as a cap and was dropped
  for a painted crop. The light skins run pale in the flat harness light; the elderly woman's
  skin is toned down (`skin_tone`). None of it has been seen on Forward+ or the owner's Mac.
- **Traps found on the way.** (1) The Meshy clips copied bone-for-bone into a body bound standing
  straight give an idle with the legs apart and the knees bent (the source rigs are bound that
  way, their idle hips ride 4-9 cm high, and ours had to drop 11 cm to plant the feet): the
  retarget now takes `settle_legs` per clip. (2) MPFB bodies carry a `scalp` vertex group, so a
  mesh attribute cannot be called "scalp" (Blender refuses the name, silently: the layer is
  None). (3) Hair cards reuse strips of one photo across many islands: packed island by island,
  a braid's texture went into the atlas 100 times at a fifth of its resolution. (4) A MakeHuman
  garment's pocket flaps and waistband follow the hips alone, so a top/bottom split by bones
  needs a per-garment rule (`"hips": "top"` for a jacket over jeans). (5) The palm twist of
  `fix_arm_pose` (32 + 28 degrees) was checked against 0, -65 and +120 on these rigs from the
  front and the side (`twist` probe renders): the existing numbers put the backs of the hands
  outward, which is right; what reads as clawed is only the curl.
- **Not done / next.** (1) Look at it on the Mac (Forward+, AgX, auto exposure): skin
  tone, hair, the hands. (2) The biggest visual gains left are in textures, not geometry:
  delit, higher-detail garment textures (our own garments the way tools/hero/tracksuit.py
  makes the tracksuit - hoodies, chinos, dresses), a pore / crease detail map on the faces like
  the hero's, beards. (3) More people: every row of crowd_config.json is a minute or two; the
  pack has six suits for men, four for women, ten hair styles - more variety needs our own
  garments. (4) The web build: every glb embeds its atlases (and the old rigs are still in the
  export), about +49 MB; an export exclude filter for the unused `pedestrian_[a-l]*` and
  `tools/shrink_glb.py`-style JPEG bodies would claw most back. (5) Branch `mountains` moved on
  (tree LOD ladders, new car bodies) and was not merged into this branch here; nothing in it
  touches the crowd files, the likely conflicts are CLAUDE.md, loading_screen.gd and
  smoke_test.gd (adjacent hunks).

## 9ak. The hill ground from standing height, 2026-09-27 (agent branch `wt/hill-ground`; roadmap #19, #33, #34)

The ask: a player who lands on a hill saw smooth plastic ground with camouflage blobs of dark
olive brush and tan grass, a few rocks and almost no vegetation.

- **Hill shells** (`HillShells`, `scripts/world/hill_shells.gd`; `shaders/hill_shells.gdshader`).
  Every FULL hill chunk draws its terrain mesh again as 16 lifted layers: a MultiMesh of that one
  mesh with identity instances, the layer's height in `INSTANCE_CUSTOM.r`. One draw per tile, no
  vertex or index memory of its own, 0.3 ms to build. A fragment is kept only where a blade of
  dry grass (a 2 x 5 cm cell in the frame of a slow lean field, tapering, bent over with height,
  swayed by `wind_factor`, a 5 cm thatch mat at the roots, 0.55 m at the tallest) or the brush
  understory (the painted crowns grown into low mounds of 3 cm leaves, 0.42 m; the lone sage
  dots into paler round bushes) reaches that high. The first version built a per-tile ArrayMesh
  with 16 copies of the vertices and a LOD ladder of index prefixes: its `add_surface_from_arrays`
  alone was 3-7 ms, over the step budget; the MultiMesh costs nothing.
- **One splat, three readers.** The splat's maths moved to `shaders/hill_splat.gdshaderinc`
  (uniform defaults, noise, `hill_stand_threshold/stand/sage/brush/bare/rocky/crowns`), included
  by `terrain.gdshader` and the shells; `HillPlanting` mirrors it (the smoke test reads the include
  for `MIRRORED` and the new `MIRRORED_CONSTS`). The shells work the slow terms out per vertex
  (~3 m apart; those noises vary over 25 m and more) and the edge-raggers per fragment.
- **Keep-out.** `_mark_shell_ground` (a build step before the terrain mesh, a few obstacles a
  call) writes a signed distance to the nearest hill road + shoulder, mansion pad or landmark into
  the terrain's COLOR.b (0.5 at the edge, so it interpolates straight); the ridge sign is exempt
  (its 400 m radius is reserved lots, the letters stand on legs). Replica chunks build no shells.
- **LOD.** Layers are stored bit-reversed, so any power-of-two prefix is spread evenly up the
  canopy; `visible_instance_count` is 16 / 8 / 4 / 0 with the camera 40 / 65 / 90 m from the tile's
  box (checked five times a second per tile), and the shader thins them from 35 to 75 m. Past a
  pixel a blade or leaf only aliases (moire in the first renders, "sequins" on the brush), so there
  a layer is kept by its average cover, dithered per pixel and coloured by the layer's height - TAA
  resolves it on the Mac; opengl3 stills show it as grain.
- **Shrub crowns in the paint.** `hill_crowns()`: a dome per jittered 2.6 m cell, big and small,
  never reaching past the four cells searched (so none is cut off straight). A stand's edge runs
  round them (`crown_edge` 0.06) and inside they are shaded as domes (`crown_relief`); they fade
  out from a 0.06 m to a 0.2 m pixel footprint (full to ~40 m, gone by ~120 m at 720 rows;
  resolved further out they read as bubble wrap from across a canyon); off with `ground_detail`. The lone sage and
  buckwheat dots are painted `sage_color` (paler grey-green): in chaparral's colour they were
  dark polka dots across the straw.
- **A hitch removed.** `_scatter_hills` asked `MacroMap.height_at()` about a thousand times in
  one step (20-40 us each in the eroded hills): 57 ms mean, 75 ms worst per hill chunk on this box.
  It now reads the tile's own grid (`_terrain_height`, also the surface drawn and collided with)
  and runs 60 tries a step with its rng kept between calls (same stream, same rolls): 3.6 calls of
  3.6 ms. The props-on-the-ground check now measures against the tile grid.
- **Quality.** `CityChunk.shells_enabled` is false on the web and below MEDIUM (set by `Quality`,
  which also hides built shells via group `hill_shells`).

Numbers (opengl3 / llvmpipe, 1280x720, `--quality=0`, still_shot GEO of the exact frame; before =
mountains 7a84542 in a separate worktree):

| View | Before tris / draws | After tris / draws | Change |
|---|---|---|---|
| ridge, EYE -400,3,-1250 (AGL) | 1,213,599 / 469 | 1,338,332 / 465 | +124.7k (+10.3 %) |
| slope to the city, EYE -150,2.5,-1100 | 3,026,761 / 927 | 3,232,947 / 927 | +206.2k (+6.8 %) |
| grass between stands, EYE 608,1.7,-1018 | 1,839,034 / 861 | 2,047,108 / 869 | +208.1k (+11.3 %) |
| open grass, EYE 780,1.7,-1402 | 2,675,326 / 1,134 | 2,854,903 / 1,141 | +179.6k (+6.7 %) |
| high flank, EYE -352,1.7,-1369 | 3,181,416 / 1,213 | 3,264,902 / 1,213 | +83.5k (+2.6 %) |
| hills bookmark (--spawn=300,-650,0,-6,260) | 1,962,821 / 1,132 | 1,980,267 / 1,132 | +17.4k (+0.9 %) |

A tile is 2,048 triangles (4,608 where a hill road crosses it), so 16 layers are 33k / 74k.
`tools/geo_count.gd` at the hills bookmark (its own frame, 90 frames in): 5,667,443 -> 5,690,211
triangles (+0.4 %), 4,129 draws both.
GPU (Forward+ under lavapipe, hill_ground_shot.gd `PROFILE=4`, a ground view the shells fill
most of, measured before the shells took the painted texture tone - two fetches a visible pixel
more in the colour pass): frame 4,085 -> 4,198 ms (+2.8 %): the depth pre-pass +46 %, the opaque
pass -24 % (the shells hide the far heavier terrain shader behind them). Read the shares, not the
milliseconds.

Build steps (`tools/hill_step_bench/`, headless, 36 hill chunks of the front range, this contended
box): `_mark_shell_ground` 0.40 ms mean (worst 0.76), `_build_hill_shells` 0.34 ms (0.30 worst
after the first chunk, which loads the shader: 6.2 ms), `_scatter_hills` 57 ms -> 3.6 ms a call.
Pre-existing and untouched: `_build_terrain` ~5 ms mean (9 worst), `_build_mansions`' first
call ~400 ms (loads the Building scene).

Tools: `tools/glshot/hill_ground_shot.tscn` builds the real hill chunks round an EYE with the city's
WorldEnvironment and sun, a minute a shot instead of eight (`AB=1` saves each frame again without
the shells, `DEBUG_SEQ=1,3`, `SHELL_DEBUG`, `PROFILE=n` under `--gpu-profile`); its sky and
exposure are not DayNight's, so judge colour in the city. Screens (agent scratch `screens/`):
`hillground_{before,after,ab}_{ridge,slope,stands,grass,flank}.jpg`, `hillground_*_hills.jpg`. `tools/hill_step_bench/hill_step_bench.tscn` times every hill build
step.

Traps: a MultiMesh without `use_colors` hands the Compatibility shader a COLOR that is not the
vertex colour (the keep-out read "never grow" and nothing drew); `return` is not allowed in
`fragment()`. **The painted straw is not `straw_color`**: terrain.gdshader multiplies it by its
grass texture's and aerial mottle's light and dark (`gl`), which average well over one, so shells
coloured from `straw_color` came out at a third of the ground's brightness (sRGB 97 against 192 in
the city) - it looked like a lighting bug and was chased through normals, shadows, the Compatibility
renderer's additive shadow pass and every shader output before a probe mode (debug_mode 3: the
kept fragments in the painted colour on the slope normal) matched the ground exactly once it had
`gl`. The shells now sample the same two textures. Also: the harness first lit everything with
the scene's own level sun (the streamer turns it in `_ready`), which grazes every up-facing
surface; it now applies `sun_rotation_degrees`.

Still open / needs the Mac (Forward+ with TAA at 60 fps is where this is meant to be judged):
- The grass is calibrated to the painted straw on opengl3 (a little darker, as grass with depth
  is); check `grass_gain` / `root_shadow` against a Mac screenshot. The dither grain should
  resolve under TAA; if it shimmers, raise `blade_cell` or pull `fade_end` in.
- The brush understory reads as dark textured cushions following the stand shapes; the 3D shrubs
  (6.2 m grid) are still too sparse to make a continuous canopy at ground level, and more of them
  cost 2,200 triangles each. A cheaper near shrub (or impostor) is the next lever.
- The crowns fade out by ~120 m (720 rows, twice that at 1440p) because further out they read as
  bubble wrap (a first fade at a 0.5 m footprint left them on every hill in view); past that the stands are the old smooth paint with a scalloped edge, and from
  across a canyon they can still read as camouflage. The far answer is real geometry (a cheap
  near-far shrub, roadmap #6) rather than more paint.

## 9aj. The crowd up close, 2026-09-27 (agent branch `wt/crowd-detail`; roadmap #38)

The ask, after 9ah: the next real gain is close-up quality - faces (skin detail and warmth, eyes
that catch light, brows, stubble variety, less generic proportions) and garments (fabric detail,
folds, jeans that are not all bright blue) - with performance flat.

- **Faces.** `build_character.py` rolls MPFB's own face targets per person (`FACE_PAIRS`: nose,
  jaw and chin, cheeks, eye size, lids and bags, mouth and lips, ears, brows, forehead;
  `face_var` 0.35, 0.3 for most women; `face_seed`). The first roll (0.55, with eye spacing, head
  height and brow angle in the pool) made caricatures and was cut back. Men carry **stubble or a
  beard** painted into the atlas over a beard zone found on the head in the eyes' frame, scaled
  by the eye-to-chin distance, with MPFB's `lips` group kept clear and used to find where the face
  targets moved the mouth (`stubble`, `beard`, `beard_rgb`): stubble is a cool shadow over the
  skin (the first version laid the beard's brown on and read as orange smudges); a beard is
  opaque hair colour with soft strand shading (a sharp grain sparkled like frost). Eyes carry a
  flag in the vertex colour (B + A full) and get a glossy cornea (`eye_roughness` 0.06, specular
  0.55); the eye atlas scale went 0.5 -> 0.75. Skin: Forward+ subsurface scattering
  (`skin_sss`, `sss_mode_skin`; the Compatibility renderer prints one warning per compile and
  ignores it, as it already did for the hero), a softly warm `skin_backlight` (at 1.0/0.42/0.28 it
  turned every face orange on the opengl3 path - measured by A/B, `MAT_PARAM=` on
  crowd_lineup.gd), and the tiling pore tile of the detail texture. The skin relief from the
  photo (a band-pass of its luminance turned into a normal) is on the head only and gentler
  (`skin_normal_strength` 1.2 -> 0.5): on the body it was JPEG noise amplified into lumpy skin, and
  at 1.2 the faces read pock-marked. **Brows** were a solid near-black bar on everyone: their
  texels are a third as bright as the hair and only the dense core passes the cards' alpha cut.
  `crowd_atlas.py` now shades each brow round the hair colour from its own mean (`BROW_DARKEN`
  0.8: a redhead's brows are auburn, a grey head's grey) and lets the fringe through the cut
  (`BROW_ALPHA_GAIN` 1.7) coloured toward the body's median skin (below `BROW_SOLID`), which is
  the blend the card would have drawn, baked.
- **Garments.** Folds from `tools/hero/folds.py` (the hero's fold field, reused as it is):
  `build_character.py` dumps every garment triangle's atlas UVs, rest-pose corners and normals
  plus the landmarks the field needs (bones, the top's hem, whether sleeves pass the elbow and
  trousers the knee), `crowd_atlas.py` rasterises them at the normal atlas' size, evaluates the
  field (elbow rings and cuff stacking, hem blousing, chest drape, knee and ankle folds, hip
  creases, seat folds), adds the slopes to the garments' own normal maps and darkens the valleys
  a little in the colour. `fold_gain` per garment (0.75 on the jersey tees). Trousers are dyed
  per person, keeping the photo's fades as shading (`dye.bottom`, `dye_contrast`): dark indigo
  (a, j), black (d), khaki (f), grey (h), charcoal (l); e and k keep the washed photo. The body
  mesh carries **UV2 in metres** (per atlas rect: its UV times sqrt(surface area / UV area),
  randomly offset), on which character.gdshader tiles `assets/textures/crowd/crowd_detail.png`
  (`tools/crowd/make_detail.py`, procedural: skin, jersey knit, denim twill with slub streaks,
  plain weave; RG normal, B roughness, A tone) with one `textureGrad` fetch. The fabric rides in
  the region colour's level (R or G: 1.0 jersey, 0.85 denim, 0.70 woven; "keep" 0.45 lower in R),
  with per-fabric roughness and rim sheen. Honest note: at 2-4 m the tiling detail is nearly
  invisible (A/B at 1.1 m: `detail_strength=0` vs 1 differ by under a grey level); what reads at
  street distance is the folds, the trouser colours and the fabric roughness / sheen.
  **Skin through the shirt.** The covered skin the builder keeps (the ring inside every garment
  edge, and the chest under a V-neck or an open collar) sat about 5 mm under the cloth, and a
  walk's chest turn pushed a skin triangle out through the shirt front as a pale sliver on crowd_c
  and crowd_j (the "button" noted in 9ah was this). `build_character.py` now tucks the skin under
  the garments up to `cover_tuck` (6 mm; 14 mm on crowd_j's open-collar denim shirt) along its
  normals, as a SMOOTH field (the covered flag averaged over four neighbour passes, so it ramps
  in across the garment edge). The first version moved the covered vertices as a step, and it
  cost: every neckline, cuff and hem became a 6 mm crease, the importer's generated LODs kept far
  more triangles to hold it, and the downtown pedestrians went 355,311 -> 519,163 triangles
  (+46 %; frame 6.83 -> 7.00 M) with the base meshes the same size. Smoothed: 355,294.
  crowd_c's sliver is gone; crowd_j keeps a smaller one (72 bright pixels at 1.5 m against 173
  untucked): that skin is visible through his open collar in the rest pose, so it is not
  covered and cannot be tucked without denting the collar. A known flaw.
- **Cost.** Geometry and draws flat. `tools/geo_count.gd` at the downtown bookmark (800x600):
  4,934,170 -> 4,934,065 triangles, 5,333 draws and 21,546 objects both. `still_shot.gd SPLIT=1`
  downtown_noon: pedestrians 354,583 (78,318 shadow) -> 355,294 (78,386) triangles, 343 draws
  both; frame 6,831,626 -> 6,832,349. The four street views on Flower (eye level, 1280x720):
  4.891 / 5.920 / 6.809 / 6.205 M -> 4.897 / 5.920 / 6.816 / 6.205 M, draws identical. Textures:
  +1.4 MB (the 1024 px detail texture, VRAM-compressed), -2 MB (the two crops without a hair mesh
  get a 512 px hair atlas); body atlases unchanged in size. Loading (`people_load_bench.gd`, the
  people's share of the loading screen): rigs 12 in 917-975 ms either side; camp figures 60 swing 568-853 ms run to run on this loaded box, so the totals (before 1,602 and 1,606 ms, after 1,485, 1,685 and 1,804 ms) show no change beyond that noise. Smoke test 506 checks.
- **Judged** (opengl3 lineups at 1.6-3 m and the street; `tools/glshot/crowd_lineup.gd`, which now
  takes `LIGHT=street` and `MAT_PARAM=` A/Bs). What reads at 2-4 m: the beards and stubble, the
  brows, the dark / khaki / grey trousers, the folds at elbows, knees, ankles and cuffs, and the
  per-fabric roughness and sheen; the faces differ from each other more. What does not: the
  tiling pores and weave (under a grey level at 1.1 m in the A/B - the atlas' own photo detail is
  what is visible), and the faces are still MakeHuman-grade (soft painted skin, generic
  expressions, thin hair cards) - better, not PS5. Forward+ subsurface and the wet eyes are
  unverified here (Compatibility ignores SSS): NEEDS MAC CHECK.
- **How to rebuild.** `tools/crowd/build.sh [names]` as before (all twelve ~25 min on a loaded
  box); `FROM=crowd_atlas tools/crowd/build.sh` redoes only the atlases and the export (~15 min
  for twelve) after a change to crowd_atlas.py or the config's look keys; `python3
  tools/crowd/make_detail.py` rewrites the detail texture (then import, and keep its `.import`
  at `compress/normal_map=2` - it is not a two-channel normal map). The shared build dir can be
  pointed elsewhere with `HERO_BUILD`.
- **Traps.** (1) Removing Blender attributes from a list of references removes the wrong ones
  after the first (the list goes stale): look each up by name. (2) A full disk mid-build
  (other agents' renders share it) killed a background render job silently; the glbs and atlases
  were checked afterwards (header length vs file size, every image decodes). (3) The atlas plan
  (`WORK/<name>/atlas.json`) is written by the Blender step; until `_LOOK` the atlas step read
  the look keys only from there, so config changes between Blender runs silently did nothing
  (two rounds of `skin_normal_strength` tuning and a softer grey for crowd_g never landed; the lumpy skin went away only when
  the relief left the body). (4) A step in a crowd body's surface is a triangle cost you cannot
  see in the base mesh: the glb had the same triangle count, the importer's LODs did not (the
  tuck above). Measure `SPLIT=1`'s Pedestrian line after any reshaping. (5) One headless check
  crashed (signal 11 in the street-life checks, "caller thread can't call propagate_notification"
  on /root) on a tree that passed when re-run unchanged (and again after the final rebuild):
  an engine flake under load, not the crowd.
- **Next.** (1) Our own garments (the hero's tracksuit route: modelled, UV'd, analytic folds)
  for the three or four most common outfits - the MakeHuman clothes' soft photographed textures
  are now the weakest part up close. (2) Painted brows and lip colour into the skin atlas instead
  of cards (needs the brow cards projected onto the head's UVs in the Blender step). (3) A
  shared face-detail normal (nasolabial folds, eyelid creases, age lines by the character's age)
  on the head rect, which the photo band-pass cannot give without its noise. (4) Check the
  Forward+ SSS and the eye clearcoat on the Mac; if the skin reads waxy, `CROWD_SKIN_SSS` 0.35 is
  the knob.

## 9al. Motion blur and depth of field, 2026-09-27 (agent branch `wt/post-fx`; roadmap #12)

The brief: restrained per-pixel motion blur and depth of field while aiming and in the weapon
wheel, Forward+ only. Both live in `CameraPost` (`scripts/player/camera_post.gd`), the new
`Post` node under the player's CameraRig in `player.tscn`, so the city and the test room get it;
CLAUDE.md's "Motion blur and depth of field" note is the reference.

### What it does

- **Motion blur**: `MotionBlurEffect` (`scripts/util/motion_blur_effect.gd`), a CompositorEffect
  on the player camera's `compositor`, six compute kernels in `shaders/motion_blur.glsl` (one
  RDShaderFile, `#[versions]`): prepare (velocity -> blur radius in pixels, linear depth), tile
  max in x then y (tile = the longest radius), neighbour max (3 x 3, diagonals only when they
  point in), gather (McGuire 2012 with Guertin 2014's taps alternating between the
  neighbourhood's velocity and the pixel's own, interleaved-gradient jitter stepped per frame for
  TAA) into a result image, and resolve (the result back into the frame only where a tile
  blurred - the first version copied the whole frame every frame, a third of its idle cost). POST_TRANSPARENT is the last callback Godot has, so it runs on the HDR frame at the
  internal resolution before TAA / FSR 2.2 and the tonemapper - the right order: TAA averages the
  jitter, and a streaked highlight goes through AgX as light.
- **Frame-rate independent**: length = one frame's displacement x `shutter / reference_fps /
  frame_seconds`, frame_seconds the UNSCALED process delta (so the wheel's 0.25 time scale gives a
  quarter of the blur, as a high-speed camera would). Lengths are in pixels of a 1080-line frame,
  scaled to the internal resolution, so every quality level and the Mac's FSR-upscaled HIGH blur
  alike. `velocity_threshold_px` (3) is subtracted first as a soft knee: walking stays sharp.
- **Depth of field**: Godot's far blur on the camera's CameraAttributesPractical, three states
  blended on the real clock - ambient (the old CameraRig focus, moved over unchanged: 260 m +
  14 m per metre of altitude, amount 0.04, HIGH only), aim (hold alt_fire: blur from 35 % past
  the locked target or the crosshair hit, at least 4 m, amount 0.06; HIGH and MEDIUM) and the
  weapon wheel (from 8 m, amount 0.16; HIGH and MEDIUM). Compatibility has no depth of field.
- **Quality** hands `CameraPost.apply_quality(level)` the level instead of setting the DOF flag
  itself: motion blur and the aim / wheel blur on at HIGH and MEDIUM, off at LOW and LOWEST.

### Traps (each cost time here)

1. **FSR 2.2 leaves most of the velocity buffer empty.** With `SCALING_3D_MODE_FSR2` the engine
   renders motion vectors only for MOVING objects and clears everything else to (-1, -1) - FSR
   derives the camera's motion itself. The pixel budget turns FSR on at HIGH on a Retina Mac, so
   that is the Mac's normal path. The sky writes no velocity in either mode. Both are rebuilt in
   the prepare kernel from depth and the camera's reprojection, which the effect keeps itself
   (last frame's `get_cam_transform()` / `get_cam_projection()`).
2. **`get_cam_projection()` is the corrected projection**: y flipped, reverse-Z remapped to 0..1,
   and the TAA jitter in its z column (zeroed before use, or a still camera reprojects to a
   sub-pixel wobble). Its z row gives linear depth directly: `d = b / L - a`.
3. **A shot tool must capture the frame drawn from the last move.** `await process_frame` after
   the last move, then `frame_post_draw`, captures a frame drawn after the camera stopped: zero
   velocity, and the effect looks like it does nothing (it cost two rounds of renders). And the
   engine compiles its motion-vector pipelines in the background and draws NO velocity until
   they are ready, so warm up (the tools do 30 frames).
4. An origin re-centre or a respawn moves the camera a kilometre in a frame; every moving
   object's velocity is garbage in that frame too, so the whole frame is skipped (`effect.cut`,
   set by CameraPost when `WorldState.world_offset` changes, and `max_camera_jump`).

### How it was verified (Forward+ under lavapipe; the city does not fit, so small scenes)

- `tools/glshot/motion_blur_shot.gd`: a code-built street (checker road, rows of columns, blocks,
  sky, a capsule "player" with a gun riding with the camera). Before/after at 45 m/s, 1/60 s
  frames, mean |RGB diff| out of 765: forward flight 15.5 (no AA), 12.2 (TAA), 15.2 (FSR 2.2 at
  0.6); a 5 rad/s camera orbit 13.2 (TAA); nothing moving 0.00 (the effect leaves a still frame
  bit-identical). The near ground and columns streak radially, the far street, the player and
  the gun stay sharp, the capsule does not smear onto the road behind it. `DEBUG=1` shows the
  radial field on the TAA path and a uniform sideways field (sky included) on the FSR path - the
  camera part rebuilt from depth where the engine wrote (-1, -1). A car-sized box crossing at
  45 m/s 20 m away gets its ~3 px of edge blur (small by design: half a frame's travel, less
  the threshold).
- `tools/glshot/post_room_shot.gd`: the test room with the real player, camera rig, CameraPost
  and HUD (effect built and drawing, 38/38 frames): a 280 deg/s whip blurs the world and not the
  hero; aim starts the far blur at 36 m with the crosshair's hit at 27 m; the wheel blurs from 8 m under its
  glass. The same script under `--rendering-driver opengl3`: no effect built, DOF fields set,
  no errors. Headless (smoke test): no compositor, the effect constructs disabled, the DOF moves
  between its states and Quality turns it off.
- Screenshots: `postfx_street_*`, `postfx_room_*`, `postfx_debug_*`, `postfx_moving_box_crop`.

### Cost

`--gpu-profile` on the street at 1920x1080 under lavapipe (read the ratios, not the ms - the box
was shared, and the same frame's TAA pass measured 97 to 152 ms between runs). The effect is the
"Process Post Transparent Compositor Effects" segment, against Godot's own TAA pass in the same
frame:

| Case | effect / TAA |
|---|---|
| Forward flight, nearly every pixel blurred, 12 taps | 110 / 97-107 ms, then 158 / 152 ms (1.0-1.1x) |
| The same, 8 taps | 106 / 115 ms (0.9x) |
| Nothing moving, first version (full-frame copy) | 35 / 103 ms (0.34x) |
| Nothing moving, with the resolve pass | 38 / 147 ms (0.26x) |

So at worst it costs what TAA costs, and on a still frame a quarter of that; TAA at that size is
a fraction of a millisecond on a real GPU. The resolve version renders bit-identical frames to
the copying one. Knobs that cut it further: `samples` (8 is fine under TAA) and
`velocity_threshold_px` (more tiles take the early out).

### Knobs (CameraPost exports)

Motion blur: `motion_blur_enabled`, `motion_blur_strength` (1), `shutter` (0.5 = 180 degrees),
`reference_fps` (60), `max_blur_px` (40, 1080-line pixels), `velocity_threshold_px` (3),
`samples` (12), `depth_tolerance` (0.06 of the distance), `max_camera_jump` (30 m). DOF:
`dof_ground_distance` / `dof_altitude_gain` / `dof_lerp_speed` / `dof_amount` (ambient),
`aim_dof_*` (enabled, amount 0.06, margin 0.35 / 4 m, transition 1.0 / 10 m, no-hit focus 150 m,
focus speed 8), `wheel_dof_*` (enabled, 8 m, 14 m, 0.16), `aim_ease_seconds` 0.25,
`wheel_ease_seconds` 0.15. Debug: `fixed_frame_seconds`. Switch: `-- --motionblur=0|1|<scale>`.

### Not done / next

- Look at it on the Mac (Forward+, FSR at HIGH): a boost down a street, a fast flight low over
  the city, a car at speed, a mouse flick, then aim and the wheel. If it reads too strong, lower
  `motion_blur_strength` or `shutter`; too weak at speed, lower `velocity_threshold_px`. The
  explosion camera shake is blurred too (it is camera motion); if that reads as smear rather
  than concussion, cap the shake's share (not done).
- Physics interpolation is off and the player moves on physics ticks: on a machine rendering
  faster than 60 Hz uncapped (Quality caps desktop at 60) frames with no tick would carry no
  blur. Not an issue at the cap.
- Transparent things (particles, glass) write no velocity: they take the blur of what is behind
  them. The web and the opengl3 stills show none of this.

## 9am. Lots filled, not paved: podiums, forecourts, car parks, 2026-09-27 (agent branch `wt/lot-fill`)

The brief: downtown towers stood on a sea of bare beige paving - from the street a vast empty
plaza, from the air towers scattered on tan concrete. Measured first (`tools/lot_coverage.gd`,
headless, rasterises every BUILDINGS block's inner rect on a 1 m grid; `FILL=0` is the before):

| Block ground (inside the pavement ring) | bare before | bare after | built before -> after | notes |
|---|---|---|---|---|
| Financial core (65 blocks) | 44.0 % | 2.2 % | 46.9 -> 60.1 % | forecourt 25.6 %, car parks 3.0 % |
| Rest of downtown (147) | 30.8 % | 2.7 % | 54.9 -> 49.3 % | forecourt 25.1 %, car parks 8.5 % |
| Midtown (324, west of the 110) | 53.6 % | 5.4 % | 40.7 -> 41.4 % | forecourt 38.8 %, car parks 8.8 % |

Where the bare ground came from: TOWER and CROWN shapes covered 23 % and 30 % of their lots
(`minf(lot) * 0.45-0.75` square in the middle; 3 of the 8 core shapes, and midtown's TOWER at
26 %), SLAB 73-76 %; the gaps between lots (a lot is its grid cell less a 2-5 m gap downtown,
3-8 m midtown: 11 % of the core, 15 % of the rest, 34 % of midtown); and the lots a landmark's
square pushed out of the grid (19 % of the core: a downtown tower's radius square drops every
lot it touches and only its footprint was built). Now (`LotFill`, `scripts/world/lot_fill.gd`):

- **Podiums** (`Building._add_podium()`): a tower whose ground parts cover under 55 % of a lot
  (16 m+ short side, 28 m+ tall) gets a base filling 88-98 % of it, a parking deck or 1-3
  retail storeys, the tower lifted onto it and slid off centre. TOWER lots now 82 % covered in
  the core (70 % in midtown), CROWN 82 %; 79 podiums in the core, 401 in midtown. Hashes of the
  seed only, after the layout's rolls: nothing of the building's colours or any other building
  moves, and the far box follows through `parts`. The parking deck is all shader
  (`building.gdshader`, CUSTOM3.z): spandrels, columns on the bay lines, the deck traced behind
  the opening (stall lines and nose-in cars on the floor, lamps under the next deck that light
  up at night, the far side open to the day), a drive-in bay on the street face
  (`garage_entry`) and a roof deck with painted stalls.
- **Forecourts**: each lot's ground out to its grid cell (`lot.cell`) in one of four paving looks
  a block; raised planters, benches, a short run of bollards, and in plaza-sized pieces a
  reflecting pool or a bronze on a cross of walks with lawns in the quarters. A retail podium's
  roof is the tower's garden (lawns, planters, a turquoise pool).
- **Surface car parks**: `CityPlan.lots()` marks some lots `"parking"` (DISTRICTS
  `surface_lots` 13 % downtown, 4 % in the core, 10 % midtown; only under 55 m of massing):
  asphalt, stall rows and aisles, ArenaGrounds' static cars, a pay booth, light poles, a low
  wall / hedge / chain-link on the street sides. A parking podium gets its drive-in (asphalt to
  the kerb) and cars and light poles on its roof deck.
- **What a landmark's square left** (`CityPlan.dropped_cells()`, the same walk as `lots()`):
  forecourt round the landmark (a downtown tower's own footprint kept 4 m clear) or a car park.
- **The code car** (`ArenaGrounds.car_mesh()`, also the arena district's and the airport's
  parked cars) rebuilt at ~400 triangles with a two-box shadow twin: the old painted brick read
  as toys once a car park stood on half the blocks.

### Frame cost

opengl3 at 1280x720, `--quality=0`, noon, clear (`still_shot.gd`; before = this branch's base,
f17726e). The draws that are left are content where there was none (the fill's own ground is
ONE mesh and material a chunk, `shaders/lot_ground.gdshader`); the triangles are the retail
podiums' facades and kit, the parked cars (~400 each, box shadows to 70 m), the planters'
bushes and trees (one species a chunk, `MAX_TREES` 10), and the lawns.

| Bookmark | triangles before -> after | draws before -> after |
|---|---|---|
| Flower at Olympic, `--spawn=2359.4,880,0,12,2` | 6,083,678 -> 6,772,741 (+11.3 %) | 3,382 -> 3,487 (+3.1 %) |
| South-west aerial, `--spawn=1450,2150,-38,4,140` | 5,072,188 -> 5,414,891 (+6.8 %) | 3,205 -> 3,270 (+2.0 %) |
| Top-down, `EYE=2300,420,800,0,-89.9` | 2,775,281 -> 3,111,162 (+12.1 %) | 2,464 -> 2,645 (+7.3 %) |

The first cut was +385 draws / +1.7 M triangles on the street bookmark; SPLIT (still_shot.gd now
has a LotFill line) and a census of the full chunks' nodes found the causes, in the traps
below. The podiums also occlude: the street bookmark's Landmark category fell from 234 to 127
draws.

### Traps

- A planter built as a solid kerb box hides a soil box placed below its top: the planted top has
  to stand a hair proud of the kerb (it did not, and every planter was a white slab with weeds).
- `CityChunk._add_bush()` rolls one of eight species; a batch key is a draw and its shadow twin
  another, so the planters alone put up to sixteen new draws on a chunk. Planting code that is
  not the street's own should pick ONE species a chunk.
- A bollard is a 72-triangle cylinder with no LODs, counted and drawn per instance in every
  cascade: a frontage of them on every lot was ~2,000 in one street view (+0.5 M triangles).
- On a LOD chunk every ground slab is gridded at 8 m whatever it is, and a slab under 6 m
  becomes a box of its own material (a draw). The far tiers take only what changes the read
  from there: asphalt and lawns.
- The podium's rolls must not come from `Building._rng`: `plan_only()` feeds the colours from
  it right after the layout, so the podium is decided from `hash([seed, tag])` in between.
- A `SurfaceTool` handed an indexed mesh (`append_from()` of a BoxMesh's arrays) after unindexed
  ones keeps only the indexed triangles: the merged fill mesh lost every grid and the car parks
  drew as the pavement under them. Append everything unindexed.
- `CityChunk._add_slab()` treats anything 0.5 m tall or less and 6 m long as ground and lays a
  relief grid NODE for it: a pool's 0.45 m kerbs were four draws each. Solid furniture goes into
  the merged boxes directly (`LotFill._solid()`).
- The Poly Haven asphalt, grass and paving textures are world-mapped in `lot_ground.gdshader`
  from the chunk-space position (true world inside a chunk), never the world position, or they
  swim on every origin re-centre.

### Not done / next

- Look at it on the Mac (Forward+): the garage interior's exposure by day and its lamps at
  night, the chain-link's dither under TAA, the plaza lawns' colour.
- Retail podium roofs carry no mechanical plant now; a few packaged units among the planters
  would be truer. Beach town (67 % bare) and campus blocks were left as they were (since filled:
  9az).
- The code car is still a code car up close; a real ~2k-triangle parked-car body with LODs
  would be the next step for car parks seen from the pavement.

## 9an. Car damage, 2026-09-27 (agent branch `wt/car-damage`; roadmap #10)

Before this a car took no damage at all: rounds and rockets only knocked it out of the traffic.
Now every car (traffic, parked, police, the one you drive) has a damage model; the flyable jets
opt out (`Aircraft.can_take_damage()`), the scripted air traffic keeps its own.
- **One entry point, `Vehicle.take_hit(shape, damage, dir, at, kind)`**: `HIT_BULLET` from
  `AssaultRifle.fire_ray`, `HIT_PELLET` from `Shotgun.fire_pellet` (per pellet; the uniforms are
  pushed once a frame), police rounds under `Police.innocent`, `HIT_BLAST` from
  `Explosion.blast()` (once per car - the query returns a result per collision shape - with
  the falloff measured to the body rather than the origin), `HIT_CRASH` from the crash watch.
- **Crashes** are a velocity change in one physics step (`Vehicle._crash_watch()`, one
  subtraction a tick in the car's existing script; `crash_min_dv` 8 m/s sideways,
  `landing_min_dv` 20 m/s straight up, because cars are flown and dropped all the time) that
  a ray finds something at, the way the car was going. Without the ray every script that sets
  a car's velocity is a crash: the smoke test zeroes a car's flight speed and it blew up on the
  quick fuse (two checks failed that way). `hold_crash_watch()` before a deliberate change (the
  jump does it). A crash never takes the quick fuse.
- **Where a round lands** is traced onto the real body mesh (`TriangleMesh`, built once per mesh,
  face index -> slot by the surfaces' face counts): paint gets a hole, the glass slot a crack or a
  pane, a lamp slot breaks that lamp. The collision boxes are centimetres off the skin, and a hole
  3D-tested in the shader against a point 3 cm off the surface never shows.
- **Look**: `car_paint.gdshader` is now `car_paint.gdshaderinc`; `car_paint_damage.gdshader` is
  the same file with `CAR_DAMAGE` defined, so an undamaged car compiles exactly the old shader.
  A car's paint material is copied onto it on the first hit (every uniform carried over) and set
  on its body meshes and shadow twins. Holes (40, recycled): black hole, torn bright steel ring,
  primer and metal flecks where the paint chipped, the metal pushed in. Dents (8): vertex
  displacement with a crumple noise and a normal rebuilt from the offset. Scorch (4). Burn: bands
  out from the engine bay - cooked paint, soot, temper colours, rust / ash bare steel - with the
  sills kept cooler. Glass slot: `car_glass_damage.gdshader`; the panes are the glass surface's
  connected pieces (union-find on welded positions, one pass per mesh, cached; the windscreen is
  the biggest forward-facing pane ahead of the middle - raked screens face mostly up - and lamp
  lenses are the small pieces at the ends). Tempered panes craze (Voronoi cubes, milky past a few
  pixels a cube) and fall out as a burst of glinting cubes, the windscreen collects webs, lamp
  lenses go with their lamp. An empty frame draws the cabin traced in body space: dash, two front
  seats, the rear bench, headrests, the headliner, the far window's daylight (or its pillar),
  emitted at `cabin_light` x `sky_tint`. Lamps: `car_lamp_damage.gdshader`; the night glow is
  `PropFactory.vehicle_lights(..., broken)`, one cached mesh per combination.
- **Fire**: smoke past `smoke_at` (grey to black), fire past `fire_at` for `burn_seconds`
  (6-9 s; `quick_fuse` 0.9-1.7 s after a hit of `quick_fuse_damage`), then `explode()`: the
  driver is put out, `Explosion.blast(..., exclude = the car)` under `Police.innocent =
  blame_police` (the last hit's), a police car reported as `police_car` when it is the player's,
  the wreck tossed up to `toss_speed` (not on top of a rocket's throw). An OmniLight flickers
  under it on desktop (a random walk plus a shimmer, `fire_light_energy`), the synthesised
  `fire_loop` plays (no CC0 take yet).
- **The fire's look** (second pass, the lead: the first flames read as cartoon candle tongues):
  the explosion's `fire_puff.gdshader` (density = heat) on the car's own material
  (`CarDamage.fire_material()`: `core_heat` 1.4, `soft_distance` 0.35 - at the blast's 2.6 m
  the bonnet under the fire faded every flame out), in four systems while it burns: a billowing
  body out of the engine bay (emitted just under the skin, so it rolls out of the shut lines),
  tall-quad tongues off the bonnet's edges and up the windscreen (`EMISSION_SHAPE_DIRECTED_POINTS`
  along `_lick_lines()`), embers, and - after `spread_share` of the burn, or at once on the
  wreck - flames out of the cabin's empty frames, up the windscreen and over the roof
  (`_cabin_lines()`, from the panes; the side glass pops when it spreads), with the cabin glowing
  through the frames. The grey wisps give way at ignition to the fire's own smoke: black, opaque
  where it leaves the flames, its first moments glowing the fire's colour (what shows of the
  column at night), drawn behind the fire. A one-shot whoomph of flame as it catches.
  **Colour, measured**: an unshaded colour chart through car_shot's AgX showed a red-heavy colour
  (green under ~0.35 of red) going salmon pink once brighter than ~1 - the pink the first flames
  had at night - while green at half of red goes cream-yellow bright and deep orange dim. The
  shader multiplies one ramp colour by the density, so a puff's core and edge share that ratio:
  the ramp holds green / red at ~0.5 while it is bright and only drops toward red as it dims.
  Web: the plain puff material, half the particles, no light. Cost (`GEO=1`, one sedan, opengl3):
  whole 40 draws; burning 44 (bay flames, tongues, embers, smoke); a blaze 52 while the popped
  side glass is still in the air (the cabin's flames are one more draw, the cube bursts the
  rest, gone in two seconds); the burning wreck 40. `max_burning` (6) caps the fires at once.
  Stills: `cardmg_fire_*` before/after in the screens folder of the session.
- **Wreck**: burnt = 1, every pane gone, lamps out, trim / tyre / chrome and the far twin's
  parts on shared charred materials, the physics wheels at 0.7 of their radius and the visible
  ones scaled to rims in a charred metal (the car sits down on them), burning for
  `wreck_fire_seconds`, smoking for `wreck_smoke_seconds`, freed by PhysicsBudget after
  `wreck_lifetime` (`register_debris(body, lifetime)`, the `debris_life` meta). A cruiser leaves
  the police (`Police.car_wrecked`); one shot up and pooled is `repair()`ed.
- **Cost**: an undamaged car is unchanged - shared shader, no node, no draw, no script beyond the
  crash watch. A damaged car draws what it drew (the same surfaces, other materials); a burning
  one adds its smoke and flame particles (two draws) and, on desktop, one light. Measured with
  `GEO=1` on car_shot.gd (one sedan, opengl3): whole 40 draws / 173,478 triangles; shot up
  (holes, glass, dents) once its glass cubes have landed 40 / 173,472; burning 42 / 173,626; the
  wreck 37 / 173,216 (lamps, calipers and livery prop gone). While a burst of glass is in the air
  it is one more draw (it casts no shadow: with shadows eight bursts were +32 draws). Caps:
  `max_burning` 6 (past it a car smokes just short of catching), `max_smoking` 10,
  `max_wrecks` 10, `max_glass_bursts` 8. The damage shader loops over its holes per pixel only on
  damaged cars; the flames, glass cubes and smoke are warmed on the loading screen.
- **Tools**: `DAMAGE=holes,glass,dents,smoke,burning,wreck` on `tools/glshot/car_shot.gd` stages
  it through `CarDamage.stage()` (real rounds and crashes through the game's paths), views
  `door`, `glass`, `screen`, `cabin`; `GEO=1` prints the frame's draws. Checks:
  `tests/car_damage_checks.gd`, 30 on a deck 250 m over the street (smoke test 536).
- **Open**: needs a Mac look at the flames and smoke under AgX + TAA (these stills are the
  Compatibility path), and at holes from 5-15 m. `Explosion.blast()` still pushes a car once per
  collision shape (2-3x a rocket's 30 m/s: cars fly very high); left as it was, it is feel. No
  flat tyres from rounds yet, no torn-off panels, no damage on the crowd's cheap parked cars
  (`ArenaGrounds.car_mesh()` statics).

## 9ao. Street-level facades with real depth, 2026-09-27 (agent branch `wt/facade-depth`; roadmap #40)

The brief (owner: "next level ... AAA studio quality"): on a downtown pavement the buildings read
as CG boxes - a shopfront was a painted sign band over dark flat glass between flat grey pier
boxes, a curtain-wall tower a flat grid of painted panes, and the upper floors' window frames
thick pale flat outlines that read as a drawing. CLAUDE.md's "Storefronts and curtain walls"
note is the reference; this is the story and the numbers.

### What it does

- **`ShopfrontKit`** (`scripts/world/shopfront_kit.gd`): the facade kit's code-built half, built
  in GDScript in the kit's own frame and conventions (x along the wall, y up, z out; UV (x, 1+y)
  in metres; UV2.x occlusion) on `PropFactory.kit_material()` - new materials `kit_alu`
  (anodised framing, tinted per instance), `kit_mullion` (the caps, culled per instance) and
  `kit_sign` (a blade sign's lightbox) - into each building's one kit batch. Pieces: `bay` (a
  display window's frame: jambs and head lapping the glass 12 mm, a sloped sill, the transom at
  door-head height, a centre mullion as an optional layout), `door` (frame, threshold, transom;
  a pair of glazed leaves with pull handles OR one leaf with a push bar beside a fixed mullion
  and a sidelight, both in the mesh), `pier` / `pier_metal` (plinth, chamfered shaft, capital
  over the pier box), `fascia` (a trim round the sign board with a drip flashing), `blade` (a
  projecting board on two brackets, the name up both faces), `awning_dome`, `awning_flat` (a
  metal canopy on tie rods), `awning_roller` (cassette, sloped canvas, valance, folding arms),
  `cap_v` / `cap_h` (curtain-wall mullion and transom caps).
- **Anchors in the kit shader.** The three-slice alone cannot keep a door's meeting stiles in
  the middle or its handles at hand height: everything inside the unit opening stretches. UV2.y
  - 1 is now a per-vertex code (x mode + 4 x y mode: 0 slice, 1 moves with the low edge, 2 the
  high edge, 3 stays at the centre; bits 4-7 keep a vertex only where INSTANCE_CUSTOM.g / .r is
  or is not set, so one mesh holds two layouts - one draw for every door on a building, pairs
  and singles alike). The glTF pieces all carry UV2.y = 1 (code 0, checked), so the Blender kit
  is untouched. `ShopfrontKit.place()` is the same placement in GDScript; the smoke test places
  a door with it on a 1.9 x 3.33 m opening and checks the 6 mm meeting gap, the stiles, the
  transom at 2.38 m and the jambs.
- **The pieces stand where the shader paints the same frames.** The door bay (it was a float
  hash of `shop_seed`, which no CPU can reproduce), whether it is a recessed entry, the centre
  mullion, the door layout and the frame finish are all `Building.shop_byte()` rolls (salts
  14-18, `ShopfrontKit.SALT_*`); the transom is at 2.38-2.50 m above the pavement in both; the
  jambs lap the glass where the shader's bars are. The painted frames are hidden inside
  `shop_paint_near` (45 m) and fully back by `shop_paint_far` (70 m); the pieces draw to
  `kit_shopfront_distance` (100 m, raised per building to shop_paint_far + half its footprint
  diagonal + 8 m, because a node's range is measured to its centre). Past 70 m both draw, 7 cm
  apart - under a pixel there. The strip of wall between two display bays, the sill and the
  head are now painted in the shop's frame finish at every range, so the storefront reads as one
  framed glazing system instead of glass holes in a stone wall.
- **Recessed entries** (28 % of door bays) are the shader alone, at every range: the door bay's
  traced recess is 1.1 m deep, with a mosaic floor and border, polished stone returns (three
  stones), a dark soffit with a downlight that comes on with the street lamps, and the door
  painted at the back of the lobby (its own frame, leaves, handles, the hours plate) with the
  shop's room behind it. No geometry, because the wall is a box: nothing can stand inside it.
- **On the glass** (traced pane, so it sits on the inside of the glass with its parallax):
  vinyl lettering (invented capitals built from strokes, white or gold, 39 % of shops), one or
  two posters in one bay (47 %), and on the door an opening-hours plate and an OPEN plate. They
  fade to their average coverage once a stroke is under a pixel. Lit shops show them as
  silhouettes against the room at night.
- **Scissor gates**: a third of the shutters a closed shop pulls at night are a see-through
  lattice (posts, diagonal links, rails) over the dark shop; the bars fade to 42 % cover when
  finer than a pixel.
- **Awnings**: one shape a building (`_kit_awnings`: canvas slope / dome / retractable / flat
  metal canopy, glass and panel blocks lean to the metal canopy), colour and stripes per shop as
  before; glass, panel and plain blocks without a canopy now hang them too (half of them, by
  hash - the `has_awnings` roll is untouched).
- **Blade signs** (24 % of shops, on the pier at one end of the shop, above the sign band): the
  board in one of eight paints, the shop's own name (Building's own name roll, replayed) stacked
  letter by letter when short, running up the board when long, on both faces - flat letters
  merged on the CPU into ONE mesh per letters' material per building (`BladeText*`, culled at
  SIGN_DRAW_DISTANCE). After
  dark it is lit exactly as the shop's fascia is (`shop_letters()`): a lightbox, or dark behind
  lit channel letters, or off with a closed shop.
- **Curtain walls** (`curtain_spandrel` on every CURTAIN-style Building): the far shader's
  layout (vision glass 0.08-0.93 of the floor, building_lod.gdshader's `vis_lo` / `vis_hi`), a
  spandrel panel over each slab edge rolled pale or dark by the far shader's own hash (through
  `lod_seed`, (seed % 997) / 997) with a dimmer reflection, and thin transom lines in the
  building's frame paint. With the kit, `cap_v` on every mullion line (CAP_BAND_ROWS 4 floors an
  instance) and `cap_h` on both transom lines of every floor; the flat `Frames` are dropped on
  those walls. The caps collapse per instance past `kit_mullion_distance` (175 m) in the vertex
  shader, shadow passes too, so a tower's caps are two draws.
- **Window frames** everywhere else (`Frames`): `ShopfrontKit.window_frame()` - bars of a real
  section (`FRAME_WIDTH`: 60 mm punched, 55 slot, 50 ribbon, 45 curtain) worked out per building
  from its pitch and floor height, with the faces that look into the opening, and a sash bar
  (a meeting rail, or a rail and a muntin) in most punched and slot windows; one paint a
  building from `FRAME_PAINTS` (white, cream, black, green and bronze on brick; the anodised
  range on glass). The curtain-wall frames' centre was mirrored wrong (9 cm off the glass) and
  is fixed (`col + 1 - cx`, identical on every other style).
- **The storefront is measured from the part's base.** `building.gdshader` used `v / pt_ground`,
  a ratio of WORLD height: right only for a building standing at y 0. Every building on the
  rolling ground had a squashed shopfront and one 20 m up had no glass at all and its shop names
  at knee height. Now `(v - base) / storefront`; the shop names (`band_y`), StreetWear's
  `_paintable()` and its tag reach follow (StreetWear's float hash emulation of the old door bay
  is gone with it). Downtown sits at y 0.25, so there it moved by about 5 cm.

### Cost

opengl3, `DIFF=1`, before = the parent commit (2fa67b9), after = this branch, same frames:

| Frame | triangles before -> after | draws before -> after |
|---|---|---|
| Downtown bookmark, 960x540 (`--spawn=2359.4,880,0,12,2`) | 5,181,266 -> 5,330,346 (+2.9 %) | 2,733 -> 2,769 (+1.3 %) |
| - its Building category (`SPLIT=1`) | 1,077,558 -> 1,226,078 | 857 -> 893 |
| South-west aerial, 960x540 (`--spawn=1450,2150,-38,4,140`) | 4,666,147 -> 4,673,339 (+0.2 %) | 2,769 -> 2,774 |
| Flower St storefronts, 1280x720 (`EYE=2366,1.7,880,-55,6`) | 3,084,918 -> 3,143,592 (+1.9 %) | 1,340 -> 1,363 |
| The tower from its foot (`EYE=2366,1.7,860,-80,35`, FOV 70) | 1,997,742 -> 2,023,368 (+1.3 %) | 901 -> 927 |
| Brick block on Broadway at 5th (`EYE=2977,1.7,-12,25,5`) | 4,255,296 -> 4,423,902 (+4.0 %) | 2,396 -> 2,443 |
| The same at 21:00 | 4,247,684 -> 4,432,066 (+4.3 %) | 2,384 -> 2,478 |

The new `BSPLIT` kinds at the downtown bookmark: storefront pieces 29,930 triangles, curtain-wall
caps 101,492, awnings 17,052, blade-sign names 4,300 (per-kind draw deltas there do not add up
and are not worth quoting; the Building total is +36). The GEO counter includes the triangles of
the layout an instance does not show (collapsed, never rasterised) and of culled caps.

Generation (headless, 48 buildings of all four finishes, 20-60 m, the same machine, pieces on
against `ShopfrontKit.enabled` off): about +2 ms a building, 12-15 ms -> 14-17 ms. It was +6 ms
before the blade-sign names stopped using `SurfaceTool.append_from()` (a read-back of the text
mesh from the renderer per letter; now CPU arrays taken once per name, `ShopfrontKit.TextAcc`) and
flat, coarse-curved text (12 names in reach at the bookmark were 141,880 triangles; now 10,660).
`STOREFRONT_KIT=0` on `still_shot.gd` is the A/B switch.

### Screenshots

Before / after pairs at eye level (opengl3, the harness): storefronts on Flower St, the tower from
its foot, a brick block in the historic core by day and at 21:00, the storefronts at 21:00, down
Flower St, and from 28 m up at 60-120 m (the handoff); close-ups of a recessed entry, doors and
frames, blade signs, dome and retractable awnings and a shop at night. The lead has them as
`facade_*.jpg`.

### Traps

- A `--script` tool that loads `building.tscn` in `_initialize()` compiles the Building chain
  before the autoloads exist and silently runs without ShopfrontKit: its buildings had no
  storefront pieces and the painted frames showed at any range. `building_shot.gd` now loads
  the scene after three frames; do the same in any new tool.
- `_bar()`'s bevel insets the front face from each end of the bar: a rail's front face near the
  centre line ends 8 mm further from it than the rail does. Measure a member by its sides.
- MultiMesh bounds come from the mesh's box: a sliced piece draws up to its opening past it, so
  every sliced piece carries a `custom_aabb` grown by what it can stretch (a 12 m sign board,
  a 4.4 m pier), and the caps, which are scaled rather than sliced, none.

### Not done / next

- Look at it on the Mac: the metal framing (`kit_alu` metal 0.45) and the vinyl and posters
  under Forward+ light, the blade signs and gates at night, the spandrels in the sun.
- The landmark towers (TowerMesh, `uv_facade`) keep their own curtain walls: no caps, no
  spandrel (they are a replica's facades, tuned there).
- Bulkheads are still painted; a raised panel under the sill would add another depth cue.

## 9ay. Front range roads and estates back: switchbacks, 2026-10-04 (agent branch `wt/switchbacks`, VISUAL_ROADMAP #20)

**What it is.** The cut-bank fix (#17) trimmed the canyon roads that walked straight up the
front range and the estates went with them. They are back as roads that follow the contours:
`HillRoads.add_switchbacks()` (called by `MacroMap.setup()` after the freeway) grows a network of
drives off the kept roads and off each other - legs across the slope at 8.5 %, hairpins of 13 m
turned uphill, a slow wander where the ground is flat, the bed benched into the slope, every step
asked whether its banks meet the ground before it is taken, and the whole drive trimmed by
`_earthwork_ok()` like any other road - plus `Valley Vista Dr` along the inland foot. Estates
(`_place_estates()`) take a 17 m or a compact 13 m pad beside the road or up a 4-26 m driveway
(a long one is a carved `"drive"` road). The chunk builds each with its driveway, a gate between
two piers, a pool beside the house and walls that follow the ground: a garden wall, a retaining
wall holding back a cut, or a tall one dropping down a fill (`CityChunk._build_mansions()`, all
boxes merged into the chunk's box meshes). Hill road strips are now mitred at their joints and
their edges sit on the carved ground. Details in CLAUDE.md (the Map note, after the hill roads).

**Where they are, and where they are not.** The pass (west of the freeway; 15 m clear of its
deck and ramps, pads too), the inland foot and the north flank. NOT the south face toward the
city: it is steeper than 45 degrees nearly everywhere (`tools/hill_road_probe` map: 37-40 % of
the hills over 45, the face a solid band), and on ground steeper than a 1:1 cut no bank ever meets
the ground, so a road there is a cliff whatever the layout. Only terrain changes (gentler
foothills under the face) or retaining-walled roads would put drives there, and the second breaks
#17's rule.

**Numbers** (default seed; `tools/hill_road_probe/hill_road_probe.tscn`, headless, seconds):

| | before (28105b5) | after |
|---|---|---|
| hill roads (kept) | 28 (20) | 38 (30), 9 driveways |
| hairpins | 0 | 7 |
| estates, all / front range | 345 / 31 | 402 / 88 |
| carved cells steeper than 60 degrees | 0.38 % (285 of 75,387) | 0.36 % (325 of 91,190) |
| ... of those, round the new drives and estates | - | 0.16 % |
| freeway deck lowest clearance over the hills | 2.9 m | 2.9 m (unchanged) |
| MacroMap.setup() | ~1.0 s | ~1.35 s (+~0.4 s: the walks; ground read off a 12 m lattice) |

(The probe's "steeper than 60" counts every 4 m cell the carve moves by more than 0.25 m; #17's
0.6 % was measured some other way, so compare before against after here, not against 0.6.)
Frame cost (still_shot / bookmarks GEO, opengl3, 960x540 / 1280x720):

| view | before tris / draws | after tris / draws |
|---|---|---|
| hills bookmark | 1,905,603 / 1,063 | 1,913,620 / 1,141 (+0.4 % / +7 %) |
| aerial over the pass (EYE 1180,424 AGL,-1330) | 1,359,261 / 1,093 | 1,407,347 / 1,259 |
| switchback at road level (402,1.8,-1873) | 3,746,872 / 1,643 | 4,077,925 / 1,772 |
| aerial over the west pass (560,260,-1600) | 1,012,307 / 826 | 1,061,056 / 1,017 |
| north flank from the valley (0,200,-2400) | 3,384,268 / 1,878 | 3,407,623 / 2,002 |

The draws are the estate houses (a Building is a handful of draws) and their palms; the pads,
walls, gates and pools are merged into the chunk's boxes, and an estate used to be ~8 nodes on
its own, so the old headland estates got cheaper.

**Stills**: branch `shots/switchbacks` (before/after pairs: aerial over the pass, a switchback at
road level, the west pass from above, the north flank from the valley, the hills bookmark).

**Checks** (smoke test, `_check_switchbacks()`): enough drives, hairpins and front-range
estates; every drive held to its grade and its banks meeting the ground (the exact ground, with
1.5 m more slack than the 12 m lattice the layout used); the carved ground round the first six
drives under 1.5 % steeper than 60 degrees; estates clear of each other and of every road; a
chunk with an estate up a driveway builds its driveway, house and walls.

**Traps found.** `Basis.scaled()` scales in GLOBAL axes: an estate's pad / walls / far house box
on a turned basis came out skewed into long diagonal sticks - use `scaled_local()` (the old far
hill-house box in `Skyline` and `_build_mansions` had the same bug; both fixed). `Vector2.orthogonal()`
is the clockwise normal in x/z, so a half circle to that side runs its angle DOWN - the first
hairpins doubled back on themselves. The layout is greedy and chaotic: a small change anywhere
(the foot drive's line, a clearance) reshuffles the whole network, so judge a tuning on the probe's
counts and map, not on one drive.

**Not done.** No drives on the south face (see above). No traffic, parked cars or people on the
new drives (like every hill road). The houses are the old SLAB villa; no cantilevered decks,
garages or terraces down the slope. Forward+ look not seen (opengl3 stills only).

## 9as. Car glass and drivers, 2026-09-28 (agent branch `wt/car-glass`)

Every intact car window used to be the model's own opaque dark glass, so every car on the street
was a sealed toy, and traffic drove itself with nobody at the wheel. Now:
- **Glass you see into.** Every body with a glass slot (the four road_* bodies and the four
  exotics; the Meshy sports car has its glass in the paint and stays as it was) wears
  `shaders/car_glass.gdshader` on it - ONE material per body type (`CarCabin.glass_material()`,
  from `Vehicle._add_cabin_glass()` after the wheel tuck), shared by every car of it with nobody
  inside (occupied cars wear a copy, below). Still
  opaque: the model's own glass colour, roughness and metal, so the renderer's reflection is what
  it was, and the cabin behind the pane emitted over it, dimmed by Fresnel (the reflected share
  is the renderer's), the pane's tint and `through_light`. Tints (`pane_n.w`, CarCabin
  constants): windscreen 0.8, front side glass 0.6, rear side 0.48 or privacy 0.17 behind the
  front seats of the crossover, pickup and van (picked per fragment: the pickup's two door
  windows are one piece of glass), rear screen 0.42 / privacy 0.17, a two-seater's engine cover
  0.1, mirror glass and lamps nothing.
- **One cabin, shared with the damage.** The trace CarDamage's shattered windows had
  (`cabin_view()`) is now `shaders/car_cabin.gdshaderinc`, included by both glass shaders
  (`#define CABIN_FIRE` gives the damage its `burnt` / `cabin_fire`; without it they are
  constants). New in it: the steering wheel (a raked washer rim with hub, spokes and column) in
  front of the driver's seat - the car's left, left-hand drive -, a centre console with a gear
  lever, a centre screen, the instrument cluster and screen glowing after dark while somebody is
  at the wheel (`dash_glow`), and the street lamps lighting the cabin and the far windows at night
  (`street_light` x `lamp_factor`). The damage glass is the same shader as before otherwise: the
  crazed sheet, the webs, the empty frame's cabin at `cabin_light`; what is still whole now shows
  the cabin through its tint like the intact glass (it was opaque, so the first round would have
  turned every window of a car black).
- **People.** `person()` in the include: head (hair by style - short, long, shaved, a cap - with
  a darker eye band), neck, shoulders, chest, thighs, and arms whose elbows bend down and out to
  hands at ten to two on the rim (a passenger's in the lap). Laid out from the top of the side
  glass down (`side_top`: the crown just under it, the shoulders a hand over the door line),
  because the bodies' cabins are about 10 cm lower than a real car's and a real-sized person
  put his head through the roof. Skin, tops (weighted like a street: mostly dark and neutral),
  hair, trouser colours, sleeves and build all rolled per car.
- **Who sits where.** Four uniforms (`occupant_top` / `_skin` / `_hair` / `_mate`; seats in
  `occupant_top.a`, bit 0 driver, bit 1 front passenger) set by `CarCabin.seat()` from
  `Vehicle._update_occupant()`: a car nobody is in stays on the body's shared glass, an occupied
  car gets its own copy (`_glass_own`, made once, kept through the pool), a damaged car's go on
  CarDamage's glass (forced when it swaps in, and after `repair()`). **This was first built with
  `instance uniform`s** (one material for every car, as asked) and the downtown still logged 267
  "Too many instances using shader instance variables" errors: each instance using them takes a
  16-item block of the global shader buffer, which the Compatibility renderer caps at 4096 items
  (WebGL2 only guarantees a quarter of that), and ~300 cars plus their shadow twins did not fit.
  Forward+ (65,536 items) would have held it, the web would not. A per-car copy costs a
  ShaderMaterial (~1 KB of uniforms) per occupied car and nothing per draw - every car already
  binds its own paint material.
  A car given `traffic` (the setter) gets a driver, re-rolled each time it leaves the pool, with
  a passenger in 22 % (`PASSENGER_SHARE`); he stays when a hit knocks the car out of traffic and
  is gone once it catches fire (`_abandoned()`); the player at the wheel is the player (the
  `driver` setter; the hero himself is hidden in a car, so this is him, in his black tracksuit),
  and the car he gets out of is empty; parked cars are empty; a cruiser seats its crew from
  `crew_aboard` (a setter), in uniform and cap, emptying as they get out.
- **Measured once per body type.** `CarCabin.measure()` - CarDamage's `_measure_panes()` /
  `_components()` / `_stand_in_panes()` / `_set_cabin()` moved there - keeps the panes, the cabin
  box, the door line, `side_top` and the seat rows per body type; CarDamage reads the same data
  (`CarCabin.for_car()`). Fixes on the way, which the damaged look shares: the front row sits
  `COWL_TO_SEAT` (0.95 m) behind the windscreen's foot (the middle-of-the-side-glass rule put the
  saloon's driver behind the B-pillar - only his arms showed in the front window - and the van's
  seat under its dash); no back seats in the two-seaters or the van's cab; the hypercar's
  double-shell windscreen is one windscreen (the inner shell was classed as an engine cover and
  drew the screen black); the exotics' mirror glass (in their glass slot, a metre outboard) no
  longer sizes the cabin; the cabin reaches forward until the dash face is `DASH_TO_SEAT`
  (0.72 m) ahead of the front seats (the supercars' short side windows sit well back, and the
  wheel was in the driver's chest; the road bodies already met it). Measuring takes 1-12 ms once
  per body type (the super coupe's 7k-triangle glass the most). Headless (no mesh data): the
  stand-in panes, as before.
- **Cost.** No node, draw or triangle per car: GEO identical with and without it (car_shot,
  one sedan: 40 draws / 171,714 triangles either way; the city numbers below). What it costs is
  the glass's fragments: the cabin trace (13 boxes, the wheel, up to two people of 11
  primitives each behind one box test) on the glass of cars within 30 m (the far twin has no
  glass slot) - 70 m for the exotics, which have no twin. Past `cabin_detail` (12 m) the small
  parts leave the trace. Under llvmpipe the close-up views ran 1.3-1.8x slower, but that box's
  timings swung by 50 % between identical runs with four agents on it; read it on the Mac.
  Downtown bookmark (`still_shot.gd --spawn=2359.4,880,0,12,2 --hour=12 --weather=clear --nohud
  --quality=0`, 1280x720, opengl3, `SPLIT=1`), `CAR_GLASS=0` against on: identical - GEO
  6,944,352 triangles / 3,526 draws / 3,559 objects both, the Vehicle category 441,873 triangles
  (6.4 %) / 271 draws (shadow 152,236) both. Memory: one ShaderMaterial per occupied car.
- **Tools.** `tools/glshot/car_shot.gd`: `OCCUPANT=npc[:seed]|pair[:seed]|player|none`, views
  `driver`, `inside`, `street`, `chase`, `CABIN_DEBUG=1` (a flat colour per body part - how the
  figure's layout was fixed), `CAR_GLASS=0` (also on `still_shot.gd`: the model's own opaque glass,
  the A/B), `TIME=n` (a view's frame time). Checks: `tests/car_cabin_checks.gd` (the shared
  material per body type, street cars occupied and parked ones empty across the city, a traffic
  driver staying when knocked out of traffic and carrying onto the damage glass, leaving a
  burning car, the player at the wheel, a cruiser's crew, the tints).
- **Look at it on the Mac (Forward+).** The balance of cabin against reflection is set on
  Forward+ car_shot stills (`through_light` 0.45: at 1.0 the seats measured 110/255 against the
  paint's 156); the Compatibility renderer lights the paint much brighter (the same car's bonnet
  ~240), so it has its own `through_light_compat` (0.9, `CURRENT_RENDERER`). The night look (the
  faces lit by the dash, the street in the far windows) is subtle on purpose. The empty frames
  of a shot-up car keep the damage pass's `cabin_light` 4 untouched (asked to stay the same); on
  Forward+ they read brighter than the paint, which is worth a look on the Mac.
- **Not done.** The sports car (single-texture Meshy body, glass in the paint) and the lot fill's
  cheap static cars have no cabin. Nobody is seen in an open car (the spider) except through its
  windscreen - there is no glass elsewhere to draw them on. Occupants are not shot or thrown
  out: a round through an empty frame passes them, and a carjacked NPC simply vanishes when the
  player takes the seat.


## 9at. Shop interiors behind street-level glass, 2026-10-04 (agent branch `wt/interiors`; roadmap #14)

The brief: at street level the storefronts (9ao) showed glass with nothing real behind it - each
bay was its own small empty "office" box from `room_interior()`. Now every shop is a room you can
read from the pavement, by day and at night. CLAUDE.md's "Shop interiors" note is the reference.

### What it does

- **One room per shop**, the width of the whole shop (2-4 bays), 6-9.5 m deep (salt 45), ceiling
  at 0.86 of the storefront; traced per pixel by `shop_interior()` in
  `shaders/shop_interior.gdshaderinc`, included by `building.gdshader` and called from the glass
  branch for storefront panes (offices above keep `room_interior()`). The ray starts where it
  crosses the (recessed) pane, in the shop's frame (x along `u`, so the bay's offset is added).
- **Fittings are boxes and rows of boxes** (`shop_row()`: the row's slab, then an analytic step to
  the next item's near side - a row of 6 tables is one call; `shop_row_z()` swaps axes). Kinds:
  retail (back and side wall shelving of rolled product facings - runs of the same pack, price
  rails - gondolas with end caps, a counter, chillers glowing on a grocer's back wall), clothing
  (two racks of garments with ragged hems, cubbies of folded stacks, a display table, two dressed
  mannequins on stands in the window), cafe (two rows of tables with pedestals and chairs facing
  the street, the counter with a lit cake case, a back bar with a chalk menu board, pendants on
  cords), restaurant (tablecloths, a buttoned banquette, framed pictures, pendants over the
  tables), laundromat (washers and dryers on the back wall and an island, portholes with drums,
  LEDs, a folding table), barber (chairs on chrome pedestals facing a mirror run, the counter, a
  waiting bench), bank (teller counter with monitors, a desk, stanchions) and lobby (below).
  Floors by kind (planks, checker vinyl, polished stone slabs, tile), walls with a wainscot and
  hung pictures, contact shadows under the rows near the glass, ceiling fixtures (fluorescent
  runs, downlights, linear slots). Detail finer than a pixel fades to its average; the pixel
  size grows with the ray's depth.
- **The room is what the sign says.** `Building.shop_names()` is the sign roll (now one
  function), `SHOP_NAME_ROOMS` maps every name to a room (BAKERY, PIZZA, BOBA -> cafe; SUSHI, DELI
  -> restaurant; LAUNDRY; BARBER, NAILS & SPA, TATTOO -> barber; BANK, DENTAL, TAX PRO -> bank;
  THRIFT, DRY CLEAN -> clothing; the rest retail), and `shop_room_codes()` packs the first 7 shops
  of each face into the `shop_rooms` ivec4 uniform (4 bits each). Past 7, and on the landmark
  towers, the hash `shop_room_kind()` (salt 40) decides.
- **Tower lobbies.** The middle shop of most faces (salt 44, 75 %) of a building over 30 m
  (`tower_height` = `Building.height`; the ground part of a tower is often a low tier, so the
  part's height cannot say) is a double-height lobby, 13 m deep: polished stone floor and walls,
  a row of columns, a lit reception desk, planters with plants against the side walls, a bench,
  and the lift bank on the back wall (steel doors, frames, amber indicators). It is lit all night
  (no shutter), has no neon or posters, its sign shows a street number (multiples of 25) instead
  of a shop name, and it throws a pool of light on the pavement (`shop_is_lobby()` mirrors the
  shader).
- **Light.** By day the room is lit from the front (faces toward the street and tops brighter,
  falling off inward), times the old storefront exposure, plus a little of its own light
  (`shop_day_light` 0.30) so a shop in shade is not a black hole. After dark, open shops use the
  old lit-room path with each surface's `lamp` and the room's colour - `room_tone()`: cafes and
  restaurants warm, laundromats cold or neutral, banks and lobbies neutral-warm, barbers bright;
  retail keeps the shop's own roll - and `Building.room_tone()` colours the pavement spill the
  same. Practical glows (`shop_glow`): pendant bulbs, chillers, cake case, till, washer LEDs,
  desk light strips, lift indicators, ceiling fittings. Closed shops stay dark (the old night
  light at the back), shutters and gates as before.
- **Cost guard.** Past `shop_fittings_distance` (80 m) only the room is traced.

### Numbers

geo_count (still_shot GEO, opengl3, same frames before/after; `tools/glshot/shop_probe.gd` found the
storefronts):

| View | before tris / draws | after tris / draws |
|---|---|---|
| Flower at Olympic, east side, noon (`EYE=2373,1.7,858,-90,-2`) | 2,866,214 / 1,507 | 2,866,220 / 1,507 |
| same, oblique (`2372.5,1.7,885,-125,-2`) | 3,051,561 / 1,693 | 3,051,565 / 1,693 |
| same, 21:00 | 2,961,974 / 1,526 | 2,961,980 / 1,526 |
| oblique, 21:00 | 3,227,171 / 1,755 | 3,227,175 / 1,755 |
| west side (`2344,1.7,883.6,90,-2`), noon | 3,081,345 / 1,632 | 3,081,357 / 1,632 |
| west side, 21:00 | 3,226,254 / 1,715 | 3,226,266 / 1,715 |
| midtown (`1069.5,1.7,265.8,-90,-2`), noon | 5,377,621 / 2,459 | 5,377,635 / 2,459 |
| midtown, 21:00 | 5,306,502 / 2,415 | 5,306,516 / 2,415 |

The few triangles are the lobbies' street numbers (shorter or longer text than the shop name).
Shader cost: `building_shot.gd BENCH=20` on a frame two thirds shop glass, llvmpipe, measured while
the headless check ran (noisy): ~110 ms -> ~131 ms (~+18 %), before the 80 m fittings cut-off.
On a GPU that is ALU on storefront pixels only; it has not been profiled on the Mac.

### Not done / to check

- **Needs the owner's Mac (Forward+)**: the rooms' daytime exposure under AgX and auto exposure
  (judged only in opengl3 stills), and whether shop glass reflections over them read right.
- The lobby rule counts shops from the ground part's face length in the shader and from `runs` in
  Building: on a face with cut corners they can disagree, so a lobby's pavement pool can sit one
  shop off (rare). ShopfrontKit's blade signs still carry a shop name on a lobby.
- No people inside (the crowd is outside), no real geometry: a camera pressed to the glass sees the
  boxes' hard edges. Real low-poly interiors within ~15 m would be the next step if the owner wants
  more.
- The midtown oblique shot was not rendered (the render job hit its time limit); its night pair
  shows both shops closed, so the night comparison is downtown's.

## 9au. The mountains from the air, 2026-10-04 (agent branch; owner: "make the graphics a million times better")

Redone from scratch after the first attempt (`wt/hills-air`) was lost to a container restart
before it was pushed. Two bugs, then the look.

**Bug 1: the dark dashes were Skyline's far chaparral mounds.** `Skyline._add_hills` put a low
squashed blob (9-22 m across, 2-3.4 m tall, `HILL_MOUND_*`) on every far stand, up to 28 a hill
block, under the LOD chunks too (they plant nothing, so the far tier's planting stays). From the
air at 1-2 km each was a 6 x 3 pixel blob, lit by the renderer against a far ground that paints
its own light and its ridges' shadows: rows of dark dashes over every range (`before_aerial_4`
below). Removed; the far tier plants only the oaks and sycamores in the hollows (`HILL_OAK_*`,
unchanged rolls), and the brush out there is the ground's own (the LOD tiles' stands and the
horizon plane's, the same field). Fewer instances, so it costs less.

**Bug 2: the far ground's colours were linearised twice on Forward+.** Proven with a probe (one
unshaded quad per input, 0.5 in, read back; `<scratchpad>/hillsair/cs_probe3.gd`, `cs_probe4.gd`):

| Input | Forward+ (lavapipe) | Compatibility (opengl3) |
|---|---|---|
| `source_color` uniform, default 0.5 | 127 (decoded) | 128 (raw) |
| plain uniform, default 0.5 | 187 (raw = linear) | 128 |
| Color SET from script, `source_color` / plain uniform | 127 / 127 (both decoded!) | 128 / 128 |
| `source_color` ImageTexture (the bake) / plain | 127 / 187 | 127 / 127 |
| imported JPG, `source_color` / plain (mean texel) | (107,98,33) / (173,166,100) | (107,97,31) both |
| `color` shader global (`sky_tint`) | 187 (raw!) | 128 |
| vertex COLOR, MultiMesh instance COLOR | 187 / 188 (raw) | 127 / 128 |
| StandardMaterial albedo_color | 128 (decoded) | 128 |
| lit ALBEDO 0.25 x sun 1, no ambient | 137 (= 0.25 linear) | 64 (= 0.25 raw) |
| lit ALBEDO 0.25 + EMISSION 0.25 | 188 (0.5) | 89 (passes add in linear) |

So Compatibility decodes nothing and lights the raw numbers (sRGB), Forward+ decodes
`source_color` inputs and lights in linear. `macro_ground.gdshader` wrote its natural colours
as LINEAR numbers (its own comment said so: "MacroMap's Color(0.216) arrives as 0.038") but
declared them `source_color`, so Forward+ decoded them again: straw 0.150 -> 0.020, rock 0.100
-> 0.010, seven to ten times too dark, and the plane on the Mac drew near-black olive ranges
against the near hills' straw. On opengl3 nothing decodes, which is why every still looked
right. (The terrain had the opposite trap on opengl3: its textures arrive raw, so its luma
ratios against LINEAR means came out two to three times too bright, then clamped - the web's
near hills were pale tan against a dark plane, `nf_before_gl_1` below.) Same family as the far
boxes' `instance_color_is_srgb` (fixed before; now checked by the smoke test too).

**The fix: every hill shader works in linear on both renderers.** `shaders/color_space.gdshaderinc`
(`cs_in()` on every `source_color` input, `cs_out()` on ALBEDO / EMISSION / BACKLIGHT, the
renderer told at compile time by `CURRENT_RENDERER`; no-ops on Forward+, the sRGB curve on
Compatibility), included by `macro_ground`, `terrain`, `hill_shells` and `far_canopy`. The plane's
linear colours lost `source_color`; `sky_tint` (raw on both) is decoded where it is used as light
and as the rim colour, and the far boxes' rim takes the same colour (`building_lod.gdshader`), so
the plane, the far canopy and the far city all fade to the horizon the sky actually draws (raw,
it was up to a stop brighter on the Mac). The painted band (past `paint_end`) is lit in the
renderer's own space (`lit_ws`), and its gain was measured, not guessed: `paint_gain` 0.66 ->
1.42 and `compat_paint_gain` 1.2 (see below).

**One ground, no copies.** The plane now includes `hill_splat.gdshaderinc`: the stand rule,
`hill_rocky()` (crest rock) and `hill_bare()`, and the colours (`straw_color`, `chaparral_color`,
`dirt_color`, `rock_color`, `snow_color`, `drain_shade`, `macro_variation` moved there from
terrain.gdshader) are the tiles' own uniforms, with every octave a far pixel cannot resolve at
its mean and the edge widened by what it spread; `FAR_CHAP_TONE` / `FAR_BARE_SHARE` are the
tiles' straw and brush as they average from afar, `FAR_TONE` 0.91 the measured remainder. The
painted band draws the stands too (mottled by the 27 m and 90 m patch octaves while they
resolve) instead of a smooth share, plus crest rock and the craggy faces (`far_rock_slope_*`).
`tests/hill_air_checks.gd` fails if a copy of a splat uniform reappears in the plane.

**The look: Los Angeles ranges.** `south_grass` 0.08 -> 0.35, `drain_brush` 0.45 -> 0.6 (splat
and HillPlanting): measured over 3,111 points of the front range (`share_probe.gd`), the south
faces - what the whole basin looks at - go from 86 % brush (one olive-brown tone) to 54 %:
gullies 97 %, mid-slopes 51 %, spurs 6 %; north faces stay 89 %, east/west 46 %. So a south face
is gold ribs and dark folds, as the real front ranges are from the city. Colours (linear): straw
(0.150, 0.124, 0.074) -> (0.200, 0.158, 0.076) pale gold, chaparral (0.050, 0.056, 0.036) ->
(0.046, 0.058, 0.040) dusty grey-green, sage (0.082, 0.086, 0.064) -> (0.085, 0.097, 0.075),
dirt (0.150, 0.126, 0.094) -> (0.205, 0.176, 0.133) and rock (0.112, 0.106, 0.096) -> (0.172,
0.164, 0.150) pale, so crests and fire cuts read as pale rock rather than dark scars.

**Measured (small scenes; the city does not fit lavapipe).** `tools/glshot/hill_ground_shot.tscn`
grew what it took: `GROUND=1` (the horizon plane, CityStreamer's own material and bake), `LOD=n`
(a LOD ring), `CENTRE=x,z`, `HILLS_ONLY=1`, `MASKS=1` (the frame again without the plane, without
the chunks, without either: which pixel is which tier), `NOFOG=1`, `DAYNIGHT=1` (the city's
DayNight held at `-- --hour`, so the light is the game's: the scene file alone has the sun at
1.0 and the ambient at 1.0 against the game's 1.3 and 0.3), `PAINT_AB=1` (the plane all lit /
all painted, via `paint_debug`). The scene: FULL 3x3 and LOD to 6 blocks round (300, -1500), the
plane, the front range from (300, 400 m up, -300) looking north and from (300, 900 m up, 600);
14:00, no fog. Seam = linear luminance of the plane over the tiles along their shared edge
(`<scratchpad>/hillsair/seam_measure.py`):

| Seam, plane / tile | Forward+ before | Forward+ after | opengl3 before | opengl3 after |
|---|---|---|---|---|
| 400 m up, the range's flank 0.6-1.2 km off | 0.37 | 1.08 | 0.59 | 1.05 |
| 900 m up, 1.5-2.5 km off (in the paint ramp) | 0.57 | 1.15 | 0.32 | 1.00 |

(Saturation of the plane against the tiles at the seam, Forward+: 0.68 / 0.80 before, 0.98 / 0.74
after; the far view's 1.15 is the paint ramp, where the plane is lit by its own light.)
Painted band / lit band, the same pixels (`paint_measure.py`): Forward+ 0.63-0.73 at the old 0.66
(and the plane was decoded twice on top), 0.81-0.83 at 0.97, 1.10 / 0.92 (mean 1.01) at 1.42;
opengl3 0.51-0.55 at the start, 0.89 / 0.70 at 1.42 x 1.05 (seam from 900 m 1.00), 1.22 / 0.92
at 1.36 (seam 1.27): `compat_paint_gain` is 1.2, between them, not rendered again. The two views
disagree by 20-30 % on Compatibility whatever the gain (its light passes add in linear, its
albedo is lit in sRGB numbers), so one number cannot be exact there; on Forward+ they agree.
Before/after frames: `<scratchpad>/hillsair/seam/dn_before_vk.png` / `dn_after6_vk.png`
(Forward+, the game's light), `dn_before_gl.png` / `dn_after6_gl.png` (opengl3), and the `_1`
views (900 m up).

City stills (opengl3, `DIFF=1`, 14:00, clear, one load, `<scratchpad>/hillsair/shots.sh`; before =
this branch's base 28105b5, after = 7414f46 with `compat_paint_gain` 1.36), in
`<scratchpad>/hillsair/shots/`, grey p1/p5/p50/p95/p99 and std of a box over the ranges:

| Still | Box | Before | After |
|---|---|---|---|
| `*_aerial` front range from 500 m (EYE 700,500,-300,0,-14) | back range | 101/103/129/166/177, std 22.6 | 108/114/159/178/184, std 19.3 |
| same | sign hill + foothills (tiles and plane) | 70/89/107/174/203, std 26.1 | 84/115/157/180/205, std 20.5 |
| `*_aerial_1` high air 900 m (500,900,300,0,-28) | front range | 81/87/98/145/206, std 23.0 | 91/102/162/189/207, std 24.9 |
| `*_aerial_2` street, avenue north (714.1,2.5,-100,0,5) | mountains over the street | 14/34/107/182/200 | 14/34/123/183/200 |
| `*_aerial_3` the range face 140 m up, looking east | whole frame | 51/74/123/194/215 | 60/91/155/195/215 |
| `*_aerial_4` hills bookmark (300,250,-650,0,-6) | sign hill | 73/83/103/161/188, std 24.7 | 101/119/152/175/189, std 17.7 |
| `*_aerial_5` the back range from the valley (900,300,-2000,0,-4) | ranges | 81/85/106/174/193 | 89/96/154/181/195 |

What they show: no dashes (`before_aerial_4`: rows of them over the sign hill; after: a few
oaks in the hollows), no tide-line where the tiles meet the plane (`before_aerial`,
`before_aerial_1`: pale tan tiles against a dark brown plane), the back range no longer a dark
monolith. What they do NOT show is the Mac: on Compatibility the albedo is lit in sRGB numbers,
so a mid albedo under a 1.3 sun comes out paler than Forward+ draws it (the small scene: the same
tiles 172/157/126 on opengl3, 140/121/97 on Forward+), and the ranges read pale and low in
contrast in these stills (the hills bookmark's std 24.7 -> 17.7). Before, opengl3's tiles were
as pale (their textures' luma ratios were two to three times too high) and the plane dark; the
plane now matches them. Judge contrast on Forward+.

geo_count at the front-range aerial (`--spawn=700,-300,0,-14,500 --hour=14 --quality=0`, 800x600):
6,434,032 triangles / 4,380 draws / 4,429 objects before, 6,280,384 / 4,376 / 4,425 after
(-153,648 triangles, -2.4 %: the far chaparral mounds, a blob with no LODs counted per instance;
-4 draws: hill tiles whose planting is now empty build no planting node). The shaders' extra work is
ALU only and on Forward+ nothing: `cs_in` / `cs_out` compile out; the plane's natural ground
evaluates the splat's functions instead of its own copies of them (about the same), plus the
crest-rock cell noise and two fades.

Checks: `tests/hill_air_checks.gd` (loaded by the smoke test after the distance checks): the
four hill shaders include the colour-space include and call `cs_out`, the plane's only
`source_color` colours are the five sRGB-authored ones, the splat has none, the renderer test is
`CURRENT_RENDERER`, the far boxes decode their instance colour where the renderer decodes the
near ones, the plane includes the splat and redeclares none of its 25 uniforms, and far hill
blocks on the front range plant no clump lower than an oak. The headless check passes (579).

**Not verified.** The Forward+ look of the whole city from the air (lavapipe cannot hold it):
the small scene proves the seam and the colour space, not the final grade under the player
camera's auto exposure, SDFGI over the real basin, or the aerial-perspective fog. Ask the owner
for a Mac shot from `--spawn=700,-300,0,-14,500` and from a street looking north
(`--spawn=714.1,-100,0,5`). The painted band's gain was measured at 14:00 only; at golden hour
the renderer's light and the plane's own (`sun_strength`, `ambient_strength`) may part again.
The far oaks are still lit by the renderer in ridge shadow. The spiky back-range summits are the
height field's erosion (9ab), untouched here.

**Traps found.** A Color set from script is decoded on Forward+ even into a plain `vec3` uniform
(only a Vector3 is not); `color` shader globals arrive raw on both. On Compatibility the light
passes add in linear (0.25 + 0.25 drew 0.35), so EMISSION and the renderer's lit albedo do not
mix the way the sRGB numbers suggest - measure, do not derive. A probe camera that shows two of
ten quads reads two cases ten times (the first probe "proved" Forward+ decodes nothing); a seam
mask built from "changes when the chunks are hidden" misses exactly the good seams, where the
plane below is the same colour (`_none.png`, the frame with neither, fixes it). And `flock -o`:
killing a waiting flock whose child already started leaves the render running without the lock.

## 9av. The crowd in our own garments, 2026-10-04 (agent branch `worktree-agent-ab30bcf7c66c96fb9`)

After 9aj the crowd's faces held up at 2 m and its clothes did not: MakeHuman's library garments
are soft photographs (one V-neck on every tee, the same jeans wash on half the crowd), and the
shader had nothing left to pull out of them. Eight of the twelve people now wear garments modelled
on their own bodies and painted texel by texel; the patch that started it
(`docs/wip/crowd-garments.patch`) is gone, its code is `tools/crowd/garments.py` and
`tools/crowd/garment_paint.py`.

### Who wears what

| rig | outfit |
| --- | --- |
| a | white crew tee (regular), mid-wash indigo jeans |
| d | rust fitted tee, black slim jeans with a grey fade and grey thread |
| e | mustard tee, washed denim shorts above the knee |
| h | white button shirt with blue pinstripes, long sleeves and cuffs, grey washed jeans |
| i | heather-grey fitted tee, black leggings |
| j | chambray shirt, sleeves rolled, chest pocket, loose; dark jeans |
| k | teal fitted tee, light stonewash jeans |
| l | burgundy long-sleeved tee, charcoal chinos |

b (overalls), c (blouse and skirt) and g (suit) stay in MakeHuman's clothes: there is no garment
of ours for a bib, a skirt or a tailored jacket yet. **f went back to his library clothes at the
lead's review**: built in our olive zip jacket and khaki chinos he read plainer than his tailored
jacket with lapels and pockets over a striped shirt. The jacket builder and painter stay
(`garments.jacket()`, `garment_paint.paint_jacket()`), worn by nobody; f's outfit was
`[{"type": "trousers", "style": "chinos", "color": [150, 128, 92]}, {"type": "jacket",
"color": [78, 84, 58], "rib_fabric": "jersey", "zip_color": [38, 38, 36]}]`, which is how to
put it on somebody.

A row opts in with an `"outfit"` list in `tools/crowd/crowd_config.json` (its `"clothes"` then
hold only the shoes); the keys are in the header of garments.py.

### How

- **Shape** (`garments.py`, inside `build_character.py`'s Blender run, before the cover test).
  Every garment is a shell grown off a Taubin-smoothed copy of the body (its UVs and weights
  carried), so it moves with the rig for free. An `Envelope` (a convex hull per centimetre slice
  about a fitted axis, hung from the chest by a slope, blurred over azimuth and height) gives a
  top its drape over the chest and shoulder blades instead of the skin's every dip; sleeves and
  legs are tubes measured on the limb's own vertices. Planes cut the hems, the neck and the
  sleeves (the sleeve cut only takes faces that are both past the plane and near the upper arm,
  or a heavy torso lost its side), and every hem is turned in as a lip. Collars (crew rib,
  stand-and-fall with points, stand), cuffs, rib bands, the placket, the zip tape and teeth are
  swept bands along a curve; buttons and the zip pull are discs. The shirt tail is a curved cut
  from tangent planes round the hips.
- **Layers.** A top is pushed off the trousers by a grown, blurred displacement field
  (`push_smooth`), the trousers under a top are deleted with a margin whose weights blend to the
  top's (`hide_under`), and everything clears the body by a few millimetres along rays cast FROM
  the point. Weights are blurred round the shoulders and the crotch before the trousers are cut.
- **Paint** (`garment_paint.py`, called by `crowd_atlas.py`). A garment has no source photo: its
  atlas rect is "virtual" and every texel is painted from what it is in 3D - rasterised from the
  triangles `build_character.py` dumps (`own.npz`: position, normal, part, zone, AO) -: twin-needle
  hems, neck coverstitch, rib wales, heathered jersey; on trousers the waistband, belt loops, fly
  J-stitch, yoke, patch and slant pockets, out- and inseams, hem roping, denim wash with whiskers
  and knee honeycombs, slub, chino welts and a crease; on shirts the yoke, placket rows, button
  band stitching, a chest pocket, woven stripes or checks; on the jacket welts, rib wales and zip
  teeth. A height field gives the normal map at its real scale in metres; 9aj's fold field is
  added on top (`fold_gain` 0.7). Patterns are box-filtered per texel in metres (`mpp`), which is
  what keeps a 1.1 cm pinstripe from turning into moire. Colours and patterns re-read the
  outfit, so a recolour needs only `FROM=crowd_atlas`.
- **The contract is unchanged.** The garments join the ONE Body surface; R / G carry the top and
  bottom fabric levels, B the hair, A the skin, and buttons, the zip's teeth and pull are the
  "other" region (all zero, never recoloured). The welded mid / far bodies, the camp-figure
  bakes, limb cutting and the police recolour see an ordinary rig: no game code changed. The
  crowd-rig contract checks pass on all twelve.
- **Preview without the lock.** `tools/crowd/preview.sh out.png crowd_a,crowd_h front,side,back`
  renders the built rigs in Blender Cycles in seconds a view (`FLAT=1` geometry only, `REGION=1`
  the region colours - green on a top is trousers showing through, black is skin; views include
  `torso` and `sleeve_r`). It is how every fix here was judged before the Godot lineup, because the
  opengl3 render lock was queued for an hour at a time.

### Cost

Body triangles per rig (LOD 0, the hair unchanged): a 12,215 -> 12,537, d 11,954 -> 12,505,
e 12,735 -> 12,851, h 11,071 -> 12,611, i 11,421 -> 12,407, j 11,061 -> 12,841, k 11,954 ->
12,515, l 10,526 -> 11,662 (b, c, f, g in library clothes). The shells are decimated to
per-garment budgets and kept smooth (the 9aj lesson: a step in a crowd body is what the importer's
LODs keep). Downtown bookmark (`tools/geo_count.gd --spawn=2359.4,880,0,12,2 --quality=0`,
800x600, opengl3, `AB=Body,Hair`, the same frozen frame with every Body and Hair node hidden),
the 28105b5 rigs swapped in against these:

| | frame triangles | draws | objects | the crowd's share (Body + Hair) |
| --- | --- | --- | --- | --- |
| before | 5,969,405 | 4,196 | 20,280 | 270,432 triangles, 315 draws |
| after | 5,997,007 | 4,196 | 20,280 | 298,034 triangles, 315 draws |

+27,602 triangles, 0.46 % of the frame (the crowd's own share +10 %), draws and objects
unchanged. That was measured with f in the zip jacket (+2,108 triangles on his body); with f
back in his library clothes the cost is lower still and was not measured again. The welded mid /
far bodies are capped by `mid_triangles` / `far_triangles` as before, so the difference is the
near people. If it has to be zero, the lever is each garment's `tris`
(1,800-1,900 a shell today) - a full Blender rebuild of the rows that change.

### Judged

Every fix in Cycles previews first (front, side, back, torso, sleeves, feet; flat, region and
textured), then `crowd_lineup.gd` (`LIGHT=street`) against the 28105b5 rigs: a close shot per
person front and side (`SHOTS=`, `TURN=90`) and the whole crowd front and side. What reads at
2-4 m: turned hems, crew rib collars, the shirt's collar points, placket and buttons, the rolled
sleeves, the jeans' wash, pockets, yoke and inseam, a break over the shoe. The police recolour
(look 1 with `uniform_material()`'s numbers through `MAT_PARAM`) turns a, d, f, h and j navy as
before (f was shot in the jacket he no longer wears); h's pinstripe shows through the navy as the
old h's stripes did. The lead's review of the first shirt (blue swirl bands across chest and back) was
the painter's sleeve test - fixed by the `zone` attribute below; the dark V nicks at the tee hem
were the jeans poking through - fixed by `hide_under`.

### Traps (each cost a round)

- **A push-out ray must start at the point.** Cast inward from outside the cloth, it hits the
  far side of a fold (crotch, armpit, under the breasts) and throws the vertex through it - the
  nipple tents and the navel dent were this.
- **Trousers under a top poke through at every stride** unless they are cut away and their
  margin takes the top's weights (`hide_under`); clearance alone is not enough, the two layers
  are skinned to different bones at the hem. Blur weights BEFORE that cut, or the blur pulls the
  cut edge's weights back to the legs.
- **The crotch.** Flatten it only on the front and never let a vertex cross the midline: its
  weights are its own leg's, and one that crossed was dragged by the other leg into a spike.
- **Stripes swirled** because the painter read sleeve and body from 3D distance (the armpit
  folds give it both); the shell now writes a `zone` per face (body, left / right sleeve) that
  the painter reads, and the pattern runs in body coordinates from the torso axis.
- **The cover test** treated skin in the armpit as uncovered and kept it (pale slivers). For our
  garments it counts torso skin outward from the torso's axis, and a lone miss among covered
  neighbours as covered.
- **AO is baked on a coarse shell in the rest pose** the game never shows, so it is gentle with
  a floor (`own_ao` 0.32), and the hem lips are left out of its rays (they made zigzags).
- **The ankle.** 9aj's fold field stacks rings over the ankle, which is right for the hero's
  gathered track pant and read as jogger cuffs on every hemmed pair in the first lineup.
  `tools/hero/folds.py` takes `ankle_stack` / `ankle_reach` from the landmarks (absent for the
  hero: 1.0 / 0.2) and crowd_atlas.py sets them from the trousers' style. Gold thread on black
  jeans read as a track stripe down the inseam; d has grey.
- **Blender:** adding a corner attribute reallocates the others, so re-fetch layer handles after
  each; the glTF importer multiplies the texture by COLOR_0 (the region colours) - a preview has
  to unplug it; two imports of rigs share datablock names, so preview.py loads each rig into a
  fresh file.

### Not done / next

- b, c and g: an overall bib, a skirt and a blazer would finish the set; a tailored jacket with
  lapels and pockets (f's look) is the garment most worth building next.
- Long-sleeved tops show faint horizontal creases across the shoulder blades (the fold field
  over the shell's own shading), the ankle stacking on jeans is a little regular, and e's back
  hem has a small step where the tail meets the side. None reads past 3 m.
- The garments' AO and folds are baked for the rest pose; nothing moves the fabric in a stride
  beyond the skinning.

## 9aw. Car lights that light the world, 2026-10-04 (agent branch `wt/carlight`; roadmap #26, #41; GAME_PLAN G4 / G6)

**#26 verified first.** HANDOFF 000 said the beam fix was ported to main: it was. The beam quad
lies at `ground + 0.12` (12 cm over the road) in `PropFactory.vehicle_lights()`, and it shows in
every still below. Row #26 is closed.

**What shipped** (CLAUDE.md "Car lights" has the whole contract):
- **The lamp mesh got a state.** Still one mesh and one draw a car (`vehicle_lights()`), now on
  `shaders/car_lights.gdshader` with amber indicators at the four corners, reversing lamps and a
  red wash on the road behind; the part is in the quad's u shift. The car's state is one of a
  few shared materials (`PropFactory.vehicle_light_material()`: brake x signal x blink phase x
  reverse, at most 52), never instance uniforms. `Vehicle._tick_lights()` decides it each tick:
  player brake / handbrake / reverse; traffic brake from its speed falling or standing (held
  0.35 s); the indicator of the turn TrafficManager rolled (`t.turn`, `t.to_c` - new, the
  distance to that junction's centre - within 48 m), a U-turn as a left; hazards on a car
  knocked out of traffic with its driver in. Brake, indicator and reversing lamps show by day.
- **Parked cars are dark now** (they burned head and tail lamps like moving cars). A car's lamps
  are on while somebody is in its cabin (`lights_running()`).
- **Real headlights, Forward+ only**: `CarLights` (one node under the tree root, made by the
  first Vehicle). The player's car: a 44 m beam with the low-beam cookie (flat cut-off at lamp
  height, kick up on the right), shadowed at HIGH, and a red OmniLight3D behind for brake /
  reverse. Traffic: up to `budget` (6 HIGH, 3 MEDIUM, 0 below) running cars within 60 m, nearest
  first (cars behind the camera count 1.8x further), plain soft cones dipped 7 degrees, faded by
  distance and on every hand-over. Never on the web or Compatibility (`CarLights.force` for
  stills).
- **The trap that cost an hour**: Godot maps a spot light's projector through its shadow matrix,
  which an unshadowed spot never gets, so a cookie on an unshadowed spot draws NOTHING (lavapipe
  Forward+: with the player's shadow off its beam vanished; with the cookie removed it came back).
  Compatibility ignores projectors entirely, so an opengl3 still cannot judge a cookie - my first
  "fix" to its orientation was made on opengl3 and was wrong. Judge the cookie on
  `tools/glshot/car_light_shot.gd` under lavapipe (a minute a shot).

**Tools**: `tools/glshot/car_light_shot.gd` (a small night street: the player's car, an oncoming
traffic car, a parked pickup, a brick wall; `VIEW=chase|side|top|rear`, `NOLIGHTS=1` is the
before, `BRAKE=1`, `REVERSE=1`, `PSHADOW=0`, `NOCOOKIE=1`). `still_shot.gd`: `CAR_LIGHTS=1` forces
the spots onto an opengl3 still; a `LIGHTS` line after every GEO (car spots and street-lamp
omnis, on and in view); `STREET_EYE=1` puts the camera on the pavement behind a `STREET=queue`.
Checks: `tests/car_lights_checks.gd` (parked dark, shared materials, brake on / held / off,
indicators against the car's own right on both axes and directions, U-turn, hazards, player
brake / reverse, broken headlamps, CarLights' budget, reach, player shadow and cookie, day off).

**Cost** (opengl3 counters; the spot lights add no draws or triangles - their cost is per-pixel
GPU shading on Forward+, which only the Mac can measure; the player's shadowed spot adds one
shadow pass of what is within 44 m of the bumper):
| frame (opengl3, 960x540, --hour=22, clear) | before | after | car spots on (in view) | street-lamp lights in view |
|---|---|---|---|---|
| braking queue at Flower (still_shot STREET=queue STREET_EYE=1, same frame) | 7,518,784 tris / 2,788 draws | 7,518,768 / 2,778 | 6 (6) | 51 |
| pavement, Flower at Olympic (still_shot) | 7,056,618 / 3,758 | 7,056,580 / 3,750 | 1 (1) | 126 |
| geo_count.gd at the avenue bookmark (--spawn=2359.4,880,0,12,2) | 4,751,217 / 3,669 | 4,751,077 / 3,655 | - | - |

The few draws saved are parked cars' lamp meshes, now hidden. Stills (orphan branch
`shots/carlight`): `street_*`, `queue_*` (opengl3, the spots forced on with `CAR_LIGHTS=1`),
`wall_chase_*`, `wall_top_*`, `wall_rear_*` (car_light_shot.gd on lavapipe Forward+; `before` is
`NOLIGHTS=1`, the lamp mesh alone, what the web draws).

**Found on the way**: PhysicsBudget switches off the per-step script of every car past
`vehicle_script_radius` (100 m) - traffic too - so a traffic car's lamp state froze there (an
indicator blinking or a brake light on for good). `TrafficManager._place()` now ticks the lamps of
any car it places whose own script is off. In the queue still two cars pulling away show only a
faint tail glow: the following car's (forced, opengl3) beam washes their tailgates white; the
new tail glow measures brighter than the old one on the same car (car_light_shot.gd `OLDMAT=1`
is that A/B).

**Needs the owner's eyes on the Mac**: beam energy and the cut-off under AgX and the camera's
auto exposure (`player_energy` 24, `spot_energy` 6 - tuned on lavapipe with a fixed exposure);
the frame time with six beams downtown (drop `CarLights.budget` if it shows); whether the
indicators read at 1.5 Hz.

**Not done**: no shadows on traffic beams (cost); no cookie on them (the engine trap above);
traffic does not signal lane changes or kerb pull-overs for sirens (only turns); the replica
area's traffic (`ReplicaTraffic`) and the freeway never signal (they roll no turns); far
headlights past 160 m are still the mesh's glows only.

## 9ax. The Pacific and the beach, 2026-10-04 (agent branch `wt/ocean`)

The brief (lead, from the owner's "make the graphics a million times better"): make the coast
read like Santa Monica / Redondo in a 2026 game - breaking surf along the whole waterline, the
swash running up the sand and draining back, colour by depth, kelp, sun glitter, the backs of
waves glowing at golden hour, the pier and the city in the water at night, storm surf, spray.
CLAUDE.md's "Surf and beach" note is the reference; this is the story.

**What was there.** Gerstner swells with crest foam and a fresnel sky mix; the "surf" was two
bands of `sin(shore)` foam sliding toward the sand and a 14 m white wash painted over the last
of the water, so from standing height the near sea was a white smear. The sky reflection was in
ALBEDO, so it was lit by the sun: fine at noon, black at sunset (the golden-hour still was a
brown-black sea under an orange sky) and nothing at night (the pier stood over a black void).
And every street that ran into the sea left a hole in the beach: the sand was laid over the
block's rect only, and the sea chunk's flat water plane showed through the road strip - the
"beach at noon" bookmark first landed the camera standing in one, up to its knees in sea.

**What it is now.**
- One wave model, `shaders/surf.gdshaderinc` (header explains it), shared by the ocean, the sand
  and the spray and mirrored by `Surf` (scripts/world/surf.gd). Waves are crests parallel to the
  shore, each with its own height (sets of bigger waves, sections along the shore), standing up
  to a break point that grows with the wave, throwing a lip there and running in as a bore that
  shrinks to nothing at the waterline. Weather sets two globals from the wave scale
  (`Surf.params()`), so a storm is 2.9 m surf breaking 103 m out, a clear day 0.9 m at 38 m.
- Ocean vertex: the surf's height and lip in the zone (the way to the land is the gradient of
  `shore_distance()`), with analytic derivatives so the normal and the fold see it; the swell
  hands down to 30 % there. Fragment: whitewater from the same wave (bore face, trail, lip,
  feathering, a warped net of old lace), breaking in sections that peel along the crest, the
  light through each standing face (warm jade when backlit at golden hour), kelp beds, sandy
  shallows that match the swash sheet at the seam. The mirror is EMITTED and the body lit.
- At night (`lamp_factor`) the piers' lamp rows (`Weather.pier_light_lines()`: the old pier,
  Manhattan's two rows, Redondo's horseshoe as two legs and three chords) and a wall of city
  light `city_front` inland are mirrored by intersecting the reflected ray with their vertical
  plane, smeared into columns by the ripple the pixel cannot resolve.
- Sand: `shaders/beach_sand.gdshader`, the old pbr sand plus the swash (sheet, foam line and
  web, fizz, wet glossy sand after it, rain through `road_wetness`). UV2 on the sand mesh is the
  metres from the waterline. The sand now covers the +Z street strip and dips under its road.
- Spray: one MultiMesh of quads per FULL shoreline chunk, puffed in the shader as each wave
  breaks; between waves every quad is transparent.

**Stills** (opengl3, 960x540, `still_shot.gd`; `shots/ocean` branch, README there):
- Esplanade bluff looking down: `EYE=-458,15.5,3380,100,-14 FOV=60 --spawn=-458,3380,100,-14
  --hour=12`, and zoomed `-458,15.5,3380,100,-9` at FOV 28.
- Beach at noon near the waterline: `EYE=-732,2.1,800,105,-4` (z 800, 6 m up the sand).
- Golden hour toward the sun: `-732,2.1,800,92,-1` at `--hour=18` and at 17.6 (at 18:00 the sun
  is on the horizon due west, so 17.6 is the one with the glitter path).
- The pier at night: `-712,2.2,1000,130,-2` at 21.5 (Manhattan pier).
- Storm: the beach view and the bluff with `--weather=storm`.
All in one load with `SHOTS=` (see the README for the exact command).

**Cost** (`tools/geo_count.gd`, opengl3 960x540, `--hour=12 --weather=clear`, before -> after):
beach z 800 `--spawn=-732,800,105,-4` 543,392 tris / 427 draws -> 544,032 / 431; Esplanade bluff
`--spawn=-458,3380,100,-14,15` 1,445,798 / 932 -> 1,446,070 / 937; by the Manhattan pier
`--spawn=-712,1000,130,-2` 815,832 / 1,893 -> 816,472 / 1,896. So +0.1 % triangles and +3 to +5
draws (the spray, one a shoreline chunk; the sand over the street strips). The ocean adds no
geometry (same plane), the sand one more row point and the strip rows. ALU:
the surf's vertex work runs only inside the zone (2 extra shore distances and 2 surf
evaluations a vertex there); the fragment's whitewater only inside it; the night lights only at
night; kelp only where `ground_detail` is on.

**Not done / not verified.**
- Forward+ (Mac): the emitted reflection's exposure against the lit sand, SSR on the swash sheet
  doubling the emitted mirror, TAA on the lace. Opengl3 only here.
- The spray is hard to see in a 1 fps harness still (each puff lives 2.6 s of shader TIME and
  the stills hold TIME nearly still); judge it on the Mac at the beach.
- The surf runs wherever there is a shore distance: the headland's cliffs get it too (plausible),
  the harbour basin by the port may show a faint surf line near the bay's north shore.
- The waterline was striped in nested zigzags for most of the session, and it was not
  z-fighting, though it looked exactly like it: the whitewater read the interpolated surf phase,
  which was 0 on vertices outside the zone and hundreds of periods inside, and the foam texture
  projected world positions onto an interpolated shore tangent. Fixed (phase on every vertex,
  foam on true-world z). Along the way: the sea is held over the ground follower near the shore,
  the surf is flat for its last 3 m, and the sand falls away under the water - all three were
  real, smaller problems. A dip of the sea plane under the sand was tried and made a sawtooth;
  it is not in.
- The far plane (past ~470 m) still paints its own surf band from the bake; there is no
  breaking surf in the far tier.

## 9az. No bare ground outside downtown and midtown: yards, the campus, the freeway's right of way, 2026-10-04 (agent branch `worktree-agent-afdcc0e44305064bc`, the brief's `wt/lot-fill-2`)

The brief (00000): fill the beach town (9am's "not done"), the campus blocks, the freeway sides
and the empty block south-east of MacArthur Park, each the way the real place looks. This redoes
a branch lost to a container restart. Measured with `tools/lot_coverage.gd`, which now runs on
`GroundCoverage` (`scripts/world/ground_coverage.gd`, the same code the smoke test calls):
`FILL=lot` is the city before this branch (LotFill on, YardFill off), `FILL=1` after, `FILL=0`
neither. Replica blocks (the Esplanade's: ReplicaBuilder builds them) are left out now; the
campus hall's footprint counts as built.

Whole basin, seed 1337 (`RECT=-3000,-3000,8000,8000`), bare share of the blocks' ground inside
the pavement ring:

| Row | bare before (`FILL=lot`) | bare after (`FILL=1`) | what covers it after |
|---|---|---|---|
| Beach town (71 seeded blocks) | 56.0 % | 3.7 % | built 38.3, garden 47.5, parking 3.6, row 4.1, yard 2.9 |
| Campus (6 blocks) | 74.3 % | 1.2 % | built 25.7 (incl. the hall), garden 61.2, parking 12.0 |
| Freeway blocks (166, any district) | 17.7 % | 6.3 % | row 46.7; what is left is suburban lawn and industrial yard beside the right of way |
| The right of way's own cells (ROW_CELLS) | 23.1 % | 0.0 % | row 100 |
| MacArthur SE (the plaza, 1 block) | 96.7 % | 7.0 % | built 35.8, forecourt 44.9, yard 12.2 |
| Downtown core / rest / midtown (LotFill's) | 2.2 / 2.4 / 5.0 % | 1.2 / 1.5 / 3.5 % | the right of way through them |

The old tool on the base commit gave the beach town 62.5 % over 106 blocks (35 of them the
Esplanade replica's, which ReplicaBuilder builds) and the campus 93.1 % (the hall's own ground
counted as bare). Suburbs (82.5 %, the plain block lawn) and industrial (39.7 %) were not in the
brief and are as they were apart from the right of way.

**What it does** (`YardFill`, `scripts/world/yard_fill.gd`; the rules are the CLAUDE.md bullet
after LotFill's):
- **Beach town.** Every lot with a house gets its yard out to its grid cell, planned in the lot's
  street frame from the plan and the house's ground footprint: a driveway on one side of the
  frontage (32 % of lots; a static car in some), a front walk to the middle of the house, the
  front garden (lawn 34 %, decomposed granite with gazania 40 %, brick or saltillo 18 %, paved
  the rest) with a mulch bed of shrubs along the house, the street line edged with a low stucco
  wall (cap course in a lighter trim), white pickets or a clipped hedge, open at the drive and the
  walk; timber (or stucco) fences down the lot lines from the house front back and along the
  back; the back yard lawn, deck, tile, concrete or decomposed granite (a pool in the few deep
  enough); an L's inner corner a saltillo courtyard with a fountain and two palms (the courtyard
  apartment); wheelie bins in the side yard. 29 of the 67 non-replica beach blocks get a **walk
  street**: the row boundary along x where every column leaves the widest gap between its two
  rows of houses (at least `WALK_MIN`), a brick or concrete path with lamps down it, the houses
  along it fronting it with their gardens and low walls. The cells the boardwalk's, the piers'
  and the mall's squares dropped are beach car parks (LotFill's) or pocket parks (lawn, a walk,
  palms, benches, a clipped hedge), trimmed off the sand and the boardwalk's shops.
- **The beach town is lower** (DISTRICTS BEACHTOWN height 5.5-12.5 m, was 6-18; finishes mostly
  FLAT): "low stucco houses" - the old band put four- and five-storey blocks on every lot.
- **Campus.** The campus hall's square drops every lot of the four blocks round it, which were
  plain lawn; now its free ground (less `Landmarks.campus_footprint()`) is quads (walks corner to
  corner as ribbons and one across, trees along them, lamps, benches round the crossing, shrubs
  along the edges), one surface car park a block (no longer than `CAMPUS_PARK_MAX`), service
  yards (a block-wall dumpster bay, a transformer, pallets) and small lawns with a tree; every
  campus building gets an entry walk from its street face to the pavement, an apron at the door
  and shrubs either side. The hall's sixteen primitive ball trees are the chunk's street tree.
- **The freeway's right of way** (every district): the corridor lots' cells, not just the lots
  (the gaps between them were bare paving), in ivy that fades to compacted dirt in the deck's
  shade (per vertex, `BARE_FADE`); oleander hedge rows `HEDGE_OFFSET` beyond the deck edge and a
  tree row at `ROW_TREE_OFFSET`, off the ramps; shrub clumps further out; a 4.2 m split-face
  sound wall in 6 m panels between pilasters (creeping fig up its foot) on every cell edge that
  meets a house lot in the residential districts, chain-link on the street side and elsewhere;
  in 40 % of blocks a maintenance yard under the deck (gravel, k-rail, a container, a crew
  truck, a light). It replaces `_build_corridor_lot`'s ivy slab per lot (a ground-grid NODE, a
  draw each - block -6,0 had 21) and its eight-species shrub scatter.
- **MacArthur SE.** The empty block was a PLAZA roll south of the park's east half: 100 x 180 m
  of paving with one fountain and no beds (the beds' rule never fits that shape). A plaza rolled
  across the street from a landmark's site is buildings now (`CityPlan.block()`, after the roll,
  `"was_plaza"`), filled like the rest of midtown - Westlake is dense apartments and shops round
  the park, not a second square.

**Cost.** opengl3, 1280x720, `--quality=0`, noon, clear; before = the base commit (28105b5) from a
snapshot, after = this branch; each a live frame, so the traffic and the crowd differ by a few
cars and people between the two. `still_shot.gd` (the stills' own GEO line, free camera):

| Bookmark (`EYE`, y over the ground) | triangles before -> after | draws before -> after |
|---|---|---|
| Beach street `-652,2,95,70,-5` | 7,560,781 -> 7,678,515 (+1.6 %) | 2,670 -> 2,680 (+0.4 %) |
| Beach air `-610,110,210,35,-39.3` | 6,637,558 -> 6,906,284 (+4.0 %) | 6,176 -> 6,139 (-0.6 %) |
| Campus street `-545,2,-405,36.3,-3` | 9,270,150 -> 7,066,094 (-23.8 %) | 1,970 -> 1,971 |
| Campus air `-480,140,-330,37.9,-31.5` | 2,369,945 -> 2,456,929 (+3.7 %) | 1,645 -> 1,654 (+0.5 %) |
| Freeway street `-461,2,195,30.4,-3` | 8,599,037 -> 7,924,945 (-7.8 %) | 4,385 -> 4,362 (-0.5 %) |
| Freeway air `-420,100,220,35.3,-34.2` | 5,479,307 -> 5,556,345 (+1.4 %) | 5,093 -> 5,031 (-1.2 %) |
| MacArthur SE street `412,2,404,145.6,-3` | 5,107,407 -> 6,286,138 (+23.1 %) | 3,171 -> 3,784 (+19.3 %) |
| MacArthur SE air `560,160,700,31.3,-30.7` | 3,549,857 -> 3,690,498 (+4.0 %) | 2,538 -> 2,905 (+14.5 %) |

`tools/geo_count.gd` (the player standing there, `--spawn=x,z,yaw,pitch`, 90 frames after the
load, the player camera):

| Bookmark (`--spawn`) | triangles before -> after | draws before -> after | objects before -> after |
|---|---|---|---|
| Beach town `-648,60,140,-3` | 8,779,945 -> 8,855,948 (+0.9 %) | 3,706 -> 3,802 (+2.6 %) | 3,780 -> 3,881 (+2.7 %) |
| Campus `-545,-405,36.3,-3` | 10,083,563 -> 5,012,178 (-50.3 %) | 2,837 -> 2,856 (+0.7 %) | 2,855 -> 2,874 (+0.7 %) |
| Freeway side `-461,195,30.4,-3` | 9,025,099 -> 8,255,749 (-8.5 %) | 5,447 -> 5,408 (-0.7 %) | 5,564 -> 5,520 (-0.8 %) |
| MacArthur SE `412,404,145.6,-3` | 6,135,755 -> 7,032,002 (+14.6 %) | 4,595 -> 5,535 (+20.5 %) | 4,665 -> 5,592 (+19.9 %) |

The MacArthur "after" ran once main's shop interiors and hills were merged in; main itself (040beaf,
from a snapshot) measures 6,091,389 / 4,583 / 4,653 at the same spawn, within 1 % of the base, so
the rise is this branch's.

The stills render the same frame twice to the triangle (the after beach shots were rendered
twice, an hour apart: identical GEO lines), so these differences are the change, not noise.

The campus and freeway street frames got cheaper: the walks, car parks and the right of way's
cells keep the block lawn's blade grass off them (`_lot_rects`), and the corridor's ivy is now in
the yard mesh instead of a ground-grid node per lot. MacArthur's rise is new content - a block of
midtown buildings, forecourts and parked cars where there was one empty square - not the yards.
The yards themselves cost two draws a FULL chunk (the ground, the walls) plus the walls' shadow
casters, and their planting rides batches the chunk mostly has already.

**Traps.**
- Godot's front faces are clockwise to the viewer: a quad listed counter-clockwise from outside
  is laid 0-2-1, 0-3-2 (`_wall_tris`), and the ribbon tests the cross product's sign.
- Ground pieces must never overlap (identical surfaces at the same height z-fight once the
  variants differ): the campus entry walk stops where its apron starts, a pocket park's lawn is
  cut round its walk, the walk street's gardens run up to the path rather than under a strip.
- A beach block's twenty-odd yards dressed in one build step would be one long step: the walls,
  planting and props run through `CityChunk._run_or_defer()` in 2.5 ms slices before the finish
  (headless, a FULL beach block's build is ~0-75 ms longer with the yards, its slowest step the
  same as without; LOD +3-8 ms).
- The hedge took three passes: plain grass texture and flat lighting read as a painted green box,
  60 cm noise lumps and an 11 cm normal jitter as camouflage; it is fine leaves, faint lumps and a
  7 cm jitter now (in the last block shots, `hedge3*.png`; the city stills show the second).
- A patterned texture (brick, planks) must not go through `tiled()`'s rotated second sample: it
  crosses the courses with a diagonal hatch.
- A Godot `RandomNumberGenerator.randf_range(a, b)` with a > b still returns a value (between
  them): STEPPED's 15 m floor over the beach town's 12.5 m top gives 12.5-15 m.
- `as Array[Rect2]` on an array literal is not a safe way to make a typed argument; a typed local
  is (`_less()`, `_defer1()`).

**Tools and checks.** `tools/lot_coverage.gd` (`FILL=0|lot|1`, rows per district, FREEWAY,
ROW_CELLS, MACARTHUR_SE); `tools/glshot/block_shot.tscn` (a few FULL blocks alone, `EYE`,
`SHOTS`, `BLOCKS`, `GEO=1`, `YARD_FILL=0`); `still_shot.gd` `YARD_FILL=0` (the A/B; `SPLIT=1`
counts `YardGround` / `YardWalls` in the LotFill line). `tests/lot_fill_checks.gd` (25 checks in
the smoke test): bare share before and after round the bookmarks, the right of way out to its
cells, the shader kind tables, the campus plan, the MacArthur plaza, the beach plans (walk
streets, drives, house heights, no yard piece under a house or on another), one mesh each on the
right shader for a beach, a campus and a freeway block, the budgets, a LOD build with no yard
meshes, and a beach and a freeway block built with the fill off being the same block.

**Not done / not verified.** Looked at in opengl3 stills only (city `still_shot.gd`, `tools/glshot/block_shot.tscn`): the
walls, hedges, tile, decks, ivy and dirt on the Mac's Forward+ are not judged (the paint goes in
linear there, `PropFactory.has_reflections()`; the hedge's leaf normals and the concrete and
brick normal maps only show in real light).
- PLAZA blocks elsewhere (`_build_plaza` / `_furnish_plaza`) still read as big squares of paving
  from the air - the beach town has several; only the one beside MacArthur Park was turned into
  buildings. The suburbs (the plain block lawn, 82.5 % "bare" by the probe) and the industrial
  yards (39.7 %) were not in the brief.
- Sound walls run along the lot cells' edges (axis-aligned, stepping where the deck runs on a
  diagonal), not parallel to the deck; the ground is flat (no ivy berms, no embankment slopes).
  In the base stills the elevated deck's underside does not seem to draw from below (cars over a
  street look as if they float) - seen, not investigated, not touched.
- The beach houses are still `Building` boxes with flat roofs and the storefront band; no pitched
  roofs, garage doors where the drives end, porches or mailboxes. Pools are rare (3 in 735 lots:
  the back yards are shallow, as real beach-town lots are).
- Nobody walks the walk streets (the block's walkers keep to its pavement ring).
- The far tiers get the lawns and the ivy only; from 200 m up a beach-town block is pale
  concrete and paving between the roofs, which is roughly true.
- **Seen, not fixed (9ae's code, on main too):** a `--spawn` at the MacArthur SE bookmark builds
  downtown encampments inside `CityStreamer._ready()`. There `CampFigure.mesh_for()` cannot add
  its bake host to the root ("Parent node is busy setting up children"), `_bake()` then logs
  `is_inside_tree()` errors (13 in main's geo_count run, 17 in this branch's; the block itself
  is midtown and has no camp), and since the host stays valid but out of the tree it is never
  added again, so every later bake fails the same way and that session has no posed camp
  figures. Any `--spawn` with a camp in the first FULL ring does it; the default start (the
  origin) and the smoke test's spawn do not, or the check's `is_inside_tree` tripwire would
  fail. Fix there: re-add the host whenever it is not inside the tree, and when that fails
  (the root busy) return null without caching the key, so the loading screen's warm-up bakes it.

## 9ba. LA freeways as a 2026 game shows them, 2026-10-04 (agent branch `wt/freeway-kit`; VISUAL_ROADMAP #43)

The brief (lead, from the owner's "make the graphics a million times better"): make the decks
read like the 110 / 101 / 10 - overhead guide signs, Botts' dots and markers that glint in
headlights, worn paint and the carpool diamond, barriers with grime and scuffs, expansion
joints, scuppers with rust, pillar detail, light standards that light the deck, roadside
furniture, and the underside from the street. CLAUDE.md's Freeways bullet ("The freeway kit")
is the reference; this is the story.

**What was there.** Per 24 m segment: a flat deck top, an underside and two fascias as one
1.4 m slab, two box barriers, six painted strips (a yellow pair down the middle, white dashes),
square-ish columns (built as parallelograms off the world X axis, so a diagonal route's columns
were sheared), and every 340 m two posts, a beam and two blank green boards. No median barrier,
no lights, nothing on the shoulders. Traffic drove two lanes each way between dashes that did
not line up with it. (Main's e85f2c7, which landed while this was in flight, turned the old
underside and barriers to face the right way and squared the columns; the kit replaces all of
that code, so on the rebase its `_build_freeway()` / `_pillar()` / `_bar()` changes were dropped
in favour of FreewayKit. The bent-cap bug below was still there.)

**What it is now** (`scripts/world/freeway_kit.gd`, `shaders/freeway_structure.gdshader`,
`shaders/freeway_paint.gdshader`; `CityChunk._build_freeway()` keeps only the collision):
- Cross section: a box girder (fascia 0.55 m, cantilever soffit, inclined web, bottom slab at
  the old 1.4 m), New Jersey barriers 0.95 m at both edges (outer face flush with the fascia)
  and a double-sided one down the median. Board-formed soffit (plywood seams, tie holes, soot
  toward the edges, efflorescence at the segment joints), barrier joints every 6.1 m, grime at
  the foot, black tyre scuffs in runs along the faces the traffic sees, drip streaks, rust down
  the fascia under each scupper grate (every 12 m at the barrier toe; same phase in the shader).
- Lanes (`Freeway.lane_layout()`): four each way, 3.2-3.6 m, the inner one a carpool lane behind
  a double yellow with a diamond every 192 m; yellow left edge line with yellow markers, Botts'
  dots (four dots and a marker every 7.32 m) on the next line, a dashed stripe with a marker in
  each gap on the last (Caltrans's newer practice), white right edge line, all worn. An
  expansion joint (steel finger plate) across the deck every third bent. Traffic now drives
  `Freeway.lane_fraction()`: the cars sit in the painted lanes, four of them.
- Bents every 72 m: two 1.6 m columns square to the route (StreetWear's column tags follow),
  flared heads, a 1.6 m bent cap, five bearing pads, a downpipe, two under-deck lights and the
  pool each throws on the street below at night. Streaks run down the columns from the cap,
  splash dirt at the foot.
- Light standards on the median every 48 m: tapered pole, twin arms, cobra heads with a glowing
  drop lens, and a broad pool on each carriageway (`pool_material()`, light_pool.gdshader at a
  flat 0.75 falloff - at the city lamps' falloff a 34 m pool was a small hot spot that read as a
  headlight beam). Sodium amber on the 110, 101 and 10, LED white on the 405 and 105.
- Gantries every 340 m: laced box truss on laced posts, a catwalk with sign lights, and per
  carriageway a guide sign (route shield, direction, one or two destinations, a down arrow per
  lane) and, where an off-ramp lies within 1.5 km on that side, an exit sign (the street, 1/4 to
  1 MILE or a yellow EXIT ONLY band, the exit tab "EXIT 4B" - the number is the route's mile).
  The other carriageway, which only has on-ramps in this map, gets a second guide sign. Sign
  faces are lit at night by their sign lights and by headlights (retroreflective sheeting).
- At FULL chunks, on the shoulders: call boxes (yellow, a blue SOS plate) about every 500 m,
  CCTV poles about every 900 m, postmile paddles every ~170 m, tyre treads and the odd board.
- Off-ramps use the same slab, barrier and edge-line pieces (`ramp_piece()`).
- Retroreflection is the night look: markers, paint beads and sign sheeting light up in a cone
  ahead of the CAMERA (taken as the headlights) with `lamp_factor`, and a marker the cone
  reaches never draws under about a pixel, so a dashed line of glints runs on up the road.

**Names.** Shield numbers are this game's own (Coast 47, Century 58, Hollywood 21, Harbor 33,
Santa Monica 14; the check fails if one matches the real route), on an original crest shield.
Destinations are invented (`DESTINATIONS`), plus "Downtown" when the carriageway heads for it;
exit signs name the plan's streets (public names downtown, seeded ones elsewhere).

**Stills** (opengl3, 1280x720, `still_shot.gd`, one load, `--spawn=1989,160,-6,-3,12 --hour=13
--weather=clear --nohud`, `EYE=1989,12.0,160,-6,-3`, `SHOTS=` as in the shots branch README): on the 110
by downtown heading north at noon and 22:00; the guide signs at (1986.7, 55.6) from 26 m
(`1990,12.5,82,-6,10@13@40`); the southbound exit sign at noon and night
(`1980.5,12.1,27,174,10@13@45`, `@22@45`); the deck from 5th St (`2045,1.7,2,60,10`) at noon
and night. Before/after pairs on the `shots/freeway-kit` branch (README there).

**Cost.** `tools/geo_count.gd` (opengl3, 1280x720, `AB='Freeway*,Ramp*'`: the same frozen frame
counted with and without every freeway and ramp node), on the 110 by downtown
(`--spawn=1989,160,-6,-3,12 --weather=clear`), main 306274c against this branch rebased on it:

| | main: freeway nodes | branch: freeway nodes |
|---|---|---|
| 13:00 | 14,208 tris, 76 draws (59 nodes) | 28,249 tris, 49 draws (75 nodes) |
| 22:00 | 14,208 tris, 76 draws | 28,249 tris, 49 draws |

So +14k triangles on a 3.6 M frame (+0.4 %) and 27 FEWER draws: the old paint mesh cast
shadows (a StandardMaterial, opaque), the new paint and pool meshes do not. The whole frame
moved by the traffic's own noise (3.72 M / 3,168 draws on main, 3.63 M / 3,125 here, with
different cars). Per segment (the smoke check's own count over a chunk): a FULL deck chunk with a
gantry 955 triangles a segment (budget 1,400), an LOD one 271 (budget 420). The stills' GEO lines (the whole frame, traffic and people included, so a
few percent is noise), before -> after: drive noon 6.00 M / 3,168 draws -> 5.68 M / 3,103;
drive night 5.94 M / 3,154 -> 5.82 M / 3,103; guide sign 4.41 M / 1,707 -> 4.18 M / 1,620;
exit sign noon 3.86 M / 1,832 -> 3.73 M / 1,797; exit sign night 3.26 M / 1,443 -> 3.21 M /
1,426; under noon 5.58 M / 2,858 -> 5.59 M / 2,808.
The freeway bookmark (`--spawn=200,1088,-90,-4,30 --hour=13`, the 105 from the west, whole
frame, one count each): 3,461,955 tris / 3,321 draws on main, 3,474,657 / 3,325 here (+0.37 %,
+4 draws). Its AB pass (the frozen second count) did not finish inside geo_count's 15 minutes
on either side, nor did the 22:00 pair, so that bookmark has no freeway-only split.
ALU: the structure shader is one triplanar fetch (three taps) plus a few value noises, the paint
shader a handful of noises and one cone test; nothing runs per pixel that the old StandardMaterial
did not already pay for in texture fetches, except on sign faces and marker strips.

**Not done / not verified.**
- Forward+ (Mac): the sign wash (`sign_light`), the glint energy and the pool strength are tuned
  on opengl3 only; Forward+ lights the lit pieces in linear with auto exposure on top. Judge on
  the Mac at night on the 110 by downtown.
- The glint is lit from the camera, so walking on the deck at night the markers still glint;
  traffic's own headlights do not light them.
- No barrier collision (as before): the deck's one box per segment is all there is, so a car
  can still drive through a barrier. Adding it is a gameplay change for the owner to ask for.
- Pigeon spikes and soffit-mounted underpass fixtures (optional in the brief) are not modelled;
  the under-deck lights hang off the bent caps.
- The far city (Skyline) still draws the decks as plain boxes; no lights there at night.
- **Found on the way: every old bent cap stood in the wrong place.** The old `_pillar()` put its
  headstock at `Vector3(base.x, cap_y - 1.1, base.y)` - `base.y` is the ground height, so every
  cap in the city stood at z = ground - 1, in a row along z 0. From 5th St downtown they read as
  a staircase of floating beams over the street (the `under_noon_before` still). The kit's caps
  sit on their columns.
- The gantry chunk is the heavy one: lettering is most of its triangles (coarse curves,
  FULL only); the smoke check holds a FULL deck chunk to 1,400 triangles a segment and an LOD
  one to 420.
## 9bb. The airport as a major international field, 2026-10-04 (agent branch `wt/airport`; VISUAL_ROADMAP #44)

The brief (lead, from the owner's "make the graphics a million times better" and "commercial jets
taking off and landing at LAX"): the airport as a 2026 game shows one, from the ground and from
the air - terminals, airside clutter, the field's lights at night, landside. Everything original
(invented airlines and names), a big field's real FORMS. CLAUDE.md's "Airport" note is the
reference; this is the story.

**What was there.** One 740 x 390 m slab of road-shader asphalt at a tint of 1.25 (from the air a
pale grey sheet), three 55 m "runways" as flat-colour boxes 2 cm proud of it that barely showed,
a box hall with ribbon windows, a cylinder tower, a saucer on four sticks behind the hall, four
grey boxes for jet bridges with nothing docked, three flyable jets parked sideways, three street
lamps, hangars - and nothing at night: the whole field was black from the air.

**What it is now** (three files; layout, buildings, hardware):
- **Layout** (`Airport`, everything from MacroMap's numbers): the runways are the parallel pair
  27R (z 870) and 27L (z 955, moved from 960 so its south edge lights stand inside the fence),
  45 m wide; the old third runway at z 780, which nothing flew from, is the parallel taxiway
  (`MacroMap.taxiway_z`); `departure_runway` names 27R (AirTraffic read `zs[1]`). Three cross
  taxiways (`CONNECTOR_XS`), infield grass between (lawn shader, very dry), concrete apron. The
  concourse is an arc convex to the apron (`ARC_CENTRE` (-350, -330), radius 1030 m to its centre
  line, x -575 .. -125) with nine gates 46 m apart (stands 11-19; 17 empty, its bridge parked back).
- **Ground** is a PARTITION (`Airport.ground_pieces()`): every feature edge cuts the chunk into a
  grid, each cell takes the highest feature, runs merge into strips. The first pass laid runways
  ON an apron slab, 3 cm apart, and from 300 m up every runway was grey streaks (the depth
  buffer's step there is tens of centimetres: measured, see the top-down still in the shots).
  Runway paint at LOD is lifted 3 cm for the same reason.
- **Buildings** (`AirportTerminal`, landmarks, far copies kept): the head house - a glazed hall
  whose roof rises off the airside and sweeps out over the drop-off lanes like a wing on
  branching tree columns standing on the curb, a slatted soffit lit at night, the name on the
  fascia, lit DEPARTURES boards on the trunks; the two concourse halves (service level, glazed
  departures level with curtain_glass's lit interior, steel fins every 9 m and a louvre band,
  a clerestory, the gate numbers lit); a jet bridge at every gate (rotunda, two telescoping
  sections sloping down to the cab at the forward-left door, drive column and bogie); the parked
  airliners as ONE MultiMesh of the airliner model on `airliner_livery.gdshader`; the control
  tower (ribbed shaft, lit glass cab with consoles, rotating beacon); the "skyhook" - two
  parabolic arches crossing over a lit glass disc restaurant, floodlit, on a palm-ringed plaza
  (the saucer's idea done properly); the multi-storey car park and the rental lot (ArenaGrounds).
- **Liveries**: the Meshy airliner texture reads as camouflage, so the livery shader ignores it
  and paints by region in the model's own units (white top, belly, cheatline, a window row each
  side, doors, cockpit glazing, the fin and its mark, nacelles, grey wings) - six invented
  airlines. The air traffic's airliners and the flyable one wear them too.
- **Airside** (`AirportKit`, code-built, real sizes, one shader): pushback, belt loader, baggage
  tug and its carts, catering truck with its box lifted to the rear door, fuel truck, GPU,
  cones, at every attended gate (`gates()[i].service` picks the trucks), staging rows at the
  concourse ends, 2-3 `ApronCrew` in hi-vis per gate; floodlight masts with night pools; the
  perimeter fence with barbed outriggers and the airside line either side of the terminal; blast
  fences at the runway ends, the localizer array, the glide-slope mast, windsocks, the PAPI.
  Paint: thresholds, designators, touchdown zones, aiming points, centre and edge lines, rubber;
  taxiway centre / edge lines, lead-off curves, hold-short bars; lead-in lines, stop bars, stand
  numbers, red restraint envelopes, the service road.
- **Night**: ~640 field lights in ONE billboard mesh on aircraft_lights.gdshader (new kinds:
  field light, the approach lights' rabbit, rotating beacon, PAPI whose colour is the eye's angle).
- **Found on the way, game-wide**: every "all-round" billboard light faced NORTH. The aircraft
  lights shader read "zero normal = all round", but Godot cannot store a zero normal (a probe:
  `SurfaceTool.set_normal(Vector3.ZERO)` comes back (0, 0, -1)), so nav lights, strobes and every
  downtown tower's obstruction lights showed at full only from the north and at 6 % elsewhere. An
  aimed light now adds 100 to its UV2.y code (AmbientCraft, Airport); all-round lights leave it.
  Also: AIR=final stills fade the staged jet in at once (`AirTraffic._shown()`), and the still's
  AIR line prints world positions.

**Stills** (shots/airport branch; same cameras before and after, opengl3, 1600 x 900):
the apron at noon `EYE=-360,1.7,762,42,4`; the terminal from the drop-off
`-330,1.7,606,195,12`; the aerial `-260,330,1230,8,-36`; night with an airliner on final
`EYE=1100,200,1250,71,-8 AIR=final AIR_DIST=480 --hour=22 FOV=50`; and two more at night: short
final over the approach lights `EYE=420,160,1120,70,-14 AIR=final AIR_DIST=200 FOV=55`, the apron
from over the taxiway `EYE=-262,40,812,42,-17`.

**Frame cost** (still_shot.gd GEO on opengl3 1600 x 900, the same frames on main 96f86f1 and
this branch; triangles / draw calls, camera + shadow passes):

| View | main | wt/airport | change |
|---|---|---|---|
| apron at noon, standing | 1.853 M / 1,706 | 2.032 M / 1,766 | +9.7 % / +3.5 % |
| terminal from the drop-off | 3.032 M / 855 | 3.180 M / 972 | +4.9 % / +13.7 % |
| aerial over the field | 1.346 M / 856 | 1.404 M / 943 | +4.3 % / +10.2 % |
| night, airliner on final (1.4 km) | 0.905 M / 285 | 0.919 M / 310 | +1.5 % / +8.8 % |
| apron at night from 40 m | 1.739 M / 1,509 | 1.874 M / 1,593 | +7.8 % / +5.6 % |
| night, short final (close) | 1.421 M / 1,081 | 1.473 M / 1,143 | +3.7 % / +5.7 % |

A gate's trucks are one instance of one mesh per service variant and a chunk's painted texts one
mesh per colour (the first pass was eight batches and a dozen TextMesh nodes a chunk: the
drop-off view was +22 % draws). The field's ~640 lights are one draw. The parked airliners are
one MultiMesh per concourse half (8k-triangle model with its imported LODs).

**Checks**: `tests/airport_checks.gd` (layout, flyable jets' clearances, painted runway under the
touchdown, the lights mesh and its kinds, far copies and parked jets, a FULL chunk's paint and
trucks, the crew); smoke test's airport chunk check reads the ground partition; distance checks
pick a field block no cross taxiway cuts.

**Not done / open**: no taxiing jets or pushbacks in motion (the parked jets are static meshes;
the flyable ones are where they were, on the taxiway and the remote stands); no cargo apron;
gate signs and the terminal name are TextMesh (a draw each, detailed only); the concourse
interior is curtain_glass's generic trace (no gate lounges); the arrival jet's approach path is
lifted to ~60 m over the city by the clearance field, higher than a 3 degree slope near the
fence. NEEDS MAC CHECK: the glass interiors' exposure, the livery shader on Forward+, the field
lights' size and glow under AgX and auto exposure (all judged on opengl3 only).
## 9bc. Crowd life: people who do things, 2026-10-04 (agent branch `wt/crowd-life`; GAME_PLAN G5)

The brief (lead, from the owner's "make the graphics a million times better"): make the street
feel inhabited the way RDR2 / GTA V does - pairs and threes talking, people on the phone,
waiting at the crossing, sitting on benches, leaning on walls and smoking, window shopping,
coffee and bags, joggers on the beach paths and dog walkers. CLAUDE.md's "Crowd life" note is
the reference; this is the story.

**The clips.** Quaternius' Universal Animation Library 1 and 2 (CC0, the free Standard files,
`tools/crowd/fetch_life_clips.sh`; itch.io's free download is a CSRF-token POST, scripted there)
give 14 we use: Idle_Loop, Idle_Talking_Loop, the three sitting clips and Sitting_Exit,
Jog_Fwd_Loop, Idle_Torch_Loop (only to have it: the cup is now aimed, see below),
Idle_TalkingPhone_Loop, Idle_FoldArms_Loop, Consume (a sip, a drag), Yes (a nod), Idle_No_Loop,
Idle_Rail_Loop (kept for a railing lean; not used yet). No smoking or wall-lean clip exists in
either free library: a smoker stands or leans with the idle and takes the Consume clip to the
mouth; a wall-leaner folds their arms with their back 30 cm off the wall. `life_clips.gd`
retargets them **in Godot** onto all twelve rigs (two seconds a rig): Blender's glTF import
re-orients bones (its bone heuristic), so a clip exported from that skeleton is keyed against
other bone frames than the ones the game imported. The method is retarget_lib's world delta
(`R = D * arc(target rest dir -> source rest dir) * target rest`, parent-first), so the
library's T-pose rest and the crowd's lowered-arm bind never need to agree - every retargeted
bone direction matched the source to the hundredth (DEBUG=1 prints them). Then two fixes and
compression:
- the jog is authored at ~5.7 m/s (a 2.6 m step): under a 3 m/s jogger its legs turned over in
  slow motion. Each leg bone's rotation is scaled 0.55 about its clip mean: ~3.0 m/s now
  (`clip_probe.tscn CLIPS=life/jog`, 2.3-3.7 per foot over the rigs).
- the library stands every idle wide, knees bent, one foot forward - a game hero's ready stance;
  on a pavement every idler looked about to fight. The legs of the standing clips are settled
  60 % toward the rig's own stance (retarget_lib's `settle_legs` idea).
- `Animation.compress()`: 6.2 -> 2.0 MB of clips in memory for twelve rigs, 200 -> 55 KB a file.

**The behaviour** (`Pedestrian` "Life" section, `CrowdLife` for the shared data): who stops, for
what, how long, is all rolled per person (`hash([seed, "life"])`). Near the player (60 m) at the
end of a walk (`life_chance` 0.32) or as soon as they appear (`life_spawn_chance` 0.5: a street
you fly into is already busy), a person TALKs (recruits one or two free walkers on the same
ring within 14 m into a circle; the speaker is worked out from the clock so the group needs no
leader; listeners nod and look at the speaker), STANDs (phone clip on a call, the TEXT arms
with the head down, a coffee with sips, idle / folded arms), SITs (the chunk's benches and the
bus-stop benches register two places each, `CrowdLife.add_seat()`), LEANs or looks in a
WINDOW (one world-layer ray to the buildings; no wall, no lean). At the crossing, waiting
people play the same standing clips. What a walker carries is laid over the walk (a frame of
the phone clip at the ear; a frame of the talk clip for texting; the coffee forearm aimed
forward at the waist; a bag held plumb) with a prop in the hand. Joggers (14 % in the suburbs,
beach town and on the Esplanade, 3 % elsewhere) jog at any range; dog walkers (12 % / 3 %) walk
a Shiba Inu (Quaternius' Ultimate Animated Animals, CC0) on a red lead to the left hand and stop
now and then while it sniffs. Panic (`_scare()`) ends every stop at once; out of range a stop
just ends. Officers and rough sleepers are untouched (`_lives()`).

**Traps, each cost a round:**
- All life timing is the physics clock (`_life_now_ms()`): on the real clock the 4 s
  "just appeared" window expired during a slow software render and no still ever showed
  anyone doing anything (it also keeps the weapon wheel's slow motion honest).
- A bench is 0.45 m; the clip's chair puts adult hips 10-20 cm higher (and a child's lower).
  `_sit_pose()` moves the hips onto the bench and re-solves each leg (two-bone, in the plane
  the clip bent the knee in) so the feet stay where the clip planted them. Checked: hips 0.56 m
  over the pavement, toe 4 cm.
- The props are built in a GRIP frame (x thumb, y fingers, z out of the palm) measured on the
  rigs' rest pose (identical on all twelve to a hundredth): built in the bone frame directly,
  the phone stood past the fingertips and the bag hung upward from the fist.
- `fix_arm_pose()` rebuilds the arms of every clip in the player it is given: the life library
  must be added after it (it is: `_setup_life()` runs after `_add_model()`).
- The smoke test's outfit tally read `cloth_hue` off every ShaderMaterial on a pedestrian: the
  props' material has none (it is skipped now).

**Cost.** CPU, `crowd_lab.tscn MODE=bench` (ms per physics tick per 100 people, three runs,
median; the bench's people all appear at once, so half start a stop): near 6.05 -> 5.48
(people stopped skip move_and_slide), 50 m 1.84 -> 2.39 (carry overlays and sitters' leg
solves; the life range is 60 m), 100 m 1.17 -> 1.28, 200 m 0.75 -> 0.77. Memory: +2.0 MB of
clips, +1.3 MB the dog. Frame (`still_shot.gd` GEO, opengl3 1280x720, the same EYE
with `CROWD_LIFE=0` and without): the avenue's east pavement 7,755,044 -> 7,783,186 tris
(+0.4 %), 3,625 -> 3,638 draws; the west pavement 4,202,917 -> 4,306,147 (+2.5 %), 1,719 -> 1,732
(more people stand inside the shadow range at once); the plaza bench 4,855,309 -> 4,896,898
(+0.9 %), 1,992 -> 1,997; the Esplanade bookmark identical (2,585,908 / 1,709). A prop is one
draw, unshadowed, culled past 60 m; a dog ~4k triangles and a skeleton of 46 bones.

**Where to look in the game (motion is the point; stills cannot show it):**
- Downtown, the avenue under the towers (Flower at Olympic; desktop `-- --spawn=2359.4,880,0,12,2`):
  walk the east pavement north from the corner - talking groups, people on the phone, a
  smoker taking drags (an ember after dark), coffee carriers; the west pavement has pairs under
  the street trees and a bench by the bus stop with people sitting down and getting up.
- Any bus stop: people sit on its bench, a pair on one bench sometimes talk (sit_talk).
- The Esplanade (beach path south of the piers; `-- --spawn=-441.7,3534.6,-178,-1.5`): joggers
  and dog walkers along the ocean-side walkway; the suburbs and beach town blocks have them too.
- Any signalised crossing: the people waiting shift their weight, fold their arms, check phones.
- Fire a shot: every group, sitter and leaner bolts at once.

**Not done / next:** no wall-lean or smoking clip exists in the free CC0 libraries (folded arms
and the Consume clip stand in); Idle_Rail_Loop is in the library unused (the Esplanade's railing
would suit it); props are dropped, not thrown, when someone is knocked down (they vanish with the
walker); sitting is benches only (low walls and planters are not registered as seats); the dog is
the pack's low-poly Shiba, flat-shaded, and walks through people; the lead is a straight
cylinder. Stills: `shots/crowd-life` (README lists them). The lead in a dog walker's hand only draws
within the 26 m look range, which a frozen still does not refresh after `LIFE_FOCUS` moves the
camera: the dog still has no lead in F_dog. `still_shot.gd` gained `LIFE_REPORT=1` (who is
doing what near the camera, true world positions) and `LIFE_FOCUS=jog|dog|talk|sit|...` (frames
the nearest such person).

**At merge (lead):** dog walkers are switched OFF (`Pedestrian.dog_share` = 0; the roll is
still made, so no other person changes). The Shiba is the pack's low-poly flat-shaded model and
the owner's rule is realistic, high-poly; dog walkers come back with a realistic dog (Blender-
built like the hero, or a CC0 scan), `CrowdDog.MODEL` swapped and `dog_share` back to (0.12, 0.03).


## 9bd. The far city's buildings: coded copies of the near ones, 2026-10-04 (agent branch; GAME_PLAN G7, VISUAL_ROADMAP #46)

G7's last open item was "real impostors for the far city's towers instead of shaded boxes". Every
building past the FULL ring (the LOD chunks, and the far city, which captures their build) was its
parts as boxes on `building_lod.gdshader`, which GUESSED the facade: typology from the facade
colour, its own window grid, its own lit-window hash, its own roof roll. So at the LOD line
(200 m) a building kept its massing and changed in almost everything else - another window grid,
other offices lit at night, a white roof turning black, a light panel building classed as stone,
a stucco block with a curtain grid drawn as punched stone - and on the Mac every far wall was
brighter than the near one (the near wall is the facade times its photographed texture; the far
one was the bare facade: plaster about 2x, the metal sets about 12x).

**Why not baked impostors.** The far city holds 22,472 facade parts (census below), all unique.
An octahedral set of 8 x 8 views at 64 px a building is ~63 GB of atlas, a 16-view 32 px card set
~3.9 GB, and either needs every near building generated and rendered at load (at the ~10 ms a
near building takes, a quarter of an hour). A far building IS a box - its silhouette is its
parts - so the win is the box drawn from the near building's own data: still 12 triangles, no
texture memory, the real sun, the per-block dissolve and the capture untouched. Impostors stay
where a box cannot carry the detail (trees, landmark crowns), which have their own far meshes.

**What it is now** (rules in CLAUDE.md, "Far buildings are coded copies of the near ones"):
- `FarBuilding.boxes()` (`scripts/world/far_building.gd`) turns a planned Building into its far
  boxes: each part one box whose basis carries six 20-bit codes in its off-diagonals - seed,
  finish, window style, roof covering, wall texture set, glass tint / lit colour / frame paint
  palette indices, crown shade, warehouse, storefront, parking deck, cut corners, crown, shop
  runs per face, bays per wall, storeys, base course, lit ratio, tall-tower lobby, plinth depth,
  parapet rise - then its roof plant, one box a unit. The plinth (one instance a building) is
  folded into the parts on the ground; the parapet's height is on top of the part.
- `Building.part_grid()` is the near walls' own grid (rows, bays, storefront, cut corners, base
  course, crown) and both use it; `Building.parapet_rise()`, `crown_shade()`, `base_color()`.
- The roof plant rolls on its own stream (`_roof_rng`, from the seed): it was the last thing on
  `_rng`, after the facade details' per-bay balcony rolls, so nothing short of building the facade
  could say what stood on a roof. `Building.roof_plan()` replays the layout without a node
  (0.13 ms a building after `_rect_free` stopped rebuilding the taller parts' footprints on every
  try). The near roofs got a new random arrangement once; the kit on/off check still holds.
- Lit offices and pale/dark spandrels roll from integers in `shaders/window_lights.gdshaderinc`,
  included by both building shaders (they were float hashes of different inputs). The near
  office pattern changed once (a new roll); the far one is now the same pattern.
- `building_lod.gdshader`'s coded branch draws the near wall cell for cell: the near `u` per face,
  bays and storeys from the code, the four window masks, curtain transoms and spandrels, punched
  reveals, shops with door bays, shop frames, sign bands (lightboxes or lit letters after dark),
  bulkheads, shutters, lobbies, parking decks open between spandrels with their lamps, base
  course, crown, grime, the wall texture's measured mean (`wall_tex_mean()`), cut-corner piers,
  the plinth's concrete, the parapet band; roofs in the near covering with its parapet ring; glass
  mirroring what the near glass mirrors (its default sky, the fake city opposite, the street - the
  far path's bare sky gradient drew panes 2-5x brighter); frames as antialiased coverage at least
  half a pixel wide near the handoff. Past a few pixels a cell goes to its own average, albedo and
  lit-office share, so a far tower at night glows with its lit fraction instead of sparkling.
- The LOD chunks build every roof unit; Skyline keeps `FarBuilding.SILHOUETTE` (stair bulkheads,
  water tanks, cooling towers, billboards, spires and antennas with their red beacons - masts at
  least `mast_min_px` wide, never wider than `mast_max_width`) and prints the small plant
  (`print_small_plant`, on its own material instance: `PropFactory.building_lod_material(true)`).
- The old path stays for what is not a Building (replica houses, estates, slabs, plates, decks).
- `FarBuilding.enabled` (`FAR_CODED=0` in the environment turns it off) is the A/B on one tree.

**The code is exact on both renderers.** Compatibility packs INSTANCE_CUSTOM and COLOR into half
floats, so the code rides in the transform. Probe (`<scratchpad>/impostors/probe/shear_probe.gd`):
548 instances, six codes each up to 2^20 - 1 as code * 2^-28, under a node offset like Skyline's,
the shader green where all six decode right: opengl3 183,790 green px and 0 red; lavapipe
Forward+ 183,790 green and 0 red. `tests/far_city_checks.gd` checks the round trip in GDScript.

**Near against far, the same buildings at 200 m** (`tools/glshot/far_building_shot.gd` + `far_pair.py`,
six seeded buildings - stucco, brick, panel and three glass towers on podium lots - from one
camera, luminance of each building far / near; `<scratchpad>/impostors/pair/`):

| Pass | opengl3 day | opengl3 night | Forward+ day | Forward+ night |
|---|---|---|---|---|
| first coded version (p1) | mean 1.04 (0.65-1.25), but panes 28-77 /255 against 5-16 | 6.18 (4.4-8.6) | - | - |
| final (p5 opengl3, v5 Forward+) | 0.88 / 1.07 / 0.71 / 1.10 / 1.00 / 0.56, mean 0.89 | 0.85 / 0.89 / 0.88 / 0.54 / 1.04 / 0.73, mean 0.82 | 0.88 / 0.91 / 0.84 / 1.18 / 1.11 / 0.82, mean 0.96 | 1.26 / 1.40 / 1.15 / 0.97 / 1.18 / 1.03, mean 1.16 |

(buildings in order: stucco setback, brick, panel-on-podium glass, dark glass tower on a podium,
pale curtain setback, dark curtain tower). Mean absolute difference per pixel went from 24-38 to
16-30 /255 by day, and the share of pixels more than 24/255 off from 36-70 % to 14-47 %; what is
left is pattern (the near fins, frame quads and traced rooms), not level. On the way: the far
glass mirrored a bare sky gradient (panes 2-5x the near), the far lit offices were at the flat
tile's old 1.9 (4-9x the near traced rooms), the far walls took no wall texture mean, the far
shop frames fell through to the wall finish (black on glass buildings), the curtain mullions
aliased away; each fixed and measured again (`p1`..`p5`, `v3`, `v5` in the pair folder).

The lit offices are the same windows near and far, every one (`p3_n1_crop.png`, `v3_n1_crop.png`).
What the far copy still does not have: the near glass towers' fins and frame quads (rolled on
`_rng` in the facade details, so not in the code), which leave the two dark curtain towers
0.56-0.71 of the near on opengl3 and ~0.82-0.86 on Forward+; cut-corner GEOMETRY (the cut bay
is drawn as the pier, but the box's corner is square); balconies, fire escapes, awnings, the
facade kit (all under a few pixels past 200 m).

**Cost.** Draws: no new MultiMesh anywhere (the plant rides in each chunk's `lod_box` batch and in
the far city's tile MultiMesh). Instances and build (`tools/far_census.gd`, headless, process CPU
time, whole basin from (1900, 500), FAR_CODED 0 / 1):

| | old boxes | coded |
|---|---|---|
| far city boxes (7 km) | 54,933 = 22,472 facades + 28,093 plain + 3,387 plates + 981 decks | 49,347 = 22,472 coded parts + 13,428 plain + 9,079 silhouette units + plates + decks |
| far city box triangles (all drawn) | 659,196 | 592,164 (-10 %) |
| LOD ring, 225 blocks round the eye | 3,603 instances (43k tris) | 14,540 (174k tris): 2,419 parts, 1,482 silhouette units, 10,639 small units |
| far city build at load, CPU | 44.2 s | 49.7 s (+12 %; FarBuilding.boxes() 0.22 ms a building) |
| LOD block build, CPU (225 blocks) | 1.1 s | 1.9-2.4 s (+4-6 ms a block, spread over its lot steps) |
| static memory after the far city | 58 MB | 58 MB; GPU instance buffers 4.4 -> 3.9 MB (80 B an instance on Forward+) |

geo_count (opengl3 800x600, `--hour=14 --weather=clear --quality=0`, before = this tree with
FAR_CODED=0, so main's merges are on both sides):

| View | before (FAR_CODED=0) | after | change |
|---|---|---|---|
| aerial `--spawn=700,-300,0,-14,500` | 6,280,170 tris / 4,339 draws / 4,392 objects | 6,288,078 / 4,339 / 4,392 | +0.13 % tris, same draws |
| SW skyline `--spawn=1450,2150,-38,4,140` | 7,283,742 / 5,834 / 5,884 | 7,296,702 / 5,834 / 5,884 | +0.18 % tris, same draws |
| street, the x 1589.6 avenue north `--spawn=1589.6,2232,0,3` | 6,791,287 / 4,360 / 4,394 | 6,799,795 / 4,360 / 4,394 | +0.13 % tris, same draws |

The same frames through `still_shot.gd` (EYE cameras, GEO lines in `*_stills.log`): aerial
1,494,592 -> 1,474,804 tris (352 -> 353 draws), SW 3,793,235 -> 3,802,271 (2,133 both, shadow
996,723 -> 1,009,287), SW night 3,566,913 -> 3,572,385 (1,874 both), street 8,301,020 ->
8,320,208 (4,148 both), street night 8,714,279 -> 8,731,583 (4,501 both). The LOD ring's roof
units cast with the rest of its batch: about +13k shadow triangles at the SW view.

Stills (opengl3 960x540, `DIFF=1`, 14:00 and 21:00, one load each, `<scratchpad>/impostors/shots/`,
`pair_<view>.png` is before | after): before = `beforeab_aerial_day{,_1.._5}.png` (this tree, FAR_CODED=0), after =
`after2_aerial_day{,_1.._5}.png`, in order aerial 14:00 / 21:00, SW 14:00 / 21:00, street 14:00 /
21:00; `pair_<view>.png` side by side, `stack_<view>.png` stacked. Grey p1/p5/p50/p95/p99, before
-> after (and the share of pixels that moved more than 8/255):

| Still | before | after | moved |
|---|---|---|---|
| aerial day | 72/99/158/186/209 | 72/96/157/180/204 | 10.7 % |
| aerial night | 9/15/28/92/147 | 9/15/27/80/129 | 10.2 % |
| SW day | 48/74/156/200/212 | 48/72/153/188/209 | 15.6 % |
| SW night | 8/11/28/133/213 | 8/11/28/103/151 | 14.9 % |
| street day | 20/34/140/180/203 | 20/34/140/180/202 | 0.5 % |
| street night | 7/9/37/98/160 | 7/9/37/98/159 | 0.5 % |

What they show: the LOD and far blocks lose their pastel, too-bright walls (the old boxes skipped
the near walls' texture mean, so a LOD block beside a FULL one was visibly whiter) and take the
near buildings' tones, roofs and roof plant; the skyline gets its real masts and spires; at night
the far city drops to the near rooms' level (the old far boxes lit their windows about five times
brighter than the near buildings - in the before frame the LOD towers out-glow the FULL ones in
front of them), so the far skyline at night is darker and calmer than it was. That is the match
the task asked for; if the owner wants the old sparkle back it is one knob, `lit_room_level`
in building_lod.gdshader, at the price of the far towers outshining the near ones. At street
level the far city is mostly hidden: 0.5 % of pixels move.

**Traps found.**
- A shader parameter may not share a uniform's name: building.gdshader has `seed` and
  `lit_ratio`, and the include's parameters of those names failed its compile. Headless DOES
  parse shaders and prints `SHADER ERROR` (`tools/shader_check.gd`, ten seconds); only GPU-side
  GLSL errors need a renderer.
- `VIEWPORT_SIZE` read 0 in the far shader's vertex stage in the city: the first mast widening
  divided by it and drew every antenna a kilometre out a kilometre and a half wide. The pair scene
  never showed it.
- The near wall is facade x texture x 1.3 (Building.WALL_TEXTURE_MEAN is NOT divided out by the
  building shader, whatever its comment says): anything that must match a near wall's average
  multiplies by the set's mean in the renderer's space.
- A `--script` tool that names Building, CityPlan or Skyline fails to compile before the autoloads
  exist and then HANGS; `tools/far_census.gd` loads its body at run time.
- procfs files report a size of 0: `FileAccess.get_as_text()` reads nothing, `get_line()` works.

**Not verified.**
- The Mac. Forward+ was proven in the small pair scene only (lavapipe cannot hold the city); the
  city stills are opengl3. Ask for a Mac shot from the SW view (`--spawn=1450,2150,-38,4,140`) by
  day and at 21:00, and one from the air (`--spawn=700,-300,0,-14,500`), with F1 FULL.
- The silhouette plant and beacons in motion (a mast's least width flickers as it crosses a pixel
  boundary on Compatibility; TAA settles it on Forward+).
- Shadow cost of the LOD ring's roof units: they cast with the rest of the `lod_box` batch; the
  geo_count shadow lines above are what it costs at these three views.
## 9be. Houses in the suburbs and the beach town, 2026-10-04 (agent branch `wt/houses`; VISUAL_ROADMAP #47)

The brief: every house lot in SUBURBS and BEACHTOWN was a flat-roofed `Building` box with a
storefront band (9az's "not done"), and the suburbs were 82 % bare lawn by `tools/lot_coverage.gd`
- from the street and from the air the least real part of the city. Make them read as Los Angeles
neighbourhoods: real house geometry in the styles LA has, yards like 9az's in the suburbs too, a
cheap pitched-roof version for the LOD chunks and the far city.

**What it does** (rules in CLAUDE.md, "Nor are the houses boxes", after the YardFill paragraph):
- `HouseKit` (`scripts/world/house_kit.gd`) plans a house per lot, PURE (hashes of the seed and
  the lot; the chunk's and the block's rngs untouched), in the lot's yard frame (u along the street,
  v back from the front edge; `YardFill.lot_front()` says which way it faces: the nearest street,
  or the walk street). Six types, odds per district:
  - **Ranch**: one long storey, hipped (60 %) or gabled shingle roof (clay on a fifth) with deep
    eaves, a two- or one-car garage wing at one end (a little forward on some), a front-gabled
    wing on the other end on 45 %, stucco or lap siding / board and batten, a shed porch or a stoop,
    a brick chimney on half, vents, solar panels on 30 %.
  - **Spanish revival**: white stucco, a low clay roof with short eaves, a front-gabled wing with an
    arched picture window, an arched front door with a fanlight, a stucco chimney with a tiled hood;
    one storey, two on the taller lots.
  - **Craftsman bungalow**: front-gabled, narrow and deep, lap siding (board and batten on a
    quarter) in sage / slate / olive / brown / mustard with cream trim, rafter tails under 0.75-0.95
    m eaves, a porch across the front under its own gable on tapered columns standing on brick
    piers, gridded upper sashes, gable vents, a drive down the side to the back yard.
  - **Mid-century**: a flat roof on a 1.0-1.5 m overhang or a butterfly roof, a clerestory band on
    the street face and a wall of glass at the back, a carport on steel posts (45 %) or a garage in
    stained vertical boards, a bright front door under a flat canopy, a breeze-block screen beside
    the entry on 55 %.
  - **Stucco box**: two storeys (three by the beach on the taller lots), the garage in the front
    face, a hipped clay or shingle roof or a flat one behind a coped parapet, an iron balcony over
    the door with a slider onto it.
  - **Dingbat** (the beach town only): two or three storeys over open tuck-under carport bays, a
    lobby door at one end, a flat roof behind a parapet.
- **The cells the lot grid left empty** get a house each (`HouseKit.extra_lots()`): CityPlan's lot
  walk rolls a gap per cell and drops any cell it leaves under 6 m, which in the suburbs (14 m gaps
  on 14-22 m cells) was two cells in five - the green squares between the boxes in every aerial.
  Hash-seeded after every rolled lot, so nothing the plan decides moves; never on a landmark's
  square, the approach clear zone or the right of way. Suburban lots 2,984 -> 4,308 basin-wide.
- `HouseBuild` (`scripts/world/house_build.gd`) builds it: walls cut round every opening on a cell
  grid (ReplicaHouses' method) with reveals, framed glass on `house_glass.gdshader` (lit at night),
  sills, muntins, the craftsman's casings; arches fill their spandrels and the reveal follows the
  curve; sectional garage doors with raised panels (a row of lights on a craftsman's or a Spanish
  house's); doors with panels, a knob and a wall lamp; hip, gable (gable-end walls in the wing's
  cladding, barge boards, a louvred vent), flat-with-parapet, deck and butterfly roofs; porches,
  stoops, canopies; chimneys; pipe and box vents; solar racks on the roof face that looks most to
  the south, standing off it on a frame; balconies. New shaders: `house_shingle.gdshader` (courses
  of three-tab or laminated shingles, a shadow line under every butt, granules, streaks),
  `house_siding.gdshader` (lap / board and batten / stained tongue and groove), and
  `house_breeze.gdshader` (the breeze-block screen, cut out per pixel, dithered to its share far
  off). All colour work through `color_space.gdshaderinc`.
- **One mesh per material per FULL chunk** (13 names at most), collision on one `Houses` body,
  each house's wings in the occluder. A suburban FULL block is ~19-22 k triangles of houses
  (26-32 houses), 4-7 ms of GDScript a house in its lot step, the commit 2-7 ms (26 cold, the
  materials' first load): `_tri()` writes each triangle's normal and tangent itself because
  `generate_normals()` / `generate_tangents()` over the chunk cost 10-30 ms in one step.
- **LOD chunks and the far city**: a `lod_box` per wing plus, for a pitched wing, two tilted roof
  slabs in the roof colour and a gable prism in the wall colour (CLAUDE.md has the two traps), so
  Skyline draws the roofscape with no code of its own.
- **YardFill fills the suburbs** (`YardFill.SUBURB` odds on the beach plan): driveways to the garage
  doors, front walks to the porches, mostly open front lawns (the block's own lawn and its blades;
  lawn pieces are not laid there), drought gardens, beds along the house fronts, block-wall or
  timber fences, back lawns with pools on half the deep ones (on a concrete apron), trees, palms,
  bins, cars in the drives. The yard reads the house: its facing, the drive's span and end (the
  garage door), the front door. The walk street is worked out from the lot rects now
  (`YardFill.walk_for()`), so a house knows it fronts one before the block step runs.

**Coverage** (`tools/lot_coverage.gd`, whole basin `RECT=-3000,-3000,8000,8000`, seed 1337;
before = main c848ad4, after = this branch):

| Row | bare before -> after | built before -> after | lots before -> after |
|---|---|---|---|
| Suburbs (330 blocks) | 82.5 % -> 4.6 % | 15.6 % -> 33.2 % | 2,984 -> 4,308 |
| Beach town (71 blocks) | 3.7 % -> 3.8 % | 38.3 % -> 32.5 % | 865 -> 865 |

(The beach town's yards were already filled by 9az; its houses are a little smaller than the boxes
were, and the difference is garden.) Types basin-wide: suburbs ranch 1,420, Spanish 898, stucco box
651, craftsman 646, mid-century 508; beach town stucco box 248, Spanish 167, craftsman 107,
mid-century 93, dingbat 86, ranch 77.

**Frame cost.** opengl3, 1280x720, `--quality=0`, noon; before = main c848ad4 (the `base`
worktree), after = this branch. `tools/geo_count.gd` (the player at `--spawn`, 90 frames, the
player camera):

| Bookmark (`--spawn`) | triangles before -> after | draws before -> after | objects before -> after |
|---|---|---|---|
| Suburb corner `-290,307,-60,-3` | 8,897,807 -> 6,553,716 (-26 %) | 5,938 -> 5,388 (-9 %) | 17,755 -> 17,185 |
| Suburb street `-250,306,35,-3` | 7,467,853 -> 5,976,479 (-20 %) | 3,973 -> 3,456 (-13 %) | 15,771 -> 15,238 |
| Beach town `-648,60,140,-3` | 8,723,426 -> 7,411,528 (-15 %) | 4,372 -> 2,437 (-44 %) | 12,522 -> 10,514 |

`tools/glshot/block_shot.tscn` (the FULL blocks round the suburb alone, no far city; `GEO=1`):
aerial `-270,60,360,25,-35` 6,823,811 / 1,873 -> 4,411,477 / 1,647 (houses and yards; with
`YARD_FILL=0` 5,263,183 / 1,598), street `-262,1.7,304,20,-4` 6,085,359 / 1,787 -> 4,498,385 / 1,466.
A house is ~660-830 triangles and its whole chunk's houses ~13 draws, where each `Building` box
was its walls, facade detail, bays, roof plant and storefront kit (a handful of draws and thousands
of triangles each). The one view that costs more is a high aerial over the LOD ring
(`still_shot.gd` EYE `-300,320,600,-30,-24` over spawn `-300,350`): 2,390,872 / 854 -> 2,881,406 /
1,066 - the roof slabs and gable prisms (three boxes a pitched wing) and the 44 % more suburban
houses in the LOD chunks and the far city, plus the yards' planting batches in the FULL chunks
below. The street-level stills' own GEO lines agree (suburb corner 7.77 M / 3,541 -> 6.37 M /
3,065; beach street 7.19 M / 2,212 -> 6.68 M / 1,134; those "before" stills are from 96f86f1, the
commit this branch started on).

Build time (headless, `HouseKit.build()` + plan per lot): 3-7 ms a house in its lot step on this
box, a suburban block's 26-32 houses 83-98 ms spread over that many steps; the finish's commit
2-7 ms (26 ms on the first chunk, the materials' first load).

**Stills** (branch `shots/houses`, README there): before/after of the suburb street corner, the
suburb aerial, the beach street and the beach aerial, each at noon and at 18:24; after-only
close-ups of a ranch house (noon and dusk), garages and drives, a mid-century house, a stucco box,
a craftsman by the beach and the beach roofscape (`block_shot.tscn`); the far tier from 320 m.

**Tools and checks.** `still_shot.gd` / `block_shot.tscn` `HOUSES=0` (the A/B: Building boxes on
the house lots, as before); `tools/lot_coverage.gd` counts the houses' footprints and the extra
lots (SHAPE lines `house_<type>`). `tests/house_checks.gd` (in the smoke test, 17 checks): the
plans over the suburbs and the beach town west of downtown (pure, inside their yards, wings apart,
every type, heights, the yard's drive ending at the garage door), FULL suburban and beach blocks
(one mesh per material, collision on one body, no Building boxes, yards laid), the same blocks
captured for the far city (a box per wing, tilted slabs per pitched wing), and the kit off giving
Building boxes with nothing else moved. `tests/lot_fill_checks.gd`'s beach plan reads the houses.

**Traps.**
- A tilted box in the `lod_box` batch must show its LOCAL X face: building_lod.gdshader decides a
  roof by the LOCAL normal (any +-Y face is a flat roof and gets membrane, gravel and plant painted
  on it). And its basis must be rotation x scale: a MultiMesh instance's normal goes through the
  basis, not its inverse transpose, so a skewed box lights wrong.
- A front wing's gable roof pokes its back gable end up through the main roof (a dark notch from
  the street): its roof runs back `roof_back` into the main roof; the walls stay where they were.
- The lot grid's dropped cells are dropped BEFORE their seed roll, so they cannot be restored in
  CityPlan without moving every later lot's seed; they are rebuilt beside it instead
  (`extra_lots()`).
- `taken` spans for openings must reset per floor, or the garage and the front door blank the
  storey above them.
- `generate_normals()` / `generate_tangents()` on a chunk's whole house mesh: 10-30 ms in one
  finish step. Write them per triangle.

**Not done / not verified.**
- Judged in opengl3 stills only: the shingle and siding normal maps, the clay roofs, the glass and
  the stucco under Forward+ (the Mac) are not seen. The shaders work in linear through
  `color_space.gdshaderinc` but nobody has looked at them on Forward+.
- No dormers, no second-storey craftsman, no Monterey balconies, no tile "eyebrows" over Spanish
  windows, no wrought-iron grilles, no garage-door windows on the stucco boxes, no gutters or
  downspouts, no mailboxes at the drive, no porch lights that light anything.
- The houses' walls are axis-aligned like the lots; the far tier draws hip roofs as gables.
- `still_shot.gd SPLIT=1` fails on these bookmarks with "Trying to assign invalid previously freed
  instance" at `_geo_split` (line 806, both before and after: a pre-existing tool bug), so the
  high aerial's increase is not split by category.
- Nobody walks the drives or the walk streets; parked cars in the drives are the yard's
  (LotFill's static cars).


## 9bg. Real headwear, fitted to each head, 2026-10-04 (agent branch `worktree-agent-a4d942dcfd8aa9ccb`; GAME_PLAN G5, VISUAL_ROADMAP #49)

The brief (lead): the crowd's caps and beanies read as plastic bowls perched on the crown - a
smooth half-dome with a thin flat peak in flat saturated blue / green - the most toy-like thing
on a person in crowd-life's stills; make real headwear that fits each rig. CLAUDE.md's
"Headwear" note is the reference; this is the story.

**What was wrong, measured.** The old `_add_accessory()` hung one fixed tube + half-dome (cap
240 triangles, beanie 220, police cap 200) at one offset from the Head bone, levelled in the walk
clip's first frame. The crowd rigs' heads sit at different heights over that bone: on most of
them the cap's peak came out at eye level with the crown pushed back on the skull, the police cap
floated a few centimetres over the head, and the cap kept its hair cards on, which stood out
through it. Stills (not committed, the session's scratchpad `caps/`): `before2/close_*.png` (the same
framings as `after5/close_*.png`, drawn with the old code pasted into a scratch copy of
crowd_lineup) and `before/lineup_street.png` (the old hats at street range).

**The fit.** `tools/crowd/hat_fit.gd` (opengl3 under Xvfb; it needs mesh data) skins each crowd
rig's Body and Hair at rest into the HEAD FRAME (metres, skeleton axes, origin at the Head bone's
rest) and measures: the eye centre (the region colour's eye vertices), the ear tops, a centre C
at eye height half way between the back of the skull and the forehead and centred on the eyes
across (the Head bone is up to 3 mm off the head's middle), the skull's radius from C on a 17 x 32
grid of directions (four jittered rays a direction at the head-weighted triangles, outermost hit
kept - a ray down the mirror seam slipped between triangles and found the inside of the face),
the ears put back on the skull (only the samples within 35 degrees of each ear, near eye height,
that stand 2 mm proud of the chord over the window: a whole-ring fit "removed" the nose and the
occiput too), the two sides averaged, a light blur; and the hair's thickness over it from rays at
the Hair cards less the brows and lashes. `scripts/npc/crowd_hat_table.gd` holds it (52 KB for
twelve rigs). `REPORT=1` builds every hat on every rig from the table and casts from outside in
through every covered head vertex to the hat's outer surface: 0 through on all 48 rig x kind
pairs, the outside 0.0-6.5 mm off the skin at its closest, the band 0.5-17 mm (the larger numbers
are the beanie's knit over pressed hair).

**The hats** (`scripts/npc/crowd_hat.gd`, `CrowdHat`, all code): a grid shell round the head - per
column round the head the band edge's elevation (a height over the eyes per kind, the front and
back in `EDGE`, the sides never under the ear tops + `EAR_CLEAR`), rows up to the crown, each
point the skull radius there plus `standoff()` (cloth, room for the pressed hair, a loft, the
cap's structured front panels, each panel puffed between its seams, the beanie's slouch to the
back) - and parts on it:
- cap: six panels (seams on columns), a button, a sweatband 28 mm up the inside, a rolled edge,
  the opening at the back (a rounded arch) with a strap tucked under the panels and a slide
  buckle, the bill: 7 cm reach for a 20 cm head, 12 degrees down, its sides curved down 2 cm, a
  crown across its depth, 3.4 mm thick, a taped edge rolled round it, its root tucked under the
  band;
- beanie: the knit to the crown (a slouch toward the back), a 52 mm 2x2-rib cuff 3.6 mm proud,
  its lower edge folded under and its top rolled back onto the knit;
- bucket: four side panels (seams 45 degrees off the front), a quarter-round corner, a round top,
  a 52 mm brim sloping and waving, a taped edge;
- police: a straight black braid band, a crown flaring to a rim (higher at the front), a domed
  top, a patent peak (52 mm, 29 degrees down), a chin strap on two buttons, a shield badge laid
  on the crown's slope.
LOD: the levels are the same grids at every 1st, 2nd and 4th row and column, one vertex buffer
(cap 1,812 / 464 / 121 triangles, beanie 1,656 / 432 / 107, bucket 1,980 / 522 / 153, police
1,636 / 454 / 139; edges `LEVEL_EDGES` 0 / 1.8 / 5.5 mm). Normals and windings are decided per
GRID (vote, then one way for all): turned vertex by vertex, the police flare's first row had
every other triangle facing in (a sawtooth of lining showing at the band's top).

**The cloth** (`shaders/crowd_hat.gdshader`): everything a close look reads is drawn on the
mesh's coordinates (UV in metres round and up; part id, occlusion, parameter and ring radius in
the vertex colour): twill and slubs, panel seams as a valley with the cloth puffed either side and
topstitching 3.2 mm off, embroidered eyelets, eight rows of stitching round the bill, a taped
edge's stitch line, the ribbed sweatband, stockinette knit (Vs up each column, a heather), the
cuff's 2x2 rib, the crown's six decrease lines, a bucket's metal vent eyelets, three original
embroidered marks (a ring and dot, a ridge line, a wave; half the caps plain) or a woven label on
a third of the beanies, the police band's braid, patent with a clearcoat. Each pattern fades to
its average under a pixel. Both faces drawn (`cull_disabled`): the back faces are the lining
(dark, unlit by the sky), so the inside of a crown under a bill, through the cap's opening and
up into a bucket needs no geometry. The relief tilts the normal in a frame worked out from the
screen derivatives of UV (no tangents in the mesh). Linear on both renderers
(`color_space.gdshaderinc`). Colourways are muted and team-less (`CAP_COLORS`, `BEANIE_COLORS`,
`BUCKET_COLORS`; the police navy = `PoliceOfficer.CAP_COLOR`); one material per colourway and
mark (~60 at most).

**The hair is pressed, not hidden** (`pressed_hair()`, one copy per hair mesh, rig and kind):
every hair vertex under the crown moved inside the hat's inner surface, easing out over 3.5 cm
below the band so the hair comes out from under it at the back and sides; a strand more than
2.6-4 cm off the scalp left alone (crowd_d's ponytail goes out through the cap's opening); the
triangles left wholly inside dropped (crowd_d's 3,830 hair triangles are 2,250 under the cap,
crowd_i's 3,829 are 1,565, crowd_k's 3,831 are 3,193); the importer's hair LODs kept, less the same triangles. A fringe
(a hair card that starts under the crown and hangs in front of the face) is dropped whole, as if
tucked up under the hat. Three other ways were tried and each was worse: pressed only where it
was under the hat it bunched into a dark slab over one eye, laid flat on the skin it was an eye
patch, and slid in whole (by the most any of its vertices stood out of the hat) it still poked
out through the front of the crown and hung over an eye. Dropped, the scalp painted under it can
show as a soft smudge of the hair colour on the forehead, which reads as hair under the band
(`caps/after5/close_front.png`: crowd_h and crowd_c, over one brow). A "card" is a connected piece
of the hair mesh, and on four rigs (crowd_c, g, h, l: short crops) the whole scalp of hair is one
piece that reaches both under the crown and down the forehead, so under any hat it all goes and
the painted scalp is the hair at the back and sides (it reads as a short crop from behind,
`after5/close_back.png`); the rigs with separate cards (b, d, e, f, i, k) keep theirs below the
band. crowd_a and crowd_j have no scalp hair, only brows. No mesh data (the headless check) hides the
cards as before; a rig whose hair is too thick to press can be marked `"hide"` by the tool (none
is: crowd_e's natural hair is ~2 cm and presses).

**In the game.** `Pedestrian._add_accessory()` makes the same three `_style` rolls as before (the
chance, the kind, one colour roll; CampFigure.seed_for() and everything rolled after depend on
them) - a bucket hat is the top tenth of the old cap roll; the pack is unchanged.
`Pedestrian.knock()` dresses the ragdoll in the same hat (`_dress_doll()`; a decapitating gib
takes it with the head bone). `PoliceOfficer._add_cap()` is `CrowdHat.Kind.PEAKED` (the tactical
unit still goes bare-headed), on the officer and on their ragdoll. Rough sleepers wear hats from
the same roll in a worn colourway (dulled toward grey-brown, the top sun-faded, grime in blotches
at the band: `CrowdHat.material(kind, pick, true)`, `RoughSleeper._wear_hat()`); camp figures'
seeds still avoid them. The loading screen builds every hat and
pressed hair (`CrowdHat.warm()` from `Pedestrian.warm_far_mesh()`, which already has the rig
instanced): **~0.8 s here** for twelve rigs (41 hats at ~10-13 ms, the hair ~10 ms a kind) - the
people's share of the loading screen grows by about that.

**Cost per wearer.** One draw (the hat), no shadow pass, no GI, gone past
`accessory_distance` - as before. Triangles 1.6-2k near, ~430-520 from a couple of metres, ~110-150
from ~4 m (the old ones were 200-240 at every range). The hair under a beanie or the police cap is
drawn again (it was hidden; it is the person's own draw, the one they have without a hat), with
the triangles inside the hat dropped. Memory: ~3 MB of hat meshes, ~6 MB of pressed hair copies.

**Judged** (opengl3 lineups, `crowd_lineup.gd HATS=...`, and one Forward+ lavapipe lineup):
`after5/close_*.png` (four kinds at 1.4-1.9 m: 3/4, front, profile, back, from below),
`after5/street_*.png` (eight people at 6 and 16 m), `fwd/close_*.png` (Forward+); pairs in
`pairs/`. At street range a cap is a cap - crown down on the forehead, the bill's curve and the
button read - and a beanie a beanie; up close the seams, the bill's stitching, the knit and the
rib read, the hair comes out under the band. Not seen on the owner's Mac.

**Traps:** `posmod()` is integer-only - on a float angle it truncated, and the whole skull
lookup was constant over a radian (the first "48 % of the head through the cap" report);
`Array[PackedInt32Array]`'s element appended through the subscript is the stored one, but
`var x := arr[i]` then `x.append()` is a copy; the fit tool's TriangleMesh rays down the mirror
seam miss or go through (jitter them); a class_name file the editor has not imported is not
declared to other scripts (`--import` after adding one); the cap's sweatband and rolled edge at
half the crown's columns cut the corners of the back opening's arch and came 0.4 mm through the
skin there (they now take the crown's columns: the report's last two contacts).

**Not done / next:** the hats cast no shadow (the brief's rule): the brim does not shade the
eyes, which is now the biggest tell left up close - a SHADOWS_ONLY twin of the bill within ~15 m
would cost one shadow draw per near wearer; a little of the painted hairline still shows under
the bucket hat's front edge on crowd_c (symmetric paint, see the follow-up below); a one-piece head of hair (c, g, h, l)
goes whole - splitting a piece by region (drop the part in front of the face below the band,
press the rest) would keep their hair at the back and sides; the cards of very thick hair would need `"hide"` (no rig has it); hats never come off (shot or
blasted off, a cap could be debris); the warm could run on worker threads during the city build
instead of adding ~0.8 s; no cap is worn backwards or tilted; the bucket hat's brim does not
droop with the wind. Rerun `tools/crowd/hat_fit.gd` whenever a crowd rig is rebuilt.

**Follow-up, 2026-10-05: the black eye under a hat.** Where a fringe hung over one eye, the body
atlas has the scalp painted in the hair colour under it (it is the far bodies' hair); with the
fringe dropped under a hat, crowd_h (black) and crowd_c (grey) read as having a black eye at 2 m.
A hat wearer's body now draws on a copy of its look material (`CrowdHat.fit_face()`, from
`dress()` and RoughSleeper's `_wear_hat()`, which swaps in the worn look after the hat) with
`character.gdshader`'s `hat_face` on: in the face's zone below the band (`FACE_HALF` / `_LOW` /
`_HIGH` round the eyes, faded over `FACE_FADE`) a texel whose neighbourhood (three mips up)
differs from its MIRROR IMAGE across the face and is the less skin-like (saturation x 1.5 plus
value) takes the mirror's texel; symmetric paint (skin, brows, stubble, the hairline) is left
alone. `face_fix()` measures it per rig once, at rest in the head frame: every head vertex near
the zone paired with the vertex at its mirror position (the rigs are exactly symmetric: 0.0 mm),
the mirror fitted as a reflection across a line in the atlas (a doubled-angle mean of the pairs'
differences and the median of their midpoints, refitted on the inliers; 0.1-0.5 px RMS on all
twelve rigs - a least-squares affine was dragged off by the few seam copies on other islands),
the face island (inlier vertices, the midline's on the line, within 0.15 x 0.25 UV of their
median - crowd_i and crowd_k have a small symmetric island elsewhere on the same line) and the
zone rasterised into a 128 px mask over its UV rect (a triangle with one island corner counts:
asking for three left holes, each a black speck). Uniforms `hat_face_rect`, `hat_face_mask`,
`hat_face_u` / `_v`; one material copy per look material (~45 ms a rig on the loading screen,
through `warm()`). Nothing changes without mesh data (headless) or where the mirror does not fit
(a warning names the rig). The probe that lays the fix out on the atlas on the CPU and the
previews are in the session's scratchpad (`caps/face_probe.gd`, `caps/face/`). Stills
(before = the fringe dropped, after = this): `build/hat_face/face_h_front.jpg`,
`face_c_front.jpg`, `face_h_up.jpg`, `face_c_up.jpg` and the whole lineup `close_front.jpg`,
`close_up.jpg`, `close_q.jpg` in the worktree (ignored, not committed). Left: a faint seam on
crowd_h's cheek where the mirrored skin meets the original, and on crowd_c the grey stipple of
the hairline between the brows under the brim edge (symmetric, so nothing to mirror).

## 9bh. The industrial district as Los Angeles industry, 2026-10-04 (agent branch `wt/industrial`; VISUAL_ROADMAP #48)

The brief: INDUSTRIAL (east of the 110 below z 2300 down to the port, and the Arts District east
of Vignes) was `Building` WAREHOUSEs - boxes with ribbon windows, offices in all but name - and
slabs standing on bare paving, 40 % of the district's block ground. Make it read like Vernon, the
Alameda corridor and the Arts District. All of it is `Industrial` (`scripts/world/industrial.gd`)
and `IndustrialKit` (`scripts/world/industrial_kit.gd`); the rules are the CLAUDE.md bullet after
YardFill's.

**What a block is now.**
- A WAREHOUSE lot is Industrial's own tilt-up warehouse (the Building is planned for its height
  and shape, then freed): concrete panels with joints, reveals, an accent wainscot and parapet
  band, buffed-out graffiti patches, lifting inserts, dirt run down from the coping; a parapet and
  coping; a membrane roof with seams, ponding, skylights and rooftop units; a glazed office corner
  with a canopy; on the end walls a steel man door, wall packs and downspouts. Facing the street it
  is deepest from (`lot_side()`), a lot at least 44 m deep gets a TRUCK COURT (20-30 m): dock
  doors every 4.25 m (roll-up, seal head and side pads, bumpers, a plate, an arm-mounted dock
  light, a light pool), a grade-level door at the far end with yellow bollards, trailers backed on
  to 55 % of the docks (a 53 ft van, a skirted one or a 40 ft reefer; a tractor still coupled to a
  fifth of them where the court has room), a concrete apron, stall stripes, chain-link with barbed
  wire on outriggers along the street with a gate open. A shallower lot gets two or three
  grade-level doors and an employee car park or a weed strip in its setback.
- In the Arts District 80 % of the warehouses are BRICK (the photographed courses sooted up the
  wall, steel factory sash - 4 x 5 panes, a few painted out or broken - in every bay at each
  4.6 m floor, a third of them lit warm at night) standing at the back of the pavement, and the
  Building lots there take brick finishes; three in four street-facing end walls carry a MURAL
  (and some fronts), and a tilt-up wall elsewhere now and then (8 %). The murals are invented in
  the shader (`mural()` in `industrial_walls.gdshader`: six palettes, a waved two-colour ground,
  rays from a disc, ringed discs, a band of stripes, outlined blobs, dots, a zig-zag, dark ink
  outlines, the paint chipped back to the concrete and faded at the foot) - abstract, no lettering,
  no figure, nobody's work.
- Every lot cell less its building is spoken for (`block_plan()`): the court and apron, drive
  strips down the sides (cracked asphalt, weedy dirt or gravel; a dumpster or a roll-off, a row of
  pallet loads), the back (a storage yard when it is over 7 m: pallets - empties, wrapped loads,
  doubles, cartons -, drums, a PortKit container, a corrugated shed with a mono-pitch roof and a
  roll-up door, or two to four storage tanks in a concrete containment wall), the front setback.
  Half the blocks with two rows of lots and 5.6 m between them have a RAIL SPUR down the middle
  (ballast with creosoted ties drawn by the ground shader, two rails, yellow bumper stops, a string
  of boxcars - ribbed, a sliding door, rust, a block of invented marks - and black or white tank
  cars on 80 % of them), and the warehouses backing onto it get rail doors. One block in eleven
  with a big enough yard has an elevated steel water tower.
- Nothing industrial stands under a freeway deck or ramp (`clear_of_freeway()`): the first full
  check failed on boxcars under the 110 (`downtown_checks`' "no deck through a building" holds
  every captured far box to it), so a string of cars now stops short of a deck.

**How it is drawn.** A FULL chunk's industrial geometry is two meshes and a batch: the ground
(`IndustrialGround`, `shaders/industrial_ground.gdshader`, no shadow: asphalt oxidised in broad
patches, alligator-cracked where it has failed with weeds in the wider cracks, darker patches,
hairline long cracks, oil; concrete apron slabs with saw joints and stains; gravel; dirt with weed
clumps; ballast and ties; worn stall paint), everything upright (`IndustrialWalls`,
`shaders/industrial_walls.gdshader`, casting: the warehouses, docks, fences, rails AND every prop -
trailers, tractors, rail cars, pallets, drums, bins, tanks, the tower - written straight into the
mesh by `IndustrialKit.place()`), and the dock and wall-pack light pools (`ind_pool`, additive, no
shadow). The first version had a MultiMesh batch per prop kind (15-20 a chunk, each with its
shadow cascades); at the court bookmark that was +497 draws over the old district, so the props
went into the walls mesh. Containers stay PortKit's (`container` batch), the parked cars
ArenaGrounds' (`apark_car_*`). LOD chunks and the far city (capture mode) get the warehouses,
trailers, rail cars, tanks and the tower as plain `lod_box`es (custom alpha 1: no windows) and the
yards as ground slabs - their LOD steps are a few milliseconds.

**Coverage** (`tools/lot_coverage.gd`, whole district, seed 1337, `RECT=2150,-1700,3000,7700`;
`FILL=yard` is the city before this branch, the default now runs Industrial too; a new kind,
`works`):

| Row | bare before | bare after | what covers it after |
|---|---|---|---|
| INDUSTRIAL (943 blocks, 2,098 lots) | 40.0 % | 0.0 % | built 46.6, works 46.0, row 7.4 |

The warehouses cover 69 % of their lots now (81 % as Building boxes): the court is the difference.

**Cost.** opengl3, 1280x720, `--quality=0`, clear; before = `INDUSTRIAL=0` (the district as it
was), after = this branch. `still_shot.gd` (free camera, `EYE_AGL=1`; GEO, triangles / draws):

| Still | before | after |
|---|---|---|
| Vernon street `2610,1.7,3290,180,-1` 13:00 | 2,210,272 / 1,519 | 2,199,371 / 1,426 (-0.5 % / -6.1 %) |
| Vernon court `2630,2.2,3300,-139,-4` 18:24 | 1,802,370 / 1,585 | 2,184,489 / 1,866 (+21.2 % / +17.7 %) |
| Vernon aerial `2580,85,3250,-139,-38` 13:00 | 2,085,334 / 1,956 | 1,988,603 / 1,781 (-4.6 % / -8.9 %) |
| Arts District mural `3992,1.7,345,-142,10` 15:00 | 2,787,490 / 2,153 | 2,761,376 / 2,050 (-0.9 % / -4.8 %) |
| Arts District street `4277,1.7,610,8,3` 15:00 | 3,653,900 / 2,142 | 3,552,417 / 1,934 (-2.8 % / -9.7 %) |
| Arts District aerial `4180,110,760,0,-38` 15:00 | 2,764,053 / 2,635 | 2,677,944 / 2,396 (-3.1 % / -9.1 %) |

`tools/geo_count.gd` (the player camera at `--spawn`, 90 frames, noon):

| Spawn | triangles | draws | objects |
|---|---|---|---|
| Vernon street `2610,3290,180,-1` | 2,348,512 -> 2,289,138 (-2.5 %) | 2,594 -> 2,474 (-4.6 %) | 18,637 -> 18,511 |
| Vernon court `2620,3330,-90,-3` | 2,257,745 -> 2,737,407 (+21.2 %) | 2,722 -> 3,090 (+13.5 %) | 18,767 -> 19,133 |
| Arts District street `4277,610,8,3` | 3,190,092 -> 3,088,019 (-3.2 %) | 3,407 -> 3,192 (-6.3 %) | 19,463 -> 19,237 |

A warehouse is now a few hundred boxes in its chunk's ONE walls mesh (2-6k triangles a FULL
chunk, every prop included: `industrial_bench`'s count) where a Building was walls, frames,
details, roof plant and kit nodes; so most views got cheaper. The court views are the exception
and it is what they see, not what is built: before, the camera stood against an office block's
wall (the Building filled 90 % of the lot) and the wall hid the city; now it looks across an open
court and down the streets beyond. (`geo_count.gd`'s `AB=` second count hung at that spawn twice -
the `Engine.time_scale = 0` frames never came back - so the split is from the bench, not an A/B.)

**Build time** (`tools/industrial_bench/industrial_bench.tscn`, headless, warm, Industrial on vs
off, four blocks: a Vernon court block, a spur block, two Arts District blocks): FULL 163-193 ms vs
162-225 ms in 59-84 steps, slowest step 44-62 ms vs 48-65 ms (the slowest step is not Industrial's:
it is the same with it off); LOD 17-19 ms vs 14-15 ms, slowest step 5-7 ms either way.

**Traps.**
- `Basis(Vector3.FORWARD, PI * 0.5)` takes a cylinder's +y to +x (a wheel's axle); the first
  wheels were offset by their own width.
- `PortKit.container_xform()` lays a box along x; turned for a long-x yard it lay across the rail
  spur.
- The night courts were striped (three wrong guesses first: shadow acne, the far city, big
  triangles in the additive light passes). It was the street lamp's own light pool
  (`CityChunk._add_lamp()`), laid 5 cm over the pavement - exactly the height of the yard ground
  beside it - so the two z-fought inside the pool. The pool is 9 cm up now (additive, no depth: it
  looks the same everywhere); this fixes YardFill's yards beside a lamp too. The industrial light
  pools stand 15 cm up for the same reason.
- The asphalt's crack network was thinner than a pixel at a grazing view and aliased; cracks now
  fade by the pixel's LONGER footprint axis (`length(dFdx(p)), length(dFdy(p))`) to the tone they
  average to, and the patch mask is smooth noise (quantised to 0.5 m it drew stair-stepped edges).
- A still's `EYE` y is absolute: give `EYE_AGL=1` or the camera is in the ground on any relief
  (the first "before" set was).
- Hour 19.45 is full night; the lamps are on and the sky still lit at about 18.4.

**Tools and checks.** `tests/industrial_checks.gd` (13 checks in the smoke test): bare share
before and after round Vernon, both shaders' kind tables, the plans over Vernon and the Arts
District (warehouses in their cells, no yard piece under a building, outside its block, on another
piece or on the spur; warehouses, courts, docks, spurs, brick, murals and storage yards all
present), a FULL chunk (one mesh each on the right shaders, no Building for a warehouse lot,
trailers at the docks, no prop batches, the pools shadowless, the warehouses in the encampments'
wall list), the block built with Industrial off keeps every pavement prop where it was, a LOD build
and the far city's capture draw the warehouses as far boxes. `INDUSTRIAL=0` on `still_shot.gd`,
`block_shot.tscn` and `tools/geo_count.gd` is the A/B; `industrial_bench.tscn` times the builds.

## 9bf. Frame cost after the 2026-10-04 wave: the audit, and three cuts, 2026-10-05 (agent branch `worktree-agent-af1df0312085290fc`; VISUAL_ROADMAP #50)

The brief: since 9x a lot landed (shop interiors, hills from the air, crowd garments, car lights,
surf, switchbacks, yards, the freeway kit, the airport, crowd life, coded far buildings; houses,
industry and headwear while this ran). Measure where the frame goes now and cut what is cheap to
cut, with no visible loss. North star: 60 fps at 1440p on the owner's Mac, 30 the floor.

### The baseline next to 9x

`SPLIT=1 tools/glshot/bookmarks.sh` on main b2a6482 (before houses, industry and headwear), opengl3
/ llvmpipe, 960x540, `--quality=0`, each bookmark at its own hour; GEO triangles include the
shadow passes (camera / shadow), "draws" is the camera pass. Three bookmarks moved since 9x
(downtown, the freeway and the masjid went to their 1:1 places on 2026-09-25), so 9ai's "after"
(the same spawns, 2026-09-27) is the fair comparison for those:

| Bookmark | 9x (2026-09-25) | 9ai after (same spawns) | now (b2a6482) |
|---|---|---|---|
| downtown_noon | 8.24 M / 4,679 (old spawn) | 6.52 M / 3,360 | 7.66 M (4.17 / 3.49) / 3,950 |
| downtown_night_rain | 8.24 M / 4,685 (old spawn) | 6.52 M / 3,363 | 7.66 M (4.17 / 3.49) / 3,953 |
| freeway | 8.68 M / 6,661 (old spawn) | 6.40 M / 3,646 | 6.43 M (4.21 / 2.23) / 3,935 |
| masjid | - (old spawn) | 7.91 M / 4,258 | 8.20 M (4.46 / 3.74) / 4,940 |
| esplanade_sunset | 3.19 M / 1,309 | - | 2.72 M (1.41 / 1.31) / 2,159 |
| hills | 1.60 M / 1,202 (942 after the box merge) | - | 1.72 M (1.59 / 0.13) / 1,134 |

Where it goes now (`SPLIT`: triangles, of which shadow, and draws):

| Category | downtown_noon | freeway | masjid | esplanade_sunset | hills |
|---|---|---|---|---|---|
| Buildings | **2.10 M (1.42 sh)**, 1,172 | 0.74 M (0.50 sh), 1,159 | 0.97 M (0.73 sh), 1,241 | 0.14 M (0.13 sh), 228 | 0.01 M, 38 |
| Far city (Skyline) | 1.69 M, 143 | **1.84 M**, 199 | **2.01 M**, 181 | 0.24 M, 65 | **1.20 M**, 118 |
| Trees, palms, planting | 1.10 M (0.71 sh), 443 | 1.30 M (0.81 sh), 599 | 1.79 M (1.33 sh), 833 | **1.57 M (0.93 sh), 1,056** | 0.03 M, 61 |
| Street props | 0.86 M (0.56 sh), 852 | 0.68 M (0.28 sh), 794 | 0.72 M (0.40 sh), 1,148 | 0.22 M (0.13 sh), 420 | 0.04 M, 138 |
| Other (chunk ground, freeway kit, merged boxes, terrain) | 0.60 M (0.30 sh), 211 | 0.70 M (0.35 sh), 457 | **1.79 M (1.12 sh)**, 738 | 0.40 M (0.10 sh), 262 | 0.36 M (0.07 sh), 445 |
| Vehicles | 0.51 M (0.20 sh), 280 | 0.58 M (0.24 sh), 340 | 0.55 M (0.11 sh), 441 | 0.09 M, 59 | ~0, 5 |
| Pedestrians (+ hero) | 0.39 M (0.12 sh), 354 | 0.12 M, 125 | 0.16 M, 125 | 0.01 M, 15 | 0.07 M, 28 |
| Camp (encampments) | 0.26 M (0.18 sh), 379 | - | - | - | - |
| LotFill / yards | 0.10 M, 22 | 0.34 M, 72 | 0.06 M, 25 | 0.01 M, 5 | 0 |

What grew most:
- **Shadows.** The shadow passes are 46 % of the downtown frame (3.49 of 7.66 M; 2.69 of 8.24 M in
  9x) and 46 % at the masjid. Inside the Building category, BSPLIT put 1.15 M on "kit other"
  downtown, and the shadow census below found it: the facade kit's ROOFLINE - the parapet coping
  (511k shadow triangles downtown) and the plain cornice (384k) - a 42-triangle 2 m run round
  every roof within 230 m, cast into every cascade it touches (the coping's 6 cm drip line is
  invisible past the second cascade).
- **The far city**: 0.8-1.3 M in 9x, 1.2-2.0 M now (the coded far buildings' silhouette plant,
  9bd, and the canopy blobs). Camera pass only, few draws; nothing cheap to cut without a change.
- **Draws**: the esplanade's planting (1,056 draws: the hill chunks' species batches on the
  peninsula) and the street props (850-1,150 a street frame) are the draw sinks now; the kit's
  rooftop units (`Batch_kit_hvac`, three surfaces a building) are ~200 draws downtown for almost
  no camera triangles.

The shadow census (`perfaudit/shadow_census.gd` in the agent's scratchpad: every visible caster
within 520 m grouped by kind, then each of the top kinds' shadows turned off on the frozen frame,
and each kind hidden for its draws) ranked downtown's shadow pass: coping 511k, trees' shadow twins
385k, plain cornice 384k, the chunk ground grids (`road.gdshader` MeshInstances: the block's
pavement slab, the roads, lawns) 261k, palms' twins 159k, vehicle wheels 152k, benches' twins
151k, rooftop units 139k + 122k, parapets and bands 103k, encampment pieces ~180k together.

### Forward+: the city does not fit lavapipe any more

`tools/gpu_profile.gd` on the whole city was OOM-killed twice at 12.7 GB of anonymous memory (the
session's memory cgroup is 14.3 GB, shared with every other agent's renders, and the OOM killer
took a second, small Godot process along with it). So there is no city per-pass table this time:
`gpu_profile.gd` now takes `LIGHT_WORLD=1` (still_shot.gd's smaller world) for a box that can hold
it, prints a `LIGHTS` line (positional lights inside their distance fade: lit, at zero energy,
shadowed) and the A/B switches below; on this box the rule is now never to render the city on
lavapipe. The lights were counted headless instead (a scratch script at the downtown spawn): 10
street-lamp OmniLights inside their fade at noon and at night, one searchlight, CarLights' spot
and rear light (off by day). Every positional light is unshadowed except the sun and the
player's car spot; the freeway's under-deck lights and the airport masts are additive quads, not
lights.

### What was cut (each with its A/B switch)

Measured as the lead asked: `still_shot.gd` at 1280x720, `--hour=12 --weather=clear --nohud
--quality=0`, `DIFF=1` (cars, people, aircraft and particles hidden, so two runs render the same
frame), "before" = `SHADOW_REACH=0 GROUND_SHADOW=0 LAMPS_AT_ZERO=1` on the same tree (e616d37 plus
this branch: houses, industry and headwear in), "after" = the defaults. Pixel diffs by
`tools/glshot/img_diff.py`:

| Bookmark (`--spawn`) | before: tris (camera / shadow) / draws | after | change | pixels that moved |
|---|---|---|---|---|
| downtown `2359.4,880,0,12,2` | 7,013,501 (3,841,909 / 3,171,590) / 3,298 | 6,310,853 (3,841,909 / 2,468,942) / 3,247 | **-10.0 %** (shadow -22 %), -51 draws | 1,171 (0.13 %); 54 > 8, 5 > 32 |
| freeway `200,1088,-90,-4,30` | 5,759,212 (3,892,417 / 1,866,793) / 3,318 | 5,417,496 (3,892,417 / 1,525,077) / 3,272 | **-5.9 %** (shadow -18 %), -46 | 1,807 (0.20 %); 208 > 8, 20 > 32 |
| masjid `1880.7,2809.6,-31.8,-23.7,32` | 8,739,540 (4,149,800 / 4,589,738) / 5,743 | 8,312,876 (4,149,800 / 4,163,074) / 5,613 | **-4.9 %** (shadow -9.3 %), -130 | 5,402 (0.59 %); 418 > 8, 32 > 32 |
| suburb `-290,307,-60,-3` | 7,059,843 (4,565,039 / 2,494,802) / 3,943 | 6,876,023 (4,565,039 / 2,310,982) / 3,929 | -2.6 % (shadow -7.4 %), -14 | 1,063 (0.12 %); 169 > 8, 11 > 32 |
| Vernon `2610,3290,180,-1` | 2,323,761 (1,738,489 / 585,270) / 1,606 | 2,223,093 (1,738,489 / 484,602) / 1,598 | -4.3 % (shadow -17 %), -8 | 0 |
| hills `300,-650,0,-6,260` | 1,919,420 (1,815,050 / 104,368) / 1,104 | the same | 0 | 7 (what two DIFF runs differ by) |
| esplanade (the bookmark's EYE, FOV 44) | 2,476,372 (1,352,891 / 1,123,479) / 1,760 | 2,469,892 (1,352,891 / 1,116,999) / 1,760 | -0.3 % | 28, all by 1/255 |

Again on the merged head 07f2669 (buses and trucks, the vendors and the Coral Line in), downtown:
7,206,949 (3,888,059 / 3,318,888) / 3,424 -> 6,504,301 (3,888,059 / 2,616,240) / 3,373, -9.7 %
(shadow -21 %), 1,157 pixels moved (54 > 8, 5 > 32) - the same cut on a frame that grew.

The camera pass is identical to the triangle in every view: everything came out of the shadow
passes. Per cut (the other two off): downtown, the ground rule -175,548 shadow triangles (1,130
pixels moved, 53 > 8) and the roofline reach -527,100; the masjid, ground -183,784 (3,406 px, 167 >
8) and reach -242,880 (2,027 px, 252 > 8, 29 > 32). Side by side at 3x the moved pixels cannot be
told apart by eye (`perfaudit/ab/masjid_reach_tl.png`, `masjid_kerb_triple.png`).

1. **The roofline casts only near the camera** (`MultiMeshBatch.set_shadow_reach()`,
   `Building.kit_roofline_shadow_reach` 80 m, `SHADOW_REACH=0` the A/B). The cornices and the
   coping keep their own shadow while any run of a building's roofline is within 80 m of the camera
   (the twin's range is the reach plus half the diagonal of the runs' bounds, since a node's range
   is measured to the centre of its bounds); past it the cascades are 10-15 cm a texel (80-210 m)
   and 30 cm and more (to 500 m), so the coping's 6 cm drip line cannot be drawn, and the
   cornice's shadow is cast by the box band that has always sat inside the moulding
   (`KIT_CORNICE_CORE`, which stays). `set_shadow_reach()` is new and generic: a batch with a
   lighter twin keeps it with that range, one without gets a SHADOWS_ONLY twin of its own mesh; up
   close it casts exactly what it cast before. What moves: thin lines along far rooflines and the
   cornice shadow on far walls, 20-45/255 on single pixel rows (most in the masjid's aerial view).
2. **A raised ground slab casts from its skirt and its edge** (`CityChunk.ground_skirt_shadows`,
   `GROUND_SHADOW=0` the A/B). The block's pavement slab (the whole block at 2.2 m quads, ~10k
   triangles), lawns, paths and plazas now cast through a SHADOWS_ONLY `GroundRim`: the skirt
   (the kerb face, which draws the kerb's shadow on the road) and the ring of edge cells (so the
   kerb top's shadow edge and its filtering are what they were); the middle of the top, which
   nothing under it can see, casts nothing. Only slabs whose top is within `GROUND_RIM_TOP`
   (0.5 m) of the pavement: a gas station's 0.5 m canopy is ground-grid shaped too, up in the air,
   and keeps all of its shadow. The roads keep theirs - the first version took the road slabs out
   too (nothing lies under a road) and the paint, stop lines and patches millimetres above them
   came out lighter along their edges (6,075 pixels downtown, 849 > 8; `perfaudit/ab_v1/`). What
   still moves: where something lies a centimetre or two above a slab's middle (yard ground,
   forecourts), the slab's own depth no longer darkens its edges - acne, not a shadow - and a few
   scattered facade pixels, from the shadow map's depth fit changing with its casters.
3. **The street lamps' lights are hidden while they are off** (`DayNight.hide_dark_lamps`,
   `LAMPS_AT_ZERO=1` the A/B). DayNight set their energy to 0 by day (and below MEDIUM, where
   Quality zeroes `lamp_scale`) and left them visible, and Godot does not skip a light for having
   no energy: Forward+ puts every light inside its distance fade into its clusters
   (`LightStorage::update_light_buffers` checks only the fade; read in the 4.7.2 source) and the
   Compatibility renderer into its per-object light lists. The opengl3 counters cannot see light
   cost, so it was measured on a small Forward+ scene under lavapipe (`perfaudit/light_bench.gd`:
   a 400 m street, two walls, a PSSM sun, 100 lamp lights at energy 0 every 12 m, ~14 inside
   their fade): frame 146 / 143 ms with them shown, 103 / 99 ms hidden (two runs each, 7-8 GPU
   profile samples a run, the box busy with opengl3 renders) - the opaque pass 87-88 -> 56-59 ms;
   with volumetric fog 186 -> 172 ms. A software GPU is not the Mac, but such a light costs every
   pixel it reaches, and downtown at noon that was 10 of them. Nothing on screen can change (they
   were at zero).

### Tried and dropped

- **The rooftop air conditioners from the model's shadow proxy** (half the triangles at LOD 0, a
  twin per building): the shadow pass counted exactly the same triangles to the unit (138,908 and
  122,053 downtown, before and after). The units' surfaces have LODs, the counter counts a LOD'd
  surface once per draw (measurement trap 3), and at the distances they stand from a street camera
  the proxy's LODs and the model's are the same index arrays. No measurable gain, not kept.
- **Roads that cast nothing**: see cut 2.

### Found, not fixed

- **`MultiMeshBatch.set_shadow_distance()` does nothing on a batch with no lighter twin**: the
  distance only reaches a twin, and a code-built mesh has none. The airport's fence posts (60 m),
  edge lights (30 m), gate sets and staging rows (160 m) and the car parks' fence posts (40 m) all
  ask for one and cast to their draw distance instead. `set_shadow_reach()` is what they meant;
  switching them changes the look at the airport, which no bookmark covers, so it is left.
- **Car wheels**: 776 wheel MeshInstances (four a car, one surface each) were 152k shadow
  triangles downtown, cast to `_wheel_far_end`. `vehicle.gd` belongs to the buses / trucks branch;
  a shadow distance for the wheels (the body's twin already stops at `body_shadow_distance`) is the
  next cheap cut there.
- **Benches' shadow twin** is 151k downtown: the bench is 6.4k triangles (its `TRI_BUDGET` of 4,000
  could not be met by the generated LODs) and its proxy 3.4k; a coarser proxy needs a look check.
- `Batch_kit_hvac` is ~200 draws for ~800 camera triangles downtown (three surfaces a building,
  drawn behind parapets from the street).

### How to check it again

    # one A/B pair (the same args both sides; before = the three switches)
    env OUT=a.png FRAMES=45 DIFF=1 [SHADOW_REACH=0 GROUND_SHADOW=0 LAMPS_AT_ZERO=1] \
      LIBGL_ALWAYS_SOFTWARE=1 flock -o /tmp/rando_render_gl.lock xvfb-run -a -s "-screen 0 1280x720x24" \
      godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
      --script tools/glshot/still_shot.gd --resolution 1280x720 \
      -- --spawn=2359.4,880,0,12,2 --hour=12 --weather=clear --nohud --quality=0
    python3 tools/glshot/img_diff.py before.png after.png heat.png

The stills, heatmaps and logs of this pass are in the agent's scratchpad (`perfaudit/ab/`:
`<bookmark>_before.png`, `_after.png`, `_heat.png`, `_diff.txt` and the logs with their GEO lines;
`perfaudit/base/` the SPLIT baseline; `perfaudit/ab_v1/` the dropped road variant), not the repo.

**Not verified**: the Mac. The cuts are shadow-pass and light-cluster work, which only the Mac's
GPU can time; the opengl3 counters show the triangles and the lavapipe bench the lights' per-pixel
cost in a small scene. The look was judged on opengl3 (the pixel diffs above), not on Forward+.

## 9bi. Buses and trucks in traffic, 2026-10-04 (agent branch `wt/big-vehicles`; VISUAL_ROADMAP #51)

The brief: a real LA street has city buses, box trucks and delivery vans, and the freeways have
semis; traffic was all cars. Now: a 40 ft city bus (the invented agency BASIN TRANSIT) running
lines on the avenues and stopping at its stops, a cab-over box truck (invented fleets) and a
sleeper semi with a 53 ft dry van, on the streets and the freeways. CLAUDE.md "Big vehicles" is
the reference; this is the story.

- **Bodies** (`tools/make_big_vehicles.py`, Blender 4.2 on `make_road_cars.py`'s pipeline - it
  imports that module and reuses the loft, the booleans, the raycast parts, the slots and the far
  twin; `--render` for Cycles previews). Bus: one flat-roofed loft (the van's ninth anchor and
  pinned tangents) with the windscreen and the sign window cut into the domed nose cap, window
  bands with posts and sliding vents, two plug doors on the kerb side (four leaves, own nodes),
  roof pod, round lamps, a folded bike rack, bull-horn mirrors; 43k triangles + a 10k far twin.
  Box truck: a cab-over loft plus a bevelled van body with rails, posts, a roll-up door, marker
  and tail lamps, frame, tank, steps, underride bar; 26k + 10k. Semi: a long-bonnet sleeper loft
  (the pickup's corners, the van's flat roof), chrome grille and bumper, tanks, stacks, fenders,
  fifth wheel; 41.5k + 11k, and the trailer (swing doors with lock rods, landing gear, skirts,
  tandem) as its own node on the kingpin, 1.8k + 3.6k. The cars' probe rays start 3-5 m out,
  inside a 12 m bus: the module patches `Surface.end_hit` / `side_hit` / `top_hit` to start
  further out (a dozen parts were dropped as "missed" before that).
- **In the game** they are Vehicle body types 9-11, so nothing else needed to learn about them;
  the work was in the contracts: the body is centred and scaled without the doors and the trailer
  (otherwise the semi's origin sat mid-rig and a snapped turn swung the tractor 7 m sideways);
  queues measure to a semi's trailer end (`rear`); `tyre_r` is the physics radius that makes a
  parked one stand where traffic stands it (CONTACT -0.339 -> -0.298 for the bus); the cabin
  measure called the bus's windscreen a LAMP (big glass at the very end below the belt) and saw no
  windscreen at all (its normal is nearly level) - both fixed in `CarCabin`, cars unchanged.
- **Lines and stops** are pure functions (no network, nothing streamed): `route_of()` gives about
  half the avenues a line number, `block_stop()` a far-side stop on about every other block per
  direction. The chunk asks the same function for the shelter and for its parked cars (none in the
  stop's kerb zone, decided after their rolls so nothing moves); the traffic asks it where to pull
  in. A bus at its stop: pulls 1.4 m toward the kerb, stands, doors swing open, kneels, dwells
  7-13 s, closes, pulls out.
- **Trailer**: a tractrix - the trailer's axle is dragged toward the kingpin each tick. Traffic
  turns are still snapped at the junction's centre (for every vehicle), and this is what makes
  the semi's look right: the tractor snaps, the trailer swings round behind it.
- **Frame cost** (`tools/geo_count.gd`, opengl3 800x600, main 96f86f1 vs this branch; traffic
  differs between runs, so part of the difference is which vehicles happen to be in view):
  downtown avenue `--spawn=2359.4,880,0,12,2`: 4.56 M tris / 3,488 draws -> 4.92 M / 3,644
  (+7.8 % / +4.5 %); west freeway `--spawn=200,1088,-90,-4,30`: 3.03 M / 2,923 -> 3.08 M /
  2,949 (+1.6 % / +0.9 %); by the 110 `--spawn=1930,600,180,-5,14`: 3.72 M / 3,117 -> 3.91 M /
  3,271 (+5.0 % / +4.9 %). Per vehicle: a near bus is ~43k + 4 wheel rigs (~1.3k each), the
  lettering 2 draws to 55 m, door leaves 2 surfaces each (they were 4). Build: 2-3 ms warm
  (smoke check), 40-80 ms the first time a model loads - inside `builds_per_frame` 1.
- **Checks**: `tests/big_vehicle_checks.gd` (builds, budget, hit -> physics, the trailer's swing,
  the pool, lines and stops, a bus at its stop, a car behind a semi at a red, a freeway semi).
- **Stills** (`shots/big-vehicles`): bus at a stop downtown by day and night (`BIG=bus`), a box
  truck in the queue at a red (`STREET=queue STREET_BIG=10 STREET_EYE=1`), a semi on the 110
  (`BIG=semi BIG_ROUTE=110`), close-ups of each body (`car_shot.gd --each=9,10,11`), the bus's
  seat rows and passengers through the side glass (`OCCUPANT=npc`).
- **Frame cost** (`still_shot.gd` GEO, opengl3, Broadway south from 6th St `EYE=2985,1.7,205,180,5`,
same load both ways): noon 6.15 M triangles / 3,406 draws with `BROADWAY=0`, 6.44 M / 3,431 with it
(+4.7 % / +0.7 %); 21:00 (different loads) 7.46 M / 4,811 -> 7.42 M / 4,582. A palace is about 15k
triangles in one mesh of ~7 surfaces. Stills on `shots/broadway` (README there).

**Not done / not verified**: no Forward+ look (the LED signs and the lit bus cabin at night
  NEED A MAC CHECK); the bus's door openings show a black interior (no stairwell or floor); the
  front indicators are clear lenses; turns are snapped (a real turning radius for long vehicles
  would need the street traffic to drive arcs); no bus stops in the Esplanade replica's own
  traffic (ReplicaTraffic has its own cars); the semi's lamp mesh runs straight behind the
  tractor whatever the trailer's angle; the semis and box trucks never park.

## 9bj. Street vendors: taco trucks, carts, umbrellas and the people at them, 2026-10-04 (agent branch `wt/vendors`; VISUAL_ROADMAP #52)

The brief (lead, from the owner's "make the graphics a million times better"): nothing on our
pavements sold anything. A real LA street has taco trucks at the kerb at night with a lit menu
board, a serving window and a generator, fruit and elote carts under big striped umbrellas,
bacon-wrapped hot dog carts outside the arena and the bars at night, paleta carts in the parks,
flower and balloon sellers at the downtown corners. CLAUDE.md's "Street vendors" note is the
reference; this is the story.

**What it is.** `StreetVendors` (`scripts/world/street_vendors.gd`, static) builds every stand in
code at real size - a 7 m step van (box cut round a 2.7 x 0.95 m serving window, propped flap
with an LED strip, a lit kitchen inside: hood, plancha with meat on it, fridge, shelves; a steel
counter outside with salsas, napkins and limes; a menu lightbox with three food pictures and
real TextMesh lettering; the name along both sides; bonnet, grille, mirrors, wheels, tail lamps,
a red generator on a rack behind the bumper), a fruit cart (ice tray of mango, watermelon,
pineapple, cucumber, jicama and papaya spears, cups, chile-lime and chamoy, a cooler), an elote
cart (the pot of corn with its lid tipped back, the esquites pot, mayo / chile / cotija / butter,
a hand-lettered card), a hot dog cart (griddle under foil, three rows of bacon-wrapped dogs, a
heap of onions and peppers, buns, bottles, a propane tank, a light pole with a string of bulbs, a
cardboard sign), a paleta push cart (printed sides of ice pops, two lids, bells on the handle) and
a flower stand (buckets of roses, sunflowers and the rest on a slatted stand, foil balloons on
ribbons) - and a market umbrella shared by the carts. One shader (`street_vendor.gdshader`), one
batch per kind a chunk. Names and menus are invented (`TRUCKS`: TACOS EL COMPA CHUY, MARISCOS EL
FARO AZUL, TAQUERÍA LA ESTRELLITA, BIRRIA LA CHAPARRITA, LOS PRIMOS TACOS & MÁS, EL REY DEL
ASADA). Triangles: truck 7.5k, fruit 4.1k, elote 2.2k, hot dog 3.9k, paleta 0.7k, flowers 7.5k.

**Where and when.** `plan_block(plan, ix, iz, hour)` is pure: each face of a block is a place
(downtown, midtown, industrial, a park, across from MacArthur Park, within 430 m of the arena, the
beach town / near the boardwalk) and rolls each kind against `ODDS`; a hashed schedule per vendor
(`SCHEDULE` +- 1 h; a quarter of trucks, most on the industrial blocks, work lunch) says whether it
is working at the hour the chunk is built at. Round downtown (9 x 9 blocks) that is 28 trucks at
21:00 and 7 at 13:00, 52 carts at 21:00 and 74 at 13:00 (smoke test). Trucks park in the chunk's
own parking lane (+x / +z faces), serving side to the kerb, nose with the traffic; carts stand
1.55 m in from the kerb, slid along the face to clear lamps, trees, cans and camps.

**How it plays.** A shot truck sparks (a prop on StreetProps classifies as metal) and never
breaks; a round through the window finds the cook. A cart is an `EncampmentItem`: rounds, a car or
a blast tip it over as a real body and it stays gone. The cook (`StreetVendor`) stands on the
truck floor (kinematic, out of the truck's collision) and ducks under the counter at gunfire; a
cart vendor runs like anyone and walks back after. Walkers near a stand stop at its queue
(`Pedestrian._plan_queue()`, `QUEUE_SHARE` 0.55, 12-40 s) and the vendor talks to them. After
dark the truck lights the pavement (a pool in the chunk's `shop_spill` batch and a `lamp_light`
omni), the hot dog cart's bulbs too. The truck's generator hums (`Sfx` "generator", a CC0 loop,
38 m reach).

**Traps.**
- The MultiMesh instance COLOR multiplies every vertex colour in the vertex shader, so it cannot
  carry the umbrella's second stripe without tinting the pole: the shader has the colours
  (`CANVAS2`), picked by INSTANCE_CUSTOM.a, and the smoke test checks the copy.
- A parked car skipped for a truck must still make every roll and count as parked: `_park_car`'s
  cap short-circuits the rng, so a missing car moved every later roll (and the walkers after).
- The menu lightbox face sat inside its own frame box and drew dark; and a flap tipped up 18
  degrees hid the truck's name from the pavement (now 5).
- The brushed-steel grain at 160 cycles a metre aliased into dark corrugation on every cart: it
  fades to its mean under a pixel now.
- The smoke test's shop-spill count and the camp check both counted the vendors (a pool in the
  same batch; a cart is an EncampmentItem): the chunk now counts its pools (`vendor_pools`
  meta) and the camp check skips `Vendor_*` items.

**Cost** (`still_shot.gd` GEO, opengl3 1280x720, `--quality=0`, the same EYE with
`STREET_VENDORS=0`): the night truck view 5,787,253 -> 5,868,306 tris (+1.4 %), 2,954 -> 2,974
draws; the day fruit cart view 5,634,670 -> 5,860,288 (+4.0 %, mostly the vendor and the two
customers standing in shadow range in front of the camera), 3,022 -> 3,061 draws. Cart draw
distance then cut 150 -> 120 m and their shadows 70 -> 45 m afterwards (not re-measured). A chunk with
vendors adds at most one draw per kind plus its shadow twin, one omni per truck or hot dog cart.

**Stills** (`shots/vendors`): `truck_night` (EL REY DEL ASADA downtown at 21:00, people waiting
at the window, the pool on the pavement), `fruit_day` (a fruit cart under its umbrella at noon,
vendor and two customers), `paleta_park` (a paleta cart on a park's edge at 14:00, vendor and
two customers), `stand_day` / `stand_night` / `stand_carts` (the stands alone,
`tools/glshot/vendor_shot.gd`: the hot dog cart's bulbs and the lit truck at night), and the
`*_before` frames with the vendors off. The arena hot dog still in the city was framed on a cart
that its face's camp pieces had pushed out (no cart in frame); its reshoot was lost to a
container restart - frame one with `tools/vendor_probe.gd KIND=hotdog --spawn=2300,1150,0,0`.

**Not done / not verified.** The Mac (Forward+): the lightbox and kitchen emission under AgX
and the umbrellas' backlight. Vendors appear and leave only when a chunk is built (the hour is
read then), so standing at one corner across dusk does not bring the trucks in. No vendors on
the boardwalk landmark itself or inside MacArthur Park (its edges only). The vendors wear the
crowd's clothes (no apron or cap); customers do not carry food away; no steam off the elote pot
or smoke off the griddle; the balloons are round foil only.
## 9bk. The Coral Line: a light rail line, 2026-10-04 (agent branch `wt/light-rail`; VISUAL_ROADMAP #53)

Number is provisional (9bf / 9bg reserved for local agents; the lead renumbers on merge).

**What it is.** One light rail line, Basin Metro's Coral Line (original name, coral colour, "C"
bullet, white / coral / black livery), as a DATA TABLE in `scripts/world/light_rail.gd`
(`ROUTE`, `PORTAL`, `STATIONS`, speeds, timetable). Default seed: 5.2 km, 7 stations - 7TH ST /
FLOWER (underground terminus, two stair kiosks in Flower's median), PICO / FLOWER (at grade),
WILLOW / FLOWER and RIVER / GEORGIA (on the structure), RIVER / CREST, RIVER / LAKE, RIVER / HILL
(at grade, the last a terminus in the beach town). Downtown on the real Flower St at 1:1: tunnel
to a portal trench south of 11th St (s 916-1084), at grade past Pico, then the structure from
south of Venice over the 10 (rail 28.0 m abs over a 20.5 m deck), round the corner (R 28 m) onto
River Blvd (the default seed's 24 m boulevard that plays Exposition), over the 110 and the 105, down
to grade at x 1381. 19 at-grade crossings, 17 gated. 4 trains (2-car articulated consists, 54.6 m),
a 309 s headway, 618 s a trip. CLAUDE.md "Light rail" has the whole contract.

**Files.** `scripts/world/light_rail.gd` (the line, pure), `light_rail_kit.gd` (a FULL chunk's works,
extends FreewayKit), `light_rail_system.gd` (the `LightRail` node in city.tscn: clock, trains, far
tiers, crossings, riders, strikes, sound), `rail_gate.gd`, `scripts/vehicles/light_rail_train.gd`,
`rail_section.gd`, `scripts/npc/rail_rider.gd`; shaders `lrv_body`, `lrv_glass`, `lrv_interior`,
`lrv_far`, `light_rail_far_line`; `tools/make_light_rail.py` (Blender, the car),
`tools/light_rail/` (probe, compile, rail_shot); `tests/light_rail_checks.gd`. Small hooks in shared
files: `city_chunk.gd` (`_road_slab()`, `_build_light_rail()`, `_lot_under_freeway()`,
`_mark_road()`), `traffic.gd` (outer lane on a rail street, stop at a closed crossing),
`weapon_fx.gd` (the `rail_vehicle` group is metal), `sfx.gd` (four names, synth fallbacks),
`macro_ground.gdshader` (`cut_rect`: the plane sinks under the trench), `city.tscn`, `smoke_test.gd`.

**Decisions worth knowing.** The structure's profile is the upper envelope of 5.8 % cones from
every point it must clear, then eased - grade-limited by construction. Every freeway the line
crosses at grade is crossed OVER (there was no crossing where the line "must" rise otherwise).
Nothing per train is ticked: trips are (time, nose s) tables from the speed limits with dwells;
the fleet fills the round trip and the phases make an arriving train the departing one (double-
ended cars; pantographs on the swapping ends). Gates are posed from `crossing_phase()` (seconds
closed / open), so a gate streamed in mid-closure is already down. LOD chunks build none of the
line: the system's one far mesh draws it from 150 m out, every piece inside the FULL works'
own, so where both draw only the detail shows. Trains past 340 m (3D) are lit boxes.

**Frame cost** (opengl3 stills, `still_shot.gd`, RAIL=0 vs on, same frame): from the air over the
line (EYE 2650,300,1500,153,-14 AGL) 2,293 -> 2,295 draws, 3.626 -> 3.632 M tris; on Flower at the
Pico station with two trains in (EYE 2377,4,1532,32,-6) 1,989 -> 2,130 draws (+7 %), 5.52 -> 5.68 M
tris (+3 %). rail_shot split there: works 170 k tris, riders ~35 draws, trains ~15 draws (one
vertex-coloured body material, doors merged while shut, only the body casts).

**Stills** (shots/light-rail): station by day and night with a train dwelling, a level crossing
with the gates down and a train coming, the structure over the 110 seen from its deck, the portal
trench, the line from the air by day and night.

**Not done / not verified.** Forward+ (the Mac) not seen: the glass trace, the clearcoat body and
the headlight spot need eyes. Police cruisers still drive lane 0 on a rail street (over the
trackway). The trench has no collision floor of its own; the player standing in it stands on the
GroundBody plane at y 0. Cars turning left across the line ignore it. The gong is a struck crossing
bell (no CC0 tram gong found); nobody has listened to any clip yet. Riders board and alight but do
not ride (they are gone at the door). The underground station has no platform below ground.


## 9bl. City birds: pigeons, gulls, crows, sparrows, 2026-10-04 (agent branch `wt/birds`; VISUAL_ROADMAP #54)

The brief (lead, from "make the graphics a million times better"): nothing in the city was alive
but people. Pigeons on plazas, pavements and park lawns that walk, peck, bob and burst up when the
player comes close, runs, fires or a car passes fast; gulls on the beach, the piers and the port;
crows on suburban wires and lawns; sparrows if cheap; realistic, not low-poly; one MultiMesh per
species; frame cost near flat. CLAUDE.md's "City birds" note is the reference; this is the story.

**Models in code, not Blender.** No CC0 photo-scanned bird exists on Poly Haven or ambientCG, and
a glTF cannot carry what the animation needs: every vertex has TWO poses, flight (VERTEX) and
ground (CUSTOM0.xyz + its normal in CUSTOM1), blended in the vertex shader by the instance's
`spread`. So `BirdMesh` builds each species at its real size in GDScript (as the palms and the
port kit are): a body lofted round a curved spine (deep pigeon breast, long flat gull, heavy crow
bill, round sparrow head; the spine's landmarks S_NECK / S_HEAD / S_EYE / S_BEAK are fixed
fractions so one atlas layout serves every species), eyes, legs with toes (tucked back under the
belly in flight), and real feather cards cut out of painted feathers: secondaries along the
forearm, tertials, primaries fanned from the hand to the wingtip, an alula, a covert sheet with
the greater coverts' scalloped edge, the tail fan (closed on the ground, spread in flight). The
folded pose lays each feather on the flank (`_snap()`: the body's half width at that height and
depth plus a layer, so primaries sit under secondaries under tertials under coverts - the order a
real folded wing shows) and flattens the primaries over the rump above the closed tail. Three
LODs: ~2.1k / ~450 / ~100 triangles. `tools/glshot/bird_shot.gd` is the fast loop (a lineup of
every pose in seconds, opengl3).

**Plumage**: `tools/birds/make_bird_textures.py` paints each species' 1024 atlas procedurally -
every feather with its shaft, barbs, vane splits and down, the species' pattern (the pigeon's two
black bars and tail band, the gull's black wingtip with white mirrors and white trailing edge,
the sparrow's rufous edges and white wing bar), contour-feather scallops on the body, eyes,
scaled legs, a whole wing from above for the far LOD; a mask (iridescence, morph region,
roughness) and a normal map. Pigeons come in their feral morphs (blue-bar, checker, dark, white,
red, mealy) through the instance colour; the neck and the crow carry a thin-film sheen.

**Behaviour** (`Birds`): see CLAUDE.md. Things worth knowing: the ground is a ray from the PLAN's
street height (the valley is a plateau 140 m up - rays from y 0 found nothing there); a flock
staged for a still must not flush from the player, whom the free EYE camera drags along
(`shot_calm`); kinematic traffic has no velocity, so the car check takes speed from position
deltas between its 2 Hz shape queries; crows on wires sit on the polyline StreetDetail draws
(`wire_point()`), rebuilt from StreetDetail's constants, and only where a ray finds the pole.

**Sound**: freesound.org is blocked from this box (403 at the proxy), so the clips are
public-domain field recordings (radio aporee on archive.org, Public Domain Mark 1.0, and one
Wikimedia Commons file): coos, a balcony flock's wing claps, crows (three European takes and one
American), sparrows, a gull close by (docs/ASSETS.md). Ambience still plays the far gull calls,
but places them on a real gull when there is one (`Birds.gull_at()`). The coos have other coos
under them (a balcony of pigeons); crow_0..2 are carrion crows, not American - swap them when a
public-domain American crow can be fetched (Commons rate-limited the USGS one).

**Cost.** CPU (`tools/bird_bench.tscn`, 220 pigeons all within 60 m, the cap, on this box with a
render running beside it): simulate 0.35 ms on the ground / 0.69 ms in the air, buffer writes
0.41 ms, per frame. First version 2.8 ms: appending to a packed array held in a dictionary copies
it every time; now one pass by index, and ground flocks tick every 2nd frame past 20 m and every
4th past 60 m. GPU (`still_shot.gd` GEO, opengl3 1280x720, Pershing Square looking north):
birds off (`BIRDS=0`)
5,761,480 tris / 2,755 draws; the survey's own flocks on 5,794,952 / 2,759 (+0.6 %, +4 draws);
a staged flock of 30 pigeons 4-15 m in front of the camera 5,878,835 / 2,759 (+2.0 %, +4).
Only the near birds cast a shadow, and that from the mid mesh (a shadows-only twin of the near
batch): with every LOD casting, the staged flock was +5.7 %. The beach bookmark had no flock in
view (identical numbers on and off).

**Stills** (branch `shots/birds`): `plaza_ground` (30 pigeons on Pershing Square, morphs mixed),
`plaza_flush` (the same flock a third of a second after the camera flushed it), `plaza_before`
(BIRDS=0), `beach_gulls` (gulls on the sand between the two piers), `pier_gulls` (a flock
lifting off by the pier), `wire_crows` (crows on a power span in the valley suburbs),
`lineup` (`bird_shot.gd`: every species in every pose).

**Not done / next:** sparrows do not hop (they walk); no perching on benches, fountain rims,
statues or traffic signals (roof edges, wires and the ground only); gulls do not hang in the wind
over the surf or follow the ships; pigeons do not come for food the player drops; no feathers left
on the ground after a shot; flight paths do not avoid buildings (they circle 9-22 m up over open
ground and usually clear the low ones; a flock circling a downtown plaza can pass through a tower's
corner); the Forward+ look (SSS-less feathers, the sheen, backlight) is unjudged - only opengl3
stills were taken. Needs the owner's eyes on the Mac: the plumage's brightness under AgX (the
flying birds read very pale from below), and the flap rates at 60 fps.
## 9bm. Fire engines and ambulances that answer the chaos, 2026-10-04 (agent branch `wt/emergency`; VISUAL_ROADMAP #55)

The brief: the player blows up cars and knocks people down all day and only the police ever
came. Now the city sends fire and medics. CLAUDE.md "Emergency services" is the reference; this
is the story.

- **Bodies** (`tools/make_emergency_vehicles.py`, Blender 4.2, importing `make_big_vehicles.py`
  and through it `make_road_cars.py`; a helper agent built them and judged them in Cycles
  previews). A Type 1 pumper, 10.04 m: a flat-faced custom crew cab with a raised rear roof, a
  chrome-trimmed grille, an extended chrome bumper with a mechanical Q-siren and horns, a light
  bar across the cab's front edge, a pump panel each side behind the cab (gauges, valves, the
  steamer), roll-up compartment doors, a hose bed with folded hose, ladders racked over the kerb
  side, a tailboard, chevrons; 35k triangles + a 10k far twin. A Type III ambulance, 6.97 m: a van
  cab cut off behind the B-pillar with a module box, entry door and rear doors with windows,
  compartments, corner warning lamps, scene lights, striping and rear chevrons; 23k + 10k. New
  slots: `beacon_red`, `beacon_white` (the game flashes them), `stripe`, `satin` (roll-ups, pump
  panel, ladders, diamond plate) and `hose`. They are Vehicle body types 12 and 13 and
  `BigVehicles.is_big()` (truck wheels from WHEEL_POSE `axles`, mass x12 / x4.5).
- **Dispatch** (`Emergency`, a node in `city.tscn` like Police). Calls: a car burning or a wreck
  still in flames (CarDamage's own lists), a big blast with no fire at it, a fresh body (a Ragdoll
  in the debris group). A unit goes `response_delay` later, out of the nearest fire station (its
  bay doors roll up and it starts on the street in front) or along a street out of sight. Lane
  driving is PoliceCar's (copied: the cruiser carries the police's groups and crimes), siren and
  the wig-wag on; the traffic pulls over (`TrafficManager._siren_list()` takes `emergency_unit`).
  It pulls up at `StreetRoute.kerb_stop()` stood off the scene and stays kinematic there. A wreck
  burns for 14 s on its own; one with an engine coming is held burning (`CarDamage.hold_fire()`)
  so there is a fire to put out. A burning car still explodes on its fuse - that is the game.
- **Crews** (`EmergencyCrew`, Pedestrians): three firefighters (nozzle, backup, pump operator) in
  turnout tan with a helmet built round each rig's head (`FireHelmet`, from CrowdHatTable), two
  paramedics in blue and navy. The nozzle stands off the fire on the line from the pump panel; the
  hose is a tube laid from the panel along the street to the hands, the water streaks on a
  particle system (`hose_water.gdshader`), spray where it lands; `CarDamage.douse()` ->
  `extinguish()` (flames out, a burst of steam, the smoke pale and dying; a burning car is left
  smoking, a wreck stays a wreck). A paramedic kneels at the body with a bag; the other fetches the
  cot from the back, pushes it to the body, loads it (the ragdoll goes, a blanketed patient lies on
  the cot) and wheels it back. Then they climb in and the unit leaves; unseen, it is pooled.
  Shooting or knocking a responder is a crime like anyone's (Pedestrian.knock); their bodies are
  not calls. Kneel / hose / push poses are RoughSleeper's aim tables solved per rig over the idle.
  A CharacterBody3D does not step: blocked kerbs stopped every crew member dead in the first runs,
  so they step up 0.34 m where there is room, and board when pressed against the wrong side of
  their unit.
- **Fire stations** (`FireStation`): one per 850 m cell where a hash says so and the block under
  the hashed point is ordinary buildings in a station district, on that block's biggest deep edge
  lot clear of the freeway (`CityChunk._build_lot()` asks after its own rolls). A brick firehouse,
  two sectional bay doors (their own nodes, `open_door()`), a lit bay interior, an apron and a ramp
  across the pavement to the kerb, STATION nn and RANDO CITY FIRE DEPT over the doors, a flagpole;
  parked cars keep off its kerb (`keeps_clear()`); one `lod_box` far away. 10 stations in the 49
  cells round the spawn.
- **The bus's front** (from 9bi's stills): a bus's traced cabin is daylit (`CarCabin.BUS_DAYLIGHT`
  2.2, and more of it through the glass) and its far twin starts at 60 m, not a car's 30.
- **Sounds**: `siren_yelp` (the ambulance) and `fire_horn` (the engine's air horn every few
  seconds on a call) are SYNTHESISED fallbacks only: the CC0 recording found for them (Wikimedia
  Commons `File:Whelen.ogg`, CC0, "Whelen emergency siren tones Wail/Yelp/Piercer used on a Fire
  Engine") could not be downloaded - upload.wikimedia.org answered 429 to every request from this
  box all session. Fetch it, cut a yelp loop and a piercer/horn one-shot, add them to Sfx.SAMPLES
  with their SAMPLE_LOUDNESS_DB and a row in docs/ASSETS.md. The engine's own siren is the
  existing police wail pitched down.
- **Frame cost** (`tools/geo_count.gd`, opengl3 800x600): downtown avenue
  `--spawn=2359.4,880,0,12,2`, main vs this branch: 5.090 M tris / 3,734 draws -> 5.090 M / 3,734
  (no station or call in view: flat). In front of Station 79 `--spawn=2894.05,397,-152.1,8.28,1.7`,
  `FIRE_STATIONS=0` vs on: 4.18 M / 4,262 -> 3.48 M / 4,259 (the firehouse replaces a taller
  building; part of the difference is traffic). A unit on a call adds its body (35k / 23k near,
  10k far twin, one draw a slot: 12 / 11 surfaces near), four truck-wheel rigs, two lens materials
  and, per crew member, a crowd rig; a hose is one tube mesh and two particle systems. Units and
  crews exist only while a call is open (caps 2 engines, 2 ambulances).
- **Checks**: `tests/emergency_checks.gd`, 34 (builds, lights, a hit, extinguish, the stations
  pure / chunk / far city, an engine at a wreck puts it out and leaves, an ambulance takes a body
  and leaves, a unit sent through the streets with its siren that the traffic sees, a responder
  down is not a call, the sounds). The emergency checks run about 80 s of the smoke test.
- **Stills** (`shots/emergency`): fire day and night, the hose, a paramedic at a body, a fire
  station, close-ups of both bodies, the bus front before and after.
- **Not done / not verified**: no Forward+ look (NEEDS MAC CHECK: the lenses and the roof light at
  night under AgX and glow, the hose water, the turnout gear and helmets); the siren yelp and the
  air horn are synthesised (see Sounds); no nozzle mesh in the hands (the stream starts at them);
  the stretcher and the bag are simple code boxes; the unit's lane driving is a copy of PoliceCar's
  (a fix to one does not reach the other); a unit knocked off the lanes only rejoins them upright
  and still; encampments and parked cars keep off a station's apron, other street clutter is not
  checked; there are no ladder trucks, police at fire scenes or traffic cones; the bus's daylit
  cabin is judged on opengl3 only.

## 9bn. Rec parks, schoolyards and sports grounds, 2026-10-04 (agent branch `wt/parks`; VISUAL_ROADMAP #56)

The brief: from the air real Los Angeles is stamped all over with baseball diamonds, basketball
and tennis courts, soccer fields, school running tracks and public pools; ours had lawns, trees
and fountains and none of those. CLAUDE.md "Nor is a park just a lawn" is the reference; this is
the story.

**Where they go.** `Parks.role_for()`, from `CityPlan.block()` after every other roll and
override (a hash of seed + block): 60 % of the PARK blocks in the suburbs, midtown and the beach
town become rec parks; of the BUILDINGS blocks, 3.5 % (suburbs) / 2.5 % (midtown) become rec
parks and 8 % / 4.5 % schools (the new `BlockKind.SCHOOL`). `CityPlan.lots()` is empty on both, so
the LOD ring, the far city, AirTraffic and HouseKit see no buildings there. Never on or beside a
site, under a freeway, near a landmark, in the replica, the runway clear zone or downtown. In the
window `(-1500, -3600) - (1500, 1500)` on seed 1337: 40 rec parks, 4 schools (one high school),
15 diamonds, 13 soccer fields, 32 basketball court groups, 15 tennis groups, 25 playgrounds,
5 pools, 9 rec centres.

**The track problem.** A regulation 400 m track (84.39 m straights, 36.5 m radius, 1.22 m
lanes) round a football field needs ~172 x 88 m of ground. Suburban blocks are 60-100 m long
(p90 103 m); one midtown block in the whole basin fits it. Merging two blocks into a site that
closes the road between them (as MacArthur Park does) would have touched traffic, roads, the
minimap and every system that asks `road_open()`, so a school stays one block and **its track is
the largest that fits** (`Parks._track()`): 400 m where it can be, else the radius and straights
shrunk (the default seed's high school is 337 m, 4 lanes), the football field regulation or
scaled to fit inside the kerb (0.55 at least). High schools only where the block is >= 140 x 72
m; elementary schools elsewhere (grass field, playground, yard games, bungalows, lunch shelter).

**How it is drawn.**
- Ground: ONE mesh a FULL chunk (`ParkGround`, `shaders/park_ground.gdshader`, no shadow). Each
  piece carries its facility's own frame in UV (home plate or the centre at the origin, a along
  the long axis) and the facility's numbers in UV2, so every line is analytic and box-filtered
  (`aline()`: crisp up close, its average cover once under a pixel): soccer (FIFA markings scaled
  for a youth field), the diamond (skinned infield out 60 ft from the pitcher, home circle, base
  paths, warning track, chalk foul lines, batter's boxes, pitcher's circle, on-deck circles, the
  outfield's checkerboard mowing, drag rings), basketball (FIBA: key, free-throw circle, 6.75 m
  arc with its corner straights, restricted arc; acrylic in four palettes, or lines alone on a
  school's asphalt), tennis (doubles, singles, service boxes, centre mark; three palettes), the
  track (lane lines, finish and start lines, kerb; the football field inside with yard lines,
  hash marks, end zones in the school's colour), poured rubber, decomposed granite, concrete
  deck, asphalt with the drop-off loop's markings, yard games (four-square, hopscotch, a circle),
  lawn.
- The pool is TRACED like the windows: the view ray refracted (and wobbled by ripples) into the
  tank, the floor's tiles and lane T-lines or the wall's tiles and waterline band, absorbed toward
  turquoise with the path length, caustics by day, underwater lights by night; Fresnel sky
  emitted on top; lane ropes floating red at the ends, white and blue between.
- Everything upright: ONE casting mesh (`ParkWalls`, `shaders/park_walls.gdshader`) written by
  `ParkKit` through IndustrialKit's box and cylinder writers: chain-link and windscreens, tennis
  and soccer nets and hoop nets (cord or chain) cut out, backboards with the shooter's square,
  goal posts, a curved backstop with its padding, CMU dugouts, aluminium bleachers, a grandstand
  with its press box, play structures and swings, floodlight poles whose lenses blaze after dark
  (and throw `park_pool` light pools), stucco rec centres and classroom wings (windows, doors, lit
  rooms at night), covered walkways, picnic shelters, a pool's coping, ladders and guard chair.
- LOD chunks and the far city: the ground as slabs that PARTITION the site (`Parks.minus()`; the
  track as an infield of turf and a red ring, the diamond as clay and turf), the buildings,
  shelters and stands as `lod_box`es.

**People.** `ParkGoer` (a Pedestrian kept to its facility, living the crowd-life layer): track
joggers lapping their lane on the oval, the loop's joggers, pickup basketball (3-6 a court),
a kickabout, fielders at their positions, parents at the playground, people at the picnic
tables; `MAX_PEOPLE` (18) a chunk under the city's crowd cap. A `ParkBall` is dribbled, shot at
the nearer rim on a high arc, drops through and bounces to the nearest player (scripted, nothing
past 90 m). No children (there are no child rigs); no swimmers.

**Traps.**
- The block's pavement slab tops out at SIDEWALK_TOP: the pool water, first dropped 12 cm under
  the deck, was under it, and what showed was the pavement (grey concrete squares).
- `_fit()` turns a facility to fit; a row of courts must then be told which axis its courts run
  along (`_along_x()`): three tennis courts side by side are longer across than along.
- A HDR emission (the floodlight lens) must not go through the sRGB curve: `to_lit()` is applied
  to the clamped colour and the gain after.

**Coverage** (`tools/lot_coverage.gd`, seed 1337, `RECT=-1500,-3600,3000,5100`, the basin west of
downtown; before `PARKS=0`). New kind `sport` (fields, courts, track, pool, yard, walks) and rows
`REC` / `SCHOOL`; a rec park or school is counted in its district's row as well. Before, PARK
blocks were not counted at all (lawn and trees) and the converted BUILDINGS blocks were houses.

| Row | before | after |
|---|---|---|
| SUBURBS | 104 blocks: bare 8.3, built 30.8, garden 56.9 % | 117 blocks: bare 7.2, built 25.9, garden 53.6, sport 9.1 % |
| MIDTOWN | 262 blocks: bare 5.1, built 41.3, forecourt 38.6 % | 276 blocks: bare 4.8, built 38.4, forecourt 35.6, sport 4.6 % |
| BEACHTOWN | 50 blocks: bare 4.2 % | 53 blocks: bare 4.1, sport 1.8 % |
| REC (39 blocks) | - | built 2.9, parking 3.6, garden 40.7, sport 52.8 %, bare 0 |
| SCHOOL (4 blocks) | - | built 11.8, parking 8.1, sport 80.1 %, bare 0 |

**Frame cost** (`tools/geo_count.gd`, opengl3 800x600, `--quality=0`, noon, 90 frames; before
`PARKS=0`, the same commit; the spawns see different things before and after, which is the
point - a rec park's fields are lighter than the old park's ~30 trees and ground cover):

| Spawn | triangles | draws | objects |
|---|---|---|---|
| High school, the street in front `966,800,0,-12,6` | 5,573,932 -> 5,272,590 (-5.4 %) | 5,313 -> 4,662 (-12.3 %) | 21,308 -> 20,669 |
| Rec park courts, eye level `-262,-2486,10,-6,2` | 7,679,841 -> 5,039,083 (-34 %) | 4,072 -> 3,976 (-2.4 %) | 15,985 -> 15,889 |
| Rec park diamond, 90 m up `52,-20,0,-35,90` | 13,224,535 -> 7,747,123 (-41 %) | 6,875 -> 6,585 (-4.2 %) | 17,404 -> 17,109 |

`still_shot.gd` (1280x720): the suburb aerial `EYE=1911,150,4260,0,-42` (AGL) 4,303,087 / 3,262 ->
4,204,408 / 3,254. A FULL chunk's kit is 5.9k (the high school) to 9.3k (a full rec park)
triangles in one mesh; the ground one mesh; the pools one batch.

**Stills** (`shots/parks`): the suburb aerial before and after, a rec park aerial, the high
school's track aerial, pickup basketball at eye level, the diamond from the bleachers, the track
and football field, the diamond at night under the floodlights, the pool from above and at eye
level, a playground and rec centre, the track at night.

**Checks**: `tests/park_checks.gd` (13 in the smoke test): both shaders handle every kind; roles
only on city ground in the right districts with no lots, a school is SCHOOL; every facility in its
site, none on another, regulation sizes (court rows run the right way, 400 m at most, the
football field inside the kerb), plans pure; counts across the basin; a jogger's oval maps onto
itself; a FULL rec park and school: one ground mesh, one walls mesh, no Building, pools
shadowless, a kit budget, people's spawn steps; LOD builds no meshes; the far city's capture lays
partitioned slabs (0 overlaps) covering the site and far boxes.

**Not done / not verified**: no Forward+ look (the pool trace, the floodlight glow, the acrylic
and turf under AgX: NEEDS A MAC CHECK); no children or swimmers; the playground structure and
the people's "games" are simple (pickup players run between spots, fielders stand; nobody
throws a ball - only the basketball is scripted); the far city averages a park block into one
plate colour (the LOD ring shows the fields); tracks are rarely 400 m (the blocks are too small);
fences have no collision. Flaky checks seen across six full runs, none in parks' code: the
wreck-on-the-deck toss once (2.70 m against a 2.6 m limit, in the test room), the bus's
"its signs show its line" once (line 0; passed in the runs either side on the same code), and an
error in `StreetVendors.free_queue()` (`rec is Dictionary` on a freed node) once - guarded on this
branch (one line in scripts/world/street_vendors.gd; the vendors' owner may want to look). The
light rail's structure keeps parks and schools off its blocks (`LightRail.blocks_rect()` /
`cuts_in()` in `role_for()`).
## 9bo. Billboards and supergraphics, 2026-10-04 (agent branch `wt/billboards`; VISUAL_ROADMAP #57)

The brief: LA's streets and freeways are lined with billboards and the city had one roof-plant box.
Now `Billboards` (`scripts/world/billboards.gd`; CLAUDE.md "Billboards" is the reference) builds,
in code at real sizes, rooftop bulletins (14 x 48 ft) on I-beam legs with a kicker and a ladder,
real posters (12 x 24 ft) where Building's own roof-plant billboard roll always stood, V-shaped
monopoles in the freeways' right of way, perforated vinyl supergraphics on glass and panel
towers, and a double-sided lightbox at every bus shelter. Each face is a unit of one frame kit:
face, trim, back sheet with panel lines, stringers, uprights, X-bracing, a grated catwalk with a
rail, five (three) lighting arms with fixtures.

- **Placement** is hashes only and happens last: `on_building()` after each Building in
  `_build_lot()` (both levels), `block_step()` after Industrial's, and `commit()` in a deferred
  step before the finish (every board one breakable `"billboard"` prop, 300 hp, collision on
  StreetProps). The block's other props keep their positions and ids (checked with Billboards on
  and off). Rooftop bulletins only on lots on the pavement (`lot.edge`): the first pass put boards
  on lots deep inside midtown's big blocks, 150 m behind the street. Monopoles: a corridor lot, both
  face ends and the faces' whole footprint clear of every deck (the downtown freeway check reads
  the far boxes' axis-aligned footprints - it caught the first V at 2.3 m from the deck edge),
  140 m apart.
- **Far**: LOD chunks and the far city's capture keep each face as the roof plant's PANEL far box
  in its ad's mean colour (`BillboardTable`), lit after dark, LED boards self-lit, and the pole as
  a MAST; `building_lod.gdshader`'s PANEL branch draws the frame round the face.
- **Art**: `tools/make_billboard_art.py` (PIL, seconds) - twelve invented campaigns (THE LAST
  ORBIT, FIZZLY, LUMEN X, RAMIREZ & KOLB with a 555 number, ZAPWOLF, SAND & SMOKE on HALCYON+,
  SUNCREST AIR - the airport's sunset carrier -, STARDUST DRIVE-IN, CASA LUNARA, CORVO ARIA, 104.1
  THE DRIFT, THE HOLLOW HOUSE) and STRIDE CO. on the portraits. The face shader does the wear per
  instance: paper sheets a hair off register with seams, sun fade (reds first), torn patches with a
  white fringe showing the poster under them, the vinyl's sheen and edge ripples, mesh vinyl's
  perforations, welds and hem, rain run-off, the lightbox, LED slides every 8 s with the dot pitch,
  and the fixtures' night wash.
- **Frame cost** (`tools/geo_count.gd`, opengl3 800x600, `BILLBOARDS=0` vs on): midtown bulletin
  block `--spawn=1030,1662,52,20,2` 4.894 M tris / 4,392 draws -> 4.914 M / 4,434 (+0.4 % / +1.0 %);
  by the 110 `--spawn=1893,640,0,14,2` 3.624 M / 3,574 -> 3.636 M / 3,618 (+0.3 % / +1.2 %). A
  bulletin unit is ~1.9k triangles (frame) + 0.5k (legs) + 2 (face); a chunk with boards adds 3-9
  batches plus their shadow passes.
- **Tools**: `tools/billboard_probe.tscn -- --spawn=x,z` (headless: counts the boards in the far
  captures round a point, lists the monopoles, the strip roads and the shelters, and with
  `BB_DEBUG=1` every face with an EYE); `tools/glshot/block_shot.tscn` gained `NIGHT=1` (a crude
  night with the lamp globals on).
- **Checks**: `tests/billboard_checks.gd` (atlas and table, the shader's grid, boards as props in
  one batch per kind, LOD/far boxes, monopoles pure and clear, nothing else in the block moved).
- **Stills** (`shots/billboards`): midtown rooftop bulletin by day and night, its profile, the
  110 with a monopole by day and night (one digital), a supergraphic on a glass tower, bus
  shelter lightboxes, the atlas.
- **Not done / not verified**: no Forward+ look (the night wash and LED brightness under AgX and
  auto exposure NEED A MAC CHECK); the "strip" avenues are rare in midtown (22 % of wide roads;
  `STRIP_SHARE`), so a Sunset-Strip-dense stretch is not guaranteed near any bookmark; landmark
  towers' blank uv_facade walls carry no supergraphics (only Building towers); boards do not cast
  light on the street (emission only); the face's night wash is drawn, not a light.
## 9bp. The Los Angeles River: the concrete channel and its bridges, 2026-10-05 (agent branch `wt/la-river`; VISUAL_ROADMAP #58)

Number is provisional (the next free one after 9bm when this was rebased; the lead renumbers on merge).

**The brief** (lead, from the owner's "make the graphics a million times better"): the game had
nothing where the real river runs - just east of downtown, past the Arts District, under the 101
and the 10, south through Vernon to Long Beach. Build it as its concrete flood channel, with the
arched viaducts, the freeway crossings and a rail bridge, drivable (the classic chase location),
from the air too. CLAUDE.md's "The Los Angeles River" note is the reference; this is the story.

**Where it runs, and why there.** At 1:1 from Pershing Square the real river would stand in the
east range (the real 6th St bridge maps to x 5205; the range starts at 5000), so `LaRiver.CONTROL`
keeps the real ORDER and compresses the distance, as the port did: 200-650 m east of Vignes past
downtown (the Arts District between them, the river its east edge), crossing the pinned real
streets - so the streets the real river is bridged by are bridged here too - the 101 130 m from its
east end, the 10 where it bends for the East LA interchange, the 105 where the real one crosses it
(Lynwood), and out across the industrial south to the bay's north shore east of the port (Long
Beach). The 110 runs west of the real river all the way to San Pedro and never crosses it; the
brief asked for a 110 crossing and there is none, on purpose. Default seed: 8.43 km, 1,055 centre
points every 8 m; north end at the foot of the front range (a headwall with two box culverts:
the Glendale Narrows' mouth stands for the river's way in), mouth at (4138, 6222).

**The land, not a cut.** CityStreamer's GroundBody (a 14 km box, top y 0) is under the whole map
and the city's ground is the relief over it, so a channel cut below 0 would put the player and
every wheel ray on the GroundBody. Instead the land is lifted: `LaRiver.top_at()` is the city's
relief along the centre line smoothed over +-200 m, never lower than the channel needs (bed over
MIN_BED, 0.62 m), the bed only falling downstream; `terrace()` blends the relief to it inside the
corridor and over 170 m outside (`MacroMap._relief_at()`; `_relief_natural()` is the relief
without it). On this seed the land is 7.5 m along the downtown stretch and 7.1 m south of the 10 -
the channel reads as a levee-banked river. Streets climb to it at 2-4 %, the bridges are flat
(the street's own road slab is the deck), the freeway decks rise with it (8.4-9.5 m over the
banks where they cross).

**The grid.** `LaRiver._classify()` takes every road segment whose rect (with its end junctions)
reaches the corridor, in runs; a run is one crossing. A BRIDGE needs one crossing of the centre
line, under 52 degrees of skew, both ends clear; then the real bridged streets get their design
(NAMED_BRIDGES: Cesar Chavez, 1st, 4th, 7th the arch viaduct, 6th the tied-arch ribbon, Olympic,
Temple, Venice girders), avenues 55 %, other streets 16 %. Anything else is CLOSED: it ends at the
bank (a row of concrete barriers, RiverBuild._stub_ends()), and because `CityPlan.road_open()`
asks `LaRiver.road_open()`, traffic U-turns short of it, police route round it, the minimap and
the respawn know. Default seed: 18 bridges, 178 closed segments, 130 river blocks. A river block
(`CityPlan.river_block()`) has no lots and builds no seeded block; walkers never plan a crossing
onto one.

**What a river block builds** (RiverBuild, time-sliced: 3 channel segments, one land row, one
prop kind, one bridge job a step; the worst step on this box ~25-45 ms against a Building's
10-20): the channel cross section per owned 8 m segment - the low-flow notch, the bed in two
strips, both banks, the coping - on one concrete material, the water sheet, outfall headwalls and
pipes (and their stains, painted by the shader on the same hashed slots), sediment bars with reeds
and shrubs, the ramps (10.5 %, a kerb wall, the coping opened at the head), the north headwall and
the mouth's end walls and apron; then the land per 12 m cell cut exactly with Geometry2D: the bank
roads, the closed streets' stubs, a pavement ring with street lamps, and the yard - one surface a
block on Industrial's ground material, chain-link along the bank roads (Industrial._fence()), up to
five storage yards and trailer drop rows (Industrial._store(), IndustrialKit.trailer), scrub, and
the freight tracks that run along both banks in LA (ballast, ties as a batch, rails, strings of
boxcars and tank cars); ONE trimesh RiverBody with backface collision for all of it.

**The bridges** (RiverBridges, original designs in the real ones' forms, none named): ARCH - three
open-spandrel arches on cutwater piers parallel to the current (skewed under the street), four ribs
with spandrel columns, solid spandrel walls over the banks, a moulded fascia and cornice, a turned
balustrade (the balusters one batch, `rv_baluster`), twin-lantern standards every 16 m, stepped
corner pylons with lanterns; RIBBON - three spans of white tied-arch rib pairs leaning outward,
cable hangers, an LED strip under every rib (river_lamp.gdshader, by `lamp_factor`), a steel rail
with cable infill, slim LED poles; GIRDER - a box girder on bents of round columns under a cap
turned to the current, a concrete barrier with a steel rail, cobra-head lamps; RAIL - plate girders
stiffened every 1.5 m on concrete piers, the track run on over the bank roads (set in them) to
buffer stops. Lit lamps are `lamp_light` OmniLights (every second standard) with `lamp_pool`
pools. Freeway bents standing in the channel go down to its floor (FreewayKit, the far city's
pillars too); no off-ramp lands in the corridor (Freeway._place_ramps(); the side still
alternates so the other ramps stay where they were).

**From the air.** LOD chunks build the same channel at a 16 m step with no props or lights and no
relief floor (it would lie over the channel). The far city's capture (`RiverBuild.capture()`)
records thin land slabs in 8 m z slices round the channel, the bed, the water and the banks as
tilted boxes per 32 m, and each bridge's deck; Skyline sinks a river block's plate to the bed
(`far_plate_drop()`) and plants no street trees on it. `MacroMap.bake()` paints the channel on the
horizon plane; the minimap draws it and its bridges.

**Shaders.** `river_concrete.gdshader` (ONE material a chunk; kind in COLOR.r/8): form-panel and
lift joints, streaks run down the slope, old water lines, the tide line and algae at the toe,
efflorescence, silt fans and algae strands on the bed, tyre tracks, the outfalls' rust trails
(ihash() = LaRiver.ihash(), lowbias32, checked), board-formed bridge concrete, wet piers; graffiti
from the street wear tag atlas (mostly throw-ups and roller letters, 3-5.5 m tall, two colours, worn,
some buffed in a grey that never matches); rain darkens it. `river_water.gdshader`: riffles carried
down the current and standing ones over the concrete, foam streaks, the algae fringe, the sky
emitted by Fresnel (capped). Both include color_space.gdshaderinc and work in linear.

**Checks** (`tests/la_river_checks.gd`): the route south all the way, its bed falling and over y 0,
east of Vignes, the corridor's ground at the top level, the mouth on the bay east of the port; the
101 / 10 / 105 cross on decks clear of the banks and the 110 never does; the real bridged streets
bridged in all three designs; a rail bridge and the ramps; no open street drops into the channel
unless it is a bridge and no lot in the corridor; the hashes; a FULL chunk's meshes, collision and
lit lamps, LOD without lights or a relief floor, the capture as boxes; a car dropped on the bed
stands on it and a car rolled down a ramp goes down into the channel upright.
`tests/downtown_checks.gd` skips river blocks in its "nothing under a freeway" box test (their far
boxes are the channel's banks, which the freeways cross).

**Tools.** `tools/la_river/probe.gd` (headless, seconds: route, profile, bridges, ramps, rail, river
blocks, freeway crossings), `tools/la_river/river_bench.tscn` (a chunk's build steps, FULL / LOD /
capture), `tools/la_river/river_shot.tscn` (the river's chunks alone, `CAR=1` a sedan rolling down
a ramp), and still_shot.gd EYEs. `RIVER=0` in the environment (or `-- --no-river`) is the A/B.

**Frame cost** (`tools/geo_count.gd`, opengl3 + Xvfb, 800x600, `RIVER=0` against the river, same
spawn): on the 1st St bridge 2.02 M -> 1.46 M triangles, 2,393 -> 1,606 draws; at the 6th St
ribbon 2.56 M -> 1.42 M, 2,677 -> 1,768 (the river blocks build no buildings, and their channel,
ground and fences are a handful of meshes a chunk); the default downtown spawn 7.06 M / 3,763 both
ways. A FULL river chunk is ~1.6-7 k triangles of concrete (the 1st St chunk with its arch viaduct
and the rail bridge 6.9 k plus the instanced balusters), 0.5-1 k of ground, one collision body;
LOD 1.3-3.2 k; the far city 40-100 boxes a river block. Build: a FULL river chunk 140-280 ms over
40-60 steps (the worst step 25-45 ms: the arch viaduct's core job, the fences), LOD 40-75 ms, the
capture 3-8 ms (`tools/la_river/river_bench.tscn`).

**Stills** (shots/la-river; opengl3, not the Mac's Forward+): from the 1st St viaduct along the
channel by day and at dusk, down on the bed by the low-flow channel, a sedan rolling down an access
ramp (river_shot.tscn), the river from the air south of downtown, and at night the arch viaduct's
lanterns and the ribbon's LED arches from the bed.

**Not done / not verified.** Forward+ (the Mac) not seen: the concrete's tone, the water's
mirror and the lamps' glow under AgX need eyes. Traffic never drives the channel (it is a place
for the player and the police chase; nothing routes into it). The bank roads are drivable but no
traffic or police uses them. The yards' remainder is still mostly open gravel in the biggest river
blocks. The north end stops at a headwall with box culverts rather than continuing up the Glendale
Narrows into the valley. The far city's land slabs on a river block step every 8 m along the
channel's edge (under a pixel past ~500 m). Sediment bars and reeds are FULL only. The Coral Line
(9bk, not on main when this was written) does not reach the river; the rail bridge carries a
freight spur that ends at buffer stops past the bank roads.

## 9bq. More everyday car bodies: hatchback, SUV, minivan, taxi, beater, 2026-10-05 (agent branch `wt/more-cars`; VISUAL_ROADMAP #59)

The brief: a real LA street is full of compact hatchbacks, full-size SUVs, minivans, taxis and a
beater or two; traffic had four Blender bodies (sedan, crossover, pickup, van), the exotics and
the Meshy sports car, so the street repeated. CLAUDE.md "More everyday bodies" is the reference;
this is the story.

- **Bodies** (`tools/make_more_cars.py`, imports `make_road_cars.py` like the big vehicles do;
  about 80 s for all five, `--render` for Cycles previews; the beater adds `close` and `dent`
  views). The four lofted bodies are specs plus DATA for one detail builder,
  `everyday_details()` (`spec["d"]`: lamps - blades with DRL and projector eyes, round lamps, or
  an old car's sealed lens with an amber corner -, grille mouth with an egg-crate or chrome bars
  and a chrome surround, lower intake, fogs, bumpers, door and hatch gaps, B/C/D pillars, belt
  trim, rocker, rub strip, roof rails, sliding-door tracks, spoiler, tail lamp pieces, mirrors,
  dents, an `extra` callback). `overhangs()` + `remap()` rescale a spec's overhangs without
  touching the wheelbase (how the first, too-long hatch, minivan and beater were brought to size).
  Hatchback 4.36 m (51k + 7.9k far), SUV 5.51 m x 1.87 m (48k + 7.9k), minivan 5.18 m (52k +
  7.9k), beater 4.79 m (51k + 7.9k), taxi = the sedan + sign (54k + 7.9k): inside the road cars'
  budget. The taxi's sign is a ninth slot `taxi_sign` (a bevelled lightbox on a black base and
  feet, a chrome cap line); the run prints its box (TAXI SIGN), which `taxi_sign.gdshader`'s
  `sign_center` / `sign_size` copy.
- **Rolls**. `BODY_ODDS` is now the shares (hatchback 70, SUV 80, minivan 55, beater 35; sports
  145 -> 85, van 115 -> 75, sedan 250 -> 210, pickup 150 -> 120, crossover 220 -> 190, the
  exotics a third less) and `Vehicle.ROLL_MAP` the 0-999 ranges: each old type keeps the START of
  its old range, so a seed's parked sedan stays a sedan unless its roll fell in the slice the
  hatchbacks took (the avenue bookmark's parked white sports car is a hatchback now, the rest of
  the row unchanged). `random_car()` makes the same rng calls (checked against a replay of them).
  The taxi is NOT in the table: the sedan's taxi roll (`TAXI_SHARE`, unchanged) now builds
  `BodyType.TAXI`, so the old taxis are exactly the new ones and no `LiveryProp` box sign is made
  for them. `look_seed` keeps random_car()'s look on the car (fleet number, beater door).
- **Taxi**: TAXI livery paint (yellow, checker band), lettering (`_add_taxi_lettering()`:
  BASIN CAB on the front doors, a number on the rear, BigVehicles' shared TextMeshes, 55 m, not
  on the web), the sign shader (cream lightbox, "TAXI" in stroked capitals front and back, read
  the right way from either end, emission `glow_day` + `glow_night` x lamp_factor), and a fare:
  `_cabin_seats()` returns 5 for `TAXI_FARE_SHARE` of traffic taxis. **CarCabin seat bit 2** is
  new (the bench behind the passenger, the passenger's colours); `person()` takes the seat
  back's z; bit 1 is now tested as a bit (it was `seats > 1.5`); the occupant key's shifts moved
  up a bit to make room.
- **Beater**: 1990s notchback proportions (upright screens, short flat deck, thick C-pillar,
  sealed-beam lamps, slot grille, chrome strips, narrow tyres, black plastic bumpers). Geometry
  wear: `BEATER_DENT` pushed into the right rear door after everything else is built; the right
  tail lamp is four red pieces with dark cracks between, a broken corner showing the housing and
  silver tape across. Paint wear (`car_paint.gdshaderinc`, `wear` > 0 only on a beater, so every
  other car pays one uniform branch): the left front door in another colour (`BEATER_DOOR` in the
  body mesh's space; colour from `BEATER_DOORS` by look seed, never the car's own), a feathered
  primer patch on the right front wing, the clear coat faded everywhere and chalky in patches on
  what faces the sky, rust low on the sills. Works on the damage variant too (same include).
- **Contracts**: kinematic traffic, `go_physical()`, CarDamage, CarCabin (measured per body; SUV
  and minivan have privacy glass), CarLights (`lamp_y` / `tail_y` per body), pools (ordinary
  cars), PhysicsBudget, parked cars - all through the existing paths; `tyre_r` tuned so a parked
  one settles where traffic stands it (car_shot CONTACT within ~1 cm).
- **Frame cost** (`still_shot.gd` GEO, opengl3 1280x720, the avenue `--spawn=2359.4,880,0,12,2`,
  main a0ee161 vs this branch; traffic and parked cars differ between the runs): 7.53 M tris /
  3,720 draws -> 7.39 M / 3,805 (-1.9 % / +2.3 %). Build: 1.4 ms warm in the check (headless);
  the first load of each .glb is the importer's, as for every body.
- **Tools**: `car_shot.gd` now routes only 12-13 to EmergencyCar and 9-11 to BigVehicles (it
  sent every type >= 12 to EmergencyCar), shows the taxi (17) in its livery and takes `LOOK=`
  for the taxi and beater; `still_shot.gd STREET=queue STREET_MIX=14,15,17,16,18` queues the
  new bodies.
- **Checks**: `tests/more_cars_checks.gd` (the roll table against BODY_ODDS and the old ranges,
  the rng stream, builds with glass / far twin / lamps / wheels, the parked stance, a traffic SUV,
  hits to physics and CarDamage, the pool, the taxi's sign, lettering and fare, the beater's
  wear and nobody else's).
- **Not done / not verified**: no Forward+ look (the taxi sign's glow and the beater's chalky
  coat under AgX NEED A MAC CHECK); the beater's odd door and primer are always the same panels
  (per-car colour only); the minivan's sliding doors do not open; the SUV has two rows of traced
  seats, not three (CarCabin's cabin has a front row and one bench); the taxi is always the
  yellow checker livery; the hatch, minivan and SUV faces are plainer than a 2026 car's (one
  egg-crate or bar grille each).

## 9br. The beach on a warm afternoon, 2026-10-05 (agent branch `wt/beach-life`; VISUAL_ROADMAP #60)

Number is provisional (the lead renumbers on merge).

**The brief** (lead, from the owner's "make the graphics a million times better"): the sand, the
surf and the piers were there and the beach was empty. Fill it - sunbathers, swimmers and surfers,
volleyball, a bike path with cyclists, a lifeguard - placed from seed + chunk + hour, scattering at
gunfire, and dots of colour from the air. CLAUDE.md's "Beach life" note is the contract; this is
the story.

**What it is.**
- `BeachLife` (`scripts/world/beach_life.gd`, static): the plan (`plan_stretch()`, pure, world
  cells of 6.5 m of shore, groups of 1-4 in eight bands across the sand, the front rows first,
  `density()` by hour, `weather_factor()`), the props built in code at real size (towel, beach
  umbrella, low chair, cooler, tote, boogie board, surfboard, volleyball net and tapes, the LA
  lifeguard tower, the ball, a skateboard, the beach cruiser), the bike path (one strip a chunk),
  the court, the LOD dots. One shader, `shaders/beach_props.gdshader`.
- `BeachGoer` (`scripts/npc/beach_goer.gd`, extends RoughSleeper): swimwear on the crowd rigs
  (`swim_mesh()`: per triangle by rest-pose height, the garment bands stay garment and are coloured
  as the suit, the rest is skin on one texel of the person's neck; border vertices split so the
  suit's edge is clean and nothing interpolates across the atlas), the beach poses in
  RoughSleeper's table format, the cyclist's `ride_pose()` (two-bone IK of both legs onto the
  pedals, measured: ankles within 2 mm of their targets round the crank), volleyball moves.
- `BeachFigure` / `BeachFigureMesh` (`scripts/world/`): the camps' static figures for the beach,
  each (rig, pose) baked once and each suit a copy with the suit's look; merged in 32 m cells with
  a near (middle body) and a far (far body) mesh, so ~120 people a chunk are a handful of draws.
- `BeachActivity` (`scripts/world/beach_activity.gd`, one per FULL beach chunk): swimmers, surfers
  (sit in the lineup past the break, paddle in, ride a wave side-on along the shore, paddle back),
  riders and skaters (`BeachRider`, `scripts/npc/beach_rider.gd`), the volleyball rally (four live
  BeachGoers and the ball), walkers (`BeachWalker`, boards under the arm), the scatter.

**Decisions.**
- Swimwear by rewriting the regions rather than new garments in tools/crowd/garments.py: no
  Blender runs, no new atlases, and every system that reads the crowd rigs (welds, bakes, limb
  cuts, ragdolls, hats) sees an ordinary rig. The cost: a bare torso is the old shirt's shell (a
  few millimetres proud of where the body was), which nobody sees past a few metres.
- A beach's people are figures, not rigs. Live rigs only for the volleyball players, the walkers
  and anyone woken. Gunfire wakes the nearest up to 16 (3 a tick) and they run up the beach and
  walk back, the way the camps do.
- Cyclists are flipbooks (12 crank angles), each frame a bake with the bike built round it, so
  the crank, the pedals and the feet always agree; no skeleton ticks on the path.
- Courts are world cells of 26 m of shore with their own hash, so a court belongs to one chunk and
  its neighbours keep their people off it too.
- The block's own rolls are untouched: the palms are where they were (one rolled onto the path
  is moved just off it, after its roll), the tower is where it was and keeps its roll, but is now a
  real tower turned to the sea.

**Frame cost** (opengl3 1280x720, `still_shot.gd` GEO, `--quality=0`, BEACH_LIFE=0 vs on, the
same frame):

| frame | before (BEACH_LIFE=0) | after | |
|---|---|---|---|
| from the sand, 15:00 (`EYE=-725,1.7,610,160,-6`) | 1,323,727 tris, 349 draws | 1,620,191 tris, 417 draws | +22 % tris, +68 draws |
| aerial over a busy stretch (`EYE=-735,55,330,160,-32`) | 3,023,490 tris, 584 draws | 3,227,125 tris, 693 draws | +7 %, +109 draws |
| sunset 17:45 (`EYE=-725,1.7,610,160,-4`) | 1,290,853 tris, 332 draws | 1,361,609 tris, 387 draws | +5 %, +55 draws |

A beach frame was among the cheapest in the game (1.3 M against 5-8 M downtown) and stays well
under a city frame. The draws are the prop batches (towel, umbrella, chair, cooler, tote, boards,
net, tower - one each a chunk, umbrellas, chairs, coolers and the net with a shadow twin), the
figure cells (a draw per rig per cell, four rigs per 200 m of shore, near or far, plus a shadow),
and one or two per rider, surfer and swimmer. If they need to come down: merge the water people
into their chunk's cells, and drop the coolers' and chairs' shadow twins.

**Stills** (`shots/beach-life`): `beach_1500` (from the sand at 15:00, the lifeguard on his
tower), `aerial` (a busy stretch from 55 m), `volleyball`, `bike_path` (cyclists on cruisers),
`bike_close`, `surfers` (one riding a wave in, the lineup behind), `sunset` (17:45, a few left,
the lifeguard still up), and the
`*_before` frames with BEACH_LIFE=0.

**Not done / not verified.**
- Forward+ (the Mac) not seen: skin subsurface on the bare backs, the canvas backlight.
- The far city (Skyline, past the LOD ring) draws no dots: beach blocks are not captured there.
- Swimmers do not swim (they tread water and turn); surfers ride on their own clock, not exactly on
  the shader's wave (it is close: the same period and speed). Nobody goes in or out of the water.
- A bare torso is the shirt's shell; a one-piece is a band, not a cut; long hair is the painted
  scalp on the figures (the hair cards are on the live people).
- Cyclists and skaters ride a fixed stretch round their chunk and wrap; they do not cross into the
  next chunk's riders. Riders do not give way to people on the path.
- The beach under the Esplanade's bluff and the boardwalk get no path or court (their own
  ground); the boardwalk's stretch and the piers' get no people.

## 9bs. NPC polish: pigeons up close, turnout gear, paramedic uniforms, the bus windscreen, 2026-10-05 (agent branch `wt/npc-polish`; VISUAL_ROADMAP #61)

The brief (lead, reviewing 9bl and 9bm): pigeons at 1-3 m read as pale low-poly facets and are
pale from below; firefighters wear a flat tan; paramedics wear street clothes; confirm the bus's
windscreen at noon and dusk. Each item has a before / after pair from the same camera (branch
`shots/npc-polish`).

- **Pigeons** (`BirdMesh`, `bird.gdshader`, `make_bird_textures.py`). The near body loft is 28 x 22
  (was 24 x 18) and its normals are welded and averaged over the faces round each POSITION
  (`_smooth_normals()`): the analytic ellipse normals were only approximate where the radii change
  fast (breast, nape, cere), and each quad lit on its own. The folded feathers and the covert
  sheet take the body's flank normal (`flank_normal()`, a little lifted toward the top) instead of
  a fixed `(side, 0.4, 0)`, so the folded wing shades as part of the bird and no longer catches
  the sky as a pale sheet. The body's scallop relief is softer (normal depth 0.4 on the body, 0.7
  on feathers). The underwing: a wing or tail card's BACK face draws the species' underside
  (`under_cov` coverts, `under_flight` flight feathers, `under_keep` how much of the upper
  pattern's luminance shows, `under_mix`; in `BirdMesh.LOOKS`): a pigeon's mid-grey, a gull's
  white with the dark tips, a sparrow's buff; the crow keeps its black. Pigeon belly srgb 0.44 ->
  0.38, wing feather grey 0.56 -> 0.51 (atlas repainted; the white is the rump alone, where a
  feral pigeon has it). Near pigeon 2,146 -> 2,518 triangles (budget 2,600; MID / FAR unchanged).
- **Turnout gear and the paramedics' uniform** (`EmergencyCrew`, `character.gdshader`). The shader
  needed to know where on the BODY a pixel is, which the crowd rigs do not carry (UV2 is metres
  of surface per atlas rect, nothing positional). `EmergencyCrew.trim_mesh()` bakes it once per
  rig from the bind pose (CUSTOM2 / CUSTOM3, see CLAUDE.md "Emergency services"), keeps the mesh's
  LOD index lists by reading them back from the RenderingServer (`_surface_lods()`: a/d/f/h/j all
  keep their 4-5 levels), costs ~35 ms a rig and is warmed on the loading screen
  (`Pedestrian.warm_far_mesh(officer = true)`); the welded middle / far bodies are handed over
  from the plain mesh (no stripes past 50 m: they are a few pixels there). `uniform_kind` 1:
  khaki (TURNOUT 0.40 / 0.345 / 0.22), lime / silver / lime triple trim round both arm segments,
  chest and back, the coat's hem and the shins, a darker yoke and wristlets, black knee patches,
  leather gloves, the coat's sleeves over any bare forearm (half the rigs wear tees), bulk
  (`turnout_bulk` 1.4 cm). The trim is retroreflective: at night it is emitted by `lamp_factor` x a
  cone ahead of the camera x how squarely it faces it (`trim_retro` 1.8, `trim_reach` 45 m) -
  the freeway kit's glint on a body. `uniform_kind` 2: navy shirt and trousers with most of the
  rig's own pattern flattened (`cloth_shade_keep` 0.35: crowd_h's stripes read as street
  clothes), a shoulder patch on each upper arm (gold border, blue field, a white heartbeat trace -
  ours, not a real emblem), placket and buttons, a badge, cargo pockets with flaps on the thighs, a
  duty belt with a buckle. Both services get black boots. The limb code is a `flat` varying:
  interpolated, the knee between thigh (4) and shin (5) passed through every code between and drew
  jagged lightning lines; the distance along a limb now runs on over the elbow and knee.
- **The bus**: the 9bm fix holds. From the pavement at noon (`BIG=bus --hour=12`, both the stop's own
  eye and a clear one 8 m on, `EYE=2392.06,1.7,814.99,72.86,0`) the windscreen shows the daylit
  cabin, the driver and the first rows - not a black slab. At dusk and at night it was a dull
  grey: the cabin's own lamps followed `night_factor` at `BUS_LAMP` 1.0. Now they follow
  `lamp_factor` (dusk and storms) at 2.0 - a modest lift of the ceiling and seats behind the glass
  (`bus_front_*_before_after`). It reads as a bus with its lights on, not yet as a bright
  fluorescent box: the next step would be the cabin's own lit ceiling strips in the trace.
- **Tools**: `crowd_lineup.gd CREW=fire|medic|fire,medic NIGHT=1`; `bird_shot.gd ONLY=<pose>` (one
  bird at the origin for a close-up); `still_shot.gd SHOTS=@21.5` (an empty camera keeps the last
  one: the same frame at another hour from one load).
- **Frame cost** (opengl3): `tools/geo_count.gd --spawn=2800,180,0,-5,2` (Pershing Square, the
  survey's own flocks), before and after: 2,984,199 tris / 3,092 draws both. A staged medic scene
  (`EMERGENCY=medic --hour=12.5`): 4,987,861 / 2,500 -> 4,978,920 / 2,502 (flat: the trim mesh keeps
  every LOD). The bus at its stop: 5,445,409 / 2,665 both. The hose scene is not comparable (the
  wreck had burnt out before the before-shot and was still burning in the after-shot):
  4.26 M -> 4.49 M. Per near pigeon +372 triangles (30 staged pigeons ~ +11 k). The trim bake is
  ~35 ms per crew rig, once, on the loading screen.
- **Checks**: bird_checks (welded body normals, an underwing for pigeon / gull / sparrow, grey
  pigeon coverts), emergency_checks (the crews on a call wear the trim material, the two uniforms
  are told apart, navy, the trim's night and flat-code code paths, the bake keeps the mesh when
  there is no mesh data, the limb chains).
- **Stills** (`shots/npc-polish`, opengl3): `pigeon_close_before_after`, `pigeon_underwing_before_after`,
  `bird_lineup_after`; `turnout_before_after`, `turnout_night_before_after` (crowd_lineup.gd, the
  same rigs and pose), `medic_front_before_after`, `medic_side_before_after`; the city:
  `hose_day_before` / `hose_day_after`, `hose_night_after`, `medic_scene_before` / `_after`;
  `bus_9bm_fix_noon`, `bus_9bm_fix_dusk_blocked` (the stop's own eye, a pedestrian in the way at
  dusk), `bus_front_noon|dusk|night_before_after`.
- **Not done / not verified**: everything was judged on opengl3 only - NEEDS MAC CHECK: the trim's
  glint under AgX on Forward+ (it is emitted; `trim_retro` is the knob), the navy under the Mac's
  exposure, the pigeons' plumage. The paramedics' shirts are still the rigs' own garments (a crew
  neck tee on crowd_a / d reads as a uniform tee, not a collared shirt): a real collar needs
  geometry (tools/crowd/garments.py). No radio on the belt (painted gear reads flat). The turnout
  coat ends where the rig's top ends (at the waist), not at mid-thigh. Birds: the MID and FAR
  meshes and the gull / crow / sparrow bodies are unchanged; the feral pigeon's underwing is
  greyer than a wild rock dove's (the lead's call).

## 9bt. The night aerial: light rivers, lamp heads, sodium and LED, 2026-10-05 (agent branch `wt/night-city`; VISUAL_ROADMAP #62)

The money shot of LA is the basin at night from a hill or a plane. Before this pass the far city
at 21:00-23:00 (opengl3 stills, `shots/night-city` before_*.jpg) had: freeway decks as dark grey
threads with no traffic past the streamed range; the street grid a faint brown hatching (far
glow mean ~0.05) under moonlit roofs, with the far plates' and LOD ground's streets mostly black;
no lamp heads; far roof beacons steady; lit offices the same at 19:00 and 03:00. The airport's
field lights and the arena already read well and were left alone.

**What it is now** (rules in CLAUDE.md "Night aerial"):
- `shaders/far_traffic.gdshaderinc`: moving head and tail lights per pixel - `FT_CELL` 14 m
  cells, 32 to a period (`NightCity.PERIOD` 448 m), a hash per cell and lane, moving at 27 m/s on
  freeways (10-15 on streets), right-hand traffic, white toward the camera and red away; lamps
  drawn at least 0.9 px with a soft bloom gain, the lane's mean x `FT_FAR_BLOOM` once a car is
  under a couple of pixels. Decks (building_lod deck mode, Skyline passes the phase and route),
  far plates and the LOD ground (`street_traffic()`: lanes from the width, busier on avenues),
  and an additive skin on LOD freeway chunks (`FreewayTraffic`, `far_traffic.gdshader`) faded in
  past `freeway_range`, so the cars hand over to the lights.
- `street_glow.gdshaderinc`: sodium or LED by 420 m patch (`lamp_led()`, integer roll, LED 72 %
  within 2 km of downtown falling to 38 % past 6.5 km), lamp heads as points; far plates and LOD
  ground at `far_glow_gain` 2.6, junction squares at 0.75. The near lamps take the patch's
  colour (`NightCity.lamp_light()`, `pool_color()` in `CityChunk._add_lamp()`), and road.gdshader's
  far glow too.
- Hours: `city_hour` global (DayNight); `traffic_level()` (0.12 at 04:00 to 0.95 in the peaks,
  ~0.55 at 21:00, ~0.39 at 23:00) and `window_hour_scale()` (x1.25 at 18:00, x0.66 at midnight,
  x0.38 at 04:00) - the latter inside `window_lit()`, so near and far keep the same windows.
- Far roof masts' red beacons flash (1.5-2.2 s, own phase; 18 % steady).

**Stills** (opengl3 1280x720, `tools/glshot/still_shot.gd`, `--spawn=1500,300 --hour=22`, one
load, on `shots/night-city`): basin from the front range `EYE=420,330,-1180,-119,-9` (22:00),
over downtown at 400 m `2300,400,1700,0,-22@21`, the 110 and the 10 from the south
`2100,260,3700,0,-10@23`, the airport `600,180,780,90,-12@22`. before_*, after_* (a2).

**Cost** (GEO lines of the same four frames, before -> after): 1,864,233 / 466 draws -> same;
3,134,111 / 1,117 -> 3,134,145 / 1,120; 2,959,671 / 764 -> 2,959,707 / 768; 902,919 / 379 ->
902,951 / 383. The new draws are the LOD freeway skins (one a deck chunk); everything else is
ALU in shaders that were already running.

**Not done / not verified.**
- The Mac (Forward+, AgX, auto exposure, glow): the streams' level is tuned on opengl3 and may
  bloom harder there. Knobs: `FT_HEAD`, `FT_TAIL`, `FT_FAR_BLOOM` (far_traffic.gdshaderinc),
  `far_glow_gain`, `lamp_head_energy`.
- The near (FULL) roofs' beacons still burn steady; parking lots and the port are not floodlit in
  the far city (only where their LOD pools are); dark parks and hills were already dark.
- The night ambient (DayNight) still lights roofs a moonlit blue-grey on opengl3; not this pass.
- The far deck's traffic pattern only roughly joins the LOD skin's (both start at the segment's
  run in the period; the far box is 0.4 m long at the joints).

## 9bu. City acoustics: spaces, gunfire echo, footsteps, the newest systems' sounds, 2026-10-05 (agent branch `wt/audio`; VISUAL_ROADMAP #63)

**What was missing.** One street-canyon reverb summed from the probe, no echo of gunfire, no
footsteps at all (`footstep` was a name nothing played), and the bus, the light rail car, the LA
River, plazas and parks were silent.

**Spaces (reverb).** Ambience's probe already cast eight wall rays and one up; it now keeps their
distances (`scene.walls`, `scene.ceiling`), and `_water_scene()` adds plan maths: down in the
river's channel (`LaRiver.nearest()`, the ear under the coping), at the light rail's rails in its
TUNNEL / TRENCH samples. `Ambience.space_for(scene)` turns that into weights over ten presets
(`Ambience.SPACES`): tunnel (a lid over it; with sky above it is the trench, which takes the
channel preset), car park (a lid under 4.5 m with walls round), underpass (a lid higher than 7 m),
channel, alley (two facades within 16 m of each other with the way along open), canyon (the old
measure), street, beach, hills, open. `reverb_for()` blends the presets and the World reverb eases
to them over 1.2 s (wet, room, damping, pre-delay and now the reverb's own high-pass). Nothing is
placed by hand, no Area3D.

**Gunfire echo.** `echo_for()` makes the taps from the same rays: each of the two nearest facades
in different directions slaps a shot back after its round trip (level falling with distance), then
the flutter across; under a lid a tight cluster at the ceiling's round trip; in the river channel
or the rail trench bank-to-bank slaps; in the hills a rolling tail at 0.45 / 0.9 / 1.45 / 2.1 /
2.9 s, low-passed to ~1.6-2.7 kHz; out in the open city one soft return at 0.55 s; on the beach
nothing. `Sfx.set_echo()` takes it; `Sfx.play()` of `shot`, `shotgun`, `explosion`, `rocket`
queues delayed copies of the very take it just played on the new **Echo** bus (Game <- Echo:
low-pass from the profile, a reverb of its own for the smear), placed toward what reflects, 3 dB
down per doubling of the shot's distance from 15 m, none past 450 m. Police rounds echo too; no
weapon code changed. The web plays them 4 dB lower (no bus filter there).

**Footsteps.** `Footsteps` (`scripts/player/footsteps.gd`, a child of the Player): a step sounds
when a foot comes down in the animation (each foot's height in metres over the player, the bottom
22 % of its own swing, re-armed above the middle), so walk, run and the boosted sprint keep time
with the clip; without a rig a stride length. Surface from a ray down every 0.2 s through the pure
`Footsteps.surface_at()`: car / train / prop = metal, freeway / river / rail bodies = concrete,
over the sea = wood (piers), beach = sand (wood on a pier or the boardwalk), hills = grass, roofs =
concrete, off the block rect = asphalt, the pavement ring = concrete, parks / yards (suburbs,
beach town) = grass, rec facilities by kind. -13 dB at a walk to -7 at a run, soft ground 2 dB
quieter.

**New sources.** Bus (`VehicleAudio.bus_doors()` from `BusFittings.set_doors()`): the two-tone
chime, the pneumatic doors (opening hiss / closing under the warning beeper / a folding door), the
kneel's air release; its diesel idle is the street's traffic voice (Ambience hands the `diesel_idle`
loop to a bus or truck instead of the tyre roll, louder at idle, revving with speed). Light rail
car (`VehicleAudio.TrainVoice`, on its middle section): the traction whine (synthesized
`rail_motor`, pitch 0.45-1.7 with speed, loudest under acceleration or braking), the wire hum and
crackle (`rail_hum`), the door chime on opening and again as they start to close. River: an
emitter on the centre line (`amb_river`, `river_reach` 140 m; full only down in the channel, a
third from the bank). Fountains: every PLAZA block (`amb_fountain`, 75 m). Playgrounds: rec parks'
and schools' `playground` / `games` facilities (`amb_playground`, 150 m, 7:30-20:00, not in
rain). Basketball: `ParkBall` plays `ball_dribble` on each floor hit. Construction: an Ambience
one-shot kind (jackhammer bursts, hammering; urban density x 1.4 /min, 7:00-17:30).

**Mix report** (`tools/audio_probe.tscn`, headless, default seed, noon, clear; levels are the
beds' target gains 0..1, events per minute):

| Place | Space (weights) | World reverb | Gunfire echo taps | What plays | Feet |
|---|---|---|---|---|---|
| Flower at Olympic (downtown) | canyon .53, street .47 | wet .16, room .65, 56 ms | 105 ms -13, 113 ms -14, flutter 239 ms -11 | city 1.0, crowd 1.0, traffic .42; horns 6, bus 1.6, construction 1.4 | asphalt |
| Under the 110 by 5th St | underpass .57, garage .24, canyon .13 | wet .28, room .67, 32 ms | cluster 45 / 72 / 98 ms (-9..-15), facades 59 / 106 ms, flutter 186 ms | freeway 1.0, city 1.0 | asphalt |
| A midtown pavement | street .55, canyon .27, open .18 | wet .11, room .55 | 137 ms -16, soft 550 ms -15 | city .75, crowd .33, birds .12 | concrete |
| A plaza fountain downtown | open .63, street .21 | wet .07 | 66 ms -20, 550 ms -15 | fountain .98, city 1.0 | concrete |
| Rec park playground | street .89 | wet .10 | 169 / 291 / 481 ms | playground 1.0, crowd .42 | asphalt (the court) |
| LA River bed | channel 1.0 | wet .17, room .66, 55 ms | bank to bank ~0.15 / 0.3 s | river 1.0, city .55 | concrete |
| Light rail trench south of 11th | channel 1.0 (trench) | wet .17 | the trench walls' slap | city 1.0 | asphalt (ballast not told apart) |
| The beach | beach .78, open .22 | wet .02 | none | surf .83, wind .37, gulls 5 | sand |
| Front range hillside | hills .69, open .31 | wet .04, room .69, 92 ms | 450 / 900 / 1450 / 2100 / 2900 ms, -9..-23, 2.7 kHz | birds .6, wind .63 | grass |

**Tools.** `tools/city_audio.py` (cuts every new clip from build/audio_src/ and Kenney's zip;
sources and spans in docs/ASSETS.md), `tools/audio_probe.tscn` (the table above; `PLACES=`,
`HOUR=`). Checks: `tests/audio_checks.gd` (tables and stray files, the Echo bus, every space
staged, reverb ordering and the bus following it, echo taps per space and live echoes played,
river / fountain / playground / construction / tunnel, footstep surfaces, the player's node).

**Frame cost.** No geometry, no draws: the render is unchanged. CPU: the survey adds 9 cached
block lookups, one river nearest-point and one rail index query every 0.5 s; the footstep ray
every 0.2 s; up to 8 echo voices.

**Not done / not verified.** Nothing was heard: the headless run has the Dummy driver, so levels
are measured numbers, not listened to - the owner's ears on the Mac decide the echo level
(`Ambience.echo_db`), the footsteps under the chase camera (`Footsteps.walk_db` / `run_db`) and
the tunnel's wash. The tunnel itself is not walkable today, so its preset is only staged.
Alleys (another branch's) will classify as alleys by the ray rule; not seen in a real one here.
Car parks classify only where a deck is low over the ear (the arena garage was not visited).
The trench floor reads as asphalt underfoot. Echoes use the listener's surroundings for every
shot, not the shooter's. Stills: none (sound).

## 9bv. The hero's moves (VISUAL_ROADMAP #64, branch wt/hero-moves)

**What.** The hero had three clips (idle, walk, run) and a frozen run stride in the air. He now
has a second AnimationLibrary, `moves` (`assets/models/hero_moves.res`, 11 clips, ~90 KB), and a
procedural layer, `HeroMotion`, first in his skeleton's modifier stack:
- idle variety: after `idle_variant_after` (5-9 s) standing still, one of `idle_look` (over his
  left shoulder, then a longer look right), `idle_neck` (head over to each side with a snap, a
  shrug), `idle_watch` (left wrist up in front of his chest, he looks down at it) or
  `idle_stretch` (left arm overhead, a lean to the right); never the same twice running;
- a take-off (`jump_start`, from the crouch, on every jump and mid-air jump), the air
  (`jump_air`) and, past `fall_pose_speed`, the fall pose (left arm thrown out, the gun out to
  his right, head down at the ground);
- landings on LandingFX's scale: from `land_dip` (30 m/s) the knees take it (`land`, cut short
  when he runs on), from `land_hard` (60) the hero landing (`land_hero`: down on one knee, the
  left hand to the ground), and a hard landing at `roll_speed` (7 m/s) or faster rolls out
  (`roll`, the in-place middle of the library's dive roll);
- a sprint (`sprint`, gait 8.3 m/s) past `sprint_threshold` (9.5) and for every ground boost;
- stepping round on the spot (the walk in place, as fast as the turn) when the body turns faster
  than `turn_step_rate`;
- a flinch from each round (`PlayerHealth.hit_taken` -> `Avatar.hit_from()`): the chest knocked
  away from the shooter, the head a little further, on a spring (`flinch_*`) over whatever clip;
- a draw on a weapon change: the new gun comes up from the right hip, barrel down, over
  `draw_time` (0.42 s), the left hand joining it at the end;
- the flight pose while boosting in the air: the whole body laid along the velocity about the
  hips (upright climbing straight up, level flying level, head-down diving), banked into turns,
  legs together and pointed, the left arm swept back, the head lifted to look ahead, and the
  right fist - the gun - out ahead of the head;
- foot IK while standing (two world-layer rays a physics frame): the hips come down by the deeper
  foot and each leg is bent so its ankle lands on the ground under it (a capsule perched on a
  kerb's edge stands with both feet down on the road, hips 16 cm lower).

**How.** `tools/hero/hero_clips.gd` (headless, seconds) retargets Quaternius' CC0 Universal
Animation Library 1 and 2 [Standard] onto hero.glb in Godot, the crowd life clips' world-delta
method (never Blender's glTF import), with the hero Idle's own finger keys in every clip (the
library maps no fingers; without them the hands go flat to the bind pose), the air clips not
grounded, the roll's travel taken out. The free files have no look-round, stretch, watch or neck
clips, so those four are KEYED in the script: the library's idle with overlays (turns of a bone
about a skeleton-space axis, aims of its length, rolls about it) under eased weight envelopes;
`idle_watch` and `idle_stretch` carry meta `free_left` (when the left hand is off the gun). The
arms are now two TwoBoneIK3Ds (`GunHandsIK`, `GunHandsIKLeft`), so the left can let go by its
influence (and `GripHands.left_weight`) while the right keeps the gun in every move - there is
no holster mesh, so a "holster" is not drawn, only the draw. Raising the gun (aim, fire) always
wins over a move. Police officers' Avatars are crowd rigs: the moves are gated on the hero
(`_moves`), they keep the old three clips.

**Cost.** No geometry, no draws (GEO in hero_shot.gd identical before and after). CPU: HeroMotion
walks a handful of bone chains a frame, only the parts whose weight is above zero; foot IK two
rays a physics frame while standing.

**Look / check.** `tools/glshot/hero_moves_shot.gd` (several stills from one load: a clip frozen
at a time, or a staged move - idle, fly (FLY_TURN for the bank), climb, fall, hit_front / left /
right / back, draw, turn, sprint, aim, land_<fall speed>, roll, jump, idle_look / neck / watch /
stretch; STEP=1 a step for the foot IK, which prints MOTION lines). `tests/hero_moves_checks.gd`
stages each on the real player in the smoke test. Stills on shots/hero-moves.

**Not done / not verified.** Nothing seen at 60 fps or on Forward+: the blend times, the flight
lay and bank, the flinch strength and the idle-variant pacing want the owner's feel pass (all
exports on Avatar, "Hero moves" group). The idle variants are keyed in code over the library's
idle, not motion capture, and read a little stiff next to it. The hero landing is the library's
NinjaJump_Land (down on one knee, a hand to the ground), not a true three-point superhero pose.
No hit-reaction clips (Hit_Chest / Hit_Head) are used: the procedural flinch is directional and
blends over anything, the clips are not. Foot IK is only while standing (it fades out above
3 m/s) and keeps each foot's clip rotation (no tilt to a slope's normal). The draw has no
holster half: the old gun vanishes at once (WeaponManager hides it) and the new one comes up.

## 9bw. The container terminal at work (port life, VISUAL_ROADMAP #65)

**What.** The port moves. `PortLife` (`scripts/world/port_life.gd`) works every moving part out
from a clock (`PortLife.clock`, physics time), so the same second always shows the same picture
and nothing is simulated:
- **The ship-to-shore cranes over the moored ship dual-cycle.** The three working cranes (within
  95 m of the ship, gantried up to 32 m to the bay they work) are built at FULL as
  `PortKit.sts_frame_mesh()` - the posed crane less its trolley, cab, ropes and spreader; the
  split pieces add up to the old mesh triangle for triangle (checked) - plus a marker
  (`port_crane`). One cycle (~270-280 s) is two halves: a yard tractor pulls in under the crane
  with an export box, the spreader lifts it, the trolley runs out, sets it into slot A in the
  bay, picks slot B's box and sets it back on the same chassis; the tractor drives off round the
  yard as the crane's second tractor pulls in; the next half swaps A and B. A and B are the top
  boxes of two rows of the bay, hidden from the ship's own batch while the crane works
  (`ship_boxes()` replays Landmarks._build_cargo_ship's rolls exactly).
- **Yard tractors** (`PortLifeKit`: a terminal tractor and a 40 ft skeletal chassis, code-built,
  the chassis on the path HITCH metres behind so it articulates) loop the yard on the aisles
  between the port's chunks (`grid()`), 610-890 m loops, accelerating, cruising and braking.
- **Yard gantries** shuffle a 40 ft top box to the next column's lowest pile and back
  (`rtg_plan()`), the box's instance in the chunk's container batch hidden while it is away.
- **Straddle carriers** (9.6 x 4.9 x 13.4 m, legs, sills, eight wheels, cab up front, engine on
  top, lamps, ladder) loop the interior blocks clockwise, most with a box; 9 on the default seed.
- **The truck gate** (`PortGate`): the north-west port chunk holds no stacks (after the rolls)
  but eight lanes (six in, two out), booths on islands, an OCR / radiation portal with lane
  numbers, a canopy with the invented name BASIN HARBOR TERMINAL, a gate office, and up to
  eleven drayage semis (BigVehicles SEMI parked Vehicles, dry van hidden, a chassis and box hitched;
  some bobtails) at the booths, queued under the portal and leaving.
- **Night**: beacons (amber, flashing), head / work lamps and red lamps on the machines
  (`port_steel.gdshader` parts 11-13), pools of light under the working trolleys, ahead of the
  tractors and straddles, and on the ship's deck (and deck floodlights on its lashing bridges).
- **Sound**: Sfx `crane` at every spreader lock / release within 320 m; Ambience's crane
  one-shots come from a working spreader when one is in earshot (`PortLife.clank_at()`).

**Cost.** All the moving parts are one MultiMesh per kind (trolley, spreader, rope, gantry frame,
gantry trolley, straddle, tractor, chassis, box, light pool), drawn within 650 m of the camera;
machines within 140 m of the player carry an AnimatableBody3D (props layer, mask 0). Frame cost
(opengl3 still_shot GEO, 1280x720, `PORT_LIFE=0` against on, same EYE, clock held): the quay
under the cranes 802k / 321 draws -> 812k / 355; an aisle of the yard 792k / 474 -> 815k / 512;
the gate 1.09 M / 758 -> 1.30 M / 993 (the eleven semis are real Vehicles: about 20 draws each).

**Stills** (shots/port-life): a crane lifting a box off a chassis and one lowering a box into the
ship's bay from the quay, straddle carriers in an aisle, the cranes and tractors from above, the
gate queue, the yard from the air, the quay at 21:00, the whole terminal at 21:00 from the air and
from the west; and the PORT_LIFE=0 before of the quay and the gate.

**Tools.** `tools/port_life_probe.gd` (headless, seconds: cranes, their step times, poses and the
straddles' positions at `T=`), `PORT_T=<s>` / `PORT_HOLD=1` on still_shot.gd to frame a moment,
`PORT_LIFE=0` the A/B. Checks: `tests/port_life_checks.gd` (18).

**Not done / not verified.** Forward+ (the Mac) not seen: the lamps' glow and the pools under AgX
need eyes. The tractors and straddles do not yield to each other or to the player at crossings
(loops can cross), and do not stop for a car in the way; a tractor's chassis box changes look out
of sight on the far side of its loop. The gate's semis stand still (parked Vehicles: drivable and
stealable, lights off); the queue does not advance. No second ship with tugs. LOD chunks keep
the old posed cranes and static gantries, so a crane's trolley can jump at the FULL/LOD handoff.
The straddles carry their box under a spreader one size too long (the STS spreader).

## 9bx. The canals: a canal neighbourhood behind the boardwalk, 2026-10-05 (agent branch `wt/canals`; VISUAL_ROADMAP #66)

**What.** MARISOL CANALS (original name; the canals are Heron, Lantern, Mariner, Juniper and
Coral) - the form of the Venice canals on the 2 x 2 blocks inland of the boardwalk's shop strip
(x -824..-645, z -403..0 on the default seed). Two canals north-south, three east-west, 15 m bank
top to bank top: still, shallow water (0.6 m deep to a bed at -1.2), sloped banks planted with
grass, reeds along the waterline and shrubs, a concrete coping, a 2.6 m walk on each side; eleven
arched white footbridges with picket railings and two lantern posts each; 104 narrow lots facing
their canal, each a HouseKit house (stucco boxes, mid-century, craftsman cottages in siding,
Spanish revival, ranch; no garage, modern boxes with a wall of glass to the water), a small
garden down to the walk behind a picket / stucco / slat fence with a gate, a paver path, flowers,
a porch lantern; board fences between the yards and along a 5 m walk alley down the middle of the
back-to-back islands; trees and palms in the yards; ~20 timber docks with steps down the bank and
rowboats, kayaks (some upside down on the dock) and canoes, more boats tied to the bank. People
walk the walks and alleys. No cars: every street inside is closed (CityPlan.road_open(), the
MacArthur Park site mechanism); the four streets round it stay open as its residential ring.

**How.** `Canals` (`scripts/world/canals.gd`) is a landmark entry with an `"area"` (no kept
roads), so CityPlan snaps and closes it like MacArthur Park; `layout(plan)` is pure and cached,
`site_steps()` builds a chunk's part (ground, banks, water, houses, gardens, planting, bridges,
docks, crowd, one commit), `capture_steps()` the far city's record (hooked in
`CityChunk._begin_capture()`, two lines, plus `Landmarks.capture_steps()`). Houses go through a
new `HouseKit.plan_fronted()` (plan_house() split in two: the caller hands it the front) and a
`glass_front` flag in `HouseBuild._openings()`. `CanalKit` (`scripts/world/canal_kit.gd`): the
bridge, dock, boats and lantern are meshes built once and instanced through the chunk's batch;
fences and railings are written into the chunk's per-material meshes. Shaders: `canal_water`
(the mirror of the house fronts worked out as planes - day walls and windows, lit rooms and porch
lights at night - emitted by Fresnel; still ruffle, rain rings, scum at the edges), `canal_bank`,
`canal_boat` (paint in INSTANCE_CUSTOM), `canal_lamp`. The water is below the GroundBody: one
Area3D a chunk lets bodies down to the bed, refcounted across chunks (`Canals._sink`).
Shared files touched (small): landmarks.gd (entry, site/capture steps), city_chunk.gd (capture
hook), house_kit.gd (plan_fronted), house_build.gd (glass_front), minimap.gd (one label),
smoke_test.gd (one line), lot_fill_checks.gd (its beach-town window reaches past the site: the
canals took a block with a walk street). The blocks beside the site lose a rolled plaza or rec park
(`_beside_site`, as round MacArthur Park); no block seed moves.

**Cost** (opengl3 stills, whole frame, same EYEs with `CANALS=0`): aerial 4.44 M tris / 2,333
draws before -> 3.85 M / 1,948 with the canals; along a canal 5.87 M / 3,673 -> 5.02 M / 2,766
(the beach-town blocks it replaces had a car park, a plaza of palms and street cars). A FULL canal
chunk's own meshes are within the check's 260 k budget.

**Stills** (shots/canals): `aerial` (and `aerial_before`), along Heron Canal at golden hour
(`golden`, and `golden_before`), a footbridge from over the water (`bridge`), the same walk at
21:00 (`night`). EYEs: aerial `-735,140,95,0,-45` (EYE_AGL=1, --hour=13); along the canal
`-765,1.7,-120,0,-3@18.3`; the bridge `-773.9,2.6,-172,0,-5@15.5`; night `@21`. Fast loop:
`tools/glshot/block_shot.tscn` with `EYE=-735,95,30,0,-48 BLOCKS=2`.

**Not done / not verified.** Forward+ (the Mac) not seen: the water's made-up mirror is added at
`mirror_forward` 0.55 on top of SSR there and may want tuning; the lanterns' glow under AgX. No
ducks or animals (birds only, as briefed). Boats are static (no bob). The canals end in a headwall
at the pavement ring (no lagoon or tide gate). The minimap draws the site as park (no water).
Bridges carry no name plates; canal names are in code only.

## 9by. Photo mode, 2026-10-05 (agent branch `wt/photo-mode`)

The owner shares screenshots from his Mac; photo mode is how he shows the game off.
**`PhotoMode`** (`scripts/ui/photo_mode.gd`, a CanvasLayer at 6 that `pause_menu.gd` adds beside
itself in the city scene - no edit to city.tscn). `photo_mode` (P / right stick click) opens it
when the tree is not paused (never over the pause menu). It:

- **Freezes the world**: `get_tree().paused` like the pause menu, and `Engine.time_scale` 0. The
  render step Godot hands the RenderingServer is the process step times the time scale, so shader
  TIME stops too (clouds, ocean, sway, grain), without the stills' rollover trick. The weapon
  wheel sets the time scale back to 1 every frame the tree is paused, so photo mode re-sets it at
  `process_priority` 1000 (the value left at the end of a frame is the next frame's).
- **Flies its own camera**: a Camera3D copied from the one in force, its attributes DUPLICATED,
  so its depth of field and exposure never touch the player's (CameraPost keeps easing on the
  player's copy). Moved on the real clock; within `max_radius` (140 m) of the player (the city
  does not stream while paused) and `ground_clearance` above `ground_height_at()`. WASD / left
  stick, Q / E or the triggers, Z / C or the bumpers (roll), R level, Shift / Alt (pad: left
  stick click), right mouse held to look (the mouse is free for the panel otherwise; with the
  panel hidden by H the mouse always looks), wheel while looking = speed.
- **The panel** (`shaders/photo_panel.gdshader`: the frame behind blurred down the screen mips,
  smoked, a hairline rim, rounded by an SDF; the pause menu's chip style; 1080-line units scaled
  to the window, in a ScrollContainer): field of view, roll, speed; depth of field (Off / On /
  Focus on centre - a ray that hits the player too; focus distance; aperture: near and far blur
  round the focus with a sharp band 3.5 % of the distance per f-stop, amount 0.35 / f; hidden on
  Compatibility, which has none); exposure (`exposure_multiplier`, EV); the hour
  (`DayNight._apply()`); the weather (`force_state()`, then for `weather_settle_seconds` the
  Weather node runs ALWAYS with time at 1 so the rain fills the air, then it freezes again);
  FILTER: seven grades (`GRADES`) written into the scene's own look LUT by `grade_texture()`
  (per channel gain, lift and an S-curve over the base gradient) plus `adjustment_saturation`
  (Noir and Mono are 0); vignette and film grain (CityStreamer's Vignette layer); FRAME
  letterbox / pillarbox bars (2.39, 1.85, 4:5, 1:1; drawn, so they are in the photo); hide the
  player.
- **TAKE PHOTO** (F / Enter, pad A): hides the panel for two frames, reads the root viewport back
  (the window's resolution, the 2D layers under it - bars, vignette, lens rain - included) and
  writes `rando_<date>_<time>.png` to `OS.get_system_dir(PICTURES)/Rando Game`, else
  `user://photos`; on the web `JavaScriptBridge.download_buffer()`. A white flash and a toast
  with the path (`~` for home).
- **Leaving** (Esc / P, pad B, or the button) restores the snapshot taken on opening: the camera
  in force, the time scale, the pause, the hour, Weather's state / blend / wetness / drying /
  forced / timer and its process mode, the env's adjustment fields, vignette and grain, the
  player's visibility and every HUD CanvasLayer it hid (layers 0..127 that were visible; < 0 is
  part of the picture, 128 is the loading screen). `_exit_tree()` closes it, so a reload never
  leaves the engine frozen.

**Checks** (`tests/photo_mode_checks.gd`, 13): built in the city; P bound; not over the pause
menu; frozen (paused, time scale 0 two frames on, through the wheel's reset); own camera; HUD
hidden; radius and ground clamp; FOV / DOF / exposure on its own attributes; clock, weather and a
black-and-white grade; a neutral grade reproduces the look LUT; bars, vignette, hidden player;
the storm settle; a PNG written and read back; a capture never left stuck; and leaving restores
all of it. **Frame cost**: nothing while closed (one hidden CanvasLayer); open, one panel draw
with two screen-mip taps per pixel. **Stills** (shots/photo-mode): the panel over downtown at
golden hour (opengl3), the same view graded with the panel hidden, Noir letterboxed 2.39:1, the
toast after TAKE PHOTO and the file it saved; and the test room on Forward+ (lavapipe) for the
depth of field at f/1.4. `tools/glshot/photo_shot.gd` makes all of them from one load.

**Not done / not verified.** Not seen on the Mac: the Forward+ DOF in the city, the exposure
slider under auto exposure, and whether the grades read the same on the web (Compatibility's
adjustment support is assumed, not measured). No gamepad navigation of the panel (A shoots, B
leaves, Y hides it; the sliders need a mouse). Audio keeps playing (as under the pause menu).
The city does not stream while frozen, hence the radius. On the web a browser only grants mouse
capture after a click, so looking needs the right button pressed (which is that click).

## 9bz. Police stations the cruisers come out of, 2026-10-05 (agent branch `wt/police-station`; VISUAL_ROADMAP #68)

**What.** The police used to join the chase along a street 170-240 m out, from nowhere.
`PoliceStation` (`scripts/world/police_station.gd`, static, FireStation's pattern) places a
divisional station in every 1.5 km cell that has a suitable block, and the headquarters across
1st St (grid-south) from City Hall; `Police` sends cruisers out of the nearest one's gate and
brings recalled ones back in.

**Where (pure).** A hash of seed + cell picks up to six points; the first block that is MIDTOWN or
downtown off its tower core (skyline boost < 0.3), BUILDINGS, not a landmark's / park's / river's
and not the fire station's, gives a SITE: a centred run of its lot-grid cells along one street
(~56 x 50 m, at least 42 x 38), every cell's lot present, no courtyard lot (those build their
garden before a claim is asked), ground within 0.9 m, clear of the freeways, the road in front
open. `CityChunk._build_lot()` asks `claims()` after FireStation's (the pad roll is made either
way); the first claimed lot in lots() order builds it, the rest build nothing. The HQ is the whole
block (eight storeys). Seed 1337: seven stations within 4.5 km of downtown plus the HQ; seeds 7
and 99: six and five, each with the HQ.

**The building** (one mesh a station, a surface per material, `PoliceStation.Geo`): precast
concrete ground floor with slot windows; upper floors of glass bands between proud spandrels with
full-height fins every 1.6 m (`shaders/police_station_glass.gdshader`: tinted glass mirroring the
sky by Fresnel by day, offices lit window by window after dark with ceiling panels, blinds and a
warm or cool tube colour); a double-height glazed lobby pavilion lit all night under a
cantilevered canopy with a lit soffit and the department's name band (RANDO CITY POLICE); a dark
metal stair tower; roof plant; three flagpoles with invented flags; bollards and planters; a
monument sign with the division (invented names, `DIVISIONS`). Behind it the secured car park: a
steel palisade on the street line, the sliding gate (`Gate` node with its own AnimatableBody,
`open_gate()`), chain-link with three strands of barbed wire round the rest, stall rows in
double-loaded modules, the parked cruisers (one MultiMesh of the sedan's far twin in the
black-and-white livery, `cruiser_mesh()`, plus their dark light bars; up to 18, 24 at the HQ,
filled from the back fence forward), a fuel island under a canopy, the sally port (a covered bay
with a roll-up door and yellow bollards), floodlight poles with additive pools, CCTV cameras, a
34 m lattice radio mast with dishes and a blinking red beacon. Two `lamp_light` omnis (entrance,
car park; not on the web), TextMesh lettering (not on the web). LOD and the far city: the
building and the mast as `lod_box`es. Encampments keep off a station's frontage
(`keep_clear_points()`), parked cars off the kerb at its gate (`keeps_clear()`).

**Dispatch.** `Police._dispatch()` first asks `PoliceStation.nearest(plan, player, station_reach)`
(520 m): with a station in reach and its drive free (`_gate_busy()`), `_dispatch_from_station()`
starts the cruiser in the car park, slides the gate open and drives it along
`PoliceStation.exit_path()` (up the driveway, through the gate, down the ramp across the pavement,
round into its lane) with `PoliceCar.scripted` set (its own driving off; `_tick_drives()` moves
it), then hands it to the lanes exactly where a street cruiser would be - from there it is an
ordinary DISPATCH. A cruiser with a station is not despawned short of `station_reach + 150`.
Recalled (`board()` with the stars gone) it heads for the nearest station (`_home_for()`), and
once on the station's road level with the turn (`_maybe_enter()`; a physical one within 14 m is
stripped and frozen, wheels first) it follows `enter_path()` through the gate and is pooled.

**Checks** (`tests/police_station_checks.gd`, 18): pure and repeatable, sites inside their blocks
on their own lots off the fire station's and the freeway, the HQ by City Hall, the chunk builds
building, gate, collision and cruisers inside a triangle budget, the far city sees it, the gate
slides, a cruiser drives out of the gate onto its lane (8.5 s, 0.00 m off the lane) and then the
lanes with its siren, a recalled one turns in and is put away. Smoke test: 941 checks passed.

**Frame cost** (block_shot.tscn GEO, opengl3 1280x720, `POLICE_STATIONS=0` against on, same
eyes): the station from across the street 5.90 M -> 5.78 M triangles, 2,160 -> 2,232 draws; the car
park from 52 m up 6.07 M -> 5.94 M, 3,540 -> 3,580; the HQ from across 1st St 2.25 M -> 1.79 M,
1,587 -> 1,344 (the station replaces its lots' buildings). A station's own mesh is ~7 k
triangles; each parked cruiser is the 7.9 k-triangle far twin. A whole-city geo_count would not
finish on this box (killed after 25 min), so the numbers are block_shot's.

**Tools.** `tools/glshot/police_station_shot.gd` (the city at an EYE in a lighter world; `GATE=1
SEQ=...` a two-star dispatch out of the nearest gate shot as a sequence), `block_shot.tscn` EYEs
for the building: the default seed's OAK GROVE station from across its street
`EYE=3652,1.7,-1079,18,3`, its car park from above `3640,52,-1080,0,-52`, the HQ
`3172,2.0,-792,180,6`. `POLICE_STATIONS=0` in the environment is the A/B.

**Not done / not verified.** Forward+ (the Mac) not seen: the glass, the floodlights and the
lobby under AgX need eyes. The parked cruisers are static meshes with box collision: shooting
one does nothing and none can be stolen. No officers stand about at the station. The gate is
shared one cruiser at a time; other units still arrive along streets. Police helicopters do not
use the HQ (it has no helipad). Suburbs and the beach town get no stations (their lots are house
lots planned by HouseKit/YardFill, which a claim would fight); a cell there takes a midtown
block if one of its six points finds one, else none. The far city draws the station as two boxes,
not its car park.

## 9ca. Gullwing Park: an amusement park on Rando Pier, 2026-10-05 (agent branch `wt/pier`; VISUAL_ROADMAP #69)

**What.** The `pier` landmark (Rando Pier, (-940, -350), the Santa Monica of this map) was a
plank, two box arches, a Ferris wheel of box spokes turned by a node and a coaster "loop" of
boxes. It is now `PierPark`: a timber pier (pile bents with X braces, fascia, stringers, a
railing round the whole outline, a ramp to the sand, double-globe lamps where Weather's sea
reflections already put them) with GULLWING PARK on a 140 x 50 m platform off its south side
and a 98 x 20 m strip off its north side. Everything original: the park, the coaster (KELP
CRACKER), the arcade (TOKEN TIDE ARCADE), BUMPER BAY, the stands (SALT & SPUD, PINK FOG CANDY,
STICK SHACK, SQUEEZE PLAY, FUNNEL CLOUD), the games (RING TOSS, HOOP SHOT, BALLOON DARTS, WATER
RACE, BOTTLE DROP).

- **The Ferris wheel** (`FerrisWheel`, 26 m across, hub 16.8 m over the deck): two laced box
  rims, twenty spokes a side to a flanged hub, cross ties with gondola pins, tubular A-frames on a
  boarding platform with the drive tyres under the rim, twenty open oval gondolas under striped
  canopies. Turns in the vertex shader (`pier_park.gdshader` ride 1, a turn in 150 s), the
  gondolas translated with their pins so they hang plumb with a slow swing. After dark the LED
  strips on every spoke and both rims run four chasing patterns crossfaded every 14 s (radial
  runs, a rotating sweep, a spiral, a slow colour with sparkle) and the gondolas' canopy rims
  glow. The far copy is the same wheel at low detail with 0.9 m LED strips: a lit disc from the
  beach 500 m off and from the air.
- **The coaster** (`PierCoaster`): a 267 m circuit round the platform - station, chain lift to
  17 m, a turning first drop round the west end, camelbacks down the south side, a banked turn
  and the brakes - on a tube spine with C-frame ties and two running rails, single columns where
  the track is low and braced pairs where it is high, a lift catwalk, a station with a canopy and
  gates. The five-car train is placed from a table worked out once (76 s a ride, 26 s of it in the
  station, 17 m/s at the bottom of the drop); riders scream on the drop, the train rolls with the
  light rail's rolling loop.
- **The carousel** (`PierCarousel`): 28 carved horses (body, chest, haunch, neck, head, mane,
  ears, eyes, prancing legs, tail, saddle, blanket, breast collar, stirrups - each its coat) on
  brass poles in two rings, a striped canopy with a cream ceiling and rings of bulbs, a rounding
  board with mirrors, scallops and bulbs, a mirrored column; turns and bobs in the shader.
- **The midway**: the arcade (lit glass bays, a canopy, a neon name on a bulb-framed board),
  BUMPER BAY (an open pavilion, pick-up grid, ten cars running loops over the floor in the
  shader), five food stands with their giant fries / candy floss / corn dog / lemon / funnel cake
  on the roof, five game booths with shelves of plush prizes, benches, picnic tables under
  umbrellas, swagged strings of bulbs across the pier, the park's arch (GULLWING PARK) and the
  pier's (RANDO PIER) in neon and bulbs, warm light pools, six real lamp_light omnis.
- **People**: 48 `PierGoer`s (in the crowd cap, two in three starting on the midway) walk the
  walk graph, sit on the benches and queue at the wheel, the coaster, the carousel, the bumper
  cars, the stands and the booths (the life layer's vendor queue).
- **Shooting**: the wheel, the track and the cars are metal (sparks, pings) and keep running.

**Frame cost** (still_shot.gd GEO lines, opengl3 + Xvfb 1280x720, the same EYEs and spawn
(-1000, -345), 12:30, base 885795c against this branch): the pier from the beach (EYE
`-945,1.8,-235,61.7,7`) 1.057 M -> 1.273 M triangles, 780 -> 411 draws (camera 636 k -> 782 k,
shadows 422 k -> 491 k); under the wheel (`-1065,8.1,-330,124,22`) 0.397 M -> 0.661 M, 252 ->
197; down the deck (`-970,8.0,-353,90,-3`) 0.662 M -> 0.961 M, 627 -> 240 (most of the rise is
the crowd the old pier did not have). The park near is ~121 k triangles (pier and midway ~57 k,
the rides ~64 k) in 211 nodes with 173 collision shapes; the far copy 4 k triangles in 14 nodes.
Draws fell because the old pier was a node per box. Shadow passes were cut by giving every light,
pile, rail, lamp and string no shadow and drawing the wheel's and the track's shadows from their
far meshes (shadows only): the beach view's shadow pass 596 k -> 491 k. Build: ~0.5 s of
GDScript once, on the loading screen (`PierPark.warm()`); a pier chunk then only instances.

**Stills** (shots/pier; opengl3, not the Mac's Forward+): the pier from the beach at noon and
at 21:00 (`-945,1.8,-235,61.7,7`), the wheel close up from the deck by day and lit at night
(`-1065,8.1,-330,124,22`), the train on the drop (`PIER_COASTER_S=78`, `-1090,8.1,-348,135,12`),
the midway crowd by day and night (`-1006,8.2,-346,100,-4`), the carousel by day and night
(`-1032,8.0,-314,104,-2`), and the far wheel from the beach 500 m south and from the air.

**Tools.** `tools/pier/compile.gd` (headless, seconds): compiles the scripts, builds the park
near and far and prints triangles / nodes / shapes, the coaster's ride, and runs the checks that
need no city. Checks: `tests/pier_park_checks.gd`.

**Not done / not verified.** Forward+ (the Mac) not seen: the LED and bulb brightness under AgX
and auto exposure, the canvas and paint under SSIL. Nobody rides: the gondolas, the coaster and
the carousel are empty and the queues never board (people queue, wait and leave). The bumper cars
pass through each other (shader paths, no collision) and have no sparks on the grid. The coaster
train has no collision with the player beyond its five boxes (it does not knock anyone down).
The arcade has no interior (its glass glows). No carousel organ or midway music. Weather's sea
reflections of the pier's lamps (`Weather.pier_light_lines()`) still use the old lamp numbers
(+-11 m, 5.5 m up), within a few decimetres of the new ones. BeachLife does not keep its towels
off the ground under the pier's ramp.

## 9cb. A small-craft marina between the beach town and the airport, 2026-10-05 (agent branch `wt/marina`; VISUAL_ROADMAP #70)

Number is provisional (the next free one after 9br when this was rebased; the lead renumbers).

**The brief** (lead): a marina in the form of LA's big man-made one, between the beach town and the
airport - a basin behind a rubble breakwater with a channel to the sea and lights on the jetty
ends, calm water, floating docks on pilings, hundreds of boats bobbing, towers, restaurants, car
parks, a boat yard with a travel lift, boats motoring in the channel, and a cheap far copy (the
mast forest from the hills and from the planes). Names invented; canals (Venice) is another
session's, so the site starts south of the boardwalk's blocks.

**Where.** The real one sits between Venice and Playa del Rey, north of the airport. Here: the
whole blocks between the roads nearest x -824 / -546 and z 0 / 404 (`Marina.SITE_*`; Lake Blvd,
Birch Ave, 5th St and 7th St on the default seed - x -812..-553, z 10..394), behind the sand, west
of the 405 (no deck crosses it, checked), 200 m north of the airport fence. The coast slants 100 m
across the site, so the basin's west seawall is a straight line a promenade (bank 5 m + 13 m)
behind the sand's inland edge; the north, east and south walls are straight bulkheads.

**The land** is a terrace at QUAY_Y 1.9 m of relief (pavement 2.15, water 0.15), folded into
`MacroMap._relief_at()` like the river's, faded over 40 m outside the site and never on the sand:
the beach and the coast highway on it keep their heights; a planted bank climbs from the sand's
edge (0.5) to the promenade. **The water** stands at the sea's 0.15 over the GroundBody (y 0): you
wade in the basin as you do in the sea - no sunk floor, no collision exceptions (the MacArthur Park
lake's trick was not worth it here). `MacroMap.bake()` marks it water so the horizon plane sinks
under it.

**The channel** runs west from the basin's south-west corner (zc 284 on this seed) out 58 m past
the waterline between two rubble jetties (crest 3.2 m, 1:1.6 faces, Poly Haven boulders on top);
the beach's sand is cut out of its band (`MarinaBuild.sand_rects()` in `_build_beach`, the palms'
and lifeguard tower's rolls still made). A detached breakwater (300 m, crest 4 m) stands 175 m
offshore, a red-banded lighthouse on the south (starboard coming in) jetty head, a green light on
the north one, white flashers on the breakwater's ends (aircraft_lights billboards, kind 2). The
ocean shader still breaks surf on the beach inside the breakwater (it knows nothing of it).

**The coast highway** runs on the sand across the channel's line. It crosses on MarinaBuild's
bridge: HillRoads' strip is gapped (`pch_gap()`, snapped to its own 26 m points so the strip ends
where the ramps begin; `filter_segments()` in `CityChunk._hill_segments()`; HillRoads' segments
carry no name, so `is_pch()` finds the highway by its line and width), and the bridge deck
follows `bridge_y()` - ramps on fill between walls, a girder span on three-column piers just
outside the jetties, 3.9 m clear over the water. Only the runabouts pass; the sailboats and
flybridge boats stay in (decided: a fixed span keeps the highway drivable; a bascule is a later
job). The streets' beach ends under the ramps and across the channel are closed
(`Marina.road_open()`, through `CityPlan.road_open()`).

**Docks and boats.** Main docks every 38 m run west from the east headwalk and stop 44 m short of
the west seawall (the fairway), fingers both sides at 4.8 m, piles at every other finger tip and
along the docks, gangways with gates down from the quays, utility pedestals with lamps and light
pools; the west headwalk takes side-tied yachts. Default seed: 163 boats in the water (sail 75,
motor 27, sport fisher 17, runabout 22-ish by `TYPE_ODDS`), 34 on stands in the yard, 180 dock
pieces. `BoatMesh` builds each type in code at real size (lofted sections, cabins with window
bands, masts, booms, sail covers, furled jibs, stays and shrouds, pulpits, lifelines, flybridges,
hardtops, a tuna tower, outboards), 1.4-2.1k / 0.5-0.65k / 0.11-0.14k triangles; `boat.gdshader`
paints by region (hull paint, boot stripe, scum line, antifouling, non-skid, teak, canvas,
glass), bobs each boat about its waterline phased by its true world position, and after dark
lights a fifth of the cabins and a seventh of the anchor lights. Boats are MultiMeshes per type,
variant and 60 x 44 m cell, three nodes each with visibility ranges (70 / 230 m), so a group's
LOD fits its spread; one box shape a boat. **On land**: three apartment towers (Building, glass
or panels, balconies on every floor) on the east quay between car parks, three restaurants on the
north quay with umbrella terraces, the boat yard (rows of boats on jack stands, the travel lift
straddling its well with a sport fisher in the slings, a shed, a car park), palms, street lamps
(`lamp_light`), benches, a red bike path down the west promenade. **MarinaTraffic**: three
runabouts on a closed loop (fairway, channel, round in the lee of the breakwater) with a foam wake.

**Far.** LOD chunks: water, land, docks as slabs, FAR boats, masts as `lod_box` MASTs (drawn a
pixel wide at any range - the mast forest from the hills), coded far towers, lights. The capture:
land slabs, car parks, docks, hulls, masts, towers, the jetties, breakwater and bridge deck as
boxes; Skyline's plate for a marina block is the water at the water.

**Frame cost** (still_shot GEO, opengl3 1280x720, `MARINA=0` against the marina, same EYEs): from
the tower 6.90 M / 1,928 draws -> 2.13 M / 1,393; on a dock at 21:00 3.19 M / 1,335 -> 2.26 M /
1,053; the far aerial 1.64 M / 1,753 -> 0.78 M / 671 (the nine blocks build no houses or yards).
Close among the boats (the sailboat still) 3.91 M / 1,833: the NEAR boats within 70 m dominate.

**Tools.** `tools/marina/probe.gd` (the plan, headless, seconds), `tools/marina/area_probe.gd`
(zones, districts, roads and freeways round the coast), `tools/marina/marina_check.tscn` (the
marina's checks alone against a loaded city, a minute). Checks: `tests/marina_checks.gd` (19).
Stills on `shots/marina` (golden hour from a tower, docks at 21:00, a sailboat close up, the
jetty light at night, the far aerial, before/after).

**Not done / not verified.** Forward+ (the Mac) not seen: the water's sky mirror and SSR, the boat
gelcoat and anchor lights under AgX. No minimap drawing (another session's file). No swimming or
sinking (the basin is wadeable like the sea); boats are static colliders, not drivable. The surf
still breaks inside the breakwater. Sailboats cannot leave (fixed bridge). Shadows of the NEAR
boats are the full mesh (no lighter twin). No pedestrians on the quays or docks beyond what the
neighbouring blocks send. Golden hour from the planes on final was not shot (the approach is from
the east, south of the marina).

## 9cc. What a blast leaves behind: trees on fire, smoke columns, craters, car alarms, 2026-10-05 (agent branch `wt/explosions`)

The fleet task: "what a big blast leaves behind". A rocket used to leave a 14-second scorch and
nothing else. Now (CLAUDE.md, "What a blast leaves behind"):

- **Trees burn.** `TreeFire` (`scripts/world/tree_fire.gd`) is told every street tree and palm a
  FULL chunk draws (two lines round `_batch.build()` in CityChunk: `collect()` reads the batch
  data before it is built, `attach()` keeps the built nodes), so it needs no physics shapes. A
  blast lights the crowns in reach (odds falling with distance, not a roof blast's street tree),
  a burning car an overhanging crown (CarDamage._burning, polled every 2 s), a burning crown its
  neighbours (every 3.5 s, 30 %, crowns within 3.5 m). A burning crown is the car fire's own
  material and ramps scaled up: tongues out of the whole crown, rolling billows over it, burning
  bits falling, embers drifting down the wind, black smoke, a flickering light (desktop) and the
  fire loop; 24-36 s for a palm, 36-54 s for a broadleaf, then 30 s of smoulder. A third of the
  way in, under the flames, the instance is hidden and drawn from a CHARRED copy: the same mesh
  and LODs with burnt materials (palms: `foliage.gdshader`'s new `burnt` uniform burns the
  fronds back from the tips in 25 cm cells and chars everything; trees: foliage_tex with
  `thin_max` 0.88 and the instance's custom.x 1, dark brown leaves, bark x0.15). It stays charred
  (`WorldState.charred`, applied when the chunk is built again). Cap 8 burning (4 on the web).
- **Smoke columns.** The TreeFire node clusters every fire once a second (a tree 2, a palm 1.5,
  a burning car 1, a wreck still burning 0.8; 45 m merge) and a cluster of weight 2 gets a
  `SmokeColumn`: one mesh of 72 quads (36 on the web), every puff placed in
  `shaders/smoke_column.gdshader` from TIME - rising, slowing, widening, bending over down
  Weather's `rain_wind` and spreading into a sheet at the top; 320 m for a tree, up to 650 m for
  a big fire. Lit by hand: the puff texture's billows, a round normal per puff turned to the sun,
  the sky's tint as fill, the city's glow under it at night and the fire on its foot. It comes up
  over 25 s and clears over 70 s once nothing feeds it. Cap 4.
- **Craters and rubble.** `BlastAftermath.crater()`: generated 256 px albedo and normal maps
  (pit, broken rim, radial cracks, soot streaks) as a Decal on Forward+ and a lit cut-out quad on
  Compatibility, 14 heaved asphalt slabs round the rim (one MultiMesh), 5 minutes, cap 14.
  Rubble: 9 rigid chunks of road (lit wedges, asphalt on top, base course on the sides),
  PhysicsBudget debris for 3 minutes, cap 60 (`make_room()` first). A car's own explosion
  scorches but digs no pit (the wreck sits on it).
- **Dust and leaves.** A low wave of street dust rolling out to 3.2 radii after the fireball,
  dust and grit shaken off every roof the twelve rays from above find within 4 radii (desktop),
  and leaves (shreds of frond off a palm) torn off the six nearest trees and fluttering down for
  ~8 s.
- **Car alarms.** `CarAlarm` (`scripts/vehicles/car_alarm.gd`): 72 % of empty parked cars (a hash
  of the car) have one; a blast within 4 radii (staggered by distance) or a hit on the car sets it
  off: one of three real CC0 recordings (Sfx `car_alarm`: a pulsing siren, a multi-tone warble
  cycle, a horn honking), 24-46 s, hazards flashing (`Vehicle.alarm_left`, which turns a parked
  car's lamps on with the hazard state), cap 7. Never a driven, traffic, police, emergency car,
  wreck or aircraft.

**Shared files touched (small, local):** `explosion.gd` (one call at the end of blast()),
`city_chunk.gd` (two lines round `_batch.build()`), `vehicle.gd` (`alarm_left`, two lines in the
lamps, one in take_hit()), `world_state.gd` (`charred`), `sfx.gd` (one entry in each table and a
synth fallback), `foliage.gdshader` (`burnt`, 0 on every living palm), `loading_screen.gd` (warm
the crater maps and leaf materials), `smoke_test.gd` (one line), `still_shot.gd` (the AFTERMATH
block).

**Stills** (shots/explosions; opengl3, not the Mac's Forward+): `aftermath_palms` (a rocket by a
palm row, the fireball and a crown catching), `aftermath_burning` (the row alight at 22:00),
`aftermath_charred` (the row burnt out next morning beside living palms), `aftermath_column` (the
column from 1.4 km across the basin), `aftermath_crater` (the crater and slabs in the road).
`AFTERMATH=palms|burning|charred|column|crater` on still_shot.gd stages each
(`tools/glshot/aftermath_stage.gd`: the nearest palm row, a camera no crown blocks; `AF_NOFIRE=1`
the same frame with nothing staged).

**Frame cost:** FRAMECOST

**Not done / not verified.** Forward+ (the Mac) not seen: the crater decal, the fire's light on
the charred trunks, the column under AgX and auto exposure need eyes. Only street trees and
palms burn (the batches `tree_<n>` / `palm_<n>`): park groves of landmarks, hill trees, bushes
and LOD / far-city trees do not, and a charred tree goes back to green past the FULL ring (the LOD
chunks and the far city do not know about it). The crater is a mark plus slabs, not a hole in the
road mesh. No glass crunch underfoot. Smoke columns are built only round fires near the player
(the fires themselves live in the streamed chunks); they do not cast shadows.

## 9ce. Climbing plants: bougainvillea, ivy, fig, jasmine, vines and garden accents, 2026-10-05 (agent branch `wt/climbing-plants`; VISUAL_ROADMAP #73)

**What.** The planting that grows ON things - what makes LA walls and fences look lived in.
`ClimbingPlants` (`scripts/world/climbing_plants.gd`, static) grows, on the walls a FULL chunk has
just built: bougainvillea (magenta 62 %, orange, white) as a shrub domed out from the wall, deeper
toward its top, spilling over the coping and down the far side of a garden wall, canes hanging
under gravity; ivy and creeping fig climbing in ragged fans (ivy mounded, fig flat on the wall);
star jasmine as a mat through chain-link, pickets and board fences, both sides, white flowers;
pergolas (built here: posts, beams, rafters in YardFill's timber) over some back-yard decks and
tiled patios, wisteria with hanging racemes or grape with bunches on them; trumpet vine up some
wooden utility poles with a mass of orange trumpets at the top; and agave, aloe, red-hot poker,
lavender and lantana in YardFill's mulch and decomposed-granite beds.

**Where it reads its walls.** `ch._yard_walls` (YardFill's upright boxes, merged into straight
runs: garden walls, stucco and timber fences, pickets, chain-link, freeway sound walls, block
walls); every house face (`house_face()`, one hook line in `HouseBuild._wing()`, with the face's
openings and the spans another wing hides, so a vine frames a window and never grows into the
wing next door); LotFill's car-park walls and chain-link (`note_run()`, one line in
`LotFill._edge_run()`); low-rise Building walls (under `BUILDING_MAX_TOP` 14 m, only where
`StreetWear._paintable()` says the shader draws plain wall); the `upole` batch; `_yard_ground`'s
decks / tiles and mulch / DG. One step line in `CityChunk.begin_build()` after StreetWear; the step
moves itself behind the deferred steps (YardFill lays its walls in them), then runs in
`STEP_BUDGET_US` (1.5 ms) slices, each tile's mesh a job of its own. A wall within `FRONT_REACH`
of the block's edge is a front wall, planted on its street side and `FRONT_GAIN` times as often;
a house's front face 1.7x, its back 0.6x. Shares per district (`DISTRICT_SHARE`): beach town 1,
suburbs 0.85, campus 0.45, midtown 0.4, industrial 0.2, downtown 0.08. Nothing at LOD or in the
far city. Every roll is a hash of seed + wall / face / pole / bed; built with `CLIMBERS=0` a
block is the same block (checked).

**How it is drawn.** Leaf and bract cards built in code (`_card()`: centred, bent at the middle,
the normal leaned toward the mass's outward direction so a mass lights as a volume; COLOR.a the
wind weight, UV2.x the flower flag, UV2.y the fade distance), from ONE atlas painted by
`tools/make_climbers.py` (`assets/textures/climbers/`, 8 x 6 cells of 256 px: sprigs for the
silhouettes, dense MASS cells for the inside of a plant, the agave / aloe blades, spikes, the
woody trunk; original procedural art) on ONE shader (`shaders/climbers.gdshader`: sway by weight,
gusts, flutter; the alpha cut lowered per mip level so a mass does not thin to stems; backlight
translucency, more for bracts; wet leaves; colour-space include; a dithered fade over the last
25 m). Meshes are 64 m TILES per kind: leaves (no shadow), a shadows-only twin of every 3rd card
(35 % bigger), accents (cast) - tiles because a node's visibility range is measured to its bounds'
centre, and on a 415 m beach block a chunk-wide mesh was hidden from its own near end. Agave and
aloe are real rosettes (golden-angle leaves, a folded V section, three segments curling up).

**What went wrong first** (so nobody repeats it): sprig cells alone, at any density, read as
sticks and a trellis; the vine trunks drawn as a 7-stem cell read as a lattice; the first
bougainvillea on a house wall was a mass at the ROOF line (from the top down), a pink blob on the
roof from the street - it is a shrub now, grown from the ground to 2.4-4.6 m up the corner.

**Numbers.** A beach-town block (76 x 88 m, (-4, 14) on the default seed): ~5,500 cards,
19 k leaf triangles, 6.4 k shadow-twin triangles, 2 k accent triangles; 75-90 ms of GDScript
over ~60 slices, the worst slice ~5 ms (one pergola). Frame cost (opengl3, `still_shot.gd` GEO,
`CLIMBERS=0` against on, same EYE): the beach-town street at noon 5.91 M -> 6.03 M triangles
(+2.1 %), 2,765 -> 2,837 draws; a bougainvillea close-up 3.46 M -> 3.58 M, 2,393 -> 2,441;
the pergola 2.68 M -> 2.76 M, 1,788 -> 1,827. `geo_count.gd AB='Climbers*,ClimberAccents*'` at
`--spawn=-296,2603,0,-3,2`: 3.16 M -> 3.28 M, 2,705 -> 2,760 draws (188 tile nodes in the loaded
ring, most culled).

**Tools.** `tools/climbers/climbers_probe.tscn` (headless, seconds: cards per species, step
times, an EYE for every plant; `AT=x,z`, `DISTRICT`, `FIND`, `SLOW=1` lists slow jobs);
`tools/climbers/checks_only.tscn` (the checks alone against the city, a minute); `block_shot.tscn`
for a block alone and `still_shot.gd` EYEs. Checks: `tests/climbing_plants_checks.gd`.

**Stills** (shots/climbing-plants; opengl3, not the Mac's Forward+): the beach-town street (Hill
St-like corner at (-296, 2603) looking north) at noon and 17:36 with and without the plants, a
bougainvillea over a garden wall at noon and golden hour, an ivy-covered house wall, a pergola.

**Not done / not verified.** Forward+ (the Mac) not seen: the translucency, the bracts' colour
under AgX and the normal map's sign. The industrial district's own walls (Industrial's meshes) and
the car parks' hedges get nothing; the accent plants appear only where YardFill laid mulch or DG
(a dozen a block); climbing roses and sound-wall bougainvillea cascades from the freeway side are
not separate; no seasonal bloom (always in flower). Leaves can overlap a window frame by a few
centimetres (card centres keep 0.22-0.3 m off openings, the cards are 0.5-0.95 m). Wind sway is
the same for every species.

## 9cf. Buildings that take damage: crazed and shattered glass, blast holes, scars, 2026-10-05 (agent branch `wt/building-damage`; VISUAL_ROADMAP #74)

**What.** A round in a window crazes it (a spider web out of the impact, rings, and on shop and
curtain-wall glass a tempered dice net), a second round in the same pane takes it out: the
shards fall out of the frame as a glinting burst with the glass Sfx, the frame is left empty but
for teeth of glass round its edge, the room behind is seen plainly (no tint, no mirror, the blind
gone), and the glass lies on the pavement under it. A round in stone, render or brick leaves a
scar (a dark pit in a ring of paler spalled face) that stays - the bullet-hole decal fades and the
web has none. A rocket (any `Explosion.blast()`, car explosions too) takes out every pane within
0.7 of its radius on its side of the building and crazes them to 1.8x that, soots the wall, and
within 0.36 of its radius of a solid wall punches a hole through it: a jagged outline, the break
through the wall's thickness traced (brick courses, render over block, concrete), a burnt room
behind it (rubble floor with embers, scorched paint, a doorway), soot round it and carried up the
wall by the smoke, the window frames and kit pieces that stood there gone, broken blocks and bent
rebar round the rim, chunks of wall thrown as debris and a cloud of dust. Downtown towers
(LandmarkDowntown / TowerMesh, `uv_facade`) take the glass damage and the scars.

**How.** `BuildingDamage` (`scripts/world/building_damage.gd`) keeps a list of at most 32 records
per building - a point in the building's own space and a kind (CRACK, SHATTER, BLAST, HOLE, POCK)
with a radius - in `WorldState.building_damage` (by `key_of()`: seed and lot), and writes them to
the facade material as two uniforms (`damage[32]`, `damage_count`). `shaders/building_damage.gdshaderinc`
does the rest in `building.gdshader`: the pane a pixel belongs to is worked out from its own cell
(its centre in model space, `inverse(MODEL_MATRIX)` only on a damaged building), so the same records
serve the boxes and the towers' outline walls. A building nobody shot pays one branch. A Building's
facade material is already its own; a tower's is shared with its twin and its far copy, so a
damaged tower's detailed copy gets its own copies as surface overrides (`_tower_mats()`). Caps:
12 scars (oldest first), 6 holes, then the oldest crack goes. Real geometry rebuilt from the same
records: `DamageRim` (one mesh a building: broken blocks or bricks in their courses round each
outline, snapped rebar bent out; `hole_radius()` is the shader's outline line for line) and
`DamageLitter` (one mesh: flat shards under every pane that fell, further out from higher up; the
ground point is a ray at the moment, stored, so a restore needs no physics). `pane_at()` mirrors
the shader's window grid for Buildings (WINDOW_RECTS, the storefront's bays, part by part), so a
second round finds the same pane; towers match by distance. Hooks (one line each):
`AssaultRifle.fire_ray()`, `Shotgun.fire_pellet()`, `PoliceOfficer`'s rounds, `Explosion.blast()`,
`Building._ready()` (`restore()`), `LandmarkDowntown.build()` (`restore_tower()`). Never on a
sanctuary (`Sanctuary.is_sanctuary()`); curtain walls and glass finishes get no hole (the blast
takes their glass). `BUILDING_DAMAGE=0` in the environment is the A/B.

**Tools.** `tools/glshot/damage_shot.gd` (one building on a slab, damage dealt through the real
entry points, opengl3; `MODE=storefront|office|hole|none`, `NIGHT=1`, `LIT=1`, `NOSHOP=1`,
`FINISH`, `BSEED`, `CAM_POS` / `CAM_LOOK`, `DEBUG=1` prints the records). Checks:
`tests/building_damage_checks.gd`.

**Frame cost.** `tools/geo_count.gd` (opengl3 + Xvfb, 800x600, default spawn), `BUILDING_DAMAGE=0`
against on: 3,651,452 triangles, 3,656 draws, 15,244 objects both ways (an undamaged city adds no
node; the shader's damage code runs only where `damage_count` > 0). A damaged building adds at
most two draws (rim, litter: a few hundred to a few thousand triangles) and its facade's fragments
loop over its records.

**Stills** (shots/building-damage; opengl3): storefront before / after / night, an office row shot
out by day and at night, a rocket hole in a brick wall before / after / at night, a blast on a
curtain wall.

**Not done / not verified.** Forward+ (the Mac) not seen: the crack web's sparkle, the shattered
room's brightness and the hole's room under AgX and auto exposure need eyes. Holes do not cut the
collision (you cannot walk in) or the shadow; the room behind is traced, not modelled, and the same
for every hole of a building. Towers get no holes or rims; a tower's records go on its detailed
copy only, so its far copy shows it whole. The roof takes no damage. Panes on a cut (chamfered)
corner never break. Glass shards are not physics; the litter is laid at once for a blast.

## 9cg. More people: eight more rigs in the crowd, 2026-10-05 (agent branch `wt/more-people`; VISUAL_ROADMAP #75)

On a downtown pavement with 200+ people the twelve crowd rigs repeated within a glance. Eight
more, `crowd_m..t`, with the same pipeline (`tools/crowd/build.sh`) and contract (24 bones, one
Body surface with region colours, the Hair mesh, metric UV2, three clips), chosen for what the
twelve lacked:

| rig | person | wears |
| --- | --- | --- |
| m | white man, 70s, tall, thin, a little stooped (neck targets), thin grey hair | navy windbreaker (our zip jacket, finally worn), stone chinos |
| n | South Asian woman, 60s, short (1.46 m), heavy, short grey hair | crew-neck cardigan (knit, button band, buttons), navy midi A-line skirt |
| o | Black teenage boy, slim, 1.75 m | pullover hoodie (hood down, drawcords, kangaroo pocket, rib hem / cuffs), black joggers with rib cuffs |
| p | white teenage girl, slim, auburn ponytail | fitted lilac tee, olive A-line skirt above the knee |
| q | Latino man, 30s, tall (1.83 m), heavy | navy pique polo (short placket, three buttons, rib cuffs), khaki chino shorts |
| r | young North African woman | dusty rose hijab-style headscarf, long loose cream tee, navy wide trousers |
| s | Filipino man, 30s, very short (1.49 m), stocky | hi-vis vest (reflective bands and braces) over a heather tee, charcoal work trousers, boots |
| t | very tall Black woman (1.94 m), braid | red-striped shirt with the sleeves rolled, black slim trousers |

### New garments (tools/crowd/garments.py, garment_paint.py)

- **Jacket options**: `collar` stand / rib / hood, `closure` zip / buttons / none, `pocket` welt /
  kangaroo / none, `knit` (stockinette painted in body coordinates). The hood worn down
  (`hood_down()`) is swept round the neckline: a soft roll round the neck that folds over and lies
  on the shoulder blades ONLY round the back. The first one spread the fold from the sides and was
  a sailor's collar over both shoulders.
- **Shirt options**: `sleeve: short` (cuffs measured on the upper arm), `placket_len`, `pique`,
  rib cuffs: the polo.
- **Joggers**: a trousers style, roomy, ending above the ankle, with rib cuffs (`leg_cuffs()`),
  an elastic waistband painted gathered, and no fly or belt loops. The fold field stacks at the
  ankle like the hero's track pant (`ankle_stack` 0.9).
- **Skirt**: one band SWEPT round a vertical axis from the waist (metric UVs, painted by
  position), its radius measured by rays on the pelvis and legs ONLY: with the arms in it, the
  hanging hands made two square wings at the hips. It falls from the hips' widest ring (never in)
  and flares by `flare`. Weights are both thighs and the hips, blurred round it (`weight_blur`,
  `hip_share`); with a 0.11 flare the stride stays inside a midi skirt in the walk.
- **Vest**: the top's shell without sleeves over the tee, the armholes cut down the sides past a
  4 cm strap (the first cut left ragged wings on the shoulders), region `keep` (never recoloured).
- **Headscarf** (`scarf`, region `keep`, built last): a shell off the head, neck and shoulders.
  Three things that each looked wrong until fixed: grown along the normals it wrapped every fold of
  the ear, so the head part lies on a SPHERICAL envelope of the skull with the ear vertices left
  out (their holes in the shell filled) and the ear skin deleted under it (`build_character.py`);
  a vertical-plane hem on the drape is a sawtooth where it crosses the near-horizontal shoulder,
  so the drape's edge is cut by DISTANCE from the base of the neck, sector by sector; and the
  oval face opening (`cut_oval()`) runs along the underside of the jaw (lower, the throat showed).
  The throat is bridged from the jaw by an Envelope hung from the chin.
- A vest or a scarf deletes the top it hides (`hide_under`, margin 8 cm); an empty part is dropped.
- `PX_PER_M` density for a swept garment's UVs (the skirt), not the shell density.

### Game code

`Pedestrian.MODELS` has twenty. `Pedestrian.NO_HAT_MODELS` (crowd_r): the hat rolls are still
made, so nothing after them moves, but no hat is put on. `Encampment.FIGURE_POOL` 12: the camp
figures (baked per model and pose on the loading screen) stay on the first twelve rigs. No new
rig is in `OFFICER_MODELS` (and so not an emergency crew): m is too old, o / p too young, q wears
shorts, s's vest is never recoloured, n / p / r wear skirts or a scarf. The life clips
(`tools/crowd/life_clips.gd`) and the hat table (`tools/crowd/hat_fit.gd`, REPORT: 0 head
vertices through any hat on the new rigs) were redone for them; the old rows did not move. The
smoke test wants 20 rigs and checks NO_HAT_MODELS.

### Cost (this box, opengl3, `--quality=0`)

| | before (12 rigs) | after (20 rigs) |
| --- | --- | --- |
| downtown_noon SPLIT (1280x720): frame | 7,613,433 tris, 4,069 draws | 7,729,097 (+1.5 %), 4,069 draws |
| - pedestrians | 431,054 (126,735 shadow), 377 draws | 546,840 (142,105 shadow), 377 draws |
| pavement EYE `2377,1.7,905,8,-4` | 6,105,092 | 6,206,610 (+1.7 %), same draws |
| pavement EYE `2377,1.7,860,172,-4` | 5,674,914 | 5,706,982 (+0.6 %), same draws |
| loading screen, people (`people_load_bench.gd`) | 3,327 ms (12 rigs 2,345 + 60 camp figures 980) | 5,207 ms (20 rigs 4,173 + 60 camp figures 1,034) |

Per rig at LOD 0 the new eight average 13.2k body + 2.9k hair against the twelve's 12.2k + 2.5k,
so the expected cost of a near person is +4 % (15.3k against 14.7k averaged over all twenty);
the downtown_noon pedestrians' +27 % is mostly which rigs happened to stand nearest the camera
(different rolls with a longer MODELS list). Their importer LODs fall as the old rigs' do.
The loading screen pays ~230 ms a new rig (limbs, welded mid / far bodies, hats).

### Stills (branch `shots/more-people`)

`lineup_front` / `lineup_q3` (all twenty), `new8_front` / `new8_q3` / `new8_heads` (the eight
close), `before_` / `after_pavement_1` (the pavement south of the downtown bookmark: n and m
walk it now), `before_` / `after_downtown` (the bookmark).

### Not done

- A blazer over a tee (asked for as an option) and a dress were not built; the skirt is the dress's
  lower half and a jacket with lapels is the next garment worth building (9av's note too).
- Bodies run 12.3-13.9k triangles, a little over the twelve's 10.5-12.9k; the knobs are each
  garment's `tris`.
- Small things up close: a thin dark line between p's tee hem and her skirt, a fold line where the
  scarf's head part meets the throat, a few frayed points on the scarf's drape edge, q reads
  "solid" more than heavy. The skirts' and the scarf's walk has only been seen in the lineup's
  walk pose and the Cycles previews, not in motion in the game.
- The headscarf has been judged by eye in opengl3 and Cycles; nobody who wears one has looked
  at it. Worth asking.

## 9ch. Public schools, playing fields and the school bus, 2026-10-05 (agent branch `wt/schools`; VISUAL_ROADMAP #76)

Number is provisional (the next free one after 9bt when this was rebased; the lead renumbers on merge).

**The brief** (lead, from the owner's "make the graphics a million times better"): LA's
neighbourhoods are full of public schools - elementary schools with portable classrooms on blocks,
big high schools with football stadiums - and yellow school buses. Place them from a hash of seed +
map cell (FireStation's approach) in the suburbs, midtown and the beach town, claiming blocks AFTER
the existing rolls and clear of Parks' claims; no scaled-down crowd rigs as children. CLAUDE.md's
"Public schools" note is the reference; this is the story.

**Placement.** `Schools.decide(plan, cell)`: a cell of 640 m has a school at `ODDS` 0.8; up to
three hashed points are tried; the block under a point (its centre in the cell) must be plain
city ground nobody claimed (`_eligible()`: Parks' list plus the river, and no Parks role). A
`HIGH_ODDS` 0.4 cell first tries a ROW of three, then two, blocks along x or z (`_row_fits()`:
every block in the cell, the streets between local (<= 15.5 m) and not a pinned real road, the
site 72-192 x 175-320 m). The hook is ONE line at the end of `CityPlan.block()` (after the block is
cached): `Schools.apply()` marks the block SCHOOL with grounds `school_e` / `school_h`; inside a
decision it is a no-op (`_deciding`) and the decision marks its blocks itself, so a block is never
seen undecided and nothing recurses (only blocks in the deciding cell are asked for). The streets
between a high school's blocks close through ONE line in `CityPlan.road_open()`
(`Schools.road_closed()`: a lazy per (axis, road, block) cache; open again in the crossings at
both ends, so the cross streets and their junctions stay). Default seed, a 12 km window: 22
schools, 4 of them high schools (two on three blocks); `WHY` in the probe counts what cells lose
(mostly not city ground, then ineligible blocks, then blocks too small or stretched by pinned roads).

**Layouts** (pure, `plan_for_school()`, in the site's street frame: `s` along the front street, the
widest one; `d` in from it; mirrored by a hash). ELEMENTARY: a 4.5 m front lawn with trees, the
marquee sign and the flagpole; the office (glazed front, entry canopy, the name in standing letters)
by a 6 m entry gate; classroom wings of 28-46 m along the front, alternating one and two storeys,
covered walkways on the yard side (a balcony walk and stair on two storeys); a side wing down one
edge whose yard end is a primed blank wall for the murals pass (`K_MURAL`); the staff car park
(LotFill's); then the blacktop: a row of 2-5 portables up on blocks with skirts, T1-11 siding, a
heat pump and an ADA ramp with rails, numbered; a grass field with a kickball diamond (Parks'
kind 2 from its home corner) and backstop; two basketball courts; four-square / hopscotch games
with tetherball poles; the painted map (new park-ground kind 13: the lower 48 outlined, patched in
five colours, a star on Los Angeles, a compass rose); the lunch shelter with steel-frame tables; a
play structure and swings on poured rubber; up to ten tree wells; chain-link round the yard. HIGH:
the stadium at one end (Parks' `_track()` - 300-400 m by the site, the football field inside at
regulation or scaled, the end zones in the school colour - bleachers and a press box on the home
side, a scoreboard behind an end zone, six 26 m light standards whose lenses glow only on a game
night, `pl.game_night`, with light pools on the field); along the front two-storey classroom wings,
the office and the auditorium (glazed lobby, canopy, a fly tower with the name on it); behind them
the gym (a gable standing-seam roof, clerestory, HOME OF THE <mascot>), tennis courts, two courts,
a lawn quad with trees and benches, the lunch shelter, a car park, two portables.

**Drawing.** Every ground piece is Parks' (`Parks._ground()` into `ch._park`: the Parks ground
mesh, no new draw), clipped to the chunk's owned rect (`_gp()`) so a stadium across a closed street
is built half by each chunk with its lines running through the cut. Sports kit goes into the Parks
walls mesh (ParkKit). The buildings, signs, flag, scoreboard and light standards are ONE new mesh a
chunk (`SchoolWalls`, `shaders/school_walls.gdshader`, kinds `SchoolKit.K_*`): each wall face its
own window layout (`SchoolKit.wall()`: UV2.y = style + 16 x whole bays, centred), and behind every
window a classroom traced per pixel - back wall with a whiteboard and cork boards, cubbies, posters,
VCT floor with rows of desks, an acoustic ceiling with troffers, a blind per room; lit by day,
`room_night_share` of rooms lit after dark - the glass mirroring `sky_tint` by Fresnel. Letters are
`FreewayKit.text_geo()` flat triangles; the LED board's message and the scoreboard digits glow. A
closed street gets a pavement slab (collision) from the chunk that owns it, and Skyline no longer
paints a closed street on the far plate (one line in `_add_plate()`; this also stops it painting
MacArthur Park's closed streets). LOD and the far city: the ground as partitioned slabs, the
buildings, portables, stands and light standards as far boxes (the auditorium's fly tower its own).

**The school bus.** `tools/make_school_bus.py` (Blender 4.2, on make_big_vehicles; about ten
seconds): a 40 ft Type D (transit-style, the kind California districts run): flat face, two-piece
windscreen under the SCHOOL BUS sign between eight-way warning lamps (a new `amber` slot), the
folding entrance door ahead of the setback front axle, 10-11 split-sash windows a side, three rub
rails, the STOP arm folded on the driver's side, the crossing arm on the bumper, the rear
emergency door between two windows, roof hatches, RANDO UNIFIED SCHOOL DISTRICT on both flanks
(Blender's built-in font), 54k triangles + a 10k far twin. `BodyType.SCHOOL_BUS` is appended after
the second wave of cars (BODY_ODDS 0, not in ROLL_MAP); BigVehicles makes it (yellow paint,
`MASS_SCALE` 7, the bus's 60 m far-twin distance); CarCabin draws its rows EMPTY (`empty_rows`).
Parked: 1-3 in each school's loading zone on the front kerb (`bus_spots()`, real drivable
Vehicles under the city root, like parked cars; `keeps_clear()` keeps parked cars off the zone and
off a closed street). In traffic: `TrafficManager._street_kind()` asks `Schools.traffic_bus()`
(BUS_SHARE 7 % of street spawns within 1.4 km of a school between 6:48-8:36 and 14:12-16:12,
reusing the roll it already made, so no traffic roll moves).

**Frame cost** (`still_shot.gd` GEO, opengl3, the Jacaranda elementary school, `SCHOOLS=0` the
before; the first EYE of a run is taken before the ring has streamed and is left out):

| view | with schools | without (the block's buildings) |
|---|---|---|
| aerial from the south-east, 35 m | 5.65 M tris, 3,229 draws | 6.39 M tris, 3,604 draws |
| aerial from the east, 60 m | 2.74 M tris, 1,672 draws | 3.41 M tris, 2,085 draws |

A school is cheaper than the block of buildings it replaces (fewer Building nodes, its ground in the
Parks mesh). One chunk's school mesh: 1.5-6k triangles (checks; 160k budget); the high school's
three FULL chunks 6.0k, 1.5k and 0.7k.

**Stills** (opengl3, on `shots/schools`): `elem_street_noon` (Jacaranda from the street: the
office, the marquee, a parked bus), `elem_aerial` / `elem_aerial_before` (the same EYE with
`SCHOOLS=0`), `elem_yard` (on the blacktop), `elem_street_night`, `hs_stadium_night` (Spring High
at 20:18, the field lit), `hs_stadium_noon`, `hs_buses` (three buses at the kerb),
`hs_three_blocks` (Sunset Ridge High over two closed streets), `bus_front3` / `bus_rear3` /
`bus_side` (Cycles previews of the model). EYEs: Jacaranda street `EYE_AGL=1
EYE=1022.8,1.7,-422.4,61.7,-4`, aerial `1060,60,-480,90,-30`; Spring High night
`2235,60,3700,55,-26@20.3`, buses `2222,2.2,3690,75,-6`; `tools/schools/probe.gd` prints one for
every school.

**Not done / not verified.** No people on the campuses at all (the brief: no children; staff were
optional and left out). The warning lamps and STOP arm do not flash or swing (a parked bus is
loading nobody). The school bus in traffic is checked by its rule, not seen in a still. Forward+
not judged: the traced classrooms, the brick and the stadium lights under AgX need the Mac. A
school claimed a block that a fire station's cell may have wanted (FireStation then finds no lot
there and its cell has no station). Skyline's far plate under a school is one average colour
(red track, asphalt), as a rec park's is. The murals pass paints the primed walls (`K_MURAL`).

## 9ci. An AAA sky: volumetric cumulus, contrails, a dated moon, stars and the light dome, 2026-10-05 (agent branch `wt/sky`; VISUAL_ROADMAP #77)

**What changed.** `shaders/sky.gdshader` (rewritten round the old one: every old block is kept),
`scripts/world/day_night.gd` (the date and the moon), a new `SkyExtras` node
(`scripts/world/sky_extras.gd`, made by DayNight as its child), `tools/sky/` (the noise generator
and a sky-only shot tool), `assets/textures/sky/` (two noise images), `tests/sky_checks.gd`.
- **Cumulus as a volume (Forward+, `cloud_detail` on).** A march through a slab 1.45-3.15 km up in
  Godot's half-resolution sky pass (`use_half_res_pass`, guarded by `CURRENT_RENDERER`; the full
  pass composites `HALF_RES_COLOR`). Columns from a 30 km weather map (R where, G how tall), a dome
  over a flat base, eaten by a 64^3 Perlin-Worley; light: four taps toward the sun (the moon after
  dark), three octaves of multiple scattering, a dual-lobe phase (silver linings), powder, sky
  ambient above and ground / city bounce below; aerial haze by distance. Coverage over 0.8 turns
  it into a flat stratus ceiling (the weather states). Two traps found on the way: a fixed number of
  steps through the slab, and coarse steps entering a cloud, both draw every edge as a COMB of
  per-pixel spikes - steps now grow with distance and back up to fine steps on entering a cloud;
  and the billows (no mips in a 3D texture) fade to a five-times-coarser copy where a pixel spans
  them. Compatibility (web) and Forward+ below MEDIUM keep the old painted deck
  (`painted_cumulus()`); the mid deck is thinned next to the volume.
- **Crepuscular rays** in the same half pass (`sky_rays()`: eight weather-map fetches toward the
  sun, the light through the gaps streaming down the line), golden hour strongest. Forward+ only.
- **Contrails.** SkyExtras flies `contrail_jets` (4) airliners straight across at 9-12 km (not
  AirTraffic's, which stay under 1.5 km). A trail is one segment: head minus (heading x speed -
  wind) x age; the shader intersects the view ray with its height, spreads it with the square root
  of age, fades it over the jet's `trail_life` (45-700 s), breaks it where the air is drier, lights
  it from the sun after the street's sunset (pink), and draws the jet as a glint. `CONTRAILS=n` /
  `--contrails=n`.
- **The moon.** `DayNight.moon_age_days` (default 11.7, the old fixed 9.5 h offset) plus
  `day_count` (turns over at midnight) plus the hour give its age; it trails the sun by age / 29.53
  of a day, so its phase and place come from the date (`--moonage=14.8` full, `4` a crescent;
  `?moonage=` on the web). The face: the near side's seas as a table of ellipses, crater relief lit
  by the real sun direction, Tycho's rays, Lommel-Seeliger shading (a full moon is flat-bright to
  its limb), earthshine on a crescent. Moonlight's energy scales with the phase (unchanged at the
  default gibbous) and lights the night cloud edges (the march's key light).
- **Stars and the light dome.** Three star layers of round, antialiased points, many faint and few
  bright, thinned by `sky_dark` (how much city surrounds the camera), washed out under the dome
  and round a bright moon; the milky way only where it is dark (over the ocean, up a mountain).
  SkyExtras surveys the map zones on rings at 1.5 / 4.5 / 10 km every 1.5 s and pulls toward
  downtown: `city_dir`, `city_wrap` (how much of the horizon it wraps), and `city_glow` (from
  `lamp_factor`, brighter under overcast) - an orange glow climbing from the horizon that also
  lights the cloud bases. Compatibility gets it raised to its sRGB-added equivalent.

**Cost.** Sky-only frame, 1280x720, lavapipe Forward+ (`tools/sky/sky_shot.gd BENCH=8`, noon,
looking north, ~60 % of the frame sky): old shader 710 ms, new with the volume 778 ms (+9.5 %),
new with the painted path (`DETAIL=0`, what MEDIUM-off and the web run) 658 ms. A city frame has
far less of its time in the sky. No geometry: the city's triangles and draws are unchanged (the
stills' GEO lines are the same frames' as before).

**Tools.** `tools/sky/sky_shot.gd` (the city's own Environment and DayNight, no city: seconds on
opengl3, a minute or two on lavapipe; HOUR, YAW, PITCH, FOV, MOONAGE, COVERAGE, CONTRAILS, DOME,
DETAIL=0, SHADER= another sky for the A/B, BENCH), `tools/sky/make_cloud_noise.py` (numpy, PIL).

**Stills** (shots/sky): Forward+ sky-only (`sky_shot.gd`): midday cumulus before / after, golden
hour toward the sun with rays before / after, a contrail sky, the full moon at 23:00, a crescent
at 19:40 under a forced dome; opengl3 city stills (the Compatibility path: painted clouds, the
moon, stars, the dome): the full moon from the pier at 23:00, the dome over the city from the
pier, a crescent over downtown, midday over the hills.

**Not done / not verified.** The volume has never been seen in the city on Forward+: the whole
city (and even LIGHT_WORLD with a 900 m far city) is OOM-killed under lavapipe on this box, so the
volumetric stills are sky-only over a flat ground. NEEDS MAC CHECK: the march's dither under real
TAA at 60 fps (some small teeth remain on cloud tops in a no-TAA frame), night cloud brightness
under the player camera's auto exposure, the dome's strength, the frame cost at HIGH on the Mac.
The cumulus cast no shadows on the ground. Contrails are thin lines, never a double trail from
four engines; the jets carry no lights at night. The flying player can climb into the deck (it is
drawn correctly from inside and above) but nothing fogs the near view there. The moon's lunar
north is not tilted with latitude. The weather session (weather.gd) drives cloud_coverage /
cloud_extra as before; a marine-layer stratus look would sit on top of `strat` in `cumulus()`.

## 9cj. The map: minimap, full-screen map, waypoint and GPS, 2026-10-05 (agent branch `wt/minimap`; VISUAL_ROADMAP #78)

**What.** The minimap and a new full-screen map draw the same thing through one painter
(`MapPainter`, `scripts/ui/map_painter.gd`). It covers: hill-shaded mountains, faint 100 m
contours, the sea, surf and sand (`shaders/map_relief.gdshader`, painted from the horizon plane's
own basin bake); blocks by district and kind; rec-park and school facilities (diamonds, fields,
tracks, courts, pools) from `Parks.plan_for()`; streets and avenues with casings; hill roads; the
Esplanade; MacArthur's lake; the LA River with its bridges; runways, taxiway and concourse; the
three piers; freeways and their ramps with **route shields** carrying `FreewayKit.route_number()`
(an original teal badge, never a real marker); the **Coral Line** (solid in the open, dashed
underground) with its stations; landmark **glyphs** (tower, civic, dome, plane, ship, pier, venue,
tree, bag, cup, rail, star) with names. The full map adds district names zoomed out and street
names zoomed in. Both draw the GPS route, the waypoint pin, police and fire / ambulance blips
(group `emergency_unit`) and the player arrow.

**The full map** (`WorldMap`, `scripts/ui/world_map.gd`, a CanvasLayer at 4 that DebugHud adds) is
the new `map` action: **M / pad Back**. Respawn's pad button moved from Back to **L3**, since
Back was taken. Opening the map pauses the game (GTA style). Controls: drag to pan, wheel to
zoom about the cursor, click to set the waypoint (click it again to clear), right click to clear,
WASD / arrows and Q / E as keys, Space sets the waypoint at the centre. On a pad: left stick pans
a centre cursor, the triggers zoom, A sets, X clears, B / Back closes. Esc closes it too. Panels
use the HUD's smoked glass (`glass_hud.gdshader` mode 1): the title with the district and the
waypoint's distance, a legend of 14 symbols, the controls, a scale bar and a north arrow, all in
1080-line units. The ground plan is drawn once into a Node2D in world metres, and panning or
zooming only moves it. It is redrawn when the zoom moves 35 % or the view leaves what was drawn.
Zoomed out it holds the whole basin; zoomed in, a margin round the view.

**Data.** `MapData` (`scripts/ui/map_data.gd`, `MapData.of(plan)`) holds the basin's land blocks
(3,478 on the default seed) and their two roads as records, with a 500 m cell index. The HUD warms
it 1.5 ms a frame from load; the whole build is ~1 s. The minimap's neighbourhood is filled first
(`ensure_rect()`). It reads CityPlan only and rolls nothing. Closed roads (MacArthur Park's inner
streets, the river's dead ends) are not drawn. On the map, an "avenue" is a road at least
`avenue_width - 1` wide: downtown's real 18-22 m streets read as streets, not as a yellow mesh.

**GPS.** `GpsRoute` (`scripts/ui/gps_route.gd`) is A* on a binary heap over the intersection grid.
An edge is usable when it is `StreetRoute.drivable()` and `CityPlan.road_open()`. Avenues cost
0.8 of a street's metre. Both ends snap to the nearest open stretch and may enter it at either
end. The search runs time-sliced (`route_budget_us` 1.5 ms a frame), with no search box (it
crosses the basin) and at most 40,000 nodes. Probe on the default seed: downtown to Westlake 4.2 km
in 36 ms, downtown to the port 5.8 km in 28 ms, 6 km across midtown in 47 ms. The route is
recomputed from where the player is once they are `off_route` (38 m) from it, and cleared within
`arrive` (28 m). The **beacon** (`shaders/waypoint_beacon.gdshader`) is an additive, fog-free violet
beam 420 m tall plus a pulsing ground ring, widened with distance so it never drops under ~2 px.
It is a Node3D under the CanvasLayer, placed from true world coordinates every frame, so origin
shifts never touch it.

**Tools.** `tools/minimap/map_shot.gd`: `SHOTS=mini;map:x,z,ppm;beacon`, `WAYPOINT=x,z` or
`WAYPOINT_AHEAD=m`, `STARS=n`. It prints `MINIMAP draw` (the minimap's CPU time per redraw) and the
route. `tools/minimap/probe.gd` (headless, seconds) prints MapData's size and build time and a few
GPS routes. Checks: `tests/minimap_checks.gd`.

**Frame cost.** The 3D frame is unchanged: the map adds no geometry until a waypoint is set, and
then two draws (the beam and the ring, ~70 triangles). MapData costs 1.5 ms a frame on the CPU for
the first ~1 s after load. The minimap redraws 10 times a second as before; its draw time is in the
stills section. The full map pauses the game.

**Stills** (shots/minimap, opengl3): the minimap downtown with Flower's dashed Coral Line and the
33 shields; the full map over the whole basin; the full map zoomed into downtown with street,
station and tower labels; a GPS route on both; the beacon in the world.

**Not done / not verified.** Forward+ (the Mac) is not seen, though everything here is 2D or
unshaded and should match the stills. Mouse and pad input were not driven in the harness; the
click, zoom, pause and close paths are driven by the checks through the same functions. The route
uses the street grid only: it never takes the freeways and never routes into the hills (hill roads
are drawn, not routed). Street names on the full map label one run per road. District labels come
from block counts and can repeat on a long district (INDUSTRIAL shows several times zoomed out).
Railway and river labels are in the legend only.

## 9ck. Los Angeles weather: the marine layer, the Santa Ana, heat haze, 2026-10-05 (agent branch `wt/weather`; VISUAL_ROADMAP #79)

**What.** Two LA states join clear / overcast / rain / storm (`Weather.State.MARINE`,
`SANTA_ANA`, appended; every per-state table has six rows), plus heat shimmer and rain bursting on
car roofs. Pause menu: WEATHER is now two rows of chips (Auto, Clear, Cloudy, Rain / Storm,
Marine layer, Santa Ana). Debug: `--weather=marine|santa_ana` (web `?weather=`; aliases `gloom`,
`santa`, ... in `Weather.STATE_ALIASES`). The auto roll uses `Weather.odds_at(hour)`: the marine
layer x2.2 overnight and in the morning, x0.35 in the afternoon; the Santa Ana 5 %; both last
3-4 rolls long (`marine_length_gain`, `santa_ana_length_gain`).

**The marine layer ("June gloom").** Where the deck is, is ONE number of the hour:
`LaWeather.edge_x()` (`scripts/world/la_weather.gd`, pure) - the stratus covers everything WEST of
it (the coast runs north-south at `MacroMap.coast_base_x`), wobbled along the coast by
`edge_wobble(z)`, which `shaders/marine_layer.gdshader` copies (checked). Overnight it is 9 km
inland (the whole basin is under it); from 09:20 it burns off inland first (downtown clears about
10:25, the beach about 12:00); all afternoon it waits ~2.3 km offshore as a bank; from 17:00 it
rolls back in LOW (`deck_heights()`: 130-300 m instead of 255-520 m), standing about 1.5 km off the
beach at 18:30, ashore by 20:30, over the city by 22:00. `MarineLayer` (a child of Weather) draws
it: the underside and the top as two planes (8 km radius, snapped to 400 m in true world space,
one face each) and the evening bank as a ribbon (16 km of it along the coast, stood on the edge,
billowed and domed in the vertex shader). Three transparent draws, shadowless, hidden at weight
0. The deck fogs itself (`fog_disabled`, the scene's fog colour and density handed over) because
of the next point. **Under the deck at the camera** (`Weather.marine_here` = the state's weight x
cover x `under_deck(cam y)` - above the deck top it is a sunny day over a white sea) Weather adds
cool haze (`marine_fog`, `marine_volumetric`, more where the evening bank has come ashore) and
switches Godot's height fog to a NEGATIVE density from `LaWeather.fog_start()` (thicker going
UP): the tops of downtown's tallest towers and the hill crests fade into the deck. Each half of
that blend runs its own density to zero before `fog_height` changes, and everywhere else the
city.tscn ground haze (16 m, +0.0006) is put back. DayNight's new `marine` hook greys the sky
(`marine_top` / `_horizon`, the city's sodium light on it at night), cuts the sun
(`marine_sun_cut` 0.74) and cools it, softens its shadows (`shadow_opacity`, `marine_shadow_cut`
0.72), lifts the sky fill (`marine_ambient_gain`), drops the golden-hour smog. All marine colours
are pushed bluer than neutral: through the look LUT a neutral grey came out beige (measured
150/148/141 on the first still).

**The Santa Ana.** `fog_by_state` 0.000035 (about 110 km of visibility) and almost no volumetric
haze; DayNight's `santa_ana` hook: a deeper zenith (`santa_top`), a dusty horizon and fog
(`santa_horizon`, `santa_fog`), a warm sun (`santa_sun`), half the smog, fewer clouds.
`wind_factor` + `santa_ana_wind` (5) and a NEW global `wind_lean` (vec2 world XZ, length 0..1,
toward the south-west, `LaWeather.SANTA_ANA_DIR`): `foliage.gdshader` and `foliage_tex.gdshader`
lay every palm and tree over downwind in model space (a 4-line block each after the sway; the
global is declared in project.godot). `SantaAnaFx` (a child of Weather): dry leaves and scraps
of paper tumbling past the player (90, alpha-cut billboards, half on the web) and low dust
streaming over the ground (26 puffs), emitted upwind; and the **brush fire** on
`LaWeather.fire_site()` - a crest of the front range north-west of downtown picked by a hash of
the seed from the highest ground in `FIRE_WINDOW` (default seed: (-100, 470, -1400), on the ridge
above the hill sign, ~3 km from Pershing Square): a smoke column of 80 camera-facing puffs
(CPUParticles3D in LOCAL coords, so it rides the origin shift; `shaders/brush_smoke.gdshader`
lights each as a ball from the script's sun and sky colours and glows its underside with the fire
after dark), an upright additive card with a soft glow and a flickering flame line
(`shaders/fire_glow.gdshader`, deliberately NOT through cs_out(): on the Compatibility renderer
an additive glow's faint tail turned into a visible rectangle), and on Forward+ desktop an
OmniLight that colours the slope at night. Purely visual: nothing burns or spreads.

**Heat haze.** `HeatHaze` (`shaders/heat_haze.gdshader`): one full-screen quad at
render_priority MIN reading the screen (the explosion shimmer's rule), displacing the picture by
rising noise along grazing rays (`graze`, elevation under ~4 degrees) past `near` (30 m), full at
`far` (450 m) and on the sky at the horizon; `discard` everywhere else, so the cost is the
horizon band. `Weather.heat` = `LaWeather.afternoon_heat(hour)` (10:30-18:00) x (clear 0.5,
Santa Ana 1.0, a burnt-off marine day 0.35). Built only where `HeatHaze.supported()` (Forward+,
not the web, not headless) and shown only at HIGH and MEDIUM. **Never seen in a still**: every
still here is opengl3, where it does not exist.

**Rain on car roofs.** `RoofRain` (a child of Weather): one MultiMesh of 220 crown splashes
(`shaders/roof_splash.gdshader`: eight droplets on ballistic arcs over a spreading ring, the sky's
colour by day, lamp-lit at night), animated in GDScript on the roofs of the ten nearest cars
within 26 m (`Vehicle._model_top_y` over the `_dims()` cabin), 34 a second per car at full rain.
Drips off awnings were not done (the awnings are kit instances inside each building's batch; no
cheap way to find their edges without a per-building query).

**Files.** New: `scripts/world/la_weather.gd`, `marine_layer.gd`, `santa_ana_fx.gd`,
`heat_haze.gd`, `roof_rain.gd`; `shaders/marine_layer.gdshader`, `brush_smoke.gdshader`,
`fire_glow.gdshader`, `heat_haze.gdshader`, `roof_splash.gdshader`; `tests/weather_la_checks.gd`;
`tools/weather_probe.gd` (the front range's heights, the fire site, palm-lined blocks round a
`--spawn`). Touched: `weather.gd` (states, odds, `_update_la()`), `day_night.gd` (two hooks, an
export group, the frame's light published), `pause_menu.gd`, `foliage.gdshader`,
`foliage_tex.gdshader`, `project.godot` (`wind_lean`), `tests/smoke_test.gd` (one line).

**Checks** (`tests/weather_la_checks.gd`, 25): the clock (covered overnight, downtown clears
before the beach, the bank offshore in the afternoon, a low wall off the beach at 18:30, back by
night), the shader's wobble mirror, forcing each state (DayNight hooks, negative height fog,
shadowless light, the deck drawn / hidden, clearer air, the lean's direction, the fire on a
front-range crest), heat by hour and weather and only where drawable, the roll's odds by hour, a
splash on a car's roof, the menu's chips.

**Frame cost** (`tools/geo_count.gd`, opengl3 + Xvfb, 800x600, the default spawn, `AB=` the new
nodes hidden in the same frozen frame): the marine layer's three draws (deck under, deck top, fog
bank) 1 draw and 2 triangles in that view (3,659 -> 3,658 draws, 3.65 M triangles either way);
the Santa Ana's smoke column, glow card, litter and dust 3 draws and ~400 triangles (3,448 ->
3,445, 3.6413 -> 3.6409 M); the roof splashes 1 draw (no car in reach there). Clear at 15:00 is
3.64 M / 3,443. The heat haze is one full-screen quad on Forward+ that discards outside the
horizon band; not measurable on opengl3 (it is never built there).

**Stills** (branch `shots/weather`, opengl3, before = `--weather=clear` from the same eye): the
skyline from the south-west at 09:00 under the deck (grey ceiling, tower tops and the mountains
into it, soft shadowless light) and at 15:00 burnt off; the beach by the pier at 18:30 with the
fog bank low on the sea, and the same bank from the front range rolling along the coast; a
midtown palm street at 15:00 in a Santa Ana (deep sky, warm light, the smoke column off the
ridge); the brush fire at 22:00 from over midtown and from the palm street. EYEs in its README.

**Not done / not verified.** Forward+ (the Mac) not seen: the grey under the deck and the Santa
Ana's warm cast through AgX and the auto exposure, the volumetric fog under the deck, the fire's
OmniLight on the slope, and the heat shimmer at all (Forward+ only). The tree lean is in the
foliage shaders only: grass, hill shells and the palms' far canopy blobs do not lean; no flags
fly. The Santa Ana has no sound of its own (ambience.gd is the audio session's: a gusting wind
bed keyed to `Weather.santa_ana_weight` is the hook to add). The deck's edge is a straight line
north-south plus a wobble, so in the south (the peninsula, the bay) it does not follow the coast;
the evening bank is a ribbon along that line and crosses the headland. Under the deck the far
city and the mountains fade by Godot's height fog; the far ground plane's own haze is not told
about the deck. Drips off awnings not done (see above). Sea-level fog on the streets as the bank
comes ashore is depth fog only (no ground-hugging volume).

## 9cl. Broadway's theatre district: the movie palaces, 2026-10-05 (agent branch `wt/broadway`; VISUAL_ROADMAP #80)

The historic stretch of Broadway between 3rd St and Olympic Blvd (DowntownReal pins it 1:1 on
every seed: x 2991, z -403 .. 1006, west blocks bx 27 and east bx 28 on seed 1337) now reads as
the real street's FORMS with invented names: eleven movie palaces with blade signs, chasing
marquees and terracotta fronts, the 1920s commercial blocks round them with Spanish/English
discount, electronics and bridal shops, its own cast-iron lanterns, goods racks and gowns on the
pavement, a street clock.

**Where** (`Broadway`, `scripts/world/broadway.gd`): `THEATRES` lists each palace by its REAL
house number on S Broadway (odd east, even west; 307, 518, 534, 615, 630, 703, 744, 802, 812, 842,
933 - the real palaces' addresses), turned into a game z by the real cross streets
(`address_z()`: the 300 block is 3rd to 4th St ... the 900 block 9th to Olympic). Each takes the
Broadway-fronting lot of the seeded block holding its address (`palaces()`, cached per seed; the
nearest free one within `LOT_REACH` 60 m when an earlier palace has it - the 802 / 812 pair share
a real block face). `CityChunk._build_lot()` asks `Broadway.claims()` after the fire station's
check (the pad roll is made), so no other lot moves. `tools/broadway_probe.gd` prints them with
an EYE each. Names, shows, shops: all invented (the checks fail on a real palace's name).

**The palace** (`BroadwayTheatre`, `scripts/world/broadway_theatre.gd`), in its own frame (x
along the street, +z out, the face at z 0), filling its lot's whole frontage: a ground storey of
shopfronts (piers, bulkheads, display glass, transoms, painted sign boards with the shops' names,
striped awnings) either side of a recessed entrance (terrazzo sunburst, a row of glazed doors in
brass, lit poster cases, a bulb soffit, the octagonal ticket booth); the PAVILION (the palace's
own front, `pavilion_width()` 16-26 m) in its `Style` - FRENCH (a giant arched window with
voussoirs and a real hole in the wall, paired columns, side bays with balconettes, entablature,
cornice with dentils and modillions, an attic with a balustrade, urns and a crest), SPANISH (a
tall office shaft with a churrigueresque frontispiece: estipites, nested frames, carving, an
arched window, a crest of scrolls; Gothic piers ending in pinnacles), DECO (fluted fins stepping
up past the parapet, chevron spandrels, speed lines, a stepped pylon); wings either side
(terracotta, or brick with windows when a wing is over 9 m wide, so a 78 m frontage is not one
long terracotta front); a clock tower on one (`tower`), a rooftop name sign on another
(`roof_sign`); the brick auditorium and fly tower behind out to the lot's back. The marquee
(`marquee_plan()`: a vee, flat or drum front) is boards between two bulb rows round its plan,
neon along its top and bottom edges, a bulb soffit, the name on a crest in lit letters, tie rods;
the blade sign (`_blade_sign()`) an enamel slab out over the marquee with the name STACKED letter
by letter on both faces, a bulb border and a column of bulbs on its front edge, a neon outline, a
pointed foot and a crown. Masonry: `landmark_facade` (LandmarkMats, floodlit after dark);
everything on the street front is ONE surface on `shaders/broadway_sign.gdshader` (kind in COLOR.a
x 16: enamel, bulbs with a three-phase chase, neon, bulb-studded letters that spell out row by row
then flash, the backlit letter board, the soffit, board type, iron, brass, glass, poster cases,
terrazzo; one material per palace for the sequence's phase). Lettering is TextMesh geometry
(`ShopfrontKit._text_geo`) merged into that surface. A palace is one MeshInstance3D (about 7
surfaces), box collision (front, auditorium, marquee, sign), two occluder boxes, one lamp-group
OmniLight under the marquee and two `bw_pool` light pools (warm, and the neon's colour). LOD and
the far city: the front and auditorium as `lod_box`es and the blade sign and marquee as lit
PANEL plant boxes (building_lod lights them after dark), so the column of signs shows from afar.

**The street** (`BroadwayStreet`, `scripts/world/broadway_street.gd`): the lamps along Broadway's
pavements in the stretch take CityChunk's lamp slot (`Broadway.lamp()` in `_build_sidewalk_props`;
same prop kind, same counter, so prop ids do not move) with an original lantern (octagonal plinth,
fluted column, collar, a cross-arm with two pendant globes and a lantern on top; lathe-built, the
globes lit by `lamp_factor`); goods outside the shops (`bw_rack` clothes racks, `bw_gown` ball
gowns on dress forms in the instance colour, `bw_table` sale tables) every `GOODS_STEP` by hash,
off the palaces' frontages and the corners; the street clock (`CLOCKS`: Broadway & 7th east,
Broadway & 4th west) whose dials (`shaders/broadway_clock.gdshader`) follow DayNight's hour
(`ClockSync`, once a second) and the palace clock tower uses too. `Broadway.dress()` (one line in
`_build_lot`, both levels) makes every other Broadway-fronting building masonry, under the old 150
ft limit (`HEIGHT_LIMIT` 46 m), and names its shops from `BROADWAY_SHOPS` through
`Building.name_pool` (appended to `SHOP_NAMES` after the old 30; every other building rolls the
old 30 exactly - checked).

**Shared files touched**: city_chunk.gd (4 hook lines: the claim, dress, the lamp, a block step),
building.gd (the appended names and `name_pool` in `shop_names()`), shopfront_kit.gd
(`_face_names()` now asks `Building.shop_names()`), smoke_test.gd (one line).

**A/B**: `BROADWAY=0` in the environment. Checks: `tests/broadway_checks.gd`. Stills
(`still_shot.gd`, opengl3): Broadway south from 6th St `EYE=2984,1.7,170,180,4` at noon and
`@21`; the Empress across the street `EYE=2981,1.7,234.8,-90,10`; La Paloma `2998,1.7,255.4,90,12`.

**Not done / not verified**: no Forward+ look (the bulbs' and neon's bloom, AgX on the red neon,
the terrazzo's polish) - Mac eyes needed; the palace interiors are not modelled (the doors are
glass); the encampment pieces stand in front of some palaces (Encampment's own placement, left
alone); the 802 / 812 palaces share a block face so the 812 one stands on the next lot south.

## 9cm. The four-level stack: where the 110 meets the 101, 2026-10-05 (agent branch `wt/stack-interchange`; VISUAL_ROADMAP #81)

**What.** At the real four-level interchange north-west of downtown (DowntownReal's
`four_level_interchange`, where FREEWAY_110 and FREEWAY_101 cross) the 110 used to be lifted 7.5 m
over the 101 by `Freeway._separate_crossings()` and the two simply crossed. Now it is a stack:
the 110 at level 1, the 101 at level 4, and the four directional LEFT-turn connectors at levels
2 and 3, each a long curve banked into the turn on tall single columns with hammerhead caps,
leaving its parent edge to edge through an opening in the parent's barrier and coming back onto
the target the same way. From the air it is a knot of curving ribbons; at night the connectors'
davit lights run in curving rows.

**Why it is tall (~26 / 34 / 42 / 50 m on the default seed).** The 101 leaves the stack westward
on its 2 km climb to the pass at the 7 % grade limit (it was 32 m at the crossing and 48 m 224 m
further west). A connector can only fall at the grade limit too, so one tied to that leg can never
get under the 101 near the crossing, and one tied to the east leg (low) never over it. So
`FreewayStack.prepare()` holds both main lines LEVEL through a window round the crossing (raise
only, `_clear_ground`'s relaxation, nothing outside the window moves): the 101 at its height at
the window's west end, the 110 three deck separations under it, its 231 m north stub climbing away
past the crossings (`STUB_GRADE`) so the connectors tied to it have height in hand. Every metre of
window on the climbing side lifts the whole stack 7 cm, so the planner tries the least extra run
there (`climb_ext` 0 / 30 / 60 / 90 m) and the spreads of level (`SLACK`) until the connectors
solve; the default seed solves at 30 m. With nothing feasible there is no stack and the decks
cross the old way (a warning; `STACK=0` forces it).

**The solver.** Each connector's centre line is built first (`_path()`: the parent's offset
polyline through TOUCH / TAPER / EXT, a cubic Bezier circle of about RADIUS between the tangent
points, the target's offset polyline back), resampled every 8 m. Its height bounds: equal to the
parent / target on the touch runs, over the 110 and under the 101 (DECK_SEPARATION) wherever the
footprints overlap - except beside its own parent / target in the leads - and over the street.
The envelopes are the lowest and highest a GRADE_SOLVE-limited profile can be; the profile is its
level clamped between them, smoothed for vertical curves and clamped again (a clamp between
Lipschitz bounds stays Lipschitz). Then the crossing pairs (the connectors that cross go on
different levels; the crossing graph is 2-coloured) are pushed apart where they fall short of
LINK_SEP, the shortfall split by each one's room, until none falls short; `verify_all()` checks
every overlapping pair and every grade at the end, and the checks call it again.

**The build.** Connector segments come out of `Freeway.segments_in()` and `blocks()` like any
deck (`route` LINK_BASE + k, `link` true), so the lots under the stack become the right of way
(YardFill), trees and lamps keep out, the bake draws it, AirTraffic clears it, and the far city's
deck boxes include it. FreewayKit skips them; StackBuild builds them into the chunk's same four
freeway meshes (no extra draws), with banked collision boxes and a cylinder per column. On the
main lines the kit opens the outer barrier and drops the edge line where a connector touches,
skips light standards and gantries under a deck, and skips the two bents whose columns would stand
on a lower deck; StackBuild puts single hammerhead columns under the main line instead. The far
city (Skyline) draws the stack's columns and caps as boxes and skips the same bents.

**Traffic.** `StackTraffic` drives each connector by distance (four cars a connector, two on the
web). Hand-over both ways with TrafficManager: a freeway car within 18 m of a diverge in the right
direction is taken now and then (`take_share`) and drifts across the open touch run into the
connector's lane; at the end the car drifts onto the target's outer lane and joins
`freeway_cars`. When nobody can be taken a car appears on the connector away from the player.

**Tools.** `tools/stack/probe.gd` (headless, seconds: levels, connectors and their profiles,
columns, verify, EYEs on each connector; `SEED=`), `tools/stack/compile.gd`, `STACK_DEBUG=1`
prints the solver's tries.

**Checks** (`tests/stack_interchange_checks.gd`, 20): planned with four connectors at the real
interchange, the 110 under the 101 three separations apart, verify_all() clean (every overlapping
pair a deck apart, no connector steeper than GRADE_SOLVE), ends tied at the deck heights, banked
into the turn and level at the ends, never near the street, two connectors a level, no off-ramp in
the stack, the connectors out of segments_in() / blocks(), every column clear of the decks below
and no span over three column spacings, sound on another seed, a FULL and an LOD chunk at the
stack building the connectors with collision, and the traffic: a connector car rides its deck and
is handed to the freeway traffic at the end, a freeway car at a diverge is taken onto the connector.

**Frame cost** (`tools/geo_count.gd`, opengl3 + Xvfb, 800x600, `--spawn=2134,-1385,45,-25,120`,
noon, `STACK=0` against the stack): 2.96 M -> 2.87 M triangles, 2,727 -> 2,679 draws (the
connectors are in the chunks' existing freeway meshes; the lots under the stack became right of
way). The planner adds ~0.4 s to MacroMap.setup() (2.0 -> 2.4 s on this box), once per load.

**Stills** (shots/stack-interchange; opengl3, not the Mac's Forward+): before (the 110 lifted over
the 101's climb); the stack from the air at golden hour and straight down; driving a connector
under the 101; under the stack at street level (the single hammerhead columns); at 21:00 and 22:00
from a downtown tower.

**Not done / not verified.** Forward+ (the Mac) not seen. The stack is TALL (~26-50 m on the
default seed, 27-55 m on others): the 101's climb to the pass forces it; a flatter stack needs the
101 re-profiled (its whole 2 km climb). Connector grades reach 7.4 % (GRADE_SOLVE), steeper than a
real connector. Only the four left turns are built: no right-turn ramps, and the 110's north leg
is still the 231 m stub that ends in the air (the real Arroyo Seco Parkway does not exist here).
The diverge / merge is a short edge-to-edge touch run (24 m), so a car drifting across it is a
quick lane change; the player can drive off the main line onto a connector there but it is
abrupt. A connector car spawned when nobody can be taken pops in (only farther than 140 m from
the player). Sound: no rolling-traffic emitter of its own (Ambience's freeway emitter reads
segments_in(), so it does hear the connectors). The far city draws the connectors as unbanked
deck boxes.

## 9d?. The farmers' market: a weekly street market of white canopies, 2026-10-05 (agent branch `wt/farmers-market`)

**What.** One ordinary local street per 1.7 km map cell (by hash) is a farmers' market street:
removable bollards across both ends, painted stall corners and numbers on the asphalt, and a sign
with the market's day and hours. On its day (`FarmersMarket.DAY_ODDS`: mostly Saturday and Sunday;
the game starts on a Saturday at 9:00) the growers put up two rows of 10 x 10 ft pop-up canopies
facing an aisle down the middle, vans parked behind one row, string lights zig-zagging across the
aisle, a grower's banner on every valance, and shoppers browsing stall to stall. Before 8 and from
about 13:00 the stalls are setting up / packing (canopy folded, tables leant together, crates
stacked); after about 14:30 and on every other day the street is empty but for the bollards,
marks and sign. The default seed has 5 markets in the basin (probe below); Palm St (around
(1253, -3833)) is on Saturday.

**Files.**
- `scripts/world/farmers_market.gd` (`FarmersMarket`, static, pure): the site per cell
  (`decide()`, `_segment()`, `_eligible()`, `_street_clear()`: MIDTOWN / SUBURBS / BEACHTOWN plain
  BUILDINGS or PARK blocks either side, no site / grounds / school / hospital / plaza, not an
  avenue or a pinned road, no freeway, rail, approach zone, river, marina, replica, landmark;
  flat), the closure (`road_closed()`, CityPlan.road_open()'s hook: from `CLOSE_INSET` 2.5 m past
  each crossing road's edge, so `junction_closed()` at 2 m keeps the junction's signals and
  crosswalks and traffic's 3 m turn test sees the arm closed), `paves()`, `blocks_parking()`, the
  hours (`stall_state()`, `status()`, `busyness()`), the layout (`layout()`: stalls, vans, cached).
- `scripts/world/farmers_market_kit.gd` (`FarmersMarketKit`): every mesh in code at real size on
  ONE shader: the canopy (telescoping legs, scissor trusses, rafters, a sagging peaked roof and
  valance, sandbags), the folded canopy, goods tables per kind and variant (produce: 13 kinds in
  wooden crates heaped on a dome; flowers in buckets on a stepped stand; bread on boards and a
  rack; pantry jars, eggs, oil), the packed-up stack, the bollard, the sign post. `Geo` writes
  packed arrays with TWO index lists: the near triangles are the surface, the far ones its one LOD
  (and its shadow twin, registered as `PropFactory.shadow_proxy()`).
- `scripts/world/farmers_market_build.gd` (`FarmersMarketBuild`): the chunk's steps (one hook in
  `CityChunk._block_steps()`); FULL: bollards (one collision box each), signs, marks, every stall
  by its state (canopy and table as `EncampmentItem`s: knocked, they fly as one body and stay
  gone), vans (the road van's far twin, painted), ONE `MarketDetail` mesh (banners, sign lettering,
  marks, string lights), browse spots in the chunk's `vendor_queue` (two a stall: the crowd life's
  `_plan_queue()` stops people there), then up to 14 stallholders (`StreetVendor`) and up to 34
  shoppers by the hour. LOD: the canopies only. The far city: nothing.
- `scripts/npc/market_shopper.gd` (`MarketShopper`, a Pedestrian kept to the aisle; half carry a
  tote bag, some a coffee).
- `shaders/farmers_market.gdshader` (codes in the vertex alpha x 20; colour space via
  `color_space.gdshaderinc`; canvas backlit; bulbs lit by `lamp_factor`).
- Shared-file hooks: `CityPlan.road_open()` (one if), `CityChunk._build_roads()` (paves the closed
  road), `_park_car()` (no car on it, counted as parked so the rolls do not move),
  `ground_y()` (`market_road`: people stand on the asphalt there), `_block_steps()`, the loading
  screen (`FarmersMarketKit.warm()`, ~150 ms), one smoke-test line.

**Switches.** `FARMERS_MARKET=0` (the A/B: no market, the street open), `MARKET_DAY=1` (today is
every market's day), `MARKET_HOUR=h`; `force_hour` / `force_day` / `force_market_day` for tests.

**Tools.** `tools/farmers_market/probe.gd` (every market with an EYE, the kit's triangles and
build time; seconds), `tools/farmers_market/checks.gd` (the checks alone, a few minutes).
Checks: `tests/farmers_market_checks.gd` (27).

**Known gaps.** The street keeps no utility poles (StreetDetail hangs no line on a closed road) and
the prop ids after them on that chunk shift (persistence of broken props only). The market is
built for the hour the chunk is built at; it does not set up or pack up in front of you. A
produce table is 6-10k triangles near (the batch's far level past ~40 m); a busy market chunk adds
~300-400k triangles in view. Not seen on Forward+: canvas translucency, the produce's sheen.
Stills on `shots/farmers-market`.

