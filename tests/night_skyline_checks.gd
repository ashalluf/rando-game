extends RefCounted
## The night skyline (NightSkyline, docs/HANDOFF.md "The night skyline"): checks for
## tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads. Under --headless no
## shader runs, so the rolls are held to their GDScript copies here and the sources are read to keep
## the near walls and the far boxes on the same functions; tools/glshot/still_shot.gd with
## NIGHT_SKYLINE=0 / 1 at a night aerial shows the pixels. Nothing here depends on state an earlier
## check left: the switch is put back as it was found.

var _t: Node


func run(t: Node, _city: Node3D = null) -> void:
	_t = t
	_global_and_switch()
	_shader_copies()
	_rolls_spread()
	_beacons_out_of_step()


## The shader global exists, and the switch drives it.
func _global_and_switch() -> void:
	_t._check(ProjectSettings.has_setting("shader_globals/night_skyline"), "night_skyline is a shader global")
	var was := NightSkyline.enabled
	NightSkyline.set_enabled(false)
	var off := float(RenderingServer.global_shader_parameter_get("night_skyline"))
	NightSkyline.set_enabled(true)
	var on := float(RenderingServer.global_shader_parameter_get("night_skyline"))
	NightSkyline.set_enabled(was)
	_t._check(is_equal_approx(off, 0.0) and is_equal_approx(on, 1.0),
		"NIGHT_SKYLINE switches the night_skyline global (off %.1f, on %.1f)" % [off, on])


## The near walls and the far boxes call the same shared functions with their own seed, and the
## include holds NightSkyline's numbers.
func _shader_copies() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/window_lights.gdshaderinc")
	var near := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	var far := FileAccess.get_file_as_string("res://shaders/building_lod.gdshader")
	var air := FileAccess.get_file_as_string("res://shaders/aircraft_lights.gdshader")
	_t._check(inc.contains("const float CLEANERS_FLOOR = %.3f;" % NightSkyline.CLEANERS_FLOOR),
		"the cleaners' floor share is NightSkyline.CLEANERS_FLOOR")
	var temps_ok := true
	for i in NightSkyline.TEMPS.size():
		var m: Vector3 = NightSkyline.TEMPS[i]
		var row := "t < %.2f) {\n\t\t\tm = vec3(%.2f, %.2f, %.2f);" % [NightSkyline.TEMP_EDGES[i], m.x, m.y, m.z]
		temps_ok = temps_ok and inc.contains(row)
	var c := NightSkyline.CLEANERS_TEMP
	temps_ok = temps_ok and inc.contains("m = vec3(%.2f, %.1f, %.2f);" % [c.x, c.y, c.z])
	_t._check(temps_ok, "window_temp()'s shares and colours are NightSkyline.TEMP_EDGES / TEMPS")
	_t._check(inc.contains("wl_roll(sd, 65u) < %.1f" % NightSkyline.CROWN_SHARE)
		and inc.contains("wl_roll(sd, 68u) < %.1f" % NightSkyline.FLOOD_SHARE),
		"tower_wash()'s shares are NightSkyline's")
	_t._check(near.contains("window_temp(seed, face_id, row, col)") and far.contains("window_temp(sd, face_id, row, col)"),
		"the near walls and the far boxes light an office in the same colour (window_temp)")
	_t._check(near.contains("tower_wash(seed, pt_size.y, v - pt_base_y, u,") and far.contains("tower_wash(sd, part_h, vp, uq,"),
		"the near walls and the far boxes wash the same towers (tower_wash)")
	_t._check(air.contains("global uniform float night_skyline;") and air.contains("fract(TIME * rate + v_phase)"),
		"the aviation beacons flash at their own rates")


## The rolls land where the plan says: about one floor in twenty-two a cleaners' floor, every
## colour of office in use, half the tall towers with a crown wash.
func _rolls_spread() -> void:
	var floors := 0
	var cleaners := 0
	var temps := {}
	for sd in range(0, 1000, 7):
		for row in 40:
			floors += 1
			if NightSkyline.cleaners_floor(sd, row):
				cleaners += 1
			for col in [0, 3, 6]:
				var k := NightSkyline.temp_index(sd, 1 + row % 4, row, col)
				temps[k] = int(temps.get(k, 0)) + 1
	var share := float(cleaners) / float(floors)
	_t._check(share > 0.03 and share < 0.065, "cleaners' floors are about 4.5 %% of all (%.3f)" % share)
	var all_used := true
	for k in [-1, 0, 1, 2, 3, 4]:
		all_used = all_used and temps.has(k)
	var own := float(temps.get(-1, 0)) / float(floors * 3)
	_t._check(all_used and own > 0.36 and own < 0.48,
		"offices come in every colour temperature, most in the building's own (%.2f; %s)" % [own, temps])
	var crowned := 0
	for sd in 1000:
		if NightSkyline.crown_washed(sd):
			crowned += 1
	_t._check(crowned > 440 and crowned < 560, "about half the tall towers wear a crown wash (%d of 1000)" % crowned)


## Every tower's beacons on their own phases: two towers with the same light layout in two places
## do not flash together, and no two lights of one tower share a phase.
func _beacons_out_of_step() -> void:
	var tower_a: Array[float] = []
	var tower_b: Array[float] = []
	for i in 8:
		var p := Vector3(cos(i * 0.785) * 15.4, 310.4, sin(i * 0.785) * 15.4)
		tower_a.append(NightSkyline.light_phase(p, i))
		tower_b.append(NightSkyline.light_phase(p + Vector3(0.0, -82.0, 0.0), i))
	var same := 0
	var close := 0
	for i in 8:
		if absf(tower_a[i] - tower_b[i]) < 0.03:
			same += 1
		for j in range(i + 1, 8):
			if absf(tower_a[i] - tower_a[j]) < 0.005:
				close += 1
	var ok := same <= 1 and close == 0
	for ph in tower_a + tower_b:
		ok = ok and ph >= 0.0 and ph < 1.0
	_t._check(ok, "the towers' aviation lights flash out of step (%d in step across towers, %d within one)" % [same, close])
