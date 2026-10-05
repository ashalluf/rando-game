class_name JetBridge
extends Node3D
## One stand's jet bridge, posable (the near concourse builds one per gate; the far copy keeps
## its static bridges, which nobody can tell apart from across the field). The rotunda stays in
## the concourse's mesh; this is the rest - the two telescoping tunnel sections from the rotunda
## to the cab, the cab with its bellows and canopy, the drive column and its wheel bogie - posed
## from AirportGround.bridge_amount(): 1 docked at the parked jet's forward door (exactly the
## old static bridge), 0 pulled back, swung toward the building and its cab lifted, the way a
## real bridge waits between flights. The mesh is rebuilt only while the bridge moves (a few
## dozen boxes); the walkway's collision box moves with it.

## Off: the near concourse keeps static bridges, docked or parked as at load (the A/B;
## AIRPORT_GROUND=0 in the environment turns it off with the rest of AirportGround).
static var posable: bool = OS.get_environment("AIRPORT_GROUND") != "0"

var gate: int = 0
var y0: float = 0.1
var detailed: bool = true

var _mi: MeshInstance3D
var _mesh: ArrayMesh
var _body: AnimatableBody3D
var _shape: CollisionShape3D
var _amount: float = -1.0
var _start: Vector3
var _end_docked: Vector3
var _end_parked: Vector3
var _n: Vector3
var _t: Vector3
var _cab_drop: float = 0.0
## Surfaces: the bridge cladding, dark glass and bellows, the metal of the drive column.
var _mats: Array[Material] = []


func setup(gate_index: int, base_y: float, detail: bool, mats: Array[Material]) -> void:
	gate = gate_index
	y0 = base_y
	detailed = detail
	_mats = mats


func _ready() -> void:
	var g: Dictionary = Airport.gates()[gate]
	var n2: Vector2 = g.n
	var t2: Vector2 = g.t
	_n = Vector3(n2.x, 0.0, n2.y)
	_t = Vector3(t2.x, 0.0, t2.y)
	var rot: Vector2 = g.rotunda
	var door: Vector3 = g.door
	var floor_r := y0 + AirportTerminal.DEPARTURE_LEVEL
	_start = Vector3(rot.x, floor_r + 1.3, rot.y)
	var cab := door - _t * 1.9
	cab.y = y0 + door.y - 0.6
	_end_docked = cab - _t * 1.7 + Vector3(0.0, 1.3, 0.0)
	# Retracted: the tunnel drawn in to 60 % of its docked length, swung back toward the
	# building and level with the rotunda.
	var d := _end_docked - _start
	var flat := Vector3(d.x, 0.0, d.z)
	var swung := flat.rotated(Vector3.UP, 0.32 * signf(flat.cross(_n).y + 1e-4)) * 0.62
	_end_parked = _start + swung + Vector3(0.0, 0.3, 0.0)
	_mesh = ArrayMesh.new()
	_mi = MeshInstance3D.new()
	_mi.name = "Bridge"
	_mi.mesh = _mesh
	add_child(_mi)
	_body = AnimatableBody3D.new()
	_body.sync_to_physics = false
	_body.collision_layer = 1
	_body.collision_mask = 0
	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	_body.add_child(_shape)
	add_child(_body)
	_pose(AirportGround.bridge_amount(gate))


func _process(_delta: float) -> void:
	var a := AirportGround.bridge_amount(gate)
	if absf(a - _amount) > 0.001:
		_pose(a)


## The bridge at extension `a` (0 retracted .. 1 docked).
func _pose(a: float) -> void:
	_amount = a
	var e := smoothstep(0.0, 1.0, a)
	var start := _start
	var end := _end_parked.lerp(_end_docked, e)
	var dir := (end - start).normalized()
	var cab := end + _t * 1.7 - Vector3(0.0, 1.3, 0.0)
	var b := _Builder.new()
	# The outer section is fixed to the rotunda; the inner one slides out of it to the cab.
	var outer_len := maxf(start.distance_to(_end_docked) * 0.55, 3.0)
	b.tunnel(start, start + dir * outer_len, 3.2, 3.1)
	b.tunnel(start + dir * minf(outer_len - 0.6, start.distance_to(end) * 0.5), end, 3.0, 2.9)
	var face := atan2(_t.x, _t.z)
	var fb := Basis(Vector3.UP, face)
	b.box(0, cab + Vector3(0.0, 1.3, 0.0), Vector3(3.6, 3.0, 3.2), fb)
	b.box(1, cab + _t * 1.62 + Vector3(0.0, 1.3, 0.0), Vector3(3.2, 2.7, 0.12), fb)
	# The drive column under the inner tunnel: two legs, the bogie and its wheels.
	var dc := end.lerp(start, 0.18)
	dc.y = y0
	var leg_h := maxf(end.y - 1.6 - y0, 0.5)
	var nb := Basis(Vector3.UP, atan2(_n.x, _n.z))
	for s: float in [-0.9, 0.9]:
		b.box(2, dc + _n * s + Vector3(0.0, leg_h * 0.5, 0.0), Vector3(0.3, leg_h, 0.3), Basis(), Color(0.75, 0.76, 0.78))
	b.box(2, dc + Vector3(0.0, 0.55, 0.0), Vector3(2.6, 0.5, 1.2), nb, Color(0.85, 0.65, 0.1))
	if detailed:
		for s: float in [-1.0, 1.0]:
			b.box(1, dc + _n * (s * 1.1) - _t * 0.4 + Vector3(0.0, 0.45, 0.0), Vector3(0.4, 0.9, 0.9), nb)
	b.commit(_mesh, _mats)
	var span := end - start
	_body.transform = Transform3D(Basis.looking_at(span.normalized(), Vector3.UP), (start + end) * 0.5)
	(_shape.shape as BoxShape3D).size = Vector3(3.2, 3.1, span.length())


## A tiny box writer with UVs in metres (u along a face, v world height), for the landmark
## facade shader the bridge cladding uses, one surface per material slot.
class _Builder extends RefCounted:
	var v: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var nrm: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var uv: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	var col: Array[PackedColorArray] = [PackedColorArray(), PackedColorArray(), PackedColorArray()]
	var tan: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]

	func box(slot: int, c: Vector3, size: Vector3, basis: Basis, tint: Color = Color.WHITE) -> void:
		var h := size * 0.5
		for axis in 3:
			for sgn: float in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[axis] = sgn
				var ua := (axis + 1) % 3
				var va := (axis + 2) % 3
				var u := Vector3.ZERO
				u[ua] = 1.0
				var w := Vector3.ZERO
				w[va] = 1.0
				var p0 := n * h[axis]
				var corners := [p0 - u * h[ua] - w * h[va], p0 + u * h[ua] - w * h[va], p0 + u * h[ua] + w * h[va], p0 - u * h[ua] + w * h[va]]
				var wn := (basis * n).normalized()
				var wu := (basis * u).normalized()
				var pts: Array[Vector3] = []
				for q: Vector3 in corners:
					pts.append(c + basis * q)
				var order := [0, 1, 2, 0, 2, 3]
				if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(wn) > 0.0:
					order = [0, 2, 1, 0, 3, 2]
				for k: int in order:
					var p: Vector3 = pts[k]
					v[slot].append(p)
					nrm[slot].append(wn)
					uv[slot].append(Vector2(p.dot(wu), p.y))
					col[slot].append(tint)
					tan[slot].append_array(PackedFloat32Array([wu.x, wu.y, wu.z, 1.0]))

	## A box tunnel from a to b (centre line of its floor + half its height), w wide, h tall, with
	## a band of windows along both sides.
	func tunnel(a: Vector3, b: Vector3, w: float, h: float) -> void:
		var d := b - a
		if d.length() < 0.2:
			return
		var basis := Basis.looking_at(d.normalized(), Vector3.UP)
		box(0, (a + b) * 0.5, Vector3(w, h, d.length()), basis)
		for s: float in [-1.0, 1.0]:
			box(1, (a + b) * 0.5 + basis * Vector3(s * (w * 0.5 + 0.01), 0.25, 0.0), Vector3(0.02, 0.8, d.length() - 0.8), basis)

	func commit(mesh: ArrayMesh, mats: Array[Material]) -> void:
		mesh.clear_surfaces()
		for slot in 3:
			if v[slot].is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = v[slot]
			arrays[Mesh.ARRAY_NORMAL] = nrm[slot]
			arrays[Mesh.ARRAY_TEX_UV] = uv[slot]
			arrays[Mesh.ARRAY_COLOR] = col[slot]
			arrays[Mesh.ARRAY_TANGENT] = tan[slot]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			if slot < mats.size():
				mesh.surface_set_material(mesh.get_surface_count() - 1, mats[slot])
