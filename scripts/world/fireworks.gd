class_name Fireworks
extends Node3D
## FIREWORKS (2026-10-30, wave 3, docs/HANDOFF.md "Fireworks"): shows over the beach (a barge off
## the pier) and over the ballpark's centre field on some nights. A Node3D in city.tscn, so the
## streamer's origin shifts carry it; its sites are placed from TRUE world positions every frame.
##
## **A show is worked out, never simulated.** Its programme is shaders/fireworks.gdshaderinc: time
## in FW_BIN bins, a hash of (show seed, bin) says whether a bin launches a shell and everything
## about it (when, where on the launch line, how high, PEONY / WILLOW / CROSSETTE / STROBE / RING,
## colours, size), looping an act of an opening, the body, a build, a finale and a gap. The GPU
## draws it from one clock (`now`) and one seed: ONE mesh of quads per site for the stars and the
## rising shells (shaders/fireworks.gdshader), one for the smoke drifting off on the wind
## (fireworks_smoke.gdshader), and at the beach the glints on the sea (fireworks_water.gdshader).
## No particles, no per-star CPU; it is the same on Compatibility. This script mirrors the plan
## bit for bit (`shell()`, the same integer hash) for what the GPU cannot do: the booms, heard
## distance / SOUND_SPEED seconds after each break from wherever the camera is; the crackle; the
## light (an OmniLight3D per site, off the web, coloured by what is breaking now, which lights the
## water, the pier and the city round it); the brightest breaks handed to the water.
##
## **Which nights**: `show_tonight()`, a hash of (plan seed, day, site) against `ODDS`, the night
## running from START_HOUR to END_HOUR of the game clock (the day counted from noon, so a show
## that runs past midnight is still the same night's); none while it rains. Every roll is a hash,
## nothing else in the city rolls differently.
##
## Switches: `FIREWORKS=0` off (the A/B), `FIREWORKS=1` forces both sites on whatever the night,
## hour or weather; `FIREWORKS_SITE=beach|stadium` only that one; `FIREWORKS_T=<s>` starts the
## show clock there, `FIREWORKS_HOLD=1` holds it (stills).

## Must match fireworks.gdshaderinc (the checks read it back).
const BIN := 0.4
const SLOTS := 24
const STARS := 96
const TRAIL := 10
const SMOKE_SLOTS := 84
const SMOKE_PUFFS := 4
const SMOKE_LIFE := 28.0
const ACT_BINS := 375
const OPEN_END := 20
const BODY_END := 250
const BUILD_END := 320
const FINALE_END := 358
const P_OPEN := 0.30
const P_BODY := 0.40
const P_BUILD := 0.60
const P_FINALE := 0.95
const TYPE_CUT := [0.36, 0.56, 0.74, 0.88]
const FINALE_CUT := [0.28, 0.55, 0.66, 0.90]
const LIFE := [2.3, 5.0, 2.7, 3.0, 2.1]
const V0 := [95.0, 72.0, 82.0, 80.0, 92.0]
const DRAG := [1.6, 2.3, 1.2, 1.5, 1.6]
const COLORS := [Color(1.0, 0.10, 0.035), Color(0.16, 1.0, 0.10), Color(0.10, 0.24, 1.0),
	Color(1.0, 0.52, 0.12), Color(0.88, 0.90, 1.0), Color(0.55, 0.12, 1.0), Color(0.12, 0.82, 1.0)]
const WILLOW_COLOR := Color(1.0, 0.42, 0.10)
const STROBE_COLOR := Color(0.95, 0.97, 1.0)
enum Type {PEONY, WILLOW, CROSSETTE, STROBE, RING}
const TYPE_NAMES := ["peony", "willow", "crossette", "strobe", "ring"]

## Speed of sound (m/s): a break 1.7 km off is heard five seconds after it is seen.
const SOUND_SPEED := 343.0
## Booms are not played past this (metres), the crackle past CRACKLE_REACH, the launch thumps
## past THUMP_REACH.
const BOOM_REACH := 6000.0
const CRACKLE_REACH := 2200.0
const THUMP_REACH := 1200.0
## The night's window (game hours) and how long the show fades in and out at its ends.
const START_HOUR := 20.75
const END_HOUR := 23.25
const FADE_HOURS := 0.04
## Odds a night has a show, per site.
const ODDS := {"beach": 0.22, "stadium": 0.30}
## The water's brightest breaks (fireworks_water.gdshader's arrays).
const WATER_LIGHTS := 4

## Off (the A/B): `FIREWORKS=0`; forced: `FIREWORKS=1`. -1 until read.
static var _env: int = -2

## Each site: id, true world ground point, launch line, its length, break heights.
var sites: Array = []
## Set by the checks / stills: a site id -> show seconds to hold or run from.
var staged: Dictionary = {}
var hold: bool = false
## Counts, for the checks.
var booms_played: int = 0
var crackles_played: int = 0
var thumps_played: int = 0

var plan: CityPlan
var _built: bool = false
var _players: Array[AudioStreamPlayer3D] = []
var _next_player: int = 0
static var _streams: Dictionary = {}
static var _star_mesh: ArrayMesh
static var _smoke_mesh: ArrayMesh


static func env_state() -> int:
	if _env == -2:
		var v := OS.get_environment("FIREWORKS")
		_env = 0 if v == "0" else (1 if v == "1" else -1)
	return _env


static func enabled() -> bool:
	return env_state() != 0


static func forced() -> bool:
	return env_state() == 1


# --- The plan (fireworks.gdshaderinc, in GDScript) -----------------------------------------------

static func _mul32(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF


static func h32(key: int, salt: int) -> int:
	var h := (_mul32(key & 0xFFFFFFFF, 747796405) + _mul32(salt & 0xFFFFFFFF, 2891336453)) & 0xFFFFFFFF
	h ^= h >> 16
	h = _mul32(h, 2246822519)
	h ^= h >> 13
	h = _mul32(h, 3266489917)
	h ^= h >> 16
	return h


static func roll(key: int, salt: int) -> float:
	return float(h32(key, salt) >> 8) / 16777216.0


static func shell_key(show_seed: int, bin: int) -> int:
	return h32(show_seed, bin)


static func launch_odds(bin: int) -> float:
	var ph := bin % ACT_BINS
	if ph < OPEN_END:
		return P_OPEN
	if ph < BODY_END:
		return P_BODY
	if ph < BUILD_END:
		return P_BUILD
	if ph < FINALE_END:
		return P_FINALE
	return 0.0


static func is_finale(bin: int) -> bool:
	var ph := bin % ACT_BINS
	return ph >= BUILD_END and ph < FINALE_END


## The shell of a bin, or {} when the bin launches nothing: launch / burst times (show seconds),
## `off` the mortar and `burst` the break in the site's frame, type, colours, size, life.
static func shell(show_seed: int, bin: int, line_dir: Vector2, spread: float, h_min: float, h_max: float) -> Dictionary:
	if bin < 0:
		return {}
	var k := shell_key(show_seed, bin)
	if roll(k, 1) >= launch_odds(bin):
		return {}
	var tl := (float(bin) + 0.8 * roll(k, 2)) * BIN
	var along := (roll(k, 3) - 0.5) * spread
	var across := (roll(k, 4) - 0.5) * 18.0
	var ld := line_dir.normalized()
	var o := ld * along + Vector2(-ld.y, ld.x) * across
	var h := lerpf(h_min, h_max, roll(k, 5))
	var rise := 1.4 + h / 130.0
	var tr := roll(k, 6)
	var cuts: Array = FINALE_CUT if is_finale(bin) else TYPE_CUT
	var type := 4
	for i in 4:
		if tr < float(cuts[i]):
			type = i
			break
	var drift := (Vector2(roll(k, 9), roll(k, 10)) - Vector2(0.5, 0.5)) * 0.14 * h
	var size := lerpf(0.78, 1.22, roll(k, 11))
	return {"bin": bin, "key": k, "launch": tl, "burst_t": tl + rise, "off": Vector3(o.x, 0.0, o.y),
		"burst": Vector3(o.x + drift.x, h, o.y + drift.y), "type": type,
		"c1": int(roll(k, 7) * 7.0), "c2": int(roll(k, 8) * 7.0), "size": size,
		"life": float(LIFE[type]) * lerpf(0.85, 1.12, roll(k, 15))}


## The colour a shell's stars burn (linear).
static func shell_color(sh: Dictionary) -> Color:
	var t: int = sh.type
	if t == Type.WILLOW:
		return WILLOW_COLOR
	if t == Type.STROBE:
		return STROBE_COLOR
	return COLORS[int(sh.c1)]


## The break's radius (metres) for the light and the smoke: star speed over drag.
static func shell_reach(sh: Dictionary) -> float:
	return float(V0[sh.type]) / float(DRAG[sh.type]) * float(sh.size)


## When a break at distance `d` is heard (show seconds).
static func heard_at(burst_t: float, d: float) -> float:
	return burst_t + d / SOUND_SPEED


## Whether a site has a show on a night (the day the evening began on).
static func show_tonight(seed: int, night: int, site_id: String) -> bool:
	var k := h32(h32(seed, night & 0xFFFFFFFF), site_id.hash() & 0xFFFFFFFF)
	return roll(k, 77) < float(ODDS.get(site_id, 0.0))


## That night's show seed (31 bits, an int uniform).
static func night_seed(seed: int, night: int, site_id: String) -> int:
	return h32(h32(seed, night & 0xFFFFFFFF), (site_id.hash() + 1) & 0xFFFFFFFF) & 0x7FFFFFFF


## The night a game time belongs to: the day count, less one before noon.
static func night_of(day_count: int, hour: float) -> int:
	return day_count - 1 if hour < 12.0 else day_count


## 0..1: how far into its window the show is at this hour (0 outside it).
static func window_level(hour: float) -> float:
	var h := hour if hour >= 12.0 else hour + 24.0
	if h < START_HOUR or h > END_HOUR:
		return 0.0
	return clampf(minf(h - START_HOUR, END_HOUR - h) / FADE_HOURS, 0.0, 1.0)


# --- The sites ----------------------------------------------------------------------------------

## The sites on this plan: the beach show from a barge off the pier, the ballpark's beyond the
## centre-field fence. Pure (the plan only).
static func plan_sites(p: CityPlan) -> Array:
	var out: Array = []
	if p == null or p.macro == null:
		return out
	var pier := Vector2(-940.0, -350.0)
	for lm in Landmarks.all():
		if lm.id == "pier":
			pier = lm.anchor
	var shore: float = p.macro.coast_x(pier.y)
	# The barge stands well past the pier's end, on open water.
	var bx := minf(pier.x, shore) - 480.0
	var bp := Vector2(bx, pier.y)
	var tries := 0
	while int(p.macro.zone_at(bp)) != int(MacroMap.Zone.OCEAN) and tries < 20:
		bp.x -= 60.0
		tries += 1
	out.append({"id": "beach", "world": Vector3(bp.x, 0.4, bp.y), "line": Vector2(0.0, 1.0), "spread": 240.0,
		"h_min": 140.0, "h_max": 290.0, "shore_x": shore - bp.x, "water": true})
	if Ballpark.enabled():
		var c := Ballpark.world(0.0, 170.0)
		out.append({"id": "stadium", "world": Vector3(c.x, p.height_at(c) + 2.0, c.y), "line": Ballpark.RIGHT,
			"spread": 110.0, "h_min": 95.0, "h_max": 190.0, "shore_x": 0.0, "water": false})
	return out


# --- The node -----------------------------------------------------------------------------------

func _ready() -> void:
	name = "Fireworks"
	var t := OS.get_environment("FIREWORKS_T")
	if t != "":
		var only := OS.get_environment("FIREWORKS_SITE")
		for id in ["beach", "stadium"]:
			if only == "" or only == id:
				staged[id] = float(t)
	hold = OS.get_environment("FIREWORKS_HOLD") == "1"


func _setup() -> bool:
	if _built:
		return true
	if not enabled():
		return false
	var city := get_parent()
	if city == null or not ("plan" in city):
		return false
	plan = city.get("plan") as CityPlan
	if plan == null or plan.macro == null:
		return false
	var only := OS.get_environment("FIREWORKS_SITE")
	for s in plan_sites(plan):
		if only != "" and s.id != only:
			continue
		sites.append(_build_site(s))
	var bus := "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	for i in 8:
		var a := AudioStreamPlayer3D.new()
		a.name = "Boom%d" % i
		a.bus = bus
		a.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		a.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(a)
		_players.append(a)
	_built = true
	return true


func _build_site(s: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "Show_" + String(s.id)
	root.visible = false
	add_child(root)
	var stars := MeshInstance3D.new()
	stars.name = "Stars"
	stars.mesh = star_mesh()
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	stars.custom_aabb = AABB(Vector3(-900.0, -60.0, -900.0), Vector3(1800.0, 700.0, 1800.0))
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/fireworks.gdshader")
	stars.material_override = sm
	root.add_child(stars)
	var smoke := MeshInstance3D.new()
	smoke.name = "Smoke"
	smoke.mesh = smoke_mesh()
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	smoke.custom_aabb = AABB(Vector3(-1200.0, -60.0, -1200.0), Vector3(2400.0, 700.0, 2400.0))
	var km := ShaderMaterial.new()
	km.shader = load("res://shaders/fireworks_smoke.gdshader")
	km.set_shader_parameter("puff_tex", WeaponFX.puff_texture())
	km.set_shader_parameter("puffs", float(SMOKE_PUFFS))
	smoke.material_override = km
	root.add_child(smoke)
	var mats: Array[ShaderMaterial] = [sm, km]
	var water: ShaderMaterial = null
	if s.water:
		var w := MeshInstance3D.new()
		w.name = "WaterGlints"
		var pm := PlaneMesh.new()
		pm.size = Vector2(2400.0, 2400.0)
		w.mesh = pm
		w.position = Vector3(0.0, 0.15, 0.0)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		water = ShaderMaterial.new()
		water.shader = load("res://shaders/fireworks_water.gdshader")
		water.set_shader_parameter("shore_x", float(s.shore_x))
		w.material_override = water
		root.add_child(w)
	for m in mats:
		m.set_shader_parameter("line_dir", s.line)
		m.set_shader_parameter("spread", float(s.spread))
		m.set_shader_parameter("h_min", float(s.h_min))
		m.set_shader_parameter("h_max", float(s.h_max))
	var light: OmniLight3D = null
	if not OS.has_feature("web"):
		light = OmniLight3D.new()
		light.name = "Flash"
		light.omni_range = 900.0
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		light.light_specular = 0.4
		light.visible = false
		root.add_child(light)
	var d := s.duplicate()
	d.merge({"root": root, "stars": sm, "smoke": km, "water": water, "light": light, "clock": 0.0,
		"prev": 0.0, "active": false, "cache": {}, "level": 0.0, "seed": 1, "energy": 0.0, "flash": Color(0, 0, 0)}, true)
	return d


func _process(delta: float) -> void:
	if not _setup():
		return
	var dn := get_parent().get_node_or_null("DayNight")
	var hour: float = dn.get("hour") if dn else 21.0
	var day: int = int(dn.get("day_count")) if dn else 0
	var wx := get_parent().get_node_or_null("Weather")
	var rain: float = float(wx.get("rain_level")) if wx and ("rain_level" in wx) else 0.0
	var wind := Vector2(2.2, 0.8)
	if wx and ("rain_wind" in wx):
		var rw: Vector3 = wx.get("rain_wind")
		wind = Vector2(rw.x, rw.z) * 0.45
	var night := night_of(day, hour)
	var cam := get_viewport().get_camera_3d()
	var smoke_test := get_tree().root.get_node_or_null("SmokeTest") != null
	for s in sites:
		var level := window_level(hour)
		var on := level > 0.0 and rain < 0.15 and show_tonight(plan.seed, night, s.id)
		if forced():
			on = true
			level = 1.0
		if smoke_test and not staged.has(s.id):
			on = false
		if staged.has(s.id):
			if not s.active:
				s.clock = float(staged[s.id])
				s.prev = s.clock
			on = true
			level = 1.0
		if on and not s.active:
			s.seed = night_seed(plan.seed, night, s.id)
			s.cache = {}
			if not staged.has(s.id):
				s.clock = 0.0
				s.prev = 0.0
		s.active = on
		s.level = level
		s.root.visible = on
		if not on:
			if s.light:
				s.light.visible = false
			continue
		s.prev = s.clock
		if not hold:
			s.clock += delta
		advance_site(s, cam, wind)


## One frame of a site: where it stands, the uniforms, the light, the water, the sounds.
func advance_site(s: Dictionary, cam: Camera3D, wind: Vector2) -> void:
	var root: Node3D = s.root
	root.global_position = WorldState.to_local(s.world)
	var px := 0.0012
	if cam:
		var vh := float(get_viewport().get_visible_rect().size.y)
		px = 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / maxf(vh, 1.0)
	for m: ShaderMaterial in [s.stars, s.smoke]:
		m.set_shader_parameter("now", s.clock)
		m.set_shader_parameter("show_seed", int(s.seed))
		m.set_shader_parameter("strength", float(s.level))
		m.set_shader_parameter("wind", wind)
	s.stars.set_shader_parameter("px_angle", px)
	# What is breaking now: the light's colour, level and place; the water's brightest breaks.
	var bnow := int(floor(s.clock / BIN))
	var sum := Color(0, 0, 0)
	var at := Vector3.ZERO
	var wsum := 0.0
	var lit: Array = []
	for b in range(bnow - SLOTS, bnow + 1):
		var sh := _shell_of(s, b)
		if sh.is_empty():
			continue
		var a: float = s.clock - float(sh.burst_t)
		if a < 0.0 or a > float(sh.life):
			continue
		var lvl := flash_level(a, float(sh.life), int(sh.type)) * float(sh.size)
		var c := shell_color(sh)
		sum += c * lvl
		at += Vector3(sh.burst) * lvl
		wsum += lvl
		lit.append([lvl, sh.burst, c])
	s.energy = wsum * float(s.level)
	s.flash = sum * float(s.level)
	if s.light:
		var l: OmniLight3D = s.light
		l.visible = s.energy > 0.02
		if l.visible:
			l.position = at / wsum
			var mx := maxf(sum.r, maxf(sum.g, sum.b))
			l.light_color = Color(sum.r / mx, sum.g / mx, sum.b / mx)
			l.light_energy = minf(s.energy * 2.2, 14.0)
	s.smoke.set_shader_parameter("flash", Vector3(s.flash.r, s.flash.g, s.flash.b))
	s.smoke.set_shader_parameter("flash_at", at / wsum if wsum > 0.0 else Vector3(0, 200, 0))
	if s.water:
		lit.sort_custom(func(x, y): return x[0] > y[0])
		var pos := PackedVector4Array()
		var col := PackedVector3Array()
		for i in WATER_LIGHTS:
			if i < lit.size():
				var p: Vector3 = lit[i][1]
				var c: Color = lit[i][2]
				pos.append(Vector4(p.x, p.y, p.z, float(lit[i][0]) * float(s.level)))
				col.append(Vector3(c.r, c.g, c.b))
			else:
				pos.append(Vector4(0, 0, 0, 0))
				col.append(Vector3.ZERO)
		s.water.set_shader_parameter("burst_pos", pos)
		s.water.set_shader_parameter("burst_col", col)
		s.water.set_shader_parameter("now", s.clock)
		s.water.set_shader_parameter("strength", float(s.level))
	if cam:
		_sounds(s, WorldState.to_world(cam.global_position))


## A break's light against its age: the white flash, then the stars burning down.
static func flash_level(a: float, life: float, type: int) -> float:
	var burn := 1.0 - smoothstep(0.5 * life, life, a)
	var f := 2.4 * exp(-a * 6.0) + 0.8 * exp(-a * 1.1) * burn
	if type == Type.STROBE and a > 0.35:
		f *= 0.7
	return f


# --- Sound --------------------------------------------------------------------------------------

## Plays every boom, crackle and launch thump whose sound reaches the listener (true world
## position) between the last frame and this one.
func _sounds(s: Dictionary, ear: Vector3) -> void:
	if s.clock <= s.prev:
		return
	var origin: Vector3 = s.world
	var max_delay := BOOM_REACH / SOUND_SPEED + 6.0
	var b_lo := int(floor((s.prev - max_delay - 9.0) / BIN))
	var b_hi := int(floor(s.clock / BIN))
	for b in range(maxi(b_lo, 0), b_hi + 1):
		var sh := _shell_of(s, b)
		if sh.is_empty():
			continue
		var bw: Vector3 = origin + Vector3(sh.burst)
		var d := ear.distance_to(bw)
		if d < BOOM_REACH:
			var th := heard_at(float(sh.burst_t), d)
			if th > s.prev and th <= s.clock:
				_play("boom", bw, ear, d, 2.0 - 4.0 * (1.0 - float(sh.size)), 0.85 + 0.25 * roll(int(sh.key), 40))
				booms_played += 1
			var t := int(sh.type)
			if d < CRACKLE_REACH and (t == Type.STROBE or t == Type.WILLOW or t == Type.CROSSETTE):
				var tc := th + (FW_SPLIT_S if t == Type.CROSSETTE else 0.35)
				if tc > s.prev and tc <= s.clock:
					_play("crackle", bw, ear, d, -4.0, 0.9 + 0.2 * roll(int(sh.key), 41))
					crackles_played += 1
		var lw: Vector3 = origin + Vector3(sh.off)
		var dl := ear.distance_to(lw)
		if dl < THUMP_REACH:
			var tt := float(sh.launch) + dl / SOUND_SPEED
			if tt > s.prev and tt <= s.clock:
				_play("thump", lw, ear, dl, -3.0, 0.9 + 0.2 * roll(int(sh.key), 42))
				thumps_played += 1


## The crossette's split, in seconds after the break (FW_SPLIT).
const FW_SPLIT_S := 0.8


func _play(kind: String, at: Vector3, ear: Vector3, d: float, gain_db: float, pitch: float) -> void:
	if _players.is_empty():
		return
	# Level by distance (spherical spreading from 150 m), the air taking the top off far away.
	var vol := gain_db - 20.0 * log(maxf(d, 150.0) / 150.0) / log(10.0) - d * 0.0012
	if vol < -48.0:
		return
	var a := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	a.stream = stream(kind)
	var dir := (at - ear).normalized() if d > 0.1 else Vector3.FORWARD
	# Stood a little way off toward the source, so it pans; the level is ours.
	a.global_position = WorldState.to_local(ear + dir * minf(d, 40.0))
	a.volume_db = vol
	a.pitch_scale = pitch * lerpf(1.0, 0.82, clampf(d / 3000.0, 0.0, 1.0))
	a.attenuation_filter_cutoff_hz = lerpf(9000.0, 900.0, clampf(d / 2500.0, 0.0, 1.0))
	a.play()


## The sounds, synthesised once: a deep boom with a rolling tail, the crackle of a strobe or a
## willow's glitter, the mortar's thump.
static func stream(kind: String) -> AudioStreamWAV:
	if _streams.has(kind):
		return _streams[kind]
	var rate := 22050
	var seconds: float = {"boom": 2.6, "crackle": 1.8, "thump": 0.7}[kind]
	var n := int(seconds * rate)
	var data := PackedFloat32Array()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	var lp := 0.0
	var lp2 := 0.0
	var env := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var w := rng.randf() * 2.0 - 1.0
		var v := 0.0
		if kind == "boom":
			# A pressure thump (a falling sine), a blast of low noise, then the rumble rolling off.
			var f := 38.0 + 30.0 * exp(-t * 9.0)
			v += sin(TAU * f * t) * exp(-t * 5.0) * 0.9
			lp += (w - lp) * 0.09
			v += lp * 3.2 * exp(-t * 7.0)
			lp2 += (w - lp2) * 0.015
			v += lp2 * 7.0 * exp(-t * 1.3) * smoothstep(0.0, 0.08, t)
		elif kind == "crackle":
			# Many tiny pops, thinning out.
			if rng.randf() < 0.012 * exp(-t * 1.2):
				env = 1.0
			env *= 0.86
			lp += (w - lp) * 0.5
			v = (w - lp) * env * 1.4
		else:
			var f := 70.0 + 50.0 * exp(-t * 20.0)
			v += sin(TAU * f * t) * exp(-t * 16.0)
			lp += (w - lp) * 0.2
			v += lp * 1.2 * exp(-t * 9.0)
			v += w * 0.06 * exp(-t * 4.0) * smoothstep(0.02, 0.1, t)
		data[i] = v
	var peak := 0.0
	for x in data:
		peak = maxf(peak, absf(x))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var k := 0.9 / maxf(peak, 1e-4)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(data[i] * k, -1.0, 1.0) * 32767.0))
	var ws := AudioStreamWAV.new()
	ws.format = AudioStreamWAV.FORMAT_16_BITS
	ws.mix_rate = rate
	ws.stereo = false
	ws.data = bytes
	_streams[kind] = ws
	return ws


# --- Meshes -------------------------------------------------------------------------------------

## SLOTS x (STARS + TRAIL) quads; UV the corner, UV2 (slot, quad).
static func star_mesh() -> ArrayMesh:
	if _star_mesh == null:
		_star_mesh = _quads(SLOTS, STARS + TRAIL)
	return _star_mesh


static func smoke_mesh() -> ArrayMesh:
	if _smoke_mesh == null:
		_smoke_mesh = _quads(SMOKE_SLOTS, SMOKE_PUFFS)
	return _smoke_mesh


static func _quads(slots: int, per: int) -> ArrayMesh:
	var n := slots * per
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(n * 4)
	uvs.resize(n * 4)
	uv2s.resize(n * 4)
	idx.resize(n * 6)
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var q := 0
	for s in slots:
		for k in per:
			for c in 4:
				verts[q * 4 + c] = Vector3(corners[c].x, corners[c].y, 0.0)
				uvs[q * 4 + c] = corners[c]
				uv2s[q * 4 + c] = Vector2(s, k)
			var o := q * 6
			idx[o] = q * 4
			idx[o + 1] = q * 4 + 1
			idx[o + 2] = q * 4 + 2
			idx[o + 3] = q * 4
			idx[o + 4] = q * 4 + 2
			idx[o + 5] = q * 4 + 3
			q += 1
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## The site record of an id (or {}).
## A site's shell for a bin, cached (the booms and the light ask for the same bins every frame).
func _shell_of(s: Dictionary, b: int) -> Dictionary:
	var cache: Dictionary = s.cache
	if cache.has(b):
		return cache[b]
	var sh := shell(s.seed, b, s.line, s.spread, s.h_min, s.h_max)
	cache[b] = sh
	if cache.size() > 400:
		var keep := int(floor(s.clock / BIN)) - 150
		for k in cache.keys():
			if int(k) < keep:
				cache.erase(k)
	return sh


func site(id: String) -> Dictionary:
	for s in sites:
		if s.id == id:
			return s
	return {}
