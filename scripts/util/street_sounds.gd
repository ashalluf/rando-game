class_name StreetSounds
extends Node
## The street's sound at eye level (wave 4, "ambient-sound-2"): what the city's beds cannot carry
## because it happens right next to you. A child of Ambience (one line in Ambience._ready()).
##   - The crowd's footsteps: the few walkers nearest the listener each step on what they walk on
##     (Footsteps.surface_at(), the hero's own rule), at their own cadence (step_interval()), a
##     share of them in heels on hard ground. One sphere query on the npc layer a `scan_interval`.
##   - A shop door's bell when somebody goes into or comes out of a shop (StreetErrands, one hook
##     each), a car door's latch and slam (ErrandCar, one hook).
##   - A bus's or a truck's air brakes setting as it comes to a stand (traffic within
##     `brake_reach`, worked out from their positions: nothing in TrafficManager changes).
##   - The player's tyres by surface: gravel / dirt / grass / sand off the tarmac, a wet hiss on a
##     wet road (tyre_kind(), pure), a loop under the car pitched by speed, silent in the air.
## The two new beds - leaves in the wind and the sea from a long way off - are Ambience layers
## (levels_for()); the traffic voices' wet hiss is Ambience's too.
##
## Every level is a pure function (step_interval(), step_db(), tyre_kind(), tyre_db()) so the smoke
## test can check them; `AMBIENT_SOUND_2=0` in the environment turns all of it off (the A/B).

## Off: none of this, and Ambience's two new beds and the wet hiss stay silent.
static var enabled: bool = OS.get_environment("AMBIENT_SOUND_2") != "0"

## How far round the listener walkers are heard (m), and how many at once.
@export var step_reach: float = 15.0
@export var max_walkers: int = 6
## How often the crowd round the listener is looked for, seconds (real clock).
@export var scan_interval: float = 0.25
## A walker's step at a walk and at a run, dB (before the distance falloff).
@export var walk_step_db: float = -15.0
@export var run_step_db: float = -9.0
## Share of walkers in heels (on hard ground only).
@export var heels_share: float = 0.16
## Shop bells and car doors further than this from the listener are not played (m).
@export var event_reach: float = 40.0
## Heavy vehicles' air brakes: how far (m), how often one vehicle may (s).
@export var brake_reach: float = 80.0
@export var brake_cooldown: float = 12.0
## The player's tyres: level at a crawl and at `tyre_full_speed` m/s (dB).
@export var tyre_low_db: float = -24.0
@export var tyre_high_db: float = -6.0
@export var tyre_full_speed: float = 28.0

const NPC_LAYER := 8
const WORLD_LAYER := 1
const HARD := ["concrete", "asphalt", "wood", "metal"]
const SOFT := ["grass", "sand"]

## What has played since load (the smoke test and the audio probe).
static var counts: Dictionary = {"step": 0, "bell": 0, "door": 0, "brake": 0}
static var _inst: StreetSounds

var tyre: String = "" # what the player's tyres are on now ("" none: dry tarmac, on foot, airborne)
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _walkers: Dictionary = {} # instance id -> {"p": Pedestrian, "prev": Vector3, "phase": float, "speed": float}
var _scan_left: float = 0.0
var _brake_left: float = 0.0
var _big: Dictionary = {} # instance id -> [prev position, moving (s), last brake msec]
var _tyre_player: AudioStreamPlayer3D
var _tyre_trim: float = 0.0
var _tyre_left: float = 0.0
var _last_us: int = 0
var _sphere := PhysicsShapeQueryParameters3D.new()
var _ray := PhysicsRayQueryParameters3D.new()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_inst = self
	_rng.seed = 7707
	var ball := SphereShape3D.new()
	ball.radius = step_reach
	_sphere.shape = ball
	_sphere.collision_mask = NPC_LAYER
	_sphere.collide_with_areas = false
	_ray.collision_mask = WORLD_LAYER | 4
	for i in maxi(max_walkers, 1) + 2:
		var v := AudioStreamPlayer3D.new()
		v.name = "Step_%d" % i
		v.bus = Sfx.BUS_WORLD
		v.unit_size = 2.5
		v.max_distance = step_reach * 1.6
		add_child(v)
		_voices.append(v)
	_tyre_player = AudioStreamPlayer3D.new()
	_tyre_player.name = "Tyres"
	_tyre_player.bus = Sfx.BUS_WORLD
	_tyre_player.unit_size = 6.0
	add_child(_tyre_player)
	_last_us = Time.get_ticks_usec()


func _exit_tree() -> void:
	if _inst == self:
		_inst = null


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf(float(now - _last_us) / 1000000.0, 0.0, 0.25)
	_last_us = now
	if not enabled:
		return
	var eye := _listener()
	_scan_left -= dt
	if _scan_left <= 0.0:
		_scan_left = scan_interval
		_scan_walkers(eye)
	_step_walkers(dt)
	_brake_left -= dt
	if _brake_left <= 0.0:
		_brake_left = 0.25
		_watch_brakes(eye, 0.25)
	_tyre_left -= dt
	if _tyre_left <= 0.0:
		_tyre_left = 0.2
		_update_tyre_surface()
	_drive_tyres()


# --- Pure levels --------------------------------------------------------------------------------

## Seconds between two steps of somebody moving at `speed` m/s: a 0.7 m step at a stroll, a 1.3 m
## one at a run (cadence ~1.9 steps a second walking, ~2.8 running). INF standing still.
static func step_interval(speed: float) -> float:
	if speed < 0.35:
		return INF
	var length := lerpf(0.68, 1.3, clampf((speed - 1.3) / 2.6, 0.0, 1.0))
	return length / speed


## A walker's step level (dB, before the falloff): louder running, softer on grass and sand,
## heels a little brighter.
static func step_db(speed: float, surface: String, walk_db: float = -15.0, run_db: float = -9.0) -> float:
	var db := lerpf(walk_db, run_db, clampf((speed - 1.6) / 2.4, 0.0, 1.0))
	if surface in SOFT:
		db -= 3.0
	return db


## The Sfx name of a walker's step on `surface`; `heels` only counts on hard ground.
static func step_sound(surface: String, heels: bool) -> String:
	if heels and surface in HARD:
		return "footstep_heels"
	return "footstep_" + surface


## What a car's tyres say on `surface` (Footsteps.SURFACES) of a road `wetness` (0..1) wet:
## "gravel" off the tarmac (grass, sand: dirt and grit under the tyres), "wet" on a wet hard
## road, "" on a dry one (the engine and the traffic's roll carry that).
static func tyre_kind(surface: String, wetness: float) -> String:
	if surface in SOFT:
		return "gravel"
	if wetness > 0.3:
		return "wet"
	return ""


## The tyre loop's level for `kind` at `speed` m/s (dB before the trim), and its pitch.
static func tyre_db(kind: String, speed: float, low_db: float = -24.0, high_db: float = -6.0, full: float = 28.0) -> float:
	if kind == "" or speed < 0.8:
		return -80.0
	var k := clampf(speed / maxf(full, 1.0), 0.0, 1.0)
	var db := lerpf(low_db, high_db, sqrt(k))
	if kind == "wet":
		db -= 2.0 + 4.0 * (1.0 - k) # the hiss is a speed thing: a crawl barely makes one
	return db


static func tyre_pitch(kind: String, speed: float) -> float:
	if kind == "gravel":
		return clampf(0.75 + speed / 30.0, 0.75, 1.6)
	return clampf(0.85 + speed / 60.0, 0.85, 1.4)


# --- Events (hooks) -----------------------------------------------------------------------------

## A shop door's bell at `at` (global): somebody went in or came out (StreetErrands).
static func shop_door(at: Vector3) -> void:
	if not enabled or _inst == null or not is_instance_valid(_inst):
		return
	_inst._event("shop_bell", at + Vector3.UP * 2.1, -8.0, 0.04, "bell")


## A car door at `at` (global) opening (the latch and swing) or shutting (the slam) (ErrandCar).
static func car_door(at: Vector3, opening: bool) -> void:
	if not enabled or _inst == null or not is_instance_valid(_inst):
		return
	_inst._event("car_door_open" if opening else "car_door", at + Vector3.UP * 0.9, -9.0 if opening else -5.0, 0.08, "door")


## The hook ErrandCar calls each tick with its door's opening before and after the tick: a sound
## when it starts to open and when it closes.
static func car_door_moved(door: Node3D, before: float, after: float) -> void:
	if door == null or not door.is_inside_tree() or before == after:
		return
	if before <= 0.0 and after > 0.0:
		car_door(door.global_position, true)
	elif before > 0.0 and after <= 0.0:
		car_door(door.global_position, false)


## Where a real dog (group "dog", less the wildlife: yard dogs, walkers' dogs) stands nearest `eye` within
## `reach` m, a little over its back; INF when none. Ambience's far barks come from it.
static func dog_at(tree: SceneTree, eye: Vector3, reach: float) -> Vector3:
	var best := reach
	var at := Vector3.INF
	for d: Node in tree.get_nodes_in_group("dog"):
		var n := d as Node3D
		if n == null or n is WildAnimal or not n.is_inside_tree() or not n.is_visible_in_tree():
			continue # a coyote or a deer is in the group too: it does not bark like a dog
		var dist := n.global_position.distance_to(eye)
		if dist < best:
			best = dist
			at = n.global_position + Vector3.UP * 0.5
	return at


func _event(sound: String, at: Vector3, db: float, spread: float, counter: String) -> void:
	if at.distance_to(_listener()) > event_reach:
		return
	var got: Array = Sfx.take(sound)
	if got.is_empty():
		return
	var v := _free_voice()
	v.stop()
	v.stream = got[0]
	v.unit_size = 4.0
	v.max_distance = event_reach * 1.5
	v.global_position = at
	v.volume_db = db + float(got[1])
	v.pitch_scale = _rng.randf_range(1.0 - spread, 1.0 + spread)
	v.play()
	counts[counter] = int(counts.get(counter, 0)) + 1


func _free_voice() -> AudioStreamPlayer3D:
	for i in _voices.size():
		var v := _voices[(_next_voice + i) % _voices.size()]
		if not v.playing:
			_next_voice = (_next_voice + i + 1) % _voices.size()
			return v
	var oldest := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	return oldest


# --- The crowd's feet ---------------------------------------------------------------------------

func _scan_walkers(eye: Vector3) -> void:
	var space := _space()
	if space == null:
		return
	_sphere.transform = Transform3D(Basis(), eye)
	var found: Array = []
	for r: Dictionary in space.intersect_shape(_sphere, 32):
		var c: Object = r.get("collider")
		if c is Pedestrian and (c as Pedestrian).visible and (c as Pedestrian).is_inside_tree():
			found.append([(c as Node3D).global_position.distance_to(eye), c])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var keep := {}
	for i in mini(found.size(), max_walkers):
		var p: Pedestrian = found[i][1]
		var id := p.get_instance_id()
		keep[id] = true
		if not _walkers.has(id):
			# Start half way through a step, at a random point, so a group does not stamp in step.
			_walkers[id] = {"p": p, "prev": p.global_position, "phase": _rng.randf(), "speed": 0.0,
				"heels": float(hash(id) % 1000) / 1000.0 < heels_share, "surface": ""}
	for id in _walkers.keys():
		if not keep.has(id):
			_walkers.erase(id)


func _step_walkers(dt: float) -> void:
	if dt <= 0.0:
		return
	var plan := _plan()
	for id in _walkers.keys():
		var w: Dictionary = _walkers[id]
		var p: Variant = w.p
		if not is_instance_valid(p) or not (p as Pedestrian).is_inside_tree() or not (p as Pedestrian).visible:
			_walkers.erase(id)
			continue
		var ped := p as Pedestrian
		var pos := ped.global_position
		var d := pos - (w.prev as Vector3)
		w.prev = pos
		d.y = 0.0
		var v := d.length() / dt
		if v > 9.0:
			v = 0.0 # a teleport, a re-centre, a ragdoll handover
		w.speed = lerpf(float(w.speed), v, 0.35)
		var interval := step_interval(float(w.speed))
		if interval == INF:
			continue
		w.phase = float(w.phase) + dt / interval
		if float(w.phase) < 1.0:
			continue
		w.phase = fmod(float(w.phase), 1.0)
		var surface := String(w.surface)
		if surface == "" or _rng.randf() < 0.2:
			var tw := WorldState.to_world(pos)
			surface = Footsteps.surface_at(plan, Vector2(tw.x, tw.z), tw.y, null) if plan != null else "concrete"
			w.surface = surface
		var sound := step_sound(surface, bool(w.heels))
		var got: Array = Sfx.take(sound)
		if got.is_empty():
			continue
		var voice := _free_voice()
		voice.stop()
		voice.stream = got[0]
		voice.unit_size = 2.5
		voice.max_distance = step_reach * 1.6
		voice.global_position = pos + Vector3.UP * 0.05
		voice.volume_db = step_db(float(w.speed), surface, walk_step_db, run_step_db) + float(got[1])
		voice.pitch_scale = _rng.randf_range(0.92, 1.08)
		voice.play()
		counts.step = int(counts.step) + 1


# --- Air brakes ---------------------------------------------------------------------------------

## One look at a heavy vehicle: `rec` is [position, seconds it has been moving, msec it last
## hissed] (updated in place), `speed` m/s since the last look. True when the brakes should set:
## it was rolling for over a second and now stands, and it has not hissed in `cooldown` s.
static func brake_step(rec: Array, speed: float, dt: float, now: int, cooldown: float) -> bool:
	if speed > 2.5 and speed < 40.0:
		rec[1] = float(rec[1]) + dt
		return false
	if speed >= 0.25:
		return false
	var hiss := float(rec[1]) > 1.0 and now - int(rec[2]) > int(cooldown * 1000.0)
	if hiss:
		rec[2] = now
	rec[1] = 0.0
	return hiss


func _watch_brakes(eye: Vector3, dt: float) -> void:
	var traffic := _traffic()
	if traffic == null:
		return
	var now := Time.get_ticks_msec()
	var seen := {}
	for car in traffic.get("cars"):
		if not is_instance_valid(car) or not (car as Node3D).is_inside_tree():
			continue
		if not BigVehicles.is_big(int(car.get("body_type"))):
			continue
		var n := car as Node3D
		var pos := n.global_position
		if pos.distance_to(eye) > brake_reach:
			continue
		var id := n.get_instance_id()
		seen[id] = true
		var rec: Array = _big.get(id, [pos, 0.0, -100000])
		var speed := (pos - (rec[0] as Vector3)).length() / dt
		rec[0] = pos
		if brake_step(rec, speed, dt, now, brake_cooldown):
			_event("air_brake", pos + Vector3.UP * 0.6, -6.0, 0.05, "brake")
		_big[id] = rec
	for id in _big.keys():
		if not seen.has(id):
			_big.erase(id)


# --- The player's tyres -------------------------------------------------------------------------

func _player_car() -> Vehicle:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	var car: Variant = player.get("vehicle")
	if not (car is Vehicle) or car is Aircraft or car is FlyableHeli or car is Boat:
		return null
	return car as Vehicle


func _update_tyre_surface() -> void:
	var car := _player_car()
	if car == null or not car.is_inside_tree():
		tyre = ""
		return
	var space := _space()
	if space == null:
		tyre = ""
		return
	_ray.from = car.global_position + Vector3.UP * 0.5
	_ray.to = car.global_position + Vector3.DOWN * 1.6
	_ray.exclude = [car.get_rid()]
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		tyre = "" # in the air
		return
	var plan := _plan()
	var tw := WorldState.to_world(hit.position as Vector3)
	var surface := Footsteps.surface_at(plan, Vector2(tw.x, tw.z), tw.y, null) if plan != null else "asphalt"
	if surface == "grass" and plan != null and plan.macro != null and _on_hill_road(plan.macro, Vector2(tw.x, tw.z)):
		surface = "asphalt"
	var st := _streamer()
	var weather := st.get_node_or_null("Weather") if st else null
	var wet := float(weather.get("wetness")) if weather else 0.0
	tyre = tyre_kind(surface, wet)


func _on_hill_road(macro: MacroMap, xz: Vector2) -> bool:
	var hr = macro.hill_roads
	if hr == null:
		return false
	for seg: Dictionary in hr.segments_in(Rect2(xz - Vector2.ONE * 12.0, Vector2.ONE * 24.0)):
		if not bool(seg.get("draw", true)):
			continue # fire roads and long driveways are dirt
		var a: Vector2 = seg.a
		var ab: Vector2 = (seg.b as Vector2) - a
		var f := clampf((xz - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if xz.distance_to(a + ab * f) < float(seg.width) * 0.5 + 0.5:
			return true
	return false


func _drive_tyres() -> void:
	var car := _player_car()
	if car == null or tyre == "":
		if _tyre_player.playing:
			_tyre_player.stop()
		return
	var name := "tyre_gravel" if tyre == "gravel" else "tyre_wet"
	if _tyre_player.get_meta("sound", "") != name:
		var got: Array = Sfx.take(name)
		if got.is_empty():
			return
		_tyre_player.stop()
		_tyre_player.stream = got[0]
		_tyre_trim = float(got[1])
		_tyre_player.set_meta("sound", name)
	var speed := car.linear_velocity.length()
	_tyre_player.global_position = car.global_position
	_tyre_player.volume_db = tyre_db(tyre, speed, tyre_low_db, tyre_high_db, tyre_full_speed) + _tyre_trim
	_tyre_player.pitch_scale = tyre_pitch(tyre, speed)
	if speed < 0.8:
		if _tyre_player.playing:
			_tyre_player.stop()
	elif not _tyre_player.playing:
		_tyre_player.play(_rng.randf_range(0.0, maxf(_tyre_player.stream.get_length() - 0.3, 0.0)))


# --- Helpers ------------------------------------------------------------------------------------

func _listener() -> Vector3:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam and cam.is_inside_tree():
		return cam.global_position
	var p := get_tree().get_first_node_in_group("player") as Node3D
	return p.global_position if p else Vector3.ZERO


func _streamer() -> Node:
	var amb := get_parent()
	return amb.get_parent() if amb else null


func _plan() -> CityPlan:
	var s := _streamer()
	return s.get("plan") as CityPlan if s and "plan" in s else null


func _traffic() -> Node:
	var s := _streamer()
	return s.get_node_or_null("Traffic") if s else null


func _space() -> PhysicsDirectSpaceState3D:
	var w := get_viewport().world_3d if get_viewport() else null
	return w.direct_space_state if w else null
