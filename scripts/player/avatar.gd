class_name Avatar
extends Node3D
## The player's animated body: one of the rigged characters (see Pedestrian.MODELS), driven by
## the player's motion every physics frame. Idle, walk and run clips are picked by speed and
## sped up to match the feet; in the air the run stride is frozen (jump) or slowed (fall), and a
## boost leans the whole body forward. Falls back silently when the model is missing.
##
## The hero (hero.glb) also moves like a protagonist (the "moves" library, tools/hero/hero_clips.gd,
## and HeroMotion, the procedural layer under the gun hands): idle variants after standing a few
## seconds, a take-off crouch, the air and fall poses, a landing by fall speed (LandingFX's scale:
## a dip, a hard crouch, the hero landing, a roll when running), a sprint, stepping round on the
## spot, a flinch away from each round (PlayerHealth.hit_taken), a draw on a weapon change, the
## flight pose (laid along the velocity, banked into turns, the gun hand forward) and foot IK.
## The police officers' Avatars are crowd rigs and keep the old three clips.

const IDLE_CLIP := "Idle"
const WALK_CLIP := "Casual_Walk_inplace"
const RUN_CLIP := "run_fast_3_inplace"
## The hero's moves, retargeted from the Universal Animation Library (tools/hero/hero_clips.gd).
const MOVES_LIBRARY := "res://assets/models/hero_moves.res"
## Speeds (m/s) at which the walk and run clips play at their natural pace.
const WALK_CLIP_SPEED := 1.3
const RUN_CLIP_SPEED := 5.0

## Above this ground speed (m/s) the run clip replaces the walk clip.
@export var run_threshold: float = 4.0
## Forward lean (radians) while boosting through the air.
@export var boost_lean: float = 0.6
## Forward lean (radians) while boosting along the ground.
@export var ground_lean: float = 0.22
## Which axis of a forearm bone the elbow-pole IK turns toward the pole (SecondaryDirection).
@export var pole_axis: int = SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Z
## Which way a hand bone's axes point on these rigs: its Y along the fingers (+1) or back up
## the arm (-1), and its Z out of the palm (+1) or out of the back of the hand (-1).
@export var finger_axis_sign: float = 1.0
@export var palm_axis_sign: float = 1.0
## Cross-fade time between clips (seconds).
@export var blend_time: float = 0.15

@export_group("Hero moves")
## Above this ground speed (m/s) the sprint replaces the run (walk_speed is 12).
@export var sprint_threshold: float = 9.5
## Seconds of standing still before an idle variant (look round, stretch, watch, neck), a range.
@export var idle_variant_after: Vector2 = Vector2(5.0, 9.0)
## Fall speeds (m/s) for the landings: from `land_dip` the knees take it (a normal 12 m jump
## lands at ~47), from `land_hard` the hero landing, LandingFX.slam_speed and up the hardest.
@export var land_dip: float = 30.0
@export var land_hard: float = 60.0
## Running faster than this (m/s) when a hard landing comes, he rolls out of it instead.
@export var roll_speed: float = 7.0
## How far the body is laid over along the velocity while boost-flying (0 upright, 1 fully).
@export var fly_lay: float = 1.0
## Bank into a turn while flying: radians of roll per radian a second of turn, and the most.
@export var fly_bank: float = 0.35
@export var fly_bank_max: float = 0.7
## Below this fall speed (m/s) the fall pose (arms out) is not used.
@export var fall_pose_speed: float = 14.0
## The flinch: how hard a round knocks the chest (radians a second per 40 damage), the spring's
## stiffness and damping.
@export var flinch_kick: float = 7.0
@export var flinch_stiffness: float = 220.0
@export var flinch_damping: float = 16.0
## Seconds the draw takes on a weapon change (the new gun from the hip to the hands).
@export var draw_time: float = 0.42
## Turning on the spot faster than this (radians a second) steps the feet round.
@export var turn_step_rate: float = 1.4
## Plant the feet on uneven ground while standing (two rays a physics frame).
@export var foot_ik: bool = true
## The most the hips come down for a foot (m).
@export var foot_ik_reach: float = 0.25
## How far the fingers close round a grip is the gun's own (Weapon.curl_*, fitted per gun by
## tools/grip_fit.gd). Which way the curl goes: flip if the fingers bend back instead of closing.
@export var palm_curl_sign: float = 1.0
## Rim sheen on the hero's velour tracksuit in the sun (0 flat cotton, 1 satin-bright edges).
@export var velour_rim: float = 0.45
## The velour's edge-on brightening in any light (the pile catching light sideways).
@export var velour_sheen: float = 0.55
## Subsurface scattering in the hero's skin (Forward+ only; 0 is a plastic mannequin).
@export var skin_sss: float = 0.4
## Density of the hero's stubble hairs over his beard area.
@export var stubble: float = 0.9
## Depth of the pores and fine lines in the hero's skin.
@export var pores: float = 0.6
## How far the hero's hair highlight stretches across the strands (0 a round plastic sheen).
@export var hair_anisotropy: float = 0.8
## How fast the gun comes up to the shoulder when aiming or firing, and back down (per second).
@export var raise_speed: float = 7.0
## 0..1: how firmly the chest holds its shooting stance against the clip's own turning (the
## idle swings the shoulders 75 degrees; at 0 the support hand leaves the gun as it does).
@export var stance_hold: float = 1.0
## Where the elbows point while holding a gun, relative to each shoulder joint (body space).
@export var right_elbow_pole: Vector3 = Vector3(0.5, -0.6, 0.35)
@export var left_elbow_pole: Vector3 = Vector3(-0.45, -0.6, 0.2)

var _anim: AnimationPlayer
## The hero's materials and pose-driven wrinkles (HeroLook), null on the crowd rigs.
var hero_look: HeroLook
var _clip := ""
## The wingsuit (scripts/player/wingsuit.gd) sets these while gliding: the spread (0..1), how far
## the body is laid over (radians, a right angle level, more diving) and the roll (+ banks right).
var glide: float = 0.0
var glide_tilt: float = 0.0
var glide_bank: float = 0.0
var _lean := 0.0

# Gun handling (owner, 2026-09-24: "the weapons not even in the hands"). The gun used to hang at
# a fixed point off the body while the walk clip swung both arms past it. Now the gun is placed
# relative to the hero's own right shoulder - at the hip, raised to the shoulder to aim or fire -
# and two-bone IK pulls both wrists onto its grips (Weapon.grip_right / grip_left).
var _skeleton: Skeleton3D
var _ik: TwoBoneIK3D
var _twist: AimTwist
var _hands: GripHands
var _mount: Node3D
var _player: Node3D
var _grip_r: Node3D
var _grip_l: Node3D
var _body: Node3D
var _bone_r: int = -1
var _raise := 0.0
var _ik_l: TwoBoneIK3D

# The hero's moves (null / empty on a crowd rig).
var _motion: HeroMotion
var _moves := false
## The one-shot clip playing ("" none), its time, how long it runs, when movement may cut it.
var _oneshot := ""
var _oneshot_t := 0.0
var _oneshot_end := 0.0
var _oneshot_break := 0.0
var _oneshot_air := false
var _idle_t := 0.0
var _idle_next := 6.0
var _last_variant := ""
var _rng := RandomNumberGenerator.new()
## 0..1 weights eased each frame: the flight pose, the fall pose, the left hand on the gun.
var _fly := 0.0
var _fall := 0.0
var _left := 1.0
var _tilt := 0.0
var _bank := 0.0
var _flinch := Vector3.ZERO
var _flinch_v := Vector3.ZERO
var _draw := 1.0
## 0..1: the gun lowered to the hip for a roll or a hero landing (the hand goes to the ground).
var _low := 0.0
var _last_gun: Weapon
var _prev_yaw := 0.0
var _yaw_rate := 0.0
var _vel_yaw := 0.0
var _vel_yaw_rate := 0.0
var _feet_lift := Vector2.ZERO
var _hips_drop := 0.0


## Loads the rig; false when the file is missing or has no AnimationPlayer.
func load_model(path: String, look: int = 3, tracksuit: Color = Color(0, 0, 0, 0)) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var scene: PackedScene = load(path)
	if scene == null:
		return false
	var inst := scene.instantiate() as Node3D
	Pedestrian.prepare_rig(inst, look)
	if tracksuit.a > 0.0:
		_dress_tracksuit(inst, tracksuit)
	hero_look = HeroLook.dress(inst, {"skin_sss": skin_sss, "stubble": stubble, "pores": pores,
		"hair_anisotropy": hair_anisotropy, "velour_sheen": velour_sheen, "velour_rim": velour_rim})
	if hero_look == null:
		_velour_sheen(inst)
	inst.rotation.y = PI # the rigs face +Z; the player's visual faces -Z
	add_child(inst)
	_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		return false
	Pedestrian.fix_arm_pose(_anim, path)
	for clip in _anim.get_animation_list():
		_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	# The hero's moves (tools/hero/hero_clips.gd), added after fix_arm_pose(), which must never
	# see them, and after the loop above, which would loop the one-shots.
	_skeleton = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if hero_look != null and _skeleton and ResourceLoader.exists(MOVES_LIBRARY) and not _anim.has_animation_library("moves"):
		_anim.add_animation_library("moves", load(MOVES_LIBRARY))
		_moves = true
		# First in the stack: setup_gun_hands() adds the stance, the IK and the hands after it.
		_motion = HeroMotion.new()
		_motion.name = "HeroMotion"
		_skeleton.add_child(_motion)
		_rng.seed = hash(path)
		_idle_next = _rng.randf_range(idle_variant_after.x, idle_variant_after.y)
	_play(IDLE_CLIP, 1.0)
	return true


## Velour is brighter at a grazing angle than head on - that sheen is the fabric. The glTF
## importer drops it, so the hero's own tracksuit materials get Godot's rim lobe back here.
func _velour_sheen(inst: Node3D) -> void:
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat and mat.resource_name.begins_with("hero_tracksuit"):
				mat.rim_enabled = true
				mat.rim = velour_rim
				mat.rim_tint = 0.6


## Jacket and trousers in one velour colour with white piping (Pedestrian.tracksuit_material).
func _dress_tracksuit(inst: Node3D, color: Color) -> void:
	Pedestrian.add_piping(inst)
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh else null
		if src == null or src.albedo_texture == null:
			continue
		var mat := Pedestrian.tracksuit_material(src.albedo_texture, color)
		if mat:
			mi.material_override = mat


## Puts the hands on the guns in `mount` (the WeaponManager, a child of `body`). Call once the
## model is loaded. Does nothing on a rig without the usual arm bones.
func setup_gun_hands(mount: Node3D, body: Node3D, player: Node3D) -> void:
	if _skeleton == null:
		return
	var bones := ["RightArm", "RightForeArm", "RightHand", "LeftArm", "LeftForeArm", "LeftHand"]
	for b in bones:
		if _skeleton.find_bone(b) < 0:
			return
	_mount = mount
	_player = player
	_body = body
	_bone_r = _skeleton.find_bone("RightArm")
	# The elbow poles hang off the shoulders where the rig stands at rest; they only steer
	# which way the elbows bend, so they do not need to follow the clip.
	var shoulder_r := body.to_local(_skeleton.to_global(_skeleton.get_bone_global_rest(_bone_r).origin))
	var shoulder_l := body.to_local(_skeleton.to_global(_skeleton.get_bone_global_rest(_skeleton.find_bone("LeftArm")).origin))
	_grip_r = Node3D.new()
	_grip_r.name = "GripRight"
	mount.add_child(_grip_r)
	_grip_l = Node3D.new()
	_grip_l.name = "GripLeft"
	mount.add_child(_grip_l)
	var pole_r := Node3D.new()
	pole_r.name = "ElbowPoleRight"
	body.add_child(pole_r)
	pole_r.position = shoulder_r + right_elbow_pole
	var pole_l := Node3D.new()
	pole_l.name = "ElbowPoleLeft"
	body.add_child(pole_l)
	pole_l.position = shoulder_l + left_elbow_pole
	# The stance first: modifiers run in child order, so the IK reaches from twisted shoulders.
	_twist = AimTwist.new()
	_twist.name = "GunTwist"
	for pair in [["Spine02", 0.25], ["Spine01", 0.35], ["Spine", 0.4], ["neck", -0.45], ["Head", -0.55]]:
		var b := _skeleton.find_bone(pair[0])
		if b >= 0:
			_twist.bones.append([b, pair[1]])
	_twist.left_arm = _skeleton.find_bone("LeftArm")
	_twist.right_arm = _bone_r
	_skeleton.add_child(_twist)
	_twist.active = false
	# One IK per arm, so the left hand can let go of the gun (an idle variant, the draw, the
	# flight and fall poses) by its own influence while the right keeps it.
	_ik = _arm_ik("GunHandsIK", "Right", _grip_r, pole_r)
	_ik_l = _arm_ik("GunHandsIKLeft", "Left", _grip_l, pole_l)
	_hands = GripHands.new()
	_hands.name = "GunHandsTurn"
	_skeleton.add_child(_hands)
	_hands.hands = [[_skeleton.find_bone("RightHand"), _grip_r], [_skeleton.find_bone("LeftHand"), _grip_l]]
	_hands.fingers = _grip_fingers()
	_hands.active = false


func _arm_ik(node_name: String, side: String, target: Node3D, pole: Node3D) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new()
	ik.name = node_name
	_skeleton.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, side + "Arm")
	ik.set_middle_bone_name(0, side + "ForeArm")
	ik.set_end_bone_name(0, side + "Hand")
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.set_pole_direction(0, pole_axis)
	ik.active = false
	return ik


## Curl for every finger joint of a rig with finger bones (the hero; the crowd rigs have none),
## so the hands close round the gun instead of lying flat on it. The axis each joint turns
## about is worked out from the rest pose: the palm faces along the cross of the knuckle line
## and the finger direction, and a joint turns about (its own direction x palm normal), which
## swings its tip toward the palm. The right index stays straighter: it is on the trigger.
func _grip_fingers() -> Array:
	var out: Array = []
	for side in ["Right", "Left"]:
		var hand := _skeleton.find_bone(side + "Hand")
		var index1 := _skeleton.find_bone(side + "HandIndex1")
		var pinky1 := _skeleton.find_bone(side + "HandPinky1")
		if hand < 0 or index1 < 0 or pinky1 < 0:
			continue
		var at_hand := _skeleton.get_bone_global_rest(hand).origin
		var at_index := _skeleton.get_bone_global_rest(index1).origin
		var at_pinky := _skeleton.get_bone_global_rest(pinky1).origin
		var along := ((at_index + at_pinky) * 0.5 - at_hand).normalized()
		var across := (at_index - at_pinky).normalized()
		var palm := across.cross(along).normalized() * palm_curl_sign * (1.0 if side == "Right" else -1.0)
		for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			for joint in 3:
				var bone := _skeleton.find_bone("%sHand%s%d" % [side, finger, joint + 1])
				if bone < 0:
					continue
				var rest := _skeleton.get_bone_global_rest(bone)
				var child := _skeleton.find_bone("%sHand%s%d" % [side, finger, joint + 2])
				var dir: Vector3 = (_skeleton.get_bone_global_rest(child).origin - rest.origin).normalized() if child >= 0 else rest.basis.y.normalized()
				var axis := dir.cross(palm)
				if axis.length() < 0.001:
					continue
				var local_axis := (rest.basis.orthonormalized().inverse() * axis.normalized()).normalized()
				# Which of the gun's curls this joint takes (Weapon.curl_*), set per gun in hold_gun().
				var kind := "curl_right" if side == "Right" else "curl_left"
				if finger == "Thumb":
					kind = "curl_thumb" if side == "Right" else "curl_left_thumb"
				elif finger == "Index" and side == "Right":
					kind = "curl_trigger"
				var entry := [bone, _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion(), local_axis, 0.0, kind, joint]
				if finger == "Thumb" and joint == 0:
					# The thumb's base also rolls about the hand's length (Weapon.thumb_wrap),
					# which carries the thumb across the grip: opposition, not flexion.
					entry.append_array([(rest.basis.orthonormalized().inverse() * along).normalized(), 0.0, 0 if side == "Right" else 1])
				out.append(entry)
	return out


## The gun the hands are on: at the hip, or up at the shoulder while `raised` (aiming, firing).
## Null (in a car, no gun out) lets the arms go back to the clip. On the hero the gun also
## follows the moves: drawn from the hip after a weapon change, out to the side in the fall
## pose, forward in the flying fist; and the left hand lets go when a move needs it.
func hold_gun(weapon: Weapon, raised: bool, delta: float) -> void:
	if _ik == null:
		return
	if weapon == null:
		_ik.active = false
		_ik_l.active = false
		_hands.active = false
		_twist.active = false
		_last_gun = null
		return
	if _moves and weapon != _last_gun and _last_gun != null:
		_draw = 0.0
	_last_gun = weapon
	_draw = minf(_draw + delta / maxf(draw_time, 0.05), 1.0)
	_raise = move_toward(_raise, 1.0 if raised else 0.0, raise_speed * delta)
	var t := smoothstep(0.0, 1.0, _raise)
	# The moves that take the gun somewhere else fade out while it is raised: aiming wins.
	var fly := _fly * (1.0 - t)
	var fall := _fall * (1.0 - t)
	_twist.angle = deg_to_rad(lerpf(weapon.hold_twist.x, weapon.hold_twist.y, t)) * (1.0 - fly)
	_twist.hold = stance_hold
	_twist.active = true
	# The live shoulder, not the rest pose: the clips stand the rig 7 cm taller than it is bound
	# and carry the shoulders 12 cm higher again, which put every grip out of arm's reach. It
	# also lets the gun ride the walk the way it does on a real shoulder. It is the shoulder
	# where the stance put it last frame; the clip's own is 20 cm off it while the idle turns.
	var at := _twist.shoulder if _twist.shoulder != Vector3.INF else _skeleton.get_bone_global_pose(_bone_r).origin
	var shoulder := _body.to_local(_skeleton.to_global(at))
	var offset := weapon.hold_hip.lerp(weapon.hold_aim, t)
	var rot := weapon.hold_hip_rot.lerp(Vector3.ZERO, t)
	if _moves:
		# Out to the side for balance while falling.
		offset = offset.lerp(FALL_GUN, fall)
		rot = rot.lerp(FALL_GUN_ROT, fall)
		# The draw: up from the right hip (the first part of draw_time), barrel down.
		var d := smoothstep(0.0, 1.0, _draw)
		offset = DRAW_GUN.lerp(offset, d)
		rot = DRAW_GUN_ROT.lerp(rot, d)
	_mount.position = shoulder + offset
	weapon.rotation_degrees = rot
	if _moves and _low > 0.0:
		# Rolling, or down on one knee: the gun goes in against the right thigh, barrel down and
		# forward, where the crouched arm still reaches it.
		var thigh := _body.to_local(_skeleton.to_global(_skeleton.get_bone_global_pose(_skeleton.find_bone("RightUpLeg")).origin))
		var low := smoothstep(0.0, 1.0, _low) * (1.0 - t)
		_mount.position = _mount.position.lerp(thigh + LOW_GUN, low)
		weapon.rotation_degrees = weapon.rotation_degrees.lerp(LOW_GUN_ROT, low)
	if _moves and fly > 0.0:
		# The flying fist: the gun hand out ahead of the head along the body, the barrel along it.
		var lay := basis.orthonormalized()
		_mount.position = _mount.position.lerp(shoulder + lay * FLY_GUN, fly)
		var head := lay * Vector3.UP
		var pitch := atan2(head.y, -head.z) - _mount.rotation.x
		weapon.rotation = weapon.rotation.lerp(Vector3(pitch, 0.0, 0.0), fly)
	# In the mount's space, through the gun's own transform so the recoil kick carries the hands.
	_grip_r.transform = weapon.transform * Transform3D(_hand_basis(weapon.grip_right_fingers, weapon.grip_right_palm), weapon.grip_right)
	_grip_l.transform = weapon.transform * Transform3D(_hand_basis(weapon.grip_left_fingers, weapon.grip_left_palm), weapon.grip_left)
	for f in _hands.fingers:
		var curl: Vector3 = weapon.get(f[4])
		f[3] = deg_to_rad(curl[f[5]])
		if f.size() > 8:
			f[7] = deg_to_rad(weapon.thumb_wrap[f[8]])
	# The left hand: on the gun unless a move has it (raised, it always comes back to the gun).
	var left := 1.0
	if _moves:
		left = maxf(minf(minf(minf(_left, 1.0 - _fly), 1.0 - glide), minf(1.0 - _fall, smoothstep(0.55, 1.0, _draw))), t)
	_ik.active = true
	_ik_l.active = left > 0.001
	_ik_l.influence = left
	_hands.left_weight = left
	_hands.active = true


## A hand bone's basis from where its fingers run and its palm faces (see finger_axis_sign).
func _hand_basis(fingers: Vector3, palm: Vector3) -> Basis:
	var y := fingers.normalized() * finger_axis_sign
	var zp := palm * palm_axis_sign
	var z := (zp - y * zp.dot(y)).normalized()
	return Basis(y.cross(z), y, z)


func has_model() -> bool:
	return _anim != null



## Called by the player after it moved: horizontal speed, floor contact, vertical velocity,
## boost, and (the hero's flight and fall) the whole velocity.
func drive(delta: float, speed: float, on_floor: bool, vertical: float, boosting: bool, velocity: Vector3 = Vector3.ZERO) -> void:
	if _anim == null:
		return
	if _moves:
		_drive_moves(delta, speed, on_floor, vertical, boosting, velocity)
		return
	var lean_target := 0.0
	if not on_floor:
		if boosting:
			_play(RUN_CLIP, 1.7)
			lean_target = boost_lean
		elif vertical > 1.0:
			_play(RUN_CLIP, 0.3) # a frozen stride on the way up
		else:
			_play(RUN_CLIP, 0.7) # a slow flail on the way down
	elif speed < 0.4:
		_play(IDLE_CLIP, 1.0)
	elif speed < run_threshold:
		_play(WALK_CLIP, clampf(speed / WALK_CLIP_SPEED, 0.7, 2.4))
	else:
		_play(RUN_CLIP, clampf(speed / RUN_CLIP_SPEED, 0.8, 2.8))
		if boosting:
			lean_target = ground_lean
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-8.0 * delta))
	rotation.x = -_lean # forward is -Z, so a negative X rotation tips the head forward


func _play(clip: String, speed: float) -> void:
	if _clip != clip and _anim.has_animation(clip):
		_anim.play(clip, blend_time)
		_clip = clip
	_anim.speed_scale = speed


# --- The hero's moves -------------------------------------------------------------------------

## Where the gun goes for the moves, relative to the gun shoulder: in the visual's space for the
## fall (out to his right) and the draw (down at the right hip), in the laid-over body's own
## space for the flying fist (ahead of the head).
const FALL_GUN := Vector3(0.16, -0.2, -0.3)
const FALL_GUN_ROT := Vector3(-8.0, 30.0, -25.0)
const DRAW_GUN := Vector3(0.08, -0.5, 0.0)
const DRAW_GUN_ROT := Vector3(-78.0, 15.0, 0.0)
const LOW_GUN := Vector3(0.16, -0.12, -0.32)
const LOW_GUN_ROT := Vector3(-30.0, 30.0, 0.0)
const FLY_GUN := Vector3(-0.12, 0.38, -0.2)
## The idle variants (moves library) picked after standing still.
const IDLE_VARIANTS := ["idle_look", "idle_neck", "idle_watch", "idle_stretch"]
## Seconds the left hand takes to let go of the gun and to come back for a variant.
const LEFT_RAMP := 0.35
## Natural speed of the sprint clip (tools/hero/hero_clips.gd prints its gait).
const SPRINT_CLIP_SPEED := 8.3


## The player jumped: the take-off (air: a mid-air jump, the same spring of the legs).
func jumped(air: bool) -> void:
	if not _moves:
		return
	_start_oneshot("moves/jump_start", 0.0 if not air else 0.05, 0.55, 1.4, 0.0, true)


## The player touched down at `fall` m/s, running at `run` m/s.
func landed(fall: float, run: float) -> void:
	if not _moves:
		return
	if fall >= land_hard:
		_low = 1.0 # the gun is in against the thigh as he hits the ground
	if fall >= land_hard and run >= roll_speed:
		_start_oneshot("moves/roll", 0.5, 1.4, 0.95, 1.05)
	elif fall >= land_hard:
		_start_oneshot("moves/land_hero", 0.0, 1.27, 1.0 if fall >= LandingFX.slam_speed else 1.35, 0.7)
	elif fall >= land_dip:
		# The knees take it: the deepest part of the library's landing, cut short when he runs on.
		_start_oneshot("moves/land", 0.1 if run < 2.0 else 0.18, 0.85, 1.5, 0.12)


## A round hit him from `at` (scene position); `amount` is the damage.
func hit_from(at: Vector3, amount: float) -> void:
	if not _moves or _skeleton == null or at == Vector3.INF:
		return
	var away := _skeleton.global_transform.basis.inverse() * (_skeleton.global_position - at)
	away.y = 0.0
	if away.length_squared() < 1e-6:
		away = Vector3(0, 0, -1)
	_flinch_v += away.normalized() * flinch_kick * clampf(amount / 40.0, 0.5, 2.0)


## Back to standing with nothing going on (tools/glshot/hero_moves_shot.gd between shots).
func debug_reset() -> void:
	_oneshot = ""
	_idle_t = 0.0
	_fly = 0.0
	_fall = 0.0
	glide = 0.0
	_left = 1.0
	_tilt = 0.0
	_bank = 0.0
	_flinch = Vector3.ZERO
	_flinch_v = Vector3.ZERO
	_draw = 1.0
	_low = 0.0
	_clip = ""
	transform = Transform3D.IDENTITY
	if _anim:
		_play(IDLE_CLIP, 1.0)


func _start_oneshot(clip: String, from: float, length: float, speed: float, breakable: float, air := false) -> void:
	if not _anim.has_animation(clip):
		return
	_anim.play(clip, blend_time, speed)
	_anim.seek(from, true)
	_anim.speed_scale = speed
	_clip = clip
	_oneshot = clip
	_oneshot_t = 0.0
	_oneshot_end = (length - from) / maxf(speed, 0.01)
	_oneshot_break = breakable / maxf(speed, 0.01)
	_oneshot_air = air


func _drive_moves(delta: float, speed: float, on_floor: bool, vertical: float, boosting: bool, velocity: Vector3) -> void:
	var k := 1.0 - exp(-10.0 * delta)
	# How fast the body is turning (stepping round on the spot) and the velocity's heading (the bank).
	var parent := get_parent() as Node3D
	var yaw := parent.global_rotation.y if parent else 0.0
	_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _prev_yaw, -PI, PI) / maxf(delta, 1e-4), k)
	_prev_yaw = yaw
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 3.0:
		var vy := atan2(-velocity.x, -velocity.z)
		_vel_yaw_rate = lerpf(_vel_yaw_rate, wrapf(vy - _vel_yaw, -PI, PI) / maxf(delta, 1e-4), 1.0 - exp(-4.0 * delta))
		_vel_yaw = vy
	else:
		_vel_yaw_rate = lerpf(_vel_yaw_rate, 0.0, k)
	var flying := boosting and not on_floor
	var falling := not on_floor and not boosting and vertical < -fall_pose_speed and glide < 0.01
	var gliding := glide > 0.001
	_fly = move_toward(_fly, 1.0 if flying else 0.0, delta * 3.0)
	_fall = move_toward(_fall, clampf((-vertical - fall_pose_speed) / 12.0, 0.0, 1.0) if falling and _oneshot == "" else 0.0, delta * 2.5)
	var left_target := 1.0
	var low_target := 0.0
	var lean_target := 0.0
	# A one-shot (take-off, landing, roll, idle variant) runs to its end unless cut.
	if _oneshot != "":
		_oneshot_t += delta
		var moving := speed > 1.0
		var cut := _oneshot_t >= _oneshot_end
		if _oneshot_air:
			cut = cut or on_floor or flying
		else:
			cut = cut or not on_floor or (moving and _oneshot_t >= _oneshot_break)
		if _oneshot.begins_with("moves/idle_"):
			cut = cut or speed > 0.4 or boosting
			var window: Vector2 = _anim.get_animation(_oneshot).get_meta("free_left", Vector2.ZERO)
			if window != Vector2.ZERO:
				var ct := _oneshot_t # the variants start at 0 and play at speed 1
				left_target = 1.0 - minf(clampf((ct - window.x) / LEFT_RAMP, 0.0, 1.0), clampf((window.y - ct) / LEFT_RAMP, 0.0, 1.0))
		elif _oneshot == "moves/roll" or _oneshot == "moves/land_hero":
			left_target = 0.0 # the hand goes to the ground
			low_target = 1.0
		if cut:
			_oneshot = ""
			_clip = ""
	if _oneshot == "":
		_idle_t = _idle_t + delta if on_floor and speed < 0.4 and not boosting else 0.0
		if not on_floor:
			if flying:
				_play("moves/jump_air", 1.0)
			else:
				_play("moves/jump_air", 1.0 if vertical > -fall_pose_speed else 1.6)
		elif speed < 0.4:
			if absf(_yaw_rate) > turn_step_rate:
				# Stepping round on the spot: the walk in place, as fast as the turn.
				_play(WALK_CLIP, clampf(absf(_yaw_rate) * 0.5, 0.6, 1.6))
			elif _idle_t > _idle_next:
				_idle_t = 0.0
				_idle_next = _rng.randf_range(idle_variant_after.x, idle_variant_after.y)
				var pick: String = IDLE_VARIANTS[_rng.randi() % IDLE_VARIANTS.size()]
				if pick == _last_variant:
					pick = IDLE_VARIANTS[(IDLE_VARIANTS.find(pick) + 1) % IDLE_VARIANTS.size()]
				_last_variant = pick
				var clip := "moves/" + pick
				if _anim.has_animation(clip):
					_start_oneshot(clip, 0.0, _anim.get_animation(clip).length, 1.0, 0.0)
					_anim.play(clip, 0.4)
			else:
				_play(IDLE_CLIP, 1.0)
		elif speed < run_threshold:
			_play(WALK_CLIP, clampf(speed / WALK_CLIP_SPEED, 0.7, 2.4))
		elif speed < sprint_threshold and not boosting:
			_play(RUN_CLIP, clampf(speed / RUN_CLIP_SPEED, 0.8, 2.8))
		else:
			_play("moves/sprint", clampf(speed / SPRINT_CLIP_SPEED, 0.9, 2.2))
			if boosting:
				lean_target = ground_lean
	_left = move_toward(_left, left_target, delta / LEFT_RAMP)
	_low = move_toward(_low, low_target, delta / LEFT_RAMP)
	# The flight: the body laid along the velocity (0 upright when climbing straight up, a right
	# angle level, more diving) and banked into the turn, about the hips.
	var tilt_target := 0.0
	if flying and velocity.length() > 4.0 and parent:
		var v := parent.global_basis.orthonormalized().inverse() * velocity
		tilt_target = clampf(atan2(-v.z, v.y), 0.0, deg_to_rad(150.0)) * fly_lay
	elif flying:
		tilt_target = boost_lean
	if gliding:
		tilt_target = glide_tilt * glide
	_tilt = lerp_angle(_tilt, tilt_target if flying or gliding else 0.0, 1.0 - exp(-6.0 * delta))
	_bank = lerpf(_bank, clampf(-_vel_yaw_rate * fly_bank, -fly_bank_max, fly_bank_max) * _fly + glide_bank * glide, 1.0 - exp(-4.0 * delta))
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-8.0 * delta))
	var air := 1.0 - (1.0 if on_floor else 0.0) * (1.0 - _fly)
	var pivot := Vector3(0.0, 0.95 * clampf(maxf(_fly, glide) + air * 0.5, 0.0, 1.0), 0.0)
	var b := Basis(Vector3.RIGHT, -(_tilt + _lean)) * Basis(Vector3.UP, _bank)
	transform = Transform3D(b, pivot - b * pivot)
	# The flinch: a spring the hits kick.
	_flinch_v += (-flinch_stiffness * _flinch - flinch_damping * _flinch_v) * delta
	_flinch += _flinch_v * delta
	if _motion:
		_motion.fly = _fly
		_motion.glide = glide
		_motion.look_up = _tilt
		_motion.fall = _fall
		_motion.flinch = _flinch
		_feet(delta, on_floor and speed < 3.0 and _oneshot == "" and _fly < 0.01)


## The foot IK: a ray down at each foot, the ground's rise under it handed to HeroMotion.
func _feet(delta: float, planted: bool) -> void:
	var want := Vector2.ZERO
	var drop := 0.0
	if foot_ik and planted and _skeleton and is_inside_tree():
		var space := get_world_3d().direct_space_state
		var base := (get_parent() as Node3D).global_position.y if get_parent() is Node3D else global_position.y
		var lifts: Array[float] = []
		for foot in ["LeftFoot", "RightFoot"]:
			var bi := _skeleton.find_bone(foot)
			var at := _skeleton.to_global(_skeleton.get_bone_global_pose(bi).origin)
			var from := Vector3(at.x, base + 0.6, at.z)
			var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 0.6 + foot_ik_reach + 0.05, 0), 1)
			if _player:
				q.exclude = [(_player as CollisionObject3D).get_rid()]
			var hit := space.intersect_ray(q) if space else {}
			lifts.append(clampf((hit.position.y - base) if hit else 0.0, -foot_ik_reach, foot_ik_reach))
		want = Vector2(lifts[0], lifts[1])
		drop = maxf(0.0, -minf(want.x, want.y))
	var k := 1.0 - exp(-12.0 * delta)
	_feet_lift = _feet_lift.lerp(want, k)
	_hips_drop = lerpf(_hips_drop, drop, k)
	_motion.foot_lift = _feet_lift
	_motion.hips_drop = _hips_drop
