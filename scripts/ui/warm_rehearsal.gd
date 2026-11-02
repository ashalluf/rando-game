class_name WarmRehearsal
extends RefCounted
## The loading screen's second warm-up (fleet task shader-warm, 2026-10-05): a dress rehearsal of
## the things that first appear in the middle of play, staged behind the loading shade.
##
## LoadingScreen._warm_shaders() draws one 2 cm quad per shader file. That compiles the shader,
## but Forward+ builds a PIPELINE per shader AND vertex format (and per pass: colour, motion
## vectors, depth with normals, SDFGI, shadows), so a car body, a skinned person or a particle
## system whose format the quad does not share still compiled its own the first time it was
## drawn - in the middle of a frame, and the frame waited for it (Godot precompiles a new
## surface's pipelines in the background, but a car spawned this frame is drawn next frame,
## before that has finished). So the rehearsal builds the REAL things in front of the camera for
## a few frames: every car body (police, emergency, big vehicles and a car shot up and set on
## fire included), people (shot and dismembered), the weapons' effects (tracers, impacts, holes,
## an explosion, blood, a crater, brass), a rocket, a car light with its cookie, and copies of
## the particle systems that sit idle until the weather or the boost wakes them (rain, splashes,
## the boost's vapour); then frees it all and everything it left in the scene.
##
## And it keeps the decal atlas whole. Godot packs every Decal texture (and every light
## projector) into one atlas, and REPACKS it whenever a texture is added that is not there. A
## texture leaves the atlas when its last decal goes, without a repack, and coming back later
## repacks the whole atlas again: the first blood after the last splat faded, the first bullet
## hole, the player's headlight cookie switching on and off. `keep_decal_atlas()` holds one
## hidden Decal per texture the game uses for the whole session, so the atlas is packed once,
## here, and never again.
##
## Nothing here touches the seed's world: no rolls, no crimes (Police.innocent), no sound (the
## master bus is muted while it runs), and every node it or the effects added is freed after.
## WARM_REHEARSAL=0 in the environment turns it off (the A/B).

## Frames each stage is held on screen. The first draw starts the specialised pipelines; the
## rest let the background compiles finish while the shade is still up.
const HOLD_FRAMES := 3
## Meta on every car and person the rehearsal makes (the checks look for any left alive).
const TAG := &"warm_rehearsal"

static var enabled: bool = OS.get_environment("WARM_REHEARSAL") != "0"
## Wave 3's first uses, rehearsed too (loading-first-frame, 2026-10-31; docs/HANDOFF.md "The first
## minute"): a crash's crumple and its litter, a lit cruiser's washes (PoliceNightLook), the
## car cabins' door split and kit (CarInteriors: the first car the player walks up to), people
## under umbrellas and hoods (RainCrowd), a wild animal. `WARM_WAVE3=0` leaves them out (the A/B).
static var wave3: bool = OS.get_environment("WARM_WAVE3") != "0"
## Wave 4's first uses (load-time-3, 2026-11-01; docs/HANDOFF.md "Load time after wave 4"): the
## five-star troop truck and the gunship (wanted-escalation; the first helicopter of any kind), a
## spike strip and its flats (police-chase), a corner crash at speed (car-crash-3: the torn wheel,
## its sparks, the debris), a burst's barrel smoke and every surface's bullet marks (gunplay-feel),
## blood on the hero (blood-gore-2). Measured with tools/shader_warm/first_use_probe EVENTS=wave4.
## `WARM_WAVE4=0` leaves them out (the A/B).
static var wave4: bool = OS.get_environment("WARM_WAVE4") != "0"
## For the first-use probe (tools/shader_warm/), which cannot fit the whole rehearsal's pipelines in
## lavapipe's memory any more: only these stages ("cars", "people", ...) and body types (empty: all).
static var only_stages: PackedStringArray = []
static var only_types: Array = []
static var _keeper: Node3D
## The car bodies and crowd rigs held for the session: freed with the last car or person of a
## kind, Godot drops the scene from its cache and the next one reads the .glb from disk again
## (and recompiles its meshes' pipelines) in the middle of a frame.
static var _resident: Array = []


## Runs the rehearsal in front of `cam`. `scene` is where the city lives (effects are parented
## to the current scene by WeaponFX, and freed from there afterwards). `progress` is called with
## a 0..1 fraction and a label. Awaits frames throughout.
## Frames the scene is swept for the effects' leftovers after the holder goes.
const SWEEP_FRAMES := 12


static func run(scene: Node, cam: Camera3D, progress: Callable = Callable(), log_times: bool = false) -> void:
	if not enabled or cam == null or scene == null or not scene.is_inside_tree():
		return
	var tree := scene.get_tree()
	var t_all := Time.get_ticks_usec()
	# Timed stage by stage like the rest of the loading screen (load-time-3: it was the one part of
	# it with no LOADING line, ~12 s headless on the build box).
	LoadClock.start("screen: rehearsal")
	keep_decal_atlas(scene)
	keep_models()
	var bus_was := AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	var innocent_was: bool = Police.innocent
	Police.innocent = true
	var fx_root: Node = tree.current_scene if tree.current_scene else tree.root
	var before := {}
	for c in fx_root.get_children():
		before[c.get_instance_id()] = true
	var holder := Node3D.new()
	holder.name = "WarmRehearsal"
	scene.add_child(holder)
	var eye := cam.global_transform
	var fwd := -eye.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var ground := Vector3(eye.origin.x, eye.origin.y - 1.6, eye.origin.z)
	var stages: Array = [
		["cars", _stage_cars],
		["people", _stage_people],
		["effects", _stage_effects],
		["idle particles", _stage_ghosts],
	]
	for i in stages.size():
		if not only_stages.is_empty() and not only_stages.has(String(stages[i][0])):
			continue
		var t0 := Time.get_ticks_usec()
		if progress.is_valid():
			progress.call(float(i) / float(stages.size()), "Rehearsing " + String(stages[i][0]))
		var stage: Callable = stages[i][1]
		await stage.call(holder, ground, fwd, right, tree)
		for f in HOLD_FRAMES:
			await tree.process_frame
		print("LOADING rehearsal %s: %d ms" % [stages[i][0], (Time.get_ticks_usec() - t0) / 1000])
	# Clean up: the holder, and whatever the effects parented to the scene meanwhile (plain
	# nodes only - a chunk the streamer added is a scripted node and stays).
	holder.queue_free()
	# Swept again for a moment after: blood drops traced along their arcs are still in the air and
	# lay their splats (Decals on the scene) as they land, some frames after the holder is gone -
	# which rig the staged people roll decides how long they fall.
	# And on while anything still turns up (a delayed spark or a drop landing late on a slow
	# frame: batch 30's gate found one CPUParticles3D after the fixed sweep), up to 4x as long.
	var f := 0
	var last_found := 0
	while f < SWEEP_FRAMES or (f - last_found < 12 and f < SWEEP_FRAMES * 4):
		for c in fx_root.get_children():
			if before.has(c.get_instance_id()) or c == holder or c.is_queued_for_deletion():
				continue
			if c.get_script() == null or String(c.name).begins_with("BlastCrater"):
				c.queue_free()
				last_found = f
		await tree.process_frame
		_purge_statics()
		f += 1
	Police.innocent = innocent_was
	AudioServer.set_bus_mute(0, bus_was)
	_purge_statics()
	clear_pools()
	LoadClock.stop("screen: rehearsal")
	if log_times:
		print("WARM rehearsal total %d ms" % ((Time.get_ticks_usec() - t_all) / 1000))


## Loads and holds every car body and crowd rig for the session (see `_resident`). Idempotent.
static func keep_models() -> void:
	if not _resident.is_empty():
		return
	var paths: Array = Vehicle.BODY_MODELS.values()
	paths.append_array(Pedestrian.MODELS)
	for path: String in paths:
		if ResourceLoader.exists(path):
			_resident.append(load(path))


## One hidden Decal per texture the game ever decals or projects, kept for the session (see the
## header). Idempotent; `scene` is the parent the keeper lives under.
static func keep_decal_atlas(scene: Node) -> void:
	if RenderingServer.get_rendering_device() == null:
		return
	if _keeper != null and is_instance_valid(_keeper) and _keeper.is_inside_tree():
		return
	_keeper = Node3D.new()
	_keeper.name = "DecalAtlasKeeper"
	_keeper.visible = false
	scene.add_child(_keeper)
	for maps in atlas_textures():
		var d := Decal.new()
		d.size = Vector3(0.01, 0.01, 0.01)
		d.cull_mask = 0
		d.texture_albedo = maps[0]
		if maps.size() > 1:
			d.texture_normal = maps[1]
		if maps.size() > 2:
			d.texture_orm = maps[2]
		if maps.size() > 3:
			d.texture_emission = maps[3]
		_keeper.add_child(d)


## Every texture set that goes into the decal atlas: [albedo, normal?, orm?, emission?].
static func atlas_textures() -> Array:
	var out: Array = []
	out.append([WeaponFX.hole_texture()])
	out.append([WeaponFX.crack_texture(), null, null, WeaponFX.crack_texture()])
	out.append([WeaponFX.puff_texture()])
	out.append([LandingFX.crater_texture()])
	for k in 2:
		var maps: Array = BlastAftermath.crater_textures(k)
		out.append([maps[0], maps[1], null, maps[2] if maps.size() > 2 else null])
	for kind in 6:
		var tex: Array = WeaponFX.blood_textures(kind)
		out.append([tex[0], tex[1], tex[2]])
	var lights := CarLights.instance()
	if lights != null and lights.get("_cookie") != null:
		out.append([lights.get("_cookie")])
	if GunplayFeel.enabled:
		out.append_array(GunplayFeel.all_hole_textures()) # every surface's bullet marks
	return out


static func _stage_cars(holder: Node3D, ground: Vector3, fwd: Vector3, right: Vector3, tree: SceneTree) -> void:
	var types: Array = []
	for t in Vehicle.BodyType.values():
		if only_types.is_empty() or only_types.has(int(t)):
			types.append(int(t))
	var i := 0
	var cars: Array = []
	for t in types:
		var car: Vehicle
		if t == Vehicle.BodyType.FIRE_ENGINE or t == Vehicle.BodyType.AMBULANCE:
			car = EmergencyCar.make(t - Vehicle.BodyType.FIRE_ENGINE, RandomNumberGenerator.new())
			car.set("lights_forced", true)
		elif BigVehicles.is_big(t):
			car = BigVehicles.make(t, 0)
		elif Motorcycle.is_moto(t):
			car = Motorcycle.make(t, 0)
		else:
			car = Vehicle.new()
			car.setup(t, Color(0.55, 0.08, 0.06), 0)
		if car == null:
			continue
		cars.append(car)
		i += 1
	for heavy in ([false] if not only_types.is_empty() else [false, true]):
		var cop: PoliceCar = PoliceCar.make(heavy, RandomNumberGenerator.new())
		cop.set("police", null)
		cars.append(cop)
	if wave4 and only_types.is_empty():
		var troop: PoliceCar = PoliceCar.make(false, RandomNumberGenerator.new(), true)
		troop.set("police", null)
		cars.append(troop)
	for k in cars.size():
		var car: Vehicle = cars[k]
		# A row across the view, far enough out to be drawn whole, off every collision layer the
		# player or the streets use: nothing here should touch the world it stands in.
		var row := k / 8
		var col := k % 8
		car.position = holder.to_local(ground + fwd * (14.0 + row * 9.0) + right * (float(col) - 3.5) * 5.5 + Vector3.UP * 1.0)
		car.collision_layer = 0
		car.set_meta(TAG, true)
		holder.add_child(car)
		car.set("_npc_driver", true)
		if car.has_method("_update_occupant"):
			car.call("_update_occupant")
	for f in 2:
		await tree.process_frame
	# The first car is shot full of holes, its glass and lamps broken, then blown up: the damage
	# paint, the glass and lamp variants, smoke and fire.
	var hurt: Vehicle = cars[0]
	var at := hurt.global_position + Vector3.UP * 0.8
	for n in 6:
		hurt.take_hit(0, 60.0, fwd, at + right * (0.3 * n - 0.8) - fwd * 1.0, Vehicle.HIT_BULLET)
	hurt.take_hit(0, 900.0, fwd, at - fwd * 3.0, Vehicle.HIT_BLAST)
	if wave3:
		await _stage_wave3_cars(cars, fwd, tree)
	if wave4:
		await _stage_wave4_cars(holder, cars, ground, fwd, right, tree)


static func _stage_people(holder: Node3D, ground: Vector3, fwd: Vector3, right: Vector3, tree: SceneTree) -> void:
	var peds: Array = []
	for k in 8:
		var p := Pedestrian.new()
		var at := ground + fwd * (6.0 + float(k / 4) * 1.6) + right * (float(k % 4) - 1.5) * 1.3
		var local := holder.to_local(at)
		p.setup(Rect2(local.x - 2.0, local.z - 2.0, 4.0, 4.0), 1.0, 90210 + k * 7919)
		p.set_meta(TAG, true)
		p.set_meta("no_trim", true)
		holder.add_child(p)
		p.position = local + Vector3.UP * 0.1
		p.set("_pause_left", 30.0)
		# Off the npc layer and its hit zone off, like the cars off theirs: a live traffic car
		# through the row knocked one down mid-rehearsal (gate run 5151), leaving its blood and a
		# freed walker in this list. The shot and the knock below are direct calls.
		p.collision_layer = 0
		if p._hit_shape and p._hit_shape.get_parent() is Area3D:
			(p._hit_shape.get_parent() as Area3D).monitoring = false
		peds.append(p)
	for f in 2:
		await tree.process_frame
	# Rain on them (RainCrowd): umbrellas opened in hand, hoods up, for a few frames.
	if wave3 and RainCrowd.enabled:
		var was := RainCrowd.forced
		RainCrowd.forced = 1.0
		for p in peds:
			if is_instance_valid(p) and p.get("rain") != null:
				p.rain.settle_now()
		for f in HOLD_FRAMES:
			await tree.process_frame
		RainCrowd.forced = was
	# Two go down: one shot (the ragdoll, the stain, the blood), one torn apart (limbs, stumps).
	if is_instance_valid(peds[0]):
		var a: Pedestrian = peds[0]
		a.shot(a.global_position + Vector3.UP * 1.3, fwd, fwd * 4.0, 2.0)
	if is_instance_valid(peds[1]):
		var b: Pedestrian = peds[1]
		b.knock(fwd * 6.0 + Vector3.UP * 3.0, 3)
	# Blood on the hero (HeroBlood): his cloth and skin shaders' spatter path, cleared after.
	if wave4 and HeroBlood.current != null:
		var hero := tree.get_first_node_in_group("player") as Node3D
		if hero:
			HeroBlood.splash(hero.global_position + Vector3.UP * 1.2 + fwd * 0.6, -fwd, 2.0)
			for f in HOLD_FRAMES:
				await tree.process_frame
			if HeroBlood.current != null:
				HeroBlood.current.clear()


static func _stage_effects(holder: Node3D, ground: Vector3, fwd: Vector3, right: Vector3, tree: SceneTree) -> void:
	var p := ground + fwd * 9.0
	WeaponFX.tracer(holder, p - right * 3.0 + Vector3.UP, p + Vector3.UP * 0.2, Color(1.0, 0.8, 0.4))
	WeaponFX.flash(holder, p - right * 2.0 + Vector3.UP)
	WeaponFX.impact(holder, p + right * 1.5, Color(1.0, 0.85, 0.5), Vector3.UP)
	WeaponFX.explosion(holder, p + fwd * 6.0, 4.0, 1.0)
	WeaponFX.blood(holder, p + right * 2.0 + Vector3.UP * 1.2, fwd, 1.5)
	WeaponFX.blood_gush(holder, p - right * 2.0 + Vector3.UP * 0.5, fwd, 1.0)
	var pool := WeaponFX.blood_pool(holder, p + right * 3.0, Vector3.UP, 1.0)
	if pool:
		WeaponFX.feed_pool(pool, 1.0)
	WeaponFX.blood_smear(holder, p - right * 3.0, Vector3.UP, right, 1.2, 0.4)
	BlastAftermath.crater(holder, p + fwd * 4.0, Vector3.UP, 4.0, true)
	BlastAftermath.leaf_burst(holder, p + Vector3.UP * 5.0, 2.0, fwd, 4.0, false, 12)
	BlastAftermath.leaf_burst(holder, p + Vector3.UP * 5.0 + right * 3.0, 2.0, fwd, 4.0, true, 12)
	BrassCasings.eject(holder, p + Vector3.UP * 1.4, right, Vector3.UP, Vector3.ZERO)
	var drip := WeaponFX.blood_drip(holder, holder.to_local(p + Vector3.UP), 2.0)
	if drip:
		drip.emitting = true
	# A rocket hanging in the air (no speed, a long fuse): its body and its smoke trail.
	var rocket := Rocket.new()
	rocket.speed = 0.0
	rocket.lifetime = 60.0
	rocket.direction = fwd
	holder.add_child(rocket)
	rocket.global_position = p + Vector3.UP * 2.0
	# A shadowed spot with the low-beam cookie (CarLights' player light at night).
	var lights := CarLights.instance()
	if lights != null and lights.get("_cookie") != null:
		var spot := SpotLight3D.new()
		spot.shadow_enabled = true
		spot.light_projector = lights.get("_cookie")
		spot.spot_range = 30.0
		holder.add_child(spot)
		spot.global_position = ground + Vector3.UP * 1.0
		spot.look_at(p, Vector3.UP)
	if wave4:
		_stage_wave4_effects(holder, ground, fwd, right, tree)
	await tree.process_frame


## Copies of the particle systems and meshes that sit idle until something wakes them - the
## weather's rain, splashes and lens drops, the boost's vapour and streaks - turned on in front of
## the camera. A plain duplicate: no script, no signals, no groups.
static func _stage_ghosts(holder: Node3D, ground: Vector3, fwd: Vector3, right: Vector3, tree: SceneTree) -> void:
	var sources: Array = []
	var weather := tree.current_scene.get_node_or_null("Weather") if tree.current_scene else null
	if weather:
		sources.append(weather)
	var player := tree.get_first_node_in_group("player")
	if player:
		var trail := player.get_node_or_null("BoostTrail")
		sources.append(trail if trail else player)
	var at := ground + fwd * 5.0 + Vector3.UP * 1.5
	var n := 0
	for src: Node in sources:
		for g in src.find_children("*", "GeometryInstance3D", true, false):
			if n >= 64:
				break
			if g is CPUParticles3D or g is GPUParticles3D or (g is GeometryInstance3D and not (g as Node3D).is_visible_in_tree()):
				var copy := (g as Node).duplicate(0) as Node3D
				if copy == null:
					continue
				for c in copy.get_children():
					copy.remove_child(c)
					c.free()
				holder.add_child(copy)
				copy.visible = true
				copy.global_position = at + right * (float(n % 8) - 3.5) * 0.6
				if copy is CPUParticles3D:
					(copy as CPUParticles3D).emitting = true
				elif copy is GPUParticles3D:
					(copy as GPUParticles3D).emitting = true
				n += 1
	await tree.process_frame


## Wave 3's car first uses (see `wave3`): one car crashes into nothing (CrashDeform's crumple and
## CrashLitter's shards), a cruiser's bar is lit (PoliceNightLook's glow, pool and wall washes,
## drawn on every renderer), and the everyday bodies get their real cabin and doors for a moment
## (CarInteriors: the door split runs on a worker thread and is cached per body type, so the first
## car the player walks up to or gets into has it ready). Waits on the splits, at most `CABIN_WAIT`.
const CABIN_WAIT := 240


static func _stage_wave3_cars(cars: Array, fwd: Vector3, tree: SceneTree) -> void:
	if cars.size() > 1 and is_instance_valid(cars[1]):
		var c: Vehicle = cars[1]
		c.take_hit(0, 24.0, -fwd, c.global_position - fwd * 2.0 + Vector3.UP * 0.5, Vehicle.HIT_CRASH)
	for car: Vehicle in cars:
		if car is PoliceCar and is_instance_valid(car):
			car.set("_stolen", true)
			break
	var inst := CarInteriors.instance()
	if inst == null:
		return
	var todo: Array = []
	var seen := {}
	for car: Vehicle in cars:
		if is_instance_valid(car) and not seen.has(car.body_type) and CarInteriors.supported(car) and car != cars[0]:
			seen[car.body_type] = true
			todo.append(car)
	var waited := 0
	while not todo.is_empty() and waited < CABIN_WAIT:
		for car: Vehicle in todo.duplicate():
			if not is_instance_valid(car) or inst.activate(car) != null:
				todo.erase(car)
		await tree.process_frame
		waited += 1
	for f in HOLD_FRAMES:
		await tree.process_frame
	for car: Vehicle in cars:
		if is_instance_valid(car) and CarInteriors.rig_of(car) != null:
			inst.deactivate(car)


## Wave 4's car first uses (see `wave4`): a spike strip across the row with two of a car's tyres
## gone flat on it (ChaseFlatTyres' sagging tyre), and a corner crash at speed on another car
## (CrashBreakup: the glass burst, the bonnet, a torn wheel rolling off with its hub dragging, the
## debris ring).
static func _stage_wave4_cars(holder: Node3D, cars: Array, ground: Vector3, fwd: Vector3, right: Vector3, tree: SceneTree) -> void:
	var strip := ChaseSpikeStrip.new()
	holder.add_child(strip)
	strip.global_position = ground + fwd * 10.0
	strip.deploy()
	if cars.size() > 3 and is_instance_valid(cars[3]):
		var flat: Vehicle = cars[3]
		ChaseFlatTyres.puncture(flat, 0)
		ChaseFlatTyres.puncture(flat, 1)
	if cars.size() > 2 and is_instance_valid(cars[2]):
		var c: Vehicle = cars[2]
		var at := c.global_position + c.global_basis * Vector3(0.8, 0.0, -2.0)
		c.take_hit(0, 28.0, -c.global_basis.z, at, Vehicle.HIT_CRASH)
	for f in HOLD_FRAMES:
		await tree.process_frame


## Wave 4's effect first uses: every surface's bullet marks (GunplayFeel: on Compatibility one
## quad material per mark set, on Forward+ the decals, whose textures the atlas keeper holds), the
## smoke off a hot barrel (BarrelSmoke, on the player's gun: it stays there, as it would after the
## first burst), and the police helicopter dressed as the five-star gunship - the first helicopter
## of any kind, which the air traffic flies over the city in the first minute.
static func _stage_wave4_effects(holder: Node3D, ground: Vector3, fwd: Vector3, right: Vector3, tree: SceneTree) -> void:
	if GunplayFeel.enabled:
		var k := 0
		for surf in GunplayFeel.baked_surfaces():
			for v in GunplayFeel.VARIANTS:
				GunplayFeel.hole_textures(surf, v)
			var at := ground + fwd * 7.0 + right * (float(k) - 2.0) * 0.7 + Vector3.UP * 1.0
			GunplayFeel.hole(holder, at, -fwd, surf, holder)
			k += 1
		var player := tree.get_first_node_in_group("player")
		var manager: Node = player.get("weapon_manager") if player else null
		var gun: Weapon = manager.get("current") if manager else null
		if gun != null:
			GunplayFeel.BarrelSmoke.heat_up(gun)
	var heli := Helicopter.new()
	var at_heli := ground + fwd * 45.0 + Vector3.UP * 16.0
	heli.setup(Helicopter.Role.POLICE, WorldState.to_world(at_heli), 0.0, 4242)
	heli.set_meta(TAG, true)
	holder.add_child(heli)
	heli.global_position = at_heli
	WantedEscalation.arm_gunship(heli)


## The burnt rehearsal car stays in CarDamage's static lists (burning, smoking, wrecks) after it is
## freed: Emergency's scan then met a freed instance every second of play (a SCRIPT ERROR each
## time) and the caps counted a car that is not there. Drops every entry that is gone.
static func _purge_statics() -> void:
	# The rehearsal's bullet marks in WeaponFX's cap list, and the pieces its crash and blast left
	# lying in the shared debris rings (CrashDebris, BlastBits: under the camera all session).
	var holes: Array = WeaponFX._holes
	for i in range(holes.size() - 1, -1, -1):
		if not is_instance_valid(holes[i]):
			holes.remove_at(i)
	for list: Array in [CarDamage._burning, CarDamage._smokers, CarDamage._wrecks]:
		for i in range(list.size() - 1, -1, -1):
			if not is_instance_valid(list[i]):
				list.remove_at(i)


## Empties the shared rings the rehearsal's crash and blast threw pieces into (load-time-3: the
## crash's bumper chunks and the blast's chips lay at the spawn point for the whole session).
static func clear_pools() -> void:
	var debris := CrashDebris.instance()
	if debris != null:
		debris.clear()
	var bits := BlastBits.current()
	if bits != null:
		bits.clear()
