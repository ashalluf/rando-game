class_name HardHat
extends RefCounted
## A cap-style safety helmet (the everyday American hard hat: a high-gloss HDPE shell with a raised
## centre ridge and two side ribs, a short peak at the front, a rain gutter round the rim),
## modelled round each crowd rig's own head from CrowdHatTable's measurements the way FireHelmet
## is (CrowdHat.head_for(): the skull's radius round the head, the eyes, the ear tops), in the head
## frame CrowdHat uses (metres, skeleton axes, origin at the Head bone's rest; +Z the face). One
## mesh per rig, one mesh per rig and colour, one material, shared by everyone wearing it; one draw, no shadow, gone
## past the crowd's accessory range. The hair goes under it (hidden, as FireHelmet does).
## Original: no maker's name or logo; a plain reflective strip on the back.

## The shell stands this far off the skull (m): the suspension's crown straps.
const STANDOFF := 0.034
## The band edge over the eye line at the front and round the back (m).
const EDGE_FRONT := 0.042
const EDGE_BACK := 0.005
## The peak's depth at the front (m) and how far it drops; the gutter round the rest.
const PEAK := 0.055
const PEAK_DROP := 0.018
const GUTTER := 0.012
const RIDGE_HEIGHT := 0.010
const RIDGE_WIDTH := 0.016
const COLS := 40
const ROWS := 12
## The colours a crew wears (white for the super, yellow and orange for the crews, blue, green).
const COLORS := [Color(0.94, 0.94, 0.91), Color(0.95, 0.76, 0.06), Color(0.96, 0.76, 0.06), Color(0.96, 0.42, 0.06),
	Color(0.14, 0.32, 0.64), Color(0.20, 0.52, 0.22), Color(0.95, 0.76, 0.06)]
const DRAW_DISTANCE := 70.0

static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}


## Puts a hard hat in colour `pick` on the rig `inst` (an instance of the crowd rig at `rig`).
static func dress(inst: Node3D, rig: String, pick: int) -> MeshInstance3D:
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return null
	var hb := skel.find_bone("Head")
	if hb < 0:
		return null
	var unit := CrowdHat._unit(inst, skel)
	var rest := skel.get_bone_global_rest(hb)
	var att := BoneAttachment3D.new()
	att.name = "HardHatMount"
	skel.add_child(att)
	att.bone_name = "Head"
	var mi := MeshInstance3D.new()
	mi.name = "HardHat"
	mi.mesh = mesh_for(rig, pick)
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = DRAW_DISTANCE
	mi.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE / maxf(unit, 1e-6)), rest.origin)
	att.add_child(mi)
	for node in inst.find_children("Hair*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false
		node.set_meta("under_hat", true)
	return mi


## The shell's glossy plastic (its colour, the strip and the suspension are in the vertex colour).
static func material() -> StandardMaterial3D:
	if _mats.has(0):
		return _mats[0]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.28
	m.clearcoat_enabled = true
	m.clearcoat = 0.5
	m.clearcoat_roughness = 0.2
	_mats[0] = m
	return m


static func mesh_for(rig: String, pick: int) -> ArrayMesh:
	var i := absi(pick) % COLORS.size()
	var key := "%s|%d" % [rig.get_file(), i]
	if not _meshes.has(key):
		_meshes[key] = build_mesh(CrowdHat.head_for(rig), COLORS[i])
	return _meshes[key]


## The band edge's height round azimuth `th` (head frame), never down on the ears.
static func edge_y(h: CrowdHat.Head, th: float) -> float:
	var y := h.eye_y + lerpf(EDGE_FRONT, EDGE_BACK, (1.0 - cos(th)) * 0.5)
	var ear_th := atan2(h.ear.x, h.ear.z - h.c.z)
	var near := exp(-pow((absf(wrapf(th, -PI, PI)) - ear_th) / 0.5, 2.0))
	return y + maxf(h.ear.y + 0.016 - y, 0.0) * near


## A point on the shell at azimuth `th`, elevation `ph`: the skull, the standoff, the ribs.
static func shell_point(h: CrowdHat.Head, th: float, ph: float, extra: float = 0.0) -> Vector3:
	var d := CrowdHat.Head.dir(th, ph)
	var r := h.radius(th, ph) + STANDOFF + clampf(h.hair(th, ph) * 0.3, 0.0, 0.01) + extra
	# The centre ridge over the top, front to back, and two lower ribs either side of it.
	var across := absf(sin(th)) * cos(ph) * r
	var up := smoothstep(0.15, 0.7, ph)
	r += RIDGE_HEIGHT * exp(-pow(across / RIDGE_WIDTH, 2.0)) * up
	r += RIDGE_HEIGHT * 0.55 * exp(-pow((across - 0.045) / (RIDGE_WIDTH * 0.7), 2.0)) * up * smoothstep(0.0, 0.4, absf(cos(th)))
	# A hard hat's dome is fuller and higher than the skull under it.
	r += 0.014 * smoothstep(0.5, 1.4, ph)
	return h.c + d * r


static func build_mesh(h: CrowdHat.Head, shell: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	var edge_ring: Array[Vector3] = []
	for j in COLS + 1:
		var th := TAU * float(j) / float(COLS)
		var ph0 := h.phi_at_height(th, edge_y(h, th))
		var col: Array[Vector3] = []
		for i in ROWS + 1:
			var f := float(i) / float(ROWS)
			var ph := lerpf(ph0, PI * 0.5 - 0.02, f * f * 0.3 + f * 0.7)
			col.append(shell_point(h, th, ph))
		grid.append(col)
		edge_ring.append(col[0])
	var centre := h.c
	for j in COLS:
		for i in ROWS:
			FireHelmet._quad(st, grid[j][i], grid[j + 1][i], grid[j + 1][i + 1], grid[j][i + 1], shell, centre, true)
	var top := shell_point(h, 0.0, PI * 0.5)
	for j in COLS:
		FireHelmet._tri(st, grid[j][ROWS], grid[j + 1][ROWS], top, shell, centre, true)
	# The peak at the front and the gutter lip round the rest: out from the band edge, sloping down.
	var tip_ring: Array[Vector3] = []
	for j in COLS + 1:
		var th := TAU * float(j) / float(COLS)
		var front := pow(clampf(cos(th), 0.0, 1.0), 1.6)
		var w := lerpf(GUTTER, PEAK, front)
		var out := Vector3(sin(th), 0.0, cos(th))
		var drop := lerpf(0.004, PEAK_DROP, front)
		tip_ring.append(edge_ring[j] + out * w + Vector3.DOWN * drop)
	var dn := Vector3.DOWN * 0.004
	for j in COLS:
		FireHelmet._quad(st, edge_ring[j], edge_ring[j + 1], tip_ring[j + 1], tip_ring[j], shell, centre, true, true)
		FireHelmet._quad(st, edge_ring[j] + dn, tip_ring[j] + dn, tip_ring[j + 1] + dn, edge_ring[j + 1] + dn, shell * Color(0.7, 0.7, 0.7), centre, false, true)
		FireHelmet._quad(st, tip_ring[j], tip_ring[j + 1], tip_ring[j + 1] + dn, tip_ring[j] + dn, shell, centre, true)
	# The suspension's headband under the rim (dark), seen from below and the sides.
	for j in COLS:
		var a: Vector3 = edge_ring[j] - (edge_ring[j] - centre).normalized() * 0.022
		var b: Vector3 = edge_ring[j + 1] - (edge_ring[j + 1] - centre).normalized() * 0.022
		FireHelmet._quad(st, a, b, b + Vector3.DOWN * 0.016, a + Vector3.DOWN * 0.016, Color(0.08, 0.08, 0.08), centre, true)
	# A reflective strip on the back (a silver band of shell faces, a little proud).
	var rows_lo := 2
	var rows_hi := 4
	for j in COLS:
		var th := TAU * (float(j) + 0.5) / float(COLS)
		if absf(wrapf(th - PI, -PI, PI)) > 0.55:
			continue
		for i in range(rows_lo, rows_hi):
			var o := 0.0015
			var p0: Vector3 = grid[j][i] + ((grid[j][i] as Vector3) - centre).normalized() * o
			var p1: Vector3 = grid[j + 1][i] + ((grid[j + 1][i] as Vector3) - centre).normalized() * o
			var p2: Vector3 = grid[j + 1][i + 1] + ((grid[j + 1][i + 1] as Vector3) - centre).normalized() * o
			var p3: Vector3 = grid[j][i + 1] + ((grid[j][i + 1] as Vector3) - centre).normalized() * o
			FireHelmet._quad(st, p0, p1, p2, p3, Color(0.78, 0.80, 0.82), centre, true)
	return st.commit()
