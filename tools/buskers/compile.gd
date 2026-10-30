extends SceneTree
## Compiles the buskers' scripts once the autoloads exist, builds every gear mesh and prints its
## triangles (seconds):  godot --headless --path . --script tools/buskers/compile.gd

const SCRIPTS := ["res://scripts/world/buskers.gd", "res://scripts/npc/busker.gd", "res://scripts/npc/busk_watcher.gd",
	"res://scripts/world/city_chunk.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	var sh: Shader = load("res://shaders/busker_prop.gdshader")
	var m := ShaderMaterial.new()
	m.shader = sh
	var B: Script = load("res://scripts/world/buskers.gd")
	B.warm()
	var meshes: Dictionary = B.gear_meshes()
	for k in ["guitar", "violin", "bow", "trumpet", "stick"]:
		meshes[k] = B.call(k + "_mesh") if k != "guitar" else B.guitar_mesh(false)
	meshes["guitarron"] = B.guitar_mesh(true)
	meshes["sombrero_a"] = B.sombrero_mesh("res://assets/models/crowd_a.glb")
	for k: String in meshes:
		var mesh: Mesh = meshes[k]
		var tris := 0
		for i in mesh.get_surface_count():
			tris += (mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		print("MESH %-12s %6d tris  aabb %s" % [k, tris, mesh.get_aabb()])
	quit()
