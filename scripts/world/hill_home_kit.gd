class_name HillHomeKit
extends RefCounted
## The houses on the hillside estates (2026-10-05, "the Hollywood Hills form": an estate was a
## pad, walls, a gate, a pool and an 18 x 9 m Building slab). Every estate HillRoads places
## (`mansions`: the canyon roads', the switchbacks', the peninsula's) gets a house PLANNED on its
## pad, sized to it and facing the view - the pad side the ground falls away from most - and built
## as real geometry in HouseKit / HouseBuild's conventions (HillHomeBuild extends HouseBuild).
## Three Los Angeles hillside types, rolled per estate:
##   CANTILEVER    the mid-century glass pavilion: one long storey of floor-to-ceiling glass under a
##                 flat roof on a deep overhang, jutting 3.5-7 m out over the downhill bank on a
##                 steel frame (perimeter beams, tall steel columns down the slope, X bracing), a
##                 deck with a cable rail at its end, an infinity pool on the pad beside it whose
##                 far edge spills into a trough, a carport off the motor court; on a steep drop a
##                 glazed lower level tucked under the overhang
##   VILLA         Spanish revival stepping down the slope: two storeys of white stucco under clay
##                 hips, a three-storey tower, arched door and windows, a loggia wing a storey down
##                 the bank whose flat roof is a terrace at pad level (and on a steep drop a second
##                 step under it), a plain pool, a garage wing by the gate
##   CONTEMPORARY  stacked white boxes: a ground volume (white, stained timber or dark render) with
##                 the garage in it, an upper volume slid sideways and cantilevered 3.5-5.5 m out
##                 past it and the pad's edge, glass walls to the view, ribbon windows down the
##                 sides, an infinity pool
## Round every type: the pad walls by what the ground does (CityChunk._build_mansions' rule), on
## the view side no parapet where the house, the deck or the pool stand at the edge, a cable rail
## elsewhere; stairs down the bank to a lower level; terraced gardens below the pad (retaining
## walls with clipped hedges), Italian cypress (the fir, narrowed) and olives (the broad city
## tree, small and grey-green) on them and along the pad's sides; palms by the motor court. A
## house whose pad lies well below its road (`drive_h`) keeps its garage up at road level on
## steel stilts, the way the canyon houses do, with a stair down to the pad.
##
## The plan is PURE (plan_home(): the city plan and the estate, every roll a hash of the seed and
## the estate's own seed, the ground read through plan.height_at(), the carved ground), so the far
## city's boxes (far_boxes(), from Skyline._add_hills), the probe and the tests see the very house
## the chunk builds. It is laid in a frame on the pad (`o`, `fu`, `fv`: u across, v from the pad's
## uphill edge to its view edge at v = Dp; pad rect u 0..Wp, v 0..Dp), one of the pad's own four
## axes, so the house squares with the pad's walls. Heights are over `floor`, the pad's top plus
## HouseKit.FLOOR_LIFT; a wing's `y` is its floor over that (a lower level is -STOREY), its
## `base` how far below its floor its walls run (to the pad, the slab edge, or the bank).
##
## FULL chunks: every house of the chunk into ONE mesh per material (commit(), from the chunk's
## finish), collision boxes on one static body; the site works (decks, coping, beams, columns,
## braces, stairs, terraces, retaining walls) into the chunk's merged boxes. LOD chunks: the city's
## LOD box per wing with lit windows (building_lod's old path), roof slabs, the pool and the
## columns as boxes. The far city (Skyline): a few boxes an estate on far_canopy.gdshader plus a
## glass band on each wing's view face that glows warm after dark (INSTANCE_CUSTOM.g), so the
## hills twinkle across the basin.

## Off, the estates get the old Building slab (the A/B: HILL_HOMES=0 in the environment).
static var enabled: bool = OS.get_environment("HILL_HOMES") != "0"

enum Style { CANTILEVER, VILLA, CONTEMPORARY }
const STYLE_NAMES := ["cantilever", "villa", "contemporary"]
## Cumulative odds by how far the ground falls off the view side: a gentle pad gets fewer
## cantilevers (nothing to jut over) and villas (nothing to step down).
const STYLES_STEEP := [[Style.CANTILEVER, 0.42], [Style.VILLA, 0.74], [Style.CONTEMPORARY, 1.0]]
const STYLES_GENTLE := [[Style.CANTILEVER, 0.25], [Style.VILLA, 0.55], [Style.CONTEMPORARY, 1.0]]
## The drop (metres, pad top to the ground 3-8 m off the view edge) that counts as steep.
const STEEP_DROP := 3.0
## Where the view's drop is read: metres past the edge of the pad's flat.
const VIEW_SAMPLES: Array[float] = [4.0, 9.0]

## The pad box: the full estate's (CityChunk.ESTATE_PAD) and the compact one's.
const PAD_FULL := Vector3(26.0, 0.4, 22.0)
const PAD_COMPACT := Vector3(20.0, 0.4, 17.0)
## The motor court's depth in front of the house when the gate is on the uphill edge.
const COURT := 7.0
const COURT_COMPACT := 5.6
## The gate's corridor half width (the gate is 5.2 m).
const GATE_HALF := 3.2
## How far below its floor a wing on the pad runs its walls (into the pad), and a slab's edge.
const PAD_BASE := -0.55
const SLAB := 0.45
## Steel: the perimeter beam's depth under a cantilevered slab, a column's half width, the spacing
## along a row, the brace and the cable rail.
const BEAM := 0.5
const COLUMN := 0.14
const COLUMN_SPACING := 4.6
const BRACE := 0.05
const RAIL_H := 1.05
## The deck at the end of a cantilever.
const DECK := 2.6
## Garage on stilts when the road is this much higher than the pad.
const ROAD_GARAGE_RISE := 2.6
## A terraced garden's walls below the pad: how far out each one stands, and how tall.
const TERRACE_STEPS := [4.0, 8.5]
const TERRACE_WALL := 1.2

## Palettes (sRGB).
const WHITE_STUCCO := [Color(0.96, 0.95, 0.92), Color(0.94, 0.93, 0.90), Color(0.97, 0.96, 0.94), Color(0.92, 0.90, 0.86)]
const VILLA_STUCCO := [Color(0.97, 0.95, 0.90), Color(0.95, 0.91, 0.83), Color(0.93, 0.87, 0.76), Color(0.96, 0.92, 0.86), Color(0.90, 0.82, 0.70)]
const DARK_RENDER := [Color(0.30, 0.30, 0.29), Color(0.42, 0.41, 0.39), Color(0.22, 0.22, 0.23)]
const MOD_WALL := [Color(0.95, 0.94, 0.91), Color(0.86, 0.85, 0.82), Color(0.80, 0.78, 0.73), Color(0.92, 0.90, 0.84)]
## Dark bronze, black and a warm grey: the glass frames of a modern house.
const MOD_FRAME := [Color(0.11, 0.11, 0.11), Color(0.18, 0.15, 0.12), Color(0.30, 0.30, 0.29)]
const STEEL := Color(0.13, 0.13, 0.13)
## The far tiers' house colours are the walls'; the glass band is a dark glazing by day.
const FAR_GLASS := Color(0.10, 0.12, 0.13)

## Materials of the house meshes (HouseKit's, plus the hillside glass and the pool water).
const MATS := ["h_wall", "h_siding", "h_trim", "h_door", "h_metal", "h_dark", "h_roof", "h_flat", "hh_glass", "hh_water"]
const NO_SHADOW := ["hh_glass", "h_dark", "hh_water"]


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _pick(arr: Array, parts: Array) -> Variant:
	return arr[absi(hash(parts)) % arr.size()]


static func _range(v: Vector2, parts: Array) -> float:
	return lerpf(v.x, v.y, _h01(parts))


static func pad_size(m: Dictionary) -> Vector3:
	return PAD_FULL if float(m.get("radius", HillRoads.PAD_RADIUS)) >= 15.0 else PAD_COMPACT


# =================================================================================================
# The plan (pure)
# =================================================================================================

## A house for an estate. {"style", "style_name", "seed", "o", "fu", "fv", "Wp", "Dp", "top" (pad
## top, world y), "floor" (top + FLOOR_LIFT), "view_side", "drop", "gate" (frame point), "wings":
## [{"r", "storeys", "roof", "role", "mat", "clad", "y", "base", "eave", "glass" (faces of floor-to-
## ceiling glass), "ribbon" (faces of ribbon windows), "arches"}], "door", "garage", "porch",
## "chimney", "pool": {"r", "infinity"} or {}, "deck": Rect2 or zero, "cantilever", "frame_steel"
## (the wing index whose overhang stands on columns, -1 none), "stairs": [[a, b, y0, y1, width]],
## "terraces": [Rect2 free u ranges as Vector2], "road_garage": {} or {"c", "y"}, "trees",
## "colors", "eye", "height"} plus HouseBuild's keys (pitch, eave, roof_mat, shingle_kind, vents,
## solar, breeze, style - HouseKit.Style for the openings it reads).
static func plan_home(plan: CityPlan, m: Dictionary) -> Dictionary:
	var ps: int = plan.seed
	var s: int = int(m.seed)
	var pos: Vector2 = m.pos
	var pad := pad_size(m)
	var top: float = float(m.height) + pad.y
	var basis := Basis(Vector3.UP, float(m.yaw))
	var ax := Vector2(basis.x.x, basis.x.z)
	var az := Vector2(basis.z.x, basis.z.z)
	# The view: of the pad's three sides that are not its road side, the one the ground falls off
	# most past the pad's flat (the carved disc of `radius`; the road side keeps the gate and the
	# drive).
	var radius: float = float(m.get("radius", HillRoads.PAD_RADIUS))
	var sides := [["back", -az, pad.z * 0.5, pad.x * 0.5], ["right", ax, pad.x * 0.5, pad.z * 0.5], ["left", -ax, pad.x * 0.5, pad.z * 0.5]]
	var best := 0
	var best_drop := -INF
	for k in sides.size():
		var sd: Array = sides[k]
		var dir: Vector2 = sd[1]
		var perp: float = sd[3]
		var side_u := Vector2(dir.y, -dir.x)
		var sum := 0.0
		for d: float in VIEW_SAMPLES:
			for t: float in [-0.35, 0.0, 0.35]:
				sum += plan.height_at(pos + dir * (radius + d) + side_u * (t * perp * 2.0))
		var drop := top - sum / (3.0 * VIEW_SAMPLES.size()) + _h01([ps, s, "view", k]) * 0.3
		if drop > best_drop:
			best_drop = drop
			best = k
	var sv: Array = sides[best]
	var fv: Vector2 = sv[1]
	var fu := Vector2(fv.y, -fv.x)
	var half: float = sv[2]
	var Wp: float = float(sv[3]) * 2.0
	# The pad runs out on the view side to the edge of the flat, as far as its corners stay off
	# ground that rises over it (a corner past the disc stands on the bank, walled).
	var Dp := half * 2.0
	for ext: float in [radius - 0.6, sqrt(maxf((radius + 2.0) * (radius + 2.0) - Wp * Wp * 0.25, 0.0))]:
		if ext <= half + 0.3:
			continue
		var ok := true
		for sg: float in [-1.0, 1.0]:
			var corner := pos + fv * ext + fu * (sg * Wp * 0.5)
			if plan.height_at(corner) > top - 0.3:
				ok = false
		if ok:
			Dp = half + ext
			break
	var o: Vector2 = pos - fu * (Wp * 0.5) - fv * half
	var gate_w: Vector2 = pos + az * (pad.z * 0.5)
	var gate := Vector2((gate_w - o).dot(fu), (gate_w - o).dot(fv))
	var drop := maxf(best_drop, 0.0)
	var compact := pad.x < PAD_FULL.x - 0.1
	var odds: Array = STYLES_STEEP if drop >= STEEP_DROP else STYLES_GENTLE
	var roll := _h01([ps, s, "hill_style"])
	var style: int = Style.CONTEMPORARY
	for e: Array in odds:
		if roll < float(e[1]):
			style = int(e[0])
			break
	# Where the house may stand: past the motor court when the gate is on the uphill edge, past
	# the gate's corridor when it is on a side edge.
	var gate_front := gate.y < Dp * 0.25
	var vh: float = (COURT_COMPACT if compact else COURT) if gate_front else gate.y + GATE_HALF + 0.4
	var h := {"style": style, "style_name": STYLE_NAMES[style], "seed": s, "o": o, "fu": fu, "fv": fv, "Wp": Wp, "Dp": Dp,
		"top": top, "floor": top + HouseKit.FLOOR_LIFT, "view_side": sv[0], "drop": drop, "gate": gate, "gate_front": gate_front,
		"vh": vh, "wings": [], "door": {}, "garage": {}, "porch": {}, "chimney": {}, "pool": {}, "deck": Rect2(), "cantilever": 0.0,
		"frame_steel": -1, "stairs": [], "terraces": [], "road_garage": {}, "trees": [], "breeze": Rect2(), "vents": 0,
		"solar": false, "roof_mat": "h_flat", "shingle_kind": 1, "pitch": 0.3, "eave": 0.5, "drive": Vector2.ZERO, "drive_v": 0.0,
		"door_u": Wp * 0.5, "door_v": vh, "hstyle": HouseKit.Style.MIDCENTURY, "compact": compact, "pad": pad, "m_pos": pos}
	# Which side of the frame the house's main volume takes (the pool and the terrace the other).
	var left := _h01([ps, s, "hill_side"]) < 0.5
	if not gate_front:
		# With the gate on a side edge the house keeps to the far side from it, so the court and
		# the garage by the gate stay clear.
		left = gate.x > Wp * 0.5
	h["left"] = left
	match style:
		Style.CANTILEVER:
			_plan_cantilever(h, ps, s, plan)
		Style.VILLA:
			_plan_villa(h, ps, s, plan)
		_:
			_plan_contemporary(h, ps, s, plan)
	_plan_garage(h, ps, s, plan, m)
	_plan_site(h, ps, s, plan)
	_colors(h, ps, s)
	# The bases: a wing on the pad runs its walls into the pad; one standing out over the bank
	# (a lower level) runs them down to the lowest ground under it.
	for w: Dictionary in h.wings:
		var r: Rect2 = w.r
		var y: float = w.y
		if y < -0.5:
			var lo := INF
			for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.get_center()]:
				lo = minf(lo, plan.height_at(frame_point(h, c)))
			w.base = minf(-0.3, lo - (float(h.floor) + y) - 0.4)
		elif not w.has("base"):
			w.base = PAD_BASE if y < 0.5 else -SLAB
	var hgt := 0.0
	for w: Dictionary in h.wings:
		var t := float(w.y) + float(w.storeys) * HouseKit.STOREY
		if w.roof == "hip" or w.roof == "gable":
			var rr: Rect2 = w.r
			t += minf(rr.size.x, rr.size.y) * 0.5 * float(h.pitch)
		hgt = maxf(hgt, t)
	h["height"] = hgt
	# A camera on the slope below the house looking back up at it (the probe's EYE), clear of the
	# other estates' pads.
	var eye_p: Vector2 = frame_point(h, Vector2(Wp * 0.5, Dp + 36.0))
	if plan.macro and plan.macro.hill_roads:
		for d: float in [36.0, 46.0, 28.0, 58.0, 70.0]:
			var q: Vector2 = frame_point(h, Vector2(Wp * 0.5, Dp + d))
			var clear := true
			for o2: Dictionary in plan.macro.hill_roads.mansions_in(Rect2(q - Vector2(30, 30), Vector2(60, 60))):
				if int(o2.seed) != s and q.distance_to(o2.pos) < float(o2.get("radius", HillRoads.PAD_RADIUS)) + 8.0:
					clear = false
			if clear:
				eye_p = q
				break
	var eye_y := plan.height_at(eye_p) + 1.7
	var look := -fv
	var eye_d := eye_p.distance_to(frame_point(h, Vector2(Wp * 0.5, Dp)))
	h["eye"] = "%.1f,%.1f,%.1f,%.0f,%.0f" % [eye_p.x, eye_y, eye_p.y, rad_to_deg(atan2(-look.x, -look.y)), clampf(rad_to_deg(atan2(float(h.floor) - eye_y + 3.0, eye_d)), -20.0, 35.0)]
	h["eye_agl"] = "%.1f,1.7,%.1f,%.0f,%.0f" % [eye_p.x, eye_p.y, rad_to_deg(atan2(-look.x, -look.y)), clampf(rad_to_deg(atan2(float(h.floor) - eye_y + 3.0, eye_d)), -20.0, 35.0)]
	return h


static func frame_point(h: Dictionary, uv: Vector2) -> Vector2:
	return (h.o as Vector2) + (h.fu as Vector2) * uv.x + (h.fv as Vector2) * uv.y


static func _wing(r: Rect2, storeys: int, roof: String, role: String, y: float = 0.0) -> Dictionary:
	return {"r": r, "storeys": storeys, "roof": roof, "ridge": 0, "role": role, "mat": "h_wall", "clad": 1.0, "y": y,
		"glass": [], "ribbon": [], "arches": false, "eave": -1.0}


static func _rect(u0: float, v0: float, u1: float, v1: float) -> Rect2:
	return Rect2(minf(u0, u1), minf(v0, v1), absf(u1 - u0), absf(v1 - v0))


## The house's main volume across the frame: `share` of the pad's width on the house's side.
static func _main_span(h: Dictionary, share: float) -> Vector2:
	var Wp: float = h.Wp
	var w := Wp * share
	return Vector2(1.2, 1.2 + w) if h.left else Vector2(Wp - 1.2 - w, Wp - 1.2)


## The free strip beside the main volume (the pool's, the terrace's): u0, u1.
static func _free_span(h: Dictionary, main: Vector2) -> Vector2:
	var Wp: float = h.Wp
	return Vector2(main.y + 1.0, Wp - 1.0) if h.left else Vector2(1.0, main.x - 1.0)


static func _plan_cantilever(h: Dictionary, ps: int, s: int, _plan: CityPlan) -> void:
	var Dp: float = h.Dp
	var drop: float = h.drop
	var over := clampf(3.4 + drop * 0.45, 3.4, 7.0) * _range(Vector2(0.85, 1.05), [ps, s, "over"])
	if drop < 1.5:
		over = 2.2
	h.cantilever = over
	h.eave = _range(Vector2(1.5, 2.3), [ps, s, "eave"])
	var span := _main_span(h, _range(Vector2(0.56, 0.66), [ps, s, "width"]))
	var v0: float = float(h.vh) + 0.4
	var v1: float = Dp + over - DECK
	if v1 - v0 < 7.0:
		v0 = maxf(v1 - 7.0, 1.0)
	var main := _wing(_rect(span.x, v0, span.y, v1), 1, "deck", "main")
	main.glass = ["back", "left", "right"]
	main["solid_front_share"] = _range(Vector2(0.3, 0.45), [ps, s, "solid"])
	if _h01([ps, s, "boards"]) < 0.45:
		main.mat = "h_siding"
		main.clad = 0.0
	h.wings.append(main)
	h.frame_steel = 0
	h.deck = _rect(span.x, v1, span.y, v1 + DECK)
	_door(h, 0, span.x + 1.6 if not h.left else span.y - 1.6, "mod_door")
	h.porch = {"r": _rect(float(h.door_u) - 1.1, v0 - 1.8, float(h.door_u) + 1.1, v0), "kind": "canopy", "top": HouseKit.FLOOR_LIFT + 2.6}
	# On a steep drop, a glazed lower level tucked under the overhang.
	if drop > 6.0 and _h01([ps, s, "lower"]) < 0.55:
		var low := _wing(_rect(span.x + 1.2, Dp - 0.6, span.y - 1.2, v1 - 1.2), 1, "deck", "lower", -HouseKit.STOREY)
		low.eave = 0.0
		low.glass = ["back"]
		low.ribbon = ["left", "right"]
		h.wings.append(low)
		h.stairs.append(_side_stair(h, span, -HouseKit.STOREY))
	var free := _free_span(h, span)
	if free.y - free.x >= 5.5:
		var pw := _range(Vector2(3.6, 4.6), [ps, s, "poolw"])
		h.pool = {"r": _rect(free.x + 0.4, Dp - 0.25 - pw, free.y - 0.4, Dp - 0.25), "infinity": true}
	h["hstyle"] = HouseKit.Style.MIDCENTURY


static func _plan_villa(h: Dictionary, ps: int, s: int, _plan: CityPlan) -> void:
	var Dp: float = h.Dp
	var drop: float = h.drop
	h.roof_mat = "h_roof"
	h.pitch = _range(Vector2(0.27, 0.33), [ps, s, "pitch"])
	h.eave = _range(Vector2(0.4, 0.55), [ps, s, "eave"])
	var span := _main_span(h, _range(Vector2(0.62, 0.72), [ps, s, "width"]))
	var v0: float = float(h.vh) + 0.4
	var v1 := Dp - 1.0
	var main := _wing(_rect(span.x, v0, span.y, v1), 2, "hip", "main")
	main.arches = true
	main["balcony"] = _h01([ps, s, "balcony"]) < 0.6
	h.wings.append(main)
	# The tower at the main wing's outer front corner.
	var tw := 4.4
	var tu0: float = span.x if h.left else span.y - tw
	var tower := _wing(_rect(tu0, v0 - 1.2, tu0 + tw, v0 - 1.2 + tw), 3, "hip", "tower")
	tower.arches = true
	h.wings.append(tower)
	var mw := span.y - span.x
	_door(h, 0, span.x + mw * 0.55, "arch_door")
	h.porch = {"r": _rect(float(h.door_u) - 1.0, v0 - 1.2, float(h.door_u) + 1.0, v0), "kind": "stoop", "top": HouseKit.FLOOR_LIFT}
	h.chimney = {"wing": 0, "end": 1 if h.left else 0, "mat": "h_wall", "side": true}
	# Stepping down: a loggia wing a storey down the bank, its roof a terrace at pad level.
	if drop > 2.2:
		var low := _wing(_rect(span.x + 0.8, Dp - 0.8, span.y - 0.8, Dp + _range(Vector2(4.8, 6.2), [ps, s, "loggia"])), 1, "flat", "lower", -HouseKit.STOREY)
		low.arches = true
		low["terrace"] = true
		h.wings.append(low)
		h.stairs.append(_side_stair(h, span, -HouseKit.STOREY))
		if drop > 7.0 and _h01([ps, s, "lower2"]) < 0.6:
			var lr: Rect2 = low.r
			var low2 := _wing(_rect(lr.position.x + 1.5, lr.end.y - 0.6, lr.end.x - 1.5, lr.end.y + 4.6), 1, "flat", "lower", -2.0 * HouseKit.STOREY)
			low2.arches = true
			low2["terrace"] = true
			h.wings.append(low2)
	var free := _free_span(h, span)
	if free.y - free.x >= 5.5:
		var pw := _range(Vector2(3.8, 4.8), [ps, s, "poolw"])
		var pl := minf(free.y - free.x - 1.0, _range(Vector2(8.0, 11.0), [ps, s, "pooll"]))
		var pc := (free.x + free.y) * 0.5
		h.pool = {"r": _rect(pc - pl * 0.5, Dp - 2.2 - pw, pc + pl * 0.5, Dp - 2.2), "infinity": false}
	h["hstyle"] = HouseKit.Style.SPANISH


static func _plan_contemporary(h: Dictionary, ps: int, s: int, _plan: CityPlan) -> void:
	var Dp: float = h.Dp
	var drop: float = h.drop
	h.eave = 0.3
	var span := _main_span(h, _range(Vector2(0.55, 0.64), [ps, s, "width"]))
	var v0: float = float(h.vh) + 0.4
	var lower := _wing(_rect(span.x, v0, span.y, Dp - 0.6), 1, "deck", "main")
	lower.eave = 0.15
	lower.glass = ["back"]
	lower.ribbon = ["left", "right"]
	var lm := _h01([ps, s, "lower_mat"])
	if lm < 0.4:
		lower.mat = "h_siding"
		lower.clad = 0.0
	elif lm < 0.65:
		lower["dark"] = true
	h.wings.append(lower)
	# The upper volume, slid toward the free side and out past the pad's edge.
	var over := clampf(3.2 + drop * 0.3, 3.2, 5.5) * _range(Vector2(0.9, 1.05), [ps, s, "over"])
	h.cantilever = over
	var shift := _range(Vector2(2.0, 4.0), [ps, s, "shift"]) * (1.0 if h.left else -1.0)
	var uw := (span.y - span.x) * _range(Vector2(0.85, 1.05), [ps, s, "upper_w"])
	var uc := (span.x + span.y) * 0.5 + shift
	var Wp: float = h.Wp
	uc = clampf(uc, uw * 0.5 + 0.8, Wp - uw * 0.5 - 0.8)
	var upper := _wing(_rect(uc - uw * 0.5, v0 + _range(Vector2(1.6, 3.0), [ps, s, "upper_v"]), uc + uw * 0.5, Dp + over), 1, "deck", "upper", HouseKit.STOREY)
	upper.eave = 0.35
	upper.glass = ["back"]
	upper.ribbon = ["left", "right", "front"]
	h.wings.append(upper)
	_door(h, 0, span.x + 1.4 if h.left else span.y - 1.4, "mod_door")
	h.porch = {"r": _rect(float(h.door_u) - 1.1, v0 - 1.6, float(h.door_u) + 1.1, v0), "kind": "canopy", "top": HouseKit.FLOOR_LIFT + 2.7}
	var free := _free_span(h, Vector2(minf(span.x, uc - uw * 0.5), maxf(span.y, uc + uw * 0.5)))
	if free.y - free.x >= 5.0:
		var pw := _range(Vector2(3.4, 4.4), [ps, s, "poolw"])
		h.pool = {"r": _rect(free.x + 0.3, Dp - 0.25 - pw, free.y - 0.3, Dp - 0.25), "infinity": true}
	elif drop > 2.0:
		h.stairs.append(_side_stair(h, span, -HouseKit.STOREY))
	h["hstyle"] = HouseKit.Style.STUCCO_BOX


## A stair down the bank beside the main span, from the pad to `y` (a lower level's floor): its
## top at the view edge, running out along v. [a (frame), b (frame), y0, y1, width].
static func _side_stair(h: Dictionary, span: Vector2, y: float) -> Array:
	var Dp: float = h.Dp
	var u: float = span.y + 0.9 if h.left else span.x - 0.9
	var run := absf(y) / 0.17 * 0.29
	return [Vector2(u, Dp - 0.2), Vector2(u, Dp - 0.2 + run), -HouseKit.FLOOR_LIFT, y - HouseKit.FLOOR_LIFT, 1.3]


static func _door(h: Dictionary, wing: int, u: float, kind: String) -> void:
	h.door = {"wing": wing, "u": u, "kind": kind}
	h.door_u = u
	h.door_v = (h.wings[wing].r as Rect2).position.y


## The garage or carport by the gate, its door to the court; or, when the road runs well above
## the pad, a garage up at the road on steel stilts.
static func _plan_garage(h: Dictionary, ps: int, s: int, plan: CityPlan, m: Dictionary) -> void:
	var road_y: float = float(m.get("drive_h", m.height))
	var from: Vector2 = m.get("drive_from", m.pos)
	if road_y - float(h.top) > ROAD_GARAGE_RISE and from.distance_to(m.pos) > 8.0:
		# On the road's shoulder beside the drive's mouth, its door to the road.
		var to_pad: Vector2 = ((m.pos as Vector2) - from).normalized()
		var side := Vector2(-to_pad.y, to_pad.x) * (1.0 if _h01([ps, s, "rg_side"]) < 0.5 else -1.0)
		var c: Vector2 = from + to_pad * 4.2 + side * 4.4
		h.road_garage = {"c": c, "y": road_y + 0.12, "dir": -to_pad, "side": side, "ground": plan.height_at(c)}
		return
	var Wp: float = h.Wp
	var gate: Vector2 = h.gate
	var gw := 6.2
	var gd := 6.4
	var gr: Rect2
	var face := "front"
	if h.gate_front:
		# Beside the gate's corridor, on the side away from the house's main volume when the
		# court allows, else the other.
		var room_l := gate.x - GATE_HALF - 1.0
		var room_r := Wp - 1.0 - (gate.x + GATE_HALF)
		if room_l < gw and room_r < gw:
			return
		gd = minf(gd, float(h.vh) - 0.6)
		if gd < 5.0:
			return
		var on_left: bool = room_l >= gw and (room_r < gw or not h.left)
		if on_left:
			gr = _rect(gate.x - GATE_HALF - gw, 0.6, gate.x - GATE_HALF, 0.6 + gd)
		else:
			gr = _rect(gate.x + GATE_HALF, 0.6, gate.x + GATE_HALF + gw, 0.6 + gd)
		face = "right" if on_left else "left"
	else:
		# Uphill of the gate's corridor, along the gate's edge, its door to the court.
		var at_left := gate.x < Wp * 0.5
		var v1 := gate.y - GATE_HALF - 0.3
		if v1 - gw < 0.8:
			return
		gr = _rect(0.9 if at_left else Wp - 0.9 - gd, v1 - gw, (0.9 + gd) if at_left else Wp - 0.9, v1)
		face = "back"
	# The house's main volume must be clear of it.
	for w: Dictionary in h.wings:
		if (w.r as Rect2).grow(0.3).intersects(gr) and float(w.y) > -0.5:
			return
	var kind := "garage"
	var roof := "deck"
	match int(h.style):
		Style.CANTILEVER:
			kind = "carport" if _h01([ps, s, "carport"]) < 0.65 else "garage"
		Style.VILLA:
			roof = "hip"
	var gwing := _wing(gr, 1, roof, kind)
	gwing.eave = 0.6 if roof == "deck" else -1.0
	gwing["gface"] = face
	h.wings.append(gwing)
	h.garage = {"wing": h.wings.size() - 1, "kind": kind, "face": face}


## Trees, terraces below the pad.
static func _plan_site(h: Dictionary, ps: int, s: int, _plan: CityPlan) -> void:
	var Wp: float = h.Wp
	var Dp: float = h.Dp
	var drop: float = h.drop
	# The u ranges of the view edge no wing, deck or pool stands over (a terraced garden below).
	var taken: Array[Vector2] = []
	for w: Dictionary in h.wings:
		var r: Rect2 = w.r
		if r.end.y > Dp - 0.5:
			taken.append(Vector2(r.position.x - 0.6, r.end.x + 0.6))
	for st: Array in h.stairs:
		var a: Vector2 = st[0]
		taken.append(Vector2(a.x - 1.2, a.x + 1.2))
	var free: Array[Vector2] = []
	var u := 1.0
	taken.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	for t: Vector2 in taken:
		if t.x - u > 3.0:
			free.append(Vector2(u, t.x))
		u = maxf(u, t.y)
	if Wp - 1.0 - u > 3.0:
		free.append(Vector2(u, Wp - 1.0))
	if drop > 2.5:
		h.terraces = free
	# Cypress along the pad's two side walls (a row of four to six), olives in the court, palms.
	var trees: Array = []
	var cyp_side := _h01([ps, s, "cypress"])
	if cyp_side < 0.7:
		var su := 0.6 if cyp_side < 0.35 else Wp - 0.6
		var n := 4 + absi(hash([ps, s, "ncyp"])) % 3
		for k in n:
			var v: float = lerpf(float(h.vh), Dp - 1.5, (float(k) + 0.5) / n)
			if _clear(h, Vector2(su, v), 1.2):
				trees.append(["cypress", Vector2(su, v), _range(Vector2(9.0, 13.0), [ps, s, "cyh", k])])
	for k in 2:
		var p := Vector2(_range(Vector2(1.6, Wp - 1.6), [ps, s, "olu", k]), _range(Vector2(1.6, maxf(float(h.vh) - 1.2, 2.0)), [ps, s, "olv", k]))
		var gate: Vector2 = h.gate
		if p.distance_to(gate) > 4.0 and _clear(h, p, 2.2):
			trees.append(["olive", p, _range(Vector2(4.0, 6.0), [ps, s, "olh", k])])
	var npalm := absi(hash([ps, s, "npalm"])) % 3
	for k in npalm:
		var p := Vector2(_range(Vector2(1.0, Wp - 1.0), [ps, s, "pu", k]), _range(Vector2(0.8, Dp - 1.0), [ps, s, "pv", k]))
		if _clear(h, p, 1.4) and p.distance_to(h.gate) > 3.5:
			trees.append(["palm", p, 0.0])
	for i in (h.terraces as Array).size():
		var fr: Vector2 = h.terraces[i]
		for k in int((fr.y - fr.x) / 4.5):
			var tp := Vector2(fr.x + 2.0 + float(k) * 4.5, Dp + TERRACE_STEPS[0] + 2.0)
			if _h01([ps, s, "terr_tree", i, k]) < 0.7:
				trees.append(["olive" if _h01([ps, s, "terr_kind", i, k]) < 0.6 else "cypress", tp, _range(Vector2(4.0, 9.0), [ps, s, "tth", i, k])])
	h.trees = trees


## Whether a frame point is clear (by `r`) of every wing, the pool, the deck and the gate corridor.
static func _clear(h: Dictionary, p: Vector2, r: float) -> bool:
	for w: Dictionary in h.wings:
		if (w.r as Rect2).grow(r).has_point(p):
			return false
	var pl: Dictionary = h.pool
	if not pl.is_empty() and (pl.r as Rect2).grow(r).has_point(p):
		return false
	var dk: Rect2 = h.deck
	if dk.size.x > 0.0 and dk.grow(r).has_point(p):
		return false
	var pr: Dictionary = h.porch
	if not pr.is_empty() and (pr.r as Rect2).grow(r).has_point(p):
		return false
	return true


static func _colors(h: Dictionary, ps: int, s: int) -> void:
	var style: int = h.style
	var wall: Color = _pick(WHITE_STUCCO, [ps, s, "wall"])
	var frame: Color = _pick(MOD_FRAME, [ps, s, "frame"])
	var trim := Color(0.95, 0.94, 0.91)
	match style:
		Style.VILLA:
			wall = _pick(VILLA_STUCCO, [ps, s, "wall"])
			frame = _pick([Color(0.22, 0.15, 0.10), Color(0.12, 0.12, 0.11), Color(0.16, 0.24, 0.20)], [ps, s, "frame"])
			trim = _pick([Color(0.30, 0.20, 0.13), Color(0.22, 0.16, 0.11)], [ps, s, "trim"])
		Style.CANTILEVER:
			wall = _pick(MOD_WALL, [ps, s, "wall"])
			trim = _pick([Color(0.95, 0.94, 0.91), Color(0.42, 0.30, 0.20), Color(0.16, 0.16, 0.16)], [ps, s, "trim"])
	var stain: Color = _pick(HouseKit.STAIN, [ps, s, "stain"])
	var door: Color = _pick(HouseKit.MOD_DOORS if style != Style.VILLA else [Color(0.30, 0.19, 0.12), Color(0.40, 0.26, 0.15)], [ps, s, "door_c"])
	h["colors"] = {"wall": wall, "siding": stain, "trim": trim, "frame": frame, "shingle": HouseKit.SHINGLE[0],
		"clay": _pick(HouseKit.CLAY, [ps, s, "clay"]), "door": door, "garage": _pick([Color(0.20, 0.19, 0.18), Color(0.55, 0.42, 0.28), Color(0.88, 0.87, 0.84)], [ps, s, "garage_c"]),
		"stain": stain, "dark": _pick(DARK_RENDER, [ps, s, "dark"])}


# =================================================================================================
# Building one (from CityChunk._build_mansions)
# =================================================================================================

## Whether `ch` builds the estate's house through the kit.
static func wanted(_ch: CityChunk) -> bool:
	return enabled


## The house and its site for one estate: FULL into the chunk's meshes and merged boxes, LOD as
## the city's LOD boxes. The pad, its walls and the gate are the kit's too; the driveway strip
## stays CityChunk's, run to the point this returns (just outside the gate).
static func build(ch: CityChunk, m: Dictionary) -> Vector2:
	var hp := plan_home(ch.plan, m)
	var b := HillHomeBuild.new()
	b.setup_hill(ch, hp)
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		b.acc = _acc(ch)
		b.acc.count += 1
		# Time-sliced: a house is a dozen milliseconds of GDScript, so each piece is a build step of
		# its own before the chunk's finish (which commits the meshes), run with the batch's relief
		# lift off like the step that queued it (everything here is placed at the map's height).
		# The lambdas hold `b` itself: a Callable to a RefCounted's method does not keep it alive.
		var jobs: Array = [["pad_job", []]]
		for i in (hp.wings as Array).size():
			jobs.append(["wing_job", [i]])
		jobs.append(["house_job", []])
		jobs.append(["frame_job", []])
		jobs.append(["garden_job", []])
		for job: Array in jobs:
			ch._run_or_defer(ch._on_map_ground(func() -> bool:
				b.callv(String(job[0]), job[1])
				return true))
	else:
		b.lod()
	var pad := pad_size(m)
	var basis := Basis(Vector3.UP, float(m.yaw))
	return (m.pos as Vector2) + Vector2(basis.z.x, basis.z.z) * (pad.z * 0.5 + 0.05)


## Builds every material and loads every texture the houses use, for the loading screen (drawn
## once through a MultiMesh there): the first estate to stream in used to load the planks, the
## board-formed concrete and the plaster mid-flight.
static func warm() -> Array:
	var out: Array = []
	for n: String in MATS:
		out.append(material(n))
	for n: String in ["steel", "deck", "coping", "stone", "terrace", "concrete", "board_concrete", "retain_villa", "hedge", "cushion"]:
		out.append(site_material(n))
	return out


static func _acc(ch: CityChunk) -> HouseKit.Acc:
	if not ch.has_meta("hill_home_kit"):
		ch.set_meta("hill_home_kit", HouseKit.Acc.new())
	return ch.get_meta("hill_home_kit")


## The chunk's finish: every hill home of the chunk as one mesh per material, one static body.
static func commit(ch: CityChunk) -> void:
	if not ch.has_meta("hill_home_kit"):
		return
	var acc: HouseKit.Acc = ch.get_meta("hill_home_kit")
	ch.remove_meta("hill_home_kit")
	for name: String in acc.st:
		var st: SurfaceTool = acc.st[name]
		var mesh := st.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "HillHome_" + name
		mi.mesh = mesh
		mi.material_override = material(name)
		if name in NO_SHADOW:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)
	if not acc.shapes.is_empty():
		var body := StaticBody3D.new()
		body.name = "HillHomes"
		body.collision_layer = 1
		body.collision_mask = 0
		for sh: CollisionShape3D in acc.shapes:
			body.add_child(sh)
		ch.add_child(body)


static var _mats := {}


static func material(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: Material
	match name:
		"hh_glass":
			var g := ShaderMaterial.new()
			g.shader = load("res://shaders/hill_glass.gdshader")
			m = g
		"hh_water":
			var w := ShaderMaterial.new()
			w.shader = load("res://shaders/hill_pool.gdshader")
			m = w
		_:
			m = HouseKit.material(name)
	_mats[name] = m
	return m


## Site-work materials (the chunk's merged boxes).
static var _site := {}


static func site_material(name: String) -> Material:
	if _site.has(name):
		return _site[name]
	var m: Material
	match name:
		"steel":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = STEEL
			sm.metallic = 0.55
			sm.roughness = 0.42
			m = sm
		"deck":
			m = PropFactory.pbr("planks", 1.6, Color(0.92, 0.80, 0.66))
		"coping":
			m = PropFactory.pbr("concrete", 2.0, Color(0.97, 0.95, 0.90))
		"stone":
			m = PropFactory.pbr("pavers", 2.5, Color(0.95, 0.90, 0.82))
		"terrace":
			m = PropFactory.pbr("plaster_beige", 2.5, Color(0.98, 0.94, 0.88))
		"concrete":
			m = PropFactory.pbr("concrete", 3.0, Color(0.88, 0.87, 0.84))
		"board_concrete":
			m = PropFactory.pbr("concrete_layers", 2.5, Color(0.95, 0.93, 0.9))
		"retain_villa":
			m = PropFactory.pbr("plaster_beige", 3.0, Color(1.0, 0.97, 0.92))
		"hedge":
			m = PropFactory.pbr("grass", 1.2, Color(0.42, 0.55, 0.32))
		"cushion":
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color(0.92, 0.91, 0.87)
			cm.roughness = 0.9
			m = cm
		_:
			m = PropFactory.material(Color.MAGENTA)
	_site[name] = m
	return m


# =================================================================================================
# The far city (Skyline)
# =================================================================================================

## How lit an estate's glass is after dark in the far city (most are; some are dark).
static func far_lit(seed: int, m: Dictionary) -> float:
	var r := _h01([seed, int(m.seed), "far_lit"])
	return 0.0 if r > 0.84 else lerpf(0.55, 1.0, r / 0.84)


## The estate's house as far-city boxes: [[Transform3D (world, the box's base on the pad), sRGB
## colour, glow, lift]] - a box per wing (lower levels too) and a glass band on each wing's view
## face that far_canopy.gdshader lights warm after dark (glow 1). `lift` is how far over the pad's
## top the box's base stands (the shader seats every part of an estate by the same amount).
static func far_boxes(plan: CityPlan, m: Dictionary) -> Array:
	var h := plan_home(plan, m)
	var out: Array = []
	var fu: Vector2 = h.fu
	var fv: Vector2 = h.fv
	var floor_y: float = h.floor
	var top: float = h.top
	var cl: Dictionary = h.colors
	for w: Dictionary in h.wings:
		var r: Rect2 = w.r
		var y0: float = floor_y + float(w.y) + maxf(float(w.base), -1.0)
		var hgt: float = float(w.storeys) * HouseKit.STOREY + (0.4 if w.roof == "flat" or w.roof == "deck" else 0.0) - maxf(float(w.base), -1.0)
		if w.role == "carport":
			hgt = HouseKit.STOREY * 0.5
		var c := frame_point(h, r.get_center())
		var wall: Color = cl.wall
		if w.mat == "h_siding":
			wall = cl.stain
		elif w.get("dark", false):
			wall = cl.dark
		var bx := Vector3(fu.x, 0.0, fu.y) * r.size.x
		var bz := Vector3(fv.x, 0.0, fv.y) * r.size.y
		out.append([Transform3D(Basis(bx, Vector3(0.0, hgt, 0.0), bz), Vector3(c.x, y0 + hgt * 0.5, c.y)), wall, 0.0, y0 - top])
		if w.roof == "hip" or w.roof == "gable":
			# A low clay cap for the roofscape.
			var rh := minf(r.size.x, r.size.y) * 0.5 * float(h.pitch) * 0.6
			out.append([Transform3D(Basis(bx * 0.92, Vector3(0.0, rh, 0.0), bz * 0.92), Vector3(c.x, y0 + hgt + rh * 0.5, c.y)), HouseKit.CLAY_FAR, 0.0, y0 + hgt - top])
		# The glass band on the view face (and the whole face's height, for a glass wall).
		if w.role != "carport" and w.role != "garage":
			var gh: float = float(w.storeys) * HouseKit.STOREY * (0.85 if "back" in (w.glass as Array) else 0.45)
			var gy0: float = floor_y + float(w.y) + 0.15
			var gc := frame_point(h, Vector2(r.get_center().x, r.end.y + 0.06))
			out.append([Transform3D(Basis(bx * 0.9, Vector3(0.0, gh, 0.0), Vector3(fv.x, 0.0, fv.y) * 0.25), Vector3(gc.x, gy0 + gh * 0.5, gc.y)), FAR_GLASS, 1.0, gy0 - top])
	var pl: Dictionary = h.pool
	if not pl.is_empty():
		var pr: Rect2 = pl.r
		var pc := frame_point(h, pr.get_center())
		out.append([Transform3D(Basis(Vector3(fu.x, 0.0, fu.y) * pr.size.x, Vector3(0.0, 0.3, 0.0), Vector3(fv.x, 0.0, fv.y) * pr.size.y), Vector3(pc.x, top + 0.15, pc.y)), Color(0.20, 0.62, 0.72), 0.0, 0.0])
	return out
