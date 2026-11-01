class_name RockOutcrops
## Where the hills' real rock stands (RockKit's photoscanned cliffs and boulders), worked out
## from the very field the terrain paints its rock from (HillPlanting.ground(), the splat of
## terrain.gdshader), so a scanned crag stands where the ground under it is already painted rock.
##
## Three populations, every roll a hash of the seed and the place:
##  * TORS - crags 10-90 m across on the crests and the steepest faces, the ranges' silhouette
##    from the basin. Planned once for the whole map from the basin bake (MacroMap.bake_height:
##    height and drainage per texel), cached by LoadCache, drawn by RockFar at every distance
##    (one MultiMesh per kind per cell), collided with in FULL chunks.
##  * OUTCROPS - rock 2-12 m on the painted rock of a FULL hill chunk (a jittered grid off the
##    tile's own heights), with collision.
##  * BANK BOULDERS - boulders bedded in a hill road's cut banks and fallen to their toe.
## `ROCKS=0` in the environment turns all of it off (the A/B).

static var enabled: bool = OS.get_environment("ROCKS") != "0"

## Metres between tor candidates (one jittered candidate a cell).
const TOR_CELL := 58.0
## A candidate becomes a tor where the painted rock is at least this (HillPlanting's rocky).
const TOR_ROCKY := 0.34
## The odds a rocky candidate is a tor, and the extra odds on a crest (drain below CREST_DRAIN).
const TOR_ODDS := 0.55
const CREST_DRAIN := -0.3
const CREST_ODDS := 0.5
## The odds on a steep face (the bake's slope), whatever the paint says.
const STEEP_ODDS := 0.4
## A crest tor on the highest ground within this many metres is a summit crag.
const SUMMIT_REACH := 75.0
## Never under this elevation (the low foothills stay grass) and never within this of a road's
## edge, an estate pad, a landmark's radius or a tower.
const TOR_MIN_HEIGHT := 25.0
const TOR_ROAD_CLEAR := 14.0
## Outcrops in a FULL chunk: grid spacing, and the painted rock they need.
const OUTCROP_STEP := 11.0
const OUTCROP_ROCKY := 0.42
## Bank boulders: metres along a road between tries, and how high a cut bank must stand.
const BANK_STEP := 7.0
const BANK_MIN_CUT := 1.6

static var _tors_cache: Dictionary = {}
## The bake each seed's tors were planned from (a check may bake the same macro again at another
## size, and the city's tors stay what they were), and the one a plan in progress reads.
static var _bakes: Dictionary = {}
static var _img: Image = null


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## Every tor on the map: [{"id", "pos" Vector2, "y" (the origin's height: ground less the sink),
## "sink", "kind", "basis" Basis, "tone", "radius" (metres of footprint), "top" (metres over the
## ground)}]. Needs the basin bake (plan.macro.bake_height); empty without it.
static func tors(plan: CityPlan) -> Array:
	if not enabled or plan == null or plan.macro == null:
		return []
	var key := plan.seed
	if _tors_cache.has(key):
		return _tors_cache[key]
	var macro: MacroMap = plan.macro
	if macro.bake_height == null:
		return []
	var inputs := ["rock_tors", plan.seed, macro.bake_height.get_width(), TOR_CELL, TOR_ROCKY, TOR_ODDS, CREST_ODDS]
	var cached: Variant = LoadCache.load_data("rock_tors", inputs)
	var out: Array = []
	if cached is Array:
		out = cached
	else:
		out = _plan_tors(plan, macro.bake_height)
		LoadCache.save_data("rock_tors", inputs, out)
	_tors_cache[key] = out
	_bakes[key] = macro.bake_height
	return out


## The bake's height (metres) and drainage at a world XZ, bilinear.
## The bake the seed's tors were planned from (null before tors() ran for it).
static func bake_of(plan: CityPlan) -> Image:
	return _bakes.get(plan.seed)


static func _bake_at(macro: MacroMap, p: Vector2, span: float) -> Vector2:
	var img := _img if _img else macro.bake_height
	var n := img.get_width()
	var g := (p + Vector2(span, span) * 0.5) / span * float(n) - Vector2(0.5, 0.5)
	var i := Vector2i(clampi(floori(g.x), 0, n - 2), clampi(floori(g.y), 0, n - 2))
	var f := (g - Vector2(i)).clamp(Vector2.ZERO, Vector2.ONE)
	var a := img.get_pixel(i.x, i.y)
	var b := img.get_pixel(i.x + 1, i.y)
	var c := img.get_pixel(i.x, i.y + 1)
	var d := img.get_pixel(i.x + 1, i.y + 1)
	var h := lerpf(lerpf(a.r, b.r, f.x), lerpf(c.r, d.r, f.x), f.y) * MacroMap.BAKE_HEIGHT_SCALE
	var dr := lerpf(lerpf(a.g, b.g, f.x), lerpf(c.g, d.g, f.x), f.y) * 2.0 - 1.0
	return Vector2(h, dr)


static func _plan_tors(plan: CityPlan, img: Image = null) -> Array:
	var macro: MacroMap = plan.macro
	_img = img
	var span := 16000.0
	var out: Array = []
	var marks := _keep_out_marks(plan)
	var n := int(span / TOR_CELL)
	var half := span * 0.5
	var t0 := Time.get_ticks_usec()
	for cz in n:
		for cx in n:
			var hs := [plan.seed, "tor", cx, cz]
			var p := Vector2(-half + (cx + 0.15 + 0.7 * _h01(hs + ["x"])) * TOR_CELL, -half + (cz + 0.15 + 0.7 * _h01(hs + ["z"])) * TOR_CELL)
			var hd := _bake_at(macro, p, span)
			if hd.x < TOR_MIN_HEIGHT:
				continue
			var e := 16.0
			var gx := (_bake_at(macro, p + Vector2(e, 0.0), span).x - _bake_at(macro, p - Vector2(e, 0.0), span).x) / (2.0 * e)
			var gz := (_bake_at(macro, p + Vector2(0.0, e), span).x - _bake_at(macro, p - Vector2(0.0, e), span).x) / (2.0 * e)
			var grad := Vector2(gx, gz)
			var g := HillPlanting.ground(p, grad, false, hd.y)
			var rocky := float(g.rocky)
			var crest := hd.y < CREST_DRAIN
			var odds := TOR_ODDS * smoothstep(TOR_ROCKY, TOR_ROCKY + 0.3, rocky)
			# The steep faces: the bake's 31 m texels read a cliff band as a 40-degree slope, so the
			# painted rock (which wants 60) is rare at this scale; a steep face carries rock anyway.
			odds = maxf(odds, STEEP_ODDS * smoothstep(0.16, 0.36, float(g.slope)))
			if crest:
				odds += CREST_ODDS * smoothstep(CREST_DRAIN, -0.75, hd.y) * smoothstep(0.08, 0.25, float(g.slope))
			if _h01(hs + ["odds"]) > odds:
				continue
			if macro.zone_at(p) != MacroMap.Zone.HILLS:
				continue
			var tor := _make_tor(plan, p, grad, hd.y, float(g.slope), crest, crest and _summit(macro, p, hd.x, span), hs)
			if tor.is_empty() or _kept_out(plan, p, float(tor.radius), marks):
				continue
			tor["id"] = out.size()
			out.append(tor)
			# A crest carries a spine of rock along the ridge, a summit a jumble round its crag:
			# one piece alone read as a statue from the basin.
			if crest:
				var along := grad.orthogonal().normalized() if grad.length() > 1e-4 else Vector2.RIGHT
				var pieces := 1 + int(_h01(hs + ["spine"]) * (4.0 if bool(tor.summit) else 3.0))
				for k in pieces:
					var ks := hs + ["piece", k]
					var q: Vector2
					if bool(tor.summit):
						q = p + Vector2.from_angle(_h01(ks + ["a"]) * TAU) * float(tor.radius) * lerpf(0.45, 0.9, _h01(ks + ["d"]))
					else:
						var side := 1.0 if k % 2 == 0 else -1.0
						q = p + along * side * float(tor.radius) * lerpf(0.8, 1.5, _h01(ks + ["d"])) * (1.0 + float(k / 2))
					var qk := RockKit.TOR_A if _h01(ks + ["k"]) < 0.55 else RockKit.TOR_B
					var qs := float(tor.basis.get_scale().y) * lerpf(0.45, 0.85, _h01(ks + ["s"])) * (1.0 if qk == RockKit.TOR_A else 1.4)
					var piece := _make_tor(plan, q, grad, hd.y, float(g.slope), true, false, ks, qk, qs)
					if _kept_out(plan, q, float(piece.radius), marks) or macro.zone_at(q) != MacroMap.Zone.HILLS:
						continue
					piece["id"] = out.size()
					out.append(piece)
	print("RockOutcrops: %d tors planned in %.0f ms" % [out.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	_img = null
	return out


## Is `p` the highest point of the bake within SUMMIT_REACH (eight directions)?
static func _summit(macro: MacroMap, p: Vector2, h: float, span: float) -> bool:
	for k in 8:
		var d := Vector2.from_angle(TAU * k / 8.0) * SUMMIT_REACH
		if _bake_at(macro, p + d, span).x > h:
			return false
	return true


## A tor at `p`: which scan, how big, which way, how deep. A crest gets the long cliff laid along
## the ridge; a steep face the tall face slab turned to look down the slope; the rest the block.
static func _make_tor(plan: CityPlan, p: Vector2, grad: Vector2, drain: float, slope: float, crest: bool, summit: bool, hs: Array, force_kind: int = -1, force_s: float = 0.0) -> Dictionary:
	var size := _h01(hs + ["size"])
	var kind: int
	var s: float
	if force_kind >= 0:
		kind = force_kind
		s = force_s
		summit = false
	elif summit:
		# A summit crag: the range's skyline from the basin. Stood up as a spire it read as a
		# statue on every summit (refcam hills); with RcHills on it is a broad, low tor - the
		# cliff or the block, wider than tall, bedded in the crown.
		kind = RockKit.FACE_A if _h01(hs + ["kind"]) < 0.55 else RockKit.TOR_A
		s = lerpf(3.5, 6.0, size) if kind == RockKit.FACE_A else lerpf(4.0, 7.0, size)
		if RcHills.on():
			kind = RockKit.TOR_A if _h01(hs + ["kind"]) < 0.6 else RockKit.TOR_B
			s = lerpf(3.0, 5.2, size) if kind == RockKit.TOR_A else lerpf(3.2, 5.6, size)
	elif crest and _h01(hs + ["kind"]) < 0.7:
		kind = RockKit.TOR_A
		s = lerpf(1.6, 6.0, pow(size, 1.3))
	elif slope > 0.45:
		kind = RockKit.FACE_A
		s = lerpf(1.4, 4.5, pow(size, 1.3))
	else:
		kind = RockKit.TOR_B
		s = lerpf(1.6, 5.0, pow(size, 1.3))
	var b := RockKit.bounds(kind)
	var down := -grad.normalized() if grad.length() > 1e-4 else Vector2(0.0, 1.0)
	var yaw: float
	if kind == RockKit.TOR_A:
		# The long axis (+x) along the contour.
		yaw = atan2(-down.x, -down.y) + (_h01(hs + ["yaw"]) - 0.5) * 0.6
	elif kind == RockKit.FACE_A:
		# The face (the scan's +z side) looking down the slope.
		yaw = atan2(down.x, down.y) + (_h01(hs + ["yaw"]) - 0.5) * 0.5
	else:
		yaw = _h01(hs + ["yaw"]) * TAU
	var stretch := Vector3(lerpf(0.85, 1.25, _h01(hs + ["sx"])), lerpf(0.9, 1.45, _h01(hs + ["sy"])), lerpf(0.85, 1.2, _h01(hs + ["sz"])))
	if summit and RcHills.on():
		# Spread and squat: summit rock is a heap of weathered blocks, not a finger.
		stretch = Vector3(lerpf(1.15, 1.6, _h01(hs + ["sx"])), lerpf(0.7, 1.0, _h01(hs + ["sy"])), lerpf(1.0, 1.4, _h01(hs + ["sz"])))
	elif summit:
		# Stood up: a spire or a fin, narrower than it is tall (jointed sandstone weathers that way).
		stretch = Vector3(lerpf(0.55, 0.85, _h01(hs + ["sx"])), lerpf(1.3, 1.9, _h01(hs + ["sy"])), lerpf(0.6, 0.9, _h01(hs + ["sz"])))
	var sc := stretch * s
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, (_h01(hs + ["tilt"]) - 0.5) * 0.12).scaled(sc)
	var radius := 0.5 * Vector2(b.size.x * sc.x, b.size.z * sc.z).length()
	var tall := b.size.y * sc.y
	var gy := plan.macro.height_at(p)
	# Deep enough that the uphill side of the footprint is buried, plus a fifth of the height.
	var sink := tan(acos(clampf(1.0 - slope, 0.05, 1.0))) * radius * 0.7 + tall * lerpf(0.18, 0.32, _h01(hs + ["sink"]))
	sink = minf(sink, tall * 0.6)
	if summit:
		# The summit falls away on every side: nothing uphill to bury it in.
		sink = tall * lerpf(0.22, 0.34, _h01(hs + ["sink"]))
		if RcHills.on():
			sink = tall * lerpf(0.34, 0.46, _h01(hs + ["sink"]))
	return {"pos": p, "y": gy - sink, "sink": sink, "kind": kind, "basis": basis,
		"tone": _h01(hs + ["tone"]), "radius": radius, "top": tall - sink, "summit": summit}


## Roads, pads, landmarks, towers, masts and sites to keep the tors off, as [pos, radius] marks
## (roads are asked per tor, by segment).
static func _keep_out_marks(plan: CityPlan) -> Array:
	var marks: Array = []
	for l: Dictionary in Landmarks.all():
		if l.has("anchor") and l.has("radius"):
			# A landmark's radius flattens relief round it (the sign's is 400 m of the front range);
			# the rock keeps off what stands there.
			marks.append([l.anchor, minf(float(l.radius), 150.0) + 20.0])
	var macro: MacroMap = plan.macro
	if macro.hill_roads:
		for m: Dictionary in macro.hill_roads.mansions:
			marks.append([m.pos, HillRoads.PAD_RADIUS + 22.0])
	if macro.ridges:
		# The towers are planned lazily, with the city plan (Ridges.of()).
		Ridges.of(plan)
		for m: Dictionary in macro.ridges.masts:
			marks.append([m.pos, 40.0])
		for s: Dictionary in macro.ridges.sites:
			marks.append([s.pos, float(s.get("r", 10.0)) + 25.0])
		for t: Dictionary in macro.ridges.towers:
			marks.append([t.pos, 40.0])
	return marks


static func _kept_out(plan: CityPlan, p: Vector2, radius: float, marks: Array) -> bool:
	for m: Array in marks:
		if p.distance_to(m[0]) < float(m[1]) + radius:
			return true
	var macro: MacroMap = plan.macro
	if Ballpark.covers(p, radius + 20.0):
		return true
	# The coast highway's bench, road and houses under the bluffs (CoastHighway).
	if macro.get("coast_highway") != null and macro.coast_highway.covers(p, radius + 10.0):
		return true
	if macro.reservoir and macro.reservoir.keep_clear(p, macro.height_at(p), radius + 10.0):
		return true
	if macro.hill_roads:
		for seg: Dictionary in macro.hill_roads.segments_in(Rect2(p - Vector2(radius, radius), Vector2(radius, radius) * 2.0).grow(TOR_ROAD_CLEAR + 30.0)):
			var c := Geometry2D.get_closest_point_to_segment(p, seg.a, seg.b)
			if p.distance_to(c) < float(seg.width) * 0.5 + TOR_ROAD_CLEAR + radius:
				return true
	return false


## The tors whose origin is in `rect`.
static func tors_in(plan: CityPlan, rect: Rect2) -> Array:
	var out: Array = []
	for t: Dictionary in tors(plan):
		if rect.has_point(t.pos):
			out.append(t)
	return out
