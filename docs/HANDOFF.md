# Handoff: Rando Game (written 2026-09-19; section 0000 is the newest state and the handoff to the next account, 2026-09-28)

This is the narrative handoff for whoever picks the project up next, from any Claude Code account
or as a person. `CLAUDE.md` is the rulebook and `docs/GAME_PLAN.md` is the roadmap plus the
decisions log; both stay the source of truth. This file is the story: where things stand, how
the day-to-day work goes, what is fragile, what to do next. Read all three before touching code.

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

## 9ba. Crowd life: people who do things, 2026-10-04 (agent branch `wt/crowd-life`; GAME_PLAN G5)

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
