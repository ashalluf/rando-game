class_name RideSolver
extends RefCounted
## Poses a rig astride a motorcycle (Motorcycle), worked out every frame rather than played: the
## hips on the seat, the chest leaned toward the bars as far as the bike asks (a supersport's
## tuck, a cruiser's lean back), each limb a two-bone solve in skeleton space - the hands on the
## grips, the feet on the pegs (or a boot down on the road when the bike stands, or both up on a
## scooter's floorboard) - knees and elbows bent in the plane a pole gives them, the head brought
## up to look down the road. BikeRider's method, made a class so the same solve poses a crowd rig
## (MotoRider) and the hero (HeroRide, a SkeletonModifier3D on his skeleton).
##
## The base it works from is a pose the caller hands over (the crowd rig's idle at a fixed moment,
## the hero's rest pose), so it fits any rig with the crowd's 24 bone names.

const BONES := ["Hips", "Spine02", "Spine01", "Spine", "neck", "Head", "headfront",
		"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
		"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]

var sk: Skeleton3D
var _order := PackedInt32Array()
var _parent_of := PackedInt32Array()
var _subtree: Array[PackedInt32Array] = []
var _base_rot: Array[Quaternion] = []
var _base_pos: Array[Vector3] = []
var _rot: Array[Quaternion] = []
var _glob: Array[Transform3D] = []
var _hips_pos := Vector3.ZERO
var _b := {}
var foot_len: float = 0.15
var leg_len: float = 0.9
## How far the wrists fell short of the grips in the last pose (m).
var reach_miss: float = 0.0
## Extra forward lean (radians) found so the hands reach the bars (fit()).
var lean_extra: float = 0.0


## Takes the rig: false when it lacks a bone the solve needs. `base_rot` / `base_pos` the pose to
## work from (empty: the skeleton's rest).
func setup(skel: Skeleton3D, base_rot: Array = [], base_pos: Array = []) -> bool:
	sk = skel
	if sk == null:
		return false
	var n := sk.get_bone_count()
	_base_rot.resize(n)
	_base_pos.resize(n)
	_glob.resize(n)
	_parent_of.resize(n)
	for b in n:
		_base_rot[b] = base_rot[b] if b < base_rot.size() else sk.get_bone_rest(b).basis.get_rotation_quaternion()
		_base_pos[b] = base_pos[b] if b < base_pos.size() else sk.get_bone_rest(b).origin
		_parent_of[b] = sk.get_bone_parent(b)
	_order = RoughSleeper._bone_order(sk)
	_subtree.resize(n)
	for b in n:
		var sub := PackedInt32Array()
		for o in _order:
			var x := o
			while x >= 0 and x != b:
				x = _parent_of[x]
			if x == b:
				sub.append(o)
		_subtree[b] = sub
	for bone: String in BONES:
		_b[bone] = sk.find_bone(bone)
		if int(_b[bone]) < 0 and bone != "headfront":
			sk = null
			return false
	_rot = _base_rot.duplicate()
	_hips_pos = _base_pos[_b.Hips]
	_fk()
	return true


## The leg's and foot's length in metres, given the scale of the bike frame in skeleton space.
func measure(unit: float) -> void:
	_rot = _base_rot.duplicate()
	_hips_pos = _base_pos[_b.Hips]
	_fk()
	leg_len = (_glob[_b.LeftUpLeg].origin.distance_to(_glob[_b.LeftLeg].origin) + _glob[_b.LeftLeg].origin.distance_to(_glob[_b.LeftFoot].origin)) / unit
	foot_len = _glob[_b.LeftFoot].origin.distance_to(_glob[_b.LeftToeBase].origin) / unit


## Leans this rider further over the bars until the hands reach them (a short-armed rider on a
## supersport folds lower), at most 0.45 rad more than the bike asks.
func fit(to_skel: Transform3D, g: Dictionary) -> void:
	lean_extra = 0.0
	for i in 5:
		solve(to_skel, g, {}, false)
		if reach_miss < 0.02 or lean_extra >= 0.45:
			break
		lean_extra = minf(lean_extra + clampf(reach_miss / 0.4, 0.04, 0.25), 0.45)


func _fk() -> void:
	for b in _order:
		var p := _parent_of[b]
		var local := Transform3D(Basis(_rot[b]), _hips_pos if b == _b.Hips else _base_pos[b])
		_glob[b] = _glob[p] * local if p >= 0 else local


func _set_glob_basis(b: int, basis: Basis) -> void:
	var p := _parent_of[b]
	var pb := _glob[p].basis if p >= 0 else Basis.IDENTITY
	_rot[b] = (pb.orthonormalized().inverse() * basis.orthonormalized()).get_rotation_quaternion()


func _turn(b: int, q: Quaternion) -> void:
	_set_glob_basis(b, Basis(q) * _glob[b].basis)
	for o in _subtree[b]:
		var p := _parent_of[o]
		var local := Transform3D(Basis(_rot[o]), _hips_pos if o == _b.Hips else _base_pos[o])
		_glob[o] = _glob[p] * local if p >= 0 else local


func _ik(a: int, b: int, c: int, target: Vector3, pole: Vector3) -> void:
	var pa := _glob[a].origin
	var pb := _glob[b].origin
	var pc := _glob[c].origin
	var l1 := pa.distance_to(pb)
	var l2 := pb.distance_to(pc)
	var to := target - pa
	var d := clampf(to.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var dir := to.normalized()
	var pl := pole - dir * dir.dot(pole)
	if pl.length_squared() < 1e-8:
		pl = Vector3.UP - dir * dir.dot(Vector3.UP)
	pl = pl.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var pb_new := pa + (dir * cos_a + pl * sqrt(1.0 - cos_a * cos_a)) * l1
	var end_new := pa + dir * d
	var d_old := (pb - pa).normalized()
	var d_new := (pb_new - pa).normalized()
	var n_new := d_new.cross((end_new - pb_new).normalized())
	if n_new.length_squared() < 1e-8:
		n_new = d_new.cross(pl)
	n_new = n_new.normalized()
	var n_old := d_old.cross((pc - pb).normalized())
	if n_old.length_squared() < 0.02 or n_old.dot(n_new) < 0.0:
		n_old = n_new - d_old * d_old.dot(n_new)
	n_old = n_old.normalized()
	var f_old := Basis(d_old, n_old, d_old.cross(n_old).normalized())
	var f_new := Basis(d_new, n_new, d_new.cross(n_new).normalized())
	_turn(a, (f_new * f_old.transposed()).get_rotation_quaternion())
	var cur := (_glob[c].origin - _glob[b].origin).normalized()
	var want := (end_new - _glob[b].origin).normalized()
	if cur.dot(want) < 0.99999:
		_turn(b, Quaternion(cur, want))


func _aim(b: int, child: int, want: Vector3, weight: float = 1.0) -> void:
	var cur := (_glob[child].origin - _glob[b].origin).normalized()
	var w := want.normalized()
	if cur.dot(w) > 0.99999:
		return
	_turn(b, Quaternion.IDENTITY.slerp(Quaternion(cur, w), weight))


## The pose for this frame. `to_skel` maps the bike's frame (metres, -Z forward, the ground at
## y 0) into skeleton space. `g` the bike's points: "seat" (where the hip joints' midpoint sits),
## "grip" (the right grip's centre), "peg" (the right foot's ball), "lean" (degrees the torso
## leans toward the bars; negative leans back), "floor" (true: the feet flat on a floorboard).
## `state`: "foot_down" 0..1 (the left boot goes down to the road as the bike stops), "hang"
## (metres the hips slide toward the inside of a turn, + to the right), "tuck" 0..1 (down behind
## the screen at speed), "wheelie" (radians the bike is pitched up: the rider leans forward into
## it). Writes the bones unless `write` is false.
func solve(to_skel: Transform3D, g: Dictionary, state: Dictionary = {}, write: bool = true) -> void:
	if sk == null:
		return
	var t := to_skel
	var unit := t.basis.get_scale().y
	var right := (t.basis * Vector3.RIGHT).normalized()
	var up := (t.basis * Vector3.UP).normalized()
	var fwd := (t.basis * Vector3.FORWARD).normalized()
	_rot = _base_rot.duplicate()
	_hips_pos = _base_pos[_b.Hips]
	_fk()
	var tuck := float(state.get("tuck", 0.0))
	var wheelie := float(state.get("wheelie", 0.0))
	var hang := float(state.get("hang", 0.0))
	var lean := deg_to_rad(float(g.get("lean", 20.0))) + lean_extra + tuck * 0.35 + wheelie * 0.6
	var axis := up.cross(fwd).normalized()
	_turn(_b.Hips, Quaternion(axis, lean * 0.42))
	for k in 3:
		var bone: int = [_b.Spine02, _b.Spine01, _b.Spine][k]
		_turn(bone, Quaternion(axis, lean * [0.2, 0.2, 0.18][k]))
	# Hanging off: the chest leans in with the hips.
	if absf(hang) > 0.001:
		_turn(_b.Spine01, Quaternion(fwd, -hang * 1.6))
	var mid := (_glob[_b.LeftUpLeg].origin + _glob[_b.RightUpLeg].origin) * 0.5
	var seat: Vector3 = g.get("seat", Vector3(0.0, 0.85, 0.2))
	var want := t * (seat + Vector3(hang, 0.085, -0.03))
	_hips_pos += (want - mid)
	_fk()
	var down := clampf(float(state.get("foot_down", 0.0)), 0.0, 1.0)
	var peg: Vector3 = g.get("peg", Vector3(0.17, 0.37, 0.3))
	var floor_board := bool(g.get("floor", false))
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var ball := Vector3(peg.x * sx, peg.y, peg.z)
		var toe := Vector3(0.12 * sx, -0.12, -1.0).normalized()
		if floor_board:
			toe = Vector3(0.18 * sx, -0.05, -1.0).normalized()
			ball.z -= 0.06
		if side == 0 and down > 0.0:
			# The left boot down on the road beside the bike, a little ahead of the hips.
			var foot := Vector3(-maxf(peg.x, 0.16) - 0.16, 0.02, seat.z - 0.18)
			ball = ball.lerp(foot, down)
			toe = toe.slerp(Vector3(-0.15, -0.05, -1.0).normalized(), down)
		var ankle := ball + Vector3(0.0, 0.075, 0.0) - toe * (foot_len * 0.82)
		var up_b: int = _b.LeftUpLeg if side == 0 else _b.RightUpLeg
		var leg_b: int = _b.LeftLeg if side == 0 else _b.RightLeg
		var foot_b: int = _b.LeftFoot if side == 0 else _b.RightFoot
		var toe_b: int = _b.LeftToeBase if side == 0 else _b.RightToeBase
		var knee_pole := fwd + up * 0.3 + right * (sx * 0.35)
		_ik(up_b, leg_b, foot_b, t * ankle, knee_pole)
		_aim(foot_b, toe_b, t.basis * toe)
	var grip: Vector3 = g.get("grip", Vector3(0.3, 0.85, -0.3))
	reach_miss = 0.0
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var gp := t * Vector3(grip.x * sx, grip.y, grip.z)
		var sh_b: int = _b.LeftShoulder if side == 0 else _b.RightShoulder
		var arm_b: int = _b.LeftArm if side == 0 else _b.RightArm
		var fore_b: int = _b.LeftForeArm if side == 0 else _b.RightForeArm
		var hand_b: int = _b.LeftHand if side == 0 else _b.RightHand
		var reach := (gp - _glob[arm_b].origin).normalized()
		_aim(sh_b, arm_b, (_glob[arm_b].origin - _glob[sh_b].origin).normalized().slerp(reach, 0.25), 1.0)
		# The wrist a palm short of the grip, the hand wrapped over it: the fingers along the bike,
		# turned out with the bar's sweep.
		var hand_dir := (fwd * 0.55 - up * 0.35 + right * (sx * 0.5)).normalized()
		var wrist := gp - hand_dir * (0.07 * unit) + up * (0.025 * unit)
		var elbow_pole := -up * 0.6 + right * (sx * 0.75) - fwd * 0.2
		_ik(arm_b, fore_b, hand_b, wrist, elbow_pole)
		reach_miss = maxf(reach_miss, _glob[hand_b].origin.distance_to(wrist) / unit)
		var fingers := _glob[hand_b].origin + _glob[hand_b].basis.y.normalized() * 10.0
		var cur := (fingers - _glob[hand_b].origin).normalized()
		if cur.dot(hand_dir) < 0.99999:
			_turn(hand_b, Quaternion(cur, hand_dir))
	if int(_b.headfront) >= 0:
		var look := (fwd * cos(0.12) - up * sin(0.12)).normalized()
		_aim(_b.neck, _b.headfront, look, 0.5)
		_aim(_b.Head, _b.headfront, look, 1.0)
	if write:
		write_last()


## Writes the last solved pose again (a modifier must write every frame, the clip having run).
func write_last() -> void:
	if sk == null:
		return
	# Only the bones the solve owns: the fingers keep what the clip (or the hero's grip) gave them.
	for bone: String in BONES:
		var b := int(_b[bone])
		if b >= 0:
			sk.set_bone_pose_rotation(b, _rot[b])
	sk.set_bone_pose_position(_b.Hips, _hips_pos)
