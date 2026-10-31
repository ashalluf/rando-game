extends RefCounted
## Patterned ground without moire (PavingAA, shaders/pattern_aa.gdshaderinc) for
## tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the autoloads.
## Checks: the ground shaders compile; the include's box filter and its GDScript mirror agree, are
## exact up close (a line is 1 inside, 0 outside), keep the pattern's mean at every footprint and
## never overshoot; every integer kind carried through a varying is ROUNDED before int() (the
## downtown forecourt's red / grey row stripes were a truncated 2.9999); every shader that took
## the filter honours the switch; the global exists and the switch drives it.

var _t: Node

const GROUND_SHADERS := ["res://shaders/road.gdshader", "res://shaders/lot_ground.gdshader",
	"res://shaders/lot_yard.gdshader", "res://shaders/alley_ground.gdshader",
	"res://shaders/car_park_deck.gdshader", "res://shaders/parklet.gdshader",
	"res://shaders/cemetery_stone.gdshader", "res://shaders/chinatown.gdshader"]

## The shaders that use the filter (each must keep its old line behind paa_on()).
const FILTERED := ["res://shaders/road.gdshader", "res://shaders/lot_ground.gdshader",
	"res://shaders/alley_ground.gdshader", "res://shaders/car_park_deck.gdshader",
	"res://shaders/parklet.gdshader"]


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var t0 := Time.get_ticks_msec()
	_shaders()
	_mirror()
	_filter_math()
	_rounding()
	_switch()
	print("PAVING_ALIASING_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


static func _text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""


func _shaders() -> void:
	var bad: Array = []
	for p: String in GROUND_SHADERS:
		var sh: Shader = load(p)
		if sh == null or sh.get_shader_uniform_list().is_empty():
			bad.append(p)
	_check(bad.is_empty(), "paving aa: the ground shaders compile (%s)" % str(bad))
	var off: Array = []
	for p: String in FILTERED:
		var src := _text(p)
		if not src.contains("pattern_aa.gdshaderinc") or not src.contains("paa_on()"):
			off.append(p)
	_check(off.is_empty(), "paving aa: every filtered shader includes the filter and keeps its old line behind the switch (%s)" % str(off))


## The include and PavingAA's copy are the same maths (the checks below run the copy).
func _mirror() -> void:
	var src := _text("res://shaders/pattern_aa.gdshaderinc")
	var lines := ["float s = x / p + 0.5 * w / p;", "return floor(s) * w + min(fract(s) * p, w);",
		"float f = max(fw, p * 1.0e-4);", "if (f > p * 8.0) {", "return w / p;",
		"return clamp((paa_prim(x + 0.5 * f, p, w) - paa_prim(x - 0.5 * f, p, w)) / f, 0.0, 1.0);",
		"return paa_lines(x - 0.5 * duty * p, p, duty * p, fw);",
		"return 1.0 - smoothstep(0.5, 1.0, fw / max(size, 1.0e-6) * 2.0);"]
	var missing: Array = []
	for l: String in lines:
		if not src.contains(l):
			missing.append(l)
	_check(missing.is_empty(), "paving aa: PavingAA mirrors pattern_aa.gdshaderinc (%s)" % str(missing))


func _filter_math() -> void:
	# Up close (a footprint far under the line) it is the plain pattern.
	var p := 2.0
	var w := 0.06
	var sharp := PavingAA.lines(0.0, p, w, 0.0001) > 0.99 and PavingAA.lines(2.0, p, w, 0.0001) > 0.99 \
		and PavingAA.lines(0.5, p, w, 0.0001) < 0.01 and PavingAA.lines(1.0, p, w, 0.0001) < 0.01 \
		and PavingAA.lines(-2.0 + 0.02, p, w, 0.0001) > 0.99
	_check(sharp, "paving aa: up close a joint is solid inside and absent outside")
	# The mean over a sweep is the pattern's share at every footprint, and nothing overshoots.
	var worst := 0.0
	var range_ok := true
	for fw: float in [0.001, 0.01, 0.05, 0.3, 1.0, 1.7, 2.0, 5.0, 20.0, 400.0]:
		var sum := 0.0
		var n := 4000
		for i in n:
			var x := -37.1 + (float(i) + 0.5) / float(n) * 4.0 * p
			var v := PavingAA.lines(x, p, w, fw)
			range_ok = range_ok and v >= 0.0 and v <= 1.0
			sum += v
		worst = maxf(worst, absf(sum / float(n) - w / p))
	_check(worst < 0.002 and range_ok, "paving aa: the filtered lines keep their mean (w/p) at every footprint and stay in 0..1 (worst %.4f)" % worst)
	# Far off (several periods a pixel) it is flat: the moire is gone, not just softened.
	var lo := 1.0
	var hi := 0.0
	for i in 200:
		var v := PavingAA.lines(float(i) * 0.731 + 0.13, p, w, 9.0)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_check(hi - lo < 0.012, "paving aa: at nine metres a pixel the joints are their plain average (%.4f..%.4f)" % [lo, hi])
	# A stripe pattern is on for its duty, a dash for the first half of its period.
	_check(PavingAA.stripes(1.0, 4.0, 0.5, 0.0001) > 0.99 and PavingAA.stripes(3.0, 4.0, 0.5, 0.0001) < 0.01,
		"paving aa: stripes are on for the first part of each period")
	_check(is_equal_approx(PavingAA.keep(0.06, 0.01), 1.0) and PavingAA.keep(0.06, 0.06) == 0.0,
		"paving aa: a 6 cm detail is kept at a centimetre a pixel and gone at six")


## Integer kinds carried through a varying are rounded before int(): an interpolated constant 3.0
## reads 2.9999 on some pixel rows (llvmpipe, GLES), and int() truncates it.
func _rounding() -> void:
	var re := RegEx.new()
	re.compile("int\\(\\s*(kind|v_kind)\\s*\\)")
	var bare: Array = []
	for p: String in GROUND_SHADERS:
		if re.search(_text(p)) != null:
			bare.append(p)
	_check(bare.is_empty(), "paving aa: no ground shader truncates an interpolated kind (%s)" % str(bare))
	_check(_text("res://shaders/lot_ground.gdshader").contains("int(kind + (paa_on() ? 0.5 : 0.0))"),
		"paving aa: the forecourt's paving kind is rounded (the downtown row stripes)")
	var yard := _text("res://shaders/lot_yard.gdshader")
	_check(not yard.contains("floor(variant * 31.0)") and not yard.contains("floor(variant * 997.0)"),
		"paving aa: the yards' slab and lawn seeds snap the interpolated variant first")


func _switch() -> void:
	_check(ProjectSettings.has_setting("shader_globals/paving_aa"), "paving aa: the paving_aa shader global is declared")
	# The dummy renderer (headless) keeps no global values: read back only where one does.
	var was := PavingAA.enabled
	PavingAA.set_enabled(false)
	var off: Variant = RenderingServer.global_shader_parameter_get("paving_aa")
	var off_flag := PavingAA.enabled
	PavingAA.set_enabled(true)
	var on: Variant = RenderingServer.global_shader_parameter_get("paving_aa")
	PavingAA.set_enabled(was)
	var read_ok := off == null or on == null or (float(off) == 0.0 and float(on) == 1.0)
	_check(not off_flag and read_ok, "paving aa: the switch turns the filter off and back on (global %s / %s)" % [str(off), str(on)])
