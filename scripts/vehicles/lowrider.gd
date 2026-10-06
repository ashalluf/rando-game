class_name Lowrider
## Lowriders (very LA): two classic bodies built by tools/make_lowriders.py - a 1960s full-size
## hardtop and a 1980s personal-luxury coupe - in candy paint over deep metal flake with
## hand-laid pinstripes and a patterned roof (car_paint.gdshaderinc's `custom` block), on chrome
## 13" wire wheels with thin whitewalls (wire_wheel(), built here), laid low, with hydraulics
## (Hydraulics): at a weekend cruise night (LowriderMeet) they hop, three-wheel and dance at the
## kerb with a crowd round them; now and then one cruises slow in traffic, bouncing.
##
## They ARE Vehicles (BodyType.LOWRIDER_*, BODY_ODDS 0: never rolled), so damage, cabin glass and
## drivers, lights, pools and the rest work unchanged. Everything per car is a hash of its look.
## LOWRIDERS=0 in the environment turns the meets and the cruisers off (the A/B).

const HARDTOP := Vehicle.BodyType.LOWRIDER_HARDTOP
const COUPE := Vehicle.BodyType.LOWRIDER_COUPE

static var enabled: bool = OS.get_environment("LOWRIDERS") != "0"

## Vehicle._dims() rows (tools/make_lowriders.py prints length, the ride and the road, the
## lamps' model heights; the physics wheels sit under the model's axles).
const DIMS := {
	HARDTOP: {"length": 5.489, "width": 2.01, "lamp_y": 0.498, "tail_y": 0.59, "chassis_h": 0.62, "cabin": Vector2(-0.6, 2.4), "cabin_h": 0.42,
			"wheel_z": 1.5, "wheel_front": 1.441, "wheel_rear": 1.579, "track": 1.58, "tyre_r": 0.29, "ride": -0.096, "road": -0.120},
	COUPE: {"length": 5.148, "width": 1.84, "lamp_y": 0.54, "tail_y": 0.58, "chassis_h": 0.64, "cabin": Vector2(-0.5, 2.2), "cabin_h": 0.42,
			"wheel_z": 1.36, "wheel_front": 1.337, "wheel_rear": 1.383, "track": 1.48, "tyre_r": 0.29, "ride": -0.096, "road": -0.120},
}

## Candy colours: [face-on colour, the deep colour at grazing angles, the flake's tint]. Invented
## mixes in the spirit of the classic candies; none is a paint maker's named colour.
const CANDIES := [
	[Color(0.66, 0.03, 0.05), Color(0.13, 0.0, 0.012), Color(1.0, 0.72, 0.55)],   # apple red
	[Color(0.88, 0.30, 0.03), Color(0.30, 0.04, 0.0), Color(1.0, 0.85, 0.5)],     # tangerine
	[Color(0.40, 0.05, 0.48), Color(0.07, 0.0, 0.11), Color(0.85, 0.75, 1.0)],    # plum
	[Color(0.05, 0.18, 0.66), Color(0.0, 0.02, 0.15), Color(0.7, 0.85, 1.0)],     # cobalt
	[Color(0.03, 0.48, 0.44), Color(0.0, 0.09, 0.10), Color(0.75, 1.0, 0.95)],    # teal
	[Color(0.66, 0.56, 0.06), Color(0.20, 0.11, 0.0), Color(1.0, 0.92, 0.55)],    # lime gold
	[Color(0.40, 0.14, 0.04), Color(0.07, 0.02, 0.0), Color(1.0, 0.75, 0.45)],    # root beer
	[Color(0.06, 0.44, 0.13), Color(0.0, 0.09, 0.02), Color(0.8, 1.0, 0.7)],      # emerald
	[Color(0.22, 0.0, 0.05), Color(0.035, 0.0, 0.01), Color(1.0, 0.6, 0.6)],      # black cherry
	[Color(0.90, 0.89, 0.86), Color(0.55, 0.50, 0.62), Color(1.0, 0.95, 0.85)],   # pearl white
]
## Pinstripe enamels and the patterned roof's second colour.
const PINS := [Color(0.95, 0.78, 0.30), Color(0.95, 0.95, 0.92), Color(0.74, 0.76, 0.80), Color(0.06, 0.06, 0.07), Color(0.20, 0.80, 0.82), Color(0.85, 0.12, 0.10)]
const PATTERNS := [Color(0.82, 0.82, 0.85), Color(0.90, 0.72, 0.30), Color(0.95, 0.95, 0.92)]
## Where the paint's pieces go, in each body's MESH space (x across, y up, z along, the nose at
## -z; make_lowriders.py's LOWRIDER lines): the flank line [y, front z, rear z], the bonnet [z at
## the cowl, z at the nose, its lowest top y, half width], the deck lid [z front, z tail, lowest
## y, half width], the roof [z front, z rear, half width, lowest y].
const PAINT_PLACES := {
	HARDTOP: {"side": Vector4(0.795, -2.48, 2.55, 0.0), "hood": Vector4(-0.70, -2.56, 0.80, 0.86),
			"deck": Vector4(1.95, 2.66, 0.85, 0.80), "roof": Vector4(0.05, 1.12, 0.62, 1.18)},
	COUPE: {"side": Vector4(0.815, -2.36, 2.42, 0.0), "hood": Vector4(-0.60, -2.40, 0.81, 0.78),
			"deck": Vector4(1.82, 2.48, 0.88, 0.72), "roof": Vector4(0.15, 0.78, 0.55, 1.20)},
}

## Wire wheels: the rim's radius over the tyre's (a 13" rim in a 155/80R13), and how often a car
## runs gold-plated hubs and nipples, or every third spoke gold.
const RIM_RATIO := 0.57
const GOLD_HUB_SHARE := 0.28
const GOLD_SPOKE_SHARE := 0.14
const SPOKES := 72

static var _cache: Dictionary = {}


static func is_lowrider(type: int) -> bool:
	return type == HARDTOP or type == COUPE


## A lowrider of `type` with the look `look` (paint, stripes and wheels all hash from it).
static func make(type: int, look: int) -> Vehicle:
	var car := Vehicle.new()
	var c: Array = CANDIES[absi(hash([look, 1])) % CANDIES.size()]
	car.setup(type as Vehicle.BodyType, c[0], Vehicle.Addon.NONE)
	car.setup_look(Vehicle.Finish.GLOSS)
	car.look_seed = look
	car.wheel_style = 0
	car.wheel_kit = 0
	return car


## The custom paint on a lowrider's paint material (Vehicle._paint_material()).
static func paint(car: Vehicle, mat: ShaderMaterial) -> void:
	var look := car.look_seed
	var c: Array = CANDIES[0]
	for row: Array in CANDIES:
		if (row[0] as Color).is_equal_approx(car.paint):
			c = row
	var places: Dictionary = PAINT_PLACES[car.body_type]
	mat.set_shader_parameter("custom", 1.0)
	mat.set_shader_parameter("candy_deep", c[1])
	mat.set_shader_parameter("flake_tint", c[2])
	mat.set_shader_parameter("paint_metallic", 0.55)
	mat.set_shader_parameter("paint_roughness", 0.15)
	mat.set_shader_parameter("clearcoat_amount", 1.0)
	mat.set_shader_parameter("clearcoat_roughness_value", 0.018)
	mat.set_shader_parameter("flake_strength", 0.45)
	mat.set_shader_parameter("flake_scale", 230.0)
	mat.set_shader_parameter("flake_fade_distance", 9.0)
	var pin: Color = PINS[absi(hash([look, 2])) % PINS.size()]
	if pin.get_luminance() < 0.12 and (c[0] as Color).get_luminance() < 0.15:
		pin = PINS[0]
	mat.set_shader_parameter("pin_color", pin)
	mat.set_shader_parameter("pattern_color", PATTERNS[absi(hash([look, 3])) % PATTERNS.size()])
	mat.set_shader_parameter("pin_style", float(absi(hash([look, 4])) % 4))
	mat.set_shader_parameter("pattern_amount", 1.0 if absi(hash([look, 5])) % 100 < 70 else 0.0)
	mat.set_shader_parameter("pin_side", places.side)
	mat.set_shader_parameter("pin_hood", places.hood)
	mat.set_shader_parameter("pin_deck", places.deck)
	mat.set_shader_parameter("pin_roof", places.roof)
	if c == CANDIES[CANDIES.size() - 1]:
		# The pearl white: a flip to violet at the edges instead of a candy's depth.
		mat.set_shader_parameter("pearl_amount", 0.6)
		mat.set_shader_parameter("pearl_color", Color(0.78, 0.70, 0.95))


# --- Wire wheels ---------------------------------------------------------------------------------

## The wheels (Vehicle._add_generated_wheels() hands a "wire" pose over here): the same rig shape
## as a car's, so _update_wheels() rolls and steers them.
static func add_wheels(car: Vehicle, pose: Dictionary) -> void:
	var r := float(pose.r)
	var w := float(pose.w)
	var gold := 0
	var roll := absi(hash([car.look_seed, 6])) % 1000
	if roll < int(GOLD_HUB_SHARE * 1000.0):
		gold = 1
	elif roll < int((GOLD_HUB_SHARE + GOLD_SPOKE_SHARE) * 1000.0):
		gold = 2
	var near := wire_wheel(r, w, true, gold)
	var far := wire_wheel(r, w, false, gold)
	var mat := wheel_material()
	car._wheel_radius = r
	car._wheel_far_end = car.wheel_draw_distance
	car._wheel_meshes = [[near, far, null], [near, far, null]]
	for front: bool in [true, false]:
		for side: float in [-1.0, 1.0]:
			var steer := Node3D.new()
			steer.name = "Wheel%s%s" % ["F" if front else "R", "L" if side < 0.0 else "R"]
			steer.position = Vector3(side * float(pose.x), float(pose.y), float(pose.front) if front else float(pose.rear))
			car.add_child(steer)
			var flip := Basis(Vector3.UP, 0.0 if side > 0.0 else PI)
			var mi := MeshInstance3D.new()
			mi.mesh = near
			mi.material_override = mat
			mi.basis = flip
			mi.visibility_range_end = car._wheel_far_end
			steer.add_child(mi)
			var cal := MeshInstance3D.new()
			cal.visible = false
			steer.add_child(cal)
			car._wheel_rigs.append([steer, mi, cal, flip, front, float(pose.y), near, far])
	car._susp_rest = PackedFloat32Array()
	car._susp_rest.resize(car._wheel_rigs.size())
	car._susp_rest.fill(NAN)
	car._last_yaw = car.rotation.y


## The shared wire-wheel material (shaders/wire_wheel.gdshader).
static func wheel_material() -> ShaderMaterial:
	var key := "mat_%s" % PropFactory.has_reflections()
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/wire_wheel.gdshader")
	m.set_shader_parameter("reflections", PropFactory.has_reflections())
	_cache[key] = m
	return m


# Part codes in the vertex alpha (wire_wheel.gdshader).
const K_RUBBER := 0.0
const K_WHITE := 0.25
const K_CHROME := 0.5
const K_GOLD := 0.75
const K_DARK := 1.0
const C_RUBBER := Color(0.045, 0.045, 0.05)
const C_WHITE := Color(0.80, 0.80, 0.77)
const C_CHROME := Color(0.92, 0.92, 0.94)
const C_GOLD := Color(1.0, 0.74, 0.32)
const C_DARK := Color(0.03, 0.03, 0.035)


## A 13" wire wheel on a thin-whitewall tyre, axle along X, outboard face toward +X, centred on
## the hub (PropFactory.car_wheel()'s convention). The reversed rim's deep chrome dish, 72 spokes
## cross-laced from the hub's two flanges to the nipples in the barrel, the hub, and a two-eared
## knock-off spinner standing proud. `near` false is the far LOD: the spokes as a grey disc.
## `gold` 1: gold hub, nipples and spinner; 2: every third spoke gold as well.
static func wire_wheel(radius: float, width: float, near: bool, gold: int) -> ArrayMesh:
	var key := "ww_%d_%d_%d_%d" % [roundi(radius * 1000.0), roundi(width * 1000.0), int(near), gold]
	if _cache.has(key):
		return _cache[key]
	var seg := 48 if near else 18
	var hw := width * 0.5
	var rim := radius * RIM_RATIO
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The tyre: tread, rounded shoulders, sidewalls with a thin whitewall stripe on the outboard
	# side, beads tucked under the rim's flange. Rows are [x, r, colour, code].
	var side_r := rim + (radius - rim) * 0.42
	var tyre := [
		[-hw * 0.80, rim + 0.012, C_RUBBER, K_RUBBER],
		[-hw * 0.98, rim + (radius - rim) * 0.45, C_RUBBER, K_RUBBER],
		[-hw * 0.94, radius - 0.022, C_RUBBER, K_RUBBER],
		[-hw * 0.74, radius - 0.003, C_RUBBER, K_RUBBER],
		[hw * 0.74, radius - 0.003, C_RUBBER, K_RUBBER],
		[hw * 0.94, radius - 0.022, C_RUBBER, K_RUBBER],
		[hw * 0.985, side_r + 0.034, C_RUBBER, K_RUBBER],
		[hw * 0.99, side_r + 0.026, C_WHITE, K_WHITE],
		[hw * 0.995, side_r + 0.012, C_WHITE, K_WHITE],
		[hw * 0.99, side_r + 0.006, C_RUBBER, K_RUBBER],
		[hw * 0.84, rim + 0.012, C_RUBBER, K_RUBBER],
	]
	_revolve(st, tyre, seg)
	# The rim: the flange lip at the outboard edge, then the chrome dish stepping in to the spoke
	# seat (a reversed rim: the spokes sit deep, the dish is the show), the barrel behind, dark.
	var dish_x := hw * 0.92 - (0.075 if near else 0.06)
	var lip := [
		[hw * 0.84, rim + 0.012, C_CHROME, K_CHROME],
		[hw * 1.00, rim + 0.016, C_CHROME, K_CHROME],
		[hw * 1.04, rim + 0.002, C_CHROME, K_CHROME],
		[hw * 0.98, rim - 0.010, C_CHROME, K_CHROME],
	]
	_revolve(st, lip, seg)
	# The dish: its face looks outboard and in toward the hub.
	var dish := [
		[hw * 0.98, rim - 0.010, C_CHROME, K_CHROME],
		[dish_x + 0.02, rim - 0.016, C_CHROME, K_CHROME],
		[dish_x, rim - 0.020, C_CHROME, K_CHROME],
		[dish_x - 0.004, rim - 0.034, C_CHROME, K_CHROME],
	]
	_revolve(st, dish, seg)
	var barrel := [
		[dish_x - 0.004, rim - 0.034, C_DARK, K_DARK],
		[-hw * 0.84, rim - 0.006, C_DARK, K_DARK],
		[-hw * 0.84, rim + 0.012, C_DARK, K_DARK],
	]
	_revolve(st, barrel, seg)
	# The hub: the outer flange forward, a cone back to the inner flange, the knock-off out front.
	var hub_c := C_GOLD if gold > 0 else C_CHROME
	var hub_k := K_GOLD if gold > 0 else K_CHROME
	var hx_in := -hw * 0.45
	var hx_out := hw * 0.42
	var hub := [
		[hx_in - 0.004, 0.0, C_DARK, K_DARK],
		[hx_in - 0.004, 0.045, hub_c, hub_k],
		[hx_in + 0.006, 0.052, hub_c, hub_k],
		[hx_in + 0.012, 0.040, hub_c, hub_k],
		[hx_out - 0.010, 0.034, hub_c, hub_k],
		[hx_out - 0.004, 0.044, hub_c, hub_k],
		[hx_out + 0.004, 0.044, hub_c, hub_k],
		[hx_out + 0.010, 0.036, hub_c, hub_k],
		[hx_out + 0.030, 0.034, hub_c, hub_k],
		[hx_out + 0.040, 0.026, hub_c, hub_k],
		[hx_out + 0.046, 0.0, hub_c, hub_k],
	]
	_revolve(st, hub, maxi(seg / 2, 12))
	# The knock-off: two flat ears across the face, a little swept back.
	var ko_x := hx_out + 0.036
	for e: float in [0.0, PI]:
		var dirv := Vector3(0.0, cos(e), sin(e))
		var tang := Vector3(0.0, -sin(e), cos(e))
		var a := Vector3(ko_x, 0.0, 0.0) + dirv * 0.02
		var b := Vector3(ko_x - 0.014, 0.0, 0.0) + dirv * 0.105
		_bar(st, a, b, tang, 0.022, 0.012, hub_c, hub_k)
	if near:
		# 72 spokes, three rows: the outer flange laced to the dish's outer edge, the inner flange
		# crossed both ways (a real wire wheel's lacing), each spoke tangent-ish to its flange.
		var nip_x := dish_x - 0.004
		var nip_r := rim - 0.030
		for i in SPOKES:
			var row := i % 3
			var a0 := TAU * float(i) / float(SPOKES)
			var lean := (1.0 if (i / 3) % 2 == 0 else -1.0) * (0.42 + 0.06 * float(row))
			var fx := hx_out - 0.002 if row == 0 else hx_in + 0.004
			var fr := 0.040 if row == 0 else 0.046
			var a1 := a0 + lean
			var p0 := Vector3(fx, fr * cos(a0), fr * sin(a0))
			var p1 := Vector3(nip_x - (0.010 if row == 2 else 0.0), nip_r * cos(a1), nip_r * sin(a1))
			var spoke_gold := gold == 2 and i % 3 == 0
			_spoke(st, p0, p1, 0.0021, C_GOLD if spoke_gold else C_CHROME, K_GOLD if spoke_gold else K_CHROME)
			# The nipple where it enters the rim.
			var nd := (p0 - p1).normalized()
			_spoke(st, p1, p1 + nd * 0.016, 0.0034, hub_c if gold > 0 else C_CHROME, hub_k if gold > 0 else K_CHROME)
	else:
		# Far: a disc where the spokes are, its colour their average against the dark barrel.
		var disc := [
			[hx_out, 0.04, Color(0.42, 0.42, 0.44), K_WHITE],
			[dish_x - 0.004, rim - 0.034, Color(0.42, 0.42, 0.44), K_WHITE],
		]
		_revolve(st, disc, seg, true)
	st.index()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## Revolves a profile about X. Rows [x, r, colour, code]; the winding is chosen so each face
## looks outward from the axle (`inward` for the barrel, seen from inside), the normals per row.
static func _revolve(st: SurfaceTool, prof: Array, seg: int, inward: bool = false) -> void:
	for k in prof.size() - 1:
		var x0 := float(prof[k][0])
		var r0 := float(prof[k][1])
		var x1 := float(prof[k + 1][0])
		var r1 := float(prof[k + 1][1])
		var col: Color = prof[k][2]
		col.a = float(prof[k][3])
		# (axial, radial): the profile step turned a quarter outward.
		var n2 := Vector2(-(r1 - r0), x1 - x0)
		if n2.length_squared() < 1e-12:
			continue
		n2 = n2.normalized()
		if inward:
			n2 = -n2
		for j in seg:
			var a0 := TAU * float(j) / float(seg)
			var a1 := TAU * float(j + 1) / float(seg)
			var p00 := Vector3(x0, r0 * cos(a0), r0 * sin(a0))
			var p10 := Vector3(x1, r1 * cos(a0), r1 * sin(a0))
			var p11 := Vector3(x1, r1 * cos(a1), r1 * sin(a1))
			var p01 := Vector3(x0, r0 * cos(a1), r0 * sin(a1))
			var n0 := Vector3(n2.x, n2.y * cos(a0), n2.y * sin(a0))
			var n1 := Vector3(n2.x, n2.y * cos(a1), n2.y * sin(a1))
			_quad(st, p00, p10, p11, p01, n0, n0, n1, n1, col)


## A quad wound to face along its normals (Godot's front faces wind clockwise).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, col: Color) -> void:
	var order: Array = [[a, na], [b, nb], [c, nc], [a, na], [c, nc], [d, nd]]
	if (b - a).cross(c - a).dot(na + nb + nc + nd) > 0.0:
		order = [[a, na], [d, nd], [c, nc], [a, na], [c, nc], [b, nb]]
	for pair: Array in order:
		st.set_color(col)
		st.set_normal(pair[1])
		st.add_vertex(pair[0])


## A spoke: a three-sided rod from a to b (at 2 mm nobody counts its sides).
static func _spoke(st: SurfaceTool, a: Vector3, b: Vector3, rad: float, c: Color, k: float) -> void:
	var dirv := (b - a).normalized()
	var u := dirv.cross(Vector3.RIGHT)
	if u.length_squared() < 1e-6:
		u = dirv.cross(Vector3.UP)
	u = u.normalized()
	var v := dirv.cross(u).normalized()
	var col := c
	col.a = k
	var sides := [u, (-u * 0.5 + v * 0.866), (-u * 0.5 - v * 0.866)]
	for i in 3:
		var s0: Vector3 = sides[i]
		var s1: Vector3 = sides[(i + 1) % 3]
		_quad(st, a + s0 * rad, b + s0 * rad, b + s1 * rad, a + s1 * rad, s0, s0, s1, s1, col)


## A flat bar (the knock-off's ears): from a to b, `wide` across along `tang`, `thick` along X.
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3, tang: Vector3, wide: float, thick: float, c: Color, k: float) -> void:
	var col := c
	col.a = k
	var t := tang * wide * 0.5
	var x := Vector3(thick * 0.5, 0.0, 0.0)
	var corners := [
		[a - t - x, a + t - x, b + t * 0.6 - x, b - t * 0.6 - x],
		[a - t + x, a + t + x, b + t * 0.6 + x, b - t * 0.6 + x],
	]
	var lo: Array = corners[0]
	var hi: Array = corners[1]
	_quad(st, hi[0], hi[1], hi[2], hi[3], Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, col)
	_quad(st, lo[0], lo[1], lo[2], lo[3], Vector3.LEFT, Vector3.LEFT, Vector3.LEFT, Vector3.LEFT, col)
	for i in 4:
		var p0: Vector3 = lo[i]
		var p1: Vector3 = lo[(i + 1) % 4]
		var q0: Vector3 = hi[i]
		var q1: Vector3 = hi[(i + 1) % 4]
		var mid := (p0 + p1) * 0.5 - (a + b) * 0.5
		mid.x = 0.0
		var n := mid.normalized() if mid.length_squared() > 1e-10 else tang
		_quad(st, p0, p1, q1, q0, n, n, n, n, col)


# --- Hydraulics ----------------------------------------------------------------------------------

## Puts the hydraulics on a lowrider (Vehicle._build()). Off with LOWRIDERS=0 (the car still
## rides laid low).
static func attach(car: Vehicle) -> void:
	var h := Hydraulics.new()
	h.name = "Hydraulics"
	car.add_child(h)


## The pumps and cylinders: each corner's height over its rest (laid out a little under it, up
## to `stroke` over it on the cylinders; past that the wheel under it leaves the road) springs
## toward a target the routine sets; a hop fires the front pair up and gravity brings it down.
## The body model (Vehicle's BodyModel holder) and its night lights are moved to the four
## heights, and a kinematic car's wheels follow a corner that rises past its stroke. Visual only:
## the collision and the physics stay where they were. A physical car (shot out of its row,
## driven) lays the body back at rest and stops.
class Hydraulics extends Node:
	enum Mode { PARKED, SHOW, CRUISE }
	## What it does: PARKED laid out (a car at the meet resting), SHOW (a car at the meet whose
	## driver works the switches: hops, three-wheel, dancing, between rests), CRUISE (in traffic:
	## laid low, a bounce or a three-wheel now and then).
	var mode: int = Mode.CRUISE
	## Seconds between routines (min, max) in SHOW and CRUISE.
	var rest_seconds := Vector2(5.0, 14.0)
	## Cylinder stroke (m over rest), laid-out drop (m under), spring and damping per corner.
	var stroke: float = 0.24
	var laid: float = -0.06
	var spring: float = 210.0
	var damping: float = 15.0
	## Hop launch speeds (m/s) and how many hops in a set.
	var hop_speed := Vector2(2.6, 4.4)
	var hops := Vector2i(3, 7)
	## Past this many metres from the camera nothing moves (the body rests where it is).
	var reach: float = 140.0
	## Holds the pose where it is (stills: a hop at its peak).
	var frozen: bool = false

	var _car: Vehicle
	var _body: Node3D
	var _lights: Node3D
	var _lights_rest := Transform3D.IDENTITY
	var _rng := RandomNumberGenerator.new()
	var _h := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var _v := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var _target := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	## Corners in the air after a hop: gravity only until they come back down past their target.
	var _fly := [false, false, false, false]
	var _routine: String = ""
	var _left: float = 0.0
	var _clock: float = 0.0
	var _hops_left: int = 0
	var _next_hop: float = 0.0
	var _side: float = 1.0
	var _active: bool = false
	var _x := 0.79
	var _zf := -1.44
	var _zr := 1.58
	## Routine counts, for checks: how many hops have gone off and three-wheels been held.
	var hops_done: int = 0
	var three_wheels_done: int = 0

	func _ready() -> void:
		_car = get_parent() as Vehicle
		_rng.seed = hash([_car.look_seed, "hydraulics"])
		_body = _car.get_node_or_null("BodyModel") as Node3D
		_lights = _car.get_node_or_null("NightLights") as Node3D
		if _lights:
			_lights_rest = _lights.transform
		var pose: Dictionary = Vehicle.WHEEL_POSE.get(_car.body_type, {})
		_x = float(pose.get("x", 0.79))
		_zf = float(pose.get("front", -1.44))
		_zr = float(pose.get("rear", 1.58))
		_left = _rng.randf_range(0.5, rest_seconds.y)
		var down := laid if mode != Mode.CRUISE else laid * 0.6
		for i in 4:
			_h[i] = down
			_target[i] = down
		# Stills: LOWRIDER_HYD=routine:seconds[:side] holds every lowrider that far into it.
		var hyd := OS.get_environment("LOWRIDER_HYD").split(":")
		if hyd.size() >= 2:
			perform.call_deferred(hyd[0], hyd[2].to_float() if hyd.size() > 2 else 1.0)
			advance.call_deferred(hyd[1].to_float())
			set_deferred("frozen", true)

	## Starts a routine now ("hop", "three", "dance", "lift", "bounce"): tests and stills.
	func perform(routine: String, side: float = 1.0) -> void:
		_begin(routine)
		_side = side

	func routine() -> String:
		return _routine

	## Each corner's height over its rest (FL, FR, RL, RR), for checks.
	func heights() -> PackedFloat32Array:
		return _h

	func _process(delta: float) -> void:
		if _car == null or _body == null or not Lowrider.enabled or frozen:
			return
		var physical := not _car.is_traffic() and not _car.wheels.is_empty()
		if physical or _car.is_wreck():
			if _active or not _body.transform.is_equal_approx(Transform3D.IDENTITY):
				_reset()
			return
		var cam := get_viewport().get_camera_3d()
		if cam != null and cam.global_position.distance_squared_to(_car.global_position) > reach * reach and _routine == "":
			return
		_active = true
		_step(minf(delta, 0.05))

	## Runs the hydraulics `seconds` on (tools and checks: a still of a hop at its peak).
	func advance(seconds: float) -> void:
		var t := 0.0
		while t < seconds:
			_step(1.0 / 60.0)
			t += 1.0 / 60.0

	func _step(dt: float) -> void:
		_clock += dt
		_tick_routine(dt)
		# Integrate in small steps: a hop is fast and the spring is stiff.
		var steps := ceili(dt / 0.008)
		var h := dt / float(steps)
		for _s in steps:
			for i in 4:
				var a: float
				if _fly[i]:
					a = -9.8
					if _v[i] < 0.0 and _h[i] < _target[i] + 0.05:
						_fly[i] = false
						if _v[i] < -2.0:
							_thud(i)
				else:
					a = spring * (_target[i] - _h[i]) - damping * _v[i]
				_v[i] += a * h
				_h[i] += _v[i] * h
				if _h[i] < laid - 0.03:
					# The bump stops: a slammed corner bounces off them.
					_h[i] = laid - 0.03
					if _v[i] < 0.0:
						if _v[i] < -2.0:
							_thud(i)
						_v[i] = -_v[i] * 0.25
		_apply()

	func _tick_routine(dt: float) -> void:
		_left -= dt
		match _routine:
			"":
				var down := laid if mode != Mode.CRUISE else laid * 0.6
				for i in 4:
					_target[i] = down
				if _left <= 0.0 and mode != Mode.PARKED:
					var r := _rng.randf()
					if mode == Mode.SHOW:
						_begin("hop" if r < 0.45 else ("three" if r < 0.7 else ("dance" if r < 0.9 else "lift")))
					else:
						_begin("bounce" if r < 0.6 else ("three" if r < 0.85 else "lift"))
			"hop":
				for i in 4:
					_target[i] = 0.02 if i < 2 else laid * 0.5
				_next_hop -= dt
				if _next_hop <= 0.0 and _hops_left > 0 and _h[0] < stroke * 0.5 and _v[0] <= 0.5:
					var v := _rng.randf_range(hop_speed.x, hop_speed.y)
					_v[0] = maxf(_v[0], 0.0) + v
					_v[1] = maxf(_v[1], 0.0) + v * _rng.randf_range(0.92, 1.0)
					_fly[0] = true
					_fly[1] = true
					# The rear squats as the nose kicks up.
					_v[2] -= 0.6
					_v[3] -= 0.6
					_hops_left -= 1
					hops_done += 1
					_next_hop = _rng.randf_range(0.9, 1.5)
					_sfx("pump", 0)
				if _hops_left <= 0 and _next_hop <= 0.0:
					_end()
			"three":
				# One front corner high (its wheel off the road), the rear corner across from it
				# dropped, the other two in between: the car stands on three wheels.
				var up := 0 if _side < 0.0 else 1
				var other := 1 - up
				var diag := 3 if up == 0 else 2
				var same := 2 if up == 0 else 3
				var k := smoothstep(0.0, 0.8, minf(_clock, _left))
				_target[up] = lerpf(laid, stroke + 0.20, k)
				_target[other] = lerpf(laid, stroke * 0.55, k)
				_target[same] = lerpf(laid, stroke * 0.35, k)
				_target[diag] = laid
				if _left <= 0.0:
					_end()
			"dance":
				var ph := _clock * TAU * 1.15
				var lr := sin(ph) * stroke * 0.6
				var fb := sin(ph * 0.5 + 0.7) * stroke * 0.4
				var base := stroke * 0.45
				_target[0] = base - lr + fb
				_target[1] = base + lr + fb
				_target[2] = base - lr - fb
				_target[3] = base + lr - fb
				if _left <= 0.0:
					_end()
			"lift":
				var k2 := smoothstep(0.0, 0.6, minf(_clock, _left))
				for i in 4:
					_target[i] = lerpf(laid, stroke * 0.9, k2)
				if _left <= 0.0:
					_end()
			"bounce":
				# Cruising: the front and the back pumping in turn, smaller than a show.
				var ph2 := _clock * TAU * 1.35
				var amp := stroke * 0.38 * smoothstep(0.0, 0.5, minf(_clock, _left))
				for i in 4:
					_target[i] = laid * 0.3 + (amp if (i < 2) == (sin(ph2) > 0.0) else 0.0) * absf(sin(ph2))
				if _left <= 0.0:
					_end()

	func _begin(routine_name: String) -> void:
		_routine = routine_name
		_clock = 0.0
		match routine_name:
			"hop":
				_hops_left = _rng.randi_range(hops.x, hops.y)
				_next_hop = 0.4
				_left = 60.0
			"three":
				_side = 1.0 if _rng.randf() < 0.5 else -1.0
				_left = _rng.randf_range(3.5, 7.0)
				three_wheels_done += 1
				_sfx("pump", 0)
			"dance":
				_left = _rng.randf_range(4.0, 7.0)
			"lift":
				_left = _rng.randf_range(2.0, 4.0)
				_sfx("pump", 0)
			"bounce":
				_left = _rng.randf_range(3.0, 6.0)

	func _end() -> void:
		_routine = ""
		_clock = 0.0
		_left = _rng.randf_range(rest_seconds.x, rest_seconds.y)

	func _reset() -> void:
		_active = false
		_routine = ""
		for i in 4:
			_h[i] = 0.0
			_v[i] = 0.0
			_fly[i] = false
		_body.transform = Transform3D.IDENTITY
		if _lights:
			_lights.transform = _lights_rest
		for rig: Array in _car._wheel_rigs:
			(rig[0] as Node3D).position.y = float(rig[5])

	func _apply() -> void:
		var front := (_h[0] + _h[1]) * 0.5
		var rear := (_h[2] + _h[3]) * 0.5
		var left := (_h[0] + _h[2]) * 0.5
		var right := (_h[1] + _h[3]) * 0.5
		var pitch := atan2(front - rear, _zr - _zf)
		var roll := atan2(right - left, _x * 2.0)
		var heave := (front + rear) * 0.5
		var zc := (_zf + _zr) * 0.5
		var rot := Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
		var xf := Transform3D(Basis(), Vector3(0.0, heave, zc)) * Transform3D(rot, Vector3.ZERO) * Transform3D(Basis(), Vector3(0.0, 0.0, -zc))
		_body.transform = xf
		if _lights:
			_lights.transform = xf * _lights_rest
		# A corner past its stroke takes its wheel off the road with it.
		var rigs: Array = _car._wheel_rigs
		if rigs.size() == 4:
			for i in 4:
				var rig: Array = rigs[i]
				(rig[0] as Node3D).position.y = float(rig[5]) + maxf(_h[i] - stroke, 0.0)

	func _sfx(sound: String, _corner: int) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or cam.global_position.distance_to(_car.global_position) > 60.0:
			return
		var sfx := get_node_or_null("/root/Sfx")
		if sfx:
			sfx.play(sound, _car.global_position, -4.0, _rng.randf_range(0.55, 0.75))

	func _thud(_i: int) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or cam.global_position.distance_to(_car.global_position) > 60.0:
			return
		var sfx := get_node_or_null("/root/Sfx")
		if sfx:
			sfx.play("thud", _car.global_position, -2.0, _rng.randf_range(0.7, 0.9))
