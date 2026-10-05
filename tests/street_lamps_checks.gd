extends RefCounted
## Street lamps (StreetLamps, tools/make_street_lamps.py), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Checks the model against the table (every type's node, height, light points inside its
## bounds, a budget, the one lamp material, a shadow twin), the pick (both kerbs of a street the
## same lamp, a mast-arm LED only on an LED patch, every type somewhere), the arms over the road,
## then builds FULL chunks downtown and in the beach town: the lamps are batches of the kit on its
## material, every lamp keeps its omni (now up in the head) and its pool, and the chunk built with
## the kit off has the same lamp props at the same places (no prop id or roll moves).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_model()
	_picks(plan)
	_arms(plan)
	_chunk(city, plan, Vector2(1866.6, 660.0), "downtown", StreetLamps.Type.TWIN)
	var sub := _find(plan, StreetLamps.Type.POST, [CityPlan.District.SUBURBS, CityPlan.District.BEACHTOWN])
	_t._check(sub.x < 99999.0, "a suburban street of post-tops is found")
	if sub.x < 99999.0:
		_chunk(city, plan, sub, "the suburbs", StreetLamps.Type.POST)


func _model() -> void:
	var ok := StreetLamps.TYPES.size() == StreetLamps.Type.size() and StreetLamps.HEIGHTS.size() == StreetLamps.Type.size()
	var notes: Array[String] = []
	var twins := 0
	for ty in StreetLamps.Type.size():
		var spec: Dictionary = StreetLamps.TYPES[ty]
		var m := StreetLamps.mesh(ty)
		var box := m.get_aabb() if m else AABB()
		var tall := absf(box.end.y - float(StreetLamps.HEIGHTS[ty])) < 0.08 and absf(box.position.y) < 0.02
		var inside := true
		for l: Vector2 in spec.lights:
			inside = inside and l.x >= box.position.x - 0.01 and l.x <= box.end.x + 0.01 and l.y <= box.end.y and l.y > box.end.y - 1.0
		var mat_ok := m != null and m.get_surface_count() == 1 and m.surface_get_material(0) == StreetLamps.material()
		var budget := PropFactory.TRI_BUDGET.has("street_lamps.glb:" + str(spec.node))
		if PropFactory.shadow_proxy(m) != null:
			twins += 1
		if not (tall and inside and mat_ok and budget):
			ok = false
			notes.append("%s h %.2f inside %s mat %s budget %s" % [spec.node, box.end.y, inside, mat_ok, budget])
	_t._check(ok, "every street lamp type is in the kit at its table's height, one surface on the lamp shader, under a budget %s" % [notes])
	_t._check(twins == StreetLamps.Type.size(), "every street lamp type casts from a lighter shadow twin (%d of %d)" % [twins, StreetLamps.Type.size()])
	var src := FileAccess.get_file_as_string("res://shaders/street_lamp.gdshader")
	_t._check(src.contains("global uniform float lamp_factor") and src.contains("color_space.gdshaderinc"),
		"the lamp shader is lit by lamp_factor and works in linear (color_space)")


## Walks a block's four kerbs as CityChunk._build_sidewalk_props() does, calling `f` with the
## lamp point, its facing and the block rect.
func _each_lamp(plan: CityPlan, bx: int, bz: int, f: Callable) -> void:
	var rect: Rect2 = plan.block(bx, bz).rect
	var edges := [
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(0.0, 1.0)],
		[Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Vector2(0.0, -1.0)],
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Vector2(1.0, 0.0)],
		[Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), Vector2(-1.0, 0.0)],
	]
	for e in edges.size():
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var t := 24.0 * (0.5 if e % 2 == 0 else 0.25)
		while t < length - 4.0:
			f.call(a + dir * t + inward, -inward, rect)
			t += 24.0


func _picks(plan: CityPlan) -> void:
	# Lambdas capture locals by value: count in a Dictionary.
	var seen := {}
	var n := {"pairs": 0, "differ": 0, "bad_mast": 0}
	for c: Vector2 in [Vector2(1866.6, 660.0), Vector2(300.0, 600.0), Vector2(-1930.0, 700.0), Vector2(-900.0, -560.0), Vector2(-13.0, 250.0)]:
		var k := plan.block_index_at(c)
		for bx in range(k.x - 3, k.x + 4):
			for bz in range(k.y - 3, k.y + 4):
				_each_lamp(plan, bx, bz, func(p: Vector2, facing: Vector2, _rect: Rect2) -> void:
					var ty := StreetLamps.pick(plan, p, facing)
					seen[ty] = true
					if ty == StreetLamps.Type.MAST and not NightCity.lamp_led(p):
						n.bad_mast += 1
					# The kerb across the road: the same street, facing back.
					var st := StreetLamps.street_of(plan, p, facing)
					var axis: int = st[0]
					var road := plan.road_pos(axis, st[1])
					var q := Vector2(p.x, 2.0 * road - p.y) if axis == CityPlan.AXIS_Z else Vector2(2.0 * road - p.x, p.y)
					if plan.district_at(q) == plan.district_at(p) and NightCity.lamp_led(q) == NightCity.lamp_led(p):
						n.pairs += 1
						if StreetLamps.pick(plan, q, -facing) != ty:
							n.differ += 1)
	_t._check(n.pairs > 100 and n.differ == 0, "both kerbs of a street carry the same lamp (%d pairs, %d differ)" % [n.pairs, n.differ])
	_t._check(n.bad_mast == 0, "a mast-arm LED stands only on an LED patch (%d on sodium)" % n.bad_mast)
	_t._check(seen.size() == StreetLamps.Type.size(), "every lamp type stands somewhere in the basin (%d of %d)" % [seen.size(), StreetLamps.Type.size()])


func _arms(plan: CityPlan) -> void:
	var n := {"arms": 0, "over": 0}
	var k := plan.block_index_at(Vector2(-1930.0, 700.0))
	for bx in range(k.x - 3, k.x + 4):
		for bz in range(k.y - 3, k.y + 4):
			_each_lamp(plan, bx, bz, func(p: Vector2, facing: Vector2, rect: Rect2) -> void:
				var lp := StreetLamps.place(plan, Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y), facing)
				if lp.type == StreetLamps.Type.COBRA or lp.type == StreetLamps.Type.MAST:
					n.arms += 1
					var head: Vector3 = lp.lights[0]
					if not rect.has_point(Vector2(head.x, head.z)):
						n.over += 1)
	_t._check(n.arms > 20 and n.over == n.arms, "every cobra and mast arm reaches out over the road (%d of %d)" % [n.over, n.arms])


## The centre of a plain city block of `districts` near the middle of the map with a lamp of type
## `want` on its kerbs (the pure pick), or (99999, 0).
func _find(plan: CityPlan, want: int, districts: Array) -> Vector2:
	for r in range(2, 30):
		for c: Vector2 in [Vector2(r * 140.0, r * 90.0), Vector2(-r * 120.0, r * 150.0), Vector2(r * 60.0, -r * 160.0), Vector2(-r * 150.0, -r * 70.0)]:
			var k := plan.chunk_index_at(c)
			var block := plan.block(k.x, k.y)
			var centre: Vector2 = (block.rect as Rect2).get_center()
			if int(plan.zone_at(centre)) != MacroMap.Zone.CITY or int(block.get("kind", -1)) != CityPlan.BlockKind.BUILDINGS \
					or not districts.has(int(plan.district_at(centre))) or plan.river_block(k.x, k.y) or plan.marina_block(k.x, k.y):
				continue
			var n := {"hit": 0}
			_each_lamp(plan, k.x, k.y, func(p: Vector2, facing: Vector2, _rect: Rect2) -> void:
				if StreetLamps.pick(plan, p, facing) == want:
					n.hit += 1)
			if n.hit >= 3:
				return centre
	return Vector2(99999.0, 0.0)


func _lamp_records(chunk: CityChunk) -> Array:
	var out := []
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) == "lamp":
			out.append([r.id, (r.position as Vector3).snapped(Vector3(0.01, 0.01, 0.01))])
	return out


func _chunk(city: Node3D, plan: CityPlan, at: Vector2, label: String, want: int) -> void:
	var k := plan.chunk_index_at(at)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var lamps := _lamp_records(chunk)
	if lamps.is_empty():
		var kinds := {}
		for r: Dictionary in chunk.prop_records:
			kinds[r.kind] = kinds.get(r.kind, 0) + 1
		print("street lamps: no lamps in %s chunk %s zone %s block %s props %s" % [label, k, plan.zone_at(at), plan.block(k.x, k.y).get("kind"), kinds])
	var key := "Batch_lamp_" + str(StreetLamps.TYPES[want].node).trim_prefix("sl_")
	var node := chunk.get_node_or_null(key) as MultiMeshInstance3D
	var kit := 0
	var old := chunk.get_node_or_null("Batch_lamp") != null
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_lamp_") and String(c.name) != "Batch_lamp_pool":
			kit += (c as MultiMeshInstance3D).multimesh.instance_count
			if (c as MultiMeshInstance3D).multimesh.mesh.surface_get_material(0) != StreetLamps.material():
				kit = -9999
	_t._check(node != null and kit == lamps.size() and not old,
		"%s's lamps are the kit (%s among them), one batch per type on the lamp shader (%d lamps, %d instances)" % [label, StreetLamps.TYPES[want].node, lamps.size(), kit])
	var high := 0
	for c in chunk.get_children():
		if c is OmniLight3D and (c as Node).is_in_group("lamp_light"):
			var l := c as OmniLight3D
			if l.position.y - chunk.ground_y(l.position.x, l.position.z) > 3.9:
				high += 1
	var pools := chunk.get_node_or_null("Batch_lamp_pool") as MultiMeshInstance3D
	_t._check(high >= lamps.size() and pools != null and pools.multimesh.instance_count >= lamps.size(),
		"every lamp in %s keeps its pool and its omni, up in the head (%d omnis over 3.9 m for %d lamps)" % [label, high, lamps.size()])
	chunk.queue_free()
	StreetLamps.enabled = false
	var before: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	before.build()
	var lamps_old := _lamp_records(before)
	StreetLamps.enabled = true
	before.queue_free()
	_t._check(lamps.size() > 4 and lamps == lamps_old, "%s's lamps keep their prop ids and places with the kit off (%d / %d)" % [label, lamps.size(), lamps_old.size()])
