extends "res://tools/sky/sky_shot.gd"
## The offshore island in seconds: sky_shot.gd (the city's Environment, DayNight and sun, no
## city) with the camera at a true-world eye and a sea-coloured plane round it (20 km, so the
## sky draws the band to the horizon as the game's 14 km horizon plane leaves it).
##
##   EYE=-900,2,0 YAW=-115 PITCH=1 FOV=40 HOUR=17.8 OUT=a.png xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/offshore_island/island_shot.gd --resolution 1280x720
##
## Env as sky_shot.gd plus EYE=x,y,z (true world metres), AMOUNT / HAZE / LIGHTS (island
## uniforms held), SEA=r,g,b the plane's colour. Without EYE the camera stands on the beach.


func _initialize() -> void:
	super._initialize()
	var top := root.get_node("SkyShot")
	var eye := Vector3(-900, 2, 0)
	if _env("EYE", "") != "":
		var p := _env("EYE", "").split(",")
		eye = Vector3(float(p[0]), float(p[1]), float(p[2]))
	for c in top.get_children():
		if c is Camera3D:
			c.position = eye
		elif c is MeshInstance3D:
			c.position = Vector3(eye.x, 0.0, eye.z)
			(c.mesh as PlaneMesh).size = Vector2(20000, 20000)
			var sea := _env("SEA", "0.05,0.09,0.12").split(",")
			(c.material_override as StandardMaterial3D).albedo_color = Color(float(sea[0]), float(sea[1]), float(sea[2]))
			(c.material_override as StandardMaterial3D).roughness = 0.35


func _hold() -> void:
	super._hold()
	for k in ["AMOUNT", "HAZE", "LIGHTS"]:
		if _env(k, "") != "":
			var name := {"AMOUNT": "island_amount", "HAZE": "island_haze_km", "LIGHTS": "island_lights"}[k] as String
			_sky.set_shader_parameter(name, float(_env(k, "0")))
