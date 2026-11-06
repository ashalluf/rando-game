extends AnimatableBody3D
## A collision box FreightRailSystem lays on one of the freight cars nearest the player (props
## layer: bullets, blasts, the player and cars hit it; the player can ride it). A train shrugs off
## gunfire: WeaponFX treats the "rail_vehicle" group as metal (sparks, the ping).


func take_hit(_shape_index: int = 0, _damage: float = 0.0, _dir: Vector3 = Vector3.ZERO, _at: Vector3 = Vector3.INF, _kind: int = 0) -> void:
	pass
