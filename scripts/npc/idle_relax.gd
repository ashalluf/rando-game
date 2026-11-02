class_name IdleRelax
extends RefCounted
## The crowd standing like people, not like fighters (refcam person_closeup, docs/HANDOFF.md "A person
## at arm's length"). The library idles every standing person plays (CrowdGait's `gait/idle`, 80 %
## of the crowd, and CrowdLife's `life/idle`, `nod`, `shake`, `talk`) are Quaternius' UAL Idle_Loop
## retargeted: a ready stance with the shoulders up, the upper arms held out from the ribs, the
## elbows bent and the feet wide. From 1.6 m it read as a gunslinger squaring up. The rig's OWN
## "Idle" (after Pedestrian.fix_arm_pose) hangs its arms by the thighs and stands narrow.
##
## relax() blends each of those clips' shoulder / arm / forearm / hand keys toward the rig's own
## Idle at the same time (looped), and turns each thigh a few degrees in (the foot turned back flat),
## clip (the weight shift in the hips and spine, the head, the talk's gestures at a lower weight).
## Once per library resource (they are shared per rig, CrowdGait / CrowdLife cache them) - nothing
## per person, nothing per frame. IDLE_RELAX=0 (or PERSON_CLOSEUP=0) in the environment is the A/B.

## The clips relaxed, [library, clip, arm weight, stance narrowing in degrees per thigh].
const CLIPS := [
	["gait", "idle", 0.85, 5.5],
	["life", "idle", 0.85, 5.5],
	["life", "nod", 0.8, 5.5],
	["life", "shake", 0.8, 5.5],
	["life", "talk", 0.45, 5.5],
]
const ARM_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand"]
## [thigh, knee, foot] per side.
const LEGS := [["LeftUpLeg", "LeftLeg", "LeftFoot"], ["RightUpLeg", "RightLeg", "RightFoot"]]
const META := "idle_relaxed"

static var _on: int = -1


static func enabled() -> bool:
	if _on < 0:
		_on = 0 if OS.get_environment("IDLE_RELAX") == "0" or not PersonCloseup.enabled() else 1
	return _on == 1


## After a library (`lib_name`) is added to `anim`, whose default library holds the rig's own
## (arm-fixed) "Idle". Safe to call again: a library already relaxed is left alone.
static func relax(anim: AnimationPlayer, lib_name: String) -> void:
	if not enabled() or anim == null or not anim.has_animation_library(lib_name) or not anim.has_animation("Idle"):
		return
	var lib := anim.get_animation_library(lib_name)
	if lib.has_meta(META):
		return
	lib.set_meta(META, true)
	var own := anim.get_animation("Idle")
	var root := anim.get_node_or_null(anim.root_node)
	var skel: Skeleton3D = null
	if root:
		var found := root.find_children("*", "Skeleton3D", true, false)
		skel = found[0] if not found.is_empty() else null
	for row: Array in CLIPS:
		if row[0] != lib_name or not lib.has_animation(row[1]):
			continue
		lib.add_animation(row[1], blend_clip(lib.get_animation(row[1]), own, float(row[2]), float(row[3]), skel))


## A plain copy of `a` (the library's tracks are compressed: no key can be set or removed),
## every 3D track resampled at FPS: the arm rotations slerped toward `own` at that time (looped)
## by `arm_w`; each thigh turned `narrow_deg` in toward the other about the pelvis' forward axis
## (in skeleton space), the foot turned back so its sole stays as it was. Without `skel` (no rest
## offsets to tell left from right) the legs are left alone.
const FPS := 30.0


static func blend_clip(a: Animation, own: Animation, arm_w: float, narrow_deg: float, skel: Skeleton3D = null) -> Animation:
	var own_tracks := {}
	for i in own.get_track_count():
		if own.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			own_tracks[String(own.track_get_path(i).get_concatenated_subnames())] = i
	var rot := {}
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			rot[String(a.track_get_path(i).get_concatenated_subnames())] = i
	var span := maxf(own.length, 0.001)
	var n := maxi(int(ceil(a.length * FPS)), 1)
	# The legs' new thigh and foot rotations per sample, worked out first (they read the old keys).
	var legs := {}
	# How far the legs' turn moved the ankles down, per sample (skeleton units), summed over legs:
	# the hips go up by the mean, so the feet stand where the clip had them.
	var drop := PackedFloat32Array()
	drop.resize(n + 1)
	var legs_done := 0
	if skel != null and narrow_deg > 0.0 and rot.has("Hips"):
		for leg: Array in LEGS:
			if not (rot.has(leg[0]) and rot.has(leg[1]) and rot.has(leg[2])):
				continue
			var hb := skel.find_bone(leg[0])
			if hb < 0:
				continue
			var side := signf(skel.get_bone_rest(hb).origin.x)
			var thigh_q: Array = []
			var foot_q: Array = []
			for k in n + 1:
				var t := minf(float(k) / FPS, a.length)
				var hips := a.rotation_track_interpolate(rot["Hips"], t)
				var th := a.rotation_track_interpolate(rot[leg[0]], t)
				var kn := a.rotation_track_interpolate(rot[leg[1]], t)
				var ft := a.rotation_track_interpolate(rot[leg[2]], t)
				# The pelvis' own frame: its side axis is the rest's x, its forward z (rest space).
				var fwd := (hips * Vector3(0.0, 0.0, 1.0))
				var lat := (hips * Vector3(1.0, 0.0, 0.0))
				# Turn so the thigh's far end moves toward the middle: try a sign, keep the one
				# that brings the thigh's line in.
				var down := hips * th * Vector3(0.0, 1.0, 0.0)
				var ang := deg_to_rad(narrow_deg)
				var r := Quaternion(fwd.normalized(), ang)
				if signf((r * down).dot(lat) - down.dot(lat)) == side:
					r = Quaternion(fwd.normalized(), -ang)
				var th2 := hips.inverse() * r * hips * th
				var pg := hips * th * kn
				var kb := skel.find_bone(leg[1])
				var fb := skel.find_bone(leg[2])
				if kb >= 0 and fb >= 0:
					var o := skel.get_bone_rest(hb).origin
					var shin := skel.get_bone_rest(kb).origin + kn * skel.get_bone_rest(fb).origin
					var was := hips * (o + th * shin)
					var now := hips * (o + th2 * shin)
					drop[k] += was.y - now.y
				thigh_q.append(th2)
				foot_q.append(pg.inverse() * r.inverse() * pg * ft)
			legs[leg[0]] = thigh_q
			legs[leg[2]] = foot_q
			legs_done += 1
	var out := Animation.new()
	out.length = a.length
	out.loop_mode = a.loop_mode
	for i in a.get_track_count():
		var type := a.track_get_type(i)
		var nt := out.add_track(type)
		out.track_set_path(nt, a.track_get_path(i))
		out.track_set_interpolation_type(nt, a.track_get_interpolation_type(i))
		var bone := String(a.track_get_path(i).get_concatenated_subnames())
		match type:
			Animation.TYPE_ROTATION_3D:
				var j: int = own_tracks.get(bone, -1) if bone in ARM_BONES else -1
				for k in n + 1:
					var t := minf(float(k) / FPS, a.length)
					var q := a.rotation_track_interpolate(i, t)
					if legs.has(bone):
						q = legs[bone][k]
					elif arm_w > 0.0 and j >= 0:
						q = q.slerp(own.rotation_track_interpolate(j, fposmod(t, span)), arm_w)
					out.rotation_track_insert_key(nt, t, q)
			Animation.TYPE_POSITION_3D:
				for k in n + 1:
					var t := minf(float(k) / FPS, a.length)
					var p := a.position_track_interpolate(i, t)
					if bone == "Hips" and legs_done > 0:
						p.y += drop[k] / float(legs_done)
					out.position_track_insert_key(nt, t, p)
			Animation.TYPE_SCALE_3D:
				for k in n + 1:
					var t := minf(float(k) / FPS, a.length)
					out.scale_track_insert_key(nt, t, a.scale_track_interpolate(i, t))
			_:
				for k in a.track_get_key_count(i):
					out.track_insert_key(nt, a.track_get_key_time(i, k), a.track_get_key_value(i, k),
						a.track_get_key_transition(i, k))
	for key in a.get_meta_list():
		out.set_meta(key, a.get_meta(key))
	return out


## The part of `q` about the up axis (Y), and the rest.
static func twist(q: Quaternion) -> Quaternion:
	var t := Quaternion(0.0, q.y, 0.0, q.w)
	return t.normalized() if t.length_squared() > 1e-9 else Quaternion.IDENTITY


static func swing(q: Quaternion) -> Quaternion:
	return q * twist(q).inverse()
