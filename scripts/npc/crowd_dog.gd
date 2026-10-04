class_name CrowdDog
extends Node3D
## A dog on a lead (GAME_PLAN G5): Quaternius' Shiba Inu (Ultimate Animated Animals, CC0, see
## docs/ASSETS.md) trotting at its owner's left. A child of the owner's Pedestrian node (which
## never turns; its _visual does), placed each tick a little behind and to the left of the way
## the owner faces, eased so it swings wide on turns and catches up after a stop. It sniffs the
## ground while the owner waits (Pedestrian._try_life() stops a dog walker for it now and then).
## Not simulated: no body, no collision. Hidden and frozen past `draw_range`, and its lead (a
## thin cylinder from the owner's left hand to the collar) only drawn within `lead_range`.

const MODEL := "res://assets/models/dog_shiba.glb"
## The model is 3.1 units from paws to ear tips; a Shiba stands ~0.4 m at the shoulder.
const SCALE_RANGE := Vector2(0.17, 0.21)
## Ground speed of the walk clip at speed_scale 1, in model units (a planted paw's travel,
## measured as tools/crowd/clip_probe.gd does), and the most the clip is sped up.
const WALK_CLIP_UNITS := 1.7
const MAX_RATE := 2.6

## Where the dog walks relative to its owner (metres; x to the owner's left, z ahead).
@export var heel := Vector2(0.75, 0.35)
@export var draw_range: float = 70.0
@export var lead_range: float = 30.0
@export var follow: float = 3.5

var owner_ped: Pedestrian
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _neck: int = -1
var _hand: int = -1
var _lead: MeshInstance3D
var _model: Node3D
var _offset := Vector3.ZERO
var _yaw: float = 0.0
var _clip: String = ""
var _rng := RandomNumberGenerator.new()
var _scale: float = 0.19
var _tick: int = 0
var _last := Vector3.ZERO


static func make(ped: Pedestrian, seed_value: int) -> CrowdDog:
	if not ResourceLoader.exists(MODEL):
		return null
	var dog := CrowdDog.new()
	dog.owner_ped = ped
	dog._rng.seed = seed_value
	ped.add_child(dog)
	return dog


func _ready() -> void:
	_scale = _rng.randf_range(SCALE_RANGE.x, SCALE_RANGE.y)
	_model = (load(MODEL) as PackedScene).instantiate() as Node3D
	_model.scale = Vector3.ONE * _scale
	add_child(_model)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		(mi as MeshInstance3D).visibility_range_end = draw_range
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skel = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _anim:
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for c in _anim.get_animation_list():
			_anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR
		_play("Walk")
		_anim.seek(_rng.randf() * _anim.get_animation("Walk").length, true)
	if _skel:
		_neck = _skel.find_bone("Neck2")
	_lead = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.005
	cyl.bottom_radius = 0.005
	cyl.height = 1.0
	cyl.radial_segments = 4
	cyl.rings = 1
	_lead.mesh = cyl
	_lead.material_override = PropFactory.material(Color(0.6, 0.12, 0.1), 0.6)
	_lead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lead)
	_lead.top_level = true
	_yaw = owner_ped._visual.rotation.y if owner_ped and owner_ped._visual else 0.0
	_offset = _target_offset()
	position = _offset


func _target_offset() -> Vector3:
	var yaw := owner_ped._visual.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var left := Vector3(-cos(yaw), 0.0, sin(yaw))
	return left * heel.x + fwd * heel.y


func _physics_process(delta: float) -> void:
	if owner_ped == null or not is_instance_valid(owner_ped) or owner_ped._down:
		return
	_tick += 1
	var near := owner_ped._life_near or owner_ped._lod_stride <= 2
	visible = near
	if not near:
		return
	# The owner's own LOD rate: a dog forty metres off moves on the same ticks its owner does.
	var stride := owner_ped._lod_stride
	if stride > 1 and (_tick + owner_ped._lod_tick) % stride != 0:
		return
	delta *= stride
	var want := _target_offset()
	_offset = _offset.lerp(want, 1.0 - exp(-follow * delta))
	position = _offset
	var moved := global_position - _last
	_last = global_position
	var speed := Vector2(moved.x, moved.z).length() / maxf(delta, 1e-4)
	if speed > 6.0: # a teleport or an origin shift
		speed = 0.0
	var face := owner_ped._visual.rotation.y
	if speed > 0.25:
		face = atan2(-moved.x, -moved.z)
	elif owner_ped._act != CrowdLife.Act.NONE:
		face = owner_ped._visual.rotation.y + 0.9
	_yaw = lerp_angle(_yaw, face, 1.0 - exp(-6.0 * delta))
	# The model faces +Z; the crowd's visuals face -Z.
	_model.rotation.y = _yaw + PI
	if _anim:
		if speed > 0.2 or owner_ped._speed > 0.3:
			_play("Walk")
			_anim.speed_scale = clampf(maxf(speed, owner_ped._speed) / (WALK_CLIP_UNITS * _scale), 0.6, MAX_RATE)
		else:
			_play("Idle_2_HeadLow" if owner_ped._act != CrowdLife.Act.NONE else "Idle")
			_anim.speed_scale = 1.0
		_anim.advance(delta)
	_update_lead()


func _play(clip: String) -> void:
	if clip == _clip or _anim == null or not _anim.has_animation(clip):
		return
	_clip = clip
	_anim.play(clip, 0.3)


func _update_lead() -> void:
	var pskel: Skeleton3D = owner_ped._head_skel
	var show := pskel != null and _skel != null and _neck >= 0 and owner_ped._look_near
	if show and _hand < 0:
		_hand = pskel.find_bone("LeftHand")
	if not show or _hand < 0:
		_lead.visible = false
		return
	var a := pskel.global_transform * pskel.get_bone_global_pose(_hand).origin
	var b := _skel.global_transform * _skel.get_bone_global_pose(_neck).origin
	var d := b - a
	var span := d.length()
	if span < 0.05:
		_lead.visible = false
		return
	_lead.visible = true
	# A lead hangs a little: aim it at a point below the straight line's middle, good enough at
	# street distance for a 1.4 m strap.
	var up := d / span
	var side := up.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	side = side.normalized()
	var fwd := side.cross(up).normalized()
	_lead.global_transform = Transform3D(Basis(side, up * span, fwd), (a + b) * 0.5)
