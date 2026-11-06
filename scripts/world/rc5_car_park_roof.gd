class_name RcCarParkRoof
extends RefCounted
## The car park's roof deck at golden hour (wave 8, refcam5 `car_park_roof` in
## tools/refcams/cameras_w8.json; docs/HANDOFF.md "The car park's roof deck at 18:15"). What the
## eye landed on first from the roof by the ramp's head, fixed in that order:
##  1. the parked cars were a candy box (Vehicle.PAINTS picked flat: a third saturated, all one
##     solid gloss): `paint()` deals a real car park's mix - mostly white / black / grey / silver -
##     and the metallic finishes ride INSTANCE_CUSTOM.a (2: car_park_car.gdshader's metallic);
##  2. the core's roof-facing wall was a 42 m blank grey slab behind everything: `core()` gives it
##     precast panel reveals, the roof level's painted band, wall packs, downpipes, a louvre and a
##     second door;
##  3. the parapets were plain boxes: `parapets()` adds the panel joints and the coping the back
##     and the ramp opening lacked;
##  4. the light poles were square sticks on a hazard box: `poles()` builds round tapered poles on
##     concrete pedestals with LED shoebox heads (the old ones are not built);
##  5. the deck was one flat grey: car_park_deck.gdshader's `rc5` (the roof only) draws the precast
##     double tees' joints with their sealant, ponding stains, drains and a traffic coating's sheen.
## Everything is a hash of the car park's seed: no other car park, lot or roll moves.
## RC5_CAR_PARK_ROOF=0 is the A/B.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_CAR_PARK_ROOF") != "0"

## The parked cars' paint groups: share of the neutrals (Vehicle.PAINTS 0..19) and the muted
## colours (20..24); the rest is the saturated (25..). Roughly a real US car park.
const NEUTRAL_SHARE := 0.8
const MUTED_SHARE := 0.12
const NEUTRAL_END := 20
const MUTED_END := 25
## Precast double tees: their width along u (m), and the roof's joints' sealant width.
const TEE := 3.66
## Panel joints on the parapets and the core (m apart).
const PANEL := 3.0
## Roof poles: pedestal, pole height, head reach.
const PEDESTAL := 0.75
const POLE_H := 7.6
const POLE_R0 := 0.105
const POLE_R1 := 0.06
const ARM := 1.25


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## [paint (sRGB, as Vehicle.PAINTS), metallic] for a parked car of the stall `parts`.
static func paint(parts: Array) -> Array:
	var r := _h01(parts + ["rc5_group"])
	var lo := 0
	var hi := NEUTRAL_END
	if r >= NEUTRAL_SHARE + MUTED_SHARE:
		lo = MUTED_END
		hi = Vehicle.PAINTS.size()
	elif r >= NEUTRAL_SHARE:
		lo = NEUTRAL_END
		hi = MUTED_END
	var i := lo + absi(hash(parts + ["rc5_paint"])) % (hi - lo)
	var f: int = Vehicle.PAINT_FINISH[i]
	var metal := f == Vehicle.Finish.METALLIC or f == Vehicle.Finish.PEARL or f == Vehicle.Finish.DEEP
	return [Vehicle.PAINTS[i], metal]


## The core's face onto the roof (u = CORE, from the roof up): panel reveals, the roof level's
## band, two wall packs, a second door, downpipes, a louvre high up.
static func core(g: CarParkBuild.Geo, lay: Dictionary, band_key: String) -> void:
	var C := CarPark.CORE
	var ds: float = lay.ds
	var yr := CarPark.FLOOR * float(lay.decks)
	var top := float(lay.height) + 3.0
	# Reveals (dark, a hair proud so they read at a distance) every PANEL, and a horizontal one.
	var n := int(ds / PANEL)
	for i in range(1, n + 1):
		var v := ds * float(i) / float(n + 1)
		g.box("rc5_joint", Vector3(C, yr, v - 0.022), Vector3(C + 0.02, top, v + 0.022), false)
	g.box("rc5_joint", Vector3(C, yr + 2.88, 0.3), Vector3(C + 0.02, yr + 2.93, ds - 0.3), false)
	# The roof level's band (painted, the columns' colour) and the level's letter panels.
	g.box(band_key, Vector3(C, yr + 1.05, 0.3), Vector3(C + 0.008, yr + 1.6, ds - 0.3), false)
	# A second stair door at the far end, its EXIT sign; wall packs over both doors.
	var dv2 := ds - 2.6
	g.box("door", Vector3(C, yr, dv2 - 0.5), Vector3(C + 0.06, yr + 2.1, dv2 + 0.5), false)
	g.box("exit_sign", Vector3(C, yr + 2.2, dv2 - 0.25), Vector3(C + 0.08, yr + 2.42, dv2 + 0.25), false)
	for dv: float in [2.6, dv2, ds * 0.5]:
		g.box("steel", Vector3(C, yr + 3.35, dv - 0.2), Vector3(C + 0.16, yr + 3.65, dv + 0.2), false)
		g.box("lamp_head", Vector3(C + 0.06, yr + 3.33, dv - 0.16), Vector3(C + 0.15, yr + 3.36, dv + 0.16), false)
	# Downpipes from the core's roof to the deck, with their shoes.
	for dv: float in [0.6, ds - 0.6]:
		g.box("steel", Vector3(C, yr, dv - 0.06), Vector3(C + 0.12, top, dv + 0.06), false)
		g.box("steel", Vector3(C, yr, dv - 0.08), Vector3(C + 0.3, yr + 0.12, dv + 0.08), false)
	# A louvre (the stair's pressurisation) high on the wall.
	var lv := ds * 0.5 + 4.0
	g.box("steel", Vector3(C, yr + 4.2, lv - 0.9), Vector3(C + 0.05, yr + 5.2, lv + 0.9), false)
	for j in 6:
		var y := yr + 4.27 + float(j) * 0.16
		g.box("rc5_joint", Vector3(C + 0.05, y, lv - 0.85), Vector3(C + 0.09, y + 0.05, lv + 0.85), false)


## The roof's parapets: panel joints on their inner faces, coping on the back and round the ramp
## opening (the front and the far end had theirs).
static func parapets(g: CarParkBuild.Geo, lay: Dictionary) -> void:
	var ls: float = lay.ls
	var ds: float = lay.ds
	var e0: float = lay.e0
	var r0: float = lay.r0
	var r1: float = lay.r1
	var s0: float = lay.s0
	var s1: float = lay.s1
	var yr := CarPark.FLOOR * float(lay.decks)
	var hi := yr + CarPark.PARAPET
	var t := 0.18
	var W := CarPark.WALL
	# Coping: the back and the ramp opening's three sides.
	g.box("coping", Vector3(CarPark.CORE, hi, ds - 0.02), Vector3(ls + t, hi + 0.06, ds + t + 0.02), false)
	g.box("coping", Vector3(r0, hi, s0 - W - 0.03), Vector3(r1, hi + 0.06, s0 + 0.03), false)
	g.box("coping", Vector3(r0, hi, s1 - 0.03), Vector3(r1, hi + 0.06, s1 + W + 0.03), false)
	g.box("coping", Vector3(r0 - W - 0.03, hi, s0 - W), Vector3(r0 + 0.03, hi + 0.06, s1 + W), false)
	# Joints on the inner faces, every PANEL: front (v 0, face +v), back (v ds, face -v), far end.
	var u := e0 + PANEL
	while u < ls - 0.5:
		g.box("rc5_joint", Vector3(u - 0.02, yr, 0.0), Vector3(u + 0.02, hi, 0.015), false)
		g.box("rc5_joint", Vector3(u - 0.02, yr, ds - 0.015), Vector3(u + 0.02, hi, ds), false)
		u += PANEL
	var v := PANEL
	while v < ds - 0.5:
		g.box("rc5_joint", Vector3(ls - 0.015, yr, v - 0.02), Vector3(ls, hi, v + 0.02), false)
		v += PANEL
	# The ramp opening's walls: joints on both faces of both sides (the inner ones run down the
	# opening's full depth, to the deck below), and on its end wall.
	var below := yr - CarPark.FLOOR
	u = r0 + PANEL
	while u < r1 - 0.5:
		for f: Array in [[s0 - W - 0.015, s0 - W, yr], [s0, s0 + 0.015, below], [s1 - 0.015, s1, below], [s1 + W, s1 + W + 0.015, yr]]:
			g.box("rc5_joint", Vector3(u - 0.02, float(f[2]), float(f[0])), Vector3(u + 0.02, hi, float(f[1])), false)
		u += PANEL
	v = s0 + PANEL * 0.5
	while v < s1 - 0.3:
		g.box("rc5_joint", Vector3(r0 - W - 0.015, yr, v - 0.02), Vector3(r0 - W, hi, v + 0.02), false)
		v += PANEL


## The roof's light poles (in place of CarParkBuild._roof's): on the aisles' centre lines, a
## yellow concrete pedestal, a round tapered pole, two LED shoebox heads on short arms.
static func poles(g: CarParkBuild.Geo, lay: Dictionary) -> void:
	var y := CarPark.FLOOR * float(lay.decks)
	var m0: float = lay.m0
	var m1: float = lay.m1
	for b: Array in lay.bands:
		if int(b[2]) != 0:
			continue
		var vc := (float(b[0]) + float(b[1])) * 0.5
		var n := maxi(1, int((m1 - m0) / CarParkBuild.ROOF_POLE_SPACING))
		for i in n:
			var u := m0 + (float(i) + 0.5) * (m1 - m0) / float(n)
			var c := Vector3(u, y, vc)
			_cyl(g, "precast", c, 0.32, 0.3, PEDESTAL, 12, true)
			_cyl(g, "hazard", c + Vector3(0.0, 0.05, 0.0), 0.325, 0.325, 0.3, 12, false)
			_cyl(g, "steel", c + Vector3(0.0, PEDESTAL, 0.0), 0.16, 0.16, 0.06, 8, false)
			_cyl(g, "steel", c + Vector3(0.0, PEDESTAL, 0.0), POLE_R0, POLE_R1, POLE_H, 10, false)
			var ht := y + PEDESTAL + POLE_H
			for sv: float in [-1.0, 1.0]:
				# The arm along v, the head at its end, its lens facing down.
				g.box("steel", Vector3(u - 0.035, ht - 0.25, vc + sv * 0.05 - 0.035), Vector3(u + 0.035, ht - 0.18, vc + sv * ARM), false)
				var hc := vc + sv * (ARM + 0.2)
				g.box("door", Vector3(u - 0.24, ht - 0.33, hc - 0.32), Vector3(u + 0.24, ht - 0.17, hc + 0.32), false)
				g.box("lamp_head", Vector3(u - 0.2, ht - 0.335, hc - 0.28), Vector3(u + 0.2, ht - 0.33, hc + 0.28), false)
			_cyl(g, "steel", Vector3(u, ht - 0.25, vc), 0.075, 0.075, 0.12, 8, false)


## A tapered cylinder from `c` up `h` metres, radii r0 at the foot and r1 at the top, `sides`
## facets, its top capped.
static func _cyl(g: CarParkBuild.Geo, key: String, c: Vector3, r0: float, r1: float, h: float, sides: int, collide: bool) -> void:
	var circ := TAU * r0
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var nm := Vector3(cos((a0 + a1) * 0.5), (r0 - r1) / maxf(h, 0.01), sin((a0 + a1) * 0.5)).normalized()
		var q := [c + d0 * r0, c + d1 * r0, c + d1 * r1 + Vector3(0.0, h, 0.0), c + d0 * r1 + Vector3(0.0, h, 0.0)]
		var ua := circ * float(i) / float(sides)
		var ub := circ * float(i + 1) / float(sides)
		g.quad(key, q, nm, [Vector2(ua, c.y), Vector2(ub, c.y), Vector2(ub, c.y + h), Vector2(ua, c.y + h)], Vector2.ZERO, collide)
		g.tri(key, c + Vector3(0.0, h, 0.0), c + d0 * r1 + Vector3(0.0, h, 0.0), c + d1 * r1 + Vector3(0.0, h, 0.0), Vector3.UP,
				Vector2.ZERO, Vector2(d0.x, d0.z) * r1, Vector2(d1.x, d1.z) * r1, Vector2.ZERO, collide)


## The joints' material (CarParkBuild.material() hands "rc5_*" here; the poles, pipes, heads and
## pedestals reuse the structure's steel, door and precast, so they add no draw).
static func material(key: String) -> Material:
	if key == "rc5_joint":
		return PropFactory.material(Color(0.2, 0.2, 0.2), 0.9)
	return PropFactory.material(Color(0.5, 0.5, 0.5))
