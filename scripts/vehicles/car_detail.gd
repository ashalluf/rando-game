class_name CarDetail
extends RefCounted
## The close-up detail of a car (2026-10-30, fleet "car-detail": "at 2-5 m the everyday bodies
## still read as clean CG models"). Everything here costs nothing past the near LOD:
##
## * Number plates front and rear and the maker's badges - an emblem on the boot and the grille,
##   the model's name in chrome capitals on the boot - as REAL raised geometry (SignFont strokes
##   swept into ribbons standing a millimetre or two proud), ONE small mesh per car on ONE shared
##   material pair (`car_detail.gdshader`; the pair is the rear plate lamp off / on). The plate
##   text is the car's own (a hash of its look), in an invented format (`plate_text()`), on an
##   invented county's plate. Drawn only inside the body's near range (Vehicle.body_far_distance),
##   shadowless: past it the far twin, untouched, is all there is.
## * Raised lettering moulded into every tyre's sidewall (invented makers, the size worked out
##   from the wheel's own radius and width) - geometry in the shared near wheel mesh
##   (`tyre_letters()`, called by PropFactory.car_wheel()), so it costs nothing per car.
## * Road grime low on the body and sprayed round the wheel arches, dust on the tail, mud on the
##   work trucks and light clear-coat scratches on the flanks: uniforms on the car's OWN paint
##   material (Vehicle._paint_material() already makes one per car, so no material is added),
##   drawn by car_paint.gdshaderinc's grime block in the body mesh's own space.
## * Brake dust and dusty sidewalls on the wheels: PropFactory.wheel_material()'s `dust` level,
##   one of three shared copies per wheel kit (21 at most, never one per car).
## * A dusty windscreen outside the wipers' sweep: car_glass.gdshader's `screen_dust` on the
##   body type's shared cabin glass.
##
## Every roll is a hash of the car's look (never an rng): nothing a seed builds moves.
## CAR_DETAIL=0 in the environment turns all of it off (the A/B).

static var enabled: bool = OS.get_environment("CAR_DETAIL") != "0"

const DETAIL_SHADER := preload("res://shaders/car_detail.gdshader")

## A US-size plate (12 x 6 in), its thickness and how far it stands off the bumper.
const PLATE_W := 0.305
const PLATE_H := 0.152
const PLATE_T := 0.0016
const PLATE_STANDOFF := 0.006
## The plate's embossed characters: cap height, pen, how proud. The banner and tag line above
## and below them in the county's colours.
const PLATE_CAP := 0.062
const PLATE_PEN := 0.0075
const PLATE_LIFT := 0.0016
const PLATE_TEXT_W := 0.262
## The plate: invented county and tag line (never a real state's).
const PLATE_BANNER := "RANDO COUNTY"
const PLATE_FOOT := "PACIFIC BASIN"
## The registration tag's colours (the year's).
const TAG_COLORS := [Color(0.95, 0.78, 0.10), Color(0.18, 0.42, 0.85), Color(0.85, 0.25, 0.30), Color(0.25, 0.70, 0.40)]
## Characters a plate draws from (no I, O or Q: they read as digits).
const PLATE_LETTERS := "ABCDEFGHJKLMNPRSTUVWXYZ"

## Vertex alpha (x 8) per kind of surface, read by car_detail.gdshader.
const K_SHEET := 0   ## plate sheeting
const K_INK := 1     ## the plate's embossed paint
const K_CHROME := 2  ## badges, bolts
const K_PLASTIC := 3 ## black plastic (the badge's backing, the plate's tag recess)
const K_TAG := 4     ## the registration sticker
const K_RED := 5     ## the banner's red
const K_BLUE := 6    ## the tag line's blue

## The maker per body type (CarDealers.BRANDS' invented brands: the dealers sell these very
## cars) and the model's name on the boot. Every name invented.
const MAKES := {
	Vehicle.BodyType.SEDAN: [1, "VELLANO"],
	Vehicle.BodyType.TAXI: [1, "VELLANO"],
	Vehicle.BodyType.CROSSOVER: [3, "TALLIX"],
	Vehicle.BodyType.PICKUP: [2, "HAULDER"],
	Vehicle.BodyType.VAN: [5, "CARGOLINE"],
	Vehicle.BodyType.DELIVERY_VAN: [5, "CARGOLINE"],
	Vehicle.BodyType.HATCHBACK: [3, "ZIPPA"],
	Vehicle.BodyType.SUV: [2, "MONTAVEX"],
	Vehicle.BodyType.MINIVAN: [4, "FAMILIO"],
	Vehicle.BodyType.BEATER: [0, "ESTRAVA"],
	Vehicle.BodyType.LOWRIDER_HARDTOP: [0, "GRANDEVA"],
	Vehicle.BodyType.LOWRIDER_COUPE: [0, "MONTERRA"],
	Vehicle.BodyType.EV_HATCH: [5, "VOLTINA"],
	Vehicle.BodyType.LUX_SEDAN: [1, "QUENTIS 9"],
	Vehicle.BodyType.COMPACT_SUV: [2, "RANGLO"],
	Vehicle.BodyType.WORK_TRUCK: [2, "HAULDER WT"],
	Vehicle.BodyType.COUPE: [0, "STRADA"],
}
## Where the plates go, per body type: [rear height, rear x, front height] in metres over the
## road (the generators' plate recesses, tools/make_road_cars.py / make_more_cars.py; the van's
## is on its left-hand rear door). The ray search (`_spots()`) settles the depth and the tilt
## and moves the height a little to the flattest spot near it.
const PLATE_AT := {
	Vehicle.BodyType.SEDAN: [0.575, 0.0, 0.40],
	Vehicle.BodyType.TAXI: [0.575, 0.0, 0.40],
	Vehicle.BodyType.CROSSOVER: [0.86, 0.0, 0.42],
	Vehicle.BodyType.PICKUP: [0.87, 0.0, 0.50],
	Vehicle.BodyType.VAN: [0.875, -0.37, 0.42],
	Vehicle.BodyType.DELIVERY_VAN: [0.875, -0.37, 0.42],
	Vehicle.BodyType.HATCHBACK: [0.755, 0.0, 0.36],
	Vehicle.BodyType.SUV: [1.14, 0.0, 0.50],
	Vehicle.BodyType.MINIVAN: [0.925, 0.0, 0.40],
	Vehicle.BodyType.BEATER: [0.71, 0.0, 0.36],
	Vehicle.BodyType.LOWRIDER_HARDTOP: [0.53, 0.0, 0.40],
	Vehicle.BodyType.LOWRIDER_COUPE: [0.53, 0.0, 0.40],
	Vehicle.BodyType.EV_HATCH: [0.755, 0.0, 0.36],
	Vehicle.BodyType.LUX_SEDAN: [0.575, 0.0, 0.40],
	Vehicle.BodyType.COMPACT_SUV: [0.66, 0.0, 0.45],
	Vehicle.BodyType.WORK_TRUCK: [0.87, 0.0, 0.50],
	Vehicle.BodyType.COUPE: [0.567, 0.0, 0.38],
}
## Tyre makers and lines moulded into the sidewall (invented).
const TYRE_MAKERS := ["VORANTA", "TERRAVAL", "MARENZO", "QUILLAN"]
const TYRE_LINES := ["TOURING A/S", "SPORT HP", "ALL TERRAIN", "ECO TOUR", "CITY GRIP"]

## Grime levels over the fleet (a hash of the car's look): clean, light, dirty, filthy.
const GRIME_LEVELS := [0.0, 0.32, 0.62, 0.95]
const GRIME_ODDS := [35, 75, 95, 100]
## Body types that work for a living: more grime and, half the time, mud.
const WORK := [Vehicle.BodyType.PICKUP, Vehicle.BodyType.WORK_TRUCK, Vehicle.BodyType.VAN, Vehicle.BodyType.DELIVERY_VAN,
		Vehicle.BodyType.BOX_TRUCK, Vehicle.BodyType.GARBAGE_TRUCK, Vehicle.BodyType.TOW_TRUCK,
		Vehicle.BodyType.STREET_SWEEPER]

## Per body type: the measured spots (car space), {} when the body has no plates.
static var _spot_cache: Dictionary = {}
## Per body type: the badges' mesh arrays (car space), shared by every car of the type.
static var _badge_cache: Dictionary = {}
## Per character: its plate ribbons (plate space, origin at the glyph's baseline start).
static var _glyph_cache: Dictionary = {}
static var _mats: Array = []
## Cars waiting for their plates (near(): a few a frame).
static var _queue: Array = []
const BUILDS_PER_FRAME := 3
## Glass materials already given their windscreen dust (per instance id).
static var _dusted: Dictionary = {}


## Everything for one car, from Vehicle._ready() once the body, the wheels and the lamps exist.
static func attach(car: Vehicle) -> void:
	if not enabled or not car._has_model:
		return
	var look := look_of(car)
	var g := grime_for(car.body_type, look)
	# Stills: CAR_GRIME=grime,mud,scratches,dust bucket forces every car's level.
	var force := OS.get_environment("CAR_GRIME")
	if force != "":
		var f := force.split(",")
		for i in mini(f.size(), 4):
			g[i] = f[i].to_float() if i < 3 else f[i].to_int()
	_paint_grime(car, g)
	_wheel_dust(car, g)
	_screen_dust(car)
	car.set_meta("car_detail", look)


## The plates and badges, built the first time the car comes within its shadow tier of the camera
## (Vehicle._update_body_tier()): a car that never comes near never pays for them.
## At most BUILDS_PER_FRAME a frame (about a millisecond each); the rest wait their turn.
static func near(car: Vehicle) -> void:
	if not car.has_meta("car_detail"):
		return
	if not (MAKES.has(car.body_type) and PLATE_AT.has(car.body_type)):
		car.remove_meta("car_detail")
		return
	if not _queue.has(car):
		_queue.append(car)
	_arm()


## Builds every queued car now (tests and stills).
static func flush() -> void:
	while not _queue.is_empty():
		_build_next()


static func _drain() -> void:
	for i in BUILDS_PER_FRAME:
		if _queue.is_empty():
			return
		_build_next()
	_arm()


static func _arm() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not _queue.is_empty() and not tree.process_frame.is_connected(_drain):
		tree.process_frame.connect(_drain, CONNECT_ONE_SHOT)


static func _build_next() -> void:
	# Untyped first: a car freed while it waited (a pooled or unloaded one) is a dead reference,
	# and assigning that to a typed variable is a script error.
	var v: Variant = _queue.pop_front()
	if not is_instance_valid(v):
		return
	var car := v as Vehicle
	if car == null or not car.has_meta("car_detail") or not car.is_inside_tree():
		return
	var look: int = car.get_meta("car_detail")
	car.remove_meta("car_detail")
	_add_detail_mesh(car, look)


## The car's own hash: the same car always reads the same plate.
static func look_of(car: Vehicle) -> int:
	return absi(hash([car.look_seed, int(car.body_type), car.paint.to_rgba32(), 59]))


## [grime, mud, scratches, wheel dust bucket 0..2] for a body type and look hash. Pure.
static func grime_for(body_type: int, look: int) -> Array:
	var roll := look % 100
	var level := 0
	while level < GRIME_ODDS.size() - 1 and roll >= int(GRIME_ODDS[level]):
		level += 1
	var work := WORK.has(body_type)
	if work:
		level = mini(level + 1, GRIME_LEVELS.size() - 1)
	if body_type == Vehicle.BodyType.BEATER:
		level = maxi(level, 2)
	var grime: float = GRIME_LEVELS[level]
	# Some variety inside a level, so two dirty cars are not equally dirty.
	grime *= 0.85 + 0.3 * float((look >> 7) % 64) / 63.0
	var mud := 0.0
	if work and (look >> 13) % 2 == 0:
		mud = 0.55 + 0.45 * float((look >> 15) % 16) / 15.0
	var scratches := 0.25 + 0.75 * float((look >> 19) % 32) / 31.0
	if level == 0:
		scratches *= 0.35
	return [clampf(grime, 0.0, 1.0), mud, scratches, clampi(level - 1 if level > 0 else 0, 0, 2)]


## Invented format: two letters, a digit, a dash, three digits ("KR4-827"). Pure.
static func plate_text(look: int) -> String:
	var h := absi(hash([look, "plate"]))
	var s := ""
	s += PLATE_LETTERS[h % PLATE_LETTERS.length()]
	s += PLATE_LETTERS[(h >> 5) % PLATE_LETTERS.length()]
	s += str((h >> 10) % 10)
	s += "-"
	s += str((h >> 14) % 10) + str((h >> 18) % 10) + str((h >> 22) % 10)
	return s


## The sidewall text for a wheel: [maker, line, size]. Pure (style and size only, since the near
## wheel mesh is shared by every car on that style and size).
static func tyre_text(style: int, radius: float, rim_r: float, width: float) -> Array:
	var h := absi(hash([style, roundi(radius * 500.0), roundi(width * 500.0), "tyre"]))
	var sec := roundi(width * 1000.0 / 5.0) * 5
	var ratio := clampi(roundi((radius - rim_r) / maxf(width, 0.01) * 20.0) * 5, 25, 80)
	var rim_in := roundi(rim_r * 2.0 / 0.0254)
	var load := 88 + (h >> 4) % 14
	var speed: String = ["H", "V", "W", "T"][(h >> 9) % 4]
	return [TYRE_MAKERS[h % TYRE_MAKERS.size()], TYRE_LINES[(h >> 2) % TYRE_LINES.size()],
			"%d/%dR%d %d%s" % [sec, ratio, rim_in, load, speed]]


# --- Paint, wheels, glass ---------------------------------------------------------------------

## Every paint material the body's meshes wear (one per car, Vehicle._paint_material()).
static func paint_materials(car: Vehicle) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	var holder := car.get_node_or_null("BodyModel")
	if holder == null:
		return out
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var sm := m.get_surface_override_material(si) as ShaderMaterial
			if sm != null and sm.shader == Vehicle.PAINT_SHADER and not out.has(sm):
				out.append(sm)
	return out


static func _paint_grime(car: Vehicle, g: Array) -> void:
	var mats := paint_materials(car)
	if mats.is_empty():
		return
	var holder := car.get_node_or_null("BodyModel") as Node3D
	var near: MeshInstance3D = null
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		if not String(mi.name).ends_with("_far"):
			near = mi
			break
	if near == null:
		return
	# Car space -> the body mesh's own space: the arches go in where the shader works.
	var to_car := holder.transform * CarCabin.chain(near, holder)
	var to_mesh := to_car.affine_inverse()
	var scale := maxf(to_car.basis.get_scale().x, 1e-4)
	var pose := car._wheel_pose()
	var d := car._dims()
	var hub_y := float(pose.get("y", 0.2))
	var f := to_mesh * Vector3(0.0, hub_y, float(pose.get("front", -1.4)))
	var r := to_mesh * Vector3(0.0, hub_y, float(pose.get("rear", 1.4)))
	var bottom := to_mesh * Vector3(0.0, float(d.get("ride", car.model_bottom_y)), 0.0)
	var mat0: ShaderMaterial = mats[0]
	var along_x: bool = bool(mat0.get_shader_parameter("length_is_x"))
	var fa := f.x if along_x else f.z
	var ra := r.x if along_x else r.z
	var arch_r := float(pose.get("r", 0.34)) / scale
	for m in mats:
		m.set_shader_parameter("grime", float(g[0]))
		m.set_shader_parameter("mud", float(g[1]))
		m.set_shader_parameter("scratches", float(g[2]))
		m.set_shader_parameter("grime_arch", Vector4(fa, ra, f.y, arch_r))
		# y of the body's bottom in mesh units, metres per mesh unit, which way the tail is.
		m.set_shader_parameter("grime_frame", Vector3(bottom.y, scale, signf(ra - fa) if ra != fa else 1.0))


## The wheels' brake dust: the kit's material at this car's dust level (shared copies).
static func _wheel_dust(car: Vehicle, g: Array) -> void:
	var bucket := int(g[3])
	if bucket == 0 and float(g[0]) <= 0.0:
		return
	var base := PropFactory.wheel_material(car.wheel_kit)
	var dusty := PropFactory.wheel_material(car.wheel_kit, false, bucket + 1)
	for rig: Array in car._wheel_rigs:
		for i in [1, 2]:
			var mi := rig[i] as MeshInstance3D
			if mi != null and mi.material_override == base:
				mi.material_override = dusty


## The windscreen's dust outside the wipers' sweep: the body type's shared cabin glass gets a
## level from the type (every car of a type shares that material).
static func _screen_dust(car: Vehicle) -> void:
	var holder := car.get_node_or_null("BodyModel")
	if holder == null:
		return
	var level := 0.35 + 0.45 * float(absi(hash([int(car.body_type), "screen"])) % 100) / 99.0
	if WORK.has(car.body_type):
		level = minf(level + 0.25, 1.0)
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var sm := m.get_surface_override_material(si) as ShaderMaterial
			if sm == null or _dusted.has(sm.get_instance_id()):
				continue
			if sm.shader == null or not String(sm.shader.resource_path).ends_with("car_glass.gdshader"):
				continue
			sm.set_shader_parameter("screen_dust", level)
			_dusted[sm.get_instance_id()] = true


# --- Plates and badges ------------------------------------------------------------------------

## The shared detail material: `lit` is the rear plate lamp on (Vehicle._refresh_lights()).
static func material(lit: bool) -> ShaderMaterial:
	if _mats.is_empty():
		for on: bool in [false, true]:
			var m := ShaderMaterial.new()
			m.shader = DETAIL_SHADER
			m.set_shader_parameter("plate_lamp", 1.0 if on else 0.0)
			m.set_shader_parameter("chrome_metal", PropFactory.has_reflections())
			_mats.append(m)
	return _mats[1 if lit else 0]


## Lamps on or off (Vehicle._refresh_lights()): the rear plate lamp follows the tail lamps.
static func lamps(car: Vehicle, on: bool) -> void:
	var mi := car.get_node_or_null("CarDetail") as MeshInstance3D
	if mi != null:
		if mi.has_meta("crash_mat"):
			# A crashed car's own copy (CrashDeform.detail()).
			(mi.get_meta("crash_mat") as ShaderMaterial).set_shader_parameter("plate_lamp", 1.0 if on else 0.0)
			return
		var want := material(on)
		if mi.material_override != want:
			mi.material_override = want


static func _add_detail_mesh(car: Vehicle, look: int) -> void:
	var spots := _spots(car)
	if spots.is_empty():
		return
	var a := Arrays.new()
	var badges: Arrays = _badge_cache.get(car.body_type)
	if badges == null:
		badges = Arrays.new()
		_badges(badges, car.body_type, spots)
		_badge_cache[car.body_type] = badges
	a.append(badges)
	var text := plate_text(look)
	var tag := (look >> 3) % TAG_COLORS.size()
	_plate(a, spots.rear, text, tag, true)
	_plate(a, spots.front, text, tag, false)
	var mi := MeshInstance3D.new()
	mi.name = "CarDetail"
	mi.mesh = a.commit()
	mi.material_override = material(car.lights_running())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = car.body_far_distance
	car.add_child(mi)
	CrashDeform.detail(car, mi)


## Mesh arrays in progress (plain triangles, faces turned the way they are meant to face).
class Arrays:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	func tri(a: Vector3, b: Vector3, cc: Vector3, nrm: Vector3, col: Color, flag: float) -> void:
		# Godot's front face winds clockwise: (b - a) x (c - a) must point AWAY from the normal.
		if (b - a).cross(cc - a).dot(nrm) > 0.0:
			var t := b
			b = cc
			cc = t
		for p in [a, b, cc]:
			v.append(p)
			n.append(nrm)
			c.append(col)
			uv.append(Vector2(flag, 0.0))

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nrm: Vector3, col: Color, flag: float) -> void:
		tri(a, b, cc, nrm, col, flag)
		tri(a, cc, d, nrm, col, flag)

	func append(o: Arrays) -> void:
		v.append_array(o.v)
		n.append_array(o.n)
		c.append_array(o.c)
		uv.append_array(o.uv)

	## Another set moved by `xf` (in native code: no per-vertex GDScript), `flag` its UV.x.
	func append_xf(o: Arrays, xf: Transform3D, flag: float) -> void:
		v.append_array(xf * o.v)
		n.append_array(Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * o.n)
		c.append_array(o.c)
		var u := PackedVector2Array()
		u.resize(o.uv.size())
		u.fill(Vector2(flag, 0.0))
		uv.append_array(u)

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		var m := ArrayMesh.new()
		if not v.is_empty():
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func _col(srgb: Color, kind: int) -> Color:
	return Color(srgb.r, srgb.g, srgb.b, (float(kind) + 0.5) / 8.0)


## A flat box in a frame (car space): centre `o`, axes ex / ey / ez, half sizes hx / hy, from
## z0 to z1 along ez. The back face is left off (it is against the body).
static func _slab(a: Arrays, o: Vector3, ex: Vector3, ey: Vector3, ez: Vector3, hx: float, hy: float,
		z0: float, z1: float, col: Color, flag: float) -> void:
	var p := func(x: float, y: float, z: float) -> Vector3: return o + ex * x + ey * y + ez * z
	a.quad(p.call(-hx, -hy, z1), p.call(hx, -hy, z1), p.call(hx, hy, z1), p.call(-hx, hy, z1), ez, col, flag)
	a.quad(p.call(-hx, hy, z0), p.call(hx, hy, z0), p.call(hx, hy, z1), p.call(-hx, hy, z1), ey, col, flag)
	a.quad(p.call(-hx, -hy, z0), p.call(hx, -hy, z0), p.call(hx, -hy, z1), p.call(-hx, -hy, z1), -ey, col, flag)
	a.quad(p.call(hx, -hy, z0), p.call(hx, hy, z0), p.call(hx, hy, z1), p.call(hx, -hy, z1), ex, col, flag)
	a.quad(p.call(-hx, -hy, z0), p.call(-hx, hy, z0), p.call(-hx, hy, z1), p.call(-hx, -hy, z1), -ex, col, flag)


## A polyline with the points that bend it less than `eps` taken out (Ramer-Douglas-Peucker):
## SignFont draws a bowl in up to twenty segments, which at plate size is wasted triangles.
static func simplify(s: PackedVector2Array, eps: float) -> PackedVector2Array:
	if s.size() < 3:
		return s
	var keep := PackedByteArray()
	keep.resize(s.size())
	keep.fill(0)
	keep[0] = 1
	keep[s.size() - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, s.size() - 1)]
	while not stack.is_empty():
		var r: Vector2i = stack.pop_back()
		var a := s[r.x]
		var b := s[r.y]
		var best := -1.0
		var bi := -1
		for i in range(r.x + 1, r.y):
			var d := Geometry2D.get_closest_point_to_segment(s[i], a, b).distance_to(s[i])
			if d > best:
				best = d
				bi = i
		if bi >= 0 and best > eps:
			keep[bi] = 1
			stack.append(Vector2i(r.x, bi))
			stack.append(Vector2i(bi, r.y))
	var out := PackedVector2Array()
	for i in s.size():
		if keep[i] == 1:
			out.append(s[i])
	return out


## Strokes (2D polylines, metres) swept into raised ribbons on a flat frame: top face `lift`
## proud of the frame's z = `base`, its two long sides down to the base.
static func _ribbons(a: Arrays, strokes: Array, pen: float, o: Vector3, ex: Vector3, ey: Vector3,
		ez: Vector3, base: float, lift: float, col: Color, flag: float, walls: bool = true) -> void:
	var hp := pen * 0.5
	for s0: PackedVector2Array in strokes:
		var s := simplify(s0, pen * 0.12)
		for i in s.size() - 1:
			var p0 := s[i]
			var p1 := s[i + 1]
			var d := p1 - p0
			var l := d.length()
			if l < 1e-6:
				continue
			d /= l
			var side := Vector2(-d.y, d.x) * hp
			# Square caps half a pen past each end, so joints close.
			p0 -= d * hp
			p1 += d * hp
			var to3 := func(q: Vector2, z: float) -> Vector3: return o + ex * q.x + ey * q.y + ez * z
			var tl := base + lift
			a.quad(to3.call(p0 - side, tl), to3.call(p1 - side, tl), to3.call(p1 + side, tl), to3.call(p0 + side, tl), ez, col, flag)
			if not walls:
				continue
			var sd := (ex * side.x + ey * side.y).normalized()
			a.quad(to3.call(p0 + side, base), to3.call(p1 + side, base), to3.call(p1 + side, tl), to3.call(p0 + side, tl), sd, col, flag)
			a.quad(to3.call(p0 - side, base), to3.call(p1 - side, base), to3.call(p1 - side, tl), to3.call(p0 - side, tl), -sd, col, flag)


## Text laid out by SignFont at cap height `cap`, centred on (cx, cy), squeezed to `max_w`.
static func _text_strokes(text: String, cap: float, pen: float, cx: float, cy: float, max_w: float) -> Array:
	var lay := SignFont.layout(text, cap, pen)
	var w: float = lay[1]
	var k := minf(1.0, max_w / maxf(w, 1e-4))
	var out: Array = []
	for s: PackedVector2Array in lay[0]:
		var p := PackedVector2Array()
		for q in s:
			p.append(Vector2(cx + (q.x - w * 0.5) * k, cy + q.y - cap * 0.5))
		out.append(p)
	return out


## One plate at `t` (car space; basis x across as you read it, y up, z out of the plate). Built
## from pieces cached in the plate's own frame (the plate itself, its printing, each embossed
## character), moved into place natively: a car's two plates cost well under a millisecond.
static func _plate(a: Arrays, t: Transform3D, text: String, tag: int, rear: bool) -> void:
	var flag := 1.0 if rear else 0.0
	a.append_xf(_plate_static(tag), t, flag)
	# Embossed characters, laid out as SignFont.layout() does, squeezed to the plate.
	var xs: Array = []
	var x := 0.0
	var first := true
	for i in text.length():
		var g := SignFont.glyph(text[i])
		if (g[0] as Array).is_empty():
			x += float(g[1]) * PLATE_CAP
			first = true
			xs.append(-1.0)
			continue
		if not first:
			x += SignFont.TRACKING * PLATE_CAP + PLATE_PEN
		xs.append(x)
		x += float(g[1]) * PLATE_CAP
		first = false
	var k := minf(1.0, PLATE_TEXT_W / maxf(x, 1e-4))
	for i in text.length():
		if float(xs[i]) < 0.0:
			continue
		var place := Transform3D(Basis.from_scale(Vector3(k, 1.0, 1.0)), Vector3((float(xs[i]) - x * 0.5) * k, 0.0, 0.0))
		a.append_xf(_plate_char(text[i]), t * place, flag)


## The plate, its surround, bolts, tag (by colour index) and printing, in the plate's frame.
static func _plate_static(tag: int) -> Arrays:
	var key := "plate_%d" % tag
	if _glyph_cache.has(key):
		return _glyph_cache[key]
	var a := Arrays.new()
	var o := Vector3.ZERO
	var ex := Vector3.RIGHT
	var ey := Vector3.UP
	var ez := Vector3.BACK
	var white := _col(Color(0.90, 0.91, 0.92), K_SHEET)
	var tag_col: Color = TAG_COLORS[posmod(tag, TAG_COLORS.size())]
	_slab(a, o, ex, ey, ez, PLATE_W * 0.5 + 0.008, PLATE_H * 0.5 + 0.008, -0.004, 0.0, _col(Color(0.03, 0.03, 0.035), K_PLASTIC), 0.0)
	_slab(a, o, ex, ey, ez, PLATE_W * 0.5, PLATE_H * 0.5, 0.0, PLATE_T, white, 0.0)
	_slab(a, o + ex * (PLATE_W * 0.5 - 0.034) + ey * (PLATE_H * 0.5 - 0.022), ex, ey, ez, 0.019, 0.011, PLATE_T, PLATE_T + 0.0003, _col(tag_col, K_TAG), 0.0)
	# Two bolts across the top (7 in apart, the US hole pattern).
	for sx: float in [-1.0, 1.0]:
		_slab(a, o + ex * (sx * 0.089) + ey * (PLATE_H * 0.5 - 0.022), ex, ey, ez, 0.0055, 0.0055, PLATE_T, PLATE_T + 0.0025, _col(Color(0.72, 0.72, 0.74), K_CHROME), 0.0)
	# The banner in red over the characters and the tag line in blue under them, printed.
	_ribbons(a, _text_strokes(PLATE_BANNER, 0.017, 0.0032, 0.0, PLATE_H * 0.5 - 0.022, 0.15), 0.0032,
			o, ex, ey, ez, PLATE_T, 0.0002, _col(Color(0.62, 0.07, 0.08), K_RED), 0.0, false)
	_ribbons(a, _text_strokes(PLATE_FOOT, 0.011, 0.0022, 0.0, -PLATE_H * 0.5 + 0.014, 0.20), 0.0022,
			o, ex, ey, ez, PLATE_T, 0.0002, _col(Color(0.08, 0.18, 0.50), K_BLUE), 0.0, false)
	_glyph_cache[key] = a
	return a


## One embossed character in the plate's frame, its left edge at x 0.
static func _plate_char(ch: String) -> Arrays:
	if _glyph_cache.has(ch):
		return _glyph_cache[ch]
	var a := Arrays.new()
	var lay := SignFont.layout(ch, PLATE_CAP, PLATE_PEN)
	var strokes: Array = []
	for s: PackedVector2Array in lay[0]:
		var p := PackedVector2Array()
		for q in s:
			p.append(Vector2(q.x, q.y - PLATE_CAP * 0.5 - 0.008))
		strokes.append(p)
	_ribbons(a, strokes, PLATE_PEN, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK, PLATE_T, PLATE_LIFT, _col(Color(0.05, 0.08, 0.24), K_INK), 0.0)
	_glyph_cache[ch] = a
	return a


## The maker's emblem, the model's name and the grille's emblem, in car space.
static func _badges(a: Arrays, body_type: int, spots: Dictionary) -> void:
	var make: Array = MAKES[body_type]
	var brand: int = make[0]
	var chrome := _col(Color(0.80, 0.81, 0.83), K_CHROME)
	var back := _col(Color(0.025, 0.025, 0.03), K_PLASTIC)
	for key: String in ["badge_r", "badge_f"]:
		if not spots.has(key):
			continue
		var t: Transform3D = spots[key]
		var rad := 0.042 if key == "badge_r" else 0.050
		# A black disc behind a chrome ring and the brand's mark.
		var disc := PackedVector2Array()
		for i in 25:
			var an := TAU * float(i) / 24.0
			disc.append(Vector2(cos(an), sin(an)) * rad)
		for i in 24:
			a.tri(t.origin, t.origin + t.basis.x * disc[i].x + t.basis.y * disc[i].y,
					t.origin + t.basis.x * disc[i + 1].x + t.basis.y * disc[i + 1].y, t.basis.z, back, 0.0)
		_ribbons(a, [disc], rad * 0.16, t.origin, t.basis.x, t.basis.y, t.basis.z, 0.0, 0.004, chrome, 0.0)
		_ribbons(a, mark(brand, rad * 0.62), rad * 0.13, t.origin, t.basis.x, t.basis.y, t.basis.z, 0.0, 0.0035, chrome, 0.0)
	if spots.has("script_r"):
		var t2: Transform3D = spots.script_r
		var strokes := _text_strokes(String(make[1]), 0.026, 0.0034, 0.0, 0.0, 0.30)
		_ribbons(a, strokes, 0.0034, t2.origin, t2.basis.x, t2.basis.y, t2.basis.z, 0.0, 0.0028, chrome, 0.0)


## The brand's mark (CarDealers.BRANDS order) as strokes inside a circle of radius `r`.
static func mark(brand: int, r: float) -> Array:
	var V := func(x: float, y: float) -> Vector2: return Vector2(x, y) * r
	match brand:
		0: # VELMARA: a winged V.
			return [PackedVector2Array([V.call(-0.9, 0.45), V.call(0.0, -0.7), V.call(0.9, 0.45)]),
					PackedVector2Array([V.call(-0.55, 0.45), V.call(0.0, -0.2), V.call(0.55, 0.45)])]
		1: # QUENTIS: a diamond with a bar through it.
			return [PackedVector2Array([V.call(0.0, 0.85), V.call(0.75, 0.0), V.call(0.0, -0.85), V.call(-0.75, 0.0), V.call(0.0, 0.85)]),
					PackedVector2Array([V.call(-0.95, 0.0), V.call(0.95, 0.0)])]
		2: # HALDRIC: a shield.
			return [PackedVector2Array([V.call(-0.7, 0.75), V.call(0.7, 0.75), V.call(0.7, 0.05), V.call(0.0, -0.85), V.call(-0.7, 0.05), V.call(-0.7, 0.75)]),
					PackedVector2Array([V.call(0.0, 0.75), V.call(0.0, -0.85)])]
		3: # ORIVO: two rings.
			var p := PackedVector2Array()
			var q := PackedVector2Array()
			for i in 17:
				var an := TAU * float(i) / 16.0
				p.append(V.call(-0.32 + cos(an) * 0.5, sin(an) * 0.5))
				q.append(V.call(0.32 + cos(an) * 0.5, sin(an) * 0.5))
			return [p, q]
		4: # SUNDALE: a half sun with rays.
			var out: Array = []
			var arc := PackedVector2Array()
			for i in 9:
				var an := PI * float(i) / 8.0
				arc.append(V.call(cos(an) * 0.45, sin(an) * 0.45 - 0.3))
			out.append(arc)
			out.append(PackedVector2Array([V.call(-0.9, -0.3), V.call(0.9, -0.3)]))
			for i in 5:
				var an := PI * (0.1 + 0.8 * float(i) / 4.0)
				out.append(PackedVector2Array([V.call(cos(an) * 0.62, sin(an) * 0.62 - 0.3), V.call(cos(an) * 0.88, sin(an) * 0.88 - 0.3)]))
			return out
		_: # BRAVENT: a double chevron.
			return [PackedVector2Array([V.call(-0.8, -0.1), V.call(0.0, 0.55), V.call(0.8, -0.1)]),
					PackedVector2Array([V.call(-0.8, -0.6), V.call(0.0, 0.05), V.call(0.8, -0.6)])]


## Where the plates and badges go on this body type, car space, measured once by rays against
## the near body meshes (where the renderer keeps mesh data), else from the box. Keys rear,
## front, badge_r, badge_f, script_r: Transform3D (x across as read, y up, z out).
static func _spots(car: Vehicle) -> Dictionary:
	if _spot_cache.has(car.body_type):
		return _spot_cache[car.body_type]
	var hint: Array = PLATE_AT[car.body_type]
	var d := car._dims()
	var ride := float(d.get("ride", car.model_bottom_y))
	var half_l := float(d.length) * 0.5
	var tris := _tris(car)
	var out := {}
	var rear_y := ride + float(hint[0])
	var rear_x := float(hint[1])
	var front_y := ride + float(hint[2])
	var rear := _flat_spot(tris, rear_x, rear_y, 1.0, PLATE_W * 0.42, PLATE_H * 0.4)
	if rear.is_empty():
		rear = [Vector3(rear_x, rear_y, half_l - 0.02), Vector3.BACK]
	var front := _flat_spot(tris, 0.0, front_y, -1.0, PLATE_W * 0.42, PLATE_H * 0.4, true)
	if front.is_empty():
		front = [Vector3(0.0, front_y, -half_l + 0.02), Vector3.FORWARD]
	out["rear"] = _frame(rear[0] + rear[1] * PLATE_STANDOFF, rear[1])
	out["front"] = _frame(front[0] + front[1] * PLATE_STANDOFF, front[1])
	# The rear emblem: centred over the plate (over the bumper on the van's off-centre plate), the
	# first flat painted spot going up; the model's name to the right of it.
	var by: float = rear[0].y + PLATE_H * 0.5 + 0.07
	for k in 8:
		var s := _flat_spot(tris, 0.0, by + 0.04 * k, 1.0, 0.035, 0.035)
		if not s.is_empty():
			out["badge_r"] = _frame(s[0] + s[1] * 0.002, s[1])
			break
	if not out.has("badge_r") and tris.is_empty():
		out["badge_r"] = _frame(Vector3(0.0, by + 0.06, half_l - 0.01), Vector3.BACK)
	var sx := float(d.width) * 0.24
	var sy: float = out.badge_r.origin.y if out.has("badge_r") else by
	for k in 6:
		var s := _flat_spot(tris, sx, sy - 0.03 * k, 1.0, 0.13, 0.015)
		if not s.is_empty():
			out["script_r"] = _frame(s[0] + s[1] * 0.002, s[1])
			break
	if not out.has("script_r") and tris.is_empty():
		out["script_r"] = _frame(Vector3(sx, sy, half_l - 0.01), Vector3.BACK)
	# The grille's emblem, over the front plate.
	for k in 8:
		var s := _flat_spot(tris, 0.0, front[0].y + PLATE_H * 0.5 + 0.06 + 0.035 * k, -1.0, 0.04, 0.04, true)
		if not s.is_empty():
			out["badge_f"] = _frame(s[0] + s[1] * 0.004, s[1])
			break
	if not out.has("badge_f") and tris.is_empty():
		out["badge_f"] = _frame(Vector3(0.0, front[0].y + 0.17, -half_l + 0.01), Vector3.FORWARD)
	_spot_cache[car.body_type] = out
	return out


## A frame at `p` facing `n` (tilted only about x: a plate stands upright across the car).
static func _frame(p: Vector3, n: Vector3) -> Transform3D:
	var ez := Vector3(0.0, n.y, n.z).normalized()
	if ez.length_squared() < 0.5:
		ez = Vector3.BACK
	var ey := (Vector3.UP - ez * Vector3.UP.dot(ez)).normalized()
	var ex := ey.cross(ez)
	return Transform3D(Basis(ex, ey, ez), p)


## The near body's triangles for the spot search: [TriangleMesh data, mesh -> car] per mesh.
static func _tris(car: Vehicle) -> Array:
	var holder := car.get_node_or_null("BodyModel") as Node3D
	var out: Array = []
	if holder == null:
		return out
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm := String(m.name)
		if nm.ends_with("_far") or nm.begins_with("door_") or nm.begins_with("rig_") or nm.contains("_trailer"):
			continue
		var tri := CarDamage._tri_for(m)
		if tri.is_empty():
			continue
		out.append([tri, holder.transform * CarCabin.chain(m, holder)])
	return out


## Casts along -dir*Z from outside the car at (x, y); [point, normal, slot] of the nearest hit.
static func _ray(tris: Array, x: float, y: float, dir: float) -> Array:
	var best: Array = []
	var best_d := INF
	var o := Vector3(x, y, dir * 12.0)
	var dv := Vector3(0.0, 0.0, -dir)
	for e: Array in tris:
		var to_car: Transform3D = e[1]
		var inv := to_car.affine_inverse()
		var tri: Array = e[0]
		var r: Dictionary = (tri[0] as TriangleMesh).intersect_ray(inv * o, (inv.basis * dv).normalized())
		if r.is_empty():
			continue
		var p: Vector3 = to_car * (r.position as Vector3)
		var dd := o.distance_to(p)
		if dd < best_d:
			best_d = dd
			var nn: Vector3 = (to_car.basis * (r.normal as Vector3)).normalized()
			if nn.z * dir < 0.0:
				nn = -nn
			best = [p, nn, CarDamage._slot_of_face(tri, int(r.get("face_index", -1)))]
	return best


## A flat spot about (x, y) facing `dir` (+1 the tail, -1 the nose): five rays a window
## (centre, +-hx, +-hy), searched outward from y. [point, normal] or [] (no mesh data, or nothing
## flat enough near). `bracket`: stand on the frontmost hit (a front plate on a grille).
static func _flat_spot(tris: Array, x: float, y: float, dir: float, hx: float, hy: float, bracket: bool = false) -> Array:
	if tris.is_empty():
		return []
	for k in 15:
		var yy := y + (0.0 if k == 0 else 0.02 * float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0))
		var pts: Array = []
		var ok := true
		for off: Vector2 in [Vector2.ZERO, Vector2(-hx, 0.0), Vector2(hx, 0.0), Vector2(0.0, -hy), Vector2(0.0, hy)]:
			var h := _ray(tris, x + off.x, yy + off.y, dir)
			if h.is_empty() or ["glass", "light_front", "light_rear", "tyre", "glass_door", "sign"].has(String(h[2])):
				ok = false
				break
			if (h[1] as Vector3).z * dir < 0.45:
				ok = false
				break
			pts.append(h)
		if not ok:
			continue
		var zs: Array = pts.map(func(h: Array) -> float: return (h[0] as Vector3).z)
		var spread: float = zs.max() - zs.min()
		if spread > (0.06 if bracket else 0.035):
			continue
		var n := Vector3.ZERO
		for h: Array in pts:
			n += h[1]
		n = n.normalized()
		var z: float = zs.max() if dir > 0.0 else zs.min()
		return [Vector3(x, yy, z), n]
	return []


# --- Tyre sidewall lettering --------------------------------------------------------------------

## Raised moulded lettering on the outboard sidewall of a near wheel mesh (PropFactory.car_wheel,
## axle along X, outboard +X): the maker top and bottom, the line and the size either side.
static func tyre_letters(st: SurfaceTool, style: int, r_out: float, rim_r: float, hw: float, width: float) -> void:
	var sw := r_out - rim_r
	var txt := tyre_text(style, r_out, rim_r, width)
	var cap := sw * 0.30
	var r0 := rim_r + sw * 0.40
	var runs := [[txt[0], 0.0, cap], [txt[0], PI, cap], [txt[2], PI * 0.5, cap * 0.55], [txt[1], -PI * 0.5, cap * 0.55]]
	# The sidewall's profile (PropFactory._wheel_tyre): x in half-widths at fractions of its height.
	var prof := [[0.17, 0.945], [0.36, 1.000], [0.52, 0.975], [0.68, 0.930], [0.84, 0.875]]
	var x_of := func(r: float) -> float:
		var f := (r - rim_r) / sw
		for i in prof.size() - 1:
			var a: Array = prof[i]
			var b: Array = prof[i + 1]
			if f <= float(b[0]) or i == prof.size() - 2:
				return lerpf(float(a[1]), float(b[1]), clampf((f - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)) * hw
		return hw
	var lift := maxf(sw * 0.012, 0.0009)
	for run: Array in runs:
		var c: float = run[2]
		var pen := c * 0.13
		var lay := SignFont.layout(String(run[0]), c, pen)
		var w: float = lay[1]
		var r_mid := r0 + c * 0.5
		var a_c: float = run[1]
		var r_base := r0 if absf(c - cap) < 1e-6 else r0 + (cap - c) * 0.5
		var map := func(q: Vector2, up: float) -> Vector3:
			var r := r_base + q.y
			var an := a_c - (q.x - w * 0.5) / r_mid
			return PropFactory._wp(float(x_of.call(r)) + up, r, an)
		for s0: PackedVector2Array in lay[0]:
			var s := simplify(s0, pen * 0.15)
			for i in s.size() - 1:
				var p0 := s[i]
				var p1 := s[i + 1]
				var dd := p1 - p0
				var l := dd.length()
				if l < 1e-6:
					continue
				dd /= l
				var side := Vector2(-dd.y, dd.x) * pen * 0.5
				p0 -= dd * pen * 0.5
				p1 += dd * pen * 0.5
				var t00: Vector3 = map.call(p0 - side, lift)
				var t10: Vector3 = map.call(p1 - side, lift)
				var t11: Vector3 = map.call(p1 + side, lift)
				var t01: Vector3 = map.call(p0 + side, lift)
				PropFactory._wqf(st, t00, t10, t11, t01, Vector3.RIGHT, 1.0, PropFactory.WheelSlot.LETTER)
				var b01: Vector3 = map.call(p0 + side, -0.0006)
				var b11: Vector3 = map.call(p1 + side, -0.0006)
				var b00: Vector3 = map.call(p0 - side, -0.0006)
				var b10: Vector3 = map.call(p1 - side, -0.0006)
				PropFactory._wqf(st, b01, b11, t11, t01, t01 - t00, 0.8, PropFactory.WheelSlot.LETTER)
				PropFactory._wqf(st, b00, b10, t10, t00, t00 - t01, 0.8, PropFactory.WheelSlot.LETTER)
