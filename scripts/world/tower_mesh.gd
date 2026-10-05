class_name TowerMesh
extends RefCounted
## A geometry kit for the downtown towers (LandmarkDowntown): plans are outlines - rectangles,
## chamfers, notches, circles, ellipses, bowed faces - extruded into tiers with setbacks, and
## crowns, fins and spires built on top. Everything a tower is goes into ONE ArrayMesh:
##
##   - one surface per facade material, on shaders/building.gdshader in its `uv_facade` mode, so
##     a round tower gets the same traced window recesses, rooms, lit offices and emitted glass
##     mirror as every box in the city. UV.x is metres round the outline, with each face (a run
##     of edges between two sharp corners) a whole number of bays, so no window is cut by a
##     corner; UV.y is the face index, or 100+ for a solid wall (a parapet, a blank band).
##   - "metal": fins, frames, spires, slabs, helipads - vertex-coloured StandardMaterial3D.
##   - "glow": the lit crowns (shaders/tower_crown.gdshader), glass by day.
##
## So a tower is three to five draw calls whatever its shape, and the far copy CityStreamer keeps
## and the detailed one a chunk builds share the same mesh.
##
## Outlines are PackedVector2Array in local XZ with POSITIVE signed area (x, z as a math plane:
## north-west, north-east, south-east, south-west). With that order an edge's outward normal is
## its direction turned (d.z, -d.x), the building shader's wall tangent (-n.z, n.x) is the edge
## direction, and Godot's clockwise front faces work out as written below.

## Adjacent edges turning less than this share a smoothed normal and one run of bays (a curve);
## more, and the corner is sharp.
const SMOOTH_TURN_DEG := 24.0
## How far in the parapet ring reaches from the wall face, and how tall the lip stands.
const PARAPET_WIDTH := 0.8
const PARAPET_HEIGHT := 1.1
## Metres an occluder box is pulled in from the wall (CityChunk.OCCLUDER_INSET's rule: an
## occluder must never stick out past what it stands for).
const OCCLUDER_INSET := 1.75

## The window bay every facade surface is laid out on.
var pitch: float = 1.6
## Facade surfaces by style name: [SurfaceTool, material].
var facades: Dictionary = {}
var metal := SurfaceTool.new()
var glow := SurfaceTool.new()
var _metal_used := false
var _glow_used := false
var metal_material: Material
var glow_material: Material
## Convex hulls for collision (local points), occluder boxes (local AABB) and aviation / crown
## point lights ([local position, colour, size m, kind]; see shaders/aircraft_lights.gdshader).
var hulls: Array[PackedVector3Array] = []
var occluders: Array[AABB] = []
var lights: Array = []
## The plan's extent in local XZ, grown by every prism (the footprint the landmark stands on).
var extent := Rect2()
var _extent_set := false
## Height of the highest point built, for the checks.
var top: float = 0.0


func _init(bay: float = 1.6) -> void:
	pitch = bay
	metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)


## Registers a facade style (one surface, one material). The first one added is the default.
func add_facade(style: String, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	facades[style] = [st, material, false]


# --- Outlines --------------------------------------------------------------------------------

static func rect(w: float, d: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-w, -d) * 0.5, Vector2(w, -d) * 0.5, Vector2(w, d) * 0.5, Vector2(-w, d) * 0.5])


## A rectangle with its four corners cut at 45 degrees by `c`.
static func chamfered(w: float, d: float, c: float) -> PackedVector2Array:
	var hw := w * 0.5
	var hd := d * 0.5
	return PackedVector2Array([
		Vector2(-hw + c, -hd), Vector2(hw - c, -hd), Vector2(hw, -hd + c), Vector2(hw, hd - c),
		Vector2(hw - c, hd), Vector2(-hw + c, hd), Vector2(-hw, hd - c), Vector2(-hw, -hd + c)])


## A rectangle with its four corners stepped in by `n` (a re-entrant notch, the way stone towers
## of the eighties turn a corner).
static func notched(w: float, d: float, n: float) -> PackedVector2Array:
	var hw := w * 0.5
	var hd := d * 0.5
	return PackedVector2Array([
		Vector2(-hw + n, -hd), Vector2(hw - n, -hd), Vector2(hw - n, -hd + n), Vector2(hw, -hd + n),
		Vector2(hw, hd - n), Vector2(hw - n, hd - n), Vector2(hw - n, hd), Vector2(-hw + n, hd),
		Vector2(-hw + n, hd - n), Vector2(-hw, hd - n), Vector2(-hw, -hd + n), Vector2(-hw + n, -hd + n)])


static func ellipse(rx: float, rz: float, segments: int = 48, start: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in segments:
		var a := start + TAU * float(i) / float(segments)
		out.append(Vector2(cos(a) * rx, sin(a) * rz))
	return out


static func circle(r: float, segments: int = 48) -> PackedVector2Array:
	return ellipse(r, r, segments, PI / float(segments))


## A rectangle with round corners of radius `r`.
static func rounded(w: float, d: float, r: float, corner_segments: int = 5) -> PackedVector2Array:
	var out := PackedVector2Array()
	var hw := w * 0.5 - r
	var hd := d * 0.5 - r
	# Corner centres NW, NE, SE, SW with the arc each sweeps (x, z math-plane angles).
	var centres := [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]
	var starts := [PI, 1.5 * PI, 0.0, 0.5 * PI]
	for c in 4:
		for k in corner_segments + 1:
			var a: float = starts[c] + 0.5 * PI * float(k) / float(corner_segments)
			out.append((centres[c] as Vector2) + Vector2(cos(a), sin(a)) * r)
	return out


## A rectangle whose four faces bow outward by `bow_w` (the faces along X) and `bow_d` (along Z),
## with the corners cut by `c`. The curved glass slab of the eighties and nineties.
static func bowed(w: float, d: float, bow_w: float, bow_d: float, c: float, arc_segments: int = 10) -> PackedVector2Array:
	var hw := w * 0.5
	var hd := d * 0.5
	var corners := [Vector2(-hw + c, -hd), Vector2(hw - c, -hd), Vector2(hw, -hd + c), Vector2(hw, hd - c),
		Vector2(hw - c, hd), Vector2(-hw + c, hd), Vector2(-hw, hd - c), Vector2(-hw, -hd + c)]
	var out := PackedVector2Array()
	for i in 4:
		var a: Vector2 = corners[i * 2]
		var b: Vector2 = corners[i * 2 + 1]
		var bow := bow_w if i % 2 == 0 else bow_d
		var n := (b - a).normalized()
		var outward := Vector2(n.y, -n.x)
		for k in arc_segments + 1:
			var t := float(k) / float(arc_segments)
			out.append(a.lerp(b, t) + outward * bow * 4.0 * t * (1.0 - t))
	return out


static func moved(outline: PackedVector2Array, offset: Vector2, scale: Vector2 = Vector2.ONE, turn: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in outline:
		out.append((p * scale).rotated(turn) + offset)
	return out


## The outline pulled in by `d` metres along each corner's mitre. Good for the small insets this
## kit uses (parapet rings, setbacks) on convex and mildly re-entrant plans.
static func inset(outline: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := outline.size()
	var out := PackedVector2Array()
	for i in n:
		var prev := outline[(i + n - 1) % n]
		var cur := outline[i]
		var nxt := outline[(i + 1) % n]
		var e0 := (cur - prev).normalized()
		var e1 := (nxt - cur).normalized()
		var n0 := Vector2(e0.y, -e0.x)
		var n1 := Vector2(e1.y, -e1.x)
		var m := n0 + n1
		var ml := m.length()
		if ml < 0.001:
			out.append(cur - n0 * d)
			continue
		m /= ml
		var k := d / maxf(m.dot(n0), 0.35)
		out.append(cur - m * k)
	return out


# --- Tiers -----------------------------------------------------------------------------------

## One tier of a facade: walls from y0 to y1, a parapet lip and a roof with its ring.
## `solid` draws the walls as blank wall (a podium band, a mechanical floor). `parapet` false
## leaves the top open (something sits on it: a crown, the next tier flush with it).
func prism(outline: PackedVector2Array, y0: float, y1: float, style: String = "", solid: bool = false,
		parapet: bool = true, collide: bool = true) -> void:
	var st: SurfaceTool = _facade(style)
	var top_y := y1 + (PARAPET_HEIGHT if parapet else 0.0)
	_walls(st, outline, y0, y1, solid)
	if parapet:
		var ring := inset(outline, PARAPET_WIDTH)
		# The lip: its outer face (blank wall, not a sliver of the next floor's windows), its
		# inner face, the ring on top of it, then the roof inside it.
		_walls(st, outline, y1, top_y, true)
		_walls(st, _reversed(ring), y1, top_y, true)
		_ring(st, outline, ring, top_y, 0.0)
		_cap(st, ring, y1, 1.0)
	else:
		_cap(st, outline, y1, 1.0)
	_grow(outline, top_y)
	if collide:
		_hull(outline, y0, y1)
	_occlude(outline, y0, y1)


## A tier whose roof is a sloped plane, y = y1 + slope . (p - pivot) (local metres): the faceted
## granite towers' angled tops. `roof` with alpha > 0 puts the sloped roof in the glow surface
## in that colour (a lit glass top) instead of drawing it as roof.
func sloped(outline: PackedVector2Array, y0: float, y1: float, slope: Vector2, pivot: Vector2 = Vector2.ZERO,
		style: String = "", roof: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var st: SurfaceTool = _facade(style)
	var n := outline.size()
	var runs := _runs(outline)
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		_quad_wall(st, a, b, y0, y0, y1 + slope.dot(a - pivot), y1 + slope.dot(b - pivot), runs, i, false)
	var nrm := Vector3(-slope.x, 1.0, -slope.y).normalized()
	var tris := Geometry2D.triangulate_polygon(outline)
	var roof_st := st if roof.a <= 0.0 else _metal_or_glow("glow")
	for t in range(0, tris.size(), 3):
		var p: Array[Vector3] = []
		for k in 3:
			var q := outline[tris[t + k]]
			p.append(Vector3(q.x, y1 + slope.dot(q - pivot), q.y))
		if roof.a <= 0.0:
			# Drawn as roof (UV.x 1: no parapet ring on a slope).
			_tri(roof_st, p[0], p[1], p[2], nrm, [Vector2(1.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.0)], Color.WHITE, false)
		else:
			_tri(roof_st, p[0], p[1], p[2], nrm, [Vector2(p[0].x, p[0].z), Vector2(p[1].x, p[1].z), Vector2(p[2].x, p[2].z)], roof)
	var hi := y1
	var lo := y1
	for q in outline:
		hi = maxf(hi, y1 + slope.dot(q - pivot))
		lo = minf(lo, y1 + slope.dot(q - pivot))
	_grow(outline, hi)
	_hull(outline, y0, lo)
	_occlude(outline, y0, lo)


# --- Metal and glow --------------------------------------------------------------------------

## Walls and a lid between two outlines of the same vertex count (a taper, a drum, a lantern).
## `surface` is "metal" or "glow"; `lit` is the glow strength carried in COLOR.a.
func loft(surface: String, a: PackedVector2Array, ya: float, b: PackedVector2Array, yb: float, color: Color,
		lit: float = 1.0, lid: bool = true, collide: bool = true) -> void:
	var st := _metal_or_glow(surface)
	var n := a.size()
	if collide and absf(yb - ya) > 2.0 and absf(_signed_area(a)) > 12.0:
		var hull := PackedVector3Array()
		for p in a:
			hull.append(Vector3(p.x, ya, p.y))
		for p in b:
			hull.append(Vector3(p.x, yb, p.y))
		hulls.append(hull)
	var u := 0.0
	for i in n:
		var a0 := a[i]
		var a1 := a[(i + 1) % n]
		var b0 := b[i]
		var b1 := b[(i + 1) % n]
		var p00 := Vector3(a0.x, ya, a0.y)
		var p10 := Vector3(a1.x, ya, a1.y)
		var p01 := Vector3(b0.x, yb, b0.y)
		var p11 := Vector3(b1.x, yb, b1.y)
		var nrm := (p01 - p00).cross(p10 - p00).normalized()
		if nrm.length() < 0.5:
			nrm = (p11 - p10).cross(p00 - p10).normalized() * -1.0
		var len_a := a0.distance_to(a1)
		var h := yb - ya
		var col := Color(color.r, color.g, color.b, lit)
		# Clockwise seen from outside: top of the next corner, top of this one, bottom of this one.
		_v(st, p11, nrm, Vector2(u + len_a, h), col)
		_v(st, p01, nrm, Vector2(u, h), col)
		_v(st, p00, nrm, Vector2(u, 0.0), col)
		_v(st, p11, nrm, Vector2(u + len_a, h), col)
		_v(st, p00, nrm, Vector2(u, 0.0), col)
		_v(st, p10, nrm, Vector2(u + len_a, 0.0), col)
		u += len_a
	if lid and b.size() >= 3:
		_flat(st, b, yb, color, lit)
	_grow(a, maxf(ya, yb))
	top = maxf(top, maxf(ya, yb))


## A flat horizontal polygon facing up (a slab, a helipad, a lid).
func slab(surface: String, outline: PackedVector2Array, y0: float, y1: float, color: Color, lit: float = 0.0) -> void:
	loft(surface, outline, y0, outline, y1, color, lit, true)


## A box as metal or glow, its X side turned `turn` radians toward +Z in the ground plane (so
## a box laid along direction d takes turn = atan2(d.z, d.x)).
func box(surface: String, centre: Vector3, size: Vector3, color: Color, turn: float = 0.0, lit: float = 0.0, collide: bool = false) -> void:
	var o := moved(rect(size.x, size.z), Vector2(centre.x, centre.z), Vector2.ONE, turn)
	loft(surface, o, centre.y - size.y * 0.5, o, centre.y + size.y * 0.5, color, lit, true, collide)


## A cone or pyramid from `outline` at y0 to a point at apex (local xyz).
func spike(surface: String, outline: PackedVector2Array, y0: float, apex: Vector3, color: Color, lit: float = 0.0) -> void:
	var st := _metal_or_glow(surface)
	var n := outline.size()
	var col := Color(color.r, color.g, color.b, lit)
	var u := 0.0
	for i in n:
		var a := Vector3(outline[i].x, y0, outline[i].y)
		var b := Vector3(outline[(i + 1) % n].x, y0, outline[(i + 1) % n].y)
		var nrm := (apex - a).cross(b - a).normalized()
		var la := a.distance_to(b)
		_v(st, apex, nrm, Vector2(u + la * 0.5, apex.y - y0), col)
		_v(st, a, nrm, Vector2(u, 0.0), col)
		_v(st, b, nrm, Vector2(u + la, 0.0), col)
		u += la
	top = maxf(top, apex.y)


## A slender mast from `base` up `height`, tapering to `tip_r` - spires and antennas.
func mast(base: Vector3, height: float, r: float, tip_r: float, color: Color, segments: int = 12) -> void:
	var a := moved(circle(r, segments), Vector2(base.x, base.z))
	var b := moved(circle(tip_r, segments), Vector2(base.x, base.z))
	loft("metal", a, base.y, b, base.y + height, color, 0.0, true)


## Vertical fins standing proud of an outline every `spacing` metres, from y0 to y1 - mullion
## caps, the ribs of a lantern, the blades of a crown.
func fins(outline: PackedVector2Array, y0: float, y1: float, spacing: float, depth: float, width: float,
		color: Color, surface: String = "metal", lit: float = 0.0, margin: float = 0.0) -> void:
	var n := outline.size()
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var len := a.distance_to(b)
		var d := (b - a) / maxf(len, 0.001)
		var out := Vector2(d.y, -d.x)
		# Centred on the edge, and kept `margin` clear of its ends (a rounded or cut corner).
		var count := int(floor((len - 2.0 * margin) / spacing)) + 1
		if count < 1:
			continue
		var s := (len - float(count - 1) * spacing) * 0.5
		for k in count:
			var p := a + d * (s + float(k) * spacing) + out * depth * 0.5
			box(surface, Vector3(p.x, (y0 + y1) * 0.5, p.y), Vector3(width, y1 - y0, depth), color, atan2(d.y, d.x), lit)


## A barrel vault along X: a half cylinder of `radius` standing on y0, `length` long, centred
## on `centre` (x, z) - the rounded crown.
func vault(surface: String, centre: Vector3, length: float, radius: float, color: Color, lit: float = 1.0, segments: int = 16) -> void:
	var st := _metal_or_glow(surface)
	var col := Color(color.r, color.g, color.b, lit)
	var x0 := centre.x - length * 0.5
	var x1 := centre.x + length * 0.5
	var arc := PI * radius
	for i in segments:
		var t0 := PI * float(i) / float(segments)
		var t1 := PI * float(i + 1) / float(segments)
		var p0 := Vector3(0.0, centre.y + sin(t0) * radius, centre.z + cos(t0) * radius)
		var p1 := Vector3(0.0, centre.y + sin(t1) * radius, centre.z + cos(t1) * radius)
		var nm := Vector3(0.0, sin((t0 + t1) * 0.5), cos((t0 + t1) * 0.5))
		var u0 := arc * float(i) / float(segments)
		var u1 := arc * float(i + 1) / float(segments)
		var a := Vector3(x0, p0.y, p0.z)
		var b := Vector3(x1, p0.y, p0.z)
		var c := Vector3(x1, p1.y, p1.z)
		var d := Vector3(x0, p1.y, p1.z)
		_tri(st, a, b, c, nm, [Vector2(u0, 0.0), Vector2(u0, length), Vector2(u1, length)], col)
		_tri(st, a, c, d, nm, [Vector2(u0, 0.0), Vector2(u1, length), Vector2(u1, 0.0)], col)
		# The two half-disc ends.
		for side: float in [-1.0, 1.0]:
			var x := centre.x + side * length * 0.5
			var o := Vector3(x, centre.y, centre.z)
			_tri(st, o, Vector3(x, p0.y, p0.z), Vector3(x, p1.y, p1.z), Vector3(side, 0.0, 0.0),
				[Vector2(0.0, 0.0), Vector2(u0, radius), Vector2(u1, radius)], col)
	_grow(PackedVector2Array([Vector2(x0, centre.z - radius), Vector2(x1, centre.z + radius)]), centre.y + radius)
	var hull := PackedVector3Array()
	for s in 5:
		var t := PI * float(s) / 4.0
		for x in [x0, x1]:
			hull.append(Vector3(x, centre.y + sin(t) * radius, centre.z + cos(t) * radius))
	hulls.append(hull)


## A tier whose top is a sloped plane, as metal or glow: y = y1 + slope . (p - pivot).
## The sail crown.
func wedge(surface: String, outline: PackedVector2Array, y0: float, y1: float, slope: Vector2, pivot: Vector2,
		color: Color, lit: float = 1.0) -> void:
	var st := _metal_or_glow(surface)
	var col := Color(color.r, color.g, color.b, lit)
	var n := outline.size()
	var u := 0.0
	var hull := PackedVector3Array()
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var ya := y1 + slope.dot(a - pivot)
		var yb := y1 + slope.dot(b - pivot)
		var d := (b - a).normalized()
		var nm := Vector3(d.y, 0.0, -d.x)
		var la := a.distance_to(b)
		var a0 := Vector3(a.x, y0, a.y)
		var b0 := Vector3(b.x, y0, b.y)
		var a1 := Vector3(a.x, ya, a.y)
		var b1 := Vector3(b.x, yb, b.y)
		_tri(st, b1, a1, a0, nm, [Vector2(u + la, yb - y0), Vector2(u, ya - y0), Vector2(u, 0.0)], col)
		_tri(st, b1, a0, b0, nm, [Vector2(u + la, yb - y0), Vector2(u, 0.0), Vector2(u + la, 0.0)], col)
		u += la
		hull.append(a0)
		hull.append(a1)
		top = maxf(top, ya)
	var nrm := Vector3(-slope.x, 1.0, -slope.y).normalized()
	var tris := Geometry2D.triangulate_polygon(outline)
	for t in range(0, tris.size(), 3):
		var p: Array[Vector3] = []
		for k in 3:
			var q := outline[tris[t + k]]
			p.append(Vector3(q.x, y1 + slope.dot(q - pivot), q.y))
		_tri(st, p[0], p[1], p[2], nrm, [Vector2(p[0].x, p[0].z), Vector2(p[1].x, p[1].z), Vector2(p[2].x, p[2].z)], col)
	_grow(outline, top)
	hulls.append(hull)


## One floor's balcony slab: the part of `outline` between arc lengths s0 and s1 (metres round
## it, wrapping), pushed out `depth`, `thick` metres thick with its top at y. For twisting and
## staggered balcony faces on the residential towers.
func balcony(outline: PackedVector2Array, s0: float, s1: float, y: float, depth: float, thick: float, color: Color) -> void:
	var n := outline.size()
	var lengths: Array[float] = []
	var total := 0.0
	for i in n:
		var l := outline[i].distance_to(outline[(i + 1) % n])
		lengths.append(l)
		total += l
	var along: PackedVector2Array = PackedVector2Array()
	var outward: PackedVector2Array = PackedVector2Array()
	var steps := maxi(3, int(ceil((s1 - s0) / 2.4)))
	for k in steps + 1:
		var s := fposmod(lerpf(s0, s1, float(k) / float(steps)), total)
		var i := 0
		while i < n - 1 and s > lengths[i]:
			s -= lengths[i]
			i += 1
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var d := (b - a).normalized()
		along.append(a + d * minf(s, lengths[i]))
		outward.append(Vector2(d.y, -d.x))
	# The slab's plan: the wall line out, then the rail line back.
	var plan := PackedVector2Array()
	for k in along.size():
		plan.append(along[k] - outward[k] * 0.05)
	for k in range(along.size() - 1, -1, -1):
		plan.append(along[k] + outward[k] * depth)
	if _signed_area(plan) < 0.0:
		plan = _reversed(plan)
	loft("metal", plan, y - thick, plan, y, color, 0.0, true, false)


## The union of several outlines (Geometry2D, cleaned, positive area).
static func union(outlines: Array) -> PackedVector2Array:
	var poly: PackedVector2Array = outlines[0]
	for i in range(1, outlines.size()):
		var merged := Geometry2D.merge_polygons(poly, outlines[i])
		var best := PackedVector2Array()
		for m: PackedVector2Array in merged:
			if absf(_signed_area(m)) > absf(_signed_area(best)):
				best = m
		poly = best
	return clean(poly)


## Drops repeated and collinear points and puts the outline in this kit's (positive) order.
static func clean(outline: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in outline:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 0.05:
			pts.append(p)
	if pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) < 0.05:
		pts.remove_at(pts.size() - 1)
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[(i + n - 1) % n]
		var b := pts[i]
		var c := pts[(i + 1) % n]
		var cr := (b - a).normalized().cross((c - b).normalized())
		if absf(cr) > 0.002 or (b - a).dot(c - b) < 0.0:
			out.append(b)
	if _signed_area(out) < 0.0:
		out = _reversed(out)
	return out


static func _signed_area(outline: PackedVector2Array) -> float:
	var s := 0.0
	var n := outline.size()
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## A red (or white) aviation / crown light at a local point. kind 0 steady, 2 beacon.
func light(at: Vector3, color: Color, size: float = 2.2, kind: int = 2) -> void:
	lights.append([at, color, size, kind])


# --- Output ----------------------------------------------------------------------------------

## The finished mesh: one surface per facade style, then metal, then glow.
func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for style: String in facades:
		var entry: Array = facades[style]
		if not entry[2]:
			continue
		var st: SurfaceTool = entry[0]
		st.index()
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, entry[1])
	if _metal_used:
		metal.index()
		metal.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, metal_material)
	if _glow_used:
		glow.index()
		glow.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, glow_material)
	return mesh


## The aviation and crown lights as one billboard mesh (shaders/aircraft_lights.gdshader), or
## null when there are none.
func light_mesh(material: Material) -> ArrayMesh:
	if lights.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	var i := 0
	for spec: Array in lights:
		# A phase per light from its index, so a row of beacons does not pulse in step.
		var code := float(spec[3]) * 10.0 + fposmod(float(i) * 0.37, 1.0) * 9.0
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(spec[1])
			st.set_uv(corners[k])
			st.set_uv2(Vector2(spec[2], code))
			st.set_normal(Vector3.ZERO)
			st.add_vertex(spec[0])
		i += 1
	var mesh := st.commit()
	mesh.surface_set_material(0, material)
	return mesh


func triangle_count(mesh: ArrayMesh) -> int:
	var total := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += idx.size() / 3 if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


# --- Internals -------------------------------------------------------------------------------

func _metal_or_glow(surface: String) -> SurfaceTool:
	if surface == "metal":
		_metal_used = true
		return metal
	_glow_used = true
	return glow


## A triangle that faces `n` whatever order its corners come in (Godot's front faces are
## clockwise seen from in front, which is cross(p1 - p0, p2 - p0) pointing AWAY from the eye).
## Facade surfaces carry no vertex colour (SurfaceTool fixes its format at the first vertex, so
## every vertex of a surface must set the same attributes): pass `with_color` false for them.
static func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3, uvs: Array, col: Color,
		with_color: bool = true) -> void:
	var order := [0, 2, 1] if (p1 - p0).cross(p2 - p0).dot(n) > 0.0 else [0, 1, 2]
	var pts := [p0, p1, p2]
	for k: int in order:
		if with_color:
			st.set_color(col)
		st.set_normal(n)
		st.set_uv(uvs[k])
		st.add_vertex(pts[k])


func _facade(style: String) -> SurfaceTool:
	var key := style
	if key == "" or not facades.has(key):
		key = facades.keys()[0]
	var entry: Array = facades[key]
	entry[2] = true
	return entry[0]


static func _reversed(outline: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(outline.size() - 1, -1, -1):
		out.append(outline[i])
	return out


static func _area(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (a.x * b.y - b.x * a.y) + (b.x * c.y - c.x * b.y) + (c.x * a.y - a.x * c.y)


## For each edge: [run index, u at its start, u at its end, normal at its start, normal at its
## end]. A run is the edges between two sharp corners; its length is rounded to whole bays and
## spread over its edges, so the grid lands exactly on the corners.
func _runs(outline: PackedVector2Array) -> Array:
	var n := outline.size()
	var normals: Array[Vector2] = []
	var lengths: Array[float] = []
	for i in n:
		var d := outline[(i + 1) % n] - outline[i]
		lengths.append(d.length())
		var dn := d.normalized()
		normals.append(Vector2(dn.y, -dn.x))
	var smooth_dot := cos(deg_to_rad(SMOOTH_TURN_DEG))
	# Vertex i sits between edge i-1 and edge i.
	var sharp: Array[bool] = []
	var any_sharp := false
	for i in n:
		var s := normals[(i + n - 1) % n].dot(normals[i]) < smooth_dot
		sharp.append(s)
		any_sharp = any_sharp or s
	var start := 0
	if any_sharp:
		while not sharp[start]:
			start += 1
	var out: Array = []
	out.resize(n)
	var run := 0
	var bays_before := 0
	var k := 0
	while k < n:
		# Collect one run starting at edge (start + k).
		var edges: Array[int] = []
		var total := 0.0
		while true:
			var e := (start + k) % n
			edges.append(e)
			total += lengths[e]
			k += 1
			if k >= n or sharp[(start + k) % n]:
				break
		var bays := maxi(1, roundi(total / pitch))
		var scale := float(bays) * pitch / maxf(total, 0.001)
		var u := float(bays_before) * pitch
		for e in edges:
			var v0 := e
			var v1 := (e + 1) % n
			var n0: Vector2 = normals[e] if sharp[v0] else (normals[(e + n - 1) % n] + normals[e]).normalized()
			var n1: Vector2 = normals[e] if sharp[v1] else (normals[e] + normals[(e + 1) % n]).normalized()
			out[e] = [run, u, u + lengths[e] * scale, n0, n1]
			u += lengths[e] * scale
		bays_before += bays
		run += 1
	return out


func _walls(st: SurfaceTool, outline: PackedVector2Array, y0: float, y1: float, solid: bool) -> void:
	var runs := _runs(outline)
	var n := outline.size()
	for i in n:
		_quad_wall(st, outline[i], outline[(i + 1) % n], y0, y0, y1, y1, runs, i, solid)


func _quad_wall(st: SurfaceTool, a: Vector2, b: Vector2, ya0: float, yb0: float, ya1: float, yb1: float,
		runs: Array, i: int, solid: bool) -> void:
	var r: Array = runs[i]
	var face := float(r[0]) + (100.0 if solid else 0.0)
	var n0 := Vector3((r[3] as Vector2).x, 0.0, (r[3] as Vector2).y)
	var n1 := Vector3((r[4] as Vector2).x, 0.0, (r[4] as Vector2).y)
	var a0 := Vector3(a.x, ya0, a.y)
	var a1 := Vector3(a.x, ya1, a.y)
	var b0 := Vector3(b.x, yb0, b.y)
	var b1 := Vector3(b.x, yb1, b.y)
	var ua: float = r[1]
	var ub: float = r[2]
	# Clockwise seen from outside (u runs a -> b along the wall tangent): b1, a1, a0 / b1, a0, b0.
	for v in [[b1, n1, ub], [a1, n0, ua], [a0, n0, ua], [b1, n1, ub], [a0, n0, ua], [b0, n1, ub]]:
		st.set_normal(v[1])
		st.set_uv(Vector2(v[2], face))
		st.add_vertex(v[0])


## The parapet ring between the wall face and the inset outline, facing up, UV.x 0.
func _ring(st: SurfaceTool, outer: PackedVector2Array, inner: PackedVector2Array, y: float, uvx: float) -> void:
	var n := outer.size()
	for i in n:
		var p0 := Vector3(outer[i].x, y, outer[i].y)
		var p1 := Vector3(outer[(i + 1) % n].x, y, outer[(i + 1) % n].y)
		var q0 := Vector3(inner[i].x, y, inner[i].y)
		var q1 := Vector3(inner[(i + 1) % n].x, y, inner[(i + 1) % n].y)
		for v in [p0, p1, q1, p0, q1, q0]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(uvx, 0.0))
			st.add_vertex(v)


## A flat roof over `outline` at `y`, facing up, UV.x `uvx`.
func _cap(st: SurfaceTool, outline: PackedVector2Array, y: float, uvx: float) -> void:
	var tris := Geometry2D.triangulate_polygon(outline)
	for t in range(0, tris.size(), 3):
		var pts := [outline[tris[t]], outline[tris[t + 1]], outline[tris[t + 2]]]
		if _area(pts[0], pts[1], pts[2]) < 0.0:
			pts = [pts[0], pts[2], pts[1]]
		for p: Vector2 in pts:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(uvx, 0.0))
			st.add_vertex(Vector3(p.x, y, p.y))


func _flat(st: SurfaceTool, outline: PackedVector2Array, y: float, color: Color, lit: float) -> void:
	var tris := Geometry2D.triangulate_polygon(outline)
	var col := Color(color.r, color.g, color.b, lit)
	for t in range(0, tris.size(), 3):
		var pts := [outline[tris[t]], outline[tris[t + 1]], outline[tris[t + 2]]]
		if _area(pts[0], pts[1], pts[2]) < 0.0:
			pts = [pts[0], pts[2], pts[1]]
		for p: Vector2 in pts:
			_v(st, Vector3(p.x, y, p.y), Vector3.UP, Vector2(p.x, p.y), col)


static func _v(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)


func _grow(outline: PackedVector2Array, y_top: float) -> void:
	for p in outline:
		if not _extent_set:
			extent = Rect2(p, Vector2.ZERO)
			_extent_set = true
		else:
			extent = extent.expand(p)
	top = maxf(top, y_top)


func _hull(outline: PackedVector2Array, y0: float, y1: float) -> void:
	var pts := PackedVector3Array()
	for p in outline:
		pts.append(Vector3(p.x, y0, p.y))
		pts.append(Vector3(p.x, y1, p.y))
	hulls.append(pts)


## The biggest centred axis-aligned box that stays inside the outline, pulled in by
## OCCLUDER_INSET. Found by shrinking the bounds until all four corners are inside.
func _occlude(outline: PackedVector2Array, y0: float, y1: float) -> void:
	if y1 - y0 < 8.0:
		return
	var b := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		b = b.expand(p)
	var c := b.get_center()
	var half := b.size * 0.5
	for step in 12:
		var ok := true
		for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			if not Geometry2D.is_point_in_polygon(c + half * s, outline):
				ok = false
				break
		if ok:
			break
		half *= 0.9
	half -= Vector2(OCCLUDER_INSET, OCCLUDER_INSET)
	if half.x < 2.0 or half.y < 2.0:
		return
	occluders.append(AABB(Vector3(c.x - half.x, y0, c.y - half.y), Vector3(half.x * 2.0, y1 - y0 - 1.0, half.y * 2.0)))
