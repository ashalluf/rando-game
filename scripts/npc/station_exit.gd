class_name StationExit
extends RefCounted
## An engine (or an ambulance) going out of its firehouse on a call (wave 8, rc5-fire-station-night,
## docs/HANDOFF.md "The fire station at night"). Before this a unit sent out of a station
## (Emergency.send) appeared standing on the street's centre line in front of the bays while the
## doors began to roll up over an empty bay. Now it starts INSIDE its bay, nose to the door, lights
## going, waits for the door (`DOOR_WAIT`), rolls out across the apron and down the ramp, and
## swings into its lane on a smooth curve; then it is handed back to EmergencyCar._drive_lane()
## where the lane start was. While it comes out the street traffic stops short of the station on
## both sides (`stop_gap()`, one hook in TrafficManager._drive_street) - real crews stop the street
## (a signal, a firefighter in the road) before they pull out.
##
## The path is pure geometry of the station (FireStation's frame and lot, the very numbers
## build_lot() lays the building with): `bays()`, `path_for()`. Nothing rolls a random number.
## STATION_EXIT=0 in the environment is the A/B (the old start on the street).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("STATION_EXIT") != "0"
## Seconds the unit waits in the bay for its door (FireStation.DOOR_TIME is the door's whole roll).
const DOOR_WAIT := 3.0
## Speeds out of the bay: creeping through the door, then up to this at the lane (m/s).
const BAY_SPEED := 3.0
const OUT_SPEED := 6.0
const ACCEL := 2.0
## The swing into the lane: how far down the road the curve lands (m).
const TURN_REACH := 13.0
## Street traffic stops this far short of the bays' centre while a unit comes out (m), and keeps
## stopped until the unit is this far down the road from it (m).
const STOP_SHORT := 20.0
const CLEAR_AFTER := 22.0

## Units coming out now: [axis, index, along of the bays' centre, the unit] each (TRUE world).
static var exiting: Array = []

var car: EmergencyCar
var pts: PackedVector3Array = PackedVector3Array() # TRUE world, every 0.5 m
var yaws: PackedFloat32Array = PackedFloat32Array()
var s: float = 0.0
var speed: float = 0.0
var wait: float = DOOR_WAIT
var start: Array = []
var _entry: Array = []
## The firefighter out at the kerb (StationWatch), or null.
var watch: Node3D = null


## The bays of `station` (a FireStation entry): {"face": the building's front centre (TRUE world
## XZ), "y": its pavement top, "out": unit vector from the building to the street, "x": the
## frame's x along the front, "doors": [x of each door], "to_kerb": metres from the face to the
## kerb}. {} when the station's lot is not there.
static func bays(plan: CityPlan, station: Dictionary) -> Dictionary:
	if station.is_empty() or not station.has("lot"):
		return {}
	var f: Dictionary = station.frame
	var lot: Dictionary = station.lot
	var size: Vector2 = lot.size
	var side: int = station.side
	var along := size.x if side < 2 else size.y
	var depth := size.y if side < 2 else size.x
	var cell: Rect2 = lot.get("cell", Rect2((lot.center as Vector2) - size * 0.5, size))
	var gap_v := ((cell.size.y if side < 2 else cell.size.x) - depth) * 0.5
	var w := minf(along - 1.0, FireStation.MAX_W)
	var d := minf(depth - FireStation.APRON_MIN, FireStation.MAX_D)
	var apron := depth - d
	var a2: Vector2 = f.a
	var n2: Vector2 = f.n
	var face: Vector2 = (f.o as Vector2) + a2 * (float(f.len) * 0.5) + n2 * FireStation.setback(gap_v, apron)
	var out := -n2
	var x_axis := Vector2(out.y, -out.x) # Vector3.UP.cross(outward), FireStation.build_lot's basis
	var bay_w := FireStation.BAY_DOOR.x
	var pier := maxf((w - bay_w * float(FireStation.BAYS) - 4.2) / float(FireStation.BAYS + 1), 0.7)
	var x0 := -w * 0.5 + 4.2 + pier
	var doors: Array = []
	for i in FireStation.BAYS:
		doors.append(x0 + bay_w * 0.5 + float(i) * (bay_w + pier))
	var h := plan.macro.relief_at(face) if plan.macro else 0.0
	return {"face": face, "y": h + CityChunk.SIDEWALK_TOP, "out": out, "x": x_axis, "doors": doors,
		"to_kerb": FireStation.setback(gap_v, apron) + plan.sidewalk_width, "depth": d}


## The door a unit of `length` heading `dir` along the road takes: the one on the side it turns
## toward, so the swing into the lane is the long way round (no unit turns across its own door).
static func door_for(b: Dictionary, road_dir: Vector2) -> float:
	var doors: Array = b.doors
	var x_axis: Vector2 = b.x
	var toward := x_axis.dot(road_dir)
	return float(doors[doors.size() - 1]) if toward > 0.0 else float(doors[0])


## The path out of the bay into the lane `start` (EmergencyCar's [axis, index, dir, point]) for a
## unit `length` long with `lane` its lane offset, as TRUE world points every 0.5 m with headings.
static func path_for(plan: CityPlan, station: Dictionary, start: Array, length: float, lane: float, relief: Callable) -> Dictionary:
	var b := bays(plan, station)
	if b.is_empty():
		return {}
	var axis := int(start[0])
	var dir := int(start[2])
	var road_dir := Vector2(0.0, float(dir)) if axis == CityPlan.AXIS_X else Vector2(float(dir), 0.0)
	var out: Vector2 = b.out
	var x_axis: Vector2 = b.x
	var face: Vector2 = b.face
	var door_x := door_for(b, road_dir)
	var door: Vector2 = face + x_axis * door_x
	# The lane's line and where the curve lands on it.
	var road := plan.road_pos(axis, int(start[1])) + lane
	var door_along := door.y if axis == CityPlan.AXIS_X else door.x
	var land_along := door_along + float(dir) * TURN_REACH
	var land := Vector2(road, land_along) if axis == CityPlan.AXIS_X else Vector2(land_along, road)
	# Straight out to the kerb (the body's centre half a length inside the bay to start), then a
	# cubic onto the lane, tangent to both.
	var p0 := door - out * (length * 0.5 + 0.4)
	var kerb := door + out * float(b.to_kerb)
	var to_lane := absf((land - kerb).dot(out))
	var p1 := kerb + out * minf(1.0, to_lane * 0.3)
	var k := maxf(to_lane, 4.0) * 0.9
	var c1 := p1 + out * k
	var c2 := land - road_dir * k
	var raw: Array = []
	var n0 := int(ceil(p0.distance_to(p1) / 0.25))
	for i in n0:
		raw.append(p0.lerp(p1, float(i) / float(n0)))
	for i in 81:
		var t := float(i) / 80.0
		var u := 1.0 - t
		raw.append(p1 * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + land * t * t * t)
	# Resampled every 0.5 m by arc length; height from the bay floor down the ramp to the road.
	var pts := PackedVector3Array()
	var yaws := PackedFloat32Array()
	var acc := 0.0
	var next := 0.0
	var bay_y := float(b.y)
	var face_d := 0.0
	for i in raw.size():
		if i > 0:
			acc += (raw[i] as Vector2).distance_to(raw[i - 1])
		while acc >= next:
			var q: Vector2 = raw[i]
			var from_face := (q - face).dot(out)
			var ramp := clampf((from_face - (float(b.to_kerb) - 3.4)) / 3.4, 0.0, 1.0)
			var road_y := float(relief.call(q)) + CityChunk.ROAD_TOP
			var y := lerpf(maxf(bay_y, road_y), road_y, smoothstep(0.0, 1.0, ramp))
			pts.append(Vector3(q.x, y, q.y))
			next += 0.5
			face_d = from_face
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var c := pts[mini(i + 1, pts.size() - 1)]
		var d := Vector2(c.x - a.x, c.z - a.z)
		yaws.append(atan2(-d.x, -d.y) if d.length() > 0.01 else 0.0) # facing d: -Z forward
	return {"pts": pts, "yaws": yaws, "door": door, "face": face}


## Puts `car` (just sent by Emergency.send on lane `start`) in its bay and returns the exit that
## drives it out, or null (off, no bays, not out of a station).
static func begin(car: EmergencyCar, plan: CityPlan, station: Dictionary, start: Array) -> StationExit:
	if not enabled or car == null or station.is_empty() or start.size() < 5:
		return null
	var length := float(car._dims().length)
	var p := path_for(plan, station, start, length, float(car.traffic.lane), func(q: Vector2) -> float: return car._relief(q))
	if p.is_empty() or (p.pts as PackedVector3Array).size() < 4:
		return null
	var ex := StationExit.new()
	ex.car = car
	ex.pts = p.pts
	ex.yaws = p.yaws
	ex.start = start
	var face: Vector2 = p.face
	var axis := int(start[0])
	ex._entry = [axis, int(start[1]), face.y if axis == CityPlan.AXIS_X else face.x, car]
	exiting.append(ex._entry)
	car.traffic_speed = 0.0
	ex._pose()
	ex._send_watch(plan, station, start)
	return ex


## The firefighter who stops the street: out of the bay beside the unit to the kerb at the apron's
## corner on the side the traffic comes from (the unit turns away from it), facing it.
func _send_watch(plan: CityPlan, station: Dictionary, lane_start: Array) -> void:
	var em := car.service
	if em == null or not car.is_inside_tree():
		return
	var b := bays(plan, station)
	var axis := int(lane_start[0])
	var dir := int(lane_start[2])
	var road_dir := Vector2(0.0, float(dir)) if axis == CityPlan.AXIS_X else Vector2(float(dir), 0.0)
	var out: Vector2 = b.out
	var door: Vector2 = (b.face as Vector2) + (b.x as Vector2) * door_for(b, road_dir)
	var half := FireStation.BAY_DOOR.x * 0.5
	var spot := door + out * (float(b.to_kerb) - 0.7) - road_dir * (half + 3.2)
	# Out of the bay by the door (the building's one collision box covers the bays: a body made
	# inside it is thrown out), and back to the same place to go in.
	var home := door + out * 0.6 - road_dir * (half + 0.7)
	var look := spot - road_dir * 10.0 + out * 2.0
	var y := float(b.y)
	var w := StationWatch.new()
	w.setup_crew(em, car, EmergencyCrew.Role.FIRE, 1, hash([plan.seed, station.cell, "watch"]))
	w.car = null
	w.unit = car
	w.exit = self
	w.spot = WorldState.to_local(Vector3(spot.x, plan.height_at(spot) + CityChunk.SIDEWALK_TOP + 0.05, spot.y))
	w.home = WorldState.to_local(Vector3(home.x, y + 0.05, home.y))
	w.look = WorldState.to_local(Vector3(look.x, y, look.y))
	em.add_child(w)
	w.global_position = w.home
	em.crews.append(w)
	watch = w


## One physics tick; true while the exit still has the car (EmergencyCar skips its lane driving).
func step(delta: float) -> bool:
	if not is_instance_valid(car):
		_release()
		return false
	if wait > 0.0:
		wait -= delta
		car.traffic_speed = 0.0
		_pose()
		return true
	var total := float(pts.size() - 1) * 0.5
	var target := BAY_SPEED if s < 9.0 else OUT_SPEED
	speed = move_toward(speed, target, ACCEL * delta)
	s += speed * delta
	car.traffic_speed = speed
	if s >= total:
		s = total
		_pose()
		# The lane takes over from here (the curve landed on it, heading down it).
		car.traffic_speed = OUT_SPEED
		return false
	_pose()
	return true


func _pose() -> void:
	var f := s / 0.5
	var i := clampi(int(floor(f)), 0, pts.size() - 2)
	var t := clampf(f - float(i), 0.0, 1.0)
	var p := pts[i].lerp(pts[i + 1], t)
	var yaw := lerp_angle(yaws[i], yaws[i + 1], t)
	var ahead := pts[mini(i + 6, pts.size() - 1)]
	var back := pts[maxi(i - 6, 0)]
	var run := Vector2(ahead.x - back.x, ahead.z - back.z).length()
	var pitch := atan2(ahead.y - back.y, maxf(run, 0.5)) if run > 0.5 else 0.0
	car._place(p + Vector3.UP * car.road_lift(), yaw, pitch)


## Out of the station: the street goes again once the unit is CLEAR_AFTER down the road.
func _release() -> void:
	exiting.erase(_entry)


## Kept on the exiting list until the unit has gone CLEAR_AFTER down the road (called from the
## lane driving's tick through EmergencyCar; cheap).
static func prune() -> void:
	for i in range(exiting.size() - 1, -1, -1):
		var e: Array = exiting[i]
		var u: Variant = e[3]
		if not is_instance_valid(u):
			exiting.remove_at(i)
			continue
		var car := u as EmergencyCar
		if car == null or car._exit != null:
			continue
		var w := WorldState.to_world(car.global_position)
		var along := w.z if int(e[0]) == CityPlan.AXIS_X else w.x
		if absf(along - float(e[2])) > CLEAR_AFTER or car.mode != EmergencyCar.Mode.DISPATCH:
			exiting.remove_at(i)


## For a street car on road (axis, index) running `dir` at `along`: how far ahead it must stop for
## a unit coming out of a station on that road, or INF. Cars already past the bays go on.
static func stop_gap(axis: int, index: int, dir: int, along: float) -> float:
	if exiting.is_empty():
		return INF
	prune()
	var best := INF
	for e: Array in exiting:
		if int(e[0]) != axis or int(e[1]) != index:
			continue
		var ahead := (float(e[2]) - along) * float(dir) - STOP_SHORT
		if ahead > -STOP_SHORT * 0.6 and ahead < best:
			best = maxf(ahead, 0.0)
	return best
