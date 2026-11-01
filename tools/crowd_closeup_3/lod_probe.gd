extends SceneTree
## Triangles of every crowd rig's Body mesh at each of its LODs (the importer's), and the sum over
## the rigs, so a rebuild's cost near and far can be read off without a city.
##
##   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 640x480x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/crowd_closeup_3/lod_probe.gd
##
## Needs mesh data: never --headless.


func _initialize() -> void:
	var ped_script = load("res://scripts/npc/pedestrian.gd")
	var sums := {}
	for path: String in ped_script.MODELS:
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		var line := path.get_file().get_basename()
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null or ped_script.is_hair(mi):
				continue
			var tot := 0
			var lods := []
			for s in mi.mesh.get_surface_count():
				var d: Dictionary = RenderingServer.mesh_get_surface(mi.mesh.get_rid(), s)
				var isz := 4 if int(d.get("vertex_count", 0)) > 65535 else 2
				tot += int(d.get("index_count", 0)) / 3
				var k := 0
				for l: Dictionary in d.get("lods", []):
					var n := (l["index_data"] as PackedByteArray).size() / isz / 3
					if lods.size() <= k:
						lods.append([0, float(l["edge_length"])])
					lods[k][0] += n
					k += 1
			line += "  %s %d" % [mi.name, tot]
			sums["base"] = int(sums.get("base", 0)) + tot
			for k in lods.size():
				line += " | %d@%.3f" % [lods[k][0], lods[k][1]]
				sums[k] = int(sums.get(k, 0)) + lods[k][0]
		print("LOD ", line)
		inst.free()
	print("LOD SUM ", sums)
	quit()
