extends RefCounted
## Crowd animation checks for tests/smoke_test.gd (VISUAL_ROADMAP #28): a walker's clip rate is
## matched to the ground it covers, it pulls away from a standstill and slows into a stop,
## an about-turn is stepped round on the spot instead of slid, the body only ever moves the way
## it faces, and a head turns to a gunshot. Loaded at run time like the street-life checks, so
## it compiles after the autoloads. One walker on the spawn block's pavement, about eight
## seconds of game time.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var chunk: Node3D = city.chunks.get(Vector2i(0, 0))
	_check(chunk != null, "the spawn block's chunk is loaded for the crowd animation checks")
	if chunk == null:
		return
	var plan: CityPlan = city.plan
	var rect: Rect2 = plan.block(0, 0).rect
	var ped := Pedestrian.new()
	ped.setup(rect, plan.sidewalk_width, 4242)
	ped.pause_chance = 0.0
	ped.cross_chance = 0.0
	ped.look_range = 100000.0 # wherever the player stands
	# Never a crowd-life stop (talk, phone, idle): those take over the clip, and they start only
	# within life_range of the player, so where the run left the player decided the result.
	ped.life_range = 0.0
	# Along the north pavement, west to east, from a standstill.
	var z := rect.position.y + 2.0
	var a := Vector2(rect.position.x + 6.0, z)
	var b := Vector2(minf(rect.position.x + 40.0, rect.end.x - 6.0), z)
	ped.position = Vector3(a.x, chunk.ground_y(a.x, a.y) + 0.1, a.y)
	chunk.add_child(ped)
	await _ticks(2)
	ped._play_idle()
	ped._visual.rotation.y = -PI * 0.5 # facing east
	ped._faced = true
	var early := -1.0
	var sideways := 0.0
	var peak := 0.0
	for i in 150:
		_steer(ped, b)
		await _tree.physics_frame
		if i == 12:
			early = ped._speed
		peak = maxf(peak, ped._speed)
		sideways = maxf(sideways, _sideways(ped))
	_check(early >= 0.0 and early < ped.walk_speed * 0.6 and peak > ped.walk_speed * 0.9,
		"a walker pulls away from a standstill over its first steps (%.2f m/s after 0.2 s, %.2f later, pace %.2f)" % [early, peak, ped.walk_speed])
	var rate: float = ped._anim.speed_scale if ped._anim else 0.0
	var matched := rate * Pedestrian.WALK_CLIP_SPEED * ped._stride
	_check(ped._anim == null or (ped._clip == Pedestrian.WALK_CLIP and absf(matched - ped._speed) < 0.05),
		"the walk clip runs at the rate the ground speed asks for (clip %s covers %.2f m/s, body %.2f)" % [ped._clip, matched, ped._speed])
	# An about-turn: back west. It stops, steps round where it stands, and sets off again.
	var pivoted := false
	var slowest := INF
	var back := false
	for i in 180:
		_steer(ped, a)
		await _tree.physics_frame
		pivoted = pivoted or ped._pivoting
		if not back:
			slowest = minf(slowest, ped._speed)
		back = back or Vector2(-sin(ped._visual.rotation.y), -cos(ped._visual.rotation.y)).x < -0.95
		sideways = maxf(sideways, _sideways(ped))
	_check(pivoted and slowest < 0.25 and back,
		"an about-turn is taken standing (pivot %s, slowest %.2f m/s, facing back %s)" % [pivoted, slowest, back])
	_check(sideways < 0.05, "the body only moves the way it faces (worst sideways %.3f m/s)" % sideways)
	# A stop: a pause, and the idle clip once the last step is done.
	ped._pause_left = 3.0
	await _ticks(90)
	_check(ped._speed == 0.0 and (ped._anim == null or ped._clip == Pedestrian.IDLE_CLIP),
		"standing still plays the idle (speed %.2f, clip %s)" % [ped._speed, ped._clip])
	# A gunshot off to one side: the head turns to it (the pose over the clip, not the body).
	var face: float = ped._visual.global_rotation.y
	var side := Vector3(cos(face), 0.0, -sin(face)) # the walker's right
	ped._look_threat = ped.global_position + side * 8.0 + Vector3.UP * 1.5
	ped._look_hold = 3.0
	ped._look_scan = 0.0
	ped._pause_left = 3.0
	await _ticks(45)
	_check(ped._head_skel == null or absf(ped._look_yaw) > deg_to_rad(35.0),
		"a head turns toward a shot off to the side (%.0f degrees)" % rad_to_deg(ped._look_yaw))
	ped.queue_free()


func _steer(ped: Pedestrian, target: Vector2) -> void:
	ped._target = target
	ped._route = PackedVector2Array()
	ped._route_pending = false


## How fast the body goes across the way it faces (m/s).
func _sideways(ped: Pedestrian) -> float:
	var yaw: float = ped._visual.rotation.y
	var right := Vector2(cos(yaw), -sin(yaw))
	return absf(Vector2(ped.velocity.x, ped.velocity.z).dot(right))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
