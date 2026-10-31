extends Node3D
## A small night street for the lamps (night-lamps-review, wave 4): a two-lane road between two
## pavements, a row of real Buildings behind one of them, the city's own WorldEnvironment, Sun and
## DayNight (out of city.tscn, so the moon, the grade, the exposure and the lamps' level are the
## game's), real StreetLamps placed and lit exactly as CityChunk does (model, pool, NightAtmos halo
## / shaft / wet streak, OmniLight3D in "lamp_light" + "street_lamp_light"), a parked car and a few
## people standing under the lamps. Small enough for Forward+ under lavapipe in a few minutes:
##
##   OUT=/tmp/s.png VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s \
##     "-screen 0 1280x720x24" godot --rendering-driver vulkan --display-driver x11 \
##     --audio-driver Dummy --path . res://tools/night_lamps/lamp_street.tscn --resolution 960x540 \
##     -- --hour=21.5
##
## Env: OUT; SHOTS="cx,cy,cz,lx,ly,lz[,fov];..." (camera and look-at, one PNG each: OUT, OUT_1, ...;
## default three: the far pavement down the street, under a lamp, the facades); TYPE=cobra|twin|
## lantern|post|mast (default a mix down the row), LED=0|1 (default: the row's own roll, both kinds),
## WET=0..1 (road_wetness, and rain_intensity when over 0.6), HAZE=0..1 (night_atmos.x, default 0.3
## or 0.85 wet), FRAMES (default 24). The lamp-review switches (LAMP_REVIEW=0, LAMP_SHADOWS=0 ...)
## are read by the game's scripts as usual. Prints LAMPS lines (lights, shadowed ones).

const ROAD_HALF := 7.0
const WALK := 4.2
const LAMP_EVERY := 30.0

var _frames := 24


func _ready() -> void:
	_frames = int(_env("FRAMES", "24"))
	var stage := self
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	for keep in ["WorldEnvironment", "Sun", "DayNight"]:
		var n: Node = city.get_node_or_null(keep)
		if n:
			city.remove_child(n)
			n.owner = null
			stage.add_child(n)
	city.free()
	var wet := float(_env("WET", "0"))
	var haze := float(_env("HAZE", "0.85" if wet > 0.3 else "0.3"))
	RenderingServer.global_shader_parameter_set("road_wetness", wet)
	RenderingServer.global_shader_parameter_set("rain_intensity", 0.7 if wet > 0.6 else 0.0)
	RenderingServer.global_shader_parameter_set("night_atmos", Vector4(haze, 1.0, 1.0, 540.0))
	_ground(stage)
	_buildings(stage)
	_lamps(stage)
	_props(stage)
	await get_tree().process_frame
	await get_tree().process_frame
	var cam := Camera3D.new()
	cam.far = 2000.0
	stage.add_child(cam)
	cam.make_current()
	var shots := _env("SHOTS", "-6,1.7,-4,4,3,40;3.5,1.6,22,9,2.5,34;-3,1.8,52,14,6,40,60").split(";", false)
	var out := _env("OUT", "lamp_street.png")
	for k in shots.size():
		var p := shots[k].split(",")
		cam.fov = p[6].to_float() if p.size() > 6 else 55.0
		cam.look_at_from_position(Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float()), Vector3(p[3].to_float(), p[4].to_float(), p[5].to_float()), Vector3.UP)
		for i in _frames:
			await get_tree().process_frame
		var shadowed := 0
		var lit := 0
		for l in get_tree().get_nodes_in_group("street_lamp_light"):
			var o := l as OmniLight3D
			if o.visible and o.light_energy > 0.001:
				lit += 1
			if o.shadow_enabled:
				shadowed += 1
		print("LAMPS lit=%d shadowed=%d energy=%.2f" % [lit, shadowed, (get_tree().get_nodes_in_group("street_lamp_light")[0] as OmniLight3D).light_energy])
		print("GEO_%d tris=%d draws=%d shadow_tris=%d" % [k, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		var file := out if k == 0 else out.get_basename() + "_%d.png" % k
		get_viewport().get_texture().get_image().save_png(file)
		print("saved ", file)
	print("DONE")
	OS.kill(OS.get_process_id())


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _box(stage: Node3D, size: Vector3, at: Vector3, mat: Material, body := true) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = at
	stage.add_child(mi)
	if body:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		sb.position = at
		stage.add_child(sb)


func _ground(stage: Node3D) -> void:
	var asphalt := PropFactory.road("asphalt", 6.0, Color(0.55, 0.55, 0.56), 11, 0.0, 1.0)
	var walk := PropFactory.road("sidewalk", 3.0, Color(1.0, 1.0, 1.0), 12, 1.5, 0.3)
	_box(stage, Vector3(ROAD_HALF * 2.0, 0.2, 260.0), Vector3(0.0, -0.1, 20.0), asphalt)
	for s: float in [-1.0, 1.0]:
		_box(stage, Vector3(WALK, 0.35, 260.0), Vector3(s * (ROAD_HALF + WALK * 0.5), -0.025, 20.0), walk)
	# Behind the far pavement: a low wall and a hedge line stand-in, so the near view has a back.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.22, 0.21, 0.2)
	_box(stage, Vector3(0.4, 1.4, 260.0), Vector3(-(ROAD_HALF + WALK) - 0.2, 0.7, 20.0), dark)


func _buildings(stage: Node3D) -> void:
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var z := -40.0
	var k := 0
	while z < 120.0:
		var w := 18.0 + float((k * 7) % 3) * 4.0
		var b = scene.instantiate()
		b.seed = 4100 + k * 37
		b.lot_size = Vector2(16.0, w - 1.0)
		b.min_height = 9.0
		b.max_height = 22.0
		b.position = Vector3(ROAD_HALF + WALK + 8.0, 0.15, z + w * 0.5)
		stage.add_child(b)
		z += w
		k += 1


func _lamps(stage: Node3D) -> void:
	var types := {"cobra": 0, "twin": 1, "lantern": 2, "post": 3, "mast": 4}
	var forced := int(types.get(_env("TYPE", ""), -1))
	var mix := [0, 1, 4, 2, 0, 3]
	var batch := MultiMeshBatch.new()
	var i := 0
	var z := -20.0
	while z < 120.0:
		var t: int = forced if forced >= 0 else mix[i % mix.size()]
		# Lamps on the building side's kerb, every LAMP_EVERY m, facing the road (-x); the LED roll is
		# the place's (NightCity), or LED= forces it by moving the lamp's key point.
		var at := Vector3(ROAD_HALF + 0.6, 0.15, z)
		var lp := StreetLamps.place(null, at, Vector2(-1.0, 0.0), t)
		var key_at := Vector2(at.x, at.z)
		if _env("LED", "") != "":
			key_at = Vector2(2800.0, 100.0) if _env("LED", "") == "1" else Vector2(-9000.0, 9000.0)
			while NightCity.lamp_led(key_at) != (_env("LED", "") == "1"):
				key_at += Vector2(420.0, 0.0)
		var head := Vector3.ZERO
		for l: Vector3 in lp.lights:
			head += l
		head /= float(lp.lights.size())
		var size: float = lp.pool
		batch.add(lp.key, lp.mesh, lp.xform, lp.paint, Color(1.0 if NightCity.lamp_led(key_at) else 0.0, 0.4, 0.0, 0.0))
		var pool := NightLamps.pool_instance(lp, head, Vector3(key_at.x, at.y, key_at.y) if _env("LED", "") != "" else at)
		var pxf: Transform3D = pool[0]
		pxf.origin = Vector3(head.x, at.y + 0.09, head.z)
		batch.add("lamp_pool", PropFactory.light_pool(), pxf, pool[1], pool[2])
		for part: Array in NightAtmos.lamp_parts(lp.lights, head, at.y, size, key_at, true):
			batch.add(part[0], part[1], part[2], part[3], part[4] if part.size() > 4 else Color.BLACK)
		var light := OmniLight3D.new()
		light.position = head + Vector3(0.0, -0.25, 0.0)
		light.omni_range = lp.range
		light.omni_attenuation = maxf(1.4 * log(3.5) / log(maxf(head.y - at.y - 0.25, 3.5)), 1.1)
		NightLamps.tune_light(light, head.y - at.y - 0.25)
		light.light_color = NightCity.lamp_light(key_at)
		light.light_energy = 0.0
		light.distance_fade_enabled = true
		light.distance_fade_begin = 45.0
		light.distance_fade_length = 15.0
		light.add_to_group("lamp_light")
		light.add_to_group("street_lamp_light")
		stage.add_child(light)
		z += LAMP_EVERY
		i += 1
	batch.set_no_shadow("lamp_pool")
	NightAtmos.finish_batch(batch)
	batch.build(stage)
	LampShadows.ensure(stage)


func _props(stage: Node3D) -> void:
	# A parked car in the kerb lane under the second lamp and one under the fourth.
	for zc: float in [12.0, 70.0]:
		var car: Node3D = load("res://scripts/vehicles/vehicle.gd").new()
		car.call("setup", 0 if zc < 20.0 else 1, Color(0.55, 0.06, 0.05) if zc < 20.0 else Color(0.8, 0.8, 0.82), 0)
		car.position = Vector3(ROAD_HALF - 1.3, 0.9, zc)
		stage.add_child(car)
	# People standing on the pavement near the lamps.
	var models := ["res://assets/models/crowd_a.glb", "res://assets/models/crowd_e.glb", "res://assets/models/crowd_h.glb"]
	var spots := [Vector3(ROAD_HALF + 1.6, 0.15, 7.0), Vector3(ROAD_HALF + 2.4, 0.15, 13.0), Vector3(ROAD_HALF + 1.2, 0.15, 41.0)]
	for k in spots.size():
		var packed: PackedScene = load(models[k])
		if packed == null:
			continue
		var inst: Node3D = packed.instantiate()
		inst.position = spots[k]
		inst.rotation.y = 0.6 * float(k) - 1.2
		stage.add_child(inst)
		Pedestrian.prepare_rig(inst, k)
		var aps := inst.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			var ap: AnimationPlayer = aps[0]
			for clip in ["Idle", "idle"]:
				if ap.has_animation(clip):
					ap.play(clip)
					break
