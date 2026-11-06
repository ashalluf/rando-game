extends RefCounted
## The "pursuit" staging of a reference camera (tools/refcams/cameras_w8.json, police_pursuit): a
## police chase round the player's car of a "drive" row (chase_stage.gd). Loaded by path from
## chase_stage.gd once the autoloads exist (it names Police, PoliceCar and Vehicle).
##
## The drive row's optional "pursuit" key (every field optional):
##   {"stars": 3,                        the wanted level (the light bars, the sirens, the helicopter)
##    "cruisers": [[behind, across], ...] cruisers `behind` metres back from the player's car (centre
##                                        to centre, along the way he drives) and `across` metres to
##                                        his right, driven at his speed
##    "heli": [dist, side, height],       the police helicopter staged that far ahead of the car's
##                                        camera, `side` to its right, its searchlight on him; height
##                                        over the default orbit height (0 = AirTraffic's own)
##    "look": [yaw, pitch]}               the chase camera turned off its chase view (degrees, yaw to
##                                        the left +), held there: a look round at what follows him
## The police are switched on but dispatch nothing of their own (caps zero, no roadblocks, nobody
## shooting, the trail never lost); the staged cruisers are `scripted` (their own driving off) and
## held at the player's speed every physics tick like his car, mask world only so nothing they
## touch stops them. POLICE_PURSUIT=0 in the environment stages none of it (the A/B of the staging).

var tree: SceneTree
var city: Node
var police: Node
var air: Node
var cruisers: Array = []
var offsets: Array = []
var _saved := {}
var _look := Vector2.ZERO
var _has_look := false
var heli: Node = null
var _fx: Node = null
var _saved_spark := 4.0


static func wanted(cam: Dictionary) -> bool:
	return OS.get_environment("POLICE_PURSUIT") != "0" and (cam.get("drive", {}) as Dictionary).has("pursuit")


## Before the lead-in: the stars, the cruisers at their places round `car` (already on the road,
## facing `fwd`), the helicopter.
func run(st: SceneTree, cam: Dictionary, car: Vehicle, fwd: Vector3, player: Node) -> void:
	tree = st
	city = tree.current_scene
	var p: Dictionary = (cam.get("drive", {}) as Dictionary).get("pursuit", {})
	police = city.get_node_or_null("Police")
	if police == null:
		print("REFCAM pursuit: no Police node")
		return
	police.call("_ensure_refs")
	for key in ["cruisers_per_star", "officers_per_star", "roadblock_stars", "heavy_stars", "lose_seconds", "accuracy_base"]:
		_saved[key] = police.get(key)
	police.set("cruisers_per_star", PackedInt32Array([0, 0, 0, 0, 0, 0]))
	police.set("officers_per_star", PackedInt32Array([0, 0, 0, 0, 0, 0]))
	police.set("roadblock_stars", 99)
	police.set("heavy_stars", 99)
	police.set("lose_seconds", 1.0e6)
	police.set("accuracy_base", 0.0)
	police.set("enabled", true)
	police.call("set_wanted", int(p.get("stars", 3)))
	# Cars held at speed by velocity scrape sparks off whatever their bodies touch (DrivingFX): not
	# what a driven chase on a straight throws. Put back in finish().
	_fx = city.get_node_or_null("DrivingFX")
	if _fx:
		_saved_spark = float(_fx.get("spark_speed"))
		_fx.set("spark_speed", 1.0e6)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var yaw := atan2(-fwd.x, -fwd.z)
	var at := WorldState.to_world(car.global_position)
	for row: Array in p.get("cruisers", []):
		var off := -fwd * float(row[0]) + right * float(row[1])
		var w := at + off
		w.y = _road_top(car, w) + 0.9
		var c: Variant = police.call("spawn_cruiser", w, yaw, "pursue")
		if c == null:
			continue
		var pc := c as Vehicle
		pc.set("scripted", true)
		pc.set("mode", 1) # PURSUE: the siren and the bar run
		pc.collision_mask = 1
		pc.hold_crash_watch(6)
		cruisers.append(pc)
		offsets.append(Vector2(float(row[0]), float(row[1])))
	if p.has("look"):
		var l: Array = p.look
		_look = Vector2(deg_to_rad(float(l[0])), deg_to_rad(float(l[1]) if l.size() > 1 else 0.0))
		_has_look = true
	# The helicopter: staged from the player's camera (AirTraffic.stage("police")), which follows him.
	air = city.get_node_or_null("AirTraffic")
	if air and p.has("heli"):
		var h: Array = p.heli
		var pcam := player.get("camera") as Camera3D
		if pcam:
			var lift := float(h[2]) if h.size() > 2 else 0.0
			var keep: float = float(air.get("police_orbit_height"))
			air.set("police_orbit_height", keep + lift)
			heli = air.call("stage", "police", pcam, float(h[0]), float(h[1]) if h.size() > 1 else 0.0)
			air.set("police_orbit_height", keep)
	print("REFCAM pursuit: %d stars, %d cruisers, heli %s" % [int(police.get("stars")), cruisers.size(), heli.name if heli else "none"])


## Every physics tick of the lead-in and the settle: the cruisers kept at the player's speed, in
## their lanes, and the camera's look held.
func steer(car: Vehicle, v: float, player: Node) -> void:
	var f := -car.global_basis.z
	f.y = 0.0
	f = f.normalized()
	for i in cruisers.size():
		var c: Vehicle = cruisers[i]
		if not is_instance_valid(c):
			continue
		var right := Vector3(-f.z, 0.0, f.x)
		var o: Vector2 = offsets[i]
		var want: Vector3 = car.global_position - f * o.x + right * o.y
		var err: Vector3 = want - c.global_position
		err.y = 0.0
		var cf := -c.global_basis.z
		cf.y = 0.0
		cf = cf.normalized()
		var vel: Vector3 = f * v + err * 1.5
		c.linear_velocity = Vector3(vel.x, c.linear_velocity.y, vel.z)
		var turn := cf.signed_angle_to(f, Vector3.UP)
		c.angular_velocity = Vector3(c.angular_velocity.x * 0.5, turn * 3.0, c.angular_velocity.z * 0.5)
		c.hold_crash_watch(2)
		# Nobody's foot on the brake (an empty car holds its parking brake: the wheels skidded and
		# DrivingFX threw smoke and sparks off a car rolling straight).
		c.brake = 0.0
		c.engine_force = 0.0
	police.call("report_sighting")
	if _has_look:
		var dc: Node = _drive_cam(player)
		if dc:
			dc.set("_free_yaw", float(dc.get("_chase_yaw")) + _look.x)
			dc.set("_free_pitch", float(dc.get("_chase_pitch")) + _look.y)
			dc.set("_auto", 0.0)
			dc.set("_hold", 1.0e6)


func _drive_cam(player: Node) -> Node:
	for n in player.find_children("*", "Node", true, false):
		if n.get_script() and String((n.get_script() as Script).resource_path).ends_with("drive_cam.gd"):
			return n
	return null


func _road_top(car: Vehicle, world: Vector3) -> float:
	var plan: Variant = city.get("plan")
	var gy: float = plan.height_at(Vector2(world.x, world.z)) if plan else world.y
	var top := WorldState.to_local(Vector3(world.x, gy + 40.0, world.z))
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 80.0, 1)
	q.exclude = [car.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
	return WorldState.to_world(hit.position).y if not hit.is_empty() else gy


## After the shot: the chase stood down and the police as they were.
func finish() -> void:
	if police == null:
		return
	police.call("clear")
	if is_instance_valid(_fx):
		_fx.set("spark_speed", _saved_spark)
	for key in _saved:
		police.set(key, _saved[key])
	if air and air.has_method("clear_all"):
		air.set("forced_stars", -1)
	print("REFCAM pursuit: stood down")


## PURSUIT_AB=1: the frame again with each piece of the chase hidden in turn (the helicopter's
## pool, its light, its shaft; the cruisers' glows; the cruisers' real lights), saved as
## pab_<piece>.png in `out_dir`.
func ab(out_dir: String) -> void:
	for c in cruisers:
		if not is_instance_valid(c):
			continue
		var g: Node = c.get_node_or_null("PoliceGlow")
		var walls := ""
		if g:
			for w in ["WallA", "WallB"]:
				var wm := g.get_node_or_null(w) as Node3D
				walls += " %s found %s at %s" % [w, str(wm.get_meta("found", false)), str(WorldState.to_world(wm.global_position).round())] if wm else ""
		print("REFCAM pursuit cruiser monitor %s max %d mask %d layer %d wheels %d" % [str(c.contact_monitor), c.max_contacts_reported, c.collision_mask, c.collision_layer, c.find_children("*", "VehicleWheel3D", true, false).size()])
		for wh in c.find_children("*", "VehicleWheel3D", true, false):
			var vw := wh as VehicleWheel3D
			print("REFCAM pursuit wheel contact %s skid %.2f rpm %.0f" % [str(vw.is_in_contact()), vw.get_skidinfo(), vw.get_rpm()])
		var st := PhysicsServer3D.body_get_direct_state(c.get_rid())
		for k in st.get_contact_count():
			var o: Object = st.get_contact_collider_object(k)
			print("REFCAM pursuit contact %s local %s v %.1f" % [str(o.get_path()) if o is Node else str(o), str(st.get_contact_local_position(k) - st.transform.origin), c.linear_velocity.length()])
		if g and g.has_meta("mat"):
			var gm: ShaderMaterial = g.get_meta("mat")
			print("REFCAM pursuit wash point_pool %s pattern %s side %d" % [str(gm.get_shader_parameter("point_pool")), str(gm.get_shader_parameter("pattern")), int(c.call("flash_side", PoliceNightLook.clock))])
		print("REFCAM pursuit cruiser %s at %s lit %s glow %s%s" % [c.name, str(WorldState.to_world(c.global_position).round()), str(c.call("bar_lit")), str(g.visible) if g else "none", walls])
	if OS.get_environment("PURSUIT_AB") != "1":
		return
	var sets := {}
	if air:
		var crafts := []
		for h in air.get_children():
			if h is Node3D and (h as Node3D).visible:
				print("PURSUIT_AB aircraft %s at %s" % [h.name, str((h as Node3D).global_position)])
				crafts.append(h)
		sets["air_all"] = crafts
	var glows := []
	for c in cruisers:
		if is_instance_valid(c) and c.get_node_or_null("PoliceGlow"):
			glows.append(c.get_node("PoliceGlow"))
	sets["glows"] = glows
	var nl := []
	for c in cruisers:
		if is_instance_valid(c) and c.get_node_or_null("NightLights"):
			nl.append(c.get_node("NightLights"))
	sets["cruiser_nightlights"] = nl
	if heli and is_instance_valid(heli):
		var hl := []
		for n in ["Pool", "Searchlight"]:
			var x: Node = heli.find_child(n, true, false)
			if x:
				hl.append(x)
		sets["heli_light_all"] = hl
	var lights := []
	for n in tree.root.find_children("*", "OmniLight3D", true, false):
		if (n as Node3D).is_visible_in_tree() and n.get_parent() is PoliceNightLook:
			lights.append(n)
	sets["police_lights"] = lights
	var spots := []
	var omnis := []
	var cam := tree.root.get_viewport().get_camera_3d()
	for n in tree.root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if not l.is_visible_in_tree() or l is DirectionalLight3D:
			continue
		if l is SpotLight3D:
			spots.append(l)
			print("PURSUIT_AB spot %s energy %.1f at %.0f m" % [str(l.get_path()), l.light_energy, l.global_position.distance_to(cam.global_position)])
		elif l.global_position.distance_to(cam.global_position) < 60.0:
			omnis.append(l)
	sets["spots"] = spots
	sets["omnis"] = omnis
	# Pieces the helicopter re-shows every frame are switched off at their inputs instead.
	if heli and is_instance_valid(heli):
		sets["heli_spot"] = ["energy"]
		sets["heli_pool"] = ["pool"]
		sets["heli_shaft"] = ["shaft"]
	sets["wash_pool"] = ["wash:pool_gain"]
	sets["wash_wall"] = ["wash:wall_gain"]
	sets["wash_glare"] = ["wash:glare_gain"]
	var n_i := 0
	for key: String in sets:
		var nodes: Array = sets[key]
		for i in 3:
			await tree.process_frame
		tree.root.get_texture().get_image().save_png(out_dir.path_join("pab_%02d_base.png" % n_i))
		var keep: Variant = null
		for n in nodes:
			if n is String and String(n).begins_with("wash:"):
				keep = []
				for c in cruisers:
					var g: Node = c.get_node_or_null("PoliceGlow")
					if g and g.has_meta("mat"):
						var gm: ShaderMaterial = g.get_meta("mat")
						keep.append(gm.get_shader_parameter(String(n).substr(5)))
						gm.set_shader_parameter(String(n).substr(5), 0.0)
			elif n is String:
				match String(n):
					"energy":
						keep = heli.get("searchlight_energy")
						heli.set("searchlight_energy", 0.0)
					"pool":
						var pool := heli.find_child("Pool", true, false) as MeshInstance3D
						keep = pool.transparency
						pool.transparency = 1.0
						for ch in pool.get_children():
							(ch as GeometryInstance3D).transparency = 1.0
					"shaft":
						var sh := heli.find_child("Shaft", true, false) as GeometryInstance3D
						keep = sh.transparency
						sh.transparency = 1.0
			else:
				n.set("visible", false)
		for i in 3:
			await tree.process_frame
		tree.root.get_texture().get_image().save_png(out_dir.path_join("pab_%02d_%s.png" % [n_i, key]))
		for n in nodes:
			if n is String and String(n).begins_with("wash:"):
				var k := 0
				for c in cruisers:
					var g: Node = c.get_node_or_null("PoliceGlow")
					if g and g.has_meta("mat"):
						(g.get_meta("mat") as ShaderMaterial).set_shader_parameter(String(n).substr(5), keep[k])
						k += 1
			elif n is String:
				match String(n):
					"energy":
						heli.set("searchlight_energy", keep)
					"pool":
						var pool := heli.find_child("Pool", true, false) as MeshInstance3D
						pool.transparency = 0.0
						for ch in pool.get_children():
							(ch as GeometryInstance3D).transparency = 0.0
					"shaft":
						(heli.find_child("Shaft", true, false) as GeometryInstance3D).transparency = 0.0
			else:
				n.set("visible", true)
		n_i += 1
		print("PURSUIT_AB %s: %d nodes hidden" % [key, nodes.size()])
