extends Node
## Sea life probe (SeaLife, SeaLifeMesh): the meshes' triangle counts and sizes, the buoys and
## their sea lions, and for a stretch of coast the pods, pelican lines and whales due in the next
## minutes, with an EYE line for each to frame it with tools/glshot/still_shot.gd. Headless,
## seconds:  godot --headless --path . tools/sea_life/probe.tscn   (SEED=n, Z=metres along
## the coast to look round, MINUTES=how far ahead)
func _ready() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	for k in ["dolphin", "sea_lion", "pelican", "whale", "buoy", "spray"]:
		for lod in (1 if k == "spray" else 2):
			var t0 := Time.get_ticks_usec()
			var m := SeaLifeMesh.mesh(k, lod)
			print("MESH %-9s lod %d tris %5d size %s  (%d us)" % [k, lod, SeaLifeMesh.triangles(m), m.get_aabb().size, Time.get_ticks_usec() - t0])
	var sea := SeaLife.new()
	sea.setup_plan(plan)
	for b in sea.buoys():
		print("BUOY %s lions %d zone %d coast_x(z) %.0f" % [b.at, b.lions, macro.zone_at(b.at), macro.coast_x(b.at.y)])
		print("  EYE=%.1f,6,%.1f,0,-12" % [b.at.x, b.at.y + 14.0])
	var z0 := float(OS.get_environment("Z")) if OS.get_environment("Z") != "" else 0.0
	var minutes := float(OS.get_environment("MINUTES")) if OS.get_environment("MINUTES") != "" else 20.0
	print("coast at z %.0f: x %.1f, break %.1f m" % [z0, macro.coast_x(z0), sea._break_distance()])
	var eye := Vector3(macro.coast_x(z0) + 20.0, 3.0, z0)
	var seen := {}
	var t := 0.0
	while t < minutes * 60.0:
		for e in sea.events_at(t, eye):
			var key := "%s:%d:%d" % [e.kind, e.n, e.k]
			if seen.has(key):
				continue
			seen[key] = true
			var z: float = e.zc
			print("EVENT %-8s from t %6.1f stretch %d z %.0f dir %+.0f %s" % [e.kind, e.t0, e.k, z, e.dir, "count %d" % e.count if e.has("count") else ""])
		t += 5.0
	# A few seconds of frames at 60 fps where a pod and a line are passing (the real per-frame cost).
	var t_busy := 0.0
	for tb in range(0, 1200, 5):
		var kinds := {}
		for e in sea.events_at(float(tb), eye):
			kinds[e.kind] = true
		if kinds.has("dolphin") and kinds.has("pelican"):
			t_busy = float(tb) + 20.0
			break
	var tt := Time.get_ticks_usec()
	var n := 0
	for i in 300:
		var tf := t_busy + float(i) / 60.0
		for e in sea.events_at(tf, eye):
			match e.kind:
				"dolphin":
					n += sea.dolphins_at(e, tf).size()
				"pelican":
					n += sea.pelicans_at(e, tf).size()
				"whale":
					n += sea.whale_at(e, tf).size()
	print("cost: 300 frames at 60 fps from t %.0f: %.3f ms each (%.1f animals a frame)" % [t_busy, float(Time.get_ticks_usec() - tt) / 300000.0, float(n) / 300.0])
	if OS.get_environment("STAGE") != "":
		var kind := OS.get_environment("STAGE")
		sea.stage(kind, Vector2(-950.0, -120.0), 0.45)
		var e: Dictionary = sea._forced[0]
		for dt in [0.0, 0.3]:
			var list: Array = sea.pelicans_at(e, SeaLife.clock + dt) if kind != "dolphin" else sea.dolphins_at(e, SeaLife.clock + dt)
			for b in list:
				print("STAGED t+%.1f %s" % [dt, b])
	sea.free()
	get_tree().quit()
