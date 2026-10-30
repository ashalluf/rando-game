class_name HeroRide
extends SkeletonModifier3D
## The hero on a motorcycle: RideSolver's pose (seat, grips, pegs, a boot down at a stop, the tuck
## and the hang-off the bike asks for, Motorcycle.ride_state()) written over everything the
## modifiers before it did. Added LAST to his skeleton by Motorcycle.mount_rider() and removed
## by dismount_rider(); the base it solves from is his rest pose. The fingers are left to the
## clip and the grip modifier, so they close round the grips.

var bike: Motorcycle
var player: Node3D
var state: Dictionary = {}
var _solver: RideSolver
var _fit: bool = false


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if bike == null or not is_instance_valid(bike) or bike.rider_frame() == null:
		release()
		return
	if _solver == null:
		_solver = RideSolver.new()
		if not _solver.setup(sk):
			_solver = null
			active = false
			return
	var t := sk.global_transform.affine_inverse() * bike.rider_frame().global_transform
	if not _fit:
		_solver.measure(t.basis.get_scale().y)
		_solver.fit(t, bike.geo())
		_fit = true
	_solver.solve(t, bike.geo(), state)


## Lets go of the skeleton (the player got off, or the bike is gone): the clip's pose again.
func release() -> void:
	active = false
	if is_instance_valid(player):
		var vis = player.get("visual")
		if vis is Node3D and bike == null or (bike != null and not is_instance_valid(bike)):
			if vis is Node3D:
				(vis as Node3D).transform = Transform3D(Basis(Vector3.UP, (vis as Node3D).global_rotation.y - player.global_rotation.y), Vector3.ZERO)
	queue_free()
