class_name CoastHouses
extends RefCounted
## The coast highway's beach houses as Malibu beach houses (fleet wave 8, `coast-houses`;
## docs/HANDOFF.md "The coast highway's beach houses"). CoastHighwayBuild._house() hands every FULL
## house here: the same lot (CoastHighway's plan - width, depth, deck, floors, style, garage, stair,
## roof deck, every roll as it was), the same floor slab, skirt and braced pilings
## (CoastHighwayBuild._base()), the same street face with its garage and door, the same deck and
## stair to the sand; on them a house built the way the real ones on that coast are:
##
## - a FORM per house, a hash of its seed and its style (`form()`): MODERN (flat roofs on thin
##   overhanging slabs, the upper floor set back from the sea over a terrace and often narrower and
##   slid to one side), SHED (a single-pitch metal roof rising to the sea over a tall glass wall),
##   GABLE (a shingled gable whose sea end is glazed to the ridge, a balcony under it) and HIP (a
##   low clay hip on stucco, the Mediterranean one);
## - the sea face of every storey a GLASS WALL on the hillside glass shader (hill_glass.gdshader:
##   UV in metres, a room traced at its real size behind it, lit after dark) between slim mullions;
## - decks, terraces and balconies railed in GLASS (white and stucco houses) or CABLE (timber
##   posts, a cap rail and stainless cables: the cedar and board houses);
## - LOD chunks and the far city keep CoastHighwayBuild's box (`_house_far()`), untouched.
##
## Materials are HouseKit's (h_wall, h_siding, h_trim, h_metal, h_dark, h_flat, h_roof,
## h_shingle, h_solar, glass) plus HillHomeKit's "hh_glass"; collision is boxes for the slab, each
## storey, each terrace / balcony, the deck and the stair, in CoastHighwayBuild's one body.
## Every new choice is a hash of the house's seed (never a roll on anything shared).
## `COAST_HOUSES=0` in the environment is the A/B (CoastHighwayBuild's own house).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("COAST_HOUSES") != "0"

enum Form { MODERN, SHED, GABLE, HIP }

const STOREY := CoastHighwayBuild.STOREY
const SLAB := CoastHighwayBuild.SLAB
## The glass wall: the corner piers either end, the head band over the panes, the widest pane.
const PIER := 0.22
const HEAD := 0.32
const PANE_MAX := 2.0
const MULLION := 0.06
## The flat roof's slab: thickness, and how far it overhangs the walls (sides, street, sea).
const ROOF_SLAB := 0.24
const OVER_SIDE := 0.35
const OVER_STREET := 0.45
const OVER_SEA := 1.15
## How far a MODERN upper floor sets back from the sea (metres) and its share of the lot's width.
const SETBACK := Vector2(2.3, 3.6)
const NARROW := Vector2(0.68, 0.88)
## Roofs: the shed's rise over its depth, the gable's and the hip's pitch (radians), their eaves.
const SHED_RISE := 0.16
const GABLE_PITCH := 0.56
const HIP_PITCH := 0.40
const EAVE := 0.55
## Rails: height; the cable rail's post pitch and its cables.
const RAIL_H := 1.05
const POST_PITCH := 1.5
const CABLES := 9
## A balcony on a storey with no terrace in front of it.
const BALCONY := 1.4

const METAL_ROOF := [Color(0.26, 0.27, 0.28), Color(0.40, 0.41, 0.41), Color(0.20, 0.22, 0.24)]
const CEDAR_SHINGLE := [Color(0.42, 0.38, 0.33), Color(0.36, 0.30, 0.25), Color(0.47, 0.44, 0.40)]
const CLAY := [Color(1.0, 1.0, 1.0), Color(0.90, 0.84, 0.80), Color(1.05, 0.98, 0.92)]
const DECK_BOARDS := Color(0.55, 0.40, 0.28, 0.1)
const TERRACE_STONE := Color(0.82, 0.79, 0.73)
const STEEL := Color(0.62, 0.62, 0.60)
const POST_WOOD := Color(0.42, 0.33, 0.25)
## The glass walls' rooms (sRGB, hill_glass.gdshader's COLOR): whites, oak, travertine.
const ROOM_TONES := [Color(0.86, 0.84, 0.80), Color(0.70, 0.60, 0.48), Color(0.80, 0.76, 0.70), Color(0.62, 0.50, 0.38)]


static func h01(hs: Dictionary, what: String) -> float:
	return float(absi(hash([int(hs.seed), "coast_houses", what])) % 100003) / 100003.0


## The house's form: a hash of its seed, weighted by its style (a cedar house is never stucco Med).
static func form(hs: Dictionary) -> Form:
	var r := h01(hs, "form")
	match int(hs.style):
		CoastHighway.Style.WHITE:
			return Form.MODERN if r < 0.8 else Form.SHED
		CoastHighway.Style.CEDAR:
			return Form.GABLE if r < 0.55 else (Form.SHED if r < 0.85 else Form.MODERN)
		CoastHighway.Style.BOARD:
			return Form.SHED if r < 0.5 else (Form.MODERN if r < 0.8 else Form.GABLE)
	return Form.HIP if r < 0.6 else Form.MODERN


## Cable rails on the timber houses, glass on the white and stucco ones.
static func cable_rails(hs: Dictionary) -> bool:
	var st := int(hs.style)
	if st == CoastHighway.Style.CEDAR:
		return true
	if st == CoastHighway.Style.BOARD:
		return h01(hs, "rail") < 0.8
	return h01(hs, "rail") < 0.15


## The massing (pure): the upper storey's rect in the house frame (x along the shore, z from the
## street face out to sea) - [ux0, ux1, uz1] - and the setback; the ground storey is the lot's.
static func massing(hs: Dictionary) -> Dictionary:
	var w := float(hs.z1) - float(hs.z0)
	var hw := w * 0.5
	var depth := float(hs.depth)
	var f := form(hs)
	var us := 0.0
	var ux0 := -hw
	var ux1 := hw
	if int(hs.floors) == 2:
		match f:
			Form.MODERN:
				us = lerpf(SETBACK.x, SETBACK.y, h01(hs, "setback"))
				if w >= 10.0 and h01(hs, "narrow") < 0.7:
					var uw := w * lerpf(NARROW.x, NARROW.y, h01(hs, "narrow_w"))
					if h01(hs, "slide") < 0.5:
						ux1 = ux0 + uw
					else:
						ux0 = ux1 - uw
			Form.SHED:
				us = lerpf(1.8, 3.0, h01(hs, "setback")) if h01(hs, "set") < 0.5 else 0.0
			Form.HIP:
				us = lerpf(1.6, 2.4, h01(hs, "setback")) if h01(hs, "set") < 0.35 else 0.0
	return {"form": f, "us": us, "ux0": ux0, "ux1": ux1, "uz1": depth - us}


# --- The house ---------------------------------------------------------------------------------------

static func build(chunk: CityChunk, c: CoastHighway, g: CoastHighwayBuild.Geo, hs: Dictionary) -> void:
	var xf := CoastHighwayBuild._frame(c, hs)
	var b := xf.basis
	var o := xf.origin
	var P := func(x: float, y: float, z: float) -> Vector3: return o + b.x * x + Vector3.UP * y + b.z * z
	var w := float(hs.z1) - float(hs.z0)
	var hw := w * 0.5
	var depth := float(hs.depth)
	var deck := float(hs.deck)
	var floors := int(hs.floors)
	var style := int(hs.style)
	var zc := float(hs.zc)
	var fy := c.road_y(zc) + 0.15
	var sd := int(hs.seed)
	var m := massing(hs)
	var f: Form = m.form
	var cable := cable_rails(hs)
	var wall_col := CoastHighwayBuild._wall_color(hs)
	var wall_key := "h_wall" if style == CoastHighway.Style.WHITE or style == CoastHighway.Style.STUCCO else "h_siding"
	if wall_key == "h_siding":
		wall_col.a = 0.9 if style == CoastHighway.Style.CEDAR else 0.5
	var frame_col := CoastHighwayBuild.FRAME_DARK if style != CoastHighway.Style.STUCCO else Color(0.86, 0.85, 0.82)
	var blind: Color = CoastHighwayBuild.BLINDS[sd % CoastHighwayBuild.BLINDS.size()]
	var room: Color = ROOM_TONES[absi(hash([sd, "room"])) % ROOM_TONES.size()]
	var sea := b.z
	var street := -b.z
	var side := b.x
	var B := {"g": g, "P": P, "b": b, "hs": hs, "wall_key": wall_key, "wall_col": wall_col,
		"frame": frame_col, "blind": blind, "room": room, "sd": sd, "cable": cable, "fy": fy}

	CoastHighwayBuild._base(g, P, b, hs, hw, depth, deck, fy, style)

	# --- Storeys -------------------------------------------------------------------------------
	var ux0: float = m.ux0
	var ux1: float = m.ux1
	var uz1: float = m.uz1
	var gable_or_hip := f == Form.GABLE or f == Form.HIP
	for fl in floors:
		var y0 := fy + fl * STOREY
		var y1 := y0 + STOREY
		var x0 := -hw if fl == 0 else ux0
		var x1 := hw if fl == 0 else ux1
		var fz := depth if fl == 0 else uz1
		var top_storey := fl == floors - 1
		# The shed's walls run up under its roof (low at the street, high at the sea).
		var rise := SHED_RISE * fz if f == Form.SHED and top_storey else 0.0
		# Sea face: a glass wall between corner piers, glazed up into the shed's rise.
		_glass_wall(B, x0, x1, y0, y1 + rise, fz, fl)
		# Street face: the original openings (garage, door, high window; the upper's ribbon).
		var holes := _street_holes(c, hs, fl, x0, x1, y0)
		CoastHighwayBuild._wall_holes(g, P, b, wall_key, wall_col, x0, x1, y0, y1, 0.0, street, holes, frame_col, blind, sd + fl * 7, CoastHighwayBuild.GARAGE[int(sd / 7) % CoastHighwayBuild.GARAGE.size()])
		# Sides: a window toward the sea end, more where the side faces open beach (Rc5).
		for sx: float in [-1.0, 1.0]:
			var sh: Array = []
			if fz > 7.0:
				sh.append([fz * 0.5, y0 + 1.0, fz * 0.5 + 1.2, y0 + 2.3, "window"])
			Rc5CoastHighway.side_windows(c, hs, sx, fz, y0, y1, sh)
			var xw := x1 if sx > 0.0 else x0
			CoastHighwayBuild._side_wall(g, P, b, wall_key, wall_col, xw, 0.0, fz, y0, y1, side * sx, sh, frame_col, blind, sd + fl * 13 + int(sx))
			if rise > 0.0:
				# The gable of the shed: a wedge of wall from the eave line up the roof's slope.
				g.tri(wall_key, P.call(xw, y1, 0.0), P.call(xw, y1, fz), P.call(xw, y1 + rise, fz), side * sx, wall_col, Vector2(0.0, y1), Vector2(fz, y1), Vector2(fz, y1 + rise))
		g.boxes.append([Transform3D(b, P.call((x0 + x1) * 0.5, (y0 + y1) * 0.5, fz * 0.5)), Vector3((x1 - x0) * 0.5, STOREY * 0.5, fz * 0.5)])

	# --- The lower roof: terrace, slab line, parapet --------------------------------------------
	var lower_top := fy + STOREY
	if floors == 2:
		_slab_band(B, -hw, hw, 0.0, depth, lower_top)
		_terrace(B, hw, depth, lower_top, ux0, ux1, uz1)
	# --- The top roof -----------------------------------------------------------------------------
	var top := fy + floors * STOREY
	var rx0 := -hw if floors == 1 else ux0
	var rx1 := hw if floors == 1 else ux1
	var rz1 := depth if floors == 1 else uz1
	match f:
		Form.MODERN:
			_flat_roof(B, rx0, rx1, rz1, top)
		Form.SHED:
			_shed_roof(B, rx0, rx1, rz1, top)
		Form.GABLE:
			_gable_roof(B, rx0, rx1, rz1, top)
		Form.HIP:
			_hip_roof(B, rx0, rx1, rz1, top)
	# A balcony off the top storey's glass where nothing stands in front of it (gable, hip and an
	# unset shed): a cantilevered slab on steel, railed.
	if floors == 2 and m.us < 0.1:
		var by := lower_top
		var bz1 := depth + BALCONY
		g.quad("h_siding", P.call(ux0 + 0.3, by, depth), P.call(ux1 - 0.3, by, depth), P.call(ux1 - 0.3, by, bz1), P.call(ux0 + 0.3, by, bz1), Vector3.UP, DECK_BOARDS, CoastHighwayBuild._muv(ux0, depth, ux1, bz1))
		g.box("h_trim", Transform3D(b, P.call((ux0 + ux1) * 0.5, by - 0.13, (depth + bz1) * 0.5)), Vector3((ux1 - ux0) * 0.5 - 0.3, 0.13, BALCONY * 0.5), frame_col, 63 & ~(1 << 2))
		_rail(B, P.call(ux0 + 0.35, by, bz1 - 0.05), P.call(ux1 - 0.35, by, bz1 - 0.05))
		for sx: float in [-1.0, 1.0]:
			var xs := (ux1 - 0.35) if sx > 0.0 else (ux0 + 0.35)
			_rail(B, P.call(xs, by, depth + 0.05), P.call(xs, by, bz1 - 0.05))
		g.boxes.append([Transform3D(b, P.call((ux0 + ux1) * 0.5, by - 0.12, (depth + bz1) * 0.5)), Vector3((ux1 - ux0) * 0.5 - 0.3, 0.12, BALCONY * 0.5)])

	# --- The deck over the sand, its rail and stair (the plan's) ------------------------------------
	var dz0 := depth
	var dz1 := depth + deck
	g.quad("h_siding", P.call(-hw + 0.15, fy, dz0), P.call(hw - 0.15, fy, dz0), P.call(hw - 0.15, fy, dz1), P.call(-hw + 0.15, fy, dz1), Vector3.UP, DECK_BOARDS, CoastHighwayBuild._muv(-hw, dz0, hw, dz1))
	g.box("h_trim", Transform3D(b, P.call(0.0, fy - 0.17, (dz0 + dz1) * 0.5)), Vector3(hw - 0.15, 0.16, deck * 0.5), CoastHighwayBuild.PILE_WOOD, 63 & ~(1 << 2))
	g.boxes.append([Transform3D(b, P.call(0.0, fy - 0.15, (dz0 + dz1) * 0.5)), Vector3(hw - 0.15, 0.15, deck * 0.5)])
	var stair := bool(hs.stair)
	var sx_side := float(hs.stair_side)
	var gap_x := sx_side * (hw - 0.9)
	if stair:
		if gap_x - 0.55 > -hw + 0.4:
			_rail(B, P.call(-hw + 0.2, fy, dz1 - 0.05), P.call(gap_x - 0.55, fy, dz1 - 0.05))
		if hw - 0.2 > gap_x + 0.55 + 0.2:
			_rail(B, P.call(gap_x + 0.55, fy, dz1 - 0.05), P.call(hw - 0.2, fy, dz1 - 0.05))
		CoastHighwayBuild._stair(g, P, b, gap_x, dz1, fy, 0.45, sea)
	else:
		_rail(B, P.call(-hw + 0.2, fy, dz1 - 0.05), P.call(hw - 0.2, fy, dz1 - 0.05))
	for sx: float in [-1.0, 1.0]:
		_rail(B, P.call(sx * (hw - 0.2), fy, dz0 + 0.05), P.call(sx * (hw - 0.2), fy, dz1 - 0.05))
	# Deck life: a pair of loungers or a table and chairs (a hash), an outdoor shower post by the
	# stair, a few pots.
	_deck_life(B, hw, dz0, dz1, fy, stair, gap_x)

	# --- The street side ---------------------------------------------------------------------------
	g.box("h_dark", Transform3D(b, P.call(-hw + 0.6, fy + 2.0, -0.04)), Vector3(0.22, 0.12, 0.02), Color(0.1, 0.1, 0.1))
	Rc5CoastHighway.dress_house(chunk, c, g, hs, wall_col)


## The street face's openings, as CoastHighwayBuild._house() lays them on the ground floor (the
## garage where the plan put it, the door beside it, a high window) and on the upper floor a
## clerestory ribbon or a row of tall windows, within the storey's own width.
static func _street_holes(c: CoastHighway, hs: Dictionary, fl: int, x0: float, x1: float, y0: float) -> Array:
	var holes: Array = []
	var w := float(hs.z1) - float(hs.z0)
	var hw := w * 0.5
	var zc := float(hs.zc)
	var sd := int(hs.seed)
	if fl == 0:
		if bool(hs.garage) and w > 7.0:
			var gz := c.garage_z(hs) - zc
			holes.append([gz - 1.5, y0, gz + 1.5, y0 + 2.35, "garage"])
			var dx := gz + (2.6 if gz < 0.0 else -2.6)
			if absf(dx) < hw - 0.8:
				holes.append([dx - 0.5, y0, dx + 0.5, y0 + 2.25, "door"])
			var used: Array = []
			for h: Array in holes:
				used.append([float(h[0]) - 0.45, float(h[2]) + 0.45])
			used.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
			var best := [0.0, 0.0]
			var at := -hw + 0.5
			for u: Array in used + [[hw - 0.5, hw]]:
				if float(u[0]) - at > best[1] - best[0]:
					best = [at, float(u[0])]
				at = maxf(at, float(u[1]))
			if best[1] - best[0] >= 1.4:
				holes.append([best[0], y0 + 1.55, minf(best[1], best[0] + 3.2), y0 + 2.3, "window"])
		else:
			holes.append([-0.55, y0, 0.55, y0 + 2.25, "door"])
			holes.append([1.4, y0 + 1.6, minf(hw - 0.6, 4.4), y0 + 2.5, "window"])
		return holes
	var uw := x1 - x0
	if (sd >> 3) % 2 == 0 and uw > 6.0:
		holes.append([x0 + 0.9, y0 + 1.75, x1 - 0.9, y0 + 2.55, "window"])
	else:
		var nwin := maxi(1, int(uw / 3.4))
		for k in nwin:
			var cx := lerpf(x0, x1, (float(k) + 0.5) / nwin)
			holes.append([cx - 0.65, y0 + 0.9, cx + 0.65, y0 + 2.55, "window"])
	return holes


## A storey's sea face (z = `z`, x0..x1, y0..y1): corner piers, a head band, and between them
## floor-to-ceiling glass on hill_glass.gdshader in panes up to PANE_MAX wide, set back in a
## reveal, with slim dark mullions and a threshold: sliding doors to the deck.
static func _glass_wall(B: Dictionary, x0: float, x1: float, y0: float, y1: float, z: float, fl: int) -> void:
	var g: CoastHighwayBuild.Geo = B.g
	var P: Callable = B.P
	var b: Basis = B.b
	var sea := b.z
	var key: String = B.wall_key
	var col: Color = B.wall_col
	var fcol: Color = B.frame
	var gx0 := x0 + PIER
	var gx1 := x1 - PIER
	var head := y0 + STOREY - HEAD
	# The piers and the head band, in the wall's own cladding.
	g.quad(key, P.call(x0, y0, z), P.call(gx0, y0, z), P.call(gx0, y1, z), P.call(x0, y1, z), sea, col, CoastHighwayBuild._muv(0.0, y0, PIER, y1))
	g.quad(key, P.call(gx1, y0, z), P.call(x1, y0, z), P.call(x1, y1, z), P.call(gx1, y1, z), sea, col, CoastHighwayBuild._muv(0.0, y0, PIER, y1))
	var glass_top := y1 - 0.08 if y1 - y0 > STOREY + 0.2 else head
	if glass_top < y1 - 0.01:
		g.quad(key, P.call(gx0, glass_top, z), P.call(gx1, glass_top, z), P.call(gx1, y1, z), P.call(gx0, y1, z), sea, col, CoastHighwayBuild._muv(gx0, glass_top, gx1, y1))
	# The glass, set 0.12 m back, and its reveals.
	var rz := z - 0.12
	var floor_y := y0
	var panes := maxi(2, ceili((gx1 - gx0) / PANE_MAX))
	var room: Color = B.room
	for k in panes:
		var a := lerpf(gx0, gx1, float(k) / panes)
		var e := lerpf(gx0, gx1, float(k + 1) / panes)
		var tone := room
		tone.a = float(absi(hash([int(B.sd), fl, k, "pane"])) % 997) / 997.0
		g.quad("hh_glass", P.call(a, y0 + 0.04, rz), P.call(e, y0 + 0.04, rz), P.call(e, glass_top, rz), P.call(a, glass_top, rz), sea, tone,
			[Vector2(a - gx0, 0.04), Vector2(e - gx0, 0.04), Vector2(e - gx0, glass_top - floor_y), Vector2(a - gx0, glass_top - floor_y)], b.x)
		if k > 0:
			g.box("h_trim", Transform3D(b, P.call(a, (y0 + glass_top) * 0.5, rz + 0.03)), Vector3(MULLION * 0.5, (glass_top - y0) * 0.5, 0.04), fcol)
	# Frame: sill / threshold, head, the jambs; the reveals back to the face.
	g.box("h_trim", Transform3D(b, P.call((gx0 + gx1) * 0.5, y0 + 0.03, rz + 0.03)), Vector3((gx1 - gx0) * 0.5, 0.03, 0.06), fcol)
	g.box("h_trim", Transform3D(b, P.call((gx0 + gx1) * 0.5, glass_top - 0.03, rz + 0.03)), Vector3((gx1 - gx0) * 0.5, 0.03, 0.05), fcol)
	g.quad(key, P.call(gx0, glass_top, z), P.call(gx1, glass_top, z), P.call(gx1, glass_top, rz), P.call(gx0, glass_top, rz), Vector3.DOWN, col)
	g.quad(key, P.call(gx0, y0, z), P.call(gx0, glass_top, z), P.call(gx0, glass_top, rz), P.call(gx0, y0, rz), b.x, col)
	g.quad(key, P.call(gx1, y0, z), P.call(gx1, glass_top, z), P.call(gx1, glass_top, rz), P.call(gx1, y0, rz), -b.x, col)


## The slab line round the lower storey's roof: a fascia band and the roof's edge over the walls.
static func _slab_band(B: Dictionary, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	var g: CoastHighwayBuild.Geo = B.g
	var P: Callable = B.P
	var b: Basis = B.b
	var band := Color(0.93, 0.93, 0.91) if int(B.hs.style) != CoastHighway.Style.CEDAR else CoastHighwayBuild.PILE_WOOD
	# Sea edge, and the two side edges out to it: 0.28 m deep, 4 cm proud.
	g.box("h_trim", Transform3D(b, P.call((x0 + x1) * 0.5, y + 0.02, z1 + 0.04)), Vector3((x1 - x0) * 0.5 + 0.04, 0.16, 0.04), band)
	for sx: float in [-1.0, 1.0]:
		var xs := x1 + 0.04 if sx > 0.0 else x0 - 0.04
		g.box("h_trim", Transform3D(b, P.call(xs, y + 0.02, (z0 + z1) * 0.5)), Vector3(0.04, 0.16, (z1 - z0) * 0.5 + 0.04), band)
	g.box("h_trim", Transform3D(b, P.call((x0 + x1) * 0.5, y + 0.02, z0 - 0.04)), Vector3((x1 - x0) * 0.5 + 0.04, 0.16, 0.04), band)


## The terrace on the lower roof wherever the upper storey does not stand: decking (or pavers on
## the stucco houses) over the membrane, a rail round its open edges, a parapet to the street on a
## side strip (the highway is right there).
static func _terrace(B: Dictionary, hw: float, depth: float, y: float, ux0: float, ux1: float, uz1: float) -> void:
	var g: CoastHighwayBuild.Geo = B.g
	var P: Callable = B.P
	var b: Basis = B.b
	var stone := int(B.hs.style) == CoastHighway.Style.STUCCO or int(B.hs.style) == CoastHighway.Style.WHITE
	var key := "h_flat" if stone else "h_siding"
	var tcol := TERRACE_STONE if stone else DECK_BOARDS
	var rects: Array = []
	if depth - uz1 > 0.05:
		rects.append([-hw, depth - (depth - uz1), hw, depth])
	if ux0 > -hw + 0.05:
		rects.append([-hw, 0.0, ux0, uz1])
	if ux1 < hw - 0.05:
		rects.append([ux1, 0.0, hw, uz1])
	for r: Array in rects:
		var x0: float = r[0]
		var z0: float = r[1]
		var x1: float = r[2]
		var z1: float = r[3]
		g.quad(key, P.call(x0, y + 0.02, z0), P.call(x1, y + 0.02, z0), P.call(x1, y + 0.02, z1), P.call(x0, y + 0.02, z1), Vector3.UP, tcol, CoastHighwayBuild._muv(x0, z0, x1, z1))
		g.boxes.append([Transform3D(b, P.call((x0 + x1) * 0.5, y - 0.1, (z0 + z1) * 0.5)), Vector3((x1 - x0) * 0.5, 0.12, (z1 - z0) * 0.5)])
	var ry := y + 0.02
	# The sea edge, then each side where the terrace reaches it.
	if depth - uz1 > 0.05 or ux0 > -hw + 0.05 or ux1 < hw - 0.05:
		_rail(B, P.call(-hw + 0.08, ry, depth - 0.08), P.call(hw - 0.08, ry, depth - 0.08))
	for sx: float in [-1.0, 1.0]:
		var open := (ux0 > -hw + 0.05) if sx < 0.0 else (ux1 < hw - 0.05)
		var from_z := 0.6 if open else uz1
		if depth - 0.08 - from_z > 0.3:
			_rail(B, P.call(sx * (hw - 0.08), ry, from_z), P.call(sx * (hw - 0.08), ry, depth - 0.08))
		if open:
			# A solid parapet to the street across the side strip.
			var xa := -hw if sx < 0.0 else ux1
			var xb := ux0 if sx < 0.0 else hw
			var key2: String = B.wall_key
			var col: Color = B.wall_col
			g.quad(key2, P.call(xa, y, 0.0), P.call(xb, y, 0.0), P.call(xb, y + 1.1, 0.0), P.call(xa, y + 1.1, 0.0), -b.z, col, CoastHighwayBuild._muv(xa, y, xb, y + 1.1))
			g.quad(key2, P.call(xa, y, 0.2), P.call(xb, y, 0.2), P.call(xb, y + 1.1, 0.2), P.call(xa, y + 1.1, 0.2), b.z, col, CoastHighwayBuild._muv(xa, y, xb, y + 1.1))
			g.quad(key2, P.call(xa, y + 1.1, 0.0), P.call(xb, y + 1.1, 0.0), P.call(xb, y + 1.1, 0.2), P.call(xa, y + 1.1, 0.2), Vector3.UP, col, CoastHighwayBuild._muv(xa, 0.0, xb, 0.2))
			g.boxes.append([Transform3D(b, P.call((xa + xb) * 0.5, y + 0.55, 0.1)), Vector3((xb - xa) * 0.5, 0.55, 0.1)])
	# A table and chairs or two loungers on the terrace's sea strip.
	if depth - uz1 > 1.8:
		_furniture(B, -hw + 0.6, hw - 0.6, uz1 + 0.3, depth - 0.5, y + 0.02, "terrace")


## A flat roof: a thin slab overhanging every wall, deepest over the sea; a membrane on it, the
## rooftop rail when the plan put a roof deck up there, solar on some.
static func _flat_roof(B: Dictionary, x0: float, x1: float, z1: float, top: float) -> void:
	var g: CoastHighwayBuild.Geo = B.g
	var P: Callable = B.P
	var b: Basis = B.b
	var hs: Dictionary = B.hs
	var fcol := Color(0.93, 0.93, 0.91) if int(hs.style) == CoastHighway.Style.WHITE else Color(0.18, 0.19, 0.20)
	var ax0 := x0 - OVER_SIDE
	var ax1 := x1 + OVER_SIDE
	var az0 := -OVER_STREET
	var az1 := z1 + OVER_SEA
	var cx := (ax0 + ax1) * 0.5
	var cz := (az0 + az1) * 0.5
	g.box("h_trim", Transform3D(b, P.call(cx, top + ROOF_SLAB * 0.5, cz)), Vector3((ax1 - ax0) * 0.5, ROOF_SLAB * 0.5, (az1 - az0) * 0.5), fcol, 63 & ~(1 << 2))
	g.quad("h_flat", P.call(ax0, top + ROOF_SLAB, az0), P.call(ax1, top + ROOF_SLAB, az0), P.call(ax1, top + ROOF_SLAB, az1), P.call(ax0, top + ROOF_SLAB, az1), Vector3.UP, Color(0.74, 0.73, 0.70))
	_roof_kit(B, x0, x1, z1, top + ROOF_SLAB)
	if bool(hs.roof_deck):
		_rail(B, P.call(x0 + 0.2, top + ROOF_SLAB, z1 - 0.2), P.call(x1 - 0.2, top + ROOF_SLAB, z1 - 0.2))
		for sx: float in [-1.0, 1.0]:
			var xs := x1 - 0.2 if sx > 0.0 else x0 + 0.2
			_rail(B, P.call(xs, top + ROOF_SLAB, z1 * 0.45), P.call(xs, top + ROOF_SLAB, z1 - 0.2))
		# The stair head up to it: a small box at the street end.
		var sx0 := x0 + 0.4
		g.box(B.wall_key, Transform3D(b, P.call(sx0 + 1.1, top + ROOF_SLAB + 1.2, 1.4)), Vector3(1.1, 1.2, 1.3), B.wall_col)
		g.box("h_trim", Transform3D(b, P.call(sx0 + 1.1, top + ROOF_SLAB + 2.45, 1.4)), Vector3(1.25, 0.06, 1.45), fcol)


## The shed roof: one plane from the street (at `top`) up to the sea, rising SHED_RISE of the
## depth, standing-seam metal on deep eaves with a fascia; clerestory glass went up the sea face.
static func _shed_roof(B: Dictionary, x0: float, x1: float, z1: float, top: float) -> void:
	var g: CoastHighwayBuild.Geo = B.g
	var P: Callable = B.P
	var b: Basis = B.b
	var rise := SHED_RISE * z1
	var slope := rise / maxf(z1, 0.1)
	var col: Color = METAL_ROOF[absi(hash([int(B.sd), "metal"])) % METAL_ROOF.size()]
	var ax0 := x0 - OVER_SIDE
	var ax1 := x1 + OVER_SIDE
	var az0 := -OVER_STREET
	var az1 := z1 + OVER_SEA
	var y_at := func(z: float) -> float: return top + 0.18 + z * slope
	var n := (Vector3.UP - b.z * slope).normalized()
	var ya: float = y_at.call(az0)
	var ye: float = y_at.call(az1)
	var up_len := (az1 - az0) * sqrt(1.0 + slope * slope)
	g.quad("h_metal", P.call(ax0, ya, az0), P.call(ax1, ya, az0), P.call(ax1, ye, az1), P.call(ax0, ye, az1), n, col,
		[Vector2(0.0, 0.0), Vector2(ax1 - ax0, 0.0), Vector2(ax1 - ax0, up_len), Vector2(0.0, up_len)])
	# Standing seams every 0.45 m down the slope: thin ribs.
	var seams := int((ax1 - ax0) / 0.45)
	for k in range(1, seams):
		var sx := lerpf(ax0, ax1, float(k) / seams)
		g.quad("h_metal", P.call(sx - 0.012, ya + 0.03, az0), P.call(sx + 0.012, ya + 0.03, az0), P.call(sx + 0.012, ye + 0.03, az1), P.call(sx - 0.012, ye + 0.03, az1), n, col.darkened(0.25))
	# Fascia and the soffit under it (timber on the cedar ones).
	var fcol := CoastHighwayBuild.PILE_WOOD if int(B.hs.style) == CoastHighway.Style.CEDAR else Color(0.2, 0.21, 0.22)
	for e: Array in [[ax0, az0, ax1, az0, -b.z], [ax0, az1, ax1, az1, b.z]]:
		var y: float = y_at.call(float(e[1]))
		g.quad("h_trim", P.call(e[0], y - 0.22, e[1]), P.call(e[2], y - 0.22, e[3]), P.call(e[2], y + 0.02, e[3]), P.call(e[0], y + 0.02, e[1]), e[4], fcol)
	for sx: float in [-1.0, 1.0]:
		var xs := ax1 if sx > 0.0 else ax0
		g.quad("h_trim", P.call(xs, ya - 0.22, az0), P.call(xs, ye - 0.22, az1), P.call(xs, ye + 0.02, az1), P.call(xs, ya + 0.02, az0), b.x * sx, fcol)
	g.quad("h_trim", P.call(ax0, ya - 0.2, az0), P.call(ax1, ya - 0.2, az0), P.call(ax1, ye - 0.2, az1), P.call(ax0, ye - 0.2, az1), -n, Color(0.82, 0.78, 0.70))
	# Exposed rafter tails under the sea eave, on the timber houses.
	if int(B.hs.style) != CoastHighway.Style.WHITE:
		var k2 := int((x1 - x0) / 1.2)
		for k in k2 + 1:
			var rx := lerpf(x0 + 0.1, x1 - 0.1, float(k) / maxf(1.0, k2))
			var yz: float = y_at.call(z1 + OVER_SEA * 0.5)
			g.box("h_trim", Transform3D(b, P.call(rx, yz - 0.3, z1 + OVER_SEA * 0.5)), Vector3(0.05, 0.1, OVER_SEA * 0.5), fcol)
	if h01(B.hs, "solar") < 0.45:
		_solar(B, x0 + 0.6, x1 - 0.6, 0.8, z1 * 0.55, top, slope)


## The gable: the ridge along the house from the street to the sea, cedar shingles, the sea gable
## glazed to the ridge between timber posts, the street gable clad.
static func _gable_roof(B: Dictionary, x0: float, x1: float, z1: float, top: float) -> void:
	var g: CoastHighwayBuild.Geo = B.g
	var P: Callable = B.P
	var b: Basis = B.b
	var hw := (x1 - x0) * 0.5
	var xc := (x0 + x1) * 0.5
	var t := tan(GABLE_PITCH)
	var rise := hw * t
	var ridge := top + rise
	var ex := EAVE
	var eave_y := top - ex * t
	var col: Color = CEDAR_SHINGLE[absi(hash([int(B.sd), "shingle"])) % CEDAR_SHINGLE.size()]
	col.a = 0.75
	var z_a := -OVER_STREET
	var z_b := z1 + EAVE
	var slope_len := (hw + ex) / cos(GABLE_PITCH)
	for sx: float in [-1.0, 1.0]:
		var xe := xc + sx * (hw + ex)
		var n := (Vector3.UP * cos(GABLE_PITCH) + b.x * sx * sin(GABLE_PITCH)).normalized()
		g.quad("h_shingle", P.call(xe, eave_y, z_a), P.call(xe, eave_y, z_b), P.call(xc, ridge, z_b), P.call(xc, ridge, z_a), n, col,
			[Vector2(0.0, 0.0), Vector2(z_b - z_a, 0.0), Vector2(z_b - z_a, slope_len), Vector2(0.0, slope_len)])
		# Fascia (bargeboards) along the eave and up each gable.
		g.box("h_trim", Transform3D(b, P.call(xe, eave_y - 0.1, (z_a + z_b) * 0.5)), Vector3(0.04, 0.12, (z_b - z_a) * 0.5), B.frame)
	g.box("h_shingle", Transform3D(b, P.call(xc, ridge + 0.04, (z_a + z_b) * 0.5)), Vector3(0.14, 0.05, (z_b - z_a) * 0.5), Color(col.r * 0.85, col.g * 0.85, col.b * 0.85, col.a))
	# Soffits under each slope.
	for sx: float in [-1.0, 1.0]:
		var xe := xc + sx * (hw + ex)
		var xw := xc + sx * hw
		g.quad("h_trim", P.call(xw, top, z_a), P.call(xw, top, z_b), P.call(xe, eave_y, z_b), P.call(xe, eave_y, z_a), Vector3.DOWN, Color(0.84, 0.80, 0.72))
	# The street gable: clad. The sea gable: glass to the ridge.
	g.tri(B.wall_key, P.call(x0, top, 0.0), P.call(x1, top, 0.0), P.call(xc, ridge, 0.0), -b.z, B.wall_col, Vector2(x0, top), Vector2(x1, top), Vector2(xc, ridge))
	var tone: Color = B.room
	tone.a = 0.5
	var rz := z1 - 0.12
	var fl := top - STOREY
	g.tri("hh_glass", P.call(x0 + 0.2, top, rz), P.call(x1 - 0.2, top, rz), P.call(xc, ridge - 0.2, rz), b.z, tone,
		Vector2(0.2, top - fl), Vector2(x1 - x0 - 0.2, top - fl), Vector2(hw, ridge - 0.2 - fl), b.x)
	# Its frame: a beam at the eave line, a king post, the rakes.
	g.box("h_trim", Transform3D(b, P.call(xc, top + 0.06, z1 - 0.06)), Vector3(hw, 0.08, 0.08), B.frame)
	g.box("h_trim", Transform3D(b, P.call(xc, (top + ridge) * 0.5, z1 - 0.06)), Vector3(0.05, (ridge - top) * 0.5, 0.06), B.frame)
	for sx: float in [-1.0, 1.0]:
		var a: Vector3 = P.call(xc + sx * hw, top, z1 + 0.02)
		var e: Vector3 = P.call(xc, ridge, z1 + 0.02)
		var d := (e - a).normalized()
		var wv := d.cross(b.z).normalized() * 0.08
		g.quad("h_trim", a - wv, a + wv, e + wv, e - wv, b.z, B.frame)
	# The wedge of wall either side between the storey's top and the gable's triangle is in the roof.
	_roof_kit(B, x0, x1, z1, ridge - 0.01, true)


## The low hip of the stucco houses: clay tile on four planes to a ridge along the longer side, a
## ridge cap, a plastered soffit.
static func _hip_roof(B: Dictionary, x0: float, x1: float, z1: float, top: float) -> void:
	var g: CoastHighwayBuild.Geo = B.g
	var P: Callable = B.P
	var b: Basis = B.b
	var col: Color = CLAY[absi(hash([int(B.sd), "clay"])) % CLAY.size()]
	var t := tan(HIP_PITCH)
	var u0 := x0 - EAVE
	var u1 := x1 + EAVE
	var v0 := -EAVE
	var v1 := z1 + EAVE
	var y := top - EAVE * t
	var wu := u1 - u0
	var wv := v1 - v0
	var along_u := wu >= wv
	var half := (minf(wu, wv)) * 0.5
	var ry := y + half * t
	var r0: Vector2
	var r1: Vector2
	if along_u:
		r0 = Vector2(u0 + half, (v0 + v1) * 0.5)
		r1 = Vector2(u1 - half, (v0 + v1) * 0.5)
	else:
		r0 = Vector2((u0 + u1) * 0.5, v0 + half)
		r1 = Vector2((u0 + u1) * 0.5, v1 - half)
	var c00 := Vector2(u0, v0)
	var c10 := Vector2(u1, v0)
	var c11 := Vector2(u1, v1)
	var c01 := Vector2(u0, v1)
	var L := func(p: Vector2, yy: float) -> Vector3: return P.call(p.x, yy, p.y)
	# Planes: each edge of the rect up to the ridge end(s) nearest it.
	var planes: Array = []
	if along_u:
		planes = [[c00, c10, r1, r0, Vector2(0, -1)], [c11, c01, r0, r1, Vector2(0, 1)], [c01, c00, r0, r0, Vector2(-1, 0)], [c10, c11, r1, r1, Vector2(1, 0)]]
	else:
		planes = [[c01, c00, r0, r1, Vector2(-1, 0)], [c10, c11, r1, r0, Vector2(1, 0)], [c00, c10, r0, r0, Vector2(0, -1)], [c11, c01, r1, r1, Vector2(0, 1)]]
	for pl: Array in planes:
		var a: Vector2 = pl[0]
		var e: Vector2 = pl[1]
		var p2: Vector2 = pl[2]
		var p3: Vector2 = pl[3]
		var out: Vector2 = pl[4]
		var n3 := (b.x * out.x + b.z * out.y) * t + Vector3.UP
		var ed := (e - a).normalized()
		var up_len := half / cos(HIP_PITCH)
		var uvf := func(p: Vector2, yy: float) -> Vector2: return Vector2((p - a).dot(ed), (yy - y) / maxf(ry - y, 0.001) * up_len)
		if p2.distance_to(p3) < 0.01:
			g.tri("h_roof", L.call(a, y), L.call(e, y), L.call(p2, ry), n3, col, uvf.call(a, y), uvf.call(e, y), uvf.call(p2, ry))
		else:
			g.quad("h_roof", L.call(a, y), L.call(e, y), L.call(p2, ry), L.call(p3, ry), n3, col, [uvf.call(a, y), uvf.call(e, y), uvf.call(p2, ry), uvf.call(p3, ry)])
	# Ridge cap and the soffit.
	var rm := (r0 + r1) * 0.5
	var rd := r1 - r0
	var rlen := maxf(rd.length(), 0.2)
	var bx := Basis(b.x if along_u else b.z, Vector3.UP, b.z if along_u else -b.x)
	g.box("h_roof", Transform3D(bx, L.call(rm, ry + 0.04)), Vector3(rlen * 0.5 + 0.1, 0.07, 0.13), col.darkened(0.08))
	g.quad("h_wall", L.call(c00, y), L.call(c10, y), L.call(c11, y), L.call(c01, y), Vector3.DOWN, B.wall_col)
	for e: Array in [[c00, c10, -b.z], [c10, c11, b.x], [c11, c01, b.z], [c01, c00, -b.x]]:
		var a: Vector3 = L.call(e[0], y)
		var f: Vector3 = L.call(e[1], y)
		g.quad("h_trim", a + Vector3.DOWN * 0.16, f + Vector3.DOWN * 0.16, f, a, e[2], Color(0.86, 0.85, 0.82))


## What stands on a roof: a flue, a rooftop condenser in a screen, and (on some) a solar array.
static func _roof_kit(B: Dictionary, x0: float, x1: float, z1: float, y: float, pitched := false) -> void:
	var g: CoastHighwayBuild.Geo = B.g
	var P: Callable = B.P
	var b: Basis = B.b
	var hw := (x1 - x0) * 0.5
	var xc := (x0 + x1) * 0.5
	if pitched:
		g.box("h_metal", Transform3D(b, P.call(xc + hw * 0.45, y - 0.6, z1 * 0.3)), Vector3(0.12, 0.9, 0.12), Color(0.45, 0.45, 0.45))
		return
	g.box("h_metal", Transform3D(b, P.call(xc + hw * 0.45, y + 0.45, z1 * 0.3)), Vector3(0.12, 0.45, 0.12), Color(0.5, 0.5, 0.5))
	if h01(B.hs, "unit") < 0.6:
		g.box("h_metal", Transform3D(b, P.call(xc - hw * 0.4, y + 0.42, z1 * 0.35)), Vector3(0.55, 0.42, 0.4), Color(0.78, 0.78, 0.76))
		g.box("h_dark", Transform3D(b, P.call(xc - hw * 0.4, y + 0.86, z1 * 0.35)), Vector3(0.28, 0.02, 0.28), Color(0.12, 0.12, 0.12))
	if h01(B.hs, "solar") < 0.4 and not bool(B.hs.roof_deck):
		_solar(B, x0 + 0.5, x1 - 0.5, z1 * 0.5, z1 - 0.6, y - 0.18, 0.0)


## Panels on rails, tilted 10 degrees to the sky (or lying on a shed's slope).
static func _solar(B: Dictionary, x0: float, x1: float, z0: float, z1: float, top: float, slope: float) -> void:
	var g: CoastHighwayBuild.Geo = B.g
	var P: Callable = B.P
	var b: Basis = B.b
	var cols := maxi(1, int((x1 - x0) / 1.05))
	var rows := maxi(1, int((z1 - z0) / 1.75))
	for i in cols:
		for j in rows:
			var cx := lerpf(x0, x1, (float(i) + 0.5) / cols)
			var cz := lerpf(z0, z1, (float(j) + 0.5) / rows)
			var yy := top + 0.18 + cz * slope + 0.1
			var tilt := atan(slope) if slope > 0.0 else 0.17
			var basis := b * Basis(Vector3.RIGHT, -tilt)
			g.box("h_solar", Transform3D(basis, P.call(cx, yy, cz)), Vector3(0.49, 0.02, 0.83), Color(0.10, 0.13, 0.20))


## A rail between two world points on a deck or a terrace: glass in a steel cap, or cable.
static func _rail(B: Dictionary, a: Vector3, e: Vector3) -> void:
	if not bool(B.cable):
		CoastHighwayBuild._rail_run(B.g, a, e)
		return
	var g: CoastHighwayBuild.Geo = B.g
	var dir := e - a
	var len := dir.length()
	if len < 0.2:
		return
	var d := dir / len
	var n := d.cross(Vector3.UP).normalized()
	var timber := int(B.hs.style) == CoastHighway.Style.CEDAR
	var post_col := POST_WOOD if timber else Color(0.20, 0.20, 0.21)
	var post_key := "h_trim" if timber else "h_metal"
	var posts := maxi(1, ceili(len / POST_PITCH))
	var bx := Basis(d, Vector3.UP, n)
	for k in posts + 1:
		var p := a.lerp(e, float(k) / posts)
		g.box(post_key, Transform3D(bx, p + Vector3.UP * RAIL_H * 0.5), Vector3(0.045, RAIL_H * 0.5, 0.045), post_col)
	# The cap rail, timber, a little wider than the posts.
	g.box("h_trim", Transform3D(bx, (a + e) * 0.5 + Vector3.UP * (RAIL_H + 0.025)), Vector3(len * 0.5 + 0.05, 0.025, 0.07), POST_WOOD if timber else Color(0.48, 0.38, 0.28))
	# The cables: 9 lines 9 cm apart, each a thin ribbon both ways.
	for k in CABLES:
		var y := 0.12 + float(k) * (RAIL_H - 0.2) / float(CABLES - 1)
		var p0 := a + Vector3.UP * y
		var p1 := e + Vector3.UP * y
		var t := Vector3.UP * 0.004
		g.quad("h_metal", p0 - t, p1 - t, p1 + t, p0 + t, n, STEEL)
		g.quad("h_metal", p0 - t, p1 - t, p1 + t, p0 + t, -n, STEEL)


## Deck life: loungers or a dining set (hashes), a shower post by the stair, pots.
static func _deck_life(B: Dictionary, hw: float, dz0: float, dz1: float, fy: float, stair: bool, gap_x: float) -> void:
	_furniture(B, -hw + 0.7, hw - 0.7, dz0 + 0.4, dz1 - 0.4, fy, "deck")
	var g: CoastHighwayBuild.Geo = B.g
	var P: Callable = B.P
	var b: Basis = B.b
	if stair and h01(B.hs, "shower") < 0.5:
		var sxp := gap_x - signf(gap_x) * 0.9
		g.box("h_metal", Transform3D(b, P.call(sxp, fy + 1.1, dz1 - 0.3)), Vector3(0.04, 1.1, 0.04), STEEL)
		g.box("h_metal", Transform3D(b, P.call(sxp, fy + 2.15, dz1 - 0.48)), Vector3(0.1, 0.02, 0.2), STEEL)
	# Pots with an agave-grey ball in each, by the glass.
	var pots := int(h01(B.hs, "pots") * 3.0)
	for k in pots:
		var px := lerpf(-hw + 0.5, hw - 0.5, h01(B.hs, "pot%d" % k))
		g.box("h_wall", Transform3D(b, P.call(px, fy + 0.25, dz0 + 0.35)), Vector3(0.22, 0.25, 0.22), Color(0.36, 0.34, 0.32))
		g.box("h_dark", Transform3D(b, P.call(px, fy + 0.62, dz0 + 0.35)), Vector3(0.24, 0.16, 0.24), Color(0.34, 0.42, 0.30))


## A pair of loungers under an umbrella, or a table with four chairs, in x0..x1 by z0..z1.
static func _furniture(B: Dictionary, x0: float, x1: float, z0: float, z1: float, y: float, where: String) -> void:
	var g: CoastHighwayBuild.Geo = B.g
	var P: Callable = B.P
	var b: Basis = B.b
	if z1 - z0 < 1.4 or x1 - x0 < 2.2:
		return
	var r := h01(B.hs, where + "_set")
	if r > 0.8:
		return
	var cz := (z0 + z1) * 0.5
	var cx := lerpf(x0 + 1.1, x1 - 1.1, h01(B.hs, where + "_x"))
	var cushion := [Color(0.94, 0.93, 0.89), Color(0.45, 0.55, 0.62), Color(0.30, 0.32, 0.34)][absi(hash([int(B.sd), where])) % 3] as Color
	var frame := Color(0.22, 0.22, 0.23) if int(B.hs.style) != CoastHighway.Style.CEDAR else POST_WOOD
	if r < 0.45 and z1 - z0 >= 1.9:
		# Two loungers side by side, facing the sea, and an umbrella between them.
		for k in 2:
			var lx := cx + (float(k) - 0.5) * 0.85
			g.box("h_trim", Transform3D(b, P.call(lx, y + 0.18, cz)), Vector3(0.3, 0.05, 0.9), frame)
			g.box("h_wall", Transform3D(b, P.call(lx, y + 0.27, cz + 0.12)), Vector3(0.28, 0.04, 0.65), cushion)
			g.box("h_wall", Transform3D(b * Basis(Vector3.RIGHT, 0.85), P.call(lx, y + 0.45, cz - 0.62)), Vector3(0.28, 0.04, 0.3), cushion)
		if where == "deck":
			g.box("h_metal", Transform3D(b, P.call(cx, y + 1.15, cz - 0.9)), Vector3(0.025, 1.15, 0.025), STEEL)
			var can := Color(0.95, 0.94, 0.90) if h01(B.hs, "umb") < 0.6 else Color(0.25, 0.40, 0.48)
			for q in 8:
				var a0 := TAU * float(q) / 8.0
				var a1 := TAU * float(q + 1) / 8.0
				var c0: Vector3 = P.call(cx, y + 2.35, cz - 0.9)
				var p0: Vector3 = P.call(cx + cos(a0) * 1.25, y + 2.05, cz - 0.9 + sin(a0) * 1.25)
				var p1: Vector3 = P.call(cx + cos(a1) * 1.25, y + 2.05, cz - 0.9 + sin(a1) * 1.25)
				g.tri("h_wall", c0, p0, p1, Vector3.UP, can)
				g.tri("h_wall", c0, p1, p0, Vector3.DOWN, can.darkened(0.25))
	else:
		# A round table and four chairs.
		g.box("h_trim", Transform3D(b, P.call(cx, y + 0.74, cz)), Vector3(0.45, 0.025, 0.45), frame)
		g.box("h_metal", Transform3D(b, P.call(cx, y + 0.37, cz)), Vector3(0.03, 0.37, 0.03), STEEL)
		for q in 4:
			var ang := TAU * float(q) / 4.0 + 0.4
			var px := cx + cos(ang) * 0.75
			var pz := cz + sin(ang) * 0.75
			var cb := b * Basis(Vector3.UP, -ang)
			g.box("h_trim", Transform3D(cb, P.call(px, y + 0.45, pz)), Vector3(0.22, 0.03, 0.22), frame)
			g.box("h_metal", Transform3D(cb, P.call(px, y + 0.22, pz)), Vector3(0.025, 0.22, 0.025), STEEL)
			g.box("h_trim", Transform3D(cb, P.call(px + cos(ang) * 0.2, y + 0.72, pz + sin(ang) * 0.2)), Vector3(0.03, 0.27, 0.22), frame)
