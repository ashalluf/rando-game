class_name GripHands
extends SkeletonModifier3D
## Turns the hero's hands onto the gun after the arm IK has put the wrists on its grips
## (Avatar.hold_gun). Two-bone IK only places a wrist; left alone, the hand kept the clip's
## rotation relative to the forearm and stuck out flat past the gun. Each hand is given the
## global rotation of its grip marker, which the avatar builds from the gun's
## Weapon.grip_*_fingers / grip_*_palm directions.

## [bone index, marker Node3D] pairs; the marker's global basis is the hand's wanted basis.
var hands: Array = []
## Finger bones closed round the grip: [bone index, rest rotation, local curl axis, angle in
## radians]. Built by Avatar.setup_gun_hands() on a rig that has finger bones (the hero).
var fingers: Array = []


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	for pair in hands:
		var bone: int = pair[0]
		var marker := pair[1] as Node3D
		if bone < 0 or marker == null or not is_instance_valid(marker):
			continue
		var parent := skeleton.get_bone_parent(bone)
		if parent < 0:
			continue
		var want := (to_skeleton * marker.global_transform).basis.orthonormalized()
		var parent_basis := _chain(skeleton, parent).basis.orthonormalized()
		skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * want).get_rotation_quaternion())
	# Then close the fingers. Each joint turns about the axis that carries its tip toward the
	# palm, from its rest pose; the clip's own relaxed finger keys are overridden while the
	# gun is held.
	for f in fingers:
		skeleton.set_bone_pose_rotation(f[0], (f[1] as Quaternion) * Quaternion(f[2] as Vector3, f[3] as float))


## A bone's skeleton-space pose composed from the local poses as they stand right now - after
## the IK earlier in the stack - rather than get_bone_global_pose(), which can still hold the
## pose from before this frame's modifiers ran and turned the hands by the IK's own swing.
static func _chain(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var t := skeleton.get_bone_pose(bone)
	var p := skeleton.get_bone_parent(bone)
	while p >= 0:
		t = skeleton.get_bone_pose(p) * t
		p = skeleton.get_bone_parent(p)
	return t
