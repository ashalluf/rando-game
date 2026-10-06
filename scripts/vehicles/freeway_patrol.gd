class_name FreewayPatrol
extends Vehicle
## The highway patrol's car at a freeway incident (FreewayIncidents): the BASIN HIGHWAY PATROL, an
## invented agency - a black-and-white sedan (car_paint.gdshader stripe_mode 5, the police
## cruiser's livery), the cruiser's light bar flashing red and blue while it works a scene with an
## amber arrow stick behind (the bar's rear), the agency's name on the doors and an officer at the
## wheel. Always a traffic car of FreewayIncidents' (kinematic, no wheels, never the player's),
## until a hit knocks it out of the traffic like any other car. No siren, no police AI: it is not
## in the "police" groups and has no part in the wanted level.

const AGENCY := "BASIN HIGHWAY PATROL"
const LETTER_AT := Vector3(0.914, 0.66, -0.2)
const LETTER_SIZE := 0.06

## True while the bar flashes (at the scene, and on the way in).
var lights_on := true
var _bar_mat: ShaderMaterial
var _bar_light: OmniLight3D
var _phase := 0.0
var _night := 0.0
var _light_timer := 0.0


static func make(look: int) -> FreewayPatrol:
	var car := FreewayPatrol.new()
	car.setup(BodyType.SEDAN, PoliceCar.POLICE_BLACK, Addon.NONE)
	car.setup_look(Finish.GLOSS, Livery.NONE, PoliceCar.POLICE_WHITE)
	car.wheel_style = 0
	car.wheel_kit = 0
	car._phase = float(absi(hash([look, "fw_patrol"])) % 1000) / 1000.0
	car.traffic = {"fw_incident": true}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	return car


func _ready() -> void:
	super._ready()
	_build_bar()
	_add_lettering()


func _paint_material(albedo: Texture2D, normal: Texture2D) -> ShaderMaterial:
	var mat := super._paint_material(albedo, normal)
	mat.set_shader_parameter("stripe_color", PoliceCar.POLICE_WHITE)
	mat.set_shader_parameter("stripe_mode", 5)
	mat.set_shader_parameter("door_band", PoliceCar.DOOR_BAND)
	mat.set_shader_parameter("roof_from", 0.84)
	return mat


func _cabin_look() -> Dictionary:
	return CarCabin.police_look(false, hash([_phase, 41]))


func _build_bar() -> void:
	var dims := _dims()
	var top := _model_top_y if _has_model else 0.55 + float(dims.chassis_h) + float(dims.cabin_h)
	var bar := MeshInstance3D.new()
	bar.name = "LightBar"
	bar.mesh = PoliceCar.light_bar_mesh()
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = load("res://shaders/police_lights.gdshader")
	_bar_mat.set_shader_parameter("rate", 1.6)
	_bar_mat.set_shader_parameter("phase", _phase)
	_bar_mat.set_shader_parameter("energy", 7.0)
	bar.material_override = _bar_mat
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.visibility_range_end = 320.0
	bar.position = Vector3(0.0, top - 0.02, float(dims.length) * 0.05)
	add_child(bar)
	if not OS.has_feature("web"):
		_bar_light = OmniLight3D.new()
		_bar_light.name = "BarLight"
		_bar_light.omni_range = 14.0
		_bar_light.light_energy = 0.0
		_bar_light.shadow_enabled = false
		_bar_light.distance_fade_enabled = true
		_bar_light.distance_fade_begin = 90.0
		_bar_light.distance_fade_length = 30.0
		_bar_light.position = bar.position + Vector3(0.0, 0.35, 0.0)
		_bar_light.visible = false
		add_child(_bar_light)


func _add_lettering() -> void:
	if OS.has_feature("web"):
		return
	var mesh := BigVehicles.text_mesh(AGENCY, LETTER_SIZE, Color(0.04, 0.04, 0.05))
	for side: float in [1.0, -1.0]:
		var mi := MeshInstance3D.new()
		mi.name = "Lettering"
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = BigVehicles.LETTER_DISTANCE
		mi.basis = Basis(Vector3.UP, PI * 0.5 * side)
		mi.position = Vector3(side * LETTER_AT.x, LETTER_AT.y, LETTER_AT.z)
		add_child(mi)


func _process(delta: float) -> void:
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.5
		var day := get_tree().current_scene.get_node_or_null("DayNight") if get_tree().current_scene else null
		_night = 0.0 if day == null else maxf(float(day.get("night_factor")), float(day.get("weather_darken")) * 0.85)
	var lit := lights_on and is_traffic()
	if _bar_mat:
		_bar_mat.set_shader_parameter("lights_on", 1.0 if lit else 0.0)
	if _bar_light:
		var show := lit and _night > 0.05
		_bar_light.visible = show
		if show:
			var f := fposmod(Time.get_ticks_msec() / 1000.0 * 1.6 + _phase, 1.0)
			var side := 1 if (f < 0.09 or (f > 0.15 and f < 0.24)) else (-1 if ((f > 0.5 and f < 0.59) or (f > 0.65 and f < 0.74)) else 0)
			_bar_light.light_energy = 3.0 * _night * (1.0 if side != 0 else 0.0)
			_bar_light.light_color = Color(1.0, 0.12, 0.08) if side > 0 else Color(0.15, 0.3, 1.0)
