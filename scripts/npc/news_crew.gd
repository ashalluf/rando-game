class_name NewsCrew
extends Pedestrian
## A TV news crew member at a story (NewsCrews deploys them from a NewsVan): the REPORTER, who
## stands with the scene behind them and talks to camera with the station's hand mic, and the
## CAMERA operator, who shoots them from the shoulder. A Pedestrian, so shot, knocked, blown
## apart and ragdolled like anyone (and doing it is a crime like doing it to anyone), but it walks
## its own brain instead of the pavement ring, like EmergencyCrew:
##
##   GO      walk from the van's door to the live-shot spot NewsCrews worked out (`spot`).
##   WORK    the reporter talks (the life library's talk clip under a held mic arm), the camera
##           operator holds the shot (the camera on the shoulder, eye to the viewfinder). Gunfire
##           or a blast near them (Pedestrian._last_alarm_*) and they drop to a knee - and the
##           camera swings round to get the shot of whoever is shooting - then get back up.
##   RETURN  back to the van's door and aboard (NewsCrews.board).
##
## The arms are posed per rig from its own rest pose over the clip (EmergencyCrew's method, the
## RoughSleeper aim tables): directions of each bone's segment in rig space, +Z forward, +X the
## rig's left.

enum Role { REPORTER, CAMERA }
enum Task { GO, WORK, RETURN }

@export_group("News crew")
@export var crew_walk_speed: float = 1.45
@export var crew_hurry_speed: float = 3.6
## Gunfire or a blast this close sends them down on a knee for `duck_seconds` (m, s).
@export var duck_radius: float = 70.0
@export var duck_seconds: float = 5.5
@export_group("")

## Who plays whom: rigs dressed for it (crowd_h's pinstripe shirt, crowd_t's striped shirt,
## crowd_j's chambray, crowd_r, crowd_k, crowd_f's field jacket) and crew in work clothes. No
## teenagers, no hi-vis (crowd_o, crowd_p, crowd_s).
const REPORTER_MODELS := ["crowd_h", "crowd_t", "crowd_j", "crowd_r", "crowd_k", "crowd_f", "crowd_d"]
const CAMERA_MODELS := ["crowd_a", "crowd_b", "crowd_f", "crowd_q", "crowd_j", "crowd_d", "crowd_e"]

const POSES := {
	# The mic held up under the chin, elbow tucked: the right arm only.
	"mic": {
		"aim": {
			"RightArm": Vector3(-0.12, -0.86, 0.49), "RightForeArm": Vector3(0.42, 0.58, 0.70),
		},
		"arms": ["RightArm", "RightForeArm", "RightHand"],
	},
	# The shoulder camera: the right hand up at the camera's side grip, elbow out; the left reaching
	# under the lens to the zoom ring; the head turned a little to put the right eye to the
	# viewfinder.
	"shoot": {
		"aim": {
			"RightArm": Vector3(-0.42, -0.30, 0.86), "RightForeArm": Vector3(0.10, 0.93, 0.36),
			"LeftArm": Vector3(-0.36, -0.36, 0.86), "LeftForeArm": Vector3(-0.62, 0.32, 0.72),
			"Head": Vector3(-0.14, 0.97, 0.18),
		},
		"arms": ["RightArm", "RightForeArm", "RightHand", "LeftArm", "LeftForeArm", "LeftHand", "Head"],
	},
	# Down on one knee (EmergencyCrew's kneel, upright: they keep looking).
	"kneel": {
		"hips_pitch": 4.0, "hips_y": 52.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.98, 0.18), "Spine01": Vector3(0.0, 0.97, 0.22),
			"Spine": Vector3(0.0, 0.95, 0.30), "neck": Vector3(0.0, 0.92, 0.38),
			"Head": Vector3(0.0, 0.96, 0.27),
			"LeftUpLeg": Vector3(0.10, -0.97, 0.20), "LeftLeg": Vector3(0.02, -0.12, -0.99),
			"LeftFoot": Vector3(0.0, -0.55, -0.83),
			"RightUpLeg": Vector3(-0.14, -0.08, 0.99), "RightLeg": Vector3(-0.03, -0.99, 0.10),
			"LeftArm": Vector3(0.18, -0.80, 0.55), "LeftForeArm": Vector3(-0.25, -0.30, 0.92),
		},
		"keep": ["RightFoot"],
	},
}
const AIM_CHILD := RoughSleeper.AIM_CHILD

var service: Node
var van: NewsVan
var role: Role = Role.REPORTER
var task: Task = Task.GO
var unseen_time: float = 0.0
## Where to stand for the live shot and what to face (scene positions; NewsCrews sets them).
var spot: Vector3 = Vector3.INF
var face_at: Vector3 = Vector3.INF
## True while the reporter is on air (the camera operator is in place too).
var live: bool = false

var _dest := Vector3.INF
var _face := Vector3.INF
var _think_t: float = 0.0
var _stuck_t: float = 0.0
var _duck_left: float = 0.0
var _duck_at := Vector3.INF
var _alarm_seen: int = 0
var _skel: Skeleton3D
var _order := PackedInt32Array()
var _base_rot: Array[Quaternion] = []
var _base_pos: Array[Vector3] = []
var _hips: int = -1
var _poses: Dictionary = {}
var _pose: String = ""
var _body_pose: String = ""
var _prop: Node3D
var _prop_on_shoulder: bool = false
var _talk_ok: bool = false
var _station: int = 0


func setup_crew(s: Node, v: NewsVan, r: Role, seed_value: int) -> void:
	service = s
	van = v
	role = r
	_station = v.station_i if v else 0
	setup(Rect2(-1.0, -1.0, 2.0, 2.0), 1.0, pick_seed(r, seed_value))


## A seed near `seed_value` whose model roll (Pedestrian._add_model's first style roll) lands on
## a rig the role allows.
static func pick_seed(r: Role, seed_value: int) -> int:
	var allowed: Array = REPORTER_MODELS if r == Role.REPORTER else CAMERA_MODELS
	var available: Array[String] = []
	for p in MODELS:
		if ResourceLoader.exists(p):
			available.append(p)
	if available.is_empty():
		return seed_value
	var rng := RandomNumberGenerator.new()
	for k in 64:
		rng.seed = hash([seed_value + k, "style"])
		var path: String = available[rng.randi() % available.size()]
		if allowed.has(path.get_file().get_basename()):
			return seed_value + k
	return seed_value


func _ready() -> void:
	super._ready()
	remove_from_group("pedestrian")
	add_to_group("news_crew")
	collision_mask = 1 | 4
	_think_t = randf() * 0.2
	_alarm_seen = Pedestrian._last_alarm_ms
	_prepare_poses()
	_add_prop()


func _add_model() -> bool:
	if not super._add_model():
		return false
	# The life library for the reporter's talking (CrowdLife: added after fix_arm_pose).
	if _anim and role == Role.REPORTER and life_enabled:
		_talk_ok = CrowdLife.attach(_anim, _model_path) and _anim.has_animation(CrowdLife.TALK)
	if _head_skel:
		var node: Node3D = _head_skel
		var unit := 1.0
		while node != null and node != _visual:
			unit *= node.transform.basis.get_scale().y
			node = node.get_parent() as Node3D
		_skel_unit = 1.0 / maxf(unit, 1e-5)
	return true


func _scare(_at: Vector3) -> void:
	pass


## Always simulated with a collision body (two a van at most).
func _update_lod() -> void:
	super._update_lod()
	_lod_stride = 1
	_kinematic = false
	if not _down:
		collision_mask = 1 | 4
		if _hit_shape:
			_hit_shape.disabled = false


func _head_look_ok() -> bool:
	return false


# --- Props ----------------------------------------------------------------------------------------

## The reporter's mic in the right hand; the camera, carried by its handle until it goes up on the
## shoulder.
func _add_prop() -> void:
	if _head_skel == null:
		return
	var att := BoneAttachment3D.new()
	_head_skel.add_child(att)
	att.bone_name = "RightHand"
	var mi := MeshInstance3D.new()
	mi.name = "NewsProp"
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = 140.0
	if role == Role.REPORTER:
		mi.mesh = NewsKit.mic_mesh(_station)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(CrowdLife.grip_basis("RightHand") * Basis.from_scale(Vector3.ONE * _skel_unit), Vector3.ZERO)
	else:
		mi.mesh = NewsKit.camera_mesh()
		_carry_camera(mi)
	att.add_child(mi)
	_prop = mi


## The camera hanging from the right fist by its top handle, lens forward.
func _carry_camera(mi: MeshInstance3D) -> void:
	# Grip frame: x the thumb (forward on a hanging arm), y the fingers (down), z out of the palm.
	# The handle runs along the thumb, so the lens (-Z) points along +x, the camera's top toward
	# the wrist (-y), and the handle's middle sits in the palm.
	var g := CrowdLife.grip_basis("RightHand")
	var cam := Basis(Vector3(0.0, 0.0, -1.0), Vector3(0.0, -1.0, 0.0), Vector3(-1.0, 0.0, 0.0))
	var origin := Vector3(0.0, 0.05, 0.03) - cam * Vector3(0.0, 0.265, -0.06)
	mi.transform = Transform3D(g * cam * Basis.from_scale(Vector3.ONE * _skel_unit), g * origin * _skel_unit)
	_prop_on_shoulder = false


## On the shoulder: the camera rides the upper chest, its pad on the right shoulder and its
## viewfinder at the right eye, worked out from the posed skeleton (skeleton space, then the
## chest bone's frame).
func _shoulder_camera() -> void:
	if _prop == null or _skel == null or _prop_on_shoulder:
		return
	var chest := _skel.find_bone("Spine02")
	var head := _skel.find_bone("Head")
	if chest < 0 or head < 0:
		return
	var p_head := _skel.get_bone_global_pose(head).origin
	# Skeleton space is the rig's: +Y up, +Z forward, +X the rig's left, in the rig's units.
	var m := _skel_unit
	# The eyecup (camera frame (-0.14, 0.2, 0.04)) just in front of the right eye.
	var pad := p_head + Vector3(-0.17, -0.12, 0.15) * m
	var cam_basis := Basis(Vector3.UP, PI) * Basis.from_scale(Vector3.ONE * m)
	var want := Transform3D(cam_basis, pad)
	var chest_g := _skel.get_bone_global_pose(chest)
	var att := _prop.get_parent() as BoneAttachment3D
	att.bone_name = "Spine02"
	_prop.transform = chest_g.affine_inverse() * want
	_prop_on_shoulder = true


func _hand_camera() -> void:
	if _prop == null or not _prop_on_shoulder:
		return
	var att := _prop.get_parent() as BoneAttachment3D
	att.bone_name = "RightHand"
	_carry_camera(_prop as MeshInstance3D)


# --- Poses ----------------------------------------------------------------------------------------

func _prepare_poses() -> void:
	_skel = _visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skel == null or _anim == null or not _has_idle:
		return
	_anim.play(IDLE_CLIP, 0.0)
	_anim.seek(0.6, true)
	var n := _skel.get_bone_count()
	_base_rot.resize(n)
	_base_pos.resize(n)
	for b in n:
		_base_rot[b] = _skel.get_bone_pose_rotation(b)
		_base_pos[b] = _skel.get_bone_pose_position(b)
	_order = RoughSleeper._bone_order(_skel)
	_hips = _skel.find_bone("Hips")
	for key: String in POSES:
		_poses[key] = _solve(POSES[key])


## RoughSleeper's / EmergencyCrew's solve: each listed bone turned so its segment points along its
## aim in rig space, from the idle frame; [local rotations, hips position, whole body].
func _solve(spec: Dictionary) -> Array:
	var n := _skel.get_bone_count()
	var local: Array[Quaternion] = _base_rot.duplicate()
	var glob: Array[Transform3D] = []
	glob.resize(n)
	var base_glob: Array[Transform3D] = []
	base_glob.resize(n)
	var aims: Dictionary = spec.aim
	var keep: Array = spec.get("keep", [])
	for b in _order:
		var p := _skel.get_bone_parent(b)
		var bl := Transform3D(Basis(_base_rot[b]), _base_pos[b])
		base_glob[b] = base_glob[p] * bl if p >= 0 else bl
		var g := glob[p] * bl if p >= 0 else bl
		var bone_name := _skel.get_bone_name(b)
		if b == _hips:
			g.basis = Basis(Vector3.RIGHT, deg_to_rad(float(spec.get("hips_pitch", 0.0)))) * g.basis
		var aim: Variant = aims.get(bone_name)
		if aim == null and bone_name.begins_with("Right") and not spec.has("arms"):
			var mirror: Variant = aims.get("Left" + bone_name.trim_prefix("Right"))
			if mirror != null:
				aim = Vector3(-(mirror as Vector3).x, (mirror as Vector3).y, (mirror as Vector3).z)
		if aim != null and AIM_CHILD.has(bone_name):
			var c := _skel.find_bone(AIM_CHILD[bone_name])
			if c >= 0:
				var cur := (g.basis * _base_pos[c]).normalized()
				var want := (aim as Vector3).normalized()
				if cur.length() > 0.5 and absf(cur.dot(want)) < 0.9999:
					g.basis = Basis(Quaternion(cur, want)) * g.basis
		elif keep.has(bone_name):
			g.basis = base_glob[b].basis
		glob[b] = g
		local[b] = ((glob[p].basis.inverse() * g.basis) if p >= 0 else g.basis).get_rotation_quaternion()
	var hips := _base_pos[_hips] if _hips >= 0 else Vector3.ZERO
	if spec.has("hips_y"):
		hips.y = float(spec.hips_y)
	return [local, hips, spec.has("hips_y"), spec.get("arms", [])]


## Writes pose `key` over whatever the clip left: the whole body for a full pose (kneel), the
## listed bones alone for the others.
func _hold_pose(key: String) -> void:
	if _skel == null or not _poses.has(key):
		return
	var p: Array = _poses[key]
	var rots: Array = p[0]
	if bool(p[2]):
		for b in mini(rots.size(), _skel.get_bone_count()):
			_skel.set_bone_pose_rotation(b, rots[b])
		if _hips >= 0:
			_skel.set_bone_pose_position(_hips, p[1])
		return
	for bone_name: String in p[3]:
		var b := _skel.find_bone(bone_name)
		if b >= 0 and b < rots.size():
			_skel.set_bone_pose_rotation(b, rots[b])


# --- The brain ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _down or service == null:
		return
	_lod_timer += delta
	if _lod_timer >= 0.5:
		_lod_timer = 0.0
		_update_lod()
	_watch_alarms()
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.3
		_think()
	_duck_left = maxf(_duck_left - delta, 0.0)
	var speed := 0.0
	var move := Vector3.ZERO
	if _dest != Vector3.INF and _duck_left <= 0.0:
		move = _dest - global_position
		move.y = 0.0
		if move.length() > 0.35:
			var pace := crew_hurry_speed if task == Task.RETURN and bool(service.get("hurry")) else crew_walk_speed
			speed = minf(pace, move.length() * 2.2 + 0.4)
			move = move.normalized()
		else:
			move = Vector3.ZERO
	velocity.x = move.x * speed
	velocity.z = move.z * speed
	if not is_on_floor():
		velocity.y -= 30.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	_speed = Vector2(get_real_velocity().x, get_real_velocity().z).length()
	# Up a kerb (a CharacterBody3D does not step).
	if speed > 0.0 and _speed < speed * 0.3:
		_stuck_t += delta
		var up := Vector3.UP * 0.34
		if is_on_wall() and not test_move(global_transform, up) and not test_move(global_transform.translated(up), move * 0.35):
			global_position += up + move * 0.05
	else:
		_stuck_t = maxf(_stuck_t - delta, 0.0)
	var face := Vector3(velocity.x, 0.0, velocity.z)
	var face_point := _face
	if _duck_left > 0.0 and role == Role.CAMERA and _duck_at != Vector3.INF:
		face_point = _duck_at # the shot everybody wants
	if _speed < 0.3 and face_point != Vector3.INF:
		face = face_point - global_position
		face.y = 0.0
	if face.length() > 0.2:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-6.0 * delta))
	if _anim:
		var talking := role == Role.REPORTER and live and _talk_ok and _speed < 0.2 and _duck_left <= 0.0
		var want_clip := CrowdLife.TALK if talking else ""
		if want_clip != "":
			if _clip != want_clip:
				_set_clip(want_clip, 0.4)
			_anim.speed_scale = 1.0
		_anim.advance(delta)
		if want_clip == "":
			_animate_gait()
	var at_work := task == Task.WORK and _speed < 0.3
	if _duck_left > 0.0:
		_hold_pose("kneel")
		if role == Role.CAMERA and _prop_on_shoulder:
			_hold_pose("shoot")
		elif role == Role.REPORTER:
			_hold_pose("mic")
		_body_pose = "kneel"
	else:
		if _body_pose == "kneel" and _hips >= 0 and _hips < _base_pos.size():
			_skel.set_bone_pose_position(_hips, _base_pos[_hips])
		_body_pose = ""
		if role == Role.REPORTER and (at_work or task == Task.GO):
			_hold_pose("mic")
		elif role == Role.CAMERA and at_work:
			_hold_pose("shoot")
	if role == Role.CAMERA:
		if at_work and not _prop_on_shoulder:
			_shoulder_camera()
		elif not at_work and _prop_on_shoulder:
			_hand_camera()


## Gunfire or a blast near: down on a knee (the camera turns to it).
func _watch_alarms() -> void:
	if Pedestrian._last_alarm_ms == _alarm_seen:
		return
	_alarm_seen = Pedestrian._last_alarm_ms
	var at: Vector3 = Pedestrian._last_alarm_at
	if at.distance_to(global_position) < duck_radius:
		_duck_left = duck_seconds
		_duck_at = at


func _think() -> void:
	var van_ok := is_instance_valid(van) and van.is_inside_tree() and van.driver == null and not van.is_queued_for_deletion()
	if not van_ok:
		_dest = Vector3.INF
		live = false
		return
	var story: Dictionary = van.story
	var over := story.is_empty() or bool(story.get("wrap", false))
	if over:
		task = Task.RETURN
	if task == Task.RETURN:
		live = false
		var door := _door()
		_dest = door
		_face = Vector3.INF
		if global_position.distance_to(door) < 1.4 or (_stuck_t > 1.0 and global_position.distance_to(van.global_position) < 4.0):
			service.board(self, van)
		return
	if spot == Vector3.INF:
		return
	_dest = spot
	_face = face_at
	if _flat_to(spot) < 0.6 or (_stuck_t > 1.5 and _flat_to(spot) < 2.5):
		task = Task.WORK
		_dest = Vector3.INF
	if task == Task.WORK:
		live = role == Role.REPORTER and bool(story.get("on_air", false))


func _flat_to(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## Beside the van's side door (the kerb side) or the passenger door.
func _door() -> Vector3:
	var side := van.global_basis.x.slide(Vector3.UP).normalized()
	var fwd := (-van.global_basis.z).slide(Vector3.UP).normalized()
	var half := float(van._dims().width) * 0.5 + 0.7
	# The kerb is on the van's right (+X): it drives on the right and pulls up on the story's side.
	var d := van.global_position + side * half + fwd * (float(van._dims().length) * (0.25 if role == Role.REPORTER else -0.05))
	d.y = global_position.y
	return d


func knock(impulse: Vector3, gibs: int = 0) -> void:
	if _down:
		return
	if service and service.has_method("crew_down"):
		service.crew_down(self)
	super.knock(impulse, gibs)
