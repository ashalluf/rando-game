extends RefCounted
## Shimmer and crawl in motion (SpecularAA, shaders/specular_aa.gdshaderinc) for
## tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the autoloads.
## Checks: the shaders that took the include compile and keep their old line behind saa_on(); the
## include's maths and SpecularAA's GDScript copy agree; the geometric term widens a lobe only as
## much as the pixel's spread of normals asks and never past its limit; the minification term is
## nothing at one texel a pixel and the whole lost variance far off; the pulse coverage keeps its
## mean at every footprint; the road paint's widening keeps the marking's energy (width x cover);
## the global exists and the switch drives it.

var _t: Node

## The shaders that use the include (each must keep its old line behind saa_on()).
const USERS := ["res://shaders/car_paint.gdshader", "res://shaders/car_paint_damage.gdshader",
	"res://shaders/car_park_car.gdshader", "res://shaders/road.gdshader",
	"res://shaders/road_paint.gdshader", "res://shaders/building.gdshader"]


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var t0 := Time.get_ticks_msec()
	_shaders()
	_mirror()
	_geometric()
	_minified()
	_pulse()
	_paint_energy()
	_switch()
	print("SPECULAR_ALIASING_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


static func _text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""


## The source a shader is built from, its includes inlined (one level is enough here).
static func _source(path: String) -> String:
	var src := _text(path)
	var re := RegEx.new()
	re.compile("#include \"(res://[^\"]+)\"")
	for m in re.search_all(src):
		src += "\n" + _text(m.get_string(1))
	return src


func _shaders() -> void:
	var bad: Array = []
	var off: Array = []
	for p: String in USERS:
		var sh: Shader = load(p)
		if sh == null or sh.get_shader_uniform_list().is_empty():
			bad.append(p)
		var src := _source(p)
		if not src.contains("specular_aa.gdshaderinc") or not src.contains("saa_on()"):
			off.append(p)
	_check(bad.is_empty(), "specular aa: the shaders that took it compile (%s)" % str(bad))
	_check(off.is_empty(), "specular aa: every user includes it and keeps its old line behind the switch (%s)" % str(off))
	# Derivatives in uniform control flow: the car paint takes the normal's before any branch.
	var cp := _text("res://shaders/car_paint.gdshaderinc")
	var at := cp.find("void fragment()")
	var dn := cp.find("vec3 saa_dnx = dFdx(NORMAL);")
	_check(at > 0 and dn > at and dn < cp.find("if (cr_torn", at),
		"specular aa: the car paint takes its normal's derivatives before any branch")
	# The building's dither only on the punched / ribbon / slot styles, never the curtain wall
	# (sg_line() filters that one) or a shopfront.
	var b := _text("res://shaders/building.gdshader")
	_check(b.contains("saa_on() && !storefront && !chamfer && !garage && window_style != 2"),
		"specular aa: distant windows are dithered on the punched styles only")


## The include and SpecularAA's copy are the same maths (the checks below run the copy).
func _mirror() -> void:
	var src := _text("res://shaders/specular_aa.gdshaderinc")
	var lines := ["float variance = amount * (dot(dn_dx, dn_dx) + dot(dn_dy, dn_dy));",
		"float k = min(2.0 * variance, limit);", "return sqrt(clamp(rough * rough + k, 0.0, 1.0));",
		"float lost = slope_var * clamp(1.0 - 1.0 / max(texels * texels, 1.0), 0.0, 1.0);",
		"return 1.0 / (1.0 / max(shine, 1.0) + 0.5 * var);",
		"return clamp((widened + 2.0) / (shine + 2.0), 0.0, 1.0);"]
	var missing: Array = []
	for l: String in lines:
		if not src.contains(l):
			missing.append(l)
	_check(missing.is_empty(), "specular aa: SpecularAA mirrors specular_aa.gdshaderinc (%s)" % str(missing))


func _geometric() -> void:
	# A flat panel (no turn across the pixel) keeps its lacquer exactly.
	_check(is_equal_approx(SpecularAA.geometric(0.035, 0.0, 0.5, 0.18), 0.035),
		"specular aa: a flat panel's lacquer is untouched")
	# A wing's curve: a little wider. A silhouette: capped at the limit.
	var curve := SpecularAA.geometric(0.035, 2.0 * 0.03 * 0.03, 0.5, 0.18)
	var edge := SpecularAA.geometric(0.035, 4.0, 0.5, 0.18)
	_check(curve > 0.035 and curve < 0.06, "specular aa: a gentle curve widens the coat a little (%.3f)" % curve)
	_check(absf(edge - sqrt(0.035 * 0.035 + 0.18)) < 1e-4, "specular aa: a silhouette's widening stops at the limit (%.3f)" % edge)
	# Monotonic in the spread and never narrower than it was.
	var prev := 0.0
	var mono := true
	for i in 30:
		var r := SpecularAA.geometric(0.1, float(i) * 0.01, 0.25, 0.18)
		mono = mono and r >= prev and r >= 0.1
		prev = r
	_check(mono, "specular aa: the lobe only ever widens with the spread of normals")


func _minified() -> void:
	_check(is_equal_approx(SpecularAA.minified(0.07, 0.041, 1.0), 0.07),
		"specular aa: a normal map at one texel a pixel keeps its own roughness")
	var far := SpecularAA.minified(0.07, 0.041, 64.0)
	_check(absf(far - sqrt(0.07 * 0.07 + 0.041)) < 2e-3, "specular aa: far off the lost slope variance is all in the roughness (%.3f)" % far)
	_check(is_equal_approx(SpecularAA.minified(0.85, 0.0, 64.0), 0.85), "specular aa: a map with no slope adds nothing")
	# The road's Toksvig variance is the Asphalt033 map's (measured at 0.041).
	_check(_text("res://shaders/road.gdshader").contains("uniform float normal_slope_var = 0.041;"),
		"specular aa: the road carries its normal map's measured slope variance")


## The coverage pulse (saa_pulse in the include): exact up close, its mean (2h) at every footprint.
static func _prim(x: float, w: float) -> float:
	var s := x + 0.5 * w
	return floorf(s) * w + minf(s - floorf(s), w)


static func _pulse_at(x: float, c: float, h: float, fw: float) -> float:
	var f := maxf(fw, 1.0e-4)
	if f > 8.0:
		return 2.0 * h
	var xc := x - c
	return clampf((_prim(xc + 0.5 * f, 2.0 * h) - _prim(xc - 0.5 * f, 2.0 * h)) / f, 0.0, 1.0)


func _pulse() -> void:
	var src := _text("res://shaders/specular_aa.gdshaderinc")
	_check(src.contains("return floor(s) * w + min(fract(s), w);") and src.contains("return clamp((saa_prim(xc + 0.5 * f, 2.0 * h) - saa_prim(xc - 0.5 * f, 2.0 * h)) / f, 0.0, 1.0);"),
		"specular aa: the test's pulse is the include's")
	var c := 0.5
	var h := 0.16
	_check(_pulse_at(0.5, c, h, 0.001) > 0.99 and _pulse_at(0.1, c, h, 0.001) < 0.01 and _pulse_at(3.55, c, h, 0.001) > 0.99,
		"specular aa: up close a slot is glass inside and wall outside")
	var worst := 0.0
	var range_ok := true
	for fw: float in [0.001, 0.05, 0.3, 0.8, 1.0, 1.6, 3.0, 12.0]:
		var sum := 0.0
		var n := 3000
		for i in n:
			var x := -11.3 + (float(i) + 0.5) / float(n) * 3.0
			var v := _pulse_at(x, c, h, fw)
			range_ok = range_ok and v >= 0.0 and v <= 1.0
			sum += v
		worst = maxf(worst, absf(sum / float(n) - 2.0 * h))
	_check(worst < 0.003 and range_ok, "specular aa: the window coverage keeps the glass share at every footprint (worst %.4f)" % worst)


## The paint's widening: a marking widened k times is mixed by 1/k, so width x cover is kept.
func _paint_energy() -> void:
	var src := _text("res://shaders/road_paint.gdshader")
	_check(src.contains("VERTEX[a] *= k;") and src.contains("paint_cover /= k;") and src.contains("ALBEDO = mix(asphalt"),
		"specular aa: a widened marking keeps its width x cover and fades toward the asphalt")
	_check(src.contains("if (c0.w > 0.05)") and src.contains("if (c1.w > 0.05)"),
		"specular aa: the paint's widening skips points behind the camera")


func _switch() -> void:
	_check(ProjectSettings.has_setting("shader_globals/specular_aa"), "specular aa: the specular_aa shader global is declared")
	var was := SpecularAA.enabled
	SpecularAA.set_enabled(false)
	var off: Variant = RenderingServer.global_shader_parameter_get("specular_aa")
	var off_flag := SpecularAA.enabled
	SpecularAA.set_enabled(true)
	var on: Variant = RenderingServer.global_shader_parameter_get("specular_aa")
	SpecularAA.set_enabled(was)
	var read_ok := off == null or on == null or (float(off) == 0.0 and float(on) == 1.0)
	_check(not off_flag and read_ok, "specular aa: the switch turns it off and back on (global %s / %s)" % [str(off), str(on)])
