extends RefCounted
## The "wingsuit" staging of a reference camera (tools/refcams/cameras_w8.json, wingsuit_golden):
## the hero gliding in his wingsuit, and the shot taken from his OWN chase camera (the CameraRig
## the suit drives), not the free eye. Loaded by path from refcams_shot.gd once the autoloads exist.
##
## The camera row's "wingsuit" key (every field optional):
##   {"at": [x, y, z],        where he is at the shot, TRUE world; y over the plan's ground
##    "heading": 180.0,       his heading in degrees (yaw: 0 flies north, -Z)
##    "speed": 48.0,          airspeed at the launch (m/s)
##    "lead": 2.5,            seconds of gliding before the shot (the suit spreads, the vapour grows)
##    "input": [0.0, 0.0],    the stick held through the glide (roll, pitch as the move axes give it)
##    "dist": 6.0,            the chase camera's distance behind him (m)
##    "look": [0.0, -12.0],   the camera's yaw off his heading and its pitch (degrees)
##    "fov": 60.0}
## He is launched `lead` seconds back along the trim glide path so he passes `at` near the shot;
## the lead-in runs with the 3D rendering off (seconds a frame on the software renderer), the last
## half second drawn so the vapour, the fabric and the motion are a real frame's.

const TRIM_DEG := 14.0

var tree: SceneTree
var city: Node
var player: Player
var suit: Node
var rig: Node3D
var _heading := 0.0
var _look := Vector2(0.0, -12.0)
var _police_was := true
var _fov_was := -1.0


func run(st: SceneTree, cam: Dictionary, p: Node3D) -> void:
	tree = st
	city = tree.current_scene
	player = p as Player
	suit = player.get("wingsuit")
	rig = player.get_node("CameraRig")
	var d: Dictionary = cam.get("wingsuit", {})
	var plan: CityPlan = city.get("plan")
	var at_a: Array = d.get("at", [2500.0, 120.0, -500.0])
	var target := Vector3(float(at_a[0]), float(at_a[1]), float(at_a[2]))
	target.y += plan.height_at(Vector2(target.x, target.z))
	_heading = deg_to_rad(float(d.get("heading", 180.0)))
	var speed := float(d.get("speed", 48.0))
	var lead := float(d.get("lead", 2.5))
	var look_a: Array = d.get("look", [0.0, -12.0])
	_look = Vector2(float(look_a[0]), float(look_a[1]))
	var police: Node = city.get_node_or_null("Police")
	if police:
		_police_was = bool(police.get("enabled"))
		police.set("enabled", false)
	if suit == null:
		push_error("refcams wingsuit: the player has no wingsuit (WINGSUIT=0?)")
		return
	# Stream the city round where he will be at the shot first.
	player.visible = true
	for i in 6:
		_hold_at(target)
		city.call("update_streaming", true)
		await tree.process_frame
	# Launch him back along the trim glide path.
	var trim := deg_to_rad(TRIM_DEG)
	var dir := Basis(Vector3.UP, _heading) * Basis(Vector3.RIGHT, -trim) * Vector3.FORWARD
	var start := target - dir * speed * lead
	player.global_position = WorldState.to_local(start)
	player.velocity = dir * speed
	(player.get_node("Visual") as Node3D).rotation.y = _heading
	suit.call("open")
	var inp: Array = d.get("input", [0.0, 0.0])
	suit.call("force_input", Vector2(float(inp[0]), float(inp[1])))
	var base_dist := float(suit.get("_base_distance"))
	suit.set("camera_extra", float(d.get("dist", 6.0)) - base_dist)
	var fov := float(d.get("fov", 60.0))
	_fov_was = float(suit.get("_base_fov"))
	suit.set("_base_fov", fov)
	suit.set("fov_extra", 0.0)
	rig.set("camera_fov", fov)
	rig.set("boost_fov_boost", 0.0)
	suit.set("chase_after", 1.0e9)
	player.camera.make_current()
	tree.root.disable_3d = true
	await _fly(lead - 0.5)
	tree.root.disable_3d = false
	city.call("update_streaming", true)
	await _fly(0.5)
	var w := WorldState.to_world(player.global_position)
	var dn: Node = city.get_node_or_null("DayNight")
	var sun: Node3D = dn.get("_sun") if dn else null
	if sun:
		print("REFCAM wingsuit: sun toward %s, night_factor %.2f, lamp_factor %.2f" % [str(sun.global_basis.z), float(dn.get("night_factor")), float(dn.get("lamp_now"))])
	var fx: Node = suit.get_node_or_null("WingsuitFx")
	print("REFCAM wingsuit: at %s (wanted %s), %.1f m over the ground, %.1f m/s, gliding %s, vapour %s, camera %s" % [
		str(w), str(target), w.y - plan.height_at(Vector2(w.x, w.z)), player.velocity.length(),
		str(suit.call("is_gliding")), str(fx.call("is_trailing") if fx else "-"), str(WorldState.to_world(player.camera.global_position))])


func _hold_at(world: Vector3) -> void:
	player.global_position = WorldState.to_local(world)
	player.velocity = Vector3.ZERO


func _fly(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		_aim()
		await tree.physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	_aim()


func _aim() -> void:
	var hd := rad_to_deg(float(suit.get("heading")))
	rig.call("set_look", hd + _look.x, _look.y)


## Keeps the camera on him while the shot settles (refcams' SETTLE frames at a crawling time scale).
func hold() -> void:
	if suit:
		_aim()


func debug(_out_dir: String) -> void:
	pass


## Puts everything back for the next camera: the suit folded, his camera as it was, the police on.
func finish() -> void:
	if suit:
		suit.call("force_input", Vector2.INF)
		if _fov_was > 0.0:
			suit.set("_base_fov", _fov_was)
		suit.call("close", false)
		suit.set("chase_after", 1.2)
		suit.set("camera_extra", 2.5)
		suit.set("fov_extra", 16.0)
	player.velocity = Vector3.ZERO
	player.visible = false
	var police: Node = city.get_node_or_null("Police")
	if police:
		police.set("enabled", _police_was)
