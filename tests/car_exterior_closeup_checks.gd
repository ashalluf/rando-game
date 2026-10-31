extends RefCounted
## Cars at arm's length: what a car is made of underneath and inside its arches (CarUnderside,
## scripts/vehicles/car_underside.gd; the meshes are tools/make_car_undersides.py's
## road_<name>_under.glb) for tests/smoke_test.gd. Loaded at run time, so it can name Vehicle and
## CarUnderside. Builds its own cars high over the city and frees them. Checks: every lofted road
## body has its underside file; a car hangs it under its placed model as ONE shadowless node on the
## shared material, drawn no further than the near body; it is not one of the car's body meshes
## (damage, cabins, plates never see it) and it stays inside the car's footprint, off the road;
## the bus, the exotics and the motorcycles have none; CAR_UNDERSIDE off (the A/B) builds the car
## exactly as it was, with no node and the same body meshes.

const LOFTED := ["sedan", "crossover", "pickup", "van", "hatchback", "suv", "minivan", "taxi",
		"beater", "ev_hatch", "lux_sedan", "compact_suv", "work_truck", "coupe",
		"lowrider_hardtop", "lowrider_coupe"]

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _cars: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	var was := CarUnderside.enabled
	CarUnderside.enabled = true
	_files()
	await _car_build()
	await _ab()
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_cars.clear()
	CarUnderside.enabled = was


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _files() -> void:
	var missing := []
	for n in LOFTED:
		if CarUnderside.path_for("res://assets/models/road_%s.glb" % n) == "":
			missing.append(n)
	_check(missing.is_empty(), "every lofted road body has its underside (%d bodies%s)" % [LOFTED.size(), "" if missing.is_empty() else ", missing " + ", ".join(missing)])
	var none := true
	for t in [Vehicle.BodyType.BUS, Vehicle.BodyType.SUPER, Vehicle.BodyType.MOTO_SPORT]:
		none = none and CarUnderside.path_for(String(Vehicle.BODY_MODELS.get(t, ""))) == ""
	_check(none, "the bus, the exotics and the motorcycles have none")
	_check(CarUnderside.path_for("res://assets/models/nothing.png") == "", "only a .glb body has an underside")


func _car(type: int, x: float) -> Vehicle:
	var car := Vehicle.new()
	car.body_type = type
	_city.add_child(car)
	var player := _tree.get_first_node_in_group("player") as Node3D
	car.global_position = player.global_position + Vector3(x, 420.0, -30.0)
	_cars.append(car)
	return car


func _underside(car: Vehicle) -> Node3D:
	var holder := car.get_node_or_null("BodyModel")
	if holder == null:
		return null
	return holder.find_child("Underside", true, false) as Node3D


func _car_build() -> void:
	for type in [Vehicle.BodyType.SEDAN, Vehicle.BodyType.PICKUP, Vehicle.BodyType.EV_HATCH]:
		var car := _car(type, -12.0 + 6.0 * float(_cars.size()))
		await _tree.process_frame
		var u := _underside(car)
		var name := String(Vehicle.BODY_NAMES[type])
		_check(u != null, "a %s hangs its underside under its model" % name)
		if u == null:
			continue
		var meshes := u.find_children("*", "MeshInstance3D", true, false)
		var ok := meshes.size() == 1
		var in_body := false
		for mi in meshes:
			var m := mi as MeshInstance3D
			ok = ok and m.material_override == CarUnderside.material() \
					and m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
					and m.visibility_range_end > 0.0 and m.visibility_range_end <= car.body_far_distance + 0.01 \
					and m.mesh != null and m.mesh.get_surface_count() == 1
			in_body = in_body or car._body_meshes.has(m)
		_check(ok, "the %s's underside is one shadowless surface on the shared material, drawn only near (%d node)" % [name, meshes.size()])
		_check(not in_body, "it is not one of the %s's body meshes" % name)
		# Its box, in the car's space: inside the footprint and off the road.
		var mi0: MeshInstance3D = meshes[0] as MeshInstance3D if not meshes.is_empty() else null
		if mi0 and mi0.mesh and mi0.mesh.get_aabb().size.length() > 0.01:
			var to_car := car.global_transform.affine_inverse() * mi0.global_transform
			var box := to_car * mi0.mesh.get_aabb()
			var d := car._dims()
			var ride := float(d.get("ride", car.model_bottom_y))
			_check(box.size.x <= float(d.width) + 0.06 and box.size.z <= float(d.length) + 0.25,
					"the %s's underside stays inside its footprint (%s)" % [name, box.size])
			_check(box.position.y >= ride - 0.05 and box.position.y < ride + 0.4,
					"and hangs off the road, under the body (bottom %.2f, the body's %.2f)" % [box.position.y, ride])


func _ab() -> void:
	CarUnderside.enabled = false
	var off := _car(Vehicle.BodyType.SEDAN, 14.0)
	CarUnderside.enabled = true
	var on := _car(Vehicle.BodyType.SEDAN, 20.0)
	await _tree.process_frame
	_check(_underside(off) == null and _underside(on) != null, "CAR_UNDERSIDE off builds no underside")
	_check(off._body_meshes.size() == on._body_meshes.size(), "and the same body meshes either way (%d / %d)"
			% [off._body_meshes.size(), on._body_meshes.size()])
