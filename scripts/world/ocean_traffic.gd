class_name OceanTraffic
extends Node3D
## The bay and the coast under way (owner, wave 3: "the bay and the coast are empty water"):
## sloops tacking off the beach towns, motor yachts and sport fishers on the coastal lanes and in
## the bay, a fast catamaran ferry crossing out to the island and back, tugs and a pilot boat
## working the port, and container ships riding at anchor in the roads offshore, lit at night.
## Scripted like AirTraffic's aircraft (Vessel, AnchoredShip): nothing is simulated, each vessel
## works its position out from its program in TRUE world coordinates, its hull rides the ocean's
## swell in its shader (vessel.gdshader), and its wake is foam the ocean shader draws from
## push_wakes().
##
## A Node3D in city.tscn: its children live in true world coordinates (the streamer shifts this
## node by the origin offset, so a child's local position IS true world), and it builds nothing
## until CityStreamer's plan exists. OCEAN_TRAFFIC=0 in the environment turns it all off (the
## A/B): no vessels, no wakes. OCEAN_STAGE=x,z,yaw (TRUE world metres, degrees like a still's
## EYE) stages a composed scene ahead of that point for stills and turns the random traffic off.
##
## Population: the persistent loops (two ferries, two tugs, the pilot boat) always run (cheap: a
## handful of vector maths a tick; their meshes hide by distance). The small craft are spawned
## out of sight round the camera on water with room (sea_room()), on the coastal lanes or free
## (sailboats, sport fishers trolling), and dropped past their despawn range; fewer at night, none
## of the small ones in a storm. The ships at anchor are fixed points in the roads.

## Caps on the small craft round the camera (scaled down on the web).
@export var max_sail: int = 8
@export var max_motor: int = 4
@export var max_fisher: int = 3
@export var max_runabout: int = 2
## Where the small craft appear and go (metres from the camera).
@export var spawn_min: float = 650.0
@export var spawn_max: float = 2400.0
@export var despawn: float = 3300.0
## Seconds between population surveys.
@export var survey_interval: float = 1.5
## Wakes handed to the ocean shader (nearest first, within `wake_range` of the camera).
@export var wake_range: float = 3000.0

## The ferry's crossing: harbour, out past the anchorage, away south-west toward the island.
const FERRY_OUT := [Vector2(3240.0, 6740.0), Vector2(3330.0, 7300.0), Vector2(3050.0, 8100.0), Vector2(2300.0, 9900.0), Vector2(-1000.0, 12800.0), Vector2(-6200.0, 15800.0)]
## ... and home again on a lane a few hundred metres east of it.
const FERRY_BACK := [Vector2(-5950.0, 16150.0), Vector2(-700.0, 13150.0), Vector2(2650.0, 10100.0), Vector2(3420.0, 8150.0), Vector2(3360.0, 7250.0), Vector2(3340.0, 6760.0)]
## The roads: where the container ships lie at anchor (TRUE world XZ), south of the port.
const ANCHORAGE := [Vector2(1650.0, 8900.0), Vector2(2900.0, 9500.0), Vector2(4000.0, 8700.0), Vector2(1100.0, 10200.0), Vector2(3500.0, 10700.0)]
## The moored ship (Landmarks' cargo_ship) and where the standing-by tug pushes on her.
const MOORED_SHIP := Vector2(3065.0, 6541.0)
## Sailing grounds (homes the sloops keep near): off the marina's channel, off the pier, off the
## south beach towns, in the lee of the headland, and in the bay.
const SAIL_HOMES := [Vector2(-1500.0, 300.0), Vector2(-1450.0, -900.0), Vector2(-1350.0, 2300.0), Vector2(-1700.0, 3800.0), Vector2(1200.0, 7800.0), Vector2(-1500.0, -2600.0)]
## Hull paints for the yachts (sRGB): mostly white, some navy, dark green, cream, red, grey.
const YACHT_PAINTS := [Color(0.94, 0.94, 0.92), Color(0.94, 0.94, 0.92), Color(0.95, 0.95, 0.93), Color(0.12, 0.16, 0.3), Color(0.92, 0.92, 0.9), Color(0.08, 0.22, 0.17), Color(0.86, 0.82, 0.7), Color(0.55, 0.12, 0.1), Color(0.52, 0.55, 0.58), Color(0.2, 0.36, 0.55)]
## The tugs' hulls: one company in black over red, the other in dark green.
const TUG_PAINTS := [Color(0.05, 0.05, 0.055), Color(0.06, 0.2, 0.14)]

var plan: CityPlan
var macro: MacroMap
var enabled: bool = true
var vessels: Array[Vessel] = []
var ships: Array[AnchoredShip] = []
var lanes: Dictionary = {}
var staged: bool = false
## The sea breeze the sloops sail by (where it blows TO, unit XZ): the Weather's wind.
var wind: Vector2 = Vector2(0.95, 0.3).normalized()

var _ready_done: bool = false
var _rng := RandomNumberGenerator.new()
var _survey_left: float = 0.0
var _serial: int = 0
var _pier_zones: Array = []
var _day: Node
var _weather: Node
var _wake_a := PackedVector4Array()
var _wake_b := PackedVector4Array()


func _ready() -> void:
	add_to_group("ocean_traffic")
	_rng.seed = 41177
	enabled = OS.get_environment("OCEAN_TRAFFIC") != "0"
	if OS.has_feature("web"):
		max_sail = mini(max_sail, 5)
		max_motor = mini(max_motor, 3)
		max_fisher = mini(max_fisher, 2)
		max_runabout = mini(max_runabout, 1)
	if not enabled:
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not _ready_done and not _setup():
		return
	advance(delta)


func _exit_tree() -> void:
	# The ocean material is shared and outlives the scene: leave it with no wakes.
	var mat := PropFactory.ocean_material()
	if mat:
		mat.set_shader_parameter("wake_count", 0)


# --- Setup ----------------------------------------------------------------------------------------

func _setup() -> bool:
	var city := get_parent()
	if city == null or not ("plan" in city):
		return false
	plan = city.get("plan") as CityPlan
	if plan == null or plan.macro == null:
		set_physics_process(plan == null)
		return false
	macro = plan.macro
	_day = city.get_node_or_null("DayNight")
	_weather = city.get_node_or_null("Weather")
	for lm: Dictionary in Landmarks.all():
		var id: String = lm.id
		if id.ends_with("pier"):
			var a: Vector2 = lm.anchor
			_pier_zones.append([a + Vector2(-160.0, 0.0), 380.0])
	_build_lanes()
	_build_fleet()
	var stage := OS.get_environment("OCEAN_STAGE")
	if stage != "":
		var f := stage.split(",")
		if f.size() >= 3:
			stage_scene(Vector2(f[0].to_float(), f[1].to_float()), deg_to_rad(f[2].to_float()))
	_ready_done = true
	return true


## The persistent traffic: the ferries, the tugs, the pilot boat and the ships at anchor.
func _build_fleet() -> void:
	var bow := -wind
	for i in ANCHORAGE.size():
		var s := AnchoredShip.new()
		s.name = "AnchoredShip%d" % i
		s.setup(ANCHORAGE[i], bow.rotated(_rng.randf_range(-0.25, 0.25)), 9100 + i * 13)
		s.transform = Transform3D(Basis(Vector3.UP, s.yaw), s.world_pos)
		add_child(s)
		ships.append(s)
	var ferry: PackedVector2Array = lanes.ferry
	var flen := _loop_length(ferry)
	for i in 2:
		var v := _new_vessel(VesselMesh.Kind.FERRY, i, 42.0, Color(0.94, 0.95, 0.95), 1)
		v.tag = "ferry_%d" % i
		v.follow(ferry, 14.5, flen * float(i) * 0.5, [[0.0, 650.0, 4.0], [flen - 900.0, flen, 4.0]])
		_add(v)
	var tug_loop: PackedVector2Array = lanes.tug
	var t := _new_vessel(VesselMesh.Kind.TUG, 0, 28.0, TUG_PAINTS[0], 2)
	t.tag = "tug_0"
	t.follow(tug_loop, 5.0, 0.0, [[0.0, 300.0, 2.5]])
	_add(t)
	var t2 := _new_vessel(VesselMesh.Kind.TUG, 1, 26.0, TUG_PAINTS[1], 3)
	t2.tag = "tug_1"
	t2.hold(MOORED_SHIP + Vector2(-40.0, 33.0), Vector2(0.0, -1.0))
	_add(t2)
	var pilot: PackedVector2Array = lanes.pilot
	var p := _new_vessel(VesselMesh.Kind.PILOT, 0, 16.0, Color(0.05, 0.05, 0.06), 0)
	p.tag = "pilot_0"
	p.follow(pilot, 10.5, _loop_length(pilot) * 0.3, [[0.0, 250.0, 3.0]])
	_add(p)


## The routes, as closed loops in TRUE world XZ:
##   coast  the coastal lane: north to south 700 m off the beaches (coast_x), round the headland's
##          west end, along its south face into the bay to the port, and back 1,500 m out;
##   bay    a loop round the bay between the headland and the anchorage;
##   ferry  the crossing (FERRY_OUT) and back on a parallel lane 300 m east;
##   tug    the harbour out to the anchorage and back; pilot the same to the farthest ship.
func _build_lanes() -> void:
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	var z := -5400.0
	while z < 4400.0:
		inner.append(Vector2(minf(macro.coast_x(z), macro.headland_west_x(z)) - 700.0, z))
		outer.append(Vector2(minf(macro.coast_x(z), macro.headland_west_x(z)) - 1500.0, z))
		z += 450.0
	for k in 10:
		var th := lerpf(PI * 1.12, PI * 0.08, float(k) / 9.0)
		inner.append(_headland_ring(th, 700.0))
		outer.append(_headland_ring(th, 1500.0))
	inner.append(Vector2(3000.0, 7350.0))
	outer.append(Vector2(3600.0, 8000.0))
	var coast := inner.duplicate()
	for i in range(outer.size() - 1, -1, -1):
		coast.append(outer[i])
	lanes["coast"] = coast
	var bay := PackedVector2Array()
	for k in 14:
		var a := TAU * float(k) / 14.0
		bay.append(Vector2(2600.0, 7900.0) + Vector2(cos(a) * 1300.0, sin(a) * 420.0))
	lanes["bay"] = bay
	var ferry := PackedVector2Array()
	for p: Vector2 in FERRY_OUT:
		ferry.append(p)
	for p: Vector2 in FERRY_BACK:
		ferry.append(p)
	lanes["ferry"] = ferry
	var a0: Vector2 = ANCHORAGE[0]
	lanes["tug"] = PackedVector2Array([Vector2(2900.0, 6700.0), Vector2(2860.0, 7400.0), a0 + Vector2(220.0, -260.0), a0 + Vector2(240.0, 60.0), a0 + Vector2(-60.0, 200.0), Vector2(2700.0, 7500.0), Vector2(2800.0, 6720.0)])
	var a1: Vector2 = ANCHORAGE[4]
	lanes["pilot"] = PackedVector2Array([Vector2(3300.0, 6740.0), Vector2(3500.0, 7600.0), a1 + Vector2(260.0, -200.0), a1 + Vector2(220.0, 180.0), a1 + Vector2(-200.0, 120.0), Vector2(3150.0, 7700.0), Vector2(3200.0, 6740.0)])


## A point `off` metres outside the headland's shore at angle `th` round its ellipse (pi its west
## end, pi/2 its south face, 0 its east end).
func _headland_ring(th: float, off: float) -> Vector2:
	var b := deg_to_rad(macro.peninsula_axis_bearing)
	var u := Vector2(sin(b), -cos(b))
	var v := Vector2(-u.y, u.x)
	return macro.peninsula_center + u * (macro.peninsula_axes.x + off) * cos(th) + v * (macro.peninsula_axes.y + off) * sin(th)


static func _loop_length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in pts.size():
		l += pts[i].distance_to(pts[(i + 1) % pts.size()])
	return l


# --- The sea --------------------------------------------------------------------------------------

## True when `p` is open water with `margin` metres of it all round: the ocean zone (the bay and
## the harbour included), clear of the piers' ends.
func sea_room(p: Vector2, margin: float) -> bool:
	if macro == null:
		return false
	if macro.zone_at(p) != MacroMap.Zone.OCEAN:
		return false
	for k in 8:
		var q := p + Vector2.from_angle(TAU * float(k) / 8.0) * margin
		if macro.zone_at(q) != MacroMap.Zone.OCEAN:
			return false
	for z: Array in _pier_zones:
		if p.distance_to(z[0]) < float(z[1]) + margin * 0.5:
			return false
	# The marina's jetties and its channel: the small boats' own (MarinaTraffic).
	var mr: Marina = macro.marina
	if mr and p.distance_to(Vector2(mr.channel.position.x, mr.zc)) < 260.0 + margin * 0.5:
		return false
	return true


## The way out to sea from `p`: the mean of the directions that are water 450 m off.
func offshore_dir(p: Vector2) -> Vector2:
	var sum := Vector2.ZERO
	for k in 12:
		var d := Vector2.from_angle(TAU * float(k) / 12.0)
		if macro.zone_at(p + d * 450.0) == MacroMap.Zone.OCEAN and macro.zone_at(p + d * 900.0) == MacroMap.Zone.OCEAN:
			sum += d
	return sum.normalized() if sum.length() > 0.01 else Vector2(-1.0, 0.0)


## The swell's height over the sea's rest level at `p` and shader time `t`, as
## sea_ride.gdshaderinc works it out (its float hash and noise, the five waves, the groups);
## `wave_scale` the global, `fine` 1 near the camera. For checks and anything that must agree
## with the hulls (GDScript has no copy of shader TIME, so it cannot place them in phase).
static func sea_height(p: Vector2, t: float, wave_scale: float, fine: float = 1.0) -> float:
	var grp := _vnoise(p / 310.0 + Vector2(t * 0.006, -t * 0.004))
	var group := 1.0 - 0.55 * (1.0 - grp)
	var amp := 1.2 * maxf(wave_scale, 0.05) * group
	var l0 := 97.0
	var h := 0.0
	h += _wave(p, Vector2(1.0, 0.22).normalized(), l0, amp * 0.34, t)
	h += _wave(p, Vector2(0.86, -0.51).normalized(), l0 / 1.59, amp * 0.26, t)
	h += _wave(p, Vector2(0.62, 0.78).normalized(), l0 / 2.62, amp * 0.19 * lerpf(0.45, 1.0, fine), t)
	h += _wave(p, Vector2(0.97, -0.24).normalized(), l0 / 4.51, amp * 0.13 * fine, t)
	h += _wave(p, Vector2(0.34, 0.94).normalized(), l0 / 7.89, amp * 0.08 * fine * fine, t)
	return h


static func _wave(p: Vector2, dir: Vector2, length: float, amp: float, t: float) -> float:
	var k := TAU / length
	var c := sqrt(9.8 / k)
	return amp * cos(k * (dir.dot(p) - c * t))


static func _hash12(p: Vector2) -> float:
	var p3 := Vector3(_fract(p.x * 0.1031), _fract(p.y * 0.1031), _fract(p.x * 0.1031))
	var d := p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3.ONE * 33.33)
	p3 += Vector3.ONE * d
	return _fract((p3.x + p3.y) * p3.z)


static func _fract(x: float) -> float:
	return x - floorf(x)


static func _vnoise(p: Vector2) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := p - i
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := _hash12(i)
	var b := _hash12(i + Vector2(1.0, 0.0))
	var c := _hash12(i + Vector2(0.0, 1.0))
	var d := _hash12(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)


# --- The tick -----------------------------------------------------------------------------------

func advance(dt: float) -> void:
	if not _ready_done:
		return
	if _weather:
		var rw: Variant = _weather.get("rain_wind")
		if rw is Vector3 and Vector2((rw as Vector3).x, (rw as Vector3).z).length() > 0.05:
			wind = Vector2((rw as Vector3).x, (rw as Vector3).z).normalized()
	for v in vessels:
		if is_instance_valid(v):
			if v.program == Vessel.Program.SAIL:
				v.wind = wind
			v.drive(dt)
	for s in ships:
		s.drive(dt)
	_survey_left -= dt
	if _survey_left <= 0.0:
		_survey_left = survey_interval
		_survey()
	push_wakes()


## The camera's position in TRUE world (the player's when there is no camera).
func _camera_world() -> Vector3:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam:
		return WorldState.to_world(cam.global_position)
	return Vector3.ZERO


func _survey() -> void:
	var cam := _camera_world()
	var c2 := Vector2(cam.x, cam.z)
	# Drop what has gone out of range (not the persistent loops), and finished wrecks.
	for v in vessels.duplicate():
		if not is_instance_valid(v):
			vessels.erase(v)
			continue
		var d := Vector2(v.world_pos.x, v.world_pos.z).distance_to(c2)
		v.presence(cam.distance_to(v.world_pos))
		if v.done or (not v.tag.begins_with("ferry") and not v.tag.begins_with("tug") and not v.tag.begins_with("pilot") and not v.tag.begins_with("stage") and d > despawn):
			vessels.erase(v)
			v.queue_free()
	if staged:
		return
	# Small craft: how many of each kind the hour and the weather allow.
	var hour := 14.0
	if _day:
		hour = float(_day.get("hour"))
	var day := smoothstep(6.0, 8.5, hour) * (1.0 - smoothstep(19.0, 21.5, hour))
	var storm := false
	if _weather:
		var st: int = int(_weather.get("state"))
		storm = st == 2 or st == 3
	var counts := {VesselMesh.Kind.SAIL: 0, VesselMesh.Kind.MOTOR: 0, VesselMesh.Kind.FISHER: 0, VesselMesh.Kind.RUNABOUT: 0}
	for v in vessels:
		if counts.has(v.kind) and not v.tag.begins_with("stage"):
			counts[v.kind] += 1
	var want := {
		VesselMesh.Kind.SAIL: 0 if storm else roundi(max_sail * day),
		VesselMesh.Kind.MOTOR: 0 if storm else roundi(max_motor * lerpf(0.4, 1.0, day)),
		VesselMesh.Kind.FISHER: roundi(max_fisher * (0.5 if storm else lerpf(0.6, 1.0, day))),
		VesselMesh.Kind.RUNABOUT: 0 if storm else roundi(max_runabout * day),
	}
	# One spawn a survey at most, so a burst never lands in one frame.
	for k: int in want:
		if counts[k] < want[k]:
			if _spawn(k, c2):
				return


## Spawns one small craft of `kind` out of sight round `c2`. True when it did.
func _spawn(kind: int, c2: Vector2) -> bool:
	match kind:
		VesselMesh.Kind.SAIL:
			var p := _free_point(c2, 260.0)
			if p == Vector2.INF:
				return false
			var home: Vector2 = SAIL_HOMES[0]
			for h: Vector2 in SAIL_HOMES:
				if h.distance_to(p) < home.distance_to(p):
					home = h
			var v := _new_vessel(kind, _rng.randi() % 2, _rng.randf_range(9.5, 14.5), YACHT_PAINTS[_rng.randi() % YACHT_PAINTS.size()], _rng.randi() % 6)
			v.tag = "sail_%d" % _serial
			v.sail(p, home, wind, Vector2.from_angle(_rng.randf() * TAU))
			_add(v)
			return true
		VesselMesh.Kind.FISHER:
			var p := _free_point(c2, 320.0)
			if p == Vector2.INF:
				return false
			# Trolling: a slow loop a few hundred metres round.
			var r := _rng.randf_range(140.0, 280.0)
			var loop := PackedVector2Array()
			for i in 10:
				var a := TAU * float(i) / 10.0
				loop.append(p + Vector2(cos(a) * r, sin(a) * r * 0.7).rotated(_rng.randf() * TAU * 0.0))
			for q in loop:
				if not sea_room(q, 120.0):
					return false
			var v := _new_vessel(kind, _rng.randi() % 2, _rng.randf_range(11.0, 15.0), YACHT_PAINTS[_rng.randi() % YACHT_PAINTS.size()], _rng.randi() % 6)
			v.tag = "fisher_%d" % _serial
			v.follow(loop, _rng.randf_range(2.2, 3.4), _rng.randf() * 1000.0)
			_add(v)
			return true
	# Motor yachts and runabouts: on the coastal lane or the bay loop, where it passes in range.
	var lane: PackedVector2Array = lanes.coast if _rng.randf() < 0.65 else lanes.bay
	var cand: Array = []
	var cum := Vessel.cumulate(lane)
	var total: float = cum[cum.size() - 1]
	var s := 0.0
	while s < total:
		var q := Vessel.loop_point(lane, cum, s)
		var d := q.distance_to(c2)
		if d > spawn_min and d < spawn_max and sea_room(q, 150.0) and not _in_view(q):
			cand.append(s)
		s += 120.0
	if cand.is_empty():
		return false
	var at: float = cand[_rng.randi() % cand.size()]
	var len := _rng.randf_range(15.0, 24.0) if kind == VesselMesh.Kind.MOTOR else _rng.randf_range(6.0, 8.0)
	var v := _new_vessel(kind, _rng.randi() % 2, len, YACHT_PAINTS[_rng.randi() % YACHT_PAINTS.size()], _rng.randi() % 6)
	v.tag = ("motor_%d" if kind == VesselMesh.Kind.MOTOR else "runabout_%d") % _serial
	v.follow(lane, _rng.randf_range(8.0, 12.5) if kind == VesselMesh.Kind.MOTOR else _rng.randf_range(10.0, 15.0), at)
	_add(v)
	return true


## A random point on open water `spawn_min`..`spawn_max` from `c2`, out of the camera's view if it
## can, or INF.
func _free_point(c2: Vector2, margin: float) -> Vector2:
	for i in 14:
		var p := c2 + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(spawn_min, spawn_max)
		if sea_room(p, margin) and (i > 9 or not _in_view(p)):
			return p
	return Vector2.INF


func _in_view(p: Vector2) -> bool:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return false
	var lp := WorldState.to_local(Vector3(p.x, 2.0, p.y))
	return not cam.is_position_behind(lp) and cam.is_position_in_frustum(lp)


func _new_vessel(kind: int, variant: int, length: float, paint: Color, canvas: int) -> Vessel:
	_serial += 1
	var v := Vessel.new()
	v.name = "Vessel%d" % _serial
	v.traffic = self
	v.setup(kind, variant, length, paint, canvas, 5000 + _serial * 7)
	return v


func _add(v: Vessel) -> void:
	# Placed before it enters the tree: a kinematic body derives its velocity from how far it
	# moved in a step (AirTraffic's trap), and this node's local space is true world.
	v.transform = Transform3D(Basis.from_euler(Vector3(v.trim, v.yaw, v.heel)), v.world_pos)
	add_child(v)
	vessels.append(v)
	v.finished.connect(_on_finished)


func _on_finished(v: Vessel) -> void:
	vessels.erase(v)
	v.queue_free()


func on_vessel_lost(_v: Vessel) -> void:
	pass


# --- Wakes ----------------------------------------------------------------------------------------

## Hands the nearest vessels' wakes to the ocean shader (ocean.gdshader wake_a / wake_b): each one's
## bow and heading, speed, beam, trail, hull length and strength.
func push_wakes() -> void:
	var mat := PropFactory.ocean_material()
	if mat == null:
		return
	var cam := _camera_world()
	var list: Array = []
	for v in vessels:
		if not is_instance_valid(v) or v.life == Vessel.Life.SINKING:
			continue
		if v.speed < 0.5 and v.program != Vessel.Program.HOLD:
			continue
		var d := cam.distance_to(v.world_pos)
		if d > wake_range:
			continue
		list.append([d, v])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_wake_a.resize(16)
	_wake_b.resize(16)
	var n := mini(list.size(), 16)
	for i in 16:
		if i >= n:
			_wake_a[i] = Vector4.ZERO
			_wake_b[i] = Vector4.ZERO
			continue
		var v: Vessel = list[i][1]
		var bow := v.bow_xz()
		var sp := v.speed
		var strength := 1.0
		match v.kind:
			VesselMesh.Kind.SAIL:
				strength = 0.45
			VesselMesh.Kind.FISHER:
				strength = 0.8
		if v.program == Vessel.Program.HOLD:
			sp = 2.2
			strength = 0.55
		var trail := clampf(sp * 22.0 + v.length * 4.0, 40.0, 520.0)
		_wake_a[i] = Vector4(bow.x, bow.y, v.heading.x, v.heading.y)
		# Whole metres of hull, plus the strength under 1 (ocean.gdshader decodes both).
		_wake_b[i] = Vector4(sp, v.beam(), trail, floorf(v.length * 0.96) + clampf(strength, 0.0, 1.0) * 0.99)
	mat.set_shader_parameter("wake_a", _wake_a)
	mat.set_shader_parameter("wake_b", _wake_b)
	mat.set_shader_parameter("wake_count", n)


# --- Stills ---------------------------------------------------------------------------------------

## A composed scene ahead of `at` (TRUE world XZ) looking along `yaw` (a still's EYE yaw, radians):
## sloops on both tacks, a motor yacht crossing, a sport fisher, the ferry's lane far out. The
## random traffic stays off while it is up (`staged`).
func stage_scene(at: Vector2, yaw: float) -> void:
	staged = true
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-fwd.y, fwd.x)
	var specs := [
		[VesselMesh.Kind.SAIL, 0, 12.0, 90.0, -18.0, 0],
		[VesselMesh.Kind.SAIL, 1, 11.0, 210.0, 45.0, 1],
		[VesselMesh.Kind.SAIL, 0, 13.5, 380.0, -120.0, 2],
		[VesselMesh.Kind.SAIL, 1, 10.0, 520.0, 160.0, 3],
		[VesselMesh.Kind.MOTOR, 0, 21.0, 300.0, 70.0, 4],
		[VesselMesh.Kind.FISHER, 1, 13.0, 160.0, -95.0, 5],
		[VesselMesh.Kind.RUNABOUT, 1, 7.0, 120.0, 30.0, 6],
	]
	for s: Array in specs:
		var p := at + fwd * float(s[3]) + right * float(s[4])
		var v := _new_vessel(s[0], s[1], s[2], YACHT_PAINTS[int(s[5]) % YACHT_PAINTS.size()], int(s[5]) % 6)
		v.tag = "stage_%d" % int(s[5])
		if int(s[0]) == VesselMesh.Kind.SAIL:
			var c := right.rotated(0.35 * (1.0 if int(s[5]) % 2 == 0 else -1.0))
			if int(s[5]) % 2 == 1:
				c = -c
			v.sail(p, p, wind, c)
		else:
			var dir := right if int(s[5]) % 2 == 0 else -right
			var loop := PackedVector2Array([p - dir * 600.0, p + dir * 600.0, p + dir * 600.0 + fwd * 400.0, p - dir * 600.0 + fwd * 400.0])
			v.follow(loop, 9.0 if int(s[0]) == VesselMesh.Kind.MOTOR else (2.8 if int(s[0]) == VesselMesh.Kind.FISHER else 12.0), 600.0)
		_add(v)
