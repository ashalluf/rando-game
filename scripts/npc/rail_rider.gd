class_name RailRider
extends Pedestrian
## Someone at a Coral Line station (LightRailKit puts a few on each platform of a FULL chunk,
## inside the crowd cap): they drift along the island platform and mostly stand, waiting. When a
## train dwells with its doors open, LightRailSystem sends some of the waiting to a door
## (`board()`: they walk to it and are gone, aboard) and lets others off (`alight()`: they come
## out of a door and walk off the platform's end, down the ramp, and are gone). Everything else -
## the look, the gait, panic, being shot or knocked down - is Pedestrian's.

var line: LightRail
## The station this rider waits at (an index of LightRail.stations).
var station := 0
## 0 waiting, 1 walking to a door to board, 2 leaving the platform after alighting.
var state := 0
var _goal := Vector2.ZERO


func _init() -> void:
	cross_chance = 0.0
	pause_chance = 0.8
	pause_seconds = Vector2(6.0, 22.0)
	add_to_group("rail_rider")


## The platform's deck under a point, else the street (the ramp's foot and beyond).
func _ground_y(x: float, z: float, fallback: float) -> float:
	if line == null:
		return super(x, z, fallback)
	var st: Dictionary = line.stations[station]
	var s := line.nearest_s(Vector2(x, z))
	var along := absf(s - float(st.s))
	var deck := float(line.sample(s).y) + LightRail.PLATFORM_HEIGHT + 0.1
	if along <= LightRail.PLATFORM_LENGTH * 0.5:
		return deck
	var street := super(x, z, fallback)
	if int(st.mode) == LightRail.Mode.GRADE and along < LightRail.PLATFORM_LENGTH * 0.5 + LightRail.RAMP_RUN:
		return lerpf(deck, street, (along - LightRail.PLATFORM_LENGTH * 0.5) / LightRail.RAMP_RUN)
	return street


## A spot on the platform to drift to (or the goal, while boarding or leaving).
func _random_ring_point(_sidewalk: float) -> Vector2:
	if state != 0:
		return _goal
	if line == null:
		return Vector2(position.x, position.z)
	var st: Dictionary = line.stations[station]
	var s := float(st.s) + _rng.randf_range(-LightRail.PLATFORM_LENGTH * 0.42, LightRail.PLATFORM_LENGTH * 0.42)
	var smp := line.sample(s)
	var d: Vector2 = smp.dir
	var r := Vector2(-d.y, d.x)
	var w := float(st.width) * 0.5 - 0.9
	return (smp.pos as Vector2) + r * _rng.randf_range(-w, w)


## Off to a door at `door` (world XZ) and aboard.
func board(door: Vector2) -> void:
	state = 1
	_goal = door
	_pause_left = 0.0
	_pause_next = 0.0
	_go_to(door)


## Out of a door and away: walks to `exit` (world XZ, the platform's end) and is gone.
func alight(exit: Vector2) -> void:
	state = 2
	_goal = exit
	_pause_left = 0.0
	_pause_next = 0.0
	_go_to(exit)


func _physics_process(delta: float) -> void:
	super(delta)
	if state != 0 and not is_queued_for_deletion():
		var here := Vector2(position.x, position.z)
		if here.distance_to(_goal) < 0.8:
			queue_free()
