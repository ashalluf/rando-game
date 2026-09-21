class_name MacroMap
extends RefCounted
## The big picture of the map: where the ocean, beach, hills and districts are, and how high the
## land is. Inspired by a west-coast basin: ocean to the west, a mountain range to the north with
## a big sign on its south face, a hilly peninsula to the south-west, downtown to the east.
## Everything here is original geography; nothing is traced from a real map.

enum Zone { CITY, BEACH, OCEAN, HILLS, AIRPORT, PORT }

const ZONE_NAMES := ["City", "Beach", "Ocean", "Hills", "Airport", "Port"]

var seed: int = 0
## X of the coastline at z = 0. West is negative X.
var coast_base_x: float = -900.0
var beach_width: float = 70.0
## North is negative Z. Land starts rising at hills_start_z and is fully mountain at hills_full_z.
## This is the front range that walls the basin off on its north side, the one the big sign sits
## on; 260 m read as a large hill, and a basin like this one is ringed by actual mountains.
var hills_start_z: float = -900.0
var hills_full_z: float = -1300.0
var hills_height: float = 560.0
## Behind the front range the ground drops into a wide inland valley - flat enough to build a
## city on, but 130 m up - and then climbs again into a much higher back range. This is the
## shape of the real thing: a coastal plain, a ridge, a valley behind it, a wall behind that.
## The front range's fade-out window and this one are the same window on purpose: the range has
## to be fully gone before the valley starts, or `zone_at()` calls the valley floor HILLS and no
## city is ever built on it. Keep `valley_to_z` at or beyond where the front range reaches zero.
var valley_from_z: float = -1500.0
var valley_to_z: float = -2100.0
var valley_height: float = 130.0
## A canyon pass cut through the front range, so roads, freeways and the player can get from the
## basin into the valley instead of hitting a 560 m wall. Without it the valley is unreachable
## on the ground and the freeway that heads for it is buried by the grade limiter.
var pass_center_x: float = 780.0
var pass_width: float = 460.0
var pass_floor: float = 55.0
var back_start_z: float = -3300.0
var back_full_z: float = -4400.0
var back_height: float = 1150.0
## And a range closing the basin off to the east, so the city is a bowl rather than a sprawl
## that runs to the edge of the world in one direction.
var east_start_x: float = 1900.0
var east_full_x: float = 2900.0
var east_height: float = 540.0
var peninsula_center: Vector2 = Vector2(-700.0, 1500.0)
var peninsula_radius: float = 550.0
## The headland in the south-west bay: cliffs straight out of the water.
var peninsula_height: float = 285.0
## Water south of this Z and west of this X (except the peninsula) so the peninsula sticks out.
var bay_z: float = 1000.0
var bay_east_x: float = 400.0
var downtown_center: Vector2 = Vector2(700.0, 250.0)
var downtown_radius: float = 330.0
var midtown_radius: float = 800.0
## A second cluster of mid-rise towers on the west side.
var westside_center: Vector2 = Vector2(-350.0, -250.0)
var westside_radius: float = 320.0
## The university campus: brick halls, quads and a bell tower on the west side.
var campus_center: Vector2 = Vector2(-620.0, -520.0)
var campus_radius: float = 250.0
## South-east of this corner is the port and industrial district.
var industrial_corner: Vector2 = Vector2(300.0, 900.0)
## Flat zones (world XZ rects): the airport by the south-west coast, the port on a harbor.
var airport_rect: Rect2 = Rect2(-880.0, 590.0, 980.0, 390.0)
## Landside of the terminal (its hall front is at z 635): the sidewalk strip people crowd, and
## the drop-off loop road in front of it, as the two closed lane paths traffic crawls around
## (world XZ; each list is a closed polyline, cars drive it in order).
var terminal_curb: Rect2 = Rect2(-440.0, 624.0, 180.0, 10.0)
var terminal_loops: Array = [
	PackedVector2Array([Vector2(-484.0, 620.5), Vector2(-216.0, 620.5), Vector2(-216.0, 599.5), Vector2(-484.0, 599.5)]),
	PackedVector2Array([Vector2(-474.0, 614.5), Vector2(-226.0, 614.5), Vector2(-226.0, 605.5), Vector2(-474.0, 605.5)]),
]
var port_rect: Rect2 = Rect2(450.0, 1000.0, 700.0, 300.0)
var harbor_rect: Rect2 = Rect2(450.0, 1300.0, 700.0, 260.0)
## Runway center lines (z) and width inside the airport rect.
var runway_zs: PackedFloat32Array = PackedFloat32Array([780.0, 870.0, 960.0])
var runway_width: float = 55.0
## Where flyable jets wait on the apron (world XZ, nose toward +X) and what kind each is.
## Staggered so no jet sits in another's taxi lane.
var apron_spots: Array = [[Vector2(-440.0, 700.0), 0], [Vector2(-350.0, 730.0), 1], [Vector2(-255.0, 670.0), 0]]

## Roads and mansion pads carved into the hills (built in setup()).
var hill_roads: HillRoads
## The freeway system: curved elevated routes across the basin (see scripts/world/freeway.gd).
var freeway: Freeway

var _noise: FastNoiseLite

## Rolling ground through the city: hills and slopes between the blocks (owner's request,
## 2026-09-19). Peak height in meters; zero on the beach, in the bay, in the flat zones
## (airport, port, harbor), on the mountain hills and around every landmark.
var relief_height: float = 22.0
var relief_frequency: float = 0.0026
var _relief: FastNoiseLite
var _landmarks: Array[Dictionary] = []


func setup() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0012
	_noise.fractal_octaves = 4
	_relief = FastNoiseLite.new()
	_relief.seed = seed + 7919
	_relief.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_relief.frequency = relief_frequency
	_relief.fractal_octaves = 3
	_relief.fractal_gain = 0.45
	_landmarks = Landmarks.all()
	var hr := HillRoads.new()
	hr.build(self, seed)
	hill_roads = hr
	# After the hill roads: the freeway's deck height follows height_at(), which needs them.
	var fw := Freeway.new()
	fw.build(self, seed)
	freeway = fw


## X of the coast at a given Z: a gentle bay curve, bulging west around the peninsula.
func coast_x(z: float) -> float:
	var x := coast_base_x + 180.0 * sin(z / 700.0)
	var d := absf(z - peninsula_center.y)
	var bulge := smoothstep(peninsula_radius * 1.2, 0.0, d) * 520.0
	return x - bulge


## Land height with hill roads and mansion pads carved in.
func height_at(pos: Vector2) -> float:
	var raw := raw_height_at(pos)
	var h := raw
	if hill_roads and raw > 0.5:
		h = hill_roads.carve(pos, raw)
	return h + _relief_at(pos, raw)


## The city's rolling ground at a world XZ (meters above the flat base). Everything a city
## chunk builds sits on this; see CityChunk._gy().
func relief_at(pos: Vector2) -> float:
	return _relief_at(pos, raw_height_at(pos))


func _relief_at(pos: Vector2, raw: float) -> float:
	if _relief == null:
		setup()
	# The valley floor is a base elevation, not rolling ground: it does not fade out near the
	# mountains, or the city built on it would slide back down to sea level at its own edges.
	var base := plateau_at(pos)
	var fade := 1.0 - smoothstep(0.0, 2.5, raw)
	if fade <= 0.0:
		return base
	var cx := coast_x(pos.y)
	fade *= smoothstep(cx + beach_width + 20.0, cx + beach_width + 220.0, pos.x)
	# The bay south of bay_z (west of bay_east_x) is water; flatten toward it.
	fade *= 1.0 - smoothstep(bay_z - 240.0, bay_z, pos.y) * (1.0 - smoothstep(bay_east_x, bay_east_x + 240.0, pos.x))
	for r: Rect2 in [airport_rect, port_rect, harbor_rect]:
		fade *= _rect_fade(pos, r, 160.0)
		if fade <= 0.0:
			return base
	for lm in _landmarks:
		var radius: float = lm.radius
		fade *= smoothstep(radius + 30.0, radius + 150.0, pos.distance_to(lm.anchor))
		if fade <= 0.0:
			return base
	var n := _relief.get_noise_2dv(pos) * 0.5 + 0.5
	return base + relief_height * n * n * fade


## 0 inside the rect, rising to 1 at `margin` meters outside it.
static func _rect_fade(pos: Vector2, r: Rect2, margin: float) -> float:
	var dx := maxf(maxf(r.position.x - pos.x, pos.x - r.end.x), 0.0)
	var dy := maxf(maxf(r.position.y - pos.y, pos.y - r.end.y), 0.0)
	return smoothstep(0.0, margin, Vector2(dx, dy).length())


## The mountains alone: the three ranges and the headland, with nothing else on top. This is
## what decides whether somewhere is HILLS rather than CITY, and what the hill roads are carved
## into, so the inland valley floor is deliberately NOT part of it - the valley is a plateau the
## city is built on, not a mountain.
func raw_height_at(pos: Vector2) -> float:
	if _noise == null:
		setup()
	if airport_rect.has_point(pos) or port_rect.has_point(pos) or harbor_rect.has_point(pos):
		return 0.0
	var n := _noise.get_noise_2dv(pos)
	var n2 := _noise.get_noise_2dv(pos * 2.7 + Vector2(913.0, -457.0))
	var h := 0.0

	# The front range, walling off the basin, fading out again on its inland side so the valley
	# behind it is open ground.
	var front := smoothstep(hills_start_z, hills_full_z, pos.y) * (1.0 - smoothstep(valley_from_z, valley_to_z, pos.y))
	var front_h := front * (hills_height * (0.62 + 0.38 * n) + 60.0 * n2)
	# The pass: inside it the front range drops to a canyon floor. Blended with smoothstep and
	# taken with minf so it only ever cuts the range down, never raises ground outside it.
	var notch := smoothstep(pass_width, pass_width * 0.3, absf(pos.x - pass_center_x))
	front_h = lerpf(front_h, minf(front_h, pass_floor + 25.0 * n2), notch)
	h = maxf(h, front_h)

	# The back range beyond the valley: the real wall.
	var back := smoothstep(back_start_z, back_full_z, pos.y)
	h = maxf(h, back * (back_height * (0.58 + 0.42 * n) + 110.0 * n2))

	# The eastern range, closing the bowl.
	var east := smoothstep(east_start_x, east_full_x, pos.x)
	h = maxf(h, east * (east_height * (0.6 + 0.4 * n) + 55.0 * n2))

	var pd := pos.distance_to(peninsula_center)
	# Steep sides: the peninsula rises out of the bay as cliffs.
	var pt := smoothstep(peninsula_radius, peninsula_radius * 0.5, pd)
	h += pt * peninsula_height * (0.7 + 0.3 * n)
	return maxf(h, 0.0)


## The inland valley floor: a smooth base elevation the city sits on, 0 everywhere in the
## coastal basin. It is part of `relief_at()` rather than `raw_height_at()` on purpose - city
## chunks lay their ground on the relief, and `zone_at()` reads the mountains, so this lifts a
## whole district 180 m without turning it into hillside.
func plateau_at(pos: Vector2) -> float:
	if airport_rect.has_point(pos) or port_rect.has_point(pos) or harbor_rect.has_point(pos):
		return 0.0
	return valley_height * smoothstep(valley_from_z, valley_to_z, pos.y)


## The bay south of the airport that wraps the peninsula: water unless on the peninsula itself.
func in_bay(pos: Vector2) -> bool:
	return pos.y > bay_z and pos.x < bay_east_x and pos.distance_to(peninsula_center) > peninsula_radius * 1.02


func zone_at(pos: Vector2) -> Zone:
	if harbor_rect.has_point(pos):
		return Zone.OCEAN
	if airport_rect.has_point(pos):
		return Zone.AIRPORT
	if port_rect.has_point(pos):
		return Zone.PORT
	var cx := coast_x(pos.y)
	if pos.x < cx or in_bay(pos):
		return Zone.OCEAN
	if raw_height_at(pos) > 3.0:
		return Zone.HILLS
	if pos.x < cx + beach_width or pos.distance_to(peninsula_center) <= peninsula_radius * 1.02:
		return Zone.BEACH # the main shore, and the low ring around the peninsula's cliffs
	return Zone.CITY


## 1 at the heart of downtown, 0 at its edge: lots there get much taller buildings.
func skyline_boost(pos: Vector2) -> float:
	var dd := pos.distance_to(downtown_center)
	return smoothstep(downtown_radius, downtown_radius * 0.3, dd)


func district_at(pos: Vector2) -> CityPlan.District:
	var dd := pos.distance_to(downtown_center)
	if dd < downtown_radius:
		return CityPlan.District.DOWNTOWN
	if pos.x > industrial_corner.x and pos.y > industrial_corner.y:
		return CityPlan.District.INDUSTRIAL
	if pos.distance_to(campus_center) < campus_radius:
		return CityPlan.District.CAMPUS
	if dd < midtown_radius or pos.distance_to(westside_center) < westside_radius:
		return CityPlan.District.MIDTOWN
	return CityPlan.District.SUBURBS


static func zone_name(z: Zone) -> String:
	return ZONE_NAMES[z]


## Colours for the land beyond the loaded chunks. These are the colours the horizon is painted
## with, so they are the average of what a district looks like from the air, not the colour of
## any one surface in it.
const BAKE_OCEAN_DEEP := Color(0.018, 0.042, 0.075)
const BAKE_OCEAN_SHALLOW := Color(0.04, 0.13, 0.16)
const BAKE_SAND := Color(0.46, 0.41, 0.31)
const BAKE_DOWNTOWN := Color(0.19, 0.19, 0.20)
const BAKE_MIDTOWN := Color(0.22, 0.21, 0.20)
const BAKE_SUBURB := Color(0.21, 0.26, 0.15)
const BAKE_INDUSTRIAL := Color(0.23, 0.22, 0.20)
const BAKE_CAMPUS := Color(0.18, 0.27, 0.14)
const BAKE_GRASS := Color(0.17, 0.25, 0.11)
const BAKE_SCRUB := Color(0.27, 0.26, 0.15)
const BAKE_ROCK := Color(0.29, 0.27, 0.24)
const BAKE_CONCRETE := Color(0.32, 0.31, 0.30)
const BAKE_SNOW := Color(0.78, 0.80, 0.84)
## Metres that alpha 1.0 stands for in the baked map. The horizon plane lifts its vertices by
## this, so it has to cover the highest peak the back range can throw up.
const BAKE_HEIGHT_SCALE := 1600.0


## Paints the whole basin into one small image, so the ground plane beyond the streamed chunks
## can show the actual map instead of a flat green table out to the horizon: ocean to the west,
## the mountains to the north, the airport, the city sprawl. RGB is the ground colour and alpha
## carries the land height (metres / BAKE_HEIGHT_SCALE), which the shader both shades from
## and lifts its own vertices by, so the mountains have a silhouette and not just a colour. Alpha is
## exactly zero on water and never below 0.004 on land, so the shader can tell the sea apart and
## shade it as water rather than as a very flat blue field.
##
## These colours are albedos, not the finished look: the renderer lights the plane like anything
## else, which brightens them by roughly half again. Picking them by eye from a photograph gives
## a washed-out map.
##
## `span` is how many metres across the image covers, centred on `centre` in world XZ.
func bake(centre: Vector2, span: float, size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var step := span / float(size)
	var origin := centre - Vector2(span, span) * 0.5
	for py in size:
		for px in size:
			var pos := origin + Vector2((float(px) + 0.5) * step, (float(py) + 0.5) * step)
			var h := height_at(pos)
			var col: Color
			match zone_at(pos):
				Zone.OCEAN:
					# Shoaling water: the shelf near the shore reads much lighter than the deep.
					var shore := clampf((coast_x(pos.y) - pos.x) / 600.0, 0.0, 1.0)
					col = BAKE_OCEAN_SHALLOW.lerp(BAKE_OCEAN_DEEP, shore)
				Zone.BEACH:
					col = BAKE_SAND
				Zone.AIRPORT:
					col = BAKE_CONCRETE
				Zone.PORT:
					col = BAKE_CONCRETE.darkened(0.25)
				Zone.HILLS:
					# Green on the lower slopes, dry scrub above them, bare rock higher, and
					# snow on the back range, which tops out well over a kilometre.
					var t := clampf(h / 1000.0, 0.0, 1.0)
					col = BAKE_GRASS.lerp(BAKE_SCRUB, smoothstep(0.06, 0.26, t))
					col = col.lerp(BAKE_ROCK, smoothstep(0.26, 0.62, t))
					col = col.lerp(BAKE_SNOW, smoothstep(0.80, 1.0, t))
				_:
					match district_at(pos):
						CityPlan.District.DOWNTOWN:
							col = BAKE_DOWNTOWN
						CityPlan.District.MIDTOWN:
							col = BAKE_MIDTOWN
						CityPlan.District.INDUSTRIAL:
							col = BAKE_INDUSTRIAL
						CityPlan.District.CAMPUS:
							col = BAKE_CAMPUS
						_:
							col = BAKE_SUBURB
			if zone_at(pos) == Zone.OCEAN:
				col.a = 0.0
			else:
				col.a = clampf(maxf(h, 0.0) / BAKE_HEIGHT_SCALE, 0.004, 1.0)
				# Built-up ground is not one flat colour from the air: it is roofs, roads,
				# yards and trees at a scale far below one texel. Jitter each texel so the
				# sprawl beyond the loaded chunks reads as a city rather than a painted field.
				var n := float(absi(hash([px, py, seed])) % 1000) / 1000.0
				var jitter := 0.86 + 0.30 * n
				col = Color(col.r * jitter, col.g * jitter, col.b * (jitter * 0.98), col.a)
			img.set_pixel(px, py, col)
	return img
