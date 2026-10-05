class_name PierGoer
extends Pedestrian
## Somebody at the pier park (PierPark.people_steps()): an ordinary pedestrian - shot, knocked,
## bled and ragdolled like anyone, counted in the crowd cap, living the crowd-life layer (talks,
## phones, the benches, the queues) - kept to the pier's deck instead of a block's pavement ring.
##
## They walk the park's WALK GRAPH (PierPark.WALK_NODES / WALK_EDGES: the promenade down the
## pier, the way under the coaster's lift into the loop, round the wheel and the carousel), never
## through a ride: every walk is a path of graph nodes (breadth first), each node jittered a little
## so a crowd does not walk one line. The queues at the wheel, the coaster, the carousel, the food
## stands and the game booths are the chunk's "vendor_queue" spots (PierPark.queue_spots()), which
## the life layer's _plan_queue() already sends people to; the benches are its seats.

## The park's frame: world XZ of its origin, and the deck top (world y).
var origin := Vector2.ZERO
var deck_top: float = 6.4
var _node: int = 0


func setup_park(o: Vector2, deck: float, start_node: int, seed_value: int) -> void:
	origin = o
	deck_top = deck
	_node = start_node
	var a := PierPark.walk_node(o, start_node)
	setup(Rect2(a - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), 6.0, seed_value)
	cross_chance = 0.0
	pause_chance = 0.5
	pause_seconds = Vector2(3.0, 14.0)
	life_chance = 0.55
	life_spawn_chance = 0.6
	add_to_group("pier_goer")


func _lives() -> bool:
	return true


func _leisure_place() -> bool:
	return true


## The deck, wherever on the park this is.
func _ground_y(_x: float, _z: float, _fallback: float) -> float:
	return deck_top + 0.1


## Next stop: a neighbour of the node we are at (so the walks wander the park rather than
## crossing it end to end every time), jittered.
func _random_ring_point(_sidewalk: float) -> Vector2:
	var nbrs := PierPark.neighbours(_node)
	if nbrs.is_empty():
		return Vector2(position.x, position.z)
	var next: int = nbrs[_rng.randi() % nbrs.size()]
	# Now and then a longer walk: on to a neighbour of that one.
	if _rng.randf() < 0.4:
		var more := PierPark.neighbours(next)
		if not more.is_empty():
			next = more[_rng.randi() % more.size()]
	_node = next
	var j := PierPark.jitter(next)
	return PierPark.walk_node(origin, next) + Vector2(_rng.randf_range(-j, j), _rng.randf_range(-j, j))


## The graph's nodes between here and `to`, so nobody walks through a ride.
func _ring_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var path := PierPark.route(origin, from, to)
	var nearest := PierPark.nearest_node(origin, to)
	if nearest >= 0:
		_node = nearest
	return path
