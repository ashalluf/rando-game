extends RefCounted
## The shadows review (fleet wave 5, `shadows-review`; docs/HANDOFF.md "Shadows across the game"),
## for tests/smoke_test.gd: ShadowTuning's cascades on the ground and in the air, the A/B, the
## clearance follow, and the hooks in Quality and DayNight. Headless draws no shadow, so the checks
## hold the numbers a sun is left with; tools/shadows_review/shadow_lab.tscn shows the pixels. Every
## sun it touches is its own (a fresh DirectionalLight3D), and the statics are put back.

var _t: Node


func run(t: Node, city: Node3D = null) -> void:
	_t = t
	var was_enabled := ShadowTuning.enabled
	var was_level := ShadowTuning.level
	_ground()
	_air()
	_ab()
	_hooks(city)
	await _follow()
	ShadowTuning.enabled = was_enabled
	ShadowTuning.level = was_level
	ShadowTuning.reset()


## On the street the cascades are the old ones (city.tscn's splits, Quality's reach); only the
## fade is longer.
func _ground() -> void:
	ShadowTuning.enabled = true
	ShadowTuning.reset()
	for lvl in 4:
		var sun := DirectionalLight3D.new()
		ShadowTuning.apply_level(sun, lvl)
		_t._check(is_equal_approx(sun.directional_shadow_max_distance, float(ShadowTuning.DISTANCE[lvl]))
			and is_equal_approx(sun.directional_shadow_split_1, float(ShadowTuning.OLD_SPLITS[0]))
			and is_equal_approx(sun.directional_shadow_split_3, float(ShadowTuning.OLD_SPLITS[2])),
			"on the ground level %d keeps the old reach and splits (%.0f m, %.3f / %.3f)" % [lvl,
			sun.directional_shadow_max_distance, sun.directional_shadow_split_1, sun.directional_shadow_split_3])
		_t._check(sun.directional_shadow_fade_start <= 0.85,
			"level %d fades its shadows over the last %d %% of the reach (8 %% drew the edge as a line)" % [lvl, roundi(100.0 * (1.0 - sun.directional_shadow_fade_start))])
		sun.free()
	_t._check(ShadowTuning.DISTANCE == [500.0, 380.0, 220.0, 120.0] and ShadowTuning.BLUR == [1.0, 1.0, 0.7, 0.7],
		"ShadowTuning's ground reach and blur are Quality's old numbers")


## In the air every cascade slides out, they stay in order, each a little over twice the last, and
## the reach stops at the cap (HIGH: the LOD ring). LOW and LOWEST never follow.
func _air() -> void:
	for a in [0.0, 40.0, 128.0, 300.0, 2000.0]:
		var e := ShadowTuning.ends(0, a)
		var ordered: bool = e[0] < e[1] and e[1] < e[2] and e[2] < e[3]
		_t._check(ordered and e[3] <= float(ShadowTuning.AIR_CAP[0]) + 0.01,
			"HIGH's cascades at %d m clearance end in order under the cap: %.0f / %.0f / %.0f / %.0f m" % [a, e[0], e[1], e[2], e[3]])
	var e128 := ShadowTuning.ends(0, 128.0)
	_t._check(float(e128[0]) > 60.0 and float(e128[3]) >= 590.0,
		"128 m up the first cascade starts out where the ground is (%.0f m) and the reach grows past the ground's (%.0f m)" % [e128[0], e128[3]])
	for i in 3:
		var r: float = float(e128[i + 1]) / float(e128[i])
		_t._check(r > 1.6 and r < 3.2, "128 m up cascade %d is %.1f x cascade %d (none wasted, none starved)" % [i + 2, r, i + 1])
	for lvl in [2, 3]:
		var low := ShadowTuning.ends(lvl, 200.0)
		_t._check(is_equal_approx(float(low[3]), float(ShadowTuning.DISTANCE[lvl])),
			"level %d keeps its reach in the air (%.0f m): the cheap levels never draw more shadow" % [lvl, low[3]])


## SHADOW_TUNING=0: the old numbers exactly, nothing touched but the reach and blur.
func _ab() -> void:
	ShadowTuning.enabled = false
	ShadowTuning.air = 200.0
	var sun := DirectionalLight3D.new()
	sun.directional_shadow_split_1 = 0.055
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.42
	sun.directional_shadow_fade_start = 0.92
	ShadowTuning.apply_level(sun, 0)
	_t._check(is_equal_approx(sun.directional_shadow_max_distance, 500.0) and is_equal_approx(sun.directional_shadow_fade_start, 0.92)
		and is_equal_approx(sun.directional_shadow_split_1, 0.055) and is_equal_approx(sun.shadow_blur, 1.0),
		"SHADOW_TUNING=0 leaves the sun as Quality and city.tscn set it (500 m, fade 0.92, split 0.055)")
	sun.free()
	ShadowTuning.enabled = true
	ShadowTuning.reset()


## The hooks: Quality's level applies it, DayNight's frame follows the camera, city.tscn's sun is the
## old one underneath.
func _hooks(city: Node3D) -> void:
	_t._check(FileAccess.get_file_as_string("res://scripts/util/quality.gd").contains("ShadowTuning.apply_level(_sun, i)"),
		"Quality applies ShadowTuning at every level change")
	_t._check(FileAccess.get_file_as_string("res://scripts/world/day_night.gd").contains("ShadowTuning.follow(_sun, get_viewport().get_camera_3d())"),
		"DayNight's frame lets the cascades follow the camera")
	var scene := FileAccess.get_file_as_string("res://scenes/levels/city.tscn")
	_t._check(scene.contains("directional_shadow_split_1 = 0.055") and scene.contains("directional_shadow_fade_start = 0.92"),
		"city.tscn's sun keeps the old splits and fade (the A/B's numbers)")
	if city and city.get_node_or_null("Sun"):
		var sun := city.get_node("Sun") as DirectionalLight3D
		_t._check(sun.directional_shadow_max_distance >= 120.0 and sun.directional_shadow_split_1 < sun.directional_shadow_split_2
			and sun.directional_shadow_split_2 < sun.directional_shadow_split_3,
			"the city's sun has ordered cascades (%.0f m, %.3f / %.3f / %.3f)" % [sun.directional_shadow_max_distance,
			sun.directional_shadow_split_1, sun.directional_shadow_split_2, sun.directional_shadow_split_3])


## The follow on a real world: a floor and a camera over it; the clearance rises at its rate, falls
## at once, and a camera on a roof keeps the street's cascades.
func _follow() -> void:
	var root := Node3D.new()
	(_t as Node).get_tree().root.add_child(root)
	var ground_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	ground_body.add_child(cs)
	ground_body.collision_layer = 1
	ground_body.position = Vector3(5000, -1, 5000)
	root.add_child(ground_body)
	var roof := StaticBody3D.new()
	var cs2 := CollisionShape3D.new()
	var box2 := BoxShape3D.new()
	box2.size = Vector3(30, 2, 30)
	cs2.shape = box2
	roof.add_child(cs2)
	roof.collision_layer = 1
	roof.position = Vector3(5100, 149, 5000)
	root.add_child(roof)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(5000, 150, 5000)
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	ShadowTuning.enabled = true
	ShadowTuning.reset()
	ShadowTuning.apply_level(sun, 0)
	await (_t as Node).get_tree().physics_frame
	await (_t as Node).get_tree().physics_frame
	var got := 0.0
	for i in 40:
		ShadowTuning._probe_at = -1.0
		ShadowTuning._last_ms = Time.get_ticks_msec()
		ShadowTuning.follow(sun, cam)
		got = ShadowTuning.clearance
		if got > 140.0:
			break
	_t._check(got > 140.0 and ShadowTuning.air > 100.0 and sun.directional_shadow_max_distance >= 590.0,
		"150 m over the ground_body the cascades slide out (clearance %.0f m, reach %.0f m)" % [got, sun.directional_shadow_max_distance])
	cam.global_position = Vector3(5100, 152, 5000)
	await (_t as Node).get_tree().physics_frame
	ShadowTuning._probe_at = -1.0
	ShadowTuning.follow(sun, cam)
	_t._check(ShadowTuning.clearance < 5.0 and ShadowTuning.air == 0.0 and is_equal_approx(sun.directional_shadow_max_distance, 500.0),
		"standing on a 150 m roof the camera keeps the street's cascades at once (clearance %.1f m, reach %.0f m)" % [ShadowTuning.clearance, sun.directional_shadow_max_distance])
	root.queue_free()
	ShadowTuning.reset()
