class_name CemeteryVisitor
extends Pedestrian
## A visitor in a memorial park (Cemetery): strolls the drive's verges a few tens of metres at a
## time, on the rise (Cemetery.height() over the chunk's ground), and stops now and then by a
## grave. Never crosses a street. Everything else - the look, the gait, panic, being knocked
## down - is Pedestrian's (no gun fires in the park, but a car can still come through the gate).

var pl: Dictionary = {}

## How far along the drive one stroll goes, at most (points of the drive's polyline, ~3 m each).
const STROLL := 14


func _ready() -> void:
	cross_chance = 0.0
	super._ready()


func _ground_y(x: float, z: float, fallback: float) -> float:
	var y := super._ground_y(x, z, fallback)
	if pl.is_empty():
		return y
	return y + CemeteryBuild.LAWN_LIFT + Cemetery.height(pl, Vector2(x, z))


func _random_ring_point(_sidewalk: float) -> Vector2:
	if pl.is_empty():
		return Vector2(position.x, position.z)
	var road: PackedVector2Array = pl.road
	var here := Vector2(position.x, position.z)
	var best := 0
	var bd := INF
	for i in road.size():
		var d := here.distance_squared_to(road[i])
		if d < bd:
			bd = d
			best = i
	var i := clampi(best + _rng.randi_range(-STROLL, STROLL), 2, road.size() - 2)
	var dir := (road[i + 1] - road[i - 1]).normalized()
	var side := Vector2(-dir.y, dir.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
	return road[i] + side * (Cemetery.ROAD_W * 0.5 + _rng.randf_range(0.6, 2.4))
