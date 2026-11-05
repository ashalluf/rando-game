class_name ConstructionDusk
extends RefCounted
## A tower site at dusk (refcam5 `construction_dusk`, docs/HANDOFF.md "The construction site at
## dusk"). What the 18:45 view of a Construction tower site lacked, as hooks in construction.gd:
##
## * The late shift: a high-rise crew pours and strips into the evening under work lights, so the
##   crews (deck, gate) stay on until `SHIFT_END` (Construction.working()), and the gate gets two
##   more hands standing just inside the open leaves (`gate_crew()`), not only the flagger.
## * Work lights (`work_lights()`): LED tube fittings under the soffit of every open floor (the
##   storeys you see through the netting were black boxes at dusk), and on the top deck four
##   light towers with flood panels aimed in, each with a glow billboard (Construction's lights
##   mesh, warm white) and, on desktop, an OmniLight in `lamp_light` so the deck, the columns and
##   the net are really lit (DayNight drives its energy from the lamps' level).
## * The curtain wall's mirror and the floors behind it (construction.gdshader `dusk_glass`): the
##   finished storeys read as one black slab at dusk - the mirror took the zenith's colour flat and
##   the city under the horizon at 35 % of nothing. Now the sky brightens to the horizon, the city
##   below it is a scatter of lit windows after dark, and a share of the storeys behind the glass
##   are lit by the fit-out's temporary lights (a bright ceiling band through the glass).
## * Fly posters (construction.gdshader `printed_posters`): the hoarding's posters were blank flat
##   rectangles of cream and red, which from the pavement read as missing textures. Now they are
##   StreetWear's printed bills (its paper atlas), pasted in runs of one poster repeated along a
##   row, torn and sun-faded with age.
##
## CONSTRUCTION_DUSK=0 in the environment is the A/B (all four off, the site exactly as before).

static var enabled: bool = OS.get_environment("CONSTRUCTION_DUSK") != "0"

## The late crew goes home at this hour.
const SHIFT_END := 20.5
## Under-soffit LED fittings: spacing of the grid on an open floor, inset from the slab edge.
const TUBE_PITCH := 6.0
const TUBE_INSET := 2.4
## Light towers on the top deck: height of the mast, their inset from the deck's corners.
const TOWER_H := 4.2
const TOWER_INSET := 3.0
## The OmniLights on the deck (desktop): range and the share of the street lamps' level.
const DECK_LIGHT_RANGE := 26.0
const DECK_LIGHT_GAIN := 2.4
## Warm-white LED (sRGB, the lights mesh's colour).
const LED := Color(1.0, 0.93, 0.80)


## True while the late shift is on (after the day's WORK_HOURS, before SHIFT_END).
static func late(h: float) -> bool:
	return enabled and h > Construction.WORK_HOURS.y and h <= SHIFT_END


## Two more of the crew at the gate, just inside its open leaves (`mid` the gate's middle on the
## hoarding line, `out` toward the street, `along` along the hoarding).
static func gate_crew(ch: CityChunk, site: Dictionary, mid: Vector2, out: Vector2, along: Vector2) -> void:
	if not enabled:
		return
	var ps := ch.plan.seed
	var rect: Rect2 = ch.plan.block(ch.ix, ch.iz).rect
	var workers: Array = Construction._state(ch).workers
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var p := mid - out * (1.4 + 0.6 * float(i)) + along * side * (1.3 + 0.5 * Construction._h01([ps, site.seed, "dusk_gate", i]))
		# Turned toward each other a little, toward the street mostly.
		var look := (out * 1.6 - along * side * 0.9).normalized()
		workers.append({"at": p, "yaw": atan2(-look.x, -look.y), "lift": 0.0, "rect": rect,
			"seed": hash([ps, site.seed, "dusk_gate", i]), "paddle": false, "deck": false})


## The work lights of a tower site: LED fittings under each open floor's slab above, light towers
## on the top deck, their glow billboards and (desktop) two OmniLights over the deck.
static func work_lights(ch: CityChunk, st: SurfaceTool, site: Dictionary, floor_y: float) -> void:
	if not enabled:
		return
	var K := ConstructionKit
	var foot: Rect2 = site.foot
	var core: Rect2 = site.core
	var built: int = site.built
	var clad: int = site.clad
	var top: float = site.top
	var lights: Array = Construction._state(ch).lights
	var inner := foot.grow(-TUBE_INSET)
	var nx := maxi(1, roundi(inner.size.x / TUBE_PITCH)) + 1
	var nz := maxi(1, roundi(inner.size.y / TUBE_PITCH)) + 1
	var tubes := 0
	# Every open floor that has a slab over it: a grid of fittings on that slab's soffit.
	for k in range(clad + 1, built):
		var y := floor_y + Construction.slab_y(k + 1) - Construction.SLAB - 0.06
		for i in nx:
			for j in nz:
				var p := Vector2(lerpf(inner.position.x, inner.end.x, float(i) / float(nx - 1)), lerpf(inner.position.y, inner.end.y, float(j) / float(nz - 1)))
				if core.grow(0.6).has_point(p):
					continue
				K.box(st, Transform3D(Basis(), Vector3(p.x, y, p.y)), Vector3(1.2, 0.05, 0.1), K.K_STRIP, Color.WHITE, -1.0, 0, 16)
				tubes += 1
				# The perimeter fittings glow from the street (a billboard each on the edge rows).
				if i == 0 or j == 0 or i == nx - 1 or j == nz - 1:
					lights.append([Vector3(p.x, y - 0.06, p.y), 0.55, Color(LED.r, LED.g, LED.b, 0.55)])
	# The top deck: a light tower in from each corner, flood panels aimed at the deck's middle.
	var ty := floor_y + top
	var fc := foot.get_center()
	var tops: Array[Vector3] = []
	for corner: Vector2 in [foot.position, Vector2(foot.end.x, foot.position.y), foot.end, Vector2(foot.position.x, foot.end.y)]:
		var p := corner + (fc - corner).normalized() * TOWER_INSET
		if core.grow(1.0).has_point(p):
			continue
		K.box(st, Transform3D(Basis(), Vector3(p.x, ty + 0.12, p.y)), Vector3(1.4, 0.24, 1.0), K.K_PAINT, K.MACHINE_YELLOW)
		K.box(st, Transform3D(Basis(), Vector3(p.x, ty + TOWER_H * 0.5, p.y)), Vector3(0.12, TOWER_H, 0.12), K.K_GALV, Color.WHITE, -1.0, 0, 48)
		var to_c := (fc - p).normalized()
		var yaw := atan2(-to_c.x, -to_c.y)
		var head := Vector3(p.x, ty + TOWER_H, p.y)
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		for s in [-1.0, 1.0]:
			var hp: Vector3 = head + right * 0.42 * s
			var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.6), hp)
			K.box(st, xf, Vector3(0.62, 0.42, 0.12), K.K_PAINT, Color(0.16, 0.16, 0.17), -1.0, 0, 0)
			# The lens face, toward the deck.
			K.box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.0, -0.065)), Vector3(0.54, 0.34, 0.01), K.K_LAMP, LED, -1.0, 0, 0)
			lights.append([hp + Vector3(to_c.x, -0.3, to_c.y) * 0.1, 1.1, LED])
		tops.append(head)
	if OS.has_feature("web") or tops.is_empty():
		return
	# Two OmniLights over the deck (opposite towers): the deck, the columns and the net really lit.
	var picks: Array[Vector3] = [tops[0]]
	if tops.size() > 2:
		picks.append(tops[2])
	for hp: Vector3 in picks:
		var l := OmniLight3D.new()
		l.name = "DuskWorkLight"
		l.light_color = Color(1.0, 0.9, 0.76)
		l.omni_range = DECK_LIGHT_RANGE
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.light_energy = 0.0
		l.set_meta("lamp_gain", DECK_LIGHT_GAIN)
		l.position = hp + (Vector3(fc.x, hp.y, fc.y) - hp).normalized() * 1.5 - Vector3(0.0, 0.6, 0.0)
		l.add_to_group("lamp_light")
		ch.add_child(l)
