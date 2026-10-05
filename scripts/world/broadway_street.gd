class_name BroadwayStreet
extends RefCounted
## Broadway's pavements in the theatre district (Broadway): its own street lamps, the street
## clock on two corners, and the shops' goods out on the pavement - racks of clothes, gowns on
## dress forms (quinceañera and bridal), tables of discount goods. All of it built in code at
## real size; every placement a hash of the seed and the block (never the chunk rng).
##
## The lamp is an original cast-iron design, not a copy of any real city's: an octagonal plinth,
## a fluted column, a collar of leaves, a cross-arm with two pendant lanterns and a lantern on top,
## green-black paint, frosted globes lit after dark (lamp_factor), its pool and a real light like
## every street lamp (CityChunk._add_lamp's prop slot, so prop ids do not move).

const LAMP_HEIGHT := 5.6
const LAMP_IRON := Color(0.09, 0.13, 0.11)
## How far from the kerb the shops' goods stand (m): against the building line.
const GOODS_FROM_KERB := 4.6
const GOODS_STEP := 4.2
const GOODS_ODDS := 0.62
## A palace's frontage and the corners keep this clear of goods (m).
const CORNER_CLEAR := 7.0
## The street clocks: [block's north cross street, side (-1 west / +1 east), corner (-1 north end,
## +1 south end)].
const CLOCKS := [["7TH ST", 1, -1], ["4TH ST", -1, -1]]
const GOWN_COLORS := [Color(0.95, 0.94, 0.92), Color(0.93, 0.62, 0.74), Color(0.62, 0.52, 0.86),
	Color(0.36, 0.78, 0.80), Color(0.86, 0.20, 0.30), Color(0.98, 0.86, 0.60), Color(0.95, 0.80, 0.86)]

static var _cache: Dictionary = {}


# --- The lamp ---------------------------------------------------------------------------------

## CityChunk's lamp slot, Broadway's lantern in it (FULL chunks only build pavement props).
static func add_lamp(ch: CityChunk, at: Vector3, _inward: Vector2) -> void:
	var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(CityChunk.LAMP_POOL_SIZE, 1.0, CityChunk.LAMP_POOL_SIZE)), at + Vector3(0.0, 0.09, 0.0))
	ch._add_prop("lamp", at, LAMP_IRON, [
		["bw_lamp", lamp_mesh(), Transform3D(Basis(), at)],
		["lamp_pool", PropFactory.light_pool(), pool],
	], [[Vector3(0.4, LAMP_HEIGHT, 0.4), at + Vector3(0.0, LAMP_HEIGHT * 0.5, 0.0), 0.0]])
	ch._batch.set_no_shadow("lamp_pool")
	if ch.level != CityChunk.Level.FULL:
		return
	var light := OmniLight3D.new()
	light.position = at + Vector3(0.0, LAMP_HEIGHT - 0.8 + ch._gy(at.x, at.z), 0.0)
	light.omni_range = 11.0
	light.omni_attenuation = 1.4
	light.light_color = Color(1.0, 0.84, 0.60)
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 15.0
	light.add_to_group("lamp_light")
	ch.add_child(light)


## A surface of revolution about y from `profile` ([radius, y] pairs, bottom up), `segs` sides,
## into `st` (smooth normals from the profile's slope). `flutes` > 0 cuts that many shallow
## grooves into the radius.
static func lathe(st: SurfaceTool, profile: Array, segs: int, col: Color, centre: Vector3 = Vector3.ZERO, flutes: int = 0) -> void:
	for j in profile.size() - 1:
		var p0: Vector2 = profile[j]
		var p1: Vector2 = profile[j + 1]
		var slope := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var f0 := 1.0
			var f1 := 1.0
			if flutes > 0:
				f0 = 1.0 - 0.08 * maxf(cos(a0 * float(flutes)), 0.0)
				f1 = 1.0 - 0.08 * maxf(cos(a1 * float(flutes)), 0.0)
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var v00 := centre + d0 * p0.x * f0 + Vector3(0.0, p0.y, 0.0)
			var v01 := centre + d0 * p1.x * f0 + Vector3(0.0, p1.y, 0.0)
			var v10 := centre + d1 * p0.x * f1 + Vector3(0.0, p0.y, 0.0)
			var v11 := centre + d1 * p1.x * f1 + Vector3(0.0, p1.y, 0.0)
			var n0 := (d0 * slope.x + Vector3(0.0, slope.y, 0.0)).normalized()
			var n1 := (d1 * slope.x + Vector3(0.0, slope.y, 0.0)).normalized()
			var nm := (n0 + n1).normalized()
			var u0 := float(i) / float(segs)
			var u1 := float(i + 1) / float(segs)
			tri(st, [v00, v10, v11], [n0, n1, n1], [Vector2(u0, p0.y), Vector2(u1, p0.y), Vector2(u1, p1.y)], col, nm)
			tri(st, [v00, v11, v01], [n0, n1, n0], [Vector2(u0, p0.y), Vector2(u1, p1.y), Vector2(u0, p1.y)], col, nm)


## One triangle into `st`, wound to face `want` (Godot's front faces: (c - a) x (b - a) along it).
static func tri(st: SurfaceTool, v: Array, n: Array, uv: Array, col: Color, want: Vector3) -> void:
	var a: Vector3 = v[0]
	var b: Vector3 = v[1]
	var c: Vector3 = v[2]
	var order := [0, 1, 2]
	if (c - a).cross(b - a).dot(want) < 0.0:
		order = [0, 2, 1]
	for k: int in order:
		st.set_color(col)
		st.set_normal(n[k])
		st.set_uv(uv[k])
		st.add_vertex(v[k])


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, b: Basis = Basis()) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.FORWARD], [Vector3.LEFT, Vector3.UP, Vector3.BACK],
		[Vector3.BACK, Vector3.UP, Vector3.RIGHT], [Vector3.FORWARD, Vector3.UP, Vector3.LEFT],
		[Vector3.UP, Vector3.FORWARD, Vector3.RIGHT], [Vector3.DOWN, Vector3.BACK, Vector3.RIGHT],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var up: Vector3 = f[1]
		var rt: Vector3 = f[2]
		var o := n * Vector3(h.x, h.y, h.z).dot(n.abs())
		var u := rt * absf(Vector3(h.x, h.y, h.z).dot(rt.abs()))
		var v := up * absf(Vector3(h.x, h.y, h.z).dot(up.abs()))
		var q := [o - u - v, o - u + v, o + u + v, o + u - v]
		var wn := (b * n).normalized()
		var wq: Array = []
		var uq: Array = []
		for k in 4:
			wq.append(c + b * (q[k] as Vector3))
			uq.append(Vector2((q[k] as Vector3).x + (q[k] as Vector3).z, (q[k] as Vector3).y))
		tri(st, [wq[0], wq[1], wq[2]], [wn, wn, wn], [uq[0], uq[1], uq[2]], col, wn)
		tri(st, [wq[0], wq[2], wq[3]], [wn, wn, wn], [uq[0], uq[2], uq[3]], col, wn)


## Broadway's lantern: iron (vertex-coloured, instance tint) and frosted glass (lit).
static func lamp_mesh() -> Mesh:
	if _cache.has("lamp"):
		return _cache.lamp
	var iron := SurfaceTool.new()
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := LAMP_IRON
	# Plinth (octagonal), base mouldings, the fluted column, the collar.
	lathe(iron, [Vector2(0.30, 0.0), Vector2(0.30, 0.38), Vector2(0.26, 0.42), Vector2(0.24, 0.62), Vector2(0.20, 0.66),
		Vector2(0.16, 0.74), Vector2(0.15, 0.80)], 8, w)
	lathe(iron, [Vector2(0.15, 0.80), Vector2(0.11, 3.9)], 16, w, Vector3.ZERO, 8)
	lathe(iron, [Vector2(0.11, 3.9), Vector2(0.15, 3.98), Vector2(0.20, 4.10), Vector2(0.16, 4.20), Vector2(0.09, 4.26),
		Vector2(0.08, 4.62), Vector2(0.12, 4.68), Vector2(0.08, 4.74)], 12, w)
	# The cross-arm with scrolls under it, the two pendants.
	_box(iron, Vector3(0.0, 4.55, 0.0), Vector3(1.6, 0.07, 0.07), w)
	for sx: float in [-1.0, 1.0]:
		for k in 5:
			var a := PI * float(k) / 5.0
			_box(iron, Vector3(sx * (0.25 + 0.22 * (1.0 - cos(a))), 4.42 - 0.12 * sin(a), 0.0), Vector3(0.12, 0.035, 0.035), w, Basis(Vector3.BACK, sx * a))
		var px := sx * 0.78
		lathe(iron, [Vector2(0.15, 4.32), Vector2(0.13, 4.36), Vector2(0.03, 4.42), Vector2(0.03, 4.55)], 8, w, Vector3(px, 0.0, 0.0))
		lathe(glass, [Vector2(0.0, 3.79), Vector2(0.06, 3.80), Vector2(0.14, 3.86), Vector2(0.18, 4.00), Vector2(0.17, 4.18), Vector2(0.10, 4.32)], 12, w, Vector3(px, 0.0, 0.0))
		lathe(iron, [Vector2(0.0, 3.68), Vector2(0.03, 3.72), Vector2(0.03, 3.82)], 6, w, Vector3(px, 0.0, 0.0))
	# The top lantern: a cage, the globe, a crown and finial.
	lathe(iron, [Vector2(0.08, 4.74), Vector2(0.20, 4.80), Vector2(0.20, 4.84)], 10, w)
	lathe(glass, [Vector2(0.17, 4.84), Vector2(0.24, 5.02), Vector2(0.25, 5.20), Vector2(0.20, 5.36), Vector2(0.10, 5.42)], 14, w)
	lathe(iron, [Vector2(0.10, 5.40), Vector2(0.22, 5.44), Vector2(0.16, 5.50), Vector2(0.05, 5.58), Vector2(0.03, 5.66), Vector2(0.0, 5.72)], 10, w)
	for k in 4:
		var a := TAU * float(k) / 4.0
		_box(iron, Vector3(cos(a) * 0.235, 5.12, sin(a) * 0.235), Vector3(0.025, 0.58, 0.025), w)
	var mesh := ArrayMesh.new()
	iron.commit(mesh)
	var im := StandardMaterial3D.new()
	im.albedo_color = Color(1, 1, 1)
	im.vertex_color_use_as_albedo = true
	im.metallic = 0.45
	im.roughness = 0.42
	mesh.surface_set_material(0, im)
	glass.commit(mesh)
	mesh.surface_set_material(1, globe_material())
	_cache.lamp = mesh
	return mesh


static func globe_material() -> ShaderMaterial:
	if _cache.has("globe"):
		return _cache.globe
	var sh := Shader.new()
	sh.code = """shader_type spatial;
#include "res://shaders/color_space.gdshaderinc"
global uniform float lamp_factor;
void fragment() {
	// Frosted glass: milky by day, glowing warm after dark, brightest at the bulb's height.
	float core = 1.0 - abs(UV.y - floor(UV.y) - 0.5);
	ALBEDO = cs_out(vec3(0.82, 0.80, 0.74));
	ROUGHNESS = 0.25;
	EMISSION = cs_out(vec3(1.0, 0.82, 0.55) * (0.05 + 3.4 * lamp_factor) * (0.8 + 0.2 * core));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_cache.globe = m
	return m


# --- The street clock ------------------------------------------------------------------------

## The dial: cream enamel, hour marks, hands set from DayNight's hour (BroadwayStreet.ClockSync
## updates the shared material once a second), backlit after dark.
static func clock_material() -> ShaderMaterial:
	if _cache.has("clock"):
		return _cache.clock
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/broadway_clock.gdshader")
	m.set_shader_parameter("hour", 9.0)
	_cache.clock = m
	return m


## Keeps the clock dials on the game's hour (one node per chunk that has a clock; the material is
## shared, so whichever runs sets it).
class ClockSync:
	extends Node
	var _t := 0.0

	func _process(delta: float) -> void:
		_t -= delta
		if _t > 0.0:
			return
		_t = 1.0
		var scene := get_tree().current_scene if get_tree() else null
		var day := scene.get_node_or_null("DayNight") if scene else null
		if day:
			BroadwayStreet.clock_material().set_shader_parameter("hour", float(day.get("hour")))


## The post clock: a plinth, a fluted column, a drum head with a dial each side, a finial.
static func clock_mesh() -> Mesh:
	if _cache.has("clock_mesh"):
		return _cache.clock_mesh
	var iron := SurfaceTool.new()
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dial := SurfaceTool.new()
	dial.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := LAMP_IRON
	lathe(iron, [Vector2(0.42, 0.0), Vector2(0.42, 0.5), Vector2(0.34, 0.56), Vector2(0.30, 0.9), Vector2(0.22, 1.0), Vector2(0.18, 1.1)], 8, w)
	lathe(iron, [Vector2(0.18, 1.1), Vector2(0.14, 3.2)], 16, w, Vector3.ZERO, 10)
	lathe(iron, [Vector2(0.14, 3.2), Vector2(0.24, 3.32), Vector2(0.30, 3.42)], 12, w)
	# The drum: a short cylinder lying across the street (its axis x), dials on both ends.
	var r := 0.55
	var c := Vector3(0.0, 4.0, 0.0)
	var segs := 28
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := Vector3(0.0, sin(a0) * r, cos(a0) * r)
		var p1 := Vector3(0.0, sin(a1) * r, cos(a1) * r)
		var n0 := Vector3(0.0, sin(a0), cos(a0))
		var n1 := Vector3(0.0, sin(a1), cos(a1))
		for side: float in [-1.0, 1.0]:
			var hx := Vector3(0.16 * side, 0.0, 0.0)
			# Rim band.
			var q := [c + p0 - hx, c + p1 - hx, c + p1 + hx, c + p0 + hx]
			if side > 0.0:
				var nm := (n0 + n1).normalized()
				tri(iron, [q[0], q[1], q[2]], [n0, n1, n1], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], w, nm)
				tri(iron, [q[0], q[2], q[3]], [n0, n1, n0], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], w, nm)
			# Dial face at this end, a bezel ring round it.
			var f := c + Vector3(0.17 * side, 0.0, 0.0)
			var nn := Vector3(side, 0.0, 0.0)
			var d0 := f + p0 * 0.86
			var d1 := f + p1 * 0.86
			# Dial UV: u to the viewer's right (-z seen from +x, +z seen from -x), v down.
			var uv0 := Vector2(0.5, 0.5)
			var uv1 := Vector2(0.5 - side * cos(a0) * 0.5, 0.5 - sin(a0) * 0.5)
			var uv2 := Vector2(0.5 - side * cos(a1) * 0.5, 0.5 - sin(a1) * 0.5)
			tri(dial, [f, d0, d1], [nn, nn, nn], [uv0, uv1, uv2], w, nn)
			var b0 := f + p0 * 0.86
			var b1 := f + p1 * 0.86
			var b2 := f + p1 * 1.04 + nn * 0.03
			var b3 := f + p0 * 1.04 + nn * 0.03
			var brass := Color(0.78, 0.60, 0.30)
			tri(iron, [b0, b1, b2], [nn, nn, nn], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], brass, nn)
			tri(iron, [b0, b2, b3], [nn, nn, nn], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], brass, nn)
	lathe(iron, [Vector2(0.10, 4.55), Vector2(0.18, 4.62), Vector2(0.10, 4.75), Vector2(0.05, 4.95), Vector2(0.0, 5.05)], 10, Color(0.78, 0.60, 0.30))
	lathe(iron, [Vector2(0.20, 3.42), Vector2(0.10, 3.45)], 10, w)
	var mesh := ArrayMesh.new()
	iron.commit(mesh)
	var im := StandardMaterial3D.new()
	im.albedo_color = Color(1, 1, 1)
	im.vertex_color_use_as_albedo = true
	im.metallic = 0.5
	im.roughness = 0.4
	mesh.surface_set_material(0, im)
	dial.commit(mesh)
	mesh.surface_set_material(1, clock_material())
	_cache.clock_mesh = mesh
	return mesh


# --- The block --------------------------------------------------------------------------------

## A Broadway block's pavement life (Broadway.block_step()): goods outside the shops on the
## Broadway face, the clock if this block has one. `rect` is the block (kerb lines).
static func build_block(ch: CityChunk, rect: Rect2, side: int) -> void:
	var plan := ch.plan
	var kerb_x := rect.end.x if side < 0 else rect.position.x
	var inward := -1.0 if side < 0 else 1.0
	# Palaces on this block's face keep their frontage clear.
	var clear: Array[Vector2] = []
	for p: Dictionary in Broadway.palaces(plan):
		if p.block == Vector2i(ch.ix, ch.iz):
			var lot: Dictionary = p.lot
			clear.append(Vector2((lot.center as Vector2).y - (lot.size as Vector2).y * 0.5, (lot.center as Vector2).y + (lot.size as Vector2).y * 0.5))
	var x := kerb_x + inward * GOODS_FROM_KERB
	var face := -1.0 * inward
	var yaw := atan2(-face, 0.0)
	var z := rect.position.y + CORNER_CLEAR
	var i := 0
	var mats := [lamp_mesh()]
	while z < rect.end.y - CORNER_CLEAR:
		var skip := false
		for c: Vector2 in clear:
			if z > c.x - 1.0 and z < c.y + 1.0:
				skip = true
		var roll := Broadway.h01([plan.seed, ch.ix, ch.iz, "bw_goods", i])
		if not skip and roll < GOODS_ODDS:
			var kind := Broadway.h01([plan.seed, ch.ix, ch.iz, "bw_goods_kind", i])
			var at := Vector3(x, CityChunk.SIDEWALK_TOP, z)
			var b := Basis(Vector3.UP, yaw)
			if kind < 0.38:
				ch._batch.add("bw_rack", rack_mesh(), Transform3D(b, at))
			elif kind < 0.72:
				# Two or three gowns on forms, side by side.
				var n := 2 + int(Broadway.h01([plan.seed, ch.ix, ch.iz, "bw_gowns", i]) * 2.0)
				for k in n:
					var gc: Color = GOWN_COLORS[absi(hash([plan.seed, ch.ix, ch.iz, "gown", i, k])) % GOWN_COLORS.size()]
					ch._batch.add("bw_gown", gown_mesh(), Transform3D(b, at + Vector3(0.0, 0.0, (float(k) - float(n - 1) * 0.5) * 1.05)), gc)
			else:
				ch._batch.add("bw_table", table_mesh(), Transform3D(b, at))
		z += GOODS_STEP
		i += 1
	# The street clock on its corner.
	for cl: Array in CLOCKS:
		if int(cl[1]) != side:
			continue
		var north_z := Broadway.street_z(str(cl[0]))
		if absf(rect.position.y - (north_z + plan.road_width(CityPlan.AXIS_Z, ch.iz) * 0.5)) > 1.5:
			continue
		var cz := rect.position.y + 2.2 if int(cl[2]) < 0 else rect.end.y - 2.2
		var at := Vector3(kerb_x + inward * 1.1, CityChunk.SIDEWALK_TOP, cz)
		var node := MeshInstance3D.new()
		node.name = "BroadwayClock"
		node.mesh = clock_mesh()
		node.position = at + Vector3(0.0, ch._gy(at.x, at.z), 0.0)
		ch.add_child(node)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.42
		shape.height = 4.6
		cs.shape = shape
		cs.position = Vector3(0.0, 2.3, 0.0)
		body.add_child(cs)
		node.add_child(body)
		node.add_child(ClockSync.new())


## A clothes rack: a chrome rail on two T-feet, garments on hangers in a row (vertex colours).
static func rack_mesh() -> Mesh:
	if _cache.has("rack"):
		return _cache.rack
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var chrome := Color(0.75, 0.76, 0.78)
	for sx: float in [-0.75, 0.75]:
		_box(st, Vector3(0.0, 0.02, sx), Vector3(0.5, 0.03, 0.04), chrome)
		_box(st, Vector3(0.0, 0.78, sx), Vector3(0.03, 1.52, 0.03), chrome)
	_box(st, Vector3(0.0, 1.55, 0.0), Vector3(0.03, 0.03, 1.56), chrome)
	var n := 11
	for k in n:
		var z := -0.68 + float(k) * 1.36 / float(n - 1)
		var c := Color.from_hsv(fmod(float(k) * 0.37 + 0.05, 1.0), 0.45 + 0.4 * fmod(float(k) * 0.53, 1.0), 0.35 + 0.5 * fmod(float(k) * 0.71, 1.0))
		var long := k % 3 == 0
		var hgt := 0.95 if long else 0.62
		_box(st, Vector3(0.0, 1.5 - hgt * 0.5 - 0.04, z), Vector3(0.44 - (0.0 if long else 0.06), hgt, 0.05), c)
		_box(st, Vector3(0.0, 1.5 - 0.06, z), Vector3(0.40, 0.03, 0.02), Color(0.2, 0.2, 0.22))
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, _vc_material(0.8))
	_cache.rack = mesh
	return mesh


## A dress form wearing a ball gown: a stand, a bodice, a full layered skirt (the instance colour).
static func gown_mesh() -> Mesh:
	if _cache.has("gown"):
		return _cache.gown
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := Color.WHITE
	# Skirt tiers, flaring out, each with a ruffled hem.
	lathe(st, [Vector2(0.48, 0.06), Vector2(0.44, 0.30), Vector2(0.36, 0.55), Vector2(0.27, 0.80), Vector2(0.17, 0.98), Vector2(0.12, 1.02)], 18, w)
	lathe(st, [Vector2(0.50, 0.04), Vector2(0.52, 0.10), Vector2(0.47, 0.14)], 18, Color(0.92, 0.92, 0.92))
	# Bodice and the form's shoulders.
	lathe(st, [Vector2(0.12, 1.02), Vector2(0.13, 1.18), Vector2(0.15, 1.32), Vector2(0.14, 1.38), Vector2(0.06, 1.42)], 12, w)
	# The stand's neck knob and the base under the skirt (dark).
	lathe(st, [Vector2(0.03, 1.42), Vector2(0.03, 1.52), Vector2(0.05, 1.55), Vector2(0.0, 1.58)], 8, Color(0.25, 0.20, 0.16))
	lathe(st, [Vector2(0.22, 0.0), Vector2(0.22, 0.04)], 10, Color(0.15, 0.15, 0.16))
	var mesh := st.commit()
	var m := _vc_material(0.6)
	m.set_meta("gown", true)
	mesh.surface_set_material(0, m)
	_cache.gown = mesh
	return mesh


## A folding sale table of goods: boxes, stacked phones and radios, a price board.
static func table_mesh() -> Mesh:
	if _cache.has("table"):
		return _cache.table
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0.0, 0.74, 0.0), Vector3(0.75, 0.04, 1.8), Color(0.88, 0.87, 0.84))
	for sx: float in [-0.8, 0.8]:
		for sz: float in [-0.3, 0.3]:
			_box(st, Vector3(sz, 0.36, sx), Vector3(0.03, 0.72, 0.03), Color(0.3, 0.3, 0.32))
	for k in 9:
		var c := Color.from_hsv(fmod(float(k) * 0.29, 1.0), 0.55, 0.45 + 0.4 * fmod(float(k) * 0.61, 1.0))
		var s := Vector3(0.18 + 0.1 * fmod(float(k) * 0.43, 1.0), 0.08 + 0.18 * fmod(float(k) * 0.77, 1.0), 0.14 + 0.1 * fmod(float(k) * 0.31, 1.0))
		_box(st, Vector3(-0.2 + 0.2 * float(k % 3), 0.76 + s.y * 0.5, -0.7 + 0.18 * float(k)), s, c)
	# A price board on a stand at the end.
	_box(st, Vector3(0.0, 1.1, 0.95), Vector3(0.6, 0.45, 0.03), Color(0.95, 0.85, 0.15))
	_box(st, Vector3(0.0, 0.5, 0.95), Vector3(0.03, 1.0, 0.03), Color(0.3, 0.3, 0.32))
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, _vc_material(0.7))
	_cache.table = mesh
	return mesh


static func _vc_material(rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	return m
