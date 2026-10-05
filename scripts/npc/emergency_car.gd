class_name EmergencyCar
extends Vehicle
## A fire engine or an ambulance answering a call (Emergency). An ordinary Vehicle - body type
## FIRE_ENGINE or AMBULANCE, Blender-built by tools/make_emergency_vehicles.py on the big
## vehicles' pipeline, so CarDamage, CarCabin, CarLights, PhysicsBudget and the pools all work as
## they do on a bus - driven by the Emergency node in three ways:
##
##   DISPATCH  on its way: kinematic along the street lanes like the traffic and the police
##             (the same lane geometry and StreetRoute routing as PoliceCar), lights and siren
##             going, running the reds, the traffic pulling over for it.
##   ON_SCENE  pulled up at the kerb nearest the scene (StreetRoute.kerb_stop): still kinematic,
##             lights on, siren off, the crew out (Emergency.deploy_crew).
##   LEAVING   job done, crew back aboard: off along the lanes, lights off, until nobody sees it
##             and Emergency pools it.
##
## Shot or blasted it goes physical like any car (Vehicle.drop_out_of_traffic) and stays where
## it ends up; Emergency puts it back on the lanes when it has to leave and can (_back_to_lanes),
## and otherwise lets it sit until nobody sees it. The player can take one: with `driver` set it
## drives like any car and Emergency lets go of it.
##
## Its warning lenses are the model's `beacon_red` / `beacon_white` slots on
## shaders/emergency_lights.gdshader (a wig-wag worked out from each lens's place on the body);
## after dark an OmniLight3D on the roof throws red on the street in step with them (desktop).

enum Kind { ENGINE, AMBULANCE }
enum Mode { DISPATCH, ON_SCENE, LEAVING }

@export_group("Emergency unit")
## Cruising speed along the lanes on a call, and leaving (m/s). Heavier than a cruiser.
@export var call_speed: float = 19.0
@export var leave_speed: float = 11.0
## How far short of the scene it pulls up (m along the kerb): an engine stands off a burning car.
@export var engine_stand_off: float = 14.0
@export var ambulance_stand_off: float = 7.0
## Pulling up at the kerb: the last this-many metres ease over from the lane (m), and how hard it
## brakes for the stop (m/s squared).
@export var kerb_approach: float = 24.0
@export var stop_brake: float = 4.5
## The lights: flash rate (cycles a second) and how bright a lit lens is (HDR).
@export var flash_rate: float = 1.35
@export var lens_energy: float = 6.0
## The roof light thrown on the street at night (desktop only).
@export var scene_light_energy: float = 2.4
@export var scene_light_range: float = 14.0
## Siren loudness and reach (m), and the air horn blown at a crossing on a call.
@export var siren_volume_db: float = -3.0
@export var siren_distance: float = 420.0
@export var horn_volume_db: float = 0.0
@export var horn_every: Vector2 = Vector2(4.0, 9.0)
@export_group("")

## The department and the service: invented names, never a real one's.
const FIRE_DEPT := "RANDO CITY FIRE DEPT"
## What fits on the cab doors and the box sides (BigVehicles' lettering).
const FIRE_DOOR := "RCFD"
const AMBULANCE_SIDE := "BASIN MEDICAL"
const AMBULANCE_SERVICE := "BASIN MEDICAL RESCUE"
## Paint: apparatus red with a white cab roof band; the ambulance white with a red stripe.
const ENGINE_RED := Color(0.62, 0.035, 0.03)
const ENGINE_WHITE := Color(0.93, 0.93, 0.91)
const AMBULANCE_WHITE := Color(0.94, 0.94, 0.93)
const AMBULANCE_RED := Color(0.72, 0.05, 0.05)
## Lens colours (linear).
const LENS_RED := Vector3(1.0, 0.03, 0.02)
const LENS_WHITE := Vector3(1.0, 0.92, 0.82)
## Retroreflective striping: gold on the engine, red on the ambulance (the `stripe` slot).
const STRIPE_ENGINE := Color(0.88, 0.70, 0.22)
const STRIPE_AMBULANCE := Color(0.72, 0.05, 0.05)

var kind: Kind = Kind.ENGINE
var service: Emergency
var mode: Mode = Mode.DISPATCH
## The call this unit answers (Emergency's incident dictionary) and where it is (true world XZ).
var incident: Dictionary = {}
var goal: Vector2 = Vector2.ZERO
## The station this unit came out of (a FireStation entry) or {} from off the map.
var station: Dictionary = {}
## Crew aboard and alive (aboard sit in the cabin glass, CarCabin).
var crew_aboard: int = 2:
	set(v):
		crew_aboard = v
		_update_occupant()
var crew_alive: int = 2
var unseen_time: float = 0.0
var unit_number: int = 0

var _plan: CityPlan
var _lens_mats: Array[ShaderMaterial] = []
var _siren: AudioStreamPlayer3D
var _light: OmniLight3D
var _phase: float = 0.0
var _day: Node
var _night: float = 0.0
var _light_t: float = 0.0
var _horn_t: float = 3.0
var _stolen: bool = false
var _dest: Dictionary = {}
var _nodes: Array[Vector2i] = []
var _route_t: float = 0.0
var _route_goal := Vector2.INF


## A new unit, set up but not in the tree: kinematic until something knocks it off the lanes.
static func make(unit_kind: Kind, rng: RandomNumberGenerator) -> EmergencyCar:
	var car := EmergencyCar.new()
	car.kind = unit_kind
	if unit_kind == Kind.ENGINE:
		car.setup(BodyType.FIRE_ENGINE, ENGINE_RED, Addon.NONE)
		car.setup_look(Finish.GLOSS, Livery.NONE, ENGINE_WHITE)
		car.crew_aboard = 3
		car.set_meta("fleet", FIRE_DOOR)
	else:
		car.setup(BodyType.AMBULANCE, AMBULANCE_WHITE, Addon.NONE)
		car.setup_look(Finish.GLOSS, Livery.NONE, AMBULANCE_RED)
		car.crew_aboard = 2
		car.set_meta("fleet", AMBULANCE_SIDE)
	car.crew_alive = car.crew_aboard
	car.wheel_style = 0
	car.wheel_kit = 0 if unit_kind == Kind.ENGINE else 1
	car._phase = rng.randf()
	car.unit_number = 1 + rng.randi() % 99
	car.traffic = {"emergency": true, "axis": 0, "index": 0, "dir": 1, "lane": 0.0}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	return car


func _ready() -> void:
	super._ready()
	add_to_group("emergency_unit")
	set_meta("emergency", true)
	_wire_lenses()
	_siren = Sfx.loop_player("siren_yelp" if kind == Kind.AMBULANCE else "siren", siren_volume_db)
	_siren.max_distance = siren_distance
	_siren.unit_size = 34.0
	_siren.pitch_scale = (0.92 if kind == Kind.ENGINE else 1.0) + 0.05 * _phase
	add_child(_siren)
	if not OS.has_feature("web"):
		_light = OmniLight3D.new()
		_light.name = "SceneLight"
		_light.omni_range = scene_light_range
		_light.light_energy = 0.0
		_light.shadow_enabled = false
		_light.distance_fade_enabled = true
		_light.distance_fade_begin = 90.0
		_light.distance_fade_length = 30.0
		_light.position = Vector3(0.0, _model_top_y + 0.4 if _has_model else 3.2, -float(_dims().length) * 0.3)
		_light.visible = false
		add_child(_light)


## The paint is the body's one colour (apparatus red, ambulance white): the striping is modelled
## (the `stripe` slot), so no livery band is painted over it.
func _paint_material(albedo: Texture2D, normal: Texture2D) -> ShaderMaterial:
	var mat := super._paint_material(albedo, normal)
	mat.set_shader_parameter("stripe_mode", 0)
	return mat


## The body model's warning lenses onto the flashing shader, and the striping onto its
## retroreflective look. Done once the model is in (Vehicle._build from super._ready).
func _wire_lenses() -> void:
	var shader: Shader = load("res://shaders/emergency_lights.gdshader")
	var mats := {}
	var stripe_mat: StandardMaterial3D = null
	for m in _body_meshes:
		if not is_instance_valid(m) or m.mesh == null:
			continue
		var box := m.mesh.get_aabb()
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			if src == null:
				continue
			var nm := String(src.resource_name)
			if nm.begins_with("beacon"):
				var red := nm.begins_with("beacon_red")
				var key := "%s_%d" % [nm, m.get_instance_id()]
				if not mats.has(key):
					var mat := ShaderMaterial.new()
					mat.shader = shader
					mat.set_shader_parameter("lens_color", LENS_RED if red else LENS_WHITE)
					mat.set_shader_parameter("rate", flash_rate)
					mat.set_shader_parameter("phase", _phase)
					mat.set_shader_parameter("energy", lens_energy * (1.0 if red else 0.8))
					mat.set_shader_parameter("duty", 0.11 if red else 0.07)
					# The model's long axis is its longest horizontal one.
					var along_x := box.size.x > box.size.z
					mat.set_shader_parameter("along_axis", Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1))
					mat.set_shader_parameter("along_mid", box.get_center().x if along_x else box.get_center().z)
					mat.set_shader_parameter("across_axis", Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0))
					mat.set_shader_parameter("across_mid", box.get_center().z if along_x else box.get_center().x)
					mats[key] = mat
					_lens_mats.append(mat)
				m.set_surface_override_material(si, mats[key])
			elif nm.begins_with("stripe"):
				if stripe_mat == null:
					stripe_mat = StandardMaterial3D.new()
					stripe_mat.albedo_color = STRIPE_ENGINE if kind == Kind.ENGINE else STRIPE_AMBULANCE
					stripe_mat.roughness = 0.35
					stripe_mat.metallic_specular = 0.7
					# Sheeting glows back at a light: a touch of its own colour after dark is what a
					# headlight finds (the lamp_factor glint of the freeway signs, cheaply).
					stripe_mat.emission_enabled = true
					stripe_mat.emission = stripe_mat.albedo_color
					stripe_mat.emission_energy_multiplier = 0.0
				m.set_surface_override_material(si, stripe_mat)
	if stripe_mat != null:
		set_meta("stripe_mat", stripe_mat)


# --- Lights and sound -------------------------------------------------------------------------

func _process(delta: float) -> void:
	_light_t -= delta
	if _light_t <= 0.0:
		_light_t = 0.5
		_night = _night_level()
		var sm: StandardMaterial3D = get_meta("stripe_mat", null)
		if sm:
			sm.emission_energy_multiplier = 0.35 * _night
	var lit := lights_running_emergency()
	for m in _lens_mats:
		m.set_shader_parameter("lights_on", 1.0 if lit else 0.0)
	if _light:
		var show := lit and _night > 0.05
		_light.visible = show
		if show:
			var t := fposmod(Time.get_ticks_msec() / 1000.0 * flash_rate + _phase, 1.0)
			var on := fposmod(t, 0.5) < 0.2
			_light.light_energy = scene_light_energy * _night * (1.0 if on else 0.15)
			_light.light_color = Color(1.0, 0.1, 0.06) if t < 0.5 else Color(1.0, 0.85, 0.75)
	var wail := siren_running()
	if _siren and wail != _siren.playing:
		if wail:
			_siren.play()
		else:
			_siren.stop()
	if wail and kind == Kind.ENGINE:
		_horn_t -= delta
		if _horn_t <= 0.0:
			_horn_t = randf_range(horn_every.x, horn_every.y)
			Sfx.play("fire_horn", global_position + Vector3.UP * 1.2, horn_volume_db)


## The warning lights: on a call and on scene, not leaving, not burnt out, not the player's.
func lights_running_emergency() -> bool:
	if is_wreck():
		return false
	if _stolen:
		return driver != null
	return service != null and mode != Mode.LEAVING


## True while the siren is going (the traffic pulls over for it, TrafficManager._siren_list).
func siren_running() -> bool:
	return service != null and driver == null and mode == Mode.DISPATCH and is_traffic() and not is_wreck()


func _night_level() -> float:
	if _day == null or not is_instance_valid(_day):
		var scene := get_tree().current_scene
		_day = scene.get_node_or_null("DayNight") if scene else null
	if _day == null:
		return 0.0
	return maxf(float(_day.get("night_factor")), float(_day.get("weather_darken")) * 0.85)


## The crew sit in the cabin glass while aboard (driver and officer up front).
func _cabin_seats() -> int:
	if driver != null:
		return 1
	if _abandoned() or crew_aboard <= 0:
		return 0
	return 3 if crew_aboard >= 2 else 1


func _cabin_look() -> Dictionary:
	if driver != null:
		return CarCabin.player_look()
	return CarCabin.npc_look(hash([_phase, 77]))


# --- Driving ----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if driver != null:
		if not _stolen:
			_stolen = true
			if service:
				service.unit_stolen(self)
		super._physics_process(delta)
		return
	if is_traffic():
		match mode:
			Mode.DISPATCH, Mode.LEAVING:
				_drive_lane(delta)
			_:
				traffic_speed = 0.0
		_update_wheels(delta)
		return
	super._physics_process(delta)


## Kept running while it drives itself, whatever PhysicsBudget's distance rule says.
func set_script_active(on: bool) -> void:
	super.set_script_active(on or (service != null and driver == null and mode != Mode.ON_SCENE))


## Starts it on a lane: `axis` / `index` the road, `dir` the direction along it.
func begin_drive(plan: CityPlan, axis: int, index: int, dir: int, speed: float) -> void:
	_plan = plan
	traffic = {"emergency": true, "axis": axis, "index": index, "dir": dir, "lane": _lane_offset(axis, index, dir)}
	traffic_speed = speed
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_mask = _mask()
	_clear_route()


func _clear_route() -> void:
	_dest = {}
	_nodes.clear()
	_route_t = 0.0
	_route_goal = Vector2.INF


## The inside lane on the right-hand side of the road.
func _lane_offset(axis: int, index: int, dir: int) -> float:
	var width := _plan.road_width(axis, index)
	var lanes := 2 if width > _plan.street_width + 1.0 else 1
	var side := -dir if axis == CityPlan.AXIS_X else dir
	return side * CityPlan.lane_center(width, lanes, 0)


static func heading(axis: int, dir: int) -> float:
	var d := Vector3(0.0, 0.0, dir) if axis == CityPlan.AXIS_X else Vector3(dir, 0.0, 0.0)
	return atan2(-d.x, -d.z)


## Lane driving, PoliceCar._drive_lane()'s geometry: the turn at each crossing from the route
## (StreetRoute) to `goal`, every red run with the siren going; on a call it eases over to the
## kerb on the last stretch and pulls up there (ON_SCENE); leaving it just drives away.
func _drive_lane(delta: float) -> void:
	if _plan == null:
		return
	var t: Dictionary = traffic
	var axis: int = t.axis
	var dir: int = t.dir
	var index: int = t.index
	var wp := WorldState.to_world(global_position)
	var along := wp.z if axis == CityPlan.AXIS_X else wp.x
	var calling := mode == Mode.DISPATCH
	var stand := engine_stand_off if kind == Kind.ENGINE else ambulance_stand_off
	_route_update(goal, [axis, index, dir], along, delta, calling, stand)
	var cruise := call_speed if calling else leave_speed
	var lateral: float = t.lane
	var to_stop := INF
	if calling and _on_dest(axis, index, dir):
		to_stop = (float(_dest.along) - along) * float(dir)
		if to_stop > -2.0 and to_stop < 150.0:
			cruise = minf(cruise, sqrt(2.0 * stop_brake * maxf(to_stop, 0.0)) + 0.3)
			var ease := clampf(1.0 - to_stop / kerb_approach, 0.0, 1.0)
			lateral = lerpf(float(t.lane), float(_dest.lateral), smoothstep(0.0, 1.0, ease))
			if to_stop < 0.5:
				_arrive(lateral)
				return
		else:
			to_stop = INF
	traffic_speed = move_toward(traffic_speed, cruise, (5.0 if cruise > traffic_speed else 9.0) * delta)
	var cross_axis := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var cross_index := _plan._index_at(cross_axis, along) + (1 if dir > 0 else 0)
	var cross_pos := _plan.road_pos(cross_axis, cross_index)
	var step := traffic_speed * delta
	if to_stop < INF:
		step = minf(step, maxf(to_stop, 0.0) + 0.02)
	var new_along := along + dir * step
	if (dir > 0 and new_along >= cross_pos) or (dir < 0 and new_along <= cross_pos):
		var node := Vector2i(index, cross_index) if axis == CityPlan.AXIS_X else Vector2i(cross_index, index)
		var turn := _route_turn(axis, index, dir, node)
		if turn.is_empty():
			turn = _choose_turn(axis, index, dir, cross_axis, cross_index, wp)
		elif int(turn[0]) == axis and int(turn[1]) == index and int(turn[2]) == dir:
			turn = []
		if not turn.is_empty():
			var n_axis: int = turn[0]
			var n_index: int = turn[1]
			var n_dir: int = turn[2]
			t.axis = n_axis
			t.index = n_index
			t.dir = n_dir
			t.lane = _lane_offset(n_axis, n_index, n_dir)
			var road := _plan.road_pos(n_axis, n_index)
			var lane: float = t.lane
			var at: Vector2
			if n_axis == axis:
				at = Vector2(road + lane, cross_pos) if axis == CityPlan.AXIS_X else Vector2(cross_pos, road + lane)
			else:
				at = Vector2(road + lane, wp.z) if n_axis == CityPlan.AXIS_X else Vector2(wp.x, road + lane)
			# A heavy unit takes a corner slower than a cruiser.
			traffic_speed = minf(traffic_speed, 9.0)
			_place(Vector3(at.x, _relief(at) + CityChunk.ROAD_TOP + road_lift(), at.y), heading(n_axis, n_dir), 0.0)
			return
	var lane_pos: float = _plan.road_pos(axis, index) + lateral
	var p2 := Vector2(lane_pos, new_along) if axis == CityPlan.AXIS_X else Vector2(new_along, lane_pos)
	var forward := Vector2(0.0, dir) if axis == CityPlan.AXIS_X else Vector2(dir, 0.0)
	var here := _relief(p2)
	var ahead := _relief(p2 + forward * 4.0)
	_place(Vector3(p2.x, here + CityChunk.ROAD_TOP + road_lift(), p2.y), heading(axis, dir), atan2(ahead - here, 4.0))


## Pulled up at the kerb: stays on the lanes (kinematic, standing), lights on, crew out.
func _arrive(lateral: float) -> void:
	traffic_speed = 0.0
	traffic.lane = lateral
	mode = Mode.ON_SCENE
	if service:
		service.unit_arrived(self)


func _on_dest(axis: int, index: int, dir: int) -> bool:
	return not _dest.is_empty() and axis == int(_dest.axis) and index == int(_dest.index) and dir == int(_dest.dir)


## PoliceCar._route_update(): where to pull up for `goal2` and the junctions on the way.
func _route_update(goal2: Vector2, road: Array, along: float, delta: float, stop: bool, stand: float) -> void:
	_route_t -= delta
	if _route_t > 0.0 and goal2.distance_to(_route_goal) < 10.0:
		return
	_route_t = 0.6
	_route_goal = goal2
	_dest = StreetRoute.kerb_stop(_plan, goal2, stand if stop else 0.0)
	_nodes.clear()
	if _dest.is_empty():
		return
	if _on_dest(int(road[0]), int(road[1]), int(road[2])) and (float(_dest.along) - along) * float(road[2]) > 0.0:
		var ahead := StreetRoute.next_node(_plan, int(road[0]), int(road[1]), int(road[2]), along)
		var exit_along := _plan.road_pos(CityPlan.AXIS_Z if int(road[0]) == CityPlan.AXIS_X else CityPlan.AXIS_X, ahead.y if int(road[0]) == CityPlan.AXIS_X else ahead.x)
		if (exit_along - float(_dest.along)) * float(road[2]) > 0.0:
			return
	var start := StreetRoute.next_node(_plan, int(road[0]), int(road[1]), int(road[2]), along)
	_nodes = StreetRoute.path(_plan, start, _dest.entry, road, [_dest.axis, _dest.index, _dest.dir])


func _route_turn(axis: int, index: int, dir: int, node: Vector2i) -> Array:
	if _dest.is_empty():
		return []
	var node_along := _plan.road_pos(CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X, node.y if axis == CityPlan.AXIS_X else node.x)
	if _on_dest(axis, index, dir) and (float(_dest.along) - node_along) * float(dir) > 0.0:
		return [axis, index, dir]
	if node == _dest.entry:
		return [int(_dest.axis), int(_dest.index), int(_dest.dir)]
	var k := _nodes.find(node)
	if k < 0 or k + 1 >= _nodes.size():
		_nodes = StreetRoute.path(_plan, node, _dest.entry, [axis, index, dir], [_dest.axis, _dest.index, _dest.dir])
		k = 0
		if _nodes.size() < 2:
			return []
	return StreetRoute.edge(node, _nodes[k + 1])


## No route: toward the goal at the next crossing, never out of the city grid.
func _choose_turn(axis: int, index: int, dir: int, cross_axis: int, cross_index: int, wp: Vector3) -> Array:
	var here := Vector2(wp.x, wp.z)
	var to := goal - here
	var d_along := to.y if axis == CityPlan.AXIS_X else to.x
	var d_cross := to.x if axis == CityPlan.AXIS_X else to.y
	var ahead := d_along * float(dir)
	var cross_pos := _plan.road_pos(cross_axis, cross_index)
	var node := Vector2(_plan.road_pos(axis, index), cross_pos) if axis == CityPlan.AXIS_X else Vector2(cross_pos, _plan.road_pos(axis, index))
	var straight_ok := _drivable(node, axis, dir)
	if absf(d_cross) > 30.0 and (ahead < 45.0 or absf(d_cross) > absf(d_along)):
		var side := 1 if d_cross > 0.0 else -1
		if _drivable(node, cross_axis, side):
			return [cross_axis, cross_index, side]
	if ahead < -30.0 or not straight_ok:
		if absf(d_cross) > 8.0:
			var side2 := 1 if d_cross > 0.0 else -1
			if _drivable(node, cross_axis, side2):
				return [cross_axis, cross_index, side2]
		return [axis, index, -dir]
	return []


func _drivable(node: Vector2, axis: int, dir: int) -> bool:
	var step := Vector2(0.0, dir) if axis == CityPlan.AXIS_X else Vector2(dir, 0.0)
	for d: float in [30.0, 70.0]:
		var z := _plan.zone_at(node + step * d)
		if z != MacroMap.Zone.CITY and z != MacroMap.Zone.BEACH:
			return false
	var coord := node.x if axis == CityPlan.AXIS_X else node.y
	var along := (node.y if axis == CityPlan.AXIS_X else node.x) + float(dir) * 18.0
	return _plan.road_open_at(axis, coord, along)


func _place(world: Vector3, yaw: float, pitch: float) -> void:
	global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), WorldState.to_local(world))


func _relief(p: Vector2) -> float:
	if service and service.traffic:
		return service.traffic._relief(p)
	return _plan.macro.relief_at(p) if _plan and _plan.macro else 0.0


## Off on its way with its crew back aboard: along the lanes if it is still on them, put back on
## the nearest lane if it was knocked off them and stands upright and still, otherwise nowhere
## (Emergency retires it once nobody sees it).
func leave(away: Vector2) -> void:
	mode = Mode.LEAVING
	goal = away
	_clear_route()
	if not is_traffic():
		_back_to_lanes()


func _back_to_lanes() -> bool:
	if _plan == null or global_basis.y.y < 0.9 or linear_velocity.length() > 1.0 or is_wreck():
		return false
	var wp := WorldState.to_world(global_position)
	var fwd := -global_basis.z
	var road := StreetRoute.locate(_plan, Vector2(wp.x, wp.z), Vector2(fwd.x, fwd.z))
	if road.is_empty():
		return false
	# Wheels off before it is frozen again: a frozen VehicleBody3D with wheels is NaN.
	for w in wheels:
		if is_instance_valid(w):
			remove_child(w)
			w.free()
	wheels.clear()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	engine_force = 0.0
	begin_drive(_plan, int(road.axis), int(road.index), int(road.dir), 0.0)
	return true


## Taken off the street for reuse: a wheel-less kinematic body, nothing playing, as new.
func strip_for_pool() -> void:
	repair()
	if _siren:
		_siren.stop()
	for w in wheels:
		if is_instance_valid(w):
			remove_child(w)
			w.free()
	wheels.clear()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	engine_force = 0.0
	traffic = {"emergency": true, "axis": 0, "index": 0, "dir": 1, "lane": 0.0}
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_mask = _mask()
	crew_aboard = 3 if kind == Kind.ENGINE else 2
	crew_alive = crew_aboard
	incident = {}
	station = {}
	unseen_time = 0.0
	_stolen = false
	_clear_route()
	mode = Mode.DISPATCH


## Burnt out: the lights and siren die and Emergency lets it go.
func _become_wreck() -> void:
	super._become_wreck()
	if _siren:
		_siren.stop()
	if _light:
		_light.visible = false
	if service:
		service.unit_lost(self)

