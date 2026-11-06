extends Node
## The freight line's rolling stock on its own (FreightStock): a locomotive and one of each car on
## a straight piece of the line's track (FreightKit's ballast, ties and rails), lit with the city's
## daylight numbers. Seconds a frame instead of minutes for a city still.
##
##   OUT=stock.png CAM=14,3,-30 LOOK=0,2.5,-12 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     tools/freight/stock_shot.tscn --resolution 1280x720
##
## Env: OUT, CAM, LOOK, FOV, HOUR (sun from the hour; 21+ dark with the lamps lit), LAMPS=1 lights
## the locomotive's cab end, LOD=1 the mid level, ORDER=0,1,2,3,4,5 the cars (FreightRail.Car) from
## -Z, SHOTS="cx,cy,cz>lx,ly,lz;..." more views from one load (OUT_n.png). Prints triangle counts.
func _ready() -> void:
	var stage := Node3D.new()
	add_child(stage)
	var hour := float(OS.get_environment("HOUR")) if OS.get_environment("HOUR") != "" else 15.0
	var night := hour > 20.0 or hour < 5.0
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.68) * (0.05 if night else 1.0)
	sky_mat.sky_horizon_color = Color(0.7, 0.74, 0.78) * (0.05 if night else 1.0)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.45) * (0.05 if night else 1.0)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.18) * (0.05 if night else 1.0)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25
	e.tonemap_white = 5.0
	e.glow_enabled = night
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-clampf(90.0 - absf(hour - 12.5) * 11.0, 4.0, 80.0), 35.0, 0.0)
	sun.light_energy = 0.05 if night else 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.34, 0.31)
	gm.roughness = 0.95
	ground.material_override = gm
	ground.position.y = -0.66
	stage.add_child(ground)
	# The track: two ballasted tracks along z through FreightKit's own writers (a stand-in chunk).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ties := PackedFloat32Array()
	var z := -200.0
	var mesh_track := _track_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh_track
	mi.material_override = FreightKit.track_material()
	stage.add_child(mi)
	var tie_mm := MultiMesh.new()
	tie_mm.transform_format = MultiMesh.TRANSFORM_3D
	tie_mm.mesh = FreightKit.tie_mesh()
	var tie_x: Array[Transform3D] = []
	for tx: float in [0.0, 4.6]:
		z = -200.0
		while z < 200.0:
			tie_x.append(Transform3D(Basis(), Vector3(tx, -0.172, z)))
			z += FreightKit.TIE_SPACING
	tie_mm.instance_count = tie_x.size()
	for i in tie_x.size():
		tie_mm.set_instance_transform(i, tie_x[i])
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = tie_mm
	tmi.material_override = FreightKit.track_material()
	stage.add_child(tmi)
	# The cars, coupled along -Z from the origin.
	var order := [0, 0, 1, 2, 3, 4, 5]
	if OS.get_environment("ORDER") != "":
		order = []
		for p in OS.get_environment("ORDER").split(","):
			order.append(p.to_int())
	var lamps := 1.0 if OS.get_environment("LAMPS") == "1" else 0.0
	var at := 0.0
	var boxes: Array = []
	var box_mm := MultiMesh.new()
	box_mm.transform_format = MultiMesh.TRANSFORM_3D
	box_mm.use_colors = true
	box_mm.use_custom_data = true
	box_mm.mesh = PropFactory.container()
	for k in order.size():
		var t: int = order[k]
		var l: float = FreightRail.CAR_LEN[t]
		var c := at - l * 0.5
		at -= l
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var m := FreightStock.mesh(t)
		mm.mesh = m if OS.get_environment("LOD") != "1" else _forced(m, 1)
		mm.instance_count = 1
		var xf := Transform3D(Basis(), Vector3(0.0, 0.0, c))
		mm.set_instance_transform(0, xf)
		mm.set_instance_color(0, Color.WHITE)
		var look := 1234567 + k * 7919
		mm.set_instance_custom_data(0, FreightStock.custom(t, look, (lamps if k == 0 else 0.0) if t == FreightRail.Car.LOCO else -1.0, 0.123 + float(k) * 0.111 if t == FreightRail.Car.LOCO else -1.0))
		var cmi := MultiMeshInstance3D.new()
		cmi.multimesh = mm
		stage.add_child(cmi)
		if t == FreightRail.Car.WELL:
			for b: Array in FreightYard.well_boxes(look):
				var bx: Transform3D = b[0]
				boxes.append([Transform3D(bx.basis, xf * bx.origin), b[1], b[2]])
		print("type %d: %d triangles" % [t, FreightStock.triangles(t)])
	box_mm.instance_count = boxes.size()
	for i in boxes.size():
		box_mm.set_instance_transform(i, boxes[i][0])
		box_mm.set_instance_color(i, boxes[i][1])
		box_mm.set_instance_custom_data(i, boxes[i][2])
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = box_mm
	stage.add_child(bmi)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	cam.far = 2000.0
	stage.add_child(cam)
	var views: Array = [[_vec(OS.get_environment("CAM"), Vector3(14.0, 3.0, 8.0)), _vec(OS.get_environment("LOOK"), Vector3(0.0, 2.5, -14.0))]]
	for v in OS.get_environment("SHOTS").split(";", false):
		var parts := v.split(">")
		views.append([_vec(parts[0], Vector3.ZERO), _vec(parts[1], Vector3.ZERO)])
	var out := OS.get_environment("OUT")
	if out == "":
		out = "stock.png"
	for i in views.size():
		cam.look_at_from_position(views[i][0], views[i][1], Vector3.UP)
		cam.make_current()
		for f in 6:
			await get_tree().process_frame
		var img := get_tree().root.get_texture().get_image()
		img.save_png(out if i == 0 else out.replace(".png", "_%d.png" % i))
	get_tree().quit()


## Two tracks' ballast and rails, 400 m along z (FreightKit's writers on a bare kit).
static func _track_mesh() -> ArrayMesh:
	var kit := Kit.new()
	kit.ballast([0.0, 4.6], -200.0, 200.0, 0.0, 0.0, -0.65, -0.65, 1.0)
	var z := -200.0
	while z < 200.0:
		for tx: float in [0.0, 4.6]:
			kit.rails(tx, z, tx, z + 8.0, 0.0, 0.0)
		z += 8.0
	return kit.track.commit()


class Kit:
	extends RefCounted
	var track := SurfaceTool.new()
	var full := true
	func _init() -> void:
		track.begin(Mesh.PRIMITIVE_TRIANGLES)
	func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, col: Color,
			ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO, u2 := Vector2.ZERO) -> void:
		for t: Array in [[a, b, c, ua, ub, uc], [a, c, d, ua, uc, ud]]:
			var p0: Vector3 = t[0]
			var p1: Vector3 = t[1]
			var p2: Vector3 = t[2]
			var q0: Vector2 = t[3]
			var q1: Vector2 = t[4]
			var q2: Vector2 = t[5]
			var n := (p2 - p0).cross(p1 - p0)
			if n.length_squared() < 1e-12:
				continue
			if n.dot(want) < 0.0:
				var tp := p1
				p1 = p2
				p2 = tp
				var tq := q1
				q1 = q2
				q2 = tq
				n = -n
			n = n.normalized()
			for j in 3:
				st.set_color(col)
				st.set_normal(n)
				st.set_uv([q0, q1, q2][j])
				st.set_uv2(u2)
				st.add_vertex([p0, p1, p2][j])
	func ballast(xs: Array, za: float, zb: float, ya: float, yb: float, ga: float, gb: float, dirt := 1.0) -> void:
		var ta := ya - FreightKit.BALLAST_DROP
		var col := FreightKit.tcol(FreightKit.BALLAST_COL, FreightKit.T_BALLAST)
		var edges: Array = [float(xs[0]) - FreightKit.BALLAST_HALF, (float(xs[0]) + float(xs[1])) * 0.5, float(xs[1]) + FreightKit.BALLAST_HALF]
		for i in 2:
			var x0: float = edges[i]
			var x1: float = edges[i + 1]
			var cx: float = xs[i]
			quad(track, Vector3(x0, ta, za), Vector3(x1, ta, za), Vector3(x1, ta, zb), Vector3(x0, ta, zb), Vector3.UP, col,
				Vector2(za, x0 - cx), Vector2(za, x1 - cx), Vector2(zb, x1 - cx), Vector2(zb, x0 - cx), Vector2(0.0, dirt))
	func rails(xa: float, za: float, xb: float, zb: float, ya: float, yb: float) -> void:
		var prof: Array = LightRailKit.RAIL_PROFILE
		var n := prof.size()
		var across := Vector3.RIGHT
		var mid := Vector2(0.0, 0.09)
		for side: float in [-1.0, 1.0]:
			var off := side * (FreightRail.GAUGE * 0.5 + 0.036)
			var a0 := Vector3(xa, ya - 0.168, za) + across * off
			var b0 := Vector3(xb, yb - 0.168, zb) + across * off
			for k in n:
				var p: Vector2 = prof[k]
				var q: Vector2 = prof[(k + 1) % n]
				if p.y < 0.001 and q.y < 0.001:
					continue
				var e := q - p
				var on := Vector2(e.y, -e.x).normalized()
				if on.dot((p + q) * 0.5 - mid) < 0.0:
					on = -on
				var top := p.y > 0.16 and q.y > 0.16
				quad(track, a0 + across * p.x + Vector3.UP * p.y, a0 + across * q.x + Vector3.UP * q.y,
					b0 + across * q.x + Vector3.UP * q.y, b0 + across * p.x + Vector3.UP * p.y, across * on.x + Vector3.UP * on.y,
					FreightKit.tcol(FreightKit.RAIL_COL, FreightKit.T_HEAD if top else FreightKit.T_RAIL))


static func _forced(mesh: ArrayMesh, lod: int) -> ArrayMesh:
	var surf: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	var lods: Array = surf.get("lods", [])
	if lods.is_empty():
		return mesh
	var arrays := mesh.surface_get_arrays(0)
	var level: Dictionary = lods[mini(lod, lods.size()) - 1]
	var idx_bytes: PackedByteArray = level.get("index_data", PackedByteArray())
	var idx := PackedInt32Array()
	if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() <= 65535:
		for i in range(0, idx_bytes.size(), 2):
			idx.append(idx_bytes.decode_u16(i))
	else:
		idx = idx_bytes.to_int32_array()
	arrays[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, mesh.surface_get_material(0))
	return out


static func _vec(s: String, fallback: Vector3) -> Vector3:
	var p := s.split(",")
	if p.size() != 3:
		return fallback
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
