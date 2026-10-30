class_name CrowdFeet
extends RefCounted
## Foot placement for the crowd (G5): people standing or walking near the camera plant their feet
## on what is really under them - a kerb, a stair, a slope, a bench step - instead of on the flat
## plane the clips were authored on, where a foot over a kerb edge floated and a foot on rising
## ground sank into it.
##
## Run by Pedestrian._physics_process() last, after the clip (advanced by hand), the arm swing, the
## head, the life layer and the errands have posed the rig, so it works on the finished pose:
##  1. two rays per foot (heel and ball, `world` layer only) every `RAY_EVERY` ticks, staggered
##     per person; a foot rests on the HIGHER of its two hits (a heel over a stair nosing stands on
##     the ball), and the hits' normals give its tilt;
##  2. each foot's rise over the soles' plane (`_visual`'s origin: where the body thinks the ground
##     is) smoothed, clamped to `REACH`;
##  3. the hips moved by the LOWER foot's rise (down a kerb, onto the lower stair) - never more
##     than `HIPS_UP` up - and each leg re-solved in the plane the clip bent its knee in, so the
##     ankle lands its own rise above where the clip had it (the swing foot keeps its swing);
##  4. each foot keeps the clip's rotation, tilted toward the ground's normal while it is down.
## Faded in by distance from the camera (`near_range` .. `far_range`), off past it: two rays a
## foot every third tick is cheap near the camera and pointless past a few pixels. A bone the
## clips do not key would accumulate the offset tick after tick, so what was written is undone
## first when nothing has rewritten it since (`_restore()`).
## Off while seated (the sit pose solves its own legs), ragdolled, hidden (errands), or when the
## visual is offset from its body (a vendor ducking in a truck, a swimmer sunk to the chest).
## The hero's planted-foot IK is his own (HeroMotion); this is the crowd's. FOOT_IK=0 turns it off.

static var enabled: bool = OS.get_environment("FOOT_IK") != "0"
## Full weight inside this distance from the camera (m).
static var near_range: float = 20.0
## None past this one.
static var far_range: float = 30.0

## The most a foot is lifted or lowered (m).
const REACH := 0.34
## The most the hips come UP (a body sunk below both feet's ground).
const HIPS_UP := 0.12
## Rays start this far over the soles' plane (the highest step a foot can find: anything taller,
## a bench seat, a planter, is an obstacle, not ground) and end REACH (plus a margin) under it.
const RAY_UP := 0.4
## Physics ticks between ray samples (staggered by the person's id).
const RAY_EVERY := 2
## Past `RAY_NEAR` m from the camera, every this many.
const RAY_EVERY_FAR := 4
const RAY_NEAR := 10.0
## How straight a leg may be pulled (share of its full length) before the hips come down.
const REACH_SHARE := 0.985
## How fast the lift follows a new sample (1/s).
const FOLLOW := 24.0
## The most a foot tilts to the ground (rad).
const TILT_MAX := 0.42
## World layer.
const MASK := 1
## Layer 6, "foot ground": true treads where the world layer carries a walkable ramp over a flight
## of steps (the player's body cannot climb 17 cm risers). Static, mask 0, and in no moving
## body's mask, so it pairs with nothing: only these rays read it.
const FEET_LAYER := 1 << 5

var _sk: Skeleton3D
var _hips: int = -1
## Per side: up leg, leg, foot, toe.
var _legs := PackedInt32Array()
## The ankle's height over the soles at rest (m, per side): how high a planted ankle stands.
var _ankle_rest := Vector2(0.08, 0.08)
var _ok: bool = false
var _phase: int = 0
var _has_truck: bool = false
var _cam_d: float = 0.0
static var _query: PhysicsRayQueryParameters3D
var _tick: int = 0
var _want := Vector2.ZERO
var _lift := Vector2.ZERO
var _nrm_want: Array = [Vector3.UP, Vector3.UP]
var _nrm: Array = [Vector3.UP, Vector3.UP]
var _weight: float = 0.0
## What was written last tick, to undo it if the clip does not rewrite the bone.
var _written := {}
## Lifts and hips offset applied last tick (m), for tests and probes.
var applied_lift := Vector2.ZERO
var applied_hips: float = 0.0
var debug: bool = false
var debug_lines: PackedStringArray = []

## Time spent (us) and calls, for benches and probes.
static var cost_usec: int = 0
static var cost_sample_usec: int = 0
static var cost_apply_usec: int = 0
static var calls: int = 0
static var _cam_frame: int = -1
static var _cam_pos := Vector3.INF


static func tick(ped: Pedestrian, delta: float) -> void:
	if not enabled:
		return
	var f: CrowdFeet = ped.foot_ik
	if f == null:
		var sk: Skeleton3D = ped._head_skel
		if sk == null:
			return
		f = CrowdFeet.new()
		f._setup(sk, ped)
		ped.foot_ik = f
	var t0 := Time.get_ticks_usec()
	f._run(ped, delta)
	cost_usec += Time.get_ticks_usec() - t0
	calls += 1


func _setup(sk: Skeleton3D, ped: Pedestrian) -> void:
	_sk = sk
	_phase = absi(ped.get_instance_id()) % RAY_EVERY_FAR
	_has_truck = "in_truck" in ped
	_hips = sk.find_bone("Hips")
	for b in ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]:
		_legs.append(sk.find_bone(b))
	_ok = _hips >= 0 and not (-1 in _legs)
	if not _ok:
		return
	# The ankle's rest height over the lowest point of the foot (the toe's head stands for the
	# sole's front), in metres through the skeleton's world scale.
	var s := sk.global_basis.get_scale().y
	for side in 2:
		var a := sk.get_bone_global_rest(_legs[side * 4 + 2]).origin
		var t := sk.get_bone_global_rest(_legs[side * 4 + 3]).origin
		var h := absf(a.y - minf(t.y, a.y)) * s
		_ankle_rest[side] = clampf(h + 0.02, 0.04, 0.16)


static func _camera_pos(ped: Pedestrian) -> Vector3:
	var frame := Engine.get_physics_frames()
	if frame != _cam_frame:
		_cam_frame = frame
		var vp := ped.get_viewport()
		var cam := vp.get_camera_3d() if vp else null
		_cam_pos = cam.global_position if cam else Vector3.INF
	return _cam_pos


## Whether this person's feet should be planted now.
func _active(ped: Pedestrian) -> bool:
	if ped._down:
		return false
	var vis: Node3D = ped._visual
	if vis == null or not vis.is_visible_in_tree() or absf(vis.position.y) > 0.03:
		return false
	if ped._act == CrowdLife.Act.SIT:
		return false
	if _has_truck and ped.get("in_truck") == true:
		return false
	return true


func _run(ped: Pedestrian, delta: float) -> void:
	if not _ok or not is_instance_valid(_sk):
		return
	_tick += 1
	var vis: Node3D = ped._visual
	var cam := _camera_pos(ped)
	var want_w := 0.0
	if cam != Vector3.INF and _active(ped):
		var d := cam.distance_to(vis.global_position)
		_cam_d = d
		want_w = 1.0 - smoothstep(near_range, far_range, d)
	_weight = move_toward(_weight, want_w, delta * 3.0)
	if _weight <= 0.001:
		_written.clear()
		_lift = Vector2.ZERO
		applied_lift = Vector2.ZERO
		applied_hips = 0.0
		return
	_restore()
	var xf := _sk.global_transform
	var base := vis.global_position.y
	var every := RAY_EVERY if _cam_d < RAY_NEAR else RAY_EVERY_FAR
	if _tick % every == _phase % every or _want == Vector2.ZERO and _lift == Vector2.ZERO:
		var t1 := Time.get_ticks_usec()
		_sample(ped, xf, base)
		cost_sample_usec += Time.get_ticks_usec() - t1
	var k := 1.0 - exp(-FOLLOW * delta)
	_lift = _lift.lerp(_want, k)
	for side in 2:
		_nrm[side] = (_nrm[side] as Vector3).lerp(_nrm_want[side], k).normalized()
	var t2 := Time.get_ticks_usec()
	_apply(xf, base)
	cost_apply_usec += Time.get_ticks_usec() - t2


## Two rays a foot (ankle and ball); the foot's ground is the higher hit.
func _sample(ped: Pedestrian, xf: Transform3D, base: float) -> void:
	var space := (ped as Node3D).get_world_3d().direct_space_state
	if space == null:
		return
	for side in 2:
		var ys := [-INF, -INF]
		var ns := [Vector3.UP, Vector3.UP]
		var hits := 0
		for j in 2:
			var b := _legs[side * 4 + 2 + j]
			var at := xf * _sk.get_bone_global_pose(b).origin
			var from := Vector3(at.x, base + RAY_UP, at.z)
			if _query == null:
				_query = PhysicsRayQueryParameters3D.new()
				_query.collision_mask = MASK | FEET_LAYER
			var q := _query
			q.from = from
			q.to = Vector3(at.x, base - REACH - 0.06, at.z)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and _passes(hit):
				# A ramp standing in for steps: on through it to the treads under it.
				q.from = hit.position - Vector3(0.0, 0.002, 0.0)
				hit = space.intersect_ray(q)
			if hit.is_empty():
				continue
			hits += 1
			ys[j] = hit.position.y
			ns[j] = hit.normal
		var best: float = maxf(ys[0], ys[1])
		var nrm: Vector3 = ns[0] if ys[0] >= ys[1] else ns[1]
		if ys[0] > -INF and ys[1] > -INF:
			var n0: Vector3 = ns[0]
			var n1: Vector3 = ns[1]
			if n0.dot(n1) > 0.995 and n0.y < 0.995:
				# One sloping surface under both: the ankle stands over the heel's ground and the
				# tilt brings the ball down onto it.
				best = ys[0]
				nrm = n0
			elif absf(ys[0] - ys[1]) < 0.03:
				nrm = (n0 + n1).normalized()
		if hits == 0:
			_want[side] = 0.0
			_nrm_want[side] = Vector3.UP
			continue
		if best - base > REACH:
			# Something knee-high beside the foot (a bench, a step too tall to stand on): not ground.
			_want[side] = 0.0
			_nrm_want[side] = Vector3.UP
			continue
		_want[side] = clampf(best - base, -REACH, REACH)
		# A steep hit (a riser, a wall) says nothing about how the sole lies.
		_nrm_want[side] = nrm if nrm.y > 0.8 else Vector3.UP


## Undoes last tick's write on any bone nothing has rewritten since.
func _restore() -> void:
	for b: int in _written:
		var rec: Array = _written[b]
		if rec[0] is Vector3:
			if _sk.get_bone_pose_position(b).is_equal_approx(rec[1]):
				_sk.set_bone_pose_position(b, rec[0])
		elif _sk.get_bone_pose_rotation(b).is_equal_approx(rec[1]):
			_sk.set_bone_pose_rotation(b, rec[0])
	_written.clear()


func _set_rot(b: int, q: Quaternion) -> void:
	var before := _sk.get_bone_pose_rotation(b)
	_sk.set_bone_pose_rotation(b, q)
	if not _written.has(b):
		_written[b] = [before, q]
	else:
		_written[b][1] = q


func _set_global_rot(b: int, g: Basis) -> void:
	var p := _sk.get_bone_parent(b)
	var pb := _sk.get_bone_global_pose(p).basis if p >= 0 else Basis.IDENTITY
	_set_rot(b, (pb.orthonormalized().inverse() * g.orthonormalized()).get_rotation_quaternion())


func _apply(xf: Transform3D, base: float) -> void:
	var lift := _lift * _weight
	if absf(lift.x) < 0.002 and absf(lift.y) < 0.002 and (_nrm[0] as Vector3).y > 0.9995 and (_nrm[1] as Vector3).y > 0.9995:
		applied_lift = Vector2.ZERO
		applied_hips = 0.0
		return
	debug_lines.clear()
	var inv := xf.affine_inverse()
	var low := 0 if lift.x <= lift.y else 1
	var hips_off := minf(lift[low], HIPS_UP * _weight)
	if hips_off < 0.0:
		# The lower leg reaches down by what it has left before it is straight, and the hips come
		# down only by the rest: dropped by the whole step, the leg on the higher ground folds
		# into a squat (someone with a foot down off a kerb stands tall on the other).
		var a := xf * _sk.get_bone_global_pose(_legs[low * 4]).origin
		var k := xf * _sk.get_bone_global_pose(_legs[low * 4 + 1]).origin
		var f := xf * _sk.get_bone_global_pose(_legs[low * 4 + 2]).origin
		var slack := maxf((a.distance_to(k) + k.distance_to(f)) * REACH_SHARE - a.distance_to(f), 0.0)
		hips_off = minf(hips_off + slack, 0.0)
	# The clip's feet, before anything moves (skeleton space).
	var feet: Array = [_sk.get_bone_global_pose(_legs[2]), _sk.get_bone_global_pose(_legs[6])]
	if absf(hips_off) > 0.0005:
		var d_s := inv.basis * (Vector3.UP * hips_off)
		var p := _sk.get_bone_parent(_hips)
		if p >= 0:
			d_s = _sk.get_bone_global_pose(p).basis.inverse() * d_s
		var before := _sk.get_bone_pose_position(_hips)
		var after := before + d_s
		_sk.set_bone_pose_position(_hips, after)
		_written[_hips] = [before, after]
	var up_s := (inv.basis * Vector3.UP).normalized()
	for side in 2:
		var up := _legs[side * 4]
		var knee := _legs[side * 4 + 1]
		var foot := _legs[side * 4 + 2]
		var f0: Transform3D = feet[side]
		var target := inv * (xf * f0.origin + Vector3.UP * lift[side])
		var a := _sk.get_bone_global_pose(up)
		var k := _sk.get_bone_global_pose(knee)
		var f := _sk.get_bone_global_pose(foot)
		var l1 := a.origin.distance_to(k.origin)
		var l2 := k.origin.distance_to(f.origin)
		var to := target - a.origin
		if to.length_squared() < 1e-8 or l1 < 1e-5 or l2 < 1e-5:
			continue
		var dd := clampf(to.length(), absf(l1 - l2) + 0.01 * l1, (l1 + l2) * 0.999)
		var dir := to.normalized()
		# The knee stays in the plane the clip bent it in.
		var pole := (k.origin - a.origin) - dir * (k.origin - a.origin).dot(dir)
		if pole.length_squared() < 1e-8:
			pole = (f.origin - k.origin).cross(a.basis.x)
			if pole.length_squared() < 1e-8:
				continue
		pole = pole.normalized()
		var cos_a := clampf((l1 * l1 + dd * dd - l2 * l2) / (2.0 * l1 * dd), -1.0, 1.0)
		var k_new := a.origin + (dir * cos_a + pole * sqrt(1.0 - cos_a * cos_a)) * l1
		var r1 := Quaternion((k.origin - a.origin).normalized(), (k_new - a.origin).normalized())
		_set_global_rot(up, Basis(r1) * a.basis)
		var k2 := _sk.get_bone_global_pose(knee)
		var f2 := _sk.get_bone_global_pose(foot)
		var r2 := Quaternion((f2.origin - k2.origin).normalized(), (a.origin + dir * dd - k2.origin).normalized())
		_set_global_rot(knee, Basis(r2) * k2.basis)
		# The foot: the clip's own rotation, tilted to the ground while it is down on it.
		var g := f0.basis
		var n_w: Vector3 = _nrm[side]
		if n_w.y < 0.9995:
			var ank := (xf * f0.origin).y - base # metres over the soles' plane
			var down := 1.0 - smoothstep(_ankle_rest[side], _ankle_rest[side] + 0.1, ank)
			var n_s := (inv.basis * n_w).normalized()
			var ang := minf(up_s.angle_to(n_s), TILT_MAX) * down * _weight
			var axis := up_s.cross(n_s)
			if ang > 1e-4 and axis.length_squared() > 1e-10:
				g = Basis(Quaternion(axis.normalized(), ang)) * g
		_set_global_rot(foot, g)
		if debug:
			var got := xf * _sk.get_bone_global_pose(foot).origin
			var hp := xf * _sk.get_bone_global_pose(_hips).origin
			debug_lines.append("side %d want %s got %s (clip %s) hips %s" % [side, xf * target, got, xf * f0.origin, hp])
	applied_lift = lift
	applied_hips = hips_off


## Whether a ray hit landed on a shape marked to be seen through by feet (a ramp over steps).
static func _passes(hit: Dictionary) -> bool:
	var col := hit.collider as CollisionObject3D
	if col == null:
		return false
	var owner_id := col.shape_find_owner(int(hit.shape))
	var node := col.shape_owner_get_owner(owner_id) as Node
	return node != null and node.has_meta("feet_pass")


## A flight of steps for feet (FEET_LAYER) under a ramp that stands in for it on the world layer:
## one box per tread, from `edge` (top, at `top_y`) to `toe` (bottom, `bottom_y`) along the left
## of `d` at `p`, `half` wide either side of the centre line. `ramp` is marked to be seen through.
static func add_steps(parent: Node3D, ramp: Node, p: Vector2, d: Vector2, l: Vector2, edge: float, toe: float,
		top_y: float, bottom_y: float, steps: int, half: float) -> void:
	if not enabled or parent == null or steps <= 0:
		return
	ramp.set_meta("feet_pass", true)
	var body := StaticBody3D.new()
	body.name = "FeetSteps"
	body.collision_layer = FEET_LAYER
	body.collision_mask = 0
	var run := (edge - toe) / float(steps)
	var rise := (top_y - bottom_y) / float(steps)
	for k in steps:
		var y_top := top_y - rise * float(k + 1)
		var o := edge - run * (float(k) + 0.5)
		var c := p + l * o
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(half * 2.0, 0.2, absf(run))
		cs.shape = bx
		# Box x along d (across the flight), z along l (down it).
		var dx := Vector3(d.x, 0.0, d.y).normalized()
		cs.transform = Transform3D(Basis(dx, Vector3.UP, dx.cross(Vector3.UP)), Vector3(c.x, y_top - 0.1, c.y))
		body.add_child(cs)
	parent.add_child(body)
