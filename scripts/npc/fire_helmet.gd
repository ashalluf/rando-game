class_name FireHelmet
extends RefCounted
## A structural firefighter's helmet (the traditional American shape: a tall glossy shell with a
## ridge front to back, a narrow front brim, a long sloping duckbill at the back, a leather front
## shield), modelled round each crowd rig's own head from CrowdHatTable's measurements (CrowdHat
## .head_for: the skull's radius round the head, the eyes, the ear tops), in the head frame CrowdHat
## uses (metres, skeleton axes, origin at the Head bone's rest; +Z the face). One mesh per rig and
## rank, shared by everyone wearing it; one draw, no shadow, gone past the crowd's accessory range.
## The hair goes under it (hidden, as a hat does where hair cannot be pressed).
##
## Original: no department's crest or number on the shield, which is plain leather in a brass rim.

## The shell stands this far off the skull (m): the suspension and the liner.
const STANDOFF := 0.030
## The band edge over the eyes at the front and round the back (m above the eye line).
const EDGE_FRONT := 0.030
const EDGE_BACK := -0.012
## Brim widths (m): front, sides, back (the duckbill), and how far the back drops.
const BRIM := Vector3(0.035, 0.055, 0.115)
const BRIM_DROP := 0.065
## The ridge: how high it stands and how wide (m).
const RIDGE_HEIGHT := 0.014
const RIDGE_WIDTH := 0.020
const COLS := 36
const ROWS := 12

const SHELL_YELLOW := Color(0.86, 0.62, 0.06)
const SHELL_WHITE := Color(0.92, 0.92, 0.89)
const TRIM := Color(0.04, 0.04, 0.04)
const LEATHER := Color(0.06, 0.05, 0.045)
const BRASS := Color(0.78, 0.60, 0.26)
const DRAW_DISTANCE := 60.0

static var _meshes: Dictionary = {}
static var _mat: StandardMaterial3D


## Puts a helmet on the rig `inst` (an instance of the crowd rig at `rig`), white for a captain.
static func dress(inst: Node3D, rig: String, captain: bool) -> MeshInstance3D:
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
	mi.mesh = mesh_for(rig, captain)
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
		_mat.roughness = 0.32
		_mat.clearcoat_enabled = true
		_mat.clearcoat = 0.6
		_mat.clearcoat_roughness = 0.15
	return _mat


static func mesh_for(rig: String, captain: bool) -> ArrayMesh:
	var key := "%s|%d" % [rig.get_file(), int(captain)]
	if not _meshes.has(key):
		_meshes[key] = build_mesh(CrowdHat.head_for(rig), captain)
	return _meshes[key]


## The band edge's height round azimuth `th` (head frame), never down on the ears.
static func edge_y(h: CrowdHat.Head, th: float) -> float:
	var y := h.eye_y + lerpf(EDGE_FRONT, EDGE_BACK, (1.0 - cos(th)) * 0.5)
	var ear_th := atan2(h.ear.x, h.ear.z - h.c.z)
	var near := exp(-pow((absf(wrapf(th, -PI, PI)) - ear_th) / 0.5, 2.0))
	return y + maxf(h.ear.y + 0.012 - y, 0.0) * near


## A point on the shell at azimuth `th`, elevation `ph`: the skull plus the standoff and the ridge.
static func shell_point(h: CrowdHat.Head, th: float, ph: float, extra: float = 0.0) -> Vector3:
	var d := CrowdHat.Head.dir(th, ph)
	var r := h.radius(th, ph) + STANDOFF + clampf(h.hair(th, ph) * 0.3, 0.0, 0.01) + extra
	# The ridge runs over the top front to back where the shell is narrowest across.
	var across := absf(sin(th)) * cos(ph) * r
	r += RIDGE_HEIGHT * exp(-pow(across / RIDGE_WIDTH, 2.0)) * smoothstep(0.1, 0.6, ph)
	# A taller crown than the skull's (the helmet's dome rises above the head).
	r += 0.012 * smoothstep(0.6, 1.4, ph)
	return h.c + d * r


static func build_mesh(h: CrowdHat.Head, captain: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shell := SHELL_WHITE if captain else SHELL_YELLOW
	# The shell: a grid from the band edge to the crown.
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
	var center := h.c
	for j in COLS:
		for i in ROWS:
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j + 1][i]
			var c: Vector3 = grid[j + 1][i + 1]
			var d: Vector3 = grid[j][i + 1]
			_quad(st, a, b, c, d, shell, center, true)
	# The crown cap closes the top.
	var top := shell_point(h, 0.0, PI * 0.5)
	for j in COLS:
		var a: Vector3 = grid[j][ROWS]
		var b: Vector3 = grid[j + 1][ROWS]
		_tri(st, a, b, top, shell, center, true)
	# The brim: out from the band edge, wide and sloping down at the back; a black edge roll.
	var mid_ring: Array[Vector3] = []
	var tip_ring: Array[Vector3] = []
	for j in COLS + 1:
		var th := TAU * float(j) / float(COLS)
		var back := (1.0 - cos(th)) * 0.5
		var w := lerpf(BRIM.x, BRIM.y, smoothstep(0.0, 0.5, back)) + (BRIM.z - BRIM.y) * smoothstep(0.55, 1.0, back)
		var out := Vector3(sin(th), 0.0, cos(th))
		var p0: Vector3 = edge_ring[j]
		var drop := BRIM_DROP * smoothstep(0.4, 1.0, back) + 0.006
		mid_ring.append(p0 + out * w * 0.55 + Vector3.DOWN * drop * 0.35)
		tip_ring.append(p0 + out * w + Vector3.DOWN * drop)
	for j in COLS:
		_quad(st, edge_ring[j], edge_ring[j + 1], mid_ring[j + 1], mid_ring[j], shell, center, true, true)
		_quad(st, mid_ring[j], mid_ring[j + 1], tip_ring[j + 1], tip_ring[j], shell, center, true, true)
		# Underside (the brim is a sheet: both faces), a little below, darker.
		var dn := Vector3.DOWN * 0.005
		_quad(st, edge_ring[j] + dn, mid_ring[j] + dn, mid_ring[j + 1] + dn, edge_ring[j + 1] + dn, shell.darkened(0.45), center, false, true)
		_quad(st, mid_ring[j] + dn, tip_ring[j] + dn, tip_ring[j + 1] + dn, mid_ring[j + 1] + dn, shell.darkened(0.45), center, false, true)
		# The rolled black edge.
		_quad(st, tip_ring[j], tip_ring[j + 1], tip_ring[j + 1] + dn * 1.6, tip_ring[j] + dn * 1.6, TRIM, center, true)
	# The front shield: a leather plate standing off the front of the shell, brass-rimmed.
	var sh_rows := 5
	var sh_cols := 6
	var ph_lo := h.phi_at_height(0.0, edge_y(h, 0.0)) + 0.06
	var ph_hi := ph_lo + 0.62
	var pts: Array = []
	for i in sh_rows + 1:
		var row: Array[Vector3] = []
		var f := float(i) / float(sh_rows)
		# Wider at the top, rounded: a shield's outline.
		var half := lerpf(0.20, 0.30, f) * (1.0 - 0.25 * pow(f, 6.0))
		for j in sh_cols + 1:
			var th := lerpf(-half, half, float(j) / float(sh_cols))
			row.append(shell_point(h, th, lerpf(ph_lo, ph_hi, f), 0.010))
		pts.append(row)
	for i in sh_rows:
		for j in sh_cols:
			var inner := i > 0 and i < sh_rows - 1 and j > 0 and j < sh_cols - 1
			_quad(st, pts[i][j], pts[i][j + 1], pts[i + 1][j + 1], pts[i + 1][j], LEATHER if inner else BRASS, center, true)
	return st.commit()


## A quad facing away from `center` (`outward`) or toward it, or up / down for the brim (`flat`:
## facing +Y when outward, -Y otherwise).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, center: Vector3, outward: bool, flat: bool = false) -> void:
	_tri(st, a, b, c, col, center, outward, flat)
	_tri(st, a, c, d, col, center, outward, flat)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, center: Vector3, outward: bool, flat: bool = false) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	var want := Vector3.UP if flat else ((a + b + c) / 3.0 - center).normalized()
	if not outward:
		want = -want
	# Godot's front faces wind clockwise seen from outside: the cross product points inward.
	if n.dot(want) > 0.0:
		var t := b
		b = c
		c = t
		n = -n
	for v: Vector3 in [a, b, c]:
		st.set_color(col)
		st.set_normal(-n)
		st.add_vertex(v)
