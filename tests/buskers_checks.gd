extends RefCounted
## Street performers (Buskers, Busker, BuskWatcher), for tests/smoke_test.gd. Loaded at run time,
## not named there, so it compiles after the autoloads.
##
## Checks the tables (every place rolls every kind, every kind has hours and rigs, the rig pick
## mirrors Pedestrian's), the gear meshes (one surface each on the busker shader, sane sizes), the
## plan (pure, downtown has acts by day and none at 04:00, breakdancers only on plazas), then
## builds a FULL chunk with a performer (Buskers.force_hour) and checks: the gear batch, the watch
## spots for passers-by, the performer at the pitch facing the street with the act's clips, the
## statue up on its plinth and the drummer on the bucket, a scare that sends them running and the
## walk back to the pitch once it is over, and the block built with the buskers off is the same
## block (hash-seeded: the chunk rng, the props and the parked cars untouched).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_tables()
	_meshes()
	_plan(plan)
	var k := _find(plan, 15.0, -1, false)
	_t._check(k.x != 99999, "a downtown pavement has a street performer at 15:00")
	if k.x != 99999:
		_chunk(city, plan, k)
	_people(city)


func _tables() -> void:
	var ok := true
	for place: int in Buskers.ODDS:
		ok = ok and (Buskers.ODDS[place] as Array).size() == Buskers.Kind.size()
	for kind in Buskers.Kind.size():
		ok = ok and Buskers.HOURS.has(kind) and Buskers.RIGS.has(kind)
		for rig: String in Buskers.RIGS[kind]:
			ok = ok and ("res://assets/models/%s.glb" % rig) in Pedestrian.MODELS
	_t._check(ok, "every busker place rolls every kind, and every kind has hours and crowd rigs")
	# The performer's rig is the one asked for (Buskers.seed_for mirrors Pedestrian._add_model's
	# first style roll), and no hat or pack: checked on a real person for each kind.
	var picked := true
	var hatless := true
	for kind in Buskers.Kind.size():
		var s := Buskers.seed_for(hash(["buskers_checks", kind]), Buskers.RIGS[kind])
		var p := Pedestrian.new()
		p.set_meta("no_trim", true) # never trimmed or borrowed by the live crowd systems
		p.setup(Rect2(0, 0, 50, 50), 4.0, s)
		var holder := Node3D.new()
		_t.get_tree().root.add_child(holder)
		holder.add_child(p)
		picked = picked and String(p._model_path).get_file().get_basename() in Buskers.RIGS[kind]
		hatless = hatless and p._hat == Pedestrian.Accessory.NONE
		holder.queue_free()
	_t._check(picked, "Buskers.seed_for picks a seed whose crowd rig is one of the act's")
	_t._check(hatless, "a performer's seed wears no hat or pack (the gear goes there)")
	var lib := true
	for rig: String in ["crowd_a", "crowd_o", "crowd_t"]:
		var l: AnimationLibrary = load("res://assets/models/crowd_busk/%s_busk.res" % rig)
		lib = lib and l != null and l.has_animation("dance") and l.has_animation("crouch") and l.has_animation("spell")
	_t._check(lib, "the performers' clip library (tools/crowd/busk_clips.gd) is there for the crowd rigs")


func _meshes() -> void:
	var ok := true
	var worst := 0
	var meshes: Array[Mesh] = []
	for m: Mesh in Buskers.gear_meshes().values():
		meshes.append(m)
	meshes.append_array([Buskers.guitar_mesh(false), Buskers.guitar_mesh(true), Buskers.violin_mesh(),
		Buskers.bow_mesh(), Buskers.trumpet_mesh(), Buskers.stick_mesh(), Buskers.sombrero_mesh("res://assets/models/crowd_a.glb")])
	for m in meshes:
		var tris := (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		worst = maxi(worst, tris)
		ok = ok and m.get_surface_count() == 1 and m.surface_get_material(0) == Buskers.material() and tris >= 50
	_t._check(ok, "every busker mesh is one surface on the busker shader")
	_t._check(worst < 6000, "a busker mesh stays under 6k triangles (worst %d)" % worst)
	var g := Buskers.guitar_mesh(false).get_aabb()
	var d := Buskers.drums_mesh().get_aabb()
	_t._check(absf(g.size.x - 1.1) < 0.12 and absf(g.size.y - 0.38) < 0.05 and d.position.y > -0.01 and d.end.y < 1.0,
		"the guitar is a real guitar's size (%.2f x %.2f m) and the drum kit stands on the pavement" % [g.size.x, g.size.y])


func _plan(plan: CityPlan) -> void:
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2.ZERO)
	var day := 0
	var night := 0
	var pure := true
	var break_ok := true
	for dz in range(-5, 6):
		for dx in range(-5, 6):
			var a := Buskers.plan_block(plan, centre.x + dx, centre.y + dz, 15.0)
			pure = pure and str(a) == str(Buskers.plan_block(plan, centre.x + dx, centre.y + dz, 15.0))
			day += a.size()
			night += Buskers.plan_block(plan, centre.x + dx, centre.y + dz, 4.0).size()
			for v: Dictionary in a:
				if int(v.kind) == Buskers.Kind.BREAK and int(v.face) >= 0:
					break_ok = false
	_t._check(pure, "Buskers.plan_block is pure (the same answer twice)")
	_t._check(day >= 5 and night == 0, "downtown has street performers by day and none at 04:00 (%d at 15:00, %d at 04:00)" % [day, night])
	_t._check(break_ok, "breakdancers dance only on plazas (they need the room for their ring)")
	_t._check(StreetVendors.open_at(Buskers.hours_of(plan.seed, Buskers.Kind.MARIACHI, [1, 2, 3]), 20.0),
		"a mariachi trio plays into the evening")


## The first block round downtown with a performer (of `kind`, -1 any) at `hour`.
func _find(plan: CityPlan, hour: float, kind: int, plaza: bool) -> Vector2i:
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2.ZERO)
	for r in 7:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var k := centre + Vector2i(dx, dz)
				var b := plan.block(k.x, k.y)
				if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
					continue
				for v: Dictionary in Buskers.plan_block(plan, k.x, k.y, hour):
					if (kind < 0 or int(v.kind) == kind) and (int(v.face) < 0) == plaza:
						return k
	return Vector2i(99999, 99999)


func _chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	Buskers.force_hour = 15.0
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var acts: Array = chunk.get_meta("busk_acts", [])
	var people: Array = chunk.get_meta("busk_people", [])
	_t._check(not acts.is_empty() and not people.is_empty(), "a performer's chunk lays out an act and its people (%d acts, %d people)" % [acts.size(), people.size()])
	var batch := false
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_busk_"):
			batch = batch or (c as MultiMeshInstance3D).multimesh.mesh.surface_get_material(0) == Buskers.material()
	var act: Dictionary = acts[0] if not acts.is_empty() else {}
	_t._check(batch, "the act's gear is a batch on the busker shader")
	var spots := 0
	for q: Dictionary in chunk.get_meta("vendor_queue", []):
		if q.record is Dictionary and (q.record as Dictionary).has("busk"):
			spots += 1
	var watchable := not act.is_empty() and int(act.kind) != Buskers.Kind.BREAK
	_t._check(spots >= Buskers.WATCH_SPOTS or not watchable, "passers-by have spots to stop and watch the act (%d)" % spots)
	# Built off, the same block.
	var sig := _signature(chunk)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	Buskers.enabled = false
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	Buskers.enabled = true
	_t._check(_signature(bare) == sig, "the buskers roll nothing from the block: built without them it is the same block")
	bare.get_parent().remove_child(bare)
	bare.free()
	Buskers.force_hour = -1.0


## Performers made here, on a holder with a flat ground (the city's crowd cap may be spent): each
## kind at its pitch doing its act, the statue on its plinth, the drummer on the bucket, and a
## scare and the walk back.
func _people(city: Node3D) -> void:
	var holder := _Holder.new()
	holder.name = "BuskHolder"
	city.add_child(holder)
	var ok := true
	var lib := true
	var made: Array = []
	for kind in Buskers.Kind.size():
		var b := Busker.new()
		var at := Vector2(float(kind) * 4.0, 0.0)
		b.setup_busker(Rect2(-20, -10, 40, 20), Buskers.seed_for(hash(["busk_people", kind]), Buskers.RIGS[kind]), at, PI, kind, 0)
		b.position = Vector3(at.x, 0.3, at.y)
		holder.add_child(b)
		made.append(b)
		ok = ok and b._act == CrowdLife.Act.STAND and b._stage == Pedestrian.Stage.DOING \
			and Vector2(b.position.x, b.position.z).distance_to(at) < 0.05 and absf(angle_difference(b._visual.rotation.y, PI)) < 0.01
		lib = lib and (not b._life_ok or b._busk_ok)
	_t._check(ok, "every kind of performer stands at its pitch facing the street, at work")
	_t._check(lib, "the performers have their act's clips")
	var statue: Busker = made[Buskers.Kind.STATUE]
	_t._check(absf(statue.position.y - (holder.ground_y(0, 0) + Buskers.PLINTH_H)) < 0.05 and statue.collision_mask == 0,
		"the living statue stands up on its plinth, out of the physics (y %.2f)" % statue.position.y)
	var drummer: Busker = made[Buskers.Kind.DRUMS]
	_t._check(not drummer._life_ok or (drummer._life_base == CrowdLife.SIT and drummer._seat_drop > 0.0),
		"the drummer sits on the kit's bucket (the bench solve lowers the clip's chair by %.2f m)" % drummer._seat_drop)
	# A scare: they run, and walk back to the pitch once it is over.
	var g: Busker = made[Buskers.Kind.GUITAR]
	g._scare(g.global_position + Vector3(6.0, 0.0, 0.0))
	var fled := g._act == CrowdLife.Act.NONE and g._panic_left > 0.0
	g._panic_left = 0.0
	g._physics_process(1.0 / 60.0)
	_t._check(fled and g._act == CrowdLife.Act.STAND and g._stage == Pedestrian.Stage.GOING and g._target.distance_to(g.home) < 0.5,
		"a scared performer runs, and walks back to the pitch when it is over")
	statue._scare(statue.global_position + Vector3(6.0, 0.0, 0.0))
	_t._check(not statue._kinematic and statue.collision_mask != 0, "a scared statue steps off its plinth into the physics")
	# Watchers face the act and leave when it is gone.
	var w := BuskWatcher.new()
	w.setup_watch(Rect2(-20, -10, 40, 20), 77, Vector2(4.0, 3.0), 0.0)
	w.performer = drummer
	w.position = Vector3(4.0, 0.3, 3.0)
	holder.add_child(w)
	var watching := w._act == CrowdLife.Act.STAND and w._act_on()
	drummer.applause_until_ms = Pedestrian._life_now_ms() + 2000
	var claps := w._clapping()
	_t._check(watching and claps, "a watcher stands watching the act and claps when it asks")
	holder.queue_free()


class _Holder:
	extends Node3D

	func ground_y(_x: float, _z: float) -> float:
		return 0.2

	func _take_crowd_room(_r: float = 0.0) -> bool:
		return true


## Buildings, props, trash cans and the parked cars, by position.
func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = (car as Node3D).position
			out.append("car %.1f %.1f" % [p.x, p.z])
	out.sort()
	return out
