class_name RockKit
## The hills' real rock: photoscanned CC0 Poly Haven cliffs and boulders (docs/ASSETS.md), on
## shaders/rock_outcrop.gdshader, which recolours the scans' orange Namaqualand granite to the
## hills' buff sandstone and grey granite and seats a far rock on the horizon plane's drawn ground.
##
## Two meshes a tor kind:
##  * mesh(): the scan (tools/decimate_tree.py, 7-9k triangles) with its own maps, ONE level. Its
##    LODs are left out on purpose: the scan's UV seams are open, and every simplifier - pymeshlab's
##    texture-preserving one and Godot's - shreds it past the first level into flakes floating round
##    the rock (tools/rocks/rock_shot.gd LOD=n shows them). RockFar draws it only close up.
##  * mid_mesh(): the same scan welded and cut to ~1,800 triangles, geometry only
##    (tools/rocks/make_rock_lods.py), with LODs Godot generates down to a couple of hundred; drawn
##    with the hills' tileable rock texture laid triplanar (the shader's far mode). RockFar's far
##    cells, every near tor's shadow, and a tor's collision.
## The boulders are scans of a few thousand triangles: mesh() only, with their generated LODs
## (small enough that the flaking never shows), near the camera only.
##
## Instance data (MultiMesh INSTANCE_CUSTOM, every value small - half floats on Compatibility):
## r 1 when the real terrain is drawn under the rock (a FULL or LOD chunk), 0 where the far plane
## is the ground; g the tone (0 sandstone .. 1 granite); b how deep the origin was sunk under the
## real ground, / 100; a 0 collapses it (RockFar's far copy of a tor its near cell draws).

const DIR := "res://assets/models/"
## The kinds, their files and what they are. A kind's index is what RockOutcrops plans with.
const KINDS := ["tor_a", "tor_b", "face_a", "boulder_c", "boulder_a", "boulder_b"]
const FILES := ["rock_tor_a.glb", "rock_tor_b.glb", "rock_face_a.glb", "rock_boulder_c.glb", "rock_a.glb", "rock_b.glb"]
const TOR_A := 0
const TOR_B := 1
const FACE_A := 2
const BOULDER_C := 3
const BOULDER_A := 4
const BOULDER_B := 5
## The kinds that stand as tors (RockFar), and their welded meshes.
const TOR_KINDS := [TOR_A, TOR_B, FACE_A]
const MID_FILES := {TOR_A: "rock_tor_a_mid.glb", TOR_B: "rock_tor_b_mid.glb", FACE_A: "rock_face_a_mid.glb"}

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
## The scan's maps and mean, read once off the glTF's own material.
static var _scan: Dictionary = {}


## The kind's scan, one level, wearing the near rock material (no far seat): what a chunk's batch
## draws (with the welded mesh as its shadow twin where the kind has one). RockFar draws it under
## a material_override. Cached; the mesh is this kit's own.
static func mesh(kind: int) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	if not MID_FILES.has(kind):
		# A boulder: a few thousand triangles, small enough that its generated LODs' flaking never
		# shows; it keeps them and its shadow twin.
		var b := PropFactory.model_mesh(DIR + FILES[kind], [], [], Transform3D.IDENTITY, {}, true, 1 << 20)
		_scan_material(kind, b)
		_meshes[kind] = b
		var bm := material(kind, false, false)
		for s in b.get_surface_count():
			b.surface_set_material(s, bm)
		var twin := PropFactory.shadow_proxy(b)
		if twin:
			for s in twin.get_surface_count():
				twin.surface_set_material(s, bm)
		return b
	var src := PropFactory.model_mesh(DIR + FILES[kind], [], [], Transform3D.IDENTITY, {}, false, 1 << 20)
	_scan_material(kind, src)
	var m := ArrayMesh.new()
	_meshes[kind] = m
	for s in src.get_surface_count():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
		m.surface_set_material(s, material(kind, false, false))
	PropFactory._shadow_proxies[m] = mid_mesh(kind)
	return m


## A tor kind's welded mesh (LODs to ~200 triangles), on the far-mode material with the seat on.
static func mid_mesh(kind: int) -> Mesh:
	var key := "mid_%d" % kind
	if _meshes.has(key):
		return _meshes[key]
	var m := PropFactory.model_mesh(DIR + String(MID_FILES[kind]), [], [], Transform3D.IDENTITY, {}, false, 1 << 20)
	_meshes[key] = m
	if not _scan.has(kind):
		mesh(kind)
	var mat := material(kind, true, true)
	for s in m.get_surface_count():
		m.surface_set_material(s, mat)
	return m


## The glTF's own materials (tools/rocks/rock_shot.gd PLAIN=1).
static func plain_mesh(kind: int) -> Mesh:
	return PropFactory.model_mesh(DIR + FILES[kind])


## One LOD of a mesh as a mesh of its own (the shot tool's LOD=n; 0 the base).
static func lod_of(m: Mesh, lod: int) -> Mesh:
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var arrays := m.surface_get_arrays(s)
		var lods: Array = RenderingServer.mesh_get_surface(m.get_rid(), s).get("lods", [])
		if lod > 0 and not lods.is_empty():
			var data: PackedByteArray = lods[mini(lod, lods.size()) - 1].index_data
			var wide := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 65535
			var idx := PackedInt32Array()
			if wide:
				idx = data.to_int32_array()
			else:
				idx.resize(data.size() / 2)
				for i in idx.size():
					idx[i] = data.decode_u16(i * 2)
			arrays[Mesh.ARRAY_INDEX] = idx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(s, m.surface_get_material(s))
	return out


## A mesh's triangles per LOD (LOD0 first).
static func lod_triangles(m: Mesh) -> PackedInt32Array:
	var out := PackedInt32Array()
	var d := RenderingServer.mesh_get_surface(m.get_rid(), 0)
	out.append((m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3)
	var wide := (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 65535
	for l: Dictionary in d.get("lods", []):
		out.append((l.index_data as PackedByteArray).size() / (12 if wide else 6))
	return out


static func _scan_material(kind: int, m: Mesh) -> void:
	if _scan.has(kind):
		return
	var src := m.surface_get_material(0) as BaseMaterial3D
	var d := {"height": maxf(m.get_aabb().size.y, 0.1)}
	if src:
		d["albedo"] = src.albedo_texture
		d["normal"] = src.normal_texture
		d["arm"] = src.ao_texture if src.ao_texture else src.roughness_texture
		d["mean"] = _mean_luminance(src.albedo_texture)
	_scan[kind] = d


## The kind's rock material. `seat`: moved onto the horizon plane where no chunk drew the real
## ground (RockFar's materials; the plane uniforms are theirs to set). `far`: the welded mesh's
## far mode (no UVs: the hills' tileable rock laid triplanar instead of the scan's maps).
static func material(kind: int, seat: bool, far: bool) -> ShaderMaterial:
	var key := "%d_%d_%d" % [kind, int(seat), int(far)]
	if _materials.has(key):
		return _materials[key]
	if not _scan.has(kind):
		mesh(kind)
	var d: Dictionary = _scan[kind]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rock_outcrop.gdshader")
	mat.set_shader_parameter("albedo_tex", d.get("albedo"))
	mat.set_shader_parameter("normal_tex", d.get("normal"))
	mat.set_shader_parameter("arm_tex", d.get("arm"))
	mat.set_shader_parameter("scan_mean", float(d.get("mean", 0.2)))
	mat.set_shader_parameter("mesh_height", float(d.height))
	mat.set_shader_parameter("seat", seat)
	mat.set_shader_parameter("far_mode", far)
	var tile := PropFactory.texture("hill_outcrop", "Color")
	mat.set_shader_parameter("tile_tex", tile)
	if not _scan.has("tile_mean"):
		_scan["tile_mean"] = _mean_luminance(tile)
	mat.set_shader_parameter("tile_mean", float(_scan.tile_mean))
	_materials[key] = mat
	return mat


## The texture's mean luminance in linear light (read once, shrunk).
static func _mean_luminance(tex: Texture2D) -> float:
	if tex == null:
		return 0.2
	var img := tex.get_image()
	if img == null or img.is_empty():
		return 0.2
	if img.is_compressed():
		img.decompress()
	img.resize(16, 16, Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	for y in 16:
		for x in 16:
			var c := img.get_pixel(x, y).srgb_to_linear()
			total += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	return maxf(total / 256.0, 0.02)


## The kind's AABB in its own units.
static func bounds(kind: int) -> AABB:
	return mesh(kind).get_aabb()
