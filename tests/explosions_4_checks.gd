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
	_round4(parent)
	await _round5(parent)
	_round6(parent)
	_round7(parent)
	_round8()
	await _round9()
	await _round11(parent)
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
		if c is BlastPool and not c.is_queued_for_deletion() and (c as BlastPool).stretch <= 1.2 and (c as Node3D).global_position.distance_to(at) < 8.0:
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
	# Counted in physics frames, not the wall clock: the pops are game-time timers, and a busy box
	# (another render beside the gate) ran 15 wall seconds short of them.
	var frames := 0
	var seen := 0
	while frames < 1200 and seen == 0:
		frames += 1
		for c in parent.get_children():
			if String(c.name).begins_with("BlastPopLight") or (c is OmniLight3D and String(c.name).contains("OmniLight") and (c as OmniLight3D).light_color.is_equal_approx(Color(1.0, 0.62, 0.28))):
				seen += 1
		await _tree.physics_frame
	_t._check(seen > 0, "explosions_4: a secondary pop goes off")
	pool.life = pool.age + 0.1
	var t0 := Time.get_ticks_msec()
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


## Round 4: the rolling dust front, the plume's value range, the debris chunks, the smaller flare.
func _round4(parent: Node) -> void:
	var n0 := parent.get_child_count()
	var rolled := Blast4.dust_roll(parent, _top, Vector3.UP, 28.0)
	_t._check(rolled and parent.get_child_count() >= n0 + 2, "explosions_4: the dust rolls out as its own layers")
	_t._check(FileAccess.get_file_as_string("res://scripts/weapons/blast_aftermath.gd").contains("Blast4.dust_roll("),
		"explosions_4: the aftermath's dust wave hands over to the rolling front")
	var vs := FileAccess.get_file_as_string("res://shaders/blast_volume.gdshader")
	_t._check(vs.contains("uniform float value4 = 0.0;") and vs.contains("value4 * 0.9 * smoothstep(1.5, 6.0, t)"),
		"explosions_4: the plume's value range is in the volume (off by default)")
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/blast_volume.gdshader")
	Blast4.dress_volume(m, false, false)
	_t._check(float(m.get_shader_parameter("value4")) == (Blast4.value_range if Blast4.value_enabled else 0.0),
		"explosions_4: a volume is dressed with the value range")
	var pm := Blast4.panel_mesh()
	_t._check(pm != null and pm.get_surface_count() == 1 and pm.get_aabb().size.x > 0.9, "explosions_4: the torn panel chunk is built")
	_t._check(Blast4.flare_grow() < 4.2 and Blast4.flare_fade() < 0.13, "explosions_4: the flare is smaller and shorter")


## Round 5: the fires' underlight on the smoke, the stem held, the wreck's side flames and the
## fuel trail, the crater's soft soot and cracks.
func _round5(parent: Node) -> void:
	var vs := FileAccess.get_file_as_string("res://shaders/blast_volume.gdshader")
	_t._check(vs.contains("uniform float under4 = 0.0;") and vs.contains("uniform float stem_hold = 0.0;"),
		"explosions_4: the underlight and the stem hold are in the volume (off by default)")
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/blast_volume.gdshader")
	Blast4.dress_volume(m, true, false)
	_t._check(float(m.get_shader_parameter("under4")) == (Blast4.underlight_gain if Blast4.underlight_enabled else 0.0)
		and float(m.get_shader_parameter("stem_hold")) == (1.0 if Blast4.stem_enabled else 0.0),
		"explosions_4: a volume is dressed with the underlight and the stem hold")
	var rng := RandomNumberGenerator.new()
	rng.seed = 505
	var car := Vehicle.random_car(rng)
	_city.add_child(car)
	car.global_position = _top + Vector3(-80.0, 1.0, 0.0)
	await _ticks(2)
	var f := Blast4.side_flames(car)
	_t._check(f != null and f.get_parent() == car and f.emission_points.size() >= 16,
		"explosions_4: flames climb the wreck's sides from points round its sills")
	var pool := BlastPool.spawn(car, parent, _top + Vector3(-90.0, 0.5, 0.0), 3.5, false, 1.0, 2.6)
	_t._check(pool != null and is_equal_approx(pool.stretch, 2.6), "explosions_4: a fuel trail is a stretched pool")
	if pool != null:
		pool.queue_free()
	car.queue_free()
	await _ticks(2)
	_t._check(FileAccess.get_file_as_string("res://scripts/weapons/blast_3.gd").contains("Blast4.crater_smooth"),
		"explosions_4: the crater's soot and cracks can be smooth")


## Round 6: flames as licking tongues, the crater's pit with depth, a lip and rubble.
func _round6(parent: Node) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	Blast4.tongue_quad(q)
	if Blast4.tongues():
		_t._check(q.size.y > q.size.x and q.material is ShaderMaterial
			and (q.material as ShaderMaterial).shader.resource_path.ends_with("flame_tongue.gdshader"),
			"explosions_4: a flame card is a tall tongue on the flame shader")
	else:
		_t._check(q.size == Vector2.ONE, "explosions_4: the flame tongues stay off when switched off")
	var fs := FileAccess.get_file_as_string("res://shaders/flame_tongue.gdshader")
	_t._check(fs.contains("INV_VIEW_MATRIX") and fs.contains("climb"), "explosions_4: the flame tongue stands upright and climbs")
	var mark := Node3D.new()
	parent.add_child(mark)
	mark.global_position = _top + Vector3(-40.0, 0.0, 30.0)
	var dressed := Blast4.pit_dress(mark, 1.7)
	_t._check(dressed == Blast4.pit_enabled and (not dressed or (mark.get_node_or_null("PitBowl") != null
		and mark.get_node_or_null("PitLip") != null and mark.get_node_or_null("PitRubble") != null)),
		"explosions_4: the pit has a traced bowl, a lip and loose rubble")
	_t._check(Blast4.lip_height(1.2, 2.0) > 0.0 and Blast4.lip_height(0.5, 2.0) == 0.0,
		"explosions_4: the lip stands round the opening, not over it")
	mark.queue_free()
	var qm := ShaderMaterial.new()
	qm.shader = load("res://shaders/blast_volume.gdshader")
	Blast4.dress_volume(qm, false, false)
	_t._check(float(qm.get_shader_parameter("quiet4")) == (Blast4.quiet_jitter if Blast4.quiet_enabled else 0.0)
		and FileAccess.get_file_as_string("res://shaders/blast_volume.gdshader").contains("jit = 0.5 + (jit - 0.5) * quiet4;"),
		"explosions_4: the march's jitter is narrowed (TAA does not clear it)")


## Round 7: the violent first half second, smoke ribbons behind debris, the shop fronts answer.
func _round7(parent: Node) -> void:
	var vs := FileAccess.get_file_as_string("res://shaders/blast_volume.gdshader")
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/blast_volume.gdshader")
	Blast4.dress_volume(m, true, false)
	_t._check(vs.contains("uniform float core4 = 0.0;") and vs.contains("vec3 blackbody4(float k)")
		and float(m.get_shader_parameter("core4")) == (1.0 if Blast4.core_enabled else 0.0),
		"explosions_4: the young ball's heat follows its depth (core4, off by default)")
	var r := Blast4.ribbon_material()
	_t._check(r != null and r.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "explosions_4: the debris smoke ribbons have their material")
	var bs := FileAccess.get_file_as_string("res://scripts/weapons/blast_debris.gd")
	_t._check(bs.contains("_ribbon.global_transform = Transform3D(Basis(), global_position)"),
		"explosions_4: the ribbons' box sits at the blast (at the world origin they were culled)")
	var got: Array = Blast4.facade_response(_city, _top + Vector3(0.0, 1.0, -120.0), 9.0)
	_t._check(got.size() == 2 and int(got[0]) >= 0, "explosions_4: the shop fronts' response runs (%d awnings, %d signs)" % [int(got[0]), int(got[1])])


## Round 8: the flesh cools faster than the heart; the dust is darker near the ground.
func _round8() -> void:
	var vs := FileAccess.get_file_as_string("res://shaders/blast_volume.gdshader")
	_t._check(vs.contains("temp * temp * 1.12, core4 * smoothstep(0.04, 0.14, t)"),
		"explosions_4: the young ball's flesh cools to orange-red under its white heart")
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/blast_volume.gdshader")
	Blast4.dress_volume(m, false, false)
	var d: Vector3 = m.get_shader_parameter("dust")
	_t._check(not Blast4.dark_dust or d.x < 0.15, "explosions_4: the volume's dust ring is darker (%.3f)" % d.x)


## Round 9: the shock ring kicks loose bodies outside the radius when the wave reaches them.
func _round9() -> void:
	var body := RigidBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 1.0, 0.6)
	cs.shape = bs
	body.add_child(cs)
	_city.add_child(body)
	var at := _top + Vector3(60.0, 1.0, -60.0)
	body.global_position = at + Vector3(12.0, 0.5, 0.0)
	await _ticks(3)
	var n := Blast4.shock_kick(_city, at, 9.0)
	await _ticks(8)
	_t._check(not Blast4.shock_enabled or (n >= 1 and body.linear_velocity.x > 0.5),
		"explosions_4: the shock ring kicks a loose body outside the radius outward (%d, %.2f m/s)" % [n, body.linear_velocity.x])
	body.queue_free()
	_t._check(Blast4.flash_night() <= 1.0 and Blast4.flash_night() >= Blast4.night_flash - 0.001
		and Blast4.fire_night_gain() >= 1.0 and Blast4.fire_night_range() >= 1.0,
		"explosions_4: night holds the flash down and lifts the fires (%.2f, %.2f)" % [Blast4.flash_night(), Blast4.fire_night_gain()])
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/blast_volume.gdshader")
	Blast4.dress_volume(vm, true, false)
	_t._check(float(vm.get_shader_parameter("night4")) == (1.0 if Blast4.night_enabled else 0.0)
		and FileAccess.get_file_as_string("res://scripts/weapons/blast_debris.gd").contains("air_points.append(p.pos)"),
		"explosions_4: night darkens the smoke's crowns; flying debris streaks, landed debris stands in tongues")


## Round 11: the shock ring on the ground, a blast against a wall.
func _round11(parent: Node) -> void:
	var ring := Blast4.ground_ring(parent, _top + Vector3(-60.0, 0.0, -60.0), Vector3.UP, 20.0)
	_t._check(not Blast4.ring_enabled or (ring != null and (ring.material_override as ShaderMaterial).shader.resource_path.ends_with("blast_ring.gdshader")),
		"explosions_4: a shock ring is laid on the ground")
	var gf: Node = ring.get_node_or_null("BlastGroundFlash") if ring != null else null
	var gsrc := FileAccess.get_file_as_string("res://shaders/blast_ground_flash.gdshader")
	_t._check(not (Blast4.ring_enabled and Blast4.ground_flash_enabled) or (gf != null
		and gsrc.contains("blend_add") and gsrc.contains("fog_disabled")),
		"explosions_4: the ground flash lights the street under the burst (additive, fog-free)")
	if ring != null:
		ring.queue_free()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 20.0, 12.0)
	cs.shape = bs
	wall.add_child(cs)
	_city.add_child(wall)
	var base := _top + Vector3(-90.0, 0.0, 60.0)
	wall.global_position = base + Vector3(0.0, 10.0, 0.0)
	await _ticks(2)
	var n0 := parent.get_child_count()
	var hit := Blast4.wall_blast(_city, parent, base + Vector3(1.8, 6.0, 0.0), 9.0)
	_t._check(not Blast4.wall_enabled or (hit and parent.get_child_count() >= n0 + 3),
		"explosions_4: a blast against a wall pours smoke and rains masonry and glass")
	var none := Blast4.wall_blast(_city, parent, base + Vector3(30.0, 6.0, 0.0), 9.0)
	_t._check(not none, "explosions_4: no wall, no wall blast")
	wall.queue_free()
	var dsrc := FileAccess.get_file_as_string("res://scripts/weapons/blast_debris.gd")
	_t._check(dsrc.contains("const RIB_MAX_LEN := 8.0") and dsrc.contains("Mesh.PRIMITIVE_TRIANGLES")
		and not dsrc.contains("PRIMITIVE_TRIANGLE_STRIP"),
		"explosions_4: debris ribbons are quads, at most 8 m (a joined strip drew wires across the sky)")
	var heaps := 0
	for c in parent.get_children():
		if String(c.name).begins_with("WallHeap") or String(c.name).begins_with("WallSlabs"):
			heaps += 1
	_t._check(not (Blast4.wall_enabled and Blast4.heavy_masonry) or heaps >= 2,
		"explosions_4: a wall blast throws slabs and leaves a heap at the foot (%d)" % heaps)
