extends RefCounted
## The third explosion pass (Blast3, BlastBits, the volume fireball, the haze, the scorch) for
## tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the autoloads.
## Stages a deck high over the player, sets off blasts on it and frees what it made. Checks: the
## switch and its hooks, the fireball is ONE volume node (not cards) that frees itself and is
## capped, the web keeps the cards / particles, chips and sparks land ON the deck and the chips
## come to rest there (none through it), burning debris settles flat, the smoke knows the fires
## that burn and forgets them when they are out, the heat haze reads the screen first, the
## crater's maps (fingers, embers), and the shaders' colour rules.

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
	_top = player.global_position + Vector3(0.0, 520.0, 0.0)
	_switch()
	_web_paths()
	_build_deck()
	BlastFX._recent.clear()
	var parent := WeaponFX.fx_parent(city)
	# An earlier file's blast still fading holds the names: Godot names this blast's BlastVolume /
	# BlastHaze "@MeshInstance3D@n" beside it and the searches below miss them (gate run 4242, as
	# explosions_2 in run 505). This blast gets the names to itself.
	var stale := 0
	for c in parent.get_children():
		# (BlastBits is the chips' shared pool, not a blast's: it stays.)
		if String(c.name).begins_with("Blast") and not String(c.name).begins_with("BlastBits") and not c.is_queued_for_deletion():
			c.queue_free()
			stale += 1
	if stale > 0:
		await _tree.process_frame
	var before := {}
	for c in parent.get_children():
		before[c] = true
	await _ticks(3)
	# An earlier file's chips (thrown on a deck it has freed since) are not this file's.
	if BlastBits.current() != null:
		BlastBits.current().clear()
	var at := _top + Vector3(0.0, 1.0, 0.0)
	WeaponFX.explosion(city, at, 9.0, 1.0)
	await _tree.process_frame
	_layers(parent, at)
	_fires(at)
	await _land(at)
	await _debris_settles(at)
	await _volume_life(parent)
	_crater_maps()
	_shaders()
	# Clean up everything the blasts added (the BlastBits pool stays: it is the scene's one).
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
	_deck.name = "Explosions3Deck"
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
	var src := FileAccess.get_file_as_string("res://scripts/weapons/blast_3.gd")
	_t._check(src.contains("OS.get_environment(\"EXPLOSIONS_3\") != \"0\""), "explosions_3: EXPLOSIONS_3=0 turns it off")
	_t._check(Blast3.enabled, "explosions_3: on by default")
	var wfx := FileAccess.get_file_as_string("res://scripts/weapons/weapon_fx.gd")
	_t._check(wfx.contains("Blast3.takes_fireball()") and wfx.contains("Blast3.bits_on()") and wfx.contains("Blast3.haze_on()"),
		"explosions_3: WeaponFX hands the fireball, the bits and the haze over")
	_t._check(FileAccess.get_file_as_string("res://scripts/weapons/blast_aftermath.gd").contains("Blast3.crater_maps(kind)"),
		"explosions_3: the crater asks for the new maps")


## The web keeps the cheap path: cards, particles, no screen-reading haze.
func _web_paths() -> void:
	var was := WeaponFX._web_cache
	WeaponFX._web_cache = 1
	var web_ok := not Blast3.takes_fireball() and not Blast3.bits_on() and not Blast3.haze_on()
	WeaponFX._web_cache = was
	_t._check(web_ok, "explosions_3: the web keeps the fireball cards, the particles and no haze")


func _layers(parent: Node, at: Vector3) -> void:
	_t._check(int(BlastFX.last.get("volume", 0)) > 0, "explosions_3: the fireball is the volume")
	var vol: MeshInstance3D = null
	var haze: MeshInstance3D = null
	for c in parent.get_children():
		if c is MeshInstance3D and not c.is_queued_for_deletion():
			var mi := c as MeshInstance3D
			if String(mi.name).begins_with("BlastVolume") and mi.global_position.distance_to(at) < 30.0:
				vol = mi
			if String(mi.name).begins_with("BlastHaze") and mi.global_position.distance_to(at) < 5.0:
				haze = mi
	var vm := vol.material_override as ShaderMaterial if vol != null else null
	_t._check(vm != null and vm.get_shader_parameter("noise3d") is ImageTexture3D and int(vm.get_shader_parameter("steps")) >= 8,
		"explosions_3: one volume node with its 3D noise and its march")
	# Its box holds the fireball: it reaches the ground and three radii up.
	var box_ok := vol != null and vol.global_position.y - vol.global_basis.y.length() <= at.y \
			and vol.global_position.y + vol.global_basis.y.length() >= at.y + 9.0 * 2.5
	_t._check(box_ok, "explosions_3: the volume's box holds the fireball's travel")
	var cards := 0
	for c in parent.get_children():
		if c is CPUParticles3D and not c.is_queued_for_deletion() and (c as CPUParticles3D).global_position.distance_to(at) < 2.0:
			var m := ((c as CPUParticles3D).mesh as QuadMesh).material if (c as CPUParticles3D).mesh is QuadMesh else null
			if m == WeaponFX._fire_material():
				cards += 1
	_t._check(cards == 0, "explosions_3: no fireball cards under the volume (%d)" % cards)
	_t._check(haze != null and (haze.material_override as Material).render_priority == Material.RENDER_PRIORITY_MIN,
		"explosions_3: the heat haze reads the screen first")
	var bits := BlastBits.current()
	_t._check(bits != null and bits.chips_alive() > 0 and bits.sparks_alive() > 0, "explosions_3: chips and sparks thrown as BlastBits")


## The smoke knows the fire that burns (the flash's glow light), and the old young-puff glow goes
## with it.
func _fires(at: Vector3) -> void:
	var list := Blast3.fire_list(_tree)
	var near := false
	for v in list:
		near = near or Vector3(v.x, v.y, v.z).distance_to(at) < 9.0
	_t._check(near, "explosions_3: the smoke is lit by the blast's fire (%d fires)" % list.size())
	Blast3.push_fires(_tree)
	_t._check(int(BlastFX.smoke_material().get_shader_parameter("fire_count")) == list.size(), "explosions_3: the fires reach the smoke shader")


## Chips and sparks come down ON the deck; the chips skid and come to rest there.
func _land(at: Vector3) -> void:
	var bits := BlastBits.current()
	if bits == null:
		_t._check(false, "explosions_3: bits to watch")
		return
	var landed0 := int(bits.stats.sparks_landed)
	for i in 300:
		await _tree.physics_frame
		if bits.chips_resting() >= 20:
			break
	var under := 0
	var near := 0
	for k in BlastBits.max_chips:
		if bits._cstate[k] == BlastBits.FREE:
			continue
		var p := bits.to_global(bits._cp[k])
		if p.distance_to(at) > 200.0:
			continue
		near += 1
		under += 1 if p.y < _top.y - 0.25 else 0
	if under > 0:
		var shown := 0
		for k in BlastBits.max_chips:
			if bits._cstate[k] != BlastBits.FREE and shown < 6:
				var p := bits.to_global(bits._cp[k])
				if p.y < _top.y - 0.25:
					shown += 1
					print("EXPLOSIONS_3 under chip state=%d age=%.2f y=%.2f top=%.2f v=%s" % [bits._cstate[k], bits._cage[k], p.y, _top.y, bits._cv[k]])
	_t._check(bits.chips_resting() > 10, "explosions_3: chips come to rest (%d resting)" % bits.chips_resting())
	_t._check(near > 0 and under == 0, "explosions_3: no chip through the deck (%d of %d)" % [under, near])
	_t._check(int(bits.stats.sparks_landed) > landed0, "explosions_3: sparks land on the deck (%d)" % (int(bits.stats.sparks_landed) - landed0))
	_t._check(int(bits.stats.bounces) > 0, "explosions_3: chips bounce")


## The burning lumps skid and lie flat on what they landed on.
func _debris_settles(at: Vector3) -> void:
	var d: BlastDebris = null
	for c in WeaponFX.fx_parent(_city).get_children():
		if c is BlastDebris and not c.is_queued_for_deletion() and (c as Node3D).global_position.distance_to(at) < 5.0:
			d = c
	if d == null:
		_t._check(false, "explosions_3: debris to watch")
		return
	await _ticks(60)
	if not is_instance_valid(d):
		return
	var flat := 0
	var down := 0
	for p: Dictionary in d._pieces:
		if p.get("ground", null) == null:
			continue
		down += 1
		var mi: MeshInstance3D = p.node
		if mi.basis.orthonormalized().y.dot(p.ground) > 0.9:
			flat += 1
	_t._check(down > 0 and flat * 2 >= down, "explosions_3: burning debris lies flat where it stops (%d of %d)" % [flat, down])


## The volume frees itself; a burst of blasts is capped.
func _volume_life(parent: Node) -> void:
	BlastFX._recent.clear()
	for i in 7:
		WeaponFX.explosion(_city, _top + Vector3(float(i) * 6.0 - 18.0, 1.0, 60.0), 9.0, 1.0)
	_t._check(Blast3.volumes_alive() <= Blast3.max_volumes, "explosions_3: volumes capped (%d)" % Blast3.volumes_alive())
	var t0 := Time.get_ticks_msec()
	while Blast3.volumes_alive() > 0 and Time.get_ticks_msec() - t0 < 20000:
		await _tree.process_frame
	_t._check(Blast3.volumes_alive() == 0, "explosions_3: the volumes free themselves")


func _crater_maps() -> void:
	var maps := BlastAftermath.crater_textures(0)
	_t._check(maps.size() == 3, "explosions_3: crater maps are albedo, normal and embers")
	if maps.size() < 3:
		return
	var alb := (maps[0] as Texture2D).get_image()
	var emi := (maps[2] as Texture2D).get_image()
	if alb.is_compressed() or emi.is_compressed():
		return
	var n := alb.get_width()
	# Fingers: the soot's reach changes round the circle (a disc would not).
	var dark := 0
	var light := 0
	for i in 72:
		var a := TAU * float(i) / 72.0
		var px := Vector2(n * 0.5, n * 0.5) + Vector2(cos(a), sin(a)) * n * 0.5 * 0.62
		var c := alb.get_pixel(int(px.x), int(px.y))
		if c.a > 0.6 and c.r < 0.12:
			dark += 1
		else:
			light += 1
	_t._check(dark > 3 and light > 3, "explosions_3: the scorch reaches out in fingers (%d soot, %d not)" % [dark, light])
	var centre := emi.get_pixel(n / 2, n / 2)
	var edge := emi.get_pixel(4, n / 2)
	_t._check(edge.r < 0.02 and emi.get_pixel(int(n * 0.9), int(n * 0.9)).r < 0.02, "explosions_3: no embers outside the pit")
	var hot := 0
	for y in range(n * 3 / 8, n * 5 / 8, 4):
		for x in range(n * 3 / 8, n * 5 / 8, 4):
			hot += 1 if emi.get_pixel(x, y).r > 0.2 else 0
	_t._check(hot > 0 or centre.r > 0.2, "explosions_3: embers glow in the pit (%d)" % hot)


func _shaders() -> void:
	var vs := FileAccess.get_file_as_string("res://shaders/blast_volume.gdshader")
	_t._check(vs.contains("color_space.gdshaderinc") and vs.contains("cs_srgb_to_linear(sky_tint.rgb)") and vs.contains("cs_out(col / alpha)"),
		"explosions_3: the volume works in linear on both renderers")
	_t._check(vs.contains("depth_test_disabled") and vs.contains("cull_front"), "explosions_3: the volume draws with the camera inside it")
	for f in ["blast_volume", "blast_haze", "blast_spark", "blast_smoke"]:
		var src := FileAccess.get_file_as_string("res://shaders/%s.gdshader" % f)
		_t._check(not src.contains("instance uniform"), "explosions_3: %s has no instance uniforms" % f)
	var hz := FileAccess.get_file_as_string("res://shaders/blast_haze.gdshader")
	_t._check(hz.contains("VERTEX.z - behind.z"), "explosions_3: the haze bends only what is behind it")
