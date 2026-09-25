class_name CivicSites
extends RefCounted
## THE table for the downtown civic set (the arena district and the civic centre): where each
## landmark stands, how big it is allowed to be, which way it faces - and where the real building
## is, in metres from a downtown origin, so a later re-layout of downtown at 1:1 (owner's long-term
## goal: real block sizes, real street layout, true distances) only has to change this table.
##
## Per landmark:
##   real       the geocoded point it stands on (a key of DowntownReal.POINTS: OSM via Nominatim,
##              by street address or place name); `latlon` is that point's latitude / longitude.
##   at         optional: where to put the site instead, in DowntownReal grid metres (u, v) - for
##              two sites sharing one block (the hotel takes the corner of Olympic and Georgia,
##              the plaza the rest), where a geocoded point is a POI inside a complex.
##   radius     flattens the city relief round it (MacroMap); kept inside the block.
##   footprint  the most ground the builder may use, metres, in the landmark's OWN frame (x = its
##              width, z = its depth); the block's pavement ring always clips it further.
##   yaw        degrees the as-built layout is turned about the site centre, in quarter turns
##              only (0, 90, 180, 270; counter-clockwise seen from above, the Godot sense). At 0
##              each faces the way `faces` says; the table's yaw turns it to face its real street
##              (`real_faces` less DowntownReal.GRID_BEARING_DEG, the grid's turn onto the axes).
##   faces      where its main front looks at yaw 0 (a note).
##   real_size  the real building's approximate footprint (metres) and height.
##   real_faces compass bearing its real main front looks toward (degrees from true north).
##   tolerance  metres the site's centre may sit from its real point (the checks): the block
##              clamps it, and a few real points are POIs inside a complex.
## Where one stands is `anchor(id)`: its real point (or `at`) through DowntownReal, at 1:1 on the
## real grid; `site()` then puts the footprint there, as far as the block lets it. Every NAME the
## game shows is invented (Minimap.LANDMARK_NAMES, the builders' *_NAME consts).

const SITES := {
	"arena": {"real": "1111_s_figueroa", "latlon": Vector2(34.0429979, -118.2671352), "radius": 44.0,
		"footprint": Vector2(240.0, 200.0), "yaw": 0, "tolerance": 60.0,
		"faces": "north-east: the marquee corner and the main doors; glass north, east and west, service side south",
		"real_size": Vector3(200.0, 45.0, 170.0), "real_faces": 45.0},
	"live_plaza": {"real": "800_w_olympic", "latlon": Vector2(34.0451075, -118.2664377), "at": Vector2(-655.0, 1004.0),
		"radius": 28.0, "footprint": Vector2(145.0, 200.0), "yaw": 0, "tolerance": 115.0,
		"faces": "south: the plaza opens to the street and the arena; theatre west, screen wall north",
		"real_size": Vector3(280.0, 30.0, 180.0), "real_faces": 216.0},
	"live_hotel": {"real": "900_w_olympic", "latlon": Vector2(34.0452979, -118.2664820), "at": Vector2(-800.0, 940.0),
		"radius": 28.0, "footprint": Vector2(90.0, 70.0), "yaw": 0, "tolerance": 90.0,
		"faces": "long faces north and south; porte-cochere east",
		"real_size": Vector3(70.0, 203.0, 35.0), "real_faces": 126.0},
	"convention_center": {"real": "1201_s_figueroa", "latlon": Vector2(34.0414677, -118.2689803), "radius": 42.0,
		"footprint": Vector2(600.0, 180.0), "yaw": 0, "tolerance": 60.0,
		"faces": "north: the pavilions and the entrance plaza face the arena",
		"real_size": Vector3(330.0, 25.0, 170.0), "real_faces": 36.0},
	"ziggurat_hall": {"real": "200_n_spring", "latlon": Vector2(34.0536961, -118.2429212), "radius": 40.0,
		"footprint": Vector2(140.0, 110.0), "yaw": 90, "tolerance": 20.0,
		"faces": "north: the portico and the steps face the park (turned west, to Spring St and the park)",
		"real_size": Vector3(140.0, 138.0, 110.0), "real_faces": 306.0},
	"civic_park": {"real": "grand_park", "latlon": Vector2(34.0555008, -118.2456965), "radius": 40.0,
		"footprint": Vector2(110.0, 500.0), "yaw": 0, "tolerance": 60.0,
		"faces": "runs north-south: the fountain terrace at the north end, city hall off its south end",
		"real_size": Vector3(500.0, 0.0, 110.0), "real_faces": 306.0},
	"concert_hall": {"real": "111_s_grand", "latlon": Vector2(34.0554291, -118.2499126), "radius": 38.0,
		"footprint": Vector2(140.0, 110.0), "yaw": 180, "tolerance": 20.0,
		"faces": "south-west: the entrance sails open over the corner (turned north-east, to 1st and Grand)",
		"real_size": Vector3(110.0, 40.0, 90.0), "real_faces": 351.0},
	"lattice_museum": {"real": "221_s_grand", "latlon": Vector2(34.0544584, -118.2505943), "radius": 30.0,
		"footprint": Vector2(80.0, 90.0), "yaw": 0, "tolerance": 25.0,
		"faces": "south: the plaza and its grove; the dimple faces east, toward the concert hall",
		"real_size": Vector3(70.0, 36.0, 60.0), "real_faces": 126.0},
	"pueblo_station": {"real": "800_n_alameda", "latlon": Vector2(34.0560576, -118.2358962), "radius": 33.0,
		"footprint": Vector2(400.0, 250.0), "yaw": 0, "tolerance": 90.0,
		"faces": "west: the forecourt, the arch and the clock tower; the platforms behind to the east",
		"real_size": Vector3(260.0, 38.0, 70.0), "real_faces": 270.0},
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
	return {"id": id, "anchor": anchor(id), "radius": s.radius, "site": "block"}


## Where a landmark is placed, world XZ: its real point through DowntownReal (or its `at`).
static func anchor(id: String) -> Vector2:
	var s: Dictionary = SITES[id]
	if s.has("at"):
		return DowntownReal.to_game(s.at)
	return real_xz(id)


## The real building's position in world XZ: its geocoded point, turned onto the grid at 1:1.
static func real_xz(id: String) -> Vector2:
	return DowntownReal.game_xz(SITES[id].latlon)


## The real building's position in metres east (x) and north (y) of DowntownReal.REAL_ORIGIN.
static func real_en(id: String) -> Vector2:
	return DowntownReal.real_en(SITES[id].latlon)


## The same point in the game's sense: x east, z south.
static func real_metres(id: String) -> Vector2:
	var en := real_en(id)
	return Vector2(en.x, -en.y)


## The real position turned onto the real street grid (x grid east, z grid south): DowntownReal.
static func real_grid(id: String) -> Vector2:
	return DowntownReal.grid_uv(real_en(id))


## Where one landmark is built: {"world": the ground it may use in world XZ (axis-aligned),
## "local": the same in its own frame, centred on the origin, "centre": world XZ, "yaw": radians,
## "y0": pavement height}. The block its anchor falls in, inside the pavement; the footprint is
## centred on the anchor as far as that block lets it (clamped in), and clipped to the block.
static func site(plan: CityPlan, id: String) -> Dictionary:
	var s: Dictionary = SITES[id]
	var block := Landmarks.site_rect(plan, anchor(id))
	var quarter := posmod(int(round(float(yaw_override.get(id, s.yaw)) / 90.0)), 4)
	var fp: Vector2 = s.footprint
	# The footprint is in the landmark's own frame; a quarter turn swaps it onto the map.
	var fp_world := Vector2(fp.y, fp.x) if quarter % 2 == 1 else fp
	var c := anchor(id)
	for axis in 2:
		if fp_world[axis] >= block.size[axis]:
			c[axis] = block.get_center()[axis]
		else:
			c[axis] = clampf(c[axis], block.position[axis] + fp_world[axis] * 0.5, block.end[axis] - fp_world[axis] * 0.5)
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
