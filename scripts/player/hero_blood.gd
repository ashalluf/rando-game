class_name HeroBlood
extends RefCounted
## Blood spattered on the hero when he is close to a wound (blood-gore-2, BloodGore's header):
## every wound WeaponFX bleeds within `REACH` of his chest throws a spatter onto the side of him
## that faced it - denser and wider the closer and the heavier the wound - which rides the bone
## it landed on (shaders/blood_spatter.gdshaderinc on his skin and tracksuit), dries over
## DRY_SECONDS, and is gone after CLEAN_SECONDS or washed off by rain, and when he respawns.
## One per hero, made by HeroLook.dress(). BLOOD_GORE_2=0: never made.

## Metres from his chest a wound spatters him (a rifle round; a heavier wound reaches further).
const REACH := 2.8
## Most spatters he carries; a new one past this replaces the oldest.
const MAX_SPATS := 6
## Seconds the blood takes to dry, and to be gone.
const DRY_SECONDS := 70.0
const CLEAN_SECONDS := 240.0

## The live hero's (the player's avatar); null with none.
static var current: HeroBlood

var _skel: Skeleton3D
var _mats: Array[ShaderMaterial] = []
## {bone, local (bone space, skeleton units), radius (skeleton units), dir (bone space), density}
var spats: Array = []
var _age: float = 0.0
## Spatters thrown since start (tests).
static var thrown: int = 0


static func attach(skel: Skeleton3D, mats: Array) -> HeroBlood:
	if not BloodGore.enabled() or skel == null:
		return null
	var hb := HeroBlood.new()
	hb._skel = skel
	for m in mats:
		if m is ShaderMaterial:
			hb._mats.append(m)
	skel.skeleton_updated.connect(hb._update)
	skel.tree_exiting.connect(func() -> void:
		if current == hb:
			current = null)
	current = hb
	return hb


## A wound at `at` (true local space) bleeding along `dir` with `strength` (WeaponFX._bleed).
static func splash(at: Vector3, dir: Vector3, strength: float) -> void:
	if current == null or not BloodGore.enabled():
		return
	current._splash(at, dir, strength)


func _splash(at: Vector3, dir: Vector3, strength: float) -> void:
	if not is_instance_valid(_skel) or not _skel.is_inside_tree() or not _skel.is_visible_in_tree():
		return
	var chest := _bone_world("Spine2", "Spine1")
	var dist := chest.distance_to(at)
	var reach := REACH * sqrt(clampf(strength, 0.3, 4.0))
	if dist > reach or dist < 0.05:
		return
	var close := pow(1.0 - dist / reach, 1.2)
	# Where on him it lands: the near side of his body, high or low as the wound was.
	var toward := (at - chest)
	var flat := Vector3(toward.x, 0.0, toward.z)
	if flat.length() < 0.05:
		flat = Vector3.FORWARD
	var up := clampf(toward.y, -0.7, 0.45)
	var hit := chest + flat.normalized() * 0.16 + Vector3.UP * up * 0.8
	var travel := (chest - at).normalized()
	var sp := _skel.global_transform.affine_inverse() * hit
	var bone := _nearest_bone(_skel, sp)
	if bone < 0:
		return
	var pose := _skel.get_bone_global_pose(bone)
	var unit := 1.0 / maxf(_skel.global_basis.get_scale().x, 0.0001)
	var dir_s := (_skel.global_basis.inverse() * travel).normalized()
	var s := {
		"bone": bone,
		"local": pose.affine_inverse() * sp,
		"radius": (0.12 + 0.3 * close) * sqrt(clampf(strength, 0.5, 4.0)) * unit,
		"dir": (pose.basis.inverse() * dir_s).normalized(),
		"density": clampf(0.35 + 0.75 * close, 0.0, 1.0),
	}
	if spats.size() >= MAX_SPATS:
		spats.pop_front()
	spats.append(s)
	_age = 0.0
	thrown += 1


func clear() -> void:
	spats.clear()
	_push()


func _update() -> void:
	if spats.is_empty():
		return
	var dt := _skel.get_process_delta_time() if _skel.is_inside_tree() else 0.0
	_age += dt
	# Rain washes it off over half a minute; otherwise it dries, then is gone.
	var rain := clampf(float(RenderingServer.global_shader_parameter_get("rain_intensity")) if _has_rain() else 0.0, 0.0, 1.0)
	_age += dt * rain * (CLEAN_SECONDS / 30.0)
	if _age > CLEAN_SECONDS:
		clear()
		return
	_push()


static var _rain_known: int = -1


static func _has_rain() -> bool:
	if _rain_known < 0:
		_rain_known = 1 if RenderingServer.global_shader_parameter_get_list().has(&"rain_intensity") else 0
	return _rain_known == 1


func _push() -> void:
	var p := PackedVector4Array()
	var d := PackedVector4Array()
	p.resize(MAX_SPATS)
	d.resize(MAX_SPATS)
	for i in spats.size():
		var s: Dictionary = spats[i]
		var pose := _skel.get_bone_global_pose(int(s.bone))
		var at: Vector3 = pose * (s.local as Vector3)
		var dir: Vector3 = pose.basis * (s.dir as Vector3)
		p[i] = Vector4(at.x, at.y, at.z, float(s.radius))
		d[i] = Vector4(dir.x, dir.y, dir.z, float(s.density))
	var unit := 1.0 / maxf(_skel.global_basis.get_scale().x, 0.0001)
	for m in _mats:
		m.set_shader_parameter("spat_count", float(spats.size()))
		m.set_shader_parameter("spat_p", p)
		m.set_shader_parameter("spat_d", d)
		m.set_shader_parameter("spat_unit", unit)
		m.set_shader_parameter("spat_dry", smoothstep(0.0, DRY_SECONDS, _age))


func _bone_world(name: String, fallback: String) -> Vector3:
	var b := _skel.find_bone(name)
	if b < 0:
		b = _skel.find_bone(fallback)
	if b < 0:
		return _skel.global_position + Vector3.UP * 1.3
	return _skel.global_transform * _skel.get_bone_global_pose(b).origin


## The bone whose segment passes nearest `sp` (skeleton space); Ragdoll's rule, kept here so this
## file names no NPC class.
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
