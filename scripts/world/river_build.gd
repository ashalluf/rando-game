class_name RiverBuild
extends RefCounted
## A chunk's part of the Los Angeles River (LaRiver): what a river block builds in place of the
## seeded block (CityPlan.river_block(), CityChunk.begin_build()).
##
## The chunk owns the river's centre-line segments whose midpoints fall in its area and everything
## of the corridor inside its area, so each piece is built exactly once:
##   * the channel (`_channel_step`): per owned segment the cross section swept 8 m - the
##     low-flow notch, the bed, both banks, the coping kerbs - on ONE concrete material
##     (shaders/river_concrete.gdshader), the water sheet in the notch (river_water.gdshader), the
##     drain outfalls' headwalls and pipes, the sediment bars with reeds and shrubs, the access
##     ramps down the banks, the headwall and box culverts at the north end, the end walls and the
##     apron at the mouth;
##   * the land (`_land_step`): the maintenance roads on top of the banks, the dead-end stubs of
##     the streets that end at the bank (with barriers), and what is left of the block - a pavement
##     ring along its streets with lamps, and a rail yard of gravel, ballast and weeds with the
##     freight tracks that run along the river, the chain-link fence along the bank roads - on
##     Industrial's ground and walls materials, so the river's edge is the industrial district's;
##   * the bridges this chunk owns (`_bridge_step`, RiverBridges);
##   * one commit (`_commit_step`): a mesh per material and ONE trimesh collision body.
## LOD chunks build the same at lower detail (a 16 m step, no props, no outfalls or bars); the far
## city's capture (`capture()`) records it as boxes.
##
## Heights: the land is the relief (`ch._gy()`, which LaRiver.terrace() makes the channel's top
## level along the corridor), the channel the river's own profile. Every roll is a hash of the
## seed (LaRiver.h01()), never the chunk's rng.

const KIND_BANK := 0
const KIND_BED := 1
const KIND_NOTCH := 2
const KIND_COPING := 3
const KIND_WALL := 4
const KIND_BRIDGE := 5
const KIND_PIER := 6
const KIND_DARK := 7

## Industrial ground kinds (shaders/industrial_ground.gdshader).
const G_ASPHALT := 0
const G_CONCRETE := 1
const G_GRAVEL := 2
const G_DIRT := 3
const G_WEEDS := 6

## The pavement left along a river block's streets, and how far apart its lamps stand.
const PAVEMENT := 3.6
const LAMP_GAP := 30.0
## The freight tracks along the river: their centre this far outside the fence, the ballast's
## half width, and a tie every TIE_GAP metres.
const TRACK_OUT := 6.5
const BALLAST_HALF := 2.1
const TIE_GAP := 0.62
## Odds that a stretch of track has a string of freight cars standing on it.
const TRACK_CARS := 0.45
## Draw distances (metres): the reeds and shrubs on the bars, the ties.
const PLANT_DISTANCE := 160.0
const TIE_DISTANCE := 140.0

var ch: CityChunk
var rv: LaRiver
var plan: CityPlan
var area: Rect2
var full: bool
var block_rect: Rect2
## Point index range of the centre line that can reach this chunk.
var ir: Vector2i
var _st: Dictionary = {}
var _faces := PackedVector3Array()
## Road rects in this chunk's area: [Rect2, open (bool)].
var _roads: Array = []
var _open_rects: Array[Rect2] = []
## Ramps' coping cuts: [s0, s1, side].
var _coping_cuts: Array = []
var _lamp_count := 0


static func attach(c: CityChunk, _block: Dictionary) -> Array[Callable]:
	var b := RiverBuild.new()
	b._setup(c)
	c._river_build = b
	return [b._channel_step, b._extras_step, b._land_prep, b._land_step, b._props_step, b._bridge_step, b._commit_step]


func _setup(c: CityChunk) -> void:
	ch = c
	plan = c.plan
	rv = plan.macro.river
	area = c.owned_rect()
	full = c.level == CityChunk.Level.FULL and not c.capturing
	block_rect = plan.block(c.ix, c.iz).rect
	Industrial._state(c)
	# The coping is opened over every ramp's head (the first ten metres down it), whoever builds
	# the ramp: a ramp's head can be in the next chunk's stretch.
	for r: Dictionary in rv.ramps(plan):
		var s0: float = r.s0
		if float(r.s1) > s0:
			_coping_cuts.append([s0 - 0.5, s0 + 10.0, float(r.side)])
		else:
			_coping_cuts.append([s0 - 10.0, s0 + 0.5, float(r.side)])
	ir = rv.index_range(area, LaRiver.BED_HALF_S + LaRiver.DEPTH_S * LaRiver.SLOPE + LaRiver.CORRIDOR + 6.0)
	_find_roads()


## The roads in the chunk's area (its +X and +Z road and their junction), open or closed - as
## CityChunk._build_roads() decides what it lays.
func _find_roads() -> void:
	var ix := ch.ix
	var iz := ch.iz
	var rect := block_rect
	var rx := plan.road_pos(CityPlan.AXIS_X, ix + 1)
	var wx := plan.road_width(CityPlan.AXIS_X, ix + 1)
	var rz := plan.road_pos(CityPlan.AXIS_Z, iz + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, iz + 1)
	var open_x := plan.road_open(CityPlan.AXIS_X, ix + 1, rect.get_center().y)
	var open_z := plan.road_open(CityPlan.AXIS_Z, iz + 1, rect.get_center().x)
	var open_c := plan.road_open(CityPlan.AXIS_X, ix + 1, rz) or plan.road_open(CityPlan.AXIS_Z, iz + 1, rx)
	_roads = [
		[Rect2(rx - wx * 0.5, rect.position.y, wx, rect.size.y), open_x],
		[Rect2(rect.position.x, rz - wz * 0.5, rect.size.x, wz), open_z],
		[Rect2(rx - wx * 0.5, rz - wz * 0.5, wx, wz), open_c],
	]
	for r: Array in _roads:
		if r[1]:
			_open_rects.append(r[0])


# --- Mesh helpers -------------------------------------------------------------------------------

func _surf(key: String) -> SurfaceTool:
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
	return _st[key]


## A triangle facing `want`, with UVs (and UV2s), on surface `key`: "concrete" and "water" get
## tangents from their UVs (the shaders' normal maps and the water's riffles), "ground" (the
## industrial ground: UV world x, z) only normal, colour and UV.
func tri(key: String, a: Vector3, b: Vector3, c: Vector3, want: Vector3, col: Color, ua: Vector2, ub: Vector2, uc: Vector2,
		u2a := Vector2.ZERO, u2b := Vector2.ZERO, u2c := Vector2.ZERO, collide := true) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-10:
		return
	if n.dot(want) < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
		var t2 := u2b
		u2b = u2c
		u2c = t2
		n = -n
	n = n.normalized()
	var st := _surf(key)
	var tangent := Plane()
	var with_tangent := key != "ground"
	if with_tangent:
		var e1 := b - a
		var e2 := c - a
		var d1 := ub - ua
		var d2 := uc - ua
		var det := d1.x * d2.y - d2.x * d1.y
		var tv := Vector3(1.0, 0.0, 0.0)
		var bv := Vector3(0.0, 0.0, 1.0)
		if absf(det) > 1e-8:
			tv = (e1 * d2.y - e2 * d1.y) / det
			bv = (e2 * d1.x - e1 * d2.x) / det
		tv = (tv - n * n.dot(tv))
		if tv.length_squared() < 1e-10:
			tv = n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT)
		tv = tv.normalized()
		var sgn := 1.0 if n.cross(tv).dot(bv) >= 0.0 else -1.0
		tangent = Plane(tv, sgn)
	var vs: Array[Vector3] = [a, b, c]
	var us: Array[Vector2] = [ua, ub, uc]
	var u2s: Array[Vector2] = [u2a, u2b, u2c]
	for i in 3:
		st.set_normal(n)
		if with_tangent:
			st.set_tangent(tangent)
		st.set_color(col)
		st.set_uv(us[i])
		if key == "concrete":
			st.set_uv2(u2s[i])
		st.add_vertex(vs[i])
	if collide:
		_faces.append(a)
		_faces.append(b)
		_faces.append(c)


func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, col: Color,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, u2a := Vector2.ZERO, u2b := Vector2.ZERO,
		u2c := Vector2.ZERO, u2d := Vector2.ZERO, collide := true) -> void:
	tri(key, a, b, c, want, col, ua, ub, uc, u2a, u2b, u2c, collide)
	tri(key, a, c, d, want, col, ua, uc, ud, u2a, u2c, u2d, collide)


static func kind_color(kind: int, side: float) -> Color:
	return Color((float(kind) + 0.5) / 8.0, 0.0 if side > 0.0 else 1.0, 0.0, 1.0)


static func ground_color(kind: int, variant: float = 0.5) -> Color:
	return Color(float(kind) / 16.0 + 0.5 / 16.0, variant, 0.0, 1.0)


## A box on the concrete material (kind, local frame `xf`, size). Its UVs are metres on each face.
func cbox(xf: Transform3D, size: Vector3, kind: int, side: float = 1.0, collide := true, height0 := 0.0) -> void:
	var col := kind_color(kind, side)
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for k in 8:
		corners.append(xf * Vector3(h.x * (1.0 if k & 1 else -1.0), h.y * (1.0 if k & 2 else -1.0), h.z * (1.0 if k & 4 else -1.0)))
	# Corner order: bit 0 x, bit 1 y, bit 2 z. Faces as (a, b, c, d, local outward axis).
	var faces := [[0, 1, 5, 4, Vector3.DOWN], [2, 3, 7, 6, Vector3.UP], [0, 1, 3, 2, Vector3.FORWARD], [4, 5, 7, 6, Vector3.BACK], [0, 2, 6, 4, Vector3.LEFT], [1, 3, 7, 5, Vector3.RIGHT]]
	for f: Array in faces:
		var want: Vector3 = xf.basis * (f[4] as Vector3)
		var a: Vector3 = corners[f[0]]
		var b: Vector3 = corners[f[1]]
		var c: Vector3 = corners[f[2]]
		var d: Vector3 = corners[f[3]]
		var ax := (b - a)
		var ay := (d - a)
		var ua := Vector2.ZERO
		var ub := Vector2(ax.length(), 0.0)
		var uc := Vector2(ax.length(), ay.length())
		var ud := Vector2(0.0, ay.length())
		var u2 := Vector2(a.y - height0, 0.0)
		quad("concrete", a, b, c, d, want, col, ua, ub, uc, ud, u2, u2, u2, u2, collide)


# --- The channel ----------------------------------------------------------------------------------

## The point at `s` and lateral `o`, at height `y` (world, chunk space).
func P(s: float, o: float, y: float) -> Vector3:
	var p := rv.point(s, o)
	return Vector3(p.x, y, p.y)


func _owned_s(i: int) -> bool:
	return area.has_point(rv.pts[i].lerp(rv.pts[i + 1], 0.5))


## Cursors for the time-sliced steps (a step that returns false runs again next time).
var _ci: int = -1
var _row: int = 0
var _bi: int = 0
## Channel segments a channel step builds, and land rows a land step builds.
const SEGMENTS_PER_STEP := 3


func _channel_step() -> bool:
	var stride := 1 if full else 2
	if _ci < 0:
		_ci = ir.x
	var built := 0
	while _ci < ir.y and built < SEGMENTS_PER_STEP * (1 if full else 4):
		var j := mini(_ci + stride, rv.pts.size() - 1)
		if j > _ci and area.has_point(rv.pts[_ci].lerp(rv.pts[j], 0.5)):
			_section(rv.run[_ci], rv.run[j])
			built += 1
		_ci = j
	return _ci >= ir.y


## Outfalls, sediment bars, the ramps this chunk owns and the river's ends.
func _extras_step() -> void:
	if full:
		_outfalls()
		_bars()
	for r: Dictionary in rv.ramps(plan):
		if r.owner == Vector2i(ch.ix, ch.iz):
			_ramp(r)
	if area.has_point(rv.pts[0]):
		_headwall()
	if area.has_point(rv.pts[rv.pts.size() - 1]):
		_mouth()


## The cross section from s0 to s1: notch, bed and banks both sides, the coping, the water.
func _section(s0: float, s1: float) -> void:
	var lfb := LaRiver.LF_BOTTOM_HALF
	var lf := LaRiver.lf_half()
	var ss: Array[float] = [s0, s1]
	var top: Array[float] = [rv.top_at(s0), rv.top_at(s1)]
	var toe: Array[float] = [top[0] - rv.depth(s0), top[1] - rv.depth(s1)]
	var edge: Array[float] = [toe[0] - LaRiver.BED_FALL, toe[1] - LaRiver.BED_FALL]
	var bottom: Array[float] = [edge[0] - LaRiver.LF_DEPTH, edge[1] - LaRiver.LF_DEPTH]
	var bh: Array[float] = [rv.bed_half(s0), rv.bed_half(s1)]
	var th: Array[float] = [rv.top_half(s0), rv.top_half(s1)]
	# The notch's flat bottom, both sides at once.
	quad("concrete", P(s0, -lfb, bottom[0]), P(s1, -lfb, bottom[1]), P(s1, lfb, bottom[1]), P(s0, lfb, bottom[0]), Vector3.UP,
		kind_color(KIND_NOTCH, 1.0), Vector2(s0, -lfb), Vector2(s1, -lfb), Vector2(s1, lfb), Vector2(s0, lfb),
		Vector2(-LaRiver.LF_DEPTH, lfb), Vector2(-LaRiver.LF_DEPTH, lfb), Vector2(-LaRiver.LF_DEPTH, lfb), Vector2(-LaRiver.LF_DEPTH, lfb))
	for sg: float in [1.0, -1.0]:
		var c_notch := kind_color(KIND_NOTCH, sg)
		var c_bed := kind_color(KIND_BED, sg)
		var c_bank := kind_color(KIND_BANK, sg)
		# Notch side.
		quad("concrete", P(s0, sg * lfb, bottom[0]), P(s1, sg * lfb, bottom[1]), P(s1, sg * lf, edge[1]), P(s0, sg * lf, edge[0]), Vector3.UP,
			c_notch, Vector2(s0, sg * lfb), Vector2(s1, sg * lfb), Vector2(s1, sg * lf), Vector2(s0, sg * lf),
			Vector2(-LaRiver.LF_DEPTH, lfb), Vector2(-LaRiver.LF_DEPTH, lfb), Vector2(0.0, lf), Vector2(0.0, lf))
		# Bed, in two strips so a long span is not one sliver.
		var mid0 := (lf + bh[0]) * 0.5
		var mid1 := (lf + bh[1]) * 0.5
		var ym0 := lerpf(edge[0], toe[0], 0.5)
		var ym1 := lerpf(edge[1], toe[1], 0.5)
		quad("concrete", P(s0, sg * lf, edge[0]), P(s1, sg * lf, edge[1]), P(s1, sg * mid1, ym1), P(s0, sg * mid0, ym0), Vector3.UP,
			c_bed, Vector2(s0, sg * lf), Vector2(s1, sg * lf), Vector2(s1, sg * mid1), Vector2(s0, sg * mid0),
			Vector2(0.0, lf), Vector2(0.0, lf), Vector2(ym1 - edge[1], mid1), Vector2(ym0 - edge[0], mid0))
		quad("concrete", P(s0, sg * mid0, ym0), P(s1, sg * mid1, ym1), P(s1, sg * bh[1], toe[1]), P(s0, sg * bh[0], toe[0]), Vector3.UP,
			c_bed, Vector2(s0, sg * mid0), Vector2(s1, sg * mid1), Vector2(s1, sg * bh[1]), Vector2(s0, sg * bh[0]),
			Vector2(ym0 - edge[0], mid0), Vector2(ym1 - edge[1], mid1), Vector2(LaRiver.BED_FALL, bh[1]), Vector2(LaRiver.BED_FALL, bh[0]))
		# Bank: UV.y the slope distance down from the top edge.
		var k := sqrt(1.0 + 1.0 / (LaRiver.SLOPE * LaRiver.SLOPE))
		var v0 := (th[0] - bh[0]) * k
		var v1 := (th[1] - bh[1]) * k
		var steps := 2 if full else 1
		for m in steps:
			var f0 := float(m) / steps
			var f1 := float(m + 1) / steps
			var a0 := lerpf(bh[0], th[0], f0)
			var a1 := lerpf(bh[1], th[1], f0)
			var b0 := lerpf(bh[0], th[0], f1)
			var b1 := lerpf(bh[1], th[1], f1)
			var ya0 := lerpf(toe[0], top[0], f0)
			var ya1 := lerpf(toe[1], top[1], f0)
			var yb0 := lerpf(toe[0], top[0], f1)
			var yb1 := lerpf(toe[1], top[1], f1)
			quad("concrete", P(s0, sg * a0, ya0), P(s1, sg * a1, ya1), P(s1, sg * b1, yb1), P(s0, sg * b0, yb0), Vector3.UP,
				c_bank, Vector2(s0, v0 * (1.0 - f0)), Vector2(s1, v1 * (1.0 - f0)), Vector2(s1, v1 * (1.0 - f1)), Vector2(s0, v0 * (1.0 - f1)),
				Vector2(ya0 - edge[0], a0), Vector2(ya1 - edge[1], a1), Vector2(yb1 - edge[1], b1), Vector2(yb0 - edge[0], b0))
		_coping(s0, s1, sg)
	_water(s0, s1)


## The coping kerb along one bank's top edge from s0 to s1, in 2 m pieces, left out under every
## open road (a bridge's deck lies over it) and at a ramp's head.
func _coping(s0: float, s1: float, sg: float) -> void:
	var n := maxi(1, ceili((s1 - s0) / 2.0))
	var c := kind_color(KIND_COPING, sg)
	var hgt := LaRiver.COPING_H
	var road := CityChunk.ROAD_TOP
	for m in n:
		var a := lerpf(s0, s1, float(m) / n)
		var b := lerpf(s0, s1, float(m + 1) / n)
		var mid := (a + b) * 0.5
		var t := rv.top_half(mid)
		var q := rv.point(mid, sg * (t + LaRiver.COPING_W * 0.5))
		var cut := false
		for r: Rect2 in _open_rects:
			if r.grow(0.4).has_point(q):
				cut = true
				break
		for cc: Array in _coping_cuts:
			if sg == float(cc[2]) and mid > float(cc[0]) and mid < float(cc[1]):
				cut = true
		if cut:
			continue
		var ta := rv.top_half(a)
		var tb := rv.top_half(b)
		var ya := rv.top_at(a)
		var yb := rv.top_at(b)
		var wo := LaRiver.COPING_W
		# Inner face, top, outer face.
		quad("concrete", P(a, sg * ta, ya - 0.05), P(b, sg * tb, yb - 0.05), P(b, sg * tb, yb + hgt), P(a, sg * ta, ya + hgt),
			Vector3(0.0, 0.0, 0.0) + _lat(mid, -sg), c, Vector2(a, 0.0), Vector2(b, 0.0), Vector2(b, hgt), Vector2(a, hgt),
			Vector2(hgt, ta), Vector2(hgt, tb), Vector2(hgt, tb), Vector2(hgt, ta))
		quad("concrete", P(a, sg * ta, ya + hgt), P(b, sg * tb, yb + hgt), P(b, sg * (tb + wo), yb + hgt), P(a, sg * (ta + wo), ya + hgt),
			Vector3.UP, c, Vector2(a, 0.0), Vector2(b, 0.0), Vector2(b, wo), Vector2(a, wo),
			Vector2(hgt, ta), Vector2(hgt, tb), Vector2(hgt, tb), Vector2(hgt, ta))
		quad("concrete", P(a, sg * (ta + wo), ya + road), P(b, sg * (tb + wo), yb + road), P(b, sg * (tb + wo), yb + hgt), P(a, sg * (ta + wo), ya + hgt),
			_lat(mid, sg), c, Vector2(a, 0.0), Vector2(b, 0.0), Vector2(b, hgt - road), Vector2(a, hgt - road),
			Vector2(hgt, ta), Vector2(hgt, tb), Vector2(hgt, tb), Vector2(hgt, ta))


## The horizontal unit vector across the river at `s`, toward side `sg` (+1 west).
func _lat(s: float, sg: float) -> Vector3:
	var d: Vector2 = rv.at(s)[1]
	return Vector3(-d.y, 0.0, d.x) * sg


func _water(s0: float, s1: float) -> void:
	var w := LaRiver.LF_BOTTOM_HALF + LaRiver.LF_SIDE * (LaRiver.WATER_DEPTH / LaRiver.LF_DEPTH) + 0.08
	var y0 := rv.water_at(s0)
	var y1 := rv.water_at(s1)
	var col := Color(1.0, 1.0, 1.0, 1.0)
	tri("water", P(s0, -w, y0), P(s1, -w, y1), P(s1, w, y1), Vector3.UP, col, Vector2(s0, -w), Vector2(s1, -w), Vector2(s1, w), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
	tri("water", P(s0, -w, y0), P(s1, w, y1), P(s0, w, y0), Vector3.UP, col, Vector2(s0, -w), Vector2(s1, w), Vector2(s0, w), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)


## The drain outfalls on this chunk's stretch: a square concrete headwall flush on the bank with a
## pipe mouth in it (LaRiver.outfall_at(): the shader paints the same slots' stains).
func _outfalls() -> void:
	var s_lo := INF
	var s_hi := -INF
	for i in range(ir.x, ir.y):
		if _owned_s(i):
			s_lo = minf(s_lo, rv.run[i])
			s_hi = maxf(s_hi, rv.run[i + 1])
	if s_lo > s_hi:
		return
	for k in range(maxi(0, floori(s_lo / LaRiver.OUTFALL_PITCH)), ceili(s_hi / LaRiver.OUTFALL_PITCH) + 1):
		var s := (float(k) + 0.5) * LaRiver.OUTFALL_PITCH
		if s < s_lo or s >= s_hi or s < 30.0 or s > rv.length - LaRiver.MOUTH_RUN:
			continue
		for side in 2:
			if not LaRiver.outfall_at(k, side):
				continue
			var sg := 1.0 if side == 0 else -1.0
			_outfall(s, sg, k)


func _outfall(s: float, sg: float, k: int) -> void:
	var th := rv.top_half(s)
	var top := rv.top_at(s)
	var slope_k := sqrt(1.0 + LaRiver.SLOPE * LaRiver.SLOPE)
	# 1.8 m down the slope from the top edge (the shader's outfall_v).
	var dv := 1.8
	var a := th - dv * LaRiver.SLOPE / slope_k
	var y := top - dv / slope_k
	var d: Vector2 = rv.at(s)[1]
	var along := Vector3(d.x, 0.0, d.y)
	var inward := -_lat(s, sg)
	# The bank's outward normal (up and out of the channel's side).
	var bank_n := (Vector3.UP * LaRiver.SLOPE + inward * 1.0).normalized()
	var down := bank_n.cross(along).normalized()
	if down.y > 0.0:
		down = -down
	var centre := P(s, sg * a, y)
	var r := 0.45 + 0.25 * rv.h01(["outfall_r", k, sg])
	# Headwall: a square slab a little proud of the bank.
	var hw := Basis(along, -down, bank_n)
	cbox(Transform3D(hw, centre + bank_n * 0.12), Vector3(r * 2.0 + 0.9, r * 2.0 + 0.9, 0.3), KIND_WALL, sg, true, rv.toe_at(s) - LaRiver.BED_FALL)
	# The pipe: a short ring out of the headwall, its mouth dark.
	var segs := 12
	var out := (bank_n * 0.6 + Vector3.DOWN * 0.15).normalized()
	var c0 := centre + bank_n * 0.27
	var c1 := c0 + out * 0.45
	var u := along
	var v := out.cross(u).normalized()
	var col := kind_color(KIND_WALL, sg)
	for m in segs:
		var t0 := TAU * m / segs
		var t1 := TAU * (m + 1) / segs
		var e0 := u * cos(t0) + v * sin(t0)
		var e1 := u * cos(t1) + v * sin(t1)
		quad("concrete", c0 + e0 * r, c1 + e0 * r, c1 + e1 * r, c0 + e1 * r, (e0 + e1).normalized(), col,
			Vector2(t0 * r, 0.0), Vector2(t0 * r, 0.45), Vector2(t1 * r, 0.45), Vector2(t1 * r, 0.0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
		quad("concrete", c1 + e0 * r, c1 + e0 * (r - 0.08), c1 + e1 * (r - 0.08), c1 + e1 * r, out, col,
			Vector2(0.0, 0.0), Vector2(0.0, 0.08), Vector2(0.3, 0.08), Vector2(0.3, 0.0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
	# The dark mouth.
	var dark := kind_color(KIND_DARK, sg)
	for m in segs:
		var t0 := TAU * m / segs
		var t1 := TAU * (m + 1) / segs
		tri("concrete", c0 + out * 0.2, c0 + out * 0.2 + (u * cos(t0) + v * sin(t0)) * (r - 0.06), c0 + out * 0.2 + (u * cos(t1) + v * sin(t1)) * (r - 0.06),
			out, dark, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)


## Sediment bars on the bed of this chunk's stretch, each with reeds and a shrub or two.
func _bars() -> void:
	var s_lo := INF
	var s_hi := -INF
	for i in range(ir.x, ir.y):
		if _owned_s(i):
			s_lo = minf(s_lo, rv.run[i])
			s_hi = maxf(s_hi, rv.run[i + 1])
	if s_lo > s_hi:
		return
	for bar: Dictionary in rv.bars_in(s_lo, s_hi):
		var mid := (float(bar.s0) + float(bar.s1)) * 0.5
		if mid < s_lo or mid >= s_hi or _near_pier(mid, 14.0):
			continue
		_bar(bar)


## True within `pad` metres (along the river) of a bridge or the rail bridge.
func _near_pier(s: float, pad: float) -> bool:
	for br: Dictionary in rv.bridges(plan):
		if absf(float(br.s) - s) < pad + 40.0:
			return true
	var rail := rv.rail_bridge(plan)
	if not rail.is_empty() and absf(float(rail.s) - s) < pad + 12.0:
		return true
	for r: Dictionary in rv.ramps(plan):
		if s > minf(r.s0, r.s1) - pad and s < maxf(r.s0, r.s1) + pad:
			return true
	return false


func _bar(bar: Dictionary) -> void:
	var s0: float = bar.s0
	var s1: float = bar.s1
	var sg: float = bar.side
	var width: float = bar.width
	var lf := LaRiver.lf_half() + 0.4
	var n := 10
	var m := 3
	var grid: Array = []
	for i in n + 1:
		var t := float(i) / n
		var s := lerpf(s0, s1, t)
		var wt := width * pow(sin(t * PI), 0.6)
		var row: Array[Vector3] = []
		for j in m + 1:
			var f := float(j) / m
			var o := lf + wt * f
			var bump := 0.2 * sin(f * PI) * pow(sin(t * PI), 0.5)
			var base := rv.surface(s, sg * o)
			row.append(P(s, sg * o, base + 0.03 + bump))
		grid.append(row)
	var col := ground_color(G_DIRT if rv.h01(["bar_kind", bar.k]) < 0.5 else G_WEEDS, rv.h01(["bar_var", bar.k]))
	for i in n:
		for j in m:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var c: Vector3 = grid[i + 1][j + 1]
			var d: Vector3 = grid[i][j + 1]
			quad("ground", a, b, c, d, Vector3.UP, col, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), Vector2(d.x, d.z))
	# Reeds along the bar and a shrub or two on its crown.
	var reed := PropFactory.model_grass_clump(1)
	var count := int(clampf((s1 - s0) * width / 14.0, 3.0, 40.0))
	for q in count:
		var t := 0.08 + 0.84 * rv.h01(["reed_t", bar.k, q])
		var f := 0.15 + 0.7 * rv.h01(["reed_f", bar.k, q])
		var s := lerpf(s0, s1, t)
		var o := lf + width * pow(sin(t * PI), 0.6) * f
		var y := rv.surface(s, sg * o) + 0.12
		var p := P(s, sg * o, y)
		var sc := lerpf(1.6, 2.6, rv.h01(["reed_s", bar.k, q]))
		ch._batch.add("rv_reed", reed, Transform3D(Basis(Vector3.UP, rv.h01(["reed_y", bar.k, q]) * TAU).scaled(Vector3(sc * 0.8, sc, sc * 0.8)), _rel(p)), Color(0.82, 0.86, 0.62))
	for q in int(1 + rv.h01(["bar_shrubs", bar.k]) * 2.0):
		var t := 0.3 + 0.4 * rv.h01(["shrub_t", bar.k, q])
		var s := lerpf(s0, s1, t)
		var o := lf + width * 0.45
		var p := P(s, sg * o, rv.surface(s, sg * o) + 0.15)
		var sc := lerpf(0.9, 1.6, rv.h01(["shrub_s", bar.k, q]))
		ch._batch.add("rv_shrub", PropFactory.model_bush(int(rv.h01(["shrub_v", bar.k, q]) * 3.0)), Transform3D(Basis(Vector3.UP, rv.h01(["shrub_y", bar.k, q]) * TAU).scaled(Vector3.ONE * sc), _rel(p)), Color(0.9, 0.95, 0.8))
	ch._batch.set_draw_distance("rv_reed", PLANT_DISTANCE)
	ch._batch.set_draw_distance("rv_shrub", PLANT_DISTANCE)


## A world (chunk-space) point as a batch position: the batch adds the relief itself.
func _rel(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y - ch._gy(p.x, p.z), p.z)


## An access ramp down one bank: a concrete lane RAMP_WIDTH wide laid along the slope from the top
## edge (s0) to the bed (s1), its outer edge on the bank, a wall down from its inner edge to the
## bank and a low kerb wall along that edge; the coping is opened at its head.
func _ramp(r: Dictionary) -> void:
	var s0: float = r.s0
	var s1: float = r.s1
	var sg: float = r.side
	var w := LaRiver.RAMP_WIDTH
	var n := 18 if full else 6
	var col := kind_color(KIND_WALL, sg)
	var prev: Array = []
	for i in n + 1:
		var t := float(i) / n
		var s := lerpf(s0, s1, t)
		var top := rv.top_at(s)
		var toe := rv.toe_at(s)
		# The lane eases off the top and onto the bed.
		var e := t * t * (3.0 - 2.0 * t) * 0.25 + t * 0.75
		var y := lerpf(top + CityChunk.ROAD_TOP, toe + 0.02, e)
		var outer := clampf(rv.bed_half(s) + (y - toe) * LaRiver.SLOPE, rv.bed_half(s), rv.top_half(s))
		var inner := outer - w
		var under := rv.surface(s, sg * inner)
		var cur := [P(s, sg * outer, y), P(s, sg * inner, y), P(s, sg * inner, under - 0.05), s, y]
		if not prev.is_empty():
			var pa: float = prev[3]
			# The lane.
			quad("concrete", prev[0], cur[0], cur[1], prev[1], Vector3.UP, kind_color(KIND_BED, sg),
				Vector2(pa, 0.0), Vector2(s, 0.0), Vector2(s, w), Vector2(pa, w),
				Vector2(float(prev[4]) - toe, outer), Vector2(y - toe, outer), Vector2(y - toe, inner), Vector2(float(prev[4]) - toe, inner))
			# The wall down from its inner edge.
			if float(prev[4]) - (prev[2] as Vector3).y > 0.08 or y - under > 0.08:
				quad("concrete", prev[1], cur[1], cur[2], prev[2], _lat(s, -sg), col,
					Vector2(pa, float(prev[4])), Vector2(s, y), Vector2(s, under), Vector2(pa, (prev[2] as Vector3).y),
					Vector2(1.0, inner), Vector2(1.0, inner), Vector2(0.0, inner), Vector2(0.0, inner))
			# A kerb wall along that edge, down most of the way.
			if t < 0.92:
				var kh := 0.55
				var lo0: Vector3 = prev[1]
				var lo1: Vector3 = cur[1]
				var hi0 := lo0 + Vector3.UP * kh
				var hi1 := lo1 + Vector3.UP * kh
				var inw := _lat(s, sg) * 0.3
				quad("concrete", lo0, lo1, hi1, hi0, _lat(s, sg), col, Vector2(pa, 0.0), Vector2(s, 0.0), Vector2(s, kh), Vector2(pa, kh))
				quad("concrete", hi0, hi1, hi1 + inw, hi0 + inw, Vector3.UP, kind_color(KIND_COPING, sg), Vector2(pa, 0.0), Vector2(s, 0.0), Vector2(s, 0.3), Vector2(pa, 0.3))
				quad("concrete", lo0 - Vector3.UP * 0.1, lo1 - Vector3.UP * 0.1, hi1, hi0, _lat(s, -sg), col, Vector2(pa, 0.0), Vector2(s, 0.0), Vector2(s, kh), Vector2(pa, kh))
		prev = cur


## The north end: a concrete headwall across the channel with two box culverts the river comes out
## of, and wing walls up the banks.
func _headwall() -> void:
	var s := 0.0
	var top := rv.top_at(s)
	var th := rv.top_half(s) + LaRiver.COPING_W
	var bottom := rv.toe_at(s) - LaRiver.BED_FALL - LaRiver.LF_DEPTH
	var d: Vector2 = rv.at(s)[1]
	var along := Vector3(d.x, 0.0, d.y)
	var c := P(s, 0.0, (top + 1.2 + bottom) * 0.5) - along * 0.6
	var basis := Basis(_lat(s, 1.0), Vector3.UP, -along)
	cbox(Transform3D(basis, c), Vector3(th * 2.0 + 1.0, top + 1.2 - bottom, 1.2), KIND_WALL, 1.0, true, bottom)
	# The culverts' dark mouths.
	for k: float in [-1.0, 1.0]:
		var o := k * 4.2
		var mouth := P(s, o, bottom + 1.9) + along * 0.02
		cbox(Transform3D(basis, mouth), Vector3(6.6, 3.6, 0.04), KIND_DARK, 1.0, false)
		# The culvert's head and walls round the mouth.
		cbox(Transform3D(basis, P(s, o, bottom + 3.95) + along * 0.25), Vector3(7.4, 0.5, 0.5), KIND_WALL, 1.0, false)


## The mouth: end walls closing the banks and an apron run out onto the sand.
func _mouth() -> void:
	var s := rv.length
	var d: Vector2 = rv.at(s)[1]
	var along := Vector3(d.x, 0.0, d.y)
	var top := rv.top_at(s)
	var toe := rv.toe_at(s)
	var th := rv.top_half(s)
	var bh := rv.bed_half(s)
	for sg: float in [1.0, -1.0]:
		var a := P(s, sg * bh, toe)
		var b := P(s, sg * th, top)
		var c := P(s, sg * (th + LaRiver.CORRIDOR), top)
		var e := P(s, sg * (th + LaRiver.CORRIDOR), toe - 1.0)
		var f := P(s, sg * bh, toe - 1.0)
		quad("concrete", a, b, c, e, along, kind_color(KIND_WALL, sg), Vector2(0, 0), Vector2(1, 1), Vector2(2, 1), Vector2(2, 0))
		tri("concrete", a, e, f, along, kind_color(KIND_WALL, sg), Vector2(0, 0), Vector2(2, 0), Vector2(0, -1))
	# The apron: the bed carried 22 m on out at the sand's level.
	var w := th
	var y0 := toe - LaRiver.BED_FALL
	var p0 := P(s, -w, y0)
	var p1 := P(s, w, y0)
	var p2 := p1 + along * 22.0 + Vector3(0.0, -maxf(y0 - 0.25, 0.0), 0.0)
	var p3 := p0 + along * 22.0 + Vector3(0.0, -maxf(y0 - 0.25, 0.0), 0.0)
	quad("concrete", p0, p1, p2, p3, Vector3.UP, kind_color(KIND_BED, 1.0), Vector2(s, -w), Vector2(s, w), Vector2(s + 22.0, w), Vector2(s + 22.0, -w))


# --- The land --------------------------------------------------------------------------------------

## The land's working state (_land_prep): the corridor's bands, the road outlines, the cell grid.
var _land: Dictionary = {}


func _land_prep() -> void:
	var cell := 12.0 if full else 18.0
	var top_o := func(s: float) -> float: return rv.top_half(s) + LaRiver.COPING_W
	var road_o := func(s: float) -> float: return rv.top_half(s) + LaRiver.COPING_W + LaRiver.BANK_ROAD
	var i0 := maxi(ir.x - 1, 0)
	var i1 := mini(ir.y + 1, rv.pts.size() - 1)
	var road_polys: Array[PackedVector2Array] = []
	for r: Array in _roads:
		road_polys.append(_rect_poly(r[0]))
	_land = {
		"outer": rv.band(i0, i1, Callable(func(s: float) -> float: return -road_o.call(s)), road_o),
		"inner": rv.band(i0, i1, Callable(func(s: float) -> float: return -top_o.call(s)), top_o),
		"roads": road_polys,
		"ring": _rect_poly(block_rect.grow(-PAVEMENT)),
		"nx": maxi(1, ceili(area.size.x / cell)),
		"nz": maxi(1, ceili(area.size.y / cell)),
		"reach": LaRiver.BED_HALF_S + LaRiver.DEPTH_S * LaRiver.SLOPE + LaRiver.CORRIDOR + cell * 1.5,
	}


## One row of the land's cells a step: the bank roads, the closed streets' stubs, the pavement
## along the block's edge and the yard inside, each cut out of the cell exactly.
func _land_step() -> bool:
	var nx: int = _land.nx
	var nz: int = _land.nz
	var outer: PackedVector2Array = _land.outer
	var inner: PackedVector2Array = _land.inner
	var road_polys: Array = _land.roads
	var ring: PackedVector2Array = _land.ring
	var reach: float = _land.reach
	var gz := _row
	for gx in nx:
		var cr := Rect2(area.position + Vector2(gx, gz) * area.size / Vector2(nx, nz), area.size / Vector2(nx, nz))
		var cpoly := _rect_poly(cr)
		var nr := rv.nearest(cr.get_center(), reach)
		var near_river := nr.w > 0.5
		var land: Array[PackedVector2Array] = [cpoly]
		var bank: Array[PackedVector2Array] = []
		if near_river:
			land = _clip_all(land, outer)
			for piece in Geometry2D.intersect_polygons(cpoly, outer):
				for q in Geometry2D.clip_polygons(piece, inner):
					if not Geometry2D.is_polygon_clockwise(q):
						bank.append(q)
		# The roads: open ones are the chunk's own slabs; closed ones are stubs, laid here.
		for k in _roads.size():
			var r: Array = _roads[k]
			if not (r[0] as Rect2).intersects(cr):
				continue
			land = _clip_all(land, road_polys[k])
			if r[1]:
				bank = _clip_all(bank, road_polys[k])
			else:
				var stub: Array[PackedVector2Array] = []
				for piece in Geometry2D.intersect_polygons(cpoly, road_polys[k]):
					if not Geometry2D.is_polygon_clockwise(piece):
						stub.append(piece)
				if near_river:
					stub = _clip_all(stub, outer)
				for p in stub:
					_fill("ground", p, CityChunk.ROAD_TOP, ground_color(G_ASPHALT, 0.3), false, false)
		for p in bank:
			_fill("ground", p, CityChunk.ROAD_TOP, ground_color(G_ASPHALT, 0.7), false, false)
		var in_ring := block_rect.grow(-PAVEMENT).encloses(cr)
		for p in land:
			if in_ring:
				_fill("ground", p, CityChunk.SIDEWALK_TOP + 0.02, _yard_color(cr.get_center()), true, near_river)
				continue
			# Pavement along the block's edge, yard inside.
			for q in Geometry2D.clip_polygons(p, ring):
				if not Geometry2D.is_polygon_clockwise(q):
					_fill("ground", q, CityChunk.SIDEWALK_TOP, ground_color(G_CONCRETE, 0.5), true, near_river)
			for q in Geometry2D.intersect_polygons(p, ring):
				if not Geometry2D.is_polygon_clockwise(q):
					_fill("ground", q, CityChunk.SIDEWALK_TOP + 0.02, _yard_color(q[0]), true, near_river)
	_row += 1
	return _row >= nz


## One yard surface a block (the ground shader varies it itself): gravel, dirt or old asphalt.
func _yard_color(_at: Vector2) -> Color:
	var hv := rv.h01(["yard", ch.ix, ch.iz])
	var kind := G_GRAVEL
	if hv < 0.25:
		kind = G_DIRT
	elif hv < 0.4:
		kind = G_ASPHALT
	return ground_color(kind, hv)


## The fences, the stubs' barriers, the pavement's lamps and the freight tracks (FULL), one a step.
var _prop_i := 0


func _props_step() -> bool:
	if not full:
		return true
	match _prop_i:
		0:
			_fences()
		1:
			_stub_ends()
			_lamps()
		2:
			_tracks()
		3:
			_yard_dress()
	_prop_i += 1
	return _prop_i >= 4


## The yard inside the block, clear of the tracks: a few storage yards of Industrial's (a corrugated
## shed, containers, pallet loads, drums, or tanks in a containment wall), and scrub along the
## fence. Rects are hashed from the seed and the block; only those wholly in the yard are kept.
const YARD_STORES := 5
func _yard_dress() -> void:
	var yard := block_rect.grow(-PAVEMENT - 1.5)
	if yard.size.x < 12.0 or yard.size.y < 12.0:
		return
	var pad := LaRiver.CORRIDOR + TRACK_OUT + BALLAST_HALF + 3.0 - LaRiver.CORRIDOR
	var taken: Array[Rect2] = []
	for k in 12:
		if taken.size() >= YARD_STORES:
			break
		var key := ["store", ch.ix, ch.iz, k]
		var long_x := rv.h01(key + ["lx"]) < 0.5
		var a := lerpf(18.0, 40.0, rv.h01(key + ["a"]))
		var b := lerpf(12.0, 19.0, rv.h01(key + ["b"]))
		var size := Vector2(a, b) if long_x else Vector2(b, a)
		if size.x > yard.size.x or size.y > yard.size.y:
			continue
		var pos := yard.position + Vector2(rv.h01(key + ["x"]) * (yard.size.x - size.x), rv.h01(key + ["z"]) * (yard.size.y - size.y))
		var r := Rect2(pos, size)
		var ok := Industrial.clear_of_freeway(plan, r)
		for t: Rect2 in taken:
			if t.grow(3.0).intersects(r):
				ok = false
		if ok:
			for i in 9:
				var q := r.position + r.size * Vector2(float(i % 3) * 0.5, float(i / 3) * 0.5)
				if rv.in_corridor(q, pad):
					ok = false
					break
		if not ok:
			continue
		taken.append(r)
		var seed_k := absi(hash([rv.seed, "rv_store", ch.ix, ch.iz, k]))
		if taken.size() % 2 == 1:
			_trailer_row(r, seed_k)
		else:
			Industrial._store(ch, r, seed_k, G_GRAVEL)
	# Scrub along the fence on the yard's side.
	var shrubs := 0
	for sg: float in [1.0, -1.0]:
		var s := rv.run[ir.x]
		while s < rv.run[ir.y] and shrubs < 14:
			var key2 := ["scrub", ch.ix, ch.iz, int(s), sg]
			s += lerpf(6.0, 16.0, rv.h01(key2))
			var off := rv.top_half(s) + LaRiver.COPING_W + LaRiver.BANK_ROAD + LaRiver.FENCE_OUT + 1.2
			var p := rv.point(s, sg * off)
			if not yard.has_point(p) or rv.h01(key2 + ["k"]) < 0.4:
				continue
			var at := Vector3(p.x, CityChunk.SIDEWALK_TOP + 0.02, p.y)
			var sc := lerpf(0.8, 1.5, rv.h01(key2 + ["s"]))
			ch._batch.add("rv_shrub", PropFactory.model_bush(int(rv.h01(key2 + ["v"]) * 3.0)), Transform3D(Basis(Vector3.UP, rv.h01(key2 + ["y"]) * TAU).scaled(Vector3.ONE * sc), at), Color(0.9, 0.92, 0.75))
			shrubs += 1
	ch._batch.set_draw_distance("rv_shrub", PLANT_DISTANCE)


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## `polys` less `hole`, keeping only outer outlines (a hole inside a cell cannot happen: the
## corridor and the roads are wider than a cell).
static func _clip_all(polys: Array[PackedVector2Array], hole: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for p in polys:
		for q in Geometry2D.clip_polygons(p, hole):
			if not Geometry2D.is_polygon_clockwise(q):
				out.append(q)
	return out


## A flat piece of ground at `top` over the relief, on the industrial ground material, with a kerb
## face down to the road where `kerb` and an edge lies on the block's edge or on the bank road.
func _fill(key: String, poly: PackedVector2Array, top: float, col: Color, kerb: bool, near_river := true) -> void:
	if poly.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return
	var pts3: Array[Vector3] = []
	for p in poly:
		pts3.append(Vector3(p.x, top + ch._gy(p.x, p.y), p.y))
	for t in range(0, idx.size(), 3):
		var a := pts3[idx[t]]
		var b := pts3[idx[t + 1]]
		var c := pts3[idx[t + 2]]
		tri(key, a, b, c, Vector3.UP, col, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
	if not kerb:
		return
	var drop := top - CityChunk.ROAD_TOP + 0.02
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		var m := (p + q) * 0.5
		if not (_on_block_edge(m) or (near_river and _on_bank_road_edge(m))):
			continue
		var a := pts3[k]
		var b := pts3[(k + 1) % poly.size()]
		var e := q - p
		# Outward: away from the polygon's inside.
		var side := Vector2(e.y, -e.x).normalized()
		if Geometry2D.is_point_in_polygon(m + side * 0.05, poly):
			side = -side
		var outn := Vector3(side.x, 0.0, side.y)
		tri(key, a, b, b - Vector3(0.0, drop, 0.0), outn, col, Vector2(a.x + a.z, 0.0), Vector2(b.x + b.z, 0.0), Vector2(b.x + b.z, -drop))
		tri(key, a, b - Vector3(0.0, drop, 0.0), a - Vector3(0.0, drop, 0.0), outn, col, Vector2(a.x + a.z, 0.0), Vector2(b.x + b.z, -drop), Vector2(a.x + a.z, -drop))


func _on_block_edge(m: Vector2) -> bool:
	var r := block_rect
	return (absf(m.x - r.position.x) < 0.05 or absf(m.x - r.end.x) < 0.05) and m.y >= r.position.y - 0.05 and m.y <= r.end.y + 0.05 \
		or (absf(m.y - r.position.y) < 0.05 or absf(m.y - r.end.y) < 0.05) and m.x >= r.position.x - 0.05 and m.x <= r.end.x + 0.05


func _on_bank_road_edge(m: Vector2) -> bool:
	var nr := rv.nearest(m, 80.0)
	if nr.w < 0.5:
		return false
	return absf(absf(nr.y) - (rv.top_half(nr.x) + LaRiver.COPING_W + LaRiver.BANK_ROAD)) < 0.12


## The chain-link along each bank road's outer edge, through this chunk's area, open where a
## street crosses at grade.
func _fences() -> void:
	Industrial._state(ch)
	for sg: float in [1.0, -1.0]:
		var line := PackedVector2Array()
		for i in range(ir.x, ir.y + 1):
			var s := rv.run[i]
			line.append(rv.point(s, sg * (rv.top_half(s) + LaRiver.COPING_W + LaRiver.BANK_ROAD + LaRiver.FENCE_OUT)))
		for k in line.size() - 1:
			for piece: Array in _cut_segment(line[k], line[k + 1]):
				var a: Vector2 = piece[0]
				var b: Vector2 = piece[1]
				if a.distance_to(b) > 0.6:
					Industrial._fence(ch, a, b)


## Segment a-b clipped to the chunk's area and cut by every open road (grown a metre): the pieces.
func _cut_segment(a: Vector2, b: Vector2) -> Array:
	var pieces: Array = []
	var clipped := _clip_to_rect(a, b, area)
	if clipped.is_empty():
		return pieces
	pieces.append(clipped)
	for r: Rect2 in _open_rects:
		var next: Array = []
		for pc: Array in pieces:
			next.append_array(_minus_rect(pc[0], pc[1], r.grow(1.0)))
		pieces = next
	return pieces


## Liang-Barsky: segment a-b inside rect r, as [a', b'] or [].
static func _clip_to_rect(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for k in 4:
		var pk: float = p[k]
		var qk: float = q[k]
		if absf(pk) < 1e-9:
			if qk < 0.0:
				return []
			continue
		var t := qk / pk
		if pk < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
	if t0 >= t1:
		return []
	return [a + d * t0, a + d * t1]


## Segment a-b less rect r: zero, one or two pieces.
static func _minus_rect(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var inside := _clip_to_rect(a, b, r)
	if inside.is_empty():
		return [[a, b]]
	var out: Array = []
	var len := a.distance_to(b)
	if len < 1e-6:
		return out
	var ta := a.distance_to(inside[0]) / len
	var tb := a.distance_to(inside[1]) / len
	if ta > 1e-4:
		out.append([a, a.lerp(b, ta)])
	if tb < 1.0 - 1e-4:
		out.append([a.lerp(b, tb), b])
	return out


## Where a closed street meets the bank road: a row of concrete barriers across its end.
func _stub_ends() -> void:
	for r: Array in _roads:
		if r[1]:
			continue
		var rect: Rect2 = r[0]
		var along_z := rect.size.y > rect.size.x
		var c := rect.get_center()
		var w := rect.size.x if along_z else rect.size.y
		var len := rect.size.y if along_z else rect.size.x
		if len < 6.0:
			continue
		var dir := Vector2(0.0, 1.0) if along_z else Vector2(1.0, 0.0)
		var across := Vector2(1.0, 0.0) if along_z else Vector2(0.0, 1.0)
		# Walk the road's centre line; at every place it passes into the corridor, close it.
		var n := ceili(len)
		var prev_in := rv.in_corridor(c - dir * len * 0.5, 1.2)
		for i in range(1, n + 1):
			var p := c + dir * (-len * 0.5 + len * float(i) / n)
			var now_in := rv.in_corridor(p, 1.2)
			if now_in and not prev_in:
				_barrier_row(p - dir * 1.2, across, w)
			elif prev_in and not now_in:
				_barrier_row(p + dir * 0.2, across, w)
			prev_in = now_in


func _barrier_row(p: Vector2, across: Vector2, w: float) -> void:
	if not area.has_point(p):
		return
	var yaw := atan2(-across.x, -across.y) + PI * 0.5
	var k := int(floor((w - 1.0) / 3.1))
	for i in k:
		var q := p + across * (-(k - 1) * 0.5 + i) * 3.1
		var at := Vector3(q.x, CityChunk.ROAD_TOP, q.y)
		ch._add_prop("barrier", at, Color(0.72, 0.71, 0.68), [
			["barrier", PropFactory.model_barrier(), Transform3D(Basis(Vector3.UP, yaw), at)],
		], [[Vector3(3.0, 0.9, 0.6), at + Vector3(0.0, 0.45, 0.0), yaw]])


## Street lamps along the river block's pavement where its street is open.
func _lamps() -> void:
	var r := block_rect
	var edges := [
		[Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(0.0, 1.0), CityPlan.AXIS_Z, ch.iz],
		[Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(-1.0, 0.0), CityPlan.AXIS_X, ch.ix + 1],
		[Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y), Vector2(0.0, -1.0), CityPlan.AXIS_Z, ch.iz + 1],
		[Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y), Vector2(1.0, 0.0), CityPlan.AXIS_X, ch.ix],
	]
	for e: Array in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var len := a.distance_to(b)
		var n := floori(len / LAMP_GAP)
		for i in n:
			var t := (float(i) + 0.5) / float(n)
			var p := a.lerp(b, t) + inward * 0.8
			var along := (b - a).normalized()
			var mid_along: float = p.x if absf(along.x) > 0.5 else p.y
			if not plan.road_open(int(e[3]), int(e[4]), mid_along):
				continue
			if rv.in_corridor(p, 2.0) or (plan.macro.freeway and plan.macro.freeway.blocks(p, 4.0)):
				continue
			ch._add_lamp(Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y))
			_lamp_count += 1


## A trailer drop yard: semi-trailers parked side by side across the rect's short side, a tractor
## on now and then.
func _trailer_row(r: Rect2, s: int) -> void:
	var long_x := r.size.x >= r.size.y
	var length := r.size.x if long_x else r.size.y
	var depth := r.size.y if long_x else r.size.x
	if depth < 17.0:
		return
	var n := floori((length - 1.0) / 3.7)
	var base := CityChunk.SIDEWALK_TOP + Industrial.LIFT
	for i in n:
		if rv.h01(["trl", s, i]) < 0.22:
			continue
		var t := (r.position.x if long_x else r.position.y) + 2.0 + float(i) * 3.7
		var c := Vector2(t, r.get_center().y) if long_x else Vector2(r.get_center().x, t)
		var face := Vector2(0.0, 1.0) if long_x else Vector2(1.0, 0.0)
		if rv.h01(["trl_f", s]) < 0.5:
			face = -face
		var yaw := Industrial.yaw_to(face) + (rv.h01(["trl_y", s, i]) - 0.5) * 0.05
		var kind := 2 if rv.h01(["trl_k", s, i]) < 0.12 else (1 if rv.h01(["trl_s", s, i]) < 0.3 else 0)
		var paint: Color = Industrial.TRAILER_PAINTS[int(rv.h01(["trl_p", s, i]) * Industrial.TRAILER_PAINTS.size()) % Industrial.TRAILER_PAINTS.size()]
		Industrial._prop(ch, Vector3(c.x, base, c.y), yaw, paint, IndustrialKit.trailer.bind(kind))
		ch._add_shape(Vector3(2.6, 3.0, 16.2), Vector3(c.x, base + ch._gy(c.x, c.y) + 2.55, c.y), yaw)


## The freight tracks along the river on the block's yard, at TRACK_OUT past each fence: ballast,
## ties, rails; now and then a string of boxcars standing on them.
func _tracks() -> void:
	Industrial._state(ch)
	var yard := block_rect.grow(-PAVEMENT - 1.0)
	for sg: float in [1.0, -1.0]:
		var run_pts: Array = []
		var s := rv.run[ir.x]
		var s_end := rv.run[ir.y]
		while s <= s_end:
			var off := rv.top_half(s) + LaRiver.COPING_W + LaRiver.BANK_ROAD + LaRiver.FENCE_OUT + TRACK_OUT
			var p := rv.point(s, sg * off)
			var ok := yard.has_point(p) and yard.has_point(rv.point(s, sg * (off + BALLAST_HALF))) and yard.has_point(rv.point(s, sg * (off - BALLAST_HALF)))
			if ok and plan.macro.freeway and plan.macro.freeway.blocks(p, 3.0):
				ok = false
			if ok:
				run_pts.append([s, off])
			elif run_pts.size() > 0:
				_track_run(run_pts, sg)
				run_pts = []
			s += 2.0
		if run_pts.size() > 0:
			_track_run(run_pts, sg)


func _track_run(run_pts: Array, sg: float) -> void:
	if run_pts.size() < 6:
		return
	var tie := PropFactory.unit_box()
	var top_base := CityChunk.SIDEWALK_TOP + 0.04
	for k in run_pts.size() - 1:
		var sa: float = run_pts[k][0]
		var sb: float = run_pts[k + 1][0]
		var oa: float = run_pts[k][1]
		var ob: float = run_pts[k + 1][1]
		# Ballast: a raised strip on the yard.
		var a0 := rv.point(sa, sg * (oa - BALLAST_HALF))
		var a1 := rv.point(sa, sg * (oa + BALLAST_HALF))
		var b0 := rv.point(sb, sg * (ob - BALLAST_HALF))
		var b1 := rv.point(sb, sg * (ob + BALLAST_HALF))
		var poly := PackedVector2Array([a0, b0, b1, a1])
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		_fill("ground", poly, top_base + 0.1, ground_color(G_GRAVEL, 0.15), false)
		# Rails.
		var pa := rv.point(sa, sg * oa)
		var pb := rv.point(sb, sg * ob)
		var d := (pb - pa)
		var len := d.length()
		if len < 0.01:
			continue
		var yaw := atan2(-d.x, -d.y)
		var basis := Basis(Vector3.UP, yaw)
		var across := Vector2(-d.y, d.x) / len
		var mid := (pa + pb) * 0.5
		var g := ch._gy(mid.x, mid.y)
		for rs: float in [-0.7175, 0.7175]:
			var rp := mid + across * rs
			Industrial._wbox(ch, Transform3D(basis, Vector3(rp.x, top_base + 0.28 + g, rp.y)), Vector3(0.08, 0.15, len + 0.02), IndustrialKit.K_STEEL, Color(0.36, 0.3, 0.26), 0.0, 32)
		# Ties.
		var nt := maxi(1, int(len / TIE_GAP))
		for t in nt:
			var q := pa.lerp(pb, (float(t) + 0.5) / nt)
			ch._batch.add("rv_tie", tie, Transform3D(basis.scaled_local(Vector3(2.6, 0.16, 0.24)), Vector3(q.x, top_base + 0.18, q.y)), Color(0.24, 0.2, 0.17))
	ch._batch.set_draw_distance("rv_tie", TIE_DISTANCE)
	# Freight cars.
	var first: float = run_pts[0][0]
	var last: float = run_pts[run_pts.size() - 1][0]
	var key := [int(first / 50.0), sg]
	if rv.h01(["cars"] + key) >= TRACK_CARS or last - first < 40.0:
		return
	var pos := first + 4.0 + rv.h01(["cars_at"] + key) * 10.0
	var i := 0
	while pos + 16.0 < last - 3.0 and i < 6:
		var mid_s := pos + 8.1
		var off: float = run_pts[0][1]
		var pm := rv.point(mid_s, sg * off)
		var d2: Vector2 = rv.at(mid_s)[1]
		var tank := rv.h01(["tank"] + key + [i]) < 0.3
		var paint: Color = Industrial.BOXCAR_PAINTS[int(rv.h01(["paint"] + key + [i]) * Industrial.BOXCAR_PAINTS.size()) % Industrial.BOXCAR_PAINTS.size()]
		if tank:
			paint = Color(0.13, 0.13, 0.13)
		Industrial._prop(ch, Vector3(pm.x, top_base + 0.36, pm.y), atan2(-d2.x, -d2.y), paint, IndustrialKit.tank_car if tank else IndustrialKit.boxcar)
		ch._add_shape(Vector3(3.2, 4.2, 16.0), Vector3(pm.x, top_base + 0.36 + ch._gy(pm.x, pm.y) + 2.6, pm.y), atan2(-d2.x, -d2.y))
		pos += 17.2
		i += 1


# --- Bridges ---------------------------------------------------------------------------------------

## One bridge job a step (RiverBridges.jobs(): an arch viaduct is a dozen of them).
var _jobs: Array[Callable] = []
var _jobs_ready := false


func _bridge_step() -> bool:
	if not _jobs_ready:
		_jobs_ready = true
		var me := Vector2i(ch.ix, ch.iz)
		for br: Dictionary in rv.bridges(plan):
			if br.owner == me:
				_jobs.append_array(RiverBridges.jobs(self, br))
		var rail := rv.rail_bridge(plan)
		if not rail.is_empty() and rail.owner == me:
			_jobs.append_array(RiverBridges.rail_jobs(self, rail))
	if _bi < _jobs.size():
		_jobs[_bi].call()
		_bi += 1
	return _bi >= _jobs.size()


# --- Commit ----------------------------------------------------------------------------------------

static var _concrete_mat: ShaderMaterial
static var _water_mat: ShaderMaterial
static var _lamp_mat: ShaderMaterial


static func concrete_material() -> ShaderMaterial:
	if _concrete_mat == null:
		_concrete_mat = ShaderMaterial.new()
		_concrete_mat.shader = load("res://shaders/river_concrete.gdshader")
		_concrete_mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
		_concrete_mat.set_shader_parameter("concrete_nrm", PropFactory.texture("concrete", "NormalGL"))
		_concrete_mat.set_shader_parameter("tag_atlas", load("res://assets/textures/street_wear/street_wear_tags.png"))
		_concrete_mat.set_shader_parameter("outfall_pitch", LaRiver.OUTFALL_PITCH)
		_concrete_mat.set_shader_parameter("outfall_odds", LaRiver.OUTFALL_ODDS)
	return _concrete_mat


static func water_material() -> ShaderMaterial:
	if _water_mat == null:
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = load("res://shaders/river_water.gdshader")
		_water_mat.set_shader_parameter("half_width", LaRiver.LF_BOTTOM_HALF + LaRiver.LF_SIDE * (LaRiver.WATER_DEPTH / LaRiver.LF_DEPTH))
	return _water_mat


static func lamp_material() -> ShaderMaterial:
	if _lamp_mat == null:
		_lamp_mat = ShaderMaterial.new()
		_lamp_mat.shader = load("res://shaders/river_lamp.gdshader")
	return _lamp_mat


func _commit_step() -> void:
	var mats := {"concrete": concrete_material(), "water": water_material(), "ground": Industrial.ground_material(), "lamp": lamp_material()}
	var names := {"concrete": "RiverConcrete", "water": "RiverWater", "ground": "RiverGround", "lamp": "RiverLamps"}
	for key: String in _st:
		var st: SurfaceTool = _st[key]
		var mi := MeshInstance3D.new()
		mi.name = names.get(key, "River_" + key)
		mi.mesh = st.commit()
		mi.material_override = mats.get(key, concrete_material())
		if key == "ground" or key == "water":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)
	_st.clear()
	ch._batch.set_no_shadow("rv_tie")
	ch._batch.set_no_shadow("rv_reed")
	if _faces.size() >= 3 and (full or ch._lod_collision_wanted()):
		var body := StaticBody3D.new()
		body.name = "RiverBody"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(_faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		ch.add_child(body)
	_faces = PackedVector3Array()


# --- The far city ------------------------------------------------------------------------------------

## The capture (CityChunk.capturing): what the far city (Skyline) draws of a river block - its land
## as flat boxes in z slices, the open streets on it, the channel's banks, bed and water as tilted
## boxes, the bridges as deck boxes. Skyline sinks the block's plate under the channel.
static func capture(c: CityChunk) -> void:
	var b := RiverBuild.new()
	b._setup(c)
	b._capture()


const FAR_LAND := Color(0.36, 0.34, 0.31)
const FAR_ROAD := Color(0.10, 0.10, 0.105)
const FAR_BANK := Color(0.50, 0.48, 0.44)
const FAR_BED := Color(0.40, 0.38, 0.35)
const FAR_WATER := Color(0.05, 0.07, 0.05)


## How far a river block's far plate goes down: under the lowest bed in the block.
static func far_plate_drop(c: CityChunk) -> float:
	var rv: LaRiver = c.plan.macro.river
	var area := c.owned_rect()
	var ir2 := rv.index_range(area, 60.0)
	var low := INF
	for i in range(ir2.x, ir2.y + 1):
		low = minf(low, rv.toe_at(rv.run[i]) - LaRiver.BED_FALL - LaRiver.LF_DEPTH)
	var mid := area.get_center()
	if low == INF:
		return 0.0
	return maxf(c._gy(mid.x, mid.y) - low + 0.3, 0.0)


func _capture() -> void:
	var boxes: Array = ch.captured.boxes
	var slice := 8.0
	var nz := maxi(1, ceili(area.size.y / slice))
	var floor_y := INF
	for i in range(ir.x, ir.y + 1):
		floor_y = minf(floor_y, rv.toe_at(rv.run[i]) - 1.0)
	if floor_y == INF:
		floor_y = 0.0
	# Land and roads in z slices, the channel's opening taken out of each.
	for k in nz:
		var z0 := area.position.y + area.size.y * k / nz
		var z1 := area.position.y + area.size.y * (k + 1) / nz
		var zc := (z0 + z1) * 0.5
		var gap := _channel_span(zc)
		var spans: Array = []
		if gap.is_empty():
			spans.append([area.position.x, area.end.x])
		else:
			if gap[0] > area.position.x:
				spans.append([area.position.x, minf(gap[0], area.end.x)])
			if gap[1] < area.end.x:
				spans.append([maxf(gap[1], area.position.x), area.end.x])
		for sp: Array in spans:
			_far_land(float(sp[0]), float(sp[1]), z0, z1, floor_y, boxes)
	# The channel: per four points, the bed, the water and the two banks as boxes.
	var i := ir.x
	while i < ir.y:
		var j := mini(i + 4, rv.pts.size() - 1)
		if area.has_point(rv.pts[i].lerp(rv.pts[j], 0.5)):
			_far_channel(rv.run[i], rv.run[j], boxes)
		i = j
	for br: Dictionary in rv.bridges(plan):
		if br.owner == Vector2i(ch.ix, ch.iz):
			_far_bridge(br, boxes)


## The x interval of the channel's opening (with its coping) across z slice centre `zc`, or [].
func _channel_span(zc: float) -> Array:
	var n := rv.pts.size()
	if zc < rv.pts[0].y or zc > rv.pts[n - 1].y:
		return []
	var i := clampi(rv._first_index_z(zc), 0, n - 2)
	var a := rv.pts[i]
	var b := rv.pts[i + 1]
	var f := clampf((zc - a.y) / maxf(b.y - a.y, 0.001), 0.0, 1.0)
	var xc := lerpf(a.x, b.x, f)
	var d := (b - a).normalized()
	var s := lerpf(rv.run[i], rv.run[i + 1], f)
	# A horizontal line crosses the opening over (half width) / |cos| of the river's heading.
	var hw := (rv.top_half(s) + LaRiver.COPING_W) / maxf(absf(d.y), 0.3)
	return [xc - hw - 1.0, xc + hw + 1.0]


func _far_land(x0: float, x1: float, z0: float, z1: float, floor_y: float, boxes: Array) -> void:
	if x1 - x0 < 0.5:
		return
	# The open +X road across the slice is asphalt; a slice inside the open +Z road is asphalt.
	var cuts: Array = [[x0, x1, FAR_LAND]]
	var rx: Rect2 = _roads[0][0]
	var rz: Rect2 = _roads[1][0]
	var zc := (z0 + z1) * 0.5
	var road_slice: bool = _roads[1][1] and zc > rz.position.y and zc < rz.end.y
	if road_slice:
		cuts = [[x0, x1, FAR_ROAD]]
	elif _roads[0][1] and rx.end.x > x0 and rx.position.x < x1:
		cuts = []
		if rx.position.x > x0:
			cuts.append([x0, rx.position.x, FAR_LAND])
		cuts.append([maxf(rx.position.x, x0), minf(rx.end.x, x1), FAR_ROAD])
		if rx.end.x < x1:
			cuts.append([rx.end.x, x1, FAR_LAND])
	for cu: Array in cuts:
		var a: float = cu[0]
		var b: float = cu[1]
		if b - a < 0.3:
			continue
		var cx := (a + b) * 0.5
		var top := ch._gy(cx, zc) + CityChunk.ROAD_TOP
		var h := maxf(top - floor_y, 0.5)
		boxes.append([Transform3D(Basis().scaled(Vector3(b - a, h, z1 - z0)), Vector3(cx, top - h * 0.5, zc)), cu[2]])


func _far_channel(s0: float, s1: float, boxes: Array) -> void:
	var sm := (s0 + s1) * 0.5
	var pd := rv.at(sm)
	var d: Vector2 = pd[1]
	var len := s1 - s0 + 0.6
	var yaw := atan2(-d.x, -d.y)
	var base := Basis(Vector3.UP, yaw)
	var bh := rv.bed_half(sm)
	var th := rv.top_half(sm)
	var top := rv.top_at(sm)
	var toe := rv.toe_at(sm)
	var bed := P(sm, 0.0, toe - 0.4)
	boxes.append([Transform3D(base.scaled_local(Vector3(bh * 2.0, 0.6, len)), bed), FAR_BED])
	var wat := P(sm, 0.0, rv.water_at(sm) - 0.2)
	boxes.append([Transform3D(base.scaled_local(Vector3(LaRiver.lf_half() * 1.2, 0.5, len)), wat), FAR_WATER])
	var run_w := th - bh
	var slope_len := sqrt(run_w * run_w + (top - toe) * (top - toe))
	var tilt := atan2(top - toe, run_w)
	for sg: float in [1.0, -1.0]:
		var mid := P(sm, sg * (bh + th) * 0.5, (toe + top) * 0.5)
		var tb := base * Basis(Vector3.BACK, tilt * sg)
		boxes.append([Transform3D(tb.scaled_local(Vector3(slope_len + 0.6, 0.5, len)), mid - Vector3.UP * 0.25), FAR_BANK])


func _far_bridge(br: Dictionary, boxes: Array) -> void:
	var along: Vector2 = br.along
	var p0: Vector2 = br.p0
	var t0: float = br.t0
	var t1: float = br.t1
	var c := p0 + along * ((t0 + t1) * 0.5)
	var top := ch._gy(c.x, c.y) + CityChunk.ROAD_TOP
	var w: float = float(br.width) + 6.0
	var size := Vector3(w, 1.4, t1 - t0) if br.axis == CityPlan.AXIS_X else Vector3(t1 - t0, 1.4, w)
	boxes.append([Transform3D(Basis().scaled(size), Vector3(c.x, top - 0.75, c.y)), FAR_BANK])
