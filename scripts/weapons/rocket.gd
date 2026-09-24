class_name Rocket
extends Node3D
## Dumb-fire rocket. Flies straight, explodes on contact or after `lifetime` seconds.

var speed: float = 70.0
var lifetime: float = 6.0
var explosion_radius: float = 9.0
var explosion_launch_speed: float = 30.0
var player_launch_speed: float = 35.0
var direction: Vector3 = Vector3.FORWARD
var exclude: Array[RID] = []
## Seconds a trail puff hangs in the air.
var trail_seconds: float = 2.2
## Energy of the motor's own light (lights the street as it passes at night).
var motor_light: float = 2.5
## The warhead the launcher had loaded, placed in this rocket's space, or null for the old
## primitive body. Set before the rocket enters the tree.
var model: Node3D

var _age: float = 0.0
var _trail: CPUParticles3D
var _exploded: bool = false


func _ready() -> void:
	# The launcher's own warhead flies, rather than a red tube swapped in for it at the muzzle.
	# The motor flame and the smoke sit at its tail (+Z is backwards).
	var tail := 0.42
	if model:
		add_child(model)
		var box := AABB()
		var first := true
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != self and n is Node3D:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			var b := xf * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if not first:
			tail = box.end.z
	else:
		_build_primitive_body()
	# The motor: a hot billboard glare and a small light, not a lit orange ball.
	var flame := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	flame.mesh = quad
	var glare := StandardMaterial3D.new()
	glare.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glare.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glare.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glare.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glare.albedo_texture = WeaponFX.flare_texture()
	glare.albedo_color = Color(1.0, 0.62, 0.25)
	glare.disable_receive_shadows = true
	flame.material_override = glare
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.position = Vector3(0.0, 0.0, tail + 0.05)
	add_child(flame)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.3)
	glow.light_energy = motor_light
	glow.omni_range = 7.0
	glow.position = flame.position
	add_child(glow)

	# The trail: the explosion's own billowing smoke, puffs that start tight and bright behind
	# the motor and swell and thin as they hang in the air. Grey primitive spheres read as a
	# string of beads.
	var smoke := CPUParticles3D.new()
	_trail = smoke
	smoke.amount = 70
	smoke.lifetime = trail_seconds
	smoke.lifetime_randomness = 0.3
	smoke.local_coords = false
	smoke.direction = Vector3(0.0, 0.0, 1.0)
	smoke.spread = 10.0
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 1.6
	smoke.damping_min = 0.6
	smoke.damping_max = 1.2
	smoke.gravity = Vector3(0.0, 0.5, 0.0)
	smoke.angle_min = -180.0
	smoke.angle_max = 180.0
	smoke.scale_amount_min = 0.45
	smoke.scale_amount_max = 0.8
	var grow := Curve.new()
	grow.max_value = 4.0
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 4.0))
	smoke.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.92, 0.9, 0.86, 0.75))
	fade.set_color(1, Color(0.62, 0.62, 0.62, 0.0))
	fade.add_point(0.08, Color(1.0, 0.82, 0.6, 0.7))
	fade.add_point(0.3, Color(0.82, 0.81, 0.79, 0.45))
	smoke.color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2.ONE
	puff.material = WeaponFX.smoke_material()
	smoke.mesh = puff
	smoke.position = Vector3(0.0, 0.0, tail + 0.1)
	# World-space particles trail back along the whole flight; bounds start empty otherwise.
	smoke.custom_aabb = AABB(Vector3(-40.0, -40.0, -40.0), Vector3(80.0, 80.0, 80.0))
	add_child(smoke)


## The old stand-in body: a tube and a nose cone, for a launcher with no model file.
func _build_primitive_body() -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = 0.7
	cyl.radial_segments = 8
	body.mesh = cyl
	body.material_override = WeaponFX.unshaded(Color(0.75, 0.2, 0.15))
	body.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(body)
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = 0.25
	cone.radial_segments = 8
	nose.mesh = cone
	nose.material_override = WeaponFX.unshaded(Color(0.9, 0.85, 0.3))
	nose.position = Vector3(0.0, 0.0, -0.47)
	nose.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(nose)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_age += delta
	var step := direction * speed * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, Player.AIM_MASK, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		explode(hit.position)
		return
	global_position += step
	if _age >= lifetime:
		explode(global_position)


func explode(at: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	# The trail stays hanging in the air after the warhead is gone.
	if _trail and get_parent():
		_trail.reparent(get_parent())
		_trail.emitting = false
		var tween := _trail.create_tween()
		tween.tween_interval(trail_seconds * 1.4)
		tween.tween_callback(_trail.queue_free)
	Explosion.blast(self, at, explosion_radius, explosion_launch_speed, player_launch_speed)
	queue_free()
