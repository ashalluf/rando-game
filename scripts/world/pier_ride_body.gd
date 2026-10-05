class_name PierRideBody
extends StaticBody3D
## The collision of a pier ride (the Ferris wheel, the coaster's track and train): world layer,
## so you can stand on a deck or a track and the camera stops at the steel. In the
## "rail_vehicle" group, which WeaponFX calls metal - a round sparks and pings off it - and
## take_hit() takes the hit and changes nothing: the rides keep running however hard they are shot.

## Rounds this ride has taken (the checks read it).
var hits: int = 0


func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("rail_vehicle")
	add_to_group("pier_ride")


func take_hit(_shape: int = -1, _damage: float = 0.0, _dir: Vector3 = Vector3.ZERO, _at: Vector3 = Vector3.ZERO, _kind: int = 0) -> void:
	hits += 1
