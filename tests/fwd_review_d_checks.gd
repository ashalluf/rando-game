extends RefCounted
## Forward+ review d (fleet wave 3, session fwd-review-d), for tests/smoke_test.gd: the renderer
## traps the review of the wave-3 features found, held across EVERY shader so a new one cannot
## bring them back. Loaded at run time, not named there. Reads source text only (no scene, no
## player, no weather), so it does not care what ran before it.
##
## - `sky_tint` (and every `color` shader global) arrives as raw sRGB numbers on BOTH renderers.
##   A display-number shader (disp() / to_lit()) takes it as it is, never through disp(): the
##   refinery's and the power plant's glass, the film studio's, the deco ornament's and
##   industrial_walls' mirrored a sky re-encoded a second time (too bright on the Mac).
## - A shader that works in linear (it hands its colours over with cs_out()) decodes it
##   (cs_srgb_to_linear(), or pow 2.2): the hydrant's wet patch, the swimmer's underside of the
##   water, Chinatown's glass, the light rail's windows and the river took it as linear.
##   A luminance `dot(sky_tint ...)` is a scalar, not a colour, and is let through.
## - Vertex colours arrive raw on both renderers too: never cs_in() (which is for source_color
##   TEXTURES, decoded on Forward+ only) on COLOR (billboard_steel).
## - The river's sky mirror was written straight to EMISSION, raw sRGB read as linear on Forward+.

var _t: Node


func _shader_files() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open("res://shaders")
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gdshader") or f.ends_with(".gdshaderinc"):
			out.append("res://shaders/" + f)
	return out


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var files := _shader_files()
	_t._check(files.size() > 100, "fwd-review-d: the shader folder is readable (%d files)" % files.size())
	var disp_bad: PackedStringArray = []
	var lin_bad: PackedStringArray = []
	var col_bad: PackedStringArray = []
	var cs_in_color := RegEx.create_from_string("cs_in\\(\\s*COLOR")
	for p in files:
		var code := FileAccess.get_file_as_string(p)
		if code == "":
			continue
		var linear := code.contains("cs_out(") and not p.ends_with("color_space.gdshaderinc")
		var n := 0
		for line in code.split("\n"):
			n += 1
			var c: String = line.split("//")[0]
			if not c.contains("sky_tint") or c.contains("global uniform"):
				continue
			if c.contains("disp(sky_tint"):
				disp_bad.append("%s:%d" % [p.get_file(), n])
			if linear and not (c.contains("cs_srgb_to_linear") or c.contains("pow(") or c.contains("dot(sky_tint")):
				lin_bad.append("%s:%d" % [p.get_file(), n])
		if cs_in_color.search(code) != null:
			col_bad.append(p.get_file())
	_t._check(disp_bad.is_empty(), "no display-number shader passes sky_tint through disp() %s" % [disp_bad])
	_t._check(lin_bad.is_empty(), "every linear shader decodes sky_tint before using it as a colour %s" % [lin_bad])
	_t._check(col_bad.is_empty(), "no shader runs cs_in() on a raw vertex colour %s" % [col_bad])
	var river := FileAccess.get_file_as_string("res://shaders/river_water.gdshader")
	_t._check(river.contains("EMISSION = cs_out(sky)"), "the river's sky mirror is handed over in the renderer's space")
	var ocean := FileAccess.get_file_as_string("res://shaders/ocean.gdshader")
	_t._check(ocean.contains("cs_as_uniform(sky_tint.rgb)"), "the ocean's haze is sky_tint in the renderer's own space (the far plane's)")
	var sky := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	var late := sky.find("if (island_late) {")
	_t._check(late > 0 and late > sky.find("col = col * cl.a + cl.rgb;"),
		"under the Forward+ cloud volume the offshore island is drawn after the volume's composite")
	var flame := FileAccess.get_file_as_string("res://shaders/refinery_flame.gdshader")
	_t._check(flame.contains("exp(-r * r * 3.2) - 0.0408"), "the refinery flare's halo reaches nothing at its quad's edge")
	# The halo's value at the quad's edge, as the shader computes it: zero.
	var edge := maxf(exp(-3.2) - 0.0408, 0.0) / 0.9592
	_t._check(edge < 0.001, "the flare halo's edge value is %.4f" % edge)
	# The corner store's lit red sign face stays under AgX's salmon knee (~1) at night.
	var store := FileAccess.get_file_as_string("res://shaders/corner_store.gdshader")
	var m := RegEx.create_from_string("uniform float sign_cap = ([0-9.]+);").search(store)
	var cap := m.get_string(1).to_float() if m != null else 99.0
	_t._check(cap <= 0.8, "the corner store's lit sign is capped under AgX's salmon knee (%.2f)" % cap)
