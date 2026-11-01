class_name PlazaGoer
extends Pedestrian
## Somebody in Chinatown's plaza court (ChinatownKit.plaza_people()): an ordinary pedestrian - shot,
## knocked, bled and ragdolled like anyone, counted in the crowd cap, living the crowd-life layer
## (talks, phones, the benches round the pond, the shop queues) - kept to the court instead of a
## block's pavement ring. PierGoer's pattern: the court's open areas are rects (`regions`: the
## four quarters round the hall and the pond, and the walk), a walk goes out to the walk, along
## it and in again, so nobody walks through the hall, the pond or a shop row.

var regions: Array = []
var walk_z: float = 0.0


func setup_plaza(court: Array, walk: float, start: Vector2, seed_value: int) -> void:
	regions = court
	walk_z = walk
	setup(Rect2(start - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), 6.0, seed_value)
	cross_chance = 0.0
	pause_chance = 0.5
	pause_seconds = Vector2(3.0, 14.0)
	life_chance = 0.55
	life_spawn_chance = 0.6
	add_to_group("plaza_goer")


func _lives() -> bool:
	return true


func _leisure_place() -> bool:
	return true


## Next stop: anywhere open in the court.
func _random_ring_point(_sidewalk: float) -> Vector2:
	if regions.is_empty():
		return Vector2(position.x, position.z)
	var r: Rect2 = regions[_rng.randi() % regions.size()]
	return Vector2(_rng.randf_range(r.position.x, r.end.x), _rng.randf_range(r.position.y, r.end.y))


## Out to the walk, along it, and in to the stop.
func _ring_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var lane := walk_z + _rng.randf_range(-3.0, 3.0)
	return PackedVector2Array([Vector2(from.x, lane), Vector2(to.x, lane)])
