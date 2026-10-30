extends RefCounted
## The police at night (PoliceNightLook, docs/HANDOFF.md "Red and blue at night") for
## tests/smoke_test.gd. Loaded at run time, so it can name PoliceCar and PoliceNightLook. On a
## deck 300 m over the street (the car lights checks' way), with its own cruisers - the Police node
## stays off; nothing leans on where an earlier check left the city. Checks: one shared flash clock
## for the lenses and the glow; a glow per lit cruiser on the wash shader, its pool on the road; the
## budget's real lights on the nearest cruisers only, red or blue as the lit bank, the car's own
## BarLight dark; a wall found beside a car takes the wash; a roadblock lays its flares toward the
## player and takes them up again; a wreck goes dark; by day no light and no pool; the searchlight's
## haze; no random numbers.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _wall: StaticBody3D
var _cars: Array = []
var _top: Vector3


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var was_enabled := PoliceNightLook.enabled
	var was_force := PoliceNightLook.force
	var was_budget := PoliceNightLook.budget
	PoliceNightLook.enabled = true
	PoliceNightLook.force = true
	PoliceNightLook.budget = 2
	var home: Vector3 = ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 300.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 30.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	_check(was_enabled == (OS.get_environment("POLICE_NIGHT_LOOK") != "0"),
			"POLICE_NIGHT_LOOK=0 is the A/B switch (enabled %s)" % was_enabled)
	await _night(police, player)

	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_cars.clear()
	_deck.queue_free()
	if is_instance_valid(_wall):
		_wall.queue_free()
	PoliceNightLook.enabled = was_enabled
	PoliceNightLook.force = was_force
	PoliceNightLook.budget = was_budget
	var look := PoliceNightLook.instance()
	if look:
		look.set_night(DayNight.lamp_now)
		look._night_t = 0.0
	player.global_position = ws.to_local(home)
	player.velocity = Vector3.ZERO
	if police:
		police.set("enabled", police_was)
	await _ticks(3)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


## A cruiser standing on the deck at (x, z), its own driving off (`scripted`), lit (stars or not,
## a cruiser that is not leaving has its bar on).
func _cruiser(police: Node, at: Vector2, yaw: float) -> PoliceCar:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([at.x, at.y, "pnl"])
	var car := PoliceCar.make(false, rng)
	car.police = police as Police
	car.scripted = true
	car.position = _city.to_local(_top + Vector3(at.x, car.road_lift(), at.y))
	car.rotation.y = yaw
	_city.add_child(car)
	_cars.append(car)
	return car


func _night(police: Node, player: Player) -> void:
	if police == null:
		_check(false, "the city has a Police node")
		return
	var a := _cruiser(police, Vector2(-6.0, 12.0), 0.0)
	var b := _cruiser(police, Vector2(6.0, 4.0), 0.4)
	var c := _cruiser(police, Vector2(0.0, -30.0), 0.0)
	await _frames(3)
	var look := PoliceNightLook.instance()
	_check(look != null, "the first cruiser makes the one PoliceNightLook node")
	if look == null:
		return
	look.set_night(1.0)
	await _frames(12)
	var all_lit := a.bar_lit() and b.bar_lit() and c.bar_lit()
	_check(all_lit, "three standing cruisers have their bars lit")
	# One clock: the lens shader's and the glow's are the look's.
	var bar := a.get_node_or_null("LightBar") as MeshInstance3D
	var lens_clock: float = (bar.material_override as ShaderMaterial).get_shader_parameter("clock") if bar else -1.0
	var glow := a.get_node_or_null("PoliceGlow") as Node3D
	var gmat: ShaderMaterial = glow.get_meta("mat") if glow else null
	var glow_clock: float = gmat.get_shader_parameter("clock") if gmat else -2.0
	_check(lens_clock >= 0.0 and absf(lens_clock - glow_clock) < 0.2 and absf(glow_clock - PoliceNightLook.clock) < 0.2,
			"the lenses and the glow run on the one flash clock (%.2f, %.2f, %.2f)" % [lens_clock, glow_clock, PoliceNightLook.clock])
	_check(glow != null and glow.visible and gmat != null and gmat.shader.resource_path == "res://shaders/police_wash.gdshader",
			"a lit cruiser carries a glow on the wash shader")
	_check(gmat != b.get_node("PoliceGlow").get_meta("mat") and float(gmat.get_shader_parameter("phase")) == a.flash_phase(),
			"each cruiser's glow is its own material at its own phase (no instance uniforms)")
	var pool := glow.get_node("Pool") as MeshInstance3D if glow else null
	var deck_y := _top.y
	_check(pool != null and pool.visible and absf(pool.global_position.y - deck_y) < 0.4,
			"the pool lies on the road under the car (%.2f m off)" % (absf(pool.global_position.y - deck_y) if pool else 99.0))
	# The real lights: the budget (2) on the two cruisers nearest the camera, the far one none.
	var lit_cars := look.lit_cars()
	_check(lit_cars.size() == 2 and lit_cars.has(a) and lit_cars.has(b) and not lit_cars.has(c),
			"the budget's real lights go to the nearest cruisers (%d handed out)" % lit_cars.size())
	var own := a.get_node_or_null("BarLight") as OmniLight3D
	_check(own == null or not own.visible, "the cruiser's own BarLight stays dark under the look")
	# Colour follows the lit bank: sample frames until a light is on, then compare.
	var matched := 0
	var seen := 0
	for i in 60:
		await _frames(1)
		for slot in look._lights:
			var l: OmniLight3D = slot[0]
			if slot[1] == null or not l.visible:
				continue
			var side: int = (slot[1] as PoliceCar).flash_side(PoliceNightLook.clock)
			seen += 1
			if (side > 0 and l.light_color.r > l.light_color.b) or (side < 0 and l.light_color.b > l.light_color.r):
				matched += 1
	_check(seen > 0 and matched == seen, "a real light is red on the red bank and blue on the blue (%d of %d)" % [matched, seen])
	# A wall beside car b, on its +x: the wash finds it.
	_wall = StaticBody3D.new()
	_wall.collision_layer = 1
	_wall.collision_mask = 0
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(1.0, 12.0, 30.0)
	ws.shape = wb
	_wall.add_child(ws)
	_city.add_child(_wall)
	var right := b.global_basis.x
	right.y = 0.0
	_wall.global_position = b.global_position + right.normalized() * 8.0 + Vector3.UP * 5.0
	_wall.global_rotation.y = b.global_rotation.y
	await _ticks(2)
	look._wall_t = 0.0
	await _frames(4)
	var wall_b := b.get_node("PoliceGlow/WallB") as MeshInstance3D
	_check(wall_b.visible and wall_b.global_position.distance_to(b.global_position) < 10.0,
			"a facade beside the car takes the wash")
	# A roadblock lays its flares on the player's side and takes them up when it is one no more.
	a.roadblock = true
	await _frames(3)
	var flares := a.get_node_or_null("RoadblockFlares") as Node3D
	var toward := false
	if flares and flares.get_child_count() > 0:
		var f := flares.get_child(0) as Node3D
		var rel_p := a.global_basis.inverse() * (player.global_position - a.global_position)
		toward = signf(f.position.x) == signf(rel_p.x) or absf(rel_p.x) < 0.1
	_check(flares != null and flares.get_child_count() == look.flare_count and toward,
			"a roadblock lays %d road flares on the player's side" % look.flare_count)
	a.roadblock = false
	await _frames(3)
	_check(a.get_node_or_null("RoadblockFlares") == null or a.get_node("RoadblockFlares").is_queued_for_deletion(),
			"and takes them up when it is no roadblock")
	# A burnt-out cruiser goes dark: glow hidden, its light handed on.
	b.crew_alive = 0
	for i in 200:
		await _frames(1)
		if not look.lit_cars().has(b) and look.lit_cars().has(c):
			break
	_check(not b.bar_lit() and not b.get_node("PoliceGlow").visible and not look.lit_cars().has(b),
			"a cruiser whose bar is off loses its glow and its light")
	_check(look.lit_cars().has(c), "and the light goes to the next cruiser")
	# By day: no real light on, no pool.
	look.set_night(0.0)
	for i in 200:
		await _frames(1)
		if PoliceNightLook.active_count == 0 and look.lit_cars().is_empty():
			break
	_check(PoliceNightLook.active_count == 0 and not a.get_node("PoliceGlow/Pool").visible,
			"by day the strobes light nothing and lay no pool (%d lights on)" % PoliceNightLook.active_count)
	# The searchlight's haze: the beam shader takes the look.
	var beam: Shader = load("res://shaders/searchlight_beam.gdshader")
	var has_look := false
	for u in beam.get_shader_uniform_list():
		if u.name == "look":
			has_look = true
	_check(has_look, "the searchlight's shaft has the lit-haze look")
	# Nothing here rolls: every look is a car's own phase.
	var src: String = (load("res://scripts/npc/police_night_look.gd") as GDScript).source_code
	_check(src.find("randf") < 0 and src.find("randi") < 0 and src.find("RandomNumberGenerator") < 0,
			"PoliceNightLook rolls no random numbers")
	# Quality's budget table.
	var q_src: String = (load("res://scripts/util/quality.gd") as GDScript).source_code
	_check(q_src.find("PoliceNightLook.budget = [6, 4, 2, 0]") >= 0, "Quality budgets the strobes 6 / 4 / 2 / 0")
