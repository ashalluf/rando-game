class_name DrivingFX
extends Node3D
## The feel of driving fast and badly: skid marks laid behind sliding and spinning tyres, tyre
## smoke on burnouts, donuts and drifts (spray instead on a wet road), sparks and a grinding
## scrape where the body meets the road or a wall, dust off the hills' dirt and sand spray off the
## beach, tyre tracks in sand and dirt, exhaust puffs on a cold morning, a backfire on a hard
## lift-off and heat haze behind the player's exhaust (Forward+ desktop), and the tyre squeal.
##
## ONE node for the whole city (made by the first Vehicle, `ensure()`, a child of the current
## scene so origin shifts carry the marks), never a node per car: every `scan_interval` it picks
## the physical cars near the camera worth watching (the player's first, then the nearest moving
## ones, `max_cars`), and each physics tick reads their wheels (VehicleWheel3D's contact, skid
## info and the slip it works out from the contact's velocity) and their body contacts
## (contact_monitor is switched on for the cars it watches only, and back off when it drops them).
## Kinematic traffic has no wheels and never slides; only its idling exhaust is drawn, within
## `exhaust_reach`. Every effect is a small POOL of emitters handed to the strongest demand this
## tick, so a pile-up costs what one drift does.
##
## Skid marks are ONE MultiMesh of flat quads (shaders/skid_mark.gdshader, blend_mul: rubber
## darkens whatever light is on the road and costs no lighting), a ring of `mark_capacity`
## segments, faded over `mark_life` seconds in the shader. Flat quads, not Decals: one draw for
## every mark in the city, the same on both renderers, and at a grazing angle a 2 cm lift holds.

## The node (one a scene). Tests and stills read it.
static var _inst: DrivingFX = null
## Turns the whole layer off (`DRIVING_FX=0` in the environment is the A/B).
static var enabled: bool = true
## Stills only: every tyre reads this surface (Surface, -1 off) - the test room has no beach.
static var force_surface: int = -1

enum Surface { ASPHALT, DIRT, SAND }

@export_group("Watching")
## Only physical cars this close to the camera get any effect (m).
@export var reach: float = 70.0
## Most cars watched at once (the web gets half).
@export var max_cars: int = 6
## How often the watched cars are picked again (s).
@export var scan_interval: float = 0.2

@export_group("Slip")
## Sideways or locked-up slip (m/s at the contact) at which a tyre starts to mark and squeal...
@export var mark_slip: float = 2.4
## ... and at which the mark, the squeal and the smoke are at their fullest.
@export var full_slip: float = 10.0
## A tyre spinning on the spot lays a patch every this many metres of tread spun (m).
@export var patch_spin: float = 1.6
## Throttle on a car slower than this (m/s) spins the driven wheels (a burnout).
@export var burnout_speed: float = 9.0
## How much a full-throttle launch counts as slip (m/s at standstill).
@export var burnout_slip: float = 13.0

@export_group("Skid marks")
## Segments in the ring (the web gets 40 %).
@export var mark_capacity: int = 3000
## Length of one segment (m): short enough that a drift's arc reads as a curve.
@export var mark_segment: float = 0.32
## Seconds a mark takes to fade out.
@export var mark_life: float = 240.0
## Strength of fresh rubber at full slip (how far it darkens the road).
@export var mark_strength: float = 0.9
## Rubber, as a linear multiplier on the road.
@export var rubber_tint: Color = Color(0.05, 0.045, 0.045)
## Tyre tracks: sand and dirt take a print at any speed.
@export var sand_tint: Color = Color(0.55, 0.47, 0.36)
@export var dirt_tint: Color = Color(0.5, 0.42, 0.33)
@export var track_strength: float = 0.55

@export_group("Smoke")
## Smoke emitters in the pool (web half, none at Quality LOWEST).
@export var smoke_emitters: int = 6
## Slip (m/s) from which a dry asphalt tyre smokes.
@export var smoke_slip: float = 4.5
## Puffs per emitter, how long one lives (s) and its size at birth and death (m).
@export var smoke_puffs: int = 64
@export var smoke_life: float = 3.2
@export var smoke_size: Vector2 = Vector2(0.6, 4.4)
## Peak opacity of one puff at full slip.
@export var smoke_alpha: float = 0.7
## Above this street wetness a spinning tyre throws spray, not smoke.
@export var wet_spray: float = 0.15

@export_group("Dust and sand")
## Dust and spray emitters in the pool.
@export var dust_emitters: int = 4
## Speed (m/s) at which a tyre on dirt or sand starts to throw dust, and at which it is fullest.
@export var dust_speed: float = 3.0
@export var dust_full_speed: float = 24.0

@export_group("Sparks")
## Spark emitters in the pool, and the grinding loops.
@export var spark_emitters: int = 4
@export var scrape_voices: int = 2
## Sliding speed (m/s) at a body contact from which it sparks, and at which it is fullest.
@export var spark_speed: float = 4.0
@export var spark_full_speed: float = 22.0
## Light thrown by the strongest scrape at night (desktop), energy at full.
@export var spark_light_energy: float = 3.0

@export_group("Exhaust")
## Exhaust emitters in the pool (the player's car and idling traffic).
@export var exhaust_emitters: int = 3
## Idling traffic this close puffs on a cold morning (m).
@export var exhaust_reach: float = 26.0
## Chance a hard lift-off from full throttle pops, the speed it needs and the gap between pops.
@export var backfire_chance: float = 0.3
@export var backfire_min_speed: float = 12.0
@export var backfire_cooldown: float = 1.6
## Heat haze behind the player's exhaust (Forward+ desktop only).
@export var shimmer: bool = true

@export_group("Sound")
## Squeal loops (the player's car, then the loudest other) and their level at full slip.
@export var screech_voices: int = 2
@export var screech_db: float = -2.0
@export var scrape_db: float = -1.0
@export var backfire_db: float = 2.0

var _cars: Array = [] # [Vehicle]
var _exhaust_cars: Array = [] # cars near enough to puff exhaust, picked each scan
var _scan_left: float = 0.0
var _wheel_state: Dictionary = {} # wheel instance id -> {"last": Vector3 local or null, "carry": float}
var _monitored: Dictionary = {} # car instance id -> car (contact_monitor switched on by us)
var _prev_force: Dictionary = {} # car id -> |engine_force| last tick
var _backfire_at: float = -10.0
var _clock: float = 0.0

var _marks: MultiMesh
var _marks_node: MultiMeshInstance3D
var _mark_mat: ShaderMaterial
var _mark_next: int = 0
var _mark_count: int = 0
var _mark_birth: PackedFloat32Array = PackedFloat32Array()
var _mark_sweep: float = 0.0

var _smoke: Array[CPUParticles3D] = []
var _dust: Array[CPUParticles3D] = []
var _sparks: Array[CPUParticles3D] = []
var _exhaust: Array[CPUParticles3D] = []
var _smoke_keys: Array = []
var _dust_keys: Array = []
var _spark_keys: Array = []
var _exhaust_keys: Array = []
var _screech: Array[AudioStreamPlayer3D] = []
var _screech_keys: Array = []
var _scrape: Array[AudioStreamPlayer3D] = []
var _scrape_keys: Array = []
var _spark_light: OmniLight3D
var _flame: CPUParticles3D
var _flame_light: OmniLight3D
var _shimmer: MeshInstance3D
var _shimmer_mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()

## What the last tick asked for (tests and stills read these).
var last_marks: int = 0
var last_smoke: int = 0
var last_sparks: int = 0
var last_dust: int = 0


## Makes the node once a scene (Vehicle._ready calls it).
static func ensure(from: Node) -> void:
	if not enabled or OS.get_environment("DRIVING_FX") == "0":
		return
	# Made but not added yet (the add is deferred, and a chunk builds many cars in one frame), or
	# already in a level: nothing to do.
	if _inst != null and is_instance_valid(_inst) and (_inst.get_parent() == null or _inst.is_inside_tree()):
		return
	var tree := from.get_tree()
	if tree == null:
		return
	# The level the car is in (the city, the test room): the child of the root above it. Its
	# Node3D children are shifted with the origin, which carries the marks.
	var host: Node = from
	while host.get_parent() != null and host.get_parent() != tree.root:
		host = host.get_parent()
	if not host is Node3D:
		host = tree.root
	_inst = DrivingFX.new()
	_inst.name = "DrivingFX"
	host.add_child.call_deferred(_inst)


static func instance() -> DrivingFX:
	return _inst if _inst != null and is_instance_valid(_inst) else null


static func _web() -> bool:
	return OS.has_feature("web")


func _ready() -> void:
	add_to_group("driving_fx")
	_rng.seed = 0x5C1D
	var web := _web()
	var low := _quality_level() >= 3
	if web:
		max_cars = maxi(2, max_cars / 2)
		mark_capacity = int(mark_capacity * 0.4)
		smoke_emitters = maxi(2, smoke_emitters / 2)
		dust_emitters = maxi(2, dust_emitters / 2)
		spark_emitters = maxi(2, spark_emitters / 2)
		exhaust_emitters = 1
	if low:
		smoke_emitters = mini(smoke_emitters, 2)
		dust_emitters = mini(dust_emitters, 1)
		spark_emitters = mini(spark_emitters, 1)
		exhaust_emitters = 0
	_build_marks()
	var smoke_mat := _puff_material(Color(0.8, 0.79, 0.78), 0.9)
	for i in smoke_emitters:
		_smoke.append(_make_smoke(smoke_mat))
		_smoke_keys.append(null)
	var dust_mat := _puff_material(Color(1.0, 1.0, 1.0), 0.6)
	for i in dust_emitters:
		_dust.append(_make_dust(dust_mat))
		_dust_keys.append(null)
	for i in spark_emitters:
		_sparks.append(_make_sparks())
		_spark_keys.append(null)
	for i in exhaust_emitters:
		_exhaust.append(_make_exhaust(smoke_mat))
		_exhaust_keys.append(null)
	for i in screech_voices:
		var p := Sfx.loop_player("skid", 0.0)
		p.set_meta("base_db", p.volume_db)
		p.name = "Screech%d" % i
		add_child(p)
		_screech.append(p)
		_screech_keys.append(null)
	for i in scrape_voices:
		var p := Sfx.loop_player("scrape", 0.0)
		p.set_meta("base_db", p.volume_db)
		p.name = "Scrape%d" % i
		add_child(p)
		_scrape.append(p)
		_scrape_keys.append(null)
	_flame = _make_flame()
	if not web:
		_spark_light = OmniLight3D.new()
		_spark_light.name = "SparkLight"
		_spark_light.light_color = Color(1.0, 0.62, 0.25)
		_spark_light.omni_range = 5.0
		_spark_light.light_energy = 0.0
		_spark_light.shadow_enabled = false
		_spark_light.visible = false
		add_child(_spark_light)
		_flame_light = OmniLight3D.new()
		_flame_light.name = "BackfireLight"
		_flame_light.light_color = Color(1.0, 0.55, 0.2)
		_flame_light.omni_range = 4.0
		_flame_light.light_energy = 0.0
		_flame_light.visible = false
		add_child(_flame_light)
	if shimmer and _shimmer_supported():
		_shimmer_mat = ShaderMaterial.new()
		_shimmer_mat.shader = preload("res://shaders/exhaust_shimmer.gdshader")
		_shimmer_mat.render_priority = Material.RENDER_PRIORITY_MIN
		var q := QuadMesh.new()
		q.size = Vector2(0.7, 1.1)
		q.center_offset = Vector3(0.0, 0.45, 0.0)
		_shimmer = MeshInstance3D.new()
		_shimmer.name = "ExhaustShimmer"
		_shimmer.mesh = q
		_shimmer.material_override = _shimmer_mat
		_shimmer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shimmer.visible = false
		add_child(_shimmer)


func _exit_tree() -> void:
	for car in _monitored.values():
		if is_instance_valid(car):
			_unmonitor(car)
	_monitored.clear()
	if _inst == self:
		_inst = null


## A node of the level this one lives in (the city's Weather, DayNight, Quality), or null.
func _level_node(path: String) -> Node:
	var level := get_parent()
	return level.get_node_or_null(path) if level and level != get_tree().root else null


static func _shimmer_supported() -> bool:
	if _web() or DisplayServer.get_name() == "headless":
		return false
	return RenderingServer.get_current_rendering_method() == "forward_plus"


func _quality_level() -> int:
	var q: Node = _level_node("Quality")
	return int(q.get("level")) if q else 0


# --- Watching -------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = scan_interval
		_scan()
	_mark_mat.set_shader_parameter("now_min", fmod(_clock / 60.0, 30.0))
	_sweep_marks(delta)
	var wet := _wetness()
	var smoke_demand: Array = []
	var dust_demand: Array = []
	var spark_demand: Array = []
	var screech_demand: Array = []
	var marks := 0
	for held: Variant in _cars:
		# Untyped until checked: a freed car assigned to a typed variable is a script error.
		if not is_instance_valid(held) or not (held as Node).is_inside_tree():
			continue
		var car: Vehicle = held
		marks += _tick_wheels(car, wet, smoke_demand, dust_demand, screech_demand)
		_tick_contacts(car, spark_demand, dust_demand)
		_tick_backfire(car)
	last_marks = marks
	last_smoke = smoke_demand.size()
	last_sparks = spark_demand.size()
	last_dust = dust_demand.size()
	_serve(_smoke, _smoke_keys, smoke_demand, _drive_smoke)
	_serve(_dust, _dust_keys, dust_demand, _drive_dust)
	_serve(_sparks, _spark_keys, spark_demand, _drive_sparks)
	_serve_voices(_screech, _screech_keys, screech_demand, screech_db, 0.85, 0.3, 3, 1)
	_serve_voices(_scrape, _scrape_keys, spark_demand, scrape_db, 0.8, 0.45, 0, 8)
	_spark_glow(spark_demand)
	_tick_exhaust(delta)


## Picks the cars worth watching: physical (not traffic, not frozen), with wheels, near the
## camera; the player's car always first, then moving ones by distance.
func _scan() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var here := cam.global_position
	var ranked: Array = []
	_exhaust_cars.clear()
	for node in get_tree().get_nodes_in_group("vehicle"):
		var car := node as Vehicle
		if car == null or car is Aircraft or not car.is_inside_tree():
			continue
		# Exhaust: any car near the camera, traffic included (checked each tick for idling).
		if not _exhaust.is_empty() and (_is_player_car(car) or car.global_position.distance_squared_to(here) < exhaust_reach * exhaust_reach):
			_exhaust_cars.append(car)
		if car.freeze or car.is_traffic():
			continue
		if car.wheels.is_empty():
			continue
		var d := car.global_position.distance_to(here)
		var mine := _is_player_car(car)
		if not mine and (d > reach or car.linear_velocity.length_squared() < 0.25):
			continue
		ranked.append([-1.0 if mine else d, car])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	var keep: Array = []
	for r in ranked:
		if keep.size() >= max_cars:
			break
		keep.append(r[1])
	# Contact reports only on the cars watched: switched on as they come in, off as they go.
	for id in _monitored.keys():
		var c: Variant = _monitored[id]
		if not is_instance_valid(c):
			_monitored.erase(id)
		elif not keep.has(c):
			_unmonitor(c)
			_monitored.erase(id)
			_forget_wheels(c)
	for car: Vehicle in keep:
		var id := car.get_instance_id()
		if not _monitored.has(id):
			car.set_meta("dfx_contact", [car.contact_monitor, car.max_contacts_reported])
			car.contact_monitor = true
			car.max_contacts_reported = maxi(car.max_contacts_reported, 4)
			_monitored[id] = car
	_cars = keep


func _unmonitor(car: Vehicle) -> void:
	var was: Variant = car.get_meta("dfx_contact", null) if car.has_meta("dfx_contact") else null
	if was is Array:
		car.contact_monitor = bool(was[0])
		car.max_contacts_reported = int(was[1])
		car.remove_meta("dfx_contact")


func _forget_wheels(car: Vehicle) -> void:
	for w in car.wheels:
		if is_instance_valid(w):
			_wheel_state.erase(w.get_instance_id())


static func _is_player_car(car: Vehicle) -> bool:
	return car.driver != null and is_instance_valid(car.driver) and car.driver.is_in_group("player")


## Street wetness, 0..1: the Weather node's, or the global PropFactory last pushed (the test room).
func _wetness() -> float:
	var w: Node = _level_node("Weather")
	if w:
		return float(w.get("wetness"))
	return maxf(PropFactory._wetness, 0.0)


## What the ground under a wheel is: hill terrain (its own layer) is dirt, the beach zone sand.
func _surface(car: Vehicle, body: Object, at: Vector3) -> Surface:
	if force_surface >= 0:
		return force_surface as Surface
	if body is CollisionObject3D and ((body as CollisionObject3D).collision_layer & CityChunk.TERRAIN_LAYER) != 0:
		return Surface.DIRT
	# The zone, worked out once a scan per car (cheap MacroMap maths, but not per wheel per tick).
	var zone: int = car.get_meta("dfx_zone", -1) if car.has_meta("dfx_zone") else -1
	var stamp: float = car.get_meta("dfx_zone_t", -1.0) if car.has_meta("dfx_zone_t") else -1.0
	if zone < 0 or _clock - stamp > scan_interval:
		zone = _zone_at(at)
		car.set_meta("dfx_zone", zone)
		car.set_meta("dfx_zone_t", _clock)
	if zone == MacroMap.Zone.BEACH:
		return Surface.SAND
	if zone == MacroMap.Zone.HILLS:
		return Surface.DIRT
	return Surface.ASPHALT


func _zone_at(at: Vector3) -> int:
	var scene := get_parent()
	var plan: Variant = scene.get("plan") if scene else null
	if plan == null:
		return MacroMap.Zone.CITY
	var w := WorldState.to_world(at)
	return int(plan.zone_at(Vector2(w.x, w.z)))


# --- Wheels -----------------------------------------------------------------------------------

## Reads one car's wheels: lays marks, and asks for smoke, dust and squeal. Returns marks laid.
func _tick_wheels(car: Vehicle, wet: float, smoke: Array, dust: Array, screech: Array) -> int:
	var laid := 0
	var mine := _is_player_car(car)
	var v := car.linear_velocity
	var fwd := -car.global_basis.z
	var speed_fwd := v.dot(fwd)
	var pose: Dictionary = car._wheel_pose()
	var tyre_w := float(pose.get("w", 0.24))
	# The driver's own feet: full throttle on a slow car spins the driven wheels; a hard brake or
	# the handbrake at speed locks them.
	var throttle := clampf(absf(car.engine_force) / maxf(car.engine_power, 1.0), 0.0, 2.5) if car.driver != null else 0.0
	var spin := 0.0
	if throttle > 0.5 and absf(speed_fwd) < burnout_speed:
		spin = (throttle - 0.5) / 0.5 * (1.0 - absf(speed_fwd) / burnout_speed)
		# The handbrake held against the throttle is the burnout proper: the car stays put.
		if car.brake >= car.handbrake_force * 0.9:
			spin = maxf(spin, minf(throttle, 1.0))
	var lock := 0.0
	if car.brake >= minf(car.brake_force, car.handbrake_force) * 0.9 and v.length() > 3.0:
		lock = v.length() * (0.6 if car.brake < car.brake_force * 0.9 else 0.85)
	var squeal := 0.0
	var squeal_at := Vector3.ZERO
	var squeal_n := 0
	for i in car.wheels.size():
		var w: VehicleWheel3D = car.wheels[i]
		if not is_instance_valid(w):
			continue
		var wid := w.get_instance_id()
		var st: Dictionary = _wheel_state.get(wid, {})
		if st.is_empty():
			st = {"last": null}
			_wheel_state[wid] = st
		if not w.is_in_contact():
			st["last"] = null
			continue
		var cp := w.get_contact_point()
		var n := w.get_contact_normal()
		var body := w.get_contact_body()
		var surface := _surface(car, body, cp)
		var cv := v + car.angular_velocity.cross(cp - car.global_position)
		cv -= n * cv.dot(n)
		var side := w.global_basis.x
		var lateral := absf(cv.dot(side))
		var rolling := cv.length()
		var slip := maxf(lateral, (1.0 - w.get_skidinfo()) * rolling)
		var rear := -car.global_basis.z.dot(cp - car.global_position) < 0.0
		# Wheelspin is the rear tyres' (every body here is laid out like a rear-driven car).
		var driven := w.use_as_traction and rear
		if driven and spin > 0.0:
			slip = maxf(slip, spin * burnout_slip)
		if lock > 0.0 and (not w.use_as_steering or car.brake < car.handbrake_force * 0.9):
			slip = maxf(slip, lock)
		var k := clampf((slip - mark_slip) / maxf(full_slip - mark_slip, 0.1), 0.0, 1.0)
		var key := wid
		# Marks: rubber on asphalt from a slide; a print in sand or dirt at any speed.
		var tint := rubber_tint
		var strength := 0.0
		if surface == Surface.ASPHALT:
			strength = mark_strength * (0.35 + 0.65 * k) if slip > mark_slip else 0.0
		else:
			tint = sand_tint if surface == Surface.SAND else dirt_tint
			strength = track_strength * clampf(0.5 + slip / full_slip, 0.0, 1.0) if rolling > 0.6 or spin > 0.0 else 0.0
		if strength > 0.0:
			laid += _lay(st, cp + n * 0.025, n, cv, tyre_w, tint, strength)
		else:
			st["last"] = null
		# A burnout on the spot goes nowhere, so lay a patch under the tyre every `patch_spin`
		# metres of rubber it spins off: overlapping, they darken it as the burnout goes on.
		if driven and spin > 0.3 and rolling < 2.0 and surface == Surface.ASPHALT:
			st["spun"] = float(st.get("spun", 0.0)) + spin * burnout_slip / float(Engine.physics_ticks_per_second)
			if float(st["spun"]) >= patch_spin:
				st["spun"] = 0.0
				laid += _patch(cp + n * 0.025, n, fwd, tyre_w, mark_strength * 0.5)
		var dir := cv.normalized() if rolling > 0.5 else fwd
		if surface == Surface.ASPHALT:
			if slip > smoke_slip:
				var s := clampf((slip - smoke_slip) / maxf(full_slip - smoke_slip, 0.1), 0.0, 1.0)
				# A burnout is thick on the rear tyres.
				if driven and spin > 0.3 and rear:
					s = minf(1.0, s * 1.3 + 0.25)
				if wet > wet_spray:
					dust.append([s * clampf(wet * 1.4, 0.3, 1.0), key, cp, dir, Color(0.92, 0.94, 0.97, 0.55), 1])
				else:
					smoke.append([s, key, cp, dir])
		else:
			var dk := clampf((rolling + slip - dust_speed) / maxf(dust_full_speed - dust_speed, 0.1), 0.0, 1.0)
			if dk > 0.0:
				var col := Color(0.86, 0.78, 0.62, 0.8) if surface == Surface.SAND else Color(0.6, 0.52, 0.42, 0.7)
				dust.append([dk, key, cp, dir, col, 2 if surface == Surface.SAND else 0])
		if surface == Surface.ASPHALT and k > 0.0:
			squeal = maxf(squeal, k)
			squeal_at += cp
			squeal_n += 1
	if squeal > 0.0 and squeal_n > 0:
		# The player's car always gets a voice first.
		screech.append([squeal + (1.0 if mine else 0.0), car.get_instance_id(), squeal_at / squeal_n, squeal])
	return laid


## Adds the segment from the wheel's last mark to `at` once the tyre has moved a segment.
func _lay(st: Dictionary, at: Vector3, n: Vector3, cv: Vector3, width: float, tint: Color, strength: float) -> int:
	var here := to_local(at)
	var last: Variant = st.get("last")
	if last == null:
		st["last"] = here
		return 0
	var from: Vector3 = last
	var step := here - from
	var seg := step.length()
	if seg < mark_segment:
		return 0
	st["last"] = here
	if seg > mark_segment * 6.0:
		# A teleport, a respawn or an origin shift caught mid-way: start again here.
		return 0
	var along := step / seg
	var up := (global_basis.inverse() * n).normalized()
	var across := up.cross(along).normalized()
	var fwd := across.cross(up).normalized()
	var b := Basis(across * width, up, fwd * seg)
	var xf := Transform3D(b, (from + here) * 0.5)
	var i := _mark_next
	_mark_next = (_mark_next + 1) % _marks.instance_count
	_mark_count = mini(_mark_count + 1, _marks.instance_count)
	_marks.set_instance_transform(i, xf)
	_marks.set_instance_color(i, Color(tint.r, tint.g, tint.b, strength))
	_marks.set_instance_custom_data(i, Color(fmod(_clock / 60.0, 30.0), 1.0, 0.0, 0.0))
	_mark_birth[i] = _clock
	_marks.visible_instance_count = _mark_count
	return 1


## One short mark centred on `at` along `along` (a tyre spinning on the spot).
func _patch(at: Vector3, n: Vector3, along: Vector3, width: float, strength: float) -> int:
	var st := {"last": to_local(at - along * 0.3)}
	return _lay(st, at + along * 0.3, n, along, width, rubber_tint, strength)


## Marks past their life are switched off for good (the shader's minute clock wraps at 30).
func _sweep_marks(delta: float) -> void:
	_mark_sweep -= delta
	if _mark_sweep > 0.0:
		return
	_mark_sweep = 10.0
	var gone := _clock - mark_life - 1.0
	for i in _mark_count:
		var b := _mark_birth[i]
		if b >= 0.0 and b < gone:
			_marks.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
			_mark_birth[i] = -1.0


func _build_marks() -> void:
	_marks = MultiMesh.new()
	_marks.transform_format = MultiMesh.TRANSFORM_3D
	_marks.use_colors = true
	_marks.use_custom_data = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	_marks.mesh = plane
	_marks.instance_count = maxi(64, mark_capacity)
	_marks.visible_instance_count = 0
	_mark_birth.resize(_marks.instance_count)
	_mark_birth.fill(-1.0)
	_mark_mat = ShaderMaterial.new()
	_mark_mat.shader = preload("res://shaders/skid_mark.gdshader")
	_mark_mat.set_shader_parameter("life_min", mark_life / 60.0)
	_marks_node = MultiMeshInstance3D.new()
	_marks_node.name = "SkidMarks"
	_marks_node.multimesh = _marks
	_marks_node.material_override = _mark_mat
	_marks_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# One draw for every mark in the city; the bounds would have to follow every new segment.
	_marks_node.custom_aabb = AABB(Vector3(-20000.0, -2000.0, -20000.0), Vector3(40000.0, 4000.0, 40000.0))
	add_child(_marks_node)


## Marks in the ring that are still showing (tests).
func marks_alive() -> int:
	var n := 0
	for i in _mark_count:
		if _mark_birth[i] >= 0.0:
			n += 1
	return n


# --- Body contacts ----------------------------------------------------------------------------

## The body itself touching something while it slides: the floor pan on the road after a jump,
## a flank down a wall or a barrier, two cars grinding. Sparks on hard ground, dust on dirt and
## sand; never people.
func _tick_contacts(car: Vehicle, sparks: Array, dust: Array) -> void:
	if not car.contact_monitor:
		return
	var state := PhysicsServer3D.body_get_direct_state(car.get_rid())
	if state == null:
		return
	var origin := state.transform.origin
	var best := 0.0
	var best_at := Vector3.ZERO
	var best_dir := Vector3.ZERO
	var best_n := Vector3.UP
	var soft := false
	for i in state.get_contact_count():
		var obj := state.get_contact_collider_object(i)
		if obj is CollisionObject3D and ((obj as CollisionObject3D).collision_layer & 8) != 0:
			continue # a person (npc layer): no sparks off anybody
		if obj is Node and ((obj as Node).is_in_group("pedestrian") or (obj as Node).is_in_group("player")):
			continue
		var at := state.get_contact_local_position(i)
		var n := state.get_contact_local_normal(i)
		var rel := state.get_velocity_at_local_position(at - origin) - state.get_contact_collider_velocity_at_position(i)
		var tangential := rel - n * rel.dot(n)
		var s := tangential.length()
		if s > best:
			best = s
			best_at = at
			best_dir = tangential / maxf(s, 0.001)
			best_n = n
			soft = obj is CollisionObject3D and ((obj as CollisionObject3D).collision_layer & CityChunk.TERRAIN_LAYER) != 0
	if best < spark_speed:
		return
	var k := clampf((best - spark_speed) / maxf(spark_full_speed - spark_speed, 0.1), 0.0, 1.0)
	var key := car.get_instance_id() * 8 + 7
	if soft or _surface(car, null, best_at) != Surface.ASPHALT:
		dust.append([0.4 + 0.6 * k, key, best_at, best_dir, Color(0.62, 0.54, 0.44, 0.75), 0])
		return
	sparks.append([0.25 + 0.75 * k, key, best_at, best_dir, best_n])


# --- Pools ------------------------------------------------------------------------------------

## Hands each emitter of a pool to the strongest demands ([strength, key, ...]), keeping an
## emitter on the key it already serves so its trail is not cut off and restarted.
func _serve(pool: Array, keys: Array, demand: Array, drive: Callable) -> void:
	demand.sort_custom(func(a, b): return a[0] > b[0])
	var chosen := {}
	for d in demand:
		if chosen.size() >= pool.size():
			break
		if not chosen.has(d[1]):
			chosen[d[1]] = d
	for i in pool.size():
		if keys[i] != null and not chosen.has(keys[i]):
			keys[i] = null
	for key in chosen:
		if keys.has(key):
			continue
		var slot := keys.find(null)
		if slot >= 0:
			keys[slot] = key
	for i in pool.size():
		var p: CPUParticles3D = pool[i]
		if keys[i] == null:
			if p.emitting:
				p.emitting = false
			continue
		drive.call(p, chosen[keys[i]])
		if not p.emitting:
			p.emitting = true


func _aim(p: Node3D, at: Vector3, back: Vector3) -> void:
	# The emitter's +Z points the way the puffs are thrown (back along the contact's motion).
	var z := back
	z.y = 0.0
	if z.length_squared() < 0.0001:
		z = Vector3.BACK
	z = z.normalized()
	var x := Vector3.UP.cross(z).normalized()
	p.global_transform = Transform3D(Basis(x, Vector3.UP, z), at)


func _drive_smoke(p: CPUParticles3D, d: Array) -> void:
	var s: float = d[0]
	_aim(p, (d[2] as Vector3) + Vector3.UP * 0.35, -(d[3] as Vector3))
	p.color = Color(1.0, 1.0, 1.0, s)
	p.initial_velocity_max = 1.4 + 2.6 * s


func _drive_dust(p: CPUParticles3D, d: Array) -> void:
	var s: float = d[0]
	var col: Color = d[4]
	var kind: int = d[5] # 0 dirt, 1 wet spray, 2 sand
	_aim(p, (d[2] as Vector3) + Vector3.UP * 0.08, -(d[3] as Vector3))
	p.color = Color(col.r, col.g, col.b, col.a * s)
	p.gravity = Vector3(0.0, -7.0 if kind == 2 else (-4.0 if kind == 1 else -1.2), 0.0)
	p.initial_velocity_max = 2.5 + 6.0 * s


func _drive_sparks(p: CPUParticles3D, d: Array) -> void:
	var s: float = d[0]
	var dir: Vector3 = d[3]
	var n: Vector3 = d[4]
	# Sparks fly back off the contact (the way the ground moves past it) and up off the surface.
	var throw := (-dir + n * 0.35).normalized()
	var y := throw
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	p.global_transform = Transform3D(Basis(x, y, z), d[2])
	p.color = Color(1.0, 1.0, 1.0, s)
	p.initial_velocity_min = 3.0 + 4.0 * s
	p.initial_velocity_max = 6.0 + 10.0 * s


## Loop voices for the loudest demands ([priority, key, at, ...], the level at `level_at`; keys
## divided by `key_div` so one car is one voice): volume and pitch by level.
func _serve_voices(voices: Array, keys: Array, demand: Array, full_db: float, pitch0: float, pitch_k: float,
		level_at: int, key_div: int) -> void:
	var ranked := demand.duplicate()
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	var chosen := {}
	for d in ranked:
		if chosen.size() >= voices.size():
			break
		var key: int = int(d[1]) / key_div
		if not chosen.has(key):
			chosen[key] = d
	for i in voices.size():
		if keys[i] != null and not chosen.has(keys[i]):
			keys[i] = null
	for key in chosen:
		if keys.has(key):
			continue
		var slot := keys.find(null)
		if slot >= 0:
			keys[slot] = key
	for i in voices.size():
		var p: AudioStreamPlayer3D = voices[i]
		if keys[i] == null:
			if p.playing:
				p.volume_db = move_toward(p.volume_db, -60.0, 6.0)
				if p.volume_db <= -59.0:
					p.stop()
			continue
		var d: Array = chosen[keys[i]]
		var level: float = clampf(float(d[level_at]), 0.0, 1.0)
		p.global_position = d[2]
		var target := float(p.get_meta("base_db", 0.0)) + full_db + linear_to_db(maxf(level, 0.02))
		p.volume_db = target if not p.playing else lerpf(p.volume_db, target, 0.35)
		p.pitch_scale = pitch0 + pitch_k * level
		if not p.playing:
			p.play(_rng.randf() * 3.0)


## A scrape at night lights the road round it.
func _spark_glow(demand: Array) -> void:
	if _spark_light == null:
		return
	var best: Variant = null
	for d in demand:
		if best == null or d[0] > best[0]:
			best = d
	if best == null:
		_spark_light.light_energy = move_toward(_spark_light.light_energy, 0.0, 0.6)
		_spark_light.visible = _spark_light.light_energy > 0.01
		return
	_spark_light.global_position = (best[2] as Vector3) + Vector3.UP * 0.25
	var flicker := 0.6 + 0.4 * _rng.randf()
	_spark_light.light_energy = spark_light_energy * float(best[0]) * flicker
	_spark_light.visible = true


# --- Exhaust and backfire ----------------------------------------------------------------------

func _exhaust_point(car: Vehicle) -> Vector3:
	var pose: Dictionary = car._wheel_pose()
	var road := float(pose.get("y", 0.17)) - float(pose.get("r", 0.35))
	var tail := car.tail_point()
	return car.global_transform * Vector3(float(pose.get("x", 0.8)) * 0.55, road + 0.3, tail.z - 0.45)


## How cold the air is (visible condensation): early morning, night a little, wet weather more.
func _cold() -> float:
	var dn: Node = _level_node("DayNight")
	var hour := float(dn.get("hour")) if dn else 12.0
	var morning := smoothstep(4.5, 6.0, hour) * (1.0 - smoothstep(8.5, 10.5, hour))
	var night := 0.35 * (1.0 - smoothstep(5.0, 7.0, hour)) + 0.35 * smoothstep(20.0, 23.0, hour)
	return clampf(maxf(morning, night) + _wetness() * 0.4, 0.0, 1.0)


func _tick_exhaust(delta: float) -> void:
	_tick_shimmer()
	if _exhaust.is_empty():
		return
	var cold := _cold()
	var demand: Array = []
	if cold > 0.05:
		var cam := get_viewport().get_camera_3d()
		var here := cam.global_position if cam else Vector3.ZERO
		for held: Variant in _exhaust_cars:
			if not is_instance_valid(held) or not (held as Node).is_inside_tree():
				continue
			var car: Vehicle = held
			if car.is_wreck():
				continue
			var mine := _is_player_car(car)
			var idle: bool
			if car.is_traffic():
				idle = car.traffic_speed < 0.8
			else:
				idle = car.driver != null and car.linear_velocity.length() < 2.0
			if not mine and not idle:
				continue
			if not mine and not car.lights_running():
				continue
			var d := car.global_position.distance_to(here)
			if not mine and d > exhaust_reach:
				continue
			# An idle engine chugs: the puffs come in pulses.
			var pulse := 0.65 + 0.35 * sin(_clock * 9.0 + float(car.get_instance_id() % 97))
			var s := cold * (pulse if idle else 0.5)
			demand.append([s + (1.0 if mine else 0.0) - d * 0.001, car.get_instance_id(), car, s])
	demand.sort_custom(func(a, b): return a[0] > b[0])
	var chosen := {}
	for d in demand:
		if chosen.size() >= _exhaust.size():
			break
		chosen[d[1]] = d
	for i in _exhaust.size():
		if _exhaust_keys[i] != null and not chosen.has(_exhaust_keys[i]):
			_exhaust_keys[i] = null
	for key in chosen:
		if _exhaust_keys.has(key):
			continue
		var slot := _exhaust_keys.find(null)
		if slot >= 0:
			_exhaust_keys[slot] = key
	for i in _exhaust.size():
		var p := _exhaust[i]
		if _exhaust_keys[i] == null:
			if p.emitting:
				p.emitting = false
			continue
		var d: Array = chosen[_exhaust_keys[i]]
		var car: Vehicle = d[2]
		var t := car.global_transform
		p.global_transform = Transform3D(t.basis.orthonormalized(), _exhaust_point(car))
		p.color = Color(1.0, 1.0, 1.0, float(d[3]))
		if not p.emitting:
			p.emitting = true


func _tick_shimmer() -> void:
	if _shimmer == null:
		return
	var car: Vehicle = null
	for c: Variant in _cars:
		if is_instance_valid(c) and _is_player_car(c as Vehicle):
			car = c
	if car == null or car.is_wreck():
		_shimmer.visible = false
		return
	var throttle := clampf(absf(car.engine_force) / maxf(car.engine_power, 1.0), 0.0, 1.0)
	var speed := car.linear_velocity.length()
	# Hot pipes shimmer most standing or slow; at speed the haze is torn away behind the car.
	var heat := (0.35 + 0.65 * throttle) * (1.0 - smoothstep(6.0, 25.0, speed))
	_shimmer_mat.set_shader_parameter("heat", heat)
	_shimmer.global_position = _exhaust_point(car) + car.global_basis.z * 0.25
	_shimmer.visible = heat > 0.03


## A hard lift-off from full throttle at speed sometimes pops: a bang and a lick of flame.
func _tick_backfire(car: Vehicle) -> void:
	if car.driver == null:
		return
	var id := car.get_instance_id()
	var force := absf(car.engine_force)
	var before: float = _prev_force.get(id, 0.0)
	_prev_force[id] = force
	# Full throttle fades with speed (Vehicle: 0.64 of engine_power at 20 m/s), so "full" is half.
	if before < car.engine_power * 0.5 or force > car.engine_power * 0.1:
		return
	if _clock - _backfire_at < backfire_cooldown or car.linear_velocity.length() < backfire_min_speed:
		return
	if _rng.randf() > backfire_chance:
		return
	backfire(car)


## Pops the car's exhaust now (also for tests and stills).
func backfire(car: Vehicle) -> void:
	_backfire_at = _clock
	var at := _exhaust_point(car)
	Sfx.play("backfire", at, backfire_db)
	_flame.global_transform = Transform3D(car.global_basis.orthonormalized(), at)
	_flame.restart()
	_flame.emitting = true
	if _flame_light:
		_flame_light.global_position = at + car.global_basis.z * 0.4
		_flame_light.visible = true
		_flame_light.light_energy = 6.0
		var tw := _flame_light.create_tween()
		tw.tween_property(_flame_light, "light_energy", 0.0, 0.14)
		tw.tween_callback(func(): _flame_light.visible = false)


# --- Emitters ---------------------------------------------------------------------------------

static func _puff_material(albedo: Color, backlight: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = WeaponFX.puff_texture()
	mat.albedo_color = albedo
	# Lit through as well as on its face, like TyreSpray's mist: from behind the sun a puff of
	# smoke is a bright veil, not a dark smudge.
	mat.backlight_enabled = true
	mat.backlight = Color(backlight * 0.8, backlight * 0.8, backlight * 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Or every puff renders exactly one metre whatever scale_amount says (CLAUDE.md, Effects).
	mat.billboard_keep_scale = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	if not _web():
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 0.8
	return mat


static func _grow_curve(from: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, from))
	c.add_point(Vector2(0.35, lerpf(from, 1.0, 0.7)))
	c.add_point(Vector2(1.0, 1.0))
	return c


func _base_emitter(name_: String, mesh: Mesh, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = name_
	p.mesh = mesh
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.angle_min = 0.0
	p.angle_max = 360.0
	add_child(p)
	return p


func _make_smoke(mat: Material) -> CPUParticles3D:
	var quad := QuadMesh.new()
	quad.material = mat
	var p := _base_emitter("Smoke%d" % _smoke.size(), quad, smoke_puffs, smoke_life)
	p.lifetime_randomness = 0.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.22
	# Back along the slide and up, spreading wide: tyre smoke rolls out low then lifts.
	p.direction = Vector3(0.0, 0.22, 1.0)
	p.spread = 70.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0.0, 0.28, 0.0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = smoke_size.y * 0.7
	p.scale_amount_max = smoke_size.y
	p.scale_amount_curve = _grow_curve(smoke_size.x / smoke_size.y)
	p.angular_velocity_min = -25.0
	p.angular_velocity_max = 25.0
	p.color_ramp = WeaponFX._ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, smoke_alpha), Color(1, 1, 1, smoke_alpha * 0.55),
		Color(1, 1, 1, smoke_alpha * 0.22), Color(1, 1, 1, 0.0)])
	p.visibility_aabb = AABB(Vector3(-8.0, -1.0, -8.0), Vector3(16.0, 10.0, 16.0))
	return p


func _make_dust(mat: Material) -> CPUParticles3D:
	var quad := QuadMesh.new()
	quad.material = mat
	var p := _base_emitter("Dust%d" % _dust.size(), quad, 36, 1.4)
	p.lifetime_randomness = 0.35
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.2, 0.05, 0.15)
	# Thrown back off the tread and up in a rooster tail.
	p.direction = Vector3(0.0, 0.7, 1.0)
	p.spread = 28.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0.0, -1.2, 0.0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.4
	p.scale_amount_curve = _grow_curve(0.25)
	p.color_ramp = WeaponFX._ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.0)])
	p.visibility_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 8.0, 16.0))
	return p


static var _spark_mat: ShaderMaterial


func _make_sparks() -> CPUParticles3D:
	if _spark_mat == null:
		_spark_mat = ShaderMaterial.new()
		_spark_mat.shader = preload("res://shaders/spark_streak.gdshader")
	var quad := QuadMesh.new()
	quad.material = _spark_mat
	var p := _base_emitter("Sparks%d" % _sparks.size(), quad, 48, 0.5)
	p.lifetime_randomness = 0.5
	p.particle_flag_align_y = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.direction = Vector3.UP
	p.spread = 32.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.damping_min = 0.2
	p.damping_max = 1.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	# White-hot at the contact, orange, then red as it cools (linear, HDR via the shader's energy).
	p.color_ramp = WeaponFX._ramp([Color(1.0, 0.9, 0.6, 1.0), Color(1.0, 0.55, 0.15, 0.95),
		Color(0.9, 0.25, 0.05, 0.6), Color(0.5, 0.08, 0.02, 0.0)])
	p.visibility_aabb = AABB(Vector3(-6.0, -2.0, -6.0), Vector3(12.0, 6.0, 12.0))
	return p


func _make_exhaust(mat: Material) -> CPUParticles3D:
	var quad := QuadMesh.new()
	quad.material = mat
	var p := _base_emitter("Exhaust%d" % _exhaust.size(), quad, 22, 1.8)
	p.lifetime_randomness = 0.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.04
	# Out of the pipe backward (+Z is the car's rear), curling up as it cools.
	p.direction = Vector3(0.0, 0.1, 1.0)
	p.spread = 12.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0.0, 0.35, 0.0)
	p.damping_min = 1.2
	p.damping_max = 2.0
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _grow_curve(0.12)
	p.color_ramp = WeaponFX._ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.0)])
	p.visibility_aabb = AABB(Vector3(-4.0, -1.0, -4.0), Vector3(8.0, 5.0, 8.0))
	return p


func _make_flame() -> CPUParticles3D:
	var quad := QuadMesh.new()
	quad.material = WeaponFX._puff_material(true)
	var p := _base_emitter("Backfire", quad, 10, 0.14)
	p.one_shot = true
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.03
	p.direction = Vector3(0.0, 0.05, 1.0)
	p.spread = 14.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3.ZERO
	p.damping_min = 8.0
	p.damping_max = 12.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.5
	p.scale_amount_curve = _grow_curve(0.4)
	# Hot only for an instant (CLAUDE.md: a ramp held bright tonemaps to beige), green held near
	# half of red so AgX keeps it flame-coloured.
	p.color_ramp = WeaponFX._ramp([Color(3.2, 2.2, 1.0, 1.0), Color(2.2, 1.0, 0.25, 0.8), Color(0.6, 0.18, 0.05, 0.0)])
	p.visibility_aabb = AABB(Vector3(-2.0, -1.0, -2.0), Vector3(4.0, 2.0, 4.0))
	return p
