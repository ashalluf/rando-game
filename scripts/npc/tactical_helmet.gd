class_name TacticalHelmet
extends RefCounted
## A high-cut ballistic helmet for the tactical van's officers (four stars) and the agency's
## troopers (five stars; WantedEscalation): a matte shell standing off the skull, cut high over
## the ears, a rubber edge trim, accessory rails along both sides and a night-vision mount plate
## on the front. Modelled round each crowd rig's own head from CrowdHatTable (CrowdHat.head_for),
## in the head frame FireHelmet uses, with FireHelmet's quad writer. One mesh per rig and colour,
## one draw, no shadow, gone past `DRAW_DISTANCE`; the hair goes under it (hidden).
##
## Original: plain shells, no unit patch or insignia.

## The shell's standoff off the skull (m) and the extra rise over the crown.
const STANDOFF := 0.024
const CROWN_RISE := 0.010
## The edge over the eyes: at the brow, over the ears (high cut) and at the nape (m above the eye
## line).
const EDGE_FRONT := 0.040
const EDGE_EAR := 0.060
const EDGE_BACK := -0.020
const TRIM := 0.012
const COLS := 36
const ROWS := 11
const DRAW_DISTANCE := 60.0

## The van's black and the agency's olive (shell), the trim and the metal.
const SHELL_BLACK := Color(0.055, 0.058, 0.062)
const SHELL_OLIVE := Color(0.20, 0.205, 0.13)
const RUBBER := Color(0.025, 0.025, 0.027)
const METAL := Color(0.12, 0.12, 0.125)
## The agency's field uniform (the character shader's garment colours, OfficerUniform's form).
const FIELD_TOP := Color(0.20, 0.215, 0.135)
const FIELD_TROUSERS := Color(0.15, 0.16, 0.10)

static var _meshes: Dictionary = {}
static var _mat: StandardMaterial3D


## Puts a helmet on the rig `inst` (an instance of the crowd rig at `rig`): olive for the agency,
## black for the tactical unit.
static func dress(inst: Node3D, rig: String, olive: bool) -> MeshInstance3D:
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or skel.find_bone("Head") < 0:
		return null
	var hb := skel.find_bone("Head")
	var unit := CrowdHat._unit(inst, skel)
	var rest := skel.get_bone_global_rest(hb)
	var att := BoneAttachment3D.new()
	att.name = "HelmetMount"
	skel.add_child(att)
	att.bone_name = "Head"
	var mi := MeshInstance3D.new()
	mi.name = "Helmet"
	mi.mesh = mesh_for(rig, olive)
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
		# A textured polymer shell: matte with a soft sheen.
		_mat.roughness = 0.72
		_mat.metallic_specular = 0.35
	return _mat


static func mesh_for(rig: String, olive: bool) -> ArrayMesh:
	var key := "%s|%d" % [rig.get_file(), int(olive)]
	if not _meshes.has(key):
		_meshes[key] = build_mesh(CrowdHat.head_for(rig), olive)
	return _meshes[key]


## The edge's height round azimuth `th` (head frame): the brow, cut up high over the ears, down
## at the nape.
static func edge_y(h: CrowdHat.Head, th: float) -> float:
	var back := (1.0 - cos(th)) * 0.5
	var y := h.eye_y + lerpf(EDGE_FRONT, EDGE_BACK, smoothstep(0.35, 0.95, back))
	var ear_th := atan2(h.ear.x, h.ear.z - h.c.z)
	var near := exp(-pow((absf(wrapf(th, -PI, PI)) - ear_th) / 0.55, 2.0))
	return lerpf(y, maxf(y, h.ear.y + EDGE_EAR - 0.035), near)


static func shell_point(h: CrowdHat.Head, th: float, ph: float, extra: float = 0.0) -> Vector3:
	var d := CrowdHat.Head.dir(th, ph)
	var r := h.radius(th, ph) + STANDOFF + clampf(h.hair(th, ph) * 0.3, 0.0, 0.01) + extra
	r += CROWN_RISE * smoothstep(0.7, 1.4, ph)
	return h.c + d * r


static func build_mesh(h: CrowdHat.Head, olive: bool) -> ArrayMesh:
	return build_surface(h, olive).commit()


## The helmet's triangles, not yet committed (the checks read them with commit_to_arrays()).
static func build_surface(h: CrowdHat.Head, olive: bool) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shell := SHELL_OLIVE if olive else SHELL_BLACK
	var center := h.c
	var grid: Array = []
	var phs: Array[float] = []
	for j in COLS + 1:
		var th := TAU * float(j) / float(COLS)
		var ph0 := h.phi_at_height(th, edge_y(h, th))
		phs.append(ph0)
		var col: Array[Vector3] = []
		for i in ROWS + 1:
			var f := float(i) / float(ROWS)
			var ph := lerpf(ph0, PI * 0.5 - 0.02, f * f * 0.3 + f * 0.7)
			col.append(shell_point(h, th, ph))
		grid.append(col)
	for j in COLS:
		for i in ROWS:
			FireHelmet._quad(st, grid[j][i], grid[j + 1][i], grid[j + 1][i + 1], grid[j][i + 1], shell, center, true)
	var top := shell_point(h, 0.0, PI * 0.5)
	for j in COLS:
		FireHelmet._tri(st, grid[j][ROWS], grid[j + 1][ROWS], top, shell, center, true)
	# The rubber trim: a band rolled over the edge, out and under.
	for j in COLS:
		var a: Vector3 = grid[j][0]
		var b: Vector3 = grid[j + 1][0]
		var oa := shell_point(h, TAU * float(j) / float(COLS), phs[j], 0.006)
		var ob := shell_point(h, TAU * float(j + 1) / float(COLS), phs[j + 1], 0.006)
		var da := oa + Vector3.DOWN * TRIM
		var db := ob + Vector3.DOWN * TRIM
		FireHelmet._quad(st, a, b, ob, oa, RUBBER, center, true)
		FireHelmet._quad(st, oa, ob, db, da, RUBBER, center, true)
		FireHelmet._quad(st, a - (a - center).normalized() * 0.012, b - (b - center).normalized() * 0.012, db, da, RUBBER, center, false)
	# The side rails: a raised strip along each side just over the edge, from the temple back.
	for side: float in [1.0, -1.0]:
		var rows: Array = []
		for k in 9:
			var th := side * lerpf(0.75, 2.35, float(k) / 8.0)
			var ph := h.phi_at_height(th, edge_y(h, th)) + 0.10
			var p0 := shell_point(h, th, ph, 0.002)
			var p1 := shell_point(h, th, ph + 0.11, 0.002)
			rows.append([p0, p1, shell_point(h, th, ph, 0.010), shell_point(h, th, ph + 0.11, 0.010)])
		for k in 8:
			var r0: Array = rows[k]
			var r1: Array = rows[k + 1]
			FireHelmet._quad(st, r0[2], r1[2], r1[3], r0[3], METAL, center, true)
			FireHelmet._quad(st, r0[0], r1[0], r1[2], r0[2], METAL, center, true)
			FireHelmet._quad(st, r0[3], r1[3], r1[1], r0[1], METAL, center, true)
		# Closed ends.
		var e0: Array = rows[0]
		var e1: Array = rows[8]
		FireHelmet._quad(st, e0[0], e0[2], e0[3], e0[1], METAL, center, true)
		FireHelmet._quad(st, e1[0], e1[1], e1[3], e1[2], METAL, center, true)
	# The night-vision mount: a plate on the front over the brow, a block standing on it.
	var pl: Array = []
	var ph_lo := h.phi_at_height(0.0, edge_y(h, 0.0)) + 0.03
	for i in 3:
		var row: Array[Vector3] = []
		for k in 4:
			var th := lerpf(-0.17, 0.17, float(k) / 3.0)
			row.append(shell_point(h, th, ph_lo + 0.08 * float(i), 0.004))
		pl.append(row)
	for i in 2:
		for k in 3:
			FireHelmet._quad(st, pl[i][k], pl[i][k + 1], pl[i + 1][k + 1], pl[i + 1][k], METAL, center, true)
	var mid := shell_point(h, 0.0, ph_lo + 0.06, 0.004)
	var out := (mid - center).normalized()
	var right := Vector3.UP.cross(out).normalized()
	var up := out.cross(right).normalized()
	_block(st, mid + out * 0.012, right * 0.018, up * 0.016, out * 0.012, RUBBER, center)
	return st


## A small box centred at `c` with half axes `a`, `b`, `n` (n outward).
static func _block(st: SurfaceTool, c: Vector3, a: Vector3, b: Vector3, n: Vector3, col: Color, _center: Vector3) -> void:
	var p := [c - a - b - n, c + a - b - n, c + a + b - n, c - a + b - n, c - a - b + n, c + a - b + n, c + a + b + n, c - a + b + n]
	var mid := c
	for f: Array in [[4, 5, 6, 7], [1, 2, 6, 5], [0, 4, 7, 3], [3, 7, 6, 2], [0, 1, 5, 4]]:
		FireHelmet._quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, mid, true)
