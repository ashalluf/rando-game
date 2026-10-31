class_name HeroLook
extends RefCounted
## Dresses the Blender-built hero (assets/models/hero.glb, tools/hero/) for the game: swaps his
## glTF materials for the hero shaders by name, points the shadow pass at his light twin, and
## every frame turns the skeleton's elbow and knee angles into the tracksuit's wrinkle weights.
##
##   hero_skin         -> shaders/hero_skin.gdshader  (pores, stubble, subsurface, T-zone oil)
##   hero_hair         -> shaders/hero_hair.gdshader  (dithered cut, strand light; a blended fringe
##                        pass, hero_hair_fringe, as its next_pass - hero-closeup-2)
##   hero_brows        -> the hair shader on the brow texture (a dark brown, the fringe for the tips)
##   hero_tracksuit    -> shaders/hero_cloth.gdshader (pose-driven folds, velour pile and sheen)
##   hero_tracksuit_rib-> the cloth shader, no wrinkles
##   hero_eyes, hero_dial -> the glTF material plus a clearcoat: the wet eye, the watch glass
## The hero_x_* maps the shaders need are not in the glTF; they sit next to it (hero_x_skin_region
## is the face's pore size, redness and cartilage, hero-face-2).

const SKIN := preload("res://shaders/hero_skin.gdshader")
const HAIR := preload("res://shaders/hero_hair.gdshader")
## hero-closeup-2: the hair's soft fringe pass, and the hair as it was (HERO_CLOSEUP_2=0).
const HAIR_FRINGE := preload("res://shaders/hero_hair_fringe.gdshader")
const HAIR_BASE := preload("res://shaders/hero_hair_base.gdshader")
const CLOTH := preload("res://shaders/hero_cloth.gdshader")
const EYE := preload("res://shaders/hero_eye.gdshader")
const LASH := preload("res://shaders/hero_lash.gdshader")
const MAPS := "res://assets/models/hero_x_%s"
## Elbow and knee angles (degrees of bend) at which the closed-joint folds start and are full.
const ELBOW_BEND := Vector2(35.0, 115.0)
const KNEE_BEND := Vector2(15.0, 95.0)

var cloth: ShaderMaterial
var skin: ShaderMaterial
var hair: ShaderMaterial
var cloth_rib: ShaderMaterial
var shadow_twin: MeshInstance3D
## The living face (blinks, saccades; HeroFace), null with HERO_CLOSEUP=0 / HERO_FACE=0.
var face: HeroFace
## Rain on his skin: the skin shader takes the wet world's water (wet_surface.gdshaderinc, which
## also wets the velour and the hair); `wet_gain` 0 turns the skin's off (HERO_CLOSEUP=0),
## HERO_WET=x holds a wetness on it for stills.
const WET_MATERIALS := ["skin"]
var _joints: Array = [] # [upper, middle, end] bone triples: L elbow, R elbow, L knee, R knee
var _skeleton: Skeleton3D


## Dresses `inst` (the instantiated hero.glb) and returns the look, or null when this is not the
## hero (no hero_skin material anywhere).
static func dress(inst: Node3D, settings: Dictionary = {}) -> HeroLook:
	var look := HeroLook.new()
	if HeroFace.enabled():
		look.face = HeroFace.new()
	var found := false
	var body: MeshInstance3D
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
			if mat and src.resource_name == "hero_skin":
				body = mi
			if mat:
				mi.set_surface_override_material(i, mat)
				found = true
	if not found:
		return null
	look.setup_wet()
	if look.face and look.face.eye == null:
		look.face = null
	if look.shadow_twin:
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			if node != look.shadow_twin:
				(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	look._skeleton = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if look._skeleton:
		# Read the pose when the skeleton has finished it: the arm IK and the hands only exist
		# in the final pose, and get_bone_global_pose() anywhere else returns the clip's.
		look._skeleton.skeleton_updated.connect(look.update)
		if look.face:
			look.face.attach(look._skeleton, body)
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
			# hero-face-2: the face's region map (pore size, redness, cartilage); HERO_FACE_2=0
			# is the old skin shading (the maps the build bakes stay the new ones).
			skin.set_shader_parameter("region_tex", _map("skin_region.png"))
			skin.set_shader_parameter("face2", 1.0 if face2() else 0.0)
			skin.set_shader_parameter("closeup2", 1.0 if closeup2() else 0.0)
			# The Compatibility renderer's BACKLIGHT is not scattering, it is a glow: at the old
			# strength the ears and fingers of every web / opengl3 frame lit up bright orange
			# against the sun. Forward+ keeps its transmittance as it was.
			if HeroFace.closeup() and RenderingServer.get_current_rendering_method() == "gl_compatibility":
				skin.set_shader_parameter("backlight_gain", 0.3)
			return skin
		"hero_hair", "hero_brows":
			var m := ShaderMaterial.new()
			m.shader = HAIR if closeup2() else HAIR_BASE
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
			m.set_shader_parameter("anisotropy", s.get("hair_anisotropy", 0.8))
			m.set_shader_parameter("closeup2", 1.0 if closeup2() else 0.0)
			if src.resource_name == "hero_brows":
				m.set_shader_parameter("strands_from_texture", 1.0)
				m.set_shader_parameter("specular", 0.2)
				m.set_shader_parameter("anisotropy", 0.0)
				if face2():
					# strand brows (tools/hero/hair.py): fine hairs want a lower cut and a little
					# shine along them
					m.set_shader_parameter("alpha_cut", 0.26)
					m.set_shader_parameter("specular", 0.3)
			else:
				hair = m
				if HeroFace.closeup():
					m.set_shader_parameter("root_fade", 0.22)
				if face2():
					m.set_shader_parameter("strand_round", 0.85)
			if closeup2():
				_add_fringe(m, src.resource_name == "hero_brows")
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
			m.set_shader_parameter("closeup2", 1.0 if closeup2() else 0.0)
			if src.resource_name == "hero_tracksuit":
				m.set_shader_parameter("bent_tex", _map("suit_bent_normal.jpg"))
				m.set_shader_parameter("wrinkle_mask", _map("suit_wrinkle_mask.png"))
				cloth = m
			else:
				cloth_rib = m
				m.set_shader_parameter("use_wrinkles", false)
				m.set_shader_parameter("pile_scale", 60.0)
				m.set_shader_parameter("pile_strength", 0.15)
			return m
		"hero_eyes" when face != null:
			var m := ShaderMaterial.new()
			m.shader = EYE
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
			m.set_shader_parameter("closeup2", 1.0 if closeup2() else 0.0)
			face.eye = m
			return m
		"hero_lashes" when face != null:
			var m := ShaderMaterial.new()
			m.shader = LASH
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
			face.lash = m
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


## hero-closeup-2: the hair and brows get a soft blended pass under the core's alpha cut (the
## fine tips and edges), and the core's dither narrows, since the fringe now fills that edge.
func _add_fringe(m: ShaderMaterial, brows: bool) -> void:
	if brows:
		# finer, translucent hairs: a higher cut for the core, the tips left to the fringe
		m.set_shader_parameter("alpha_cut", 0.55)
	m.set_shader_parameter("dither", 0.1)
	var f := ShaderMaterial.new()
	f.shader = HAIR_FRINGE
	for u in m.shader.get_shader_uniform_list():
		var v: Variant = m.get_shader_parameter(u.name)
		if v != null:
			f.set_shader_parameter(u.name, v)
	f.render_priority = 1
	m.next_pass = f


## The hero-closeup-2 pass (the hair's strand light and fringe, the brows' colour, the lips, the
## eyes' wet line, the velour); HERO_CLOSEUP_2=0 is the A/B.
static func closeup2() -> bool:
	return OS.get_environment("HERO_CLOSEUP_2") != "0"


## The hero-face-2 pass (strand brows, the face's region map, the new transmittance);
## HERO_FACE_2=0 is the A/B for what the shaders do.
static func face2() -> bool:
	return OS.get_environment("HERO_FACE_2") != "0"


func _map(name: String) -> Texture2D:
	var path := MAPS % name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## The closed-joint folds: 0 with the elbows and knees straight, 1 at a full bend. Runs on the
## skeleton's skeleton_updated signal, once the IK has placed the arms.
func update() -> void:
	if face:
		face.update()

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



## Sets the rain uniforms on the skin (called once they all exist).
func setup_wet() -> void:
	var hold := float(OS.get_environment("HERO_WET")) if OS.get_environment("HERO_WET") != "" else -1.0
	for key in WET_MATERIALS:
		var m := get(key) as ShaderMaterial
		if m:
			m.set_shader_parameter("wet_gain", 1.0 if HeroFace.closeup() else 0.0)
			m.set_shader_parameter("wet_hold", hold)
