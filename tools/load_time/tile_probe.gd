extends Node
## Builds far-city tiles fresh and compares them with the load cache's copies, key by key
## (LoadCache / Skyline). Headless, a minute or two:
##   godot --headless --path . res://tools/load_time/tile_probe.tscn
## TILES=n how many cached tiles to compare (default 12). FRESH_FIRST=1 builds each fresh tile in a
## new city before anything else touched it.

func _ready() -> void:
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	add_child(city)
	for i in 5:
		await get_tree().process_frame
	var sky = city.get("_skyline")
	var stored: Variant = LoadCache.load_data("far_city", sky._disk_inputs())
	if not (stored is Dictionary):
		print("PROBE no cache entry")
		get_tree().quit()
		return
	var n := int(OS.get_environment("TILES")) if OS.get_environment("TILES") != "" else 12
	var bad := 0
	var seen := 0
	for t in stored:
		if stored[t] == null:
			continue
		seen += 1
		if seen > n:
			break
		var fresh := Skyline.new()
		fresh.setup(city.plan, city.call("chunk_style"), null)
		fresh._disk_open = true
		fresh._begin_tile(t)
		fresh._recording = true
		while not fresh._work_step():
			pass
		var a: Dictionary = fresh._disk[t]
		var b: Dictionary = stored[t]
		for key in b:
			if var_to_bytes(a[key]) == var_to_bytes(b[key]):
				continue
			bad += 1
			var msg := "PROBE tile %s key %s differs: sizes %d / %d" % [t, key, (a[key] as Variant).size(), (b[key] as Variant).size()]
			if a[key] is Array and (a[key] as Array).size() == (b[key] as Array).size():
				for i in (a[key] as Array).size():
					if var_to_bytes(a[key][i]) != var_to_bytes(b[key][i]):
						msg += " first at %d: fresh %s cached %s" % [i, a[key][i], b[key][i]]
						break
			print(msg)
		fresh.free()
	print("PROBE compared %d tiles, %d keys differ" % [mini(seen, n), bad])
	get_tree().quit()
