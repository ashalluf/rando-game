class_name Explosion
extends RefCounted
## Radial blast: shoves every physics prop in range and launches the player (rocket jumps!).


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
		var falloff := clampf(1.0 - dist / radius, 0.2, 1.0)
		var dir := (offset + Vector3.UP * radius * 0.35).normalized() if dist > 0.01 else Vector3.UP
		if collider is Vehicle:
			(collider as Vehicle).drop_out_of_traffic()
		if collider.has_method("knock"):
			collider.knock(dir * launch_speed * falloff * 1.2)
			affected += 1
			continue
		if collider is RigidBody3D:
			var body := collider as RigidBody3D
			body.freeze = false
			body.sleeping = false
			body.apply_central_impulse(dir * launch_speed * falloff * body.mass)
			body.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * body.mass * 2.0)
			affected += 1
		elif collider is Player:
			(collider as Player).launch(dir * player_launch_speed * falloff)
			affected += 1
		elif collider.has_method("take_hit"):
			collider.take_hit(result.get("shape", -1), 120.0 * falloff, dir)
			affected += 1
	WeaponFX.explosion(node, at, radius)
	return affected
