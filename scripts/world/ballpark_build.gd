class_name BallparkBuild
extends RefCounted
## The ballpark's meshes (Ballpark has the data): the seating bowl's four tiers wrapping the
## infield, the outfield pavilions under their zig-zag roofs, the hexagonal scoreboards, the light
## banks on the roof lines, the field, the outfield wall, foul poles and dugouts, the backstop net,
## the bridges from the upper terrace, the plaza and the terraced car parks, their light poles,
## parked cars and palms.
##
## Built in WORLD space (the landmark's parent sits at the world origin of its chunk, as every
## landmark does), from Ballpark's frame. Everything static is cached per detail level ("near",
## "far"), so the far copy built on the loading screen and the detailed one a chunk builds cost
## their meshes once. Materials (one each): ballpark_struct (kind in the vertex alpha), ballpark_seats
## (the crowd), ballpark_field, ballpark_lot (stalls and painted cars), the light banks' glare on
## aircraft_lights.gdshader, ballpark_glow (the night game's haze) and the backstop net.
##
## Draws: near ~9 (+ the batches: cars by tile, poles, palms); far 6. Every roll is a hash of the
## stall or the spot (Ballpark.ihash01), never a chunk rng.

const DIRL := Vector2(-0.70710678, 0.70710678)
const DIRR := Vector2(0.70710678, 0.70710678)
const NL := Vector2(-0.70710678, -0.70710678)
const NR := Vector2(0.70710678, -0.70710678)

## Concrete, cream fascia paint, dark steel, roof membrane, the field-level wall's navy, the
## outfield padding, foul-pole yellow (sRGB, as written into the vertex colour).
const C_CONCRETE := Color(0.66, 0.64, 0.6)
const C_INNER := Color(0.6, 0.59, 0.56)
const C_CREAM := Color(0.9, 0.88, 0.82)
const C_STEEL := Color(0.2, 0.22, 0.25)
const C_ROOF := Color(0.86, 0.87, 0.86)
## The roofs' undersides: white-painted steel.
const C_SOFFIT := Color(0.78, 0.79, 0.79)
const C_NAVY := Color(0.1, 0.17, 0.3)
const C_PAD := Color(0.08, 0.2, 0.35)
const C_YELLOW := Color(0.96, 0.82, 0.12)
const C_DARK := Color(0.05, 0.05, 0.05)
const PAVILION_SEAT := Color(0.32, 0.55, 0.85)

const K_FACADE := 0
const K_INNER := 1
const K_PAINT := 2
const K_STEEL := 3
const K_ROOF := 4
const K_DARK := 5
const K_PAD := 6
const K_SCREEN := 7
const K_BAND := 8
const K_POLE := 9
const K_LENS := 10
const K_OPEN := 11

## The light banks' faces: lenses across and up, their pitch.
const BANK_COLS := 7
const BANK_ROWS := 3
const LENS := 0.95
## Parked 3D cars: within this reach of home (the painted ones carry the rest), tiles of this size
## each drawn to CAR_DRAW.
const CAR_REACH := 165.0
const CAR_TILE := 80.0
const CAR_DRAW := 120.0

static var _cache: Dictionary = {}
static var _mats: Dictionary = {}
static var _pole_mesh: Mesh = null
## Triangles and surfaces per level, for probes and checks (mesh data is not readable headless).
static var stats: Dictionary = {}


## One growing surface: world-space triangles facing the direction asked for.
class Acc:
	extends RefCounted
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var uv2 := PackedVector2Array()
	var tris: int = 0

	func tri(a: Vector3, b: Vector3, c: Vector3, want: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, cl: Color) -> void:
		var flat := (c - a).cross(b - a)
		if flat.length_squared() < 1e-12:
			return
		if flat.dot(want) < 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
			flat = -flat
		var fn := flat.normalized()
		v.append_array(PackedVector3Array([a, b, c]))
		n.append_array(PackedVector3Array([fn, fn, fn]))
		uv.append_array(PackedVector2Array([ua, ub, uc]))
		col.append_array(PackedColorArray([cl, cl, cl]))
		tris += 1

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, cl: Color) -> void:
		tri(a, b, c, want, ua, ub, uc, cl)
		tri(a, c, d, want, ua, uc, ud, cl)

	## A quad with its own normals per corner (the lot and the field follow the ground).
	func quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
			ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
		var want := na + nb + nc + nd
		var pts := [[a, na, ua, ca], [b, nb, ub, cb], [c, nc, uc, cc], [a, na, ua, ca], [c, nc, uc, cc], [d, nd, ud, cd]]
		for k in 2:
			var p0: Array = pts[k * 3]
			var p1: Array = pts[k * 3 + 1]
			var p2: Array = pts[k * 3 + 2]
			var flat := ((p2[0] as Vector3) - (p0[0] as Vector3)).cross((p1[0] as Vector3) - (p0[0] as Vector3))
			if flat.length_squared() < 1e-12:
				continue
			if flat.dot(want) < 0.0:
				var t: Array = p1
				p1 = p2
				p2 = t
			for p: Array in [p0, p1, p2]:
				v.append(p[0])
				n.append(p[1])
				uv.append(p[2])
				col.append(p[3])
			tris += 1

	func mesh(mat: Material, tangents: bool = false) -> ArrayMesh:
		var m := ArrayMesh.new()
		if v.is_empty():
			return m
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_COLOR] = col
		if tangents:
			var st := SurfaceTool.new()
			st.create_from_arrays(arrays)
			st.generate_tangents()
			st.commit(m)
		else:
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, mat)
		return m


# --- Materials -------------------------------------------------------------------------------

static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"struct", "seats", "field", "lot", "glow":
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/ballpark_%s.gdshader" % key)
			m = sm
		"glare":
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/aircraft_lights.gdshader")
			sm.set_shader_parameter("field_day", 0.0)
			sm.set_shader_parameter("hdr", 3.0)
			sm.set_shader_parameter("min_angle", 0.0035)
			m = sm
		"net":
			var sm := StandardMaterial3D.new()
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.albedo_color = Color(0.06, 0.06, 0.06, 0.22)
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m = sm
	_mats[key] = m
	return m


static func _kc(c: Color, k: int) -> Color:
	return Color(c.r, c.g, c.b, float(k) / 16.0)


static func _w(q: Vector2, y: float) -> Vector3:
	return Ballpark.world3(q.x, q.y, Ballpark.PAD_Y + y)


static func _wdir(q: Vector2) -> Vector3:
	var d := Ballpark.RIGHT * q.x + Ballpark.FWD * q.y
	return Vector3(d.x, 0.0, d.y)


# --- The bowl's path -----------------------------------------------------------------------------

## The stations of a tier `a_end` metres down the lines, LF end to RF end: [base (local), outward
## normal (local)]. A row `D` out is base + normal D: the two foul lines' parallels joined by an arc
## round home.
static func path(a_end: float, step: float = 6.0, arc_steps: int = 12) -> Array:
	var out: Array = []
	var nl := maxi(2, ceili(a_end / step))
	for i in nl + 1:
		var a := a_end * (1.0 - float(i) / nl)
		out.append([DIRL * a, NL])
	for i in range(1, arc_steps):
		var phi := deg_to_rad(225.0 + 90.0 * float(i) / arc_steps)
		out.append([Vector2.ZERO, Vector2(cos(phi), sin(phi))])
	for i in nl + 1:
		var a := a_end * float(i) / nl
		out.append([DIRR * a, NR])
	return out


static func _at(st: Array, d: float) -> Vector2:
	return (st[0] as Vector2) + (st[1] as Vector2) * d


## Cumulative arc length along a row `d` out.
static func _run(sts: Array, d: float) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	r.append(0.0)
	for j in range(1, sts.size()):
		r.append(r[j - 1] + _at(sts[j], d).distance_to(_at(sts[j - 1], d)))
	return r


# --- Build ---------------------------------------------------------------------------------------

## The landmark's builder (Landmarks.build): `statics` null for the far copy.
static func build(parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	if not Ballpark.enabled():
		return
	var level := "near" if detailed else "far"
	var c := _meshes(level)
	if not detailed:
		# The far copy is built on the loading screen: build the detailed meshes there too, so the
		# chunk that streams the park in later does not stall a third of a second on them.
		_meshes("near")
	var holder := Node3D.new()
	holder.name = "Ballpark"
	parent.add_child(holder)
	for key: String in ["struct", "seats", "field", "lot", "glare", "net"]:
		if not c.has(key):
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Ballpark_" + key
		mi.mesh = c[key]
		var casts := key == "struct" or key == "seats"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	# The night game's haze over the bowl.
	var glow := MeshInstance3D.new()
	glow.name = "Ballpark_glow"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24 if detailed else 16
	sphere.rings = 12 if detailed else 8
	sphere.material = material("glow")
	glow.mesh = sphere
	var gc := _w(Vector2(0.0, 40.0), 10.0)
	var radii := Vector3(175.0, 95.0, 175.0)
	glow.transform = Transform3D(Basis().scaled(radii), gc)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(material("glow") as ShaderMaterial).set_shader_parameter("radii", radii)
	holder.add_child(glow)
	if not detailed:
		return
	if statics:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(c.collision)
		var cs := CollisionShape3D.new()
		cs.name = "BallparkShape"
		cs.shape = shape
		statics.add_child(cs)
	var batch := MultiMeshBatch.new()
	_cars(batch)
	_poles(batch)
	_palms(batch)
	batch.build(holder)
	# Real light on whatever is on the field after dark (desktop): DayNight drives the
	# "lamp_light" group with the street lamps, and Quality turns it off at the low levels.
	if not OS.has_feature("web"):
		for at: Vector2 in [Vector2(0.0, 20.0), Vector2(-45.0, 75.0), Vector2(45.0, 75.0)]:
			var light := OmniLight3D.new()
			light.name = "FieldLight"
			light.position = _w(at, 42.0)
			light.omni_range = 120.0
			light.omni_attenuation = 0.45
			light.light_color = Color(0.95, 0.97, 1.0)
			light.light_energy = 0.0
			light.shadow_enabled = false
			light.add_to_group("lamp_light")
			holder.add_child(light)


static func _meshes(level: String) -> Dictionary:
	if _cache.has(level):
		return _cache[level]
	var near := level == "near"
	var st := Acc.new()
	var seats := Acc.new()
	var glare := Acc.new()
	var net := Acc.new()
	var coll := PackedVector3Array()
	for t: Dictionary in Ballpark.TIERS:
		_tier(st, seats, coll, t, near)
	for side: int in [-1, 1]:
		_pavilion(st, seats, glare, coll, side, near)
	_roof_banks(st, glare, near)
	_wall(st, coll, near)
	_details(st, net, near)
	_bridges(st, coll, near)
	var out := {}
	out["struct"] = st.mesh(material("struct"))
	out["seats"] = seats.mesh(material("seats"))
	out["field"] = _field(near)
	out["lot"] = _lot(near)
	out["glare"] = _glare_mesh(glare)
	if near:
		out["net"] = net.mesh(material("net"))
		out["collision"] = coll
	stats[level] = {"struct": st.tris, "seats": seats.tris, "glare": glare.tris}
	_cache[level] = out
	return out


# --- The tiers -----------------------------------------------------------------------------------

## One tier: its stepped rows (seats), the front wall or fascia, the soffit under it, the
## concourse behind its last row with its lit stands, the facade outside, the end walls.
static func _tier(st: Acc, seats: Acc, coll: PackedVector3Array, t: Dictionary, near: bool) -> void:
	var d0: float = t.d
	var y0: float = t.y
	var rows: int = t.rows
	var dep: float = t.depth
	var rise: float = t.rise
	var a_end: float = t.end
	var field_level := String(t.name) == "field"
	var sts := path(a_end, 6.0 if near else 12.0, 12 if near else 6)
	var d_end := d0 + rows * dep
	var y_last := y0 + (rows - 1) * rise
	var d_back := d_end + Ballpark.CONCOURSE
	var y_top := y_last + 3.6
	var seat_col := Color(t.seat.r, t.seat.g, t.seat.b, float(t.fill))
	var front_c := C_NAVY if field_level else C_CREAM
	var y_bottom := 0.0 if field_level else y0 - Ballpark.FASCIA
	var y_under_back := y_last - 1.1
	var rc := {}
	for j in sts.size() - 1:
		var s0: Array = sts[j]
		var s1: Array = sts[j + 1]
		var out0 := _wdir(s0[1])
		var out1 := _wdir(s1[1])
		var outw := (out0 + out1).normalized()
		# Rows: riser at each row's front (the parapet for row 0), tread behind it.
		if near:
			for i in rows:
				var di := d0 + i * dep
				var yi := y0 + i * rise
				var ra := _rp(rc, sts, j, di)
				if i > 0:
					var yp := yi - rise
					seats.quad(_w(_at(s0, di), yp), _w(_at(s1, di), yp), _w(_at(s1, di), yi), _w(_at(s0, di), yi), -outw,
						Vector2(ra.x, i), Vector2(ra.y, i), Vector2(ra.y, i + 0.3), Vector2(ra.x, i + 0.3), seat_col)
				var rb := _rp(rc, sts, j, di + dep)
				seats.quad(_w(_at(s0, di), yi), _w(_at(s1, di), yi), _w(_at(s1, di + dep), yi), _w(_at(s0, di + dep), yi), Vector3.UP,
					Vector2(ra.x, i + 0.3), Vector2(ra.y, i + 0.3), Vector2(rb.y, i + 1.0), Vector2(rb.x, i + 1.0), seat_col)
		else:
			# Far: the rake as one sloped band (the shader shows it as its average).
			var ra := _rp(rc, sts, j, d0)
			seats.quad(_w(_at(s0, d0), y0), _w(_at(s1, d0), y0), _w(_at(s1, d_end), y_last), _w(_at(s0, d_end), y_last), Vector3.UP + -outw,
				Vector2(ra.x, 0.0), Vector2(ra.y, 0.0), Vector2(ra.y, rows), Vector2(ra.x, rows), seat_col)
		# The sloped plane through the rows, for walking on them.
		if near:
			_coll_quad(coll, _w(_at(s0, d0), y0), _w(_at(s1, d0), y0), _w(_at(s1, d_end), y_last), _w(_at(s0, d_end), y_last))
		# The front: a parapet a metre over row 0, down to the field (field level) or the fascia.
		var fa := _rp(rc, sts, j, d0 - 0.25)
		st.quad(_w(_at(s0, d0 - 0.25), y_bottom), _w(_at(s1, d0 - 0.25), y_bottom), _w(_at(s1, d0 - 0.25), y0 + 1.0), _w(_at(s0, d0 - 0.25), y0 + 1.0), -outw,
			Vector2(fa.x, y_bottom), Vector2(fa.y, y_bottom), Vector2(fa.y, y0 + 1.0), Vector2(fa.x, y0 + 1.0), _kc(front_c, K_PAINT))
		st.quad(_w(_at(s0, d0 - 0.25), y0 + 1.0), _w(_at(s1, d0 - 0.25), y0 + 1.0), _w(_at(s1, d0), y0 + 1.0), _w(_at(s0, d0), y0 + 1.0), Vector3.UP,
			Vector2(fa.x, 0.0), Vector2(fa.y, 0.0), Vector2(fa.y, 0.25), Vector2(fa.x, 0.25), _kc(front_c, K_PAINT))
		if near:
			st.quad(_w(_at(s0, d0), y0), _w(_at(s1, d0), y0), _w(_at(s1, d0), y0 + 1.0), _w(_at(s0, d0), y0 + 1.0), outw,
				Vector2(fa.x, 0.0), Vector2(fa.y, 0.0), Vector2(fa.y, 1.0), Vector2(fa.x, 1.0), _kc(C_INNER, K_INNER))
		if near:
			_coll_quad(coll, _w(_at(s0, d0 - 0.25), y_bottom), _w(_at(s1, d0 - 0.25), y_bottom), _w(_at(s1, d0 - 0.25), y0 + 1.0), _w(_at(s0, d0 - 0.25), y0 + 1.0))
		# Under an upper deck: its soffit, sloping up with the rake to the concourse.
		if not field_level:
			var sa := _rp(rc, sts, j, d0)
			st.quad(_w(_at(s0, d0 - 0.25), y_bottom), _w(_at(s1, d0 - 0.25), y_bottom), _w(_at(s1, d_end), y_under_back), _w(_at(s0, d_end), y_under_back), Vector3.DOWN - outw * 0.3,
				Vector2(sa.x, 0.0), Vector2(sa.y, 0.0), Vector2(sa.y, d_end - d0), Vector2(sa.x, d_end - d0), _kc(C_INNER, K_INNER))
			st.quad(_w(_at(s0, d_end), y_under_back), _w(_at(s1, d_end), y_under_back), _w(_at(s1, d_back), y_under_back), _w(_at(s0, d_back), y_under_back), Vector3.DOWN,
				Vector2(sa.x, 0.0), Vector2(sa.y, 0.0), Vector2(sa.y, 1.0), Vector2(sa.x, 1.0), _kc(C_INNER, K_INNER))
		# The concourse: its floor, the stands along its back wall (lit after dark), the wall over them.
		var ca := _rp(rc, sts, j, d_back)
		st.quad(_w(_at(s0, d_end), y_last), _w(_at(s1, d_end), y_last), _w(_at(s1, d_back), y_last), _w(_at(s0, d_back), y_last), Vector3.UP,
			Vector2(ca.x, 0.0), Vector2(ca.y, 0.0), Vector2(ca.y, 6.0), Vector2(ca.x, 6.0), _kc(C_INNER, K_INNER))
		if near:
			_coll_quad(coll, _w(_at(s0, d_end), y_last), _w(_at(s1, d_end), y_last), _w(_at(s1, d_back), y_last), _w(_at(s0, d_back), y_last))
		st.quad(_w(_at(s0, d_back), y_last), _w(_at(s1, d_back), y_last), _w(_at(s1, d_back), y_last + 2.6), _w(_at(s0, d_back), y_last + 2.6), -outw,
			Vector2(ca.x, 0.0), Vector2(ca.y, 0.0), Vector2(ca.y, 2.6), Vector2(ca.x, 2.6), _kc(Color(0.55, 0.5, 0.42), K_BAND))
		st.quad(_w(_at(s0, d_back), y_last + 2.6), _w(_at(s1, d_back), y_last + 2.6), _w(_at(s1, d_back), y_top), _w(_at(s0, d_back), y_top), -outw,
			Vector2(ca.x, y_last + 2.6), Vector2(ca.y, y_last + 2.6), Vector2(ca.y, y_top), Vector2(ca.x, y_top), _kc(C_INNER, K_INNER))
		# Outside: at field level a storeyed wall to the ground (the gates); higher up, each tier's
		# back is a band in the air - the deck's edge, a parapet, the open concourse between columns -
		# stepping out over the one below, on columns.
		var fo := _rp(rc, sts, j, d_back + 0.5)
		var ob := d_back + 0.5
		if field_level:
			st.quad(_w(_at(s0, ob), 0.0), _w(_at(s1, ob), 0.0), _w(_at(s1, ob), y_top), _w(_at(s0, ob), y_top), outw,
				Vector2(fo.x, 0.0), Vector2(fo.y, 0.0), Vector2(fo.y, y_top), Vector2(fo.x, y_top), _kc(C_CONCRETE, K_FACADE))
		else:
			var yp := y_last + 1.1
			st.quad(_w(_at(s0, ob), y_under_back), _w(_at(s1, ob), y_under_back), _w(_at(s1, ob), y_last), _w(_at(s0, ob), y_last), outw,
				Vector2(fo.x, 0.0), Vector2(fo.y, 0.0), Vector2(fo.y, 1.1), Vector2(fo.x, 1.1), _kc(C_CONCRETE, K_INNER))
			st.quad(_w(_at(s0, ob), y_last), _w(_at(s1, ob), y_last), _w(_at(s1, ob), yp), _w(_at(s0, ob), yp), outw,
				Vector2(fo.x, 0.0), Vector2(fo.y, 0.0), Vector2(fo.y, 1.1), Vector2(fo.x, 1.1), _kc(C_CREAM, K_PAINT))
			st.quad(_w(_at(s0, ob), yp), _w(_at(s1, ob), yp), _w(_at(s1, ob), y_top), _w(_at(s0, ob), y_top), outw,
				Vector2(fo.x, 0.0), Vector2(fo.y, 0.0), Vector2(fo.y, y_top - yp), Vector2(fo.x, y_top - yp), _kc(C_CONCRETE, K_OPEN))
			st.quad(_w(_at(s0, d_back), y_under_back), _w(_at(s1, d_back), y_under_back), _w(_at(s1, ob), y_under_back), _w(_at(s0, ob), y_under_back), Vector3.DOWN,
				Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(C_INNER, K_INNER))
		st.quad(_w(_at(s0, d_back), y_top), _w(_at(s1, d_back), y_top), _w(_at(s1, ob), y_top), _w(_at(s0, ob), y_top), Vector3.UP,
			Vector2(fo.x, 0.0), Vector2(fo.y, 0.0), Vector2(fo.y, 0.5), Vector2(fo.x, 0.5), _kc(C_CONCRETE, K_INNER))
		if near:
			var yc0 := 0.0 if field_level else y_under_back
			_coll_quad(coll, _w(_at(s0, ob), yc0), _w(_at(s1, ob), yc0), _w(_at(s1, ob), y_top), _w(_at(s0, ob), y_top))
		# Columns under an upper deck's back, every third station.
		if not field_level and near and j % 3 == 1:
			var cp := _at(s0, d_back - 1.0)
			_box(st, _w(cp, y_under_back * 0.5), Vector3(0.9, y_under_back, 0.9), _kc(C_INNER, K_INNER), s0[1])
	# The end walls: the section, solid to the ground at field level, under the deck above.
	for e in 2:
		var s: Array = sts[0] if e == 0 else sts[sts.size() - 1]
		var along := DIRL if e == 0 else DIRR
		var sec := PackedVector2Array()
		if field_level:
			sec.append(Vector2(d0 - 0.25, 0.0))
		else:
			sec.append(Vector2(d0 - 0.25, y_bottom))
		sec.append(Vector2(d0 - 0.25, y0 + 1.0))
		sec.append(Vector2(d0, y0 + 1.0))
		for i in rows:
			sec.append(Vector2(d0 + i * dep, y0 + i * rise))
			sec.append(Vector2(d0 + (i + 1) * dep, y0 + i * rise))
		sec.append(Vector2(d_back, y_last))
		sec.append(Vector2(d_back, y_top))
		sec.append(Vector2(d_back + 0.5, y_top))
		sec.append(Vector2(d_back + 0.5, 0.0))
		if not field_level:
			sec.append(Vector2(d_back - 1.0, 0.0))
			sec.append(Vector2(d_back - 1.0, y_under_back))
			sec.append(Vector2(d_end, y_under_back))
		_section(st, s, sec, _wdir(along), _kc(C_CONCRETE, K_FACADE))


## The arc length along the row `d` out at stations j and j + 1 (cumulative from the first
## station, cached per row in `rc`): the seats' and the facade's metre along the bowl.
static func _rp(rc: Dictionary, sts: Array, j: int, d: float) -> Vector2:
	var key := snappedf(d, 0.001)
	if not rc.has(key):
		rc[key] = _run(sts, d)
	var r: PackedFloat32Array = rc[key]
	return Vector2(r[j], r[j + 1])


## A planar section at station `s` (in its (D, y) plane), facing `face`, triangulated.
static func _section(st: Acc, s: Array, sec: PackedVector2Array, face: Vector3, cl: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(sec)
	for k in range(0, idx.size(), 3):
		var pa := sec[idx[k]]
		var pb := sec[idx[k + 1]]
		var pc := sec[idx[k + 2]]
		st.tri(_w(_at(s, pa.x), pa.y), _w(_at(s, pb.x), pb.y), _w(_at(s, pc.x), pc.y), face, pa, pb, pc, cl)


static func _coll_quad(coll: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	coll.append_array(PackedVector3Array([a, b, c, a, c, d]))


## An upright box at world `centre` sized `size`, its x along the local direction `facing`'s side.
static func _box(st: Acc, centre: Vector3, size: Vector3, cl: Color, facing: Vector2 = Vector2(0.0, 1.0)) -> void:
	var f := _wdir(facing).normalized()
	var r := Vector3(-f.z, 0.0, f.x)
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for k in 8:
		corners.append(centre + r * (h.x if k & 1 else -h.x) + Vector3.UP * (h.y if k & 2 else -h.y) + f * (h.z if k & 4 else -h.z))
	# Faces: -x, +x, -y, +y, -z, +z (corner bits: 1 x, 2 y, 4 z).
	var faces := [[0, 2, 6, 4, -r], [1, 5, 7, 3, r], [0, 4, 5, 1, Vector3.DOWN], [2, 3, 7, 6, Vector3.UP], [0, 1, 3, 2, -f], [4, 6, 7, 5, f]]
	for fc: Array in faces:
		var a: Vector3 = corners[fc[0]]
		var b: Vector3 = corners[fc[1]]
		var c: Vector3 = corners[fc[2]]
		var d: Vector3 = corners[fc[3]]
		st.quad(a, b, c, d, fc[4], Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0), cl)


# --- The pavilions ----------------------------------------------------------------------------

## A pavilion past the fence, left field (`side` -1) or right (+1): bleachers fanning round the
## fence, a concourse and facade behind, a zig-zag roof on columns, two light banks and the
## scoreboard on top.
static func _pavilion(st: Acc, seats: Acc, glare: Acc, coll: PackedVector3Array, side: int, near: bool) -> void:
	var a0 := Ballpark.PAV_A0
	var a1 := Ballpark.PAV_A1
	var n := 14 if near else 6
	var rows := Ballpark.PAV_ROWS
	var dep := Ballpark.PAV_DEPTH
	var rise := Ballpark.PAV_RISE
	var y0 := Ballpark.PAV_Y
	var y_last := y0 + (rows - 1) * rise
	var y_top := y_last + 3.4
	var seat_col := Color(PAVILION_SEAT.r, PAVILION_SEAT.g, PAVILION_SEAT.b, 0.62)
	var fronts: Array = []
	for j in n + 1:
		var deg := float(side) * lerpf(a0, a1, float(j) / n)
		var dir := Vector2(sin(deg_to_rad(deg)), cos(deg_to_rad(deg)))
		fronts.append([dir * (Ballpark.fence_r(deg) + Ballpark.PAV_GAP), dir])
	var d_end := rows * dep
	var d_back := d_end + 4.0
	var rc := {}
	for j in n:
		var s0: Array = fronts[j]
		var s1: Array = fronts[j + 1]
		var out0 := _wdir(s0[1])
		var outw := (out0 + _wdir(s1[1])).normalized()
		if near:
			for i in rows:
				var di := i * dep
				var yi := y0 + i * rise
				var ra := _rp(rc, fronts, j, di)
				if i > 0:
					seats.quad(_w(_at(s0, di), yi - rise), _w(_at(s1, di), yi - rise), _w(_at(s1, di), yi), _w(_at(s0, di), yi), -outw,
						Vector2(ra.x, i), Vector2(ra.y, i), Vector2(ra.y, i + 0.3), Vector2(ra.x, i + 0.3), seat_col)
				seats.quad(_w(_at(s0, di), yi), _w(_at(s1, di), yi), _w(_at(s1, di + dep), yi), _w(_at(s0, di + dep), yi), Vector3.UP,
					Vector2(ra.x, i + 0.3), Vector2(ra.y, i + 0.3), Vector2(ra.y, i + 1.0), Vector2(ra.x, i + 1.0), seat_col)
			_coll_quad(coll, _w(_at(s0, 0.0), y0), _w(_at(s1, 0.0), y0), _w(_at(s1, d_end), y_last), _w(_at(s0, d_end), y_last))
		else:
			var ra := _rp(rc, fronts, j, 0.0)
			seats.quad(_w(_at(s0, 0.0), y0), _w(_at(s1, 0.0), y0), _w(_at(s1, d_end), y_last), _w(_at(s0, d_end), y_last), Vector3.UP - outw,
				Vector2(ra.x, 0.0), Vector2(ra.y, 0.0), Vector2(ra.y, rows), Vector2(ra.x, rows), seat_col)
		var fa := _rp(rc, fronts, j, -0.25)
		st.quad(_w(_at(s0, -0.25), 0.0), _w(_at(s1, -0.25), 0.0), _w(_at(s1, -0.25), y0 + 1.0), _w(_at(s0, -0.25), y0 + 1.0), -outw,
			Vector2(fa.x, 0.0), Vector2(fa.y, 0.0), Vector2(fa.y, y0 + 1.0), Vector2(fa.x, y0 + 1.0), _kc(C_NAVY, K_PAINT))
		st.quad(_w(_at(s0, -0.25), y0 + 1.0), _w(_at(s1, -0.25), y0 + 1.0), _w(_at(s1, 0.0), y0 + 1.0), _w(_at(s0, 0.0), y0 + 1.0), Vector3.UP,
			Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.25), Vector2(0.0, 0.25), _kc(C_NAVY, K_PAINT))
		var ca := _rp(rc, fronts, j, d_back)
		st.quad(_w(_at(s0, d_end), y_last), _w(_at(s1, d_end), y_last), _w(_at(s1, d_back), y_last), _w(_at(s0, d_back), y_last), Vector3.UP,
			Vector2(ca.x, 0.0), Vector2(ca.y, 0.0), Vector2(ca.y, 4.0), Vector2(ca.x, 4.0), _kc(C_INNER, K_INNER))
		st.quad(_w(_at(s0, d_back), y_last), _w(_at(s1, d_back), y_last), _w(_at(s1, d_back), y_last + 2.6), _w(_at(s0, d_back), y_last + 2.6), -outw,
			Vector2(ca.x, 0.0), Vector2(ca.y, 0.0), Vector2(ca.y, 2.6), Vector2(ca.x, 2.6), _kc(Color(0.55, 0.5, 0.42), K_BAND))
		st.quad(_w(_at(s0, d_back), y_last + 2.6), _w(_at(s1, d_back), y_last + 2.6), _w(_at(s1, d_back), y_top), _w(_at(s0, d_back), y_top), -outw,
			Vector2(ca.x, 0.0), Vector2(ca.y, 0.0), Vector2(ca.y, 1.0), Vector2(ca.x, 1.0), _kc(C_INNER, K_INNER))
		var fo := _rp(rc, fronts, j, d_back + 0.5)
		st.quad(_w(_at(s0, d_back + 0.5), 0.0), _w(_at(s1, d_back + 0.5), 0.0), _w(_at(s1, d_back + 0.5), y_top), _w(_at(s0, d_back + 0.5), y_top), outw,
			Vector2(fo.x, 0.0), Vector2(fo.y, 0.0), Vector2(fo.y, y_top), Vector2(fo.x, y_top), _kc(C_CONCRETE, K_FACADE))
		st.quad(_w(_at(s0, d_back), y_top), _w(_at(s1, d_back), y_top), _w(_at(s1, d_back + 0.5), y_top), _w(_at(s0, d_back + 0.5), y_top), Vector3.UP,
			Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.5), Vector2(0.0, 0.5), _kc(C_CONCRETE, K_INNER))
		if near:
			_coll_quad(coll, _w(_at(s0, d_back + 0.5), 0.0), _w(_at(s1, d_back + 0.5), 0.0), _w(_at(s1, d_back + 0.5), y_top), _w(_at(s0, d_back + 0.5), y_top))
		# The roof: folded plates, a ridge and a valley per station, over the back two thirds,
		# cantilevered off the facade on a column at every other fold.
		var r_front := d_end * 0.35
		var ridge := 1.1 if j % 2 == 0 else -0.6
		var ridge1 := 1.1 if (j + 1) % 2 == 0 else -0.6
		var yb := y_top + 3.0
		var yf := y_top + 1.4
		var b0 := _w(_at(s0, d_back + 0.7), yb)
		var b1 := _w(_at(s1, d_back + 0.7), yb)
		var f0 := _w(_at(s0, r_front), yf + ridge)
		var f1 := _w(_at(s1, r_front), yf + ridge1)
		st.quad(b0, b1, f1, f0, Vector3.UP, Vector2(0.0, 0.0), Vector2(3.0, 0.0), Vector2(3.0, 12.0), Vector2(0.0, 12.0), _kc(C_ROOF, K_ROOF))
		var dn := Vector3.DOWN * 0.35
		st.quad(b0 + dn, b1 + dn, f1 + dn, f0 + dn, Vector3.DOWN, Vector2(0.0, 0.0), Vector2(3.0, 0.0), Vector2(3.0, 12.0), Vector2(0.0, 12.0), _kc(C_SOFFIT, K_STEEL))
		st.quad(f0, f1, f1 + dn, f0 + dn, -outw, Vector2(0.0, 0.0), Vector2(3.0, 0.0), Vector2(3.0, 0.35), Vector2(0.0, 0.35), _kc(C_CREAM, K_PAINT))
		if j % 2 == 0:
			var yr := y0 + (r_front / dep) * rise
			_box(st, (_w(_at(s0, r_front + 0.3), yr) + f0 + dn) * 0.5, Vector3(0.4, (yf + ridge - 0.35) - yr, 0.4), _kc(C_STEEL, K_STEEL), s0[1])
	# End walls.
	for e in 2:
		var s: Array = fronts[0] if e == 0 else fronts[n]
		var sec := PackedVector2Array([Vector2(-0.25, 0.0), Vector2(-0.25, y0 + 1.0), Vector2(0.0, y0 + 1.0)])
		for i in rows:
			sec.append(Vector2(i * dep, y0 + i * rise))
			sec.append(Vector2((i + 1) * dep, y0 + i * rise))
		sec.append(Vector2(d_back, y_last))
		sec.append(Vector2(d_back, y_top))
		sec.append(Vector2(d_back + 0.5, y_top))
		sec.append(Vector2(d_back + 0.5, 0.0))
		var sd: Vector2 = s[1]
		var tangent := Vector2(sd.y, -sd.x) * float(side) * (1.0 if e == 1 else -1.0)
		_section(st, s, sec, _wdir(tangent), _kc(C_CONCRETE, K_FACADE))
	# Two light banks on masts behind, and the scoreboard over the middle.
	var aim := _w(Vector2(0.0, 55.0), 0.0)
	for f: float in [0.22, 0.78]:
		var deg := float(side) * lerpf(a0, a1, f)
		var dir := Vector2(sin(deg_to_rad(deg)), cos(deg_to_rad(deg)))
		var foot := dir * (Ballpark.fence_r(deg) + Ballpark.PAV_GAP + d_back + 3.5)
		_bank(st, glare, _w(foot, 0.0), y_top + 22.0, aim, near)
	var degc := float(side) * (a0 + a1) * 0.5
	var dirc := Vector2(sin(deg_to_rad(degc)), cos(deg_to_rad(degc)))
	var board_at := dirc * (Ballpark.fence_r(degc) + Ballpark.PAV_GAP + d_back + 2.5)
	var w := Ballpark.BOARD_W.x if side < 0 else Ballpark.BOARD_W.y
	var h := Ballpark.BOARD_H.x if side < 0 else Ballpark.BOARD_H.y
	_scoreboard(st, board_at, dirc, y_top + 5.5, w, h, side < 0, near)


## The stretched hexagonal scoreboard, standing at local `at` facing home (`dir` points away from
## home), its bottom `y0` over the pad, on two legs.
static func _scoreboard(st: Acc, at: Vector2, dir: Vector2, y0: float, w: float, h: float, video: bool, near: bool) -> void:
	var face := -_wdir(dir).normalized()
	var right := Vector3(-face.z, 0.0, face.x)
	var base := _w(at, y0)
	var k := h * 0.32
	var hex := [Vector2(-w * 0.5 + k, 0.0), Vector2(w * 0.5 - k, 0.0), Vector2(w * 0.5, h * 0.5), Vector2(w * 0.5 - k, h), Vector2(-w * 0.5 + k, h), Vector2(-w * 0.5, h * 0.5)]
	var c := Vector2(0.0, h * 0.5)
	var frame := _kc(C_STEEL, K_STEEL)
	var screen := Color(1.0 if video else 0.0, 0.0, 0.0, float(K_SCREEN) / 16.0)
	var p := func(q: Vector2, depth: float) -> Vector3:
		return base + right * q.x + Vector3.UP * q.y - face * depth
	for i in 6:
		var a: Vector2 = hex[i]
		var b: Vector2 = hex[(i + 1) % 6]
		var ai := c + (a - c) * 0.9
		var bi := c + (b - c) * 0.9
		# The frame's face, the screen inset behind it, the back, the rim.
		st.quad(p.call(a, 0.0), p.call(b, 0.0), p.call(bi, 0.0), p.call(ai, 0.0), face, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, frame)
		var su := func(q: Vector2) -> Vector2:
			return Vector2(1.0 - (q.x + w * 0.45) / (w * 0.9), (q.y - h * 0.05) / (h * 0.9))
		st.tri(p.call(c, 0.15), p.call(ai, 0.15), p.call(bi, 0.15), face, su.call(c), su.call(ai), su.call(bi), screen)
		st.tri(p.call(c, 1.2), p.call(a, 1.2), p.call(b, 1.2), -face, Vector2.ZERO, Vector2.ONE, Vector2.ONE, frame)
		var m := (a + b) * 0.5 - c
		var out := right * m.x + Vector3.UP * m.y
		st.quad(p.call(a, 0.0), p.call(b, 0.0), p.call(b, 1.2), p.call(a, 1.2), out, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, frame)
	for lx: float in [-w * 0.28, w * 0.28]:
		var foot := base + right * lx - face * 0.6
		_box(st, Vector3(foot.x, Ballpark.PAD_Y + y0 * 0.5, foot.z), Vector3(0.9, y0, 0.9), frame, dir)


## A light bank: a lattice mast from `foot` (world) to `top` metres over the pad, a frame of
## lenses aimed at `aim` (world), and a glare sprite per lens.
static func _bank(st: Acc, glare: Acc, foot: Vector3, top: float, aim: Vector3, near: bool) -> void:
	var head := Vector3(foot.x, Ballpark.PAD_Y + top, foot.z)
	var mast_h := head.y - foot.y
	var to := (aim - head)
	var flat := Vector3(to.x, 0.0, to.z).normalized()
	_box(st, foot + Vector3.UP * (mast_h * 0.5), Vector3(0.8, mast_h, 0.8), _kc(C_STEEL, K_STEEL), Vector2(flat.x, flat.z))
	var face := to.normalized()
	var right := Vector3(-flat.z, 0.0, flat.x)
	var up := right.cross(face).normalized()
	if up.y < 0.0:
		up = -up
	var bw := BANK_COLS * LENS * 1.25
	var bh := BANK_ROWS * LENS * 1.3
	var ctr := head + Vector3.UP * (bh * 0.5)
	var corner := func(x: float, y: float, z: float) -> Vector3:
		return ctr + right * x + up * y + face * z
	st.quad(corner.call(-bw * 0.5, -bh * 0.5, -0.1), corner.call(bw * 0.5, -bh * 0.5, -0.1), corner.call(bw * 0.5, bh * 0.5, -0.1), corner.call(-bw * 0.5, bh * 0.5, -0.1), -face,
		Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(C_STEEL, K_STEEL))
	st.quad(corner.call(-bw * 0.5, -bh * 0.5, 0.0), corner.call(bw * 0.5, -bh * 0.5, 0.0), corner.call(bw * 0.5, bh * 0.5, 0.0), corner.call(-bw * 0.5, bh * 0.5, 0.0), face,
		Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(C_STEEL, K_STEEL))
	for r in BANK_ROWS:
		for cidx in BANK_COLS:
			var x := (float(cidx) - (BANK_COLS - 1) * 0.5) * LENS * 1.25
			var y := (float(r) - (BANK_ROWS - 1) * 0.5) * LENS * 1.3
			var h2 := LENS * 0.45
			st.quad(corner.call(x - h2, y - h2, 0.12), corner.call(x + h2, y - h2, 0.12), corner.call(x + h2, y + h2, 0.12), corner.call(x - h2, y + h2, 0.12), face,
				Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(Color.WHITE, K_LENS))
			_glare(glare, corner.call(x, y, 0.4), face, 2.6 if near else 3.4)


## One glare sprite for aircraft_lights.gdshader: four corners at the centre, UV the corner, UV2
## (size, code 140: a field light, aimed along its normal).
static func _glare(glare: Acc, at: Vector3, face: Vector3, size: float) -> void:
	var cl := Color(1.0, 0.96, 0.88, 1.0)
	for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
		glare.v.append(at)
		glare.n.append(face)
		glare.uv.append(c)
		glare.uv2.append(Vector2(size, 140.0))
		glare.col.append(cl)
	glare.tris += 2


static func _glare_mesh(glare: Acc) -> ArrayMesh:
	var m := ArrayMesh.new()
	if glare.v.is_empty():
		return m
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = glare.v
	arrays[Mesh.ARRAY_NORMAL] = glare.n
	arrays[Mesh.ARRAY_TEX_UV] = glare.uv
	arrays[Mesh.ARRAY_TEX_UV2] = glare.uv2
	arrays[Mesh.ARRAY_COLOR] = glare.col
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, material("glare"))
	# The sprites grow in the vertex shader: give the mesh room for them.
	var c := _w(Vector2(0.0, 40.0), 0.0)
	m.custom_aabb = AABB(c - Vector3(260.0, 40.0, 260.0), Vector3(520.0, 160.0, 520.0))
	return m


## The top deck's roof: folded plates round the bowl, its light banks on masts along the back.
static func _roof_banks(st: Acc, glare: Acc, near: bool) -> void:
	var t: Dictionary = Ballpark.TIERS[Ballpark.TIERS.size() - 1]
	var d0: float = t.d
	var rows: int = t.rows
	var dep: float = t.depth
	var y_last: float = float(t.y) + (rows - 1) * float(t.rise)
	var d_back := d0 + rows * dep + Ballpark.CONCOURSE
	var y_top := y_last + 3.6
	var sts := path(float(t.end), 4.5 if near else 9.0, 18 if near else 8)
	var r_front := d0 + rows * dep * 0.45
	for j in sts.size() - 1:
		var s0: Array = sts[j]
		var s1: Array = sts[j + 1]
		var outw := (_wdir(s0[1]) + _wdir(s1[1])).normalized()
		var ridge := 1.2 if j % 2 == 0 else -0.5
		var ridge1 := 1.2 if (j + 1) % 2 == 0 else -0.5
		var b0 := _w(_at(s0, d_back + 0.7), y_top + 3.2)
		var b1 := _w(_at(s1, d_back + 0.7), y_top + 3.2)
		var f0 := _w(_at(s0, r_front), y_top + 1.8 + ridge)
		var f1 := _w(_at(s1, r_front), y_top + 1.8 + ridge1)
		st.quad(b0, b1, f1, f0, Vector3.UP, Vector2(0.0, 0.0), Vector2(3.0, 0.0), Vector2(3.0, 12.0), Vector2(0.0, 12.0), _kc(C_ROOF, K_ROOF))
		var dn := Vector3.DOWN * 0.35
		st.quad(b0 + dn, b1 + dn, f1 + dn, f0 + dn, Vector3.DOWN, Vector2(0.0, 0.0), Vector2(3.0, 0.0), Vector2(3.0, 12.0), Vector2(0.0, 12.0), _kc(C_SOFFIT, K_STEEL))
		st.quad(f0, f1, f1 + dn, f0 + dn, -outw, Vector2(0.0, 0.0), Vector2(3.0, 0.0), Vector2(3.0, 0.35), Vector2(0.0, 0.35), _kc(C_CREAM, K_PAINT))
		st.quad(b0, b1, _w(_at(s1, d_back + 0.5), y_top), _w(_at(s0, d_back + 0.5), y_top), outw, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(C_CONCRETE, K_FACADE))
	# The light banks along the roof's back: six round the bowl.
	var aim := _w(Vector2(0.0, 48.0), 0.0)
	var n := sts.size()
	for f: float in [0.07, 0.24, 0.41, 0.59, 0.76, 0.93]:
		var s: Array = sts[clampi(int(f * (n - 1)), 0, n - 1)]
		var foot := _w(_at(s, d_back - 0.5), y_top + 3.0)
		_bank(st, glare, foot, y_top + 3.0 + 13.0, aim, near)


# --- The field's furniture ---------------------------------------------------------------------

## The outfield wall from foul pole to foul pole, its corner returns to the stands, the foul poles.
static func _wall(st: Acc, coll: PackedVector3Array, near: bool) -> void:
	var n := 60 if near else 20
	var hgt := Ballpark.FENCE_H
	var prev := Vector2.ZERO
	var prev_out := Vector2.ZERO
	var run := 0.0
	for j in n + 1:
		var deg := lerpf(-45.0, 45.0, float(j) / n)
		var dir := Vector2(sin(deg_to_rad(deg)), cos(deg_to_rad(deg)))
		var p := dir * Ballpark.fence_r(deg)
		var po := dir * (Ballpark.fence_r(deg) + 0.45)
		if j > 0:
			var r1 := run + p.distance_to(prev)
			var face := -_wdir(dir)
			st.quad(_w(prev, 0.0), _w(p, 0.0), _w(p, hgt), _w(prev, hgt), face, Vector2(run, 0.0), Vector2(r1, 0.0), Vector2(r1, hgt), Vector2(run, hgt), _kc(C_PAD, K_PAD))
			st.quad(_w(prev, hgt), _w(p, hgt), _w(po, hgt), _w(prev_out, hgt), Vector3.UP, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(C_YELLOW, K_PAINT))
			st.quad(_w(prev_out, 0.0), _w(po, 0.0), _w(po, hgt), _w(prev_out, hgt), -face, Vector2(run, 0.0), Vector2(r1, 0.0), Vector2(r1, hgt), Vector2(run, hgt), _kc(C_NAVY, K_PAINT))
			_coll_quad(coll, _w(prev, 0.0), _w(p, 0.0), _w(p, hgt), _w(prev, hgt))
			run = r1
		prev = p
		prev_out = po
	# Corner returns along the stands' line, and the foul poles with their screens.
	for side: int in [-1, 1]:
		var line := DIRL if side < 0 else DIRR
		var nrm := NL if side < 0 else NR
		var at := line * Ballpark.FENCE_LINE
		var a := at
		var b := at + nrm * Ballpark.FRONT
		st.quad(_w(a, 0.0), _w(b, 0.0), _w(b, hgt), _w(a, hgt), -_wdir(line), Vector2(0.0, 0.0), Vector2(Ballpark.FRONT, 0.0), Vector2(Ballpark.FRONT, hgt), Vector2(0.0, hgt), _kc(C_PAD, K_PAD))
		_coll_quad(coll, _w(a, 0.0), _w(b, 0.0), _w(b, hgt), _w(a, hgt))
		var pole := at + line * 0.6
		_box(st, _w(pole, 14.0), Vector3(0.5, 28.0, 0.5), _kc(C_YELLOW, K_POLE), line)
		var fin := pole + Vector2(-nrm.x, -nrm.y) * 0.55
		_box(st, _w(fin, 15.0), Vector3(0.9, 22.0, 0.06), _kc(C_YELLOW, K_POLE), Vector2(-line.y, line.x))


## Dugouts down the lines, bases and home plate, the mound, the backstop net, the batter's eye.
static func _details(st: Acc, net: Acc, near: bool) -> void:
	for side: int in [-1, 1]:
		var line := DIRL if side < 0 else DIRR
		var nrm := NL if side < 0 else NR
		var c := line * 36.0 + nrm * (Ballpark.FRONT - 1.6)
		var along := line
		_box(st, _w(c, 1.32), Vector3(26.0, 0.16, 3.2), _kc(C_NAVY, K_PAINT), Vector2(-along.y, along.x))
		if near:
			# The opening (dark), the lip and the step below it.
			var f := c - nrm * 1.6
			_box(st, _w(f, 0.68), Vector3(26.0, 0.96, 0.05), _kc(C_DARK, K_DARK), Vector2(-along.y, along.x))
			_box(st, _w(f + nrm * 1.6, 0.6), Vector3(26.0, 1.2, 3.2), _kc(C_DARK, K_DARK), Vector2(-along.y, along.x))
			for e: int in [-1, 1]:
				_box(st, _w(c + along * 13.0 * e, 0.7), Vector3(0.2, 1.4, 3.2), _kc(C_NAVY, K_PAINT), Vector2(-along.y, along.x))
	if near:
		# Bases (canvas bags) and the plate.
		var b := Ballpark.BASE * 0.70710678
		for q: Vector2 in [Vector2(b, b), Vector2(0.0, b * 2.0), Vector2(-b, b)]:
			_box(st, _w(q, 0.22), Vector3(0.38, 0.1, 0.38), _kc(Color.WHITE, K_PAINT), Vector2(0.70710678, 0.70710678))
		_box(st, _w(Vector2(0.0, 0.1), 0.18), Vector3(0.43, 0.03, 0.43), _kc(Color.WHITE, K_PAINT))
		# The backstop net: behind home and up the lines to the dugouts' ends.
		var sts := path(22.0, 4.0, 14)
		for j in sts.size() - 1:
			var a := _at(sts[j], Ballpark.FRONT - 0.3)
			var e := _at(sts[j + 1], Ballpark.FRONT - 0.3)
			var y0: float = float(Ballpark.TIERS[0].y) + 1.0
			net.quad(_w(a, y0), _w(e, y0), _w(e, 9.0), _w(a, 9.0), -_wdir(sts[j][1]), Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, Color.WHITE)
	# The batter's eye: a dark wall past centre field, between the pavilions.
	var n := 10 if near else 4
	for j in n:
		var d0 := lerpf(-14.0, 14.0, float(j) / n)
		var d1 := lerpf(-14.0, 14.0, float(j + 1) / n)
		var p0 := Vector2(sin(deg_to_rad(d0)), cos(deg_to_rad(d0))) * (Ballpark.fence_r(d0) + 7.0)
		var p1 := Vector2(sin(deg_to_rad(d1)), cos(deg_to_rad(d1))) * (Ballpark.fence_r(d1) + 7.0)
		var face := -_wdir((p0 + p1).normalized())
		st.quad(_w(p0, 0.0), _w(p1, 0.0), _w(p1, 9.0), _w(p0, 9.0), face, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(Color(0.04, 0.07, 0.05), K_PAINT))
		st.quad(_w(p0, 0.0), _w(p1, 0.0), _w(p1, 9.0), _w(p0, 9.0), -face, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(C_CONCRETE, K_FACADE))


## Bridges from the upper terrace's edge into the top deck's facade at the terrace's level.
static func _bridges(st: Acc, coll: PackedVector3Array, near: bool) -> void:
	var t: Dictionary = Ballpark.TIERS[Ballpark.TIERS.size() - 1]
	var d_back: float = float(t.d) + int(t.rows) * float(t.depth) + Ballpark.CONCOURSE + 0.5
	var y := Ballpark.TERRACE_RISE
	for phi_deg: float in [248.0, 270.0, 292.0]:
		var dir := Vector2(cos(deg_to_rad(phi_deg)), sin(deg_to_rad(phi_deg)))
		# Out to where the terrace's slope has topped out.
		var r1 := d_back
		while r1 < 260.0 and Ballpark.terrace_t(dir * r1) < 0.999:
			r1 += 2.0
		r1 += 4.0
		var a := dir * d_back
		var b := dir * r1
		var side := Vector2(-dir.y, dir.x) * 3.0
		var top := [_w(a - side, y), _w(b - side, y), _w(b + side, y), _w(a + side, y)]
		st.quad(top[0], top[1], top[2], top[3], Vector3.UP, Vector2.ZERO, Vector2(r1 - d_back, 0.0), Vector2(r1 - d_back, 6.0), Vector2(0.0, 6.0), _kc(C_INNER, K_INNER))
		var dn := Vector3.DOWN * 1.2
		st.quad(top[0] + dn, top[1] + dn, top[2] + dn, top[3] + dn, Vector3.DOWN, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(C_INNER, K_INNER))
		if near:
			_coll_quad(coll, top[0], top[1], top[2], top[3])
		for s: int in [-1, 1]:
			var o := side * float(s)
			var o2 := o * 1.07
			var wa := _w(a + o, y - 1.2)
			var wb := _w(b + o, y - 1.2)
			var face := Vector3(o.x, 0.0, o.y).normalized()
			# The deck's edge and its parapet.
			var rs := Ballpark.RIGHT * o.x + Ballpark.FWD * o.y
			face = Vector3(rs.x, 0.0, rs.y).normalized()
			st.quad(wa, wb, _w(b + o, y + 1.1), _w(a + o, y + 1.1), face, Vector2.ZERO, Vector2(r1 - d_back, 0.0), Vector2(r1 - d_back, 2.3), Vector2(0.0, 2.3), _kc(C_CREAM, K_PAINT))
			st.quad(_w(a + o, y + 1.1), _w(b + o, y + 1.1), _w(b + o2, y + 1.1), _w(a + o2, y + 1.1), Vector3.UP, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(C_CREAM, K_PAINT))
			st.quad(_w(a + o2, y), _w(b + o2, y), _w(b + o2, y + 1.1), _w(a + o2, y + 1.1), -face, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(C_CREAM, K_PAINT))
		# Piers down to the plaza, and the doorway in the facade.
		var r := d_back + 12.0
		while r < r1 - 6.0:
			var pc := dir * r
			_box(st, _w(pc, (y - 1.2) * 0.5), Vector3(1.4, y - 1.2, 1.4), _kc(C_INNER, K_INNER), dir)
			r += 22.0
		var door := a + dir * 0.08
		st.quad(_w(door - side * 0.8, y), _w(door + side * 0.8, y), _w(door + side * 0.8, y + 3.2), _w(door - side * 0.8, y + 3.2), _wdir(dir),
			Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(C_DARK, K_BAND))


# --- The field -----------------------------------------------------------------------------------

## The field's reach from home at angle `deg` (off the centre line): past the fence to the
## pavilions in fair ground, out to the stands' wall in foul ground.
static func field_reach(deg: float) -> float:
	var a := absf(deg)
	if a <= 45.0:
		return Ballpark.fence_r(deg) + Ballpark.PAV_GAP + 1.0
	var delta := a - 45.0
	if delta >= 90.0:
		return Ballpark.FRONT + 0.6
	return minf((Ballpark.FRONT + 0.6) / maxf(sin(deg_to_rad(delta)), 0.001), Ballpark.FENCE_LINE + 1.0)


## A polar grid round home out to field_reach(), and the mound.
static func _field(near: bool) -> ArrayMesh:
	var acc := Acc.new()
	var steps := 240 if near else 72
	var rings := 22 if near else 7
	var lift := 0.16
	var cl := Color.WHITE
	for j in steps:
		var d0 := lerpf(-180.0, 180.0, float(j) / steps)
		var d1 := lerpf(-180.0, 180.0, float(j + 1) / steps)
		var r0 := field_reach(d0)
		var r1 := field_reach(d1)
		var u0 := Vector2(sin(deg_to_rad(d0)), cos(deg_to_rad(d0)))
		var u1 := Vector2(sin(deg_to_rad(d1)), cos(deg_to_rad(d1)))
		for k in rings:
			var fa := float(k) / rings
			var fb := float(k + 1) / rings
			# Rings closer together near home, where the infield's detail is.
			fa = fa * fa * 0.5 + fa * 0.5
			fb = fb * fb * 0.5 + fb * 0.5
			var a := u0 * r0 * fa
			var b := u1 * r1 * fa
			var c := u1 * r1 * fb
			var d := u0 * r0 * fb
			acc.quad(_w(a, lift), _w(b, lift), _w(c, lift), _w(d, lift), Vector3.UP, a, b, c, d, cl)
	# The mound: a low cone 10 inches high round the rubber.
	var mc := Vector2(0.0, Ballpark.RUBBER - 0.15)
	var segs := 24 if near else 10
	for j in segs:
		var a0 := TAU * j / segs
		var a1 := TAU * (j + 1) / segs
		var pa := mc + Vector2(cos(a0), sin(a0)) * Ballpark.MOUND_R
		var pb := mc + Vector2(cos(a1), sin(a1)) * Ballpark.MOUND_R
		acc.tri(_w(mc, lift + 0.25), _w(pa, lift), _w(pb, lift), Vector3.UP, mc, pa, pb, cl)
	return acc.mesh(material("field"), true)


# --- The ground ----------------------------------------------------------------------------------

## The site's ground: a grid over the outline following the levels, its kind worked out in
## ballpark_lot.gdshader. Cells wholly inside the field are left out (the field lies over it).
static func _lot(near: bool) -> ArrayMesh:
	var acc := Acc.new()
	var step := 8.0 if near else 16.0
	var lift := 0.1 if near else 0.3
	var nu := int(ceil(Ballpark.SITE_U * 2.0 / step))
	var nv := int(ceil((Ballpark.SITE_V1 - Ballpark.SITE_V0) / step))
	var hv := func(q: Vector2) -> Vector3:
		return _w(q, Ballpark.level(q) - Ballpark.PAD_Y + lift)
	var nrm := func(q: Vector2) -> Vector3:
		var gx := Ballpark.level(q + Vector2(1.0, 0.0)) - Ballpark.level(q - Vector2(1.0, 0.0))
		var gz := Ballpark.level(q + Vector2(0.0, 1.0)) - Ballpark.level(q - Vector2(0.0, 1.0))
		var w := _wdir(Vector2(-gx * 0.5, -gz * 0.5))
		return (Vector3.UP + w).normalized()
	var colr := func(q: Vector2) -> Color:
		return Color(clampf(-Ballpark.site_sd(q) / 16.0, 0.0, 1.0), 0.0, 0.0, 1.0)
	for j in nv:
		for i in nu:
			var q0 := Vector2(-Ballpark.SITE_U + i * step, Ballpark.SITE_V0 + j * step)
			var corners := [q0, q0 + Vector2(step, 0.0), q0 + Vector2(step, step), q0 + Vector2(0.0, step)]
			var any_in := false
			var all_field := true
			for q: Vector2 in corners:
				if Ballpark.site_sd(q) < 0.0:
					any_in = true
				var deg := rad_to_deg(atan2(q.x, q.y))
				if q.length() > field_reach(deg) - 2.0:
					all_field = false
			if not any_in or all_field:
				continue
			var qs: Array[Vector2] = []
			for q: Vector2 in corners:
				# Pull a corner past the outline back onto it, so the edge follows the outline.
				var e := Ballpark.site_sd(q)
				if e > 0.0:
					var g := Vector2(Ballpark.site_sd(q + Vector2(0.5, 0.0)) - Ballpark.site_sd(q - Vector2(0.5, 0.0)),
						Ballpark.site_sd(q + Vector2(0.0, 0.5)) - Ballpark.site_sd(q - Vector2(0.0, 0.5)))
					if g.length_squared() > 1e-6:
						q = q - g.normalized() * e
				qs.append(q)
			acc.quad_n(hv.call(qs[0]), hv.call(qs[1]), hv.call(qs[2]), hv.call(qs[3]), nrm.call(qs[0]), nrm.call(qs[1]), nrm.call(qs[2]), nrm.call(qs[3]),
				qs[0], qs[1], qs[2], qs[3], colr.call(qs[0]), colr.call(qs[1]), colr.call(qs[2]), colr.call(qs[3]))
	stats["lot_" + ("near" if near else "far")] = acc.tris
	return acc.mesh(material("lot"))


# --- Cars, poles, palms (near only) ---------------------------------------------------------------

## The parked cars, in the stalls Ballpark.stall_car() fills (the shader paints the same ones).
static func _cars(batch: MultiMeshBatch) -> void:
	var count := 0
	var u0 := -Ballpark.SITE_U
	var v := Ballpark.SITE_V0
	var mi := 0
	while v < Ballpark.SITE_V1:
		for side in 2:
			var vc := v + Ballpark.LOT_STALL_D * (0.5 + side)
			var bi := 0
			while u0 + bi * Ballpark.LOT_BLOCK_U < Ballpark.SITE_U:
				for k in Ballpark.LOT_BLOCK_STALLS_N:
					var u := u0 + bi * Ballpark.LOT_BLOCK_U + (k + 0.5) * Ballpark.LOT_STALL_W
					var q := Vector2(u, vc)
					if q.length() > CAR_REACH:
						continue
					var car := Ballpark.stall_car(q)
					if car < 0:
						continue
					var kind := car % ArenaGrounds.CAR_KINDS
					var mesh := ArenaGrounds.car_mesh(kind)
					if mesh == null:
						continue
					var paint: Color = ArenaGrounds.CAR_PAINTS[(car / 7) % ArenaGrounds.CAR_PAINTS.size()]
					var nose := Ballpark.FWD if side == 0 else -Ballpark.FWD
					var yaw := atan2(-nose.x, -nose.y) + (float(car % 5) - 2.0) * 0.012
					var tile := Vector2i(floori(u / CAR_TILE), floori(vc / CAR_TILE))
					var key := "bp_car_%d_%d_%d" % [kind, tile.x, tile.y]
					batch.add(key, mesh, Transform3D(Basis(Vector3.UP, yaw), _w(q, Ballpark.level(q) - Ballpark.PAD_Y + 0.1)), paint)
					batch.set_draw_distance(key, CAR_DRAW)
					count += 1
				bi += 1
		v += Ballpark.LOT_MODULE
		mi += 1
	stats["cars"] = count


## The lot's light poles where Ballpark.pole_at() puts them.
static func _poles(batch: MultiMeshBatch) -> void:
	var mesh := pole_mesh()
	var count := 0
	for p: Vector2 in Ballpark.poles():
		batch.add("bp_pole", mesh, Transform3D(Basis(Vector3.UP, atan2(-Ballpark.RIGHT.x, -Ballpark.RIGHT.y)), _w(p, Ballpark.level(p) - Ballpark.PAD_Y + 0.1)))
		count += 1
	# set_shadow_reach, not set_shadow_distance: the pole is a code mesh with no lighter twin, and
	# set_shadow_distance only reaches a twin (on this mesh it did nothing).
	batch.set_shadow_reach("bp_pole", 120.0)
	stats["poles"] = count


## A lot pole: a tapered mast, a cross arm and four lamp heads with their lenses facing down.
static func pole_mesh() -> Mesh:
	if _pole_mesh != null:
		return _pole_mesh
	var acc := Acc.new()
	var steel := _kc(Color(0.45, 0.46, 0.47), K_STEEL)
	var h := 15.0
	var segs := 8
	for j in segs:
		var a0 := TAU * j / segs
		var a1 := TAU * (j + 1) / segs
		var b0 := Vector3(cos(a0), 0.0, sin(a0))
		var b1 := Vector3(cos(a1), 0.0, sin(a1))
		acc.quad(b0 * 0.22, b1 * 0.22, b1 * 0.12 + Vector3.UP * h, b0 * 0.12 + Vector3.UP * h, (b0 + b1) * 0.5, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, steel)
	var arm := Vector3(3.2, 0.18, 0.18)
	_box_local(acc, Vector3(0.0, h, 0.0), arm, steel)
	for x: float in [-1.4, -0.5, 0.5, 1.4]:
		_box_local(acc, Vector3(x, h - 0.25, 0.0), Vector3(0.7, 0.3, 0.5), steel)
		acc.quad(Vector3(x - 0.3, h - 0.41, -0.2), Vector3(x + 0.3, h - 0.41, -0.2), Vector3(x + 0.3, h - 0.41, 0.2), Vector3(x - 0.3, h - 0.41, 0.2), Vector3.DOWN,
			Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, _kc(Color.WHITE, K_LENS))
	_pole_mesh = acc.mesh(material("struct"))
	return _pole_mesh


static func _box_local(acc: Acc, c: Vector3, size: Vector3, cl: Color) -> void:
	var h := size * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3:
		return c + Vector3(x * h.x, y * h.y, z * h.z)
	acc.quad(p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), Vector3.BACK, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, cl)
	acc.quad(p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(-1, 1, -1), Vector3.FORWARD, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, cl)
	acc.quad(p.call(1, -1, -1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(1, 1, -1), Vector3.RIGHT, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, cl)
	acc.quad(p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1), Vector3.LEFT, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, cl)
	acc.quad(p.call(-1, 1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(-1, 1, 1), Vector3.UP, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, cl)
	acc.quad(p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1), Vector3.DOWN, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ZERO, cl)


## Palms: a row along the planted slope between the lot levels, round the plaza's edge, and down
## the lot's planted medians (Ballpark.palm_spots()).
static func _palms(batch: MultiMeshBatch) -> void:
	var count := 0
	for spot: Vector3 in Ballpark.palm_spots():
		var q := Vector2(spot.x, spot.y)
		var v := int(spot.z) % PropFactory.PALM_VARIANTS
		var s := 0.85 + 0.3 * Ballpark.ihash01(int(q.x * 10.0), int(q.y * 10.0))
		batch.add("palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, spot.z * 1.7).scaled(Vector3(s, s, s)), _w(q, Ballpark.level(q) - Ballpark.PAD_Y)))
		count += 1
	stats["palms"] = count
