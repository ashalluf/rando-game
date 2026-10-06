class_name MarketShopper
extends Pedestrian
## Somebody at the farmers' market (FarmersMarketBuild.spawn_shopper()): an ordinary pedestrian -
## shot, knocked, bled and ragdolled like anyone, in the crowd cap, living the crowd-life layer -
## kept to the market's aisle instead of a block's pavement ring. They stroll up and down between
## the two rows of stalls and stop at one (the chunk's "vendor_queue" spots in front of every
## table, which the life layer's _plan_queue() sends people to), stand and look, talk to the
## stallholder, and walk on, half of them with a tote bag and some with a coffee.

## The market's aisle in its street frame: along `t0..t1`, across `o0..o1` (FarmersMarketBuild).
var _site: Dictionary = {}
var _aisle: Dictionary = {}


func setup_market(site: Dictionary, aisle: Dictionary, block_rect: Rect2, seed_value: int) -> void:
	_site = site
	_aisle = aisle
	setup(block_rect, 4.0, seed_value)
	cross_chance = 0.0
	pause_chance = 0.35
	pause_seconds = Vector2(2.0, 7.0)
	life_chance = 0.8
	life_spawn_chance = 0.65
	add_to_group("market_shopper")


func _lives() -> bool:
	return true


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	# Nobody jogs through a market or walks a dog down it here, and most carry a bag or a coffee.
	_jogger = false
	_dog_walker = false
	var r := _life.randf()
	if r < 0.5:
		_carry = CrowdLife.Carry.BAG
	elif r < 0.68:
		_carry = CrowdLife.Carry.CUP
	elif r < 0.78:
		_carry = CrowdLife.Carry.CALL


## Next stop: somewhere along the aisle, mostly not far from here (people work down a market).
func _random_ring_point(_sidewalk: float) -> Vector2:
	if _site.is_empty():
		return super(_sidewalk)
	var t0: float = _aisle.t0
	var t1: float = _aisle.t1
	var o0: float = _aisle.o0
	var o1: float = _aisle.o1
	var here := Vector2(position.x, position.z)
	var along: Vector2 = FarmersMarket.dirs(_site)[0]
	var t_here := here.dot(along) if position != Vector3.ZERO else _rng.randf_range(t0, t1)
	var t := clampf(t_here + _rng.randf_range(-22.0, 22.0), t0 + 1.0, t1 - 1.0)
	if position == Vector3.ZERO:
		t = _rng.randf_range(t0 + 1.0, t1 - 1.0)
	var o := _rng.randf_range(o0, o1) if o1 > o0 else (o0 + o1) * 0.5
	return FarmersMarket.point(_site, t, o)


## The aisle is open: walk straight there.
func _ring_route(_from: Vector2, _to: Vector2) -> PackedVector2Array:
	if _site.is_empty():
		return super(_from, _to)
	return PackedVector2Array()
