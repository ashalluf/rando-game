class_name RailSection
extends AnimatableBody3D
## One section of a Coral Line car (LightRailTrain builds four a train): the solid, kinematic
## body the weapons hit. It takes every round and blast and keeps running; the sparks, the ping
## and the holes are the weapons' own (WeaponFX calls the "rail_vehicle" group metal).

func take_hit(_shape: int, _damage: float, _dir: Vector3 = Vector3.ZERO, _at: Vector3 = Vector3.INF, _kind: int = 0) -> void:
	pass
