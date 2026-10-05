extends RefCounted
## Forward+ review (fleet session fwd-review-b), for tests/smoke_test.gd: the renderer traps the
## review found in the marina, the blast aftermath, climbing plants, building damage, the new crowd
## rigs and the schools, held so they do not come back. Loaded at run time, not named there.
##
## - A cull_disabled shader must not flip NORMAL on a back face: Godot already turns it toward the
##   camera there (probed on both renderers, docs/HANDOFF.md, the fwd-review-b section).
## - A generated normal map is OpenGL-style (green up): the crater's pit wall north of its centre
##   leans south, so its green is under one half.
## - `sky_tint` is raw sRGB on both renderers: a display-number shader never passes it through
##   disp() (which is for Forward+'s decoded textures).

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	for p in ["res://shaders/boat.gdshader", "res://shaders/climbers.gdshader", "res://shaders/smoke_column.gdshader"]:
		var code := (load(p) as Shader).code
		_t._check(not code.contains("nrm = -nrm") and not code.contains("NORMAL = -NORMAL"),
			"%s does not flip a back face's NORMAL a second time" % p.get_file())
	for p in ["res://shaders/school_walls.gdshader"]:
		var code := (load(p) as Shader).code
		_t._check(not code.contains("disp(sky_tint"), "%s reads sky_tint as the display colour it is" % p.get_file())
	var maps: Array = BlastAftermath.crater_textures(0)
	var img: Image = (maps[1] as Texture2D).get_image()
	if img == null or img.is_empty():
		_t._check(true, "the crater's normal map (no image data headless)")
		return
	if img.is_compressed():
		img.decompress()
	var n := img.get_width()
	var north := img.get_pixel(n / 2, n / 2 - n / 14).g
	var south := img.get_pixel(n / 2, n / 2 + n / 14).g
	_t._check(north < 0.5 and south > 0.5,
		"the crater's normal map is OpenGL-style: the pit's north wall leans south (g %.2f), its south wall north (g %.2f)" % [north, south])
