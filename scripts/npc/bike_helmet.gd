class_name BikeHelmet
extends RefCounted
## A bicycle helmet modelled round each crowd rig's own head (CrowdHatTable through
## CrowdHat.head_for, in CrowdHat's head frame: metres, skeleton axes, origin at the Head bone's
## rest), like FireHelmet: an in-moulded shell standing off the skull by its foam liner, drawn out
## into a tail at the back on a road helmet, rows of vents cut through it front to back (inset
## dark slots, so there is depth in them), a short peak on a commuter helmet, the black edge band,
## the straps down to the Y-buckle under each ear. One mesh per rig and style, one material
## (vertex colour; glossy shell, matte straps); one draw per wearer, no shadow, gone past the
## crowd's accessory range. The hair goes under it (hidden).

## The shell off the skull (m): the liner.
const STANDOFF := 0.026
## The rim's height over the eye line at the front and at the back (m).
const EDGE_FRONT := 0.038
const EDGE_BACK := -0.005
## How far a road helmet's tail is drawn out behind (m), and its vents' count.
const TAIL := 0.03
const COLS := 48
const ROWS := 14
const DRAW_DISTANCE := 60.0

const ROAD_COLORS := [Color(0.93, 0.93, 0.92), Color(0.05, 0.05, 0.055), Color(0.72, 0.08, 0.07), Color(0.12, 0.25, 0.55), Color(0.85, 0.9, 0.2)]
const COMMUTER_COLORS := [Color(0.06, 0.06, 0.065), Color(0.42, 0.44, 0.46), Color(0.9, 0.9, 0.88), Color(0.55, 0.78, 0.7), Color(0.75, 0.3, 0.25)]
const DARK := Color(0.025, 0.025, 0.028)
const STRAP := Color(0.04, 0.04, 0.045)

static var _meshes: Dictionary = {}
static var _mat: StandardMaterial3D


## Puts a helmet on the rig `inst` (an instance of the crowd rig at `rig`).
static func dress(inst: Node3D, rig: String, pick: int, distance: float, road: bool) -> MeshInstance3D:
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return null
	var hb := skel.find_bone("Head")
	if hb < 0:
		return null
	var unit := CrowdHat._unit(inst, skel)
	var rest := skel.get_bone_global_rest(hb)
	var att := BoneAttachment3D.new()
	att.name = "HelmetMount"
	skel.add_child(att)
	att.bone_name = "Head"
	var mi := MeshInstance3D.new()
	mi.name = "Helmet"
	var colors: Array = ROAD_COLORS if road else COMMUTER_COLORS
	mi.mesh = mesh_for(rig, road, colors[pick % colors.size()])
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = distance
	mi.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE / maxf(unit, 1e-6)), rest.origin)
	att.add_child(mi)
	for node in inst.find_children("Hair*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false
		node.set_meta("under_hat", true)
	return mi


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.3
		_mat.clearcoat_enabled = true
		_mat.clearcoat = 0.5
		_mat.clearcoat_roughness = 0.2
	return _mat


static func mesh_for(rig: String, road: bool, shell: Color) -> ArrayMesh:
	var key := "%s|%d|%d" % [rig.get_file(), int(road), shell.to_rgba32()]
	if not _meshes.has(key):
		_meshes[key] = build_mesh(CrowdHat.head_for(rig), road, shell)
	return _meshes[key]


static func edge_y(h: CrowdHat.Head, th: float) -> float:
	var y := h.eye_y + lerpf(EDGE_FRONT, EDGE_BACK, (1.0 - cos(th)) * 0.5)
	var ear_th := atan2(h.ear.x, h.ear.z - h.c.z)
	var near := exp(-pow((absf(wrapf(th, -PI, PI)) - ear_th) / 0.5, 2.0))
	return y + maxf(h.ear.y + 0.014 - y, 0.0) * near


## A point on the shell at azimuth `th` (0 the face), elevation `ph`; `extra` more off the skull.
static func shell_point(h: CrowdHat.Head, th: float, ph: float, road: bool, extra: float = 0.0) -> Vector3:
	var d := CrowdHat.Head.dir(th, ph)
	var r := h.radius(th, ph) + STANDOFF + clampf(h.hair(th, ph) * 0.4, 0.0, 0.012) + extra
	var p := h.c + d * r
	# Drawn out at the back into a tail (lower down the back of a road helmet), and the crown a
	# little fuller than the skull.
	var back := maxf(-cos(th), 0.0)
	var tail := (TAIL if road else 0.008) * pow(back, 2.0) * smoothstep(1.2, 0.2, ph)
	p += Vector3(0.0, 0.0, -1.0) * tail + Vector3.UP * 0.006 * smoothstep(0.5, 1.4, ph)
	return p


## Whether the shell is cut by a vent at (th, ph): slots running front to back between ribs.
static func vent(th: float, ph: float, road: bool) -> bool:
	var a := wrapf(th, -PI, PI)
	if ph < 0.38 or ph > 1.42:
		return false
	var n := 7 if road else 4
	# Ribs fan out from the crown: the slot index by azimuth folded front to back.
	var u := (sin(a) * cos(ph)) / maxf(cos(ph) * 0.9 + 0.1, 0.2)
	var k := u * float(n) * 0.5
	var slot := absf(fposmod(k + 0.5, 1.0) - 0.5) < (0.22 if road else 0.16)
	# Front vents end before the rim, rear vents above the tail; none on the crown's spine on a
	# commuter helmet.
	var along := cos(a)
	if absf(along) < 0.15 and not road:
		return false
	return slot and absf(u) < 0.95 and ph < (1.3 if road else 1.15)


static func build_mesh(h: CrowdHat.Head, road: bool, shell: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	var edge_ring: Array[Vector3] = []
	var phs: Array = []
	for j in COLS + 1:
		var th := TAU * float(j) / float(COLS)
		var ph0 := h.phi_at_height(th, edge_y(h, th))
		var col: Array = []
		var pcol: Array = []
		for i in ROWS + 1:
			var f := float(i) / float(ROWS)
			var ph := lerpf(ph0, PI * 0.5 - 0.02, f * f * 0.25 + f * 0.75)
			col.append(shell_point(h, th, ph, road))
			pcol.append(ph)
		grid.append(col)
		phs.append(pcol)
		edge_ring.append(col[0])
	var center := h.c
	for j in COLS:
		var th := TAU * (float(j) + 0.5) / float(COLS)
		for i in ROWS:
			var ph := (float(phs[j][i]) + float(phs[j][i + 1])) * 0.5
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j + 1][i]
			var c: Vector3 = grid[j + 1][i + 1]
			var d: Vector3 = grid[j][i + 1]
			if vent(th, ph, road):
				# A slot: the floor sunk to the liner, dark, with its walls.
				var sink := 0.012
				var as_ := a + (a - center).normalized() * -sink
				var bs := b + (b - center).normalized() * -sink
				var cs := c + (c - center).normalized() * -sink
				var ds := d + (d - center).normalized() * -sink
				FireHelmet._quad(st, as_, bs, cs, ds, DARK, center, true)
				if not vent(th - TAU / COLS, ph, road):
					FireHelmet._quad(st, a, as_, ds, d, shell.darkened(0.35), center, true)
				if not vent(th + TAU / COLS, ph, road):
					FireHelmet._quad(st, b, c, cs, bs, shell.darkened(0.35), center, true)
			else:
				FireHelmet._quad(st, a, b, c, d, shell, center, true)
	var top := shell_point(h, 0.0, PI * 0.5, road)
	for j in COLS:
		FireHelmet._tri(st, grid[j][ROWS], grid[j + 1][ROWS], top, shell, center, true)
	# The black edge band round the rim, turned under.
	var inner_ring: Array[Vector3] = []
	for j in COLS + 1:
		var p: Vector3 = edge_ring[j]
		inner_ring.append(p + (center - p).normalized() * 0.02 + Vector3.DOWN * 0.004)
	for j in COLS:
		var lo_a := edge_ring[j] + Vector3.DOWN * 0.008
		var lo_b := edge_ring[j + 1] + Vector3.DOWN * 0.008
		FireHelmet._quad(st, edge_ring[j], edge_ring[j + 1], lo_b, lo_a, DARK, center, true)
		FireHelmet._quad(st, lo_a, lo_b, inner_ring[j + 1], inner_ring[j], DARK, center, false, true)
	# A commuter helmet's short peak over the brow.
	if not road:
		for j in COLS:
			var th := TAU * (float(j) + 0.5) / float(COLS)
			var a := wrapf(th, -PI, PI)
			if absf(a) > 0.75:
				continue
			var p0 := edge_ring[j]
			var p1 := edge_ring[j + 1]
			var o0 := Vector3(sin(TAU * float(j) / COLS), -0.15, cos(TAU * float(j) / COLS)).normalized() * 0.03 * cos(a * 2.0)
			var o1 := Vector3(sin(TAU * float(j + 1) / COLS), -0.15, cos(TAU * float(j + 1) / COLS)).normalized() * 0.03 * cos(a * 2.0)
			FireHelmet._quad(st, p0, p1, p1 + o1, p0 + o0, DARK, center, true, true)
			FireHelmet._quad(st, p0 + Vector3.DOWN * 0.003, p0 + o0 + Vector3.DOWN * 0.003, p1 + o1 + Vector3.DOWN * 0.003, p1 + Vector3.DOWN * 0.003, DARK, center, false, true)
	# Straps: from the rim in front of and behind each ear down to a buckle under it.
	for s: float in [-1.0, 1.0]:
		var ear := Vector3(h.ear.x * s, h.ear.y, h.ear.z)
		var buckle := ear + Vector3(s * 0.006, -0.05, 0.012)
		for th_off: float in [0.45, -0.5]:
			var th := atan2(ear.x, ear.z - h.c.z) + th_off * s
			var rim := shell_point(h, th, h.phi_at_height(th, edge_y(h, th)), road) + Vector3.DOWN * 0.006
			_strap(st, rim, buckle, center)
		var chin := Vector3(0.0, h.eye_y - 0.13, h.c.z + 0.035)
		_strap(st, buckle, buckle.lerp(chin, 0.6), center)
		var bx := Transform3D(Basis(), buckle)
		_box(st, bx, Vector3(0.012, 0.018, 0.008), STRAP.lightened(0.15), center)
	return st.commit()


static func _strap(st: SurfaceTool, a: Vector3, b: Vector3, center: Vector3) -> void:
	var along := (b - a).normalized()
	var out := ((a + b) * 0.5 - center).normalized()
	var side := along.cross(out).normalized() * 0.008
	FireHelmet._quad(st, a - side, a + side, b + side, b - side, STRAP, center, true)
	FireHelmet._quad(st, a - side, b - side, b + side, a + side, STRAP, center, false)


static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color, center: Vector3) -> void:
	var h := size * 0.5
	for k in 3:
		for sg: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[k] = sg
			var u := Vector3.ZERO
			u[(k + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(k + 2) % 3] = 1.0
			var c := n * h[k]
			var du := u * h[(k + 1) % 3]
			var dv := v * h[(k + 2) % 3]
			var p := [xf * (c - du - dv), xf * (c + du - dv), xf * (c + du + dv), xf * (c - du + dv)]
			var want := xf.basis * n
			_face(st, p, want, col)


static func _face(st: SurfaceTool, p: Array, want: Vector3, col: Color) -> void:
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		var a: Vector3 = p[tri[0]]
		var b: Vector3 = p[tri[1]]
		var c: Vector3 = p[tri[2]]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			continue
		if n.dot(want) > 0.0:
			var t := b
			b = c
			c = t
		for v: Vector3 in [a, b, c]:
			st.set_color(col)
			st.set_normal(want.normalized())
			st.add_vertex(v)
