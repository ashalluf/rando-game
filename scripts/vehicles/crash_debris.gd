class_name CrashDebris
extends Node3D
## The bigger pieces a crash knocks off a car and leaves on the road (wave 4, car-crash-3): chunks
## of bumper plastic, a grille's slats, a mirror housing in the car's paint, a strip of trim, a
## shard of bent wing. CrashLitter's shards are the centimetre glitter; these are the 10-45 cm
## pieces a player sees from the car and that make a junction read as "something happened here".
## ONE MultiMesh for the whole level (one draw, no shadow), a ring of CAPACITY pieces:
## each is thrown off the car with its velocity plus a kick, flies a ballistic arc simulated here
## (one ground ray a piece a tick while it flies, at most MAX_FLYING at once), bounces once or
## twice, slides to rest and then STAYS - the ring reuses the oldest piece only once it is full.
## Made by the first crash (ensure()) as a child of the level root (its Node3D children ride the
## origin shifts). `CRASH_BREAKUP=0` makes none.

enum Kind { BUMPER, GRILLE, MIRROR, TRIM, PANEL, HUBCAP }

const CAPACITY := 220
const WEB_CAPACITY := 90
const MAX_FLYING := 64

static var _inst: CrashDebris = null

var _mm: MultiMesh
var _next: int = 0
## [index, pos (local), vel, basis, spin axis, spin rate, scale, bounces, age]
var _flying: Array = []
## Pieces thrown so far (tests), and how many are lying still now.
var thrown: int = 0
var resting: int = 0


static func ensure(from: Node) -> CrashDebris:
	if _inst != null and is_instance_valid(_inst) and _inst.is_inside_tree():
		return _inst
	if from == null or not from.is_inside_tree():
		return null
	var tree := from.get_tree()
	var host: Node = from
	while host.get_parent() != null and host.get_parent() != tree.root:
		host = host.get_parent()
	if not (host is Node3D):
		return null
	_inst = CrashDebris.new()
	_inst.name = "CrashDebris"
	host.add_child(_inst)
	return _inst


static func instance() -> CrashDebris:
	return _inst if _inst != null and is_instance_valid(_inst) and _inst.is_inside_tree() else null


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = _chunk_mesh()
	_mm.instance_count = WEB_CAPACITY if OS.has_feature("web") else CAPACITY
	_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = "Pieces"
	mi.multimesh = _mm
	# Flat on the road: a shadow would be four more draws (the cascades) for the whole level, always.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _material()
	mi.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
	add_child(mi)
	set_physics_process(false)


## Throws `count` pieces of `kind` off world point `at` with the car's velocity `travel` plus a
## kick of up to `kick` m/s outward along `out` (unit). `paint` colours MIRROR / PANEL pieces.
static func throw_off(from: Node, at: Vector3, travel: Vector3, out: Vector3, kick: float, kind: int, count: int,
		paint: Color = Color.WHITE) -> int:
	if count <= 0 or not CrashBreakup.enabled:
		return 0
	var inst := ensure(from)
	if inst == null:
		return 0
	return inst._throw(at, travel, out, kick, kind, count, paint)


func _throw(at: Vector3, travel: Vector3, out: Vector3, kick: float, kind: int, count: int, paint: Color) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(at.x * 23.0), int(at.z * 23.0), thrown])
	var cap := _mm.instance_count
	var n := 0
	for i in count:
		if _flying.size() >= MAX_FLYING:
			break
		var idx := _next
		_next = (_next + 1) % cap
		# A piece still flying in that slot: forget it.
		for k in range(_flying.size() - 1, -1, -1):
			if int(_flying[k][0]) == idx:
				_flying.remove_at(k)
		var dir := (out + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.2, 0.9), rng.randf_range(-0.6, 0.6))).normalized()
		var v := travel * rng.randf_range(0.55, 0.95) + dir * kick * rng.randf_range(0.35, 1.0)
		var s := _size(kind, rng)
		var b := Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf() * TAU)
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var p := to_local(at + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.05, 0.15), rng.randf_range(-0.2, 0.2)))
		_flying.append([idx, p, v, b, axis, rng.randf_range(6.0, 22.0), s, 0, 0.0])
		_mm.set_instance_color(idx, _color(kind, rng, paint))
		_mm.set_instance_transform(idx, Transform3D(b.scaled(s), p))
		thrown += 1
		n += 1
	_mm.visible_instance_count = mini(thrown, cap)
	if not _flying.is_empty():
		set_physics_process(true)
	return n


func _physics_process(delta: float) -> void:
	if _flying.is_empty():
		set_physics_process(false)
		return
	var space := get_world_3d().direct_space_state
	var g := Vector3(0.0, -9.8, 0.0)
	for k in range(_flying.size() - 1, -1, -1):
		var f: Array = _flying[k]
		var p: Vector3 = f[1]
		var v: Vector3 = f[2]
		var b: Basis = f[3]
		f[8] = float(f[8]) + delta
		v += g * delta
		var np := p + v * delta
		var gp := to_global(p)
		var gnp := to_global(np)
		var q := PhysicsRayQueryParameters3D.create(gp + Vector3.UP * 0.05, gnp + Vector3.DOWN * 0.04, 1)
		var hit := space.intersect_ray(q)
		var landed := false
		if not hit.is_empty():
			var hn: Vector3 = hit.normal
			np = to_local((hit.position as Vector3) + hn * 0.015)
			var vn := v.dot(hn)
			if vn < 0.0:
				v -= hn * vn * 1.4
			v *= 0.45
			f[5] = float(f[5]) * 0.5
			f[7] = int(f[7]) + 1
			if v.length() < 1.2 or int(f[7]) > 3:
				landed = true
				# Lying flat on what it landed on, at its own turn about the normal.
				var up := hn
				var fwd := (b.z - up * b.z.dot(up))
				if fwd.length() < 0.1:
					fwd = up.cross(Vector3.RIGHT)
				fwd = fwd.normalized()
				b = Basis(up.cross(fwd).normalized(), up, fwd).orthonormalized()
				b = b * Basis(Vector3.FORWARD, randf_range(-0.12, 0.12))
		if not landed:
			b = Basis((f[4] as Vector3), float(f[5]) * delta) * b
			b = b.orthonormalized()
		f[1] = np
		f[2] = v
		f[3] = b
		var s: Vector3 = f[6]
		_mm.set_instance_transform(int(f[0]), Transform3D(b.scaled(s), np))
		if landed or float(f[8]) > 6.0:
			_flying.remove_at(k)
			resting += 1


static func _size(kind: int, rng: RandomNumberGenerator) -> Vector3:
	match kind:
		Kind.BUMPER:
			return Vector3(rng.randf_range(1.2, 3.2), rng.randf_range(0.6, 1.2), rng.randf_range(0.8, 1.6))
		Kind.GRILLE:
			return Vector3(rng.randf_range(1.4, 2.6), 0.4, rng.randf_range(0.6, 1.0))
		Kind.MIRROR:
			return Vector3(1.3, 1.6, 1.1)
		Kind.TRIM:
			return Vector3(rng.randf_range(2.5, 4.5), 0.3, 0.35)
		Kind.HUBCAP:
			return Vector3(2.4, 0.5, 2.4)
		_:
			return Vector3(rng.randf_range(1.2, 2.6), 0.25, rng.randf_range(1.0, 2.0))


static func _color(kind: int, rng: RandomNumberGenerator, paint: Color) -> Color:
	var v := rng.randf_range(0.85, 1.15)
	match kind:
		Kind.BUMPER:
			return Color(0.03 * v, 0.03 * v, 0.032 * v)
		Kind.GRILLE:
			return Color(0.02 * v, 0.02 * v, 0.022 * v)
		Kind.TRIM:
			return Color(0.55 * v, 0.56 * v, 0.58 * v) if rng.randf() < 0.4 else Color(0.03, 0.03, 0.03)
		Kind.HUBCAP:
			return Color(0.5 * v, 0.51 * v, 0.53 * v)
		_:
			return Color(paint.r * v, paint.g * v, paint.b * v)


## A jagged slab about 10 x 4 x 7 cm before its scale: a broken-off piece, bent across its middle,
## its outline torn, a few millimetres of edge to catch the light. Front faces clockwise.
static func _chunk_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7731
	var ring: Array[Vector3] = []
	var nseg := 9
	for k in nseg:
		var a := TAU * float(k) / float(nseg)
		var r := rng.randf_range(0.65, 1.0)
		var x := cos(a) * 0.05 * r
		var z := sin(a) * 0.035 * r
		# Bent: the ends lift a little, like a strip of plastic folded by the hit.
		var y := 0.010 * absf(x) / 0.05 + rng.randf_range(-0.002, 0.002)
		ring.append(Vector3(x, y, z))
	var h := 0.006
	var c := Vector3(0.0, 0.0, 0.0)
	for k in nseg:
		var a: Vector3 = ring[k]
		var bq: Vector3 = ring[(k + 1) % nseg]
		var up := Vector3(0.0, h, 0.0)
		# Top (clockwise from above), bottom, the torn edge.
		st.set_normal(Vector3.UP)
		st.add_vertex(c + up)
		st.add_vertex(bq + up)
		st.add_vertex(a + up)
		st.set_normal(Vector3.DOWN)
		st.add_vertex(c)
		st.add_vertex(a)
		st.add_vertex(bq)
		var en := Vector3(a.x + bq.x, 0.0, a.z + bq.z).normalized()
		st.set_normal(en)
		st.add_vertex(a + up)
		st.add_vertex(bq + up)
		st.add_vertex(bq)
		st.add_vertex(a + up)
		st.add_vertex(bq)
		st.add_vertex(a)
	return st.commit()


static var _mat: StandardMaterial3D


static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.45
		_mat.metallic_specular = 0.6
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat


## Frees the pieces (a test cleaning up after itself).
func clear() -> void:
	thrown = 0
	resting = 0
	_next = 0
	_flying.clear()
	if _mm != null:
		_mm.visible_instance_count = 0
	set_physics_process(false)
