class_name CityPlan
extends RefCounted
## The layout of an endless city from one seed, computed lazily: any road, block or
## intersection index can be asked for and always comes back the same.
## Pure data, no nodes. CityStreamer builds CityChunks from it around the player.

enum District { DOWNTOWN, MIDTOWN, SUBURBS, INDUSTRIAL }
enum BlockKind { BUILDINGS, PARK, PLAZA }
enum Intersection { PLAIN, STOP_SIGNS, SIGNALS, ROUNDABOUT }

const DISTRICT_NAMES := ["Downtown", "Midtown", "Suburbs", "Industrial"]
const AXIS_X := 0
const AXIS_Z := 1

## Parameter ranges per district. Heights and lots in meters.
const DISTRICTS := {
	District.DOWNTOWN: {
		"height": Vector2(50.0, 140.0), "lot": Vector2(28.0, 46.0), "gap": Vector2(2.0, 5.0),
		"shapes": [Building.Shape.TOWER, Building.Shape.PODIUM_TOWER, Building.Shape.SETBACK, Building.Shape.CROWN, Building.Shape.CROWN, Building.Shape.STEPPED],
		"finishes": [Building.Finish.GLASS, Building.Finish.GLASS, Building.Finish.PANELS, Building.Finish.GLASS],
		"lit": Vector2(0.3, 0.6), "park": 0.05, "plaza": 0.12, "trees": 0.35, "courtyard": 0.5,
	},
	District.MIDTOWN: {
		"height": Vector2(12.0, 45.0), "lot": Vector2(20.0, 32.0), "gap": Vector2(3.0, 8.0),
		"shapes": [Building.Shape.SLAB, Building.Shape.STEPPED, Building.Shape.L_SHAPE, Building.Shape.PODIUM_TOWER, Building.Shape.TOWER],
		"finishes": [Building.Finish.FLAT, Building.Finish.BRICK, Building.Finish.PANELS, Building.Finish.GLASS],
		"lit": Vector2(0.2, 0.5), "park": 0.10, "plaza": 0.06, "trees": 0.7, "courtyard": 0.6,
	},
	District.SUBURBS: {
		"height": Vector2(5.0, 14.0), "lot": Vector2(14.0, 22.0), "gap": Vector2(6.0, 14.0),
		"shapes": [Building.Shape.SLAB, Building.Shape.SLAB, Building.Shape.L_SHAPE],
		"finishes": [Building.Finish.BRICK, Building.Finish.FLAT, Building.Finish.BRICK],
		"lit": Vector2(0.1, 0.35), "park": 0.18, "plaza": 0.02, "trees": 1.0, "courtyard": 0.3,
	},
	District.INDUSTRIAL: {
		"height": Vector2(6.0, 16.0), "lot": Vector2(34.0, 60.0), "gap": Vector2(6.0, 12.0),
		"shapes": [Building.Shape.WAREHOUSE, Building.Shape.WAREHOUSE, Building.Shape.SLAB],
		"finishes": [Building.Finish.PANELS, Building.Finish.FLAT],
		"lit": Vector2(0.05, 0.2), "park": 0.02, "plaza": 0.0, "trees": 0.1, "courtyard": 0.0,
	},
}

var seed: int = 0
var block_size_range: Vector2 = Vector2(70.0, 120.0)
var street_width: float = 14.0
var avenue_width: float = 24.0
## Every Nth road (roughly) is an avenue.
var avenue_every: int = 3
var sidewalk_width: float = 4.0
## District rings, in meters from the origin.
var downtown_radius: float = 180.0
var midtown_radius: float = 380.0
## Beyond this radius, one seeded quadrant is industrial.
var industrial_start_radius: float = 260.0

## Optional big-picture map. When set, it decides districts and zones (ocean, beach, hills).
var macro: MacroMap

var _industrial_quadrant: int = -1
var _road_pos: Array[Dictionary] = [{0: 0.0}, {0: 0.0}]
var _road_width: Array[Dictionary] = [{}, {}]
var _blocks: Dictionary = {}
var _intersections: Dictionary = {}


func industrial_quadrant() -> int:
	if _industrial_quadrant < 0:
		_industrial_quadrant = _rng_for(7, 0, 0).randi_range(0, 3)
	return _industrial_quadrant


# --- Roads -------------------------------------------------------------------------

## Center coordinate of road `i` on an axis. Road 0 is at 0 on both axes.
func road_pos(axis: int, i: int) -> float:
	var cache: Dictionary = _road_pos[axis]
	if cache.has(i):
		return cache[i]
	if i > 0:
		var j := i
		while not cache.has(j):
			j -= 1
		var pos: float = cache[j]
		while j < i:
			pos += _block_size(axis, j)
			j += 1
			cache[j] = pos
		return pos
	var j := i
	while not cache.has(j):
		j += 1
	var pos: float = cache[j]
	while j > i:
		j -= 1
		pos -= _block_size(axis, j)
		cache[j] = pos
	return pos


func road_width(axis: int, i: int) -> float:
	var cache: Dictionary = _road_width[axis]
	if cache.has(i):
		return cache[i]
	var is_avenue := posmod(i, avenue_every) == avenue_every - 1 or _rng_for(2 + axis, i, 0).randf() < 0.15
	var w := avenue_width if is_avenue else street_width
	cache[i] = w
	return w


## Size of the block between road `i` and road `i + 1` on an axis.
func _block_size(axis: int, i: int) -> float:
	return _rng_for(4 + axis, i, 0).randf_range(block_size_range.x, block_size_range.y)


## Index of the block containing a world XZ position (block (ix, iz) spans road ix..ix+1, iz..iz+1).
func block_index_at(pos: Vector2) -> Vector2i:
	return Vector2i(_index_at(AXIS_X, pos.x), _index_at(AXIS_Z, pos.y))


func _index_at(axis: int, value: float) -> int:
	var i := 0
	while value >= road_pos(axis, i + 1):
		i += 1
	while value < road_pos(axis, i):
		i -= 1
	return i


# --- Blocks and intersections --------------------------------------------------------

## {"rect": Rect2 (between road edges), "ix", "iz", "district", "kind", "seed"}
func block(ix: int, iz: int) -> Dictionary:
	var key := Vector2i(ix, iz)
	if _blocks.has(key):
		return _blocks[key]
	var x0 := road_pos(AXIS_X, ix) + road_width(AXIS_X, ix) * 0.5
	var x1 := road_pos(AXIS_X, ix + 1) - road_width(AXIS_X, ix + 1) * 0.5
	var z0 := road_pos(AXIS_Z, iz) + road_width(AXIS_Z, iz) * 0.5
	var z1 := road_pos(AXIS_Z, iz + 1) - road_width(AXIS_Z, iz + 1) * 0.5
	var rect := Rect2(x0, z0, x1 - x0, z1 - z0)
	var district := district_at(rect.get_center())
	var params: Dictionary = DISTRICTS[district]
	var rng := _rng_for(3, ix, iz)
	var roll := rng.randf()
	var kind := BlockKind.BUILDINGS
	if roll < params.park:
		kind = BlockKind.PARK
	elif roll < params.park + params.plaza:
		kind = BlockKind.PLAZA
	var result := {"rect": rect, "ix": ix, "iz": iz, "district": district, "kind": kind, "seed": rng.randi()}
	_blocks[key] = result
	return result


## {"pos": Vector2, "kind": Intersection, "size": Vector2 (road widths x, z), "seed"}
func intersection(ix: int, iz: int) -> Dictionary:
	var key := Vector2i(ix, iz)
	if _intersections.has(key):
		return _intersections[key]
	var wx := road_width(AXIS_X, ix)
	var wz := road_width(AXIS_Z, iz)
	var rng := _rng_for(6, ix, iz)
	var roll := rng.randf()
	var both_avenues := wx >= avenue_width - 0.1 and wz >= avenue_width - 0.1
	var any_avenue := wx >= avenue_width - 0.1 or wz >= avenue_width - 0.1
	var kind := Intersection.PLAIN
	if ix == 0 and iz == 0:
		kind = Intersection.SIGNALS # the spawn point; keep it open
	elif both_avenues:
		kind = Intersection.ROUNDABOUT if roll < 0.3 else Intersection.SIGNALS
	elif any_avenue:
		kind = Intersection.SIGNALS if roll < 0.7 else Intersection.STOP_SIGNS
	else:
		kind = Intersection.STOP_SIGNS if roll < 0.6 else Intersection.PLAIN
	var result := {"pos": Vector2(road_pos(AXIS_X, ix), road_pos(AXIS_Z, iz)), "kind": kind, "size": Vector2(wx, wz), "seed": rng.randi()}
	_intersections[key] = result
	return result


func zone_at(pos: Vector2) -> MacroMap.Zone:
	return macro.zone_at(pos) if macro else MacroMap.Zone.CITY


func height_at(pos: Vector2) -> float:
	return macro.height_at(pos) if macro else 0.0


func district_at(pos: Vector2) -> District:
	if macro:
		return macro.district_at(pos)
	var r := pos.length()
	var quadrant := (0 if pos.x >= 0.0 else 1) + (0 if pos.y >= 0.0 else 2)
	if quadrant == industrial_quadrant() and r > industrial_start_radius:
		return District.INDUSTRIAL
	if r < downtown_radius:
		return District.DOWNTOWN
	if r < midtown_radius:
		return District.MIDTOWN
	return District.SUBURBS


static func district_name(d: District) -> String:
	return DISTRICT_NAMES[d]


func _rng_for(kind: int, a: int, b: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, kind, a, b])
	return rng
