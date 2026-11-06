class_name HeroStride
extends RefCounted
## Measures a locomotion clip's natural ground speed from its own feet. In an in-place clip the
## planted foot slides backward under the hips at exactly the speed the body should travel, so a
## clip played at (ground speed / that) keeps its feet still on the ground and anything else is
## foot sliding. Used by tools/hero_closeup/stride_probe.gd (which printed Avatar's clip speeds)
## and by tests/hero_closeup_checks.gd (which holds Avatar's constants to the clips).

## Seconds between samples.
const STEP := 1.0 / 120.0
## A foot counts as planted while it is within this many metres of its lowest point in the clip.
const PLANT := 0.025


## [speed m/s, stride m (one foot's full cycle), cadence (steps a second)] of `clip` on `sk`,
## whose skeleton units are `unit` metres. Leaves the player on the clip's first frame.
static func measure(anim: AnimationPlayer, sk: Skeleton3D, clip: String, unit: float) -> Vector3:
	if not anim.has_animation(clip):
		return Vector3.ZERO
	var a := anim.get_animation(clip)
	# The ball of the foot: the ankle rises off the ground as the heel lifts, the toe stays down.
	var feet := [sk.find_bone("LeftToeBase"), sk.find_bone("RightToeBase")]
	var hips := sk.find_bone("Hips")
	anim.play(clip, 0.0)
	anim.speed_scale = 1.0
	var n := int(a.length / STEP)
	var tracks := [PackedVector3Array(), PackedVector3Array()]
	for i in n + 1:
		anim.seek(i * STEP, true)
		sk.force_update_all_bone_transforms()
		var h := sk.get_bone_global_pose(hips).origin
		for f in 2:
			var p := sk.get_bone_global_pose(feet[f]).origin
			# The foot relative to the hips' ground point (an in-place clip still sways its hips).
			tracks[f].append(Vector3(p.x - h.x, p.y, p.z - h.z) * unit)
	var speeds: Array[float] = []
	var plants := 0
	for f in 2:
		var t: PackedVector3Array = tracks[f]
		var low := INF
		for p in t:
			low = minf(low, p.y)
		var was := false
		for i in range(1, t.size()):
			var down := t[i].y < low + PLANT and t[i - 1].y < low + PLANT
			if down:
				# Backward is -Z: the rigs face +Z.
				speeds.append(-(t[i].z - t[i - 1].z) / STEP)
			if down and not was:
				plants += 1
			was = down
	if speeds.is_empty():
		return Vector3.ZERO
	# The median: the frames where the toe touches down or peels off move slower than the stance.
	speeds.sort()
	var v := speeds[speeds.size() / 2]
	var cadence := plants / a.length
	anim.seek(0.0, true)
	return Vector3(v, v * 2.0 / maxf(cadence, 0.01), cadence)


static func measure_line(anim: AnimationPlayer, sk: Skeleton3D, clip: String, unit: float) -> String:
	var m := measure(anim, sk, clip, unit)
	return "STRIDE %s speed=%.2f m/s stride=%.2f m cadence=%.2f steps/s" % [clip, m.x, m.y, m.z]
