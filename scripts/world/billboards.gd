class_name Billboards
extends RefCounted
## Los Angeles billboards and supergraphics (2026-10-04, VISUAL_ROADMAP #54; docs/HANDOFF.md 9bl).
##
## LA's streets and freeways are lined with outdoor advertising, and ours had one box on a roof.
## Now, all built in code at real sizes:
##   * BULLETINS (14 x 48 ft, 4.27 x 14.63 m) on steel I-beam legs on the roofs of low commercial
##     buildings in MIDTOWN and at downtown's edge, facing the street or standing across it to face
##     the traffic; on the "strip" avenues (a hash of the road: Sunset-Strip-like stretches) most
##     low buildings carry one and a share are DIGITAL (LED slides).
##   * POSTERS (12 x 24 ft, 3.66 x 7.32 m): Building's own roof-plant billboard roll (a box until
##     now) is a real poster structure where it always stood (Building keeps its rolls; FarBuilding
##     keeps its far box, now the poster's size and the ad's colour).
##   * MONOPOLES beside the freeways: one 1.1 m column in the right of way, a V of two bulletins
##     on a head frame 4 m over the deck, the V's point toward the road so each face looks at one
##     carriageway's traffic, every POLE_EVERY segments a route by hash, only in a corridor lot,
##     clear of every deck (Freeway.blocks()) and of any lot whose building reaches the faces.
##   * SUPERGRAPHICS: perforated vinyl wraps over the street face of glass and panel towers.
##   * BUS SHELTER ADS: a double-sided lightbox at the end of every shelter (StreetDetail).
## Every face is a unit of the frame kit: the face, a trim, a back sheet with stringers, uprights
## and X-bracing, a grated catwalk with a rail, lighting arms with fixtures; legs, a pole, a head.
##
## The art is ONE atlas, assets/textures/billboards/billboard_ads.jpg, drawn by
## tools/make_billboard_art.py: twelve invented campaigns (films, a soda, a phone, a lawyer with a
## 555 number, an energy drink, a show, SUNCREST AIR, ...) as bulletins and posters, six as
## portraits. shaders/billboard_face.gdshader wears it per instance: paper sheet seams with their
## misregistration, sun fade, a torn patch showing the poster under it; the vinyl's sheen and edge
## pull; the mesh vinyl's perforations and panel seams; the lightbox; LED slides with the dot
## pitch; and at night the wash of the fixtures (lamp_factor). The steel is
## shaders/billboard_steel.gdshader (galvanised, painted, rust, the fixtures' lenses lit at night).
##
## Frame cost: ONE batch per kind per chunk (faces by format, frames by format, legs, pole, head,
## base), each board a breakable prop ("billboard": its instances and its collision, like a lamp).
## LOD chunks and the far city (capture mode) keep every face as a far box (the roof plant's PANEL
## kind, lit at night, LED boards self-lit) and the pole as a MAST, so the skyline reads.
## Hashes of seed + block / building / segment only, never the block rng or Building._rng; the
## boards' props are placed in a deferred step just before the finish, so the block's own props
## keep their ids. `enabled` false (BILLBOARDS=0 in the environment) is the A/B.

static var enabled: bool = OS.get_environment("BILLBOARDS") != "0"

const BULLETIN := Vector2(14.63, 4.27)
const POSTER := Vector2(7.32, 3.66)
## The shelter's lightbox face (a 4 x 6 ft panel shows about this much).
const SHELTER_FACE := Vector2(1.19, 1.76)
## Roof to face bottom: a bulletin's I-beam legs and a poster's.
const LEG_BULLETIN := 3.6
const LEG_POSTER := 2.47
## A monopole: the column's radius, the faces' bottom over the deck, its lateral distance from
## the route's centre line past the deck edge, and the V's half opening.
const POLE_RADIUS := 0.55
const POLE_FACE_RISE := 4.0
const POLE_OFFSET := 11.0
const V_ANGLE := 0.19
## One monopole every this many deck segments of a route (Freeway.STEP 24 m), by hash.
const POLE_EVERY := 7
const POLE_DIGITAL := 0.3
## No two monopoles of a block closer than this.
const POLE_SPACING := 140.0

## Rooftop bulletins: the chance a qualifying building carries one, by district; on a strip.
const ROOF_CHANCE := {CityPlan.District.MIDTOWN: 0.2, CityPlan.District.DOWNTOWN: 0.12, CityPlan.District.INDUSTRIAL: 0.06}
const ROOF_MAX_HEIGHT := 17.0
const ROOF_MIN_HEIGHT := 5.0
const STRIP_SHARE := 0.22
const STRIP_CHANCE := 0.7
const STRIP_DIGITAL := 0.4
const LIT_SHARE := 0.85
## Supergraphics: towers at least this tall, glass or panel finish, this share of them.
const SUPER_MIN_HEIGHT := 42.0
const SUPER_CHANCE := 0.12
const SUPER_OFFSET := 0.28

## How far the frames and legs draw (the faces draw as far as their chunk does).
const FRAME_DRAW := 380.0
const SMALL_DRAW := 160.0

enum Fmt { BULLETIN, POSTER, PORTRAIT, DIGITAL }
const ADS := 12
const PORTRAITS := 6

## Steel paint kinds in the vertex alpha (billboard_steel.gdshader).
enum Steel { PAINT, LENS, GRATING, SHEET, GALV, CONCRETE }

const C_STEEL := Color(0.30, 0.31, 0.30)
const C_GALV := Color(0.56, 0.57, 0.56)
const C_SHEET := Color(0.20, 0.23, 0.21)
const C_TRIM := Color(0.12, 0.12, 0.13)
const C_FIXTURE := Color(0.18, 0.18, 0.19)
const C_LENS := Color(0.95, 0.93, 0.86)
const C_CONCRETE := Color(0.62, 0.61, 0.58)
const C_ALU := Color(0.70, 0.71, 0.72)

static var _cache := {}
static var _debug: bool = OS.get_environment("BB_DEBUG") == "1"


## The atlas and the face's material (one shared material: everything per board is instance data).
static func face_material() -> ShaderMaterial:
	if _cache.has("face_mat"):
		return _cache.face_mat
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/billboard_face.gdshader")
	m.set_shader_parameter("atlas", load("res://assets/textures/billboards/billboard_ads.jpg"))
	_cache.face_mat = m
	return m


static func steel_material() -> ShaderMaterial:
	if _cache.has("steel_mat"):
		return _cache.steel_mat
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/billboard_steel.gdshader")
	_cache.steel_mat = m
	return m


## The far box's colour for an ad (sRGB, as the far plant boxes take a Building colour).
static func far_color(fmt: int, ad: int) -> Color:
	var c: Color
	match fmt:
		Fmt.POSTER:
			c = BillboardTable.POSTER_MEAN[posmod(ad, ADS)]
		Fmt.PORTRAIT:
			c = BillboardTable.PORTRAIT_MEAN[posmod(ad, PORTRAITS)]
		_:
			c = BillboardTable.BULLETIN_MEAN[posmod(ad, ADS)]
	return c.linear_to_srgb()


## The ad on Building's roof-plant poster at `at` (building space). A hash: Building's roof stream
## and FarBuilding agree on it with nothing shared.
static func roof_poster_ad(building_seed: int, at: Vector3) -> int:
	return absi(hash([building_seed, "bb_roof", roundi(at.x * 10.0), roundi(at.z * 10.0)])) % ADS


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## Face-local +Z turned to world direction `d` (XZ).
static func yaw_of(d: Vector2) -> float:
	return atan2(d.x, d.y)


# ------------------------------------------------------------------------------- placement

## A planned board unit: the frame `xf` (face-local: face plane z 0 facing +Z, bottom edge at y 0,
## centred in x; chunk space, true heights), its format, ad, lit and digital flags.
static func _unit(xf: Transform3D, fmt: int, ad: int, lit: bool, wear: float) -> Dictionary:
	return {"xf": xf, "fmt": fmt, "ad": ad, "lit": lit, "wear": wear}


## After a lot's Building is planned (LOD) or built (FULL): its rooftop board, its roof-plant
## posters (FULL; the far boxes are FarBuilding's) and its supergraphic. FULL queues them for
## commit(); LOD lays their far boxes at once.
static func on_building(ch: CityChunk, lot: Dictionary, building: Building, district: int) -> void:
	if not enabled or ch.plan == null:
		return
	var origin: Vector3 = building.position
	var jobs: Array = ch.billboard_jobs
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		for k in building.roof_props.size():
			var prop: Array = building.roof_props[k]
			if String(prop[0]) != "billboard":
				continue
			var rolls: Dictionary = prop[2]
			var at: Vector3 = origin + (prop[1] as Vector3)
			var yaw: float = rolls.get("yaw", 0.0)
			var ad: int = rolls.get("ad", roof_poster_ad(building.seed, prop[1]))
			var xf := Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0.0, LEG_POSTER, 0.0))
			jobs.append({"kind": "roof", "anchor": at, "units": [_unit(xf, Fmt.POSTER, ad, true, _h01([building.seed, "bb_wear", k]))], "legs": "p"})
	var roof := _roof_board(ch, lot, building, district)
	if not roof.is_empty():
		_queue_or_far(ch, roof)
	var sg := _supergraphic(ch, lot, building, district)
	if not sg.is_empty():
		_queue_or_far(ch, sg)


static func _queue_or_far(ch: CityChunk, job: Dictionary) -> void:
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		ch.billboard_jobs.append(job)
	else:
		_far_boxes(ch, job)


## Which road a lot's street face is on: [axis, index] (CityChunk's block ix spans roads ix..ix+1).
static func _face_road(ch: CityChunk, face: int) -> Array:
	match face:
		1: return [CityPlan.AXIS_X, ch.ix + 1]
		2: return [CityPlan.AXIS_X, ch.ix]
		3: return [CityPlan.AXIS_Z, ch.iz + 1]
	return [CityPlan.AXIS_Z, ch.iz]


## A strip: a wide road in MIDTOWN (or downtown's edge) that a hash picks for boards - the
## Sunset-Strip-like stretches, where most low buildings carry one and some are digital.
static func is_strip(plan: CityPlan, axis: int, index: int) -> bool:
	if plan.road_width(axis, index) < plan.avenue_width - 0.5:
		return false
	return _h01([plan.seed, axis, index, "bb_strip"]) < STRIP_SHARE


static func _face_dir(face: int) -> Vector2:
	match face:
		1: return Vector2(1, 0)
		2: return Vector2(-1, 0)
		3: return Vector2(0, 1)
	return Vector2(0, -1)


## The roof bulletin of one low commercial building, or {}.
static func _roof_board(ch: CityChunk, lot: Dictionary, b: Building, district: int) -> Dictionary:
	if not ROOF_CHANCE.has(district) or b.height > ROOF_MAX_HEIGHT or b.height < ROOF_MIN_HEIGHT:
		return {}
	if b.shape == Building.Shape.WAREHOUSE and district != CityPlan.District.INDUSTRIAL:
		return {}
	# Only a lot on the pavement: a board deep inside a block is behind its neighbours.
	if not bool(lot.get("edge", true)):
		return {}
	var center: Vector2 = lot.center
	if district == CityPlan.District.DOWNTOWN and ch.plan.macro and ch.plan.macro.skyline_boost(center) > 0.05:
		return {}
	var face := LotFill.street_face(ch, lot)
	var road := _face_road(ch, face)
	var strip := (district != CityPlan.District.INDUSTRIAL) and is_strip(ch.plan, road[0], road[1])
	var chance: float = STRIP_CHANCE if strip else float(ROOF_CHANCE[district])
	if _h01([ch.plan.seed, b.seed, "bb_roof_board"]) >= chance:
		return {}
	# The highest part's roof (the building's top), and the street side of it.
	var top_i := -1
	var top_y := -INF
	for i in b.parts.size():
		var p: Dictionary = b.parts[i]
		var t: float = (p.center as Vector3).y + (p.size as Vector3).y * 0.5
		if t > top_y + 0.01:
			top_y = t
			top_i = i
	if top_i < 0:
		return {}
	var part: Dictionary = b.parts[top_i]
	var size: Vector3 = part.size
	var pc: Vector3 = part.center
	# Anything tall on that roof (another part, a water tank, a spire) keeps the board off it.
	for p: Dictionary in b.parts:
		if p != part and (p.center as Vector3).y + (p.size as Vector3).y * 0.5 > top_y - 0.5:
			return {}
	for prop: Array in b.roof_props:
		if String(prop[0]) in ["billboard", "water_tower", "spire", "antenna", "cooling_tower"]:
			return {}
	var n := _face_dir(face)
	var along := Vector2(-n.y, n.x)
	var half := Vector2(size.x, size.z) * 0.5
	var depth := absf(n.x) * half.x + absf(n.y) * half.y
	var span := absf(along.x) * half.x + absf(along.y) * half.y
	var roof := b.position + Vector3(pc.x, top_y, pc.z)
	var w := BULLETIN.x
	var across := _h01([ch.plan.seed, b.seed, "bb_across"]) < 0.45
	var units: Array = []
	var digital := strip and _h01([ch.plan.seed, b.seed, "bb_digital"]) < STRIP_DIGITAL
	var lit := digital or _h01([ch.plan.seed, b.seed, "bb_lit"]) < LIT_SHARE
	var ad := absi(hash([ch.plan.seed, b.seed, "bb_ad"])) % ADS
	var wear := _h01([ch.plan.seed, b.seed, "bb_wear"])
	var fmt := Fmt.DIGITAL if digital else Fmt.BULLETIN
	if across:
		# Standing across the street edge, back to back: one face for each direction of traffic.
		if depth * 2.0 < w * 0.72 or span * 2.0 < 4.0:
			across = false
		else:
			var side := 1.0 if _h01([ch.plan.seed, b.seed, "bb_side"]) < 0.5 else -1.0
			var c2 := Vector2(roof.x, roof.z) + n * (depth - w * 0.5 + 1.2) + along * side * (span - 2.2)
			var c3 := Vector3(c2.x, roof.y + LEG_BULLETIN, c2.y)
			for s: float in [1.0, -1.0]:
				var d := along * s
				var basis := Basis(Vector3.UP, yaw_of(d))
				units.append(_unit(Transform3D(basis, c3 + Vector3(d.x, 0.0, d.y) * 0.95), fmt, (ad + (0 if s > 0.0 else 5)) % ADS, lit, wear))
	if not across:
		if span * 2.0 < w * 0.8:
			if span * 2.0 < POSTER.x * 0.9:
				return {}
			w = POSTER.x
			fmt = Fmt.POSTER
		var c2 := Vector2(roof.x, roof.z) + n * (depth - 1.6)
		var leg := LEG_BULLETIN if fmt != Fmt.POSTER else LEG_POSTER
		var basis := Basis(Vector3.UP, yaw_of(n))
		units.append(_unit(Transform3D(basis, Vector3(c2.x, roof.y + leg, c2.y)), fmt, ad, lit, wear))
	return {"kind": "roof", "anchor": roof, "units": units, "legs": "p" if fmt == Fmt.POSTER else "b"}


## A supergraphic over the street face of a glass or panel tower, or {}.
static func _supergraphic(ch: CityChunk, lot: Dictionary, b: Building, district: int) -> Dictionary:
	if district != CityPlan.District.DOWNTOWN and district != CityPlan.District.MIDTOWN:
		return {}
	if b.height < SUPER_MIN_HEIGHT or not (b.finish == Building.Finish.GLASS or b.finish == Building.Finish.PANELS):
		return {}
	if _h01([ch.plan.seed, b.seed, "bb_super"]) >= SUPER_CHANCE:
		return {}
	var best := -1
	var best_h := 0.0
	for i in b.parts.size():
		var p: Dictionary = b.parts[i]
		if int(p.get("podium", 0)) > 0:
			continue
		if (p.size as Vector3).y > best_h:
			best_h = (p.size as Vector3).y
			best = i
	if best < 0:
		return {}
	var part: Dictionary = b.parts[best]
	var size: Vector3 = part.size
	var pc: Vector3 = part.center
	var face := LotFill.street_face(ch, lot)
	var n := _face_dir(face)
	var half := Vector2(size.x, size.z) * 0.5
	var along_len := (absf(n.y) * half.x + absf(n.x) * half.y) * 2.0
	if along_len < 14.0:
		return {}
	var depth := absf(n.x) * half.x + absf(n.y) * half.y
	var w := clampf(along_len * 0.78, 12.0, 34.0)
	var bottom := maxf(10.0, size.y * 0.14)
	var avail := size.y - bottom - maxf(6.0, size.y * 0.1)
	var h := w * 1.5
	if h > avail:
		h = avail
		w = h / 1.5
	if w < 10.0:
		return {}
	var base_y: float = b.position.y + pc.y - size.y * 0.5 + bottom
	var c2 := Vector2(b.position.x + pc.x, b.position.z + pc.z) + n * (depth + SUPER_OFFSET)
	var basis := Basis(Vector3.UP, yaw_of(n)).scaled_local(Vector3(w, h, 1.0))
	var ad := absi(hash([ch.plan.seed, b.seed, "bb_super_ad"])) % PORTRAITS
	return {"kind": "super", "anchor": Vector3(c2.x, base_y, c2.y), "xf": Transform3D(basis, Vector3(c2.x, base_y, c2.y)), "ad": ad,
		"size": Vector2(w, h), "wear": _h01([ch.plan.seed, b.seed, "bb_wear"])}


## The block's freeway monopoles (CityChunk, a block step after the lots): planned purely from the
## deck segments the chunk owns and the plan's lots; FULL queues them and commits every queued
## board in a step just before the finish, LOD lays the far boxes.
static func block_step(ch: CityChunk, block: Dictionary) -> void:
	if not enabled:
		return
	for job: Dictionary in monopoles(ch.plan, ch.ix, ch.iz, block):
		_queue_or_far(ch, job)
	if ch.level == CityChunk.Level.FULL and not ch.capturing and not ch.billboard_jobs.is_empty():
		ch._run_or_defer(func() -> bool:
			commit(ch)
			return true)


## Every monopole of block (ix, iz): pure.
static func monopoles(plan: CityPlan, ix: int, iz: int, block: Dictionary) -> Array:
	var out: Array = []
	if plan.macro == null or plan.macro.freeway == null:
		return out
	var fw: Freeway = plan.macro.freeway
	var rect: Rect2 = block.rect
	var inner := rect.grow(-plan.sidewalk_width - 1.0)
	var district: int = block.district
	var corridor: Array[Rect2] = []
	var others: Array = []
	for lot: Dictionary in plan.lots(ix, iz):
		var r := Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size)
		if fw.blocks(lot.center, 14.0) or fw.blocks_rect(r, CityChunk.LOT_FREEWAY_MARGIN):
			corridor.append(r.grow(-0.6))
		else:
			var boost := plan.macro.skyline_boost(lot.center)
			others.append([r.grow(1.5), plan.lot_height(lot.seed, district, boost)])
	if corridor.is_empty():
		return out
	for s: Dictionary in fw.segments_in(rect):
		var a: Vector2 = s.a
		var bpt: Vector2 = s.b
		var mid := a.lerp(bpt, 0.5)
		if not rect.has_point(mid) or a.distance_to(bpt) < 1.0:
			continue
		if absi(hash([plan.seed, s.route, s.index, "bb_pole"])) % POLE_EVERY != 0:
			continue
		var dir := (bpt - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var first := 1.0 if _h01([plan.seed, s.route, s.index, "bb_pole_side"]) < 0.5 else -1.0
		var near := false
		for o: Dictionary in out:
			near = near or Vector2((o.anchor as Vector3).x, (o.anchor as Vector3).z).distance_to(mid) < POLE_SPACING
		if near:
			continue
		for side: float in [first, -first]:
			var job := _pole_at(plan, fw, s, mid, dir, nrm * side, inner, corridor, others)
			if not job.is_empty():
				out.append(job)
				break
	return out


static func _pole_at(plan: CityPlan, fw: Freeway, s: Dictionary, mid: Vector2, dir: Vector2, out_dir: Vector2,
		inner: Rect2, corridor: Array[Rect2], others: Array) -> Dictionary:
	var width: float = s.width
	var p := mid + out_dir * (width * 0.5 + POLE_OFFSET)
	if not inner.has_point(p):
		return {}
	var in_corridor := false
	for r: Rect2 in corridor:
		if r.has_point(p):
			in_corridor = true
			break
	if not in_corridor or fw.blocks(p, 2.0):
		return {}
	var deck: float = lerpf(float(s.ha), float(s.hb), 0.5)
	var face_y := deck + POLE_FACE_RISE
	# The V: in the pole's frame +X runs away from the deck and +Z along the route; the point is at
	# the deck side, each face turned V_ANGLE toward its traffic.
	var out3 := Vector3(out_dir.x, 0.0, out_dir.y)
	var pole_basis := Basis(out3, Vector3.UP, out3.cross(Vector3.UP))
	var units: Array = []
	var digital := _h01([plan.seed, s.route, s.index, "bb_pole_led"]) < POLE_DIGITAL
	var ad := absi(hash([plan.seed, s.route, s.index, "bb_pole_ad"])) % ADS
	var wear := _h01([plan.seed, s.route, s.index, "bb_wear"])
	for k in 2:
		var local := v_face_local(k)
		var xf := Transform3D(pole_basis, Vector3(p.x, face_y, p.y)) * local
		units.append(_unit(xf, Fmt.DIGITAL if digital else Fmt.BULLETIN, (ad + k * 7) % ADS, true, wear))
		# Both faces' ends clear of every deck, and of any lot whose building reaches them.
		# The face's whole footprint (its axis-aligned box, as the downtown freeway check reads the
		# far boxes) clear of every deck and ramp.
		var foot := Rect2(Vector2(xf.origin.x, xf.origin.z), Vector2.ZERO)
		for cx: float in [-0.5, 0.5]:
			for cz: float in [-0.9, 0.0]:
				var q := xf * Vector3(BULLETIN.x * cx, 0.0, cz)
				foot = foot.expand(Vector2(q.x, q.z))
		if fw.blocks_rect(foot, 0.5):
			return {}
		for t: float in [-0.5, 0.0, 0.5]:
			var e3 := xf * Vector3(BULLETIN.x * t, 0.0, 0.0)
			var e := Vector2(e3.x, e3.z)
			if fw.blocks(e, 1.0):
				return {}
			for o: Array in others:
				if (o[0] as Rect2).has_point(e) and float(o[1]) + plan.height_at(e) > face_y - 1.0:
					return {}
	var ground := plan.height_at(p)
	return {"kind": "pole", "anchor": Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y), "units": units,
		"pole": Transform3D(pole_basis, Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y)), "pole_top": face_y - 0.55, "ground": ground}


## Face k (0, 1) of a monopole V in the pole's frame (origin the pole's axis at the faces' bottom).
static func v_face_local(k: int) -> Transform3D:
	var sa := sin(V_ANGLE)
	var ca := cos(V_ANGLE)
	var w := BULLETIN.x
	# The point (both faces' deck-side ends) and each face's frame from it.
	var e := Vector3(-w * ca * 0.5, 0.0, 0.0)
	if k == 0:
		var basis := Basis(Vector3.UP, -V_ANGLE)
		return Transform3D(basis, e + basis.x * (w * 0.5) + basis.z * 0.8)
	var basis := Basis(Vector3.UP, PI + V_ANGLE)
	return Transform3D(basis, e - basis.x * (w * 0.5) + basis.z * 0.8)


# --------------------------------------------------------------------------------- commit

## Places every queued board of a FULL chunk as a prop (its instances in the chunk's batches,
## its collision on the chunk's StreetProps): one batch per kind per chunk.
static func commit(ch: CityChunk) -> void:
	for job: Dictionary in ch.billboard_jobs:
		var inst: Array = []
		var shapes: Array = []
		var anchor: Vector3 = job.anchor
		var g := ch._gy(anchor.x, anchor.z)
		if job.kind == "pole":
			# A pole's anchor is on the ground, which the plan gives without the chunk's relief.
			anchor.y += g
		match String(job.kind):
			"super":
				var xf: Transform3D = job.xf
				var sz: Vector2 = job.size
				if _debug:
					var nz := xf.basis.z.normalized()
					var eye := xf.origin + nz * (sz.y * 1.1 + 20.0)
					print("  FACE super ad %d at %s size %s EYE=%.1f,1.7,%.1f,%.0f,%.0f (EYE_AGL=1)" % [job.ad, xf.origin.snapped(Vector3.ONE * 0.1), sz,
						eye.x, eye.z, rad_to_deg(atan2(nz.x, nz.z)), rad_to_deg(atan2(xf.origin.y + sz.y * 0.5, sz.y * 1.1 + 20.0)) * 0.8])
				inst.append(_inst(ch, "bb_face_super", super_mesh(), xf, Fmt.PORTRAIT, int(job.ad), false, float(job.wear)))
				var c := xf * Vector3(0.0, 0.5, -0.1)
				shapes.append([Vector3(sz.x, sz.y, 0.2), c - Vector3(0.0, g, 0.0), xf.basis.orthonormalized().get_euler().y])
			_:
				for u: Dictionary in job.units:
					var xf: Transform3D = u.xf
					if _debug:
						# tools/billboard_probe.tscn: an EYE 40 m out in front of each face, looking at it.
						var nz := xf.basis.z
						var rect: Rect2 = ch.plan.block(ch.ix, ch.iz).rect
						var o2 := Vector2(xf.origin.x, xf.origin.z)
						var d2 := Vector2(nz.x, nz.z)
						var t := 0.0
						while rect.has_point(o2 + d2 * t) and t < 400.0:
							t += 1.0
						var eye := o2 + d2 * (t + 9.0)
						var up := rad_to_deg(atan2(xf.origin.y - 2.0, t + 9.0))
						print("  FACE %s fmt %d ad %d at %s EYE=%.1f,1.7,%.1f,%.0f,%.0f (EYE_AGL=1)" % [job.kind, u.fmt, u.ad, xf.origin.snapped(Vector3.ONE * 0.1),
							eye.x, eye.y, rad_to_deg(atan2(nz.x, nz.z)), up * 0.7])
					var fmt: int = u.fmt
					var poster := fmt == Fmt.POSTER
					var size := POSTER if poster else BULLETIN
					inst.append(_inst(ch, "bb_face_p" if poster else "bb_face_b", face_mesh(poster), xf, fmt, int(u.ad), bool(u.lit), float(u.wear)))
					inst.append(_raw(ch, "bb_frame_p" if poster else "bb_frame_b", frame_mesh(poster), xf))
					if job.kind == "roof":
						inst.append(_raw(ch, "bb_legs_" + String(job.legs), legs_mesh(String(job.legs) == "p"), xf))
					else:
						inst.append(_raw(ch, "bb_head", head_mesh(), xf))
					var c := xf * Vector3(0.0, size.y * 0.5, -0.3)
					shapes.append([Vector3(size.x, size.y + 0.4, 1.0), c - Vector3(0.0, g, 0.0), xf.basis.get_euler().y])
				if job.kind == "pole":
					var pxf: Transform3D = job.pole
					var ground_y := pxf.origin.y + ch._gy(pxf.origin.x, pxf.origin.z)
					var hgt: float = float(job.pole_top) - ground_y
					var col := Transform3D(pxf.basis.scaled_local(Vector3(1.0, hgt, 1.0)), pxf.origin)
					inst.append([ "bb_pole", pole_mesh(), col, Color.WHITE, Color.BLACK])
					inst.append([ "bb_base", base_mesh(), pxf, Color.WHITE, Color.BLACK])
					shapes.append([Vector3(POLE_RADIUS * 2.0, hgt, POLE_RADIUS * 2.0), pxf.origin + Vector3(0.0, hgt * 0.5 + ch._gy(pxf.origin.x, pxf.origin.z) - g, 0.0), 0.0])
		ch._add_prop("billboard", anchor - Vector3(0.0, g, 0.0), Color(0.3, 0.31, 0.3), inst, shapes)
	ch.billboard_jobs.clear()
	for key in ["bb_frame_b", "bb_frame_p", "bb_legs_b", "bb_legs_p", "bb_head", "bb_pole", "bb_base"]:
		ch._batch.set_draw_distance(key, FRAME_DRAW)


## A face instance: [key, mesh, transform with the batch's relief lift taken off, white, custom].
## Custom: r ad / 32, g format / 4, b wear, a lit (1) or not (0).
static func _inst(ch: CityChunk, key: String, mesh: Mesh, xf: Transform3D, fmt: int, ad: int, lit: bool, wear: float) -> Array:
	var r := _raw(ch, key, mesh, xf)
	r[4] = Color(float(ad) / 32.0, float(fmt) / 4.0, floorf(wear * 255.0) / 256.0, 1.0 if lit else 0.0)
	return r


static func _raw(ch: CityChunk, key: String, mesh: Mesh, xf: Transform3D) -> Array:
	var o := xf.origin
	o.y -= ch._gy(o.x, o.z)
	return [key, mesh, Transform3D(xf.basis, o), Color.WHITE, Color.BLACK]


## The far boxes of a board (LOD chunks; the far city captures them): each face as the roof plant's
## PANEL box in its ad's colour, lit at night (custom.b 1, LED 2, unlit 0.5), the pole as a MAST.
static func _far_boxes(ch: CityChunk, job: Dictionary) -> void:
	var flag := FarBuilding.PLANT_FLAG
	if job.kind == "super":
		var xf: Transform3D = job.xf
		var sz: Vector2 = job.size
		var basis := Basis(Vector3.UP, xf.basis.orthonormalized().get_euler().y).scaled_local(Vector3(sz.x, sz.y, 0.12))
		_far_add(ch, Transform3D(basis, xf * Vector3(0.0, 0.5, 0.0)), far_color(Fmt.PORTRAIT, int(job.ad)), Color(float(FarBuilding.Plant.PANEL), 1.0, 0.5, flag))
		return
	for u: Dictionary in job.units:
		var xf: Transform3D = u.xf
		var size := POSTER if int(u.fmt) == Fmt.POSTER else BULLETIN
		var basis := Basis(Vector3.UP, xf.basis.get_euler().y).scaled_local(Vector3(size.x, size.y, 0.7))
		var lit := 2.0 if int(u.fmt) == Fmt.DIGITAL else (1.0 if bool(u.lit) else 0.5)
		_far_add(ch, Transform3D(basis, xf * Vector3(0.0, size.y * 0.5, -0.3)), far_color(int(u.fmt), int(u.ad)), Color(float(FarBuilding.Plant.PANEL), 1.0, lit, flag))
	if job.kind == "pole":
		var pxf: Transform3D = job.pole
		var ground_y := pxf.origin.y + ch._gy(pxf.origin.x, pxf.origin.z)
		var hgt: float = float(job.pole_top) - ground_y
		var at := Vector3(pxf.origin.x, ground_y + hgt * 0.5, pxf.origin.z)
		_far_add(ch, Transform3D(Basis.from_scale(Vector3(1.1, hgt, 1.1)), at), C_STEEL, Color(float(FarBuilding.Plant.MAST), 1.0, 0.0, flag))


## One far box at a TRUE height (the batch adds the relief at the box's origin; take it off).
static func _far_add(ch: CityChunk, xf: Transform3D, colour: Color, custom: Color) -> void:
	var o := xf.origin
	o.y -= ch._gy(o.x, o.z)
	ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(xf.basis, o), colour, custom)


## The bus shelter's ad panel (StreetDetail._bus_shelter() adds it to the shelter's prop): an
## instance entry for its _add_prop() list at the shelter's downstream end, facing along the kerb.
static func shelter_instance(seed_value: int, at: Vector3, back: Vector3, along: Vector3) -> Array:
	var d := Vector2(along.x, along.z).normalized()
	var basis := Basis(Vector3.UP, yaw_of(d) + PI * 0.5)
	var ad := absi(hash([seed_value, "bb_shelter", roundi(at.x), roundi(at.z)])) % PORTRAITS
	var wear := _h01([seed_value, "bb_shelter_wear", roundi(at.x), roundi(at.z)])
	var pos := at + back * 0.5 - along.normalized() * 2.0
	return ["bb_shelter", shelter_mesh(), Transform3D(basis, pos), Color.WHITE,
		Color(float(ad) / 32.0, float(Fmt.PORTRAIT) / 4.0, floorf(wear * 255.0) / 256.0, 1.0)]


# ---------------------------------------------------------------------------------- meshes

## Geometry accumulator: flat-shaded boxes and quads with sRGB vertex colours (kind in alpha) or
## face UVs, built into an ArrayMesh directly.
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var tg := PackedFloat32Array()

	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color, t0 := Vector2.ZERO, t1 := Vector2.ZERO, t2 := Vector2.ZERO, t3 := Vector2.ZERO, m := Vector2.ONE) -> void:
		# p0..p3 counter-clockwise seen from the side the face faces (written clockwise: Godot's
		# front faces wind clockwise, FreewayKit.tri()).
		var nn := (p1 - p0).cross(p3 - p0).normalized()
		var tan3 := (p1 - p0).normalized()
		for i in [0, 2, 1, 0, 3, 2]:
			v.append([p0, p1, p2, p3][i])
			n.append(nn)
			c.append(col)
			var t: Vector2 = [t0, t1, t2, t3][i]
			uv.append(t)
			uv2.append(Vector2((t.x - (2.0 if t.x > 1.5 else 0.0)) * m.x, (1.0 - t.y) * m.y))
			tg.append_array([tan3.x, tan3.y, tan3.z, 1.0])

	## A triangle a, b, c counter-clockwise seen from its front.
	func tri(a: Vector3, b: Vector3, c3: Vector3, col: Color) -> void:
		var nn := (b - a).cross(c3 - a).normalized()
		for p in [a, c3, b]:
			v.append(p)
			n.append(nn)
			c.append(col)
			uv.append(Vector2.ZERO)
			uv2.append(Vector2.ZERO)
			tg.append_array([1.0, 0.0, 0.0, 1.0])

	## A box of `size` centred at xf's origin in xf's frame.
	func box(xf: Transform3D, size: Vector3, col: Color) -> void:
		var h := size * 0.5
		var p := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x * h.x, y * h.y, z * h.z)
		quad(p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), col)
		quad(p.call(1, -1, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1), col)
		quad(p.call(1, -1, 1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1), col)
		quad(p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1), col)
		quad(p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1), p.call(-1, 1, -1), col)
		quad(p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1), col)

	## An axis-aligned box from corner a to corner b.
	func abox(a: Vector3, b: Vector3, col: Color) -> void:
		box(Transform3D(Basis(), (a + b) * 0.5), (b - a).abs(), col)

	## A square-section strut from a to b (`w` thick), its local y along a->b.
	func strut(a: Vector3, b: Vector3, w: float, col: Color, d: float = -1.0) -> void:
		var y := b - a
		var len := y.length()
		if len < 0.001:
			return
		y /= len
		var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var x := y.cross(ref).normalized()
		var z := x.cross(y)
		box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, len, d if d > 0.0 else w), col)

	## A vertical I-beam (wide flange) from y0 to y1 at (x, z), its web across z (flanges facing x).
	func ibeam(x: float, z: float, y0: float, y1: float, depth: float, width: float, col: Color) -> void:
		var t := 0.022
		abox(Vector3(x - width * 0.5, y0, z - depth * 0.5), Vector3(x + width * 0.5, y1, z - depth * 0.5 + t * 1.4), col)
		abox(Vector3(x - width * 0.5, y0, z + depth * 0.5 - t * 1.4), Vector3(x + width * 0.5, y1, z + depth * 0.5), col)
		abox(Vector3(x - t * 0.5, y0, z - depth * 0.5), Vector3(x + t * 0.5, y1, z + depth * 0.5), col)

	## A horizontal channel along x at (y, z).
	func channel(x0: float, x1: float, y: float, z: float, hgt: float, dep: float, col: Color) -> void:
		var t := 0.02
		abox(Vector3(x0, y - hgt * 0.5, z - dep * 0.5), Vector3(x1, y + hgt * 0.5, z - dep * 0.5 + t), col)
		abox(Vector3(x0, y + hgt * 0.5 - t, z - dep * 0.5), Vector3(x1, y + hgt * 0.5, z + dep * 0.5), col)
		abox(Vector3(x0, y - hgt * 0.5, z - dep * 0.5), Vector3(x1, y - hgt * 0.5 + t, z + dep * 0.5), col)

	## An n-sided tapered tube from y0 (radius r0) to y1 (r1) at the origin.
	func tube(r0: float, r1: float, y0: float, y1: float, sides: int, col: Color, cap := true) -> void:
		for i in sides:
			var a0 := TAU * float(i) / sides
			var a1 := TAU * float(i + 1) / sides
			var b0 := Vector3(cos(a0), 0.0, sin(a0))
			var b1 := Vector3(cos(a1), 0.0, sin(a1))
			quad(b1 * r0 + Vector3(0, y0, 0), b0 * r0 + Vector3(0, y0, 0), b0 * r1 + Vector3(0, y1, 0), b1 * r1 + Vector3(0, y1, 0), col)
			if cap:
				var top := Vector3(0, y1, 0)
				tri(top, b1 * r1 + top, b0 * r1 + top, col)

	func mesh(material: Material, with_uv: bool = false) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		if with_uv:
			arrays[Mesh.ARRAY_TEX_UV] = uv
			arrays[Mesh.ARRAY_TEX_UV2] = uv2
			arrays[Mesh.ARRAY_TANGENT] = tg
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, material)
		return m


static func _k(col: Color, kind: int) -> Color:
	return Color(col.r, col.g, col.b, (float(kind) + 0.5) / 8.0)


## A face: one quad, UV 0..1 across the art (v down), UV2 its metres from the bottom-left corner.
static func face_mesh(poster: bool) -> ArrayMesh:
	var key := "face_p" if poster else "face_b"
	if _cache.has(key):
		return _cache[key]
	var s := POSTER if poster else BULLETIN
	var g := Geo.new()
	var hw := s.x * 0.5
	g.quad(Vector3(-hw, 0.0, 0.02), Vector3(hw, 0.0, 0.02), Vector3(hw, s.y, 0.02), Vector3(-hw, s.y, 0.02), Color.WHITE,
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), s)
	_cache[key] = g.mesh(face_material(), true)
	return _cache[key]


## A supergraphic: a unit quad (x -0.5..0.5, y 0..1) facing +Z, scaled by its instance.
static func super_mesh() -> ArrayMesh:
	if _cache.has("super"):
		return _cache.super
	var g := Geo.new()
	g.quad(Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0), Vector3(0.5, 1.0, 0.0), Vector3(-0.5, 1.0, 0.0), Color.WHITE,
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2.ONE)
	_cache.super = g.mesh(face_material(), true)
	return _cache.super


## The bus shelter's lightbox: an aluminium case on two feet with an ad behind acrylic both sides
## (the back face's UV.x is shifted by 2: the shader shows the next portrait there).
static func shelter_mesh() -> ArrayMesh:
	if _cache.has("shelter"):
		return _cache.shelter
	var f := SHELTER_FACE
	var y0 := 0.32
	var g := Geo.new()
	var hw := f.x * 0.5
	g.quad(Vector3(-hw, y0, 0.091), Vector3(hw, y0, 0.091), Vector3(hw, y0 + f.y, 0.091), Vector3(-hw, y0 + f.y, 0.091), Color.WHITE,
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), f)
	g.quad(Vector3(hw, y0, -0.091), Vector3(-hw, y0, -0.091), Vector3(-hw, y0 + f.y, -0.091), Vector3(hw, y0 + f.y, -0.091), Color.WHITE,
		Vector2(2, 1), Vector2(3, 1), Vector2(3, 0), Vector2(2, 0), f)
	var face := g.mesh(face_material(), true)
	var s := Geo.new()
	var alu := _k(C_ALU, Steel.GALV)
	var fw := 0.07
	s.abox(Vector3(-hw - fw, y0 - fw, -0.09), Vector3(hw + fw, y0, 0.09), alu)
	s.abox(Vector3(-hw - fw, y0 + f.y, -0.09), Vector3(hw + fw, y0 + f.y + fw * 1.6, 0.09), alu)
	s.abox(Vector3(-hw - fw, y0, -0.09), Vector3(-hw, y0 + f.y, 0.09), alu)
	s.abox(Vector3(hw, y0, -0.09), Vector3(hw + fw, y0 + f.y, 0.09), alu)
	for x: float in [-hw + 0.12, hw - 0.12]:
		s.abox(Vector3(x - 0.04, 0.0, -0.05), Vector3(x + 0.04, y0 - fw, 0.05), alu)
	s.abox(Vector3(-hw - 0.02, 0.0, -0.14), Vector3(hw + 0.02, 0.012, 0.14), _k(C_GALV, Steel.GALV))
	var arrays := (s.mesh(steel_material()) as ArrayMesh).surface_get_arrays(0)
	face.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	face.surface_set_material(1, steel_material())
	_cache.shelter = face
	return face


## The frame behind and below a face (face-local): trim, back sheet, stringers, uprights and
## X-bracing, the catwalk with its brackets and rail, lighting arms with their fixtures.
static func frame_mesh(poster: bool) -> ArrayMesh:
	var key := "frame_p" if poster else "frame_b"
	if _cache.has(key):
		return _cache[key]
	var s := POSTER if poster else BULLETIN
	var hw := s.x * 0.5
	var g := Geo.new()
	var trim := _k(C_TRIM, Steel.PAINT)
	var steel := _k(C_STEEL, Steel.PAINT)
	var galv := _k(C_GALV, Steel.GALV)
	var sheet := _k(C_SHEET, Steel.SHEET)
	var grate := _k(Color(0.34, 0.35, 0.34), Steel.GRATING)
	var tw := 0.16
	# Trim round the face (the vinyl is laced to it).
	g.abox(Vector3(-hw - tw, -tw, -0.12), Vector3(hw + tw, 0.0, 0.07), trim)
	g.abox(Vector3(-hw - tw, s.y, -0.12), Vector3(hw + tw, s.y + tw, 0.07), trim)
	g.abox(Vector3(-hw - tw, 0.0, -0.12), Vector3(-hw, s.y, 0.07), trim)
	g.abox(Vector3(hw, 0.0, -0.12), Vector3(hw + tw, s.y, 0.07), trim)
	# The back sheet and its stringers.
	g.abox(Vector3(-hw, 0.0, -0.16), Vector3(hw, s.y, -0.12), sheet)
	var rows := 3 if not poster else 2
	for r in rows:
		var y := lerpf(0.45, s.y - 0.45, float(r) / float(rows - 1))
		g.channel(-hw, hw, y, -0.24, 0.2, 0.16, steel)
	# Uprights and X-bracing behind.
	var bays := 6 if not poster else 3
	var xs: Array[float] = []
	for i in bays + 1:
		xs.append(lerpf(-hw + 0.2, hw - 0.2, float(i) / float(bays)))
	for x: float in xs:
		g.abox(Vector3(x - 0.08, -0.3, -0.48), Vector3(x + 0.08, s.y + 0.15, -0.32), steel)
	for i in bays:
		var x0 := xs[i] + 0.1
		var x1 := xs[i + 1] - 0.1
		g.strut(Vector3(x0, 0.2, -0.4), Vector3(x1, s.y - 0.2, -0.4), 0.06, galv)
		g.strut(Vector3(x1, 0.2, -0.4), Vector3(x0, s.y - 0.2, -0.4), 0.06, galv)
	# The catwalk: brackets off the uprights, a grated deck in front of the face, a rail.
	var cw := 0.95
	var cy := -0.32
	for x: float in xs:
		g.abox(Vector3(x - 0.04, cy - 0.16, -0.48), Vector3(x + 0.04, cy - 0.04, cw + 0.1), steel)
		g.strut(Vector3(x, cy - 0.12, cw), Vector3(x, cy - 1.0, -0.4), 0.05, steel)
	g.abox(Vector3(-hw - 0.3, cy - 0.04, 0.05), Vector3(hw + 0.3, cy, cw + 0.1), grate)
	g.abox(Vector3(-hw - 0.3, cy - 0.12, cw + 0.08), Vector3(hw + 0.3, cy + 0.05, cw + 0.12), steel)
	var posts := bays * 2
	for i in posts + 1:
		var x := lerpf(-hw - 0.25, hw + 0.25, float(i) / float(posts))
		g.abox(Vector3(x - 0.025, cy, cw + 0.06), Vector3(x + 0.025, cy + 1.05, cw + 0.11), galv)
	g.abox(Vector3(-hw - 0.3, cy + 1.02, cw + 0.05), Vector3(hw + 0.3, cy + 1.07, cw + 0.12), galv)
	g.abox(Vector3(-hw - 0.3, cy + 0.52, cw + 0.07), Vector3(hw + 0.3, cy + 0.56, cw + 0.11), galv)
	# Lighting arms: out from the catwalk, a fixture on each aimed up at the face.
	var lights := 5 if not poster else 3
	for i in lights:
		var x := lerpf(-hw, hw, (float(i) + 0.5) / float(lights))
		var root := Vector3(x, cy - 0.06, cw + 0.1)
		var tip := Vector3(x, cy + 0.12, cw + 1.55)
		g.strut(root, tip, 0.06, steel)
		g.strut(Vector3(x, cy - 0.5, cw - 0.2), tip - Vector3(0, 0.06, 0.3), 0.04, steel)
		var head := Transform3D(Basis(Vector3.RIGHT, -0.85), tip + Vector3(0.0, 0.1, 0.0))
		g.box(head, Vector3(0.5, 0.16, 0.36), _k(C_FIXTURE, Steel.PAINT))
		g.box(head * Transform3D(Basis(), Vector3(0.0, 0.0, 0.19)), Vector3(0.42, 0.11, 0.02), _k(C_LENS, Steel.LENS))
	_cache[key] = g.mesh(steel_material())
	return _cache[key]


## Rooftop legs (face-local, from the roof at y = -leg to the face's bottom): wide-flange columns
## under the uprights, a rear kicker strut and a base plate each, a ladder up to the catwalk.
static func legs_mesh(poster: bool) -> ArrayMesh:
	var key := "legs_p" if poster else "legs_b"
	if _cache.has(key):
		return _cache[key]
	var s := POSTER if poster else BULLETIN
	var leg := LEG_POSTER if poster else LEG_BULLETIN
	var hw := s.x * 0.5
	var g := Geo.new()
	var steel := _k(C_STEEL, Steel.PAINT)
	var galv := _k(C_GALV, Steel.GALV)
	var n := 3 if not poster else 2
	for i in n:
		var x := lerpf(-hw + 1.2, hw - 1.2, float(i) / float(n - 1))
		g.ibeam(x, -0.4, -leg, -0.3, 0.25, 0.2, steel)
		g.strut(Vector3(x, -leg + 0.05, -0.4 - leg * 0.75), Vector3(x, -0.6, -0.42), 0.13, steel)
		g.abox(Vector3(x - 0.25, -leg, -0.65), Vector3(x + 0.25, -leg + 0.03, -0.15), galv)
		g.abox(Vector3(x - 0.2, -leg, -0.4 - leg * 0.75 - 0.2), Vector3(x + 0.2, -leg + 0.03, -0.4 - leg * 0.75 + 0.2), galv)
	# A horizontal tie between the columns.
	g.channel(-hw + 1.1, hw - 1.1, -leg * 0.45, -0.4, 0.16, 0.12, steel)
	# The ladder at one end, from the roof to the catwalk.
	var lx := hw - 0.5
	for side: float in [-0.22, 0.22]:
		g.abox(Vector3(lx + side - 0.025, -leg, 1.0), Vector3(lx + side + 0.025, -0.25, 1.05), galv)
	var rungs := int(leg / 0.3)
	for r in rungs:
		var y := -leg + 0.3 * (r + 0.6)
		g.abox(Vector3(lx - 0.22, y - 0.012, 1.01), Vector3(lx + 0.22, y + 0.012, 1.04), galv)
	_cache[key] = g.mesh(steel_material())
	return _cache[key]


## A monopole face's head frame (face-local): a box beam under the catwalk along the face and two
## struts down to the column's top.
static func head_mesh() -> ArrayMesh:
	if _cache.has("head"):
		return _cache.head
	var g := Geo.new()
	var steel := _k(C_STEEL, Steel.PAINT)
	var hw := BULLETIN.x * 0.5
	# Where the column's top is in face 0's frame (face 1 mirrors it exactly).
	var pole := v_face_local(0).affine_inverse() * Vector3(0.0, -0.55, 0.0)
	g.abox(Vector3(-hw + 0.3, -0.75, -0.62), Vector3(hw - 0.3, -0.35, -0.3), steel)
	for x: float in [-hw * 0.55, hw * 0.55]:
		g.strut(Vector3(x, -0.6, -0.46), pole + Vector3(0.0, -0.1, 0.0), 0.22, steel)
	g.strut(Vector3(pole.x, -0.55, -0.46), pole, 0.3, steel)
	_cache.head = g.mesh(steel_material())
	return _cache.head


## The column: a 16-sided steel tube 1 m tall (its instance scales it to the pole's height).
static func pole_mesh() -> ArrayMesh:
	if _cache.has("pole"):
		return _cache.pole
	var g := Geo.new()
	g.tube(POLE_RADIUS, POLE_RADIUS * 0.82, 0.0, 1.0, 16, _k(C_STEEL, Steel.PAINT))
	_cache.pole = g.mesh(steel_material())
	return _cache.pole


## The column's base: a concrete pier, the flange and its anchor nuts.
static func base_mesh() -> ArrayMesh:
	if _cache.has("base"):
		return _cache.base
	var g := Geo.new()
	g.tube(1.05, 1.05, -0.4, 0.45, 12, _k(C_CONCRETE, Steel.CONCRETE))
	g.tube(0.82, 0.82, 0.45, 0.5, 12, _k(C_STEEL, Steel.PAINT))
	for i in 8:
		var a := TAU * float(i) / 8.0
		g.abox(Vector3(cos(a) * 0.7 - 0.04, 0.5, sin(a) * 0.7 - 0.04), Vector3(cos(a) * 0.7 + 0.04, 0.58, sin(a) * 0.7 + 0.04), _k(C_GALV, Steel.GALV))
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		var d := Vector3(cos(a), 0.0, sin(a))
		g.strut(Vector3(0, 0.5, 0) + d * POLE_RADIUS, Vector3(0, 0.5, 0) + d * 0.8, 0.03, _k(C_STEEL, Steel.PAINT), 0.04)
	_cache.base = g.mesh(steel_material())
	return _cache.base


## Builds every mesh and material once (the loading screen) and hands back the materials to draw.
static func warm() -> Array:
	for p: bool in [false, true]:
		face_mesh(p)
		frame_mesh(p)
		legs_mesh(p)
	super_mesh()
	shelter_mesh()
	head_mesh()
	pole_mesh()
	base_mesh()
	return [face_material(), steel_material()]
