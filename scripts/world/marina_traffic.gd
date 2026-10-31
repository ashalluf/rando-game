class_name MarinaTraffic
extends Node3D
## A few small boats motoring round the marina (Marina.traffic_loop): out of the fairway's north
## end, down it, out along the channel under the coast highway's bridge and past the jetties, a
## wide turn in the lee of the breakwater, and back. Kinematic and scripted - a position along a
## closed polyline at a harbour speed, the hull rolled into its turns, a little bow-up trim and a
## wake of foam behind. Low boats only (runabouts and centre consoles): the bridge clears 3.9 m.
## A child of the chunk that holds the loop's start (MarinaBuild._traffic_step()); chunk space is
## true world XZ, so it needs nothing on an origin re-centre.

## How many boats, their speed (m/s: a harbour's 5 knots is 2.6), and the spacing along the loop.
@export var boats := 3
@export var speed := 3.4
@export var bank_per_turn := 0.12

var _loop := PackedVector2Array()
var _cum := PackedFloat32Array()
var _length := 0.0
var _nodes: Array[Node3D] = []
var _offsets: Array[float] = []
var _speeds: Array[float] = []
var _wakes: Array[CPUParticles3D] = []


func setup(mr: Marina) -> void:
	_loop = mr.traffic_loop.duplicate()
	_cum = PackedFloat32Array([0.0])
	for i in _loop.size():
		var a := _loop[i]
		var b := _loop[(i + 1) % _loop.size()]
		_length += a.distance_to(b)
		_cum.append(_length)
	for k in boats:
		var variant := k % 2
		var mesh := BoatMesh.mesh(Marina.Type.RUNABOUT, variant, BoatMesh.Level.NEAR)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := MarinaBuild.boat_material().duplicate() as ShaderMaterial
		mat.set_shader_parameter("solo", 1.0)
		var paint: Color = Marina.HULL_PAINTS[absi(hash([mr.seed_value, "traffic", k])) % Marina.HULL_PAINTS.size()]
		mat.set_shader_parameter("solo_paint", Vector3(paint.r, paint.g, paint.b))
		mat.set_shader_parameter("solo_flags", float(absi(hash([mr.seed_value, "traffic_c", k])) % 6))
		mi.material_override = mat
		var holder := Node3D.new()
		holder.name = "Boat%d" % k
		holder.add_child(mi)
		var s := lerpf(0.9, 1.15, float(absi(hash([mr.seed_value, "traffic_s", k])) % 100) / 100.0)
		mi.scale = Vector3.ONE * s
		add_child(holder)
		_nodes.append(holder)
		_offsets.append(_length * float(k) / float(boats))
		_speeds.append(speed * lerpf(0.85, 1.15, float(absi(hash([mr.seed_value, "traffic_v", k])) % 100) / 100.0))
		var wake := CPUParticles3D.new()
		wake.amount = 40
		wake.lifetime = 5.0
		wake.local_coords = false
		wake.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		wake.emission_box_extents = Vector3(0.6, 0.0, 0.2)
		wake.direction = Vector3(0.0, 0.0, 1.0)
		wake.spread = 25.0
		wake.initial_velocity_min = 0.3
		wake.initial_velocity_max = 0.7
		wake.gravity = Vector3.ZERO
		wake.scale_amount_min = 0.6
		wake.scale_amount_max = 1.2
		var curve := Curve.new()
		curve.max_value = 4.0
		curve.add_point(Vector2(0.0, 0.6))
		curve.add_point(Vector2(1.0, 4.0))
		wake.scale_amount_curve = curve
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 1.0, 1.0, 0.55))
		grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		wake.color_ramp = grad
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		quad.orientation = PlaneMesh.FACE_Y
		var wm := StandardMaterial3D.new()
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.vertex_color_use_as_albedo = true
		wm.albedo_color = Color(0.85, 0.88, 0.86)
		wm.albedo_texture = WeaponFX.puff_texture()
		quad.material = wm
		wake.mesh = quad
		wake.position = Vector3(0.0, Marina.WATER_Y + 0.04, 3.0)
		holder.add_child(wake)
		_wakes.append(wake)
	_place(0.0)


func _physics_process(delta: float) -> void:
	_place(delta)


func _place(delta: float) -> void:
	for k in _nodes.size():
		_offsets[k] = fposmod(_offsets[k] + _speeds[k] * delta, _length)
		var s := _offsets[k]
		var p := _at(s)
		var ahead := _at(fposmod(s + 6.0, _length))
		var behind := _at(fposmod(s - 6.0, _length))
		var d := (ahead - behind).normalized()
		var d0 := (p - behind).normalized()
		var d1 := (ahead - p).normalized()
		var turn := d0.cross(d1)
		var yaw := atan2(-d.x, -d.y)
		var t := Time.get_ticks_msec() * 0.001 + float(k) * 1.3
		var roll := clampf(turn * 3.0, -1.0, 1.0) * bank_per_turn + sin(t * 1.7) * 0.02
		var pitch := 0.05 + sin(t * 2.3) * 0.012
		_nodes[k].transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, roll) * Basis(Vector3.RIGHT, pitch), Vector3(p.x, Marina.WATER_Y + 0.05 + sin(t * 1.9) * 0.03, p.y))


## The point at distance s along the closed loop, with its corners rounded (a Catmull-Rom between
## the polyline's points by fraction of the segment).
func _at(s: float) -> Vector2:
	var n := _loop.size()
	var i := 0
	while i < n - 1 and _cum[i + 1] < s:
		i += 1
	var seg := maxf(_cum[i + 1] - _cum[i], 0.001)
	var u := (s - _cum[i]) / seg
	var p0 := _loop[(i - 1 + n) % n]
	var p1 := _loop[i]
	var p2 := _loop[(i + 1) % n]
	var p3 := _loop[(i + 2) % n]
	return p1.cubic_interpolate(p2, p0, p3, u)
