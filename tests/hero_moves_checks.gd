extends RefCounted
## The hero's moves (Avatar + HeroMotion + the "moves" library from tools/hero/hero_clips.gd), for
## tests/smoke_test.gd: the library is there with every clip and the hero's own finger keys; the
## procedural layer runs first in the skeleton's stack, before the gun stance, both arm IKs and the
## hands; and staged on the real player (its own physics paused): flying lays the body along the
## velocity with the gun hand ahead of the head, falling throws the left arm out (the left IK
## lets go), each landing speed picks its clip, a round flinches him away from it and the spring
## settles, a weapon change draws the new gun from the hip, standing still long enough plays an
## idle variant, and the tracksuit folds still follow the pose. Untyped Avatar access (get/call),
## like the rest of the smoke test.

var _t: Node


func run(t: Node, player: Node3D) -> void:
	_t = t
	var avatar: Node3D = player.get("avatar")
	_check(avatar != null, "the hero avatar is there for the moves checks")
	if avatar == null:
		return
	var anim: AnimationPlayer = avatar.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = avatar.find_child("Skeleton3D", true, false)
	_check_library(anim)
	_check_stack(sk)
	player.set_physics_process(false)
	var manager: Node = player.get("weapon_manager")
	var gun: Node = manager.get("current")
	var motion: Node = sk.find_child("HeroMotion", false, false)
	var dt := 1.0 / 60.0
	avatar.call("debug_reset")
	# Flight: level at 40 m/s.
	for i in 60:
		avatar.call("drive", dt, 40.0, false, 0.0, true, (avatar.get_parent() as Node3D).global_basis * Vector3(0, 0, -40))
		avatar.call("hold_gun", gun, false, dt)
	var head_up: float = (avatar.basis.orthonormalized() * Vector3.UP).y
	_check(float(motion.get("fly")) > 0.95 and head_up < 0.25, "flying level lays the hero along his velocity (fly %.2f, head axis up %.2f)" % [motion.get("fly"), head_up])
	var mount: Vector3 = (manager as Node3D).position
	var ahead := -mount.z
	_check(ahead > 0.5, "the flying fist: the gun is out ahead of him (%.2f m forward of the body)" % ahead)
	var ik_l: SkeletonModifier3D = sk.find_child("GunHandsIKLeft", false, false)
	_check(ik_l != null and (not ik_l.active or ik_l.influence < 0.05), "the left hand lets go of the gun in flight")
	# Falling fast: arms out.
	avatar.call("debug_reset")
	for i in 60:
		avatar.call("drive", dt, 2.0, false, -40.0, false, Vector3(0, -40, -2))
		avatar.call("hold_gun", gun, false, dt)
	_check(float(motion.get("fall")) > 0.9 and ik_l.influence < 0.05, "a fast fall throws the left arm out (fall %.2f, left IK %.2f)" % [motion.get("fall"), ik_l.influence])
	# Landings by speed.
	var picks := []
	for pair in [[40.0, 0.0, "moves/land"], [80.0, 0.0, "moves/land_hero"], [80.0, 12.0, "moves/roll"]]:
		avatar.call("debug_reset")
		avatar.call("landed", pair[0], pair[1])
		avatar.call("drive", dt, pair[1], true, 0.0, false, Vector3(0, 0, -pair[1]))
		picks.append(anim.current_animation)
		if anim.current_animation != pair[2]:
			picks.append("!" + pair[2])
	_check(not str(picks).contains("!"), "each landing speed picks its clip %s" % str(picks))
	# A round from his front: the chest goes back, then settles.
	avatar.call("debug_reset")
	avatar.call("hit_from", avatar.global_position + (avatar.get_parent() as Node3D).global_basis * Vector3(0, 1.3, -8.0), 60.0)
	var peak := 0.0
	for i in 20:
		avatar.call("drive", dt, 0.0, true, 0.0, false, Vector3.ZERO)
		peak = maxf(peak, (motion.get("flinch") as Vector3).length())
	for i in 120:
		avatar.call("drive", dt, 0.0, true, 0.0, false, Vector3.ZERO)
	var rest: float = (motion.get("flinch") as Vector3).length()
	_check(peak > 0.1 and rest < 0.01, "a hit flinches the chest away and the spring settles (peak %.2f rad, after 2 s %.3f)" % [peak, rest])
	# The draw.
	avatar.call("debug_reset")
	avatar.call("hold_gun", gun, false, dt)
	var other: Node = manager.get("weapons")[(manager.call("current_index") + 1) % 3]
	avatar.call("hold_gun", other, false, dt)
	var drawing: float = avatar.get("_draw")
	for i in 60:
		avatar.call("hold_gun", other, false, dt)
	_check(drawing < 0.2 and float(avatar.get("_draw")) >= 1.0, "a weapon change draws the new gun (draw %.2f, then %.2f)" % [drawing, avatar.get("_draw")])
	avatar.call("hold_gun", gun, false, dt)
	# An idle variant after standing still, and the watch lets the left hand go.
	avatar.call("debug_reset")
	avatar.set("_idle_next", 0.5)
	for i in 40:
		avatar.call("drive", dt, 0.0, true, 0.0, false, Vector3.ZERO)
	var variant := anim.current_animation
	_check(variant.begins_with("moves/idle_"), "standing still plays an idle variant (%s)" % variant)
	avatar.call("_start_oneshot", "moves/idle_watch", 0.0, 4.2, 1.0, 0.0)
	for i in 70:
		avatar.call("drive", dt, 0.0, true, 0.0, false, Vector3.ZERO)
		avatar.call("hold_gun", gun, false, dt)
	_check(ik_l.influence < 0.2, "checking the watch takes the left hand off the gun (left IK %.2f)" % ik_l.influence)
	# Moving cuts it.
	for i in 5:
		avatar.call("drive", dt, 6.0, true, 0.0, false, Vector3(0, 0, -6))
	_check(not anim.current_animation.begins_with("moves/idle_"), "walking off cuts the idle variant (%s)" % anim.current_animation)
	await _t.get_tree().process_frame
	await _t.get_tree().process_frame
	var look = avatar.get("hero_look")
	if look:
		var w: Vector4 = look.cloth.get_shader_parameter("wrinkle_weights")
		_check(w.x + w.y + w.z + w.w > 0.05, "the tracksuit's folds still follow the pose with the moves (%s)" % w)
	avatar.call("debug_reset")
	for i in 30:
		avatar.call("hold_gun", gun, false, dt)
	player.set_physics_process(true)


func _check_library(anim: AnimationPlayer) -> void:
	var names := ["idle", "jump_start", "jump_air", "land", "land_hero", "roll", "sprint",
		"idle_look", "idle_neck", "idle_watch", "idle_stretch"]
	var missing := []
	var no_fingers := []
	for n: String in names:
		var a := anim.get_animation("moves/" + n) if anim and anim.has_animation("moves/" + n) else null
		if a == null:
			missing.append(n)
		elif a.find_track(NodePath("Armature/Skeleton3D:RightHandIndex2"), Animation.TYPE_ROTATION_3D) < 0:
			no_fingers.append(n)
	_check(missing.is_empty() and no_fingers.is_empty(), "the hero's moves library has its %d clips with his finger keys (missing %s, no fingers %s)" % [names.size(), missing, no_fingers])
	var watch := anim.get_animation("moves/idle_watch") if anim and anim.has_animation("moves/idle_watch") else null
	_check(watch != null and watch.get_meta("free_left", Vector2.ZERO) != Vector2.ZERO, "the watch clip says when the left hand is off the gun")


func _check_stack(sk: Skeleton3D) -> void:
	var order := []
	for c in sk.get_children():
		if c is SkeletonModifier3D:
			order.append(str(c.name))
	var want := ["HeroMotion", "GunTwist", "GunHandsIK", "GunHandsIKLeft", "GunHandsTurn"]
	var at := []
	for w in want:
		at.append(order.find(w))
	var sorted := at.duplicate()
	sorted.sort()
	_check(not at.has(-1) and at == sorted, "the hero's modifiers run moves, stance, right IK, left IK, hands (%s)" % str(order))


func _check(ok: bool, label: String) -> void:
	_t.call("_check", ok, label)
