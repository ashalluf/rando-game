class_name FootbridgeKit
extends RefCounted
## The footbridges' geometry (Footbridges plans them, FootbridgeBuild puts them in the chunks), all
## code at real size into ONE LandmarkGeo surface on shaders/footbridge.gdshader, so a whole bridge -
## span, cage, stairs or towers, lamps, its graffiti - is one draw and one shadow draw.
##
## The span: a walkway slab carried by either a steel Pratt through-truss (two trusses either side of
## the walkway, floor beams under it, top struts, end portals) or a precast box girder with solid
## parapets; on both the chain-link CAGE every Los Angeles overcrossing has - posts at each panel
## point, vertical mesh up the sides, then the hoops curving over to meet above the walkway; a
## handrail each side; lamps under the crown. Boulevard ends: a landing on two columns at the back of
## the pavement and a straight stair down along the kerb (steel stringers, solid steps with grit
## nosings, a half landing on its own column), fenced in chain-link. Freeway ends: a stair tower - a
## steel frame of four columns with girts and X bracing at every landing, the switchback flights and
## landings inside, the whole tower caged, a door gap at the bottom. Tags from the street wear atlas
## on the fascias, the landing piers and the tower's base plates.
##
## Detail levels: FULL (the near chunk: every member, step and rail), LOD (chords, posts, slabs for
## flights, the cage as panels - the shader dithers chain-link to its cover anyway). The far city is
## not this kit: FootbridgeBuild.capture() records boxes.
##
## Everything is built round the pivot `o` (the span's centre at y 0): vertices are local to it.

enum Detail { FULL, LOD }

## What a face is (shaders/footbridge.gdshader): the vertex alpha is kind / 16.
const K_PAINT := 0
const K_CONCRETE := 1
const K_GALV := 2
const K_CHAIN := 3
const K_WALK := 4
const K_LAMP := 5
const K_DARK := 6
const K_NOSING := 7
const K_TAG := 8

## The cage: the side mesh's height over the walkway, the crown's height, the hoops' spacing.
const CAGE_SIDE := 2.05
const CAGE_CROWN := 2.95
const HOOP_SEGMENTS := 6
## Truss: its height over the walkway (top chord's centre), the panel length it aims for.
const TRUSS_H := 2.55
const PANEL := 3.1
## The handrail's height and the posts' spacing on stairs and landings.
const RAIL_H := 0.92
## Stair fences (chain-link) over the treads.
const STAIR_FENCE := 2.1
## Concrete parapet (GIRDER form).
const PARAPET_H := 1.08
const PARAPET_T := 0.2
## Fascia plate along the truss's deck edge (where the tags go).
const FASCIA_H := 0.55
## Tag colours (sRGB): chrome silver, black, red, blue, lime, white, magenta.
const TAG_COLORS := [Color(0.82, 0.84, 0.86), Color(0.05, 0.05, 0.06), Color(0.78, 0.12, 0.10),
	Color(0.15, 0.32, 0.78), Color(0.55, 0.85, 0.20), Color(0.95, 0.95, 0.93), Color(0.82, 0.18, 0.62)]
## Tags on one bridge, at most.
const MAX_TAGS := 7

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/footbridge.gdshader")
		_material.set_shader_parameter("tag_atlas", load("res://assets/textures/street_wear/street_wear_tags.png"))
	return _material


static func kc(c: Color, kind: int) -> Color:
	return Color(c.r, c.g, c.b, float(kind) / 16.0)


## Builds bridge `b` into a new LandmarkGeo (vertices round `o`), and the collision boxes (local to
## `o` as well): [[Vector3 centre, Vector3 size, Basis], ...] in `boxes` when it is given.
static func build(b: Dictionary, o: Vector3, detail: int, boxes: Array = []) -> LandmarkGeo:
	var g := LandmarkGeo.new()
	g.use("fb", material())
	var k := _Ctx.new()
	k.g = g
	k.o = o
	k.full = detail == Detail.FULL
	k.boxes = boxes
	k.b = b
	k.rng = RandomNumberGenerator.new()
	k.rng.seed = int(b.seed)
	_span(k)
	for e: Dictionary in b.ends:
		if (e.tower as Dictionary).is_empty():
			_boulevard_end(k, e)
		else:
			_tower(k, e)
	if k.full:
		_lamps(k)
		_tags(k)
	return g


class _Ctx:
	var g: LandmarkGeo
	var o: Vector3
	var full: bool
	var boxes: Array
	var b: Dictionary
	var rng: RandomNumberGenerator
	var tag_spots: Array = []


# --- Primitives ------------------------------------------------------------------------------

## A box of `size` (x across the span's `dir`, y up, z along `axis`... see basis) at world point `c`.
static func _box(k: _Ctx, c: Vector3, size: Vector3, basis: Basis, col: Color, kind: int, collide := false) -> void:
	k.g.box("fb", c - k.o, size, kc(col, kind), basis)
	if collide:
		k.boxes.append([c - k.o, size, basis])


## A member from world `a` to `b`, `w` wide and `h` deep (h measured toward `up`).
static func _beam(k: _Ctx, a: Vector3, b: Vector3, w: float, h: float, col: Color, kind: int, up := Vector3.UP) -> void:
	var z := b - a
	var length := z.length()
	if length < 0.01:
		return
	z /= length
	var x := up.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	k.g.box("fb", (a + b) * 0.5 - k.o, Vector3(w, h, length), kc(col, kind), Basis(x, y, z))


## A round tube from world `a` to `b`, radius r, `sides` faces round.
static func _tube(k: _Ctx, a: Vector3, b: Vector3, r: float, col: Color, kind: int, sides := 6) -> void:
	var z := b - a
	var length := z.length()
	if length < 0.01:
		return
	z /= length
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-4:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x)
	var c := kc(col, kind)
	for s in sides:
		var t0 := TAU * float(s) / float(sides)
		var t1 := TAU * float(s + 1) / float(sides)
		var n0 := x * cos(t0) + y * sin(t0)
		var n1 := x * cos(t1) + y * sin(t1)
		var p0 := a + n0 * r - k.o
		var p1 := a + n1 * r - k.o
		k.g.quad_n("fb", p0, p1, p1 + z * length, p0 + z * length, n0, n1, n1, n0,
			Vector2(0, 0), Vector2(0.1, 0), Vector2(0.1, length), Vector2(0, length), c)


## A chain-link quad a-b-c-d (world), UV in metres: u along a->b, v along a->d.
static func _mesh(k: _Ctx, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var n := (b - a).cross(d - a)
	var u1 := a.distance_to(b)
	var v1 := a.distance_to(d)
	k.g.quad("fb", a - k.o, b - k.o, c - k.o, d - k.o, n, Vector2(0, 0), Vector2(u1, 0), Vector2(u1, v1), Vector2(0, v1), kc(col, K_CHAIN))


## A flat quad (world corners) of one kind, facing `want`, UV metres.
static func _quad(k: _Ctx, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, col: Color, kind: int) -> void:
	var u1 := a.distance_to(b)
	var v1 := a.distance_to(d)
	k.g.quad("fb", a - k.o, b - k.o, c - k.o, d - k.o, want, Vector2(0, a.y), Vector2(u1, b.y), Vector2(u1, c.y), Vector2(0, d.y), kc(col, kind))


static func v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


# --- The span --------------------------------------------------------------------------------

static func _wire_color(b: Dictionary) -> Color:
	# Vinyl-coated black on a quarter of them, else galvanised.
	return Color(0.12, 0.13, 0.12) if Footbridges.h01([b.seed, "vinyl"]) < 0.25 else Color(0.62, 0.63, 0.64)


static func _span(k: _Ctx) -> void:
	var b := k.b
	var c: Vector2 = b.c
	var dir: Vector2 = b.dir
	var along: Vector2 = b.along
	var half: float = b.half
	var y: float = b.y
	var paint: Color = b.paint
	var truss := int(b.form) == Footbridges.Form.TRUSS
	var depth: float = Footbridges.DEPTH[int(b.form)]
	var wire := _wire_color(b)
	var bw := Footbridges.BRIDGE_W
	var ww := Footbridges.WALK_W
	var basis := Basis(v3(along, 0.0), Vector3.UP, v3(dir, 0.0))
	var span_len := half * 2.0
	var ctr := v3(c, 0.0)
	# The walkway slab (its top at y) and, for the girder, the box under it.
	_box(k, ctr + Vector3(0.0, y - 0.11, 0.0), Vector3(ww + 0.3, 0.22, span_len), basis, Color(1, 1, 1), K_WALK, true)
	if truss:
		# Floor beams at every panel point, bottom chords, the trusses, top struts, end portals.
		var panels := maxi(int(round(span_len / PANEL)), 4)
		if panels % 2 == 1:
			panels += 1
		var pl := span_len / float(panels)
		var yb := y - depth + 0.16
		var yt := y + TRUSS_H
		for side: float in [-1.0, 1.0]:
			var off := along * side * (bw * 0.5 - 0.14)
			var a0 := v3(c + off - dir * half, yb)
			var a1 := v3(c + off + dir * half, yb)
			_beam(k, a0, a1, 0.24, 0.3, paint, K_PAINT)
			_beam(k, a0 + Vector3(0, yt - yb, 0), a1 + Vector3(0, yt - yb, 0), 0.26, 0.26, paint, K_PAINT)
			# The fascia plate on the deck edge outside the bottom chord.
			var fo := along * side * (bw * 0.5 + 0.0)
			_quad(k, v3(c + fo - dir * half, y - depth), v3(c + fo + dir * half, y - depth),
				v3(c + fo + dir * half, y - depth + FASCIA_H), v3(c + fo - dir * half, y - depth + FASCIA_H),
				v3(along * side, 0.0), paint * 0.92, K_PAINT)
			k.tag_spots.append({"a": c + fo * 1.01 - dir * half, "b": c + fo * 1.01 + dir * half, "y0": y - depth + 0.02, "h": FASCIA_H - 0.04, "out": along * side})
			for p in panels + 1:
				var t := -half + pl * float(p)
				var pb := v3(c + off + dir * t, yb)
				var pt := v3(c + off + dir * t, yt)
				var end := p == 0 or p == panels
				if k.full or p % 2 == 0 or end:
					_beam(k, pb, pt, 0.2 if not end else 0.3, 0.18 if not end else 0.3, paint, K_PAINT, v3(dir, 0.0))
				# Pratt diagonals: from the top at the panel point toward the middle's bottom.
				if p < panels and (k.full or p == 0 or p == panels - 1):
					var mid := p < panels / 2
					var q0 := v3(c + off + dir * t, yt if mid else yb)
					var q1 := v3(c + off + dir * (t + pl), yb if mid else yt)
					_beam(k, q0, q1, 0.14, 0.14, paint, K_PAINT, v3(dir, 0.0))
		for p in panels + 1:
			var t := -half + pl * float(p)
			var l := v3(c - along * (bw * 0.5 - 0.14) + dir * t, 0.0)
			var r := v3(c + along * (bw * 0.5 - 0.14) + dir * t, 0.0)
			_beam(k, l + Vector3(0, yb + 0.05, 0), r + Vector3(0, yb + 0.05, 0), 0.22, 0.32, paint * 0.9, K_PAINT, v3(dir, 0.0))
			if k.full and p % 2 == 0:
				_beam(k, l + Vector3(0, yt, 0), r + Vector3(0, yt, 0), 0.14, 0.14, paint, K_PAINT, v3(dir, 0.0))
		# The truss's sides take the cage's side mesh; the hoops go over from the top chords.
		_cage(k, c, dir, along, half, y, bw * 0.5 - 0.2, wire, 0.0)
		k.boxes.append([v3(c, y + 1.4) - k.o + v3(along, 0.0) * (bw * 0.5 - 0.1), Vector3(0.2, 2.8, span_len), basis])
		k.boxes.append([v3(c, y + 1.4) - k.o - v3(along, 0.0) * (bw * 0.5 - 0.1), Vector3(0.2, 2.8, span_len), basis])
	else:
		# The box girder: webs leaning in, a soffit, the slab's edges; parapets on top.
		var top := y - 0.22
		var bot := y - depth
		for side: float in [-1.0, 1.0]:
			var e := along * side
			var t0 := v3(c + e * (bw * 0.5) - dir * half, top)
			var t1 := v3(c + e * (bw * 0.5) + dir * half, top)
			var m0 := v3(c + e * (bw * 0.5) - dir * half, top - 0.28)
			var m1 := v3(c + e * (bw * 0.5) + dir * half, top - 0.28)
			var w0 := v3(c + e * (bw * 0.5 - 0.55) - dir * half, bot)
			var w1 := v3(c + e * (bw * 0.5 - 0.55) + dir * half, bot)
			_quad(k, t0, t1, m1, m0, v3(e, 0.0), Color(1, 1, 1), K_CONCRETE)
			_quad(k, m0, m1, w1, w0, v3(e, -0.5), Color(0.96, 0.96, 0.96), K_CONCRETE)
			k.tag_spots.append({"a": c + e * (bw * 0.5 + 0.01) - dir * half, "b": c + e * (bw * 0.5 + 0.01) + dir * half, "y0": top - 0.27, "h": 0.26, "out": e})
			# The parapet.
			var pc := v3(c + e * (bw * 0.5 - PARAPET_T * 0.5), y + PARAPET_H * 0.5 - 0.11)
			_box(k, pc, Vector3(PARAPET_T, PARAPET_H + 0.22, span_len), basis, Color(0.98, 0.97, 0.95), K_CONCRETE, true)
			k.tag_spots.append({"a": c + e * (bw * 0.5 + 0.01) - dir * half, "b": c + e * (bw * 0.5 + 0.01) + dir * half, "y0": y - 0.18, "h": PARAPET_H + 0.15, "out": e})
		_quad(k, v3(c - along * (bw * 0.5 - 0.55) - dir * half, bot), v3(c + along * (bw * 0.5 - 0.55) - dir * half, bot),
			v3(c + along * (bw * 0.5 - 0.55) + dir * half, bot), v3(c - along * (bw * 0.5 - 0.55) + dir * half, bot), Vector3.DOWN, Color(0.9, 0.9, 0.9), K_CONCRETE)
		for side: float in [-1.0, 1.0]:
			var e2 := v3(dir * side * half, 0.0)
			# The girder's end faces.
			_quad(k, v3(c - along * (bw * 0.5), top) + e2, v3(c + along * (bw * 0.5), top) + e2,
				v3(c + along * (bw * 0.5 - 0.55), bot) + e2, v3(c - along * (bw * 0.5 - 0.55), bot) + e2, v3(dir * side, 0.0), Color(0.95, 0.95, 0.95), K_CONCRETE)
		k.boxes.append([v3(c, y - depth * 0.5) - k.o, Vector3(bw, depth, span_len), basis])
		_cage(k, c, dir, along, half, y + PARAPET_H, bw * 0.5 - PARAPET_T * 0.5, wire, 0.0)
		k.boxes.append([v3(c, y + 1.6) - k.o + v3(along, 0.0) * (bw * 0.5 - 0.1), Vector3(0.2, 3.2, span_len), basis])
		k.boxes.append([v3(c, y + 1.6) - k.o - v3(along, 0.0) * (bw * 0.5 - 0.1), Vector3(0.2, 3.2, span_len), basis])
	# The cage's crown, so the hero who lands on it stands on it.
	k.boxes.append([v3(c, y + CAGE_CROWN + 0.05) - k.o, Vector3(ww, 0.1, span_len), basis])
	# Handrails each side of the walkway.
	if k.full:
		for side: float in [-1.0, 1.0]:
			var off := along * side * (ww * 0.5 - 0.06)
			_tube(k, v3(c + off - dir * half, y + RAIL_H), v3(c + off + dir * half, y + RAIL_H), 0.024, Color(), K_GALV)
			var n := int(span_len / 2.4)
			for p in n + 1:
				var t := -half + span_len * float(p) / float(maxi(n, 1))
				var base := v3(c + off * 1.03 + dir * t, y)
				_tube(k, base, base + Vector3(0, RAIL_H, 0), 0.02, Color(), K_GALV, 5)


## The cage over a span (or a landing): posts every panel from `y0` up `side_h` (0 = they start at
## the cage's own side height over the walkway), the side mesh, then the hoops arching over. `w` is
## the half width at the posts.
static func _cage(k: _Ctx, c: Vector2, dir: Vector2, along: Vector2, half: float, y0: float, w: float, wire: Color, side_from: float) -> void:
	var y := float(k.b.y)
	var span_len := half * 2.0
	var hoops := maxi(int(round(span_len / 2.6)), 2)
	var top_side := y + CAGE_SIDE
	var crown := y + CAGE_CROWN
	# The arch: from (±w, top_side) to (0, crown), as an ellipse quarter.
	var prof: Array[Vector2] = []
	for s in HOOP_SEGMENTS + 1:
		var a := PI * 0.5 * float(s) / float(HOOP_SEGMENTS)
		prof.append(Vector2(w * cos(a), top_side + (crown - top_side) * sin(a)))
	for h in hoops + 1:
		var t := -half + span_len * float(h) / float(hoops)
		var p := c + dir * t
		if k.full or h % 2 == 0 or h == hoops:
			for side: float in [-1.0, 1.0]:
				var foot := v3(p + along * side * w, y0)
				var knee := v3(p + along * side * w, top_side)
				_tube(k, foot, knee, 0.038, Color(), K_GALV, 6 if k.full else 4)
				for s in HOOP_SEGMENTS:
					var q0 := v3(p + along * side * prof[s].x, prof[s].y)
					var q1 := v3(p + along * side * prof[s + 1].x, prof[s + 1].y)
					_tube(k, q0, q1, 0.03, Color(), K_GALV, 5 if k.full else 4)
	# The mesh: sides, then the arch's strips, one quad per strip for the whole span.
	for side: float in [-1.0, 1.0]:
		var e := along * side * w
		var from_y := y0 if side_from <= 0.0 else y + side_from
		from_y = minf(from_y, top_side - 0.1)
		_mesh(k, v3(c + e - dir * half, from_y), v3(c + e + dir * half, from_y), v3(c + e + dir * half, top_side), v3(c + e - dir * half, top_side), wire)
		for s in HOOP_SEGMENTS:
			var e0 := along * side * prof[s].x
			var e1 := along * side * prof[s + 1].x
			_mesh(k, v3(c + e0 - dir * half, prof[s].y), v3(c + e0 + dir * half, prof[s].y),
				v3(c + e1 + dir * half, prof[s + 1].y), v3(c + e1 - dir * half, prof[s + 1].y), wire)
	# Stringers along the top of the sides and the crown.
	for side: float in [-1.0, 1.0]:
		var e := along * side * w
		_tube(k, v3(c + e - dir * half, top_side), v3(c + e + dir * half, top_side), 0.03, Color(), K_GALV, 5)
	_tube(k, v3(c - dir * half, crown), v3(c + dir * half, crown), 0.03, Color(), K_GALV, 5)


static func _lamps(k: _Ctx) -> void:
	var b := k.b
	var c: Vector2 = b.c
	var dir: Vector2 = b.dir
	var along: Vector2 = b.along
	var half: float = b.half
	var y: float = b.y
	var n := maxi(int((half * 2.0) / 9.0), 2)
	var basis := Basis(v3(along, 0.0), Vector3.UP, v3(dir, 0.0))
	for i in n:
		var t := -half + (half * 2.0) * (float(i) + 0.5) / float(n)
		var p := v3(c + dir * t, y + CAGE_CROWN - 0.12)
		_box(k, p, Vector3(0.3, 0.12, 0.5), basis, Color(0.2, 0.21, 0.22), K_PAINT)
		_box(k, p - Vector3(0, 0.07, 0), Vector3(0.26, 0.02, 0.46), basis, Color(), K_LAMP)


# --- Boulevard ends: a landing and a straight stair --------------------------------------------

static func _boulevard_end(k: _Ctx, e: Dictionary) -> void:
	var b := k.b
	var dir: Vector2 = b.dir
	var along: Vector2 = b.along
	var y: float = b.y
	var side: float = e.side
	var paint: Color = b.paint
	var wire := _wire_color(b)
	var ld: Dictionary = e.landing
	var lc: Vector2 = ld.c
	var basis := Basis(v3(along, 0.0), Vector3.UP, v3(dir, 0.0))
	var g: float = e.ground
	var truss := int(b.form) == Footbridges.Form.TRUSS
	var ldd: float = ld.d
	var ldw: float = ld.w
	# The landing slab and its two columns (steel for a truss, concrete for a girder bridge).
	_box(k, v3(lc, y - 0.2), Vector3(ldw, 0.4, ldd), basis, Color(1, 1, 1), K_WALK, true)
	for s: float in [-1.0, 1.0]:
		var cp := lc + along * s * (ldw * 0.5 - 0.35) + dir * side * 0.2
		var cg := g
		if truss:
			_box(k, v3(cp, (cg + y - 0.4) * 0.5), Vector3(0.36, y - 0.4 - cg, 0.36), basis, paint, K_PAINT, true)
			_box(k, v3(cp, cg + 0.05), Vector3(0.6, 0.1, 0.6), basis, Color(0.6, 0.6, 0.6), K_CONCRETE)
		else:
			_box(k, v3(cp, (cg + y - 0.4) * 0.5), Vector3(0.55, y - 0.4 - cg, 0.55), basis, Color(0.97, 0.96, 0.93), K_CONCRETE, true)
		k.tag_spots.append({"a": cp + dir * side * 0.29 - along * 0.2, "b": cp + dir * side * 0.29 + along * 0.2, "y0": cg + 0.4, "h": 0.4, "out": dir * side, "small": true})
	# The cage round the landing's open sides: the far side (toward the buildings) and the side away
	# from the stair, both to the cage's side height, the span's cage meeting it.
	var stair: Dictionary = e.stair
	var down: Vector2 = (stair.flights[0] as Dictionary).down
	var far := lc + dir * side * (ldd * 0.5 - 0.05)
	var back := lc - down * (ldw * 0.5 - 0.05)
	_fence(k, far - along * (ldw * 0.5), far + along * (ldw * 0.5), y, CAGE_SIDE, wire, true)
	_fence(k, back - dir * (ldd * 0.5), back + dir * (ldd * 0.5), y, CAGE_SIDE, wire, true)
	# The stair, its half landing (on a column) and its fences.
	for f: Dictionary in stair.flights:
		_flight(k, f, paint, wire)
	for l: Dictionary in stair.landings:
		var lp: Vector3 = l.c
		var ls: Vector2 = l.size
		var dn: Vector2 = l.down
		var lb := Basis(v3(Vector2(-dn.y, dn.x), 0.0), Vector3.UP, v3(dn, 0.0))
		_box(k, lp - Vector3(0, 0.15, 0), Vector3(ls.y, 0.3, ls.x), lb, Color(1, 1, 1), K_WALK, true)
		var col_at := Vector2(lp.x, lp.z)
		_box(k, v3(col_at, (g + lp.y - 0.3) * 0.5), Vector3(0.3, lp.y - 0.3 - g, 0.3), lb, paint if truss else Color(0.97, 0.96, 0.93), K_PAINT if truss else K_CONCRETE)
		for s: float in [-1.0, 1.0]:
			var ed := col_at + Vector2(-dn.y, dn.x) * s * (ls.y * 0.5)
			_fence(k, ed - dn * ls.x * 0.5, ed + dn * ls.x * 0.5, lp.y, STAIR_FENCE, wire, k.full)


## A chain-link fence from world XZ `a` to `b`, standing on `y`, `h` tall, posts at its ends and
## every 2.5 m, a top rail.
static func _fence(k: _Ctx, a: Vector2, b: Vector2, y: float, h: float, wire: Color, posts: bool) -> void:
	_mesh(k, v3(a, y), v3(b, y), v3(b, y + h), v3(a, y + h), wire)
	if posts:
		var n := maxi(int(a.distance_to(b) / 2.5), 1)
		for i in n + 1:
			var p := a.lerp(b, float(i) / float(n))
			_tube(k, v3(p, y), v3(p, y + h), 0.03, Color(), K_GALV, 5)
	_tube(k, v3(a, y + h), v3(b, y + h), 0.025, Color(), K_GALV, 5)


## One flight: solid steps (risers, treads, both sides as the sawtooth, the soffit), grit nosings,
## steel stringers either side with the handrail over them and the chain-link fence on them.
static func _flight(k: _Ctx, f: Dictionary, paint: Color, wire: Color) -> void:
	var top: Vector3 = f.top
	var down: Vector2 = f.down
	var n: int = f.n
	var tread: float = f.tread
	var w: float = f.w
	var rise: float = f.rise
	var across := Vector2(-down.y, down.x)
	var d3 := v3(down, 0.0)
	var a3 := v3(across, 0.0)
	var t0 := Vector2(top.x, top.z)
	var run := float(n - 1) * tread
	var y_bot := top.y - rise * float(n)
	var white := Color(1, 1, 1)
	if k.full:
		# The sawtooth: risers and treads across the flight.
		for i in n:
			var yi := top.y - rise * float(i)
			var x0 := float(i) * tread
			var p0 := t0 + down * x0
			# Riser i: from yi down to yi - rise at x0.
			_quad(k, v3(p0 - across * w * 0.5, yi), v3(p0 + across * w * 0.5, yi), v3(p0 + across * w * 0.5, yi - rise), v3(p0 - across * w * 0.5, yi - rise), d3, white, K_CONCRETE)
			if i < n - 1:
				var p1 := p0 + down * tread
				var yt := yi - rise
				_quad(k, v3(p0 - across * w * 0.5, yt), v3(p0 + across * w * 0.5, yt), v3(p1 + across * w * 0.5, yt), v3(p1 - across * w * 0.5, yt), Vector3.UP, white, K_WALK)
				# The nosing strip at the tread's front edge.
				var pn := p0 + down * 0.06
				_quad(k, v3(p0 - across * w * 0.46, yt + 0.004), v3(p0 + across * w * 0.46, yt + 0.004), v3(pn + across * w * 0.46, yt + 0.004), v3(pn - across * w * 0.46, yt + 0.004), Vector3.UP, white, K_NOSING)
		# The sides: one polygon each, the sawtooth over the soffit.
		for s: float in [-1.0, 1.0]:
			var poly := PackedVector2Array()
			poly.append(Vector2(0.0, top.y))
			for i in n:
				var yi := top.y - rise * float(i + 1)
				poly.append(Vector2(float(i) * tread, yi))
				if i < n - 1:
					poly.append(Vector2(float(i + 1) * tread, yi))
			poly.append(Vector2(run, y_bot - 0.25))
			poly.append(Vector2(0.0, top.y - 0.3))
			var idx := Geometry2D.triangulate_polygon(poly)
			var off := across * s * w * 0.5
			for t in range(0, idx.size(), 3):
				var pts: Array[Vector3] = []
				for q in 3:
					var pp: Vector2 = poly[idx[t + q]]
					pts.append(v3(t0 + off + down * pp.x, pp.y) - k.o)
				k.g.tri("fb", pts[0], pts[1], pts[2], a3 * s, Vector2(pts[0].x, pts[0].y), Vector2(pts[1].x, pts[1].y), Vector2(pts[2].x, pts[2].y), kc(white, K_CONCRETE))
	else:
		# Far: the flight as a sloped slab.
		var a := v3(t0, top.y - rise * 0.5)
		var bb := v3(t0 + down * run, y_bot + rise * 0.5)
		_beam(k, a, bb, w, 0.4, white, K_CONCRETE)
	# The soffit.
	_quad(k, v3(t0 - across * w * 0.5, top.y - 0.3), v3(t0 + across * w * 0.5, top.y - 0.3),
		v3(t0 + down * run + across * w * 0.5, y_bot - 0.25), v3(t0 + down * run - across * w * 0.5, y_bot - 0.25), Vector3.DOWN, white, K_CONCRETE)
	# Collision: one ramp along the nosings.
	var mid := v3(t0 + down * run * 0.5, (top.y + y_bot + rise) * 0.5 - 0.15)
	var slope := Vector3(d3.x * run, (y_bot + rise) - top.y, d3.z * run)
	var zz := slope.normalized()
	var xx := a3
	var yy := zz.cross(xx).normalized()
	if yy.y < 0.0:
		yy = -yy
		xx = -xx
	k.boxes.append([mid - k.o, Vector3(w, 0.3, slope.length() + 0.4), Basis(xx, yy, zz)])
	# Stringers, the handrail and the fence on both sides.
	for s: float in [-1.0, 1.0]:
		var off := across * s * (w * 0.5 + 0.08)
		var sa := v3(t0 + off, top.y - 0.1)
		var sb := v3(t0 + off + down * run, y_bot)
		_beam(k, sa - Vector3(0, 0.15, 0), sb - Vector3(0, 0.15, 0), 0.12, 0.38, paint, K_PAINT, Vector3.UP)
		if k.full:
			_tube(k, sa + Vector3(0, RAIL_H, 0), sb + Vector3(0, RAIL_H + rise, 0), 0.024, Color(), K_GALV)
			var np := maxi(int(run / 1.4), 1)
			for i in np + 1:
				var q := sa.lerp(sb + Vector3(0, rise, 0), float(i) / float(np))
				_tube(k, q, q + Vector3(0, RAIL_H, 0), 0.02, Color(), K_GALV, 5)
		var wire_c := _wire_color(k.b)
		var fa := v3(t0 + off * 1.02, top.y)
		var fb := v3(t0 + off * 1.02 + down * run, y_bot + rise)
		_mesh(k, fa, fb, fb + Vector3(0, STAIR_FENCE, 0), fa + Vector3(0, STAIR_FENCE, 0), wire_c)
		_tube(k, fa + Vector3(0, STAIR_FENCE, 0), fb + Vector3(0, STAIR_FENCE, 0), 0.025, Color(), K_GALV, 5)
		k.boxes.append([(fa + fb) * 0.5 + Vector3(0, STAIR_FENCE * 0.5, 0) - k.o, Vector3(0.1, STAIR_FENCE, (fb - fa).length()), _upright_basis(fb - fa)])


## A basis whose z runs along `v` flattened... kept upright (y world up), for fence collision.
static func _upright_basis(v: Vector3) -> Basis:
	var z := Vector3(v.x, 0.0, v.z).normalized()
	if z.length_squared() < 0.5:
		z = Vector3.FORWARD
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x, Vector3.UP, z)


# --- Freeway ends: a stair tower ---------------------------------------------------------------

static func _tower(k: _Ctx, e: Dictionary) -> void:
	var b := k.b
	var tw: Dictionary = e.tower
	var tc: Vector2 = tw.c
	var out: Vector2 = tw.out
	var al: Vector2 = tw.along
	var tlen: float = tw.len
	var td: float = tw.d
	var y: float = tw.top
	var g: float = tw.g
	var paint: Color = b.paint
	var wire := _wire_color(b)
	var hw := td * 0.5 + Footbridges.TOWER_SKIN
	var hl := tlen * 0.5 + Footbridges.TOWER_SKIN
	var basis := Basis(v3(out, 0.0), Vector3.UP, v3(al, 0.0))
	var top := y + CAGE_SIDE + 0.3
	# A concrete pad under it.
	_box(k, v3(tc, g - 0.1), Vector3(hw * 2.0 + 0.6, 0.3, hl * 2.0 + 0.6), basis, Color(0.95, 0.95, 0.93), K_CONCRETE, true)
	# The four corner columns and a mid column on the long sides.
	var corners: Array[Vector2] = []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 0.0, 1.0]:
			corners.append(tc + out * sx * hw + al * sz * hl)
	for p: Vector2 in corners:
		_box(k, v3(p, (g + top) * 0.5), Vector3(0.26, top - g, 0.26), basis, paint, K_PAINT)
		if k.full:
			_box(k, v3(p, g + 0.06), Vector3(0.5, 0.12, 0.5), basis, Color(0.35, 0.35, 0.36), K_GALV)
	# The girts at every landing level and at the top, and X bracing on the long faces.
	var stair: Dictionary = e.stair
	var levels: Array[float] = [g + 0.4]
	for l: Dictionary in stair.landings:
		levels.append((l.c as Vector3).y - 0.3)
	levels.append(top)
	levels.sort()
	for li in levels.size():
		var ly := levels[li]
		var ring: Array[Vector2] = [tc - out * hw - al * hl, tc + out * hw - al * hl, tc + out * hw + al * hl, tc - out * hw + al * hl]
		for i in 4:
			_beam(k, v3(ring[i], ly), v3(ring[(i + 1) % 4], ly), 0.16, 0.2, paint, K_PAINT)
		if li > 0 and (k.full or li % 2 == 0):
			var y0 := levels[li - 1]
			for sx: float in [-1.0, 1.0]:
				var a0 := tc + out * sx * (hw + 0.02) - al * hl
				var a1 := tc + out * sx * (hw + 0.02) + al * hl
				_beam(k, v3(a0, y0), v3(a1, ly), 0.08, 0.08, paint, K_PAINT, v3(out, 0.0))
				_beam(k, v3(a1, y0), v3(a0, ly), 0.08, 0.08, paint, K_PAINT, v3(out, 0.0))
	# The flights and landings inside. The top landing is a full slab; the span arrives on it.
	for f: Dictionary in stair.flights:
		_flight(k, f, paint, wire)
	for l: Dictionary in stair.landings:
		var lp: Vector3 = l.c
		var ls: Vector2 = l.size
		_box(k, lp - Vector3(0, 0.15, 0), Vector3(ls.y + 0.1, 0.3, ls.x), basis, Color(1, 1, 1), K_WALK, true)
	# The cage on all four faces, a door gap at the bottom of the last flight's end, and a roof.
	var foot: Vector2 = stair.foot
	var door_end := 1.0 if (foot - tc).dot(al) > 0.0 else -1.0
	for sx: float in [-1.0, 1.0]:
		var e0 := tc + out * sx * hw - al * hl
		var e1 := tc + out * sx * hw + al * hl
		# The face toward the deck (-out) leaves the span's opening over the top landing (the near
		# end, -al): mesh below it and beside it, collision the same.
		if sx < 0.0:
			var cut := tc - al * hl + al * (Footbridges.TOWER_TOP + Footbridges.TOWER_SKIN) + out * sx * hw
			_mesh(k, v3(cut, g + 0.1), v3(e1, g + 0.1), v3(e1, top), v3(cut, top), wire)
			_mesh(k, v3(e0, g + 0.1), v3(cut, g + 0.1), v3(cut, y - 0.3), v3(e0, y - 0.3), wire)
			k.boxes.append([v3((cut + e1) * 0.5, (g + top) * 0.5) - k.o, Vector3(0.12, top - g, cut.distance_to(e1)), basis])
			k.boxes.append([v3((e0 + cut) * 0.5, (g + y - 0.3) * 0.5) - k.o, Vector3(0.12, y - 0.3 - g, e0.distance_to(cut)), basis])
		else:
			_mesh(k, v3(e0, g + 0.1), v3(e1, g + 0.1), v3(e1, top), v3(e0, top), wire)
			k.boxes.append([v3((e0 + e1) * 0.5, (g + top) * 0.5) - k.o, Vector3(0.12, top - g, hl * 2.0), basis])
	for sz: float in [-1.0, 1.0]:
		var e0 := tc - out * hw + al * sz * hl
		var e1 := tc + out * hw + al * sz * hl
		var y_from := g + 0.1
		if sz == door_end:
			# The door: the bottom 2.3 m of the face open over the foot's lane.
			y_from = g + 2.3
			k.boxes.append([v3((e0 + e1) * 0.5, (y_from + top) * 0.5) - k.o, Vector3(hw * 2.0, top - y_from, 0.12), basis])
		else:
			k.boxes.append([v3((e0 + e1) * 0.5, (g + top) * 0.5) - k.o, Vector3(hw * 2.0, top - g, 0.12), basis])
		_mesh(k, v3(e0, y_from), v3(e1, y_from), v3(e1, top), v3(e0, top), wire)
	_box(k, v3(tc, top + 0.05), Vector3(hw * 2.0 + 0.2, 0.1, hl * 2.0 + 0.2), basis, paint * 0.85, K_PAINT, true)
	# A light in the tower's roof and the base plate where the tags go.
	if k.full:
		_box(k, v3(tc, top - 0.08), Vector3(0.3, 0.06, 0.6), basis, Color(), K_LAMP)
		var plate0 := tc + out * (hw + 0.02) - al * hl * 0.9
		var plate1 := tc + out * (hw + 0.02) + al * hl * 0.9
		_quad(k, v3(plate0, g + 0.1), v3(plate1, g + 0.1), v3(plate1, g + 1.3), v3(plate0, g + 1.3), v3(out, 0.0), paint * 0.8, K_PAINT)
		k.tag_spots.append({"a": plate0 + out * 0.01, "b": plate1 + out * 0.01, "y0": g + 0.12, "h": 1.15, "out": out})


# --- Graffiti -------------------------------------------------------------------------------

## Tags from the street wear atlas on the fascias, parapets, piers and tower plates: a hashed few,
## laid along each spot without overlapping, each cell's 2:1 aspect kept.
static func _tags(k: _Ctx) -> void:
	var n := 0
	var count := mini(int(Footbridges.h01([k.b.seed, "tags"]) * float(MAX_TAGS + 1)), MAX_TAGS)
	if k.tag_spots.is_empty():
		return
	for i in count * 3:
		if n >= count:
			break
		var spot: Dictionary = k.tag_spots[int(Footbridges.h01([k.b.seed, "tag_spot", i]) * k.tag_spots.size()) % k.tag_spots.size()]
		var a: Vector2 = spot.a
		var b: Vector2 = spot.b
		var length := a.distance_to(b)
		var h: float = spot.h
		var w := h * 2.0
		if length < w + 0.2:
			continue
		var t := Footbridges.h01([k.b.seed, "tag_at", i]) * (length - w)
		var p0 := a.lerp(b, t / length)
		var p1 := a.lerp(b, (t + w) / length)
		var y0: float = spot.y0
		var out: Vector2 = spot.out
		var cell := int(Footbridges.h01([k.b.seed, "tag_cell", i]) * 16.0) % 16
		var cu := float(cell % 4) * 0.25
		var cv := float(cell / 4) * 0.25
		var col: Color = TAG_COLORS[int(Footbridges.h01([k.b.seed, "tag_col", i]) * TAG_COLORS.size()) % TAG_COLORS.size()]
		# Seen from outside, u runs left to right: which end is left depends on the side.
		var want := v3(out, 0.0)
		var right := Vector3.UP.cross(want)
		var l0 := v3(p0, y0)
		var l1 := v3(p1, y0)
		if (l1 - l0).dot(right) > 0.0:
			var tmp := l0
			l0 = l1
			l1 = tmp
		var c := kc(col, K_TAG)
		k.g.tri("fb", l0 - k.o, l1 - k.o, l1 + Vector3(0, h, 0) - k.o, want, Vector2(cu, cv + 0.25), Vector2(cu + 0.25, cv + 0.25), Vector2(cu + 0.25, cv), c)
		k.g.tri("fb", l0 - k.o, l1 + Vector3(0, h, 0) - k.o, l0 + Vector3(0, h, 0) - k.o, want, Vector2(cu, cv + 0.25), Vector2(cu + 0.25, cv), Vector2(cu, cv), c)
		n += 1
