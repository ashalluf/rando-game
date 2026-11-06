extends RefCounted
## Masjid Omar ibn Al-Khattab (LandmarkMasjidOmar) and the sanctuary rule that no gun fires at it
## (Sanctuary), for tests/smoke_test.gd. Loaded at run time so it compiles after the autoloads.
##
## The building: it streams in with its exterior, its interior and a collision body in the
## sanctuary group; the centre door is open to walk through; a window bay is closed by its pane;
## the prayer hall has a floor and the gallery a floor above it. The rule: the crosshair on it,
## a shot across its grounds and a gun fired from inside it are all refused, a shot aimed away
## from it is not, and a rocket that meets it fizzles without a blast.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var plan: CityPlan = city.plan
	var player := _tree.get_first_node_in_group("player") as CharacterBody3D
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var police: Node = city.get_node_or_null("Police")
	if police:
		police.set("enabled", false)
	var lm := {}
	for l in Landmarks.all():
		if l.id == "masjid_omar":
			lm = l
	_t._check(not lm.is_empty(), "the masjid is in the landmark table")
	if lm.is_empty():
		return
	var anchor: Vector2 = lm.anchor
	var ground: float = plan.height_at(anchor)
	# The building frame's origin in the world, and a helper from building frame to local.
	var origin := Vector3(anchor.x, ground + LandmarkMasjidOmar.FLOOR_LIFT, anchor.y) + LandmarkMasjidOmar.BLD_OFFSET
	var at := func(p: Vector3) -> Vector3:
		return ws.to_local(origin + p)
	# Stand on the pavement in front of the entrance flight.
	var front := Vector3(-3.05, LandmarkMasjidOmar.PAVE_Y + 1.0, LandmarkMasjidOmar.SITE_Z1 + 2.5)
	await _go(city, player, origin + front)
	var root: Node3D = null
	for n in _tree.get_nodes_in_group(Sanctuary.ZONE_GROUP):
		if n.get_parent() and str(n.get_parent().name).begins_with("MasjidOmar") and (n.get_parent() as Node3D).get_node_or_null("MasjidBody") != null:
			root = n.get_parent()
	_t._check(root != null and root.get_node_or_null("Exterior") != null and root.get_node_or_null("Interior") != null,
		"the masjid streams in with its exterior and its interior")
	if root == null:
		return
	var body := root.get_node("MasjidBody") as StaticBody3D
	var shape := body.get_child(0) as CollisionShape3D
	var faces: int = (shape.shape as ConcavePolygonShape3D).get_faces().size() / 3 if shape and shape.shape is ConcavePolygonShape3D else 0
	_t._check(body.is_in_group(Sanctuary.BODY_GROUP) and faces > 1000, "its collision is one sanctuary body (%d triangles)" % faces)
	var ext := root.get_node("Exterior") as MeshInstance3D
	var tris := 0
	for s in ext.mesh.get_surface_count():
		tris += (ext.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	_t._check(tris > 20000, "the exterior is modelled, not boxed (%d triangles)" % tris)
	var space := player.get_world_3d().direct_space_state
	# The centre door is open: a ray at chest height from the porch into the lobby passes the wall.
	var e_z1 := LandmarkMasjidOmar.E_Z1
	var q := PhysicsRayQueryParameters3D.create(at.call(Vector3(-3.05, 1.2, e_z1 + 1.0)), at.call(Vector3(-3.05, 1.2, e_z1 - 3.0)), 1)
	var hit := space.intersect_ray(q)
	_t._check(hit.is_empty() or ws.to_world(hit.position).z < origin.z + e_z1 - LandmarkMasjidOmar.WALL_T - 0.1,
		"the centre door stands open: you can walk into the lobby")
	# A west-block bay is closed by its pane.
	var bay_x := LandmarkMasjidOmar.W_X0 + (LandmarkMasjidOmar.W_X1 - LandmarkMasjidOmar.W_X0) / 10.0
	q = PhysicsRayQueryParameters3D.create(at.call(Vector3(bay_x, 3.0, LandmarkMasjidOmar.W_Z1 + 2.0)), at.call(Vector3(bay_x, 3.0, LandmarkMasjidOmar.W_Z1 - 2.0)), 1)
	hit = space.intersect_ray(q)
	_t._check(not hit.is_empty() and Sanctuary.is_sanctuary(hit.collider), "a window bay is closed by its pane")
	# Floors: the prayer hall's, and the gallery's above the ring.
	var hall_c := Vector3((LandmarkMasjidOmar.W_X0 + LandmarkMasjidOmar.W_X1) * 0.5, 0.0, (LandmarkMasjidOmar.W_Z0 + LandmarkMasjidOmar.W_Z1) * 0.5)
	q = PhysicsRayQueryParameters3D.create(at.call(hall_c + Vector3(0.0, 3.0, 0.0)), at.call(hall_c + Vector3(0.0, -2.0, 0.0)), 1)
	hit = space.intersect_ray(q)
	var floor_y: float = ws.to_world(hit.position).y - origin.y if not hit.is_empty() else INF
	_t._check(absf(floor_y) < 0.05, "the prayer hall has a floor to stand on (%.2f)" % floor_y)
	var gal := Vector3(hall_c.x + 7.0, 0.0, hall_c.z)
	q = PhysicsRayQueryParameters3D.create(at.call(gal + Vector3(0.0, 8.0, 0.0)), at.call(gal + Vector3(0.0, 1.0, 0.0)), 1)
	hit = space.intersect_ray(q)
	var gal_y: float = ws.to_world(hit.position).y - origin.y if not hit.is_empty() else INF
	_t._check(absf(gal_y - LandmarkMasjidOmar.GALLERY_Y) < 0.05, "the gallery has a floor (%.2f)" % gal_y)
	await _sanctuary(city, player, ws, origin, at)


func _sanctuary(city: Node3D, player: CharacterBody3D, ws: Node, origin: Vector3, at: Callable) -> void:
	# The rule, straight: at the wall, across the grounds, from inside, and away from it.
	var body := _tree.get_nodes_in_group(Sanctuary.BODY_GROUP)[0] as Node
	var from_street: Vector3 = at.call(Vector3(-3.05, 1.5, LandmarkMasjidOmar.SITE_Z1 + 6.0))
	_t._check(Sanctuary.blocks_fire(player, {"origin": from_street, "point": at.call(Vector3(-3.0, 4.0, LandmarkMasjidOmar.E_Z1)), "collider": body}),
		"the crosshair on the masjid: no shot")
	var across := {"origin": at.call(Vector3(-60.0, 1.5, 0.0)), "point": at.call(Vector3(60.0, 1.5, 0.0)), "collider": null}
	_t._check(Sanctuary.blocks_fire(player, across), "a shot across its grounds: no shot")
	var away := {"origin": from_street, "point": at.call(Vector3(-3.05, 1.5, LandmarkMasjidOmar.SITE_Z1 + 40.0)), "collider": null}
	player.global_position = at.call(Vector3(-3.05, LandmarkMasjidOmar.PAVE_Y + 1.0, LandmarkMasjidOmar.SITE_Z1 + 6.0))
	_t._check(not Sanctuary.blocks_fire(player, away), "a shot aimed away from it, from the street, is fired")
	_t._check(Sanctuary.blocks_fire(player, away, 9.0) == false, "a rocket landing well clear of it is fired")
	var beside := {"origin": from_street, "point": at.call(Vector3(-3.05, LandmarkMasjidOmar.PAVE_Y, LandmarkMasjidOmar.SITE_Z1 + 3.0)), "collider": null}
	_t._check(Sanctuary.blocks_fire(player, beside, 9.0), "a rocket landing beside it is not")
	player.global_position = at.call(Vector3(-15.0, 0.9, -1.0))
	_t._check(Sanctuary.blocks_fire(player, away), "no gun fires inside the prayer hall")
	# Through a real gun: the rifle, fired from inside the prayer hall, where every shot is
	# refused whatever the camera is pointing at. A shot that goes spends the cooldown.
	player.global_position = at.call(Vector3(-15.0, 0.9, -1.0))
	player.set("velocity", Vector3.ZERO)
	var manager: Node = player.get("weapon_manager")
	if manager:
		manager.call("equip", 0)
		await _t._ticks(3)
		var gun: Node = manager.get("current")
		if gun:
			gun.set("_cooldown", 0.0)
			gun.set("blocked_by_sanctuary", false)
			Input.action_press("fire")
			await _t._ticks(3)
			Input.action_release("fire")
			_t._check(bool(gun.get("blocked_by_sanctuary")) and float(gun.get("_cooldown")) <= 0.0,
				"the rifle will not fire inside the masjid")
			# Back out on the pavement, aimed along the street, it fires again.
			player.global_position = at.call(Vector3(-40.0, LandmarkMasjidOmar.PAVE_Y + 1.0, LandmarkMasjidOmar.SITE_Z1 + 30.0))
			await _t._ticks(3)
			var aim: Dictionary = player.call("get_aim")
			if not Sanctuary.blocks_fire(player, aim):
				gun.set("_cooldown", 0.0)
				Input.action_press("fire")
				await _t._ticks(3)
				Input.action_release("fire")
				_t._check(not bool(gun.get("blocked_by_sanctuary")), "away from it, the rifle fires")
	# A rocket already in flight that meets the wall fizzles: no blast.
	var blasts := Explosion.blast_count
	var rocket := Rocket.new()
	rocket.speed = 40.0
	rocket.direction = Vector3(0.0, 0.0, -1.0)
	rocket.exclude = [player.get_rid()]
	city.add_child(rocket)
	rocket.global_position = at.call(Vector3(-15.0, 5.0, LandmarkMasjidOmar.W_Z1 + 6.0))
	await _t._ticks(30)
	_t._check(Explosion.blast_count == blasts and not is_instance_valid(rocket), "a rocket that reaches it fizzles without a blast")


func _go(city: Node3D, player: Node3D, world: Vector3) -> void:
	var ws: Node = _tree.root.get_node("/root/WorldState")
	# Inside the physics tick, as the streamer does it (see CityStreamer.recenter()).
	await _tree.physics_frame
	player.global_position = ws.to_local(world)
	player.set("velocity", Vector3.ZERO)
	city.recenter()
	city.update_streaming(true)
	await _tree.process_frame
	await _tree.process_frame
	await _t._ticks(4)
