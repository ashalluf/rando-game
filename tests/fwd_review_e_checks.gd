extends RefCounted
## Forward+ review e (fleet wave 3, session fwd-review-e), for tests/smoke_test.gd: the renderer
## traps the review of the late wave-3 features found, held across EVERY shader where the rule is
## general. Source text only (no scene), so it leans on nothing that ran before it.
##
## - A display-number shader (its own disp() / to_lit()) takes a source_color texture through
##   disp() alone: disp(cs_in(tex)) decodes it twice on Compatibility (cs_in() decodes there,
##   disp() leaves it decoded) and every opengl3 still draws it too dark (the stunt ramps).

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
