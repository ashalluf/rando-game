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
| downtown_aerial | the civic centre: city hall from the south-west, 60 m up (moved 2026-10-31: the old pose looked into a tower) | 12:30 | clear |
| beach | the waterline at z 800 | 14:00 | clear |
| hills | the front range from 260 m | 15:00 | clear |
| freeway | the 110's deck by downtown | 13:00 | clear |
| macarthur | MacArthur Park from the south, 120 m up | 11:00 | clear |
| pier_night | the pier and its wheel from the beach | 21:00 | clear |

Wave 5's new cameras are in `cameras_w5.json` (same format; run with
`REFCAMS_JSON=tools/refcams/cameras_w5.json`): `la_river` (the LA River bed at the 6th St ribbon
bridge, 15:30 clear); `rain_day` (Wilshire in midtown at 14:00 in rain, six street cars staged by its
`street_cars` key).

Wave 5 adds cameras of its own in `cameras_w5.json` (same format, one row a line; run them with
`REFCAMS_JSON=tools/refcams/cameras_w5.json`): `marine_morning` - the beach town at 08:00 under the
marine layer, 11th St toward the sand (the street damp from the mist: refcams_shot calls
`Weather.settle_wet()` once the hour and the eye are set).

The table is `cameras.json` (eye = TRUE world x, y, z, yaw, pitch; `agl` = y over the plan's
ground). **Change a camera only on purpose**: the runs before stop being comparable for it.

Wave 5's new cameras are in `cameras_w5.json` (run with `REFCAMS_JSON=tools/refcams/cameras_w5.json`).
A row with `"hero": {"walk": 0.35, "weapon": 0, "distance": ...}` (every key optional) is shot through
the player's own CameraRig instead of a free camera: he stands at the eye's x, z walking away from
the lens, the eye's yaw / pitch is the rig's look (`hero_foot`, docs/HANDOFF.md "The on-foot camera
behind the hero").

## Wave 5's cameras (`cameras_w5.json`)

Each wave-5 refcam2 session adds ONE row to `cameras_w5.json` (same format; one row a line). Run
them with `REFCAMS_JSON=tools/refcams/cameras_w5.json`. A row may carry staging keys, all optional
and ignored by the ten originals:

- `drive` (chase_cam): the player at the wheel of his own car on a street at a steady speed, a few
  placed traffic cars round him, the shot from his chase camera (DriveCam) instead of the free eye.
  Keys and their meaning in the header of `chase_stage.gd`. `CHASE_DEBUG=1` prints what is drawn
  round the car and its contacts, `CHASE_AB=a,b,...` (names, `car:*`, `under:*`, `box:*`, `fx:*`,
  `2d:*`, `dbg:unshaded`...) renders the frame again with each hidden, `CHASE_BISECT=1` halves the
  drawables to find what draws a given pixel difference.

## Wave 6's cameras (`cameras_w6.json`)

- `person_closeup` - one pedestrian 1.6 m from the lens on a midtown pavement, 13:00 clear.
  `"stage": "person"` with a `person` key (model, look, dist, turn, carry; all optional) runs
  `person_stage.gd`: a seed found for that rig and look with no hat, placed and held standing, the
  walkers in the line of sight hidden. Env `PERSON_MODEL`, `PERSON_LOOK`, `PERSON_DIST`,
  `PERSON_TURN`, `PERSON_CARRY`, `PERSON_SEED` for framing work.

## Wave 6's cameras (`cameras_w6.json`)

Run them with `REFCAMS_JSON=tools/refcams/cameras_w6.json`. `car_closeup` (rc3-car-closeup) carries
`park_car` (`tools/refcams/park_stage.gd`): a car of a body type (`random_car()` walked from `seed`
until the type matches, no livery) parked on the kerb of the road nearest `at`, `along` the TRUE
world coordinate, `side` which kerb; the parked cars round it freed; the eye and the point aimed at
given in the car's own frame (x right, -z ahead of the nose), so the frame holds whatever the load
rolled. `tools/refcams/kerb_probe.gd -- --spawn=x,z` lists kerbs round a point.

## Wave 6's cameras (`cameras_w6.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w6.json`. `freeway_night`: the 110 northbound at 22:00
clear, a driver's eye (1.2 m over the deck) in lane 2 toward the downtown skyline. Its optional
`freeway_cars` key stages freeway traffic three frames before the shot: `{"route": r, "clear": m,
"cars": [[ahead, lane, dir, speed, kind], ...]}` - cars `ahead` metres along route `r` from the eye
in the direction it looks, lane 0 by the median, dir -1 toward the route's start (the 110 runs
north to south), `kind` a Vehicle.BodyType name or "", and every other traffic car within `clear`
metres of the eye hidden for the shot (the load's own traffic put a box truck on the lens). The log
prints each staged car's distance at the shot.
Run with `REFCAMS_JSON=tools/refcams/cameras_w6.json`. `airport_night` - the apron at 21:30 clear from
the first stand west of the concourse, a jet staged on final to 27L (`air` final: the flare over the
threshold at the shot). A row that stages an aircraft prints `REFCAM <name> air at x,y,z` (TRUE world,
at the shot): tune `air_dist` / `air_side` from it.

## Wave 6's cameras (`cameras_w6.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w6.json`. `rooftop_golden`: the black twins' north
helipad (deck 215.55 m), 17:45 clear, looking SSW over the skyline to the basin and the sea.

## Wave 8's cameras (`cameras_w8.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w8.json`. `arena_night` (rc5-arena-night): STARLIGHT
PLAZA at 21:00 clear, eye level in the crowd at the plaza's south-east looking north-west at the
screen wall, the theatre's lobby and HOTEL ALTAIR's crown. Its optional `arena_event` key (1 / 0)
makes the night an event night or a quiet one (ArenaNight, as ARENA_EVENT; set before the city
loads). `tools/rc5_arena_night/site_probe.gd` prints the district's site rects in world XZ.

`wingsuit_golden` (rc5-wingsuit-golden): the
hero gliding in his wingsuit ~120 m over Bunker Hill toward the skyline at 18:00 clear, shot from his
OWN chase camera 6 m behind. Its `wingsuit` key (`tools/refcams/wingsuit_stage.gd`: at, heading,
speed, lead, input, dist, look, fov) launches him `lead` seconds back along the trim glide so he
passes `at` at the shot; the log prints where he is, his speed and whether the vapour trails.

## Wave 7's cameras (`cameras_w7.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w7.json`. `freight_yard`: the Arroyo Pacific yard at
16:30 clear, eye level where the ladder meets the storage tracks looking north, a train pulling out
on the east main. Its optional `freight_into` key holds the freight line's clock that many seconds
into the yard stand of the trip nearest the yard (`FreightRail.clock_at_yard()`; past 150 s the train
is pulling out south). `tools/rc4_freight_yard/probe.gd` prints the yard's tracks, cuts and masts and
the train's ends over the pull-out, `chunk_probe.gd` what each yard chunk lays.
Run with `REFCAMS_JSON=tools/refcams/cameras_w8.json`. `rush_hour` (rc5-rush-hour): the 105 at 17:40
clear from the caged footbridge east of the 110 (`fb_f_1_213`), the lens just outside the cage looking
west down the carriageways into the sun; `shot_frames` 90 lets RushHour's jam build.
`rail_aerial` (rc5-rail-aerial): the Coral Line's structure where it swings off Flower over the 110,
from River Blvd below at 20:00 clear, looking west. Its optional `rail_s` key ("<s>:<dir>[:<seconds
before>]", LightRailSystem's RAIL_S) sets and holds the light rail's clock so a train's nose is at
s along the line (dir 1 runs toward the downtown terminus); "2470:1" puts a train on the curve.
`tools/rc5_rail_aerial/probe.gd` prints the flyovers, the freeways under them and the poles there.

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

## Wave 6's cameras (`cameras_w6.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w6.json`. `pier_day` - Gullwing Park on Rando Pier at
15:00 clear, from the promenade in the crowd toward the wheel and the sea end (PierDay,
docs/HANDOFF.md "The pier by day from the deck").

Wave 6's cameras are in `cameras_w6.json` (run with `REFCAMS_JSON=tools/refcams/cameras_w6.json`):
`golf_morning` - the golf course at 08:30 from behind the 9th tee toward the clubhouse and the front
range. Its optional `golf_group` key ("hole:stage[:tee[:count]]") stages a group of golfers there
(GolfLife.force_group via the GOLF_GROUP environment variable, set before the city loads).

## Wave 7's cameras (`cameras_w7.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w7.json` (the file is new in wave 7, the cameras_w6.json
format). `canals_day`: Marisol Canals at 11:00 clear, on Heron Canal's southern footbridge looking
north down the canal (no staging). `film_lot` (rc4-film-lot): inside the SUNSPIRE PICTURES studio
lot at 14:00 clear, eye level in the middle of the studio street between stages 5-7 and the basecamp,
looking north to the water tower. No staging key. `port_night` (rc4-port-night): the container
terminal at 22:00 clear from the quay's apron. Its optional `port_t` key holds PortLife's clock
(seconds) for the shot, so the cranes and tractors are where the row was framed (`_port_clock()` in
refcams_shot.gd; rows without it leave the clock alone). `OCCLUSION=0` turns occlusion culling off
for a run. `stack_aerial` (rc4-stack-aerial): the four-level stack from 150 m over the ground
north-west of it, 17:30 clear, toward downtown; `shot_frames` 90 lets the connectors' traffic fill
before the shot. `metro_station` (rc4-metro-station): on the Coral Line's
underground island at 7th St toward the bank's escalators and the glass lift, a train dwelling on
the left with its doors open. Its optional `rail_at` key (`"<station>[:<dir>[:<seconds from
mid-dwell>]]"`, LightRailSystem's RAIL_AT per camera) sets the light rail's clock when the row is
staged and holds it until the shot; while it is held, every placement of the parked player calls
`MetroStation.admit()` (an eye under the city's ground box is otherwise thrown out to the street
each step, and the tunnel train is hidden with it).


## Wave 8's cameras (`cameras_w8.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w8.json`. `gas_station_night` (rc5-gas-station-night):
the HALCYON station at (-64.6, 519.2) from the street at 23:30 clear. Its `pump_car` key (1) sets
PUMP_CAR=1 before the city loads: every gas station gets GasNight's car at a pump and its driver,
whatever its hash. `NIGHT_AB=1` (any camera) saves the frame again with the lamps' omnis, the
pools / spills / glows, the moon and the ambient each taken away (`<name>_nab_<what>.png`, plus
`nothing`), and prints the environment's night numbers, the lamps within 60 m and the pool batches
within 40 m: what lights a night frame, measured.
## Wave 7's cameras (`cameras_w7.json`)

`lowrider_meet` (rc4-lowrider-meet): the Saturday lowrider meet on Z#4 (x 810-900, seed 1337) at
19:30 clear, eye level in the road beside the row. Its optional `lowrider_meet` key
(`{"on": 1, "pose": "i:routine:seconds[:side],..."}`) holds every meet on (LOWRIDER_MEET=1) and
freezes row cars mid-routine (LOWRIDER_POSE), set before the city loads (`_lowrider_meet()` in
refcams_shot.gd). `tools/rc4_lowrider_meet_probe.gd` prints the row (stances, lamps, routines)
and the crowd headless.
## Wave 8's cameras (`cameras_w8.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w8.json`. `hill_home_dusk`: estate 392's pool deck on
the front range (a cantilever house, 159 m up) at 19:15 clear, looking south over the basin past
the infinity pool, the lit glass wall on the right. The eye's y is absolute (no `agl`): the pad's
deck. `tools/rc5_hill_home/probe.tscn` (EST=n) prints an estate's wings, deck and pool in world
space for framing another one. On this box an opengl3 city run can hang in the occlusion raycast
(0 % CPU after the far city loads): `OCCLUSION=0` on refcams.py's environment.

## Wave 8's cameras (`cameras_w8.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w8.json`. `skate_park` (rc5-skate-park): THE PIT at
16:30 clear, eye level on the high deck west of the pool looking north-east over it to the boardwalk.
Its optional `skate_t` key holds SkateParkLife's clock (seconds, the riders held: `_skate_clock()` in
refcams_shot.gd, as SKATE_T= / SKATE_HOLD=1), so the first pool rider is at the top of his
frontside air over the far coping. `tools/rc5_skate_park/air_probe.gd` lists every rider's air times.

`storm_downtown`: Flower St south of 8th
toward the towers, 20:30 storm, five staged street cars. Its optional `storm_flash` key
(`{"dist": m, "az": degrees (0 = +x, -90 = north), "hold": level}`) forces a strike through
`Weather.force_strike()` as the staging starts and holds its flash and bolt (StormDrama) until the
shot is saved.

## Wave 8's cameras (`cameras_w8.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w8.json`. `speedboat_golden` (rc5-speedboat): the
SALTRUNNER at speed 300 m off the beach town at 17:45 clear, a chase eye into the sun path. Its
`boat` key (`tools/refcams/boat_stage.gd`, the same interface as chase_stage.gd) re-centres the world
on `at`, puts the player in a fresh boat heading `heading` (the --spawn yaw), holds the throttle
`ticks` physics ticks, and lays a free eye `chase` = [back, side, up, aim ahead] metres off the hull
every frame up to the shot; optional `kind`, `look`, `boost`, `steer`. The row's own eye is unused.
## Wave 8's cameras (`cameras_w8.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w8.json`. `farmers_market` (rc5-farmers-market): Palm
St's market aisle on a Saturday at 10:00 clear. Its optional `market_day` key sets `MARKET_DAY` (and
`MARKET_HOUR` = the row's hour) before the city loads, so the stalls stand up whatever the day.
## Wave 8's cameras (`cameras_w8.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w8.json`. `police_pursuit` (rc5-police-pursuit): the
player's own car on Wilshire at 22:00 clear through his chase camera (a `drive` row, chase_stage.gd),
with the drive key's optional `pursuit` (`pursuit_stage.gd`): `stars`, `cruisers` ([metres behind,
metres to his right] each, held at his speed, their own driving off), `heli` ([dist, side, height]:
AirTraffic.stage("police") from his camera, its searchlight on him) and `look` ([yaw, pitch] degrees
the chase camera is turned off its chase view and held). The police dispatch nothing of their own
while it runs. `POLICE_PURSUIT=0` stages none of it; `PURSUIT_AB=1` saves the frame again with each
piece switched off (pab_NN_base.png / pab_NN_<piece>.png pairs): the helicopter's spot, pool and
shaft, the cruisers' wash pool / wall / glare, by their inputs (their owners re-show hidden nodes
every frame).
## Wave 8's cameras (`cameras_w8.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w8.json`. `suburb_night` (rc5-suburb-night): the
suburb_morning street (block 21,32 on seed 1337) from the same pavement eye at 21:30 clear, so the
day and the night of one street compare 1:1. Its optional `dog_walker` key (`tools/refcams/dog_stage.gd`:
`dist`, `side`, `at`, `yaw`, `seed`, `away`) stands one person walking a dog in the frame, held on its
spot and walking; the log prints a `REFCAM dog walker` line.

## Wave 8's cameras (`cameras_w8.json`)

Run with `REFCAMS_JSON=tools/refcams/cameras_w8.json`. `walk_of_fame_night` (rc5-walk-of-fame-night):
Canyon Blvd's south pavement at THE GRAND CELESTE's corner, the lens over the band of stars, 22:00
clear, looking west-south-west at the marquee and the premiere in front of it. No staging key: the
premiere, the characters and the tourists come from the build hour (WalkOfFameNight). On this box
the run needs `OCCLUSION=0` (the occlusion raycast hang, above). For framing in a minute:
`tools/glshot/station_night_shot.tscn` with `WOF_HOUR=22` (that scene has no DayNight at its root,
so the walk would otherwise build at the 13:30 fallback).
`sea_life` (rc5-sea-life): the straight pier's round head at 08:00 clear looking ESE down the coast.
Its optional `sea` key is SeaLife.stage_for_shot()'s spec ("dolphin@x,z[,lead];pelican@x,z", TRUE
world), staged three frames before the shot with the sea clock held and cleared after it;
`SEA_DEBUG=1` prints the surfers and swimmers BeachActivity has round the lens.
`yard_sale` (rc5-yard-sale): a suburb Saturday 09:30 from the far pavement. Its `yard_sale` key (1)
builds every yard sale for a Saturday at the row's hour (YARD_SALE_DAY / YARD_SALE_HOUR), its
`clear_cars` (metres) hides the vehicles that near the lens.

`marina_night` (rc5-marina-night): the marina at 21:00 clear from the north end of the east
headwalk, west down the lane along the north quay (no staging keys). `MARINA_NIGHT=0` is its A/B.
`freight_trench` (rc5-freight-trench): the Alameda trench at 12:00 clear from the south edge of the
Spring Blvd bridge looking south, a northbound stack train coming on under the bridges. Its optional
`freight_s` key ("<s>[:<dir>[:<seconds before>]]", FREIGHT_S) holds the freight line's clock with a
train's leading end at s (dir 0 north), `freight_kind` (0 stack, 1 manifest, 2 autorack) picks the
consist (FREIGHT_KIND). `tools/freight/probe.gd` prints the junctions' s.

## Wave 8's cameras (`cameras_w8.json`)

`stunt_jump` (rc5-stunt-jump): `"stage": "stunt"` with a `stunt` key runs `stunt_stage.gd`: a car
held mid-flight `t` s after a StuntRamps site's lip at `speed` m/s (`site` an id from
`tools/stunt_ramps/probe.tscn`, `body`, `paint`, `pitch`, `roll`), the jump's look given that
age by StuntJumpFX.stage() (dust, clods, hanging wheels), the free eye and its aim point in the
RAMP's frame (`eye`, `look`: +Z the way it is ridden, origin at its foot). Env `STUNT_EYE=x,y,z`,
`STUNT_LOOK=x,y,z`, `STUNT_T`, `STUNT_SPEED` override the row for framing.

## Wave 8: `bus_stop_rain`

A Wilshire bus stop at 18:00 in rain. `"stage": "bus"` with a `bus` key (`at` [x, z] TRUE world: the
stop nearest it; `dir`; `pull` metres short of the stop; `doors`; `queue` riders; `seed`) runs
`bus_stage.gd`: the bus at its stop, doors open, the stop's StreetErrands queue filled.

`fire_station_night` (rc5-fire-station-night): STATION 79 on 7th St downtown at 21:00 clear, from the
far pavement as an engine goes out on a call. `"stage": "fire_station"` runs
`tools/refcams/fire_station_stage.gd`: the station nearest the eye, a call opened `call_ahead` m down
its street, the engine sent through Emergency.send() (out of its bay, StationExit), the `cars` placed
on the station's road, then the engine and the street traffic STEPPED `t` seconds at 60 Hz by hand
(the same moment every run), the doors held up, the watch at the kerb. `FS_T=` overrides `t`
(`FS_T=0.6` on main is the before: the engine on the street). `tools/rc5_fire_station/probe.gd`
lists stations with their bays and an eye across the street.
