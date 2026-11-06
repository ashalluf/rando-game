class_name SwimPose
extends SkeletonModifier3D
## The hero's swimming strokes, keyed in code over whatever clip is playing (the idle), second in
## his modifier stack after HeroMotion (Avatar.load_model()); Swim (scripts/player/swim.gd) drives
## it. The free animation library has no swimming clips and the store it comes from is out of
## reach of this build, so the strokes are worked out per frame from a phase, the way the hero's
## idle variants are keyed (tools/hero/hero_clips.gd): each bone's length aimed at a direction in
## the rig's skeleton space (faces +Z, Y up, his LEFT is +X), as if he stood upright; Avatar lays
## the whole body over (prone, on its side, head down) about the hips.
##
## Four strokes, blended by weights that sum to one:
##  - CRAWL: the front crawl. Each arm turns a full circle at the shoulder - the catch overhead,
##    the pull down under the body with the elbow bent (the hand under it), the push past the hip,
##    and the recovery out of the water with the elbow high - the two arms half a cycle apart; the
##    body rolls toward the pulling arm, the head turns to breathe every other stroke on the left,
##    and the legs flutter, three kicks a stroke.
##  - TREAD: upright, treading water: the arms sculling out in front, the legs eggbeating.
##  - BREAST: under the water: the arms sweep out and in from overhead and shoot forward, the legs
##    whip-kick, then a glide.
##  - STREAM: the streamline - arms locked overhead, legs together - with a dolphin kick rolling
##    down from the hips (`kick`): the boost under water and the leap out of it.

enum Stroke { CRAWL, TREAD, BREAST, STREAM }

## 0..1: how much of the pose is the swim's (0 hands the skeleton back to the clips).
var weight: float = 0.0
## Weights of the four strokes (Stroke order).
var mix: PackedFloat32Array = PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
## The stroke's phase, radians (a whole crawl cycle, both arms, is TAU).
var phase: float = 0.0
## How hard the legs kick, 0..1 (the dolphin kick and the flutter).
var kick: float = 1.0
## 0..1: the head turned to breathe (the crawl).
var breathe: float = 0.0

const CHILD := {
	"Spine02": "Spine01", "Spine01": "Spine", "Spine": "neck", "neck": "Head",
	"LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand", "LeftHand": "LeftHandMiddle1",
	"RightArm": "RightForeArm", "RightForeArm": "RightHand", "RightHand": "RightHandMiddle1",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase",
}
## Aimed in this order: parents before children.
const ORDER := ["Spine02", "Spine01", "Spine", "neck",
	"LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]

var _ids := {}


func _bone(bone_name: String) -> int:
	if not _ids.has(bone_name):
		var sk := get_skeleton()
		_ids[bone_name] = sk.find_bone(bone_name) if sk else -1
	return _ids[bone_name]


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or weight < 0.001:
		return
	var want := targets(phase, mix, kick)
	for b: String in ORDER:
		if want.has(b):
			_aim(sk, b, want[b], weight)
	# The roll of the crawl, toward the arm that is pulling, and the breath on the left.
	var roll := mix[Stroke.CRAWL] * 0.42 * sin(phase)
	_turn(sk, _bone("Spine02"), Vector3.UP, roll * 0.5 * weight)
	_turn(sk, _bone("Spine"), Vector3.UP, roll * 0.5 * weight)
	_turn(sk, _bone("Head"), Vector3.UP, (1.0 * breathe - roll * 0.8) * weight * mix[Stroke.CRAWL])
	# Treading, the head is up looking ahead; in the strokes it is in line with the spine.
	_turn(sk, _bone("Head"), Vector3.RIGHT, -0.25 * mix[Stroke.TREAD] * weight)


## The directions every bone's length is aimed at for this phase (skeleton space, upright).
## Static and pure, so the checks can ask it.
static func targets(ph: float, w: PackedFloat32Array, kick_amount: float = 1.0) -> Dictionary:
	var out := {}
	var parts: Array[Dictionary] = [_crawl(ph, kick_amount), _tread(ph), _breast(ph), _stream(ph, kick_amount)]
	for k in parts.size():
		if w[k] <= 0.0001:
			continue
		for b: String in parts[k]:
			out[b] = (out.get(b, Vector3.ZERO) as Vector3) + (parts[k][b] as Vector3).normalized() * w[k]
	for b: String in out:
		out[b] = (out[b] as Vector3).normalized() if (out[b] as Vector3).length_squared() > 1e-6 else Vector3.UP
	return out


static func _straight(out: Dictionary) -> void:
	for b in ["Spine02", "Spine01", "Spine", "neck"]:
		out[b] = Vector3(0.0, 1.0, 0.03)


## One arm of the front crawl at its own phase u (0..1): upper arm, forearm.
static func _crawl_arm(u: float, side: float) -> Array:
	var upper: Vector3
	var bend: float
	if u < 0.62:
		# The catch and the pull: overhead, down through the water under the body, past the hip.
		var a := u / 0.62 * PI
		upper = Vector3(side * (0.16 - 0.1 * sin(a)), cos(a), sin(a))
		bend = 0.25 + 1.2 * sin(a) * (1.0 - 0.6 * u)
	else:
		# The recovery: out of the water and round with the elbow high, wide.
		var a := PI + (u - 0.62) / 0.38 * PI
		upper = Vector3(side * (0.18 + 0.75 * -sin(a)), cos(a), 0.55 * sin(a))
		bend = 1.7 * -sin(a)
	upper = upper.normalized()
	# The forearm bends toward the body's front (down, when he lies prone): the hand under the
	# elbow in the pull, hanging from the high elbow in the recovery.
	var n := Vector3(0.0, 0.0, 1.0) - upper * upper.z
	if n.length_squared() < 1e-4:
		n = Vector3(0.0, -1.0, 0.0)
	n = n.normalized()
	var fore := (upper * cos(bend) + n * sin(bend)).normalized()
	return [upper, fore]


static func _crawl(ph: float, kick_amount: float) -> Dictionary:
	var out := {}
	_straight(out)
	var u := fposmod(ph / TAU, 1.0)
	var r := _crawl_arm(u, -1.0)
	var l := _crawl_arm(fposmod(u + 0.5, 1.0), 1.0)
	out["RightArm"] = r[0]
	out["RightForeArm"] = r[1]
	out["RightHand"] = r[1] + Vector3(0.0, 0.0, 0.15)
	out["LeftArm"] = l[0]
	out["LeftForeArm"] = l[1]
	out["LeftHand"] = l[1] + Vector3(0.0, 0.0, 0.15)
	_flutter(out, ph, kick_amount)
	return out


## Six beats a cycle, the legs half a beat apart, from the hips, the knees following.
static func _flutter(out: Dictionary, ph: float, kick_amount: float) -> void:
	for s in [[1.0, "Left"], [-1.0, "Right"]]:
		var side: float = s[0]
		var k := sin(3.0 * ph + (0.0 if side > 0.0 else PI)) * kick_amount
		out[s[1] + "UpLeg"] = Vector3(side * 0.07, -1.0, 0.16 * k)
		out[s[1] + "Leg"] = Vector3(side * 0.05, -1.0, 0.16 * k - 0.18 * (0.5 + 0.5 * k) * kick_amount)
		out[s[1] + "Foot"] = Vector3(side * 0.04, -0.92, -0.12)


static func _tread(ph: float) -> Dictionary:
	var out := {}
	_straight(out)
	for s in [[1.0, "Left", 0.0], [-1.0, "Right", PI]]:
		var side: float = s[0]
		var p: float = ph * 0.9 + float(s[2])
		# Sculling: the arms out in front and to the side, the forearms sweeping in and out.
		out[s[1] + "Arm"] = Vector3(side * (0.78 + 0.12 * sin(p)), -0.32, 0.48)
		out[s[1] + "ForeArm"] = Vector3(side * (0.25 + 0.45 * sin(p)), -0.12, 1.0)
		out[s[1] + "Hand"] = Vector3(side * (0.25 + 0.6 * sin(p)), -0.2, 1.0)
		# The eggbeater: the knees out and up, the shins circling.
		out[s[1] + "UpLeg"] = Vector3(side * 0.42, -0.78, 0.42)
		out[s[1] + "Leg"] = Vector3(side * (0.3 + 0.32 * cos(p * 1.3)), -1.0, -0.15 + 0.35 * sin(p * 1.3))
		out[s[1] + "Foot"] = Vector3(side * 0.35, -0.35, 0.85)
	return out


## The breaststroke: pull (0 - 0.32), recovery shooting forward (0.32 - 0.5), kick (0.45 - 0.7),
## glide.
static func _breast(ph: float) -> Dictionary:
	var out := {}
	_straight(out)
	var u := fposmod(ph / TAU, 1.0)
	for s in [[1.0, "Left"], [-1.0, "Right"]]:
		var side: float = s[0]
		var upper: Vector3
		var fore: Vector3
		if u < 0.32:
			var t := u / 0.32
			upper = Vector3(side * sin(t * PI * 0.5) * 0.95, cos(t * PI * 0.6), 0.25 + 0.3 * t)
			fore = upper.lerp(Vector3(-side * 0.6, -0.2, 0.9), smoothstep(0.4, 1.0, t))
		elif u < 0.5:
			var t := (u - 0.32) / 0.18
			upper = Vector3(side * 0.55, -0.1, 0.8).lerp(Vector3(side * 0.08, 1.0, 0.08), t)
			fore = Vector3(-side * 0.6, -0.2, 0.9).lerp(Vector3(side * 0.04, 1.0, 0.02), t)
		else:
			upper = Vector3(side * 0.08, 1.0, 0.08)
			fore = Vector3(side * 0.04, 1.0, 0.02)
		out[s[1] + "Arm"] = upper
		out[s[1] + "ForeArm"] = fore
		out[s[1] + "Hand"] = fore
		var draw := smoothstep(0.38, 0.5, u) * (1.0 - smoothstep(0.55, 0.68, u))
		out[s[1] + "UpLeg"] = Vector3(side * (0.06 + 0.3 * draw), -1.0, 0.55 * draw)
		out[s[1] + "Leg"] = Vector3(side * (0.05 + 0.55 * draw), -1.0 + 0.5 * draw, -1.1 * draw)
		out[s[1] + "Foot"] = Vector3(side * (0.05 + 0.6 * draw), -0.9 + 0.5 * draw, -0.12 + 0.7 * draw)
	return out


static func _stream(ph: float, kick_amount: float) -> Dictionary:
	var out := {}
	_straight(out)
	var k := sin(ph * 2.0) * kick_amount
	for s in [[1.0, "Left"], [-1.0, "Right"]]:
		var side: float = s[0]
		out[s[1] + "Arm"] = Vector3(side * 0.12, 1.0, 0.06)
		out[s[1] + "ForeArm"] = Vector3(side * 0.02, 1.0, 0.04)
		out[s[1] + "Hand"] = Vector3(side * 0.0, 1.0, 0.06)
		out[s[1] + "UpLeg"] = Vector3(side * 0.03, -1.0, 0.22 * k)
		out[s[1] + "Leg"] = Vector3(side * 0.02, -1.0, 0.2 * sin(ph * 2.0 - 1.1) * kick_amount - 0.06)
		out[s[1] + "Foot"] = Vector3(side * 0.02, -0.95, 0.25 * sin(ph * 2.0 - 2.0) * kick_amount - 0.2)
	return out


func _turn(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 1e-5:
		return
	var p := sk.get_bone_parent(bone)
	var pb := GripHands._chain(sk, p).basis.orthonormalized() if p >= 0 else Basis()
	var local_axis := (pb.inverse() * axis).normalized()
	sk.set_bone_pose_rotation(bone, (Quaternion(local_axis, angle) * sk.get_bone_pose_rotation(bone)).normalized())


## Swings a bone so its length points along `want` (skeleton space), by weight w (HeroMotion's).
func _aim(sk: Skeleton3D, bone_name: String, want: Vector3, w: float) -> void:
	var b := _bone(bone_name)
	var c := _bone(CHILD.get(bone_name, ""))
	if b < 0 or c < 0:
		return
	var g := GripHands._chain(sk, b)
	var cur := (g.basis.orthonormalized() * sk.get_bone_pose_position(c)).normalized()
	var to := want.normalized()
	if cur.length_squared() < 0.5 or cur.dot(to) > 0.99999:
		return
	var swing := arc(cur, to)
	var gq := g.basis.orthonormalized().get_rotation_quaternion()
	var target := (Quaternion.IDENTITY.slerp(swing, w) * gq).normalized()
	var p := sk.get_bone_parent(b)
	var pq := GripHands._chain(sk, p).basis.orthonormalized().get_rotation_quaternion() if p >= 0 else Quaternion.IDENTITY
	sk.set_bone_pose_rotation(b, (pq.inverse() * target).normalized())


## The shortest turn from a to b (unit vectors), including half a turn (an arm hanging down
## swung straight overhead), which Quaternion(a, b) cannot do.
static func arc(a: Vector3, b: Vector3) -> Quaternion:
	if a.dot(b) > -0.9995:
		return Quaternion(a, b)
	var axis := a.cross(Vector3(1.0, 0.0, 0.0))
	if axis.length_squared() < 1e-4:
		axis = a.cross(Vector3(0.0, 0.0, 1.0))
	return Quaternion(axis.normalized(), PI)
