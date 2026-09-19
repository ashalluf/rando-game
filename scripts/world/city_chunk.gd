class_name CityChunk
extends Node3D
## One city block plus the road on its +X side, the road on its +Z side, and the intersection at
## that corner. FULL level has everything: buildings, props, collision, physics trash cans.
## LOD level is just slabs and colored boxes with no collision, for the far skyline.
## Children are placed at true world coordinates; the chunk node sits at -WorldState.world_offset.

enum Level { FULL, LOD }

const BUILDING_SCENE := preload("res://scenes/props/building.tscn")
const ROAD_TOP := 0.1
const SIDEWALK_TOP := 0.25
const PROP_HEALTH := {"lamp": 30.0, "hydrant": 20.0, "bench": 20.0, "stop_sign": 10.0, "signal": 60.0}

var plan: CityPlan
var ix: int = 0
var iz: int = 0
var level: Level = Level.FULL
var key: String = ""
## Colors and spacing from the streamer's exports.
var style: Dictionary = {}

var building_count: int = 0
var prop_records: Array[Dictionary] = []

var _batch := MultiMeshBatch.new()
var _mm_nodes: Dictionary = {}
var _statics: StreetProps
var _prop_counter: int = 0


func build() -> void:
	key = "%d,%d" % [ix, iz]
	name = "Chunk_" + key
	position = -WorldState.world_offset
	if level == Level.FULL:
		_statics = StreetProps.new()
		_statics.chunk = self
		add_child(_statics)
	var block := plan.block(ix, iz)
	_build_roads(block)
	_build_block(block)
	if level == Level.FULL:
		_build_intersection(plan.intersection(ix + 1, iz + 1))
	_mm_nodes = _batch.build(self)


func has_prop(id: String) -> bool:
	for record in prop_records:
		if record.id == id:
			return true
	return false


# --- Roads -----------------------------------------------------------------------------

func _build_roads(block: Dictionary) -> void:
	var rect: Rect2 = block.rect
	var asphalt: Color = style.asphalt
	# Vertical road on the +X side, spanning this block's Z range.
	var rx := plan.road_pos(CityPlan.AXIS_X, ix + 1)
	var wx := plan.road_width(CityPlan.AXIS_X, ix + 1)
	_add_slab(Vector3(rx, ROAD_TOP * 0.5, rect.get_center().y), Vector3(wx, ROAD_TOP, rect.size.y), asphalt)
	# Horizontal road on the +Z side, spanning this block's X range.
	var rz := plan.road_pos(CityPlan.AXIS_Z, iz + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, iz + 1)
	_add_slab(Vector3(rect.get_center().x, ROAD_TOP * 0.5, rz), Vector3(rect.size.x, ROAD_TOP, wz), asphalt)
	# The intersection square at the +X +Z corner.
	_add_slab(Vector3(rx, ROAD_TOP * 0.5, rz), Vector3(wx, ROAD_TOP, wz), asphalt)
	if level == Level.FULL:
		_mark_road(true, rx, wx, rect.position.y, rect.end.y)
		_mark_road(false, rz, wz, rect.position.x, rect.end.x)


## Center-line markings along one block: dashed yellow on streets, double solid on avenues.
func _mark_road(along_z: bool, center: float, width: float, a: float, b: float) -> void:
	a += 3.0
	b -= 3.0
	if b - a < 4.0:
		return
	var avenue := width >= plan.avenue_width - 0.1
	var yaw := 0.0 if along_z else PI * 0.5
	if avenue:
		for side: float in [-0.3, 0.3]:
			var mid := (a + b) * 0.5
			var pos := Vector3(center + side, ROAD_TOP + 0.01, mid) if along_z else Vector3(mid, ROAD_TOP + 0.01, center + side)
			_batch.add("dash", PropFactory.dash(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, 1.0, (b - a) / 3.0)), pos))
	else:
		var t := a + 1.5
		while t < b - 1.5:
			var pos := Vector3(center, ROAD_TOP + 0.01, t) if along_z else Vector3(t, ROAD_TOP + 0.01, center)
			_batch.add("dash", PropFactory.dash(), Transform3D(Basis(Vector3.UP, yaw), pos))
			t += 6.0


# --- Block -----------------------------------------------------------------------------

func _build_block(block: Dictionary) -> void:
	var rect: Rect2 = block.rect
	var district: CityPlan.District = block.district
	var params: Dictionary = CityPlan.DISTRICTS[district]
	var rng := RandomNumberGenerator.new()
	rng.seed = block.seed
	var center := rect.get_center()
	_add_slab(Vector3(center.x, SIDEWALK_TOP * 0.5, center.y), Vector3(rect.size.x, SIDEWALK_TOP, rect.size.y), style.sidewalk)
	match block.kind:
		CityPlan.BlockKind.PARK:
			_build_park(rect, rng)
		CityPlan.BlockKind.PLAZA:
			_build_plaza(rect, rng)
		_:
			_build_lots(rect, params, rng)
	if level == Level.FULL:
		_build_sidewalk_props(rect, params, rng)


## Lot layout is shared by FULL and LOD so both see the same buildings.
func _lots(rect: Rect2, params: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var inner := rect.grow(-plan.sidewalk_width)
	var lot_range: Vector2 = params.lot
	var lot_w := rng.randf_range(lot_range.x, lot_range.y)
	var lot_d := rng.randf_range(lot_range.x, lot_range.y)
	var nx := maxi(1, floori(inner.size.x / lot_w))
	var nz := maxi(1, floori(inner.size.y / lot_d))
	var cell := Vector2(inner.size.x / nx, inner.size.y / nz)
	var gap_range: Vector2 = params.gap
	var lots: Array[Dictionary] = []
	for lx in nx:
		for lz in nz:
			var edge := lx == 0 or lz == 0 or lx == nx - 1 or lz == nz - 1
			if not edge and rng.randf() < params.courtyard:
				continue
			var gap := rng.randf_range(gap_range.x, gap_range.y)
			var lot_size := cell - Vector2(gap, gap)
			if lot_size.x < 6.0 or lot_size.y < 6.0:
				continue
			var lot_center := inner.position + Vector2(cell.x * (lx + 0.5), cell.y * (lz + 0.5))
			lots.append({"seed": rng.randi(), "size": lot_size, "center": lot_center})
	return lots


func _build_lots(rect: Rect2, params: Dictionary, rng: RandomNumberGenerator) -> void:
	var heights: Vector2 = params.height
	for lot in _lots(rect, params, rng):
		var center: Vector2 = lot.center
		var building := BUILDING_SCENE.instantiate() as Building
		building.seed = lot.seed
		building.lot_size = lot.size
		building.min_height = heights.x
		building.max_height = heights.y
		building.lit_ratio_range = params.lit
		building.shape_options.assign(params.shapes)
		building.finish_options.assign(params.finishes)
		building.position = Vector3(center.x, SIDEWALK_TOP, center.y)
		if level == Level.FULL:
			add_child(building)
			building_count += 1
		else:
			# Far away: just the boxes, in the facade color, no props, no collision.
			building.plan_only()
			for part in building.parts:
				var size: Vector3 = part.size
				var part_center: Vector3 = part.center
				var xform := Transform3D(Basis().scaled(size), building.position + part_center)
				_batch.add("lod_box", PropFactory.unit_box(), xform, building.facade_color)
			building.free()
			building_count += 1


func _build_park(rect: Rect2, rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-2.0)
	var center := inner.get_center()
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.02, center.y), Vector3(inner.size.x, 0.04, inner.size.y), style.grass, false)
	if level != Level.FULL:
		return
	var path_w := 3.0
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.04, center.y), Vector3(inner.size.x, 0.02, path_w), style.path, false)
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.04, center.y), Vector3(path_w, 0.02, inner.size.y), style.path, false)
	for i in rng.randi_range(10, 24):
		var p := Vector2(rng.randf_range(inner.position.x + 3.0, inner.end.x - 3.0), rng.randf_range(inner.position.y + 3.0, inner.end.y - 3.0))
		if absf(p.x - center.x) < path_w or absf(p.y - center.y) < path_w:
			continue
		_add_tree(Vector3(p.x, SIDEWALK_TOP, p.y), rng)
	for i in rng.randi_range(4, 8):
		var along_x := rng.randf() < 0.5
		var t := rng.randf_range(-0.4, 0.4)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := center + (Vector2(inner.size.x * t, side * (path_w * 0.5 + 0.6)) if along_x else Vector2(side * (path_w * 0.5 + 0.6), inner.size.y * t))
		_add_bench(Vector3(p.x, SIDEWALK_TOP + 0.04, p.y), 0.0 if along_x else PI * 0.5)
	for dx: float in [-1.0, 1.0]:
		for dz: float in [-1.0, 1.0]:
			_add_lamp(Vector3(center.x + dx * (path_w * 0.5 + 1.0), SIDEWALK_TOP + 0.04, center.y + dz * (path_w * 0.5 + 1.0)))


func _build_plaza(rect: Rect2, rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-2.0)
	var center := inner.get_center()
	_add_slab(Vector3(center.x, SIDEWALK_TOP + 0.02, center.y), Vector3(inner.size.x, 0.04, inner.size.y), style.plaza, false)
	if level != Level.FULL:
		return
	var basin_r := minf(inner.size.x, inner.size.y) * 0.12
	var stone := Color(0.6, 0.58, 0.55)
	_add_cylinder(Vector3(center.x, SIDEWALK_TOP + 0.45, center.y), basin_r, 0.9, stone)
	_add_cylinder(Vector3(center.x, SIDEWALK_TOP + 0.8, center.y), basin_r - 0.5, 0.3, style.water, false, true)
	_add_cylinder(Vector3(center.x, SIDEWALK_TOP + 1.9, center.y), 0.6, 2.6, stone)
	_add_cylinder(Vector3(center.x, SIDEWALK_TOP + 3.3, center.y), 1.3, 0.25, stone, false)
	var ring := basin_r + 6.0
	for i in 4:
		var angle := i * PI * 0.5 + PI * 0.25
		var p := center + Vector2(cos(angle), sin(angle)) * ring
		_add_slab(Vector3(p.x, SIDEWALK_TOP + 0.35, p.y), Vector3(2.4, 0.7, 2.4), Color(0.55, 0.5, 0.45))
		_add_tree(Vector3(p.x, SIDEWALK_TOP + 0.7, p.y), rng)
	for i in 8:
		var angle := i * PI * 0.25
		var p := center + Vector2(cos(angle), sin(angle)) * (basin_r + 3.0)
		_add_bench(Vector3(p.x, SIDEWALK_TOP + 0.04, p.y), -angle + PI * 0.5)
	for dx: float in [-1.0, 1.0]:
		for dz: float in [-1.0, 1.0]:
			_add_lamp(Vector3(center.x + dx * inner.size.x * 0.3, SIDEWALK_TOP + 0.04, center.y + dz * inner.size.y * 0.3))


func _build_sidewalk_props(rect: Rect2, params: Dictionary, rng: RandomNumberGenerator) -> void:
	var tree_chance: float = params.trees
	var lamp_spacing: float = style.lamp_spacing
	var tree_spacing: float = style.tree_spacing
	var edges := [
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(0.0, 1.0)],
		[Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Vector2(0.0, -1.0)],
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Vector2(1.0, 0.0)],
		[Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), Vector2(-1.0, 0.0)],
	]
	var hydrant_edge := rng.randi() % 4
	var cans_left: int = style.trash_cans_per_block
	for e in edges.size():
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var t := lamp_spacing * (0.5 if e % 2 == 0 else 0.25)
		while t < length - 4.0:
			var p := a + dir * t + inward
			_add_lamp(Vector3(p.x, SIDEWALK_TOP, p.y))
			t += lamp_spacing
		t = tree_spacing * 0.75
		while t < length - 4.0:
			if rng.randf() < tree_chance and fmod(t, lamp_spacing) > 3.0:
				var p := a + dir * t + inward * 1.6
				_add_tree(Vector3(p.x, SIDEWALK_TOP, p.y), rng)
			t += tree_spacing
		if e == hydrant_edge:
			var p := a + dir * rng.randf_range(6.0, length - 6.0) + inward
			_add_prop("hydrant", Vector3(p.x, SIDEWALK_TOP, p.y), Color(0.85, 0.15, 0.12), [
				["hydrant", PropFactory.hydrant(), Transform3D(Basis(), Vector3(p.x, SIDEWALK_TOP + 0.4, p.y))],
			], [[Vector3(0.4, 0.8, 0.4), Vector3(p.x, SIDEWALK_TOP + 0.4, p.y), 0.0]])
		if cans_left > 0 and rng.randf() < 0.6 and PhysicsBudget.can_spawn():
			cans_left -= 1
			var p := a + dir * rng.randf_range(4.0, length - 4.0) + inward * 1.3
			var can := TrashCan.new()
			can.position = Vector3(p.x, SIDEWALK_TOP + 0.02, p.y)
			add_child(can)


# --- Intersections ---------------------------------------------------------------------

func _build_intersection(inter: Dictionary) -> void:
	var pos: Vector2 = inter.pos
	var size: Vector2 = inter.size
	var kind: CityPlan.Intersection = inter.kind
	var rng := RandomNumberGenerator.new()
	rng.seed = inter.seed
	if kind == CityPlan.Intersection.ROUNDABOUT:
		var r := minf(size.x, size.y) * 0.3
		_add_cylinder(Vector3(pos.x, ROAD_TOP + 0.15, pos.y), r, 0.3, style.sidewalk)
		_add_cylinder(Vector3(pos.x, ROAD_TOP + 0.31, pos.y), r - 0.8, 0.04, style.grass, false)
		_add_tree(Vector3(pos.x, ROAD_TOP + 0.3, pos.y), rng)
		return
	if kind == CityPlan.Intersection.PLAIN:
		return
	_add_crosswalks(pos, size)
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for c: Vector2 in corners:
		var corner := pos + Vector2(c.x * (size.x * 0.5 + 1.2), c.y * (size.y * 0.5 + 1.2))
		var at := Vector3(corner.x, SIDEWALK_TOP, corner.y)
		if kind == CityPlan.Intersection.STOP_SIGNS:
			var face := Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, atan2(-c.x, -c.y))
			_add_prop("stop_sign", at, Color(0.8, 0.12, 0.1), [
				["sign_pole", PropFactory.sign_pole(), Transform3D(Basis(), at + Vector3(0.0, 1.3, 0.0))],
				["stop_sign", PropFactory.stop_sign(), Transform3D(face, at + Vector3(0.0, 2.4, 0.0))],
			], [[Vector3(0.3, 2.8, 0.3), at + Vector3(0.0, 1.4, 0.0), 0.0]])
		else:
			_add_signal(at, c, size)


func _add_crosswalks(pos: Vector2, size: Vector2) -> void:
	for side: float in [-1.0, 1.0]:
		var z := pos.y + side * (size.y * 0.5 + 1.8)
		var x := pos.x - size.x * 0.5 + 1.2
		while x < pos.x + size.x * 0.5 - 0.6:
			_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, ROAD_TOP + 0.015, z)))
			x += 1.4
		var xx := pos.x + side * (size.x * 0.5 + 1.8)
		var zz := pos.y - size.y * 0.5 + 1.2
		while zz < pos.y + size.y * 0.5 - 0.6:
			_batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(), Vector3(xx, ROAD_TOP + 0.015, zz)))
			zz += 1.4


func _add_signal(at: Vector3, corner: Vector2, size: Vector2) -> void:
	var along_x := size.x >= size.y
	var dir := Vector3(-corner.x, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, -corner.y)
	var yaw := 0.0 if along_x else PI * 0.5
	var arm_center := at + Vector3(0.0, 6.2, 0.0) + dir * 2.5
	var box_pos := at + Vector3(0.0, 5.5, 0.0) + dir * 4.6
	var instances := [
		["signal_pole", PropFactory.signal_pole(), Transform3D(Basis(), at + Vector3(0.0, 3.25, 0.0))],
		["signal_arm", PropFactory.signal_arm(), Transform3D(Basis(Vector3.UP, yaw), arm_center)],
		["signal_box", PropFactory.signal_box(), Transform3D(Basis(), box_pos)],
	]
	var colors := [Color(1.0, 0.2, 0.15), Color(1.0, 0.8, 0.2), Color(0.2, 1.0, 0.3)]
	var facing := (Vector3(0.0, 0.0, 0.2) if along_x else Vector3(0.2, 0.0, 0.0)) * (corner.y if along_x else corner.x)
	for i in 3:
		instances.append(["signal_light_%d" % i, PropFactory.signal_light(colors[i]), Transform3D(Basis(), box_pos + Vector3(0.0, 0.32 - i * 0.32, 0.0) + facing)])
	_add_prop("signal", at, Color(0.2, 0.2, 0.22), instances, [[Vector3(0.3, 6.5, 0.3), at + Vector3(0.0, 3.25, 0.0), 0.0]])


# --- Props (destructible) --------------------------------------------------------------

## Registers a breakable prop: MultiMesh instances plus collision shapes tagged with its record.
## Skipped entirely if WorldState says this prop was already destroyed.
func _add_prop(kind: String, at: Vector3, color: Color, instances: Array, shapes: Array) -> void:
	var id := "%s_%d" % [kind, _prop_counter]
	_prop_counter += 1
	if WorldState.is_destroyed(key, id):
		return
	var record := {"id": id, "kind": kind, "position": at, "color": color, "health": PROP_HEALTH.get(kind, 20.0), "instances": [], "shapes": [], "dead": false}
	for inst in instances:
		var index := _batch.add(inst[0], inst[1], inst[2])
		record.instances.append([inst[0], index])
	for s in shapes:
		var shape := _add_shape(s[0], s[1], s[2])
		if shape:
			shape.set_meta("prop", record)
			record.shapes.append(shape)
	prop_records.append(record)


func damage_prop(record: Dictionary, damage: float, hit_dir: Vector3) -> void:
	if record.dead:
		return
	record.health -= damage
	if record.health <= 0.0:
		break_prop(record, hit_dir)


func break_prop(record: Dictionary, hit_dir: Vector3 = Vector3.UP) -> void:
	if record.dead:
		return
	record.dead = true
	for inst in record.instances:
		MultiMeshBatch.hide_instance(_mm_nodes.get(inst[0]), inst[1])
	for shape in record.shapes:
		if is_instance_valid(shape):
			shape.queue_free()
	WorldState.mark_destroyed(key, record.id)
	_spawn_debris(record.position, record.color, hit_dir)


func _spawn_debris(at: Vector3, color: Color, hit_dir: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([at.x, at.z, Time.get_ticks_msec()])
	var pieces := 4
	if not PhysicsBudget.make_room(pieces):
		return
	for i in pieces:
		var body := RigidBody3D.new()
		body.collision_layer = 4
		body.collision_mask = 7
		body.mass = 1.5
		var size := Vector3(rng.randf_range(0.2, 0.5), rng.randf_range(0.3, 1.2), rng.randf_range(0.2, 0.5))
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = PropFactory.material(color)
		body.add_child(mesh)
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		body.add_child(shape)
		body.position = at + Vector3(rng.randf_range(-0.4, 0.4), 0.6 + i * 0.7, rng.randf_range(-0.4, 0.4))
		add_child(body)
		PhysicsBudget.register_debris(body)
		body.linear_velocity = (hit_dir.normalized() * 6.0 + Vector3(rng.randf_range(-3, 3), rng.randf_range(4, 9), rng.randf_range(-3, 3)))
		body.angular_velocity = Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6))


func _add_lamp(at: Vector3) -> void:
	_add_prop("lamp", at, Color(0.28, 0.29, 0.32), [
		["lamp_pole", PropFactory.lamp_pole(), Transform3D(Basis(), at + Vector3(0.0, 3.0, 0.0))],
		["lamp_head", PropFactory.lamp_head(), Transform3D(Basis(), at + Vector3(0.0, 6.05, 0.0))],
	], [[Vector3(0.25, 6.0, 0.25), at + Vector3(0.0, 3.0, 0.0), 0.0]])


func _add_bench(at: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_add_prop("bench", at, Color(0.5, 0.36, 0.22), [
		["bench_legs", PropFactory.bench_legs(), Transform3D(basis, at + Vector3(0.0, 0.22, 0.0))],
		["bench", PropFactory.bench(), Transform3D(basis, at + Vector3(0.0, 0.5, 0.0))],
	], [[Vector3(1.8, 0.55, 0.5), at + Vector3(0.0, 0.28, 0.0), yaw]])


func _add_tree(at: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.8, 1.4)
	var yaw := rng.randf_range(0.0, TAU)
	_batch.add("trunk", PropFactory.trunk(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at + Vector3(0.0, 1.1 * s, 0.0)))
	var tint := Color(rng.randf_range(0.8, 1.1), rng.randf_range(0.85, 1.15), rng.randf_range(0.8, 1.05))
	if rng.randf() < 0.7:
		_batch.add("canopy_round", PropFactory.canopy_round(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s)), at + Vector3(0.0, 3.4 * s, 0.0)), tint)
	else:
		_batch.add("canopy_cone", PropFactory.canopy_cone(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at + Vector3(0.0, 3.8 * s, 0.0)), tint)


# --- Helpers ---------------------------------------------------------------------------

func _add_slab(pos: Vector3, size: Vector3, color: Color, collide: bool = true) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = PropFactory.material(color, 0.95)
	mesh.position = pos
	add_child(mesh)
	if collide:
		_add_shape(size, pos)


func _add_cylinder(pos: Vector3, radius: float, height: float, color: Color, collide: bool = true, unshaded: bool = false) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 16
	mesh.mesh = cyl
	mesh.material_override = PropFactory.material(color, 0.9, unshaded)
	mesh.position = pos
	add_child(mesh)
	if collide and _statics:
		var shape := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		shape.shape = s
		shape.position = pos
		_statics.add_child(shape)


func _add_shape(size: Vector3, pos: Vector3, yaw: float = 0.0) -> CollisionShape3D:
	if _statics == null:
		return null
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	shape.rotation.y = yaw
	_statics.add_child(shape)
	return shape
