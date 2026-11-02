class_name CrashLitter
extends Node3D
## What a crash leaves on the road: cubes of tempered glass, shards of lamp lens (clear, red,
## amber), black plastic off a bumper and flecks of paint, scattered round where the car was hit
## and thrown on along the way it was going. ONE MultiMesh ring for the whole level (one draw):
## each shard a flat chip of a few centimetres lying on the ground, tilted a little so some of
## them catch the light, its colour in the instance colour; the oldest is reused once the ring is
## full. Made by the first crash (ensure()) as a child of the level root, whose Node3D children
## ride the origin shifts. CrashDeform and CarDamage call scatter(); `CRASH_DEFORM=0` makes none.

enum Kind { GLASS, LENS_CLEAR, LENS_RED, LENS_AMBER, PLASTIC, PAINT }

## Shards kept at once (the web keeps fewer).
const CAPACITY := 900
const WEB_CAPACITY := 360

static var _inst: CrashLitter = null

var _mm: MultiMesh
var _next: int = 0
## Shards laid so far (tests).
var laid: int = 0


static func ensure(from: Node) -> CrashLitter:
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
	_inst = CrashLitter.new()
	_inst.name = "CrashLitter"
	host.add_child(_inst)
	return _inst


static func instance() -> CrashLitter:
	return _inst if _inst != null and is_instance_valid(_inst) and _inst.is_inside_tree() else null


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = _chip_mesh()
	_mm.instance_count = WEB_CAPACITY if OS.has_feature("web") else CAPACITY
	_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = "Shards"
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _material()
	# The shards are all over the level: never culled as a whole.
	mi.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
	mi.visibility_range_end = 0.0
	add_child(mi)


## Scatters `count` shards of `kind` round world point `at` on whatever is under it, thrown on
## along `travel` (the car's velocity, m/s). `paint` is the colour of PAINT flecks.
static func scatter(from: Node, at: Vector3, travel: Vector3, kind: int, count: int, paint: Color = Color.WHITE) -> int:
	if count <= 0 or not CrashDeform.enabled:
		return 0
	var inst := ensure(from)
	if inst == null:
		return 0
	return inst._scatter(at, travel, kind, count, paint)


func _scatter(at: Vector3, travel: Vector3, kind: int, count: int, paint: Color) -> int:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.2, at + Vector3.DOWN * 3.0, 1)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 0
	var ground: Vector3 = hit.position
	var gn: Vector3 = hit.normal
	# A private stream from where it happened: the city's own rolls never move.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(at.x * 37.0), int(at.z * 37.0), laid])
	var flat := Vector3(travel.x, 0.0, travel.z)
	var speed := flat.length()
	var along := flat / speed if speed > 0.3 else Vector3.FORWARD
	var throw := clampf(speed * 0.18, 0.3, 6.0)
	var spread := 0.35 + throw * 0.25
	var n := mini(count, _mm.instance_count)
	var cap := _mm.instance_count
	for i in n:
		# Most of it lands ahead of the car along the way it was going; a ring round the hit.
		var fwd := rng.randf() * throw * (0.4 + rng.randf() * 0.8)
		var side := (rng.randf() + rng.randf() - 1.0) * spread
		var off := along * fwd + along.cross(Vector3.UP) * side + Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
		var p := ground + off
		# Each shard on what is really under it (a kerb, the car's own roof is not the road).
		var q2 := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 1.5, 1)
		var h2 := space.intersect_ray(q2)
		var pn := gn
		if not h2.is_empty():
			p = h2.position
			pn = h2.normal
		p += pn * 0.003
		var up := (pn + Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))).normalized()
		var b := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, rng.randf() * TAU)
		var s := _size(kind, rng)
		b = b.scaled(Vector3(s * rng.randf_range(0.7, 1.3), 1.0, s * rng.randf_range(0.7, 1.3)))
		var xf := Transform3D(b, to_local(p))
		_mm.set_instance_transform(_next, xf)
		_mm.set_instance_color(_next, _color(kind, rng, paint))
		_next = (_next + 1) % cap
		laid += 1
	_mm.visible_instance_count = mini(laid, cap)
	return n


static func _size(kind: int, rng: RandomNumberGenerator) -> float:
	match kind:
		Kind.GLASS:
			# Tempered glass breaks into near-cubes of about a centimetre, now and then a lump.
			return rng.randf_range(0.6, 1.4) * (2.5 if rng.randf() < 0.05 else 1.0)
		Kind.PLASTIC:
			return rng.randf_range(1.5, 6.0)
		Kind.PAINT:
			return rng.randf_range(0.5, 1.6)
		_:
			return rng.randf_range(1.0, 3.6)


static func _color(kind: int, rng: RandomNumberGenerator, paint: Color) -> Color:
	var v := rng.randf_range(0.85, 1.15)
	match kind:
		Kind.GLASS:
			return Color(0.62 * v, 0.70 * v, 0.68 * v)
		Kind.LENS_CLEAR:
			return Color(0.80 * v, 0.82 * v, 0.84 * v)
		Kind.LENS_RED:
			return Color(0.55 * v, 0.03, 0.03)
		Kind.LENS_AMBER:
			return Color(0.80 * v, 0.38 * v, 0.04)
		Kind.PLASTIC:
			return Color(0.035 * v, 0.035 * v, 0.038 * v)
		_:
			return Color(paint.r * v, paint.g * v, paint.b * v)


## A chip of about a centimetre: an irregular hexagon, a millimetre or two thick so its edge
## catches the light.
static func _chip_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array[Vector2] = []
	var radii := [0.0062, 0.0048, 0.0058, 0.0042, 0.0066, 0.0050]
	for k in 6:
		var a := TAU * float(k) / 6.0 + (0.18 if k % 2 == 0 else -0.1)
		ring.append(Vector2(cos(a), sin(a)) * float(radii[k]))
	var h := 0.0018
	for k in 6:
		var a: Vector2 = ring[k]
		var b: Vector2 = ring[(k + 1) % 6]
		# Top (clockwise seen from above: Godot's front faces).
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0.0, h, 0.0))
		st.add_vertex(Vector3(b.x, h, b.y))
		st.add_vertex(Vector3(a.x, h, a.y))
		# The edge.
		var en := Vector3(a.x + b.x, 0.0, a.y + b.y).normalized()
		st.set_normal(en)
		st.add_vertex(Vector3(a.x, h, a.y))
		st.add_vertex(Vector3(b.x, h, b.y))
		st.add_vertex(Vector3(b.x, 0.0, b.y))
		st.add_vertex(Vector3(a.x, h, a.y))
		st.add_vertex(Vector3(b.x, 0.0, b.y))
		st.add_vertex(Vector3(a.x, 0.0, a.y))
	return st.commit()


static var _mat: StandardMaterial3D


static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.12
		_mat.metallic_specular = 0.75
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat


## Frees the shards (a test cleaning up after itself).
func clear() -> void:
	laid = 0
	_next = 0
	if _mm != null:
		_mm.visible_instance_count = 0
