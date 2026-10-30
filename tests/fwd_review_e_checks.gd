extends RefCounted
## Forward+ review e (fleet wave 3, session fwd-review-e), for tests/smoke_test.gd: the renderer
## traps the review of the late wave-3 features found, held across EVERY shader where the rule is
## general. Source text only (no scene), so it leans on nothing that ran before it.
##
## - A display-number shader (its own disp() / to_lit()) takes a source_color texture through
##   disp() alone: disp(cs_in(tex)) decodes it twice on Compatibility (cs_in() decodes there,
##   disp() leaves it decoded) and every opengl3 still draws it too dark (the stunt ramps).
## - The facade pass's mirrored street opposite (fx_opposite(), facade_variety.gdshaderinc) writes
##   its walls as display numbers and building.gdshader emits the mirror in the renderer's own
##   space, so they go through fx_srgb_in() (decoded on Forward+ only); raw, Forward+ mirrored the
##   street as pale beige slabs.
## - The shop sign band's hues (building.gdshader and its far copy) are display numbers too: raw,
##   a red lightbox was a pale red past 1 on Forward+ and AgX drew it pink. fx_srgb_in() them.

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


func _code(p: String) -> String:
	var lines := PackedStringArray()
	for line in FileAccess.get_file_as_string(p).split("\n"):
		lines.append(line.split("//")[0])
	return "\n".join(lines)


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var files := _shader_files()
	_t._check(files.size() > 100, "fwd-review-e: the shader folder is readable (%d files)" % files.size())
	var twice: PackedStringArray = []
	for p in files:
		if _code(p).contains("disp(cs_in("):
			twice.append(p.get_file())
	_t._check(twice.is_empty(), "no display-number shader decodes a texture twice (disp(cs_in(...))) %s" % [twice])
	var ramp := _code("res://shaders/stunt_ramp.gdshader")
	_t._check(ramp.contains("disp(texture(concrete_tex"), "the stunt ramps' concrete is read as display numbers once")
	var fv := _code("res://shaders/facade_variety.gdshaderinc")
	_t._check(fv.contains("wall = fx_srgb_in(wall);"), "the mirrored street opposite's walls are decoded on Forward+")
	var b := fv.find("vec3 fx_srgb_in(")
	_t._check(b >= 0 and fv.find("RENDERER_COMPATIBILITY", b) > b and fv.find("RENDERER_COMPATIBILITY", b) < b + 200,
		"fx_srgb_in() leaves Compatibility's numbers as they are")
	for p in ["res://shaders/building.gdshader", "res://shaders/building_lod.gdshader"]:
		var c := _code(p)
		var at := c.find("vec3 sign_hue = mix(")
		var dec := c.find("sign_hue = fx_srgb_in(sign_hue);")
		var box := c.find("vec3 box = sign_hue /")
		_t._check(at > 0 and dec > at and dec < box, "%s decodes the sign band's hues before the lightbox is made of them" % p.get_file())
