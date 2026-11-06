extends Node
## Lists the hill estates (HillRoads.mansions) in seconds, without building a city, and where a
## camera in the basin should stand to look at a cluster of them:
##   godot --headless --path . res://tools/estate_night/probe.tscn
## Env: SEED; REGION=x0,z0,x1,z1 (default the whole map); EYE_DIST metres from the cluster (2500).

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var macro := MacroMap.new()
	var seed_env := OS.get_environment("SEED")
	macro.seed = int(seed_env) if seed_env != "" else city.world_seed
	var plan := CityPlan.new()
	plan.seed = macro.seed
	for key in ["block_size_range", "street_width", "avenue_width", "sidewalk_width", "downtown_radius", "midtown_radius"]:
		plan.set(key, city.get(key))
	plan.macro = macro
	city.free()
	macro.setup()
	var region := Rect2(-1e6, -1e6, 2e6, 2e6)
	var r := OS.get_environment("REGION")
	if r != "":
		var p := r.split(",")
		region = Rect2(float(p[0]), float(p[1]), float(p[2]) - float(p[0]), float(p[3]) - float(p[1]))
	# Clusters on a 600 m grid.
	var cells := {}
	for m in macro.hill_roads.mansions:
		var pos: Vector2 = m.pos
		if not region.has_point(pos):
			continue
		var k := Vector2i(floori(pos.x / 600.0), floori(pos.y / 600.0))
		if not cells.has(k):
			cells[k] = []
		cells[k].append(m)
		print("ESTATE %.0f,%.0f h %.1f yaw %.2f r %.0f" % [pos.x, pos.y, float(m.height), float(m.yaw), float(m.get("radius", 17.0))])
	var keys := cells.keys()
	keys.sort_custom(func(a, b): return cells[a].size() > cells[b].size())
	var eye_dist := float(OS.get_environment("EYE_DIST")) if OS.get_environment("EYE_DIST") != "" else 2500.0
	for k in keys.slice(0, 8):
		var c := Vector2.ZERO
		var hsum := 0.0
		for m in cells[k]:
			c += m.pos
			hsum += float(m.height)
		c /= cells[k].size()
		hsum /= cells[k].size()
		# A camera toward downtown from the cluster, on the ground there.
		var dir := (Vector2(2800, 100) - c).normalized()
		var e := c + dir * eye_dist
		var gy := plan.height_at(e)
		var to := c - e
		var yaw := rad_to_deg(atan2(-to.x, -to.y))
		var pitch := rad_to_deg(atan2(hsum - (gy + 30.0), to.length()))
		print("CLUSTER %d estates at %.0f,%.0f (h %.0f)  EYE=%.0f,%.0f,%.0f,%.1f,%.1f" % [cells[k].size(), c.x, c.y, hsum, e.x, gy + 30.0, e.y, yaw, pitch])
	get_tree().quit()
