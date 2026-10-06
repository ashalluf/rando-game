extends RefCounted
## Street props breaking by kind (PropBreak, scripts/world/prop_break.gd) for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads. On a deck 300 m over the street with a
## chunk of its own (a real CityChunk's _add_prop(), no plan), like the driving checks. Checks: the
## city's prop records carry their instances' meshes; a broken hydrant leaves a flange, a thrown
## body and a geyser that throws the player up it and stops; a round pops a lamp (its light goes,
## the post stays), a hard hit bends it, a harder one fells it and it goes over; a bus shelter
## loses its glass to cubes and keeps its frame, then comes down in pieces; mailboxes and news
## boxes burst into paper that lands; a meter snaps off with coins and a stub; a car at speed
## smashes through a hydrant and keeps going; a destroyed prop leaves its stub on a rebuilt chunk;
## PROP_BREAK off breaks the old way.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _top: Vector3
var _chunks: Array = []
var _cars: Array = []
var _key_n: int = 0


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
	var home: Vector3 = ws.to_world(player.global_position)
	var was_enabled := PropBreak.enabled
	PropBreak.enabled = true
	_top = player.global_position + Vector3(0.0, 300.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(30.0, 1.2, 30.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	_city_records(city)
	await _hydrant(player)
	await _lamp()
	await _shelter()
	await _boxes()
	await _meter()
	await _smash()
	await _remains()
	await _off()

	PropBreak.enabled = was_enabled
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	for ch in _chunks:
		if is_instance_valid(ch):
			ch.queue_free()
	_deck.queue_free()
	player.global_position = ws.to_local(home)
	player.velocity = Vector3.ZERO
	if police:
		police.set("enabled", police_was)
	await _ticks(3)


func _city_records(city: Node3D) -> void:
	var found := 0
	var whole := 0
	for ch in city.get_children():
		if ch is CityChunk and (ch as CityChunk).level == CityChunk.Level.FULL:
			for r: Dictionary in (ch as CityChunk).prop_records:
				if r.kind == "hydrant" or r.kind == "lamp":
					found += 1
					if not r.instances.is_empty() and (r.instances[0] as Array).size() == 6 and r.instances[0][2] is Mesh:
						whole += 1
	_check(found > 0 and whole == found, "every city hydrant and lamp record keeps its instances' meshes and transforms (%d of %d)" % [whole, found])


func _hydrant(player: Player) -> void:
	var ch := _chunk()
	var at := Vector3(0.0, 0.0, 0.0)
	var r := _add(ch, "hydrant", at, PropFactory.model_hydrant(false), Vector3(0.3, 0.8, 0.3))
	_build(ch)
	var bodies := _pieces(ch)
	ch.damage_prop(r, 50.0, Vector3.FORWARD)
	await _ticks(2)
	var geyser := _first(ch, "HydrantGeyser") as HydrantGeyser
	_check(r.dead and geyser != null, "a broken hydrant starts a geyser")
	_check(_first(ch, "PropStub") != null, "and leaves its flange standing")
	_check(_pieces(ch) == bodies + 1, "and the hydrant itself is thrown as a body")
	if geyser == null:
		return
	player.global_position = ch.to_global(at) + Vector3(0.0, 0.3, 0.0)
	player.velocity = Vector3.ZERO
	var y0 := player.global_position.y
	await _ticks(20)
	_check(player.global_position.y > y0 + 1.5, "the column throws the player up it (%.1f m)" % (player.global_position.y - y0))
	player.global_position = _top + Vector3(30.0, 1.2, 30.0)
	player.velocity = Vector3.ZERO
	# Run it out: the water stops, the patch dries, the node goes.
	geyser.full_seconds = 0.3
	geyser.fade_seconds = 0.3
	geyser.dry_seconds = 0.4
	await _ticks(80)
	_check(not is_instance_valid(geyser), "the geyser stops and dries away")


func _lamp() -> void:
	var ch := _chunk()
	var at := Vector3(6.0, 0.0, 0.0)
	var lp := StreetLamps.place(null, at, Vector2(0.0, 1.0), 0)
	ch._add_prop("lamp", at, Color(0.28, 0.29, 0.32), [[lp.key, lp.mesh, lp.xform, lp.paint, lp.custom],
			["lamp_pool", PropFactory.light_pool(), Transform3D(Basis(), at)]], [[lp.box, at + Vector3(0.0, (lp.box as Vector3).y * 0.5, 0.0), 0.0]])
	var r: Dictionary = ch.prop_records.back()
	var light := OmniLight3D.new()
	ch.add_child(light)
	PropBreak.own_light(ch, light)
	_build(ch)
	_check(r.get("light") == light, "a lamp's record keeps its light")
	var hp: float = r.health
	ch.damage_prop(r, 10.0, Vector3.FORWARD)
	await _ticks(2)
	_check(not r.dead and r.get("out", false) and not is_instance_valid(light) and r.health == hp, "a round pops the lamp and its light, the post stays")
	ch.damage_prop(r, 40.0, Vector3.FORWARD)
	var tilt := 0.0
	if not r.shapes.is_empty() and is_instance_valid(r.shapes[0]):
		tilt = (r.shapes[0] as CollisionShape3D).transform.basis.y.angle_to(Vector3.UP)
	_check(not r.dead and float(r.get("lean_angle", 0.0)) > 0.05 and tilt > 0.05, "a hard hit bends the post at its foot (%.2f rad)" % tilt)
	ch.damage_prop(r, 90.0, Vector3.FORWARD)
	await _ticks(2)
	var pole := _first(ch, "FallingPole") as FallingPole
	_check(r.dead and pole != null, "a harder one fells it")
	if pole:
		await _ticks(200)
		_check(is_instance_valid(pole) and pole.tilt() > 1.0, "and it goes over (%.2f rad)" % (pole.tilt() if is_instance_valid(pole) else -1.0))


func _shelter() -> void:
	var ch := _chunk()
	var at := Vector3(14.0, 0.0, 0.0)
	var basis := Basis(Vector3.UP, PI)
	var back := Vector3(0.0, 0.0, -0.9)
	ch._add_prop("bus_stop", at, Color(0.3, 0.3, 0.32), [
		["shelter_post", PropFactory.shelter_post(), Transform3D(basis, at + back + Vector3(1.8, 1.25, 0.0))],
		["shelter_post", PropFactory.shelter_post(), Transform3D(basis, at + back + Vector3(-1.8, 1.25, 0.0))],
		["shelter_roof", PropFactory.shelter_roof(), Transform3D(basis, at + back * 0.4 + Vector3(0.0, 2.55, 0.0))],
		["shelter_glass", PropFactory.shelter_glass(), Transform3D(basis, at + back + Vector3(0.0, 1.3, 0.0))],
		["bench", PropFactory.model_bench(), Transform3D(Basis(), at + back * 0.55)],
	], [[Vector3(4.2, 2.6, 1.0), at + back + Vector3(0.0, 1.3, 0.0), 0.0]])
	var r: Dictionary = ch.prop_records.back()
	_build(ch)
	ch.damage_prop(r, 50.0, Vector3.FORWARD)
	await _ticks(2)
	var glass := _first(ch, "PropShards") as PropShards
	_check(not r.dead and r.get("glass_gone", false) and is_equal_approx(r.health, PropBreak.FRAME_HEALTH), "a shelter's glass goes and its frame stays")
	_check(glass != null and glass.kind == PropShards.Kind.GLASS and glass.count() > 50, "the glass bursts into cubes (%d)" % (glass.count() if glass else 0))
	_check(not r.shapes.is_empty() and is_instance_valid(r.shapes[0]) and not (r.shapes[0] as CollisionShape3D).disabled, "the frame still stands in the way")
	var before := _pieces(ch)
	ch.damage_prop(r, 100.0, Vector3.FORWARD)
	await _ticks(2)
	_check(r.dead and _pieces(ch) >= before + 3, "hit again, the frame comes down in pieces (%d)" % (_pieces(ch) - before))
	if glass:
		await _ticks(150)
		_check(is_instance_valid(glass) and glass.resting() > glass.count() * 0.7, "the cubes land and lie on the pavement (%d of %d)" % [glass.resting() if is_instance_valid(glass) else 0, glass.count() if is_instance_valid(glass) else 0])


func _boxes() -> void:
	var ch := _chunk()
	var mail := _add(ch, "mailbox", Vector3(20.0, 0.0, 0.0), PropFactory.mailbox(), Vector3(0.6, 1.3, 0.5))
	var news := _add(ch, "newsbox", Vector3(23.0, 0.0, 0.0), StreetClutter.news_box(), Vector3(0.5, 1.12, 0.44))
	_build(ch)
	ch.damage_prop(mail, 50.0, Vector3.FORWARD)
	ch.damage_prop(news, 50.0, Vector3.FORWARD)
	await _ticks(2)
	var letters := 0
	var papers := 0
	var all: Array = []
	for n in ch.get_children():
		if n is PropShards:
			all.append(n)
			letters += int((n as PropShards).kind == PropShards.Kind.LETTER)
			papers += int((n as PropShards).kind == PropShards.Kind.NEWSPAPER)
	_check(mail.dead and news.dead and letters == 1 and papers == 1, "a mailbox bursts into letters, a news box into newspapers")
	await _ticks(400)
	var landed := true
	for s: PropShards in all:
		if not is_instance_valid(s) or s.resting() < s.count() * 0.8:
			landed = false
	_check(landed, "the paper flutters down and lands")


func _meter() -> void:
	var ch := _chunk()
	var r := _add(ch, "meter", Vector3(27.0, 0.0, 0.0), StreetDetail._meter_mesh(), Vector3(0.2, 1.4, 0.2))
	_build(ch)
	var before := _pieces(ch)
	ch.damage_prop(r, 50.0, Vector3.FORWARD)
	await _ticks(2)
	var coins := _first(ch, "PropShards") as PropShards
	_check(r.dead and _pieces(ch) == before + 1 and _first(ch, "PropStub") != null, "a meter snaps off its stub and is thrown")
	_check(coins != null and coins.kind == PropShards.Kind.COIN, "spilling its coins")


func _smash() -> void:
	var ch := _chunk()
	var at := Vector3(-20.0, 0.0, 30.0)
	var r := _add(ch, "hydrant", at, PropFactory.model_hydrant(false), Vector3(0.3, 0.8, 0.3))
	_build(ch)
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.2, 0.3, 0.5), Vehicle.Addon.NONE)
	car.position = _city.to_local(ch.to_global(at) + Vector3(-25.0, 0.9, 0.0))
	car.rotation.y = -PI * 0.5
	_city.add_child(car)
	_cars.append(car)
	await _ticks(3)
	car.linear_velocity = Vector3(13.0, 0.0, 0.0)
	var smashed := false
	for i in 180:
		await _tree.physics_frame
		if car.linear_velocity.x < 8.0 and not smashed:
			car.linear_velocity = Vector3(13.0, car.linear_velocity.y, 0.0)
		if r.dead:
			smashed = true
			break
	var speed_after := 0.0
	await _ticks(6)
	speed_after = car.linear_velocity.length()
	await _ticks(60)
	_check(smashed, "a car at speed smashes the hydrant")
	_check(speed_after > 6.0 and car.global_position.x > ch.to_global(at).x + 1.0, "and drives on through it (%.1f m/s, %.1f m past)" % [speed_after, car.global_position.x - ch.to_global(at).x])
	for g in ch.get_children():
		if g is HydrantGeyser:
			(g as HydrantGeyser).end_now()


func _remains() -> void:
	var key := "pd_check_remains_%d" % Time.get_ticks_usec()
	var ch := _chunk(key)
	var r := _add(ch, "meter", Vector3(0.0, 0.0, 10.0), StreetDetail._meter_mesh(), Vector3(0.2, 1.4, 0.2))
	_build(ch)
	ch.break_prop(r, Vector3.FORWARD)
	var again := _chunk(key)
	_add(again, "meter", Vector3(0.0, 0.0, 10.0), StreetDetail._meter_mesh(), Vector3(0.2, 1.4, 0.2))
	_check(again.prop_records.is_empty() and _first(again, "PropStub") != null, "a destroyed meter leaves its stub on a rebuilt chunk")


func _off() -> void:
	PropBreak.enabled = false
	var ch := _chunk()
	var r := _add(ch, "hydrant", Vector3(0.0, 0.0, 20.0), PropFactory.model_hydrant(false), Vector3(0.3, 0.8, 0.3))
	_build(ch)
	ch.damage_prop(r, 50.0, Vector3.FORWARD)
	await _ticks(2)
	_check(r.dead and _first(ch, "HydrantGeyser") == null and _first(ch, "PropStub") == null, "PROP_BREAK off breaks a hydrant the old way")
	PropBreak.enabled = true


# --- Helpers ------------------------------------------------------------------------------------

func _chunk(key: String = "") -> CityChunk:
	_key_n += 1
	var ch := CityChunk.new()
	ch.key = key if key != "" else "pd_check_%d_%d" % [_key_n, Time.get_ticks_usec()]
	ch.name = "PropBreakCheck_%d" % _key_n
	ch._statics = StreetProps.new()
	ch._statics.chunk = ch
	ch.add_child(ch._statics)
	# Under the deck, never the city root: CityStreamer walks the root's chunks.
	_deck.add_child(ch)
	ch.global_position = _top
	_chunks.append(ch)
	return ch


func _add(ch: CityChunk, kind: String, at: Vector3, mesh: Mesh, box: Vector3) -> Dictionary:
	ch._add_prop(kind, at, Color(0.5, 0.2, 0.2), [[kind, mesh, Transform3D(Basis(), at)]], [[box, at + Vector3(0.0, box.y * 0.5, 0.0), 0.0]])
	return ch.prop_records.back() if not ch.prop_records.is_empty() else {}


func _build(ch: CityChunk) -> void:
	ch._mm_nodes = ch._batch.build(ch)


func _pieces(ch: CityChunk) -> int:
	var n := 0
	for c in ch.get_children():
		if c is RigidBody3D:
			n += 1
	return n


func _first(ch: Node, prefix: String) -> Node:
	for c in ch.get_children():
		if String(c.name).contains(prefix):
			return c
	return null


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(240.0, 1.0, 240.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
