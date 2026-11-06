extends RefCounted
## The driver_rain refcam's fixes (DriverRain, scripts/vehicles/driver_rain.gd), for
## tests/smoke_test.gd: CarInterior's see-through glass carries the rain (car_glass_wet's beads, runs
## and wiper arcs, refracting the street) and its default is the old dry pane; the cabin's night fill
## and night-mode screens default off and DriverRain turns them on; car lamp halos fade out within
## `halo_near` of the eye (0 by default, the old 2-5 m fade), set on every lamp material
## PropFactory makes; DRIVER_RAIN=0 puts all of it back; the camera row and its staging exist.
## Untyped access to the city (autoloads, see smoke_test.gd).

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var glass_src := FileAccess.get_file_as_string("res://shaders/car_glass_open.gdshader")
	_check(glass_src.contains("uniform float rain_inside = 0.0;") and glass_src.contains("car_glass_wet.gdshaderinc"),
		"car_glass_open.gdshader carries the rain, off by default (the old dry pane)")
	_check(glass_src.contains("hint_screen_texture"), "the open glass refracts the street from the screen texture")
	var cab_src := FileAccess.get_file_as_string("res://shaders/car_interior.gdshader")
	_check(cab_src.contains("uniform float night_fill = 0.0;") and cab_src.contains("uniform float night_screens = 0.0;"),
		"car_interior.gdshader's night fill and night screens default off")
	var lights_src := FileAccess.get_file_as_string("res://shaders/car_lights.gdshader")
	_check(lights_src.contains("uniform float halo_near = 0.0;"), "car_lights.gdshader's near halo fade defaults off")
	# DriverRain on: the glass, the cabin and the lamps get their numbers; off: the old ones.
	var was: bool = DriverRain.enabled
	var glass := ShaderMaterial.new()
	glass.shader = load("res://shaders/car_glass_open.gdshader")
	var cabin := ShaderMaterial.new()
	cabin.shader = load("res://shaders/car_interior.gdshader")
	DriverRain.enabled = true
	DriverRain.apply(glass, cabin)
	_check(float(glass.get_shader_parameter("rain_inside")) == 1.0 and float(cabin.get_shader_parameter("night_fill")) > 0.0
		and float(cabin.get_shader_parameter("night_screens")) == 1.0 and DriverRain.halo_near() > 5.0,
		"DriverRain puts the rain on the open glass, the night look on the cabin and the near halo fade on")
	DriverRain.enabled = false
	DriverRain.apply(glass, cabin)
	_check(float(glass.get_shader_parameter("rain_inside")) == 0.0 and float(cabin.get_shader_parameter("night_fill")) == 0.0
		and float(cabin.get_shader_parameter("night_screens")) == 0.0 and DriverRain.halo_near() == 0.0,
		"DRIVER_RAIN=0: the dry pane, the old cabin, the old halos")
	DriverRain.enabled = was
	var lamp_mat: ShaderMaterial = PropFactory.vehicle_light_material(true, 0, 0, false)
	_check(absf(float(lamp_mat.get_shader_parameter("halo_near")) - DriverRain.halo_near()) < 0.001,
		"PropFactory's lamp materials carry DriverRain's halo_near")
	var ci_src := FileAccess.get_file_as_string("res://scripts/vehicles/car_interior.gd")
	_check(ci_src.contains("DriverRain.apply(_glass, _mat)"), "CarInterior hands its glass and cabin to DriverRain")
	var cams = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if cams is Dictionary:
		for c in cams.get("cameras", []):
			if String(c.get("name", "")) == "driver_rain":
				row = c
	_check(not row.is_empty() and row.has("cabin") and String(row.get("weather", "")) == "rain" and float(row.get("hour", 0.0)) >= 21.5,
		"cameras_w8.json has driver_rain with its cabin staging, at night in rain")
	_check(ResourceLoader.exists("res://tools/refcams/cabin_stage.gd"), "the refcam's cabin staging script exists")


func _check(ok: bool, label: String) -> void:
	_t.call("_check", ok, label)
