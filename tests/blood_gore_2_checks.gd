extends RefCounted
## Blood and gore at arm's length (tests/smoke_test.gd, BloodGore; docs/HANDOFF.md "Blood and gore
## at arm's length"): the stump mesh and the rivulet texture; the flow of blood on tilted ground
## and down a road's camber to the gutter; a pool that runs; a shot body's stains carrying holes
## that face out of the body and runs that creep down it; the hero spattered only when close and
## never past his cap; a body on a car leaving blood on the car and a drip at its edge; and
## BLOOD_GORE_2 off doing none of it. Loaded at run time (this file names classes that use the
## autoloads), like the other check files.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	var was := BloodGore.enabled()
	BloodGore.force(true)
	var budget := WeaponFX.blood_budget
	WeaponFX.blood_budget = 1000
	_check_pure()
	var player := _tree.get_first_node_in_group("player") as Node3D
	if player == null:
		_check(false, "blood gore 2: a player to stage round")
	else:
		_check_flow(city, player)
		await _check_pool(player)
		await _check_wounds(player)
		await _check_hero(player)
		await _check_car(player)
		_check_off(player)
	WeaponFX.blood_budget = budget
	BloodGore.force(was)


func _check_pure() -> void:
	var m := BloodGore.stump_mesh(0.06)
	var verts: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var up := Vector3.ZERO
	for n in normals:
		up += n
	_check(verts.size() / 3 > 150 and verts.size() / 3 < 900 and up.y > 0.0,
		"the stump is one mesh of a few hundred triangles facing out (+Y) (%d tris, normal sum %s)" % [verts.size() / 3, up.round()])
	_check(BloodGore.stump_mesh(0.06) == m, "stump meshes are cached by radius")
	var maps := WeaponFX.blood_textures(WeaponFX._KIND_RIVULET)
	_check(maps.size() == 3 and (maps[0] as Texture2D).get_width() == 64 and (maps[0] as Texture2D).get_height() == 128,
		"the rivulet is a 64 x 128 mark with albedo, normal and ORM maps")
	_check(BloodGore.run_share(0.0) == 0.0 and BloodGore.run_share(BloodGore.RUN_SECONDS + 1.0) == 1.0
		and BloodGore.run_share(4.0) > 0.0 and BloodGore.run_share(4.0) < 1.0, "a wound's run creeps out over RUN_SECONDS")


func _check_flow(city: Node3D, player: Node3D) -> void:
	# A slope with nothing else: downhill.
	var tilt := Vector3(0.12, 1.0, 0.0).normalized()
	var off_road := player.global_position + Vector3(0.0, 0.0, 0.0)
	var f := BloodGore.flow(player, off_road + Vector3(5000.0, 0.0, 5000.0), tilt)
	_check((f.dir as Vector3).dot(Vector3.RIGHT) > 0.9, "blood runs downhill on a slope (%s)" % f.dir)
	# On a road: the camber takes it to the nearer kerb.
	var plan = city.get("plan")
	if plan == null:
		return
	var ws := _tree.root.get_node("/root/WorldState")
	var cx: float = plan.road_pos(BloodGore.AXIS_X, 1)
	var hw: float = plan.road_width(BloodGore.AXIS_X, 1) * 0.5
	var cz0: float = plan.road_pos(BloodGore.AXIS_Z, 0)
	var cz1: float = plan.road_pos(BloodGore.AXIS_Z, 1)
	var world := Vector3(cx + hw * 0.4, 0.0, (cz0 + cz1) * 0.5)
	var local: Vector3 = ws.to_local(world)
	var r := BloodGore.flow(player, local, Vector3.UP)
	_check((r.dir as Vector3).dot(Vector3.RIGHT) > 0.9 and float(r.kerb) > 0.0 and float(r.kerb) < hw,
		"on a flat road the camber takes blood to the nearer kerb (%s, kerb %.2f m of half width %.1f)" % [r.dir, float(r.kerb), hw])
	var centre: Vector2 = (plan.block(0, 0).rect as Rect2).get_center()
	var flat := BloodGore.flow(player, ws.to_local(Vector3(centre.x, 0.0, centre.y)), Vector3.UP)
	_check(flat.dir == Vector3.ZERO, "on flat ground off the carriageway (a block's middle) it pools round")
	var other := BloodGore.flow(player, ws.to_local(Vector3(cx - hw * 0.4, 0.0, (cz0 + cz1) * 0.5)), Vector3.UP)
	_check((other.dir as Vector3).dot(Vector3.LEFT) > 0.9, "and on the other half of the road to the other kerb (%s)" % other.dir)


func _check_pool(player: Node3D) -> void:
	var at := player.global_position + Vector3(2.0, 0.0, 2.0)
	var tilt := Vector3(0.0, 1.0, 0.1).normalized()
	var pool := WeaponFX.blood_pool(player, at, tilt, 2.0)
	_check(pool != null and pool.has_meta("flow") and pool.has_meta("rivulet"),
		"a pool on a slope is turned down it and sends a rivulet off downhill")
	if pool == null or not pool.has_meta("rivulet"):
		return
	var riv := pool.get_meta("rivulet") as Node3D
	var start := WeaponFX._extent(riv).z
	for i in 60:
		await _tree.process_frame
	var aspect: float = pool.get_meta("aspect", 1.0)
	_check(aspect > 1.1, "the pool is stretched down the slope (aspect %.2f)" % aspect)
	# The rivulet creeps (its own clock): give it a couple of seconds more than its delay.
	var waited := 0.0
	while waited < BloodGore.RIVULET_DELAY + 2.0:
		await _tree.process_frame
		waited += _tree.root.get_process_delta_time()
	var grown := WeaponFX._extent(riv).z
	_check(is_instance_valid(riv) and grown > start + 0.05, "the rivulet creeps out (%.2f -> %.2f m)" % [start, grown])
	pool.queue_free()


func _check_wounds(player: Node3D) -> void:
	var doll := Ragdoll.new()
	doll.position = player.position + Vector3(0.0, 0.0, -3.0)
	player.get_parent().add_child(doll)
	if not doll.build_from_rig(Pedestrian.MODELS[0], 3):
		_check(false, "blood gore 2: a rigged doll to shoot")
		doll.queue_free()
		return
	for i in 10:
		await _tree.physics_frame
	var chest := doll.bodies[0].global_position + Vector3.UP * 1.1
	doll.shot(chest, Vector3.FORWARD, Vector3.ZERO, 1.0)
	for i in 6:
		await _tree.process_frame
	var holes := 0
	var faced := 0
	for w: Dictionary in doll._wounds:
		if float(w.get("hole", 0.0)) > 0.0:
			holes += 1
		if (w.get("nrm", Vector3.ZERO) as Vector3).length() > 0.9:
			faced += 1
	_check(doll._wounds.size() >= 1 and holes == doll._wounds.size() and faced == doll._wounds.size(),
		"a round leaves stains with holes that face out of the body (%d stains, %d holed, %d faced)" % [doll._wounds.size(), holes, faced])
	var mat := doll._stain_mat
	if mat == null:
		_check(false, "the shot body has its own stain material")
		doll.queue_free()
		return
	var run0: float = (mat.get_shader_parameter("wound_dir_0") as Vector4).w
	var t := 0.0
	while t < 2.5:
		await _tree.process_frame
		t += _tree.root.get_process_delta_time()
	var run1: float = (mat.get_shader_parameter("wound_dir_0") as Vector4).w
	var hv := mat.get_shader_parameter("wound_holes") as Vector4
	_check(float(mat.get_shader_parameter("wound_gore")) == 1.0 and hv.x > 0.0,
		"the stain material draws the holes (wound_gore %s, holes %s)" % [mat.get_shader_parameter("wound_gore"), hv])
	_check(run1 > run0, "the run creeps down the body (%.2f -> %.2f)" % [run0, run1])
	var down := mat.get_shader_parameter("wound_down") as Vector3
	_check(absf(down.length() - 1.0) < 0.01, "the runs know which way is down in the rig (%s)" % down)
	doll.queue_free()


func _check_hero(player: Node3D) -> void:
	var hb := HeroBlood.current
	if hb == null:
		_check(true, "blood gore 2: the player is not the hero rig here, no spatter to check")
		return
	hb.clear()
	var chest := player.global_position + Vector3.UP * 1.3
	var front := -player.global_basis.z
	var before := HeroBlood.thrown
	HeroBlood.splash(chest + front * 12.0, -front, 1.0)
	_check(HeroBlood.thrown == before, "a wound twelve metres off does not spatter the hero")
	HeroBlood.splash(chest + front * 1.2, -front, 1.0)
	_check(HeroBlood.thrown == before + 1 and hb.spats.size() == 1, "a wound a metre in front of him spatters him")
	for i in 10:
		HeroBlood.splash(chest + front * 1.0, -front, 1.0)
	_check(hb.spats.size() == HeroBlood.MAX_SPATS, "he carries at most %d spatters (%d)" % [HeroBlood.MAX_SPATS, hb.spats.size()])
	for i in 3:
		await _tree.process_frame
	var mat := hb._mats[0] if not hb._mats.is_empty() else null
	_check(mat != null and float(mat.get_shader_parameter("spat_count")) == float(HeroBlood.MAX_SPATS),
		"the spatter reaches his materials (%s)" % (mat.get_shader_parameter("spat_count") if mat else "none"))
	hb.clear()


func _check_car(player: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var car := Vehicle.random_car(rng)
	player.get_parent().add_child(car)
	car.global_position = player.global_position + Vector3(6.0, 0.4, -6.0)
	for i in 30:
		await _tree.physics_frame
	var doll := Ragdoll.new()
	player.get_parent().add_child(doll)
	doll.global_position = car.global_position + Vector3.UP * 3.0
	var space := car.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(car.global_position + Vector3(0.0, 4.0, -1.0),
		car.global_position + Vector3(0.0, -1.0, -1.0), 4))
	if hit.is_empty() or hit.collider != car:
		_check(false, "blood gore 2: a ray finds the parked car's top (%s)" % hit)
		car.queue_free()
		doll.queue_free()
		return
	var state := {}
	BloodGore.car_bleed(doll, car, hit, 2.0, state)
	var on_car := 0
	for c in car.get_children():
		if c.is_in_group("blood"):
			on_car += 1
	_check(state.get("car") == car and on_car >= 2,
		"a body bleeding on a car leaves blood on the car that drives off with it (%d marks / drips)" % on_car)
	_check(state.has("edge") and is_instance_valid(state.get("drip")), "and drips off the panel's edge (%s)" % [state.keys()])
	car.global_position += Vector3(0.0, 0.0, 3.0)
	await _tree.physics_frame
	var left := int(state.get("left", 0))
	BloodGore.car_bleed(doll, car, hit, 2.0, state)
	_check(int(state.get("left", 0)) == left - 1, "a car that moves leaves a drop on the road under the edge")
	car.queue_free()
	doll.queue_free()


func _check_off(player: Node3D) -> void:
	BloodGore.force(false)
	var pool := WeaponFX.blood_pool(player, player.global_position + Vector3(-2.0, 0.0, 2.0), Vector3(0.0, 1.0, 0.1).normalized(), 2.0)
	_check(pool != null and not pool.has_meta("rivulet"), "BLOOD_GORE_2=0: a pool is the old round pool")
	var before := HeroBlood.thrown
	HeroBlood.splash(player.global_position + Vector3.UP * 1.3 - player.global_basis.z, player.global_basis.z, 1.0)
	_check(HeroBlood.thrown == before, "BLOOD_GORE_2=0: nothing spatters the hero")
	if pool:
		pool.queue_free()
	BloodGore.force(true)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)
