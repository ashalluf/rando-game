extends Node3D
## The shadows review's lab (docs/HANDOFF.md, "Shadows across the game"): the city's own
## WorldEnvironment, Sun and DayNight over a small set - asphalt and a kerbed pavement, two
## building blocks, a parked car, two people, a street tree, a palm, a street lamp, a bench and a
## row of posts every 10 m out to 300 m (the cascade seams) - so a shadow setting's look and cost
## come out of one lavapipe Forward+ run in a few minutes (the city's FULL chunks do not fit it).
##
##   OUT=build/sr/lab.png EYE=0,1.7,14,0,-6,12 VARIANTS="ST=0;ST=1" \
##     VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --display-driver x11 --audio-driver Dummy --path . \
##     res://tools/shadows_review/shadow_lab.tscn --resolution 960x540
##
## EYE=x,y,z,yaw,pitch[,hour] (yaw 0 looks north, 90 west), SHOTS="eye;eye" more from one load
## (OUT_<shot>_<variant>.png), FOV (55), FRAMES (24). VARIANTS="spec;spec": every shot once per
## spec; a spec is space-separated tokens: Q=0..3 (Quality's sun numbers for that level),
## ST=0|1 (ShadowTuning off / on, default its env switch), sun.<prop>=<value> (DirectionalLight3D),
## env.<prop>=<value> (Environment), SUN_YAW=<deg> turns the sun about the vertical after DayNight
## (so a golden-hour shadow can be thrown across the view), CS=0 hides the contact shadows' quads. opengl3 for the Compatibility path.
## PROFILE=1 with --gpu-profile marks SAMPLES (6) frames per shot for tools/gpu_profile.py.

var _sun: DirectionalLight3D
var _env: Environment
var _base_env: Environment
var _dn: Node


## The camera follow, as DayNight runs it in the game (the lab's DayNight is paused, but its
## _apply() is what calls it; called here too in case a hook is missing).
func _process(_dt: float) -> void:
	ShadowTuning.follow(_sun, get_viewport().get_camera_3d())


func _e(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _ready() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	for keep in ["WorldEnvironment", "Sun", "DayNight"]:
		var n: Node = city.get_node_or_null(keep)
		if n:
			city.remove_child(n)
			n.owner = null
			add_child(n)
	city.free()
	_dn = get_node_or_null("DayNight")
	if _dn and _dn.has_method("set_paused"):
		_dn.call("set_paused", true)
	_sun = get_node_or_null("Sun") as DirectionalLight3D
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	_env = we.environment if we else null
	_base_env = _env.duplicate() if _env else null
	_build_set()
	var cam := Camera3D.new()
	cam.fov = float(_e("FOV", "55"))
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()
	var eyes: Array = [_e("EYE", "0,1.7,14,0,-6,12")]
	for s in _e("SHOTS", "").split(";", false):
		eyes.append(s)
	var variants: Array = []
	for v in _e("VARIANTS", "").split(";", false):
		variants.append(v)
	if variants.is_empty():
		variants.append("")
	var out := _e("OUT", "build/sr/lab.png")
	for k in eyes.size():
		var p: PackedStringArray = (eyes[k] as String).split(",")
		var basis := Basis.from_euler(Vector3(deg_to_rad(p[4].to_float()), deg_to_rad(p[3].to_float()), 0.0))
		cam.global_transform = Transform3D(basis, Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float()))
		for vi in variants.size():
			_setup(str(variants[vi]), p[5].to_float() if p.size() > 5 else 12.0)
			for i in int(_e("FRAMES", "24")):
				await get_tree().process_frame
			if _e("PROFILE", "") == "1":
				print("GPU_PROFILE_BEGIN shot %d variant %d [%s]" % [k, vi, variants[vi]])
				for i in int(_e("SAMPLES", "6")):
					await get_tree().process_frame
				print("GPU_PROFILE_END")
			var file := out.get_basename() + "_%d_%d.png" % [k, vi]
			get_viewport().get_texture().get_image().save_png(file)
			print("saved ", file, " [", variants[vi], "] air ", ShadowTuning.air, " max ", _sun.directional_shadow_max_distance, " splits ", _sun.directional_shadow_split_1, "/", _sun.directional_shadow_split_2, "/", _sun.directional_shadow_split_3, " fade ", _sun.directional_shadow_fade_start)
	print("DONE")
	OS.kill(OS.get_process_id())


func _setup(spec: String, hour: float) -> void:
	var q := 0
	var st := ShadowTuning.enabled
	var sun_yaw := 0.0
	var sets: Array = []
	for tok in spec.split(" ", false):
		if tok.begins_with("Q="):
			q = tok.trim_prefix("Q=").to_int()
		elif tok.begins_with("ST="):
			st = tok.trim_prefix("ST=") != "0"
		elif tok.begins_with("CS="):
			var inst := ContactShadows.instance()
			if inst:
				for c in inst.get_children():
					(c as Node3D).visible = tok != "CS=0"
		elif tok.begins_with("SUN_YAW="):
			sun_yaw = tok.trim_prefix("SUN_YAW=").to_float()
		else:
			sets.append(tok)
	# The environment as city.tscn has it, then Quality's switches for the level.
	for pr in _base_env.get_property_list():
		if pr.usage & PROPERTY_USAGE_STORAGE:
			_env.set(pr.name, _base_env.get(pr.name))
	_env.sdfgi_enabled = q == 0
	_env.volumetric_fog_enabled = q == 0
	_env.ssil_enabled = q <= 1
	_env.ssr_enabled = q <= 1
	_env.ssao_enabled = q <= 2
	GiTuning.apply(_env, _sun, q)
	# The sun as Quality leaves it, ShadowTuning's numbers on top (or the old ones without).
	_sun.directional_shadow_split_1 = ShadowTuning.OLD_SPLITS[0]
	_sun.directional_shadow_split_2 = ShadowTuning.OLD_SPLITS[1]
	_sun.directional_shadow_split_3 = ShadowTuning.OLD_SPLITS[2]
	_sun.directional_shadow_fade_start = ShadowTuning.OLD_FADE
	ShadowTuning.reset()
	ShadowTuning.enabled = st
	ShadowTuning.apply_level(_sun, q)
	if _dn:
		_dn.set("hour", hour)
		_dn.call("_apply")
	if sun_yaw != 0.0:
		_sun.global_rotate(Vector3.UP, deg_to_rad(sun_yaw))
	for tok in sets:
		var kv: PackedStringArray = String(tok).split("=")
		if kv.size() != 2:
			continue
		var target: Object = _sun if kv[0].begins_with("sun.") else _env
		var prop := kv[0].trim_prefix("sun.").trim_prefix("env.")
		var cur: Variant = target.get(prop)
		var v: Variant = kv[1]
		if cur is bool:
			v = kv[1] == "1" or kv[1] == "true"
		elif cur is float:
			v = kv[1].to_float()
		elif cur is int:
			v = kv[1].to_int()
		target.set(prop, v)
	print("VARIANT [", spec, "] hour ", hour, " st ", st, " max ", _sun.directional_shadow_max_distance,
		" splits ", _sun.directional_shadow_split_1, "/", _sun.directional_shadow_split_2, "/", _sun.directional_shadow_split_3,
		" bias ", _sun.shadow_bias, " nbias ", _sun.shadow_normal_bias, " blur ", _sun.shadow_blur,
		" ang ", _sun.light_angular_distance, " pancake ", _sun.directional_shadow_pancake_size)


## The set, north of the eye (the default EYE stands at z 14 looking north, -Z).
func _build_set() -> void:
	var road := PropFactory.road("asphalt", 6.0, Color(0.42, 0.42, 0.43), 7)
	_box(Vector3(0, -0.05, -300), Vector3(1200, 0.1, 1200), road, true)
	var walk := PropFactory.road("sidewalk", 3.0, Color(0.72, 0.71, 0.68), 11, 1.5, 0.3)
	# Pavement on the west side, a 15 cm kerb.
	_box(Vector3(-11, 0.075, -300), Vector3(6, 0.15, 1200), walk, true)
	# Two building blocks behind it (a wall the shadows land on and a canyon to look down).
	var wall := PropFactory.pbr("plaster_beige", 4.0)
	_box(Vector3(-24, 9, -30), Vector3(20, 18, 40), wall, true)
	_box(Vector3(-24, 14, -80), Vector3(20, 28, 40), PropFactory.pbr("concrete_painted", 4.0), true)
	_box(Vector3(26, 12, -60), Vector3(20, 24, 60), PropFactory.pbr("brick_red", 3.0), true)
	# The car (asleep on its wheels), a second one further up.
	_car(Vector3(4.2, 0, -2), 0, Color(0.86, 0.87, 0.88))
	_car(Vector3(-5.5, 0, -18), 1, Color(0.45, 0.06, 0.05))
	# People on the pavement.
	_person(0, Vector3(-9.5, 0.15, 2.0), 0.2)
	_person(3, Vector3(-10.5, 0.15, -4.0), 0.6)
	# Planting and street furniture through one batch, the way a chunk draws them (shadow twins).
	var batch := MultiMeshBatch.new()
	batch.add("tree_0", PropFactory.model_tree(0), Transform3D(Basis.IDENTITY, Vector3(-12, 0.15, -8)))
	batch.add("palm_0", PropFactory.palm(0), Transform3D(Basis.IDENTITY, Vector3(-12, 0.15, -26)))
	var lamp := StreetLamps.mesh(0)
	if lamp:
		batch.add("lamp_0", lamp, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-8.6, 0.15, 6)))
	# Posts every 10 m out to 300 m, 1 m west of the kerb line: where the cascades hand over.
	var post := BoxMesh.new()
	post.size = Vector3(0.18, 2.4, 0.18)
	post.material = PropFactory.pbr("metal_painted", 1.0)
	var cube := BoxMesh.new()
	cube.size = Vector3(0.6, 0.6, 0.6)
	cube.material = PropFactory.pbr("concrete", 2.0)
	for i in range(1, 31):
		batch.add("post", post, Transform3D(Basis.IDENTITY, Vector3(-7.4, 1.35, -10.0 * i + 8.0)))
		batch.add("cube", cube, Transform3D(Basis.IDENTITY, Vector3(7.0, 0.3, -10.0 * i + 8.0)))
	batch.build(self)


func _box(c: Vector3, s: Vector3, mat: Material, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = mat
	mi.position = c
	add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = s
		cs.shape = sh
		sb.add_child(cs)
		sb.position = c
		add_child(sb)


func _car(at: Vector3, type: int, paint: Color) -> void:
	var car = (load("res://scripts/vehicles/vehicle.gd") as GDScript).new()
	car.call("setup", type, paint, 0)
	car.position = at + Vector3(0, 0.9, 0)
	add_child(car)


func _person(model: int, at: Vector3, phase: float) -> void:
	var ped := load("res://scripts/npc/pedestrian.gd") as GDScript
	var path: String = ped.MODELS[model]
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	inst.position = at
	inst.rotation.y = 0.7
	add_child(inst)
	ped.prepare_rig(inst, 0)
	var anims := inst.find_children("*", "AnimationPlayer", true, false)
	if not anims.is_empty():
		var ap: AnimationPlayer = anims[0]
		ped.fix_arm_pose(ap, path)
		for clip in ["Walk", "walk", "Idle", "idle"]:
			if ap.has_animation(clip):
				ap.play(clip)
				ap.seek(ap.get_animation(clip).length * phase, true)
				ap.pause()
				break
