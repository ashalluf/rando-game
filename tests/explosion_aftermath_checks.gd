extends RefCounted
## What a big blast leaves behind, for tests/smoke_test.gd: TreeFire (the chunks' trees and palms
## registered, a crown set alight, charred under the flames and kept charred across a rebuild,
## the fire spreading to a neighbour, the cap), SmokeColumn (a column over a big fire, tall and
## leaning, clearing when the fire is out), BlastAftermath (a crater with its slabs, rubble that
## is PhysicsBudget debris for minutes, a car's own blast leaves no pit, leaves torn off) and
## CarAlarm (a blast sets off the parked cars' alarms with their hazards, never a driven or a
## traffic car's, they stop on their own, the cap holds). Loaded at run time, so it can name the
## classes that use autoloads. Car and crater checks run on a deck 250 m over the street.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _ws: Node
var _deck: StaticBody3D
var _top: Vector3
var _cars: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_ws = _tree.root.get_node("/root/WorldState")
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	_sound_and_shader()
	await _trees(player)
	var home: Vector3 = _ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 250.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 40.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)
	await _alarms()
	await _craters()
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_deck.queue_free()
	player.global_position = _ws.to_local(home)
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
	box.size = Vector3(160.0, 1.0, 160.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _car(x: float, z: float = 0.0) -> Vehicle:
	var car := Vehicle.new()
	car.setup(0 as Vehicle.BodyType, Color(0.6, 0.6, 0.62), Vehicle.Addon.NONE)
	_city.add_child(car)
	car.global_position = _top + Vector3(x, 0.9, z)
	_cars.append(car)
	return car


func _sound_and_shader() -> void:
	var sfx := _tree.root.get_node("/root/Sfx")
	var takes: Array = sfx._streams.get("car_alarm", [])
	var looped := not takes.is_empty()
	for s in takes:
		if s is AudioStreamOggVorbis and not (s as AudioStreamOggVorbis).loop:
			looped = false
	_check(takes.size() == 3 and looped, "the car alarm's three recordings load and loop (%d takes)" % takes.size())
	var sh: Shader = load("res://shaders/foliage.gdshader")
	var has_burnt := false
	for u: Dictionary in sh.get_shader_uniform_list():
		if u.name == "burnt":
			has_burnt = true
	_check(has_burnt, "the palm shader has its burnt uniform (TreeFire's charred palms)")
	var col: Shader = load("res://shaders/smoke_column.gdshader")
	_check(col != null and col.get_shader_uniform_list().size() >= 10, "the smoke column shader compiles")


# --- Trees --------------------------------------------------------------------------------------

func _trees(player: Player) -> void:
	var near := TreeFire.trees_near(player.global_position, 400.0)
	var palms := 0
	for h: Array in near:
		if (h[1] as Dictionary).palm:
			palms += 1
	_check(near.size() > 0, "the loaded chunks registered their trees with TreeFire (%d within 400 m, %d palms)" % [near.size(), palms])
	_check(not TreeFire.is_tree_key("tree_grate") and TreeFire.is_tree_key("tree_3") and TreeFire.is_tree_key("palm_0"),
			"only tree_<n> and palm_<n> batches count as trees (not the tree grates)")
	if near.is_empty():
		return
	var caps := [TreeFire.max_burning, TreeFire.spread_odds, TreeFire.spread_interval]
	# Pick a tree with a neighbour close enough to spread to, if there is one.
	var pick: Array = near[0]
	var neighbour: Array = []
	for h: Array in near:
		var t: Dictionary = h[1]
		var crown := WorldState.to_local(t.crown)
		for o: Array in TreeFire.trees_near(crown, float(t.r) + TreeFire.spread_gap):
			if (o[1] as Dictionary).id != t.id and not TreeFire.is_charred(o[0], o[1]):
				pick = h
				neighbour = o
				break
		if not neighbour.is_empty():
			break
	var rec: Dictionary = pick[0]
	var tree: Dictionary = pick[1]
	var before := TreeFire.charred_count()
	_check(TreeFire.ignite(_city, rec, tree), "a tree can be set alight (%s in %s)" % [tree.id, rec.key])
	_check(not TreeFire.ignite(_city, rec, tree), "a burning tree is not set alight twice")
	var burn: Node = TreeFire._burns.get("%s|%s" % [rec.key, tree.id])
	_check(burn != null and burn.get_node_or_null("Flames") != null and burn.get_node_or_null("Smoke") != null
			and burn.get_node_or_null("Embers") != null, "a burning crown has flames, smoke and embers")
	# Spread: certain odds, now.
	TreeFire.spread_odds = 1.0
	TreeFire.spread_interval = 0.01
	burn.t = burn.life * 0.4
	await _frames(3)
	_check(TreeFire.charred_count() == before + 1, "under the flames the tree turns charred (%d -> %d)" % [before, TreeFire.charred_count()])
	_check((_ws.charred as Dictionary).get(rec.key, {}).has(tree.id), "WorldState remembers the charred tree")
	var chunk := (rec.chunk as WeakRef).get_ref() as Node3D
	var node := chunk.get_node_or_null("Charred_" + tree.key) as MultiMeshInstance3D if chunk else null
	_check(node != null and node.multimesh.instance_count >= 1, "the chunk draws it from a charred copy")
	if node:
		var mesh := node.multimesh.mesh
		var mat := mesh.surface_get_material(0)
		var burnt_ok := false
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m is ShaderMaterial and ((m as ShaderMaterial).get_shader_parameter("burnt") == 1.0
					or float((m as ShaderMaterial).get_shader_parameter("thin_max")) > 0.8):
				burnt_ok = true
			elif m is StandardMaterial3D and (m as StandardMaterial3D).albedo_color.v < 0.3:
				burnt_ok = true
		_check(burnt_ok and mat != (rec.nodes[tree.key] as MultiMeshInstance3D).multimesh.mesh.surface_get_material(0),
				"the charred copy wears burnt materials, not the living tree's")
	if not neighbour.is_empty():
		_check(TreeFire.burning_count() >= 2 or TreeFire.is_charred(neighbour[0], neighbour[1]),
				"the fire spreads to a neighbouring crown (%d burning)" % TreeFire.burning_count())
	# A smoke column over it.
	var mgr := TreeFire.manager(_tree)
	mgr._update_columns(1.0)
	var cols: Array = mgr.columns()
	_check(cols.size() >= 1, "a burning tree sends up a smoke column")
	if cols.size() >= 1:
		var col: SmokeColumn = cols[0]
		var mi := col.get_node_or_null("Plume") as MeshInstance3D
		_check(mi != null and mi.custom_aabb.size.y > 300.0 and col.height() >= 100.0,
				"the column climbs hundreds of metres (%.0f m, box %.0f m)" % [col.height(), mi.custom_aabb.size.y if mi else 0.0])
	# The rebuild: a chunk built again draws it charred from the start.
	var entries: Array = []
	for t: Dictionary in rec.trees:
		entries.append([t.key, t.i, t.xf, t.mesh])
	var count_was := (rec.charred as Dictionary).size()
	TreeFire._chunks.erase(rec.key)
	TreeFire.attach(chunk, entries, rec.nodes)
	var again: Dictionary = TreeFire._chunks.get(rec.key, {})
	_check(not again.is_empty() and (again.charred as Dictionary).has(tree.id) and (again.charred as Dictionary).size() == count_was,
			"a rebuilt chunk draws the burnt tree charred again")
	_check(not TreeFire.ignite(_city, again, again.charred[tree.id]) if not again.is_empty() else false,
			"a charred tree never burns again")
	# The cap.
	for b in TreeFire._burns.values():
		if is_instance_valid(b):
			b.queue_free()
	await _frames(2)
	TreeFire.max_burning = 2
	var lit := 0
	for h: Array in near:
		if TreeFire.ignite(_city, h[0], h[1]):
			lit += 1
	_check(TreeFire.burning_count() <= 2 and lit <= 2, "no more trees burn than the cap (%d lit)" % lit)
	for b in TreeFire._burns.values():
		if is_instance_valid(b):
			b.queue_free()
	await _frames(2)
	# The column clears once nothing feeds it.
	mgr._update_columns(1.0)
	for c: SmokeColumn in mgr.columns():
		c.strength = 0.01
	mgr._update_columns(5.0)
	_check(mgr.columns().is_empty(), "the column clears once the fire is out")
	TreeFire.max_burning = caps[0]
	TreeFire.spread_odds = caps[1]
	TreeFire.spread_interval = caps[2]


# --- Car alarms ---------------------------------------------------------------------------------

func _armed_car(x: float) -> Vehicle:
	for i in 12:
		var c := _car(x + float(i) * 0.01, -30.0 - float(i) * 6.0)
		if CarAlarm.armed(c):
			return c
	return null


func _alarms() -> void:
	var a := _armed_car(-20.0)
	var b := _armed_car(20.0)
	await _ticks(20)
	_check(a != null and b != null, "most parked cars carry an alarm")
	if a == null or b == null:
		return
	b._npc_driver = true
	_check(not CarAlarm.armed(b), "a car with somebody at the wheel sets no alarm off")
	b._npc_driver = false
	var at := (a.global_position + b.global_position) * 0.5
	CarAlarm.blast(_tree, at, 9.0)
	await _frames(4)
	var alarm := a.get_node_or_null("CarAlarm")
	_check(alarm != null, "a blast nearby sets a parked car's alarm off")
	if alarm:
		alarm._delay = 0.001
		await _frames(3)
		_check(a.alarm_left > 0.0 and alarm.get_node_or_null("AlarmSound") != null, "the alarm sounds (%.0f s to go)" % a.alarm_left)
		a._tick_lights(0.016)
		_check(a.light_signal == 2 and a.lights_running(), "its hazards flash while it sounds")
		alarm._left = 0.01
		await _frames(4)
		_check(a.get_node_or_null("CarAlarm") == null and a.alarm_left == 0.0, "the alarm stops on its own")
		a._tick_lights(0.016)
		_check(a.light_signal == 0 and not a.lights_running(), "and the hazards go off with it")
	var far := _armed_car(70.0)
	if far:
		far.global_position = _top + Vector3(75.0, 0.9, 70.0)
		CarAlarm.blast(_tree, at, 2.0)
		await _frames(2)
		_check(far.get_node_or_null("CarAlarm") == null, "a car out of reach stays quiet")
	# A hit on the car itself.
	var c := _armed_car(-50.0)
	if c:
		c.take_hit(-1, 10.0, Vector3.LEFT, c.global_position + Vector3.UP * 0.6, Vehicle.HIT_CRASH)
		await _frames(2)
		_check(c.get_node_or_null("CarAlarm") != null, "a parked car that is hit sets its own alarm off")
	var cap := CarAlarm.max_alarms
	CarAlarm.max_alarms = CarAlarm.sounding()
	var d := _armed_car(-60.0)
	_check(d == null or not CarAlarm.trigger(d), "no more alarms than the cap")
	CarAlarm.max_alarms = cap
	for v in _cars:
		if is_instance_valid(v) and v.get_node_or_null("CarAlarm"):
			v.get_node("CarAlarm")._stop()
	await _frames(2)


# --- Craters, rubble, leaves --------------------------------------------------------------------

func _craters() -> void:
	var n0 := BlastAftermath.crater_count()
	var debris0 := _tree.get_nodes_in_group("debris").size()
	var at := _top + Vector3(-40.0, 0.4, 50.0)
	Explosion.blast(_city, at, 9.0, 30.0, 0.0)
	await _ticks(3)
	_check(BlastAftermath.crater_count() == n0 + 1, "a rocket on the ground leaves a crater")
	var crater: Node3D = BlastAftermath._craters.back() if not BlastAftermath._craters.is_empty() else null
	_check(crater != null and crater.get_node_or_null("Slabs") != null and (crater.get_node("Slabs") as MultiMeshInstance3D).multimesh.instance_count == BlastAftermath.slab_count,
			"with broken slabs heaved up round its rim")
	var mark_ok := crater != null and (crater.get_child(0) is Decal or crater.get_child(0) is MeshInstance3D)
	_check(mark_ok, "the crater mark is a decal on Forward+ or a quad on Compatibility")
	var rubble := BlastAftermath.rubble_count_now()
	var lasting := 0
	for b in BlastAftermath._rubble:
		if is_instance_valid(b) and b.is_in_group("debris") and float(b.get_meta("debris_life", 0.0)) >= 120.0:
			lasting += 1
	_check(rubble > 0 and lasting == rubble, "rubble is thrown out and stays as debris for minutes (%d pieces)" % rubble)
	_check(_tree.get_nodes_in_group("debris").size() >= debris0 + rubble, "the rubble counts against the physics budget")
	var maps := BlastAftermath.crater_textures(0)
	_check(maps.size() == 2 and (maps[0] as Texture2D).get_width() == 256, "the crater's maps are generated")
	# A car's own blast: scorch, no pit.
	var car := _car(30.0, 60.0)
	await _ticks(10)
	var n1 := BlastAftermath.crater_count()
	var slabs_before := 0
	for c in BlastAftermath._craters:
		if is_instance_valid(c) and c.get_node_or_null("Slabs"):
			slabs_before += 1
	BlastAftermath.blast(_city, car.global_position, 7.0, 20.0, car)
	await _ticks(2)
	var slabs_after := 0
	for c in BlastAftermath._craters:
		if is_instance_valid(c) and c.get_node_or_null("Slabs"):
			slabs_after += 1
	_check(BlastAftermath.crater_count() == n1 + 1 and slabs_after == slabs_before, "a car's own blast scorches the road but digs no pit")
	# The cap.
	var cap := BlastAftermath.max_craters
	BlastAftermath.max_craters = 2
	for i in 3:
		BlastAftermath.crater(_city, _top + Vector3(10.0 * i, 0.0, -60.0), Vector3.UP, 9.0)
	await _frames(1)
	_check(BlastAftermath.crater_count() <= 2, "no more craters than the cap")
	BlastAftermath.max_craters = cap
	# Leaves.
	var leaves := BlastAftermath.leaf_burst(WeaponFX.fx_parent(_city), _top + Vector3(0, 8, 0), 3.0, Vector3.RIGHT, 1.0, false, 30)
	_check(leaves != null and leaves.amount == 30 and (leaves.mesh as QuadMesh).material != null, "a blast tears leaves off a tree")
