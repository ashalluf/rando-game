extends SceneTree
## Measures blank wall on the Buildings of a few FULL chunks round a point: per visible ground part
## face, the biggest rectangle StreetWear._paintable() clears (no glass, door or sign band).
##   godot --headless --path . --script tools/murals/wall_probe.gd -- --spawn=x,z
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2(2800, 100)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var city = current_scene
	var plan = city.get("plan")
	var sw: GDScript = load("res://scripts/world/street_wear.gd")
	var k0: Vector2i = plan.block_index_at(c)
	var hist := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := k0 + Vector2i(dx, dz)
			var chunk = city.call("_new_chunk", k, 0)
			chunk.build()
			var parts: Array = sw.call("_ground_parts", chunk)
			for p: Dictionary in parts:
				for face in 4:
					var along_x := face >= 2
					var su: float = (p.size as Vector3).x if along_x else (p.size as Vector3).z
					var best := 0.0
					var bw := 0.0
					var bh := 0.0
					# grid of cells 0.5 m
					var nu := int(su / 0.5)
					var nv := int((float(p.top) - float(p.base)) / 0.5)
					var ok := []
					for j in nv:
						var row := []
						for i in nu:
							row.append(sw.call("_paintable", p, face, (i + 0.5) * 0.5, float(p.base) + (j + 0.5) * 0.5))
						ok.append(row)
					# max rectangle (brute force on heights)
					var hgt := []
					hgt.resize(nu)
					hgt.fill(0)
					for j in nv:
						for i in nu:
							hgt[i] = hgt[i] + 1 if ok[j][i] else 0
						for i in nu:
							var mh := 999
							for i2 in range(i, nu):
								mh = mini(mh, hgt[i2])
								if mh == 0:
									break
								var area := float(i2 - i + 1) * 0.5 * float(mh) * 0.5
								if area > best:
									best = area
									bw = float(i2 - i + 1) * 0.5
									bh = float(mh) * 0.5
					var key := "%s style=%d sf=%s %.0fx%.0f" % [str(plan.block(k.x, k.y).district), int(p.style), str(p.storefront), bw, bh]
					if best >= 4.0:
						print("FACE ", key, " h=", snappedf(float(p.top) - float(p.base), 0.1), " pitch=", p.pitch_x, "/", p.pitch_z, " fh=", p.floor_h)
					hist[best >= 6.0] = int(hist.get(best >= 6.0, 0)) + 1
			chunk.queue_free()
	print("HIST ", hist)
	quit()
