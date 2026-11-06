extends Node
## Compiles the freeway incidents' scripts and the checks with the autoloads present (seconds):
##   godot --headless --path . tools/freeway_incidents/compile.tscn
func _ready() -> void:
	for p in ["res://scripts/npc/freeway_incidents.gd", "res://scripts/npc/freeway_motorist.gd", "res://scripts/vehicles/freeway_patrol.gd",
			"res://scripts/world/freeway_incident_kit.gd", "res://scripts/world/freeway_kit.gd", "res://scripts/npc/traffic.gd",
			"res://tests/freeway_incidents_checks.gd"]:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	get_tree().quit()
