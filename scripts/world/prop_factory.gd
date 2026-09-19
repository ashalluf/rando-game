class_name PropFactory
extends RefCounted
## Meshes for street furniture and trees, built once and shared. Primitives for the cheap
## repeated bits (dashes, stripes, lamps, trees), real CC0 models (Poly Haven, see
## docs/ASSETS.md) for the things the player gets close to: model_* below.

static var _cache: Dictionary = {}

## CC0 texture sets in assets/textures (see docs/ASSETS.md). Map names: Color, NormalGL, Roughness.
const TEXTURE_SETS := {
	"asphalt": "Asphalt033", "brick": "Bricks104", "concrete": "Concrete034", "grass": "Grass004",
	"sand": "Ground054", "metal": "MetalPlates006", "paving": "PavingStones138", "rock": "Rock064",
	"hill": "AerialGrassRock", "hill_rock": "RockyTerrain02",
	# Street surface sets (Poly Haven), picked per road and per block for variety.
	"asphalt_aerial": "AerialAsphalt01", "pavers": "LargeSquarePattern01", "sidewalk": "GravelConcrete03",
	# Facade sets (Poly Haven), picked per building by Building._apply_wall_texture().
	"brick_red": "RedBrick", "brick_mossy": "Brick4", "brick_factory": "RedBrick03",
	"plaster_painted": "PaintedPlasterWall", "plaster_beige": "BeigeWall001", "plaster_white": "WhitePlaster02",
	"concrete_painted": "ConcreteWall003", "concrete_cracked": "CrackedConcreteWall", "concrete_layers": "ConcreteLayers02",
	"metal_corrugated": "CorrugatedIron", "metal_factory": "FactoryWall",
}


static func texture(set_key: String, map: String) -> Texture2D:
	var set_name: String = TEXTURE_SETS.get(set_key, set_key)
	var key := "tex_%s_%s" % [set_name, map]
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/textures/%s/%s_1K-JPG_%s.jpg" % [set_name, set_name, map]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[key] = tex
	return tex


## A textured material projected in world space (triplanar), `scale_m` meters per tile.
static func pbr(set_key: String, scale_m: float = 4.0, tint: Color = Color.WHITE, roughness_scale: float = 1.0) -> StandardMaterial3D:
	var key := "pbr_%s_%.2f_%d_%.2f" % [set_key, scale_m, tint.to_rgba32(), roughness_scale]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = texture(set_key, "Color")
	var normal := texture(set_key, "NormalGL")
	if normal:
		mat.normal_enabled = true
		mat.normal_texture = normal
		mat.normal_scale = 0.8
	var rough := texture(set_key, "Roughness")
	if rough:
		mat.roughness_texture = rough
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.roughness = roughness_scale
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / scale_m
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = mat
	return mat


static func terrain_material() -> ShaderMaterial:
	if _cache.has("terrain_mat"):
		return _cache["terrain_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("grass_albedo", texture("hill", "Color"))
	mat.set_shader_parameter("grass_normal", texture("hill", "NormalGL"))
	mat.set_shader_parameter("rock_albedo", texture("hill_rock", "Color"))
	mat.set_shader_parameter("rock_normal", texture("hill_rock", "NormalGL"))
	_cache["terrain_mat"] = mat
	return mat


static func material(color: Color, roughness: float = 0.85, unshaded: bool = false) -> StandardMaterial3D:
	var key := "m%d_%d_%d" % [color.to_rgba32(), int(roughness * 100), int(unshaded)]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.vertex_color_use_as_albedo = true
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache[key] = mat
	return mat


static func box(key: String, size: Vector3, color: Color) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material(color)
	_cache[key] = mesh
	return mesh


static func cylinder(key: String, radius: float, height: float, color: Color, top_radius: float = -1.0, segments: int = 8) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = material(color)
	_cache[key] = mesh
	return mesh


# --- Ready-made pieces (origin at the base, Y up) ---------------------------------

static func trunk() -> Mesh:
	return cylinder("trunk", 0.18, 2.2, Color(0.42, 0.30, 0.18), 0.14, 6)


static func canopy_round() -> Mesh:
	if _cache.has("canopy_round"):
		return _cache["canopy_round"]
	var mesh := SphereMesh.new()
	mesh.radius = 1.6
	mesh.height = 3.2
	mesh.radial_segments = 8
	mesh.rings = 5
	mesh.material = material(Color(0.32, 0.58, 0.28))
	_cache["canopy_round"] = mesh
	return mesh


static func canopy_cone() -> Mesh:
	return cylinder("canopy_cone", 1.5, 4.0, Color(0.20, 0.45, 0.24), 0.0, 7)


static func lamp_pole() -> Mesh:
	return cylinder("lamp_pole", 0.09, 6.0, Color(0.28, 0.29, 0.32), 0.07, 6)


static func lamp_head() -> Mesh:
	if _cache.has("lamp_head"):
		return _cache["lamp_head"]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.7, 0.18, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.6)
	mat.emission_energy_multiplier = 1.5
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	_cache["lamp_head"] = mesh
	return mesh


static func grass_blade() -> Mesh:
	if _cache.has("grass_blade"):
		return _cache["grass_blade"]
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.14, 0.55)
	mesh.center_offset = Vector3(0.0, 0.275, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mesh.material = mat
	_cache["grass_blade"] = mesh
	return mesh


static func bush() -> Mesh:
	if _cache.has("bush"):
		return _cache["bush"]
	var mesh := SphereMesh.new()
	mesh.radius = 0.9
	mesh.height = 1.4
	mesh.radial_segments = 7
	mesh.rings = 4
	mesh.material = material(Color(0.30, 0.52, 0.26))
	_cache["bush"] = mesh
	return mesh


static func bench() -> Mesh:
	return box("bench", Vector3(1.8, 0.1, 0.5), Color(0.5, 0.36, 0.22))


static func bench_legs() -> Mesh:
	return box("bench_legs", Vector3(1.6, 0.45, 0.4), Color(0.25, 0.25, 0.27))


static func hydrant() -> Mesh:
	return cylinder("hydrant", 0.16, 0.8, Color(0.85, 0.15, 0.12), 0.12, 6)


## Center-line piece; white so the instance color picks yellow or white.
static func dash() -> Mesh:
	return box("dash", Vector3(0.16, 0.02, 3.0), Color(1.0, 1.0, 1.0))


static func stripe() -> Mesh:
	return box("stripe", Vector3(0.6, 0.02, 3.0), Color(0.95, 0.95, 0.92))


static func sign_pole() -> Mesh:
	return cylinder("sign_pole", 0.05, 2.6, Color(0.5, 0.5, 0.52), -1.0, 6)


static func stop_sign() -> Mesh:
	return cylinder("stop_sign", 0.45, 0.05, Color(0.8, 0.12, 0.1), -1.0, 8)


static func signal_pole() -> Mesh:
	return cylinder("signal_pole", 0.12, 6.5, Color(0.2, 0.2, 0.22), 0.1, 6)


static func signal_arm() -> Mesh:
	return box("signal_arm", Vector3(5.0, 0.14, 0.14), Color(0.2, 0.2, 0.22))


static func signal_box() -> Mesh:
	return box("signal_box", Vector3(0.35, 1.0, 0.35), Color(0.15, 0.15, 0.16))


static func signal_light(color: Color) -> Mesh:
	var key := "signal_light_%d" % color.to_rgba32()
	if _cache.has(key):
		return _cache[key]
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = material(color, 0.5, true)
	_cache[key] = mesh
	return mesh


static func trash_can_mesh() -> Mesh:
	return cylinder("trash_can", 0.35, 1.0, Color(0.25, 0.35, 0.3), -1.0, 8)


static func palm_trunk() -> Mesh:
	return cylinder("palm_trunk", 0.22, 7.0, Color(0.55, 0.42, 0.28), 0.14, 7)


static func palm_frond() -> Mesh:
	return box("palm_frond", Vector3(0.5, 0.06, 3.2), Color(0.30, 0.62, 0.30))


static func coconut() -> Mesh:
	if _cache.has("coconut"):
		return _cache["coconut"]
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = material(Color(0.45, 0.32, 0.18))
	_cache["coconut"] = mesh
	return mesh


static func lifeguard_cabin() -> Mesh:
	return box("lifeguard_cabin", Vector3(3.0, 2.4, 3.0), Color(0.35, 0.65, 0.85))


static func lifeguard_leg() -> Mesh:
	return box("lifeguard_leg", Vector3(0.25, 2.6, 0.25), Color(0.8, 0.78, 0.7))


static func lifeguard_ramp() -> Mesh:
	return box("lifeguard_ramp", Vector3(1.0, 0.1, 4.2), Color(0.8, 0.78, 0.7))


static func container() -> Mesh:
	return box("container", Vector3(12.0, 2.6, 2.4), Color(0.9, 0.9, 0.9))


static func unit_box() -> Mesh:
	return box("unit_box", Vector3.ONE, Color(0.9, 0.9, 0.9))


static func planter() -> Mesh:
	return box("planter", Vector3(2.4, 0.7, 2.4), Color(0.55, 0.5, 0.45))


# --- Real models -----------------------------------------------------------------------------
# Poly Haven glTF props packed to one .glb each (tools/pack_gltf.py). Several ship two variants
# side by side (a fresh and an aged hydrant, a clean and a rusty can), so a model is picked by
# node-name filters, moved to the origin and merged into one ArrayMesh with LODs so it can go
# through MultiMeshBatch like everything else. Merged once per variant and cached.

const MODEL_DIR := "res://assets/models/"


## Merges the MeshInstance3D nodes of the model at `path` whose names contain every string in
## `include` and none in `exclude` into one mesh. `xform` is applied to everything (used to
## move a variant to the origin and turn it to face -Z); `overrides` maps a node-name substring
## to a Transform3D that replaces that node's own transform (kits that ship parts unassembled).
static func model_mesh(path: String, include: PackedStringArray = [], exclude: PackedStringArray = [], xform: Transform3D = Transform3D.IDENTITY, overrides: Dictionary = {}) -> Mesh:
	var key := "model_%s_%s_%s_%s" % [path, ",".join(include), ",".join(exclude), var_to_str(xform)]
	if _cache.has(key):
		return _cache[key]
	var mesh: ArrayMesh = ArrayMesh.new()
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var root: Node = scene.instantiate()
		var importer := ImporterMesh.new()
		_merge_into(root, root, importer, include, exclude, xform, overrides)
		if importer.get_surface_count() > 0:
			importer.generate_lods(25.0, 60.0, [])
			mesh = importer.get_mesh()
		root.free()
	else:
		push_warning("PropFactory: missing model " + path)
	_cache[key] = mesh
	return mesh


static func _merge_into(node: Node, root: Node, importer: ImporterMesh, include: PackedStringArray, exclude: PackedStringArray, xform: Transform3D, overrides: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var lower := mi.name.to_lower()
		var wanted := true
		for s in include:
			if not lower.contains(s):
				wanted = false
		for s in exclude:
			if lower.contains(s):
				wanted = false
		if wanted and mi.mesh:
			var local := mi.transform
			var parent := mi.get_parent()
			while parent and parent != root:
				if parent is Node3D:
					local = (parent as Node3D).transform * local
				parent = parent.get_parent()
			for name in overrides:
				if lower.contains(name):
					local = overrides[name]
			var full := xform * local
			for s in mi.mesh.get_surface_count():
				var arrays := _transformed_arrays(mi.mesh.surface_get_arrays(s), full)
				importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mi.get_active_material(s), "%s_%d" % [mi.name, s])
	for child in node.get_children():
		_merge_into(child, root, importer, include, exclude, xform, overrides)


static func _transformed_arrays(arrays: Array, t: Transform3D) -> Array:
	var out := arrays.duplicate()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var moved := PackedVector3Array()
	moved.resize(verts.size())
	for i in verts.size():
		moved[i] = t * verts[i]
	out[Mesh.ARRAY_VERTEX] = moved
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var turned := PackedVector3Array()
		turned.resize(normals.size())
		for i in normals.size():
			turned[i] = (t.basis * normals[i]).normalized()
		out[Mesh.ARRAY_NORMAL] = turned
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var turned_t := PackedFloat32Array()
		turned_t.resize(tangents.size())
		for i in tangents.size() / 4:
			var v := (t.basis * Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])).normalized()
			turned_t[i * 4] = v.x
			turned_t[i * 4 + 1] = v.y
			turned_t[i * 4 + 2] = v.z
			turned_t[i * 4 + 3] = tangents[i * 4 + 3]
		out[Mesh.ARRAY_TANGENT] = turned_t
	return out


static func _shift(offset: Vector3) -> Transform3D:
	return Transform3D(Basis(), offset)


## Fire hydrant, 0.8 m tall, base at the origin. Fresh or aged paint.
static func model_hydrant(aged: bool) -> Mesh:
	if aged:
		return model_mesh(MODEL_DIR + "prop_hydrant.glb", ["aged"], [], _shift(Vector3(-0.3, 0.0, 0.0)))
	return model_mesh(MODEL_DIR + "prop_hydrant.glb", [], ["aged"], _shift(Vector3(0.3, 0.0, 0.0)))


## Metal trash can with a loose lid, 0.91 m tall, base at the origin. Clean or rusty.
static func model_trash_can(rusty: bool) -> Mesh:
	if rusty:
		return model_mesh(MODEL_DIR + "prop_trash_can.glb", ["rust"], [], _shift(Vector3(0.5, 0.0, 0.0)))
	return model_mesh(MODEL_DIR + "prop_trash_can.glb", [], ["rust"], _shift(Vector3(-0.5, 0.0, 0.0)))


## Timber and steel street bench assembled from the Poly Haven seating kit: 1.86 m wide, seat at
## 0.45 m, back rest leaning back, facing -Z, base at the origin.
static func model_bench() -> Mesh:
	var face_minus_z := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * _shift(Vector3(1.16, 0.0, 0.0))
	var parts: PackedStringArray = ["legs_single", "legs_double", "crossbar", "suspended_support_01", "seat", "back_support", "arm_rest"]
	var overrides := {"seat_back": Transform3D(Basis(Vector3.RIGHT, deg_to_rad(69.0)), Vector3(-1.16, 0.473, 0.098))}
	var mesh := model_mesh(MODEL_DIR + "prop_bench_kit.glb", [], ["connector", "seat_bench", "suspended_support_02"], face_minus_z, overrides)
	if mesh.get_surface_count() > 0:
		return mesh
	return bench()


## Concrete road barrier, 1.55 x 0.83 x 0.64 m, base at the origin.
static func model_barrier() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_barrier.glb")


## Red steel drum, 0.56 m across and 0.88 m tall, base at the origin.
static func model_barrel() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_barrel.glb")


## Old tyre lying flat, 0.6 m across and 0.16 m thick, bottom at the origin.
static func model_tyre() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_tyre.glb", [], [], Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.08, 0.0)))


## Wooden planter box, 0.91 x 0.42 x 0.41 m, base at the origin.
static func model_planter() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_planter.glb")


## Folding cafe table with two chairs, 0.79 x 0.86 x 1.71 m, base at the origin.
static func model_cafe_set() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_cafe_set.glb")


## Street lamp, 3.87 m tall, base at the origin. The bulb and glass surfaces glow.
static func model_lamp() -> Mesh:
	var mesh := model_mesh(MODEL_DIR + "prop_lamp.glb")
	if not _cache.has("model_lamp_lit"):
		_cache["model_lamp_lit"] = true
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var name := (mat as StandardMaterial3D).resource_name.to_lower()
				if name.contains("bulb") or name.contains("glass"):
					var lit: StandardMaterial3D = mat.duplicate()
					lit.emission_enabled = true
					lit.emission = Color(1.0, 0.9, 0.65)
					lit.emission_energy_multiplier = 3.0 if name.contains("bulb") else 0.8
					mesh.surface_set_material(i, lit)
				else:
					# The post takes the instance color (district paint).
					(mat as StandardMaterial3D).vertex_color_use_as_albedo = true
	return mesh


## One of four leafy shrubs (0.9 to 1.7 m), base at the origin. Instance colors tint the leaves.
static func model_shrub(variant: int) -> Mesh:
	var offsets: Array[Vector3] = [Vector3(-1.55, -0.01, -0.02), Vector3(0.0, -0.01, -0.02), Vector3(1.56, -0.01, -0.01), Vector3(3.26, 0.0, -0.01)]
	var v := clampi(variant, 0, 3)
	var mesh := model_mesh(MODEL_DIR + "prop_shrub.glb", ["shrub_02_" + "abcd"[v]], [], _shift(-offsets[v]))
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).vertex_color_use_as_albedo = true
	return mesh


## Round manhole cover with its frame, 0.7 m across, the frame top 0.04 m above the origin.
static func model_manhole() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_manhole.glb")


## Taller jersey barrier variant, 1.57 x 1.11 x 0.44 m, base at the origin.
static func model_barrier_tall() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_barrier_b.glb")


## A real tree (Poly Haven, reduced with tools/decimate_tree.py): 0 island tree, 1 second island
## tree, 2 small tree. About 5 m tall, base at the origin. Leaves use alpha scissor and take the
## instance color as a tint.
static func model_tree(variant: int) -> Mesh:
	var files: PackedStringArray = ["tree_a.glb", "tree_b.glb", "tree_c.glb"]
	var v := clampi(variant, 0, files.size() - 1)
	var mesh := model_mesh(MODEL_DIR + files[v])
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				sm.alpha_scissor_threshold = 0.45
				sm.vertex_color_use_as_albedo = true
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mesh


## Enables alpha scissor (instead of blending) and instance-color tinting on a plant mesh.
static func _plant_material(mesh: Mesh) -> Mesh:
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				sm.alpha_scissor_threshold = 0.45
			sm.vertex_color_use_as_albedo = true
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mesh


## Hill boulder: 0 is 2.5 x 0.8 m and flat, 1 is 2.5 x 1.9 m and tall. Base at the origin.
static func model_rock(variant: int) -> Mesh:
	return model_mesh(MODEL_DIR + ("rock_b.glb" if variant == 1 else "rock_a.glb"))


## Dry scrub plant, five sizes from 0.25 to 0.55 m (variant 0 biggest). Base at the origin.
static func model_scrub(variant: int) -> Mesh:
	var offsets: Array[float] = [1.6, 1.0, 0.5, 0.1, -0.2]
	var v := clampi(variant, 0, 4)
	return _plant_material(model_mesh(MODEL_DIR + "plant_rooibos.glb", ["wild_rooibos_bush_" + "abcde"[v]], [], _shift(Vector3(-offsets[v], 0.0, 0.0))))


## Grass tuft, five sizes from 0.15 to 0.4 m (variant 4 biggest). Base at the origin.
static func model_grass_tuft(variant: int) -> Mesh:
	var offsets: Array[float] = [0.0, 0.21, 0.49, 0.79, 1.11]
	var v := clampi(variant, 0, 4)
	return _plant_material(model_mesh(MODEL_DIR + "grass_tuft.glb", ["grass_medium_02_" + "abcde"[v]], [], _shift(Vector3(-offsets[v], 0.0, 0.0))))
