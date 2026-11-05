class_name Rc5HillHome
## A hill home's pool deck at dusk (refcam `hill_home_dusk`, tools/refcams/cameras_w8.json;
## docs/HANDOFF.md "The hill home's pool deck at dusk"). What gave the 19:15 view from a cantilever
## house's pool deck over the basin away, each behind one switch (`RC5_HILL_HOME=0` is the A/B: the
## hill homes exactly as before):
##
## - THE ROOM behind the glass wall was a blown-out beige box: hill_glass.gdshader cut the open plan
##   into 4.6 m cells with a lit partition between every bay, which through the side glass at a
##   grazing look was a row of flat bright walls. `rc5`: one open room (no partitions), deeper, lit
##   by its downlights in pools with the dark between them, the walls scalloped, the back dimmer.
## - THE POOL was a flat neon slab of one turquoise. hill_pool.gdshader `rc5`: dark water lit by
##   lamps in its walls (`LAMP_PITCH`), the light falling off across the tank, the dusk sky mirrored
##   by its elevation and the lit glass wall beside it mirrored (its offset rides COLOR.b, written by
##   `pool_wall()`), the far edge a bright lip where the vanishing edge meets the view.
## - LIGHTS THAT LIT NOTHING: the lit glass and the glowing pool left the paving round them dark.
##   An additive spill (`shaders/rc5_hill_spill.gdshader`) lays the rooms' light on the terrace in
##   front of every lit ground-floor glass wall and the pool's on its coping and stone.
## - THE LOUNGERS were three grey boxes with a stick each: BackyardKit's chaise pair (frame, legs,
##   cushions with piping, a side table) on the stone, in an outdoor fabric (a hash).
## - A TERRACE OLIVE stood in front of the infinity pool, its crown across the view the pool is
##   built for: trees of the terraced garden under the pool's view span are left out (after their
##   rolls: every other tree keeps its place).

## The whole pass (`RC5_HILL_HOME=0` turns it off).
static var enabled: bool = OS.get_environment("RC5_HILL_HOME") != "0"

## How far a terrace tree keeps off the pool's u span (metres either side).
const VIEW_CLEAR := 2.5
## How deep the rooms' spill reaches out from the glass, and the pool's past its rim (metres).
const SPILL_DEPTH := 3.4
const POOL_SPILL := 1.5


## The hill glass and pool materials' switch (HillHomeKit.material()).
static func material(name: String, m: ShaderMaterial) -> void:
	if name == "hh_glass" or name == "hh_water":
		m.set_shader_parameter("rc5", 1.0 if enabled else 0.0)


## The spill material: additive, shadowless, lit by lamp_factor.
static var _spill: ShaderMaterial = null


static func spill_material() -> ShaderMaterial:
	if _spill == null:
		_spill = ShaderMaterial.new()
		_spill.shader = load("res://shaders/rc5_hill_spill.gdshader")
	return _spill


## Whether a terraced-garden tree at frame point `p` stands in the infinity pool's view (dropped).
static func blocks_view(h: Dictionary, p: Vector2) -> bool:
	if not enabled:
		return false
	var pl: Dictionary = h.pool
	if pl.is_empty():
		return false
	var r: Rect2 = pl.r
	return p.x > r.position.x - VIEW_CLEAR and p.x < r.end.x + VIEW_CLEAR


## The offset of the nearest lit glass wall beside the pool, along the pool's u (metres from the
## pool's u0 side, negative on that side, past its width on the other), packed for COLOR.b: 0 none.
## Only a ground-floor wing at the pad's level whose glass faces the pool counts, within 6 m.
static func pool_wall(h: Dictionary) -> float:
	if not enabled:
		return 0.0
	var pl: Dictionary = h.pool
	if pl.is_empty():
		return 0.0
	var r: Rect2 = pl.r
	var best := 99.0
	var off := 0.0
	for w: Dictionary in h.wings:
		if absf(float(w.y)) > 0.5 or (w.glass as Array).is_empty():
			continue
		var wr: Rect2 = w.r
		# The wing must stand beside the pool along v.
		if wr.end.y < r.position.y or wr.position.y > r.end.y:
			continue
		var d_lo := r.position.x - wr.end.x
		var d_hi := wr.position.x - r.end.x
		if d_lo >= 0.0 and d_lo < best:
			best = d_lo
			off = -d_lo
		if d_hi >= 0.0 and d_hi < best:
			best = d_hi
			off = r.size.x + d_hi
	if best > 6.0:
		return 0.0
	return clampf(0.5 + off / 40.0, 0.02, 0.98)


## A spill quad on `st` (the chunk's "hh_spill" surface): four world corners, a0..a1 the corners'
## metres along the source, from the source d0..d1 metres; the source's length and the reach.
static func spill_quad(st: SurfaceTool, p00: Vector3, p10: Vector3, p11: Vector3, p01: Vector3, a1: float, d0: float, d1: float, reach: float, cl: Color) -> void:
	var corners := [[p00, Vector2(0.0, d0)], [p10, Vector2(a1, d0)], [p11, Vector2(a1, d1)], [p00, Vector2(0.0, d0)], [p11, Vector2(a1, d1)], [p01, Vector2(0.0, d1)]]
	for c: Array in corners:
		st.set_normal(Vector3.UP)
		st.set_color(cl)
		st.set_uv(c[1])
		st.set_uv2(Vector2(a1, reach))
		st.add_vertex(c[0])


## Spill in front of a hill home's glass wall from frame a to b, normal n (outward), at the wing's
## level g: laid where the ground in front is the pad's paving or the cantilever's deck.
static func glass_spill(b: HillHomeBuild, a: Vector2, bb: Vector2, n: Vector2, y0: float) -> void:
	if not enabled or y0 > 0.6 or absf(b.g - b.g0) > 0.3:
		return
	var h: Dictionary = b.h
	var len := a.distance_to(bb)
	if len < 1.0:
		return
	var deck: Rect2 = h.deck
	var pad := Rect2(0.2, 0.2, b.Wp - 0.4, b.Dp - 0.4)
	var st := b._st("hh_spill")
	var steps := 4
	for k in steps:
		var d0 := SPILL_DEPTH * float(k) / steps + 0.08
		var d1 := SPILL_DEPTH * float(k + 1) / steps + 0.08
		var mid := (a + bb) * 0.5 + n * (d0 + d1) * 0.5
		var y := 0.0
		if deck.has_area() and deck.has_point(mid):
			y = b.g0 + 0.03
		elif pad.has_point(mid):
			y = b.top + 0.075
		else:
			continue
		var c := func(p: Vector2) -> Vector3: return b.WY(p.x, p.y, y)
		spill_quad(st, c.call(a + n * d0), c.call(bb + n * d0), c.call(bb + n * d1), c.call(a + n * d1), len, d0 - 0.08, d1 - 0.08, SPILL_DEPTH,
			Color(0.62, 0.42, 0.22, 0.55 + 0.2 * b._h([a.x, a.y, "spill"])))


## The pool's light on its coping and the stone round it (not the vanishing edge).
static func pool_spill(b: HillHomeBuild, r: Rect2, cop: float, infinity: bool) -> void:
	if not enabled:
		return
	var st := b._st("hh_spill")
	var cl := Color(0.10, 0.42, 0.44, 0.9)
	var top: float = b.top
	# Each edge: from the rim outward, the coping band then the stone. [start, end, outward normal]
	var u0 := r.position.x
	var u1 := r.end.x
	var v0 := r.position.y
	var v1 := r.end.y
	var edges := [[Vector2(u0, v0), Vector2(u1, v0), Vector2(0, -1)], [Vector2(u0, v1), Vector2(u0, v0), Vector2(-1, 0)], [Vector2(u1, v0), Vector2(u1, v1), Vector2(1, 0)]]
	if not infinity:
		edges.append([Vector2(u1, v1), Vector2(u0, v1), Vector2(0, 1)])
	for e: Array in edges:
		var a: Vector2 = e[0]
		var bb: Vector2 = e[1]
		var n: Vector2 = e[2]
		var len := a.distance_to(bb)
		for band: Array in [[0.0, cop, top + 0.165], [cop, POOL_SPILL, top + 0.067]]:
			var d0: float = band[0]
			var d1: float = band[1]
			var y: float = band[2]
			spill_quad(st, b.WY(a.x + n.x * d0, a.y + n.y * d0, y), b.WY(bb.x + n.x * d0, bb.y + n.y * d0, y),
				b.WY(bb.x + n.x * d1, bb.y + n.y * d1, y), b.WY(a.x + n.x * d1, a.y + n.y * d1, y), len, d0, d1, POOL_SPILL, cl)


## BackyardKit's chaise pair (frame, cushions, side table) by the pool, feet toward it; replaces the
## old three boxes. Returns false with the pass off (the old loungers then).
static func loungers(b: HillHomeBuild, r: Rect2) -> bool:
	if not enabled:
		return false
	var h: Dictionary = b.h
	var pairs := 2 if r.size.x > 6.4 else 1
	var lv := r.position.y - 1.3
	if lv - 1.0 < float(h.vh):
		return true
	var fabric := absi(hash([b.ps, b.seed, "rc5_fabric"])) % 8
	var paint := Color(0.16, 0.15, 0.14) if b._h(["rc5_frame"]) < 0.6 else Color(0.86, 0.85, 0.82)
	for k in pairs:
		var lu := lerpf(r.position.x, r.end.x, (float(k) + 0.5) / pairs)
		var p := b.WY(lu, lv, b.top + 0.06)
		# Mesh: feet toward -Z. -Z is the pool's way (+v).
		var zf := -Vector3(b.fv.x, 0.0, b.fv.y)
		var xf := Transform3D(Basis(Vector3.UP.cross(zf).normalized(), Vector3.UP, zf), p)
		b._badd("by_loungers", BackyardKit.get_mesh("loungers"), xf, Color.WHITE, Color(paint.r, paint.g, paint.b, float(fabric) / 8.0 + 0.01))
	return true
