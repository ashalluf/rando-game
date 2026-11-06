extends RefCounted
## The "boat" staging of a reference camera (tools/refcams/cameras_w8.json, speedboat_golden): the
## player at the helm of a fresh SALTRUNNER (or WAVEKITE) under way off the coast, the throttle held
## long enough for the wake and spray to build, and a free chase eye placed off the boat's own frame
## every frame up to the shot. Loaded by path from refcams_shot.gd once the autoloads exist (it
## names Boat, BoatKit and Player). Same interface as chase_stage.gd: run(), hold(), debug(), finish().
##
## The camera row's "boat" key (every field optional):
##   {"at": [x, z],          TRUE world start; default 260 m off the beach south of the marina
##    "heading": 90.0,       degrees, the --spawn yaw (0 north, 90 west)
##    "kind": "speedboat",   or "jetski"
##    "look": 11,            BoatKit look (paint) hash
##    "boost": 0,            1 holds the boost too
##    "steer": 0.0,          -1..1 helm held over the last second (a carve)
##    "ticks": 420,          physics ticks under way before the shot
##    "chase": [back, side, up, ahead]}  the eye: metres behind the hull, to its right, over the
##                           water, and how far ahead of the hull the lens aims
## The row's eye is unused (its yaw / pitch are worked out); hour, weather and fov are the row's.

var tree: SceneTree
var city: Node
var player: Player
var boat: Boat
var _chase := [11.0, 1.5, 3.4, 6.0]
var _fov := 55.0
var _heading := 0.0
var _police_was := true


func run(st: SceneTree, cam: Dictionary, p: Node3D) -> void:
	tree = st
	city = tree.current_scene
	player = p as Player
	_fov = float(cam.get("fov", 55.0))
	var d: Dictionary = cam.get("boat", {}) if cam.get("boat", null) is Dictionary else {}
	if d.get("chase", null) is Array and (d.chase as Array).size() >= 4:
		_chase = d.chase
	var plan: CityPlan = city.get("plan")
	var m: MacroMap = plan.macro if plan else null
	if m == null or player == null:
		push_error("refcams boat: no plan or player")
		return
	var police: Node = city.get_node_or_null("Police")
	if police:
		_police_was = bool(police.get("enabled"))
		police.set("enabled", false)
	var at2 := Vector2.ZERO
	if d.get("at", null) is Array:
		at2 = Vector2(float(d.at[0]), float(d.at[1]))
	elif m.marina != null:
		at2 = Vector2(m.coast_x(m.marina.zc + 700.0) - 260.0, m.marina.zc + 700.0)
	_heading = deg_to_rad(float(d.get("heading", 90.0)))
	var k := BoatKit.Kind.JETSKI if String(d.get("kind", "speedboat")) == "jetski" else BoatKit.Kind.SPEEDBOAT
	# Out of whatever he was in, on foot at the start (the hero camera rows leave him walking).
	if player.get("vehicle") != null:
		player.exit_vehicle()
	player.visible = true
	# The world re-centred on the start and its sea built BEFORE the boat goes in: placed from a
	# far spawn, a re-centre pending on the next frames put her hundreds of metres off (on land).
	for i in 12:
		player.global_position = WorldState.to_local(Vector3(at2.x, 2.0, at2.y))
		player.set("velocity", Vector3.ZERO)
		city.call("update_streaming", true)
		await tree.process_frame
	if city.has_method("ensure_loaded_at"):
		city.call("ensure_loaded_at", WorldState.to_local(Vector3(at2.x, 0.0, at2.y)))
	await tree.physics_frame
	await tree.physics_frame
	boat = Boat.new()
	boat.name = "RefcamBoat"
	boat.setup_boat(k, int(d.get("look", 11)))
	boat.position = WorldState.to_local(Vector3(at2.x, 0.4, at2.y))
	boat.rotation.y = _heading
	city.add_child(boat)
	player.global_position = boat.global_position + Vector3.UP
	player.enter_vehicle(boat)
	city.call("update_streaming", true)
	await tree.physics_frame
	var fwd := Vector3(-sin(_heading), 0.0, -cos(_heading))
	boat.linear_velocity = fwd * (16.0 if k == BoatKit.Kind.SPEEDBOAT else 18.0)
	Input.action_press("move_forward")
	if int(d.get("boost", 0)) == 1:
		Input.action_press("boost")
	var steer := float(d.get("steer", 0.0))
	var ticks := int(d.get("ticks", 420))
	for i in ticks:
		if absf(steer) > 0.01 and i > ticks - 60:
			Input.action_press("move_right" if steer > 0.0 else "move_left", absf(steer))
		await tree.physics_frame
		if i % 8 == 0:
			hold()
		if i % 60 == 0:
			print("REFCAM boat tick %d at %s v %s thr %.2f wet %.2f" % [i, str(WorldState.to_world(boat.global_position).snapped(Vector3.ONE * 0.1)), str(boat.linear_velocity.snapped(Vector3.ONE * 0.1)), boat.throttle, float(boat.get("wet"))])
	city.call("update_streaming", true)
	# A few drawn frames with the eye on the boat, so the chunks round the lens stand.
	for i in 12:
		await tree.process_frame
		hold()
	var bw := WorldState.to_world(boat.global_position)
	print("REFCAM boat at %s speed %.1f m/s wet %.2f heading %.1f" % [str(bw.snapped(Vector3.ONE * 0.1)), boat.linear_velocity.length(), float(boat.get("wet")), rad_to_deg(_heading)])


## The free eye behind the hull: placed off the boat's heading (levelled, so the lens does not
## pitch and roll with every swell), aimed a few metres ahead of the bow.
func hold() -> void:
	if not is_instance_valid(boat):
		return
	var b := boat.global_basis
	var f := Vector3(-b.z.x, 0.0, -b.z.z)
	if f.length() < 0.01:
		f = Vector3(-sin(_heading), 0.0, -cos(_heading))
	f = f.normalized()
	var r := Vector3(-f.z, 0.0, f.x)
	var bw := WorldState.to_world(boat.global_position)
	var base := Vector3(bw.x, 0.0, bw.z)
	var eye := base - f * float(_chase[0]) + r * float(_chase[1]) + Vector3.UP * float(_chase[2])
	var look := base + f * float(_chase[3]) + Vector3.UP * 0.6
	var dv := (look - eye).normalized()
	var yaw := rad_to_deg(atan2(-dv.x, -dv.z))
	var pitch := rad_to_deg(asin(dv.y))
	OS.set_environment("EYE", "%.3f,%.3f,%.3f,%.3f,%.3f" % [eye.x, eye.y, eye.z, yaw, pitch])
	OS.set_environment("EYE_KEEP_PLAYER", "1")
	OS.set_environment("EYE_AGL", "")
	tree.call("_eye", player, _fov)


func debug(_out_dir: String) -> void:
	pass


## Everything put back for the next camera: the throttle let go, the player out, the boat gone.
func finish() -> void:
	for a: String in ["move_forward", "boost", "move_left", "move_right"]:
		Input.action_release(a)
	OS.set_environment("EYE_KEEP_PLAYER", "")
	if is_instance_valid(boat):
		if player.get("vehicle") == boat:
			player.exit_vehicle()
		boat.queue_free()
	player.visible = false
	var police: Node = city.get_node_or_null("Police")
	if police:
		police.set("enabled", _police_was)
