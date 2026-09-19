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
	collision_layer = 2
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
	var scene: PackedScene = load(available[_rng.randi() % available.size()])
	if scene == null:
		return false
	var inst := scene.instantiate() as Node3D
	inst.rotation.y = PI # Meshy rigs face +Z; our visuals face -Z
	# The rig's skeleton is in centimeters under a 0.01 armature while the mesh bounds are in
	# meters, so the imported AABB is 2 cm tall and the renderer culls the character. Give the
	# skinned mesh a generous box in skeleton units instead.
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).custom_aabb = AABB(Vector3(-150.0, -10.0, -150.0), Vector3(300.0, 260.0, 300.0))
	_visual.add_child(inst)
	_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for clip in _anim.get_animation_list():
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		if _anim.has_animation("Casual_Walk_inplace"):
			_anim.play("Casual_Walk_inplace")
			_anim.speed_scale = walk_speed / WALK_CLIP_SPEED
	return true


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
	doll.build(shirt, pants, skin)
	PhysicsBudget.register_debris(doll)
	doll.fling(impulse)
	queue_free()
