extends "res://tools/crowd/life_clips.gd"
## The street performers' clips (Buskers / Busker), retargeted onto every crowd rig exactly as
## tools/crowd/life_clips.gd retargets the crowd's everyday clips (its _retarget(), same sources:
## Quaternius' Universal Animation Library 1 and 2, CC0), written to
## assets/models/crowd_busk/<rig>_busk.res. A Busker adds it to its rig's AnimationPlayer as the
## "busk" library (Busker.attach_clips()); nobody else loads it.
##
## Fetch the sources first (tools/crowd/fetch_life_clips.sh), then:
##   godot --headless --path . -s tools/crowd/busk_clips.gd
## RIGS=crowd_a,crowd_b limits it.

const BUSK_OUT := "res://assets/models/crowd_busk/"
## [source file, source clip, our name, loop, leg swing, leg settle] (life_clips.gd's columns).
const BUSK_CLIPS := [
	["UAL1_Standard.glb", "Dance_Loop", "dance", true, 1.0, 0.0],
	["UAL1_Standard.glb", "Crouch_Idle_Loop", "crouch", true, 1.0, 0.0],
	["UAL2_Standard.glb", "Idle_Lantern_Loop", "lantern", true, 1.0, 0.6],
	["UAL1_Standard.glb", "Spell_Simple_Idle_Loop", "spell", true, 1.0, 0.6],
]


func _initialize() -> void:
	var fps := 20.0
	var only := OS.get_environment("RIGS").split(",", false)
	var srcs := {}
	for c: Array in BUSK_CLIPS:
		if not srcs.has(c[0]):
			var node := _load(SRC_DIR + c[0])
			if node == null:
				push_error("BUSK missing source %s: run tools/crowd/fetch_life_clips.sh" % c[0])
				quit(1)
				return
			srcs[c[0]] = node
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BUSK_OUT))
	var rigs: Array[String] = []
	for f in DirAccess.get_files_at("res://assets/models/"):
		if f.begins_with("crowd_") and f.ends_with(".glb") and (only.is_empty() or f.get_basename() in only):
			rigs.append(f.get_basename())
	rigs.sort()
	for rig in rigs:
		var inst: Node = (load("res://assets/models/%s.glb" % rig) as PackedScene).instantiate()
		inst.name = rig
		var tgt := Rig.new(inst)
		var lib := AnimationLibrary.new()
		for c: Array in BUSK_CLIPS:
			var sroot: Node = srcs[c[0]]
			var src := Rig.new(sroot)
			var ap: AnimationPlayer = sroot.find_children("*", "AnimationPlayer", true, false)[0]
			var clip := _retarget(src, tgt, ap.get_animation(c[1]), c[2], c[3], fps, c[4], c[5])
			clip.compress()
			lib.add_animation(c[2], clip)
		var path := BUSK_OUT + rig + "_busk.res"
		var err := ResourceSaver.save(lib, path, ResourceSaver.FLAG_COMPRESS)
		print("BUSK wrote %s (%s), %d KB" % [path, error_string(err), FileAccess.get_file_as_bytes(path).size() / 1024])
		inst.free()
	for n in srcs.values():
		(n as Node).free()
	quit()
