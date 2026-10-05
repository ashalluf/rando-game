class_name EmergencyCrew
extends Pedestrian
## A firefighter or a paramedic (Emergency deploys them from a unit pulled up at a call). A
## Pedestrian, so shot, knocked, blown apart and ragdolled like anyone on the street - and doing
## it is a crime like doing it to anyone (Pedestrian.knock -> Police.person_down) - but it walks
## its own brain instead of the pavement ring, the way PoliceOfficer does:
##
##   GO      run to the place its job puts it (Emergency's call says where).
##   WORK    firefighters: the one on the nozzle stands off the burning car and puts water on it
##           (a hose line laid from the pump panel, a stream of water, spray where it lands;
##           Emergency.water_on -> CarDamage.douse -> extinguish), the second backs the line up,
##           the third works the pump panel. Paramedics: one kneels at the body with the bag,
##           the other brings the stretcher from the back of the ambulance, and when the first has
##           seen to the patient they load them and wheel them back.
##   RETURN  back to the unit's door and aboard (Emergency.board); with everyone in, it leaves.
##
## The body is a crowd rig in uniform: turnout gear (tan coat and trousers) with a fire helmet
## built round the rig's own head (FireHelmet, CrowdHatTable's measurements), or the paramedics'
## blue shirt and navy trousers. Kneeling, holding the line and pushing the stretcher are poses
## solved per rig from its own rest pose over the idle clip (RoughSleeper's method).

enum Role { FIRE, MEDIC }
enum Task { GO, WORK, RETURN }
## What a crew member does at the scene (from its place in the crew).
enum Job { NOZZLE, BACKUP, PUMP, PATIENT, STRETCHER }

@export_group("Crew")
@export var crew_run_speed: float = 4.6
@export var crew_walk_speed: float = 1.6
## Pushing the stretcher (m/s), and how far ahead of the hips it rides (m).
@export var stretcher_speed: float = 1.5
@export var stretcher_reach: float = 1.25
## The nozzle stands this far from the burning car (m), and the stream: its speed (m/s) and how
## far up it is aimed (radians).
@export var nozzle_distance: float = 6.5
@export var stream_speed: float = 14.5
@export var stream_lift: float = 0.16
## Seconds the patient is seen to before they are loaded.
@export var treat_seconds: float = 9.0
@export_group("")

## Turnout gear and the paramedics' uniform, as the character shader's garment colours.
const TURNOUT := Color(0.47, 0.40, 0.26)
const TURNOUT_TROUSERS := Color(0.42, 0.36, 0.24)
const MEDIC_TOP := Color(0.17, 0.27, 0.46)
const MEDIC_TROUSERS := Color(0.06, 0.075, 0.13)
## The hose's jacket and the bag's nylon.
const HOSE_COLOR := Color(0.78, 0.70, 0.48)
const BAG_COLOR := Color(0.72, 0.12, 0.07)
## The rigs that wear the uniforms (trousers, short hair under a helmet): PoliceOfficer's.
const CREW_MODELS := PoliceOfficer.OFFICER_MODELS

## The pose tables (RoughSleeper.POSES' format: each bone's segment direction in rig space, +Z
## forward, +X the rig's left; a Right bone with no entry is its Left twin mirrored).
const POSES := {
	# One knee down at the patient's side, leaning in, both hands down to them.
	"kneel": {
		"hips_pitch": 12.0, "hips_y": 52.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.94, 0.34), "Spine01": Vector3(0.0, 0.91, 0.41),
			"Spine": Vector3(0.0, 0.86, 0.51), "neck": Vector3(0.0, 0.70, 0.71),
			"Head": Vector3(0.0, 0.42, 0.91),
			"LeftUpLeg": Vector3(0.10, -0.97, 0.20), "LeftLeg": Vector3(0.02, -0.12, -0.99),
			"LeftFoot": Vector3(0.0, -0.55, -0.83),
			"RightUpLeg": Vector3(-0.14, -0.08, 0.99), "RightLeg": Vector3(-0.03, -0.99, 0.10),
			"LeftArm": Vector3(0.18, -0.74, 0.65), "LeftForeArm": Vector3(-0.15, -0.62, 0.77),
		},
		"keep": ["RightFoot"],
	},
	# Both hands on the line at the chest, elbows in: the nozzle and the backup.
	"hose": {
		"aim": {
			"LeftArm": Vector3(0.10, -0.55, 0.83), "LeftForeArm": Vector3(-0.55, 0.12, 0.83),
			"RightArm": Vector3(-0.10, -0.62, 0.78), "RightForeArm": Vector3(0.40, 0.05, 0.92),
		},
	},
	# Hands on the stretcher's rail.
	"push": {
		"aim": {
			"LeftArm": Vector3(0.10, -0.76, 0.64), "LeftForeArm": Vector3(-0.10, -0.42, 0.90),
		},
	},
}
const AIM_CHILD := RoughSleeper.AIM_CHILD
const ARM_BONES := ["LeftArm", "LeftForeArm", "RightArm", "RightForeArm", "LeftHand", "RightHand"]

var service: Emergency
var car: EmergencyCar
var role: Role = Role.FIRE
var job: Job = Job.NOZZLE
var task: Task = Task.GO
var unseen_time: float = 0.0

var _dest := Vector3.INF
var _face := Vector3.INF
var _think_t: float = 0.0
var _stuck_t: float = 0.0
## True once this crew member stops colliding with the body it treats (_step_over_patient()).
var _patient_ignored := false
var _work_t: float = 0.0
var _done_t: float = -1.0
var _skel: Skeleton3D
var _order := PackedInt32Array()
var _base_rot: Array[Quaternion] = []
var _base_pos: Array[Vector3] = []
var _hips: int = -1
var _poses: Dictionary = {}
var _pose: String = ""
var _water: CPUParticles3D
var _spray: CPUParticles3D
var _hose: MeshInstance3D
var _hose_t: float = 0.0
var _bag: MeshInstance3D
var _stretcher: Node3D
var _patient: MeshInstance3D
static var _uniform_mats: Dictionary = {}
static var _hose_mat: StandardMaterial3D
static var _water_mat: ShaderMaterial
static var _meshes_cache: Dictionary = {}


func setup_crew(s: Emergency, c: EmergencyCar, r: Role, index: int, seed_value: int) -> void:
	service = s
	car = c
	role = r
	if r == Role.FIRE:
		job = [Job.NOZZLE, Job.PUMP, Job.BACKUP][index % 3]
	else:
		job = [Job.PATIENT, Job.STRETCHER][index % 2]
	setup(Rect2(-1.0, -1.0, 2.0, 2.0), 1.0, seed_value)


func _ready() -> void:
	super._ready()
	remove_from_group("pedestrian")
	add_to_group("responder")
	collision_mask = 1 | 4
	_think_t = randf() * 0.2
	_prepare_poses()
	if role == Role.MEDIC and job == Job.PATIENT:
		_add_bag()


## The body: a crowd rig in the uniform, a helmet on a firefighter.
func _add_model() -> bool:
	var available: Array[String] = []
	for p in CREW_MODELS:
		if ResourceLoader.exists(p):
			available.append(p)
	if available.is_empty():
		return false
	var path := available[_style.randi() % available.size()]
	var scene: PackedScene = load(path)
	if scene == null:
		return false
	var inst := scene.instantiate() as Node3D
	inst.rotation.y = PI
	_look = 1
	prepare_rig(inst, _look)
	_visual.add_child(inst)
	_model_path = path
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		_meshes.append(mi)
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh else null
		if src and src.albedo_texture and not is_hair(mi):
			mi.material_override = uniform_material(src.albedo_texture, role)
	plain_hair(inst)
	_visual.scale = Vector3.ONE * _style.randf_range(0.96, 1.05)
	_stride = _visual.scale.z
	_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		fix_arm_pose(_anim, path)
		_has_walk = _anim.has_animation(WALK_CLIP)
		_has_run = _anim.has_animation(RUN_CLIP)
		_has_idle = _anim.has_animation(IDLE_CLIP)
		for clip in _anim.get_animation_list():
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if _has_idle:
			_anim.play(IDLE_CLIP, 0.0)
			_clip = IDLE_CLIP
			_anim.seek(0.6, true)
	if role == Role.FIRE:
		FireHelmet.dress(inst, path, _style.randi() % 8 == 0)
	return true


## The uniform: the model's own face, skin and hair, top and trousers repainted (turnout tan, or
## the paramedics' blue and navy) through the character shader's garment split. Per texture.
static func uniform_material(albedo: Texture2D, r: Role) -> ShaderMaterial:
	var key := "%d_%d" % [albedo.get_instance_id(), int(r)]
	if _uniform_mats.has(key):
		return _uniform_mats[key]
	var base := character_material(albedo, 1)
	if base == null:
		return null
	var mat := base.duplicate() as ShaderMaterial
	var top: Color = TURNOUT if r == Role.FIRE else MEDIC_TOP
	var low: Color = TURNOUT_TROUSERS if r == Role.FIRE else MEDIC_TROUSERS
	mat.set_shader_parameter("cloth_hue", top.h)
	mat.set_shader_parameter("cloth_sat", top.s)
	mat.set_shader_parameter("cloth_value", top.v)
	mat.set_shader_parameter("cloth_strength", 0.96)
	mat.set_shader_parameter("pants_hue", low.h)
	mat.set_shader_parameter("pants_sat", low.s)
	mat.set_shader_parameter("pants_value", low.v)
	mat.set_shader_parameter("pants_strength", 0.96)
	mat.set_shader_parameter("hair_strength", 0.0)
	mat.set_shader_parameter("skin_tint", Color(1, 1, 1))
	# Turnout gear is heavy canvas: rough, stiff (few of the source garment's creases kept).
	mat.set_shader_parameter("cloth_roughness", 0.9 if r == Role.FIRE else 0.78)
	mat.set_shader_parameter("cloth_shade_keep", 0.5 if r == Role.FIRE else 0.65)
	_uniform_mats[key] = mat
	return mat


## Not frightened off by gunfire: they are working.
func _scare(_at: Vector3) -> void:
	pass


## Always simulated with a collision body (a handful at most).
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


# --- Poses -------------------------------------------------------------------------------------

## The idle clip at a fixed moment is the base the poses are worked from (RoughSleeper._solve).
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
		if aim == null and bone_name.begins_with("Right"):
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
	return [local, hips, spec.has("hips_y")]


## Writes pose `key` over whatever the clip left: the whole body for a full pose (kneel), the
## arms alone for the others.
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
	for bone_name: String in ARM_BONES:
		var b := _skel.find_bone(bone_name)
		if b >= 0 and b < rots.size():
			_skel.set_bone_pose_rotation(b, rots[b])


# --- The brain ---------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _down or service == null:
		return
	_lod_timer += delta
	if _lod_timer >= 0.5:
		_lod_timer = 0.0
		_update_lod()
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.3
		_think()
	var speed := 0.0
	var move := Vector3.ZERO
	if _dest != Vector3.INF and _pose != "kneel":
		move = _dest - global_position
		move.y = 0.0
		if move.length() > 0.45:
			var pace := crew_run_speed if task == Task.GO and job != Job.STRETCHER else crew_walk_speed
			if _stretcher != null:
				pace = stretcher_speed
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
	# Up a kerb (a CharacterBody3D does not step): blocked while trying to move, and there is room
	# a step higher and on.
	if speed > 0.0 and _speed < speed * 0.3:
		_stuck_t += delta
		var up := Vector3.UP * 0.34
		if is_on_wall() and not test_move(global_transform, up) and not test_move(global_transform.translated(up), move * 0.35):
			global_position += up + move * 0.05
	else:
		_stuck_t = maxf(_stuck_t - delta, 0.0)
	var face := Vector3(velocity.x, 0.0, velocity.z)
	if _speed < 0.3 and _face != Vector3.INF:
		face = _face - global_position
		face.y = 0.0
	if face.length() > 0.2:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-8.0 * delta))
	if _anim and _pose != "kneel":
		_anim.advance(delta)
		_animate_gait()
	if _pose != "":
		_hold_pose(_pose)
	_tick_gear(delta)


## What to do and where to stand, a few times a second.
func _think() -> void:
	var inc: Dictionary = car.incident if is_instance_valid(car) else {}
	var car_ok := is_instance_valid(car) and car.is_inside_tree() and car.driver == null and not car.is_queued_for_deletion()
	if not car_ok:
		# Nothing to go back to: stand down where they are.
		_set_pose("")
		_dest = Vector3.INF
		_stop_water()
		return
	var finished := inc.is_empty() or bool(inc.get("done", false)) or _job_over(inc)
	if finished:
		if _done_t < 0.0:
			_done_t = service.linger_seconds
		_done_t -= 0.3
		if _done_t > 0.0:
			_stop_water()
			_set_pose("")
			return
		task = Task.RETURN
	if task == Task.RETURN:
		_stop_water()
		_set_pose("push" if _stretcher != null else "")
		var door := _door()
		_dest = door
		_face = Vector3.INF
		# At the door, or pressed against the unit round the wrong side of it: aboard.
		if global_position.distance_to(door) < 1.6 or (_stuck_t > 1.0 and global_position.distance_to(car.global_position) < float(car._dims().length) * 0.6):
			if _stretcher != null:
				_stretcher.queue_free()
				_stretcher = null
			service.board(self, car)
		return
	var scene := service.scene_point(inc)
	match job:
		Job.NOZZLE, Job.BACKUP:
			var spot := _line_spot(scene, 0.0 if job == Job.NOZZLE else 1.5)
			_dest = spot
			_face = scene
			if global_position.distance_to(spot) < 0.8:
				task = Task.WORK
				_set_pose("hose")
				if job == Job.NOZZLE and inc.kind == Emergency.KIND_FIRE and service.still_burning(inc):
					_start_water(scene)
					service.water_on(inc, 0.3)
				else:
					_stop_water()
			else:
				_set_pose("")
				_stop_water()
		Job.PUMP:
			var panel := _panel_point(scene)
			_dest = panel + car.global_basis.x.slide(Vector3.UP).normalized() * signf((panel - car.global_position).dot(car.global_basis.x)) * 0.7
			_face = panel
			task = Task.WORK if global_position.distance_to(_dest) < 0.8 else Task.GO
		Job.PATIENT:
			_step_over_patient(inc)
			var at := _patient_side(scene)
			_dest = at
			_face = scene
			if global_position.distance_to(at) < 0.8 or (_stuck_t > 0.6 and _flat_to(scene) < 1.9):
				task = Task.WORK
				_set_pose("kneel")
				_work_t += 0.3
				if _bag:
					_bag.position = Vector3(0.62, 0.14, 0.2)
			else:
				_set_pose("")
		Job.STRETCHER:
			if _stretcher == null and not inc.loaded:
				# Out of the back of the ambulance first.
				var rear := _rear_point()
				_dest = rear
				_face = Vector3.INF
				if global_position.distance_to(rear) < 1.2:
					_take_stretcher()
				return
			if not inc.loaded:
				var to := scene + (global_position - scene).slide(Vector3.UP).normalized() * 2.3
				_dest = to
				_face = scene
				_set_pose("push")
				if (global_position.distance_to(to) < 1.0 or (_stuck_t > 0.6 and _flat_to(scene) < 3.5)) and _partner_treated(inc):
					_load_patient(inc)
			else:
				task = Task.RETURN


func _flat_to(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## True once there is nothing left for this crew member's job.
func _job_over(inc: Dictionary) -> bool:
	match String(inc.kind):
		Emergency.KIND_FIRE:
			return not service.still_burning(inc)
		Emergency.KIND_DOWN:
			return bool(inc.loaded) or not is_instance_valid(inc.doll) or (inc.doll as Node).is_queued_for_deletion()
		_:
			return false


## The paramedic at the patient has seen to them long enough.
func _partner_treated(inc: Dictionary) -> bool:
	for c in service.crews:
		if is_instance_valid(c) and c.car == car and c.job == Job.PATIENT:
			return c._work_t >= c.treat_seconds
	return true # nobody kneeling (they were knocked down): load anyway


func _set_pose(key: String) -> void:
	if key == _pose:
		return
	_pose = key
	if key == "" and _anim and _skel and _hips >= 0 and _hips < _base_pos.size():
		_skel.set_bone_pose_position(_hips, _base_pos[_hips])
	if key != "kneel" and _bag and job == Job.PATIENT:
		_bag.position = Vector3(0.24, 0.42, 0.0)


func _door() -> Vector3:
	var side := car.global_basis.x.slide(Vector3.UP).normalized()
	var fwd := (-car.global_basis.z).slide(Vector3.UP).normalized()
	var half := float(car._dims().width) * 0.5 + 0.7
	var s := 1.0 if int(job) % 2 == 0 else -1.0
	var d := car.global_position + side * half * s + fwd * float(car._dims().length) * 0.3
	d.y = global_position.y
	return d


## A point on the line from the engine's pump panel to the fire, `back` metres behind the nozzle.
func _line_spot(scene: Vector3, back: float) -> Vector3:
	var panel := _panel_point(scene)
	var to := scene - panel
	to.y = 0.0
	var d := to.length()
	var dir := to / maxf(d, 0.01)
	var stand := minf(nozzle_distance, maxf(d - 2.0, 2.0))
	var p := scene - dir * (stand + back)
	if back > 0.0:
		p += dir.cross(Vector3.UP) * 0.45
	p.y = global_position.y
	return p


## Where the hose leaves the engine: the pump panel on the side facing the fire, behind the cab.
func _panel_point(scene: Vector3) -> Vector3:
	var side := car.global_basis.x.slide(Vector3.UP).normalized()
	var fwd := (-car.global_basis.z).slide(Vector3.UP).normalized()
	var s := signf((scene - car.global_position).dot(side))
	if s == 0.0:
		s = 1.0
	var base := car.global_position - Vector3.UP * car.road_lift()
	return base + side * s * (float(car._dims().width) * 0.5 + 0.05) + fwd * float(car._dims().length) * 0.05 + Vector3.UP * 0.95


func _rear_point() -> Vector3:
	var fwd := (-car.global_basis.z).slide(Vector3.UP).normalized()
	var p := car.global_position - fwd * (float(car._dims().length) * 0.5 + 1.6)
	p.y = global_position.y
	return p


## Kneeling at the patient's side, toward the unit.
## A paramedic kneels against the body, so its box (props layer, which the crew collide with)
## must not hold him off it.
func _step_over_patient(inc: Dictionary) -> void:
	var doll: Variant = inc.get("doll")
	if _patient_ignored or not (doll is Ragdoll) or not is_instance_valid(doll):
		return
	for b in (doll as Ragdoll).bodies:
		if is_instance_valid(b):
			add_collision_exception_with(b)
	_patient_ignored = true


func _patient_side(scene: Vector3) -> Vector3:
	var away := global_position - scene
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.RIGHT
	away = away.normalized()
	# Beside the body, not at its head or feet: off its long axis (the ragdoll's box runs 1.7 m
	# along its local up) on the side the medic comes from.
	var inc: Dictionary = car.incident if is_instance_valid(car) else {}
	var doll: Variant = inc.get("doll")
	if doll is Ragdoll and is_instance_valid(doll) and not (doll as Ragdoll).bodies.is_empty():
		var long := ((doll as Ragdoll).bodies[0] as Node3D).global_basis.y
		long.y = 0.0
		if long.length() > 0.3:
			var side := long.normalized().cross(Vector3.UP)
			away = side * signf(side.dot(away) + 0.001)
	var p := scene + away * 0.75
	p.y = global_position.y
	return p


# --- Gear: hose, water, bag, stretcher --------------------------------------------------------------

func _tick_gear(delta: float) -> void:
	if job == Job.NOZZLE and is_instance_valid(car) and task != Task.RETURN:
		_hose_t -= delta
		if _hose_t <= 0.0:
			_hose_t = 0.12
			_lay_hose()
	elif _hose:
		_hose.queue_free()
		_hose = null
	if _stretcher != null:
		var yaw := _visual.rotation.y
		_stretcher.position = Vector3(-sin(yaw), 0.0, -cos(yaw)) * stretcher_reach
		_stretcher.rotation = Vector3(0.0, yaw, 0.0)


## The line from the pump panel along the ground to the nozzle in the hands: a tube through a
## few points (the panel, down to the street, a lazy curve along it, up to the chest).
func _lay_hose() -> void:
	if _hose == null:
		_hose = MeshInstance3D.new()
		_hose.name = "HoseLine"
		_hose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hose.material_override = hose_material()
		_hose.top_level = true
		add_child(_hose)
	var scene := service.scene_point(car.incident) if not car.incident.is_empty() else global_position
	var a := _panel_point(scene)
	var hands := _nozzle_point()
	var ground_y := global_position.y + 0.06
	var out := (a - car.global_position).slide(Vector3.UP).normalized()
	var pts: Array[Vector3] = [a, a + out * 0.25 + Vector3.DOWN * 0.3, Vector3(a.x + out.x * 0.7, ground_y, a.z + out.z * 0.7)]
	var foot := Vector3(hands.x, ground_y, hands.z) - (hands - a).slide(Vector3.UP).normalized() * 0.9
	var mid := pts[2].lerp(foot, 0.5)
	var side := (foot - pts[2]).cross(Vector3.UP).normalized()
	pts.append(Vector3(mid.x, ground_y, mid.z) + side * 0.6)
	pts.append(foot)
	pts.append(hands + Vector3.DOWN * 0.45 - (hands - a).slide(Vector3.UP).normalized() * 0.25)
	pts.append(hands)
	_hose.mesh = tube_mesh(pts, 0.035, 7)
	_hose.global_transform = Transform3D.IDENTITY


## Where the nozzle is: in both hands at the chest, a little ahead.
func _nozzle_point() -> Vector3:
	return _visual.global_transform * Vector3(0.0, 1.12, -0.5)


func _start_water(target: Vector3) -> void:
	if _water == null:
		_water = CPUParticles3D.new()
		_water.name = "HoseWater"
		_water.amount = 160 if not OS.has_feature("web") else 60
		_water.lifetime = 0.85
		_water.local_coords = false
		_water.direction = Vector3(0.0, 0.0, -1.0)
		_water.spread = 2.2
		_water.initial_velocity_min = stream_speed * 0.92
		_water.initial_velocity_max = stream_speed * 1.05
		_water.gravity = Vector3(0.0, -9.8, 0.0)
		_water.particle_flag_align_y = true
		_water.scale_amount_min = 0.7
		_water.scale_amount_max = 1.2
		_water.color_ramp = WeaponFX._ramp([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)])
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		quad.material = water_material()
		_water.mesh = quad
		_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_water.custom_aabb = AABB(Vector3(-15, -6, -15), Vector3(30, 14, 30))
		_visual.add_child(_water)
		_water.position = Vector3(0.0, 1.12, -0.6)
		_spray = CPUParticles3D.new()
		_spray.name = "HoseSpray"
		_spray.amount = 26 if not OS.has_feature("web") else 12
		_spray.lifetime = 1.6
		_spray.local_coords = false
		_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_spray.emission_sphere_radius = 0.7
		_spray.direction = Vector3.UP
		_spray.spread = 60.0
		_spray.initial_velocity_min = 0.6
		_spray.initial_velocity_max = 2.0
		_spray.gravity = Vector3(0.0, 0.4, 0.0)
		_spray.scale_amount_min = 0.6
		_spray.scale_amount_max = 1.3
		var curve := Curve.new()
		curve.max_value = 4.0
		curve.add_point(Vector2(0.0, 0.5))
		curve.add_point(Vector2(1.0, 2.6))
		_spray.scale_amount_curve = curve
		_spray.color_ramp = WeaponFX._ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)])
		_spray.color = Color(0.85, 0.87, 0.9)
		var sq := QuadMesh.new()
		sq.size = Vector2.ONE
		sq.material = WeaponFX.smoke_material()
		_spray.mesh = sq
		_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spray.custom_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 12, 16))
		_spray.top_level = true
		add_child(_spray)
	# Aimed a little high so the arc comes down on the car.
	var flat := (target - global_position).slide(Vector3.UP).length()
	_water.rotation = Vector3(stream_lift + clampf((flat - 6.0) * 0.02, -0.08, 0.12), 0.0, 0.0)
	_water.emitting = true
	_spray.global_position = target + Vector3.UP * 0.9
	_spray.emitting = true


func _stop_water() -> void:
	if _water:
		_water.emitting = false
	if _spray:
		_spray.emitting = false


func _add_bag() -> void:
	_bag = MeshInstance3D.new()
	_bag.name = "MedicBag"
	_bag.mesh = bag_mesh()
	_bag.position = Vector3(0.24, 0.42, 0.0)
	_visual.add_child(_bag)


func _take_stretcher() -> void:
	_stretcher = Node3D.new()
	_stretcher.name = "Stretcher"
	var mi := MeshInstance3D.new()
	mi.mesh = stretcher_mesh()
	_stretcher.add_child(mi)
	_patient = MeshInstance3D.new()
	_patient.mesh = patient_mesh()
	_patient.visible = false
	_stretcher.add_child(_patient)
	add_child(_stretcher)


## The body goes onto the stretcher under a blanket and the ragdoll leaves the street.
func _load_patient(inc: Dictionary) -> void:
	inc.loaded = true
	if is_instance_valid(inc.doll):
		(inc.doll as Node).queue_free()
	if _patient:
		_patient.visible = true
	task = Task.RETURN


# --- Shot, knocked ------------------------------------------------------------------------------

## Down like anyone (a crime like anyone, Police.person_down in Pedestrian.knock); the body stays
## in uniform and is not another call.
func knock(impulse: Vector3, gibs: int = 0) -> void:
	if _down:
		return
	_stop_water()
	if _hose:
		_hose.queue_free()
		_hose = null
	if service:
		service.crew_down(self)
	var parent := get_parent()
	var before := parent.get_child_count() if parent else 0
	super.knock(impulse, gibs)
	if parent == null:
		return
	for i in range(before, parent.get_child_count()):
		var doll := parent.get_child(i) as Ragdoll
		if doll:
			doll.set_meta("responder", true)
			if doll._rig:
				for node in doll._rig.find_children("*", "MeshInstance3D", true, false):
					var mi := node as MeshInstance3D
					var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh else null
					if src and src.albedo_texture and mi.skin and not is_hair(mi):
						mi.material_override = uniform_material(src.albedo_texture, role)
				plain_hair(doll._rig)
				if role == Role.FIRE:
					FireHelmet.dress(doll._rig, _model_path, false)


# --- Meshes ------------------------------------------------------------------------------------------

static func hose_material() -> StandardMaterial3D:
	if _hose_mat == null:
		_hose_mat = StandardMaterial3D.new()
		_hose_mat.albedo_color = HOSE_COLOR
		_hose_mat.roughness = 0.85
	return _hose_mat


static func water_material() -> ShaderMaterial:
	if _water_mat == null:
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = load("res://shaders/hose_water.gdshader")
	return _water_mat


## A tube of `radius` through `pts` (scene space), `sides` round, with smooth normals.
static func tube_mesh(pts: Array[Vector3], radius: float, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Rounded corners: each inner point split in two along its neighbours.
	var path: Array[Vector3] = [pts[0]]
	for i in range(1, pts.size() - 1):
		path.append(pts[i].lerp(pts[i - 1], 0.25))
		path.append(pts[i].lerp(pts[i + 1], 0.25))
	path.append(pts[pts.size() - 1])
	var rings: Array = []
	var prev_n := Vector3.UP
	for i in path.size():
		var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var n := prev_n - t * prev_n.dot(t)
		if n.length() < 0.01:
			n = t.cross(Vector3.RIGHT)
		n = n.normalized()
		prev_n = n
		var b := t.cross(n).normalized()
		var ring: Array[Vector3] = []
		for k in sides:
			var a := TAU * float(k) / float(sides)
			ring.append(n * cos(a) + b * sin(a))
		rings.append(ring)
	for i in path.size() - 1:
		var r0: Array[Vector3] = rings[i]
		var r1: Array[Vector3] = rings[i + 1]
		for k in sides:
			var k2 := (k + 1) % sides
			for q: Array in [[r0, k, i], [r1, k, i + 1], [r1, k2, i + 1], [r0, k, i], [r1, k2, i + 1], [r0, k2, i]]:
				var dir: Vector3 = (q[0] as Array[Vector3])[q[1]]
				st.set_normal(dir)
				st.add_vertex(path[q[2]] + dir * radius)
	return st.commit()


## The medic's bag: a red duffel with a dark base and handles, built once.
static func bag_mesh() -> Mesh:
	if _meshes_cache.has("bag"):
		return _meshes_cache.bag
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0.0, 0.0, 0.0), Vector3(0.24, 0.24, 0.48), BAG_COLOR)
	_box(st, Vector3(0.0, -0.11, 0.0), Vector3(0.25, 0.03, 0.49), Color(0.05, 0.05, 0.05))
	_box(st, Vector3(0.0, 0.0, 0.0), Vector3(0.245, 0.03, 0.485), Color(0.85, 0.85, 0.8))
	_box(st, Vector3(0.0, 0.14, 0.0), Vector3(0.03, 0.04, 0.2), Color(0.05, 0.05, 0.05))
	var mesh := st.commit()
	mesh.surface_set_material(0, _vc_material(0.7))
	_meshes_cache.bag = mesh
	return mesh


## The wheeled stretcher (cot): an aluminium frame on legs and castors, a mattress, a folded
## blanket at the foot. Its front end is at -Z (the pusher's way).
static func stretcher_mesh() -> Mesh:
	if _meshes_cache.has("cot"):
		return _meshes_cache.cot
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var al := Color(0.70, 0.71, 0.72)
	var dark := Color(0.05, 0.05, 0.055)
	for sx: float in [-0.27, 0.27]:
		_box(st, Vector3(sx, 0.62, 0.0), Vector3(0.035, 0.035, 1.95), al)
		for sz: float in [-0.75, 0.75]:
			_box(st, Vector3(sx, 0.34, sz), Vector3(0.03, 0.56, 0.03), al)
			_box(st, Vector3(sx, 0.06, sz), Vector3(0.05, 0.11, 0.11), dark)
	for sz: float in [-0.75, 0.0, 0.75]:
		_box(st, Vector3(0.0, 0.60, sz), Vector3(0.56, 0.025, 0.03), al)
	# Push bar at the head (+Z, toward the pusher) and the side rails.
	_box(st, Vector3(0.0, 0.92, 0.98), Vector3(0.58, 0.03, 0.03), al)
	for sx: float in [-0.29, 0.29]:
		_box(st, Vector3(sx, 0.77, 0.98), Vector3(0.03, 0.3, 0.03), al)
		_box(st, Vector3(sx, 0.75, 0.1), Vector3(0.02, 0.02, 1.2), al)
	# Mattress, a raised back rest, the blanket folded at the foot.
	_box(st, Vector3(0.0, 0.69, -0.15), Vector3(0.54, 0.09, 1.55), Color(0.10, 0.12, 0.16))
	_box(st, Vector3(0.0, 0.80, 0.72), Vector3(0.54, 0.09, 0.5), Color(0.10, 0.12, 0.16))
	_box(st, Vector3(0.0, 0.76, -0.75), Vector3(0.5, 0.06, 0.32), Color(0.62, 0.58, 0.52))
	var mesh := st.commit()
	mesh.surface_set_material(0, _vc_material(0.45))
	_meshes_cache.cot = mesh
	return mesh


## The patient on the cot under a blanket, strapped (a shape, not a person: the blanket covers it).
static func patient_mesh() -> Mesh:
	if _meshes_cache.has("patient"):
		return _meshes_cache.patient
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blanket := Color(0.64, 0.60, 0.54)
	_box(st, Vector3(0.0, 0.82, -0.2), Vector3(0.46, 0.18, 1.35), blanket)
	_box(st, Vector3(0.0, 0.92, 0.62), Vector3(0.40, 0.16, 0.36), blanket)
	_box(st, Vector3(0.0, 0.99, 0.78), Vector3(0.18, 0.16, 0.2), Color(0.55, 0.42, 0.33))
	for sz: float in [-0.5, 0.15]:
		_box(st, Vector3(0.0, 0.915, sz), Vector3(0.5, 0.02, 0.07), Color(0.08, 0.08, 0.1))
	var mesh := st.commit()
	mesh.surface_set_material(0, _vc_material(0.9))
	_meshes_cache.patient = mesh
	return mesh


static func _vc_material(rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	return m


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.LEFT, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
		[Vector3.UP, Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)],
		[Vector3.DOWN, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.BACK, Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3.FORWARD, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var q: Array = [f[1], f[2], f[3], f[4]]
		# Wound to face `n` whatever order the corners came in (LandmarkGeo's rule).
		var flip := ((q[1] - q[0]) as Vector3).cross((q[2] - q[0]) as Vector3).dot(n) > 0.0
		var order := [0, 2, 1, 0, 3, 2] if flip else [0, 1, 2, 0, 2, 3]
		for k: int in order:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(c + (q[k] as Vector3))
