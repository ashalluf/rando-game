extends RefCounted
## Swimming (Swim, SwimWater, SeaSurface, SwimPose; scripts/player/swim.gd), for
## tests/smoke_test.gd: SeaSurface's constants are the ocean shader's (its uniform defaults and
## the five swells' lines), its height moves with time and stays flat on the waterline, SwimWater
## finds the sea, the marina and nothing on land, and is empty with the switch off; then the real
## player: dropped into the sea he goes in with a splash, floats at the surface (on the drawn
## swell), the gun put away; forward swims the crawl, the body laid prone; dive takes him under,
## jump brings him back; the boost porpoises him out of the water; a pool registered under him
## holds him in its tank; and back on land the world mask and the gun are his again.
## Untyped access to the player and the city (autoloads, see smoke_test.gd).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan = city.get("plan")
	var m: MacroMap = plan.macro if plan else null
	_check(m != null, "swimming has the city's map")
	if m == null:
		return
	_check_constants()
	_check_sea(m)
	_check_water(m)
	await _check_live(city, m)
	await _check_pool(city)
	await _t.call("stage_home")


func _check_constants() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/ocean.gdshader")
	var want := {"base_height": SeaSurface.BASE_HEIGHT, "swell_length": SeaSurface.SWELL_LENGTH,
		"group_length": SeaSurface.GROUP_LENGTH, "group_depth": SeaSurface.GROUP_DEPTH, "speed": SeaSurface.SPEED,
		"tsunami_height": SeaSurface.TSUNAMI_HEIGHT, "tsunami_length": SeaSurface.TSUNAMI_LENGTH,
		"swash_width": SeaSurface.SWASH_WIDTH, "surf_width": SeaSurface.SURF_WIDTH}
	var bad := []
	for k: String in want:
		var re := RegEx.create_from_string("uniform float " + k + "[^=]*=\\s*([0-9.]+)")
		var hit := re.search(src)
		if hit == null or absf(float(hit.get_string(1)) - float(want[k])) > 1e-6:
			bad.append(k)
	var lines := ["normalize(vec2(1.00, 0.22)), l0, amp * 0.34, 0.75 * lean_k",
		"normalize(vec2(0.86, -0.51)), l0 / 1.59, amp * 0.26",
		"normalize(vec2(0.62, 0.78)), l0 / 2.62, amp * 0.19", "normalize(vec2(0.97, -0.24)), l0 / 4.51, amp * 0.13",
		"normalize(vec2(0.34, 0.94)), l0 / 7.89, amp * 0.08", "float lean_k = clamp(3.6 / max(open, 0.1), 0.55, 1.0);",
		"uniform vec2 tsunami_dir = vec2(1.0, 0.15);"]
	for l: String in lines:
		if src.find(l) < 0:
			bad.append(l)
	_check(bad.is_empty(), "SeaSurface's swell is the ocean shader's (mismatched: %s)" % str(bad))


func _check_sea(m: MacroMap) -> void:
	var st := [1.0, 0.0, Surf.params(1.0)[0], Surf.params(1.0)[1]]
	var p := Vector2(m.coast_x(0.0) - 150.0, 0.0)
	var lo := INF
	var hi := -INF
	for k in 40:
		var h := SeaSurface.height(m, p, 3.0 + k * 0.7, st)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	_check(is_finite(lo) and hi - lo > 0.2 and lo > -2.5 and hi < 2.5, "the open sea rises and falls with the swell (%.2f to %.2f m over 28 s)" % [lo, hi])
	var storm := [6.0, 0.0, Surf.params(6.0)[0], Surf.params(6.0)[1]]
	var shi := -INF
	for k in 40:
		shi = maxf(shi, absf(SeaSurface.height(m, p, 3.0 + k * 0.7, storm) - SeaSurface.MESH_Y))
	_check(shi > hi - SeaSurface.MESH_Y + 0.3, "a storm's sea is bigger than a clear day's (%.2f m against %.2f)" % [shi, hi - SeaSurface.MESH_Y])
	var edge := SeaSurface.height(m, Vector2(m.coast_x(0.0) - 0.5, 0.0), 5.0, st)
	_check(absf(edge - SeaSurface.MESH_Y) < 0.05, "the water is level at the waterline (%.3f)" % edge)
	_check(SeaSurface.seabed(0.0) > SeaSurface.seabed(30.0) and SeaSurface.seabed(30.0) > SeaSurface.seabed(400.0) and SeaSurface.seabed(400.0) >= -13.01, "the sea floor shelves down from the beach to the floor box")


func _check_water(m: MacroMap) -> void:
	var st := [1.0, 0.0, Surf.params(1.0)[0], Surf.params(1.0)[1]]
	var sea := SwimWater.at(m, Vector3(m.coast_x(300.0) - 120.0, 0.0, 300.0), 2.0, st)
	_check(int(sea.get("kind", 0)) == SwimWater.Kind.SEA and float(sea.floor) < float(sea.surface) - 3.0, "SwimWater finds the sea offshore, with deep water under it (%s)" % str(sea.get("floor", "-")))
	var land := SwimWater.at(m, Vector3(m.coast_x(300.0) + 400.0, 0.0, 300.0), 2.0, st)
	_check(land.is_empty(), "and no water on land")
	if m.marina and m.marina.ok:
		var sum := Vector2.ZERO
		for q in m.marina.basin:
			sum += q
		var c := sum / float(m.marina.basin.size())
		var w := SwimWater.at(m, Vector3(c.x, 0.0, c.y), 2.0, st)
		_check(int(w.get("kind", 0)) == SwimWater.Kind.MARINA, "and the marina's basin")
	SwimWater.enabled = false
	var off := SwimWater.at(m, Vector3(m.coast_x(300.0) - 120.0, 0.0, 300.0), 2.0, st)
	SwimWater.enabled = true
	_check(off.is_empty(), "SWIMMING=0: no water anywhere")


func _check_live(city: Node3D, m: MacroMap) -> void:
	var player := _t.get_tree().get_first_node_in_group("player") as CharacterBody3D
	var swim: Node = player.get("swim") if player else null
	_check(swim != null, "the player has the swimming controller")
	if swim == null:
		return
	var ws: Node = _t.call("_world_state")
	var z := 300.0
	var spot := Vector3(m.coast_x(z) - 90.0, 9.0, z)
	var splashes_before := _count_splashes(player)
	player.global_position = ws.call("to_local", spot)
	player.velocity = Vector3(0.0, -14.0, 0.0)
	city.call("update_streaming", true)
	var went_in := false
	for i in 120:
		await _t.get_tree().physics_frame
		if bool(swim.get("swimming")):
			went_in = true
			break
	_check(went_in, "dropped into the sea, the hero goes in")
	_check(_count_splashes(player) > splashes_before, "with a splash")
	_check(not (player.get("weapon_manager") as Node3D).visible, "the gun is put away in the water")
	_check((player.collision_mask & 1) == 0, "in the sea he passes the ground box (the world layer is off his mask)")
	# Let the dive in settle and float him up.
	for i in 240:
		await _t.get_tree().physics_frame
	var tp: Vector3 = ws.call("to_world", player.global_position)
	var st: Array = swim.get("_sea")
	var surf := SeaSurface.height(m, Vector2(tp.x, tp.z), SeaSurface.now(), st)
	var under := surf - tp.y
	_check(bool(swim.get("swimming")) and under > 0.9 and under < 1.9, "he floats at the drawn surface, head out (feet %.2f m under it)" % under)
	# Forward: the crawl.
	Input.action_press("move_forward")
	for i in 150:
		await _t.get_tree().physics_frame
	var v := player.velocity
	var flat := Vector2(v.x, v.z).length()
	var avatar: Node3D = player.get("avatar")
	var pose: Node = avatar.get("swim_pose") if avatar else null
	var mix: PackedFloat32Array = pose.get("mix") if pose else PackedFloat32Array([0, 0, 0, 0])
	_check(flat > 3.0 and flat < 6.0, "forward swims at swimming speed (%.1f m/s)" % flat)
	_check(pose != null and float(pose.get("weight")) > 0.9 and mix[SwimPose.Stroke.CRAWL] > 0.8, "the front crawl is on (weight %.2f, crawl %.2f)" % [float(pose.get("weight")) if pose else 0.0, mix[0]])
	var head_up: float = (avatar.basis.orthonormalized() * Vector3.UP).y if avatar else 1.0
	_check(head_up < 0.35, "the body lies prone in the crawl (head axis up %.2f)" % head_up)
	# Dive.
	var y0 := player.global_position.y
	Input.action_press("dive")
	await _t.get_tree().physics_frame
	Input.action_release("dive")
	Input.action_press("dive")
	for i in 90:
		await _t.get_tree().physics_frame
	Input.action_release("dive")
	_check(bool(swim.get("under")) and player.global_position.y < y0 - 1.5, "dive takes him under (%.1f m down)" % (y0 - player.global_position.y))
	var tp2: Vector3 = ws.call("to_world", player.global_position)
	var floor_y := SeaSurface.seabed(SeaSurface.shore_distance(m, Vector2(tp2.x, tp2.z)).x)
	_check(tp2.y >= floor_y + 0.05, "never through the sea floor (%.2f over it)" % (tp2.y - floor_y))
	Input.action_release("move_forward")
	Input.action_press("jump")
	var surfaced := false
	for i in 300:
		await _t.get_tree().physics_frame
		if not bool(swim.get("under")):
			surfaced = true
			break
	Input.action_release("jump")
	_check(surfaced and bool(swim.get("swimming")), "jump brings him back up to the surface")
	for i in 30:
		await _t.get_tree().physics_frame
	# The boost: the dolphin.
	Input.action_press("move_forward")
	Input.action_press("boost")
	var leapt := false
	var top := 0.0
	for i in 240:
		await _t.get_tree().physics_frame
		top = maxf(top, Vector2(player.velocity.x, player.velocity.z).length())
		leapt = leapt or bool(swim.get("leaping"))
	Input.action_release("boost")
	Input.action_release("move_forward")
	_check(top > 10.0, "the boost races him along the water (%.1f m/s)" % top)
	_check(leapt, "and porpoises him out of it like a dolphin")
	# No drowning: a long dive is just a dive.
	var health: Node = player.get("health")
	var hp0: float = float(health.get("health")) if health and health.get("health") != null else 0.0
	Input.action_press("dive")
	for i in 30:
		await _t.get_tree().physics_frame
	Input.action_release("dive")
	for i in 300:
		await _t.get_tree().physics_frame
	var hp1: float = float(health.get("health")) if health and health.get("health") != null else 0.0
	_check(hp1 >= hp0 and not player.call("is_downed"), "no drowning: five seconds under costs nothing")
	# Out: home on land, the mask and the gun back.
	player.call("respawn")
	await _t.call("stage_home")
	for i in 10:
		await _t.get_tree().physics_frame
	_check(not bool(swim.get("swimming")) and (player.collision_mask & 1) == 1 and (player.get("weapon_manager") as Node3D).visible, "back on land the world mask and the gun are his again")


## A pool registered round the player on dry ground (a stand-in for a yard's or a park's): he goes
## in, floats in it, and stays inside its tank however hard he swims.
func _check_pool(city: Node3D) -> void:
	await _t.call("stage_home")
	var player := _t.get_tree().get_first_node_in_group("player") as CharacterBody3D
	var swim: Node = player.get("swim")
	var ws: Node = _t.call("_world_state")
	for i in 30:
		await _t.get_tree().physics_frame
	var at: Vector3 = ws.call("to_world", player.global_position)
	var holder := Node3D.new()
	holder.name = "SwimCheckPool"
	city.add_child(holder)
	var r := Rect2(at.x - 3.0, at.z - 6.0, 6.0, 12.0)
	SwimWater.add_rect(holder, r, at.y - 0.05, at.y - 0.05 - SwimWater.POOL_DEPTH, SwimWater.Kind.POOL)
	var went := false
	for i in 30:
		await _t.get_tree().physics_frame
		went = went or bool(swim.get("swimming"))
	_check(went and int((swim.get("water") as Dictionary).get("kind", 0)) == SwimWater.Kind.POOL, "he swims in a pool")
	Input.action_press("move_right")
	Input.action_press("boost")
	for i in 120:
		await _t.get_tree().physics_frame
	Input.action_release("boost")
	Input.action_release("move_right")
	var now: Vector3 = ws.call("to_world", player.global_position)
	_check(r.grow(0.05).has_point(Vector2(now.x, now.z)) and now.y > at.y - 0.05 - SwimWater.POOL_DEPTH - 0.01, "and stays in its tank (%.1f, %.1f in a %s)" % [now.x, now.z, str(r)])
	holder.queue_free()
	await _t.get_tree().physics_frame
	await _t.get_tree().physics_frame
	_check(not bool(swim.get("swimming")) and (player.collision_mask & 1) == 1, "the pool gone, he is on his feet with the world under them")


func _count_splashes(player: Node) -> int:
	var n := 0
	for c in player.get_parent().get_children():
		if str(c.name).begins_with("SwimSplash"):
			n += 1
	return n


func _check(ok: bool, label: String) -> void:
	_t.call("_check", ok, label)
