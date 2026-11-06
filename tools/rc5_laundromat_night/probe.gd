extends SceneTree
## Finds shop strips for the laundromat_night refcam: a face of a low building whose open LAUNDRY
## stands next to a DONUT HOLE and a closed, shuttered shop. Headless (reads Building data only):
##   HOPS="x,z;x,z;..." godot --headless --path . --script tools/rc5_laundromat_night/probe.gd
## Each match prints the shops along the face and an EYE across the pavement.

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return d if v == "" else v


func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 30:
		await process_frame
	var city: Node = current_scene
	var ws: Node = root.get_node("/root/WorldState")
	var player: Node3D = city.find_child("Player", true, false)
	var BuildingT: GDScript = load("res://scripts/world/building.gd")
	var seen := {}
	for pair in _env("HOPS", "0,0").split(";", false):
		var xz := pair.split(",")
		var w := Vector3(float(xz[0]), 0.0, float(xz[1]))
		var local: Vector3 = ws.call("to_local", w)
		local.y = float(city.call("ground_height_at", local)) + 3.0
		player.global_position = local
		city.call("update_streaming", true)
		for i in int(_env("HOP_FRAMES", "60")):
			await process_frame
		var off: Vector3 = ws.get("world_offset")
		for b in city.find_children("*", "StaticBody3D", true, false):
			if not (b.get("shop_fronts") is Array) or b.get("seed") == null:
				continue
			if seen.has(b.get_instance_id()):
				continue
			seen[b.get_instance_id()] = true
			var fronts: Array = b.get("shop_fronts")
			if fronts.is_empty():
				continue
			var by_face := {}
			for f in fronts:
				var key: int = f[4]
				var face_id := (key >> 10) & 7
				var run := key & 1023
				if not by_face.has(face_id):
					by_face[face_id] = {}
				by_face[face_id][run] = f
			for face_id in by_face:
				var runs: Dictionary = by_face[face_id]
				var n_runs := 0
				for r in runs:
					n_runs = maxi(n_runs, r + 1)
				var names: Array = b.call("shop_names", face_id - 1, n_runs)
				var laund := -1
				var donut := -1
				for r in runs:
					var nm: String = BuildingT.SHOP_NAMES[names[r]]
					if nm == "LAUNDRY" and BuildingT.shop_open(runs[r][4]):
						laund = r
					if nm == "DONUT HOLE":
						donut = r
				if laund < 0 or donut < 0 or absi(laund - donut) > 2:
					continue
				var line := ""
				for r in range(n_runs):
					if not runs.has(r):
						line += " [-]"
						continue
					var k: int = runs[r][4]
					var op: bool = BuildingT.shop_open(k)
					var shut: bool = not op and BuildingT.shop_byte(k, 8) < 140
					line += " [%s %s%s]" % [BuildingT.SHOP_NAMES[names[r]], "open" if op else "closed", " shutter" if shut else ""]
				var f0 = runs[laund]
				var p: Vector3 = (f0[0] as Vector3)
				var gp: Vector3 = (b as Node3D).global_transform * p + off
				var nw: Vector3 = ((b as Node3D).global_transform.basis * (f0[1] as Vector3)).normalized()
				var eye := gp + nw * 9.0
				var look := -nw
				print("MATCH ", b.name, " seed=", b.get("seed"), " h=", snappedf(float(b.get("height")), 0.1), " face=", face_id, " laund=", laund, " donut=", donut, " at=", gp.snapped(Vector3.ONE * 0.1), line)
				print("   EYE=", snappedf(eye.x, 0.1), ",1.7,", snappedf(eye.z, 0.1), ",", snappedf(rad_to_deg(atan2(-look.x, -look.z)), 1), ",2")
		print("HOP ", pair, " done, buildings seen ", seen.size())
	quit(0)
