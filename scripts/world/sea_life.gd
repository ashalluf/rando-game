class_name SeaLife
extends Node3D
## Life in the water (2026-10-30, fleet "sea-life"; docs/HANDOFF.md "Life in the water"): a pod
## of dolphins arcing beyond the surf line now and then, a line of brown pelicans gliding low over
## the swell and one of them climbing, folding and plunging, sea lions hauled out on the harbour's
## buoys and barking, and rarely, far offshore, a grey whale's blow and its back rolling through
## the swell, its flukes coming up on the last dive. A Node3D in city.tscn, so the streamer's
## origin shifts carry it; everything lives in this node's own space.
##
## NOTHING IS SIMULATED. Every animal is a pure function of the clock (`clock`) and hashes of the
## seed and a place: the coast is cut into `SEG` metre stretches and time into windows per kind,
## and a hash of (seed, kind, window, stretch) says whether a pod or a line passes there then, how
## many, which way, how far out; each animal's leaps, wingbeats, dives and barks are hashes of its
## index and its cycle. So any moment can be drawn without knowing the moment before (`advance()`
## for the checks and stills is just the clock moving), and the city's other rolls never see it.
## The coast is MacroMap.coast_x() (the sea is west of it); a pod keeps beyond the break line
## (Surf.break_distance() of the sea state Weather draws) and the water's height is SeaSurface's
## (the ocean shader's swell in GDScript), sampled once a pod or a line a frame.
##
## Drawn by one MultiMesh per kind and level of detail (SeaLifeMesh, shaders/sea_life.gdshader:
## the shader beats the tails, flaps and folds the wings, lifts the sea lions' heads and opens
## their jaws) and one of spray (shaders/sea_spray.gdshader: every splash and blow is an age the
## shader flies). The sounds are synthesised here (barks, splashes, a whale's blow).
## SEA_LIFE=0 in the environment (or `enabled` false) removes all of it: the A/B.

## The coast's stretches (m) and how far from the coast line (inland or out) the camera may be for
## the coast's life to be worked out at all.
const SEG := 600.0
const COAST_REACH := 1600.0
## Dolphins: a window (s), the odds a pod passes a stretch in one, how long it takes to pass.
const DOLPHIN_WINDOW := 150.0
const DOLPHIN_ODDS := 0.42
const DOLPHIN_RUN := 115.0
## Pelicans: the same, by day only.
const PELICAN_WINDOW := 80.0
const PELICAN_ODDS := 0.5
const PELICAN_RUN := 75.0
## The share of a line's birds that dive while it passes.
const DIVE_ODDS := 0.4
## Whales: rarer, on longer stretches, much further out.
const WHALE_WINDOW := 480.0
const WHALE_ODDS := 0.3
const WHALE_SEG := 3000.0
const WHALE_BLOWS := 4
const WHALE_GAP := 32.0
## The harbour buoys (true world XZ): one in the harbour off the port's south quay, one out in the
## bay off the Long Beach shore. A buoy that is not on open water for a seed is left out.
const BUOYS := [Vector2(3290.0, 6728.0), Vector2(3790.0, 6690.0)]
## Sea lions on a buoy's deck: at most this many, laid round the tower between its legs.
const MAX_LIONS := 3
const LION_RING := 1.0
## The bark: a bout every this many seconds per buoy at most, this share of them barked.
const BOUT_SECONDS := 9.0
const BOUT_ODDS := 0.62
## Startled (a blast or gunfire within reach) the sea lions go in and come back this long after.
const SCARE_SECONDS := Vector2(55.0, 95.0)

## Drawing distances (m): nothing past these; the near mesh inside the second number.
const RANGES := {
	"dolphin": Vector2(1100.0, 70.0), "sea_lion": Vector2(500.0, 45.0), "pelican": Vector2(850.0, 60.0),
	"whale": Vector2(6000.0, 350.0), "buoy": Vector2(1400.0, 90.0),
}
const KINDS := ["dolphin", "sea_lion", "pelican", "whale", "buoy"]
## Spray kinds (the shader's INSTANCE_CUSTOM.y).
const SPRAY_SPLASH := 0.0
const SPRAY_PLUNGE := 1.0
const SPRAY_BLOW := 2.0
const SPRAY_RANGE := 2600.0
const GRAVITY := 9.8

## Set false to remove all of it (also SEA_LIFE=0 in the environment).
@export var enabled: bool = true
## Sounds in earshot (m).
@export var bark_reach: float = 320.0
@export var splash_reach: float = 170.0
@export var blow_reach: float = 2200.0
@export var bark_db: float = 2.0
@export var splash_db: float = -6.0
@export var blow_db: float = 4.0

## The shared clock (s): advanced by the scaled process delta; every event is a function of it.
static var clock: float = 0.0
static var _live: SeaLife = null
## Counted for the checks: barks and splashes sounded since the scene started.
static var barks: int = 0
static var splashes: int = 0

var plan: CityPlan
var macro: MacroMap
var seed_value: int = 0
var _mm: Dictionary = {} # "kind:lod" -> MultiMeshInstance3D
var _shadow: Dictionary = {} # "kind:0" -> the near batch's shadow twin (the far mesh)
var _spray: MultiMeshInstance3D
var _lists: Dictionary = {} # "kind:lod" -> Array of [Transform3D, Color, Vector4]
var _spray_list: Array = [] # [Vector3 local, Vector4 custom]
var _sounds: Array = [] # AudioStreamPlayer3D pool
var _sound_next := 0
var _prev_clock := -1.0
var _buoys: Array = [] # Buoy
var _blast_seen := 0
var _sea_state: Array = []
var _eye_w := Vector3.ZERO
var _web := false
## Staged events for stills and checks: each an event dictionary like the hashed ones.
var _forced: Array = []
## Set by stage_for_shot(): the clock stands still, so every shot of a still's load sees the
## staged moment (a load's later shots stream for many frames at full speed).
var hold_clock := false
## Counted for the checks: what the last draw put out, by kind.
var drawn: Dictionary = {}


class Buoy:
	var at := Vector2.ZERO
	var yaw := 0.0
	var lions := 0
	var lion_seed: Array = []
	var scared_at := -1e9
	var back_at := -1e9
	var xf := Transform3D()
	var xf_t := -1e9
	var index := 0


func _ready() -> void:
	_live = self
	_web = OS.has_feature("web")
	if OS.get_environment("SEA_LIFE") == "0":
		enabled = false
	for k: String in KINDS:
		for lod in 2:
			var mmi := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = SeaLifeMesh.mesh(k, lod)
			mm.instance_count = 0
			mmi.multimesh = mm
			mmi.material_override = material(k)
			mmi.name = "SeaLife_%s_%d" % [k, lod]
			# Neither level casts: the near one's shadow comes from the far mesh (below), into
			# every cascade; a dolphin 200 m off throws a shadow of a pixel.
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mmi.visible = false
			add_child(mmi)
			_mm["%s:%d" % [k, lod]] = mmi
		var twin := MultiMeshInstance3D.new()
		var tm := MultiMesh.new()
		tm.transform_format = MultiMesh.TRANSFORM_3D
		tm.use_colors = true
		tm.use_custom_data = true
		tm.mesh = SeaLifeMesh.mesh(k, 1)
		tm.instance_count = 0
		twin.multimesh = tm
		twin.material_override = material(k)
		twin.name = "SeaLifeShadow_%s" % k
		twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		twin.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		twin.visible = false
		add_child(twin)
		_shadow[k + ":0"] = twin
	_spray = MultiMeshInstance3D.new()
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.use_custom_data = true
	sm.mesh = SeaLifeMesh.mesh("spray", 0)
	sm.instance_count = 0
	_spray.multimesh = sm
	_spray.material_override = spray_material()
	_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spray.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_spray.name = "SeaLife_spray"
	_spray.visible = false
	add_child(_spray)
	for i in 6:
		var p := AudioStreamPlayer3D.new()
		p.name = "SeaSound_%d" % i
		p.unit_size = 10.0
		p.attenuation_filter_cutoff_hz = 7000.0
		var sfx := get_node_or_null("/root/Sfx")
		if sfx != null and sfx.has_method("bus_for"):
			p.bus = sfx.bus_for("sea_life")
		add_child(p)
		_sounds.append(p)


func _exit_tree() -> void:
	if _live == self:
		_live = null


static var _materials: Dictionary = {}

## One shared material per kind (its pivots, eye and surfaces from SeaLifeMesh's numbers).
static func material(k: String) -> ShaderMaterial:
	if _materials.has(k):
		return _materials[k]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sea_life.gdshader")
	m.set_shader_parameter("kind", KINDS.find(k))
	match k:
		"dolphin":
			m.set_shader_parameter("hinge", SeaLifeMesh.DOLPHIN_HINGE)
			m.set_shader_parameter("tail_end", SeaLifeMesh.DOLPHIN_LEN * 0.55)
			m.set_shader_parameter("beat_reach", 0.16)
			m.set_shader_parameter("beat_wave", 1.4)
			m.set_shader_parameter("eye_pos", Vector3(0.1, 0.025, -0.985))
			m.set_shader_parameter("eye_r", 0.017)
		"sea_lion":
			m.set_shader_parameter("neck", Vector3(0.0, SeaLifeMesh.SEA_LION_NECK_Y, SeaLifeMesh.SEA_LION_NECK))
			m.set_shader_parameter("jaw_hinge", Vector3(0.0, 0.2, -SeaLifeMesh.SEA_LION_LEN * 0.5 + 0.1 * SeaLifeMesh.SEA_LION_LEN))
			m.set_shader_parameter("eye_pos", Vector3(0.058, 0.245, -0.765))
			m.set_shader_parameter("eye_r", 0.014)
			m.set_shader_parameter("body_roughness", 0.4)
		"pelican":
			m.set_shader_parameter("shoulder", SeaLifeMesh.PELICAN_SHOULDER)
			m.set_shader_parameter("wrist_x", SeaLifeMesh.PELICAN_WRIST)
		"whale":
			m.set_shader_parameter("hinge", SeaLifeMesh.WHALE_HINGE)
			m.set_shader_parameter("tail_end", SeaLifeMesh.WHALE_LEN * 0.55)
			m.set_shader_parameter("beat_reach", 0.6)
			m.set_shader_parameter("beat_wave", 0.35)
			m.set_shader_parameter("eye_pos", Vector3(0.98, -0.15, -3.9))
			m.set_shader_parameter("eye_r", 0.06)
			m.set_shader_parameter("body_roughness", 0.3)
	_materials[k] = m
	return m


static var _spray_mat: ShaderMaterial = null

static func spray_material() -> ShaderMaterial:
	if _spray_mat == null:
		_spray_mat = ShaderMaterial.new()
		_spray_mat.shader = load("res://shaders/sea_spray.gdshader")
	return _spray_mat


func _setup() -> bool:
	if macro != null:
		return true
	var city := get_parent()
	if city == null or not ("plan" in city):
		return false
	plan = city.get("plan") as CityPlan
	if plan == null or plan.macro == null:
		return false
	setup_plan(plan)
	return true


## Points the system at a plan (the city's, or a check's): the buoys and their sea lions.
func setup_plan(p: CityPlan) -> void:
	plan = p
	macro = p.macro
	seed_value = p.seed
	_buoys.clear()
	for i in BUOYS.size():
		var at: Vector2 = BUOYS[i]
		if macro.zone_at(at) != MacroMap.Zone.OCEAN:
			continue
		var b := Buoy.new()
		b.at = at
		b.index = i
		b.yaw = h01([seed_value, "buoy", i]) * TAU
		b.lions = 2 + int(h01([seed_value, "lions", i]) * float(MAX_LIONS - 1))
		for j in MAX_LIONS:
			b.lion_seed.append(h01([seed_value, "lion", i, j]))
		_buoys.append(b)


func _process(delta: float) -> void:
	if _live == null:
		_live = self
	if not enabled or not _setup():
		_hide_all()
		return
	if not hold_clock:
		clock += delta
	if Explosion.blast_count != _blast_seen:
		_blast_seen = Explosion.blast_count
		var at := Explosion.last_blast_world
		startle_world(Vector2(at.x, at.z), 90.0)
	_frame()


func _frame() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		_hide_all()
		return
	_eye_w = WorldState.to_world(cam.global_position)
	_sea_state = SeaSurface.state(get_tree())
	var sounds: Array = []
	var tp := _prev_clock if _prev_clock >= 0.0 and clock - _prev_clock < 1.0 else INF
	_collect(clock, sounds, tp)
	_play_sounds(sounds)
	_prev_clock = clock
	_draw()


func _hide_all() -> void:
	for key in _mm:
		(_mm[key] as MultiMeshInstance3D).visible = false
	for key in _shadow:
		(_shadow[key] as MultiMeshInstance3D).visible = false
	if _spray:
		_spray.visible = false


# --- hashes and the coast ----------------------------------------------------------------------

static func h01(key: Array) -> float:
	return float(absi(hash(key)) % 100003) / 100003.0


## The break line's distance offshore (m) for the sea Weather is drawing.
func _break_distance() -> float:
	if _sea_state.size() >= 3:
		return Surf.break_distance(_sea_state[2])
	return 40.0


## The point `s` metres offshore of the coast line at z (true world XZ), and whether it is open
## water on a straight enough stretch for a pod to pass there.
func coast_point(z: float, s: float) -> Vector2:
	return Vector2(macro.coast_x(z) - s, z)


var _ok_cache: Dictionary = {}

func _stretch_ok(z: float, s: float) -> bool:
	# Cached by 20 m of coast and 10 m out: a pod asks every frame as it swims.
	var ck := Vector2i(roundi(z / 20.0), roundi(s / 10.0))
	if _ok_cache.has(ck):
		return _ok_cache[ck]
	if _ok_cache.size() > 4000:
		_ok_cache.clear()
	var ok := _stretch_ok_now(z, s)
	_ok_cache[ck] = ok
	return ok


func _stretch_ok_now(z: float, s: float) -> bool:
	var cx := macro.coast_x(z)
	if absf(macro.coast_x(z + 40.0) - macro.coast_x(z - 40.0)) > 36.0:
		return false
	var p := Vector2(cx - s, z)
	return macro.zone_at(p) == MacroMap.Zone.OCEAN and macro.zone_at(p + Vector2(s * 0.5, 0.0)) == MacroMap.Zone.OCEAN


var _sea_cache: Dictionary = {}

## sea_y() for an event's own point, worked out again only every 0.08 s of the clock (the swell
## moves slowly; SeaSurface.height() is ~50 us of GDScript).
func _sea_y_at(key: Variant, p: Vector2, t: float) -> float:
	var c: Array = _sea_cache.get(key, [])
	if c.size() == 3 and absf(t - float(c[0])) < 0.08 and (c[1] as Vector2).distance_squared_to(p) < 1.0:
		return c[2]
	if _sea_cache.size() > 256:
		_sea_cache.clear()
	var y := sea_y(p)
	_sea_cache[key] = [t, p, y]
	return y


## The sea's surface height at true world XZ now (y, true world).
func sea_y(p: Vector2) -> float:
	if _sea_state.is_empty():
		_sea_state = SeaSurface.state(get_tree()) if is_inside_tree() else [1.0, 0.0, Vector4(0.9, 12.0, 8.0, 38.0), Vector4.ZERO]
	return SeaSurface.height(macro, p, SeaSurface.now(), _sea_state)


func _coast_near(eye: Vector3) -> bool:
	return absf(eye.x - macro.coast_x(eye.z)) < COAST_REACH


# --- the events, pure -------------------------------------------------------------------------

static var _event_cache: Dictionary = {}

## A dolphin pod passing stretch k in window n, or {} when none does.
func pod(n: int, k: int) -> Dictionary:
	var key := [seed_value, "dolphin", n, k]
	if _event_cache.has(key):
		return _event_cache[key]
	var e := {}
	if h01(key) < DOLPHIN_ODDS:
		e = {
			"kind": "dolphin", "n": n, "k": k,
			"t0": float(n) * DOLPHIN_WINDOW + h01(key + ["t"]) * (DOLPHIN_WINDOW - DOLPHIN_RUN),
			"run": DOLPHIN_RUN,
			"dir": 1.0 if h01(key + ["d"]) < 0.5 else -1.0,
			"v": 3.6 + h01(key + ["v"]) * 1.8,
			"zc": (float(k) + 0.5) * SEG + (h01(key + ["z"]) - 0.5) * SEG * 0.5,
			"s": 45.0 + h01(key + ["s"]) * 130.0,
			"count": 4 + int(h01(key + ["c"]) * 6.0),
		}
	_cache_put(key, e)
	return e


## A pelican line passing stretch k in window n (by day), or {}.
func line(n: int, k: int) -> Dictionary:
	var key := [seed_value, "pelican", n, k]
	if _event_cache.has(key):
		return _event_cache[key]
	var e := {}
	if h01(key) < PELICAN_ODDS:
		e = {
			"kind": "pelican", "n": n, "k": k,
			"t0": float(n) * PELICAN_WINDOW + h01(key + ["t"]) * (PELICAN_WINDOW - 20.0),
			"run": PELICAN_RUN,
			"dir": 1.0 if h01(key + ["d"]) < 0.5 else -1.0,
			"v": 9.5 + h01(key + ["v"]) * 2.5,
			"zc": (float(k) + 0.5) * SEG + (h01(key + ["z"]) - 0.5) * SEG * 0.5,
			"s_share": 0.55 + h01(key + ["s"]) * 0.6,
			"height": 1.4 + h01(key + ["h"]) * 1.2,
			"spacing": 3.0 + h01(key + ["p"]) * 0.9,
			"side": 1.0 if h01(key + ["e"]) < 0.5 else -1.0,
			"count": 4 + int(h01(key + ["c"]) * 5.0),
		}
	_cache_put(key, e)
	return e


## A grey whale surfacing in whale stretch k (WHALE_SEG long) in window n, or {}.
func whale(n: int, k: int) -> Dictionary:
	var key := [seed_value, "whale", n, k]
	if _event_cache.has(key):
		return _event_cache[key]
	var e := {}
	if h01(key) < WHALE_ODDS:
		var span := WHALE_GAP * float(WHALE_BLOWS) + 10.0
		e = {
			"kind": "whale", "n": n, "k": k,
			"t0": float(n) * WHALE_WINDOW + h01(key + ["t"]) * (WHALE_WINDOW - span),
			"dir": 1.0 if h01(key + ["d"]) < 0.5 else -1.0,
			"v": 1.2 + h01(key + ["v"]) * 0.6,
			"zc": (float(k) + 0.5) * WHALE_SEG + (h01(key + ["z"]) - 0.5) * WHALE_SEG * 0.6,
			"s": 650.0 + h01(key + ["s"]) * 800.0,
		}
	_cache_put(key, e)
	return e


static func clear_cache() -> void:
	_event_cache.clear()


static func _cache_put(key: Array, e: Dictionary) -> void:
	if _event_cache.size() > 4000:
		_event_cache.clear()
	_event_cache[key] = e


## Every event that may show now round the camera: the hashed ones of the windows and stretches
## in reach, plus any staged ones.
func events_at(t: float, eye: Vector3) -> Array:
	var out: Array = []
	if macro == null:
		return out
	if _coast_near(eye):
		var kc := int(floor(eye.z / SEG))
		var nd := int(floor(t / DOLPHIN_WINDOW))
		var np := int(floor(t / PELICAN_WINDOW))
		for k in range(kc - 1, kc + 2):
			for n in range(nd - 1, nd + 1):
				var e := pod(n, k)
				if not e.is_empty() and t >= float(e.t0) - 1.0 and t <= float(e.t0) + float(e.run) + 1.0:
					out.append(e)
			for n in range(np - 3, np + 1):
				var e := line(n, k)
				if not e.is_empty() and t >= float(e.t0) - 1.0 and t <= float(e.t0) + float(e.run) + 150.0:
					out.append(e)
		var kw := int(floor(eye.z / WHALE_SEG))
		var nw := int(floor(t / WHALE_WINDOW))
		for k in range(kw - 1, kw + 2):
			for n in range(nw - 1, nw + 1):
				var e := whale(n, k)
				if not e.is_empty() and t >= float(e.t0) - 1.0 and t <= float(e.t0) + WHALE_GAP * float(WHALE_BLOWS) + 12.0:
					out.append(e)
	for e in _forced:
		out.append(e)
	return out


# --- dolphins -----------------------------------------------------------------------------------

## The dolphins of pod `e` at time t: [{pos (true world), yaw, pitch, beat, amp, tail}] for those
## near the surface, plus splashes [{pos, age, kind, size}] and sounds [{pos, t, name}] of the
## surfacings between t0 and t (for the sound pass). Pure.
func dolphins_at(e: Dictionary, t: float, out_splash: Array = [], sounds: Array = [], t_prev: float = INF) -> Array:
	var out: Array = []
	var u: float = t - float(e.t0)
	var run: float = e.run
	if u < 0.0 or u > run:
		return out
	var dir: float = e.dir
	var v: float = e.v
	var brk := _break_distance()
	var zc: float = e.zc
	var z := zc + dir * v * (u - run * 0.5)
	var s: float = brk + float(e.s) + 8.0 * sin(u * 0.05 + float(e.n))
	if not e.get("forced", false) and not _stretch_ok(z, s):
		return out
	var c := coast_point(z, s)
	var sy := _sea_y_at(["d", e.n, e.k], c, t)
	var ahead := coast_point(z + dir * 3.0, s) - c
	var fwd := Vector3(ahead.x, 0.0, ahead.y).normalized()
	var off_dir := Vector3(-1.0, 0.0, 0.0) # offshore
	var yaw := atan2(-fwd.x, -fwd.z)
	var count: int = e.count
	var key := [seed_value, "dol", e.n, e.k]
	if not e.has("members"):
		# Each dolphin's fixed numbers, hashed once and kept with the (cached) event.
		var mem: Array = []
		for j in count:
			var hj0 := h01(key + [j])
			var per := 4.2 + h01(key + [j, "p"]) * 2.6
			mem.append([hj0, (hj0 - 0.5) * 16.0 + (3.0 if j % 2 == 0 else -3.0), (h01(key + [j, "a"]) - 0.5) * 20.0, per, h01(key + [j, "f"]) * per])
		e["members"] = mem
	var members: Array = e.members
	for j in count:
		var m: Array = members[j]
		var hj: float = m[0]
		var lat: float = m[1]
		var along: float = m[2]
		var period: float = m[3]
		var phase: float = m[4]
		if e.has("sync"):
			# Staged: every dolphin is a few tenths into a leap at the staged moment.
			phase = fposmod(0.75 + 0.1 * float(j) - float(e.sync), period)
		var local := u + phase
		var cyc := int(floor(local / period))
		var tau := local - float(cyc) * period - 0.6
		var kind_h := h01(key + [j, cyc])
		if e.has("sync") and cyc == int(floor((float(e.sync) + phase) / period)):
			kind_h = 0.1
		var base := Vector3(c.x, sy, c.y) + fwd * along + off_dir * lat
		var leap := kind_h < 0.45
		var roll := not leap and kind_h < 0.85
		var body_y := -3.0
		var pitch := 0.0
		var amp := 0.85
		var fwd_extra := 0.0
		if leap:
			var H := 0.9 + h01(key + [j, cyc, "h"]) * 1.2
			var ta := sqrt(8.0 * H / GRAVITY)
			var x := tau / ta
			body_y = H * 4.0 * x * (1.0 - x)
			var vy := H * 4.0 * (1.0 - 2.0 * x) / ta
			var vh := maxf(v, 6.2)
			pitch = atan2(vy, vh)
			fwd_extra = (vh - v) * clampf(tau, -0.5, ta + 0.5)
			amp = 0.15 if x > 0.0 and x < 1.0 else 0.85
			for crossing: float in [0.0, ta]:
				var age: float = tau - crossing
				# Where the dolphin broke the water, which the pod has swum on from since.
				var cp: Vector3 = base + fwd * ((vh - v) * crossing - v * age)
				if age >= 0.0 and age < 1.5:
					out_splash.append({"pos": Vector3(cp.x, sy, cp.z), "age": age, "kind": SPRAY_SPLASH, "size": 1.0 if crossing > 0.0 else 0.7})
				var t_cross: float = t - age
				if t_prev < t_cross and t_cross <= t:
					sounds.append({"pos": Vector3(cp.x, sy, cp.z), "name": "splash", "pitch": 0.9 + hj * 0.3})
		elif roll:
			var tr := 2.2
			var x := tau / tr
			body_y = -0.6 + 0.8 * 4.0 * x * (1.0 - x)
			pitch = atan2(0.8 * 4.0 * (1.0 - 2.0 * x) / tr, v)
			var t_blow := t - (tau - tr * 0.45)
			if t_prev < t_blow and t_blow <= t:
				sounds.append({"pos": base, "name": "puff", "pitch": 0.85 + hj * 0.3})
		if body_y < -1.6:
			continue
		var pos := base + fwd * fwd_extra + Vector3(0.0, body_y, 0.0)
		out.append({"pos": pos, "yaw": yaw, "pitch": pitch, "beat": fposmod(t * 1.7 + hj, 1.0), "amp": amp, "seed": hj})
	return out


# --- pelicans -----------------------------------------------------------------------------------

## The pelicans of line `e` at time t: [{pos, yaw, pitch, roll, phase, amp, fold}], plus the
## plunges' splashes and sounds. Pure.
func pelicans_at(e: Dictionary, t: float, out_splash: Array = [], sounds: Array = [], t_prev: float = INF) -> Array:
	var out: Array = []
	var u: float = t - float(e.t0)
	if u < 0.0:
		return out
	var run: float = e.run
	var dir: float = e.dir
	var v: float = e.v
	var brk := _break_distance()
	var s: float = brk * float(e.s_share) + 10.0
	var zc: float = e.zc
	var key := [seed_value, "pel", e.n, e.k]
	var count: int = e.count
	var lead_p := coast_point(zc + dir * v * (minf(u, run) - run * 0.5), s)
	var sy_line := _sea_y_at(["p", e.n, e.k], lead_p, t)
	if not e.has("members"):
		var mem: Array = []
		for j in count:
			mem.append([h01(key + [j]), h01(key + [j, "d"]) < DIVE_ODDS, 12.0 + h01(key + [j, "t"]) * (run - 30.0), 14.0 + h01(key + [j, "s"]) * 14.0])
		e["members"] = mem
	var members: Array = e.members
	for j in count:
		var m: Array = members[j]
		var hj: float = m[0]
		var along0 := -float(j) * float(e.spacing) + (hj - 0.5) * 0.8
		var lat := float(e.side) * float(j) * (1.0 + hj * 0.6)
		var dives: bool = m[1]
		var td: float = m[2]
		if e.has("dive_at") and j == int(e.get("diver", 0)):
			dives = true
			td = float(e.dive_at)
		var t_sit: float = m[3]
		var tau := u - td
		var line_u := u
		var y_rel := float(e.height) + 0.45 * sin(u * 0.9 + float(j) * 0.7) + (hj - 0.5) * 0.4
		var pitch := 0.0
		var roll := 0.0
		var fold := 0.0
		var wave := sin(TAU * (u / 9.0) - float(j) * 0.55)
		var amp := smoothstep(0.55, 0.75, wave)
		var phase := fposmod(u * 2.1 + float(j) * 0.11, 1.0)
		var along := v * (line_u - run * 0.5) + along0
		var on_water := false
		if dives and tau >= -3.0:
			var base_along := v * (td - 3.0 - run * 0.5) + along0
			if tau < -1.1:
				var x := tau + 3.0
				along = base_along + v * (x - 0.65 * x * x / 3.8)
				var ee := smoothstep(0.0, 1.7, x)
				y_rel = lerpf(y_rel, 9.5, ee)
				pitch = 0.3 * ee
				amp = maxf(amp, 0.7 * (1.0 - ee))
			elif tau < 0.0:
				var x := (tau + 1.1) / 1.1
				along = base_along + v * (1.2825 + 0.35 * (tau + 1.1))
				y_rel = 9.5 - 10.0 * x * x
				pitch = lerpf(0.3, -1.25, smoothstep(0.0, 0.6, x))
				fold = smoothstep(0.1, 0.5, x)
				roll = -0.9 * smoothstep(0.1, 0.7, x)
				amp = 0.0
			else:
				var sit_along := base_along + v * 1.6675
				if tau < 1.0:
					continue # under the water
				if tau < t_sit:
					along = sit_along
					on_water = true
					fold = 1.0
					amp = 0.0
					pitch = lerpf(-0.6, 0.0, smoothstep(1.0, 1.8, tau))
					y_rel = lerpf(-0.6, 0.0, smoothstep(1.0, 1.5, tau))
				else:
					var x := tau - t_sit
					var acc := 3.5
					along = sit_along + (0.5 * acc * x * x if x < 3.0 else 0.5 * acc * 9.0 + acc * 3.0 * (x - 3.0))
					fold = 1.0 - smoothstep(0.0, 0.6, x)
					amp = 1.0 if x < 4.0 else smoothstep(0.55, 0.75, wave)
					phase = fposmod(x * 2.6, 1.0)
					y_rel = 1.8 * smoothstep(0.6, 3.5, x)
					pitch = 0.12 * (1.0 - smoothstep(2.0, 4.0, x))
				if tau >= 0.0 and tau < 1.8:
					var sp := coast_point(zc + dir * sit_along, s - lat)
					out_splash.append({"pos": Vector3(sp.x, sea_y(sp), sp.y), "age": tau, "kind": SPRAY_PLUNGE, "size": 1.0})
				var t_hit := t - tau
				if t_prev < t_hit and t_hit <= t:
					var sp := coast_point(zc + dir * sit_along, s - lat)
					sounds.append({"pos": Vector3(sp.x, 0.0, sp.y), "name": "plunge", "pitch": 0.9 + hj * 0.25})
		elif u > run:
			continue
		var z := zc + dir * along
		var p := coast_point(z, s - lat)
		if not e.get("forced", false) and macro.zone_at(p) != MacroMap.Zone.OCEAN:
			continue
		var sy := sea_y(p) if on_water else sy_line
		var ahead := coast_point(z + dir * 3.0, s - lat) - p
		var yaw := atan2(-ahead.x, -ahead.y)
		out.append({"pos": Vector3(p.x, sy + y_rel + (0.02 if on_water else 0.0), p.y), "yaw": yaw, "pitch": pitch,
			"roll": roll + 0.05 * sin(u * 1.3 + float(j)), "phase": phase, "amp": amp, "fold": fold, "j": j})
	return out


## The sea's mean level (a pelican high over the water needs no wave under it).
func macro_sea() -> float:
	return SeaSurface.MESH_Y


# --- the whale ---------------------------------------------------------------------------------

## The whale of event `e` at time t (an empty array between surfacings), its blows and sounds.
func whale_at(e: Dictionary, t: float, out_splash: Array = [], sounds: Array = [], t_prev: float = INF) -> Array:
	var out: Array = []
	var u: float = t - float(e.t0)
	if u < 0.0:
		return out
	var dir: float = e.dir
	var z: float = float(e.zc) + dir * float(e.v) * u
	var s: float = e.s
	if not e.get("forced", false) and not _stretch_ok(z, s):
		return out
	var c := coast_point(z, s)
	var ahead := coast_point(z + dir * 5.0, s) - c
	var yaw := atan2(-ahead.x, -ahead.y)
	for i in WHALE_BLOWS:
		var tau := u - float(i) * WHALE_GAP
		var last := i == WHALE_BLOWS - 1
		var dur := 10.0 if last else 7.0
		if tau < 0.0 or tau > dur + 6.0:
			continue
		var blow_age := tau - 0.8
		if blow_age >= 0.0 and blow_age < 6.0:
			out_splash.append({"pos": Vector3(c.x, SeaSurface.MESH_Y + 0.2, c.y) + Vector3(-ahead.x, 0.0, -ahead.y).normalized() * 3.5, "age": blow_age, "kind": SPRAY_BLOW, "size": 1.0})
		var t_blow := t - blow_age
		if t_prev < t_blow and t_blow <= t:
			sounds.append({"pos": Vector3(c.x, 1.0, c.y), "name": "blow", "pitch": 0.9})
		if tau > dur:
			continue
		var x := tau / dur
		var y := -3.2 + 2.6 * 4.0 * x * (1.0 - x)
		var pitch := atan2(2.6 * 4.0 * (1.0 - 2.0 * x) / dur, float(e.v) + 1.5) * 1.4
		var lift := 0.0
		if last:
			y = -3.2 + 2.9 * 4.0 * minf(x, 0.5) * (1.0 - minf(x, 0.5)) - 6.0 * maxf(x - 0.5, 0.0) * maxf(x - 0.5, 0.0) * 4.0
			pitch = 0.12 * (1.0 - smoothstep(0.2, 0.5, x)) - 0.5 * smoothstep(0.45, 0.85, x)
			lift = smoothstep(0.5, 0.8, x) * (1.0 - smoothstep(0.92, 1.0, x))
		out.append({"pos": Vector3(c.x, SeaSurface.MESH_Y + y, c.y), "yaw": yaw, "pitch": pitch, "beat": fposmod(t * 0.25, 1.0), "amp": 0.4, "lift": lift})
	return out


# --- the buoys and their sea lions -----------------------------------------------------------------

## The buoy's transform (true world) now: riding the swell, tilted with it, swinging slowly on its
## mooring.
func buoy_xform(b: Buoy, t: float) -> Transform3D:
	if absf(t - b.xf_t) < 0.05:
		return b.xf
	var y := sea_y(b.at)
	var sl := SeaSurface.slope(macro, b.at, SeaSurface.now(), _sea_state, 1.2) if not _sea_state.is_empty() else Vector2.ZERO
	var up := Vector3(-sl.x, 1.0, -sl.y).normalized()
	var basis := Basis(Vector3.UP, b.yaw + 0.25 * sin(t * 0.07 + float(b.index)))
	var tilt_axis := Vector3.UP.cross(up)
	if tilt_axis.length() > 1e-4:
		basis = Basis(tilt_axis.normalized(), Vector3.UP.angle_to(up) * 0.8) * basis
	b.xf = Transform3D(basis, Vector3(b.at.x, y, b.at.y))
	b.xf_t = t
	return b.xf


## The sea lions on buoy b at time t: [{xf (true world), lift, turn, bark, breath}], and the
## splashes of any going in or coming out, and the barks between t_prev and t.
func lions_at(b: Buoy, t: float, out_splash: Array = [], sounds: Array = [], t_prev: float = INF) -> Array:
	var out: Array = []
	var bx := buoy_xform(b, t)
	var deck := SeaLifeMesh.BUOY_DECK_Y
	# The bout: who barks, from when, how many times.
	var bout := int(floor(t / BOUT_SECONDS))
	var bk := [seed_value, "bout", b.index, bout]
	var barker := -1
	var barks_n := 0
	var bout_t0 := float(bout) * BOUT_SECONDS + 0.8 + h01(bk + ["t"]) * 2.5
	if h01(bk) < BOUT_ODDS:
		barker = int(h01(bk + ["who"]) * float(b.lions))
		barks_n = 3 + int(h01(bk + ["n"]) * 4.0)
	for j in b.lions:
		var hs: float = b.lion_seed[j]
		var ang := TAU * (float(j) / 3.0) + (hs - 0.5) * 0.12
		var tangent_yaw := ang + (PI * 0.5 if hs < 0.5 else -PI * 0.5)
		var spot := Vector3(sin(ang) * LION_RING, deck, cos(ang) * LION_RING)
		# Head up or down, turned this way or that: a level per lion per 8-second stretch, eased.
		var seg_len := 8.0 + hs * 5.0
		var seg := int(floor((t + hs * 20.0) / seg_len))
		var into := (t + hs * 20.0) - float(seg) * seg_len
		var lift0 := _lion_level(b, j, seg - 1)
		var lift1 := _lion_level(b, j, seg)
		var ease := smoothstep(0.0, 1.4, into)
		var lift := lerpf(lift0.x, lift1.x, ease)
		var turn := lerpf(lift0.y, lift1.y, ease)
		var bark := 0.0
		if j == barker:
			var bt := t - bout_t0
			var period := 0.55 + hs * 0.15
			if bt > -0.6 and bt < float(barks_n) * period + 0.6:
				lift = maxf(lift, smoothstep(-0.6, 0.0, bt) * (1.0 - smoothstep(float(barks_n) * period, float(barks_n) * period + 0.6, bt)))
			for i in barks_n:
				var at := bout_t0 + float(i) * period
				var a := t - at
				if a >= 0.0 and a < 0.3:
					bark = maxf(bark, sin(a / 0.3 * PI))
				if t_prev < at and at <= t:
					sounds.append({"pos": bx * (spot + Vector3(0, 0.4, 0)), "name": "bark", "pitch": 0.85 + hs * 0.35})
		# Startled: slide off the deck outward and in; back later, hauling out the same way.
		var go := b.scared_at + float(j) * 0.4 + hs * 0.6
		var back := b.back_at + float(j) * 3.0
		var off := 0.0
		if t >= go and t < back + 2.5:
			if t < go + 1.0:
				off = smoothstep(go, go + 1.0, t)
			elif t < back:
				off = 1.0
			else:
				off = 1.0 - smoothstep(back, back + 2.5, t)
		for edge: float in [go + 0.8, back]:
			var age: float = t - edge
			if age >= 0.0 and age < 1.5 and b.scared_at > -1e8:
				out_splash.append({"pos": bx * (spot * Vector3(2.1, 0.0, 2.1)), "age": age, "kind": SPRAY_SPLASH, "size": 1.3})
			if t_prev < edge and edge <= t and b.scared_at > -1e8:
				sounds.append({"pos": bx * (spot * 2.0), "name": "splash", "pitch": 0.7})
		if off >= 0.999:
			continue
		var out_dir := Vector3(sin(ang), 0.0, cos(ang))
		var pos := spot.lerp(spot + out_dir * 1.2 + Vector3(0, -deck - 0.9, 0), off)
		var basis := Basis(Vector3.UP, tangent_yaw)
		if off > 0.0:
			# Head first over the rim: the body turns outward and tips down.
			var face := atan2(-out_dir.x, -out_dir.z)
			basis = Basis(Vector3.UP, lerp_angle(tangent_yaw, face, smoothstep(0.0, 0.3, off))) * Basis(Vector3.RIGHT, -0.9 * smoothstep(0.2, 0.8, off))
			lift = lerpf(lift, 0.3, off)
		out.append({"xf": bx * Transform3D(basis, pos), "lift": lift, "turn": turn, "bark": bark, "breath": fposmod(t / (3.5 + hs) + hs, 1.0), "tint": hs})
	return out


## A sea lion's coat (an instance colour over the mesh's brown): soaked dark, or dried to tan.
static func lion_tint(h: float) -> Color:
	return Color(0.6, 0.55, 0.52).lerp(Color(1.25, 1.12, 0.98), smoothstep(0.25, 0.85, h))


## A sea lion's pose for one stretch: (lift, turn); most of the time it lies head down.
func _lion_level(b: Buoy, j: int, seg: int) -> Vector2:
	var h := h01([seed_value, "pose", b.index, j, seg])
	var lift := 0.0 if h < 0.45 else (0.45 if h < 0.75 else 1.0)
	var turn := (h01([seed_value, "turn", b.index, j, seg]) - 0.5) * 2.0
	return Vector2(lift, turn)


## Sends the sea lions on every buoy within `radius` of true world XZ `at` into the water.
func startle_world(at: Vector2, radius: float) -> void:
	for b: Buoy in _buoys:
		if b.at.distance_to(at) < radius + 30.0 and clock > b.back_at + 2.5 + float(MAX_LIONS) * 3.0:
			b.scared_at = clock
			b.back_at = clock + lerpf(SCARE_SECONDS.x, SCARE_SECONDS.y, h01([seed_value, "scare", b.index, int(clock)]))


## Pedestrian.alarm() calls this for every gunshot and blast (global position, radius).
static func startle(at_global: Vector3, radius: float) -> void:
	if _live == null or not _live.enabled or not _live.is_inside_tree() or _live.macro == null:
		return
	var w := WorldState.to_world(at_global)
	_live.startle_world(Vector2(w.x, w.z), radius * 1.5)


static func live() -> SeaLife:
	return _live


func buoys() -> Array:
	return _buoys


# --- gathering what is drawn -----------------------------------------------------------------------

func _collect(t: float, sounds: Array = [], t_prev: float = INF) -> void:
	for key in _mm:
		_lists[key] = []
	_spray_list = []
	var splash: Array = []
	var eye := _eye_w
	var dark := clampf(DayNight.lamp_now, 0.0, 1.0)
	var rough_sea := _sea_state.size() > 0 and float(_sea_state[0]) > 1.8
	for e: Dictionary in events_at(t, eye):
		match e.kind:
			"dolphin":
				for d in dolphins_at(e, t, splash, sounds, t_prev):
					_put("dolphin", d.pos, Basis.from_euler(Vector3(d.pitch, d.yaw, 0.0), EULER_ORDER_YXZ), Color(1, 1, 1), Vector4(d.beat, d.amp, 0, 0))
			"pelican":
				if (dark > 0.5 or rough_sea) and not e.get("forced", false):
					continue
				for p in pelicans_at(e, t, splash, sounds, t_prev):
					_put("pelican", p.pos, Basis.from_euler(Vector3(p.pitch, p.yaw, p.roll), EULER_ORDER_YXZ), Color(1, 1, 1), Vector4(p.phase, p.amp, p.fold, 0))
			"whale":
				for w in whale_at(e, t, splash, sounds, t_prev):
					_put("whale", w.pos, Basis.from_euler(Vector3(w.pitch, w.yaw, 0.0), EULER_ORDER_YXZ), Color(1, 1, 1), Vector4(w.beat, w.amp, w.lift, 0))
	for b: Buoy in _buoys:
		var d := Vector2(eye.x, eye.z).distance_to(b.at)
		if d > RANGES.buoy.x and _forced.is_empty():
			continue
		var lions := lions_at(b, t, splash, sounds if d < bark_reach else [], t_prev)
		_put("buoy", b.xf.origin, b.xf.basis, Color(1, 1, 1), Vector4(h01([seed_value, "lamp", b.index]), 0, 0, 0))
		for l in lions:
			var xf: Transform3D = l.xf
			# Wet near-black brown to dry tan, by the lion.
			var tint := lion_tint(float(l.tint))
			_put("sea_lion", xf.origin, xf.basis, tint, Vector4(l.lift, l.turn, l.bark, l.breath))
	for s in splash:
		var sp: Vector3 = s.pos
		if sp.distance_to(eye) < (SPRAY_RANGE if float(s.kind) == SPRAY_BLOW else 700.0):
			_spray_list.append([sp, Vector4(s.age, s.kind, s.size, 1.5)])


func _put(k: String, pos_w: Vector3, basis: Basis, tint: Color, custom: Vector4) -> void:
	var r: Vector2 = RANGES[k]
	var d := pos_w.distance_to(_eye_w)
	if d > r.x:
		return
	var key := "%s:%d" % [k, 0 if d < r.y else 1]
	(_lists[key] as Array).append([Transform3D(basis, pos_w), tint, custom])


func _local(w: Vector3) -> Vector3:
	return to_local(WorldState.to_local(w))


func _draw() -> void:
	drawn.clear()
	var inv := global_transform.affine_inverse()
	var shift := WorldState.to_local(Vector3.ZERO)
	for key in _mm:
		var mmi: MultiMeshInstance3D = _mm[key]
		var mm := mmi.multimesh
		var items: Array = _lists.get(key, [])
		var n := items.size()
		drawn[key] = n
		var twin: MultiMeshInstance3D = _shadow.get(key)
		if n == 0:
			if mmi.visible:
				mm.visible_instance_count = 0
				mmi.visible = false
			if twin and twin.visible:
				twin.visible = false
			continue
		if mm.instance_count < n:
			mm.instance_count = 0
			mm.instance_count = int(ceil(float(n) / 8.0)) * 8
		var buf := PackedFloat32Array()
		buf.resize(mm.instance_count * 20)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		var i := 0
		for it in items:
			var xf: Transform3D = inv * Transform3D((it[0] as Transform3D).basis, (it[0] as Transform3D).origin + shift)
			var b := xf.basis
			var o := xf.origin
			var c: Color = it[1]
			var cu: Vector4 = it[2]
			buf[i] = b.x.x
			buf[i + 1] = b.y.x
			buf[i + 2] = b.z.x
			buf[i + 3] = o.x
			buf[i + 4] = b.x.y
			buf[i + 5] = b.y.y
			buf[i + 6] = b.z.y
			buf[i + 7] = o.y
			buf[i + 8] = b.x.z
			buf[i + 9] = b.y.z
			buf[i + 10] = b.z.z
			buf[i + 11] = o.z
			buf[i + 12] = c.r
			buf[i + 13] = c.g
			buf[i + 14] = c.b
			buf[i + 15] = 1.0
			buf[i + 16] = cu.x
			buf[i + 17] = cu.y
			buf[i + 18] = cu.z
			buf[i + 19] = cu.w
			i += 20
			lo = lo.min(o)
			hi = hi.max(o)
		mm.buffer = buf
		mm.visible_instance_count = n
		var pad := 9.0 if key.begins_with("whale") else 3.5
		mmi.custom_aabb = AABB(lo, hi - lo).grow(pad)
		mmi.visible = true
		if twin:
			var tm := twin.multimesh
			if tm.instance_count != mm.instance_count:
				tm.instance_count = 0
				tm.instance_count = mm.instance_count
			tm.buffer = buf
			tm.visible_instance_count = n
			twin.custom_aabb = mmi.custom_aabb
			twin.visible = true
	var n := _spray_list.size()
	drawn["spray"] = n
	var sm := _spray.multimesh
	if n == 0:
		_spray.visible = false
		return
	if sm.instance_count < n:
		sm.instance_count = 0
		sm.instance_count = int(ceil(float(n) / 8.0)) * 8
	var sb := PackedFloat32Array()
	sb.resize(sm.instance_count * 16)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var i := 0
	for s in _spray_list:
		var o: Vector3 = inv * ((s[0] as Vector3) + shift)
		var cu: Vector4 = s[1]
		sb[i] = 1.0
		sb[i + 3] = o.x
		sb[i + 5] = 1.0
		sb[i + 7] = o.y
		sb[i + 10] = 1.0
		sb[i + 11] = o.z
		sb[i + 12] = cu.x
		sb[i + 13] = cu.y
		sb[i + 14] = cu.z
		sb[i + 15] = cu.w
		i += 16
		lo = lo.min(o)
		hi = hi.max(o)
	sm.buffer = sb
	sm.visible_instance_count = n
	_spray.custom_aabb = AABB(lo, hi - lo).grow(12.0)
	_spray.visible = true


# --- sound -----------------------------------------------------------------------------------------

func _play_sounds(sounds: Array) -> void:
	for s in sounds:
		var reach := splash_reach
		var db := splash_db
		match s.name:
			"bark":
				reach = bark_reach
				db = bark_db
				barks += 1
			"blow":
				reach = blow_reach
				db = blow_db
			"puff":
				reach = 70.0
				db = splash_db - 4.0
			_:
				splashes += 1
		var pos: Vector3 = s.pos
		if pos.distance_to(_eye_w) > reach:
			continue
		var p: AudioStreamPlayer3D = _sounds[_sound_next]
		_sound_next = (_sound_next + 1) % _sounds.size()
		p.stream = SeaSounds.stream(s.name)
		p.volume_db = db
		p.max_distance = reach
		p.pitch_scale = float(s.pitch)
		p.position = _local(pos)
		p.play()


# --- staging (stills and checks) -------------------------------------------------------------------

## Stages `kind` ("dolphin", "pelican", "dive", "whale", "sealion") at true world XZ `at` (moved
## onto the nearest open water off the coast for the coast's kinds), `lead` seconds into it at
## the moment of the call; returns the true world point it stands at.
func stage(kind: String, at: Vector2, lead: float = 2.0, keep: bool = false) -> Vector3:
	if not _setup() and macro == null:
		return Vector3.ZERO
	if not keep:
		_forced.clear()
	var brk := _break_distance()
	var s := maxf(macro.coast_x(at.y) - at.x, 5.0)
	match kind:
		"dolphin":
			var e := {"kind": "dolphin", "n": 9001, "k": 0, "t0": clock - DOLPHIN_RUN * 0.5, "run": DOLPHIN_RUN,
				"dir": 1.0, "v": 4.5, "zc": at.y, "s": maxf(s - brk, 10.0), "count": 6, "forced": true, "sync": DOLPHIN_RUN * 0.5 + lead}
			_forced.append(e)
		"pelican", "dive":
			var e := {"kind": "pelican", "n": 9002, "k": 0, "t0": clock - PELICAN_RUN * 0.5 - lead, "run": PELICAN_RUN,
				"dir": 1.0, "v": 10.5, "zc": at.y, "s_share": maxf(s - 10.0, 5.0) / maxf(brk, 1.0), "height": 1.8, "spacing": 3.4,
				"side": 1.0, "count": 6, "forced": true}
			e["t0"] = clock - PELICAN_RUN * 0.5
			if kind == "dive":
				# `lead` seconds before the diver (the second bird) hits the water at `at`.
				e["dive_at"] = PELICAN_RUN * 0.5 + lead
				e["diver"] = 1
				e["zc"] = at.y - (10.5 * (lead - 1.3325) - 3.4)
			_forced.append(e)
		"whale":
			_forced.append({"kind": "whale", "n": 9003, "k": 0, "t0": clock - lead, "dir": 1.0, "v": 1.4, "zc": at.y, "s": s, "forced": true})
		"sealion":
			pass
	return Vector3(macro.coast_x(at.y) - s, SeaSurface.MESH_Y, at.y)


func clear_stage() -> void:
	_forced.clear()


## Moves the clock `seconds` on (the events are functions of it) and draws.
func advance(seconds: float) -> void:
	clock += seconds
	if _setup() and is_inside_tree():
		_frame()


## For still_shot.gd SEA: "kind[@x,z[,lead]];..." (dolphin, pelican, dive, whale): each kind
## staged at true world XZ x,z (or `dist` metres ahead of the camera), `lead` seconds before its
## moment (default `lead`); the clock then stands still (SEA_HOLD=0 lets it run). Prints each
## spot.
func stage_for_shot(spec: String, cam: Camera3D, dist: float, lead: float) -> void:
	if not _setup():
		print("SEA: no plan")
		return
	var eye := WorldState.to_world(cam.global_position)
	var f := -cam.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	_forced.clear()
	hold_clock = OS.get_environment("SEA_HOLD") != "0"
	for item in spec.split(";", false):
		var kind := item.get_slice("@", 0)
		var at := Vector2(eye.x + f.x * dist, eye.z + f.z * dist)
		var ld := lead
		if item.contains("@"):
			var nums := item.get_slice("@", 1).split(",")
			at = Vector2(float(nums[0]), float(nums[1]))
			if nums.size() > 2:
				ld = float(nums[2])
		if kind == "sealion":
			print("SEA sea lions on the buoys ", _buoys.map(func(b): return b.at))
			continue
		var p := stage(kind, at, ld, true)
		print("SEA staged %s at %s (eye %s)" % [kind, p, eye])
