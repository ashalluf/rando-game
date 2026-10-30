extends RefCounted
## The crowd's head look (CrowdLook, scripts/npc/crowd_look.gd) for tests/smoke_test.gd: a
## walker near the camera gets the modifier on its skeleton; a crash posted behind it turns the
## head (and a little of the chest) round within the caps, eased and no faster than the startle
## speed; a quiet thing behind it is not seen while one in front is; a hold-off fades the look
## out; out of range it eases back to the clip and the modifier stops. One standing walker on
## the spawn block's pavement, about eight seconds of game time. Loaded at run time, so it
## compiles after the autoloads.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	if not CrowdLook.enabled:
		_check(true, "the crowd look is off (CROWD_LOOK=0): nothing to check")
		return
	var chunk: Node3D = city.chunks.get(Vector2i(0, 0))
	_check(chunk != null, "the spawn block's chunk is loaded for the crowd look checks")
	if chunk == null:
		return
	var plan: CityPlan = city.plan
	var rect: Rect2 = plan.block(0, 0).rect
	var ped := Pedestrian.new()
	ped.setup(rect, plan.sidewalk_width, 5151)
	ped.pause_chance = 0.0
	ped.cross_chance = 0.0
	ped.look_range = 100000.0 # wherever the player and the camera are
	ped.life_range = 0.0
	var a := Vector2(rect.position.x + 8.0, rect.position.y + 2.0)
	ped.position = Vector3(a.x, chunk.ground_y(a.x, a.y) + 0.1, a.y)
	chunk.add_child(ped)
	await _ticks(2)
	ped._play_idle()
	ped._pause_left = 1000.0
	ped._visual.rotation.y = -PI * 0.5 # facing east
	ped._faced = true
	await _ticks(40) # the LOD pass (every 0.5 s) marks it near
	var mod: CrowdLook = null
	if ped._head_skel:
		for c in ped._head_skel.get_children():
			if c is CrowdLook:
				mod = c
	_check(ped._head_skel == null or mod != null, "a walker near the camera wears the look modifier on its skeleton")
	if mod == null:
		ped.queue_free()
		return
	# Clear the stage: nothing worth a look but what the checks post.
	CrowdLook._events.clear()
	mod.social = false
	mod._dwell = 0.0
	await _ticks(30)
	# A crash behind and to the left: heard, so the head turns as far as it goes that way.
	var face: float = ped._visual.global_rotation.y
	var fwd := Vector3(-sin(face), 0.0, -cos(face))
	var left := Vector3(-cos(face), 0.0, sin(face))
	var eye := ped.global_position + Vector3.UP * 1.5
	CrowdLook.notice(eye - fwd * 6.0 + left * 3.0, CrowdLook.Kind.CRASH, 40.0, 3.0)
	mod._scan = 0.0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var worst_step := 0.0
	var prev := mod.yaw
	var early := 0.0
	for i in 60:
		await _tree.physics_frame
		worst_step = maxf(worst_step, absf(mod.yaw - prev))
		prev = mod.yaw
		if i == 3:
			early = mod.yaw + mod.chest
	var total := mod.yaw + mod.chest
	_check(mod._kind == CrowdLook.Kind.CRASH and total > deg_to_rad(80.0),
		"a crash behind and to the left turns the head that way (%.0f degrees, kind %d)" % [rad_to_deg(total), mod._kind])
	_check(absf(mod.yaw) <= CrowdLook.HEAD_YAW_MAX + 0.01 and absf(mod.chest) <= CrowdLook.CHEST_YAW_MAX + 0.01 and mod.chest > 0.1,
		"the turn is capped: head %.0f (max %.0f), chest %.0f (max %.0f)" % [rad_to_deg(mod.yaw), rad_to_deg(CrowdLook.HEAD_YAW_MAX),
			rad_to_deg(mod.chest), rad_to_deg(CrowdLook.CHEST_YAW_MAX)])
	_check(early > 0.0 and early < total * 0.8 and worst_step <= CrowdLook.SPEED_STARTLE * dt * 1.05 + 1e-4,
		"the turn is eased (%.0f degrees after 4 ticks) and never faster than the startle speed (worst %.1f deg/tick)" % [
			rad_to_deg(early), rad_to_deg(worst_step)])
	_check(absf(ped._look_yaw - total) < 0.01, "the pedestrian's _look_yaw reports the modifier's turn")
	# Quiet things: a magnet behind is not seen, one ahead and to the right is.
	CrowdLook._events.clear()
	var behind := Node3D.new()
	behind.add_to_group("crowd_look_magnet")
	chunk.get_parent().add_child(behind)
	behind.global_position = eye - fwd * 5.0
	mod._dwell = 0.0
	mod._kind = CrowdLook.Kind.IDLE
	mod._point = Vector3.ZERO
	await _ticks(70)
	_check(absf(mod.yaw + mod.chest) < deg_to_rad(15.0),
		"a performer behind is not seen (%.0f degrees)" % rad_to_deg(mod.yaw + mod.chest))
	var right := -left
	behind.global_position = eye + fwd * 6.0 + right * 5.0
	await _ticks(70)
	var want := -atan2(5.0, 6.0)
	_check(mod._kind == CrowdLook.Kind.MAGNET and absf((mod.yaw + mod.chest) - want) < deg_to_rad(12.0),
		"a performer ahead and to the right is watched (%.0f degrees, wanted %.0f)" % [rad_to_deg(mod.yaw + mod.chest), rad_to_deg(want)])
	# Another system holds the head: the look fades out under it.
	CrowdLook.hold_off(ped, 2.0)
	await _ticks(30)
	_check(mod.held > 0.95, "a hold-off fades the look out (held %.2f)" % mod.held)
	behind.queue_free()
	# Out of range: eased back to the clip's pose and the modifier stops.
	ped.look_range = 0.0
	ped._update_lod()
	for i in 120:
		await _tree.process_frame
		if not mod.active:
			break
	_check(not ped._look_near and not mod.active and mod.yaw == 0.0,
		"out of the look range the head eases back and the modifier stops (active %s, yaw %.2f)" % [mod.active, mod.yaw])
	ped.queue_free()
	CrowdLook._events.clear()


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
