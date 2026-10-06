class_name Swim
extends Node3D
## The hero swims (2026-10-05): in the sea, the marina, MacArthur Park's lake, the canals and the
## swimming pools. A child of the Player; `step()` is called first thing in Player's physics tick
## (after the car) and, while he is in the water, does the whole tick itself.
##
## Where the water is and how high its surface stands is SwimWater's (the sea's swell is
## SeaSurface, the ocean shader's vertex stage in GDScript, so he rides the waves that are drawn).
## In the sea, the marina and a pool the floor he would stand on is not the water's (the city's
## ground box at 0, the sea box at -0.1, the paving the pool is painted on), so while he swims
## there the player's mask drops the world layer and Swim holds him over the water's own floor
## (the sand's profile shelving out to the sea floor box; a pool's tank, inside its rect). The
## lake and the canals have real floors under the ground box, which their own volumes let him
## through, so there the mask stays.
##
## At the surface he treads water standing still and swims the front crawl moving; `dive`
## (C / Ctrl / pad X) takes him under, where he swims where the camera looks (jump up, dive down)
## with a breaststroke, or a dolphin kick on the boost; jump at the surface hops out (onto a dock,
## a pool's edge). Boost at the surface is the dolphin: he races along the top and porpoises out
## of the water in arcs; looking up while boosting he bursts out of the water into flight.
## No drowning, no breath: he is overpowered. No guns in the water (the gun is put away).
## Splashes, the wake, stroke splashes, bubbles and the underwater view are SwimFX.
## `SWIMMING=0` in the environment turns it all off (SwimWater.enabled).
## Stills: SWIM_STAGE=tread|crawl|boost|dive|leap|under on tools/glshot/still_shot.gd fakes the
## input (see _stage_input()).

@export_group("Speeds")
## Front crawl at the surface (m/s).
@export var swim_speed: float = 4.2
## Under the water (m/s).
@export var under_speed: float = 4.6
## The boost in the water, at the surface and under (m/s): he is overpowered.
@export var boost_speed: float = 17.0
## How fast he gets up to speed (m/s^2), and with the boost.
@export var accel: float = 5.0
@export var boost_accel: float = 26.0
## Below this he treads water (m/s).
@export var tread_below: float = 1.3
## Diving down and rising under the water with dive / jump held (m/s).
@export var dive_speed: float = 3.4
## How fast he floats back up under the water when he lets go of everything (m/s).
@export var idle_rise: float = 2.4

@export_group("Floating")
## Metres from his feet to the surface while he treads (water at the shoulders), and while he
## lies prone in the crawl (the capsule's own depth; the body is laid at the surface).
@export var tread_depth: float = 1.42
@export var crawl_depth: float = 1.2
## How hard the water pulls him to his floating depth (1/s) and the most it moves him (m/s).
@export var buoyancy: float = 3.5
@export var buoyancy_max: float = 3.0
## How fast a dive into the water is slowed (1/s): a 30 m fall goes about eight metres down.
@export var entry_drag: float = 3.2
## Water shallower than this is waded, not swum (metres).
@export var min_depth: float = 0.55
## He goes in when his feet come down within this of the surface (metres).
@export var enter_above: float = 0.45

@export_group("Out of the water")
## The hop out at the surface (m/s up).
@export var jump_out: float = 8.5
## The dolphin: at boost speed he leaps this fast up every `leap_gap` seconds at the surface.
@export var leap_up: float = 6.5
@export var leap_gap: float = 0.55
## Gravity on a leap (m/s^2): a little floaty, it is a game.
@export var leap_gravity: float = 17.0
## Boosting with the camera pitched up past this (degrees) launches him out into flight.
@export var launch_pitch: float = 24.0
@export var launch_speed: float = 24.0

var swimming: bool = false
## Under the water (diving) rather than at the surface.
var under: bool = false
## Out of the water on a dolphin leap.
var leaping: bool = false
## The water he is in (SwimWater.at()), last tick.
var water: Dictionary = {}

var _player: Player
var _stripped: bool = false
var _sea: Array = []
var _sea_age: float = 99.0
var _phase: float = 0.0
var _prone: float = 0.0
var _lay: float = 0.0
var _weights := PackedFloat32Array([0.0, 1.0, 0.0, 0.0])
var _since_leap: float = 9.0
var _last_u: float = 0.0
var _wake: CPUParticles3D
var _spray: CPUParticles3D
var _bubbles: CPUParticles3D
var _overlay: MeshInstance3D
var _overlay_mat: ShaderMaterial
var _underside: MeshInstance3D
var _underside_mat: ShaderMaterial
var _under_sound: AudioStreamPlayer
var _stage := ""
var _stage_t: float = 0.0
var _under_t: float = 0.0
## Under by his own dive (he stays under) rather than by a plunge (he comes back up).
var _dived: bool = false
## SWIM_HOLD=1 (stills): he swims on the spot where he went in, so a fixed camera can frame him.
var _hold := Vector3.INF


func _ready() -> void:
	_player = get_parent() as Player
	_stage = OS.get_environment("SWIM_STAGE")
	_build_fx()


func _process(delta: float) -> void:
	SeaSurface.advance(delta)
	if swimming and _player and _player.vehicle != null:
		# Into a car from the water (a dock, a boat ramp): enter_vehicle() owns the mask now.
		swimming = false
		under = false
		leaping = false
		_stripped = false
		water = {}
	if _player and _player.avatar and _player.avatar.swim_pose and not swimming:
		var sp := _player.avatar.swim_pose
		sp.weight = move_toward(sp.weight, 0.0, delta * 4.0)
	_update_view()


## Player's hook: true when Swim did this physics tick (he is in the water).
func step(delta: float) -> bool:
	if not SwimWater.enabled or _player == null:
		return false
	if _player.is_downed() or _player.vehicle != null:
		if swimming:
			_exit()
		return false
	_sea_age += delta
	if _sea_age > 0.5 or _sea.is_empty():
		_sea = SeaSurface.state(get_tree())
		_sea_age = 0.0
	var tp := WorldState.to_world(_player.global_position)
	var w := SwimWater.at(_macro(), tp, SeaSurface.now(), _sea)
	if not swimming:
		if w.is_empty() or not _can_enter(w, tp):
			return false
		_enter(w, tp)
	elif w.is_empty() or (not leaping and float(w.surface) - float(w.floor) < min_depth * 0.8):
		# Swum out of it (up a ramp, the beach, a lake's shore) or leapt over land, or the water
		# is too shallow to swim: he stands up and wades.
		_exit()
		return false
	water = w
	_strip(bool(w.solid))
	_swim(delta, w, tp)
	return true


## The world layer off the player's mask (water with no floor of its own: the sea, the marina, a
## pool) or back on.
func _strip(on: bool) -> void:
	if on == _stripped:
		return
	_stripped = on
	if on:
		_player.collision_mask = _player.collision_mask & ~1
	else:
		_player.collision_mask = _player.collision_mask | 1


func is_swimming() -> bool:
	return swimming


func _macro() -> MacroMap:
	var city := get_tree().get_first_node_in_group("city")
	var plan = city.get("plan") if city else null
	return plan.macro if plan is CityPlan else null


func _can_enter(w: Dictionary, tp: Vector3) -> bool:
	var surface: float = w.surface
	if surface - float(w.floor) < min_depth:
		return false
	if int(w.kind) == SwimWater.Kind.SEA and float(w.s) < CityChunk.SAND_STEEP_AT:
		return false
	if int(w.kind) == SwimWater.Kind.POOL and not (w.rect as Rect2).grow(-0.3).has_point(Vector2(tp.x, tp.z)):
		return false
	if bool(w.solid):
		return tp.y < surface + enter_above and (_player.velocity.y <= 0.5 or _player.is_on_floor())
	# The lake and the canals: he wades in down to the floor and swims once it is deep enough.
	return tp.y < surface - 0.3


func _enter(w: Dictionary, tp: Vector3) -> void:
	swimming = true
	leaping = false
	_since_leap = 9.0
	_strip(bool(w.solid))
	var fall := -_player.velocity.y
	under = fall > 9.0 or tp.y < float(w.surface) - tread_depth - 0.8
	_dived = false
	if _stage in ["crawl", "tread", "boost"]:
		under = false # stills of the surface strokes start at the surface
	_prone = 1.0 if Vector2(_player.velocity.x, _player.velocity.z).length() > tread_below else 0.0
	if _player.weapon_manager:
		_player.weapon_manager.visible = false
	if _player.avatar:
		_player.avatar.hold_gun(null, false, 0.0)
	_player.set("_boosting", false)
	var bt = _player.get("_boost_fx")
	if bt:
		bt.drive(false, Vector3.ZERO, 1.0)
	var snd = _player.get("_boost_sound")
	if snd and snd.playing:
		snd.stop()
	if fall > 2.5 or _player.velocity.length() > 6.0:
		_splash_at(tp, clampf(fall / 12.0 + _player.velocity.length() / 40.0, 0.3, 3.5))


func _exit() -> void:
	if not swimming:
		return
	swimming = false
	under = false
	leaping = false
	_strip(false)
	if _player.weapon_manager:
		_player.weapon_manager.visible = true
	water = {}
	_wake.emitting = false
	_spray.emitting = false
	_bubbles.emitting = false


func _local_y(true_y: float) -> float:
	return true_y - WorldState.world_offset.y


func _swim(delta: float, w: Dictionary, tp: Vector3) -> void:
	var p := _player
	var surface := _local_y(float(w.surface))
	var floor_y := _local_y(float(w.floor))
	var feet := p.global_position.y
	var input := _stage_input(delta)
	var move_dir: Vector3 = p._camera_relative_direction(input)
	var boosting := Input.is_action_pressed("boost") or _stage in ["boost", "leap"]
	var pitch: float = p.camera_rig.rotation.x
	var deep_enough := surface - floor_y > 2.2
	var v := p.velocity
	_since_leap += delta

	if Input.is_action_just_pressed("respawn"):
		_exit()
		p.respawn()
		return

	if leaping:
		# Out of the water on a dolphin arc: gravity until he is back in.
		v.y -= leap_gravity * delta
		var hv := Vector2(v.x, v.z)
		if move_dir != Vector3.ZERO:
			var want := Vector2(move_dir.x, move_dir.z).normalized() * hv.length()
			hv = hv.lerp(want, 1.0 - exp(-3.0 * delta))
		v.x = hv.x
		v.z = hv.y
		if feet + 0.9 < surface and v.y < 0.0:
			leaping = false
			_splash_at(tp, clampf(-v.y / 8.0, 0.5, 1.6))
			v.y *= 0.35
	else:
		# Going under, coming up.
		if not under and deep_enough and (Input.is_action_just_pressed("dive") or _stage in ["dive", "under"]):
			under = true
			_dived = true
			v.y = minf(v.y, -2.5)
			SwimFX.stroke(_fx_parent(), Vector3(p.global_position.x, surface, p.global_position.z), 0.8)
		if not deep_enough:
			under = false
		var float_d := lerpf(tread_depth, crawl_depth, _prone)
		var head_out := feet > surface - float_d - 0.15
		if under:
			_under_t += delta
		else:
			_under_t = 0.0
		# Back at the surface once the head is out, unless he is still diving (and never in the
		# first moments of a dive, which starts at the surface).
		if under and head_out and _under_t > 0.6 and not Input.is_action_pressed("dive") and _stage != "under":
			under = false
			_dived = false
		var speed := boost_speed if boosting else (under_speed if under else swim_speed)
		var rate := boost_accel if boosting else accel
		if under:
			var look := -p.camera.global_basis.z
			var side := p.camera.global_basis.x
			# Under the water he swims where the camera looks, with a dead band round level so a
			# camera looking a little down does not take him to the bottom.
			var lp := asin(clampf(look.y, -1.0, 1.0))
			lp = signf(lp) * maxf(absf(lp) - deg_to_rad(12.0), 0.0)
			var flat_look := Vector3(look.x, 0.0, look.z).normalized()
			look = (flat_look * cos(lp) + Vector3.UP * sin(lp)).normalized()
			var want := (look * -input.y + side * input.x)
			if want.length() > 1.0:
				want = want.normalized()
			want *= speed
			if Input.is_action_pressed("jump"):
				want.y = maxf(want.y, dive_speed)
			elif Input.is_action_pressed("dive") or _stage == "under":
				want.y = minf(want.y, -dive_speed)
			elif want.length() < 0.5 or not _dived:
				# He floats back up when he lets go, and after a plunge he did not ask for.
				want.y = maxf(want.y, idle_rise)
			# A fast entry is slowed by the water, not by his stroke.
			if v.y < want.y - 6.0:
				v.y = lerpf(v.y, want.y, 1.0 - exp(-entry_drag * delta))
				v.x = lerpf(v.x, want.x, 1.0 - exp(-entry_drag * 0.6 * delta))
				v.z = lerpf(v.z, want.z, 1.0 - exp(-entry_drag * 0.6 * delta))
			else:
				v = v.move_toward(want, rate * delta)
		else:
			var hv := Vector2(v.x, v.z).move_toward(Vector2(move_dir.x, move_dir.z) * speed, rate * delta)
			v.x = hv.x
			v.z = hv.y
			var target := surface - float_d
			if v.y < -4.0:
				v.y = lerpf(v.y, 0.0, 1.0 - exp(-entry_drag * delta))
			else:
				v.y = clampf((target - feet) * buoyancy, -buoyancy_max, buoyancy_max)
			# Jump: out of the water (onto a dock, a pool's edge).
			if Input.is_action_just_pressed("jump") and _stage == "":
				v.y = jump_out
				_exit()
				p.velocity = v
				p.move_and_slide()
				_splash_at(tp, 0.7)
				return
			var flat_speed := hv.length()
			# Looking up on the boost: out of the water and into flight.
			if boosting and rad_to_deg(pitch) > launch_pitch and _stage == "":
				var dir := (Vector3(move_dir.x, 0.0, move_dir.z).normalized() * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
				p.velocity = dir * launch_speed
				_splash_at(tp, 1.6)
				_exit()
				p.global_position.y = maxf(p.global_position.y, surface - 0.5)
				return
			# The dolphin: porpoising out of the water at boost speed.
			if boosting and flat_speed > boost_speed * 0.6 and _since_leap > leap_gap and head_out:
				leaping = true
				_since_leap = 0.0
				v.y = leap_up
				_splash_at(tp, 1.0)
	p.velocity = v
	p.move_and_slide()
	if _stage != "" and OS.get_environment("SWIM_HOLD") == "1":
		if _hold == Vector3.INF:
			_hold = WorldState.to_world(p.global_position)
		var hl := WorldState.to_local(_hold)
		p.global_position = Vector3(hl.x, p.global_position.y, hl.z)
		var depth := float(OS.get_environment("SWIM_DEPTH")) if OS.get_environment("SWIM_DEPTH") != "" else 3.0
		if _stage == "under" and p.global_position.y < surface - depth:
			_stage = "glide"
	# Hold him over the water's floor (the sea's, the marina's, a pool's tank) and in a pool's rect.
	var pos := p.global_position
	var tank: Rect2 = w.get("rect", Rect2())
	if bool(w.solid):
		if pos.y < floor_y + 0.1:
			pos.y = floor_y + 0.1
			p.velocity.y = maxf(p.velocity.y, 0.0)
		if int(w.kind) == SwimWater.Kind.POOL:
			var lo := WorldState.to_local(Vector3(tank.position.x, 0.0, tank.position.y))
			var r := Rect2(Vector2(lo.x, lo.z), tank.size).grow(-0.45)
			pos.x = clampf(pos.x, r.position.x, r.end.x)
			pos.z = clampf(pos.z, r.position.y, r.end.y)
		if not leaping:
			pos.y = minf(pos.y, surface - 0.35)
		p.global_position = pos
	_animate(delta, surface, move_dir, boosting)


## The strokes and the body (SwimPose and Avatar.swim_body()), the facing, the effects.
func _animate(delta: float, surface: float, move_dir: Vector3, boosting: bool) -> void:
	var p := _player
	var v := p.velocity
	var flat := Vector2(v.x, v.z).length()
	var moving := flat > tread_below or under or leaping
	_prone = move_toward(_prone, 1.0 if moving else 0.0, delta * 2.0)
	var water_line := surface - p.global_position.y
	# The weights of the strokes.
	var want := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	if leaping or (under and boosting):
		want[SwimPose.Stroke.STREAM] = 1.0
	elif under:
		want[SwimPose.Stroke.BREAST] = 1.0
	elif boosting and flat > swim_speed * 1.5:
		want[SwimPose.Stroke.CRAWL] = 0.7
		want[SwimPose.Stroke.STREAM] = 0.3
	else:
		want[SwimPose.Stroke.CRAWL] = _prone
		want[SwimPose.Stroke.TREAD] = 1.0 - _prone
	var k := 1.0 - exp(-6.0 * delta)
	for i in 4:
		_weights[i] = lerpf(_weights[i], want[i], k)
	# The stroke rate: a crawl cycle (both arms) about every 1.4 s at swimming speed, faster on the
	# boost; the breaststroke slower; treading steady.
	var cycles := 0.55 + 0.25 * clampf(flat / swim_speed, 0.0, 1.0)
	if boosting:
		cycles = 1.35 if not under else 1.1
	elif under:
		cycles = 0.55
	if _weights[SwimPose.Stroke.TREAD] > 0.5:
		cycles = 0.45
	_phase = fposmod(_phase + TAU * cycles * delta, TAU * 1000.0)
	# The body: upright treading, prone in the crawl, along the velocity under and leaping.
	var lay_target := lerpf(0.18, PI * 0.5 - 0.06, _prone)
	if under or leaping:
		var dir := v.normalized() if v.length() > 1.0 else -p.visual.global_basis.z
		lay_target = clampf(PI * 0.5 - asin(clampf(dir.y, -1.0, 1.0)), 0.05, PI - 0.15)
	_lay = lerp_angle(_lay, lay_target, 1.0 - exp(-5.0 * delta))
	var roll := 0.32 * sin(_phase) * _weights[SwimPose.Stroke.CRAWL]
	var rise := 0.0
	if not under and not leaping:
		# The body at the surface: shoulders at the water treading, the back just awash prone.
		rise = water_line - lerpf(1.42, 0.92, _prone)
		rise += 0.05 * sin(_phase * 2.0) * _weights[SwimPose.Stroke.TREAD]
	var face := move_dir
	if under or leaping:
		face = Vector3(v.x, 0.0, v.z) if flat > 0.5 else Vector3.ZERO
	p._update_visual(delta, face)
	if p.avatar:
		p.avatar.hold_gun(null, false, delta)
		p.avatar.swim_body(_lay, roll, rise)
		var sp := p.avatar.swim_pose
		if sp:
			sp.weight = move_toward(sp.weight, 1.0, delta * 5.0)
			sp.mix = _weights
			sp.phase = _phase
			sp.kick = clampf(0.4 + flat / swim_speed * 0.5, 0.3, 1.2) if not boosting else 1.3
			var cyc := int(floor(_phase / TAU))
			var u := fposmod(_phase / TAU, 1.0)
			sp.breathe = smoothstep(0.1, 0.25, u) * (1.0 - smoothstep(0.45, 0.6, u)) if cyc % 2 == 0 else 0.0
	_effects(delta, surface, flat, boosting)


func _effects(delta: float, surface: float, flat: float, boosting: bool) -> void:
	var p := _player
	var pos := p.global_position
	var at_surface := not under and not leaping
	# A hand goes in at each half cycle of the crawl.
	var u := fposmod(_phase / PI, 1.0)
	if at_surface and _weights[SwimPose.Stroke.CRAWL] > 0.5 and u < _last_u:
		var fwd := -p.visual.global_basis.z
		var side := p.visual.global_basis.x * (0.28 if int(floor(_phase / PI)) % 2 == 0 else -0.28)
		SwimFX.stroke(_fx_parent(), Vector3(pos.x, surface, pos.z) + fwd * 1.05 + side, clampf(flat / swim_speed, 0.4, 1.5) * (1.6 if boosting else 1.0))
	_last_u = u
	# The wake: a narrow V off the head and shoulders. The foam stays where it was laid and spreads
	# sideways, so a moving emitter draws the V; held on the spot (stills) it drifts back instead.
	var fwd := -p.visual.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	_wake.global_position = Vector3(pos.x, surface + 0.02, pos.z) + fwd * 0.85
	_wake.emitting = at_surface and flat > 0.6
	if _hold != Vector3.INF:
		_wake.direction = -fwd
		_wake.spread = 24.0
		_wake.initial_velocity_min = flat * 0.55
		_wake.initial_velocity_max = flat * 1.05
	else:
		_wake.direction = Vector3.UP
		_wake.spread = 180.0
		_wake.initial_velocity_min = 0.25
		_wake.initial_velocity_max = 0.3 + flat * 0.05
	_spray.global_position = Vector3(pos.x, surface + 0.1, pos.z)
	_spray.emitting = at_surface and boosting and flat > swim_speed * 1.5
	if _spray.emitting:
		var back := Vector3(-p.velocity.x, 0.0, -p.velocity.z).normalized()
		_spray.direction = (back + Vector3.UP * 0.9).normalized()
	_bubbles.global_position = pos + Vector3.UP * 0.9
	# Only deep enough that they burst before they reach the top (the sea is drawn opaque, and
	# bubbles past it showed as specks on the water).
	_bubbles.emitting = under and surface - (pos.y + 0.9) > 1.2


func _splash_at(tp: Vector3, strength: float) -> void:
	var local := WorldState.to_local(tp)
	var surface := _local_y(float(water.get("surface", tp.y))) if not water.is_empty() else local.y
	SwimFX.splash(_fx_parent(), Vector3(local.x, surface + 0.02, local.z), strength)


func _fx_parent() -> Node:
	return _player.get_parent() if _player and _player.get_parent() else self


# --- the view from under the water --------------------------------------------------------------

func _build_fx() -> void:
	_wake = CPUParticles3D.new()
	_wake.name = "SwimWake"
	_wake.emitting = false
	_wake.amount = 48
	_wake.lifetime = 1.8
	_wake.mesh = SwimFX._flat(1.0, SwimFX.foam_material())
	_wake.direction = Vector3.UP
	_wake.spread = 180.0
	_wake.flatness = 1.0
	_wake.gravity = Vector3.ZERO
	_wake.initial_velocity_min = 0.1
	_wake.initial_velocity_max = 0.5
	_wake.damping_min = 0.2
	_wake.damping_max = 0.6
	_wake.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_wake.emission_sphere_radius = 0.3
	_wake.scale_amount_min = 0.3
	_wake.scale_amount_max = 0.8
	_wake.angle_min = 0.0
	_wake.angle_max = 360.0
	# Turned about the vertical (the patches lie flat on the water).
	_wake.particle_flag_rotate_y = true
	_wake.scale_amount_curve = SwimFX._grow(0.6, 1.6)
	_wake.color_ramp = SwimFX._fade_ramp(0.5, SwimFX.FOAM_COLOR)
	_wake.local_coords = false
	_wake.top_level = true
	add_child(_wake)
	_spray = CPUParticles3D.new()
	_spray.name = "SwimSpray"
	_spray.emitting = false
	_spray.amount = 90
	_spray.lifetime = 0.9
	_spray.mesh = SwimFX._quad(0.08, SwimFX.drop_material())
	_spray.spread = 22.0
	_spray.initial_velocity_min = 4.0
	_spray.initial_velocity_max = 8.0
	_spray.gravity = Vector3(0, -9.8, 0)
	_spray.scale_amount_min = 0.7
	_spray.scale_amount_max = 2.0
	_spray.color_ramp = SwimFX._fade_ramp(0.85, SwimFX.DROP_COLOR)
	_spray.local_coords = false
	_spray.top_level = true
	add_child(_spray)
	_bubbles = CPUParticles3D.new()
	_bubbles.name = "SwimBubbles"
	_bubbles.emitting = false
	_bubbles.amount = 24
	_bubbles.lifetime = 0.8
	_bubbles.mesh = SwimFX._quad(0.06, SwimFX.bubble_material())
	_bubbles.direction = Vector3.UP
	_bubbles.spread = 25.0
	_bubbles.initial_velocity_min = 0.4
	_bubbles.initial_velocity_max = 1.2
	_bubbles.gravity = Vector3(0, 2.5, 0)
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_bubbles.emission_sphere_radius = 0.25
	_bubbles.scale_amount_min = 0.5
	_bubbles.scale_amount_max = 1.6
	_bubbles.color_ramp = SwimFX._fade_ramp(0.7, Color(0.85, 0.95, 1.0))
	_bubbles.local_coords = false
	_bubbles.top_level = true
	add_child(_bubbles)
	for e in [_wake, _spray, _bubbles]:
		(e as CPUParticles3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if DisplayServer.get_name() == "headless":
		return
	_overlay = MeshInstance3D.new()
	_overlay.name = "Underwater"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_overlay.mesh = quad
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = load("res://shaders/underwater.gdshader")
	_overlay_mat.render_priority = Material.RENDER_PRIORITY_MIN
	_overlay.material_override = _overlay_mat
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex stage covers the screen whatever the transform: never cull it.
	_overlay.extra_cull_margin = 16384.0
	_overlay.top_level = true
	_overlay.visible = false
	add_child(_overlay)
	_underside = MeshInstance3D.new()
	_underside.name = "WaterUnderside"
	var plane := PlaneMesh.new()
	plane.size = Vector2(900.0, 900.0)
	plane.flip_faces = true
	_underside.mesh = plane
	_underside_mat = ShaderMaterial.new()
	_underside_mat.shader = load("res://shaders/water_underside.gdshader")
	_underside.material_override = _underside_mat
	_underside.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_underside.top_level = true
	_underside.visible = false
	add_child(_underside)
	_under_sound = AudioStreamPlayer.new()
	_under_sound.stream = SwimFX.sound_stream("under")
	_under_sound.volume_db = -16.0
	add_child(_under_sound)


## Under the surface or not, by the camera's own point (it can dip under while he does not).
func _update_view() -> void:
	if _overlay == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	var below := 0.0
	var surface_l := 0.0
	if cam and (swimming or not water.is_empty()):
		var ct := WorldState.to_world(cam.global_position)
		var w := water if not water.is_empty() else {}
		var surface := float(w.get("surface", -INF))
		if int(w.get("kind", 0)) == SwimWater.Kind.SEA:
			surface = SeaSurface.height(_macro(), Vector2(ct.x, ct.z), SeaSurface.now(), _sea)
		surface_l = _local_y(surface)
		below = surface_l - cam.global_position.y
	var on := below > 0.02 and swimming
	_overlay.visible = on
	_underside.visible = on
	if on:
		_overlay_mat.set_shader_parameter("depth_m", below)
		# DayNight's lamp level: 0 by day, 1 at night (never read the global back from the server).
		_overlay_mat.set_shader_parameter("light", 1.0 - 0.85 * DayNight.lamp_now)
		_underside.global_position = Vector3(cam.global_position.x, surface_l, cam.global_position.z)
		_overlay.global_position = cam.global_position
		var off := WorldState.world_offset
		_underside_mat.set_shader_parameter("world_offset", Vector2(off.x, off.z))
		if not _under_sound.playing:
			_under_sound.play()
	elif _under_sound.playing:
		_under_sound.stop()


# --- staging for stills -------------------------------------------------------------------------

## SWIM_STAGE fakes the stick for stills: tread (still), crawl (forward), boost (forward on the
## boost, porpoising), dive / under (forward, going down), leap (one dolphin leap). Real input
## otherwise.
func _stage_input(delta: float) -> Vector2:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _stage == "":
		return input
	_stage_t += delta
	match _stage:
		"tread":
			return Vector2.ZERO
		_:
			return Vector2(0.0, -1.0)
	# "glide": under the water at SWIM_DEPTH, swimming level (the under stage hands over to it).
