class_name Wingsuit
extends Node3D
## The hero's wingsuit (fleet task "wingsuit", 2026-10-06). In the air, `wingsuit` (G / pad X) -
## or holding jump on the way down - spreads it, as long as there is `open_clearance` of air under
## him. Then he flies it: W / S (the move axes' forward and back) pitch the dive and the flare,
## A / D roll him into a banked turn, speed comes from the dive (gravity along the flight path,
## drag growing with the square of the speed), a pull-up trades it for height, boost thrusts along
## the flight. Near the ground he flares by himself; touching down slower than `run_out_speed`
## he runs it out, faster he skids on one knee in a spray of grit (`skid_decel`). Jump or the key
## again folds the suit away (a buffered jump hops him out of it); a wall at speed folds it too.
##
## The player owns nothing of this: Player._physics_process() hands each tick to tick(), which
## returns true while the suit has the body (gliding or skidding) and has then moved it itself.
## The pose is HeroMotion's `glide` aims on the hero (Avatar.glide / glide_tilt / glide_bank);
## the fabric and the wingtip vapour are WingsuitFx (scripts/player/wingsuit_fx.gd); the whoosh
## is the `wind` loop pitched and swelled by the airspeed. WINGSUIT=0 in the environment builds
## none of it (the A/B).

enum State { OFF, GLIDE, SKID }

@export_group("Opening")
## Air needed under him to spread the suit (m).
@export var open_clearance: float = 14.0
## Holding jump this long while falling spreads it (s).
@export var hold_open_seconds: float = 0.3
## Falling at least this fast (m/s) counts as falling for the held jump.
@export var hold_fall_speed: float = 3.0
## Seconds the fabric takes to spread out, and to fold.
@export var spread_seconds: float = 0.35

@export_group("Flight")
## Gravity in the suit (m/s^2). The player's own is a superhero's 57.
@export var glide_gravity: float = 14.0
## Drag: speed lost a second per (m/s)^2, and a flat part (m/s^2).
@export var drag: float = 0.0016
@export var drag_base: float = 0.4
## The attitude with the stick centred, pushed forward and pulled back (degrees, + nose up).
@export var trim_pitch: float = -14.0
@export var dive_pitch: float = -72.0
@export var flare_pitch: float = 26.0
## How fast the nose comes round (degrees a second) and how far he banks (degrees).
@export var pitch_rate: float = 95.0
@export var max_bank: float = 55.0
@export var bank_rate: float = 160.0
## Turn rate for a bank: g * tan(bank) / speed, times this.
@export var turn_gain: float = 1.3
## How hard the wing swings the velocity onto the attitude (radians per metre flown).
@export var align_rate: float = 0.05
## Below this speed (m/s) the wing stalls and the alignment fades out; full at stall_full.
@export var stall_speed: float = 9.0
@export var stall_full: float = 22.0
## Boost in the suit: thrust along the flight (m/s^2).
@export var boost_thrust: float = 32.0
## Fastest he goes (m/s).
@export var max_speed: float = 105.0

@export_group("Landing")
## He flares by himself this close to the ground (m, along a ray down).
@export var flare_height: float = 9.0
## The flare levels the attitude (degrees) and eases the sink to `landing_sink` (m/s) without ever
## climbing, unless he pulls back himself (then he can climb out of it).
@export var flare_level: float = 2.0
@export var landing_sink: float = 2.5
## Touching down slower than this (m/s along the ground) he runs it out; faster he skids.
@export var run_out_speed: float = 26.0
## Speed he keeps out of a run-out (m/s), and how fast a skid sheds speed (m/s^2).
@export var run_out_keep: float = 18.0
@export var skid_decel: float = 34.0
## A skid ends at this speed (m/s) or after this long (s).
@export var skid_end_speed: float = 6.0
@export var skid_max_seconds: float = 1.6
## Hitting a wall faster than this (m/s into it) folds the suit.
@export var wall_fold_speed: float = 22.0

@export_group("Camera")
## Extra camera distance in the suit (m), and field of view added at `fov_speed` m/s.
@export var camera_extra: float = 2.5
@export var fov_extra: float = 16.0
@export var fov_speed: float = 80.0
## The camera swings in behind the flight after this long without a look input (s), this fast.
@export var chase_after: float = 1.2
@export var chase_speed: float = 2.2

@export_group("Sound")
## The whoosh: the `wind` loop, from silent at `whoosh_min` to full at `whoosh_full` m/s.
@export var whoosh_db: float = 0.0
@export var whoosh_min: float = 12.0
@export var whoosh_full: float = 85.0

var state: State = State.OFF
## 0 folded .. 1 spread (the pose and the fabric).
var spread: float = 0.0
## The flight attitude (radians): pitch (+ up), heading (the player's yaw convention), bank (+ right).
var pitch: float = 0.0
var heading: float = 0.0
var bank: float = 0.0
## Height of the ground under him (m, a ray down; INF when out of reach) - what the flare reads.
var ground_gap: float = INF

var _player: Player
var _fx: WingsuitFx
var _whoosh: AudioStreamPlayer3D
var _scrape: AudioStreamPlayer3D
var _hold := 0.0
var _skid_t := 0.0
var _look_quiet := 99.0
var _base_distance := -1.0
var _base_fov := -1.0
var _forced := Vector2.INF
## The physics frame the suit spread on (the press that opened it must not fold it again).
var _opened_frame := -1


## Builds the suit on a player unless WINGSUIT=0. Player._ready() calls it.
static func attach(player: Player) -> Wingsuit:
	if OS.get_environment("WINGSUIT") == "0":
		return null
	var w := Wingsuit.new()
	w.name = "Wingsuit"
	w._player = player
	player.add_child(w)
	return w


func _ready() -> void:
	if _player == null:
		_player = get_parent() as Player
	position = Vector3(0.0, 0.95, 0.0)
	_fx = WingsuitFx.new()
	_fx.name = "WingsuitFx"
	add_child(_fx)
	_whoosh = Sfx.loop_player("wind", -40.0)
	_whoosh.bus = Sfx.BUS_WORLD
	add_child(_whoosh)
	_scrape = Sfx.loop_player("scrape", -8.0)
	add_child(_scrape)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_look_quiet = 0.0


func is_gliding() -> bool:
	return state == State.GLIDE


func is_active() -> bool:
	return state != State.OFF


## Stick input for tests and stills (x roll, y pitch as the move axes give it); INF: the real one.
func force_input(v: Vector2) -> void:
	_forced = v


## One physics tick, from Player._physics_process() after its timers. True: the suit moved the
## player this tick (the rest of the player's tick is skipped).
func tick(delta: float, on_floor: bool) -> bool:
	if _player.vehicle != null or _player.is_downed():
		if state != State.OFF:
			close(false)
		return false
	match state:
		State.GLIDE:
			_glide(delta)
			return true
		State.SKID:
			_skid(delta)
			return true
	spread = move_toward(spread, 0.0, delta / spread_seconds)
	_fx.drive(spread, _player.velocity, delta)
	_quiet(delta)
	if on_floor:
		_hold = 0.0
		return false
	var want := Input.is_action_just_pressed("wingsuit")
	if Input.is_action_pressed("jump") and _player.velocity.y < -hold_fall_speed:
		_hold += delta
		want = want or _hold >= hold_open_seconds
	elif not Input.is_action_pressed("jump"):
		_hold = 0.0
	if want and can_open():
		open()
		_glide(delta)
		return true
	return false


## Enough air under him to spread the suit.
func can_open() -> bool:
	return not _player.is_on_floor() and _gap(open_clearance + 1.0) > open_clearance


## Spreads the suit: the attitude starts on the velocity (a dive if he is falling straight down).
func open() -> void:
	if state == State.GLIDE:
		return
	state = State.GLIDE
	_hold = 0.0
	_opened_frame = Engine.get_physics_frames()
	var v := _player.velocity
	var flat := Vector2(v.x, v.z)
	heading = _player.visual.rotation.y if flat.length() < 2.0 else atan2(-v.x, -v.z)
	pitch = clampf(atan2(v.y, maxf(flat.length(), 0.1)), deg_to_rad(dive_pitch), deg_to_rad(flare_pitch))
	bank = 0.0
	Sfx.play("wings", global_position, 2.0, 0.55)
	var rig: Node = _player.camera_rig
	if _base_distance < 0.0:
		_base_distance = float(rig.get("camera_distance"))
		_base_fov = float(rig.get("camera_fov"))


## Folds it away. `bump`: a wall stopped him (a thud and a shake).
func close(bump: bool) -> void:
	if state == State.OFF:
		return
	state = State.OFF
	_hold = 0.0
	_scrape.stop()
	if _player.avatar:
		_player.avatar.glide = 0.0
	if _player.weapon_manager:
		_player.weapon_manager.visible = _player.vehicle == null
	if bump:
		Sfx.play("thud", global_position, 0.0)
		_player.camera_rig.shake(0.35)
	else:
		Sfx.play("wings", global_position, -2.0, 0.8)
	_restore_camera()


func _glide(delta: float) -> void:
	spread = move_toward(spread, 1.0, delta / spread_seconds)
	var p := _player
	var input := _forced if _forced != Vector2.INF else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var fresh := Engine.get_physics_frames() == _opened_frame
	if not fresh and (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("wingsuit")):
		close(false)
		return
	if Input.is_action_just_pressed("respawn") or p.global_position.y < p.kill_y:
		close(false)
		p.respawn()
		return
	var g_v := p.velocity
	var speed := g_v.length()
	ground_gap = _gap(flare_height * 3.0)
	# The attitude: the stick's dive or flare, and the flare by himself as the ground comes up.
	var want := deg_to_rad(trim_pitch)
	if input.y < 0.0:
		want = lerpf(want, deg_to_rad(dive_pitch), -input.y)
	else:
		want = lerpf(want, deg_to_rad(flare_pitch), input.y)
	var near := clampf(1.0 - (ground_gap - 1.5) / flare_height, 0.0, 1.0)
	want = lerpf(want, maxf(want, deg_to_rad(flare_level)), near)
	pitch = move_toward(pitch, want, deg_to_rad(pitch_rate) * delta)
	bank = move_toward(bank, deg_to_rad(max_bank) * input.x, deg_to_rad(bank_rate) * delta)
	heading = wrapf(heading - glide_gravity * tan(bank) / maxf(speed, 15.0) * turn_gain * delta, -PI, PI)
	var fwd := Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
	# The flight: gravity, the wing swinging the velocity onto the attitude (lift does no work, so
	# the speed is kept), drag, the boost.
	g_v.y -= glide_gravity * delta
	speed = g_v.length()
	if speed > 0.01:
		var lift := align_rate * smoothstep(stall_speed, stall_full, speed) * spread
		var dir := g_v / speed
		var angle := dir.angle_to(fwd)
		var axis := dir.cross(fwd)
		if angle > 1e-4 and axis.length_squared() > 1e-8:
			dir = dir.rotated(axis.normalized(), minf(angle, lift * speed * delta))
		speed = maxf(speed - (drag * speed * speed + drag_base) * delta, 0.0)
		g_v = dir * speed
	if near > 0.0 and input.y < 0.5:
		g_v.y = lerpf(g_v.y, minf(g_v.y * 0.5, -landing_sink), near * minf(1.0, 6.0 * delta))
		g_v.y = minf(g_v.y, -landing_sink * near)
	var boosting := Input.is_action_pressed("boost")
	if boosting:
		g_v += fwd * boost_thrust * delta
	if g_v.length() > max_speed:
		g_v = g_v.normalized() * max_speed
	p.velocity = g_v
	var fall := -g_v.y
	var flat_speed := Vector2(g_v.x, g_v.z).length()
	p.move_and_slide()
	# A wall at speed folds the suit.
	for i in p.get_slide_collision_count():
		var c := p.get_slide_collision(i)
		var n := c.get_normal()
		if n.y < 0.5 and -g_v.dot(n) > wall_fold_speed:
			p.velocity = g_v.bounce(n) * 0.25
			close(true)
			_after_move(delta, true, false)
			return
	if p.is_on_floor():
		_touch_down(fall, flat_speed)
		_after_move(delta, false, false)
		return
	p.visual.rotation.y = lerp_angle(p.visual.rotation.y, heading, 1.0 - exp(-10.0 * delta))
	_after_move(delta, true, boosting)


func _touch_down(fall: float, flat_speed: float) -> void:
	var p := _player
	var at := p.global_position
	if fall >= LandingFX.dust_speed:
		LandingFX.land(p, at, p.get_floor_normal(), fall)
	if flat_speed < run_out_speed:
		# Flared and running: the speed he can carry, the landing's knees (or the roll).
		state = State.OFF
		var flat := Vector3(p.velocity.x, 0.0, p.velocity.z)
		p.velocity = flat.limit_length(run_out_keep)
		if p.avatar:
			p.avatar.glide = 0.0
			p.avatar.landed(maxf(fall, p.avatar.land_dip + 1.0), flat.length())
		if fall < LandingFX.dust_speed:
			Sfx.play("land", at, -4.0)
		if p.weapon_manager:
			p.weapon_manager.visible = true
		_restore_camera()
		return
	# Too fast to run: down on one knee and a hand, skidding (the hero landing, held).
	state = State.SKID
	_skid_t = 0.0
	p.velocity.y = 0.0
	if p.avatar:
		p.avatar.glide = 0.0
		p.avatar.landed(p.avatar.land_hard + 1.0, 0.0)
	_scrape.play()
	_fx.skid_burst(at, Vector3(p.velocity.x, 0.0, p.velocity.z))
	p.camera_rig.shake(0.25)


func _skid(delta: float) -> void:
	var p := _player
	spread = move_toward(spread, 0.0, delta / spread_seconds)
	_skid_t += delta
	var flat := Vector3(p.velocity.x, 0.0, p.velocity.z)
	flat = flat.move_toward(Vector3.ZERO, skid_decel * delta)
	p.velocity = Vector3(flat.x, p.velocity.y - p.rising_gravity() * delta, flat.z)
	p.move_and_slide()
	if p.is_on_floor():
		p.velocity.y = 0.0
	var speed := flat.length()
	_scrape.volume_db = linear_to_db(clampf(speed / 30.0, 0.05, 1.0)) - 6.0 + Sfx.master_volume_db
	_scrape.pitch_scale = lerpf(0.8, 1.15, clampf(speed / 50.0, 0.0, 1.0))
	if p.avatar:
		# Standing still for the clip, so the held landing is not cut by the motion.
		p.avatar.drive(delta, 0.0, true, 0.0, false, Vector3.ZERO)
		p.avatar.hold_gun(null, false, delta)
	if p.weapon_manager:
		p.weapon_manager.visible = false
	_fx.drive(spread, p.velocity, delta)
	_fx.skid_dust(p.global_position, speed / 50.0)
	_quiet(delta)
	if speed < skid_end_speed or _skid_t > skid_max_seconds or not p.is_on_floor():
		state = State.OFF
		_scrape.stop()
		_fx.skid_dust(p.global_position, 0.0)
		if p.weapon_manager:
			p.weapon_manager.visible = true
		_restore_camera()


## The pose, the gun, the effects, the sound and the camera after a gliding tick.
func _after_move(delta: float, airborne: bool, boosting: bool) -> void:
	var p := _player
	var v := p.velocity
	var speed := v.length()
	if p.avatar:
		var a := p.avatar
		a.glide = spread if state == State.GLIDE else 0.0
		a.glide_tilt = PI * 0.5 - pitch
		a.glide_bank = bank
		a.drive(delta, Vector2(v.x, v.z).length(), not airborne, v.y, false, v)
		# The gun comes out of the wing to shoot or aim, and goes back after.
		var raised := Input.is_action_pressed("fire") or Input.is_action_pressed("alt_fire") or p._aim_timer > 0.0
		var gun: Weapon = p.weapon_manager.current if p.weapon_manager else null
		if p.weapon_manager:
			p.weapon_manager.visible = raised or state != State.GLIDE
		a.hold_gun(gun if raised or state != State.GLIDE else null, raised, delta)
	_fx.drive(spread if state == State.GLIDE else 0.0, v, delta, boosting)
	if p._boost_fx:
		p._boost_fx.drive(false, v, p.boost_max_speed)
	if p._boost_sound and p._boost_sound.playing and not boosting:
		p._boost_sound.stop()
	elif p._boost_sound and boosting and not p._boost_sound.playing:
		p._boost_sound.play()
	# The whoosh swells with the airspeed and rises in pitch.
	var k := clampf((speed - whoosh_min) / (whoosh_full - whoosh_min), 0.0, 1.0) * spread
	if k > 0.01:
		if not _whoosh.playing:
			_whoosh.play()
		_whoosh.volume_db = linear_to_db(k) + whoosh_db + Sfx.master_volume_db
		_whoosh.pitch_scale = lerpf(0.7, 1.5, k)
	elif _whoosh.playing:
		_whoosh.stop()
	_camera(delta, speed)


func _quiet(delta: float) -> void:
	if _whoosh.playing:
		_whoosh.volume_db -= 60.0 * delta
		if _whoosh.volume_db < -50.0:
			_whoosh.stop()
	_look_quiet += delta


func _camera(delta: float, speed: float) -> void:
	var rig: Node3D = _player.camera_rig
	if _base_distance < 0.0:
		_base_distance = float(rig.get("camera_distance"))
		_base_fov = float(rig.get("camera_fov"))
	var k := spread if state == State.GLIDE else 0.0
	rig.set("camera_distance", _base_distance + camera_extra * k)
	rig.set("camera_fov", _base_fov + fov_extra * clampf(speed / fov_speed, 0.0, 1.0) * k)
	_look_quiet += delta
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick != Vector2.ZERO:
		_look_quiet = 0.0
	if state == State.GLIDE and _look_quiet > chase_after and not bool(rig.get("lock_active")):
		var fwd := Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, minf(pitch, 0.0) * 0.5 - 0.18) * Vector3.FORWARD
		rig.call("track", rig.call("aim_origin") + fwd * 50.0, chase_speed * k, delta)


func _restore_camera() -> void:
	if _base_distance < 0.0:
		return
	var rig: Node = _player.camera_rig
	rig.set("camera_distance", _base_distance)
	rig.set("camera_fov", _base_fov)


## Air under him, along a ray straight down, up to `reach` metres (INF past it).
func _gap(reach: float) -> float:
	if not is_inside_tree():
		return INF
	var space := get_world_3d().direct_space_state
	var from := _player.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * reach, 1 | 4 | 16)
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q) if space else {}
	return from.y - (hit.position as Vector3).y if hit else INF
