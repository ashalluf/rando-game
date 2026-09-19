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
var hills_start_z: float = -900.0
var hills_full_z: float = -1500.0
var hills_height: float = 260.0
var peninsula_center: Vector2 = Vector2(-700.0, 1500.0)
var peninsula_radius: float = 550.0
var peninsula_height: float = 150.0
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
var airport_rect: Rect2 = Rect2(-880.0, 630.0, 980.0, 350.0)
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

var _noise: FastNoiseLite


func setup() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0012
	_noise.fractal_octaves = 4
	var hr := HillRoads.new()
	hr.build(self, seed)
	hill_roads = hr


## X of the coast at a given Z: a gentle bay curve, bulging west around the peninsula.
func coast_x(z: float) -> float:
	var x := coast_base_x + 180.0 * sin(z / 700.0)
	var d := absf(z - peninsula_center.y)
	var bulge := smoothstep(peninsula_radius * 1.2, 0.0, d) * 520.0
	return x - bulge


## Land height with hill roads and mansion pads carved in.
func height_at(pos: Vector2) -> float:
	var raw := raw_height_at(pos)
	if hill_roads and raw > 0.5:
		return hill_roads.carve(pos, raw)
	return raw


## Land height from the noise alone (what the roads are laid over).
func raw_height_at(pos: Vector2) -> float:
	if _noise == null:
		setup()
	if airport_rect.has_point(pos) or port_rect.has_point(pos) or harbor_rect.has_point(pos):
		return 0.0
	var n := _noise.get_noise_2dv(pos)
	var t := smoothstep(hills_start_z, hills_full_z, pos.y)
	var h := t * (hills_height * (0.6 + 0.4 * n) + 40.0 * n)
	var pd := pos.distance_to(peninsula_center)
	# Steep sides: the peninsula rises out of the bay as cliffs.
	var pt := smoothstep(peninsula_radius, peninsula_radius * 0.5, pd)
	h += pt * peninsula_height * (0.7 + 0.3 * n)
	return maxf(h, 0.0)


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
