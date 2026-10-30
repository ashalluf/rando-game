class_name Refinery
extends RefCounted
## An oil refinery in the industrial south, north of the port (2026-10-29, fleet "refinery": the
## form of the Wilmington refineries, an invented company): VELLARD REFINING CO.'s BAY WORKS.
##   - the TANK FARM (the east half): big floating-roof crude tanks, each in its own earth berm
##     with a gravel floor, a spiral stair up the shell, the roof riding inside it at its own
##     level; product tanks with cone and dome roofs; a row of pressure spheres;
##   - the PROCESS UNITS (the west half), one a block, rolled by hash: a crude unit (the tall
##     atmospheric column, a fat vacuum column, a stabiliser, a fired heater and its stack, a steel
##     structure of four grated decks), a cat cracker (a structure seven decks tall, the reactor
##     riser and the fat regenerator, the main fractionator, a tall stack), a coker (drums on top of
##     a high structure with drilling derricks over them) and a hydrotreater (reactors, columns);
##   - PIPE RACKS down every closed street between the blocks, three tiers of pipes in their
##     colours, fin-fan coolers over the process ones;
##   - FLARE STACKS on the port side: banded risers in lattice derricks, a flame at the tip (and a
##     halo, shaders/refinery_flame.gdshader) burning day and night;
##   - COOLING TOWERS with steam plumes (shaders/refinery_plume.gdshader), the gate, offices, the
##     control room, high-mast floodlights;
##   - after dark, a city of lights: every deck edge, platform, stair head and rack bent has a lamp
##     (thousands of billboard points on aircraft_lights.gdshader, readable from across the basin),
##     the steel round them is lit warm and the tanks are floodlit from their feet.
##
## How it sits on the map: its Landmarks entry carries an "area" (like the film studio's) that
## CityPlan snaps to whole blocks and closes every road inside; the closed roads are the plant's
## own roads, under the racks. The layout is PURE (layout(), cached per plan): every chunk and every
## tier asks the same question. Every roll is a hash of the seed and the place, never a block rng.
##   FULL site chunks build their part in detail (site_steps(): time-sliced, a piece a step) with a
##   RefineryCover child that hides that block's far piece while the chunk is shown;
##   LOD chunks lay the ground; the far city records the ground (capture_steps());
##   RefineryFar (made by CityStreamer with the far landmarks) holds a far piece per block -
##   `detail` false: no rails, ladders, small pipes, fewer sides - with its lights, flames and
##   steam, so the plant reads from the freeway, the hills and the night aerial.
##
## REFINERY=0 in the environment: no entry, no site - the blocks are ordinary industrial (the A/B).

const SITE_ID := "refinery"

static var enabled: bool = OS.get_environment("REFINERY") != "0"

# --- Where -------------------------------------------------------------------------------------
## Four blocks by seven in the industrial south, between the 110's corridor and Alameda, the port
## along its south side (on the default seed the streets at x 2739 / 3235 and z 5167 / 5830).
const ANCHOR := Vector2(2987.0, 5498.0)
const WEST_X := 2739.0
const EAST_X := 3235.0
const NORTH_Z := 5167.0
const SOUTH_Z := 5830.0
const RADIUS := 30.0
const FLAT_MARGIN := 80.0

const COMPANY := "VELLARD REFINING CO"
const WORKS := "BAY WORKS"

# --- The section (metres) -----------------------------------------------------------------------
## The public pavement round the plant, inside the perimeter kerbs, and the service road inside
## the fence.
const PAVEMENT := 4.5
const LANE := 9.0
## Set back from a closed street (the plant's own road, under its rack) on an inner side of a block.
const INNER_SET := 3.0
## The ground inside the fence (Industrial's yard ground).
const BASE_Y := CityChunk.SIDEWALK_TOP + Industrial.LIFT
const GATE_W := 14.0
## A pipe rack's width and tiers.
const RACK_W := 8.0
const RACK_LEVELS := 3
## A berm's height.
const BERM_H := 2.3

## Process unit variants (`variant` of a process block).
enum Unit { CRUDE, FCC, COKER, HYDRO }

static var _layouts: Dictionary = {}


## The entry Landmarks.all() lists: id, anchor, a radius and the area CityPlan snaps to the grid.
## No kept roads: the streets inside are the plant's.
static func entry() -> Dictionary:
	return {"id": SITE_ID, "anchor": ANCHOR, "radius": RADIUS,
		"flat_rect": Rect2(WEST_X - 15.0, NORTH_Z - 15.0, EAST_X - WEST_X + 30.0, SOUTH_Z - NORTH_Z + 30.0), "flat_margin": FLAT_MARGIN,
		"area": {"west_x": WEST_X, "east_x": EAST_X, "north_z": NORTH_Z, "south_z": SOUTH_Z, "keep_z": [], "streets": {}}}


static func h01(parts: Array) -> float:
	return RefineryKit.h01(parts)


# =================================================================================================
# Layout (pure)
# =================================================================================================

## {"site", "rect" (kerb to kerb), "inner" (inside the fence), "gate": {"at", "w"}, "subs": [{"bx",
## "bz", "col", "row", "content", "role", "variant"}], "items": [{"type", "at" (Vector2, the owner
## point), ...}], "racks": [{"a", "b" (Vector2), "fans"}], "roads": [Rect2], "pads": [Rect2],
## "berms": [Rect2]}. {} without the site.
static func layout(plan: CityPlan) -> Dictionary:
	if plan == null or not enabled:
		return {}
	var key := plan.get_instance_id()
	if _layouts.has(key):
		return _layouts[key]
	var lay := _make_layout(plan)
	_layouts[key] = lay
	return lay


static func _make_layout(plan: CityPlan) -> Dictionary:
	var s := plan.site_by_id(SITE_ID)
	if s.is_empty():
		return {}
	var ps := plan.seed
	var rect: Rect2 = s.rect
	var inner := rect.grow(-PAVEMENT)
	var edge := PAVEMENT + LANE
	var lay := {"site": s, "rect": rect, "inner": inner, "subs": [], "items": [], "racks": [], "roads": [], "pads": [], "berms": []}
	var cols := int(s.ix1) - int(s.ix0)
	var rows := int(s.iz1) - int(s.iz0)
	var tank_from := maxi(1, cols / 2)
	for bx in range(int(s.ix0), int(s.ix1)):
		for bz in range(int(s.iz0), int(s.iz1)):
			var b: Rect2 = plan.block(bx, bz).rect
			var x0 := b.position.x + (edge if bx == int(s.ix0) else INNER_SET)
			var x1 := b.end.x - (edge if bx == int(s.ix1) - 1 else INNER_SET)
			var z0 := b.position.y + (edge if bz == int(s.iz0) else INNER_SET)
			var z1 := b.end.y - (edge if bz == int(s.iz1) - 1 else INNER_SET)
			if x1 - x0 < 20.0 or z1 - z0 < 20.0:
				continue
			var col := bx - int(s.ix0)
			var row := bz - int(s.iz0)
			var role := "process"
			if col >= tank_from:
				role = "tanks"
			elif row == 0:
				role = "admin" if col == 0 else "cooling"
			elif row == rows - 1:
				role = "flare"
			lay.subs.append({"bx": bx, "bz": bz, "col": col, "row": row, "content": Rect2(x0, z0, x1 - x0, z1 - z0), "role": role, "variant": 0})
	if lay.subs.is_empty():
		return {}
	# The tank side: a row of spheres and one or two blocks of product tanks among the crude tanks.
	var tank_subs: Array = lay.subs.filter(func(sb: Dictionary) -> bool: return sb.role == "tanks")
	if tank_subs.size() >= 4:
		var k_sph := int(h01([ps, "ref_spheres"]) * float(tank_subs.size()))
		tank_subs[k_sph].role = "spheres"
		var k_cone := (k_sph + 2 + int(h01([ps, "ref_cone"]) * float(tank_subs.size() - 3))) % tank_subs.size()
		if tank_subs[k_cone].role == "tanks":
			tank_subs[k_cone].role = "cone"
	# The process blocks: one of each unit first (a cracker, a coker, a crude unit), the rest rolled;
	# a second cooling tower block among them when there are enough.
	var proc: Array = lay.subs.filter(func(sb: Dictionary) -> bool: return sb.role == "process")
	proc.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return h01([ps, "ref_p", a.bx, a.bz]) < h01([ps, "ref_p", b.bx, b.bz]))
	for i in proc.size():
		var sb: Dictionary = proc[i]
		if i < 4:
			sb.variant = [Unit.FCC, Unit.CRUDE, Unit.COKER, Unit.HYDRO][i]
		else:
			sb.variant = int(h01([ps, "ref_v", sb.bx, sb.bz]) * 4.0) % 4
		if i == 5 and proc.size() >= 8:
			sb.role = "cooling"
	# The gate: on the north street, in front of the admin block (or the north row's west block).
	var front: Dictionary = {}
	for sb: Dictionary in lay.subs:
		if sb.role == "admin":
			front = sb
	if front.is_empty():
		front = lay.subs[0]
	var gx := clampf((front.content as Rect2).get_center().x, inner.position.x + GATE_W, inner.end.x - GATE_W)
	lay.gate = {"at": Vector2(gx, inner.position.y), "w": GATE_W}
	# The plant's roads: the closed streets between the blocks, and the service lane inside the fence.
	for ix in range(int(s.ix0) + 1, int(s.ix1)):
		var x := plan.road_pos(CityPlan.AXIS_X, ix)
		var w := plan.road_width(CityPlan.AXIS_X, ix)
		lay.roads.append(Rect2(x - w * 0.5, inner.position.y, w, inner.size.y))
	for iz in range(int(s.iz0) + 1, int(s.iz1)):
		var z := plan.road_pos(CityPlan.AXIS_Z, iz)
		var w := plan.road_width(CityPlan.AXIS_Z, iz)
		lay.roads.append(Rect2(inner.position.x, z - w * 0.5, inner.size.x, w))
	var lane := LANE - 1.0
	lay.roads.append(Rect2(inner.position.x, inner.position.y, inner.size.x, lane))
	lay.roads.append(Rect2(inner.position.x, inner.end.y - lane, inner.size.x, lane))
	lay.roads.append(Rect2(inner.position.x, inner.position.y, lane, inner.size.y))
	lay.roads.append(Rect2(inner.end.x - lane, inner.position.y, lane, inner.size.y))
	# Racks: down every closed north-south street, and along the closed east-west streets of the
	# process side (with fin-fans), in pieces of whole bays so each is one chunk's.
	for ix in range(int(s.ix0) + 1, int(s.ix1)):
		var x := plan.road_pos(CityPlan.AXIS_X, ix)
		var proc_side := ix - int(s.ix0) <= tank_from
		_rack_run(lay, Vector2(x, inner.position.y + LANE + 4.0), Vector2(x, inner.end.y - LANE - 4.0), false and proc_side)
	for iz in range(int(s.iz0) + 1, int(s.iz1)):
		var z := plan.road_pos(CityPlan.AXIS_Z, iz)
		var x_end := plan.road_pos(CityPlan.AXIS_X, int(s.ix0) + tank_from) - RACK_W
		_rack_run(lay, Vector2(inner.position.x + LANE + 4.0, z), Vector2(x_end, z), true)
	for sb: Dictionary in lay.subs:
		match String(sb.role):
			"tanks":
				_plan_tanks(lay, sb, ps)
			"cone":
				_plan_cone(lay, sb, ps)
			"spheres":
				_plan_spheres(lay, sb, ps)
			"process":
				_plan_process(lay, sb, ps)
			"cooling":
				_plan_cooling(lay, sb, ps)
			"flare":
				_plan_flare(lay, sb, ps)
			"admin":
				_plan_admin(lay, sb, ps)
	# High-mast floodlights along the service lane, every ~90 m.
	var per := inner.size.x * 2.0 + inner.size.y * 2.0
	var n_m := maxi(4, int(per / 95.0))
	for k in n_m:
		var t := (float(k) + 0.5) / float(n_m) * per
		var p := _perimeter_point(inner.grow(-3.0), t)
		if p.distance_to(lay.gate.at) < GATE_W * 2.0:
			continue
		lay.items.append({"type": "mast", "at": p, "h": 28.0})
	return lay


static func _perimeter_point(r: Rect2, t: float) -> Vector2:
	var w := r.size.x
	var h := r.size.y
	t = fposmod(t, 2.0 * (w + h))
	if t < w:
		return r.position + Vector2(t, 0.0)
	t -= w
	if t < h:
		return Vector2(r.end.x, r.position.y + t)
	t -= h
	if t < w:
		return Vector2(r.end.x - t, r.end.y)
	t -= w
	return Vector2(r.position.x, r.end.y - t)


static func _rack_run(lay: Dictionary, a: Vector2, b: Vector2, fans: bool) -> void:
	var l := a.distance_to(b)
	if l < 12.0:
		return
	var n := maxi(1, int(ceil(l / 36.0)))
	for i in n:
		var pa := a.lerp(b, float(i) / float(n))
		var pb := a.lerp(b, float(i + 1) / float(n))
		lay.racks.append({"a": pa, "b": pb, "fans": fans, "at": (pa + pb) * 0.5})


static func _plan_tanks(lay: Dictionary, sb: Dictionary, ps: int) -> void:
	var c: Rect2 = sb.content
	var long_x := c.size.x >= c.size.y
	var L := maxf(c.size.x, c.size.y)
	var S := minf(c.size.x, c.size.y)
	var two := L >= S * 1.7
	var n := 2 if two else 1
	var D := minf(S - 14.0, L / float(n) - 14.0)
	D = clampf(D, 24.0, 76.0)
	for i in n:
		var f := (float(i) + 0.5) / float(n)
		var p := Vector2(c.position.x + c.size.x * f, c.get_center().y) if long_x else Vector2(c.get_center().x, c.position.y + c.size.y * f)
		var cell := Rect2(p - Vector2(c.size.x / float(n) if long_x else c.size.x, c.size.y if long_x else c.size.y / float(n)) * 0.5, Vector2(c.size.x / float(n) if long_x else c.size.x, c.size.y if long_x else c.size.y / float(n))).grow(-1.5)
		lay.berms.append(cell)
		var key := [ps, "ref_tank", sb.bx, sb.bz, i]
		var d := D * lerpf(0.86, 1.0, h01(key + ["d"]))
		var paint := RefineryKit.TANK_WHITE if h01(key + ["p"]) < 0.78 else RefineryKit.TANK_TAN
		lay.items.append({"type": "ftank", "at": p, "D": d, "H": lerpf(15.5, 19.5, h01(key + ["h"])), "fill": h01(key + ["f"]),
			"seed": absi(hash(key)) % 100000, "paint": paint})


static func _plan_cone(lay: Dictionary, sb: Dictionary, ps: int) -> void:
	var c: Rect2 = sb.content
	lay.berms.append(c.grow(-1.5))
	var D := 22.0
	var nx := maxi(1, int((c.size.x - 8.0) / (D + 8.0)))
	var nz := maxi(1, int((c.size.y - 8.0) / (D + 8.0)))
	for i in nx:
		for j in nz:
			var key := [ps, "ref_cone", sb.bx, sb.bz, i, j]
			var p := Vector2(c.position.x + c.size.x * (float(i) + 0.5) / float(nx), c.position.y + c.size.y * (float(j) + 0.5) / float(nz))
			var d := lerpf(14.0, minf(D + 2.0, minf(c.size.x / float(nx), c.size.y / float(nz)) - 8.0), h01(key + ["d"]))
			lay.items.append({"type": "ctank", "at": p, "D": d, "H": lerpf(10.0, 15.0, h01(key + ["h"])), "seed": absi(hash(key)) % 100000,
				"paint": RefineryKit.TANK_WHITE if h01(key + ["p"]) < 0.6 else (RefineryKit.TANK_TAN if h01(key + ["p"]) < 0.85 else Color(0.32, 0.32, 0.3))})


static func _plan_spheres(lay: Dictionary, sb: Dictionary, ps: int) -> void:
	var c: Rect2 = sb.content
	lay.pads.append(c.grow(-2.0))
	var R := clampf(minf(c.size.x, c.size.y) * 0.18, 6.5, 9.5)
	var long_x := c.size.x >= c.size.y
	var L := maxf(c.size.x, c.size.y)
	var n := clampi(int((L - 10.0) / (R * 2.0 + 9.0)), 1, 5)
	var two_rows := minf(c.size.x, c.size.y) > R * 4.0 + 22.0
	for row in (2 if two_rows else 1):
		for i in n:
			var f := (float(i) + 0.5) / float(n)
			var g := (float(row) + 0.5) / (2.0 if two_rows else 1.0)
			var p := Vector2(c.position.x + c.size.x * f, c.position.y + c.size.y * g) if long_x else Vector2(c.position.x + c.size.x * g, c.position.y + c.size.y * f)
			lay.items.append({"type": "sphere", "at": p, "R": R * lerpf(0.9, 1.0, h01([ps, "ref_sph", sb.bx, sb.bz, row, i])), "seed": absi(hash([ps, "sph", sb.bx, sb.bz, row, i])) % 100000})


## A process block: a concrete pad, the unit's structure along one long side, its columns in a row
## along the other, a fired heater at one end, floodlight masts.
static func _plan_process(lay: Dictionary, sb: Dictionary, ps: int) -> void:
	var c: Rect2 = sb.content.grow(-2.0)
	var key := [ps, "ref_unit", sb.bx, sb.bz]
	var flip := h01(key + ["flip"]) < 0.5
	var long_x := c.size.x >= c.size.y
	# A frame on the block: u along its long side, v across.
	var L := maxf(c.size.x, c.size.y)
	var W := minf(c.size.x, c.size.y)
	var at := func(u: float, v: float) -> Vector2:
		if flip:
			v = W - v
		return c.position + (Vector2(u, v) if long_x else Vector2(v, u))
	var sd := absi(hash(key)) % 100000
	var variant: int = sb.variant
	# The structure.
	var s_len := minf(L * 0.55, 52.0)
	var s_w := clampf(W * 0.36, 14.0, 24.0)
	var levels := 4
	var lh := 6.5
	match variant:
		Unit.FCC:
			s_len = minf(L * 0.32, 26.0)
			s_w = clampf(W * 0.4, 16.0, 24.0)
			levels = 7
			lh = 7.0
		Unit.COKER:
			s_len = minf(L * 0.5, 34.0)
			s_w = clampf(W * 0.32, 13.0, 18.0)
			levels = 4
			lh = 8.0
		Unit.HYDRO:
			s_len = minf(L * 0.4, 36.0)
			levels = 3
	var s0: Vector2 = at.call(L * 0.08, 3.0)
	var s1: Vector2 = at.call(L * 0.08 + s_len, 3.0 + s_w)
	var srect := Rect2(Vector2(minf(s0.x, s1.x), minf(s0.y, s1.y)), (s1 - s0).abs())
	# Concrete under the structure and the columns' row; the rest of the block is gravel.
	lay.pads.append(srect.grow(4.0).intersection(c))
	var crow0: Vector2 = at.call(L * 0.04, 3.0 + s_w + 1.0)
	var crow1: Vector2 = at.call(L * 0.96, W)
	lay.pads.append(Rect2(Vector2(minf(crow0.x, crow1.x), minf(crow0.y, crow1.y)), (crow1 - crow0).abs()))
	lay.items.append({"type": "structure", "at": srect.get_center(), "rect": srect, "levels": levels, "lh": lh, "seed": sd,
		"paint": RefineryKit.GREY_STEEL if h01(key + ["paint"]) < 0.6 else RefineryKit.GREEN_STEEL})
	var v_col := 3.0 + s_w + (W - 3.0 - s_w) * 0.5
	match variant:
		Unit.CRUDE:
			lay.items.append({"type": "column", "at": at.call(L * 0.14, v_col), "r": 3.2, "h": lerpf(46.0, 56.0, h01(key + ["c0"])), "seed": sd + 1})
			lay.items.append({"type": "column", "at": at.call(L * 0.32, v_col), "r": 4.3, "h": lerpf(34.0, 40.0, h01(key + ["c1"])), "seed": sd + 2})
			lay.items.append({"type": "column", "at": at.call(L * 0.48, v_col), "r": 1.7, "h": lerpf(28.0, 34.0, h01(key + ["c2"])), "seed": sd + 3})
			lay.items.append({"type": "heater", "at": at.call(L * 0.82, W * 0.5), "size": Vector3(13.0, 14.0, 10.0), "stack": lerpf(44.0, 55.0, h01(key + ["st"])), "seed": sd + 4})
		Unit.FCC:
			lay.items.append({"type": "column", "at": at.call(L * 0.08 + s_len * 0.5, 3.0 + s_w * 0.5), "r": 3.0, "h": 64.0, "seed": sd + 1, "riser": true})
			lay.items.append({"type": "column", "at": at.call(L * 0.5, v_col), "r": 6.2, "h": 40.0, "seed": sd + 2})
			lay.items.append({"type": "column", "at": at.call(L * 0.66, v_col), "r": 3.1, "h": 50.0, "seed": sd + 3})
			lay.items.append({"type": "column", "at": at.call(L * 0.8, v_col), "r": 1.9, "h": 36.0, "seed": sd + 5})
			lay.items.append({"type": "heater", "at": at.call(L * 0.62, 3.0 + s_w * 0.4), "size": Vector3(10.0, 10.0, 9.0), "stack": 72.0, "seed": sd + 4})
		Unit.COKER:
			lay.items.append({"type": "drums", "at": srect.get_center(), "rect": srect, "lh": lh, "levels": levels, "seed": sd + 7})
			lay.items.append({"type": "column", "at": at.call(L * 0.66, v_col), "r": 2.9, "h": lerpf(42.0, 48.0, h01(key + ["c0"])), "seed": sd + 1})
			lay.items.append({"type": "heater", "at": at.call(L * 0.86, W * 0.5), "size": Vector3(12.0, 13.0, 10.0), "stack": 50.0, "seed": sd + 4})
		Unit.HYDRO:
			lay.items.append({"type": "column", "at": at.call(L * 0.58, v_col), "r": 2.4, "h": 24.0, "seed": sd + 1})
			lay.items.append({"type": "column", "at": at.call(L * 0.68, v_col), "r": 2.4, "h": 24.0, "seed": sd + 2})
			lay.items.append({"type": "column", "at": at.call(L * 0.8, v_col), "r": 2.0, "h": lerpf(36.0, 42.0, h01(key + ["c2"])), "seed": sd + 3})
			lay.items.append({"type": "heater", "at": at.call(L * 0.88, 3.0 + s_w * 0.5), "size": Vector3(10.0, 12.0, 9.0), "stack": 42.0, "seed": sd + 4})
	# A short rack along the unit linking it to the street's rack.
	var ra: Vector2 = at.call(L * 0.06, 3.0 + s_w + 2.0 + RACK_W * 0.5)
	var rb: Vector2 = at.call(L * 0.06 + s_len, 3.0 + s_w + 2.0 + RACK_W * 0.5)
	_rack_run(lay, ra, rb, false)
	lay.items.append({"type": "mast", "at": at.call(L * 0.97, 1.5), "h": 26.0})
	lay.items.append({"type": "mast", "at": at.call(L * 0.04, W - 1.5), "h": 26.0})


static func _plan_cooling(lay: Dictionary, sb: Dictionary, ps: int) -> void:
	var c: Rect2 = sb.content.grow(-3.0)
	lay.pads.append(c)
	var long_x := c.size.x >= c.size.y
	var L := maxf(c.size.x, c.size.y)
	var cell := 12.0
	var cells := clampi(int((L - 10.0) / cell), 2, 8)
	var depth := 16.0
	var p := c.get_center() + (Vector2(0.0, -c.size.y * 0.18) if long_x else Vector2(-c.size.x * 0.18, 0.0))
	lay.items.append({"type": "cooling", "at": p, "cells": cells, "cell": cell, "depth": depth, "h": 12.0, "long_x": long_x})
	var q := c.get_center() + (Vector2(0.0, c.size.y * 0.3) if long_x else Vector2(c.size.x * 0.3, 0.0))
	lay.items.append({"type": "building", "at": q, "size": Vector3(26.0, 8.0, 12.0), "glass": false, "paint": Color(0.7, 0.68, 0.62)})


## Flares on the port side: two or three in a row along the block, a knockout drum by each.
static func _plan_flare(lay: Dictionary, sb: Dictionary, ps: int) -> void:
	var c: Rect2 = sb.content.grow(-6.0)
	lay.pads.append(c.grow(-4.0))
	var long_x := c.size.x >= c.size.y
	var L := maxf(c.size.x, c.size.y)
	var n := clampi(int(L / 28.0), 1, 3)
	for i in n:
		var f := (float(i) + 0.5) / float(n)
		var p := Vector2(c.position.x + c.size.x * f, c.get_center().y) if long_x else Vector2(c.get_center().x, c.position.y + c.size.y * f)
		var key := [ps, "ref_flare", sb.bx, sb.bz, i]
		lay.items.append({"type": "flare", "at": p, "h": lerpf(72.0, 96.0, h01(key)), "seed": absi(hash(key)) % 100000})


static func _plan_admin(lay: Dictionary, sb: Dictionary, ps: int) -> void:
	var c: Rect2 = sb.content
	var g: Vector2 = lay.gate.at
	# The gatehouse on the island inside the gate, the offices facing the street, the control room
	# (blast-proof: no windows) behind them, the lab, a car park.
	lay.items.append({"type": "building", "at": g + Vector2(0.0, LANE + 4.0), "size": Vector3(5.0, 3.6, 4.0), "glass": true, "paint": Color(0.78, 0.76, 0.7)})
	lay.items.append({"type": "gate", "at": g})
	var off := Vector2(c.position.x + c.size.x * 0.5, c.position.y + 10.0)
	if absf(off.x - g.x) < 20.0:
		off.x = clampf(g.x + 32.0 * signf(c.get_center().x - g.x + 0.01), c.position.x + 22.0, c.end.x - 22.0)
	lay.items.append({"type": "building", "at": off, "size": Vector3(minf(c.size.x * 0.5, 40.0), 11.0, 14.0), "glass": true, "both": true, "paint": Color(0.74, 0.74, 0.72)})
	lay.items.append({"type": "building", "at": Vector2(c.get_center().x, c.end.y - 14.0), "size": Vector3(minf(c.size.x * 0.6, 34.0), 6.5, 20.0), "glass": false, "paint": Color(0.62, 0.6, 0.54)})
	lay.items.append({"type": "sign", "at": Vector2(g.x + GATE_W * 0.5 + 9.0, lay.inner.position.y + 2.0)})
	lay.pads.append(Rect2(c.position.x + 2.0, c.position.y + 26.0, c.size.x - 4.0, maxf(c.size.y - 48.0, 6.0)))


## True where the plant (fence, pavement ring, everything inside) covers world XZ `p`.
static func covers(plan: CityPlan, p: Vector2) -> bool:
	var lay := layout(plan)
	return not lay.is_empty() and (lay.rect as Rect2).has_point(p)


# =================================================================================================
# Building a piece (a chunk's part, or a far piece)
# =================================================================================================

## Writes every item, rack and berm owned by `area` into `st` (detail or far), appending lamps to
## `lights`, flame tips to `flames` and steam stacks to `plumes`. `gy` maps a world XZ to its ground
## height. With `i0` / `i1` only that slice of the items (time-slicing).
static func write(lay: Dictionary, area: Rect2, st: SurfaceTool, detail: bool, gy: Callable, lights: Array, flames: Array, plumes: Array, what: String = "all", i0: int = 0, i1: int = 1 << 30) -> void:
	if what == "all" or what == "berms":
		for r: Rect2 in lay.berms:
			if area.has_point(r.get_center()):
				RefineryKit.berm(st, r, BASE_Y - 0.05 + float(gy.call(r.get_center())), BERM_H)
	if what == "all" or what == "racks":
		var racks: Array = lay.racks
		for k in range(i0, mini(i1, racks.size())):
			var rk: Dictionary = racks[k]
			if not area.has_point(rk.at):
				continue
			var y: float = BASE_Y + float(gy.call(rk.at as Vector2))
			RefineryKit.pipe_rack(st, Vector3(rk.a.x, y, rk.a.y), Vector3(rk.b.x, y, rk.b.y), RACK_W, RACK_LEVELS, absi(hash([rk.a, "rack"])) % 100000, rk.fans, detail, lights)
	if what == "all" or what == "items":
		var items: Array = lay.items
		for k in range(i0, mini(i1, items.size())):
			var it: Dictionary = items[k]
			var at: Vector2 = it.at
			if not area.has_point(at):
				continue
			write_item(it, st, detail, BASE_Y + float(gy.call(at)), lights, flames, plumes)


static func write_item(it: Dictionary, st: SurfaceTool, detail: bool, y: float, lights: Array, flames: Array, plumes: Array) -> void:
	var at: Vector2 = it.at
	var foot := Vector3(at.x, y, at.y)
	match String(it.type):
		"ftank":
			RefineryKit.floating_tank(st, foot, it.D, it.H, it.fill, it.seed, it.paint, detail, lights)
		"ctank":
			RefineryKit.cone_tank(st, foot, it.D, it.H, it.seed, it.paint, detail, lights)
		"sphere":
			RefineryKit.pressure_sphere(st, foot, it.R, it.seed, detail, lights)
		"structure":
			var r: Rect2 = it.rect
			RefineryKit.structure(st, Vector3(r.position.x, y, r.position.y), r.size, it.levels, it.lh, it.seed, it.paint, detail, lights)
		"column":
			RefineryKit.column(st, foot, it.r, it.h, it.seed, detail, lights)
			if it.get("riser", false):
				# The cat cracker's reactor rides over its structure: a cyclone head and a stack of lights.
				RefineryKit.roof_cone(st, foot + Vector3(0.0, float(it.h) + 1.2, 0.0), float(it.r) * 0.6, 3.0, RefineryKit.K_ALU, Color.WHITE, 10, true)
		"heater":
			RefineryKit.heater(st, foot, it.size, it.stack, it.seed, detail, lights)
		"drums":
			var r: Rect2 = it.rect
			var top := float(it.lh) * float(it.levels)
			RefineryKit.structure(st, Vector3(r.position.x, y, r.position.y), r.size, it.levels, it.lh, it.seed, RefineryKit.GREY_STEEL, detail, lights)
			var long_x := r.size.x >= r.size.y
			for k in 4:
				var f := (float(k) + 0.5) / 4.0
				var p := Vector2(r.position.x + r.size.x * f, r.get_center().y) if long_x else Vector2(r.get_center().x, r.position.y + r.size.y * f)
				var dr := clampf(minf(r.size.x, r.size.y) * 0.3, 3.0, 4.2)
				RefineryKit.column(st, Vector3(p.x, y + top, p.y), dr, 24.0, int(it.seed) + k, detail, lights)
				# A drilling derrick over each pair.
				if k % 2 == 0:
					var q := Vector2(r.position.x + r.size.x * (f + 0.125), r.get_center().y) if long_x else Vector2(r.get_center().x, r.position.y + r.size.y * (f + 0.125))
					_derrick(st, Vector3(q.x, y + top + 26.0, q.y), 22.0, detail)
					lights.append([Vector3(q.x, y + top + 49.0, q.y), RefineryKit.RED, 1.2, RefineryKit.L_FIELD])
		"cooling":
			var tops := RefineryKit.cooling_tower(st, foot if not it.long_x else foot, it.cells, it.cell, it.depth, it.h, detail, lights) if it.long_x else _cooling_turned(st, foot, it, detail, lights)
			for t: Vector3 in tops:
				plumes.append(t)
		"flare":
			var tip := RefineryKit.flare(st, foot, it.h, it.seed, detail, lights)
			flames.append(tip)
			# The knockout drum beside it.
			RefineryKit.tube(st, foot + Vector3(-14.0, 2.6, -6.0), foot + Vector3(-14.0, 2.6, 6.0), 2.2, RefineryKit.K_TANK, RefineryKit.TANK_WHITE, 16 if detail else 8, true)
			RefineryKit.tube(st, foot + Vector3(-14.0, 4.4, 0.0), foot + Vector3(-0.8, 4.4, 0.0), 0.6, RefineryKit.K_PIPE, RefineryKit.PIPE_PAINTS[0], 8)
		"building":
			RefineryKit.building(st, foot, it.size, it.paint, it.glass, it.get("both", false), detail, lights)
		"mast":
			RefineryKit.mast(st, foot, it.h, detail, lights)
		"gate":
			_gate(st, foot, detail, lights)
		"sign":
			_sign(st, foot, detail, lights)


## A cooling tower whose long side runs along z: the same tower turned a quarter.
static func _cooling_turned(st: SurfaceTool, foot: Vector3, it: Dictionary, detail: bool, lights: Array) -> Array:
	# Written with x and z swapped through IndustrialKit's frame (a turn about y at the foot).
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), foot)
	IndustrialKit._xf = xf * Transform3D(Basis(), -foot)
	var lights_local: Array = []
	var tops := RefineryKit.cooling_tower(st, foot, it.cells, it.cell, it.depth, it.h, false, lights_local)
	IndustrialKit._xf = Transform3D()
	var out: Array = []
	var fix := xf * Transform3D(Basis(), -foot)
	for t: Vector3 in tops:
		out.append(fix * t)
	for l: Array in lights_local:
		l[0] = fix * (l[0] as Vector3)
		lights.append(l)
	return out


static func _derrick(st: SurfaceTool, foot: Vector3, h: float, detail: bool) -> void:
	var w := 4.0
	var legs := [Vector3(-w, 0, -w), Vector3(w, 0, -w), Vector3(w, 0, w), Vector3(-w, 0, w)]
	var top := foot + Vector3(0.0, h, 0.0)
	for k in 4:
		var b: Vector3 = foot + legs[k]
		var t: Vector3 = top + (legs[k] as Vector3) * 0.25
		RefineryKit.beam(st, b, t, 0.22, 0.22, RefineryKit.K_STEEL, Color(0.78, 0.74, 0.62))
		var n := 5
		for i in n:
			var f0 := float(i) / float(n)
			var f1 := float(i + 1) / float(n)
			var b2: Vector3 = foot + legs[(k + 1) % 4]
			var t2: Vector3 = top + (legs[(k + 1) % 4] as Vector3) * 0.25
			RefineryKit.beam(st, b.lerp(t, f1), b2.lerp(t2, f1), 0.1, 0.1, RefineryKit.K_STEEL, Color(0.78, 0.74, 0.62))
			if detail:
				RefineryKit.beam(st, b.lerp(t, f0), b2.lerp(t2, f1), 0.08, 0.08, RefineryKit.K_STEEL, Color(0.78, 0.74, 0.62))
	RefineryKit.block(st, top, Vector3(3.0, 1.2, 3.0), RefineryKit.K_STEEL, Color(0.7, 0.66, 0.55))


## The main gate: two pylons, barrier arms, a canopy with lamps.
static func _gate(st: SurfaceTool, foot: Vector3, detail: bool, lights: Array) -> void:
	for s: float in [-1.0, 1.0]:
		RefineryKit.block(st, foot + Vector3(s * (GATE_W * 0.5 + 0.8), 0.0, 0.0), Vector3(1.6, 3.2, 1.6), RefineryKit.K_CONCRETE, RefineryKit.CONCRETE)
	RefineryKit.block(st, foot + Vector3(0.0, 0.0, LANE + 4.0), Vector3(1.2, 0.25, 9.0), RefineryKit.K_CONCRETE, Color(0.85, 0.7, 0.15))
	RefineryKit.block(st, foot + Vector3(0.0, 6.0, LANE + 4.0), Vector3(GATE_W + 4.0, 0.6, 12.0), RefineryKit.K_CLAD, Color(0.82, 0.82, 0.8))
	for s: float in [-1.0, 1.0]:
		for z: float in [LANE - 1.5, LANE + 9.5]:
			RefineryKit.block(st, foot + Vector3(s * (GATE_W * 0.5 + 1.5), 0.0, z), Vector3(0.35, 6.0, 0.35), RefineryKit.K_STEEL, RefineryKit.GREY_STEEL)
		if detail:
			RefineryKit.beam(st, foot + Vector3(s * 0.8, 1.0, LANE), foot + Vector3(s * (GATE_W * 0.45), 1.0, LANE), 0.08, 0.08, RefineryKit.K_BANDS, Color.WHITE)
	for k in 4:
		var p := foot + Vector3((float(k) - 1.5) * 4.0, 5.85, LANE + 4.0)
		lights.append([p, RefineryKit.LED, 1.4, RefineryKit.L_FIELD])
		if detail:
			RefineryKit.block(st, p - Vector3(0.0, 0.1, 0.0), Vector3(0.8, 0.12, 0.8), RefineryKit.K_LAMP, Color.WHITE, 1.0)


## The monument sign by the gate: the company's name, lit after dark.
static func _sign(st: SurfaceTool, foot: Vector3, detail: bool, lights: Array) -> void:
	RefineryKit.block(st, foot + Vector3(0.0, 0.0, 1.0), Vector3(16.0, 0.6, 2.4), RefineryKit.K_CONCRETE, RefineryKit.CONCRETE)
	RefineryKit.block(st, foot + Vector3(0.0, 0.6, 1.0), Vector3(14.0, 2.6, 0.6), RefineryKit.K_CLAD, Color(0.12, 0.2, 0.32))
	if detail:
		var xf := Transform3D(Basis(Vector3.UP, PI), foot + Vector3(0.0, 2.25, 0.68))
		FilmStudioKit.letters(st, COMPANY, 0.9, xf, RefineryKit.K_SIGN, Color(0.95, 0.95, 0.92))
		FilmStudioKit.letters(st, WORKS, 0.5, xf * Transform3D(Basis(), Vector3(0.0, -1.0, 0.0)), RefineryKit.K_SIGN, Color(0.95, 0.66, 0.18))
		# The emblem: an orange flame mark on the left of the name.
		RefineryKit.block(st, foot + Vector3(6.0, 1.5, 0.66), Vector3(0.9, 1.3, 0.05), RefineryKit.K_SIGN, Color(0.95, 0.5, 0.12))
	lights.append([foot + Vector3(-4.0, 0.9, -1.0), RefineryKit.LED, 0.8, RefineryKit.L_FIELD])
	lights.append([foot + Vector3(4.0, 0.9, -1.0), RefineryKit.LED, 0.8, RefineryKit.L_FIELD])


# --- Lights, flames, steam ---------------------------------------------------------------------

static var _light_mat: ShaderMaterial
static var _flame_mat: ShaderMaterial
static var _plume_mat: ShaderMaterial


static func light_material() -> ShaderMaterial:
	if _light_mat == null:
		_light_mat = ShaderMaterial.new()
		_light_mat.shader = load("res://shaders/aircraft_lights.gdshader")
		_light_mat.set_shader_parameter("min_angle", 0.0055)
		_light_mat.set_shader_parameter("hdr", 3.0)
		_light_mat.set_shader_parameter("day_level", 0.0)
		_light_mat.set_shader_parameter("field_day", 0.0)
	return _light_mat


## Every lamp of a piece in ONE billboard mesh (aircraft_lights.gdshader: all four corners at the
## lamp's centre, the size in UV2.x, the kind in UV2.y).
static func lights_mesh(lights: Array) -> ArrayMesh:
	if lights.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for l: Array in lights:
		var phase := fposmod((l[0] as Vector3).x * 0.031 + (l[0] as Vector3).z * 0.017, 1.0)
		var code := float(l[3]) * 10.0 + phase * 9.0
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(l[1])
			st.set_uv(corners[k])
			st.set_uv2(Vector2(l[2], code))
			st.set_normal(Vector3.UP)
			st.add_vertex(l[0])
	var mesh := st.commit()
	mesh.surface_set_material(0, light_material())
	return mesh


static func flame_material() -> ShaderMaterial:
	if _flame_mat == null:
		_flame_mat = ShaderMaterial.new()
		_flame_mat.shader = load("res://shaders/refinery_flame.gdshader")
		_flame_mat.set_shader_parameter("puff_tex", WeaponFX.puff_texture())
	return _flame_mat


static func plume_material() -> ShaderMaterial:
	if _plume_mat == null:
		_plume_mat = ShaderMaterial.new()
		_plume_mat.shader = load("res://shaders/refinery_plume.gdshader")
		_plume_mat.set_shader_parameter("puff_tex", WeaponFX.puff_texture())
	return _plume_mat


## `per` quads at each point (all four corners on it), slot and random in UV2; flames add one glow
## sprite (UV2.x 2) each.
static func _puff_mesh(points: Array, per: int, glow: bool, salt: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	var j := 0
	for p: Vector3 in points:
		var n := per + (1 if glow else 0)
		for i in n:
			var rnd := h01([salt, j, i])
			var slot := 2.0 if (glow and i == per) else (float(i) + rnd * 0.6) / float(per)
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_uv(corners[k])
				st.set_uv2(Vector2(slot, rnd))
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
		j += 1
	return st.commit()


## The flames and steam of a piece as nodes under `parent` (in `parent`'s space).
static func add_fx(parent: Node3D, flames: Array, plumes: Array) -> void:
	if not flames.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "RefineryFlames"
		mi.mesh = _puff_mesh(flames, 10 if not OS.has_feature("web") else 6, true, "flame")
		mi.material_override = flame_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.custom_aabb = _fx_aabb(flames, 40.0, 40.0)
		mi.extra_cull_margin = 2000.0
		parent.add_child(mi)
	if not plumes.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "RefinerySteam"
		mi.mesh = _puff_mesh(plumes, 12 if not OS.has_feature("web") else 6, false, "steam")
		mi.material_override = plume_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.custom_aabb = _fx_aabb(plumes, 50.0, 80.0)
		parent.add_child(mi)


static func _fx_aabb(points: Array, grow: float, up: float) -> AABB:
	var b := AABB(points[0], Vector3.ZERO)
	for p: Vector3 in points:
		b = b.expand(p)
	return AABB(b.position - Vector3(grow, 2.0, grow), b.size + Vector3(grow * 2.0, up + 2.0, grow * 2.0))


static func add_lights(parent: Node3D, lights: Array, name: String) -> void:
	var mesh := lights_mesh(lights)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.extra_cull_margin = 16000.0
	mi.set_meta("air_ignore", true)
	parent.add_child(mi)


# =================================================================================================
# Chunk build
# =================================================================================================

class Acc:
	var st: SurfaceTool
	var ground: SurfaceTool
	var walk: SurfaceTool
	var lights: Array = []
	var flames: Array = []
	var plumes: Array = []


static func _acc(ch: CityChunk) -> Acc:
	if not ch.has_meta("refinery_acc"):
		var a := Acc.new()
		a.st = SurfaceTool.new()
		a.st.begin(Mesh.PRIMITIVE_TRIANGLES)
		a.st.set_smooth_group(-1)
		a.ground = SurfaceTool.new()
		a.ground.begin(Mesh.PRIMITIVE_TRIANGLES)
		a.walk = SurfaceTool.new()
		a.walk.begin(Mesh.PRIMITIVE_TRIANGLES)
		ch.set_meta("refinery_acc", a)
	return ch.get_meta("refinery_acc")


static func site_steps(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var lay := layout(ch.plan)
	if lay.is_empty():
		return steps
	var area := ch.owned_rect()
	steps.append(_ground.bind(ch, lay, area))
	if ch.level == CityChunk.Level.FULL:
		steps.append(_fence.bind(ch, lay, area))
		steps.append(_piece.bind(ch, lay, area, "berms", 0, 1 << 30))
		for i in range(0, (lay.racks as Array).size(), 3):
			steps.append(_piece.bind(ch, lay, area, "racks", i, i + 3))
		var items: Array = lay.items
		for i in items.size():
			if area.has_point(items[i].at):
				steps.append(_piece.bind(ch, lay, area, "items", i, i + 1))
		steps.append(_collision.bind(ch, lay, area))
		steps.append(_commit.bind(ch, lay, area))
	return steps


## The far city's record (capture mode): the ground. The plant itself is RefineryFar's.
static func capture_steps(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var lay := layout(ch.plan)
	if not lay.is_empty():
		steps.append(_ground.bind(ch, lay, ch.owned_rect()))
	return steps


static func _full(ch: CityChunk) -> bool:
	return ch.level == CityChunk.Level.FULL and not ch.capturing


static func _parts(rects: Array, area: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r: Rect2 in rects:
		var p := r.intersection(area)
		if p.size.x > 0.05 and p.size.y > 0.05:
			out.append(p)
	return out


const GRAVEL_FAR := Color(0.47, 0.45, 0.41)


## The pavement ring outside the fence; inside, gravel, the concrete pads, the asphalt roads.
static func _ground(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var rect: Rect2 = lay.rect
	var inner: Rect2 = lay.inner
	var ring := Parks.minus(rect, [inner], 0.05)
	var hard: Array = []
	hard.append_array(lay.pads)
	hard.append_array(lay.roads)
	if not _full(ch):
		for r: Rect2 in _parts(ring, area):
			ch._add_slab(Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP - 0.1, r.get_center().y), Vector3(r.size.x, 0.2, r.size.y), ch.style.sidewalk, true)
		for r: Rect2 in _parts([inner], area):
			ch._add_slab(Vector3(r.get_center().x, BASE_Y - 0.1, r.get_center().y), Vector3(r.size.x, 0.2, r.size.y), GRAVEL_FAR, true)
		return
	var acc := _acc(ch)
	for r: Rect2 in _parts(ring, area):
		FilmStudio._flat(ch, acc.walk, r, CityChunk.SIDEWALK_TOP)
		ch._add_shape(Vector3(r.size.x, 0.3, r.size.y), Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP - 0.15 + ch._gy(r.get_center().x, r.get_center().y), r.get_center().y))
	for r: Rect2 in _parts([inner], area):
		for piece: Rect2 in Parks.minus(r, hard, 0.05):
			Industrial._ground_rect(acc.ground, ch, piece, BASE_Y, Industrial.G_GRAVEL, 0.4, true)
		ch._add_shape(Vector3(r.size.x, 0.3, r.size.y), Vector3(r.get_center().x, BASE_Y - 0.15 + ch._gy(r.get_center().x, r.get_center().y), r.get_center().y))
	for p: Rect2 in _parts(lay.roads, area):
		Industrial._ground_rect(acc.ground, ch, p, BASE_Y + 0.01, Industrial.G_ASPHALT, 0.2, false)
	for p: Rect2 in _parts(lay.pads, area):
		var q := Parks.minus(p, lay.roads, 0.05)
		for piece: Rect2 in q:
			Industrial._ground_rect(acc.ground, ch, piece, BASE_Y + 0.03, Industrial.G_CONCRETE, 0.35, true)
	# A dropped kerb at the gate.
	var g: Vector2 = lay.gate.at
	var ramp := Rect2(g.x - GATE_W * 0.5, rect.position.y, GATE_W, PAVEMENT)
	if area.has_point(ramp.get_center()):
		Industrial._ground_rect(acc.ground, ch, ramp, CityChunk.SIDEWALK_TOP + 0.02, Industrial.G_CONCRETE, 0.5, false)


## Chain-link with barbed wire along the fence line, open at the gate.
static func _fence(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	Industrial._state(ch)
	var w: Rect2 = lay.inner
	var g: Vector2 = lay.gate.at
	var hg := GATE_W * 0.5 + 1.6
	var runs := [[w.position, Vector2(g.x - hg, w.position.y)], [Vector2(g.x + hg, w.position.y), Vector2(w.end.x, w.position.y)],
		[Vector2(w.end.x, w.position.y), w.end], [Vector2(w.position.x, w.end.y), w.end], [w.position, Vector2(w.position.x, w.end.y)]]
	for run: Array in runs:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		# Clip the axis-aligned run to the chunk's owned rect.
		var lo := Vector2(maxf(minf(a.x, b.x), area.position.x), maxf(minf(a.y, b.y), area.position.y))
		var hi := Vector2(minf(maxf(a.x, b.x), area.end.x), minf(maxf(a.y, b.y), area.end.y))
		var horizontal := absf(a.y - b.y) < 0.01
		if horizontal and (a.y < area.position.y or a.y >= area.end.y):
			continue
		if not horizontal and (a.x < area.position.x or a.x >= area.end.x):
			continue
		if (hi - lo).length() < 0.8:
			continue
		Industrial._fence(ch, lo, hi)


## One slice of the plant into the chunk's mesh.
static func _piece(ch: CityChunk, lay: Dictionary, area: Rect2, what: String, i0: int, i1: int) -> void:
	var acc := _acc(ch)
	var gy := func(p: Vector2) -> float: return ch._gy(p.x, p.y)
	write(lay, area, acc.st, true, gy, acc.lights, acc.flames, acc.plumes, what, i0, i1)


## Collision: tanks and spheres as cylinders and spheres, decks and buildings as boxes, the racks'
## top tier, the columns, the flares, the berms.
static func _collision(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	if ch._statics == null:
		return
	for it: Dictionary in lay.items:
		var at: Vector2 = it.at
		if not area.has_point(at):
			continue
		var y := BASE_Y + ch._gy(at.x, at.y)
		match String(it.type):
			"ftank", "ctank":
				_cyl_shape(ch, Vector3(at.x, y, at.y), float(it.D) * 0.5, float(it.H))
			"sphere":
				var sh := CollisionShape3D.new()
				var sp := SphereShape3D.new()
				sp.radius = float(it.R)
				sh.shape = sp
				sh.position = Vector3(at.x, y + float(it.R) + 2.2, at.y)
				ch._statics.add_child(sh)
			"column":
				_cyl_shape(ch, Vector3(at.x, y, at.y), float(it.r) + 0.3, float(it.h))
			"flare":
				_cyl_shape(ch, Vector3(at.x, y, at.y), 1.2, float(it.h))
			"heater":
				var sz: Vector3 = it.size
				ch._add_shape(sz + Vector3(0.0, 3.0, 0.0), Vector3(at.x, y + (sz.y + 3.0) * 0.5, at.y))
				_cyl_shape(ch, Vector3(at.x, y, at.y), 1.6, float(it.stack))
			"structure", "drums":
				var r: Rect2 = it.rect
				for lv in int(it.levels):
					var dy := float(it.lh) * float(lv + 1)
					ch._add_shape(Vector3(r.size.x, 0.2, r.size.y), Vector3(r.get_center().x, y + dy - 0.1, r.get_center().y))
			"cooling":
				var w := float(it.cell) * float(it.cells)
				var size := Vector3(w, float(it.h) + 0.3, float(it.depth)) if it.long_x else Vector3(float(it.depth), float(it.h) + 0.3, w)
				ch._add_shape(size, Vector3(at.x, y + size.y * 0.5, at.y))
			"building":
				var sz: Vector3 = it.size
				ch._add_shape(sz, Vector3(at.x, y + sz.y * 0.5, at.y))
				ch._occluder_boxes.append([Transform3D(Basis(), Vector3.ZERO), Vector3(at.x, y + sz.y * 0.5, at.y), sz - Vector3(1.0, 1.0, 1.0)])
	for rk: Dictionary in lay.racks:
		if not area.has_point(rk.at):
			continue
		var a: Vector2 = rk.a
		var b: Vector2 = rk.b
		var y := BASE_Y + ch._gy(rk.at.x, rk.at.y) + 5.5 + 1.9 * float(RACK_LEVELS - 1) + 0.6
		var d := b - a
		var size := Vector3(absf(d.x) + (RACK_W if absf(d.x) < 1.0 else 0.0), 1.0, absf(d.y) + (RACK_W if absf(d.y) < 1.0 else 0.0))
		ch._add_shape(size, Vector3((a.x + b.x) * 0.5, y, (a.y + b.y) * 0.5))
	for r: Rect2 in lay.berms:
		if not area.has_point(r.get_center()):
			continue
		var y := BASE_Y + ch._gy(r.get_center().x, r.get_center().y) + BERM_H * 0.5
		var t := 1.2 + BERM_H * 1.4
		ch._add_shape(Vector3(r.size.x + t * 2.0, BERM_H, t), Vector3(r.get_center().x, y, r.position.y - t * 0.5 + BERM_H * 1.4))
		ch._add_shape(Vector3(r.size.x + t * 2.0, BERM_H, t), Vector3(r.get_center().x, y, r.end.y + t * 0.5 - BERM_H * 1.4))
		ch._add_shape(Vector3(t, BERM_H, r.size.y), Vector3(r.position.x - t * 0.5 + BERM_H * 1.4, y, r.get_center().y))
		ch._add_shape(Vector3(t, BERM_H, r.size.y), Vector3(r.end.x + t * 0.5 - BERM_H * 1.4, y, r.get_center().y))


static func _cyl_shape(ch: CityChunk, foot: Vector3, r: float, h: float) -> void:
	var sh := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = h
	sh.shape = cy
	sh.position = foot + Vector3(0.0, h * 0.5, 0.0)
	ch._statics.add_child(sh)


static var _walk_mat: Material


## Everything accumulated: the plant mesh, the yard ground, the pavement, the lights, flames and
## steam, the night pools and the omnis, and the cover that hides this block's far piece.
static func _commit(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	if not ch.has_meta("refinery_acc"):
		return
	var acc: Acc = ch.get_meta("refinery_acc")
	ch.remove_meta("refinery_acc")
	if _walk_mat == null:
		_walk_mat = PropFactory.road("sidewalk", 3.0, Color(1.45, 1.43, 1.38), 7713, 1.5, 0.35)
	var parts := [["RefineryPlant", acc.st, RefineryKit.material(), true], ["RefineryGround", acc.ground, Industrial.ground_material(), false],
		["RefineryPavement", acc.walk, _walk_mat, false]]
	for p: Array in parts:
		var st: SurfaceTool = p[1]
		var mesh := st.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = p[0]
		mi.mesh = mesh
		mi.material_override = p[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if p[3] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)
	add_lights(ch, acc.lights, "RefineryLights")
	add_fx(ch, acc.flames, acc.plumes)
	# Light pools on the ground under the lamps (one batch, shadowless), and a few real lights.
	var n_pool := 0
	var n_omni := 0
	for l: Array in acc.lights:
		var p: Vector3 = l[0]
		if (l[1] as Color) == RefineryKit.RED:
			continue
		if n_pool % 3 == 0:
			var size := clampf(p.y * 0.9, 6.0, 22.0)
			ch._batch.add("ref_pool", PropFactory.light_pool(RefineryKit.SODIUM, 1.1, 2.0), Transform3D(Basis().scaled(Vector3(size, 1.0, size)), Vector3(p.x, BASE_Y + 0.04, p.z)))
		n_pool += 1
	ch._batch.set_no_shadow("ref_pool")
	if not OS.has_feature("web"):
		for it: Dictionary in lay.items:
			if String(it.type) != "mast" or not area.has_point(it.at) or n_omni >= 3:
				continue
			var at: Vector2 = it.at
			var l := OmniLight3D.new()
			l.position = Vector3(at.x, BASE_Y + float(it.h) - 2.0 + ch._gy(at.x, at.y), at.y)
			l.light_color = Color(1.0, 0.7, 0.42)
			l.omni_range = 48.0
			l.light_energy = 0.0
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 160.0
			l.distance_fade_length = 60.0
			l.visible = false
			l.set_meta("dark_hidden", true)
			l.add_to_group("lamp_light")
			ch.add_child(l)
			n_omni += 1
		# The flares light their surroundings orange, day and night.
		for t: Vector3 in acc.flames:
			var fl := OmniLight3D.new()
			fl.position = t + Vector3(0.0, 4.0, 0.0)
			fl.light_color = Color(1.0, 0.5, 0.18)
			fl.omni_range = 70.0
			fl.light_energy = 1.4
			fl.omni_attenuation = 1.6
			fl.shadow_enabled = false
			fl.distance_fade_enabled = true
			fl.distance_fade_begin = 300.0
			fl.distance_fade_length = 80.0
			ch.add_child(fl)
	# Sound: the flares' roar.
	for t: Vector3 in acc.flames:
		var snd := Sfx.loop_player("fire_loop")
		snd.name = "FlareRoar"
		snd.position = t
		snd.pitch_scale = 0.55
		snd.unit_size = 30.0
		snd.max_distance = 420.0
		snd.autoplay = true
		ch.add_child(snd)
	var cover := RefineryCover.new()
	cover.key = Vector2i(ch.ix, ch.iz)
	ch.add_child(cover)
