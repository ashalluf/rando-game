class_name SwimFX
extends RefCounted
## What swimming looks and sounds like (Swim, scripts/player/swim.gd): the splash of going in
## (droplets thrown up in a crown, a burst of white mist, a ring of foam spreading on the
## surface), a hand's splash at each stroke, the wake (foam laid on the water behind the swimmer,
## a rooster tail of spray at boost speed), bubbles under water, and the view from under the
## surface (a tint that eats red first, darker with depth, the screen wobbling, and the underside of
## the surface overhead: the bright window of sky straight up, mirror-dark past the critical angle).
## Built in code; the sounds are synthesized here (noise bursts and bubble chirps), since no CC0
## water recording is in the project and the sources are out of this build's reach.

const DROP_COLOR := Color(0.86, 0.92, 0.96, 0.85)
const FOAM_COLOR := Color(0.92, 0.95, 0.97, 0.9)
const MIX_RATE := 22050

static var _dot: Texture2D
static var _foam: Texture2D
static var _ring: Texture2D
static var _drop_mat: StandardMaterial3D
static var _mist_mat: StandardMaterial3D
static var _foam_mat: StandardMaterial3D
static var _bubble_mat: StandardMaterial3D
static var _sounds := {}


# --- textures and materials ---------------------------------------------------------------------

static func dot_texture() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.85))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 32
		t.height = 32
		_dot = t
	return _dot


## Foam: a lace of bubbles, a disc broken up by noise (a smooth disc reads as paint).
static func foam_texture() -> Texture2D:
	if _foam == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.frequency = 0.09
		noise.fractal_octaves = 3
		for y in n:
			for x in n:
				var d := Vector2(x - n * 0.5, y - n * 0.5).length() / (n * 0.5)
				var v := noise.get_noise_2d(x, y) * 0.5 + 0.5
				var a := clampf((v - 0.38) * 3.0, 0.0, 1.0) * (1.0 - smoothstep(0.55, 1.0, d))
				img.set_pixel(x, y, Color(1, 1, 1, a))
		img.generate_mipmaps()
		_foam = ImageTexture.create_from_image(img)
	return _foam


## The ring of foam a splash leaves: a broken ring.
static func ring_texture() -> Texture2D:
	if _ring == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var noise := FastNoiseLite.new()
		noise.seed = 11
		noise.frequency = 0.12
		for y in n:
			for x in n:
				var d := Vector2(x - n * 0.5, y - n * 0.5).length() / (n * 0.5)
				var band := exp(-pow((d - 0.78) / 0.12, 2.0)) + 0.35 * (1.0 - smoothstep(0.0, 0.75, d))
				var v := noise.get_noise_2d(x, y) * 0.5 + 0.5
				img.set_pixel(x, y, Color(1, 1, 1, clampf(band * (v * 1.6 - 0.2), 0.0, 1.0) * (1.0 - smoothstep(0.92, 1.0, d))))
		img.generate_mipmaps()
		_ring = ImageTexture.create_from_image(img)
	return _ring


static func drop_material() -> StandardMaterial3D:
	if _drop_mat == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = dot_texture()
		m.roughness = 0.15
		m.metallic_specular = 0.8
		_drop_mat = m
	return _drop_mat


static func mist_material() -> StandardMaterial3D:
	if _mist_mat == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = WeaponFX.puff_texture()
		m.roughness = 1.0
		m.render_priority = -1
		_mist_mat = m
	return _mist_mat


## Flat foam on the surface: lit, see-through, no shadow.
static func foam_material() -> StandardMaterial3D:
	if _foam_mat == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = foam_texture()
		m.roughness = 0.6
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_foam_mat = m
	return _foam_mat


static func bubble_material() -> StandardMaterial3D:
	if _bubble_mat == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = ring_texture()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bubble_mat = m
	return _bubble_mat


static func _quad(size: float, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return q


static func _flat(size: float, mat: Material) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = Vector2(size, size)
	p.material = mat
	return p


static func _fade_ramp(a0: float, c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c.r, c.g, c.b, a0))
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	return g


static func _grow(from: float, to: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(from, to) + 0.01
	c.add_point(Vector2(0.0, from))
	c.add_point(Vector2(1.0, to))
	return c


# --- one-shots -----------------------------------------------------------------------------------

## A body going into (or bursting out of) the water at `at` (scene position on the surface):
## `strength` 0.3 a step in, 1 a dive, 3 a fall from a tower.
static func splash(parent: Node, at: Vector3, strength: float, up: Vector3 = Vector3.UP) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var s := clampf(strength, 0.2, 3.5)
	var root := Node3D.new()
	root.name = "SwimSplash"
	parent.add_child(root)
	root.global_position = at
	var drops := CPUParticles3D.new()
	drops.one_shot = true
	drops.explosiveness = 0.85
	drops.amount = int(50 + 60 * s)
	drops.lifetime = 0.9 + 0.35 * s
	drops.mesh = _quad(0.09, drop_material())
	drops.direction = up
	drops.spread = 26.0 + 10.0 * s
	drops.initial_velocity_min = 2.0 + 1.5 * s
	drops.initial_velocity_max = 4.5 + 3.4 * s
	drops.gravity = Vector3(0, -9.8, 0)
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	drops.emission_ring_axis = Vector3.UP
	drops.emission_ring_radius = 0.35 + 0.2 * s
	drops.emission_ring_inner_radius = 0.1
	drops.emission_ring_height = 0.05
	drops.scale_amount_min = 0.6
	drops.scale_amount_max = 1.8 + 0.4 * s
	drops.scale_amount_curve = _grow(1.0, 0.4)
	drops.color_ramp = _fade_ramp(DROP_COLOR.a, DROP_COLOR)
	drops.local_coords = false
	root.add_child(drops)
	var mist := CPUParticles3D.new()
	mist.one_shot = true
	mist.explosiveness = 0.9
	mist.amount = int(10 + 10 * s)
	mist.lifetime = 1.3 + 0.4 * s
	mist.mesh = _quad(1.0, mist_material())
	mist.direction = up
	mist.spread = 40.0
	mist.initial_velocity_min = 1.0 * s
	mist.initial_velocity_max = 3.0 * s
	mist.damping_min = 2.0
	mist.damping_max = 4.0
	mist.gravity = Vector3(0, -1.5, 0)
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = 0.4
	mist.scale_amount_min = 0.5 + 0.3 * s
	mist.scale_amount_max = 1.0 + 0.6 * s
	mist.scale_amount_curve = _grow(0.6, 1.6)
	mist.color_ramp = _fade_ramp(0.55, Color(0.95, 0.97, 1.0))
	mist.local_coords = false
	root.add_child(mist)
	var ring := MeshInstance3D.new()
	ring.mesh = _flat(1.0, foam_material())
	ring.material_override = _ring_material()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0, 0.03, 0)
	ring.scale = Vector3.ONE * (1.0 + 0.5 * s)
	root.add_child(ring)
	drops.emitting = true
	mist.emitting = true
	var life := 3.2 + 0.4 * s
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * (3.5 + 2.5 * s), life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "transparency", 1.0, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(root.queue_free)
	play(parent, "splash" if s >= 0.6 else "splash_small", at, linear_to_db(clampf(0.35 + 0.3 * s, 0.2, 1.0)))


static var _ring_mat: StandardMaterial3D


static func _ring_material() -> StandardMaterial3D:
	if _ring_mat == null:
		_ring_mat = foam_material().duplicate()
		_ring_mat.albedo_texture = ring_texture()
		_ring_mat.albedo_color = FOAM_COLOR
		_ring_mat.vertex_color_use_as_albedo = false
	return _ring_mat


## A hand going in on the stroke: a small crown and a slap.
static func stroke(parent: Node, at: Vector3, strength: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var drops := CPUParticles3D.new()
	drops.one_shot = true
	drops.explosiveness = 0.9
	drops.amount = int(14 + 18 * strength)
	drops.lifetime = 0.7
	drops.mesh = _quad(0.06, drop_material())
	drops.direction = Vector3.UP
	drops.spread = 40.0
	drops.initial_velocity_min = 0.8 + strength
	drops.initial_velocity_max = 2.0 + 2.2 * strength
	drops.gravity = Vector3(0, -9.8, 0)
	drops.scale_amount_min = 0.6
	drops.scale_amount_max = 1.6
	drops.color_ramp = _fade_ramp(0.8, DROP_COLOR)
	drops.local_coords = false
	parent.add_child(drops)
	drops.global_position = at
	drops.emitting = true
	drops.finished.connect(drops.queue_free)
	play(parent, "stroke", at, linear_to_db(0.25 + 0.2 * strength))


# --- sound ---------------------------------------------------------------------------------------

## Plays one of the synthesized water sounds at a scene position.
static func play(parent: Node, sound: String, at: Vector3, volume_db: float = 0.0, pitch: float = -1.0) -> void:
	if parent == null or not parent.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = sound_stream(sound)
	p.volume_db = volume_db
	p.pitch_scale = pitch if pitch > 0.0 else randf_range(0.88, 1.12)
	p.unit_size = 6.0
	p.max_distance = 90.0
	if AudioServer.get_bus_index("World") >= 0:
		p.bus = "World"
	parent.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()


## The synthesized sounds, made once: splash, splash_small, stroke, under (a loop).
static func sound_stream(sound: String) -> AudioStreamWAV:
	if _sounds.has(sound):
		return _sounds[sound]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sound)
	var data := PackedFloat32Array()
	match sound:
		"splash":
			data = _splash_pcm(rng, 1.3, 0.75, 6)
		"splash_small":
			data = _splash_pcm(rng, 0.7, 0.35, 3)
		"stroke":
			data = _splash_pcm(rng, 0.32, 0.12, 1)
		"under":
			data = _under_pcm(rng, 4.0)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	wav.data = bytes
	if sound == "under":
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = data.size()
	_sounds[sound] = wav
	return wav


## A splash: a burst of filtered noise (the impact and the sheet falling back) with bubble
## chirps under it (a bubble rings at a pitch that rises as it shrinks).
static func _splash_pcm(rng: RandomNumberGenerator, seconds: float, decay: float, bubbles: int) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := minf(t / 0.004, 1.0) * exp(-t / decay)
		# A second, later wash as the thrown water falls back.
		env += 0.45 * exp(-pow((t - decay * 0.9) / (decay * 0.5), 2.0))
		var cutoff := lerpf(0.55, 0.12, clampf(t / seconds, 0.0, 1.0))
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cutoff
		lp2 += (lp - lp2) * 0.5
		out[i] = (lp * 0.7 + (lp - lp2) * 0.6) * env * 0.9
	for b in bubbles:
		var start := rng.randf_range(0.02, seconds * 0.6)
		var f0 := rng.randf_range(260.0, 900.0)
		var len := rng.randf_range(0.04, 0.12)
		var ph := 0.0
		for i in range(int(start * MIX_RATE), mini(n, int((start + len) * MIX_RATE))):
			var u := float(i) / MIX_RATE - start
			var f := f0 * (1.0 + 2.2 * u / len)
			ph += TAU * f / MIX_RATE
			out[i] += sin(ph) * exp(-u / (len * 0.35)) * 0.22
	return out


## The muffled roar under the water: brown noise with slow swells.
static func _under_pcm(rng: RandomNumberGenerator, seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var b := 0.0
	for i in n:
		b = clampf(b + rng.randf_range(-1.0, 1.0) * 0.03, -1.0, 1.0) * 0.998
		var t := float(i) / MIX_RATE
		# Seamless: every swell has a whole number of periods in the loop.
		out[i] = b * (0.7 + 0.3 * sin(TAU * t * 2.0 / seconds))
	# Fade the seam.
	var k := int(0.05 * MIX_RATE)
	for i in k:
		var w := float(i) / k
		out[n - k + i] = lerpf(out[n - k + i], out[i], w)
	return out
