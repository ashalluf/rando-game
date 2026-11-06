extends Node
## The rush_hour refcam's freeway, headless (docs/HANDOFF.md "The freeway at rush hour"): loads the
## city at a spawn and prints, every PRINT_EVERY frames, the freeway cars TrafficManager keeps, how
## many stand within 400 m of the player on the route under him, their mean speed, how many show
## their brake lamps, RushHour's level and the cap:
##   godot --headless --path . res://tools/rc5_rush_hour/probe.tscn -- --spawn=3209.6,2882.5,86,-5 --hour=17.67
## FRAMES (600) and PRINT_EVERY (60) in the environment; RUSH_HOUR=0 the A/B.

func _ready() -> void:
	var root := get_tree().root
	await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	root.add_child(scene.instantiate())
	for i in 3:
		await get_tree().process_frame
	var city: Node = root.find_child("City", false, false)
	# BusyStreets.hour_now() reads the current scene's DayNight.
	get_tree().current_scene = city
	var tm: Node = city.get_node("Traffic")
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	_spawn = WorldState.to_world(player.global_position)
	if _env("Y", "") != "":
		_spawn.y = float(_env("Y", "0"))
	var frames := int(_env("FRAMES", "600"))
	var every := int(_env("PRINT_EVERY", "60"))
	for i in frames:
		await get_tree().process_frame
		# Hold the player on the spawn (headless he falls off the bridge and walks).
		player.global_position = WorldState.to_local(_spawn)
		player.set("velocity", Vector3.ZERO)
		if i % every != every - 1:
			continue
		var fw: Freeway = city.plan.macro.freeway
		var pw := WorldState.to_world(player.global_position)
		var near := 0
		var vsum := 0.0
		var braking := 0
		var ri_best := -1
		var best := INF
		for ri in fw.routes.size():
			var n: Array = fw.nearest_on(ri, Vector2(pw.x, pw.z))
			if float(n[1]) < best:
				best = float(n[1])
				ri_best = ri
		var anchor := float(fw.nearest_on(ri_best, Vector2(pw.x, pw.z))[0])
		for car: Vehicle in tm.freeway_cars:
			if is_instance_valid(car) and int(car.traffic.get("fw", -1)) == ri_best and absf(float(car.traffic.t) - anchor) < 400.0:
				near += 1
				vsum += float(car.traffic.get("v", car.traffic.speed))
				if car.light_brake:
					braking += 1
		var per_route := {}
		var hist := {}
		for car: Vehicle in tm.freeway_cars:
			if not is_instance_valid(car):
				continue
			var r := int(car.traffic.get("fw", -1))
			per_route[r] = int(per_route.get(r, 0)) + 1
			if r == ri_best:
				var b := floori((float(car.traffic.t) - anchor) / 100.0) * 100
				hist[b] = int(hist.get(b, 0)) + 1
		var keys := hist.keys()
		keys.sort()
		var hs := ""
		for k in keys:
			hs += "%d:%d " % [k, hist[k]]
		print("PROBE routes %s; along route %d (100 m bins from the player, +t): %s" % [str(per_route), ri_best, hs])
		print("PROBE frame %d: freeway cars %d (cap %d), route %d at %.0f m (%.1f m off): %d within 400 m, mean %.1f m/s, %d braking; level %.2f, can_spawn %s, drive %.0f us, player %s" % [
			i + 1, tm.freeway_cars.size(), tm._fw_cap(), ri_best, anchor, best, near, vsum / maxf(near, 1), braking,
			RushHour.now_level, PhysicsBudget.can_spawn(), tm.drive_usec, pw])
	get_tree().quit()


var _spawn := Vector3.ZERO


func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d
