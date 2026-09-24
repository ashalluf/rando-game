class_name AimTwist
extends SkeletonModifier3D
## Holds the upper body in a shooting stance while a gun is in the hands. Runs before the arm IK
## (Avatar adds it first) and turns the spine about the skeleton's vertical axis:
##  - the stance: the chest blades toward the gun side and brings the support shoulder forward,
##    while the neck and head turn back so he still looks where he aims. On a square-on torso
##    the left hand ran out of arm half a hand short of every handguard.
##  - the hold: the idle clip swings the hips and shoulders through 50-75 degrees as it shifts
##    weight, and a torso that turns with it took the support shoulder 30 cm away from the gun,
##    past what the arm can reach (tools/grip_fit.gd TRACE=150 shows it). With `hold` at 1 the
##    spine takes back the clip's turn of the shoulder line, so the chest keeps the stance
##    whatever the legs and hips are doing.
## It also reports where the gun shoulder ended up (`shoulder`), because the gun is placed from
## that shoulder and the clip's shoulder is not where the stance puts it.

## [bone index, share of the twist] from the hips up; negative shares turn back.
var bones: Array = []
## The whole twist in radians: positive turns the chest toward the character's right.
var angle: float = 0.0
## 0..1: how much of the clip's turn of the shoulders the spine takes back.
var hold: float = 1.0
## The shoulder-line bones (left, right upper arm) the chest's facing is measured on.
var left_arm: int = -1
var right_arm: int = -1
## Where `right_arm` stood after the last pass, in skeleton space (Vector3.INF before one ran).
var shoulder: Vector3 = Vector3.INF


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var spin := -angle # radians about +Y, spread over the spine by share
	if hold > 0.0 and left_arm >= 0 and right_arm >= 0:
		# A turn by t about +Y lowers atan2(z, x) of the shoulder line by t, so the turn that
		# takes the clip's line back to the rest line is (clip yaw - rest yaw).
		var now := GripHands._chain(skeleton, left_arm).origin - GripHands._chain(skeleton, right_arm).origin
		var rest := skeleton.get_bone_global_rest(left_arm).origin - skeleton.get_bone_global_rest(right_arm).origin
		spin += hold * wrapf(atan2(now.z, now.x) - atan2(rest.z, rest.x), -PI, PI)
	for pair in bones:
		var bone: int = pair[0]
		var share: float = pair[1]
		var parent := skeleton.get_bone_parent(bone)
		if bone < 0 or parent < 0:
			continue
		# The vertical axis in the parent's frame, from the pose as it stands right now (the
		# bones below have already been turned).
		var up := (GripHands._chain(skeleton, parent).basis.orthonormalized().inverse() * Vector3.UP).normalized()
		# Spine bones (positive share) take the stance and the hold; the neck and head (negative)
		# only turn back by the stance, so the face ends up square to the aim. The rigs face +Z,
		# so their right is -X: a turn to the right is negative about +Y.
		var turn := spin * share if share > 0.0 else -angle * share
		var q := Quaternion(up, turn) * skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, q.normalized())
	if right_arm >= 0:
		shoulder = GripHands._chain(skeleton, right_arm).origin
