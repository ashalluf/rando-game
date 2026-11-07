extends RefCounted
## Driving controls (drive-controls, wave 9; docs/HANDOFF.md "Driving controls"), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## DriveInput (scripts/vehicles/drive_input.gd): the keyboard diagonal is full throttle AND full
## steer (get_vector normalised it to 71 % each), the pad's triggers are proportional pedals, the
## brake holds the car at a stop for a beat before reverse engages, W while rolling back brakes
## first, reverse fades out at its top speed, the handbrake is its own action (right mouse, Ctrl,
## pad RB) and RB then no longer tunes the radio, the settings' steering knobs reach DriveInput,
## and DRIVE_INPUT=0 (enabled false) is the old input.

var _t: Object
const ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "drive_throttle",
	"drive_brake", "handbrake", "alt_fire", "next_weapon", "radio_next"]


func run(t: Object, _city: Node3D) -> void:
	_t = t
	var was_on := DriveInput.enabled
	var sens := DriveInput.steer_sensitivity
	var centre := DriveInput.auto_centre
	DriveInput.enabled = true
	DriveInput.steer_sensitivity = 1.0
	DriveInput.auto_centre = 1.0
	_actions()
	_release()
	_vector()
	_release()
	_pedals()
	_release()
	_triggers()
	_release()
	await _handbrake_and_radio()
	_release()
	_settings()
	_hooks()
	_release()
	DriveInput.enabled = was_on
	DriveInput.steer_sensitivity = sens
	DriveInput.auto_centre = centre


func _release() -> void:
	for a: String in ACTIONS:
		if InputMap.has_action(a) and Input.is_action_pressed(a):
			Input.action_release(a)


func _events(action: String) -> Array:
	return InputMap.action_get_events(action) if InputMap.has_action(action) else []


func _actions() -> void:
	var thr := false
	for e in _events("drive_throttle"):
		thr = thr or (e is InputEventJoypadMotion and e.axis == JOY_AXIS_TRIGGER_RIGHT)
	var brk := false
	for e in _events("drive_brake"):
		brk = brk or (e is InputEventJoypadMotion and e.axis == JOY_AXIS_TRIGGER_LEFT)
	var mouse := false
	var rb := false
	var key := false
	for e in _events("handbrake"):
		mouse = mouse or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT)
		rb = rb or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_RIGHT_SHOULDER)
		key = key or (e is InputEventKey and e.physical_keycode == KEY_CTRL)
	_t._check(thr and brk and mouse and rb and key,
		"drive controls: the pad's RT / LT are drive_throttle / drive_brake, the handbrake is right mouse, Ctrl and RB (%s %s %s %s %s)" % [thr, brk, mouse, rb, key])
	_t._check(InputMap.action_get_deadzone("drive_throttle") <= 0.1 and InputMap.action_get_deadzone("drive_brake") <= 0.1,
		"drive controls: the trigger pedals' deadzones are small (a trigger is analog)")


func _vector() -> void:
	Input.action_press("move_forward")
	Input.action_press("move_right")
	var v := DriveInput.vector()
	_t._check(is_equal_approx(v.x, 1.0) and is_equal_approx(v.y, -1.0),
		"drive controls: W + D is full steer and full throttle (%s; get_vector made it 0.71 each)" % v)
	DriveInput.enabled = false
	var old := DriveInput.vector()
	DriveInput.enabled = true
	_t._check(absf(old.length() - 1.0) < 0.01 and absf(old.x - 0.7071) < 0.01,
		"drive controls: DRIVE_INPUT=0 gives the old normalised vector (%s)" % old)
	_release()
	Input.action_press("move_left", 0.5)
	var half := DriveInput.steer()
	DriveInput.steer_sensitivity = 1.4
	var gained := DriveInput.steer()
	Input.action_press("move_left", 1.0)
	var key := DriveInput.steer()
	DriveInput.steer_sensitivity = 1.0
	_t._check(absf(half + 0.5) < 0.01 and absf(gained + 0.7) < 0.01 and is_equal_approx(key, -1.0),
		"drive controls: the stick's steer takes the sensitivity as a gain, a key stays full lock (%.2f %.2f %.2f)" % [half, gained, key])


## Drives DriveInput.pedals() for `car` at a held speed for `seconds`; returns the last result.
func _hold(car: Object, speed: float, seconds: float) -> Vector2:
	var r := Vector2.ZERO
	var t := 0.0
	while t < seconds:
		r = DriveInput.pedals(car, speed, 1.0 / 60.0)
		t += 1.0 / 60.0
	return r


func _pedals() -> void:
	var car := RefCounted.new()
	# Rolling forward, S: full brake, no drive.
	Input.action_press("move_back")
	var at_speed := _hold(car, 12.0, 0.2)
	_t._check(at_speed.x == 0.0 and is_equal_approx(at_speed.y, 1.0),
		"drive controls: S at speed is the full brake (%s)" % at_speed)
	# At the stop: held on the brake for a beat, then reverse.
	var early := _hold(car, 0.0, DriveInput.REVERSE_DELAY * 0.5)
	var later := _hold(car, 0.0, DriveInput.REVERSE_DELAY)
	_t._check(early.x == 0.0 and early.y > 0.9 and later.x < -0.9 and DriveInput.in_reverse(car)
			and DriveInput.gear(car, -0.5, "D") == "R",
		"drive controls: a beat on the brake at the stop, then reverse (%s, then %s)" % [early, later])
	# Reverse fades to nothing at its top speed.
	var fast := DriveInput.pedals(car, -DriveInput.REVERSE_TOP_SPEED, 1.0 / 60.0)
	var slow := DriveInput.pedals(car, -4.0, 1.0 / 60.0)
	_t._check(absf(fast.x) < 0.01 and slow.x < -0.6,
		"drive controls: reverse fades out at %.0f m/s (%.2f there, %.2f at 4 m/s)" % [DriveInput.REVERSE_TOP_SPEED, fast.x, slow.x])
	# Rolling back in reverse, W: brake first, then drive once stopped.
	_release()
	Input.action_press("move_forward")
	var back := DriveInput.pedals(car, -6.0, 1.0 / 60.0)
	var stopped := _hold(car, 0.0, DriveInput.FORWARD_DELAY + 0.05)
	_t._check(back.x == 0.0 and back.y > 0.9 and stopped.x > 0.9 and not DriveInput.in_reverse(car),
		"drive controls: W while rolling back brakes first, then drives (%s, then %s)" % [back, stopped])
	# Nothing pressed: coast (-1), gear N standing.
	_release()
	var coast := DriveInput.pedals(car, 0.0, 1.0 / 60.0)
	_t._check(coast == Vector2(0.0, -1.0) and DriveInput.gear(car, 0.0, "D") == "N",
		"drive controls: no pedal coasts and the selector reads N standing (%s)" % coast)
	# Rolling back in DRIVE (down a hill), W: brakes first.
	var car2 := RefCounted.new()
	Input.action_press("move_forward")
	var hill := DriveInput.pedals(car2, -3.0, 1.0 / 60.0)
	_t._check(hill.x == 0.0 and hill.y > 0.9,
		"drive controls: rolling back in drive, W brakes before it drives (%s)" % hill)


func _triggers() -> void:
	var car := RefCounted.new()
	Input.action_press("drive_throttle", 0.5)
	var half := DriveInput.pedals(car, 5.0, 1.0 / 60.0)
	Input.action_press("drive_throttle", 1.0)
	var full := DriveInput.pedals(car, 5.0, 1.0 / 60.0)
	_release()
	Input.action_press("drive_brake", 0.4)
	var light := DriveInput.pedals(car, 15.0, 1.0 / 60.0)
	_t._check(half.x > 0.4 and half.x < 0.6 and is_equal_approx(full.x, 1.0) and light.y > 0.3 and light.y < 0.45 and light.x == 0.0,
		"drive controls: RT and LT are proportional pedals (RT 0.5 -> %.2f, 1.0 -> %.2f; LT 0.4 -> brake %.2f)" % [half.x, full.x, light.y])


func _handbrake_and_radio() -> void:
	# LT presses alt_fire and drive_brake together: the brake pedal, not the handbrake.
	Input.action_press("alt_fire")
	Input.action_press("drive_brake", 1.0)
	var lt_only := DriveInput.handbrake()
	Input.action_release("drive_brake")
	var mouse_alt := DriveInput.handbrake()
	_release()
	# A press is "just pressed" only in its own frame: a frame between the two presses.
	# Read outside a physics frame (CarRadio reads it in _process; a press made inside a physics
	# frame is not "just pressed" until the next one).
	var tree := (_t as Node).get_tree()
	await tree.process_frame
	Input.action_press("next_weapon")
	var wheel := DriveInput.radio_step()
	_release()
	await tree.process_frame
	await tree.process_frame
	Input.action_press("handbrake")
	var hb := DriveInput.handbrake()
	Input.action_press("next_weapon")
	var radio := DriveInput.radio_step()
	_release()
	await tree.process_frame
	DriveInput.enabled = false
	Input.action_press("alt_fire")
	var old := DriveInput.handbrake()
	DriveInput.enabled = true
	_t._check(not lt_only and mouse_alt and hb and radio == 0 and wheel == 1 and old,
		"drive controls: the handbrake is its own action and alt_fire without LT (LT is the brake pedal), RB held does not tune the radio, the wheel does, the A/B is alt_fire (%s %s %s %d %d %s)" % [lt_only, mouse_alt, hb, radio, wheel, old])


func _settings() -> void:
	_t._check(GameSettings.DEFAULTS.get("drive_steer") == 1.0 and GameSettings.DEFAULTS.get("drive_centre") == 1.0,
		"drive controls: the settings carry steering sensitivity and auto-centre, defaults 1 (the game as it was)")
	var keep_s: Variant = GameSettings.get_value("drive_steer")
	var keep_c: Variant = GameSettings.get_value("drive_centre")
	GameSettings.set_value("drive_steer", 1.3)
	GameSettings.set_value("drive_centre", 0.6)
	GameSettings._apply_drive()
	var s := DriveInput.steer_sensitivity
	var c := DriveInput.auto_centre
	var turning_in := DriveInput.steer_rate(0.1, 0.4)
	var returning := DriveInput.steer_rate(0.4, 0.0)
	GameSettings.set_value("drive_steer", keep_s)
	GameSettings.set_value("drive_centre", keep_c)
	GameSettings._apply_drive()
	DriveInput.steer_sensitivity = 1.0
	DriveInput.auto_centre = 1.0
	_t._check(is_equal_approx(s, 1.3) and is_equal_approx(c, 0.6) and is_equal_approx(turning_in, 1.3) and is_equal_approx(returning, 0.6),
		"drive controls: the settings reach DriveInput, sensitivity turning in, auto-centre coming back (%.2f %.2f)" % [turning_in, returning])
	var found := false
	for sec: Array in load("res://scripts/ui/pause_menu.gd").SETTINGS_LAYOUT:
		for row: Array in sec[1]:
			found = found or row[0] == "drive_centre"
	_t._check(found, "drive controls: the settings screen has the steering rows")


func _hooks() -> void:
	var v := FileAccess.get_file_as_string("res://scripts/vehicles/vehicle.gd")
	var m := FileAccess.get_file_as_string("res://scripts/vehicles/motorcycle.gd")
	var b := FileAccess.get_file_as_string("res://scripts/vehicles/boat.gd")
	_t._check(v.contains("DriveInput.pedals(self") and v.contains("DriveInput.handbrake()") and m.contains("DriveInput.pedals(self")
			and b.contains("DriveInput.vector()") and not b.contains("Input.is_action_pressed(\"alt_fire\")"),
		"drive controls: car, motorcycle and boat read DriveInput (pedals, handbrake, per-axis vector)")
