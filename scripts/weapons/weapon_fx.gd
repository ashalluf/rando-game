class_name WeaponFX
extends RefCounted
## Cheap, code-built visual effects for weapons: tracers, muzzle flashes, impacts, explosions.
## Everything is unshaded primitives and short tweens, so it works on the web build too.


static func fx_parent(node: Node) -> Node:
	var scene := node.get_tree().current_scene
	return scene if scene != null else node.get_tree().root


static func unshaded(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## A thin glowing line from `from` to `to` that shrinks away over `life` seconds.
static func tracer(node: Node, from: Vector3, to: Vector3, color: Color, life: float = 0.06, radius: float = 0.03) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.05:
		return
	dir /= length
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 6
	cyl.rings = 1
	mesh.mesh = cyl
	mesh.material_override = unshaded(color)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	fx_parent(node).add_child(mesh)
	mesh.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, -PI * 0.5), from + dir * length * 0.5)
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "scale", Vector3(0.01, 1.0, 0.01), life)
	tween.tween_callback(mesh.queue_free)


## A brief bright blob at the muzzle.
static func flash(node: Node, at: Vector3, color: Color = Color(1.0, 0.8, 0.3), size: float = 0.25, life: float = 0.05) -> void:
	var mesh := _sphere(node, at, size, color, 1.0)
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE * 0.05, life)
	tween.tween_callback(mesh.queue_free)


## A small puff where a bullet lands.
static func impact(node: Node, at: Vector3, color: Color = Color(1.0, 0.85, 0.5)) -> void:
	var mesh := _sphere(node, at, 0.12, color, 0.9)
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE * 0.5, 0.15)
	tween.parallel().tween_property(mesh.material_override, "albedo_color:a", 0.0, 0.15)
	tween.tween_callback(mesh.queue_free)


## Expanding fireball plus a burst of chunks.
static func explosion(node: Node, at: Vector3, radius: float) -> void:
	var parent := fx_parent(node)
	var core := _sphere(node, at, 0.6, Color(1.0, 0.95, 0.7), 0.95)
	var fire := _sphere(node, at, 0.4, Color(1.0, 0.45, 0.1), 0.85)
	var t1 := core.create_tween()
	t1.tween_property(core, "scale", Vector3.ONE * radius * 0.35, 0.12)
	t1.parallel().tween_property(core.material_override, "albedo_color:a", 0.0, 0.2)
	t1.tween_callback(core.queue_free)
	var t2 := fire.create_tween()
	t2.tween_property(fire, "scale", Vector3.ONE * radius * 0.6, 0.3).set_ease(Tween.EASE_OUT)
	t2.parallel().tween_property(fire.material_override, "albedo_color:a", 0.0, 0.4)
	t2.tween_callback(fire.queue_free)

	var chunks := CPUParticles3D.new()
	chunks.one_shot = true
	chunks.explosiveness = 1.0
	chunks.amount = 36
	chunks.lifetime = 0.9
	chunks.direction = Vector3.UP
	chunks.spread = 180.0
	chunks.initial_velocity_min = radius * 1.2
	chunks.initial_velocity_max = radius * 2.4
	chunks.gravity = Vector3(0.0, -30.0, 0.0)
	chunks.scale_amount_min = 0.6
	chunks.scale_amount_max = 1.4
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.25, 0.25)
	box.material = unshaded(Color(0.25, 0.22, 0.2))
	chunks.mesh = box
	parent.add_child(chunks)
	chunks.global_position = at
	chunks.emitting = true
	var t3 := chunks.create_tween()
	t3.tween_interval(chunks.lifetime + 0.1)
	t3.tween_callback(chunks.queue_free)


static func _sphere(node: Node, at: Vector3, size: float, color: Color, alpha: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	mesh.mesh = sphere
	mesh.material_override = unshaded(color, alpha)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_parent(node).add_child(mesh)
	mesh.global_position = at
	mesh.scale = Vector3.ONE * size
	return mesh
