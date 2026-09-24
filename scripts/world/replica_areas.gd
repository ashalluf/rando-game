class_name ReplicaAreas
extends RefCounted
## REPLICA AREAS (owner, 2026-09-24: "we are basically picking certain 1:1 replica areas and then
## filling them in between with whatever").
##
## A replica area is a real place rebuilt at TRUE scale from real references - its street layout,
## lane and kerb widths, parking, lamp rhythm, building sizes and setbacks, bluff height, what you
## see from the road - authored as a data table, never as hand-placed nodes. Everything between
## replica areas stays the seeded city. The distances BETWEEN areas may be compressed (the basin
## is a miniature); the areas themselves are not.
##
## How one is consumed:
##   * MacroMap owns one ReplicaAreas per area (`macro.replica`), built in setup() before the hill
##     roads, and asks it for the coast (`waterline_x`), the beach width, the terrace the town
##     stands on (`terrace_at`, folded into relief so every chunk's _gy() already follows it) and
##     whether the seeded relief should be calmed near the road.
##   * CityChunk asks `chunk_role(rect)`: a block that touches the corridor skips the seeded block
##     content and builds the replica's own (ReplicaBuilder) - road, bluff, beach stairs, frontage
##     houses, and seeded backfill houses on the rest of the block.
##   * CityPlan.lots() returns `block_lots()` for those blocks, so the LOD tier, the far skyline and
##     the air traffic's obstacle map all see the same houses.
##   * HillRoads carves the part of the route that climbs into the hills (`hill_route()`).
##   * ReplicaTraffic drives `lane_point()`; the grid traffic keeps out of `blocks_grid()`.
##
## Business names stay original; public street names ("Esplanade") are used as they are.
##
## Adding the next area: another const table shaped like ESPLANADE, appended to AREAS, and the
## same consumers pick it up. Only ESPLANADE exists today.

## Metres between path samples. Every lateral measurement in this file is taken at a sample, so
## this is also the resolution of the terrace, the corridor and the lane paths.
const STEP := 4.0
## Cell size of the sample index (metres).
const CELL := 48.0
## Metres of ground past the path ends over which the terrace fades to nothing.
const END_FADE := 150.0
## The flat terrace extends this far inland of the road before it starts easing back down to the
## seeded city's level, and is gone by INLAND_FADE_END. Real Redondo rises gently inland; this is
## a two-percent slope nobody can see.
const INLAND_FLAT := 260.0
const INLAND_FADE_END := 900.0
## Metres inland of the road the seeded rolling relief is kept off (full, then fading back in by
## CALM_END), so the replica's streets are the grade the real ones are.
const CALM_FLAT := 170.0
const CALM_END := 360.0
## Road surface above the ground a chunk lays (CityChunk.ROAD_TOP). The terrace is the GROUND, the
## profile is the road top, so the two differ by this.
const ROAD_TOP := 0.1
## The pavement top above the ground (CityChunk.SIDEWALK_TOP).
const WALK_TOP := 0.25

# ---------------------------------------------------------------------------------------------
# THE ESPLANADE, Redondo Beach, south into Palos Verdes.
#
# References: the owner's three Street View captures - 1718 Esplanade looking south (May 2025,
# twice: kerb lane and centre), 1799 Esplanade at the south curve (January 2021) - plus the real
# street as it is on the map: the Esplanade runs 2.0 km from Knob Hill (just south of the pier)
# to Avenue I on a bearing of about 173 degrees, along the top of a 14-16 m bluff; at its south
# end it drops, splits round a planted median, curves left past the Avenue I beach car park and
# meets Avenue I and Paseo de la Playa at a roundabout; Paseo de la Playa runs south along the
# Torrance bluff to Malaga Cove, where Palos Verdes Blvd climbs south-west into the hills and
# becomes Palos Verdes Drive West along the north face of the peninsula.
#
# What the photos fix, and the numbers below reproduce:
#   * four travel lanes, 3.5 m, two each way, divided by a 3.2 m painted median between two
#     double-yellow lines; parallel parking on both kerbs with T stall marks and a solid white
#     edge line; ~22.4 m kerb to kerb.
#   * the ocean side: a 3.5 m concrete walkway along the kerb, a low concrete seat wall, a strip
#     of coastal scrub, a fence at the bluff edge, the bluff face (ice plant and sage scrub), a
#     wide sand beach below and the surf.
#   * the inland side: a 3.5 m pavement and a continuous frontage of 2-3 storey stucco houses and
#     apartments on 10-16 m lots, low garden walls, garages off the street, balconies with glass
#     rails, tile and flat roofs; tall slender Mexican fan palms in the front yards.
#   * grey double-arm "cobra" lamps on the ocean-side kerb about every 45 m.
#   * at the south end: yellow roundabout warning signs and chevrons, the curve, the car park on
#     the beach side with nose-in stalls along a low wall, a long four-storey condominium block
#     with green-tinted glass balconies beyond, and the Palos Verdes ridge filling the view,
#     falling right to the headland point in the sea.
#
# Compressed: Paseo de la Playa (1.6 km on the ground, 0.8 km here) - it is the link between
# the Esplanade and the hills, and the Palos Verdes north face is placed so the view from the
# Esplanade keeps the real angles. Everything else is 1:1.
# ---------------------------------------------------------------------------------------------

## Cross sections. Lateral offsets are measured from the centre line, POSITIVE TO THE LEFT of the
## direction of travel (east, heading south). Numeric fields blend over a leg's `blend` metres.
## median: half-width of the median; median_raised: a kerbed planted island instead of paint.
## park_w / park_e: parking lane width on each side (0 = none). walk_w / walk_e: pavement widths.
## verge: planted strip between the ocean-side walkway and the bluff edge (fence at its far side).
## west_lots / east_lots: depth of the frontage lots on that side (0 = none).
## bluff: horizontal run of the bluff face; beach: sand from the bluff toe to the waterline.
## alley: service lane behind the east lots before the seeded backfill starts.
## coast: false for the hill sections, where the headland draws the shore instead.
const SECTIONS := {
	"esplanade": {
		"median": 1.6, "median_raised": 0.0, "lanes": 2, "lane_w": 3.5, "park_w": 2.6, "park_e": 2.6,
		"walk_w": 3.5, "walk_e": 3.5, "verge": 5.0, "west_lots": 0.0, "east_lots": 30.0,
		"bluff": 24.0, "beach": 80.0, "alley": 5.0, "coast": 1.0, "lamps": 1.0,
	},
	# The last stretch before the curve: the painted median opens into a planted island and the
	# southbound kerb loses its parking to the car park entrance.
	"esplanade_south": {
		"median": 7.0, "median_raised": 1.0, "lanes": 2, "lane_w": 3.5, "park_w": 0.0, "park_e": 2.6,
		"walk_w": 2.5, "walk_e": 3.5, "verge": 4.0, "west_lots": 0.0, "east_lots": 30.0,
		"bluff": 16.0, "beach": 84.0, "alley": 5.0, "coast": 1.0, "lamps": 1.0,
	},
	# Into the roundabout: one lane each way either side of a splitter island.
	"approach": {
		"median": 1.4, "median_raised": 1.0, "lanes": 1, "lane_w": 4.2, "park_w": 0.0, "park_e": 0.0,
		"walk_w": 2.5, "walk_e": 2.5, "verge": 4.0, "west_lots": 0.0, "east_lots": 0.0,
		"bluff": 12.0, "beach": 88.0, "alley": 0.0, "coast": 1.0, "lamps": 1.0,
	},
	# Paseo de la Playa: two lanes and parking, homes on both sides, the bluff behind the west ones.
	"paseo": {
		"median": 0.15, "median_raised": 0.0, "lanes": 1, "lane_w": 3.6, "park_w": 2.4, "park_e": 2.4,
		"walk_w": 2.0, "walk_e": 2.4, "verge": 0.0, "west_lots": 32.0, "east_lots": 30.0,
		"bluff": 22.0, "beach": 72.0, "alley": 5.0, "coast": 1.0, "lamps": 1.0,
	},
	# Palos Verdes Blvd and Drive West: a two-lane hill road with shoulders, cut into the slope.
	"pv_blvd": {
		"median": 0.15, "median_raised": 0.0, "lanes": 1, "lane_w": 3.6, "park_w": 1.2, "park_e": 1.2,
		"walk_w": 0.0, "walk_e": 1.6, "verge": 0.0, "west_lots": 0.0, "east_lots": 0.0,
		"bluff": 0.0, "beach": 0.0, "alley": 0.0, "coast": 0.0, "lamps": 0.0,
	},
	"pv_drive": {
		"median": 0.15, "median_raised": 0.0, "lanes": 1, "lane_w": 3.5, "park_w": 1.0, "park_e": 1.0,
		"walk_w": 0.0, "walk_e": 0.0, "verge": 0.0, "west_lots": 0.0, "east_lots": 0.0,
		"bluff": 0.0, "beach": 0.0, "alley": 0.0, "coast": 0.0, "lamps": 0.0,
	},
	# Side streets the replica owns (Knob Hill, Avenue I).
	"avenue": {
		"median": 0.15, "median_raised": 0.0, "lanes": 1, "lane_w": 3.6, "park_w": 2.4, "park_e": 2.4,
		"walk_w": 2.4, "walk_e": 2.4, "verge": 0.0, "west_lots": 0.0, "east_lots": 0.0,
		"bluff": 0.0, "beach": 0.0, "alley": 0.0, "coast": 0.0, "lamps": 0.0,
	},
}

const ESPLANADE := {
	"id": "esplanade",
	"name": "Redondo Beach Esplanade to Palos Verdes",
	"references": [
		"Street View, 1718 Esplanade, looking south (May 2025), kerb lane and centre lane",
		"Street View, 1799 Esplanade, the south curve (January 2021)",
	],
	# The Esplanade's north end (Knob Hill), centre line, true world XZ, and its bearing.
	"start": Vector2(-678.0, 1540.0),
	"heading_deg": 173.0,
	# Legs, in order. straight: length. arc: turn_deg (+ right, - left) at radius. roundabout: the
	# path so far ends at the ring's centre and leaves it on exit_heading_deg; its stubs are the
	# other legs of the junction. `blend` is how far into a leg its section blends in from the last.
	"legs": [
		{"name": "Esplanade", "kind": "straight", "length": 1880.0, "section": "esplanade", "blend": 0.0},
		{"name": "Esplanade", "kind": "straight", "length": 120.0, "section": "esplanade_south", "blend": 110.0},
		{"name": "Esplanade", "kind": "arc", "turn_deg": -26.0, "radius": 140.0, "section": "esplanade_south", "blend": 0.0},
		{"name": "Esplanade", "kind": "straight", "length": 48.0, "section": "approach", "blend": 40.0},
		{"name": "Avenue I", "kind": "roundabout", "r_out": 19.0, "r_island": 10.5, "exit_heading_deg": 190.0,
			"stubs": [{"name": "Avenue I", "heading_deg": 84.0, "length": 150.0, "section": "avenue"}]},
		{"name": "Paseo de la Playa", "kind": "straight", "length": 40.0, "section": "approach", "blend": 0.0},
		{"name": "Paseo de la Playa", "kind": "straight", "length": 330.0, "section": "paseo", "blend": 40.0},
		{"name": "Paseo de la Playa", "kind": "arc", "turn_deg": 6.0, "radius": 700.0, "section": "paseo", "blend": 0.0},
		{"name": "Paseo de la Playa", "kind": "straight", "length": 360.0, "section": "paseo", "blend": 0.0},
		# Up the headland's north face: round to the east above Malaga Cove, then climbing
		# obliquely across the face the way the real road climbs out of the cove.
		{"name": "Palos Verdes Blvd", "kind": "arc", "turn_deg": -58.0, "radius": 150.0, "section": "pv_blvd", "blend": 60.0},
		{"name": "Palos Verdes Dr N", "kind": "climb", "length": 1500.0, "bearing_deg": 112.0, "grade": 0.06, "turn_deg": 2.0, "pull": 0.45, "section": "pv_blvd", "blend": 0.0},
	],
	# The leg the terrace (the town on its bluff) ends with; after it the route is a hill road cut
	# into the headland's terrain.
	"city_legs": 9,
	# Road-top elevation (m above sea level) along the route, for the city legs: control points,
	# joined linearly, then smoothed and held to MAX_GRADE. Real Esplanade: up from the pier plaza
	# onto a 14-16 m bluff, level for most of its length, down to 6.5 m at the Avenue I curve (the
	# car park beside it is at 6), the Paseo up onto the Torrance bluff and down again toward
	# Malaga Cove, where the hill road picks up the headland's own ground.
	"profile": [[0.0, 4.0], [220.0, 14.0], [520.0, 15.5], [1000.0, 16.2], [1500.0, 15.4],
		[1780.0, 13.6], [1930.0, 10.0], [2030.0, 6.6], [2230.0, 6.4], [2330.0, 9.0],
		[2600.0, 13.0], [2780.0, 14.0], [2915.0, 11.5], [3030.0, 12.0]],
	# Grade limit for the whole route, and for the hill part how far the road may sit above or
	# below the natural slope it follows.
	"max_grade": 0.085,
	"hill_grade": 0.10,
	"hill_cut": 3.0,
	# Side streets off the route that the replica builds: at path distance `s` on `side`, e.g.
	# {"name": ..., "s": 6.0, "side": 1.0, "heading_deg": 83.0, "length": 130.0, "section": "avenue"}.
	# None here: Knob Hill, where the Esplanade starts, is left to the seeded grid's east-west
	# streets (a replica street laid 7 degrees off the grid ran alongside one of them), and the
	# route's north end is a kerb and a pavement they run past.
	"streets": [],
	# Where things stand along the route, by path distance.
	"lamp_spacing": 45.0,
	"stairs": [340.0, 720.0, 1090.0, 1460.0, 1790.0],
	# Junctions with the seeded grid that get an all-way stop and a crosswalk (every other one).
	"stop_every": 2,
	# The Avenue I car park: in the frame of the tangent at `s`, `along` metres ahead and `lateral`
	# metres to the left (negative = the ocean side), one row of nose-in stalls along the sea wall.
	# Its surface is level at `elev` (m above the sea), ramping down to it from the road over its
	# first `ramp` metres; a sea wall drops from its seaward edge to the sand.
	"car_park": {"s": 1998.0, "along": [18.0, 205.0], "lateral": [-30.0, -12.0], "stall_w": 2.7, "stall_d": 5.6, "elev": 6.0, "ramp": 45.0},
	# The long condominium block (4 storeys, green-tinted glass balconies), east side of the Paseo.
	"condo": {"s": [2215.0, 2375.0], "side": 1.0, "setback": 9.0, "depth": 21.0, "storeys": 4, "storey_h": 3.2},
	# Frontage lot widths along the street (metres) and the gap left for a grid street's mouth.
	"lot_width": [10.0, 16.0],
	"street_gap": 3.0,
	# Palms in the east front yards: mean spacing and its jitter, metres.
	"palm_spacing": 17.0,
}

const AREAS := [ESPLANADE]

# --- Runtime -----------------------------------------------------------------------------------

var macro: MacroMap
var data: Dictionary = {}
var seed: int = 0
## Centre line samples, true world XZ, STEP apart, and per sample: unit heading, path distance,
## road-top elevation, leg index and the resolved cross section.
var pts := PackedVector2Array()
var dirs := PackedVector2Array()
var run := PackedFloat32Array()
var top := PackedFloat32Array()
var leg := PackedInt32Array()
var sec: Array[Dictionary] = []
var length: float = 0.0
## Path distance where the terrace ends and the hill road begins.
var s_city_end: float = 0.0
## Roundabouts: {"center", "s", "index", "r_out", "r_island", "in_dir", "out_dir", "top", "stubs"}
var roundabouts: Array[Dictionary] = []
## Side streets as their own little paths: {"name", "pts", "dirs", "top", "section", "from_s"}
var streets: Array[Dictionary] = []
var _cells := {}
## The waterline as x per z, and the beach width, sampled every WL_DZ metres from _wl_z0.
const WL_DZ := 5.0
var _wl_z0: float = 0.0
var _wl := PackedFloat32Array()
var _bw := PackedFloat32Array()
## x of the centre line per z, and s per z, on the same table, for the inland terrace.
var _cx := PackedFloat32Array()
var _cs := PackedFloat32Array()
var _lots: Array[Dictionary] = []
var _block_lot_cache := {}
var _bounds := Rect2()


func build(macro_map: MacroMap, seed_value: int, area: Dictionary = ESPLANADE) -> void:
	macro = macro_map
	seed = seed_value
	data = area
	# The city legs first: they are pure geometry, and their waterline is the coast the rest of
	# the map (the headland's shore included) is measured against. The hill legs climb the
	# headland's terrain, so they wait for fit_hill_profile(), once MacroMap has this replica.
	_begin_path()
	_sample_legs(0, int(data.get("city_legs", (data.legs as Array).size())))
	s_city_end = length
	_resolve_sections()
	_city_profile()
	_tables()
	_index()


## True when `pos` is within `reach` metres of the replica's centre line at all (a cheap test).
func near(pos: Vector2, reach: float) -> bool:
	return nearest(pos, reach).size() > 0


# --- The path ----------------------------------------------------------------------------------

static func dir_of(bearing_deg: float) -> Vector2:
	var b := deg_to_rad(bearing_deg)
	return Vector2(sin(b), -cos(b))


## Left of a heading in world XZ (east when heading south).
static func left_of(d: Vector2) -> Vector2:
	return Vector2(d.y, -d.x)


## Sampling state, carried from the city legs to the hill legs.
var _sp: Vector2
var _sbear: float
var _ss: float


func _begin_path() -> void:
	pts.clear()
	dirs.clear()
	run.clear()
	leg.clear()
	roundabouts.clear()
	streets.clear()
	_sp = data.start
	_sbear = data.heading_deg
	_ss = 0.0
	_push(_sp, dir_of(_sbear), _ss, 0)
	for st: Dictionary in data.get("streets", []):
		streets.append({"def": st})


func _sample_legs(from_leg: int, to_leg: int) -> void:
	var legs: Array = data.legs
	var p := _sp
	var bearing := _sbear
	var s := _ss
	for li in range(from_leg, mini(to_leg, legs.size())):
		var l: Dictionary = legs[li]
		match str(l.kind):
			"straight":
				var n := maxi(1, ceili(float(l.length) / STEP))
				var d := dir_of(bearing)
				for k in n:
					p += d * (float(l.length) / n)
					s += float(l.length) / n
					_push(p, d, s, li)
			"arc":
				var turn: float = l.turn_deg
				var r: float = l.radius
				var arc_len := absf(deg_to_rad(turn)) * r
				var n := maxi(2, ceili(arc_len / STEP))
				for k in n:
					# Midpoint rule: advance along the chord of each small step at its mean bearing.
					var b0 := bearing + turn * float(k) / n
					var b1 := bearing + turn * float(k + 1) / n
					var chord := 2.0 * r * sin(absf(deg_to_rad(b1 - b0)) * 0.5)
					p += dir_of((b0 + b1) * 0.5) * chord
					s += arc_len / n
					_push(p, dir_of(b1), s, li)
				bearing += turn
			"climb":
				# A hill road laid the way one is surveyed: each step takes whichever heading within
				# `turn_deg` of the last one comes closest to climbing at `grade`, pulled toward the
				# leg's bearing. So it traverses a face too steep to take straight on, and heads for
				# its bearing again where the slope eases - which is what makes it read as a real
				# road on a hillside rather than a line ruled across one.
				var n := maxi(1, ceili(float(l.length) / STEP))
				var want: float = l.bearing_deg
				var grade: float = l.grade
				var turn: float = l.get("turn_deg", 2.5)
				var pull: float = l.get("pull", 0.3)
				var h_prev := _terrain(p)
				for k in n:
					var best_b := bearing
					var best := INF
					for c in 9:
						var b := bearing + turn * (float(c) / 4.0 - 1.0)
						var g := (_terrain(p + dir_of(b) * STEP) - h_prev) / STEP
						var score := absf(g - grade) * 12.0 + absf(angle_difference(deg_to_rad(b), deg_to_rad(want))) * pull
						if score < best:
							best = score
							best_b = b
					bearing = best_b
					p += dir_of(bearing) * STEP
					s += STEP
					h_prev = _terrain(p)
					_push(p, dir_of(bearing), s, li)
			"roundabout":
				var ra := {
					"center": p, "s": s, "index": pts.size() - 1, "name": str(l.name),
					"r_out": float(l.r_out), "r_island": float(l.r_island),
					"in_dir": dir_of(bearing), "out_dir": dir_of(float(l.exit_heading_deg)),
					"stubs": [],
				}
				bearing = float(l.exit_heading_deg)
				for st: Dictionary in l.get("stubs", []):
					(ra.stubs as Array).append(st)
					streets.append({"def": st, "roundabout": ra})
				roundabouts.append(ra)
	_sp = p
	_sbear = bearing
	_ss = s
	length = s


## The headland's ground under a climbing road, averaged across its width so one noisy sample
## cannot swing the heading.
func _terrain(p: Vector2) -> float:
	if macro == null:
		return 0.0
	# height_at() rather than the bare mountain: the terrace fades out over the headland's lower
	# slopes, and a road profiled on the mountain alone sat in a trench nine metres under it. The
	# hill roads that would carve it do not exist yet when this runs.
	return (macro.height_at(p) * 2.0 + macro.height_at(p + Vector2(5.0, 0.0)) + macro.height_at(p - Vector2(5.0, 0.0))
		+ macro.height_at(p + Vector2(0.0, 5.0)) + macro.height_at(p - Vector2(0.0, 5.0))) / 6.0


func _push(p: Vector2, d: Vector2, s: float, li: int) -> void:
	pts.append(p)
	dirs.append(d)
	run.append(s)
	leg.append(li)


## The section blended at each sample. Numeric fields lerp from the previous leg's over this
## leg's `blend` metres, so a median opens and lanes merge instead of stepping.
func _resolve_sections() -> void:
	sec.clear()
	var legs: Array = data.legs
	var leg_start := {}
	for i in pts.size():
		if not leg_start.has(leg[i]):
			leg_start[leg[i]] = run[i]
	for i in pts.size():
		var li: int = leg[i]
		var l: Dictionary = legs[li]
		if str(l.kind) == "roundabout":
			li = maxi(li - 1, 0)
			l = legs[li]
		var cur: Dictionary = SECTIONS[str(l.get("section", "esplanade"))]
		var blend: float = float(l.get("blend", 0.0))
		var out: Dictionary = cur.duplicate()
		if blend > 0.0 and li > 0:
			var prev_li := li - 1
			while prev_li > 0 and str((legs[prev_li] as Dictionary).kind) == "roundabout":
				prev_li -= 1
			var prev: Dictionary = SECTIONS[str((legs[prev_li] as Dictionary).get("section", "esplanade"))]
			var t := clampf((run[i] - float(leg_start.get(li, 0.0))) / blend, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			for k in cur:
				out[k] = lerpf(float(prev[k]), float(cur[k]), t)
		_derive(out)
		sec.append(out)


## Lateral lines of a resolved section, all measured from the centre line (left positive).
static func _derive(s: Dictionary) -> void:
	var lanes_w := float(s.lanes) * float(s.lane_w)
	s["kerb_w"] = -(float(s.median) + lanes_w + float(s.park_w))
	s["kerb_e"] = float(s.median) + lanes_w + float(s.park_e)
	s["walk_w_edge"] = float(s.kerb_w) - float(s.walk_w)
	s["walk_e_edge"] = float(s.kerb_e) + float(s.walk_e)
	# The bluff edge: past the west lots when there are any, else past the verge.
	s["edge"] = float(s.walk_w_edge) - float(s.verge) - float(s.west_lots)
	s["toe"] = float(s.edge) - float(s.bluff)
	s["water"] = float(s.toe) - float(s.beach)
	s["east_back"] = float(s.walk_e_edge) + float(s.east_lots) + float(s.alley)


## The road-top profile: authored for the city legs, smoothed and grade-limited; the hill legs
## are filled in by `fit_hill_profile()` once the terrain exists.
func _city_profile() -> void:
	top.resize(pts.size())
	var prof: Array = data.profile
	for i in pts.size():
		top[i] = _profile_at(prof, minf(run[i], s_city_end))
	_smooth_and_limit(0, pts.size() - 1)


static func _profile_at(prof: Array, s: float) -> float:
	if prof.is_empty():
		return 0.0
	if s <= float(prof[0][0]):
		return float(prof[0][1])
	for k in range(1, prof.size()):
		if s <= float(prof[k][0]):
			var a: Array = prof[k - 1]
			var b: Array = prof[k]
			return lerpf(float(a[1]), float(b[1]), (s - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001))
	return float(prof[prof.size() - 1][1])


func _smooth_and_limit(i0: int, i1: int) -> void:
	i1 = mini(i1, top.size() - 1)
	for pass_i in 3:
		var src := top.duplicate()
		for i in range(i0, i1 + 1):
			var sum := 0.0
			var n := 0
			for k in range(-6, 7):
				var j := i + k
				if j >= i0 and j <= i1:
					sum += src[j]
					n += 1
			top[i] = sum / n
	var g: float = data.get("max_grade", 0.085)
	for i in range(i0 + 1, i1 + 1):
		var r := run[i] - run[i - 1]
		top[i] = clampf(top[i], top[i - 1] - g * r, top[i - 1] + g * r)
	for i in range(i1 - 1, i0 - 1, -1):
		var r := run[i + 1] - run[i]
		top[i] = clampf(top[i], top[i + 1] - g * r, top[i + 1] + g * r)


## The hill part of the route follows the headland's slope: raw terrain under each sample,
## smoothed, held to the grade and never more than `hill_cut` metres off the ground. Called by
## MacroMap once the headland exists (the city part does not depend on it).
func fit_hill_profile() -> void:
	var i0 := pts.size() - 1
	var city_top := top.duplicate()
	_sample_legs(int(data.get("city_legs", (data.legs as Array).size())), (data.legs as Array).size())
	_resolve_sections()
	top = city_top
	top.resize(pts.size())
	if i0 < pts.size() - 1:
		var cut: float = data.get("hill_cut", 3.0)
		var g: float = data.get("hill_grade", data.get("max_grade", 0.085))
		for i in range(i0 + 1, pts.size()):
			top[i] = _terrain(pts[i]) + 0.3
		# Smooth the hill part only, holding the join to the city part.
		for pass_i in 4:
			var src := top.duplicate()
			for i in range(i0 + 1, pts.size()):
				var sum := 0.0
				var n := 0
				for k in range(-8, 9):
					var j := clampi(i + k, i0, pts.size() - 1)
					sum += src[j]
					n += 1
				top[i] = sum / n
		var ground := PackedFloat32Array()
		ground.resize(pts.size())
		for i in range(i0 + 1, pts.size()):
			ground[i] = _terrain(pts[i])
		# Hold it near the ground and to the grade, alternately, so neither undoes the other.
		for pass_i in 3:
			for i in range(i0 + 1, pts.size()):
				top[i] = clampf(top[i], ground[i] - cut, ground[i] + cut)
			for i in range(i0 + 1, pts.size()):
				var r := run[i] - run[i - 1]
				top[i] = clampf(top[i], top[i - 1] - g * r, top[i - 1] + g * r)
			for i in range(pts.size() - 2, i0, -1):
				var r := run[i + 1] - run[i]
				top[i] = clampf(top[i], top[i + 1] - g * r, top[i + 1] + g * r)
	_index()
	_near_cache.clear()
	# The side streets sit level with the route where they leave it.
	for st in streets:
		_sample_street(st)


func _sample_street(st: Dictionary) -> void:
	var def: Dictionary = st.def
	var from: Vector2
	var base_top: float
	if st.has("roundabout"):
		var ra: Dictionary = st.roundabout
		from = ra.center
		base_top = top[int(ra.index)]
	else:
		var i := _index_of_s(float(def.s))
		var side: float = float(def.get("side", 1.0))
		from = pts[i] + left_of(dirs[i]) * (float(sec[i].kerb_e) if side > 0.0 else float(sec[i].kerb_w))
		base_top = top[i]
	var d := dir_of(float(def.heading_deg))
	var n := maxi(2, ceili(float(def.length) / STEP))
	var spts := PackedVector2Array()
	var stop := PackedFloat32Array()
	for k in n + 1:
		var p := from + d * (float(def.length) * float(k) / n)
		spts.append(p)
		stop.append(base_top)
	st["pts"] = spts
	st["top"] = stop
	st["dir"] = d
	var section: Dictionary = (SECTIONS[str(def.get("section", "avenue"))] as Dictionary).duplicate()
	_derive(section)
	st["section"] = section
	st["name"] = str(def.name)


func _index_of_s(s: float) -> int:
	var lo := 0
	var hi := run.size() - 1
	if s <= 0.0:
		return 0
	if s >= run[hi]:
		return hi
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if run[mid] <= s:
			lo = mid
		else:
			hi = mid
	return lo


## Everything about the route at path distance `s`: [point, heading, road top, section].
func at_s(s: float) -> Array:
	s = clampf(s, 0.0, length)
	var i := _index_of_s(s)
	var j := mini(i + 1, pts.size() - 1)
	var f := 0.0 if j == i else (s - run[i]) / maxf(run[j] - run[i], 0.0001)
	var d := dirs[i].slerp(dirs[j], f) if dirs[i].dot(dirs[j]) > -0.5 else dirs[j]
	return [pts[i].lerp(pts[j], f), d.normalized(), lerpf(top[i], top[j], f), sec[i]]


# --- The index ---------------------------------------------------------------------------------

## How many samples the index covers. While the hill legs are being sampled the index still
## holds only the city ones, and nearest() must not walk into samples with no section yet.
var _n_indexed: int = 0


func _index() -> void:
	_cells.clear()
	_n_indexed = pts.size()
	# Everything the replica can touch lies within NEAR_REACH of its centre line.
	_bounds = Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		_bounds = _bounds.expand(q)
	_bounds = _bounds.grow(NEAR_REACH + 40.0)
	# Plain Arrays: a PackedInt32Array is a value type, so appending to one fetched out of the
	# dictionary appends to a copy and the index comes out empty.
	for i in pts.size():
		var key := Vector2i(floori(pts[i].x / CELL), floori(pts[i].y / CELL))
		if not _cells.has(key):
			_cells[key] = []
		(_cells[key] as Array).append(i)


## Size of the cells the nearest-sample cache is kept in (metres), and how far from the route a
## cell still looks for one. terrace_at() runs for every relief sample a chunk takes - thousands
## per chunk - so a full search each time would cost more than the rest of the chunk build.
const NEAR_CELL := 16.0
const NEAR_REACH := 260.0
var _near_cache := {}


func _cell_nearest(key: Vector2i) -> int:
	var cached: Variant = _near_cache.get(key)
	if cached != null:
		return cached
	var c := (Vector2(key) + Vector2(0.5, 0.5)) * NEAR_CELL
	var r := ceili((NEAR_REACH + NEAR_CELL) / CELL)
	var cx := floori(c.x / CELL)
	var cz := floori(c.y / CELL)
	var best_i := -1
	var best_d := INF
	for gx in range(cx - r, cx + r + 1):
		for gz in range(cz - r, cz + r + 1):
			var list: Variant = _cells.get(Vector2i(gx, gz))
			if list == null:
				continue
			for i: int in list as Array:
				var d := c.distance_squared_to(pts[i])
				if d < best_d:
					best_d = d
					best_i = i
	if best_d > (NEAR_REACH + NEAR_CELL) * (NEAR_REACH + NEAR_CELL):
		best_i = -1
	if _near_cache.size() > 200000:
		_near_cache.clear()
	_near_cache[key] = best_i
	return best_i


## The nearest point of the centre line within `reach` metres (at most NEAR_REACH): {"i", "s",
## "o" (left positive), "d" (distance), "p", "beyond"}, or {} when nothing is that close. Past
## either end the lateral offset is still measured from the end sample, and `beyond` says how far
## past it the point is.
func nearest(pos: Vector2, reach: float) -> Dictionary:
	var guess := _cell_nearest(Vector2i(floori(pos.x / NEAR_CELL), floori(pos.y / NEAR_CELL)))
	if guess < 0:
		return {}
	# The true nearest sample of any point in the cell is within a cell diagonal of the cell
	# centre's, which is a handful of samples either way.
	var span := ceili(NEAR_CELL * 1.5 / STEP) + 2
	var last := _n_indexed - 1
	var best_i := -1
	var best_d := INF
	for i in range(maxi(guess - span, 0), mini(guess + span, last) + 1):
		var d := pos.distance_squared_to(pts[i])
		if d < best_d:
			best_d = d
			best_i = i
	if best_i < 0 or best_d > reach * reach * 2.0:
		return {}
	# Refine onto the segment either side of the nearest sample.
	var out := {}
	var best := INF
	for seg in [best_i - 1, best_i]:
		if seg < 0 or seg >= last:
			continue
		var a := pts[seg]
		var ab := pts[seg + 1] - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + ab * t
		var d := pos.distance_to(q)
		if d < best:
			best = d
			var dir := dirs[seg].slerp(dirs[seg + 1], t).normalized()
			out = {"i": seg if t < 0.5 else seg + 1, "s": lerpf(run[seg], run[seg + 1], t),
				"o": (pos - q).dot(left_of(dir)), "d": d, "p": q, "beyond": 0.0}
	if out.is_empty():
		var q := pts[best_i]
		out = {"i": best_i, "s": run[best_i], "o": (pos - q).dot(left_of(dirs[best_i])), "d": sqrt(best_d), "p": q, "beyond": 0.0}
	# Past an end of the route: how far along its own heading.
	if best_i == 0 or best_i == last:
		var along := (pos - pts[best_i]).dot(dirs[best_i])
		if best_i == 0 and along < 0.0:
			out.beyond = -along
		elif best_i == last and along > 0.0:
			out.beyond = along
	if float(out.d) > reach:
		return {}
	return out


# --- The coast ---------------------------------------------------------------------------------

## The waterline and the beach width as tables of z, from the sections' `water` and `toe` lines.
func _tables() -> void:
	var z_lo := INF
	var z_hi := -INF
	var wl_pts: Array[Vector2] = []
	var toe_pts: Array[Vector2] = []
	var cx_pts: Array[Vector3] = []
	var wl_max := -INF
	var toe_max := -INF
	for i in pts.size():
		if float(sec[i].coast) < 0.5 or run[i] > s_city_end:
			continue
		var l := left_of(dirs[i])
		var w := pts[i] + l * float(sec[i].water)
		var t := pts[i] + l * float(sec[i].toe)
		# Each line kept only where it moves on down the coast. Where the route turns right (the
		# roundabout) its seaward lines are on the INSIDE of the turn, a hundred metres out from a
		# turn of a few tens: they fold back on themselves, and a table read by z then jumps
		# backwards - the sand once covered the whole south curve because of it.
		if w.y > wl_max + 0.01:
			wl_pts.append(w)
			wl_max = w.y
		if t.y > toe_max + 0.01:
			toe_pts.append(t)
			toe_max = t.y
		cx_pts.append(Vector3(pts[i].y, pts[i].x, run[i]))
		z_lo = minf(z_lo, w.y)
		z_hi = maxf(z_hi, w.y)
	_wl_z0 = z_lo
	var n := int((z_hi - z_lo) / WL_DZ) + 1
	_wl.resize(n)
	_bw.resize(n)
	_cx.resize(n)
	_cs.resize(n)
	# The waterline and the bluff toe each interpolated by their OWN z. The beach is the gap
	# between them along x, which is what the sand is laid across: measured along the section's
	# normal instead, it came out a sixth too wide on the curve and the sand ran up the bluff.
	var k := 0
	var kt := 0
	for j in n:
		var z := _wl_z0 + float(j) * WL_DZ
		while k < wl_pts.size() - 2 and wl_pts[k + 1].y < z:
			k += 1
		while kt < toe_pts.size() - 2 and toe_pts[kt + 1].y < z:
			kt += 1
		_wl[j] = _lerp_z(wl_pts, k, z)
		_bw[j] = maxf(_lerp_z(toe_pts, kt, z) - _wl[j], 6.0)
	var m := 0
	for j in n:
		var z := _wl_z0 + float(j) * WL_DZ
		while m < cx_pts.size() - 2 and cx_pts[m + 1].x < z:
			m += 1
		var a3 := cx_pts[m]
		var b3 := cx_pts[mini(m + 1, cx_pts.size() - 1)]
		var f := clampf((z - a3.x) / maxf(b3.x - a3.x, 0.0001), 0.0, 1.0)
		_cx[j] = lerpf(a3.y, b3.y, f)
		_cs[j] = lerpf(a3.z, b3.z, f)


## x of polyline `p` (points in x, z, increasing z) at z, from segment k on.
static func _lerp_z(p: Array[Vector2], k: int, z: float) -> float:
	var a := p[k]
	var b := p[mini(k + 1, p.size() - 1)]
	var f := clampf((z - a.y) / maxf(b.y - a.y, 0.0001), 0.0, 1.0)
	return lerpf(a.x, b.x, f)


## The replica's z range of coast: [first, last] z of its waterline table.
func coast_range() -> Vector2:
	return Vector2(_wl_z0, _wl_z0 + float(maxi(_wl.size() - 1, 0)) * WL_DZ)


static func _table(t: PackedFloat32Array, z0: float, dz: float, z: float) -> float:
	if t.is_empty():
		return 0.0
	var f := (z - z0) / dz
	var j := clampi(floori(f), 0, t.size() - 1)
	var j1 := mini(j + 1, t.size() - 1)
	return lerpf(t[j], t[j1], clampf(f - float(j), 0.0, 1.0))


## x of the waterline at z (only meaningful inside coast_range()).
func waterline_x(z: float) -> float:
	return _table(_wl, _wl_z0, WL_DZ, z)


func beach_width(z: float) -> float:
	return _table(_bw, _wl_z0, WL_DZ, z)


## The waterline table for the ocean shader: [z0, dz, PackedFloat32Array x]. Resampled to `n`.
func waterline_table(n: int) -> Array:
	var r := coast_range()
	var out := PackedFloat32Array()
	out.resize(n)
	var dz := (r.y - r.x) / float(n - 1)
	for j in n:
		out[j] = waterline_x(r.x + dz * float(j))
	return [r.x, dz, out]


# --- The terrace -------------------------------------------------------------------------------

## The ground the replica's town stands on at `pos`, metres above sea level, and how strongly the
## seeded relief is kept off it: Vector2(ground, calm). Ground is the road-top profile less
## ROAD_TOP across the road and inland of it, stepping down the bluff face to the sand on the
## ocean side, easing away past the ends and far inland. Zero where the replica has no say.
func terrace_at(pos: Vector2) -> Vector2:
	if _cx.is_empty():
		return Vector2.ZERO
	var r := coast_range()
	if pos.y < r.x - END_FADE - 200.0 or pos.y > r.y + 400.0:
		return Vector2.ZERO
	var hit := nearest(pos, 190.0)
	var s: float
	var o: float
	var beyond := 0.0
	var sd: Dictionary = {}
	if hit.is_empty():
		# Further inland than the index reaches: measure across by z, which is good enough for a
		# route that runs north-south (heading south, east is left, so the offset is x minus the
		# centre line's x), and only the gentle inland ease is decided out here.
		if pos.y < r.x or pos.y > r.y:
			return Vector2.ZERO
		s = _table(_cs, _wl_z0, WL_DZ, pos.y)
		o = pos.x - _table(_cx, _wl_z0, WL_DZ, pos.y)
		if o < 0.0:
			return Vector2.ZERO
		sd = sec[_index_of_s(s)]
	else:
		s = float(hit.s)
		o = float(hit.o)
		beyond = float(hit.beyond)
		sd = sec[int(hit.i)]
	# Past the town the hill road takes over (HillRoads carves it); the town's ground eases out
	# over END_FADE rather than stopping dead, or a cliff ran inland from the Paseo's end.
	if s > s_city_end + END_FADE:
		return Vector2.ZERO
	if s > s_city_end:
		var tail := terrace_without_car_park(pos, s_city_end, o, beyond, sec[_index_of_s(s_city_end)])
		return tail * (1.0 - smoothstep(s_city_end, s_city_end + END_FADE, s))
	# The beach car park is a platform of its own, and so is the ground between it and the road.
	var lot_level := car_park_level(pos)
	if lot_level > -INF:
		var under := lot_level - WALK_TOP - 0.01
		var road := terrace_without_car_park(pos, s, o, beyond, sd)
		return Vector2(maxf(maxf(road.x, under), 0.0), 1.0)
	return terrace_without_car_park(pos, s, o, beyond, sd)


## The surface height of the beach car park over `pos` (the platform and the ground between it
## and the road), or -INF when pos is not over it.
func car_park_level(pos: Vector2) -> float:
	var cp: Dictionary = data.get("car_park", {})
	if cp.is_empty() or pts.is_empty():
		return -INF
	if _cp_frame.is_empty():
		var at := at_s(float(cp.s))
		_cp_frame = {"p": at[0], "d": at[1], "l": left_of(at[1]), "entry": float(at_s(float(cp.s) + float(cp.along[0]))[2])}
	var q: Vector2 = pos - (_cp_frame.p as Vector2)
	var a := q.dot(_cp_frame.d)
	var o := q.dot(_cp_frame.l)
	if a < float(cp.along[0]) - 3.0 or a > float(cp.along[1]) + 3.0 or o < float(cp.lateral[0]) - 0.6:
		return -INF
	# East of the lot only as far as the road's own ground reaches.
	var hit := nearest(pos, 120.0)
	if not hit.is_empty() and float(hit.o) > float((sec[int(hit.i)] as Dictionary).walk_w_edge) - 1.0:
		return -INF
	var t := smoothstep(float(cp.along[0]), float(cp.along[0]) + float(cp.get("ramp", 0.0)), a)
	return lerpf(float(_cp_frame.entry), float(cp.elev), t)


var _cp_frame := {}


func terrace_without_car_park(_pos: Vector2, s: float, o: float, beyond: float, sd: Dictionary) -> Vector2:
	var i := _index_of_s(s)
	var j := mini(i + 1, top.size() - 1)
	var ground := lerpf(top[i], top[j], clampf((s - run[i]) / maxf(run[j] - run[i], 0.001), 0.0, 1.0)) - ROAD_TOP
	var calm := 1.0
	var h := ground
	var edge: float = sd.edge
	var toe: float = sd.toe
	if o < edge:
		if float(sd.coast) < 0.5:
			h = ground
		elif o <= toe:
			return Vector2(0.0, 1.0)
		else:
			# The bluff face: steep near the top, easing out onto the sand.
			var t := (edge - o) / maxf(edge - toe, 0.01)
			h = lerpf(ground, 0.35, 1.0 - pow(1.0 - t, 1.6))
	elif o > INLAND_FLAT:
		var t := smoothstep(INLAND_FLAT, INLAND_FADE_END, o)
		h = ground * (1.0 - t)
	if o > CALM_FLAT:
		calm = 1.0 - smoothstep(CALM_FLAT, CALM_END, o)
	if beyond > 0.0:
		var f := 1.0 - smoothstep(0.0, END_FADE, beyond)
		h *= f
		calm *= f
	return Vector2(maxf(h, 0.0), calm)


# --- The corridor ------------------------------------------------------------------------------

## True when `pos` is somewhere the seeded city must not build: on the route, its pavements, its
## frontage lots and alley, the bluff and the beach, or one of its own side streets. `pad` grows
## everything by that many metres.
func blocks_grid(pos: Vector2, pad: float = 0.0, east_key: String = "east_back") -> bool:
	var hit := nearest(pos, 200.0)
	if not hit.is_empty() and float(hit.beyond) <= pad + 4.0:
		var sd: Dictionary = sec[int(hit.i)]
		var o: float = hit.o
		if float(hit.beyond) > pad:
			# Past the north end: only its pavement (ReplicaBuilder._north_end()).
			if o >= float(sd.walk_w_edge) - pad and o <= float(sd.walk_e_edge) + pad:
				return true
		elif float(hit.s) <= s_city_end + 1.0:
			var west: float = float(sd.water) - 30.0 if float(sd.coast) > 0.5 else float(sd.walk_w_edge)
			if o >= west - pad and o <= float(sd[east_key]) + pad:
				return true
		elif absf(o) <= float(sd.kerb_e) + 3.0 + pad:
			return true
	for ra in roundabouts:
		if pos.distance_to(ra.center) < float(ra.r_out) + 12.0 + pad:
			return true
	for st in streets:
		if not st.has("pts"):
			continue
		var sp: PackedVector2Array = st.pts
		var half: float = float(st.section.walk_e_edge) + pad
		for k in sp.size() - 1:
			if Geometry2D.get_closest_point_to_segment(pos, sp[k], sp[k + 1]).distance_to(pos) < half:
				return true
	return false


## How a chunk's block relates to the replica: 0 not at all, 1 it touches the corridor (the chunk
## skips the seeded block content and builds the replica's instead).
func chunk_role(rect: Rect2) -> int:
	var c := rect.get_center()
	if nearest(c, 260.0).is_empty():
		var any := false
		for ra in roundabouts:
			if c.distance_to(ra.center) < 260.0:
				any = true
		if not any:
			return 0
	# Test the rect's corners, edge midpoints and centre, then a grid across it.
	for fx in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for fz in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var p := rect.position + rect.size * Vector2(fx, fz)
			if blocks_grid(p, 2.0):
				return 1
	return 0


# --- Where the seeded grid meets the replica ---------------------------------------------------

var _mouths: Array[Dictionary] = []
var _mouths_seed: int = -1


## The seeded grid's east-west streets that run into the route from the town side: path distance
## `s` where each meets it, the street's `z` and `width`, and its grid index `j`. The frontage
## leaves a gap for each, the replica lays the pavement across its mouth, and every
## `stop_every`-th one gets an all-way stop and a crosswalk.
func mouths(plan: CityPlan) -> Array[Dictionary]:
	if _mouths_seed == plan.seed:
		return _mouths
	_mouths_seed = plan.seed
	_mouths.clear()
	var r := coast_range()
	var j := plan._index_at(CityPlan.AXIS_Z, r.x)
	while plan.road_pos(CityPlan.AXIS_Z, j) < r.y:
		var z := plan.road_pos(CityPlan.AXIS_Z, j)
		var s := _table(_cs, _wl_z0, WL_DZ, z)
		# Not where the route has no east frontage: the ends, the curve and the roundabout.
		var sd: Dictionary = sec[_index_of_s(s)]
		# Not across the condominium either: its block runs the whole way along (the street
		# ends at its back fence).
		var condo: Dictionary = data.get("condo", {})
		var hw := plan.road_width(CityPlan.AXIS_Z, j) * 0.5 + 6.0
		var under_condo := not condo.is_empty() and s > float(condo.s[0]) - hw and s < float(condo.s[1]) + hw
		if s > 30.0 and s < s_city_end - 20.0 and float(sd.east_lots) > 20.0 and absf(float(sd.median_raised)) < 0.5 and not under_condo:
			_mouths.append({"s": s, "z": z, "width": plan.road_width(CityPlan.AXIS_Z, j), "j": j,
				"stop": _mouths.size() % int(data.get("stop_every", 2)) == 0,
				"origin": Vector2(_table(_cx, _wl_z0, WL_DZ, z), z), "dir": Vector2(1.0, 0.0), "sw": plan.sidewalk_width})
		j += 1
	# The replica's own side streets off the east kerb (Knob Hill Ave) meet the frontage the same
	# way: a gap in the houses, the carriageway and its pavements laid across the frontage.
	for st in streets:
		if st.has("roundabout") or not st.has("pts") or float(st.def.get("side", 1.0)) < 0.0:
			continue
		var sec_st: Dictionary = st.section
		_mouths.append({"s": float(st.def.s), "z": (st.pts as PackedVector2Array)[0].y, "width": float(sec_st.kerb_e) * 2.0,
			"j": -1, "name": str(st.name).to_upper(), "stop": false, "origin": (st.pts as PackedVector2Array)[0],
			"dir": st.dir, "sw": float(sec_st.walk_e_edge) - float(sec_st.kerb_e), "own": true})
	_mouths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.s) < float(b.s))
	return _mouths


## True when path distance `s` is within `half` metres of a street mouth's edges.
func _in_mouth(plan: CityPlan, s: float, half: float) -> bool:
	for m in mouths(plan):
		if absf(s - float(m.s)) < float(m.width) * 0.5 / 0.98 + half:
			return true
	return false


# --- Lots ----------------------------------------------------------------------------------------

## Stucco, weighted like a real street: mostly warm whites, creams and sand, a pale green, a
## salmon and a grey now and then (the photos: beige, tan, cream, a mint garden wall).
const STUCCO := [
	Color(0.90, 0.88, 0.82), Color(0.90, 0.88, 0.82), Color(0.86, 0.82, 0.72), Color(0.86, 0.82, 0.72),
	Color(0.80, 0.72, 0.60), Color(0.80, 0.72, 0.60), Color(0.74, 0.65, 0.52), Color(0.93, 0.92, 0.89),
	Color(0.72, 0.78, 0.66), Color(0.86, 0.68, 0.56), Color(0.76, 0.76, 0.74), Color(0.83, 0.77, 0.66),
]
## Roof tile tints over the clay texture: brown concrete tile, terracotta, dark brown, grey-brown.
const TILE_TINTS := [Color(0.78, 0.58, 0.46), Color(1.0, 0.80, 0.66), Color(0.62, 0.48, 0.40), Color(0.70, 0.62, 0.56)]

var _frontage: Array[Dictionary] = []
var _frontage_seed: int = -1


## Every lot on the route's own frontage, true world XZ: the houses and apartments along the
## Esplanade's inland side, both sides of Paseo de la Playa, and the condominium block. Seeded from
## the plan seed alone, so every tier (FULL, LOD, the far skyline) sees the same ones.
func frontage_lots(plan: CityPlan) -> Array[Dictionary]:
	if _frontage_seed == plan.seed:
		return _frontage
	_frontage_seed = plan.seed
	_frontage.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, "replica_frontage", str(data.id)])
	var widths: Vector2 = Vector2(data.lot_width[0], data.lot_width[1])
	var gap: float = data.get("street_gap", 3.0)
	var condo: Dictionary = data.get("condo", {})
	var condo_span := Vector2(condo.s[0], condo.s[1]) if not condo.is_empty() else Vector2(-1.0, -1.0)
	var last_poly := {}
	for side: float in [1.0, -1.0]:
		var s := 34.0
		while s < s_city_end - 12.0:
			var w := rng.randf_range(widths.x, widths.y)
			var sd: Dictionary = sec[_index_of_s(s + w * 0.5)]
			var depth: float = float(sd.east_lots) if side > 0.0 else float(sd.west_lots)
			var sd_end: Dictionary = sec[_index_of_s(s + w)]
			var depth_end: float = float(sd_end.east_lots) if side > 0.0 else float(sd_end.west_lots)
			if depth < 20.0 or depth_end < 20.0:
				s += 6.0
				continue
			if _in_mouth(plan, s + w * 0.5, w * 0.5 + gap) and side > 0.0:
				s += 4.0
				continue
			if side > 0.0 and s + w > condo_span.x - 4.0 and s < condo_span.y + 4.0:
				s = condo_span.y + 4.0
				continue
			var kind_roll := rng.randf()
			var kind := "house"
			if kind_roll < 0.16 and w > 12.5:
				# A small apartment block takes the next lot as well.
				kind = "apartment"
				w = minf(w * 1.9, 28.0)
			elif kind_roll < 0.34:
				kind = "duplex"
			elif kind_roll < 0.42:
				kind = "modern"
			var mid := s + w * 0.5
			var a := at_s(mid)
			var p: Vector2 = a[0]
			var d: Vector2 = a[1]
			var sdm: Dictionary = a[3]
			var line: float = float(sdm.walk_e_edge) if side > 0.0 else float(sdm.walk_w_edge)
			var centre := p + left_of(d) * (line + side * depth * 0.5)
			var front := -left_of(d) * side
			var fl := _lot(rng, centre, w, depth, front, kind, "frontage")
			fl["s"] = mid
			fl["side"] = side
			# On the inside of a bend the lots fan in toward each other at the back; a house that
			# would run into the one before it is left out (its lot becomes garden).
			var poly := _house_poly(fl)
			if last_poly.has(side) and not Geometry2D.intersect_polygons(poly, last_poly[side]).is_empty():
				s += w
				continue
			last_poly[side] = poly
			_frontage.append(fl)
			s += w
	if not condo.is_empty():
		var mid := (condo_span.x + condo_span.y) * 0.5
		var a := at_s(mid)
		var sdm: Dictionary = a[3]
		var side: float = condo.get("side", 1.0)
		var depth: float = float(condo.depth) + float(condo.setback) + 4.0
		var centre: Vector2 = (a[0] as Vector2) + left_of(a[1]) * ((float(sdm.walk_e_edge) + depth * 0.5) * side)
		var lot := _lot(rng, centre, condo_span.y - condo_span.x, depth, -left_of(a[1]) * side, "condo", "frontage")
		lot["storeys"] = int(condo.storeys)
		lot["height"] = float(condo.storeys) * float(condo.storey_h) + 1.2
		lot["color"] = Color(0.93, 0.92, 0.88)
		lot["s"] = mid
		lot["side"] = side
		_frontage.append(lot)
	return _frontage


## A house's gaps to its neighbours either side and behind, and its entry door's width
## (house_frame()).
const HOUSE_SIDE_GAP := Vector2(0.9, 1.7)
const HOUSE_REAR_GAP := Vector2(2.5, 4.5)
const HOUSE_DOOR_W := 1.0


## A lot's footprint in its own frame (u along the street, v toward it, the lot centred on 0):
## the house rect, the driveway (u centre and width, 0 when there is no garage) and the entry.
## Pure, and cached on the lot, so the kerb parking, the frontage's overlap test and the house
## (ReplicaHouses) all agree. Here rather than in ReplicaHouses so this class stays free of the
## chunk-side classes, which use autoloads: MacroMap and CityPlan are named by --script tools.
static func house_frame(the_lot: Dictionary) -> Dictionary:
	if the_lot.has("frame"):
		return the_lot.frame
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(the_lot.seed), "frame"])
	var w: float = the_lot.w
	var d: float = the_lot.d
	var kind: String = the_lot.kind
	var gl := r.randf_range(HOUSE_SIDE_GAP.x, HOUSE_SIDE_GAP.y)
	var gr := r.randf_range(HOUSE_SIDE_GAP.x, HOUSE_SIDE_GAP.y)
	var rear := r.randf_range(HOUSE_REAR_GAP.x, HOUSE_REAR_GAP.y)
	var setback: float = the_lot.setback
	var max_d := 18.0 if kind == "house" else (21.0 if kind != "condo" else 21.0)
	if kind == "condo":
		gl = 1.0
		gr = 1.0
		setback = 9.0
		rear = d - 9.0 - 21.0
	var width := maxf(w - gl - gr, 6.0)
	var depth := clampf(d - setback - rear, 8.0, max_d)
	var u0 := -w * 0.5 + gl
	var u1 := u0 + width
	var v1 := d * 0.5 - setback
	var v0 := v1 - depth
	var drive_w := 0.0
	var drive_u := 0.0
	var side := 1.0 if r.randf() < 0.5 else -1.0
	if bool(the_lot.garage) and kind != "condo":
		drive_w = 5.2 if (width > 11.5 and r.randf() < 0.55) or kind == "duplex" else 2.9
		drive_u = (u1 - drive_w * 0.5 - 0.7) if side > 0.0 else (u0 + drive_w * 0.5 + 0.7)
	var entry_u := (u0 + 0.7 + HOUSE_DOOR_W * 0.5) if side > 0.0 else (u1 - 0.7 - HOUSE_DOOR_W * 0.5)
	if drive_w > 4.0 and width < 13.0:
		# A double garage on a narrow house leaves the door round the side of the porch.
		entry_u = (u0 + 0.55 + HOUSE_DOOR_W * 0.5) if side > 0.0 else (u1 - 0.55 - HOUSE_DOOR_W * 0.5)
	var f := {"u0": u0, "u1": u1, "v0": v0, "v1": v1, "drive_u": drive_u, "drive_w": drive_w, "entry_u": entry_u}
	the_lot["frame"] = f
	return f


## The footprint of the house a lot stands (house_frame()) as a world polygon.
static func _house_poly(lot: Dictionary) -> PackedVector2Array:
	var f := house_frame(lot)
	var fr: Vector2 = (lot.front as Vector2).normalized()
	var al := Vector2(-fr.y, fr.x)
	var c: Vector2 = lot.center
	var poly := PackedVector2Array()
	for q: Vector2 in [Vector2(f.u0, f.v0), Vector2(f.u1, f.v0), Vector2(f.u1, f.v1), Vector2(f.u0, f.v1)]:
		poly.append(c + al * q.x + fr * q.y)
	return poly


## One lot: centre, width along its street, depth back from it, the direction its front faces
## (toward the street), what stands on it, and what it looks like - all rolled here, so the house
## a chunk builds and the box the far skyline draws are the same building.
func _lot(rng: RandomNumberGenerator, centre: Vector2, w: float, depth: float, front: Vector2, kind: String, where: String) -> Dictionary:
	var storeys := 2
	match kind:
		"apartment", "duplex":
			storeys = 3
		"modern":
			storeys = 2 if rng.randf() < 0.5 else 3
		_:
			storeys = 3 if rng.randf() < 0.22 else 2
	var roof := "flat"
	if kind == "house":
		roof = "hip" if rng.randf() < 0.62 else ("gable" if rng.randf() < 0.5 else "flat")
	elif kind == "duplex":
		roof = "hip" if rng.randf() < 0.35 else "flat"
	var height := float(storeys) * 3.0 + (2.2 if roof != "flat" else 0.9)
	# The world-axis extents the far tier draws the lot's box with.
	var along := Vector2(-front.y, front.x)
	var ext := Vector2(absf(along.x) * w + absf(front.x) * depth, absf(along.y) * w + absf(front.y) * depth)
	return {
		"seed": rng.randi(), "size": ext * 0.82, "center": centre, "edge": true, "yard": false,
		"replica": true, "where": where, "kind": kind, "w": w, "d": depth, "front": front,
		"storeys": storeys, "roof": roof, "height": height,
		"color": STUCCO[rng.randi() % STUCCO.size()], "tile": TILE_TINTS[rng.randi() % TILE_TINTS.size()],
		"trim": rng.randf(), "garage": rng.randf() < 0.8, "balcony": rng.randf() < 0.7,
		"setback": rng.randf_range(3.0, 6.0),
	}


## The lots a replica block builds, or null when the block is not one: the frontage lots whose
## centre is in it, and seeded backfill houses on the rest of it, facing the grid's streets.
## CityPlan.lots() returns this for replica blocks so every tier agrees.
func block_lots(plan: CityPlan, ix: int, iz: int) -> Variant:
	var key := "%d,%d,%d" % [ix, iz, plan.seed]
	if _block_lot_cache.has(key):
		return _block_lot_cache[key]
	var owned := owned_rect(plan, ix, iz)
	# Most blocks asked about (the far skyline walks the whole basin) are nowhere near.
	if not _bounds.intersects(owned):
		_block_lot_cache[key] = null
		return null
	var b := plan.block(ix, iz)
	var rect: Rect2 = b.rect
	var out: Array[Dictionary] = []
	for lot in frontage_lots(plan):
		if owned.has_point(lot.center):
			out.append(lot)
	if out.is_empty() and chunk_role(rect) == 0:
		_block_lot_cache[key] = null
		return null
	out.append_array(_backfill(plan, ix, iz, rect))
	_block_lot_cache[key] = out
	return out


## A block's role (see chunk_role()), counting a block that owns a frontage lot as a replica block
## even when the corridor only grazes it. What CityChunk and CityPlan.lots() both go by.
func block_role(plan: CityPlan, ix: int, iz: int) -> int:
	return 0 if block_lots(plan, ix, iz) == null else 1


## The area a chunk owns: its block and the roads on its +X and +Z sides (CityChunk.owned_rect()).
static func owned_rect(plan: CityPlan, ix: int, iz: int) -> Rect2:
	var x0 := plan.road_pos(CityPlan.AXIS_X, ix) + plan.road_width(CityPlan.AXIS_X, ix) * 0.5
	var x1 := plan.road_pos(CityPlan.AXIS_X, ix + 1) + plan.road_width(CityPlan.AXIS_X, ix + 1) * 0.5
	var z0 := plan.road_pos(CityPlan.AXIS_Z, iz) + plan.road_width(CityPlan.AXIS_Z, iz) * 0.5
	var z1 := plan.road_pos(CityPlan.AXIS_Z, iz + 1) + plan.road_width(CityPlan.AXIS_Z, iz + 1) * 0.5
	return Rect2(x0, z0, x1 - x0, z1 - z0)


## Seeded houses on the part of a replica block the corridor leaves: a row facing the street on
## each of its north and south edges, filled from its east edge westward until the corridor.
func _backfill(plan: CityPlan, ix: int, iz: int, rect: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, "replica_backfill", ix, iz])
	var inner := rect.grow(-plan.sidewalk_width)
	if inner.size.x < 12.0 or inner.size.y < 14.0:
		return out
	var depth := minf(30.0, inner.size.y * 0.5)
	for row in 2:
		var front := Vector2(0.0, -1.0) if row == 0 else Vector2(0.0, 1.0)
		var zc := inner.position.y + depth * 0.5 if row == 0 else inner.end.y - depth * 0.5
		var x := inner.end.x
		while x > inner.position.x + 8.0:
			var w := rng.randf_range(11.0, 15.5)
			var cx := x - w * 0.5
			var centre := Vector2(cx, zc)
			var ok := cx - w * 0.5 >= inner.position.x - 0.5 and macro.zone_at(Vector2(cx, zc)) == MacroMap.Zone.CITY
			for c: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2.ZERO]:
				if ok and blocks_grid(centre + Vector2(c.x * w, c.y * depth), 1.0):
					ok = false
			var kind := "house" if rng.randf() < 0.7 else ("duplex" if rng.randf() < 0.6 else "modern")
			var lot := _lot(rng, centre, w, depth, front, kind, "backfill")
			if ok:
				out.append(lot)
			x -= w
	return out
