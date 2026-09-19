class_name PropFactory
extends RefCounted
## Meshes for street furniture and trees, built once and shared. All primitives, low-poly.

static var _cache: Dictionary = {}


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
	return box("lamp_head", Vector3(0.7, 0.18, 0.3), Color(1.0, 0.95, 0.8))


static func bench() -> Mesh:
	return box("bench", Vector3(1.8, 0.1, 0.5), Color(0.5, 0.36, 0.22))


static func bench_legs() -> Mesh:
	return box("bench_legs", Vector3(1.6, 0.45, 0.4), Color(0.25, 0.25, 0.27))


static func hydrant() -> Mesh:
	return cylinder("hydrant", 0.16, 0.8, Color(0.85, 0.15, 0.12), 0.12, 6)


static func dash() -> Mesh:
	return box("dash", Vector3(0.16, 0.02, 3.0), Color(0.95, 0.8, 0.2))


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


static func unit_box() -> Mesh:
	return box("unit_box", Vector3.ONE, Color(0.9, 0.9, 0.9))


static func planter() -> Mesh:
	return box("planter", Vector3(2.4, 0.7, 2.4), Color(0.55, 0.5, 0.45))
