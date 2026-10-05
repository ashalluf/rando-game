class_name HouseKit
extends RefCounted
## The houses of the suburbs and the beach town (2026-10-04, the house pass: "every house lot was
## a flat-roofed box with a storefront band"). Real geometry built in code, the way ReplicaHouses
## builds the Esplanade's: walls cut round every opening with reveals, framed glass set back in
## them (shaders/house_glass.gdshader), panelled garage doors where the driveway ends, roofs hipped
## or gabled with eaves, soffits and fascias, in clay tile (ReplicaHouses' "h_roof") or asphalt
## shingle (shaders/house_shingle.gdshader), or flat. Six Los Angeles types, rolled per lot:
##   RANCH       one long low storey, a hipped or gabled shingle roof with deep eaves, an attached
##               garage at one end, a front wing now and then, stucco or lap siding, a brick chimney
##   SPANISH     white stucco, a low clay-tile roof with short eaves, a front-gabled wing with an
##               arched picture window, an arched front door, a stucco chimney
##   CRAFTSMAN   a front-gabled bungalow in lap siding: deep eaves on rafter tails, a porch across
##               the front under its own gable, tapered columns on brick piers, a drive down the side
##   MIDCENTURY  flat roof on a deep overhang or a butterfly roof, a clerestory band, a carport or a
##               garage in vertical boards, a breeze-block screen by the door
##   STUCCO_BOX  two (three by the beach) storeys of stucco, the garage in the front face, a hipped
##               clay roof or a flat one behind a parapet, a balcony over the door
##   DINGBAT     the beach town's apartment: two or three storeys over open tuck-under parking, flat
##               roof behind a parapet
## Chimneys, roof vents, solar panels on the roof face that looks south, porches, stoops.
##
## A house is planned in its yard's street frame (YardFill._frame(): u along the street, v back
## from the front edge), which faces the way YardFill.lot_front() says (the nearest street, or the
## walk street), and the plan is PURE (plan_house(): the plan, the block and the lot), so the yard
## (YardFill: the driveway runs to the garage door, the front walk to the door) and the coverage
## probe (GroundCoverage) see the very house the chunk builds. Every roll is a hash of the seed and
## the lot, never the chunk's or the block's rng.
##
## FULL chunks: every house of the chunk goes into ONE mesh per material (commit(), from the
## chunk's finish), its collision into one static body. LOD chunks and the far city's capture: the
## city's LOD box for each wing (shaders/building_lod.gdshader draws its windows) and, for a pitched
## roof, two tilted slabs in the roof colour over a wall-coloured prism that fills the gable ends -
## the same `lod_box` batch, so the far city draws the roofscape with no code of its own. The slabs
## lie on their local X face (the shader treats a local +-Y face as a flat roof and paints plant on
## it), and their bases are rotation times scale, which keeps the normals right.

## Off, house lots get Building boxes as before (the A/B: still_shot.gd HOUSES=0).
static var enabled: bool = true

const DISTRICTS := [CityPlan.District.SUBURBS, CityPlan.District.BEACHTOWN]

enum Style { RANCH, SPANISH, CRAFTSMAN, MIDCENTURY, STUCCO_BOX, DINGBAT }
const STYLE_NAMES := ["ranch", "spanish", "craftsman", "midcentury", "stucco_box", "dingbat"]
## Cumulative odds of each type, per district.
const SUBURB_STYLES := [[Style.RANCH, 0.34], [Style.SPANISH, 0.56], [Style.CRAFTSMAN, 0.72], [Style.MIDCENTURY, 0.85], [Style.STUCCO_BOX, 1.0]]
const BEACH_STYLES := [[Style.STUCCO_BOX, 0.32], [Style.SPANISH, 0.54], [Style.MIDCENTURY, 0.66], [Style.CRAFTSMAN, 0.8], [Style.DINGBAT, 0.91], [Style.RANCH, 1.0]]

# --- Sizes (metres) ---------------------------------------------------------------------------
const STOREY := 3.0
## The ground floor over the yard (a step up), and how far the walls run below it.
const FLOOR_LIFT := 0.22
const PLINTH := 0.5
## Setbacks: the front yard, the back yard and each side, suburbs and beach town.
const SUBURB_FRONT := Vector2(4.2, 7.0)
const SUBURB_BACK := Vector2(3.2, 7.5)
const SUBURB_SIDE := Vector2(1.1, 1.8)
const BEACH_FRONT := Vector2(1.4, 3.0)
const BEACH_BACK := Vector2(1.0, 3.0)
const BEACH_SIDE := Vector2(0.6, 1.1)
## A two-car and a one-car garage's width, its depth and its door's height.
const GARAGE_2 := 6.0
const GARAGE_1 := 3.5
const GARAGE_D := 6.4
const GARAGE_H := 2.25
const DOOR_W := 0.95
const DOOR_H := 2.15
## Glass set back in the wall, its frame's width.
const REVEAL := 0.12
const FRAME := 0.055
## Metres per tile of the clay roof texture (as ReplicaHouses).
const TILE_M := 4.4
const PARAPET := 0.7
## How far the solar panels and vents stand off the roof.
const PANEL_LIFT := 0.11

# --- Palettes (sRGB) ---------------------------------------------------------------------------
const STUCCO := [Color(0.95, 0.93, 0.88), Color(0.93, 0.89, 0.80), Color(0.88, 0.82, 0.71), Color(0.84, 0.77, 0.66),
	Color(0.90, 0.86, 0.80), Color(0.80, 0.80, 0.77), Color(0.93, 0.84, 0.76), Color(0.86, 0.88, 0.82), Color(0.97, 0.96, 0.93),
	Color(0.78, 0.72, 0.63)]
## The beach town's paler, sun-washed stuccos and its pastels.
const BEACH_STUCCO := [Color(0.97, 0.96, 0.93), Color(0.94, 0.91, 0.84), Color(0.86, 0.91, 0.90), Color(0.95, 0.86, 0.80),
	Color(0.90, 0.92, 0.86), Color(0.96, 0.92, 0.80), Color(0.82, 0.87, 0.90), Color(0.93, 0.89, 0.83)]
## Painted siding: sage, slate blue, olive, brown, mustard, dark green, grey, cream, barn red.
const SIDING := [Color(0.56, 0.62, 0.52), Color(0.46, 0.55, 0.62), Color(0.47, 0.47, 0.34), Color(0.45, 0.35, 0.27),
	Color(0.74, 0.62, 0.36), Color(0.28, 0.36, 0.30), Color(0.62, 0.62, 0.60), Color(0.88, 0.85, 0.76), Color(0.55, 0.27, 0.22)]
## Stained boards on a mid-century accent wall.
const STAIN := [Color(0.50, 0.34, 0.22), Color(0.36, 0.25, 0.18), Color(0.62, 0.46, 0.30)]
const TRIM := [Color(0.95, 0.94, 0.90), Color(0.92, 0.89, 0.81), Color(0.30, 0.24, 0.19), Color(0.20, 0.20, 0.20)]
## Asphalt shingle: charcoal, weathered wood grey, brown, black, slate green, desert tan.
const SHINGLE := [Color(0.27, 0.27, 0.27), Color(0.42, 0.40, 0.37), Color(0.36, 0.29, 0.23), Color(0.17, 0.17, 0.18),
	Color(0.32, 0.36, 0.33), Color(0.55, 0.48, 0.40)]
## Clay tile tints over the texture (terracotta, a darker blend, a sun-faded one, a brown one).
const CLAY := [Color(1.0, 1.0, 1.0), Color(0.86, 0.80, 0.78), Color(1.08, 1.02, 0.96), Color(0.82, 0.70, 0.62)]
## What a roof is seen as from the far tiers (sRGB, the building_lod palette): clay, by shingle.
const CLAY_FAR := Color(0.66, 0.36, 0.26)
const DOORS := [Color(0.30, 0.20, 0.14), Color(0.16, 0.15, 0.15), Color(0.52, 0.36, 0.22), Color(0.20, 0.30, 0.34),
	Color(0.55, 0.12, 0.10), Color(0.92, 0.91, 0.88)]
## The mid-century front door: orange, teal, yellow, turquoise.
const MOD_DOORS := [Color(0.86, 0.42, 0.12), Color(0.10, 0.45, 0.45), Color(0.92, 0.72, 0.18), Color(0.26, 0.62, 0.64)]
const GARAGE_DOORS := [Color(0.94, 0.93, 0.90), Color(0.88, 0.85, 0.79), Color(0.62, 0.52, 0.40), Color(0.32, 0.31, 0.30), Color(0.78, 0.74, 0.66)]
const BLINDS := [Color(0.92, 0.9, 0.84), Color(0.85, 0.82, 0.75), Color(0.6, 0.58, 0.55), Color(0.93, 0.93, 0.93), Color(0.74, 0.66, 0.56)]
const METAL := Color(0.62, 0.62, 0.60)
const IRON := Color(0.12, 0.12, 0.12)
const CONCRETE := Color(0.80, 0.78, 0.74)
const BRICK := Color(1.0, 1.0, 1.0)

## Materials: every house in a FULL chunk is one mesh per name.
const MATS := ["h_wall", "h_siding", "h_brick", "h_trim", "h_door", "h_metal", "h_dark", "h_roof", "h_shingle",
	"h_flat", "glass", "h_solar", "h_breeze"]
## Surfaces whose shadow is only cascade fill (they lie on or in something that casts already).
const NO_SHADOW := ["glass", "h_solar", "h_dark", "h_breeze"]


static func wanted(ch: CityChunk, district: int) -> bool:
	return enabled and ch.zone == MacroMap.Zone.CITY and district in DISTRICTS


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _pick(arr: Array, parts: Array) -> Variant:
	return arr[absi(hash(parts)) % arr.size()]


static func _range(v: Vector2, parts: Array) -> float:
	return lerpf(v.x, v.y, _h01(parts))


# =================================================================================================
# The plan (pure)
# =================================================================================================

## A house for a lot, in its yard's street frame. Rects are frame rects, Rect2(u0, v0, du, dv), v 0
## at the front edge of the yard. {"f", "side", "yard", "walk_front", "style", "seed", "wings":
## [{"r", "storeys", "roof" (hip, gable, flat, deck, butterfly), "ridge" (0 auto, 1 along u, 2 along
## v), "mat", "clad", "wall", "role" (main, garage, wing, carport)}], "porch": {"r", "kind" (porch,
## shed, canopy, stoop), "top"} or {}, "door": {"wing", "u", "kind"}, "garage": {"wing", "u0", "u1",
## "kind" (garage, carport, tuck)} or {}, "drive" (Vector2 u range, zero: none), "drive_v", "door_u",
## "door_v", "chimney": {"wing", "end", "mat"} or {}, "solar", "vents", "breeze" (Rect2 or zero),
## "roof_mat", "shingle_kind", "pitch", "eave", "colors": {...}, "height"}.
static func plan_house(plan: CityPlan, bx: int, bz: int, lot: Dictionary, district: int) -> Dictionary:
	var grid := YardFill.lot_grid(plan, bx, bz, [lot])
	var front := YardFill.lot_front(plan, bx, bz, lot, grid)
	return plan_fronted(plan, lot, district, front)


## plan_house() for a lot whose front the caller decides: `front` is {"side", "yard",
## "walk_front"} as YardFill.lot_front() returns it, plus an optional "styles" table in
## BEACH_STYLES' form (the canal houses, Canals, face their canal and pick their own types).
static func plan_fronted(plan: CityPlan, lot: Dictionary, district: int, front: Dictionary) -> Dictionary:
	var f := YardFill._frame(front.yard, int(front.side))
	var U: float = f.U
	var V: float = f.V
	var s: int = lot.seed
	var ps := plan.seed
	var beach := district == CityPlan.District.BEACHTOWN
	var styles: Array = front.get("styles", BEACH_STYLES if beach else SUBURB_STYLES)
	var roll := _h01([ps, s, "house_style"])
	var style: int = Style.STUCCO_BOX
	for e: Array in styles:
		if roll < float(e[1]):
			style = int(e[0])
			break
	var fs := _range(BEACH_FRONT if beach else SUBURB_FRONT, [ps, s, "setback"])
	var bs := _range(BEACH_BACK if beach else SUBURB_BACK, [ps, s, "backyard"])
	var ss := _range(BEACH_SIDE if beach else SUBURB_SIDE, [ps, s, "sideyard"])
	# A walk-street house fronts its garden on the walk: a small front yard, nothing to park.
	if front.walk_front:
		fs = minf(fs, 2.4)
	var u0 := ss
	var u1 := U - ss
	var v0 := minf(fs, V * 0.4)
	var v1 := maxf(V - bs, v0 + 5.0)
	var W := u1 - u0
	var D := v1 - v0
	var target := plan.lot_height(s, district, 0.0)
	var h := {"f": f, "side": front.side, "yard": front.yard, "walk_front": front.walk_front, "style": style, "seed": s,
		"wings": [], "porch": {}, "door": {}, "garage": {}, "drive": Vector2.ZERO, "drive_v": 0.0, "door_u": U * 0.5,
		"door_v": v0, "chimney": {}, "solar": false, "vents": 0, "breeze": Rect2(), "roof_mat": "h_shingle",
		"shingle_kind": 1 if _h01([ps, s, "laminated"]) < 0.6 else 0, "pitch": 0.33, "eave": 0.6, "beach": beach}
	# Too small a yard for a house of any type: a cottage, one wing.
	if W < 6.0 or D < 5.5:
		u0 = minf(0.6, U * 0.1)
		u1 = U - u0
		v0 = minf(1.2, V * 0.15)
		v1 = V - minf(1.0, V * 0.12)
		W = u1 - u0
		D = v1 - v0
	match style:
		Style.RANCH:
			_plan_ranch(h, ps, s, u0, u1, v0, v1)
		Style.SPANISH:
			_plan_spanish(h, ps, s, u0, u1, v0, v1, target, beach)
		Style.CRAFTSMAN:
			_plan_craftsman(h, ps, s, u0, u1, v0, v1, target)
		Style.MIDCENTURY:
			_plan_midcentury(h, ps, s, u0, u1, v0, v1)
		Style.DINGBAT:
			_plan_dingbat(h, ps, s, u0, u1, v0, v1, target)
		_:
			_plan_box(h, ps, s, u0, u1, v0, v1, target, beach)
	_fit_porch(h)
	_colors(h, ps, s, beach)
	# The height the far tiers and the tests see: the tallest wing's top.
	var top := 0.0
	for w: Dictionary in h.wings:
		var wr: Rect2 = w.r
		var t := float(w.storeys) * STOREY + FLOOR_LIFT
		if w.roof == "hip" or w.roof == "gable":
			t += minf(wr.size.x, wr.size.y) * 0.5 * float(h.pitch) + float(h.eave) * float(h.pitch)
		elif w.roof == "flat":
			t += PARAPET
		top = maxf(top, t)
	h["height"] = top
	return h


static func _wing(r: Rect2, storeys: int, roof: String, role: String, ridge: int = 0) -> Dictionary:
	return {"r": r, "storeys": storeys, "roof": roof, "ridge": ridge, "role": role, "mat": "h_wall", "clad": 1.0}


static func _rect(u0: float, v0: float, u1: float, v1: float) -> Rect2:
	return Rect2(minf(u0, u1), minf(v0, v1), absf(u1 - u0), absf(v1 - v0))


## The garage: a wing of its own at one end, `fwd` metres in front of the house line, its door
## facing the street and the drive running to it.
static func _side_garage(h: Dictionary, ps: int, s: int, u0: float, u1: float, v0: float, v1: float, gw: float, fwd: float, roof: String, kind: String = "garage") -> Array:
	var left := _h01([ps, s, "garage_side"]) < 0.5
	var gd := minf(GARAGE_D, v1 - v0)
	var gr := _rect(u0, v0 - fwd, u0 + gw, v0 - fwd + gd) if left else _rect(u1 - gw, v0 - fwd, u1, v0 - fwd + gd)
	var w := _wing(gr, 1, roof, "carport" if kind == "carport" else "garage")
	h.wings.append(w)
	var inset := 0.4 if kind == "garage" else 0.15
	h.garage = {"wing": h.wings.size() - 1, "u0": gr.position.x + inset, "u1": gr.end.x - inset, "kind": kind}
	h.drive = Vector2(gr.position.x + inset - 0.25, gr.end.x - inset + 0.25)
	h.drive_v = gr.position.y
	# What is left of the frontage for the house itself.
	return [gr.end.x, u1] if left else [u0, gr.position.x]


static func _door(h: Dictionary, wing: int, u: float, kind: String = "door") -> void:
	h.door = {"wing": wing, "u": u, "kind": kind}
	h.door_u = u
	h.door_v = (h.wings[wing].r as Rect2).position.y


## A stoop: a small concrete step in front of the door (a ground part, so the walk ends at it).
static func _stoop(h: Dictionary) -> void:
	var r := _rect(float(h.door_u) - 0.9, float(h.door_v) - 1.1, float(h.door_u) + 0.9, float(h.door_v))
	h.porch = {"r": r, "kind": "stoop", "top": FLOOR_LIFT}
	h.door_v = r.position.y


## Keeps a porch, stoop or canopy inside the yard and clear of every wing but the one its door is
## on: it gives up width away from a wing it would run into, and becomes a stoop (or nothing) when
## too little is left.
static func _fit_porch(h: Dictionary) -> void:
	if (h.porch as Dictionary).is_empty():
		return
	var pr: Rect2 = h.porch.r
	var du: float = h.door_u
	var u0 := pr.position.x
	var u1 := pr.end.x
	var v0 := maxf(pr.position.y, 0.1)
	var v1 := pr.end.y
	var dw: int = int(h.door.get("wing", -1))
	for i in (h.wings as Array).size():
		if i == dw:
			continue
		var q: Rect2 = (h.wings[i].r as Rect2)
		if q.end.y <= v0 + 0.06 or q.position.y >= v1 - 0.06:
			continue
		if q.get_center().x < du:
			u0 = maxf(u0, q.end.x + 0.05)
		else:
			u1 = minf(u1, q.position.x - 0.05)
	if u1 - u0 < 1.3 or v1 - v0 < 0.7 or du < u0 or du > u1:
		h.porch = {}
		h.door_v = v1
		return
	h.porch.r = Rect2(u0, v0, u1 - u0, v1 - v0)
	h.door_v = v0


static func _plan_ranch(h: Dictionary, ps: int, s: int, u0: float, u1: float, v0: float, v1: float) -> void:
	h.pitch = _range(Vector2(0.27, 0.36), [ps, s, "pitch"])
	h.eave = _range(Vector2(0.6, 0.85), [ps, s, "eave"])
	var roof := "hip" if _h01([ps, s, "hip"]) < 0.6 else "gable"
	var md := minf(v1 - v0, _range(Vector2(8.0, 11.0), [ps, s, "depth"]))
	var W := u1 - u0
	var hu := [u0, u1]
	if W >= 12.5:
		hu = _side_garage(h, ps, s, u0, u1, v0, v0 + md, GARAGE_2, minf(_range(Vector2(0.0, 1.6), [ps, s, "fwd"]), v0 - 1.5), roof)
	elif W >= 9.5:
		hu = _side_garage(h, ps, s, u0, u1, v0, v0 + md, GARAGE_1, 0.0, roof)
	var main := _wing(_rect(hu[0], v0, hu[1], v0 + md), 1, roof, "main")
	if _h01([ps, s, "siding"]) < 0.38:
		main.mat = "h_siding"
		main.clad = 1.0 if _h01([ps, s, "clad"]) < 0.65 else 0.5
	h.wings.append(main)
	if not h.garage.is_empty():
		h.wings[h.garage.wing].mat = main.mat
		h.wings[h.garage.wing].clad = main.clad
	var mi: int = h.wings.size() - 1
	var mw: float = float(hu[1]) - float(hu[0])
	# A front wing on the end away from the garage (the L of a ranch house).
	var garage_left: bool = not h.garage.is_empty() and (h.wings[h.garage.wing].r as Rect2).position.x < (main.r as Rect2).position.x
	if mw >= 9.0 and v0 >= 3.6 and _h01([ps, s, "ell"]) < 0.45:
		var ew := minf(mw * 0.4, 5.2)
		var ed := minf(_range(Vector2(1.8, 3.0), [ps, s, "ell_d"]), v0 - 1.4)
		var eu0: float = float(hu[1]) - ew if garage_left or h.garage.is_empty() else float(hu[0])
		h.wings.append(_wing(_rect(eu0, v0 - ed, eu0 + ew, v0 + 0.01), 1, "gable", "wing", 2))
		h.wings.back()["roof_back"] = ew * 0.5 + float(h.eave) + 0.4
		h.wings.back().mat = main.mat
		h.wings.back().clad = main.clad
		var du: float = eu0 - 1.4 if eu0 > float(hu[0]) + 1.0 else eu0 + ew + 1.4
		_door(h, mi, clampf(du, float(hu[0]) + 0.9, float(hu[1]) - 0.9))
	else:
		_door(h, mi, lerpf(float(hu[0]), float(hu[1]), 0.62 if garage_left else 0.38))
	# A shed porch over the door on half of them, else a stoop.
	if float(h.door_v) >= 2.6 and _h01([ps, s, "porch"]) < 0.5:
		var pr := _rect(float(h.door_u) - 1.6, float(h.door_v) - 1.7, float(h.door_u) + 1.6, float(h.door_v))
		h.porch = {"r": pr, "kind": "shed", "top": FLOOR_LIFT + 2.55}
		h.door_v = pr.position.y
	else:
		_stoop(h)
	h.roof_mat = "h_shingle" if _h01([ps, s, "roofmat"]) < 0.78 else "h_roof"
	if _h01([ps, s, "chimney"]) < 0.5:
		h.chimney = {"wing": mi, "end": 1 if garage_left else 0, "mat": "h_brick"}
	h.vents = 2 + absi(hash([ps, s, "vents"])) % 3
	h.solar = _h01([ps, s, "solar"]) < 0.3


static func _plan_spanish(h: Dictionary, ps: int, s: int, u0: float, u1: float, v0: float, v1: float, target: float, beach: bool) -> void:
	h.roof_mat = "h_roof"
	h.pitch = _range(Vector2(0.24, 0.32), [ps, s, "pitch"])
	h.eave = _range(Vector2(0.22, 0.38), [ps, s, "eave"])
	var storeys := 2 if (target > (8.0 if beach else 9.5) and _h01([ps, s, "two"]) < 0.7) else 1
	var roof := "gable" if _h01([ps, s, "hip"]) < 0.5 else "hip"
	var md := minf(v1 - v0, _range(Vector2(8.5, 12.0), [ps, s, "depth"]))
	var W := u1 - u0
	var hu := [u0, u1]
	if not beach and W >= 13.0 and _h01([ps, s, "garage"]) < 0.55:
		hu = _side_garage(h, ps, s, u0, u1, v0, v0 + md, GARAGE_2, 0.0, "gable")
	elif W >= 10.5 and _h01([ps, s, "garage"]) < 0.4:
		hu = _side_garage(h, ps, s, u0, u1, v0, v0 + md, GARAGE_1, 0.0, "gable")
	var main := _wing(_rect(hu[0], v0, hu[1], v0 + md), storeys, roof, "main")
	h.wings.append(main)
	var mi: int = h.wings.size() - 1
	var mw: float = float(hu[1]) - float(hu[0])
	# The front-gabled wing with the arched picture window.
	var garage_left: bool = not h.garage.is_empty() and (h.wings[h.garage.wing].r as Rect2).position.x < (main.r as Rect2).position.x
	if mw >= 8.0 and v0 >= 2.8 and _h01([ps, s, "ell"]) < 0.62:
		var ew := minf(_range(Vector2(4.2, 5.4), [ps, s, "ell_w"]), mw * 0.5)
		var ed := minf(_range(Vector2(1.6, 2.6), [ps, s, "ell_d"]), v0 - 1.0)
		var at_left := (not garage_left) if not h.garage.is_empty() else _h01([ps, s, "ell_side"]) < 0.5
		var eu0: float = float(hu[0]) if at_left else float(hu[1]) - ew
		var wing := _wing(_rect(eu0, v0 - ed, eu0 + ew, v0 + 0.01), 1, "gable", "wing", 2)
		wing["arch"] = true
		wing["roof_back"] = ew * 0.5 + float(h.eave) + 0.4
		h.wings.append(wing)
		var du: float = eu0 + ew + 1.3 if at_left else eu0 - 1.3
		_door(h, mi, clampf(du, float(hu[0]) + 0.9, float(hu[1]) - 0.9), "arch_door")
	else:
		main["arch"] = true
		_door(h, mi, lerpf(float(hu[0]), float(hu[1]), _range(Vector2(0.3, 0.45), [ps, s, "door_at"])), "arch_door")
	_stoop(h)
	if _h01([ps, s, "chimney"]) < 0.45:
		h.chimney = {"wing": mi, "end": 0 if _h01([ps, s, "ch_end"]) < 0.5 else 1, "mat": "h_wall"}
	h.vents = 0
	h.solar = _h01([ps, s, "solar"]) < 0.2


static func _plan_craftsman(h: Dictionary, ps: int, s: int, u0: float, u1: float, v0: float, v1: float, target: float) -> void:
	h.roof_mat = "h_shingle"
	h.pitch = _range(Vector2(0.36, 0.48), [ps, s, "pitch"])
	h.eave = _range(Vector2(0.75, 0.95), [ps, s, "eave"])
	var storeys := 2 if target > 10.5 and _h01([ps, s, "two"]) < 0.4 else 1
	var W := u1 - u0
	# Narrow and deep, off to one side so a drive runs down the other to the back yard.
	var left := _h01([ps, s, "garage_side"]) < 0.5
	var drive_room := W >= 10.5
	var mw := minf(_range(Vector2(7.5, 10.5), [ps, s, "width"]), W - (3.6 if drive_room else 0.0))
	var porch_d := minf(_range(Vector2(2.2, 2.8), [ps, s, "porch_d"]), maxf(v0 - 1.2, 0.0))
	var hv0 := v0
	var md := minf(v1 - hv0, _range(Vector2(10.0, 14.0), [ps, s, "depth"]))
	var hu0 := u1 - mw if left else u0
	var main := _wing(_rect(hu0, hv0, hu0 + mw, hv0 + md), storeys, "gable", "main", 2)
	main.mat = "h_siding"
	main.clad = 1.0 if _h01([ps, s, "clad"]) < 0.75 else 0.5
	h.wings.append(main)
	var mi: int = h.wings.size() - 1
	if drive_room:
		var du0 := hu0 - 3.3 if left else hu0 + mw + 0.3
		h.drive = Vector2(du0, du0 + 3.0)
		h.drive_v = minf(hv0 + md + 1.5, float((h.f as Dictionary).V))
	_door(h, mi, hu0 + mw * _range(Vector2(0.3, 0.42), [ps, s, "door_at"]) if left else hu0 + mw * _range(Vector2(0.58, 0.7), [ps, s, "door_at"]))
	if porch_d >= 1.6:
		var pw := mw * (1.0 if _h01([ps, s, "porch_w"]) < 0.55 else 0.62)
		var pu0 := hu0 if pw >= mw - 0.01 else clampf(float(h.door_u) - pw * 0.5, hu0, hu0 + mw - pw)
		var pr := _rect(pu0, hv0 - porch_d, pu0 + pw, hv0)
		h.porch = {"r": pr, "kind": "porch", "top": FLOOR_LIFT + 0.25 + 2.5}
		h.door_v = pr.position.y
	else:
		_stoop(h)
	if _h01([ps, s, "chimney"]) < 0.6:
		h.chimney = {"wing": mi, "end": 0 if left else 1, "mat": "h_brick", "side": true}
	h.vents = 1 + absi(hash([ps, s, "vents"])) % 3
	h.solar = _h01([ps, s, "solar"]) < 0.22
	h["rafters"] = true


static func _plan_midcentury(h: Dictionary, ps: int, s: int, u0: float, u1: float, v0: float, v1: float) -> void:
	h.roof_mat = "h_flat"
	h.eave = _range(Vector2(1.0, 1.5), [ps, s, "eave"])
	h.pitch = 0.16
	var butterfly := _h01([ps, s, "butterfly"]) < 0.42
	var md := minf(v1 - v0, _range(Vector2(8.5, 11.0), [ps, s, "depth"]))
	var W := u1 - u0
	var hu := [u0, u1]
	var carport := _h01([ps, s, "carport"]) < 0.45
	if W >= 12.0:
		hu = _side_garage(h, ps, s, u0, u1, v0, v0 + md, GARAGE_2, 0.0, "deck", "carport" if carport else "garage")
	elif W >= 9.5:
		hu = _side_garage(h, ps, s, u0, u1, v0, v0 + md, GARAGE_1 + 0.4, 0.0, "deck", "carport" if carport else "garage")
	var main := _wing(_rect(hu[0], v0, hu[1], v0 + md), 1, "butterfly" if butterfly else "deck", "main", 1)
	h.wings.append(main)
	var mi: int = h.wings.size() - 1
	if not h.garage.is_empty() and not carport:
		h.wings[h.garage.wing].mat = "h_siding"
		h.wings[h.garage.wing].clad = 0.0
	var garage_left: bool = not h.garage.is_empty() and (h.wings[h.garage.wing].r as Rect2).position.x < (main.r as Rect2).position.x
	var mw: float = float(hu[1]) - float(hu[0])
	_door(h, mi, float(hu[0]) + (1.4 if garage_left else mw - 1.4), "mod_door")
	h.porch = {"r": _rect(float(h.door_u) - 1.0, float(h.door_v) - 1.6, float(h.door_u) + 1.0, float(h.door_v)), "kind": "canopy", "top": FLOOR_LIFT + 2.6}
	h.door_v = (h.porch.r as Rect2).position.y
	# The breeze-block screen beside the entry, in the front garden.
	if v0 >= 3.4 and _h01([ps, s, "breeze"]) < 0.55:
		var bu := float(h.door_u) + (1.6 if garage_left else -1.6 - 3.0)
		h.breeze = _rect(bu, v0 - 2.2, bu + 3.0, v0 - 2.0)
	h.vents = 0
	h.solar = _h01([ps, s, "solar"]) < 0.25


static func _plan_box(h: Dictionary, ps: int, s: int, u0: float, u1: float, v0: float, v1: float, target: float, beach: bool) -> void:
	var storeys := 2
	if beach and target > 9.6:
		storeys = 3
	var roll := _h01([ps, s, "roof"])
	var roof := "hip" if roll < (0.62 if beach else 0.72) else "flat"
	h.roof_mat = "h_roof" if _h01([ps, s, "roofmat"]) < 0.7 else "h_shingle"
	h.shingle_kind = 1
	h.pitch = _range(Vector2(0.28, 0.36), [ps, s, "pitch"])
	h.eave = _range(Vector2(0.4, 0.6), [ps, s, "eave"])
	var md := minf(v1 - v0, _range(Vector2(9.0, 12.5), [ps, s, "depth"]))
	var main := _wing(_rect(u0, v0, u1, v0 + md), storeys, roof, "main")
	h.wings.append(main)
	var W := u1 - u0
	# The garage in the front face of the ground floor.
	var left := _h01([ps, s, "garage_side"]) < 0.5
	var gw := GARAGE_2 if W >= 11.0 else (GARAGE_1 if W >= 7.0 else 0.0)
	if gw > 0.0:
		var g0 := u0 + 0.6 if left else u1 - 0.6 - gw
		h.garage = {"wing": 0, "u0": g0 + 0.3, "u1": g0 + gw - 0.3, "kind": "garage"}
		h.drive = Vector2(g0 + 0.05, g0 + gw - 0.05)
		h.drive_v = v0
		_door(h, 0, (g0 + gw + 1.3) if left else (g0 - 1.3))
	else:
		_door(h, 0, lerpf(u0, u1, 0.5))
	main["balcony"] = _h01([ps, s, "balcony"]) < 0.45
	_stoop(h)
	h.vents = 2 if h.roof_mat == "h_shingle" else 0
	h.solar = roof == "hip" and _h01([ps, s, "solar"]) < 0.3


static func _plan_dingbat(h: Dictionary, ps: int, s: int, u0: float, u1: float, v0: float, v1: float, target: float) -> void:
	var storeys := 3 if target > 10.0 else 2
	var md := minf(v1 - v0, _range(Vector2(10.0, 14.0), [ps, s, "depth"]))
	var main := _wing(_rect(u0, v0, u1, v0 + md), storeys, "flat", "main")
	main["tuck"] = true
	h.wings.append(main)
	var W := u1 - u0
	# Open bays across the street face but for the lobby door at one end.
	var left := _h01([ps, s, "garage_side"]) < 0.5
	var lobby := 2.2
	var c0 := u0 + (lobby if left else 0.3)
	var c1 := u1 - (0.3 if left else lobby)
	h.garage = {"wing": 0, "u0": c0, "u1": c1, "kind": "tuck"}
	h.drive = Vector2(c0, c1)
	h.drive_v = v0
	_door(h, 0, (u0 + lobby * 0.5) if left else (u1 - lobby * 0.5))
	_stoop(h)
	h.roof_mat = "h_flat"
	h.vents = 0
	h.solar = false
	if W < 7.0:
		h.garage = {}
		h.drive = Vector2.ZERO


static func _colors(h: Dictionary, ps: int, s: int, beach: bool) -> void:
	var style: int = h.style
	var wall: Color = _pick(BEACH_STUCCO if beach else STUCCO, [ps, s, "stucco"])
	if style == Style.SPANISH:
		wall = _pick([Color(0.97, 0.96, 0.93), Color(0.95, 0.92, 0.85), Color(0.93, 0.88, 0.78), Color(0.96, 0.93, 0.89)], [ps, s, "stucco"])
	var siding: Color = _pick(SIDING, [ps, s, "siding_c"])
	var trim: Color = _pick(TRIM, [ps, s, "trim"])
	# Trim reads against its wall: dark trim on pale stucco is a modern look, white on siding the
	# craftsman one.
	if style == Style.CRAFTSMAN:
		trim = _pick([Color(0.95, 0.94, 0.90), Color(0.92, 0.89, 0.81), Color(0.30, 0.24, 0.19)], [ps, s, "trim"])
	elif style == Style.SPANISH:
		trim = _pick([Color(0.30, 0.20, 0.13), Color(0.95, 0.94, 0.90), Color(0.18, 0.28, 0.24)], [ps, s, "trim"])
	var frame: Color = trim if _h01([ps, s, "frame"]) < 0.6 else Color(0.93, 0.93, 0.90)
	if style == Style.MIDCENTURY or style == Style.STUCCO_BOX and _h01([ps, s, "frame"]) < 0.4:
		frame = Color(0.16, 0.16, 0.16)
	var shingle: Color = _pick(SHINGLE, [ps, s, "shingle_c"])
	var clay: Color = _pick(CLAY, [ps, s, "clay_c"])
	var door: Color = _pick(MOD_DOORS if style == Style.MIDCENTURY else DOORS, [ps, s, "door_c"])
	var garage: Color = _pick(GARAGE_DOORS, [ps, s, "garage_c"])
	var stain: Color = _pick(STAIN, [ps, s, "stain"])
	h["colors"] = {"wall": wall, "siding": siding, "trim": trim, "frame": frame, "shingle": shingle, "clay": clay,
		"door": door, "garage": garage, "stain": stain}


## The cells of a house block that hold no lot: CityPlan's lot grid rolls a gap per cell and drops
## any cell it leaves under 6 m (in the suburbs, whose gaps run to 14 m, two cells in five), which
## left them as bare lawn between the houses. Each gets a house of its own on a synthetic lot
## seeded by a hash of the cell - after the plan's own rolls, so nothing they decide moves - unless
## it is a landmark's ground, under the final approach or the freeway's right of way. PURE.
static func extra_lots(plan: CityPlan, bx: int, bz: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var b := plan.block(bx, bz)
	if b.has("site") or int(b.kind) != CityPlan.BlockKind.BUILDINGS or not (int(b.district) in DISTRICTS):
		return out
	if plan.macro and plan.macro.replica and plan.macro.replica.block_role(plan, bx, bz) != 0:
		return out
	var lots := plan.lots(bx, bz)
	if lots.is_empty():
		return out
	var grid := YardFill.lot_grid(plan, bx, bz, lots)
	var taken := {}
	for lot: Dictionary in lots:
		taken[YardFill.cell_index(grid, lot.center)] = true
	for r: Rect2 in plan.dropped_cells(bx, bz):
		taken[YardFill.cell_index(grid, r.get_center())] = true
	var blocked: Array[Rect2] = []
	if plan.macro:
		for lm in Landmarks.all():
			if lm.get("area") is Dictionary:
				continue
			var rad: float = lm.radius
			blocked.append(Rect2((lm.anchor as Vector2) - Vector2(rad, rad), Vector2(rad * 2.0, rad * 2.0)))
		blocked.append(plan.macro.runway_clear_zone())
	for j in int(grid.nz):
		for i in int(grid.nx):
			var k := Vector2i(i, j)
			if taken.has(k):
				continue
			var cell := YardFill.cell_rect(grid, k)
			var hit := false
			for bl: Rect2 in blocked:
				if bl.size.x > 0.0 and bl.intersects(cell):
					hit = true
					break
			if hit:
				continue
			var edge := i == 0 or j == 0 or i == int(grid.nx) - 1 or j == int(grid.nz) - 1
			var lot := {"seed": hash([plan.seed, bx, bz, i, j, "extra_house"]), "size": cell.size - Vector2(2.0, 2.0),
				"center": cell.get_center(), "edge": edge, "yard": false, "cell": cell, "parking": false, "extra": true}
			if YardFill.is_corridor(plan, lot):
				continue
			out.append(lot)
	return out


## The ground a house stands on, as world rects: its wings and its porch or stoop (YardFill keeps
## its yard off them, the lawn's blades keep off them).
static func ground_parts(h: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var f: Dictionary = h.f
	for w: Dictionary in h.wings:
		var r: Rect2 = w.r
		out.append(YardFill._fr(f, r.position.x, r.position.y, r.end.x, r.end.y))
	if not (h.porch as Dictionary).is_empty():
		var pr: Rect2 = h.porch.r
		out.append(YardFill._fr(f, pr.position.x, pr.position.y, pr.end.x, pr.end.y))
	return out


## What the yard plan needs of a house (YardFill._beach_lot()).
static func yard_entry(lot: Dictionary, h: Dictionary) -> Dictionary:
	return {"lot": lot, "parts": ground_parts(h), "house": {"side": h.side, "yard": h.yard, "walk_front": h.walk_front,
		"drive": h.drive, "drive_v": h.drive_v, "door_u": h.door_u, "door_v": h.door_v}}


# =================================================================================================
# Building one (a lot's build step)
# =================================================================================================

## Per-chunk accumulator: SurfaceTools by material, collision shapes, the body.
class Acc extends RefCounted:
	var st := {}
	var shapes: Array = []
	var count := 0


static func _acc(ch: CityChunk) -> Acc:
	if not ch.has_meta("house_kit"):
		ch.set_meta("house_kit", Acc.new())
	return ch.get_meta("house_kit")


## Builds one lot's house into the chunk: FULL into the chunk's house meshes, LOD and capture as
## the city's LOD boxes and roof slabs.
static func build(ch: CityChunk, h: Dictionary) -> void:
	var b := HouseBuild.new()
	b.setup(ch, h)
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		b.acc = _acc(ch)
		b.acc.count += 1
		b.full()
		# A cypress pair by the walk and the front garden's accents (LaTrees, hashes only).
		LaTrees.house(ch, h)
	else:
		b.lod()


## The chunk's finish: every house of the chunk as one mesh per material, and one static body.
static func commit(ch: CityChunk) -> void:
	if not ch.has_meta("house_kit"):
		return
	var acc: Acc = ch.get_meta("house_kit")
	ch.remove_meta("house_kit")
	for name: String in acc.st:
		var s: SurfaceTool = acc.st[name]
		var mesh := s.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "House_" + name
		mi.mesh = mesh
		mi.material_override = material(name)
		if name in NO_SHADOW:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)
	if not acc.shapes.is_empty():
		var body := StaticBody3D.new()
		body.name = "Houses"
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
		"h_wall", "h_trim", "h_door", "h_metal", "h_dark", "h_flat", "glass":
			m = ReplicaHouses.material(name)
		"h_roof":
			var sm := ReplicaHouses.material(name) as StandardMaterial3D
			# HouseKit writes roof UVs in metres (along the eave, up the slope).
			sm.uv1_scale = Vector3(1.0 / TILE_M, -1.0 / TILE_M, 1.0)
			m = sm
		"h_brick":
			var bm := (PropFactory.pbr("brick_red", 2.0, Color.WHITE) as StandardMaterial3D).duplicate() as StandardMaterial3D
			bm.vertex_color_use_as_albedo = true
			bm.vertex_color_is_srgb = true
			m = bm
		"h_shingle":
			var sh := ShaderMaterial.new()
			sh.shader = load("res://shaders/house_shingle.gdshader")
			m = sh
		"h_siding":
			var sd := ShaderMaterial.new()
			sd.shader = load("res://shaders/house_siding.gdshader")
			m = sd
		"h_breeze":
			var br := ShaderMaterial.new()
			br.shader = load("res://shaders/house_breeze.gdshader")
			m = br
		"h_solar":
			var so := StandardMaterial3D.new()
			so.vertex_color_use_as_albedo = true
			so.vertex_color_is_srgb = true
			so.metallic = 0.45
			so.roughness = 0.16
			m = so
		_:
			m = PropFactory.material(Color.MAGENTA)
	_mats[name] = m
	return m
