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
## Cross-fade time between clips (seconds).
@export var blend_time: float = 0.15

var _anim: AnimationPlayer
var _clip := ""
var _lean := 0.0


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
	for clip in _anim.get_animation_list():
		_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_play(IDLE_CLIP, 1.0)
	return true


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
