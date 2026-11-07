class_name DriveInput
extends RefCounted
## The player's driving INPUT (drive-controls, wave 9): what the keyboard, mouse and pad mean for
## the car, motorcycle or boat he drives. Vehicle / Motorcycle / Boat ask it in place of their old
## `Input.get_vector()` lines; it decides nothing about engine, grip or steering geometry (those
## are DriveTrain's / DriveHandling's), only what the player asked for.
##
## * `vector()`: the old get_vector's shape (x steer -1 left .. 1 right, y -1 forward .. 1 back) but
##   per AXIS, never normalised: W + D was (0.71, -0.71) - 71 % throttle and 71 % steering on a
##   keyboard diagonal. The pad's triggers are analog pedals (actions `drive_throttle` /
##   `drive_brake`, RT / LT), added to the stick's; the stick's steering takes the player's
##   `steer_sensitivity` as a gain.
## * `pedals()`: brake-then-reverse with a pause at the stop (`reverse_delay`): holding S brakes to
##   a stand, waits, then reverses - and the other way round, W while rolling backwards brakes
##   first (it used to throttle against the roll). Reverse fades out at `reverse_top_speed` (it
##   had no cap: 48 m/s backwards after eight seconds of S). Returns (drive, brake): drive > 0
##   forward throttle, < 0 reverse; brake 0..1 of the car's brake_force, -1 = coast.
## * `handbrake()`: the `handbrake` action (right mouse, Ctrl, pad RB) - and alt_fire only when it
##   is not the pad's LT, the brake pedal now. With the pad's RB the handbrake, it no longer tunes the radio in a car
##   (`radio_step()`).
## * `steer_rate()`: the steering's rate multiplier - `steer_sensitivity` turning in,
##   `auto_centre` coming back (GameSettings "drive_steer" / "drive_centre").
## * `gear()`: what the selector shows (VehicleHud): R once reverse is engaged, N standing with no
##   pedal, else D.
##
## `DRIVE_INPUT=0` in the environment is the A/B: every caller runs its old lines.

static var enabled: bool = OS.get_environment("DRIVE_INPUT") != "0"
## Multiplier on how fast the wheel turns in, and on the stick's steering gain (settings).
static var steer_sensitivity: float = 1.0
## Multiplier on how fast the wheel comes back to centre once the steering is let go (settings).
static var auto_centre: float = 1.0

## Seconds standing on the brake at a stop before reverse engages (and throttle while rolling
## back before drive does). GTA-like: a beat, not an instant flip and not a long wait.
const REVERSE_DELAY := 0.28
const FORWARD_DELAY := 0.12
## Under this speed (m/s along the nose) the car counts as stopped for the gear change.
const STOP_SPEED := 1.0
## Reverse drive fades to nothing here (m/s, ~58 km/h).
const REVERSE_TOP_SPEED := 16.0
## The pad's triggers under this read as zero (on top of the actions' own small deadzone).
const TRIGGER_DEAD := 0.04
## Both pedals down under this speed: a burnout on the spot (throttle wins, the brake held).
const BURNOUT_SPEED := 4.0

## Per-car state (only the player drives, so one car at a time).
static var _car_id: int = 0
static var _reverse: bool = false
static var _wait: float = 0.0
static var last_throttle: float = 0.0
static var last_brake: float = 0.0


static func _has(action: StringName) -> bool:
	return InputMap.has_action(action)


static func _strength(action: StringName) -> float:
	return Input.get_action_strength(action) if _has(action) else 0.0


## Throttle pedal 0..1: W, the stick forward, RT.
static func throttle() -> float:
	var t := maxf(_strength(&"move_forward"), _trigger(&"drive_throttle"))
	return clampf(t, 0.0, 1.0)


## Brake pedal 0..1: S, the stick back, LT.
static func brake_pedal() -> float:
	var b := maxf(_strength(&"move_back"), _trigger(&"drive_brake"))
	return clampf(b, 0.0, 1.0)


static func _trigger(action: StringName) -> float:
	var v := _strength(action)
	return 0.0 if v < TRIGGER_DEAD else (v - TRIGGER_DEAD) / (1.0 - TRIGGER_DEAD)


## Steering -1 (left) .. 1 (right), per axis. The stick takes the sensitivity as a gain (a key is
## already full lock).
static func steer() -> float:
	var s := _strength(&"move_right") - _strength(&"move_left")
	if absf(s) < 0.999:
		s *= steer_sensitivity
	return clampf(s, -1.0, 1.0)


## The old get_vector's shape (see the header), per axis.
static func vector() -> Vector2:
	if not enabled:
		return Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return Vector2(steer(), brake_pedal() - throttle())


## The handbrake: the `handbrake` action (right mouse, Ctrl, pad RB), or alt_fire unless that is
## the pad's LT (the brake pedal now: alt_fire held with drive_brake down is not the handbrake).
## alt_fire alone when DriveInput is off.
static func handbrake() -> bool:
	if not enabled or not _has(&"handbrake"):
		return Input.is_action_pressed("alt_fire")
	if Input.is_action_pressed("handbrake"):
		return true
	return Input.is_action_pressed("alt_fire") and _strength(&"drive_brake") < TRIGGER_DEAD


## Gear and pedals for `car` this tick: Vector2(drive, brake). drive > 0 throttle forward, < 0
## reverse (both 0..1 before the car's own power, fade and nitro); brake 0..1 of brake_force, or
## -1 to coast (the car's old 1.0 rolling resistance).
static func pedals(car: Object, speed: float, delta: float) -> Vector2:
	var id := car.get_instance_id()
	if id != _car_id:
		_car_id = id
		_reverse = speed < -STOP_SPEED
		_wait = 0.0
	var t := throttle()
	var b := brake_pedal()
	last_throttle = t
	last_brake = b
	# A car shoved forward while in reverse with nothing pressed goes back into drive.
	if _reverse and speed > STOP_SPEED * 3.0 and t <= 0.0:
		_reverse = false
	if not _reverse:
		if t > 0.0 and b > 0.0 and absf(speed) < BURNOUT_SPEED:
			_wait = 0.0
			return Vector2(t, b * 0.6)
		if t > 0.0 and speed < -STOP_SPEED:
			_wait = 0.0
			return Vector2(0.0, t) # rolling back in drive: brake first
		if t > 0.0:
			_wait = 0.0
			return Vector2(t, 0.0)
		if b > 0.0:
			if speed > STOP_SPEED:
				_wait = 0.0
				return Vector2(0.0, b)
			_wait += delta
			if _wait >= REVERSE_DELAY:
				_reverse = true
				_wait = 0.0
			else:
				return Vector2(0.0, b) # held at the stop for a beat
		else:
			_wait = 0.0
			return Vector2(0.0, -1.0)
	# Reverse gear: the brake pedal drives backwards, the throttle brakes then selects drive.
	if t > 0.0:
		if speed < -STOP_SPEED:
			_wait = 0.0
			return Vector2(0.0, t)
		_wait += delta
		if _wait >= FORWARD_DELAY:
			_reverse = false
			_wait = 0.0
			return Vector2(t, 0.0)
		return Vector2(0.0, t)
	_wait = 0.0
	if b > 0.0:
		var fade := clampf(1.0 - maxf(-speed, 0.0) / REVERSE_TOP_SPEED, 0.0, 1.0)
		return Vector2(-b * fade, 0.0)
	return Vector2(0.0, -1.0)


## Is `car` in reverse (the player's selector)?
static func in_reverse(car: Object) -> bool:
	return enabled and car != null and car.get_instance_id() == _car_id and _reverse


## The selector's letter for the HUD: R in reverse, N standing with no pedal, else D. Falls back
## to `fallback` (VehicleHud's speed rule) for a car DriveInput is not driving.
static func gear(car: Object, forward_mps: float, fallback: String) -> String:
	if not enabled or car == null or car.get_instance_id() != _car_id:
		return fallback
	if _reverse:
		return "R"
	if absf(forward_mps) < 0.4 and last_throttle <= 0.0 and last_brake <= 0.0:
		return "N"
	return "D"


## The steering rate multiplier: sensitivity turning in, auto-centre coming back.
static func steer_rate(current: float, target: float) -> float:
	if not enabled:
		return 1.0
	if absf(target) < absf(current) - 0.002 or (target != 0.0 and signf(target) != signf(current) and current != 0.0):
		return auto_centre
	return steer_sensitivity


## The radio's step from the wheel / pad this tick (CarRadio): radio_next / radio_prev, and
## next_weapon / prev_weapon unless that press is the pad's RB, the handbrake now.
static func radio_step() -> int:
	if Input.is_action_just_pressed("radio_next"):
		return 1
	if Input.is_action_just_pressed("radio_prev"):
		return -1
	var hb := enabled and _has(&"handbrake") and Input.is_action_pressed("handbrake")
	if Input.is_action_just_pressed("next_weapon") and not hb:
		return 1
	if Input.is_action_just_pressed("prev_weapon") and not hb:
		return -1
	return 0
