extends SceneTree
## The surf_dawn refcam's wave (SurfRide) without rendering: what SurfRide.stage_pick() finds round
## Z (default 800) at time 0 (the refcams' held TIME), the crests and gains near the break there, and
## an EYE for the shoulder shot. Headless, ~3 min (the city loads):
##   godot --headless --path . --script tools/rc5_surf_dawn/probe.gd   (Z=, GAIN= Weather.surf_gain)
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var m = plan.macro
	var SurfRide = load("res://scripts/world/surf_ride.gd")
	var SeaSurface = load("res://scripts/world/sea_surface.gd")
	var z := float(OS.get_environment("Z")) if OS.get_environment("Z") != "" else 800.0
	if OS.get_environment("GAIN") != "":
		current_scene.get_node("Weather").set("surf_gain", float(OS.get_environment("GAIN")))
	var st = SeaSurface.state(self)
	var shape = st[2]
	print("SHAPE ", shape, " EXTRA ", st[3])
	var zz := z - 40.0
	while zz <= z + 40.0:
		var line := "Z %.0f coast=%.1f" % [zz, m.coast_x(zz)]
		for n in [1.0, 2.0, 3.0]:
			var sc = SurfRide.crest_s(m, shape, zz, n, 0.0)
			line += "  n%d s=%.1f g=%.2f" % [int(n), sc, SeaSurface._wave_gain(n, SurfRide.point(m, zz, sc))]
		print(line)
		zz += 4.0
	var pick = SurfRide.stage_pick(m, st, z, 0.0)
	var rp = SurfRide.ride_point(m, st, pick.x, pick.y, 0.0)
	var sc = SurfRide.crest_s(m, shape, pick.x, pick.y, 0.0)
	print("EYE shoulder: rider at %.2f,%.2f crest_s=%.1f" % [m.coast_x(pick.x) - rp.x, pick.x, sc])
	print("PICK z=%.1f n=%d rider_s=%.1f x=%.2f y=%.2f slope=%.2f gain=%.2f" % [pick.x, int(pick.y), rp.x, m.coast_x(pick.x) - rp.x, rp.y, rp.z, SurfRide.gain(m, shape, pick.x, pick.y)])
	quit()
