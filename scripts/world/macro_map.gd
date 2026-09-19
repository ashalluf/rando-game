class_name MacroMap
extends RefCounted
## The big picture of the map: where the ocean, beach, hills and districts are, and how high the
## land is. Inspired by a west-coast basin: ocean to the west, a mountain range to the north with
## a big sign on its south face, a hilly peninsula to the south-west, downtown to the east.
## Everything here is original geography; nothing is traced from a real map.

enum Zone { CITY, BEACH, OCEAN, HILLS }

const ZONE_NAMES := ["City", "Beach", "Ocean", "Hills"]

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
var peninsula_height: float = 110.0
var downtown_center: Vector2 = Vector2(700.0, 250.0)
var downtown_radius: float = 330.0
var midtown_radius: float = 800.0
## A second cluster of mid-rise towers on the west side.
var westside_center: Vector2 = Vector2(-350.0, -250.0)
var westside_radius: float = 320.0
## South-east of this corner is the port and industrial district.
var industrial_corner: Vector2 = Vector2(300.0, 900.0)

var _noise: FastNoiseLite


func setup() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0012
	_noise.fractal_octaves = 4


## X of the coast at a given Z: a gentle bay curve, bulging west around the peninsula.
func coast_x(z: float) -> float:
	var x := coast_base_x + 180.0 * sin(z / 700.0)
	var d := absf(z - peninsula_center.y)
	var bulge := smoothstep(peninsula_radius * 1.2, 0.0, d) * 520.0
	return x - bulge


func height_at(pos: Vector2) -> float:
	if _noise == null:
		setup()
	var n := _noise.get_noise_2dv(pos)
	var t := smoothstep(hills_start_z, hills_full_z, pos.y)
	var h := t * (hills_height * (0.6 + 0.4 * n) + 40.0 * n)
	var pd := pos.distance_to(peninsula_center)
	var pt := smoothstep(peninsula_radius, peninsula_radius * 0.25, pd)
	h += pt * peninsula_height * (0.7 + 0.3 * n)
	return maxf(h, 0.0)


func zone_at(pos: Vector2) -> Zone:
	var cx := coast_x(pos.y)
	if pos.x < cx:
		return Zone.OCEAN
	if height_at(pos) > 3.0:
		return Zone.HILLS
	if pos.x < cx + beach_width:
		return Zone.BEACH
	return Zone.CITY


func district_at(pos: Vector2) -> CityPlan.District:
	var dd := pos.distance_to(downtown_center)
	if dd < downtown_radius:
		return CityPlan.District.DOWNTOWN
	if pos.x > industrial_corner.x and pos.y > industrial_corner.y:
		return CityPlan.District.INDUSTRIAL
	if dd < midtown_radius or pos.distance_to(westside_center) < westside_radius:
		return CityPlan.District.MIDTOWN
	return CityPlan.District.SUBURBS


static func zone_name(z: Zone) -> String:
	return ZONE_NAMES[z]
