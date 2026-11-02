class_name MotoThrow
extends Node
## The hero thrown off a motorcycle (Motorcycle.throw_rider(): a crash, a landing on its side, a
## blast): he goes on as a ragdoll of his own rig in his own clothes (PlayerHealth's doll), flung
## with the bike's speed, the camera following the body, and gets up where it stopped - after
## `min_seconds`, once it lies still, at most `max_seconds`. No damage: the hero is overpowered,
## the fall is the show. Off for the duration: his input, his gun, his collision.

## Seconds the body tumbles at least and at most before he is back on his feet.
@export var min_seconds: float = 1.3
@export var max_seconds: float = 4.0

var player: Player
var doll: Ragdoll
var _t: float = 0.0


## Throws `p` from `from` (scene position) at velocity `v` (m/s).
static func throw(p: Player, from: Vector3, v: Vector3) -> MotoThrow:
	if p == null or not p.is_inside_tree():
		return null
	var host := p.get_tree().current_scene if p.get_tree().current_scene else p.get_parent()
	var d := Ragdoll.new()
	host.add_child(d)
	d.global_position = from - Vector3.UP * 0.9
	d.rotation.y = p.visual.global_rotation.y if p.visual else 0.0
	if not d.build_from_rig(p.avatar_model, p.avatar_look):
		d.build(Color(0.2, 0.04, 0.05), Color(0.2, 0.04, 0.05), Color(0.8, 0.6, 0.5))
	elif p.health:
		p.health._dress_doll(d)
	# A Ragdoll's fling() is an impulse on its 23 kg: this much is the bike's speed.
	d.fling((v + Vector3.UP * 2.5) * Ragdoll.TOTAL_MASS)
	var t := MotoThrow.new()
	t.name = "MotoThrow"
	t.player = p
	t.doll = d
	host.add_child(t)
	p.set_physics_process(false)
	p.visual.visible = false
	p.collision_layer = 0
	p.collision_mask = 0
	if p.weapon_manager:
		p.weapon_manager.visible = false
	Sfx.play("yelp", from, 0.0, 0.9)
	return t


func _physics_process(delta: float) -> void:
	_t += delta
	if player == null or not is_instance_valid(player):
		queue_free()
		return
	if doll == null or not is_instance_valid(doll) or doll.bodies.is_empty():
		_get_up(player.global_position)
		return
	var body: RigidBody3D = doll.bodies[0]
	player.global_position = body.global_position + Vector3.UP * 0.2
	player.velocity = Vector3.ZERO
	var still := body.linear_velocity.length() < 0.6
	if (_t > min_seconds and still) or _t > max_seconds:
		_get_up(body.global_position)


func _get_up(at: Vector3) -> void:
	if is_instance_valid(doll):
		doll.queue_free()
	if is_instance_valid(player):
		player.global_position = at + Vector3.UP * 0.5
		player.velocity = Vector3.ZERO
		player.visual.visible = true
		player.collision_layer = 2
		player.collision_mask = 5
		if player.weapon_manager:
			player.weapon_manager.visible = true
		player.set_physics_process(true)
		player.recover_from_fall()
	queue_free()
