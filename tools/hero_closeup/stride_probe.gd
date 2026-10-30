extends SceneTree
## Measures each locomotion clip's natural ground speed from its own feet: in an in-place clip the
## planted foot slides backward at exactly the speed the body should move, so the clip must play at
## speed / that. Prints, per clip, the stance speed of each foot, the stride and the cadence.
##   godot --headless --path . --script tools/hero_closeup/stride_probe.gd
## (headless is fine: it reads bone poses, not pixels.)
const HS := preload("res://scripts/player/hero_stride.gd")
const CLIPS := ["Casual_Walk_inplace", "run_fast_3_inplace", "moves/sprint"]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst := (load("res://assets/models/hero.glb") as PackedScene).instantiate() as Node3D
	get_root().add_child(inst)
	await process_frame
	var anim := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not anim.has_animation_library("moves"):
		anim.add_animation_library("moves", load("res://assets/models/hero_moves.res"))
	var sk := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var unit := sk.global_transform.basis.get_scale().x # metres per skeleton unit
	for clip in CLIPS:
		print(HS.measure_line(anim, sk, clip, unit))
	quit()
