class_name Valet
extends Pedestrian
## A parking valet (Valets / ValetStand): stands at the stand's podium in the operator's uniform
## (the crowd's garment regions recoloured: a jacket or vest over dark trousers), looking at
## whatever pulls in, and on the stand's say runs a JOB - a list of points it is placed along at a
## run (StreetErrands._step_to(), which steps down off the kerb onto the carriageway and up
## again) - to a car's driver door, gets in (hidden, out of the collision) and is driven off, or
## gets out of a car brought back and runs back to the podium. A crowd rig like anyone: shot,
## knocked, bled and ragdolled the same way, in the crowd cap and the "pedestrian" group (they
## hear gunfire and witness crimes). Gunfire calls a job off and sends them running; once it is
## over they walk back to the podium.

## The operators' uniforms: [jacket / vest, trousers] in the crowd's garment regions (sRGB).
const UNIFORMS := [
	[Color(0.36, 0.04, 0.05), Color(0.03, 0.03, 0.035)],
	[Color(0.035, 0.035, 0.04), Color(0.03, 0.03, 0.035)],
	[Color(0.05, 0.08, 0.2), Color(0.04, 0.04, 0.05)],
	[Color(0.24, 0.04, 0.08), Color(0.07, 0.07, 0.08)],
	[Color(0.86, 0.86, 0.84), Color(0.03, 0.03, 0.035)],
]
static var _uniform_mats: Dictionary = {}

## Run pace to a car (m/s) and the walk back with a guest's keys.
@export var run_pace: float = 3.6
@export var walk_pace: float = 1.5

var home := Vector2.ZERO
var home_yaw: float = 0.0
var uniform: int = 0
## True while sitting in a car (not drawn, out of the collision).
var hidden: bool = false
var _job: Array = []
var _job_k: int = 0
var _job_pace: float = 3.6
var _job_done: Callable
var _job_face: float = INF
var _beat: float = 0.0


func setup_valet(block_rect: Rect2, seed_value: int, at: Vector2, yaw: float, uniform_index: int) -> void:
	setup(block_rect, 4.0, seed_value)
	# Nobody parks cars in a cap or a backpack (the crowd's own roll is still made).
	accessory_chance = 0.0
	home = at
	home_yaw = yaw
	uniform = uniform_index


## Valets get the crowd's life clips (Pedestrian only gives them to the plain crowd).
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
			var mat := uniform_look(src.albedo_texture, uniform)
			if mat:
				mi.material_override = mat
	return true


## The rig's look in uniform `index` (one material per rig texture and uniform).
static func uniform_look(albedo: Texture2D, index: int) -> ShaderMaterial:
	var key := "%s|%d" % [albedo.resource_path if albedo.resource_path != "" else str(albedo.get_instance_id()), index]
	if _uniform_mats.has(key):
		return _uniform_mats[key]
	var base := character_material(albedo, 1)
	if base == null:
		return null
	var top: Color = UNIFORMS[index % UNIFORMS.size()][0]
	var pants: Color = UNIFORMS[index % UNIFORMS.size()][1]
	var mat := base.duplicate() as ShaderMaterial
	mat.set_shader_parameter("cloth_hue", top.h)
	mat.set_shader_parameter("cloth_sat", top.s)
	mat.set_shader_parameter("cloth_value", top.v)
	mat.set_shader_parameter("cloth_strength", 0.96)
	mat.set_shader_parameter("pants_hue", pants.h)
	mat.set_shader_parameter("pants_sat", pants.s)
	mat.set_shader_parameter("pants_value", pants.v)
	mat.set_shader_parameter("pants_strength", 0.95)
	mat.set_shader_parameter("cloth_roughness", 0.7)
	mat.set_shader_parameter("cloth_shade_keep", 0.6)
	_uniform_mats[key] = mat
	return mat


func _ready() -> void:
	super()
	_work(true)


## At the podium: standing there (until a job or a fright).
func _work(at_once: bool) -> void:
	_act = CrowdLife.Act.STAND
	_act_left = INF
	_act_face = home_yaw
	_act_beat = 3.0
	_life_base = CrowdLife.IDLE if _life_ok else ""
	if at_once:
		_place_at(home, home_yaw)
		_stage = Stage.DOING
		_life_clip = _life_base
	else:
		_stage = Stage.GOING
		_go_to(home)


## True while at the podium, free for a job.
func free_for_job() -> bool:
	return not hidden and not _down and _job.is_empty() and _panic_left <= 0.0 and errand.is_empty() \
		and _act == CrowdLife.Act.STAND and _stage == Stage.DOING and Vector2(position.x, position.z).distance_to(home) < 1.5


## True while running a job.
func busy() -> bool:
	return not _job.is_empty()


## Runs along `pts` (true world XZ) at `pace`, then calls `done` (and faces `face_yaw` first, if
## given). Called off by a fright (done is not called).
func run_job(pts: Array, pace: float, done: Callable, face_yaw: float = INF) -> void:
	_end_act(true)
	_act = CrowdLife.Act.NONE
	_life_clip = ""
	_life_look = Vector3.INF
	_pause_left = 0.0
	_job = pts
	_job_k = 0
	_job_pace = pace
	_job_done = done
	_job_face = face_yaw


func cancel_job() -> void:
	_job = []
	_job_done = Callable()


## Into a car: not drawn, out of the collision and the hit tests.
func hide_in_car() -> void:
	hidden = true
	_job = []
	visible = false
	collision_layer = 0
	var area := _hit_shape.get_parent() as Area3D if _hit_shape else null
	if area:
		area.monitoring = false
	_speed = 0.0
	velocity = Vector3.ZERO
	_life_clip = ""


## Out of a car at `at` (true world XZ), facing `yaw`.
func show_at(at: Vector2, yaw: float) -> void:
	hidden = false
	position = Vector3(at.x, StreetErrands._floor(self, at), at.y)
	_visual.rotation.y = yaw
	_faced = true
	_speed = 0.0
	_panic_left = 0.0
	_pause_left = 0.0
	_end_act(true)
	visible = true
	collision_layer = 8
	var area := _hit_shape.get_parent() as Area3D if _hit_shape else null
	if area:
		area.monitoring = true


## Back to the podium at once (nobody near to see it).
func home_now() -> void:
	if hidden:
		show_at(home, home_yaw)
	_job = []
	_work(true)


func _life_range_changed(_near: bool) -> void:
	pass


func _walk(delta: float) -> void:
	if hidden:
		velocity = Vector3.ZERO
		return
	if not _job.is_empty():
		if _panic_left > 0.0 or _down:
			cancel_job()
		else:
			_do_job(delta)
			return
	super(delta)


func _do_job(delta: float) -> void:
	if _job_k >= _job.size():
		if _job_face < INF and absf(angle_difference(_visual.rotation.y, _job_face)) > 0.2:
			_turn_on_spot(_job_face, delta)
			return
		_pivoting = false
		var done := _job_done
		_job = []
		_job_done = Callable()
		if done.is_valid():
			done.call()
		return
	var goal: Vector2 = _job[_job_k]
	var last := _job_k == _job.size() - 1
	var left := StreetErrands._step_to(self, goal, delta, _job_pace, last)
	if left < (0.12 if last else 0.45):
		_job_k += 1


func _physics_process(delta: float) -> void:
	super(delta)
	if _down or hidden:
		return
	# The scare is over and they are walking about: back to the podium.
	if _job.is_empty() and _act == CrowdLife.Act.NONE and _panic_left <= 0.0 and _cross == Cross.NONE and errand.is_empty():
		_work(false)


func _do_act(delta: float) -> void:
	super(delta)
	if _stage != Stage.DOING or not _life_ok:
		return
	_beat -= delta
	if _beat > 0.0:
		return
	_beat = _life.randf_range(3.0, 7.0)
	if _one_shot_left <= 0.0:
		_life_base = CrowdLife.IDLE if _life.randf() < 0.7 else CrowdLife.FOLD
		_life_clip = _life_base
