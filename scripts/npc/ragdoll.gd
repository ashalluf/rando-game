class_name Ragdoll
extends Node3D
## A knocked-over pedestrian. With a rigged model it is that same character tumbling as one
## rigid body, flailing its run cycle until it comes to rest (build_from_rig); without one it is
## the floppy six-piece box body held together by pin joints (build). Spawned when a pedestrian
## gets hit. Registered as debris so PhysicsBudget frees it later.

## Total mass of the box body; fling() scales impulses by piece mass over this.
const TOTAL_MASS := 23.0

var bodies: Array[RigidBody3D] = []
var _anim: AnimationPlayer
var _age: float = 0.0
var _rig: Node3D
var _rig_path: String = ""
var _hider: LimbHider
var _limbs: Array[RigidBody3D] = []
var _skel: Skeleton3D

## How badly this body is bleeding: its wounds' strengths summed (1 per rifle round, more for a
## torn-off limb). It sizes the pool, and a body that was only knocked over has 0 and leaves
## no blood at all.
var bleed: float = 0.0
## This body's pools (they live under the scene root and outlive it) and where the last began.
var _pools: Array = []
var _pool_at := Vector3.INF
## The drag trail: where the last smear ended and how many more it may lay.
var _trail_from := Vector3.INF
var _trail_left: int = 0
var _blood_tick: float = 0.0
var _drip: Node
## Wounds shot into this body that wait one frame for the skeleton's pose ([point in the body's
## own space, radius in metres]), and the stains they became ({bone, local, radius, age}), drawn
## by character.gdshader's wound_* uniforms on a copy of the look's material.
var _stains_due: Array = []
var _wounds: Array = []
var _stain_mat: ShaderMaterial
## Torn-off limbs still able to leave a trail: limb instance id -> [limb, smears left, last spot].
var _limb_trails: Dictionary = {}
## Most stains one body carries; a new one past this replaces the oldest.
const MAX_WOUNDS := 4
## Seconds a stain takes to soak out to its full size.
const STAIN_SOAK := 3.5

## The limbs a blast can take off: the bone the limb hangs from (it collapses, with everything
## below it) and every bone whose skin belongs to the flying piece. Standard humanoid names; all
## nine pedestrian rigs share them.
const LIMBS := {
	"left_arm": ["LeftArm", "LeftForeArm", "LeftHand"],
	"right_arm": ["RightArm", "RightForeArm", "RightHand"],
	"left_leg": ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase"],
	"right_leg": ["RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"],
	"head": ["Head", "head_end", "headfront"],
}
## Kilograms of a flying limb, and how long before PhysicsBudget clears it with the other debris.
const LIMB_MASS := {"left_arm": 3.5, "right_arm": 3.5, "left_leg": 9.0, "right_leg": 9.0, "head": 5.0}
## Limb meshes cut out of each character model, keyed "path|limb": [ArrayMesh, centre, size].
static var _limb_cache: Dictionary = {}


## The real character as one tumbling body. False when the model cannot be loaded.
func build_from_rig(path: String, look: int = -1) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var scene: PackedScene = load(path)
	if scene == null:
		return false
	var inst := scene.instantiate() as Node3D
	Pedestrian.prepare_rig(inst, look)
	# Out of the blood decals' reach: the pool it lies in would paint it from above.
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = WeaponFX.NO_BLOOD_LAYER
	inst.rotation.y = PI
	_rig = inst
	_rig_path = path
	var body := RigidBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 5 # world and props, not other characters
	body.mass = TOTAL_MASS
	body.continuous_cd = true
	body.angular_damp = 0.6
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 1.7, 0.4)
	shape.shape = box
	shape.position = Vector3(0.0, 0.87, 0.0)
	body.add_child(shape)
	body.add_child(inst)
	add_child(body)
	bodies.append(body)
	_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim and _anim.has_animation("run_fast_3_inplace"):
		_anim.get_animation("run_fast_3_inplace").loop_mode = Animation.LOOP_LINEAR
		_anim.play("run_fast_3_inplace")
		_anim.speed_scale = 2.2
	return true


func _process(delta: float) -> void:
	if bodies.is_empty():
		return
	_age += delta
	var busy := false
	if bleed > 0.0:
		busy = _blood_step(delta)
	if _anim != null and _anim.is_playing():
		var body: RigidBody3D = bodies[0]
		# Stop flailing once it lies still.
		if _age > 0.8 and (body.sleeping or body.linear_velocity.length() < 0.7):
			_anim.pause()
		else:
			busy = true
	if not busy:
		set_process(false)


## Shot where it lies, or on the way down (Pedestrian.shot hands the round on; WeaponFX
## .bullet_wound sends shots at a body here). Bleeds from the hit, stains the clothes round the
## entry and the exit, drips for a while and feeds the pool. `impulse` is an extra shove at the
## hit (the rifle already shoves rigid bodies itself). Same signature as Pedestrian.shot().
func shot(at: Vector3, dir: Vector3, impulse: Vector3 = Vector3.ZERO, strength: float = 1.0) -> void:
	if bodies.is_empty():
		return
	var body: RigidBody3D = bodies[0]
	if impulse.length() > 0.01:
		body.apply_impulse(impulse, at - body.global_position)
	WeaponFX.blood(self, at, dir, strength, self)
	var d := dir.normalized() if not dir.is_zero_approx() else Vector3.FORWARD
	var s := sqrt(clampf(strength, 0.1, WeaponFX.blood_strength_max))
	var inv := body.global_transform.affine_inverse()
	# The entry a little inside where the ray met the collision shape (which stands off the skin),
	# and the exit on the far side, bigger, the way an exit wound is.
	_stains_due.append([inv * (at + d * 0.08), 0.10 * s])
	_stains_due.append([inv * (at + d * WeaponFX.blood_exit_depth), 0.15 * s])
	_wounded(strength, inv * (at + d * WeaponFX.blood_exit_depth))


## Books a wound: more bleeding, a wider pool, a fresh drip from `drip_at` (the body's own
## space) and a trail again if it slides.
func _wounded(strength: float, drip_at: Vector3) -> void:
	bleed += strength
	for pool in _pools:
		WeaponFX.feed_pool(pool, bleed)
	if is_instance_valid(_drip):
		_drip.queue_free()
	_drip = WeaponFX.blood_drip(bodies[0], drip_at, WeaponFX.blood_drip_seconds * clampf(bleed, 1.0, 2.0))
	_trail_left = WeaponFX.blood_trail_max
	set_process(true)


## Blood upkeep: stains placed once the pose is known and soaking outward (every frame, while
## the limbs still flail), and ten times a second a pool once the body has come to rest (a second
## one if it is moved on), smears while it slides along the ground, and the same for its torn-off
## limbs. True while any of it still has something to do.
func _blood_step(delta: float) -> bool:
	# One frame after the shot the skeleton has taken its first pose of the flailing clip.
	if not _stains_due.is_empty() and _age > delta:
		for s: Array in _stains_due:
			_place_stain(s[0], s[1])
		_stains_due.clear()
	var soaking := _update_stains(delta)
	_blood_tick -= delta
	if _blood_tick > 0.0:
		return true
	_blood_tick = 0.1
	var body: RigidBody3D = bodies[0]
	var pelvis := _pelvis()
	var ground := _ground_under(pelvis)
	var waiting := false
	if not ground.is_empty():
		var gp: Vector3 = ground.position
		var gn: Vector3 = ground.normal
		var lying := pelvis.y - gp.y < 0.6
		var flat := Vector3(body.linear_velocity.x, 0.0, body.linear_velocity.z)
		# Dragged along the ground: a smear every trail step.
		if lying and _trail_left > 0 and flat.length() > 1.2:
			if _trail_from == Vector3.INF:
				_trail_from = gp
			elif gp.distance_to(_trail_from) > WeaponFX.blood_trail_step:
				WeaponFX.blood_smear(self, (gp + _trail_from) * 0.5, gn, gp - _trail_from,
					gp.distance_to(_trail_from) * 1.35, 0.36)
				_trail_from = gp
				_trail_left -= 1
		else:
			_trail_from = Vector3.INF
		# At rest (or long enough that it is not going to be): the pool spreads from under the hips.
		var resting := _age > 0.7 and body.linear_velocity.length() < 0.8
		if lying and (resting or _age > 3.5):
			if _pool_at == Vector3.INF or (gp.distance_to(_pool_at) > 1.2 and _pools.size() < 2):
				var pool := WeaponFX.blood_pool(self, gp, gn, bleed)
				if pool:
					_pools.append(pool)
					_pool_at = gp
		elif _pool_at == Vector3.INF:
			waiting = true
	elif _pool_at == Vector3.INF and _age < 6.0:
		waiting = true
	var limbs := _limb_blood()
	var sliding := Vector2(body.linear_velocity.x, body.linear_velocity.z).length() > 1.2
	return (soaking or waiting or limbs or sliding) and _age < 16.0


## The hips in the world (the pool runs out from under them), or the body's middle.
func _pelvis() -> Vector3:
	var skel := _skeleton()
	if skel:
		var hips := skel.find_bone("Hips")
		if hips >= 0:
			return skel.global_transform * skel.get_bone_global_pose(hips).origin
	return bodies[0].global_transform * Vector3(0.0, 0.87 if _rig else 0.0, 0.0)


## The ground straight under `at` (the world layer only: a body on a car roof gets no pool on the
## roof, and none on the road under the car either, since it is too far down).
func _ground_under(at: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var skip: Array[RID] = []
	for b in bodies:
		skip.append(b.get_rid())
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.DOWN * 1.2, 1, skip)
	return space.intersect_ray(q)


func _skeleton() -> Skeleton3D:
	if _skel == null and _rig != null:
		_skel = _rig.find_child("Skeleton3D", true, false) as Skeleton3D
	return _skel


## A stain on the clothes round a wound: `local_at` in the body's own space, `radius` in metres.
## It rides the bone nearest the wound, so it stays on the sleeve or the shirt as they flail.
func _place_stain(local_at: Vector3, radius: float) -> void:
	var skel := _skeleton()
	if skel == null or _stain_material() == null:
		return
	var world: Vector3 = bodies[0].global_transform * local_at
	var sp := skel.global_transform.affine_inverse() * world
	# Skeleton units per metre (the rigs are in centimetres under a 0.01 armature).
	var unit := 1.0 / maxf(skel.global_basis.get_scale().x, 0.0001)
	var bone := _nearest_bone(skel, sp)
	if bone < 0:
		return
	var local := skel.get_bone_global_pose(bone).affine_inverse() * sp
	var r := radius * unit
	# Shot again close to a stain: that stain spreads instead of a second one on top of it.
	for w: Dictionary in _wounds:
		if int(w.bone) == bone and (w.local as Vector3).distance_to(local) < r * 0.9:
			w.radius = minf(float(w.radius) + r * 0.45, float(w.radius) * 1.8)
			return
	if _wounds.size() >= MAX_WOUNDS:
		_wounds.pop_front()
	_wounds.append({"bone": bone, "local": local, "radius": r, "age": 0.0})


## The bone whose segment (from its own origin to its child's) passes nearest `sp`, skeleton space.
static func _nearest_bone(skel: Skeleton3D, sp: Vector3) -> int:
	var best := -1
	var best_d := INF
	for b in skel.get_bone_count():
		var a := skel.get_bone_global_pose(b).origin
		var kids := skel.get_bone_children(b)
		var e := skel.get_bone_global_pose(kids[0]).origin if kids.size() > 0 else a
		var ab := e - a
		var t := clampf((sp - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var dist := sp.distance_to(a + ab * t)
		if dist < best_d:
			best_d = dist
			best = b
	return best


## Pushes the stains to the shader: each one where its bone has carried it, soaking out over
## STAIN_SOAK seconds. True while one is still soaking or the limbs still move.
func _update_stains(delta: float) -> bool:
	if _wounds.is_empty() or _stain_mat == null:
		return false
	var skel := _skeleton()
	if skel == null:
		return false
	var soaking := false
	for i in MAX_WOUNDS:
		var v := Vector4.ZERO
		if i < _wounds.size():
			var w: Dictionary = _wounds[i]
			w.age = float(w.age) + delta
			var k := smoothstep(0.0, STAIN_SOAK, float(w.age))
			soaking = soaking or k < 1.0
			var p := skel.get_bone_global_pose(int(w.bone)) * (w.local as Vector3)
			v = Vector4(p.x, p.y, p.z, float(w.radius) * lerpf(0.45, 1.0, k))
		_stain_mat.set_shader_parameter("wound_%d" % i, v)
	_stain_mat.set_shader_parameter("wound_count", float(_wounds.size()))
	return soaking or (_anim != null and _anim.is_playing())


## This body's own copy of its look's material, made the first time it is stained. The looks are
## shared by the whole crowd, so a stain set on one would bleed through every copy of that look.
func _stain_material() -> ShaderMaterial:
	if _stain_mat != null:
		return _stain_mat
	if _rig == null:
		return null
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var shared := m.material_override as ShaderMaterial
		if m.skin == null or shared == null:
			continue
		if _stain_mat == null:
			_stain_mat = shared.duplicate() as ShaderMaterial
		m.material_override = _stain_mat
	return _stain_mat


## Torn-off limbs leave a splat where they come down and a smear while they skid. True while one
## still might.
func _limb_blood() -> bool:
	if _limb_trails.is_empty():
		return false
	for id: int in _limb_trails.keys():
		var entry: Array = _limb_trails[id]
		var limb := entry[0] as RigidBody3D
		if not is_instance_valid(limb) or int(entry[1]) <= 0 or _age > 8.0:
			_limb_trails.erase(id)
			continue
		var ground := _ground_under(limb.global_position)
		if ground.is_empty():
			continue
		var gp: Vector3 = ground.position
		if limb.global_position.y - gp.y > 0.35:
			continue
		var last: Vector3 = entry[2]
		if last == Vector3.INF:
			WeaponFX.blood_splat_below(self, limb.global_position, randf_range(0.3, 0.45))
			entry[2] = gp
			entry[1] = int(entry[1]) - 1
		elif gp.distance_to(last) > 0.35 and limb.linear_velocity.length() > 0.8:
			WeaponFX.blood_smear(self, (gp + last) * 0.5, ground.normal, gp - last, gp.distance_to(last) * 1.3, 0.2)
			entry[2] = gp
			entry[1] = int(entry[1]) - 1
	return not _limb_trails.is_empty()


## Tears `count` limbs off (a close blast; owner, 2026-09-23: "body parts limbs flying off ...
## from the rocket launcher"). Each lost limb collapses on the body (LimbHider), leaves a bloody
## stump, and flies off as its own piece of debris - a plain mesh cut out of the character
## model, so a limb costs one draw and no skeleton. Only rigged ragdolls come apart.
func dismember(count: int, impulse: Vector3) -> int:
	if _rig == null or count <= 0:
		return 0
	var skel := _rig.find_child("Skeleton3D", true, false) as Skeleton3D
	var source: MeshInstance3D = null
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin != null:
			source = mi
			break
	if skel == null or source == null:
		return 0
	if _hider == null:
		_hider = LimbHider.new()
		skel.add_child(_hider)
	var names: Array = LIMBS.keys()
	names.shuffle()
	# Heads come off least often: all four limbs first in the draw, the head only at the end.
	if names.has("head") and names.find("head") < count - 1:
		names.erase("head")
		names.append("head")
	var torn := 0
	for limb: String in names.slice(0, count):
		var root_bone := skel.find_bone(LIMBS[limb][0])
		if root_bone < 0:
			continue
		var piece: Array = _limb_mesh(source, skel, limb)
		if piece.is_empty():
			continue
		_hider.bones.append(root_bone)
		var joint := skel.global_transform * skel.get_bone_global_pose(root_bone).origin
		_add_stump(skel, root_bone)
		_throw_limb(piece, limb, source.get_active_material(0), impulse)
		var out := (impulse.normalized() + Vector3.UP * 0.6).normalized()
		WeaponFX.blood_gush(self, joint, out, WeaponFX.blood_gib_strength, self)
		# The stump soaks what is left of the clothes round it, pumps for a while, and pools.
		var inv: Transform3D = bodies[0].global_transform.affine_inverse()
		_stains_due.append([inv * joint, 0.2])
		_wounded(WeaponFX.blood_gib_strength, inv * joint)
		torn += 1
	if torn > 0:
		Sfx.play("gore", global_position + Vector3.UP, 2.0)
	return torn


## A dark wound where the limb was, riding the bone it hung from.
func _add_stump(skel: Skeleton3D, root_bone: int) -> void:
	var parent_bone := skel.get_bone_parent(root_bone)
	if parent_bone < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = skel.get_bone_name(parent_bone)
	skel.add_child(att)
	var cap := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	# The attachment carries the rig's own scale (the skeletons are in centimetres under a 0.01
	# armature), so the cap is sized in the bone's units, from what one metre is there.
	var unit := 1.0 / maxf(skel.global_basis.get_scale().x, 0.0001)
	sphere.radius = 0.075 * unit
	sphere.height = 0.12 * unit
	sphere.radial_segments = 10
	sphere.rings = 5
	cap.mesh = sphere
	cap.material_override = _wound_material()
	cap.position = skel.get_bone_rest(root_bone).origin
	att.add_child(cap)


func _throw_limb(piece: Array, limb: String, material: Material, impulse: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = "Limb"
	body.collision_layer = 4
	# The world only, and never the body it came off: it is spawned inside that body's box, and
	# a collision there fired limbs forty metres into the air.
	body.collision_mask = 1
	body.mass = LIMB_MASS.get(limb, 4.0)
	body.continuous_cd = true
	body.angular_damp = 0.4
	body.add_to_group("gib")
	var mi := MeshInstance3D.new()
	mi.mesh = piece[0]
	mi.layers = WeaponFX.NO_BLOOD_LAYER
	if material:
		mi.material_override = material
	body.add_child(mi)
	var cap := MeshInstance3D.new()
	cap.mesh = _limb_cap_mesh()
	cap.material_override = _wound_material()
	cap.position = piece[3]
	body.add_child(cap)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (piece[2] as Vector3).clamp(Vector3.ONE * 0.08, Vector3.ONE * 1.2)
	shape.shape = box
	body.add_child(shape)
	for b in bodies:
		body.add_collision_exception_with(b)
	for other in _limbs:
		if is_instance_valid(other):
			body.add_collision_exception_with(other)
	_limbs.append(body)
	var holder: Node = get_parent() if get_parent() else self
	holder.add_child(body)
	# The torn end drips as it flies, then marks the road where it lands and skids.
	WeaponFX.blood_drip(body, piece[3], WeaponFX.blood_drip_seconds, 0.8)
	_limb_trails[body.get_instance_id()] = [body, 6, Vector3.INF]
	var at: Vector3 = _rig.global_transform * (piece[1] as Vector3)
	# Clear of the ground first. A leg's box reaches down to the foot, below the pavement top,
	# and the depenetration alone fired it upward at 45 m/s.
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		at.y = maxf(at.y, (hit.position as Vector3).y + box.size.y * 0.5 + 0.05)
	body.global_transform = Transform3D(_rig.global_basis.orthonormalized(), at)
	# Thrown out along the blast, fast enough to read as torn off, with a little lift.
	var out := impulse.normalized() if impulse.length() > 0.01 else Vector3.UP
	var speed := clampf(impulse.length() * 0.25, 4.0, 12.0)
	body.linear_velocity = out * speed + Vector3(randf_range(-2.0, 2.0), randf_range(1.5, 4.5), randf_range(-2.0, 2.0))
	body.angular_velocity = Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14))
	PhysicsBudget.register_debris(body)


## Cuts every limb of a character model into the cache now (the loading screen does this), so
## the first blast that takes one off does not stall for it. `host` is any node in the tree.
static func warm_limbs(path: String, host: Node) -> void:
	if not ResourceLoader.exists(path):
		return
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	host.add_child(inst)
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if skel and m.skin and m.mesh:
			_limb_mesh(m, skel, "head")
			break
	inst.queue_free()


## The piece of the character's skin that belongs to `limb`, as a static mesh in the model's
## own space, re-centred: [mesh, centre, size, joint end]. A triangle goes to a limb when all
## three corners are weighted mostly to its bones. The first ask for a model cuts all five limbs
## in one pass over its skin (reading a mesh back and walking 18k vertices is the expensive
## part, and it was being paid once per limb), then every later one is a lookup.
static func _limb_mesh(source: MeshInstance3D, skel: Skeleton3D, limb: String) -> Array:
	var model := "%s|%s" % [source.mesh.resource_path, source.mesh.get_rid()]
	if not _limb_cache.has(model + "|" + limb):
		_cut_limbs(source, skel, model)
	return _limb_cache.get(model + "|" + limb, [])


static func _cut_limbs(source: MeshInstance3D, skel: Skeleton3D, model: String) -> void:
	var limbs: Array = LIMBS.keys()
	for limb: String in limbs:
		_limb_cache[model + "|" + limb] = []
	var arrays := source.mesh.surface_get_arrays(0)
	if arrays.is_empty() or source.skin == null:
		return
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if verts.is_empty() or bones.is_empty() or index.is_empty():
		return
	var per := bones.size() / verts.size()
	# Which limb each skin bind belongs to (-1 = the body).
	var bind_limb := PackedInt32Array()
	bind_limb.resize(source.skin.get_bind_count())
	bind_limb.fill(-1)
	for li in limbs.size():
		for bn: String in LIMBS[limbs[li]]:
			for i in source.skin.get_bind_count():
				if String(source.skin.get_bind_name(i)) == bn:
					bind_limb[i] = li
	# Each vertex's limb, from its heaviest bone.
	var vert_limb := PackedInt32Array()
	vert_limb.resize(verts.size())
	for v in verts.size():
		var best := 0
		var best_w := -1.0
		for k in per:
			var w := weights[v * per + k]
			if w > best_w:
				best_w = w
				best = bones[v * per + k]
		vert_limb[v] = bind_limb[best] if best >= 0 and best < bind_limb.size() else -1
	# Rest-pose positions in the model's space. A skinned vertex is NOT stored in the skeleton's
	# space: it is taken there by its bones' bind poses, exactly as the GPU does it, and on these
	# rigs the two differ by the centimetre scale - read raw, a limb came out a hundredth of its
	# size at the body's feet. So each vertex is skinned here once, at rest, by its own weights.
	var to_model := _rig_space(source, skel)
	var bind_xf: Array[Transform3D] = []
	for i in source.skin.get_bind_count():
		var bone := skel.find_bone(source.skin.get_bind_name(i))
		var rest := skel.get_bone_global_rest(bone) if bone >= 0 else Transform3D.IDENTITY
		bind_xf.append(to_model * rest * source.skin.get_bind_pose(i))
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	# Tangents too: the character shader is normal-mapped, and without them a limb lights as if
	# its surface pointed nowhere.
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var has_t := tangents.size() == verts.size() * 4
	# One pass sorts the triangles by limb. Plain Arrays, because they are shared by reference:
	# a Packed array taken out of a container is a copy, and appending to it builds nothing.
	var tris: Array = []
	for li in limbs.size():
		tris.append([])
	for t in index.size() / 3:
		var li := vert_limb[index[t * 3]]
		if li >= 0 and vert_limb[index[t * 3 + 1]] == li and vert_limb[index[t * 3 + 2]] == li:
			(tris[li] as Array).append(t)
	var rig_xf := _rig_space_of_skel(skel)
	for li in limbs.size():
		var list: Array = tris[li]
		if list.size() < 10:
			continue
		var remap := {}
		var out_v := PackedVector3Array()
		var out_n := PackedVector3Array()
		var out_t := PackedFloat32Array()
		var out_uv := PackedVector2Array()
		var out_i := PackedInt32Array()
		for t: int in list:
			for c in 3:
				var v := index[t * 3 + c]
				if not remap.has(v):
					remap[v] = out_v.size()
					var pos := Vector3.ZERO
					var basis := Basis()
					var total := 0.0
					for k in per:
						var w := weights[v * per + k]
						var bi := bones[v * per + k]
						if w <= 0.0 or bi < 0 or bi >= bind_xf.size():
							continue
						pos += bind_xf[bi] * verts[v] * w
						total += w
						if k == 0 or w > 0.5:
							basis = bind_xf[bi].basis
					out_v.append(pos / maxf(total, 0.0001))
					if not normals.is_empty():
						out_n.append((basis * normals[v]).normalized())
					if not uvs.is_empty():
						out_uv.append(uvs[v])
					if has_t:
						var tv := (basis * Vector3(tangents[v * 4], tangents[v * 4 + 1], tangents[v * 4 + 2])).normalized()
						out_t.append_array(PackedFloat32Array([tv.x, tv.y, tv.z, tangents[v * 4 + 3]]))
				out_i.append(remap[v])
		var box := AABB(out_v[0], Vector3.ZERO)
		for p in out_v:
			box = box.expand(p)
		var centre := box.get_center()
		for i in out_v.size():
			out_v[i] -= centre
		var mesh_arrays := []
		mesh_arrays.resize(Mesh.ARRAY_MAX)
		mesh_arrays[Mesh.ARRAY_VERTEX] = out_v
		if not out_n.is_empty():
			mesh_arrays[Mesh.ARRAY_NORMAL] = out_n
		if not out_uv.is_empty():
			mesh_arrays[Mesh.ARRAY_TEX_UV] = out_uv
		if has_t:
			mesh_arrays[Mesh.ARRAY_TANGENT] = out_t
		mesh_arrays[Mesh.ARRAY_INDEX] = out_i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
		# The torn end: the limb's root joint, in the re-centred space.
		var root_bone := skel.find_bone(LIMBS[limbs[li]][0])
		var joint := rig_xf * skel.get_bone_global_rest(root_bone).origin - centre
		_limb_cache[model + "|" + limbs[li]] = [mesh, centre, box.size, joint]


## From a skinned mesh's vertex space (the skeleton's, in rest pose) to the model root's space.
static func _rig_space(_source: MeshInstance3D, skel: Skeleton3D) -> Transform3D:
	return _rig_space_of_skel(skel)


static func _rig_space_of_skel(skel: Skeleton3D) -> Transform3D:
	# Up to, not including, the model's own scene root (the instanced .glb): its transform is
	# where the model is placed, not part of the model.
	var xf := Transform3D.IDENTITY
	var n: Node = skel
	while n != null and n.scene_file_path == "":
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static var _wound_mat: StandardMaterial3D
static var _cap_mesh: SphereMesh


static func wound_material() -> StandardMaterial3D:
	return _wound_material()


static func _wound_material() -> StandardMaterial3D:
	if _wound_mat == null:
		_wound_mat = StandardMaterial3D.new()
		_wound_mat.albedo_color = Color(0.32, 0.02, 0.02)
		_wound_mat.roughness = 0.25
		_wound_mat.metallic_specular = 0.8
	return _wound_mat


static func _limb_cap_mesh() -> SphereMesh:
	if _cap_mesh == null:
		_cap_mesh = SphereMesh.new()
		_cap_mesh.radius = 0.07
		_cap_mesh.height = 0.1
		_cap_mesh.radial_segments = 10
		_cap_mesh.rings = 5
	return _cap_mesh


func build(shirt: Color, pants: Color, skin: Color) -> void:
	var torso := _piece(Vector3(0.5, 0.65, 0.3), Vector3(0.0, 1.05, 0.0), shirt, 8.0)
	var head := _piece(Vector3(0.28, 0.28, 0.28), Vector3(0.0, 1.55, 0.0), skin, 3.0, true)
	var l_arm := _piece(Vector3(0.16, 0.6, 0.16), Vector3(-0.36, 1.05, 0.0), skin, 2.0)
	var r_arm := _piece(Vector3(0.16, 0.6, 0.16), Vector3(0.36, 1.05, 0.0), skin, 2.0)
	var l_leg := _piece(Vector3(0.2, 0.7, 0.2), Vector3(-0.14, 0.38, 0.0), pants, 4.0)
	var r_leg := _piece(Vector3(0.2, 0.7, 0.2), Vector3(0.14, 0.38, 0.0), pants, 4.0)
	_pin(torso, head, Vector3(0.0, 1.4, 0.0))
	_pin(torso, l_arm, Vector3(-0.3, 1.33, 0.0))
	_pin(torso, r_arm, Vector3(0.3, 1.33, 0.0))
	_pin(torso, l_leg, Vector3(-0.14, 0.72, 0.0))
	_pin(torso, r_leg, Vector3(0.14, 0.72, 0.0))


func _ready() -> void:
	set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)


func fling(impulse: Vector3) -> void:
	for b in bodies:
		b.apply_central_impulse(impulse * b.mass / TOTAL_MASS)
		b.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))


func _piece(size: Vector3, pos: Vector3, color: Color, piece_mass: float, round_head: bool = false) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 5 # world and props, not other characters
	body.mass = piece_mass
	body.position = pos
	var mesh := MeshInstance3D.new()
	if round_head:
		var sphere := SphereMesh.new()
		sphere.radius = size.x * 0.5
		sphere.height = size.x
		sphere.radial_segments = 8
		sphere.rings = 4
		mesh.mesh = sphere
	else:
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
	mesh.material_override = PropFactory.material(color, 0.8)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	add_child(body)
	bodies.append(body)
	return body


func _pin(a: RigidBody3D, b: RigidBody3D, at: Vector3) -> void:
	var joint := PinJoint3D.new()
	joint.position = at
	add_child(joint)
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)
