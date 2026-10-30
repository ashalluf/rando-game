class_name YardSaleBrowser
extends Pedestrian
## A neighbour at a yard sale (YardSales._people()): an ordinary pedestrian - shot, knocked, bled
## and ragdolled like anyone, in the crowd cap, living the crowd-life layer - kept to the sale's
## aisle, the strip of lawn and driveway in front of the tables, instead of a block's pavement
## ring. They drift along it and stop at a table (the chunk's "vendor_queue" spots in front of
## each, which the life layer's _plan_queue() sends people to), look, talk to the seller, and drift
## on; most carry a bag or a coffee.

## The aisle's two ends (chunk space, true world: the ring's space).
var _a := Vector2.ZERO
var _b := Vector2.ZERO


func setup_sale(a: Vector2, b: Vector2, block_rect: Rect2, seed_value: int) -> void:
	_a = a
	_b = b
	setup(block_rect, 4.0, seed_value)
	cross_chance = 0.0
	pause_chance = 0.45
	pause_seconds = Vector2(2.0, 6.0)
	life_chance = 0.85
	life_spawn_chance = 0.7
	add_to_group("yard_sale_browser")


func _lives() -> bool:
	return true


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_jogger = false
	_dog_walker = false
	var r := _life.randf()
	if r < 0.35:
		_carry = CrowdLife.Carry.BAG
	elif r < 0.55:
		_carry = CrowdLife.Carry.CUP
	elif r < 0.62:
		_carry = CrowdLife.Carry.CALL


## Next stop: somewhere along the aisle, mostly not far from here.
func _random_ring_point(_sidewalk: float) -> Vector2:
	if _a == _b:
		return super(_sidewalk)
	var here := Vector2(position.x, position.z)
	var along := (_b - _a)
	var L := along.length()
	if L < 0.01:
		return _a
	var t := clampf((here - _a).dot(along) / (L * L) + _rng.randf_range(-0.6, 0.6) * minf(1.0, 4.0 / L), 0.0, 1.0)
	var side := Vector2(-along.y, along.x).normalized() * _rng.randf_range(-0.3, 0.3)
	return _a.lerp(_b, t) + side


## The aisle is open: walk straight there.
func _ring_route(_from: Vector2, _to: Vector2) -> PackedVector2Array:
	if _a == _b:
		return super(_from, _to)
	return PackedVector2Array()
