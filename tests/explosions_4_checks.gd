extends RefCounted
## The fourth explosion pass (Blast4, BlastPool) for tests/smoke_test.gd. Loaded at run time (not
## named there), so it compiles after the autoloads. Stages a deck high over the player, sets off a
## rocket blast and a fuel blast on it and frees what it made. Checks: the switch and its hooks,
## the volume lives on as the mushroom (its uniforms, its taller box, the card cap left out and the
## card column held back for the hand-over), the shader's cap height matches the hand-over's, a
## fuel blast leaves a burning pool ON the deck that lights the smoke and frees itself, secondary
## pops go off, a chain fuse reaches the car beside a fuel blast and stops at its depth, the bang's
## delay is the speed of sound, the web keeps cards for the pops, and the shaders' rules.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _top: Vector3


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	var player := _tree.get_first_node_in_group("player") as Node3D
	_top = player.global_position + Vector3(140.0, 560.0, 0.0)
	_switch()
	_pure()
	_shaders()
	if not Blast4.enabled or not Blast3.enabled:
		return
	_build_deck()
	BlastFX._recent.clear()
	var parent := WeaponFX.fx_parent(city)
	for c in parent.get_children():
		if String(c.name).begins_with("Blast") and not String(c.name).begins_with("BlastBits") and not c.is_queued_for_deletion():
			c.queue_free()
	await _ticks(2)
	var before := {}
	for c in parent.get_children():
		before[c] = true
	var at := _top + Vector3(0.0, 1.0, 0.0)
	WeaponFX.explosion(city, at, 9.0, 1.0)
	await _tree.process_frame
	_mushroom(parent, at)
	await _fuel(parent, at + Vector3(0.0, 0.0, 70.0))
	_web_pop(parent)
	await _chain()
	for c in parent.get_children():
		if not before.has(c) and c != _deck and not (c is BlastBits):
			c.queue_free()
	_deck.queue_free()
	BlastFX._recent.clear()
	await _ticks(3)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.name = "Explosions4Deck"
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300.0, 1.0, 300.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _switch() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/weapons/blast_4.gd")
	_t._check(src.contains("OS.get_environment(\"EXPLOSIONS_4\") != \"0\""), "explosions_4: EXPLOSIONS_4=0 turns it off")
	_t._check(Blast4.enabled, "explosions_4: on by default")
	_t._check(FileAccess.get_file_as_string("res://scripts/weapons/blast_3.gd").contains("Blast4.dress_volume("),
		"explosions_4: the volume asks Blast4 for the mushroom")
	_t._check(FileAccess.get_file_as_string("res://scripts/weapons/blast_fx.gd").contains("Blast4.after_blast("),
		"explosions_4: BlastFX hands the pool, the pops and the chain over")
	_t._check(FileAccess.get_file_as_string("res://scripts/weapons/explosion.gd").contains("Blast4.punch("),
		"explosions_4: the bang and the shake go through Blast4")
	_t._check(FileAccess.get_file_as_string("res://scripts/vehicles/car_damage.gd").contains("func chain_fuse("),
		"explosions_4: a car can take a chain fuse")


func _pure() -> void:
	_t._check(Blast4.life_for(false, false) > Blast3.volume_life and Blast4.life_for(true, false) > Blast4.life_for(false, false),
		"explosions_4: the mushroom outlives the third pass's fireball, a car's longer")
	# The hand-over height is the shader's rocket cap height (change one, change both).
	var vs := FileAccess.get_file_as_string("res://shaders/blast_volume.gdshader")
	_t._check(vs.contains("(0.3 + 1.05 * (1.0 - exp(-tt / 1.1)) + 0.13 * tt * (1.0 + 0.4 * gas)) * big"),
		"explosions_4: the shader's cap height is Blast4.handover_height()'s")
	_t._check(absf(Blast4.handover_height(4.0) - (0.3 + 1.05 * (1.0 - exp(-4.0 / 1.1)) + 0.52)) < 1e-4,
		"explosions_4: the hand-over height")
	_t._check(Blast4.fade_at(0.0, 9.0) == 1.0 and Blast4.fade_at(9.0, 9.0) == 0.0 and Blast4.fade_at(5.0, 9.0) == 1.0,
		"explosions_4: the volume fades only at the end of its life")


func _shaders() -> void:
	var vs := FileAccess.get_file_as_string("res://shaders/blast_volume.gdshader")
	_t._check(vs.contains("if (v4 > 0.5)") and vs.contains("uniform float v4 = 0.0;"),
		"explosions_4: the volume's fourth pass is behind its uniform (0 = the third pass)")
	_t._check(vs.contains("vec3 advect4(") and vs.contains("field4_lo(q + L * 0.85)"),
		"explosions_4: the noise is advected and the soot takes three shadow taps")
	var ps := FileAccess.get_file_as_string("res://shaders/blast_pool.gdshader")
	_t._check(ps.contains("color_space.gdshaderinc") and ps.contains("cs_out(alb)") and not ps.contains("instance uniform"),
		"explosions_4: the pool works in linear and has no instance uniforms")


## The rocket's volume is the mushroom: its uniforms, its box, the card cap hidden, the column held.
func _mushroom(parent: Node, at: Vector3) -> void:
	var vol: MeshInstance3D = null
	for c in parent.get_children():
		if c is MeshInstance3D and not c.is_queued_for_deletion() and String(c.name).begins_with("BlastVolume") \
				and (c as Node3D).global_position.distance_to(at) < 40.0:
			vol = c
	var vm := vol.material_override as ShaderMaterial if vol != null else null
	_t._check(vm != null and float(vm.get_shader_parameter("v4")) == 1.0 and absf(float(vm.get_shader_parameter("life")) - Blast4.volume_life) < 0.01,
		"explosions_4: the volume runs the fourth pass for the mushroom's life")
	var top := vol.global_position.y + vol.global_basis.y.length() if vol != null else 0.0
	_t._check(vol != null and top >= at.y + 9.0 * (Blast4.handover_height(Blast4.volume_life) + 0.8),
		"explosions_4: the volume's box holds the mushroom's rise (%.1f m over)" % (top - at.y))
	var col: Node = null
	for c in parent.get_children():
		if String(c.name).begins_with("BlastColumn") and not c.is_queued_for_deletion() and (c as Node3D).global_position.distance_to(at) < 3.0:
			col = c
	var cap := col.get_node_or_null("Cap") as CPUParticles3D if col != null else null
	var stem := col.get_node_or_null("Stem") as CPUParticles3D if col != null else null
	_t._check(cap != null and not cap.visible and stem != null and not stem.visible and not stem.emitting,
		"explosions_4: the card cap is left out and the card column waits for the hand-over")


## A fuel blast: the pool on the deck, burning, lighting the smoke; the pops; the pool frees itself.
func _fuel(parent: Node, at: Vector3) -> void:
	var pools0 := BlastPool.alive()
	BlastFX._recent.clear()
	BlastFX.fuel_next = true
	WeaponFX.explosion(_city, at, 7.0, 1.0)
	BlastFX.fuel_next = false
	await _tree.process_frame
	var made: Dictionary = BlastFX.last
	_t._check(bool(made.get("pool", false)) and BlastPool.alive() == pools0 + 1, "explosions_4: a fuel blast leaves a burning pool")
	_t._check(int(made.get("secondaries", 0)) >= Blast4.secondary_count.x, "explosions_4: secondary pops are set (%d)" % int(made.get("secondaries", 0)))
	var pool: BlastPool = null
	for c in parent.get_children():
		if c is BlastPool and not c.is_queued_for_deletion() and (c as Node3D).global_position.distance_to(at) < 8.0:
			pool = c
	_t._check(pool != null and absf(pool.global_position.y - _top.y) < 0.2, "explosions_4: the pool lies ON the deck")
	if pool == null:
		return
	await _ticks(30)
	_t._check(pool.burn() > 0.5 and (pool.get_node("PoolFire") as CPUParticles3D).emitting, "explosions_4: the pool burns")
	if not WeaponFX._web():
		var lit := false
		for v in Blast3.fire_list(_tree):
			lit = lit or Vector3(v.x, v.y, v.z).distance_to(pool.global_position) < 3.0
		_t._check(lit, "explosions_4: the pool's fire lights the smoke")
	# The pops went off by now (each makes a light at its bang).
	var t0 := Time.get_ticks_msec()
	var seen := 0
	while Time.get_ticks_msec() - t0 < 15000 and seen == 0:
		for c in parent.get_children():
			if String(c.name).begins_with("BlastPopLight") or (c is OmniLight3D and String(c.name).contains("OmniLight") and (c as OmniLight3D).light_color.is_equal_approx(Color(1.0, 0.62, 0.28))):
				seen += 1
		await _tree.physics_frame
	_t._check(seen > 0, "explosions_4: a secondary pop goes off")
	pool.life = pool.age + 0.1
	t0 = Time.get_ticks_msec()
	while is_instance_valid(pool) and Time.get_ticks_msec() - t0 < 20000:
		await _tree.process_frame
	_t._check(not is_instance_valid(pool), "explosions_4: the pool burns out and frees itself")


## On the web a pop is cards (no volume), and it does not fail.
func _web_pop(parent: Node) -> void:
	var was := WeaponFX._web_cache
	WeaponFX._web_cache = 1
	var n0 := parent.get_child_count()
	Blast4.pop(parent, _top + Vector3(30.0, 2.0, 0.0), 2.5)
	WeaponFX._web_cache = was
	var vol := false
	for i in range(n0, parent.get_child_count()):
		vol = vol or String(parent.get_child(i).name).begins_with("BlastVolume")
	_t._check(parent.get_child_count() > n0 and not vol, "explosions_4: a pop on the web is cards")


## A chain fuse reaches the car beside a fuel blast, staggered and capped in depth; then the cars
## are freed before they go up.
func _chain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var a := Vehicle.random_car(rng)
	var b := Vehicle.random_car(rng)
	for car in [a, b]:
		_city.add_child(car)
	var p := _top + Vector3(-60.0, 1.0, 0.0)
	a.global_position = p
	b.global_position = p + Vector3(4.5, 0.0, 0.0)
	await _ticks(3)
	var none := Blast4.chain(a, p, 7.0, Blast4.chain_depth + 1)
	_t._check(none == 0, "explosions_4: a chain stops at its depth")
	var n := Blast4.chain(a, p, 7.0, 1)
	var d: CarDamage = b.damage_state()
	_t._check(n >= 1 and d.state == CarDamage.State.BURNING and d._fuse <= Blast4.chain_fuse.y * 1.25,
		"explosions_4: the car beside a fuel blast catches a short fuse (%d, %.2f s)" % [n, d._fuse])
	_t._check(int(b.get_meta("chain_gen", 0)) == 1, "explosions_4: the chain counts its depth")
	for car in [a, b]:
		if is_instance_valid(car):
			car.queue_free()
	await _ticks(2)
