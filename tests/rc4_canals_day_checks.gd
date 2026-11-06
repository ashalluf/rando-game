extends RefCounted
## Marisol Canals by day from a footbridge (Rc4Canals, the canals_day reference camera in
## tools/refcams/cameras_w7.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the water's pass (no engine specular on Compatibility, calmer, murkier) is in the shader
## and off by default; the coping's water face runs down past the bank's top row (the slot that drew
## a dark strip down every canal); the face and end walls take the ground lift; more boats on the
## banks; the bank planting and the bank shader's pass; the bridge railing's painted finish; the
## camera row stands on a footbridge's deck; RC4_CANALS=0 puts every number back.

var _t: Object


func run(t: Object) -> void:
	_t = t
	var was := Rc4Canals.enabled
	Rc4Canals.enabled = true
	_water()
	_coping()
	_banks()
	_rail()
	_camera()
	Rc4Canals.enabled = false
	_t._check(is_equal_approx(Rc4Canals.cope_foot(), Canals.BANK_TOP_Y - 0.05)
		and Rc4Canals.bank_boat_odds() == Canals.BANK_BOAT_ODDS,
		"RC4_CANALS=0: the old coping face and the old boat odds")
	Rc4Canals.enabled = was


func _water() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/canal_water.gdshader")
	_t._check(src.contains("uniform float rc4 = 0.0;"), "the canal water's pass is off by default (the A/B)")
	var i := src.find("RENDERER_COMPATIBILITY\n\tif (rc4 > 0.5)")
	_t._check(i > 0 and src.find("SPECULAR = 0.0;", i) > i,
		"on Compatibility the engine's own sky reflection is off under the pass (the mirror carries the sky)")
	_t._check(src.contains("mix(1.0, 0.45, rc4)"), "the ruffle is calmer under the pass")
	var wm := ShaderMaterial.new()
	Rc4Canals.water(wm)
	_t._check(float(wm.get_shader_parameter("rc4")) == 1.0, "Rc4Canals.water() switches the pass on")


func _coping() -> void:
	# The face must reach under the bank's top row (offset COPE_IN - 0.4), or a slot opens.
	var row := Canals.bank_y(Canals.COPE_IN - 0.4)
	_t._check(Rc4Canals.cope_foot() < row and Rc4Canals.cope_foot() < Canals.BANK_TOP_Y - 0.05,
		"the coping's water face runs down past the bank's top row (%.2f < %.2f)" % [Rc4Canals.cope_foot(), row])
	var src := FileAccess.get_file_as_string("res://scripts/world/canals.gd")
	_t._check(src.count("Rc4Canals.lift(ch,") >= 4, "the coping face and the end walls take the ground lift")
	var ch := CityChunk.new()
	_t._check(Rc4Canals.lift(ch, Vector2(-770.0, -50.0)) == 0.0, "no plan: no lift")
	ch.free()


func _banks() -> void:
	_t._check(Rc4Canals.bank_boat_odds() > Canals.BANK_BOAT_ODDS * 2.0,
		"more boats tied to the banks (%.2f of the lots)" % Rc4Canals.bank_boat_odds())
	var src := FileAccess.get_file_as_string("res://scripts/world/canals.gd")
	var a := src.find("ch._batch.add(\"shrub_%d\"")
	var b := src.find("Rc4Canals.bank_planting(")
	_t._check(a > 0 and b > a, "the extra bank planting comes after the old rolls")
	var bank := FileAccess.get_file_as_string("res://shaders/canal_bank.gdshader")
	_t._check(bank.contains("uniform float rc4 = 0.0;") and src.contains("sm.set_shader_parameter(\"rc4\""),
		"the bank shader's pass is off by default and set by the canals")


func _rail() -> void:
	var m := Rc4Canals.rail_material() as StandardMaterial3D
	_t._check(m != null and m.albedo_texture != null and m.vertex_color_use_as_albedo,
		"the bridge railing wears a textured painted finish over its vertex colour")
	var kit := FileAccess.get_file_as_string("res://scripts/world/canal_kit.gd")
	_t._check(kit.contains("\"rail_paint\" if Rc4Canals.enabled else \"paint\""), "the bridge mesh picks it under the pass")


func _camera() -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w7.json", FileAccess.READ)
	_t._check(f != null, "tools/refcams/cameras_w7.json exists")
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	var row: Dictionary = {}
	for c: Dictionary in (data as Dictionary).get("cameras", []):
		if String(c.get("name", "")) == "canals_day":
			row = c
	_t._check(not row.is_empty() and float(row.get("hour", 0.0)) == 11.0 and String(row.get("weather", "")) == "clear",
		"the canals_day camera is in the table at 11:00 clear")
	if row.is_empty():
		return
	# On Heron Canal's southern footbridge (x -773.9, z -55.9): within its deck's half span and width.
	var eye: Array = row.eye
	var dx := absf(float(eye[0]) - (-773.915))
	var dz := absf(float(eye[2]) - (-55.875))
	_t._check(dx < CanalKit.BRIDGE_HALF - 1.0 and dz < CanalKit.BRIDGE_W * 0.5,
		"the camera stands on the footbridge's deck (%.1f across, %.1f along)" % [dx, dz])
