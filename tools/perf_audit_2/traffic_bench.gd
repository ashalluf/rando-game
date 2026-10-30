extends Node
## What TrafficManager's physics tick costs, piece by piece, headless (docs/HANDOFF.md, the
## perf-audit-2 section). Loads the city at a spawn, lets it stream SETTLE frames, then switches
## TrafficManager's own tick off and runs it by hand TICKS times, timing each part:
##   godot --headless --path . res://tools/perf_audit_2/traffic_bench.tscn -- --spawn=2359.4,880,0,12,2 --hour=12
## (a scene, so the autoloads exist before the traffic scripts compile)
## Prints BENCH lines (mean microseconds a tick) and the car counts. Read them against each other:
## the box's absolute numbers move with its load.

func _ready() -> void:
	var root := get_tree().root
	await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	root.add_child(scene.instantiate())
	for i in 3:
		await get_tree().process_frame
	var city: Node = root.find_child("City", false, false)
	var settle := int(_env("SETTLE", "400"))
	for i in settle:
		await get_tree().process_frame
	var tm: Node = city.get_node("Traffic")
	tm.set_physics_process(false)
	var ticks := int(_env("TICKS", "200"))
	var acc := {}
	var parts := ["_maintain", "_maintain_freeway", "_run_spawns", "_drive_streets", "_drive_loops", "_drive_freeway"]
	var dt := 1.0 / 60.0
	for i in ticks:
		await get_tree().physics_frame
		TrafficSignals.advance(dt)
		TrafficAI.clock += dt
		for p in parts:
			if (p == "_maintain" or p == "_maintain_freeway") and i % 30 != 0:
				continue
			var t0 := Time.get_ticks_usec()
			if p.begins_with("_drive"):
				tm.call(p, dt)
			else:
				tm.call(p)
			acc[p] = float(acc.get(p, 0.0)) + float(Time.get_ticks_usec() - t0)
	for p in parts:
		var n := ticks if not p.begins_with("_maintain") else ceili(ticks / 30.0)
		print("BENCH %-20s %9.1f us a call" % [p, float(acc.get(p, 0.0)) / n])
	# MICRO=1: the pieces of one car's street tick, each over every street car.
	if _env("MICRO", "1") != "0":
		var plan: CityPlan = tm.get("plan")
		var list: Array = (tm.get("cars") as Array).duplicate()
		var micro := {}
		for rep in 5:
			for car: Vehicle in list:
				if not is_instance_valid(car) or not car.is_traffic():
					continue
				var t: Dictionary = car.traffic
				var axis: int = t.axis
				var cross_axis := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
				var along: float = t.get("along", 0.0)
				var t0 := Time.get_ticks_usec()
				car.global_transform = car.global_transform
				var t1 := Time.get_ticks_usec()
				var ci := plan._index_at(cross_axis, along)
				plan.road_pos(cross_axis, ci)
				plan.road_width(cross_axis, ci)
				var t2 := Time.get_ticks_usec()
				plan.road_open(axis, int(t.index), along)
				var t3 := Time.get_ticks_usec()
				var idx := int(t.index)
				var r0 := Time.get_ticks_usec()
				if plan.macro.river: plan.macro.river.road_open(plan, axis, idx, along)
				var r1 := Time.get_ticks_usec()
				if plan.macro.marina: plan.macro.marina.road_open(plan, axis, idx, along)
				var r2 := Time.get_ticks_usec()
				Schools.road_closed(plan, axis, idx, along)
				var r3 := Time.get_ticks_usec()
				Cemetery.road_closed(plan, axis, idx, along)
				var r4 := Time.get_ticks_usec()
				FarmersMarket.road_closed(plan, axis, idx, along)
				var r5 := Time.get_ticks_usec()
				var fr := FreightRail.of(plan)
				if fr: fr.road_open(axis, idx, along)
				var r6 := Time.get_ticks_usec()
				var r6b := Time.get_ticks_usec()
				var nsites := 0
				for st: Dictionary in plan.sites():
					nsites += 1
					if axis == CityPlan.AXIS_X and (idx <= st.ix0 or idx >= st.ix1):
						continue
					plan._site_bounds(st)
				var r7 := Time.get_ticks_usec()
				micro["sites n"] = float(micro.get("sites n", 0.0)) + nsites
				micro["ro sites"] = float(micro.get("ro sites", 0.0)) + float(r7 - r6b)
				for pair in [["ro river", r1 - r0], ["ro marina", r2 - r1], ["ro schools", r3 - r2], ["ro cemetery", r4 - r3], ["ro market", r5 - r4], ["ro freight", r6 - r5]]:
					micro[pair[0]] = float(micro.get(pair[0], 0.0)) + float(pair[1])
				t3 = Time.get_ticks_usec()
				var wp := WorldState.to_world(car.global_position)
				tm.call("_relief", Vector2(wp.x, wp.z))
				var t4 := Time.get_ticks_usec()
				car._tick_lights(1.0 / 60.0)
				var t5 := Time.get_ticks_usec()
				for pair in [["transform", t1 - t0], ["plan index/pos/width", t2 - t1], ["road_open", t3 - t2], ["relief", t4 - t3], ["tick_lights", t5 - t4]]:
					micro[pair[0]] = float(micro.get(pair[0], 0.0)) + float(pair[1])
		for k in micro:
			print("MICRO %-22s %8.1f us a car" % [k, float(micro[k]) / (5.0 * list.size())])
		var kids := 0
		for car in list:
			if is_instance_valid(car):
				kids += (car as Node).find_children("*", "Node3D", true, false).size()
		print("MICRO Node3D descendants a car: %.1f" % (float(kids) / maxf(list.size(), 1)))
	var pmd: Dictionary = tm.get("pm") if tm.get("pm") != null else {}
	for k in pmd:
		print("PMARK %-4s %8.1f us a tick" % [k, float(pmd[k]) / ticks])
	print("CARS streets %d freeway %d" % [(tm.get("cars") as Array).size(), (tm.get("freeway_cars") as Array).size()])
	get_tree().quit()


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return d if v == "" else v
