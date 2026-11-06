class_name MarinaNight
extends RefCounted
## The marina at night (wave 8 refcam `marina_night`, docs/HANDOFF.md "The marina at night"). What
## the camera on the east headwalk at 21:00 gave away as a game:
##
##   - the water mirrored none of the lights: a harbour at night is black water striped with the
##     wavering columns of every lamp, anchor light and lit window round it - here it was a dark
##     sheet with a faint orange crazing in the chop that read as brick paving. MarinaGolden's
##     node (which already hands the water the nearest boats) now also hands it the LIGHTS nearest
##     the camera (`ml_p` / `ml_c`: the dock pedestals, the boats' anchor lights and lit cabins,
##     the quay lamps, the jetty and breakwater nav lights) and the restaurants' lit fronts
##     (`mf_a` / `mf_b`); shaders/marina_night.gdshaderinc follows each water pixel's reflected ray
##     to them: a light's column is its miss across the ray (tight) and in height (loose, growing
##     with the distance travelled, broken by a steeper copy of the chop), a front is the ray's hit
##     on its plane - the shop band, the window band over it, the bulkhead in front cutting it off;
##   - the restaurants on the north quay sold cigarettes and liquor: their shops are drawn from
##     the eateries of Building.SHOP_NAMES (`name_pool`), so the vinyl and the traced rooms are cafes;
##   - the furled jibs' UV cover strips drew as black-and-white barber poles: the cover is wound
##     with its turns overlapping (`jib_soft`: thin, dulled slivers of sail between them).
##
## MARINA_NIGHT=0 is the A/B: `ml_count` / `mf_count` 0, `jib_soft` 0, the restaurants' own names.
## It rides on MarinaGolden's node (MARINA_GOLDEN=0 turns it off too).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

const MAX_LIGHTS := 48
const MAX_FRONTS := 4
## Lights within this of the camera are candidates (a light further off is a dot under a pixel).
const REACH := 420.0
## The eateries of Building.SHOP_NAMES a marina restaurant's shops are drawn from.
const EATERIES := ["SUSHI", "PIZZA", "TACOS", "COFFEE STOP", "DELI", "BAKERY", "BOBA", "JUGOS FRESCOS"]
## Linear colours and strengths (the column's peak, before the water's Fresnel).
const PEDESTAL := Color(1.0, 0.72, 0.42)
const ANCHOR := Color(1.0, 0.95, 0.85)
const CABIN := Color(1.0, 0.62, 0.3)
const LAMP_SODIUM := Color(1.0, 0.6, 0.26)
const LAMP_LED := Color(0.86, 0.9, 1.0)
const NAV_GAIN := 7.0
## A quay lamp counts when it stands this close to the water's edge (car park lamps behind the
## buildings never reach the water).
const LAMP_EDGE := 9.0

static var enabled := OS.get_environment("MARINA_NIGHT") != "0"
## The plan, for the quay lamps' types (StreetLamps.place); set by MarinaGolden.ensure().
static var plan: CityPlan = null
static var _cache_key := -1
static var _cache: Array = []
static var _fronts: Array = []


## Every light the water can mirror: [true world position, linear colour x strength, size (m),
## half width (m)], pure but for the plan's lamp types. Cached per marina.
static func lights_for(mr: Marina) -> Array:
	var key := mr.get_instance_id()
	if key == _cache_key:
		return _cache
	_cache_key = key
	_cache = []
	var y := Marina.DOCK_Y
	# The dock pedestals, as MarinaBuild._dock_step() places them.
	for d: Dictionary in mr.docks:
		if str(d.kind) == "finger":
			continue
		var a: Vector2 = d.a
		var b: Vector2 = d.b
		var dir := (b - a).normalized()
		var n := Vector2(-dir.y, dir.x)
		var count := int(a.distance_to(b) / 9.4)
		for k in count:
			if k % MarinaBuild.DOCK_LIGHT_EVERY != 0:
				continue
			var s := 1.0 if k % 2 == 0 else -1.0
			var q := a.lerp(b, (float(k) + 0.5) / count) + n * s * (float(d.w) * 0.5 - 0.35)
			_cache.append([Vector3(q.x, y + 1.22, q.y), PEDESTAL * 2.2, 0.16, 0.0])
	# The boats: anchor lights at the masthead, lit cabins' windows.
	for bt: Dictionary in mr.boats:
		var t := int(bt.type)
		var s := float(bt.scale)
		var p: Vector2 = bt.p
		var xf := Transform3D(Basis(Vector3.UP, float(bt.yaw)).scaled(Vector3(s, s, s)), Vector3(p.x, Marina.WATER_Y + 0.02, p.y))
		if bool(bt.anchor):
			var tip := xf * Vector3(0.0, BoatMesh.air_draft(t, int(bt.variant)) + 0.12, float(Marina.REF_LEN[t]) * -0.1)
			_cache.append([tip, ANCHOR * 3.0, 0.12, 0.0])
		if bool(bt.lit):
			var row: Array = MarinaGolden.pack(bt)
			var hb: Vector4 = row[1]
			var cy := lerpf(hb.y, hb.z, 0.55) + Marina.WATER_Y
			_cache.append([Vector3(p.x, cy, p.y), CABIN * 1.1, 0.3, Marina._beam(t, float(bt.len)) * 0.3])
	# The nav lights (MarinaBuild._lights_step()'s heights).
	for nl: Dictionary in mr.nav_lights:
		var p: Vector2 = nl.p
		var top := Marina.JETTY_TOP if absf(p.y - mr.zc) < Marina.CHANNEL_HALF + 20.0 else Marina.BREAKWATER_TOP
		var h := 9.5 if bool(nl.tower) else 5.0
		var c: Color = nl.color
		_cache.append([Vector3(p.x, top + h + 0.55, p.y), Color(c.r, c.g, c.b) * NAV_GAIN, 0.35, 0.0])
	# The quay lamps by the water.
	for p: Vector2 in mr.lamps:
		if _edge_distance(mr, p) > LAMP_EDGE:
			continue
		var head := Vector3(p.x, CityChunk.SIDEWALK_TOP + 5.5, p.y)
		if plan != null:
			var lp := StreetLamps.place(plan, Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y), Vector2.ZERO)
			var acc := Vector3.ZERO
			for l: Vector3 in lp.lights:
				acc += l
			if not (lp.lights as Array).is_empty():
				head = acc / float((lp.lights as Array).size())
		head.y += Marina.QUAY_Y
		var col := LAMP_LED if NightCity.lamp_led(p) else LAMP_SODIUM
		_cache.append([head, col * 3.0, 0.25, 0.0])
	# The restaurants' fronts: [a (x, z), b (x, z), base y, top y, the bulkhead's line z, its top].
	_fronts = []
	for bd: Dictionary in mr.buildings:
		if str(bd.kind) != "restaurant":
			continue
		var r: Rect2 = bd.rect
		var base := CityChunk.SIDEWALK_TOP + Marina.QUAY_Y
		_fronts.append([Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), base, base + 7.5, mr.z_north, base])
	return _cache


static func fronts_for(mr: Marina) -> Array:
	lights_for(mr)
	return _fronts


## How far a point is from the basin's water (0 inside it).
static func _edge_distance(mr: Marina, p: Vector2) -> float:
	if Geometry2D.is_point_in_polygon(p, mr.water):
		return 0.0
	var best := INF
	for i in mr.water.size():
		var a: Vector2 = mr.water[i]
		var b: Vector2 = mr.water[(i + 1) % mr.water.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## The MAX_LIGHTS lights nearest `cam` (true world xz) within REACH, nearest first.
static func pick(mr: Marina, cam: Vector2) -> Array:
	var near: Array = []
	for l: Array in lights_for(mr):
		var p: Vector3 = l[0]
		var d := Vector2(p.x, p.z).distance_squared_to(cam)
		if d < REACH * REACH:
			near.append([d, l])
	near.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var out: Array = []
	for k in mini(near.size(), MAX_LIGHTS):
		out.append(near[k][1])
	return out


## Packs the picks into the water material. Returns how many lights.
static func push(mat: ShaderMaterial, mr: Marina, cam: Vector2) -> int:
	if not enabled or mr == null:
		mat.set_shader_parameter("ml_count", 0)
		mat.set_shader_parameter("mf_count", 0)
		return 0
	var picked := pick(mr, cam)
	var lp := PackedVector4Array()
	var lc := PackedVector4Array()
	lp.resize(MAX_LIGHTS)
	lc.resize(MAX_LIGHTS)
	for i in picked.size():
		var l: Array = picked[i]
		var p: Vector3 = l[0]
		var c: Color = l[1]
		lp[i] = Vector4(p.x, p.y, p.z, float(l[2]))
		lc[i] = Vector4(c.r, c.g, c.b, float(l[3]))
	var fa := PackedVector4Array()
	var fb := PackedVector4Array()
	fa.resize(MAX_FRONTS)
	fb.resize(MAX_FRONTS)
	var fronts := fronts_for(mr)
	var nf := mini(fronts.size(), MAX_FRONTS)
	for i in nf:
		var f: Array = fronts[i]
		var a: Vector2 = f[0]
		var b: Vector2 = f[1]
		fa[i] = Vector4(a.x, a.y, b.x, b.y)
		fb[i] = Vector4(float(f[2]), float(f[3]), float(f[4]), float(f[5]))
	mat.set_shader_parameter("ml_p", lp)
	mat.set_shader_parameter("ml_c", lc)
	mat.set_shader_parameter("ml_count", picked.size())
	mat.set_shader_parameter("mf_a", fa)
	mat.set_shader_parameter("mf_b", fb)
	mat.set_shader_parameter("mf_count", nf)
	return picked.size()


## The eateries' indices in Building.SHOP_NAMES (a restaurant's `name_pool`).
static func eatery_pool() -> PackedInt32Array:
	var out := PackedInt32Array()
	if not enabled:
		return out
	for nm: String in EATERIES:
		var i := Building.SHOP_NAMES.find(nm)
		if i >= 0:
			out.append(i)
	return out


## The bulkheads' wall face (shaders/marina_seawall.gdshader): the concrete set's maps, the tide
## zone over the marina's water, the streaks from the coping.
static func seawall_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/marina_seawall.gdshader")
	m.set_shader_parameter("albedo_tex", PropFactory.texture("concrete", "Color"))
	m.set_shader_parameter("normal_tex", PropFactory.texture("concrete", "NormalGL"))
	m.set_shader_parameter("rough_tex", PropFactory.texture("concrete", "Roughness"))
	m.set_shader_parameter("water_y", Marina.WATER_Y)
	m.set_shader_parameter("coping_y", Marina.QUAY_Y + CityChunk.SIDEWALK_TOP)
	return m
