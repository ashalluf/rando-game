class_name CoastFlutes
extends RefCounted
## The coast highway's bluff fluted by rain gullies (Rc5CoastHighway, docs/HANDOFF.md "The coast
## highway at 17:00 from the seawall"). Its own small script so MacroMap.height_at() names nothing
## that needs the autoloads (tools that run MacroMap under --script compile it alone).
## `RC5_COAST=0` in the environment turns it off with the rest of the pass.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_COAST") != "0"

## Gullies: the mean spacing along the shore, how deep (at the bottom of the face, and per metre of
## height, capped), how wide a gully is against its cell, and how far up the face they start.
const FLUTE_CELL := 19.0
const FLUTE_DEPTH := 2.0
const FLUTE_PER_M := 0.24
const FLUTE_MAX := 13.0
const FLUTE_WIDTH := 0.62
const FLUTE_START := 1.0
const FLUTE_FULL := 9.0
## How far from the toe the face is fluted (past it the mountains' own erosion takes over), and
## where the flutes fade out at the stretch's south end (the bench comes down there).
const FLUTE_REACH := 175.0
const FLUTE_SOUTH_FADE := 70.0


## The ground after the carve, with the bluff's face fluted. `h` is MacroMap.height_at()'s.
static func flute(m: MacroMap, pos: Vector2, h: float) -> float:
	if not enabled:
		return h
	var c: CoastHighway = m.coast_highway
	if c == null:
		return h
	var w := c.weight(pos.y)
	if w <= 0.0:
		return h
	w *= 1.0 - smoothstep(c.z_full - FLUTE_SOUTH_FADE, c.z_full, pos.y)
	if w <= 0.0:
		return h
	var d := pos.x - m.coast_x(pos.y)
	var toe := CoastHighway.TOE + 1.5
	if d < toe or d > FLUTE_REACH:
		return h
	var by := c.bed_y(pos.y)
	var above := h - by
	if above < FLUTE_START:
		return h
	var amount := w * smoothstep(FLUTE_START, FLUTE_FULL, above) * smoothstep(toe, toe + 5.0, d) \
			* (1.0 - smoothstep(FLUTE_REACH - 40.0, FLUTE_REACH, d))
	if amount <= 0.0:
		return h
	var g := gully(c.seed, pos.y, above)
	if g <= 0.0:
		return h
	var depth := minf(FLUTE_DEPTH + FLUTE_PER_M * above, FLUTE_MAX)
	return maxf(by + 0.4, h - amount * depth * g)


## 0..1: how far into a gully a point of the face is, at shore coordinate z and `above` metres up
## it. Each FLUTE_CELL cell along the shore holds one gully, its centre and width hashed; the line
## leans and wanders as it climbs, so the gullies are not ruler-straight.
static func gully(sd: int, z: float, above: float) -> float:
	var u := z + 2.2 * sin(above * 0.13 + z * 0.021) + 0.18 * above
	var cell := floori(u / FLUTE_CELL)
	var best := 0.0
	for k in [cell - 1, cell, cell + 1]:
		var hc := _h01(sd, k, 0)
		var centre := (float(k) + 0.2 + 0.6 * hc) * FLUTE_CELL
		var half := FLUTE_CELL * FLUTE_WIDTH * (0.35 + 0.4 * _h01(sd, k, 1))
		var t := absf(u - centre) / half
		if t < 1.0:
			# A rounded V: deep in the middle, easing out to the spur.
			var v := 1.0 - t * t
			best = maxf(best, v * v * (0.55 + 0.45 * _h01(sd, k, 2)))
	return best


static func _h01(sd: int, k: int, salt: int) -> float:
	return float(absi(hash([sd, "coast_flute", k, salt])) % 10007) / 10007.0
