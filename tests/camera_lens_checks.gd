extends RefCounted
## The camera lens (docs/HANDOFF.md "The camera lens", CameraLens) for tests/smoke_test.gd.
## - The exposure: main's clamps and speed, a compensation under a lid (more by day than at
##   night, none in the open or a street canyon), slow to open up and fast to close down.
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
	var open_noon := CameraLens.open_target(0.0, 1.0, 0.0, 2.6, 1.3, 0.3, 0.75)
	var lid_noon := CameraLens.open_target(0.9, 1.0, 0.0, 2.6, 1.3, 0.3, 0.75)
	var lid_night := CameraLens.open_target(0.9, 0.0, 1.0, 2.6, 1.3, 0.3, 0.75)
	_t._check(open_noon == 1.0 and is_equal_approx(lid_noon, 2.6) and is_equal_approx(lid_night, 1.3),
		"camera lens: the open street keeps main's exposure; a lid opens it up by day (%.2f), less at night (%.2f)" % [lid_noon, lid_night])
	_t._check(CameraLens.open_target(0.15, 1.0, 0.0, 2.6, 1.3, 0.3, 0.75) == 1.0,
		"camera lens: walls alone (a street canyon) do not open the camera")
	# One second each way: opening up is slow, closing down fast.
	var up := 1.0
	var down := 2.6
	for i in 30:
		up = CameraLens.adapt(up, 2.6, 1.0 / 30.0, 1.8, 0.35)
		down = CameraLens.adapt(down, 1.0, 1.0 / 30.0, 1.8, 0.35)
	_t._check(up > 1.2 and up < 2.0 and down < 1.1,
		"camera lens: a second in, the eye is part open (%.2f); a second out, it has closed (%.2f)" % [up, down])
	_t._check(CameraLens.sun_weight(-0.1, 0.0, 0.0) == 0.0 and CameraLens.sun_weight(0.5, 0.0, 0.0) > 0.99,
		"camera lens: the flare is the sun's only while it is up")
	_t._check(CameraLens.sun_weight(0.5, 0.8, 0.0) < 0.01 and CameraLens.sun_weight(0.5, 0.0, 0.9) < 0.01,
		"camera lens: rain and the marine layer take the flare away")
	_t._check(CameraLens.dark_gain(1.0, 2.6) == 0.0 and CameraLens.dark_gain(2.6, 2.6) == 1.0,
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
	var fresh: Variant = mat.get_shader_parameter("flare_amount")
	_t._check(fresh == null or float(fresh) == 0.0, "camera lens: a fresh lens material has no flare")


func _live(city: Node3D) -> void:
	for i in 4:
		await _t.get_tree().process_frame
	var lens := _t.get_tree().get_first_node_in_group("camera_lens") as CameraLens
	_t._check(lens != null, "camera lens: the player's camera rig carries a Lens")
	if lens == null:
		return
	var cam := lens.get_parent().get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	var attrs := cam.attributes as CameraAttributesPractical if cam else null
	_t._check(attrs != null and is_equal_approx(attrs.auto_exposure_min_sensitivity, 200.0)
			and is_equal_approx(attrs.auto_exposure_max_sensitivity, 620.0) and is_equal_approx(attrs.auto_exposure_speed, 0.6),
		"camera lens: the player camera keeps main's exposure limits and speed")
	var layer := city.get_node_or_null("Vignette")
	var mat := (layer.get_child(0) as CanvasItem).material as ShaderMaterial if layer and layer.get_child_count() > 0 else null
	_t._check(mat != null and int(mat.get_shader_parameter("lens_mode")) == 1,
		"camera lens: the city's lens layer takes film grain")
	var flare: Variant = mat.get_shader_parameter("flare_amount") if mat else null
	_t._check(mat != null and (flare == null or float(flare) == 0.0),
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
	var comp_under := lens.compensation_target
	body.queue_free()
	_t._check(seen > 0.5, "camera lens: a deck over the camera reads as enclosed (%.2f)" % seen)
	_t._check(comp_under > 1.0 and attrs != null and attrs.auto_exposure_scale > 0.4,
		"camera lens: under it the camera opens up (target %.2f, scale %.3f)" % [comp_under, attrs.auto_exposure_scale if attrs else 0.0])
