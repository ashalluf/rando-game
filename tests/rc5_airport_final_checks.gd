extends RefCounted
## The airport_final refcam's fixes (JetFinal, scripts/vehicles/jet_final.gd), for
## tests/smoke_test.gd: the camera row and its staging; airliner_livery.gdshader's pass is off by
## default (the parked jets and the shared liveries untouched); an arrival wears its own copy with
## the pass on, the city's glow on its belly over the city and none on the runway, the gear lamps
## with its landing lights; JET_FINAL=0 changes none of it.
## Untyped access to the city (autoloads, see smoke_test.gd).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_check_static()
	_check_live(city)


func _check_static() -> void:
	var cams = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if cams is Dictionary:
		for c in cams.get("cameras", []):
			if String(c.get("name", "")) == "airport_final":
				row = c
	_check(not row.is_empty() and String(row.get("air", "")) == "final" and absf(float(row.get("hour", 0.0)) - 19.5) < 0.01,
		"cameras_w8.json has airport_final: an arrival staged at 19:30")
	var sh := FileAccess.get_file_as_string("res://shaders/airliner_livery.gdshader")
	_check(sh.contains("uniform float final_look = 0.0;") and sh.contains("uniform vec3 under_glow = vec3(0.0);") and sh.contains("uniform float gear_light = 0.0;"),
		"airliner_livery.gdshader's night-approach pass is off by default")
	var shared: ShaderMaterial = AirportTerminal.livery_material(1)
	var fl = shared.get_shader_parameter("final_look")
	_check(fl == null or float(fl) < 0.5, "the shared livery material (the parked jets) keeps the old look")
	_check(is_zero_approx(JetFinal.under_share(0.0)) and is_zero_approx(JetFinal.under_share(JetFinal.UNDER_GROUND - 1.0)),
		"no city glow on a jet on the runway")
	_check(is_equal_approx(JetFinal.under_share(100.0), 1.0) and absf(JetFinal.under_share(5000.0) - JetFinal.UNDER_HIGH) < 0.001,
		"the full city glow low over the city, UNDER_HIGH of it high up")
	var was: bool = JetFinal.enabled
	JetFinal.enabled = false
	_check(JetFinal.material(shared) == shared, "JET_FINAL=0: the shared material")
	JetFinal.enabled = was


func _check_live(city: Node3D) -> void:
	var air: Node = city.get_node_or_null("AirTraffic")
	if air == null or (not bool(air.get("_ready_done")) and not bool(air.call("_setup"))):
		_check(false, "the final-approach checks have AirTraffic")
		return
	var jet: AmbientJet = air.call("spawn_arrival", Aircraft.Kind.AIRLINER, 1500.0, "arrival_south")
	if jet == null:
		_check(false, "an arrival spawned for the final-approach checks")
		return
	var mat: ShaderMaterial = jet.get("_final_mat")
	if not JetFinal.enabled:
		_check(mat == null, "JET_FINAL=0: the arrival wears the shared livery")
		jet.call("remove")
		return
	_check(mat != null and float(mat.get_shader_parameter("final_look")) > 0.5 and mat != AirportTerminal.livery_material(jet.livery),
		"an arrival wears its own livery copy with the night-approach pass")
	if mat:
		JetFinal.tick(mat, 100.0, true)
		var g: Vector3 = mat.get_shader_parameter("under_glow")
		_check(g.x > 0.05 and g.x > g.z and float(mat.get_shader_parameter("gear_light")) > 0.0,
			"low over the city its belly takes the warm glow, its gear the landing lights")
		JetFinal.tick(mat, 0.0, false)
		_check((mat.get_shader_parameter("under_glow") as Vector3).is_zero_approx() and is_zero_approx(float(mat.get_shader_parameter("gear_light"))),
			"on the runway with its lights off: none of it")
	jet.call("remove")


func _check(ok: bool, label: String) -> void:
	_t.call("_check", ok, label)
