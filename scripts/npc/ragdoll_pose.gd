class_name RagdollPose
extends SkeletonModifier3D
## Poses a jointed ragdoll's skeleton from its rigid bodies (RagdollJoints): every frame each
## driven bone's skeleton-space pose is set from the body it rides and the fixed offset that body
## had to the bone when the doll was made. Bones nobody drives (the spine's middle, the neck,
## hands, feet, fingers) keep the pose of the still idle frame, relative to their parents. Added
## to the skeleton before any LimbHider, so a torn-off limb still collapses after it.

## Bone indices, parents before children, and for each the body it rides and the offset
## (body space -> the bone's world transform, the rig's 0.01 scale included).
var bones: PackedInt32Array = PackedInt32Array()
var rides: Array[Node3D] = []
var offsets: Array[Transform3D] = []


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	var inv := skel.global_transform.affine_inverse()
	for i in bones.size():
		var body := rides[i]
		if body == null or not is_instance_valid(body):
			continue
		skel.set_bone_global_pose(bones[i], inv * body.global_transform * offsets[i])


## Stops driving `bone` (a limb torn off): it falls back to the clip pose under its parent.
func drop_bone(bone: int) -> void:
	var i := bones.find(bone)
	if i < 0:
		return
	bones.remove_at(i)
	rides.remove_at(i)
	offsets.remove_at(i)


## Hands every bone riding `from` over to `to`, keeping where it is now (the doll freezing into
## one body: the limbs' bodies go and their bones ride the pelvis at their last pose).
func rebase(from: Node3D, to: Node3D) -> void:
	var rel := to.global_transform.affine_inverse() * from.global_transform
	for i in bones.size():
		if rides[i] == from:
			rides[i] = to
			offsets[i] = rel * offsets[i]
