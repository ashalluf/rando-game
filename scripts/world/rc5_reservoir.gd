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
##   stops, a half-octagon concrete balcony on the bench in the dam's own dress (its pierced
##   balustrade panels, posts and coping), a bench. The refcam stands on it.
## - THE BANKS under the trail swelled into smooth green pillows along the lake: the bench was a
##   smoothstep blend that lifted the bank's own humps to the trail's height. It is graded now
##   (Reservoir._carve()): the bench, a steep rock fill down to the water and a 1:1 cut up the hill.
##   The chunks the trail runs through also sample their terrain finer (`tile_n()`): at 5-8 m a
##   vertex the bench fell between the vertices.
## - THE CHAPARRAL on the banks: HillScatter's clumps are smooth domes, which from across the lake
##   read as rows of green balloons; hill_scatter's `rc5_edge` tears their outline into lobes.
## - THE TRAIL was a flat pale ribbon with a boulder lying on it: decomposed granite now darker with
##   worn edges into the bank, a centre wear line, pebbles and rain runnels (reservoir_dam `trail2`);
##   RockBuild's scree keeps off the trail and the water like its outcrops (`scree_ok()`).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## The whole pass (`RC5_RESERVOIR=0` turns it off).
static var enabled: bool = OS.get_environment("RC5_RESERVOIR") != "0"

## The overlook: where on the trail (metres from the dam's middle, and the side it is on), its
## balcony's radius past the trail's lake edge, and how much fence it opens.
const OVERLOOK_DIST := 160.0
const OVERLOOK_R := 3.66
const OVERLOOK_OPEN := 4.4
## How far past the trail's lake edge the balcony's centre stands (it projects over the bank on its
## wall, so the water shows over the balustrade from its rail), and how deep the wall goes.
const OVERLOOK_OUT := 1.2
const WALL_DEPTH := 12.0
## The balcony's plinth and balustrade panel (m): 1.22 m to the top of the coping.
const PLINTH_H := 0.3
const PANEL_H := 0.8

## The trail's bench is graded (Reservoir._carve()): a 1:1 cut out to BANK_EASE past its edge and a
## FILL_GRADE fill (rise per metre: a rock-faced bank, no further into the lake than the old blend)
## out to FILL_EASE, both steeper after, nothing past BANK_REACH.
const BANK_EASE := 8.0
const FILL_GRADE := 2.0
const FILL_EASE := 3.0
const BANK_REACH := 14.0

## A FULL hill chunk the lake trail runs through samples its terrain this finely: at the usual 32 to
## 48 a side (5-8 m a vertex) the 3 m bench and its banks fell between the vertices and the lake
## side drew as rounded lumps whatever the carve said.
const TRAIL_TILE_N := 96

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
## of the dam's middle near OVERLOOK_DIST whose lake side faces the dam best.
static func overlook(res: Reservoir) -> Dictionary:
	if not enabled or res == null or res.trail.is_empty():
		return {}
	if _overlook_for == res:
		return _overlook
	_overlook_for = res
	_overlook = {}
	var mid := res.arc_point((res.dam_a0 + res.dam_a1) * 0.5, Reservoir.DAM_RADIUS)
	var best := INF
	var pick := {}
	for li in res.trail.size():
		var line: PackedVector2Array = res.trail[li]
		for k in range(4, line.size() - 4):
			var p := line[k]
			var d := p - mid
			# East of the dam's middle and upstream of it, looking back down the lake at it.
			if d.x < 40.0 or d.y > -80.0:
				continue
			var o := _lake_out(res, line, k)
			# Near OVERLOOK_DIST, and the balcony facing the dam (the trail square to the view).
			var score := absf(d.length() - OVERLOOK_DIST) + 160.0 * (1.0 - o.dot(-d.normalized()))
			if score < best:
				best = score
				pick = {"line": li, "k": k, "out": o}
	_overlook = pick
	if _overlook.is_empty():
		return _overlook
	var line2: PackedVector2Array = res.trail[int(_overlook.line)]
	var k2: int = _overlook.k
	var dir := (line2[mini(k2 + 1, line2.size() - 1)] - line2[maxi(k2 - 1, 0)]).normalized()
	var out: Vector2 = _overlook.out
	_overlook.at = line2[k2]
	_overlook.dir = dir
	_overlook.out = out
	_overlook.centre = line2[k2] + out * (1.5 + OVERLOOK_OUT)
	return _overlook


## The terrain tile's subdivisions for chunk `ch` (`n` what it would use).
static func tile_n(ch: CityChunk, n: int) -> int:
	if not enabled or ch.level != CityChunk.Level.FULL or ch.plan == null or ch.plan.macro == null:
		return n
	var res: Reservoir = ch.plan.macro.reservoir
	if res == null or res.trail.is_empty():
		return n
	var rect := ch.owned_rect()
	if not rect.intersects(Reservoir.BOX):
		return n
	for line in res.trail:
		for p in line:
			if rect.has_point(p):
				return maxi(n, TRAIL_TILE_N)
	return n


## The way from trail point k down to the lake (its normal on the lower side, over 6 m).
static func _lake_out(res: Reservoir, line: PackedVector2Array, k: int) -> Vector2:
	var dir := (line[mini(k + 1, line.size() - 1)] - line[maxi(k - 1, 0)]).normalized()
	var n := Vector2(-dir.y, dir.x)
	return n if res.macro.height_at(line[k] + n * 6.0) < res.macro.height_at(line[k] - n * 6.0) else -n


## True where the fence is left out for the overlook (a fence segment's midpoint).
static func fence_open(res: Reservoir, p: Vector2) -> bool:
	var o := overlook(res)
	if o.is_empty():
		return false
	return p.distance_to(o.centre) < OVERLOOK_OPEN


## The balcony, in the dam's own dress: a half octagon of concrete out from the trail's lake edge
## on a wall down into the bank, each side one of the crest's pierced balustrade panels on a plinth
## between posts under a coping (LandmarkReservoir's parapet, the same materials and sizes), the
## fence ending either side, and a bench against the uphill edge. Into ctx.geo ("dam" and "rail").
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
	var panel: float = float(ctx.get("panel", 2.35))
	var sides := 4
	# Each side's chord is one panel plus a post.
	var r := (panel + 0.45) / (2.0 * sin(PI / (2.0 * sides)))
	var trim := LandmarkReservoir._k(LandmarkReservoir.K_TRIM)
	var face := LandmarkReservoir._k(LandmarkReservoir.K_FACE, 0.5)
	var pts: Array[Vector2] = []
	for i in sides + 1:
		var th := PI * float(i) / float(sides)
		pts.append(c + along * cos(th) * r + out * sin(th) * r)
	var c3 := Vector3(c.x, y + 0.02, c.y)
	var y_foot := y - WALL_DEPTH
	# Lower than the crest's (1.75 m): an overlook is looked over. The panel's openings stop under
	# 0.7 m (reservoir_railing.gdshader's spring + half an opening), so a 0.8 m panel keeps them.
	var ph := PLINTH_H
	var rt := PANEL_H
	var yc := y + ph + rt
	var t := LandmarkReservoir.PARAPET_T
	for i in sides:
		var a := pts[i]
		var b := pts[i + 1]
		var m := (a + b) * 0.5 - c
		var w := Vector3(m.x, 0.0, m.y).normalized()
		var w2 := Vector2(w.x, w.z)
		var ua := float(i) * (panel + 0.45)
		var ub := ua + panel + 0.45
		var a_in := a - w2 * t
		var b_in := b - w2 * t
		var a_mid := a - w2 * t * 0.5
		var b_mid := b - w2 * t * 0.5
		# The deck (a fan), the wall into the bank and the plinth's outer face, its inner face, top.
		g.tri("dam", c3, Vector3(a.x, y + 0.02, a.y), Vector3(b.x, y + 0.02, b.y), Vector3.UP, Vector2(c.x, c.y), Vector2(a.x, a.y), Vector2(b.x, b.y), trim, true)
		g.quad("dam", Vector3(a.x, y_foot, a.y), Vector3(b.x, y_foot, b.y), Vector3(b.x, y + ph, b.y), Vector3(a.x, y + ph, a.y), w,
			Vector2(ua, y_foot), Vector2(ub, y_foot), Vector2(ub, y + ph), Vector2(ua, y + ph), face, true)
		g.quad("dam", Vector3(a_in.x, y, a_in.y), Vector3(b_in.x, y, b_in.y), Vector3(b_in.x, y + ph, b_in.y), Vector3(a_in.x, y + ph, a_in.y), -w,
			Vector2(ua, y), Vector2(ub, y), Vector2(ub, y + ph), Vector2(ua, y + ph), trim, true)
		g.quad("dam", Vector3(a_in.x, y + ph, a_in.y), Vector3(b_in.x, y + ph, b_in.y), Vector3(b.x, y + ph, b.y), Vector3(a.x, y + ph, a.y), Vector3.UP,
			Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, t), Vector2(ua, t), trim)
		# The pierced panel between the posts (half a post in from each corner).
		var dir := (b - a).normalized()
		var pa := a_mid + dir * 0.225
		var pb := b_mid - dir * 0.225
		g.quad("rail", Vector3(pa.x, y + ph, pa.y), Vector3(pb.x, y + ph, pb.y), Vector3(pb.x, yc, pb.y), Vector3(pa.x, yc, pa.y), w,
			Vector2(0.0, 0.0), Vector2(panel, 0.0), Vector2(panel, rt), Vector2(0.0, rt), Color(float(i % 7) * 0.13, 0.5, 0.0, 1.0), true)
		# The coping: outer and inner faces, top and soffit.
		var a_o := a + w2 * 0.06
		var b_o := b + w2 * 0.06
		var a_i := a_in - w2 * 0.06
		var b_i := b_in - w2 * 0.06
		for f in 2:
			var aa := a_o if f == 0 else a_i
			var bb := b_o if f == 0 else b_i
			g.quad("dam", Vector3(aa.x, yc - 0.02, aa.y), Vector3(bb.x, yc - 0.02, bb.y), Vector3(bb.x, yc + LandmarkReservoir.COPING_H, bb.y), Vector3(aa.x, yc + LandmarkReservoir.COPING_H, aa.y), w if f == 0 else -w,
				Vector2(ua, yc), Vector2(ub, yc), Vector2(ub, yc + 0.15), Vector2(ua, yc + 0.15), trim, true)
		g.quad("dam", Vector3(a_i.x, yc + LandmarkReservoir.COPING_H, a_i.y), Vector3(b_i.x, yc + LandmarkReservoir.COPING_H, b_i.y), Vector3(b_o.x, yc + LandmarkReservoir.COPING_H, b_o.y), Vector3(a_o.x, yc + LandmarkReservoir.COPING_H, a_o.y), Vector3.UP,
			Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 0.6), Vector2(ua, 0.6), trim, true)
		g.quad("dam", Vector3(a_i.x, yc - 0.02, a_i.y), Vector3(b_i.x, yc - 0.02, b_i.y), Vector3(b_o.x, yc - 0.02, b_o.y), Vector3(a_o.x, yc - 0.02, a_o.y), Vector3.DOWN,
			Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 0.6), Vector2(ua, 0.6), trim)
	# The posts at the corners, the end ones heavier where the fence meets them.
	for i in sides + 1:
		var p := pts[i] - (pts[i] - c).normalized() * t * 0.5
		var end := i == 0 or i == sides
		var sz := Vector3(0.6, rt + 0.3, 0.6) if end else Vector3(0.45, rt, 0.62)
		var yaw := atan2(-(pts[i] - c).x, -(pts[i] - c).y)
		g.box("dam", Vector3(p.x, y + ph + sz.y * 0.5, p.y), sz, trim, Basis(Vector3.UP, yaw), 0.03, true)
	# A bench on the uphill edge of the trail, facing the lake.
	var yaw_t := atan2(-along.x, -along.y)
	var metal := LandmarkReservoir._k(LandmarkReservoir.K_METAL)
	var bc: Vector2 = (o.at as Vector2) - out * 1.35
	var bb2 := Basis(Vector3.UP, yaw_t)
	for sgn: float in [-0.75, 0.75]:
		var leg := bc + along * sgn
		g.box("dam", Vector3(leg.x, y + 0.22, leg.y), Vector3(0.12, 0.44, 0.4), trim, bb2, 0.02)
	g.box("dam", Vector3(bc.x, y + 0.47, bc.y), Vector3(1.9, 0.07, 0.42), metal, bb2, 0.01, true)
