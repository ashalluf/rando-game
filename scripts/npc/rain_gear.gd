class_name RainGear
extends RefCounted
## What the crowd puts on when it rains (RainCrowd): umbrellas and hoods, built in code at real
## size on one shader (shaders/rain_gear.gdshader).
##
## UMBRELLAS: a full-size stick umbrella (eight steel ribs, a 1.05 m canopy, a curved crook
## handle in wood or black plastic) and a compact folding one (seven ribs, 0.95 m, a straight
## rubber grip). Each is built in its own frame - metres, origin at the middle of the hand's grip,
## +Y up the shaft - at OPEN_STEPS opening amounts (0 furled and strapped, 1 open): the ribs swing
## from hanging down the shaft to the canopy's dome, the runner slides up the shaft, the
## stretchers follow, the gores sag between the ribs and fold in as it closes. Opening or folding
## swaps through the steps in about half a second (RainCrowd), so nobody needs a per-instance
## uniform (the Compatibility renderer's global buffer, CLAUDE.md "Car glass and drivers").
## ~1.6k triangles open; one draw per holder, no shadow pass (an umbrella's shadow is the one
## thing a street in the rain does not have: the light is overcast).
##
## HOODS: a jacket's hood up over the head, fitted to each rig's own skull from CrowdHatTable
## (the hats' measurement, CrowdHat.head_for()): a loose shell standing a couple of centimetres
## off the skull and the hair, open at the face in an oval from the brow to under the chin, with
## a rolled hem round the opening and a drape down the back of the neck into the collar. Built in
## the hats' HEAD FRAME (metres, skeleton axes, origin at the Head bone's rest) and hung the way
## CrowdHat.dress() hangs a hat. ~1.1k triangles, one mesh per rig.
##
## Vertex colour: rgb unused (white), alpha the PART (P_*); UV the fabric coordinates (x round the
## canopy in gores / round the hood in metres, y out along a rib / down the hood in metres).

const P_FABRIC := 0.0
const P_RIB := 1.0
const P_HANDLE := 2.0
const P_TIP := 3.0
const P_HOOD := 4.0
const P_HEM := 5.0
const P_STRAP := 6.0

const SHADER := "res://shaders/rain_gear.gdshader"

## Opening amounts each umbrella is built at (0 furled .. 1 open).
const OPEN_STEPS := 7

enum Kind { STICK, COMPACT }
## Per kind: ribs, rib length (m, apex to tip along the curve), shaft top (apex height over the
## grip), the canopy's dome (rib angle from straight up at the apex and at the tip, degrees).
const SPECS := {
	Kind.STICK: {"ribs": 8, "rib": 0.56, "apex": 0.74, "a0": 72.0, "a1": 112.0, "tip": 0.09},
	Kind.COMPACT: {"ribs": 7, "rib": 0.50, "apex": 0.62, "a0": 70.0, "a1": 106.0, "tip": 0.03},
}

## Canopy colourways: [main, second, pattern]. Pattern 0 plain, 1 alternate gores in `second`,
## 2 a band round the edge in `second`. Linear colours; most umbrellas on a city street are black
## or navy, then a few colours.
const CANOPY_COLORS := [
	[Color(0.012, 0.012, 0.014), Color(0.012, 0.012, 0.014), 0],
	[Color(0.012, 0.012, 0.014), Color(0.012, 0.012, 0.014), 0],
	[Color(0.012, 0.012, 0.014), Color(0.012, 0.012, 0.014), 0],
	[Color(0.008, 0.014, 0.04), Color(0.008, 0.014, 0.04), 0],
	[Color(0.008, 0.014, 0.04), Color(0.008, 0.014, 0.04), 0],
	[Color(0.03, 0.03, 0.034), Color(0.03, 0.03, 0.034), 0],
	[Color(0.30, 0.012, 0.014), Color(0.30, 0.012, 0.014), 0],
	[Color(0.012, 0.035, 0.018), Color(0.012, 0.035, 0.018), 0],
	[Color(0.55, 0.40, 0.03), Color(0.55, 0.40, 0.03), 0],
	[Color(0.012, 0.012, 0.014), Color(0.55, 0.55, 0.52), 1],
	[Color(0.30, 0.012, 0.014), Color(0.62, 0.60, 0.56), 1],
	[Color(0.008, 0.014, 0.04), Color(0.55, 0.42, 0.04), 2],
	[Color(0.012, 0.012, 0.014), Color(0.40, 0.012, 0.016), 2],
	[Color(0.06, 0.018, 0.08), Color(0.06, 0.018, 0.08), 0],
	[Color(0.40, 0.11, 0.02), Color(0.40, 0.11, 0.02), 0],
	[Color(0.18, 0.20, 0.22), Color(0.18, 0.20, 0.22), 0],
]
## A hood's colour when the jacket under it keeps its own photographed colour (linear).
const HOOD_DEFAULT := Color(0.025, 0.026, 0.03)

## The hood: how far its cloth stands off the skull and hair (m) at the crown, at the back and
## round the face; the face opening's half width (radians round the head) and how high it reaches
## over the eyes (m); how far the drape runs down the neck (m) below the table's lowest ring.
const HOOD_STANDOFF := Vector3(0.016, 0.034, 0.012)
const HOOD_OPEN_HALF := 0.98
const HOOD_OPEN_TOP := 0.062
const HOOD_DRAPE := 0.13
const HOOD_HEM := 0.011

static var _umbrellas: Dictionary = {}
static var _hoods: Dictionary = {}
static var _mats: Dictionary = {}
static var _shader: Shader


# --- Umbrellas ---------------------------------------------------------------------------------

## The umbrella of `kind` at opening step `step` (0 .. OPEN_STEPS - 1), shared.
static func umbrella(kind: int, step: int) -> ArrayMesh:
	step = clampi(step, 0, OPEN_STEPS - 1)
	var key := kind * 100 + step
	if not _umbrellas.has(key):
		_umbrellas[key] = build_umbrella(kind, float(step) / float(OPEN_STEPS - 1))
	return _umbrellas[key]


## Every umbrella mesh now (the loading screen: ~3 ms an umbrella here).
static func warm() -> void:
	for k in [Kind.STICK, Kind.COMPACT]:
		for s in OPEN_STEPS:
			umbrella(k, s)


## How far the canopy reaches out from the shaft when open (m): RainCrowd keeps it clear of walls.
static func canopy_radius(kind: int) -> float:
	var sp: Dictionary = SPECS[kind]
	return float(sp.rib) * 0.93


## Height of the canopy's apex over the grip (m).
static func apex_height(kind: int) -> float:
	return float(SPECS[kind].apex)


static func build_umbrella(kind: int, open: float) -> ArrayMesh:
	var sp: Dictionary = SPECS[kind]
	var n: int = sp.ribs
	var rib_len: float = sp.rib
	var apex: float = sp.apex
	var b := _Buf.new()
	# How open it is, eased: the ribs swing out fast once the runner leaves the bottom notch.
	var f := smoothstep(0.0, 1.0, open)
	# The rib's angle from straight up along its length: open it is the dome (a0 at the apex,
	# a1 at the tip); furled it hangs down the shaft (176 degrees), curling in a little at the tip.
	var rows := 9
	var rib_pts: Array[PackedVector2Array] = []   # per row: (radius, height) of the rib
	var prof := PackedVector2Array()
	var p := Vector2(0.0, apex)
	prof.append(p)
	for r in range(1, rows + 1):
		var s := (float(r) - 0.5) / float(rows)
		var a_open := lerpf(float(sp.a0), float(sp.a1), pow(s, 1.25))
		var a_shut := 176.0 - 6.0 * s
		var a := deg_to_rad(lerpf(a_shut, a_open, f))
		p += Vector2(sin(a), cos(a)) * (rib_len / float(rows))
		prof.append(p)
	rib_pts.append(prof)
	# The canopy: a grid per gore, rows out along the ribs, columns across the gore. The cloth
	# sags between the ribs (taut, a few centimetres at the hem) and, furled, folds in toward the
	# shaft between them.
	var cols := 6
	var gore := TAU / float(n)
	for g in n:
		var pts := PackedVector3Array()
		var uvs := PackedVector2Array()
		for r in rows + 1:
			var rad := prof[r].x
			var hy := prof[r].y
			var s := float(r) / float(rows)
			for c in cols + 1:
				var t := float(c) / float(cols)
				var th := (float(g) + t) * gore
				var mid := sin(PI * t)
				# Open: the chord between rib tips, bowed a touch out (the cloth is taut) and dropped
				# (the hem scallops between the tips). Furled: pulled in to the shaft, the fold.
				var chord := cos(gore * 0.5) / cos((t - 0.5) * gore)
				var radial := rad * lerpf(1.0, chord, 1.0) * (1.0 + 0.025 * mid * s * f)
				radial = lerpf(radial * (1.0 - 0.75 * mid * (1.0 - f)), radial, f)
				var drop := 0.035 * mid * pow(s, 2.0) * f
				pts.append(Vector3(sin(th) * radial, hy - drop, cos(th) * radial))
				uvs.append(Vector2(float(g) + t, s))
		b.grid(rows + 1, cols + 1, pts, uvs, P_FABRIC, Vector3(0.0, apex - 0.3, 0.0), false)
	# The ribs under the cloth, the tips' caps, the stretchers from the runner, the shaft, the
	# ferrule on top and the handle.
	var runner_y := lerpf(0.16, apex - 0.24, f)
	for g in n:
		var th := float(g) * gore
		var dir := Vector3(sin(th), 0.0, cos(th))
		var rib := PackedVector3Array()
		for r in rows + 1:
			rib.append(dir * prof[r].x + Vector3(0.0, prof[r].y - 0.006, 0.0))
		b.tube(rib, 0.0022, 4, P_RIB)
		var tip := rib[rows]
		b.tube(PackedVector3Array([tip, tip + (tip - rib[rows - 1]).normalized() * 0.016]), 0.0042, 6, P_TIP)
		var at := int(rows * 0.45)
		var on_rib := rib[at]
		b.tube(PackedVector3Array([Vector3(0.0, runner_y, 0.0) + dir * 0.008, on_rib]), 0.0018, 4, P_RIB)
	b.tube(PackedVector3Array([Vector3(0.0, runner_y - 0.03, 0.0), Vector3(0.0, runner_y + 0.03, 0.0)]), 0.0085, 8, P_HANDLE)
	b.tube(PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, apex + 0.01, 0.0)]), 0.0048 if kind == Kind.STICK else 0.0042, 8, P_RIB)
	b.tube(PackedVector3Array([Vector3(0.0, apex - 0.01, 0.0), Vector3(0.0, apex + float(sp.tip), 0.0)]), 0.0055, 8, P_TIP)
	if kind == Kind.STICK:
		# The crook: down from the grip, then round in a J away from the holder.
		var hook := PackedVector3Array()
		hook.append(Vector3(0.0, 0.06, 0.0))
		hook.append(Vector3(0.0, -0.07, 0.0))
		for i in range(1, 10):
			var a := PI * float(i) / 9.0
			hook.append(Vector3(0.0, -0.07 - sin(a) * 0.045, 0.045 - cos(a) * 0.045))
		b.tube(hook, 0.0125, 10, P_HANDLE)
	else:
		b.tube(PackedVector3Array([Vector3(0.0, -0.07, 0.0), Vector3(0.0, 0.07, 0.0)]), 0.0145, 10, P_HANDLE)
		# The wrist strap hanging off the bottom of the grip.
		b.tube(PackedVector3Array([Vector3(0.0, -0.07, 0.0), Vector3(0.0, -0.13, 0.012), Vector3(0.0, -0.15, 0.0)]), 0.003, 4, P_STRAP)
	if f < 0.15:
		# Furled: the tie strap round the folds.
		var r0 := prof[int(rows * 0.6)].x
		var ring := PackedVector3Array()
		for i in 13:
			var a := TAU * float(i) / 12.0
			ring.append(Vector3(sin(a) * (r0 * 0.55 + 0.012), prof[int(rows * 0.6)].y, cos(a) * (r0 * 0.55 + 0.012)))
		b.tube(ring, 0.006, 4, P_STRAP)
	return b.commit()


# --- Hoods -------------------------------------------------------------------------------------

## The hood fitted to the rig at `rig` (a .glb path), shared.
static func hood(rig: String) -> ArrayMesh:
	var key := rig.get_file()
	if not _hoods.has(key):
		_hoods[key] = build_hood(rig)
	return _hoods[key]


## The elevation (radians, the table's spherical frame) at which the face opening reaches its
## top, and the opening's half width round the head at elevation `ph` (0 where it is closed).
static func _open_half(h: CrowdHat.Head, ph: float) -> float:
	var top := h.phi_at_height(0.0, h.eye_y + HOOD_OPEN_TOP)
	var eye := h.phi_at_height(0.0, h.eye_y)
	if ph >= top:
		return 0.0
	# An ellipse over the brow, full width from the eyes down.
	var e := clampf((ph - eye) / maxf(top - eye, 0.01), 0.0, 1.0)
	return HOOD_OPEN_HALF * sqrt(maxf(0.0, 1.0 - e * e))


static func build_hood(rig: String) -> ArrayMesh:
	var h := CrowdHat.head_for(rig)
	var b := _Buf.new()
	var rows := 22
	var cols := 30
	var ph_top := PI * 0.5 - 0.02
	var ph_low := h.phi0 + 0.01
	var drape_rows := 5
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var hem := PackedFloat32Array()
	for r in rows + drape_rows:
		var ph: float
		var down := 0.0
		if r < rows:
			# Rows bunched toward the crown a little less than evenly in elevation.
			ph = lerpf(ph_top, ph_low, float(r) / float(rows - 1))
		else:
			ph = ph_low
			down = HOOD_DRAPE * float(r - rows + 1) / float(drape_rows)
		var half := _open_half(h, ph)
		for c in cols + 1:
			# Round the back from the opening's right edge to its left (th 0 is the face).
			var th := lerpf(half, TAU - half, float(c) / float(cols))
			var rad := h.radius(th, ph) + h.hair(th, ph)
			var back := (1.0 - cos(th)) * 0.5
			var crown := smoothstep(0.0, 0.9, sin(maxf(ph, 0.0)))
			var off := lerpf(HOOD_STANDOFF.z, lerpf(HOOD_STANDOFF.x, HOOD_STANDOFF.y, back), smoothstep(0.0, 0.35, back + crown * 0.3))
			# A soft point at the crown's back where the hood's centre seam pulls.
			off += 0.01 * back * smoothstep(0.2, 0.9, crown) * smoothstep(0.4, 1.0, back)
			var d := CrowdHat.Head.dir(th, ph)
			var q := h.c + d * (rad + off)
			if down > 0.0:
				# The drape: straight down the neck into the collar, eased in under the jaw at the
				# front edges and out over the trapezius at the back.
				var horiz := Vector3(d.x, 0.0, d.z).normalized()
				q += Vector3(0.0, -down, 0.0) + horiz * down * lerpf(-0.12, 0.28, back)
			# The hem: the cloth rolls over near the opening's edges.
			var edge := minf(float(c), float(cols - c))
			var e := 1.0 - smoothstep(0.0, 2.0, edge) if half > 0.0 else 0.0
			q += d * HOOD_HEM * e
			pts.append(q)
			uvs.append(Vector2(th * 0.1, float(r) * 0.02 + down))
			hem.append(e)
	b.grid_hem(rows + drape_rows, cols + 1, pts, uvs, hem, h.c)
	return b.commit()


# --- Materials ---------------------------------------------------------------------------------

## The umbrella canopy colourway `pick` (CANOPY_COLORS), shared.
static func canopy_material(pick: int) -> ShaderMaterial:
	var ci := posmod(pick, CANOPY_COLORS.size())
	var key := "u%d" % ci
	if not _mats.has(key):
		var c: Array = CANOPY_COLORS[ci]
		var m := _material()
		m.set_shader_parameter("main_color", _vec(c[0]))
		m.set_shader_parameter("second_color", _vec(c[1]))
		m.set_shader_parameter("pattern", int(c[2]))
		m.set_shader_parameter("handle_wood", 1.0 if ci % 3 == 0 else 0.0)
		_mats[key] = m
	return _mats[key]


## A hood in `colour` (linear), quantised so a crowd shares a handful of materials.
static func hood_material(colour: Color) -> ShaderMaterial:
	var q := Color(snappedf(colour.r, 0.01), snappedf(colour.g, 0.01), snappedf(colour.b, 0.01))
	var key := "h%s" % q.to_html(false)
	if not _mats.has(key):
		var m := _material()
		m.set_shader_parameter("main_color", _vec(q))
		m.set_shader_parameter("second_color", _vec(q.darkened(0.2)))
		m.set_shader_parameter("pattern", 0)
		_mats[key] = m
	return _mats[key]


static func _material() -> ShaderMaterial:
	if _shader == null:
		_shader = load(SHADER)
	var m := ShaderMaterial.new()
	m.shader = _shader
	return m


## Colours go in as Vector3: a Color set from script is decoded again on Forward+ (CLAUDE.md's
## colour-space trap), and these are already linear.
static func _vec(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


# --- Mesh building -----------------------------------------------------------------------------

class _Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	## A grid of rows x cols points, its normals from the grid itself, turned away from `ref`
	## (inward false) for most vertices, wound to face them (Godot's front faces are clockwise).
	func grid(rows: int, cols: int, p: PackedVector3Array, uvs: PackedVector2Array, part: float, ref: Vector3, inward: bool) -> void:
		var parts := PackedFloat32Array()
		parts.resize(p.size())
		parts.fill(part)
		_grid(rows, cols, p, uvs, parts, ref, inward)

	## The hood: the part is the hood's cloth, or its hem where `hem` says so.
	func grid_hem(rows: int, cols: int, p: PackedVector3Array, uvs: PackedVector2Array, hem: PackedFloat32Array, ref: Vector3) -> void:
		var parts := PackedFloat32Array()
		parts.resize(p.size())
		for k in p.size():
			parts[k] = P_HEM if hem[k] > 0.5 else P_HOOD
		_grid(rows, cols, p, uvs, parts, ref, false)

	func _grid(rows: int, cols: int, p: PackedVector3Array, uvs: PackedVector2Array, parts: PackedFloat32Array, ref: Vector3, inward: bool) -> void:
		var base := v.size()
		var vote := 0.0
		var ns := PackedVector3Array()
		ns.resize(p.size())
		for i in rows:
			for j in cols:
				var k := i * cols + j
				var dv := p[mini(i + 1, rows - 1) * cols + j] - p[maxi(i - 1, 0) * cols + j]
				var du := p[i * cols + mini(j + 1, cols - 1)] - p[i * cols + maxi(j - 1, 0)]
				if du.length_squared() < 1e-12:
					var i2 := i + 1 if i < rows - 1 else i - 1
					du = p[i2 * cols + mini(j + 1, cols - 1)] - p[i2 * cols + maxi(j - 1, 0)]
				var nn := du.cross(dv).normalized()
				ns[k] = nn
				vote += signf((p[k] - ref).dot(nn))
		var flip := (vote >= 0.0) == inward
		for k in p.size():
			v.append(p[k])
			n.append(-ns[k] if flip else ns[k])
			uv.append(uvs[k])
			col.append(Color(1.0, 1.0, 1.0, (parts[k] + 0.5) / 8.0))
		for i in rows - 1:
			for j in cols - 1:
				var a := base + i * cols + j
				var b2 := a + 1
				var c := a + cols + 1
				var d := a + cols
				if flip:
					_tri(a, b2, c)
					_tri(a, c, d)
				else:
					_tri(a, c, b2)
					_tri(a, d, c)

	func _tri(a: int, b2: int, c: int) -> void:
		if (v[b2] - v[a]).cross(v[c] - v[a]).length_squared() < 1e-16:
			return
		idx.append(a)
		idx.append(b2)
		idx.append(c)

	## A round tube along the polyline `path` (no caps: the ends are hidden in what they meet).
	func tube(path: PackedVector3Array, radius: float, sides: int, part: float) -> void:
		var rows := path.size()
		if rows < 2:
			return
		var pts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var prev_side := Vector3.ZERO
		var run := 0.0
		for i in rows:
			var t := (path[mini(i + 1, rows - 1)] - path[maxi(i - 1, 0)]).normalized()
			var side := prev_side
			if side == Vector3.ZERO or absf(side.dot(t)) > 0.9:
				side = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT).normalized()
			side = (side - t * side.dot(t)).normalized()
			prev_side = side
			var up := t.cross(side)
			if i > 0:
				run += path[i].distance_to(path[i - 1])
			for s in sides + 1:
				var a := TAU * float(s) / float(sides)
				pts.append(path[i] + (side * cos(a) + up * sin(a)) * radius)
				uvs.append(Vector2(float(s) / float(sides), run))
		var parts := PackedFloat32Array()
		parts.resize(pts.size())
		parts.fill(part)
		# Normals out of the tube: away from the nearest path point (the centre of the polyline
		# is a fine stand-in for which side is out, since every ring is round its own point).
		var base := v.size()
		_grid(rows, sides + 1, pts, uvs, parts, path[0], false)
		for i in rows:
			for s in sides + 1:
				var k := base + i * (sides + 1) + s
				var out := (v[k] - path[i]).normalized()
				n[k] = out
		# Re-wind every quad of the tube to face out (the vote above can lose on a short bent tube).
		var start := idx.size() - (rows - 1) * sides * 6
		var k2 := maxi(start, 0)
		while k2 + 2 < idx.size():
			var a := idx[k2]
			var bb := idx[k2 + 1]
			var c := idx[k2 + 2]
			var fn := (v[bb] - v[a]).cross(v[c] - v[a])
			if fn.dot(n[a] + n[bb] + n[c]) > 0.0:
				# A front face is clockwise: its cross product points away from the side it faces.
				idx[k2 + 1] = c
				idx[k2 + 2] = bb
			k2 += 3

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
