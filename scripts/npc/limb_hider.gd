class_name LimbHider
extends SkeletonModifier3D
## Makes limbs that have been blown off disappear from a skinned character: every frame, after
## the animation has posed the skeleton, each listed bone is scaled to almost nothing, which
## collapses it and everything below it into its joint. A modifier and not a plain
## set_bone_pose_scale(), because the clips key scale too and would put the limb straight back.

## Skeleton bone indices to collapse (the root of each lost limb is enough; its children follow).
var bones: PackedInt32Array = PackedInt32Array()


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for b in bones:
		if b >= 0 and b < skel.get_bone_count():
			skel.set_bone_pose_scale(b, Vector3.ONE * 0.001)
