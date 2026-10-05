class_name EstateFar
## The hillside estates as the basin sees them at night and by day, past the FULL chunks: the LOD
## chunks' copy and the far city's (Skyline), on shaders/far_estate.gdshader. They used to be one
## pale box each (a pavers slab under it at LOD), which read as a grey disc on the dark hills.
##
## With the hillside houses on (HillHomeKit, the default) the HOUSE is HillHomeKit's at every
## range - FULL geometry, LOD boxes, the far city's boxes with their lit glass band on
## far_canopy.gdshader - and this adds what makes an estate read as one from across the basin,
## laid out from the very plan (`HillHomeKit.plan_home()`): the pad's garden (a lawn, now and then
## gravel, over the pavers, on its retaining walls), the motor court inside the gate, the pool's
## underwater glow, and the lamps - two on the gate piers, two at the door, garden lights round the
## lawn, lamps down a long driveway - which light after dark and never shrink under a pixel or two;
## and, in the far city, the plan's trees in the planting. With HILL_HOMES=0 it draws the old
## Building villa's whole estate itself (`_box_parts()`: house with windows and roof too).
##
## Seating matches far_canopy's estate rule exactly: each part moves by the drawn far plane under
## its OWN origin, its reference height (the pad top, or the real ground for a driveway lamp) put
## FAR_SINK into it; what must lie on the drawn ground (garden, court, pool, garden and drive
## lamps) is lifted FAR_SINK back. Every roll is a hash of the estate's seed; `parts()` is pure.
##
## ESTATE_NIGHT=0 in the environment turns all of it off: the A/B.

## Part kinds (far_estate.gdshader): pad, house, roof, pool, lamp, plain (court, coping, hedge).
const K_PAD := 0
const K_HOUSE := 1
const K_ROOF := 2
const K_POOL := 3
const K_LAMP := 4
const K_PLAIN := 5
## Added to the kind when the part stands on the real terrain (a LOD chunk drew it), not the far plane.
const REAL := 8

## The pad as CityChunk builds it (ESTATE_PAD) and how far its retaining walls go down below the
## deck, so a pad seated on a sloping far plane never shows daylight under its downhill side.
const PAD := Vector3(26.0, 0.4, 22.0)
const SKIRT := 6.0
## Lamp heads (metres): the shader grows them to lamp_min_angle with distance.
const LAMP_SIZE := 0.35
## Driveway lamps every this many metres down a drive longer than DRIVE_MIN.
const DRIVE_LAMP_STEP := 18.0
const DRIVE_MIN := 8.0

## Garden tops (LINEAR): watered lawn mostly, now and then a gravel and succulent garden.
const LAWNS: Array[Color] = [Color(0.055, 0.10, 0.03), Color(0.07, 0.115, 0.035), Color(0.045, 0.085, 0.028), Color(0.19, 0.16, 0.115)]
## Walls (LINEAR): the stucco CityChunk paints the estates' walls, a little darker.
## (At 0.8-0.9, like the old box's 0.92, a house glowed white in the moonlight across the basin.)
const WALLS: Array[Color] = [Color(0.50, 0.46, 0.39), Color(0.44, 0.37, 0.28), Color(0.53, 0.51, 0.47), Color(0.34, 0.28, 0.21), Color(0.20, 0.18, 0.16)]
## Roofs (LINEAR): clay tile, dark gravel, grey membrane, dark standing seam.
const ROOFS: Array[Color] = [Color(0.26, 0.085, 0.045), Color(0.22, 0.10, 0.06), Color(0.10, 0.095, 0.09), Color(0.32, 0.31, 0.29), Color(0.05, 0.05, 0.055)]
## The FULL estate's lawn (CityChunk._build_mansions): [centre over the deck, size] in the pad's
## frame, down both sides of the motor court and behind the house, under the pool and the walls.
const LAWN_PIECES: Array = [[Vector3(-9.25, 0.03, 0.0), Vector3(7.5, 0.06, 21.0)], [Vector3(9.25, 0.03, 0.0), Vector3(7.5, 0.06, 21.0)],
	[Vector3(0.0, 0.03, -8.5), Vector3(11.0, 0.06, 4.0)]]
## How far far_canopy.gdshader sinks a far estate's pad top into the drawn ground (its estate seat).
const FAR_SINK := 0.8
const COURT := Color(0.40, 0.37, 0.32)
const COPING := Color(0.62, 0.60, 0.56)
const HEDGE := Color(0.022, 0.045, 0.018)

static var enabled: bool = OS.get_environment("ESTATE_NIGHT") != "0"
static var _material: ShaderMaterial
static var _mesh: Mesh


## The shared material (one for the far city and every LOD chunk; CityStreamer gives it the far
## plane's uniforms as it does far_canopy's).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/far_estate.gdshader")
	return _material


## A unit box wearing material(), for the LOD chunks' batch.
static func mesh() -> Mesh:
	if _mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		box.material = material()
		_mesh = box
	return _mesh


## 0..1 from the estate's seed and a tag.
static func _h(s: int, tag: Variant) -> float:
	return float(absi(hash([s, "estate_far", tag])) % 10007) / 10007.0


## Every part of estate `m` (a HillRoads mansion): [Transform3D of a unit box, linear Color
## (alpha 1), custom Color (far_estate.gdshader's code)]. `real` when they stand on the real
## terrain (a LOD chunk), not the drawn far plane. Pure.
static func parts(plan: CityPlan, m: Dictionary, real: bool) -> Array:
	if HillHomeKit.enabled:
		return _home_parts(plan, m, real)
	return _box_parts(plan, m, real)


## One part. `ref` is the height the shader seats it by (the pad top, or the real ground under a
## lamp); `hug` lifts it FAR_SINK back over the drawn ground in the far city.
static func _part(out: Array, xf: Transform3D, color: Color, kind: int, variant: float, ref: float, pos: Vector2, real: bool, hug: bool) -> void:
	var code := float(kind + (REAL if real else 0)) + clampf(variant, 0.0, 0.99)
	var r := xf.origin.y - ref + (FAR_SINK if hug and not real else 0.0)
	out.append([xf, Color(color.r, color.g, color.b, 1.0), Color(r, code, xf.origin.x - pos.x, xf.origin.z - pos.y)])


## A box in the plan's frame: centre (u, v) on the pad, `y` over the pad top, size (u, height, v).
static func _frame_box(h: Dictionary, uv: Vector2, y: float, size: Vector3) -> Transform3D:
	var fu: Vector2 = h.fu
	var fv: Vector2 = h.fv
	var c := HillHomeKit.frame_point(h, uv)
	return Transform3D(Basis(Vector3(fu.x, 0.0, fu.y) * size.x, Vector3(0.0, size.y, 0.0), Vector3(fv.x, 0.0, fv.y) * size.z),
		Vector3(c.x, float(h.top) + y, c.y))


## The night and the garden on HillHomeKit's plan (its house is its own).
static func _home_parts(plan: CityPlan, m: Dictionary, real: bool) -> Array:
	var out: Array = []
	var h := HillHomeKit.plan_home(plan, m)
	var s: int = int(m.seed)
	var pos: Vector2 = m.pos
	var top: float = h.top
	var Wp: float = h.Wp
	var Dp: float = h.Dp
	var gate: Vector2 = h.gate
	var lamp := Vector3.ONE * LAMP_SIZE
	var tone := _h(s, "tone")
	# The garden over the pad's pavers, on its retaining walls (the skirt sits inside the LOD's pad).
	var lawn: Color = LAWNS[int(_h(s, "lawn") * LAWNS.size()) % LAWNS.size()]
	_part(out, _frame_box(h, Vector2(Wp, Dp) * 0.5, 0.04 - (SKIRT + 0.06) * 0.5, Vector3(Wp - 0.4, SKIRT + 0.06, Dp - 0.4)), lawn, K_PAD, 0.0, top, pos, real, true)
	# The motor court inside the gate.
	if bool(h.gate_front):
		var cw := HillHomeKit.GATE_HALF * 2.0 + 0.6
		var cd: float = maxf(float(h.vh), 2.0)
		_part(out, _frame_box(h, Vector2(gate.x, cd * 0.5), 0.07, Vector3(cw, 0.06, cd)), COURT, K_PLAIN, 0.0, top, pos, real, true)
	# The pool and its underwater light.
	var pl: Dictionary = h.pool
	if not pl.is_empty():
		var pr: Rect2 = pl.r
		_part(out, _frame_box(h, pr.get_center(), 0.24, Vector3(pr.size.x, 0.06, pr.size.y)), Color(0.04, 0.32, 0.42), K_POOL, 0.0, top, pos, real, true)
	# The gate piers' lamps, along the edge the gate is on.
	var along := Vector2(1.0, 0.0) if absf(gate.y) < 0.8 or absf(gate.y - Dp) < 0.8 else Vector2(0.0, 1.0)
	var inward := Vector2(0.0, 1.0) if along.x > 0.5 else (Vector2(1.0, 0.0) if gate.x < Wp * 0.5 else Vector2(-1.0, 0.0))
	for sg: float in [-1.0, 1.0]:
		_part(out, _frame_box(h, gate + along * (sg * 3.0) + inward * 0.35, 2.5, lamp), Color.WHITE, K_LAMP, tone, top, pos, real, false)
	# The door: a lamp either side of it on the wall.
	var dr: Dictionary = h.door
	if not dr.is_empty():
		var w: Dictionary = h.wings[int(dr.wing)]
		var y: float = float(h.floor) - top + float(w.y) + 2.4
		for sg: float in [-1.0, 1.0]:
			_part(out, _frame_box(h, Vector2(float(h.door_u) + sg * 1.3, float(h.door_v) - 0.35), y, lamp), Color.WHITE, K_LAMP, tone, top, pos, real, false)
	# Garden lights round the lawn, clear of the house, the pool and the gate.
	var garden := 3 + int(_h(s, "gn") * 4.0)
	for i in garden:
		var p := Vector2(lerpf(1.2, Wp - 1.2, _h(s, ["gu", i])), lerpf(1.2, Dp - 1.2, _h(s, ["gv", i])))
		# Pushed out to the nearer edge of the lawn, where garden lights run.
		if minf(p.x, Wp - p.x) < minf(p.y, Dp - p.y):
			p.x = 1.2 if p.x < Wp * 0.5 else Wp - 1.2
		else:
			p.y = 1.2 if p.y < Dp * 0.5 else Dp - 1.2
		if p.distance_to(gate) < 4.0 or not HillHomeKit._clear(h, p, 0.6):
			continue
		_part(out, _frame_box(h, p, 0.6, lamp * 0.8), Color.WHITE, K_LAMP, clampf(tone + 0.2, 0.0, 0.99), top, pos, real, true)
	_drive_lamps(out, plan, m, HillHomeKit.frame_point(h, gate), top, tone, real)
	return out


## Lamps down a long driveway, on the real ground beside it, a metre up.
static func _drive_lamps(out: Array, plan: CityPlan, m: Dictionary, gate: Vector2, _top: float, tone: float, real: bool) -> void:
	var pos: Vector2 = m.pos
	var from: Vector2 = m.get("drive_from", pos)
	var length := from.distance_to(gate)
	if length <= DRIVE_MIN:
		return
	var dir := (from - gate) / length
	var n := Vector2(-dir.y, dir.x)
	var k := DRIVE_LAMP_STEP * 0.5
	while k < length:
		var q := gate + dir * k + n * 2.8 * (1.0 if int(k / DRIVE_LAMP_STEP) % 2 == 0 else -1.0)
		var gy := plan.height_at(q)
		_part(out, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * LAMP_SIZE), Vector3(q.x, gy + 1.0, q.y)), Color.WHITE, K_LAMP, tone, gy, pos, real, true)
		k += DRIVE_LAMP_STEP


## The whole estate for the old Building villa (HILL_HOMES=0), in CityChunk._build_mansions' frame
## (x across the pad, z toward the gate, the house 4 m back).
static func _box_parts(plan: CityPlan, m: Dictionary, real: bool) -> Array:
	var out: Array = []
	var s: int = int(m.seed)
	var pos: Vector2 = m.pos
	var basis := Basis(Vector3.UP, float(m.yaw))
	var deck := float(m.height) + PAD.y
	var centre := Vector3(pos.x, deck, pos.y)
	var add := func(local: Vector3, size: Vector3, kind: int, color: Color, variant: float, hug: bool) -> void:
		_part(out, Transform3D(basis.scaled_local(size), centre + basis * local), color, kind, variant, deck, pos, real, hug)
	var lawn: Color = LAWNS[int(_h(s, "lawn") * LAWNS.size()) % LAWNS.size()]
	add.call(Vector3(0.0, 0.02 - (SKIRT + PAD.y) * 0.5, 0.0), Vector3(PAD.x, SKIRT + PAD.y, PAD.z), K_PAD, lawn, 0.0, true)
	add.call(Vector3(0.0, 0.05, 6.4), Vector3(11.0, 0.06, 9.0), K_PLAIN, COURT, 0.0, true)
	for sx: float in [-1.0, 1.0]:
		add.call(Vector3(sx * (PAD.x * 0.5 - 0.7), 0.85, -0.5), Vector3(1.1, 1.7, PAD.z - 3.0), K_PLAIN, HEDGE, 0.0, true)
	var w := lerpf(15.5, 19.0, _h(s, "w"))
	var d := lerpf(11.0, 13.5, _h(s, "d"))
	var hh := lerpf(6.2, 8.4, _h(s, "hh"))
	var hz := -4.0
	var wall: Color = WALLS[int(_h(s, "wall") * WALLS.size()) % WALLS.size()]
	add.call(Vector3(0.0, hh * 0.5, hz), Vector3(w, hh, d), K_HOUSE, wall, _h(s, "win"), true)
	var roof: Color = ROOFS[int(_h(s, "roof") * ROOFS.size()) % ROOFS.size()]
	add.call(Vector3(0.0, hh + 0.3, hz), Vector3(w + 0.8, 0.6, d + 0.8), K_ROOF, roof, 0.0, true)
	if _h(s, "wing") < 0.5:
		var side := -1.0 if _h(s, "wside") < 0.5 else 1.0
		var ww := lerpf(5.0, 7.0, _h(s, "ww"))
		add.call(Vector3(side * (w * 0.5 + ww * 0.5 - 0.5), 1.9, hz - 1.0), Vector3(ww, 3.8, d - 3.0), K_HOUSE, wall, _h(s, "win2"), true)
		add.call(Vector3(side * (w * 0.5 + ww * 0.5 - 0.5), 4.05, hz - 1.0), Vector3(ww + 0.6, 0.5, d - 2.4), K_ROOF, roof, 0.0, true)
	# The pool: CityChunk._build_mansions' first two rolls on the estate's seed.
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var pool_x := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(5.0, 6.5)
	add.call(Vector3(pool_x, 0.04, 6.0), Vector3(6.4, 0.1, 8.4), K_PLAIN, COPING, 0.0, true)
	add.call(Vector3(pool_x, 0.1, 6.0), Vector3(5.4, 0.06, 7.4), K_POOL, Color(0.04, 0.32, 0.42), 0.0, true)
	var tone := _h(s, "tone")
	var front := PAD.z * 0.5
	for sx: float in [-1.0, 1.0]:
		add.call(Vector3(sx * 3.0, 2.5, front - 0.35), Vector3.ONE * LAMP_SIZE, K_LAMP, Color.WHITE, tone, true)
		add.call(Vector3(sx * 2.2, 2.6, hz + d * 0.5 + 0.3), Vector3.ONE * LAMP_SIZE, K_LAMP, Color.WHITE, tone, true)
	var garden := 3 + int(_h(s, "gn") * 4.0)
	for i in garden:
		var p := Vector3(lerpf(-PAD.x * 0.5 + 1.6, PAD.x * 0.5 - 1.6, _h(s, ["ga", i])), 0.6, lerpf(1.0, front - 1.4, _h(s, ["gz", i])))
		if absf(p.x) < 6.5:
			p.x = signf(p.x if p.x != 0.0 else 1.0) * 7.0
		add.call(p, Vector3.ONE * LAMP_SIZE * 0.8, K_LAMP, Color.WHITE, clampf(tone + 0.2, 0.0, 0.99), true)
	_drive_lamps(out, plan, m, pos + Vector2(basis.z.x, basis.z.z) * (front + 0.4), deck, tone, real)
	return out


## The trees round an estate for the far city's planting (Skyline's veg): [Transform3D of a canopy
## blob, linear Color]. With HillHomeKit, the plan's own cypress, olives and palms; else a few
## dark crowns behind and beside the villa. Never under Skyline.HILL_OAK_HEIGHT.x: the far hills
## plant no low mounds (hill_air_checks).
static func trees(plan: CityPlan, m: Dictionary) -> Array:
	var out: Array = []
	var s: int = int(m.seed)
	if HillHomeKit.enabled:
		var h := HillHomeKit.plan_home(plan, m)
		var i := 0
		for t: Array in h.trees:
			var p := HillHomeKit.frame_point(h, t[1])
			var kind := String(t[0])
			var th := maxf(float(t[2]) if kind != "palm" else 9.0, 6.0)
			var r := 1.1 if kind == "cypress" else (1.8 if kind == "palm" else 2.6)
			var c := lerpf(0.85, 1.15, _h(s, ["tc", i]))
			var base := Color(0.045, 0.065, 0.032) if kind == "cypress" else (Color(0.11, 0.12, 0.07) if kind == "olive" else Color(0.07, 0.10, 0.045))
			out.append([Transform3D(Basis(Vector3.UP, _h(s, ["ty", i]) * TAU).scaled(Vector3(r, th, r)), Vector3(p.x, float(h.top) + th * 0.3, p.y)),
				Color(base.r * c, base.g * c, base.b * c, 1.0)])
			i += 1
		return out
	var pos: Vector2 = m.pos
	var basis := Basis(Vector3.UP, float(m.yaw))
	var deck := float(m.height) + PAD.y
	var n := 2 + int(_h(s, "tn") * 3.0)
	for i in n:
		var local := Vector3(lerpf(-12.0, 12.0, _h(s, ["tx", i])), 0.0, -9.5 if _h(s, ["tb", i]) < 0.6 else lerpf(-2.0, 9.0, _h(s, ["tz", i])))
		if local.z > -9.0 and absf(local.x) < 10.5:
			local.x = signf(local.x if local.x != 0.0 else 1.0) * 11.0
		var r := lerpf(2.4, 3.8, _h(s, ["tr", i]))
		var th := lerpf(6.0, 9.0, _h(s, ["th", i]))
		var at := Vector3(pos.x, deck + th * 0.3, pos.y) + basis * local
		var c := lerpf(0.85, 1.15, _h(s, ["tc", i]))
		# Alpha is Skyline's dissolve, not part of the tint.
		out.append([Transform3D(Basis(Vector3.UP, _h(s, ["ty", i]) * TAU).scaled(Vector3(r, th, r * 0.9)), at),
			Color(0.06 * c, 0.085 * c, 0.04 * c, 1.0)])
	return out
