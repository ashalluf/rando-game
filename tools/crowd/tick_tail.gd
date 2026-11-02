extends Node
## Runs last in every physics tick (process_physics_priority), so crowd_lab.gd can time
## everything the nodes did in between: the crowd's scripts, animation and move_and_slide.
var t0: int = 0
var total_usec: int = 0
var ticks: int = 0


func _physics_process(_delta: float) -> void:
	if t0 > 0:
		total_usec += Time.get_ticks_usec() - t0
		ticks += 1
