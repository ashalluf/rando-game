class_name CarInterior
extends Node3D
## A car's real cabin and doors, while it has them (CarInteriors decides: the car the player drives,
## parked cars he stands by, a car that has lost a door). A child of the car's near body mesh, so it
## works in the body MESH's space like everything CarCabin measures:
##   * the body mesh is swapped for CarDoorSplit's copy without its front doors, and each door is a
##     DoorL / DoorR pivot on its hinge holding the door's skin, glass and handle (the body's own
##     surface materials - the paint with its damage, the glass - kept in step every tick) and its
##     card (CarInteriorKit);
##   * the cabin (CarInteriorKit) - dash, seats, console, carpet, headliner, the quarter trims and the
##     painted jambs - and the steering wheel, which turns with the car's steering;
##   * the glass becomes car_glass_open.gdshader (transparent, the people still traced on it),
##     through Vehicle.cabin_glass_override.
## The body's shadow twins carry the closed doors, so while this is up the body and the doors cast
## their own shadows instead. remove() puts everything back the way the car had it.

const INTERIOR_SHADER := preload("res://shaders/car_interior.gdshader")
const GLASS_OPEN_SHADER := preload("res://shaders/car_glass_open.gdshader")

## How far a door swings open (degrees), and how fast it opens and closes (of the swing a second).
const OPEN_DEG := 66.0
const OPEN_SPEED := 2.6
const CLOSE_SPEED := 3.4
## How long a door stands open when somebody gets in or out (s).
const HOLD := 0.45
## Steering wheel turns per radian of road-wheel steer (a 15:1 rack: 0.5 rad is ~430 degrees).
const STEER_RATIO := 15.0
## A door torn off flies at this (m/s) out of the side, and is debris for this long (s).
const DOOR_FLING := 7.0
const DOOR_LIFE := 90.0

## Interior colour schemes: seat, insert, dash, plastic, carpet, headliner (linear) and leather.
const SCHEMES := [
	{"name": "charcoal cloth", "seat": Vector3(0.028, 0.028, 0.03), "insert": Vector3(0.04, 0.04, 0.043), "dash": Vector3(0.02, 0.02, 0.022), "plastic": Vector3(0.026, 0.026, 0.028), "carpet": Vector3(0.016, 0.016, 0.018), "headliner": Vector3(0.22, 0.21, 0.2), "leather": 0.0},
	{"name": "black leather", "seat": Vector3(0.018, 0.017, 0.017), "insert": Vector3(0.022, 0.021, 0.021), "dash": Vector3(0.018, 0.018, 0.02), "plastic": Vector3(0.024, 0.024, 0.026), "carpet": Vector3(0.014, 0.014, 0.016), "headliner": Vector3(0.05, 0.05, 0.052), "leather": 1.0},
	{"name": "grey leather", "seat": Vector3(0.18, 0.18, 0.18), "insert": Vector3(0.14, 0.14, 0.145), "dash": Vector3(0.03, 0.03, 0.032), "plastic": Vector3(0.05, 0.05, 0.052), "carpet": Vector3(0.03, 0.03, 0.032), "headliner": Vector3(0.36, 0.35, 0.33), "leather": 1.0},
	{"name": "tan leather", "seat": Vector3(0.36, 0.2, 0.09), "insert": Vector3(0.3, 0.165, 0.075), "dash": Vector3(0.025, 0.022, 0.02), "plastic": Vector3(0.035, 0.03, 0.026), "carpet": Vector3(0.03, 0.022, 0.016), "headliner": Vector3(0.4, 0.37, 0.32), "leather": 1.0},
	{"name": "oxblood leather", "seat": Vector3(0.16, 0.025, 0.02), "insert": Vector3(0.12, 0.02, 0.017), "dash": Vector3(0.02, 0.018, 0.018), "plastic": Vector3(0.026, 0.024, 0.024), "carpet": Vector3(0.016, 0.014, 0.014), "headliner": Vector3(0.06, 0.055, 0.052), "leather": 1.0},
]
## Cumulative odds of the schemes (most cars are dark inside).
const SCHEME_ODDS := [0.32, 0.62, 0.8, 0.93, 1.0]

var car: Vehicle
var body_mi: MeshInstance3D
var scheme: int = 0
## Per door: {"side", "data", "pivot", "mesh", "card", "open", "target", "hold", "lost"}.
var doors: Array = []
var wheel: Node3D
var cabin: MeshInstance3D
var _orig_mesh: Mesh
var _orig_cast: int = 0
var _mat: ShaderMaterial
var _glass: ShaderMaterial
var _wheel_xf: Transform3D
var _real := false
var _powered := -1.0
## Lights the dash with nobody at the wheel (stills).
var force_powered := false
## A door has come off: the shadow twin shows the hole, the doors left cast their own.
var _holed := false


## Builds it on `c` (CarDoorSplit's result for its body type must be ready). Null when the car
## has no near body mesh to build on.
static func make(c: Vehicle, split: Dictionary, kit: Dictionary) -> CarInterior:
	var mi: MeshInstance3D = null
	for m in c._body_meshes:
		if is_instance_valid(m) and m.mesh != null and not String(m.name).ends_with("_far") \
				and not String(m.name).begins_with("door_") and not String(m.name).begins_with("rig_"):
			mi = m
			break
	if mi == null:
		return null
	var ci := CarInterior.new()
	ci.name = "CarInterior"
	ci.car = c
	ci.body_mi = mi
	ci._setup(split, kit)
	mi.add_child(ci)
	return ci


## The scheme a car gets: a hash of what it looks like, so the same parked car is the same inside.
static func scheme_for(c: Vehicle) -> int:
	var r := float(absi(hash([c.body_type, c.paint, c.look_seed, c.wheel_style, "interior"])) % 1000) / 1000.0
	for i in SCHEME_ODDS.size():
		if r < float(SCHEME_ODDS[i]):
			return i
	return 0


## The doors this car's rig is built with: the split's, or stand-ins without mesh data.
static func doors_for(c: Vehicle, split: Dictionary) -> Array:
	if bool(split.get("real", false)) and split.get("body") != null:
		return split.doors
	return _stand_in_doors(CarCabin.for_car(c))


func _setup(split: Dictionary, kit: Dictionary) -> void:
	var data := CarCabin.for_car(car)
	_real = bool(split.get("real", false)) and split.get("body") != null
	scheme = scheme_for(car)
	_mat = ShaderMaterial.new()
	_mat.shader = INTERIOR_SHADER
	var sc: Dictionary = SCHEMES[scheme]
	for k in ["seat", "insert", "dash", "plastic", "carpet", "headliner"]:
		_mat.set_shader_parameter(k + "_col", sc[k])
	_mat.set_shader_parameter("leather", sc.leather)
	var p := car.paint.srgb_to_linear()
	_mat.set_shader_parameter("jamb_col", Vector3(p.r, p.g, p.b))
	var door_data: Array = split.doors if _real else _stand_in_doors(data)
	cabin = MeshInstance3D.new()
	cabin.name = "Cabin"
	cabin.mesh = kit.cabin
	cabin.material_override = _mat
	cabin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cabin)
	_wheel_xf = kit.wheel_xf
	wheel = MeshInstance3D.new()
	wheel.name = "SteeringWheel"
	(wheel as MeshInstance3D).mesh = kit.wheel
	(wheel as MeshInstance3D).material_override = _mat
	(wheel as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wheel.transform = _wheel_xf
	add_child(wheel)
	if _real:
		_orig_mesh = body_mi.mesh
		_orig_cast = body_mi.cast_shadow
		body_mi.mesh = split.body
	for i in door_data.size():
		var d: Dictionary = door_data[i]
		var pivot := Node3D.new()
		pivot.name = "DoorL" if float(d.side) < 0.0 else "DoorR"
		pivot.position = d.hinge
		add_child(pivot)
		var door_mi: MeshInstance3D = null
		if _real:
			door_mi = MeshInstance3D.new()
			door_mi.name = "Skin"
			door_mi.mesh = d.mesh
			door_mi.position = -(d.hinge as Vector3)
			pivot.add_child(door_mi)
		var card := MeshInstance3D.new()
		card.name = "Card"
		card.mesh = kit.cards[i]
		card.material_override = _mat
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		card.position = -(d.hinge as Vector3)
		pivot.add_child(card)
		doors.append({"side": float(d.side), "data": d, "pivot": pivot, "mesh": door_mi, "card": card,
			"open": 0.0, "target": 0.0, "hold": 0.0, "lost": false})
	_set_far(body_mi.visibility_range_end)
	# The glass: transparent, the people still traced on it.
	_glass = ShaderMaterial.new()
	_glass.shader = GLASS_OPEN_SHADER
	CarCabin.apply(_glass, data)
	car.cabin_glass_override = _glass
	car._update_occupant(true)
	_shadows(true)
	sync()


## Doors where the headless check has no mesh to split: hinges from the outline table, the skin
## just outside the measured cabin.
static func _stand_in_doors(data: Dictionary) -> Array:
	var out := []
	var hi: Vector3 = data.cabin_hi
	var lo: Vector3 = data.cabin_lo
	var belt: float = data.belt_y
	for s: float in [-1.0, 1.0]:
		var skin := (hi.x - lo.x) * 0.5 + 0.13
		out.append({"side": s, "hinge": Vector3(s * skin, belt - 0.3, lo.z + 0.6), "skin_x": skin,
			"front": -(lo.z + 0.6), "rear": -(lo.z + 1.6), "sill": belt - 0.6, "belt": belt, "top": float(data.side_top),
			"lower": PackedVector2Array([Vector2(-(lo.z + 0.6), belt), Vector2(-(lo.z + 0.6), belt - 0.6),
				Vector2(-(lo.z + 1.6), belt - 0.6), Vector2(-(lo.z + 1.6), belt)])})
	return out


func _set_far(end: float) -> void:
	for gi: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		gi.visibility_range_end = end


## Shadows: the body keeps its light shadow twin (it has the doors shut, which is the door's shadow
## too while it is shut); a door casts its own only while it stands open. Casting the split body
## at full detail into every cascade cost ~100k triangles a frame.
func _shadows(_on: bool) -> void:
	for d: Dictionary in doors:
		if not d.lost and d.mesh != null and is_instance_valid(d.mesh):
			(d.mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Takes it all back off the car. A car that has lost a door is never handed back (CarInteriors
## keeps it), since the body it would go back to has the door.
func remove() -> void:
	if OS.get_environment("CABIN_DEBUG") != "":
		print("CABIN remove %s (car valid %s)" % [name, car != null and is_instance_valid(car)])
		print_stack()
	if car != null and is_instance_valid(car):
		if car.cabin_glass_override == _glass:
			car.cabin_glass_override = null
			car._update_occupant(true)
		_shadows(false)
	if _orig_mesh != null and body_mi != null and is_instance_valid(body_mi):
		var split := body_mi.mesh
		body_mi.cast_shadow = _orig_cast as GeometryInstance3D.ShadowCastingSetting
		body_mi.mesh = _orig_mesh
		# A shadow twin made while this was up was made from the split body: give it the whole one.
		if car != null and is_instance_valid(car):
			for twin in car._body_shadows:
				if is_instance_valid(twin) and twin.mesh == split:
					twin.mesh = _orig_mesh
	queue_free()


func has_lost_door() -> bool:
	for d: Dictionary in doors:
		if d.lost:
			return true
	return false


func busy() -> bool:
	for d: Dictionary in doors:
		if not d.lost and (float(d.open) > 0.001 or float(d.target) > 0.0):
			return true
	return false


## The door on `side` (-1 left, +1 right) of the mesh, or {}.
func door(side: float) -> Dictionary:
	for d: Dictionary in doors:
		if signf(float(d.side)) == signf(side):
			return d
	return {}


## Opens the door on `side`, holds it, closes it (somebody getting in or out).
func swing(side: float) -> void:
	var d := door(side)
	if d.is_empty() or d.lost:
		return
	d.target = 1.0
	d.hold = HOLD


## The door's swing now (0 shut .. 1 wide open).
func door_open(side: float) -> float:
	var d := door(side)
	return 0.0 if d.is_empty() else float(d.open)


func tick(delta: float) -> void:
	for d: Dictionary in doors:
		if d.lost:
			continue
		var o: float = d.open
		var tgt: float = d.target
		if tgt > 0.0 and o >= 0.999:
			d.hold = float(d.hold) - delta
			if float(d.hold) <= 0.0:
				d.target = 0.0
		o = move_toward(o, float(d.target), delta * (OPEN_SPEED if float(d.target) > o else CLOSE_SPEED))
		d.open = o
		# Out fast and easing to the check strap; shut with a little speed at the end.
		var e := 1.0 - pow(1.0 - o, 2.2) if float(d.target) > 0.0 else o * o * (3.0 - 2.0 * o)
		(d.pivot as Node3D).rotation = Vector3(0.0, deg_to_rad(OPEN_DEG) * e * float(d.side), 0.0)
		var skin: MeshInstance3D = d.mesh if d.mesh != null and is_instance_valid(d.mesh) else null
		if skin != null:
			var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if o > 0.02 or _holed else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if skin.cast_shadow != cast:
				skin.cast_shadow = cast
	if _real and car != null and _orig_mesh != null:
		# The shadow twin carries whole doors (a twin made while this was up gets them back), or
		# the hole once one is gone.
		var want: Mesh = body_mi.mesh if _holed else _orig_mesh
		for twin in car._body_shadows:
			if is_instance_valid(twin) and twin.mesh != want:
				twin.mesh = want
	if wheel != null and car != null:
		wheel.transform = Transform3D(_wheel_xf.basis * Basis(Vector3(0, 0, 1), -car.steering * STEER_RATIO), _wheel_xf.origin)
	var powered := 1.0 if car != null and (car.driver != null or force_powered) else 0.0
	if powered != _powered:
		_powered = powered
		_mat.set_shader_parameter("powered", powered)
	sync()


## The doors' skins wear what the body's surfaces wear now (the damage's paint, the glass).
func sync() -> void:
	if not _real or body_mi == null or not is_instance_valid(body_mi):
		return
	for d: Dictionary in doors:
		if d.lost or d.mesh == null or not is_instance_valid(d.mesh):
			continue
		var m: MeshInstance3D = d.mesh
		var map: PackedInt32Array = d.data.surf_map
		for k in map.size():
			var want := body_mi.get_surface_override_material(map[k])
			if m.get_surface_override_material(k) != want:
				m.set_surface_override_material(k, want)


## Tears the door on `side` off and throws it along `push` (world): a debris body with the door's
## skin and card on it. The hole stays (the car keeps this rig).
func detach(side: float, push: Vector3) -> RigidBody3D:
	var d := door(side)
	if d.is_empty() or d.lost:
		return null
	d.lost = true
	_holed = true
	var pivot: Node3D = d.pivot
	var xf := pivot.global_transform
	var body := RigidBody3D.new()
	body.name = "LostDoor"
	body.collision_layer = 4
	body.collision_mask = 5
	body.mass = 28.0
	var data: Dictionary = d.data
	var box := BoxShape3D.new()
	var length := absf(float(data.front) - float(data.rear))
	var height := absf(float(data.top) - float(data.sill))
	box.size = Vector3(0.12, maxf(height, 0.4), maxf(length, 0.5))
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, (float(data.sill) + float(data.top)) * 0.5, -(float(data.front) + float(data.rear)) * 0.5) - (data.hinge as Vector3)
	body.add_child(shape)
	for part: Variant in [d.mesh, d.card]:
		if part != null and is_instance_valid(part):
			(part as Node).reparent(body, false)
	var root := car.get_parent() if car.get_parent() != null else car.get_tree().root
	root.add_child(body, true)
	# It starts inside its car's collision box: never against that car (the depenetration threw
	# both, and a wreck came to rest on its own door).
	body.add_collision_exception_with(car)
	car.add_collision_exception_with(body)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	pivot.queue_free()
	var out := car.global_basis.x * float(d.side)
	body.linear_velocity = car.linear_velocity + out * DOOR_FLING + push + Vector3.UP * 2.5
	body.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-6, 6), randf_range(-4, 4))
	var pb := car.get_tree().root.get_node_or_null("/root/PhysicsBudget")
	if pb != null:
		pb.register_debris(body, DOOR_LIFE)
	return body
