class_name RagdollJoints
extends RefCounted
## The jointed half of a Ragdoll (2026-10-30, "bodies that fall like people"). A rigged doll near
## the camera is not one tumbling box: it is eleven rigid bodies - pelvis, chest, head, upper arms,
## forearms (with the hand), thighs, shins (with the foot) - sized from the rig's own bones and held
## together by joints with a person's limits (cone-twist at the spine, neck, shoulders and hips,
## one-way hinges at the elbows and knees), so it folds over a bonnet, drapes off a kerb and lands
## with its arms out. A RagdollPose modifier poses the skeleton from the bodies every frame.
##
## The cost is bounded: at most `max_active` dolls are jointed at once (the oldest freezes when a
## new one needs the room), only within `joint_range` of the camera, and once a doll lies still
## (or after `settle_max` seconds, or the camera has left it) it FREEZES back into the old single
## body: every part's shape moves onto the pelvis body as one compound rigid body holding the pose
## it fell in, the limb bodies and the joints go, and the bones ride the pelvis from then on. So a
## settled doll costs what the old one did, and everything that reads `Ragdoll.bodies[0]` (the
## blood, Emergency's patients, the onlookers) still finds one body there.
##
## The pelvis IS the doll's original body (bodies[0]), moved onto the hips; the others are new
## RigidBody3Ds, direct children of the Ragdoll node, so WeaponFX, the shotgun and classify() find
## the doll from any part they hit (`collider.get_parent()`). RAGDOLLS=0 in the environment keeps
## every doll the old single body (the A/B).

## Off with RAGDOLLS=0 (the old single tumbling body everywhere).
static var enabled: bool = OS.get_environment("RAGDOLLS") != "0"
## Most dolls jointed at once (the web build: fewer).
static var max_active: int = 3 if OS.has_feature("web") else 6
## Only this close to the camera (metres) is a doll jointed; farther ones are the single body.
static var joint_range: float = 70.0
## A jointed doll the camera has left this far behind freezes.
static var leave_range: float = 110.0
## Still enough to freeze: every part under this speed (m/s) and spin (rad/s) ...
static var settle_speed: float = 0.35
static var settle_spin: float = 1.2
## ... for this long (seconds).
static var settle_hold: float = 0.6
## And whatever happens, frozen after this long (seconds).
static var settle_max: float = 8.0
## Shared spin of a flung doll (rad/s, each axis up to this) and the extra flail of each limb.
static var tumble_spin: float = 2.5
static var limb_flail: float = 4.0

## The jointed dolls alive now, oldest first (instance ids).
static var _active: Array[int] = []
## How many dolls have ever been jointed and frozen (the checks read them).
static var built_count: int = 0
static var frozen_count: int = 0

enum Shape { BOX, CAPSULE, SPHERE }
enum Joint { NONE, CONE, HINGE }

## The parts, parents first. bone: the bone the body rides; to: the bone its segment runs to;
## parent: the part it hangs from; shape and its size (box: width, depth; capsule / sphere:
## radius); extend: how far past `to` the segment runs (a hand, the top of the head), as a share
## of the segment; share: of the doll's mass; joint, and its limits in degrees (a cone: swing,
## twist; a hinge: how far it bends, and which way - 1 toward the front (elbow), -1 back (knee)).
const PARTS := [
	{"name": "pelvis", "bone": "Hips", "to": "Spine01", "parent": -1, "shape": Shape.BOX, "size": Vector2(0.32, 0.22), "extend": 0.35, "share": 0.18},
	{"name": "chest", "bone": "Spine01", "to": "neck", "parent": 0, "shape": Shape.BOX, "size": Vector2(0.36, 0.22), "extend": 0.0, "share": 0.26, "joint": Joint.CONE, "limits": Vector2(28.0, 22.0)},
	{"name": "head", "bone": "Head", "to": "head_end", "parent": 1, "shape": Shape.SPHERE, "size": Vector2(0.105, 0.0), "extend": 0.0, "share": 0.09, "joint": Joint.CONE, "limits": Vector2(38.0, 45.0)},
	{"name": "upper_arm_l", "bone": "LeftArm", "to": "LeftForeArm", "parent": 1, "shape": Shape.CAPSULE, "size": Vector2(0.055, 0.0), "extend": 0.0, "share": 0.04, "joint": Joint.CONE, "limits": Vector2(85.0, 40.0)},
	{"name": "forearm_l", "bone": "LeftForeArm", "to": "LeftHand", "parent": 3, "shape": Shape.CAPSULE, "size": Vector2(0.045, 0.0), "extend": 0.55, "share": 0.025, "joint": Joint.HINGE, "limits": Vector2(140.0, 1.0)},
	{"name": "upper_arm_r", "bone": "RightArm", "to": "RightForeArm", "parent": 1, "shape": Shape.CAPSULE, "size": Vector2(0.055, 0.0), "extend": 0.0, "share": 0.04, "joint": Joint.CONE, "limits": Vector2(85.0, 40.0)},
	{"name": "forearm_r", "bone": "RightForeArm", "to": "RightHand", "parent": 5, "shape": Shape.CAPSULE, "size": Vector2(0.045, 0.0), "extend": 0.55, "share": 0.025, "joint": Joint.HINGE, "limits": Vector2(140.0, 1.0)},
	{"name": "thigh_l", "bone": "LeftUpLeg", "to": "LeftLeg", "parent": 0, "shape": Shape.CAPSULE, "size": Vector2(0.075, 0.0), "extend": 0.0, "share": 0.11, "joint": Joint.CONE, "limits": Vector2(62.0, 25.0)},
	{"name": "shin_l", "bone": "LeftLeg", "to": "LeftFoot", "parent": 7, "shape": Shape.CAPSULE, "size": Vector2(0.055, 0.0), "extend": 0.0, "share": 0.06, "joint": Joint.HINGE, "limits": Vector2(145.0, -1.0)},
	{"name": "thigh_r", "bone": "RightUpLeg", "to": "RightLeg", "parent": 0, "shape": Shape.CAPSULE, "size": Vector2(0.075, 0.0), "extend": 0.0, "share": 0.11, "joint": Joint.CONE, "limits": Vector2(62.0, 25.0)},
	{"name": "shin_r", "bone": "RightLeg", "to": "RightFoot", "parent": 9, "shape": Shape.CAPSULE, "size": Vector2(0.055, 0.0), "extend": 0.0, "share": 0.06, "joint": Joint.HINGE, "limits": Vector2(145.0, -1.0)},
]
## The foot on each shin body: a box from the ankle to the toe.
const FEET := {"shin_l": ["LeftFoot", "LeftToeBase"], "shin_r": ["RightFoot", "RightToeBase"]}
## The parts each torn-off limb takes with it (Ragdoll.LIMBS' names).
const LIMB_PARTS := {
	"left_arm": ["upper_arm_l", "forearm_l"], "right_arm": ["upper_arm_r", "forearm_r"],
	"left_leg": ["thigh_l", "shin_l"], "right_leg": ["thigh_r", "shin_r"], "head": ["head"],
}

var doll: Node3D
## Part name -> RigidBody3D (the pelvis is the doll's own first body).
var parts: Dictionary = {}
var joints: Array[Joint3D] = []
## Each joint as [parent body, child body, the anchor in the parent's space] (gap()).
var anchors: Array = []
var pose: RagdollPose
var age: float = 0.0
var _still: float = 0.0
var frozen: bool = false


## Whether a doll made at `at` (world) may be jointed now: enabled, near the camera.
static func wanted(at: Vector3, viewport: Viewport) -> bool:
	if not enabled or max_active <= 0:
		return false
	var cam := viewport.get_camera_3d() if viewport else null
	return cam == null or cam.global_position.distance_to(at) <= joint_range


## Builds the joints into a doll whose rig is set up (Ragdoll.build_from_rig: `body` is its one
## body with the rig under it, in the tree). Returns null when the rig lacks a bone it needs (the
## doll stays the single body).
static func attach(rag: Node3D, body: RigidBody3D, rig: Node3D, anim: AnimationPlayer) -> RagdollJoints:
	var skel := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return null
	for p: Dictionary in PARTS:
		if skel.find_bone(p.bone) < 0 or skel.find_bone(p.to) < 0:
			return null
	# The reference pose: the first frame of the idle, standing straight, arms down. The limits
	# are measured from it.
	if anim:
		anim.stop()
		if anim.has_animation(Pedestrian.IDLE_CLIP):
			anim.play(Pedestrian.IDLE_CLIP)
			anim.seek(0.0, true)
			anim.pause()
	skel.force_update_all_bone_transforms()
	var sx := skel.global_transform
	var world := func(name: String) -> Transform3D:
		return sx * skel.get_bone_global_pose(skel.find_bone(name))
	var rig_world := rig.global_transform
	# Which way the person faces (the rigs face their own +Z) and which way is up the body.
	var fwd := (rig.global_basis * Vector3.BACK).normalized()
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized() if Vector2(fwd.x, fwd.z).length() > 0.1 else Vector3.FORWARD
	var j := RagdollJoints.new()
	j.doll = rag
	j.pose = RagdollPose.new()
	j.pose.name = "RagdollPose"
	var total: float = Ragdoll.TOTAL_MASS
	var bodies: Array[RigidBody3D] = []
	for i in PARTS.size():
		var p: Dictionary = PARTS[i]
		var bx: Transform3D = world.call(p.bone)
		var xf := Transform3D(bx.basis.orthonormalized(), bx.origin)
		var rb: RigidBody3D
		if i == 0:
			rb = body
			for c in rb.get_children():
				if c is CollisionShape3D:
					rb.remove_child(c)
					c.queue_free()
			rb.global_transform = xf
			# The rig stays where it was in the world, now under the moved pelvis.
			rig.global_transform = rig_world
		else:
			rb = RigidBody3D.new()
			rb.name = "Part_" + p.name
			rb.collision_layer = body.collision_layer
			rb.collision_mask = body.collision_mask
			rb.continuous_cd = true
			rag.add_child(rb)
			rb.global_transform = xf
		rb.mass = total * float(p.share)
		rb.angular_damp = 1.2 if i < 3 else 2.0
		rb.linear_damp = 0.05
		rb.physics_material_override = _material()
		var end: Vector3 = (world.call(p.to) as Transform3D).origin
		var seg := xf.affine_inverse() * end
		seg *= 1.0 + float(p.extend)
		_add_shape(rb, p, seg, xf, fwd)
		if FEET.has(p.name):
			var f: Array = FEET[p.name]
			var a := xf.affine_inverse() * (world.call(f[0]) as Transform3D).origin
			var b := xf.affine_inverse() * (world.call(f[1]) as Transform3D).origin
			_add_box(rb, (a + b) * 0.5 + (xf.basis.inverse() * Vector3.DOWN) * 0.02, b - a, xf, fwd, Vector2(0.1, 0.07), 0.08)
		j.parts[p.name] = rb
		bodies.append(rb)
		j.pose.bones.append(skel.find_bone(p.bone))
		j.pose.rides.append(rb)
		j.pose.offsets.append(xf.affine_inverse() * bx)
	# A person's parts pass through each other rather than fight: no part collides with another.
	for a in bodies.size():
		for b in range(a + 1, bodies.size()):
			bodies[a].add_collision_exception_with(bodies[b])
	for i in range(1, PARTS.size()):
		var p: Dictionary = PARTS[i]
		var child: RigidBody3D = bodies[i]
		var parent: RigidBody3D = bodies[int(p.parent)]
		var at: Vector3 = (world.call(p.bone) as Transform3D).origin
		var d: Vector3 = ((world.call(p.to) as Transform3D).origin - at).normalized()
		j.joints.append(_joint(rag, p, parent, child, at, d, fwd))
		j.anchors.append([parent, child, parent.global_transform.affine_inverse() * at])
	# Before any LimbHider (dismember adds one later), so a torn limb still collapses after it.
	skel.add_child(j.pose)
	skel.move_child(j.pose, 0)
	_active.append(rag.get_instance_id())
	built_count += 1
	return j


static func _material() -> PhysicsMaterial:
	var m := PhysicsMaterial.new()
	m.friction = 0.9
	m.bounce = 0.02
	return m


## The part's collision shape along its segment `seg` (body space).
static func _add_shape(rb: RigidBody3D, p: Dictionary, seg: Vector3, xf: Transform3D, fwd: Vector3) -> void:
	var size: Vector2 = p.size
	match int(p.shape):
		Shape.BOX:
			var centre := seg * 0.5
			if p.name == "pelvis":
				# The hips reach below the joint the bone starts at.
				centre = seg * 0.3
			_add_box(rb, centre, seg, xf, fwd, size, seg.length())
		Shape.SPHERE:
			var cs := CollisionShape3D.new()
			var sp := SphereShape3D.new()
			sp.radius = size.x
			cs.shape = sp
			cs.position = seg * 0.5
			rb.add_child(cs)
		_:
			var cs := CollisionShape3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = size.x
			cap.height = maxf(seg.length() + size.x * 2.0, size.x * 2.0 + 0.01)
			cs.shape = cap
			cs.transform = Transform3D(_along(seg, xf, fwd), seg * 0.5)
			rb.add_child(cs)


## A box centred at `centre`, `length` along `along`, `size` across (width, depth).
static func _add_box(rb: RigidBody3D, centre: Vector3, along: Vector3, xf: Transform3D, fwd: Vector3, size: Vector2, length: float) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, maxf(length, 0.04), size.y)
	cs.shape = box
	cs.transform = Transform3D(_along(along, xf, fwd), centre)
	rb.add_child(cs)


## A basis (body space) whose Y runs along `seg`, X across the body and Z its front.
static func _along(seg: Vector3, xf: Transform3D, fwd: Vector3) -> Basis:
	var y := seg.normalized() if seg.length() > 0.001 else Vector3.UP
	var f := (xf.basis.inverse() * fwd).normalized()
	var x := y.cross(f)
	if x.length() < 0.05:
		x = y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD)
	x = x.normalized()
	return Basis(x, y, x.cross(y).normalized())


## The joint between `parent` and `child` at `at` (world), the child's segment running along `d`.
static func _joint(rag: Node3D, p: Dictionary, parent: RigidBody3D, child: RigidBody3D, at: Vector3, d: Vector3, fwd: Vector3) -> Joint3D:
	var lim: Vector2 = p.limits
	var jn: Joint3D
	if int(p.joint) == Joint.HINGE:
		var h := HingeJoint3D.new()
		# The axis a positive turn about which bends the limb toward the front (elbow) or back
		# (knee): d x front. Godot's hinge counts that turn NEGATIVE (measured), so the bend is the
		# limit's lower side.
		var toward := fwd * signf(lim.y)
		var axis := d.cross(toward)
		if axis.length() < 0.05:
			axis = d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT)
		axis = axis.normalized()
		var x := d.slide(axis).normalized()
		h.set_meta("xf", Transform3D(Basis(x, axis.cross(x), axis), at))
		h.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		h.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -deg_to_rad(lim.x))
		h.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(4.0))
		h.set_param(HingeJoint3D.PARAM_LIMIT_SOFTNESS, 0.9)
		h.set_param(HingeJoint3D.PARAM_LIMIT_RELAXATION, 1.0)
		jn = h
	else:
		var c := ConeTwistJoint3D.new()
		# The twist axis (the joint's X) runs down the child's segment.
		var y := d.cross(fwd)
		if y.length() < 0.05:
			y = d.cross(Vector3.RIGHT)
		y = y.normalized()
		c.set_meta("xf", Transform3D(Basis(d, y, d.cross(y).normalized()), at))
		c.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(lim.x))
		c.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(lim.y))
		c.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.8)
		c.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)
		jn = c
	jn.name = "Joint_" + p.name
	jn.exclude_nodes_from_collision = true
	rag.add_child(jn)
	# The frame is world space: set once the joint is under the (moved, turned) doll.
	jn.global_transform = jn.get_meta("xf")
	jn.remove_meta("xf")
	jn.node_a = jn.get_path_to(parent)
	jn.node_b = jn.get_path_to(child)
	return jn


## Every live part (the pelvis first).
func bodies() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for p: Dictionary in PARTS:
		var rb: RigidBody3D = parts.get(p.name)
		if rb != null and is_instance_valid(rb):
			out.append(rb)
	return out


## Flings the whole doll: the old single body's speed on every part, one shared tumble about the
## centre of mass, and each limb a flail of its own. The old body took `impulse` as its SPEED
## (measured): Godot Physics works a new body's mass out at its first step, so an impulse in the
## frame it is made meets a mass of 1. Every knock in the game is tuned to that, so it stays.
func fling(impulse: Vector3) -> void:
	var list := bodies()
	var v := impulse
	var com := Vector3.ZERO
	var m := 0.0
	for rb in list:
		com += rb.global_position * rb.mass
		m += rb.mass
	com /= maxf(m, 0.001)
	var w := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * tumble_spin
	for i in list.size():
		var rb := list[i]
		rb.linear_velocity += v + w.cross(rb.global_position - com)
		rb.angular_velocity = w
		if i >= 3:
			rb.angular_velocity += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * limb_flail


## How far the worst joint has pulled apart (metres): the child's origin is its joint, and the
## parent carries where that joint was. Under a few centimetres while the solver holds.
func gap() -> float:
	var worst := 0.0
	for a: Array in anchors:
		var par := a[0] as RigidBody3D
		var ch := a[1] as RigidBody3D
		if par == null or ch == null or not is_instance_valid(par) or not is_instance_valid(ch) or par.is_queued_for_deletion() or ch.is_queued_for_deletion():
			continue
		worst = maxf(worst, (par.global_transform * (a[2] as Vector3)).distance_to(ch.global_position))
	return worst


## The part nearest `at` (world): a round shoves the arm it went through, not the hips.
func nearest(at: Vector3) -> RigidBody3D:
	var best: RigidBody3D = null
	var bd := INF
	for rb in bodies():
		var d := rb.global_position.distance_squared_to(at)
		if d < bd:
			bd = d
			best = rb
	return best


## The parts of a torn-off limb go (Ragdoll.dismember): their joints, bodies and bones.
func drop_limb(limb: String, skel: Skeleton3D) -> void:
	for name: String in LIMB_PARTS.get(limb, []):
		var rb: RigidBody3D = parts.get(name)
		if rb == null:
			continue
		for jn in joints.duplicate():
			if is_instance_valid(jn) and (jn.get_node_or_null(jn.node_b) == rb or jn.get_node_or_null(jn.node_a) == rb):
				joints.erase(jn)
				jn.queue_free()
		for p: Dictionary in PARTS:
			if p.name == name and skel:
				pose.drop_bone(skel.find_bone(p.bone))
		parts.erase(name)
		if is_instance_valid(rb):
			rb.queue_free()


## Called every frame while jointed. Freezes the doll once it is still, old, or left behind.
## True while it stays jointed.
func tick(delta: float) -> bool:
	if frozen:
		return false
	age += delta
	var still := true
	for rb in bodies():
		if rb.linear_velocity.length() > settle_speed or rb.angular_velocity.length() > settle_spin:
			still = false
			break
	_still = _still + delta if still else 0.0
	var gone := false
	var cam := doll.get_viewport().get_camera_3d() if doll.is_inside_tree() else null
	if cam and cam.global_position.distance_to((parts.get("pelvis") as Node3D).global_position) > leave_range:
		gone = true
	if (_still >= settle_hold and age > 0.5) or age >= settle_max or gone:
		freeze()
		return false
	return true


## Into one body: every part's shapes onto the pelvis (where they lie now), the bones riding it,
## the limb bodies and joints gone. The pelvis keeps the whole mass and is left asleep.
func freeze() -> void:
	if frozen:
		return
	frozen = true
	frozen_count += 1
	_active.erase(doll.get_instance_id())
	var pelvis: RigidBody3D = parts.get("pelvis")
	if pelvis == null or not is_instance_valid(pelvis):
		return
	var inv := pelvis.global_transform.affine_inverse()
	for jn in joints:
		if is_instance_valid(jn):
			jn.queue_free()
	joints.clear()
	for p: Dictionary in PARTS:
		var rb: RigidBody3D = parts.get(p.name)
		if rb == null or rb == pelvis or not is_instance_valid(rb):
			continue
		var rel := inv * rb.global_transform
		for c in rb.get_children():
			if c is CollisionShape3D:
				var cs := CollisionShape3D.new()
				cs.shape = (c as CollisionShape3D).shape
				cs.transform = rel * (c as CollisionShape3D).transform
				pelvis.add_child(cs)
		pose.rebase(rb, pelvis)
		# Anything that rode the limb (a drip, a hat) moves onto the pelvis where it is.
		for c in rb.get_children():
			if not (c is CollisionShape3D):
				c.reparent(pelvis, true)
		rb.queue_free()
	parts = {"pelvis": pelvis}
	# The pose baked into the skeleton's own bone poses (the clip is paused, nothing overwrites
	# them) and the modifier gone: a frozen doll costs no skeleton work a frame.
	var skel := pose.get_skeleton()
	if skel:
		var sinv := skel.global_transform.affine_inverse()
		for i in pose.bones.size():
			skel.set_bone_global_pose(pose.bones[i], sinv * pose.rides[i].global_transform * pose.offsets[i])
		pose.active = false
		pose.queue_free()
	pelvis.mass = Ragdoll.TOTAL_MASS
	pelvis.linear_velocity = Vector3.ZERO
	pelvis.angular_velocity = Vector3.ZERO
	pelvis.sleeping = true


## The jointed dolls alive now (the checks; pruned of freed ones).
static func active_count() -> int:
	_active = _active.filter(func(id): return is_instance_valid(instance_from_id(id)))
	return _active.size()


## Room for one more: the oldest jointed doll freezes when the cap is reached.
static func make_room() -> void:
	active_count()
	while _active.size() >= max_active and not _active.is_empty():
		var old := instance_from_id(_active[0]) as Node
		_active.remove_at(0)
		if old != null and old.get("_joints") != null:
			(old.get("_joints") as RagdollJoints).freeze()
