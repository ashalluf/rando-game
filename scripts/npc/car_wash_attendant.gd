class_name CarWashAttendant
extends StreetVendor
## A car wash's hand-dry crew member (RcCarWash, the car_wash refcam): a crowd rig in the crew's
## polo and dark work trousers (ApronCrew's garment split), a microfibre towel in the right hand,
## standing at their spot by a washed car - leaning over its roof on the crowd's rail clip, or at
## its tail. An ordinary pedestrian otherwise (shot, knocked, ragdolled; in the crowd cap); a scare
## sends them off and they walk back like a cart vendor (StreetVendor).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## The crew's polo (set before the attendant enters the tree).
var polo: Color = Color(0.08, 0.32, 0.62)
## Which of RcCarWash.TOWELS they hold.
var towel: int = 0
## The life clip they hold at their spot (CrowdLife.RAIL leaning over a roof, or IDLE).
var pose_clip: String = CrowdLife.IDLE

static var _mats: Dictionary = {}


func _init() -> void:
	# Nobody wears a cap or carries a pack at work (the crowd's roll is still made).
	accessory_chance = 0.0


func _add_model() -> bool:
	if not super._add_model():
		return false
	var inst: Node3D = null
	for c in _visual.get_children():
		if c is Node3D:
			inst = c
			break
	if inst == null:
		return true
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			var mat := crew_material(src.albedo_texture, polo)
			if mat:
				mi.material_override = mat
	_hold_towel()
	return true


## The model's own face, skin and hair, the top repainted the crew's polo, the trousers dark.
static func crew_material(albedo: Texture2D, top: Color) -> ShaderMaterial:
	var key := "%d_%s" % [albedo.get_instance_id(), top.to_html()]
	if _mats.has(key):
		return _mats[key]
	var base := character_material(albedo, 1)
	if base == null:
		return null
	var mat := base.duplicate() as ShaderMaterial
	mat.set_shader_parameter("cloth_hue", top.h)
	mat.set_shader_parameter("cloth_sat", top.s)
	mat.set_shader_parameter("cloth_value", top.v)
	mat.set_shader_parameter("cloth_strength", 0.95)
	mat.set_shader_parameter("pants_hue", ApronCrew.TROUSERS.h)
	mat.set_shader_parameter("pants_sat", ApronCrew.TROUSERS.s)
	mat.set_shader_parameter("pants_value", ApronCrew.TROUSERS.v)
	mat.set_shader_parameter("pants_strength", 0.95)
	mat.set_shader_parameter("cloth_roughness", 0.75)
	mat.set_shader_parameter("cloth_shade_keep", 0.7)
	_mats[key] = mat
	return mat


## The towel in the right hand, hanging plumb whatever the clip does with the wrist.
func _hold_towel() -> void:
	if _head_skel == null:
		var found := _visual.find_children("*", "Skeleton3D", true, false)
		if found.is_empty():
			return
		_head_skel = found[0]
	if _head_skel.find_bone("RightHand") < 0:
		return
	var att := BoneAttachment3D.new()
	_head_skel.add_child(att)
	att.bone_name = "RightHand"
	var hang := Plumb.new()
	hang.name = "Towel"
	att.add_child(hang)
	var mi := MeshInstance3D.new()
	mi.mesh = RcCarWash.towel_mesh(towel)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = 70.0
	hang.add_child(mi)


## At the car: the pose clip held for good.
func _work(at_once: bool) -> void:
	super(at_once)
	if _life_ok:
		_life_base = pose_clip
		_life_clip = pose_clip


func _do_act(delta: float) -> void:
	var base := _life_base
	super(delta)
	# StreetVendor turns to customers and swaps idles; the crew keep to their job.
	if _stage == Stage.DOING and _life_ok and base == pose_clip:
		_life_base = pose_clip
		if _one_shot_left <= 0.0:
			_life_clip = pose_clip


## Keeps its node level and at world scale (the hand bone turns and the rig is scaled 0.01).
class Plumb extends Node3D:
	func _ready() -> void:
		top_level = true
		_follow()

	func _process(_delta: float) -> void:
		_follow()

	func _follow() -> void:
		var p := get_parent() as Node3D
		if p == null or not p.is_inside_tree():
			return
		var g := p.global_transform
		var fwd := g.basis.z
		fwd.y = 0.0
		var yaw := atan2(fwd.x, fwd.z) if fwd.length_squared() > 1e-6 else 0.0
		global_transform = Transform3D(Basis(Vector3.UP, yaw), g.origin)
