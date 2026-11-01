class_name AirportApron
extends RefCounted
## The airport apron at eye level and from the tower (refcam2 "airport_apron", wave 5): the
## fixes the reference view found, kept in one place so AIRPORT_APRON=0 is the old field.
##
## - The paint was UNDER the ground. Airport painted its lines 2 mm over the surface on the
##   stripe batch's 2 cm box, and road_paint.gdshader's `thickness` (StreetCloseup, the street
##   paint pressed to 4 mm) moves the box's top down to its underside plus 4 mm: 6 mm UNDER the
##   apron. Every taxiway centre line, lead-in, stop bar, hold-short and runway marking at FULL
##   was gone (the stand numbers are TextMesh and stayed). paint_lift() puts the box where the
##   pressed top stands proud of the surface.
## - Apron lead-ins and stop bars on the pale concrete are yellow on a black border (a real
##   field's rule: yellow alone on new concrete vanishes): outline() lays the black line under
##   every yellow line on the apron's own surface.
## - A stand is where a jet stands an hour at a time: oil under the nose gear, hydraulic and
##   rubber at the mains, fuel and oil under the engines, dark tyre tracks down the lead-in, a
##   few spills. stains() lays them as the street's own "patch" batch (road_patch.gdshader: dark
##   shades soak in, blotchy and see-through), one draw a chunk that already exists.
## - The infield was a saturated lime lawn: real field grass in LA is straw most of the year.
##   straw() desaturates the grass texture toward a warm straw (lawn.gdshader `straw`).
## Every placement is a hash of the stand, never an rng.

static var enabled: bool = OS.get_environment("AIRPORT_APRON") != "0"

## The stripe box's centre over the surface (it is 2 cm tall; road_paint presses its top to
## StreetCloseup.PAINT_THICK over its underside): yellow on top, its black border under it.
const PAINT_LIFT := 0.014
const BORDER_LIFT := 0.008
## How much wider the black border is than its yellow line (metres), and how far past its ends.
const BORDER_EXTRA := 0.32
const BORDER_RUN := 0.15
const BLACK := Color(0.035, 0.035, 0.035)
## The infield (lawn.gdshader): straw share, watered and parched tints.
const STRAW := 0.82
const GRASS_TINT := Color(0.82, 0.80, 0.64)
const GRASS_DRY := Color(0.94, 0.80, 0.60)
## Its far-city colour (the plates and the LOD ground), linear.
const GRASS_FAR := Color(0.50, 0.44, 0.31)
## A stand's stains, in its frame: [metres back from the nose, metres to the jet's right (t),
## length along n, width along t, shade]. Shades under 0.6 soak in (road_patch.gdshader).
const STAND_STAINS := [
	[1.6, 0.0, 4.5, 1.7, 0.30],      # oil under the nose gear at the stop
	[-1.2, 0.0, 2.2, 2.6, 0.38],     # the tug's drips in front of it
	[17.0, 3.6, 7.0, 2.4, 0.34],     # the main gear, both sides
	[17.0, -3.6, 7.0, 2.4, 0.34],
	[13.5, 5.8, 3.4, 3.8, 0.28],     # under the engines
	[13.5, -5.8, 3.4, 3.8, 0.28],
	[31.0, 0.0, 3.0, 2.2, 0.40],     # under the APU, at the tail
]
## The tyre tracks down the lead-in: nose gear on the line, the mains either side, from
## TRACK_FROM metres back to TRACK_TO.
const TRACK_FROM := 3.0
const TRACK_TO := 44.0
const TRACK_SHADE := 0.36
## The concourse's hall by day, through its glass (curtain_glass interior_day).
const GLASS_DAY := 0.62
## AirportKit's boxes: chamfer every box at least BEVEL_MIN thick by BEVEL_SHARE of its thinnest
## side, at most BEVEL_MAX (metres).
const BEVEL_MIN := 0.12
const BEVEL_SHARE := 0.12
const BEVEL_MAX := 0.06
## Spills a stand: how many, inside how far of its centre line.
const SPILLS := 5


static func paint_lift() -> float:
	return PAINT_LIFT if enabled else 0.002


## The black border under a yellow line on the apron (`top` the apron's own surface).
static func outline(ch: CityChunk, area: Rect2, a: Vector2, b: Vector2, width: float, top: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.05:
		return
	var dir := d / length
	var pa := a - dir * BORDER_RUN
	var pb := b + dir * BORDER_RUN
	# Clip as Airport._line() does: only the part over this chunk.
	var t0 := 0.0
	var t1 := 1.0
	var dd2 := pb - pa
	for axis in 2:
		var p0: float = pa[axis]
		var dd: float = dd2[axis]
		var lo: float = area.position[axis]
		var hi: float = area.end[axis]
		if absf(dd) < 1e-6:
			if p0 < lo or p0 >= hi:
				return
			continue
		var ta := (lo - p0) / dd
		var tb := (hi - p0) / dd
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t1 - t0 < 1e-4:
		return
	var qa := pa + dd2 * t0
	var qb := pa + dd2 * t1
	var mid := (qa + qb) * 0.5
	var seg := qa.distance_to(qb)
	ch._batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(Vector3.UP, atan2(dd2.x, dd2.y)).scaled_local(
		Vector3((width + BORDER_EXTRA) / 0.6, 1.0, seg / 3.0)), Vector3(mid.x, top + BORDER_LIFT, mid.y)), BLACK)


## A yellow line on the bare apron (not a taxiway, not a runway) gets a border.
static func wants_border(col: Color, top: float, apron_top: float) -> bool:
	return enabled and col == Airport.YELLOW and absf(top - apron_top) < 0.002


## The stands' stains whose centres lie in the chunk (the "patch" batch).
static func stains(ch: CityChunk, area: Rect2, top: float) -> void:
	if not enabled:
		return
	var y := top + 0.003
	for g: Dictionary in Airport.gates():
		if g.get("empty", false):
			continue
		var n: Vector2 = g.n
		var t: Vector2 = g.t
		var nose: Vector2 = g.nose
		var yaw := atan2(n.x, n.y)
		var gi := int(String(g.number).to_int())
		var k := 0
		for s: Array in STAND_STAINS:
			var p: Vector2 = nose + n * float(s[0]) + t * float(s[1])
			_stain(ch, area, p, yaw + (_h(gi, k, 0) - 0.5) * 0.3, float(s[2]) * (0.85 + 0.3 * _h(gi, k, 1)), float(s[3]) * (0.85 + 0.3 * _h(gi, k, 2)), float(s[4]) + (_h(gi, k, 3) - 0.5) * 0.08, y)
			k += 1
		# Tyre tracks down the lead-in, in a few pieces so their ragged rims break the run.
		for side: float in [0.0, -3.6, 3.6]:
			var s0 := TRACK_FROM
			while s0 < TRACK_TO:
				var run := 6.0 + 4.0 * _h(gi, k, 4)
				var p: Vector2 = nose + n * (s0 + run * 0.5) + t * (side + (_h(gi, k, 5) - 0.5) * 0.4)
				_stain(ch, area, p, yaw, run, 0.75 if side == 0.0 else 1.1, TRACK_SHADE + _h(gi, k, 6) * 0.1, y)
				s0 += run + 0.5 + 3.0 * _h(gi, k, 7)
				k += 1
		for j in SPILLS:
			var back := 2.0 + 34.0 * _h(gi, j, 20)
			var off := (_h(gi, j, 21) - 0.5) * 20.0
			var size := 0.7 + 2.2 * _h(gi, j, 22)
			_stain(ch, area, nose + n * back + t * off, _h(gi, j, 23) * TAU, size, size * (0.5 + 0.5 * _h(gi, j, 24)), 0.24 + 0.14 * _h(gi, j, 25), y)


static func _stain(ch: CityChunk, area: Rect2, p: Vector2, yaw: float, length: float, width: float, shade: float, y: float) -> void:
	if not area.has_point(p):
		return
	ch._batch.add("patch", PropFactory.patch(), Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(width, 1.0, length)), Vector3(p.x, y, p.y)),
		Color(shade, shade, shade * 1.06))


static func _h(gate: int, k: int, salt: int) -> float:
	return float(absi(hash([gate, k, salt, "apron_stain"])) % 10007) / 10007.0


## The infield grass material's straw (Airport.grass_material()).
static func dress_grass(mat: ShaderMaterial) -> void:
	if not enabled:
		return
	mat.set_shader_parameter("straw", STRAW)
	mat.set_shader_parameter("dry_tint", GRASS_DRY)


## An airliner livery material's close-up pass (airliner_livery.gdshader `detail`).
static func dress_jet(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("detail", 1.0 if enabled else 0.0)


## The terminal's and concourses' glass (AirportTerminal._glass()): by day the old numbers drew a
## near-black band a concourse long (interior_day 0.16 under a dark tint), where a real terminal
## at noon shows its skylit hall through the glass: a paler tint, the hall lit by day, the mirror
## a little less. Night is as it was.
static func glass_params(y0: float, storey: float, depth: float) -> Dictionary:
	return {"glass_tint": Color(0.30, 0.38, 0.42), "frame_color": Color(0.78, 0.80, 0.83),
		"grid": Vector2(1.8, minf(storey * 0.5, 3.4)), "frame_width": 0.09, "room_depth": depth, "storey": storey, "floor_y": y0,
		"interior_color": Color(0.98, 0.93, 0.84), "interior_day": GLASS_DAY, "interior_night": 1.9, "spandrel_every": 0.0,
		"reflect_emit": 0.6}
