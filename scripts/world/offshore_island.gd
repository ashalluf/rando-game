class_name OffshoreIsland
extends Node
## The island on the horizon offshore: Isla Calandra, the form of the Channel Islands (an
## original name; its one town is Puerto Calandra). 30-40 km out across the water, three times
## past the camera's 12 km far plane, so it is drawn by the sky (shaders/offshore_island.gdshaderinc,
## included by sky.gdshader): a height field in true-world kilometres that each sky pixel's ray
## is followed across. This node is its data and its weather: DayNight makes it as a child (next
## to SkyExtras), it pushes the shape once and, every frame, how much of it the air lets through -
## pale blue on a clear day, crisp in a Santa Ana, hazier in the golden-hour smog, faint under
## overcast, gone in the marine layer and the rain - and the town's lights after dark.
## ISLAND=0 in the environment (or -- --no-island) leaves it out (the A/B).

## The footprint, true world metres: centre, long axis, half length, greatest half width.
## From the beach town (-900, 0) the centre is 36 km out a little south of west, so the island
## spans the sunset's side of the horizon (its north point near due west); from the hills and
## downtown it is 38-42 km off.
const CENTRE := Vector2(-33500.0, 15200.0)
const AXIS := Vector2(0.6, 0.8)
const HALF_LEN := 17000.0
const HALF_WID := 4200.0
## The main ridge's highest (metres).
const PEAK := 1050.0
## Where the town is along the island (-1..1 of the half length, the larger half) and how far in
## from the greatest half width toward the axis (it sits in a bay, lights up the hill behind).
const TOWN_U := -0.42
const TOWN_IN := 0.55
const SHAPE_SEED := 3.7

## Visibility by weather (Weather.State order: clear, overcast, rain, storm, marine, Santa Ana).
const AMOUNT_BY_STATE := [1.0, 0.3, 0.0, 0.0, 0.0, 1.0]
## The haze distance (km) by weather: 1 - exp(-d / haze) of the island is air.
const HAZE_BY_STATE := [26.0, 15.0, 8.0, 6.0, 8.0, 75.0]
## Golden hour's smog takes this share off the haze distance.
@export var golden_haze_cut: float = 0.35
## How dark the island stands against a low sun behind it (sky shader `island_glare`).
@export var sunset_glare: float = 0.62
## Land albedo (the sky's colour space, linear numbers).
@export var land_color: Color = Color(0.105, 0.092, 0.062)

var _sky: ShaderMaterial
var _day: Node
var _weather: Node
var _looked := false


static func enabled() -> bool:
	if OS.get_environment("ISLAND") == "0":
		return false
	return not OS.get_cmdline_user_args().has("--no-island")


## The town's place (true world metres) and the coast's outward direction there (unit).
static func town() -> Array:
	var perp := Vector2(-AXIS.y, AXIS.x)
	# The side that faces the mainland (the world origin).
	var side := signf(perp.dot(-CENTRE))
	var out := perp * side
	var p := CENTRE + AXIS * (TOWN_U * HALF_LEN) + out * (HALF_WID * TOWN_IN * 0.75)
	return [p, out]


## Bearing (radians, from +X toward +Z) and distance (m) of the island's centre from a point.
static func seen_from(at: Vector2) -> Vector2:
	var r := CENTRE - at
	return Vector2(atan2(r.y, r.x), r.length())


func setup(sky: ShaderMaterial, day: Node) -> void:
	_sky = sky
	_day = day
	var t := town()
	_sky.set_shader_parameter("island_centre", CENTRE / 1000.0)
	_sky.set_shader_parameter("island_axis", AXIS.normalized())
	_sky.set_shader_parameter("island_half_len", HALF_LEN / 1000.0)
	_sky.set_shader_parameter("island_half_wid", HALF_WID / 1000.0)
	_sky.set_shader_parameter("island_peak", PEAK / 1000.0)
	_sky.set_shader_parameter("island_seed", SHAPE_SEED)
	_sky.set_shader_parameter("island_town", (t[0] as Vector2) / 1000.0)
	_sky.set_shader_parameter("island_town_out", t[1])
	_sky.set_shader_parameter("island_land", Vector3(land_color.r, land_color.g, land_color.b))
	_sky.set_shader_parameter("island_glare", sunset_glare)
	_push()


func _process(_delta: float) -> void:
	_push()


## What the weather and the hour let through, as (amount, haze km, lights).
static func air(weights: Array, golden: float, night: float, haze_cut: float) -> Vector3:
	var amount := 0.0
	var haze := 0.0
	var total := 0.0
	for i in weights.size():
		var w: float = weights[i]
		amount += w * AMOUNT_BY_STATE[i]
		haze += w * HAZE_BY_STATE[i]
		total += w
	if total <= 0.001:
		amount = 1.0
		haze = HAZE_BY_STATE[0]
	else:
		amount /= total
		haze /= total
	haze *= 1.0 - haze_cut * clampf(golden, 0.0, 1.0)
	# The lights: from dusk; their glow carries further than the land's colour does.
	var lights := smoothstep(0.25, 0.8, night)
	return Vector3(clampf(amount, 0.0, 1.0), haze, lights)


func _push() -> void:
	if _sky == null:
		return
	if not _looked:
		_looked = true
		var scene := get_tree().current_scene if is_inside_tree() else null
		if scene:
			_weather = scene.find_child("Weather", true, false)
	var weights := []
	if _weather and _weather.has_method("weight_of"):
		for s in 6:
			weights.append(float(_weather.call("weight_of", s)))
	var golden := float(_day.get("golden")) if _day else 0.0
	var night := float(_day.get("night_factor")) if _day else 0.0
	var a := air(weights, golden, night, golden_haze_cut)
	_sky.set_shader_parameter("island_amount", a.x)
	_sky.set_shader_parameter("island_haze_km", a.y)
	_sky.set_shader_parameter("island_lights", a.z)
