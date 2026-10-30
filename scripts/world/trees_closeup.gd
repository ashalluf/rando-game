class_name TreesCloseup
## Street trees and palms from the pavement (trees-closeup, 2026-10-30; docs/HANDOFF.md "Trees
## close up"). Everything is in the three tree shaders - shaders/foliage_tex.gdshader (the
## scanned street and hill trees), shaders/foliage.gdshader (the palms) and
## shaders/la_tree.gdshader (the code-built LA trees) - and their shared gust field,
## shaders/tree_wind.gdshaderinc. This script only hands them what they cannot work out alone:
##   * `closeup` on every tree material (TREES_CLOSEUP=0 sets 0: each shader is then exactly the
##     shader it was, the A/B);
##   * each scanned tree's crown bounds in its own mesh space (`crown_center` / `crown_radius`),
##     from which foliage_tex works out how deep a leaf sits in the crown (inner leaves dark,
##     the sun side's shell bright, the shell translucent, the core not);
##   * the scanned trees' bark: the normal maps they ship at their full strength (the branches'
##     came at half) and the ORM map's occlusion channel switched on (Poly Haven's ARM packs it,
##     the glTF import leaves it off).
## No mesh, no roll, no LOD changes: the foliage ladders' table still matches.

## The A/B: false = every tree shader as it was.
static var enabled: bool = OS.get_environment("TREES_CLOSEUP") != "0"

## The crown inside a scanned tree's bounds: the leaves fill the top of it. Its centre is this far
## up the bounds, its vertical half extent this share of the height, and across it is the bounds.
const CROWN_UP := 0.62
const CROWN_HALF_HEIGHT := 0.42
const CROWN_SPREAD := 0.5
## Bark normal-map strength and the occlusion's reach on direct light.
const BARK_NORMAL := 1.0
const BRANCH_NORMAL := 0.9
const BARK_AO_LIGHT := 0.25

## The gust field (tree_wind.gdshaderinc's TW_*; tests/trees_closeup_checks.gd reads the include
## and holds these to it).
const TW_DIR := Vector2(0.949, 0.316)
const TW_SPEED := 8.5
const TW_LEN := 74.0
const TW_LEN2 := 31.0
const TW_RAGGED := 9.0


## `closeup` on a tree material (foliage_textured(), foliage_material(), LaTrees.material()).
static func mark(mat: ShaderMaterial) -> void:
	if mat != null:
		mat.set_shader_parameter("closeup", 1.0 if enabled else 0.0)


## Crown bounds on a scanned tree's leaf materials and the bark settings on its wood. Called once
## per model by PropFactory._tree_mesh() (the mesh and its materials are cached).
static func dress(mesh: Mesh) -> void:
	if mesh == null:
		return
	var box := mesh.get_aabb()
	var centre := Vector3(box.get_center().x, box.position.y + box.size.y * CROWN_UP, box.get_center().z)
	var radius := Vector3(box.size.x * CROWN_SPREAD, box.size.y * CROWN_HALF_HEIGHT, box.size.z * CROWN_SPREAD)
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is ShaderMaterial:
			var sm := mat as ShaderMaterial
			if sm.shader != null and sm.shader.resource_path.ends_with("foliage_tex.gdshader"):
				mark(sm)
				sm.set_shader_parameter("crown_center", centre)
				sm.set_shader_parameter("crown_radius", radius)
		elif mat is StandardMaterial3D and enabled:
			_bark(mat as StandardMaterial3D)


static func _bark(m: StandardMaterial3D) -> void:
	if m.get_meta("trees_closeup", false):
		return
	m.set_meta("trees_closeup", true)
	if m.normal_enabled:
		m.normal_scale = BRANCH_NORMAL if m.resource_name.ends_with("_branches") else BARK_NORMAL
	if m.roughness_texture != null and not m.ao_enabled:
		m.ao_enabled = true
		m.ao_texture = m.roughness_texture
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.ao_light_affect = BARK_AO_LIGHT


## tree_wind.gdshaderinc's tw_dir().
static func wind_dir(lean: Vector2 = Vector2.ZERO) -> Vector2:
	return lean.normalized() if lean.length_squared() > 1e-6 else TW_DIR


## tree_wind.gdshaderinc's tw_gust(): gust strength 0..1 at a TRUE world point at shader time t.
static func gust(world_xz: Vector2, t: float, lean: Vector2 = Vector2.ZERO) -> float:
	var d := wind_dir(lean)
	var along := world_xz.dot(d) - t * TW_SPEED
	var across := world_xz.dot(Vector2(-d.y, d.x))
	along += sin(across * 0.031 + t * 0.07) * TW_RAGGED
	var a := 0.5 + 0.5 * sin(along * (TAU / TW_LEN))
	var b := 0.5 + 0.5 * sin(along * (TAU / TW_LEN2) + 1.7 + across * 0.011)
	return a * a * (0.6 + 0.4 * b)
