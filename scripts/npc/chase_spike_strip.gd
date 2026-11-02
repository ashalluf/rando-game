class_name ChaseSpikeStrip
extends Node3D
## A police spike strip (PoliceChase lays one in front of a roadblock): a scissor lattice of
## hollow steel spikes across the carriageway, thrown out from one kerb when it goes down
## (deploy()). Built in code at real size - a link is two crossed 25 mm bars 0.32 m long with
## four spikes - as ONE MultiMesh of links (one draw), its length along the node's local +X,
## centred on the node.
##
## A tyre that crosses it goes flat (ChaseFlatTyres). Each physics tick it sweeps the wheels of
## the player's car and of any car a 5 Hz box query found on it: a wheel whose hub passed over the
## strip's line since the last tick, inside its length, is punctured. Police cars know where their
## own strips are and are never punctured; kinematic traffic has no wheels (it goes physical first
## if anything hits it). Gone after `life` seconds, or when the Police node clears.

## Across the road (m), set before deploy().
@export var length: float = 6.0
## Depth of the strip front to back (m) and how long it stays down (s).
@export var depth: float = 0.42
@export var life: float = 75.0
## Seconds the strip takes to unfold across the road.
@export var deploy_seconds: float = 0.7

const LINK := 0.32

var police: Police
## Wheels punctured by this strip (the checks read it).
var punctured: int = 0
var _mm: MultiMeshInstance3D
var _age: float = 0.0
var _query_t: float = 0.0
## Vehicles found on or near it: instance id -> Vehicle.
var _watch: Dictionary = {}
## Last strip-space z of each watched wheel, by wheel instance id.
var _last_z: Dictionary = {}

static var _link_mesh: Mesh
static var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("spike_strip")
	_mm = MultiMeshInstance3D.new()
	_mm.name = "Links"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = link_mesh()
	mm.instance_count = maxi(int(ceil(length / LINK)), 2)
	_mm.multimesh = mm
	_mm.material_override = material()
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_mm.visibility_range_end = 140.0
	add_child(_mm)
	_pose(1.0)


## Throws it out across the road (the links unfold from the -X end).
func deploy() -> void:
	_age = 0.0
	_pose(0.0)
	if is_inside_tree():
		Sfx.play("casing", global_position, 4.0, 0.55)


func _pose(u: float) -> void:
	var mm := _mm.multimesh
	var n := mm.instance_count
	var e := 1.0 - pow(1.0 - clampf(u, 0.0, 1.0), 3.0)
	var start := -length * 0.5
	for i in n:
		# Folded, every link stacks at the start; unfolding spreads them to their pitch.
		var x := start + (float(i) + 0.5) * LINK * e
		var fold := lerpf(0.7, 1.0, e)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(fold, 1.0, 1.0)), Vector3(x, 0.0, 0.0)))
	_mm.custom_aabb = AABB(Vector3(-length * 0.5 - 0.5, -0.1, -depth), Vector3(length + 1.0, 0.4, depth * 2.0))


func _physics_process(delta: float) -> void:
	_age += delta
	if _age < deploy_seconds + 0.1:
		_pose(_age / deploy_seconds)
	if _age > life:
		queue_free()
		return
	_query_t -= delta
	if _query_t <= 0.0:
		_query_t = 0.2
		_find_cars()
	if police != null:
		var mine := police.player_vehicle()
		if mine != null:
			_watch[mine.get_instance_id()] = mine
	if _age < deploy_seconds * 0.6:
		return
	var inv := global_transform.affine_inverse()
	for id in _watch.keys():
		var c: Variant = _watch[id]
		if not is_instance_valid(c):
			_watch.erase(id)
			continue
		var car: Vehicle = c
		if car is PoliceCar and (car as PoliceCar).driver == null:
			continue
		var near := false
		for i in car.wheels.size():
			var w := car.wheels[i]
			if not is_instance_valid(w):
				continue
			var lp := inv * w.global_position
			var wid := w.get_instance_id()
			if absf(lp.x) < length * 0.5 + 0.1 and absf(lp.z) < 6.0:
				near = true
			var last: Variant = _last_z.get(wid)
			_last_z[wid] = lp.z
			if last == null or absf(lp.x) > length * 0.5 + 0.1 or lp.y > 1.4:
				continue
			var lz: float = last
			if (lz <= depth * 0.5 and lp.z >= -depth * 0.5 and lz < lp.z) or (lz >= -depth * 0.5 and lp.z <= depth * 0.5 and lz > lp.z) \
					or absf(lp.z) < depth * 0.5:
				if ChaseFlatTyres.puncture(car, i):
					punctured += 1
		if not near and car.global_position.distance_to(global_position) > 14.0:
			_watch.erase(id)


## Physical cars standing on or about to cross the strip, five times a second.
func _find_cars() -> void:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return
	var box := BoxShape3D.new()
	box.size = Vector3(length + 2.0, 2.0, 16.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(global_basis, global_position + Vector3.UP)
	q.collision_mask = 4
	for hit in space.intersect_shape(q, 16):
		var c: Object = hit.collider
		if c is Vehicle and not (c as Vehicle).wheels.is_empty():
			_watch[(c as Vehicle).get_instance_id()] = c


## One link of the lattice: two crossed bars, end caps and four hollow spikes, in a 0.32 m pitch
## along +X. Vertex colours carry the finish (dark polymer, steel, a yellow band on the caps).
static func link_mesh() -> Mesh:
	if _link_mesh != null:
		return _link_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bar := Color(0.05, 0.05, 0.055)
	var steel := Color(0.55, 0.56, 0.58)
	var cap := Color(0.85, 0.62, 0.05)
	var h := 0.42 * 0.5
	# The scissor: two bars corner to corner across the link, a little apart in height.
	_bar(st, Vector3(-LINK * 0.5, 0.022, -h), Vector3(LINK * 0.5, 0.022, h), 0.026, 0.02, bar)
	_bar(st, Vector3(-LINK * 0.5, 0.044, h), Vector3(LINK * 0.5, 0.044, -h), 0.026, 0.02, bar)
	# Pivot blocks at the joints front and back (yellow-banded on every other link reads as one band).
	for z in [-h, h]:
		_box(st, Vector3(-LINK * 0.5, 0.034, z), Vector3(0.05, 0.05, 0.05), cap)
	_box(st, Vector3(0.0, 0.034, 0.0), Vector3(0.04, 0.03, 0.04), bar)
	# Spikes: hollow steel tubes cut on a slant, standing up off the bars.
	for p in [Vector3(-LINK * 0.25, 0.05, -h * 0.5), Vector3(LINK * 0.25, 0.05, h * 0.5),
			Vector3(-LINK * 0.25, 0.06, h * 0.5), Vector3(LINK * 0.25, 0.06, -h * 0.5)]:
		_spike(st, p, 0.006, 0.065, steel)
	st.generate_normals()
	_link_mesh = st.commit()
	return _link_mesh


static func material() -> StandardMaterial3D:
	if _material != null:
		return _material
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.metallic = 0.55
	_material.roughness = 0.42
	return _material


## A bar of square section from a to b.
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3, w: float, t: float, col: Color) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP).normalized() * w * 0.5
	var up := Vector3.UP * t * 0.5
	var p := [a - side - up, a + side - up, a + side + up, a - side + up, b - side - up, b + side - up, b + side + up, b - side + up]
	_hexa(st, p, col)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var p := [c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	# Reordered into _hexa's layout: the four at the -Z end, then the four at +Z.
	_hexa(st, p, col)


## Six quads of an eight-corner solid: p[0..3] one end, p[4..7] the other, in the same order.
## Each face is wound by the direction from the solid's centre, so it faces out whatever the order.
static func _hexa(st: SurfaceTool, p: Array, col: Color) -> void:
	var c := Vector3.ZERO
	for v in p:
		c += v
	c /= 8.0
	for f: Array in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		_quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], c, col)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, centre: Vector3, col: Color) -> void:
	_tri(st, a, b, c, centre, col)
	_tri(st, a, c, d, centre, col)


## A triangle wound clockwise seen from outside (the project's front face), away from `centre`.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, centre: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	var out := (a + b + c) / 3.0 - centre
	if n.dot(out) > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_color(col)
		st.add_vertex(v)


## A hollow spike: a thin six-sided tube rising `tall` from `base`, its top cut on a slant.
static func _spike(st: SurfaceTool, base: Vector3, r: float, tall: float, col: Color) -> void:
	var sides := 6
	var centre := base + Vector3.UP * tall * 0.5
	for k in sides:
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var o0 := Vector3(cos(a0), 0.0, sin(a0)) * r
		var o1 := Vector3(cos(a1), 0.0, sin(a1)) * r
		# The slant: the top is tall at +X and a third lower at -X.
		var t0 := tall * (0.67 + 0.33 * (o0.x / r * 0.5 + 0.5))
		var t1 := tall * (0.67 + 0.33 * (o1.x / r * 0.5 + 0.5))
		_quad(st, base + o0, base + o1, base + o1 + Vector3.UP * t1, base + o0 + Vector3.UP * t0, centre, col)
