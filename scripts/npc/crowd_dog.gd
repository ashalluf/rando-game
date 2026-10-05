class_name CrowdDog
extends Dog
## A dog on a lead (GAME_PLAN G5; the body is DogMesh / DogRig, code-built, six breeds). It walks
## at its owner's left - a little ahead, eased so it swings wide on turns and catches up after a
## stop - at a walk or, for a small dog keeping up with a person, a trot; when the owner stops
## (Pedestrian._try_life() stops a dog walker for it now and then) it sniffs the pavement, sits and
## looks up at its owner, or stands about. It looks at the player when he comes close, wags, and a
## small dog may yap at him; a gun going off near it tucks its tail and sets it barking. Hit, it
## yelps, slips its collar and bolts (Dog). Its owner going down sets it running too.
##
## It is the owner's SIBLING under the chunk (not a child: a knocked person's node is freed, and
## the dog must outlive it), placed in the chunk's space from the owner's position each tick. Not
## simulated: no body but the hit box. Hidden and frozen when the owner is out of life range and
## past its second LOD step; the lead (a sagging ribbon from the owner's left hand to the collar)
## only drawn within the owner's look range.

## Where the dog walks relative to its owner (metres; x to the owner's left, z ahead).
@export var heel := Vector2(0.75, 0.35)
@export var follow: float = 3.5
## Lead length (metres) and the ribbon's width.
@export var lead_length: float = 1.5
@export var lead_width: float = 0.011
## Odds per stop of sniffing, else sitting (else standing about).
@export var sniff_odds: float = 0.5
@export var sit_odds: float = 0.75
## How close the player has to come before the dog notices him (metres).
@export var notice_range: float = 5.0

const LEAD_COLORS := [Color(0.55, 0.08, 0.07), Color(0.05, 0.05, 0.06), Color(0.08, 0.2, 0.45), Color(0.12, 0.32, 0.16), Color(0.6, 0.38, 0.06)]
const LEAD_SEGMENTS := 10

var owner_ped: Pedestrian
var _lead: MeshInstance3D
var _lead_mesh: ImmediateMesh
var _hand: int = -1
var _offset := Vector3.ZERO
var _tick: int = 0
var _stop_kind: int = -1
var _was_stopped: bool = false
var _pants: bool = false
var _notice_cool: float = 0.0
var _wander_t: float = 0.0
var _lead_on: bool = true


static func make(ped: Pedestrian, seed_value: int) -> CrowdDog:
	if not Dog.enabled:
		return null
	var dog := CrowdDog.new()
	dog.owner_ped = ped
	dog.roll(seed_value)
	var parent := ped.get_parent()
	if parent == null:
		return null
	dog.position = ped.position
	parent.add_child.call_deferred(dog)
	ped.tree_exiting.connect(dog._owner_leaving)
	return dog


func _ready() -> void:
	_make_body()
	_pants = _rng.randf() < 0.4
	_wander_t = _rng.randf() * 10.0
	_add_collar()
	_lead_mesh = ImmediateMesh.new()
	_lead = MeshInstance3D.new()
	_lead.mesh = _lead_mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = LEAD_COLORS[_rng.randi() % LEAD_COLORS.size()]
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lead.material_override = m
	_lead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lead.top_level = true
	add_child(_lead)
	if owner_ped and is_instance_valid(owner_ped) and owner_ped._visual:
		_yaw = owner_ped._visual.rotation.y
		_offset = _target_offset()
		position = owner_ped.position + _offset
		rotation.y = _yaw


## A nylon collar round the neck, on the neck bone.
func _add_collar() -> void:
	var b := DogMesh.breed(breed)
	var j := DogMesh.joints(breed)
	var att := BoneAttachment3D.new()
	att.bone_name = "Neck"
	rig.skeleton.add_child(att)
	var neck: Vector3 = j["Neck"]
	var head: Vector3 = j["Head"]
	var at := neck.lerp(head, 0.42)
	var r: float = float(b.neck_r) * float(b.h) * 1.02 + float(b.coat) * 0.35
	var torus := TorusMesh.new()
	torus.inner_radius = r
	torus.outer_radius = r + clampf(r * 0.12, 0.006, 0.012)
	torus.rings = 20
	torus.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	var m := StandardMaterial3D.new()
	m.albedo_color = LEAD_COLORS[(_rng.randi() + 2) % LEAD_COLORS.size()]
	m.roughness = 0.55
	mi.material_override = m
	# The bone's rest is a translation; its frame is the skeleton's. The collar's axis along the neck.
	var axis := (head - neck).normalized()
	mi.transform = Transform3D(DogRig._aim(Vector3.UP, axis, Vector3.RIGHT) * Basis.from_scale(Vector3(1.0, 2.2, 1.0)), at - neck)
	att.add_child(mi)


func _target_offset() -> Vector3:
	var yaw := owner_ped._visual.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var left := Vector3(-cos(yaw), 0.0, sin(yaw))
	var wob := sin(_wander_t * 0.7) * 0.15
	return left * (heel.x + wob) + fwd * (heel.y + sin(_wander_t * 0.43) * 0.2)


func _owner_leaving() -> void:
	if fleeing or not is_inside_tree():
		return
	if owner_ped != null and is_instance_valid(owner_ped) and owner_ped._down:
		_drop_lead()
		var away := global_position - owner_ped.global_position
		away.y = 0.0
		_bolt(away.normalized() if away.length_squared() > 0.01 else -global_basis.z)
	else:
		# Trimmed with the crowd, or its chunk went: the dog goes with its owner.
		queue_free()


func _drop_lead() -> void:
	_lead_on = false
	if _lead:
		_lead.visible = false


func _on_hit() -> void:
	_drop_lead()


func _on_startle(_at: Vector3) -> void:
	if fleeing:
		return
	# Barks at it, tail tucked; the owner (who panics too) drags it along.
	bark(_rng.randi_range(2, 3) if not is_small() else _rng.randi_range(4, 7))


func _physics_process(delta: float) -> void:
	if rig == null:
		return
	if fleeing:
		_lead.visible = false
		_tick_flee(delta)
		_advance_rig(delta)
		return
	if owner_ped == null or not is_instance_valid(owner_ped):
		queue_free()
		return
	if owner_ped._down:
		_owner_leaving()
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
	_wander_t += delta
	var stopped := owner_ped._act != CrowdLife.Act.NONE and owner_ped._speed < 0.3
	var want := _target_offset()
	if stopped:
		# Stopped: the dog stays where it is, a little nearer its person.
		want = _offset.lerp(want, 0.15)
	_offset = _offset.lerp(want, 1.0 - exp(-follow * delta))
	var prev := global_position
	position = owner_ped.position + _offset
	var moved := global_position - prev
	var speed := Vector2(moved.x, moved.z).length() / maxf(delta, 1e-4)
	if speed > 9.0: # a teleport or an origin shift
		speed = 0.0
	var face := _yaw
	if speed > 0.25:
		face = atan2(-moved.x, -moved.z)
	elif stopped:
		face = owner_ped._visual.rotation.y + 0.9
	var prev_yaw := _yaw
	_yaw = lerp_angle(_yaw, face, 1.0 - exp(-6.0 * delta))
	_turn = wrapf(_yaw - prev_yaw, -PI, PI) / maxf(delta, 1e-4)
	rotation.y = _yaw
	# What it does at a stop: picked once per stop.
	if stopped and not _was_stopped:
		var r := _rng.randf()
		_stop_kind = 0 if r < sniff_odds else (1 if r < sit_odds else 2)
	_was_stopped = stopped
	rig.speed = speed
	rig.turn = _turn
	rig.sniff = 1.0 if stopped and _stop_kind == 0 else 0.0
	rig.sit = 1.0 if stopped and _stop_kind == 1 else 0.0
	rig.pant = (0.6 if _pants else 0.0) * clampf(speed, 0.0, 1.0)
	rig.fear = clampf(_fear_left / 3.0, 0.0, 1.0)
	rig.wag = 0.35 + (0.35 if stopped else 0.0)
	rig.look_at = Vector3.INF
	if stopped and _stop_kind != 0 and owner_ped._head_skel:
		rig.look_at = rig.to_local(owner_ped.global_position + Vector3.UP * 1.55)
	_notice_player(delta)
	_advance_rig(delta)
	_update_lead()


## The player close by: the dog looks at him and wags; a small dog may yap.
func _notice_player(dt: float) -> void:
	_notice_cool = maxf(_notice_cool - dt, 0.0)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var d := player.global_position.distance_to(global_position)
	if d > notice_range:
		return
	rig.look_at = rig.to_local(player.global_position + Vector3.UP * 1.2)
	rig.wag = 0.9
	if _notice_cool <= 0.0:
		_notice_cool = _rng.randf_range(6.0, 14.0)
		if _rng.randf() < (0.45 if is_small() else 0.15):
			bark(_rng.randi_range(1, 3))


func _update_lead() -> void:
	var pskel: Skeleton3D = owner_ped._head_skel
	var show := pskel != null and owner_ped._look_near and _lead_on
	if show and _hand < 0:
		_hand = pskel.find_bone("LeftHand")
	_lead_mesh.clear_surfaces()
	if not show or _hand < 0:
		return
	var a := pskel.global_transform * pskel.get_bone_global_pose(_hand).origin
	var sk := rig.skeleton
	var np := sk.get_bone_global_pose(DogMesh.B_NECK).origin
	var hp := sk.get_bone_global_pose(DogMesh.B_HEAD).origin
	var b := sk.global_transform * np.lerp(hp, 0.42) + Vector3.UP * float(DogMesh.breed(breed).neck_r) * height() * 0.9
	var span := a.distance_to(b)
	if span < 0.05 or span > 4.0:
		return
	var sag := maxf(lead_length - span, 0.0) * 0.45 + 0.02
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else a + Vector3.UP
	_lead_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var pts: Array[Vector3] = []
	for i in LEAD_SEGMENTS + 1:
		var t := float(i) / float(LEAD_SEGMENTS)
		pts.append(a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
	for i in pts.size():
		var along := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := along.cross(eye - pts[i]).normalized() * lead_width * 0.5
		var n := side.cross(along).normalized()
		_lead_mesh.surface_set_normal(n)
		_lead_mesh.surface_add_vertex(pts[i] - side)
		_lead_mesh.surface_set_normal(n)
		_lead_mesh.surface_add_vertex(pts[i] + side)
	_lead_mesh.surface_end()
