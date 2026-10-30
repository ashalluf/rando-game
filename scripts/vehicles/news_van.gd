class_name NewsVan
extends Vehicle
## A TV station's live truck (NewsCrews): the Blender-built high-roof panel van (BodyType.VAN) in
## fleet white with the station's band and lettering, and code-built roof gear (NewsKit) - a
## satellite uplink dish on a turntable, or a telescoping microwave mast with its pan-tilt head
## and coiled cable - that raises when it is parked at a story and comes down before it leaves.
## An ordinary Vehicle, so CarDamage, CarCabin glass and driver, CarLights, PhysicsBudget and the
## pools all work as they do on a car; hit, it goes physical like any car and stays where it ends
## up (its crew walks back to it; NewsCrews lets it go once nobody sees it).
##
##   DRIVE     on its way: kinematic along the street lanes like the traffic (EmergencyCar's lane
##             geometry and StreetRoute routing), stopping at red lights (no siren), and pulling up
##             double-parked at the kerb it was sent to.
##   ON_SCENE  parked, hazards on, the uplink raised (`raise` 0 -> 1 over `raise_seconds`), the
##             crew out (NewsCrews.deploy_crew).
##   LEAVING   the crew back aboard: the uplink comes down, then it drives off; NewsCrews pools it
##             once nobody sees it.

enum Mode { DRIVE, ON_SCENE, LEAVING }

@export_group("News van")
## Cruising speed on the way (m/s) and leaving.
@export var drive_speed: float = 13.0
@export var leave_speed: float = 10.0
## Pulling up: the last metres ease over to the kerb (m) and the stop's braking (m/s squared).
@export var kerb_approach: float = 22.0
@export var stop_brake: float = 3.8
## Seconds the uplink takes to go up (and comes down in a little less).
@export var raise_seconds: float = 14.0
## How far short of a red's crossing it stops (m past the crossing road's kerb).
@export var stop_line_back: float = 2.5
@export_group("")

## Fleet white, gloss.
const VAN_WHITE := Color(0.93, 0.93, 0.92)
## Where the lettering goes on the van's sides (body space: x the side, y up, z along; -z front).
const NAME_AT := Vector3(1.03, 1.72, 0.55)
const NAME_SIZE := 0.42
const TAG_AT := Vector3(1.03, 1.33, 0.55)
const TAG_SIZE := 0.2
const SLOGAN_AT := Vector3(1.03, 1.06, 0.55)
const SLOGAN_SIZE := 0.085

var station_i: int = 0
var service: Node
var mode: Mode = Mode.DRIVE
## The story this van covers (NewsCrews' dictionary) and the kerb it pulls up at (true world XZ).
var story: Dictionary = {}
var goal: Vector2 = Vector2.ZERO
## 0 stowed .. 1 raised.
var raise: float = 0.0
var crew_aboard: int = 2:
	set(v):
		crew_aboard = v
		_update_occupant()
var crew_alive: int = 2
var unseen_time: float = 0.0
## Where the uplink aims (true world): a satellite due south, or the receive site downtown.
var aim_world: Vector3 = Vector3.INF

var _plan: CityPlan
var _gear: Node3D
var _dish_turn: Node3D
var _dish_hinge: Node3D
var _mast_sections: Array[Node3D] = []
var _mast_head: Node3D
var _coil: Node3D
var _dest: Dictionary = {}
var _nodes: Array[Vector2i] = []
var _route_t: float = 0.0
var _route_goal := Vector2.INF
var _top: float = 2.6


static func make(station_index: int, rng: RandomNumberGenerator) -> NewsVan:
	var van := NewsVan.new()
	van.station_i = posmod(station_index, NewsKit.STATIONS.size())
	var s := NewsKit.station(van.station_i)
	van.setup(BodyType.VAN, VAN_WHITE, Addon.NONE)
	# The fleet's belt band in the station colour (the delivery vans' graphic); NewsVan replaces
	# the delivery livery's roof vent with its own gear.
	van.setup_look(Finish.GLOSS, Livery.DELIVERY, s.color)
	van.look_seed = rng.randi()
	van.traffic = {"news": true, "axis": 0, "index": 0, "dir": 1, "lane": 0.0}
	van.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	van.freeze = true
	van.set_meta("fleet", s.name)
	return van


func _ready() -> void:
	super._ready()
	add_to_group("news_van")
	_build_gear()
	_add_lettering()


## The roof gear in place of the delivery livery's vent.
func _add_livery_props(_dims_in: Dictionary) -> void:
	pass


func uplink() -> String:
	return String(NewsKit.station(station_i).uplink)


func _build_gear() -> void:
	var d := _dims()
	_top = _model_top_y if _has_model else 2.6
	var length: float = d.length
	_gear = Node3D.new()
	_gear.name = "NewsGear"
	add_child(_gear)
	var rack := _part(NewsKit.rack_mesh(length * 0.58, float(d.width) * 0.78), Vector3(0.0, _top - 0.01, length * 0.08), _gear)
	rack.name = "Rack"
	if uplink() == "dish":
		_dish_turn = Node3D.new()
		_dish_turn.name = "DishTurn"
		_dish_turn.position = Vector3(0.0, _top + 0.09, -length * 0.08)
		_gear.add_child(_dish_turn)
		_part(NewsKit.dish_base_mesh(), Vector3.ZERO, _dish_turn)
		_dish_hinge = Node3D.new()
		_dish_hinge.name = "DishHinge"
		_dish_hinge.position = Vector3(0.0, NewsKit.HINGE_Y, 0.0)
		_dish_turn.add_child(_dish_hinge)
		_part(NewsKit.dish_mesh(), Vector3.ZERO, _dish_hinge)
	else:
		var base := Node3D.new()
		base.name = "MastBase"
		base.position = Vector3(-float(d.width) * 0.22, _top + 0.09, length * 0.36)
		_gear.add_child(base)
		_part(NewsKit.mast_base_mesh(), Vector3.ZERO, base)
		for i in NewsKit.MAST_SECTIONS:
			var sec := _part(NewsKit.mast_section_mesh(i), Vector3(0.0, 0.3, 0.0), base)
			sec.name = "Mast%d" % i
			_mast_sections.append(sec)
		_mast_head = Node3D.new()
		_mast_head.name = "MastHead"
		base.add_child(_mast_head)
		_part(NewsKit.mast_head_mesh(), Vector3.ZERO, _mast_head)
		_coil = _part(NewsKit.coil_mesh(), Vector3(0.0, 0.5, 0.0), base)
		_coil.name = "Coil"
	_pose_gear()


func _part(mesh: Mesh, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.visibility_range_end = 260.0
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(mi)
	return mi


## The station's name, its tag and slogan on both sides, and the channel number on the roof for
## the helicopters: shared TextMeshes (BigVehicles.text_mesh), no shadow, not on the web.
func _add_lettering() -> void:
	if OS.has_feature("web"):
		return
	var s := NewsKit.station(station_i)
	var col: Color = s.color
	var d := _dims()
	var half := float(d.width) * 0.5 + 0.012
	for spec: Array in [[String(s.name), NAME_AT, NAME_SIZE, col], [String(s.tag) + "  LIVE", TAG_AT, TAG_SIZE, Color(0.06, 0.06, 0.07)],
			[String(s.slogan), SLOGAN_AT, SLOGAN_SIZE, Color(0.25, 0.25, 0.27)]]:
		var mesh := BigVehicles.text_mesh(String(spec[0]), float(spec[2]), spec[3])
		var at: Vector3 = spec[1]
		for side: float in [1.0, -1.0]:
			var mi := MeshInstance3D.new()
			mi.name = "Lettering"
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = BigVehicles.LETTER_DISTANCE * 1.4
			mi.basis = Basis(Vector3.UP, PI * 0.5 * side)
			mi.position = Vector3(side * half, at.y, at.z)
			add_child(mi)
	# The number on the roof, read from the air (nose toward the top of the letters).
	var num := MeshInstance3D.new()
	num.name = "RoofNumber"
	num.mesh = BigVehicles.text_mesh(String(s.number), 1.1, Color(0.04, 0.04, 0.05))
	num.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	num.visibility_range_end = 600.0
	num.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	num.position = Vector3(0.0, _top + 0.012, -float(d.length) * 0.32)
	add_child(num)


# --- The uplink -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var want := 1.0 if mode == Mode.ON_SCENE and not is_wreck() and crew_alive > 0 else 0.0
	if want != raise:
		var rate := 1.0 / maxf(raise_seconds, 0.1)
		raise = move_toward(raise, want, delta * (rate if want > raise else rate * 1.3))
		_pose_gear()


## Poses the dish or the mast at `raise`.
func _pose_gear() -> void:
	var r := clampf(raise, 0.0, 1.0)
	var aim_local := _aim_local()
	if _dish_hinge:
		# Stowed face down over the roof, then up to the satellite's elevation and round to it.
		var up := smoothstep(0.0, 0.55, r)
		var turn := smoothstep(0.35, 1.0, r)
		var elev := deg_to_rad(44.0)
		_dish_hinge.rotation.x = lerpf(PI * 0.5, -elev, up)
		_dish_turn.rotation.y = lerp_angle(0.0, atan2(aim_local.x, aim_local.z), turn)
	if not _mast_sections.is_empty():
		var lift := smoothstep(0.0, 0.85, r)
		var step := NewsKit.MAST_SECTION_LEN - NewsKit.MAST_OVERLAP
		for i in _mast_sections.size():
			# Each nested inside the one below while stowed, run out in turn.
			var own := clampf(lift * float(_mast_sections.size()) - float(i) + 1.0, 0.0, 1.0) if i > 0 else 0.0
			var below := 0.0 if i == 0 else _mast_sections[i - 1].position.y
			_mast_sections[i].position.y = (0.3 if i == 0 else below + 0.02 + step * own)
		var top := _mast_sections[-1].position.y + NewsKit.MAST_SECTION_LEN
		_mast_head.position.y = top
		var pan := smoothstep(0.8, 1.0, r)
		_mast_head.rotation.y = lerp_angle(0.0, atan2(-aim_local.x, -aim_local.z), pan)
		if _coil:
			_coil.scale = Vector3(1.0, maxf(top - 0.7, 0.4), 1.0)


## The uplink's target in the van's frame (a horizontal direction).
func _aim_local() -> Vector3:
	var dir_w := Vector3(0.0, 0.0, 1.0)
	if aim_world != Vector3.INF and is_inside_tree():
		var here := WorldState.to_world(global_position)
		dir_w = aim_world - here
		dir_w.y = 0.0
		if dir_w.length() < 1.0:
			dir_w = Vector3(0.0, 0.0, 1.0)
	elif uplink() == "dish":
		dir_w = Vector3(0.0, 0.0, 1.0) # due south: the geostationary arc from Los Angeles
	var local := global_basis.inverse() * dir_w.normalized() if is_inside_tree() else dir_w
	local.y = 0.0
	return local.normalized() if local.length() > 0.01 else Vector3(0.0, 0.0, 1.0)


## True once the uplink is fully up (the crew goes live) or down (it can drive).
func gear_up() -> bool:
	return raise >= 0.999


func gear_down() -> bool:
	return raise <= 0.001


# --- Lights ---------------------------------------------------------------------------------------

## Parked on the story the hazards blink (Vehicle._traffic_signal()'s `hazard`) and the lamps stay
## on with nobody in the cab.
func lights_running() -> bool:
	if mode == Mode.ON_SCENE and not is_wreck():
		return true
	return super.lights_running()


## The crew sit in the cab while aboard (driver and the reporter riding shotgun).
func _cabin_seats() -> int:
	if driver != null:
		return 1
	if crew_aboard <= 0:
		return 0
	return 3 if crew_aboard >= 2 else 1


func _cabin_look() -> Dictionary:
	if driver != null:
		return CarCabin.player_look()
	return CarCabin.npc_look(hash([look_seed, 91]))


# --- Driving --------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if driver != null:
		if service and service.has_method("van_stolen"):
			service.van_stolen(self)
			service = null
		super._physics_process(delta)
		return
	if is_traffic():
		match mode:
			Mode.DRIVE:
				_drive_lane(delta)
			Mode.LEAVING:
				if gear_down():
					_drive_lane(delta)
				else:
					traffic_speed = 0.0
			_:
				traffic_speed = 0.0
		_update_wheels(delta)
		return
	super._physics_process(delta)


func set_script_active(on: bool) -> void:
	super.set_script_active(on or (service != null and driver == null and mode != Mode.ON_SCENE))


func begin_drive(plan: CityPlan, axis: int, index: int, dir: int, speed: float) -> void:
	_plan = plan
	traffic = {"news": true, "axis": axis, "index": index, "dir": dir, "lane": _lane_offset(axis, index, dir)}
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


func _lane_offset(axis: int, index: int, dir: int) -> float:
	var width := _plan.road_width(axis, index)
	var lanes := 2 if width > _plan.street_width + 1.0 else 1
	var side := -dir if axis == CityPlan.AXIS_X else dir
	return side * CityPlan.lane_center(width, lanes, 0)


static func heading(axis: int, dir: int) -> float:
	var d := Vector3(0.0, 0.0, dir) if axis == CityPlan.AXIS_X else Vector3(dir, 0.0, 0.0)
	return atan2(-d.x, -d.z)


## EmergencyCar._drive_lane()'s geometry without the siren: the route's turn at each crossing,
## held at a red short of the crossing road, eased over to the kerb on the last stretch.
func _drive_lane(delta: float) -> void:
	if _plan == null:
		return
	var t: Dictionary = traffic
	var axis: int = t.axis
	var dir: int = t.dir
	var index: int = t.index
	var wp := WorldState.to_world(global_position)
	var along := wp.z if axis == CityPlan.AXIS_X else wp.x
	var going := mode == Mode.DRIVE
	_route_update(goal, [axis, index, dir], along, delta, going)
	var cruise := drive_speed if going else leave_speed
	var lateral: float = t.lane
	var to_stop := INF
	if going and _on_dest(axis, index, dir):
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
	var cross_axis := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var cross_index := _plan._index_at(cross_axis, along) + (1 if dir > 0 else 0)
	var cross_pos := _plan.road_pos(cross_axis, cross_index)
	var node := Vector2i(index, cross_index) if axis == CityPlan.AXIS_X else Vector2i(cross_index, index)
	# A red (or an amber it can stop for) holds it at the stop line.
	var to_line := (cross_pos - along) * float(dir) - _plan.road_width(cross_axis, cross_index) * 0.5 - stop_line_back
	if to_line > 0.3 and to_line < 60.0 and TrafficSignals.is_signal(_plan, node.x, node.y):
		var l := TrafficSignals.light(_plan, node.x, node.y, axis)
		if l == TrafficSignals.Light.RED or (l == TrafficSignals.Light.AMBER and to_line > traffic_speed * 1.2):
			cruise = minf(cruise, sqrt(2.0 * stop_brake * maxf(to_line - 0.3, 0.0)))
			to_stop = minf(to_stop, to_line - 0.3)
	traffic_speed = move_toward(traffic_speed, cruise, (3.5 if cruise > traffic_speed else 7.0) * delta)
	var step := traffic_speed * delta
	if to_stop < INF:
		step = minf(step, maxf(to_stop, 0.0) + 0.02)
	var new_along := along + dir * step
	if (dir > 0 and new_along >= cross_pos) or (dir < 0 and new_along <= cross_pos):
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
			traffic_speed = minf(traffic_speed, 7.0)
			_place(Vector3(at.x, _relief(at) + CityChunk.ROAD_TOP + road_lift(), at.y), heading(n_axis, n_dir), 0.0)
			return
	var lane_pos: float = _plan.road_pos(axis, index) + lateral
	var p2 := Vector2(lane_pos, new_along) if axis == CityPlan.AXIS_X else Vector2(new_along, lane_pos)
	var forward := Vector2(0.0, dir) if axis == CityPlan.AXIS_X else Vector2(dir, 0.0)
	var here := _relief(p2)
	var ahead := _relief(p2 + forward * 4.0)
	_place(Vector3(p2.x, here + CityChunk.ROAD_TOP + road_lift(), p2.y), heading(axis, dir), atan2(ahead - here, 4.0))


func _arrive(lateral: float) -> void:
	traffic_speed = 0.0
	traffic.lane = lateral
	traffic.hazard = true
	mode = Mode.ON_SCENE
	if service and service.has_method("van_arrived"):
		service.van_arrived(self)


func _on_dest(axis: int, index: int, dir: int) -> bool:
	return not _dest.is_empty() and axis == int(_dest.axis) and index == int(_dest.index) and dir == int(_dest.dir)


## Where it pulls up is worked out by NewsCrews (`story.kerb`, StreetRoute.kerb_stop's
## dictionary); leaving, it has none and just drives on.
func _route_update(goal2: Vector2, road: Array, along: float, delta: float, stop: bool) -> void:
	_route_t -= delta
	if _route_t > 0.0 and goal2.distance_to(_route_goal) < 10.0:
		return
	_route_t = 0.6
	_route_goal = goal2
	var kerb: Dictionary = story.get("kerb", {}) if stop else {}
	_dest = kerb if not kerb.is_empty() else StreetRoute.kerb_stop(_plan, goal2, 0.0)
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
	var tm: TrafficManager = service.get("traffic") if service else null
	if tm:
		return tm._relief(p)
	return _plan.macro.relief_at(p) if _plan and _plan.macro else 0.0


## Off with the crew back aboard (the uplink comes down first, then it drives away), put back on
## the nearest lane if it was knocked off and stands upright and still.
func leave(away: Vector2) -> void:
	mode = Mode.LEAVING
	goal = away
	_clear_route()
	if is_traffic():
		traffic.erase("hazard")
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


## Taken off the street for reuse: a wheel-less kinematic body, the gear stowed, as new.
func strip_for_pool() -> void:
	repair()
	for w in wheels:
		if is_instance_valid(w):
			remove_child(w)
			w.free()
	wheels.clear()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	engine_force = 0.0
	traffic = {"news": true, "axis": 0, "index": 0, "dir": 1, "lane": 0.0}
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_mask = _mask()
	crew_aboard = 2
	crew_alive = 2
	story = {}
	unseen_time = 0.0
	raise = 0.0
	aim_world = Vector3.INF
	_pose_gear()
	_clear_route()
	mode = Mode.DRIVE
