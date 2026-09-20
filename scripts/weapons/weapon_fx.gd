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


## A soft round particle sprite, built once: a radial white-to-transparent gradient. Without
## it every puff is a hard square, which is the single most obvious tell of a cheap effect.
static var _puff_cache: Texture2D


static func puff_texture() -> Texture2D:
	if _puff_cache != null:
		return _puff_cache
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.45, Color(1.0, 1.0, 1.0, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_puff_cache = tex
	return tex


## Material for a billboarded particle sprite. `additive` for fire and sparks (they add light),
## plain alpha for smoke (it blocks light).
static func _puff_material(additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Billboarding normalises the particle's transform, which throws away scale_amount and makes
	# every puff exactly one metre no matter what the emitter asks for. This keeps the size.
	mat.billboard_keep_scale = true
	mat.particles_anim_h_frames = 1
	mat.particles_anim_v_frames = 1
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = puff_texture()
	mat.disable_receive_shadows = true
	return mat


## One layer of billboarded puffs. Returns the node so the caller can position it.
static func _puff_layer(parent: Node, at: Vector3, count: int, size: float, life: float,
		speed_min: float, speed_max: float, gravity: float, ramp: Gradient, additive: bool,
		spread: float = 180.0, grow: float = 2.2) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.gravity = Vector3(0.0, gravity, 0.0)
	p.damping_min = speed_max * 0.2
	p.damping_max = speed_max * 0.45
	p.scale_amount_min = size * 0.65
	p.scale_amount_max = size
	# Curve values are clamped to max_value, which defaults to 1.0 - without raising it the
	# `grow` factor silently does nothing and puffs never expand as they age.
	var curve := Curve.new()
	curve.max_value = maxf(1.0, grow)
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, grow))
	p.scale_amount_curve = curve
	p.color_ramp = ramp
	p.angle_min = -180.0
	p.angle_max = 180.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _puff_material(additive)
	p.mesh = quad
	parent.add_child(p)
	p.global_position = at
	# A particle system's automatic bounds start empty, and an empty box means the renderer has
	# nothing to draw against, so the whole burst can vanish. Give it a box big enough for how
	# far the particles will actually travel. (Same trap as the rigged character meshes.)
	var reach := speed_max * life + size * maxf(grow, 1.0) + absf(gravity) * life * life
	p.custom_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * (reach * 2.0))
	p.restart()
	p.emitting = true
	var tween := p.create_tween()
	tween.tween_interval(life + 0.2)
	tween.tween_callback(p.queue_free)
	return p


static func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, colors[0])
	g.set_color(1, colors[colors.size() - 1])
	for i in range(1, colors.size() - 1):
		g.add_point(float(i) / float(colors.size() - 1), colors[i])
	return g


## A full explosion: light flash, fireball, rolling smoke, sparks, a ground shockwave, debris
## and a scorch mark, plus a camera shake that falls off with distance.
static func explosion(node: Node, at: Vector3, radius: float) -> void:
	var parent := fx_parent(node)

	# 1. The flash. A real light is what makes an explosion feel like it happened in the world
	# instead of being painted on top of it: it lights the street, the cars and the people.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.36)
	light.light_energy = 14.0
	light.omni_range = radius * 4.0
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = at + Vector3.UP * radius * 0.3
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 6.0, 0.06)
	lt.tween_property(light, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_IN)
	lt.tween_callback(light.queue_free)

	# 2. White-hot core, very short.
	var core := _sphere(node, at, radius * 0.25, Color(1.0, 0.97, 0.85), 1.0)
	(core.material_override as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var ct := core.create_tween()
	ct.tween_property(core, "scale", Vector3.ONE * radius * 0.7, 0.10).set_ease(Tween.EASE_OUT)
	ct.parallel().tween_property(core.material_override, "albedo_color:a", 0.0, 0.14)
	ct.tween_callback(core.queue_free)

	# 3. Fireball: hot yellow through orange to a dark cooling edge, rising as it goes.
	# Puff sizes are a fraction of the radius, not a multiple: one puff is a piece of the
	# fireball, and sizing them in whole radii makes single quads swallow the camera.
	# Alpha-blended, not additive: burning fuel is opaque. Additive fire only adds brightness,
	# so in daylight it washes out to nothing against a sunlit street.
	# Slow and fat, not fast and small: a fireball is one rolling mass of overlapping puffs.
	# Throwing them outward at the blast speed just scatters them into separate dots.
	_puff_layer(parent, at, 38, radius * 0.52, 0.95, radius * 0.18, radius * 0.7, 2.5,
		_ramp([Color(1.0, 0.96, 0.72, 1.0), Color(1.0, 0.62, 0.16, 1.0),
			Color(0.62, 0.18, 0.04, 0.85), Color(0.13, 0.10, 0.09, 0.0)]), false, 180.0, 1.6)

	# 4. Smoke: slower, bigger, lingers and drifts up after the fire is gone.
	_puff_layer(parent, at + Vector3.UP * radius * 0.3, 26, radius * 0.62, 2.8,
		radius * 0.12, radius * 0.42, 1.4,
		_ramp([Color(0.35, 0.32, 0.30, 0.0), Color(0.22, 0.20, 0.19, 0.75),
			Color(0.16, 0.15, 0.14, 0.45), Color(0.12, 0.11, 0.10, 0.0)]), false, 180.0, 2.6)

	# 5. Sparks: small, fast, thrown wide, falling under gravity.
	_puff_layer(parent, at, 34, radius * 0.05, 1.1, radius * 2.6, radius * 4.4, -26.0,
		_ramp([Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.6, 0.2, 1.0), Color(0.8, 0.25, 0.05, 0.0)]),
		true, 180.0, 0.5)

	# 6. Ground shockwave: a thin ring racing outward and fading.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	var ring_mat := unshaded(Color(1.0, 0.8, 0.5), 0.7)
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = at + Vector3.UP * 0.25
	ring.scale = Vector3(radius * 0.25, radius * 0.06, radius * 0.25)
	var rt := ring.create_tween()
	rt.tween_property(ring, "scale", Vector3(radius * 1.5, radius * 0.05, radius * 1.5), 0.42).set_ease(Tween.EASE_OUT)
	rt.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.42)
	rt.tween_callback(ring.queue_free)

	# 7. Debris: lit chunks, so they sit in the scene's lighting rather than glowing flat.
	var chunks := CPUParticles3D.new()
	chunks.one_shot = true
	chunks.explosiveness = 1.0
	chunks.amount = 26
	chunks.lifetime = 1.6
	chunks.direction = Vector3.UP
	chunks.spread = 170.0
	chunks.initial_velocity_min = radius * 1.4
	chunks.initial_velocity_max = radius * 3.0
	chunks.gravity = Vector3(0.0, -32.0, 0.0)
	chunks.angular_velocity_min = -720.0
	chunks.angular_velocity_max = 720.0
	chunks.scale_amount_min = 0.5
	chunks.scale_amount_max = 1.3
	var box := BoxMesh.new()
	box.size = Vector3(0.18, 0.18, 0.18)
	var debris_mat := StandardMaterial3D.new()
	debris_mat.albedo_color = Color(0.29, 0.26, 0.24)
	debris_mat.roughness = 0.9
	box.material = debris_mat
	chunks.mesh = box
	parent.add_child(chunks)
	chunks.global_position = at
	var chunk_reach := radius * 3.0 + 40.0
	chunks.custom_aabb = AABB(Vector3.ONE * -chunk_reach, Vector3.ONE * (chunk_reach * 2.0))
	chunks.restart()
	chunks.emitting = true
	var dt := chunks.create_tween()
	dt.tween_interval(chunks.lifetime + 0.2)
	dt.tween_callback(chunks.queue_free)

	# 8. Scorch mark on whatever is under the blast. Decals need a rendering device, so the
	# Compatibility renderer (the web build) quietly skips this.
	if RenderingServer.get_rendering_device() != null:
		var decal := Decal.new()
		decal.texture_albedo = puff_texture()
		decal.modulate = Color(0.05, 0.04, 0.035)
		decal.albedo_mix = 0.85
		decal.size = Vector3(radius * 1.8, 6.0, radius * 1.8)
		decal.upper_fade = 2.0
		decal.lower_fade = 2.0
		parent.add_child(decal)
		decal.global_position = at
		var dect := decal.create_tween()
		dect.tween_interval(14.0)
		dect.tween_property(decal, "modulate:a", 0.0, 4.0)
		dect.tween_callback(decal.queue_free)

	shake(node, at, radius)


## Rattles the player's camera, hard up close and not at all far away.
static func shake(node: Node, at: Vector3, radius: float) -> void:
	var player := node.get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var rig: Node = player.get("camera_rig")
	if rig == null or not rig.has_method("shake"):
		return
	var d := player.global_position.distance_to(at)
	var falloff := clampf(1.0 - d / (radius * 6.0), 0.0, 1.0)
	if falloff > 0.0:
		rig.shake(falloff * falloff)


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
