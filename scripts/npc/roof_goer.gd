class_name RoofGoer
extends Pedestrian
## Someone on a rooftop pool deck (Rooftops puts two to four on each pool deck of a FULL chunk,
## inside the crowd cap): they drift about the deck round the pool and mostly stand. Everything
## else - the look, the gait, panic, being shot or knocked off - is Pedestrian's. Rooftops loads
## this by path (a Building must not compile against the autoloads a Pedestrian needs).

## The deck's top (in the chunk's space) and the part of it they may stand on; the pool they keep
## out of.
var deck_y := 0.0
var area := Rect2()
var avoid := Rect2()


func _init() -> void:
	cross_chance = 0.0
	pause_chance = 0.85
	pause_seconds = Vector2(8.0, 30.0)
	add_to_group("roof_goer")


func _ground_y(_x: float, _z: float, _fallback: float) -> float:
	return deck_y


func _random_ring_point(_sidewalk: float) -> Vector2:
	for k in 12:
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if not avoid.grow(0.5).has_point(p):
			return p
	return Vector2(position.x, position.z)
