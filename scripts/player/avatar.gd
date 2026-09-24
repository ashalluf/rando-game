class_name Avatar
extends Node3D
## The player's animated body: one of the rigged characters (see Pedestrian.MODELS), driven by
## the player's motion every physics frame. Idle, walk and run clips are picked by speed and
## sped up to match the feet; in the air the run stride is frozen (jump) or slowed (fall), and a
## boost leans the whole body forward. Falls back silently when the model is missing.

const IDLE_CLIP := "Idle"
const WALK_CLIP := "Casual_Walk_inplace"
const RUN_CLIP := "run_fast_3_inplace"
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
## How fast the gun comes up to the shoulder when aiming or firing, and back down (per second).
@export var raise_speed: float = 7.0
## Where the elbows point while holding a gun, relative to each shoulder joint (body space).
@export var right_elbow_pole: Vector3 = Vector3(0.5, -0.6, 0.35)
@export var left_elbow_pole: Vector3 = Vector3(-0.45, -0.6, 0.2)

var _anim: AnimationPlayer
var _clip := ""
var _lean := 0.0

# Gun handling (owner, 2026-09-24: "the weapons not even in the hands"). The gun used to hang at
# a fixed point off the body while the walk clip swung both arms past it. Now the gun is placed
# relative to the hero's own right shoulder - at the hip, raised to the shoulder to aim or fire -
# and two-bone IK pulls both wrists onto its grips (Weapon.grip_right / grip_left).
var _skeleton: Skeleton3D
var _ik: TwoBoneIK3D
var _hands: GripHands
var _mount: Node3D
var _player: Node3D
var _grip_r: Node3D
var _grip_l: Node3D
var _body: Node3D
var _bone_r: int = -1
var _raise := 0.0


## Loads the rig; false when the file is missing or has no AnimationPlayer.
func load_model(path: String, look: int = 3) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var scene: PackedScene = load(path)
	if scene == null:
		return false
	var inst := scene.instantiate() as Node3D
	Pedestrian.prepare_rig(inst, look)
	inst.rotation.y = PI # the rigs face +Z; the player's visual faces -Z
	add_child(inst)
	_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		return false
	Pedestrian.fix_arm_pose(_anim, path)
	for clip in _anim.get_animation_list():
		_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_play(IDLE_CLIP, 1.0)
	_skeleton = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	return true


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
	_ik = TwoBoneIK3D.new()
	_ik.name = "GunHandsIK"
	_skeleton.add_child(_ik)
	_ik.setting_count = 2
	var arms := [["Right", _grip_r, pole_r], ["Left", _grip_l, pole_l]]
	for i in arms.size():
		var side: String = arms[i][0]
		_ik.set_root_bone_name(i, side + "Arm")
		_ik.set_middle_bone_name(i, side + "ForeArm")
		_ik.set_end_bone_name(i, side + "Hand")
		_ik.set_target_node(i, _ik.get_path_to(arms[i][1]))
		_ik.set_pole_node(i, _ik.get_path_to(arms[i][2]))
		_ik.set_pole_direction(i, pole_axis)
	_ik.active = false
	_hands = GripHands.new()
	_hands.name = "GunHandsTurn"
	_skeleton.add_child(_hands)
	_hands.hands = [[_skeleton.find_bone("RightHand"), _grip_r], [_skeleton.find_bone("LeftHand"), _grip_l]]
	_hands.active = false


## The gun the hands are on: at the hip, or up at the shoulder while `raised` (aiming, firing).
## Null (in a car, no gun out) lets the arms go back to the clip.
func hold_gun(weapon: Weapon, raised: bool, delta: float) -> void:
	if _ik == null:
		return
	if weapon == null:
		_ik.active = false
		_hands.active = false
		return
	_raise = move_toward(_raise, 1.0 if raised else 0.0, raise_speed * delta)
	var t := smoothstep(0.0, 1.0, _raise)
	# The live shoulder, not the rest pose: the clips stand the rig 7 cm taller than it is bound
	# and carry the shoulders 12 cm higher again, which put every grip out of arm's reach. It
	# also lets the gun ride the walk the way it does on a real shoulder.
	var shoulder := _body.to_local(_skeleton.to_global(_skeleton.get_bone_global_pose(_bone_r).origin))
	_mount.position = shoulder + weapon.hold_hip.lerp(weapon.hold_aim, t)
	weapon.rotation_degrees = weapon.hold_hip_rot.lerp(Vector3.ZERO, t)
	# In the mount's space, through the gun's own transform so the recoil kick carries the hands.
	_grip_r.transform = weapon.transform * Transform3D(_hand_basis(weapon.grip_right_fingers, weapon.grip_right_palm), weapon.grip_right)
	_grip_l.transform = weapon.transform * Transform3D(_hand_basis(weapon.grip_left_fingers, weapon.grip_left_palm), weapon.grip_left)
	_ik.active = true
	_hands.active = true


## A hand bone's basis from where its fingers run and its palm faces (see finger_axis_sign).
func _hand_basis(fingers: Vector3, palm: Vector3) -> Basis:
	var y := fingers.normalized() * finger_axis_sign
	var zp := palm * palm_axis_sign
	var z := (zp - y * zp.dot(y)).normalized()
	return Basis(y.cross(z), y, z)


func has_model() -> bool:
	return _anim != null


## Called by the player after it moved: horizontal speed, floor contact, vertical velocity, boost.
func drive(delta: float, speed: float, on_floor: bool, vertical: float, boosting: bool) -> void:
	if _anim == null:
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
