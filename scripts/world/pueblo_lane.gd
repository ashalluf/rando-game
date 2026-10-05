class_name PuebloLane
extends RefCounted
## The historic Mexican marketplace lane by Pueblo Station: PASEO DE LAS GOLONDRINAS (an invented
## name; the FORM of the real lane and plaza across Alameda from Union Station). A civic site
## (CivicSites.SITES "pueblo_lane"): it takes the whole block between Main and Alameda, Arcadia and
## Cesar Chavez, and lays out, in its own frame (x east, z south, yaw 0):
##
##   * the PLAZA (PLAZA VIEJA) on the real plaza's point: terracotta tiles in a brick ring, a ring
##     of shade trees with ring benches, lamps, an octagonal KIOSK bandstand in the middle (stucco
##     base and steps, slender iron columns, a balustrade, an arched frieze, a bell-cast roof with a
##     lantern and a finial), and papel picado strung from the kiosk's eave to poles round the edge;
##   * the LANE north from the plaza's north side, brick-paved, under a timber PERGOLA of grape and
##     wisteria (ClimbingPlants' atlas and shader), with two rows of PUESTOS back to back down its
##     middle (PuebloMarket: stalls, goods, awnings), papel picado and bulb strings across it, and
##     a large timber cross at its south entrance (the real lane has one);
##   * the buildings along it, one- and two-storey: the ADOBE house (whitewashed, thick-walled,
##     vigas, a corredor of posts under a tiled roof), stucco and brick shops with arched openings,
##     shop windows lit inside after dark, iron balconies, tiled eaves, wall lanterns;
##   * the CHURCH (IGLESIA DE LA PALOMA, invented) south-west of the plaza, facing it: a stucco
##     nave under clay tiles, buttresses, a bell gable with three bells over an arched door - a
##     SANCTUARY (Sanctuary: no shooting at or into it);
##   * the old firehouse east of the plaza, a three-storey hotel block south of it, gardens, the
##     adobe's courtyard and surface car parks filling the rest of the block.
##
## Real place relative to the station: the real plaza is 245 m grid-west and 25 m grid-north of the
## station's point, and so is this one (to within the block: CivicSites tolerance). The real
## church stands across Main; here it stands inside the block on the plaza's south-west side.
## Everything is laid out by `layout()` (pure, from the site rect and the kiosk's real point), so
## the checks and the people ask the same question the build does. Every roll is a hash of
## SEED_BASE and a place, never an rng that outlives one piece.

const ID := "pueblo_lane"
const NAME := "PASEO DE LAS GOLONDRINAS"
const PLAZA_NAME := "PLAZA VIEJA"
const CHURCH_NAME := "IGLESIA DE LA PALOMA"
const SEED_BASE := 52013

## PUEBLO_LANE=0 in the environment leaves the block to the seeded city (the A/B).
static var enabled: bool = OS.get_environment("PUEBLO_LANE") != "0"

## The real plaza's centre (the kiosk), latitude / longitude.
const KIOSK_LATLON := Vector2(34.05722, -118.23816)

## The plaza: half its size (m), the kiosk's radius, the ring of trees.
const PLAZA_HALF := 26.0
const KIOSK_R := 5.2
const KIOSK_DECK := 1.1
const KIOSK_COLS := 3.5
const TREE_RING := 12.5
## The lane: half the width between the building fronts, its length north of the plaza.
const LANE_HALF := 6.5
const LANE_LEN := 118.0
## The pergola over it: post height and spacing, beam spacing.
const PERGOLA_H := 4.6
const PERGOLA_PITCH := 4.0
## The east row's depth (the west row runs back to the block's edge).
const EAST_ROW := 16.0
## The church: width, length, eave height.
const CHURCH_W := 15.0
const CHURCH_L := 38.0
const CHURCH_H := 11.0
## Stall rows: a gap every this many stalls (a way across the lane).
const STALLS_PER_RUN := 5
const STALL_GAP := 2.6
## Vendors: one at every n-th stall.
const VENDOR_EVERY := 4

## Stucco tints the lane's buildings wear (vertex colour, multiplied into the facade's own).
const STUCCO_TINTS := [Color(1.0, 0.97, 0.9), Color(1.0, 0.86, 0.66), Color(0.98, 0.78, 0.7),
	Color(0.84, 0.9, 0.92), Color(0.92, 0.95, 0.82), Color(1.0, 0.92, 0.78), Color(0.95, 0.72, 0.55)]

enum Kind { ADOBE, STUCCO1, STUCCO2, BRICK2 }


# --- Layout (pure) -------------------------------------------------------------------------------------

## The kiosk's real point in a site's own frame.
static func kiosk_local(info: Dictionary) -> Vector2:
	var real := DowntownReal.game_xz(KIOSK_LATLON)
	var d := real - (info.centre as Vector2)
	var yaw: float = info.yaw
	# Inverse of CivicSites.to_world()'s turn.
	return Vector2(d.x * cos(yaw) - d.y * sin(yaw), d.x * sin(yaw) + d.y * cos(yaw))


## Everything's place in the site's own frame: rects for the plaza, the lane, the rows, the
## church, the firehouse, the hotel, the gardens and the car parks; the kiosk's centre; the
## building segments along the lane; the stall frames. `s` the site's local rect.
static func layout(s: Rect2, k: Vector2) -> Dictionary:
	var px := clampf(k.x, s.position.x + LANE_HALF + 22.0, s.end.x - LANE_HALF - EAST_ROW - 40.0)
	var pz := clampf(k.y, s.position.y + LANE_LEN + PLAZA_HALF + 30.0, s.end.y - PLAZA_HALF - 80.0)
	var p := Vector2(px, pz)
	var plaza := Rect2(p - Vector2(PLAZA_HALF, PLAZA_HALF), Vector2(PLAZA_HALF, PLAZA_HALF) * 2.0)
	var lane_z1 := plaza.position.y
	var lane_z0 := maxf(s.position.y + 30.0, lane_z1 - LANE_LEN)
	var lane := Rect2(px - LANE_HALF, lane_z0, LANE_HALF * 2.0, lane_z1 - lane_z0)
	var west := Rect2(s.position.x, lane_z0, lane.position.x - s.position.x, lane.size.y)
	var east := Rect2(lane.end.x, lane_z0, EAST_ROW, lane.size.y)
	var north := Rect2(s.position.x, s.position.y, s.size.x, lane_z0 - s.position.y)
	# The church: south-west of the kiosk, its front on the plaza's south edge, facing north.
	var church := Rect2(Vector2(px - 21.0, plaza.end.y + 5.0), Vector2(CHURCH_W, CHURCH_L))
	# The firehouse on the plaza's east side, facing west to it; the hotel block south of the
	# plaza east of the church, facing north.
	var fire := Rect2(Vector2(plaza.end.x + 4.0, pz - 10.0), Vector2(16.0, 20.0))
	var hotel := Rect2(Vector2(church.end.x + 6.0, plaza.end.y + 5.0), Vector2(minf(48.0, s.end.x - church.end.x - 8.0), 26.0))
	# The adobe's courtyard behind the east row, a car park beyond it to Alameda.
	var court := Rect2(Vector2(east.end.x, lane_z0 + lane.size.y * 0.35), Vector2(16.0, lane.size.y * 0.4))
	var east_lot := Rect2(Vector2(east.end.x + 18.0, lane_z0 + 2.0), Vector2(s.end.x - east.end.x - 19.0, plaza.position.y - lane_z0 - 6.0))
	# Another east of the firehouse and the hotel, down to the south zone.
	var south_z := maxf(church.end.y, hotel.end.y) + 6.0
	var south := Rect2(Vector2(s.position.x, south_z), Vector2(s.size.x, s.end.y - south_z))
	var garden := Rect2(south.position + Vector2(2.0, 2.0), Vector2(south.size.x * 0.42, south.size.y - 4.0))
	var south_lot := Rect2(Vector2(garden.end.x + 4.0, south.position.y + 2.0), Vector2(s.end.x - garden.end.x - 5.0, south.size.y - 4.0))
	var x2 := maxf(fire.end.x, hotel.end.x) + 4.0
	var east_lot2 := Rect2(Vector2(x2, plaza.position.y), Vector2(s.end.x - x2 - 1.0, south.position.y - plaza.position.y - 2.0))
	# Building segments along the lane: [z0, z1, kind, storeys, tint index, side (+1 west row
	# facing east, -1 east row facing west)]. The adobe is the east row's middle segment.
	var segs: Array = []
	for side: int in [1, -1]:
		var z := lane_z0
		var i := 0
		while z < lane_z1 - 4.0:
			var length := 10.0 + 10.0 * h01([SEED_BASE, "seg", side, i])
			var z1 := minf(z + length, lane_z1)
			if lane_z1 - z1 < 7.0:
				z1 = lane_z1
			var kind: int
			var adobe_mid := lane_z0 + lane.size.y * 0.55
			if side < 0 and z <= adobe_mid and adobe_mid < z1:
				kind = Kind.ADOBE
			else:
				var r := h01([SEED_BASE, "kind", side, i])
				kind = Kind.STUCCO1 if r < 0.3 else (Kind.STUCCO2 if r < 0.72 else Kind.BRICK2)
			var storeys := 1 if kind == Kind.ADOBE or kind == Kind.STUCCO1 else 2
			segs.append([z, z1, kind, storeys, hash([SEED_BASE, "tint", side, i]) % STUCCO_TINTS.size(), side])
			z = z1
			i += 1
	# Stall frames: two rows back to back down the lane's middle, gaps to cross.
	var stalls: Array = []
	var sz0 := lane_z0 + 6.0
	var sz1 := lane_z1 - 7.0
	for side: int in [1, -1]:
		var z := sz0
		var n := 0
		while z + PuebloMarket.STALL_W <= sz1:
			var zc := z + PuebloMarket.STALL_W * 0.5
			# Frame: origin at the front's middle on the ground, +Z out over the aisle.
			var out := Vector3(float(side), 0.0, 0.0)
			var bas := Basis.looking_at(-out, Vector3.UP)
			var org := Vector3(px + float(side) * (PuebloMarket.STALL_D + 0.05), 0.0, zc)
			var id := stalls.size()
			stalls.append({"xf": Transform3D(bas, org), "goods": hash([SEED_BASE, "goods", side, n]) % PuebloMarket.GOODS_COUNT,
				"seed": hash([SEED_BASE, "stall", side, n]), "side": side, "id": id})
			n += 1
			z += PuebloMarket.STALL_W
			if n % STALLS_PER_RUN == 0:
				z += STALL_GAP
	return {"p": p, "plaza": plaza, "lane": lane, "west": west, "east": east, "north": north, "church": church,
		"fire": fire, "hotel": hotel, "court": court, "east_lot": east_lot, "south": south, "garden": garden,
		"south_lot": south_lot, "east_lot2": east_lot2, "segs": segs, "stalls": stalls, "site": s}


static func h01(parts: Array) -> float:
	return PuebloMarket.h01(parts)


# --- Crowds and people -----------------------------------------------------------------------------------

## The crowds the chunk spawns, in the site's own frame: the lane's two aisles (one ring round the
## stall rows), the plaza's ring round the trees, the garden.
static func crowds(info: Dictionary) -> Array:
	var L := layout(info.local, kiosk_local(info))
	var lane: Rect2 = L.lane
	var plaza: Rect2 = L.plaza
	var garden: Rect2 = L.garden
	var out := [[lane.grow_individual(0.0, -1.0, 0.0, -1.0), 2.0, 18], [plaza.grow(-3.0), 5.0, 12]]
	if garden.size.x > 12.0 and garden.size.y > 12.0:
		out.append([garden.grow(-2.0), 3.0, 4])
	return out


## Build steps for the stall vendors (Landmarks.people_steps()): every VENDOR_EVERY-th stall's
## seller standing inside it, and two queue spots in front of each (CityChunk meta
## "vendor_queue", the walkers' life layer fills them).
static func people_steps(lm: Dictionary, chunk: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	if chunk == null or chunk.plan == null:
		return steps
	var info := CivicSites.site(chunk.plan, ID)
	var L := layout(info.local, kiosk_local(info))
	var queue: Array = chunk.get_meta("vendor_queue", [])
	var block_rect: Rect2 = chunk.plan.block(chunk.ix, chunk.iz).rect
	for st: Dictionary in L.stalls:
		var xf: Transform3D = st.xf
		var out3 := xf.basis * Vector3(0, 0, 1)
		var out := CivicSites.to_world(info, Vector2(out3.x, out3.z)) - CivicSites.to_world(info, Vector2.ZERO)
		var to := -out
		var record := {"dead": false}
		for k in 2:
			var q3 := xf * Vector3(-0.55 + 1.1 * float(k), 0.0, 0.95)
			queue.append({"p": CivicSites.to_world(info, Vector2(q3.x, q3.z)), "yaw": atan2(-to.x, -to.y), "taken": null, "record": record})
		if int(st.id) % VENDOR_EVERY != 1:
			continue
		var home3 := xf * Vector3(0.0, 0.0, -1.2)
		var home := CivicSites.to_world(info, Vector2(home3.x, home3.z))
		var yaw := atan2(-out.x, -out.y)
		var sd := hash([chunk.plan.seed, ID, "vendor", st.id])
		var y := float(info.y0) + 0.06
		steps.append(func() -> void: _spawn_vendor(chunk, block_rect, sd, home, yaw, y))
	chunk.set_meta("vendor_queue", queue)
	return steps


static func _spawn_vendor(chunk: CityChunk, block_rect: Rect2, sd: int, at: Vector2, yaw: float, y: float) -> void:
	if not is_instance_valid(chunk) or not chunk._take_crowd_room():
		return
	var ped := StreetVendor.new()
	ped.setup_vendor(block_rect, sd, at, yaw, false, 0.0)
	ped.position = Vector3(at.x, y + 0.05, at.y)
	chunk.add_child(ped)


# --- Build ------------------------------------------------------------------------------------------

## Built sites by (local rect, ground height, near / far): a holder of the nodes and a body of the
## shapes, out of the tree. Building the near site is ~0.7 s of GDScript (the stalls' and the
## vines' geometry), so it is built once - when the far copy is built at load - and every chunk
## that streams it in gets copies sharing its meshes and shapes.
static var _templates: Dictionary = {}


## Builds the site under `parent` (CivicSites' pivot, the site's own frame). `statics` is null for
## the far copy.
static func build(info: Dictionary, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var key := _key(info, detailed)
	if not _templates.has(key):
		_templates[key] = _template(info, detailed)
	# The far copy is built at load: build the near one then too, not when a chunk streams it in.
	if not detailed and not _templates.has(_key(info, true)):
		_templates[_key(info, true)] = _template(info, true)
	var t: Array = _templates[key]
	var holder: Node3D = t[0]
	for c in holder.get_children():
		parent.add_child(c.duplicate())
	for m in holder.get_meta_list():
		parent.set_meta(m, holder.get_meta(m))
	if statics and t[1] != null:
		for c in (t[1] as Node).get_children():
			statics.add_child(c.duplicate())


static func _key(info: Dictionary, detailed: bool) -> String:
	return "%s|%.3f|%s" % [info.local, float(info.y0), detailed]


static func _template(info: Dictionary, detailed: bool) -> Array:
	var holder := Node3D.new()
	var body: StaticBody3D = StaticBody3D.new() if detailed else null
	_build_into(info, holder, body, detailed)
	return [holder, body]


static func _build_into(info: Dictionary, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var s: Rect2 = info.local
	var y0: float = info.y0
	var L := layout(s, kiosk_local(info))
	_tick("")
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	var solid := PuebloMarket.Acc.new()
	var thin := PuebloMarket.Acc.new()
	# The small things - goods, bulbs, strings, lanterns, ironwork bars - cast no shadow: four
	# cascades of 100k triangles of pots and pinatas were half a million shadow triangles.
	var small := PuebloMarket.Acc.new()
	_materials(g, y0)
	_ground(g, batch, L, y0, detailed)
	var occ: Array = []
	for seg: Array in L.segs:
		_row_building(g, small, statics, L, seg, y0, detailed, occ)
	_church(g, small, parent, statics, L.church, y0, detailed)
	_firehouse(g, small, statics, L.fire, y0, detailed, occ)
	_hotel(g, solid, statics, L.hotel, y0, detailed, occ)
	_tick("buildings")
	_kiosk(g, solid, statics, L.p, y0, detailed)
	_tick("kiosk")
	if detailed:
		_plaza_detail(g, batch, small, thin, statics, L, y0)
		_tick("plaza")
		_lane_detail(g, small, thin, statics, L, y0)
		_lane_pools(batch, L, y0)
		_tick("lane")
		for st: Dictionary in L.stalls:
			var xf: Transform3D = st.xf
			xf.origin.y = y0 + 0.05
			PuebloMarket.stall(solid, thin, xf, int(st.goods), int(st.seed), 0, small)
			if statics:
				var c := xf * Vector3(0, PuebloMarket.STALL_H * 0.5, -PuebloMarket.STALL_D * 0.5)
				LandmarkGeo.shape_box(statics, c, Vector3(PuebloMarket.STALL_W - 0.1, PuebloMarket.STALL_H, PuebloMarket.STALL_D - 0.6), xf.basis)
		_tick("stalls")
		_pergola(parent, g, statics, L, y0)
		_tick("pergola")
		_fill(g, batch, parent, statics, L, y0)
	else:
		# From afar the pergola is a green roof over the lane, the stalls a colourful band under it.
		g.use("far_vines", LandmarkMats.plain("pueblo_far_vines", Color(0.24, 0.32, 0.14), 0.9))
		var lane: Rect2 = L.lane
		g.box("far_vines", Vector3(lane.get_center().x, y0 + PERGOLA_H + 0.25, lane.get_center().y), Vector3(lane.size.x, 0.5, lane.size.y), Color.WHITE)
	_tick("pergola+fill")
	parent.set_meta("pueblo_tris", {"geo": g.triangles, "market": solid.tris() + small.tris(), "small": small.tris(), "paper": thin.tris()})
	g.commit(parent, "PuebloLane")
	_tick("commit geo")
	if statics:
		g.commit_collision(statics)
	var sm := solid.mesh(PuebloMarket.solid_material())
	if sm:
		var mi := MeshInstance3D.new()
		mi.name = "PuebloMarket"
		mi.mesh = sm
		mi.visibility_range_end = 220.0
		mi.visibility_range_end_margin = 20.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mi)
	var gm := small.mesh(PuebloMarket.solid_material())
	if gm:
		var mi := MeshInstance3D.new()
		mi.name = "PuebloGoods"
		mi.mesh = gm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 170.0
		mi.visibility_range_end_margin = 20.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mi)
	var tm := thin.mesh(PuebloMarket.thin_material())
	if tm:
		var mi := MeshInstance3D.new()
		mi.name = "PuebloPaper"
		mi.mesh = tm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 170.0
		mi.visibility_range_end_margin = 20.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mi)
	batch.build(parent)
	if detailed:
		LandmarkArenaDistrict._occluder(parent, occ)
	_tick("commit rest")


static var debug: bool = OS.get_environment("PUEBLO_DEBUG") == "1"
static var _t0: int = 0


static func _tick(what: String) -> void:
	if debug:
		var t := Time.get_ticks_usec()
		if what != "":
			print("PUEBLO_STEP %-14s %d us" % [what, t - _t0])
		_t0 = t


static func _materials(g: LandmarkGeo, y0: float) -> void:
	g.use("stucco", LandmarkMats.facade("pueblo_stucco", "plaster_white", 3.0,
		{"tint": Color(0.93, 0.9, 0.84), "roughness": 0.92, "texture_contrast": 0.9, "grime": 0.4, "base_y": y0,
		"win_pitch": Vector2(3.3, 4.2), "win_size": Vector2(0.36, 0.5), "win_sill": 0.18, "win_band": Vector2(y0 + 4.6, y0 + 8.4),
		"win_reveal": 0.24, "lit_ratio": 0.5, "lit_color": Color(1.0, 0.76, 0.48),
		"flood_strength": 0.35, "flood_base_y": y0, "flood_reach": 6.0, "flood_floor": 0.25, "flood_spacing": 3.3}))
	g.use("adobe", LandmarkMats.facade("pueblo_adobe", "plaster_beige", 2.5,
		{"tint": Color(0.96, 0.93, 0.86), "roughness": 0.96, "texture_contrast": 1.2, "grime": 0.55, "base_y": y0,
		"flood_strength": 0.25, "flood_base_y": y0, "flood_reach": 5.0, "flood_floor": 0.2, "flood_spacing": 3.0}))
	g.use("brick", LandmarkMats.facade("pueblo_brick", "brick_red", 2.2,
		{"tint": Color(0.6, 0.31, 0.22), "roughness": 0.9, "grime": 0.35, "base_y": y0,
		"win_pitch": Vector2(3.3, 4.2), "win_size": Vector2(0.34, 0.55), "win_sill": 0.18, "win_band": Vector2(y0 + 4.6, y0 + 12.6),
		"win_reveal": 0.2, "lit_ratio": 0.45, "lit_color": Color(1.0, 0.78, 0.5)}))
	g.use("church", LandmarkMats.facade("pueblo_church", "plaster_white", 3.0,
		{"tint": Color(0.97, 0.94, 0.88), "roughness": 0.9, "texture_contrast": 0.8, "grime": 0.3, "base_y": y0,
		"win_pitch": Vector2(6.0, 30.0), "win_size": Vector2(0.18, 0.12), "win_sill": 0.3, "win_band": Vector2(y0 + 6.5, y0 + 9.5),
		"win_reveal": 0.4, "lit_ratio": 0.9, "lit_color": Color(1.0, 0.82, 0.55),
		"flood_strength": 1.1, "flood_base_y": y0, "flood_reach": 16.0, "flood_floor": 0.35, "flood_spacing": 3.0}))
	g.use("tile", LandmarkMats.clay("pueblo"))
	g.use("timber", LandmarkMats.plain("pueblo_timber", Color(0.38, 0.26, 0.16), 0.8))
	g.use("trim", LandmarkMats.plain("pueblo_trim", Color(0.9, 0.88, 0.82), 0.75))
	g.use("iron", LandmarkMats.plain("pueblo_iron", Color(0.07, 0.07, 0.07), 0.45, 0.4))
	g.use("shop", LandmarkMats.glass("pueblo_shop", {"glass_tint": Color(0.16, 0.13, 0.1), "frame_color": Color(0.3, 0.2, 0.12),
		"grid": Vector2(0.6, 0.8), "frame_width": 0.04, "room_depth": 6.0, "storey": 4.0, "floor_y": y0, "interior_day": 0.45, "interior_night": 2.2,
		"interior_color": Color(1.0, 0.76, 0.46)}))
	g.use("door", LandmarkMats.plain("pueblo_door", Color(0.34, 0.2, 0.12), 0.7))
	g.use("roof", LandmarkMats.paving("concrete", 3.0, Color(0.58, 0.55, 0.5), SEED_BASE + 9, 0.0, 0.6))


## The ground: paving over the whole site, brick down the lane, tiles on the plaza with a brick
## ring, lawn in the gardens.
static func _ground(g: LandmarkGeo, batch: MultiMeshBatch, L: Dictionary, y0: float, detailed: bool) -> void:
	var s: Rect2 = L.site
	g.use("pave", LandmarkMats.paving("pavers", 2.4, Color(0.9, 0.82, 0.72), SEED_BASE, 0.0, 0.3))
	g.use("lane_brick", LandmarkMats.paving("brick_red", 1.4, Color(0.92, 0.8, 0.72), SEED_BASE + 1, 0.0, 0.25))
	g.use("plaza_tile", LandmarkMats.paving("pavers", 1.0, Color(0.95, 0.66, 0.5), SEED_BASE + 2, 0.0, 0.3))
	g.cap("pave", LandmarkGeo.ccw(_poly(s)), y0 + 0.03)
	var lane: Rect2 = L.lane
	g.cap("lane_brick", LandmarkGeo.ccw(_poly(lane)), y0 + 0.05)
	# The plaza: tiles inside a brick band, the band a ring of 32 segments.
	var p: Vector2 = L.p
	var segs := 40 if detailed else 16
	var disc := PackedVector2Array()
	for i in segs:
		disc.append(p + Vector2(cos(-TAU * float(i) / float(segs)), sin(-TAU * float(i) / float(segs))) * (PLAZA_HALF - 1.5))
	g.cap("lane_brick", LandmarkGeo.ccw(_poly((L.plaza as Rect2))), y0 + 0.05)
	g.cap("plaza_tile", LandmarkGeo.ccw(disc), y0 + 0.07)
	if detailed:
		g.ring_flat("lane_brick", p, Vector2(TREE_RING - 2.2, TREE_RING - 2.2), Vector2(TREE_RING - 1.4, TREE_RING - 1.4), y0 + 0.08, 0.0, TAU, 40)
		g.ring_flat("lane_brick", p, Vector2(KIOSK_R + 1.6, KIOSK_R + 1.6), Vector2(KIOSK_R + 2.3, KIOSK_R + 2.3), y0 + 0.08, 0.0, TAU, 32)
	g.use("lawn", PropFactory.lawn(Color(0.48, 0.6, 0.3), SEED_BASE + 3, 0.3, 3.0))
	var garden: Rect2 = L.garden
	if garden.size.x > 6.0 and garden.size.y > 6.0:
		g.cap("lawn", LandmarkGeo.ccw(_poly(garden.grow(-3.0))), y0 + 0.08)
	var court: Rect2 = L.court
	g.cap("lawn", LandmarkGeo.ccw(_poly(court.grow(-2.0))), y0 + 0.08)


static func _poly(r: Rect2) -> PackedVector2Array:
	return LandmarkArenaDistrict._rect_poly(r)


# --- The lane's buildings ----------------------------------------------------------------------------

## One building of a row: [z0, z1, kind, storeys, tint, side]. Its front on the lane's edge, its
## back at the row's back; the ground floor built round its openings (arched or square, a shop
## window or a door each, recessed), the upper storey's windows the facade shader's; a tiled eave,
## a parapet or a brick cornice; an iron balcony on some; the adobe's corredor.
static func _row_building(g: LandmarkGeo, solid: PuebloMarket.Acc, statics: StaticBody3D, L: Dictionary, seg: Array, y0: float, detailed: bool, occ: Array) -> void:
	var z0: float = seg[0]
	var z1: float = seg[1]
	var kind: int = seg[2]
	var storeys: int = seg[3]
	var tint: Color = STUCCO_TINTS[int(seg[4])]
	var side: int = seg[5]
	var lane: Rect2 = L.lane
	var row: Rect2 = L.west if side > 0 else L.east
	# Front line and the way the front faces (+x for the west row).
	var f := float(side)
	var fx := lane.position.x if side > 0 else lane.end.x
	var back := row.position.x if side > 0 else row.end.x
	var depth := absf(fx - back)
	var key := "adobe" if kind == Kind.ADOBE else ("brick" if kind == Kind.BRICK2 else "stucco")
	var col := Color.WHITE if kind == Kind.BRICK2 else tint
	if kind == Kind.ADOBE:
		col = Color(1.0, 0.98, 0.94)
	var gf := 4.4 if storeys == 2 else (4.2 if kind == Kind.ADOBE else 4.8)
	var hgt := gf + (4.0 if storeys == 2 else 0.0)
	var recess := 0.35 if kind != Kind.ADOBE else 0.6
	var zc := (z0 + z1) * 0.5
	var length := z1 - z0
	var sd := hash([SEED_BASE, "bld", side, roundi(z0)])
	# The body behind the ground floor's recess.
	var body_c := Vector3(fx - f * (recess + (depth - recess) * 0.5), y0 + hgt * 0.5, zc)
	var body_s := Vector3(depth - recess, hgt, length - 0.02)
	g.box(key, body_c, body_s, col, Basis(), 0.0, false, 3.3)
	occ.append([body_c, body_s])
	if statics:
		LandmarkGeo.shape_box(statics, Vector3(fx - f * depth * 0.5, y0 + hgt * 0.5, zc), Vector3(depth, hgt, length - 0.02))
	# The upper storey's front, flush with the street line.
	if storeys == 2:
		g.box(key, Vector3(fx - f * recess * 0.5, y0 + gf + (hgt - gf) * 0.5, zc), Vector3(recess, hgt - gf, length - 0.02), col, Basis(), 0.0, false, 3.3)
	# The ground floor: bays of piers and openings.
	var bays := maxi(1, roundi(length / 3.3))
	var bay := length / float(bays)
	var arched := kind != Kind.BRICK2 and h01([sd, "arch"]) < 0.7
	var n := Vector3(f, 0, 0)
	for b in bays:
		var bz0 := z0 + bay * float(b)
		var bzc := bz0 + bay * 0.5
		var door := (b % 2 == 0) == (h01([sd, "door"]) < 0.5) or bays == 1
		var ow := 1.5 if door else minf(2.0, bay - 0.9)
		if kind == Kind.ADOBE:
			ow = 1.1 if door else 0.9
		var oh := 2.7 if door else (1.6 if kind == Kind.ADOBE else 2.2)
		var sill := 0.0 if door else (0.9 if kind == Kind.ADOBE else 0.55)
		var top := sill + oh
		var pier := (bay - ow) * 0.5
		for sg: float in [-1.0, 1.0]:
			var pzc := bzc + sg * (ow * 0.5 + pier * 0.5)
			g.box(key, Vector3(fx - f * recess * 0.5, y0 + gf * 0.5, pzc), Vector3(recess, gf, pier), col)
		if sill > 0.0:
			g.box(key, Vector3(fx - f * recess * 0.5, y0 + sill * 0.5, bzc), Vector3(recess, sill, ow), col)
			g.box("trim", Vector3(fx - f * 0.05, y0 + sill - 0.03, bzc), Vector3(0.2, 0.06, ow + 0.1), Color(0.86, 0.84, 0.78))
		var rad := ow * 0.5
		var spring := top - (rad if arched else 0.0)
		# The head: square lintel, or an arch's spandrels and soffit.
		g.box(key, Vector3(fx - f * recess * 0.5, y0 + (top + gf) * 0.5, bzc), Vector3(recess, gf - top, ow), col)
		if arched and detailed:
			var segs := 8
			for i in segs:
				var a0 := PI * float(i) / float(segs)
				var a1 := PI * float(i + 1) / float(segs)
				var p0 := Vector3(fx, y0 + spring + sin(a0) * rad, bzc - cos(a0) * rad)
				var p1 := Vector3(fx, y0 + spring + sin(a1) * rad, bzc - cos(a1) * rad)
				g.quad(key, p0, Vector3(fx, y0 + top, p0.z), Vector3(fx, y0 + top, p1.z), p1, n,
					Vector2(p0.z, p0.y), Vector2(p0.z, y0 + top), Vector2(p1.z, y0 + top), Vector2(p1.z, p1.y), col)
				var q0 := p0 - n * recess
				var q1 := p1 - n * recess
				var mid := (p0 + p1) * 0.5
				var inward := (Vector3(fx, y0 + spring, bzc) - mid).normalized()
				g.quad(key, p0, q0, q1, p1, inward, Vector2(0, a0), Vector2(recess, a0), Vector2(recess, a1), Vector2(0, a1), col * 0.95)
		# The opening's jambs.
		if detailed:
			for sg: float in [-1.0, 1.0]:
				var jz := bzc + sg * ow * 0.5
				g.quad(key, Vector3(fx, y0 + sill, jz), Vector3(fx - f * recess, y0 + sill, jz), Vector3(fx - f * recess, y0 + spring, jz), Vector3(fx, y0 + spring, jz),
					Vector3(0, 0, -sg), Vector2(0, y0 + sill), Vector2(recess, y0 + sill), Vector2(recess, y0 + spring), Vector2(0, y0 + spring), col * 0.95)
		# In the opening: a lit shop window, or a door (timber, or glazed into a lit shop).
		var gx := fx - f * (recess - 0.02)
		if door and kind == Kind.ADOBE:
			g.box("door", Vector3(gx + f * 0.04, y0 + oh * 0.5, bzc), Vector3(0.08, oh, ow - 0.04), Color.WHITE)
		else:
			var gtop := top
			g.quad("shop", Vector3(gx, y0 + sill, bzc - ow * 0.5), Vector3(gx, y0 + sill, bzc + ow * 0.5), Vector3(gx, y0 + gtop, bzc + ow * 0.5), Vector3(gx, y0 + gtop, bzc - ow * 0.5), n,
				Vector2(0, y0 + sill), Vector2(ow, y0 + sill), Vector2(ow, y0 + gtop), Vector2(0, y0 + gtop))
			if door and detailed:
				g.box("door", Vector3(gx + f * 0.03, y0 + 1.2, bzc), Vector3(0.05, 2.4, 0.06), Color.WHITE)
		# A lantern beside every other opening.
		if detailed and b % 2 == 1:
			PuebloMarket.lantern(solid, Vector3(fx, y0 + gf - 1.1, bz0 + 0.3), n)
	# The roof line: a flat roof behind a parapet (brick with a corbelled cornice, the adobe's low
	# one), or a tiled gable along the lane, or a tiled eave over the front.
	var foot := Rect2(Vector2(minf(fx, back), z0), Vector2(depth, length))
	if kind == Kind.BRICK2:
		g.box("brick", Vector3(fx - f * 0.05, y0 + hgt + 0.25, zc), Vector3(0.6, 0.5, length), Color.WHITE, Basis(), 0.05 if detailed else 0.0)
		g.box("trim", Vector3(fx - f * 0.15, y0 + hgt + 0.55, zc), Vector3(0.75, 0.12, length + 0.1), Color(0.82, 0.8, 0.74))
		_flat_roof(g, foot, y0 + hgt, "brick", Color.WHITE, 0.5)
	elif kind == Kind.ADOBE:
		# A low parapet, viga ends out of the wall, and the corredor: posts, a beam and a tiled
		# lean-to roof out over the lane's edge.
		_flat_roof(g, foot, y0 + hgt, "adobe", col, 0.5)
		if detailed:
			var nv := int(length / 0.9)
			for i in nv:
				g.box("timber", Vector3(fx + f * 0.18, y0 + hgt - 0.35, z0 + 0.45 + 0.9 * float(i)), Vector3(0.36, 0.2, 0.2), Color.WHITE)
		var cx := fx + f * 1.5
		var np := maxi(2, int(length / 3.2) + 1)
		for i in np:
			var pz := z0 + 0.4 + (length - 0.8) * float(i) / float(np - 1)
			g.box("timber", Vector3(cx, y0 + 1.5, pz), Vector3(0.2, 3.0, 0.2), Color.WHITE)
			if detailed:
				g.box("timber", Vector3(cx, y0 + 2.95, pz), Vector3(0.3, 0.1, 0.6), Color.WHITE)
		g.box("timber", Vector3(cx, y0 + 3.1, zc), Vector3(0.24, 0.24, length), Color.WHITE)
		_lean_to(g, "tile", fx, cx + f * 0.4, z0, z1, y0 + 3.9, y0 + 3.2)
	else:
		var r := h01([sd, "eave"])
		if r < 0.45:
			# A low tiled gable, its ridge along the lane, eaves out over the front and the back.
			LandmarkCivicCenter._gable(g, "tile", key, foot.grow_individual(0.6, 0.0, 0.6, 0.0), y0 + hgt, 2.2, true, statics)
		elif r < 0.75:
			_lean_to(g, "tile", fx - f * 0.6, fx + f * 0.9, z0, z1, y0 + hgt + 0.5, y0 + hgt - 0.15)
			_flat_roof(g, foot, y0 + hgt, key, col, 0.55)
		else:
			_flat_roof(g, foot, y0 + hgt, key, col, 0.85)
			g.box("trim", Vector3(fx - f * 0.15, y0 + hgt + 0.88, zc), Vector3(0.42, 0.08, length + 0.06), Color(0.86, 0.84, 0.78))
	# An iron balcony on a two-storey front.
	if storeys == 2 and detailed and h01([sd, "balc"]) < 0.55:
		var bw := minf(length - 1.0, 3.3 * float(maxi(1, int(bays / 2))))
		var by := y0 + gf + 0.05
		g.box("trim", Vector3(fx + f * 0.55, by, zc), Vector3(1.1, 0.14, bw), Color(0.82, 0.8, 0.74))
		solid.set_look(Color(0.06, 0.06, 0.06), PuebloMarket.K_IRON)
		solid.box(Transform3D(Basis(), Vector3(fx + f * 1.07, by + 1.0, zc)), Vector3(0.04, 0.04, bw))
		for i in int(bw / 0.14):
			solid.box(Transform3D(Basis(), Vector3(fx + f * 1.07, by + 0.52, zc - bw * 0.5 + 0.07 + 0.14 * float(i))), Vector3(0.018, 0.92, 0.018))
		for sg: float in [-1.0, 1.0]:
			solid.box(Transform3D(Basis(), Vector3(fx + f * 0.55, by + 0.52, zc + sg * bw * 0.5)), Vector3(1.05, 0.92, 0.02))
		if statics:
			LandmarkGeo.shape_box(statics, Vector3(fx + f * 0.55, by, zc), Vector3(1.1, 0.14, bw))


## A lean-to roof from x_hi (at y_hi) out to x_lo (at y_lo), z0..z1, with its fascia.
static func _lean_to(g: LandmarkGeo, key: String, x_hi: float, x_lo: float, z0: float, z1: float, y_hi: float, y_lo: float) -> void:
	var a := Vector3(x_hi, y_hi, z0)
	var b := Vector3(x_hi, y_hi, z1)
	var c := Vector3(x_lo, y_lo, z1)
	var d := Vector3(x_lo, y_lo, z0)
	var run := absf(x_lo - x_hi)
	var slope := sqrt(run * run + (y_hi - y_lo) * (y_hi - y_lo))
	var n := Vector3(signf(x_lo - x_hi) * (y_hi - y_lo), run, 0.0).normalized()
	g.quad(key, a, b, c, d, n, Vector2(0, slope), Vector2(z1 - z0, slope), Vector2(z1 - z0, 0), Vector2(0, 0))
	g.quad("timber", a + Vector3(0, -0.06, 0), d + Vector3(0, -0.06, 0), c + Vector3(0, -0.06, 0), b + Vector3(0, -0.06, 0), -n, Vector2(0, 0), Vector2(slope, 0), Vector2(slope, 1), Vector2(0, 1), Color(0.8, 0.8, 0.8))
	g.box("timber", Vector3(x_lo, y_lo - 0.08, (z0 + z1) * 0.5), Vector3(0.06, 0.18, z1 - z0), Color.WHITE)


## A flat roof over `r` at height `y`: a gravel-and-membrane deck behind a parapet `par` high.
static func _flat_roof(g: LandmarkGeo, r: Rect2, y: float, key: String, col: Color, par: float) -> void:
	g.cap("roof", LandmarkGeo.ccw(_poly(r.grow(-0.2))), y + 0.03)
	var t := 0.3
	var c := r.get_center()
	for sg: float in [-1.0, 1.0]:
		g.box(key, Vector3(c.x, y + par * 0.5, c.y + sg * (r.size.y * 0.5 - t * 0.5)), Vector3(r.size.x, par, t), col)
		g.box(key, Vector3(c.x + sg * (r.size.x * 0.5 - t * 0.5), y + par * 0.5, c.y), Vector3(t, par, r.size.y - 2.0 * t), col)


# --- The church -----------------------------------------------------------------------------------------

## The church: front on the plaza (facing -z), nave south. A sanctuary: its zone covers the nave
## and the forecourt; its collision is its own body in Sanctuary's group.
static func _church(g: LandmarkGeo, solid: PuebloMarket.Acc, parent: Node3D, statics: StaticBody3D, r: Rect2, y0: float, detailed: bool) -> void:
	var body: StaticBody3D = null
	if statics:
		body = StaticBody3D.new()
		body.name = "ChurchBody"
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group(Sanctuary.BODY_GROUP)
		parent.add_child(body)
	var cx := r.get_center().x
	var zf := r.position.y
	var h := CHURCH_H
	var nave_c := Vector3(cx, y0 + h * 0.5, r.get_center().y + 0.5)
	g.box("church", nave_c, Vector3(r.size.x, h, r.size.y - 1.0), Color.WHITE, Basis(), 0.0, false, 6.0)
	LandmarkGeo.shape_box(body, nave_c, Vector3(r.size.x, h, r.size.y - 1.0))
	LandmarkCivicCenter._gable(g, "tile", "church", Rect2(Vector2(r.position.x - 0.7, zf + 1.0), Vector2(r.size.x + 1.4, r.size.y - 0.5)), y0 + h, 4.2, true, body)
	# Buttresses down both sides.
	var nb := int(r.size.y / 6.5)
	for i in nb:
		var bz := zf + 5.0 + float(i) * 6.5
		for sg: float in [-1.0, 1.0]:
			var bc := Vector3(cx + sg * (r.size.x * 0.5 + 0.55), y0 + 3.5, bz)
			g.box("church", bc, Vector3(1.1, 7.0, 1.2), Color(0.96, 0.94, 0.9), Basis(), 0.06 if detailed else 0.0)
			LandmarkGeo.shape_box(body, bc, Vector3(1.1, 7.0, 1.2))
	# The front: a thick wall rising into the bell gable - a stepped, scrolled parapet with three
	# arched openings, a bell in each - over the arched door, a round window, pilasters, a cornice.
	var fw := r.size.x + 2.0
	var front_c := Vector3(cx, y0 + h * 0.5 + 1.0, zf + 0.6)
	g.box("church", front_c, Vector3(fw, h + 2.0, 1.2), Color.WHITE, Basis(), 0.04 if detailed else 0.0)
	LandmarkGeo.shape_box(body, front_c, Vector3(fw, h + 2.0, 1.2))
	# The gable: three stepped tiers, the bells in the middle one.
	var gy := y0 + h + 2.0
	var tiers := [[fw - 3.0, 2.2], [fw - 6.5, 3.6], [3.4, 2.4]]
	var ty := gy
	for t: Array in tiers:
		var tw: float = t[0]
		var th: float = t[1]
		g.box("church", Vector3(cx, ty + th * 0.5, zf + 0.6), Vector3(tw, th, 1.0), Color.WHITE, Basis(), 0.04 if detailed else 0.0)
		g.box("trim", Vector3(cx, ty + th + 0.08, zf + 0.6), Vector3(tw + 0.3, 0.16, 1.2), Color(0.94, 0.92, 0.86))
		ty += th + 0.16
	LandmarkGeo.shape_box(body, Vector3(cx, gy + 3.0, zf + 0.6), Vector3(fw - 3.0, 6.0, 1.0))
	# The cross on top.
	g.box("timber", Vector3(cx, ty + 1.2, zf + 0.6), Vector3(0.22, 2.4, 0.22), Color(0.9, 0.9, 0.9))
	g.box("timber", Vector3(cx, ty + 1.7, zf + 0.6), Vector3(1.2, 0.22, 0.22), Color(0.9, 0.9, 0.9))
	# Bell openings: dark recesses in the middle tier with a bronze bell hanging in each.
	g.use("bronze", LandmarkMats.plain("pueblo_bronze", Color(0.45, 0.32, 0.16), 0.35, 0.85))
	g.use("dark", LandmarkMats.plain("pueblo_dark", Color(0.05, 0.045, 0.04), 0.9))
	var by := gy + 2.2 + 0.16 + 0.6
	for i in 3:
		var bx := cx + (float(i) - 1.0) * 2.2
		g.box("dark", Vector3(bx, by + 1.0, zf + 0.08), Vector3(1.2, 2.0, 0.06), Color.WHITE)
		if detailed:
			g.cylinder("bronze", Vector3(bx, by + 0.5, zf - 0.05), 0.42, 0.9, 12, Color.WHITE, 0.24)
			g.cylinder("bronze", Vector3(bx, by + 1.4, zf - 0.05), 0.05, 0.4, 6)
			g.box("timber", Vector3(bx, by + 1.85, zf + 0.0), Vector3(1.3, 0.12, 0.12), Color.WHITE)
	# The door: an arched opening with a moulded surround and twin timber doors.
	var dw := 3.2
	var dh := 5.6
	g.box("dark", Vector3(cx, y0 + dh * 0.5, zf - 0.02), Vector3(dw, dh, 0.04), Color.WHITE)
	g.box("door", Vector3(cx, y0 + (dh - dw * 0.5) * 0.5, zf - 0.05), Vector3(dw - 0.2, dh - dw * 0.5, 0.06), Color.WHITE)
	if detailed:
		var segs := 12
		var rad := dw * 0.5 + 0.35
		for i in segs:
			var a := PI * (float(i) + 0.5) / float(segs)
			var p := Vector3(cx - cos(a) * rad, y0 + dh - dw * 0.5 + sin(a) * rad, zf - 0.1)
			g.box("trim", p, Vector3(PI * rad / float(segs) + 0.05, 0.5, 0.25), Color(0.92, 0.9, 0.84), Basis(Vector3.FORWARD, -(a - PI * 0.5)))
		for sg: float in [-1.0, 1.0]:
			g.box("trim", Vector3(cx + sg * (dw * 0.5 + 0.35), y0 + (dh - dw * 0.5) * 0.5, zf - 0.1), Vector3(0.5, dh - dw * 0.5, 0.25), Color(0.92, 0.9, 0.84))
			# Pilasters at the corners and a pair framing the door.
			for px: float in [fw * 0.5 - 0.4, dw * 0.5 + 1.6]:
				g.box("church", Vector3(cx + sg * px, y0 + (h + 2.0) * 0.5, zf - 0.12), Vector3(0.7, h + 2.0, 0.3), Color(0.98, 0.97, 0.93))
		# A stone plinth along the foot of the front, a tiled hood over the door on carved corbels,
		# a niche with a lantern glow over it.
		g.box("trim", Vector3(cx, y0 + 0.45, zf - 0.08), Vector3(fw + 0.1, 0.9, 0.3), Color(0.78, 0.72, 0.64))
		LandmarkCivicCenter._gable(g, "tile", "church", Rect2(Vector2(cx - dw * 0.5 - 1.0, zf - 1.3), Vector2(dw + 2.0, 1.3)), y0 + dh + 0.7, 0.55, false, null)
		for sg: float in [-1.0, 1.0]:
			g.box("timber", Vector3(cx + sg * (dw * 0.5 + 0.7), y0 + dh + 0.45, zf - 0.6), Vector3(0.25, 0.5, 1.2), Color(0.8, 0.8, 0.8))
		g.box("dark", Vector3(cx, y0 + 11.5, zf - 0.02), Vector3(0.9, 1.3, 0.05), Color.WHITE)
		g.box("trim", Vector3(cx, y0 + 10.78, zf - 0.15), Vector3(1.3, 0.16, 0.35), Color(0.92, 0.9, 0.84))
		# The round window over the door.
		g.cylinder("dark", Vector3(cx, y0 + 9.1, zf), 0.9, 0.1, 16)
		var ring := 16
		for i in ring:
			var a := TAU * float(i) / float(ring)
			g.box("trim", Vector3(cx + cos(a) * 1.05, y0 + 9.1 + sin(a) * 1.05, zf - 0.1), Vector3(0.45, 0.25, 0.22), Color(0.92, 0.9, 0.84), Basis(Vector3.FORWARD, -a))
		# A lantern either side of the door.
		for sg: float in [-1.0, 1.0]:
			PuebloMarket.lantern(solid, Vector3(cx + sg * 3.1, y0 + 3.2, zf), Vector3(0, 0, -1))
		# The name over the door.
		var batch_name := MultiMeshBatch.new()
		batch_name.add("church_name", Signage.text_mesh(CHURCH_NAME, 0.42, Signage.Letters.PRINT),
			Transform3D(LandmarkArenaDistrict._face(0.0, 1.0), Vector3(cx, y0 + 7.35, zf - 0.13)), Color(0.32, 0.24, 0.16))
		batch_name.set_no_shadow("church_name")
		batch_name.build(parent)
	# The sanctuary zone: the nave, the front and the forecourt to the plaza's edge.
	Sanctuary.add_zone(parent, Vector3(cx, y0 + 10.0, r.get_center().y - 2.5), Vector3(fw * 0.5 + 1.5, 12.0, r.size.y * 0.5 + 3.5))


# --- The firehouse and the hotel block ---------------------------------------------------------------------

static func _firehouse(g: LandmarkGeo, solid: PuebloMarket.Acc, statics: StaticBody3D, r: Rect2, y0: float, detailed: bool, occ: Array) -> void:
	var h := 9.0
	var c := Vector3(r.get_center().x, y0 + h * 0.5, r.get_center().y)
	g.box("brick", c, Vector3(r.size.x, h, r.size.y), Color.WHITE, Basis(), 0.0, false, 3.3)
	occ.append([c, Vector3(r.size.x, h, r.size.y)])
	LandmarkGeo.shape_box(statics, c, Vector3(r.size.x, h, r.size.y))
	var fx := r.position.x
	# The engine door: a tall arched opening, doors of timber and glass, on the plaza side.
	g.box("door", Vector3(fx - 0.03, y0 + 2.2, c.z), Vector3(0.06, 4.4, 4.0), Color(0.62, 0.12, 0.08))
	g.box("trim", Vector3(fx - 0.12, y0 + 4.6, c.z), Vector3(0.24, 0.4, 4.6), Color(0.88, 0.86, 0.8))
	g.box("trim", Vector3(fx - 0.12, y0 + h + 0.2, c.z), Vector3(0.5, 0.4, r.size.y + 0.3), Color(0.88, 0.86, 0.8))
	g.box("brick", Vector3(fx + 0.3, y0 + h + 1.0, c.z), Vector3(0.6, 1.6, 6.0), Color.WHITE)
	_flat_roof(g, r, y0 + h, "brick", Color.WHITE, 0.6)
	if detailed:
		PuebloMarket.lantern(solid, Vector3(fx, y0 + 4.2, c.z - 3.2), Vector3(-1, 0, 0))
		PuebloMarket.lantern(solid, Vector3(fx, y0 + 4.2, c.z + 3.2), Vector3(-1, 0, 0))


static func _hotel(g: LandmarkGeo, solid: PuebloMarket.Acc, statics: StaticBody3D, r: Rect2, y0: float, detailed: bool, occ: Array) -> void:
	if r.size.x < 12.0:
		return
	var h := 12.8
	var c := Vector3(r.get_center().x, y0 + h * 0.5, r.get_center().y)
	g.box("stucco", c, Vector3(r.size.x, h, r.size.y), Color(1.0, 0.9, 0.74), Basis(), 0.0, false, 3.3)
	occ.append([c, Vector3(r.size.x, h, r.size.y)])
	LandmarkGeo.shape_box(statics, c, Vector3(r.size.x, h, r.size.y))
	var zf := r.position.y
	# A ground-floor arcade of shop windows, string courses, a bracketed cornice.
	g.quad("shop", Vector3(r.position.x + 1.0, y0 + 0.4, zf - 0.02), Vector3(r.end.x - 1.0, y0 + 0.4, zf - 0.02), Vector3(r.end.x - 1.0, y0 + 3.4, zf - 0.02), Vector3(r.position.x + 1.0, y0 + 3.4, zf - 0.02),
		Vector3(0, 0, -1), Vector2(0, y0 + 0.4), Vector2(r.size.x - 2.0, y0 + 0.4), Vector2(r.size.x - 2.0, y0 + 3.4), Vector2(0, y0 + 3.4))
	var nb := maxi(2, int(r.size.x / 3.3))
	for i in nb + 1:
		g.box("stucco", Vector3(r.position.x + 1.0 + (r.size.x - 2.0) * float(i) / float(nb), y0 + 2.0, zf - 0.2), Vector3(0.6, 4.0, 0.4), Color(1.0, 0.9, 0.74))
	for yy: float in [4.2, 8.4]:
		g.box("trim", Vector3(c.x, y0 + yy, zf - 0.08), Vector3(r.size.x + 0.2, 0.24, 0.3), Color(0.9, 0.88, 0.8))
	g.box("trim", Vector3(c.x, y0 + h + 0.25, c.z), Vector3(r.size.x + 1.0, 0.5, r.size.y + 1.0), Color(0.88, 0.86, 0.8), Basis(), 0.06 if detailed else 0.0)
	_flat_roof(g, r, y0 + h + 0.5, "stucco", Color(1.0, 0.9, 0.74), 0.7)
	# Roof plant: a stair bulkhead, two condensers.
	g.box("stucco", Vector3(r.position.x + 5.0, y0 + h + 1.9, c.z), Vector3(4.0, 2.8, 4.0), Color(1.0, 0.9, 0.74))
	for i in 2:
		g.box("trim", Vector3(r.end.x - 6.0 - 4.0 * float(i), y0 + h + 1.1, c.z + 4.0), Vector3(2.2, 1.2, 1.4), Color(0.7, 0.7, 0.7))


# --- The kiosk ------------------------------------------------------------------------------------------

## The octagonal bandstand on the plaza's centre `p`.
static func _kiosk(g: LandmarkGeo, solid: PuebloMarket.Acc, statics: StaticBody3D, p: Vector2, y0: float, detailed: bool) -> void:
	var oct := PackedVector2Array()
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		oct.append(p + Vector2(cos(a), sin(a)) * KIOSK_R)
	g.prism("stucco", oct, y0, y0 + KIOSK_DECK, Color(1.0, 0.92, 0.8), false, true, false, "plaza_tile")
	LandmarkGeo.shape_box(statics, Vector3(p.x, y0 + KIOSK_DECK * 0.5, p.y), Vector3(KIOSK_R * 1.6, KIOSK_DECK, KIOSK_R * 1.6))
	LandmarkGeo.shape_box(statics, Vector3(p.x, y0 + KIOSK_DECK * 0.5, p.y), Vector3(KIOSK_R * 1.6, KIOSK_DECK, KIOSK_R * 1.6), Basis(Vector3.UP, PI * 0.25))
	# A terracotta band round the base, steps north and south.
	g.band("plaza_tile", p, Vector2(KIOSK_R * 1.01, KIOSK_R * 1.01), Vector2(KIOSK_R * 1.01, KIOSK_R * 1.01), y0 + KIOSK_DECK - 0.25, y0 + KIOSK_DECK - 0.05, 0.0, TAU, 16)
	for sg: float in [-1.0, 1.0]:
		for k in 4:
			var sy := y0 + KIOSK_DECK * float(k + 1) / 5.0
			var sc := Vector3(p.x, sy - KIOSK_DECK / 10.0, p.y + sg * (KIOSK_R * 0.92 + 0.35 * float(4 - k)))
			g.box("trim", sc, Vector3(2.4, KIOSK_DECK / 5.0, 0.36), Color(0.82, 0.8, 0.76))
			LandmarkGeo.shape_box(statics, sc, Vector3(2.4, KIOSK_DECK / 5.0, 0.36))
	# Eight slender iron columns, a ring beam, the roof: a bell-cast octagon of tiles, a small
	# lantern on top, a finial.
	var top := y0 + KIOSK_DECK + KIOSK_COLS
	var paint := Color(0.92, 0.9, 0.84)
	solid.set_look(paint, PuebloMarket.K_IRON)
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		var cp := p + Vector2(cos(a), sin(a)) * (KIOSK_R - 0.35)
		solid.lathe(Transform3D(Basis(), Vector3(cp.x, y0 + KIOSK_DECK, cp.y)),
			[Vector2(0.0, 0.0), Vector2(0.14, 0.0), Vector2(0.14, 0.12), Vector2(0.07, 0.2), Vector2(0.06, KIOSK_COLS - 0.4), Vector2(0.11, KIOSK_COLS - 0.15), Vector2(0.16, KIOSK_COLS), Vector2(0.0, KIOSK_COLS)], 8 if detailed else 5)
	g.band("trim", p, Vector2(KIOSK_R - 0.1, KIOSK_R - 0.1), Vector2(KIOSK_R - 0.1, KIOSK_R - 0.1), top, top + 0.45, 0.0, TAU, 8)
	g.ring_flat("trim", p, Vector2(0.01, 0.01), Vector2(KIOSK_R - 0.1, KIOSK_R - 0.1), top, 0.0, TAU, 8, Color(0.94, 0.9, 0.82), false, true)
	# The roof: rings of an ogee profile, eight sides.
	var prof := [[KIOSK_R + 0.7, 0.45], [KIOSK_R + 0.1, 0.75], [KIOSK_R * 0.7, 1.45], [KIOSK_R * 0.38, 2.5], [0.9, 3.0]]
	for j in prof.size() - 1:
		var r0: float = prof[j][0]
		var y_a: float = prof[j][1]
		var r1: float = prof[j + 1][0]
		var y_b: float = prof[j + 1][1]
		for i in 8:
			var a0 := TAU * (float(i) + 0.5) / 8.0
			var a1 := TAU * (float(i) + 1.5) / 8.0
			var p0 := Vector3(p.x + cos(a0) * r0, top + y_a, p.y + sin(a0) * r0)
			var p1 := Vector3(p.x + cos(a1) * r0, top + y_a, p.y + sin(a1) * r0)
			var q1 := Vector3(p.x + cos(a1) * r1, top + y_b, p.y + sin(a1) * r1)
			var q0 := Vector3(p.x + cos(a0) * r1, top + y_b, p.y + sin(a0) * r1)
			var am := (a0 + a1) * 0.5
			var out := Vector3(cos(am), 0, sin(am))
			var nrm := (out * (y_b - y_a) + Vector3.UP * (r0 - r1)).normalized()
			var wl := p0.distance_to(p1)
			var sl := p0.distance_to(q0)
			g.quad("tile", p0, p1, q1, q0, nrm, Vector2(0, 0), Vector2(wl, 0), Vector2(wl, sl), Vector2(0, sl))
	g.cylinder("trim", Vector3(p.x, top + 3.0, p.y), 0.75, 1.0, 8, Color(0.94, 0.9, 0.82))
	g.cylinder("tile", Vector3(p.x, top + 4.0, p.y), 0.95, 0.15, 8, Color.WHITE, 0.0)
	g.use("pueblo_gold", LandmarkMats.plain("pueblo_gold", Color(0.75, 0.58, 0.26), 0.3, 0.9))
	g.cylinder("pueblo_gold", Vector3(p.x, top + 4.1, p.y), 0.08, 1.4, 6)
	LandmarkGeo.shape_box(statics, Vector3(p.x, top + 1.2, p.y), Vector3(KIOSK_R * 1.7, 1.6, KIOSK_R * 1.7))
	if not detailed:
		return
	# The balustrade: a rail and balusters between the columns, open at the steps.
	solid.set_look(paint, PuebloMarket.K_IRON)
	for i in 8:
		var a0 := TAU * (float(i) + 0.5) / 8.0
		var a1 := TAU * (float(i) + 1.5) / 8.0
		var mid := (a0 + a1) * 0.5
		if absf(sin(mid)) > 0.95:
			continue
		var e0 := p + Vector2(cos(a0), sin(a0)) * (KIOSK_R - 0.35)
		var e1 := p + Vector2(cos(a1), sin(a1)) * (KIOSK_R - 0.35)
		var d := e1 - e0
		var bas := Basis(Vector3.UP, atan2(-d.y, d.x))
		var mc := (e0 + e1) * 0.5
		for yy: float in [0.12, 0.95]:
			solid.box(Transform3D(bas, Vector3(mc.x, y0 + KIOSK_DECK + yy, mc.y)), Vector3(d.length(), 0.05, 0.05))
		var nbal := int(d.length() / 0.14)
		for k in nbal:
			var bp := e0 + d * (float(k) + 0.5) / float(nbal)
			solid.box(Transform3D(bas, Vector3(bp.x, y0 + KIOSK_DECK + 0.53, bp.y)), Vector3(0.02, 0.8, 0.02))
		# The frieze: an arch of iron scrollwork between each pair of columns under the beam.
		var segs := 10
		for k in segs:
			var t0 := float(k) / float(segs)
			var t1 := float(k + 1) / float(segs)
			var q0 := e0 + d * t0
			var q1 := e0 + d * t1
			var h0 := 0.55 * (1.0 - pow(2.0 * t0 - 1.0, 2.0))
			var h1 := 0.55 * (1.0 - pow(2.0 * t1 - 1.0, 2.0))
			var w0 := Vector3(q0.x, top - 0.6 + h0, q0.y)
			var w1 := Vector3(q1.x, top - 0.6 + h1, q1.y)
			var dir := w1 - w0
			solid.box(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (w0 + w1) * 0.5), Vector3(0.05, 0.05, dir.length()))
			if k % 2 == 1:
				var w2 := (w0 + w1) * 0.5
				solid.box(Transform3D(bas, Vector3(w2.x, (w2.y + top) * 0.5, w2.z)), Vector3(0.02, top - w2.y, 0.02))
	# Bulbs round the eave.
	for i in 8:
		var a0 := TAU * (float(i) + 0.5) / 8.0
		var a1 := TAU * (float(i) + 1.5) / 8.0
		var e0 := Vector3(p.x + cos(a0) * (KIOSK_R + 0.6), top + 0.35, p.y + sin(a0) * (KIOSK_R + 0.6))
		var e1 := Vector3(p.x + cos(a1) * (KIOSK_R + 0.6), top + 0.35, p.y + sin(a1) * (KIOSK_R + 0.6))
		PuebloMarket.bulbs(solid, e0, e1, 0.25, 0.5, SEED_BASE + i)


# --- The plaza, the lane, the pergola, the fill ---------------------------------------------------------------

static func _plaza_detail(g: LandmarkGeo, batch: MultiMeshBatch, solid: PuebloMarket.Acc, thin: PuebloMarket.Acc, statics: StaticBody3D, L: Dictionary, y0: float) -> void:
	var p: Vector2 = L.p
	var ring := ArenaGrounds._ring_bench()
	# Ten shade trees round the kiosk, each with its grate and a ring bench.
	g.use("grate", LandmarkMats.plain("bosque_grate", Color(0.13, 0.13, 0.14), 0.55, 0.6))
	for i in 10:
		var a := TAU * (float(i) + 0.5) / 10.0
		var tp := p + Vector2(cos(a), sin(a)) * TREE_RING
		g.box("grate", Vector3(tp.x, y0 + 0.09, tp.y), Vector3(1.8, 0.02, 1.8), Color.WHITE)
		var tv := 1 + i % 3
		var sc := PropFactory.city_tree_scale(tv, 9.0 + 2.0 * h01([SEED_BASE, "tree", i]))
		batch.add("tree_%d" % tv, PropFactory.model_tree(tv), Transform3D(Basis(Vector3.UP, TAU * h01([SEED_BASE, "tyaw", i])).scaled(Vector3(sc, sc, sc)), Vector3(tp.x, y0 + 0.08, tp.y)),
			Color.WHITE, Color(h01([SEED_BASE, "tc", i]), h01([SEED_BASE, "td", i]), h01([SEED_BASE, "te", i]), 0.8))
		batch.add("ring_bench", ring, Transform3D(Basis(Vector3.UP, a), Vector3(tp.x, y0 + 0.08, tp.y)))
		LandmarkGeo.shape_box(statics, Vector3(tp.x, y0 + 0.3, tp.y), Vector3(2.4, 0.5, 2.4))
	for tv in range(1, 4):
		batch.set_draw_distance("tree_%d" % tv, 280.0)
	# Poles round the edge carrying the papel picado from the kiosk's eave; lamps between them.
	var lamp := PropFactory.model_lamp()
	var top := y0 + KIOSK_DECK + KIOSK_COLS + 0.6
	for i in 8:
		var a := TAU * float(i) / 8.0
		var pp := p + Vector2(cos(a), sin(a)) * (PLAZA_HALF - 3.0)
		var pole_h := 5.6
		g.box("timber", Vector3(pp.x, y0 + pole_h * 0.5, pp.y), Vector3(0.18, pole_h, 0.18), Color(0.75, 0.75, 0.75))
		LandmarkGeo.shape_box(statics, Vector3(pp.x, y0 + pole_h * 0.5, pp.y), Vector3(0.2, pole_h, 0.2))
		var e := Vector3(p.x + cos(a) * (KIOSK_R + 0.7), top, p.y + sin(a) * (KIOSK_R + 0.7))
		PuebloMarket.picado(thin, solid, e, Vector3(pp.x, y0 + pole_h - 0.1, pp.y), 0.9, SEED_BASE * 3 + i)
		var la := a + TAU / 16.0
		var lp := p + Vector2(cos(la), sin(la)) * (PLAZA_HALF - 2.0)
		batch.add("pueblo_lamp", lamp, Transform3D(Basis(Vector3.UP, -la + PI * 0.5), Vector3(lp.x, y0 + 0.05, lp.y)))
		batch.add("pueblo_pool", PropFactory.light_pool(), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(11.0, 1.0, 11.0)), Vector3(lp.x, y0 + 0.12, lp.y)))
	batch.set_no_shadow("pueblo_pool")
	# Bulb strings between the poles round the rim.
	for i in 8:
		var a0 := TAU * float(i) / 8.0
		var a1 := TAU * float(i + 1) / 8.0
		var q0 := p + Vector2(cos(a0), sin(a0)) * (PLAZA_HALF - 3.0)
		var q1 := p + Vector2(cos(a1), sin(a1)) * (PLAZA_HALF - 3.0)
		PuebloMarket.bulbs(solid, Vector3(q0.x, y0 + 5.3, q0.y), Vector3(q1.x, y0 + 5.3, q1.y), 0.7, 0.8, SEED_BASE * 5 + i)
	# The big timber cross at the lane's mouth, on a stone base (the real lane has one).
	var lane: Rect2 = L.lane
	var cp := Vector2(lane.end.x + 2.5, lane.end.y + 3.0)
	g.box("trim", Vector3(cp.x, y0 + 0.4, cp.y), Vector3(1.6, 0.8, 1.6), Color(0.8, 0.78, 0.74), Basis(), 0.05)
	g.box("timber", Vector3(cp.x, y0 + 4.2, cp.y), Vector3(0.35, 6.8, 0.35), Color(0.75, 0.75, 0.75))
	g.box("timber", Vector3(cp.x, y0 + 5.9, cp.y), Vector3(0.35, 0.35, 2.6), Color(0.75, 0.75, 0.75))
	LandmarkGeo.shape_box(statics, Vector3(cp.x, y0 + 3.4, cp.y), Vector3(1.6, 6.8, 1.6))


## Over the lane: papel picado strung across from front to front, bulb strings down its length,
## lanterns at the mouth.
static func _lane_detail(g: LandmarkGeo, solid: PuebloMarket.Acc, thin: PuebloMarket.Acc, statics: StaticBody3D, L: Dictionary, y0: float) -> void:
	var lane: Rect2 = L.lane
	var n := int(lane.size.y / 5.5)
	for i in n:
		var z := lane.position.y + 3.0 + 5.5 * float(i)
		var dz := 1.5 * (h01([SEED_BASE, "pz", i]) - 0.5)
		var a := Vector3(lane.position.x + 0.2, y0 + 4.1, z)
		var b := Vector3(lane.end.x - 0.2, y0 + 4.1, z + dz)
		PuebloMarket.picado(thin, solid, a, b, 0.55, SEED_BASE * 7 + i)
	for x: float in [lane.position.x + 3.3, lane.end.x - 3.3]:
		var segs := int(lane.size.y / PERGOLA_PITCH)
		for i in segs:
			var z0 := lane.position.y + PERGOLA_PITCH * float(i)
			PuebloMarket.bulbs(solid, Vector3(x, y0 + PERGOLA_H - 0.25, z0), Vector3(x, y0 + PERGOLA_H - 0.25, z0 + PERGOLA_PITCH), 0.35, 0.65, SEED_BASE * 11 + i * 2 + int(x))


## Warm pools of light down the lane's two aisles (the bulbs' light on the bricks, after dark).
static func _lane_pools(batch: MultiMeshBatch, L: Dictionary, y0: float) -> void:
	var lane: Rect2 = L.lane
	var pool := PropFactory.light_pool(Color(1.0, 0.72, 0.42), 0.9)
	var n := int(lane.size.y / 5.0)
	for i in n:
		var z := lane.position.y + 2.5 + 5.0 * float(i)
		for x: float in [lane.position.x + 2.6, lane.end.x - 2.6]:
			batch.add("pueblo_lane_pool", pool, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(6.5, 1.0, 6.5)), Vector3(x, y0 + 0.1, z)))
	batch.set_no_shadow("pueblo_lane_pool")


## The pergola: posts at the lane's edges, beams across, joists along, the vines on top (grape and
## wisteria from ClimbingPlants' atlas), and its leaves' shadow twin.
static func _pergola(parent: Node3D, g: LandmarkGeo, statics: StaticBody3D, L: Dictionary, y0: float) -> void:
	var lane: Rect2 = L.lane
	var xa := lane.position.x + 0.35
	var xb := lane.end.x - 0.35
	var n := int(lane.size.y / PERGOLA_PITCH)
	var H := PERGOLA_H
	for i in n + 1:
		var z := lane.position.y + lane.size.y * float(i) / float(n)
		for x: float in [xa, xb]:
			g.box("timber", Vector3(x, y0 + H * 0.5, z), Vector3(0.22, H, 0.22), Color.WHITE)
			LandmarkGeo.shape_box(statics, Vector3(x, y0 + H * 0.5, z), Vector3(0.22, H, 0.22))
		g.box("timber", Vector3(lane.get_center().x, y0 + H + 0.12, z), Vector3(xb - xa + 0.8, 0.24, 0.16), Color.WHITE)
	var nj := int((xb - xa) / 0.75)
	for j in nj + 1:
		var x := xa + (xb - xa) * float(j) / float(nj)
		g.box("timber", Vector3(x, y0 + H + 0.31, lane.get_center().y), Vector3(0.08, 0.14, lane.size.y + 0.6), Color(0.92, 0.92, 0.92))
	# The vines: cards over the joists, ragged by noise so the sun comes through in patches,
	# leaves hanging under the beams, grape bunches and wisteria racemes.
	var leaf := ClimbingPlants.Acc.new()
	var shade := ClimbingPlants.Acc.new()
	leaf.fade = 160.0
	shade.fade = 90.0
	var top := y0 + H + 0.42
	var step := 0.42
	var cards := 0
	var x := xa - 0.2
	var ix := 0
	while x < xb + 0.2:
		var z := lane.position.y
		var iz := 0
		while z < lane.end.y:
			var hsh := [SEED_BASE, "vine", ix, iz]
			var hx := h01(hsh + ["x"])
			var hz := h01(hsh + ["z"])
			var px := x + (hx - 0.5) * step * 0.8
			var pz := z + (hz - 0.5) * step * 0.8
			# Patches: a slow noise over the lane decides where the vine is thick or open.
			var patch := 0.5 + 0.5 * sin(pz * 0.37 + sin(px * 0.9) * 1.3) * cos(pz * 0.13 + 1.7)
			var wisteria := sin(pz * 0.045 + 2.0) > 0.55
			if h01(hsh + ["keep"]) < 0.55 + 0.45 * patch:
				var ang := TAU * h01(hsh + ["a"])
				var tilt := Vector3(h01(hsh + ["tx"]) - 0.5, 0.0, h01(hsh + ["tz"]) - 0.5) * 0.8
				var axes := ClimbingPlants._flat_axes(Vector3(1, 0, 0), (Vector3.UP + tilt).normalized(), ang)
				var is_mass := h01(hsh + ["m"]) < 0.6
				var cell: int = (ClimbingPlants.C_WIST_MASS if wisteria else ClimbingPlants.C_GRAPE_MASS) if is_mass else \
					((ClimbingPlants.C_WIST_LEAF if wisteria else ClimbingPlants.C_GRAPE_LEAF)[hash(hsh + ["c"]) % 2])
				var p := Vector3(px, top + 0.2 * h01(hsh + ["y"]), pz)
				var tint := Color(0.85 + 0.3 * h01(hsh + ["r"]), 0.9 + 0.2 * h01(hsh + ["g"]), 0.85 + 0.2 * h01(hsh + ["b"]))
				var w := 0.9 if is_mass else 0.7
				ClimbingPlants._card_into(leaf, p, axes[0], axes[1], Vector3.UP, w, w, cell, tint, 0.15, 0.4, 0.0, 0.06)
				cards += 1
				if cards % 3 == 0:
					ClimbingPlants._card_into(shade, p, axes[0], axes[1], Vector3.UP, w * 1.35, w * 1.35, cell, tint, 0.15, 0.4, 0.0, 0.06)
				# Leaves seen from below, hanging off the joists.
				if h01(hsh + ["low"]) < 0.35:
					var a3 := TAU * h01(hsh + ["a3"])
					var ay3 := (Vector3(sin(a3), 0.0, cos(a3)) * 0.5 - Vector3.UP).normalized()
					var ax3 := Vector3(cos(a3), 0.0, -sin(a3))
					ClimbingPlants._card_into(leaf, p - Vector3.UP * 0.32, ax3, ay3, Vector3.DOWN, 0.55, 0.55,
						(ClimbingPlants.C_WIST_LEAF if wisteria else ClimbingPlants.C_GRAPE_LEAF)[hash(hsh + ["c3"]) % 2], tint * 0.85, 0.3, 0.6, 0.0, 0.0)
				# Hanging racemes or bunches.
				if h01(hsh + ["hang"]) < (0.2 if wisteria else 0.06):
					var len := 0.35 + 0.3 * h01(hsh + ["len"]) if wisteria else 0.22
					var cell2: int = ClimbingPlants.C_WIST_FLOWER[hash(hsh + ["fl"]) % 2] if wisteria else ClimbingPlants.C_GRAPE
					var a2 := PI * h01(hsh + ["a2"])
					var axh := Vector3(cos(a2), 0.0, sin(a2))
					var hp := Vector3(px, top - 0.12 - len * 0.5, pz)
					ClimbingPlants._card_into(leaf, hp, axh, Vector3.UP, axh.cross(Vector3.UP).normalized(), len * (0.45 if wisteria else 0.8), len, cell2, Color(1, 1, 1), 0.6, 0.2, 1.0, 0.0)
			z += step
			iz += 1
		x += step
		ix += 1
	# A vine trunk up every other post.
	for i in range(0, n + 1, 2):
		var z := lane.position.y + lane.size.y * float(i) / float(n)
		for xx: float in [xa, xb]:
			for k in 6:
				var y := y0 + (float(k) + 0.5) * H / 6.0
				ClimbingPlants._card_into(leaf, Vector3(xx + 0.14 * signf(lane.get_center().x - xx), y, z + 0.12), Vector3(0, 0, 1), Vector3.UP, Vector3(signf(lane.get_center().x - xx), 0, 0), 0.22, H / 6.0 * 1.2, ClimbingPlants.C_WOOD, Color(0.9, 0.9, 0.9), 0.0, 0.0, 0.0, 0.0)
	var lm := leaf.mesh(ClimbingPlants.material())
	var mi := MeshInstance3D.new()
	mi.name = "PergolaVines"
	mi.mesh = lm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 170.0
	parent.add_child(mi)
	var sm := shade.mesh(ClimbingPlants.material())
	var si := MeshInstance3D.new()
	si.name = "PergolaVinesShadow"
	si.mesh = sm
	si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	si.visibility_range_end = 110.0
	parent.add_child(si)
	parent.set_meta("pergola_cards", cards)


## What fills the rest of the block: the gardens, the adobe's courtyard, the car parks, the
## north forecourt with its gateway sign; lights.
static func _fill(g: LandmarkGeo, batch: MultiMeshBatch, parent: Node3D, statics: StaticBody3D, L: Dictionary, y0: float) -> void:
	var garden: Rect2 = L.garden
	if garden.size.x > 20.0 and garden.size.y > 20.0:
		ArenaGrounds.bosque(g, batch, garden.grow(-4.0), y0 + 0.05, 13.0, SEED_BASE + 21)
	var court: Rect2 = L.court
	if court.size.x > 8.0 and court.size.y > 8.0:
		ArenaGrounds.bed(g, batch, statics, Rect2(court.position + Vector2(3.0, 3.0), Vector2(court.size.x - 6.0, 3.0)), y0 + 0.05, SEED_BASE + 22, 0.0, false, false)
		var tv := 2
		var sc := PropFactory.city_tree_scale(tv, 10.0)
		batch.add("tree_%d" % tv, PropFactory.model_tree(tv), Transform3D(Basis().scaled(Vector3(sc, sc, sc)), Vector3(court.get_center().x, y0 + 0.08, court.get_center().y + 4.0)), Color.WHITE, Color(0.5, 0.5, 0.5, 0.8))
	var lot: Rect2 = L.east_lot
	ArenaGrounds.surface_lot(g, batch, parent, lot, y0 + 0.01, SEED_BASE + 23)
	var south_lot: Rect2 = L.south_lot
	ArenaGrounds.surface_lot(g, batch, parent, south_lot, y0 + 0.01, SEED_BASE + 24)
	ArenaGrounds.surface_lot(g, batch, parent, L.east_lot2, y0 + 0.01, SEED_BASE + 27)
	# The north forecourt: palms, and the gateway over the lane's north end with its name.
	var north: Rect2 = L.north
	var lane: Rect2 = L.lane
	if north.size.y > 10.0:
		ArenaGrounds.bed(g, batch, statics, Rect2(Vector2(north.position.x + 3.0, north.position.y + 3.0), Vector2(lane.position.x - north.position.x - 6.0, 4.0)), y0 + 0.05, SEED_BASE + 25, 9.0, true, true)
		ArenaGrounds.bed(g, batch, statics, Rect2(Vector2(lane.end.x + 3.0, north.position.y + 3.0), Vector2(north.end.x - lane.end.x - 6.0, 4.0)), y0 + 0.05, SEED_BASE + 26, 9.0, true, true)
	var gz := lane.position.y
	for sg: float in [-1.0, 1.0]:
		var gp := Vector3(lane.get_center().x + sg * (LANE_HALF + 0.2), y0 + 3.4, gz)
		g.box("adobe", gp, Vector3(1.2, 6.8, 1.2), Color(1.0, 0.95, 0.88), Basis(), 0.05)
		LandmarkGeo.shape_box(statics, gp, Vector3(1.2, 6.8, 1.2))
	g.box("timber", Vector3(lane.get_center().x, y0 + 6.3, gz), Vector3(LANE_HALF * 2.0 + 1.6, 0.9, 0.4), Color.WHITE)
	var name_batch := MultiMeshBatch.new()
	for sg: float in [-1.0, 1.0]:
		name_batch.add("pueblo_name", Signage.text_mesh(NAME, 0.48, Signage.Letters.PRINT),
			Transform3D(LandmarkArenaDistrict._face(0.0 if sg < 0.0 else PI, 1.0), Vector3(lane.get_center().x, y0 + 6.2, gz + sg * 0.22)), Color(0.95, 0.85, 0.55))
	name_batch.set_no_shadow("pueblo_name")
	name_batch.build(parent)
	# Real light where it matters after dark: the lane, the plaza, the church's front.
	var p: Vector2 = L.p
	for i in 3:
		LandmarkArenaDistrict._add_light(parent, Vector3(lane.get_center().x, y0 + 3.6, lane.position.y + lane.size.y * (float(i) + 0.5) / 3.0), 18.0)
	LandmarkArenaDistrict._add_light(parent, Vector3(p.x, y0 + 4.0, p.y), 24.0)
