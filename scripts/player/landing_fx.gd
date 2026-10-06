class_name LandingFX
extends RefCounted
## What landing from a superhuman jump does to the ground. A normal jump already comes down at
## about 47 m/s (the fall gravity is 1.6x a 12 m jump's), so the scale runs off how far past that
## the fall was: a little dust from `dust_speed`, a ring of dust racing out along the ground and
## a camera kick that grow with it, and from `slam_speed` (a drop of thirty metres or more) a
## crater of cracks in the road and a shockwave that throws the people, props and loose cars
## round the landing. Static: the player calls land() once per landing.
##
## Tunables, as static vars (like Explosion's): set them from anywhere.

## Fall speed (m/s) from which a landing kicks up any dust at all.
static var dust_speed: float = 22.0
## Fall speed at which the dust ring and the camera kick are at full size.
static var full_speed: float = 85.0
## Fall speed from which the ground cracks and the shockwave throws things.
static var slam_speed: float = 72.0
## Reach of the shockwave (m) at full size, and the speed it throws things at its centre (m/s).
static var slam_radius: float = 7.0
static var slam_launch: float = 11.0

static var _crater_cache: Texture2D


static func land(player: Node3D, at: Vector3, normal: Vector3, fall: float) -> void:
	if player == null or not player.is_inside_tree() or fall < dust_speed:
		return
	CrowdLook.landing(player, fall)
	var k := clampf((fall - 47.0) / (full_speed - 47.0), 0.0, 1.0)
	var parent := WeaponFX.fx_parent(player)
	var up := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	var aim := WeaponFX._basis_up(up)
	var dust := WeaponFX._ramp([Color(0.44, 0.40, 0.35, 0.0), Color(0.40, 0.37, 0.33, 0.5),
		Color(0.33, 0.31, 0.28, 0.28), Color(0.26, 0.25, 0.23, 0.0)])
	# A flat ring racing out along the ground (flatness 1 lays the cone in the surface plane).
	var small := fall < 47.0
	var count := WeaponFX._count(6 if small else int(10.0 + 22.0 * k))
	WeaponFX._puff_layer(parent, at + up * 0.15, count, 0.6 + 1.6 * k, 0.9 + 0.8 * k,
		2.0 + 5.0 * k, 5.0 + 12.0 * k, 0.4, dust, false, 180.0, 2.6 + k, aim, 1.0, 0.35, 1.4, true)
	if not small:
		# A few puffs thrown up out of the middle.
		WeaponFX._puff_layer(parent, at + up * 0.3, WeaponFX._count(int(4.0 + 10.0 * k)), 0.8 + 1.2 * k, 1.1,
			1.5, 4.0 + 5.0 * k, -1.5, dust, false, 30.0, 2.2, aim, 0.0, 0.4, 1.0, true)
	var rig: Node = player.get("camera_rig")
	if rig and rig.has_method("shake"):
		rig.shake((0.05 if small else 0.12) + 0.5 * k * k)
	if fall < 47.0:
		Sfx.play("land", at, -6.0)
		return
	Sfx.play("thud", at, -2.0 + 8.0 * k, lerpf(1.0, 0.7, k))
	if fall < slam_speed:
		return
	var slam := clampf((fall - slam_speed) / maxf(full_speed - slam_speed, 1.0), 0.25, 1.0)
	# Grit and chips flung out of the crater.
	WeaponFX._chip_layer(parent, at + up * 0.1, WeaponFX._count(int(14.0 * slam)), 0.07, 1.2,
		4.0, 9.0 + 6.0 * slam, Color(0.2, 0.19, 0.18), aim, 70.0, -26.0)
	_crater(player, parent, at, up, 1.6 + 1.8 * slam)
	_shockwave(player, at, slam_radius * (0.6 + 0.4 * slam), slam_launch * (0.6 + 0.4 * slam))
	Sfx.play("explosion", at, -12.0 + 4.0 * slam, 1.35)


## The crater: a dark splash of radial cracks on whatever the player landed on (a Decal, so
## Forward+ only; the Compatibility renderer and the web skip it, like the blast scorch).
static func _crater(player: Node3D, parent: Node, at: Vector3, up: Vector3, radius: float) -> void:
	if RenderingServer.get_rendering_device() == null:
		return
	if Sanctuary.contains(player.get_tree(), at, radius):
		return
	var decal := Decal.new()
	decal.texture_albedo = crater_texture()
	decal.modulate = Color(0.1, 0.09, 0.085)
	decal.albedo_mix = 0.9
	decal.size = Vector3(radius * 2.0, 2.0, radius * 2.0)
	decal.upper_fade = 0.5
	decal.lower_fade = 0.5
	parent.add_child(decal)
	decal.global_transform = Transform3D(WeaponFX._basis_up(up).rotated(up, randf() * TAU), at)
	var t := decal.create_tween()
	t.tween_interval(20.0)
	t.tween_property(decal, "modulate:a", 0.0, 4.0)
	t.tween_callback(decal.queue_free)


## Throws what is round the landing outward: people off their feet, props and loose cars.
## The same query an explosion makes, without the fire and without hurting the player.
static func _shockwave(player: Node3D, at: Vector3, radius: float, launch: float) -> void:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), at)
	# Props and people (the player's own layer left out).
	query.collision_mask = (1 << 2) | (1 << 3)
	var results := player.get_world_3d().direct_space_state.intersect_shape(query, 64)
	for result in results:
		var target := result.collider as Node3D
		if target == null or target == player:
			continue
		var offset := target.global_position - at
		var d := offset.length()
		var falloff := clampf(1.0 - d / radius, 0.2, 1.0)
		var dir := (offset + Vector3.UP * radius * 0.5).normalized() if d > 0.05 else Vector3.UP
		if target is Vehicle:
			(target as Vehicle).drop_out_of_traffic(dir * launch * falloff)
			continue
		if target.has_method("knock"):
			target.call("knock", dir * launch * falloff * 1.3)
			continue
		var body := target as RigidBody3D
		if body:
			body.freeze = false
			body.sleeping = false
			body.apply_central_impulse(dir * launch * falloff * body.mass)


## Radial cracks round a crushed centre, ragged and uneven: dark lines on clear, 128 px.
static func crater_texture() -> Texture2D:
	if _crater_cache != null:
		return _crater_cache
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 19
	noise.frequency = 0.09
	for y in size:
		for x in size:
			var u := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var ang := atan2(v, u)
			var n := noise.get_noise_2d(float(x), float(y))
			# Eleven cracks wandering outward, thinning and fading toward the rim.
			var spokes := absf(sin(ang * 5.5 + n * 1.6 + sin(ang * 2.0) * 0.5))
			var crack := pow(clampf(1.0 - spokes * (9.0 + r * 10.0), 0.0, 1.0), 0.7) * (1.0 - smoothstep(0.25, 0.95, r))
			# A broken ring round the centre and the crushed middle itself.
			var ring := clampf(1.0 - absf(r - 0.22 - n * 0.05) * 30.0, 0.0, 1.0) * (0.5 + 0.5 * n) * 0.7
			var hub := (1.0 - smoothstep(0.0, 0.2, r)) * (0.55 + 0.35 * n)
			var a := clampf(crack + ring + hub, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	img.generate_mipmaps()
	_crater_cache = ImageTexture.create_from_image(img)
	return _crater_cache
