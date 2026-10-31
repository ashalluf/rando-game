extends SceneTree
## The guns at arm's length (docs/HANDOFF.md "Gunplay at arm's length"): the real player in the
## test room, a wall of one surface in front of him, a free camera on the hands, the trigger held
## and the picture saved at set moments of game time - the muzzle flash on the hands and the
## wall, tracers, brass in flight, the recoil, the smoke after the burst, the holes left behind.
##
##   OUT=/tmp/strip WEAPON=1 SURF=concrete LIGHT=night xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/gunplay/gun_strip.gd --resolution 960x540
##
## Env: OUT (file prefix: <OUT>_<i>.png), WEAPON 1 the AK, 3 the shotgun; SURF concrete | metal
## | wood | dirt (what the wall in front is); WALL metres to it (7); LIGHT day | night (the
## sun off and the sky dark: the flash is the only light); VIEW side (the hands from his right,
## the default) | behind (over the shoulder, the gameplay camera) | wall (the wall, close) | far
## (side, further back: the tracers' run); FIRE_TIME seconds of trigger (game time, 0.5); STRIP
## the moments to save, seconds of game time from the trigger (default
## "0.02,0.07,0.16,0.45,1.4,3.0"); SCALE the clock while it runs (0.04: a frame is a tick or so).
## GUNPLAY_FEEL=0 is the before.

const SURFS := ["concrete", "metal", "wood", "dirt"]


func _initialize() -> void:
	var level: Node = (load("res://scenes/levels/test_box.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var player := get_first_node_in_group("player") as Node3D
	var rig: Node = player.get("camera_rig")
	rig.call("set_look", 0.0, 0.0)
	var night := _env("LIGHT", "day") == "night"
	if night:
		var we := level.get_node("WorldEnvironment") as WorldEnvironment
		var e := we.environment
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.01, 0.012, 0.02)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.12, 0.14, 0.2)
		e.ambient_light_energy = 0.12
		e.fog_enabled = false
		(level.get_node("Sun") as DirectionalLight3D).light_energy = 0.0
	var hud := level.get_node_or_null("DebugHud") as CanvasLayer
	if hud != null and _env("HUD", "0") != "1":
		hud.visible = false
	var p0 := player.global_position
	var wall_d := float(_env("WALL", "7"))
	var surf := _env("SURF", "concrete")
	_wall(level, p0 + Vector3(0.0, 1.5, -wall_d), surf)
	# A floor of the same stuff at his feet would hide the brass: the room's own floor stays.
	var slot := _env("WEAPON", "1")
	Input.action_press("weapon_%s" % slot)
	await process_frame
	Input.action_release("weapon_%s" % slot)
	for i in 12:
		await process_frame
	Input.action_press("alt_fire")
	for i in 30:
		await process_frame
	var cam := Camera3D.new()
	cam.fov = float(_env("FOV", "50"))
	cam.far = 400.0
	level.add_child(cam)
	cam.current = true
	_place(cam, player, wall_d)
	var strip: Array = []
	for s in _env("STRIP", "0.02,0.07,0.16,0.45,1.4,3.0").split(","):
		strip.append(float(s))
	var out := _env("OUT", "/tmp/gun_strip")
	var fire_time := float(_env("FIRE_TIME", "0.5"))
	Engine.time_scale = float(_env("SCALE", "0.04"))
	Input.action_press("fire")
	var t := 0.0
	var k := 0
	var held := true
	while k < strip.size():
		await process_frame
		t += root.get_process_delta_time()
		if held and t >= fire_time:
			Input.action_release("fire")
			held = false
		_place(cam, player, wall_d)
		if t >= float(strip[k]):
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.save_png("%s_%d.png" % [out, k])
			print("STRIP %d t=%.3f -> %s_%d.png" % [k, t, out, k])
			k += 1
	Input.action_release("fire")
	Input.action_release("alt_fire")
	quit()


## The camera, placed off the gun in hand each frame (the hero sways; the shot is the hands).
func _place(cam: Camera3D, player: Node3D, wall_d: float) -> void:
	var p := player.global_position
	var wm: Node = player.get("weapon_manager")
	var gun := wm.get("current") as Node3D if wm != null else null
	var g := gun.global_position if gun != null else p + Vector3(0.2, 0.5, -0.4)
	var view := _env("VIEW", "side")
	var eye := Vector3.ZERO
	var look := Vector3.ZERO
	match view:
		"behind":
			eye = g + Vector3(0.45, 0.32, 1.7)
			look = g + Vector3(-0.1, 0.0, -wall_d)
		"wall":
			eye = p + Vector3(1.7, 1.2, -wall_d + 2.8)
			look = p + Vector3(0.0, 0.6, -wall_d)
		"far":
			eye = g + Vector3(4.0, 0.6, -wall_d * 0.5)
			look = g + Vector3(0.0, 0.0, -wall_d * 0.5)
		"front":
			eye = g + Vector3(1.1, 0.2, -1.9)
			look = g + Vector3(0.0, 0.0, -0.3)
		_:
			eye = g + Vector3(1.25, 0.18, -0.35)
			look = g + Vector3(0.0, 0.0, -0.45)
	cam.look_at_from_position(eye, look, Vector3.UP)


## A 5 x 3.5 m wall of one surface, the way WeaponFX.classify() reads it.
func _wall(level: Node, at: Vector3, surf: String) -> void:
	var body: CollisionObject3D
	if surf == "wood":
		var rb := RigidBody3D.new()
		rb.freeze = true
		body = rb
	else:
		body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	if surf == "metal":
		body.add_to_group("rail_vehicle")
	elif surf == "dirt":
		body.set_meta("terrain", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.5, 0.4)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = {"concrete": Color(0.55, 0.53, 0.5), "metal": Color(0.25, 0.32, 0.4),
		"wood": Color(0.45, 0.32, 0.2), "dirt": Color(0.42, 0.34, 0.25)}.get(surf, Color(0.5, 0.5, 0.5))
	mat.roughness = 0.35 if surf == "metal" else 0.9
	mat.metallic = 0.6 if surf == "metal" else 0.0
	mesh.material_override = mat
	body.add_child(mesh)
	level.add_child(body)
	body.global_position = at


static func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback
