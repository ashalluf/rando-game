extends Node3D
## Stills of the ridges without the whole city (Ridges, RidgeBuild, RidgeSystem): the real chunk
## build round a point (FULL, then an LOD ring), the far node with every wire and lattice line and
## the red lights, the city scene's own WorldEnvironment and sun (and DayNight with DAYNIGHT=1,
## held at `-- --hour=h`), the horizon plane with GROUND=1. A minute or two a shot:
##
##   OUT=/tmp/r.png TOWER=5 xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . res://tools/ridges/ridge_shot.tscn \
##     --resolution 1280x720 -- --hour=17.6
##
## EYE=x,y,z,yaw,pitch (TRUE world, y over the ground there) or TOWER=n / MAST=i / SITE=id / SUB=1
## frames that piece (DIST metres off, AZ degrees round it, UP metres over its base, AIM 0..1 up it);
## FOV, FRAMES (default 14), BLOCKS (FULL chunks each way, default 1), LOD (LOD ring, default 3),
## CENTRE=x,z builds round that point, SHOTS="x,y,z,yaw,pitch;..." more eyes (OUT_1.png ...),
## NOFAR=1 leaves the far node out, GEO=1 prints the frame's triangles and draws.
var plan: CityPlan
var _ground_mat: ShaderMaterial


func set_ground_haze(color: Color, sun_direction: Vector3) -> void:
	if _ground_mat:
		_ground_mat.set_shader_parameter("haze_color", color)
		_ground_mat.set_shader_parameter("sun_dir", sun_direction)


func set_ground_smog(amount: float, color: Color) -> void:
	if _ground_mat:
		_ground_mat.set_shader_parameter("smog", amount)
		_ground_mat.set_shader_parameter("smog_color", color)


static func city_plan(city: Node) -> CityPlan:
	var p := CityPlan.new()
	p.seed = city.world_seed
	p.block_size_range = city.block_size_range
	p.street_width = city.street_width
	p.avenue_width = city.avenue_width
	p.sidewalk_width = city.sidewalk_width
	p.downtown_radius = city.downtown_radius
	p.midtown_radius = city.midtown_radius
	p.macro = MacroMap.new()
	p.macro.seed = city.world_seed
	p.macro.setup()
	return p


func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	plan = city_plan(city)
	var r := Ridges.of(plan)
	for keep in ["WorldEnvironment", "Sun"]:
		var n: Node = city.get_node_or_null(keep)
		if n:
			city.remove_child(n)
			n.owner = null
			add_child(n)
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = city.get("sun_rotation_degrees")
		RenderingServer.global_shader_parameter_set("sun_direction", sun.global_basis.z)
	if OS.get_environment("DAYNIGHT") != "0":
		var dn: Node = city.get_node_or_null("DayNight")
		if dn:
			city.remove_child(dn)
			dn.owner = null
			add_child(dn)
			dn.call("set_paused", true)
	if OS.get_environment("GROUND") == "1":
		city.set("plan", plan)
		_ground_mat = city.call("_build_ground_material")
		var plane := PlaneMesh.new()
		plane.size = Vector2(city.ground_size, city.ground_size)
		var subdiv: int = (city.get_script() as GDScript).get_script_constant_map()["GROUND_SUBDIVISIONS"]
		plane.subdivide_width = subdiv
		plane.subdivide_depth = subdiv
		var ground := MeshInstance3D.new()
		ground.mesh = plane
		ground.material_override = _ground_mat
		ground.extra_cull_margin = city.ground_size
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ground)
		if sun:
			_ground_mat.set_shader_parameter("sun_dir", sun.global_basis.z)
	var eye := OS.get_environment("EYE")
	var focus := _focus(r)
	if focus.size() > 0:
		var at: Vector3 = focus[0]
		var dist := _envf("DIST", 70.0)
		var az := deg_to_rad(_envf("AZ", 30.0))
		var cam_p := Vector2(at.x, at.z) + Vector2(sin(az), cos(az)) * dist
		var cy := plan.height_at(cam_p) if plan.zone_at(cam_p) == MacroMap.Zone.HILLS else CityChunk.SIDEWALK_TOP + plan.macro.relief_at(cam_p)
		var ey := maxf(cy + 1.7, at.y + _envf("UP", 2.0))
		var target := at + Vector3(0.0, float(focus[1]) * _envf("AIM", 0.45), 0.0)
		var look := target - Vector3(cam_p.x, ey, cam_p.y)
		var yaw := rad_to_deg(atan2(-look.x, -look.z))
		var pitch := rad_to_deg(atan2(look.y, Vector2(look.x, look.z).length()))
		eye = "%.1f,%.2f,%.1f,%.2f,%.2f" % [cam_p.x, ey - cy, cam_p.y, yaw, pitch]
		print("EYE ", eye)
	var eyes: Array = [eye]
	for e in OS.get_environment("SHOTS").split(";", false):
		eyes.append(e)
	var cam := Camera3D.new()
	cam.fov = _envf("FOV", 55.0)
	cam.far = 12000.0
	add_child(cam)
	cam.make_current()
	var style: Dictionary = city.chunk_style()
	var built := {}
	var blocks := int(_envf("BLOCKS", 1.0))
	var lod := int(_envf("LOD", 3.0))
	if OS.get_environment("NOFAR") != "1":
		var sys := RidgeSystem.new()
		add_child(sys)
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "ridge.png"
	for k in eyes.size():
		var p: PackedStringArray = (eyes[k] as String).split(",")
		var at := Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
		var g := Vector2(at.x, at.z)
		at.y += plan.height_at(g) if plan.zone_at(g) == MacroMap.Zone.HILLS else CityChunk.SIDEWALK_TOP + plan.macro.relief_at(g)
		var centre := g
		if OS.get_environment("CENTRE") != "":
			var cp := OS.get_environment("CENTRE").split(",")
			centre = Vector2(cp[0].to_float(), cp[1].to_float())
		elif focus.size() > 0:
			centre = Vector2((focus[0] as Vector3).x, (focus[0] as Vector3).z)
		var home: Vector2i = plan.block_index_at(centre)
		for dz in range(-lod, lod + 1):
			for dx in range(-lod, lod + 1):
				var bk := Vector2i(home.x + dx, home.y + dz)
				if built.has(bk):
					continue
				var ch := CityChunk.new()
				ch.plan = plan
				ch.ix = bk.x
				ch.iz = bk.y
				ch.level = CityChunk.Level.FULL if maxi(absi(dx), absi(dz)) <= blocks else CityChunk.Level.LOD
				ch.style = style
				add_child(ch)
				ch.build()
				built[bk] = ch
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(p[4].to_float()), deg_to_rad(p[3].to_float()), 0.0)), at)
		for i in int(_envf("FRAMES", 14.0)):
			await get_tree().process_frame
		var sysn := get_node_or_null("Ridges") as RidgeSystem
		if sysn and sysn.wires and OS.get_environment("WIRE_PX") != "":
			sysn.wires.material_override = null
			(sysn.wires.mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("min_px", _envf("WIRE_PX", 1.0))
			for i in 2:
				await get_tree().process_frame
		if sysn and sysn.wires and OS.get_environment("WIRE_DBG") == "3":
			var tw := RidgeSystem.Wires.new()
			var line: Dictionary = r.lines[0]
			for kk in 4:
				var ends: Array = r.span_ends(line, kk)
				for ph in 8:
					var pts := Ridges.wire(ends[0][ph], ends[1][ph], 20)
					tw.line(pts, 0.0145, 1.0, Color(0.3, 0.3, 0.3), 0)
					if kk == 2 and ph == 0:
						print("SPAN2 ", pts[0], " ", pts[10], " ", pts[20])
			var tmi := MeshInstance3D.new()
			tmi.mesh = tw.mesh(sysn.wires.mesh.surface_get_material(0))
			print("TEST surfaces ", tmi.mesh.get_surface_count(), " verts ", tw.v.size())
			add_child(tmi)
			for i in 3:
				await get_tree().process_frame
		if sysn and sysn.wires and OS.get_environment("WIRE_DBG") == "2":
			var tw := RidgeSystem.Wires.new()
			var f := -cam.global_basis.z
			var rt := cam.global_basis.x
			tw.seg(cam.global_position + f * 12.0 - rt * 3.0, cam.global_position + f * 12.0 + rt * 3.0, 0.05, 1.0, Color(0.3, 0.3, 0.3), 0)
			var tmi := MeshInstance3D.new()
			tmi.mesh = tw.mesh(sysn.wires.mesh.surface_get_material(0))
			add_child(tmi)
			var big := MeshInstance3D.new()
			big.mesh = sysn.wires.mesh
			add_child(big)
			sysn.wires.visible = false
			for i in 3:
				await get_tree().process_frame
		if sysn and sysn.wires and OS.get_environment("WIRE_DBG") != "":
			var va: PackedVector3Array = sysn.wires.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			print("WIRE aabb ", sysn.wires.custom_aabb, " first ", va[0], " ", va[100], " cam ", cam.global_position, " sys pos ", sysn.global_position, " visible ", sysn.wires.is_visible_in_tree())
		if sysn and sysn.wires and k == 0:
			print("WIRES %d vertices, lights %s, solids %s" % [(sysn.wires.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), sysn.lights != null, sysn.solids != null])
		if OS.get_environment("GEO") == "1":
			print("GEO tris=%d draws=%d objects=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
		var file := out if k == 0 else out.get_basename() + "_%d.png" % k
		get_viewport().get_texture().get_image().save_png(file)
		print("saved ", file)
	city.free()
	get_tree().quit()


## [position (true world, its base), height] of the piece TOWER / MAST / SITE / SUB names, or [].
func _focus(r: Ridges) -> Array:
	if OS.get_environment("TOWER") != "":
		var t: Dictionary = r.towers[int(OS.get_environment("TOWER"))]
		return [Vector3((t.pos as Vector2).x, float(t.base), (t.pos as Vector2).y), float(t.h)]
	if OS.get_environment("MAST") != "":
		var m: Dictionary = r.masts[int(OS.get_environment("MAST"))]
		return [Vector3((m.pos as Vector2).x, float(m.base), (m.pos as Vector2).y), float(m.h)]
	if OS.get_environment("SITE") != "":
		for s: Dictionary in r.sites:
			if s.id == OS.get_environment("SITE"):
				return [Vector3((s.pos as Vector2).x, float(s.base), (s.pos as Vector2).y), maxf(float(s.h), 8.0)]
	if OS.get_environment("SUB") == "1":
		var c: Vector2 = (r.substation.rect as Rect2).get_center()
		return [Vector3(c.x, float(r.substation.base), c.y), 18.0]
	return []


static func _envf(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return v.to_float() if v != "" else fallback
