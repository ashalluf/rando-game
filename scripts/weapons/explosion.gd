class_name Explosion
extends RefCounted
## Radial blast: shoves every physics prop in range and launches the player (rocket jumps!).


# Tunables. This is a static utility class, never a node, so these are static vars rather than
# @export: set them from anywhere (Explosion.up_bias = 0.5) and every blast follows.

## How much of the blast is aimed upward rather than straight out from the centre, as a
## fraction of the radius. Higher throws cars into the air; 0 slides everything along the road.
static var up_bias: float = 0.35
## Extra shove given to anything with a `knock()` (pedestrians), which has no mass to scale by.
static var knock_scale: float = 1.2
## Spin handed to every rigid body, per kilogram. This is what makes debris tumble.
static var spin_scale: float = 2.0
## Damage dealt to breakable street props at the centre of the blast.
static var prop_damage: float = 120.0
## Smallest share of the blast strength anything inside the radius keeps, so a prop at the very
## edge still moves instead of being ignored.
static var min_falloff: float = 0.2
## Blast strength that counts as "normal" (a rocket) when scaling how hard the effect throws
## its sparks and debris. Bigger launch speeds throw faster fire.
static var reference_launch: float = 30.0
## Fraction of the blast radius inside which people lose limbs (more of them nearer the centre).
static var gib_reach: float = 0.6


## `launch_speed` is the velocity change at the center for props (scaled by falloff, not mass).
static func blast(node: Node3D, at: Vector3, radius: float, launch_speed: float, player_launch_speed: float) -> int:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), at)
	query.collision_mask = Player.BLAST_MASK
	var results := node.get_world_3d().direct_space_state.intersect_shape(query, 256)
	var affected := 0
	for result in results:
		var collider: Object = result.collider
		var target := collider as Node3D
		if target == null:
			continue
		var offset := target.global_position - at
		if target is CharacterBody3D:
			offset.y += 0.9 # aim at the chest, not the feet
		var dist := offset.length()
		var falloff := clampf(1.0 - dist / radius, min_falloff, 1.0)
		var dir := (offset + Vector3.UP * radius * up_bias).normalized() if dist > 0.01 else Vector3.UP
		if collider is Vehicle:
			(collider as Vehicle).drop_out_of_traffic()
		if collider is Pedestrian:
			# Close to the blast people come apart: up to three limbs at the centre, one at the
			# edge of `gib_reach`, none past it (owner, 2026-09-23: "limbs flying off").
			var near := 1.0 - dist / maxf(radius * gib_reach, 0.01)
			var gibs := 0 if near <= 0.0 else clampi(int(ceil(near * 3.0)), 1, 3)
			(collider as Pedestrian).knock(dir * launch_speed * falloff * knock_scale, gibs)
			affected += 1
			continue
		if collider.has_method("knock"):
			collider.knock(dir * launch_speed * falloff * knock_scale)
			affected += 1
			continue
		if collider is RigidBody3D:
			var body := collider as RigidBody3D
			body.freeze = false
			body.sleeping = false
			body.apply_central_impulse(dir * launch_speed * falloff * body.mass)
			body.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * body.mass * spin_scale)
			affected += 1
		elif collider is Player:
			(collider as Player).launch(dir * player_launch_speed * falloff)
			# Only hurts with PlayerHealth.self_blast_damage on (rocket jumps stay free).
			(collider as Player).blast_hit(falloff, at)
			affected += 1
		elif collider.has_method("take_hit"):
			collider.take_hit(result.get("shape", -1), prop_damage * falloff, dir)
			affected += 1
	# The effect is thrown as hard as the blast is: a heavier charge sprays its sparks and
	# debris further, so the picture and the physics agree instead of every blast looking alike.
	WeaponFX.explosion(node, at, radius, launch_speed / maxf(reference_launch, 1.0))
	Sfx.play("explosion", at, 4.0)
	# Everyone for a block around runs; the ones nearest scream.
	Pedestrian.alarm(node.get_tree(), at, maxf(55.0, radius * 6.0), 5, true)
	return affected
