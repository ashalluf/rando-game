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
## The volume's march jitter narrowed (blast_volume.gdshader `quiet4`): TAA does not clear it.
## BLAST_QUIET=0 is the A/B.
static var quiet_enabled: bool = OS.get_environment("BLAST_QUIET") != "0"
static var quiet_jitter: float = 0.3
## The shop fronts round a blast answer it (`facade_response()`): awnings torn off into canvas
## scraps (burning near it), blade signs knocked askew. BLAST_FACADES=0 is the A/B.
static var facades_enabled: bool = OS.get_environment("BLAST_FACADES") != "0"
## The first half second as a violent core (blast_volume.gdshader `core4`): depth-led heat, a fuel
## ball's soot skin, the flash on the dust. BLAST_CORE=0 is the A/B.
static var core_enabled: bool = OS.get_environment("BLAST_CORE") != "0"
static var facade_reach: float = 3.2 # blast radii
static var max_awnings: int = 6
## A continuous smoke ribbon behind each burning piece of debris, and longer burns on the ground
## (BlastDebris._ribbons()). BLAST_RIBBONS=0 is the A/B.
static var debris_ribbons: bool = OS.get_environment("BLAST_RIBBONS") != "0"
static var _ribbon_mat: Material
## Round 14: debris trails drawn with a soft, torn profile (shaders/blast_ribbon.gdshader). BLAST_RIBBON_SOFT=0.
static var ribbon_soft: bool = OS.get_environment("BLAST_RIBBON_SOFT") != "0"
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
	mat.set_shader_parameter("quiet4", quiet_jitter if quiet_enabled else 0.0)
	mat.set_shader_parameter("core4", 1.0 if core_enabled else 0.0)
	mat.set_shader_parameter("night4", 1.0 if night_enabled else 0.0)
	mat.set_shader_parameter("burn5", 1.0 if burn_enabled else 0.0)
	if dark_dust:
		mat.set_shader_parameter("dust", Vector3(0.085, 0.077, 0.066))
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
## Round 8: the dust skirt and the volume's dust ring darker and denser near the ground.
## BLAST_DUST_DARK=0 is the A/B.
static var dark_dust: bool = OS.get_environment("BLAST_DUST_DARK") != "0"
## The shock ring (`shock_kick()`): loose bodies between 1 and `shock_reach` radii are kicked
## outward as the wave reaches them. BLAST_SHOCK=0 is the A/B.
static var shock_enabled: bool = OS.get_environment("BLAST_SHOCK") != "0"
static var shock_reach: float = 2.5
static var shock_speed: float = 9.0 # m/s at the radius, falling to 0 at the reach
## Night (`DayNight.lamp_now`): the flash is held down (it blew the dark-adapted frame out to
## white) and the fires reach further and burn brighter on the facades and the wet road.
## BLAST_NIGHT=0 is the A/B.
static var night_enabled: bool = OS.get_environment("BLAST_NIGHT") != "0"
static var night_flash: float = 0.45 # the flash's share left at full night
static var night_fire_gain: float = 2.2
static var night_fire_range: float = 1.7
## Debris in flight streaks fire behind it; the tongues stand up once it lands
## (BlastDebris._flames_air). BLAST_STREAKS=0 is the A/B.
static var debris_streaks: bool = OS.get_environment("BLAST_STREAKS") != "0"
## Round 11: the shock ring on the ground (`ground_ring()`, what reads from the air) and a blast
## against a wall (`wall_blast()`: smoke pouring from the hole, masonry and glass raining down).
## BLAST_RING=0 / BLAST_WALL=0 are the A/Bs.
static var ring_enabled: bool = OS.get_environment("BLAST_RING") != "0"
## Round 13: the street lit white-orange under the burst for its first frames, then the core's
## embers (`shaders/blast_ground_flash.gdshader`): what reads first from the air. BLAST_GROUND_FLASH=0.
## Round 14: the ring fades for an eye near it or at a grazing look (BLAST_RING_AIR=0 the round-11 ring).
## Round 15: fuel and gas balls burn longer (blast_volume.gdshader `burn5`). BLAST_BURN=0.
static var burn_enabled: bool = OS.get_environment("BLAST_BURN") != "0"
## Round 16: the crater's soot a dark core with thinning streaks, not solid spikes (Blast3.crater_maps). BLAST_SCORCH=0.
static var scorch_soft: bool = OS.get_environment("BLAST_SCORCH") != "0"
static var ring_air_fade: bool = OS.get_environment("BLAST_RING_AIR") != "0"
static var ground_flash_enabled: bool = OS.get_environment("BLAST_GROUND_FLASH") != "0"
static var _flash_shader: Shader
static var wall_enabled: bool = OS.get_environment("BLAST_WALL") != "0"
static var wall_smoke_seconds: float = 22.0
static var _ring_shader: Shader
## Round 12: the wall blast's heavier burst - slabs of wall, a pale masonry dust burst, and the
## rubble heap at the foot of the wall that stays. BLAST_MASONRY=0 is the A/B.
static var heavy_masonry: bool = OS.get_environment("BLAST_MASONRY") != "0"
static var heap_seconds: float = 90.0


static func dust_roll(parent: Node, ground: Vector3, normal: Vector3, reach: float) -> bool:
	if not enabled or not dust_roll_enabled or parent == null:
		return false
	ground_ring(parent, ground, normal, reach * 1.25)
	if _dust_ramps.is_empty() and dark_dust:
		# Round 8: the skirt is grime and soot-laden debris near the ground, darker and denser
		# (the pale beige read as a sunlit cloud bank, not street filth thrown out by a blast);
		# the sun still lights its upper edges.
		_dust_ramps = [
			WeaponFX._ramp([Color(0.085, 0.077, 0.068, 0.0), Color(0.09, 0.082, 0.072, 0.9),
				Color(0.12, 0.11, 0.098, 0.62), Color(0.15, 0.14, 0.125, 0.0)]),
			WeaponFX._ramp([Color(0.075, 0.068, 0.06, 0.0), Color(0.085, 0.078, 0.068, 0.78),
				Color(0.11, 0.1, 0.09, 0.46), Color(0.14, 0.13, 0.12, 0.0)]),
			WeaponFX._ramp([Color(0.13, 0.12, 0.11, 0.0), Color(0.14, 0.13, 0.12, 0.3),
				Color(0.16, 0.15, 0.14, 0.2), Color(0.18, 0.17, 0.16, 0.0)]),
			WeaponFX._ramp([Color(0.8, 0.76, 0.72, 1.0), Color(1.0, 0.97, 0.92, 1.0), Color(1.15, 1.1, 1.0, 1.0)])]
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


## The shop fronts within `facade_reach` radii of a blast: every awning facing it is torn off (its
## kit instance hidden, a burst of scraps in its colour - burning within 1.4 radii - fluttering
## down), and every blade sign facing it swings askew on its bracket. Returns [awnings, signs].
static func facade_response(node: Node, at: Vector3, radius: float) -> Array:
	var done := [0, 0]
	if not enabled or not facades_enabled or not (node is Node3D) or not (node as Node3D).is_inside_tree():
		return done
	var space := (node as Node3D).get_world_3d().direct_space_state
	var reach := radius * facade_reach
	var shape := SphereShape3D.new()
	shape.radius = reach
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 1
	var seen := {}
	var parent := WeaponFX.fx_parent(node)
	for res: Dictionary in space.intersect_shape(q, 64):
		var t := BuildingDamage.target_of(res.get("collider"), int(res.get("shape", -1)))
		if t.is_empty() or t.building == null or seen.has(t.key):
			continue
		seen[t.key] = true
		var b: Building = t.building
		for c in b.get_children():
			var mmi := c as MultiMeshInstance3D
			if mmi == null or mmi.multimesh == null:
				continue
			var nm := String(mmi.name)
			var awning := nm.begins_with("Batch_kit_awning")
			var blade := nm.begins_with("Batch_kit_shop_blade")
			if not awning and not blade:
				continue
			var mm := mmi.multimesh
			for i in mm.instance_count:
				var xf := mmi.global_transform * mm.get_instance_transform(i)
				if xf.basis.get_scale().length() < 0.01:
					continue
				var d := xf.origin.distance_to(at)
				if d > reach:
					continue
				# Only what faces the blast (its +Z is the wall's outward normal).
				var out := xf.basis.z.normalized()
				if out.dot((at - xf.origin).normalized()) < 0.1:
					continue
				var keep := 1.0 - d / reach
				var hi := hash([int(xf.origin.x * 10.0), int(xf.origin.z * 10.0), int(xf.origin.y * 10.0), "facade"])
				if float(hi & 1023) / 1023.0 > 0.4 + 0.6 * keep:
					continue
				if awning and done[0] < max_awnings:
					var col := mm.get_instance_color(i) if mm.use_colors else Color(0.6, 0.2, 0.15)
					var width := (mm.get_instance_custom_data(i).b * 2.0 + 1.0) if mm.use_custom_data else 2.5
					MultiMeshBatch.hide_instance(mmi, i)
					_awning_scraps(parent, xf, col, width, d < radius * 1.4, d / 343.0)
					done[0] += 1
				elif blade:
					# Swung on its bracket away from the blast, a little dropped.
					var tilt := deg_to_rad(12.0 + 22.0 * keep) * (1.0 if (hi & 2) == 0 else -1.0)
					var local := mm.get_instance_transform(i)
					local.basis = Basis(local.basis.x.normalized(), tilt) * local.basis
					local.origin.y -= 0.12 * keep
					mm.set_instance_transform(i, local)
					done[1] += 1
	return done


## Torn canvas: scraps of the awning's colour thrown off its frame by the wave (arriving at the
## speed of sound), fluttering down; near the blast they burn.
static func _awning_scraps(parent: Node, xf: Transform3D, col: Color, width: float, burning: bool, delay: float) -> void:
	var p := CPUParticles3D.new()
	p.name = "AwningScraps"
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.one_shot = true
	p.emitting = false
	p.amount = WeaponFX._count(26)
	p.explosiveness = 0.9
	p.lifetime = 3.2
	p.lifetime_randomness = 0.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(maxf(width * 0.5, 0.5), 0.25, 0.4)
	p.direction = Vector3(0.0, 0.4, 1.0)
	p.spread = 55.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0.0, -3.2, 0.0)
	p.damping_min = 1.5
	p.damping_max = 3.5
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_min = 0.18
	p.scale_amount_max = 0.55
	var dark := col.darkened(0.55) if burning else col
	p.color = dark
	if burning:
		p.color_ramp = WeaponFX._ramp([Color(2.0, 1.0, 0.25, 1.0), Color(1.0, 0.45, 0.08, 1.0),
			Color(0.12, 0.08, 0.06, 1.0), Color(0.05, 0.04, 0.035, 0.0)])
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 0.7)
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.3
	if burning:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.4, 0.08)
		m.emission_energy_multiplier = 1.2
	quad.material = m
	p.mesh = quad
	p.custom_aabb = AABB(Vector3(-15.0, -15.0, -15.0), Vector3(30.0, 30.0, 30.0))
	parent.add_child(p)
	p.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	var tw := p.create_tween()
	tw.tween_interval(maxf(delay, 0.02))
	tw.tween_callback(func(): p.emitting = true)
	tw.tween_interval(p.lifetime * 1.5 + 0.5)
	tw.tween_callback(p.queue_free)


## The debris ribbons' material: soot that takes the sun and sky, see-through by its alpha.
static func ribbon_material() -> Material:
	if _ribbon_mat == null:
		if ribbon_soft:
			# Round 14: a soft torn profile across the band (a flat band drew hard arcs at 5 m).
			var sm := ShaderMaterial.new()
			sm.shader = preload("res://shaders/blast_ribbon.gdshader")
			_ribbon_mat = sm
			return _ribbon_mat
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.roughness = 1.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.disable_receive_shadows = true
		_ribbon_mat = m
	return _ribbon_mat


## Kicks every loose body (props, bins, parked cars, debris) between the blast's radius and
## `shock_reach` radii outward, when the wave (343 m/s) gets there: a bin tumbles away down the
## street, a parked car rocks on its springs and slides, a traffic car within 1.6 radii is thrown
## out of traffic. Inside the radius Explosion.blast() already threw them. Returns how many.
static func shock_kick(node: Node, at: Vector3, radius: float, exclude: Object = null) -> int:
	if not enabled or not shock_enabled or node == null or not (node is Node3D) or not (node as Node3D).is_inside_tree():
		return 0
	var reach := radius * shock_reach
	var shape := SphereShape3D.new()
	shape.radius = reach
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 4 # props (bins, physics props, parked and traffic cars)
	var seen := {}
	var n := 0
	var tree := node.get_tree()
	for res: Dictionary in (node as Node3D).get_world_3d().direct_space_state.intersect_shape(q, 128):
		var body := res.get("collider") as RigidBody3D
		if body == null or body == exclude or seen.has(body):
			continue
		seen[body] = true
		var off := body.global_position - at
		var d := off.length()
		if d <= radius or d > reach:
			continue
		var k := 1.0 - (d - radius) / (reach - radius)
		k *= k
		var dir := (Vector3(off.x, 0.0, off.z).normalized() + Vector3.UP * 0.35).normalized()
		if body is Vehicle:
			var car := body as Vehicle
			if not car.traffic.is_empty():
				if d > radius * 1.6:
					continue
				car.drop_out_of_traffic()
			# A car is heavy: a shove and a rock on its springs, not a launch.
			k *= 0.7
		var wait := d / 343.0
		var b := body
		var kk := k
		var dd := dir
		tree.create_timer(maxf(wait, 0.01), false).timeout.connect(func():
			if not is_instance_valid(b):
				return
			b.freeze = false
			b.sleeping = false
			b.apply_central_impulse(dd * shock_speed * kk * b.mass)
			b.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * b.mass * kk * 1.5))
		n += 1
	return n


static func _night() -> float:
	if not enabled or not night_enabled:
		return 0.0
	return clampf(DayNight.lamp_now, 0.0, 1.0)


## The flash's share at this hour (BlastFX's flash light and screen flash).
static func flash_night() -> float:
	return lerpf(1.0, night_flash, _night())


## A fire light's energy gain at this hour (the burning wreck, the pools).
static func fire_night_gain() -> float:
	return lerpf(1.0, night_fire_gain, _night())


## A fire light's reach at this hour.
static func fire_night_range() -> float:
	return lerpf(1.0, night_fire_range, _night())


## The shock ring: a pale ragged band of dust racing out over the ground to `reach` metres.
static func ground_ring(parent: Node, ground: Vector3, normal: Vector3, reach: float) -> MeshInstance3D:
	if not enabled or not ring_enabled or parent == null:
		return null
	if _ring_shader == null:
		_ring_shader = preload("res://shaders/blast_ring.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _ring_shader
	m.set_shader_parameter("noise3d", Blast3.noise_texture())
	m.set_shader_parameter("reach", reach)
	m.set_shader_parameter("seed", randf() * 7.0)
	m.set_shader_parameter("air_fade", 1.0 if ring_air_fade else 0.0)
	var q := MeshInstance3D.new()
	q.name = "BlastRing"
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * reach * 2.0
	q.mesh = pm
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(q)
	q.global_transform = Transform3D(WeaponFX._basis_up(normal), ground + normal * 0.12)
	var tw := q.create_tween()
	tw.tween_method(func(a: float): m.set_shader_parameter("age", a), 0.0, 6.0, 6.0)
	tw.tween_callback(q.queue_free)
	ground_flash(q, reach)
	return q


## The ground flash under the burst (round 13): a quad of 0.55 x the dust reach on the ring's own
## node (so it rides the same transform and dies with it), additive, fog-free. Returns the quad.
static func ground_flash(ring: Node3D, reach: float) -> MeshInstance3D:
	if not ground_flash_enabled or ring == null:
		return null
	if _flash_shader == null:
		_flash_shader = preload("res://shaders/blast_ground_flash.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _flash_shader
	m.set_shader_parameter("noise3d", Blast3.noise_texture())
	m.set_shader_parameter("seed", randf() * 7.0)
	var q := MeshInstance3D.new()
	q.name = "BlastGroundFlash"
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * reach * 1.1
	q.mesh = pm
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.position = Vector3(0.0, 0.03, 0.0)
	ring.add_child(q)
	var tw := q.create_tween()
	tw.tween_method(func(a: float): m.set_shader_parameter("age", a), 0.0, 4.0, 4.0)
	tw.tween_callback(q.queue_free)
	return q


## A blast against a wall (a rocket into a facade): found by rays round the blast point, it
## leaves smoke pouring out of the hole and up the face for `wall_smoke_seconds` (with embers),
## and masonry chunks and glass raining from it to the street. Returns true when there was a wall.
static func wall_blast(node: Node, parent: Node, at: Vector3, radius: float) -> bool:
	if not enabled or not wall_enabled or not (node is Node3D) or parent == null:
		return false
	var space := (node as Node3D).get_world_3d().direct_space_state
	var best := {}
	var best_d := 2.2
	for k in 8:
		var a := TAU * float(k) / 8.0
		var to := at + Vector3(cos(a), 0.0, sin(a)) * 2.2
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, to, 1))
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.4:
			continue
		var d := at.distance_to(hit.position)
		if d < best_d:
			best_d = d
			best = hit
	if best.is_empty():
		return false
	var wn: Vector3 = best.normal
	var wp: Vector3 = best.position
	# The ground under the hole: how far the masonry falls.
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(wp + wn * 1.0, wp + wn * 1.0 - Vector3.UP * 80.0, 1))
	var drop := (wp.y - (down.position as Vector3).y) if not down.is_empty() else 6.0
	if drop < 1.5:
		return false # a blast at the foot of a wall: the ground's own dust and rubble take it
	var b := WeaponFX._basis_up(wn)
	# Smoke pouring out of the hole: lit smoke leaving along the wall's normal and rising up the face.
	var sm := CPUParticles3D.new()
	sm.name = "WallHoleSmoke"
	sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sm.amount = WeaponFX._count(70)
	sm.lifetime = 5.0
	sm.lifetime_randomness = 0.35
	sm.local_coords = false
	sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = radius * 0.12
	sm.direction = Vector3(0.0, 1.0, 0.0) # local +Y: out of the wall
	sm.spread = 28.0
	sm.initial_velocity_min = 1.2
	sm.initial_velocity_max = 2.6
	sm.gravity = b.inverse() * Vector3(0.0, 1.6, 0.0) # buoyant: up the face, in local axes
	sm.damping_min = 0.4
	sm.damping_max = 0.9
	sm.angle_min = -180.0
	sm.angle_max = 180.0
	sm.angular_velocity_min = -20.0
	sm.angular_velocity_max = 20.0
	sm.scale_amount_min = radius * 0.16
	sm.scale_amount_max = radius * 0.28
	var c := Curve.new()
	c.max_value = 4.0
	c.add_point(Vector2(0.0, 0.5))
	c.add_point(Vector2(0.3, 1.4))
	c.add_point(Vector2(1.0, 3.2))
	sm.scale_amount_curve = c
	sm.color_ramp = WeaponFX._ramp([Color(0.05, 0.045, 0.04, 0.0), Color(0.05, 0.045, 0.04, 0.8),
		Color(0.08, 0.075, 0.07, 0.5), Color(0.12, 0.115, 0.11, 0.0)])
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = BlastFX.smoke_material()
	sm.mesh = quad
	sm.custom_aabb = AABB(Vector3(-40.0, -10.0, -40.0), Vector3(80.0, 70.0, 80.0))
	parent.add_child(sm)
	sm.global_transform = Transform3D(b, wp + wn * 0.4)
	var st := sm.create_tween()
	st.tween_interval(wall_smoke_seconds * 0.6)
	st.tween_property(sm, "color", Color(1, 1, 1, 0.0), wall_smoke_seconds * 0.4)
	st.tween_callback(func(): sm.emitting = false)
	st.tween_interval(sm.lifetime + 0.5)
	st.tween_callback(sm.queue_free)
	# Masonry and glass raining from the hole: chunks and glints thrown out, falling to the street
	# (gone at the ground: their life is the fall's time).
	var fall := sqrt(2.0 * maxf(drop, 1.0) / 9.8)
	if heavy_masonry:
		_masonry_extra(parent, b, wp, wn, radius, fall, down)
	for kind in 2:
		var r := CPUParticles3D.new()
		r.name = "WallRain" if kind == 0 else "WallGlass"
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		r.amount = WeaponFX._count(34 if kind == 0 else 60)
		r.one_shot = true
		r.explosiveness = 0.75
		r.lifetime = fall + 0.25
		r.local_coords = false
		r.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		r.emission_sphere_radius = radius * 0.2
		r.direction = Vector3(0.0, 1.0, 0.0)
		r.spread = 70.0
		r.initial_velocity_min = 2.0
		r.initial_velocity_max = 7.0 if kind == 0 else 9.0
		r.gravity = b.inverse() * Vector3(0.0, -9.8, 0.0)
		r.angular_velocity_min = -400.0
		r.angular_velocity_max = 400.0
		r.particle_flag_rotate_y = true
		if kind == 0:
			if _rock_mesh == null:
				_rock_mesh = BlastAftermath._chunk_mesh(6, Vector3(0.26, 0.16, 0.2), 29, Color(0.08, 0.075, 0.07), Color(0.3, 0.27, 0.24))
			r.mesh = _rock_mesh
			r.scale_amount_min = 0.5
			r.scale_amount_max = 1.6
			var mm := StandardMaterial3D.new()
			mm.vertex_color_use_as_albedo = true
			mm.roughness = 0.95
			r.material_override = mm
		else:
			var gq := QuadMesh.new()
			gq.size = Vector2(0.09, 0.12)
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.55, 0.62, 0.62)
			gm.metallic = 0.6
			gm.roughness = 0.05
			gm.cull_mode = BaseMaterial3D.CULL_DISABLED
			gq.material = gm
			r.mesh = gq
			r.scale_amount_min = 0.6
			r.scale_amount_max = 1.8
		r.custom_aabb = AABB(Vector3(-30.0, -40.0, -30.0), Vector3(60.0, 50.0, 60.0))
		parent.add_child(r)
		r.global_transform = Transform3D(b, wp + wn * 0.3)
		r.emitting = true
		var rt := r.create_tween()
		rt.tween_interval(r.lifetime + 1.0)
		rt.tween_callback(r.queue_free)
	return true


## The heavier masonry burst (wall_blast()): slabs of wall thrown out with the chunks, a pale
## burst of masonry dust from the hole, and where they land a heap of broken masonry that stays
## `heap_seconds` (it appears as the first of them reach the street).
static func _masonry_extra(parent: Node, b: Basis, wp: Vector3, wn: Vector3, radius: float, fall: float, down: Dictionary) -> void:
	var slabs := CPUParticles3D.new()
	slabs.name = "WallSlabs"
	slabs.amount = WeaponFX._count(12)
	slabs.one_shot = true
	slabs.explosiveness = 0.85
	slabs.lifetime = fall + 0.2
	slabs.local_coords = false
	slabs.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	slabs.emission_sphere_radius = radius * 0.15
	slabs.direction = Vector3(0.0, 1.0, 0.0)
	slabs.spread = 50.0
	slabs.initial_velocity_min = 3.0
	slabs.initial_velocity_max = 8.0
	slabs.gravity = b.inverse() * Vector3(0.0, -9.8, 0.0)
	slabs.angular_velocity_min = -300.0
	slabs.angular_velocity_max = 300.0
	slabs.particle_flag_rotate_y = true
	slabs.mesh = BlastAftermath.slab_mesh()
	slabs.scale_amount_min = 1.0
	slabs.scale_amount_max = 2.4
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.roughness = 0.95
	slabs.material_override = sm
	slabs.custom_aabb = AABB(Vector3(-30.0, -40.0, -30.0), Vector3(60.0, 50.0, 60.0))
	parent.add_child(slabs)
	slabs.global_transform = Transform3D(b, wp + wn * 0.3)
	slabs.emitting = true
	var tw := slabs.create_tween()
	tw.tween_interval(slabs.lifetime + 1.0)
	tw.tween_callback(slabs.queue_free)
	# The pale dust of crushed masonry, thrown out of the hole and falling with the debris.
	WeaponFX._puff_layer(parent, wp + wn * 0.6, WeaponFX._count(22), radius * 0.16, 3.5,
		radius * 0.25, radius * 0.7, -1.2, WeaponFX._ramp([Color(0.42, 0.39, 0.35, 0.0),
		Color(0.4, 0.37, 0.33, 0.7), Color(0.38, 0.36, 0.33, 0.35), Color(0.36, 0.35, 0.33, 0.0)]),
		false, 55.0, 2.6, WeaponFX._basis_up(wn), 0.0, 0.4, 1.4, true, null, BlastFX.smoke_material())
	if down.is_empty():
		return
	# The heap at the foot of the wall.
	var foot: Vector3 = down.position
	if _rock_mesh == null:
		_rock_mesh = BlastAftermath._chunk_mesh(6, Vector3(0.26, 0.16, 0.2), 29, Color(0.08, 0.075, 0.07), Color(0.3, 0.27, 0.24))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _rock_mesh
	var n := WeaponFX._count(26)
	mm.instance_count = n
	var hb := hash([int(foot.x * 4.0), int(foot.z * 4.0), "heap"])
	var side := wn.cross(Vector3.UP).normalized()
	for i in n:
		var hi := hash([hb, i])
		var out := float(hi & 255) / 255.0 * 3.2 + 0.4
		var along := (float((hi >> 8) & 255) / 255.0 - 0.5) * 4.0 * (1.0 - out / 4.0)
		var sc := 0.8 + 2.2 * float((hi >> 16) & 63) / 63.0 * (1.0 - out / 4.5)
		var bb := Basis(Vector3(float((hi >> 3) & 7) - 3.5, 2.0, float((hi >> 6) & 7) - 3.5).normalized(), float(hi & 255) / 40.0)
		var at := wn * out + side * along + Vector3.UP * 0.05 * sc # relative to the foot
		mm.set_instance_transform(i, Transform3D(bb.scaled(Vector3.ONE * sc), at))
	var heap := MultiMeshInstance3D.new()
	heap.name = "WallHeap"
	heap.multimesh = mm
	heap.material_override = sm
	heap.visible = false
	parent.add_child(heap)
	heap.global_transform = Transform3D(Basis(), foot) # its box is round the node: at the foot
	var ht := heap.create_tween()
	ht.tween_interval(fall * 0.9)
	ht.tween_callback(func(): heap.visible = true)
	ht.tween_interval(heap_seconds)
	ht.tween_callback(heap.queue_free)
