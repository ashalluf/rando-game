class_name ParkletDiner
extends Pedestrian
## Somebody at a parklet (Parklets): a DINER sat at a bistro table on the crowd's seated clips
## (CrowdLife: sit, and sit_talk to whoever shares the table, looking at them), or the WAITER
## walking a beat between the restaurant's door and the tables, stopping at each to take an
## order (the talking clip, facing the table). A crowd rig like anyone, so shot, knocked, bled
## and ragdolled the same way, in the crowd cap and the "pedestrian" group (they hear gunfire and
## witness crimes).
##
## Seated, a diner is placed, never solved against the deck's collision (kinematic, mask 0), so
## the chair holds them; gunfire sends them running like everyone else and they do not come back
## (their dinner is ruined). A waiter goes back to work once the scare is over.

enum Role { DINER, WAITER }

## A waiter's uniform: black shirt and black trousers (the crowd's garment regions).
const WAITER_TOP := Color(0.035, 0.035, 0.04)
const WAITER_PANTS := Color(0.03, 0.03, 0.035)
static var _waiter_mats: Dictionary = {}

## Seconds a waiter stands at a table, and at the door.
@export var table_seconds: Vector2 = Vector2(4.0, 9.0)
@export var door_seconds: Vector2 = Vector2(5.0, 14.0)
## How far from a table's middle the waiter stands, on the pavement side (m).
@export var waiter_stand: float = 0.78

var role: int = Role.DINER
var seat := Vector2.ZERO
var seat_yaw: float = 0.0
## Where the other chair at the table is (who a diner talks to).
var mate_at := Vector2.ZERO
var door := Vector2.ZERO
var tables: Array = []
## The way out into the road from the kerb (the deck's +z).
var out_dir := Vector2(0.0, 1.0)
var _leg: int = 0
var _beat: float = 0.0
var _mate: Node3D = null
var _mate_looked: bool = false
## The waiter's tray, held level on the left palm (placed every frame, never on the bone: the
## hand's own turn would tip it).
var _tray: MeshInstance3D = null
var _tray_w: float = 0.0


func setup_diner(block_rect: Rect2, seed_value: int, at: Vector2, yaw: float, mate: Vector2) -> void:
	setup(block_rect, 4.0, seed_value)
	role = Role.DINER
	seat = at
	seat_yaw = yaw
	mate_at = mate


func setup_waiter(block_rect: Rect2, seed_value: int, door_at: Vector2, table_spots: Array, out: Vector2) -> void:
	setup(block_rect, 4.0, seed_value)
	role = Role.WAITER
	# Nobody serves in a cap or a backpack (the crowd's own roll is still made).
	accessory_chance = 0.0
	door = door_at
	tables = table_spots
	out_dir = out
	_leg = 1 + 2 * (absi(hash([seed_value, "leg"])) % maxi(tables.size(), 1))


## They get the crowd's life clips (Pedestrian only gives them to the plain crowd).
func _lives() -> bool:
	return true


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_carry = CrowdLife.Carry.NONE
	_jogger = false
	_dog_walker = false


func _add_model() -> bool:
	if not super._add_model():
		return false
	if role != Role.WAITER:
		return true
	var inst: Node3D = null
	for c in _visual.get_children():
		if c is Node3D:
			inst = c
			break
	if inst == null:
		return true
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			var mat := waiter_material(src.albedo_texture)
			if mat:
				mi.material_override = mat
	return true


## The rig's look in the waiter's blacks (one material per rig texture).
static func waiter_material(albedo: Texture2D) -> ShaderMaterial:
	var key := albedo.resource_path if albedo.resource_path != "" else str(albedo.get_instance_id())
	if _waiter_mats.has(key):
		return _waiter_mats[key]
	var base := character_material(albedo, 1)
	if base == null:
		return null
	var mat := base.duplicate() as ShaderMaterial
	mat.set_shader_parameter("cloth_hue", WAITER_TOP.h)
	mat.set_shader_parameter("cloth_sat", WAITER_TOP.s)
	mat.set_shader_parameter("cloth_value", WAITER_TOP.v)
	mat.set_shader_parameter("cloth_strength", 0.97)
	mat.set_shader_parameter("pants_hue", WAITER_PANTS.h)
	mat.set_shader_parameter("pants_sat", WAITER_PANTS.s)
	mat.set_shader_parameter("pants_value", WAITER_PANTS.v)
	mat.set_shader_parameter("pants_strength", 0.95)
	mat.set_shader_parameter("cloth_roughness", 0.75)
	mat.set_shader_parameter("cloth_shade_keep", 0.6)
	_waiter_mats[key] = mat
	return mat


func _ready() -> void:
	super()
	if role == Role.DINER:
		_sit_down()
	else:
		_kinematic = true
		collision_mask = 0
		_next_leg(true)


## In the chair for good (until something frightens them): hips on the seat, the legs re-solved
## to the chair's height (Pedestrian._sit_pose()).
func _sit_down() -> void:
	var info := _sit_clip_info()
	if info.is_empty():
		# A rig without the seated clips: stand at the table instead.
		_act = CrowdLife.Act.STAND
		_act_left = INF
		_act_face = seat_yaw
		_life_base = CrowdLife.IDLE if _life_ok else ""
		_place_at(seat, seat_yaw)
		_stage = Stage.DOING
		_life_clip = _life_base
		return
	_kinematic = true
	collision_mask = 0
	var face := Vector2(-sin(seat_yaw), -cos(seat_yaw))
	_act = CrowdLife.Act.SIT
	# The hips' spot on the chair, a little back from the seat's middle.
	var hips := seat - face * 0.04
	_seat = {"p": hips, "yaw": seat_yaw, "taken": self, "record": null}
	_act_spot = hips + face * float(info.back) * _visual.scale.z
	_act_face = seat_yaw
	_seat_drop = float(info.hips) * _visual.scale.y - (ParkletKit.SEAT_Y + CrowdLife.HIP_OVER_SEAT)
	_act_left = INF
	# Pedestrian's own beat (a bench neighbour) never fires: the diner's is _diner_beat().
	_act_beat = INF
	_place_at(_act_spot, _act_face)
	_stage = Stage.DOING
	_life_base = CrowdLife.SIT
	_life_clip = CrowdLife.SIT
	_beat = _life.randf_range(0.5, 4.0)


## Nobody walks a diner or a waiter off: out of range they stay where they are.
func _life_range_changed(_near: bool) -> void:
	pass


func _update_lod() -> void:
	super()
	if (role == Role.DINER and _act == CrowdLife.Act.SIT) or (role == Role.WAITER and _panic_left <= 0.0):
		# On the deck: placed, never solved against its collision.
		_kinematic = true
		collision_mask = 0


func _physics_process(delta: float) -> void:
	super(delta)
	if _down:
		return
	# The scare is over and they are walking about: a waiter goes back to work.
	if role == Role.WAITER and _act == CrowdLife.Act.NONE and _panic_left <= 0.0 and _cross == Cross.NONE:
		_next_leg(false)


## The waiter carries the tray: the left forearm forward (the crowd's coffee hold) and the tray
## level on the palm, while working and near; never running, never down.
func _life_pose(delta: float) -> void:
	super(delta)
	if role != Role.WAITER or _head_skel == null:
		return
	var carry := _life_near and not _down and _panic_left <= 0.0 and _clip != RUN_CLIP
	_tray_w = move_toward(_tray_w, 1.0 if carry else 0.0, delta * 3.0)
	var fore := _head_skel.find_bone("LeftForeArm")
	var hand := _head_skel.find_bone("LeftHand")
	if fore < 0 or hand < 0:
		return
	if _tray_w > 0.001:
		var w := smoothstep(0.0, 1.0, _tray_w)
		var f := _head_skel.get_bone_global_pose(fore)
		var now := (_head_skel.get_bone_global_pose(hand).origin - f.origin).normalized()
		var turn := Quaternion(now, CrowdLife.CUP_FOREARM.normalized())
		_set_global_rot(fore, Basis(Quaternion.IDENTITY.slerp(turn, w)) * f.basis)
	if _tray == null and carry:
		_tray = MeshInstance3D.new()
		_tray.name = "Tray"
		_tray.mesh = ParkletKit.tray()
		_tray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tray.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_tray.top_level = true
		add_child(_tray)
	if _tray == null:
		return
	_tray.visible = _tray_w > 0.5
	if not _tray.visible:
		return
	# Level, over the palm: the hand's origin is the wrist, the palm a hand's length on toward
	# the fingers, and the tray's floor just over it.
	var sk_xf := _head_skel.global_transform
	var wrist := sk_xf * _head_skel.get_bone_global_pose(hand).origin
	var elbow := sk_xf * _head_skel.get_bone_global_pose(fore).origin
	var along := wrist - elbow
	along.y = 0.0
	along = along.normalized() if along.length_squared() > 1e-6 else -_visual.global_transform.basis.z
	var yaw := _visual.global_rotation.y
	_tray.global_transform = Transform3D(Basis(Vector3.UP, yaw), wrist + along * 0.07 + Vector3.UP * 0.035)


func _do_act(delta: float) -> void:
	if role == Role.WAITER and _stage == Stage.DOING and _act_left - delta <= 0.0:
		_next_leg(false)
		return
	super(delta)
	if role == Role.DINER and _act == CrowdLife.Act.SIT and _stage == Stage.DOING:
		_diner_beat(delta)


## Every few seconds a diner talks to their table mate or sits listening, looking at them.
func _diner_beat(delta: float) -> void:
	if not _life_ok:
		return
	_beat -= delta
	if _beat > 0.0:
		return
	_beat = _life.randf_range(3.0, 8.0)
	var mate := _find_mate()
	if _one_shot_left <= 0.0:
		var base := CrowdLife.SIT_TALK if mate != null and _life.randf() < 0.55 else CrowdLife.SIT
		if base != _life_base:
			_life_base = base
			_life_clip = base
	if mate != null:
		_life_look = mate.global_position + Vector3.UP * 1.1
	else:
		# Alone: down at the plate, or out at the street.
		_life_look = Vector3.INF if _life.randf() < 0.5 else global_position + Vector3(-sin(seat_yaw), 0.0, -cos(seat_yaw)) * 2.0 + Vector3.UP * 0.6


## Whoever sits in the other chair at this table (looked for once).
func _find_mate() -> Node3D:
	if _mate_looked:
		return _mate if is_instance_valid(_mate) and not (_mate as Pedestrian)._down else null
	_mate_looked = true
	var parent := get_parent()
	if parent == null:
		return null
	for n in parent.get_children():
		var d := n as ParkletDiner
		if d != null and d != self and d.role == Role.DINER and d.seat.distance_to(mate_at) < 0.05:
			_mate = d
			break
	return _mate


## The waiter's next stop: the door, then a table, the door again, the next table...
func _next_leg(at_once: bool) -> void:
	_act = CrowdLife.Act.STAND
	var at_table := _leg % 2 == 1 and not tables.is_empty()
	var target: Vector2
	var face: Vector2
	if at_table:
		var t: Vector2 = tables[(_leg / 2) % tables.size()]
		target = t - out_dir * waiter_stand
		face = out_dir
		_act_left = _life.randf_range(table_seconds.x, table_seconds.y)
		_life_base = CrowdLife.TALK if _life_ok else ""
	else:
		target = door
		face = -out_dir
		_act_left = _life.randf_range(door_seconds.x, door_seconds.y)
		_life_base = CrowdLife.IDLE if _life_ok else ""
	_leg += 1
	_act_spot = target
	_act_face = atan2(-face.x, -face.y)
	_act_beat = INF
	_life_look = Vector3.INF
	if at_once:
		_place_at(target, _act_face)
		_stage = Stage.DOING
		_life_clip = _life_base
	else:
		_life_clip = ""
		_stage = Stage.GOING
		# Straight there across the pavement and onto the deck (no ring route: the deck is off it).
		_target = target
		_route = PackedVector2Array()
		_route_pending = false
