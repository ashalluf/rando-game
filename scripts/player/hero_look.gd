class_name HeroLook
extends RefCounted
## Dresses the Blender-built hero (assets/models/hero.glb, tools/hero/) for the game: swaps his
## glTF materials for the hero shaders by name, points the shadow pass at his light twin, and
## every frame turns the skeleton's elbow and knee angles into the tracksuit's wrinkle weights.
##
##   hero_skin         -> shaders/hero_skin.gdshader  (pores, stubble, subsurface, T-zone oil)
##   hero_hair         -> shaders/hero_hair.gdshader  (dithered cut, anisotropic shine)
##   hero_brows        -> the hair shader on the brow texture
##   hero_tracksuit    -> shaders/hero_cloth.gdshader (pose-driven folds, velour pile and sheen)
##   hero_tracksuit_rib-> the cloth shader, no wrinkles
##   hero_eyes, hero_dial -> the glTF material plus a clearcoat: the wet eye, the watch glass
## The hero_x_* maps the shaders need are not in the glTF; they sit next to it.

const SKIN := preload("res://shaders/hero_skin.gdshader")
const HAIR := preload("res://shaders/hero_hair.gdshader")
const CLOTH := preload("res://shaders/hero_cloth.gdshader")
const MAPS := "res://assets/models/hero_x_%s"
## Elbow and knee angles (degrees of bend) at which the closed-joint folds start and are full.
const ELBOW_BEND := Vector2(35.0, 115.0)
const KNEE_BEND := Vector2(15.0, 95.0)

var cloth: ShaderMaterial
var skin: ShaderMaterial
var hair: ShaderMaterial
var shadow_twin: MeshInstance3D
var _joints: Array = [] # [upper, middle, end] bone triples: L elbow, R elbow, L knee, R knee
var _skeleton: Skeleton3D


## Dresses `inst` (the instantiated hero.glb) and returns the look, or null when this is not the
## hero (no hero_skin material anywhere).
static func dress(inst: Node3D, settings: Dictionary = {}) -> HeroLook:
	var look := HeroLook.new()
	var found := false
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		if mi.name.begins_with("hero_shadow"):
			look.shadow_twin = mi
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null:
				continue
			var mat := look._material_for(src, settings)
			if mat:
				mi.set_surface_override_material(i, mat)
				found = true
	if not found:
		return null
	if look.shadow_twin:
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			if node != look.shadow_twin:
				(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	look._skeleton = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if look._skeleton:
		# Read the pose when the skeleton has finished it: the arm IK and the hands only exist
		# in the final pose, and get_bone_global_pose() anywhere else returns the clip's.
		look._skeleton.skeleton_updated.connect(look.update)
		for chain in [["LeftArm", "LeftForeArm", "LeftHand"], ["RightArm", "RightForeArm", "RightHand"],
				["LeftUpLeg", "LeftLeg", "LeftFoot"], ["RightUpLeg", "RightLeg", "RightFoot"]]:
			look._joints.append([look._skeleton.find_bone(chain[0]), look._skeleton.find_bone(chain[1]), look._skeleton.find_bone(chain[2])])
	return look


func _material_for(src: StandardMaterial3D, s: Dictionary) -> Material:
	match src.resource_name:
		"hero_skin":
			skin = ShaderMaterial.new()
			skin.shader = SKIN
			skin.set_shader_parameter("albedo_tex", src.albedo_texture)
			skin.set_shader_parameter("normal_tex", src.normal_texture)
			skin.set_shader_parameter("rough_tex", src.roughness_texture)
			skin.set_shader_parameter("mask_tex", _map("skin_mask.png"))
			skin.set_shader_parameter("detail_tex", _map("skin_detail.png"))
			skin.set_shader_parameter("sss_strength", s.get("skin_sss", 0.4))
			skin.set_shader_parameter("stubble_amount", s.get("stubble", 0.9))
			skin.set_shader_parameter("detail_strength", s.get("pores", 0.6))
			return skin
		"hero_hair", "hero_brows":
			var m := ShaderMaterial.new()
			m.shader = HAIR
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
			m.set_shader_parameter("anisotropy", s.get("hair_anisotropy", 0.8))
			if src.resource_name == "hero_brows":
				m.set_shader_parameter("strands_from_texture", 1.0)
				m.set_shader_parameter("specular", 0.2)
				m.set_shader_parameter("anisotropy", 0.0)
			else:
				hair = m
			return m
		"hero_tracksuit", "hero_tracksuit_rib":
			var m := ShaderMaterial.new()
			m.shader = CLOTH
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
			m.set_shader_parameter("albedo_color", src.albedo_color)
			m.set_shader_parameter("normal_tex", src.normal_texture)
			m.set_shader_parameter("pile_tex", _map("pile.png"))
			m.set_shader_parameter("sheen", s.get("velour_sheen", 0.55))
			m.set_shader_parameter("rim", s.get("velour_rim", 0.45))
			if src.resource_name == "hero_tracksuit":
				m.set_shader_parameter("bent_tex", _map("suit_bent_normal.jpg"))
				m.set_shader_parameter("wrinkle_mask", _map("suit_wrinkle_mask.png"))
				cloth = m
			else:
				m.set_shader_parameter("use_wrinkles", false)
				m.set_shader_parameter("pile_scale", 60.0)
				m.set_shader_parameter("pile_strength", 0.15)
			return m
		"hero_eyes", "hero_dial":
			var m := src.duplicate() as StandardMaterial3D
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.02
			m.metallic = 0.0
			if src.resource_name == "hero_eyes":
				m.roughness = 0.3
			return m
		"hero_gold", "hero_zipper":
			var m := src.duplicate() as StandardMaterial3D
			m.metallic = 1.0
			m.metallic_specular = 0.7
			return m
	return null


func _map(name: String) -> Texture2D:
	var path := MAPS % name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## The closed-joint folds: 0 with the elbows and knees straight, 1 at a full bend. Runs on the
## skeleton's skeleton_updated signal, once the IK has placed the arms.
func update() -> void:
	if cloth == null or _skeleton == null or _joints.size() < 4:
		return
	var w := Vector4.ZERO
	for i in 4:
		var j: Array = _joints[i]
		if j[0] < 0 or j[1] < 0 or j[2] < 0:
			continue
		var a := _skeleton.get_bone_global_pose(j[0]).origin
		var b := _skeleton.get_bone_global_pose(j[1]).origin
		var c := _skeleton.get_bone_global_pose(j[2]).origin
		var bend := rad_to_deg((b - a).angle_to(c - b))
		var r: Vector2 = ELBOW_BEND if i < 2 else KNEE_BEND
		w[i] = smoothstep(r.x, r.y, bend)
	cloth.set_shader_parameter("wrinkle_weights", w)
