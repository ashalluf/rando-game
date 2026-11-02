class_name RailGate
extends Node3D
## One level crossing gate (LightRailKit builds the mast, the crossbuck, the bell and the flasher
## hoods into the chunk's mesh; this node is the part that moves): the striped arm on its pivot
## with three lamps along it, and the two flasher lamps that alternate. LightRailSystem drives
## every gate in the "rail_gate" group from the crossing state it works out from the clock
## (LightRail.crossing_phase()): `pose_at(phase, blink)`. Nothing here is ticked or decided.

## Seconds for the arm to come down or go up (a real gate takes 10-15; a game wants it seen).
const ARM_SECONDS := 6.0
## How long the lamps flash before the arm starts down (real practice: 3-5 s).
const PRE_FLASH := 3.0

static var _arm_mesh: ArrayMesh
static var _arm_mat: StandardMaterial3D
static var _lamp_on: StandardMaterial3D
static var _lamp_off: StandardMaterial3D
static var _lamp_mesh: CylinderMesh

var node_key := Vector2i.ZERO
var axis := 0
var _pivot: Node3D
var _lamps: Array[MeshInstance3D] = []
var _arm_lamps: Array[MeshInstance3D] = []
## 0 = up (vertical), 1 = down (across the lanes).
var lowered := 0.0


static func make(g: Dictionary, full: bool) -> RailGate:
	var gate := RailGate.new()
	gate.name = "RailGate"
	gate.node_key = g.node
	gate.axis = g.axis
	gate.add_to_group("rail_gate")
	var base: Vector3 = g.base
	var heading: Vector2 = g.heading
	var right: Vector2 = g.right
	var h3 := Vector3(heading.x, 0.0, heading.y)
	var r3 := Vector3(right.x, 0.0, right.y)
	# The node's own frame: x toward the road's centre (-right), z along the traffic (so the
	# drivers it stops are on its -z side).
	gate.transform = Transform3D(Basis(-r3, Vector3.UP, h3), base)
	var pivot := Node3D.new()
	pivot.name = "Arm"
	pivot.position = Vector3(-0.35, 1.05, -0.25)
	gate.add_child(pivot)
	gate._pivot = pivot
	var arm := MeshInstance3D.new()
	arm.mesh = arm_mesh(float(g.length))
	arm.material_override = _arm_material()
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if full else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(arm)
	if full:
		# The three lamps along the arm, one mesh (they light together).
		var l := MeshInstance3D.new()
		l.mesh = arm_lamps_mesh(float(g.length))
		l.material_override = lamp_material(false)
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(l)
		gate._arm_lamps.append(l)
		# The flasher pair on the crossarm, facing the traffic (-z of the node).
		for e: float in [0.48, -0.48]:
			var lamp := MeshInstance3D.new()
			lamp.mesh = lamp_mesh()
			lamp.position = Vector3(e, 2.85, -0.2)
			lamp.rotation = Vector3(PI * 0.5, 0.0, 0.0)
			lamp.material_override = lamp_material(false)
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gate.add_child(lamp)
			gate._lamps.append(lamp)
	gate._pose()
	return gate


## The arm: a 10 cm square boom with red and white stripes (vertex colours), counterweight end.
static func arm_mesh(length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stripe := 0.6
	var x := -0.6
	var k := 0
	while x < length:
		var x1 := minf(x + stripe, length)
		var col := Color(0.06, 0.06, 0.07) if x < 0.0 else (Color(0.78, 0.04, 0.03) if k % 2 == 0 else Color(0.92, 0.92, 0.9))
		_box(st, Vector3((x + x1) * 0.5, 0.0, 0.0), Vector3((x1 - x) * 0.5, 0.05 if x >= 0.0 else 0.14, 0.05 if x >= 0.0 else 0.09), col)
		x = x1
		k += 1
	st.generate_normals()
	return st.commit()


static func _box(st: SurfaceTool, c: Vector3, h: Vector3, col: Color) -> void:
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.LEFT, Vector3.UP]]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + n * h
		var uu := u * h
		var vv := v * h
		var p := [o - uu - vv, o + uu - vv, o + uu + vv, o - uu + vv]
		for i: int in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.add_vertex(p[i])


static func _arm_material() -> StandardMaterial3D:
	if _arm_mat == null:
		_arm_mat = StandardMaterial3D.new()
		_arm_mat.vertex_color_use_as_albedo = true
		_arm_mat.roughness = 0.45
	return _arm_mat


static var _arm_lamp_meshes: Dictionary = {}


## Three lamp discs along an arm of `length`, facing the traffic (-z).
static func arm_lamps_mesh(length: float) -> ArrayMesh:
	var key := snappedf(length, 0.1)
	if _arm_lamp_meshes.has(key):
		return _arm_lamp_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var c := Vector3(length * (0.3 + 0.33 * float(k)), 0.1, -0.06)
		for i in 10:
			var a0 := TAU * float(i) / 10.0
			var a1 := TAU * float(i + 1) / 10.0
			for p: Vector3 in [c, c + Vector3(cos(a1), sin(a1), 0.0) * 0.09, c + Vector3(cos(a0), sin(a0), 0.0) * 0.09]:
				st.set_normal(Vector3.FORWARD)
				st.add_vertex(p)
	var m := st.commit()
	_arm_lamp_meshes[key] = m
	return m


static func lamp_mesh() -> CylinderMesh:
	if _lamp_mesh == null:
		_lamp_mesh = CylinderMesh.new()
		_lamp_mesh.top_radius = 0.15
		_lamp_mesh.bottom_radius = 0.15
		_lamp_mesh.height = 0.04
		_lamp_mesh.radial_segments = 12
		_lamp_mesh.rings = 1
	return _lamp_mesh


static func lamp_material(on: bool) -> StandardMaterial3D:
	if _lamp_on == null:
		_lamp_on = StandardMaterial3D.new()
		_lamp_on.albedo_color = Color(0.5, 0.02, 0.01)
		_lamp_on.emission_enabled = true
		_lamp_on.emission = Color(1.0, 0.08, 0.03)
		_lamp_on.emission_energy_multiplier = 7.0
		_lamp_off = StandardMaterial3D.new()
		_lamp_off.albedo_color = Color(0.12, 0.02, 0.02)
		_lamp_off.roughness = 0.25
	return _lamp_on if on else _lamp_off


## The gate at crossing phase `phase` (LightRail.crossing_phase(): seconds closed, or minus the
## seconds open): the lamps flash from the moment it closes, the arm starts down PRE_FLASH later
## and takes ARM_SECONDS, and goes back up as soon as it opens. Worked out, never ticked.
func pose_at(phase: float, blink: bool) -> void:
	if phase > 0.0:
		lowered = clampf((phase - PRE_FLASH) / ARM_SECONDS, 0.0, 1.0)
	else:
		# Up from wherever it was when the crossing opened (fully down for any real train).
		lowered = clampf(1.0 + phase / ARM_SECONDS, 0.0, 1.0)
	_pose()
	var flashing := phase > 0.0 or lowered > 0.02
	for i in _lamps.size():
		_lamps[i].material_override = lamp_material(flashing and ((i == 0) == blink))
	for l in _arm_lamps:
		l.material_override = lamp_material(flashing)


func _pose() -> void:
	if _pivot == null:
		return
	# Up is the arm standing near vertical; down lies across the lanes (+x).
	var e := lowered * lowered * (3.0 - 2.0 * lowered)
	_pivot.rotation = Vector3(0.0, 0.0, lerpf(deg_to_rad(84.0), 0.0, e))
