extends SceneTree
## Proves a merged Building draws what the node-per-part Building drew, pixel for pixel.
##
##   LIBGL_ALWAYS_SOFTWARE=1 flock -o /tmp/rando_render_gl.lock xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/building_merge_probe.gd --resolution 640x360
##
## (vulkan through lavapipe works too, under /tmp/rando_render.lock: it is one building, not a city.)
## For a handful of seeded buildings - setbacks, podium towers, stepped and L blocks, chamfered,
## one standing on a slope and one turned - and camera distances either side of every detail
## range (frames 240 m, bands 380 m, parapets 760 m), by day and by night, it renders the building
## as it is built now (the walls one mesh under one material, one facade-detail MultiMesh per kind,
## the roof plant one mesh, the rooftop units a MultiMesh per model), then hides those and puts
## the old nodes back from the same data - a BoxMesh or prism with its own ShaderMaterial per part,
## a MultiMesh per part per kind with its own visibility range and StandardMaterial3D, a node per
## roof box, cylinder and unit - renders the same frame again and prints how many pixels differ,
## then which kind of node the difference comes from (the old nodes of that kind alone swapped
## in: walls, detail, roof plant, roof units). SHIFT=1 also renders both again with the scene's
## origin moved by SHIFT_BY metres (default 137.25, 0, -61.5), as CityStreamer.recenter() does,
## and compares old with old: pixels that flip on an origin shift in the old build are float
## rounding (a z-fight's winner, a shadow contact, a pixel on a window edge), which merging
## moves exactly as a re-centre does. OUT_DIR=path saves every image. The rooftop units are the
## one intended difference: one MultiMesh picks its LOD from its whole box, so a far unit can
## be drawn finer (never coarser). DIST=35,230,... picks the distances, NIGHT=0 skips the night,
## ONLY=1,2 the buildings (indices into SEEDS).
## Building is loaded, not named: it reaches the autoloads, and this script compiles before them.

const SEEDS := [[3301, 5], [4417, 5], [5023, 3], [6121, 2], [7717, 4], [8819, 6], [9901, 0]]
const DISTANCES := [35.0, 120.0, 230.0, 250.0, 370.0, 395.0, 740.0, 780.0]

var _worst := 0
var _building: GDScript = null
var _pairs := 0
var _differ_pairs := 0


func _initialize() -> void:
	# A script error stops this coroutine but not the tree, which would then hold the render lock
	# until the outer timeout: give up on our own well before that.
	create_timer(2700.0).timeout.connect(func() -> void:
		print("PROBE timed out")
		quit(1))
	var root3 := Node3D.new()
	root.add_child(root3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.35, 0.38, 0.45)
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 900.0
	root3.add_child(sun)
	var cam := Camera3D.new()
	cam.far = 3000.0
	root3.add_child(cam)
	cam.current = true
	await process_frame
	# The scene first: loading building.gd on its own first walks into a preload cycle.
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	_building = load("res://scripts/world/building.gd")
	_building.set("keep_records", true)
	# As if the origin had been re-centred far from here: the detail nodes' part centres are in
	# true world space and must come back through the origin_shift global.
	root.get_node("WorldState").set("world_offset", Vector3(1234.5, 0.0, -987.25))
	var out_dir := OS.get_environment("OUT_DIR")
	var only := Array(OS.get_environment("ONLY").split(",", false)).map(func(t: String) -> int: return t.to_int())
	for si in SEEDS.size():
		if not only.is_empty() and not only.has(si):
			continue
		var spec: Array = SEEDS[si]
		var b: Node3D = scene.instantiate()
		b.set("seed", spec[0])
		b.set("force_shape", spec[1])
		b.set("lot_size", Vector2(46.0, 40.0))
		b.set("min_height", 60.0 if spec[1] in [4, 5, 6] else 18.0)
		b.set("max_height", 170.0 if spec[1] in [4, 5, 6] else 40.0)
		b.set("chamfer_chance", 1.0 if si % 2 == 0 else 0.0)
		b.set("plinth_depth", 1.2)
		# One on a slope (its floors counted from a world height that is not zero), one turned.
		b.position = Vector3(0.0, 7.3 if si == 2 else 0.0, 0.0)
		b.rotation.y = 0.6 if si == 3 else 0.0
		root3.add_child(b)
		await process_frame
		var olds := _old_nodes(b, _building)
		var shift_on := OS.get_environment("SHIFT") == "1"
		var by := Vector3(137.25, 0.0, -61.5)
		if OS.get_environment("SHIFT_BY") != "":
			var p := OS.get_environment("SHIFT_BY").split(",")
			by = Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
		var nights := [false] if OS.get_environment("NIGHT") == "0" else [false, true]
		var dists: Array = DISTANCES
		if OS.get_environment("DIST") != "":
			dists = Array(OS.get_environment("DIST").split(",")).map(func(t: String) -> float: return t.to_float())
		for night: bool in nights:
			RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
			RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
			for dist: float in dists:
				var height: float = b.get("height")
				var mid := Vector3(0.0, height * 0.45, 0.0)
				var dir := Vector3(0.62, 0.0, 0.78).normalized()
				cam.position = mid + dir * dist + Vector3(0.0, 2.0 + dist * 0.12, 0.0)
				cam.look_at(mid)
				cam.fov = clampf(2.0 * rad_to_deg(atan(height * 0.7 / dist)), 12.0, 75.0)
				_show(b, olds, [])
				var a := await _grab()
				_show(b, olds, KINDS)
				var o := await _grab()
				var r := _compare(a, o)
				_pairs += 1
				if r[0] > 0:
					_differ_pairs += 1
				_worst = maxi(_worst, r[1])
				var tag := "seed %d shape %d %s %4.0f m" % [spec[0], spec[1], "night" if night else "day  ", dist]
				print("PROBE %s: %d px differ (%d > 2/255), worst %d/255" % [tag, r[0], r[2], r[1]])
				var line := ""
				for kind: String in KINDS:
					_show(b, olds, [kind])
					var k := _compare(a, await _grab())
					line += "  %s %d (%d)" % [kind, k[0], k[2]]
				print("PROBE   by kind swapped alone, px differ (> 2/255):%s" % line)
				if shift_on:
					# Move the whole scene the way a re-centre does: the building, the camera and
					# the world offset, so true world positions stay where they were.
					var ws := root.get_node("WorldState")
					b.position -= by
					cam.position -= by
					ws.set("world_offset", (ws.get("world_offset") as Vector3) + by)
					_show(b, olds, [])
					var a2 := await _grab()
					_show(b, olds, KINDS)
					var o2 := await _grab()
					b.position += by
					cam.position += by
					ws.set("world_offset", (ws.get("world_offset") as Vector3) - by)
					var so := _compare(o, o2)
					var sn := _compare(a, a2)
					print("PROBE   origin moved %s: old vs old %d px (%d > 2/255, worst %d), new vs new %d px (%d > 2/255, worst %d)" % [
						by, so[0], so[2], so[1], sn[0], sn[2], sn[1]])
				if out_dir != "":
					a.save_png("%s/b%d_%s_%d_new.png" % [out_dir, si, "n" if night else "d", int(dist)])
					o.save_png("%s/b%d_%s_%d_old.png" % [out_dir, si, "n" if night else "d", int(dist)])
		# The old nodes are the building's children and go with it.
		b.queue_free()
		await process_frame
	print("PROBE done: %d of %d frames differ at all, worst pixel %d/255" % [_differ_pairs, _pairs, _worst])
	quit()


func _grab() -> Image:
	for i in 3:
		await process_frame
	return root.get_texture().get_image()


## [pixels that differ at all, the worst difference, pixels more than 2/255 off].
static func _compare(a: Image, b: Image) -> Array:
	var n := 0
	var big := 0
	var worst := 0
	for y in a.get_height():
		for x in a.get_width():
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			var d := roundi(maxf(absf(pa.r - pb.r), maxf(absf(pa.g - pb.g), absf(pa.b - pb.b))) * 255.0)
			if d > 0:
				n += 1
				worst = maxi(worst, d)
				if d > 2:
					big += 1
	return [n, worst, big]


const KINDS := ["walls", "detail", "plant", "units"]


## Which kind of merged node a building child is ("" for the rest: plinth, kit, signs).
static func _kind(n: Node) -> String:
	var nm := String(n.name)
	if nm == "Walls":
		return "walls"
	if nm in ["Frames", "Details", "Bays"]:
		return "detail"
	if nm == "RoofPlant":
		return "plant"
	if nm.begins_with("RoofUnits"):
		return "units"
	return ""


## Shows the old nodes of the kinds in `old` and the merged nodes of the rest.
static func _show(b: Node3D, olds: Dictionary, old: Array) -> void:
	for c in b.get_children():
		var k := _kind(c)
		if k != "" and not (c as Node3D).has_meta("old"):
			(c as Node3D).visible = not old.has(k)
	for k: String in olds:
		for n: Node3D in olds[k]:
			n.visible = old.has(k)


## The building's merged nodes rebuilt the old way, as children of the building.
static func _old_nodes(b: Node3D, bscript: GDScript) -> Dictionary:
	var out := {"walls": [], "detail": [], "plant": [], "units": []}
	# Walls: a mesh and a ShaderMaterial per part, the part's numbers in its uniforms.
	for part: Dictionary in b.get("parts"):
		var size: Vector3 = part.size
		var mat := (b.get("_part_mat") as ShaderMaterial).duplicate() as ShaderMaterial
		mat.set_shader_parameter("part_attributes", false)
		mat.set_shader_parameter("window_pitch_x", part.pitch_x)
		mat.set_shader_parameter("window_pitch_z", part.pitch_z)
		mat.set_shader_parameter("floor_height", part.floor_h)
		mat.set_shader_parameter("ground_floor_height", part.gfh)
		mat.set_shader_parameter("base_y", part.base_y)
		mat.set_shader_parameter("has_storefront", part.storefront)
		mat.set_shader_parameter("part_size", size)
		mat.set_shader_parameter("base_height", part.base_h)
		if float(part.crown) < 99999.0:
			mat.set_shader_parameter("crown_start", part.crown)
		var mi := MeshInstance3D.new()
		if part.boxy:
			var box := BoxMesh.new()
			box.size = size
			mi.mesh = box
		else:
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bscript.call("_prism_arrays", size, part.cut.x, part.cut.y))
			mi.mesh = am
		mi.material_override = mat
		mi.position = part.center
		out.walls.append(mi)
	# Facade detail: a MultiMesh per part per kind, as the building recorded them before merging,
	# with the mesh's own StandardMaterial3D and the node's own visibility range.
	for rec: Array in b.get("detail_record"):
		var om := MultiMesh.new()
		om.transform_format = MultiMesh.TRANSFORM_3D
		om.use_colors = true
		om.mesh = rec[1]
		om.instance_count = (rec[2] as Array).size()
		for i in om.instance_count:
			om.set_instance_transform(i, rec[2][i])
			om.set_instance_color(i, rec[3][i])
		var on := MultiMeshInstance3D.new()
		on.multimesh = om
		on.visibility_range_end = rec[4]
		if not rec[5]:
			on.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.detail.append(on)
	# Roof plant: a node per box and cylinder with its own StandardMaterial3D.
	for prim: Array in b.get("roof_record"):
		var arrays: Array = prim[1]
		var pm := ArrayMesh.new()
		pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var sm := StandardMaterial3D.new()
		if prim[5]:
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = prim[2]
		sm.roughness = prim[3]
		sm.metallic = prim[4]
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = sm
		mi.transform = prim[0]
		out.plant.append(mi)
	# Rooftop units: a node each.
	for c in b.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("RoofUnits"):
			var mm := (c as MultiMeshInstance3D).multimesh
			var buf := mm.buffer
			var stride := buf.size() / mm.instance_count
			for i in mm.instance_count:
				var o := i * stride
				var mi := MeshInstance3D.new()
				mi.mesh = mm.mesh
				mi.transform = Transform3D(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
					Vector3(buf[o + 2], buf[o + 6], buf[o + 10]), Vector3(buf[o + 3], buf[o + 7], buf[o + 11]))
				out.units.append(mi)
	for k: String in out:
		for n: Node3D in out[k]:
			n.visible = false
			n.set_meta("old", true)
			b.add_child(n)
	return out
