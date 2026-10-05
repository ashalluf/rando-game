class_name SmokeColumn
extends Node3D
## A big fire's column of smoke (TreeFire's manager makes one over every cluster of fires heavy
## enough: several burning cars, a burning tree): a tall dark plume climbing hundreds of metres
## and leaning down the wind, seen from across the basin. ONE mesh of `PUFFS` camera-facing
## quads, every one placed by shaders/smoke_column.gdshader from TIME, so a column is one draw
## and no CPU work a frame but a handful of uniform sets a second. It grows over `rise` seconds
## while the fire feeds it and clears over `clear` seconds once nothing does.

## Puffs in a column (fewer on the web).
const PUFFS := 56
## Column height (metres) for a fire of weight 2, and per unit of weight more, and its cap.
const BASE_HEIGHT := 150.0
const HEIGHT_PER_WEIGHT := 55.0
const MAX_HEIGHT := 420.0

static var _mesh: ArrayMesh
static var _shader: Shader

## The weight of fire under it this second (0 while nothing feeds it).
var fed: float = 0.0
## 0..1, how far it has come up.
var strength: float = 0.0
var _height: float = BASE_HEIGHT
var _lean: Vector2 = Vector2.ZERO
var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _glow: float = 0.0


func _ready() -> void:
	name = "SmokeColumn"
	_mi = MeshInstance3D.new()
	_mi.name = "Plume"
	_mi.mesh = mesh()
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The shader moves every vertex; the box has to hold the whole plume and its lean.
	_mi.custom_aabb = AABB(Vector3(-500.0, -20.0, -500.0), Vector3(1000.0, MAX_HEIGHT + 120.0, 1000.0))
	_mat = ShaderMaterial.new()
	_mat.shader = shader()
	_mat.set_shader_parameter("puff_tex", WeaponFX.puff_texture())
	_mat.set_shader_parameter("strength", 0.0)
	_mi.material_override = _mat
	add_child(_mi)


static func shader() -> Shader:
	if _shader == null:
		_shader = load("res://shaders/smoke_column.gdshader")
	return _shader


## PUFFS quads, each carrying its slot in UV2 (x: phase along the loop, y: a random number).
static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var n := PUFFS if not OS.has_feature("web") else PUFFS / 2
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in n:
		var r := float(hash([i, "smoke_column"]) & 0xffff) / 65535.0
		var slot := (float(i) + r * 0.6) / float(n)
		var base := verts.size()
		for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			verts.append(Vector3(c.x - 0.5, c.y, 0.0))
			uvs.append(c)
			uv2.append(Vector2(slot, r))
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh


## A second of the column's life: grow toward the fire it has, lean with `wind` (m/s, xz).
func step(dt: float, rise: float, clear: float, wind: Vector2) -> void:
	if fed > 0.0:
		strength = minf(strength + dt / maxf(rise, 0.1), 1.0)
		var want := clampf(BASE_HEIGHT + (fed - 2.0) * HEIGHT_PER_WEIGHT, BASE_HEIGHT * 0.7, MAX_HEIGHT)
		_height = lerpf(_height, want, clampf(dt * 0.1, 0.0, 1.0))
		_glow = minf(_glow + dt * 0.5, 1.0)
	else:
		strength = maxf(strength - dt / maxf(clear, 0.1), 0.0)
		_glow = maxf(_glow - dt * 0.4, 0.0)
	# The column comes up from the fire: early on only its lower part is there.
	var shown := _height * (0.35 + 0.65 * smoothstep(0.0, 0.6, strength))
	# Smoke rises ~8-10 m/s and the wind carries it the whole way up: the top's drift is
	# the wind times the time it took to get there.
	_lean = _lean.lerp(wind * (shown / 9.0) * 0.9, clampf(dt * 0.2, 0.0, 1.0))
	if _mat:
		_mat.set_shader_parameter("height", shown)
		_mat.set_shader_parameter("strength", smoothstep(0.0, 1.0, strength))
		_mat.set_shader_parameter("lean", _lean)
		_mat.set_shader_parameter("glow", _glow * clampf(fed / 2.0, 0.0, 1.0))
		_mat.set_shader_parameter("radius_top", clampf(shown * 0.16, 18.0, 60.0))
		_mat.set_shader_parameter("radius_base", clampf(2.0 + fed * 1.5, 3.0, 9.0))


func gone() -> bool:
	return fed <= 0.0 and strength <= 0.0


## The column's height now (tests).
func height() -> float:
	return _height
