class_name Rc5Reservoir
## Lake Shallufer from its trail at 10:30 (refcam `reservoir_dam`, tools/refcams/cameras_w8.json;
## docs/HANDOFF.md "Lake Shallufer's dam from the lake trail"). What gave the view away, each behind
## one switch (`RC5_RESERVOIR=0` is the A/B: the reservoir exactly as before):
##
## - THE WATER read as a pale cyan swimming pool, not a mountain lake: the engine reflected its own
##   sky radiance on top of the shader's traced mirror (which already carries the sky and the ridge),
##   so on Compatibility every mirrored hill was washed out to the sky's colour. reservoir_water's
##   `rc5`: the engine's specular is off on Compatibility (the emitted mirror is the whole mirror),
##   and on Forward+ it is off only where the traced ray meets the ridge (so SSR and the sky radiance
##   still give the sky its due); the mirror gains the bathtub ring's pale band at the foot of every
##   mirrored hill, chaparral in the hill, and the dam's parapet and towers as a dark top band.
## - THE FENCE along the lake side of the trail was a cage of 25 cm diamonds right in front of the
##   lens: chain_link.gdshader's UV is metres along a ONE-metre panel that every instance stretches
##   to its length, so every fence in the city drew its 6 cm weave 2-3 times wider. `scale_uv` takes
##   the instance's own x scale back out (the material of LotFill.chain_link_panel(); the meshes that
##   borrow it are unscaled, so nothing else changes).
## - NO VIEW: the fence runs the whole trail, so nowhere on it does the lake open up. An OVERLOOK
##   (`overlook()`, pure) where the trail stands about 160 m off the dam on its east side: the fence
##   stops, a semicircular concrete balcony on the bench with a low parapet and a steel pipe rail, a
##   bench. The refcam stands on it.
## - THE TRAIL was a flat pale ribbon with a boulder lying on it: decomposed granite now darker with
##   worn edges into the bank, a centre wear line, pebbles and rain runnels (reservoir_dam `trail2`);
##   RockBuild's scree keeps off the trail and the water like its outcrops (`scree_ok()`).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## The whole pass (`RC5_RESERVOIR=0` turns it off).
static var enabled: bool = OS.get_environment("RC5_RESERVOIR") != "0"

## The overlook: where on the trail (metres from the dam's middle, and the side it is on), its
## balcony's radius past the trail's lake edge, and how much fence it opens.
const OVERLOOK_DIST := 160.0
const OVERLOOK_R := 3.2
const OVERLOOK_OPEN := 5.5
const PARAPET_H := 0.55
const RAIL_H := 1.07

static var _overlook_for: Reservoir = null
static var _overlook: Dictionary = {}


## The water material's switch, and what it mirrors of the dam: the two intake towers (where
## LandmarkReservoir._intake_tower() stands them: along the arc, off the face, the shaft's radius
## and the house's height) and the crest with its parapet.
static func water(m: ShaderMaterial, res: Reservoir) -> void:
	m.set_shader_parameter("rc5", 1.0 if enabled else 0.0)
	if res == null:
		return
	var towers := [[0.62, 24.0, 4.2, 4.8], [0.36, 15.0, 2.7, 3.4]]
	for i in 2:
		var t: Array = towers[i]
		var a := lerpf(res.dam_a0, res.dam_a1, float(t[0]))
		var c := res.arc_point(a, Reservoir.DAM_RADIUS + float(t[1]))
		# Base course (1 m over the crest), the house, the cornice: the dome sits on its top.
		var top := res.crest + 1.0 + 0.6 + float(t[3]) + 0.55 - res.level
		m.set_shader_parameter("tower_a" if i == 0 else "tower_b", Vector4(c.x, c.y, float(t[2]) + 0.45, top))
	m.set_shader_parameter("crest_over", res.crest - res.level)
	m.set_shader_parameter("parapet", LandmarkReservoir.PLINTH_H + LandmarkReservoir.RAIL_TOP + LandmarkReservoir.COPING_H)


## The chain-link material's weave by the instance's stretch.
static func fence(m: Material) -> void:
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("scale_uv", 1.0 if enabled else 0.0)


## The trail's look on the dam material.
static func dam(m: ShaderMaterial) -> void:
	m.set_shader_parameter("trail2", 1.0 if enabled else 0.0)


## False for a scree boulder that would land on the reservoir's water, bathtub ring, trail, dam or
## spillway (RockBuild's outcrops already ask; their scree did not).
static func scree_ok(ch: CityChunk, q: Vector2) -> bool:
	if not enabled or ch.plan.macro == null or ch.plan.macro.reservoir == null:
		return true
	return not ch.plan.macro.reservoir.keep_clear(q, ch._terrain_height(q))


## The overlook on `res`'s trail: {"line", "k", "at" (trail point), "out" (toward the lake),
## "centre" (the balcony's centre)}, or {} (no trail, or the pass off). Pure: the trail point east
## of the dam's middle whose distance to it is nearest OVERLOOK_DIST and that looks at the dam.
static func overlook(res: Reservoir) -> Dictionary:
	if not enabled or res == null or res.trail.is_empty():
		return {}
	if _overlook_for == res:
		return _overlook
	_overlook_for = res
	_overlook = {}
	var mid := res.arc_point((res.dam_a0 + res.dam_a1) * 0.5, Reservoir.DAM_RADIUS)
	var best := INF
	for li in res.trail.size():
		var line: PackedVector2Array = res.trail[li]
		for k in range(4, line.size() - 4):
			var p := line[k]
			var d := p - mid
			# East of the dam's middle and upstream of it, looking back down the lake at it.
			if d.x < 40.0 or d.y > -80.0:
				continue
			var score := absf(d.length() - OVERLOOK_DIST)
			if score < best:
				best = score
				_overlook = {"line": li, "k": k}
	if _overlook.is_empty():
		return _overlook
	var line2: PackedVector2Array = res.trail[int(_overlook.line)]
	var k2: int = _overlook.k
	var dir := (line2[mini(k2 + 1, line2.size() - 1)] - line2[maxi(k2 - 1, 0)]).normalized()
	var n := Vector2(-dir.y, dir.x)
	var hl := res.macro.height_at(line2[k2] + n * 6.0)
	var hr := res.macro.height_at(line2[k2] - n * 6.0)
	var out := n if hl < hr else -n
	_overlook.at = line2[k2]
	_overlook.dir = dir
	_overlook.out = out
	_overlook.centre = line2[k2] + out * 1.5
	return _overlook


## True where the fence is left out for the overlook (a fence segment's midpoint).
static func fence_open(res: Reservoir, p: Vector2) -> bool:
	var o := overlook(res)
	if o.is_empty():
		return false
	return p.distance_to(o.centre) < OVERLOOK_OPEN


## The balcony: a half disc of concrete out from the trail's lake edge on a battered wall down into
## the bank, a low parapet round it with a steel pipe rail on posts, two end piers where the fence
## stops and a bench against the uphill side. Into `g` ("dam" material; K_* of the dam shader).
static func build_overlook(ctx: Dictionary) -> void:
	var res: Reservoir = ctx.res
	var o := overlook(res)
	if o.is_empty():
		return
	var g: LandmarkGeo = ctx.geo
	var y := res.level + Reservoir.TRAIL_RISE + 0.07
	var c: Vector2 = o.centre
	var out: Vector2 = o.out
	var along: Vector2 = o.dir
	var r := OVERLOOK_R
	var segs := 14
	# Board-formed concrete like the dam's (not the smooth trim), a shade darker and warmer.
	var trim := Color(0.86, 0.5, 0.82, float(LandmarkReservoir.K_FACE) / 16.0)
	var face := Color(0.8, 1.0, 0.78, float(LandmarkReservoir.K_FACE) / 16.0)
	var metal := LandmarkReservoir._k(LandmarkReservoir.K_METAL)
	var pts: Array[Vector2] = []
	for i in segs + 1:
		var th := PI * float(i) / float(segs)
		pts.append(c + along * cos(th) * r + out * sin(th) * r)
	var c3 := Vector3(c.x, y + 0.02, c.y)
	var y_foot := y - 4.5
	for i in segs:
		var a := pts[i]
		var b := pts[i + 1]
		var a3 := Vector3(a.x, y + 0.02, a.y)
		var b3 := Vector3(b.x, y + 0.02, b.y)
		# The deck (a fan), its wall down into the bank, the parapet's two faces and top.
		g.tri("dam", c3, a3, b3, Vector3.UP, Vector2(c.x, c.y), Vector2(a.x, a.y), Vector2(b.x, b.y), trim, true)
		var m := (a + b) * 0.5 - c
		var w := Vector3(m.x, 0.0, m.y).normalized()
		var ua := float(i) * PI * r / float(segs)
		var ub := float(i + 1) * PI * r / float(segs)
		var a_in := c + (a - c) * ((r - 0.3) / r)
		var b_in := c + (b - c) * ((r - 0.3) / r)
		g.quad("dam", Vector3(a.x, y_foot, a.y), Vector3(b.x, y_foot, b.y), Vector3(b.x, y + PARAPET_H, b.y), Vector3(a.x, y + PARAPET_H, a.y), w,
			Vector2(ua, y_foot), Vector2(ub, y_foot), Vector2(ub, y + PARAPET_H), Vector2(ua, y + PARAPET_H), face, true)
		g.quad("dam", Vector3(a_in.x, y, a_in.y), Vector3(b_in.x, y, b_in.y), Vector3(b_in.x, y + PARAPET_H, b_in.y), Vector3(a_in.x, y + PARAPET_H, a_in.y), -w,
			Vector2(ua, y), Vector2(ub, y), Vector2(ub, y + PARAPET_H), Vector2(ua, y + PARAPET_H), trim, true)
		g.quad("dam", Vector3(a_in.x, y + PARAPET_H, a_in.y), Vector3(b_in.x, y + PARAPET_H, b_in.y), Vector3(b.x, y + PARAPET_H, b.y), Vector3(a.x, y + PARAPET_H, a.y), Vector3.UP,
			Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 0.3), Vector2(ua, 0.3), trim, true)
	# The pipe rail on posts over the parapet's middle line.
	var rail_y := y + RAIL_H
	for i in segs + 1:
		var p := c + (pts[i] - c) * ((r - 0.15) / r)
		if i % 2 == 0:
			g.cylinder("dam", Vector3(p.x, y + PARAPET_H, p.y), 0.024, RAIL_H - PARAPET_H, 6, metal)
		if i < segs:
			var q := c + (pts[i + 1] - c) * ((r - 0.15) / r)
			var mid := (p + q) * 0.5
			var l := p.distance_to(q) + 0.02
			var yaw := atan2(-(q - p).x, -(q - p).y)
			g.box("dam", Vector3(mid.x, rail_y, mid.y), Vector3(0.05, 0.05, l), metal, Basis(Vector3.UP, yaw), 0.0, true)
			g.box("dam", Vector3(mid.x, (rail_y + y + PARAPET_H) * 0.5 + 0.05, mid.y), Vector3(0.03, 0.03, l), metal, Basis(Vector3.UP, yaw))
	# End piers where the fence stops, and a bench on the uphill edge of the trail facing the lake.
	var yaw_t := atan2(-along.x, -along.y)
	for s: float in [-1.0, 1.0]:
		var e := c + along * s * (OVERLOOK_OPEN + 0.2) - out * 0.25
		g.box("dam", Vector3(e.x, y + 0.6, e.y), Vector3(0.45, 1.2, 0.45), trim, Basis(Vector3.UP, yaw_t), 0.03, true)
	var bc: Vector2 = (o.at as Vector2) - out * 1.35
	var bb := Basis(Vector3.UP, yaw_t)
	for s: float in [-0.75, 0.75]:
		var leg := bc + along * s
		g.box("dam", Vector3(leg.x, y + 0.22, leg.y), Vector3(0.12, 0.44, 0.4), trim, bb, 0.02)
	g.box("dam", Vector3(bc.x, y + 0.47, bc.y), Vector3(1.9, 0.07, 0.42), metal, bb, 0.01, true)
