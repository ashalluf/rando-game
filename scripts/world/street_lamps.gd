class_name StreetLamps
extends RefCounted
## The city's street lights as real models (fleet task "street-lamps", 2026-10-05): five Los
## Angeles types built at real size by tools/make_street_lamps.py into
## assets/models/street_lamps.glb, worn by shaders/street_lamp.gdshader (one material, the part in
## UV2), and picked per street by a hash of seed + road + district - never a chunk rng, so no
## roll in the city moves. CityChunk._add_lamp() asks place(); everything else about a lamp - its
## prop slot and id, its pool, its OmniLight3D in "lamp_light", NightCity's sodium / LED roll -
## is what it was, moved to where the lamp's head now is.
##
## Types (TYPES; the model's numbers, checked against its bounds by tests/street_lamps_checks.gd):
##   COBRA   cobra-head on a tapered galvanised pole, arm over the street (8.6 m light)
##   TWIN    downtown's twin-globe ornamental on a fluted cast-iron post (paint per street)
##   LANTERN midtown's single-lantern ornamental on a fluted post (paint per street)
##   POST    residential post-top on a spun-concrete pole
##   MAST    mast-arm LED: tall pole, long straight arm, slim LED head (LED patches only)
## Arms reach along the model's +x; place() turns +x toward the street.

enum Type { COBRA, TWIN, LANTERN, POST, MAST }

const MODEL := "res://assets/models/street_lamps.glb"
## Per type: the model's node, its light points in the model's frame (x along the arm, y up), the
## collision box round the pole (size), the pool's diameter and the omni light's reach.
const TYPES := [
	{"node": "sl_cobra", "lights": [Vector2(2.54, 8.60)], "box": Vector3(0.34, 8.44, 0.34), "pool": 17.0, "range": 16.0},
	{"node": "sl_twin", "lights": [Vector2(-0.62, 4.96), Vector2(0.62, 4.96)], "box": Vector3(0.6, 4.8, 0.6), "pool": 13.0, "range": 11.0},
	{"node": "sl_lantern", "lights": [Vector2(0.0, 4.32)], "box": Vector3(0.46, 4.6, 0.46), "pool": 11.5, "range": 10.0},
	{"node": "sl_post", "lights": [Vector2(0.0, 4.65)], "box": Vector3(0.3, 4.8, 0.3), "pool": 11.0, "range": 10.0},
	{"node": "sl_mast", "lights": [Vector2(3.36, 9.12)], "box": Vector3(0.38, 9.45, 0.38), "pool": 19.0, "range": 17.0},
]
## The model's height per type (top of the tallest part), for the checks.
const HEIGHTS := [8.91, 5.37, 5.19, 5.07, 9.45]
## Cast-iron paints (sRGB): the ornamentals take one per street.
const TWIN_PAINTS := [Color(0.13, 0.15, 0.13), Color(0.19, 0.17, 0.13), Color(0.1, 0.13, 0.12), Color(0.15, 0.16, 0.17)]
const LANTERN_PAINTS := [Color(0.07, 0.075, 0.08), Color(0.09, 0.15, 0.12), Color(0.2, 0.19, 0.16), Color(0.06, 0.08, 0.12)]
## A street "wide" enough for the tall lamps: within this of the plan's avenue width.
const AVENUE_SLACK := 2.0

## Off: every lamp is the old Poly Haven post again (the A/B, `STREET_LAMPS=0` in the environment).
static var enabled: bool = OS.get_environment("STREET_LAMPS") != "0"

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/street_lamp.gdshader")
	return _material


## One lamp type's mesh, with its LODs and shadow twin (PropFactory.model_mesh(): TRI_BUDGET keyed
## "street_lamps.glb:<node>").
static func mesh(t: int) -> Mesh:
	if _meshes.has(t):
		return _meshes[t]
	var m := PropFactory.model_mesh(MODEL, PackedStringArray([TYPES[t].node]))
	for s in m.get_surface_count():
		m.surface_set_material(s, material())
	var twin := PropFactory.shadow_proxy(m)
	if twin:
		for s in twin.get_surface_count():
			twin.surface_set_material(s, material())
	_meshes[t] = m
	return m


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## The street a lamp at `at` (TRUE world XZ) faces: `facing` is the unit direction from the lamp
## to the street, ZERO when it stands in a park, plaza or car park. Returns [axis, road index] or
## [] for no street.
static func street_of(plan: CityPlan, at: Vector2, facing: Vector2) -> Array:
	if facing == Vector2.ZERO or plan == null:
		return []
	# A street along x lies across z: its road is one of the AXIS_Z roads.
	var axis := CityPlan.AXIS_Z if absf(facing.y) > absf(facing.x) else CityPlan.AXIS_X
	var coord := at.y if axis == CityPlan.AXIS_Z else at.x
	return [axis, plan._nearest_road(axis, coord)]


## Which lamp stands at `at`: by district, by the street (both its sides and its whole length in
## a district alike) and by NightCity's LED roll (a mast-arm LED only where the patch is LED).
static func pick(plan: CityPlan, at: Vector2, facing: Vector2) -> int:
	var district := plan.district_at(at) if plan else CityPlan.District.MIDTOWN
	var led := NightCity.lamp_led(at)
	var street := street_of(plan, at, facing)
	if street.is_empty():
		# Parks, plazas, car parks: the ornamental of the district, else the post-top.
		match district:
			CityPlan.District.DOWNTOWN:
				return Type.TWIN
			CityPlan.District.MIDTOWN, CityPlan.District.CAMPUS:
				return Type.LANTERN
			CityPlan.District.INDUSTRIAL:
				return Type.MAST if led else Type.COBRA
			_:
				return Type.POST
	var seed := plan.seed if plan else 0
	var h := h01([seed, street[0], street[1], district, "lamp"])
	var wide := plan.road_width(street[0], street[1]) >= plan.avenue_width - AVENUE_SLACK
	match district:
		CityPlan.District.DOWNTOWN:
			if h < 0.78:
				return Type.TWIN
			return Type.MAST if led and wide else Type.COBRA
		CityPlan.District.MIDTOWN:
			if wide:
				return Type.MAST if led and h < 0.6 else Type.COBRA
			if h < 0.55:
				return Type.LANTERN
			return Type.COBRA
		CityPlan.District.CAMPUS:
			return Type.LANTERN if h < 0.6 else Type.POST
		CityPlan.District.INDUSTRIAL:
			return Type.MAST if led and h < 0.5 else Type.COBRA
		_:
			# Suburbs and the beach town: post-tops on the side streets, cobras on the big ones.
			if wide:
				return Type.MAST if led and h < 0.35 else Type.COBRA
			return Type.POST if h < 0.65 else Type.COBRA


## A car park's light pole: the tall arm types, the arm turned by the old hashed yaw.
static func car_park_type(at: Vector2) -> int:
	return Type.MAST if NightCity.lamp_led(at) else Type.COBRA


## The instance colour: the paint of a cast-iron type, per street.
static func paint(plan: CityPlan, t: int, at: Vector2, facing: Vector2) -> Color:
	var street := street_of(plan, at, facing)
	var seed := plan.seed if plan else 0
	var h := h01([seed, street, "lamp_paint"])
	if t == Type.TWIN:
		return TWIN_PAINTS[int(h * TWIN_PAINTS.size()) % TWIN_PAINTS.size()]
	if t == Type.LANTERN:
		return LANTERN_PAINTS[int(h * LANTERN_PAINTS.size()) % LANTERN_PAINTS.size()]
	return Color.WHITE


## The yaw that turns the model's +x toward `facing`; a lamp with no street gets the hashed yaw
## the old post had.
static func basis_for(at: Vector2, facing: Vector2) -> Basis:
	if facing == Vector2.ZERO:
		return Basis(Vector3.UP, fmod(absf(at.x * 7.3 + at.y * 3.1), TAU))
	return Basis(Vector3.UP, atan2(-facing.y, facing.x))


## Everything CityChunk._add_lamp() needs to place one lamp: the batch key and mesh, its
## transform, paint and instance custom (LED flag, wear), the light points in the CHUNK's frame
## (true world, pavement-relative y), the pool's diameter, the omni's reach and the collision box.
## `force` >= 0 is the type to use whatever the street (a car park's light poles).
static func place(plan: CityPlan, at: Vector3, facing: Vector2, force: int = -1) -> Dictionary:
	var at2 := Vector2(at.x, at.z)
	var t := force if force >= 0 else pick(plan, at2, facing)
	var spec: Dictionary = TYPES[t]
	var b := basis_for(at2, facing)
	var lights: Array[Vector3] = []
	for l: Vector2 in spec.lights:
		lights.append(at + b * Vector3(l.x, l.y, 0.0))
	var seed := plan.seed if plan else 0
	var box: Vector3 = spec.box
	return {
		"type": t,
		"key": "lamp_" + str(spec.node).trim_prefix("sl_"),
		"mesh": mesh(t),
		"xform": Transform3D(b, at),
		"paint": paint(plan, t, at2, facing),
		"custom": Color(1.0 if NightCity.lamp_led(at2) else 0.0, h01([seed, at2.snapped(Vector2(0.1, 0.1)), "lamp_age"]), 0.0, 0.0),
		"lights": lights,
		"pool": float(spec.pool),
		"range": float(spec.range),
		"box": box,
	}
