extends Node
## What the city sounds like at a handful of places, headless (the mix report in docs/HANDOFF):
##   godot --headless --path . res://tools/audio_probe.tscn            (env PLACES=a,b,... HOUR=h)
## (a scene, not --script: it names Ambience and CityChunk, which need the autoloads.)
## Loads the city, moves the player to each place (true world; found from the plan where the
## place is a kind of thing - the river, a plaza, a playground, the hills), lets the chunks stream
## in with their collision, and runs the Ambience survey there: the acoustic space (weights), the
## World reverb it asks for, gunfire's echo taps, the beds and emitters above 5 %, the one-shots
## per minute, and the footstep surface under the listener.

const PLACES := ["canyon", "underpass", "street", "river", "plaza", "playground", "trench", "beach", "hills"]


func _ready() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	add_child(city)
	for i in 30:
		await get_tree().process_frame
	var plan: CityPlan = city.get("plan")
	var amb := city.get_node("Ambience") as Ambience
	amb.frozen = true
	var hour := float(OS.get_environment("HOUR")) if OS.get_environment("HOUR") != "" else 12.0
	var want: Array = Array(OS.get_environment("PLACES").split(",", false)) if OS.get_environment("PLACES") != "" else PLACES
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for name: String in want:
		var at := _place(name, plan)
		if at == Vector3.INF:
			print("PLACE %s: not found" % name)
			continue
		player.global_position = WorldState.to_local(at + Vector3.DOWN * 1.7)
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO
		city.call("update_streaming", true)
		for i in 40:
			await get_tree().physics_frame
		var eye := WorldState.to_local(at)
		amb._survey(eye)
		var night := 1.0 if hour < 5.5 or hour > 19.5 else 0.0
		var lv := amb.levels_for(amb.scene, hour, night, {"rain": 0.0, "storm": 0.0, "waves": 1.0})
		var rt := amb.rates_for(amb.scene, hour, night, {"rain": 0.0, "storm": 0.0, "waves": 1.0})
		var sp: Array = []
		for k: String in amb.space:
			if float(amb.space[k]) > 0.05:
				sp.append([float(amb.space[k]), k])
		sp.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var verb := amb.reverb_for(amb.space)
		var prof := amb.echo_for(amb.scene, amb.space)
		var taps: PackedStringArray = []
		for tp: Array in prof.get("taps", []):
			taps.append("%d ms %.0f dB" % [int(float(tp[0]) * 1000.0), float(tp[1])])
		var beds: PackedStringArray = []
		for k: String in lv:
			if float(lv[k]) > 0.05:
				beds.append("%s %.2f" % [k, float(lv[k])])
		var shots: PackedStringArray = []
		for k: String in rt:
			if float(rt[k]) > 0.05:
				shots.append("%s %.1f" % [k, float(rt[k])])
		var walls: PackedStringArray = []
		for d: float in amb.scene.get("walls", PackedFloat32Array()):
			walls.append("-" if d == INF else "%.0f" % d)
		var space_state := get_viewport().world_3d.direct_space_state
		var q := PhysicsRayQueryParameters3D.create(eye, eye + Vector3.DOWN * 3.5, 1 | 4)
		q.exclude = [(player as CollisionObject3D).get_rid()]
		var hit := space_state.intersect_ray(q)
		var surf := Footsteps.surface_at(plan, Vector2(at.x, at.z), at.y - 1.7, hit.get("collider") if not hit.is_empty() else null)
		print("PLACE %s at (%.0f, %.1f, %.0f)" % [name, at.x, at.y, at.z])
		print("  space   %s" % ", ".join(sp.map(func(e: Array) -> String: return "%s %.2f" % [e[1], e[0]])))
		print("  probe   walls [%s] cover %.2f ceiling %s canyon %.2f" % [" ".join(walls), float(amb.scene.get("cover", 0.0)), str(snappedf(float(amb.scene.get("ceiling", INF)), 0.1)), float(amb.scene.get("canyon", 0.0))])
		print("  reverb  wet %.2f room %.2f damp %.2f predelay %.0f ms" % [verb.wet, verb.room, verb.damp, verb.delay])
		print("  echo    %s%s" % [", ".join(taps) if not taps.is_empty() else "none", "  (cutoff %.0f Hz)" % float(prof.cutoff) if prof.has("cutoff") else ""])
		print("  beds    %s" % ", ".join(beds))
		print("  events  %s /min" % ", ".join(shots))
		print("  feet    %s" % surf)
	get_tree().quit()


## A place's listening point (true world, at ear height).
func _place(name: String, plan: CityPlan) -> Vector3:
	var macro := plan.macro
	var dt: Vector2 = macro.downtown_center
	match name:
		"canyon":
			return _ear(plan, Vector2(2359.4, 880.0)) # Flower at Olympic
		"underpass":
			# Straight under the 110's deck nearest 5th St.
			var best := Vector2.INF
			for seg: Dictionary in macro.freeway.segments_in(Rect2(1845.0, -200.0, 400.0, 400.0)):
				var m: Vector2 = (seg.a + seg.b) * 0.5
				if macro.zone_at(m) == MacroMap.Zone.CITY and (best == Vector2.INF or m.distance_to(Vector2(2045.0, 2.0)) < best.distance_to(Vector2(2045.0, 2.0))):
					best = m
			return _ear(plan, best) if best != Vector2.INF else Vector3.INF
		"street":
			var bi := plan.block_index_at(Vector2(1500.0, -400.0))
			var r: Rect2 = plan.block(bi.x, bi.y).rect
			return _ear(plan, Vector2(r.position.x + 2.0, r.get_center().y))
		"river":
			var rv: LaRiver = macro.river
			if rv == null:
				return Vector3.INF
			var s := rv.length * 0.3
			var p: Vector2 = rv.at(s)[0]
			return Vector3(p.x + 2.5, rv.water_at(s) + 1.7, p.y)
		"plaza", "playground":
			var bi := plan.block_index_at(dt)
			for r in 40:
				for dx in range(-r, r + 1):
					for dz in [-r, r]:
						for pair: Vector2i in [Vector2i(dx, dz), Vector2i(dz, dx)]:
							var b := plan.block(bi.x + pair.x, bi.y + pair.y)
							if name == "plaza" and int(b.kind) == CityPlan.BlockKind.PLAZA:
								var c := (b.rect as Rect2).get_center()
								return _ear(plan, c + Vector2(12.0, 0.0))
							if name == "playground" and String(b.get("grounds", "")) != "":
								for f: Dictionary in Parks.plan_for(plan, bi.x + pair.x, bi.y + pair.y).get("fac", []):
									if f.t == "playground":
										return _ear(plan, (f.c as Vector2) + Vector2(18.0, 0.0))
		"trench":
			var lr := LightRail.of(plan)
			if lr == null:
				return Vector3.INF
			for i in lr.mode.size():
				if lr.mode[i] == LightRail.Mode.TRENCH and lr.street[i] - lr.rail[i] > 4.0:
					var p := lr.pts[i] + Vector2(-lr.dirs[i].y, lr.dirs[i].x) * (lr.half[i] + 1.5)
					return Vector3(p.x, lr.rail[i] + 1.7, p.y)
		"beach":
			for z in [-100.0, 100.0, -300.0]:
				var p := Vector2(macro.coast_x(z) + macro.beach_width * 0.5, z)
				if macro.zone_at(p) == MacroMap.Zone.BEACH:
					return _ear(plan, p)
		"suburb":
			for z in [0.0, 400.0, -400.0]:
				for x in [1300.0, 1500.0, 1700.0, -1100.0]:
					var p := Vector2(x, z)
					if macro.zone_at(p) == MacroMap.Zone.CITY and macro.district_at(p) == CityPlan.District.SUBURBS:
						var bi := plan.block_index_at(p)
						var r: Rect2 = plan.block(bi.x, bi.y).rect
						return _ear(plan, Vector2(r.position.x + 2.0, r.get_center().y))
		"hills":
			for x in [-600.0, -200.0, 200.0, 600.0]:
				for z in [-1200.0, -1300.0, -1400.0]:
					var p := Vector2(x, z)
					if macro.zone_at(p) == MacroMap.Zone.HILLS and macro.raw_height_at(p) > 200.0:
						return _ear(plan, p)
	return Vector3.INF


func _ear(plan: CityPlan, p: Vector2) -> Vector3:
	return Vector3(p.x, plan.macro.height_at(p) + CityChunk.SIDEWALK_TOP + 1.7, p.y)
