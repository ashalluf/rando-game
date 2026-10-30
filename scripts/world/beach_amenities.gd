class_name BeachAmenities
extends RefCounted
## The beach's public amenities (2026-10-30, wave 3 "beach-amenities": the sand had people and
## towers but none of what a Los Angeles county beach is built round). Code-built at real size on
## one shader (shaders/beach_amenities.gdshader, kind in the vertex alpha), one batch per kind a
## chunk (`bam_*`):
##
## * **Restroom blocks**: split-face block comfort stations on a concrete pad seaward of the bike
##   path, a flat cast roof with an overhang, louvred vents under it, an entrance at each end behind
##   a privacy screen wall, the MEN / WOMEN plates, caged bulkhead lamps lit after dark (a light pool
##   and, on desktop, an OmniLight in `lamp_light`), a stainless drinking fountain, the downpipe.
## * **The concession stand** with its rental counter: a cream stand with a serving window under a
##   striped awning (the roll-up shutter up from 8:30 to 19:00, down otherwise), menu boards lit at
##   night, the stand's invented name on the fascia (STAND_NAMES), and at its end the RENTALS counter
##   with racks of boogie boards, surfboards stood on end, folded umbrellas and stacked chairs;
##   picnic tables on the pad in front.
## * **The outdoor gym pen** on the sand: a sandblasted timber border, a stepped pull-up rig, a
##   rings frame with chains, parallel dip bars, decline and flat benches, its sign.
## * **Showers** on the path's seaward edge: a brushed stainless column with two heads and push
##   buttons, a foot tap, a wet pad with a grate.
## * **Bike racks**: galvanised wave racks on pads beside the stations (and alone now and then).
## * **More volleyball poles** beyond BeachLife's court: a row of two or three courts along the shore
##   at mid-beach, some with a net and tapes (BeachLife's own net and court meshes), most bare poles.
## * **Trash drums**: painted 55-gallon drums on the sand in a few bands, now and then a pair with a
##   white-banded recycling drum.
##
## **Where is pure** (plan_stretch()): world cells of shore - a STATION_CELL picks one of restroom,
## concession, gym, poles or nothing; SHOWER_CELL a shower (and sometimes a rack); CAN_CELL a drum -
## each a hash of the seed and the cell, never a chunk or block rng, owned by the chunk its cell's
## centre falls in. Lower kinds give way to higher (stations > showers > racks > drums) over a
## window round the stretch, so a neighbour's station is known. The block's palms and tower
## (`obstacles`, chunk-local) only NUDGE an item along the shore. BeachLife's people then keep
## clear of all of it: CityChunk._build_beach() appends obstacles() to what it hands BeachLife.build().
##
## LOD chunks and the far city: the two buildings as plain lod_boxes. `BEACH_AMENITIES=0` in the
## environment turns all of it off (the A/B; BeachLife's people are then exactly as before).

static var enabled: bool = OS.get_environment("BEACH_AMENITIES") != "0"

## Metres of shore a station cell covers (13 of BeachLife's cells), a shower cell, a drum cell.
const STATION_CELL := 84.5
const SHOWER_CELL := 42.25
const CAN_CELL := 19.5
## The station roll's cumulative odds: restroom, concession, gym, poles (the rest nothing).
const STATION_ODDS := [0.28, 0.46, 0.64, 0.82]
const SHOWER_ODDS := 0.55
const LONE_RACK_ODDS := 0.25
const CAN_ODDS := 0.6
## The narrowest beach each kind stands on (m of sand from the waterline to the town).
const MIN_WIDTH := 45.0
const MIN_WIDTH_MID := 58.0
## How far a station may be nudged along the shore off a palm or the tower (m), in steps.
const NUDGES := [0.0, 5.0, -5.0, 10.0, -10.0, 15.0, -15.0]

## Footprints, half extents (along the shore, across it), metres, with what BeachLife keeps off.
const HALF := {
	"restroom": Vector2(5.7, 3.7), "concession": Vector2(6.5, 4.6), "gym": Vector2(7.2, 4.7),
	"shower": Vector2(1.2, 1.2), "rack": Vector2(1.6, 0.8), "can": Vector2(0.35, 0.35),
	"court": Vector2(8.6, 5.5),
}
## Building sizes (m): the restroom's block (along, up, across), the concession's.
const RESTROOM := Vector3(9.6, 2.9, 5.6)
const CONCESSION := Vector3(8.0, 3.0, 5.0)

## Kinds in the vertex alpha (x 32), the shader's codes.
const K_CONCRETE := 1
const K_BLOCK := 2
const K_PAINT := 3
const K_GALV := 4
const K_STAINLESS := 5
const K_WOOD := 6
const K_CANVAS := 7
const K_LAMP := 8
const K_SIGN := 9
const K_RUBBER := 10
const K_GLASS := 11
const K_MENU := 12
const K_PAD := 13
const K_CHAIN := 14
const K_SHUTTER := 15
const K_SANDWOOD := 16

## The stand's names, invented (never a real business).
const STAND_NAMES := ["SANDPIPER SNACKS", "TIDELINE CAFE", "THE SALT SHACK", "GULL & GALLEY", "BLUE CURL KIOSK"]
## Block colours a restroom is laid in (sRGB).
const BLOCK_COLORS: Array[Color] = [Color(0.78, 0.72, 0.62), Color(0.68, 0.67, 0.64), Color(0.66, 0.70, 0.72)]
## Door and trim paints (sRGB): county teal, harbour blue, sea green, sand brown.
const TRIM_PAINTS: Array[Color] = [Color(0.12, 0.45, 0.48), Color(0.16, 0.3, 0.55), Color(0.2, 0.48, 0.36), Color(0.5, 0.38, 0.26)]
## Drum paints (sRGB): the county's blues and teals, white, sun yellow, green.
const DRUM_PAINTS: Array[Color] = [Color(0.2, 0.45, 0.7), Color(0.1, 0.55, 0.58), Color(0.92, 0.92, 0.88),
	Color(0.92, 0.75, 0.2), Color(0.25, 0.55, 0.32), Color(0.35, 0.65, 0.85)]
## Awning stripes (sRGB, the second colour; the first is white).
const AWNINGS: Array[Color] = [Color(0.85, 0.2, 0.2), Color(0.12, 0.38, 0.7), Color(0.1, 0.55, 0.5), Color(0.95, 0.62, 0.15)]
## The gym's frames (sRGB).
const GYM_PAINTS: Array[Color] = [Color(0.18, 0.42, 0.3), Color(0.15, 0.32, 0.55), Color(0.55, 0.56, 0.55)]

const PROP_DRAW := 260.0
const SMALL_DRAW := 150.0
const LAMP_POOL := Color(1.0, 0.9, 0.72)

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial


static func _h(parts: Array) -> float:
	return float(absi(hash(parts)) % 1000003) / 1000003.0


static func _hi(parts: Array) -> int:
	return absi(hash(parts))


# --- Where -------------------------------------------------------------------------------------

## The shore's frame at z: [coast x, beach width, land (unit, inland), along (unit, +z), sea-facing yaw].
static func _frame(plan: CityPlan, z: float) -> Array:
	var macro: MacroMap = plan.macro
	var slope := (macro.coast_x(z + 2.0) - macro.coast_x(z - 2.0)) / 4.0
	var land := Vector2(1.0, -slope).normalized()
	var along := Vector2(slope, 1.0).normalized()
	return [macro.coast_x(z), macro.beach_width_at(z), land, along, atan2(land.x, land.y)]


## True where the beach is not ours to furnish: BeachLife's kept-off stretches and the coast
## highway's stretch under the bluffs (CoastHighwayBuild builds those chunks' sand itself).
static func off(plan: CityPlan, z: float) -> bool:
	if BeachLife.kept_off(plan, z):
		return true
	var ch: CoastHighway = plan.macro.coast_highway if plan.macro else null
	return ch != null and z > ch.z_north - CoastHighway.NORTH_FADE - 30.0 and z < ch.z_south + 30.0


## The stations of the station cells round z0..z1 (pure, no obstacles): {kind, at, yaw, k, half}.
static func _stations(plan: CityPlan, z0: float, z1: float) -> Array:
	var out: Array = []
	for k in range(floori(z0 / STATION_CELL), floori(z1 / STATION_CELL) + 1):
		var zc := (float(k) + 0.5) * STATION_CELL
		var pick := _h([plan.seed, "bam_station", k])
		var kind := ""
		if pick < float(STATION_ODDS[0]):
			kind = "restroom"
		elif pick < float(STATION_ODDS[1]):
			kind = "concession"
		elif pick < float(STATION_ODDS[2]):
			kind = "gym"
		elif pick < float(STATION_ODDS[3]):
			kind = "poles"
		if kind == "":
			continue
		var z := zc + (_h([plan.seed, "bam_station_z", k]) - 0.5) * STATION_CELL * 0.3
		if off(plan, z):
			continue
		var f := _frame(plan, z)
		var w: float = f[1]
		var at := Vector2.ZERO
		var half: Vector2 = HALF.get(kind, HALF.court)
		match kind:
			"restroom", "concession":
				if w < MIN_WIDTH:
					continue
				# Seaward of the bike path, its back a couple of metres off the path's edge.
				at = Vector2(BeachLife.path_x(plan, z) - BeachLife.PATH_WIDTH * 0.5 - 1.8 - half.y, z)
			"gym":
				if w < MIN_WIDTH_MID:
					continue
				at = Vector2(float(f[0]) + w * 0.62, z)
			"poles":
				if w < MIN_WIDTH_MID:
					continue
				at = Vector2(float(f[0]) + w * 0.5, z)
		out.append({"kind": kind, "at": at, "yaw": float(f[4]), "k": k, "half": half, "z": z})
	return out


## The courts of a row of poles (pure): 2-3 along the shore, 20 m apart.
static func _row_courts(plan: CityPlan, st: Dictionary) -> Array:
	var n := 2 + int(_h([plan.seed, "bam_row_n", st.k]) > 0.55)
	var out: Array = []
	for i in n:
		var dz := (float(i) - float(n - 1) * 0.5) * 20.0
		var z: float = float(st.z) + dz
		var f := _frame(plan, z)
		var at := Vector2(float(f[0]) + float(f[1]) * 0.5, z)
		var slope := (plan.macro.coast_x(z + 2.0) - plan.macro.coast_x(z - 2.0)) / 4.0
		out.append({"at": at, "yaw": atan(slope), "net": _h([plan.seed, "bam_net", st.k, i]) < 0.4, "i": i})
	return out


static func _overlaps(a: Vector2, ha: Vector2, b: Vector2, hb: Vector2, margin: float) -> bool:
	return absf(a.y - b.y) < ha.x + hb.x + margin and absf(a.x - b.x) < ha.y + hb.y + margin


## Whether a rect (at, half: along z / across x) keeps clear of every circle [point, radius].
static func _clear(obstacles: Array, at: Vector2, half: Vector2, pad: float) -> bool:
	for o: Array in obstacles:
		var p: Vector2 = o[0]
		var r: float = float(o[1]) + pad
		if absf(p.y - at.y) < half.x + r and absf(p.x - at.x) < half.y + r:
			return false
	return true


## A station's spot nudged along the shore off `obstacles` (and BeachLife's courts), or INF.
static func _nudge(plan: CityPlan, st: Dictionary, obstacles: Array, courts: Array) -> Vector2:
	var base: Vector2 = st.at
	var half: Vector2 = st.half
	for d: float in NUDGES:
		var at := Vector2(base.x, base.y + d)
		var ok := _clear(obstacles, at, half, 0.4)
		for c: Dictionary in courts:
			ok = ok and not BeachLife._near_court(c, at, maxf(half.x, half.y) + 1.0)
		if ok:
			# The across position follows the shore at the nudged z.
			if String(st.kind) in ["restroom", "concession"]:
				at.x = BeachLife.path_x(plan, at.y) - BeachLife.PATH_WIDTH * 0.5 - 1.8 - half.y
			return at
	return Vector2.INF


## Everything the stretch z0..z1 holds (pure apart from `obstacles`, the chunk's palms and tower,
## which only nudge): [{kind, mesh, at: Vector2, yaw, paint: Color, half}], every item's cell
## centred in z0..z1 so two neighbours split the shore exactly.
static func plan_stretch(plan: CityPlan, z0: float, z1: float, obstacles: Array = []) -> Array:
	var out: Array = []
	if plan == null or plan.macro == null:
		return out
	var courts := BeachLife.courts_in(plan, z0 - 120.0, z1 + 120.0)
	# Every station near enough to matter (the window), for the lower kinds to give way to.
	var near := _stations(plan, z0 - STATION_CELL, z1 + STATION_CELL)
	var blocking: Array = []
	# BeachLife's own courts (and their run-off) are nobody's to stand on.
	for bc: Dictionary in courts:
		blocking.append([bc.centre, Vector2(BeachLife.COURT_SIZE.y * 0.5 + 2.0, BeachLife.COURT_SIZE.x * 0.5 + 2.0)])
	for st: Dictionary in near:
		var mine: bool = float(st.z) >= z0 and float(st.z) < z1
		if String(st.kind) == "poles":
			for c: Dictionary in _row_courts(plan, st):
				var clash := false
				for bc: Dictionary in courts:
					clash = clash or BeachLife._near_court(bc, c.at, 10.0)
				if clash:
					continue
				blocking.append([c.at, HALF.court])
				if mine and _clear(obstacles, c.at, Vector2(1.0, 5.4), 0.3):
					out.append({"kind": "court", "mesh": "vb_net" if c.net else "vb_poles", "at": c.at, "yaw": float(c.yaw),
						"paint": Color.WHITE, "half": HALF.court, "net": bool(c.net)})
			continue
		var at := _nudge(plan, st, obstacles if mine else [], courts)
		if at == Vector2.INF or off(plan, at.y):
			continue
		var half: Vector2 = st.half
		# The lower kinds give way to where the station could stand, nudged or not.
		blocking.append([Vector2(at.x, float(st.z)), half + Vector2(15.5, 0.0)])
		if not mine:
			continue
		var hk := _hi([plan.seed, "bam_look", st.k])
		match String(st.kind):
			"restroom":
				out.append({"kind": "restroom", "mesh": "restroom_%d" % (hk % BLOCK_COLORS.size()), "at": at, "yaw": st.yaw,
					"paint": TRIM_PAINTS[(hk / 7) % TRIM_PAINTS.size()], "half": half})
				_add_beside(plan, out, at, float(st.yaw), half, hk, obstacles, blocking.slice(0, blocking.size() - 1))
			"concession":
				out.append({"kind": "concession", "mesh": "concession_%d" % (hk % STAND_NAMES.size()), "at": at, "yaw": st.yaw,
					"paint": AWNINGS[(hk / 7) % AWNINGS.size()], "half": half})
				_add_beside(plan, out, at, float(st.yaw), half, hk, obstacles, blocking.slice(0, blocking.size() - 1))
			"gym":
				out.append({"kind": "gym", "mesh": "gym", "at": at, "yaw": st.yaw,
					"paint": GYM_PAINTS[hk % GYM_PAINTS.size()], "half": half})
	# Showers (and lone racks) along the path's seaward edge.
	for k in range(floori(z0 / SHOWER_CELL), floori(z1 / SHOWER_CELL) + 1):
		var zc := (float(k) + 0.5) * SHOWER_CELL
		if zc < z0 or zc >= z1 or off(plan, zc):
			continue
		if _h([plan.seed, "bam_shower", k]) >= SHOWER_ODDS or plan.macro.beach_width_at(zc) < MIN_WIDTH:
			continue
		var f := _frame(plan, zc)
		var at := Vector2(BeachLife.path_x(plan, zc) - BeachLife.PATH_WIDTH * 0.5 - 1.5, zc)
		if not _free(blocking, at, HALF.shower, 1.0) or not _clear(obstacles, at, HALF.shower, 0.3):
			continue
		out.append({"kind": "shower", "mesh": "shower", "at": at, "yaw": float(f[4]), "paint": Color.WHITE, "half": HALF.shower})
		blocking.append([at, HALF.shower])
		if _h([plan.seed, "bam_lone_rack", k]) < LONE_RACK_ODDS:
			var ra := at + Vector2(0.0, 4.2)
			if _free(blocking, ra, HALF.rack, 0.5) and _clear(obstacles, ra, HALF.rack, 0.3):
				out.append({"kind": "rack", "mesh": "rack", "at": ra, "yaw": float(f[4]), "paint": Color.WHITE, "half": HALF.rack})
				blocking.append([ra, HALF.rack])
	# The drums, in bands across the sand.
	for k in range(floori(z0 / CAN_CELL), floori(z1 / CAN_CELL) + 1):
		var zc := (float(k) + 0.5) * CAN_CELL
		if zc < z0 or zc >= z1 or off(plan, zc):
			continue
		var hc := _hi([plan.seed, "bam_can", k])
		if _h([hc, 0]) >= CAN_ODDS:
			continue
		var f := _frame(plan, zc)
		var w: float = f[1]
		if w < MIN_WIDTH * 0.8:
			continue
		var band: float = [0.34, 0.5, 0.7][hc % 3]
		var at := Vector2(float(f[0]) + w * band, zc + (_h([hc, 1]) - 0.5) * CAN_CELL * 0.5)
		if not _free(blocking, at, HALF.can, 1.0) or not _clear(obstacles, at, HALF.can, 0.4) or off(plan, at.y):
			continue
		var paint: Color = DRUM_PAINTS[(hc / 3) % DRUM_PAINTS.size()]
		out.append({"kind": "can", "mesh": "drum_trash", "at": at, "yaw": _h([hc, 2]) * TAU, "paint": paint, "half": HALF.can})
		if _h([hc, 3]) < 0.3:
			var bt := at + (f[3] as Vector2) * 0.75
			if _free(blocking, bt, HALF.can, 1.0) and _clear(obstacles, bt, HALF.can, 0.4):
				out.append({"kind": "can", "mesh": "drum_recycle", "at": bt, "yaw": _h([hc, 4]) * TAU,
					"paint": DRUM_PAINTS[(hc / 3 + 1) % DRUM_PAINTS.size()], "half": HALF.can})
	return out


static func _free(blocking: Array, at: Vector2, half: Vector2, margin: float) -> bool:
	for b: Array in blocking:
		if _overlaps(b[0], b[1], at, half, margin):
			return false
	return true


## A station's rack and drums beside it, along the shore past its end.
static func _add_beside(plan: CityPlan, out: Array, at: Vector2, yaw: float, half: Vector2, hk: int, obstacles: Array, blocking: Array) -> void:
	var side := 1.0 if hk % 2 == 0 else -1.0
	var rack := Vector2(BeachLife.path_x(plan, at.y + side * (half.x + 2.6)) - BeachLife.PATH_WIDTH * 0.5 - 1.3, at.y + side * (half.x + 2.6))
	if _clear(obstacles, rack, HALF.rack, 0.3) and _free(blocking, rack, HALF.rack, 0.3) and not off(plan, rack.y):
		out.append({"kind": "rack", "mesh": "rack", "at": rack, "yaw": yaw, "paint": Color.WHITE, "half": HALF.rack})
	var can := Vector2(at.x - half.y + 0.4, at.y - side * (half.x + 1.4))
	if _clear(obstacles, can, HALF.can, 0.3) and _free(blocking, can, HALF.can, 0.3) and not off(plan, can.y):
		out.append({"kind": "can", "mesh": "drum_trash", "at": can, "yaw": _h([hk, "c"]) * TAU,
			"paint": DRUM_PAINTS[hk % DRUM_PAINTS.size()], "half": HALF.can})
	var can2 := can + Vector2(0.0, -side * 0.75)
	if _h([hk, "c2"]) < 0.6 and _clear(obstacles, can2, HALF.can, 0.3) and _free(blocking, can2, HALF.can, 0.3):
		out.append({"kind": "can", "mesh": "drum_recycle", "at": can2, "yaw": _h([hk, "c3"]) * TAU,
			"paint": DRUM_PAINTS[(hk + 2) % DRUM_PAINTS.size()], "half": HALF.can})


# --- Building a chunk ---------------------------------------------------------------------------

## A FULL beach chunk's amenities, from CityChunk._build_beach() before BeachLife.build():
## returns the obstacles BeachLife's people keep clear of.
static func build(ch: CityChunk, z0: float, z1: float, obstacles_in: Array) -> Array:
	if not enabled or ch.plan == null or ch.plan.macro == null:
		return []
	var plan := ch.plan
	var items := plan_stretch(plan, z0, z1, obstacles_in)
	ch.set_meta("beach_amenities", items)
	var hour := fposmod(BeachLife.hour_now(ch), 24.0)
	var open := hour >= 8.5 and hour < 19.0
	var lights := 0
	var used: Dictionary = {}
	for it: Dictionary in items:
		var at: Vector2 = it.at
		var half: Vector2 = it.half
		var yaw: float = it.yaw
		var y := _ground(ch, it)
		var key := String(it.mesh)
		if key.begins_with("concession") and not open:
			key += "_shut"
		var basis := Basis(Vector3.UP, yaw)
		var xf := Transform3D(basis, Vector3(at.x, y, at.y))
		var paint: Color = it.paint
		var custom := Color(paint.r, paint.g, paint.b, _h([plan.seed, "bam_seed", at.x, at.y]))
		var kind := String(it.kind)
		if kind == "court" and bool(it.get("net", false)):
			ch._batch.add("beach_net", BeachLife.prop_mesh("net"), xf)
			ch._batch.add("beach_court_lines", BeachLife.prop_mesh("court_lines"), xf)
			ch._batch.set_shadow_distance("beach_net", 60.0)
			ch._batch.set_no_shadow("beach_court_lines")
		else:
			ch._batch.add("bam_" + key, mesh(key), xf, Color.WHITE, custom)
			used[key] = true
		_collide(ch, kind, xf)
		if kind == "restroom":
			for sx: float in [-1.0, 1.0]:
				var lamp := xf * Vector3(sx * (RESTROOM.x * 0.5 + 0.15), 0.0, 0.0)
				var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(6.0, 1.0, 6.0)), lamp + Vector3(0.0, 0.08, 0.0))
				ch._batch.add("bam_pool", PropFactory.light_pool(LAMP_POOL, 0.7), pool)
				used["pool"] = true
			if lights < 1 and not OS.has_feature("web"):
				_add_light(ch, xf * Vector3(0.0, 2.6, -RESTROOM.z * 0.5 - 1.0), 9.0)
				lights += 1
		elif kind == "concession" and open:
			var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(7.0, 1.0, 4.5)), xf * Vector3(0.0, 0.1, -CONCESSION.z * 0.5 - 2.0))
			ch._batch.add("bam_pool", PropFactory.light_pool(LAMP_POOL, 0.7), pool)
			used["pool"] = true
	for key: String in used.keys():
		var bk := "bam_" + key
		if key == "pool":
			continue
		var small := key == "shower" or key == "rack" or key.begins_with("drum")
		ch._batch.set_draw_distance(bk, SMALL_DRAW if small else PROP_DRAW)
		ch._batch.set_shadow_distance(bk, 45.0 if small else 90.0)
	if used.has("pool"):
		ch._batch.set_no_shadow("bam_pool")
	var obs: Array = []
	for it: Dictionary in items:
		obs.append([it.at, (it.half as Vector2).length() + 0.8])
	# And a neighbour's, which this chunk's people must keep off too.
	for it: Dictionary in plan_stretch(plan, z0 - 40.0, z1 + 40.0, []):
		if float((it.at as Vector2).y) < z0 or float((it.at as Vector2).y) >= z1:
			obs.append([it.at, (it.half as Vector2).length() + 0.8])
	return obs


## The sand under an item: the lowest of its corners for a building (it stands on a plinth), its
## centre for anything small.
static func _ground(ch: CityChunk, it: Dictionary) -> float:
	var at: Vector2 = it.at
	var half: Vector2 = it.half
	if String(it.kind) in ["restroom", "concession", "gym"]:
		var y := INF
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
			y = minf(y, BeachLife.sand_y(ch, at.x + c.y * half.y, at.y + c.x * half.x))
		return y + (0.0 if String(it.kind) == "gym" else 0.05)
	return BeachLife.sand_y(ch, at.x, at.y)


static func _collide(ch: CityChunk, kind: String, xf: Transform3D) -> void:
	var yaw := xf.basis.get_euler().y
	match kind:
		"restroom":
			ch._add_shape(Vector3(RESTROOM.x, RESTROOM.y + 0.6, RESTROOM.z), xf * Vector3(0.0, RESTROOM.y * 0.5 - 0.3, 0.0), yaw)
			ch._add_shape(Vector3(RESTROOM.x + 1.0, 0.3, RESTROOM.z + 1.0), xf * Vector3(0.0, RESTROOM.y + 0.15, 0.0), yaw)
		"concession":
			ch._add_shape(Vector3(CONCESSION.x, CONCESSION.y + 0.6, CONCESSION.z), xf * Vector3(0.0, CONCESSION.y * 0.5 - 0.3, 0.0), yaw)
		"gym":
			for p: Vector3 in [Vector3(-4.5, 1.4, -1.2), Vector3(0.0, 1.8, 1.5), Vector3(4.3, 0.6, -1.0)]:
				ch._add_shape(Vector3(2.2 if p.x != 0.0 else 2.6, p.y * 2.0, 0.3), xf * p, yaw)
		"shower":
			ch._add_shape(Vector3(0.3, 2.5, 0.3), xf * Vector3(0.0, 1.25, 0.0), yaw)
		"can":
			ch._add_shape(Vector3(0.58, 0.9, 0.58), xf * Vector3(0.0, 0.45, 0.0), yaw)
		"court":
			for sx: float in [-4.9, 4.9]:
				ch._add_shape(Vector3(0.14, 2.6, 0.14), xf * Vector3(sx, 1.3, 0.0), yaw)


static func _add_light(ch: CityChunk, at: Vector3, reach: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.omni_range = reach
	light.omni_attenuation = 1.5
	light.light_color = LAMP_POOL
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 50.0
	light.distance_fade_length = 15.0
	light.add_to_group("lamp_light")
	ch.add_child(light)


## LOD chunks and the far city: the two buildings as plain boxes.
static func build_lod(ch: CityChunk, z0: float, z1: float) -> void:
	if not enabled or ch.plan == null or ch.plan.macro == null:
		return
	for it: Dictionary in plan_stretch(ch.plan, z0, z1, []):
		var kind := String(it.kind)
		if kind != "restroom" and kind != "concession":
			continue
		var at: Vector2 = it.at
		var size := RESTROOM if kind == "restroom" else CONCESSION
		var col: Color = BLOCK_COLORS[0] if kind == "restroom" else Color(0.9, 0.86, 0.76)
		var y := BeachLife.sand_y(ch, at.x, at.y)
		var b := Basis(Vector3.UP, float(it.yaw)).scaled(Vector3(size.x, size.y + 0.6, size.z))
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(b, Vector3(at.x, y + size.y * 0.5 - 0.3, at.y)), col, Color(0.0, 0.0, 0.0, 1.0))


# --- Meshes -------------------------------------------------------------------------------------

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/beach_amenities.gdshader")
	return _material


static func _c(rgb: Color, k: int) -> Color:
	return Color(rgb.r, rgb.g, rgb.b, float(k) / 32.0)


static func mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	if key.begins_with("restroom_"):
		_restroom(st, int(key.substr(9)))
	elif key.begins_with("concession_"):
		var parts := key.split("_")
		_concession(st, int(parts[1]), not key.ends_with("_shut"))
	else:
		match key:
			"gym":
				_gym(st)
			"shower":
				_shower(st)
			"rack":
				_rack(st)
			"drum_trash":
				_drum(st, false)
			"drum_recycle":
				_drum(st, true)
			"vb_poles":
				_poles(st)
	st.generate_tangents()
	var m := st.commit()
	m.surface_set_material(0, material())
	_meshes[key] = m
	return m


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color, rm: Vector2, bevel: float = 0.01, yaw: float = 0.0) -> void:
	StreetClutter._bbox(st, Transform3D(Basis(Vector3.UP, yaw), c), size, bevel, col, rm)


static func _post(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color, rm: Vector2, sides: int = 8) -> void:
	StreetClutter._tube(st, [a, b], r, sides, col, rm)


## Lettering facing the item's front (-z) at `c`.
static func _text_front(st: SurfaceTool, text: String, h: float, c: Vector3, col: Color, max_w: float, facing: Vector3 = Vector3.FORWARD) -> void:
	var b := Basis.looking_at(-facing, Vector3.UP)
	StreetVendors._text(st, text, h, Transform3D(b, c), col, max_w)


## A comfort station: 9.6 x 5.6 m of split-face block, 2.9 m to the roof, entrances at both ends.
static func _restroom(st: SurfaceTool, variant: int) -> void:
	var block := _c(BLOCK_COLORS[variant % BLOCK_COLORS.size()], K_BLOCK)
	var conc := _c(Color(0.74, 0.73, 0.7), K_CONCRETE)
	var roofc := _c(Color(0.8, 0.79, 0.76), K_CONCRETE)
	var paint := _c(Color.WHITE, K_PAINT)
	var galv := _c(Color(0.7, 0.71, 0.72), K_GALV)
	var dark := _c(Color(0.12, 0.12, 0.12), K_SIGN)
	var rm := Vector2(0.9, 0.0)
	var mrm := Vector2(0.4, 0.7)
	var L := RESTROOM.x
	var H := RESTROOM.y
	var D := RESTROOM.z
	# The pad, then the block body down into the sand (a plinth).
	_box(st, Vector3(0.0, 0.06, 0.0), Vector3(L + 1.8, 0.16, D + 1.8), conc, rm, 0.02)
	_box(st, Vector3(0.0, (H - 0.6) * 0.5, 0.0), Vector3(L, H + 0.6, D), block, rm, 0.01)
	# A darker course of bond-beam block under the roof and the roof slab with its overhang.
	_box(st, Vector3(0.0, H - 0.1, 0.0), Vector3(L + 0.04, 0.2, D + 0.04), _c(Color(0.62, 0.6, 0.56), K_CONCRETE), rm, 0.005)
	_box(st, Vector3(0.0, H + 0.14, 0.0), Vector3(L + 1.0, 0.28, D + 1.0), roofc, rm, 0.03)
	# The roof's parapet lip, vents and a hatch.
	for sz: float in [-1.0, 1.0]:
		_box(st, Vector3(0.0, H + 0.34, sz * (D * 0.5 + 0.44)), Vector3(L + 1.0, 0.12, 0.12), roofc, rm, 0.01)
	for sx: float in [-1.0, 1.0]:
		_box(st, Vector3(sx * (L * 0.5 + 0.44), H + 0.34, 0.0), Vector3(0.12, 0.12, D + 1.0), roofc, rm, 0.01)
	for p: Vector3 in [Vector3(-2.2, H + 0.28, 1.0), Vector3(2.4, H + 0.28, 0.8)]:
		StreetClutter._cyl(st, Transform3D(Basis(), p), 0.06, 0.06, 0.55, galv, mrm, 8)
		StreetClutter._cyl(st, Transform3D(Basis(), p + Vector3(0.0, 0.55, 0.0)), 0.1, 0.03, 0.12, galv, mrm, 8)
	_box(st, Vector3(0.6, H + 0.36, -0.6), Vector3(0.9, 0.16, 0.9), galv, mrm, 0.01)
	# Louvred vents along both long walls under the bond beam.
	for sz: float in [-1.0, 1.0]:
		for i in 6:
			var x := (float(i) - 2.5) * 1.35
			var c := Vector3(x, H - 0.45, sz * (D * 0.5 + 0.005))
			_box(st, c, Vector3(0.9, 0.36, 0.02), dark, rm, 0.0)
			for s in 4:
				_box(st, c + Vector3(0.0, -0.13 + float(s) * 0.087, sz * 0.02), Vector3(0.88, 0.02, 0.03), galv, mrm, 0.0)
	# The entrances at each end: a dark opening with a painted steel frame, the door held open
	# against the inside wall, a privacy screen wall 1.4 m out, the plate and a caged lamp.
	for sx: float in [-1.0, 1.0]:
		var face := sx * L * 0.5
		var door_z := -0.9
		_box(st, Vector3(face + sx * 0.005, 1.1, door_z), Vector3(0.02, 2.2, 1.1), dark, rm, 0.0)
		_box(st, Vector3(face + sx * 0.03, 2.24, door_z), Vector3(0.06, 0.08, 1.26), paint, rm, 0.005)
		for dz: float in [-0.6, 0.6]:
			_box(st, Vector3(face + sx * 0.03, 1.12, door_z + dz), Vector3(0.06, 2.24, 0.06), paint, rm, 0.005)
		# The door open inward, flat against the reveal.
		_box(st, Vector3(face - sx * 0.08, 1.05, door_z + 0.53), Vector3(0.9, 2.05, 0.04), paint, rm, 0.005, PI * 0.5 * 0.0)
		# The screen wall.
		_box(st, Vector3(face + sx * 1.45, 0.75, door_z + 0.15), Vector3(0.2, 2.1, 2.6), block, rm, 0.01)
		_box(st, Vector3(face + sx * 1.45, 1.86, door_z + 0.15), Vector3(0.26, 0.08, 2.66), roofc, rm, 0.01)
		# The plate on the screen's outer face: a blue board, the pictogram and the word.
		var plate := Vector3(face + sx * 1.56, 1.5, door_z + 0.15)
		var outward := Vector3(sx, 0.0, 0.0)
		_box(st, plate, Vector3(0.015, 0.42, 0.62), _c(Color(0.12, 0.26, 0.55), K_SIGN), Vector2(0.5, 0.0), 0.004)
		var fig := plate + outward * 0.01 + Vector3(0.0, 0.06, 0.0)
		var white := _c(Color(0.95, 0.95, 0.93), K_SIGN)
		StreetClutter._cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5 * sx), fig + Vector3(0.0, 0.1, 0.0)), 0.035, 0.035, 0.008, white, rm, 10)
		if sx < 0.0:
			_box(st, fig + Vector3(0.0, -0.02, 0.0), Vector3(0.01, 0.12, 0.06), white, rm, 0.0)
		else:
			StreetClutter._tri(st, fig + Vector3(0.006, 0.05, 0.0), fig + Vector3(0.006, -0.08, -0.06), fig + Vector3(0.006, -0.08, 0.06), outward, white, rm)
		_text_front(st, "MEN" if sx < 0.0 else "WOMEN", 0.07, plate + outward * 0.012 + Vector3(0.0, -0.14, 0.0), white, 0.55, outward)
		# The lamp over the door: a cage over a frosted lens.
		var lamp := Vector3(face + sx * 0.1, 2.5, door_z)
		_box(st, lamp, Vector3(0.12, 0.22, 0.3), galv, mrm, 0.02)
		_box(st, lamp + Vector3(sx * 0.07, 0.0, 0.0), Vector3(0.03, 0.16, 0.24), _c(Color(1.0, 0.92, 0.75), K_LAMP), Vector2(0.3, 0.0), 0.01)
		for k in 3:
			_box(st, lamp + Vector3(sx * 0.1, -0.08 + float(k) * 0.08, 0.0), Vector3(0.012, 0.012, 0.3), galv, mrm, 0.0)
	# The sea face: RESTROOMS lettered on the block, a stainless drinking fountain, a hose bib.
	_text_front(st, "RESTROOMS", 0.32, Vector3(0.0, 2.15, -D * 0.5 - 0.01), _c(Color(0.95, 0.95, 0.92), K_SIGN), 4.2)
	var ss := _c(Color(0.78, 0.79, 0.8), K_STAINLESS)
	var srm := Vector2(0.25, 0.95)
	_box(st, Vector3(-2.6, 0.45, -D * 0.5 - 0.22), Vector3(0.3, 0.9, 0.34), ss, srm, 0.02)
	_box(st, Vector3(-2.6, 0.93, -D * 0.5 - 0.3), Vector3(0.4, 0.07, 0.5), ss, srm, 0.02)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(-2.6, 0.96, -D * 0.5 - 0.3)), 0.012, 0.01, 0.06, ss, srm, 6)
	_box(st, Vector3(-2.6, 0.31, -D * 0.5 - 0.42), Vector3(0.22, 0.05, 0.22), ss, srm, 0.01)
	_post(st, Vector3(2.8, 0.4, -D * 0.5 - 0.02), Vector3(2.8, 0.4, -D * 0.5 - 0.14), 0.015, _c(Color(0.62, 0.45, 0.25), K_PAINT), mrm, 6)
	# The land face: the electric box and the downpipes at the corners.
	_box(st, Vector3(1.5, 1.4, D * 0.5 + 0.1), Vector3(0.6, 0.8, 0.2), _c(Color(0.62, 0.64, 0.62), K_GALV), mrm, 0.02)
	for sx: float in [-1.0, 1.0]:
		_post(st, Vector3(sx * (L * 0.5 - 0.15), H, D * 0.5 + 0.12), Vector3(sx * (L * 0.5 - 0.15), 0.1, D * 0.5 + 0.12), 0.05, galv, mrm, 8)
	# The vents' louvres on the end walls too, over the door.
	_text_front(st, "PLEASE CONSERVE WATER", 0.08, Vector3(-2.6, 1.25, -D * 0.5 - 0.01), _c(Color(0.2, 0.2, 0.22), K_SIGN), 0.9)


## The concession stand with its rental counter, 8 x 5 m, the window to the sea.
static func _concession(st: SurfaceTool, variant: int, open: bool) -> void:
	var L := CONCESSION.x
	var H := CONCESSION.y
	var D := CONCESSION.z
	var stucco := _c(Color(0.92, 0.88, 0.78), K_CONCRETE)
	var conc := _c(Color(0.74, 0.73, 0.7), K_CONCRETE)
	var trim := _c(Color(0.16, 0.32, 0.5), K_SIGN)
	var ss := _c(Color(0.8, 0.8, 0.81), K_STAINLESS)
	var srm := Vector2(0.25, 0.95)
	var wood := _c(Color(0.55, 0.4, 0.26), K_WOOD)
	var galv := _c(Color(0.7, 0.71, 0.72), K_GALV)
	var mrm := Vector2(0.4, 0.7)
	var rm := Vector2(0.85, 0.0)
	_box(st, Vector3(0.0, 0.06, -0.8), Vector3(L + 4.0, 0.16, D + 3.6), conc, rm, 0.02)
	_box(st, Vector3(0.0, (H - 0.6) * 0.5, 0.0), Vector3(L, H + 0.6, D), stucco, rm, 0.02)
	# The roof: a deep fascia board carrying the name, a flat roof, a cooler unit.
	_box(st, Vector3(0.0, H + 0.12, 0.0), Vector3(L + 0.6, 0.24, D + 0.6), _c(Color(0.86, 0.84, 0.8), K_CONCRETE), rm, 0.02)
	_box(st, Vector3(0.0, H + 0.42, -D * 0.5 - 0.32), Vector3(L - 0.4, 0.62, 0.08), trim, Vector2(0.5, 0.0), 0.01)
	_text_front(st, String(STAND_NAMES[variant % STAND_NAMES.size()]), 0.36, Vector3(0.0, H + 0.42, -D * 0.5 - 0.37), _c(Color(0.97, 0.95, 0.88), K_SIGN), L - 1.0)
	_box(st, Vector3(1.8, H + 0.55, 0.8), Vector3(1.2, 0.6, 0.9), galv, mrm, 0.02)
	# The serving window: a recess, the menu-lit back, a stainless counter, the shutter.
	var wx := -0.8
	var ww := 4.0
	# The kitchen seen through the window (the body is solid, so it is laid on its face): a dark
	# warm back, the menu over the back counter, a fridge glowing, a shelf of cups.
	_box(st, Vector3(wx, 1.65, -D * 0.5 - 0.01), Vector3(ww, 1.1, 0.02), _c(Color(0.2, 0.15, 0.11), K_SIGN), Vector2(0.8, 0.0), 0.0)
	_box(st, Vector3(wx, 2.02, -D * 0.5 - 0.025), Vector3(ww - 0.4, 0.3, 0.01), _c(Color(0.1, 0.11, 0.1), K_MENU), Vector2(0.6, 0.0), 0.0)
	_box(st, Vector3(wx + 1.3, 1.5, -D * 0.5 - 0.025), Vector3(0.7, 0.75, 0.01), _c(Color(0.75, 0.85, 0.9), K_LAMP), Vector2(0.2, 0.0), 0.0)
	_box(st, Vector3(wx - 0.9, 1.4, -D * 0.5 - 0.12), Vector3(1.4, 0.03, 0.22), ss, srm, 0.005)
	for i in 6:
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(wx - 1.5 + float(i) * 0.24, 1.415, -D * 0.5 - 0.12)), 0.04, 0.05, 0.14, _c(Color(0.95, 0.94, 0.9), K_SIGN), Vector2(0.4, 0.0), 8)
	for sx: float in [-1.0, 1.0]:
		_box(st, Vector3(wx + sx * (ww * 0.5 + 0.05), 1.65, -D * 0.5 - 0.02), Vector3(0.1, 1.2, 0.08), trim, rm, 0.01)
	_box(st, Vector3(wx, 1.08, -D * 0.5 - 0.22), Vector3(ww + 0.2, 0.05, 0.48), ss, srm, 0.01)
	if open:
		_box(st, Vector3(wx, 2.36, -D * 0.5 - 0.16), Vector3(ww + 0.2, 0.3, 0.3), _c(Color(0.7, 0.71, 0.72), K_SHUTTER), mrm, 0.04)
		# Napkins, a tip jar and a menu stand on the counter.
		_box(st, Vector3(wx - 1.3, 1.16, -D * 0.5 - 0.25), Vector3(0.14, 0.12, 0.12), ss, srm, 0.01)
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(wx + 1.2, 1.1, -D * 0.5 - 0.25)), 0.06, 0.07, 0.16, _c(Color(0.4, 0.5, 0.5), K_GLASS), Vector2(0.1, 0.0), 10)
	else:
		_box(st, Vector3(wx, 1.65, -D * 0.5 - 0.06), Vector3(ww + 0.1, 1.2, 0.04), _c(Color(0.7, 0.71, 0.72), K_SHUTTER), mrm, 0.0)
	# The striped awning over it on two arms (instance paint is the stripe's other colour).
	var aw0 := Vector3(wx - ww * 0.5 - 0.3, 2.65, -D * 0.5)
	var aw1 := Vector3(wx + ww * 0.5 + 0.3, 2.65, -D * 0.5)
	var drop := Vector3(0.0, -0.45, -1.5)
	var canvas := _c(Color(0.97, 0.96, 0.92), K_CANVAS)
	var crm := Vector2(0.85, 0.0)
	StreetClutter._quad(st, aw0, aw1, aw1 + drop, aw0 + drop, Vector3(0.0, 1.0, -0.3), canvas, crm)
	StreetClutter._quad(st, aw0 + Vector3(0.0, -0.01, 0.0), aw1 + Vector3(0.0, -0.01, 0.0), aw1 + drop + Vector3(0.0, -0.01, 0.0), aw0 + drop + Vector3(0.0, -0.01, 0.0), Vector3(0.0, -1.0, 0.3), canvas, crm)
	StreetClutter._quad(st, aw0 + drop, aw1 + drop, aw1 + drop + Vector3(0.0, -0.25, 0.0), aw0 + drop + Vector3(0.0, -0.25, 0.0), Vector3(0.0, 0.0, -1.0), canvas, crm)
	for p: Vector3 in [aw0, aw1]:
		_post(st, p + drop + Vector3(0.0, -0.02, 0.0), p + Vector3(0.0, -0.75, 0.0), 0.02, galv, mrm, 6)
	# Menu boards either side of the window.
	for x: float in [wx - ww * 0.5 - 0.75, wx + ww * 0.5 + 0.75]:
		_box(st, Vector3(x, 1.85, -D * 0.5 - 0.04), Vector3(0.9, 1.1, 0.04), _c(Color(0.1, 0.11, 0.1), K_MENU), Vector2(0.6, 0.0), 0.005)
		_box(st, Vector3(x, 1.85, -D * 0.5 - 0.03), Vector3(1.0, 1.2, 0.03), wood, rm, 0.005)
	# A lamp strip under the awning.
	_box(st, Vector3(wx, 2.6, -D * 0.5 - 0.05), Vector3(ww, 0.04, 0.05), _c(Color(1.0, 0.94, 0.8), K_LAMP), Vector2(0.3, 0.0), 0.0)
	# The rental counter round the +x end: a half door, its board, the racks of gear.
	var ex := L * 0.5
	_box(st, Vector3(ex + 0.01, 1.4, 0.0), Vector3(0.02, 1.6, 1.8), _c(Color(0.2, 0.15, 0.1), K_SIGN), rm, 0.0)
	_box(st, Vector3(ex + 0.25, 1.05, 0.0), Vector3(0.5, 0.05, 2.0), wood, rm, 0.01)
	_box(st, Vector3(ex + 0.03, 2.55, 0.0), Vector3(0.05, 0.5, 2.6), _c(Color(0.95, 0.75, 0.2), K_SIGN), Vector2(0.5, 0.0), 0.01)
	_text_front(st, "RENTALS", 0.26, Vector3(ex + 0.07, 2.6, 0.0), _c(Color(0.12, 0.2, 0.35), K_SIGN), 2.2, Vector3.RIGHT)
	_text_front(st, "BOARDS  CHAIRS  UMBRELLAS", 0.07, Vector3(ex + 0.07, 2.38, 0.0), _c(Color(0.12, 0.2, 0.35), K_SIGN), 2.3, Vector3.RIGHT)
	# The boogie board rack: a timber A-frame with boards in it.
	var rk := Vector3(ex + 1.4, 0.0, -1.3)
	for dz: float in [-0.75, 0.75]:
		_post(st, rk + Vector3(-0.35, 0.0, dz), rk + Vector3(0.0, 1.2, dz), 0.035, wood, rm, 5)
		_post(st, rk + Vector3(0.35, 0.0, dz), rk + Vector3(0.0, 1.2, dz), 0.035, wood, rm, 5)
	_post(st, rk + Vector3(0.0, 1.2, -0.8), rk + Vector3(0.0, 1.2, 0.8), 0.03, wood, rm, 5)
	var boards: Array[Color] = [Color(0.35, 0.72, 0.85), Color(0.95, 0.45, 0.25), Color(0.98, 0.84, 0.3), Color(0.25, 0.3, 0.75), Color(0.9, 0.3, 0.5)]
	for i in 5:
		var side := -1.0 if i % 2 == 0 else 1.0
		var bz := rk.z - 0.55 + float(i) * 0.27
		StreetClutter._bbox(st, Transform3D(Basis(Vector3.BACK, side * 0.32), Vector3(rk.x + side * 0.16, 0.6, bz)), Vector3(0.05, 1.0, 0.5), 0.02, _c(boards[i], K_SIGN), Vector2(0.4, 0.0))
	# Surfboards stood on end against a rail.
	var sb := Vector3(ex + 1.2, 0.0, 1.3)
	_post(st, sb + Vector3(-0.25, 1.6, -0.7), sb + Vector3(-0.25, 1.6, 0.7), 0.025, galv, mrm, 6)
	for dz: float in [-0.7, 0.7]:
		_post(st, sb + Vector3(-0.25, 0.0, dz), sb + Vector3(-0.25, 1.6, dz), 0.03, galv, mrm, 6)
	for i in 3:
		var bz := sb.z - 0.42 + float(i) * 0.42
		var lean := Basis(Vector3.BACK, -0.12)
		StreetClutter._bbox(st, Transform3D(lean, Vector3(sb.x, 1.15, bz)), Vector3(0.07, 2.3, 0.52), 0.03, _c(boards[(i + 2) % 5], K_SIGN), Vector2(0.35, 0.0))
	# Folded umbrellas in a stand and stacked chairs.
	var um := Vector3(ex + 2.2, 0.0, 0.1)
	_box(st, um + Vector3(0.0, 0.2, 0.0), Vector3(0.5, 0.4, 0.5), wood, rm, 0.01)
	for i in 4:
		var off := Vector3(-0.12 + 0.24 * float(i % 2), 0.0, -0.12 + 0.24 * float(i / 2))
		_post(st, um + off, um + off + Vector3(0.0, 2.0, 0.0), 0.015, _c(Color(0.9, 0.9, 0.88), K_SIGN), mrm, 5)
		StreetClutter._cyl(st, Transform3D(Basis(), um + off + Vector3(0.0, 1.0, 0.0)), 0.04, 0.09, 0.9, _c(boards[i], K_CANVAS), Vector2(0.85, 0.0), 8)
	for i in 6:
		var y := 0.06 + float(i) * 0.09
		_box(st, Vector3(ex + 0.5, y + 0.25, 1.4 + 0.0), Vector3(0.6, 0.04, 0.55), _c(boards[i % 5], K_SIGN), rm, 0.005)
	# Two picnic tables on the pad in front.
	for tx: float in [-2.8, 1.8]:
		var tc := Vector3(tx, 0.0, -D * 0.5 - 3.0)
		_box(st, tc + Vector3(0.0, 0.76, 0.0), Vector3(1.8, 0.05, 0.75), wood, rm, 0.01)
		for sz: float in [-0.62, 0.62]:
			_box(st, tc + Vector3(0.0, 0.45, sz), Vector3(1.8, 0.04, 0.26), wood, rm, 0.01)
		for sx: float in [-0.7, 0.7]:
			_post(st, tc + Vector3(sx, 0.0, -0.75), tc + Vector3(sx, 0.75, 0.0), 0.025, galv, mrm, 6)
			_post(st, tc + Vector3(sx, 0.0, 0.75), tc + Vector3(sx, 0.75, 0.0), 0.025, galv, mrm, 6)
	# The back: the door, a stack of crates, the vent.
	_box(st, Vector3(-2.5, 1.05, D * 0.5 + 0.01), Vector3(0.95, 2.1, 0.04), trim, rm, 0.005)
	for i in 3:
		_box(st, Vector3(-1.4, 0.18 + float(i) * 0.33, D * 0.5 + 0.35), Vector3(0.5, 0.3, 0.4), _c(Color(0.25, 0.4, 0.62), K_RUBBER), rm, 0.01)


## The gym pen: 14 x 9 m of sand in a timber border, a stepped pull-up rig, the rings, dip bars,
## benches and the sign. Frames in the instance's paint, bars galvanised.
static func _gym(st: SurfaceTool) -> void:
	var paint := _c(Color.WHITE, K_PAINT)
	var galv := _c(Color(0.72, 0.73, 0.74), K_GALV)
	var mrm := Vector2(0.4, 0.75)
	var border := _c(Color(0.62, 0.55, 0.45), K_SANDWOOD)
	var rm := Vector2(0.9, 0.0)
	var hl := HALF.gym.x - 0.5
	var hw := HALF.gym.y - 0.5
	for sz: float in [-1.0, 1.0]:
		_box(st, Vector3(0.0, 0.05, sz * hw), Vector3(hl * 2.0 + 0.2, 0.22, 0.2), border, rm, 0.02)
	for sx: float in [-1.0, 1.0]:
		_box(st, Vector3(sx * hl, 0.05, 0.0), Vector3(0.2, 0.22, hw * 2.0), border, rm, 0.02)
	# The pull-up rig: four posts, three bays stepped 2.1 / 2.4 / 2.7 m.
	var px := [-6.0, -4.9, -3.8, -2.7]
	var tops := [2.2, 2.5, 2.8]
	for i in 4:
		var top: float = tops[mini(i, 2)] if i < 3 else 2.8
		if i > 0:
			top = maxf(top, tops[i - 1])
		_post(st, Vector3(px[i], -0.4, -1.2), Vector3(px[i], top + 0.08, -1.2), 0.055, paint, mrm, 10)
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(px[i], top + 0.08, -1.2)), 0.065, 0.065, 0.03, paint, mrm, 10)
	for i in 3:
		_post(st, Vector3(px[i], tops[i], -1.2), Vector3(px[i + 1], tops[i], -1.2), 0.019, galv, mrm, 8)
	# The rings: two posts with a crossbeam at 3.5 m, chains, two pairs of rings.
	for sx: float in [-1.4, 1.4]:
		_post(st, Vector3(sx, -0.4, 1.5), Vector3(sx, 3.55, 1.5), 0.07, paint, mrm, 10)
	_post(st, Vector3(-1.6, 3.5, 1.5), Vector3(1.6, 3.5, 1.5), 0.06, paint, mrm, 10)
	var chain := _c(Color(0.45, 0.45, 0.44), K_CHAIN)
	for rx: float in [-0.8, -0.25, 0.25, 0.8]:
		var bottom := 2.05
		_post(st, Vector3(rx, 3.44, 1.5), Vector3(rx, bottom + 0.11, 1.5), 0.008, chain, mrm, 4)
		var pts: Array = []
		for k in 13:
			var a := TAU * float(k) / 12.0
			pts.append(Vector3(rx + sin(a) * 0.1, bottom + cos(a) * 0.1, 1.5))
		StreetClutter._tube(st, pts, 0.014, 6, galv, mrm)
	# Dip bars: two parallel bars at 1.2 m on four posts.
	for sz: float in [-0.28, 0.28]:
		for sx: float in [3.2, 5.4]:
			_post(st, Vector3(sx, -0.4, -1.0 + sz), Vector3(sx, 1.2, -1.0 + sz), 0.045, paint, mrm, 8)
		_post(st, Vector3(3.0, 1.2, -1.0 + sz), Vector3(5.6, 1.2, -1.0 + sz), 0.025, galv, mrm, 8)
	# A decline sit-up bench and a flat bench.
	var wood := _c(Color(0.55, 0.42, 0.3), K_WOOD)
	var dec := Basis(Vector3.BACK, 0.28)
	StreetClutter._bbox(st, Transform3D(dec, Vector3(4.2, 0.62, 2.0)), Vector3(1.6, 0.06, 0.38), 0.015, wood, rm)
	for sx: float in [3.55, 4.85]:
		_post(st, Vector3(sx, -0.2, 2.0), Vector3(sx, 0.62 + (sx - 4.2) * 0.29, 2.0), 0.035, paint, mrm, 8)
	_post(st, Vector3(4.95, 0.35, 1.85), Vector3(4.95, 0.35, 2.15), 0.04, _c(Color(0.1, 0.1, 0.1), K_RUBBER), rm, 8)
	_box(st, Vector3(-4.6, 0.48, 2.0), Vector3(1.8, 0.07, 0.4), wood, rm, 0.015)
	for sx: float in [-5.3, -3.9]:
		_box(st, Vector3(sx, 0.22, 2.0), Vector3(0.08, 0.5, 0.34), paint, mrm, 0.01)
	# The sign at the corner.
	_post(st, Vector3(-hl + 0.5, -0.3, -hw - 0.6), Vector3(-hl + 0.5, 2.0, -hw - 0.6), 0.04, galv, mrm, 8)
	_box(st, Vector3(-hl + 0.5, 1.7, -hw - 0.64), Vector3(0.9, 0.55, 0.03), _c(Color(0.1, 0.38, 0.25), K_SIGN), Vector2(0.5, 0.0), 0.005)
	_text_front(st, "OUTDOOR FITNESS", 0.08, Vector3(-hl + 0.5, 1.82, -hw - 0.66), _c(Color(0.95, 0.95, 0.92), K_SIGN), 0.82)
	_text_front(st, "USE AT YOUR OWN RISK", 0.05, Vector3(-hl + 0.5, 1.62, -hw - 0.66), _c(Color(0.95, 0.95, 0.92), K_SIGN), 0.8)


## A beach shower: a stainless column with two heads, push buttons and a foot tap, on its pad.
static func _shower(st: SurfaceTool) -> void:
	var ss := _c(Color(0.8, 0.81, 0.82), K_STAINLESS)
	var srm := Vector2(0.25, 0.95)
	st_pad(st)
	_box(st, Vector3(0.0, 1.22, 0.0), Vector3(0.14, 2.44, 0.14), ss, srm, 0.015)
	_box(st, Vector3(0.0, 2.47, 0.0), Vector3(0.18, 0.05, 0.18), ss, srm, 0.01)
	for sx: float in [-1.0, 1.0]:
		var arm_end := Vector3(sx * 0.48, 2.3, 0.0)
		_post(st, Vector3(sx * 0.06, 2.3, 0.0), arm_end, 0.022, ss, srm, 8)
		StreetClutter._cyl(st, Transform3D(Basis(), arm_end + Vector3(0.0, -0.12, 0.0)), 0.075, 0.03, 0.1, ss, srm, 10)
		_box(st, Vector3(sx * 0.075, 1.2, 0.0), Vector3(0.02, 0.06, 0.06), ss, srm, 0.005)
		StreetClutter._cyl(st, Transform3D(Basis(Vector3.BACK, -sx * PI * 0.5), Vector3(sx * 0.09, 1.2, 0.0)), 0.022, 0.022, 0.02, _c(Color(0.75, 0.2, 0.15), K_PAINT), Vector2(0.4, 0.0), 8)
	_post(st, Vector3(0.0, 0.45, -0.07), Vector3(0.0, 0.45, -0.22), 0.018, ss, srm, 8)
	_post(st, Vector3(0.0, 0.45, -0.22), Vector3(0.0, 0.38, -0.24), 0.016, ss, srm, 8)
	_box(st, Vector3(0.0, 1.7, 0.075), Vector3(0.12, 0.2, 0.01), _c(Color(0.1, 0.32, 0.6), K_SIGN), Vector2(0.5, 0.0), 0.002)


static func st_pad(st: SurfaceTool) -> void:
	_box(st, Vector3(0.0, 0.04, 0.0), Vector3(2.4, 0.12, 2.4), _c(Color(0.72, 0.71, 0.68), K_PAD), Vector2(0.88, 0.0), 0.02)


## A galvanised wave rack (five loops, 2.6 m) on a concrete pad.
static func _rack(st: SurfaceTool) -> void:
	var galv := _c(Color(0.72, 0.73, 0.74), K_GALV)
	var mrm := Vector2(0.4, 0.75)
	_box(st, Vector3(0.0, 0.03, 0.0), Vector3(3.2, 0.1, 1.4), _c(Color(0.73, 0.72, 0.69), K_CONCRETE), Vector2(0.9, 0.0), 0.02)
	var pts: Array = []
	for k in 49:
		var t := float(k) / 48.0
		var x := lerpf(-1.3, 1.3, t)
		var y := 0.05 + 0.8 * absf(sin(t * PI * 5.0))
		pts.append(Vector3(x, y, 0.0))
	StreetClutter._tube(st, pts, 0.03, 8, galv, mrm)


## A painted 55-gallon drum, ribbed, its rim rolled, a dark bin bag showing at the top; the
## recycling one with a white band.
static func _drum(st: SurfaceTool, recycle: bool) -> void:
	var paint := _c(Color.WHITE, K_PAINT)
	var prm := Vector2(0.6, 0.0)
	var r := 0.29
	var h := 0.88
	StreetClutter._cyl(st, Transform3D(), r, r, h, paint, prm, 18)
	for y: float in [0.3, 0.58]:
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, y - 0.015, 0.0)), r + 0.012, r + 0.012, 0.03, paint, prm, 18)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, h - 0.02, 0.0)), r + 0.015, r + 0.015, 0.035, paint, prm, 18)
	# The bag's folded edge over the rim and the dark inside.
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, h - 0.06, 0.0)), r + 0.018, r + 0.02, 0.06, _c(Color(0.06, 0.06, 0.07), K_RUBBER), Vector2(0.4, 0.0), 18)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, h - 0.1, 0.0)), r - 0.02, r - 0.02, 0.112, _c(Color(0.04, 0.04, 0.045), K_RUBBER), Vector2(0.5, 0.0), 14)
	if recycle:
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 0.62, 0.0)), r + 0.004, r + 0.004, 0.16, _c(Color(0.95, 0.95, 0.92), K_SIGN), prm, 18)


## Bare volleyball poles: two galvanised posts with eye bolts and a padded sleeve on one, a court's
## width apart (BeachLife.COURT_SIZE.x + 1.8), across the shore.
static func _poles(st: SurfaceTool) -> void:
	var galv := _c(Color(0.75, 0.76, 0.77), K_GALV)
	var mrm := Vector2(0.4, 0.75)
	var half := BeachLife.COURT_SIZE.x * 0.5 + 0.9
	for sx: float in [-half, half]:
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(sx, -0.6, 0.0)), 0.055, 0.055, 3.25, galv, mrm, 10)
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(sx, 2.65, 0.0)), 0.065, 0.065, 0.03, galv, mrm, 10)
		for y: float in [1.45, 2.4]:
			_post(st, Vector3(sx, y, 0.0), Vector3(sx - signf(sx) * 0.08, y, 0.0), 0.01, galv, mrm, 5)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(half, 0.2, 0.0)), 0.08, 0.08, 1.4, _c(Color(0.15, 0.3, 0.65), K_PAINT), Vector2(0.75, 0.0), 10)


## Builds every mesh on the loading screen.
static func warm() -> Array:
	if not enabled:
		return []
	for k in BLOCK_COLORS.size():
		mesh("restroom_%d" % k)
	for k in STAND_NAMES.size():
		mesh("concession_%d" % k)
		mesh("concession_%d_shut" % k)
	for key: String in ["gym", "shower", "rack", "drum_trash", "drum_recycle", "vb_poles"]:
		mesh(key)
	return [material()]
