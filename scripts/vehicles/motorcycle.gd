class_name Motorcycle
extends Vehicle
## Motorcycles: a 600-class supersport, a big V-twin cruiser and a 150-class scooter
## (tools/make_motorcycles.py, Blender, real size). They ARE Vehicles - BodyType MOTO_SPORT,
## MOTO_CRUISER, MOTO_SCOOTER, BODY_ODDS 0 - so the player's enter / exit (interact), the
## kinematic traffic (`traffic`, TrafficManager places them like any car), drop_out_of_traffic(),
## take_hit(), CarLights, DrivingFX, PhysicsBudget's settle and the pools all work unchanged.
## What is a bike's own:
##
## * TWO physics wheels on the centre line (VehicleWheel3D, front steering) and an UPRIGHT HOLD:
##   while somebody rides it (or it stands parked) the roll about its own length is driven to
##   zero every step (`upright_gain`), the way a rider balances one. The LEAN is drawn: the model
##   (the `Pose` node) leans into a turn by the angle the turn asks (atan(v * yaw rate / g)),
##   about the line through the tyres' contact patches, and pitches up about the rear contact for
##   a WHEELIE while boost is held (`wheelie_angle`). Parked, it leans onto its side stand with the
##   bars turned. Nobody aboard and knocked (a crash, a blast, a hit out of traffic) it is FALLEN:
##   the hold lets go and it goes down on its side like a real bike; whoever gets on stands it up.
## * THE RIDER is visible: in traffic a MotoRider (a crowd rig posed by RideSolver: seat, grips,
##   pegs, a boot down when it stands), the player is the hero himself (HeroRide, the same solve as
##   the last modifier on his skeleton) - never hidden as he is in a car. A crash over
##   `throw_dv` m/s, a landing on its side, a blast or a hit out of the traffic throws the rider
##   off: a ragdoll (the hero comes back to his feet where his body stopped, MotoThrow).
## * In the air it is a car: Vehicle._fly(), the same stabilised flight on boost.
## * Damage is its own (no CarDamage: a bike has no cabin, panes or doors): rounds spark and
##   wear it down, a blast or `max_health` worth of hits and it explodes and burns out.

enum Kind { SPORT, CRUISER, SCOOTER }
const TYPES := [BodyType.MOTO_SPORT, BodyType.MOTO_CRUISER, BodyType.MOTO_SCOOTER]

## Off: no motorcycles in traffic or at the kerbs (`MOTORCYCLES=0`).
static var enabled: bool = OS.get_environment("MOTORCYCLES") != "0"

## Per kind, in the MODEL's frame (metres, -Z forward, the ground at y 0, the origin midway
## between the axles), as tools/make_motorcycles.py prints them: the axles and tyre radii, the
## steering axis (through `head`, up and back), where the rider sits, holds and rests his feet,
## his forward lean (degrees), the lamps.
const DIMS := [
	{"length": 2.049, "width": 0.78, "height": 1.123, "front": Vector3(0.0, 0.300, -0.700), "rear": Vector3(0.0, 0.315, 0.700), "rf": 0.300, "rr": 0.315,
		"head": Vector3(0.0, 0.905, -0.395), "axis": Vector3(0.0, 0.9135, 0.4067),
		"seat": Vector3(0.0, 0.855, 0.22), "grip": Vector3(0.255, 0.845, -0.36), "peg": Vector3(0.17, 0.375, 0.31), "lean": 42.0,
		"lamp": Vector3(0.0, 0.87, -0.95), "tail": Vector3(0.0, 0.89, 0.88), "tyre_w": Vector2(0.122, 0.180), "hang": 0.09},
	{"length": 2.428, "width": 0.84, "height": 1.361, "front": Vector3(0.0, 0.330, -0.825), "rear": Vector3(0.0, 0.330, 0.825), "rf": 0.330, "rr": 0.330,
		"head": Vector3(0.0, 0.985, -0.335), "axis": Vector3(0.0, 0.8480, 0.5299),
		"seat": Vector3(0.0, 0.70, 0.33), "grip": Vector3(0.325, 1.137, -0.123), "peg": Vector3(0.27, 0.37, -0.26), "lean": -8.0,
		"lamp": Vector3(0.0, 0.930, -0.60), "tail": Vector3(0.0, 0.640, 1.215), "tyre_w": Vector2(0.130, 0.150), "hang": 0.0},
	{"length": 1.906, "width": 0.78, "height": 1.233, "front": Vector3(0.0, 0.272, -0.665), "rear": Vector3(0.0, 0.258, 0.665), "rf": 0.272, "rr": 0.258,
		"head": Vector3(0.0, 0.900, -0.470), "axis": Vector3(0.0, 0.8910, 0.4540),
		"seat": Vector3(0.0, 0.80, 0.33), "grip": Vector3(0.30, 0.984, -0.409), "peg": Vector3(0.11, 0.48, -0.17), "lean": 2.0, "floor": true,
		"lamp": Vector3(0.0, 1.010, -0.509), "tail": Vector3(0.0, 0.700, 0.930), "tyre_w": Vector2(0.110, 0.130), "hang": 0.0},
]
## Per kind: kg, engine force (N), top speed (m/s), braking, the steering lock (rad), how far the
## bike may wheelie (rad), and its traffic speed factor.
const PHYS := [
	{"mass": 205.0, "power": 2700.0, "top": 66.0, "brake": 26.0, "steer": 0.42, "wheelie": 0.62, "traffic": 1.08},
	{"mass": 320.0, "power": 3200.0, "top": 50.0, "brake": 34.0, "steer": 0.40, "wheelie": 0.42, "traffic": 0.98},
	{"mass": 140.0, "power": 1050.0, "top": 32.0, "brake": 18.0, "steer": 0.48, "wheelie": 0.30, "traffic": 0.82},
]
## Paints a kind is seen in, roughly in the proportion a street has them.
const MOTO_PAINTS := [
	[Color(0.62, 0.04, 0.04), Color(0.03, 0.03, 0.035), Color(0.92, 0.92, 0.93), Color(0.05, 0.18, 0.55), Color(0.28, 0.55, 0.06),
		Color(0.85, 0.36, 0.03), Color(0.62, 0.63, 0.66), Color(0.03, 0.03, 0.035), Color(0.80, 0.68, 0.05)],
	[Color(0.025, 0.025, 0.028), Color(0.025, 0.025, 0.028), Color(0.30, 0.03, 0.04), Color(0.04, 0.08, 0.16), Color(0.06, 0.15, 0.09),
		Color(0.86, 0.82, 0.72), Color(0.35, 0.36, 0.38)],
	[Color(0.93, 0.93, 0.92), Color(0.86, 0.82, 0.70), Color(0.55, 0.78, 0.70), Color(0.62, 0.06, 0.05), Color(0.04, 0.04, 0.045),
		Color(0.55, 0.56, 0.58), Color(0.45, 0.65, 0.82), Color(0.93, 0.93, 0.92)],
]
## Shares of the kinds by district (DOWNTOWN, MIDTOWN, SUBURBS, INDUSTRIAL, CAMPUS, BEACHTOWN):
## sport, cruiser, scooter.
const MOTO_MIX := [[0.36, 0.22, 0.42], [0.38, 0.30, 0.32], [0.34, 0.46, 0.20], [0.26, 0.56, 0.18], [0.30, 0.18, 0.52], [0.24, 0.34, 0.42]]

## Shares of the street and freeway traffic that are motorcycles (TrafficManager rolls them from
## the top end of the roll it already makes for trucks).
const STREET_SHARE := 0.05
const FREEWAY_SHARE := 0.04
## Lane filtering: the most a bike goes while it threads a queue (m/s), how slow the queue has to
## be to start, and how far ahead the slow car may be.
const FILTER_SPEED := 5.5
const FILTER_QUEUE_SPEED := 3.0
const FILTER_REACH := 26.0

@export_group("Bike")
## How hard the roll is held to upright while it is ridden or parked (1/s).
@export var upright_gain: float = 9.0
## Most the model leans into a turn (rad), and how fast it gets there.
@export var max_lean: float = 0.82
@export var lean_rate: float = 6.0
## The side stand's lean when parked (rad, to the left) and the bars' turn.
@export var stand_lean: float = 0.13
@export var stand_steer: float = -0.38
## A crash over this many m/s (the change in speed in one step) throws the rider off.
@export var throw_dv: float = 11.0
## Health: hits come off this; a blast takes `blast_hit` times its falloff.
@export var max_health: float = 600.0
@export var blast_hit: float = 900.0
## How far (m) the drawn bike hands over to its far twin.
@export var far_distance: float = 26.0

var kind: int = Kind.SPORT
## True once it has gone down with nobody to hold it up (crash, blast, knocked out of traffic).
var fallen: bool = false
## The drawn lean (rad, + to the left), the wheelie (rad, nose up) and the front wheel's turn.
var lean: float = 0.0
var wheelie: float = 0.0
var steer_draw: float = 0.0
## Seconds the bike has stood still (a rider puts a boot down).
var stood: float = 0.0
## Stills and checks: holds the drawn bike in a pose ({"lean", "wheelie", "steer", "speed"}).
var hold_pose: Dictionary = {}

var _pose: Node3D
var _holder: Node3D
var _steer: Node3D
var _steer_rest := Transform3D.IDENTITY
var _wheel_f: Node3D
var _wheel_r: Node3D
var _wf_rest := Transform3D.IDENTITY
var _wr_rest := Transform3D.IDENTITY
var _spin_f: float = 0.0
var _spin_r: float = 0.0
var _rider: MotoRider
var _hero_ride: HeroRide
var _health: float = 600.0
var _wrecked: bool = false
var _paint_mat: ShaderMaterial
var _yaw_prev: float = 0.0
var _yaw_rate: float = 0.0
var _pos_prev := Vector3.INF
var _speed_est: float = 0.0
var _foot: float = 0.0
var _tuck: float = 0.0


# --- Making one ----------------------------------------------------------------------------

static func is_moto(t: int) -> bool:
	return t >= BodyType.MOTO_SPORT and t <= BodyType.MOTO_SCOOTER


static func kind_of(t: int) -> int:
	return clampi(t - BodyType.MOTO_SPORT, 0, 2)


## A bike of body type `type` (one of TYPES), its paint and finish from `look`.
static func make(type: int, look: int) -> Motorcycle:
	var m := Motorcycle.new()
	m.kind = kind_of(type)
	var paints: Array = MOTO_PAINTS[m.kind]
	m.setup(type as BodyType, paints[absi(hash([look, "paint"])) % paints.size()], Addon.NONE)
	var r := float(absi(hash([look, "finish"])) % 1000) / 1000.0
	var f := Finish.METALLIC
	if m.kind == Kind.SPORT:
		f = Finish.GLOSS if r < 0.45 else (Finish.PEARL if r < 0.7 else (Finish.MATTE if r < 0.82 else Finish.METALLIC))
	elif m.kind == Kind.CRUISER:
		f = Finish.DEEP if r < 0.45 else (Finish.GLOSS if r < 0.75 else (Finish.MATTE if r < 0.9 else Finish.METALLIC))
	else:
		f = Finish.GLOSS if r < 0.7 else Finish.METALLIC
	m.setup_look(f)
	m.look_seed = look
	return m


static func traffic_factor(type: int) -> float:
	return float(PHYS[kind_of(type)].traffic)


## Lane filtering (TrafficManager._drive_street asks every tick, for a bike only): a bike in the
## inner lane of a two-lane carriageway that comes up behind a slow or stopped queue threads it
## on the line between the lanes, at walking-plus pace, to the front (the stop line still holds
## it); it moves back into its lane once nothing in it is alongside. True while it filters: the
## caller then ignores the car in front.
static func filter_tick(tm: Node, bike: Motorcycle, leader: Vehicle, groups: Dictionary, _delta: float) -> bool:
	var t: Dictionary = bike.traffic
	var plan: CityPlan = tm.get("plan")
	if plan == null or not enabled:
		return false
	var axis := int(t.axis)
	var index := int(t.index)
	var width := plan.road_width(axis, index)
	var lanes := 2 if width > plan.street_width + 1.0 else 1
	var c0 := CityPlan.lane_center(width, lanes, 0)
	var c1 := CityPlan.lane_center(width, lanes, 1) if lanes > 1 else c0
	var inner := lanes == 2 and absf(absf(float(t.lane)) - c0) < 0.35
	var filtering := bool(t.get("filtering", false))
	if not inner or int(t.get("turn", 0)) != 0 or t.has("lc_from") or t.has("bus") or t.has("pull"):
		filtering = false if not filtering else _alongside(bike, groups)
	else:
		var along := float(t.along)
		var dir := float(t.dir)
		var slow_ahead := false
		if leader != null and is_instance_valid(leader):
			var lt: Dictionary = leader.traffic
			var gap := (float(lt.along) - along) * dir
			slow_ahead = float(lt.get("v", 0.0)) < FILTER_QUEUE_SPEED and gap < FILTER_REACH
		if not filtering:
			filtering = slow_ahead
		else:
			filtering = slow_ahead or _alongside(bike, groups)
	t.filtering = filtering
	t.filter_shift = (c1 - c0) * 0.5 if filtering else 0.0
	if filtering:
		t.v = minf(float(t.get("v", 0.0)), FILTER_SPEED)
	return filtering


## True while a car of the bike's own lane stands alongside it (it may not move back in yet).
static func _alongside(bike: Motorcycle, groups: Dictionary) -> bool:
	var t: Dictionary = bike.traffic
	var key := TrafficManager.lane_key(int(t.axis), int(t.index), int(t.dir), float(t.lane))
	var group: Array = groups.get(key, [])
	var along := float(t.along)
	for c: Vehicle in group:
		if c == bike or not is_instance_valid(c):
			continue
		var ct: Dictionary = c.traffic
		var d := (float(ct.get("along", INF)) - along) * float(t.dir)
		if d > -float(ct.get("rear", 2.4)) - 1.4 and d < float(t.get("half", 1.0)) + float(ct.get("half", 2.4)) + 1.0:
			return true
	return false


## Shares of the parked stalls that hold motorcycles instead of a car, by district (DOWNTOWN,
## MIDTOWN, SUBURBS, INDUSTRIAL, CAMPUS, BEACHTOWN), and of those, the ones with two.
const PARK_SHARE := [0.09, 0.08, 0.04, 0.04, 0.12, 0.12]
const PARK_PAIR := 0.45


## A parked car's stall (CityChunk._park_car: `spot` [position, yaw, kerb side], the car already
## placed) handed over to motorcycles now and then: the car is freed and one bike returned in its
## place - backed in at an angle, rear wheel to the kerb, on its side stand - and sometimes a
## second added beside it (into `holder` and the chunk's cars). A hash of the seed and the spot,
## after every roll the chunk makes, so nothing else on the block moves.
static func parked_swap(chunk: Node, car: Vehicle, spot: Array, holder: Node) -> Vehicle:
	if not enabled:
		return car
	var plan: CityPlan = chunk.get("plan")
	if plan == null:
		return car
	var p: Vector3 = spot[0]
	var h := absi(hash([plan.seed, roundi(p.x * 4.0), roundi(p.z * 4.0), "moto_park"]))
	var district := int(plan.district_at(Vector2(p.x, p.z)))
	if float(h % 10000) / 10000.0 >= float(PARK_SHARE[clampi(district, 0, PARK_SHARE.size() - 1)]):
		return car
	var at := car.position
	var vis := car.visible
	car.free()
	var side := float(spot[2])
	var along_x := absf(float(spot[1])) > 0.1
	# Into the stall: the kerb is `side` across the road.
	var kerb := Vector3(0.0, 0.0, side) if along_x else Vector3(side, 0.0, 0.0)
	var road_dir := Vector3(1.0, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, 1.0)
	var lean := 1.0 if (h >> 8) % 2 == 0 else -1.0
	var fwd := (-kerb + road_dir * 0.75 * lean).normalized()
	var yaw := atan2(-fwd.x, -fwd.z)
	var pair := float((h >> 12) % 1000) / 1000.0 < PARK_PAIR
	var first: Motorcycle = null
	for k in (2 if pair else 1):
		var type := type_for(float((h >> (14 + k * 5)) % 997) / 997.0, district)
		var m := make(type, h + k * 131)
		var off := road_dir * ((float(k) - 0.5) * 1.5 if pair else 0.0) + kerb * 0.35
		m.position = at + off + Vector3.UP * 0.25
		m.rotation.y = yaw
		m.visible = vis
		if k == 0:
			first = m
		else:
			holder.add_child(m)
			var cars = chunk.get("_cars")
			if cars is Array:
				(cars as Array).append(m)
	return first


## The kind of bike for a hash roll 0..1 in `district` (CityPlan.District).
static func type_for(roll: float, district: int) -> int:
	var mix: Array = MOTO_MIX[clampi(district, 0, MOTO_MIX.size() - 1)]
	var acc := 0.0
	for i in 3:
		acc += float(mix[i])
		if roll < acc:
			return TYPES[i]
	return TYPES[2]


func _init() -> void:
	body_type = BodyType.MOTO_SPORT


func _ready() -> void:
	kind = kind_of(body_type)
	var ph: Dictionary = PHYS[kind]
	engine_power = float(ph.power)
	reverse_power = 600.0
	top_speed = float(ph.top)
	brake_force = float(ph.brake)
	handbrake_force = float(ph.brake) * 0.5
	parking_brake = 12.0
	max_steer = float(ph.steer)
	steer_full_speed = 9.0
	steer_min_factor = 0.16
	suspension_stiffness = 46.0
	suspension_rest_length = 0.30
	suspension_travel = 0.16
	suspension_max_force = 20000.0
	damping_compression = 1.6
	damping_relaxation = 2.2
	wheel_grip = 9.0
	wheel_roll_influence = 0.05
	center_of_mass_height = -0.05
	jump_speed = 8.0
	fly_thrust = 36.0
	collision_clearance = 0.2
	body_far_distance = far_distance
	enter_radius = 3.0
	_health = max_health
	super._ready()
	add_to_group("motorcycle")
	mass = float(ph.mass)
	angular_damp = 1.2
	_yaw_prev = global_rotation.y if is_inside_tree() else rotation.y


func display_name() -> String:
	return BODY_NAMES[body_type]


## The model frame's numbers, plus the keys Vehicle's code reads. `road` is where the road is in
## body space: the bike's origin stands this far over it.
func _dims() -> Dictionary:
	var d: Dictionary = DIMS[kind_of(body_type)]
	var road := -0.36
	var rf := float(d.rf)
	var rr := float(d.rr)
	return {"length": d.length, "width": 0.55, "chassis_h": 0.4, "cabin": Vector2(-0.3, 0.6), "cabin_h": 0.5,
		"wheel_z": absf((d.front as Vector3).z), "track": 0.0, "tyre_r": (rf + rr) * 0.5, "ride": road, "road": road,
		"lamp_y": road + (d.lamp as Vector3).y, "tail_y": road + (d.tail as Vector3).y}


# --- Building ------------------------------------------------------------------------------

func _build() -> void:
	var d: Dictionary = DIMS[kind]
	var dd := _dims()
	var road := float(dd.road)
	_pose = Node3D.new()
	_pose.name = "Pose"
	add_child(_pose)
	_holder = Node3D.new()
	_holder.name = "BodyModel"
	_holder.position = Vector3(0.0, road, 0.0)
	_pose.add_child(_holder)
	_has_model = _load_model(d)
	# One box for the body (the wheels are the physics wheels' job), from just over the tyres'
	# bottoms to the top of the tank / screen.
	var h := float(d.height) * 0.62
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.46, h, float(d.length) * 0.82)
	shape.shape = box
	shape.position = Vector3(0.0, road + 0.26 + h * 0.5, 0.0)
	add_child(shape)
	_seat = Node3D.new()
	_seat.name = "Seat"
	_seat.position = Vector3(0.0, road + (d.seat as Vector3).y + 0.05, (d.seat as Vector3).z)
	_holder.add_child(_seat)
	var bumper := Area3D.new()
	bumper.collision_layer = 0
	bumper.collision_mask = 2 | 8
	bumper.monitorable = false
	var bshape := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(0.9, 1.4, float(d.length) + 0.5)
	bshape.shape = bbox
	bshape.position = Vector3(0.0, road + 0.7, 0.0)
	bumper.add_child(bshape)
	bumper.body_entered.connect(_on_bumper_hit)
	add_child(bumper)
	_wheel_slots = []
	for front: bool in [true, false]:
		var ax: Vector3 = d.front if front else d.rear
		var r := float(d.rf if front else d.rr)
		var sag := 9.8 / (2.0 * suspension_stiffness)
		_wheel_slots.append([Vector3(0.0, road + r + suspension_rest_length - sag, ax.z), front])
	if not is_traffic():
		_add_real_wheels()
	_add_moto_lights(d)
	_occupant_key = -1
	_update_occupant()


func _add_wheel(pos: Vector3, front: bool) -> void:
	var d: Dictionary = DIMS[kind]
	super._add_wheel(pos, front)
	var w := wheels[wheels.size() - 1]
	w.wheel_radius = float(d.rf if front else d.rr)
	# Rear-wheel drive.
	w.use_as_traction = not front


func _load_model(d: Dictionary) -> bool:
	var path: String = BODY_MODELS.get(body_type, "")
	if path == "" or not ResourceLoader.exists(path):
		return false
	var scene: PackedScene = load(path)
	if scene == null:
		return false
	var inst := scene.instantiate() as Node3D
	_holder.add_child(inst)
	var near: Array[MeshInstance3D] = []
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm := String(m.name)
		_body_meshes.append(m)
		if nm.ends_with("_far"):
			m.visibility_range_begin = far_distance
			m.visibility_range_begin_margin = 2.0
			m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		else:
			near.append(m)
			m.visibility_range_end = far_distance
			m.visibility_range_end_margin = 2.0
		if nm.ends_with("_steer"):
			_steer = m
		elif nm.ends_with("_wheel_f"):
			_wheel_f = m
		elif nm.ends_with("_wheel_r"):
			_wheel_r = m
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si) as StandardMaterial3D
			if src == null:
				continue
			var slot := String(src.resource_name)
			if slot.begins_with("paint"):
				if _paint_mat == null:
					_paint_mat = _paint_material(null, null)
				m.set_surface_override_material(si, _paint_mat)
			elif slot == "glass":
				m.set_surface_override_material(si, screen_material())
			else:
				var part := _part_material(src)
				if part != null:
					m.set_surface_override_material(si, part)
	# The front wheel turns with the fork: it goes under the steer node, where it was.
	if _steer != null and _wheel_f != null:
		var xf := _steer.transform.affine_inverse() * _wheel_f.transform
		_wheel_f.get_parent().remove_child(_wheel_f)
		_steer.add_child(_wheel_f)
		_wheel_f.transform = xf
	if _steer != null:
		_steer_rest = _steer.transform
	if _wheel_f != null:
		_wf_rest = _wheel_f.transform
	if _wheel_r != null:
		_wr_rest = _wheel_r.transform
	return not near.is_empty()


## The lamps (car_lights.gdshader, the same part codes and state materials as a car's): one
## headlamp, the tail lamp, the four indicators and the beam on the road.
func _add_moto_lights(d: Dictionary) -> void:
	var node := MeshInstance3D.new()
	node.name = "NightLights"
	node.mesh = lights_mesh(kind)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 160.0
	_holder.add_child(node)
	_night_lights = node
	_light_key = -1
	_refresh_lights()


static var _light_meshes: Dictionary = {}
static var _screen_mat: StandardMaterial3D


## The screens and the dash glass: smoked and see-through (the rider's hands and the bars behind
## a supersport's screen, the clocks under the scooter's), glossy. One material for every bike.
static func screen_material() -> StandardMaterial3D:
	if _screen_mat == null:
		_screen_mat = StandardMaterial3D.new()
		_screen_mat.resource_name = "moto_screen"
		_screen_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_screen_mat.albedo_color = Color(0.06, 0.07, 0.08, 0.5)
		_screen_mat.roughness = 0.04
		_screen_mat.metallic_specular = 0.7
		_screen_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _screen_mat


static func lights_mesh(k: int) -> Mesh:
	if _light_meshes.has(k):
		return _light_meshes[k]
	var d: Dictionary = DIMS[k]
	var lamp: Vector3 = d.lamp
	var tail: Vector3 = d.tail
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head := Color(1.0, 0.95, 0.82, 1.0)
	var red := Color(1.0, 0.16, 0.10, 0.78)
	var amber := Color(1.0, 0.52, 0.06, 0.9)
	PropFactory._light_quad(st, lamp + Vector3(0.0, 0.0, -0.05), Vector3(0.36, 0.0, 0.0), Vector3(0.0, 0.24, 0.0), head)
	PropFactory._light_quad(st, tail + Vector3(0.0, 0.0, 0.05), Vector3(0.26, 0.0, 0.0), Vector3(0.0, 0.16, 0.0), red, 0.0, PropFactory.LIGHT_TAIL)
	for side: float in [-1.0, 1.0]:
		var part := PropFactory.LIGHT_LEFT if side < 0.0 else PropFactory.LIGHT_RIGHT
		PropFactory._light_quad(st, Vector3(side * 0.20, lamp.y - 0.04, lamp.z + 0.12), Vector3(0.12, 0.0, 0.0), Vector3(0.0, 0.1, 0.0), amber, 0.0, part)
		PropFactory._light_quad(st, Vector3(side * 0.14, tail.y - 0.12, tail.z + 0.06), Vector3(0.11, 0.0, 0.0), Vector3(0.0, 0.09, 0.0), amber, 0.0, part)
	PropFactory._light_quad(st, Vector3(0.0, 0.12, lamp.z - 3.4), Vector3(1.6, 0.0, 0.0), Vector3(0.0, 0.0, 8.0), Color(1.0, 0.94, 0.80, 0.42), 2.0)
	PropFactory._light_quad(st, Vector3(0.0, 0.12, tail.z + 1.0), Vector3(0.8, 0.0, 0.0), Vector3(0.0, 0.0, 1.8), Color(1.0, 0.12, 0.06, 0.4), 0.0, PropFactory.LIGHT_ROAD_BEHIND)
	var mesh := st.commit()
	mesh.surface_set_material(0, PropFactory.vehicle_light_material())
	_light_meshes[k] = mesh
	return mesh


func headlight_transform(dip: float) -> Transform3D:
	var d: Dictionary = DIMS[kind]
	var lamp: Vector3 = d.lamp
	return Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(dip)), Vector3(0.0, float(_dims().road) + lamp.y, lamp.z - 0.1))


func tail_point() -> Vector3:
	var d: Dictionary = DIMS[kind]
	var tail: Vector3 = d.tail
	return Vector3(0.0, float(_dims().road) + tail.y - 0.1, tail.z + 0.3)


# --- Riders --------------------------------------------------------------------------------

## A traffic bike carries its rider (the cabin rule: Vehicle._cabin_seats()); the player on it is
## the hero (mount_rider()); a parked bike nobody.
func _update_occupant(force: bool = false) -> void:
	_occupant_key = -1
	var want_npc := driver == null and _npc_driver and not _wrecked and not fallen
	if want_npc and _rider == null and _holder != null:
		_rider = MotoRider.new()
		_rider.setup_moto(self, _occupant_seed)
		_rider.name = "Rider"
		_holder.add_child(_rider)
	elif not want_npc and _rider != null and is_instance_valid(_rider) and not _rider._down:
		_rider.queue_free()
		_rider = null
	if _rider != null and not is_instance_valid(_rider):
		_rider = null


func _cabin_seats() -> int:
	if driver != null:
		return 1
	return 1 if _npc_driver and not _wrecked and not fallen else 0


## The player gets on: the hero rides it, seen (Player.enter_vehicle calls this).
func mount_rider(player: Node3D) -> void:
	_stand_up()
	if _rider != null and is_instance_valid(_rider):
		_rider.queue_free()
		_rider = null
	player.visible = true
	var avatar = player.get("avatar")
	if avatar != null and avatar.get("_skeleton") != null:
		var sk: Skeleton3D = avatar.get("_skeleton")
		_hero_ride = HeroRide.new()
		_hero_ride.name = "HeroRide"
		_hero_ride.bike = self
		_hero_ride.player = player
		sk.add_child(_hero_ride)
	_place_rider_visual()


## The player gets off (Player.exit_vehicle calls this, before he is put down beside it).
func dismount_rider(player: Node3D) -> void:
	if _hero_ride != null and is_instance_valid(_hero_ride):
		_hero_ride.release()
	_hero_ride = null
	var vis = player.get("visual")
	if vis is Node3D:
		var yaw := global_rotation.y
		(vis as Node3D).transform = Transform3D(Basis(Vector3.UP, yaw - player.global_rotation.y), Vector3.ZERO)


## The hero's Visual node follows the bike's model frame, so the pose (worked out in that frame)
## lands on the seat whatever the player node is doing.
func _place_rider_visual() -> void:
	if _hero_ride == null or not is_instance_valid(_hero_ride) or _holder == null:
		return
	var vis = _hero_ride.player.get("visual") if is_instance_valid(_hero_ride.player) else null
	if vis is Node3D:
		(vis as Node3D).global_transform = _holder.global_transform


func _process(_delta: float) -> void:
	_place_rider_visual()


## Its own rider stands inside its bumper zone: never knocked by it.
func _on_bumper_hit(body: Node3D) -> void:
	if body == _rider or body is MotoRider:
		return
	super._on_bumper_hit(body)


## Throws whoever rides it off: the hero (MotoThrow) or the traffic's rider (a ragdoll).
func throw_rider(impulse: Vector3) -> void:
	var v := linear_velocity if not is_traffic() else -global_basis.z * traffic_speed
	if driver != null and driver is Player:
		var p := driver as Player
		p.exit_vehicle()
		MotoThrow.throw(p, _seat.global_position if _seat else global_position + Vector3.UP, v + impulse)
	elif _rider != null and is_instance_valid(_rider) and not _rider._down:
		var r := _rider
		_rider = null
		_npc_driver = false
		r.knock((v * 0.9 + impulse + Vector3.UP * 3.0) * Ragdoll.TOTAL_MASS)
	fallen = true
	_update_occupant()


func _stand_up() -> void:
	if not fallen and global_basis.y.y > 0.8:
		return
	fallen = false
	var yaw := global_rotation.y
	global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * 0.4)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	hold_crash_watch(4)


# --- Damage --------------------------------------------------------------------------------

func is_wreck() -> bool:
	return _wrecked


func take_hit(_shape_index: int, damage: float, dir: Vector3, at: Vector3 = Vector3.INF, kind_hit: int = HIT_PROP) -> void:
	if _wrecked:
		return
	if is_traffic() and kind_hit != HIT_CRASH:
		drop_out_of_traffic()
	match kind_hit:
		HIT_CRASH:
			if damage > throw_dv - crash_min_dv and (driver != null or _rider != null):
				throw_rider(Vector3.UP * 2.0)
			elif damage > throw_dv - crash_min_dv:
				fallen = true
			_health -= damage * 8.0
		HIT_BLAST:
			if driver != null or _rider != null:
				throw_rider(dir.normalized() * 6.0 * damage + Vector3.UP * 5.0)
			fallen = true
			_health -= blast_hit * damage
		_:
			_health -= damage
	if _health <= 0.0:
		_explode()


func drop_out_of_traffic(impulse: Vector3 = Vector3.ZERO) -> void:
	if not is_traffic():
		return
	super.drop_out_of_traffic(impulse)
	throw_rider(impulse * 0.002)


func _explode() -> void:
	if _wrecked:
		return
	_wrecked = true
	if driver != null or (_rider != null and is_instance_valid(_rider)):
		throw_rider(Vector3.UP * 6.0)
	fallen = true
	set_meta("wreck", true)
	if _paint_mat:
		_paint_mat.set_shader_parameter("paint", Color(0.035, 0.032, 0.03))
		_paint_mat.set_shader_parameter("clearcoat_amount", 0.0)
		_paint_mat.set_shader_parameter("paint_roughness", 0.9)
	for m in _body_meshes:
		if is_instance_valid(m):
			m.material_overlay = CarDamage.wreck_wheel_material()
	_refresh_lights()
	if _engine_sound:
		_engine_sound.stop()
	Explosion.blast(self, global_position + Vector3.UP * 0.4, 5.0, 14.0, 10.0, self)
	PhysicsBudget.register_debris(self, 120.0)


func lights_running() -> bool:
	if _wrecked:
		return false
	return driver != null or (_npc_driver and not fallen)


# --- Riding --------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_crash_watch()
	_tick_lights(delta)
	_animate(delta)
	if is_traffic():
		return
	if driver == null:
		if _was_airborne:
			gravity_scale = 1.0
			_was_airborne = false
		engine_force = 0.0
		brake = parking_brake if linear_velocity.length() < parking_speed else 2.0
		steering = lerpf(steering, 0.0, 1.0 - exp(-steer_speed * delta))
		if _engine_sound and _engine_sound.playing:
			_engine_sound.stop()
		if fallen or global_basis.y.y < 0.5 or linear_velocity.length() > 6.0:
			# Nobody to hold it up: it goes down.
			if not fallen and linear_velocity.length() > 6.0:
				fallen = true
			return
		_hold_upright(delta, 1.0)
		return
	if PhysicsServer3D.body_get_state(get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING):
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
	if _engine_sound == null:
		_engine_sound = Sfx.loop_player("engine_loop", -10.0)
		add_child(_engine_sound)
	if not _engine_sound.playing:
		_engine_sound.play()
	var speed := linear_velocity.dot(-global_basis.z)
	_engine_sound.pitch_scale = (1.0 if kind != Kind.SCOOTER else 1.5) + clampf(absf(speed) / top_speed, 0.0, 1.0) * 1.6
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var throttle := -input.y
	var boosting := Input.is_action_pressed("boost")
	var boost := nitro_multiplier if boosting else 1.0
	var fade := clampf(1.0 - absf(speed) / top_speed, 0.0, 1.0)
	if throttle > 0.0:
		engine_force = -throttle * engine_power * boost * (fade if not boosting else maxf(fade, 0.3))
		brake = 0.0
	elif throttle < 0.0:
		if speed > 1.0:
			engine_force = 0.0
			brake = brake_force
		else:
			engine_force = -throttle * reverse_power
			brake = 0.0
	else:
		engine_force = 0.0
		brake = 0.6
	if Input.is_action_pressed("alt_fire"):
		brake = handbrake_force
	_jump_timer = maxf(_jump_timer - delta, 0.0)
	var airborne := is_airborne()
	if Input.is_action_just_pressed("jump") and _jump_timer <= 0.0 and (not airborne or air_jump):
		_jump_timer = jump_cooldown
		var up := jump_speed * (air_jump_factor if airborne else 1.0)
		if airborne and linear_velocity.y < 0.0:
			apply_central_impulse(Vector3.UP * -linear_velocity.y * mass)
		apply_central_impulse(Vector3.UP * up * mass)
		hold_crash_watch(3)
		angular_velocity = Vector3.ZERO
		Sfx.play("jump", global_position, -2.0, 0.8)
	var steer_factor := lerpf(1.0, steer_min_factor, clampf(absf(speed) / (steer_full_speed * 3.0), 0.0, 1.0))
	_steer_target = -input.x * max_steer * steer_factor
	steering = lerpf(steering, _steer_target, 1.0 - exp(-steer_speed * delta))
	RoadWear.bump(self)
	_air_time = _air_time + delta if airborne else 0.0
	if _air_time >= flight_grace:
		_fly(delta, input)
		return
	if _was_airborne:
		gravity_scale = 1.0
		_was_airborne = false
		# Landed on its side: off he goes.
		if global_basis.y.y < 0.45:
			throw_rider(Vector3.ZERO)
			return
	if global_basis.y.y < 0.25 and not airborne:
		throw_rider(Vector3.ZERO)
		return
	_hold_upright(delta, 1.0)
	# The wheelie: the drawn bike only (the front physics wheel stays down), and a little more
	# shove while it is up.
	if boosting and throttle > 0.0 and absf(speed) < top_speed * 0.6 and not airborne:
		engine_force *= 1.08


## PhysicsBudget turns a far bike's script off: nothing would hold it up any more, so a parked
## one is put to sleep where it stands (it wakes, and its script comes back, when touched).
func set_script_active(on: bool) -> void:
	super.set_script_active(on)
	if not on and driver == null and not is_traffic() and not fallen and linear_velocity.length() < 1.0:
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, true)


## Drives the roll about the bike's own length toward upright (the drawn lean does the leaning).
## Read and written on the body's direct state: RigidBody3D's `angular_velocity` is synced before
## VehicleBody3D applies its wheels' impulses each step, so writing it back threw away the yaw the
## front tyre's side force had just given, and the bike would not turn at all.
func _hold_upright(delta: float, weight: float) -> void:
	if PhysicsServer3D.body_get_state(get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING):
		return
	var st := PhysicsServer3D.body_get_direct_state(get_rid())
	if st == null:
		return
	var bz := global_basis.z
	var roll := asin(clampf(global_basis.x.y, -1.0, 1.0))
	var av := st.angular_velocity
	# Standing still and level already: nothing to hold (a write would keep it awake for good).
	if driver == null and absf(roll) < 0.003 and av.length() < 0.02 and st.linear_velocity.length() < 0.05:
		return
	var along := av.dot(bz)
	var want := -roll * upright_gain * weight
	av += bz * (lerpf(along, want, 1.0 - exp(-12.0 * delta)) - along)
	# Nor may it pitch over its own nose or tail on the ground.
	var bx := global_basis.x
	var pitch := asin(clampf(-bz.y, -1.0, 1.0))
	if absf(pitch) > 0.35:
		var ap := av.dot(bx)
		av += bx * (-signf(pitch) * 2.0 - ap) * (1.0 - exp(-8.0 * delta))
	st.angular_velocity = av


## The drawn bike: the lean into a turn (from the speed and the turn rate, the angle a real bike
## leans at), the wheelie, the side stand, the bars and the wheels, the rider's state.
func _animate(delta: float) -> void:
	if _pose == null:
		return
	var yaw := global_rotation.y
	var yr := wrapf(yaw - _yaw_prev, -PI, PI) / maxf(delta, 0.0001)
	_yaw_prev = yaw
	_yaw_rate = lerpf(_yaw_rate, yr, 1.0 - exp(-10.0 * delta))
	var speed := 0.0
	if is_traffic():
		speed = traffic_speed
	else:
		speed = linear_velocity.dot(-global_basis.z)
	_speed_est = speed
	var parked := driver == null and not is_traffic() and not _npc_driver and absf(speed) < 0.5
	var want_lean := 0.0
	var want_steer := 0.0
	if fallen or _wrecked:
		want_lean = 0.0
	elif parked:
		want_lean = stand_lean
		want_steer = stand_steer
	else:
		want_lean = clampf(atan(speed * _yaw_rate / 9.8), -max_lean, max_lean)
		if is_traffic():
			want_steer = clampf(_yaw_rate * 1.6 / maxf(absf(speed), 2.5), -0.4, 0.4)
		else:
			want_steer = steering * 0.8
	if not is_traffic() and not wheels.is_empty() and is_airborne():
		want_lean = 0.0
	lean = lerpf(lean, want_lean, 1.0 - exp(-lean_rate * delta))
	steer_draw = lerpf(steer_draw, want_steer, 1.0 - exp(-10.0 * delta))
	var boosting := driver != null and Input.is_action_pressed("boost") and Input.get_axis("move_back", "move_forward") > 0.1
	var want_w := 0.0
	if boosting and not fallen and absf(speed) < top_speed * 0.62 and not is_airborne():
		want_w = float(PHYS[kind].wheelie) * clampf(0.35 + absf(speed) / 12.0, 0.0, 1.0)
	wheelie = lerpf(wheelie, want_w, 1.0 - exp(-(3.0 if want_w > wheelie else 5.0) * delta))
	if not hold_pose.is_empty():
		lean = float(hold_pose.get("lean", lean))
		wheelie = float(hold_pose.get("wheelie", 0.0))
		steer_draw = float(hold_pose.get("steer", steer_draw))
		speed = float(hold_pose.get("speed", speed))
		boosting = wheelie > 0.05
	var d: Dictionary = DIMS[kind]
	var road := float(_dims().road)
	var rear: Vector3 = d.rear
	var pivot := Vector3(0.0, road, rear.z + float(d.rr) * 0.2)
	var xf := Transform3D(Basis(Vector3.BACK, lean), Vector3.ZERO)
	var w_xf := Transform3D(Basis.IDENTITY, pivot) * Transform3D(Basis(Vector3.RIGHT, wheelie), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)
	# The lean is about the ground line under the tyres (y = road in body space).
	var l_xf := Transform3D(Basis.IDENTITY, Vector3(0.0, road, 0.0)) * xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -road, 0.0))
	_pose.transform = l_xf * w_xf
	if _steer != null:
		var axis: Vector3 = d.axis
		_steer.transform = Transform3D(Basis(axis.normalized(), steer_draw) * _steer_rest.basis, _steer_rest.origin)
	_spin_f = fposmod(_spin_f - speed / float(d.rf) * delta, TAU)
	_spin_r = fposmod(_spin_r - speed / float(d.rr) * delta, TAU)
	if _wheel_f != null:
		_wheel_f.transform = Transform3D(_wf_rest.basis * Basis(Vector3.RIGHT, _spin_f), _wf_rest.origin)
	if _wheel_r != null:
		_wheel_r.transform = Transform3D(_wr_rest.basis * Basis(Vector3.RIGHT, _spin_r), _wr_rest.origin)
	# The rider: a boot down once it stands, tucked in at speed on the supersport, hanging off
	# into the turn.
	stood = stood + delta if absf(speed) < 0.6 else 0.0
	_foot = move_toward(_foot, 1.0 if stood > 0.25 and not boosting else 0.0, delta * 3.0)
	_tuck = move_toward(_tuck, 1.0 if kind == Kind.SPORT and absf(speed) > 22.0 else 0.0, delta * 1.5)
	if _rider != null and is_instance_valid(_rider) and not _rider._down:
		_rider.ride_state = ride_state()
	if _hero_ride != null and is_instance_valid(_hero_ride):
		_hero_ride.state = ride_state()
	_update_body_tier(global_position.distance_to(_focus_point()))


## What the rider's pose needs this frame (RideSolver.solve()).
func ride_state() -> Dictionary:
	var hang := -lean / maxf(max_lean, 0.01) * float(DIMS[kind].get("hang", 0.0))
	return {"foot_down": _foot, "tuck": _tuck, "wheelie": wheelie, "hang": hang}


func geo() -> Dictionary:
	return DIMS[kind]


## The holder frame the rider is posed in (the model's frame: the ground at y 0, leaning).
func rider_frame() -> Node3D:
	return _holder
