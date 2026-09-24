class_name RoughSleeper
extends Pedestrian
## Someone living on the pavement at a downtown encampment (scripts/world/encampment.gd). Not a
## walker: they hold a pose at their spot - sitting against the wall, lying on their bedding, or
## standing bent far forward at the waist in a deep slump - breathing, the slumped ones swaying a
## little. A Pedestrian all the same, so they are in the crowd (the "pedestrian" group: they count
## against the crowd cap, they hear gunfire, they witness crimes for the police), and a bullet, a
## car or a blast knocks them into the same ragdoll as anyone, and they bleed the same way.
##
## Reactions: gunfire or a blast nearby sends someone sitting or lying up onto their feet and off
## down the pavement like anyone else, and they walk back to their spot and settle again when it
## is over; someone standing in a slump does not run - they cower where they stand.
##
## The rigs only carry idle, walk and run clips, so the poses are written straight into the
## skeleton as bone rotations (a pose override): the idle clip is posed once and never advanced
## again while they are still, so nothing overwrites the pose. Each pose is a table of directions
## for each bone's segment in the rig's own space (+Y up, +Z forward, +X the rig's left), and the
## rotation that swings the idle pose's segment onto it is worked out per rig, so the same table
## poses all nine models whatever pose their mesh was bound in (the lesson of fix_arm_pose()).
## Their clothes go through the character shader as worn, dirty versions of the crowd's looks
## (worn_material()).

enum Pose { SIT, LIE, SLUMP }
enum State { POSED, COWER, FLEE, RETURN }

@export_group("Rough sleeper")
## Seconds per breath at rest, and how far the chest rises (degrees of spine pitch).
@export var breath_period: float = 4.6
@export var breath_depth: float = 1.6
## The slumped sway: its period (seconds) and reach (degrees).
@export var sway_period: float = 6.5
@export var sway_depth: float = 3.5
## Seconds to blend between the pose and the clip when getting up or settling again.
@export var blend_seconds: float = 0.45
## Past this distance (m) from the player the pose is left as it is: no breathing, no sway.
@export var breathe_range: float = 45.0

var pose: int = Pose.SIT
## Metres the pose sits above the pavement (a mattress, flattened boxes).
var lift: float = 0.0
## Sitting pose variant: knees up (0) or legs out (1).
var variant: int = 0
var _state: int = State.POSED
## Where the pose stands (the chunk's space, XZ) and which way the body faces (the visual's yaw).
var _home := Vector2.ZERO
var _home_yaw: float = 0.0
var _skel: Skeleton3D
var _order: PackedInt32Array = PackedInt32Array()
var _base_rot: Array[Quaternion] = []
var _base_pos: Array[Vector3] = []
var _posed_rot: Array[Quaternion] = []
var _posed_hips := Vector3.ZERO
var _cower_rot: Array[Quaternion] = []
var _cower_hips := Vector3.ZERO
var _hips: int = -1
var _weight: float = 1.0
var _cower_w: float = 0.0
var _clock: float = 0.0
var _phase: float = 0.0
var _breath_bones: PackedInt32Array = PackedInt32Array()
static var _worn: Dictionary = {}

## Each bone's segment direction for a pose (rig space; a Right bone with no entry of its own is
## its Left twin mirrored). "hips_pitch" tips the pelvis (degrees, + forward); "hips_y" / "hips_x"
## put the hip joint where a seated or lying body has it (cm, rig space); a "stand" pose instead
## moves the hips until the feet are back where they stood; "keep" lists bones that keep the idle
## pose's orientation in rig space (feet flat on the pavement); "roll" lays the whole body over
## (degrees about the forward axis: 90 is on its right side, head toward the rig's right).
const POSES := {
	"sit_knees": {
		"hips_pitch": -16.0, "hips_y": 13.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.94, -0.34), "Spine01": Vector3(0.0, 0.97, -0.20),
			"Spine": Vector3(0.0, 0.99, 0.08), "neck": Vector3(0.0, 0.84, 0.54),
			"Head": Vector3(0.0, 0.58, 0.82),
			"LeftUpLeg": Vector3(0.14, 0.62, 0.77), "LeftLeg": Vector3(0.03, -0.76, 0.65),
			"LeftArm": Vector3(0.10, -0.62, 0.78), "LeftForeArm": Vector3(-0.36, -0.12, 0.93),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	"sit_legs": {
		"hips_pitch": -12.0, "hips_y": 12.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.93, -0.36), "Spine01": Vector3(0.0, 0.96, -0.25),
			"Spine": Vector3(0.0, 0.98, 0.0), "neck": Vector3(0.0, 0.9, 0.44),
			"Head": Vector3(0.0, 0.72, 0.69),
			"LeftUpLeg": Vector3(0.12, -0.05, 0.99), "LeftLeg": Vector3(0.10, -0.12, 0.99),
			"LeftFoot": Vector3(0.18, 0.62, 0.76),
			"LeftArm": Vector3(0.12, -0.84, 0.52), "LeftForeArm": Vector3(-0.42, -0.36, 0.83),
		},
		"keep": [],
	},
	"lie": {
		"hips_pitch": 8.0, "hips_y": 25.0, "roll": 90.0, "hips_x": 22.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.97, 0.24), "Spine01": Vector3(0.0, 0.93, 0.36),
			"Spine": Vector3(0.0, 0.90, 0.43), "neck": Vector3(0.0, 0.82, 0.57),
			"Head": Vector3(0.0, 0.86, 0.51),
			"LeftUpLeg": Vector3(0.05, -0.34, 0.94), "LeftLeg": Vector3(0.02, -0.92, -0.40),
			"LeftFoot": Vector3(0.0, -0.45, 0.89),
			"LeftArm": Vector3(-0.22, -0.30, 0.93), "LeftForeArm": Vector3(-0.55, 0.55, 0.63),
			"RightArm": Vector3(-0.30, -0.55, 0.78), "RightForeArm": Vector3(0.20, 0.35, 0.92),
			"RightUpLeg": Vector3(-0.05, -0.26, 0.96), "RightLeg": Vector3(-0.02, -0.80, -0.60),
		},
		"keep": [],
	},
	"slump": {
		"hips_pitch": 26.0, "stand": true,
		"aim": {
			"Spine02": Vector3(0.0, 0.46, 0.89), "Spine01": Vector3(0.0, 0.06, 1.0),
			"Spine": Vector3(0.0, -0.28, 0.96), "neck": Vector3(0.0, -0.66, 0.75),
			"Head": Vector3(0.0, -0.93, 0.37),
			"LeftUpLeg": Vector3(0.05, -0.92, 0.39), "LeftLeg": Vector3(0.0, -0.95, -0.31),
			"LeftArm": Vector3(0.06, -1.0, 0.06), "LeftForeArm": Vector3(0.02, -1.0, 0.10),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	"cower": {
		"hips_pitch": 22.0, "stand": true,
		"aim": {
			"Spine02": Vector3(0.0, 0.62, 0.78), "Spine01": Vector3(0.0, 0.42, 0.91),
			"Spine": Vector3(0.0, 0.22, 0.97), "neck": Vector3(0.0, -0.2, 0.98),
			"Head": Vector3(0.0, -0.55, 0.83),
			"LeftUpLeg": Vector3(0.16, 0.08, 0.98), "LeftLeg": Vector3(0.03, -0.95, -0.31),
			"LeftArm": Vector3(0.18, 0.58, 0.80), "LeftForeArm": Vector3(-0.80, 0.36, 0.48),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
}
## Which child a bone's segment points at.
const AIM_CHILD := {
	"Spine02": "Spine01", "Spine01": "Spine", "Spine": "neck", "neck": "Head", "Head": "head_end",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase",
	"LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand",
	"RightArm": "RightForeArm", "RightForeArm": "RightHand",
}


func setup_sleeper(block_rect: Rect2, sidewalk: float, seed_value: int, pose_kind: int, home: Vector2, yaw: float) -> void:
	setup(block_rect, sidewalk, seed_value)
	pose = pose_kind
	variant = absi(seed_value) % 2
	_home = home
	_home_yaw = yaw
	_phase = float(absi(seed_value) % 1000) * 0.0073


func _ready() -> void:
	super._ready()
	_visual.rotation = Vector3(0.0, _home_yaw, 0.0)
	_skel = _visual.find_child("Skeleton3D", true, false) as Skeleton3D
	for mi in _meshes:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			mi.material_override = worn_material(src.albedo_texture, _look)
	_fit_shape()
	if _skel == null or _anim == null:
		return
	# The idle clip, posed once at a fixed moment, is the base every pose is worked from.
	if _anim.has_animation(IDLE_CLIP):
		_anim.play(IDLE_CLIP, 0.0)
		_anim.seek(0.6, true)
	var n := _skel.get_bone_count()
	_base_rot.resize(n)
	_base_pos.resize(n)
	for b in n:
		_base_rot[b] = _skel.get_bone_pose_rotation(b)
		_base_pos[b] = _skel.get_bone_pose_position(b)
	_order = _bone_order(_skel)
	_hips = _skel.find_bone("Hips")
	for bone_name: String in ["Spine01", "Spine", "neck"]:
		var bi := _skel.find_bone(bone_name)
		if bi >= 0:
			_breath_bones.append(bi)
	var key := "sit_knees" if pose == Pose.SIT and variant == 0 else ("sit_legs" if pose == Pose.SIT else ("lie" if pose == Pose.LIE else "slump"))
	var p := _solve(POSES[key])
	_posed_rot = p[0]
	_posed_hips = p[1]
	if pose == Pose.SLUMP:
		var c := _solve(POSES["cower"])
		_cower_rot = c[0]
		_cower_hips = c[1]
	_apply(1.0)


## Bones parents first.
static func _bone_order(skel: Skeleton3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	var done := {}
	var n := skel.get_bone_count()
	while out.size() < n:
		var added := false
		for b in n:
			if done.has(b):
				continue
			var p := skel.get_bone_parent(b)
			if p < 0 or done.has(p):
				out.append(b)
				done[b] = true
				added = true
		if not added:
			break
	return out


## The bone rotations (local) and the hip position for one pose table, from the idle base.
func _solve(spec: Dictionary) -> Array:
	var n := _skel.get_bone_count()
	var local: Array[Quaternion] = _base_rot.duplicate()
	var glob: Array[Transform3D] = []
	glob.resize(n)
	var base_glob: Array[Transform3D] = []
	base_glob.resize(n)
	var aims: Dictionary = spec.aim
	var keep: Array = spec.get("keep", [])
	for b in _order:
		var p := _skel.get_bone_parent(b)
		var bl := Transform3D(Basis(_base_rot[b]), _base_pos[b])
		base_glob[b] = base_glob[p] * bl if p >= 0 else bl
		var g := glob[p] * bl if p >= 0 else bl
		var bone_name := _skel.get_bone_name(b)
		if b == _hips:
			g.basis = Basis(Vector3.RIGHT, deg_to_rad(float(spec.get("hips_pitch", 0.0)))) * g.basis
		var aim: Variant = aims.get(bone_name)
		if aim == null and bone_name.begins_with("Right"):
			var mirror: Variant = aims.get("Left" + bone_name.trim_prefix("Right"))
			if mirror != null:
				aim = Vector3(-(mirror as Vector3).x, (mirror as Vector3).y, (mirror as Vector3).z)
		if aim != null and AIM_CHILD.has(bone_name):
			var c := _skel.find_bone(AIM_CHILD[bone_name])
			if c >= 0:
				var cur := (g.basis * _base_pos[c]).normalized()
				var want := (aim as Vector3).normalized()
				if cur.length() > 0.5 and absf(cur.dot(want)) < 0.9999:
					g.basis = Basis(Quaternion(cur, want)) * g.basis
		elif keep.has(bone_name):
			g.basis = base_glob[b].basis
		glob[b] = g
		local[b] = ((glob[p].basis.inverse() * g.basis) if p >= 0 else g.basis).get_rotation_quaternion()
	var hips := _base_pos[_hips] if _hips >= 0 else Vector3.ZERO
	if spec.get("stand", false):
		# Feet back on the pavement where they stood, however the legs are now bent.
		var drop := 0.0
		var shift := Vector2.ZERO
		var count := 0
		for foot: String in ["LeftFoot", "RightFoot"]:
			var f := _skel.find_bone(foot)
			if f >= 0:
				drop += base_glob[f].origin.y - glob[f].origin.y
				shift += Vector2(base_glob[f].origin.x - glob[f].origin.x, base_glob[f].origin.z - glob[f].origin.z)
				count += 1
		if count > 0:
			drop /= count
			shift /= count
		hips += Vector3(shift.x, drop, shift.y)
	else:
		hips.y = float(spec.get("hips_y", hips.y))
		hips.x += float(spec.get("hips_x", 0.0))
	if spec.has("roll") and _hips >= 0:
		local[_hips] = (Quaternion(Vector3.BACK, deg_to_rad(float(spec.roll))) * local[_hips]).normalized()
	return [local, hips]


## The pose at weight `w` over the clip's pose, and the cower mixed in for a slumped one.
func _apply(w: float) -> void:
	if _skel == null or _posed_rot.is_empty():
		return
	var n := mini(_skel.get_bone_count(), _posed_rot.size())
	var clip := _weight < 1.0 or _state == State.FLEE or _state == State.RETURN
	for b in n:
		var target := _posed_rot[b]
		if _cower_w > 0.0 and not _cower_rot.is_empty():
			target = target.slerp(_cower_rot[b], _cower_w)
		if w >= 0.999 and not clip:
			_skel.set_bone_pose_rotation(b, target)
		else:
			_skel.set_bone_pose_rotation(b, _skel.get_bone_pose_rotation(b).slerp(target, w))
	if _hips >= 0:
		var hp := _posed_hips.lerp(_cower_hips, _cower_w) if _cower_w > 0.0 else _posed_hips
		if w >= 0.999 and not clip:
			_skel.set_bone_pose_position(_hips, hp)
		else:
			_skel.set_bone_pose_position(_hips, _skel.get_bone_pose_position(_hips).lerp(hp, w))


## The collision capsule shaped to the pose: short and forward for a sitter, laid along the body
## for someone lying down, bent forward for a slump. Bullets and blasts find them by it.
func _fit_shape() -> void:
	for c in get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is CapsuleShape3D):
			continue
		var cap := CapsuleShape3D.new()
		cap.radius = 0.32
		var fwd := Vector3(-sin(_home_yaw), 0.0, -cos(_home_yaw))
		match pose:
			Pose.SIT:
				cap.height = 1.05
				cs.position = Vector3(0.0, 0.52, 0.0) + fwd * 0.18
				cs.rotation = Vector3.ZERO
			Pose.LIE:
				cap.radius = 0.28
				cap.height = 1.7
				cs.position = Vector3(0.0, 0.3, 0.0) - fwd * 0.05
				# Laid along the body, which lies across the rig's left-right axis.
				cs.rotation = Vector3(0.0, _home_yaw, PI * 0.5)
			_:
				cap.height = 1.5
				cs.position = Vector3(0.0, 0.75, 0.0) + fwd * 0.2
				cs.rotation = Vector3.ZERO
		cs.shape = cap
		break


func _physics_process(delta: float) -> void:
	if _down:
		return
	match _state:
		State.FLEE:
			super._physics_process(delta)
			_blend_toward(0.0, delta)
			if _panic_left <= 0.0:
				_state = State.RETURN
				_target = _home
			return
		State.RETURN:
			var here := Vector2(global_position.x, global_position.z)
			if here.distance_to(_home) < 1.2:
				_settle()
				return
			_target = _home
			super._physics_process(delta)
			return
	_lod_timer += delta
	if _lod_timer >= 0.5:
		_lod_timer = 0.0
		_update_lod()
	_clock += delta
	if _state == State.COWER:
		_panic_left -= delta
		_cower_w = move_toward(_cower_w, 1.0, delta * 3.0)
		if _panic_left <= 0.0:
			_state = State.POSED
	else:
		_cower_w = move_toward(_cower_w, 0.0, delta * 0.8)
	var near := _player == null or not is_instance_valid(_player) or global_position.distance_to(_player.global_position) < breathe_range
	if _cower_w > 0.0:
		_apply(1.0)
	if near and _skel:
		_breathe()


## Breathing (and a slumped one's sway), written over the pose on the spine and neck only.
func _breathe() -> void:
	if _posed_rot.is_empty():
		return
	var t := _clock + _phase * 10.0
	var breath := sin(TAU * t / breath_period) * deg_to_rad(breath_depth)
	var sway := 0.0
	var roll := 0.0
	if pose == Pose.SLUMP and _cower_w < 0.5:
		sway = sin(TAU * t / sway_period) * deg_to_rad(sway_depth)
		roll = sin(TAU * t / (sway_period * 1.7) + 1.3) * deg_to_rad(sway_depth * 0.5)
	for i in _breath_bones.size():
		var b := _breath_bones[i]
		var base := _posed_rot[b]
		if _cower_w > 0.0 and not _cower_rot.is_empty():
			base = base.slerp(_cower_rot[b], _cower_w)
		var k := 1.0 - 0.35 * i
		_skel.set_bone_pose_rotation(b, (base * Quaternion(Vector3.RIGHT, -breath * k)).normalized())
	if (sway != 0.0 or roll != 0.0) and _hips >= 0:
		var s02 := _skel.find_bone("Spine02")
		if s02 >= 0:
			_skel.set_bone_pose_rotation(s02, (_posed_rot[s02] * Quaternion(Vector3.RIGHT, sway) * Quaternion(Vector3.BACK, roll)).normalized())


func _blend_toward(target: float, delta: float) -> void:
	_weight = move_toward(_weight, target, delta / maxf(blend_seconds, 0.01))
	if _weight > 0.001:
		_apply(_weight)


## Back at the spot: stop, face the way they were, and take the pose again.
func _settle() -> void:
	_state = State.POSED
	velocity = Vector3.ZERO
	position = Vector3(_home.x, _pose_ground(), _home.y)
	_visual.rotation = Vector3(0.0, _home_yaw, 0.0)
	if _anim and _anim.has_animation(IDLE_CLIP):
		_anim.play(IDLE_CLIP, 0.0)
		_anim.seek(0.6, true)
	_weight = 1.0
	_apply(1.0)


## The pavement height at the spot (the chunk's own ground, like a walker's).
func _pose_ground() -> float:
	var chunk := get_parent()
	if chunk and chunk.has_method("ground_y"):
		return chunk.ground_y(_home.x, _home.y) + lift
	return position.y


## Gunfire or a blast: up and away (sitting, lying), or cower where they stand (slumped).
func _scare(at: Vector3) -> void:
	if _down:
		return
	if pose == Pose.SLUMP:
		_state = State.COWER
		_panic_left = _rng.randf_range(panic_seconds.x, panic_seconds.y)
		_threat = Vector2(at.x, at.z)
		return
	if _state == State.POSED or _state == State.RETURN:
		_state = State.FLEE
	super._scare(at)
	# Up off the pavement: the clip takes over as the pose lets go (_blend_toward).
	_visual.rotation.x = 0.0


## True while they hold their pose at their spot (the smoke test reads it).
func is_posed() -> bool:
	return _state == State.POSED or _state == State.COWER


func knock(impulse: Vector3, gibs: int = 0) -> void:
	if _down:
		return
	var parent := get_parent()
	var before := parent.get_child_count() if parent else 0
	super.knock(impulse, gibs)
	if parent == null:
		return
	for i in range(before, parent.get_child_count()):
		var doll := parent.get_child(i) as Ragdoll
		if doll and doll._rig:
			for node in doll._rig.find_children("*", "MeshInstance3D", true, false):
				var mi := node as MeshInstance3D
				var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh else null
				if src and src.albedo_texture and mi.skin:
					mi.material_override = worn_material(src.albedo_texture, _look)


## A crowd look worn down by months outdoors: the garments muted to greys, browns and faded
## darks, grime through the cloth (heaviest at the cuffs, the knees and the seat), rougher. The
## person's own face, skin and hair are left exactly as they are.
static func worn_material(albedo: Texture2D, look: int) -> ShaderMaterial:
	var key := "%d_%d" % [albedo.get_instance_id(), look]
	if _worn.has(key):
		return _worn[key]
	var base := character_material(albedo, look)
	if base == null:
		return null
	var mat := base.duplicate() as ShaderMaterial
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + look
	mat.set_shader_parameter("cloth_hue", rng.randf_range(0.05, 0.16) if rng.randf() < 0.6 else rng.randf_range(0.5, 0.65))
	mat.set_shader_parameter("cloth_sat", rng.randf_range(0.06, 0.26))
	mat.set_shader_parameter("cloth_value", rng.randf_range(0.14, 0.42))
	mat.set_shader_parameter("cloth_strength", rng.randf_range(0.75, 0.9))
	mat.set_shader_parameter("pants_hue", rng.randf_range(0.55, 0.66) if rng.randf() < 0.5 else rng.randf_range(0.06, 0.14))
	mat.set_shader_parameter("pants_sat", rng.randf_range(0.05, 0.22))
	mat.set_shader_parameter("pants_value", rng.randf_range(0.10, 0.30))
	mat.set_shader_parameter("pants_strength", rng.randf_range(0.8, 0.92))
	mat.set_shader_parameter("hair_strength", 0.0)
	mat.set_shader_parameter("cloth_roughness", 0.96)
	mat.set_shader_parameter("cloth_shade_keep", 1.0)
	mat.set_shader_parameter("grime", rng.randf_range(0.55, 0.85))
	_worn[key] = mat
	return mat
