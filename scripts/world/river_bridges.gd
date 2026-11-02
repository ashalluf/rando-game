class_name RiverBridges
extends RefCounted
## The Los Angeles River's bridges (LaRiver.Bridge), built in code at real size into a river
## chunk's meshes (RiverBuild: the concrete material for everything cast, Industrial's walls
## material for the steel, the river lamp material for what glows). Original designs in the forms
## of the real ones, none of them named:
##   ARCH    a 1920s-30s concrete viaduct: three open-spandrel arches over the bed on cutwater
##           piers, the deck carried on spandrel columns, a moulded fascia and cornice, a turned
##           balustrade with posts, twin-lantern lamp standards, and a stepped pylon with a lantern
##           at each corner where it leaves the bank;
##   RIBBON  the new viaduct's form: white tied arches over the deck in three spans, each a pair
##           of ribs leaning outward with hangers down to the deck edges, an LED strip along every
##           rib lit at night, a steel rail with cable infill, slim LED lamp poles;
##   GIRDER  a plain concrete box-girder deck on bents of round columns, a concrete barrier with a
##           steel rail on it, cobra-head lamps;
##   RAIL    a freight track on a deck between two steel plate girders, stiffened every metre and a
##           half, on concrete piers, the track run on over the bank roads to buffer stops.
## The road on a street bridge is the chunk's own road slab (CityChunk._build_roads(): the relief
## along the corridor is the top level, so the street runs straight over); the bridge is
## everything under and beside it. A bridge is built by the chunk the road's crossing point falls
## in (LaRiver bridges() "owner"), detailed at FULL, a deck, piers and coarse ribs at LOD.

## The pavement each side of a bridge's carriageway, and the parapet's height.
const WALK := 3.0
const RAIL_H := 1.08
## Lamp standards along a bridge (metres apart, each side), and one real light every how many.
const LAMP_GAP := 16.0
const LIGHT_EVERY := 2
## Warm sodium for the lanterns and cobra heads, cool white for the LED strips (LINEAR).
const LANTERN := Color(1.0, 0.62, 0.26, 1.0)
const LED := Color(0.62, 0.78, 1.0, 1.0)


## A street bridge, all at once.
static func build(b: RiverBuild, br: Dictionary) -> void:
	for job: Callable in jobs(b, br):
		job.call()


## A street bridge as build jobs (RiverBuild runs one a step: an arch viaduct is ~45 ms of work).
static func jobs(b: RiverBuild, br: Dictionary) -> Array[Callable]:
	var f := _frame(b, br)
	var out: Array[Callable] = []
	match int(br.kind):
		LaRiver.Bridge.ARCH:
			out.append(func() -> void: _arch_core(f))
			for k in 4:
				out.append(func() -> void: _arch_rib(f, k))
			if b.full:
				out.append(func() -> void: _balustrade(f, -1.0))
				out.append(func() -> void: _balustrade(f, 1.0))
				out.append(func() -> void: _arch_lamps(f))
		LaRiver.Bridge.RIBBON:
			out.append(func() -> void: _ribbon_core(f))
			for k in 3:
				out.append(func() -> void: _ribbon_span(f, k))
			if b.full:
				out.append(func() -> void: _ribbon_dress(f))
		_:
			out.append(func() -> void: _girder(f))
	return out


## The bridge's frame: {"o" (Vector2 origin on the road line), "u" (along the road), "q" (across,
## to its left), "t0", "t1" (the span along u), "w" (carriageway), "half" (carriageway + walks),
## "y" (deck top, a function of t), "flow" (the river's direction), "tb" (the bed's edges along u),
## "piers" (t of the piers on the road line), "s" (the crossing's s)}.
static func _frame(b: RiverBuild, br: Dictionary) -> Dictionary:
	var u: Vector2 = br.along
	var q := Vector2(-u.y, u.x)
	var o: Vector2 = br.p0
	var t0: float = br.t0
	var t1: float = br.t1
	var s: float = br.s
	var rv := b.rv
	# Where the road's centre line crosses the bed's edges (the bank toes).
	var tb := Vector2(t0, t1)
	var found := [false, false]
	var t := t0
	while t <= t1:
		var nr := rv.nearest(o + u * t, 100.0)
		if nr.w > 0.5 and absf(nr.y) < rv.bed_half(nr.x):
			if not found[0]:
				tb.x = t
				found[0] = true
			tb.y = t
		t += 0.25
	var piers := [lerpf(tb.x, tb.y, 1.0 / 3.0), lerpf(tb.x, tb.y, 2.0 / 3.0)]
	return {"o": o, "u": u, "q": q, "t0": t0, "t1": t1, "w": float(br.width), "half": float(br.width) * 0.5 + WALK,
		"flow": br.dir, "tb": tb, "piers": piers, "s": s, "b": b, "br": br, "seed": absi(hash([b.rv.seed, br.axis, br.index]))}


## World point at (t along, a across, y up) in the bridge frame.
static func _p(f: Dictionary, t: float, a: float, y: float) -> Vector3:
	var p: Vector2 = (f.o as Vector2) + (f.u as Vector2) * t + (f.q as Vector2) * a
	return Vector3(p.x, y, p.y)


## The deck's top (the road slab's) at t on the centre line.
static func _deck_y(f: Dictionary, t: float) -> float:
	var p: Vector2 = (f.o as Vector2) + (f.u as Vector2) * t
	var b: RiverBuild = f.b
	return b.ch._gy(p.x, p.y) + CityChunk.ROAD_TOP


## The channel's surface under bridge point (t, a).
static func _ground(f: Dictionary, t: float, a: float) -> float:
	var p: Vector2 = (f.o as Vector2) + (f.u as Vector2) * t + (f.q as Vector2) * a
	var b: RiverBuild = f.b
	var nr := b.rv.nearest(p, 120.0)
	if nr.w < 0.5:
		return _deck_y(f, t) - 1.0
	return b.rv.surface(nr.x, nr.y)


## Where the line along u at offset `a` meets the line through bridge point (tc, 0) along the
## flow: the t of a pier or abutment line at that offset (piers stand parallel to the current).
static func _skew_t(f: Dictionary, tc: float, a: float) -> float:
	var u: Vector2 = f.u
	var q: Vector2 = f.q
	var d: Vector2 = f.flow
	# o + u t + q a = o + u tc + d k  ->  solve for t.
	var det := u.x * (-d.y) - (-d.x) * u.y
	if absf(det) < 1e-5:
		return tc
	var rhs := u * tc - q * a
	# [u, -d] [t, k]^T = rhs
	var tt := (rhs.x * (-d.y) - (-d.x) * rhs.y) / det
	return tt


# --- Pieces ---------------------------------------------------------------------------------------

## The deck's underside, fascias and cornice from t0 to t1, `thick` metres deep, plus the walks.
static func _deck(f: Dictionary, thick: float, cornice: bool) -> void:
	var b: RiverBuild = f.b
	var t0: float = f.t0 - 1.0
	var t1: float = f.t1 + 1.0
	var half: float = f.half
	var w: float = f.w
	var n := maxi(2, ceili((t1 - t0) / 8.0))
	var col := RiverBuild.kind_color(RiverBuild.KIND_BRIDGE, 1.0)
	for k in n:
		var ta := lerpf(t0, t1, float(k) / n)
		var tb := lerpf(t0, t1, float(k + 1) / n)
		var ya := _deck_y(f, ta)
		var yb := _deck_y(f, tb)
		# Soffit.
		b.quad("concrete", _p(f, ta, -half, ya - thick), _p(f, tb, -half, yb - thick), _p(f, tb, half, yb - thick), _p(f, ta, half, ya - thick),
			Vector3.DOWN, col, Vector2(ta, -half), Vector2(tb, -half), Vector2(tb, half), Vector2(ta, half), Vector2(2.0, 0), Vector2(2.0, 0), Vector2(2.0, 0), Vector2(2.0, 0))
		# Under the carriageway the road slab is the top; the walks are this deck's own.
		for sg: float in [-1.0, 1.0]:
			var a_in := sg * w * 0.5
			var a_out := sg * half
			b.quad("concrete", _p(f, ta, a_in, ya + 0.15), _p(f, tb, a_in, yb + 0.15), _p(f, tb, a_out, yb + 0.15), _p(f, ta, a_out, ya + 0.15),
				Vector3.UP, RiverBuild.kind_color(RiverBuild.KIND_COPING, 1.0), Vector2(ta, 0), Vector2(tb, 0), Vector2(tb, WALK), Vector2(ta, WALK))
			# The kerb face down to the carriageway.
			b.quad("concrete", _p(f, ta, a_in, ya - 0.02), _p(f, tb, a_in, yb - 0.02), _p(f, tb, a_in, yb + 0.15), _p(f, ta, a_in, ya + 0.15),
				_q3(f, -sg), col, Vector2(ta, 0), Vector2(tb, 0), Vector2(tb, 0.17), Vector2(ta, 0.17))
			# Fascia.
			b.quad("concrete", _p(f, ta, a_out, ya - thick), _p(f, tb, a_out, yb - thick), _p(f, tb, a_out, yb + 0.15), _p(f, ta, a_out, ya + 0.15),
				_q3(f, sg), col, Vector2(ta, -thick), Vector2(tb, -thick), Vector2(tb, 0.15), Vector2(ta, 0.15), Vector2(4.0, 0), Vector2(4.0, 0), Vector2(4.0, 0), Vector2(4.0, 0))
			if cornice:
				var c0 := a_out + sg * 0.32
				b.quad("concrete", _p(f, ta, a_out, ya - 0.55), _p(f, tb, a_out, yb - 0.55), _p(f, tb, c0, yb - 0.38), _p(f, ta, c0, ya - 0.38),
					_q3(f, sg) + Vector3.DOWN * 0.7, col, Vector2(ta, 0), Vector2(tb, 0), Vector2(tb, 0.35), Vector2(ta, 0.35), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
				b.quad("concrete", _p(f, ta, c0, ya - 0.38), _p(f, tb, c0, yb - 0.38), _p(f, tb, c0, yb - 0.1), _p(f, ta, c0, ya - 0.1),
					_q3(f, sg), col, Vector2(ta, 0), Vector2(tb, 0), Vector2(tb, 0.28), Vector2(ta, 0.28), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
				b.quad("concrete", _p(f, ta, c0, ya - 0.1), _p(f, tb, c0, yb - 0.1), _p(f, tb, a_out, yb - 0.1), _p(f, ta, a_out, ya - 0.1),
					Vector3.UP, col, Vector2(ta, 0), Vector2(tb, 0), Vector2(tb, 0.32), Vector2(ta, 0.32), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
	# The deck's ends, where it meets the bank.
	for tt: float in [t0, t1]:
		var y := _deck_y(f, tt)
		var dir := -1.0 if tt == t0 else 1.0
		b.quad("concrete", _p(f, tt, -half, y - thick), _p(f, tt, half, y - thick), _p(f, tt, half, y + 0.15), _p(f, tt, -half, y + 0.15),
			_u3(f, dir), col, Vector2(-half, 0), Vector2(half, 0), Vector2(half, thick), Vector2(-half, thick))


static func _u3(f: Dictionary, sg: float) -> Vector3:
	var u: Vector2 = f.u
	return Vector3(u.x, 0.0, u.y) * sg


static func _q3(f: Dictionary, sg: float) -> Vector3:
	var q: Vector2 = f.q
	return Vector3(q.x, 0.0, q.y) * sg


## A box in the bridge frame: centre (t, a, y), size (along, up, across).
static func _fbox(f: Dictionary, t: float, a: float, y: float, size: Vector3, kind: int, collide := true) -> void:
	var b: RiverBuild = f.b
	var basis := Basis(_q3(f, 1.0), Vector3.UP, _u3(f, 1.0))
	b.cbox(Transform3D(basis, _p(f, t, a, y)), Vector3(size.z, size.y, size.x), kind, 1.0, collide, _ground(f, t, a))


## A box turned to the current (a pier): centre `c`, size (across the flow, up, along the flow).
static func _flow_box(f: Dictionary, c: Vector3, size: Vector3, kind: int, collide := true) -> void:
	var b: RiverBuild = f.b
	var d: Vector2 = f.flow
	var along := Vector3(d.x, 0.0, d.y)
	var basis := Basis(Vector3(-d.y, 0.0, d.x), Vector3.UP, along)
	b.cbox(Transform3D(basis, c), size, kind, 1.0, collide, c.y - size.y * 0.5)


## A cutwater pier on the bed under bridge point (tc, 0): a slab along the current the bridge's
## width (plus a metre), pointed both ends, up to `top`.
static func _pier(f: Dictionary, tc: float, top: float, thick: float) -> void:
	var b: RiverBuild = f.b
	var half: float = f.half
	var d: Vector2 = f.flow
	var along := Vector3(d.x, 0.0, d.y)
	var cosk := absf((f.u as Vector2).dot(Vector2(-d.y, d.x)))
	var len := (half * 2.0 + 1.0) / maxf(cosk, 0.55)
	var base := _ground(f, tc, 0.0) - 0.2
	var c := _p(f, tc, 0.0, (top + base) * 0.5)
	_flow_box(f, c, Vector3(thick, top - base, len), RiverBuild.KIND_PIER)
	# The cutwaters.
	var col := RiverBuild.kind_color(RiverBuild.KIND_PIER, 1.0)
	var across := Vector3(-d.y, 0.0, d.x)
	for e: float in [-1.0, 1.0]:
		var end := c + along * (len * 0.5 * e)
		var tip := end + along * (thick * 0.9 * e)
		var l := end + across * thick * 0.5
		var r := end - across * thick * 0.5
		var lo := Vector3(0.0, base - c.y, 0.0)
		var hi := Vector3(0.0, top - c.y, 0.0)
		for side: Vector3 in [l, r]:
			var n := (tip - side).cross(Vector3.UP).normalized()
			if n.dot(side - end) < 0.0:
				n = -n
			b.quad("concrete", side + lo, tip + lo, tip + hi, side + hi, n, col,
				Vector2(0, base), Vector2(1, base), Vector2(1, top), Vector2(0, top), Vector2(0, 0), Vector2(0, 0), Vector2(top - base, 0), Vector2(top - base, 0))
		b.tri("concrete", l + hi, r + hi, tip + hi, Vector3.UP, col, Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1))


## A rib along points `pts` (world), `width` across (along `side`) and `depth` in its own plane.
static func _rib(f: Dictionary, pts: Array, side: Vector3, width: float, depth: float, kind: int, collide := true, glow_key := "") -> void:
	var b: RiverBuild = f.b
	var col := RiverBuild.kind_color(kind, 1.0)
	var n := pts.size()
	var ups: Array[Vector3] = []
	for i in n:
		var a: Vector3 = pts[maxi(i - 1, 0)]
		var c: Vector3 = pts[mini(i + 1, n - 1)]
		var tng := (c - a).normalized()
		var up := side.cross(tng).normalized()
		if up.y < 0.0:
			up = -up
		ups.append(up)
	var run := 0.0
	for i in n - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var seg := p0.distance_to(p1)
		var hw := side * width * 0.5
		var u0 := ups[i] * depth * 0.5
		var u1 := ups[i + 1] * depth * 0.5
		var r0 := run
		var r1 := run + seg
		var h0 := Vector2(p0.y - _ground_y(f, p0), 0.0)
		var h1 := Vector2(p1.y - _ground_y(f, p1), 0.0)
		b.quad("concrete", p0 + hw + u0, p1 + hw + u1, p1 - hw + u1, p0 - hw + u0, (ups[i] + ups[i + 1]), col, Vector2(r0, 0), Vector2(r1, 0), Vector2(r1, width), Vector2(r0, width), h0, h1, h1, h0, collide)
		b.quad("concrete", p0 + hw - u0, p1 + hw - u1, p1 - hw - u1, p0 - hw - u0, -(ups[i] + ups[i + 1]), col, Vector2(r0, 0), Vector2(r1, 0), Vector2(r1, width), Vector2(r0, width), h0, h1, h1, h0, collide)
		b.quad("concrete", p0 + hw - u0, p1 + hw - u1, p1 + hw + u1, p0 + hw + u0, side, col, Vector2(r0, 0), Vector2(r1, 0), Vector2(r1, depth), Vector2(r0, depth), h0, h1, h1, h0, collide)
		b.quad("concrete", p0 - hw - u0, p1 - hw - u1, p1 - hw + u1, p0 - hw + u0, -side, col, Vector2(r0, 0), Vector2(r1, 0), Vector2(r1, depth), Vector2(r0, depth), h0, h1, h1, h0, collide)
		if glow_key != "":
			# An LED strip under the rib's soffit.
			var g0 := p0 - u0 * 1.02
			var g1 := p1 - u1 * 1.02
			var gw := side * 0.12
			b.quad("lamp", g0 + gw, g1 + gw, g1 - gw, g0 - gw, -(ups[i] + ups[i + 1]), LED, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
		run = r1


static func _ground_y(f: Dictionary, p: Vector3) -> float:
	var b: RiverBuild = f.b
	var nr := b.rv.nearest(Vector2(p.x, p.z), 120.0)
	return b.rv.surface(nr.x, nr.y) if nr.w > 0.5 else p.y


## An upright n-sided column from `base` `height` metres up, radius `r` (tapering to `r_top`).
static func _column(b: RiverBuild, base: Vector3, height: float, r: float, r_top: float, sides: int, kind: int, collide := true) -> void:
	var col := RiverBuild.kind_color(kind, 1.0)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var e0 := Vector3(cos(a0), 0.0, sin(a0))
		var e1 := Vector3(cos(a1), 0.0, sin(a1))
		b.quad("concrete", base + e0 * r, base + e1 * r, base + e1 * r_top + Vector3.UP * height, base + e0 * r_top + Vector3.UP * height,
			(e0 + e1).normalized(), col, Vector2(a0 * r, 0), Vector2(a1 * r, 0), Vector2(a1 * r, height), Vector2(a0 * r, height),
			Vector2(0, 0), Vector2(0, 0), Vector2(height, 0), Vector2(height, 0), collide)
	var top := base + Vector3.UP * height
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		b.tri("concrete", top, top + Vector3(cos(a0), 0, sin(a0)) * r_top, top + Vector3(cos(a1), 0, sin(a1)) * r_top, Vector3.UP, col, Vector2(0, 0), Vector2(1, 0), Vector2(0, 1),
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)


## A glowing globe (lantern) of radius r at c, on the lamp material.
static func _globe(b: RiverBuild, c: Vector3, r: float, glow: Color) -> void:
	var rings := 4
	var segs := 8
	for i in rings:
		var p0 := PI * float(i) / rings - PI * 0.5
		var p1 := PI * float(i + 1) / rings - PI * 0.5
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var v00 := c + Vector3(cos(p0) * cos(a0), sin(p0), cos(p0) * sin(a0)) * r
			var v10 := c + Vector3(cos(p0) * cos(a1), sin(p0), cos(p0) * sin(a1)) * r
			var v01 := c + Vector3(cos(p1) * cos(a0), sin(p1), cos(p1) * sin(a0)) * r
			var v11 := c + Vector3(cos(p1) * cos(a1), sin(p1), cos(p1) * sin(a1)) * r
			var want := ((v00 + v11) * 0.5 - c)
			b.quad("lamp", v00, v10, v11, v01, want, glow, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)


## A real light (FULL), DayNight's lamp group, and its pool on the deck.
static func _light(f: Dictionary, at: Vector3, deck: Vector3, color: Color, reach: float) -> void:
	var b: RiverBuild = f.b
	if not b.full:
		return
	var light := OmniLight3D.new()
	light.position = at
	light.omni_range = reach
	light.omni_attenuation = 1.4
	light.light_color = Color(color.r, color.g, color.b)
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	light.add_to_group("lamp_light")
	b.ch.add_child(light)
	var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(CityChunk.LAMP_POOL_SIZE, 1.0, CityChunk.LAMP_POOL_SIZE)), b._rel(deck + Vector3(0.0, 0.09, 0.0)))
	b.ch._batch.add("lamp_pool", PropFactory.light_pool(), pool)
	b.ch._batch.set_no_shadow("lamp_pool")


## The rib points of a segmental arch along offset `a` from tb_a to tb_b (bridge t at the
## springing), springing at `y_s`, rise to `y_c`.
static func _arch_pts(f: Dictionary, ta: float, tb: float, a: float, y_s: float, y_c: float, n: int) -> Array:
	var out: Array = []
	for i in n + 1:
		var x := float(i) / n
		var t := lerpf(ta, tb, x)
		var e := 2.0 * x - 1.0
		var y := y_s + (y_c - y_s) * pow(maxf(1.0 - e * e, 0.0), 0.62)
		out.append(_p(f, t, a, y))
	return out


# --- ARCH ------------------------------------------------------------------------------------------

static func _arch_core(f: Dictionary) -> void:
	_deck(f, ARCH_THICK, (f.b as RiverBuild).full)
	for tc: float in f.piers:
		_pier(f, tc, _arch_spring(f) + 0.5, 2.6)


const ARCH_THICK := 0.95


static func _arch_spring(f: Dictionary) -> float:
	return _ground(f, (float(f.t0) + float(f.t1)) * 0.5, 0.0) + 0.9


## Rib `k` of four (under the walks' edges and the carriageway's quarters) in its three spans,
## with its spandrel columns, and the solid spandrel walls over the banks either end.
static func _arch_rib(f: Dictionary, k: int) -> void:
	var b: RiverBuild = f.b
	var full := b.full
	var tb: Vector2 = f.tb
	var piers: Array = f.piers
	var half: float = f.half
	var thick := ARCH_THICK
	var deck := _deck_y(f, (float(f.t0) + float(f.t1)) * 0.5)
	var spring := _arch_spring(f)
	var a: float = [-(half - 1.0), -half * 0.4, half * 0.4, half - 1.0][k]
	var spans := [[tb.x, piers[0]], [piers[0], piers[1]], [piers[1], tb.y]]
	var n := 14 if full else 6
	var crown := deck - thick - 0.55
	for sp: Array in spans:
		var ta := _skew_t(f, float(sp[0]), a) + (0.0 if sp[0] == tb.x else 1.3)
		var tz := _skew_t(f, float(sp[1]), a) - (0.0 if sp[1] == tb.y else 1.3)
		var pts := _arch_pts(f, ta, tz, a, spring, crown, n)
		_rib(f, pts, _q3(f, 1.0), 1.0, 1.1, RiverBuild.KIND_BRIDGE)
		if full:
			# Spandrel columns from the rib up to the deck.
			var t := ta + 2.2
			while t < tz - 2.0:
				var x := (t - ta) / (tz - ta)
				var e := 2.0 * x - 1.0
				var y := spring + (crown - spring) * pow(maxf(1.0 - e * e, 0.0), 0.62)
				var hgt := (deck - thick) - (y + 0.5)
				if hgt > 0.5:
					_fbox(f, t, a, y + 0.5 + hgt * 0.5, Vector3(0.55, hgt, 0.7), RiverBuild.KIND_BRIDGE, false)
				t += 3.1
	# The bank spans: a solid spandrel wall from the bank up to the deck between the top edge and
	# the bed's edge, either end.
	for e: float in [0.0, 1.0]:
		var ta := float(f.t0) if e == 0.0 else _skew_t(f, tb.y, a)
		var tz := _skew_t(f, tb.x, a) if e == 0.0 else float(f.t1)
		var m_n := 4 if full else 2
		for m in m_n:
			var t_a := lerpf(ta, tz, float(m) / m_n)
			var t_b := lerpf(ta, tz, float(m + 1) / m_n)
			var g := minf(_ground(f, t_a, a), _ground(f, t_b, a))
			var top := deck - thick
			if top - g > 0.3:
				_fbox(f, (t_a + t_b) * 0.5, a, (top + g) * 0.5, Vector3(t_b - t_a, top - g, 1.0), RiverBuild.KIND_BRIDGE)


## The pylons and the twin-lantern standards on the balustrade's posts.
static func _arch_lamps(f: Dictionary) -> void:
	var half: float = f.half
	_pylons(f)
	var t := float(f.t0) + 4.0
	var i := 0
	while t < float(f.t1) - 3.0:
		for sg: float in [-1.0, 1.0]:
			_lantern_post(f, t, sg * (half - 0.25), i % LIGHT_EVERY == 0 and (sg > 0.0) == (i % 2 == 0))
		t += LAMP_GAP
		i += 1


## A turned balustrade along both deck edges: plinth, balusters, a heavy top rail, a post every
## six metres.
static func _balustrade(f: Dictionary, sg: float) -> void:
	var b: RiverBuild = f.b
	var half: float = f.half
	var t0: float = f.t0 - 1.0
	var t1: float = f.t1 + 1.0
	if true:
		var a := sg * (half - 0.25)
		var n := maxi(2, ceili((t1 - t0) / 6.0))
		for k in n:
			var ta := lerpf(t0, t1, float(k) / n)
			var tz := lerpf(t0, t1, float(k + 1) / n)
			var y := _deck_y(f, (ta + tz) * 0.5) + 0.15
			# Plinth and rail.
			_fbox(f, (ta + tz) * 0.5, a, y + 0.14, Vector3(tz - ta, 0.28, 0.5), RiverBuild.KIND_BRIDGE)
			_fbox(f, (ta + tz) * 0.5, a, y + RAIL_H - 0.11, Vector3(tz - ta, 0.22, 0.42), RiverBuild.KIND_BRIDGE)
			# Post at the segment's start.
			_fbox(f, ta, a, y + (RAIL_H + 0.25) * 0.5, Vector3(0.62, RAIL_H + 0.25, 0.62), RiverBuild.KIND_BRIDGE)
			# Balusters.
			var m := int((tz - ta - 0.62) / 0.36)
			for j in m:
				var t := ta + 0.31 + 0.36 * (float(j) + 0.5) + ((tz - ta - 0.62) - m * 0.36) * 0.5
				var base := _p(f, t, a, y + 0.28)
				b.ch._batch.add("rv_baluster", baluster_mesh(), Transform3D(Basis(), b._rel(base)))
		var ye := _deck_y(f, t1) + 0.15
		_fbox(f, t1, a, ye + (RAIL_H + 0.25) * 0.5, Vector3(0.62, RAIL_H + 0.25, 0.62), RiverBuild.KIND_BRIDGE)


static var _baluster_mesh: ArrayMesh


## The turned baluster as one mesh on the river's concrete, for a batch: one per balustrade gap,
## hundreds a viaduct, so it is instanced rather than written into the chunk's mesh.
static func baluster_mesh() -> ArrayMesh:
	if _baluster_mesh == null:
		var tmp := RiverBuild.new()
		_baluster(tmp, Vector3.ZERO, RAIL_H - 0.5)
		_baluster_mesh = (tmp._st["concrete"] as SurfaceTool).commit()
		_baluster_mesh.surface_set_material(0, RiverBuild.concrete_material())
	return _baluster_mesh


## One turned baluster: a vase on six sides, `h` tall.
static func _baluster(b: RiverBuild, base: Vector3, h: float) -> void:
	var prof := [[0.0, 0.07], [0.12, 0.05], [0.45, 0.095], [0.8, 0.05], [1.0, 0.075]]
	var sides := 6
	var col := RiverBuild.kind_color(RiverBuild.KIND_BRIDGE, 1.0)
	for i in prof.size() - 1:
		var y0: float = float(prof[i][0]) * h
		var y1: float = float(prof[i + 1][0]) * h
		var r0: float = prof[i][1]
		var r1: float = prof[i + 1][1]
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var e0 := Vector3(cos(a0), 0.0, sin(a0))
			var e1 := Vector3(cos(a1), 0.0, sin(a1))
			b.quad("concrete", base + e0 * r0 + Vector3.UP * y0, base + e1 * r0 + Vector3.UP * y0, base + e1 * r1 + Vector3.UP * y1, base + e0 * r1 + Vector3.UP * y1,
				(e0 + e1).normalized(), col, Vector2(a0 * r0, y0), Vector2(a1 * r0, y0), Vector2(a1 * r1, y1), Vector2(a0 * r1, y1),
				Vector2(4, 0), Vector2(4, 0), Vector2(4, 0), Vector2(4, 0), false)


## A twin-lantern standard: a fluted column, a crossarm and two globes; `lit` hangs a real light.
static func _lantern_post(f: Dictionary, t: float, a: float, lit: bool) -> void:
	var b: RiverBuild = f.b
	var y := _deck_y(f, t) + 0.15 + RAIL_H + 0.25
	var base := _p(f, t, a, y)
	_column(b, base, 4.2, 0.17, 0.12, 8, RiverBuild.KIND_BRIDGE, false)
	var top := base + Vector3.UP * 4.2
	var u := _u3(f, 1.0)
	_fbox(f, t, a, y + 4.25, Vector3(1.5, 0.12, 0.12), RiverBuild.KIND_BRIDGE, false)
	for e: float in [-0.68, 0.68]:
		_globe(b, top + u * e + Vector3.UP * 0.32, 0.26, LANTERN)
	_globe(b, top + Vector3.UP * 0.62, 0.2, LANTERN)
	if lit:
		_light(f, top + Vector3.UP * 0.4, _p(f, t, a - signf(a) * 3.5, _deck_y(f, t)), Color(1.0, 0.8, 0.55), 15.0)


## The four corner pylons where the viaduct leaves the banks: stepped, with a lantern on top.
static func _pylons(f: Dictionary) -> void:
	var b: RiverBuild = f.b
	var half: float = f.half
	for tt: float in [float(f.t0) - 0.2, float(f.t1) + 0.2]:
		for sg: float in [-1.0, 1.0]:
			var a := sg * (half - 0.6)
			var y := _deck_y(f, tt) + 0.15
			_fbox(f, tt, a, y + 1.6, Vector3(1.7, 3.2, 1.7), RiverBuild.KIND_BRIDGE)
			_fbox(f, tt, a, y + 4.6, Vector3(1.35, 2.8, 1.35), RiverBuild.KIND_BRIDGE)
			_fbox(f, tt, a, y + 6.25, Vector3(1.6, 0.5, 1.6), RiverBuild.KIND_BRIDGE)
			_fbox(f, tt, a, y + 6.9, Vector3(0.9, 0.8, 0.9), RiverBuild.KIND_BRIDGE)
			_globe(b, _p(f, tt, a, y + 7.75), 0.42, LANTERN)


# --- RIBBON ----------------------------------------------------------------------------------------

const RIBBON_THICK := 1.5
const RIBBON_RISE := 9.5
const RIBBON_LEAN := 0.2


static func _ribbon_core(f: Dictionary) -> void:
	_deck(f, RIBBON_THICK, false)
	var deck := _deck_y(f, (float(f.t0) + float(f.t1)) * 0.5)
	# Slim pier walls under the arch springings.
	for tc: float in f.piers:
		_pier(f, tc, deck - RIBBON_THICK, 1.6)


## Span `k` of three: a pair of ribs leaning outward over the deck, their LED strips and hangers.
static func _ribbon_span(f: Dictionary, k: int) -> void:
	var b: RiverBuild = f.b
	var full := b.full
	var piers: Array = f.piers
	var half: float = f.half
	var stops := [float(f.t0) + 0.5, piers[0], piers[1], float(f.t1) - 0.5]
	var n := 16 if full else 6
	var ta: float = stops[k]
	var tz: float = stops[k + 1]
	for sg: float in [-1.0, 1.0]:
		var a0 := sg * (half + 0.4)
		var pts: Array = []
		var ys: Array = []
		for i in n + 1:
			var x := float(i) / n
			var e := 2.0 * x - 1.0
			var h := RIBBON_RISE * pow(maxf(1.0 - e * e, 0.0), 0.7)
			var t := lerpf(ta, tz, x)
			# Leaning outward as it rises.
			var a := a0 + sg * h * RIBBON_LEAN
			var y := _deck_y(f, t) + 0.2 + h
			pts.append(_p(f, t, a, y))
			ys.append([t, a, y])
		_rib(f, pts, _q3(f, 1.0), 0.9, 1.2, RiverBuild.KIND_BRIDGE, true, "led" if full else "")
		if not full:
			continue
		# Hangers: cables from the rib to the deck edge.
		for i in range(1, n):
			var tt: float = ys[i][0]
			var aa: float = ys[i][1]
			var yy: float = ys[i][2]
			var bot := _p(f, tt, sg * (half + 0.2), _deck_y(f, tt) + 0.15)
			var top := _p(f, tt, aa, yy - 0.6)
			var mid := (bot + top) * 0.5
			var dirv := (top - bot)
			var len := dirv.length()
			if len < 0.5:
				continue
			var y_axis := dirv / len
			var x_axis := _u3(f, 1.0)
			var z_axis := x_axis.cross(y_axis).normalized()
			x_axis = y_axis.cross(z_axis).normalized()
			Industrial._wbox(b.ch, Transform3D(Basis(x_axis, y_axis, z_axis), mid), Vector3(0.05, len, 0.05), IndustrialKit.K_GALV, Color(0.85, 0.86, 0.88))


## The ribbon's steel rails and its slim LED lamp poles.
static func _ribbon_dress(f: Dictionary) -> void:
	var b: RiverBuild = f.b
	var half: float = f.half
	_steel_rail(f)
	var t := float(f.t0) + 6.0
	var i := 0
	while t < float(f.t1) - 4.0:
		var sg := 1.0 if i % 2 == 0 else -1.0
		var a := sg * (half - 0.35)
		var y := _deck_y(f, t) + 0.15
		Industrial._wbox(b.ch, Transform3D(Basis(), _p(f, t, a, y + 3.5)), Vector3(0.14, 7.0, 0.14), IndustrialKit.K_GALV, Color(0.82, 0.83, 0.85))
		var head := _p(f, t, a - sg * 1.0, y + 7.0)
		Industrial._wbox(b.ch, Transform3D(Basis(Vector3.UP, atan2(-(f.q as Vector2).x, -(f.q as Vector2).y)), head), Vector3(0.3, 0.12, 2.1), IndustrialKit.K_GALV, Color(0.82, 0.83, 0.85))
		var lens := _p(f, t, a - sg * 1.5, y + 6.92)
		b.quad("lamp", lens + _u3(f, 0.22) + _q3(f, 0.4), lens + _u3(f, -0.22) + _q3(f, 0.4), lens + _u3(f, -0.22) + _q3(f, -0.4), lens + _u3(f, 0.22) + _q3(f, -0.4),
			Vector3.DOWN, Color(0.85, 0.9, 1.0, 1.0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
		if i % LIGHT_EVERY == 0:
			_light(f, lens + Vector3.DOWN * 0.3, _p(f, t, a - sg * 3.0, _deck_y(f, t)), Color(0.85, 0.9, 1.0), 16.0)
		t += LAMP_GAP * 0.8
		i += 1


## A steel rail with cable infill along both deck edges (posts every 1.6 m).
static func _steel_rail(f: Dictionary) -> void:
	var b: RiverBuild = f.b
	var half: float = f.half
	var t0: float = f.t0 - 1.0
	var t1: float = f.t1 + 1.0
	var basis := Basis(_q3(f, 1.0), Vector3.UP, _u3(f, 1.0))
	for sg: float in [-1.0, 1.0]:
		var a := sg * (half - 0.15)
		var n := maxi(2, ceili((t1 - t0) / 8.0))
		for k in n:
			var ta := lerpf(t0, t1, float(k) / n)
			var tz := lerpf(t0, t1, float(k + 1) / n)
			var y := _deck_y(f, (ta + tz) * 0.5) + 0.15
			var mid := (ta + tz) * 0.5
			Industrial._wbox(b.ch, Transform3D(basis, _p(f, mid, a, y + RAIL_H)), Vector3(0.12, 0.08, tz - ta), IndustrialKit.K_GALV, Color(0.86, 0.87, 0.89))
			for c in 4:
				Industrial._wbox(b.ch, Transform3D(basis, _p(f, mid, a, y + 0.2 + 0.2 * c)), Vector3(0.02, 0.02, tz - ta), IndustrialKit.K_GALV, Color(0.7, 0.71, 0.73))
			var m := int((tz - ta) / 1.6)
			for j in m:
				var t := ta + (float(j) + 0.5) * (tz - ta) / m
				Industrial._wbox(b.ch, Transform3D(basis, _p(f, t, a, y + RAIL_H * 0.5)), Vector3(0.06, RAIL_H, 0.06), IndustrialKit.K_GALV, Color(0.86, 0.87, 0.89))
		# Collision: one box each side.
		var uu: Vector2 = f.u
		b.ch._add_shape(Vector3(0.2, RAIL_H, t1 - t0), _p(f, (t0 + t1) * 0.5, a, _deck_y(f, (t0 + t1) * 0.5) + 0.15 + RAIL_H * 0.5), atan2(-uu.x, -uu.y))


# --- GIRDER ----------------------------------------------------------------------------------------

static func _girder(f: Dictionary) -> void:
	var b: RiverBuild = f.b
	var full := b.full
	var piers: Array = f.piers
	var half: float = f.half
	var thick := 1.7
	_deck(f, thick, false)
	var d: Vector2 = f.flow
	var cosk := absf((f.u as Vector2).dot(Vector2(-d.y, d.x)))
	# Bents: round columns under a cap beam turned to the current.
	for tc: float in piers:
		var top := _deck_y(f, tc) - thick
		var cap_len := (half * 2.0) / maxf(cosk, 0.55)
		_flow_box(f, _p(f, tc, 0.0, top - 0.6), Vector3(1.6, 1.2, cap_len), RiverBuild.KIND_PIER)
		var cols := 3
		for k in cols:
			var along := lerpf(-cap_len * 0.36, cap_len * 0.36, float(k) / (cols - 1))
			var c := _p(f, tc, 0.0, 0.0) + Vector3(d.x, 0.0, d.y) * along
			var g := _ground_y(f, c) - 0.1
			if full:
				_column(b, Vector3(c.x, g, c.z), top - 1.2 - g, 0.65, 0.6, 10, RiverBuild.KIND_PIER)
			else:
				_flow_box(f, Vector3(c.x, (g + top - 1.2) * 0.5, c.z), Vector3(1.2, top - 1.2 - g, 1.2), RiverBuild.KIND_PIER)
	if not full:
		return
	# Concrete barrier with a steel rail on it, both edges.
	var t0: float = f.t0 - 1.0
	var t1: float = f.t1 + 1.0
	var basis := Basis(_q3(f, 1.0), Vector3.UP, _u3(f, 1.0))
	for sg: float in [-1.0, 1.0]:
		var a := sg * (half - 0.28)
		var n := maxi(2, ceili((t1 - t0) / 8.0))
		for k in n:
			var ta := lerpf(t0, t1, float(k) / n)
			var tz := lerpf(t0, t1, float(k + 1) / n)
			var y := _deck_y(f, (ta + tz) * 0.5) + 0.15
			_fbox(f, (ta + tz) * 0.5, a, y + 0.42, Vector3(tz - ta, 0.84, 0.48), RiverBuild.KIND_BRIDGE)
			Industrial._wbox(b.ch, Transform3D(basis, _p(f, (ta + tz) * 0.5, a, y + 1.05)), Vector3(0.1, 0.1, tz - ta), IndustrialKit.K_GALV, Color(0.66, 0.67, 0.68))
			var m := int((tz - ta) / 2.0)
			for j in m:
				var t := ta + (float(j) + 0.5) * (tz - ta) / m
				Industrial._wbox(b.ch, Transform3D(basis, _p(f, t, a, y + 0.95)), Vector3(0.08, 0.22, 0.08), IndustrialKit.K_GALV, Color(0.66, 0.67, 0.68))
	# Cobra-head lamps, alternating sides.
	var t := float(f.t0) + 8.0
	var i := 0
	while t < float(f.t1) - 4.0:
		var sg := 1.0 if i % 2 == 0 else -1.0
		var a := sg * (half - 0.28)
		var y := _deck_y(f, t) + 0.15 + 0.84
		Industrial._wbox(b.ch, Transform3D(Basis(), _p(f, t, a, y + 4.2)), Vector3(0.2, 8.4, 0.2), IndustrialKit.K_GALV, Color(0.62, 0.63, 0.64))
		var arm := _p(f, t, a - sg * 1.3, y + 8.3)
		Industrial._wbox(b.ch, Transform3D(basis, arm), Vector3(2.6, 0.12, 0.12), IndustrialKit.K_GALV, Color(0.62, 0.63, 0.64))
		var head := _p(f, t, a - sg * 2.6, y + 8.25)
		Industrial._wbox(b.ch, Transform3D(basis, head), Vector3(0.9, 0.22, 0.4), IndustrialKit.K_GALV, Color(0.55, 0.56, 0.57))
		var lens := head + Vector3.DOWN * 0.12
		b.quad("lamp", lens + _u3(f, 0.18) + _q3(f, 0.4), lens + _u3(f, -0.18) + _q3(f, 0.4), lens + _u3(f, -0.18) + _q3(f, -0.4), lens + _u3(f, 0.18) + _q3(f, -0.4),
			Vector3.DOWN, LANTERN, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
		if i % LIGHT_EVERY == 0:
			_light(f, lens + Vector3.DOWN * 0.3, _p(f, t, a - sg * 4.0, _deck_y(f, t)), Color(1.0, 0.78, 0.5), 18.0)
		t += LAMP_GAP * 1.6
		i += 1


# --- RAIL ------------------------------------------------------------------------------------------

## The freight rail bridge (LaRiver.rail_bridge()): a deck between two steel plate girders on
## piers, its track run on over the bank roads to buffer stops.
static func build_rail(b: RiverBuild, rail: Dictionary) -> void:
	for job: Callable in rail_jobs(b, rail):
		job.call()


## The rail bridge as build jobs: the deck, piers and girders; then the track.
static func rail_jobs(b: RiverBuild, rail: Dictionary) -> Array[Callable]:
	var out: Array[Callable] = []
	out.append(func() -> void: _rail_bridge(b, rail, true))
	out.append(func() -> void: _rail_bridge(b, rail, false))
	return out


static func _rail_bridge(b: RiverBuild, rail: Dictionary, structure: bool) -> void:
	var rv := b.rv
	var s: float = rail.s
	var c: Vector2 = rail.p
	var u: Vector2 = rail.dir
	var th := rv.top_half(s)
	var half: float = rail.half
	var f := {"o": c - u * half, "u": u, "q": Vector2(-u.y, u.x), "t0": half - th - 1.0, "t1": half + th + 1.0, "w": 4.2, "half": 2.9,
		"flow": rail.flow, "b": b, "s": s}
	var tb := Vector2(half - rv.bed_half(s), half + rv.bed_half(s))
	f["tb"] = tb
	f["piers"] = [lerpf(tb.x, tb.y, 1.0 / 3.0), lerpf(tb.x, tb.y, 2.0 / 3.0)]
	var top := rv.top_at(s)
	var deck := top + 0.3
	var full := b.full
	var t0: float = f.t0
	var t1: float = f.t1
	var basis := Basis(_q3(f, 1.0), Vector3.UP, _u3(f, 1.0))
	if not structure:
		_rail_track(b, f, deck, basis)
		return
	# The deck slab under the track.
	_fbox_y(f, (t0 + t1) * 0.5, 0.0, deck - 0.55, Vector3(t1 - t0, 1.1, 5.0), RiverBuild.KIND_BRIDGE)
	for tc: float in f.piers:
		_pier(f, tc, deck - 1.1, 2.2)
	var steel := Color(0.24, 0.17, 0.12)
	# The plate girders: deep webs with flanges, stiffened every 1.5 m, both sides.
	for sg: float in [-1.0, 1.0]:
		var a := sg * 2.75
		var mid := (t0 + t1) * 0.5
		var len := t1 - t0
		Industrial._wbox(b.ch, Transform3D(basis, _p(f, mid, a, deck + 1.35)), Vector3(0.05, 2.7, len), IndustrialKit.K_STEEL, steel)
		Industrial._wbox(b.ch, Transform3D(basis, _p(f, mid, a, deck + 2.68)), Vector3(0.6, 0.06, len), IndustrialKit.K_STEEL, steel)
		Industrial._wbox(b.ch, Transform3D(basis, _p(f, mid, a, deck + 0.04)), Vector3(0.6, 0.06, len), IndustrialKit.K_STEEL, steel)
		if full:
			var n := int(len / 1.5)
			for k in n + 1:
				var t := t0 + len * float(k) / n
				Industrial._wbox(b.ch, Transform3D(basis, _p(f, t, a + sg * 0.12, deck + 1.35)), Vector3(0.2, 2.6, 0.04), IndustrialKit.K_STEEL, steel)
				Industrial._wbox(b.ch, Transform3D(basis, _p(f, t, a - sg * 0.12, deck + 1.35)), Vector3(0.2, 2.6, 0.04), IndustrialKit.K_STEEL, steel)
		b.ch._add_shape(Vector3(0.6, 2.7, len), _p(f, mid, a, deck + 1.35), atan2(-u.x, -u.y))


## The rail bridge's track: ties and rails the whole length, on the deck over the channel, set in
## the bank roads where it crosses them, on a ballast bank on the yards, buffer stops at both ends.
static func _rail_track(b: RiverBuild, f: Dictionary, deck: float, basis: Basis) -> void:
	var u: Vector2 = f.u
	var t0: float = f.t0
	var t1: float = f.t1
	var full := b.full
	var half: float = ((f.t0 as float) + (f.t1 as float)) * 0.5
	var road_half := b.rv.top_half(float(f.s)) + LaRiver.COPING_W + LaRiver.BANK_ROAD + LaRiver.FENCE_OUT
	var level := func(t: float) -> float:
		var pm := (f.o as Vector2) + u * t
		if t > t0 and t < t1:
			return deck
		if absf(t - half) < road_half:
			# Set in the bank road: the rails' heads at its surface.
			return b.ch._gy(pm.x, pm.y) + CityChunk.ROAD_TOP - 0.31
		return b.ch._gy(pm.x, pm.y) + CityChunk.SIDEWALK_TOP + 0.25
	var tie := PropFactory.unit_box()
	var full_len := half * 2.0
	var nt := int(full_len / RiverBuild.TIE_GAP)
	for k in nt:
		var t := (float(k) + 0.5) * full_len / nt
		var y: float = level.call(t)
		var p := _p(f, t, 0.0, y + 0.08)
		if full:
			b.ch._batch.add("rv_tie", tie, Transform3D(Basis(Vector3.UP, atan2(-u.x, -u.y)).scaled_local(Vector3(2.6, 0.16, 0.24)), b._rel(p)), Color(0.24, 0.2, 0.17))
	var segs := 16 if full else 4
	for k in segs:
		var ta := full_len * float(k) / segs
		var tz := full_len * float(k + 1) / segs
		var tm := (ta + tz) * 0.5
		var over := tm > t0 and tm < t1
		var y: float = level.call(tm)
		if not over and absf(tm - half) >= road_half:
			# Ballast bank off the bridge.
			_fbox_y(f, tm, 0.0, y - 0.2, Vector3(tz - ta, 0.5, 4.2), RiverBuild.KIND_COPING)
		for rs: float in [-0.7175, 0.7175]:
			Industrial._wbox(b.ch, Transform3D(basis, _p(f, tm, rs, y + 0.25)), Vector3(0.08, 0.15, tz - ta + 0.02), IndustrialKit.K_STEEL, Color(0.36, 0.3, 0.26))
	for e: float in [0.6, full_len - 0.6]:
		var pe := (f.o as Vector2) + u * e
		var y := b.ch._gy(pe.x, pe.y) + CityChunk.SIDEWALK_TOP + 0.25
		Industrial._wbox(b.ch, Transform3D(basis, _p(f, e, 0.0, y + 0.75)), Vector3(2.4, 1.2, 0.8), IndustrialKit.K_STEEL, Color(0.75, 0.6, 0.1))


static func _fbox_y(f: Dictionary, t: float, a: float, y: float, size: Vector3, kind: int) -> void:
	_fbox(f, t, a, y, size, kind, true)
