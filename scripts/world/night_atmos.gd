class_name NightAtmos
extends Node
## The night street's air (2026-10-30, wave 3, "the GTA 6 night look"; docs/HANDOFF.md "Night
## street atmosphere"): soft halos round every street lamp head, lit shop front and car lamp, a
## drawn cone of light under each lamp in mist and rain, a thin lens streak on the brightest
## lights the camera looks straight at, and a wet sodium haze in the street canyon.
##
## All of it is cheap by construction:
##   * Lamp halos and shafts are two more instances in each lamp's own prop record
##     (`CityChunk._add_street_lamp()`), so they are the chunk's batch (one draw per kind a chunk),
##     go out with the lamp (their keys hold PropBreak's glow words, "glow" and "beam") and are
##     never thrown as pieces. Shop halos ride the chunk's shop spill. Car halos are four more
##     quads in PropFactory.vehicle_lights() (car_lights.gdshader parts 6 and 7).
##   * Everything is sized, faded and turned to the camera in the shaders
##     (shaders/night_halo.gdshaderinc), off one global, `night_atmos` (x haze, y shaft gain, z
##     halo gain, w viewport height), which this node pushes four times a second. Nothing per
##     lamp runs on the CPU at all.
##   * By day lamp_factor is 0 and every quad collapses in the vertex stage.
##
## The haze is worked out from the weather (`haze_for()`, pure): faint on a Santa Ana night,
## moderate when clear, heavy in rain, the marine layer and a storm. Shafts are drawn only where
## Forward+'s volumetric fog is off (`shaft_gain_for()`): the volume already lights the air round
## the lamps' OmniLights, and the drawn cone on top of it doubled them.
##
## The canyon's sodium haze is the Environment's own depth fog: after DayNight and Weather have
## written it this frame, this node (process_priority 50) leans its colour toward sodium and
## thickens it a little, by the haze, the lamps and how close the camera is to the street
## (`sodium_for()`, pure). It never accumulates: it remembers what it wrote and starts from the
## others' value each frame (when they did not write, it puts its own change back first).
##
## NIGHT_HAZE=<0..1> holds the haze for stills. NIGHT_ATMOS=0 in the environment is the A/B: no halo or shaft instances, no car halo quads, no
## fog change, the global's halo gain 0.

static var enabled: bool = OS.get_environment("NIGHT_ATMOS") != "0"

const HALO_KEY := "atmos_glow_halo"
const SHAFT_KEY := "atmos_beam_shaft"
const SHOP_KEY := "atmos_shop_glow"
## A FULL lamp's reflection in the wet road (night_wet.gdshader; the night street review): the key
## holds "glow" so PropBreak treats it as the lamp's light.
const WET_KEY := "atmos_glow_wet"
const WET_DISTANCE := 160.0
## A reflection's strength per light of the lamp (a twin globe's two heads make one brighter streak).
const WET_PER_LIGHT := 0.7
const WET_MAX := 1.4

## Haze per Weather.State (CLEAR, OVERCAST, RAIN, STORM, MARINE, SANTA_ANA).
const HAZE_BY_STATE := [0.3, 0.45, 0.8, 0.95, 0.92, 0.06]
## A lamp halo's base radius (metres) and its shop front's range.
const LAMP_HALO := 0.7
const SHOP_HALO_MIN := 1.2
const SHOP_HALO_MAX := 3.0
## How high a shop front's glow sits over the pavement (the shop window's middle).
const SHOP_HALO_Y := 2.3
## The shaft's foot as a share of the lamp's pool.
const SHAFT_FOOT := 0.4
## Halo colours, a little deeper than the lamps' light (a halo is the lamp's colour seen through
## more of the air, which takes the white out of it). Raw, like every instance colour.
const HALO_SODIUM := Color(1.0, 0.66, 0.3)
const HALO_LED := Color(0.82, 0.9, 1.0)
## The street's sodium haze: the most the fog colour leans to sodium, and fog density added (per
## metre, at full haze and lamps), and the camera height over the street where it is gone.
const SODIUM_FOG := Color(0.62, 0.36, 0.14)
const SODIUM_LEAN := 0.42
const SODIUM_DENSITY := 0.0011
const SODIUM_TOP := 140.0
const DRAW_DISTANCE := 900.0
const SHAFT_DISTANCE := 90.0

## The city's node, by instance id (a static holding the node itself outlived it at exit).
static var _node_id: int = 0
static var _meshes: Dictionary = {}

## Last values pushed (the checks read them: the dummy renderer reads globals back as null).
var pushed: Vector4 = Vector4.ZERO
var haze: float = 0.3
var shaft_gain: float = 1.0
var halo_gain: float = 1.0
## The camera's height over the street, when a check stages it (-1: measured).
var cam_height_override: float = -1.0
var _timer: float = 0.0
var _env: Environment
var _wrote_color: Color = Color(-1, -1, -1)
var _base_color: Color
var _wrote_density: float = -1.0
var _base_density: float = 0.0


## The air's wetness for a weather (Weather.State `state`, blending from `previous` by `blend`),
## its rain level, the marine layer at the camera (Weather.marine_here) and the street's wetness.
static func haze_for(state: int, previous: int, blend: float, rain: float, marine_here: float, wetness: float) -> float:
	var a: float = HAZE_BY_STATE[clampi(previous, 0, HAZE_BY_STATE.size() - 1)]
	var b: float = HAZE_BY_STATE[clampi(state, 0, HAZE_BY_STATE.size() - 1)]
	var h := lerpf(a, b, clampf(blend, 0.0, 1.0))
	h = maxf(h, 0.3 + 0.6 * clampf(rain, 0.0, 1.0))
	h = maxf(h, 0.9 * clampf(marine_here, 0.0, 1.0))
	# A soaked street breathes for a while after the rain.
	h += 0.12 * clampf(wetness, 0.0, 1.0) * (1.0 - h)
	# Santa Ana air stays dry whatever the street is.
	if state == 5:
		h = lerpf(h, HAZE_BY_STATE[5], clampf(blend, 0.0, 1.0))
	return clampf(h, 0.0, 1.0)


## Shafts are drawn only where nothing else draws the lamps' light in the air.
static func shaft_gain_for(volumetric_fog: bool) -> float:
	return 0.0 if volumetric_fog else 1.0


## Quality: the lowest level keeps the halos dim and drops the shafts.
static func halo_gain_for(quality_level: int) -> float:
	return 0.6 if quality_level >= 3 else 1.0


## [colour lean, density added] for the canyon's sodium haze.
static func sodium_for(lamp: float, h: float, cam_height: float) -> Vector2:
	var street := 1.0 - smoothstep(12.0, SODIUM_TOP, cam_height)
	var k := clampf(lamp, 0.0, 1.0) * h * street
	return Vector2(SODIUM_LEAN * k, SODIUM_DENSITY * k * h)


# --- Instances ------------------------------------------------------------------------------

## The halo and shaft instances for one street lamp, in the chunk's batch format
## ([key, mesh, xform, colour, custom]): a halo at each of its `lights` (chunk-local, before the
## relief), a shaft from `head` down to `foot_y` a `pool` wide. `full` false (LOD chunks): halos
## only, the shafts are a near thing. Empty with the A/B off.
static func lamp_parts(lights: Array, head: Vector3, foot_y: float, pool: float, world_xz: Vector2, full: bool) -> Array:
	if not enabled:
		return []
	var col := HALO_LED if NightCity.lamp_led(world_xz) else HALO_SODIUM
	var out: Array = []
	for l: Vector3 in lights:
		out.append([HALO_KEY, halo_mesh(), Transform3D(Basis.from_scale(Vector3.ONE * LAMP_HALO), l + Vector3(0.0, -0.12, 0.0)), col, Color(1.0, 0.0, 0.0, 0.0)])
	var h := head.y - foot_y
	if full and h > 1.5:
		var r := maxf(pool * SHAFT_FOOT, 1.2)
		out.append([SHAFT_KEY, shaft_mesh(), Transform3D(Basis.from_scale(Vector3(r, h, r)), head + Vector3(0.0, -0.2, 0.0)), col, Color(1.0, 0.0, 0.0, 0.0)])
	if full and h > 1.5 and NightStreetReview.enabled:
		# The reflection: on the ground under the head, its height in the basis' y.
		out.append([WET_KEY, wet_mesh(), Transform3D(Basis.from_scale(Vector3(1.0, h, 1.0)), Vector3(head.x, foot_y, head.z)), col, Color(minf(float(lights.size()) * WET_PER_LIGHT, WET_MAX), 0.0, 0.0, 0.0)])
	return out


## A shop front's glow, for a pool of Building.shop_pools (its transform in the chunk, colour).
## Null with the A/B off.
static func shop_part(xf: Transform3D, color: Color, foot_y: float) -> Variant:
	if not enabled:
		return null
	var out_dir := xf.basis.y
	out_dir.y = 0.0
	if out_dir.length_squared() < 1e-6:
		return null
	out_dir = out_dir.normalized()
	var wide := xf.basis.x.length()
	var s := clampf(wide * 0.45, SHOP_HALO_MIN, SHOP_HALO_MAX)
	var at := xf.origin + out_dir * 0.6
	at.y = foot_y + SHOP_HALO_Y
	return [SHOP_KEY, halo_mesh(), Transform3D(Basis.from_scale(Vector3.ONE * s), at), Color(color.r, color.g, color.b), Color(clampf(color.a, 0.2, 1.5), 1.0, 0.0, 0.0)]


## After a chunk's batch keys are filled: no shadows, the draw distances.
static func finish_batch(batch: MultiMeshBatch) -> void:
	for k: String in [HALO_KEY, SHAFT_KEY, SHOP_KEY, WET_KEY]:
		batch.set_no_shadow(k)
	batch.set_draw_distance(WET_KEY, WET_DISTANCE)
	batch.set_draw_distance(HALO_KEY, DRAW_DISTANCE)
	batch.set_draw_distance(SHAFT_KEY, SHAFT_DISTANCE)
	batch.set_draw_distance(SHOP_KEY, 220.0)


## One quad, corners at +-1 (the shader turns it to the camera and sizes it). Its bounds cover the
## largest halo and streak the shader can draw, or a halo at the frame's edge would be culled.
static func halo_mesh() -> Mesh:
	if _meshes.has("halo"):
		return _meshes.halo
	var m := ArrayMesh.new()
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)])
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	m.surface_set_material(0, atmos_material("halo"))
	m.custom_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	_meshes.halo = m
	return m


## The wet reflection's quad (corners at +-1; night_wet.gdshader lays it on the road toward the
## camera). Its bounds cover the longest streak the shader lays from the lamp's foot.
static func wet_mesh() -> Mesh:
	if _meshes.has("wet"):
		return _meshes.wet
	var m := (halo_mesh() as ArrayMesh).duplicate() as ArrayMesh
	m.surface_set_material(0, atmos_material("wet"))
	m.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 4, 80))
	_meshes.wet = m
	return m


## An open unit cone: the top ring at y 0 (radius 0.12), the floor ring at y -1 (radius 1), with
## a ring between so the fade down it is not one long interpolation.
static func shaft_mesh() -> Mesh:
	if _meshes.has("shaft"):
		return _meshes.shaft
	const SIDES := 18
	var rings := [[0.0, 0.12], [-0.45, 0.6], [-1.0, 1.0]]
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for r: Array in rings:
		for i in SIDES:
			var t := TAU * float(i) / float(SIDES)
			v.append(Vector3(cos(t) * float(r[1]), float(r[0]), sin(t) * float(r[1])))
	for ring in rings.size() - 1:
		for i in SIDES:
			var a := ring * SIDES + i
			var b := ring * SIDES + (i + 1) % SIDES
			idx.append_array([a, b, a + SIDES, b, b + SIDES, a + SIDES])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, atmos_material("shaft"))
	_meshes.shaft = m
	return m


static func atmos_material(kind: String) -> ShaderMaterial:
	var key := "mat_" + kind
	if _meshes.has(key):
		return _meshes[key]
	var mat := ShaderMaterial.new()
	mat.shader = load({"halo": "res://shaders/night_halo.gdshader", "wet": "res://shaders/night_wet.gdshader"}.get(kind, "res://shaders/night_shaft.gdshader"))
	if kind == "wet" or kind == "shaft":
		RainStreetNight.dress_wet(mat)
	_meshes[key] = mat
	return mat


# --- The node -------------------------------------------------------------------------------

## Makes the node (once per city) under `city` (the CityStreamer, the scene root in the game,
## which holds Weather, DayNight and Quality). Called by the first lamp a chunk builds; safe to
## call any number of times.
static func ensure(city: Node) -> void:
	if not enabled or node() != null or city == null:
		return
	var n := NightAtmos.new()
	n.name = "NightAtmos"
	_node_id = n.get_instance_id()
	city.add_child.call_deferred(n)


## The city's node, or null.
static func node() -> NightAtmos:
	return instance_from_id(_node_id) as NightAtmos if _node_id != 0 else null


func _ready() -> void:
	process_priority = 50
	_push()
	WetCarGlints.ensure(get_parent())


func _exit_tree() -> void:
	if _node_id == get_instance_id():
		_node_id = 0
		# The city is going (a quit or a rebuild): its chunks go with it, so the cached meshes and
		# materials go too rather than outliving the renderer in a static at exit.
		_meshes.clear()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		_push()
	_sodium()


func _scene_node(n: String) -> Node:
	var s := get_parent()
	return s.get_node_or_null(n) if s else null


func _environment() -> Environment:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.environment:
		return cam.environment
	var w := get_viewport().world_3d
	return w.environment if w else null


## The global, four times a second.
func _push() -> void:
	var w := _scene_node("Weather")
	if w:
		haze = haze_for(int(w.get("state")), int(w.get("_previous")), float(w.get("blend")), float(w.get("rain_level")), float(w.get("marine_here")), float(w.get("wetness")))
	# NIGHT_HAZE=<0..1> holds the haze (stills of a scene without the city's Weather node).
	var forced := OS.get_environment("NIGHT_HAZE")
	if forced != "":
		haze = clampf(forced.to_float(), 0.0, 1.0)
	_env = _environment()
	var vol := false
	if _env and _env.volumetric_fog_enabled and not OS.has_feature("web"):
		vol = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	shaft_gain = shaft_gain_for(vol)
	var q := _scene_node("Quality")
	halo_gain = halo_gain_for(int(q.get("level"))) if q else 1.0
	if int(q.get("level") if q else 0) >= 3:
		shaft_gain = 0.0
	var vh := get_viewport().get_visible_rect().size.y if is_inside_tree() else 1080.0
	pushed = Vector4(haze, shaft_gain, halo_gain, vh)
	RenderingServer.global_shader_parameter_set("night_atmos", pushed)


## The canyon's sodium haze, after DayNight and Weather wrote the fog this frame.
func _sodium() -> void:
	if _env == null:
		return
	var col := _env.fog_light_color
	var dens := _env.fog_density
	# Nobody rewrote it since our last write: start from what it was before us.
	if col.is_equal_approx(_wrote_color):
		col = _base_color
	if is_equal_approx(dens, _wrote_density):
		dens = _base_density
	_base_color = col
	_base_density = dens
	var lamp: float = DayNight.lamp_now
	# By day (or with no haze) the lean is nothing whatever the camera's height (street <= 1):
	# skip the ground sample under the camera, the same answer as below (perf-audit-3).
	if SODIUM_LEAN * clampf(lamp, 0.0, 1.0) * haze <= 0.0005:
		_wrote_color = Color(-1, -1, -1)
		_wrote_density = -1.0
		return
	var cam := get_viewport().get_camera_3d()
	var cam_h := 0.0
	var streamer := get_parent()
	if cam and streamer and streamer.has_method("ground_height_at"):
		cam_h = cam.global_position.y - (float(streamer.call("ground_height_at", cam.global_position)) - 0.4)
	if cam_height_override >= 0.0:
		cam_h = cam_height_override
	var k := sodium_for(lamp, haze, cam_h)
	if k.x <= 0.0005:
		_wrote_color = Color(-1, -1, -1)
		_wrote_density = -1.0
		return
	_wrote_color = col.lerp(SODIUM_FOG, k.x)
	_wrote_density = dens + k.y
	_env.fog_light_color = _wrote_color
	_env.fog_density = _wrote_density
