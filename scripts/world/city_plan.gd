class_name CityPlan
extends RefCounted
## The layout of the city from one seed: road grid, blocks, districts, block kinds.
## Pure data, no nodes. CityBuilder turns it into meshes; later chunk streaming can
## build and free blocks from the same plan.

enum District { DOWNTOWN, MIDTOWN, SUBURBS, INDUSTRIAL }
enum BlockKind { BUILDINGS, PARK, PLAZA }
enum Intersection { PLAIN, STOP_SIGNS, SIGNALS, ROUNDABOUT }

const DISTRICT_NAMES := ["Downtown", "Midtown", "Suburbs", "Industrial"]

## Parameter ranges per district. Heights and lots in meters.
const DISTRICTS := {
	District.DOWNTOWN: {
		"height": Vector2(40.0, 120.0), "lot": Vector2(26.0, 40.0), "gap": Vector2(3.0, 6.0),
		"shapes": [Building.Shape.TOWER, Building.Shape.PODIUM_TOWER, Building.Shape.STEPPED, Building.Shape.SLAB],
		"finishes": [Building.Finish.GLASS, Building.Finish.PANELS, Building.Finish.GLASS],
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
## Number of blocks on each side of the center intersection.
var blocks_x: int = 5
var blocks_z: int = 5
var block_size_range: Vector2 = Vector2(70.0, 120.0)
var street_width: float = 14.0
var avenue_width: float = 24.0
## Every Nth road (roughly) is an avenue.
var avenue_every: int = 3
var sidewalk_width: float = 4.0

## Road center coordinates and widths along X (vertical roads) and Z (horizontal roads).
var road_xs: PackedFloat32Array = []
var road_x_widths: PackedFloat32Array = []
var road_zs: PackedFloat32Array = []
var road_z_widths: PackedFloat32Array = []
## {"rect": Rect2 (block area between road edges, in xz), "ix", "iz", "district", "kind", "seed"}
var blocks: Array[Dictionary] = []
## {"pos": Vector2, "kind": Intersection, "size": Vector2 (road widths x, z), "seed"}
var intersections: Array[Dictionary] = []
var extent: float = 0.0
var industrial_quadrant: int = 0

var _rng := RandomNumberGenerator.new()


func generate() -> void:
	_rng.seed = seed
	industrial_quadrant = _rng.randi_range(0, 3)
	road_xs = _lay_roads(blocks_x, road_x_widths)
	road_zs = _lay_roads(blocks_z, road_z_widths)
	extent = maxf(absf(road_xs[0]), absf(road_xs[-1]))
	extent = maxf(extent, maxf(absf(road_zs[0]), absf(road_zs[-1])))

	blocks.clear()
	for ix in road_xs.size() - 1:
		for iz in road_zs.size() - 1:
			var x0 := road_xs[ix] + road_x_widths[ix] * 0.5
			var x1 := road_xs[ix + 1] - road_x_widths[ix + 1] * 0.5
			var z0 := road_zs[iz] + road_z_widths[iz] * 0.5
			var z1 := road_zs[iz + 1] - road_z_widths[iz + 1] * 0.5
			var rect := Rect2(x0, z0, x1 - x0, z1 - z0)
			var district := district_at(rect.get_center())
			var params: Dictionary = DISTRICTS[district]
			var roll := _rng.randf()
			var kind := BlockKind.BUILDINGS
			if roll < params.park:
				kind = BlockKind.PARK
			elif roll < params.park + params.plaza:
				kind = BlockKind.PLAZA
			blocks.append({"rect": rect, "ix": ix, "iz": iz, "district": district, "kind": kind, "seed": _rng.randi()})

	intersections.clear()
	for ix in road_xs.size():
		for iz in road_zs.size():
			var wx := road_x_widths[ix]
			var wz := road_z_widths[iz]
			var kind := Intersection.PLAIN
			var both_avenues := wx >= avenue_width - 0.1 and wz >= avenue_width - 0.1
			var any_avenue := wx >= avenue_width - 0.1 or wz >= avenue_width - 0.1
			var roll := _rng.randf()
			if absf(road_xs[ix]) < 0.01 and absf(road_zs[iz]) < 0.01:
				kind = Intersection.SIGNALS # spawn point; keep it open
			elif both_avenues:
				kind = Intersection.ROUNDABOUT if roll < 0.3 else Intersection.SIGNALS
			elif any_avenue:
				kind = Intersection.SIGNALS if roll < 0.7 else Intersection.STOP_SIGNS
			else:
				kind = Intersection.STOP_SIGNS if roll < 0.6 else Intersection.PLAIN
			intersections.append({"pos": Vector2(road_xs[ix], road_zs[iz]), "kind": kind, "size": Vector2(wx, wz), "seed": _rng.randi()})


## Roads are laid outward from the center so there is always an intersection at (0, 0).
func _lay_roads(count: int, widths: PackedFloat32Array) -> PackedFloat32Array:
	var centers: PackedFloat32Array = []
	var half := count / 2
	var positive: Array[float] = [0.0]
	var negative: Array[float] = []
	var pos := 0.0
	for i in half:
		pos += _rng.randf_range(block_size_range.x, block_size_range.y)
		positive.append(pos)
	pos = 0.0
	for i in count - half:
		pos -= _rng.randf_range(block_size_range.x, block_size_range.y)
		negative.append(pos)
	negative.reverse()
	for c in negative:
		centers.append(c)
	for c in positive:
		centers.append(c)
	widths.clear()
	for i in centers.size():
		var is_avenue := (i % avenue_every == avenue_every - 1) or _rng.randf() < 0.15
		widths.append(avenue_width if is_avenue else street_width)
	return centers


func district_at(pos: Vector2) -> District:
	var r := pos.length() / maxf(extent, 1.0)
	var quadrant := (0 if pos.x >= 0.0 else 1) + (0 if pos.y >= 0.0 else 2)
	if quadrant == industrial_quadrant and r > 0.5:
		return District.INDUSTRIAL
	if r < 0.32:
		return District.DOWNTOWN
	if r < 0.68:
		return District.MIDTOWN
	return District.SUBURBS


static func district_name(d: District) -> String:
	return DISTRICT_NAMES[d]


func block_at(pos: Vector2) -> Dictionary:
	for block in blocks:
		if (block.rect as Rect2).has_point(pos):
			return block
	return {}
