class_name PropShards
extends Node3D
## Small bits a broken street prop throws (PropBreak): a bus shelter's tempered glass bursting into
## cubes, the letters out of a mailbox, the papers out of a news box, the coins out of a parking
## meter. ONE MultiMesh for the lot, simulated in GDScript like the rifle's brass (BrassCasings): a
## gravity arc with drag, a ground plane at the pavement the prop stood on, bounces, then resting.
## Paper flutters (strong drag, a sway, a tumble) and lands flat; glass and coins skitter and lie.
## What lands stays on the pavement for `linger` seconds, then shrinks away. Never a rigid body
## each: a shelter is a few hundred cubes.

enum Kind { GLASS, LETTER, NEWSPAPER, COIN }

## How many shard nodes may be in the scene at once (the oldest goes first).
const MAX_NODES := 10
## Seconds the pieces lie on the pavement before they shrink away, per kind.
const LINGER := {Kind.GLASS: 150.0, Kind.LETTER: 110.0, Kind.NEWSPAPER: 110.0, Kind.COIN: 90.0}

static var _live: Array = []

var kind: Kind = Kind.GLASS
## Ground height (this node's space) the pieces land on.
var ground_y: float = 0.0

var _mm: MultiMesh
var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _spin: PackedVector3Array
var _rot: Array[Basis] = []
var _rest: PackedByteArray
var _size: PackedFloat32Array
var _phase: PackedFloat32Array
var _age: float = 0.0
var _all_rest_at: float = -1.0


## Throws `count` pieces of `kind` from points in `box` (an AABB in `frame`'s space, the frame in
## `parent`'s), along `push` (scene, m/s) plus a random spread, landing on `ground_y` (scene y).
static func burst(parent: Node3D, kind: Kind, frame: Transform3D, box: AABB, count: int, push: Vector3,
		spread: float, up: Vector2, ground_y: float, seed_value: int) -> PropShards:
	if parent == null or not parent.is_inside_tree() or count <= 0:
		return null
	_prune()
	while _live.size() >= MAX_NODES:
		var old: Node = _live.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var s := PropShards.new()
	s.name = "PropShards"
	s.kind = kind
	parent.add_child(s)
	s.global_transform = Transform3D(Basis(), parent.global_transform * frame.origin)
	s.ground_y = ground_y - s.global_position.y
	s._throw(frame, box, count, push, spread, up, seed_value)
	_live.append(s)
	return s


static func _prune() -> void:
	var keep: Array = []
	for n in _live:
		if is_instance_valid(n):
			keep.append(n)
	_live = keep


func _throw(frame: Transform3D, box: AABB, count: int, push: Vector3, spread: float, up: Vector2, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var parent_basis := (get_parent() as Node3D).global_basis
	var local_frame := Transform3D(parent_basis * frame.basis, Vector3.ZERO)
	_pos.resize(count)
	_vel.resize(count)
	_spin.resize(count)
	_rest.resize(count)
	_size.resize(count)
	_phase.resize(count)
	_rot.resize(count)
	var colors := PackedColorArray()
	colors.resize(count)
	for i in count:
		var p := box.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * box.size
		_pos[i] = local_frame * p
		var out := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * spread
		_vel[i] = push * rng.randf_range(0.5, 1.2) + out + Vector3(0.0, rng.randf_range(up.x, up.y), 0.0)
		_spin[i] = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * (22.0 if kind == Kind.GLASS or kind == Kind.COIN else 7.0)
		_rot[i] = Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		_rest[i] = 0
		_phase[i] = rng.randf() * TAU
		match kind:
			Kind.GLASS:
				# Mostly single cubes, some still stuck together in clumps of a few centimetres.
				_size[i] = rng.randf_range(0.7, 1.5) if rng.randf() < 0.75 else rng.randf_range(2.0, 4.2)
				var g := rng.randf_range(0.85, 1.0)
				colors[i] = Color(g * 0.86, g * 0.97, g * 0.93)
			Kind.COIN:
				_size[i] = rng.randf_range(0.8, 1.15)
				colors[i] = Color(0.78, 0.6, 0.32) if rng.randf() < 0.3 else Color(0.74, 0.74, 0.76)
			Kind.LETTER:
				_size[i] = rng.randf_range(0.8, 1.2)
				var t := rng.randf()
				colors[i] = Color(0.96, 0.95, 0.9) if t < 0.6 else (Color(0.86, 0.76, 0.56) if t < 0.85 else Color(0.82, 0.88, 0.96))
			_:
				_size[i] = rng.randf_range(0.85, 1.15)
				var w := rng.randf_range(0.86, 1.0)
				colors[i] = Color(w, w, w * 0.97)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = _mesh(kind)
	_mm.instance_count = count
	for i in count:
		_mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mmi.visibility_range_end = 90.0
	add_child(mmi)
	_write()


func _physics_process(delta: float) -> void:
	_age += delta
	var n := _pos.size()
	if n == 0:
		return
	var moving := 0
	var paper := kind == Kind.LETTER or kind == Kind.NEWSPAPER
	for i in n:
		if _rest[i] != 0:
			continue
		moving += 1
		var v := _vel[i]
		if paper:
			# Paper: drag toward a slow fall, a sway on its own phase, tumbling that slows.
			v.y -= 9.8 * delta
			v *= exp(-3.2 * delta)
			v.y = maxf(v.y, -1.15)
			var sway := sin(_age * 3.1 + _phase[i]) * 1.4
			v.x += cos(_phase[i]) * sway * delta * 6.0
			v.z += sin(_phase[i]) * sway * delta * 6.0
		else:
			v.y -= 9.8 * delta
			v *= exp(-0.15 * delta)
		var p := _pos[i] + v * delta
		_rot[i] = _rot[i].rotated(_spin[i].normalized(), _spin[i].length() * delta) if _spin[i].length_squared() > 1e-6 else _rot[i]
		if p.y <= ground_y:
			p.y = ground_y
			if paper or absf(v.y) < 1.2:
				_rest[i] = 1
				v = Vector3.ZERO
				# Lying down: flat on the pavement, keeping only its turn about the vertical.
				var fwd := _rot[i].x
				fwd.y = 0.0
				var yaw := atan2(fwd.z, fwd.x) if fwd.length_squared() > 1e-6 else _phase[i]
				_rot[i] = Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, -PI * 0.5 if paper else 0.0)
				if kind == Kind.COIN:
					_rot[i] = Basis(Vector3.UP, _phase[i])
			else:
				v = Vector3(v.x * 0.45, -v.y * 0.28, v.z * 0.45)
				_spin[i] *= 0.5
		_pos[i] = p
		_vel[i] = v
	var linger: float = LINGER.get(kind, 120.0)
	if moving == 0 and _all_rest_at < 0.0:
		_all_rest_at = _age
		_write()
		return
	if _all_rest_at >= 0.0:
		var over := _age - _all_rest_at - linger
		if over < 0.0:
			return
		var t := clampf(over / 4.0, 0.0, 1.0)
		if t >= 1.0:
			queue_free()
			return
		_write(1.0 - t)
		return
	_write()


func _write(scale_all: float = 1.0) -> void:
	for i in _pos.size():
		var b := _rot[i].scaled(Vector3.ONE * _size[i] * scale_all)
		_mm.set_instance_transform(i, Transform3D(b, _pos[i] + Vector3(0.0, 0.004 * scale_all, 0.0)))


func resting() -> int:
	var c := 0
	for r in _rest:
		c += int(r != 0)
	return c


func count() -> int:
	return _pos.size()


# --- Meshes and materials (built once) -------------------------------------------------------

static var _meshes: Dictionary = {}


static func _mesh(k: Kind) -> Mesh:
	if _meshes.has(k):
		return _meshes[k]
	var m: Mesh
	match k:
		Kind.GLASS:
			# Tempered glass breaks into blunt little cubes about a centimetre and a half across.
			var b := BoxMesh.new()
			b.size = Vector3(0.016, 0.011, 0.014)
			b.material = _glass_material()
			m = b
		Kind.COIN:
			var c := CylinderMesh.new()
			c.top_radius = 0.011
			c.bottom_radius = 0.011
			c.height = 0.0025
			c.radial_segments = 10
			c.rings = 1
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.metallic = 0.85
			mat.roughness = 0.35
			c.material = mat
			m = c
		Kind.LETTER:
			var q := QuadMesh.new()
			q.size = Vector2(0.235, 0.11)
			q.material = _paper_material(false)
			m = q
		_:
			var q := QuadMesh.new()
			q.size = Vector2(0.26, 0.32)
			q.material = _paper_material(true)
			m = q
	_meshes[k] = m
	return m


static func _glass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# Green-edged safety glass: dark body, all its look in the sparkle off the faces.
	mat.albedo_color = Color(0.62, 0.74, 0.7)
	mat.metallic = 0.15
	mat.roughness = 0.12
	mat.metallic_specular = 1.0
	mat.rim_enabled = true
	mat.rim = 0.8
	mat.rim_tint = 0.2
	return mat


static func _paper_material(newsprint: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _paper_texture(newsprint)
	mat.roughness = 0.92
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## A sheet drawn in code: an envelope (stamp, postmark, address lines) or a folded page of
## newsprint (masthead bar, a photo block, columns of grey text). Original, no lettering.
static func _paper_texture(newsprint: bool) -> Texture2D:
	var w := 128
	var h := 64 if not newsprint else 160
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 1, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 if newsprint else 41
	if newsprint:
		img.fill(Color(0.9, 0.89, 0.86))
		img.fill_rect(Rect2i(8, 8, w - 16, 14), Color(0.16, 0.16, 0.17))
		img.fill_rect(Rect2i(8, 28, 64, 44), Color(0.45, 0.44, 0.42))
		var col_w := (w - 16 - 8) / 3
		for c in 3:
			var x0 := 8 + c * (col_w + 4)
			var y := 80 if c < 2 else 28
			while y < h - 8:
				var run := col_w - (rng.randi_range(0, 8) if rng.randf() < 0.2 else 0)
				img.fill_rect(Rect2i(x0, y, run, 2), Color(0.5, 0.5, 0.5))
				y += 5
	else:
		img.fill_rect(Rect2i(w - 22, 6, 14, 17), Color(0.75, 0.2, 0.18))
		img.fill_rect(Rect2i(w - 20, 8, 10, 13), Color(0.3, 0.45, 0.7))
		for k in 3:
			img.fill_rect(Rect2i(w - 44 + k, 10 + k * 3, 16, 1), Color(0.4, 0.4, 0.42))
		for l in 3:
			img.fill_rect(Rect2i(44, 30 + l * 7, 40 - l * 6, 2), Color(0.3, 0.3, 0.35))
		img.fill_rect(Rect2i(6, 8, 28, 2), Color(0.45, 0.45, 0.48))
		img.fill_rect(Rect2i(6, 12, 22, 2), Color(0.45, 0.45, 0.48))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
