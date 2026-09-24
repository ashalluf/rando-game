class_name Ambience
extends Node
## What the city sounds like: layered beds, sources that come from somewhere, and one-shots
## dropped round the listener, mixed by place, hour and weather (owner, 2026-09-24: "the city
## should SOUND like a real city, AAA-style"). A node in the city scene next to Weather.
##
## Every sound is an Sfx name, so each has a real CC0 recording and a synthesized fallback.
##   - Beds: stereo loops heard everywhere at once - the city's roar by day and far off by night,
##     the near traffic, crowd walla, birds, crickets, wind, rain on the street and on a roof.
##     Non-positional; only their levels move.
##   - Emitters: loops that come FROM somewhere - the freeway, the surf, the airfield, the port.
##     An AudioStreamPlayer3D with Godot's own falloff switched off, kept `emitter_distance` from
##     the listener in the direction of the source, so it pans while the level stays ours.
##   - One-shots: far horns, far sirens, dogs, bus brakes, gulls, coyotes, ship horns and crane
##     clanks, rolled as events per minute and dropped round the listener at a real distance,
##     where the distance filter takes their top off.
##   - The street's own traffic: the nearest moving cars each carry a tyre-roll voice with a
##     Doppler shift, and one that passes close gets a recorded pass-by lined up with the moment
##     it goes past.
##
## Nothing here scans the city. The survey runs every `survey_interval` on the real clock: zone
## and district are MacroMap maths at a few ring points, the freeway comes from its cell index,
## the crowd from one sphere query on the npc layer, the street canyon from nine rays, the cars
## from TrafficManager's own capped lists. Each frame only eases a dozen volumes.
##
## The mix is plain data - `scene` (what the survey found), `levels` (target gains per layer),
## `rates` (one-shots per minute), `gains` (the eased gains) - built by pure functions
## (`scene_at()`, `levels_for()`, `rates_for()`), so the smoke test can check what plays where
## and when under the Dummy audio driver without hearing anything.
##
## Buses (built by Sfx): Ambience carries all of this; it is low-passed when the listener is
## shut in (a car, a covered street between towers) and ducked by a compressor keyed on World,
## so gunfire pushes the city down. World carries every game sound and its reverb grows in the
## street canyons. Game, above both, is muffled while the weapon wheel slows time and for a
## moment after a blast close by.

@export_group("Mix")
## Overall trim on every ambient sound, in dB. Turn the ambience up or down here.
@export var ambience_db: float = -4.0
## Level of each bed and emitter at full gain, in dB on top of `ambience_db` and the sample's own
## loudness trim. These set the balance between layers.
@export var layer_db: Dictionary = {
	"city": -12.0, "city_far": -13.0, "traffic": -15.0, "crowd": -14.0,
	"birds": -15.0, "crickets": -18.0, "wind": -16.0, "gale": -14.0,
	"rain": -10.0, "rain_heavy": -12.0, "rain_roof": -11.0, "rain_car": -9.0,
	"freeway": -9.0, "surf": -9.0, "airport": -11.0, "port": -12.0,
}
## Crossfade time constant for the beds, seconds (real time). Bigger = slower, smoother swells.
@export var fade_seconds: float = 2.4
## Time constant for the fast moves: getting into a car, walking under a deck, ducking.
@export var quick_fade_seconds: float = 0.35
## How often the survey looks round, seconds (real time).
@export var survey_interval: float = 0.5
## How often the traffic voices are handed to the nearest cars, seconds (real time).
@export var traffic_interval: float = 0.15

@export_group("Places")
## How loud a city district is, 0..1, indexed by CityPlan.District
## (DOWNTOWN, MIDTOWN, SUBURBS, INDUSTRIAL, CAMPUS, BEACHTOWN).
@export var district_density: PackedFloat32Array = PackedFloat32Array([1.0, 0.72, 0.28, 0.55, 0.45, 0.5])
## Radii of the two survey rings, metres: the near ring says where you are, the far ring what
## you can hear across the basin (the city from the hills, the sea from the beach towns).
@export var ring_radii: Vector2 = Vector2(110.0, 700.0)
## The surf is heard out to this far from the waterline, metres.
@export var surf_reach: float = 360.0
## The freeway roar reaches this far from the deck, metres.
@export var freeway_reach: float = 420.0
## The airfield's jet rumble reaches this far from the fence, metres.
@export var airport_reach: float = 800.0
## The port's cranes and hum reach this far from the quay, metres.
@export var port_reach: float = 850.0
## Height above the ground where the street starts to fall away and the wind takes over, and
## where it is gone, metres.
@export var altitude_range: Vector2 = Vector2(30.0, 260.0)
## Emitters are parked this far from the listener in the direction of their source, metres.
@export var emitter_distance: float = 14.0

@export_group("Street")
## Walls closer than this count toward the street canyon (reverb), metres.
@export var canyon_reach: float = 55.0
## A roof or deck closer than this overhead counts as cover, metres.
@export var cover_reach: float = 40.0
## Pedestrians within this radius make the crowd walla, metres.
@export var crowd_radius: float = 28.0
## This many people within `crowd_radius` is a full crowd.
@export var crowd_full: int = 12
## Traffic cars within this distance get a tyre-roll voice, metres.
@export var car_hear_distance: float = 45.0
## A car passing closer than this gets a recorded pass-by, metres.
@export var pass_distance: float = 7.5
## ...if it is doing at least this, m/s.
@export var pass_min_speed: float = 8.0
## Where the loudest instant of every car_pass take sits, seconds from its start (the clips are
## cut so it is the same for all of them).
@export var pass_peak_seconds: float = 1.2

@export_group("Enclosure")
## Ambience low-pass cutoff inside a car, Hz.
@export var car_cutoff_hz: float = 1300.0
## Ambience low-pass cutoff when covered AND walled in (under a deck between towers), Hz.
@export var indoor_cutoff_hz: float = 2600.0
## World reverb wet level in the open, and extra for a full street canyon and for full cover.
@export var reverb_wet: Vector3 = Vector3(0.04, 0.22, 0.18)

@export_group("Ducking")
## Game bus low-pass while the weapon wheel (or any slow motion) holds time, Hz.
@export var slow_cutoff_hz: float = 1100.0
## How far the ambience drops while the wheel is open, dB.
@export var slow_duck_db: float = -5.0
## A blast within this distance ducks the ambience, metres; the duck scales with closeness.
@export var blast_duck_radius: float = 160.0
## Deepest ambience duck from a blast at the listener, dB.
@export var blast_duck_db: float = -14.0
## A blast within this distance also muffles everything for a moment (ringing ears), metres.
@export var concussion_radius: float = 35.0
## Game bus low-pass right after a blast at point-blank, Hz.
@export var concussion_cutoff_hz: float = 650.0
## How long a blast's duck and muffle take to recover, seconds (real time).
@export var blast_recover_seconds: float = 2.2

## Beds and emitters: the Sfx sound each plays, and whether it comes from a place.
const LAYERS := {
	"city": {"sound": "amb_city"},
	"city_far": {"sound": "amb_city_far"},
	"traffic": {"sound": "ambience_city"},
	"crowd": {"sound": "amb_crowd"},
	"birds": {"sound": "amb_birds"},
	"crickets": {"sound": "amb_crickets"},
	"wind": {"sound": "wind"},
	"gale": {"sound": "amb_gale"},
	"rain": {"sound": "rain"},
	"rain_heavy": {"sound": "amb_rain_heavy"},
	"rain_roof": {"sound": "amb_rain_roof"},
	"rain_car": {"sound": "amb_rain_car"},
	"freeway": {"sound": "amb_freeway", "emitter": true, "pan": 0.75},
	"surf": {"sound": "amb_surf", "emitter": true, "pan": 0.55},
	"airport": {"sound": "amb_airport", "emitter": true, "pan": 0.7},
	"port": {"sound": "amb_port", "emitter": true, "pan": 0.7},
}

## One-shots: Sfx sound, distance from the listener (m), height above it (m), falloff scale
## (Godot's unit_size: bigger carries further), level (dB) and pitch spread.
const ONE_SHOTS := {
	"horn": {"sound": "horn_far", "dist": Vector2(35.0, 170.0), "up": Vector2(0.0, 2.0), "unit": 22.0, "db": 0.0, "pitch": 0.06},
	"siren": {"sound": "siren_far", "dist": Vector2(260.0, 700.0), "up": Vector2(0.0, 12.0), "unit": 110.0, "db": 0.0, "pitch": 0.04},
	"dog": {"sound": "dog", "dist": Vector2(50.0, 240.0), "up": Vector2(0.0, 1.0), "unit": 26.0, "db": 0.0, "pitch": 0.08},
	"bus": {"sound": "bus_hiss", "dist": Vector2(25.0, 90.0), "up": Vector2(0.0, 1.0), "unit": 16.0, "db": -2.0, "pitch": 0.05},
	"gull": {"sound": "gull", "dist": Vector2(18.0, 110.0), "up": Vector2(8.0, 35.0), "unit": 20.0, "db": 0.0, "pitch": 0.1},
	"coyote": {"sound": "coyote", "dist": Vector2(180.0, 650.0), "up": Vector2(0.0, 20.0), "unit": 90.0, "db": 0.0, "pitch": 0.06},
	"ship_horn": {"sound": "ship_horn", "dist": Vector2(350.0, 1200.0), "up": Vector2(0.0, 15.0), "unit": 280.0, "db": 2.0, "pitch": 0.03},
	"crane": {"sound": "crane", "dist": Vector2(120.0, 480.0), "up": Vector2(5.0, 30.0), "unit": 60.0, "db": 0.0, "pitch": 0.05},
}

const ONE_SHOT_VOICES := 5
const TRAFFIC_VOICES := 3
const PASS_VOICES := 2
const SOUND_SPEED := 343.0
const WORLD_LAYER := 1
const NPC_LAYER := 8

## What the last survey found (see scene_at()), the target gains it asked for, the one-shot rates
## (per minute) and the eased gains the players are at now.
var scene: Dictionary = {}
var levels: Dictionary = {}
var rates: Dictionary = {}
var gains: Dictionary = {}
## Set true to stop the survey (the smoke test drives the mix itself).
var frozen: bool = false
## Game-bus muffle and ambience enclosure cutoffs in use, Hz (20000 = open), and the duck, dB.
var game_cutoff: float = 20000.0
var ambience_cutoff: float = 20000.0
var duck_db: float = 0.0
## One-shots fired since load, per kind (for the test and the HUD).
var fired: Dictionary = {}

var _beds: Dictionary = {}        # layer -> AudioStreamPlayer or AudioStreamPlayer3D
var _trim: Dictionary = {}        # layer -> dB trim of the take it plays
var _shots: Array[AudioStreamPlayer3D] = []
var _next_shot: int = 0
var _cars: Array[AudioStreamPlayer3D] = []
var _car_of: Array = []           # per traffic voice: the Vehicle it follows, or null
var _car_trim: float = 0.0
var _passes: Array[AudioStreamPlayer3D] = []
var _pass_of: Array = []
var _passed: Dictionary = {}      # car instance id -> msec it last got a pass-by
var _car_prev: Dictionary = {}    # car instance id -> [local position, msec]
var _car_vel: Dictionary = {}     # car instance id -> velocity (m/s, local)
var _eye_prev := Vector3.INF
var _eye_vel := Vector3.ZERO
var _offset_seen := Vector3.ZERO
var _last_us: int = 0
var _survey_left: float = 0.0
var _traffic_left: float = 0.0
var _blast_seen: int = 0
var _blast: float = 0.0           # 1 right after a blast, easing to 0
var _blast_depth: float = 0.0     # how deep that blast's duck is, 0..1
var _concussion: float = 0.0      # how hard that blast muffles, 0..1
var _slow: float = 0.0
var _enclose: float = 20000.0
var _verb_wet: float = 0.04
var _verb_room: float = 0.4
var _verb_delay: float = 30.0
var _bus_sent := Vector4(-1.0, -1.0, -1.0, -1.0) # what the buses were last told
var _rng := RandomNumberGenerator.new()
var _streamer: Node
var _daynight: Node
var _weather: Node
var _traffic: Node
var _player: Node3D
var _ray := PhysicsRayQueryParameters3D.new()
var _sphere := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	_rng.seed = 9091
	_streamer = get_parent()
	_daynight = get_parent().get_node_or_null("DayNight")
	_weather = get_parent().get_node_or_null("Weather")
	_ray.collision_mask = WORLD_LAYER
	var ball := SphereShape3D.new()
	ball.radius = crowd_radius
	_sphere.shape = ball
	_sphere.collision_mask = NPC_LAYER
	_sphere.collide_with_areas = false
	for layer: String in LAYERS:
		gains[layer] = 0.0
		levels[layer] = 0.0
	for kind: String in ONE_SHOTS:
		fired[kind] = 0
		rates[kind] = 0.0
	_build_voices()
	_blast_seen = Explosion.blast_count
	_last_us = Time.get_ticks_usec()


func _build_voices() -> void:
	for layer: String in LAYERS:
		var info: Dictionary = LAYERS[layer]
		var sound: String = info.sound
		var got: Array = Sfx.take(sound)
		var p: Node
		if info.get("emitter", false):
			var p3 := AudioStreamPlayer3D.new()
			p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
			p3.attenuation_filter_cutoff_hz = 20500.0 # off: the level and the air are ours
			p3.panning_strength = float(info.get("pan", 0.7))
			p = p3
		else:
			p = AudioStreamPlayer.new()
		p.name = "Bed_" + layer
		p.set("bus", Sfx.BUS_AMBIENCE)
		if not got.is_empty():
			p.set("stream", got[0])
			_trim[layer] = got[1]
		add_child(p)
		_beds[layer] = p
	for i in ONE_SHOT_VOICES:
		var v := AudioStreamPlayer3D.new()
		v.name = "Shot_%d" % i
		v.bus = Sfx.BUS_AMBIENCE
		v.max_distance = 2500.0
		v.attenuation_filter_cutoff_hz = 4500.0
		v.attenuation_filter_db = -30.0
		add_child(v)
		_shots.append(v)
	var roll: Array = Sfx.take("car_roll")
	for i in TRAFFIC_VOICES:
		var v := AudioStreamPlayer3D.new()
		v.name = "Car_%d" % i
		v.bus = Sfx.BUS_WORLD
		v.unit_size = 5.0
		v.max_distance = car_hear_distance * 1.3
		if not roll.is_empty():
			v.stream = roll[0]
			_car_trim = roll[1]
		add_child(v)
		_cars.append(v)
		_car_of.append(null)
	for i in PASS_VOICES:
		var v := AudioStreamPlayer3D.new()
		v.name = "Pass_%d" % i
		v.bus = Sfx.BUS_WORLD
		v.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		v.attenuation_filter_cutoff_hz = 20500.0
		add_child(v)
		_passes.append(v)
		_pass_of.append(null)


## The buses outlive this node (Sfx is an autoload): a seed rebuild in the middle of a blast's
## muffle, or from inside a car, must not leave the next scene low-passed.
func _exit_tree() -> void:
	Sfx.set_filter(Sfx.BUS_AMBIENCE, 20000.0)
	Sfx.set_filter(Sfx.BUS_GAME, 20000.0)
	Sfx.set_reverb(reverb_wet.x, 0.4, 30.0)


func _process(_delta: float) -> void:
	# Everything runs on the real clock: the weapon wheel scales the process delta down to a
	# quarter, and a duck that recovered at a quarter speed would sit on the mix for ten seconds.
	var now := Time.get_ticks_usec()
	var dt := clampf(float(now - _last_us) / 1000000.0, 0.0, 0.25)
	_last_us = now
	var eye := _listener()
	_track_listener(eye, dt)
	if not frozen:
		_survey_left -= dt
		if _survey_left <= 0.0:
			_survey_left = survey_interval
			_survey(eye)
		_traffic_left -= dt
		if _traffic_left <= 0.0:
			_traffic_left = traffic_interval
			_assign_traffic(eye)
	_poll_blasts(eye)
	step(dt)
	_place_emitters(eye)
	_follow_traffic(eye, dt)


## Advances the mix by `dt` real seconds: eases every gain toward its target, applies the ducks
## and the bus effects. The smoke test calls it directly.
func step(dt: float) -> void:
	var slow_target := 1.0 if _slowed() else 0.0
	_slow = _approach(_slow, slow_target, dt, quick_fade_seconds)
	_blast = maxf(0.0, _blast - dt / maxf(blast_recover_seconds, 0.05))
	duck_db = slow_duck_db * _slow + blast_duck_db * _blast_depth * _blast * _blast
	var master := ambience_db + duck_db
	for layer: String in LAYERS:
		var target: float = levels.get(layer, 0.0)
		var tau := fade_seconds
		if layer == "rain_roof" or layer == "rain_car" or layer == "rain":
			tau = quick_fade_seconds * 2.0 # stepping under a roof is quick
		var g: float = _approach(gains[layer], target, dt, tau)
		gains[layer] = g
		var p: Node = _beds[layer]
		if p.get("stream") == null:
			continue
		var playing: bool = p.get("playing")
		if g < 0.002:
			if playing:
				p.call("stop")
			continue
		p.set("volume_db", master + float(layer_db.get(layer, -12.0)) + float(_trim.get(layer, 0.0)) + linear_to_db(g))
		if not playing:
			# From a random point, so two loops that start together never line up.
			var s: AudioStream = p.get("stream")
			p.call("play", _rng.randf_range(0.0, maxf(s.get_length() - 0.5, 0.0)))
	_apply_buses(dt)


## Target cutoffs and reverb from the last survey, eased, pushed to the buses Sfx built.
func _apply_buses(dt: float) -> void:
	var s := scene
	var in_car: float = s.get("in_car", 0.0)
	var cover: float = s.get("cover", 0.0)
	var canyon: float = s.get("canyon", 0.0)
	var shut := maxf(in_car, cover * canyon)
	var enclose_target := 20000.0
	if shut > 0.01:
		var inner := car_cutoff_hz if in_car > 0.5 else indoor_cutoff_hz
		enclose_target = exp(lerpf(log(20000.0), log(inner), shut))
	_enclose = exp(_approach(log(_enclose), log(enclose_target), dt, quick_fade_seconds))
	ambience_cutoff = _enclose
	var game_target := 20000.0
	if _slow > 0.001:
		game_target = exp(lerpf(log(20000.0), log(slow_cutoff_hz), _slow))
	if _concussion * _blast > 0.001:
		var c := exp(lerpf(log(20000.0), log(concussion_cutoff_hz), _concussion * _blast * _blast))
		game_target = minf(game_target, c)
	game_cutoff = game_target
	_verb_wet = _approach(_verb_wet, reverb_wet.x + reverb_wet.y * canyon + reverb_wet.z * cover, dt, fade_seconds)
	_verb_room = _approach(_verb_room, 0.35 + 0.45 * maxf(canyon, cover), dt, fade_seconds)
	_verb_delay = _approach(_verb_delay, 22.0 + 60.0 * canyon, dt, fade_seconds)
	# Only when something moved audibly (1 % on a cutoff, a thousandth of wet or room): most frames
	# nothing does.
	var moved := absf(ambience_cutoff - _bus_sent.x) > _bus_sent.x * 0.01 or absf(game_cutoff - _bus_sent.y) > _bus_sent.y * 0.01
	moved = moved or absf(_verb_wet - _bus_sent.z) > 0.001 or absf(_verb_room - _bus_sent.w) > 0.001
	# ...and always when a filter crosses the point where Sfx switches it off.
	moved = moved or (ambience_cutoff < 19000.0) != (_bus_sent.x < 19000.0) or (game_cutoff < 19000.0) != (_bus_sent.y < 19000.0)
	if moved:
		_bus_sent = Vector4(ambience_cutoff, game_cutoff, _verb_wet, _verb_room)
		Sfx.set_filter(Sfx.BUS_AMBIENCE, ambience_cutoff)
		Sfx.set_filter(Sfx.BUS_GAME, game_cutoff)
		Sfx.set_reverb(_verb_wet, _verb_room, _verb_delay)


## Exponential approach with time constant `tau`, frame-rate independent.
static func _approach(from: float, to: float, dt: float, tau: float) -> float:
	return lerpf(from, to, 1.0 - exp(-dt / maxf(tau, 0.001)))


# --- The survey ---------------------------------------------------------------------------------

func _survey(eye: Vector3) -> void:
	var plan := _plan()
	if plan == null or plan.macro == null:
		return
	var w := WorldState.to_world(eye)
	scene = scene_at(w, plan.macro)
	_probe(eye, scene)
	var hour: float = _daynight.hour if _daynight else 12.0
	var night: float = _daynight.night_factor if _daynight else 0.0
	var wx := weather_now()
	levels = levels_for(scene, hour, night, wx)
	rates = rates_for(scene, hour, night, wx)
	_roll_one_shots(eye, w)


## The weather as the mix sees it: rain 0..1, storm 0..1, wave scale.
func weather_now() -> Dictionary:
	if _weather == null:
		return {"rain": 0.0, "storm": 0.0, "waves": 1.0}
	var storm := 0.0
	if int(_weather.get("state")) == 3: # Weather.State.STORM
		storm = float(_weather.get("blend"))
	return {"rain": float(_weather.get("rain_level")), "storm": storm, "waves": float(_weather.get("wave_scale"))}


## Where a world position is, as far as sound goes. Pure MacroMap maths plus the freeway's cell
## index; the physics parts (canyon, cover, crowd, cars, being in a car) start at zero and are
## filled in by _probe() for the real listener.
func scene_at(w: Vector3, macro: MacroMap) -> Dictionary:
	var here := Vector2(w.x, w.z)
	var zones := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var urban := 0.0
	var green := 0.0
	var far_city := 0.0
	var total := 0.0
	# The waterline, seen from land: the nearest sea sample. Seen from the sea: the nearest land
	# sample. Either way the surf is where the two meet, not wherever there is water.
	var at_sea := macro.zone_at(here) == MacroMap.Zone.OCEAN
	var in_harbor := macro.harbor_rect.has_point(here)
	var water_near := INF
	var water_at := Vector2.INF
	# Centre (weight 3), a near ring of 6 (1 each) and a far ring of 8 that only says what is in
	# earshot across the basin.
	var points: Array = [[here, 3.0, true]]
	for i in 6:
		var a := TAU * float(i) / 6.0
		points.append([here + Vector2(cos(a), sin(a)) * ring_radii.x, 1.0, true])
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		points.append([here + Vector2(cos(a), sin(a)) * ring_radii.y, 1.0, false])
	var far_n := 0.0
	for pt: Array in points:
		var p: Vector2 = pt[0]
		var wt: float = pt[1]
		var zone := macro.zone_at(p)
		var sea := zone == MacroMap.Zone.OCEAN and not macro.harbor_rect.has_point(p)
		if sea != at_sea and p != here:
			var d := p.distance_to(here)
			if d < water_near:
				water_near = d
				water_at = p
		if not pt[2]:
			far_n += 1.0
			if zone == MacroMap.Zone.CITY:
				far_city += 1.0
			continue
		zones[zone] += wt
		total += wt
		if zone == MacroMap.Zone.CITY:
			var dens := _density(macro.district_at(p))
			urban += wt * dens
			green += wt * (1.0 - dens) * 0.8
		elif zone == MacroMap.Zone.HILLS:
			green += wt
		elif zone == MacroMap.Zone.BEACH:
			green += wt * 0.2
	for i in zones.size():
		zones[i] /= total
	# The main coast is maths, from either side of it; the bay's shore is whichever ring point
	# crossed the waterline. The harbour is the port's, and has no surf.
	var coast := Vector2(macro.coast_x(here.y), here.y)
	var coast_d := absf(here.x - coast.x)
	if coast_d < water_near:
		water_near = coast_d
		water_at = coast
	if in_harbor:
		water_at = Vector2.INF
	var ground := maxf(macro.height_at(here), 0.0)
	var height := w.y - ground
	var s := {
		"zones": zones,
		"urban": urban / total,
		"green": clampf(green / total, 0.0, 1.0),
		"far_city": far_city / maxf(far_n, 1.0),
		"height": height,
		"altitude": smoothstep(altitude_range.x, altitude_range.y, height),
		"ridge": smoothstep(80.0, 350.0, macro.raw_height_at(here)),
		"canyon": 0.0, "cover": 0.0, "in_car": 0.0, "crowd": 0.0, "panic": 0.0, "cars": 0,
	}
	# Emitters: how loud and which way. Levels fall off smoothly with distance to the source.
	s["surf"] = smoothstep(surf_reach, 25.0, water_near + maxf(height, 0.0) * 0.5) if water_at != Vector2.INF else 0.0
	s["surf_at"] = Vector3(water_at.x, 0.0, water_at.y) if water_at != Vector2.INF else Vector3.INF
	var fw := _freeway_near(macro, here, w.y)
	s["freeway"] = smoothstep(freeway_reach, 22.0, fw[0])
	s["freeway_at"] = fw[1]
	var air := _rect_near(macro.airport_rect, here)
	s["airport"] = smoothstep(airport_reach, 150.0, air.distance_to(here) + maxf(height, 0.0) * 0.3)
	s["airport_at"] = Vector3(air.x, 0.0, air.y)
	var port_rect := macro.port_rect.merge(macro.harbor_rect)
	var port := _rect_near(port_rect, here)
	s["port"] = smoothstep(port_reach, 90.0, port.distance_to(here) + maxf(height, 0.0) * 0.3)
	s["port_at"] = Vector3(port.x, 0.0, port.y)
	return s


func _density(d: int) -> float:
	return district_density[d] if d >= 0 and d < district_density.size() else 0.4


## Nearest deck point within reach: [3D distance, world point]. Uses the freeway's own cell index.
func _freeway_near(macro: MacroMap, here: Vector2, y: float) -> Array:
	var fw: Freeway = macro.freeway
	if fw == null:
		return [INF, Vector3.INF]
	var best := INF
	var at := Vector3.INF
	for seg: Dictionary in fw.segments_in(Rect2(here - Vector2.ONE * freeway_reach, Vector2.ONE * freeway_reach * 2.0)):
		var a: Vector2 = seg.a
		var ab: Vector2 = seg.b - a
		var f := clampf((here - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var p := a + ab * f
		var deck := lerpf(float(seg.ha), float(seg.hb), f)
		var d := Vector3(p.x - here.x, (deck - y) * 0.6, p.y - here.y).length()
		if d < best:
			best = d
			at = Vector3(p.x, deck, p.y)
	return [best, at]


static func _rect_near(r: Rect2, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


## The parts of the scene only physics can answer, for the real listener: the street canyon and
## cover (nine rays), the crowd (one sphere query), the cars round it, and whether it is in a car.
func _probe(eye: Vector3, s: Dictionary) -> void:
	var space := _space()
	if space:
		var walls := 0.0
		_ray.from = eye
		for i in 8:
			var a := TAU * float(i) / 8.0
			_ray.to = eye + Vector3(cos(a), 0.0, sin(a)) * canyon_reach
			var hit := space.intersect_ray(_ray)
			if not hit.is_empty():
				walls += 1.0 - eye.distance_to(hit.position) / canyon_reach
		_ray.to = eye + Vector3.UP * cover_reach
		var up := space.intersect_ray(_ray)
		if not up.is_empty():
			s["cover"] = clampf(1.2 - eye.distance_to(up.position) / cover_reach, 0.0, 1.0)
		# Walls alone are any street; tall walls are downtown, which the density says.
		# A hillside across the valley is not a street of towers, so only built-up ground counts.
		var z: PackedFloat32Array = s.zones
		var built := clampf(z[MacroMap.Zone.CITY] + z[MacroMap.Zone.PORT] * 0.6 + z[MacroMap.Zone.AIRPORT] * 0.4, 0.0, 1.0)
		s["canyon"] = clampf(walls / 8.0 * 1.6, 0.0, 1.0) * lerpf(0.55, 1.0, float(s.urban)) * built * (1.0 - float(s.altitude))
		_sphere.transform = Transform3D(Basis(), eye)
		var people := 0
		var scared := 0
		for r: Dictionary in space.intersect_shape(_sphere, 32):
			var c: Object = r.get("collider")
			if c is Pedestrian:
				people += 1
				if float(c.get("_panic_left")) > 0.0:
					scared += 1
		s["crowd"] = clampf(float(people) / float(maxi(crowd_full, 1)), 0.0, 1.0)
		s["panic"] = float(scared) / float(maxi(people, 1))
	var near := 0
	for car in _traffic_cars():
		if (car as Node3D).global_position.distance_to(eye) < 60.0:
			near += 1
	s["cars"] = near
	var player := _get_player()
	if player and player.get("vehicle") != null:
		s["in_car"] = 1.0


## Target gain per layer for a scene, hour, night factor (DayNight.night_factor) and weather.
## Pure, so the smoke test can ask "what plays downtown at noon" without a listener.
func levels_for(s: Dictionary, hour: float, night: float, wx: Dictionary) -> Dictionary:
	var z: PackedFloat32Array = s.zones
	var day := 1.0 - night
	var alt: float = s.altitude
	var ground := 1.0 - alt # the street falls away as you climb
	var urban: float = s.urban
	var far_city: float = s.far_city
	var green: float = s.green
	var shelter := maxf(float(s.cover), float(s.in_car)) # a roof or a car between you and the sky
	var rain: float = wx.get("rain", 0.0)
	var storm: float = wx.get("storm", 0.0)
	var out := {}
	# The city's roar: loud in the middle by day; at night the far, thin traffic carries.
	out["city"] = urban * lerpf(0.45, 1.0, day) * lerpf(1.0, 0.3, alt)
	out["city_far"] = clampf(maxf(far_city * 0.75, urban * lerpf(0.3, 0.85, night)) + alt * far_city * 0.4, 0.0, 1.0) * (1.0 - z[MacroMap.Zone.OCEAN] * 0.5)
	out["traffic"] = clampf(float(s.cars) / 6.0 * lerpf(0.6, 1.0, day) + urban * 0.25, 0.0, 1.0) * ground
	out["crowd"] = float(s.crowd) * (1.0 - float(s.panic) * 0.85) * ground
	var chorus := birdsong(hour)
	out["birds"] = chorus * clampf(green + z[MacroMap.Zone.BEACH] * 0.3, 0.0, 1.0) * (1.0 - rain * 0.9) * ground
	out["crickets"] = night * clampf(green * 1.1 + z[MacroMap.Zone.BEACH] * 0.3, 0.0, 1.0) * (1.0 - rain) * (1.0 - storm) * ground
	var wind := 0.16 + z[MacroMap.Zone.HILLS] * 0.3 + z[MacroMap.Zone.BEACH] * 0.25 + z[MacroMap.Zone.OCEAN] * 0.3
	wind += float(s.ridge) * 0.3 + alt * 0.5 + rain * 0.3
	out["wind"] = clampf(wind, 0.0, 1.0) * (1.0 - shelter * 0.6)
	out["gale"] = clampf(storm * 0.9 + alt * 0.6 + float(s.ridge) * 0.4 - 0.15, 0.0, 1.0) * (1.0 - shelter * 0.7)
	out["rain"] = rain * (1.0 - shelter * 0.75)
	out["rain_heavy"] = clampf((rain - 0.45) / 0.55, 0.0, 1.0) * (1.0 - shelter * 0.6)
	out["rain_roof"] = rain * float(s.cover) * (1.0 - float(s.in_car))
	out["rain_car"] = rain * float(s.in_car)
	out["freeway"] = float(s.freeway) * lerpf(0.55, 1.0, day)
	out["surf"] = float(s.surf) * clampf(0.75 + 0.08 * float(wx.get("waves", 1.0)), 0.75, 1.4)
	out["airport"] = float(s.airport) * lerpf(0.6, 1.0, day)
	out["port"] = float(s.port)
	return out


## One-shots per minute for a scene, hour and weather.
func rates_for(s: Dictionary, _hour: float, night: float, wx: Dictionary) -> Dictionary:
	var z: PackedFloat32Array = s.zones
	var day := 1.0 - night
	var ground := 1.0 - float(s.altitude)
	var urban: float = s.urban
	var rain: float = wx.get("rain", 0.0)
	var storm: float = wx.get("storm", 0.0)
	var suburb := float(s.green) * z[MacroMap.Zone.CITY]
	return {
		"horn": urban * lerpf(1.5, 6.0, day) * ground * (1.0 - rain * 0.3),
		"siren": (urban * 0.5 + float(s.far_city) * 0.3) * lerpf(0.5, 1.0, night),
		"dog": (suburb * 1.6 + z[MacroMap.Zone.HILLS] * 0.3) * lerpf(1.0, 2.0, night) * (1.0 - rain * 0.6) * ground,
		"bus": urban * urban * day * 1.6 * ground,
		"gull": float(s.surf) * day * 5.0 * (1.0 - storm) * (1.0 - rain * 0.5),
		"coyote": night * (z[MacroMap.Zone.HILLS] + suburb * 0.25) * 0.9 * (1.0 - rain),
		"ship_horn": float(s.port) * 0.6,
		"crane": float(s.port) * 4.0 * lerpf(0.5, 1.0, day),
	}


## How much birdsong the hour carries, 0..1: nothing at night, the dawn chorus loudest, a little
## swell again before dusk.
static func birdsong(hour: float) -> float:
	var up := smoothstep(5.2, 6.3, hour) * (1.0 - smoothstep(19.2, 20.3, hour))
	var dawn := exp(-pow((hour - 7.0) / 1.3, 2.0))
	var dusk := 0.35 * exp(-pow((hour - 18.5) / 0.8, 2.0))
	return up * clampf(0.6 + 0.4 * dawn + dusk, 0.0, 1.0)


# --- One-shots ----------------------------------------------------------------------------------

func _roll_one_shots(eye: Vector3, w: Vector3) -> void:
	for kind: String in ONE_SHOTS:
		var per_min: float = rates.get(kind, 0.0)
		if per_min <= 0.0:
			continue
		if _rng.randf() < 1.0 - exp(-per_min / 60.0 * survey_interval):
			fire(kind, eye, w)


## Plays one ambient one-shot of `kind` round the listener at `eye` (local; `w` is the same point
## in the world). Placed where that kind of sound comes from: ship horns out over the harbour,
## cranes over the port, gulls up over the beach, everything else anywhere round.
func fire(kind: String, eye: Vector3, w: Vector3) -> void:
	var info: Dictionary = ONE_SHOTS[kind]
	var got: Array = Sfx.take(info.sound)
	if got.is_empty():
		return
	var range_m: Vector2 = info.dist
	var dir := Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU)
	var target: Vector3 = Vector3.INF
	if kind == "ship_horn" or kind == "crane":
		target = scene.get("port_at", Vector3.INF)
	elif kind == "gull":
		target = scene.get("surf_at", Vector3.INF)
	if target != Vector3.INF:
		var flat := Vector3(target.x - w.x, 0.0, target.z - w.z)
		if flat.length() > 1.0:
			dir = flat.normalized().rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
	var up: Vector2 = info.up
	var at := eye + dir * _rng.randf_range(range_m.x, range_m.y) + Vector3.UP * _rng.randf_range(up.x, up.y)
	var v := _free_shot()
	v.stop()
	v.stream = got[0]
	v.unit_size = info.unit
	v.global_position = at
	v.volume_db = ambience_db + float(info.db) + float(got[1])
	var spread: float = info.pitch
	v.pitch_scale = _rng.randf_range(1.0 - spread, 1.0 + spread)
	v.play()
	fired[kind] = int(fired.get(kind, 0)) + 1


func _free_shot() -> AudioStreamPlayer3D:
	for i in _shots.size():
		var v := _shots[(_next_shot + i) % _shots.size()]
		if not v.playing:
			_next_shot = (_next_shot + i + 1) % _shots.size()
			return v
	var oldest := _shots[_next_shot]
	_next_shot = (_next_shot + 1) % _shots.size()
	return oldest


# --- Emitters -----------------------------------------------------------------------------------

func _place_emitters(eye: Vector3) -> void:
	if scene.is_empty():
		return
	var w := WorldState.to_world(eye)
	for layer: String in ["freeway", "surf", "airport", "port"]:
		var p: AudioStreamPlayer3D = _beds[layer]
		if not p.playing:
			continue
		var src: Vector3 = scene.get(layer + "_at", Vector3.INF)
		var dir := Vector3.FORWARD
		if src != Vector3.INF:
			var d := src - w
			if layer != "freeway":
				d.y = 0.0 # the surf, the field and the quay are all "over there", not below
			if d.length() > 0.5:
				dir = d.normalized()
		p.global_position = eye + dir * emitter_distance


# --- Traffic ------------------------------------------------------------------------------------

func _traffic_cars() -> Array:
	if _traffic == null or not is_instance_valid(_traffic):
		_traffic = _streamer.get_node_or_null("Traffic") if _streamer else null
		if _traffic == null:
			return []
	var out: Array = []
	out.append_array(_traffic.get("cars"))
	out.append_array(_traffic.get("freeway_cars"))
	return out


## Hands the traffic voices to the nearest moving cars and lines up pass-bys.
func _assign_traffic(eye: Vector3) -> void:
	var now := Time.get_ticks_msec()
	var near: Array = []
	var seen := {}
	for car in _traffic_cars():
		if not is_instance_valid(car) or not (car as Node3D).is_inside_tree():
			continue
		var n := car as Node3D
		var id := n.get_instance_id()
		seen[id] = true
		var pos := n.global_position
		var prev: Array = _car_prev.get(id, [])
		if not prev.is_empty():
			var ms: int = now - int(prev[1])
			if ms > 0:
				var vel: Vector3 = (pos - prev[0]) / (float(ms) / 1000.0)
				_car_vel[id] = vel if vel.length() < 90.0 else Vector3.ZERO
		_car_prev[id] = [pos, now]
		var d := pos.distance_to(eye)
		if d < car_hear_distance:
			near.append([d, n])
		_maybe_pass(n, id, pos, eye, now)
	for id in _car_prev.keys():
		if not seen.has(id):
			_car_prev.erase(id)
			_car_vel.erase(id)
			_passed.erase(id)
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in _cars.size():
		var car: Node3D = near[i][1] if i < near.size() else null
		_car_of[i] = car
		var v := _cars[i]
		if car == null or v.stream == null:
			if v.playing:
				v.stop()
		elif not v.playing:
			v.play(_rng.randf_range(0.0, maxf(v.stream.get_length() - 0.3, 0.0)))


func _maybe_pass(car: Node3D, id: int, pos: Vector3, eye: Vector3, now: int) -> void:
	var vel: Vector3 = _car_vel.get(id, Vector3.ZERO)
	var rel_v := vel - _eye_vel
	var speed := rel_v.length()
	if speed < pass_min_speed or now - int(_passed.get(id, -100000)) < 4000:
		return
	var rel := pos - eye
	var t := -rel.dot(rel_v) / (speed * speed)
	if t < 0.0 or t > pass_peak_seconds:
		return
	var miss := (rel + rel_v * t).length()
	if miss > pass_distance:
		return
	var wet := float(_weather.get("wetness")) > 0.5 if _weather else false
	var got: Array = Sfx.take("car_pass_wet" if wet else "car_pass")
	if got.is_empty():
		return
	var slot := -1
	for i in _passes.size():
		if not _passes[i].playing:
			slot = i
			break
	if slot < 0:
		return
	_passed[id] = now
	var v := _passes[slot]
	v.stream = got[0]
	# Closer and faster is louder; the take already carries its own swell and Doppler.
	v.volume_db = float(got[1]) - 2.0 - 20.0 * log(maxf(miss, 2.0) / 3.0) / log(10.0) + clampf((vel.length() - 12.0) * 0.4, -4.0, 4.0)
	v.pitch_scale = clampf(vel.length() / 14.0, 0.8, 1.25)
	v.global_position = pos
	_pass_of[slot] = car
	# Start part-way in, so the take's loudest instant lands when the car is alongside.
	v.play(maxf(pass_peak_seconds - t, 0.0))


func _follow_traffic(eye: Vector3, _dt: float) -> void:
	for i in _cars.size():
		var v := _cars[i]
		var car: Variant = _car_of[i]
		if car == null or not is_instance_valid(car) or not (car as Node3D).is_inside_tree():
			if v.playing:
				v.stop()
			_car_of[i] = null
			continue
		var n := car as Node3D
		v.global_position = n.global_position
		var vel: Vector3 = _car_vel.get(n.get_instance_id(), Vector3.ZERO)
		var speed := vel.length()
		var to_eye := eye - n.global_position
		var closing := (vel - _eye_vel).dot(to_eye.normalized()) if to_eye.length() > 0.5 else 0.0
		var doppler := clampf(SOUND_SPEED / maxf(SOUND_SPEED - closing, 200.0), 0.85, 1.2)
		v.pitch_scale = clampf((0.75 + speed / 40.0) * doppler, 0.5, 2.0)
		# A stopped car is an idle murmur; a fast one is tyre roar.
		v.volume_db = _car_trim + ambience_db + clampf(-14.0 + speed * 0.6, -14.0, -2.0)
		for k in _passes.size():
			if _pass_of[k] == car and _passes[k].playing:
				v.volume_db -= 8.0 # the pass-by carries it for now
	for k in _passes.size():
		var car: Variant = _pass_of[k]
		if not _passes[k].playing:
			_pass_of[k] = null
		elif car != null and is_instance_valid(car) and (car as Node3D).is_inside_tree():
			_passes[k].global_position = (car as Node3D).global_position


# --- Ducking ------------------------------------------------------------------------------------

func _poll_blasts(eye: Vector3) -> void:
	if Explosion.blast_count == _blast_seen:
		return
	_blast_seen = Explosion.blast_count
	notify_blast(WorldState.to_local(Explosion.last_blast_world), eye)


## A blast at `at` (local): ducks the ambience by how close it was and, point-blank, muffles the
## whole game for a moment. Called by the blast poll; the smoke test calls it directly.
func notify_blast(at: Vector3, eye: Vector3) -> void:
	var d := at.distance_to(eye)
	var depth := clampf(1.0 - d / maxf(blast_duck_radius, 1.0), 0.0, 1.0)
	if depth <= 0.0:
		return
	var ring := clampf(1.0 - d / maxf(concussion_radius, 1.0), 0.0, 1.0)
	# The deeper of this blast and what is left of the last one, then the recovery starts over.
	_blast_depth = maxf(depth, _blast_depth * _blast)
	_concussion = maxf(ring, _concussion * _blast)
	_blast = 1.0


## True while something holds time slow: the weapon wheel, or the knock-out collapse.
func _slowed() -> bool:
	if AudioServer.playback_speed_scale < 0.97:
		return true
	var wheel := get_tree().get_first_node_in_group("weapon_wheel")
	return wheel != null and wheel.has_method("is_open") and bool(wheel.call("is_open"))


# --- Helpers ------------------------------------------------------------------------------------

func _listener() -> Vector3:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam and cam.is_inside_tree():
		return cam.global_position
	var p := _get_player()
	return p.global_position if p else Vector3.ZERO


func _track_listener(eye: Vector3, dt: float) -> void:
	var offset := WorldState.world_offset
	if offset != _offset_seen:
		# The world moved under us: every stored position is in the old frame.
		_offset_seen = offset
		_eye_prev = Vector3.INF
		_car_prev.clear()
		_car_vel.clear()
	if _eye_prev != Vector3.INF and dt > 0.0:
		var v := (eye - _eye_prev) / dt
		_eye_vel = _eye_vel.lerp(v if v.length() < 150.0 else Vector3.ZERO, 0.3)
	_eye_prev = eye


func _get_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func _plan() -> CityPlan:
	return _streamer.get("plan") as CityPlan if _streamer else null


func _space() -> PhysicsDirectSpaceState3D:
	var w := get_viewport().world_3d if get_viewport() else null
	return w.direct_space_state if w else null
