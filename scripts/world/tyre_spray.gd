class_name TyreSpray
extends Node3D
## Spray thrown up behind the tyres of cars driving on a wet street. A small pool of particle
## emitters, not one per car: every `scan_interval` the fastest cars near the player on a wet
## road get one each, and each frame an emitter rides its car's rear axle. Weather owns it and
## feeds it `wetness`; nothing runs on a dry street.

## Emitters in the pool (the web gets half).
@export var emitters: int = 6
## Only cars this close to the player throw spray (m).
@export var reach: float = 55.0
## Speed (m/s) at which spray starts, and at which it is at its fullest.
@export var min_speed: float = 4.0
@export var full_speed: float = 24.0
## Below this street wetness there is no spray at all; at `full_wetness` it is at its fullest.
@export var min_wetness: float = 0.12
@export var full_wetness: float = 0.6
## Mist puffs per emitter, how long a puff lives, and its size at birth and at death (m).
@export var puffs: int = 40
@export var puff_life: float = 0.9
@export var puff_size: Vector2 = Vector2(0.6, 2.6)
## Peak opacity of one puff: spray is a veil, many thin puffs deep.
@export var puff_alpha: float = 0.42
@export var scan_interval: float = 0.25

## Street wetness, 0..1 (Weather.wetness).
var wetness: float = 0.0
## Quality says the machine is struggling (Weather's LOWEST): no spray.
var low_detail: bool = false

var _pool: Array[CPUParticles3D] = []
var _cars: Array = []
var _last_pos: Dictionary = {}
var _speed: Dictionary = {}
var _scan_left: float = 0.0


func _ready() -> void:
	var n := maxi(1, emitters / 2) if OS.has_feature("web") else emitters
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = WeaponFX.puff_texture()
	mat.albedo_color = Color(0.92, 0.94, 0.97)
	# Mist is lit through as much as on its face: from behind the sun it was a dark smudge.
	mat.backlight_enabled = true
	mat.backlight = Color(0.7, 0.72, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Or every puff renders exactly one metre whatever scale_amount says (CLAUDE.md, Effects).
	mat.billboard_keep_scale = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not OS.has_feature("web"):
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 0.6
	var quad := QuadMesh.new()
	quad.material = mat
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, puff_size.x / puff_size.y))
	grow.add_point(Vector2(1.0, 1.0))
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	ramp.add_point(0.15, Color(1.0, 1.0, 1.0, puff_alpha))
	ramp.add_point(0.55, Color(1.0, 1.0, 1.0, puff_alpha * 0.6))
	for i in n:
		var p := CPUParticles3D.new()
		p.name = "Spray%d" % i
		p.mesh = quad
		p.amount = puffs
		p.lifetime = puff_life
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(0.8, 0.08, 0.15)
		# Backward (+Z is the car's rear) and a little up, fanning out.
		p.direction = Vector3(0.0, 0.55, 1.0)
		p.spread = 24.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 5.0
		p.gravity = Vector3(0.0, -5.0, 0.0)
		p.damping_min = 3.0
		p.damping_max = 5.0
		p.scale_amount_min = puff_size.y * 0.7
		p.scale_amount_max = puff_size.y
		p.scale_amount_curve = grow
		p.color_ramp = ramp
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.emitting = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-4.0, -1.0, -4.0), Vector3(8.0, 5.0, 12.0))
		add_child(p)
		_pool.append(p)
		_cars.append(null)


func _process(delta: float) -> void:
	var wet := 0.0 if low_detail else clampf((wetness - min_wetness) / maxf(full_wetness - min_wetness, 0.01), 0.0, 1.0)
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = scan_interval
		_scan(wet)
	for i in _pool.size():
		var p := _pool[i]
		var car: Node3D = _cars[i]
		if car == null or not is_instance_valid(car) or not car.is_inside_tree() or wet <= 0.0:
			if p.emitting:
				p.emitting = false
			_cars[i] = null
			continue
		var speed: float = _speed.get(car.get_instance_id(), 0.0)
		var amount := wet * clampf((speed - min_speed) / maxf(full_speed - min_speed, 0.1), 0.0, 1.0)
		var rear := 1.4
		var pose: Variant = Vehicle.WHEEL_POSE.get(car.get("body_type"))
		if pose is Dictionary:
			rear = float(pose["rear"]) + 0.25
		var t := car.global_transform
		p.global_transform = Transform3D(t.basis.orthonormalized(), t * Vector3(0.0, -0.1, rear))
		# How thick the spray is: the colour multiplies the ramp, so this thins each new puff.
		p.color = Color(1.0, 1.0, 1.0, amount)
		p.initial_velocity_max = 2.0 + 0.2 * speed
		var on := amount > 0.02
		if p.emitting != on:
			p.emitting = on


## Picks the cars that throw spray: moving, on the ground, near the player, fastest first.
func _scan(wet: float) -> void:
	var seen := {}
	var ranked: Array = []
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if wet > 0.0 and player:
		var here := player.global_position
		for node in get_tree().get_nodes_in_group("vehicle"):
			var car := node as Node3D
			if car == null or car is Aircraft or not car.is_inside_tree():
				continue
			var d := car.global_position.distance_to(here)
			if d > reach:
				continue
			var id := car.get_instance_id()
			seen[id] = true
			# True world position, so an origin shift between two scans is not a car at 1000 km/h.
			var pos := WorldState.to_world(car.global_position)
			var last: Variant = _last_pos.get(id)
			_last_pos[id] = pos
			if last == null:
				continue
			var step: Vector3 = pos - (last as Vector3)
			# Airborne: a flying car or a jump throws nothing.
			if absf(step.y) > 2.5 * scan_interval or not _grounded(car):
				_speed[id] = 0.0
				continue
			var speed := Vector2(step.x, step.z).length() / scan_interval
			_speed[id] = speed
			if speed > min_speed:
				ranked.append([speed - d * 0.1, car])
	for id in _last_pos.keys():
		if not seen.has(id):
			_last_pos.erase(id)
			_speed.erase(id)
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	var chosen: Array = []
	for r in ranked:
		if chosen.size() >= _pool.size():
			break
		chosen.append(r[1])
	# Keep a car on the emitter it already has, so its trail is not cut off and restarted.
	for i in _pool.size():
		if _cars[i] != null and not chosen.has(_cars[i]):
			_cars[i] = null
	for car in chosen:
		if _cars.has(car):
			continue
		var slot := _cars.find(null)
		if slot >= 0:
			_cars[slot] = car


func _grounded(car: Node3D) -> bool:
	var wheels: Variant = car.get("wheels")
	if wheels is Array and not (wheels as Array).is_empty():
		for w in wheels:
			if is_instance_valid(w) and (w as VehicleWheel3D).is_in_contact():
				return true
		return false
	# Traffic cars (kinematic, no wheels) are always on the road.
	return true
