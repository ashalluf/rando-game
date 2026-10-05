class_name DogBody
extends AnimatableBody3D
## A dog's hit box (Dog): on the npc layer, so bullets (Player.AIM_MASK), blasts
## (Player.BLAST_MASK) and cars' bumper zones find it; mask 0 (it detects nothing). Everything
## that hits it goes to the dog, which yelps and runs - no blood, no ragdoll: no gore on animals.

var dog: Node


func _init() -> void:
	collision_layer = 8
	collision_mask = 0
	sync_to_physics = false


## A blast, a bumper, a landing shockwave.
func knock(impulse: Vector3, _gibs: int = 0) -> void:
	if is_instance_valid(dog):
		dog.hit(impulse)


## A round (WeaponFX.bullet_wound): the dog is hit, nothing bleeds.
func shot(_at: Vector3, dir: Vector3, impulse: Vector3, _strength: float = 1.0) -> void:
	if is_instance_valid(dog):
		dog.hit(impulse if impulse.length_squared() > 0.01 else dir * 4.0 + Vector3.UP * 2.0)
