extends Node3D
## The hero in the city's own sky, sun, DayNight and Weather on a patch of wet street: a small
## scene that loads in seconds on the web build too, so the browser and the native Compatibility
## renderer can be compared on the SAME frame (docs/HANDOFF.md "The hero in the rain on the web").
##
## Native (opengl3, the Compatibility renderer the web uses):
##   OUT=/tmp/hr.png HOUR=13 WEATHER=rain xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     res://tools/web_hero_rain/hero_rain.tscn --resolution 960x540
## Web: export with this scene as the main scene (tools/web_hero_rain/export_web.sh), then
##   QS='?hour=13&weather=rain' node tools/webshot/webshot.js
## Knobs (env natively, query string on the web): hour, weather (clear, overcast, rain, storm,
## marine, santa_ana), wetness (a held road_wetness), yaw (degrees round the hero), dist (m),
## frames (before the shot, native), quit (native: save OUT and quit; default 1).
## Prints HERO_RGB: the mean colour of the hero's top in the frame (the pixels in his torso box).

var plan: CityPlan
var world_seed: int = 0
var _q := {}


func _arg(k: String, d: String) -> String:
	if _q.has(k):
		return _q[k]
	var v := OS.get_environment(k.to_upper())
	return v if v != "" else d


func _ready() -> void:
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String:
			for part in (search as String).trim_prefix("?").split("&", false):
				var kv := part.split("=")
				_q[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	world_seed = city.world_seed
	plan = CityPlan.new()
	plan.seed = city.world_seed
	plan.macro = MacroMap.new()
	plan.macro.seed = city.world_seed
	plan.macro.setup()
	for keep in ["WorldEnvironment", "Sun", "DayNight", "Weather"]:
		var n: Node = city.get_node_or_null(keep)
		if n:
			city.remove_child(n)
			n.owner = null
			add_child(n)
	city.free()
	# A stand-in player (rain follows "player") and a wet street round him.
	var stand := Node3D.new()
	stand.add_to_group("player")
	add_child(stand)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	ground.material_override = PropFactory.road("asphalt", 4.0, Color(1, 1, 1), 1)
	add_child(ground)
	var body := Avatar.new()
	body.name = "Avatar"
	add_child(body)
	body.load_model("res://assets/models/hero.glb", -1, Color(0, 0, 0, 0))
	var dn: Node = get_node_or_null("DayNight")
	if dn:
		dn.set("hour", _arg("hour", "13").to_float())
		dn.call("_apply")
	var wx: Node = get_node_or_null("Weather")
	if wx and wx.has_method("force_state"):
		var names := {"clear": 0, "overcast": 1, "rain": 2, "storm": 3, "marine": 4, "santa_ana": 5}
		wx.call("force_state", int(names.get(_arg("weather", "rain"), 2)))
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.make_current()
	var yaw := deg_to_rad(_arg("yaw", "0").to_float())
	var dist := _arg("dist", "3.2").to_float()
	# The player's visual faces -Z; yaw 0 looks at his back, as the chase camera does.
	var eye := Vector3(sin(yaw) * dist, 1.55, cos(yaw) * dist)
	cam.look_at_from_position(eye, Vector3(0, 1.15, 0))
	# webq=1: what Quality._apply_web() sets in the browser, replayed natively.
	if _arg("webq", "0") == "1" or OS.has_feature("web"):
		var we := (get_node("WorldEnvironment") as WorldEnvironment).environment
		(we.sky.sky_material as ShaderMaterial).set_shader_parameter("cloud_detail", 0.0)
		RenderingServer.global_shader_parameter_set("ground_detail", 0.0)
	var wet := _arg("wetness", "")
	for i in int(_arg("frames", "40")):
		if wet != "":
			RenderingServer.global_shader_parameter_set("road_wetness", wet.to_float())
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	print("HERO_RGB ", _torso_mean(img, cam))
	if OS.has_feature("web") or _arg("quit", "1") != "1":
		return
	img.save_png(_arg("out", "hero_rain.png"))
	print("saved ", _arg("out", "hero_rain.png"))
	get_tree().quit()


## The mean colour of the pixels in a box over the hero's back (chest height), 0..255.
func _torso_mean(img: Image, cam: Camera3D) -> String:
	var a := cam.unproject_position(Vector3(-0.12, 1.35, 0))
	var b := cam.unproject_position(Vector3(0.12, 1.05, 0))
	var s := Vector3.ZERO
	var n := 0
	for y in range(int(min(a.y, b.y)), int(max(a.y, b.y))):
		for x in range(int(min(a.x, b.x)), int(max(a.x, b.x))):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c := img.get_pixel(x, y)
			s += Vector3(c.r, c.g, c.b)
			n += 1
	if n == 0:
		return "none"
	s = s / n * 255.0
	return "%d %d %d" % [roundi(s.x), roundi(s.y), roundi(s.z)]
