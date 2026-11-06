extends SceneTree
## Compiles the terminal kerb's scripts and the files that call them (seconds):
##   godot --headless --path . --script tools/terminal_curb/compile.gd
func _initialize() -> void:
	for p in ["res://scripts/world/terminal_curb.gd", "res://scripts/npc/curb_traveller.gd", "res://scripts/world/landmarks.gd",
			"res://scripts/world/airport_terminal.gd", "res://scripts/npc/traffic.gd"]:
		var s: Script = load(p)
		print("COMPILE ", p, " ", s != null and s.can_instantiate())
	quit()
