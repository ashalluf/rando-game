extends SceneTree
## Compiles the wildlife's scripts once the autoloads exist and builds every species' meshes
## (seconds): godot --headless --path . --script tools/wildlife/compile.gd

const SCRIPTS := ["res://scripts/npc/wild_species.gd", "res://scripts/npc/wild_animal.gd",
	"res://scripts/world/wildlife.gd", "res://scripts/npc/dog_mesh.gd", "res://scripts/npc/dog_rig.gd",
	"res://scripts/npc/dog.gd", "res://scripts/ui/loading_screen.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	var t0 := Time.get_ticks_msec()
	WildSpecies.warm()
	print("WARM %d ms" % (Time.get_ticks_msec() - t0))
	for n: String in WildSpecies.NAMES:
		var line := n
		for lv in 3:
			var tc := DogMesh.triangle_count(n, lv)
			line += "  L%d %d+%d" % [lv, tc.x, tc.y]
		print(line)
	for h in [3.0, 6.5, 12.0, 19.0, 22.0]:
		var s := "HOUR %.1f" % h
		for n: String in WildSpecies.NAMES:
			s += " %s=%.2f" % [n, WildSpecies.activity(n, h)]
		print(s)
	quit()
