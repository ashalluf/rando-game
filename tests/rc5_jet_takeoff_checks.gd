extends RefCounted
## The jet_takeoff refcam's fixes (JetTakeoff, scripts/vehicles/jet_takeoff.gd), for
## tests/smoke_test.gd: the camera row and its staging keys; aircraft_lights.gdshader's flash_hold
## is there and off by default (strobes and beacons flash as before in play); jet_beam.gdshader is
## additive and fog-free; the edge lights' feet are found (runway white and taxiway blue); the
## shimmer grows only near take-off thrust; a departure carries three landing beams and its
## shimmer cones lengthen at full thrust; JET_TAKEOFF=0 changes none of it.
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
			if String(c.get("name", "")) == "jet_takeoff":
				row = c
	_check(not row.is_empty() and String(row.get("air", "")) == "takeoff" and absf(float(row.get("hour", 0.0)) - 19.25) < 0.01 and bool(row.get("air_flash", false)),
		"cameras_w8.json has jet_takeoff: a take-off staged at 19:15 with its strobes held")
	var lights := FileAccess.get_file_as_string("res://shaders/aircraft_lights.gdshader")
	_check(lights.contains("uniform float flash_hold : hint_range(0.0, 1.0) = 0.0;"), "aircraft_lights.gdshader has flash_hold, off by default")
	var beam := FileAccess.get_file_as_string("res://shaders/jet_beam.gdshader")
	_check(beam.contains("blend_add") and beam.contains("fog_disabled"), "the landing beams are additive and fog-free (the additive fog trap)")
	var refcam := FileAccess.get_file_as_string("res://tools/refcams/refcams_shot.gd")
	_check(refcam.contains("\"air_frames\"") and refcam.contains("\"air_flash\""), "refcams_shot.gd handles the air_frames and air_flash keys")
	_check(is_equal_approx(JetTakeoff.plume_scale(0.3), 1.0) and is_equal_approx(JetTakeoff.plume_scale(1.0), JetTakeoff.PLUME_GAIN),
		"the shimmer keeps its old length at idle and grows to PLUME_GAIN at take-off thrust")
	_check(is_equal_approx(JetTakeoff.bend(0.0055, 0.3), 0.0055), "the shimmer's bend is the old one at idle")
	var was: bool = JetTakeoff.enabled
	JetTakeoff.enabled = false
	_check(is_equal_approx(JetTakeoff.fitted_span(36.0, 32.0), 36.0), "JET_TAKEOFF=0: the old span")
	_check(is_equal_approx(JetTakeoff.plume_scale(1.0), 1.0) and is_equal_approx(JetTakeoff.bend(0.0055, 1.0), 0.0055),
		"JET_TAKEOFF=0: the old shimmer at full thrust")
	JetTakeoff.enabled = was


func _check_live(city: Node3D) -> void:
	var plan = city.get("plan")
	var m: MacroMap = plan.macro if plan else null
	if m == null:
		_check(false, "the jet checks have the city's map")
		return
	var spots: Array = Airport.edge_light_spots(m)
	var white := spots.filter(func(s: Array) -> bool: return bool(s[1])).size()
	_check(white > 20 and spots.size() - white > 20, "the field's edge lights' feet: %d runway, %d taxiway" % [white, spots.size() - white])
	var all_off_runway := true
	var hw: float = m.runway_width * 0.5
	for s: Array in spots:
		var p: Vector3 = s[0]
		for z: float in m.runway_zs:
			if absf(p.z - z) < hw:
				all_off_runway = false
	_check(all_off_runway, "no edge light's glow is laid on a runway's pavement")
	var air: Node = city.get_node_or_null("AirTraffic")
	if air == null or (not bool(air.get("_ready_done")) and not bool(air.call("_setup"))):
		_check(false, "the jet checks have AirTraffic")
		return
	var name := "departure_%d_left" % Aircraft.Kind.AIRLINER
	var lift: float = float((air.get("routes")[name] as AirRoute).marks.liftoff)
	var jet: AmbientJet = air.call("spawn_departure", Aircraft.Kind.AIRLINER, lift - 20.0, true)
	if jet == null:
		_check(false, "a departure spawned for the jet checks")
		return
	_check(jet.get("_beams").size() == 3, "a departure carries three landing-light beams")
	_check(jet.wingspan < 35.0 and jet.wingspan > 25.0 or OS.has_feature("web"), "the airliner's nav lights hang at the model's own span (%.1f m, not the old 36)" % jet.wingspan)
	var lo = (jet.get("_light_mat") as ShaderMaterial).get_shader_parameter("landing_on")
	_check(lo != null and float(lo) > 0.5, "a jet that starts out rolling has its landing lights on")
	jet.engine_level = 1.0
	jet.life = AmbientCraft.Life.FLYING
	jet.call("_update_shimmer")
	var shimmers: Array = jet.get("_shimmers")
	var grown := not shimmers.is_empty()
	for s in shimmers:
		if (s as Node3D).transform.basis.get_scale().y < 26.0 * (jet.length / 38.0) * (JetTakeoff.PLUME_GAIN - 0.05):
			grown = false
	_check(grown or OS.has_feature("web"), "at take-off thrust the shimmer cones run PLUME_GAIN times their idle length")
	jet.call("remove")


func _check(ok: bool, label: String) -> void:
	_t.call("_check", ok, label)
