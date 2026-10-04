class_name CrowdHat
extends RefCounted
## The crowd's headwear, fitted to each rig's own head: a six-panel cotton-twill baseball cap
## (seams, eyelets, a button, a curved bill with rows of stitching and a taped edge, the
## sweatband, a strap across the opening at the back with a slide buckle), a ribbed knit beanie
## (a turned-up 2x2 rib cuff, a little slouch, the crown's decreases), a twill bucket hat and the
## police peaked cap (a black braid band, a flared navy crown, a patent peak, a chin strap and a
## badge). Built in code from tools/crowd/hat_fit.gd's measurement of the head
## (CrowdHatTable: a centre, the eyes, the ear tops, the skull's radius on a grid of directions,
## the hair's thickness over it), so each hat sits ON its head - down on the forehead, over the
## ear tops, round the back of the skull - with the cloth a couple of millimetres off the skin
## and room for the hair it presses flat. The fabric is shaders/crowd_hat.gdshader.
##
## Cost: one mesh per rig and kind, shared by every wearer, three levels in one vertex buffer
## (LODs at their geometric error); one material per colourway; one draw per wearer, never in a
## shadow pass, gone past Pedestrian.accessory_distance. The hair cards are pressed under the hat
## (pressed_hair(): the vertices under the crown moved inside it, the triangles left wholly
## inside dropped) so hair still shows below the band at the back and sides, or hidden where the
## rig's hair is too thick to press (the table's "hide").
##
## Everything is built in the HEAD FRAME: metres, the skeleton's axes (y up, z the way the rig
## faces), origin at the Head bone's rest position. dress() hangs it on a BoneAttachment3D with
## the transform that takes that frame into the bone's.
enum Kind {CAP, BEANIE, BUCKET, PEAKED}

## The shader's part ids (COLOR.r = (id + 0.5) / 16).
const PART_CROWN := 0
const PART_BRIM_TOP := 1
const PART_BRIM_UNDER := 2
const PART_INNER := 3
const PART_BUTTON := 4
const PART_STRAP := 5
const PART_METAL := 6
const PART_KNIT := 7
const PART_CUFF := 8
const PART_PATENT := 9
const PART_BINDING := 10
const PART_BAND := 11
const PART_POLICE_CROWN := 12

const SHADER := "res://shaders/crowd_hat.gdshader"
## Cloth thickness (metres): the outer face to the inner.
const FABRIC := 0.0016
## The reference radius round-the-head UVs are measured at (UV.x = angle x R_REF), so knit
## columns run straight up the head rather than shearing as the rings narrow.
const R_REF := 0.095
## Where the band edge sits, per kind, as height over the eye centre at the front and at the back
## (metres; the sides are between, and never below the ear tops plus EAR_CLEAR).
const EDGE := {
	Kind.CAP: Vector2(0.042, -0.012),
	Kind.BEANIE: Vector2(0.034, -0.034),
	Kind.BUCKET: Vector2(0.046, 0.004),
	Kind.PEAKED: Vector2(0.046, 0.021),
}
const EAR_CLEAR := {Kind.CAP: 0.007, Kind.BEANIE: 0.004, Kind.BUCKET: 0.008, Kind.PEAKED: 0.008}
const EDGE_SAMPLES := 96
## The cap's back: the opening over the strap (half-width in radians round the head, height in
## metres) and the strap's height.
const OPEN_HALF := 0.42
const OPEN_HEIGHT := 0.048
const STRAP_HEIGHT := 0.017
## The cap's bill: reach at its centre (metres, for a 0.2 m head), half-span round the band
## (radians), pitch down (radians), how far its sides curve down at the edge (metres), thickness.
const BILL_REACH := 0.072
const BILL_SPAN := 1.18
const BILL_PITCH := 0.21
const BILL_CURVE := 0.020
const BILL_THICK := 0.0034
## The beanie's cuff: its height up the head and how far it stands off the knit under it.
const CUFF_HEIGHT := 0.052
const CUFF_STANDOFF := 0.0036
## LOD levels (every 1st, 2nd and 4th row and column of each grid) and the geometric error each
## is used at (metres): the renderer switches when that is under a pixel.
const LEVELS := [0, 1, 2]
const LEVEL_EDGES := [0.0, 0.0018, 0.0055]

## Colourways, sRGB: [main, second (undervisor, strap, label), thread, mark thread]. Muted,
## team-less; the marks are four original shapes (the shader's mark_shape()).
const CAP_COLORS := [
	[Color(0.11, 0.13, 0.21), Color(0.27, 0.29, 0.26), Color(0.13, 0.15, 0.24), Color(0.80, 0.77, 0.68)],
	[Color(0.045, 0.045, 0.05), Color(0.05, 0.05, 0.055), Color(0.07, 0.07, 0.075), Color(0.82, 0.82, 0.80)],
	[Color(0.20, 0.20, 0.21), Color(0.14, 0.14, 0.15), Color(0.24, 0.24, 0.25), Color(0.62, 0.17, 0.14)],
	[Color(0.45, 0.45, 0.44), Color(0.32, 0.32, 0.31), Color(0.41, 0.41, 0.41), Color(0.12, 0.14, 0.24)],
	[Color(0.56, 0.50, 0.38), Color(0.45, 0.40, 0.30), Color(0.50, 0.45, 0.34), Color(0.25, 0.18, 0.12)],
	[Color(0.27, 0.28, 0.18), Color(0.20, 0.21, 0.14), Color(0.31, 0.31, 0.21), Color(0.78, 0.75, 0.64)],
	[Color(0.46, 0.15, 0.13), Color(0.30, 0.30, 0.29), Color(0.42, 0.15, 0.13), Color(0.86, 0.84, 0.80)],
	[Color(0.18, 0.26, 0.45), Color(0.27, 0.29, 0.27), Color(0.20, 0.28, 0.45), Color(0.86, 0.85, 0.82)],
	[Color(0.78, 0.75, 0.68), Color(0.30, 0.33, 0.28), Color(0.72, 0.69, 0.62), Color(0.12, 0.14, 0.24)],
	[Color(0.32, 0.23, 0.16), Color(0.25, 0.18, 0.12), Color(0.35, 0.26, 0.19), Color(0.80, 0.75, 0.64)],
	[Color(0.12, 0.22, 0.16), Color(0.10, 0.14, 0.11), Color(0.14, 0.24, 0.18), Color(0.80, 0.77, 0.68)],
	[Color(0.30, 0.09, 0.11), Color(0.22, 0.20, 0.20), Color(0.32, 0.11, 0.13), Color(0.82, 0.80, 0.74)],
]
const BEANIE_COLORS := [
	[Color(0.05, 0.05, 0.055), Color(0.82, 0.80, 0.74), Color(0.05, 0.05, 0.05), Color(0.06, 0.06, 0.06)],
	[Color(0.21, 0.21, 0.22), Color(0.05, 0.05, 0.05), Color(0.2, 0.2, 0.2), Color(0.80, 0.78, 0.72)],
	[Color(0.42, 0.41, 0.40), Color(0.06, 0.06, 0.06), Color(0.4, 0.4, 0.4), Color(0.80, 0.78, 0.72)],
	[Color(0.10, 0.12, 0.20), Color(0.80, 0.78, 0.72), Color(0.1, 0.12, 0.2), Color(0.10, 0.12, 0.20)],
	[Color(0.25, 0.27, 0.17), Color(0.06, 0.06, 0.06), Color(0.25, 0.27, 0.17), Color(0.78, 0.74, 0.62)],
	[Color(0.52, 0.38, 0.13), Color(0.06, 0.06, 0.06), Color(0.5, 0.36, 0.12), Color(0.80, 0.78, 0.72)],
	[Color(0.44, 0.20, 0.12), Color(0.80, 0.78, 0.72), Color(0.44, 0.2, 0.12), Color(0.12, 0.10, 0.09)],
	[Color(0.74, 0.70, 0.60), Color(0.12, 0.14, 0.22), Color(0.72, 0.68, 0.58), Color(0.80, 0.78, 0.72)],
	[Color(0.12, 0.21, 0.16), Color(0.80, 0.78, 0.72), Color(0.12, 0.21, 0.16), Color(0.12, 0.21, 0.16)],
	[Color(0.29, 0.09, 0.12), Color(0.06, 0.06, 0.06), Color(0.29, 0.09, 0.12), Color(0.80, 0.78, 0.72)],
]
const BUCKET_COLORS := [
	[Color(0.55, 0.49, 0.37), Color(0.55, 0.49, 0.37), Color(0.49, 0.44, 0.33), Color(0.25, 0.18, 0.12)],
	[Color(0.05, 0.05, 0.055), Color(0.05, 0.05, 0.055), Color(0.08, 0.08, 0.085), Color(0.80, 0.80, 0.78)],
	[Color(0.26, 0.27, 0.18), Color(0.26, 0.27, 0.18), Color(0.30, 0.30, 0.20), Color(0.78, 0.75, 0.64)],
	[Color(0.76, 0.73, 0.65), Color(0.76, 0.73, 0.65), Color(0.70, 0.67, 0.60), Color(0.12, 0.14, 0.24)],
	[Color(0.11, 0.13, 0.21), Color(0.11, 0.13, 0.21), Color(0.14, 0.16, 0.25), Color(0.80, 0.77, 0.68)],
	[Color(0.30, 0.37, 0.48), Color(0.30, 0.37, 0.48), Color(0.62, 0.50, 0.30), Color(0.84, 0.82, 0.78)],
]
## The police cap: its crown (PoliceOfficer.CAP_COLOR, written out here so this file needs no
## other class) and its badge.
const POLICE_NAVY := Color(0.07, 0.08, 0.14)
const POLICE_GOLD := Color(0.78, 0.62, 0.30)

static var _heads: Dictionary = {}
static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}
static var _hair: Dictionary = {}


## A rig's head as measured by hat_fit.gd (or a generic one where the table has no row).
class Head:
	var c := Vector3(0.0, 0.095, 0.03)
	var eye_y := 0.095
	var eye_z := 0.11
	var ear := Vector3(0.076, 0.104, 0.02)
	var top := 0.205
	var hide_hair := false
	var rows := 17
	var cols := 32
	var phi0 := deg_to_rad(-30.0)
	var phi_step := deg_to_rad(7.5)
	var skull := PackedFloat32Array()
	var hair_t := PackedFloat32Array()
	## Per kind, the band edge's elevation round the head (CrowdHat.edge_phi).
	var edges := {}

	## The two grids resampled twice as fine by Catmull-Rom (so the shell has no creases at the
	## table's grid lines: a midpoint is (-a + 9b + 9c - d) / 16 of its four neighbours), round
	## each ring and then up each meridian, and read bilinearly after: a hat is a few thousand
	## lookups.
	var _dr := 0
	var _dc := 0
	var _dskull := PackedFloat32Array()
	var _dhair := PackedFloat32Array()

	func densify() -> void:
		_dc = cols * 2
		_dr = (rows - 1) * 2 + 1
		_dskull = _up2(skull)
		_dhair = _up2(hair_t)
		for k in _dhair.size():
			_dhair[k] = maxf(_dhair[k], 0.0)

	func _up2(g: PackedFloat32Array) -> PackedFloat32Array:
		# Round each ring (closed).
		var wide := PackedFloat32Array()
		wide.resize(rows * _dc)
		for i in rows:
			var o := i * cols
			for j in cols:
				var b := g[o + j]
				var c2 := g[o + (j + 1) % cols]
				wide[i * _dc + 2 * j] = b
				wide[i * _dc + 2 * j + 1] = (-g[o + (j + cols - 1) % cols] + 9.0 * b + 9.0 * c2 - g[o + (j + 2) % cols]) / 16.0
		# Up each meridian (clamped at the ends).
		var out := PackedFloat32Array()
		out.resize(_dr * _dc)
		for i in rows:
			for j in _dc:
				var b := wide[i * _dc + j]
				out[2 * i * _dc + j] = b
				if i < rows - 1:
					var a := wide[maxi(i - 1, 0) * _dc + j]
					var c2 := wide[(i + 1) * _dc + j]
					var d := wide[mini(i + 2, rows - 1) * _dc + j]
					out[(2 * i + 1) * _dc + j] = (-a + 9.0 * b + 9.0 * c2 - d) / 16.0
		return out

	func _bilinear(g: PackedFloat32Array, th: float, ph: float) -> float:
		var x := fposmod(th, TAU) / TAU * float(_dc)
		var y := clampf((ph - phi0) / phi_step * 2.0, 0.0, float(_dr - 1) - 0.0001)
		var j0 := int(x)
		var i0 := int(y)
		var fx := x - float(j0)
		var fy := y - float(i0)
		var j1 := (j0 + 1) % _dc
		j0 = j0 % _dc
		var a := lerpf(g[i0 * _dc + j0], g[i0 * _dc + j1], fx)
		var b := lerpf(g[(i0 + 1) * _dc + j0], g[(i0 + 1) * _dc + j1], fx)
		return lerpf(a, b, fy)

	func radius(th: float, ph: float) -> float:
		return _bilinear(_dskull, th, ph)

	func hair(th: float, ph: float) -> float:
		return 0.0 if hide_hair else _bilinear(_dhair, th, ph)

	static func dir(th: float, ph: float) -> Vector3:
		return Vector3(sin(th) * cos(ph), sin(ph), cos(th) * cos(ph))

	## The elevation at which the skull, round azimuth `th`, reaches height `y`.
	func phi_at_height(th: float, y: float) -> float:
		var lo := phi0
		var hi := PI * 0.5
		for it in 12:
			var mid := (lo + hi) * 0.5
			if c.y + radius(th, mid) * sin(mid) < y:
				lo = mid
			else:
				hi = mid
		return (lo + hi) * 0.5

	## The head's length front to back (for scaling the bill).
	func length() -> float:
		return radius(0.0, 0.25) + radius(PI, 0.1)


## The head of the rig at `rig` (a .glb path), from the table, cached.
static func head_for(rig: String) -> Head:
	var key := rig.get_file()
	if _heads.has(key):
		return _heads[key]
	var h := Head.new()
	var row: Dictionary = CrowdHatTable.TABLE.get(key, {})
	h.rows = CrowdHatTable.ROWS
	h.cols = CrowdHatTable.COLS
	h.phi0 = deg_to_rad(CrowdHatTable.PHI0)
	h.phi_step = deg_to_rad(CrowdHatTable.PHI_STEP)
	if not row.is_empty():
		var cc: Array = row.c
		h.c = Vector3(cc[0], cc[1], cc[2])
		h.eye_y = row.eye[0]
		h.eye_z = row.eye[1]
		h.ear = Vector3(row.ear[1], row.ear[0], row.ear[2])
		h.top = row.top
		h.hide_hair = row.hair == "hide"
		h.skull.resize(h.rows * h.cols)
		h.hair_t.resize(h.rows * h.cols)
		var sk: Array = row.skull
		var ht: Array = row.hair_t
		for k in h.rows * h.cols:
			h.skull[k] = float(sk[k]) * 0.0001
			h.hair_t[k] = float(ht[k]) * 0.001
	else:
		# A generic adult head: an ellipsoid round the default centre.
		h.skull.resize(h.rows * h.cols)
		h.hair_t.resize(h.rows * h.cols)
		h.hair_t.fill(0.006)
		var axes := Vector3(0.078, 0.112, 0.10)
		for i in h.rows:
			for j in h.cols:
				var d := Head.dir(TAU * float(j) / float(h.cols), h.phi0 + h.phi_step * float(i))
				h.skull[i * h.cols + j] = 1.0 / sqrt(pow(d.x / axes.x, 2) + pow(d.y / axes.y, 2) + pow(d.z / axes.z, 2))
	h.densify()
	_heads[key] = h
	return h


## The band edge's height (head frame) round azimuth `th` for `kind`.
static func edge_y(h: Head, kind: int, th: float) -> float:
	var e: Vector2 = EDGE[kind]
	var y := h.eye_y + lerpf(e.x, e.y, (1.0 - cos(th)) * 0.5)
	# Never down on the ears: the band runs over their tops.
	var ear_th := atan2(h.ear.x, h.ear.z - h.c.z)
	var near := exp(-pow((absf(wrapf(th, -PI, PI)) - ear_th) / 0.5, 2.0))
	var need: float = h.ear.y + EAR_CLEAR[kind]
	return y + maxf(need - y, 0.0) * near


## The band edge's elevation round `th` (what the hat covers is above it). The cap's opening
## at the back is not in it: the hair is pressed under the strap's line all the same.
## Read off a table of EDGE_SAMPLES round the head, made the first time a kind asks: pressing
## the hair asks for every hair vertex.
static func edge_phi(h: Head, kind: int, th: float) -> float:
	var t: PackedFloat32Array = h.edges.get(kind, PackedFloat32Array())
	if t.is_empty():
		t.resize(EDGE_SAMPLES + 1)
		for i in EDGE_SAMPLES + 1:
			var a := -PI + TAU * float(i) / float(EDGE_SAMPLES)
			t[i] = h.phi_at_height(a, edge_y(h, kind, a))
		h.edges[kind] = t
	var x := (wrapf(th, -PI, PI) + PI) / TAU * float(EDGE_SAMPLES)
	var i0 := clampi(int(x), 0, EDGE_SAMPLES - 1)
	return lerpf(t[i0], t[i0 + 1], x - float(i0))


## How far the cloth stands off the skull, at (th, ph) and `s` up the crown: the cloth itself,
## room for the hair pressed under it, and the shape the kind gives the crown.
static func standoff(h: Head, kind: int, th: float, ph: float, s: float) -> float:
	var hair := h.hair(th, ph)
	match kind:
		Kind.BEANIE:
			var room := clampf(hair * 0.32, 0.0, 0.009)
			var loft := 0.005 * smoothstep(0.25, 1.0, s)
			var slouch := 0.011 * smoothstep(0.45, 1.0, s) * pow((1.0 - cos(th)) * 0.5, 1.5)
			return 0.0032 + room + loft + slouch
		Kind.CAP, Kind.BUCKET:
			# Pressed hardest at the band; a structured front panel stands up off the forehead.
			var room := clampf(hair * 0.28, 0.0, 0.008) * lerpf(0.55, 1.0, smoothstep(0.0, 0.3, s))
			var loft := 0.0032 * smoothstep(0.15, 1.0, s)
			var front := 0.0
			# Each panel stands a little proud between its seams (six round a cap from the front;
			# a bucket's four side panels from 45 degrees off it).
			var panel := PI / 3.0 if kind == Kind.CAP else PI * 0.5
			var f := fposmod(th - (0.0 if kind == Kind.CAP else PI * 0.25), panel) / panel
			var puff := 0.0011 * sin(PI * f) * smoothstep(0.04, 0.3, s) * (1.0 - smoothstep(0.8, 0.98, s))
			if kind == Kind.CAP:
				front = 0.0065 * pow(maxf(cos(th), 0.0), 3.0) * pow(sin(PI * clampf(s * 1.05, 0.0, 1.0)), 1.3)
			return 0.0024 + room + loft + front + puff
		_:
			return 0.0024 + clampf(hair * 0.3, 0.0, 0.008)


## The mesh of `kind` fitted to the rig at `rig`, shared by every wearer.
static func mesh_for(rig: String, kind: int) -> ArrayMesh:
	var key := "%s|%d" % [rig.get_file(), kind]
	if not _meshes.has(key):
		_meshes[key] = build_mesh(rig, kind)
	return _meshes[key]


## Builds the hats of the rig `inst` (an instance of the crowd rig at `rig`) now, and presses
## its hair under each: the crowd's three, and the police cap too for an `officer` rig. The
## loading screen, through Pedestrian.warm_far_mesh(), so nobody put on a hat later stalls the
## frame (~12 ms a hat and ~10 ms of hair pressing a kind here).
static func warm(inst: Node3D, rig: String, officer: bool) -> void:
	var kinds: Array = [Kind.CAP, Kind.BEANIE, Kind.BUCKET]
	if officer:
		kinds.append(Kind.PEAKED)
	for k: int in kinds:
		mesh_for(rig, k)
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or skel.find_bone("Head") < 0 or head_for(rig).hide_hair:
		return
	var unit := _unit(inst, skel)
	for hmi in inst.find_children("Hair*", "MeshInstance3D", true, false):
		_press(hmi as MeshInstance3D, skel, rig, kinds, unit)


## Triangles per level of a hat mesh (the fit report and the checks).
static func lod_triangles(mesh: ArrayMesh) -> Array:
	return mesh.get_meta("level_tris", []) if mesh else []


## One vertex buffer, every level's triangles over it: LOD0 is the whole hat, the coarser levels
## take every second or fourth row and column of the same grids and leave the small parts out.
static func build_mesh(rig: String, kind: int) -> ArrayMesh:
	var h := head_for(rig)
	var b := Buf.new()
	match kind:
		Kind.CAP:
			_cap(b, h)
		Kind.BEANIE:
			_beanie(b, h)
		Kind.BUCKET:
			_bucket(b, h)
		Kind.PEAKED:
			_peaked(b, h)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = b.v
	arrays[Mesh.ARRAY_NORMAL] = b.n
	arrays[Mesh.ARRAY_TEX_UV] = b.uv
	arrays[Mesh.ARRAY_COLOR] = b.col
	arrays[Mesh.ARRAY_INDEX] = b.lv[0]
	var lods := {}
	var tris: Array = []
	for l in LEVELS:
		tris.append((b.lv[l] as PackedInt32Array).size() / 3)
		if l > 0:
			lods[float(LEVEL_EDGES[l])] = b.lv[l]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	mesh.set_meta("level_tris", tris)
	return mesh


## The vertices and each level's triangles, and the grid patches that fill them.
class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var lv: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]

	## A grid of `rows` x `cols` points (row-major `p`), with its UVs and colours. Normals come
	## from the grid itself (along its columns crossed with along its rows; where a row has
	## shrunk to a point, a crown's pole, the next row decides), all turned one way for the whole
	## grid: away from `ref` for most of its vertices (toward it when `inward`). Turned vertex by
	## vertex, a flare whose normal runs across the line to `ref` came out with every other
	## triangle facing in. Triangles are wound to match (Godot's front faces are clockwise).
	## `closed`: the last column repeats the first (a ring with its UV seam there), so their
	## normals are worked out across the seam and match. `strides`: per level, every how many
	## rows and columns that level keeps (0 leaves the grid out of it); a grid's last row and
	## column are always kept.
	func grid(rows: int, cols: int, p: PackedVector3Array, uvs: PackedVector2Array, cs: PackedColorArray,
			ref: Vector3, inward: bool = false, closed: bool = false, strides: Array = [1, 2, 4]) -> void:
		var base := v.size()
		var vote := 0.0
		for i in rows:
			for j in cols:
				var k := i * cols + j
				var jl := maxi(j - 1, 0)
				var jr := mini(j + 1, cols - 1)
				if closed:
					jl = cols - 2 if j == 0 else j - 1
					jr = 1 if j == cols - 1 else j + 1
				var dv := p[mini(i + 1, rows - 1) * cols + j] - p[maxi(i - 1, 0) * cols + j]
				var du := p[i * cols + jr] - p[i * cols + jl]
				if du.length_squared() < 1e-14:
					var i2 := i - 1 if i > 0 else i + 1
					du = p[i2 * cols + jr] - p[i2 * cols + jl]
				var nn := du.cross(dv).normalized()
				vote += signf((p[k] - ref).dot(nn))
				v.append(p[k])
				n.append(nn)
				uv.append(uvs[k])
				col.append(cs[k])
		# The vote: do these normals (along-columns x along-rows) face the way asked?
		var flip := (vote >= 0.0) == inward
		if flip:
			for k in range(base, v.size()):
				n[k] = -n[k]
		for l in strides.size():
			var st: int = strides[l]
			if st <= 0:
				continue
			var ri := _keep(rows, st)
			var ci := _keep(cols, st)
			for a in ri.size() - 1:
				for c in ci.size() - 1:
					var p00 := base + ri[a] * cols + ci[c]
					var p01 := base + ri[a] * cols + ci[c + 1]
					var p11 := base + ri[a + 1] * cols + ci[c + 1]
					var p10 := base + ri[a + 1] * cols + ci[c]
					# (p01 - p00) x (p11 - p00) runs with the unflipped normals; a front face is
					# clockwise, so its cross product points away from the side it faces.
					if flip:
						_quad_tri(l, p00, p01, p11)
						_quad_tri(l, p00, p11, p10)
					else:
						_quad_tri(l, p00, p11, p01)
						_quad_tri(l, p00, p10, p11)

	func _quad_tri(l: int, a: int, b: int, c: int) -> void:
		if (v[b] - v[a]).cross(v[c] - v[a]).length_squared() < 1e-16:
			return
		lv[l].append(a)
		lv[l].append(b)
		lv[l].append(c)

	static func _keep(count: int, st: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		var i := 0
		while i < count - 1:
			out.append(i)
			i += st
		out.append(count - 1)
		return out

	## One triangle into level `l`, wound to face its vertices' normals; none where it has no area.
	func tri(l: int, a: int, b: int, c: int) -> void:
		var va := v[a]
		var fn := (v[b] - va).cross(v[c] - va)
		if fn.length_squared() < 1e-16:
			return
		# Appended in place: a packed array taken out of the Array into a variable is a copy.
		lv[l].append(a)
		if fn.dot(n[a] + n[b] + n[c]) < 0.0:
			lv[l].append(b)
			lv[l].append(c)
		else:
			lv[l].append(c)
			lv[l].append(b)

	## A box with its own axes (half extents along `ex`, `ey`, `ez`), flat-shaded, in the levels
	## of `levels`.
	func box(centre: Vector3, ex: Vector3, ey: Vector3, ez: Vector3, colour: Color, levels: Array = [0]) -> void:
		for f: Array in [[ex, ey, ez], [ex, ey, -ez], [ey, ez, ex], [ey, ez, -ex], [ex, ez, ey], [ex, ez, -ey]]:
			var a: Vector3 = f[0]
			var b2: Vector3 = f[1]
			var off: Vector3 = f[2]
			var normal := off.normalized()
			var cn := centre + off
			var base := v.size()
			var corners := [cn - a - b2, cn + a - b2, cn + a + b2, cn - a + b2]
			for q in 4:
				v.append(corners[q])
				n.append(normal)
				uv.append(Vector2(float(q % 2) * 0.01, float(q / 2) * 0.01))
				col.append(colour)
			for l: int in levels:
				tri(l, base, base + 1, base + 2)
				tri(l, base, base + 2, base + 3)


static func _c(part: int, occ: float, param: float, ring: float = 0.0) -> Color:
	return Color((float(part) + 0.5) / 16.0, occ, param, clampf(ring / 0.25, 0.0, 1.0))


## The `s` up the crown round `th` that lies `metres` of cloth above the band edge: marched up
## in steps of 0.025 and interpolated in the step that passes it.
static func _s_at_arc(h: Head, kind: int, th: float, pe: float, metres: float) -> float:
	var arc := 0.0
	var prev := _point(h, kind, th, pe, 0.0)
	var s := 0.0
	while s < 0.95:
		var s2 := s + 0.025
		var q := _point(h, kind, th, lerpf(pe, PI * 0.5, s2), s2)
		var step := q.distance_to(prev)
		if arc + step >= metres:
			return s + 0.025 * (metres - arc) / maxf(step, 1e-6)
		arc += step
		prev = q
		s = s2
	return 0.95


static func _point(h: Head, kind: int, th: float, ph: float, s: float, dr: float = 0.0) -> Vector3:
	return h.c + Head.dir(th, ph) * (h.radius(th, ph) + standoff(h, kind, th, ph, s) + dr)


## The angle of column `j` of `cols` round a closed ring that starts and ends at the back.
static func _col_th(j: int, cols: int) -> float:
	return -PI + TAU * float(j) / float(cols - 1)


## The cap's band edge round `th`, raised into the arch of the opening at the back.
static func _cap_edge(h: Head, th: float) -> float:
	var y := edge_y(h, Kind.CAP, th)
	var d := (PI - absf(th)) / OPEN_HALF
	var arch := OPEN_HEIGHT * sqrt(maxf(0.0, 1.0 - pow(d, 4.0))) if d < 1.0 else 0.0
	return h.phi_at_height(th, y + arch)


## A baseball cap.
static func _cap(b: Buf, h: Head) -> void:
	var cols := 6 * 6 + 1
	var rows := 13
	var p := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cs := PackedColorArray()
	p.resize(rows * cols)
	uvs.resize(p.size())
	cs.resize(p.size())
	for j in cols:
		var th := _col_th(j, cols)
		var pe := _cap_edge(h, th)
		var arc := 0.0
		var prev := Vector3.ZERO
		for i in rows:
			var s := float(i) / float(rows - 1)
			var ph := lerpf(pe, PI * 0.5, s)
			var r := h.radius(th, ph) + standoff(h, Kind.CAP, th, ph, s)
			var q := h.c + Head.dir(th, ph) * r
			if i > 0:
				arc += q.distance_to(prev)
			prev = q
			p[i * cols + j] = q
			uvs[i * cols + j] = Vector2(th * R_REF, arc)
			cs[i * cols + j] = _c(PART_CROWN, 1.0, s, r * cos(ph))
	b.grid(rows, cols, p, uvs, cs, h.c, false, true)
	# The sweatband inside, the lowest 28 mm, and the edge rolled between it and the crown.
	var ci := 6 * 3 + 1
	var sb := PackedVector3Array()
	var sb_uv := PackedVector2Array()
	var sb_c := PackedColorArray()
	var lip := PackedVector3Array()
	var lip_uv := PackedVector2Array()
	var lip_c := PackedColorArray()
	sb.resize(3 * ci)
	sb_uv.resize(sb.size())
	sb_c.resize(sb.size())
	lip.resize(3 * ci)
	lip_uv.resize(lip.size())
	lip_c.resize(lip.size())
	for j in ci:
		var th := _col_th(j, ci)
		var pe := _cap_edge(h, th)
		var s_top := _s_at_arc(h, Kind.CAP, th, pe, 0.028)
		for i in 3:
			var s := s_top * float(i) / 2.0
			var k := i * ci + j
			sb[k] = _point(h, Kind.CAP, th, lerpf(pe, PI * 0.5, s), s, -FABRIC)
			sb_uv[k] = Vector2(th * R_REF, 0.014 * float(i))
			sb_c[k] = _c(PART_INNER, 0.55, s)
		var o := _point(h, Kind.CAP, th, pe, 0.0)
		var inn := _point(h, Kind.CAP, th, pe, 0.0, -FABRIC)
		var down := (_point(h, Kind.CAP, th, pe - 0.03, 0.0) - o).normalized()
		lip[j] = o
		lip[ci + j] = (o + inn) * 0.5 + down * FABRIC * 0.55
		lip[2 * ci + j] = inn
		for r in 3:
			lip_uv[r * ci + j] = Vector2(th * R_REF, -0.001 * float(r))
			lip_c[r * ci + j] = _c(PART_CROWN if r == 0 else PART_INNER, 0.85, 0.0, 0.1)
	b.grid(3, ci, sb, sb_uv, sb_c, h.c, true, true, [1, 2, 0])
	b.grid(3, ci, lip, lip_uv, lip_c, h.c + Vector3(0.0, 0.3, 0.0), false, true, [1, 2, 4])
	# The button on top.
	var tp := _point(h, Kind.CAP, 0.0, PI * 0.5, 1.0)
	var up := (tp - h.c).normalized()
	_dome(b, tp - up * 0.0006, up, 0.0085, 0.0042, 12, 3, PART_BUTTON, [1, 2, 0])
	_cap_strap(b, h)
	_bill(b, h, Kind.CAP, BILL_REACH * h.length() / 0.2, BILL_SPAN, BILL_PITCH, BILL_CURVE, BILL_THICK,
		PART_BRIM_TOP, PART_BRIM_UNDER)


## The strap at the back of a cap: a band over the bottom of the opening, tucked under the
## panels either side of it, with a slide buckle on one side.
static func _cap_strap(b: Buf, h: Head) -> void:
	var cols := 17
	var half := OPEN_HALF * 1.32
	var p := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cs := PackedColorArray()
	p.resize(3 * cols)
	uvs.resize(p.size())
	cs.resize(p.size())
	var along := 0.0
	var prev := Vector3.ZERO
	for j in cols:
		# Round the back through th = PI.
		var th := wrapf(PI - half + 2.0 * half * float(j) / float(cols - 1), -PI, PI)
		var d := absf(PI - absf(th)) / OPEN_HALF
		var proud := lerpf(0.0014, -0.0012, smoothstep(0.85, 1.15, d))
		var y0 := edge_y(h, Kind.CAP, th)
		for i in 3:
			var y := y0 + STRAP_HEIGHT * float(i) / 2.0
			var pt := _point(h, Kind.CAP, th, h.phi_at_height(th, y), 0.05, proud)
			var k := i * cols + j
			p[k] = pt
			if i == 0:
				if j > 0:
					along += pt.distance_to(prev)
				prev = pt
			uvs[k] = Vector2(along, STRAP_HEIGHT * float(i) / 2.0)
			cs[k] = _c(PART_STRAP, 0.9, float(i) / 2.0)
	b.grid(3, cols, p, uvs, cs, h.c, false, false, [1, 2, 4])
	# The buckle: a small slide frame on the wearer's left of the opening.
	var th := PI - OPEN_HALF * 0.55
	var ph := h.phi_at_height(th, edge_y(h, Kind.CAP, th) + STRAP_HEIGHT * 0.5)
	var pt := _point(h, Kind.CAP, th, ph, 0.05, 0.0026)
	var out := pt - h.c
	out.y = 0.0
	out = out.normalized()
	var side := Vector3.UP.cross(out).normalized()
	b.box(pt, side * 0.0075, Vector3.UP * 0.0115, out * 0.0011, _c(PART_METAL, 1.0, 0.0), [0])


## A small dome (a cap's button, a police cap's strap buttons): base centre `at`, axis `up`.
static func _dome(b: Buf, at: Vector3, up: Vector3, radius: float, height: float, seg: int, rings: int,
		part: int, strides: Array) -> void:
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up).normalized()
	var rows := rings + 1
	var cols := seg + 1
	var p := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cs := PackedColorArray()
	p.resize(rows * cols)
	uvs.resize(p.size())
	cs.resize(p.size())
	for i in rows:
		var t := float(i) / float(rings)
		var a := t * PI * 0.5
		for j in cols:
			var u := TAU * float(j) / float(seg)
			p[i * cols + j] = at + (side * cos(u) + fwd * sin(u)) * (radius * cos(a)) + up * (height * sin(a))
			uvs[i * cols + j] = Vector2(u * radius, t * radius)
			cs[i * cols + j] = _c(part, 0.95, t)
	b.grid(rows, cols, p, uvs, cs, at - up * 0.02, false, true, strides)


## A bill or peak along the front of the band: from `span` either side of the front, reaching
## `reach` at its centre, pitched down by `pitch`, its sides curving down by `curve` at the edge,
## `thick` deep, with a taped edge rolled round it.
static func _bill(b: Buf, h: Head, kind: int, reach: float, span: float, pitch: float,
		curve: float, thick: float, top_part: int, under_part: int) -> void:
	var cols := 21
	var rows := 6
	var top := PackedVector3Array()
	var top_uv := PackedVector2Array()
	var top_c := PackedColorArray()
	top.resize(rows * cols)
	top_uv.resize(top.size())
	top_c.resize(top.size())
	var reaches := PackedFloat32Array()
	reaches.resize(cols)
	var outward: Array[Vector3] = []
	var roots: Array[Vector3] = []
	for j in cols:
		var t := -1.0 + 2.0 * float(j) / float(cols - 1)
		var th := t * span
		var pe := edge_phi(h, kind, th)
		# Sewn under the band: the bill's root is just inside the crown and a little up.
		roots.append(_point(h, kind, th, pe, 0.0, -0.0011) + Vector3(0.0, 0.0016, 0.0))
		outward.append(Vector3(sin(th), 0.0, cos(th)).lerp(Vector3(0.0, 0.0, 1.0), 0.35).normalized())
		reaches[j] = reach * pow(maxf(0.0, 1.0 - pow(absf(t), 2.4)), 0.6)
	for i in rows:
		var w := float(i) / float(rows - 1)
		# A bill is not flat across its depth: it crowns a little in the middle of its reach.
		var bow := 0.0025 * sin(PI * w)
		for j in cols:
			var t := -1.0 + 2.0 * float(j) / float(cols - 1)
			top[i * cols + j] = roots[j] + outward[j] * reaches[j] * w \
				+ Vector3(0.0, -tan(pitch) * reaches[j] * w - curve * t * t * w + bow * (1.0 - t * t), 0.0)
	# Arc length along the outer edge from its middle, for the stitch dashes.
	var edge_len := PackedFloat32Array()
	edge_len.resize(cols)
	var mid := cols / 2
	var e0 := (rows - 1) * cols
	for j in range(mid + 1, cols):
		edge_len[j] = edge_len[j - 1] + top[e0 + j].distance_to(top[e0 + j - 1])
	for j in range(mid - 1, -1, -1):
		edge_len[j] = edge_len[j + 1] - top[e0 + j].distance_to(top[e0 + j + 1])
	for i in rows:
		var w := float(i) / float(rows - 1)
		for j in cols:
			top_uv[i * cols + j] = Vector2(edge_len[j], reaches[j] * (1.0 - w))
			top_c[i * cols + j] = _c(top_part, lerpf(0.85, 1.0, w), w)
	b.grid(rows, cols, top, top_uv, top_c, h.c + Vector3(0.0, -0.4, 0.15))
	# The underside, `thick` under the top along its normals.
	var base := b.v.size() - top.size()
	var under := PackedVector3Array()
	var under_c := PackedColorArray()
	under.resize(top.size())
	under_c.resize(top.size())
	for k in top.size():
		under[k] = top[k] - b.n[base + k] * thick
		var w := float(k / cols) / float(rows - 1)
		under_c[k] = _c(under_part, lerpf(0.55, 0.92, w), w)
	b.grid(rows, cols, under, top_uv, under_c, h.c + Vector3(0.0, 0.4, 0.15))
	# The taped edge: a half-round from the top's edge to the underside's, standing out a little.
	var seg := 5
	var tape := PackedVector3Array()
	var tape_uv := PackedVector2Array()
	var tape_c := PackedColorArray()
	tape.resize(seg * cols)
	tape_uv.resize(tape.size())
	tape_c.resize(tape.size())
	var bind_part := PART_BINDING if top_part == PART_BRIM_TOP else top_part
	var centre := PackedVector3Array()
	for j in cols:
		var k := e0 + j
		var nrm: Vector3 = b.n[base + k]
		var outd := (top[k] - top[k - cols]).normalized()
		outd = (outd - nrm * outd.dot(nrm)).normalized()
		var ctr := (top[k] + under[k]) * 0.5
		centre.append(ctr)
		for s in seg:
			var ang := PI * float(s) / float(seg - 1)
			tape[s * cols + j] = ctr + nrm * (thick * 0.5 * cos(ang)) + outd * (thick * 0.62 * sin(ang))
			tape_uv[s * cols + j] = Vector2(edge_len[j], float(s) * 0.001)
			tape_c[s * cols + j] = _c(bind_part, 0.95, float(s) / float(seg - 1))
	# Each tape vertex faces away from the edge's own centre line.
	var tb := b.v.size()
	b.grid(seg, cols, tape, tape_uv, tape_c, h.c, false, false, [1, 2, 4])
	for s in seg:
		for j in cols:
			var k := tb + s * cols + j
			var nn := (b.v[k] - centre[j]).normalized()
			b.n[k] = nn


## A cuffed knit beanie.
static func _beanie(b: Buf, h: Head) -> void:
	var cols := 6 * 6 + 1
	var rows := 13
	var edge := PackedFloat32Array()
	var s_cuff := PackedFloat32Array()
	edge.resize(cols)
	s_cuff.resize(cols)
	for j in cols:
		var th := _col_th(j, cols)
		edge[j] = edge_phi(h, Kind.BEANIE, th)
		s_cuff[j] = _s_at_arc(h, Kind.BEANIE, th, edge[j], CUFF_HEIGHT)
	# The knit from just under the cuff's top to the crown.
	var p := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cs := PackedColorArray()
	p.resize(rows * cols)
	uvs.resize(p.size())
	cs.resize(p.size())
	for j in cols:
		var th := _col_th(j, cols)
		var s0 := s_cuff[j] * 0.88
		var arc := CUFF_HEIGHT * 0.88
		var prev := Vector3.ZERO
		for i in rows:
			var s := lerpf(s0, 1.0, float(i) / float(rows - 1))
			var ph := lerpf(edge[j], PI * 0.5, s)
			var r := h.radius(th, ph) + standoff(h, Kind.BEANIE, th, ph, s)
			var pt := h.c + Head.dir(th, ph) * r
			if i > 0:
				arc += pt.distance_to(prev)
			prev = pt
			p[i * cols + j] = pt
			uvs[i * cols + j] = Vector2(th * R_REF, arc)
			cs[i * cols + j] = _c(PART_KNIT, 1.0, s, r * cos(ph))
	b.grid(rows, cols, p, uvs, cs, h.c, false, true)
	# The cuff: from inside the knit round its folded lower edge, up the outside, its top rolled
	# back in onto the knit.
	var crows := 7
	var all_rows := 2 + crows + 3
	var cp := PackedVector3Array()
	var cuv := PackedVector2Array()
	var cc := PackedColorArray()
	cp.resize(all_rows * cols)
	cuv.resize(cp.size())
	cc.resize(cp.size())
	for j in cols:
		var th := _col_th(j, cols)
		var pe := edge[j]
		var pin := _point(h, Kind.BEANIE, th, lerpf(pe, PI * 0.5, 0.05), 0.05, -0.0006)
		var pout := _point(h, Kind.BEANIE, th, pe, 0.0, CUFF_STANDOFF)
		var at_edge := _point(h, Kind.BEANIE, th, pe, 0.0)
		var down := (_point(h, Kind.BEANIE, th, pe - 0.03, 0.0) - at_edge).normalized()
		cp[j] = pin
		cp[cols + j] = (at_edge + pout) * 0.5 + down * CUFF_STANDOFF * 0.5
		for i in crows:
			var s := s_cuff[j] * float(i) / float(crows - 1)
			cp[(2 + i) * cols + j] = _point(h, Kind.BEANIE, th, lerpf(pe, PI * 0.5, s), s, CUFF_STANDOFF)
		var st := s_cuff[j]
		cp[(2 + crows) * cols + j] = _point(h, Kind.BEANIE, th, lerpf(pe, PI * 0.5, st * 1.025), st * 1.025, CUFF_STANDOFF * 0.75)
		cp[(3 + crows) * cols + j] = _point(h, Kind.BEANIE, th, lerpf(pe, PI * 0.5, st * 1.045), st * 1.045, CUFF_STANDOFF * 0.3)
		cp[(4 + crows) * cols + j] = _point(h, Kind.BEANIE, th, lerpf(pe, PI * 0.5, st * 1.08), st * 1.08, -0.0005)
		for i in all_rows:
			var f := clampf(float(i - 2) / float(crows - 1), 0.0, 1.06)
			cuv[i * cols + j] = Vector2(th * R_REF, CUFF_HEIGHT * f)
			var occ := 0.7 if i < 2 else (0.82 if i >= 2 + crows else 1.0)
			cc[i * cols + j] = _c(PART_CUFF, occ, clampf(f, 0.0, 1.0), 0.1)
	b.grid(all_rows, cols, cp, cuv, cc, h.c, false, true)


## A bucket hat: a crown of four side panels and a round top, and a sloping brim all round.
static func _bucket(b: Buf, h: Head) -> void:
	var cols := 4 * 9 + 1
	var wall := 6
	var corner := 3
	var topr := 5
	var rows := wall + corner + topr + 1
	var p := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cs := PackedColorArray()
	p.resize(rows * cols)
	uvs.resize(p.size())
	cs.resize(p.size())
	var y_top := h.top + 0.010 + clampf(h.hair(0.0, PI * 0.5) * 0.3, 0.0, 0.008)
	var centre := Vector3(h.c.x, y_top + 0.004, h.c.z - 0.004)
	var edge_pts: Array[Vector3] = []
	for j in cols:
		var th := _col_th(j, cols)
		var e := _point(h, Kind.BUCKET, th, edge_phi(h, Kind.BUCKET, th), 0.0)
		edge_pts.append(e)
		var o := Vector3(sin(th), 0.0, cos(th))
		var rho_e := Vector2(e.x - h.c.x, e.z - h.c.z).length()
		# The side wall tapers in a little to a rounded corner, then the top runs in to its middle.
		var rho_w := rho_e * 0.9
		var corner_r := 0.012
		var arc := 0.0
		var prev := e
		for i in rows:
			var pt: Vector3
			var s: float
			if i <= wall:
				var t := float(i) / float(wall)
				var y := lerpf(e.y, y_top - corner_r, t)
				var rho := lerpf(rho_e, rho_w, t) + 0.004 * sin(PI * t)
				# Never inside the head.
				var ph := h.phi_at_height(th, y)
				rho = maxf(rho, (h.radius(th, ph) + 0.004) * cos(ph))
				pt = Vector3(h.c.x, y, h.c.z) + o * rho
				s = 0.78 * t
			elif i <= wall + corner:
				# The corner: a quarter round, where the top is sewn to the side panels.
				var t := float(i - wall) / float(corner)
				var ang := t * PI * 0.5
				pt = Vector3(h.c.x, y_top - corner_r + corner_r * sin(ang), h.c.z) + o * (rho_w - corner_r + corner_r * cos(ang))
				s = lerpf(0.78, 0.80, t)
			else:
				var t := float(i - wall - corner) / float(topr)
				pt = (Vector3(h.c.x, y_top, h.c.z) + o * (rho_w - corner_r)).lerp(centre, t)
				pt.y += 0.004 * sin(t * PI * 0.5)
				s = lerpf(0.8, 1.0, t)
			if i > 0:
				arc += pt.distance_to(prev)
			prev = pt
			p[i * cols + j] = pt
			uvs[i * cols + j] = Vector2(th * R_REF, arc)
			cs[i * cols + j] = _c(PART_CROWN, 1.0, s, Vector2(pt.x - h.c.x, pt.z - h.c.z).length())
	b.grid(rows, cols, p, uvs, cs, h.c, false, true)
	# The brim, all round, 55 mm out and down.
	var brows := 6
	var width := 0.052
	var thick := 0.003
	var top := PackedVector3Array()
	var tuv := PackedVector2Array()
	var tc := PackedColorArray()
	top.resize(brows * cols)
	tuv.resize(top.size())
	tc.resize(top.size())
	for j in cols:
		var th := _col_th(j, cols)
		var o := Vector3(sin(th), 0.0, cos(th))
		var e: Vector3 = edge_pts[j] - o * 0.0018 + Vector3(0.0, 0.0012, 0.0)
		var wave := 0.004 * sin(3.0 * th + 0.6) + 0.002 * sin(5.0 * th + 1.9)
		for i in brows:
			var w := float(i) / float(brows - 1)
			var k := i * cols + j
			top[k] = e + o * (width * w) + Vector3(0.0, -(width * (0.36 * w + 0.10 * w * w) + wave * w * w), 0.0)
			tuv[k] = Vector2(th * (0.1 + width), width * (1.0 - w))
			tc[k] = _c(PART_BRIM_TOP, lerpf(0.82, 1.0, w), w)
	b.grid(brows, cols, top, tuv, tc, h.c + Vector3(0.0, -0.6, 0.0), false, true)
	var base := b.v.size() - top.size()
	var under := PackedVector3Array()
	var uc := PackedColorArray()
	under.resize(top.size())
	uc.resize(top.size())
	for k in top.size():
		under[k] = top[k] - b.n[base + k] * thick
		uc[k] = _c(PART_BRIM_UNDER, lerpf(0.5, 0.85, float(k / cols) / float(brows - 1)), float(k / cols) / float(brows - 1))
	b.grid(brows, cols, under, tuv, uc, h.c + Vector3(0.0, 0.5, 0.0), false, true)
	var seg := 5
	var tape := PackedVector3Array()
	var tape_uv := PackedVector2Array()
	var tape_c := PackedColorArray()
	tape.resize(seg * cols)
	tape_uv.resize(tape.size())
	tape_c.resize(tape.size())
	var centres := PackedVector3Array()
	var e0 := (brows - 1) * cols
	for j in cols:
		var k := e0 + j
		var nrm: Vector3 = b.n[base + k]
		var outd := (top[k] - top[k - cols]).normalized()
		outd = (outd - nrm * outd.dot(nrm)).normalized()
		var ctr := (top[k] + under[k]) * 0.5
		centres.append(ctr)
		for s in seg:
			var ang := PI * float(s) / float(seg - 1)
			tape[s * cols + j] = ctr + nrm * (thick * 0.5 * cos(ang)) + outd * (thick * 0.6 * sin(ang))
			tape_uv[s * cols + j] = Vector2(_col_th(j, cols) * (0.1 + width), float(s) * 0.001)
			tape_c[s * cols + j] = _c(PART_BINDING, 0.95, float(s) / float(seg - 1))
	var tb := b.v.size()
	b.grid(seg, cols, tape, tape_uv, tape_c, h.c, false, true, [1, 2, 4])
	for s in seg:
		for j in cols:
			b.n[tb + s * cols + j] = (b.v[tb + s * cols + j] - centres[j]).normalized()


## The police peaked cap.
static func _peaked(b: Buf, h: Head) -> void:
	var cols := 37
	var band_rows := 4
	var flare_rows := 5
	var top_rows := 5
	var band_h := 0.036
	var rows := band_rows + flare_rows + top_rows
	var p := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cs := PackedColorArray()
	p.resize(rows * cols)
	uvs.resize(p.size())
	cs.resize(p.size())
	var top_y := 0.0
	for j in cols:
		top_y = maxf(top_y, edge_y(h, Kind.PEAKED, _col_th(j, cols)))
	top_y = maxf(top_y + band_h + 0.032, h.top + 0.018)
	var centre := Vector3(h.c.x, top_y + 0.004, h.c.z + 0.006)
	for j in cols:
		var th := _col_th(j, cols)
		var o := Vector3(sin(th), 0.0, cos(th))
		var y0 := edge_y(h, Kind.PEAKED, th)
		var arc := 0.0
		var prev := Vector3.ZERO
		var band_top := Vector3.ZERO
		for i in band_rows:
			var pt := _band_point(h, th, y0 + band_h * float(i) / float(band_rows - 1))
			if i > 0:
				arc += pt.distance_to(prev)
			prev = pt
			band_top = pt
			p[i * cols + j] = pt
			uvs[i * cols + j] = Vector2(th * R_REF, arc)
			cs[i * cols + j] = _c(PART_BAND, 1.0, float(i) / float(band_rows - 1) * 0.3, 0.1)
		# The crown flares out from the band to a rim, higher at the front.
		var rho_b := Vector2(band_top.x - h.c.x, band_top.z - h.c.z).length()
		var rim_rho := rho_b + 0.014 + 0.006 * maxf(cos(th), 0.0)
		var rim_y := top_y - 0.010 + 0.010 * (cos(th) + 1.0) * 0.5
		var ctrl := Vector2(rho_b + 0.013, band_top.y + 0.008)
		var a := Vector2(rho_b, band_top.y)
		var c2 := Vector2(rim_rho, rim_y)
		for i in flare_rows:
			var t := float(i + 1) / float(flare_rows)
			var bz := a.lerp(ctrl, t).lerp(ctrl.lerp(c2, t), t)
			var pt := Vector3(h.c.x, bz.y, h.c.z) + o * bz.x
			arc += pt.distance_to(prev)
			prev = pt
			var k := (band_rows + i) * cols + j
			p[k] = pt
			uvs[k] = Vector2(th * R_REF, arc)
			cs[k] = _c(PART_POLICE_CROWN, 1.0, lerpf(0.3, 0.75, t), bz.x)
		var rim := prev
		for i in top_rows:
			var t := float(i + 1) / float(top_rows)
			var pt := rim.lerp(centre, t)
			pt.y += 0.004 * sin(t * PI * 0.5)
			arc += pt.distance_to(prev)
			prev = pt
			var k := (band_rows + flare_rows + i) * cols + j
			p[k] = pt
			uvs[k] = Vector2(th * R_REF, arc)
			cs[k] = _c(PART_POLICE_CROWN, 1.0, lerpf(0.78, 1.0, t), Vector2(pt.x - h.c.x, pt.z - h.c.z).length())
	var nb := band_rows * cols
	b.grid(band_rows, cols, p.slice(0, nb), uvs.slice(0, nb), cs.slice(0, nb), h.c, false, true)
	# The crown starts again from the band's top row, so no triangle is half band, half crown.
	var cp := p.slice(nb - cols)
	var cuv := uvs.slice(nb - cols)
	var cc := cs.slice(nb - cols)
	for j in cols:
		cc[j] = _c(PART_POLICE_CROWN, 1.0, 0.3, Vector2(cp[j].x - h.c.x, cp[j].z - h.c.z).length())
	b.grid(rows - band_rows + 1, cols, cp, cuv, cc, h.c, false, true)
	# The lip under the band.
	var lip := PackedVector3Array()
	var luv := PackedVector2Array()
	var lc := PackedColorArray()
	lip.resize(2 * cols)
	luv.resize(lip.size())
	lc.resize(lip.size())
	for j in cols:
		var th := _col_th(j, cols)
		var pe := h.phi_at_height(th, edge_y(h, Kind.PEAKED, th))
		lip[j] = p[j]
		lip[cols + j] = _point(h, Kind.PEAKED, th, pe, 0.0, -FABRIC * 1.5)
		luv[j] = Vector2(th * R_REF, 0.0)
		luv[cols + j] = Vector2(th * R_REF, -0.002)
		lc[j] = _c(PART_INNER, 0.6, 0.0)
		lc[cols + j] = _c(PART_INNER, 0.5, 0.0)
	b.grid(2, cols, lip, luv, lc, h.c + Vector3(0.0, 0.3, 0.0), false, true)
	# The peak: short, stiff and steep.
	_bill(b, h, Kind.PEAKED, 0.052 * h.length() / 0.2, 1.26, 0.50, 0.006, 0.003, PART_PATENT, PART_PATENT)
	# The chin strap across the band's front, and the buttons that hold it.
	var scols := 17
	var sp := PackedVector3Array()
	var suv := PackedVector2Array()
	var sc := PackedColorArray()
	sp.resize(2 * scols)
	suv.resize(sp.size())
	sc.resize(sp.size())
	for j in scols:
		var th := lerpf(-1.32, 1.32, float(j) / float(scols - 1))
		var y0 := edge_y(h, Kind.PEAKED, th) + 0.006
		for i in 2:
			sp[i * scols + j] = _band_point(h, th, y0 + 0.010 * float(i), 0.0012)
			suv[i * scols + j] = Vector2(th * R_REF, 0.01 * float(i))
			sc[i * scols + j] = _c(PART_PATENT, 0.9, float(i))
	b.grid(2, scols, sp, suv, sc, h.c, false, false, [1, 2, 4])
	for side: float in [-1.0, 1.0]:
		var th := 1.36 * side
		var at := _band_point(h, th, edge_y(h, Kind.PEAKED, th) + 0.011, 0.0016)
		var out := at - h.c
		out.y = 0.0
		_dome(b, at, out.normalized(), 0.0055, 0.0026, 8, 2, PART_METAL, [1, 0, 0])
	# The badge on the crown's front over the band.
	var y_b := edge_y(h, Kind.PEAKED, 0.0) + band_h + 0.012
	# Laid on the crown's own slope there, so the shield sits on the cloth rather than through it.
	var front := cols / 2
	var bi := band_rows
	for i in range(band_rows, rows - 1):
		if absf(p[i * cols + front].y - y_b) < absf(p[bi * cols + front].y - y_b):
			bi = i
	var pb := p[bi * cols + front]
	var up := (p[(bi + 1) * cols + front] - p[(bi - 1) * cols + front]).normalized()
	var nrm := up.cross(Vector3.RIGHT).normalized()
	if nrm.dot(pb - h.c) < 0.0:
		nrm = -nrm
	_badge(b, pb + nrm * 0.0008, up.cross(nrm).normalized(), up, nrm)


## A point on the police cap's band round `th` at height `y`: on the head, but standing straight
## (a band is stiff: no narrower toward its top than the head at its foot), `out` metres proud.
static func _band_point(h: Head, th: float, y: float, out: float = 0.0) -> Vector3:
	var foot := _point(h, Kind.PEAKED, th, h.phi_at_height(th, edge_y(h, Kind.PEAKED, th)), 0.0)
	var pt := _point(h, Kind.PEAKED, th, h.phi_at_height(th, y), 0.0)
	var o := Vector3(sin(th), 0.0, cos(th))
	var rho := maxf(Vector2(pt.x - h.c.x, pt.z - h.c.z).length(), Vector2(foot.x - h.c.x, foot.z - h.c.z).length() * 0.985)
	return Vector3(h.c.x, pt.y, h.c.z) + o * (rho + out)


## A shield badge: a pointed-bottom plate a few millimetres thick (LOD0 and LOD1).
static func _badge(b: Buf, at: Vector3, right: Vector3, up: Vector3, out: Vector3) -> void:
	var outline := [Vector2(-0.013, 0.016), Vector2(0.0, 0.019), Vector2(0.013, 0.016), Vector2(0.0135, 0.002),
		Vector2(0.008, -0.010), Vector2(0.0, -0.017), Vector2(-0.008, -0.010), Vector2(-0.0135, 0.002)]
	var depth := 0.0022
	var col := _c(PART_METAL, 1.0, 0.0)
	var front := at + out * depth
	var base := b.v.size()
	b.v.append(front + up * 0.002)
	b.n.append(out)
	b.uv.append(Vector2.ZERO)
	b.col.append(col)
	for pt: Vector2 in outline:
		b.v.append(front + right * pt.x + up * pt.y)
		b.n.append((out * 0.85 + (right * pt.x + up * pt.y).normalized() * 0.15).normalized())
		b.uv.append(pt)
		b.col.append(col)
	for i in outline.size():
		for l in [0, 1]:
			b.tri(l, base, base + 1 + i, base + 1 + (i + 1) % outline.size())
	# The rim, edge-on.
	for i in outline.size():
		var a: Vector2 = outline[i]
		var c2: Vector2 = outline[(i + 1) % outline.size()]
		var pa := at + right * a.x + up * a.y
		var pc := at + right * c2.x + up * c2.y
		var en := (right * (c2.y - a.y) - up * (c2.x - a.x)).normalized()
		if en.dot(right * (a.x + c2.x) + up * (a.y + c2.y)) < 0.0:
			en = -en
		var k := b.v.size()
		for v3: Vector3 in [pa, pc, pc + out * depth, pa + out * depth]:
			b.v.append(v3)
			b.n.append(en)
			b.uv.append(Vector2.ZERO)
			b.col.append(col)
		b.tri(0, k, k + 1, k + 2)
		b.tri(0, k, k + 2, k + 3)


## The material for `kind` in colourway `pick` (any int: its bits choose the colours and mark).
## `worn`: a rough sleeper's - the colours dulled toward a grey-brown, the top sun-faded, the band
## dark with grime.
static func material(kind: int, pick: int, worn: bool = false) -> ShaderMaterial:
	var pal: Array = CAP_COLORS
	match kind:
		Kind.BEANIE:
			pal = BEANIE_COLORS
		Kind.BUCKET:
			pal = BUCKET_COLORS
	var ci := posmod(pick, pal.size())
	var bits := absi(pick) / 16
	var mk := 0
	match kind:
		Kind.CAP:
			# Half the caps plain, the rest with one of three small marks.
			mk = 0 if bits % 2 == 0 else 1 + (bits / 2) % 3
		Kind.BEANIE:
			mk = 4 if bits % 3 == 0 else 0
		Kind.BUCKET:
			mk = 0 if bits % 3 != 0 else 1 + (bits / 3) % 2
		Kind.PEAKED:
			ci = 0
	var key := "%d|%d|%d|%d" % [kind, ci, mk, int(worn)]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("kind", kind)
	if kind == Kind.PEAKED:
		m.set_shader_parameter("main_color", POLICE_NAVY)
		m.set_shader_parameter("second_color", Color(0.05, 0.05, 0.06))
		m.set_shader_parameter("thread_color", POLICE_NAVY.lightened(0.05))
		m.set_shader_parameter("metal_color", POLICE_GOLD)
		m.set_shader_parameter("panels", 1.0)
		m.set_shader_parameter("cotton_rough", 0.82)
		m.set_shader_parameter("twill_pitch", 0.0007)
		m.set_shader_parameter("wear", 0.0)
	else:
		var c: Array = pal[ci]
		m.set_shader_parameter("main_color", c[0])
		m.set_shader_parameter("second_color", c[1])
		m.set_shader_parameter("thread_color", c[2])
		m.set_shader_parameter("mark_color", c[3])
		m.set_shader_parameter("mark", mk)
		m.set_shader_parameter("panels", 4.0 if kind == Kind.BUCKET else 6.0)
		m.set_shader_parameter("seam_offset", PI * 0.25 if kind == Kind.BUCKET else 0.0)
		m.set_shader_parameter("metal_color", Color(0.58, 0.55, 0.50))
		if worn:
			var dull := Color(0.30, 0.27, 0.23)
			for slot: String in ["main_color", "second_color", "thread_color", "mark_color"]:
				var c0: Color = m.get_shader_parameter(slot)
				m.set_shader_parameter(slot, c0.lerp(dull, 0.45).darkened(0.12))
			m.set_shader_parameter("wear", 0.9)
			m.set_shader_parameter("grime", 0.8)
	_mats[key] = m
	return m


## Puts a hat of `kind` on the rig `inst` (an instance of the crowd rig at `rig`), in colourway
## `pick`, and presses or hides its hair. Returns the hat's MeshInstance3D, or null when the rig
## has no head bone. `distance` is how far it draws.
static func dress(inst: Node3D, rig: String, kind: int, pick: int, distance: float) -> MeshInstance3D:
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return null
	var hb := skel.find_bone("Head")
	if hb < 0:
		return null
	# The skeleton works in centimetres under a 0.01 armature: the head frame is metres.
	var unit := _unit(inst, skel)
	var rest := skel.get_bone_global_rest(hb)
	var att := BoneAttachment3D.new()
	att.name = "HatMount"
	skel.add_child(att)
	att.bone_name = "Head"
	var mi := MeshInstance3D.new()
	mi.name = "Hat"
	mi.mesh = mesh_for(rig, kind)
	mi.material_override = material(kind, pick)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = distance
	# The head frame into the bone's: skeleton space is rest.origin + frame / unit, the bone's
	# space that through the rest's inverse.
	mi.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE / maxf(unit, 1e-6)), rest.origin)
	att.add_child(mi)
	_press_hair(inst, skel, rig, kind, unit)
	return mi


## Presses each hair mesh of `inst` under the hat, or hides it where the rig's hair is too thick to
## press or there is no mesh data to press (the headless check).
static func _press_hair(inst: Node3D, skel: Skeleton3D, rig: String, kind: int, unit: float) -> void:
	var h := head_for(rig)
	for node in inst.find_children("Hair*", "MeshInstance3D", true, false):
		var hmi := node as MeshInstance3D
		var pressed: Mesh = null if h.hide_hair else pressed_hair(hmi, skel, rig, kind, unit)
		if pressed == null:
			hmi.visible = false
			hmi.set_meta("under_hat", true)
		else:
			hmi.mesh = pressed


## The hair mesh of `hmi` with every card under the crown of a `kind` hat pressed inside its
## inner surface (fully above the band edge, easing out over the few centimetres below it, so
## the hair shows where it comes out from under the band), the triangles left wholly inside the
## hat dropped, and a fringe hanging from under it slid in whole. Strands standing far
## off the scalp (a ponytail out through the opening, a braid) are left as they are. Shared per
## hair mesh, rig and kind; null without mesh data (the headless check), where dress() hides the
## hair instead.
static func pressed_hair(hmi: MeshInstance3D, skel: Skeleton3D, rig: String, kind: int, unit: float) -> Mesh:
	if hmi.mesh == null:
		return null
	var key := _hair_key(hmi.mesh, rig, kind)
	if not _hair.has(key):
		_press(hmi, skel, rig, [kind], unit)
	return _hair.get(key)


static func _hair_key(mesh: Mesh, rig: String, kind: int) -> String:
	return "%s|%d|%d" % [rig.get_file(), kind, mesh.get_rid().get_id()]


## The skeleton's scale chain up to the rig's root (0.01: centimetres under the armature).
static func _unit(inst: Node3D, skel: Skeleton3D) -> float:
	var unit := 1.0
	var node: Node3D = skel
	while node != null and node != inst:
		unit *= node.transform.basis.get_scale().y
		node = node.get_parent() as Node3D
	return unit


## Presses `hmi`'s hair for every kind in `kinds` in one pass over its vertices (what the kinds
## share - where each vertex is round the head, the skull and hair there, which card it is on -
## is worked out once) and caches the results.
static func _press(hmi: MeshInstance3D, skel: Skeleton3D, rig: String, kinds: Array, unit: float) -> void:
	var src := hmi.mesh
	for k: int in kinds:
		_hair[_hair_key(src, rig, k)] = null
	if src == null or hmi.skin == null:
		return
	var arrays := src.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_INDEX] == null:
		return
	var hb := skel.find_bone("Head")
	var bind := -1
	for i in hmi.skin.get_bind_count():
		if String(hmi.skin.get_bind_name(i)) == "Head":
			bind = i
	if hb < 0 or bind < 0:
		return
	var rest := skel.get_bone_global_rest(hb)
	# Mesh space to the head frame, in the rest pose (where every bind takes a vertex to the same
	# place, so the Head's serves for all).
	var to_frame := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * unit), -rest.origin * unit) * rest * hmi.skin.get_bind_pose(bind)
	var from_frame := to_frame.affine_inverse()
	var h := head_for(rig)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var n := verts.size()
	var dirs := PackedVector3Array()
	var rads := PackedFloat32Array()
	var ths := PackedFloat32Array()
	var phs := PackedFloat32Array()
	var skull := PackedFloat32Array()
	var ys := PackedFloat32Array()
	dirs.resize(n)
	rads.resize(n)
	ths.resize(n)
	phs.resize(n)
	skull.resize(n)
	ys.resize(n)
	for v in n:
		var p := to_frame * verts[v]
		var d := p - h.c
		var r := maxf(d.length(), 1e-5)
		d /= r
		dirs[v] = d
		rads[v] = r
		ths[v] = atan2(d.x, d.z)
		phs[v] = asin(clampf(d.y, -1.0, 1.0))
		skull[v] = h.radius(ths[v], phs[v])
		ys[v] = p.y
	# Each card is a connected piece of the hair mesh.
	var root := PackedInt32Array()
	root.resize(n)
	for v in n:
		root[v] = v
	for t in idx.size() / 3:
		var a := _find(root, idx[t * 3])
		for k in [1, 2]:
			var b := _find(root, idx[t * 3 + k])
			if a != b:
				root[b] = a
	for v in n:
		root[v] = _find(root, v)
	# The importer's LODs index the same vertices: kept, less the same triangles.
	var src_lods: Array = []
	var surf := RenderingServer.mesh_get_surface(src.get_rid(), 0)
	for lod: Dictionary in surf.get("lods", []):
		var data: PackedByteArray = lod.get("index_data", PackedByteArray())
		var li := PackedInt32Array()
		if n <= 65535:
			li.resize(data.size() / 2)
			for k in li.size():
				li[k] = data.decode_u16(k * 2)
		else:
			li = data.to_int32_array()
		src_lods.append([float(lod.get("edge_length", 0.0)), li])
	var flags: int = src.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	for kind: int in kinds:
		var out_v := verts.duplicate()
		var inside := PackedByteArray()
		inside.resize(n)
		# Which cards start under the crown, and which hang in front of the face below the band:
		# a card that does both is a fringe, and it slides in under the hat whole - every vertex
		# moved in by the most any of its vertices under the crown stands out of the hat - so it
		# keeps its shape and still hangs where the hair style hangs it. Pressed only where it is
		# under the hat it bunched into a dark slab over the eyes; laid flat on the skin it was an
		# eye patch; dropped, it left the scalp painted under it showing as a smudge.
		var under := {}
		var front := {}
		var lift := {}
		# Per vertex: how much it is under the hat (w) and the room inside the hat over it.
		var ws := PackedFloat32Array()
		var rooms := PackedFloat32Array()
		ws.resize(n)
		rooms.resize(n)
		for v in n:
			var pe := edge_phi(h, kind, ths[v])
			var ph := phs[v]
			ws[v] = smoothstep(pe - 0.035 / maxf(rads[v], 0.05), pe + 0.015, ph)
			if ws[v] > 0.0:
				var s := clampf((ph - pe) / maxf(PI * 0.5 - pe, 0.1), 0.0, 1.0)
				rooms[v] = skull[v] + standoff(h, kind, ths[v], ph, s) - FABRIC - 0.0012
			if ph >= pe:
				under[root[v]] = true
				lift[root[v]] = maxf(float(lift.get(root[v], 0.0)), rads[v] - rooms[v])
			elif absf(ths[v]) < 1.0 and ys[v] > h.eye_y - 0.03:
				front[root[v]] = true
		for v in n:
			var r := rads[v]
			if r < 0.02:
				continue
			if under.has(root[v]) and front.has(root[v]):
				var r2 := maxf(r - clampf(float(lift.get(root[v], 0.0)), 0.0, 0.012), skull[v] + 0.0008)
				out_v[v] = from_frame * (h.c + dirs[v] * minf(r, r2))
				continue
			var w := ws[v]
			if w <= 0.0:
				continue
			var excess := r - rooms[v]
			if excess <= 0.0:
				if w >= 1.0:
					inside[v] = 1
				continue
			# A strand well off the scalp is a ponytail or a braid going out through the back.
			var t := w * (1.0 - smoothstep(0.026, 0.04, excess))
			out_v[v] = from_frame * (h.c + dirs[v] * (r - excess * t))
			if t >= 0.999:
				inside[v] = 1
		var kept := _drop_inside(idx, inside)
		if kept.is_empty():
			continue
		var out_arrays := arrays.duplicate()
		out_arrays[Mesh.ARRAY_VERTEX] = out_v
		out_arrays[Mesh.ARRAY_INDEX] = kept
		var lods := {}
		for lod: Array in src_lods:
			var lk := _drop_inside(lod[1], inside)
			if not lk.is_empty():
				lods[lod[0]] = lk
		var out := ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays, [], lods, flags)
		out.surface_set_material(0, src.surface_get_material(0))
		out.resource_name = src.resource_name + "_under_hat"
		_hair[_hair_key(src, rig, kind)] = out


## Union-find's root of `v` (no path compression: a packed array argument is not the caller's
## to write, and a hair card is a few dozen vertices).
static func _find(root: PackedInt32Array, v: int) -> int:
	while root[v] != v:
		v = root[v]
	return v


static func _drop_inside(idx: PackedInt32Array, inside: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		if inside[a] == 1 and inside[b] == 1 and inside[c] == 1:
			continue
		out.append(a)
		out.append(b)
		out.append(c)
	return out
