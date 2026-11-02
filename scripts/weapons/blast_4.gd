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
