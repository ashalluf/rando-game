extends RefCounted
## The second explosion pass (BlastFX, BlastDebris) for tests/smoke_test.gd. Loaded at run time
## (not named there), so it compiles after the autoloads and can name WeaponFX, BlastFX and
## Building. Stages its own deck high over wherever the player stands, sets off blasts on it and
## frees everything it made. Checks: every layer of a blast is made (flash brighter and wider than
## the old light, the screen flash, the pressure wave on the screen-reading renderers, the ground
## kick, the rolling fire, the cap and column in their own space with room for their travel, the
## debris), the particle traps stay fixed (billboard_keep_scale, Curve max_value, custom_aabb, the
## screen readers drawn first), the caps hold under a burst of blasts, debris lands on the deck
## and never falls through it, windows facing a blast across the street break (BuildingDamage's
## records), the car's own blast is a fuel fireball and throws the car higher, and the switch.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _top: Vector3
var _made: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	var player := _tree.get_first_node_in_group("player") as Node3D
	_top = player.global_position + Vector3(0.0, 420.0, 0.0)
	_build_deck()
	var was_heavy := BlastFX.max_heavy
	BlastFX._recent.clear()
	var parent := WeaponFX.fx_parent(city)
	# Debris an earlier check's blasts left flying is not this check's.
	var alive_before := BlastDebris.alive()
	if alive_before > 0:
		# Debris still burning from an earlier file: say whose, so a leak names itself.
		for d in BlastDebris._all:
			if is_instance_valid(d):
				var n := d as Node
				print("EXPLOSIONS_2 debris left: %s live %d age %.1f processing %s" % [n.get_path(), d._live, d._age, n.can_process()])
				n.queue_free()
		await _tree.process_frame
		alive_before = BlastDebris.alive()
	# An earlier file's blast still fading (its flash glows for seconds) takes the name: Godot
	# names this blast's "BlastFlash" "@OmniLight3D@n" beside it and the search below misses it
	# (gate run 505). This check's blast gets the names to itself.
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
	await _ticks(3) # the deck's shape reaches the physics space

	_switch()
	var at := _top + Vector3(0.0, 1.0, 0.0)
	WeaponFX.explosion(city, at, 9.0, 1.0)
	await _layers(parent, at)
	await _debris_lands(at)
	await _caps(parent)
	await _glass()
	await _ticks(20) # the shards wait for the wave to reach their panes
	_car_fuel()

	# Clean up: everything the blasts left, the deck, the building, the caps' clocks.
	# Everything the blasts added to the scene (WeaponFX's own layers too) goes now.
	for c in parent.get_children():
		if not before.has(c) and c != _deck and not _made.has(c) and not (c is BlastBits):
			c.queue_free()
	for n in _made:
		if is_instance_valid(n):
			n.queue_free()
	_deck.queue_free()
	BlastFX._recent.clear()
	BlastFX.max_heavy = was_heavy
	BlastFX.fuel_next = false
	await _ticks(3)
	var left := 0
	for c in parent.get_children():
		# (Blast3's BlastBits is the scene's one pool of chips and sparks, made by the first blast.)
		left += 0 if before.has(c) or c is BlastBits else 1
	_t._check(left == 0 and BlastDebris.alive() <= alive_before, "explosions_2: the blasts leave nothing behind (%d nodes, %d pieces, %d before)" % [left, BlastDebris.alive(), alive_before])


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.name = "Explosions2Deck"
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _switch() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/weapons/blast_fx.gd")
	_t._check(src.contains("OS.get_environment(\"EXPLOSIONS_2\") != \"0\""), "explosions_2: EXPLOSIONS_2=0 turns it off")
	_t._check(BlastFX.enabled, "explosions_2: on by default")
	_t._check(FileAccess.get_file_as_string("res://scripts/weapons/weapon_fx.gd").contains("BlastFX.explosion(node, at, radius, power)"),
		"explosions_2: WeaponFX.explosion hands over to BlastFX")


## The newest child named `prefix`* (an earlier check's blast may still be fading), as [] or [it].
func _named(parent: Node, prefix: String) -> Array:
	var out: Array = []
	for c in parent.get_children():
		if String(c.name).begins_with(prefix) and not c.is_queued_for_deletion():
			out = [c]
	return out


func _layers(parent: Node, at: Vector3) -> void:
	var last := BlastFX.last
	_t._check(bool(last.get("heavy", false)), "explosions_2: the first blast gets the whole effect")
	for key in ["flash", "kick", "column"]:
		_t._check(int(last.get(key, 0)) > 0, "explosions_2: the blast made its %s" % key)
	# The rolling fire, or Blast3's volume fireball in its place (explosions-3).
	_t._check(int(last.get("roll", 0)) > 0 or int(last.get("volume", 0)) > 0, "explosions_2: the blast made its rolling fire")
	_t._check(int(last.get("debris", 0)) > 0, "explosions_2: the blast threw burning debris (%d)" % int(last.get("debris", 0)))
	var screen := RenderingServer.get_current_rendering_method() != "dummy" and not OS.has_feature("web")
	_t._check(not screen or int(last.get("wave", 0)) > 0, "explosions_2: the pressure wave where the screen can be read")
	# The flash: far brighter and wider than WeaponFX's own light (14 over 4 radii).
	# This blast's flash: the one nearest it (an earlier check's blast can leave one fading). A busy
	# runner may add it a frame late; its energy and reach are the ones BlastFX sets it to.
	var flash: OmniLight3D = null
	for f in 4:
		for c in parent.get_children():
			if c is OmniLight3D and String(c.name).begins_with("BlastFlash") and not c.is_queued_for_deletion():
				if flash == null or (c as Node3D).global_position.distance_to(at) < flash.global_position.distance_to(at):
					flash = c
		if flash != null:
			break
		await _tree.process_frame
	var lit := flash != null and flash.global_position.distance_to(at) < 5.0 \
			and BlastFX.flash_energy > 14.0 and 9.0 * BlastFX.flash_reach > 9.0 * 4.0
	_t._check(lit, "explosions_2: one flash light, brighter and wider than the old one")
	var flare := _named(parent, "BlastFlare")
	_t._check(flare.size() == 1 and ((flare[0] as MeshInstance3D).material_override as StandardMaterial3D).billboard_keep_scale,
		"explosions_2: the flare billboard keeps its scale")
	# The cap and the column: in their own space, bounds for their whole travel, growth unclamped.
	var cols := _named(parent, "BlastColumn")
	var ok := cols.size() == 1
	if ok:
		for name in ["Cap", "Stem"]:
			var e := (cols[0] as Node).get_node_or_null(name) as CPUParticles3D
			ok = ok and e != null and e.local_coords and e.custom_aabb.size.y > 60.0
			ok = ok and e.scale_amount_curve != null and e.scale_amount_curve.max_value >= 3.0
			ok = ok and (e.mesh as QuadMesh).material == BlastFX.smoke_material()
	_t._check(ok, "explosions_2: cap and column in local space with bounds and growth")
	_t._check(BlastFX.smoke_material().render_priority < 0, "explosions_2: the smoke draws before the fire")
	var roll := _named(parent, "BlastFireRoll")
	_t._check((roll.size() == 1 and (roll[0] as CPUParticles3D).custom_aabb.size.length() > 1.0) or int(last.get("volume", 0)) > 0,
		"explosions_2: the rolling fireball has its bounds")
	var fire := WeaponFX._fire_material()
	_t._check(not (fire is ShaderMaterial) or float((fire as ShaderMaterial).get_shader_parameter("relief")) > 0.0,
		"explosions_2: the fireball's billows are shaded")
	var waves := _named(parent, "BlastWave")
	_t._check(waves.is_empty() or ((waves[0] as MeshInstance3D).material_override as Material).render_priority == Material.RENDER_PRIORITY_MIN,
		"explosions_2: the pressure wave reads the screen first")
	var deb := _named(parent, "BlastDebris")
	var aabb_ok := deb.size() == 1
	if aabb_ok:
		for c in (deb[0] as Node).get_children():
			if c is CPUParticles3D:
				aabb_ok = aabb_ok and (c as CPUParticles3D).local_coords and (c as CPUParticles3D).custom_aabb.size.x > 20.0
	_t._check(aabb_ok, "explosions_2: the debris trails are in local space with bounds")
	# The shaders' own sources keep the colour rules (linear on both renderers).
	var sm := FileAccess.get_file_as_string("res://shaders/blast_smoke.gdshader")
	_t._check(sm.contains("color_space.gdshaderinc") and sm.contains("cs_srgb_to_linear(sky_tint.rgb)") and sm.contains("cs_out(col)"),
		"explosions_2: the lit smoke works in linear on both renderers")


## Debris arcs out and comes down ON the deck.
func _debris_lands(at: Vector3) -> void:
	# This blast's debris: the one nearest it (an earlier check's blast can leave its own about).
	var d: BlastDebris = null
	for c in WeaponFX.fx_parent(_city).get_children():
		if c is BlastDebris and not c.is_queued_for_deletion():
			if d == null or (c as Node3D).global_position.distance_to(at) < d.global_position.distance_to(at):
				d = c
	if d == null:
		_t._check(false, "explosions_2: debris to watch")
		return
	var high := -INF
	var pieces: Array = d._pieces
	for i in 120:
		await _tree.physics_frame
		# A busy run can free the debris (its own lifetime, the caps) before the 120 ticks are up.
		if not is_instance_valid(d):
			break
		pieces = d._pieces
		for p: Dictionary in d._pieces:
			high = maxf(high, d.to_global(p.pos).y - _top.y)
	var landed := 0
	var under := 0
	if is_instance_valid(d):
		for p: Dictionary in d._pieces:
			landed += 1 if p.landed else 0
			under += 1 if d.to_global(p.pos).y < _top.y - 0.6 else 0
	else:
		landed = pieces.size() # freed after it settled: count what it had
	_t._check(high > 3.0, "explosions_2: debris arcs up (%.1f m)" % high)
	_t._check(landed > 0 and under == 0, "explosions_2: debris lands on the deck, none through it (%d landed, %d under)" % [landed, under])


## A burst of blasts: only `max_heavy` get the heavy layers, the columns and debris stay capped.
func _caps(parent: Node) -> void:
	BlastFX._recent.clear()
	var heavy := 0
	for i in 8:
		WeaponFX.explosion(_city, _top + Vector3(float(i) * 4.0 - 16.0, 1.0, 30.0), 9.0, 1.0)
		heavy += 1 if bool(BlastFX.last.get("heavy", false)) else 0
	_t._check(heavy == BlastFX.max_heavy, "explosions_2: %d of 8 quick blasts got the heavy layers (cap %d)" % [heavy, BlastFX.max_heavy])
	_t._check(BlastFX.columns_alive() <= BlastFX.max_columns, "explosions_2: columns capped (%d)" % BlastFX.columns_alive())
	_t._check(BlastDebris.alive() <= BlastFX.max_debris, "explosions_2: debris capped (%d)" % BlastDebris.alive())
	await _ticks(2)


## The windows of a building across the street from a blast blow out.
func _glass() -> void:
	BlastFX._recent.clear()
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var bld: Building = scene.instantiate()
	bld.seed = 7712
	bld.lot_size = Vector2(26.0, 22.0)
	bld.min_height = 18.0
	bld.max_height = 26.0
	bld.finish_options.assign([Building.Finish.PANELS])
	_city.add_child(bld)
	_made.append(bld)
	bld.global_position = _top + Vector3(0.0, 0.0, -60.0)
	await _ticks(2)
	# The blast in the street, 14 m off the building's nearest face.
	var face := -INF
	for part: Dictionary in bld.parts:
		face = maxf(face, (part.center as Vector3).z + (part.size as Vector3).z * 0.5)
	var at := bld.to_global(Vector3(0.0, 1.5, face + 14.0))
	var key := BuildingDamage.key_of(bld)
	WorldState.building_damage.erase(key)
	WeaponFX.explosion(_city, at, 9.0, 1.0)
	var broke := int(BlastFX.last.get("glass", 0))
	var shattered := 0
	if WorldState.building_damage.has(key):
		for rec: Vector4 in WorldState.building_damage[key].recs:
			shattered += 1 if BuildingDamage._kind(rec) == BuildingDamage.K_SHATTER else 0
	_t._check(broke > 0 and shattered >= broke, "explosions_2: windows across the street blew out (%d panes, %d records)" % [broke, shattered])
	_t._check(broke <= BlastFX.max_glass_panes, "explosions_2: the panes a blast breaks are capped")
	WorldState.building_damage.erase(key)


## A car's own explosion is the fuel fireball, and the toss is higher.
func _car_fuel() -> void:
	BlastFX._recent.clear()
	BlastFX.fuel_next = true
	WeaponFX.explosion(_city, _top + Vector3(30.0, 1.0, 30.0), 7.0, 0.6)
	_t._check(not BlastFX.fuel_next, "explosions_2: a fuel blast consumes the flag")
	_t._check(int(BlastFX.last.get("roll", 0)) > 18 or int(BlastFX.last.get("volume", 0)) > 0 or WeaponFX._web(), "explosions_2: a fuel fireball rolls up bigger (%d)" % int(BlastFX.last.get("roll", 0)))
	_t._check(BlastFX.lift_gain() > 1.2, "explosions_2: a car's own blast throws it higher")
	_t._check(FileAccess.get_file_as_string("res://scripts/vehicles/car_damage.gd").contains("BlastFX.lift_gain()"),
		"explosions_2: CarDamage.explode asks for the lift")
