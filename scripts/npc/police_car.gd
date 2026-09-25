class_name PoliceCar
extends Vehicle
## A police cruiser (owner, 2026-09-24: "a police and star system"). An ordinary Vehicle in a
## black-and-white livery (car_paint.gdshader stripe_mode 5) with a flashing red and blue light
## bar and a siren, driven by the Police node in three ways:
##
##   DISPATCH  on its way in: kinematic along the street lanes, exactly the way traffic drives,
##             turning at each crossing toward its goal. Robust at any range, costs no physics.
##   PURSUE    within `engage_range` of a player the police can see: real VehicleBody3D physics,
##             steering at the player, ramming a car, backing out when it gets stuck.
##   STOPPED / PARKED  braking near the player, then standing as cover while the crew is out.
##
## The handover is the one traffic uses (a kinematic car has no VehicleWheel3D; the wheels go on
## when it goes physical - CLAUDE.md), and it is never frozen with wheels on. The player can take
## one: with `driver` set it drives like any car and the police AI lets go of it.

enum Mode { DISPATCH, PURSUE, STOPPED, PARKED, LEAVING }

@export_group("Police car")
## Cruising speed on the way in, along the lanes (m/s).
@export var dispatch_speed: float = 24.0
## Top speed while chasing under physics (m/s).
@export var pursuit_speed: float = 30.0
## How hard the cruiser steers toward its target (steering per radian of heading error).
@export var steer_gain: float = 1.8
## Within this distance of a player the police can see, the cruiser leaves the lanes and
## drives straight at them under physics (m).
@export var engage_range: float = 70.0
## A player on foot: the cruiser stops this far away and the crew gets out (m).
@export var stop_distance: float = 13.0
## A player in a car is rammed: the cruiser aims this many seconds ahead of the car.
@export var ram_lead: float = 0.35
## Damage a cruiser does to a player on foot it runs into.
@export var ram_damage: float = 30.0
## Seconds without progress before the cruiser backs up and tries again, and how long it backs.
@export var stuck_seconds: float = 1.4
@export var reverse_seconds: float = 1.1
## Light bar flash rate (flash cycles per second) and how bright the lit lenses are (HDR).
@export var flash_rate: float = 1.6
@export var lens_energy: float = 4.0
## The light bar's glow on the street at night: OmniLight3D energy and range (desktop only).
@export var bar_light_energy: float = 2.6
@export var bar_light_range: float = 12.0
## Siren loudness (dB) and how far it carries (m). A siren is meant to be heard blocks away.
@export var siren_volume_db: float = -3.0
@export var siren_distance: float = 420.0
@export_group("Routing")
## The route (StreetRoute) is worked out again this often (s), or at once when the goal moves
## more than `route_moved` metres.
@export var route_interval: float = 0.5
@export var route_moved: float = 10.0
## Under physics, a cruiser rams a player's car straight on only inside this range with a clear
## line; further out it drives the streets like everyone else (m).
@export var ram_range: float = 35.0
## Speed through a right-angle turn and through a U-turn under physics, and how hard it brakes
## for them (m/s, m/s squared).
@export var corner_speed: float = 9.0
@export var u_turn_speed: float = 4.0
@export var route_brake: float = 7.0
## How far ahead along the route a physics cruiser aims (m, at walking pace and at full chase).
@export var look_ahead: Vector2 = Vector2(6.0, 16.0)
## Pulling up at the kerb: the last this-many metres ease over from the lane (m).
@export var kerb_approach: float = 26.0

## Paint: gloss black with white doors and roof.
const POLICE_BLACK := Color(0.030, 0.031, 0.036)
const POLICE_WHITE := Color(0.93, 0.93, 0.92)
## The tactical van at five stars: dark navy all over with a white belt band.
const HEAVY_PAINT := Color(0.045, 0.060, 0.095)
## Livery bands along the car (fractions of its length from the nose): the doors between them
## are white. The sedan's own door cuts, as tools/make_hifi_sedan.py prints them.
const DOOR_BAND := Vector2(0.301, 0.723)

var police: Police
var mode: Mode = Mode.DISPATCH
## Where the cruiser is heading (true world XZ), set by the Police node.
var goal: Vector2 = Vector2.ZERO
## Officers inside, and still alive (in the car or out of it).
var crew_aboard: int = 2
var crew_alive: int = 2
## Five-star tactical unit: a van, three officers with carbines.
var heavy: bool = false
## The crew has been told to get back in (Police sets it, officers read it).
var recall_crew: bool = false
## Part of a roadblock: parked across the street from the start, never chases.
var roadblock: bool = false
## Seconds since this cruiser was on screen (the Police node retires the ones nobody sees).
var unseen_time: float = 0.0

var _plan: CityPlan
var _siren: AudioStreamPlayer3D
var _bar_light: OmniLight3D
var _bar_mat: ShaderMaterial
var _phase: float = 0.0
var _stuck_t: float = 0.0
var _stuck_count: int = 0
var _reverse_t: float = 0.0
var _flip_t: float = 0.0
var _stopped_t: float = 0.0
var _stolen: bool = false
var _day: Node
var _light_timer: float = 0.0
var _night: float = 0.0
static var _bar_mesh: Mesh
## The route: where to pull up (StreetRoute.kerb_stop), the junctions on the way from the next
## one (ending at the stretch the stop is on), and under physics the lane polyline steered along.
var _dest: Dictionary = {}
var _nodes: Array[Vector2i] = []
var _path_pts: PackedVector2Array = PackedVector2Array()
var _path_i: int = 0
var _route_t: float = 0.0
var _route_goal := Vector2.INF
## Where the route is going and whether the car should stop there (a kerb by a player on foot)
## or only pass through (a search point, a player in a car).
var _stop_at_dest: bool = false


## A new cruiser, set up but not yet in the tree. `rng` picks the phase of its lights so a row of
## cruisers does not flash in step.
static func make(is_heavy: bool, rng: RandomNumberGenerator) -> PoliceCar:
	var car := PoliceCar.new()
	car.heavy = is_heavy
	if is_heavy:
		car.setup(BodyType.VAN, HEAVY_PAINT, Addon.NONE)
		car.setup_look(Finish.GLOSS, Livery.NONE, POLICE_WHITE)
		car.crew_aboard = 3
	else:
		car.setup(BodyType.SEDAN, POLICE_BLACK, Addon.NONE)
		car.setup_look(Finish.GLOSS, Livery.NONE, POLICE_WHITE)
		car.crew_aboard = 2
	car.crew_alive = car.crew_aboard
	car.wheel_style = 0
	car.wheel_kit = 0
	car._phase = rng.randf()
	# Kinematic until it engages: a car that joins the tree with `traffic` set gets no
	# VehicleWheel3D, which a frozen body must never have.
	car.traffic = {"police": true, "axis": 0, "index": 0, "dir": 1, "lane": 0.0}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	return car


func _ready() -> void:
	super._ready()
	add_to_group("police_car")
	set_meta("police", true)
	# Heavier and stronger than a street car, so it wins a shove and a ram does something.
	mass = 1900.0 if heavy else 1500.0
	engine_power = 9500.0 if heavy else 8200.0
	_build_light_bar()
	_siren = Sfx.loop_player("siren", siren_volume_db)
	_siren.max_distance = siren_distance
	_siren.unit_size = 34.0
	_siren.pitch_scale = 0.97 + 0.06 * _phase
	add_child(_siren)


## The livery: the base paint is black, the white is the shader's second colour, laid over the
## doors and the roof (car_paint.gdshader, stripe_mode 5). The van wears a belt band instead.
func _paint_material(albedo: Texture2D, normal: Texture2D) -> ShaderMaterial:
	var mat := super._paint_material(albedo, normal)
	mat.set_shader_parameter("stripe_color", POLICE_WHITE)
	if heavy:
		mat.set_shader_parameter("stripe_mode", 3)
		mat.set_shader_parameter("stripe_width", 0.05)
		mat.set_shader_parameter("stripe_height", 0.47)
	else:
		mat.set_shader_parameter("stripe_mode", 5)
		mat.set_shader_parameter("door_band", DOOR_BAND)
		mat.set_shader_parameter("roof_from", 0.84)
	return mat


# --- Light bar -------------------------------------------------------------------------------

## The bar on the roof: a dark housing with red lenses on the driver's side and blue on the
## other, one mesh with the colours in the vertex colour (the alpha says which bank a lens is
## in), flashed by shaders/police_lights.gdshader. One draw per cruiser. At night an OmniLight3D
## over it throws the colour on the street, switched in step with the lenses.
func _build_light_bar() -> void:
	var dims := _dims()
	var top := _model_top_y if _has_model else 0.55 + float(dims.chassis_h) + float(dims.cabin_h)
	var length: float = dims.length
	var bar := MeshInstance3D.new()
	bar.name = "LightBar"
	bar.mesh = light_bar_mesh()
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = load("res://shaders/police_lights.gdshader")
	_bar_mat.set_shader_parameter("rate", flash_rate)
	_bar_mat.set_shader_parameter("phase", _phase)
	_bar_mat.set_shader_parameter("energy", lens_energy)
	bar.material_override = _bar_mat
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.visibility_range_end = 260.0
	# Just behind the middle of the car, where every model's roof is (see _add_livery_props).
	bar.position = Vector3(0.0, top - 0.02, length * 0.05)
	if heavy:
		bar.position.z = -length * 0.28
		bar.scale = Vector3(1.25, 1.0, 1.0)
	add_child(bar)
	if not OS.has_feature("web"):
		_bar_light = OmniLight3D.new()
		_bar_light.name = "BarLight"
		_bar_light.omni_range = bar_light_range
		_bar_light.light_energy = 0.0
		_bar_light.shadow_enabled = false
		_bar_light.distance_fade_enabled = true
		_bar_light.distance_fade_begin = 90.0
		_bar_light.distance_fade_length = 30.0
		_bar_light.position = bar.position + Vector3(0.0, 0.35, 0.0)
		_bar_light.visible = false
		add_child(_bar_light)


## Housing plus six lenses, 1.2 m across, built once and shared by every cruiser.
static func light_bar_mesh() -> Mesh:
	if _bar_mesh != null:
		return _bar_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var housing := Color(0.07, 0.07, 0.075, 0.0)
	_bar_box(st, Vector3(0.0, 0.04, 0.0), Vector3(1.22, 0.07, 0.30), housing)
	_bar_box(st, Vector3(0.0, 0.004, 0.0), Vector3(0.9, 0.02, 0.2), housing)
	for i in 6:
		var x := -0.51 + 0.204 * float(i)
		# The two in the middle are white takedown lamps in the housing's colour group, so they
		# stay dark: a lit centre reads as a taxi sign.
		var col := Color(1.0, 0.06, 0.04, 0.5) if i < 3 else Color(0.10, 0.26, 1.0, 1.0)
		_bar_box(st, Vector3(x, 0.115, 0.0), Vector3(0.18, 0.085, 0.27), col)
	st.generate_normals()
	_bar_mesh = st.commit()
	return _bar_mesh


static func _bar_box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	# Clockwise seen from outside (the project's winding), so generate_normals points out.
	for f: Array in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(p[f[k]])


## Which bank of the bar is lit right now: 1 red, -1 blue, 0 dark. The same pattern the shader
## draws (two quick strobes a side), so the light on the street matches the lenses.
func flash_side(t: float) -> int:
	var f := fposmod(t * flash_rate + _phase, 1.0)
	if (f < 0.09) or (f > 0.15 and f < 0.24):
		return 1
	if (f > 0.5 and f < 0.59) or (f > 0.65 and f < 0.74):
		return -1
	return 0


func _process(delta: float) -> void:
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.5
		_night = _night_level()
	var lit := _lights_on()
	if _bar_mat:
		_bar_mat.set_shader_parameter("lights_on", 1.0 if lit else 0.0)
	if _bar_light:
		var show := lit and _night > 0.05
		_bar_light.visible = show
		if show:
			var side := flash_side(Time.get_ticks_msec() / 1000.0)
			_bar_light.light_energy = bar_light_energy * _night * (1.0 if side != 0 else 0.0)
			_bar_light.light_color = Color(1.0, 0.12, 0.08) if side > 0 else Color(0.15, 0.3, 1.0)
	var wail := _siren_on()
	if _siren and wail != _siren.playing:
		if wail:
			_siren.play()
		else:
			_siren.stop()


func _lights_on() -> bool:
	return police != null and (police.stars > 0 or mode != Mode.LEAVING) and crew_alive > 0 or _stolen


## True while the siren is going (TrafficManager pulls cars over for it).
func siren_running() -> bool:
	return _siren_on()


func _siren_on() -> bool:
	return police != null and police.stars > 0 and driver == null and crew_alive > 0 \
			and (mode == Mode.DISPATCH or mode == Mode.PURSUE) and not roadblock


## How dark it is (0 day .. 1 night), from the DayNight node the lamps follow.
func _night_level() -> float:
	if _day == null or not is_instance_valid(_day):
		var scene := get_tree().current_scene
		_day = scene.get_node_or_null("DayNight") if scene else null
	if _day == null:
		return 0.0
	return maxf(float(_day.get("night_factor")), float(_day.get("weather_darken")) * 0.85)


# --- Driving -----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if driver != null:
		if not _stolen:
			_stolen = true
			if police:
				police.cruiser_stolen(self)
		super._physics_process(delta)
		return
	match mode:
		Mode.DISPATCH, Mode.LEAVING:
			if is_traffic():
				_drive_lane(delta)
				_update_wheels(delta)
			else:
				_update_wheels(delta)
				_pursue(delta)
		Mode.PURSUE:
			_update_wheels(delta)
			_pursue(delta)
		Mode.STOPPED:
			_update_wheels(delta)
			_brake_to_stop(delta)
		_:
			super._physics_process(delta)


## Kept running while the police drive it, whatever PhysicsBudget's distance rule says: a car
## on its way in from 200 m out is the one that most needs its script.
func set_script_active(on: bool) -> void:
	super.set_script_active(on or (police != null and driver == null and (mode == Mode.DISPATCH or mode == Mode.PURSUE or mode == Mode.LEAVING)))


## Never put to sleep while it is chasing.
func settle() -> void:
	if mode == Mode.PURSUE or mode == Mode.STOPPED:
		return
	super.settle()


## Starts it on a lane: `axis` / `index` name the road (CityPlan), `dir` the direction along it.
func begin_dispatch(plan: CityPlan, axis: int, index: int, dir: int, speed: float) -> void:
	_plan = plan
	traffic = {"police": true, "axis": axis, "index": index, "dir": dir, "lane": _lane_offset(axis, index, dir)}
	traffic_speed = speed
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_mask = _mask()
	mode = Mode.DISPATCH
	_clear_route()


## Forgets the route (a new dispatch, a trip back to the pool).
func _clear_route() -> void:
	_dest = {}
	_nodes.clear()
	_path_pts = PackedVector2Array()
	_path_i = 0
	_route_t = 0.0
	_route_goal = Vector2.INF
	_stop_at_dest = false


## The inside lane on the right-hand side of the road (the lane nearest the centre line).
func _lane_offset(axis: int, index: int, dir: int) -> float:
	var width := _plan.road_width(axis, index)
	var lanes := 2 if width > _plan.street_width + 1.0 else 1
	var side := -dir if axis == CityPlan.AXIS_X else dir
	return side * CityPlan.lane_center(width, lanes, 0)


func _heading(axis: int, dir: int) -> float:
	var d := Vector3(0.0, 0.0, dir) if axis == CityPlan.AXIS_X else Vector3(dir, 0.0, 0.0)
	return atan2(-d.x, -d.z)


## Lane driving, the same geometry as the traffic's (TrafficManager._drive_street()), with the
## turn at each crossing taken from the route (StreetRoute) to `goal`, running every red with the
## siren going. A player in a car close enough is engaged under physics; for a player on foot the
## cruiser stays on the lanes to the kerb nearest them and pulls up there.
func _drive_lane(delta: float) -> void:
	if _plan == null:
		return
	var t: Dictionary = traffic
	var axis: int = t.axis
	var dir: int = t.dir
	var index: int = t.index
	var wp := WorldState.to_world(global_position)
	if police and mode == Mode.DISPATCH and police.player_known() and police.player_driving():
		var pp: Vector3 = police.player_world()
		if Vector2(pp.x - wp.x, pp.z - wp.z).length() < engage_range:
			go_physical()
			return
	var along := wp.z if axis == CityPlan.AXIS_X else wp.x
	var known := police != null and police.player_known()
	var on_foot := police != null and not police.player_driving()
	_route_update(goal, [axis, index, dir], along, delta, mode == Mode.DISPATCH and known and on_foot)
	var cruise := dispatch_speed * (0.6 if mode == Mode.LEAVING else 1.0)
	var lateral: float = t.lane
	# On the stretch the stop is on and short of it: slow, ease over to the kerb, pull up.
	var to_stop := INF
	if _stop_at_dest and _on_dest(axis, index, dir):
		to_stop = (float(_dest.along) - along) * float(dir)
		# Kept on the lanes all the way to the kerb point, and only handed to physics there
		# (_pull_up()). Handing over on the last straight instead was tried: in a city already
		# strewn with wrecks and bodies the physics approach got knocked off the road and stuck
		# 60 m short, where the lanes cannot be.
		if to_stop > -2.0 and to_stop < 150.0:
			cruise = minf(cruise, sqrt(2.0 * route_brake * 0.75 * maxf(to_stop, 0.0)) + 0.4)
			var ease := clampf(1.0 - to_stop / kerb_approach, 0.0, 1.0)
			lateral = lerpf(float(t.lane), float(_dest.lateral), smoothstep(0.0, 1.0, ease))
			if to_stop < 0.6:
				_pull_up()
				return
		else:
			to_stop = INF
	traffic_speed = move_toward(traffic_speed, cruise, (10.0 if cruise > traffic_speed else 16.0) * delta)
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
				# A U-turn: same road, the other carriageway, at the crossing.
				at = Vector2(road + lane, cross_pos) if axis == CityPlan.AXIS_X else Vector2(cross_pos, road + lane)
			else:
				# Onto the cross street, keeping the coordinate the car is already at.
				at = Vector2(road + lane, wp.z) if n_axis == CityPlan.AXIS_X else Vector2(wp.x, road + lane)
			_place(Vector3(at.x, 0.55 + _relief(at), at.y), _heading(n_axis, n_dir), 0.0)
			return
	var lane_pos: float = _plan.road_pos(axis, index) + lateral
	var p2 := Vector2(lane_pos, new_along) if axis == CityPlan.AXIS_X else Vector2(new_along, lane_pos)
	var forward := Vector2(0.0, dir) if axis == CityPlan.AXIS_X else Vector2(dir, 0.0)
	var here := _relief(p2)
	var ahead := _relief(p2 + forward * 4.0)
	_place(Vector3(p2.x, 0.55 + here, p2.y), _heading(axis, dir), atan2(ahead - here, 4.0))


## Arrived at the kerb by the player: off the lanes into physics, braked, and the crew gets out
## (STOPPED, then PARKED and Police.deploy_crew()).
func _pull_up() -> void:
	traffic_speed = 0.0
	go_physical()
	stop_here()


## True when (axis, index, dir) is the carriageway the route ends on.
func _on_dest(axis: int, index: int, dir: int) -> bool:
	return not _dest.is_empty() and axis == int(_dest.axis) and index == int(_dest.index) and dir == int(_dest.dir)


## Works the route out again (StreetRoute) when it is due or the goal has moved: where to pull up
## for `goal2` (true world XZ), and the junctions from the next one on `road` ([axis, index, dir],
## the car at `along`). `stop` says whether to pull up there or only pass through.
func _route_update(goal2: Vector2, road: Array, along: float, delta: float, stop: bool) -> void:
	_route_t -= delta
	if _route_t > 0.0 and stop == _stop_at_dest and goal2.distance_to(_route_goal) < route_moved:
		return
	_route_t = route_interval
	_route_goal = goal2
	_stop_at_dest = stop
	_dest = StreetRoute.kerb_stop(_plan, goal2, stop_distance if stop else 0.0)
	_nodes.clear()
	_path_pts = PackedVector2Array()
	_path_i = 0
	if _dest.is_empty():
		return
	if _on_dest(int(road[0]), int(road[1]), int(road[2])) and (float(_dest.along) - along) * float(road[2]) > 0.0:
		# Already on the stretch's road, heading for it: straight on.
		var ahead := StreetRoute.next_node(_plan, int(road[0]), int(road[1]), int(road[2]), along)
		var exit_along := _plan.road_pos(CityPlan.AXIS_Z if int(road[0]) == CityPlan.AXIS_X else CityPlan.AXIS_X, ahead.y if int(road[0]) == CityPlan.AXIS_X else ahead.x)
		if (exit_along - float(_dest.along)) * float(road[2]) > 0.0:
			return
	var start := StreetRoute.next_node(_plan, int(road[0]), int(road[1]), int(road[2]), along)
	_nodes = StreetRoute.path(_plan, start, _dest.entry, road, [_dest.axis, _dest.index, _dest.dir])


## At junction `node`: [axis, index, dir] of the road the route takes on from it, or [] when
## there is no route to follow (the caller falls back to _choose_turn()).
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


## At a crossing: [axis, index, dir] of the road to take, or [] to carry straight on. Turns onto
## the cross street when the goal lies off to that side, turns round when it is behind, and
## never drives out of the city grid.
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


## True when the road from `node` along `axis` in `dir` stays in the city for the next block.
func _drivable(node: Vector2, axis: int, dir: int) -> bool:
	var step := Vector2(0.0, dir) if axis == CityPlan.AXIS_X else Vector2(dir, 0.0)
	for d: float in [30.0, 70.0]:
		var z := _plan.zone_at(node + step * d)
		if z != MacroMap.Zone.CITY and z != MacroMap.Zone.BEACH:
			return false
	# Not into a landmark's site, where the road is closed (CityPlan.road_open). Looked at past
	# the crossing road's own width: inside it the road always reads open.
	var coord := node.x if axis == CityPlan.AXIS_X else node.y
	var along := (node.y if axis == CityPlan.AXIS_X else node.x) + float(dir) * 18.0
	return _plan.road_open_at(axis, coord, along)


func _place(world: Vector3, yaw: float, pitch: float) -> void:
	global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), WorldState.to_local(world))


## The road height under a lane point, from the traffic's cache (the same lattice the chunks lay
## the asphalt with), else straight from the relief.
func _relief(p: Vector2) -> float:
	if police and police.traffic:
		return police.traffic._relief(p)
	return _plan.macro.relief_at(p) if _plan and _plan.macro else 0.0


## Off the lanes and into real physics, keeping its speed: the handover traffic uses when it is
## hit, without the report (nobody hit it).
func go_physical() -> void:
	if not is_traffic():
		mode = Mode.PURSUE
		return
	var v := -global_basis.z * traffic_speed
	traffic = {}
	traffic_speed = 0.0
	collision_mask = _mask()
	_add_real_wheels()
	freeze = false
	sleeping = false
	linear_velocity = v
	mode = Mode.PURSUE
	_stuck_t = 0.0
	_stuck_count = 0
	_path_pts = PackedVector2Array()
	_route_t = 0.0


## Shot or blasted on its way in: physics takes it, and it carries on the chase from there.
func drop_out_of_traffic(impulse: Vector3 = Vector3.ZERO) -> void:
	var was := is_traffic()
	super.drop_out_of_traffic(impulse)
	if was and not roadblock and mode == Mode.DISPATCH:
		mode = Mode.PURSUE


## Driving under physics: along the streets (StreetRoute) to the kerb nearest a player on foot, to
## the search area, or after a player's car - straight at that car only once it is inside
## `ram_range` with nothing in the way. The route is a lane polyline; the cruiser steers at a
## point `look_ahead` along it and slows for the turns and for the stop. With no route (off the
## grid) it falls back to steering straight at the target, as it always did.
func _pursue(delta: float) -> void:
	if police == null:
		mode = Mode.PARKED
		return
	var in_car: bool = police.player_driving()
	var known: bool = police.player_known()
	var target: Vector3 = police.pursuit_target(self)
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var speed := linear_velocity.dot(-global_basis.z)
	# Upside down or on its side for a while: the crew bails out where it lies.
	if global_basis.y.y < 0.35:
		_flip_t += delta
		if _flip_t > 2.0:
			stop_here()
			return
	else:
		_flip_t = 0.0
	var aim := target
	var want := pursuit_speed
	var routed := false
	var direct := in_car and known and mode != Mode.LEAVING and dist < ram_range and police._clear_line(global_position + Vector3.UP, target)
	if not direct and _plan != null:
		var wp := WorldState.to_world(global_position)
		var here := Vector2(wp.x, wp.z)
		var road := StreetRoute.locate(_plan, here, Vector2(fwd.x, fwd.z))
		if not road.is_empty():
			var tw := WorldState.to_world(target)
			var stop := mode != Mode.LEAVING and (not in_car or not known)
			_route_update(Vector2(tw.x, tw.z), [road.axis, road.index, road.dir], float(road.along), delta, stop)
			if _path_pts.is_empty() and not _dest.is_empty():
				_path_pts = StreetRoute.polyline(_plan, here, [road.axis, road.index, road.dir], _nodes, _dest, PATH_LANE)
				_path_i = 0
		if _path_pts.size() >= 2:
			var look := lerpf(look_ahead.x, look_ahead.y, clampf(absf(speed) / pursuit_speed, 0.0, 1.0))
			var pt := _path_target(here, look)
			var p2: Vector2 = pt[0]
			aim = WorldState.to_local(Vector3(p2.x, wp.y, p2.y))
			var turn: float = pt[2]
			var v_turn := u_turn_speed if turn > 2.4 else lerpf(pursuit_speed, corner_speed, clampf(turn / (PI * 0.5), 0.0, 1.0))
			want = minf(want, sqrt(v_turn * v_turn + 2.0 * route_brake * float(pt[1])))
			if _stop_at_dest:
				var to_end: float = pt[3]
				want = minf(want, sqrt(2.0 * route_brake * 0.7 * maxf(to_end - 0.5, 0.0)))
				if to_end < 1.6 and absf(speed) < 3.0:
					stop_here()
					return
			routed = true
	if not routed and (not in_car or mode == Mode.LEAVING or not known):
		# No route: pull up short of the target and let the crew out, as before.
		var stop_at := stop_distance if known else 6.0
		want = clampf((dist - stop_at) * 1.1, 0.0, pursuit_speed)
		if dist < stop_at + 3.0 and absf(speed) < 4.0:
			stop_here()
			return
	var to_aim := aim - global_position
	to_aim.y = 0.0
	var aim_d := to_aim.length()
	var dir := to_aim / maxf(aim_d, 0.01)
	var ang := atan2(fwd.cross(dir).y, fwd.dot(dir))
	if _reverse_t > 0.0:
		_reverse_t -= delta
		engine_force = reverse_power
		brake = 0.0
		steering = lerpf(steering, -signf(ang) * max_steer, 1.0 - exp(-steer_speed * delta))
		return
	# Pointing the wrong way and slow: back round rather than circle.
	if absf(ang) > 2.0 and absf(speed) < 6.0 and (routed or aim_d < 22.0):
		_reverse_t = reverse_seconds
		return
	steering = lerpf(steering, clampf(ang * steer_gain, -max_steer, max_steer), 1.0 - exp(-steer_speed * delta))
	if speed < want:
		var push := clampf((want - speed) / 6.0, 0.25, 1.0)
		var nitro := nitro_multiplier if dist > 45.0 and absf(ang) < 0.3 and not routed else 1.0
		engine_force = -engine_power * push * nitro
		brake = 0.0
	else:
		engine_force = 0.0
		brake = brake_force * clampf((speed - want) / 8.0, 0.1, 1.0)
	# No progress while pushing: back out and try again; after a few goes, stop and get out.
	if engine_force < 0.0 and absf(speed) < 1.5:
		_stuck_t += delta
		if _stuck_t > stuck_seconds:
			_stuck_t = 0.0
			_stuck_count += 1
			_reverse_t = reverse_seconds
			if _stuck_count >= 3 and dist < 60.0:
				stop_here()
	else:
		_stuck_t = maxf(_stuck_t - delta, 0.0)


## How far out from the centre line a physics cruiser's route runs (m): about the inside lane.
const PATH_LANE := 2.1


## Along the route polyline from the car at `here`: [the point `look` metres on, metres to the
## next turn, how sharp that turn is (radians), metres to the end].
func _path_target(here: Vector2, look: float) -> Array:
	var pts := _path_pts
	var n := pts.size()
	var best_i := clampi(_path_i, 0, n - 2)
	var best_t := 0.0
	var best_d := INF
	for i in range(best_i, mini(best_i + 4, n - 1)):
		var ab := pts[i + 1] - pts[i]
		var l2 := ab.length_squared()
		var tt := clampf((here - pts[i]).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-4 else 0.0
		var d := here.distance_squared_to(pts[i] + ab * tt)
		if d < best_d:
			best_d = d
			best_i = i
			best_t = tt
	_path_i = best_i
	var pos := pts[best_i].lerp(pts[best_i + 1], best_t)
	# The point `look` on.
	var aim := pos
	var left := look
	var i := best_i
	var from := pos
	while i < n - 1:
		var seg := from.distance_to(pts[i + 1])
		if seg >= left:
			aim = from.move_toward(pts[i + 1], left)
			break
		left -= seg
		from = pts[i + 1]
		aim = from
		i += 1
	# The next corner: the next vertex that is not the end, and its turn.
	var to_turn := INF
	var turn := 0.0
	if best_i + 2 < n:
		to_turn = pos.distance_to(pts[best_i + 1])
		var a := (pts[best_i + 1] - pts[best_i]).normalized()
		var b := (pts[best_i + 2] - pts[best_i + 1]).normalized()
		turn = acos(clampf(a.dot(b), -1.0, 1.0))
	var to_end := pos.distance_to(pts[best_i + 1])
	for k in range(best_i + 1, n - 1):
		to_end += pts[k].distance_to(pts[k + 1])
	return [aim, to_turn, turn, to_end]


## Brakes hard; once it has stopped the Police node lets the crew out.
func stop_here() -> void:
	mode = Mode.STOPPED
	_stopped_t = 0.0
	engine_force = 0.0


func _brake_to_stop(delta: float) -> void:
	_stopped_t += delta
	engine_force = 0.0
	brake = brake_force
	steering = lerpf(steering, 0.0, 1.0 - exp(-steer_speed * delta))
	if linear_velocity.length() < 2.5 or _stopped_t > 3.0 or is_traffic():
		mode = Mode.PARKED
		brake = parking_brake
		if police:
			police.deploy_crew(self)


## Back to driving after the crew is in again.
func resume_pursuit() -> void:
	recall_crew = false
	_stuck_count = 0
	_reverse_t = 0.0
	sleeping = false
	_path_pts = PackedVector2Array()
	_route_t = 0.0
	mode = Mode.PURSUE if not is_traffic() else Mode.DISPATCH


## A cruiser that runs into a player on foot hurts them; people it hits are its own doing, not
## the player's (Police.innocent).
func _on_bumper_hit(body: Node3D) -> void:
	Police.innocent = true
	super._on_bumper_hit(body)
	Police.innocent = false
	if body is Player and driver == null and (body as Player).vehicle == null:
		var speed := traffic_speed if is_traffic() else linear_velocity.length()
		if speed >= 6.0:
			(body as Player).take_damage(ram_damage * clampf(speed / 20.0, 0.5, 1.5), global_position, "ram")


## Taken off the street for reuse: back to a wheel-less kinematic body, nothing playing.
func strip_for_pool() -> void:
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
	traffic = {"police": true, "axis": 0, "index": 0, "dir": 1, "lane": 0.0}
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_mask = _mask()
	crew_aboard = 3 if heavy else 2
	crew_alive = crew_aboard
	recall_crew = false
	roadblock = false
	unseen_time = 0.0
	_stolen = false
	_stuck_count = 0
	_reverse_t = 0.0
	_clear_route()
	mode = Mode.DISPATCH
