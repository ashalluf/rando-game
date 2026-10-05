class_name Cyclists
extends Node3D
## The people riding the bike lanes (Micromobility's lanes): cyclists on road bikes, cruisers,
## longtail cargo bikes and share bikes, and scooter riders, driven along the lanes near the
## player - not TrafficManager's cars, a small manager of their own. A node in city.tscn, so the
## origin shifts carry it: its riders live in its own space, which is the true world.
##
## A rider holds its lane (road, axis, direction; right-hand running, Micromobility.ride_offset())
## at its own pace, stops at the stop line for a red (TrafficSignals.light, the same clock the
## cars and the walkers keep) or an amber it can stop for, rolls a stop sign or a roundabout after
## a look, follows the rider in front, brakes for whatever stands in the lane ahead (a shape query
## on the player, props and npc layers: a bus at its stop, a car in the lane, a walker), and rides
## away flat out when shots or a blast scare it (BikeRider._scare). At the end of its lane (the
## next stretch has none) it waits at the line, and goes once nobody sees it. Riders come and go
## out of sight within `spawn_radius` of the player; past `despawn_radius` they are dropped.
## FULL-chunk range only, none on the web's lowest settings. Hit, a rider is a Pedestrian like
## any other: a ragdoll, and the bike a debris body (BikeRider.knock).

## Riders at once at most (desktop / web); Quality takes this down at LOW and LOWEST.
@export var max_riders: int = 12
@export var web_max_riders: int = 4
## Riders appear between these distances from the player (m), out of the camera's sight when
## nearer than `visible_spawn`, and go past `despawn_radius`.
@export var spawn_min: float = 45.0
@export var spawn_radius: float = 165.0
@export var visible_spawn: float = 110.0
@export var despawn_radius: float = 220.0
## Cruising speeds (m/s, min and max) by vehicle (MicroMesh.Kind): road, cruiser, cargo, share,
## scooter (the operators cap them at 15 mph).
@export var road_speed: Vector2 = Vector2(6.2, 8.6)
@export var cruiser_speed: Vector2 = Vector2(3.6, 4.8)
@export var cargo_speed: Vector2 = Vector2(4.3, 5.4)
@export var share_speed: Vector2 = Vector2(3.9, 5.2)
@export var scooter_speed: Vector2 = Vector2(5.4, 6.7)
## Acceleration and braking (m/s2).
@export var accel: float = 1.3
@export var brake: float = 3.2
## The gap a rider keeps to the one ahead (m) and how far ahead it looks for obstacles.
@export var follow_gap: float = 3.2
@export var look_ahead: float = 3.0
## Seconds at a stop sign or a roundabout before going.
@export var stop_wait: float = 0.9
## How often the riders are counted, culled and topped up (s).
@export var survey_interval: float = 0.6
## Shares of what people ride (road, cruiser, cargo, share bike, scooter), by district
## (DOWNTOWN, MIDTOWN, SUBURBS, INDUSTRIAL, CAMPUS, BEACHTOWN).
const MIX := [
	[0.2, 0.08, 0.04, 0.28, 0.4], [0.3, 0.12, 0.08, 0.2, 0.3], [0.38, 0.18, 0.16, 0.06, 0.22],
	[0.4, 0.15, 0.05, 0.1, 0.3], [0.18, 0.2, 0.04, 0.24, 0.34], [0.14, 0.42, 0.12, 0.12, 0.2],
]

## Off: no riders (`MICROMOBILITY=0`).
static var enabled: bool = OS.get_environment("MICROMOBILITY") != "0"

var plan: CityPlan
var _riders: Array = []
var _survey_t: float = 0.0
var _cap: int = 12
var _web: bool = false
var _player: Node3D
var _spawned: int = 0
var _relief: Dictionary = {}
var _query := PhysicsShapeQueryParameters3D.new()
var _query_box := BoxShape3D.new()
var _staged: bool = false
## Seconds since the riders were last checked for obstacles (a quarter second apart).
var _probe_t: float = 0.0


func _ready() -> void:
	_web = OS.has_feature("web")
	_query.shape = _query_box
	_query.collision_mask = 2 | 4 | 8
	_query.collide_with_areas = false


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if plan == null:
		var city := get_parent()
		if city == null or not ("plan" in city):
			return
		plan = city.get("plan") as CityPlan
		if plan == null:
			return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	if not _staged and OS.get_environment("MICRO_RIDERS") != "":
		_staged = true
		_stage(OS.get_environment("MICRO_RIDERS"))
	_survey_t -= delta
	if _survey_t <= 0.0:
		_survey_t = survey_interval
		_survey()
	_probe_t -= delta
	var probe := _probe_t <= 0.0
	if probe:
		_probe_t = 0.25
	for r: Dictionary in _riders:
		if is_instance_valid(r.node):
			_ride(r, delta, probe)


## The player's true-world position (this node's space).
func player_at() -> Vector3:
	return to_local(_player.global_position) if _player else Vector3.ZERO


func riders() -> Array:
	return _riders


# --- The survey ---------------------------------------------------------------------------------

func _survey() -> void:
	var q := get_parent().get_node_or_null("Quality")
	var lv := int(q.get("level")) if q != null and q.get("level") != null else 0
	_cap = int((web_max_riders if _web else max_riders) * [1.0, 0.8, 0.5, 0.0][clampi(lv, 0, 3)])
	var me := player_at()
	var keep: Array = []
	for r: Dictionary in _riders:
		var node: BikeRider = r.node
		if not is_instance_valid(node):
			continue
		var d := Vector2(node.position.x - me.x, node.position.z - me.z).length()
		var gone := d > despawn_radius or (bool(r.ended) and not _seen(node.position, 70.0))
		# Riders placed by hand (tests, stills) stay until they are knocked off or freed.
		if bool(r.get("placed", false)):
			keep.append(r)
			continue
		if gone or keep.size() >= _cap:
			node.queue_free()
			continue
		keep.append(r)
	_riders = keep
	# One new rider a survey, so they arrive over a few seconds rather than all at once.
	if _riders.filter(func(x: Dictionary) -> bool: return not bool(x.get("placed", false))).size() < _cap:
		_try_spawn(me)


## Whether a point (this space) is in front of the camera within `reach` metres of it.
func _seen(p: Vector3, reach: float) -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return false
	var g := to_global(p)
	if g.distance_to(cam.global_position) > reach:
		return false
	return not cam.is_position_behind(g) and cam.is_position_in_frustum(g)


func _try_spawn(me: Vector3) -> void:
	var at := plan.block_index_at(Vector2(me.x, me.z))
	var picks: Array = []
	for axis in 2:
		var mine := at.x if axis == CityPlan.AXIS_X else at.y
		var other_i := at.y if axis == CityPlan.AXIS_X else at.x
		for index in range(mine - 2, mine + 4):
			for k in range(other_i - 3, other_i + 3):
				if Micromobility.lane_on(plan, axis, index, k):
					picks.append([axis, index, k])
	if picks.is_empty():
		return
	_spawned += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, "cyclist", _spawned, int(me.x), int(me.z)])
	for attempt in 6:
		var pick: Array = picks[rng.randi() % picks.size()]
		var axis: int = pick[0]
		var index: int = pick[1]
		var k: int = pick[2]
		var dir := 1 if rng.randf() < 0.5 else -1
		var span := Micromobility.lane_span(plan, axis, index, k)
		if span.y - span.x < 12.0:
			continue
		var s := lerpf(span.x + 2.0, span.y - 2.0, rng.randf())
		var p := _lane_point(axis, index, dir, s)
		var d := Vector2(p.x - me.x, p.z - me.z).length()
		if d < spawn_min or d > spawn_radius:
			continue
		if d < visible_spawn and _seen(p, visible_spawn):
			continue
		if _crowded(axis, index, dir, s):
			continue
		_add_rider(axis, index, dir, k, s, rng)
		return


func _crowded(axis: int, index: int, dir: int, s: float) -> bool:
	for r: Dictionary in _riders:
		if int(r.axis) == axis and int(r.index) == index and int(r.dir) == dir and absf(float(r.s) - s) < 12.0:
			return true
	return false


func _add_rider(axis: int, index: int, dir: int, k: int, s: float, rng: RandomNumberGenerator) -> void:
	var p := _lane_point(axis, index, dir, s)
	var district := plan.district_at(Vector2(p.x, p.z))
	var mix: Array = MIX[clampi(int(district), 0, MIX.size() - 1)]
	var roll := rng.randf()
	var vehicle := 0
	var acc := 0.0
	for i in mix.size():
		acc += float(mix[i])
		if roll <= acc:
			vehicle = i
			break
		vehicle = i
	var kind := vehicle
	if vehicle == 4:
		kind = MicroMesh.Kind.SCOOTER_A + (rng.randi() % 2)
	var paint := Color(0.5, 0.5, 0.5)
	if MicroMesh.PAINTS.has(kind):
		var paints: Array = MicroMesh.PAINTS[kind]
		paint = paints[rng.randi() % paints.size()]
	var range_v: Vector2 = [road_speed, cruiser_speed, cargo_speed, share_speed, scooter_speed][vehicle]
	var rider := BikeRider.new()
	rider.setup_rider(kind, hash([plan.seed, "rider", _spawned]), paint)
	rider.name = "Rider%d" % _spawned
	rider.position = p
	rider.rotation.y = _yaw(axis, dir)
	add_child(rider)
	var want := rng.randf_range(range_v.x, range_v.y)
	_riders.append({"node": rider, "axis": axis, "index": index, "dir": dir, "k": k, "s": s, "v": want * 0.9,
		"want": want, "wait": 0.0, "stopped_at": -99999, "ended": false, "block_v": INF, "swerve": 0.0, "stuck": 0.0})
	rider.ride_speed = want * 0.9


# --- Riding ----------------------------------------------------------------------------------

func _yaw(axis: int, dir: int) -> float:
	var d := Vector3(0.0, 0.0, dir) if axis == CityPlan.AXIS_X else Vector3(dir, 0.0, 0.0)
	return atan2(-d.x, -d.z)


## A point on the rider's line of lane (axis, index, dir) at `s` along the road, on the road.
func _lane_point(axis: int, index: int, dir: int, s: float) -> Vector3:
	var off := plan.road_pos(axis, index) + Micromobility.ride_offset(plan, axis, index, dir)
	var x := off if axis == CityPlan.AXIS_X else s
	var z := s if axis == CityPlan.AXIS_X else off
	return Vector3(x, CityChunk.ROAD_TOP + _relief_at(x, z), z)


## The city's relief, as a chunk samples it (CityChunk._gy: a 3 m lattice, bilinear).
func _relief_at(x: float, z: float) -> float:
	if plan.macro == null:
		return 0.0
	var st := CityChunk.RELIEF_STEP
	var fx := x / st
	var fz := z / st
	var i := floori(fx)
	var j := floori(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	return lerpf(lerpf(_rs(i, j), _rs(i + 1, j), tx), lerpf(_rs(i, j + 1), _rs(i + 1, j + 1), tx), tz)


func _rs(i: int, j: int) -> float:
	var key := Vector2i(i, j)
	var h: Variant = _relief.get(key)
	if h == null:
		if _relief.size() > 20000:
			_relief.clear()
		h = plan.macro.relief_at(Vector2(i * CityChunk.RELIEF_STEP, j * CityChunk.RELIEF_STEP))
		_relief[key] = h
	return h


func _ride(r: Dictionary, delta: float, probe: bool) -> void:
	var node: BikeRider = r.node
	if node._down:
		return
	var axis: int = r.axis
	var index: int = r.index
	var dir: int = r.dir
	var other := 1 - axis
	var s: float = r.s
	var v: float = r.v
	var panic := node.panicking()
	var want: float = float(r.want) * (1.3 if panic else 1.0)
	# The crossing ahead and the stop line before it.
	var next_k: int = int(r.k) + (1 if dir > 0 else 0)
	var jc := plan.road_pos(other, next_k)
	var half := plan.road_width(other, next_k) * 0.5
	var stop_at := jc - float(dir) * (half + Micromobility.JUNCTION_GAP - 0.6)
	var to_stop := (stop_at - s) * float(dir)
	var limit := want
	if to_stop > -0.5:
		var must := false
		var ix := index if axis == CityPlan.AXIS_X else next_k
		var iz := next_k if axis == CityPlan.AXIS_X else index
		var kind := int(plan.intersection(ix, iz).kind)
		var next_seg := int(r.k) + dir
		if bool(r.ended) or not Micromobility.lane_on(plan, axis, index, next_seg):
			# The lane ends: wait at the line (Cyclists drops them once unseen).
			must = true
			r.ended = true
		elif kind == CityPlan.Intersection.SIGNALS:
			var light := TrafficSignals.light(plan, ix, iz, axis)
			if light == TrafficSignals.Light.RED and not panic:
				must = true
			elif light == TrafficSignals.Light.AMBER and not panic and to_stop > v * v / (2.0 * brake) + 1.0:
				must = true
		elif kind == CityPlan.Intersection.STOP_SIGNS or kind == CityPlan.Intersection.ROUNDABOUT:
			# A look either way, then go (a rolling stop more often than not).
			if int(r.stopped_at) != next_k * 2 + dir and not panic:
				must = true
				if to_stop < 0.8 and v < 0.6:
					r.wait = float(r.wait) + delta
					if float(r.wait) > stop_wait:
						r.stopped_at = next_k * 2 + dir
						r.wait = 0.0
		if must:
			limit = minf(limit, sqrt(maxf(2.0 * brake * maxf(to_stop - 0.3, 0.0), 0.0)))
	# The rider ahead in the same lane.
	for o: Dictionary in _riders:
		if o == r or not is_instance_valid(o.node) or int(o.axis) != axis or int(o.index) != index or int(o.dir) != dir:
			continue
		var gap := (float(o.s) - s) * float(dir)
		if gap > 0.0 and gap < 25.0:
			limit = minf(limit, maxf(0.0, (gap - follow_gap) * 0.9) + float(o.v) * 0.6)
	# Whatever stands in the lane ahead.
	if probe:
		r.block_v = _probe_ahead(node, axis, dir, v)
	# Held up by something that does not move (a car left in the lane, a bike lying in it): after
	# a few seconds they go round it, out toward the traffic and back.
	if float(r.swerve) > 0.0:
		r.swerve = float(r.swerve) - delta
	else:
		limit = minf(limit, float(r.block_v))
		if float(r.block_v) < 0.3 and v < 0.3:
			r.stuck = float(r.stuck) + delta
			if float(r.stuck) > 5.0:
				r.stuck = 0.0
				r.swerve = 3.2
		else:
			r.stuck = 0.0
	var dv := limit - v
	v += clampf(dv, -brake * 1.6 * delta, accel * delta)
	v = maxf(v, 0.0)
	if dv < -0.3:
		node.coast(0.6)
	s += float(dir) * v * delta
	# Past the crossing's middle: onto the next stretch.
	if (s - jc) * float(dir) > 0.0:
		r.k = int(r.k) + dir
	r.s = s
	r.v = v
	node.ride_speed = v
	var p := _lane_point(axis, index, dir, s)
	# Out round an obstacle: eased toward the road's middle and back.
	var out := sin(clampf(float(r.swerve) / 3.2, 0.0, 1.0) * PI) * 1.1
	if out > 0.001:
		var to_mid := -signf(Micromobility.ride_offset(plan, axis, index, dir))
		if axis == CityPlan.AXIS_X:
			p.x += to_mid * out
		else:
			p.z += to_mid * out
	node.position = p
	node.rotation.y = _yaw(axis, dir)


## The speed the space ahead of a rider allows: something on the player, props or npc layers
## within the box ahead (a car, a bus at its stop, a walker, another rider's debris) brings it to
## a stop short of it. A quarter-second probe.
func _probe_ahead(node: BikeRider, axis: int, dir: int, v: float) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return INF
	var reach := look_ahead + v * 1.4
	_query_box.size = Vector3(0.6, 1.2, reach)
	var fwd := Vector3(0.0, 0.0, dir) if axis == CityPlan.AXIS_X else Vector3(dir, 0.0, 0.0)
	var centre := node.global_position + global_basis * (fwd * (reach * 0.5 + 0.9) + Vector3.UP * 0.9)
	var basis := Basis(Vector3.UP, _yaw(axis, dir))
	_query.transform = Transform3D(basis, centre)
	_query.exclude = [node.get_rid()]
	var hits := space.intersect_shape(_query, 4)
	if hits.is_empty():
		return INF
	var nearest := reach
	for h: Dictionary in hits:
		var c := h.collider as Node3D
		# Riders follow each other (above); a scooter lying in the gutter is ridden past.
		if c == null or c == node or c is BikeRider or c is EncampmentItem:
			continue
		var d := (c.global_position - node.global_position).dot(global_basis * fwd)
		nearest = minf(nearest, maxf(d, 0.0))
	if nearest >= reach:
		return INF
	return maxf(0.0, (nearest - 2.2) * 1.2)


## Puts a rider exactly somewhere (tests and stills): on lane (axis, index, dir) at `s`, of
## `kind`, at `speed`.
func place_rider(axis: int, index: int, dir: int, s: float, kind: int, speed: float, seed_value: int = 0) -> BikeRider:
	if plan == null:
		plan = get_parent().get("plan") as CityPlan
	var other := 1 - axis
	var k := 0
	while plan.road_pos(other, k + 1) < s:
		k += 1
	while plan.road_pos(other, k) > s:
		k -= 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, "placed", seed_value])
	_spawned += 1
	var paint := Color(0.7, 0.06, 0.05)
	if MicroMesh.PAINTS.has(kind):
		var paints: Array = MicroMesh.PAINTS[kind]
		paint = paints[absi(seed_value) % paints.size()]
	var rider := BikeRider.new()
	rider.setup_rider(kind, hash([plan.seed, "rider", seed_value]), paint)
	rider.name = "Placed%d" % _spawned
	rider.position = _lane_point(axis, index, dir, s)
	rider.rotation.y = _yaw(axis, dir)
	add_child(rider)
	_riders.append({"node": rider, "axis": axis, "index": index, "dir": dir, "k": k, "s": s, "v": speed,
		"want": maxf(speed, 0.1), "wait": 0.0, "stopped_at": -99999, "ended": false, "block_v": INF, "swerve": 0.0, "stuck": 0.0, "placed": true})
	rider.ride_speed = speed
	return rider


## Stills: MICRO_RIDERS="axis,index,dir,s,kind,speed[,seed];..." puts riders exactly there
## (tools/micro_probe.gd lists the lanes), and with MICRO_ONLY=1 no others come.
func _stage(spec: String) -> void:
	for part: String in spec.split(";", false):
		var f := part.split(",")
		if f.size() < 6:
			continue
		place_rider(f[0].to_int(), f[1].to_int(), f[2].to_int(), f[3].to_float(), f[4].to_int(), f[5].to_float(), f[6].to_int() if f.size() > 6 else 0)
	if OS.get_environment("MICRO_ONLY") == "1":
		max_riders = 0
		web_max_riders = 0
