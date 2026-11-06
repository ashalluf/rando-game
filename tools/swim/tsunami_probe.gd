extends Node
## How high a running tsunami lifts the sea where the swimming check drops the hero (90 m out).
##   godot --headless --path . tools/swim/tsunami_probe.tscn
func _ready() -> void:
	var m: MacroMap = GroundCoverage.make_plan(1337).macro
	var p := Vector2(m.coast_x(300.0) - 90.0, 300.0)
	for ts in [0.0, 0.5, 1.0]:
		var hi := -INF
		for k in 80:
			hi = maxf(hi, SeaSurface.height(m, p, 1.0 + k * 0.5, [1.0, ts, Surf.params(1.0)[0], Surf.params(1.0)[1]]))
		print("SWIM tsunami %.1f: top of the sea %.2f, floor %.2f" % [ts, hi, SeaSurface.seabed(SeaSurface.shore_distance(m, p).x)])
	get_tree().quit()
