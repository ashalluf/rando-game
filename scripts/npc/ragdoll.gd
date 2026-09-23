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
	if _anim == null or bodies.is_empty():
		return
	_age += delta
	var body: RigidBody3D = bodies[0]
	# Stop flailing once it lies still.
	if _age > 0.8 and (body.sleeping or body.linear_velocity.length() < 0.7):
		_anim.pause()
		set_process(false)


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
		WeaponFX.blood(self, joint, (impulse.normalized() + Vector3.UP * 0.6).normalized(), 1.0)
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


## The piece of the character's skin that belongs to `limb`, as a static mesh in the model's
## own space, re-centred: [mesh, centre, size, joint end]. A triangle goes to the limb when all
## three corners are weighted mostly to its bones. Cut once per model and limb, then shared.
static func _limb_mesh(source: MeshInstance3D, skel: Skeleton3D, limb: String) -> Array:
	var key := "%s|%s|%s" % [source.mesh.resource_path, source.mesh.get_rid(), limb]
	if _limb_cache.has(key):
		return _limb_cache[key]
	var result: Array = []
	var arrays := source.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if verts.is_empty() or bones.is_empty() or index.is_empty() or source.skin == null:
		_limb_cache[key] = result
		return result
	var per := bones.size() / verts.size()
	var wanted := {}
	for bn: String in LIMBS[limb]:
		for i in source.skin.get_bind_count():
			if String(source.skin.get_bind_name(i)) == bn:
				wanted[i] = true
	var mine := PackedByteArray()
	mine.resize(verts.size())
	for v in verts.size():
		var best := 0
		var best_w := -1.0
		for k in per:
			var w := weights[v * per + k]
			if w > best_w:
				best_w = w
				best = bones[v * per + k]
		mine[v] = 1 if wanted.has(best) else 0
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
	var remap := {}
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_t := PackedFloat32Array()
	var out_uv := PackedVector2Array()
	var out_i := PackedInt32Array()
	for t in index.size() / 3:
		var a := index[t * 3]
		var b := index[t * 3 + 1]
		var c := index[t * 3 + 2]
		if mine[a] == 0 or mine[b] == 0 or mine[c] == 0:
			continue
		for v in [a, b, c]:
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
				if tangents.size() == verts.size() * 4:
					var tv := (basis * Vector3(tangents[v * 4], tangents[v * 4 + 1], tangents[v * 4 + 2])).normalized()
					out_t.append_array(PackedFloat32Array([tv.x, tv.y, tv.z, tangents[v * 4 + 3]]))
			out_i.append(remap[v])
	if out_i.size() < 30:
		_limb_cache[key] = result
		return result
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
	if out_t.size() == out_v.size() * 4:
		mesh_arrays[Mesh.ARRAY_TANGENT] = out_t
	mesh_arrays[Mesh.ARRAY_INDEX] = out_i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	# The torn end: the limb's root joint, in the re-centred space.
	var root_bone := skel.find_bone(LIMBS[limb][0])
	var joint := _rig_space_of_skel(skel) * skel.get_bone_global_rest(root_bone).origin - centre
	result = [mesh, centre, box.size, joint]
	_limb_cache[key] = result
	return result


## From a skinned mesh's vertex space (the skeleton's, in rest pose) to the model root's space.
static func _rig_space(_source: MeshInstance3D, skel: Skeleton3D) -> Transform3D:
	return _rig_space_of_skel(skel)


static func _rig_space_of_skel(skel: Skeleton3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = skel
	while n != null and n.get_parent() != null and not (n.get_parent() is Ragdoll) and not (n.get_parent() is RigidBody3D):
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static var _wound_mat: StandardMaterial3D
static var _cap_mesh: SphereMesh


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
