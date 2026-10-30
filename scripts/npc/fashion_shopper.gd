class_name FashionShopper
extends Pedestrian
## A shopper in the fashion district's market alley (FashionDistrict.dress_market()): strolls the
## aisle between the stalls - a point anywhere along it, then the next - stopping now and then to
## look (the crowd's life), most of them carrying shopping bags. Everything else (the look, the
## gait, panic, being shot or knocked down) is Pedestrian's.

## The aisle's two ends (chunk space), half its free width, and whether it runs along x.
var lane_a: Vector2 = Vector2.ZERO
var lane_b: Vector2 = Vector2.ZERO
var lane_half: float = 0.5

## How many carry bags (the rest carry what the crowd carries).
const BAG_SHARE := 0.75


func setup_shopper(block_rect: Rect2, seed_value: int, path: Array) -> void:
	setup(block_rect, 1.0, seed_value)
	lane_a = path[0]
	lane_b = path[1]
	lane_half = float(path[2])
	cross_chance = 0.0
	# A browsing pace, slower than the street's.
	walk_speed = _rng.randf_range(0.75, 1.1)
	_speed = walk_speed


## The plain crowd's life clips and props (Pedestrian gives them only to itself by script path).
func _lives() -> bool:
	return true


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_jogger = false
	_dog_walker = false
	walk_speed = minf(walk_speed, 1.1)
	_speed = walk_speed
	if _life.randf() < BAG_SHARE:
		_carry = CrowdLife.Carry.BAG


## A point in the aisle, anywhere along it.
func _random_ring_point(_sidewalk: float) -> Vector2:
	var d := lane_b - lane_a
	var perp := Vector2(-d.y, d.x).normalized()
	return lane_a + d * _rng.randf() + perp * _rng.randf_range(-lane_half, lane_half)


## The aisle is straight: no going round a block's corners.
func _ring_route(_from: Vector2, _to: Vector2) -> PackedVector2Array:
	return PackedVector2Array()
