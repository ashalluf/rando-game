extends Node
## Measures each crowd rig's walk and run clips: how fast the planted foot travels backwards
## (the ground speed the in-place clip was authored for, at speed_scale 1) and the cycle length.
## Run: godot --headless --path . tools/crowd/clip_probe.tscn
func _ready() -> void:
	await get_tree().process_frame
	for path in Pedestrian.MODELS:
		var inst: Node3D = load(path).instantiate()
		add_child(inst)
		var sk: Skeleton3D
		for n in inst.find_children("*", "Skeleton3D", true, false): sk = n
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		Pedestrian.fix_arm_pose(ap, path)
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var out: String = path.get_file()
		for clip in [Pedestrian.WALK_CLIP, Pedestrian.RUN_CLIP]:
			var a := ap.get_animation(clip)
			ap.play(clip, 0.0)
			var n := 160
			var dt := a.length / n
			var speeds := []
			var contacts := 0
			for foot in ["LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot"]:
				var b := sk.find_bone(foot)
				var ys := PackedFloat32Array(); var zs := PackedFloat32Array()
				for k in n + 1:
					ap.seek(a.length * k / n, true)
					sk.force_update_all_bone_transforms()
					var p := sk.global_transform * sk.get_bone_global_pose(b).origin
					ys.append(p.y); zs.append(p.z)
				var ymin: float = Array(ys).min()
				# Planted: within 1.5 cm of the lowest point, moving backwards (the rig faces +Z).
				var tot := 0.0; var t := 0.0
				for k in n:
					if ys[k] < ymin + 0.015 and ys[k + 1] < ymin + 0.015:
						tot += zs[k] - zs[k + 1]; t += dt
				# Count touch-downs: the foot entering the planted band (and when the left one lands).
				if foot.ends_with("ToeBase"):
					for k in n:
						if ys[k] >= ymin + 0.015 and ys[k + 1] < ymin + 0.015:
							contacts += 1
							if foot == "LeftToeBase":
								speeds.append("L down %.3f" % (float(k + 1) / n))
				speeds.append("%s %.2f" % [foot, tot / t if t > 0.0 else 0.0])
			out += " | %s %.2fs steps=%d %s" % [clip, a.length, contacts, speeds]
		print(out)
		inst.queue_free()
	get_tree().quit()
