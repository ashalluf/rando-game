class_name StuntKit
extends RefCounted
## The stunt features' geometry (StuntRamps plans them, StuntBuild puts them in the chunks), built
## in code at real size into LandmarkGeo on ONE material (shaders/stunt_ramp.gdshader): what a face
## is in COLOR.a (K_*, in 16ths), paint in COLOR.rgb (display numbers), UV metres. Every piece is
## in its own frame: +Z the way you ride it, +X across, +Y up, the origin on the ground at the
## foot's centre. Meshes that depend only on their numbers are cached (a kicker is the same kicker
## on every car park); each comes with its collision triangles in the same frame.
##   kicker()    steel: a circular-arc transition up to the lip, diamond plate on stringers, painted
##               side cheeks with hazard bands, a round lip bar, the frame open at the back (posts,
##               a cross brace, a top beam), rubber feet.
##   launch()    the freeway pair's tall kicker and landing(): a plated deck on a galvanised frame
##               of columns, ties and X bracing in every bay, guard rails both sides.
##   qpipe()     cast concrete: the transition, a steel coping, the deck back to the bank.
##   loop()      a steel loop-the-loop: a plated track with rails, shifted sideways over the turn so
##               the exit lane runs beside the entry, two lattice towers with arms to the upper half,
##               columns under the climb and the descent, entry and exit aprons.
##   dirt()      a line of tabletops as a height field on the lot's ground.

const K_PAINT := 0
const K_PLATE := 1
const K_HAZARD := 2
const K_CONCRETE := 3
const K_COPING := 4
const K_DIRT := 5
const K_PLY := 6
const K_RUBBER := 7
const K_GALV := 8

const S := "s"

static var _material: ShaderMaterial
static var _cache: Dictionary = {}


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/stunt_ramp.gdshader")
		_material.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
		_material.set_shader_parameter("dirt_tex", PropFactory.texture("hill_dirt", "Color"))
		_material.set_shader_parameter("paint_tex", PropFactory.texture("metal_painted", "Color"))
		_material.set_shader_parameter("plank_tex", PropFactory.texture("planks", "Color"))
	return _material


static func c(paint: Color, k: int) -> Color:
	return Color(paint.r, paint.g, paint.b, (float(k) + 0.5) / 16.0)


static func _geo() -> LandmarkGeo:
	var g := LandmarkGeo.new()
	g.use(S, material())
	return g


## [ArrayMesh, PackedVector3Array collision, triangles] of a finished geo.
static func _finish(g: LandmarkGeo) -> Array:
	var tris := g.triangles
	var holder := Node3D.new()
	var mi := g.commit(holder, "m")
	var mesh: Mesh = mi.mesh if mi != null else null
	holder.free()
	var col := g.collision
	g.collision = PackedVector3Array()
	return [mesh, col, tris]


static func _cached(key: String, maker: Callable) -> Array:
	if not _cache.has(key):
		_cache[key] = maker.call()
	return _cache[key]


## Builds every cached piece once (the loading screen), so the first car park roof costs nothing.
static func warm() -> void:
	kicker(StuntRamps.KICKER_LEN, StuntRamps.KICKER_H, StuntRamps.KICKER_W, StuntRamps.PAINTS[0])
	kicker(StuntRamps.PIER_LEN, StuntRamps.PIER_H, StuntRamps.PIER_W, Color(0.86, 0.16, 0.10))


# --- Shared pieces -------------------------------------------------------------------------------

## A box member from `a` to `b` (its centre line), `t` thick, collision optional.
static func member(g: LandmarkGeo, a: Vector3, b: Vector3, t: float, col: Color, collide := false) -> void:
	var d := b - a
	var l := d.length()
	if l < 1e-3:
		return
	var z := d / l
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	g.box(S, (a + b) * 0.5, Vector3(t, t, l), col, Basis(x, y, z), 0.0, collide)


## A round bar from `a` to `b`, radius `r`, `n` sides (UV: u round it, v along it).
static func bar(g: LandmarkGeo, a: Vector3, b: Vector3, r: float, col: Color, n := 8, collide := false) -> void:
	var d := b - a
	var l := d.length()
	if l < 1e-3:
		return
	var z := d / l
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var n0 := x * cos(a0) + y * sin(a0)
		var n1 := x * cos(a1) + y * sin(a1)
		g.quad_n(S, a + n0 * r, a + n1 * r, b + n1 * r, b + n0 * r, n0, n1, n1, n0,
			Vector2(a0 * r, 0.0), Vector2(a1 * r, 0.0), Vector2(a1 * r, l), Vector2(a0 * r, l), col, collide)


## The circular-arc transition: [z, y, slope angle] at `n` + 1 stations from the foot (tangent to
## the ground) to the lip `len` metres on at height `h`.
static func arc_profile(len: float, h: float, n: int) -> Array:
	var th := 2.0 * atan(h / len)
	var r := len / sin(th)
	var out: Array = []
	for i in n + 1:
		var a := th * float(i) / float(n)
		out.append([r * sin(a), r * (1.0 - cos(a)), a])
	return out


## A deck surface along a profile ([z, y, ...] stations), across x0..x1, facing up (its normal from
## the slope), kind `k`. UV: u = x, v = the distance along the surface.
static func deck(g: LandmarkGeo, prof: Array, x0: float, x1: float, col: Color, collide := true) -> void:
	var v := 0.0
	for i in prof.size() - 1:
		var a: Array = prof[i]
		var b: Array = prof[i + 1]
		var za: float = a[0]
		var ya: float = a[1]
		var zb: float = b[0]
		var yb: float = b[1]
		var seg := Vector2(zb - za, yb - ya).length()
		var na := _up_normal(prof, i)
		var nb := _up_normal(prof, i + 1)
		g.quad_n(S, Vector3(x0, ya, za), Vector3(x1, ya, za), Vector3(x1, yb, zb), Vector3(x0, yb, zb), na, na, nb, nb,
			Vector2(x0, v), Vector2(x1, v), Vector2(x1, v + seg), Vector2(x0, v + seg), col, collide)
		v += seg


static func _up_normal(prof: Array, i: int) -> Vector3:
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 1, prof.size() - 1)
	var dz := float(prof[i1][0]) - float(prof[i0][0])
	var dy := float(prof[i1][1]) - float(prof[i0][1])
	return Vector3(0.0, dz, -dy).normalized()


## A side cheek under a profile at x = `x`, facing `out` (+1 / -1 in x), from `y0` up to the
## profile less `band` (where a hazard band of that height runs along the top).
static func cheek(g: LandmarkGeo, prof: Array, x: float, out: float, y0: float, col: Color, band: float, collide := true) -> void:
	var n := Vector3(out, 0.0, 0.0)
	for i in prof.size() - 1:
		var za: float = prof[i][0]
		var ya: float = prof[i][1]
		var zb: float = prof[i + 1][0]
		var yb: float = prof[i + 1][1]
		var ta := maxf(ya - band, y0)
		var tb := maxf(yb - band, y0)
		if maxf(ta, tb) > y0 + 0.002:
			g.quad(S, Vector3(x, y0, za), Vector3(x, ta, za), Vector3(x, tb, zb), Vector3(x, y0, zb), n,
				Vector2(za, y0), Vector2(za, ta), Vector2(zb, tb), Vector2(zb, y0), col, collide)
		if band > 0.0 and maxf(ya - ta, yb - tb) > 0.002:
			g.quad(S, Vector3(x, ta, za), Vector3(x, ya, za), Vector3(x, yb, zb), Vector3(x, tb, zb), n,
				Vector2(za, ta), Vector2(za, ya), Vector2(zb, yb), Vector2(zb, tb), c(Color.WHITE, K_HAZARD), collide)


# --- The kicker ----------------------------------------------------------------------------------

## A steel kicker `len` long rising to `h` at its lip, `w` wide, its cheeks in `paint`.
static func kicker(len: float, h: float, w: float, paint: Color) -> Array:
	var key := "kicker_%.2f_%.2f_%.2f_%s" % [len, h, w, paint.to_html(false)]
	return _cached(key, _make_kicker.bind(len, h, w, paint))


static func _make_kicker(len: float, h: float, w: float, paint: Color) -> Array:
	var g := _geo()
	var prof := arc_profile(len, h, 14)
	var hw := w * 0.5
	var plate := c(Color.WHITE, K_PLATE)
	var pc := c(paint, K_PAINT)
	var t := 0.012
	deck(g, prof, -hw + 0.04, hw - 0.04, plate)
	# The plate's edge strips and the cheeks (painted, a hazard band along the top).
	for sx: float in [-1.0, 1.0]:
		cheek(g, prof, sx * hw, sx, 0.0, pc, 0.16)
		# The cheek's top cap: a flat steel strip on edge.
		var capped: Array = []
		for p: Array in prof:
			capped.append([p[0], float(p[1]) + t, p[2]])
		deck(g, capped, (sx * hw) - 0.04 if sx > 0.0 else sx * hw, sx * hw if sx > 0.0 else sx * hw + 0.04, pc, false)
	# The lip bar across the top edge.
	var lip: Array = prof[prof.size() - 1]
	bar(g, Vector3(-hw, float(lip[1]) - 0.03, float(lip[0]) - 0.02), Vector3(hw, float(lip[1]) - 0.03, float(lip[0]) - 0.02), 0.045, c(Color.WHITE, K_COPING), 8, true)
	# The back: posts at the corners and the middle, a top beam, a diagonal brace, a bottom rail.
	var zb: float = lip[0] - 0.06
	var galv := c(paint.darkened(0.25), K_PAINT)
	for x: float in [-hw + 0.06, 0.0, hw - 0.06]:
		member(g, Vector3(x, 0.0, zb), Vector3(x, h - 0.04, zb), 0.08, galv)
	member(g, Vector3(-hw + 0.06, h - 0.07, zb), Vector3(hw - 0.06, h - 0.07, zb), 0.09, galv)
	member(g, Vector3(-hw + 0.06, 0.06, zb), Vector3(hw - 0.06, 0.06, zb), 0.07, galv)
	member(g, Vector3(-hw + 0.1, 0.1, zb), Vector3(-0.05, h - 0.12, zb), 0.06, galv)
	member(g, Vector3(hw - 0.1, 0.1, zb), Vector3(0.05, h - 0.12, zb), 0.06, galv)
	# Stringers under the plate (seen through the open back), every third of the width.
	for x: float in [-hw * 0.33, hw * 0.33]:
		var under: Array = []
		for p: Array in prof:
			under.append(Vector3(x, maxf(float(p[1]) - 0.09, 0.0), p[0]))
		for i in under.size() - 1:
			member(g, under[i], under[i + 1], 0.07, galv)
	# Rubber feet.
	for x: float in [-hw + 0.15, hw - 0.15]:
		for z: float in [0.6, zb - 0.1]:
			g.box(S, Vector3(x, 0.02, z), Vector3(0.24, 0.04, 0.3), c(Color.BLACK, K_RUBBER))
	# Collision-only back plane (cars must not drive under it from behind).
	g.collision.append_array(PackedVector3Array([Vector3(-hw, 0.0, zb), Vector3(hw, 0.0, zb), Vector3(hw, h, zb),
		Vector3(-hw, 0.0, zb), Vector3(hw, h, zb), Vector3(-hw, h, zb)]))
	return _finish(g)


# --- The freeway pair ----------------------------------------------------------------------------

## The launch kicker: a plated deck on a framed truss, guard rails, `len` x `h` x `w`.
static func launch(len: float, h: float, w: float, paint: Color) -> Array:
	var key := "launch_%.2f_%.2f_%.2f_%s" % [len, h, w, paint.to_html(false)]
	return _cached(key, func() -> Array:
		var prof := arc_profile(len, h, 22)
		return _framed(prof, w, paint, true))


## The landing: from a flat top `h` high (a 3 m knuckle) down over `len` to the ground.
static func landing(len: float, h: float, w: float, paint: Color) -> Array:
	var key := "landing_%.2f_%.2f_%.2f_%s" % [len, h, w, paint.to_html(false)]
	return _cached(key, func() -> Array:
		var prof: Array = []
		var n := 22
		var top := 3.0
		prof.append([0.0, h, 0.0])
		for i in n + 1:
			var t := float(i) / float(n)
			# Convex over the knuckle, straight, then a concave run-out tangent to the ground.
			var e := t * t * (3.0 - 2.0 * t)
			prof.append([top + t * len, h * (1.0 - lerpf(t, e, 0.65)), 0.0])
		return _framed(prof, w, paint, false))


## A framed ramp on profile `prof`: plate deck, columns every bay to the deck, ties across and X
## bracing on both sides, guard rails, a closed end (the launch's tall back, the landing's front).
static func _framed(prof: Array, w: float, paint: Color, launch_side: bool) -> Array:
	var g := _geo()
	var hw := w * 0.5
	var plate := c(Color.WHITE, K_PLATE)
	var frame := c(Color.WHITE, K_GALV)
	var rail := c(paint, K_PAINT)
	deck(g, prof, -hw, hw, plate)
	# The deck's skin: a 0.25 m fascia down each edge, painted, a hazard band on it.
	for sx: float in [-1.0, 1.0]:
		var fascia: Array = []
		for p: Array in prof:
			fascia.append([p[0], p[1], p[2]])
		var lower: Array = []
		for p: Array in prof:
			lower.append([p[0], maxf(float(p[1]) - 0.32, 0.0), p[2]])
		for i in prof.size() - 1:
			var za: float = prof[i][0]
			var zb: float = prof[i + 1][0]
			var ya: float = prof[i][1]
			var yb: float = prof[i + 1][1]
			var la: float = lower[i][1]
			var lb: float = lower[i + 1][1]
			if maxf(ya - la, yb - lb) < 0.01:
				continue
			g.quad(S, Vector3(sx * hw, la, za), Vector3(sx * hw, ya, za), Vector3(sx * hw, yb, zb), Vector3(sx * hw, lb, zb),
				Vector3(sx, 0.0, 0.0), Vector2(za, la), Vector2(za, ya), Vector2(zb, yb), Vector2(zb, lb), c(Color.WHITE, K_HAZARD))
	# Bays every ~2 m along: three columns across (edges and middle) from the ground to the deck.
	var z_end: float = prof[prof.size() - 1][0]
	var z_start: float = prof[0][0]
	var bays := maxi(2, int((z_end - z_start) / 2.0))
	var cols: Array = []
	for b in bays + 1:
		var z := lerpf(z_start, z_end, float(b) / float(bays))
		var y := _y_at(prof, z) - 0.33
		if y < 0.35:
			cols.append([z, 0.0])
			continue
		cols.append([z, y])
		for x: float in [-hw + 0.12, 0.0, hw - 0.12]:
			member(g, Vector3(x, 0.0, z), Vector3(x, y, z), 0.14, frame)
			g.box(S, Vector3(x, 0.03, z), Vector3(0.42, 0.06, 0.42), frame)
		# A tie across under the deck and one half way down.
		member(g, Vector3(-hw + 0.12, y, z), Vector3(hw - 0.12, y, z), 0.12, frame)
		if y > 2.0:
			member(g, Vector3(-hw + 0.12, y * 0.5, z), Vector3(hw - 0.12, y * 0.5, z), 0.09, frame)
	# X bracing in every bay on both sides, and a runner along the ground.
	for i in cols.size() - 1:
		var za: float = cols[i][0]
		var zb: float = cols[i + 1][0]
		var ya: float = cols[i][1]
		var yb: float = cols[i + 1][1]
		if minf(ya, yb) < 0.6:
			continue
		for sx: float in [-1.0, 1.0]:
			var x := sx * (hw - 0.12)
			member(g, Vector3(x, 0.15, za), Vector3(x, yb - 0.1, zb), 0.07, frame)
			member(g, Vector3(x, 0.15, zb), Vector3(x, ya - 0.1, za), 0.07, frame)
			member(g, Vector3(x, 0.08, za), Vector3(x, 0.08, zb), 0.09, frame)
	# Guard rails: posts every 2 m, a top and a mid rail, along both edges.
	for sx: float in [-1.0, 1.0]:
		var x := sx * (hw - 0.05)
		var tops: Array = []
		var mids: Array = []
		var n := maxi(2, int((z_end - z_start) / 2.0))
		for i in n + 1:
			var z := lerpf(z_start + 0.1, z_end - 0.1, float(i) / float(n))
			var y := _y_at(prof, z)
			member(g, Vector3(x, y, z), Vector3(x, y + 1.05, z), 0.06, rail)
			tops.append(Vector3(x, y + 1.05, z))
			mids.append(Vector3(x, y + 0.55, z))
		for i in tops.size() - 1:
			member(g, tops[i], tops[i + 1], 0.07, rail)
			member(g, mids[i], mids[i + 1], 0.05, rail)
		# The rail is a wall to a car (collision only: a 1.05 m skin along the edge).
		for i in tops.size() - 1:
			var a: Vector3 = tops[i]
			var b: Vector3 = tops[i + 1]
			g.collision.append_array(PackedVector3Array([a - Vector3(0, 1.05, 0), b - Vector3(0, 1.05, 0), b,
				a - Vector3(0, 1.05, 0), b, a]))
	# The closed end: the launch's back, the landing's front, as a braced panel and a collision wall.
	var z0: float = z_end if launch_side else z_start
	var h0 := _y_at(prof, z0)
	g.quad(S, Vector3(-hw, 0.0, z0), Vector3(hw, 0.0, z0), Vector3(hw, h0, z0), Vector3(-hw, h0, z0),
		Vector3(0.0, 0.0, 1.0 if launch_side else -1.0), Vector2(-hw, 0.0), Vector2(hw, 0.0), Vector2(hw, h0), Vector2(-hw, h0),
		c(paint.darkened(0.15), K_PAINT), true)
	# Collision skins down the sides under the deck (the frame is not a place to park a car).
	for sx: float in [-1.0, 1.0]:
		for i in prof.size() - 1:
			var za: float = prof[i][0]
			var zb: float = prof[i + 1][0]
			var ya: float = prof[i][1]
			var yb: float = prof[i + 1][1]
			g.collision.append_array(PackedVector3Array([Vector3(sx * hw, 0.0, za), Vector3(sx * hw, ya, za), Vector3(sx * hw, yb, zb),
				Vector3(sx * hw, 0.0, za), Vector3(sx * hw, yb, zb), Vector3(sx * hw, 0.0, zb)]))
	return _finish(g)


static func _y_at(prof: Array, z: float) -> float:
	for i in prof.size() - 1:
		var za: float = prof[i][0]
		var zb: float = prof[i + 1][0]
		if z >= za - 1e-4 and z <= zb + 1e-4:
			var t := 0.0 if zb - za < 1e-5 else (z - za) / (zb - za)
			return lerpf(float(prof[i][1]), float(prof[i + 1][1]), clampf(t, 0.0, 1.0))
	return float(prof[prof.size() - 1][1]) if z > float(prof[0][0]) else float(prof[0][1])


# --- The river's quarter-pipe --------------------------------------------------------------------

## A concrete quarter-pipe `len` wide (x), radius `r` to `angle` degrees, a deck `deck` deep behind
## the coping running back into a bank of `slope` : 1, its foot `drop` over the lowest bed under it.
static func qpipe(len: float, r: float, angle: float, deck_m: float, slope: float) -> Array:
	var key := "qp_%.2f_%.2f_%.2f_%.2f_%.2f" % [len, r, angle, deck_m, slope]
	return _cached(key, func() -> Array:
		var g := _geo()
		var hw := len * 0.5
		var a := deg_to_rad(angle)
		var n := 18
		var prof: Array = []
		for i in n + 1:
			var t := a * float(i) / float(n)
			prof.append([r * sin(t), r * (1.0 - cos(t)), t])
		var conc := c(Color.WHITE, K_CONCRETE)
		var top: Array = prof[prof.size() - 1]
		var zt: float = top[0]
		var ht: float = top[1]
		# A short flat apron at the foot, flush with the bed.
		g.quad(S, Vector3(-hw, 0.0, -0.8), Vector3(hw, 0.0, -0.8), Vector3(hw, 0.0, 0.0), Vector3(-hw, 0.0, 0.0), Vector3.UP,
			Vector2(-hw, -0.8), Vector2(hw, -0.8), Vector2(hw, 0.0), Vector2(-hw, 0.0), conc, true)
		deck(g, prof, -hw, hw, conc)
		# The deck: flat from the coping back until it meets the bank (slope : 1 from the toe,
		# which is just behind the top of the transition).
		var back := zt + maxf(deck_m, ht * slope + 0.3)
		g.quad(S, Vector3(-hw, ht, zt + 0.12), Vector3(hw, ht, zt + 0.12), Vector3(hw, ht, back), Vector3(-hw, ht, back), Vector3.UP,
			Vector2(-hw, zt), Vector2(hw, zt), Vector2(hw, back), Vector2(-hw, back), conc, true)
		# The coping, flush with the deck and proud of the face.
		bar(g, Vector3(-hw, ht - 0.03, zt + 0.04), Vector3(hw, ht - 0.03, zt + 0.04), 0.06, c(Color.WHITE, K_COPING), 10, true)
		g.box(S, Vector3(0.0, ht - 0.005, zt + 0.08), Vector3(len, 0.01, 0.14), c(Color.WHITE, K_COPING))
		# Side walls: the profile, then the deck, down to below the bed.
		var walls: Array = prof.duplicate()
		walls.append([zt + 0.12, ht, 0.0])
		walls.append([back, ht, 0.0])
		for sx: float in [-1.0, 1.0]:
			cheek(g, walls, sx * hw, sx, -0.5, conc, 0.0)
			# The wall's top edge: a 0.2 m concrete cap.
		# The back face down into the bank (hidden in it but closed against the sky behind).
		g.quad(S, Vector3(-hw, -0.5, back), Vector3(hw, -0.5, back), Vector3(hw, ht, back), Vector3(-hw, ht, back), Vector3(0, 0, 1),
			Vector2(-hw, -0.5), Vector2(hw, -0.5), Vector2(hw, ht), Vector2(-hw, ht), conc)
		return _finish(g))


# --- The loop ------------------------------------------------------------------------------------

## A loop of radius `r`, track `w` wide, shifting `shift` sideways over the turn, `run` metres of
## apron in and out; `paint` on the rails and towers. A negative `shift` shifts to -X.
static func loop(r: float, w: float, shift: float, run: float, paint: Color) -> Array:
	var key := "loop_%.2f_%.2f_%.2f_%.2f_%s" % [r, w, shift, run, paint.to_html(false)]
	return _cached(key, _make_loop.bind(r, w, shift, run, paint))


## The loop's centre line at angle `phi` (0 at the bottom of the entry, TAU at the exit): the
## track rises ahead (+Z), goes over the top and comes down behind, shifting `shift` in x.
static func loop_point(r: float, shift: float, phi: float) -> Vector3:
	var t := phi / TAU
	var x := shift * (t - sin(TAU * t) / TAU)
	return Vector3(x, r - r * cos(phi), r * sin(phi))


## Unit normal of the riding surface at `phi` (toward the loop's axis).
static func loop_normal(phi: float) -> Vector3:
	return Vector3(0.0, cos(phi), -sin(phi))


static func _make_loop(r: float, w: float, shift: float, run: float, paint: Color) -> Array:
	var g := _geo()
	var hw := w * 0.5
	var plate := c(Color.WHITE, K_PLATE)
	var pc := c(paint, K_PAINT)
	var galv := c(Color.WHITE, K_GALV)
	var n := 64
	var lift := 0.03
	var th := 0.14
	var rail := 0.5
	# The track: riding surface (inside), the plate's back (outside), and the rails at both edges.
	var v := 0.0
	for i in n:
		var p0 := TAU * float(i) / float(n)
		var p1 := TAU * float(i + 1) / float(n)
		var c0 := loop_point(r, shift, p0)
		var c1 := loop_point(r, shift, p1)
		var n0 := loop_normal(p0)
		var n1 := loop_normal(p1)
		c0 += n0 * lift
		c1 += n1 * lift
		var seg := c0.distance_to(c1)
		var x0 := Vector3(hw, 0, 0)
		g.quad_n(S, c0 - x0, c0 + x0, c1 + x0, c1 - x0, n0, n0, n1, n1,
			Vector2(-hw, v), Vector2(hw, v), Vector2(hw, v + seg), Vector2(-hw, v + seg), plate, true)
		g.quad_n(S, c0 - x0 - n0 * th, c0 + x0 - n0 * th, c1 + x0 - n1 * th, c1 - x0 - n1 * th, -n0, -n0, -n1, -n1,
			Vector2(-hw, v), Vector2(hw, v), Vector2(hw, v + seg), Vector2(-hw, v + seg), pc)
		for sx: float in [-1.0, 1.0]:
			var e0 := c0 + x0 * sx
			var e1 := c1 + x0 * sx
			var o := Vector3(sx, 0.0, 0.0)
			# Rail: from the plate's back up `rail` over the riding surface, both faces, a cap.
			g.quad(S, e0 - n0 * th, e0 + n0 * rail, e1 + n1 * rail, e1 - n1 * th, o, Vector2(v, -th), Vector2(v, rail), Vector2(v + seg, rail), Vector2(v + seg, -th), pc, true)
			g.quad(S, e0 - o * 0.06 - n0 * 0.0, e0 - o * 0.06 + n0 * rail, e1 - o * 0.06 + n1 * rail, e1 - o * 0.06, -o,
				Vector2(v, 0.0), Vector2(v, rail), Vector2(v + seg, rail), Vector2(v + seg, 0.0), c(Color.WHITE, K_HAZARD))
			g.quad(S, e0 + n0 * rail, e0 - o * 0.06 + n0 * rail, e1 - o * 0.06 + n1 * rail, e1 + n1 * rail, n0 + n1,
				Vector2(v, 0.0), Vector2(v, 0.06), Vector2(v + seg, 0.06), Vector2(v + seg, 0.0), pc)
		v += seg
	# The aprons: the entry lane at x = 0 and the exit at x = shift, plated, with a bevelled nose.
	for lane: Array in [[0.0, -run, 0.0], [shift, 0.0, run]]:
		var x: float = lane[0]
		var za: float = lane[1]
		var zb: float = lane[2]
		var nose := za if za < 0.0 else zb
		var far := zb if za < 0.0 else za
		g.quad(S, Vector3(x - hw, lift, far), Vector3(x + hw, lift, far), Vector3(x + hw, lift, nose - signf(nose) * 0.6), Vector3(x - hw, lift, nose - signf(nose) * 0.6),
			Vector3.UP, Vector2(-hw, za), Vector2(hw, za), Vector2(hw, zb), Vector2(-hw, zb), plate, true)
		g.quad(S, Vector3(x - hw, lift, nose - signf(nose) * 0.6), Vector3(x + hw, lift, nose - signf(nose) * 0.6), Vector3(x + hw, 0.0, nose), Vector3(x - hw, 0.0, nose),
			Vector3(0.0, 1.0, signf(nose) * 0.05), Vector2(-hw, 0.0), Vector2(hw, 0.0), Vector2(hw, 0.6), Vector2(-hw, 0.6), c(Color.WHITE, K_HAZARD), true)
	# Columns under the climb and the descent (behind the track, outside the loop).
	for deg: float in [22.0, 36.0, 50.0, 64.0, 296.0, 310.0, 324.0, 338.0]:
		var phi := deg_to_rad(deg)
		var cp := loop_point(r, shift, phi) - loop_normal(phi) * (th + 0.05)
		for sx: float in [-1.0, 1.0]:
			var x := cp.x + sx * (hw - 0.25)
			member(g, Vector3(x, 0.0, cp.z), Vector3(x, cp.y, cp.z), 0.16, galv, true)
			g.box(S, Vector3(x, 0.03, cp.z), Vector3(0.5, 0.06, 0.5), galv)
		member(g, Vector3(cp.x - hw + 0.25, cp.y * 0.5, cp.z), Vector3(cp.x + hw - 0.25, cp.y * 0.5, cp.z), 0.1, galv)
	# Two lattice towers outside the track's sides, at the loop's middle, with arms to the upper half.
	var tower_h := 2.0 * r + 1.6
	for sx: float in [-1.0, 1.0]:
		var tx := (minf(shift, 0.0) - hw - 1.3) if sx < 0.0 else (maxf(shift, 0.0) + hw + 1.3)
		var legs: Array[Vector3] = []
		for lx: float in [-0.55, 0.55]:
			for lz: float in [-0.55, 0.55]:
				legs.append(Vector3(tx + lx, 0.0, lz))
				member(g, Vector3(tx + lx, 0.0, lz), Vector3(tx + lx * 0.7, tower_h, lz * 0.7), 0.13, galv, true)
				g.box(S, Vector3(tx + lx, 0.03, lz), Vector3(0.45, 0.06, 0.45), galv)
		# Rungs and diagonals every 1.6 m.
		var y := 0.0
		while y < tower_h - 0.5:
			var y1 := minf(y + 1.6, tower_h)
			var f0 := 1.0 - 0.3 * y / tower_h
			var f1 := 1.0 - 0.3 * y1 / tower_h
			var ring0: Array[Vector3] = []
			var ring1: Array[Vector3] = []
			for q: Vector2 in [Vector2(-0.55, -0.55), Vector2(0.55, -0.55), Vector2(0.55, 0.55), Vector2(-0.55, 0.55)]:
				ring0.append(Vector3(tx + q.x * f0, y, q.y * f0))
				ring1.append(Vector3(tx + q.x * f1, y1, q.y * f1))
			for k in 4:
				member(g, ring1[k], ring1[(k + 1) % 4], 0.06, galv)
				member(g, ring0[k], ring1[(k + 1) % 4], 0.05, galv)
			y = y1
		# Arms from the tower's head to the track's edge over the upper half.
		for deg: float in [115.0, 150.0, 180.0, 210.0, 245.0]:
			var phi := deg_to_rad(deg)
			var cp := loop_point(r, shift, phi) - loop_normal(phi) * th
			var edge := Vector3(cp.x + sx * (hw + 0.05), cp.y, cp.z)
			var head := Vector3(tx, minf(cp.y + 0.6, tower_h - 0.2), clampf(cp.z * 0.35, -0.4, 0.4))
			member(g, head, edge, 0.12, pc)
		# A red beacon on top.
		g.box(S, Vector3(tx, tower_h + 0.12, 0.0), Vector3(0.5, 0.24, 0.5), pc)
	return _finish(g)


# --- Dirt jumps ----------------------------------------------------------------------------------

## The height of a dirt line's jumps at (x across, z along) in the line's frame.
static func dirt_height(jumps: Array, w: float, x: float, z: float) -> float:
	var best := 0.0
	for j: Array in jumps:
		var v0: float = j[0]
		var take: float = j[1]
		var table: float = j[2]
		var land: float = j[3]
		var h: float = j[4]
		var t := z - v0
		if t <= 0.0 or t >= take + table + land:
			continue
		var y := 0.0
		if t < take:
			# The takeoff: a circular arc, tangent to the ground, steepening to the lip.
			var th := 2.0 * atan(h / take)
			var r := take / sin(th)
			y = r - sqrt(maxf(r * r - t * t, 0.0))
		elif t < take + table:
			y = h
		else:
			var u := (t - take - table) / land
			y = h * (1.0 - u * u * (3.0 - 2.0 * u))
		# The sides fall away at about 40 degrees from the shoulders.
		var side := maxf(h * 1.2, 0.6)
		var edge := w * 0.5 + side - absf(x)
		y = minf(y, maxf(edge, 0.0) / side * y if edge < side else y)
		best = maxf(best, y)
	return best


## A dirt line's mesh in its frame, its heights over `ground` (a Callable(local x, z) -> local y).
static func dirt(jumps: Array, w: float, ground: Callable, tint: Color) -> Array:
	var g := _geo()
	var col := c(tint, K_DIRT)
	var hx := w * 0.5 + 2.4
	var dx := 0.4
	var dz := 0.35
	for j: Array in jumps:
		var z0: float = float(j[0]) - 0.6
		var z1: float = float(j[0]) + float(j[1]) + float(j[2]) + float(j[3]) + 0.6
		var nx := int(ceil(hx * 2.0 / dx))
		var nz := int(ceil((z1 - z0) / dz))
		var pts: Array = []
		for iz in nz + 1:
			var row: Array = []
			for ix in nx + 1:
				var x := -hx + hx * 2.0 * float(ix) / float(nx)
				var z := z0 + (z1 - z0) * float(iz) / float(nz)
				var h := dirt_height(jumps, w, x, z)
				# The edge ring sinks a hand under the ground, so no seam shows.
				var sink := -0.04 if (ix == 0 or iz == 0 or ix == nx or iz == nz) else 0.015
				row.append(Vector3(x, float(ground.call(x, z)) + h + sink, z))
			pts.append(row)
		for iz in nz:
			for ix in nx:
				var a: Vector3 = pts[iz][ix]
				var b: Vector3 = pts[iz][ix + 1]
				var cc: Vector3 = pts[iz + 1][ix + 1]
				var d: Vector3 = pts[iz + 1][ix]
				var na := _grid_normal(pts, ix, iz)
				var nb := _grid_normal(pts, ix + 1, iz)
				var nc := _grid_normal(pts, ix + 1, iz + 1)
				var nd := _grid_normal(pts, ix, iz + 1)
				g.quad_n(S, a, b, cc, d, na, nb, nc, nd, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(cc.x, cc.z), Vector2(d.x, d.z), col, true)
	return _finish(g)


static func _grid_normal(pts: Array, ix: int, iz: int) -> Vector3:
	var nz := pts.size() - 1
	var nx := (pts[0] as Array).size() - 1
	var l: Vector3 = pts[iz][maxi(ix - 1, 0)]
	var r: Vector3 = pts[iz][mini(ix + 1, nx)]
	var d: Vector3 = pts[maxi(iz - 1, 0)][ix]
	var u: Vector3 = pts[mini(iz + 1, nz)][ix]
	return (u - d).cross(r - l).normalized()
