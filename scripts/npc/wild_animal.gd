class_name WildAnimal
extends Dog
## One wild animal (WildSpecies: a coyote, a mule deer, a raccoon, a fox squirrel, a cottontail)
## that Wildlife put down round the player. It is a Dog underneath - DogRig's body and gait,
## DogBody's hit box on the npc layer, Dog's bolt (a scripted hop off a hit, then a run until it
## is out of sight and gone) - with a wild animal's brain on top:
##   IDLE     grazes or forages (the nose down), sits up (a squirrel eating, a rabbit on watch, a
##            raccoon at the bins), looks round; now and then walks or hops somewhere near home
##   WANDER   walks / hops to a point near home
##   TRAVEL   follows its route (a coyote trotting across a street or a hill road, on and away)
##   ALERT    the player is within `alert` metres: it freezes, ears up, and watches him
##   (fleeing) within `flush` (more the faster he comes), at a gunshot or a blast near it
##            (Dog.startle_all from Pedestrian.alarm), or hit: it bolts away from him or the
##            noise - a deer stotting, a rabbit or squirrel bounding, a coyote at full stretch -
##            and is gone once out of sight. Never blood, never a ragdoll, never a crime.

enum Mode { IDLE, WANDER, TRAVEL, ALERT }

var species: String = "coyote"
## Where it lives (the parent's space: Wildlife's, which the origin shifts carry).
var home := Vector3.ZERO
var home_radius: float = 10.0
## A route in the parent's space (TRAVEL), walked in order.
var route: Array = []
## Raccoon at the kerb carts: sits up at them and roots about.
var at_bins: bool = false
## Stills and checks: nothing flushes it but a hit or a gun (Wildlife.stage()).
var calm: bool = false
## Wildlife's id for it.
var wid: int = 0

var mode: int = Mode.IDLE
var _sp: Dictionary
var _mode_left: float = 2.0
var _target := Vector3.ZERO
var _idle_pose: int = 0
var _alert_left: float = 0.0
var _player_prev := Vector3.INF
var _player_speed: float = 0.0
var _think: float = 0.0
var _pronk: float = 0.0

static var flushes: int = 0
static var hits: int = 0


## The animal from a seed (look, size, sex, which antlers).
func setup(species_name: String, seed_value: int) -> void:
	species = species_name
	_sp = WildSpecies.data(species)
	roll(seed_value, species)
	flee_speed = float(_sp.flee)
	flee_min_seconds = 3.0
	flee_max_seconds = 18.0
	startle_reach = 30.0 if species == "deer" else 18.0


func _ready() -> void:
	add_to_group("wildlife")
	_make_body()
	var g: Array = _sp.get("gait", [2.05, 5.2])
	rig.trot_at = float(g[0])
	rig.gallop_at = float(g[1])
	# The small ones' fur shells matter only close by; the deer's carry further.
	rig.draw_range = 95.0 if species == "deer" else (70.0 if species == "coyote" else 45.0)
	rig.wag = 0.0
	if species == "deer" and _rng.randf() < 0.42:
		_add_antlers(2 + _rng.randi() % 3)
	rotation.y = _yaw
	_mode_left = _rng.randf_range(0.5, 4.0)
	_idle_pose = _rng.randi() % 3
	if not route.is_empty():
		mode = Mode.TRAVEL


func _add_antlers(points: int) -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	rig.skeleton.add_child(att)
	var near := MeshInstance3D.new()
	near.mesh = WildSpecies.antler_mesh(mini(points, 4), 0)
	near.visibility_range_end = 35.0
	att.add_child(near)
	var far := MeshInstance3D.new()
	far.mesh = WildSpecies.antler_mesh(mini(points, 4), 1)
	far.visibility_range_begin = 35.0
	far.visibility_range_end = 110.0
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	att.add_child(far)
	# The head bone's rest is a translation at the head joint; the antlers are built about it.
	att.set_meta("antlers", points)


func antlers() -> int:
	for c in rig.skeleton.get_children():
		if c is BoneAttachment3D and c.has_meta("antlers"):
			return int(c.get_meta("antlers"))
	return 0


## A hit: the hop and the bolt (Dog), a coyote's yelp; the others run silent.
func hit(impulse: Vector3) -> void:
	hits_taken += 1
	hits += 1
	if species == "coyote" and is_inside_tree():
		Sfx.play("dog_yelp", global_position + Vector3.UP * height() * 0.7, 0.0, _pitch * 1.15)
	var flat := Vector3(impulse.x, 0.0, impulse.z)
	if flat.length_squared() < 0.01:
		flat = -global_basis.z
	var push := clampf(impulse.length() * 0.35, 1.5, 7.0) * clampf(0.5 / height(), 0.6, 1.6)
	_vel = flat.normalized() * push + Vector3.UP * clampf(impulse.y * 0.4 + 2.0, 2.0, 6.0)
	_air = true
	_flee_from(global_position - flat.normalized())


func _on_startle(at: Vector3) -> void:
	_flee_from(at)


## Bolts away from `from` (world), a little off the straight line so a herd scatters.
func _flee_from(from: Vector3) -> void:
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -global_basis.z
	away = away.normalized().rotated(Vector3.UP, _rng.randf_range(-0.45, 0.45))
	if not fleeing:
		flushes += 1
	_bolt(away)
	if rig:
		rig.sit = 0.0
		rig.sniff = 0.0


func _physics_process(delta: float) -> void:
	if rig == null:
		return
	var dt := minf(delta, 0.1)
	if fleeing:
		_tick_flee(dt)
		_tick_pronk(dt)
		_advance_rig(dt)
		return
	_think -= dt
	if _think <= 0.0:
		_think = 0.2
		_watch_player(0.2)
	match mode:
		Mode.ALERT:
			_tick_alert(dt)
		Mode.TRAVEL:
			_tick_move(dt, true)
		Mode.WANDER:
			_tick_move(dt, false)
		_:
			_tick_idle(dt)
	_advance_rig(dt)


## The player: how far and how fast; alert or flush.
func _watch_player(dt: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or calm:
		return
	var pp := p.global_position
	if _player_prev != Vector3.INF:
		_player_speed = lerpf(_player_speed, pp.distance_to(_player_prev) / dt, 0.5)
	_player_prev = pp
	var d := pp.distance_to(global_position)
	var flush := float(_sp.flush) + _player_speed * 0.9
	if d < flush:
		_flee_from(pp)
		return
	if d < float(_sp.alert) + _player_speed * 1.2 and mode != Mode.ALERT:
		mode = Mode.ALERT
		_alert_left = _rng.randf_range(3.0, 7.0)
	if mode == Mode.ALERT:
		rig.look_at = rig.to_local(pp + Vector3.UP * 1.6)
		if d > float(_sp.alert) * 1.25:
			_alert_left -= dt


func _tick_alert(dt: float) -> void:
	rig.speed = 0.0
	rig.sniff = 0.0
	rig.sit = 0.55 if species in ["squirrel", "rabbit", "raccoon"] else 0.0
	rig.fear = 0.15
	_alert_left -= dt * 0.25
	if _alert_left <= 0.0:
		rig.look_at = Vector3.INF
		rig.fear = 0.0
		mode = Mode.TRAVEL if not route.is_empty() else Mode.IDLE
		_mode_left = _rng.randf_range(1.0, 3.0)


func _tick_idle(dt: float) -> void:
	rig.speed = 0.0
	rig.turn = 0.0
	_mode_left -= dt
	var t := Time.get_ticks_msec() * 0.001 + float(wid % 97)
	match species:
		"deer", "rabbit":
			# Grazing: the head down, up now and then to look round.
			var up := smoothstep(0.82, 0.92, fposmod(t * 0.13, 1.0))
			rig.sniff = 1.0 - up
			rig.sit = 0.7 if species == "rabbit" and _idle_pose == 1 else 0.0
		"squirrel":
			rig.sit = 1.0 if _idle_pose != 2 else 0.0
			rig.sniff = 0.0 if _idle_pose != 2 else 1.0
		"raccoon":
			rig.sit = 0.8 if at_bins and fposmod(t * 0.2, 1.0) < 0.55 else 0.0
			rig.sniff = 1.0 - rig.sit
		_:
			# A coyote stands, sniffs the verge, looks down the road.
			rig.sniff = 1.0 if _idle_pose == 0 else 0.0
			rig.sit = 0.0
	if _mode_left <= 0.0:
		if not route.is_empty():
			mode = Mode.TRAVEL
			return
		_idle_pose = _rng.randi() % 3
		if _rng.randf() < 0.55:
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(0.3, 1.0) * home_radius
			_target = home + Vector3(sin(a) * r, 0.0, cos(a) * r)
			mode = Mode.WANDER
		_mode_left = _rng.randf_range(2.0, 7.0) * (0.5 if species in ["squirrel", "rabbit"] else 1.0)


## Walks (or trots, or hops) toward the target or along the route.
func _tick_move(dt: float, travel: bool) -> void:
	var tgt := _target
	if travel:
		if route.is_empty():
			mode = Mode.IDLE
			return
		tgt = route[0]
	var to := tgt - position
	to.y = 0.0
	var d := to.length()
	if d < maxf(height(), 0.4):
		if travel:
			route.remove_at(0)
			if route.is_empty():
				home = position
				mode = Mode.IDLE
		else:
			mode = Mode.IDLE
		_mode_left = _rng.randf_range(2.0, 6.0)
		return
	var spd := float(_sp.wander)
	if travel and species == "coyote":
		spd = 1.9
	elif species in ["squirrel", "rabbit"]:
		# Small animals move in hops and dashes: on for a beat, off for a beat.
		var beat := fposmod(Time.get_ticks_msec() * 0.0012 + float(wid % 17) * 0.1, 1.0)
		spd = 1.4 if beat < 0.45 else 0.0
	var want := atan2(-to.x, -to.z)
	var prev := _yaw
	_yaw = lerp_angle(_yaw, want, 1.0 - exp(-4.0 * dt))
	_turn = wrapf(_yaw - prev, -PI, PI) / maxf(dt, 1e-4)
	rotation.y = _yaw
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	position += fwd * spd * dt
	_ray_tick += 1
	if _ray_tick % 4 == 0:
		_ground_y = _ground_at(global_position)
	global_position.y = lerpf(global_position.y, _ground_y, 1.0 - exp(-12.0 * dt))
	rig.speed = spd
	rig.turn = _turn
	rig.sniff = 0.25 if species == "coyote" and travel else 0.0
	rig.sit = 0.0
	rig.look_at = Vector3.INF


## A mule deer bolts in stots: all four feet leave the ground together, the body thrown up a
## good share of its height each bound.
func _tick_pronk(_dt: float) -> void:
	if not _sp.get("pronk", false) or rig == null:
		return
	var duty := 0.34
	var phi := fposmod(rig._phase, 1.0)
	var lift := 0.0
	if phi > duty and not _air:
		lift = sin((phi - duty) / (1.0 - duty) * PI) * height() * 0.42
	_pronk = lift
	rig.position.y = lift
