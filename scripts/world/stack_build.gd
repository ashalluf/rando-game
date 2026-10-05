class_name StackBuild
extends RefCounted
## Builds the four-level stack's connectors (FreewayStack) into a chunk's freeway meshes: called
## from CityChunk._build_freeway() with the chunk's FreewayKit, so the connectors share the four
## meshes (asphalt, structure, paint, light pools) the main decks already draw - no extra draw
## calls. Per connector segment the chunk owns (by its midpoint): the asphalt top and a deep box
## girder BANKED into the curve (FreewayStack.frame(): the section turns with the bank), New
## Jersey barriers (the inner one open along the touch run, where the parent's outer barrier is
## open too), two lanes of worn paint with raised markers, and a davit light standard on the
## outside barrier every LIGHT_EVERY segments (none where a deck passes over it), throwing its
## pool on the deck. Columns (FreewayStack.columns()) are single round shafts on a plinth with a
## tapered hammerhead cap, the main line's replacement ones with a wider head; each lights the
## street under it at night. Collision: a banked box per segment, a cylinder per column.

## A davit light every so many connector segments (FreewayStack.LINK_STEP apart).
const LIGHT_EVERY := 5
const CAP_DEPTH := 2.2
const MAIN_CAP_DEPTH := 2.8


## Builds what `chunk` owns; returns how many segments (columns count too).
static func build(chunk: CityChunk, kit: FreewayKit, body: StaticBody3D) -> int:
	var plan := chunk.plan
	if plan.macro == null or plan.macro.freeway == null or plan.macro.freeway.stack == null:
		return 0
	var stack: FreewayStack = plan.macro.freeway.stack
	var area := chunk.owned_rect()
	if not area.grow(900.0).has_point(stack.centre):
		return 0
	var built := 0
	for k in stack.links.size():
		var l: Dictionary = stack.links[k]
		var pts: PackedVector2Array = l.points
		for i in pts.size() - 1:
			if not area.has_point(pts[i].lerp(pts[i + 1], 0.5)):
				continue
			_segment(kit, stack, l, k, i, body)
			built += 1
	for c in stack.columns(plan):
		if area.has_point(c.pos):
			_column(kit, c, body, chunk.level == CityChunk.Level.FULL)
			built += 1
	return built


## A point across the deck: `u` metres right of the centre line, `y` up, on the banked section.
static func lat(f: Array, u: float, y: float) -> Vector3:
	var p: Vector3 = f[0]
	var r: Vector2 = f[1]
	var e: float = f[2]
	return p + Vector3(r.x * u, u * e + y, r.y * u)


static func _want(f: Array, on: Vector2) -> Vector3:
	var r: Vector2 = f[1]
	return Vector3(r.x * on.x, float(f[2]) * on.x + on.y, r.y * on.x).normalized()


## A cross-section swept from frame fa to fb: edge i faces away from `inside`.
static func sweep(kit: FreewayKit, st: SurfaceTool, fa: Array, fb: Array, pts: PackedVector2Array,
		inside: Vector2, cols: Array, run0: float, run1: float, flags: PackedFloat32Array) -> void:
	for i in pts.size() - 1:
		var p := pts[i]
		var q := pts[i + 1]
		var e := q - p
		var on := Vector2(e.y, -e.x).normalized()
		if on.dot((p + q) * 0.5 - inside) < 0.0:
			on = -on
		var soffit := int(round((cols[i] as Color).a * FreewayKit.KIND_SCALE)) == FreewayKit.S_SOFFIT
		var vp := p.x if soffit else p.y
		var vq := q.x if soffit else q.y
		kit.quad(st, lat(fa, p.x, p.y), lat(fa, q.x, q.y), lat(fb, q.x, q.y), lat(fb, p.x, p.y),
			_want(fa, on), cols[i], Vector2(run0, vp), Vector2(run0, vq), Vector2(run1, vq), Vector2(run1, vp),
			Vector2(flags[i], 0.0))


static func _segment(kit: FreewayKit, stack: FreewayStack, l: Dictionary, k: int, i: int, body: StaticBody3D) -> void:
	var fa := FreewayStack.frame(l, i)
	var fb := FreewayStack.frame(l, i + 1)
	var run: PackedFloat32Array = l.run
	var run0 := run[i]
	var run1 := run[i + 1]
	var half := FreewayStack.LINK_WIDTH * 0.5
	var touching := run0 < float(l.touch_a) - 0.1 or run1 > float(l.touch_b) + 0.1
	# Asphalt (the kit's deck-top winding).
	var l0 := lat(fa, -half, 0.0)
	var r0 := lat(fa, half, 0.0)
	var l1 := lat(fb, -half, 0.0)
	var r1 := lat(fb, half, 0.0)
	for v: Vector3 in [l0, r1, r0, l0, l1, r1]:
		kit.top.add_vertex(v)
	# Box girder: fascia, cantilever soffit, web, bottom slab.
	var g := FreewayStack.GIRDER
	var conc := FreewayKit.kind_color(FreewayKit.CONCRETE, FreewayKit.S_FASCIA)
	var soff := FreewayKit.kind_color(FreewayKit.CONCRETE * 0.92, FreewayKit.S_SOFFIT)
	for side: float in [-1.0, 1.0]:
		var gp := PackedVector2Array([Vector2(half, 0.0), Vector2(half, -0.62), Vector2(half - 1.9, -1.05),
			Vector2(half - 2.7, -g), Vector2(0.0, -g)])
		for j in gp.size():
			gp[j].x *= side
		sweep(kit, kit.body, fa, fb, gp, Vector2(half * 0.5 * side, -g * 0.5), [conc, soff, soff, soff],
			run0, run1, PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
	# Barriers; the inner (left) one is open where the connector runs edge to edge with its parent.
	var col := FreewayKit.kind_color(FreewayKit.CONCRETE, FreewayKit.S_BARRIER)
	var h := FreewayKit.BARRIER_H
	for side: float in [-1.0, 1.0]:
		if side < 0.0 and touching:
			continue
		var toe := half - FreewayKit.BARRIER_BASE
		var bp := PackedVector2Array([Vector2(toe, 0.0), Vector2(toe, 0.075), Vector2(half - 0.24, 0.33),
			Vector2(half - 0.17, h), Vector2(half, h), Vector2(half, 0.0)])
		for j in bp.size():
			bp[j].x *= side
		sweep(kit, kit.body, fa, fb, bp, Vector2((half - 0.15) * side, 0.4), [col, col, col, col, col],
			run0, run1, PackedFloat32Array([1.0, 1.0, 1.0, 0.0, 0.0]))
	# Paint: yellow left edge, the lane line (dots and markers at FULL), white right edge.
	var d: Vector2 = fa[3]
	var face := -d
	var left := FreewayStack.LANE_LEFT
	if not touching:
		_strip(kit, fa, fb, left, 0.12, run0, run1, FreewayKit.kind_color(FreewayKit.YELLOW, FreewayKit.P_LINE), face, 0.035)
		if kit.full:
			_strip(kit, fa, fb, left + 0.18, 0.12, run0, run1, FreewayKit.kind_color(FreewayKit.YELLOW, FreewayKit.P_RPM), face, 0.04)
	var mid := left + FreewayStack.LANE_W
	_strip(kit, fa, fb, mid, 0.14, run0, run1, FreewayKit.kind_color(FreewayKit.WHITE, FreewayKit.P_DASH), face, 0.035)
	if kit.full:
		_strip(kit, fa, fb, mid, 0.12, run0, run1, FreewayKit.kind_color(FreewayKit.WHITE, FreewayKit.P_RPM), face, 0.04)
	_strip(kit, fa, fb, left + FreewayStack.LANE_W * 2.0, 0.15, run0, run1, FreewayKit.kind_color(FreewayKit.WHITE, FreewayKit.P_LINE), face, 0.035)
	# A davit light on the outside barrier, its arm over the lanes, its pool on the deck.
	if i % LIGHT_EVERY == 2:
		var foot := lat(fa, half - 0.2, h)
		var p2 := Vector2(foot.x, foot.z)
		if not stack.deck_over(p2, float((fa[0] as Vector3).y), FreewayKit.LIGHT_HEIGHT + 2.0, FreewayStack.LINK_BASE + k):
			_davit(kit, fa, half, foot)
	# Collision: a banked box.
	var a3: Vector3 = fa[0]
	var b3: Vector3 = fb[0]
	var seg_len := a3.distance_to(b3)
	if seg_len > 0.2:
		var fwd := (b3 - a3).normalized()
		var rr: Vector2 = fa[1]
		var right := Vector3(rr.x, (float(fa[2]) + float(fb[2])) * 0.5, rr.y).normalized()
		var up := right.cross(fwd).normalized()
		right = fwd.cross(up).normalized()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(FreewayStack.LINK_WIDTH, 1.0, seg_len + 0.3)
		cs.shape = bx
		cs.transform = Transform3D(Basis(right, up, -fwd), (a3 + b3) * 0.5 - up * 0.5)
		body.add_child(cs)


## A flat strip on the banked deck at `u` across, `w` wide (FreewayKit.strip()'s UVs).
static func _strip(kit: FreewayKit, fa: Array, fb: Array, u: float, w: float, run0: float, run1: float, col: Color, face: Vector2, lift: float) -> void:
	kit.quad(kit.paint, lat(fa, u - w * 0.5, lift), lat(fa, u + w * 0.5, lift), lat(fb, u + w * 0.5, lift), lat(fb, u - w * 0.5, lift),
		Vector3.UP, col, Vector2(0.0, run0), Vector2(1.0, run0), Vector2(1.0, run1), Vector2(0.0, run1), face)
	kit._paint_any = true


## A davit: tapered pole on the barrier, a curved arm over the lanes, a cobra head with its
## glowing drop lens, and its pool on the deck. Sodium amber, like both main lines.
static func _davit(kit: FreewayKit, f: Array, half: float, foot: Vector3) -> void:
	var r: Vector2 = f[1]
	var d: Vector2 = f[3]
	var n3 := Vector3(r.x, 0.0, r.y)
	var d3 := Vector3(d.x, 0.0, d.y)
	var pole := FreewayKit.kind_color(FreewayKit.POLE_GREY, FreewayKit.S_STEEL)
	var deck_y := float((f[0] as Vector3).y)
	var top := Vector3(foot.x, deck_y + FreewayKit.LIGHT_HEIGHT, foot.z)
	kit.prism(kit.body, foot, top, 0.17 if kit.full else 0.2, 0.09, 6 if kit.full else 4, pole)
	if kit.full:
		kit.box(kit.body, foot + Vector3(0.0, 0.12, 0.0), d3 * 0.26, Vector3(0.0, 0.12, 0.0), n3 * 0.26, pole)
	var bend := top - n3 * 0.9 + Vector3(0.0, 0.35, 0.0)
	var tip := top - n3 * 3.2 + Vector3(0.0, 0.5, 0.0)
	kit.prism(kit.body, top - Vector3(0.0, 0.2, 0.0), bend, 0.08, 0.07, 4, pole, false)
	kit.prism(kit.body, bend, tip, 0.07, 0.06, 4, pole, false)
	var lamp := Color(1.0, 0.66, 0.30)
	var hc := tip - n3 * 0.35 - Vector3(0.0, 0.08, 0.0)
	kit.box(kit.body, hc, n3 * 0.42, Vector3(0.0, 0.09, 0.0), d3 * 0.17, FreewayKit.kind_color(Color(0.50, 0.51, 0.52), FreewayKit.S_PAINTED))
	kit.box(kit.body, hc - Vector3(0.0, 0.13, 0.0), n3 * 0.32, Vector3(0.0, 0.045, 0.0), d3 * 0.13, FreewayKit.kind_color(lamp, FreewayKit.S_LENS), 1.0, false)
	kit.pool(lat(f, -0.6, 0.08), d3, Vector2(34.0, 13.0), Color(lamp.r, lamp.g, lamp.b, FreewayKit.POOL_SODIUM))


## A single column: plinth, round shaft (slightly tapered), a hammerhead cap under the girder,
## a lamp under the cap and its pool on the street.
static func _column(kit: FreewayKit, c: Dictionary, body: StaticBody3D, full: bool) -> void:
	var pos: Vector2 = c.pos
	var dir: Vector2 = c.dir
	var r: float = c.r
	var base: float = float(c.base) - 0.6
	var top: float = c.top
	var main := int(c.link) < 0
	var cap_h := 3.0 if main else 2.3
	var cap_bottom := top - cap_h
	if cap_bottom - base < 2.0:
		return
	var col := FreewayKit.kind_color(Color(0.67, 0.66, 0.63), FreewayKit.S_PILLAR)
	var p0 := Vector3(pos.x, base, pos.y)
	var p1 := Vector3(pos.x, cap_bottom + 0.3, pos.y)
	kit.prism(kit.body, p0, p1, r * 1.06, r, 16 if full else 8, col, false)
	var d3 := Vector3(dir.x, 0.0, dir.y)
	var n3 := Vector3(-dir.y, 0.0, dir.x)
	kit.box(kit.body, p0 + Vector3(0.0, 0.85, 0.0), d3 * (r + 0.35), Vector3(0.0, 0.25, 0.0), n3 * (r + 0.35), col)
	# Hammerhead: a trapezoid across the deck, its top following the bank.
	var ch: float = c.cap_half
	var e: float = c.bank
	var depth := (MAIN_CAP_DEPTH if main else CAP_DEPTH) * 0.5
	var prof := PackedVector2Array([Vector2(-ch, cap_h - ch * e), Vector2(ch, cap_h + ch * e), Vector2(ch, cap_h - 0.7 + ch * e),
		Vector2(r * 1.15, 0.0), Vector2(-r * 1.15, 0.0), Vector2(-ch, cap_h - 0.7 - ch * e)])
	var centre := Vector3(pos.x, cap_bottom, pos.y)
	var fa := [centre - d3 * depth, Vector2(n3.x, n3.z), 0.0, dir]
	var fb := [centre + d3 * depth, Vector2(n3.x, n3.z), 0.0, dir]
	var closed := prof.duplicate()
	closed.append(prof[0])
	var cols := []
	var flags := PackedFloat32Array()
	for j in closed.size() - 1:
		cols.append(col)
		flags.append(0.0)
	sweep(kit, kit.body, fa, fb, closed, Vector2(0.0, cap_h * 0.5), cols, 0.0, depth * 2.0, flags)
	var idx := Geometry2D.triangulate_polygon(prof)
	for side: float in [-1.0, 1.0]:
		var f: Array = fb if side > 0.0 else fa
		for t in range(0, idx.size(), 3):
			kit.tri(kit.body, lat(f, prof[idx[t]].x, prof[idx[t]].y), lat(f, prof[idx[t + 1]].x, prof[idx[t + 1]].y),
				lat(f, prof[idx[t + 2]].x, prof[idx[t + 2]].y), d3 * side, col)
	# Bearings under the girder.
	if full:
		for u: float in [-ch * 0.6, 0.0, ch * 0.6]:
			kit.box(kit.body, Vector3(pos.x, top - 0.08 + u * e, pos.y) + n3 * u, n3 * 0.35, Vector3(0.0, 0.07, 0.0), d3 * 0.3,
				FreewayKit.kind_color(Color(0.14, 0.14, 0.15), FreewayKit.S_RUBBER))
		# A lamp under the cap and the pool it throws on the street.
		var fx := Vector3(pos.x, cap_bottom - 0.12, pos.y) + n3 * (r + 0.6)
		kit.box(kit.body, fx, n3 * 0.25, Vector3(0.0, 0.1, 0.0), d3 * 0.2, FreewayKit.kind_color(Color(0.35, 0.36, 0.37), FreewayKit.S_PAINTED), 0.0, false)
		kit.box(kit.body, fx - Vector3(0.0, 0.13, 0.0), n3 * 0.2, Vector3(0.0, 0.03, 0.0), d3 * 0.15, FreewayKit.kind_color(Color(0.9, 0.93, 1.0), FreewayKit.S_LENS), 0.8, false)
		kit.pool(Vector3(pos.x, float(c.base) + 0.09, pos.y) + n3 * 4.0, d3, Vector2(26.0, 20.0), Color(0.9, 0.93, 1.0, 0.3))
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = cap_bottom - base
	cs.shape = cyl
	cs.position = Vector3(pos.x, (base + cap_bottom) * 0.5, pos.y)
	body.add_child(cs)
