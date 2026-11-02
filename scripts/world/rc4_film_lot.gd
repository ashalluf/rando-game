class_name Rc4FilmLot
extends RefCounted
## The film lot refcam (`film_lot` in tools/refcams/cameras_w7.json; docs/HANDOFF.md "The film lot
## at 14:00"): what read fake on the studio street between the sound stages, fixed.
##   - The production trailers were boxes: now a fibreglass shell lofted round a rounded section
##     with radiused ends, a black belly skirt, framed windows (blinds in some), doors with grab
##     rails and folding steps, roof air conditioners in rounded shrouds, a roll-up awning case
##     (an awning out on some), the A-frame tongue with its jack and propane bottles.
##   - The studio streets wore the industrial yards' failed asphalt (alligator cracks with weeds:
##     lime patches down the whole street). A studio keeps its streets: the same material KEPT
##     (industrial_ground.gdshader `kept`), tyre tracks worn along each street.
##   - The street was empty between the trailers: golf carts parked in the basecamp's gaps, a
##     chair, a cooler and a stinger at the trailer doors, cable ramps across, wardrobe racks and
##     carts of gear - all hashes of the seed and the spot (FilmStudio's own layout untouched).
##   - The golf carts were stacked boxes: a moulded body with a rounded nose, seat cushions, a
##     canopy on posts, a tinted windscreen, real tyres.
## RC4_FILM_LOT=0 in the environment is the A/B (the old kit and ground, nothing added).

static var enabled: bool = OS.get_environment("RC4_FILM_LOT") != "0"

const K_STEEL := FilmStudioKit.K_STEEL
const K_GLASS := FilmStudioKit.K_GLASS
const K_LAMP := FilmStudioKit.K_LAMP
const K_CANVAS := FilmStudioKit.K_CANVAS
const K_RUBBER := FilmStudioKit.K_RUBBER
const K_CHROME := FilmStudioKit.K_CHROME
const K_TRAILER := FilmStudioKit.K_TRAILER
const K_WOOD := FilmStudioKit.K_WOOD

const GELCOAT := Color(0.94, 0.94, 0.92)
const BLACK := Color(0.07, 0.07, 0.075)
const ALU := Color(0.72, 0.73, 0.74)
const CART_PAINTS := [Color(0.92, 0.92, 0.9), Color(0.9, 0.86, 0.74), Color(0.2, 0.34, 0.24), Color(0.12, 0.12, 0.13), Color(0.6, 0.12, 0.1)]

static var _ground_mat: Material
## Built once per variant (key -> ArrayMesh on the studio material), placed through the chunk's
## MultiMesh batch: a trailer is ~2,500 triangles of GDScript (~75 ms a copy), so never per copy.
static var _meshes: Dictionary = {}


## The variant `key`, built by `build(st)` in its own frame the first time it is asked for.
static func cached(key: String, build: Callable) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	build.call(st)
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, FilmStudioKit.material())
	_meshes[key] = mesh
	return mesh


## A trailer variant through the batch (the trailer's foot at `xf`, y with no relief: the batch
## adds it). Seed picks one of three dressings.
static func place_trailer(ch: CityChunk, xf: Transform3D, length: float, honey: bool, band: int, seed: int) -> void:
	var v := absi(seed) % 3
	var key := "rc4_trailer_%d_%d_%d_%d" % [int(length * 10.0), 1 if honey else 0, band, v]
	var mesh := cached(key, func(st: SurfaceTool) -> void: trailer(st, Transform3D.IDENTITY, length, honey, band, v * 7 + 3))
	ch._batch.add(key, mesh, xf)


## A golf cart variant through the batch.
static func place_cart(ch: CityChunk, xf: Transform3D, paint_i: int, bed: bool) -> void:
	var key := "rc4_cart_%d_%d" % [paint_i, 1 if bed else 0]
	var paint: Color = CART_PAINTS[paint_i % CART_PAINTS.size()]
	var mesh := cached(key, func(st: SurfaceTool) -> void: golf_cart(st, Transform3D.IDENTITY, paint, bed))
	ch._batch.add(key, mesh, xf)


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## The studio's ground: the industrial yards' material with its asphalt KEPT (industrial_ground's
## `kept`: no failed patches, no weeds in the cracks, the long cracks mostly gone).
static func ground_material() -> Material:
	if _ground_mat == null:
		var m := Industrial.ground_material().duplicate() as ShaderMaterial
		m.set_shader_parameter("kept", 1.0)
		_ground_mat = m
	return _ground_mat


## The tyre tracks' axis for an asphalt piece (industrial_ground's COLOR.b, RcVernon's code): along
## the studio street it lies in, none off the streets.
static func track_axis(lay: Dictionary, piece: Rect2) -> float:
	var c := piece.get_center()
	for st: Dictionary in lay.streets:
		if (st.rect as Rect2).has_point(c):
			return 0.25 if int(st.axis) == 0 else 0.75
	return 0.0


# --- Writers ----------------------------------------------------------------------------------

## One triangle, its three normals smooth, wound to face the normals' sum.
static func _tri(st: SurfaceTool, p: Array, n: Array, uv: Array, kind: int, paint: Color, h: float, param: float) -> void:
	var col := Color(paint.r, paint.g, paint.b, (float(kind) + 0.5) / 32.0)
	var face: Vector3 = (n[0] as Vector3) + (n[1] as Vector3) + (n[2] as Vector3)
	var order := [0, 2, 1] if ((p[1] as Vector3) - (p[0] as Vector3)).cross((p[2] as Vector3) - (p[0] as Vector3)).dot(face) > 0.0 else [0, 1, 2]
	for k: int in order:
		st.set_normal(n[k])
		st.set_color(col)
		st.set_uv(uv[k])
		st.set_uv2(Vector2(h, param))
		st.add_vertex(p[k])
	FilmStudioKit.tris += 1


## A rounded rectangle section in (x, y): half width `hw`, from `y0` to `y1`, radius `rb` at the
## bottom corners and `rt` at the top, `seg` steps a corner. Points and outward normals, counter-
## clockwise from the bottom middle, closed (the first point repeated at the end).
static func section(hw: float, y0: float, y1: float, rb: float, rt: float, seg: int) -> Array:
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	var corners := [[Vector2(hw - rb, y0 + rb), rb, -PI * 0.5], [Vector2(hw - rt, y1 - rt), rt, 0.0],
		[Vector2(-hw + rt, y1 - rt), rt, PI * 0.5], [Vector2(-hw + rb, y0 + rb), rb, PI]]
	pts.append(Vector2(0.0, y0))
	nrm.append(Vector2(0.0, -1.0))
	for c: Array in corners:
		for i in seg + 1:
			var a: float = float(c[2]) + PI * 0.5 * float(i) / float(seg)
			var d := Vector2(cos(a), sin(a))
			pts.append((c[0] as Vector2) + d * float(c[1]))
			nrm.append(d)
	pts.append(Vector2(0.0, y0))
	nrm.append(Vector2(0.0, -1.0))
	return [pts, nrm]


## A shell lofted along z through `rings` ([z, scale] pairs, z rising) of `sec` (section()), its
## ends closed by fans. UV: x metres along z, y the height over `y0`; UV2.x `h`.
static func loft(st: SurfaceTool, xf: Transform3D, sec: Array, rings: Array, kind: int, paint: Color, y0: float, h: float, param: float = 0.0) -> void:
	var pts: PackedVector2Array = sec[0]
	var nrm: PackedVector2Array = sec[1]
	var cy := y0 + h * 0.5
	var ring_p: Array = []
	var ring_n: Array = []
	for ri in rings.size():
		var r: Array = rings[ri]
		var z: float = r[0]
		var s: float = r[1]
		# The surface leans in along z where the ring shrinks: tilt the normal toward the end.
		var dz := 0.0
		if ri > 0 and ri < rings.size() - 1:
			dz = (float(rings[ri + 1][1]) - float(rings[ri - 1][1])) / maxf(float(rings[ri + 1][0]) - float(rings[ri - 1][0]), 0.01)
		elif ri == 0:
			dz = (float(rings[1][1]) - s) / maxf(float(rings[1][0]) - z, 0.01)
		else:
			dz = (s - float(rings[ri - 1][1])) / maxf(z - float(rings[ri - 1][0]), 0.01)
		var rp := PackedVector3Array()
		var rn := PackedVector3Array()
		for i in pts.size():
			var q := Vector2(pts[i].x * s, cy + (pts[i].y - cy) * s)
			rp.append(xf * Vector3(q.x, q.y, z))
			var radial := Vector2(pts[i].x, pts[i].y - cy).length()
			rn.append((xf.basis * Vector3(nrm[i].x, nrm[i].y, -dz * radial).normalized()).normalized())
		ring_p.append(rp)
		ring_n.append(rn)
	for ri in rings.size() - 1:
		var a: PackedVector3Array = ring_p[ri]
		var b: PackedVector3Array = ring_p[ri + 1]
		var an: PackedVector3Array = ring_n[ri]
		var bn: PackedVector3Array = ring_n[ri + 1]
		var za: float = rings[ri][0]
		var zb: float = rings[ri + 1][0]
		for i in pts.size() - 1:
			var ya := pts[i].y - y0
			var yb := pts[i + 1].y - y0
			_tri(st, [a[i], a[i + 1], b[i + 1]], [an[i], an[i + 1], bn[i + 1]], [Vector2(za, ya), Vector2(za, yb), Vector2(zb, yb)], kind, paint, h, param)
			_tri(st, [a[i], b[i + 1], b[i]], [an[i], bn[i + 1], bn[i]], [Vector2(za, ya), Vector2(zb, yb), Vector2(zb, ya)], kind, paint, h, param)
	for e in 2:
		var ri := 0 if e == 0 else rings.size() - 1
		var rp: PackedVector3Array = ring_p[ri]
		var s: float = rings[ri][1]
		var z: float = rings[ri][0]
		var c := xf * Vector3(0.0, cy, z)
		var en := (xf.basis * Vector3(0.0, 0.0, -1.0 if e == 0 else 1.0)).normalized()
		for i in pts.size() - 1:
			var u0 := Vector2(pts[i].x * s, (pts[i].y - y0))
			var u1 := Vector2(pts[i + 1].x * s, (pts[i + 1].y - y0))
			_tri(st, [c, rp[i], rp[i + 1]], [en, en, en], [Vector2(0.0, h * 0.5), u0, u1], kind, paint, h, param)


## A tyre on its rim (axis along x in `xf`), `r` radius, `w` wide: a 14-sided tread with rounded
## shoulders, a dished alloy face on the outside.
static func wheel(st: SurfaceTool, xf: Transform3D, at: Vector3, r: float, w: float, rim: Color = ALU) -> void:
	var t := xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), at)
	# A tyre is a loft along the axle of a circular "section" (its tread round the axle).
	var segs := 14
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		pts.append(Vector2(cos(a), sin(a)) * r)
		nrm.append(Vector2(cos(a), sin(a)))
	var sec := [pts, nrm]
	# In t, the axle is y; loft() runs along z, so turn it.
	var lx := t * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO)
	loft(st, lx, sec, [[-w * 0.5, 0.86], [-w * 0.42, 1.0], [w * 0.42, 1.0], [w * 0.5, 0.86]], K_RUBBER, Color(0.06, 0.06, 0.065), -0.0, 0.0)
	FilmStudioKit.cyl(st, t * Transform3D(Basis(), Vector3(0.0, w * 0.5 - 0.01, 0.0)), r * 0.58, 0.02, K_CHROME, rim, 10, true)
	FilmStudioKit.cyl(st, t * Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, -w * 0.5 + 0.01, 0.0)), r * 0.58, 0.02, K_STEEL, Color(0.2, 0.2, 0.21), 10, true)


## A framed window on a side wall at `x` (the wall's plane), centred `z`, `y`: a black rubber frame
## standing 2 cm off, the tinted pane, a blind drawn part-way down in some.
static func _window(st: SurfaceTool, xf: Transform3D, side: float, x: float, z: float, y: float, w: float, hh: float, seed: int) -> void:
	var fx := side * (x + 0.012)
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(fx, y, z)), Vector3(0.03, hh + 0.1, w + 0.1), K_RUBBER, BLACK)
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(side * (x + 0.03), y, z)), Vector3(0.02, hh, w), K_GLASS, Color(0.14, 0.16, 0.17), maxf(w, 0.5))
	var blind := h01([seed, "blind"])
	if blind > 0.45:
		var bh := hh * (0.25 + 0.6 * h01([seed, "blind_h"]))
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(side * (x + 0.035), y + hh * 0.5 - bh * 0.5, z)), Vector3(0.012, bh, w - 0.04), K_CANVAS, Color(0.78, 0.74, 0.66))


## A production trailer (star / makeup trailer, or a honeywagon with a row of doors), `length` long,
## nose toward +z, foot centre at xf's origin, its doors on the kerb side (+x). `band` picks the
## stripe colour (K_TRAILER), `seed` the dressing.
static func trailer(st: SurfaceTool, xf: Transform3D, length: float, honey: bool, band: int, seed: int) -> void:
	var w := 2.55
	var hw := w * 0.5
	var fl := 1.0
	var bh := 3.0
	var top := fl + bh
	var L := length
	var sec := section(hw, fl, top, 0.1, 0.32, 4)
	# The shell: square-ish sides, its ends radiused in over the last 40 cm (a moulded nose cap
	# leans further in at the front).
	var rings := [[-L * 0.5, 0.9], [-L * 0.5 + 0.12, 0.965], [-L * 0.5 + 0.4, 1.0], [L * 0.5 - 0.6, 1.0], [L * 0.5 - 0.2, 0.96], [L * 0.5, 0.88]]
	loft(st, xf, sec, rings, K_TRAILER, GELCOAT, fl, bh, float(band))
	# The belly: a black skirt from the frame to the floor, set in 6 cm, with wheel wells cut by
	# leaving it off over the axles.
	var ax0 := -L * 0.22
	var ax1 := ax0 - 1.3
	var well0 := ax1 - 0.75
	var well1 := ax0 + 0.75
	for seg: Array in [[-L * 0.5 + 0.35, well0], [well1, L * 0.5 - 0.4]]:
		var a: float = seg[0]
		var b: float = seg[1]
		if b - a > 0.2:
			FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, fl - 0.24, (a + b) * 0.5)), Vector3(w - 0.12, 0.48, b - a), K_STEEL, Color(0.09, 0.09, 0.1))
	# Wheel arches: dark fender lips over the tyres.
	for s2: float in [-1.0, 1.0]:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * (hw - 0.02), fl - 0.04, (ax0 + ax1) * 0.5)), Vector3(0.08, 0.08, 2.9), K_RUBBER, BLACK)
		for az: float in [ax0, ax1]:
			wheel(st, xf, Vector3(s2 * (hw - 0.3), 0.37, az), 0.37, 0.24)
	# Frame rails under the belly.
	for s2: float in [-1.0, 1.0]:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 0.75, fl - 0.55, 0.0)), Vector3(0.1, 0.16, L - 0.6), K_STEEL, Color(0.11, 0.11, 0.12))
	# Doors on the kerb side, framed, with a grab rail, a porch lamp and folding steps.
	var doors := 4 if honey else 2
	var dzs: Array[float] = []
	for k in doors:
		var dz := -L * 0.5 + L * (float(k) + 0.5) / float(doors)
		if honey:
			dz = -L * 0.5 + 1.4 + (L - 2.8) * float(k) / float(doors - 1)
		dzs.append(dz)
		var dx := hw + 0.01
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(dx, fl + 1.02, dz)), Vector3(0.025, 2.0, 0.84), K_RUBBER, BLACK)
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(dx + 0.012, fl + 1.02, dz)), Vector3(0.02, 1.92, 0.76), K_TRAILER, GELCOAT, float(band))
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(dx + 0.03, fl + 1.48, dz + 0.04)), Vector3(0.015, 0.5, 0.42), K_GLASS, Color(0.12, 0.13, 0.14), 0.5)
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(dx + 0.05, fl + 1.0, dz - 0.28)), Vector3(0.05, 0.05, 0.14), K_CHROME, ALU)
		# The grab rail beside the door.
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(dx + 0.08, fl + 0.95, dz + 0.52)), Vector3(0.035, 0.75, 0.035), K_CHROME, ALU)
		for yy: float in [fl + 0.6, fl + 1.3]:
			FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(dx + 0.04, yy, dz + 0.52)), Vector3(0.08, 0.03, 0.03), K_CHROME, ALU)
		# Porch lamp over the door.
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(dx + 0.06, fl + 2.2, dz)), Vector3(0.1, 0.1, 0.26), K_LAMP, Color(1.0, 0.92, 0.75))
		# Folding steps: three treads on side stringers, the lowest on the ground.
		for s in 3:
			var ty := fl - 0.27 * float(s + 1) + 0.02
			var tx := hw + 0.2 + 0.24 * float(s)
			FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(tx, ty, dz)), Vector3(0.26, 0.04, 0.72), K_STEEL, Color(0.55, 0.56, 0.57))
		for s2: float in [-1.0, 1.0]:
			FilmStudioKit.beam(st, xf * Vector3(hw + 0.08, fl - 0.05, dz + s2 * 0.37), xf * Vector3(hw + 0.8, 0.1, dz + s2 * 0.37), 0.03, 0.06, K_STEEL, Color(0.45, 0.46, 0.47))
	# Windows along both sides, clear of the doors and the wheel wells' line of sight.
	for s2: float in [-1.0, 1.0]:
		var nwin := int(L / 2.6)
		for k in nwin:
			var wz := -L * 0.5 + L * (float(k) + 0.5) / float(nwin)
			var skip := false
			if s2 > 0.0:
				for dz: float in dzs:
					if absf(dz - wz) < 1.15:
						skip = true
			if skip or absf(wz) > L * 0.5 - 0.9:
				continue
			_window(st, xf, s2, hw, wz, fl + 1.85, 1.15 if not honey else 0.55, 0.72 if not honey else 0.32, absi(hash([seed, s2, k])))
	# A roll-up awning case under the roof edge on the kerb side; out on some trailers.
	var aw0 := -L * 0.5 + 1.0
	var aw1 := L * 0.5 - 1.2
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(hw + 0.08, top - 0.32, (aw0 + aw1) * 0.5)), Vector3(0.14, 0.16, aw1 - aw0), K_CHROME, Color(0.86, 0.86, 0.85))
	if not honey and h01([seed, "awning"]) < 0.55:
		var out := 2.3
		var drop := 0.55
		var stripe: Color = [Color(0.18, 0.3, 0.48), Color(0.48, 0.16, 0.13), Color(0.22, 0.24, 0.26), Color(0.2, 0.36, 0.3)][absi(seed) % 4]
		var a0 := xf * Vector3(hw + 0.14, top - 0.3, aw0)
		var a1 := xf * Vector3(hw + 0.14, top - 0.3, aw1)
		var b0 := xf * Vector3(hw + out, top - 0.3 - drop, aw0)
		var b1 := xf * Vector3(hw + out, top - 0.3 - drop, aw1)
		var up := (xf.basis * Vector3(drop, out, 0.0)).normalized()
		FilmStudioKit.quad(st, a0, a1, b1, b0, up, K_CANVAS, stripe, [Vector2(0.0, 0.6), Vector2(aw1 - aw0, 0.6), Vector2(aw1 - aw0, 0.0), Vector2(0.0, 0.0)], 0.6, 0.3)
		FilmStudioKit.quad(st, a0, a1, b1, b0, -up, K_CANVAS, stripe * 0.8, [Vector2(0.0, 0.6), Vector2(aw1 - aw0, 0.6), Vector2(aw1 - aw0, 0.0), Vector2(0.0, 0.0)], 0.6, 0.3)
		# The valance and the two arms down to the ground.
		var v0 := xf * Vector3(hw + out, top - 0.3 - drop - 0.18, aw0)
		var v1 := xf * Vector3(hw + out, top - 0.3 - drop - 0.18, aw1)
		var vn := (xf.basis * Vector3(1.0, 0.0, 0.0)).normalized()
		FilmStudioKit.quad(st, v0, v1, b1, b0, vn, K_CANVAS, stripe, [Vector2(0.0, 0.0), Vector2(aw1 - aw0, 0.0), Vector2(aw1 - aw0, 0.18), Vector2(0.0, 0.18)], 0.2, 0.3)
		FilmStudioKit.quad(st, v0, v1, b1, b0, -vn, K_CANVAS, stripe * 0.7, [Vector2(0.0, 0.0), Vector2(aw1 - aw0, 0.0), Vector2(aw1 - aw0, 0.18), Vector2(0.0, 0.18)], 0.2, 0.3)
		for az: float in [aw0 + 0.1, aw1 - 0.1]:
			FilmStudioKit.beam(st, xf * Vector3(hw + out - 0.05, top - 0.3 - drop, az), xf * Vector3(hw + 0.12, 0.0, az), 0.04, 0.04, K_CHROME, ALU)
			FilmStudioKit.beam(st, xf * Vector3(hw + out - 0.05, top - 0.3 - drop, az), xf * Vector3(hw + 0.12, top - 0.35, az), 0.03, 0.03, K_CHROME, ALU)
	# Roof: two air conditioners in rounded shrouds, a vent, a satellite dome on some.
	var shroud := section(0.38, 0.0, 0.36, 0.05, 0.14, 2)
	for az: float in [-L * 0.2, L * 0.22]:
		loft(st, xf * Transform3D(Basis(), Vector3(0.0, top - 0.02, az)), shroud, [[-0.48, 0.92], [-0.4, 1.0], [0.38, 1.0], [0.5, 0.85]], K_TRAILER, Color(0.9, 0.9, 0.88), 0.0, 0.36, 0.0)
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.6, top + 0.04, 0.0)), Vector3(0.36, 0.1, 0.36), K_STEEL, Color(0.82, 0.82, 0.8))
	# The tongue: an A-frame to the coupler, the jack, two propane bottles and a battery box.
	var nose := L * 0.5
	for s2: float in [-1.0, 1.0]:
		FilmStudioKit.beam(st, xf * Vector3(s2 * 0.75, fl - 0.5, nose - 0.3), xf * Vector3(0.0, fl - 0.5, nose + 1.4), 0.1, 0.12, K_STEEL, Color(0.11, 0.11, 0.12))
	FilmStudioKit.cyl(st, xf * Transform3D(Basis(), Vector3(0.0, 0.0, nose + 1.15)), 0.05, fl - 0.4, K_STEEL, Color(0.12, 0.12, 0.13), 8, true)
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.04, nose + 1.15)), Vector3(0.22, 0.08, 0.22), K_STEEL, Color(0.3, 0.3, 0.3))
	for s2: float in [-1.0, 1.0]:
		FilmStudioKit.cyl(st, xf * Transform3D(Basis(), Vector3(s2 * 0.25, fl - 0.42, nose + 0.45)), 0.16, 0.58, K_STEEL, Color(0.86, 0.86, 0.84), 10, true)
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, fl - 0.3, nose + 0.85)), Vector3(0.36, 0.26, 0.28), K_RUBBER, BLACK)
	# Stabiliser jacks at the four corners.
	for c: Vector2 in [Vector2(-0.9, L * 0.5 - 0.5), Vector2(0.9, L * 0.5 - 0.5), Vector2(-0.9, -L * 0.5 + 0.5), Vector2(0.9, -L * 0.5 + 0.5)]:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(c.x, (fl - 0.48) * 0.5, c.y)), Vector3(0.07, fl - 0.48, 0.07), K_STEEL, Color(0.42, 0.43, 0.44))
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(c.x, 0.02, c.y)), Vector3(0.24, 0.04, 0.24), K_WOOD, Color(0.62, 0.5, 0.36))
	# Tail lamps and marker lights.
	for s2: float in [-1.0, 1.0]:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * (hw - 0.25), fl + 0.25, -L * 0.5 - 0.005)), Vector3(0.22, 0.12, 0.04), K_LAMP, Color(0.9, 0.1, 0.06))
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * (hw + 0.005), top - 0.22, L * 0.5 - 0.8)), Vector3(0.03, 0.06, 0.12), K_LAMP, Color(1.0, 0.6, 0.15))


## A five-ton grip / electric truck, nose toward +z, foot centre at xf's origin: a cab-over cab
## lofted round a rounded section with its glass, mirrors and grille; a box body on radiused corner
## posts with the band, rub rails and a roll-up door at the back over a folded lift gate; fuel tank,
## steps, mudflaps, dual rear wheels.
static func truck(st: SurfaceTool, xf: Transform3D, band: int, seed: int) -> void:
	var white := Color(0.94, 0.94, 0.93)
	# The cab: 2.3 wide, 2.3 tall from 0.95, its nose rounded.
	var cab := section(1.15, 0.95, 3.15, 0.08, 0.22, 3)
	loft(st, xf, cab, [[2.55, 0.97], [2.62, 1.0], [4.3, 1.0], [4.52, 0.95], [4.6, 0.86]], K_TRAILER, white, 0.95, 2.2, 4.0)
	# Glass: the windscreen across the nose, side windows, the black band of the grille.
	FilmStudioKit.box(st, xf * Transform3D(Basis(Vector3.RIGHT, -0.08), Vector3(0.0, 2.45, 4.58)), Vector3(2.0, 0.95, 0.03), K_GLASS, Color(0.12, 0.13, 0.15), 2.1)
	for s2: float in [-1.0, 1.0]:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 1.155, 2.45, 3.85)), Vector3(0.03, 0.85, 1.0), K_GLASS, Color(0.12, 0.13, 0.15), 1.1)
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 1.16, 1.65, 3.85)), Vector3(0.02, 0.02, 0.9), K_RUBBER, BLACK)
		# Mirrors on arms, a step under the door, the headlamp.
		FilmStudioKit.beam(st, xf * Vector3(s2 * 1.15, 2.6, 4.3), xf * Vector3(s2 * 1.45, 2.7, 4.35), 0.03, 0.03, K_STEEL, BLACK)
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 1.5, 2.55, 4.35)), Vector3(0.08, 0.42, 0.22), K_RUBBER, BLACK)
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 1.05, 0.65, 3.9)), Vector3(0.3, 0.05, 0.6), K_STEEL, Color(0.5, 0.5, 0.52))
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 0.82, 1.28, 4.58)), Vector3(0.34, 0.2, 0.05), K_LAMP, Color(1.0, 0.96, 0.88))
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.55, 4.6)), Vector3(1.2, 0.35, 0.03), K_RUBBER, Color(0.1, 0.1, 0.11))
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.85, 4.6)), Vector3(2.3, 0.3, 0.18), K_STEEL, Color(0.16, 0.16, 0.17))
	# Chassis rails, the fuel tank, battery box.
	for s2: float in [-1.0, 1.0]:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 0.45, 0.85, 0.0)), Vector3(0.1, 0.28, 9.2), K_STEEL, Color(0.1, 0.1, 0.1))
	FilmStudioKit.cyl(st, xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.95, 0.72, 0.9)), 0.28, 1.2, K_CHROME, ALU, 12, true)
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.95, 0.75, 1.5)), Vector3(0.5, 0.45, 0.7), K_STEEL, BLACK)
	# The box: 2.5 x 3.1 x 7.4 on radiused corner posts.
	var bz0 := -4.95
	var bz1 := 2.45
	var box_sec := section(1.25, 1.18, 4.3, 0.05, 0.1, 2)
	loft(st, xf, box_sec, [[bz0, 1.0], [bz1, 1.0]], K_TRAILER, white, 1.18, 3.12, float(band))
	for c: Vector2 in [Vector2(-1.26, bz0 + 0.03), Vector2(1.26, bz0 + 0.03), Vector2(-1.26, bz1 - 0.03), Vector2(1.26, bz1 - 0.03)]:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(c.x, 2.74, c.y)), Vector3(0.07, 3.12, 0.07), K_CHROME, ALU)
	for s2: float in [-1.0, 1.0]:
		for yy: float in [1.25, 4.25]:
			FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 1.27, yy, (bz0 + bz1) * 0.5)), Vector3(0.05, 0.1, bz1 - bz0), K_CHROME, ALU)
		# A side door near the front of the box, its steps.
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 1.27, 2.45, bz1 - 1.2)), Vector3(0.02, 2.1, 0.9), K_STEEL, Color(0.84, 0.84, 0.82))
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 1.28, 2.4, bz1 - 0.85)), Vector3(0.04, 0.06, 0.18), K_CHROME, ALU)
		# Marker lamps along the top.
		for k in 3:
			FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 1.27, 4.15, bz0 + 0.6 + float(k) * 3.0)), Vector3(0.03, 0.06, 0.1), K_LAMP, Color(1.0, 0.6, 0.15))
	# The rental house's name down both sides of the box, painted.
	var names := ["SUNSPIRE GRIP & ELECTRIC", "BACKLOT LIGHTING CO.", "STAGE 9 RENTALS", "MAGPIE CAMERA SUPPLY"]
	var label: String = names[absi(seed) % names.size()]
	var lh := 0.32
	var lw := float(FilmStudioKit.text2d(label, lh)[1])
	for s2: float in [-1.0, 1.0]:
		var face := Transform3D(Basis(Vector3(0.0, 0.0, -s2), Vector3.UP, Vector3(s2, 0.0, 0.0)), Vector3(s2 * 1.29, 3.35, (bz0 + bz1) * 0.5 - 0.6))
		FilmStudioKit.letters(st, label, lh * minf(1.0, 6.0 / maxf(lw, 0.1)), xf * face, FilmStudioKit.K_SIGN, Color(0.1, 0.1, 0.12))
	# The roll-up door (its slats) at the back, the folded lift gate under it, tail lamps.
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 2.7, bz0 - 0.02)), Vector3(2.25, 2.85, 0.04), FilmStudioKit.K_DOOR, Color(0.88, 0.88, 0.86), 1.1)
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.08, bz0 - 0.25)), Vector3(2.4, 0.12, 0.5), K_STEEL, Color(0.5, 0.5, 0.52))
	FilmStudioKit.box(st, xf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0.0, 1.45, bz0 - 0.48)), Vector3(2.3, 0.7, 0.06), K_STEEL, Color(0.55, 0.56, 0.57))
	for s2: float in [-1.0, 1.0]:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 1.0, 1.4, bz0 - 0.05)), Vector3(0.24, 0.16, 0.05), K_LAMP, Color(1.0, 0.1, 0.05))
		# Mudflaps behind the rear wheels.
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 0.95, 0.45, -3.85)), Vector3(0.6, 0.7, 0.02), K_RUBBER, BLACK)
	# Wheels: singles under the cab, duals at the back.
	for s2: float in [-1.0, 1.0]:
		wheel(st, xf, Vector3(s2 * 1.0, 0.5, 3.4), 0.5, 0.3)
		wheel(st, xf, Vector3(s2 * 0.92, 0.5, -3.0), 0.5, 0.28)
		wheel(st, xf, Vector3(s2 * 1.2, 0.5, -3.0), 0.5, 0.26)


## A truck through the batch.
static func place_truck(ch: CityChunk, xf: Transform3D, band: int) -> void:
	var key := "rc4_truck_%d" % band
	var mesh := cached(key, func(st: SurfaceTool) -> void: truck(st, Transform3D.IDENTITY, band, band))
	ch._batch.add(key, mesh, xf)


## A golf cart (2.4 x 1.2), nose toward +z: a moulded body with a rounded cowl, two bench cushions,
## a canopy on four posts, a tinted windscreen, tyres on alloys; a cargo bed on some.
static func golf_cart(st: SurfaceTool, xf: Transform3D, paint: Color, bed: bool) -> void:
	var body := section(0.6, 0.18, 0.62, 0.08, 0.1, 2)
	loft(st, xf, body, [[-1.05, 0.88], [-0.95, 1.0], [0.7, 1.0], [1.05, 0.9], [1.18, 0.72]], K_CHROME, paint, 0.18, 0.44)
	# The cowl over the front wheels, rising to the dash.
	var cowl := section(0.58, 0.6, 0.92, 0.02, 0.16, 2)
	loft(st, xf, cowl, [[0.62, 1.0], [0.9, 0.97], [1.12, 0.7]], K_CHROME, paint, 0.6, 0.32)
	# Bench seat and back, upholstered.
	var cush := section(0.52, 0.0, 0.14, 0.05, 0.06, 2)
	loft(st, xf * Transform3D(Basis(), Vector3(0.0, 0.66, -0.12)), cush, [[-0.32, 0.92], [-0.26, 1.0], [0.26, 1.0], [0.32, 0.92]], K_CANVAS, Color(0.24, 0.18, 0.13), 0.0, 0.14)
	var back := section(0.52, 0.0, 0.48, 0.06, 0.1, 2)
	loft(st, xf * Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0.0, 0.78, -0.44)), back, [[-0.06, 0.92], [-0.03, 1.0], [0.03, 1.0], [0.06, 0.92]], K_CANVAS, Color(0.24, 0.18, 0.13), 0.0, 0.48)
	# Posts, roof, windscreen.
	for c: Vector2 in [Vector2(-0.53, 0.72), Vector2(0.53, 0.72)]:
		FilmStudioKit.beam(st, xf * Vector3(c.x, 0.9, c.y), xf * Vector3(c.x, 2.0, c.y - 0.08), 0.035, 0.035, K_STEEL, Color(0.12, 0.12, 0.13))
	for c: Vector2 in [Vector2(-0.53, -0.5), Vector2(0.53, -0.5)]:
		FilmStudioKit.beam(st, xf * Vector3(c.x, 0.62, c.y), xf * Vector3(c.x, 2.0, c.y), 0.035, 0.035, K_STEEL, Color(0.12, 0.12, 0.13))
	var roof := section(0.66, 0.0, 0.07, 0.03, 0.03, 2)
	loft(st, xf * Transform3D(Basis(), Vector3(0.0, 2.0, 0.08)), roof, [[-0.85, 0.96], [-0.8, 1.0], [0.8, 1.0], [0.86, 0.96]], K_CHROME, paint, 0.0, 0.07)
	FilmStudioKit.box(st, xf * Transform3D(Basis(Vector3.RIGHT, 0.08), Vector3(0.0, 1.45, 0.73)), Vector3(1.04, 1.0, 0.015), K_GLASS, Color(0.55, 0.6, 0.62), 2.0)
	# The steering wheel on its column.
	FilmStudioKit.beam(st, xf * Vector3(-0.24, 0.72, 0.62), xf * Vector3(-0.24, 1.0, 0.42), 0.03, 0.03, K_STEEL, BLACK)
	FilmStudioKit.cyl(st, xf * Transform3D(Basis(Vector3.RIGHT, -1.05), Vector3(-0.24, 1.0, 0.42)), 0.17, 0.025, K_RUBBER, BLACK, 12, true)
	# Headlamps in the cowl, a bumper.
	for s2: float in [-1.0, 1.0]:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 0.32, 0.66, 1.14)), Vector3(0.14, 0.08, 0.04), K_LAMP, Color(1.0, 0.95, 0.85))
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.3, 1.2)), Vector3(1.0, 0.1, 0.08), K_RUBBER, BLACK)
	if bed:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.8, -0.95)), Vector3(1.1, 0.06, 0.8), K_STEEL, Color(0.22, 0.22, 0.23))
		for s2: float in [-1.0, 1.0]:
			FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 0.54, 0.95, -0.95)), Vector3(0.03, 0.26, 0.8), K_STEEL, Color(0.22, 0.22, 0.23))
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.1, 1.06, -0.98)), Vector3(0.6, 0.45, 0.5), K_STEEL, BLACK)
	for c: Vector2 in [Vector2(-0.52, 0.78), Vector2(0.52, 0.78), Vector2(-0.52, -0.62), Vector2(0.52, -0.62)]:
		wheel(st, xf, Vector3(c.x, 0.23, c.y), 0.23, 0.2)


# --- The street's dressing ----------------------------------------------------------------------

## What stands in the basecamp's gaps and at its doors, from the layout alone (pure): golf carts in
## gaps over 4 m, chairs / coolers / cable at trailer doors, wardrobe racks, cable ramps across the
## street. [{"kind", "at", "yaw", "seed"}] in TRUE world XZ.
static func dressing(lay: Dictionary, ps: int) -> Array:
	var out: Array = []
	if lay.is_empty():
		return out
	for st: Dictionary in lay.streets:
		var axis: int = st.axis
		var r: Rect2 = st.rect
		var mid: float = r.get_center().x if axis == 0 else r.get_center().y
		var spans: Array = []
		for pk: Dictionary in lay.parking:
			var p: Vector2 = pk.at
			if not r.grow(1.0).has_point(p):
				continue
			var along := p.y if axis == 0 else p.x
			var across := p.x if axis == 0 else p.y
			spans.append([along - float(pk.length) * 0.5, along + float(pk.length) * 0.5, across, pk])
		if spans.is_empty():
			continue
		spans.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var side := signf(float(spans[0][2]) - mid)
		var across0: float = spans[0][2]
		# Gaps between trailers: a golf cart or two nose-in, a rack or a gear cart.
		for i in spans.size() - 1:
			var g0: float = float(spans[i][1]) + 1.6
			var g1: float = float(spans[i + 1][0]) - 1.6
			var key := [ps, "rc4_gap", axis, st.index, i]
			if g1 - g0 < 1.4 or g1 - g0 > 14.0:
				continue
			var n := clampi(int((g1 - g0) / 1.6), 1, 3)
			for k in n:
				var t := g0 + (g1 - g0) * (float(k) + 0.5) / float(n)
				var kind := "cart" if h01(key + [k]) < 0.72 else ("rack" if h01(key + [k, "r"]) < 0.5 else "gearcart")
				var ac := across0 + side * 0.4
				var at := Vector2(ac, t) if axis == 0 else Vector2(t, ac)
				# A cart parks nose out toward the street.
				var yaw := (PI * 0.5 if side < 0.0 else -PI * 0.5) if axis == 0 else (0.0 if side < 0.0 else PI)
				out.append({"kind": kind, "at": at, "yaw": yaw + (h01(key + [k, "y"]) - 0.5) * 0.3, "seed": absi(hash(key + [k]))})
		# At trailer doors (the side toward the street's middle): a director's chair, a cooler, a
		# stinger coiled on the ground.
		for sp: Array in spans:
			var pk: Dictionary = sp[3]
			if String(pk.kind) == "truck":
				continue
			var key2 := [ps, "rc4_door", axis, st.index, int(float(sp[0]))]
			if h01(key2) > 0.6:
				continue
			var t2 := (float(sp[0]) + float(sp[1])) * 0.5 + (h01(key2 + ["t"]) - 0.5) * 3.0
			var ac2 := float(sp[2]) - side * 3.2
			var at2 := Vector2(ac2, t2) if axis == 0 else Vector2(t2, ac2)
			out.append({"kind": "chairs", "at": at2, "yaw": (-PI * 0.5 * side if axis == 0 else (0.0 if side < 0.0 else PI)), "seed": absi(hash(key2))})
		# Cable ramps (yellow jackets) across the street now and then.
		var a0: float = r.position.y if axis == 0 else r.position.x
		var a1: float = r.end.y if axis == 0 else r.end.x
		var tt := a0 + 30.0
		var q := 0
		while tt < a1 - 30.0:
			var key3 := [ps, "rc4_ramp", axis, st.index, q]
			if h01(key3) < 0.4:
				var at3 := Vector2(mid, tt) if axis == 0 else Vector2(tt, mid)
				out.append({"kind": "ramp", "at": at3, "yaw": (PI * 0.5 if axis == 0 else 0.0), "len": (r.size.x if axis == 0 else r.size.y) - 9.0, "seed": absi(hash(key3))})
			tt += 40.0 + 30.0 * h01(key3 + ["s"])
			q += 1
	return out


## A director's chair: a black frame, a canvas seat and back with the studio's colour.
static func _chair(st: SurfaceTool, xf: Transform3D, canvas: Color) -> void:
	for s2: float in [-1.0, 1.0]:
		FilmStudioKit.beam(st, xf * Vector3(s2 * 0.27, 0.0, 0.2), xf * Vector3(s2 * 0.27, 0.47, -0.2), 0.025, 0.025, K_WOOD, Color(0.2, 0.15, 0.1))
		FilmStudioKit.beam(st, xf * Vector3(s2 * 0.27, 0.0, -0.2), xf * Vector3(s2 * 0.27, 0.47, 0.2), 0.025, 0.025, K_WOOD, Color(0.2, 0.15, 0.1))
		FilmStudioKit.beam(st, xf * Vector3(s2 * 0.27, 0.47, -0.22), xf * Vector3(s2 * 0.27, 0.95, -0.24), 0.025, 0.025, K_WOOD, Color(0.2, 0.15, 0.1))
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 0.27, 0.66, 0.0)), Vector3(0.05, 0.03, 0.46), K_WOOD, Color(0.2, 0.15, 0.1))
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.47, 0.0)), Vector3(0.52, 0.02, 0.4), K_CANVAS, canvas)
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.84, -0.235)), Vector3(0.54, 0.2, 0.015), K_CANVAS, canvas)


## Everything dressing() planned that lies in `area`: variants through the chunk's batch.
static func build_dressing(ch: CityChunk, lay: Dictionary, area: Rect2, base_y: float) -> void:
	for d: Dictionary in dressing(lay, ch.plan.seed):
		var p: Vector2 = d.at
		if not area.has_point(p):
			continue
		var y := base_y + ch._gy(p.x, p.y)
		var seed: int = d.seed
		var xf := Transform3D(Basis(Vector3.UP, float(d.yaw)), Vector3(p.x, base_y, p.y))
		match String(d.kind):
			"cart":
				place_cart(ch, xf, seed % CART_PAINTS.size(), seed % 3 == 0)
				ch._add_shape(Vector3(1.2, 1.9, 2.4), Vector3(p.x, y + 0.95, p.y), float(d.yaw))
			"rack":
				var v := seed % 4
				ch._batch.add("rc4_rack_%d" % v, cached("rc4_rack_%d" % v, func(st: SurfaceTool) -> void: _rack(st, v * 31 + 5)), xf)
				ch._add_shape(Vector3(1.6, 1.7, 0.6), Vector3(p.x, y + 0.85, p.y), float(d.yaw))
			"gearcart":
				ch._batch.add("rc4_gearcart", cached("rc4_gearcart", _gear_cart), xf)
				ch._add_shape(Vector3(0.8, 1.1, 1.5), Vector3(p.x, y + 0.55, p.y), float(d.yaw))
			"chairs":
				var v2 := seed % 6
				ch._batch.add("rc4_chairs_%d" % v2, cached("rc4_chairs_%d" % v2, func(st: SurfaceTool) -> void: _chairs(st, v2)), xf)
			"ramp":
				var L: float = d.len
				var mesh := cached("rc4_ramp", _ramp_piece)
				var segs := int(L / 0.9)
				for k in segs:
					var z := -L * 0.5 + 0.9 * (float(k) + 0.5)
					var rx := xf * Transform3D(Basis(), Vector3(0.0, 0.0, z))
					ch._batch.add("rc4_ramp", mesh, rx)
	for key: String in ["rc4_ramp"]:
		ch._batch.set_no_shadow(key)


## A wardrobe rack: chrome frame on castors, garments hanging in a run of colours.
static func _rack(st: SurfaceTool, seed: int) -> void:
	var xf := Transform3D.IDENTITY
	for s2: float in [-1.0, 1.0]:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 0.75, 0.85, 0.0)), Vector3(0.03, 1.7, 0.03), K_CHROME, ALU)
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(s2 * 0.75, 0.06, 0.0)), Vector3(0.05, 0.05, 0.55), K_CHROME, ALU)
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.68, 0.0)), Vector3(1.55, 0.03, 0.03), K_CHROME, ALU)
	var n := 9 + seed % 6
	for k in n:
		var gc := Color.from_hsv(h01([seed, k]), 0.15 + 0.45 * h01([seed, k, "s"]), 0.2 + 0.6 * h01([seed, k, "v"]))
		var gl := 0.8 + 0.5 * h01([seed, k, "l"])
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(-0.68 + 1.36 * (float(k) + 0.5) / float(n), 1.66 - gl * 0.5, 0.0)), Vector3(0.07, gl, 0.42 + 0.1 * h01([seed, k, "w"])), K_CANVAS, gc)


## A grip cart: a steel deck on wheels, crates and stands on it.
static func _gear_cart(st: SurfaceTool) -> void:
	var xf := Transform3D.IDENTITY
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.45, 0.0)), Vector3(0.8, 0.06, 1.5), K_STEEL, Color(0.3, 0.3, 0.31))
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.25, 0.0)), Vector3(0.7, 0.04, 1.4), K_STEEL, Color(0.3, 0.3, 0.31))
	for c: Vector2 in [Vector2(-0.36, 0.7), Vector2(0.36, 0.7), Vector2(-0.36, -0.7), Vector2(0.36, -0.7)]:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(c.x, 0.5, c.y)), Vector3(0.03, 1.0, 0.03), K_STEEL, Color(0.3, 0.3, 0.31))
		wheel(st, xf, Vector3(c.x, 0.1, c.y), 0.1, 0.05)
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.66, 0.3)), Vector3(0.7, 0.36, 0.6), K_STEEL, BLACK)
	FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.62, -0.4)), Vector3(0.6, 0.28, 0.5), K_WOOD, Color(0.7, 0.58, 0.4))
	for k in 4:
		FilmStudioKit.box(st, xf * Transform3D(Basis(), Vector3(-0.25 + 0.17 * float(k), 1.3, -0.1)), Vector3(0.03, 1.6, 0.03), K_CHROME, ALU)


## One or two director's chairs, a cooler, a coiled stinger (variant 0..5).
static func _chairs(st: SurfaceTool, v: int) -> void:
	var xf := Transform3D.IDENTITY
	var canvas: Color = [Color(0.1, 0.1, 0.11), Color(0.55, 0.14, 0.1), Color(0.14, 0.22, 0.38)][v % 3]
	_chair(st, xf * Transform3D(Basis(Vector3.UP, 0.3), Vector3(-0.45, 0.0, 0.0)), canvas)
	if v % 2 == 0:
		_chair(st, xf * Transform3D(Basis(Vector3.UP, -0.25), Vector3(0.45, 0.0, 0.1)), canvas)
	var cooler := section(0.3, 0.0, 0.38, 0.04, 0.05, 2)
	var cc: Color = [Color(0.85, 0.2, 0.12), Color(0.15, 0.32, 0.6), Color(0.92, 0.92, 0.9)][(v / 2) % 3]
	loft(st, xf * Transform3D(Basis(Vector3.UP, 1.4), Vector3(1.15, 0.0, -0.2)), cooler, [[-0.22, 0.95], [-0.2, 1.0], [0.2, 1.0], [0.22, 0.95]], K_TRAILER, cc, 0.0, 0.38, 0.0)
	FilmStudioKit.cyl(st, xf * Transform3D(Basis(), Vector3(-1.2, 0.0, -0.4)), 0.3, 0.07, K_RUBBER, Color(0.08, 0.08, 0.09), 12, true)


## One cable ramp section, 0.9 m of the run: a black body, the yellow lid.
static func _ramp_piece(st: SurfaceTool) -> void:
	var sec := section(0.3, 0.0, 0.07, 0.01, 0.05, 2)
	loft(st, Transform3D.IDENTITY, sec, [[-0.44, 1.0], [0.44, 1.0]], K_RUBBER, Color(0.12, 0.12, 0.12), 0.0, 0.07)
	FilmStudioKit.box(st, Transform3D(Basis(), Vector3(0.0, 0.072, 0.0)), Vector3(0.22, 0.008, 0.86), K_CANVAS, Color(0.92, 0.72, 0.1))


## FilmStudio's build step for the dressing (its own step: the lot mesh's accumulator).
static func dressing_step(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	build_dressing(ch, lay, area, FilmStudio.BASE_Y)


# --- The crew ---------------------------------------------------------------------------------

## The tops a film crew wears (black, charcoal, deep navy, a faded olive) and their trousers
## (black, charcoal work trousers, dark denim, khaki cargo): HSV for character.gdshader's recolour.
const CREW_TOPS := [Vector3(0.62, 0.05, 0.07), Vector3(0.6, 0.06, 0.16), Vector3(0.63, 0.35, 0.16), Vector3(0.2, 0.25, 0.24), Vector3(0.0, 0.0, 0.1)]
const CREW_TROUSERS := [Vector3(0.6, 0.04, 0.08), Vector3(0.6, 0.05, 0.2), Vector3(0.61, 0.3, 0.22), Vector3(0.11, 0.26, 0.4)]
## Share of the lot's walkers who are crew (the rest are cast, producers, visitors).
const CREW_SHARE := 0.75

static var _crew_mats: Dictionary = {}


## FilmStudio's step after its crowd: three in four of the chunk's walkers dressed as crew. Each
## mesh's own look material is copied once per (material, outfit) with the top and trousers
## recoloured; the copy rides material_override, which the middle and far bodies keep.
## Walkers the street gets later (BusyStreets' top-ups, CrowdFlow's doors) are dressed as they
## enter the chunk.
static func dress_crew(ch: CityChunk) -> void:
	for c in ch.get_children():
		_crew_walker(ch, c)
	if not ch.has_meta("rc4_crew_watch"):
		ch.set_meta("rc4_crew_watch", true)
		ch.child_entered_tree.connect(func(n: Node) -> void: _crew_walker(ch, n))


static func _crew_walker(ch: CityChunk, c: Node) -> void:
	if not (c is Pedestrian) or c.has_meta("rc4_crew") or (c.get_script() as Script) != Pedestrian:
		return
	var ped := c as Pedestrian
	var roll := h01([ch.plan.seed, "rc4_crew", roundi(ped.position.x * 10.0), roundi(ped.position.z * 10.0)])
	ped.set_meta("rc4_crew", roll < CREW_SHARE)
	if roll >= CREW_SHARE:
		return
	var outfit := int(roll / CREW_SHARE * 20.0)
	if ped.is_node_ready():
		_dress(ped, outfit)
	else:
		ped.ready.connect(_dress.bind(ped, outfit), CONNECT_ONE_SHOT)


static func _dress(ped: Pedestrian, outfit: int) -> void:
	if not is_instance_valid(ped):
		return
	for mi: MeshInstance3D in ped._meshes:
		if not is_instance_valid(mi) or Pedestrian.is_hair(mi):
			continue
		var base := mi.material_override as ShaderMaterial
		if base == null or base.shader == null or not base.shader.resource_path.ends_with("character.gdshader"):
			continue
		var key := "%d_%d" % [base.get_instance_id(), outfit]
		if not _crew_mats.has(key):
			var m := base.duplicate() as ShaderMaterial
			var top: Vector3 = CREW_TOPS[outfit % CREW_TOPS.size()]
			var low: Vector3 = CREW_TROUSERS[(outfit / CREW_TOPS.size()) % CREW_TROUSERS.size()]
			m.set_shader_parameter("cloth_hue", top.x)
			m.set_shader_parameter("cloth_sat", top.y)
			m.set_shader_parameter("cloth_value", top.z)
			m.set_shader_parameter("cloth_strength", 0.9)
			m.set_shader_parameter("pants_hue", low.x)
			m.set_shader_parameter("pants_sat", low.y)
			m.set_shader_parameter("pants_value", low.z)
			m.set_shader_parameter("pants_strength", 0.9)
			_crew_mats[key] = m
		mi.material_override = _crew_mats[key]
