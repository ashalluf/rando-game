class_name RcSurfDawn
extends RefCounted
## The surf at dawn from the water (wave 8, refcam5 `surf_dawn`, docs/HANDOFF.md "The surf at dawn
## from the water"): BeachActivity's hooks for a surfer riding the drawn wave (SurfRide), and the
## view's other fixes. RC5_SURF_DAWN=0 (SurfRide.enabled) is the A/B.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## How fast (m/s) the rider runs down the line along the shore while the wave carries him in.
const TRIM_SPEED := 2.4
## Most the board and the rider are tipped to the face (radians).
const MAX_TILT := 0.6
## How far over the surface the board's deck rides (the node's origin is the board's top).
const RIDE_LIFT := 0.06


static func _state(act: BeachActivity) -> Array:
	if act.sea_state.is_empty():
		act.sea_state = SeaSurface.state(act.get_tree())
	return act.sea_state


## A staged ride (BEACH_STAGE): the place along the shore and the set wave SurfRide.stage_pick() finds.
static func stage_ride(act: BeachActivity, w: Dictionary) -> void:
	var m := act.plan_ref.macro
	var st := _state(act)
	var pick := SurfRide.stage_pick(m, st, float(w.z), SurfRide.now())
	w.z = pick.x
	w.z_home = pick.x
	w.wave = pick.y
	var rp := SurfRide.ride_point(m, st, pick.x, pick.y, SurfRide.now())
	w.s = rp.x
	if OS.get_environment("SURF_DEBUG") == "1":
		var sc := SurfRide.crest_s(m, st[2], pick.x, pick.y, SurfRide.now())
		print("SURF stage z=%.1f wave=%d crest_s=%.1f rider_s=%.1f x=%.2f y=%.2f slope=%.2f gain=%.2f brk=%.1f" % [
			pick.x, int(pick.y), sc, rp.x, m.coast_x(pick.x) - rp.x, rp.y, rp.z,
			SurfRide.gain(m, st[2], pick.x, pick.y), (st[2] as Vector4).w])


## Paddling in to the break: catch the wave whose crest is coming up behind.
static func catch(act: BeachActivity, w: Dictionary) -> void:
	var m := act.plan_ref.macro
	var st := _state(act)
	w.wave = SurfRide.wave_at(m, st[2], float(w.z), float(w.s), SurfRide.now())


## Riding: carried in by wave n, trimming down the line.
static func ride_tick(act: BeachActivity, w: Dictionary, dt: float) -> void:
	var m := act.plan_ref.macro
	var st := _state(act)
	w.z = float(w.z) + float(w.dir_z) * TRIM_SPEED * dt
	var rp := SurfRide.ride_point(m, st, float(w.z), float(w.wave), SurfRide.now())
	w.s = rp.x


## The rider on the face: on the drawn surface, tipped to its slope, side-on.
static func place_ride(act: BeachActivity, w: Dictionary, _x: float) -> void:
	var m := act.plan_ref.macro
	var st := _state(act)
	var z := float(w.z)
	var rp := SurfRide.ride_point(m, st, z, float(w.wave), SurfRide.now())
	var p := SurfRide.point(m, z, rp.x)
	# The face rises seaward (-x in the world here: the sea is west); its normal leans landward.
	var n := Vector3(clampf(rp.z, -1.2, 1.2), 1.0, 0.0).normalized()
	var ang := minf(acos(clampf(n.y, -1.0, 1.0)), MAX_TILT)
	var axis := Vector3.UP.cross(n)
	var tilt := Basis(axis.normalized(), ang) if axis.length() > 0.0001 else Basis.IDENTITY
	var node: Node3D = w.node
	node.transform = Transform3D(tilt * Basis(Vector3.UP, float(w.yaw)), Vector3(p.x, rp.y + RIDE_LIFT, z))
	var board: Node3D = w.board
	board.transform = Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, -0.05, 0.0))
