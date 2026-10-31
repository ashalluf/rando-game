extends RefCounted
## The golden-aerial review (docs/HANDOFF.md "The golden aerial", GoldenAerial) for
## tests/smoke_test.gd: what the golden_aerial reference camera was tuned to.
## - The horizon plane's painted light follows DayNight's sun: its colour, its energy as a share of
##   noon's (unchanged at noon), and a shaded-face fill toward the zenith at golden hour only.
## - The sky's mid deck is cloudlets (mid_cells), and the shader still has the old path for the A/B.
## - The far antennas are dimmed by the share of their drawn width they cover.
## - HallDress puts a roof, rooftop units, pilasters and a plinth on a hall, and nothing when off.
## - The lens fringe is halved.
## Stages the city's DayNight hour and puts it back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_t._check(GoldenAerial.enabled, "golden aerial: on by default")
	_pure()
	_halls()
	_live(city)


func _pure() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/macro_ground.gdshader")
	var top := Color(0.08, 0.28, 0.76)
	var hor := Color(0.66, 0.75, 0.88)
	# Noon: the light is noon's, no zenith fill.
	GoldenAerial.ground_light(mat, Color(1.0, 0.94, 0.82), 1.3, 1.3, top, hor, 0.0, 0.0)
	_t._check(is_equal_approx(float(mat.get_shader_parameter("sun_gain")), 1.0) and float(mat.get_shader_parameter("fill_top_mix")) == 0.0,
		"golden aerial: at noon the far ground's painted light is as it was")
	# Golden hour: half the energy, an orange sun, the fill toward the zenith's blue.
	GoldenAerial.ground_light(mat, Color(1.0, 0.6, 0.35), 0.65, 1.3, top, hor, 1.0, 0.0)
	var gain := float(mat.get_shader_parameter("sun_gain"))
	var sc: Color = mat.get_shader_parameter("sun_color")
	var ft: Vector3 = mat.get_shader_parameter("fill_top")
	_t._check(absf(gain - 0.5) < 0.01 and sc.b < sc.r * 0.5,
		"golden aerial: at golden hour the far ground takes the low sun's energy (%.2f) and colour" % gain)
	_t._check(float(mat.get_shader_parameter("fill_top_mix")) > 0.5 and ft.z > ft.x * 2.0,
		"golden aerial: the far ground's shaded faces lean to the zenith's blue (%s)" % ft)
	# Night: the plane dims itself; the painted sun keeps its day numbers.
	GoldenAerial.ground_light(mat, Color(0.7, 0.76, 0.95), 0.1, 1.3, top, hor, 0.0, 1.0)
	_t._check(is_equal_approx(float(mat.get_shader_parameter("sun_gain")), 1.0),
		"golden aerial: at night the painted sun is left to the plane's own dimming")
	var sky_src: String = (load("res://shaders/sky.gdshader") as Shader).code
	_t._check(sky_src.contains("uniform float mid_cells") and sky_src.contains("if (mid_cells > 0.0)"),
		"golden aerial: the sky's mid deck has its cloudlets and the old field behind the switch")
	var lod := PropFactory.building_lod_material(true)
	_t._check(is_equal_approx(float(lod.get_shader_parameter("mast_cover_dim")), GoldenAerial.MAST_DIM),
		"golden aerial: the far city's antennas are dimmed by their coverage")
	_t._check(GoldenAerial.FRINGE_GAIN > 0.0 and GoldenAerial.FRINGE_GAIN < 1.0,
		"golden aerial: the lens fringe is reduced")


func _halls() -> void:
	var hall := Rect2(Vector2(0.0, 0.0), Vector2(160.0, 90.0))
	var a := LandmarkGeo.new()
	a.use("white", LandmarkMats.plain("t_white", Color.WHITE))
	HallDress.dress(a, hall, 0.0, 19.0, [20.0, 45.0, 70.0], "white", true)
	_t._check(a.triangles > 400, "golden aerial: a hall gets its roof, units and pilasters (%d triangles)" % a.triangles)
	GoldenAerial.enabled = false
	var b := LandmarkGeo.new()
	b.use("white", LandmarkMats.plain("t_white", Color.WHITE))
	HallDress.dress(b, hall, 0.0, 19.0, [20.0, 45.0, 70.0], "white", true)
	GoldenAerial.enabled = true
	_t._check(b.triangles == 0, "golden aerial: GOLDEN_AERIAL=0 dresses no hall")


func _live(city: Node3D) -> void:
	var day: Node = city.get_node_or_null("DayNight")
	var mat: ShaderMaterial = city.get("_ground_material")
	_t._check(day != null and mat != null, "golden aerial: the city has a DayNight and a ground material")
	if day == null or mat == null:
		return
	var held: float = day.get("hour")
	var held_w: float = day.get("weather_darken")
	day.set("weather_darken", 0.0)
	day.set("hour", 12.5)
	day.call("_apply")
	var noon_gain := float(mat.get_shader_parameter("sun_gain"))
	var noon_fill := float(mat.get_shader_parameter("fill_top_mix"))
	day.set("hour", 17.2)
	day.call("_apply")
	var gold_gain := float(mat.get_shader_parameter("sun_gain"))
	var gold_fill := float(mat.get_shader_parameter("fill_top_mix"))
	var sc: Color = mat.get_shader_parameter("sun_color")
	_t._check(noon_gain > 0.95 and noon_fill < 0.01,
		"golden aerial: live, the noon far ground is unchanged (gain %.2f, fill %.2f)" % [noon_gain, noon_fill])
	_t._check(gold_gain < 0.9 and gold_fill > 0.2 and sc.b < sc.r * 0.8,
		"golden aerial: live, at 17:12 the far ground takes the low warm sun (gain %.2f, fill %.2f, sun %s)" % [gold_gain, gold_fill, sc])
	var sky := day.get("_sky") as ShaderMaterial
	_t._check(sky != null and is_equal_approx(float(sky.get_shader_parameter("mid_cells")), 1.0),
		"golden aerial: live, the sky draws its mid deck as cloudlets")
	day.set("hour", held)
	day.set("weather_darken", held_w)
	day.call("_apply")
