class_name PavingAA
extends RefCounted
## Patterned ground without moire (docs/HANDOFF.md "Patterned ground without moire"): every
## ground shader's repeating pattern - the pavement's slab joints, a deck's board gaps, stall and
## centre lines, chevrons, grooves, setts and pavers - is box-filtered by the pixel's footprint
## (shaders/pattern_aa.gdshaderinc) and its textures' mips are kept honest, so a pattern is crisp
## up close and its plain average far off, never stripes. This is the switch: `PAVING_AA=0` in
## the environment turns it off (the A/B): the `paving_aa` shader global goes to 0 and every
## shader keeps its old line.

static var enabled: bool = OS.get_environment("PAVING_AA") != "0"

## A paving texture set's MODULE as a share of one tile: the smallest repeat of its pattern (a
## sett row, a brick course, a paver), measured by the art's spectrum (the strongest period along
## each axis, the finer one; HANDOFF "Patterned ground without moire"). A ground shader fades the
## texture to its mean once a module is under two pixels (paa_tex_fade). Sets with no laid
## pattern (concrete, gravel, asphalt) are not listed: 0, never faded.
const MODULE := {
	"paving": 1.0 / 14.0,  # PavingStones138: setts in ~14 rows a tile
	"pavers": 1.0 / 3.0,   # LargeSquarePattern01: 3 x 3 square pavers
	"brick": 1.0 / 15.0,   # Bricks104: 15 courses a tile
}


## The module in metres of a set laid at `scale_m` metres a tile (0 = no pattern).
static func module_m(set_key: String, scale_m: float) -> float:
	return float(MODULE.get(set_key, 0.0)) * scale_m


## Pushes the switch to the shaders (Weather._ready(), beside WetWorld's).
static func install() -> void:
	RenderingServer.global_shader_parameter_set("paving_aa", 1.0 if enabled else 0.0)


## Turns it on or off at once (tests, stills).
static func set_enabled(on: bool) -> void:
	enabled = on
	install()


# --- Mirror of shaders/pattern_aa.gdshaderinc (the checks hold the two together) ---------------

## paa_prim(): the antiderivative of lines `w` wide every `p`, at `x`.
static func prim(x: float, p: float, w: float) -> float:
	var s := x / p + 0.5 * w / p
	return floorf(s) * w + minf((s - floorf(s)) * p, w)


## paa_lines(): coverage of those lines averaged over a footprint `fw` wide.
static func lines(x: float, p: float, w: float, fw: float) -> float:
	var f := maxf(fw, p * 1.0e-4)
	if f > p * 8.0:
		return w / p
	return clampf((prim(x + 0.5 * f, p, w) - prim(x - 0.5 * f, p, w)) / f, 0.0, 1.0)


## paa_stripes(): a square wave on for the first `duty` of every period.
static func stripes(x: float, p: float, duty: float, fw: float) -> float:
	return lines(x - 0.5 * duty * p, p, duty * p, fw)


## paa_keep(): how much of a detail `size` across still resolves at footprint `fw`.
static func keep(size: float, fw: float) -> float:
	return 1.0 - smoothstep(0.5, 1.0, fw / maxf(size, 1.0e-6) * 2.0)
