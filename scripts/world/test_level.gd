extends Node3D
## Greybox test level. Everything is generated in code from `world_seed`;
## the same seed always produces the same layout.

const CRATE_SCENE := preload("res://scenes/props/crate.tscn")
const BUILDING_SCENE := preload("res://scenes/props/building.tscn")

@export_group("Generation")
@export var world_seed: int = 1337
## Side length of the flat ground square (meters).
@export var ground_size: float = 400.0
## Nothing is generated within this radius of the spawn point.
@export var spawn_clear_radius: float = 26.0
@export var tall_box_count: int = 40
@export var tall_box_min_height: float = 3.0
@export var tall_box_max_height: float = 60.0
@export var ramp_count: int = 6
@export var crate_count: int = 100
## Center of the demo city block (a ring of seeded buildings around a sidewalk slab).
@export var block_center: Vector3 = Vector3(0.0, 0.0, -125.0)
@export var block_size: Vector2 = Vector2(150.0, 90.0)
@export var buildings_per_row: int = 5
@export var building_min_height: float = 8.0
@export var building_max_height: float = 70.0
## Heights (meters) of the jump gauge boxes in front of spawn.
@export var jump_gauge_heights: PackedFloat32Array = PackedFloat32Array([4, 8, 12, 16, 20, 24, 30])

@export_group("Look")
@export var sun_rotation_degrees: Vector3 = Vector3(-52.0, 38.0, 0.0)
@export var ground_color_a: Color = Color(0.50, 0.55, 0.46)
@export var ground_color_b: Color = Color(0.38, 0.43, 0.35)
@export var sidewalk_color: Color = Color(0.72, 0.70, 0.66)
## Size of one ground checker cell (meters).
@export var ground_cell_size: float = 2.0
@export var box_palette: PackedColorArray = PackedColorArray([
	Color(0.85, 0.35, 0.30), Color(0.30, 0.55, 0.85), Color(0.95, 0.75, 0.25),
	Color(0.40, 0.75, 0.45), Color(0.70, 0.45, 0.80), Color(0.90, 0.90, 0.88),
])
@export var crate_palette: PackedColorArray = PackedColorArray([
	Color(0.78, 0.55, 0.30), Color(0.70, 0.48, 0.26), Color(0.84, 0.62, 0.36),
])

var _materials: Dictionary = {}


func _ready() -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = sun_rotation_degrees
	generate()


func generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	_build_ground()
	_build_jump_gauge()
	_build_ramps(rng)
	_build_tall_boxes(rng)
	_build_crates(rng)
	_build_city_block(rng)


# --- Pieces ------------------------------------------------------------------

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 7

	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_size, ground_size)
	mesh.mesh = plane
	mesh.material_override = _checker_material()
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ground_size, 2.0, ground_size)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	add_child(body)


func _build_jump_gauge() -> void:
	# A row of boxes of known heights so "how high can I jump" is easy to read.
	var count := jump_gauge_heights.size()
	var spacing := 4.0
	var x0 := -(count - 1) * spacing * 0.5
	for i in count:
		var h := jump_gauge_heights[i]
		var pos := Vector3(x0 + i * spacing, h * 0.5, -22.0)
		var color := box_palette[i % box_palette.size()]
		_add_static_box(pos, Vector3(3.0, h, 3.0), color)
		var label := Label3D.new()
		label.text = "%d m" % int(h)
		label.font_size = 96
		label.pixel_size = 0.02
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = pos + Vector3(0.0, h * 0.5 + 1.0, 0.0)
		label.outline_size = 16
		add_child(label)


func _build_ramps(rng: RandomNumberGenerator) -> void:
	var thickness := 0.6
	for i in ramp_count:
		var angle := TAU * (float(i) + rng.randf_range(0.1, 0.9)) / ramp_count
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var dist := rng.randf_range(spawn_clear_radius + 8.0, spawn_clear_radius + 26.0)
		var length := rng.randf_range(14.0, 26.0)
		var width := rng.randf_range(5.0, 9.0)
		var pitch := deg_to_rad(rng.randf_range(15.0, 35.0))
		var center := dir * dist + Vector3(0.0, length * 0.5 * sin(pitch) - thickness * 0.5, 0.0)
		var yaw := atan2(-dir.x, -dir.z) # local -Z (the raised end) points away from spawn
		var color := box_palette[rng.randi() % box_palette.size()]
		_add_static_box(center, Vector3(width, thickness, length), color, yaw, pitch)


func _build_tall_boxes(rng: RandomNumberGenerator) -> void:
	var half := ground_size * 0.5 - 20.0
	var placed := 0
	var attempts := 0
	while placed < tall_box_count and attempts < tall_box_count * 20:
		attempts += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if Vector2(x, z).length() < spawn_clear_radius + 30.0:
			continue
		if _block_rect().grow(20.0).has_point(Vector2(x, z)):
			continue
		var height := lerpf(tall_box_min_height, tall_box_max_height, pow(rng.randf(), 2.2))
		var size := Vector3(rng.randf_range(4.0, 14.0), height, rng.randf_range(4.0, 14.0))
		var color := box_palette[rng.randi() % box_palette.size()]
		var yaw := deg_to_rad(rng.randf_range(0.0, 90.0)) if rng.randf() < 0.3 else 0.0
		var box := _add_static_box(Vector3(x, height * 0.5, z), size, color, yaw)
		# Some boxes get a smaller step on top so there is something to land on.
		if rng.randf() < 0.4:
			var step_h := rng.randf_range(2.0, 6.0)
			var step := Vector3(size.x * 0.5, step_h, size.z * 0.5)
			var child := _make_box_visual(step, color.darkened(0.15))
			child.position = Vector3(0.0, height * 0.5 + step_h * 0.5, 0.0)
			box.add_child(child)
			var shape := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = step
			shape.shape = bs
			shape.position = child.position
			box.add_child(shape)
		placed += 1


func _build_crates(rng: RandomNumberGenerator) -> void:
	var spawned := 0
	# Pyramid pile.
	var pile_center := Vector3(18.0, 0.0, -6.0)
	var base := 5
	for layer in base:
		var n := base - layer
		for ix in n:
			for iz in n:
				if spawned >= crate_count or not PhysicsBudget.can_spawn():
					return
				var offset := Vector3((ix - (n - 1) * 0.5) * 1.05, 0.55 + layer * 1.02, (iz - (n - 1) * 0.5) * 1.05)
				offset += Vector3(rng.randf_range(-0.03, 0.03), 0.0, rng.randf_range(-0.03, 0.03))
				_spawn_crate(pile_center + offset, rng)
				spawned += 1
	# Wall to run through.
	var wall_origin := Vector3(-14.0, 0.0, -4.0)
	for ix in 8:
		for iy in 5:
			if spawned >= crate_count or not PhysicsBudget.can_spawn():
				return
			var pos := wall_origin + Vector3(0.0, 0.55 + iy * 1.02, (ix - 3.5) * 1.05)
			_spawn_crate(pos, rng)
			spawned += 1


func _block_rect() -> Rect2:
	return Rect2(Vector2(block_center.x, block_center.z) - block_size * 0.5, block_size)


## Two rows of seeded buildings on a sidewalk slab, facing a gap in the middle like a street.
func _build_city_block(rng: RandomNumberGenerator) -> void:
	_add_static_box(block_center + Vector3(0.0, 0.1, 0.0), Vector3(block_size.x, 0.2, block_size.y), sidewalk_color)
	var lot_w := block_size.x / buildings_per_row
	var lot_d := block_size.y * 0.5
	for row in 2:
		for i in buildings_per_row:
			var lot_center := block_center + Vector3(
				-block_size.x * 0.5 + lot_w * (i + 0.5), 0.2,
				-block_size.y * 0.5 + lot_d * (row + 0.5))
			var building := BUILDING_SCENE.instantiate() as Building
			building.seed = rng.randi()
			building.lot_size = Vector2(lot_w - 6.0, lot_d - 8.0)
			building.min_height = building_min_height
			building.max_height = building_max_height
			building.position = lot_center
			add_child(building)


# --- Helpers -----------------------------------------------------------------

func _spawn_crate(pos: Vector3, rng: RandomNumberGenerator) -> RigidBody3D:
	var crate := CRATE_SCENE.instantiate() as RigidBody3D
	crate.position = pos
	crate.rotation.y = rng.randf_range(-0.05, 0.05)
	add_child(crate)
	crate.set_material(_material(crate_palette[rng.randi() % crate_palette.size()]))
	return crate


func _add_static_box(pos: Vector3, size: Vector3, color: Color, yaw: float = 0.0, pitch: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 7
	body.add_child(_make_box_visual(size, color))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	body.rotation = Vector3(pitch, yaw, 0.0)
	add_child(body)
	return body


func _make_box_visual(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	return mesh


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_rgba32()
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	_materials[key] = mat
	return mat


func _checker_material() -> StandardMaterial3D:
	var img := Image.create_empty(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, ground_color_a)
	img.set_pixel(1, 1, ground_color_a)
	img.set_pixel(1, 0, ground_color_b)
	img.set_pixel(0, 1, ground_color_b)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 1.0
	var repeats := ground_size / (ground_cell_size * 2.0)
	mat.uv1_scale = Vector3(repeats, repeats, 1.0)
	return mat
