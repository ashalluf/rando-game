extends SceneTree
## The utility-pole kit alone, in seconds: a row of three poles on a pavement strip with their
## heads, a transformer, a street light, a riser, spans between them (primaries, secondary, comm
## bundles with a splice case and a coil), a guy at the end and a house wall with a meter, a mast
## and a drop. Lit by a sun and a sky like the city's (AgX).
##
##   OUT=pole.png CAM=x,y,z LOOK=x,y,z FOV=50 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/utility_poles/pole_shot.gd --resolution 1280x720
## NIGHT=1 lamp_factor 1 and a dark sky. SHOTS="cx,cy,cz>lx,ly,lz@fov;..." takes several (OUT_n).
var _frames := 0
var _shots: Array = []
var _cam: Camera3D
## Loaded by path: naming them as types compiles them before the autoloads exist.
var UP: GDScript
var SD: GDScript


func _initialize() -> void:
	UP = load("res://scripts/world/utility_poles.gd")
	SD = load("res://scripts/world/street_detail.gd")
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var night := OS.get_environment("NIGHT") == "1"
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("road_wetness", 0.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	if night:
		sm.sky_top_color = Color(0.01, 0.015, 0.03)
		sm.sky_horizon_color = Color(0.05, 0.04, 0.04)
		sm.ground_horizon_color = Color(0.03, 0.03, 0.03)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 0.05 if night else 1.4
	sun.shadow_enabled = true
	root3.add_child(sun)
	# The pavement and a road.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.32, 0.32, 0.31)
	ground.material_override = gmat
	root3.add_child(ground)
	# A wall behind the line (x < -6), facing +x.
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 4.0, 12.0)
	wall.mesh = bm
	wall.position = Vector3(-7.0, 2.0, 15.0)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.75, 0.68, 0.58)
	wall.material_override = wmat
	root3.add_child(wall)
	# Three poles along z at x = 0, the street toward +x.
	var street := Vector3(1, 0, 0)
	var zl := street.cross(Vector3.UP)
	var basis: Basis = UP.pole_basis(street, zl)
	var mm := {}
	var pins: Array[Vector3] = []
	for i in 3:
		var pin := Vector3(0.0, 0.0, float(i) * 30.0)
		pins.append(pin)
		var foot: Vector3 = UP.foot_of(pin, zl)
		_add(root3, UP.shaft_mesh(), Transform3D(basis, foot + Vector3(0, SD.POLE_HEIGHT * 0.5, 0)))
		_add(root3, UP.head_mesh(), Transform3D(basis, foot))
		if i == 1:
			_add(root3, UP.transformer_mesh(), Transform3D(basis, foot))
			_add(root3, UP.riser_mesh(), Transform3D(basis, foot))
		if i == 0:
			_add(root3, UP.light_mesh(), Transform3D(basis, foot))
	# The wires, as the chunk builds them.
	var wires: Array = []
	var sag: float = SD.POWER_SAG
	for i in 2:
		var a: Vector3 = pins[i]
		var b: Vector3 = pins[i + 1]
		for k in 3:
			var o: Vector3 = street * float(k - 1) * UP.PIN_SPREAD
			wires.append(_wire(a + o + Vector3(0, SD.POWER_ARM_HEIGHT + 0.2, 0), b + o + Vector3(0, SD.POWER_ARM_HEIGHT + 0.2, 0), sag, 0, UP.R_PRIMARY))
		var sa: Vector3 = UP.foot_of(a, zl) + zl * (UP.POLE_FACE + 0.06) + Vector3(0, UP.SECONDARY_HEIGHT, 0)
		var sb: Vector3 = UP.foot_of(b, zl) + zl * (UP.POLE_FACE + 0.06) + Vector3(0, UP.SECONDARY_HEIGHT, 0)
		wires.append(_wire(sa, sb, UP.SECONDARY_SAG, 1, UP.R_SECONDARY))
		for c in 2:
			var ca: Vector3 = UP.foot_of(a, zl) + street * UP.COMM_OUT + Vector3(0, UP.COMM_HEIGHTS[c], 0)
			var cb: Vector3 = UP.foot_of(b, zl) + street * UP.COMM_OUT + Vector3(0, UP.COMM_HEIGHTS[c], 0)
			wires.append(_wire(ca, cb, UP.COMM_SAGS[c], 2, UP.R_COMM[c]))
	# A drop from the middle pole's spool to the wall's mast, and a guy at the far end.
	var mid_spool: Vector3 = UP.foot_of(pins[1], zl) + zl * (UP.POLE_FACE + 0.06) + Vector3(0, UP.SECONDARY_HEIGHT, 0)
	var mast_top := Vector3(-6.78, 4.95, 15.0)
	wires.append(_wire(mid_spool, mast_top - Vector3(0, 0.22, 0), 0.5, 3, UP.R_DROP))
	var face := Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(1, 0, 0))
	_add(root3, UP.meter_mesh(), Transform3D(face, Vector3(-6.78, 1.55, 15.0)))
	_add(root3, UP.mast_mesh(), Transform3D(face.scaled_local(Vector3(1, 4.95 - 1.85, 1)), Vector3(-6.78, 1.85, 15.0)))
	var tp := Vector3(mid_spool.x - mast_top.x, 0, mid_spool.z - mast_top.z).normalized()
	_add(root3, UP.weatherhead_mesh(), Transform3D(Basis(Vector3.UP.cross(tp).normalized(), Vector3.UP, tp), mast_top))
	var foot2: Vector3 = UP.foot_of(pins[2], zl)
	var gtop: Vector3 = foot2 + Vector3(0, UP.GUY_HEIGHT, 0) + Vector3(0, 0, 0.13)
	var anchor: Vector3 = foot2 + Vector3(0, 0.05, UP.GUY_LEAD)
	wires.append(_wire(gtop, anchor, 0.0, 4, UP.R_GUY))
	var gd: Vector3 = (gtop - anchor).normalized()
	_add(root3, UP.guard_mesh(), _along(anchor + gd * (UP.GUARD_LENGTH * 0.5 + 0.12), gd))
	_add(root3, UP.anchor_mesh(), _along(anchor, gd))
	var la: Vector3 = wires[4][0][0]
	var lb: Vector3 = wires[4][0][wires[4][0].size() - 1]
	var sp: Vector3 = UP.catenary_point(la, lb, UP.COMM_SAGS[0], 0.09)
	var sd: Vector3 = (UP.catenary_point(la, lb, UP.COMM_SAGS[0], 0.1) - sp).normalized()
	_add(root3, UP.splice_mesh(), _along(sp - Vector3(0, 0.09, 0), sd))
	var wmesh: ArrayMesh = UP.ribbon_mesh(wires)
	var wmi := MeshInstance3D.new()
	wmi.mesh = wmesh
	wmi.material_override = UP.wire_material()
	if OS.get_environment("WIRE_DEBUG") == "1":
		var dm: ShaderMaterial = (UP.wire_material() as ShaderMaterial).duplicate()
		dm.set_shader_parameter("debug_solid", 1.0)
		wmi.material_override = dm
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3.add_child(wmi)
	_cam = Camera3D.new()
	_cam.far = 2000.0
	root3.add_child(_cam)
	var shots := OS.get_environment("SHOTS")
	if shots == "":
		var c := _vec(OS.get_environment("CAM"), Vector3(9, 6, -8))
		var l := _vec(OS.get_environment("LOOK"), Vector3(0, 7, 12))
		var fov := float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 55.0
		_shots.append([c, l, fov])
	else:
		for s in shots.split(";"):
			var parts := s.split("@")
			var cl := parts[0].split(">")
			_shots.append([_vec(cl[0], Vector3.ZERO), _vec(cl[1], Vector3.ZERO), float(parts[1]) if parts.size() > 1 else 55.0])


func _wire(a: Vector3, b: Vector3, sag: float, kind: int, r: float) -> Array:
	var n: int = SD.CABLE_SEGMENTS if sag > 0.0 else 1
	var pts := PackedVector3Array()
	for i in n + 1:
		pts.append(UP.catenary_point(a, b, sag, float(i) / float(n)))
	return [pts, r, kind]


func _along(at: Vector3, dir: Vector3) -> Transform3D:
	var x := Vector3.UP.cross(dir).normalized()
	return Transform3D(Basis(x, dir.cross(x).normalized(), dir), at)


func _add(parent: Node3D, mesh: Mesh, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	parent.add_child(mi)


func _vec(s: String, d: Vector3) -> Vector3:
	if s == "":
		return d
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())


func _process(_delta: float) -> bool:
	_frames += 1
	var i := (_frames - 1) / 8
	if i >= _shots.size():
		return true
	var s: Array = _shots[i]
	_cam.fov = s[2]
	_cam.look_at_from_position(s[0], s[1])
	if (_frames - 1) % 8 == 7:
		var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "pole.png"
		if i > 0:
			out = out.get_basename() + "_%d.png" % i
		get_root().get_texture().get_image().save_png(out)
		print("saved ", out)
	return false
