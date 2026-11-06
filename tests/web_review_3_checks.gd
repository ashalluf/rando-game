extends RefCounted
## The web review after wave 3 (tests/smoke_test.gd; docs/HANDOFF.md "The web build after wave 3").
## WebGL2 is GLSL ES 3.00. Godot passes a shader's built-in calls through to the driver, so a
## function that only GLSL ES 3.10+ or desktop GLSL has (bitfieldExtract, findMSB, textureGather,
## fma, the Fine / Coarse derivatives, textureQueryLod ...) compiles on the Mac and in every
## opengl3 still and leaves a blank white material in the browser. No .gdshader or .gdshaderinc
## may call one outside a comment (the RenderingDevice compute kernels, *.glsl, are Forward+ only
## and not looked at).

const ES31_ONLY := ["bitfieldExtract", "bitfieldInsert", "bitfieldReverse", "bitCount", "findMSB",
	"findLSB", "uaddCarry", "usubBorrow", "umulExtended", "imulExtended", "frexp", "ldexp",
	"textureGather", "textureGatherOffset", "textureQueryLod", "textureQueryLevels", "imageLoad",
	"imageStore", "imageSize", "atomicAdd", "packUnorm4x8", "unpackUnorm4x8", "packSnorm4x8",
	"unpackSnorm4x8", "fma", "dFdxFine", "dFdyFine", "fwidthFine", "dFdxCoarse", "dFdyCoarse",
	"fwidthCoarse", "interpolateAtCentroid", "interpolateAtSample", "interpolateAtOffset"]

var _t: Node


func run(t: Node) -> void:
	_t = t
	var files: Array[String] = []
	_collect("res://shaders", files)
	var call := RegEx.create_from_string("\\b(" + "|".join(ES31_ONLY) + ")\\s*\\(")
	var bad: Array[String] = []
	for path in files:
		var src := _strip_comments(FileAccess.get_file_as_string(path))
		for m in call.search_all(src):
			bad.append("%s: %s" % [path.get_file(), m.get_string(1)])
	_t._check(files.size() > 100, "web review 3: the shader folder was read (%d files)" % files.size())
	_t._check(bad.is_empty(), "web review 3: no shader calls a GLSL ES 3.1+ built-in (WebGL2 is ES 3.00) %s" % [bad])
	# The rule holds what it says: a planted call is found.
	var planted := _strip_comments("// findMSB(x) in a comment\nint b = findMSB(a);")
	_t._check(call.search_all(planted).size() == 1, "web review 3: the ES 3.1 scan finds a call and skips a comment")


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gdshader") or f.ends_with(".gdshaderinc"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)


func _strip_comments(src: String) -> String:
	src = RegEx.create_from_string("(?s)/\\*.*?\\*/").sub(src, "", true)
	return RegEx.create_from_string("//[^\\n]*").sub(src, "", true)
