class_name SantaAnaFx
extends Node3D
## What a Santa Ana looks like near and far (Weather owns it and calls `drive()` every frame with
## the state's weight): leaves and litter tumbling past the player downwind and dust streaming
## low over the ground (two particle pools that follow the player), and a brush fire on a ridge
## of the front range (LaWeather.fire_site()): a column of smoke laid over by the wind, an orange
## glow and a line of flame on the hill after dark, and on Forward+ a light that colours the
## slope. Purely visual: nothing burns, nothing spreads. At zero weight it is hidden.

## Leaves and litter in the air round the player at full wind, and dust puffs.
@export var litter_amount: int = 90
@export var dust_amount: int = 26
## Wind speed the litter and dust are carried at (m/s).
@export var wind_speed: float = 13.0
## Smoke puffs in the column, how long one lives (s) and how fast it rises (m/s).
@export var plume_puffs: int = 56
@export var plume_life: float = 70.0
@export var plume_rise: Vector2 = Vector2(9.0, 15.0)
## Puff size at birth and at the top (m).
@export var plume_size: Vector2 = Vector2(90.0, 420.0)
## Width (m) of the fire's line and its glow's height.
@export var fire_width: float = 520.0
@export var glow_height: float = 260.0
## The fire light's energy and range at night (Forward+ only).
@export var light_energy: float = 9.0
@export var light_range: float = 900.0

var amount: float = 0.0
var site: Vector3 = Vector3.ZERO
var _litter: CPUParticles3D
var _dust: CPUParticles3D
var _plume: CPUParticles3D
var _smoke_mat: ShaderMaterial
var _glow: MeshInstance3D
var _glow_mat: ShaderMaterial
var _light: OmniLight3D
var _has_site: bool = false
var _web: bool = false


func _ready() -> void:
	_web = OS.has_feature("web")
	_build_litter()
	_build_dust()
	_build_plume()
	_build_glow()
	if not _web and RenderingServer.get_current_rendering_method() == "forward_plus":
		_light = OmniLight3D.new()
		_light.name = "FireLight"
		_light.light_color = Color(1.0, 0.45, 0.16)
		_light.omni_range = light_range
		_light.omni_attenuation = 1.4
		_light.shadow_enabled = false
		_light.light_energy = 0.0
		add_child(_light)
	visible = false


## A leaf or a scrap of paper, drawn once: an oval with a stem notch, alpha cut.
static func _leaf_texture() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var r := sqrt(u * u / 0.30 + v * v)
			var a := 1.0 - smoothstep(0.82, 0.95, r)
			var vein := 1.0 - 0.25 * exp(-u * u * 260.0)
			img.set_pixel(x, y, Color(vein, vein, vein, a))
	return ImageTexture.create_from_image(img)


func _build_litter() -> void:
	_litter = CPUParticles3D.new()
	_litter.name = "Litter"
	_litter.amount = litter_amount / 2 if _web else litter_amount
	_litter.lifetime = 4.5
	_litter.local_coords = false
	_litter.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_litter.emission_box_extents = Vector3(30.0, 4.0, 30.0)
	_litter.direction = Vector3(LaWeather.SANTA_ANA_DIR.x, 0.25, LaWeather.SANTA_ANA_DIR.y)
	_litter.spread = 30.0
	_litter.initial_velocity_min = wind_speed * 0.6
	_litter.initial_velocity_max = wind_speed * 1.1
	# Gusts lift and drop them: a little gravity against an up-tilted start.
	_litter.gravity = Vector3(0.0, -2.2, 0.0)
	_litter.angular_velocity_min = -720.0
	_litter.angular_velocity_max = 720.0
	_litter.angle_min = 0.0
	_litter.angle_max = 360.0
	_litter.scale_amount_min = 0.08
	_litter.scale_amount_max = 0.22
	_litter.damping_min = 0.0
	_litter.damping_max = 1.5
	# Dry leaves (sycamore brown, eucalyptus olive) and the odd scrap of paper.
	var tint := Gradient.new()
	tint.set_color(0, Color(0.42, 0.30, 0.16))
	tint.set_color(1, Color(0.86, 0.84, 0.78))
	tint.add_point(0.45, Color(0.55, 0.43, 0.22))
	tint.add_point(0.7, Color(0.40, 0.42, 0.26))
	tint.add_point(0.88, Color(0.62, 0.52, 0.34))
	_litter.color_initial_ramp = tint
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.08, Color(1, 1, 1, 1))
	fade.add_point(0.88, Color(1, 1, 1, 1))
	_litter.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _leaf_texture()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.8
	mat.backlight_enabled = true
	mat.backlight = Color(0.35, 0.28, 0.14)
	quad.material = mat
	_litter.mesh = quad
	_litter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_litter.visibility_aabb = AABB(Vector3(-80, -20, -80), Vector3(160, 60, 160))
	_litter.emitting = false
	add_child(_litter)


func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "Dust"
	_dust.amount = dust_amount / 2 if _web else dust_amount
	_dust.lifetime = 5.0
	_dust.local_coords = false
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(38.0, 1.5, 38.0)
	_dust.direction = Vector3(LaWeather.SANTA_ANA_DIR.x, 0.05, LaWeather.SANTA_ANA_DIR.y)
	_dust.spread = 12.0
	_dust.initial_velocity_min = wind_speed * 0.7
	_dust.initial_velocity_max = wind_speed * 1.2
	_dust.gravity = Vector3(0.0, 0.25, 0.0)
	_dust.angle_min = 0.0
	_dust.angle_max = 360.0
	_dust.scale_amount_min = 3.5
	_dust.scale_amount_max = 8.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.0))
	_dust.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.3, Color(1, 1, 1, 0.16))
	fade.add_point(0.7, Color(1, 1, 1, 0.1))
	_dust.color_ramp = fade
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = WeaponFX.puff_texture()
	mat.albedo_color = Color(0.78, 0.66, 0.5)
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.backlight_enabled = true
	mat.backlight = Color(0.5, 0.42, 0.3)
	if not _web:
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 1.5
	quad.material = mat
	_dust.mesh = quad
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust.visibility_aabb = AABB(Vector3(-100, -20, -100), Vector3(200, 60, 200))
	_dust.emitting = false
	add_child(_dust)


func _build_plume() -> void:
	_plume = CPUParticles3D.new()
	_plume.name = "SmokeColumn"
	_plume.amount = plume_puffs
	_plume.lifetime = plume_life
	# Local: the column rides the emitter when the origin re-centres.
	_plume.local_coords = true
	_plume.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_plume.emission_box_extents = Vector3(fire_width * 0.35, 20.0, 60.0)
	_plume.direction = Vector3.UP
	_plume.spread = 10.0
	_plume.initial_velocity_min = plume_rise.x
	_plume.initial_velocity_max = plume_rise.y
	# The wind lays the column over toward the sea as it rises.
	_plume.gravity = Vector3(LaWeather.SANTA_ANA_DIR.x, 0.0, LaWeather.SANTA_ANA_DIR.y) * 0.55
	_plume.damping_min = 0.02
	_plume.damping_max = 0.08
	_plume.angle_min = 0.0
	_plume.angle_max = 360.0
	_plume.scale_amount_min = plume_size.y * 0.75
	_plume.scale_amount_max = plume_size.y
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, plume_size.x / plume_size.y))
	grow.add_point(Vector2(1.0, 1.0))
	_plume.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.06, Color(1, 1, 1, 0.85))
	fade.add_point(0.55, Color(1, 1, 1, 0.55))
	_plume.color_ramp = fade
	# The red channel is a per-puff seed for the billow (brush_smoke.gdshader).
	var seeds := Gradient.new()
	seeds.set_color(0, Color(0, 1, 1, 1))
	seeds.set_color(1, Color(1, 1, 1, 1))
	_plume.color_initial_ramp = seeds
	var quad := QuadMesh.new()
	_smoke_mat = ShaderMaterial.new()
	_smoke_mat.shader = load("res://shaders/brush_smoke.gdshader")
	quad.material = _smoke_mat
	_plume.mesh = quad
	_plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plume.visibility_aabb = AABB(Vector3(-4000, -100, -4000), Vector3(8000, 2600, 8000))
	_plume.emitting = false
	# Fill the column at once: a plume that has to grow for a minute after a still loads is none.
	_plume.preprocess = plume_life
	add_child(_plume)


func _build_glow() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = load("res://shaders/fire_glow.gdshader")
	_glow = MeshInstance3D.new()
	_glow.name = "FireGlow"
	_glow.mesh = quad
	_glow.material_override = _glow_mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.extra_cull_margin = 2000.0
	add_child(_glow)


## Called by Weather each frame. `weight` the Santa Ana's blend, `plan` the city plan (for the
## fire's site), `night` the lamps' night ramp (DayNight.lamp_now), `sun_col` / `amb_col` linear
## light on the smoke, `sun` the direction back to the sun.
func drive(weight: float, plan: Variant, night: float, sun_col: Color, amb: Color, sun: Vector3, player: Node3D) -> void:
	amount = weight
	var on := weight > 0.01
	if visible != on:
		visible = on
	_litter.emitting = on and weight > 0.35 and player != null
	_dust.emitting = _litter.emitting
	_plume.emitting = on
	if not on:
		if _light:
			_light.light_energy = 0.0
		return
	if not _has_site:
		site = LaWeather.fire_site(plan)
		_has_site = true
		_glow_mat.set_shader_parameter("seed", float(absi(hash(site)) % 997))
	if player:
		var p := player.global_position
		var up := Vector3(LaWeather.SANTA_ANA_DIR.x, 0.0, LaWeather.SANTA_ANA_DIR.y)
		# Emit upwind of the player, so the wind carries everything past.
		_litter.global_position = p - up * 18.0 + Vector3(0.0, 2.5, 0.0)
		_dust.global_position = p - up * 28.0 + Vector3(0.0, 0.8, 0.0)
	var local := WorldState.to_local(site)
	_plume.global_position = local + Vector3(0.0, 30.0, 0.0)
	_glow.global_transform = Transform3D(Basis.from_scale(Vector3(fire_width, glow_height, 1.0)), local + Vector3(0.0, -20.0, 0.0))
	_smoke_mat.set_shader_parameter("opacity", clampf(weight * 1.2, 0.0, 1.0))
	_smoke_mat.set_shader_parameter("fire_y", local.y)
	_smoke_mat.set_shader_parameter("sun_dir", sun)
	_smoke_mat.set_shader_parameter("light_col", Vector3(sun_col.r, sun_col.g, sun_col.b))
	_smoke_mat.set_shader_parameter("amb_col", Vector3(amb.r, amb.g, amb.b))
	_smoke_mat.set_shader_parameter("glow_col", Vector3(0.9, 0.28, 0.06) * (0.15 + 0.85 * night) * weight)
	_glow_mat.set_shader_parameter("level", weight * (0.12 + 0.88 * night))
	if _light:
		_light.global_position = local + Vector3(0.0, 120.0, 0.0)
		_light.light_energy = light_energy * night * weight
		_light.visible = _light.light_energy > 0.01
