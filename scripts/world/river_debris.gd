class_name RiverDebris
## What lives and lies on the LA River's concrete bed (wave 5, refcam `la_river`, docs/HANDOFF.md
## "The LA River from the bed"): the bed read as a swept stage. Weed tufts grow out of the tar-
## sealed joints, in a ragged line along the low flow's lip and at the foot of each bank; and a
## little of what the city throws in - shopping carts (some on their side), tyres, trash bags, a
## mattress - lies where the last flow left it.
##
## FULL chunks only (RiverBuild._props_step() calls dress() after its own props), every roll a hash
## of the seed and the place (LaRiver.h01), no rng, no collision (the litter is under a car's
## wheels' notice), one batch per kind: `rv_tuft_<v>` / `rv_mustard` (VacantKit's weeds, shadowless) and `rv_litter_<piece>`. Off with
## RIVER_LOOK=0 (RiverLook.enabled()).

## Bed joints across the river every PANEL metres (river_concrete.gdshader panel_pitch) and along it
## every LANE metres from the bed's edge (the shader's 6 m lines).
const PANEL := 9.2
const LANE := 6.0
## Odds that a joint crossing / a lip or toe slot carries a tuft.
const JOINT_ODDS := 0.32
const LIP_ODDS := 0.55
const TOE_ODDS := 0.5
## Slot spacing (metres) along the lip and the toes.
const LIP_STEP := 1.7
const TOE_STEP := 1.4
## Litter per 8 m segment and side.
const LITTER_ODDS := 0.075
## Draw distances: the tufts are knee-high and fade before the cards turn to mush.
const WEED_DISTANCE := 85.0
const LITTER_DISTANCE := 140.0
## Nothing within this many metres (along the river) of a ramp's foot (the cars come down there).
const RAMP_CLEAR := 6.0
## Trash bag colours (black, grey, a blue recycling bag, a white kitchen bag).
const BAG_COLORS := [Color(0.07, 0.07, 0.08), Color(0.09, 0.09, 0.1), Color(0.32, 0.33, 0.34), Color(0.12, 0.2, 0.42), Color(0.78, 0.78, 0.74)]
## Per chunk caps.
const MAX_WEEDS := 420
const MAX_LITTER := 14


static func dress(b: RiverBuild) -> void:
	if not RiverLook.enabled():
		return
	var rv := b.rv
	var ch := b.ch
	var weeds := 0
	var litter := 0
	var lf := LaRiver.lf_half()
	var ramps: Array = rv.ramps(b.plan)
	for i in range(b.ir.x, b.ir.y):
		if not b._owned_s(i):
			continue
		var s0: float = rv.run[i]
		var s1: float = rv.run[i + 1]
		var bh := rv.bed_half(s0)
		for sg: float in [1.0, -1.0]:
			if _near_ramp(ramps, (s0 + s1) * 0.5, sg):
				continue
			# Along the joints across the bed.
			var k0 := int(ceil(s0 / PANEL))
			var k1 := int(floor((s1 - 0.001) / PANEL))
			for k in range(k0, k1 + 1):
				var s := k * PANEL
				for m in int((bh - lf) / LANE) + 2:
					var key := ["rv_weed_j", k, m, sg]
					if rv.h01(key) >= JOINT_ODDS or weeds >= MAX_WEEDS:
						continue
					var o := lf + 0.6 + rv.h01(key + ["o"]) * (bh - lf - 1.2)
					_tuft(b, s, sg * o, key, 0.55)
					weeds += 1
			for m in int((bh - lf) / LANE) + 1:
				# Along the joints that run down the river (the shader's 6 m lines from the edge).
				var o := bh - (m + 1) * LANE + 0.5
				if o < lf + 0.4:
					continue
				var key := ["rv_weed_l", i, m, sg]
				if rv.h01(key) >= JOINT_ODDS * 0.8 or weeds >= MAX_WEEDS:
					continue
				_tuft(b, lerpf(s0, s1, rv.h01(key + ["s"])), sg * o, key, 0.55)
				weeds += 1
			# The low flow's lip: the wettest ground on the bed, the most growth.
			var s := s0
			var q := 0
			while s < s1 and weeds < MAX_WEEDS:
				var key := ["rv_weed_lip", i, q, sg]
				if rv.h01(key) < LIP_ODDS:
					_tuft(b, s + rv.h01(key + ["s"]) * LIP_STEP, sg * (lf + 0.15 + 0.35 * rv.h01(key + ["o"])), key, 0.85)
					weeds += 1
				s += LIP_STEP
				q += 1
			# The bank's foot: silt piles up in the corner and grass takes it.
			s = s0
			q = 0
			while s < s1 and weeds < MAX_WEEDS:
				var key := ["rv_weed_toe", i, q, sg]
				if rv.h01(key) < TOE_ODDS:
					_tuft(b, s + rv.h01(key + ["s"]) * TOE_STEP, sg * (bh - 0.05 - 0.45 * rv.h01(key + ["o"])), key, 0.75)
					weeds += 1
				s += TOE_STEP
				q += 1
			# Litter on the bed.
			var lk := ["rv_litter", i, sg]
			if rv.h01(lk) < LITTER_ODDS and litter < MAX_LITTER:
				_litter(b, lerpf(s0, s1, rv.h01(lk + ["s"])), sg * lerpf(lf + 1.2, bh - 1.5, rv.h01(lk + ["o"])), lk)
				litter += 1
	if OS.get_environment("RIVER_DEBUG") == "1":
		print("RiverDebris chunk ", ch.ix, ",", ch.iz, " weeds ", weeds, " litter ", litter,)
	if weeds > 0:
		for k: String in ["rv_tuft_0", "rv_tuft_1", "rv_mustard"]:
			ch._batch.set_no_shadow(k)
			ch._batch.set_draw_distance(k, WEED_DISTANCE)
	for piece: String in ["cart", "bag_trash", "mattress", "box", "tyre"]:
		ch._batch.set_draw_distance("rv_litter_" + piece, LITTER_DISTANCE)


static func _near_ramp(ramps: Array, s: float, sg: float) -> bool:
	for r: Dictionary in ramps:
		if float(r.side) == sg and s > minf(r.s0, r.s1) - RAMP_CLEAR and s < maxf(r.s0, r.s1) + RAMP_CLEAR:
			return true
	return false


## A tuft at (s, o) on the bed (VacantKit's foxtail and wild oats, the city's dry weeds), sized by
## `big`; at the bank's foot now and then a stalk of wild mustard.
static func _tuft(b: RiverBuild, s: float, o: float, key: Array, big: float) -> void:
	var rv := b.rv
	var p := rv.point(s, o)
	var y := rv.surface(s, o)
	var dry := rv.h01(key + ["g"])
	var v := 0 if dry > 0.3 else 1
	var sc := lerpf(0.55, 1.05, rv.h01(key + ["sc"])) * big
	var tint := Color(lerpf(0.85, 1.12, dry), lerpf(0.85, 1.08, dry), lerpf(0.75, 1.0, dry))
	var xf := Transform3D(Basis(Vector3.UP, rv.h01(key + ["y"]) * TAU).scaled(Vector3(sc, sc * lerpf(0.8, 1.3, rv.h01(key + ["h"])), sc)), b._rel(Vector3(p.x, y - 0.01, p.y)))
	if big > 0.7 and rv.h01(key + ["mustard"]) < 0.08:
		b.ch._batch.add("rv_mustard", VacantKit.mustard(), xf, tint)
		return
	b.ch._batch.add("rv_tuft_%d" % v, VacantKit.tuft(v), xf, tint)
	# Weeds come in clumps: one or two smaller ones beside it.
	for c in int(rv.h01(key + ["n"]) * 3.0):
		var a := rv.h01(key + ["ca", c]) * TAU
		var r := lerpf(0.15, 0.45, rv.h01(key + ["cr", c]))
		var q := p + Vector2(cos(a), sin(a)) * r
		var cs := sc * lerpf(0.5, 0.85, rv.h01(key + ["cs", c]))
		b.ch._batch.add("rv_tuft_%d" % v, VacantKit.tuft(v), Transform3D(Basis(Vector3.UP, a * 3.0).scaled(Vector3(cs, cs, cs)), b._rel(Vector3(q.x, y - 0.01, q.y))), tint)


## One piece of litter: a cart (upright, or on its side), a tyre, trash bags, a box, a mattress.
static func _litter(b: RiverBuild, s: float, o: float, key: Array) -> void:
	var rv := b.rv
	var r := rv.h01(key + ["kind"])
	var p := rv.point(s, o)
	var y := rv.surface(s, o)
	var yaw := rv.h01(key + ["yaw"]) * TAU
	var basis := Basis(Vector3.UP, yaw)
	var piece := "cart"
	var tint := Color(1.0, 1.0, 1.0)
	var custom := Color(lerpf(0.5, 1.0, rv.h01(key + ["sun"])), rv.h01(key + ["w"]), 0.0, 0.0)
	var lift := 0.0
	if r < 0.32:
		if rv.h01(key + ["fall"]) < 0.55:
			# On its side, the way the flow leaves them.
			basis = basis * Basis(Vector3.FORWARD, PI * 0.5)
			lift = 0.3
	elif r < 0.55:
		piece = "tyre"
	elif r < 0.8:
		piece = "bag_trash"
		tint = BAG_COLORS[int(rv.h01(key + ["c"]) * BAG_COLORS.size()) % BAG_COLORS.size()]
	elif r < 0.92:
		piece = "box"
	else:
		piece = "mattress"
		tint = Color(0.62, 0.56, 0.46)
	var at := b._rel(Vector3(p.x, y + lift, p.y))
	if piece == "tyre":
		var tb := Basis(Vector3.UP, yaw)
		if rv.h01(key + ["up"]) < 0.3:
			# Stood on its tread against nothing, leaning: a tyre rolled down the bank.
			tb = tb * Basis(Vector3.RIGHT, PI * 0.5 - 0.35)
			at.y += 0.25
		b.ch._batch.add("rv_litter_tyre", PropFactory.model_tyre(), Transform3D(tb, at), Color(0.55, 0.55, 0.55))
		return
	b.ch._batch.add("rv_litter_" + piece, PropFactory.encampment(piece), Transform3D(basis, at), tint, custom)
