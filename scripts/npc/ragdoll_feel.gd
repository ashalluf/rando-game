class_name RagdollFeel
extends RefCounted
## How a jointed doll moves (2026-10-31, "ragdolls that read right"), on top of RagdollJoints:
##
## - SHOT: a person hit by a round does not fly off as a plank. For a beat (`stagger_time`) the
##   doll keeps its muscles: every part is driven toward the standing pose it was made in, leaned
##   along the round (the hips a little, the chest more, a head shot snaps the head), the shoulders
##   turned by which side the round went in, the whole held up against gravity. Then the muscles
##   let go - the knees buckle first - and it falls along the round. The direction comes from the
##   round itself, so a shot from behind pitches the person forward, one from the side spins them.
## - FLY: every jointed doll has joint damping (the relative spin of each part to its parent eased
##   out, momentum kept) and air drag that is far stronger on the limbs than on the trunk, so a
##   flung body flies trunk first with its arms and legs trailing, not as a spinning star.
## - CAR: a car's bumper (Vehicle._on_bumper_hit) says it was a car; the legs then take the car's
##   speed and the trunk much less, with a backward pitch, so the car runs under the body: it
##   folds over the bonnet onto the windscreen and slides off as the car goes on or brakes.
## - SLOPE: a doll lying on a slope or a flight of steps is not "still" while it still rolls down
##   (the settle test of RagdollJoints asks it), and gets a little downhill nudge while it tips, so
##   it rolls down the stairs rather than freezing on the third step.
##
## The cap, the range and the freeze are RagdollJoints' and unchanged. RAGDOLL_FEEL=0 in the
## environment is the A/B (the joints' own fling and nothing per step).

## Off with RAGDOLL_FEEL=0.
static var enabled: bool = OS.get_environment("RAGDOLL_FEEL") != "0"

## A round stagger: a knock this fast or slower (m/s, the rifle's 14.9) staggers; faster (a
## shotgun's full blast, an explosion) throws as before.
static var stagger_max_speed: float = 24.0
## How long the muscles hold before the person goes down (seconds, picked per doll by a hash).
static var stagger_time := Vector2(0.42, 0.68)
## The share of the round's speed the doll starts its stagger with (the rest is spent falling).
static var stagger_kick: float = 0.16
## The push along the round as the muscles let go (m/s).
static var fall_push: float = 2.6
## Lean along the round at the end of the stagger (degrees): hips, chest, head; the head snaps
## further when the round hit it.
const LEAN_DEG := Vector3(9.0, 24.0, 20.0)
## The first jolt over the held lean (a share of it).
const JOLT := 0.7
const HEAD_SNAP_DEG := 38.0
## The shoulders turned by a round that went in off the middle (degrees at 0.2 m off it).
const TWIST_DEG := 32.0
## Knees bent as the muscles let go (degrees).
const BUCKLE_DEG := 55.0
## Muscle gain (1/s) and the most a muscle turns a part (rad/s).
const MUSCLE_GAIN := 14.0
const MUSCLE_MAX := 9.0

## Relative spin between joined parts eased out at this rate (1/s): limbs, the spine and neck.
static var joint_damp: float = 5.0
static var spine_damp: float = 8.0
## Air drag (1/m): the trunk and the limbs (v -= v |v| k dt). Limbs trail because theirs is bigger.
const DRAG_CORE := 0.004
const DRAG_LIMB := 0.022
## A flung doll's limbs start at this share of the trunk's speed (momentum kept), and flail less.
const LIMB_LAG := 0.82
const FLAIL_SHARE := 0.35

## Car hits: the share of the car's speed the legs, the hips and the trunk start with, the lift
## (m/s) and the backward pitch (rad/s per m/s of car).
const CAR_LEGS := 1.02
const CAR_HIPS := 0.85
const CAR_TRUNK := 0.45
const CAR_LIFT := 1.6
const CAR_PITCH := 0.32
## Past this car speed (m/s) the hit is the old over-the-top throw (the trunk lifted too).
const CAR_THROW_SPEED := 26.0

## Slopes: a doll counts as rolling while its pelvis sits on ground steeper than this (degrees)
## and moves at least `roll_speed`, for at most `roll_max` seconds; the nudge (m/s^2).
static var roll_slope_deg: float = 12.0
static var roll_speed: float = 0.12
static var roll_max: float = 6.0
const ROLL_NUDGE := 2.4
## Friction of every part while it rolls down (a body tumbling down steps does not stick to the
## first nosing it touches); the old material comes back once it stops or freezes.
const ROLL_FRICTION := 0.4
## The trunk's tumble while it rolls: the spin of something of this radius (m) rolling at its speed,
## eased toward at ROLL_SPIN_RATE (1/s), at most ROLL_SPIN_MAX (rad/s).
const ROLL_RADIUS := 0.3
const ROLL_SPIN_RATE := 4.0
const ROLL_SPIN_MAX := 5.0
static var _roll_mat: PhysicsMaterial

## What hit the person, said just before Pedestrian.knock() makes the doll (taken by fling()).
static var _hint: Dictionary = {}
static var _hint_frame: int = -1
## Counters the checks read.
static var staggered: int = 0
static var car_wraps: int = 0

var joints: RagdollJoints
var kind: String = "fly"
## The standing basis of every part when the doll was made (world), by part name.
var rest: Dictionary = {}
var age: float = 0.0
var stagger_for: float = 0.0
var lean_axis := Vector3.ZERO
var lean_dir := Vector3.ZERO
var twist: float = 0.0
var head_hit: bool = false
var _pushed: bool = false
var rolling: float = 0.0
var _slope_dir := Vector3.ZERO
## The parts' own materials while the rolling one is on (part -> material).
var _mats: Dictionary = {}


## A round is about to knock a person down (Pedestrian.shot): where it went in and which way.
static func note_shot(at: Vector3, dir: Vector3, impulse: Vector3) -> void:
	_hint = {"kind": "shot", "at": at, "dir": dir, "impulse": impulse}
	_hint_frame = Engine.get_physics_frames()


## A car's bumper is about to knock a person down: the car and its velocity (world).
static func note_car(car: Node3D, velocity: Vector3) -> void:
	_hint = {"kind": "car", "car": car, "velocity": velocity}
	_hint_frame = Engine.get_physics_frames()


static func clear() -> void:
	_hint = {}


## The hint said this physics frame, once.
static func take() -> Dictionary:
	var h := _hint
	_hint = {}
	if h.is_empty() or _hint_frame != Engine.get_physics_frames():
		return {}
	return h


## Flings a freshly jointed doll by what hit it. Returns the feel that runs it each step (null when
## off: the joints' own fling has been used).
static func start(j: RagdollJoints, impulse: Vector3) -> RagdollFeel:
	var hint := take()
	if not enabled or j == null:
		j.fling(impulse)
		return null
	var f := RagdollFeel.new()
	f.joints = j
	for name: String in j.parts:
		var rb := j.parts[name] as RigidBody3D
		f.rest[name] = rb.global_basis.orthonormalized()
	var k: String = hint.get("kind", "")
	if k == "shot" and impulse.length() <= stagger_max_speed and impulse.length() > 0.01:
		f._start_stagger(impulse, hint)
	elif k == "car":
		f._start_car(impulse, hint)
	else:
		f._start_fly(impulse)
	return f


func _com() -> Vector3:
	var c := Vector3.ZERO
	var m := 0.0
	for rb in joints.bodies():
		c += rb.global_position * rb.mass
		m += rb.mass
	return c / maxf(m, 0.001)


func _h01(salt: String) -> float:
	return float(hash([joints.doll.get_instance_id() % 997, salt]) % 10007) / 10006.0


## A knock or a blast: the joints' speed on the trunk, the limbs lagging behind it (the same
## momentum), the tumble as before and a smaller flail of their own.
func _start_fly(impulse: Vector3) -> void:
	kind = "fly"
	var list := joints.bodies()
	var com := _com()
	var w := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * RagdollJoints.tumble_spin
	var m_core := 0.0
	var m_limb := 0.0
	for i in list.size():
		if i < 3:
			m_core += list[i].mass
		else:
			m_limb += list[i].mass
	# Momentum kept: the trunk a little faster for what the limbs give up.
	var core_gain := 1.0 + (1.0 - LIMB_LAG) * m_limb / maxf(m_core, 0.001)
	for i in list.size():
		var rb := list[i]
		var v := impulse * (core_gain if i < 3 else LIMB_LAG)
		rb.linear_velocity += v + w.cross(rb.global_position - com)
		rb.angular_velocity = w
		if i >= 3:
			rb.angular_velocity += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * RagdollJoints.limb_flail * FLAIL_SHARE


## A round: a small kick along it, then the muscles hold for stagger_for seconds (step()).
func _start_stagger(impulse: Vector3, hint: Dictionary) -> void:
	kind = "shot"
	staggered += 1
	var dir: Vector3 = hint.get("dir", impulse)
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.05:
		flat = Vector3(impulse.x, 0.0, impulse.z)
	if flat.length() < 0.05:
		flat = -(rest["pelvis"] as Basis).z
	lean_dir = flat.normalized()
	lean_axis = Vector3.UP.cross(lean_dir).normalized()
	stagger_for = lerpf(stagger_time.x, stagger_time.y, _h01("stagger"))
	var at: Vector3 = hint.get("at", (joints.parts["chest"] as Node3D).global_position)
	var head := joints.parts.get("head") as Node3D
	head_hit = head != null and at.distance_to(head.global_position) < 0.2
	# Which side of the body the round went in: a round right of the middle turns the shoulders.
	var pelvis := joints.parts["pelvis"] as Node3D
	var side := lean_dir.cross(Vector3.UP).normalized()
	var off := (at - pelvis.global_position).dot(side)
	twist = clampf(off / 0.2, -1.0, 1.0) * deg_to_rad(TWIST_DEG)
	var kick := Vector3(impulse.x, 0.0, impulse.z) * stagger_kick
	for name: String in joints.parts:
		var rb := joints.parts[name] as RigidBody3D
		var share := 1.0 if name in ["chest", "head", "upper_arm_l", "upper_arm_r", "forearm_l", "forearm_r"] else 0.5
		rb.linear_velocity += kick * share
	# The part the round went into jerks.
	var hit := joints.nearest(at)
	if hit:
		hit.linear_velocity += lean_dir * 1.4


## A car: the legs swept at the car's speed, the trunk left behind and pitched back over them.
func _start_car(impulse: Vector3, hint: Dictionary) -> void:
	kind = "car"
	car_wraps += 1
	var cv: Vector3 = hint.get("velocity", impulse)
	var speed := cv.length()
	if speed < 0.5:
		_start_fly(impulse)
		return
	var along := Vector3(cv.x, 0.0, cv.z).normalized()
	var pitch_axis := Vector3.UP.cross(along).normalized()
	var throw := clampf((speed - CAR_THROW_SPEED) / 10.0, 0.0, 1.0)
	var com := _com()
	# Legs forward, head back: a turn about pitch_axis by a negative rate puts the feet along the
	# car's way and the head back toward it.
	var w := -pitch_axis * speed * CAR_PITCH
	for name: String in joints.parts:
		var rb := joints.parts[name] as RigidBody3D
		var share := CAR_TRUNK
		if name.begins_with("shin") or name.begins_with("thigh"):
			share = CAR_LEGS
		elif name == "pelvis":
			share = CAR_HIPS
		share = lerpf(share, 1.0, throw)
		var lift := CAR_LIFT + throw * maxf(impulse.y, 0.0)
		rb.linear_velocity = along * speed * share + Vector3.UP * lift
		rb.linear_velocity += w.cross(rb.global_position - com) * 0.35
		rb.angular_velocity = w * 0.5 + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.6


## Every physics step while the doll is jointed (Ragdoll._physics_process, after clamp_spin).
func step(dt: float) -> void:
	age += dt
	if kind == "shot" and age < stagger_for + 0.1:
		_muscles(dt)
	_joint_damping(dt)
	_air_drag(dt)


## The stagger: every part driven toward its standing basis, leaned along the round as it goes on,
## the knees giving way at the end; held up against gravity while the muscles hold.
func _muscles(dt: float) -> void:
	var t := clampf(age / stagger_for, 0.0, 1.0)
	# Full strength for the first half, then letting go.
	var s := 1.0 - smoothstep(0.45, 1.0, t)
	# The lean: a jolt along the round in the first tenth of a second, then held a little less.
	var lean := smoothstep(0.0, 0.18, t) * (1.0 + JOLT * (1.0 - smoothstep(0.18, 0.55, t)))
	var buckle := smoothstep(0.35, 1.0, t)
	if age >= stagger_for:
		s = 0.0
		if not _pushed:
			_pushed = true
			for rb in joints.bodies():
				rb.linear_velocity += lean_dir * fall_push * (1.2 if rb == joints.parts.get("chest") or rb == joints.parts.get("head") else 0.6)
		return
	var support := s * 0.96
	var blend := 1.0 - exp(-22.0 * s * dt)
	# The knees bend toward the person's front, whichever way the round came.
	var knee_axis := Vector3.DOWN.cross(joints.fwd).normalized()
	for name: String in joints.parts:
		var rb := joints.parts[name] as RigidBody3D
		if not rest.has(name) or not is_instance_valid(rb):
			continue
		var target: Basis = rest[name]
		var a := 0.0
		var tw := twist * lean
		match name:
			"pelvis":
				a = deg_to_rad(LEAN_DEG.x) * lean
				tw *= 0.3
			"chest":
				a = deg_to_rad(LEAN_DEG.y) * lean
			"head":
				a = deg_to_rad(HEAD_SNAP_DEG if head_hit else LEAN_DEG.z) * (smoothstep(0.0, 0.25, t) if head_hit else lean)
			"thigh_l", "thigh_r":
				# The hips fold forward against the lean as the knees go.
				a = deg_to_rad(LEAN_DEG.x) * lean
				tw = 0.0
				target = Basis(knee_axis, deg_to_rad(BUCKLE_DEG) * 0.5 * buckle) * target
			"shin_l", "shin_r":
				tw = 0.0
				target = Basis(knee_axis, -deg_to_rad(BUCKLE_DEG) * 0.5 * buckle) * target
			_:
				# Arms: lightly held, they swing.
				tw *= 0.5
		target = Basis(Vector3.UP, tw) * Basis(lean_axis, a) * target
		var gain := s if not name.begins_with("upper_arm") and not name.begins_with("forearm") else s * 0.35
		var q := Quaternion((target * rb.global_basis.orthonormalized().inverse()).orthonormalized())
		var ang := q.get_angle()
		if ang > PI:
			ang -= TAU
		var want := q.get_axis() * ang * MUSCLE_GAIN if absf(ang) > 0.0005 else Vector3.ZERO
		if want.length() > MUSCLE_MAX:
			want = want.normalized() * MUSCLE_MAX
		rb.angular_velocity = rb.angular_velocity.lerp(want, blend * gain)
		# Held up: gravity cancelled by the support share; the stagger's travel eased out.
		rb.linear_velocity.y += 9.8 * support * dt
		var flat := Vector3(rb.linear_velocity.x, 0.0, rb.linear_velocity.z)
		rb.linear_velocity -= flat * (1.0 - exp(-2.5 * s * dt))


## Joint damping: each joint's relative spin eased out, the angular momentum of the pair kept.
func _joint_damping(dt: float) -> void:
	for a: Array in joints.anchors:
		var par := a[0] as RigidBody3D
		var ch := a[1] as RigidBody3D
		if par == null or ch == null or not is_instance_valid(par) or not is_instance_valid(ch) or par.is_queued_for_deletion() or ch.is_queued_for_deletion():
			continue
		var rate := spine_damp if ch == joints.parts.get("chest") or ch == joints.parts.get("head") else joint_damp
		var f := 1.0 - exp(-rate * dt)
		var ip := maxf(par.inertia.x, par.mass * 0.01)
		var ic := maxf(ch.inertia.x, ch.mass * 0.01)
		var rel := ch.angular_velocity - par.angular_velocity
		var d := rel * f
		ch.angular_velocity -= d * ip / (ip + ic)
		par.angular_velocity += d * ic / (ip + ic)


## Air drag, much stronger on the limbs: a flung body leads with its trunk, its limbs trailing.
func _air_drag(dt: float) -> void:
	for name: String in joints.parts:
		var rb := joints.parts[name] as RigidBody3D
		if not is_instance_valid(rb):
			continue
		var v := rb.linear_velocity
		var sp := v.length()
		if sp < 3.0:
			continue
		var k := DRAG_CORE if name in ["pelvis", "chest", "head"] else DRAG_LIMB
		rb.linear_velocity = v * maxf(1.0 - k * sp * dt, 0.5)


## RagdollJoints.tick() asks before it counts the doll still: true while it rolls down a slope or
## steps. Nudges it downhill while it does.
func rolling_down(dt: float) -> bool:
	if not enabled or age > roll_max:
		restore()
		return false
	var pelvis := joints.parts.get("pelvis") as RigidBody3D
	if pelvis == null or not is_instance_valid(pelvis) or not pelvis.is_inside_tree():
		restore()
		return false
	var space := pelvis.get_world_3d().direct_space_state
	var from := pelvis.global_position
	# Two rays a few decimetres apart along the way it moves (or fell): the ground's fall between
	# them is the slope, which a flight of steps reads like a ramp.
	var flat := Vector3(pelvis.linear_velocity.x, 0.0, pelvis.linear_velocity.z)
	var dir := flat.normalized() if flat.length() > 0.05 else (_slope_dir if not _slope_dir.is_zero_approx() else Vector3.ZERO)
	if dir.is_zero_approx():
		restore()
		return false
	var ex: Array[RID] = []
	for rb in joints.bodies():
		ex.append(rb.get_rid())
	var ys: Array[float] = []
	for o in [-0.35, 0.35]:
		var q := PhysicsRayQueryParameters3D.create(from + dir * o + Vector3.UP * 0.3, from + dir * o + Vector3.DOWN * 1.6, 1)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			restore()
			return false
		ys.append((hit.position as Vector3).y)
	var fall := ys[0] - ys[1]
	var slope := rad_to_deg(atan2(absf(fall), 0.7))
	if slope < roll_slope_deg:
		rolling = 0.0
		restore()
		return false
	var down := dir if fall > 0.0 else -dir
	_slope_dir = down
	var sp := Vector3(pelvis.linear_velocity.x, 0.0, pelvis.linear_velocity.z).length()
	rolling += dt
	# Tipping over the edge of a step: help downhill, and parts that slide over the nosings.
	if _roll_mat == null:
		_roll_mat = PhysicsMaterial.new()
		_roll_mat.friction = ROLL_FRICTION
		_roll_mat.bounce = 0.05
	var tumble := Vector3.UP.cross(down) * minf(sp / ROLL_RADIUS, ROLL_SPIN_MAX)
	var ease := 1.0 - exp(-ROLL_SPIN_RATE * dt)
	for rb in joints.bodies():
		rb.linear_velocity += down * ROLL_NUDGE * dt
		if rb == pelvis or rb == joints.parts.get("chest"):
			rb.angular_velocity = rb.angular_velocity.lerp(tumble, ease)
		if not _mats.has(rb):
			_mats[rb] = rb.physics_material_override
			rb.physics_material_override = _roll_mat
	if sp > roll_speed or rolling < 1.2:
		return true
	restore()
	return false


## The parts' own materials back (it stopped rolling, or the doll freezes).
func restore() -> void:
	for rb in _mats:
		if is_instance_valid(rb):
			(rb as RigidBody3D).physics_material_override = _mats[rb]
	_mats.clear()
