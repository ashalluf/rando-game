class_name CivicSites
extends RefCounted
## THE table for the downtown civic set (the arena district and the civic centre): where each
## landmark stands, how big it is allowed to be, which way it faces - and where the real building
## is, in metres from a downtown origin, so a later re-layout of downtown at 1:1 (owner's long-term
## goal: real block sizes, real street layout, true distances) only has to change this table.
##
## Per landmark:
##   anchor     game world XZ that picks the block (the block centre for the default seed, 1337).
##   radius     flattens the city relief round it (MacroMap); kept inside the block.
##   footprint  the most ground the builder may use, metres, in the landmark's OWN frame (x = its
##              width, z = its depth; the block's pavement ring always clips it further). Today
##              every one is bigger than its block, so the block decides; at 1:1 set the real
##              footprint and give it a block that size.
##   yaw        degrees the as-built layout is turned about the site centre, in quarter turns
##              only (0, 90, 180, 270; counter-clockwise seen from above, the Godot sense). At 0
##              each faces the way `faces` says.
##   faces      where its main front looks at yaw 0 (a note, for whoever re-lays it).
##   latlon     the real building's approximate latitude / longitude (degrees).
##   real_size  the real building's approximate footprint (metres) and height.
##   real_faces compass bearing its real main front looks toward (degrees from true north).
## The real position in metres is `real_metres(id)`: from latlon, east = +x, SOUTH = +z (the
## game's convention: north is -Z), relative to ORIGIN_LATLON. Downtown's real street grid is
## turned about REAL_GRID_BEARING degrees from true north (Spring, Broadway, Hill... run on it),
## which a 1:1 re-layout on the game's axis-aligned grid will have to decide what to do with.
##
## Everything here is approximate - read off public maps, not surveyed - and every NAME the game
## shows is invented (Minimap.LANDMARK_NAMES, the builders' *_NAME consts).

## Pershing Square, the middle of the downtown grid.
const ORIGIN_LATLON := Vector2(34.0484, -118.2513)
const REAL_GRID_BEARING := 36.0
const METRES_PER_DEG_LAT := 110574.0
## At the origin's latitude (111 320 x cos 34.05 degrees).
const METRES_PER_DEG_LON := 92240.0

const SITES := {
	"arena": {"anchor": Vector2(352.2, 474.55), "radius": 44.0, "footprint": Vector2(240.0, 200.0), "yaw": 0,
		"faces": "north-east: the marquee corner and the main doors; glass north, east and west, service side south",
		"latlon": Vector2(34.0430, -118.2673), "real_size": Vector3(200.0, 45.0, 170.0), "real_faces": 45.0},
	"live_plaza": {"anchor": Vector2(352.2, 377.7), "radius": 28.0, "footprint": Vector2(300.0, 200.0), "yaw": 0,
		"faces": "south: the plaza opens to the street and the arena; theatre west, screen wall north",
		"latlon": Vector2(34.0446, -118.2665), "real_size": Vector3(280.0, 30.0, 180.0), "real_faces": 216.0},
	"live_hotel": {"anchor": Vector2(456.1, 377.7), "radius": 28.0, "footprint": Vector2(90.0, 70.0), "yaw": 0,
		"faces": "long faces north and south; porte-cochere east",
		"latlon": Vector2(34.0452, -118.2657), "real_size": Vector3(70.0, 203.0, 35.0), "real_faces": 126.0},
	"convention_center": {"anchor": Vector2(352.2, 595.65), "radius": 42.0, "footprint": Vector2(600.0, 300.0), "yaw": 0,
		"faces": "north: the pavilions and the entrance plaza face the arena",
		"latlon": Vector2(34.0400, -118.2685), "real_size": Vector3(330.0, 25.0, 170.0), "real_faces": 36.0},
	"ziggurat_hall": {"anchor": Vector2(875.9, 170.75), "radius": 40.0, "footprint": Vector2(140.0, 110.0), "yaw": 0,
		"faces": "north: the portico and the steps face the park",
		"latlon": Vector2(34.0537, -118.2427), "real_size": Vector3(140.0, 138.0, 110.0), "real_faces": 306.0},
	"civic_park": {"anchor": Vector2(875.9, 59.05), "radius": 40.0, "footprint": Vector2(110.0, 500.0), "yaw": 0,
		"faces": "runs north-south: the fountain terrace at the north end, city hall off its south end",
		"latlon": Vector2(34.0560, -118.2460), "real_size": Vector3(500.0, 0.0, 110.0), "real_faces": 306.0},
	"concert_hall": {"anchor": Vector2(875.9, -49.55), "radius": 38.0, "footprint": Vector2(140.0, 110.0), "yaw": 0,
		"faces": "south-west: the entrance sails open over the corner facing the park and downtown",
		"latlon": Vector2(34.0553, -118.2498), "real_size": Vector3(110.0, 40.0, 90.0), "real_faces": 351.0},
	"lattice_museum": {"anchor": Vector2(782.05, -49.55), "radius": 30.0, "footprint": Vector2(80.0, 90.0), "yaw": 0,
		"faces": "south: the plaza and its grove; the dimple faces east, toward the concert hall",
		"latlon": Vector2(34.0544, -118.2502), "real_size": Vector3(70.0, 36.0, 60.0), "real_faces": 126.0},
	"pueblo_station": {"anchor": Vector2(1091.15, -49.55), "radius": 33.0, "footprint": Vector2(400.0, 250.0), "yaw": 0,
		"faces": "west: the forecourt, the arch and the clock tower; the platforms behind to the east",
		"latlon": Vector2(34.0562, -118.2365), "real_size": Vector3(260.0, 38.0, 70.0), "real_faces": 270.0},
}

## Yaw by id, in degrees, overriding the table (the smoke test turns a landmark to prove the turn
## works; a quick A/B of an orientation needs no edit to SITES).
static var yaw_override: Dictionary = {}

## The ids in the order Landmarks.all() lists them.
const ORDER := ["arena", "live_plaza", "live_hotel", "convention_center",
	"ziggurat_hall", "civic_park", "concert_hall", "lattice_museum", "pueblo_station"]


## The Landmarks.all() entry for one site.
static func entry(id: String) -> Dictionary:
	var s: Dictionary = SITES[id]
	return {"id": id, "anchor": s.anchor, "radius": s.radius, "site": "block"}


## The real building's position in metres from ORIGIN_LATLON: x east, z south.
static func real_metres(id: String) -> Vector2:
	var ll: Vector2 = SITES[id].latlon
	return Vector2((ll.y - ORIGIN_LATLON.y) * METRES_PER_DEG_LON, -(ll.x - ORIGIN_LATLON.x) * METRES_PER_DEG_LAT)


## Where one landmark is built: {"world": the ground it may use in world XZ (axis-aligned),
## "local": the same in its own frame, centred on the origin, "centre": world XZ, "yaw": radians,
## "y0": pavement height}. The block its anchor falls in, inside the pavement, clipped to the
## table's footprint.
static func site(plan: CityPlan, id: String) -> Dictionary:
	var s: Dictionary = SITES[id]
	var block := Landmarks.site_rect(plan, s.anchor)
	var quarter := posmod(int(round(float(yaw_override.get(id, s.yaw)) / 90.0)), 4)
	var fp: Vector2 = s.footprint
	# The footprint is in the landmark's own frame; a quarter turn swaps it onto the map.
	var fp_world := Vector2(fp.y, fp.x) if quarter % 2 == 1 else fp
	var c := block.get_center()
	var world := block.intersection(Rect2(c - fp_world * 0.5, fp_world))
	c = world.get_center()
	var local_size := Vector2(world.size.y, world.size.x) if quarter % 2 == 1 else world.size
	return {"world": world, "local": Rect2(-local_size * 0.5, local_size), "centre": c,
		"yaw": float(quarter) * PI * 0.5, "y0": LandmarkArenaDistrict.ground(plan, world)}


## A point in a landmark's own frame to world XZ (the frame is centred on its site, turned by yaw).
static func to_world(info: Dictionary, p: Vector2) -> Vector2:
	var yaw: float = info.yaw
	# Godot's +yaw about UP takes local +X to (cos, -sin) in (x, z).
	return (info.centre as Vector2) + Vector2(p.x * cos(yaw) + p.y * sin(yaw), -p.x * sin(yaw) + p.y * cos(yaw))


## An axis-aligned rect in a landmark's own frame to the world (exact for quarter turns).
static func rect_to_world(info: Dictionary, r: Rect2) -> Rect2:
	var a := to_world(info, r.position)
	var b := to_world(info, r.end)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())


## The build a landmark is in the middle of, for the few things that need the world: the chunk
## (its grass), whether this is the detailed copy (occluders, lights). Set by build().
static var ctx: Dictionary = {}


## Builds one civic landmark: a pivot at its site centre turned by its yaw, its own static body
## (so a turned landmark's shapes turn with it), and the builder working in the local frame.
static func build(id: String, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var info := site(plan, id)
	var pivot := Node3D.new()
	pivot.name = "Civic_" + id
	pivot.position = Vector3((info.centre as Vector2).x, 0.0, (info.centre as Vector2).y)
	pivot.rotation.y = info.yaw
	parent.add_child(pivot)
	var body: StaticBody3D = null
	if statics:
		body = StaticBody3D.new()
		body.name = "CivicBody"
		body.collision_layer = 1
		body.collision_mask = 0
		pivot.add_child(body)
	ctx = {"id": id, "info": info, "chunk": parent if parent is CityChunk else null, "detailed": detailed and statics != null}
	match id:
		"arena", "live_plaza", "live_hotel", "convention_center":
			LandmarkArenaDistrict.build(id, info.local, info.y0, pivot, body, detailed)
		_:
			LandmarkCivicCenter.build(id, info.local, info.y0, pivot, body, detailed)
	ctx = {}


## The crowds a landmark wants, in world rects (see Landmarks.crowds()).
static func crowds(id: String, plan: CityPlan) -> Array:
	var info := site(plan, id)
	var local: Array
	match id:
		"arena", "live_plaza", "live_hotel", "convention_center":
			local = LandmarkArenaDistrict.crowds(id, info.local)
		_:
			local = LandmarkCivicCenter.crowds(id, info.local)
	var out := []
	for c: Array in local:
		out.append([rect_to_world(info, c[0]), c[1], c[2]])
	return out
