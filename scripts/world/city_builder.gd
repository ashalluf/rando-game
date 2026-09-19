class_name CityBuilder
extends Node3D
## Turns a CityPlan into the world: ground, roads with markings, blocks with buildings,
## parks and plazas, intersections, and street props. Everything comes from `world_seed`.

const BUILDING_SCENE := preload("res://scenes/props/building.tscn")
const ROAD_TOP := 0.1
const SIDEWALK_TOP := 0.25

@export_group("City")
@export var world_seed: int = 1337
## Blocks on each axis. 5 x 5 is a small town; the center intersection is always at (0, 0).
@export var blocks_x: int = 5
@export var blocks_z: int = 5
@export var block_size_range: Vector2 = Vector2(70.0, 120.0)
@export var street_width: float = 14.0
@export var avenue_width: float = 24.0
@export var sidewalk_width: float = 4.0
@export var ground_size: float = 1600.0

@export_group("Street life")
@export var lamp_spacing: float = 24.0
@export var tree_spacing: float = 12.0
@export var trash_cans_per_block: int = 2

@export_group("Look")
@export var sun_rotation_degrees: Vector3 = Vector3(-48.0, 35.0, 0.0)
@export var ground_color: Color = Color(0.45, 0.48, 0.36)
@export var asphalt_color: Color = Color(0.20, 0.20, 0.22)
@export var sidewalk_color: Color = Color(0.68, 0.66, 0.62)
@export var grass_color: Color = Color(0.36, 0.58, 0.30)
@export var plaza_color: Color = Color(0.78, 0.74, 0.68)
@export var path_color: Color = Color(0.80, 0.76, 0.66)
@export var water_color: Color = Color(0.25, 0.55, 0.80)

var plan: CityPlan
var building_count: int = 0

var _batch := MultiMeshBatch.new()
var _statics: StaticBody3D
var _rng := RandomNumberGenerator.new()
var _materials: Dictionary = {}


func _ready() -> void:
	add_to_group("city")
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = sun_rotation_degrees
	generate()


func generate() -> void:
	plan = CityPlan.new()
	plan.seed = world_seed
	plan.blocks_x = blocks_x
	plan.blocks_z = blocks_z
	plan.block_size_range = block_size_range
	plan.street_width = street_width
	plan.avenue_width = avenue_width
	plan.sidewalk_width = sidewalk_width
	plan.generate()
	_rng.seed = world_seed + 99

	_statics = StaticBody3D.new()
	_statics.name = "StreetProps"
	_statics.collision_layer = 1
	_statics.collision_mask = 7
	add_child(_statics)

	_build_ground()
	_build_roads()
	for block in plan.blocks:
		_build_block(block)
	for inter in plan.intersections:
		_build_intersection(inter)
	_batch.build(self)


func district_name_at(pos: Vector3) -> String:
	if plan == null:
		return ""
	return CityPlan.district_name(plan.district_at(Vector2(pos.x, pos.z)))


# --- Ground and roads ----------------------------------------------------------------

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 7
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_size, ground_size)
	mesh.mesh = plane
	mesh.material_override = _material(ground_color)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ground_size, 2.0, ground_size)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	add_child(body)


func _build_roads() -> void:
	var z_min := plan.road_zs[0] - plan.road_z_widths[0] * 0.5 - sidewalk_width
	var z_max := plan.road_zs[-1] + plan.road_z_widths[-1] * 0.5 + sidewalk_width
	var x_min := plan.road_xs[0] - plan.road_x_widths[0] * 0.5 - sidewalk_width
	var x_max := plan.road_xs[-1] + plan.road_x_widths[-1] * 0.5 + sidewalk_width
	for i in plan.road_xs.size():
		var x := plan.road_xs[i]
		var w := plan.road_x_widths[i]
		_add_static_box(Vector3(x, ROAD_TOP * 0.5, (z_min + z_max) * 0.5), Vector3(w, ROAD_TOP, z_max - z_min), asphalt_color)
		_mark_road(true, x, w, plan.road_zs, plan.road_z_widths)
	for i in plan.road_zs.size():
		var z := plan.road_zs[i]
		var w := plan.road_z_widths[i]
		_add_static_box(Vector3((x_min + x_max) * 0.5, ROAD_TOP * 0.5, z), Vector3(x_max - x_min, ROAD_TOP, w), asphalt_color)
		_mark_road(false, z, w, plan.road_xs, plan.road_x_widths)


## Center-line markings between intersections: dashed yellow on streets, double solid on avenues.
func _mark_road(along_z: bool, center: float, width: float, crossings: PackedFloat32Array, crossing_widths: PackedFloat32Array) -> void:
	var avenue := width >= avenue_width - 0.1
	for i in crossings.size() - 1:
		var a := crossings[i] + crossing_widths[i] * 0.5 + 3.0
		var b := crossings[i + 1] - crossing_widths[i + 1] * 0.5 - 3.0
		if b - a < 4.0:
			continue
		var yaw := 0.0 if along_z else PI * 0.5
		if avenue:
			for side: float in [-0.3, 0.3]:
				var mid := (a + b) * 0.5
				var pos := Vector3(center + side, ROAD_TOP + 0.01, mid) if along_z else Vector3(mid, ROAD_TOP + 0.01, center + side)
				var xform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, 1.0, (b - a) / 3.0)), pos)
				_batch.add("dash", PropFactory.dash(), xform)
		else:
			var t := a + 1.5
			while t < b - 1.5:
				var pos := Vector3(center, ROAD_TOP + 0.01, t) if along_z else Vector3(t, ROAD_TOP + 0.01, center)
				_batch.add("dash", PropFactory.dash(), Transform3D(Basis(Vector3.UP, yaw), pos))
				t += 6.0


# --- Blocks --------------------------------------------------------------------------

func _build_block(block: Dictionary) -> void:
	var rect: Rect2 = block.rect
	var district: CityPlan.District = block.district
	var params: Dictionary = CityPlan.DISTRICTS[district]
	var rng := RandomNumberGenerator.new()
	rng.seed = block.seed
	var center := rect.get_center()
	# Sidewalk slab under the whole block.
	_add_static_box(Vector3(center.x, SIDEWALK_TOP * 0.5, center.y), Vector3(rect.size.x, SIDEWALK_TOP, rect.size.y), sidewalk_color)
	match block.kind:
		CityPlan.BlockKind.PARK:
			_build_park(rect, rng)
		CityPlan.BlockKind.PLAZA:
			_build_plaza(rect, rng)
		_:
			_build_lots(rect, params, rng)
	_build_sidewalk_props(rect, params, rng)


func _build_lots(rect: Rect2, params: Dictionary, rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-sidewalk_width)
	var lot_range: Vector2 = params.lot
	var lot_w := rng.randf_range(lot_range.x, lot_range.y)
	var lot_d := rng.randf_range(lot_range.x, lot_range.y)
	var nx := maxi(1, floori(inner.size.x / lot_w))
	var nz := maxi(1, floori(inner.size.y / lot_d))
	var cell := Vector2(inner.size.x / nx, inner.size.y / nz)
	var heights: Vector2 = params.height
	var gap_range: Vector2 = params.gap
	for ix in nx:
		for iz in nz:
			var edge := ix == 0 or iz == 0 or ix == nx - 1 or iz == nz - 1
			if not edge and rng.randf() < params.courtyard:
				continue
			var gap := rng.randf_range(gap_range.x, gap_range.y)
			var lot_size := cell - Vector2(gap, gap)
			if lot_size.x < 6.0 or lot_size.y < 6.0:
				continue
			var lot_center := inner.position + Vector2(cell.x * (ix + 0.5), cell.y * (iz + 0.5))
			var building := BUILDING_SCENE.instantiate() as Building
			building.seed = rng.randi()
			building.lot_size = lot_size
			building.min_height = heights.x
			building.max_height = heights.y
			building.lit_ratio_range = params.lit
			building.shape_options.assign(params.shapes)
			building.finish_options.assign(params.finishes)
			building.position = Vector3(lot_center.x, SIDEWALK_TOP, lot_center.y)
			add_child(building)
			building_count += 1


func _build_park(rect: Rect2, rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-2.0)
	var center := inner.get_center()
	_add_static_box(Vector3(center.x, SIDEWALK_TOP + 0.02, center.y), Vector3(inner.size.x, 0.04, inner.size.y), grass_color, false)
	# Cross paths.
	var path_w := 3.0
	_add_static_box(Vector3(center.x, SIDEWALK_TOP + 0.04, center.y), Vector3(inner.size.x, 0.02, path_w), path_color, false)
	_add_static_box(Vector3(center.x, SIDEWALK_TOP + 0.04, center.y), Vector3(path_w, 0.02, inner.size.y), path_color, false)
	# Trees off the paths.
	var count := rng.randi_range(10, 24)
	for i in count:
		var p := Vector2(rng.randf_range(inner.position.x + 3.0, inner.end.x - 3.0), rng.randf_range(inner.position.y + 3.0, inner.end.y - 3.0))
		if absf(p.x - center.x) < path_w or absf(p.y - center.y) < path_w:
			continue
		_add_tree(Vector3(p.x, SIDEWALK_TOP, p.y), rng)
	# Benches along the paths, lamps at the crossing.
	for i in rng.randi_range(4, 8):
		var along_x := rng.randf() < 0.5
		var t := rng.randf_range(-0.4, 0.4)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := center + (Vector2(inner.size.x * t, side * (path_w * 0.5 + 0.6)) if along_x else Vector2(side * (path_w * 0.5 + 0.6), inner.size.y * t))
		_add_bench(Vector3(p.x, SIDEWALK_TOP + 0.04, p.y), 0.0 if along_x else PI * 0.5)
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			_add_lamp(Vector3(center.x + dx * (path_w * 0.5 + 1.0), SIDEWALK_TOP + 0.04, center.y + dz * (path_w * 0.5 + 1.0)))


func _build_plaza(rect: Rect2, rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-2.0)
	var center := inner.get_center()
	_add_static_box(Vector3(center.x, SIDEWALK_TOP + 0.02, center.y), Vector3(inner.size.x, 0.04, inner.size.y), plaza_color, false)
	# Fountain: basin, water, pillar.
	var basin_r := minf(inner.size.x, inner.size.y) * 0.12
	_add_static_cylinder(Vector3(center.x, SIDEWALK_TOP + 0.45, center.y), basin_r, 0.9, Color(0.6, 0.58, 0.55))
	_add_static_cylinder(Vector3(center.x, SIDEWALK_TOP + 0.8, center.y), basin_r - 0.5, 0.3, water_color, false, true)
	_add_static_cylinder(Vector3(center.x, SIDEWALK_TOP + 1.9, center.y), 0.6, 2.6, Color(0.6, 0.58, 0.55))
	_add_static_cylinder(Vector3(center.x, SIDEWALK_TOP + 3.3, center.y), 1.3, 0.25, Color(0.6, 0.58, 0.55), false)
	# Planters with trees, benches around the fountain.
	var ring := basin_r + 6.0
	for i in 4:
		var angle := i * PI * 0.5 + PI * 0.25
		var p := center + Vector2(cos(angle), sin(angle)) * ring
		_add_static_box(Vector3(p.x, SIDEWALK_TOP + 0.35, p.y), Vector3(2.4, 0.7, 2.4), Color(0.55, 0.5, 0.45))
		_add_tree(Vector3(p.x, SIDEWALK_TOP + 0.7, p.y), rng)
	for i in 8:
		var angle := i * PI * 0.25
		var p := center + Vector2(cos(angle), sin(angle)) * (basin_r + 3.0)
		_add_bench(Vector3(p.x, SIDEWALK_TOP + 0.04, p.y), -angle + PI * 0.5)
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			_add_lamp(Vector3(center.x + dx * inner.size.x * 0.3, SIDEWALK_TOP + 0.04, center.y + dz * inner.size.y * 0.3))


## Lamps, trees, hydrants, trash cans along the four curbs of a block.
func _build_sidewalk_props(rect: Rect2, params: Dictionary, rng: RandomNumberGenerator) -> void:
	var tree_chance: float = params.trees
	var edges := [
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(0.0, 1.0)],
		[Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Vector2(0.0, -1.0)],
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Vector2(1.0, 0.0)],
		[Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), Vector2(-1.0, 0.0)],
	]
	var hydrant_edge := rng.randi() % 4
	var cans_left := trash_cans_per_block
	for e in edges.size():
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var curb_offset := inward * 1.0
		var tree_offset := inward * 1.6
		# Lamps, offset half a spacing on alternate edges so corners don't crowd.
		var t := lamp_spacing * (0.5 if e % 2 == 0 else 0.25)
		while t < length - 4.0:
			var p := a + dir * t + curb_offset
			_add_lamp(Vector3(p.x, SIDEWALK_TOP, p.y))
			t += lamp_spacing
		t = tree_spacing * 0.75
		while t < length - 4.0:
			if rng.randf() < tree_chance and fmod(t, lamp_spacing) > 3.0:
				var p := a + dir * t + tree_offset
				_add_tree(Vector3(p.x, SIDEWALK_TOP, p.y), rng)
			t += tree_spacing
		if e == hydrant_edge:
			var p := a + dir * rng.randf_range(6.0, length - 6.0) + curb_offset
			_batch.add("hydrant", PropFactory.hydrant(), Transform3D(Basis(), Vector3(p.x, SIDEWALK_TOP + 0.4, p.y)))
			_add_static_shape(Vector3(0.4, 0.8, 0.4), Vector3(p.x, SIDEWALK_TOP + 0.4, p.y))
		if cans_left > 0 and rng.randf() < 0.6 and PhysicsBudget.can_spawn():
			cans_left -= 1
			var p := a + dir * rng.randf_range(4.0, length - 4.0) + inward * 1.3
			var can := TrashCan.new()
			can.position = Vector3(p.x, SIDEWALK_TOP + 0.02, p.y)
			add_child(can)


# --- Intersections -------------------------------------------------------------------

func _build_intersection(inter: Dictionary) -> void:
	var pos: Vector2 = inter.pos
	var size: Vector2 = inter.size
	var kind: CityPlan.Intersection = inter.kind
	var rng := RandomNumberGenerator.new()
	rng.seed = inter.seed
	if kind == CityPlan.Intersection.ROUNDABOUT:
		var r := minf(size.x, size.y) * 0.3
		_add_static_cylinder(Vector3(pos.x, ROAD_TOP + 0.15, pos.y), r, 0.3, sidewalk_color)
		_add_static_cylinder(Vector3(pos.x, ROAD_TOP + 0.31, pos.y), r - 0.8, 0.04, grass_color, false)
		_add_tree(Vector3(pos.x, ROAD_TOP + 0.3, pos.y), rng)
		return
	if kind == CityPlan.Intersection.PLAIN:
		return
	_add_crosswalks(pos, size)
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for c in corners:
		var corner := pos + Vector2(c.x * (size.x * 0.5 + 1.2), c.y * (size.y * 0.5 + 1.2))
		var at := Vector3(corner.x, SIDEWALK_TOP, corner.y)
		if kind == CityPlan.Intersection.STOP_SIGNS:
			_batch.add("sign_pole", PropFactory.sign_pole(), Transform3D(Basis(), at + Vector3(0.0, 1.3, 0.0)))
			var face := Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, atan2(-c.x, -c.y))
			_batch.add("stop_sign", PropFactory.stop_sign(), Transform3D(face, at + Vector3(0.0, 2.4, 0.0)))
		else:
			_add_signal(at, c, size)


func _add_crosswalks(pos: Vector2, size: Vector2) -> void:
	for side: float in [-1.0, 1.0]:
		# Stripes across the X road (walking along X), placed just outside the box on the Z axis.
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
	_batch.add("signal_pole", PropFactory.signal_pole(), Transform3D(Basis(), at + Vector3(0.0, 3.25, 0.0)))
	_add_static_shape(Vector3(0.3, 6.5, 0.3), at + Vector3(0.0, 3.25, 0.0))
	# Arm reaches over the road toward the intersection, along the longer road side.
	var along_x := size.x >= size.y
	var dir := Vector3(-corner.x, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, -corner.y)
	var yaw := 0.0 if along_x else PI * 0.5
	var arm_center := at + Vector3(0.0, 6.2, 0.0) + dir * 2.5
	_batch.add("signal_arm", PropFactory.signal_arm(), Transform3D(Basis(Vector3.UP, yaw), arm_center))
	var box_pos := at + Vector3(0.0, 5.5, 0.0) + dir * 4.6
	_batch.add("signal_box", PropFactory.signal_box(), Transform3D(Basis(), box_pos))
	var colors := [Color(1.0, 0.2, 0.15), Color(1.0, 0.8, 0.2), Color(0.2, 1.0, 0.3)]
	for i in 3:
		var light_pos := box_pos + Vector3(0.0, 0.32 - i * 0.32, 0.0) + (Vector3(0.0, 0.0, 0.2) if along_x else Vector3(0.2, 0.0, 0.0)) * (corner.y if along_x else corner.x)
		_batch.add("signal_light_%d" % i, PropFactory.signal_light(colors[i]), Transform3D(Basis(), light_pos))


# --- Props ---------------------------------------------------------------------------

func _add_tree(at: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.8, 1.4)
	var yaw := rng.randf_range(0.0, TAU)
	var trunk_xform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at + Vector3(0.0, 1.1 * s, 0.0))
	_batch.add("trunk", PropFactory.trunk(), trunk_xform)
	var tint := Color(rng.randf_range(0.8, 1.1), rng.randf_range(0.85, 1.15), rng.randf_range(0.8, 1.05))
	if rng.randf() < 0.7:
		_batch.add("canopy_round", PropFactory.canopy_round(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s)), at + Vector3(0.0, 3.4 * s, 0.0)), tint)
	else:
		_batch.add("canopy_cone", PropFactory.canopy_cone(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at + Vector3(0.0, 3.8 * s, 0.0)), tint)


func _add_lamp(at: Vector3) -> void:
	_batch.add("lamp_pole", PropFactory.lamp_pole(), Transform3D(Basis(), at + Vector3(0.0, 3.0, 0.0)))
	_batch.add("lamp_head", PropFactory.lamp_head(), Transform3D(Basis(), at + Vector3(0.0, 6.05, 0.0)))
	_add_static_shape(Vector3(0.25, 6.0, 0.25), at + Vector3(0.0, 3.0, 0.0))


func _add_bench(at: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_batch.add("bench_legs", PropFactory.bench_legs(), Transform3D(basis, at + Vector3(0.0, 0.22, 0.0)))
	_batch.add("bench", PropFactory.bench(), Transform3D(basis, at + Vector3(0.0, 0.5, 0.0)))
	_add_static_shape(Vector3(1.8, 0.55, 0.5), at + Vector3(0.0, 0.28, 0.0), yaw)


# --- Helpers -------------------------------------------------------------------------

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_rgba32()
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	_materials[key] = mat
	return mat


func _add_static_box(pos: Vector3, size: Vector3, color: Color, collide: bool = true) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	mesh.position = pos
	add_child(mesh)
	if collide:
		_add_static_shape(size, pos)


func _add_static_cylinder(pos: Vector3, radius: float, height: float, color: Color, collide: bool = true, unshaded: bool = false) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 16
	mesh.mesh = cyl
	mesh.material_override = PropFactory.material(color, 0.9, unshaded) if unshaded else _material(color)
	mesh.position = pos
	add_child(mesh)
	if collide:
		var shape := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		shape.shape = s
		shape.position = pos
		_statics.add_child(shape)


func _add_static_shape(size: Vector3, pos: Vector3, yaw: float = 0.0) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	shape.rotation.y = yaw
	_statics.add_child(shape)
