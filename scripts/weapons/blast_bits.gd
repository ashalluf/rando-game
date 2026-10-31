class_name BlastBits
extends Node3D
## The grit and the sparks a blast throws (Blast3), as things that LAND. They were CPUParticles3D,
## which know nothing of the world: the chips fell through the road and vanished, the sparks fell
## through it still glowing. Here each is a point on a ballistic arc with one world ray a physics
## tick (BrassCasings' and BlastDebris' way): a chip bounces off the road or a wall, skids along
## the ground and lies there flat for `chip_rest` s before it sinks away; a spark skitters - it
## bounces low, keeps most of its speed along the road - and dies on the ground as a red ember.
## ONE node for the scene (under the scene root, so the origin re-centre shifts it with
## everything), two MultiMeshes whose buffers are written whole each frame: every chip of every
## blast is one draw, every spark another. Desktop only; the web keeps the particles.

## Most chips and sparks alive at once (the oldest slot is reused past this).
static var max_chips: int = 240
static var max_sparks: int = 220
## Seconds a chip lies on the ground before it sinks away.
static var chip_rest: float = 25.0
## Share of the speed kept off a bounce (across the surface, along it), and the skid's deceleration.
static var chip_bounce: Vector2 = Vector2(0.28, 0.6)
static var spark_bounce: Vector2 = Vector2(0.32, 0.72)
static var chip_friction: float = 7.0
static var spark_friction: float = 3.0
## Gravity on each.
static var chip_gravity: float = 22.0
static var spark_gravity: float = 14.0

const FREE := 0
const FLY := 1
const SKID := 2
const REST := 3

static var _pool: BlastBits
static var _chip_mesh: Mesh
static var _spark_mat: ShaderMaterial

var _chips: MultiMeshInstance3D
var _sparks: MultiMeshInstance3D
var _cbuf := PackedFloat32Array()
var _sbuf := PackedFloat32Array()

# Chips.
var _cp := PackedVector3Array()
var _cv := PackedVector3Array()
var _cn := PackedVector3Array() # the ground's normal once it skids / rests
var _caxis := PackedVector3Array()
var _cspin := PackedFloat32Array()
var _cang := PackedFloat32Array()
var _csize := PackedVector3Array()
var _ccol := PackedColorArray()
var _cage := PackedFloat32Array()
var _cstate := PackedInt32Array()
var _cnext := 0
# Sparks.
var _sp := PackedVector3Array()
var _sv := PackedVector3Array()
var _sage := PackedFloat32Array()
var _slife := PackedFloat32Array()
var _sheat := PackedFloat32Array()
var _sstate := PackedInt32Array()
var _shits := PackedInt32Array()
var _snext := 0
var _idle_written := false
var _live_chips := 0
var _live_sparks := 0
## Counters the checks read: bounces, chips at rest, sparks that reached the ground.
var stats := {"bounces": 0, "rested": 0, "sparks_landed": 0}


static func pool(node: Node) -> BlastBits:
	if _pool == null or not is_instance_valid(_pool) or not _pool.is_inside_tree():
		_pool = BlastBits.new()
		_pool.name = "BlastBits"
		WeaponFX.fx_parent(node).add_child(_pool)
	return _pool


static func current() -> BlastBits:
	return _pool if _pool != null and is_instance_valid(_pool) and _pool.is_inside_tree() else null


## Chips: `count` thrown from `at` (global) inside a cone of `spread` degrees round `axis`, at
## `speed` (min, max); `size` the chip's length in metres, `color` its base (lit albedo).
func throw_chips(at: Vector3, count: int, speed: Vector2, size: float, color: Color,
		axis: Vector3 = Vector3.UP, spread: float = 75.0, low: bool = false) -> void:
	var local := to_local(at)
	for i in count:
		var k := _cnext
		_cnext = (_cnext + 1) % max_chips
		if _cstate[k] == FREE:
			_live_chips += 1
		var dir := _cone(axis, spread)
		if low:
			# Skimming grit: nearly flat out along the ground.
			dir = Vector3(dir.x, absf(dir.y) * 0.25 + 0.05, dir.z).normalized()
		_cp[k] = local + dir * 0.2
		_cv[k] = dir * randf_range(speed.x, speed.y)
		_cn[k] = Vector3.UP
		_caxis[k] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		_cspin[k] = randf_range(10.0, 32.0)
		_cang[k] = randf() * TAU
		var s := size * randf_range(0.45, 1.35)
		_csize[k] = Vector3(s, s * randf_range(0.35, 0.7), s * randf_range(0.6, 0.95))
		var shade := randf_range(0.7, 1.25)
		_ccol[k] = Color(color.r * shade, color.g * shade, color.b * shade)
		_cage[k] = 0.0
		_cstate[k] = FLY


## Sparks: `count` from `at` thrown out at `speed`, mostly upward and outward.
func throw_sparks(at: Vector3, count: int, speed: Vector2, axis: Vector3 = Vector3.UP, spread: float = 85.0) -> void:
	var local := to_local(at)
	for i in count:
		var k := _snext
		_snext = (_snext + 1) % max_sparks
		if _sstate[k] == FREE:
			_live_sparks += 1
		var dir := _cone(axis, spread)
		_sp[k] = local + dir * 0.3
		_sv[k] = dir * randf_range(speed.x, speed.y)
		_sage[k] = 0.0
		_slife[k] = randf_range(0.7, 1.9)
		_sheat[k] = randf_range(0.75, 1.0)
		_sstate[k] = FLY
		_shits[k] = 0


static func _cone(axis: Vector3, deg: float) -> Vector3:
	var b := WeaponFX._basis_up(axis.normalized())
	var el := deg_to_rad(randf_range(0.0, deg))
	var az := randf() * TAU
	return (b * Vector3(sin(el) * cos(az), cos(el), sin(el) * sin(az))).normalized()


func _ready() -> void:
	for arr in [_cp, _cv, _cn, _caxis, _csize]:
		arr.resize(max_chips)
	_cspin.resize(max_chips)
	_cang.resize(max_chips)
	_ccol.resize(max_chips)
	_cage.resize(max_chips)
	_cstate.resize(max_chips)
	_cstate.fill(FREE)
	for arr in [_sp, _sv]:
		arr.resize(max_sparks)
	_sage.resize(max_sparks)
	_slife.resize(max_sparks)
	_sheat.resize(max_sparks)
	_sstate.resize(max_sparks)
	_sstate.fill(FREE)
	_shits.resize(max_sparks)
	_chips = _make_mm("Chips", chip_mesh(), max_chips, true)
	_chips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = spark_material()
	_sparks = _make_mm("Sparks", quad, max_sparks, true)
	_cbuf.resize(max_chips * 16)
	_cbuf.fill(0.0)
	_sbuf.resize(max_sparks * 16)
	_sbuf.fill(0.0)


func _make_mm(n: String, mesh: Mesh, count: int, colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.name = n
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Spread over wherever the blasts went off; keep them all drawable.
	mi.custom_aabb = AABB(Vector3(-4000.0, -500.0, -4000.0), Vector3(8000.0, 1000.0, 8000.0))
	add_child(mi)
	return mi


## A chip: a lopsided wedge of road or kerb, lit; the instance colour is its albedo.
static func chip_mesh() -> Mesh:
	if _chip_mesh == null:
		var m := PrismMesh.new()
		m.size = Vector3(1.0, 0.6, 0.85)
		m.left_to_right = 0.25
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		m.material = mat
		_chip_mesh = m
	return _chip_mesh


static func spark_material() -> ShaderMaterial:
	if _spark_mat == null:
		_spark_mat = ShaderMaterial.new()
		_spark_mat.shader = preload("res://shaders/blast_spark.gdshader")
	return _spark_mat


func _physics_process(dt: float) -> void:
	if _live_chips <= 0 and _live_sparks <= 0:
		return
	var space := get_world_3d().direct_space_state
	_step_chips(space, dt)
	_step_sparks(space, dt)


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(to_global(from), to_global(to), 1)
	return space.intersect_ray(q)


func _step_chips(space: PhysicsDirectSpaceState3D, dt: float) -> void:
	for k in max_chips:
		var st := _cstate[k]
		if st == FREE:
			continue
		_cage[k] += dt
		if st == FLY:
			var v := _cv[k] + Vector3.DOWN * chip_gravity * dt
			v *= 1.0 - minf(0.4 * dt, 0.5)
			var from := _cp[k]
			var to := from + v * dt
			var hit := _ray(space, from, to)
			if not hit.is_empty():
				var n: Vector3 = hit.normal
				var vn := n * v.dot(n)
				var vt := v - vn
				to = to_local(hit.position) + n * 0.03
				if vn.length() > 2.2:
					v = vt * chip_bounce.y - vn * chip_bounce.x
					_cspin[k] *= 0.6
					stats.bounces += 1
				elif n.y > 0.55:
					v = vt * chip_bounce.y
					_cn[k] = n
					_cstate[k] = SKID
				else:
					v = vt * 0.5 - n * 0.3
			elif _cage[k] > 6.0:
				_cstate[k] = REST
			_cv[k] = v
			_cp[k] = to
			_cang[k] += _cspin[k] * dt
		elif st == SKID:
			var v := _cv[k]
			var sp := v.length()
			var nsp := maxf(sp - chip_friction * dt, 0.0)
			if nsp < 0.15:
				_cstate[k] = REST
				_cage[k] = 0.0
				stats.rested += 1
				continue
			v *= nsp / maxf(sp, 1e-4)
			var to := _cp[k] + v * dt
			# Off an edge (a kerb, a deck): it falls again.
			var down := _ray(space, to + _cn[k] * 0.25, to - _cn[k] * 0.35)
			if down.is_empty():
				_cstate[k] = FLY
			else:
				_cn[k] = down.normal
				to = to_local(down.position) + (down.normal as Vector3) * 0.03
			_cv[k] = v
			_cp[k] = to
			_cang[k] += sp * 2.0 * dt
		elif st == REST:
			if _cage[k] > chip_rest:
				_cstate[k] = FREE
				_live_chips -= 1


func _step_sparks(space: PhysicsDirectSpaceState3D, dt: float) -> void:
	for k in max_sparks:
		var st := _sstate[k]
		if st == FREE:
			continue
		_sage[k] += dt
		if _sage[k] > _slife[k]:
			_sstate[k] = FREE
			_live_sparks -= 1
			continue
		var v := _sv[k]
		if st == FLY:
			v += Vector3.DOWN * spark_gravity * dt
			v *= 1.0 - minf(0.9 * dt, 0.5)
			var from := _sp[k]
			var to := from + v * dt
			var hit := _ray(space, from, to)
			if not hit.is_empty():
				var n: Vector3 = hit.normal
				var vn := n * v.dot(n)
				var vt := v - vn
				to = to_local(hit.position) + n * 0.02
				v = vt * spark_bounce.y - vn * spark_bounce.x
				_shits[k] += 1
				if _shits[k] == 1:
					stats.sparks_landed += 1
				if n.y > 0.55 and (vn.length() < 2.5 or _shits[k] >= 3):
					_sstate[k] = SKID
					v = vt * spark_bounce.y
			_sp[k] = to
		else:
			# Skidding along the road, slowing, then lying there as an ember.
			var sp := v.length()
			var nsp := maxf(sp - spark_friction * dt, 0.0)
			v *= nsp / maxf(sp, 1e-4)
			_sp[k] += v * dt
		_sv[k] = v


func _process(_dt: float) -> void:
	# The smoke's fires (Blast3): pushed while anything of a blast is about.
	Blast3.push_fires(get_tree())
	if _live_chips <= 0 and _live_sparks <= 0 and _idle_written:
		return
	_idle_written = _live_chips <= 0 and _live_sparks <= 0
	_write_chips()
	_write_sparks()


func _write_chips() -> void:
	var b := _cbuf
	for k in max_chips:
		var o := k * 16
		var st := _cstate[k]
		if st == FREE:
			for j in 12:
				b[o + j] = 0.0
			continue
		var s := _csize[k]
		var basis: Basis
		if st == FLY:
			basis = Basis(_caxis[k], _cang[k])
		else:
			# Flat on what it lies on, turned to its own heading.
			basis = WeaponFX._basis_up(_cn[k], _cang[k])
		var sink := 1.0
		if st == REST and _cage[k] > chip_rest - 3.0:
			sink = clampf((chip_rest - _cage[k]) / 3.0, 0.0, 1.0)
		basis = basis * Basis.from_scale(s * sink)
		var p := _cp[k] + (_cn[k] * s.y * 0.3 if st != FLY else Vector3.ZERO)
		b[o] = basis.x.x; b[o + 1] = basis.y.x; b[o + 2] = basis.z.x; b[o + 3] = p.x
		b[o + 4] = basis.x.y; b[o + 5] = basis.y.y; b[o + 6] = basis.z.y; b[o + 7] = p.y
		b[o + 8] = basis.x.z; b[o + 9] = basis.y.z; b[o + 10] = basis.z.z; b[o + 11] = p.z
		var c := _ccol[k]
		b[o + 12] = c.r; b[o + 13] = c.g; b[o + 14] = c.b; b[o + 15] = 1.0
	_chips.multimesh.buffer = b


func _write_sparks() -> void:
	var b := _sbuf
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for k in max_sparks:
		var o := k * 16
		if _sstate[k] == FREE:
			for j in 12:
				b[o + j] = 0.0
			b[o + 15] = 0.0
			continue
		var age := _sage[k] / _slife[k]
		var v := _sv[k]
		var sp := v.length()
		var dir := v / sp if sp > 0.05 else Vector3.RIGHT
		# The streak is how far it moves in about a 1/40 s exposure, never under a few cm.
		var length := clampf(sp * 0.025, 0.04, 0.9)
		var width := 0.012 + 0.01 * (1.0 - age)
		if _sstate[k] == SKID and sp < 0.3:
			# An ember on the road: a short fat glint.
			length = 0.05
			width = 0.03
		var x := dir.cross(Vector3.UP)
		if x.length_squared() < 1e-4:
			x = Vector3.RIGHT
		x = x.normalized() * width
		var y := dir * length
		var z := x.cross(y).normalized()
		var p := _sp[k]
		b[o] = x.x; b[o + 1] = y.x; b[o + 2] = z.x; b[o + 3] = p.x
		b[o + 4] = x.y; b[o + 5] = y.y; b[o + 6] = z.y; b[o + 7] = p.y
		b[o + 8] = x.z; b[o + 9] = y.z; b[o + 10] = z.z; b[o + 11] = p.z
		# Temperature: white-yellow in flight, orange, then dull red on the ground.
		var h := _sheat[k] * (1.0 - age * 0.85)
		var c: Color
		if h > 0.6:
			c = Color(2.6, 1.9, 1.0).lerp(Color(1.9, 0.85, 0.2), (1.0 - h) / 0.4)
		else:
			c = Color(1.9, 0.85, 0.2).lerp(Color(0.6, 0.08, 0.01), clampf((0.6 - h) / 0.5, 0.0, 1.0))
		b[o + 12] = c.r; b[o + 13] = c.g; b[o + 14] = c.b
		b[o + 15] = clampf((1.0 - age) * 3.0, 0.0, 1.0)
	_sparks.multimesh.buffer = b
	if cam == null:
		return


func chips_alive() -> int:
	return _live_chips


func sparks_alive() -> int:
	return _live_sparks


## Chips lying still on the ground (the checks read it).
func chips_resting() -> int:
	var n := 0
	for k in max_chips:
		if _cstate[k] == REST:
			n += 1
	return n
