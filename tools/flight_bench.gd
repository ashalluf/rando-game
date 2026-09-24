extends SceneTree
## Frame times during a scripted fast flight over the city, to measure streaming hitches.
##
##   godot --headless --path . --script tools/flight_bench.gd -- --nohud
##
## The player is flown along a fixed route (SPEED m/s, default 90 - jet speed, the hardest case
## for streaming - at HEIGHT metres, default 70) and every frame's real duration is recorded.
## Headless runs the dummy renderer, so this is the CPU side only: chunk building, the far city,
## scripts, physics - which is where a hitch while flying comes from. It moves the player by the
## frame's own duration (capped at the eight physics steps Godot would run), so a slow frame
## carries the player further, exactly as in the game.
##
## Prints one FLIGHT line: frames, median / p95 / p99 / worst frame in ms, frames over 33, 50
## and 100 ms, and the streamer's own counters where it has them. ROUTE=a|b picks the route.
##
## FIXED=1 moves the player 1/60 s of flight per frame whatever the frame took, so two builds fly
## exactly the same frames, and adds the process's CPU time for the flight (from /proc, so it is
## the work done rather than the wall clock) - on a shared, loaded machine the wall-clock numbers
## of two runs differ by more than any change being measured, the CPU total much less.
## FARCITY=1 builds the whole far city first, as the loading screen does on desktop (without it
## the far city past far_city_immediate_radius is built during the flight, as on the web).
func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	root.add_child(scene.instantiate())
	var speed := float(_env("SPEED", "90"))
	var height := float(_env("HEIGHT", "70"))
	# Across midtown, through downtown, then south over the industrial ground toward the port:
	# about four kilometres of new city, most of it streamed on the way.
	var route: Array[Vector2] = [Vector2(-600, 320), Vector2(700, 250), Vector2(1500, 280), Vector2(1450, 950)]
	if _env("ROUTE", "a") == "b":
		# North into the hills, then along the front range and back down to the coast.
		route = [Vector2(0, 0), Vector2(300, -1100), Vector2(-500, -1000), Vector2(-850, -200)]
	for i in 5:
		await process_frame
	var city: Node = root.get_child(root.get_child_count() - 1)
	var player: Node3D = get_first_node_in_group("player")
	var ws: Node = root.get_node("/root/WorldState")
	var police := city.get_node_or_null("Police")
	if police:
		police.set("enabled", false)
	var fixed := _env("FIXED", "") == "1"
	if _env("FARCITY", "") == "1" and city.has_method("finish_far_city"):
		city.call("finish_far_city")
	# CENSUS=1: every 20 frames, count the city blocks ahead (a 100-degree cone, 3 km) that no tier
	# draws - the holes a player flying this route actually looks at.
	var census := _env("CENSUS", "") == "1"
	var census_samples := 0
	var census_holes := 0
	var census_max := 0
	var seg := 0
	var pos := route[0]
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	var warm := 60
	var cpu0 := 0
	while seg < route.size() - 1:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000000.0
		last = now
		if warm > 0:
			warm -= 1
			dt = 0.0
			if warm == 0:
				cpu0 = _cpu_ms()
		else:
			times.append(dt * 1000.0)
		var step := speed * minf(dt, 8.0 / 60.0)
		if fixed and warm <= 0:
			step = speed / 60.0
		while step > 0.0 and seg < route.size() - 1:
			var to := route[seg + 1]
			var left := pos.distance_to(to)
			if left <= step:
				pos = to
				step -= left
				seg += 1
			else:
				pos += (to - pos).normalized() * step
				step = 0.0
		var dir := (route[mini(seg + 1, route.size() - 1)] - pos).normalized()
		var off: Vector3 = ws.get("world_offset")
		player.global_position = Vector3(pos.x - off.x, height, pos.y - off.z)
		player.set("velocity", Vector3(dir.x, 0.0, dir.y) * speed)
		if census and warm <= 0 and times.size() % 20 == 0:
			var h := _holes(city, Vector3(pos.x, height, pos.y), dir)
			census_samples += 1
			census_holes += h
			census_max = maxi(census_max, h)
			# The census itself is not part of the frame being measured.
			last = Time.get_ticks_usec()
	times.sort()
	var n := times.size()
	var over := func(ms: float) -> int:
		var c := 0
		for t in times:
			if t > ms:
				c += 1
		return c
	var total := 0.0
	for t in times:
		total += t
	var cpu := _cpu_ms() - cpu0
	print("FLIGHT frames=%d mean=%.1f p50=%.1f p95=%.1f p99=%.1f max=%.1f over33=%d over50=%d over100=%d total=%.1fs cpu=%.1fs cpu_per_frame=%.1fms" % [
		n, total / n, times[n / 2], times[int(n * 0.95)], times[int(n * 0.99)], times[n - 1],
		over.call(33.0), over.call(50.0), over.call(100.0), total / 1000.0, cpu / 1000.0, float(cpu) / n])
	if city.has_method("chunk_counts"):
		print("FLIGHT chunks ", city.call("chunk_counts"))
	if census:
		print("FLIGHT census samples=%d holes_total=%d holes_mean=%.1f holes_max=%d" % [census_samples, census_holes, float(census_holes) / maxi(census_samples, 1), census_max])
	quit()


## City blocks within 3 km ahead (a 100-degree cone round `dir`) that nothing draws: no installed
## chunk and no far city. Works on both the old far tier (drawn by tile distance, clipped at the
## camera's far plane) and the new one (per-block visibility).
func _holes(city: Node, eye: Vector3, dir: Vector2) -> int:
	var plan = city.get("plan")
	var sky: Node = city.get_node_or_null("Skyline")
	var player: Node3D = get_first_node_in_group("player")
	var cam: Camera3D = player.get_node("CameraRig/SpringArm3D/Camera3D")
	var here: Vector2i = plan.block_index_at(Vector2(eye.x, eye.z))
	var chunks: Dictionary = city.get("chunks")
	var holes := 0
	for dx in range(-32, 33):
		for dz in range(-32, 33):
			var k := Vector2i(here.x + dx, here.y + dz)
			var b: Dictionary = plan.block(k.x, k.y)
			var c: Vector2 = (b.rect as Rect2).get_center()
			var to := c - Vector2(eye.x, eye.z)
			if to.length() > 3000.0 or to.length() < 1.0 or to.normalized().dot(dir) < cos(deg_to_rad(50.0)):
				continue
			if int(plan.zone_at(c)) != 0 or int(b.kind) != 0 or plan.lots(k.x, k.y).is_empty():
				continue
			if chunks.has(k):
				continue
			var d3 := Vector3(c.x, plan.height_at(c) + 10.0, c.y).distance_to(eye)
			var drawn := false
			if d3 <= cam.far and sky:
				if sky.has_method("block_alpha"):
					drawn = float(sky.call("block_alpha", k)) > 0.001
				else:
					var tiles: Dictionary = sky.get("_tiles")
					var t := Vector2i(floori(float(k.x) / 6.0), floori(float(k.y) / 6.0))
					if tiles.has(t) and tiles[t] != null:
						var r0: Rect2 = plan.block(t.x * 6, t.y * 6).rect
						var r1: Rect2 = plan.block(t.x * 6 + 5, t.y * 6 + 5).rect
						var tc := (r0.position + r1.end) * 0.5
						var td := Vector3(tc.x, plan.height_at(tc) + 15.0, tc.y).distance_to(eye)
						drawn = td >= float(sky.get("draw_from")) - float(sky.get("fade_margin"))
			if not drawn:
				holes += 1
	return holes


## This process's user + system CPU time so far, in ms (Linux /proc; 0 elsewhere). Every thread
## counts, the render and physics threads too.
func _cpu_ms() -> int:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return 0
	var fields := f.get_as_text().split(")")[-1].strip_edges().split(" ")
	# After the ")" closing the name: state is field 3, utime 14 and stime 15 (1-based).
	return int((int(fields[11]) + int(fields[12])) * 10)


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback
