class_name FerrisWheel
extends Node3D
## Spins around its local Z axis; gondola children stay upright.

@export var rpm: float = 1.2

var gondolas: Array[Node3D] = []


func _process(delta: float) -> void:
	rotation.z += rpm * TAU / 60.0 * delta
	for g in gondolas:
		g.rotation.z = -rotation.z
