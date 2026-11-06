class_name TreeLight
extends Node
## Trees under light (tree-light-2, 2026-10-31; docs/HANDOFF.md "Trees under light"). The work is
## in the tree shaders (shaders/tree_light.gdshaderinc, included by foliage_tex, foliage and
## la_tree); this script hands them what they cannot work out alone:
##   * `tree_light` on every tree material (TREE_LIGHT=0 sets 0: each shader is exactly the shader
##     it was before this pass, the A/B);
##   * `sway_height` on each scanned tree's leaf material (its crown top at scale 1, from the mesh
##     AABB), from which the sway's rate and the gust's lag follow;
##   * the `tree_sun` shader global: the sun's colour times its energy, linear, 0 at night, kept
##     by one node under the tree root (made by the first tree material, like CarLights), which
##     the crowns' forward-scattered light reads.
## No mesh, roll, LOD ladder or shadow twin changes.

## The A/B: false = every tree shader as it was.
static var enabled: bool = OS.get_environment("TREE_LIGHT") != "0"

## The weighted gust (tree_light.gdshaderinc's tl_rate / tl_lag / tl_load; tests hold them).
const RATE_REF := 10.0
const RATE_MIN := 0.6
const RATE_MAX := 1.5
const LAG_BASE := 0.35
const LAG_PER_M := 0.05
const LAG_MIN := 0.4
const LAG_MAX := 1.6
const SWING_BACK := 0.9
## Seconds between looks at the sun.
const SUN_INTERVAL := 0.2

static var _marked: Array[ShaderMaterial] = []
static var _node: TreeLight = null
var _sun: DirectionalLight3D = null
var _left := 0.0


## `tree_light` on a tree material (TreesCloseup.mark() calls this for every tree material).
static func mark(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("tree_light", 1.0 if enabled else 0.0)
	if not _marked.has(mat):
		_marked.append(mat)
	ensure()


## The pass on or off for every tree material made so far (a still's A/B in one held frame).
static func set_all(on: bool) -> void:
	for m in _marked:
		m.set_shader_parameter("tree_light", 1.0 if on else 0.0)


## A scanned tree's sway height on its leaf materials (TreesCloseup.dress()).
static func dress_material(mat: ShaderMaterial, box: AABB) -> void:
	mark(mat)
	mat.set_shader_parameter("sway_height", maxf(box.end.y, 1.0))


## The node that keeps `tree_sun`, made once under the tree root.
static func ensure() -> void:
	if not enabled or is_instance_valid(_node):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_node = TreeLight.new()
	_node.name = "TreeLight"
	tree.root.add_child.call_deferred(_node)


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = SUN_INTERVAL
	if not is_instance_valid(_sun):
		_sun = _find_sun()
	RenderingServer.global_shader_parameter_set("tree_sun", sun_light(_sun))


func _exit_tree() -> void:
	if _node == self:
		_node = null


## The sun: the scene's "Sun" light, else its strongest directional light.
func _find_sun() -> DirectionalLight3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var named := scene.get_node_or_null("Sun") as DirectionalLight3D
	if named:
		return named
	var best: DirectionalLight3D = null
	for n in scene.find_children("*", "DirectionalLight3D", true, false):
		var l := n as DirectionalLight3D
		if best == null or l.light_energy > best.light_energy:
			best = l
	return best


## The sun's light for the crowns, linear: colour (decoded from sRGB, as the renderer does) times
## energy, faded out as it reaches the horizon. Zero with no sun.
static func sun_light(sun: DirectionalLight3D) -> Vector3:
	if sun == null or not sun.is_visible_in_tree():
		return Vector3.ZERO
	var c := sun.light_color.srgb_to_linear()
	var up := clampf(sun.global_basis.z.y * 6.0, 0.0, 1.0)
	return Vector3(c.r, c.g, c.b) * sun.light_energy * up


## tree_light.gdshaderinc's tl_rate().
static func rate(height_m: float) -> float:
	return clampf(sqrt(RATE_REF / maxf(height_m, 1.0)), RATE_MIN, RATE_MAX)


## tree_light.gdshaderinc's tl_lag().
static func lag(height_m: float) -> float:
	return clampf(LAG_BASE + height_m * LAG_PER_M, LAG_MIN, LAG_MAX)


## tree_light.gdshaderinc's tl_load(): the gust as a crown `height_m` tall feels it.
static func load_of(world_xz: Vector2, t: float, height_m: float, lean: Vector2 = Vector2.ZERO) -> float:
	var l := lag(height_m)
	var g0 := TreesCloseup.gust(world_xz, t - l, lean)
	var g1 := TreesCloseup.gust(world_xz, t - l * 2.2, lean)
	return clampf(g0 + SWING_BACK * (g0 - g1), -0.35, 1.3)
