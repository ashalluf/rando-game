class_name MarinaBuild
extends RefCounted
## Builds a chunk's share of the marina (Marina is the plan). A marina block (Marina.owns_block())
## builds `attach()`'s steps instead of a seeded block: its roads, the sand where it holds the
## shore, the water, the land and its bulkheads, the docks, pilings and gangways, the boats, the
## buildings, the boat yard, the palms, lamps and car parks, the lights; any chunk the marina
## reaches outside its blocks (the channel across the sand, the jetties, the highway's bridge, the
## breakwater out at sea) runs `extras()`. LOD chunks build the same with the far boats and no
## props; the far city's capture (`capture()`) records slabs, boxes and masts.
##
## Ownership: a polygon is clipped to the chunk's owned rect, a feature (dock, boat, pile,
## building, light) is built by the chunk its centre falls in, a line by the chunk its midpoint
## falls in. Every roll was made by the plan (hashes); nothing here draws a random number.
##
## Meshes, one per material a chunk (no node per piece): the water (marina_water.gdshader), the
## land by ground kind (road.gdshader pavers / asphalt / concrete, the lawn shader, the bike
## path), the concrete (bulkheads, copings, the bridge, the lift well), the rubble (jetties,
## breakwater: the "rock" set, with Poly Haven boulders on the crest in a batch), the docks
## (pontoons and fingers, timber decks), the steel (rails, the travel lift, cleats). The boats are
## MultiMeshes (BoatMesh, boat.gdshader) grouped by type and dock, each group three nodes with
## visibility ranges (NEAR / MID / FAR) - a batch picks one LOD for all its instances, so a group
## is kept to a dock's length. The lights (masthead glows, dock pedestals, nav lights) are one
## billboard mesh on aircraft_lights.gdshader.

const FAR_WATER := Color(0.035, 0.07, 0.085)
const FAR_LAND := Color(0.42, 0.41, 0.38)
const FAR_ASPHALT := Color(0.11, 0.11, 0.115)
const FAR_LAWN := Color(0.16, 0.24, 0.09)
const FAR_DOCK := Color(0.55, 0.53, 0.5)
const FAR_ROCK := Color(0.3, 0.29, 0.27)
const FAR_HULL := Color(0.8, 0.8, 0.79)

## Where each boat level is drawn (metres from the camera to the group's centre).
const NEAR_RANGE := 70.0
const MID_RANGE := 230.0
## Boats per group (a dock's boats of one type), so a group's LOD fits its spread.
const DOCK_LIGHT_EVERY := 3

var ch: CityChunk
var plan: CityPlan
var mr: Marina
var area: Rect2
var full := false
var lod := false
var capturing := false
var _st: Dictionary = {}
var _faces := PackedVector3Array()
var _lights: Array = []
var top_y := 0.0

static var _mats: Dictionary = {}


# --- Entry points --------------------------------------------------------------------------------

## The steps of a marina block (instead of the seeded block's).
static func attach(c: CityChunk, block: Dictionary) -> Array[Callable]:
	var b := MarinaBuild.new()
	b._setup(c)
	c.set_meta("marina_build", b)
	var steps: Array[Callable] = []
	steps.append(func() -> void: c._build_roads(block))
	if c.level == CityChunk.Level.FULL:
		steps.append(func() -> void: c._build_intersection(c.plan.intersection(c.ix + 1, c.iz + 1)))
	if c._owns_shoreline():
		steps.append(func() -> void: c._build_beach(block))
	steps.append(c._build_hill_roads)
	steps.append(b._water_step)
	steps.append(b._land_step)
	steps.append(b._bank_step)
	steps.append(b._dock_step)
	steps.append(b._boat_step)
	steps.append(b._building_step)
	steps.append(b._props_step)
	steps.append(b._yard_step)
	steps.append_array(b._extra_steps())
	steps.append(b._commit_step)
	return steps


## The steps for any other chunk the marina reaches (channel, jetties, bridge, breakwater), or [].
static func extras(c: CityChunk) -> Array[Callable]:
	var out: Array[Callable] = []
	var macro: MacroMap = c.plan.macro
	if macro == null or macro.marina == null or c.plan.marina_block(c.ix, c.iz):
		return out
	if not macro.marina.outer_bounds().intersects(c.owned_rect()):
		return out
	var b := MarinaBuild.new()
	b._setup(c)
	c.set_meta("marina_build", b)
	if c.capturing:
		out.append(b._capture_extras)
		return out
	out.append_array(b._extra_steps())
	out.append(b._commit_step)
	return out


## The far city's record of a marina block (CityChunk.capturing).
static func capture(c: CityChunk) -> void:
	var b := MarinaBuild.new()
	b._setup(c)
	b._capture_block()
	b._capture_extras()


## A beach chunk's sand rects less the channel's band (the jetties stand on its edges).
static func sand_rects(c: CityChunk, rect: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = [rect]
	var macro: MacroMap = c.plan.macro
	if macro == null or macro.marina == null:
		return out
	var mr := macro.marina
	var z0 := mr.zc - Marina.CHANNEL_HALF - 6.0
	var z1 := mr.zc + Marina.CHANNEL_HALF + 6.0
	if rect.end.y <= z0 or rect.position.y >= z1:
		return out
	out.clear()
	if z0 > rect.position.y + 0.5:
		out.append(Rect2(rect.position.x, rect.position.y, rect.size.x, z0 - rect.position.y))
	if z1 < rect.end.y - 0.5:
		out.append(Rect2(rect.position.x, z1, rect.size.x, rect.end.y - z1))
	return out


## True when `at` (chunk space = world XZ) is within `pad` of the channel's band on the sand.
static func on_channel(c: CityChunk, at: Vector3, pad: float) -> bool:
	var macro: MacroMap = c.plan.macro
	if macro == null or macro.marina == null:
		return false
	return absf(at.z - macro.marina.zc) < Marina.CHANNEL_HALF + 6.0 + pad


## Circles ([point, radius]) BeachLife's towels, umbrellas and people keep out of: the channel's
## band and its jetties across this chunk's sand.
static func beach_obstacles(c: CityChunk) -> Array:
	var out: Array = []
	var macro: MacroMap = c.plan.macro
	if macro == null or macro.marina == null:
		return out
	var mr := macro.marina
	var area := c.owned_rect().grow(40.0)
	if mr.zc < area.position.y or mr.zc > area.end.y:
		return out
	var x := mr.channel.position.x
	while x < mr.sand_x(mr.zc) + 10.0:
		out.append([Vector2(x, mr.zc), Marina.CHANNEL_HALF + 16.0])
		x += 12.0
	return out


## The coast highway's segments less the bridge's gap (the bridge is MarinaBuild's).
static func filter_segments(c: CityChunk, segs: Array[Dictionary]) -> Array[Dictionary]:
	var macro: MacroMap = c.plan.macro
	if macro == null or macro.marina == null:
		return segs
	var gap := macro.marina.pch_gap()
	var out: Array[Dictionary] = []
	for seg in segs:
		if str(seg.get("name", "")) == "Pacific Coast Highway" or seg.get("coast", false):
			var mid: Vector2 = (seg.a as Vector2).lerp(seg.b, 0.5)
			if mid.y > gap.x + 0.5 and mid.y < gap.y - 0.5:
				continue
		out.append(seg)
	return out


## How far a marina block's far plate goes down: to the water.
static func far_plate_drop(c: CityChunk) -> float:
	var mid := c.owned_rect().get_center()
	return maxf(c._gy(mid.x, mid.y) + Skyline.PLATE_TOP - Marina.WATER_Y - 0.05, 0.0)


func _setup(c: CityChunk) -> void:
	ch = c
	plan = c.plan
	mr = plan.macro.marina
	area = c.owned_rect()
	capturing = c.capturing
	full = c.level == CityChunk.Level.FULL and not capturing
	lod = not full
	top_y = Marina.QUAY_Y + CityChunk.SIDEWALK_TOP


func _extra_steps() -> Array[Callable]:
	var out: Array[Callable] = []
	if mr.channel.grow(16.0).intersects(area) or mr.breakwater_rect().intersects(area):
		out.append(_channel_step)
		out.append(_mound_step)
	var gap := mr.pch_gap()
	if area.intersects(Rect2(mr.pch_x(gap.x) - 30.0, gap.x, 80.0, gap.y - gap.x)):
		out.append(_bridge_step)
	if not capturing:
		out.append(_lights_step)
		out.append(_traffic_step)
	return out


# --- Mesh helpers ---------------------------------------------------------------------------------

func _surf(key: String) -> SurfaceTool:
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
	return _st[key]


## A triangle facing `want` (flat normal, UV world XZ or face metres), on surface `key`.
func tri(key: String, a: Vector3, b: Vector3, c: Vector3, want: Vector3, collide := true, col := Color.WHITE) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	if n.dot(want) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	var st := _surf(key)
	var horiz := absf(n.y) > 0.7
	var u_axis := Vector3(n.z, 0.0, -n.x).normalized() if not horiz else Vector3.RIGHT
	for p: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		if horiz:
			st.set_uv(Vector2(p.x, p.z))
		else:
			st.set_uv(Vector2(p.dot(u_axis), p.y))
		st.add_vertex(p)
	if collide:
		_faces.append(a)
		_faces.append(b)
		_faces.append(c)


func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, collide := true, col := Color.WHITE) -> void:
	tri(key, a, b, c, want, collide, col)
	tri(key, a, c, d, want, collide, col)


## A box (frame `xf`, size) on surface `key`.
func box(key: String, xf: Transform3D, size: Vector3, collide := true, bottom := false, col := Color.WHITE) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for k in 8:
		p.append(xf * Vector3(h.x * (1.0 if k & 1 else -1.0), h.y * (1.0 if k & 2 else -1.0), h.z * (1.0 if k & 4 else -1.0)))
	var faces := [[2, 3, 7, 6, Vector3.UP], [0, 1, 3, 2, Vector3.FORWARD], [4, 5, 7, 6, Vector3.BACK], [0, 2, 6, 4, Vector3.LEFT], [1, 3, 7, 5, Vector3.RIGHT]]
	if bottom:
		faces.append([0, 1, 5, 4, Vector3.DOWN])
	for f: Array in faces:
		quad(key, p[f[0]], p[f[1]], p[f[2]], p[f[3]], xf.basis * (f[4] as Vector3), collide, col)


## A box for collision only (nothing drawn).
func collide_box(xf: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for k in 8:
		p.append(xf * Vector3(h.x * (1.0 if k & 1 else -1.0), h.y * (1.0 if k & 2 else -1.0), h.z * (1.0 if k & 4 else -1.0)))
	for f: Array in [[2, 3, 7, 6], [0, 1, 3, 2], [4, 5, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5], [0, 1, 5, 4]]:
		_faces.append_array(PackedVector3Array([p[f[0]], p[f[1]], p[f[2]], p[f[0]], p[f[2]], p[f[3]]]))


## A box between two points on the ground plane (a strip `w` wide, `h` thick, top at `top`).
func strip(key: String, a: Vector2, b: Vector2, w: float, top: float, h: float, collide := true) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var yaw := atan2(-d.x, -d.y)
	var c := (a + b) * 0.5
	box(key, Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, top - h * 0.5, c.y)), Vector3(w, h, len), collide)


## A flat polygon (world XZ) at height `y`, facing up.
func poly_top(key: String, poly: PackedVector2Array, y: float, collide := true) -> void:
	var ids := Geometry2D.triangulate_polygon(poly)
	for i in range(0, ids.size(), 3):
		var a := poly[ids[i]]
		var b := poly[ids[i + 1]]
		var c := poly[ids[i + 2]]
		tri(key, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3.UP, collide)


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Polygons of `poly` inside the chunk's area.
func _clip(poly: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for q: PackedVector2Array in Geometry2D.intersect_polygons(poly, _rect_poly(area)):
		if not Geometry2D.is_polygon_clockwise(q) and q.size() >= 3:
			out.append(q)
	return out


## Segment a-b clipped to the area, or [].
func _clip_seg(a: Vector2, b: Vector2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for k in 4:
		var p: float
		var q: float
		match k:
			0:
				p = -d.x
				q = a.x - area.position.x
			1:
				p = d.x
				q = area.end.x - a.x
			2:
				p = -d.y
				q = a.y - area.position.y
			_:
				p = d.y
				q = area.end.y - a.y
		if absf(p) < 1e-9:
			if q < 0.0:
				return []
			continue
		var r := q / p
		if p < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
		if t0 > t1:
			return []
	return [a + d * t0, a + d * t1]


func _owns(p: Vector2) -> bool:
	return area.has_point(p)


# --- Materials ------------------------------------------------------------------------------------

static func water_material() -> ShaderMaterial:
	if not _mats.has("water"):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/marina_water.gdshader")
		_mats["water"] = m
	return _mats["water"]


static func boat_material() -> ShaderMaterial:
	if not _mats.has("boat"):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/boat.gdshader")
		_mats["boat"] = m
	return _mats["boat"]


static func light_material() -> ShaderMaterial:
	if not _mats.has("lights"):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/aircraft_lights.gdshader")
		m.set_shader_parameter("min_angle", 0.0032)
		m.set_shader_parameter("hdr", 3.0)
		m.set_shader_parameter("day_level", 0.0)
		m.set_shader_parameter("field_day", 0.0)
		_mats["lights"] = m
	return _mats["lights"]


static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"pavers":
			m = PropFactory.road("pavers", 2.6, Color(1.08, 1.03, 0.96), 4021, 0.0, 0.35)
		"asphalt":
			m = PropFactory.road("asphalt", 7.0, Color(0.86, 0.86, 0.88), 4022, 0.0, 0.8)
		"concrete":
			m = PropFactory.road("concrete", 4.0, Color(0.92, 0.91, 0.88), 4023, 3.0, 0.9)
		"bulkhead":
			m = PropFactory.road("concrete", 3.0, Color(0.86, 0.85, 0.82), 4024, 0.0, 1.0)
		"lawn":
			m = PropFactory.lawn(Color(0.82, 0.95, 0.7), 4025, 0.3)
		"bank":
			m = PropFactory.lawn(Color(0.72, 0.86, 0.55), 4026, 0.55, 0.0)
		"bike":
			m = PropFactory.road("asphalt", 6.0, Color(1.35, 0.78, 0.66), 4027, 0.0, 0.3)
		"rock":
			m = PropFactory.pbr("rock", 3.2, Color(0.82, 0.8, 0.76))
		"deck":
			m = PropFactory.pbr("planks", 2.2, Color(0.82, 0.74, 0.64))
		"float":
			m = PropFactory.pbr("concrete", 2.0, Color(0.9, 0.9, 0.88))
		"pile":
			m = PropFactory.pbr("concrete", 1.5, Color(0.78, 0.77, 0.74))
		"steel":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.62, 0.64, 0.66)
			s.metallic = 0.8
			s.roughness = 0.35
			m = s
		"blue":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.1, 0.27, 0.55)
			s.metallic = 0.4
			s.roughness = 0.45
			m = s
		"white":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.9, 0.9, 0.88)
			s.roughness = 0.5
			m = s
		"rubber":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.05, 0.05, 0.055)
			s.roughness = 0.8
			m = s
		"stripe":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.92, 0.92, 0.88)
			s.roughness = 0.7
			m = s
		_:
			m = PropFactory.material(Color(0.7, 0.7, 0.7))
	_mats[key] = m
	return m


# --- The water ------------------------------------------------------------------------------------

func _water_step() -> void:
	for q in _clip(mr.water):
		poly_top("water", q, Marina.WATER_Y, false)


# --- The land -------------------------------------------------------------------------------------

func _land_step() -> void:
	var keys := {Marina.Ground.PAVERS: "pavers", Marina.Ground.ASPHALT: "asphalt", Marina.Ground.CONCRETE: "concrete", Marina.Ground.LAWN: "lawn", Marina.Ground.BIKE: "bike"}
	for g: Dictionary in mr.grounds:
		var key: String = keys[g.kind]
		var y := top_y + (0.01 if g.kind == Marina.Ground.LAWN else 0.0)
		for q in _clip(g.poly):
			poly_top(key, q, y)
	# The car parks' asphalt over the plazas (a hair above).
	for cp: Rect2 in mr.car_parks:
		for q in _clip(_rect_poly(cp)):
			poly_top("asphalt", q, top_y + 0.012, false)
	# The bike path along the west promenade: a red-asphalt strip, its dashed centre line.
	for i in mr.bike_path.size() - 1:
		var a := mr.bike_path[i]
		var b := mr.bike_path[i + 1]
		if absf((a.y + b.y) * 0.5 - mr.zc) < Marina.CHANNEL_HALF + 2.0:
			continue
		if not _owns((a + b) * 0.5):
			continue
		strip("bike", a, b, 3.0, top_y + 0.02, 0.05, false)
		if full:
			var d := (b - a)
			var n := int(d.length() / 3.0)
			for k in n:
				var t0 := (float(k) + 0.1) / n
				var t1 := (float(k) + 0.5) / n
				strip("stripe", a + d * t0, a + d * t1, 0.12, top_y + 0.026, 0.01, false)
	# Bulkheads: every water edge that borders the land, a wall down into the water with a coping.
	var w := mr.water
	for i in w.size():
		var a := w[i]
		var b := w[(i + 1) % w.size()]
		_bulkhead(a, b)
	# The land's outer edges that meet a road (the kerb face) or the sand bank: a skirt down.
	var lo := mr.land
	for i in lo.size():
		var a := lo[i]
		var b := lo[(i + 1) % lo.size()]
		var seg := _clip_seg(a, b)
		if seg.is_empty():
			continue
		var p0: Vector2 = seg[0]
		var p1: Vector2 = seg[1]
		if p0.distance_to(p1) < 0.05:
			continue
		var mid := (p0 + p1) * 0.5
		if mr.in_water(mid + (b - a).normalized().rotated(PI * 0.5) * 0.6) or mr.in_water(mid - (b - a).normalized().rotated(PI * 0.5) * 0.6):
			continue
		var out := Vector3(-(b - a).y, 0.0, (b - a).x).normalized()
		# Outward: away from the site's centre.
		var cen := mr.site.get_center()
		if out.dot(Vector3(mid.x - cen.x, 0.0, mid.y - cen.y)) < 0.0:
			out = -out
		var g0 := ch._gy(p0.x, p0.y) + CityChunk.ROAD_TOP - 0.3
		var g1 := ch._gy(p1.x, p1.y) + CityChunk.ROAD_TOP - 0.3
		quad("concrete", Vector3(p0.x, top_y, p0.y), Vector3(p1.x, top_y, p1.y), Vector3(p1.x, g1, p1.y), Vector3(p0.x, g0, p0.y), out)


## A bulkhead along water edge a-b where it borders the land: the wall face from the coping down
## under the water, the coping a slab along the top edge.
func _bulkhead(a: Vector2, b: Vector2) -> void:
	var seg := _clip_seg(a, b)
	if seg.is_empty():
		return
	var p0: Vector2 = seg[0]
	var p1: Vector2 = seg[1]
	var len := p0.distance_to(p1)
	if len < 0.05:
		return
	var d := (p1 - p0) / len
	# The water side: the normal toward the water polygon.
	var n := Vector2(-d.y, d.x)
	var mid := (p0 + p1) * 0.5
	if not mr.in_water(mid + n * 0.8):
		n = -n
	# Only where land stands behind it (east of the sand's bank: the channel's banks out on the
	# sand are the jetties' rubble instead).
	var pieces := 6
	var k := 0
	while k < pieces:
		var q0 := p0.lerp(p1, float(k) / pieces)
		var q1 := p0.lerp(p1, float(k + 1) / pieces)
		k += 1
		var qm := (q0 + q1) * 0.5 - n * 1.0
		if qm.x < mr.sand_x(qm.y) + Marina.BANK - 0.5:
			continue
		if not mr.site.grow(0.5).has_point(qm):
			continue
		var want := Vector3(n.x, 0.0, n.y)
		quad("bulkhead", Vector3(q0.x, top_y + 0.06, q0.y), Vector3(q1.x, top_y + 0.06, q1.y), Vector3(q1.x, -1.6, q1.y), Vector3(q0.x, -1.6, q0.y), want)
		# Coping: a 0.45 m cap a little proud of the paving.
		var i0 := q0 - n * 0.45
		var i1 := q1 - n * 0.45
		quad("bulkhead", Vector3(q0.x, top_y + 0.06, q0.y), Vector3(q1.x, top_y + 0.06, q1.y), Vector3(i1.x, top_y + 0.06, i1.y), Vector3(i0.x, top_y + 0.06, i0.y), Vector3.UP)
		quad("bulkhead", Vector3(i0.x, top_y + 0.06, i0.y), Vector3(i1.x, top_y + 0.06, i1.y), Vector3(i1.x, top_y, i1.y), Vector3(i0.x, top_y, i0.y), -want, false)


## The planted bank from the sand's edge up to the promenade (west side), where this chunk owns it.
func _bank_step() -> void:
	var e := mr.sand_edge
	for i in e.size() - 1:
		var a := e[i]
		var b := e[i + 1]
		var mid := (a + b) * 0.5
		if mid.y < mr.site.position.y or mid.y > mr.site.end.y or not _owns(mid):
			continue
		if absf(mid.y - mr.zc) < Marina.CHANNEL_HALF + 1.0:
			continue
		var lo := 0.5
		quad("bank", Vector3(a.x, lo, a.y), Vector3(b.x, lo, b.y), Vector3(b.x + Marina.BANK, top_y, b.y), Vector3(a.x + Marina.BANK, top_y, a.y), Vector3(-1.0, 1.4, 0.0))
		if full and i % 2 == 0:
			# Ice plant and shrubs down the bank.
			var at := Vector3(mid.x + Marina.BANK * 0.5, (lo + top_y) * 0.5 - Marina.QUAY_Y, mid.y)
			var v := int(mr.h01(["bank", i]) * 3.0)
			ch._batch.add("mr_bush", PropFactory.model_bush(v), Transform3D(Basis(Vector3.UP, mr.h01(["bank_y", i]) * TAU).scaled(Vector3.ONE * lerpf(0.7, 1.2, mr.h01(["bank_s", i]))), at), Color(0.9, 0.95, 0.8))


# --- Docks ----------------------------------------------------------------------------------------

func _dock_step() -> void:
	var y := Marina.DOCK_Y
	for d: Dictionary in mr.docks:
		var a: Vector2 = d.a
		var b: Vector2 = d.b
		if not _owns((a + b) * 0.5):
			continue
		var w: float = d.w
		var kind: String = d.kind
		if lod:
			strip("float", a, b, w, y, 0.5, false)
			continue
		# The float: concrete sides, a timber deck on top, a rubber rub rail along the edges.
		var dir := (b - a).normalized()
		var n := Vector2(-dir.y, dir.x)
		strip("float", a, b, w, y - 0.06, 0.62)
		strip("deck", a + dir * 0.05, b - dir * 0.05, w - 0.1, y, 0.06)
		if kind != "finger":
			for s: float in [-1.0, 1.0]:
				strip("rubber", a + n * s * (w * 0.5 + 0.03), b + n * s * (w * 0.5 + 0.03), 0.07, y - 0.08, 0.16, false)
		# Cleats and, on the main docks and headwalks, utility pedestals with a lamp.
		var len := a.distance_to(b)
		if kind == "finger":
			for t: float in [0.35, 0.92]:
				var p := a.lerp(b, t)
				for s: float in [-1.0, 1.0]:
					var q := p + n * s * (w * 0.5 - 0.12)
					box("steel", Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(q.x, y + 0.06, q.y)), Vector3(0.06, 0.08, 0.3), false)
		else:
			var count := int(len / 9.4)
			for k in count:
				var p := a.lerp(b, (float(k) + 0.5) / count)
				if k % DOCK_LIGHT_EVERY == 0:
					var s := 1.0 if k % 2 == 0 else -1.0
					var q := p + n * s * (w * 0.5 - 0.35)
					box("white", Transform3D(Basis(), Vector3(q.x, y + 0.55, q.y)), Vector3(0.32, 1.1, 0.26), false)
					box("blue", Transform3D(Basis(), Vector3(q.x, y + 1.14, q.y)), Vector3(0.36, 0.08, 0.3), false)
					_lights.append([Vector3(q.x, y + 1.22, q.y), Color(1.0, 0.82, 0.55, 0.9), 0.45, 4, 0.0])
					if full:
						var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(7.0, 1.0, 7.0)), Vector3(q.x, y + 0.08 - ch._gy(q.x, q.y), q.y))
						ch._batch.add("mr_pool", PropFactory.light_pool(Color(1.0, 0.84, 0.6), 0.8), pool)
	ch._batch.set_no_shadow("mr_pool")
	# Pilings: concrete with a white cap, from under the water to well over the deck.
	for p: Vector2 in mr.piles:
		if not _owns(p):
			continue
		if lod:
			box("pile", Transform3D(Basis(), Vector3(p.x, 1.5, p.y)), Vector3(0.4, 3.6, 0.4), false)
			continue
		_pile(p)
	# Gangways: a ramp from the quay down to the headwalk with handrails, a gate at the top.
	for g: Dictionary in mr.gangways:
		var top: Vector2 = g.top
		var bot: Vector2 = g.bottom
		if not _owns((top + bot) * 0.5):
			continue
		_gangway(top, bot, g.w)


func _pile(p: Vector2) -> void:
	var sides := 8
	var r := 0.2
	var y0 := -1.2
	var y1 := Marina.DOCK_Y + 2.7
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var q0 := p + Vector2(cos(a0), sin(a0)) * r
		var q1 := p + Vector2(cos(a1), sin(a1)) * r
		var out := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		quad("pile", Vector3(q0.x, y0, q0.y), Vector3(q1.x, y0, q1.y), Vector3(q1.x, y1, q1.y), Vector3(q0.x, y1, q0.y), out)
		# The white cap.
		var c0 := p + Vector2(cos(a0), sin(a0)) * (r + 0.03)
		var c1 := p + Vector2(cos(a1), sin(a1)) * (r + 0.03)
		quad("white", Vector3(c0.x, y1 - 0.25, c0.y), Vector3(c1.x, y1 - 0.25, c1.y), Vector3(c1.x, y1 + 0.05, c1.y), Vector3(c0.x, y1 + 0.05, c0.y), out, false)
		tri("white", Vector3(c0.x, y1 + 0.05, c0.y), Vector3(c1.x, y1 + 0.05, c1.y), Vector3(p.x, y1 + 0.14, p.y), Vector3.UP, false)


func _gangway(top: Vector2, bot: Vector2, w: float) -> void:
	var a := Vector3(top.x, top_y, top.y)
	var b := Vector3(bot.x, Marina.DOCK_Y + 0.06, bot.y)
	var d := b - a
	var flat := Vector2(d.x, d.z).normalized()
	var n := Vector3(-flat.y, 0.0, flat.x) * (w * 0.5)
	# The walkway, aluminium with cleats across.
	quad("steel", a - n, a + n, b + n, b - n, Vector3.UP)
	quad("steel", a - n + Vector3(0, -0.12, 0), a + n + Vector3(0, -0.12, 0), b + n + Vector3(0, -0.12, 0), b - n + Vector3(0, -0.12, 0), Vector3.DOWN, false)
	for s: float in [-1.0, 1.0]:
		var e0 := a + n * s
		var e1 := b + n * s
		quad("steel", e0 + Vector3(0, -0.12, 0), e1 + Vector3(0, -0.12, 0), e1 + Vector3(0, 0.14, 0), e0 + Vector3(0, 0.14, 0), n * s, false)
		# Handrails on posts.
		var posts := int(d.length() / 1.6) + 1
		for k in posts + 1:
			var p := e0.lerp(e1, float(k) / posts)
			box("steel", Transform3D(Basis(), p + Vector3(0, 0.5, 0)), Vector3(0.05, 1.0, 0.05), false)
		var r0 := e0 + Vector3(0, 1.0, 0)
		var r1 := e1 + Vector3(0, 1.0, 0)
		quad("steel", r0, r1, r1 + Vector3(0, 0.05, 0), r0 + Vector3(0, 0.05, 0), n * s, false)
		quad("steel", r0 + Vector3(0, -0.45, 0), r1 + Vector3(0, -0.45, 0), r1 + Vector3(0, -0.41, 0), r0 + Vector3(0, -0.41, 0), n * s, false)
	# The security gate at the top: a mesh panel between two posts, the sign over it.
	if full:
		var g := a - Vector3(flat.x, 0, flat.y) * 0.4
		for s: float in [-1.0, 1.0]:
			box("steel", Transform3D(Basis(), g + n * s * 1.15 + Vector3(0, 1.1, 0)), Vector3(0.1, 2.2, 0.1), false)
		box("steel", Transform3D(Basis(Vector3.UP, atan2(-flat.x, -flat.y)), g + Vector3(0, 2.25, 0)), Vector3(w + 0.6, 0.08, 0.08), false)
		box("blue", Transform3D(Basis(Vector3.UP, atan2(-flat.x, -flat.y)), g + Vector3(0, 2.55, 0)), Vector3(w + 0.4, 0.45, 0.05), false)


# --- Boats ----------------------------------------------------------------------------------------

## Boats grouped (type, variant, group key) -> [{xf, custom}] for a chunk; built in one step.
func _boat_step() -> void:
	var groups := {}
	var shapes: Array = []
	for bt: Dictionary in mr.boats:
		var p: Vector2 = bt.p
		if not _owns(p):
			continue
		var gkey := Vector3i(int(bt.type), int(bt.variant), int(floorf(p.y / 44.0)) * 1000 + int(floorf(p.x / 60.0)))
		if not groups.has(gkey):
			groups[gkey] = []
		var s: float = bt.scale
		var xf := Transform3D(Basis(Vector3.UP, float(bt.yaw)).scaled(Vector3(s, s, s)), Vector3(p.x, Marina.WATER_Y + 0.02, p.y))
		(groups[gkey] as Array).append([xf, _custom(bt, false)])
		# LOD: the mast as a far box drawn at least a pixel wide (the mast forest from the hills).
		if lod and int(bt.type) == Marina.Type.SAIL:
			_far_mast(bt, Marina.WATER_Y)
		if full:
			var hb := BoatMesh.hull_box(int(bt.type))
			shapes.append([xf.basis.orthonormalized(), xf * (hb[0] as Vector3), (hb[1] as Vector3) * s])
		if bool(bt.anchor):
			var t := int(bt.type)
			var tip := xf * Vector3(0.0, BoatMesh.air_draft(t, int(bt.variant)) + 0.12, float(Marina.REF_LEN[t]) * -0.1)
			_lights.append([tip, Color(1.0, 0.97, 0.88, 0.85), 0.3, 4, 0.0])
	for gkey: Vector3i in groups:
		_boat_group(groups[gkey], gkey.x, gkey.y)
	if not shapes.is_empty():
		var body := StaticBody3D.new()
		body.name = "MarinaBoats"
		body.collision_layer = 1
		body.collision_mask = 0
		for sh: Array in shapes:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = sh[2]
			cs.shape = bs
			cs.transform = Transform3D(sh[0], sh[1])
			body.add_child(cs)
		ch.add_child(body)


## INSTANCE_CUSTOM for a boat: hull paint, flags / 64 (BoatMesh / boat.gdshader).
static func _custom(bt: Dictionary, stands: bool) -> Color:
	var paint: Color = bt.paint
	var canvas_i := Marina.CANVAS.find(bt.canvas)
	var flags := maxi(canvas_i, 0) + (8 if bool(bt.lit) else 0) + (16 if bool(bt.anchor) else 0) + (32 if stands else 0)
	return Color(paint.r, paint.g, paint.b, float(flags) / 64.0)


## One group of boats as three MultiMeshInstance3Ds (NEAR / MID / FAR by visibility range); LOD
## chunks build only the FAR one.
func _boat_group(items: Array, type: int, variant: int) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for it: Array in items:
		var o: Vector3 = (it[0] as Transform3D).origin
		lo = lo.min(o)
		hi = hi.max(o)
	var centre := (lo + hi) * 0.5
	var levels := [BoatMesh.Level.NEAR, BoatMesh.Level.MID, BoatMesh.Level.FAR] if full else [BoatMesh.Level.FAR]
	for lv: int in levels:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = BoatMesh.mesh(type, variant, lv)
		mm.instance_count = items.size()
		for i in items.size():
			var xf: Transform3D = items[i][0]
			mm.set_instance_transform(i, Transform3D(xf.basis, xf.origin - centre))
			mm.set_instance_color(i, Color.WHITE)
			mm.set_instance_custom_data(i, items[i][1])
		var mi := MultiMeshInstance3D.new()
		mi.name = "Boats_%d_%d_%d" % [type, variant, lv]
		mi.multimesh = mm
		mi.material_override = boat_material()
		mi.position = centre
		var reach := 26.0
		mi.custom_aabb = AABB(lo - centre - Vector3(reach, 3.0, reach), hi - lo + Vector3(reach * 2.0, 22.0, reach * 2.0))
		if full:
			match lv:
				BoatMesh.Level.NEAR:
					mi.visibility_range_end = NEAR_RANGE
					mi.visibility_range_end_margin = 6.0
				BoatMesh.Level.MID:
					mi.visibility_range_begin = NEAR_RANGE
					mi.visibility_range_begin_margin = 6.0
					mi.visibility_range_end = MID_RANGE
					mi.visibility_range_end_margin = 12.0
				_:
					mi.visibility_range_begin = MID_RANGE
					mi.visibility_range_begin_margin = 12.0
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)


# --- Buildings ------------------------------------------------------------------------------------

func _building_step() -> void:
	for b: Dictionary in mr.buildings:
		var r: Rect2 = b.rect
		if not _owns(r.get_center()):
			continue
		_building(b)


## A Building on the marina's land: the towers glassy with balconies on every floor, the
## restaurants low with storefronts on the promenade, the yard's shed a plain box.
func _building(b: Dictionary) -> void:
	var r: Rect2 = b.rect
	var building := CityChunk.BUILDING_SCENE.instantiate() as Building
	building.seed = int(b.seed)
	building.lot_size = r.size
	var params: Dictionary = CityPlan.DISTRICTS[CityPlan.District.MIDTOWN]
	building.lit_ratio_range = params.lit
	building.weathering_range = Vector2(0.1, 0.4)
	match str(b.kind):
		"tower":
			var hh := lerpf(42.0, 66.0, mr.h01(["tower_h", b.seed]))
			building.min_height = hh * 0.92
			building.max_height = hh
			building.force_shape = Building.Shape.SLAB if mr.h01(["tower_s", b.seed]) < 0.5 else Building.Shape.SETBACK
			building.finish_options.assign([Building.Finish.GLASS, Building.Finish.FLAT, Building.Finish.PANELS])
			building.balcony_chance = 1.0
			building.lit_ratio_range = Vector2(0.35, 0.65)
		"restaurant":
			building.min_height = 6.5
			building.max_height = 9.0
			building.force_shape = Building.Shape.SLAB
			building.finish_options.assign([Building.Finish.FLAT, Building.Finish.GLASS, Building.Finish.FLAT])
			building.canopy_chance = 1.0
			building.balcony_chance = 0.0
			building.lit_ratio_range = Vector2(0.7, 0.95)
		_:
			building.min_height = 7.0
			building.max_height = 8.5
			building.force_shape = Building.Shape.WAREHOUSE
			building.finish_options.assign([Building.Finish.PANELS])
			building.allow_storefront = false
	building.plinth_depth = 0.6
	var c := r.get_center()
	var base := Vector3(c.x, CityChunk.SIDEWALK_TOP, c.y)
	var g := Marina.QUAY_Y
	building.position = base + Vector3(0.0, g, 0.0)
	if full:
		ch.add_child(building)
		ch.building_count += 1
		return
	# LOD and the far city: the coded far boxes (FarBuilding), a box shape each part.
	var lod_style := building.plan_only()
	for part in building.parts:
		if not capturing:
			ch._add_lod_shape(part.size, building.position + (part.center as Vector3))
		ch._occluder_boxes.append([Transform3D(Basis(), building.position), part.center, part.size])
	if FarBuilding.enabled:
		for fb: Array in FarBuilding.boxes(building, lod_style, building.plinth_depth):
			var xf: Transform3D = fb[0]
			var at: Vector3 = base + xf.origin
			at.y += g - ch._gy(at.x, at.z)
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(xf.basis, at), fb[1], fb[2])
	building.free()
	ch.building_count += 1


# --- Props ----------------------------------------------------------------------------------------

func _props_step() -> void:
	if not full:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([mr.seed_value, "marina_palms", ch.ix, ch.iz])
	for p: Vector2 in mr.palms:
		if _owns(p):
			ch._add_palm(Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y), rng, false)
	for p: Vector2 in mr.lamps:
		if _owns(p):
			ch._add_lamp(Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y))
	for bn: Dictionary in mr.benches:
		var p: Vector2 = bn.p
		if _owns(p):
			ch._add_bench(Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y), float(bn.yaw))
	# Car parks: stall stripes in rows, parked cars in most stalls.
	for cp: Rect2 in mr.car_parks:
		if cp.size.x < 10.0 or cp.size.y < 10.0 or not _owns(cp.get_center()):
			continue
		_car_park(cp)
	# Restaurant terraces: tables under umbrellas on the promenade in front of each restaurant.
	for b: Dictionary in mr.buildings:
		if str(b.kind) != "restaurant":
			continue
		var r: Rect2 = b.rect
		if not _owns(r.get_center()):
			continue
		for k in 4:
			var at := Vector2(r.position.x + 2.5 + k * 5.0, r.end.y + 4.0)
			_umbrella(at, int(b.seed) + k)


## A car park: rows of 2.6 m stalls 5.4 deep both sides of 7 m aisles along x, cars in most.
func _car_park(cp: Rect2) -> void:
	var y := top_y + 0.014
	var rows := int((cp.size.y + 0.5) / 17.8)
	var z := cp.position.y
	for row in maxi(rows, 1):
		for side in 2:
			var zl := z + (0.0 if side == 0 else 12.4)
			var zs := zl + 5.4
			if zs > cp.end.y + 0.1:
				continue
			var x := cp.position.x + 1.0
			var k := 0
			while x + 2.6 < cp.end.x - 1.0:
				strip("stripe", Vector2(x, zl + 0.2), Vector2(x, zs - 0.2), 0.1, y + 0.004, 0.01, false)
				if mr.h01(["car", cp.position, row, side, k]) < 0.7:
					var yaw := 0.0 if side == 0 else PI
					var col: Color = ArenaGrounds.CAR_PAINTS[int(mr.h01(["carc", cp.position, row, side, k]) * ArenaGrounds.CAR_PAINTS.size()) % ArenaGrounds.CAR_PAINTS.size()]
					var v := int(mr.h01(["carv", cp.position, row, side, k]) * ArenaGrounds.CAR_KINDS) % ArenaGrounds.CAR_KINDS
					ch._batch.add("mr_car_%d" % v, ArenaGrounds.car_mesh(v), Transform3D(Basis(Vector3.UP, yaw), Vector3(x + 1.3, CityChunk.SIDEWALK_TOP + 0.014, (zl + zs) * 0.5)), col)
				x += 2.6
				k += 1
		z += 17.8


func _umbrella(at: Vector2, sd: int) -> void:
	var y := top_y
	box("white", Transform3D(Basis(), Vector3(at.x, y + 0.37, at.y)), Vector3(0.8, 0.04, 0.8), false)
	box("steel", Transform3D(Basis(), Vector3(at.x, y + 0.18, at.y)), Vector3(0.06, 0.36, 0.06), false)
	box("steel", Transform3D(Basis(), Vector3(at.x, y + 1.25, at.y)), Vector3(0.05, 2.5, 0.05), false)
	var canvas: Color = Marina.CANVAS[absi(sd) % Marina.CANVAS.size()]
	var key := "umb_%d" % (absi(sd) % Marina.CANVAS.size())
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = canvas
		m.roughness = 0.85
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	var r := 1.4
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		tri(key, Vector3(at.x, y + 2.55, at.y), Vector3(at.x + cos(a0) * r, y + 2.15, at.y + sin(a0) * r), Vector3(at.x + cos(a1) * r, y + 2.15, at.y + sin(a1) * r), Vector3.UP, false)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		box("white", Transform3D(Basis(Vector3.UP, a), Vector3(at.x + cos(a) * 0.75, y + 0.23, at.y + sin(a) * 0.75)), Vector3(0.42, 0.46, 0.42), false)


# --- The boat yard --------------------------------------------------------------------------------

func _yard_step() -> void:
	# Boats on stands: hulls on keel blocks, jack stands along both sides.
	var items := {}
	for bt: Dictionary in mr.yard_boats:
		var p: Vector2 = bt.p
		if not _owns(p):
			continue
		var s: float = bt.scale
		var keel := 1.25 if int(bt.type) == Marina.Type.SAIL else 0.95
		var y := top_y + keel * s + (2.0 * s if int(bt.type) == Marina.Type.SAIL else 0.0)
		var xf := Transform3D(Basis(Vector3.UP, float(bt.yaw)).scaled(Vector3(s, s, s)), Vector3(p.x, y, p.y))
		var key := Vector2i(int(bt.type), int(bt.variant))
		if not items.has(key):
			items[key] = []
		(items[key] as Array).append([xf, _custom(bt, true)])
		if full:
			_stands(xf, int(bt.type), s, y)
			var hb := BoatMesh.hull_box(int(bt.type))
			collide_box(Transform3D(xf.basis.orthonormalized(), xf * (hb[0] as Vector3)), (hb[1] as Vector3) * s * Vector3(0.9, 0.8, 0.9))
	for key: Vector2i in items:
		_boat_group(items[key], key.x, key.y)
	# The travel lift's well: two concrete piers out over the water, rails on them, the lift astride.
	var wr := mr.lift_well
	if _owns(wr.get_center()):
		for s: float in [-1.0, 1.0]:
			var x := wr.get_center().x + s * (wr.size.x * 0.5 + 1.3)
			box("bulkhead", Transform3D(Basis(), Vector3(x, top_y - 0.6, wr.get_center().y)), Vector3(2.6, 1.3, wr.size.y))
			if full:
				for k in 4:
					box("pile", Transform3D(Basis(), Vector3(x, -0.4, wr.position.y + 2.0 + k * (wr.size.y - 4.0) / 3.0)), Vector3(0.5, 3.0, 0.5), false)
		if full:
			_travel_lift(Vector3(wr.get_center().x, top_y + 0.06, wr.position.y + 6.0))


## Jack stands (screw poppets) either side of a hull, and keel blocks.
func _stands(xf: Transform3D, type: int, s: float, y: float) -> void:
	var beam := Marina._beam(type, float(Marina.REF_LEN[type])) * s
	for k in 3:
		var t := (float(k) - 1.0) * float(Marina.REF_LEN[type]) * s * 0.28
		for side: float in [-1.0, 1.0]:
			var foot := xf.origin + xf.basis.orthonormalized() * Vector3(side * (beam * 0.55 + 0.2), 0.0, t)
			foot.y = top_y
			var head := xf.origin + xf.basis.orthonormalized() * Vector3(side * beam * 0.42, 0.0, t)
			head.y = y + 0.25 * s
			var mid := (foot + head) * 0.5
			var d := head - foot
			var basis := Basis(Vector3.UP, atan2(-d.x, -d.z)) * Basis(Vector3.RIGHT, -atan2(Vector2(d.x, d.z).length(), d.y))
			box("blue", Transform3D(basis, mid), Vector3(0.07, d.length(), 0.07), false)
			box("blue", Transform3D(Basis(), Vector3(foot.x, top_y + 0.03, foot.z)), Vector3(0.6, 0.06, 0.6), false)
	box("deck", Transform3D(xf.basis.orthonormalized(), Vector3(xf.origin.x, (top_y + y - (2.6 if type == Marina.Type.SAIL else 0.9) * s) * 0.5, xf.origin.z)), Vector3(0.5, maxf(y - (2.6 if type == Marina.Type.SAIL else 0.9) * s - top_y, 0.2), 1.6), false)


## The travel lift: a blue portal frame on four tyred legs astride the well, slings under a boat.
func _travel_lift(at: Vector3) -> void:
	var half_w := mr.lift_well.size.x * 0.5 + 1.3
	var hgt := 9.0
	var len := 9.0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := at + Vector3(sx * half_w, 0.0, sz * len * 0.5)
			box("blue", Transform3D(Basis(), p + Vector3(0.0, hgt * 0.5 + 0.6, 0.0)), Vector3(0.6, hgt, 0.6), false)
			box("rubber", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), p + Vector3(0.0, 0.6, 0.0)), Vector3(1.2, 0.5, 1.2), false)
		box("blue", Transform3D(Basis(), at + Vector3(sx * half_w, hgt + 0.6, 0.0)), Vector3(0.8, 0.9, len + 0.6), false)
	for sz: float in [-1.0, 1.0]:
		box("blue", Transform3D(Basis(), at + Vector3(0.0, hgt + 1.2, sz * len * 0.35)), Vector3(half_w * 2.0 + 0.8, 0.8, 0.7), false)
	box("white", Transform3D(Basis(), at + Vector3(half_w + 0.9, 2.6, len * 0.5 - 0.6)), Vector3(1.2, 1.6, 1.2), false)
	# Slings down to a sport fisher hanging in them, its keel just clear of the water.
	var boat_y := Marina.WATER_Y + 1.6
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var a := at + Vector3(sx * (half_w - 0.6), hgt + 0.7, sz * len * 0.35)
			var b := Vector3(at.x + sx * 1.8, boat_y + 0.3, at.z + sz * len * 0.35)
			strip("rubber", Vector2(a.x, a.z), Vector2(b.x, b.z) + Vector2(0.001, 0.0), 0.25, a.y, 0.05, false)
			var d := b - a
			box("rubber", Transform3D(Basis(Vector3.FORWARD, atan2(d.x, -d.y)), (a + b) * 0.5), Vector3(0.04, d.length(), 0.25), false)
	var bt := {"paint": Color(0.93, 0.93, 0.91), "canvas": Marina.CANVAS[1], "lit": false, "anchor": false}
	var xf := Transform3D(Basis().scaled(Vector3.ONE * 0.95), Vector3(at.x, boat_y, at.z))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = BoatMesh.mesh(Marina.Type.FISHER, 0, BoatMesh.Level.NEAR)
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_color(0, Color.WHITE)
	mm.set_instance_custom_data(0, _custom(bt, true))
	var mi := MultiMeshInstance3D.new()
	mi.name = "LiftBoat"
	mi.multimesh = mm
	mi.material_override = boat_material()
	mi.visibility_range_end = MID_RANGE
	ch.add_child(mi)


# --- The channel, the jetties, the breakwater -----------------------------------------------------

## The channel's water across the sand (outside the site; inside it the water step lays it).
func _channel_step() -> void:
	if ch.plan.marina_block(ch.ix, ch.iz):
		return
	var r := mr.channel.intersection(area)
	if r.size.x > 0.1 and r.size.y > 0.1:
		poly_top("water", _rect_poly(r), Marina.WATER_Y, false)


## The jetties along the channel's banks from the land out past the waterline, and the breakwater
## offshore: rubble mounds (a core on the "rock" set) with boulders along the crest and down the
## faces in a batch, a round head at the seaward ends.
func _mound_step() -> void:
	var land_x := mr.west_x(mr.zc) - 2.0
	var tip := mr.channel.position.x
	for side: float in [-1.0, 1.0]:
		var zw := mr.zc + side * Marina.CHANNEL_HALF
		var a := Vector2(land_x, zw)
		var b := Vector2(tip, zw)
		_mound(a, b, side, Marina.JETTY_CREST, Marina.JETTY_TOP, "jetty%d" % int(side))
	var bx := mr.breakwater_x()
	_mound(Vector2(bx, mr.zc - Marina.BREAKWATER_HALF), Vector2(bx, mr.zc + Marina.BREAKWATER_HALF), 0.0, Marina.BREAKWATER_CREST, Marina.BREAKWATER_TOP, "breakwater")


## A rubble mound along a -> b: its channel-side toe on the line (side +-1: the mound stands on
## the +-z side of it), or centred on it (side 0). Crest `crest` wide at `top`.
func _mound(a: Vector2, b: Vector2, side: float, crest: float, top: float, key: String) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	if side != 0.0 and n.y * side < 0.0:
		n = -n
	var run := (top - Marina.MOUND_FOOT) * Marina.MOUND_SLOPE
	var water_run := (Marina.WATER_Y - Marina.MOUND_FOOT) * Marina.MOUND_SLOPE
	# Cross-section offsets from the line (along n) and heights: inner toe, crest edges, outer toe.
	var off0 := -water_run if side != 0.0 else -(crest * 0.5 + run)
	var prof: Array = []
	prof.append([off0, Marina.MOUND_FOOT])
	prof.append([off0 + run, top])
	prof.append([off0 + run + crest, top])
	prof.append([off0 + run * 2.0 + crest, Marina.MOUND_FOOT])
	var len := a.distance_to(b)
	var step := 6.0
	var n_steps := maxi(1, int(ceil(len / step)))
	for k in n_steps:
		var t0 := float(k) / n_steps
		var t1 := float(k + 1) / n_steps
		var c0 := a.lerp(b, t0)
		var c1 := a.lerp(b, t1)
		if not _owns((c0 + c1) * 0.5):
			continue
		for j in prof.size() - 1:
			var o0: float = prof[j][0]
			var o1: float = prof[j + 1][0]
			var y0: float = prof[j][1]
			var y1: float = prof[j + 1][1]
			var p00 := c0 + n * o0
			var p01 := c0 + n * o1
			var p10 := c1 + n * o0
			var p11 := c1 + n * o1
			var nrm := Vector3(n.x * (y0 - y1), absf(o1 - o0), n.y * (y0 - y1)).normalized()
			if j == 1:
				nrm = Vector3.UP
			quad("rock", Vector3(p00.x, y0, p00.y), Vector3(p10.x, y0, p10.y), Vector3(p11.x, y1, p11.y), Vector3(p01.x, y1, p01.y), nrm)
		# Boulders on the crest and the faces (FULL; a few at LOD for the silhouette).
		var count := 6 if full else (1 if not capturing else 0)
		for q in count:
			var hk := [key, k, q]
			var tt := lerpf(t0, t1, mr.h01(hk + ["t"]))
			var c := a.lerp(b, tt)
			var u := mr.h01(hk + ["u"])
			var off := lerpf(float(prof[0][0]) + water_run * 0.6, float(prof[3][0]) - water_run * 0.6, u)
			var p := c + n * off
			var h := _mound_y(off, prof)
			var sc := lerpf(0.75, 1.5, mr.h01(hk + ["s"]))
			var basis := Basis(Vector3.UP, mr.h01(hk + ["y"]) * TAU) * Basis(Vector3.RIGHT, (mr.h01(hk + ["r"]) - 0.5) * 0.9)
			var v := 0 if mr.h01(hk + ["v"]) < 0.6 else 1
			var at := Vector3(p.x, h - 0.4 * sc - ch._gy(p.x, p.y), p.y)
			ch._batch.add("mr_rock%d" % v, PropFactory.model_rock(v), Transform3D(basis.scaled(Vector3.ONE * sc), at), Color(0.86, 0.84, 0.8))
	# The seaward head: a cone of rubble round the tip.
	if _owns(b):
		var segs := 10
		for j in segs:
			var a0 := atan2(d.y, d.x) - PI * 0.5 + PI * float(j) / segs
			var a1 := atan2(d.y, d.x) - PI * 0.5 + PI * float(j + 1) / segs
			var centre := b + n * ((float(prof[1][0]) + float(prof[2][0])) * 0.5)
			var r0 := crest * 0.5
			var r1 := r0 + run
			var e0 := Vector2(cos(a0), sin(a0))
			var e1 := Vector2(cos(a1), sin(a1))
			quad("rock", Vector3(centre.x + e0.x * r0, top, centre.y + e0.y * r0), Vector3(centre.x + e1.x * r0, top, centre.y + e1.y * r0), Vector3(centre.x + e1.x * r1, Marina.MOUND_FOOT, centre.y + e1.y * r1), Vector3(centre.x + e0.x * r1, Marina.MOUND_FOOT, centre.y + e0.y * r1), Vector3((e0.x + e1.x), 1.0, (e0.y + e1.y)))
			tri("rock", Vector3(centre.x, top, centre.y), Vector3(centre.x + e0.x * r0, top, centre.y + e0.y * r0), Vector3(centre.x + e1.x * r0, top, centre.y + e1.y * r0), Vector3.UP)


static func _mound_y(off: float, prof: Array) -> float:
	for j in prof.size() - 1:
		var o0: float = prof[j][0]
		var o1: float = prof[j + 1][0]
		if off >= o0 and off <= o1:
			return lerpf(float(prof[j][1]), float(prof[j + 1][1]), (off - o0) / maxf(o1 - o0, 0.001))
	return Marina.MOUND_FOOT


# --- The coast highway's bridge -------------------------------------------------------------------

## The bridge carrying the coast highway over the channel: a deck on the strip's own line
## following Marina.bridge_y(), concrete barriers either side, a box girder under the span with
## piers just outside the jetties, and the ramps on fill held by walls down to the sand.
func _bridge_step() -> void:
	var gap := mr.pch_gap()
	var half := HillRoads.COAST_WIDTH * 0.5
	var end_y0 := plan.height_at(Vector2(mr.pch_x(gap.x), gap.x)) + 0.26
	var end_y1 := plan.height_at(Vector2(mr.pch_x(gap.y), gap.y)) + 0.26
	var step := 4.0
	var n_steps := int(ceil((gap.y - gap.x) / step))
	for k in n_steps:
		var z0 := gap.x + (gap.y - gap.x) * k / n_steps
		var z1 := gap.x + (gap.y - gap.x) * (k + 1) / n_steps
		var c0 := Vector2(mr.pch_x(z0), z0)
		var c1 := Vector2(mr.pch_x(z1), z1)
		if not _owns((c0 + c1) * 0.5):
			continue
		var ey0 := end_y0 if z0 < mr.zc else end_y1
		var ey1 := end_y0 if z1 < mr.zc else end_y1
		var y0 := mr.bridge_y(z0, ey0)
		var y1 := mr.bridge_y(z1, ey1)
		var d := (c1 - c0).normalized()
		var n := Vector2(-d.y, d.x)
		if n.x < 0.0:
			n = -n
		var l0 := c0 - n * half
		var r0 := c0 + n * half
		var l1 := c1 - n * half
		var r1 := c1 + n * half
		quad("bridge_deck", Vector3(l0.x, y0, l0.y), Vector3(r0.x, y0, r0.y), Vector3(r1.x, y1, r1.y), Vector3(l1.x, y1, l1.y), Vector3.UP)
		# Lane paint: the double yellow and the dashed lane lines.
		if full:
			for o: float in [-0.12, 0.12]:
				quad("yellow", Vector3(c0.x + n.x * o - n.x * 0.05, y0 + 0.012, c0.y + n.y * o - n.y * 0.05), Vector3(c0.x + n.x * o + n.x * 0.05, y0 + 0.012, c0.y + n.y * o + n.y * 0.05), Vector3(c1.x + n.x * o + n.x * 0.05, y1 + 0.012, c1.y + n.y * o + n.y * 0.05), Vector3(c1.x + n.x * o - n.x * 0.05, y1 + 0.012, c1.y + n.y * o - n.y * 0.05), Vector3.UP, false)
			if k % 3 == 0:
				for o: float in [-4.2, 4.2]:
					quad("stripe", Vector3(c0.x + n.x * o - n.x * 0.06, y0 + 0.012, c0.y + n.y * o - n.y * 0.06), Vector3(c0.x + n.x * o + n.x * 0.06, y0 + 0.012, c0.y + n.y * o + n.y * 0.06), Vector3(c1.x + n.x * o + n.x * 0.06, y1 + 0.012, c1.y + n.y * o + n.y * 0.06), Vector3(c1.x + n.x * o - n.x * 0.06, y1 + 0.012, c1.y + n.y * o - n.y * 0.06), Vector3.UP, false)
		var span_flat := absf((z0 + z1) * 0.5 - mr.zc) < Marina.CHANNEL_HALF + Marina.BRIDGE_ABUT
		for s: float in [-1.0, 1.0]:
			var e0 := c0 + n * s * half
			var e1 := c1 + n * s * half
			var o0 := c0 + n * s * (half + 0.5)
			var o1 := c1 + n * s * (half + 0.5)
			var want := Vector3(n.x * s, 0.0, n.y * s)
			# The barrier: 0.9 m of concrete, its inner face, top and outer face.
			quad("bridge", Vector3(e0.x, y0, e0.y), Vector3(e1.x, y1, e1.y), Vector3(e1.x, y1 + 0.9, e1.y), Vector3(e0.x, y0 + 0.9, e0.y), -want)
			quad("bridge", Vector3(e0.x, y0 + 0.9, e0.y), Vector3(e1.x, y1 + 0.9, e1.y), Vector3(o1.x, y1 + 0.9, o1.y), Vector3(o0.x, y0 + 0.9, o0.y), Vector3.UP)
			if span_flat:
				# The girder's fascia down to its soffit.
				quad("bridge", Vector3(o0.x, y0 + 0.9, o0.y), Vector3(o1.x, y1 + 0.9, o1.y), Vector3(o1.x, y1 - Marina.BRIDGE_DECK, o1.y), Vector3(o0.x, y0 - Marina.BRIDGE_DECK, o0.y), want)
			else:
				# The fill's retaining wall down to the sand.
				quad("bridge", Vector3(o0.x, y0 + 0.9, o0.y), Vector3(o1.x, y1 + 0.9, o1.y), Vector3(o1.x, -0.4, o1.y), Vector3(o0.x, -0.4, o0.y), want)
		if span_flat:
			var so0 := c0 - n * (half + 0.5)
			var so1 := c1 - n * (half + 0.5)
			var sp0 := c0 + n * (half + 0.5)
			var sp1 := c1 + n * (half + 0.5)
			quad("bridge", Vector3(so0.x, y0 - Marina.BRIDGE_DECK, so0.y), Vector3(sp0.x, y0 - Marina.BRIDGE_DECK, sp0.y), Vector3(sp1.x, y1 - Marina.BRIDGE_DECK, sp1.y), Vector3(so1.x, y1 - Marina.BRIDGE_DECK, so1.y), Vector3.DOWN, false)
	# Piers: a wall of three columns under a cap, just outside each jetty, and the abutments.
	for zp: float in [mr.zc - Marina.CHANNEL_HALF - Marina.BRIDGE_ABUT, mr.zc - Marina.CHANNEL_HALF + 1.0, mr.zc + Marina.CHANNEL_HALF - 1.0, mr.zc + Marina.CHANNEL_HALF + Marina.BRIDGE_ABUT]:
		var c := Vector2(mr.pch_x(zp), zp)
		if not _owns(c):
			continue
		var yt := mr.bridge_y(zp, end_y0) - Marina.BRIDGE_DECK
		var dz := Vector2(mr.pch_x(zp + 1.0), zp + 1.0) - c
		var yaw := atan2(-dz.x, -dz.y)
		var basis := Basis(Vector3.UP, yaw)
		box("bridge", Transform3D(basis, Vector3(c.x, yt - 0.5, c.y)), Vector3(half * 2.0 + 1.6, 1.0, 2.0))
		for o: float in [-half * 0.66, 0.0, half * 0.66]:
			var p := Vector3(c.x, 0.0, c.y) + basis * Vector3(o, 0.0, 0.0)
			box("bridge", Transform3D(basis, Vector3(p.x, (yt - 1.0 - 3.0) * 0.5, p.z)), Vector3(1.3, yt - 1.0 + 3.0, 1.3))


# --- Lights ---------------------------------------------------------------------------------------

## The nav lights (and the lighthouse on the south jetty's head), then every glow this chunk
## gathered, as one billboard mesh on aircraft_lights.gdshader.
func _lights_step() -> void:
	for nl: Dictionary in mr.nav_lights:
		var p: Vector2 = nl.p
		if not _owns(p):
			continue
		var tower: bool = nl.tower
		var col: Color = nl.color
		var top := Marina.JETTY_TOP if absf(p.y - mr.zc) < Marina.CHANNEL_HALF + 20.0 else Marina.BREAKWATER_TOP
		var h := 9.5 if tower else 5.0
		_light_tower(Vector3(p.x, top, p.y), h, col, tower)
		_lights.append([Vector3(p.x, top + h + 0.55, p.y), Color(col.r, col.g, col.b, 1.0), 1.6, 2, float(nl.phase)])
	if _lights.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for spec: Array in _lights:
		var code := float(spec[3]) * 10.0 + clampf(float(spec[4]), 0.0, 1.0) * 9.0
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(spec[1])
			st.set_uv(corners[k])
			st.set_uv2(Vector2(spec[2], code))
			st.set_normal(Vector3.UP)
			st.add_vertex(spec[0])
	var mi := MeshInstance3D.new()
	mi.name = "MarinaLights"
	mi.mesh = st.commit()
	mi.material_override = light_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 400.0
	ch.add_child(mi)
	_lights.clear()


## A light structure on a jetty or breakwater head: a white tapered tower with a band in the
## light's colour and a lantern gallery (the lighthouse), or a post on a concrete base.
func _light_tower(at: Vector3, h: float, col: Color, lighthouse: bool) -> void:
	var key := "nav_%d" % int(col.r * 10.0 + col.g * 100.0)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col.lerp(Color(0.5, 0.5, 0.5), 0.2)
		m.roughness = 0.5
		_mats[key] = m
	box("bulkhead", Transform3D(Basis(), at + Vector3(0, 0.4, 0)), Vector3(3.2, 0.8, 3.2))
	var sides := 10
	var r0 := 1.25 if lighthouse else 0.35
	var r1 := 0.85 if lighthouse else 0.3
	var y0 := at.y + 0.8
	var y1 := at.y + h
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var out := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		# The tower in bands: white, the colour band near the top, white.
		var ys := [y0, lerpf(y0, y1, 0.62), lerpf(y0, y1, 0.82), y1]
		for b in 3:
			var ya: float = ys[b]
			var yb: float = ys[b + 1]
			var ra := lerpf(r0, r1, (ya - y0) / (y1 - y0))
			var rb := lerpf(r0, r1, (yb - y0) / (y1 - y0))
			var mat := key if b == 1 else "white"
			quad(mat, Vector3(at.x + cos(a0) * ra, ya, at.z + sin(a0) * ra), Vector3(at.x + cos(a1) * ra, ya, at.z + sin(a1) * ra), Vector3(at.x + cos(a1) * rb, yb, at.z + sin(a1) * rb), Vector3(at.x + cos(a0) * rb, yb, at.z + sin(a0) * rb), out, b == 0)
	if lighthouse:
		# The gallery, the lantern's glazing, the cap.
		box("steel", Transform3D(Basis(), Vector3(at.x, y1 + 0.05, at.z)), Vector3(2.6, 0.1, 2.6), false)
		box("glass_lamp", Transform3D(Basis(), Vector3(at.x, y1 + 0.55, at.z)), Vector3(1.0, 0.9, 1.0), false)
		box("steel", Transform3D(Basis(), Vector3(at.x, y1 + 1.1, at.z)), Vector3(1.3, 0.2, 1.3), false)
	else:
		box("steel", Transform3D(Basis(), Vector3(at.x, y1 + 0.3, at.z)), Vector3(0.45, 0.6, 0.45), false)


# --- Channel traffic ------------------------------------------------------------------------------

func _traffic_step() -> void:
	if not full or mr.traffic_loop.is_empty():
		return
	if not _owns(mr.traffic_loop[0]):
		return
	var t := MarinaTraffic.new()
	t.name = "MarinaTraffic"
	t.setup(mr)
	ch.add_child(t)


# --- Commit ---------------------------------------------------------------------------------------

func _commit_step() -> void:
	for key: String in _st:
		var st: SurfaceTool = _st[key]
		var mi := MeshInstance3D.new()
		mi.name = "Marina_" + key
		mi.mesh = st.commit()
		match key:
			"water":
				mi.material_override = water_material()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"yellow":
				if not _mats.has("yellow"):
					var m := StandardMaterial3D.new()
					m.albedo_color = Color(0.92, 0.72, 0.16)
					m.roughness = 0.7
					_mats["yellow"] = m
				mi.material_override = _mats["yellow"]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"glass_lamp":
				if not _mats.has("glass_lamp"):
					var m := StandardMaterial3D.new()
					m.albedo_color = Color(0.2, 0.22, 0.2)
					m.roughness = 0.1
					m.metallic = 0.3
					_mats["glass_lamp"] = m
				mi.material_override = _mats["glass_lamp"]
			"bridge", "bridge_deck":
				mi.material_override = material("bulkhead") if key == "bridge" else material("asphalt")
			_:
				mi.material_override = material(key)
		if key in ["pavers", "asphalt", "concrete", "lawn", "bike", "stripe", "bank", "deck"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)
	_st.clear()
	if _faces.size() >= 3 and (full or ch._lod_collision_wanted()):
		var body := StaticBody3D.new()
		body.name = "MarinaBody"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(_faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		ch.add_child(body)
	_faces = PackedVector3Array()


# --- The far city ---------------------------------------------------------------------------------

## A far box with its top on its local +X face (building_lod.gdshader paints a local +-Y face as a
## roof with plant on it; RiverBuild._far()).
static func _far(xf: Transform3D, col: Color) -> Array:
	var b := xf.basis
	return [Transform3D(Basis(b.y, -b.x, b.z), xf.origin), col]


func _capture_block() -> void:
	var boxes: Array = ch.captured.boxes
	# The land as slabs, row by row (the far plate under them is the water).
	var slice := 8.0
	var nz := maxi(1, ceili(area.size.y / slice))
	for k in nz:
		var z0 := area.position.y + area.size.y * k / nz
		var z1 := area.position.y + area.size.y * (k + 1) / nz
		var zc := (z0 + z1) * 0.5
		var spans := _land_spans(zc)
		for sp: Array in spans:
			var a := maxf(float(sp[0]), area.position.x)
			var b := minf(float(sp[1]), area.end.x)
			if b - a < 0.5:
				continue
			var h := top_y - Marina.WATER_Y + 0.4
			boxes.append(_far(Transform3D(Basis().scaled(Vector3(b - a, h, z1 - z0)), Vector3((a + b) * 0.5, top_y - h * 0.5, zc)), FAR_LAND))
	for cp: Rect2 in mr.car_parks:
		var r := cp.intersection(area)
		if r.size.x > 1.0 and r.size.y > 1.0:
			boxes.append(_far(Transform3D(Basis().scaled(Vector3(r.size.x, 0.1, r.size.y)), Vector3(r.get_center().x, top_y + 0.05, r.get_center().y)), FAR_ASPHALT))
	# Docks.
	for d: Dictionary in mr.docks:
		var a: Vector2 = d.a
		var b: Vector2 = d.b
		if not _owns((a + b) * 0.5) or str(d.kind) == "finger":
			continue
		var len := a.distance_to(b)
		var dir := (b - a) / maxf(len, 0.01)
		var c := (a + b) * 0.5
		boxes.append(_far(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)).scaled_local(Vector3(float(d.w), 0.5, len)), Vector3(c.x, Marina.DOCK_Y - 0.25, c.y)), FAR_DOCK))
	# Boats: a hull box each, and a mast (drawn at least a pixel wide) for the sailboats.
	var all_boats: Array = []
	for bt: Dictionary in mr.boats:
		all_boats.append([bt, false])
	for bt: Dictionary in mr.yard_boats:
		all_boats.append([bt, true])
	for pair: Array in all_boats:
		var bt: Dictionary = pair[0]
		var yard: bool = pair[1]
		var p: Vector2 = bt.p
		if not _owns(p):
			continue
		var t := int(bt.type)
		var s: float = bt.scale
		var length := float(Marina.REF_LEN[t]) * s
		var beam := Marina._beam(t, length)
		var basis := Basis(Vector3.UP, float(bt.yaw))
		var y0 := (top_y + 1.0 * s) if yard else Marina.WATER_Y
		var fb := [1.1, 2.4, 2.0, 0.8][t] as float
		var paint: Color = bt.paint
		boxes.append(_far(Transform3D(basis.scaled_local(Vector3(beam * 0.85, fb * s, length * 0.9)), Vector3(p.x, y0 + fb * s * 0.5, p.y)), paint.srgb_to_linear() * 0.9))
		if t == Marina.Type.MOTOR or t == Marina.Type.FISHER:
			boxes.append(_far(Transform3D(basis.scaled_local(Vector3(beam * 0.7, 1.8 * s, length * 0.45)), Vector3(p.x, y0 + fb * s + 0.9 * s, p.y)), FAR_HULL))
		if t == Marina.Type.SAIL:
			_far_mast(bt, y0)
	# Buildings (their coded far boxes go into the lod_box batch).
	for b: Dictionary in mr.buildings:
		if _owns((b.rect as Rect2).get_center()):
			_building(b)


## The far city's record of the channel's jetties, the breakwater and the bridge (any chunk).
func _capture_extras() -> void:
	var boxes: Array = ch.captured.boxes
	var land_x := mr.west_x(mr.zc) - 2.0
	var tip := mr.channel.position.x
	var runs: Array = []
	for side: float in [-1.0, 1.0]:
		var zw := mr.zc + side * (Marina.CHANNEL_HALF + (Marina.JETTY_TOP - Marina.WATER_Y) * Marina.MOUND_SLOPE + Marina.JETTY_CREST * 0.5)
		runs.append([Vector2(land_x, zw), Vector2(tip, zw), Marina.JETTY_CREST + 4.0, Marina.JETTY_TOP])
	var bx := mr.breakwater_x()
	runs.append([Vector2(bx, mr.zc - Marina.BREAKWATER_HALF), Vector2(bx, mr.zc + Marina.BREAKWATER_HALF), Marina.BREAKWATER_CREST + 6.0, Marina.BREAKWATER_TOP])
	for r: Array in runs:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var len := a.distance_to(b)
		var n := maxi(1, int(len / 24.0))
		for k in n:
			var c0 := a.lerp(b, float(k) / n)
			var c1 := a.lerp(b, float(k + 1) / n)
			var c := (c0 + c1) * 0.5
			if not _owns(c):
				continue
			var d := c1 - c0
			var h: float = float(r[3]) + 1.0
			boxes.append(_far(Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.y)).scaled_local(Vector3(float(r[2]), h, d.length())), Vector3(c.x, float(r[3]) - h * 0.5, c.y)), FAR_ROCK))
	var gap := mr.pch_gap()
	var e0 := plan.height_at(Vector2(mr.pch_x(gap.x), gap.x)) + 0.26
	var z := gap.x
	while z < gap.y:
		var z1 := minf(z + 12.0, gap.y)
		var c := Vector2(mr.pch_x((z + z1) * 0.5), (z + z1) * 0.5)
		if _owns(c):
			var y := mr.bridge_y(c.y, e0)
			boxes.append(_far(Transform3D(Basis().scaled(Vector3(HillRoads.COAST_WIDTH + 1.0, 1.2, z1 - z)), Vector3(c.x, y - 0.6, c.y)), FAR_ROCK.lerp(FAR_LAND, 0.6)))
		z = z1


## A sailboat's mast as a far box (FarBuilding.Plant.MAST: building_lod.gdshader draws it at least
## a pixel wide), from `y0` (the water, or the stands) to the masthead.
func _far_mast(bt: Dictionary, y0: float) -> void:
	var t := int(bt.type)
	var s: float = bt.scale
	var p: Vector2 = bt.p
	var hgt := BoatMesh.air_draft(t, int(bt.variant)) * s
	var at := Vector3(p.x, y0 + hgt * 0.5, p.y) + Basis(Vector3.UP, float(bt.yaw)) * Vector3(0.0, 0.0, -float(Marina.REF_LEN[t]) * s * 0.1)
	ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis.from_scale(Vector3(0.18, hgt, 0.18)), at - Vector3(0.0, ch._gy(at.x, at.z), 0.0)), Color(0.72, 0.73, 0.75), Color(float(FarBuilding.Plant.MAST), 1.0, 0.0, FarBuilding.PLANT_FLAG))


## The land's x spans across row z (site less the water, east of the sand's bank).
func _land_spans(z: float) -> Array:
	if z < mr.site.position.y or z > mr.site.end.y:
		return []
	var x0 := maxf(mr.sand_x(z) + Marina.BANK, mr.site.position.x)
	var x1 := mr.site.end.x
	var cuts: Array = []
	if z > mr.z_north and z < mr.z_south:
		cuts.append([mr.west_x(z), mr.x_east])
	if absf(z - mr.zc) < Marina.CHANNEL_HALF:
		cuts.append([mr.channel.position.x, mr.west_x(z)])
	var spans: Array = [[x0, x1]]
	for cu: Array in cuts:
		var next: Array = []
		for sp: Array in spans:
			var a: float = sp[0]
			var b: float = sp[1]
			if float(cu[1]) <= a or float(cu[0]) >= b:
				next.append(sp)
				continue
			if float(cu[0]) > a:
				next.append([a, float(cu[0])])
			if float(cu[1]) < b:
				next.append([float(cu[1]), b])
		spans = next
	return spans
