class_name ServiceVehicles
extends RefCounted
## The city's working vehicles: the side-loader garbage truck, the street sweeper, the rollback
## tow truck, the ice-cream truck and the delivery van. Their bodies are Blender-built by
## tools/make_service_vehicles.py on the big vehicles' pipeline (the van is the road van) and they
## ARE Vehicles (BodyType GARBAGE_TRUCK ... DELIVERY_VAN, BODY_ODDS 0, BigVehicles.is_big()): kinematic
## in traffic, go_physical() when hit, CarDamage, CarCabin glass and a driver, CarLights, the pools.
## What is theirs lives here:
##   * the look: make() picks the livery - every department, company and brand name is INVENTED;
##   * their moving parts, posed with no bones (the model's `rig_*` nodes, each origin on its
##     pivot): the garbage truck's arm (GarbageArm: the boom slides out, the lift swings a cart up
##     and over the hopper and back), the sweeper's brooms (SweeperGear, with its water spray and
##     dust), the tow truck's bed (TowBed: slides back and tilts, ServiceFleet winches a wreck on);
##   * the amber beacons (shaders/service_beacon.gdshader), the ice-cream truck's menu boards and
##     awning (shaders/ice_cream_menu.gdshader) and its chime (IceCreamGear, ServiceSounds).
## ServiceFleet decides where they work; TrafficManager drives them (its `work` hook).

const GARBAGE := Vehicle.BodyType.GARBAGE_TRUCK
const SWEEPER := Vehicle.BodyType.STREET_SWEEPER
const TOW := Vehicle.BodyType.TOW_TRUCK
const ICE_CREAM := Vehicle.BodyType.ICE_CREAM_TRUCK
const DELIVERY := Vehicle.BodyType.DELIVERY_VAN
const TYPES := [GARBAGE, SWEEPER, TOW, ICE_CREAM, DELIVERY]

## Mass relative to a car (BigVehicles.tune()): a laden refuse truck ~11 t, a sweeper 8, a
## rollback 8, the ice-cream truck 5, a loaded van 3.
const MASS := {GARBAGE: 9.0, SWEEPER: 7.0, TOW: 7.0, ICE_CREAM: 4.0, DELIVERY: 2.4}

## Vehicle._dims() for each (tools/make_service_vehicles.py prints the lengths, axles and ride;
## the box truck's physics numbers on its chassis, the ambulance's on the cutaway, the van's).
const DIMS := {
	GARBAGE: {"length": 8.906, "width": 2.50, "lamp_y": 0.89, "tail_y": 1.39, "chassis_h": 1.0, "cabin": Vector2(-4.4, 8.8), "cabin_h": 1.4, "wheel_z": 2.9, "wheel_front": 3.377, "wheel_rear": 2.423, "track": 1.72, "tyre_r": 0.424, "ride": -0.236, "road": -0.260,
			"light_len": 8.80, "light_z": 0.06, "letter_at": Vector3(1.252, 2.10, 1.85), "letter_size": 0.24},
	SWEEPER: {"length": 8.776, "width": 2.45, "lamp_y": 0.89, "tail_y": 1.23, "chassis_h": 1.0, "cabin": Vector2(-4.4, 8.8), "cabin_h": 1.4, "wheel_z": 2.9, "wheel_front": 3.312, "wheel_rear": 2.488, "track": 1.72, "tyre_r": 0.424, "ride": -0.259, "road": -0.260,
			"light_len": 8.70, "light_z": 0.10, "letter_at": Vector3(1.214, 2.00, 0.49), "letter_size": 0.26},
	TOW: {"length": 9.316, "width": 2.44, "lamp_y": 0.89, "tail_y": 0.92, "chassis_h": 1.0, "cabin": Vector2(-4.4, 8.8), "cabin_h": 1.2, "wheel_z": 2.9, "wheel_front": 3.699, "wheel_rear": 2.101, "track": 1.72, "tyre_r": 0.424, "ride": -0.236, "road": -0.260,
			"light_len": 9.50, "light_z": 0.105, "letter_at": Vector3(1.212, 0.56, -1.06), "letter_size": 0.13},
	ICE_CREAM: {"length": 6.724, "width": 2.40, "lamp_y": 0.595, "tail_y": 0.99, "chassis_h": 0.9, "cabin": Vector2(-3.4, 6.7), "cabin_h": 1.3, "wheel_z": 2.0, "wheel_front": 2.488, "wheel_rear": 1.532, "track": 1.74, "tyre_r": 0.35, "ride": -0.199, "road": -0.220,
			"letter_at": Vector3(1.19, 2.33, 1.31), "letter_size": 0.22},
	DELIVERY: {"length": 5.944, "width": 2.03, "lamp_y": 0.674, "tail_y": 0.864, "chassis_h": 0.8, "cabin": Vector2(-2.0, 4.4), "cabin_h": 1.2, "wheel_z": 1.65, "wheel_front": 1.95, "wheel_rear": 1.67, "track": 1.70, "tyre_r": 0.36, "ride": -0.176, "road": -0.196,
			"letter_at": Vector3(1.045, 1.25, 0.70), "letter_size": 0.22},
}

## Liveries: [name on the side, paint, trim]. Invented, none real.
const SANITATION := ["RANDO CITY SANITATION", Color(0.93, 0.93, 0.91), Color(0.08, 0.36, 0.20)]
const STREETS := ["RANDO CITY STREETS", Color(0.93, 0.93, 0.91), Color(0.06, 0.22, 0.50)]
const TOW_FLEETS := [
	["RAPID HOOK TOWING", Color(0.62, 0.05, 0.04), Color(0.95, 0.95, 0.93)],
	["NIGHT OWL RECOVERY", Color(0.05, 0.05, 0.06), Color(0.95, 0.72, 0.08)],
	["GOLD COAST TOW", Color(0.93, 0.70, 0.08), Color(0.06, 0.06, 0.07)],
	["BASIN AUTO RESCUE", Color(0.92, 0.92, 0.90), Color(0.10, 0.25, 0.60)],
]
const ICE_CREAM_FLEETS := [
	["FROSTLINE TREATS", Color(0.95, 0.95, 0.93), Color(0.88, 0.32, 0.52)],
	["PALETA PARADISE", Color(0.95, 0.95, 0.93), Color(0.04, 0.55, 0.58)],
	["SNOWCAP SWEETS", Color(0.97, 0.92, 0.80), Color(0.12, 0.30, 0.70)],
]
const DELIVERY_FLEETS := [
	["PARCELWAY", Color(0.94, 0.94, 0.93), Color(0.95, 0.45, 0.05)],
	["SWIFTBOX", Color(0.14, 0.16, 0.20), Color(0.55, 0.80, 0.10)],
	["DOORSTEP EXPRESS", Color(0.94, 0.94, 0.93), Color(0.10, 0.30, 0.75)],
	["ZIPCRATE", Color(0.80, 0.10, 0.10), Color(0.95, 0.95, 0.93)],
]
## Where the livery band sits on each body (fraction of the model's height, width).
const BAND := {GARBAGE: [0.36, 0.05], SWEEPER: [0.42, 0.04]}

## The garbage arm: the body-space z of the grab point (ahead of the origin), the lift lever's
## reach from its pivot to the middle of the cart it holds (along the lever, out from it), the
## boom's travel.
const ARM_AHEAD := 1.237
const BIN_DOWN := 2.02
const BIN_OUT := 0.69
const MAX_EXT := 2.6

static var _beacon_mats: Dictionary = {}
static var _menu_mats: Dictionary = {}
static var _bin_mats: Dictionary = {}


static func is_service(type: int) -> bool:
	return type in TYPES


## A service vehicle of `type`, its livery rolled from `look` (any int). Not in the tree yet.
static func make(type: int, look: int) -> Vehicle:
	var car := Vehicle.new()
	var f: Array
	var livery := Vehicle.Livery.NONE
	match type:
		GARBAGE:
			f = SANITATION
			livery = Vehicle.Livery.SERVICE
		SWEEPER:
			f = STREETS
			livery = Vehicle.Livery.SERVICE
		TOW:
			f = TOW_FLEETS[absi(hash([look, 1])) % TOW_FLEETS.size()]
		ICE_CREAM:
			f = ICE_CREAM_FLEETS[absi(hash([look, 2])) % ICE_CREAM_FLEETS.size()]
			livery = Vehicle.Livery.TWO_TONE
		_:
			f = DELIVERY_FLEETS[absi(hash([look, 3])) % DELIVERY_FLEETS.size()]
			livery = Vehicle.Livery.DELIVERY
	car.setup(type, f[1], Vehicle.Addon.NONE)
	car.setup_look(Vehicle.Finish.GLOSS, livery, f[2])
	car.wheel_style = 0
	car.wheel_kit = 1
	car.set_meta("fleet", f[0])
	car.set_meta("fleet_no", 100 + absi(hash([look, 4])) % 8900)
	car.set_meta("look", look)
	return car


## After the body model is placed (BigVehicles.fit): the beacons', menus' and awning's materials,
## the band, and the gear that moves the `rigs` (the model's rig_* MeshInstance3Ds).
static func fit(car: Vehicle, holder: Node3D, rigs: Array) -> void:
	var by_name := {}
	for m in rigs:
		by_name[String((m as Node).name)] = m
	_materials(car)
	var gear: Gear = null
	match car.body_type:
		GARBAGE:
			gear = GarbageArm.new()
		SWEEPER:
			gear = SweeperGear.new()
		TOW:
			gear = TowBed.new()
		ICE_CREAM:
			gear = IceCreamGear.new()
	if gear != null:
		gear.name = "ServiceGear"
		car.add_child(gear)
		gear.setup(car, holder, by_name)


## The gear a service vehicle carries (null for the van).
static func gear_of(car: Node) -> Gear:
	if car == null or not is_instance_valid(car):
		return null
	return car.get_node_or_null("ServiceGear") as Gear


static func _materials(car: Vehicle) -> void:
	var accent: Color = car.trim_color
	for m in car._body_meshes:
		if not is_instance_valid(m) or m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			if src == null:
				continue
			var nm := String(src.resource_name)
			if nm.begins_with("beacon_amber"):
				m.set_surface_override_material(si, beacon_material(car.body_type == ICE_CREAM))
			elif nm.begins_with("menu"):
				m.set_surface_override_material(si, menu_material(accent, 0))
			elif nm.begins_with("canvas"):
				m.set_surface_override_material(si, menu_material(accent, 1))
			elif nm.begins_with("paint") and BAND.has(car.body_type):
				var pm := m.get_surface_override_material(si) as ShaderMaterial
				if pm != null:
					var b: Array = BAND[car.body_type]
					pm.set_shader_parameter("stripe_height", b[0])
					pm.set_shader_parameter("stripe_width", b[1])


## The amber lenses: `idle` true gives the ice-cream truck's pair, which ServiceFleet lights only
## while it stands (IceCreamGear swaps the shared materials, never a per-car copy).
static func beacon_material(idle: bool) -> ShaderMaterial:
	var key := 1 if idle else 0
	if not _beacon_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/service_beacon.gdshader")
		m.set_shader_parameter("active", 0.0 if idle else 1.0)
		_beacon_mats[key] = m
	return _beacon_mats[key]


static func beacon_on_material() -> ShaderMaterial:
	return beacon_material(false)


## The ice-cream truck's menu boards (`mode` 0) and striped awning (1), in its accent colour.
static func menu_material(accent: Color, mode: int) -> ShaderMaterial:
	var key := "%s|%d" % [accent.to_html(), mode]
	if not _menu_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/ice_cream_menu.gdshader")
		m.set_shader_parameter("accent", Vector3(accent.r, accent.g, accent.b))
		m.set_shader_parameter("mode", mode)
		_menu_mats[key] = m
	return _menu_mats[key]


## A carried cart's material: the kerb carts' shader with its colour fixed (raw sRGB, like the
## kerb batch's instance colours).
static func bin_material(color_index: int) -> ShaderMaterial:
	if not _bin_mats.has(color_index):
		var m := KerbBins.material().duplicate() as ShaderMaterial
		var c: Color = KerbBins.COLORS[color_index]
		m.set_shader_parameter("use_fixed", true)
		m.set_shader_parameter("fixed_tint", Vector3(c.r, c.g, c.b))
		_bin_mats[color_index] = m
	return _bin_mats[color_index]


## The sweeper's spray and dust: WeaponFX's smoke puff with a short soft-particle fade - at its
## 1.2 m, puffs this close to the road faded out entirely.
static func spray_material() -> Material:
	if not _bin_mats.has("spray"):
		var m := WeaponFX.smoke_material().duplicate() as StandardMaterial3D
		m.proximity_fade_distance = 0.25
		_bin_mats["spray"] = m
	return _bin_mats["spray"]


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# --- Gear ------------------------------------------------------------------------------------------

## What every service vehicle's gear has: the car, the model's holder, its rig nodes by name.
class Gear extends Node3D:
	var car: Vehicle
	var holder: Node3D
	var rigs: Dictionary = {}

	func setup(c: Vehicle, h: Node3D, r: Dictionary) -> void:
		car = c
		holder = h
		rigs = r
		_setup()

	func _setup() -> void:
		pass

	## Back to rest (from the pool, or after a cycle cut short).
	func reset() -> void:
		pass

	## True while a cycle (a lift, a load) is running.
	func busy() -> bool:
		return false

	## The node the rig is posed in (the model's own root, which the rigs are children of).
	func rig_space(n: Node3D) -> Node3D:
		return n.get_parent() as Node3D


## The side loader's arm: the boom slides out to the cart, the claws close, the lift swings it up
## outward and over onto the hopper (the boom drawing in under it), shakes it out, brings it back
## down, sets it where it stood and lets go, and the boom draws in. advance() runs it; ServiceFleet
## starts it (begin()) when the truck stands at a cart and hides the kerb cart while it is held.
class GarbageArm extends Gear:
	const T_EXT := 1.5
	const T_GRAB := 0.5
	const T_LIFT := 1.9
	const T_SHAKE := 0.9
	const T_LOWER := 1.6
	const T_PLACE := 0.4
	const T_RETRACT := 1.3
	const LIFT_ANGLE := deg_to_rad(205.0)
	const CARRY_EXT := 0.15

	var boom: Node3D
	var lift: Node3D
	var boom_rest := Vector3.ZERO
	var lift_rest := Basis()
	var pivot_rest := Vector3.ZERO
	var inner: MeshInstance3D
	var ext := 0.0
	var theta := 0.0
	var t := -1.0
	var target_ext := 0.0
	var cart: Node3D
	var lid: Node3D
	var cart_global := Transform3D()
	var color_index := 0
	var picked := false
	var on_pick: Callable
	var on_return: Callable
	var whine: AudioStreamPlayer3D
	var bangs := 0
	var cycles := 0

	func _setup() -> void:
		boom = rigs.get("rig_boom") as Node3D
		lift = rigs.get("rig_lift") as Node3D
		if boom == null or lift == null:
			return
		boom_rest = boom.position
		lift.reparent(boom)
		lift_rest = lift.basis
		pivot_rest = boom.transform * lift.position
		# The boom's inner telescopic section: fills the gap between the guide channel and the
		# slid-out boom (a box stretched each frame).
		inner = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 0.13, 0.16)
		inner.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.32, 0.33, 0.34)
		mat.metallic = 0.7
		mat.roughness = 0.4
		inner.material_override = mat
		inner.visible = false
		rig_space(boom).add_child(inner)
		whine = ServiceSounds.player(car, "hydraulic", -9.0, 70.0)
		set_process(false)

	func reset() -> void:
		t = -1.0
		ext = 0.0
		theta = 0.0
		_drop_cart()
		_pose()
		if whine:
			whine.stop()
		set_process(false)

	func busy() -> bool:
		return t >= 0.0

	## Starts a lift of the cart standing at `kerb` (its global transform). False when the boom
	## cannot reach it from where the truck stands.
	func begin(kerb: Transform3D, color: int, pick: Callable, ret: Callable) -> bool:
		if boom == null or busy():
			return false
		var space := rig_space(boom)
		var at := space.global_transform.affine_inverse() * kerb.origin
		var need := at.x - (pivot_rest.x + ServiceVehicles.BIN_OUT)
		if need < -0.35 or need > ServiceVehicles.MAX_EXT or absf(at.z - pivot_rest.z) > 0.9:
			return false
		target_ext = clampf(need, 0.0, ServiceVehicles.MAX_EXT)
		cart_global = kerb
		color_index = color
		on_pick = pick
		on_return = ret
		picked = false
		bangs = 0
		t = 0.0
		set_process(true)
		if whine and not whine.playing:
			whine.play()
		return true

	func _process(delta: float) -> void:
		advance(delta)

	## Steps the cycle by `dt` seconds (the tests call it directly).
	func advance(dt: float) -> void:
		if t < 0.0:
			return
		t += dt
		var k := t
		var e := 0.0
		var a := 0.0
		var moving := true
		if k < T_EXT:
			e = target_ext * ServiceVehicles._ease(k / T_EXT)
		elif k < T_EXT + T_GRAB:
			e = target_ext
			moving = false
			if not picked and k > T_EXT + T_GRAB * 0.6:
				_take_cart()
		else:
			k -= T_EXT + T_GRAB
			if k < T_LIFT:
				var u := ServiceVehicles._ease(k / T_LIFT)
				a = LIFT_ANGLE * u
				e = lerpf(target_ext, CARRY_EXT, u)
			elif k < T_LIFT + T_SHAKE:
				var s := (k - T_LIFT) / T_SHAKE
				a = LIFT_ANGLE - deg_to_rad(9.0) * absf(sin(s * PI * 2.0))
				e = CARRY_EXT
				var hit := int(s * 2.0 + 0.5)
				if hit > bangs:
					bangs = hit
					_bang()
			else:
				k -= T_LIFT + T_SHAKE
				if k < T_LOWER:
					var u := ServiceVehicles._ease(k / T_LOWER)
					a = LIFT_ANGLE * (1.0 - u)
					e = lerpf(CARRY_EXT, target_ext, u)
				elif k < T_LOWER + T_PLACE:
					e = target_ext
					moving = false
					if picked:
						_drop_cart()
						if on_return.is_valid():
							on_return.call()
				elif k < T_LOWER + T_PLACE + T_RETRACT:
					e = target_ext * (1.0 - ServiceVehicles._ease((k - T_LOWER - T_PLACE) / T_RETRACT))
				else:
					t = -1.0
					cycles += 1
					e = 0.0
					moving = false
					set_process(false)
		ext = e
		theta = a
		_pose()
		if whine:
			if moving and t >= 0.0 and not whine.playing:
				whine.play()
			elif (not moving or t < 0.0) and whine.playing:
				whine.stop()
			whine.pitch_scale = 0.85 + 0.25 * clampf(theta / LIFT_ANGLE, 0.0, 1.0)

	func _pose() -> void:
		if boom == null:
			return
		boom.position = boom_rest + Vector3(ext, 0.0, 0.0)
		lift.basis = Basis(Vector3(0.0, 0.0, 1.0), theta) * lift_rest
		if inner:
			var x0 := boom_rest.x - 0.35
			var x1 := boom_rest.x + ext + 0.05
			inner.visible = ext > 0.6
			inner.scale = Vector3(maxf(x1 - x0, 0.01), 1.0, 1.0)
			inner.position = Vector3((x0 + x1) * 0.5, boom_rest.y, boom_rest.z)
		if lid != null:
			# The lid falls open once the cart is past upright on its way over.
			var open := clampf((theta - deg_to_rad(110.0)) / deg_to_rad(60.0), 0.0, 1.0)
			lid.rotation.z = -1.9 * open

	func _take_cart() -> void:
		picked = true
		cart = Node3D.new()
		cart.name = "Cart"
		var body := MeshInstance3D.new()
		body.mesh = KerbBins.mesh(0, "body")
		body.material_override = ServiceVehicles.bin_material(color_index)
		cart.add_child(body)
		lid = MeshInstance3D.new()
		(lid as MeshInstance3D).mesh = KerbBins.mesh(0, "lid")
		(lid as MeshInstance3D).material_override = ServiceVehicles.bin_material(color_index)
		lid.position = KerbBins.hinge()
		cart.add_child(lid)
		lift.add_child(cart)
		cart.global_transform = cart_global
		if on_pick.is_valid():
			on_pick.call()

	func _drop_cart() -> void:
		if cart != null and is_instance_valid(cart):
			cart.queue_free()
		cart = null
		lid = null
		picked = false

	func _bang() -> void:
		if not is_inside_tree():
			return
		var p := ServiceSounds.player(car, "bang", -2.0, 90.0)
		p.position = Vector3(0.6, 2.4, -ServiceVehicles.ARM_AHEAD)
		p.pitch_scale = randf_range(0.9, 1.1)
		p.play()
		p.finished.connect(p.queue_free)
		var sfx := get_node_or_null("/root/Sfx")
		if sfx:
			sfx.play("hit_metal", car.global_transform * p.position, -6.0, 0.7)


## The sweeper's gear: the gutter brooms and the main broom spin while it works, water sprays
## ahead of them, dust lifts behind, the brushes hiss.
class SweeperGear extends Gear:
	var brush_r: Node3D
	var brush_l: Node3D
	var broom: Node3D
	var working := false
	var spin := 0.0
	var water: Array[CPUParticles3D] = []
	var dust: CPUParticles3D
	var hiss: AudioStreamPlayer3D

	func _setup() -> void:
		brush_r = rigs.get("rig_brush_r") as Node3D
		brush_l = rigs.get("rig_brush_l") as Node3D
		broom = rigs.get("rig_broom") as Node3D
		var web := OS.has_feature("web")
		for side: float in [1.0, -1.0]:
			var p := _mist(Color(0.85, 0.88, 0.92, 0.6), 0.10, 0.35, 0.8 if not web else 0.5)
			p.position = Vector3(side * 0.95, 0.25, -1.30)
			p.direction = Vector3(side * 0.2, -1.0, -0.15)
			p.spread = 18.0
			p.initial_velocity_min = 2.5
			p.initial_velocity_max = 4.0
			p.gravity = Vector3(0, -9.0, 0)
			water.append(p)
		dust = _mist(Color(0.62, 0.58, 0.52, 0.42), 0.7, 1.6, 2.6 if not web else 1.2)
		dust.position = Vector3(0.9, 0.2, -0.2)
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		dust.emission_box_extents = Vector3(0.5, 0.1, 0.8)
		dust.direction = Vector3(0.3, 0.6, 1.0)
		dust.spread = 40.0
		dust.initial_velocity_min = 0.3
		dust.initial_velocity_max = 1.0
		dust.gravity = Vector3(0, 0.15, 0)
		dust.damping_min = 0.5
		dust.damping_max = 1.0
		hiss = ServiceSounds.player(car, "brush", -8.0, 60.0)

	func _mist(color: Color, size0: float, size1: float, life: float) -> CPUParticles3D:
		var p := CPUParticles3D.new()
		var quad := QuadMesh.new()
		quad.material = ServiceVehicles.spray_material()
		p.mesh = quad
		p.amount = 24
		p.lifetime = life
		p.local_coords = false
		p.scale_amount_min = size0
		p.scale_amount_max = size1
		var ramp := Gradient.new()
		ramp.set_color(0, Color(color.r, color.g, color.b, 0.0))
		ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
		ramp.add_point(0.2, color)
		p.color_ramp = ramp
		p.emitting = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 5, 10))
		add_child(p)
		return p

	func set_working(on: bool) -> void:
		if on == working:
			return
		working = on
		for p in water:
			p.emitting = on
		if dust:
			dust.emitting = on
		if hiss:
			if on:
				hiss.play()
			else:
				hiss.stop()

	func reset() -> void:
		set_working(false)

	func _process(delta: float) -> void:
		var target := 7.0 if working else 0.0
		spin = move_toward(spin, target, delta * 6.0)
		if spin <= 0.0:
			return
		if brush_r:
			brush_r.rotate_object_local(Vector3.UP, -spin * delta)
		if brush_l:
			brush_l.rotate_object_local(Vector3.UP, spin * delta)
		if broom:
			broom.rotate_object_local(Vector3.RIGHT, spin * 1.6 * delta)


## The rollback's bed: slid back along the chassis and tilted until its tail meets the road
## (`pose(u)`, u 0 level .. 1 down), ServiceFleet winching a wreck up it. `deck()` is the global
## transform a load rides on (the middle of the deck, on top of it).
class TowBed extends Gear:
	const SLIDE := 1.9
	const TILT := deg_to_rad(11.0)
	## The deck's top over the bed node's origin (the pivot), and the middle of the deck from it
	## (body space, +z rearward: the deck runs from the headboard back past the tail).
	const DECK_UP := 0.28
	const DECK_MID := -1.25
	var bed: Node3D
	var rest := Transform3D()
	var u := 0.0
	var winch: AudioStreamPlayer3D

	func _setup() -> void:
		bed = rigs.get("rig_bed") as Node3D
		if bed:
			rest = bed.transform
		winch = ServiceSounds.player(car, "winch", -10.0, 60.0)

	func reset() -> void:
		pose(0.0)
		if winch:
			winch.stop()

	## 0 level and home, 1 slid back and tilted to the road.
	func pose(x: float) -> void:
		u = clampf(x, 0.0, 1.0)
		if bed == null:
			return
		var slide := ServiceVehicles._ease(minf(u * 1.6, 1.0)) * SLIDE
		var tilt := ServiceVehicles._ease(maxf(u * 1.6 - 0.6, 0.0)) * TILT
		bed.transform = Transform3D(Basis(Vector3.RIGHT, tilt) * rest.basis, rest.origin + Vector3(0.0, 0.0, slide))

	## Where a load sits on the deck (global): the middle of the deck at `back` metres further
	## toward the tail (0 the load's home over the axles).
	func deck(back: float = 0.0) -> Transform3D:
		if bed == null:
			return car.global_transform
		return bed.global_transform * Transform3D(Basis(), Vector3(0.0, DECK_UP, DECK_MID + back))


## The ice-cream truck: the chime while it cruises, the amber flashers while it stands.
class IceCreamGear extends Gear:
	var chime: AudioStreamPlayer3D
	var standing := false
	var _beacon_surfaces: Array = []

	func _setup() -> void:
		chime = ServiceSounds.player(car, "chime", -4.0, 140.0)
		chime.position = Vector3(0.0, 3.0, -0.6)
		for m in car._body_meshes:
			if not is_instance_valid(m) or m.mesh == null:
				continue
			for si in m.mesh.get_surface_count():
				var src := m.mesh.surface_get_material(si)
				if src != null and String(src.resource_name).begins_with("beacon_amber"):
					_beacon_surfaces.append([m, si])

	func set_music(on: bool) -> void:
		if chime == null:
			return
		if on and not chime.playing:
			chime.play()
		elif not on and chime.playing:
			chime.stop()

	func set_standing(on: bool) -> void:
		if on == standing:
			return
		standing = on
		for e: Array in _beacon_surfaces:
			(e[0] as MeshInstance3D).set_surface_override_material(int(e[1]), ServiceVehicles.beacon_material(not on))

	func reset() -> void:
		set_music(false)
		set_standing(false)
