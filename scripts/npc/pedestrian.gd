class_name Pedestrian
extends CharacterBody3D
## Wandering pedestrian. Walks between random points on its block's sidewalk ring, bobs a bit,
## and turns into a ragdoll when something fast hits it (cars, crates, explosions, bullets,
## a boosting player). Collides with the world only, so cars never get stuck on it.

const SHIRTS := [Color(0.9, 0.3, 0.3), Color(0.3, 0.5, 0.9), Color(0.95, 0.85, 0.3), Color(0.4, 0.75, 0.45), Color(0.9, 0.9, 0.9), Color(0.6, 0.35, 0.7), Color(0.95, 0.55, 0.2)]
const PANTS := [Color(0.2, 0.25, 0.4), Color(0.15, 0.15, 0.17), Color(0.5, 0.4, 0.3), Color(0.35, 0.35, 0.38)]
const SKINS := [Color(0.95, 0.8, 0.65), Color(0.85, 0.65, 0.5), Color(0.6, 0.42, 0.3), Color(0.4, 0.28, 0.2)]
## Generated rigged characters (see docs/ASSETS.md). Each has Idle, Casual_Walk_inplace and
## run_fast_3_inplace clips. Missing files fall back to the box person.
const MODELS := [
	"res://assets/models/pedestrian_a_anim.glb",
	"res://assets/models/pedestrian_b_anim.glb",
	"res://assets/models/pedestrian_c_anim.glb",
]
## Walking speed (m/s) at which the walk clip plays at its natural pace.
const WALK_CLIP_SPEED := 1.3

@export var walk_speed: float = 1.8
## Anything moving faster than this that touches us knocks us over (m/s).
@export var knock_speed: float = 4.0
## A boosting player has to be at least this fast to tackle us (m/s).
@export var tackle_speed: float = 14.0

var ring: Rect2
var shirt: Color
var pants: Color
var skin: Color
var _target: Vector2
var _rng := RandomNumberGenerator.new()
var _visual: Node3D
var _bob: float = 0.0
var _down: bool = false
var _anim: AnimationPlayer
## Which rig this pedestrian wears ("" for the box person); the ragdoll keeps the same one.
var _model_path: String = ""
## Clothing look index, so the ragdoll that replaces this pedestrian keeps the same outfit.
var _look: int = 0
## Update LOD: far pedestrians move and animate every Nth physics frame (see _update_lod).
var _lod_stride: int = 1
var _lod_tick: int = 0
var _lod_timer: float = 0.0
static var _player: Node3D


func setup(block_rect: Rect2, sidewalk: float, seed_value: int) -> void:
	ring = block_rect
	_rng.seed = seed_value
	shirt = SHIRTS[_rng.randi() % SHIRTS.size()]
	pants = PANTS[_rng.randi() % PANTS.size()]
	skin = SKINS[_rng.randi() % SKINS.size()]
	walk_speed = _rng.randf_range(1.4, 2.6)
	_target = _random_ring_point(sidewalk)
	_sidewalk = sidewalk


var _sidewalk: float = 4.0


func _ready() -> void:
	add_to_group("pedestrian")
	collision_layer = 8 # the npc layer: bullets, blasts and bumpers look for it
	collision_mask = 1
	floor_snap_length = 0.4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.85, 0.0)
	add_child(shape)
	_visual = Node3D.new()
	add_child(_visual)
	if _add_model():
		_add_hit_area()
		return
	_part(Vector3(0.5, 0.65, 0.3), Vector3(0.0, 1.05, 0.0), shirt)
	_part(Vector3(0.2, 0.7, 0.2), Vector3(-0.14, 0.38, 0.0), pants)
	_part(Vector3(0.2, 0.7, 0.2), Vector3(0.14, 0.38, 0.0), pants)
	_part(Vector3(0.16, 0.6, 0.16), Vector3(-0.36, 1.05, 0.0), skin)
	_part(Vector3(0.16, 0.6, 0.16), Vector3(0.36, 1.05, 0.0), skin)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	sphere.radial_segments = 8
	sphere.rings = 4
	head.mesh = sphere
	head.material_override = PropFactory.material(skin, 0.8)
	head.position = Vector3(0.0, 1.55, 0.0)
	_visual.add_child(head)
	_add_hit_area()


## Picks one of the generated characters (seeded) and starts its walk cycle. False if none exist.
func _add_model() -> bool:
	var available: Array[String] = []
	for path in MODELS:
		if ResourceLoader.exists(path):
			available.append(path)
	if available.is_empty():
		return false
	var path: String = available[_rng.randi() % available.size()]
	var scene: PackedScene = load(path)
	if scene == null:
		return false
	var inst := scene.instantiate() as Node3D
	inst.rotation.y = PI # Meshy rigs face +Z; our visuals face -Z
	_look = _rng.randi() % CHARACTER_LOOKS
	prepare_rig(inst, _look)
	_visual.add_child(inst)
	_model_path = path
	# Build variation: nobody in a crowd is the same height or width as the person next to them.
	var tall := _rng.randf_range(0.90, 1.10)
	_visual.scale = Vector3(_rng.randf_range(0.94, 1.07), tall, _rng.randf_range(0.94, 1.07))
	_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for clip in _anim.get_animation_list():
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		# Advanced by hand in _physics_process so far pedestrians can animate less often.
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if _anim.has_animation("Casual_Walk_inplace"):
			_anim.play("Casual_Walk_inplace")
			_anim.speed_scale = walk_speed / WALK_CLIP_SPEED
			# Start everyone at a different point in the cycle. A crowd stepping in perfect
			# unison is the most obvious tell that they are all the same model.
			_anim.seek(_rng.randf() * _anim.get_animation("Casual_Walk_inplace").length, true)
	return true


## Fixes an instantiated rig so it renders right (shared by pedestrians, ragdolls and the
## player's avatar). The rig's skeleton is in centimeters under a 0.01 armature while the mesh
## bounds are in meters, so the imported AABB is 2 cm tall and the renderer culls the character:
## give the skinned mesh a generous box in skeleton units. Meshy's animated export also keeps
## only the base color and leaves the glTF defaults of metallic 1 plus a full emission of the
## same texture (a shiny, self-lit mannequin): make it plain skin and cloth. The material is
## shared by every instance of the model.
static func prepare_rig(inst: Node3D, look: int = -1) -> void:
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).custom_aabb = AABB(Vector3(-150.0, -10.0, -150.0), Vector3(300.0, 260.0, 300.0))
		var mat := (mi as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
		if mat and mat.metallic_texture == null:
			mat.metallic = 0.0
			mat.roughness = 0.85
			mat.emission_enabled = false
		if look >= 0 and mat:
			(mi as MeshInstance3D).material_override = character_material(mat.albedo_texture, look)


## Character materials, shared by look so a crowd of hundreds still uses a handful of materials.
## `look` picks a clothing hue and brightness; see shaders/character.gdshader.
const CHARACTER_LOOKS := 14
static var _looks: Dictionary = {}


static func character_material(albedo: Texture2D, look: int) -> ShaderMaterial:
	if albedo == null:
		return null
	var key := "%d_%d" % [albedo.get_instance_id(), look % CHARACTER_LOOKS]
	if _looks.has(key):
		return _looks[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4200 + (look % CHARACTER_LOOKS)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/character.gdshader")
	mat.set_shader_parameter("albedo_tex", albedo)
	# One look in five keeps the original outfit, so the source clothes still appear.
	var plain := look % 5 == 0
	mat.set_shader_parameter("cloth_hue", rng.randf())
	# Most clothes are muted; a few people wear something bright.
	mat.set_shader_parameter("cloth_sat", rng.randf_range(0.10, 0.30) if rng.randf() < 0.75 else rng.randf_range(0.35, 0.62))
	mat.set_shader_parameter("cloth_value", rng.randf_range(0.55, 1.20))
	mat.set_shader_parameter("cloth_strength", 0.0 if plain else rng.randf_range(0.55, 0.85))
	_looks[key] = mat
	return mat


func _add_hit_area() -> void:
	# Hit detector: anything fast on the props layer, or a fast player.
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2 | 4
	var ashape := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	abox.size = Vector3(1.0, 1.8, 1.0)
	ashape.shape = abox
	ashape.position = Vector3(0.0, 0.9, 0.0)
	area.add_child(ashape)
	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _part(size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = PropFactory.material(color, 0.8)
	mesh.position = pos
	_visual.add_child(mesh)


func _physics_process(delta: float) -> void:
	if _down:
		return
	_lod_timer += delta
	if _lod_timer >= 0.5:
		_lod_timer = 0.0
		_update_lod()
	_lod_tick += 1
	if _lod_stride > 1 and _lod_tick % _lod_stride != 0:
		return
	delta *= _lod_stride
	if _anim:
		_anim.advance(delta)
	var here := Vector2(global_position.x, global_position.z) - _ring_origin()
	var to_target := _target - here
	if to_target.length() < 1.0:
		_target = _random_ring_point(_sidewalk)
		to_target = _target - here
	var dir := to_target.normalized()
	velocity.x = dir.x * walk_speed
	velocity.z = dir.y * walk_speed
	if not is_on_floor():
		velocity.y -= 30.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-dir.x, -dir.y), 1.0 - exp(-8.0 * delta))
	if _anim == null:
		_bob += delta * walk_speed * 4.0
		_visual.position.y = absf(sin(_bob)) * 0.06


## Far pedestrians move and animate every 3rd (past lod_mid) or 6th (past lod_far) physics
## frame with a matching delta, so a crowd of hundreds costs what a few dozen used to.
static var lod_mid: float = 60.0
static var lod_far: float = 140.0


func _update_lod() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			_lod_stride = 1
			return
	var d := global_position.distance_to(_player.global_position)
	_lod_stride = 1 if d < lod_mid else (3 if d < lod_far else 6)


## Ring points are stored relative to the chunk's world offset so re-centering does not matter.
func _ring_origin() -> Vector2:
	return Vector2.ZERO


func _random_ring_point(sidewalk: float) -> Vector2:
	# A point on the sidewalk ring: pick an edge, then a spot 1..(sidewalk-1) m in from the curb.
	var inset := _rng.randf_range(1.0, maxf(sidewalk - 1.0, 1.2))
	var edge := _rng.randi() % 4
	match edge:
		0:
			return Vector2(_rng.randf_range(ring.position.x + 1.0, ring.end.x - 1.0), ring.position.y + inset)
		1:
			return Vector2(_rng.randf_range(ring.position.x + 1.0, ring.end.x - 1.0), ring.end.y - inset)
		2:
			return Vector2(ring.position.x + inset, _rng.randf_range(ring.position.y + 1.0, ring.end.y - 1.0))
		_:
			return Vector2(ring.end.x - inset, _rng.randf_range(ring.position.y + 1.0, ring.end.y - 1.0))


func _on_body_entered(body: Node3D) -> void:
	if _down:
		return
	var speed := 0.0
	var dir := Vector3.UP
	if body is RigidBody3D:
		speed = (body as RigidBody3D).linear_velocity.length()
		dir = (body as RigidBody3D).linear_velocity.normalized()
		if body is Vehicle and (body as Vehicle).is_traffic():
			speed = (body as Vehicle).traffic_speed
			dir = -(body as Vehicle).global_basis.z
	elif body is Player:
		speed = (body as Player).velocity.length()
		dir = (body as Player).velocity.normalized()
		if speed < tackle_speed:
			return
	if speed >= knock_speed:
		knock(dir * (8.0 + speed * 0.6) + Vector3.UP * 6.0)


## Turns into a ragdoll flung by `impulse`.
func knock(impulse: Vector3) -> void:
	if _down:
		return
	_down = true
	Sfx.play("yelp", global_position, 0.0, _rng.randf_range(0.8, 1.3))
	var doll := Ragdoll.new()
	doll.position = position
	doll.rotation.y = _visual.rotation.y
	get_parent().add_child(doll)
	if _model_path == "" or not doll.build_from_rig(_model_path, _look):
		doll.build(shirt, pants, skin)
	PhysicsBudget.register_debris(doll)
	doll.fling(impulse)
	queue_free()
