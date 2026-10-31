extends Node
## Kerbs probe (scripts/world/kerbs.gd): builds a few FULL city blocks headless - one per district
## it can find near the anchors, or the blocks in BLOCKS="bx,bz;..." - and prints what the kerb
## ring cut and painted there (ramps, driveway aprons, tree wells, heaves, zones, house numbers),
## the step's build time, and EYE lines for tools/glshot/block_shot.tscn / still_shot.gd.
##
##   godot --headless --path . res://tools/kerbs/probe.tscn
##
## ANCHORS="x,z;..." where to look for blocks (true world); DISTRICTS="2,0" which districts.

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = city.world_seed
	plan.macro.setup()
	var style: Dictionary = city.chunk_style()
	var picks: Array[Vector2i] = []
	if OS.get_environment("BLOCKS") != "":
		for b in OS.get_environment("BLOCKS").split(";", false):
			var p := b.split(",")
			picks.append(Vector2i(int(p[0]), int(p[1])))
	else:
		var anchors := "-700,-150;300,-600;1200,600;2700,300;3200,3200;600,1800"
		if OS.get_environment("ANCHORS") != "":
			anchors = OS.get_environment("ANCHORS")
		var want := {}
		var dl := "0,1,2,3,5"
		if OS.get_environment("DISTRICTS") != "":
			dl = OS.get_environment("DISTRICTS")
		for d in dl.split(","):
			want[int(d)] = true
		for a in anchors.split(";", false):
			var p := a.split(",")
			var home: Vector2i = plan.block_index_at(Vector2(p[0].to_float(), p[1].to_float()))
			for r in 6:
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						var bk := Vector2i(home.x + dx, home.y + dz)
						var b: Dictionary = plan.block(bk.x, bk.y)
						if b.kind != CityPlan.BlockKind.BUILDINGS or b.has("site") or plan.river_block(bk.x, bk.y):
							continue
						if plan.zone_at(b.rect.get_center()) != MacroMap.Zone.CITY:
							continue
						if want.has(int(b.district)):
							want.erase(int(b.district))
							picks.append(bk)
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	for bk in picks:
		var b: Dictionary = plan.block(bk.x, bk.y)
		var ch = chunk_script.new()
		ch.plan = plan
		ch.ix = bk.x
		ch.iz = bk.y
		ch.level = 0
		ch.style = style
		add_child(ch)
		var t0 := Time.get_ticks_usec()
		ch.begin_build()
		var worst := 0
		var kerb_us := 0
		while true:
			var s0 := Time.get_ticks_usec()
			var done: bool = ch.build_step()
			var dt := Time.get_ticks_usec() - s0
			worst = maxi(worst, dt)
			if ch.has_meta("kerbs") and (ch.get_meta("kerbs") as Dictionary).has("built") and kerb_us == 0:
				kerb_us = dt
			if done:
				break
		var total := Time.get_ticks_usec() - t0
		print("BLOCK %d,%d district=%d rect=%s build=%.1f ms worst_step=%.1f ms kerb_step=%.1f ms" % [bk.x, bk.y, b.district, b.rect, total / 1000.0, worst / 1000.0, kerb_us / 1000.0])
		if not ch.has_meta("kerbs"):
			print("  no kerb ring")
			ch.queue_free()
			continue
		var built: Dictionary = (ch.get_meta("kerbs") as Dictionary).get("built", {})
		if built.is_empty():
			print("  kerb step did not run")
			ch.queue_free()
			continue
		print("  ramps=%d drives=%d wells=%d heaves=%d cracks=%d zones=%d numbers=%d faces=%d" % [built.ramps, built.drives, built.wells, built.heaves, built.cracks, (built.zones as Array).size(), (built.numbers as Array).size(), built.faces])
		var edges: Array = built.edges
		if OS.get_environment("NOTCHES") == "1":
			for n: Dictionary in built.notches:
				var c: Vector2 = (n.poly as PackedVector2Array)[0].lerp((n.poly as PackedVector2Array)[1], 0.5)
				print("  NOTCH kind=%d e=%d uc=%.2f half=%.2f at=%.2f,%.2f" % [n.kind, n.e, n.uc, n.a, c.x, c.y])
		var shown := {}
		for n: Dictionary in built.notches:
			var key := "ramp" if int(n.kind) == 0 else "drive"
			if shown.has(key):
				continue
			shown[key] = true
			print("  EYE_%s %s" % [key, _eye(plan, edges, int(n.e), float(n.uc), 4.5, 1.4, 1.2)])
		for z: Array in built.zones:
			var col: Color = z[3]
			var key := "zone_%s" % ("red" if col == Kerbs.RED else ("yellow" if col == Kerbs.YELLOW else ("green" if col == Kerbs.GREEN else ("white" if col == Kerbs.WHITE else "blue"))))
			if shown.has(key) or float(z[2]) - float(z[1]) < 3.0:
				continue
			shown[key] = true
			print("  EYE_%s(%s) %s" % [key, z[4], _eye(plan, edges, int(z[0]), (float(z[1]) + float(z[2])) * 0.5, 2.6, 1.2, 0.0)])
		for nb: Array in built.numbers:
			print("  EYE_number(%s) %s" % [nb[2], _eye(plan, edges, int(nb[0]), float(nb[1]), 1.6, 0.9, 0.0)])
			break
		for w: Rect2 in built.wells_at:
			print("  EYE_well %s" % _eye_down(plan, w.get_center()))
			break
		if ch._batch.data().has("tree_grate"):
			for xf: Transform3D in ch._batch.data()["tree_grate"].xforms:
				if xf.basis.get_scale().x > 0.5:
					print("  EYE_grate %s" % _eye_down(plan, Vector2(xf.origin.x, xf.origin.z)))
					break
		for h: Array in built.heaves_at:
			print("  EYE_heave %s" % _eye_down(plan, (h[0] as Rect2).get_center()))
			break
		ch.queue_free()
	city.free()
	get_tree().quit()


## An EYE (true world x, metres over the ground, z, yaw, pitch) standing `back` metres out in the
## road from u along edge e, `side` metres along, looking at the kerb.
func _eye(plan: CityPlan, edges: Array, e: int, u: float, back: float, h: float, side: float) -> String:
	var a: Vector2 = edges[e][0]
	var b: Vector2 = edges[e][1]
	var n: Vector2 = edges[e][2]
	var dir := (b - a).normalized()
	var target := a + dir * u
	var cam := target - n * back + dir * side
	var d := target - cam
	var yaw := rad_to_deg(atan2(-d.x, -d.y))
	var pitch := -rad_to_deg(atan2(h - 0.2, d.length()))
	return "%.2f,%.2f,%.2f,%.1f,%.1f" % [cam.x, h, cam.y, yaw, pitch]


func _eye_down(plan: CityPlan, p: Vector2) -> String:
	var cam := p + Vector2(0.0, 2.2)
	return "%.2f,%.2f,%.2f,%.1f,%.1f" % [cam.x, 1.7, cam.y, 0.0, -38.0]
