class_name FallingPole
extends RigidBody3D
## A felled lamp post, sign or signal (PropBreak._topple()): one body of the whole pole, swung
## over on a hinge at its foot - so it goes down from the base like a real post, not tumbling off
## into the air - then let go once it is well over (or after `HOLD_SECONDS`), so it slams onto the
## street, bounces and lies there. The slam is heard and throws a little dust.

const HOLD_SECONDS := 2.2
## Let go past this tilt from upright (radians).
const RELEASE_ANGLE := 1.15

var _joint: HingeJoint3D
var _t: float = 0.0
var _landed: bool = false
var _passer: PhysicsBody3D


func _init() -> void:
	name = "FallingPole"
	collision_layer = 4
	collision_mask = 7
	continuous_cd = true
	angular_damp = 0.4


## Hinges the pole to the chunk's props body (a fixed point) at its foot, turning about `axis`.
func hinge(ch: CityChunk, axis: Vector3) -> void:
	if ch._statics == null:
		return
	_joint = HingeJoint3D.new()
	_joint.name = "FallHinge"
	# A hinge turns about its own Z axis.
	var z := axis.normalized()
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	_joint.transform = Transform3D(Basis(x, z.cross(x), z), position)
	ch.add_child(_joint)
	_joint.node_a = _joint.get_path_to(ch._statics)
	_joint.node_b = _joint.get_path_to(self)


## Lets `body` (the car that felled it) through until the pole is on the ground.
func pass_through(body: PhysicsBody3D) -> void:
	_passer = body
	add_collision_exception_with(body)


func tilt() -> float:
	return acos(clampf(global_basis.y.normalized().dot(Vector3.UP), -1.0, 1.0))


func _physics_process(delta: float) -> void:
	_t += delta
	var a := tilt()
	if _joint and (a > RELEASE_ANGLE or _t > HOLD_SECONDS):
		_joint.queue_free()
		_joint = null
	if not _landed and a > 1.35:
		_landed = true
		var top := global_transform * Vector3(0.0, 3.0, 0.0)
		Sfx.play("crash", top, 4.0, 0.75)
		Sfx.play("hit_metal", top, 2.0, 0.55)
		WeaponFX._puff_layer(get_parent(), top, 10, 1.6, 1.4, 1.0, 3.0, -0.5,
				WeaponFX._ramp([Color(0.55, 0.52, 0.48, 0.4), Color(0.6, 0.58, 0.55, 0.0)]), false, 70.0, 2.4)
	if _passer and (_t > 3.0 or not is_instance_valid(_passer)):
		if is_instance_valid(_passer):
			remove_collision_exception_with(_passer)
		_passer = null
	if _landed and _t > 6.0 and _passer == null:
		set_physics_process(false)


func _exit_tree() -> void:
	if _joint and is_instance_valid(_joint):
		_joint.queue_free()
