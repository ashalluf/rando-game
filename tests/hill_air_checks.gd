extends RefCounted
## The mountains from the air (HANDOFF 9at): checks for tests/smoke_test.gd that hold the two
## fixes of 2026-10-04 and the shared ground. Loaded at run time, so it compiles after the
## autoloads and can name Skyline and CityChunk. Source reads and bookkeeping only - under
## --headless no shader compiles and no pixel can be read, so these guard the contracts that made
## the colours right, not the pixels themselves.
##   * Colour space: every hill ground shader works in linear on both renderers
##     (shaders/color_space.gdshaderinc) and none of the horizon plane's linear colours is a
##     `source_color` uniform again (Forward+ decoded them twice: the far mountains near-black).
##   * One ground: the horizon plane reads the splat the near tiles paint from, and keeps no
##     copies of its colours or rules to drift apart from it.
##   * No far chaparral mounds: the far tier plants only the oaks in the hollows (the mounds drew
##     as dark dashes across every range from the air).

## The plane's `source_color` vec3 uniforms that ARE sRGB-authored (set from script as colours, or
## written as display colours): everything else in it is a linear albedo and must be plain.
const PLANE_SRGB := ["haze_color", "smog_color", "sun_color", "bounce_color", "city_light_color"]
## The hill ground shaders that do arithmetic on colours, which must work in linear on both.
const LINEAR_SHADERS := ["res://shaders/macro_ground.gdshader", "res://shaders/terrain.gdshader",
	"res://shaders/hill_shells.gdshader", "res://shaders/far_canopy.gdshader"]

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_colour_space()
	_one_ground()
	var plan: CityPlan = city.get("plan")
	if plan and plan.macro:
		_no_far_mounds(plan, city)


func _colour_space() -> void:
	var inc := "#include \"res://shaders/color_space.gdshaderinc\""
	var missing: Array[String] = []
	for path: String in LINEAR_SHADERS:
		var src := FileAccess.get_file_as_string(path)
		if not src.contains(inc) or not src.contains("cs_out("):
			missing.append(path.get_file())
	_t._check(missing.is_empty(), "the hill ground shaders work in linear on both renderers (%s)" % (", ".join(missing) + " missing" if missing else "all four"))
	var plane := FileAccess.get_file_as_string("res://shaders/macro_ground.gdshader")
	var re := RegEx.create_from_string("uniform\\s+vec[34]\\s+(\\w+)\\s*:\\s*source_color")
	var wrong: Array[String] = []
	for m in re.search_all(plane):
		if not PLANE_SRGB.has(m.get_string(1)):
			wrong.append(m.get_string(1))
	_t._check(wrong.is_empty(), "the horizon plane decodes none of its linear colours from sRGB (%s)" % (", ".join(wrong) if wrong else "only %d sRGB-authored ones" % PLANE_SRGB.size()))
	var splat := FileAccess.get_file_as_string("res://shaders/hill_splat.gdshaderinc")
	var splat_srgb := re.search_all(splat).size()
	var probe := FileAccess.get_file_as_string("res://shaders/color_space.gdshaderinc")
	_t._check(splat_srgb == 0 and probe.contains("#if CURRENT_RENDERER == RENDERER_COMPATIBILITY"),
		"the splat's colours are plain linear uniforms and the colour space is told by renderer (%d source_color in the splat)" % splat_srgb)
	# The precedent: far boxes decode their instance colour where the renderer decodes the near
	# buildings' (it was declared and never set, CLAUDE.md).
	var lod_mat := PropFactory.building_lod_material()
	_t._check(lod_mat.get_shader_parameter("instance_color_is_srgb") == PropFactory.has_reflections(),
		"the far boxes decode their instance colour exactly where the renderer decodes the near ones")


func _one_ground() -> void:
	var plane := FileAccess.get_file_as_string("res://shaders/macro_ground.gdshader")
	var splat := FileAccess.get_file_as_string("res://shaders/hill_splat.gdshaderinc")
	var re := RegEx.create_from_string("uniform\\s+\\w+\\s+(\\w+)")
	var splat_names := {}
	for m in re.search_all(splat):
		splat_names[m.get_string(1)] = true
	var copies: Array[String] = []
	for m in re.search_all(plane):
		if splat_names.has(m.get_string(1)):
			copies.append(m.get_string(1))
	var uses := ["hill_stand_threshold(", "hill_stand(", "hill_rocky(", "hill_bare(", "straw_color", "chaparral_color", "dirt_color", "rock_color"]
	var unused: Array[String] = []
	for u: String in uses:
		if not plane.contains(u):
			unused.append(u)
	_t._check(plane.contains("#include \"res://shaders/hill_splat.gdshaderinc\"") and copies.is_empty() and unused.is_empty(),
		"the horizon plane paints the near tiles' own field, with no copies of it (%s)" % (", ".join(PackedStringArray(copies + unused)) if copies or unused else "%d shared uniforms" % splat_names.size()))


## Far hill blocks on the front range: every planting the far tier puts there is an oak, none a
## low brush mound.
func _no_far_mounds(plan: CityPlan, city: Node3D) -> void:
	var sky := Skyline.new()
	sky.setup(plan, city.call("chunk_style"))
	var oaks := 0
	var low := 0
	var blocks := 0
	for x: float in [-600.0, -150.0, 300.0, 750.0, 1200.0]:
		for z: float in [-1150.0, -1350.0]:
			var k := plan.block_index_at(Vector2(x, z))
			var rect: Rect2 = plan.block(k.x, k.y).rect
			if plan.zone_at(rect.get_center()) != MacroMap.Zone.HILLS:
				continue
			blocks += 1
			sky._work = {"veg": [], "veg_colors": [], "veg_custom": [], "houses": [], "house_colors": []}
			sky._add_hills(rect, plan.macro)
			for xf: Transform3D in sky._work.veg:
				# The clump's height is its basis' Y scale (a unit blob).
				if xf.basis.y.length() < Skyline.HILL_OAK_HEIGHT.x - 0.01:
					low += 1
				else:
					oaks += 1
	sky.free()
	_t._check(blocks >= 4 and low == 0, "the far hills plant no brush mounds, only the hollows' oaks (%d oaks, %d low clumps on %d blocks)" % [oaks, low, blocks])
