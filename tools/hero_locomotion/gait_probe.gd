extends SceneTree
## Measures the hero's gait clips for HeroLoco's sync table: each clip's length, its speed and
## cadence (HeroStride), and the seconds each foot touches down. Prints the GDScript line to paste
## into HeroLoco.GAITS. Headless, seconds:
##   godot --headless --path . -s tools/hero_locomotion/gait_probe.gd

const CLIPS := ["Casual_Walk_inplace", "run_fast_3_inplace", "moves/sprint"]


func _initialize() -> void:
	var inst: Node3D = (load("res://assets/models/hero.glb") as PackedScene).instantiate()
	get_root().add_child(inst)
	await process_frame
	var anim: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = inst.find_child("Skeleton3D", true, false)
	load("res://scripts/npc/pedestrian.gd").fix_arm_pose(anim, "res://assets/models/hero.glb")
	anim.add_animation_library("moves", load("res://assets/models/hero_moves.res"))
	var unit := 0.01
	for clip in CLIPS:
		var a := anim.get_animation(clip)
		var m: Vector3 = load("res://scripts/player/hero_stride.gd").measure(anim, sk, clip, unit)
		var downs: Array = load("res://scripts/player/hero_loco.gd").touchdowns(anim, sk, clip, unit)
		print("GAIT %s len=%.3f speed=%.3f stride=%.3f cadence=%.3f left_down=%s right_down=%s" % [clip, a.length, m.x, m.y, m.z, downs[0], downs[1]])
	quit()

