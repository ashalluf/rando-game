extends RefCounted
## The camera lens (docs/HANDOFF.md "The camera lens", CameraLens) for tests/smoke_test.gd.
## - The exposure's dark limit opens by day only (nights keep main's 200), the bright limit is
##   main's; the adaptation is slow into the dark, fast into the light, main-like when steady.
## - The sun flare's weight: none under the horizon, none in rain or under the marine layer.
## - Grain from the exposure: more with the camera opened up, never less than the user's grain.
## - The lens pass: the old grain and no flare by default (what CAMERA_LENS=0 draws), the flare
##   behind its weight, film grain behind lens_mode.
## - The bloom spread: a core and a long tail, the same total weight as Godot's default.
## - Live: the player's rig carries a Lens, the camera's limits and the city's lens layer follow it.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_t._check(CameraLens.enabled, "camera lens: on by default")
	_pure()
	_shader()
	await _live(city)


func _pure() -> void:
	var day := CameraLens.min_sensitivity_for(1.0, 0.0, 110.0, 200.0)
	var night := CameraLens.min_sensitivity_for(0.0, 1.0, 110.0, 200.0)
	_t._check(is_equal_approx(day, 110.0) and is_equal_approx(night, 200.0),
		"camera lens: the dark limit opens by day (%.0f) and stays main's at night (%.0f)" % [day, night])
	var dusk := CameraLens.min_sensitivity_for(0.5, 0.3, 110.0, 200.0)
	_t._check(dusk > day and dusk < night, "camera lens: the dark limit blends through dusk (%.0f)" % dusk)
	var into := CameraLens.speed_for(0.3, 0.42, 1.7, 0.75)
	var out := CameraLens.speed_for(-0.3, 0.42, 1.7, 0.75)
	var still := CameraLens.speed_for(0.0, 0.42, 1.7, 0.75)
	_t._check(into < still and out > still * 2.0 and is_equal_approx(still, 0.75),
		"camera lens: slow into the dark (%.2f), fast into the light (%.2f), steady between (%.2f)" % [into, out, still])
	_t._check(CameraLens.sun_weight(-0.1, 0.0, 0.0) == 0.0 and CameraLens.sun_weight(0.5, 0.0, 0.0) > 0.99,
		"camera lens: the flare is the sun's only while it is up")
	_t._check(CameraLens.sun_weight(0.5, 0.8, 0.0) < 0.01 and CameraLens.sun_weight(0.5, 0.0, 0.9) < 0.01,
		"camera lens: rain and the marine layer take the flare away")
	_t._check(CameraLens.dark_gain(110.0, 620.0, 0.0) == 0.0 and CameraLens.dark_gain(110.0, 620.0, 1.0) > 0.9
			and CameraLens.dark_gain(200.0, 620.0, 1.0) < CameraLens.dark_gain(110.0, 620.0, 1.0),
		"camera lens: the grain gain follows how far the camera opens up")
	var total := 0.0
	var old := 0.0
	for i in CameraLens.GLOW_LEVELS.size():
		total += CameraLens.GLOW_LEVELS[i]
		old += CameraLens.GLOW_LEVELS_OLD[i]
	_t._check(absf(total - old) < 0.05 and CameraLens.GLOW_LEVELS[1] > 0.0 and CameraLens.GLOW_LEVELS[5] > 0.0,
		"camera lens: the bloom has a core and a long tail at the old total weight (%.2f / %.2f)" % [total, old])


func _shader() -> void:
	var src: String = (load("res://shaders/vignette.gdshader") as Shader).code
	_t._check(src.contains("uniform float flare_amount = 0.0") and src.contains("if (flare_amount > 0.0)"),
		"camera lens: the lens pass draws no flare (and takes no tap) unless the flare has a weight")
	_t._check(src.contains("uniform int lens_mode = 0") and src.contains("lens_mode == 1")
			and src.contains("uniform float grain_gain = 1.0"),
		"camera lens: the old grain is the default; film grain only behind lens_mode")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vignette.gdshader")
	_t._check(float(mat.get_shader_parameter("flare_amount")) == 0.0, "camera lens: a fresh lens material has no flare")


func _live(city: Node3D) -> void:
	for i in 4:
		await _t.get_tree().process_frame
	var lens := _t.get_tree().get_first_node_in_group("camera_lens") as CameraLens
	_t._check(lens != null, "camera lens: the player's camera rig carries a Lens")
	if lens == null:
		return
	var cam := lens.get_parent().get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	var attrs := cam.attributes as CameraAttributesPractical if cam else null
	_t._check(attrs != null and is_equal_approx(attrs.auto_exposure_min_sensitivity, lens.min_sensitivity_now)
			and is_equal_approx(attrs.auto_exposure_max_sensitivity, lens.max_sensitivity),
		"camera lens: the player camera's exposure limits follow the lens (%.0f..%.0f)" % [
			attrs.auto_exposure_min_sensitivity if attrs else -1.0, attrs.auto_exposure_max_sensitivity if attrs else -1.0])
	_t._check(lens.speed_now > 0.0 and attrs != null and absf(attrs.auto_exposure_speed - lens.speed_now) <= 0.011,
		"camera lens: the adaptation speed is the lens's (%.2f)" % lens.speed_now)
	var layer := city.get_node_or_null("Vignette")
	var mat := (layer.get_child(0) as CanvasItem).material as ShaderMaterial if layer and layer.get_child_count() > 0 else null
	_t._check(mat != null and int(mat.get_shader_parameter("lens_mode")) == 1,
		"camera lens: the city's lens layer takes film grain")
	_t._check(mat != null and float(mat.get_shader_parameter("flare_amount")) == 0.0,
		"camera lens: no flare where it is not supported (headless, the web)")
	var env := cam.get_world_3d().environment if cam and cam.get_world_3d() else null
	_t._check(env != null and is_equal_approx(env.get_glow_level(1), CameraLens.GLOW_LEVELS[1])
			and is_equal_approx(env.get_glow_level(5), CameraLens.GLOW_LEVELS[5]),
		"camera lens: the city's bloom takes the wider spread")
	# The enclosure probe sees a lid: a box over the camera for a moment.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(30.0, 1.0, 30.0)
	cs.shape = sh
	body.add_child(cs)
	city.add_child(body)
	body.global_position = cam.global_position + Vector3(0.0, 4.0, 0.0)
	var seen := 0.0
	for i in 30:
		await _t.get_tree().physics_frame
		await _t.get_tree().process_frame
		seen = maxf(seen, lens.enclosure)
		if seen > 0.5:
			break
	body.queue_free()
	_t._check(seen > 0.5, "camera lens: a deck over the camera reads as enclosed (%.2f)" % seen)
