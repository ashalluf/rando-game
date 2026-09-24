class_name DowntownReal
extends RefCounted
## DOWNTOWN LOS ANGELES AT 1:1 - a replica area (owner, 2026-09-24: "I want the whole downtown
## landscape to become a 1:1 replica ... This should be geographically sound").
##
## STATUS (2026-09-24): DATA ONLY - nothing calls this module yet. The re-lay that consumes it
## (CityPlan's pins, MacroMap, the freeways, the tower and civic tables, the checks) was written
## and probed but not run through the smoke test before the session ended; it is kept as
## tools/downtown_relay/relay.patch, and docs/HANDOFF.md (section 9p) says how to land it.
##
## The same idea as ReplicaAreas (the Esplanade): a real place rebuilt at TRUE scale from real
## references, as data, with the seeded city between replica areas. A replica area is a REAL
## ORIGIN (lat/long), a TURN (the real bearing that becomes game north) and a GAME ANCHOR (where
## the real origin stands in world XZ); every real point goes through `game_xz()`, and distances
## inside the area are true metres. What differs from the Esplanade is the shape: that one is a
## road, this one is a street GRID, so it is carried by CityPlan's pinned roads rather than a
## corridor of its own.
##
## The turn. Downtown's streets run on a grid turned 37.86 degrees east of north (fitted below),
## and CityPlan's street grid is axis-aligned - blocks, lots, lanes and the minimap all assume
## it. So the real grid is turned onto the game's axes: the avenues (Figueroa ... Main, Alameda)
## run game north-south at fixed x, the numbered streets (1st ... 9th, Olympic, Pico; Temple,
## Wilshire) east-west at fixed z. "Grid north" (up the avenues, toward 1st St) is game north.
## Everything real in the area is turned the same way, so a tower stands on its real block, at
## its real distance from its neighbours, facing its real street.
##
## THE FIT (2026-09-24). 93 Nominatim queries, strictly under one a second, every answer cached:
## 40 landmark and anchor points (towers, civic buildings, parks, interchanges) and the OSM way
## centroids of 45 named streets and 4 freeways inside a downtown box - points ON each street's
## centre line. Per street, the points where it runs on the core grid (the numbered streets bend
## at the 110, the streets east of Main fan out onto another grid), trimmed to those within 18 m
## of the street's median. The bearing that minimises the scatter: 37.86 degrees, RMS 2.0 m over
## 115 centre-line points; the avenues alone fit 37.87, the streets alone 37.80 + 90, so the grid
## is square to 0.07 degrees. Each street's position below is the mean of its trimmed points,
## with their count and RMS. Coordinates (c) OpenStreetMap contributors, ODbL (docs/ASSETS.md).
##
## Where it stands in the basin (MacroMap): Pershing Square at GAME_ANCHOR, east-north-east of
## the airport, the mountains to the north - receding in a bay above the civic centre, the way
## the real ones do north of downtown. 5th Street is exactly z = 0, because CityPlan's road 0 is
## at 0 on both axes and has to be one of the real streets.
##
## What is NOT 1:1, and why:
##   * East of Main the real streets turn onto another grid (Alameda swings 500 m across the
##     grid between Union Station and Little Tokyo). Only Alameda and Vignes are pinned there, at
##     the stretch past Union Station (so the station faces Alameda across its forecourt, where
##     it really stands); Los Angeles, San Pedro and Central are left out and Little Tokyo is
##     seeded filler east of Alameda.
##   * One road per line: a pinned road runs across the whole map. Wilshire is pinned (it is the
##     axis of MacArthur Park and of the sail tower's block) and so also splits the historic
##     core's 6th-7th blocks east of Grand, where the real one does not run. 12th St is left out:
##     west of Figueroa it does not exist and pinned it would cut the arena in two. Georgia St
##     (the back of the arena district) is pinned where it runs south of Olympic; north of Olympic
##     the real street there is Francisco St, 100 m east of it.
##   * The streets west of the 110 bend 8 degrees north. MacArthur Park is placed at its true
##     distance along Wilshire (Park View and Alvarado at their real positions), but ON the
##     straightened Wilshire, 6th and 7th - 280 m grid-north of where the real park is.
##   * Widths are approximate (typical right of way less the game's 4 m pavements), not measured.

## The real origin: Pershing Square's centroid, as geocoded (latitude, longitude).
const REAL_ORIGIN := Vector2(34.0483957, -118.2530218)
## WGS84 metres per degree at the origin's latitude.
const M_PER_DEG_LAT := 110923.3
const M_PER_DEG_LON := 92332.3
## Compass bearing of the avenues (the real grid's "north"), fitted: see THE FIT above.
const GRID_BEARING_DEG := 37.86
## World XZ of the real origin. x puts MacArthur Park (2.5 km west along Wilshire) east of the
## airport and clear of the coast towns; z puts 5th Street (grid v -102.7) exactly on z = 0.
const GAME_ANCHOR := Vector2(2800.0, 102.7)

## The area in the ReplicaAreas vocabulary (id, name, references, the frame).
const AREA := {
	"id": "downtown",
	"name": "Downtown Los Angeles",
	"references": [
		"OpenStreetMap via Nominatim: 40 landmark points and the centre-line points of 45 streets and 4 freeways (2026-09-24)",
		"Real tower heights and massing: LandmarkDowntown.TOWERS; civic buildings: CivicSites.SITES",
	],
	"real_origin": REAL_ORIGIN,
	"grid_bearing_deg": GRID_BEARING_DEG,
	"anchor": GAME_ANCHOR,
}

## The avenues, west to east: name, u (metres along the streets from the origin, grid east),
## carriageway width, the centre-line points behind the position and their RMS about it (-1:
## placed, not fitted - the street runs off the grid there and this is where it matters: see
## the header). Consecutive roads of one `run` are adjacent blocks; between runs lies seeded
## filler (inside MacArthur Park, Westlake between Alvarado and Georgia, everything east of
## Vignes).
const AVENUES := [
	# MacArthur Park's two sides, where they bound the park (the real streets are 10 degrees off
	# the grid there, so this is their position at the park's own latitude).
	{"name": "PARK VIEW ST", "u": -2700.0, "width": 16.0, "n": 2, "rms": 3.7, "run": 0},
	{"name": "ALVARADO ST", "u": -2313.0, "width": 22.0, "n": 3, "rms": -1.0, "run": 1},
	# The downtown grid.
	{"name": "GEORGIA ST", "u": -835.0, "width": 16.0, "n": 6, "rms": 12.0, "run": 2},
	{"name": "FIGUEROA ST", "u": -566.5, "width": 24.0, "n": 5, "rms": 1.2, "run": 2},
	{"name": "FLOWER ST", "u": -440.6, "width": 20.0, "n": 3, "rms": 1.2, "run": 2},
	{"name": "HOPE ST", "u": -310.9, "width": 18.0, "n": 9, "rms": 2.5, "run": 2},
	{"name": "GRAND AVE", "u": -189.2, "width": 22.0, "n": 9, "rms": 1.9, "run": 2},
	{"name": "OLIVE ST", "u": -60.4, "width": 18.0, "n": 5, "rms": 0.7, "run": 2},
	{"name": "HILL ST", "u": 64.4, "width": 20.0, "n": 8, "rms": 1.8, "run": 2},
	{"name": "BROADWAY", "u": 191.0, "width": 20.0, "n": 9, "rms": 3.2, "run": 2},
	{"name": "SPRING ST", "u": 313.0, "width": 18.0, "n": 13, "rms": 0.7, "run": 2},
	{"name": "MAIN ST", "u": 435.7, "width": 18.0, "n": 5, "rms": 2.5, "run": 2},
	# Where Alameda passes Union Station's forecourt, and Vignes behind the platforms.
	{"name": "ALAMEDA ST", "u": 590.0, "width": 24.0, "n": 3, "rms": -1.0, "run": 2},
	{"name": "VIGNES ST", "u": 1117.0, "width": 16.0, "n": 2, "rms": -1.0, "run": 2},
]

## The streets, north to south: name, v (metres along the avenues from the origin, grid SOUTH,
## i.e. game +Z), width, points, RMS (-1 as above). One run: no seeded road between any two.
const STREETS := [
	# North of Union Station (the eastern stretch; west of Main the real street is 200 m south).
	{"name": "CESAR CHAVEZ AVE", "v": -1829.0, "width": 20.0, "n": 3, "rms": -1.0},
	{"name": "ARCADIA ST", "v": -1377.5, "width": 16.0, "n": 2, "rms": 1.5},
	{"name": "TEMPLE ST", "v": -1193.2, "width": 20.0, "n": 4, "rms": 8.5},
	{"name": "1ST ST", "v": -879.5, "width": 20.0, "n": 7, "rms": 0.2},
	{"name": "2ND ST", "v": -715.5, "width": 18.0, "n": 11, "rms": 3.9},
	{"name": "3RD ST", "v": -506.1, "width": 20.0, "n": 2, "rms": 2.2},
	{"name": "4TH ST", "v": -305.2, "width": 18.0, "n": 6, "rms": 0.9},
	{"name": "5TH ST", "v": -102.7, "width": 20.0, "n": 6, "rms": 2.5},
	{"name": "6TH ST", "v": 97.5, "width": 20.0, "n": 5, "rms": 1.3},
	{"name": "WILSHIRE BLVD", "v": 210.0, "width": 24.0, "n": 3, "rms": -1.0},
	{"name": "7TH ST", "v": 301.3, "width": 20.0, "n": 2, "rms": 1.6},
	{"name": "8TH ST", "v": 501.7, "width": 18.0, "n": 3, "rms": 0.1},
	{"name": "9TH ST", "v": 704.2, "width": 18.0, "n": 4, "rms": 0.3},
	{"name": "OLYMPIC BLVD", "v": 903.1, "width": 24.0, "n": 4, "rms": 2.4},
	{"name": "11TH ST", "v": 1105.7, "width": 18.0, "n": 8, "rms": 0.9},
	{"name": "PICO BLVD", "v": 1459.9, "width": 22.0, "n": 3, "rms": 2.5},
	{"name": "VENICE BLVD", "v": 1897.0, "width": 22.0, "n": 3, "rms": -1.0},
]

## Geocoded points (latitude, longitude): OSM building or POI centroids, found by street
## address or place name. The keys are neutral: which real building a tower stands for is in
## LandmarkDowntown.TOWERS by id, never by name.
const POINTS := {
	"pershing_square": Vector2(34.0483957, -118.2530218),
	"900_wilshire": Vector2(34.0501526, -118.2603791),
	"404_s_figueroa": Vector2(34.0527673, -118.2558460),
	"515_s_flower": Vector2(34.0515462, -118.2569516),
	"555_s_flower": Vector2(34.0508088, -118.2576412),
	"601_s_figueroa": Vector2(34.0507779, -118.2593021),
	"725_s_figueroa": Vector2(34.0487308, -118.2611292),
	"777_s_figueroa": Vector2(34.0484829, -118.2614352),
	"333_s_hope": Vector2(34.0536175, -118.2532727),
	"444_s_flower": Vector2(34.0512400, -118.2552210),
	"707_wilshire": Vector2(34.0492822, -118.2569630),
	"333_s_grand": Vector2(34.0527460, -118.2519538),
	"355_s_grand": Vector2(34.0522001, -118.2527889),
	"633_w_5th": Vector2(34.0510635, -118.2544231),
	"350_s_grand": Vector2(34.0514466, -118.2516519),
	"300_s_grand": Vector2(34.0522505, -118.2514130),
	"555_w_5th": Vector2(34.0501156, -118.2531327),
	"1101_s_flower": Vector2(34.0426001, -118.2653388),
	"francisco_st_tower": Vector2(34.0481298, -118.2637375),
	"1200_s_figueroa": Vector2(34.0410945, -118.2665426),
	"1120_s_grand": Vector2(34.0403207, -118.2626490),
	"770_s_grand": Vector2(34.0461113, -118.2568501),
	"1111_s_figueroa": Vector2(34.0429979, -118.2671352),
	"800_w_olympic": Vector2(34.0451075, -118.2664377),
	"900_w_olympic": Vector2(34.0452979, -118.2664820),
	"1201_s_figueroa": Vector2(34.0414677, -118.2689803),
	"200_n_spring": Vector2(34.0536961, -118.2429212),
	"grand_park": Vector2(34.0555008, -118.2456965),
	"111_s_grand": Vector2(34.0554291, -118.2499126),
	"221_s_grand": Vector2(34.0544584, -118.2505943),
	"800_n_alameda": Vector2(34.0560576, -118.2358962),
	"macarthur_park": Vector2(34.0588418, -118.2776964),
	"630_w_5th": Vector2(34.0508201, -118.2554523),
	"317_s_broadway": Vector2(34.0507342, -118.2487992),
	"135_n_grand": Vector2(34.0566135, -118.2489220),
	"555_w_temple": Vector2(34.0580666, -118.2455356),
	"100_n_central": Vector2(34.0496133, -118.2386120),
	"1000_vin_scully": Vector2(34.0736255, -118.2398452),
	"four_level_interchange": Vector2(34.0626710, -118.2488172),
}

## The freeways round the area, in grid metres (u, v), from the geocoded motorway points
## (a straight run between them where there were none). The 110 runs down the west edge from
## the four-level interchange with the 101 to the 10; the 101 along the north edge past the
## civic centre and west-south-west to the pass (where the real one really is heading: its
## geocoded point at u -2044 lands on the game's pass); the 10 across the south, 2.3 km below
## Pershing Square.
const FREEWAY_110 := [Vector2(-642.6, -1718.4), Vector2(-666.4, -1488.0), Vector2(-886.2, 538.3),
	Vector2(-911.9, 626.8), Vector2(-943.2, 735.1), Vector2(-1016.5, 998.0), Vector2(-1089.0, 1530.3),
	Vector2(-1074.6, 1615.2), Vector2(-594.0, 2547.0), Vector2(-412.0, 2897.0)]
const FREEWAY_101 := [Vector2(1500.0, -1335.0), Vector2(600.0, -1330.0), Vector2(-300.0, -1335.0),
	Vector2(-560.0, -1440.0), Vector2(-666.4, -1488.0), Vector2(-805.3, -1514.3),
	Vector2(-2044.4, -1391.7)]
## (The 10's line runs on from u 2150 to the geocoded points at u 2416-2685, where it curves north
## to the East LA interchange; here that is the east range's flank, so it stops short.)
const FREEWAY_10 := [Vector2(-594.0, 2547.0), Vector2(1000.0, 2048.0), Vector2(2150.0, 1688.0)]

## The replica's extent in grid metres: the 110 to Vignes, Cesar Chavez to Venice.
const EXTENT := Rect2(-1150.0, -1850.0, 2300.0, 3770.0)
## The financial core and South Park, where the towers are (grid metres): Bunker Hill and the
## Financial District from the 110 to Grand/Olive, 2nd to 9th; South Park Figueroa to Olive,
## 9th to Pico. The skyline boost is 1 inside (the tall infill). The historic core east of
## Olive, the civic centre and the east side stay lower - the real 12-storey limit of 1911-57
## still reads in them.
const CORE := [Rect2(-900.0, -720.0, 840.0, 1430.0), Rect2(-900.0, 700.0, 900.0, 770.0)]
## Real parks and plazas on the grid: blocks whose centre is inside one are that kind, not
## buildings (Pershing Square; Grand Hope Park).
const PARKS := [
	{"rect": Rect2(-60.4, -102.7, 124.8, 200.2), "kind": "plaza"},
	{"rect": Rect2(-310.9, 704.2, 121.7, 198.9), "kind": "park"},
	# Grand Park east of the civic landmark's own block, down to city hall's steps.
	{"rect": Rect2(64.4, -1193.2, 248.6, 313.7), "kind": "park"},
]
## MacArthur Park, on the straightened Wilshire (see the header): its sides and the streets that
## bound it, in grid metres.
const MACARTHUR := {"west_u": -2700.0, "east_u": -2313.0, "north_v": 97.5, "south_v": 301.3,
	"wilshire_v": 210.0, "real": "macarthur_park"}


# --- The frame -----------------------------------------------------------------------------------

## Metres east and north of the real origin (a local equirectangular projection; within the
## area's 4 km it is good to a few centimetres).
static func real_en(latlon: Vector2) -> Vector2:
	return Vector2((latlon.y - REAL_ORIGIN.y) * M_PER_DEG_LON, (latlon.x - REAL_ORIGIN.x) * M_PER_DEG_LAT)


## East/north metres turned into grid metres: u along the streets (grid east), v along the
## avenues toward the higher street numbers (grid SOUTH, the game's +Z).
static func grid_uv(en: Vector2) -> Vector2:
	var b := deg_to_rad(GRID_BEARING_DEG)
	var grid_north := Vector2(sin(b), cos(b))
	var grid_east := Vector2(cos(b), -sin(b))
	return Vector2(en.dot(grid_east), -en.dot(grid_north))


static func uv_to_en(uv: Vector2) -> Vector2:
	var b := deg_to_rad(GRID_BEARING_DEG)
	return Vector2(cos(b), -sin(b)) * uv.x - Vector2(sin(b), cos(b)) * uv.y


## Grid metres to world XZ and back: the turn is already in u/v, so this is only the anchor.
static func to_game(uv: Vector2) -> Vector2:
	return GAME_ANCHOR + uv


static func to_grid(xz: Vector2) -> Vector2:
	return xz - GAME_ANCHOR


## World XZ of a real latitude / longitude.
static func game_xz(latlon: Vector2) -> Vector2:
	return to_game(grid_uv(real_en(latlon)))


## World XZ of one of POINTS.
static func point(key: String) -> Vector2:
	return game_xz(POINTS[key])


## A real compass bearing, as the game bearing it has after the turn (degrees, 0 = game north).
static func game_bearing(real_bearing_deg: float) -> float:
	return fposmod(real_bearing_deg - GRID_BEARING_DEG, 360.0)


## The replica's extent (and its core rects) in world XZ.
static func game_extent() -> Rect2:
	return Rect2(to_game(EXTENT.position), EXTENT.size)


static func game_core() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r: Rect2 in CORE:
		out.append(Rect2(to_game(r.position), r.size))
	return out


static func in_extent(xz: Vector2, margin: float = 0.0) -> bool:
	return game_extent().grow(margin).has_point(xz)


# --- The grid, as CityPlan pins it ----------------------------------------------------------------

## The pinned roads per axis for CityPlan: [world position, width, name, run] sorted along the
## axis (AXIS_X: the avenues at their x, AXIS_Z: the streets at their z).
static var _pins: Array = []


static func pins() -> Array:
	if _pins.is_empty():
		var xs: Array = []
		for a: Dictionary in AVENUES:
			xs.append([GAME_ANCHOR.x + float(a.u), float(a.width), str(a.name), int(a.run)])
		var zs: Array = []
		for s: Dictionary in STREETS:
			var z := GAME_ANCHOR.y + float(s.v)
			# 5th St is road 0, which CityPlan keeps at exactly 0: 102.7 - 102.7 in float32 is not.
			zs.append([0.0 if absf(z) < 0.001 else z, float(s.width), str(s.name), 0])
		_pins = [xs, zs]
	return _pins


## The pinned road at world coordinate `at` on `axis` (within 1 cm), or [].
static func pin_at(axis: int, at: float) -> Array:
	for pin: Array in pins()[axis]:
		if absf(float(pin[0]) - at) < 0.01:
			return pin
	return []


## The pinned road on `axis` with this name (case-insensitive), or [].
static func named(axis: int, road_name: String) -> Array:
	for pin: Array in pins()[axis]:
		if str(pin[2]).to_upper() == road_name.to_upper():
			return pin
	return []


## The real kind of the block centred at `centre` (world XZ): "plaza", "park", or "" for the
## seeded roll (buildings in the replica, whatever the district says elsewhere).
static func block_kind(centre: Vector2) -> String:
	var g := to_grid(centre)
	for p: Dictionary in PARKS:
		if (p.rect as Rect2).has_point(g):
			return str(p.kind)
	return ""


## The pinned block holding world XZ `at`, inside `pavement` metres of pavement. On an axis where
## `at` is not between two real streets of one run the rect has zero size there (no clamp).
static func block_inner(at: Vector2, pavement: float) -> Rect2:
	var lo := at
	var hi := at
	for axis in 2:
		var list: Array = pins()[axis]
		var v: float = at[axis]
		for k in list.size() - 1:
			var a: Array = list[k]
			var b: Array = list[k + 1]
			if float(a[0]) <= v and v < float(b[0]) and int(a[3]) == int(b[3]):
				lo[axis] = float(a[0]) + float(a[1]) * 0.5 + pavement
				hi[axis] = float(b[0]) - float(b[1]) * 0.5 - pavement
				break
	return Rect2(lo, hi - lo)


## A freeway alignment in world XZ.
static func freeway(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(to_game(p))
	return out


## Real distance in metres between two POINTS (the smoke test's anchor distances).
static func real_distance(a: String, b: String) -> float:
	return real_en(POINTS[a]).distance_to(real_en(POINTS[b]))
