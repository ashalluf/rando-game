extends Node3D
## The street performers on their own (Buskers, Busker, BuskWatcher): every act on a strip of
## pavement with its gear, playing, lit by day or at night. Seconds a frame instead of minutes
## for a city still. A scene (the autoloads exist before Pedestrian compiles).
##
##   OUT=/tmp/busk SHOTS="-6,1.6,4:-6,1.0,-3;0,2,9:0,1,-3" xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --audio-driver Dummy --path . --resolution 1280x720 \
##     tools/buskers/busk_shot.tscn
##
## Env: OUT (prefix; <OUT>_<i>.png), SHOTS (cam:look pairs, ";"-separated; T=seconds of play
## before each, TIMES="t0,t1,..." per shot), NIGHT=1, FOV, KINDS (subset of guitar, drums,
## statue, mariachi, break). Layout: the kerb along x at z 0, the road at z > 0; guitar at
## x -9, drums -4.5, statue 0, the mariachis round 5, the breakdancer at 12 with a ring.

const PAVE := 0.25
var _peds: Array = []


func ground_y(_x: float, _z: float) -> float:
	return PAVE


func _take_crowd_room(_r: float = 0.0) -> bool:
	return true


func _ready() -> void:
	var night := OS.get_environment("NIGHT") == "1"
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.68) if not night else Color(0.01, 0.015, 0.03)
	sky_mat.sky_horizon_color = Color(0.7, 0.74, 0.78) if not night else Color(0.05, 0.04, 0.04)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.45) if not night else Color(0.03, 0.03, 0.03)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.18) if not night else Color(0.01, 0.01, 0.01)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.3 if not night else 0.25
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0 if not night else 1.6
	e.glow_enabled = night
	env.environment = e
	add_child(env)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 25.0, 0.0)
	sun.light_energy = 1.3 if not night else 0.03
	sun.shadow_enabled = true
	add_child(sun)
	if night:
		for x: float in [-7.0, 2.0, 11.0]:
			var l := OmniLight3D.new()
			l.position = Vector3(x, 5.5, -0.6)
			l.omni_range = 14.0
			l.light_energy = 3.0
			l.light_color = Color(1.0, 0.82, 0.6)
			add_child(l)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80.0, 1.0, 40.0)
	cs.shape = bs
	cs.position = Vector3(0.0, PAVE - 0.5, 0.0)
	body.add_child(cs)
	add_child(body)
	for i in 2:
		var g := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(80.0, 0.1 if i == 0 else PAVE, 14.0)
		g.mesh = b
		g.position = Vector3(0.0, 0.05 if i == 0 else PAVE * 0.5, 7.0 if i == 0 else -7.0)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.12, 0.125) if i == 0 else Color(0.55, 0.54, 0.52)
		m.roughness = 0.9
		g.material_override = m
		add_child(g)
	var wall := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(80.0, 9.0, 1.0)
	wall.mesh = wb
	wall.position = Vector3(0.0, 4.5, -4.7)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.62, 0.55, 0.47)
	wall.material_override = wm
	add_child(wall)
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	var kinds := OS.get_environment("KINDS").split(",", false)
	var want := func(k: String) -> bool: return kinds.is_empty() or k in kinds
	var yaw := PI
	var out := Vector2(0.0, 1.0)
	if want.call("guitar"):
		_gear(Buskers.case_mesh(), Vector2(-9.0, -2.2), yaw)
		_gear(Buskers.amp_mesh(), Vector2(-8.25, -3.2), yaw + 0.35)
		_busker(Buskers.Kind.GUITAR, 0, Vector2(-9.0, -3.15), yaw, 11)
	if want.call("drums"):
		_gear(Buskers.drums_mesh(), Vector2(-4.5, -3.15), yaw)
		_busker(Buskers.Kind.DRUMS, 0, Vector2(-4.5, -3.15), yaw, 23)
	if want.call("statue"):
		_gear(Buskers.plinth_mesh(), Vector2(0.0, -3.15), yaw)
		_busker(Buskers.Kind.STATUE, 0, Vector2(0.0, -3.15), yaw, 31)
	if want.call("mariachi"):
		_gear(Buskers.case_mesh(), Vector2(5.0, -2.2), yaw)
		for i in 3:
			_busker(Buskers.Kind.MARIACHI, i, Vector2(5.0 + (float(i) - 1.0) * 1.15, -3.15 - absf(float(i) - 1.0) * 0.25), yaw - (float(i) - 1.0) * 0.18, 41)
	if want.call("break"):
		var at := Vector2(12.0, -2.4)
		_gear(Buskers.break_mesh(), at, PI)
		var b := _busker(Buskers.Kind.BREAK, 0, at, PI, 53)
		print("BUSK_BREAK the freeze is at %.1f s (+18 n)" % (13.5 - float(b._hash % 7) if b._hash % 7 < 13 else 0.0))
		for i in 5:
			var ang := PI * 0.5 + (float(i) - 2.0) * 0.62
			var d := Vector2(0.0, 1.0).rotated(ang - PI * 0.5)
			var w := at + d * 3.0
			var to := at - w
			var wt := BuskWatcher.new()
			wt.setup_watch(Rect2(-40, -14, 80, 14), hash([53, "w", i]), w, atan2(-to.x, -to.y))
			wt.performer = b
			wt.position = Vector3(w.x, PAVE + 0.05, w.y)
			add_child(wt)
			_peds.append(wt)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 45.0
	add_child(cam)
	cam.make_current()
	var shots := OS.get_environment("SHOTS")
	if shots == "":
		shots = "-2,1.7,7:-2,1.1,-3"
	var times := OS.get_environment("TIMES").split(",", false)
	var prefix := OS.get_environment("OUT")
	if prefix == "":
		prefix = "busk"
	var list := shots.split(";")
	var played := 0.0
	for i in list.size():
		var pair := list[i].split(":")
		var c := _vec(pair[0])
		player.global_position = c
		cam.look_at_from_position(c, _vec(pair[1]), Vector3.UP)
		var t := float(times[i]) if i < times.size() else (6.0 if i == 0 else 0.0)
		while played < t:
			await get_tree().physics_frame
			played += 1.0 / 60.0
		for k in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, i])
		print("BUSK_SHOT %s_%d.png at %.1f s" % [prefix, i, played])
		for p in _peds:
			if p is Busker and (p as Busker).kind == Buskers.Kind.BREAK:
				print("BUSK_BREAK t %.2f phase %.2f clip %s" % [p._t, p._break_phase(), p._life_clip])
	get_tree().quit()


func _gear(mesh: Mesh, at: Vector2, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, PAVE, at.y))
	add_child(mi)


func _busker(kind: int, role: int, at: Vector2, yaw: float, base: int) -> Busker:
	var b := Busker.new()
	if OS.get_environment("NOPEOPLE") == "1":
		return b
	var s := Buskers.seed_for(hash([base, role]), Buskers.RIGS[kind])
	b.setup_busker(Rect2(-40, -14, 80, 14), s, at, yaw, kind, role)
	b.position = Vector3(at.x, PAVE + 0.05, at.y)
	add_child(b)
	_peds.append(b)
	return b


static func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
