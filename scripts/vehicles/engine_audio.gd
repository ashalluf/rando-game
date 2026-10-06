class_name EngineAudio
extends Node
## Engines for the cars nearest the listener (the engine-audio pass): a voice per car, an engine
## per body type, its revs worked out from the speed and a simulated gearbox.
##
## Profiles (PROFILES, `profile_for()`): a small FOUR (sedans, hatchbacks, crossovers, minivans,
## taxis, vans), a big V8 (pickups, SUVs, the muscle car, police cruisers), a truck DIESEL (box
## trucks, semis, the service trucks, fire engines, ambulances), the city BUS's rear diesel (city
## and school buses), a V12 (the exotics, with a turbo) and a V-twin (MOTO, for the motorcycles to
## come: a car with meta "engine_profile" gets that profile instead). Each has an idle, three
## on-load loops recorded at a low, mid and high rpm and a coasting loop (Sfx eng_<profile>_*,
## built by tools/engine_audio.py). A voice crossfades the on-load ladder by rpm (equal power,
## each loop pitched by rpm / its rpm), fades toward the coasting loop as the throttle lifts, and
## gets louder with load and revs.
##
## Revs (`step_engine()`, pure): gears spread geometrically between the speed first gear tops out
## at and the speed top gear reaches near the redline; upshift by an rpm that rises with the
## throttle, downshift under it, kick down on a floored throttle, a throttle cut and a dip through
## each shift, the clutch slipping in first, the limiter bouncing at the redline, free revs in the
## air (cars fly) or standing with the throttle down. Boost (the player's nitro) floors it.
##
## On top: the turbo whistle spooling with load on turbo profiles (a blow-off valve on the
## exotics when the throttle lifts off boost); the reversing alarm on trucks and buses; a short
## squeal when a TRAFFIC car (kinematic, so DrivingFX's tyre slip never sees it) brakes hard or
## turns hard at speed - DrivingFX keeps the physical cars' squeal; and every car's own horn
## (`horn()`: one take and pitch per car, a deep one on trucks and buses, the air horn on the big
## rigs), which TrafficAI's honks use and the player sounds with `horn` (H / pad d-pad down).
##
## Nearest cars only: up to `voices` traffic voices (2 on the web) within `reach` of the camera,
## plus the player's car always; re-picked every `pick_interval` s. A voiced bus or truck drops
## Ambience's diesel loop (`voiced()`). One instance under the tree root, made by the first Vehicle
## (ensure()), like CarLights. `ENGINE_AUDIO=0` in the environment turns it off (the Vehicle's old
## engine loop plays for the player's car again). `ENGINE_AUDIO_HUD=1` shows the debug panel.

## Off with ENGINE_AUDIO=0.
static var enabled: bool = OS.get_environment("ENGINE_AUDIO") != "0"
## Traffic voices (the player's car is extra).
static var voices: int = 2 if OS.has_feature("web") else 4
## Show the debug panel (the voices' profile, gear, rpm, load and layers).
static var show_hud: bool = OS.get_environment("ENGINE_AUDIO_HUD") == "1"
static var _inst: EngineAudio

## Traffic cars further than this from the camera get no engine (m).
@export var reach: float = 55.0
## Seconds between picks of the nearest cars (real clock).
@export var pick_interval: float = 0.2
## Level of a traffic engine and of the player's own, dB (on top of the loops' normalisation).
@export var traffic_db: float = -9.0
@export var player_db: float = -5.0
## Extra level at full load and at the redline, dB.
@export var load_db: float = 4.0
@export var rev_db: float = 4.0
## Falloff of a traffic engine (AudioStreamPlayer3D unit size, m).
@export var unit_size: float = 7.0
## The turbo whistle at full spool and the reversing alarm, dB.
@export var turbo_db: float = -10.0
@export var beeper_db: float = -8.0
## A traffic car squeals braking harder than this (m/s2) or cornering harder (lateral, m/s2) above
## `squeal_speed` m/s.
@export var squeal_decel: float = 8.5
@export var squeal_lateral: float = 8.5
@export var squeal_speed: float = 9.0
@export var squeal_db: float = -6.0

## rpm: the idle and the three on-load loops' rpm (the coasting loop is at the mid one), as
## tools/engine_audio.py made them. redline, gears; first: speed (m/s) first gear reaches the
## upshift at full throttle; top: speed top gear reaches 92 % of the redline at; db: trim;
## turbo: whistle; bov: blow-off on lifting; beeper: reversing alarm.
const PROFILES := {
	"four": {"rpm": [800, 2200, 3900, 6000], "redline": 6500, "gears": 5, "first": 12.0, "top": 50.0, "db": -1.0},
	"v8": {"rpm": [650, 1800, 3300, 5600], "redline": 6000, "gears": 6, "first": 15.0, "top": 62.0, "db": 0.0},
	"diesel": {"rpm": [650, 1200, 1750, 2300], "redline": 2500, "gears": 8, "first": 3.5, "top": 30.0, "db": 1.0,
		"turbo": true, "beeper": true},
	"bus": {"rpm": [600, 1100, 1550, 2000], "redline": 2200, "gears": 4, "first": 5.0, "top": 26.0, "db": 1.0,
		"turbo": true, "beeper": true},
	"v12": {"rpm": [1000, 3000, 5500, 8400], "redline": 8800, "gears": 7, "first": 18.0, "top": 95.0, "db": 0.0,
		"turbo": true, "bov": true},
	"moto": {"rpm": [1000, 2600, 4600, 7400], "redline": 8000, "gears": 6, "first": 14.0, "top": 65.0, "db": -1.0},
}
const LAYERS := ["idle", "low", "mid", "high", "off"]

var _voices: Array = [] # Voice
var _pick_t: float = 0.0
var _horns: Array[AudioStreamPlayer3D] = []
var _horn_next: int = 0
var _player_horn: AudioStreamPlayer3D
var _player_horn_car: Vehicle
var _hud: Label
## Picks made since load (the checks).
var picks: int = 0


## Makes the one instance, the first time a car enters the tree.
static func ensure(from: Node) -> void:
	if not enabled or (_inst != null and is_instance_valid(_inst)):
		return
	var tree := from.get_tree()
	if tree == null:
		return
	_inst = EngineAudio.new()
	_inst.name = "EngineAudio"
	tree.root.add_child.call_deferred(_inst)


static func instance() -> EngineAudio:
	return _inst if _inst != null and is_instance_valid(_inst) else null


## True when this node voices the player's car (the Vehicle then plays no engine of its own).
static func covers(car: Vehicle) -> bool:
	return enabled and instance() != null and _inst.is_inside_tree() and car != null


## True when `car` has an engine voice now (Ambience drops its diesel loop for it).
static func voiced(car: Node) -> bool:
	var me := instance()
	if me == null:
		return false
	for v: Voice in me._voices:
		if v.car == car:
			return true
	return false


## The engine profile of a car.
static func profile_for(car: Vehicle) -> String:
	if car.has_meta("engine_profile"):
		var p := String(car.get_meta("engine_profile"))
		if PROFILES.has(p):
			return p
	if car.is_in_group("police_car"):
		return "v8"
	return profile_for_type(car.body_type)


static func profile_for_type(t: int) -> String:
	match t:
		Vehicle.BodyType.PICKUP, Vehicle.BodyType.SUV, Vehicle.BodyType.SPORTS:
			return "v8"
		Vehicle.BodyType.SUPER, Vehicle.BodyType.SPIDER, Vehicle.BodyType.HYPER, Vehicle.BodyType.TRACK:
			return "v12"
		Vehicle.BodyType.BUS, Vehicle.BodyType.SCHOOL_BUS:
			return "bus"
		Vehicle.BodyType.BOX_TRUCK, Vehicle.BodyType.SEMI, Vehicle.BodyType.FIRE_ENGINE, Vehicle.BodyType.AMBULANCE, \
				Vehicle.BodyType.GARBAGE_TRUCK, Vehicle.BodyType.STREET_SWEEPER, Vehicle.BodyType.TOW_TRUCK:
			return "diesel"
	return "four"


## rpm per m/s in gear `g` (0-based) of profile `prof`.
static func gear_k(prof: Dictionary, g: int) -> float:
	var red := float(prof.redline)
	var n := int(prof.gears)
	var k1 := red * 0.9 / float(prof.first)
	var kt := red * 0.92 / float(prof.top)
	if n <= 1:
		return k1
	return k1 * pow(kt / k1, float(g) / float(n - 1))


## A fresh engine state.
static func new_state(prof: Dictionary) -> Dictionary:
	return {"rpm": float(prof.rpm[0]), "gear": 0, "shift_t": 0.0, "load": 0.0, "kick_t": 0.0, "limit_t": 0.0,
		"shifts": 0}


## One step of the revs. `speed` m/s (unsigned), `throttle` 0..1 (boost is 1 and `boost` true),
## `free_rev` true when the wheels are off the ground (or neutral). Writes rpm, gear, load into `st`.
static func step_engine(st: Dictionary, prof: Dictionary, speed: float, throttle: float, free_rev: bool,
		boost: bool, dt: float) -> void:
	var idle := float(prof.rpm[0])
	var red := float(prof.redline)
	var n := int(prof.gears)
	var th := clampf(throttle, 0.0, 1.0)
	if boost:
		th = 1.0
	st.shift_t = maxf(float(st.shift_t) - dt, 0.0)
	st.kick_t = maxf(float(st.kick_t) - dt, 0.0)
	var gear := int(st.gear)
	var target := idle
	if free_rev or (speed < 0.6 and th > 0.05):
		# Off the ground or standing on the throttle: the engine revs freely.
		target = idle + th * (red * (1.0 if boost else 0.85) - idle)
		if speed < 0.6:
			gear = 0
	else:
		var up := lerpf(red * 0.42, red * 0.93, th)
		var rpm_g := speed * gear_k(prof, gear)
		if rpm_g > up and gear < n - 1 and float(st.shift_t) <= 0.0:
			gear += 1
			st.shift_t = 0.24
			st.shifts = int(st.shifts) + 1
		elif gear > 0 and speed * gear_k(prof, gear - 1) < maxf(up * 0.62, idle * 1.25):
			gear -= 1
		elif th > 0.92 and gear > 0 and float(st.kick_t) <= 0.0 and speed * gear_k(prof, gear - 1) < red * 0.82:
			gear -= 1 # kick-down
			st.kick_t = 1.2
		rpm_g = speed * gear_k(prof, gear)
		target = maxf(idle, rpm_g)
		if gear == 0:
			# The clutch slips pulling away.
			var slip := 1.0 - clampf(speed / (float(prof.first) * 0.45), 0.0, 1.0)
			target = maxf(target, idle + th * slip * (red * 0.45 - idle))
	st.gear = gear
	var load := th
	if float(st.shift_t) > 0.0:
		load = 0.1 # the throttle cut through a shift
	if free_rev and speed >= 0.6:
		target = minf(target, red * 0.96) # flying: held high, not bouncing off the limiter
	elif target >= red * 0.995 and th > 0.5:
		# The limiter: cuts and catches, a few times a second.
		st.limit_t = float(st.limit_t) + dt
		target = red * (0.95 if fmod(float(st.limit_t), 0.09) < 0.045 else 1.0)
	target = minf(target, red)
	var rpm := float(st.rpm)
	var span := red - idle
	var rate := span * ((2.8 * (0.35 + th)) if target > rpm else 1.8)
	if float(st.shift_t) > 0.0:
		rate = span * 5.0
	rpm = move_toward(rpm, target, rate * dt)
	st.rpm = clampf(rpm, idle * 0.9, red)
	st.load = lerpf(float(st.load), load, 1.0 - exp(-dt * 10.0))


## The five layers' gains (idle, low, mid, high, off) at `rpm` and `load`, equal power.
static func layer_gains(prof: Dictionary, rpm: float, load: float) -> PackedFloat32Array:
	var g := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var pts: Array = prof.rpm
	var i := 0
	while i < 2 and rpm >= float(pts[i + 1]):
		i += 1
	var w := clampf((rpm - float(pts[i])) / (float(pts[i + 1]) - float(pts[i])), 0.0, 1.0)
	g[i] = cos(w * PI * 0.5)
	g[i + 1] = sin(w * PI * 0.5)
	# Coasting: the throttle off above idle.
	var off := (1.0 - clampf(load * 1.6, 0.0, 1.0)) * smoothstep(float(pts[0]) * 1.15, float(pts[0]) * 1.8, rpm)
	for k in 4:
		g[k] *= sqrt(1.0 - off)
	g[4] = sqrt(off)
	return g


## The rpm each layer was recorded at.
static func layer_rpm(prof: Dictionary, layer: int) -> float:
	return float(prof.rpm[2]) if layer == 4 else float(prof.rpm[layer])


func _ready() -> void:
	process_priority = 100
	for i in 3:
		var h := AudioStreamPlayer3D.new()
		h.bus = Sfx.BUS_WORLD
		h.max_distance = 160.0
		h.unit_size = 14.0
		add_child(h)
		_horns.append(h)
	_player_horn = AudioStreamPlayer3D.new()
	_player_horn.bus = Sfx.BUS_WORLD
	_player_horn.unit_size = 14.0
	add_child(_player_horn)
	if show_hud:
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		_hud = Label.new()
		_hud.position = Vector2(16, 16)
		_hud.add_theme_font_size_override("font_size", 15)
		_hud.add_theme_color_override("font_color", Color(1, 1, 1))
		_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_hud.add_theme_constant_override("outline_size", 5)
		layer.add_child(_hud)


func _physics_process(delta: float) -> void:
	for v: Voice in _voices:
		v.sense(delta)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.001)
	var cam := get_viewport().get_camera_3d()
	var mine := _player_car()
	_pick_t -= real
	if _pick_t <= 0.0:
		_pick_t = pick_interval
		_pick(cam, mine)
	for v: Voice in _voices:
		v.tick(delta, self, v.car == mine)
	_tick_player_horn(mine)
	if _hud:
		_hud.text = debug_text()


## Up to `voices` running cars nearest the camera within `reach`, plus the player's car.
func _pick(cam: Camera3D, mine: Vehicle) -> void:
	picks += 1
	var want: Array = []
	if mine != null:
		want.append(mine)
	if cam != null:
		var eye := cam.global_position
		var scored: Array = []
		for node in get_tree().get_nodes_in_group("vehicle"):
			var car := node as Vehicle
			if car == null or car == mine or car is Aircraft or not car.is_inside_tree():
				continue
			if not car.lights_running():
				continue
			var d := car.global_position.distance_to(eye)
			if d > reach:
				continue
			scored.append([d, car])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for i in mini(scored.size(), voices):
			want.append(scored[i][1])
	# Keep the voices whose car is still wanted, free the others, then seat the rest.
	var spare: Array = []
	for v: Voice in _voices:
		if v.car == null or not is_instance_valid(v.car) or not want.has(v.car):
			v.release()
			spare.append(v)
		else:
			want.erase(v.car)
	for car: Vehicle in want:
		var v: Voice
		if not spare.is_empty():
			v = spare.pop_back()
		else:
			v = Voice.new()
			add_child(v)
			_voices.append(v)
		v.assign(car, self)


func _player_car() -> Vehicle:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not ("vehicle" in p):
		return null
	var car: Variant = p.get("vehicle")
	if car == null or not is_instance_valid(car) or car is Aircraft or not (car as Node).is_inside_tree():
		return null
	return car as Vehicle


## The car's own horn: the take and pitch are the car's (a hash of it), so a car always sounds
## like itself; trucks and buses honk deep, the big rigs with the air horn. Returns false when
## there is no horn to play (the caller falls back to its own).
static func horn(car: Vehicle, long: bool = false, at: Variant = null) -> bool:
	var me := instance()
	if me == null or car == null or not car.is_inside_tree():
		return false
	var spec := horn_spec(car, long)
	var got: Array = Sfx.take_at(String(spec[0]), int(spec[1]))
	if got.is_empty():
		return false
	var h := me._horns[me._horn_next]
	me._horn_next = (me._horn_next + 1) % me._horns.size()
	h.stop()
	h.stream = got[0]
	h.volume_db = float(got[1])
	h.pitch_scale = float(spec[2])
	h.global_position = at if at is Vector3 else car.global_position + Vector3.UP * 0.8
	h.play()
	return true


## [Sfx name, take, pitch] of a car's horn.
static func horn_spec(car: Vehicle, long: bool) -> Array:
	var h := absi(hash([car.look_seed, car.get_instance_id() if car.look_seed == 0 else 0, "horn"]))
	var t := car.body_type
	if t in [Vehicle.BodyType.SEMI, Vehicle.BodyType.FIRE_ENGINE, Vehicle.BodyType.GARBAGE_TRUCK]:
		return ["fire_horn", 0, 0.9 + float(h % 11) * 0.01]
	var name := "car_horn_long" if long else "car_horn"
	var takes := 3 if long else 5
	var pitch := 0.9 + float(h % 21) * 0.01
	if profile_for(car) in ["diesel", "bus"]:
		pitch = 0.7 + float(h % 9) * 0.01
	elif profile_for(car) == "v12":
		pitch = 1.04 + float(h % 9) * 0.01
	return [name, (h >> 5) % takes, pitch]


func _tick_player_horn(mine: Vehicle) -> void:
	if mine == null or not InputMap.has_action("horn") or not mine.driver is Player:
		if _player_horn.playing:
			_player_horn.stop()
		return
	if Input.is_action_just_pressed("horn"):
		var spec := horn_spec(mine, true)
		var got: Array = Sfx.take_at(String(spec[0]), int(spec[1]))
		if not got.is_empty():
			_player_horn.stream = got[0]
			_player_horn.volume_db = float(got[1]) + 2.0
			_player_horn.pitch_scale = float(spec[2])
			_player_horn.play()
			_player_horn_car = mine
	elif not Input.is_action_pressed("horn") and _player_horn.playing:
		_player_horn.stop()
	if _player_horn.playing:
		_player_horn.global_position = mine.global_position + Vector3.UP * 0.8 - mine.global_basis.z * 1.5


## The debug panel's text: one line per voice.
func debug_text() -> String:
	var lines := PackedStringArray(["ENGINES  voices %d / %d + player" % [_live_count(), voices]])
	for v: Voice in _voices:
		if v.car == null:
			continue
		var g := layer_gains(PROFILES[v.profile], float(v.st.rpm), float(v.st.load))
		lines.append("%s%-6s %-4s gear %d  %5d rpm  load %.2f  %5.1f m/s  [%s]%s%s%s" % [
			"* " if v.mine else "  ", v.profile, "trf" if v.car.is_traffic() else "phy", int(v.st.gear) + 1,
			int(v.st.rpm), float(v.st.load), v.speed,
			" ".join(Array(g).map(func(x: float) -> String: return "%.2f" % x)),
			"  turbo %.2f" % v.spool if v.spool > 0.02 else "", "  BEEP" if v.beeping else "",
			"  SQUEAL" if v.squealing else ""])
	return "\n".join(lines)


func _live_count() -> int:
	var n := 0
	for v: Voice in _voices:
		if v.car != null:
			n += 1
	return n


## One car's engine: five loop players, the turbo, the beeper and a squeal, following the car.
class Voice extends Node3D:
	var car: Vehicle
	var profile: String = "four"
	var prof: Dictionary
	var st: Dictionary = {}
	var mine := false
	var speed := 0.0
	var spool := 0.0
	var beeping := false
	var squealing := false
	## Why it last squealed, and the hardest braking and cornering it has read (the checks).
	var squeal_cause := ""
	var peak_decel := 0.0
	var peak_lat := 0.0
	var _players: Array[AudioStreamPlayer3D] = []
	var _trims: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0])
	var _turbo: AudioStreamPlayer3D
	var _turbo_trim := 0.0
	var _beeper: AudioStreamPlayer3D
	var _beeper_trim := 0.0
	var _skid: AudioStreamPlayer3D
	var _skid_trim := 0.0
	var _pitch := 1.0
	var _last_pos := Vector3.ZERO
	var _last_speed := 0.0
	var _vel := Vector3.ZERO
	var _lat := 0.0
	var _signed := 0.0
	var _since := 0.0
	var _omega := 0.0
	var _heading := 0.0
	var _have_heading := false
	var _accel := 0.0
	var _squeal := 0.0
	var _was_boost := false

	func _ready() -> void:
		for i in 5:
			var p := AudioStreamPlayer3D.new()
			p.bus = Sfx.BUS_WORLD
			add_child(p)
			_players.append(p)
		_turbo = AudioStreamPlayer3D.new()
		_turbo.bus = Sfx.BUS_WORLD
		add_child(_turbo)
		_beeper = AudioStreamPlayer3D.new()
		_beeper.bus = Sfx.BUS_WORLD
		add_child(_beeper)
		_skid = AudioStreamPlayer3D.new()
		_skid.bus = Sfx.BUS_WORLD
		add_child(_skid)
		var t: Array = Sfx.take("eng_beeper")
		if not t.is_empty():
			_beeper.stream = t[0]
			_beeper_trim = float(t[1])
		t = Sfx.take("skid")
		if not t.is_empty():
			_skid.stream = t[0]
			_skid_trim = float(t[1])

	func assign(c: Vehicle, owner_node: EngineAudio) -> void:
		car = c
		profile = EngineAudio.profile_for(c)
		prof = EngineAudio.PROFILES[profile]
		st = EngineAudio.new_state(prof)
		var h := absi(hash([c.look_seed, c.get_instance_id(), "engine"]))
		_pitch = 0.96 + float(h % 81) * 0.001
		for i in 5:
			var t: Array = Sfx.take("eng_%s_%s" % [profile, EngineAudio.LAYERS[i]])
			var p := _players[i]
			p.stop()
			if t.is_empty():
				p.stream = null
				continue
			p.stream = t[0]
			_trims[i] = float(t[1])
			p.unit_size = owner_node.unit_size
			p.max_distance = owner_node.reach + 15.0
		var tt: Array = Sfx.take("eng_turbo")
		_turbo.stop()
		if prof.get("turbo", false) and not tt.is_empty():
			_turbo.stream = tt[0]
			_turbo_trim = float(tt[1])
		else:
			_turbo.stream = null
		for p: AudioStreamPlayer3D in [_turbo, _beeper, _skid]:
			p.unit_size = owner_node.unit_size
			p.max_distance = owner_node.reach + 15.0
		global_position = c.global_position
		_last_pos = c.global_position
		_last_speed = 0.0
		_vel = Vector3.ZERO
		_lat = 0.0
		_signed = 0.0
		_since = 0.0
		speed = 0.0
		_omega = 0.0
		_have_heading = false
		_accel = 0.0
		spool = 0.0
		_squeal = 0.0
		beeping = false
		squealing = false

	func release() -> void:
		car = null
		for p in _players:
			p.stop()
		for p: AudioStreamPlayer3D in [_turbo, _beeper, _skid]:
			p.stop()

	## Reads the car's motion, once a physics tick (traffic is placed on physics ticks, so a render
	## frame can see it move twice or not at all): speed, its rate, the sideways acceleration.
	func sense(dt: float) -> void:
		if car == null or not is_instance_valid(car) or not car.is_inside_tree():
			return
		var pos := car.global_position
		var fwd := -car.global_basis.z
		var vel := _vel
		_since += dt
		if car.is_traffic() or car.freeze:
			# Kinematic: no velocity of its own. Measured over the time since it last moved (a car
			# placed every few ticks is not stopping and starting); an origin re-centre or a
			# teleport jumps too fast to be driving and is skipped.
			if pos.is_equal_approx(_last_pos):
				if _since < 0.3:
					return
				vel = Vector3.ZERO
			else:
				var step := (pos - _last_pos) / _since
				_last_pos = pos
				if step.length() > 90.0:
					_since = 0.0
					return
				vel = step
		else:
			vel = car.linear_velocity
			_last_pos = pos
		var span := _since
		_since = 0.0
		_signed = vel.dot(fwd)
		speed = absf(_signed)
		var a := (speed - _last_speed) / span
		if absf(a) < 40.0: # a teleport (staging, a re-placed car) is not a stop
			_accel = lerpf(_accel, a, 1.0 - exp(-span * 6.0))
		_last_speed = speed
		# Sideways acceleration = speed x how fast the direction of travel turns, the turning rate
		# smoothed over a quarter second: traffic is placed along lane polylines and its heading
		# steps at every vertex (a raw rate spikes), and a turn taken slowly must not squeal as
		# the car speeds away out of it (the rate has decayed by then, the speed is the current).
		if vel.length() > 1.0:
			var heading := atan2(vel.x, vel.z)
			if _have_heading:
				var w := wrapf(heading - _heading, -PI, PI) / span
				if absf(w) < 6.0:
					_omega = lerpf(_omega, w, 1.0 - exp(-span * 4.0))
			_heading = heading
			_have_heading = true
		else:
			_omega = lerpf(_omega, 0.0, 1.0 - exp(-span * 4.0))
		_vel = vel
		_lat = absf(_omega) * speed

	func tick(delta: float, owner_node: EngineAudio, is_mine: bool) -> void:
		if car == null:
			return
		if not is_instance_valid(car) or not car.is_inside_tree() or car.is_wreck():
			release()
			return
		mine = is_mine
		var dt := maxf(delta, 0.0001)
		global_position = car.global_position
		var signed := _signed
		# Throttle.
		var throttle := 0.0
		var boost := false
		var free_rev := false
		var reversing := false
		if is_mine and car.driver is Player:
			var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			throttle = absf(input.y)
			boost = Input.is_action_pressed("boost")
			free_rev = car.is_airborne()
			reversing = car.light_reverse or (input.y > 0.1 and signed < 0.5)
		elif car.is_traffic():
			throttle = clampf(0.22 + _accel * 0.35, 0.0, 1.0) if speed > 0.4 else 0.0
			reversing = signed < -0.3
		else:
			# Knocked out of the traffic with the driver still in: idling, rolling.
			throttle = 0.0
			reversing = signed < -0.5
		EngineAudio.step_engine(st, prof, speed, throttle, free_rev, boost, dt)
		var rpm := float(st.rpm)
		var load := float(st.load)
		var red := float(prof.redline)
		var idle := float(prof.rpm[0])
		var g := EngineAudio.layer_gains(prof, rpm, load)
		var base := (owner_node.player_db if is_mine else owner_node.traffic_db) + float(prof.db)
		base += owner_node.load_db * load + owner_node.rev_db * clampf((rpm - idle) / (red - idle), 0.0, 1.0)
		for i in 5:
			var p := _players[i]
			if p.stream == null:
				continue
			if g[i] < 0.02:
				if p.playing:
					p.stop()
				continue
			p.volume_db = _trims[i] + base + linear_to_db(g[i])
			p.pitch_scale = clampf(rpm / EngineAudio.layer_rpm(prof, i) * _pitch, 0.4, 2.6)
			if not p.playing:
				p.play(randf() * 1.0)
		# Turbo: spools with load and revs, lags in, dumps on a lift.
		if _turbo.stream != null:
			var want := load * clampf((rpm - idle) / (red - idle) * 1.4, 0.0, 1.0)
			if boost:
				want = 1.0
			var lifted := want < spool - 0.35
			spool = lerpf(spool, want, 1.0 - exp(-dt * (1.6 if want > spool else 7.0)))
			if lifted and spool > 0.55 and prof.get("bov", false):
				Sfx.play("eng_blowoff", car.global_position, -6.0 if is_mine else -12.0)
				spool *= 0.4
			if spool > 0.03:
				_turbo.volume_db = _turbo_trim + owner_node.turbo_db + (4.0 if is_mine else 0.0) + linear_to_db(spool)
				_turbo.pitch_scale = 0.55 + spool * 0.75
				if not _turbo.playing:
					_turbo.play(randf())
			elif _turbo.playing:
				_turbo.stop()
		_was_boost = boost
		# Reversing alarm on trucks and buses.
		beeping = reversing and prof.get("beeper", false)
		if beeping and _beeper.stream != null:
			_beeper.volume_db = _beeper_trim + owner_node.beeper_db
			_beeper.position = Vector3(0.0, 1.5, 0.0) + car.global_basis.z * 3.0
			if not _beeper.playing:
				_beeper.play()
		elif _beeper.playing:
			_beeper.stop()
		# A traffic car braking or cornering hard squeals (DrivingFX has the physical cars).
		var want_sq := 0.0
		if car.is_traffic() and speed > owner_node.squeal_speed:
			var brake_sq := clampf((-_accel - owner_node.squeal_decel) / 4.0, 0.0, 1.0)
			var turn_sq := clampf((_lat - owner_node.squeal_lateral) / 5.0, 0.0, 1.0)
			want_sq = maxf(brake_sq, turn_sq)
			if want_sq > 0.0:
				squeal_cause = "brake" if brake_sq >= turn_sq else "turn"
		peak_decel = maxf(peak_decel, -_accel)
		peak_lat = maxf(peak_lat, _lat)
		_squeal = lerpf(_squeal, want_sq, 1.0 - exp(-dt * (12.0 if want_sq > _squeal else 5.0)))
		squealing = _squeal > 0.05
		if squealing and _skid.stream != null:
			_skid.volume_db = _skid_trim + owner_node.squeal_db + linear_to_db(_squeal)
			_skid.pitch_scale = 0.9 + 0.2 * _squeal
			if not _skid.playing:
				_skid.play(randf())
		elif _skid.playing:
			_skid.stop()
