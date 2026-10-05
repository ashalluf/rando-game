class_name MarineLayer
extends Node3D
## The marine layer's geometry (see LaWeather for where and when): the deck's underside and top as
## two big planes that follow the camera, and the evening fog bank as a ribbon standing on the
## water along the deck's edge (shaders/marine_layer.gdshader). Weather owns it and calls
## `drive()` every frame with the state's weight; at zero everything is hidden and costs nothing.
## Three draws, no shadows; the planes are transparent so the far end hands over to the fog.

## Radius of the deck planes (m). The camera draws to 12 km; past ~7.5 km the fog has the deck.
@export var deck_radius: float = 8000.0
## Length of the fog bank's ribbon along the coast (m) and its column spacing.
@export var bank_length: float = 16000.0
@export var bank_step: float = 100.0
## Metres a deck plane snaps by as it follows the camera (keeps its noise still).
@export var snap: float = 400.0
## Wind drift of the stratus texture (units per second of game time).
@export var drift_speed: float = 0.004

var amount: float = 0.0
## The scene's depth fog density (Weather sets it): the deck fogs itself with it.
var fog_density: float = 0.0003
var _under: MeshInstance3D
var _top: MeshInstance3D
var _bank: MeshInstance3D
var _mats: Array[ShaderMaterial] = []
var _drift: float = 0.0


func _ready() -> void:
	var shader := load("res://shaders/marine_layer.gdshader") as Shader
	for m in 3:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("mode", m)
		mat.set_shader_parameter("deck_base", LaWeather.DECK_BASE)
		mat.set_shader_parameter("deck_top", LaWeather.DECK_TOP)
		mat.set_shader_parameter("edge_soft", LaWeather.EDGE_SOFT)
		mat.set_shader_parameter("rim_start", deck_radius * 0.65)
		mat.set_shader_parameter("rim_end", deck_radius * 0.95)
		# Drawn after the opaque world and before other transparents at the same depth.
		mat.render_priority = -2
		_mats.append(mat)
	var plane := PlaneMesh.new()
	plane.size = Vector2(deck_radius * 2.0, deck_radius * 2.0)
	_under = _instance("DeckUnder", plane, _mats[0])
	_top = _instance("DeckTop", plane, _mats[1])
	_bank = _instance("FogBank", _ribbon(), _mats[2])
	visible = false


func _instance(n: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The bank is moved in the vertex shader and the planes are huge: never cull them by bounds.
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	return mi


## A grid in (z, y) at x 0: the shader stands it on the edge line.
func _ribbon() -> ArrayMesh:
	var cols := int(bank_length / bank_step) + 1
	var rows := 7
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for r in rows:
		var y := LaWeather.DECK_TOP * pow(float(r) / float(rows - 1), 1.25)
		for c in cols:
			verts.append(Vector3(0.0, y, -bank_length * 0.5 + float(c) * bank_step))
	for r in rows - 1:
		for c in cols - 1:
			var i := r * cols + c
			idx.append_array([i, i + cols, i + 1, i + 1, i + cols, i + cols + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Called by Weather each frame. `weight` the marine state's blend (0..1), `edge_x` the edge in
## true world X, `bank` LaWeather.bank_amount(), colours linear (lit top, shaded underside, the
## city's glow), `sun` the direction back to the sun, `fog` the scene's fog colour (as authored:
## sRGB numbers, decoded here).
func drive(weight: float, edge_x: float, bank: float, lit: Color, shade: Color, glow: Color, sun: Vector3, fog: Color, delta: float) -> void:
	amount = weight
	visible = weight > 0.003
	if not visible:
		return
	_drift += delta * drift_speed
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var at := cam.global_position if cam else Vector3.ZERO
	# Snap in TRUE world space, so the plane's own grid does not slide under the noise.
	var off := WorldState.world_offset
	var sx := snappedf(at.x + off.x, snap) - off.x
	var sz := snappedf(at.z + off.z, snap) - off.z
	_under.global_transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(sx, LaWeather.DECK_BASE, sz))
	_top.global_position = Vector3(sx, LaWeather.DECK_TOP, sz)
	_bank.global_position = Vector3(0.0, 0.0, sz)
	_bank.visible = bank > 0.003
	var lit3 := Vector3(lit.r, lit.g, lit.b)
	var shade3 := Vector3(shade.r, shade.g, shade.b)
	var glow3 := Vector3(glow.r, glow.g, glow.b)
	var f := fog.srgb_to_linear()
	var fog3 := Vector3(f.r, f.g, f.b)
	for mat in _mats:
		mat.set_shader_parameter("amount", weight)
		mat.set_shader_parameter("bank", bank)
		mat.set_shader_parameter("edge_x", edge_x)
		mat.set_shader_parameter("world_offset", off)
		mat.set_shader_parameter("lit_col", lit3)
		mat.set_shader_parameter("shade_col", shade3)
		mat.set_shader_parameter("glow_col", glow3)
		mat.set_shader_parameter("sun_dir", sun)
		mat.set_shader_parameter("drift", _drift)
		mat.set_shader_parameter("fog_col", fog3)
		mat.set_shader_parameter("fog_k", fog_density)
