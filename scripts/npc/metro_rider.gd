class_name MetroRider
extends RailRider
## Someone in the Coral Line's underground station (MetroBuild puts them there, in the crowd
## cap): level 0 waits on the island platform (boarding and alighting as RailRider does), level 1
## drifts about the concourse's ticket halls. Both keep clear of what stands on their floor (the
## bank, the lift, the benches; the stair blocks, the gates' line) by where they pick to go, and
## stand on their own floor's height. They pass through the city's ground box for good: they never
## leave the station (MetroStation.sink()'s exception, added before their first step).

## MetroStation.frame() of the station.
var frame: Dictionary = {}
## 0 the platform, 1 the concourse.
var level := 0


func _ready() -> void:
	super()
	var city := get_tree().get_first_node_in_group("city")
	var ground := city.get_node_or_null("GroundBody") as PhysicsBody3D if city else null
	if ground:
		PhysicsServer3D.body_add_collision_exception(get_rid(), ground.get_rid())


func _ground_y(x: float, z: float, fallback: float) -> float:
	if frame.is_empty():
		return super(x, z, fallback)
	if level == 1:
		return float(frame.y0) + MetroStation.CONC_FLOOR + 0.1
	return float(frame.y0) + float(frame.plat) + 0.1


func _random_ring_point(_sidewalk: float) -> Vector2:
	if state != 0 or frame.is_empty():
		return super(_sidewalk)
	var u := 0.0
	var v := 0.0
	if level == 0:
		# Either end of the island, clear of the bank (and the lift beside it) and the benches.
		u = _rng.randf_range(12.0, 29.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
		v = _rng.randf_range(1.0, 2.6) * (1.0 if _rng.randf() < 0.5 else -1.0)
	else:
		# The unpaid halls by the ticket machines, or the paid zone round the bank.
		if _rng.randf() < 0.7:
			u = _rng.randf_range(14.0, 18.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
			v = _rng.randf_range(2.2, 5.6) * (1.0 if _rng.randf() < 0.5 else -1.0)
		else:
			u = _rng.randf_range(-10.0, 7.0)
			v = _rng.randf_range(2.9, 5.8) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var w := MetroStation.to_world(frame, Vector3(u, 0.0, v))
	return Vector2(w.x, w.z)
