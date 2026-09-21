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
## Where the northern coastal shelf starts and is fully cut (Z; north is negative), how far
## inland it reaches before the mountainside takes over again, and how high its bench sits.
## This is the ledge the coast highway runs along under the cliffs.
var shelf_from_z: float = -700.0
var shelf_full_z: float = -1020.0
var shelf_width: float = 300.0
var shelf_height: float = 26.0
## How far inland the beach towns run before the ordinary grid takes over.
var beach_town_depth: float = 340.0
## The towns down the coast, north to south, each entry the Z at which that town begins. A real
## coast like this one is a chain of small separate towns rather than one seafront, and naming
## them is most of what makes it read that way: the HUD place name changes as you drive the
## highway. Bands are keyed to Z only, because the coast is a ribbon.
const COAST_TOWNS := [
	[-99999.0, "Malibu"], [-950.0, "Santa Monica"], [-520.0, "Venice"], [-160.0, "Playa"],
	[250.0, "El Segundo"], [1010.0, "Manhattan Beach"], [1240.0, "Hermosa Beach"],
	[1420.0, "Redondo Beach"],
]
## The headland. It sits far enough south that the chain of beach towns has coastline to run
## along before it starts: with it at 1500 the towns south of the airport had nowhere to go.
var peninsula_center: Vector2 = Vector2(-780.0, 1980.0)
var peninsula_radius: float = 550.0
## The headland in the south-west bay: cliffs straight out of the water.
var peninsula_height: float = 285.0
## Water south of this Z and west of this X (except the peninsula) so the peninsula sticks out.
var bay_z: float = 1460.0
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
## How far up a mountain the city's rolling relief takes to fade out. Wide on purpose: see
## `_relief_at()`.
var relief_fade_height: float = 60.0
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
	# Relief first, then carve: the roads have to be cut into the surface the player actually
	# walks on. Carving the bare mountain and adding relief afterwards lifts every road off its
	# own bed by whatever the relief happens to be there.
	var h := raw + _relief_at(pos, raw)
	if hill_roads and raw > 0.5:
		h = hill_roads.carve(pos, h)
	return h


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
	# Fade the rolling relief out over the first `relief_fade_height` metres of mountain, not the
	# first 2.5. At the foot of a range raw climbs from 0 to 3 m in about twenty metres of ground,
	# so a narrow window switched the relief off in one step and left a metres-high wall along the
	# whole city/hills seam - a grey band right round the valley. Hill roads are carved into the
	# surface *including* relief (see `height_at`), so letting it run up the lower slopes costs
	# nothing.
	var fade := 1.0 - smoothstep(0.0, relief_fade_height, raw)
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

	# The northern coastal shelf. Up there the front range comes all the way down to the water,
	# and on a coast like that the mountains stop at a narrow bench a few hundred metres wide
	# with the road and a ribbon of houses on it, then the sea. Without the bench the coast
	# highway would be a cutting in a 560 m mountainside and the grade limiter would bury it.
	# Only in the north: further south the basin is already flat, and on the headland the cliffs
	# dropping straight into the water are the whole character of the place.
	var north := smoothstep(shelf_from_z, shelf_full_z, pos.y)
	if north > 0.0:
		var inland := pos.x - coast_x(pos.y)
		var rise := smoothstep(0.0, shelf_width, inland)
		var bench := lerpf(minf(h, shelf_height + 14.0 * n2), h, rise)
		h = lerpf(h, bench, north)
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
	# The strip behind the sand, for as far inland as the towns run. Checked after the named
	# centres so that a campus or a downtown placed near the water still wins, and gated on the
	# ground being low so the headland and the northern cliffs stay hillside rather than town.
	if pos.x - coast_x(pos.y) < beach_town_depth and raw_height_at(pos) < 12.0:
		return CityPlan.District.BEACHTOWN
	if dd < midtown_radius or pos.distance_to(westside_center) < westside_radius:
		return CityPlan.District.MIDTOWN
	return CityPlan.District.SUBURBS


## The name of the place at a world position, or "" when it has none and the district name
## should be used instead. Only the coast is named: that is where the towns are.
func place_name(pos: Vector2) -> String:
	if pos.distance_to(peninsula_center) < peninsula_radius:
		return "Palos Verdes"
	if airport_rect.has_point(pos):
		return ""
	if pos.x - coast_x(pos.y) > beach_town_depth + 260.0:
		return ""
	var found := ""
	for town in COAST_TOWNS:
		if pos.y >= float(town[0]):
			found = str(town[1])
	return found


static func zone_name(z: Zone) -> String:
	return ZONE_NAMES[z]


## Colours for the land beyond the loaded chunks. These are the colours the horizon is painted
## with, so they are the average of what a district looks like from the air, not the colour of
## any one surface in it.
##
## They also carry one bit of information the horizon shader cannot get any other way.
## `built_amount()` in shaders/macro_ground.gdshader tells built-up ground from open country by
## SATURATION: everything people build - roofs, asphalt, concrete, dust - averages out to a
## near-neutral grey from three kilometres up, and every natural cover in this basin (parched
## grass, chaparral, rock, sand) has real chroma in it. So every district colour below is
## deliberately near enough to grey and every natural one deliberately is not. Those tests run
## on the LINEAR values the sampler decodes these to, which are about a quarter of what is
## written here: a district lands at 0.027..0.040 with saturation under 0.15, chaparral at 0.07
## with saturation 0.76, bare rock at 0.11, pale concrete at 0.09, snow at 0.62.
## and the shader puts blocks, streets, roof variation and tree canopy on the first and rock,
## scree, scrub and drainage on the second. How much greener than red a district is sets how
## leafy the shader makes it, which is why campus is the greenest and industrial is not green
## at all. Change one of these and check `built_amount()` still separates them.
##
## These are albedos, not the finished look: the shader lights them, which brightens them by
## roughly half again. Picking them by eye from a photograph gives a washed-out map.
const BAKE_OCEAN_DEEP := Color(0.014, 0.034, 0.062)
const BAKE_OCEAN_SHALLOW := Color(0.045, 0.125, 0.155)
## The surf line. One bright texel along the shore is what makes a coastline read as a coast
## from ten kilometres up instead of as the edge of a blue shape.
const BAKE_SURF := Color(0.34, 0.44, 0.45)
## Metres offshore the surf fades out over.
const BAKE_SURF_WIDTH := 95.0
const BAKE_SAND := Color(0.50, 0.44, 0.33)
## Southern California, so the open country is parched gold-olive, not a green field.
const BAKE_GRASS := Color(0.28, 0.275, 0.155)
const BAKE_SCRUB := Color(0.36, 0.325, 0.175)
const BAKE_ROCK := Color(0.40, 0.365, 0.315)
const BAKE_SNOW := Color(0.78, 0.80, 0.84)
const BAKE_CONCRETE := Color(0.34, 0.335, 0.33)
const BAKE_PORT := Color(0.32, 0.31, 0.305)
const BAKE_DOWNTOWN := Color(0.175, 0.177, 0.188)
const BAKE_MIDTOWN := Color(0.200, 0.204, 0.206)
const BAKE_INDUSTRIAL := Color(0.225, 0.222, 0.215)
const BAKE_SUBURB := Color(0.216, 0.225, 0.212)
const BAKE_CAMPUS := Color(0.207, 0.220, 0.203)
## The freeway decks, drawn into the map as dark threads. Three curved routes crossing the
## basin are the most recognisable thing in an aerial view of a city like this one, and at this
## resolution they are the only man-made line long enough to survive the bake.
const BAKE_FREEWAY := Color(0.150, 0.150, 0.158)
## Metres either side of a route centre line that get painted.
const BAKE_FREEWAY_MARGIN := 18.0
## Metres that alpha 1.0 stands for in the baked map. The horizon plane lifts its vertices by
## this, so it has to cover the highest peak the back range can throw up.
const BAKE_HEIGHT_SCALE := 1600.0
## The bake is rendered this many times finer than the caller asks for. 256 px across 16 km is
## 62 metres a texel - a whole city block - and the coastline, the airport fence, the freeways
## and the edge of the city all come out as a smear that no amount of shader detail can undo,
## because the shader can invent what a hillside looks like but not where the hillside is.
## Measured on CI hardware: 0.24 s at 160, 0.8 s at 256, 1.9 s at 384, 3.0 s at 512, once, at
## load. The web build is left alone: GDScript under WASM is several times slower and the whole
## point of that build is that it starts fast.
const BAKE_UPSCALE := 2
## ...but never past this, because the cost is quadratic and the image is uploaded as a texture.
const BAKE_MAX_SIZE := 512
## Per-texel brightness jitter. It used to be +/- 15 %, which at 62 m a texel was the only
## variation the horizon had; now the shader synthesizes block-scale detail itself and this only
## has to keep neighbourhoods from all being the same value. Applied to every channel equally,
## so it cannot disturb the saturation the shader classifies on.
const BAKE_JITTER := 0.07


## Paints the whole basin into one small image, so the ground plane beyond the streamed chunks
## can show the actual map instead of a flat green table out to the horizon: ocean to the west,
## the mountains to the north, the airport, the city sprawl, the freeways. RGB is the ground
## colour and alpha carries the land height (metres / BAKE_HEIGHT_SCALE), which the shader both
## shades from and lifts its own vertices by, so the mountains have a silhouette and not just a
## colour. Alpha is exactly zero on water and never below 0.004 on land, so the shader can tell
## the sea apart and shade it as water rather than as a very flat blue field.
##
## `span` is how many metres across the image covers, centred on `centre` in world XZ; `size` is
## what the caller thinks it wants, and BAKE_UPSCALE is how much finer it actually gets.
func bake(centre: Vector2, span: float, size: int) -> Image:
	var res := size if OS.has_feature("web") else mini(size * BAKE_UPSCALE, BAKE_MAX_SIZE)
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	var step := span / float(res)
	var origin := centre - Vector2(span, span) * 0.5
	for py in res:
		for px in res:
			var pos := origin + Vector2((float(px) + 0.5) * step, (float(py) + 0.5) * step)
			var h := height_at(pos)
			var zone := zone_at(pos)
			var col: Color
			match zone:
				Zone.OCEAN:
					# Shoaling water: the shelf near the shore reads much lighter than the deep,
					# and the last hundred metres of it are breaking.
					var offshore := coast_x(pos.y) - pos.x
					var shore := clampf(offshore / 600.0, 0.0, 1.0)
					col = BAKE_OCEAN_SHALLOW.lerp(BAKE_OCEAN_DEEP, shore)
					if offshore >= 0.0:
						col = col.lerp(BAKE_SURF, (1.0 - smoothstep(0.0, BAKE_SURF_WIDTH, offshore)) * 0.85)
				Zone.BEACH:
					col = BAKE_SAND
				Zone.AIRPORT:
					col = BAKE_CONCRETE
				Zone.PORT:
					col = BAKE_PORT
				Zone.HILLS:
					# Parched grass on the lower slopes, chaparral above it, bare rock higher,
					# and snow on the back range, which tops out well over a kilometre.
					# The bands have to line up with what `terrain.gdshader` does on the streamed
					# chunks and with what `macro_ground.gdshader` synthesizes beyond them, or
					# every mountain gets a tide-line where the two meet.
					var t := clampf(h / 1000.0, 0.0, 1.0)
					col = BAKE_GRASS.lerp(BAKE_SCRUB, smoothstep(0.03, 0.14, t))
					col = col.lerp(BAKE_ROCK, smoothstep(0.45, 0.85, t))
					col = col.lerp(BAKE_SNOW, smoothstep(0.84, 1.0, t))
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
			if zone == Zone.OCEAN:
				col.a = 0.0
			else:
				col.a = clampf(maxf(h, 0.0) / BAKE_HEIGHT_SCALE, 0.004, 1.0)
				# The freeways, drawn last so they cross districts and hills alike.
				if freeway and freeway.blocks(pos, BAKE_FREEWAY_MARGIN):
					col = Color(BAKE_FREEWAY.r, BAKE_FREEWAY.g, BAKE_FREEWAY.b, col.a)
				# Built-up ground is not one flat value from the air. The shader draws the blocks
				# and the roofs; this only keeps one neighbourhood from reading exactly like the
				# next. Every channel is scaled together, so the saturation the shader classifies
				# on is untouched.
				var n := float(absi(hash([px, py, seed])) % 1000) / 1000.0
				var jitter := 1.0 + (n - 0.5) * 2.0 * BAKE_JITTER
				col = Color(col.r * jitter, col.g * jitter, col.b * jitter, col.a)
			img.set_pixel(px, py, col)
	return img
