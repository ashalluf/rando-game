class_name YardGoer
extends BeachGoer
## A woken back-yard sunbather (YardFigure): a BeachGoer whose ground is the yard's level over the
## chunk's relief, not the sand.

## The yard's level over the relief (m).
var yard_y: float = 0.15


func _ground_y(x: float, z: float, _fallback: float) -> float:
	var ch := get_parent() as CityChunk
	return yard_y + (ch._gy(x, z) if ch else 0.0)


func _pose_ground() -> float:
	return _ground_y(_home.x, _home.y, position.y) + lift
