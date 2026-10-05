class_name HeroMotion
extends SkeletonModifier3D
## The hero's procedural layer, run FIRST in his skeleton's modifier stack (before the gun stance,
## the arm IK and the hands, Avatar.setup_gun_hands()), over whatever clip is playing:
##  - the flight pose (`fly`, 0..1): legs together and pointed, the free left arm swept back along
##    the body, the back arched and the head lifted to look along the flight (`look_up`, radians:
##    how far the body is tipped over, which is how far the head must come back). The body itself
##    is laid along the velocity by Avatar, and the right fist - the gun - goes forward there.
##  - the fall pose (`fall`, 0..1): the left arm thrown out for balance, the head down at the
##    ground coming up.
##  - the hit flinch (`flinch`): the chest knocked away from a round, a skeleton-space vector
##    whose direction is where the top of the spine goes and whose length is the angle (radians);
##    Avatar runs it as a spring. The head goes a little further than the chest.
##  - the foot IK (`foot_lift`, per foot in metres, and `hips_drop`): planted feet on uneven
##    ground. The hips come down by the deeper foot and each leg is bent (an analytic two-bone
##    solve in the knee's own plane) so the ankle lands where Avatar's ray found the ground; the
##    foot keeps its clip rotation.
## Directions are the rig's skeleton space: it faces +Z, Y up, his LEFT is +X.

## [bone, direction] the flight pose aims each bone's length at (right side mirrored unless given).
const FLY_AIMS := [
	["LeftUpLeg", Vector3(0.05, -1.0, -0.08)], ["RightUpLeg", Vector3(-0.03, -1.0, -0.04)],
	["LeftLeg", Vector3(0.03, -0.97, -0.22)], ["RightLeg", Vector3(-0.03, -0.9, -0.42)],
	["LeftFoot", Vector3(0.0, -0.75, -0.35)], ["RightFoot", Vector3(0.0, -0.6, -0.55)],
	["LeftArm", Vector3(0.3, -0.92, -0.22)], ["LeftForeArm", Vector3(0.14, -0.97, -0.2)],
	["LeftHand", Vector3(0.06, -0.98, -0.18)],
]
const FALL_AIMS := [
	["LeftArm", Vector3(0.93, 0.25, 0.12)], ["LeftForeArm", Vector3(0.8, 0.5, 0.3)],
	["LeftHand", Vector3(0.7, 0.45, 0.55)],
]
## Bone -> the child whose head gives its direction.
const CHILD := {
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase",
	"LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand", "LeftHand": "LeftHandMiddle1",
}

var fly: float = 0.0
var look_up: float = 0.0
var fall: float = 0.0
var flinch: Vector3 = Vector3.ZERO
## Metres each foot is lifted (left, right; negative lowers it) and the hips are lowered.
var foot_lift: Vector2 = Vector2.ZERO
var hips_drop: float = 0.0
## Skeleton units per metre (the rigs are in centimetres under a 0.01 armature).
var units: float = 100.0

var _ids := {}


func _bone(name: String) -> int:
	if not _ids.has(name):
		var sk := get_skeleton()
		_ids[name] = sk.find_bone(name) if sk else -1
	return _ids[name]


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if hips_drop > 0.0005 or foot_lift != Vector2.ZERO:
		_feet(sk)
	if fly > 0.001:
		_aim_set(sk, FLY_AIMS, fly)
		for pair in [["Spine01", -0.12], ["Spine", -0.1], ["neck", -0.35], ["Head", -0.45]]:
			_turn(sk, _bone(pair[0]), Vector3.RIGHT, look_up * float(pair[1]) * fly)
	if fall > 0.001:
		_aim_set(sk, FALL_AIMS, fall)
		_turn(sk, _bone("Head"), Vector3.RIGHT, 0.3 * fall)
	if flinch.length_squared() > 1e-6:
		var axis := Vector3.UP.cross(flinch.normalized())
		if axis.length_squared() > 1e-6:
			var a := flinch.length()
			for pair in [["Spine02", 0.25], ["Spine01", 0.35], ["Spine", 0.4], ["Head", 0.5]]:
				_turn(sk, _bone(pair[0]), axis.normalized(), a * float(pair[1]))


## Turns a bone about a skeleton-space axis, after what the clip and the layers before did.
func _turn(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 1e-5:
		return
	var p := sk.get_bone_parent(bone)
	var pb := GripHands._chain(sk, p).basis.orthonormalized() if p >= 0 else Basis()
	var local_axis := (pb.inverse() * axis).normalized()
	sk.set_bone_pose_rotation(bone, (Quaternion(local_axis, angle) * sk.get_bone_pose_rotation(bone)).normalized())


func _aim_set(sk: Skeleton3D, aims: Array, w: float) -> void:
	for pair in aims:
		_aim(sk, pair[0], pair[1], w)


## Swings a bone so its length points along `want` (skeleton space), by weight w.
func _aim(sk: Skeleton3D, name: String, want: Vector3, w: float) -> void:
	var b := _bone(name)
	var c := _bone(CHILD.get(name, ""))
	if b < 0 or c < 0:
		return
	var g := GripHands._chain(sk, b)
	var cur := (g.basis.orthonormalized() * sk.get_bone_pose_position(c)).normalized()
	var to := want.normalized()
	if cur.length_squared() < 0.5 or cur.dot(to) > 0.99999:
		return
	var swing := Quaternion(cur, to)
	if cur.dot(to) < -0.9999:
		return
	var gq := g.basis.orthonormalized().get_rotation_quaternion()
	var target := (Quaternion.IDENTITY.slerp(swing, w) * gq).normalized()
	var p := sk.get_bone_parent(b)
	var pq := GripHands._chain(sk, p).basis.orthonormalized().get_rotation_quaternion() if p >= 0 else Quaternion.IDENTITY
	sk.set_bone_pose_rotation(b, (pq.inverse() * target).normalized())


## The hips down and each leg bent so its ankle moves up by its foot's lift (see the header).
func _feet(sk: Skeleton3D) -> void:
	var hips := _bone("Hips")
	if hips < 0:
		return
	var up := Vector3.UP # the skeleton's up: the body is upright whenever the feet are planted
	sk.set_bone_pose_position(hips, sk.get_bone_pose_position(hips) - up * hips_drop * units)
	var sides := [["LeftUpLeg", "LeftLeg", "LeftFoot", foot_lift.x], ["RightUpLeg", "RightLeg", "RightFoot", foot_lift.y]]
	for s in sides:
		var hb := _bone(s[0])
		var kb := _bone(s[1])
		var ab := _bone(s[2])
		if hb < 0 or kb < 0 or ab < 0:
			continue
		var foot_rot := GripHands._chain(sk, ab).basis.orthonormalized().get_rotation_quaternion()
		var H := GripHands._chain(sk, hb).origin
		var K := GripHands._chain(sk, kb).origin
		var A := GripHands._chain(sk, ab).origin
		# The ankle went down with the hips; it goes back up by that and by the ground's rise.
		var T := A + up * (hips_drop + float(s[3])) * units
		var l1 := H.distance_to(K)
		var l2 := K.distance_to(A)
		var d := clampf(H.distance_to(T), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
		# The knee: interior angle now and wanted (law of cosines), turned in the leg's plane.
		var n := (K - H).cross(A - K)
		if n.length_squared() < 1e-6:
			n = GripHands._chain(sk, hb).basis.x
		n = n.normalized()
		var now_cos := clampf((K - H).normalized().dot((A - K).normalized()), -1.0, 1.0)
		var want_cos := clampf((d * d - l1 * l1 - l2 * l2) / (2.0 * l1 * l2), -1.0, 1.0)
		var bend := acos(want_cos) - acos(now_cos)
		_turn(sk, kb, n, bend)
		# Then the whole leg swung so the ankle is on the target.
		var A2 := GripHands._chain(sk, ab).origin
		var from := (A2 - H).normalized()
		var to := (T - H).normalized()
		if from.dot(to) < 0.99999:
			var hq := GripHands._chain(sk, hb).basis.orthonormalized().get_rotation_quaternion()
			var p := sk.get_bone_parent(hb)
			var pq := GripHands._chain(sk, p).basis.orthonormalized().get_rotation_quaternion() if p >= 0 else Quaternion.IDENTITY
			sk.set_bone_pose_rotation(hb, (pq.inverse() * (Quaternion(from, to) * hq)).normalized())
		# The foot keeps the clip's own rotation (flat on flat ground).
		var kq := GripHands._chain(sk, kb).basis.orthonormalized().get_rotation_quaternion()
		sk.set_bone_pose_rotation(ab, (kq.inverse() * foot_rot).normalized())
