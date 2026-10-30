extends Node
## The ocean traffic's vessels on their own (VesselMesh, Vessel, AnchoredShip) on a patch of the
## real ocean shader, under way with their wakes, lit with the city's daylight numbers. Seconds a
## frame instead of minutes for a city still, so the look can be iterated:
##
##   OUT=v.png CAM=-60,12,90 LOOK=0,3,0 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s \
##     "-screen 0 1280x720x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . tools/ocean_traffic/vessel_shot.tscn --resolution 1280x720
## (a scene, so the autoloads exist before Vessel compiles)
##
## Env: OUT (png), CAM / LOOK (x,y,z), FOV, HOUR (the sun from the hour; 20+ is night: lamps on),
## SCENE=lineup (default: every kind abreast, under way north, with wakes) | sail (four sloops on
## both tacks, heeled) | port (tugs, the pilot boat and a ship at anchor) | ferry, WAVE (the
## wave_scale global), SETTLE (seconds driven before the shot, default 20), LOD=0|1|2 forces a level.
var _vessels: Array = []
var _ships: Array = []
var _ot: OceanTraffic


func _ready() -> void:
	var stage := Node3D.new()
	add_child(stage)
	var hour := float(OS.get_environment("HOUR")) if OS.get_environment("HOUR") != "" else 15.0
	var night := hour >= 19.8 or hour < 5.5
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.68) if not night else Color(0.01, 0.015, 0.03)
	sky_mat.sky_horizon_color = Color(0.7, 0.74, 0.78) if not night else Color(0.04, 0.05, 0.08)
	sky_mat.ground_horizon_color = Color(0.5, 0.55, 0.6) if not night else Color(0.03, 0.04, 0.05)
	sky_mat.ground_bottom_color = Color(0.2, 0.25, 0.3) if not night else Color(0.01, 0.01, 0.02)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25 if not night else 1.6
	e.tonemap_white = 5.0
	e.glow_enabled = true
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-clampf(90.0 - absf(hour - 12.5) * 11.0, 4.0, 80.0), -60.0, 0.0)
	sun.light_energy = 1.3 if not night else 0.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	stage.add_child(sun)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("sky_tint", Color(0.55, 0.66, 0.78, 1.0) if not night else Color(0.03, 0.04, 0.07, 1.0))
	RenderingServer.global_shader_parameter_set("sun_direction", -sun.global_transform.basis.z if sun.is_inside_tree() else Vector3(0.3, 0.6, 0.5))
	if OS.get_environment("WAVE") != "":
		RenderingServer.global_shader_parameter_set("wave_scale", float(OS.get_environment("WAVE")))
	# A patch of the open sea on the real ocean shader (far from any coast: no surf).
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2400.0, 2400.0)
	plane.subdivide_width = 400
	plane.subdivide_depth = 400
	sea.mesh = plane
	sea.material_override = PropFactory.ocean_material()
	sea.position = Vector3(0.0, 0.15, 0.0)
	stage.add_child(sea)
	var mat := PropFactory.ocean_material()
	mat.set_shader_parameter("coast_base_x", 50000.0)
	mat.set_shader_parameter("coast_wobble", 0.0)
	mat.set_shader_parameter("peninsula_center", Vector2(90000.0, 90000.0))
	_ot = OceanTraffic.new()
	_ot.name = "OceanTraffic"
	stage.add_child(_ot)
	_ot.set_physics_process(false)
	var scene := OS.get_environment("SCENE")
	match scene:
		"sail":
			_sail_scene(stage)
		"port":
			_port_scene(stage)
		"ferry":
			_add(stage, VesselMesh.Kind.FERRY, 0, 42.0, Color(0.94, 0.95, 0.95), Vector2(0.0, 0.0), Vector2(0.0, -1.0), 14.0)
		_:
			var kinds := [[VesselMesh.Kind.SAIL, 12.0, 0], [VesselMesh.Kind.MOTOR, 20.0, 0], [VesselMesh.Kind.FISHER, 13.0, 1], [VesselMesh.Kind.RUNABOUT, 7.0, 1], [VesselMesh.Kind.PILOT, 16.0, 0], [VesselMesh.Kind.TUG, 28.0, 0], [VesselMesh.Kind.FERRY, 42.0, 0]]
			var x := -90.0
			for k: Array in kinds:
				var paint := Color(0.94, 0.94, 0.92)
				if k[0] == VesselMesh.Kind.TUG:
					paint = OceanTraffic.TUG_PAINTS[0]
				elif k[0] == VesselMesh.Kind.PILOT:
					paint = Color(0.05, 0.05, 0.06)
				var sp := 3.0 if k[0] == VesselMesh.Kind.SAIL else (5.0 if k[0] == VesselMesh.Kind.TUG else 9.0)
				_add(stage, k[0], k[2], k[1], paint, Vector2(x, 0.0), Vector2(0.0, -1.0), sp)
				x += 30.0
	var force_lod := int(OS.get_environment("LOD")) if OS.get_environment("LOD") != "" else -1
	if force_lod >= 0:
		for v in _vessels:
			for n in (v as Node).find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				if mi.visibility_range_end > 0.0 or mi.visibility_range_begin > 0.0:
					var lv := int(String(mi.name).right(1)) if String(mi.name).begins_with("Hull") else -1
					mi.visibility_range_begin = 0.0
					mi.visibility_range_end = 0.0
					if lv >= 0 and lv != force_lod:
						mi.visible = false
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	cam.far = 4000.0
	stage.add_child(cam)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), Vector3(-70.0, 14.0, 110.0)), _vec(OS.get_environment("LOOK"), Vector3(0.0, 4.0, 0.0)), Vector3.UP)
	cam.make_current()
	# Drive them a while so the sails sheet, the boats turn onto their courses and wakes stretch.
	var settle := float(OS.get_environment("SETTLE")) if OS.get_environment("SETTLE") != "" else 20.0
	var t := 0.0
	while t < settle:
		for v in _vessels:
			(v as Vessel).drive(0.1)
		for s in _ships:
			(s as AnchoredShip).drive(0.1)
		t += 0.1
	for v in _vessels:
		print("vessel ", (v as Vessel).tag, " kind=", (v as Vessel).kind, " at=", (v as Vessel).world_pos, " speed=%.2f heel=%.2f boom=%.2f" % [(v as Vessel).speed, (v as Vessel).heel, (v as Vessel).boom])
	for i in 8:
		_ot.push_wakes()
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "vessel_shot.png")
	get_tree().quit()


func _add(stage: Node3D, kind: int, variant: int, length: float, paint: Color, at: Vector2, dir: Vector2, sp: float) -> Vessel:
	var v := Vessel.new()
	v.setup(kind, variant, length, paint, _vessels.size() % 6, 777 + _vessels.size())
	v.tag = "shot_%d" % _vessels.size()
	if kind == VesselMesh.Kind.SAIL:
		v.sail(at, at, _ot.wind, dir)
		v.home_reach = 1e9
	else:
		var loop := PackedVector2Array([at - dir * 3000.0, at + dir * 3000.0, at + dir * 3000.0 + Vector2(-dir.y, dir.x) * 400.0, at - dir * 3000.0 + Vector2(-dir.y, dir.x) * 400.0])
		v.follow(loop, sp, 3000.0)
		v.speed = sp
	_ot.add_child(v)
	_ot.vessels.append(v)
	v.apply_pose()
	_vessels.append(v)
	return v


func _sail_scene(stage: Node3D) -> void:
	var w := _ot.wind
	var up := -w
	_add(stage, VesselMesh.Kind.SAIL, 0, 12.0, Color(0.94, 0.94, 0.92), Vector2(0.0, 0.0), up.rotated(0.9), 3.0)
	_add(stage, VesselMesh.Kind.SAIL, 1, 11.0, Color(0.12, 0.16, 0.3), Vector2(60.0, -70.0), up.rotated(-0.9), 3.0)
	_add(stage, VesselMesh.Kind.SAIL, 0, 13.5, Color(0.92, 0.92, 0.9), Vector2(-80.0, -140.0), up.rotated(1.6), 3.0)
	_add(stage, VesselMesh.Kind.SAIL, 1, 10.0, Color(0.55, 0.12, 0.1), Vector2(110.0, -220.0), w, 3.0)


func _port_scene(stage: Node3D) -> void:
	var s := AnchoredShip.new()
	s.setup(Vector2(0.0, -260.0), Vector2(-1.0, 0.0), 9100)
	_ot.add_child(s)
	s.drive(0.0)
	_ships.append(s)
	_add(stage, VesselMesh.Kind.TUG, 0, 28.0, OceanTraffic.TUG_PAINTS[0], Vector2(-40.0, -40.0), Vector2(0.0, -1.0), 4.0)
	_add(stage, VesselMesh.Kind.TUG, 1, 26.0, OceanTraffic.TUG_PAINTS[1], Vector2(30.0, -120.0), Vector2(-1.0, -0.3).normalized(), 3.0)
	_add(stage, VesselMesh.Kind.PILOT, 0, 16.0, Color(0.05, 0.05, 0.06), Vector2(60.0, 10.0), Vector2(0.3, -1.0).normalized(), 10.0)


static func _vec(s: String, fallback: Vector3) -> Vector3:
	var p := s.split(",")
	if p.size() != 3:
		return fallback
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
