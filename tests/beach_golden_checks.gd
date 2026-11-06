extends RefCounted
## The beach at golden hour (BeachGolden, beach_golden.gdshaderinc), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks that the sand shader carries the postcard pass behind its switch and compiles, that its
## sky mirror takes sky_tint as the renderer's colour (the Forward+ fix), that the sand material
## is switched by BeachGolden, that the tower's paint and timber codes are the ones the props
## shader draws, and that the tower mesh carries them only while the switch is on - the same
## triangles either way (nothing rolls: the A/B changes looks, never placement). Leans on no state
## an earlier check left: it builds its own tower meshes and puts the switch back.

var _t: Object


func run(t: Object, _city: Node3D) -> void:
	_t = t
	_sand_shader()
	_props_shader()
	_tower()


func _sand_shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/beach_sand.gdshader")
	var inc := FileAccess.get_file_as_string("res://shaders/beach_golden.gdshaderinc")
	_t._check(src.contains("#include \"res://shaders/beach_golden.gdshaderinc\"") and src.contains("#include \"res://shaders/color_space.gdshaderinc\""),
		"beach_sand.gdshader includes the golden pass and the colour-space helpers")
	_t._check(inc.contains("uniform float golden_on") and src.contains("golden_on > 0.5 ? cs_as_uniform(sky_tint.rgb) : sky_tint.rgb"),
		"the sand's sky mirror takes sky_tint through cs_as_uniform behind golden_on (raw only with BEACH_GOLDEN=0)")
	for f: String in ["bg_ripples", "bg_hummocks", "bg_footprints", "bg_wrack", "bg_glint"]:
		_t._check(inc.contains("vec3 " + f + "(") or inc.contains("float " + f + "("), "beach_golden.gdshaderinc defines %s" % f)
	var sh: Shader = load("res://shaders/beach_sand.gdshader")
	var names: Array = sh.get_shader_uniform_list().map(func(u: Dictionary) -> String: return String(u.name))
	_t._check(names.has("golden_on") and names.has("band_mirror") and names.has("ripple_amp") and names.has("print_depth"),
		"the sand shader parses with the golden uniforms (%d uniforms)" % names.size())
	var mat := PropFactory.beach_sand_material()
	_t._check(float(mat.get_shader_parameter("golden_on")) == (1.0 if BeachGolden.enabled else 0.0),
		"the sand material's golden_on follows BEACH_GOLDEN (%s)" % str(mat.get_shader_parameter("golden_on")))


func _props_shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/beach_props.gdshader")
	var paint := roundi(BeachGolden.A_TOWER_PAINT * 20.0)
	var wood := roundi(BeachGolden.A_TOWER_WOOD * 20.0)
	_t._check(paint == 11 and wood == 12 and src.contains("code == %d || code == %d" % [paint, wood]),
		"the tower's paint / timber codes (%d / %d) are the ones beach_props.gdshader draws" % [paint, wood])
	var used := [BeachLife.A_PLAIN, BeachLife.A_PAINT, BeachLife.A_TOWEL, BeachLife.A_CANVAS, BeachLife.A_NET,
		BeachLife.A_BALL, BeachLife.A_BOARD, BeachLife.A_PATH, BeachLife.A_GLASS, BeachLife.A_TAPE]
	var clash := false
	for a: float in used:
		clash = clash or roundi(a * 20.0) == paint or roundi(a * 20.0) == wood
	_t._check(not clash, "the tower codes are free in BeachLife's A_* table")


func _tower_arrays(on: bool) -> Array:
	var was := BeachGolden.enabled
	BeachGolden.enabled = on
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	BeachLife._tower(st)
	BeachGolden.enabled = was
	return st.commit_to_arrays()


func _tower() -> void:
	var on := _tower_arrays(true)
	var off := _tower_arrays(false)
	var pv: PackedVector3Array = on[Mesh.ARRAY_VERTEX]
	var qv: PackedVector3Array = off[Mesh.ARRAY_VERTEX]
	_t._check(pv.size() > 0 and pv == qv, "the tower has the same %d vertices with the switch on and off" % pv.size())
	var codes_on := {}
	var codes_off := {}
	for c: Color in (on[Mesh.ARRAY_COLOR] as PackedColorArray):
		codes_on[roundi(c.a * 20.0)] = true
	for c: Color in (off[Mesh.ARRAY_COLOR] as PackedColorArray):
		codes_off[roundi(c.a * 20.0)] = true
	_t._check(codes_on.has(11) and codes_on.has(12) and not codes_on.has(0) and codes_on.has(9),
		"switched on, the tower is weathered paint and timber round its glass (codes %s)" % str(codes_on.keys()))
	_t._check(not codes_off.has(11) and not codes_off.has(12) and codes_off.has(0),
		"BEACH_GOLDEN=0 builds the old plain tower (codes %s)" % str(codes_off.keys()))
