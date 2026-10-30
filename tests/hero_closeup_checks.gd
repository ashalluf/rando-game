extends RefCounted
## The hero close-up pass (wave 3, "hero-closeup"; scripts/player/hero_face.gd, hero_stride.gd,
## the eye / lash shaders, the rain on him), for tests/smoke_test.gd's room part:
##  - the living face: HeroLook puts the eye and lash shaders on and owns a HeroFace; a fresh
##    HeroFace stepped 30 s blinks every few seconds (fully shut, open again), makes many
##    saccades, keeps the eyes in their range, and aims at a point the way it lies
##  - the clip speeds: each locomotion clip's speed measured from its own planted feet (on a
##    separate hero.glb, never the player's) matches Avatar's HERO_*_SPEED, and the gait plays
##    each band's clip at the rate that keeps the feet still
##  - the rain and the skin: the four wet-able materials take the rain (wet_gain 1)
## Leans on nothing an earlier check left: it builds what it measures.

var _t: Node


func run(t: Node, player: Node3D) -> void:
	_t = t
	_check(HeroFace.closeup(), "the hero close-up pass is on (HERO_CLOSEUP)")
	var avatar: Node3D = player.get("avatar")
	var look: HeroLook = avatar.get("hero_look") if avatar else null
	_check(look != null, "the hero is dressed by HeroLook")
	if look == null:
		return
	_check_face_materials(avatar, look)
	_check_face_clock(avatar)
	_check_aim()
	await _check_strides(avatar)
	_check_gait(avatar)
	var wet_ok := true
	for key in HeroLook.WET_MATERIALS:
		var m := look.get(key) as ShaderMaterial
		wet_ok = wet_ok and m != null and float(m.get_shader_parameter("wet_gain")) == 1.0
	_check(wet_ok, "the skin, the velour, its rib bands and the hair take the rain")


func _check_face_materials(avatar: Node3D, look: HeroLook) -> void:
	_check(look.face != null and look.face.eye != null and look.face.lash != null, "HeroLook owns a living face with its eye and lash materials")
	var found := 0
	for node in avatar.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m and (m.shader == HeroLook.EYE or m.shader == HeroLook.LASH):
				found += 1
	_check(found == 2, "the eyes and the lashes wear the face shaders (%d surfaces)" % found)


func _check_face_clock(avatar: Node3D) -> void:
	var sk: Skeleton3D = avatar.find_child("Skeleton3D", true, false)
	var mesh: MeshInstance3D = null
	for node in avatar.find_children("*", "MeshInstance3D", true, false):
		if not str(node.name).begins_with("hero_shadow"):
			mesh = node
			break
	var face := HeroFace.new()
	face.attach(sk, mesh)
	var dt := 1.0 / 60.0
	var shut := false
	var opened_after := false
	var in_range := true
	for i in 30 * 60:
		face.step(dt)
		if face.blink > 0.99:
			shut = true
		elif shut and face.blink == 0.0:
			opened_after = true
		in_range = in_range and absf(face.gaze_l.x) <= face.max_yaw + 0.01 and absf(face.gaze_l.y) <= face.max_pitch + 0.01
	_check(face.blinks >= 5 and face.blinks <= 20, "the hero blinks %d times in 30 s (every 2-6 s, doubles and with saccades)" % face.blinks)
	_check(shut and opened_after, "a blink shuts the lids fully and opens them again")
	_check(face.saccades >= 12, "his eyes make %d saccades in 30 s" % face.saccades)
	_check(in_range, "the eyes stay inside their range (%.0f / %.0f degrees)" % [rad_to_deg(face.max_yaw), rad_to_deg(face.max_pitch)])
	_check(is_equal_approx(HeroFace.blink_amount(HeroFace.BLINK_CLOSE + 0.01), 1.0) and HeroFace.blink_amount(-1.0) == 0.0 and HeroFace.blink_amount(1.0) == 0.0, "the blink curve: shut after %d ms, open after" % int(HeroFace.BLINK_CLOSE * 1000.0))


func _check_aim() -> void:
	var face := HeroFace.new()
	var mid := (HeroFace.EYE_L + HeroFace.EYE_R) * 0.5
	var ahead: Vector2 = face.call("_aim", Transform3D.IDENTITY, HeroFace.EYE_L, mid + Vector3(0, 0, 20), true)
	var left: Vector2 = face.call("_aim", Transform3D.IDENTITY, HeroFace.EYE_L, mid + Vector3(10, 0, 10), true)
	var down: Vector2 = face.call("_aim", Transform3D.IDENTITY, HeroFace.EYE_L, mid + Vector3(0, -10, 10), true)
	var near_l: Vector2 = face.call("_aim", Transform3D.IDENTITY, HeroFace.EYE_L, mid + Vector3(0, 0, 0.3), true)
	var near_r: Vector2 = face.call("_aim", Transform3D.IDENTITY, HeroFace.EYE_R, mid + Vector3(0, 0, 0.3), true)
	_check(ahead.length() < 0.01 and left.x > 0.7 and down.y > 0.7 and near_l.x < -0.05 and near_r.x > 0.05,
		"the eyes aim at a point: ahead %s, his left %s, below %s, and converge on a near one" % [ahead, left, down])
	# The rotation the shader gets: yaw toward +X (his left), pitch down.
	var r := HeroFace.eye_rotation(Vector2(0.3, 0.0)) * Vector3(0, 0, 1)
	var p := HeroFace.eye_rotation(Vector2(0.0, 0.3)) * Vector3(0, 0, 1)
	_check(r.x > 0.25 and p.y < -0.25, "an eye turned left looks left, pitched down looks down")


## The clips' own speeds, measured on a separate hero.glb (the player's clips are left alone).
func _check_strides(avatar: Node3D) -> void:
	var inst := (load("res://assets/models/hero.glb") as PackedScene).instantiate() as Node3D
	avatar.get_tree().root.add_child(inst)
	await avatar.get_tree().process_frame
	var anim := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	anim.add_animation_library("moves", load(Avatar.MOVES_LIBRARY))
	var sk := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var unit := sk.global_transform.basis.get_scale().x
	var lines := []
	var ok := true
	for pair in [["Casual_Walk_inplace", Avatar.HERO_WALK_SPEED], ["run_fast_3_inplace", Avatar.HERO_RUN_SPEED], ["moves/sprint", Avatar.HERO_SPRINT_SPEED]]:
		var m := HeroStride.measure(anim, sk, pair[0], unit)
		lines.append("%s %.2f (Avatar %.2f)" % [pair[0], m.x, pair[1]])
		ok = ok and absf(m.x - pair[1]) < 0.08 * pair[1]
	inst.queue_free()
	_check(ok, "each clip's speed from its own planted feet matches Avatar's: %s" % ", ".join(lines))


## The gait: every band plays its clip at speed / the clip's speed (no foot sliding).
func _check_gait(avatar: Node3D) -> void:
	var worst := 0.0
	var clips := {}
	for v in [0.8, 1.3, 1.9, 2.5, 4.0, 6.0, 7.0, 9.4, 12.0, 18.0]:
		var g: Array = avatar.call("hero_gait", v, false)
		clips[g[0]] = true
		var natural: float = {"Casual_Walk_inplace": Avatar.HERO_WALK_SPEED, "run_fast_3_inplace": Avatar.HERO_RUN_SPEED}.get(g[0], Avatar.HERO_SPRINT_SPEED)
		worst = maxf(worst, absf(g[1] * natural - v) / v)
	_check(clips.size() == 3 and worst < 0.01, "walk, run and sprint each keep the feet planted from 0.8 to 18 m/s (worst slip %.0f%%)" % (worst * 100.0))
	var boost: Array = avatar.call("hero_gait", 3.0, true)
	_check(boost[0] == "moves/sprint", "boosting on the ground sprints")


func _check(ok: bool, label: String) -> void:
	_t.call("_check", ok, label)
