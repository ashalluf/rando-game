class_name SkylineGlass
extends Node
## The downtown skyline's glass by day (fleet "skyline-glass-day", wave 3). The shader side is
## shaders/skyline_glass.gdshaderinc (building.gdshader, building_lod.gdshader, tower_crown.gdshader):
## the glass mirrors the sky of this hour and its clouds, the real towers round it and the sun.
## This node (DayNight's child, made in its _ready next to SkyExtras) feeds it, four times a second:
##   skyline_glass     x on, y cloud coverage, z the sun's glint gain, w golden hour
##   skyline_sky_top   DayNight's zenith (as set on the sky), w the sunward glow of a low sun
##   skyline_sky_rim   DayNight's horizon, w the light on the clouds (day 1 .. night 0.12)
##   skyline_towers_a/b  the eight boxes the glass traces: the tallest-for-their-distance of
##                     LandmarkDowntown's towers (a pair split into its two towers) and the tall
##                     parts of the Buildings standing near the camera, in TRUE world.
## `SKYLINE_GLASS=0` in the environment is the A/B: x 0, the glass exactly as before.

static var enabled: bool = OS.get_environment("SKYLINE_GLASS") != "0"

## How far round the camera a box may be traced (metres), and the shortest that counts.
const REACH := 1100.0
const MIN_HEIGHT := 45.0
## Boxes the shader traces (two mat4 globals).
const SLOTS := 8
const NONE_TOP := -100000.0
## A Building part counts when it reaches this high; parts nearer than this (metres) are the
## street's own walls and are left to the street opposite (fx_opposite) and the probes.
const PART_MIN_TOP := 40.0
const UPDATE_SECONDS := 0.25

var _last_ms: int = -1000000
var _landmarks: Array = []


static func landmark_boxes() -> Array:
	## [centre (true world xz), half size, top y] for every downtown tower, a pair as two towers.
	var out: Array = []
	for id: String in LandmarkDowntown.TOWERS:
		var row: Dictionary = LandmarkDowntown.TOWERS[id]
		var at: Vector2 = LandmarkDowntown.anchor(id)
		var plan: Vector2 = row.plan
		var top: float = LandmarkDowntown.BASE_Y + float(row.height)
		var long_x := plan.x > plan.y
		var lo := minf(plan.x, plan.y)
		var hi := maxf(plan.x, plan.y)
		if hi > lo * 2.2:
			# Two towers at the ends of the plan, each as wide as it is narrow.
			var off := (hi - lo) * 0.5
			var axis := Vector2(1.0, 0.0) if long_x else Vector2(0.0, 1.0)
			for s: float in [-1.0, 1.0]:
				out.append([at + axis * off * s, Vector2(lo, lo) * 0.5, top])
		else:
			out.append([at, plan * 0.5, top])
	return out


## The packed half size the shader decodes (round(hx * 4) + round(hz * 4) * 1024).
static func pack_half(half: Vector2) -> float:
	var hx := clampi(roundi(half.x * 4.0), 0, 1023)
	var hz := clampi(roundi(half.y * 4.0), 0, 1023)
	return float(hx + hz * 1024)


static func unpack_half(v: float) -> Vector2:
	var hz := floorf(v / 1024.0)
	return Vector2(v - hz * 1024.0, hz) * 0.25


## Pick the boxes for a camera at `cam` (true world) from candidates [centre, half, top]: the
## tallest for their distance first, at most SLOTS. Pure (the checks call it).
static func pick(cands: Array, cam: Vector3) -> Array:
	var scored: Array = []
	for c: Array in cands:
		var centre: Vector2 = c[0]
		var top: float = c[2]
		var d := centre.distance_to(Vector2(cam.x, cam.z))
		if d > REACH or top < MIN_HEIGHT:
			continue
		scored.append([top / maxf(d, 60.0), c])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out: Array = []
	for s: Array in scored:
		if out.size() >= SLOTS:
			break
		out.append(s[1])
	return out


## The two mat4 globals for a list of boxes (unused slots NONE_TOP).
static func pack(boxes: Array) -> Array[Projection]:
	var cols: Array[Vector4] = []
	for i in SLOTS:
		if i < boxes.size():
			var b: Array = boxes[i]
			cols.append(Vector4((b[0] as Vector2).x, (b[0] as Vector2).y, pack_half(b[1]), float(b[2])))
		else:
			cols.append(Vector4(0.0, 0.0, 0.0, NONE_TOP))
	return [Projection(cols[0], cols[1], cols[2], cols[3]), Projection(cols[4], cols[5], cols[6], cols[7])]


func _ready() -> void:
	_landmarks = landmark_boxes()
	if not enabled:
		RenderingServer.global_shader_parameter_set("skyline_glass", Vector4(0.0, 0.0, 0.0, 0.0))


func _process(_delta: float) -> void:
	if not enabled:
		return
	# On the real clock: a still holds the game clock all but stopped (and the wheel slows it).
	var now := Time.get_ticks_msec()
	if now - _last_ms < int(UPDATE_SECONDS * 1000.0):
		return
	_last_ms = now
	push()


## Push every global now (tests call it).
func push() -> void:
	var dn := get_parent()
	var sky: ShaderMaterial = dn.get("_sky") if dn else null
	var night: float = float(dn.get("night_factor")) if dn and dn.get("night_factor") != null else 0.0
	var golden: float = float(dn.get("golden")) if dn and dn.get("golden") != null else 0.0
	var darken: float = float(dn.get("weather_darken")) if dn and dn.get("weather_darken") != null else 0.0
	var top := Color(0.26, 0.44, 0.80)
	var rim := Color(0.42, 0.47, 0.55)
	var coverage := 0.42
	if sky:
		top = _color(sky.get_shader_parameter("sky_top"), top)
		rim = _color(sky.get_shader_parameter("sky_horizon"), rim)
		var c: Variant = sky.get_shader_parameter("cloud_coverage")
		if c != null:
			coverage = float(c)
	var sun: Vector3 = RenderingServer.global_shader_parameter_get("sun_direction")
	var low := clampf(1.0 - sun.y / 0.45, 0.0, 1.0) * clampf(sun.y / 0.05 + 0.5, 0.0, 1.0)
	var day := 1.0 - night
	# Overcast takes the sun out of the glass; an overcast sky's "clouds" are the whole sky.
	var glint := day * (1.0 - clampf(darken * 1.4, 0.0, 1.0)) * (1.0 - clampf((coverage - 0.7) / 0.25, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set("skyline_glass", Vector4(1.0, coverage * (1.0 - 0.7 * darken), glint, golden))
	RenderingServer.global_shader_parameter_set("skyline_sky_top", Vector4(top.r, top.g, top.b, low * day * (1.0 - darken)))
	RenderingServer.global_shader_parameter_set("skyline_sky_rim", Vector4(rim.r, rim.g, rim.b, lerpf(0.12, 1.0, day) * (1.0 - 0.35 * darken)))
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cam_true := Vector3.ZERO
	if cam:
		cam_true = WorldState.to_world(cam.global_position)
	var mats := pack(pick(_landmarks + _building_boxes(), cam_true))
	RenderingServer.global_shader_parameter_set("skyline_towers_a", mats[0])
	RenderingServer.global_shader_parameter_set("skyline_towers_b", mats[1])


static func _color(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is Vector3:
		return Color(v.x, v.y, v.z)
	return fallback


## The tall parts of the Buildings in the tree (FULL and LOD chunks' near buildings), true world.
func _building_boxes() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for b in get_tree().get_nodes_in_group("building"):
		var bn := b as Node3D
		if bn == null or not bn.is_inside_tree() or not ("parts" in bn):
			continue
		var origin := WorldState.to_world(bn.global_position)
		for p: Dictionary in bn.get("parts"):
			var size: Vector3 = p.get("size", Vector3.ZERO)
			var centre: Vector3 = p.get("center", Vector3.ZERO)
			var top := origin.y + centre.y + size.y * 0.5
			if top - origin.y < PART_MIN_TOP:
				continue
			out.append([Vector2(origin.x + centre.x, origin.z + centre.z), Vector2(size.x, size.z) * 0.5, top])
	return out
