extends Node3D
## The GI review's stills and GPU timings: fwd_block_shot.gd's small Forward+ scene (the FULL
## chunks round each EYE, the city's WorldEnvironment / Sun / DayNight / Weather) with the
## Environment set the way Quality sets it at a level, and settings overridden from the shell, so
## one setting's look and cost come out of one lavapipe run (docs/HANDOFF.md, "Grounded light").
##
##   OUT=/tmp/g.png EYE=2366,1.7,880,-55,6 QUALITY=0 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --display-driver x11 --audio-driver Dummy --path . \
##     res://tools/gi_review/gi_shot.tscn --resolution 960x540 -- --hour=12 --weather=clear
##
## EYE / SHOTS / FOV / FRAMES / BLOCKS (number or "home") as fwd_block_shot.gd; a sixth EYE field
## is that shot's hour. QUALITY=0..3 applies Quality's environment flags and GiTuning's numbers
## for that level (default 0, HIGH). ENV="ssao_radius=1.2,ssil_enabled=false" sets Environment
## properties after that (bool / float / int); SUN="shadow_blur=1.5" the sun's. GI_REVIEW=0 is
## the game before this pass (no GiTuning, no contact shadows). PROFILE=1 with --gpu-profile
## marks SAMPLES (6) frames of every shot for tools/gpu_profile.py (pipe the log through it, or
## through tools/gi_review/profile_split.py for one table per shot). CARS=n parks n cars (BodyType
## 0..) in a row from the EYE along its view, CAR_AT=x,z,yaw puts one exactly; both on the ground
## at once, wheels on, asleep. The camera wears the player's attributes (auto exposure, as the
## player's eye adapts; AUTO_EXPOSURE=0 none). VARIANTS="spec;spec" shoots every EYE once per
## spec (see _setup()), OUT_<shot>_<variant>.png. Opengl3: --rendering-driver opengl3.

var plan: CityPlan
var world_seed: int = 0
var _scene_env: Environment
var _base_env: Environment
var _sun: DirectionalLight3D


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _ready() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	world_seed = city.world_seed
	plan = CityPlan.new()
	plan.seed = city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = city.world_seed
	plan.macro.setup()
	var style: Dictionary = city.chunk_style()
	var eyes: Array = [_env("EYE", "0,2,0,0,0")]
	for e in _env("SHOTS", "").split(";", false):
		eyes.append(e)
	var first: PackedStringArray = (eyes[0] as String).split(",")
	var at0 := Vector3(first[0].to_float(), first[1].to_float(), first[2].to_float())
	at0.y += plan.height_at(Vector2(at0.x, at0.z))
	var stand := Node3D.new()
	stand.name = "PlayerStandIn"
	stand.add_to_group("player")
	add_child(stand)
	stand.global_position = at0
	var cam := Camera3D.new()
	cam.fov = float(_env("FOV", "55"))
	cam.far = float(_env("FAR", "12000"))
	add_child(cam)
	cam.make_current()
	# The player's own camera attributes (auto exposure 200..620, no far blur), so a dark
	# underpass is judged the way the player's eye adapts to it. AUTO_EXPOSURE=0: none.
	if _env("AUTO_EXPOSURE", "1") != "0":
		var player: Node = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
		var pcam := player.find_child("Camera3D", true, false) as Camera3D
		if pcam == null:
			for c in player.find_children("*", "Camera3D", true, false):
				pcam = c
		if pcam and pcam.attributes:
			var attr := pcam.attributes.duplicate() as CameraAttributesPractical
			attr.dof_blur_far_enabled = false
			attr.dof_blur_near_enabled = false
			cam.attributes = attr
			print("AUTO_EXPOSURE ", attr.auto_exposure_enabled, " ", attr.auto_exposure_min_sensitivity, "..", attr.auto_exposure_max_sensitivity)
		player.free()
	for keep in ["WorldEnvironment", "Sun", "DayNight", "Weather"]:
		var n: Node = city.get_node_or_null(keep)
		if n:
			city.remove_child(n)
			n.owner = null
			add_child(n)
	# The clock held: variants of one shot are seconds of real time apart and minutes of game time.
	var dn0: Node = get_node_or_null("DayNight")
	if dn0 and dn0.has_method("set_paused"):
		dn0.call("set_paused", true)
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	_scene_env = we.environment if we else null
	_base_env = _scene_env.duplicate() if _scene_env else null
	_sun = get_node_or_null("Sun") as DirectionalLight3D
	var variants: Array = []
	for v in _env("VARIANTS", "").split(";", false):
		variants.append(v)
	if variants.is_empty():
		variants.append("")
	var built := {}
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	var home_only := _env("BLOCKS", "1") == "home"
	var blocks := 0 if home_only else int(_env("BLOCKS", "1"))
	var out := _env("OUT", "gi.png")
	var profile := _env("PROFILE", "") == "1"
	for k in eyes.size():
		var p: PackedStringArray = (eyes[k] as String).split(",")
		var at := Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
		at.y += plan.height_at(Vector2(at.x, at.z))
		var home: Vector2i = plan.block_index_at(Vector2(at.x, at.z))
		for dz in range(-blocks, blocks + 1):
			for dx in range(-blocks, blocks + 1):
				var bk := Vector2i(home.x + dx, home.y + dz)
				if built.has(bk):
					continue
				var ch = chunk_script.new()
				ch.plan = plan
				ch.ix = bk.x
				ch.iz = bk.y
				ch.level = 0
				ch.style = style
				add_child(ch)
				ch.build()
				built[bk] = ch
		if p.size() > 5:
			var dn: Node = get_node_or_null("DayNight")
			if dn:
				dn.set("hour", p[5].to_float())
				dn.call("_apply")
		stand.global_position = at
		var basis := Basis.from_euler(Vector3(deg_to_rad(p[4].to_float()), deg_to_rad(p[3].to_float()), 0.0))
		cam.global_transform = Transform3D(basis, at)
		if k == 0:
			_park_cars(at, basis)
		for vi in variants.size():
			_setup(str(variants[vi]))
			for i in int(_env("FRAMES", "30")):
				await get_tree().process_frame
			if profile:
				print("GPU_PROFILE_BEGIN shot %d variant %d [%s]" % [k, vi, variants[vi]])
				for i in int(_env("SAMPLES", "6")):
					await get_tree().process_frame
				print("GPU_PROFILE_END")
			var file := out.get_basename() + "_%d_%d.png" % [k, vi]
			get_viewport().get_texture().get_image().save_png(file)
			print("saved ", file, " [", variants[vi], "]")
			print("GEO_%d_%d tris=%d draws=%d" % [k, vi, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	print("DONE")
	OS.kill(OS.get_process_id())


## One variant: the scene's environment as city.tscn has it, then Quality's switches for Q (the
## QUALITY default), GiTuning unless GI=0 (or GI_REVIEW=0), the contact shadows shown unless CS=0
## (or GI=0), then any Environment property=value in the spec. Space separated: "Q=1 GI=0 ssao_radius=2".
func _setup(spec: String) -> void:
	var env := _scene_env
	if env == null:
		return
	var q := int(_env("QUALITY", "0"))
	var gi := GiTuning.enabled
	var cs := ContactShadows.enabled
	var props: PackedStringArray = []
	for tok in spec.split(" ", false):
		if tok.begins_with("Q="):
			q = tok.trim_prefix("Q=").to_int()
		elif tok.begins_with("GI="):
			gi = tok.trim_prefix("GI=") != "0"
			cs = cs and gi
		elif tok.begins_with("CS="):
			cs = tok.trim_prefix("CS=") != "0"
		elif tok.begins_with("GIS=") or tok.begins_with("AMB=") or tok.begins_with("SKY=") or tok.begins_with("FILL="):
			pass
		else:
			props.append(tok)
	for pr in _base_env.get_property_list():
		var nm: String = pr.name
		if (nm.begins_with("ssao") or nm.begins_with("ssil") or nm.begins_with("sdfgi") or nm.begins_with("ssr")) and pr.usage & PROPERTY_USAGE_STORAGE:
			env.set(nm, _base_env.get(nm))
	env.sdfgi_enabled = q == 0
	env.volumetric_fog_enabled = q == 0
	env.ssil_enabled = q <= 1
	env.ssr_enabled = q <= 1
	env.ssao_enabled = q <= 2
	if _sun:
		_sun.directional_shadow_max_distance = [500.0, 380.0, 220.0, 120.0][q]
		_sun.shadow_blur = 1.0 if q <= 1 else 0.7
	if gi:
		var was := GiTuning.enabled
		GiTuning.enabled = true
		GiTuning.apply(env, _sun, q)
		GiTuning.enabled = was
	else:
		GiTuning.gi_scale = 1.0
		GiTuning.ambient_scale = 1.0
		GiTuning.sky_contribution = 1.0
		FreewayKit.structure_material().set_shader_parameter("under_fill", 0.0)
	# GIS= / AMB= override DayNight's SDFGI energy and sky fill multipliers after the level's.
	for tok in spec.split(" ", false):
		if tok.begins_with("GIS="):
			GiTuning.gi_scale = tok.trim_prefix("GIS=").to_float()
		elif tok.begins_with("AMB="):
			GiTuning.ambient_scale = tok.trim_prefix("AMB=").to_float()
		elif tok.begins_with("SKY="):
			GiTuning.sky_contribution = tok.trim_prefix("SKY=").to_float()
		elif tok.begins_with("FILL="):
			FreewayKit.structure_material().set_shader_parameter("under_fill", tok.trim_prefix("FILL=").to_float())
	_set_props(env, ",".join(props))
	_set_props(env, _env("ENV", ""))
	if _sun:
		_set_props(_sun, _env("SUN", ""))
	var inst := ContactShadows.instance()
	if inst:
		for c in inst.get_children():
			(c as Node3D).visible = cs
	for n in find_children("BatchContact", "MultiMeshInstance3D", true, false):
		(n as Node3D).visible = cs
	print("VARIANT [", spec, "] q ", q, " gi ", gi, " cs ", cs)


## Sets "name=value" pairs on an object, the value typed by the property's current one.
func _set_props(o: Object, spec: String) -> void:
	for pair in spec.split(",", false):
		var kv := pair.split("=")
		if kv.size() != 2:
			continue
		var cur: Variant = o.get(kv[0])
		var v: Variant = kv[1]
		if cur is bool:
			v = kv[1] == "true" or kv[1] == "1"
		elif cur is float:
			v = kv[1].to_float()
		elif cur is int:
			v = kv[1].to_int()
		o.set(kv[0], v)
		print("SET ", o.get_class(), ".", kv[0], " = ", o.get(kv[0]))


## CARS=n: parked cars in a row ahead of the eye, 6 m apart, 7 m out (a car to look at, whatever
## the block parked); CAR_AT=x,z,yaw,type: one exactly.
func _park_cars(at: Vector3, basis: Basis) -> void:
	var specs: Array = []
	var n := int(_env("CARS", "0"))
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for i in n:
		var p := at + fwd * (7.0 + 6.0 * i)
		specs.append([p.x, p.z, rad_to_deg(atan2(-fwd.x, -fwd.z)) + 90.0, i % 4])
	for s in _env("CAR_AT", "").split(";", false):
		var v := s.split(",")
		specs.append([v[0].to_float(), v[1].to_float(), v[2].to_float() if v.size() > 2 else 0.0, v[3].to_int() if v.size() > 3 else 0])
	var paints := [Color(0.08, 0.09, 0.1), Color(0.86, 0.87, 0.88), Color(0.45, 0.06, 0.05), Color(0.5, 0.52, 0.55)]
	for j in specs.size():
		var s: Array = specs[j]
		var car = (load("res://scripts/vehicles/vehicle.gd") as GDScript).new()
		car.call("setup", int(s[3]), paints[j % paints.size()], 0)
		var gy := plan.height_at(Vector2(s[0], s[1]))
		car.position = Vector3(s[0], gy + 0.9, s[1])
		car.rotation.y = deg_to_rad(s[2])
		add_child(car)
		print("CAR ", s)
