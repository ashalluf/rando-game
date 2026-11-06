class_name StationWatch
extends EmergencyCrew
## The firefighter who walks out of the bay ahead of the unit going out on a call and stands at
## the kerb at the apron's corner, facing the traffic coming up the lane the unit turns into, until
## it is out and away; then walks back into the bay and is gone (wave 8, rc5-fire-station-night,
## docs/HANDOFF.md "The fire station at night"). An EmergencyCrew in turnout and helmet, so shot,
## knocked and ragdolled like any responder; only its brain is its own (`_think`). Made by
## StationExit.begin(); STATION_EXIT=0 makes none.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## Where it stands and which way it looks (local space of the scene, set by StationExit), and
## the bay it goes back into.
var spot := Vector3.INF
var look := Vector3.INF
var home := Vector3.INF
var exit: StationExit = null
## The unit it sees out (not `car`: a watch knocked down is not one of that unit's crew).
var unit: EmergencyCar = null
var _going_home := false
var _watch_t := 0.0


func _ready() -> void:
	super._ready()
	job = Job.BACKUP


func _physics_process(delta: float) -> void:
	_watch_t += delta
	super._physics_process(delta)


func _think() -> void:
	_set_pose("")
	var out := exit != null and is_instance_valid(unit) and (unit._exit == exit or _unit_near())
	if out and not _going_home and _watch_t < 60.0:
		_dest = spot
		_face = look
		task = Task.GO
		return
	_going_home = true
	task = Task.RETURN
	_dest = home
	_face = Vector3.INF
	var d := global_position - home
	d.y = 0.0
	if d.length() < 0.8 or _watch_t > 90.0:
		if service:
			service.crews.erase(self)
		queue_free()


## The unit is still on the stretch in front of the station (StationExit keeps the street stopped).
func _unit_near() -> bool:
	for e: Array in StationExit.exiting:
		if e[3] == unit:
			return true
	return false
