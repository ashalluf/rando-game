class_name HeroLoco
extends SkeletonModifier3D
## The hero's locomotion pose (docs/HANDOFF.md "The hero's locomotion"), run FIRST in his
## skeleton's stack, before HeroMotion (whose foot IK and hips drop then bend the legs it posed),
## the gun stance, the arm IK and the hands - so the gun stays in his hand through every move.
##
## The AnimationPlayer keeps playing the idle (or a one-shot) underneath; this modifier samples
## the gait clips itself and lays them over it by `weight`, so going from standing to walking,
## from the walk to the run to the sprint, and back to standing is a weight that moves, never a
## clip swap: nothing pops.
##  - Phase sync: one gait `phase` (0..1, 0 = the left toe touching down) drives every gait clip,
##    each sampled at its own time for that phase (GAITS: length and left touchdown of each clip,
##    measured by tools/hero_locomotion/gait_probe.gd), so walk, run and sprint blend foot for
##    foot. Avatar advances the phase by the blended cadence; a negative rate plays it backward
##    (the backpedal).
##  - `hips_yaw` (radians, + turns the hips to his left about the vertical): the lower body turned
##    toward where he is going while the chest keeps facing where he looks - the strafe, the
##    backpedal and the feet staying planted while the body turns on the spot until he steps.
##    The spine takes the turn back (`counter` of it) so the chest stays square.
##  - `drive` (radians, + forward): the chest pitched into an acceleration, back against a stop.
## Directions are the rig's skeleton space: it faces +Z, Y up, his LEFT is +X.

## The gait clips: [clip, length (s), the left toe's touchdowns in it (s; one a stride cycle),
## where the right toe comes down in a cycle (0..1)]. tools/hero_locomotion/gait_probe.gd prints
## them; tests/hero_locomotion_2_checks.gd holds the table to the clips. These are the sync
## markers: the phase counts cycles, cycle k of a clip runs from its k-th left touchdown to the
## next, and the phase wraps at `period()` (every clip's cycle count divides it), so a mocap clip
## of several uneven strides plays all of them in turn, each foot down where the others' are.
const GAITS := [
	["Casual_Walk_inplace", 4.2, [0.079, 1.579, 2.929], 0.53],
	["run_fast_3_inplace", 0.767, [0.113], 0.515],
	["moves/sprint", 0.667, [0.042], 0.537],
]
## Spine bones that take the hips' turn back, and their shares.
const COUNTER := [["Spine02", 0.3], ["Spine01", 0.3], ["Spine", 0.25], ["neck", 0.15]]
## Spine bones the drive pitches, and their shares.
const DRIVE := [["Spine02", 0.4], ["Spine01", 0.35], ["Spine", 0.25]]

## 0..1: how much of the pose is the gait (0 the AnimationPlayer's clip alone).
var weight: float = 0.0
## Each gait clip's share (sums to 1 when any).
var gait_w: PackedFloat32Array = PackedFloat32Array([1.0, 0.0, 0.0])
var phase: float = 0.0
var hips_yaw: float = 0.0
## 0..1: how much of hips_yaw the spine takes back.
var counter: float = 1.0
var drive: float = 0.0

var _lengths: PackedFloat32Array = PackedFloat32Array()
var _cycles: PackedFloat32Array = PackedFloat32Array()
var _anims: Array[Animation] = []
## [bone, [rotation track per clip or -1], [position track per clip or -1]].
var _tracks: Array = []
var _ids := {}
var _ready_ok := false


## Caches the gait clips' tracks from `anim` for the bones of `sk`. False when a clip is missing.
func setup(anim: AnimationPlayer, sk: Skeleton3D) -> bool:
	_anims.clear()
	_lengths.clear()
	_cycles.clear()
	_tracks.clear()
	for g in GAITS:
		if not anim.has_animation(g[0]):
			_ready_ok = false
			return false
		var a := anim.get_animation(g[0])
		_anims.append(a)
		_lengths.append(a.length)
		_cycles.append(float((g[2] as Array).size()))
	var bones := {}
	for ci in _anims.size():
		var a := _anims[ci]
		for t in a.get_track_count():
			var tt := a.track_get_type(t)
			if tt != Animation.TYPE_ROTATION_3D and tt != Animation.TYPE_POSITION_3D:
				continue
			var bone_name := a.track_get_path(t).get_concatenated_subnames()
			if _is_finger(bone_name):
				continue
			var b := sk.find_bone(bone_name)
			if b < 0:
				continue
			if not bones.has(b):
				var none := []
				none.resize(_anims.size())
				none.fill(-1)
				bones[b] = [b, none.duplicate(), none.duplicate()]
			var entry: Array = bones[b]
			if tt == Animation.TYPE_ROTATION_3D:
				entry[1][ci] = t
			else:
				entry[2][ci] = t
	for b in bones:
		_tracks.append(bones[b])
	_ready_ok = true
	return true


static func _is_finger(n: String) -> bool:
	for f in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		if n.contains(f):
			return true
	return false


## Seconds into gait clip `i` for the current phase.
func clip_time(i: int) -> float:
	var len := _lengths[i]
	var downs: Array = GAITS[i][2]
	var n := downs.size()
	var c := fposmod(phase, float(n))
	var k := mini(int(c), n - 1)
	var t0: float = downs[k]
	var t1: float = downs[k + 1] if k + 1 < n else float(downs[0]) + len
	return fposmod(lerpf(t0, t1, c - k), len)


## The phase wraps at this many cycles.
static func period() -> float:
	var p := 1
	for g in GAITS:
		var n: int = (g[2] as Array).size()
		var a := p
		var b := n
		while b != 0:
			var r := a % b
			a = b
			b = r
		p = p * n / a
	return float(p)


## The length of one stride cycle of gait clip `i` (s).
static func cycle_seconds(i: int) -> float:
	return float(GAITS[i][1]) / float((GAITS[i][2] as Array).size())


## The phase of the next touchdown (either foot) at or after the current one, unwrapped
## (phase + the distance to it, going forward when `forward`).
func next_contact(forward: bool) -> float:
	var right := _right_share()
	var p := fposmod(phase, 1.0)
	var marks := [0.0, right, 1.0, 1.0 + right]
	if forward:
		for m: float in marks:
			if m >= p - 1e-4:
				return phase + (m - p)
	else:
		for k in range(marks.size() - 1, -1, -1):
			var m: float = marks[k] - 1.0
			if m <= p + 1e-4:
				return phase - (p - m)
	return phase


## Where the right toe comes down in the phase (the blended clips' share).
func _right_share() -> float:
	var s := 0.0
	var tot := 0.0
	for i in GAITS.size():
		s += gait_w[i] * float(GAITS[i][3])
		tot += gait_w[i]
	return s / tot if tot > 0.0 else 0.5


func _bone(n: String) -> int:
	if not _ids.has(n):
		var sk := get_skeleton()
		_ids[n] = sk.find_bone(n) if sk else -1
	return _ids[n]


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not _ready_ok:
		return
	if weight > 0.001:
		_blend(sk)
	if absf(hips_yaw) > 1e-4:
		_turn_up(sk, _bone("Hips"), hips_yaw)
		for pair in COUNTER:
			_turn_up(sk, _bone(pair[0]), -hips_yaw * counter * float(pair[1]))
	if absf(drive) > 1e-4:
		for pair in DRIVE:
			_turn(sk, _bone(pair[0]), Vector3.RIGHT, drive * float(pair[1]))


func _blend(sk: Skeleton3D) -> void:
	var times := PackedFloat32Array()
	for i in _anims.size():
		times.append(clip_time(i))
	for entry: Array in _tracks:
		var b: int = entry[0]
		var rot_tracks: Array = entry[1]
		var pos_tracks: Array = entry[2]
		var here_q := sk.get_bone_pose_rotation(b)
		var q := here_q
		var acc := 0.0
		var p := sk.get_bone_pose_position(b)
		var here_p := p
		var acc_p := 0.0
		for i in _anims.size():
			var w := gait_w[i]
			if w <= 0.0001:
				continue
			var tr: int = rot_tracks[i]
			var cq := _anims[i].rotation_track_interpolate(tr, times[i]) if tr >= 0 else here_q
			q = cq if acc == 0.0 else q.slerp(cq, w / (acc + w))
			acc += w
			var tp: int = pos_tracks[i]
			if tp >= 0:
				var cp := _anims[i].position_track_interpolate(tp, times[i])
				p = cp if acc_p == 0.0 else p.lerp(cp, w / (acc_p + w))
				acc_p += w
		if acc > 0.0:
			sk.set_bone_pose_rotation(b, here_q.slerp(q.normalized(), weight).normalized())
		if acc_p > 0.0:
			sk.set_bone_pose_position(b, here_p.lerp(p, weight * minf(acc_p / maxf(acc, 1e-4), 1.0)))


## Turns a bone about the skeleton's vertical by `angle`.
func _turn_up(sk: Skeleton3D, bone: int, angle: float) -> void:
	_turn(sk, bone, Vector3.UP, angle)


## Turns a bone about a skeleton-space axis, after what came before.
func _turn(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or absf(angle) < 1e-5:
		return
	var par := sk.get_bone_parent(bone)
	var pb := GripHands._chain(sk, par).basis.orthonormalized() if par >= 0 else Basis()
	var local_axis := (pb.inverse() * axis).normalized()
	sk.set_bone_pose_rotation(bone, (Quaternion(local_axis, angle) * sk.get_bone_pose_rotation(bone)).normalized())


## Seconds each toe comes down in `clip` (left, right): the frames its height falls to within
## 2.5 cm of its lowest after being above it. Leaves the player on the clip's first frame.
## tools/hero_locomotion/gait_probe.gd and the checks hold GAITS to it.
static func touchdowns(anim: AnimationPlayer, sk: Skeleton3D, clip: String, unit: float) -> Array:
	var a := anim.get_animation(clip)
	var step := 1.0 / 240.0
	var feet := [sk.find_bone("LeftToeBase"), sk.find_bone("RightToeBase")]
	var heights := [PackedFloat32Array(), PackedFloat32Array()]
	anim.play(clip, 0.0)
	anim.speed_scale = 1.0
	var n := int(a.length / step)
	for i in n:
		anim.seek(i * step, true)
		sk.force_update_all_bone_transforms()
		for f in 2:
			heights[f].append(sk.get_bone_global_pose(feet[f]).origin.y * unit)
	var out := [[], []]
	for f in 2:
		var h: PackedFloat32Array = heights[f]
		var low := INF
		for v in h:
			low = minf(low, v)
		for i in n:
			var prev := h[(i - 1 + n) % n]
			if h[i] < low + 0.025 and prev >= low + 0.025:
				out[f].append(snappedf(i * step, 0.001))
	anim.seek(0.0, true)
	return out
