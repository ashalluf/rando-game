class_name MotoHelmet
extends RefCounted
## A full-face motorcycle helmet modelled round each crowd rig's own head (CrowdHat.head_for, the
## head frame: metres, skeleton axes, the face toward +Z, origin at the Head bone's rest), like
## BikeHelmet and FireHelmet: a smooth egg of a shell standing 4-6 cm off the skull, down over the
## jaw to a chin bar at the front and the nape at the back, a dark smoked visor across the eyes
## (a hair proud of the shell, with its pivot plates), a vent in the chin bar, a rubber trim round
## the opening. One smooth-shaded mesh per rig and shell colour, vertex colours on one glossy
## clear-coated material; one draw per wearer, no shadow. The hair goes under it (hidden).

const COLS := 40
const ROWS := 16
const COLORS := [Color(0.05, 0.05, 0.055), Color(0.05, 0.05, 0.055), Color(0.92, 0.92, 0.91), Color(0.62, 0.05, 0.04),
	Color(0.38, 0.40, 0.42), Color(0.10, 0.18, 0.42), Color(0.08, 0.08, 0.08), Color(0.85, 0.75, 0.10)]
const VISOR := Color(0.018, 0.02, 0.024)
const TRIM := Color(0.03, 0.03, 0.032)
const DRAW_DISTANCE := 90.0

static var _meshes: Dictionary = {}
static var _mat: StandardMaterial3D


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
	att.name = "HelmetMount"
	skel.add_child(att)
	att.bone_name = "Head"
	var mi := MeshInstance3D.new()
	mi.name = "MotoHelmet"
	mi.mesh = mesh_for(rig, COLORS[pick % COLORS.size()])
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


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.22
		_mat.clearcoat_enabled = true
		_mat.clearcoat = 0.8
		_mat.clearcoat_roughness = 0.08
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat


static func mesh_for(rig: String, shell: Color) -> ArrayMesh:
	var key := "%s|%d" % [rig.get_file(), shell.to_rgba32()]
	if not _meshes.has(key):
		_meshes[key] = build_mesh(CrowdHat.head_for(rig), shell)
	return _meshes[key]


## The shell's half sizes round the head's centre: x across, y up / down, z to the face / back.
static func _axes(h: CrowdHat.Head) -> Array:
	var rx := maxf(h.ear.x, 0.07) + 0.062
	var zf := maxf(h.eye_z - h.c.z, 0.06) + 0.085
	var zb := 0.10 + 0.055
	var yu := maxf(h.top - h.c.y, 0.09) + 0.045
	var yd := (h.c.y - (h.eye_y - 0.17))
	return [rx, zf, zb, yu, yd]


## The shell's point at azimuth th (0 the face, + toward the rig's left: +x) and elevation ph,
## and its outward normal.
static func _shell(h: CrowdHat.Head, ax: Array, th: float, ph: float, extra: float = 0.0) -> Array:
	var c := cos(ph)
	var s := sin(ph)
	var fz := cos(th)
	var rz := float(ax[1]) if fz > 0.0 else float(ax[2])
	var ry := float(ax[3]) if s > 0.0 else float(ax[4])
	var rx := float(ax[0])
	var p := Vector3(sin(th) * c * (rx + extra), s * (ry + extra), fz * c * (rz + extra))
	var n := Vector3(p.x / ((rx + extra) * (rx + extra)), p.y / ((ry + extra) * (ry + extra)), p.z / ((rz + extra) * (rz + extra))).normalized()
	return [h.c + p, n]


## Where the shell stops: low at the chin, up under the jaw at the sides, the nape behind.
static func _bottom(h: CrowdHat.Head, ax: Array, th: float) -> float:
	var y := lerpf(h.eye_y - 0.165, h.eye_y - 0.125, (1.0 - cos(th)) * 0.5)
	var ry := float(ax[4])
	return -asin(clampf((h.c.y - y) / ry, 0.0, 0.999))


static func build_mesh(h: CrowdHat.Head, shell: Color) -> ArrayMesh:
	var ax := _axes(h)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	var nrm: Array = []
	var col: Array = []
	for j in COLS + 1:
		var th := TAU * float(j) / float(COLS)
		var ph0 := _bottom(h, ax, th)
		var cp: Array = []
		var cn: Array = []
		var cc: Array = []
		for i in ROWS + 1:
			var f := float(i) / float(ROWS)
			var ph := lerpf(ph0, PI * 0.5 - 0.001, f)
			var a := absf(wrapf(th, -PI, PI))
			var y := h.c.y + sin(ph) * (float(ax[3]) if ph > 0.0 else float(ax[4]))
			var visor := a < 1.2 and y > h.eye_y - 0.04 and y < h.eye_y + 0.045
			var chin_vent := a < 0.22 and y > h.eye_y - 0.115 and y < h.eye_y - 0.075
			var sp := _shell(h, ax, th, ph, 0.004 if visor else 0.0)
			cp.append(sp[0])
			cn.append(sp[1])
			cc.append(VISOR if visor else (TRIM if chin_vent or i == 0 else shell))
		pts.append(cp)
		nrm.append(cn)
		col.append(cc)
	for j in COLS:
		for i in ROWS:
			var q := [[j, i], [j + 1, i], [j + 1, i + 1], [j, i + 1]]
			var c: Color = col[j][i]
			for tri: Array in [[0, 2, 1], [0, 3, 2]]:
				for k: int in tri:
					var jj: int = q[k][0]
					var ii: int = q[k][1]
					st.set_color(c)
					st.set_normal(nrm[jj][ii])
					st.add_vertex(pts[jj][ii])
	# The rubber trim turned in under the rim.
	for j in COLS:
		var a0: Vector3 = pts[j][0]
		var a1: Vector3 = pts[j + 1][0]
		var b0 := a0 + (h.c - a0) * 0.18 + Vector3.DOWN * 0.004
		var b1 := a1 + (h.c - a1) * 0.18 + Vector3.DOWN * 0.004
		for v: Vector3 in [a0, b1, a1, a0, b0, b1]:
			st.set_color(TRIM)
			st.set_normal(Vector3.DOWN)
			st.add_vertex(v)
	# The visor's pivot plates by the temples.
	for s: float in [-1.0, 1.0]:
		var th := s * 1.25
		var ph := asin(clampf((h.eye_y + 0.005 - h.c.y) / float(ax[3]), -0.99, 0.99))
		var sp := _shell(h, ax, th, ph, 0.006)
		var p: Vector3 = sp[0]
		var n: Vector3 = sp[1]
		var u := n.cross(Vector3.UP).normalized() * 0.018
		var v := Vector3.UP * 0.014
		for vv: Vector3 in [p - u - v, p + u + v, p + u - v, p - u - v, p - u + v, p + u + v]:
			st.set_color(TRIM)
			st.set_normal(n)
			st.add_vertex(vv)
	var mesh := st.commit()
	return mesh
