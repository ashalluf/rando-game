extends RefCounted
## Foot placement checks for tests/smoke_test.gd (G5, CrowdFeet): on a little test site built
## 300 m over the spawn (a 15 cm kerb, a 14-degree ramp, a flight of steps under a walkable ramp
## that the feet see through), real Pedestrians standing near a camera plant each foot on what is
## under it - the foot over the kerb goes down to the road, the hips come down with it, feet on a
## slope sit on it - nothing accumulates tick after tick, the IK fades out with distance and
## FOOT_IK's switch turns it off. Loaded at run time like the other crowd checks.

var _t: Node
var _tree: SceneTree
var _site: Node3D
var _cam: Camera3D
var _old_cam: Camera3D
var _peds: Array = []
const KERB := 0.15
const RAMP_DEG := 14.0


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var player := _tree.get_first_node_in_group("player") as Node3D
	var o := (player.global_position if player else Vector3.ZERO) + Vector3(0.0, 300.0, 0.0)
	_build(city, o)
	_old_cam = city.get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	city.add_child(_cam)
	_cam.global_position = o + Vector3(0.0, 1.5, 6.0)
	_cam.make_current()
	var was := CrowdFeet.enabled
	CrowdFeet.enabled = true
	await _check_kerb(city, o)
	await _check_ramp(city, o)
	await _check_steps(city, o)
	await _check_fade_and_switch(city, o)
	_check_steps_body()
	CrowdFeet.enabled = was
	for p in _peds:
		if is_instance_valid(p):
			p.queue_free()
	_site.queue_free()
	_cam.queue_free()
	if is_instance_valid(_old_cam):
		_old_cam.make_current()
	await _ticks(2)


func _box(centre: Vector3, size: Vector3, tilt_x: float = 0.0, layer: int = 1) -> CollisionShape3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.position = centre
	body.rotation_degrees.x = tilt_x
	_site.add_child(body)
	return cs


func _build(city: Node3D, o: Vector3) -> void:
	_site = Node3D.new()
	_site.name = "FootIkSite"
	city.add_child(_site)
	# Road (top at o.y) and a pavement x < 0 whose kerb edge is z = 0 (relative to o).
	_box(o + Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	_box(o + Vector3(-10, KERB * 0.5, -3), Vector3(20, KERB, 6))
	# Ramp at x in [10, 16] rising toward -z.
	var a := deg_to_rad(RAMP_DEG)
	_box(o + Vector3(13, 7.0 * sin(a) - 0.25 * cos(a), -7.0 * cos(a)), Vector3(6, 0.5, 14), RAMP_DEG)
	# Steps at x in [24, 28], 17 x 30 cm, climbing toward -z, on the feet layer only, under a
	# world-layer ramp through their nosings that the feet are told to see through.
	for i in 8:
		var h := 0.17 * float(i + 1)
		_box(o + Vector3(26, h * 0.5, -0.3 * (float(i) + 0.5)), Vector3(4, h, 0.3), 0.0, CrowdFeet.FEET_LAYER)
	var ang := atan2(0.17, 0.3)
	var len := 8.0 * 0.3 / cos(ang)
	# The line through the nosings is y = 0.17 + 0.17 * (-z / 0.3); the ramp's top lies on it.
	var ramp := _box(o + Vector3(26, 0.85 - 0.15 * cos(ang), -1.2 - 0.15 * sin(ang)), Vector3(4, 0.3, len), rad_to_deg(ang))
	ramp.set_meta("feet_pass", true)
	_box(o + Vector3(26, -0.5, -1.2), Vector3(4, 1, 2.4)) # ground under the flight (road level)


func _stand(o: Vector3, at: Vector3, yaw_deg: float, seed_value: int) -> Pedestrian:
	var p := Pedestrian.new()
	var w := o + at
	p.setup(Rect2(w.x - 40, w.z - 40, 80, 80), 4.0, seed_value)
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	p.life_spawn_chance = 0.0
	p.life_chance = 0.0
	p.set_meta("no_trim", true)
	p.position = w
	_site.add_child(p)
	p._pause_left = 1.0e6
	p._visual.rotation.y = deg_to_rad(yaw_deg)
	p._play_idle()
	p._speed = 0.0
	_peds.append(p)
	return p


func _bone(p: Pedestrian, bone: String) -> Vector3:
	return _ankle(p, bone)


func _ankle(p: Pedestrian, bone: String) -> Vector3:
	var sk: Skeleton3D = p._head_skel
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin


## Ground under a point (world and feet layers, seeing through feet_pass shapes).
func _ground(at: Vector3) -> float:
	var space := _site.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.7, at - Vector3.UP * 1.0, 1 | CrowdFeet.FEET_LAYER)
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and CrowdFeet._passes(hit):
		q.from = hit.position - Vector3(0, 0.002, 0)
		hit = space.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else NAN


func _check_kerb(_city: Node3D, o: Vector3) -> void:
	# A reference on the flat road, and one side-on at the kerb with a foot over the edge.
	# Seed 1310 rolls crowd_z whether MODELS holds 26 rigs or 32 (seed 11 did with 26; with
	# crowd_aa..af appended it rolled crowd_f, whose shoes stand 1 mm past the tolerance).
	var flat := _stand(o, Vector3(4.0, 0.0, 2.0), 90.0, 1310)
	var kerb := _stand(o, Vector3(-2.0, KERB, -0.06), 90.0, 1310)
	_cam.global_position = o + Vector3(1.0, 1.5, 5.0)
	await _ticks(45)
	var f: CrowdFeet = kerb.foot_ik
	_check(f != null, "a person near the camera gets foot placement")
	if f == null:
		return
	var lift := f.applied_lift
	_check(minf(lift.x, lift.y) < -0.11 and maxf(lift.x, lift.y) > -0.03,
		"the foot over the kerb goes down to the road, the other stays (lift %s)" % lift)
	_check(f.applied_hips < -0.05 and f.applied_hips >= minf(lift.x, lift.y) - 0.005,
		"the hips come down with the lower foot, never past it (hips %.3f)" % f.applied_hips)
	# Each ankle stands over its own ground as high as the flat reference's planted ankles do.
	var ref := minf(_ankle(flat, "LeftFoot").y - o.y, _ankle(flat, "RightFoot").y - o.y)
	var worst := 0.0
	for b in ["LeftFoot", "RightFoot"]:
		var at := _ankle(kerb, b)
		worst = maxf(worst, absf((at.y - _ground(at)) - ref))
	_check(worst < 0.04, "both feet at the kerb stand on their own ground (worst %.3f m off the flat stance)" % worst)
	# Nothing accumulates: the kerb person's hips stay where the same person's on the flat road
	# are, less the drop, a hundred ticks on (the idle's own sway is in both).
	var drift := []
	for n in 2:
		var hk := _bone(kerb, "Hips").y - kerb.global_position.y
		var hf := _bone(flat, "Hips").y - flat.global_position.y
		drift.append(hk - hf)
		if n == 0:
			await _ticks(100)
	_check(absf(float(drift[1]) - float(drift[0])) < 0.012 and absf(float(drift[0]) - f.applied_hips) < 0.02,
		"the IK does not pile up tick on tick (hips against the flat stance %.3f, then %.3f)" % [drift[0], drift[1]])
	flat.queue_free()
	kerb.queue_free()


func _check_ramp(_city: Node3D, o: Vector3) -> void:
	var y := 4.0 * tan(deg_to_rad(RAMP_DEG))
	var across := _stand(o, Vector3(13.0, y + 0.02, -4.0), 90.0, 61)
	_cam.global_position = o + Vector3(18.0, y + 1.5, -4.0)
	await _ticks(45)
	var f: CrowdFeet = across.foot_ik
	_check(f != null and absf(f.applied_lift.x - f.applied_lift.y) > 0.04,
		"standing across a slope, the feet are planted at two heights (%s)" % (f.applied_lift if f else Vector2.INF))
	var gaps: Array = []
	for b in ["LeftFoot", "RightFoot"]:
		var at := _ankle(across, b)
		gaps.append(at.y - _ground(at))
	_check(absf(float(gaps[0]) - float(gaps[1])) < 0.05,
		"both ankles stand the same height over the slope (%.3f, %.3f)" % [gaps[0], gaps[1]])
	across.queue_free()


func _check_steps(_city: Node3D, o: Vector3) -> void:
	# Facing up the flight, standing on the walkable ramp at its 3rd tread (where the body of a
	# real walker stands): the feet find the treads (the feet layer), not the ramp over them, and
	# stand on them as high as feet on the flat do.
	var flat := _stand(o, Vector3(20.0, 0.0, 2.0), 0.0, 101)
	var p := _stand(o, Vector3(26.0, 0.17 + 0.17 * 3.0 + 0.02, -0.3 * 3.0), 0.0, 101)
	_cam.global_position = o + Vector3(30.0, 2.0, -1.2)
	await _ticks(45)
	var ref := minf(_ankle(flat, "LeftFoot").y - o.y, _ankle(flat, "RightFoot").y - o.y)
	var worst := 0.0
	var line := ""
	for b in ["LeftFoot", "RightFoot"]:
		var at := _ankle(p, b)
		var ball := _ankle(p, b.replace("Foot", "ToeBase"))
		# A foot across a riser stands on the higher tread (under its ball, going up).
		var k := maxi(clampi(int(floor(-(at.z - o.z) / 0.3)), 0, 7), clampi(int(floor(-(ball.z - o.z) / 0.3)), 0, 7))
		var tread := o.y + 0.17 * float(k + 1)
		worst = maxf(worst, absf(at.y - tread - ref))
		line += " %s %.3f over tread %d" % [b, at.y - tread, k]
	var f: CrowdFeet = p.foot_ik
	_check(worst < 0.07, "on the steps the ankles stand on the treads, not on the ramp over them (worst %.3f m off the flat stance;%s; lift %s; body at %.2f)"
		% [worst, line, f.applied_lift if f else Vector2.INF, p.global_position.y - o.y])
	flat.queue_free()
	p.queue_free()


func _check_fade_and_switch(_city: Node3D, o: Vector3) -> void:
	var kerb := _stand(o, Vector3(-6.0, KERB, -0.06), 90.0, 29)
	_cam.global_position = o + Vector3(-6.0, 1.5, 5.0)
	await _ticks(45)
	var f: CrowdFeet = kerb.foot_ik
	var near_lift := f.applied_lift if f else Vector2.ZERO
	_cam.global_position = o + Vector3(-6.0, 1.5, 5.0 + CrowdFeet.far_range + 10.0)
	await _ticks(60)
	_check(f != null and near_lift != Vector2.ZERO and f.applied_lift == Vector2.ZERO,
		"foot placement fades out past far_range from the camera (near %s, far %s)" % [near_lift, f.applied_lift if f else Vector2.INF])
	_cam.global_position = o + Vector3(-6.0, 1.5, 5.0)
	CrowdFeet.enabled = false
	await _ticks(30)
	var sk: Skeleton3D = kerb._head_skel
	var at := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin
	var off_hips := at.y
	CrowdFeet.enabled = true
	await _ticks(45)
	at = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin
	_check(off_hips - at.y > 0.04, "FOOT_IK's switch turns it off (hips %.3f higher without it)" % (off_hips - at.y))
	kerb.queue_free()


func _check_steps_body() -> void:
	var parent := Node3D.new()
	_site.add_child(parent)
	var ramp := CollisionShape3D.new()
	CrowdFeet.add_steps(parent, ramp, Vector2.ZERO, Vector2(0, 1), Vector2(1, 0), 4.0, 0.0, 2.0, 0.5, 8, 1.1)
	var body := parent.get_node_or_null("FeetSteps") as StaticBody3D
	_check(body != null and body.collision_layer == CrowdFeet.FEET_LAYER and body.collision_mask == 0
		and body.get_child_count() == 8 and ramp.has_meta("feet_pass"),
		"a flight's treads are feet-only static boxes (layer 6, mask 0) and its ramp is seen through")
	ramp.free()


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
