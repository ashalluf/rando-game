class_name Blast4
extends RefCounted
## The explosion, fourth pass (fleet wave 5, "explosions-4": the owner's "make the explosions
## EXTREMELY AAA"). The third pass made the fireball a ray-marched volume that lived 2.7 s and then
## handed the sky over to card smoke, which read as a string of separate grey balls. This pass:
##  - THE MUSHROOM IS THE VOLUME. The fireball lives on (`life_for()`: 9 s, a car 12, gas 8): it
##    rises and flattens into a cap that rolls as a vortex ring over a wavering stem, and cools from
##    fire to black soot to a paling grey-brown smoke that thins as it spreads. The noise is rolled
##    round the ring's core and advected by a curl field (blast_volume.gdshader `v4`), so the
##    billows turn over instead of scrolling; the soot is lit through three shadow taps with a
##    multiple-scattering lift; a dust ring runs out along the ground. BlastFX's card cap is left out
##    under it and its card column starts late, high up, as the smoke the volume hands over to.
##  - SECONDARY EXPLOSIONS (`secondaries()`): a car's fuel blast sets off two to four smaller pops
##    over the next 1.6 s round the wreck (the tank, the tyres, a line) - a small fireball each
##    (the volume when there is room, cards else), a flash, sparks, a shudder and a bang.
##  - A FUEL FIRE POOL (`BlastPool`, scripts/weapons/blast_pool.gd): burning petrol spread over
##    the road where a car went up (or a pump), flames licking off it for 15-25 s, its light on the
##    street and on the smoke (Blast3's fire list).
##  - GAS: a shot-up petrol pump (PropBreak's pump hook) goes up as a vapour fireball (`gas_next`):
##    rounder, brighter, cleaner, bigger, with a pool of burning fuel on the forecourt.
##  - CHAIN REACTIONS: a car's fuel blast hands the cars round it a short staggered fuse
##    (`chain()`), so a row of parked cars goes up one after another instead of all at once or not
##    at all.
##  - THE PUNCH: the bang arrives at the speed of sound (`sound_delay()`), a low thump under it up
##    close, and the camera shake comes with the pressure wave, harder and longer for a fuel blast.
## EXPLOSIONS_4=0 in the environment is the A/B (the third pass exactly).

static var enabled: bool = OS.get_environment("EXPLOSIONS_4") != "0"
## The daylight value range of the mushroom (blast_volume.gdshader `value4`): sunlit billows near
## white, deep soot in the folds. BLAST_VALUE=0 is the A/B (the round-3 flat grey).
static var value_enabled: bool = OS.get_environment("BLAST_VALUE") != "0"
static var value_range: float = 1.0
## The fires under the smoke light its underside (blast_volume.gdshader `under4`): the night cap
## glows over a burning wreck. BLAST_UNDERLIGHT=0 is the A/B.
static var underlight_enabled: bool = OS.get_environment("BLAST_UNDERLIGHT") != "0"
static var underlight_gain: float = 0.5
## The mushroom's stem holds to the end of its life (blast_volume.gdshader `stem_hold`).
## BLAST_STEM=0 is the A/B.
static var stem_enabled: bool = OS.get_environment("BLAST_STEM") != "0"
## A car blast throws a trail of fuel out across the road (two stretched pools, `fuel_trail()`)
## and flames climb the wreck's sides from the sills (`side_flames()`). BLAST_WRECK_FIRE=0 the A/B.
static var wreck_fire_enabled: bool = OS.get_environment("BLAST_WRECK_FIRE") != "0"
static var side_flame_seconds: float = 14.0
## The crater's soot specks from a smooth noise (Blast3.crater_maps()): BLAST_CRATER=0 the A/B.
static var crater_smooth: bool = OS.get_environment("BLAST_CRATER") != "0"
## Flames as tall licking tongues (shaders/flame_tongue.gdshader) in place of the round fire
## puffs: the car fire, the pools, the wreck's sides, the burning debris. BLAST_FLAMES=0 the A/B.
static var flames_enabled: bool = OS.get_environment("BLAST_FLAMES") != "0"
## The crater's pit with depth (`pit_dress()`): a traced bowl, a raised lip of earth and loose
## chunks on it. BLAST_PIT=0 is the A/B.
static var pit_enabled: bool = OS.get_environment("BLAST_PIT") != "0"
static var pit_depth: float = 0.35 # metres of depth per metre of pit radius
static var _pit_shader: Shader
static var _lip_mat: StandardMaterial3D
static var _rock_mesh: ArrayMesh
static var _flame_mat: ShaderMaterial

## The volume's life (seconds) by kind, and the march's steps (the mushroom's box is taller).
static var volume_life: float = 9.0
static var fuel_life: float = 12.0
static var gas_life: float = 8.0
static var volume_steps: int = 40
## Set by whoever sets off a gas blast just before it (PropBreak's pump): that one is vapour.
static var gas_next: bool = false
## Set while WeaponFX lays a gas blast (read by the volume and BlastFX).
static var this_gas: bool = false
## The blast BlastFX is laying out now was a fuel one (its flash's glow lasts longer).
static var this_fuel: bool = false
## The fire's glow after the flash: how much longer it lasts for a fuel / gas fireball.
static var fuel_glow_stretch: float = 1.7
static var gas_glow_stretch: float = 1.3
## ... and how much longer again after dark.
static var night_glow_stretch: float = 0.8

## Secondary pops after a fuel blast: how many (min, max), over how long, how far out (radii).
static var secondary_count: Vector2i = Vector2i(2, 4)
static var secondary_window: float = 1.6
static var secondary_reach: float = 0.55
## Chain reactions: cars within this many radii of a fuel blast catch a fuse this long, at most
## `chain_depth` cars deep from the first (a kerb of parked cars would go up to the horizon).
static var chain_reach: float = 1.15
static var chain_fuse: Vector2 = Vector2(0.5, 1.7)
static var chain_depth: int = 3
## The bang: metres a second it travels (0 plays it at once), the low thump's reach (radii).
static var sound_speed: float = 343.0
static var thump_reach: float = 7.0
## The shake: how far it reaches (radii) and a fuel blast's extra.
static var shake_reach: float = 8.0
static var fuel_shake: float = 1.35


## The volume's life for a blast of this kind.
static func life_for(fuel: bool, gas: bool) -> float:
	if gas:
		return gas_life
	return fuel_life if fuel else volume_life


## Blast3.spawn_volume()'s hook: the mushroom's box (half extents and centre, radii) and the
## shader's fourth-pass uniforms. Returns [half, centre, life].
static func dress_volume(mat: ShaderMaterial, fuel: bool, gas: bool) -> Array:
	var big := 1.0 + (0.3 if fuel else 0.0) + (0.25 if gas else 0.0)
	var life := life_for(fuel, gas)
	mat.set_shader_parameter("v4", 1.0)
	mat.set_shader_parameter("gas", 1.0 if gas else 0.0)
	mat.set_shader_parameter("life", life)
	mat.set_shader_parameter("steps", volume_steps)
	mat.set_shader_parameter("value4", value_range if value_enabled else 0.0)
	mat.set_shader_parameter("under4", underlight_gain if underlight_enabled else 0.0)
	mat.set_shader_parameter("stem_hold", 1.0 if stem_enabled else 0.0)
	return [Vector3(2.3, 2.1, 2.3) * big, Vector3(0.0, 2.0, 0.0) * big, life]


## The mushroom cap's height (radii over the blast) at `t` seconds: where BlastFX's card smoke
## takes over (blast_volume.gdshader's cap_y4 for a rocket).
static func handover_height(t: float) -> float:
	return 0.3 + 1.05 * (1.0 - exp(-t / 1.1)) + 0.13 * t


## The fade over the volume's life (1 drawn .. 0 gone): the mushroom thins itself in the shader
## (its age term), so the fade is only the last share.
static func fade_at(t: float, life: float) -> float:
	return 1.0 - smoothstep(life * 0.7, life, t)


## Seconds before the bang reaches the camera from `at`.
static func sound_delay(node: Node, at: Vector3) -> float:
	if not enabled or sound_speed <= 0.0:
		return 0.0
	var cam := WeaponFX._camera(node)
	if cam == null:
		return 0.0
	return cam.global_position.distance_to(at) / sound_speed


## The bang and the shake, called by Explosion.blast() in place of its Sfx line and by WeaponFX
## in place of its shake. Returns true when it played them (false: the caller plays the old way).
static func punch(node: Node, at: Vector3, radius: float, fuel: bool) -> bool:
	if not enabled or node == null or not node.is_inside_tree():
		return false
	var delay := sound_delay(node, at)
	var cam := WeaponFX._camera(node)
	var d := cam.global_position.distance_to(at) if cam != null else 1e9
	var tree := node.get_tree()
	var gain := 1.0 + (0.25 if fuel else 0.0)
	var play := func():
		Sfx.play("explosion", at, 4.0 + 2.0 * gain, randf_range(0.92, 1.04))
		# A low thump under it up close: the same take pitched down, the chest-punch.
		if d < radius * thump_reach:
			Sfx.play("explosion", at, 3.0 * (1.0 - d / (radius * thump_reach)) + 1.0, randf_range(0.48, 0.58))
	if delay > 0.02:
		tree.create_timer(delay, false).timeout.connect(play)
	else:
		play.call()
	_shake(node, at, radius, fuel, delay)
	return true


static func _shake(node: Node, at: Vector3, radius: float, fuel: bool, delay: float) -> void:
	var player := node.get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var rig: Node = player.get("camera_rig")
	if rig == null or not rig.has_method("shake"):
		return
	var dist := player.global_position.distance_to(at)
	var falloff := clampf(1.0 - dist / (radius * shake_reach), 0.0, 1.0)
	if falloff <= 0.0:
		return
	var amount := falloff * falloff * (fuel_shake if fuel else 1.0)
	# A jolt with the light, the real shake when the pressure wave arrives, a rumble after it.
	rig.shake(minf(amount * 0.35, 1.0))
	var tree := node.get_tree()
	tree.create_timer(maxf(delay, 0.03), false).timeout.connect(func():
		if is_instance_valid(rig):
			rig.shake(minf(amount, 1.0)))
	tree.create_timer(maxf(delay, 0.03) + 0.35, false).timeout.connect(func():
		if is_instance_valid(rig):
			rig.shake(minf(amount * 0.3, 1.0)))


## Everything a fuel or gas blast adds after WeaponFX has laid it (the pool, the pops, the
## chain). Called last thing in BlastFX.explosion().
static func after_blast(node: Node, parent: Node, at: Vector3, radius: float, fuel: bool, gas: bool) -> Dictionary:
	var made := {}
	if not enabled or node == null or not node.is_inside_tree() or parent == null:
		return made
	if fuel or gas:
		made["pool"] = BlastPool.spawn(node, parent, at, radius * (1.25 if gas else 1.0), gas) != null
		if fuel and wreck_fire_enabled:
			made["trail"] = fuel_trail(node, parent, at, radius)
			if node is Vehicle:
				made["sides"] = side_flames(node as Node3D) != null
		made["secondaries"] = secondaries(node, parent, at, radius, gas)
	if fuel:
		made["chain"] = chain(node, at, radius, int(node.get_meta("chain_gen", 0)) + 1)
	return made


## Gas: a petrol pump shot to pieces goes up (PropBreak.broke()'s hook, the pump still breaks the
## old way too). The blast waits a beat (the fuel finds the spark), and at most `gas_burst` pumps go
## in `gas_window` seconds, each a little after the last, so a forecourt goes up in a ripple, not
## all in one frame.
static var gas_radius: float = 8.5
static var gas_burst: int = 3
static var gas_window: float = 4.0
static var _gas_times: Array[float] = []


static func pump_break(ch: Node3D, record: Dictionary) -> bool:
	if not enabled or ch == null or not ch.is_inside_tree():
		return false
	var now := Time.get_ticks_msec() * 0.001
	_gas_times = _gas_times.filter(func(t): return now - t < gas_window)
	if _gas_times.size() >= gas_burst:
		return false
	var at := ch.to_global(record.position as Vector3)
	var space := ch.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 4.0, at - Vector3.UP * 6.0, 1))
	if not hit.is_empty():
		at = hit.position
	var delay := 0.12 + 0.35 * float(_gas_times.size()) + randf() * 0.15
	_gas_times.append(now + delay)
	ch.get_tree().create_timer(delay, false).timeout.connect(func():
		if is_instance_valid(ch) and ch.is_inside_tree():
			gas_next = true
			Explosion.blast(ch, at + Vector3.UP * 0.9, gas_radius, 26.0, 18.0)
			gas_next = false)
	return true


## The secondary pops: scheduled on timers (the tree's, paused with it). Returns how many.
static func secondaries(node: Node, parent: Node, at: Vector3, radius: float, gas: bool) -> int:
	var n := randi_range(secondary_count.x, secondary_count.y) + (1 if gas else 0)
	var tree := node.get_tree()
	for i in n:
		var delay := randf_range(0.25, secondary_window) * (0.6 + 0.4 * float(i + 1) / float(n))
		var ang := randf() * TAU
		var off := Vector3(cos(ang), 0.0, sin(ang)) * radius * randf_range(0.15, secondary_reach)
		var r := radius * randf_range(0.26, 0.42)
		tree.create_timer(delay, false).timeout.connect(func():
			if is_instance_valid(parent) and parent.is_inside_tree():
				pop(parent, at + off + Vector3.UP * randf_range(0.2, 1.4), r))
	return n


## One secondary pop at `at` of `radius` (a fraction of the main blast's): no damage, no crater.
static func pop(parent: Node, at: Vector3, radius: float) -> void:
	if Blast3.takes_fireball():
		# A pop is a fireball and a puff of soot, not a mushroom.
		Blast3.spawn_volume(parent, at, radius, false, 3.0)
	else:
		WeaponFX._puff_layer(parent, at, WeaponFX._count(14), radius * 0.6, 0.8, radius * 0.3, radius * 0.9, 2.0,
			WeaponFX._ramp([Color(4.0, 3.0, 1.8, 1.0), Color(2.0, 0.7, 0.14, 1.0), Color(0.6, 0.16, 0.04, 0.85),
				Color(0.07, 0.055, 0.05, 0.0)]), false, 180.0, 1.4, Basis(), 0.0, 0.4, 1.0, false,
			WeaponFX._ramp([Color(1.4, 1.3, 1.1), Color(1.0, 1.0, 1.0), Color(0.5, 0.38, 0.3)]), WeaponFX._fire_material())
	var light := OmniLight3D.new()
	light.name = "BlastPopLight"
	light.light_color = Color(1.0, 0.62, 0.28)
	light.light_energy = 16.0
	light.omni_range = radius * 6.0
	light.omni_attenuation = 1.5
	parent.add_child(light)
	light.global_position = at + Vector3.UP * radius * 0.4
	Blast3.add_fire(light)
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.5).set_ease(Tween.EASE_IN)
	lt.tween_callback(light.queue_free)
	if Blast3.bits_on():
		BlastBits.pool(parent).throw_sparks(at, WeaponFX._count(18), Vector2(radius * 2.0, radius * 4.5))
	Sfx.play("explosion", at, 1.0, randf_range(1.25, 1.5))
	_shake(parent, at, radius, false, 0.0)


## Chain reactions: every car within `chain_reach` radii of a fuel blast that is not already a
## wreck catches a short fuse, staggered by distance (the nearest goes first). Returns how many.
static func chain(node: Node, at: Vector3, radius: float, gen: int = 1) -> int:
	var n := 0
	if gen > chain_depth:
		return 0
	var reach := radius * chain_reach
	for c in node.get_tree().get_nodes_in_group("vehicle"):
		var car := c as Vehicle
		if car == null or not car.is_inside_tree() or not car.can_take_damage():
			continue
		var d := car.global_position.distance_to(at)
		if d > reach or d < 0.5:
			continue
		var dmg: Node = car.call("damage_state")
		if dmg == null or not dmg.has_method("chain_fuse"):
			continue
		var fuse := lerpf(chain_fuse.x, chain_fuse.y, d / reach) * randf_range(0.85, 1.2)
		if dmg.call("chain_fuse", fuse):
			car.set_meta("chain_gen", gen)
			n += 1
	return n


## BlastFX's glow light: how many times its old `glow_time` it lasts (1 without Blast4).
static func glow_stretch() -> float:
	if not enabled:
		return 1.0
	# At night the fire under the smoke is all that shows it: the glow lingers on.
	var night := 1.0 + night_glow_stretch * clampf(DayNight.lamp_now, 0.0, 1.0)
	return (fuel_glow_stretch if this_fuel else (gas_glow_stretch if this_gas else 1.0)) * night


## BlastFX's glow light: how fast it dies (the power on 1 - t; softer at night).
static func glow_fall() -> float:
	if not enabled:
		return 1.6
	return lerpf(1.6, 0.9, clampf(DayNight.lamp_now, 0.0, 1.0))


## BlastFX's glow light: its height in blast radii at the fraction `t` of its life, so the light
## on the facades and the street rises with the fireball (the mushroom's cap, Blast4) instead of
## a fixed climb. `base_time` is BlastFX.glow_time.
static func glow_height(t: float, base_time: float) -> float:
	if not enabled:
		return 0.45 + 0.9 * t
	# The light sits a little under the cap's centre (the fire is in its lower half).
	return maxf(0.35, handover_height(t * base_time * glow_stretch()) * 0.85)


## THE DUST ROLLS OUT: the shock's dust along the ground as a ROLLING front (BlastAftermath's
## dust wave hands over to it): one layer of even unlit puffs grew into a flat beige wall of one
## height. Here, fast low creepers that slow hard and bunch at the front, fewer lumpy rollers
## thrown a beat later that climb and break the top line, and a faint wide haze that hangs low
## and outlasts both - all lit smoke (the sun shapes them, night leaves them dark), each puff its
## own tint. Returns false when off (the old wave). BLAST_DUST_ROLL=0 is the A/B.
static var dust_roll_enabled: bool = OS.get_environment("BLAST_DUST_ROLL") != "0"
static var _dust_ramps: Array = []


static func dust_roll(parent: Node, ground: Vector3, normal: Vector3, reach: float) -> bool:
	if not enabled or not dust_roll_enabled or parent == null:
		return false
	if _dust_ramps.is_empty():
		# Linear albedo for the lit smoke material: street dust, alpha shaping each layer's life.
		_dust_ramps = [
			WeaponFX._ramp([Color(0.34, 0.31, 0.27, 0.0), Color(0.33, 0.30, 0.26, 0.62),
				Color(0.30, 0.28, 0.25, 0.42), Color(0.27, 0.26, 0.24, 0.0)]),
			WeaponFX._ramp([Color(0.30, 0.27, 0.24, 0.0), Color(0.29, 0.27, 0.24, 0.5),
				Color(0.27, 0.25, 0.23, 0.3), Color(0.25, 0.24, 0.22, 0.0)]),
			WeaponFX._ramp([Color(0.32, 0.30, 0.27, 0.0), Color(0.31, 0.29, 0.27, 0.2),
				Color(0.30, 0.28, 0.26, 0.14), Color(0.29, 0.28, 0.26, 0.0)]),
			# Per-puff tint: browner and paler lumps in one front.
			WeaponFX._ramp([Color(0.78, 0.74, 0.70, 1.0), Color(1.0, 0.97, 0.92, 1.0), Color(1.18, 1.12, 1.02, 1.0)])]
	var mat := BlastFX.smoke_material()
	var gb := WeaponFX._basis_up(normal)
	# The creepers: flat out along the ground, slowing hard so they bunch into a front.
	WeaponFX._puff_layer(parent, ground + normal * 0.3, WeaponFX._count(40), reach * 0.09, 3.0,
		reach * 0.5, reach * 0.95, 0.15, _dust_ramps[0], false, 180.0, 2.1, gb, 1.0, 0.45, 1.7, true,
		_dust_ramps[3], mat)
	# The rollers: a beat later, slower, bigger, rising - the front's lumpy top.
	var tw := parent.create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func():
		if is_instance_valid(parent):
			WeaponFX._puff_layer(parent, ground + normal * 0.6, WeaponFX._count(16), reach * 0.1, 4.2,
				reach * 0.25, reach * 0.6, 0.9, _dust_ramps[1], false, 180.0, 2.5, gb, 1.0, 0.5, 1.2, true,
				_dust_ramps[3], mat))
	# The haze: wide, faint, low; what hangs over the street after the front has gone.
	WeaponFX._puff_layer(parent, ground + normal * 0.25, WeaponFX._count(16), reach * 0.14, 5.5,
		reach * 0.35, reach * 0.7, -0.05, _dust_ramps[2], false, 180.0, 1.6, gb, 1.0, 0.4, 1.4, true,
		_dust_ramps[3], mat)
	return true


## The flare grows to this many radii (4.2 before) and fades over this long (0.13 s): on a fuel
## blast it reached ~30 m and caught mid-frame it was a blown-out white disc over the street.
static var flare_grow_radii: float = 3.0
static var flare_fade_seconds: float = 0.1


static func flare_grow() -> float:
	return flare_grow_radii if enabled else 4.2


static func flare_fade() -> float:
	return flare_fade_seconds if enabled else 0.13


## Burning debris as real chunks (BlastDebris): bigger wedges and torn thin panels, denser smoke
## trails. BLAST_CHUNKS=0 is the A/B.
static var debris_chunks: bool = OS.get_environment("BLAST_CHUNKS") != "0"
static var _panel: Mesh


## A torn panel: a thin bent sheet, one mesh for every piece (scaled per piece).
static func panel_mesh() -> Mesh:
	if _panel == null:
		# One bent sheet, drawn double-sided by its piece's material (BlastDebris).
		var pts := [Vector3(-0.5, 0.0, -0.4), Vector3(0.0, 0.12, -0.45), Vector3(0.48, -0.05, -0.32),
			Vector3(-0.42, 0.04, 0.38), Vector3(0.05, 0.14, 0.4), Vector3(0.5, 0.02, 0.3)]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for q in [[0, 1, 4, 3], [1, 2, 5, 4]]:
			for k in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(pts[q[k]])
		st.generate_normals()
		_panel = st.commit()
	return _panel


## The fuel a car's tank threw: two long tongues of burning fuel running out from the pool, their
## directions a hash of where it went up. Returns how many were laid.
static func fuel_trail(node: Node, parent: Node, at: Vector3, radius: float) -> int:
	var h := hash([int(floorf(at.x * 4.0)), int(floorf(at.z * 4.0)), "fuel_trail"])
	var made := 0
	for k in 2:
		var a := float((h >> (k * 9)) & 511) / 511.0 * TAU + float(k) * PI * 0.8
		var dir := Vector3(cos(a), 0.0, sin(a))
		var reach := BlastPool.pool_radius * clampf(radius / 7.0, 0.6, 1.8) * (1.15 + 0.35 * float((h >> (20 + k * 4)) & 15) / 15.0)
		var p := BlastPool.spawn(node, parent, at + dir * reach, radius * 0.5, false, a, 2.6)
		if p != null:
			p.life *= 0.6
			made += 1
	return made


## Flames licking up the wreck's sides: a ring of points round the body at sill height, tall
## narrow tongues rising up the doors and wings, riding the wreck wherever it was thrown, dying
## down over `side_flame_seconds`.
static func side_flames(car: Node3D) -> CPUParticles3D:
	if car == null or not car.is_inside_tree():
		return null
	var d: Dictionary = car.call("_dims") if car.has_method("_dims") else {}
	var hl := float(d.get("length", 4.6)) * 0.5 - 0.15
	var hw := float(d.get("width", 1.85)) * 0.5 + 0.02
	var y0 := float(d.get("road", -0.2)) + 0.22
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var n := 40
	for i in n:
		var u := float(i) / float(n)
		# Round the rectangle by its perimeter: the long sides take most of the points.
		var per := 2.0 * (hl + hw) * 2.0
		var s := u * per
		var p: Vector3
		var o: Vector3
		if s < 2.0 * hl:
			p = Vector3(hw, 0.0, -hl + s); o = Vector3.RIGHT
		elif s < 2.0 * hl + 2.0 * hw:
			p = Vector3(hw - (s - 2.0 * hl), 0.0, hl); o = Vector3.BACK
		elif s < 4.0 * hl + 2.0 * hw:
			p = Vector3(-hw, 0.0, hl - (s - 2.0 * hl - 2.0 * hw)); o = Vector3.LEFT
		else:
			p = Vector3(-hw + (s - 4.0 * hl - 2.0 * hw), 0.0, -hl); o = Vector3.FORWARD
		p.y = y0 + 0.25 * fposmod(float(i) * 0.618, 1.0)
		pts.append(p)
		nrm.append(o)
	var f := CPUParticles3D.new()
	f.name = "WreckSideFlames"
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.amount = WeaponFX._count(70)
	f.lifetime = 0.85
	f.lifetime_randomness = 0.45
	f.local_coords = false
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
	f.emission_points = pts
	f.emission_normals = nrm
	f.direction = Vector3(0.25, 1.0, 0.0)
	f.spread = 12.0
	f.initial_velocity_min = 0.6
	f.initial_velocity_max = 1.6
	f.gravity = Vector3(0.0, 2.6, 0.0)
	f.damping_min = 0.4
	f.damping_max = 1.0
	f.color_ramp = CarDamage._flame_ramp()
	f.color_initial_ramp = CarDamage._flame_variety()
	f.angle_min = -10.0
	f.angle_max = 10.0
	f.scale_amount_min = 0.55
	f.scale_amount_max = 1.05
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(0.65, 0.75))
	curve.add_point(Vector2(1.0, 0.2))
	f.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 1.45)
	quad.center_offset = Vector3(0.0, 0.45, 0.0)
	quad.material = CarDamage.fire_material()
	tongue_quad(quad, 1.25)
	f.mesh = quad
	f.custom_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 10.0, 16.0))
	car.add_child(f)
	var tw := f.create_tween()
	tw.tween_interval(side_flame_seconds * 0.3)
	tw.tween_property(f, "color", Color(1, 1, 1, 0.15), side_flame_seconds * 0.7)
	tw.tween_callback(func(): f.emitting = false)
	tw.tween_interval(1.2)
	tw.tween_callback(f.queue_free)
	return f


## True when the flame tongues replace the round fire puffs (not on the web: no depth texture).
static func tongues() -> bool:
	return enabled and flames_enabled and not WeaponFX._web()


## The flame tongue material, shared by every fire that uses it.
static func flame_material() -> Material:
	if not tongues():
		return CarDamage.fire_material()
	if _flame_mat == null:
		_flame_mat = ShaderMaterial.new()
		_flame_mat.shader = preload("res://shaders/flame_tongue.gdshader")
		_flame_mat.set_shader_parameter("noise3d", Blast3.noise_texture())
	return _flame_mat


## A flame system's card made a tongue: taller and narrower, its root at the particle.
static func tongue_quad(quad: QuadMesh, gain: float = 1.6) -> void:
	if not tongues():
		return
	quad.size = Vector2(quad.size.x * 1.15, quad.size.y * gain)
	quad.center_offset = Vector3(0.0, quad.size.y * 0.42, 0.0)
	quad.material = flame_material()


## The pit's depth, lip and loose rubble on a crater mark (BlastAftermath.crater()'s hook).
static func pit_dress(mark: Node3D, pit_r: float) -> bool:
	if not enabled or not pit_enabled or mark == null or pit_r < 0.4:
		return false
	var h := hash([int(mark.global_position.x * 8.0), int(mark.global_position.z * 8.0), "pit"])
	# The bowl, traced on a quad just over the road.
	if _pit_shader == null:
		_pit_shader = preload("res://shaders/blast_pit.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _pit_shader
	m.set_shader_parameter("noise3d", Blast3.noise_texture())
	m.set_shader_parameter("pit_r", pit_r)
	m.set_shader_parameter("depth", pit_r * pit_depth)
	m.set_shader_parameter("seed", float(h & 1023) / 97.0)
	m.render_priority = 1
	var quad := MeshInstance3D.new()
	quad.name = "PitBowl"
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * pit_r * 2.08
	quad.mesh = pm
	quad.material_override = m
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position = Vector3(0.0, 0.11, 0.0)
	mark.add_child(quad)
	# The lip: earth and crushed base course thrown up round the opening.
	var lip := MeshInstance3D.new()
	lip.name = "PitLip"
	lip.mesh = lip_mesh(pit_r, h)
	if _lip_mat == null:
		_lip_mat = StandardMaterial3D.new()
		_lip_mat.vertex_color_use_as_albedo = true
		_lip_mat.roughness = 0.96
	lip.material_override = _lip_mat
	lip.position = Vector3(0.0, 0.02, 0.0)
	mark.add_child(lip)
	# Loose chunks on the lip and tipped into the opening.
	if _rock_mesh == null:
		_rock_mesh = BlastAftermath._chunk_mesh(6, Vector3(0.26, 0.16, 0.2), 29, Color(0.08, 0.075, 0.07), Color(0.3, 0.27, 0.24))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _rock_mesh
	var n := clampi(int(pit_r * 9.0), 8, 28)
	mm.instance_count = n
	for i in n:
		var hi := hash([h, i])
		var a := float(hi & 1023) / 1023.0 * TAU
		var d := pit_r * (0.92 + 0.5 * float((hi >> 10) & 255) / 255.0)
		var sc := 0.6 + 1.3 * float((hi >> 18) & 63) / 63.0
		var b := Basis(Vector3(float((hi >> 3) & 7) - 3.5, 2.0, float((hi >> 6) & 7) - 3.5).normalized(), float(hi & 255) / 40.0)
		var y := lip_height(d / pit_r, pit_r) * 0.85
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * sc), Vector3(cos(a) * d, y, sin(a) * d)))
	var mi := MultiMeshInstance3D.new()
	mi.name = "PitRubble"
	mi.multimesh = mm
	mi.visibility_range_end = 120.0
	mark.add_child(mi)
	return true


## The lip's height at s (distance / pit radius): up from the opening's edge to a crest, falling
## away over the road.
static func lip_height(s: float, pit_r: float) -> float:
	var k := clampf((s - 0.92) / 0.6, 0.0, 1.0)
	return pit_r * 0.075 * sin(k * PI) * (1.0 - 0.3 * k)


## The lip as a ring of quads: the opening's edge to 1.55 radii, raised by lip_height(), ragged.
static func lip_mesh(pit_r: float, h: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var na := 40
	var nr := 6
	var pts: Array = []
	for j in nr + 1:
		var row: Array = []
		for i in na:
			var a := TAU * float(i) / float(na)
			var jit := float(hash([h, i, j]) & 255) / 255.0
			var s := 0.92 + 0.6 * float(j) / float(nr) + (jit - 0.5) * 0.06
			var y := lip_height(s, pit_r) * (0.7 + 0.6 * jit)
			if j == nr:
				y = -0.02
			row.append(Vector3(cos(a) * s * pit_r, y, sin(a) * s * pit_r))
		pts.append(row)
	for j in nr:
		for i in na:
			var i2 := (i + 1) % na
			var p00: Vector3 = pts[j][i]
			var p01: Vector3 = pts[j][i2]
			var p10: Vector3 = pts[j + 1][i]
			var p11: Vector3 = pts[j + 1][i2]
			var c0 := Color(0.2, 0.18, 0.15).lerp(Color(0.1, 0.095, 0.09), float(j) / float(nr))
			var c1 := Color(0.2, 0.18, 0.15).lerp(Color(0.1, 0.095, 0.09), float(j + 1) / float(nr))
			# Wound clockwise seen from above (Godot's front faces).
			for v in [[p00, c0], [p01, c0], [p10, c1], [p01, c0], [p11, c1], [p10, c1]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
	st.generate_normals()
	return st.commit()
