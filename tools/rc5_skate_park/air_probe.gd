extends SceneTree
## Lists the clock times (SKATE_T / a refcam row's "skate_t") when each of THE PIT's riders is in the
## air, with where (park-local) and how high over the surface. Headless, seconds:
##   godot --headless --path . --script tools/rc5_skate_park/air_probe.gd [-- --from=0 --to=60 --rider=0]

func _initialize() -> void:
	var life: GDScript = load("res://scripts/world/skate_park_life.gd")
	var riders: Array = life.get_script_constant_map()["RIDERS"]
	var from := 0.0
	var to := 40.0
	var only := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--from="): from = a.get_slice("=", 1).to_float()
		if a.begins_with("--to="): to = a.get_slice("=", 1).to_float()
		if a.begins_with("--rider="): only = a.get_slice("=", 1).to_int()
	for i in riders.size():
		if only >= 0 and i != only:
			continue
		var r: Array = riders[i]
		var was := false
		var t := from
		while t < to:
			var at: Array = life.at(String(r[0]), t * float(r[2]) + float(r[1]))
			var p: Vector3 = (at[0] as Transform3D).origin
			var air: bool = int(at[1]) == 2
			if air:
				var over: float = p.y - SkatePark.surface_y(Vector2(p.x, p.z))
				if over > 0.25:
					print("AIR rider %d (%s) t %.2f at %.1f,%.2f,%.1f over %.2f flip %.2f" % [i, r[0], t, p.x, p.y, p.z, over, float(at[2])])
			was = air
			t += 0.1
	quit()
