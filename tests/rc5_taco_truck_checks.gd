extends RefCounted
## The taco truck at 23:00 (TacoTruckNight, the taco_truck_night reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: no truck parks in a bike lane; regulars by the hour; a truck chunk built at 23:00 has
## its regulars at the queue spots (front pair first), the cook at the counter and the steam over
## the stack; the truck mesh carries its running lamps (code 19) and the shader lights them; the
## menu box and kitchen burn at the new levels; the camera row looks at a truck that works at
## 23:00; RC5_TACO=0 is the truck as before.

var _t: Object


func run(t: Object, city: Node) -> void:
	_t = t
	var was := TacoTruckNight.enabled
	TacoTruckNight.enabled = true
	var plan: CityPlan = city.get("plan")
	_bike_lanes(plan)
	_regulars(plan)
	_mesh_and_shader()
	var k := _camera(plan)
	if k.x != 99999:
		_chunk(city, plan, k)
	TacoTruckNight.enabled = false
	_t._check(not TacoTruckNight.truck_blocked(plan, k.x, k.y, 3) and TacoTruckNight.regular_count(plan.seed, "vend_3_0", 23.0) == 0,
		"RC5_TACO=0: trucks park as before and bring nobody")
	TacoTruckNight.enabled = was


func _bike_lanes(plan: CityPlan) -> void:
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2.ZERO)
	var trucks := 0
	var in_lane := 0
	for dz in range(-6, 7):
		for dx in range(-14, 3):
			for v: Dictionary in StreetVendors.plan_block(plan, centre.x + dx, centre.y + dz, 23.0):
				if int(v.kind) != StreetVendors.Kind.TRUCK:
					continue
				trucks += 1
				var e := int(v.face)
				var ix := centre.x + dx
				var iz := centre.y + dz
				var lane := Micromobility.lane_on(plan, CityPlan.AXIS_X, ix + 1, iz) if e == 3 else Micromobility.lane_on(plan, CityPlan.AXIS_Z, iz + 1, ix)
				if lane and Micromobility.enabled:
					in_lane += 1
	_t._check(trucks > 0 and in_lane == 0, "no taco truck parks in a bike lane (%d trucks at 23:00 west of downtown, %d in a lane)" % [trucks, in_lane])


func _regulars(plan: CityPlan) -> void:
	var late := TacoTruckNight.regular_count(plan.seed, "vend_3_0", 23.0)
	var noon := TacoTruckNight.regular_count(plan.seed, "vend_3_0", 13.0)
	var dusk := TacoTruckNight.regular_count(plan.seed, "vend_3_0", 19.0)
	_t._check(late >= 2 and late <= TacoTruckNight.MAX_REGULARS and noon == 0 and dusk >= 1 and dusk <= late,
		"a truck's regulars follow the hour (23:00 %d, 19:00 %d, 13:00 %d)" % [late, dusk, noon])


func _mesh_and_shader() -> void:
	var mesh := StreetVendors.truck(0)
	var cols: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var lamps := 0
	for c in cols:
		if int(round(c.a * 20.0)) == 19:
			lamps += 1
	_t._check(lamps >= 24 * 8, "the truck carries its clearance and tail lamps (%d lamp vertices)" % lamps)
	var src := FileAccess.get_file_as_string("res://shaders/street_vendor.gdshader")
	_t._check(src.contains("code == 19") and src.contains("marker_night"), "the vendor shader lights the running lamps (code 19)")
	var mat := StreetVendors.material()
	_t._check(is_equal_approx(float(mat.get_shader_parameter("glow_night")), TacoTruckNight.MENU_GLOW)
		and is_equal_approx(float(mat.get_shader_parameter("interior_night")), TacoTruckNight.INTERIOR_GLOW),
		"the menu box and the kitchen burn at the new night levels")
	_t._check(TacoTruckNight.steam_mesh().get_surface_count() == 1 and TacoTruckNight.steam_material().shader != null,
		"the stack's steam mesh and shader load")


## The camera row, and the block of the truck it looks at (99999 when none).
func _camera(plan: CityPlan) -> Vector2i:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	for c: Dictionary in table.get("cameras", []):
		if String(c.name) == "taco_truck_night":
			row = c
	_t._check(not row.is_empty() and is_equal_approx(float(row.get("hour", 0.0)), 23.0), "the taco_truck_night camera is in cameras_w8.json at 23:00")
	if row.is_empty():
		return Vector2i(99999, 0)
	var eye := Vector2(float(row.eye[0]), float(row.eye[2]))
	var best := Vector2i(99999, 0)
	var best_d := 14.0
	var start := plan.block_index_at(eye)
	for iz in range(start.y - 1, start.y + 2):
		for ix in range(start.x - 1, start.x + 2):
			var rect: Rect2 = plan.block(ix, iz).rect
			var edges := CityChunk._sidewalk_edges(rect)
			for v: Dictionary in StreetVendors.plan_block(plan, ix, iz, 23.0):
				if int(v.kind) != StreetVendors.Kind.TRUCK:
					continue
				var e: Array = edges[int(v.face)]
				var at: Vector2 = (e[0] as Vector2) + ((e[1] as Vector2) - (e[0] as Vector2)).normalized() * float(v.t)
				if at.distance_to(eye) < best_d:
					best_d = at.distance_to(eye)
					best = Vector2i(ix, iz)
	_t._check(best.x != 99999, "the camera stands in the queue of a truck working at 23:00 (%.1f m from its kerb)" % best_d)
	return best


func _chunk(city: Node, plan: CityPlan, k: Vector2i) -> void:
	StreetVendors.force_hour = 23.0
	var chunk: CityChunk = city.call("_new_chunk", k, CityChunk.Level.FULL)
	chunk.build()
	var people: Array = chunk.get_meta("vendor_people", [])
	var queue: Array = chunk.get_meta("vendor_queue", [])
	var trucks: Array = chunk.get_meta("vendor_trucks", [])
	var customers := people.filter(func(s: Dictionary) -> bool: return bool(s.get("customer", false)))
	var cooks := people.filter(func(s: Dictionary) -> bool: return bool(s.truck))
	var want := 0
	for v: Dictionary in StreetVendors.plan_block(plan, k.x, k.y, 23.0):
		if int(v.kind) == StreetVendors.Kind.TRUCK:
			want = TacoTruckNight.regular_count(plan.seed, String(v.id), 23.0)
	var on_spots := true
	var first := 99999
	for c: Dictionary in customers:
		first = mini(first, int(c.queue))
	for c: Dictionary in customers:
		var qi := int(c.queue)
		on_spots = on_spots and qi >= 0 and qi < queue.size() and (queue[qi].p as Vector2).distance_to(c.at) < 0.01 and qi - first < customers.size()
	_t._check(customers.size() == want and want >= 2 and on_spots, "the truck's regulars stand at its queue spots, front first (%d of %d)" % [customers.size(), want])
	var cook_ok := false
	if not cooks.is_empty() and not trucks.is_empty():
		var c: Vector2 = trucks[0][0]
		var d := (cooks[0].at as Vector2).distance_to(c)
		cook_ok = d > 0.55 and d < 0.95
	_t._check(cook_ok, "the cook stands at the counter, not at the back wall")
	var steam := 0
	for n in chunk.get_children():
		if n is MeshInstance3D and String(n.name).begins_with("TacoSteam"):
			steam += 1
	_t._check(steam == trucks.size() and steam > 0, "steam rises off each truck's stack (%d)" % steam)
	# A regular made here (the streamed city may have spent the crowd cap) waits at its spot.
	var ok := false
	if not customers.is_empty():
		var s: Dictionary = customers[0]
		var ped := TacoCustomer.new()
		ped.setup_vendor(s.rect, int(s.seed), s.at, float(s.yaw), false, 0.0)
		var at: Vector2 = s.at
		ped.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.05, at.y)
		chunk.add_child(ped)
		ok = ped._act == CrowdLife.Act.STAND and Vector2(ped.position.x, ped.position.z).distance_to(at) < 0.05
	_t._check(ok, "a regular stands waiting at the window")
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	StreetVendors.force_hour = -1.0
