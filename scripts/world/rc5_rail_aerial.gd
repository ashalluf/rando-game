class_name RcRailAerial
extends RefCounted
## The Coral Line's aerial structure at night, seen from the street under it (wave 8 refcam
## `rail_aerial`, docs/HANDOFF.md "The Coral Line's aerial structure at night"). Hooks in
## LightRailKit (`_wire()`, `_pole()`, `_column()`, `_commit()`); RC5_RAIL_AERIAL=0 is the A/B
## (the kit exactly as before).
##
##   wires     the contact wire, messenger and droppers (4-6.5 mm) were 3-sided prisms: from the
##             street 40 m below they are a tenth of a pixel, so they drew as dotted dashes or
##             not at all. They are ribbons on shaders/rail_wire.gdshader now (turned to the
##             camera, never thinner than a pixel, their real width as coverage; at night they
##             catch the pole lamps near each pole), one mesh a chunk.
##   lamps     an LED walkway luminaire on a bracket either side of every pole on the structure,
##             its lens lit by `lamp_factor`, a halo (NightAtmos) and a pool on the ballast.
##   soffit    a downlight pair under the girder midway between columns, a pool on the street
##             below; the column and its hammerhead washed from them, and the soffit lit by the
##             street lamps below (emitted, `rail_wash` on the structure's own material copy).
##   fascia    the freeway's scupper rust (a blotch every 12 m) does not belong on a guideway with
##             drains at its piers: the copy has one every column span, faint.
## Hashes only; nothing a seed builds elsewhere moves.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_RAIL_AERIAL") != "0"

## Narrowest a wire is drawn (pixels) and where the wires fade (metres from the camera).
const WIRE_MIN_PX := 1.0
const WIRE_FADE := Vector2(260.0, 380.0)
## rail_wire.gdshader kinds: 0 copper (contact wire, messenger), 4 galvanised (droppers).
const KIND_WIRE := 0.0
const KIND_DROPPER := 4.0
## The walkway luminaires: height over the rail, how far out from the pole (past the track).
const LAMP_HEIGHT := 4.7
const LAMP_OUT := 1.35
const LAMP_COLOR := Color(1.0, 0.86, 0.66)
## A lens's brightness (the structure shader's kind-7 lenses: base x lens_energy x flag).
const LAMP_FLAG := 1.6
const UNDER_FLAG := 2.2
## The pools: on the ballast under each walkway lamp, on the street under each downlight pair.
const DECK_POOL := Vector2(9.0, 4.0)
const STREET_POOL := Vector2(16.0, 13.0)
const POOL_COLOR := Color(1.0, 0.88, 0.70, 0.55)
## The downlights under the girder, halfway between columns (LightRailKit.COLUMN_SPACING, offset 5).
const UNDER_OFFSET := 20.0
## The emitted washes on the structure's own material: the columns from the downlights (top down),
## the soffit and fascia from the street lamps below; both x lamp_factor.
const COLUMN_WASH := 0.32
const SOFFIT_WASH := 0.06
## The guideway's drains are at its piers: one faint rust run per column span.
const RUST_AMOUNT := 0.18
const RUST_SPACING := 30.0

static var _wire_mat: ShaderMaterial = null
static var _struct_mat: ShaderMaterial = null


## The overhead wires' material (rail_wire.gdshader: utility_wire.gdshader's ribbons, copper, lit by
## the pole lamps).
static func wire_material() -> ShaderMaterial:
	if _wire_mat == null:
		_wire_mat = ShaderMaterial.new()
		_wire_mat.shader = load("res://shaders/rail_wire.gdshader")
		_wire_mat.set_shader_parameter("min_px", WIRE_MIN_PX)
		_wire_mat.set_shader_parameter("fade_start", WIRE_FADE.x)
		_wire_mat.set_shader_parameter("fade_end", WIRE_FADE.y)
	return _wire_mat


## The light rail's own copy of the freeway structure material (rust spacing, washes). The
## freeway's `under_fill` (GiTuning, by Quality) is carried over every time a chunk asks.
static func structure_material(base: ShaderMaterial) -> ShaderMaterial:
	if not enabled:
		return base
	if _struct_mat == null:
		_struct_mat = base.duplicate() as ShaderMaterial
		_struct_mat.set_shader_parameter("rust_amount", RUST_AMOUNT)
		_struct_mat.set_shader_parameter("scupper_spacing", RUST_SPACING)
		_struct_mat.set_shader_parameter("rail_wash", Vector2(COLUMN_WASH, SOFFIT_WASH))
	_struct_mat.set_shader_parameter("under_fill", base.get_shader_parameter("under_fill"))
	return _struct_mat


## One straight piece of wire from a to b, radius r, as a camera-facing ribbon: every vertex on
## the centre line, the tangent in NORMAL, UV (side, metres to the nearest pole: how much of the
## pole's lamp the wire catches), UV2 (radius, kind). `pa` / `pb` are a's and b's metres to the
## nearest pole.
static func wire(st: SurfaceTool, a: Vector3, b: Vector3, r: float, kind: float, pa: float, pb: float) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.001:
		return
	var t := d / len
	var pts := [[a, -1.0, pa], [a, 1.0, pa], [b, 1.0, pb], [a, -1.0, pa], [b, 1.0, pb], [b, -1.0, pb]]
	for v: Array in pts:
		st.set_normal(t)
		st.set_uv(Vector2(float(v[1]), float(v[2])))
		st.set_uv2(Vector2(r, kind))
		st.add_vertex(v[0])


## Metres from s to the nearest pole of the line.
static func to_pole(line: LightRail, s: float) -> float:
	var span: Array = line.span_at(s)
	return maxf(minf(s - float(span[0]), float(span[1]) - s), 0.0)


## The walkway luminaires on a pole of the structure: a bracket out over each walkway, a housing
## and its lens, a pool on the ballast under it, a halo for the night air.
static func pole_lamps(kit: LightRailKit, smp: Dictionary) -> void:
	var p: Vector2 = smp.pos
	var d: Vector2 = smp.dir
	var r := Vector2(-d.y, d.x)
	var r3 := Vector3(r.x, 0.0, r.y)
	var d3 := Vector3(d.x, 0.0, d.y)
	var y: float = smp.y
	var half: float = smp.half
	var hy := y + LAMP_HEIGHT
	var c := Vector3(p.x, 0.0, p.y)
	var arm := kit.kind_color(LightRailKit.POLE, FreewayKit.S_PAINTED)
	var housing := kit.kind_color(Color(0.16, 0.17, 0.18), FreewayKit.S_PAINTED)
	var lens := kit.kind_color(LAMP_COLOR, FreewayKit.S_LENS)
	var bed := y - 0.168 - 0.33
	for side: float in [-1.0, 1.0]:
		var out := half + LAMP_OUT
		var tip := c + r3 * side * out + Vector3.UP * hy
		kit.prism(kit.body, c + r3 * side * 0.12 + Vector3.UP * (hy + 0.05), tip + Vector3.UP * 0.05, 0.035, 0.03, 5, arm)
		# The housing: a slim flat box, 60 x 26 cm, its lens 2 cm under it.
		var hc := tip + r3 * side * 0.2
		kit.box(kit.body, hc, r3 * 0.3, Vector3.UP * 0.05, d3 * 0.13, housing, 0.0, false)
		kit.box(kit.body, hc + Vector3.DOWN * 0.065, r3 * 0.26, Vector3.UP * 0.015, d3 * 0.1, lens, LAMP_FLAG, false)
		kit.pool(Vector3(hc.x, bed + 0.03, hc.z) - r3 * side * 0.9, d3, DECK_POOL, POOL_COLOR)
		FreewayCloseup.lamp_halo(kit.chunk, hc + Vector3.DOWN * 0.1, false)
		if OS.get_environment("RC5_RAIL_DEBUG") == "1":
			print("RAILAERIAL lamp at %.1f, %.1f, %.1f" % [hc.x, hc.y, hc.z])


## The downlight pair under the girder at s (the street under the structure, halfway between
## columns): two lenses in the soffit, a pool on the street.
static func soffit_lights(kit: LightRailKit, smp: Dictionary, deck_bottom: float, street: float) -> void:
	var p: Vector2 = smp.pos
	var d: Vector2 = smp.dir
	var r := Vector2(-d.y, d.x)
	var r3 := Vector3(r.x, 0.0, r.y)
	var d3 := Vector3(d.x, 0.0, d.y)
	var lens := kit.kind_color(LAMP_COLOR, FreewayKit.S_LENS)
	var housing := kit.kind_color(Color(0.20, 0.21, 0.22), FreewayKit.S_PAINTED)
	for side: float in [-1.0, 1.0]:
		var c := Vector3(p.x, deck_bottom - 0.09, p.y) + r3 * side * 0.9
		kit.box(kit.body, c, r3 * 0.24, Vector3.UP * 0.08, d3 * 0.24, housing, 0.0, false)
		kit.box(kit.body, c + Vector3.DOWN * 0.09, r3 * 0.18, Vector3.UP * 0.012, d3 * 0.18, lens, UNDER_FLAG, false)
	kit.pool(Vector3(p.x, street + 0.06, p.y), d3, STREET_POOL, POOL_COLOR)


## The places along the line the downlights hang: halfway between the columns, on the structure,
## clear of the street's junctions only where a column could stand (a span over a junction still
## gets its pair) and never over a freeway deck (the pool would land on the street under it).
static func soffit_spots(line: LightRail, plan: CityPlan, owns: Callable) -> Array[float]:
	var out: Array[float] = []
	var n := ceili(line.length / LightRailKit.COLUMN_SPACING)
	for k in n + 1:
		var s := float(k) * LightRailKit.COLUMN_SPACING + UNDER_OFFSET
		if s > line.length:
			break
		var smp := line.sample(s)
		if int(smp.mode) != LightRail.Mode.AERIAL or not bool(owns.call(smp.pos)):
			continue
		if plan.macro.freeway != null and plan.macro.freeway.blocks(smp.pos, 4.0):
			continue
		out.append(s)
	return out
