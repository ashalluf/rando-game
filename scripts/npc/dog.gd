class_name Dog
extends Node3D
## What every dog in the city shares (CrowdDog on a lead, YardDog behind a fence): its body
## (DogRig: the breed's skinned mesh, fur shells, the procedural pose), a hit box on the npc layer
## (DogBody), its bark and its yelp, and what happens when it is hit or a gun goes off near it.
## A hit dog yelps, is thrown a little (a scripted hop, no physics body), and bolts with its tail
## tucked - away from what hit it, round walls it sees ahead - until it is out of sight, then it is
## gone. Never blood, never a ragdoll: no gore on animals. Never a crime either.
##
## Sounds: Sfx `bark_big` (a big dog close up) or `bark_small` (a small dog's yap) by size,
## pitched by size and per dog; `dog_yelp`. CC0 recordings, docs/ASSETS.md.

## Withers height under which a dog yaps instead of barking.
const SMALL_DOG := 0.36

## How far a gun or a blast startles a dog (metres), on top of the alarm's own radius.
@export var startle_reach: float = 10.0
## Bolting: speed (m/s for a 0.5 m dog, scaled by the root of its height), how long before it
## is let go once out of sight, the longest it runs.
@export var flee_speed: float = 6.5
@export var flee_min_seconds: float = 4.0
@export var flee_max_seconds: float = 14.0
## Seconds between barks in a burst.
@export var bark_gap: Vector2 = Vector2(0.38, 0.75)

var rig: DogRig
var breed: String = "labrador"
var look: String = "lab_yellow"
var size_scale: float = 1.0
var hit_box: DogBody
var fleeing: bool = false
## Not simulated and never a crime; tests read this.
var hits_taken: int = 0

var _rng := RandomNumberGenerator.new()
var _pitch: float = 1.0
var _vel := Vector3.ZERO
var _air: bool = false
var _flee_dir := Vector3.FORWARD
var _flee_t: float = 0.0
var _yaw: float = 0.0
var _turn: float = 0.0
var _bark_left: int = 0
var _bark_wait: float = 0.0
var _last_pos := Vector3.INF
var _fear_left: float = 0.0
var _ray_tick: int = 0
var _ground_y: float = 0.0


## The breed, the look and the size from a seed (the same dog every time).
func roll(seed_value: int, breed_name: String = "") -> void:
	_rng.seed = hash([seed_value, "dog"])
	breed = breed_name if breed_name != "" else DogMesh.pick_breed(_rng.randf())
	look = DogMesh.pick_look(breed, _rng.randf())
	size_scale = _rng.randf_range(0.93, 1.07)
	_pitch = _rng.randf_range(0.9, 1.12) * clampf(pow(0.5 / float(DogMesh.breed(breed).h), 0.25), 0.85, 1.35)


func _make_body() -> void:
	add_to_group("dog")
	rig = DogRig.make(breed, look, _rng.randi())
	rig.scale = Vector3.ONE * size_scale
	add_child(rig)
	var b := DogMesh.breed(breed)
	var h: float = float(b.h) * size_scale
	var l: float = float(b.l) * size_scale
	hit_box = DogBody.new()
	hit_box.dog = self
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(b.cw) * 2.2 * size_scale, h * 0.8, l + float(b.hl) * size_scale)
	cs.shape = box
	cs.position = Vector3(0.0, h * 0.58, -float(b.hl) * size_scale * 0.35)
	hit_box.add_child(cs)
	add_child(hit_box)


func height() -> float:
	return float(DogMesh.breed(breed).h) * size_scale


func is_small() -> bool:
	return height() < SMALL_DOG


## Barks `n` times, a burst (the rig snaps its jaw on each).
func bark(n: int = 1) -> void:
	_bark_left = maxi(_bark_left, n)
	if _bark_wait <= 0.0:
		_bark_wait = 0.0


func _bark_now() -> void:
	if rig:
		rig.bark = 1.0
	if is_inside_tree():
		Sfx.play("bark_small" if is_small() else "bark_big", global_position + Vector3.UP * height() * 0.8,
			-2.0 if is_small() else 0.0, _pitch * _rng.randf_range(0.95, 1.05))


func _tick_barks(dt: float) -> void:
	if _bark_left <= 0:
		return
	_bark_wait -= dt
	if _bark_wait <= 0.0:
		_bark_now()
		_bark_left -= 1
		_bark_wait = _rng.randf_range(bark_gap.x, bark_gap.y) * (0.7 if is_small() else 1.0)


## Something hit it (DogBody): a yelp, a hop away from the blow, then it bolts.
func hit(impulse: Vector3) -> void:
	hits_taken += 1
	if is_inside_tree():
		Sfx.play("dog_yelp", global_position + Vector3.UP * height() * 0.7, 0.0, _pitch * _rng.randf_range(0.95, 1.1))
	var flat := Vector3(impulse.x, 0.0, impulse.z)
	if flat.length_squared() < 0.01:
		flat = -global_basis.z
	# A scripted hop: the blow's push, capped, so a rocket throws a dog a few metres, not forty.
	var push := clampf(impulse.length() * 0.35, 1.5, 7.0)
	_vel = flat.normalized() * push + Vector3.UP * clampf(impulse.y * 0.4 + 2.0, 2.0, 6.0)
	_air = true
	_bolt(flat.normalized())
	_on_hit()


## A gun or a blast near it (Pedestrian.alarm, through Dog.startle).
func startle(at: Vector3) -> void:
	_fear_left = maxf(_fear_left, 6.0)
	_on_startle(at)


## Every dog within `radius` (plus startle_reach) of `at` hears it.
static func startle_all(tree: SceneTree, at: Vector3, radius: float) -> void:
	if tree == null:
		return
	for n in tree.get_nodes_in_group("dog"):
		var d := n as Dog
		if d == null or not d.is_inside_tree():
			continue
		if d.global_position.distance_to(at) <= radius + d.startle_reach:
			d.startle(at)


## Hooks for the brains.
func _on_hit() -> void:
	pass


func _on_startle(_at: Vector3) -> void:
	pass


## Runs off along `dir` (world).
func _bolt(dir: Vector3) -> void:
	if not fleeing:
		fleeing = true
		_flee_t = 0.0
		_yaw = rotation.y
	_flee_dir = dir
	_fear_left = maxf(_fear_left, flee_max_seconds)


## The bolt: ballistic while thrown, then a gallop along the flee direction, turning off walls,
## following the ground; gone once out of sight (or after flee_max_seconds).
func _tick_flee(dt: float) -> void:
	_flee_t += dt
	var h := height()
	var spd := flee_speed * sqrt(h / 0.5)
	if _air:
		_vel.y -= 18.0 * dt
		global_position += _vel * dt
		var g := _ground_at(global_position)
		if global_position.y <= g and _vel.y < 0.0:
			global_position.y = g
			_air = false
	else:
		_ray_tick += 1
		if _ray_tick % 6 == 0:
			_steer_off_walls(h)
		var want := atan2(-_flee_dir.x, -_flee_dir.z)
		var prev := _yaw
		_yaw = lerp_angle(_yaw, want, 1.0 - exp(-6.0 * dt))
		_turn = wrapf(_yaw - prev, -PI, PI) / maxf(dt, 1e-4)
		rotation.y = _yaw
		var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		global_position += fwd * spd * dt
		if _ray_tick % 3 == 0:
			_ground_y = _ground_at(global_position)
		global_position.y = lerpf(global_position.y, _ground_y, 1.0 - exp(-14.0 * dt))
	if rig:
		rig.fear = 1.0
		rig.sit = 0.0
		rig.sniff = 0.0
		rig.speed = 0.0 if _air else spd
		rig.turn = _turn
		rig.look_at = Vector3.INF
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var unseen := cam == null or cam.global_position.distance_to(global_position) > 40.0 \
		or (-cam.global_basis.z).dot((global_position - cam.global_position).normalized()) < 0.2
	if (_flee_t > flee_min_seconds and unseen) or _flee_t > flee_max_seconds:
		queue_free()


func _steer_off_walls(h: float) -> void:
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * h * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + _flee_dir.normalized() * 3.5, 1)
	if space.intersect_ray(q).is_empty():
		return
	# A wall ahead: try left and right of it, take the open side.
	for a in [0.9, -0.9, 1.6, -1.6, PI]:
		var d := _flee_dir.rotated(Vector3.UP, a)
		q = PhysicsRayQueryParameters3D.create(from, from + d * 3.5, 1)
		if space.intersect_ray(q).is_empty():
			_flee_dir = d
			return


## The ground under a point (a world-layer ray), or the point's own height when nothing is hit.
func _ground_at(p: Vector3) -> float:
	if not is_inside_tree():
		return p.y
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 3.0, 1)
	var hit_d := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit_d.position as Vector3).y if not hit_d.is_empty() else p.y


## Steps the body (call once a tick with the tick's seconds).
func _advance_rig(dt: float) -> void:
	_tick_barks(dt)
	_fear_left = maxf(_fear_left - dt, 0.0)
	if rig:
		rig.advance(dt)
