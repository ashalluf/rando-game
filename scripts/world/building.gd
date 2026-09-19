class_name Building
extends StaticBody3D
## One seeded building. Picks a shape style, dimensions, facade finish, window style,
## colors and rooftop props from small option lists. Same seed, same building.

const SHADER: Shader = preload("res://shaders/building.gdshader")

enum Shape { SLAB, TOWER, STEPPED, PODIUM_TOWER, L_SHAPE, WAREHOUSE }
enum WindowStyle { PUNCHED, RIBBON, CURTAIN, NARROW }
enum Finish { FLAT, BRICK, PANELS, GLASS }

const FLAT_COLORS := [
	Color(0.72, 0.66, 0.56), Color(0.62, 0.66, 0.70), Color(0.76, 0.58, 0.48),
	Color(0.58, 0.64, 0.54), Color(0.70, 0.60, 0.70), Color(0.80, 0.76, 0.66),
]
const BRICK_COLORS := [Color(0.62, 0.30, 0.22), Color(0.55, 0.28, 0.20), Color(0.72, 0.44, 0.32), Color(0.48, 0.30, 0.28)]
const PANEL_COLORS := [Color(0.56, 0.56, 0.54), Color(0.68, 0.64, 0.56), Color(0.46, 0.48, 0.52), Color(0.62, 0.60, 0.62)]
const GLASS_COLORS := [Color(0.18, 0.28, 0.42), Color(0.16, 0.32, 0.32), Color(0.22, 0.22, 0.26), Color(0.30, 0.34, 0.42)]
const WINDOW_TINTS := [Color(0.35, 0.50, 0.65), Color(0.30, 0.55, 0.55), Color(0.45, 0.45, 0.50), Color(0.60, 0.50, 0.35), Color(0.40, 0.60, 0.75)]
const LIT_COLORS := [Color(1.0, 0.82, 0.50), Color(1.0, 0.92, 0.70), Color(0.85, 0.90, 1.0)]

@export_group("Generation")
@export var seed: int = 0
## Maximum footprint the building may use (meters, x and z).
@export var lot_size: Vector2 = Vector2(24.0, 24.0)
@export var min_height: float = 8.0
@export var max_height: float = 60.0
## Fraction of windows lit, picked between these two.
@export var lit_ratio_range: Vector2 = Vector2(0.15, 0.5)
## Height of the storefront floor on ground-level parts (meters).
@export var storefront_height: float = 4.5
## Force a shape style for tests; -1 = random.
@export var force_shape: int = -1
## Districts narrow the choices: allowed shapes / finishes (empty = all).
@export var shape_options: Array[int] = []
@export var finish_options: Array[int] = []
## Ground floor gets a storefront (shops) when tall enough.
@export var allow_storefront: bool = true

var shape: Shape
var window_style: WindowStyle
var finish: Finish
## Footprint actually used (meters).
var footprint: Vector2 = Vector2.ZERO
## Total height (meters).
var height: float = 0.0
## Each part: {"size": Vector3, "center": Vector3} in local space.
var parts: Array[Dictionary] = []
## Main wall color, available after plan_only() or generate(). Used by the far LOD boxes.
var facade_color: Color = Color.GRAY

static var _prop_materials: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _generated: bool = false


func _ready() -> void:
	add_to_group("building")
	if not _generated:
		generate()


func generate() -> void:
	var style := plan_only()
	for child in get_children():
		child.queue_free()
	collision_layer = 1
	collision_mask = 7
	for part in parts:
		_build_part(part, style)
	_build_roof_props()


## Picks everything and lays out the parts without creating any nodes. Returns the style.
func plan_only() -> Dictionary:
	_generated = true
	parts.clear()
	footprint = Vector2.ZERO
	height = 0.0
	_rng.seed = seed

	if force_shape >= 0:
		shape = force_shape as Shape
	elif not shape_options.is_empty():
		shape = shape_options[_rng.randi() % shape_options.size()] as Shape
	else:
		shape = _rng.randi_range(0, Shape.size() - 2) as Shape # WAREHOUSE only when asked for
	if not finish_options.is_empty():
		finish = finish_options[_rng.randi() % finish_options.size()] as Finish
	else:
		finish = _rng.randi_range(0, Finish.size() - 1) as Finish
	window_style = _pick_window_style()
	_layout_parts()
	var style := _pick_style()
	facade_color = style.facade
	return style


# --- Layout ------------------------------------------------------------------

func _layout_parts() -> void:
	var lot := lot_size
	var h_lo := min_height
	var h_hi := max_height
	match shape:
		Shape.SLAB:
			var size := Vector3(lot.x * _rng.randf_range(0.7, 1.0), _rng.randf_range(h_lo, minf(h_hi, 40.0)), lot.y * _rng.randf_range(0.7, 1.0))
			_add_part(size, Vector2.ZERO, 0.0)
		Shape.TOWER:
			var w := minf(lot.x, lot.y) * _rng.randf_range(0.45, 0.7)
			var size := Vector3(w, _rng.randf_range(maxf(h_lo, 30.0), maxf(h_hi, 32.0)), w * _rng.randf_range(0.8, 1.2))
			_add_part(size, Vector2.ZERO, 0.0)
		Shape.STEPPED:
			var tiers := _rng.randi_range(2, 3)
			var total := _rng.randf_range(maxf(h_lo, 15.0), h_hi)
			var w := lot.x * _rng.randf_range(0.8, 1.0)
			var d := lot.y * _rng.randf_range(0.8, 1.0)
			var bottom := 0.0
			var offset := Vector2.ZERO
			for i in tiers:
				var tier_h := total / tiers * _rng.randf_range(0.7, 1.3) if i < tiers - 1 else total - bottom
				tier_h = maxf(tier_h, 4.0)
				_add_part(Vector3(w, tier_h, d), offset, bottom)
				bottom += tier_h
				var shrink := _rng.randf_range(0.15, 0.3)
				var new_w := w * (1.0 - shrink)
				var new_d := d * (1.0 - shrink)
				offset += Vector2(_rng.randf_range(-(w - new_w), w - new_w), _rng.randf_range(-(d - new_d), d - new_d)) * 0.5
				w = new_w
				d = new_d
		Shape.PODIUM_TOWER:
			var pw := lot.x * _rng.randf_range(0.85, 1.0)
			var pd := lot.y * _rng.randf_range(0.85, 1.0)
			var ph := _rng.randf_range(6.0, 12.0)
			_add_part(Vector3(pw, ph, pd), Vector2.ZERO, 0.0)
			var tw := pw * _rng.randf_range(0.45, 0.65)
			var td := pd * _rng.randf_range(0.45, 0.65)
			var th := _rng.randf_range(maxf(h_lo, 20.0), maxf(h_hi, 22.0)) - ph
			var off := Vector2(_rng.randf_range(-(pw - tw), pw - tw), _rng.randf_range(-(pd - td), pd - td)) * 0.5
			_add_part(Vector3(tw, th, td), off, ph)
		Shape.WAREHOUSE:
			var size := Vector3(lot.x * _rng.randf_range(0.85, 0.95), _rng.randf_range(h_lo, h_hi), lot.y * _rng.randf_range(0.85, 0.95))
			_add_part(size, Vector2.ZERO, 0.0)
		Shape.L_SHAPE:
			var h := _rng.randf_range(h_lo, minf(h_hi, 45.0))
			var arm := _rng.randf_range(0.4, 0.55)
			var sx := 1.0 if _rng.randf() < 0.5 else -1.0
			var sz := 1.0 if _rng.randf() < 0.5 else -1.0
			_add_part(Vector3(lot.x, h, lot.y * arm), Vector2(0.0, sz * lot.y * (1.0 - arm) * 0.5), 0.0)
			_add_part(Vector3(lot.x * arm, h * _rng.randf_range(0.7, 1.0), lot.y), Vector2(sx * lot.x * (1.0 - arm) * 0.5, 0.0), 0.0)


func _add_part(size: Vector3, offset: Vector2, bottom: float) -> void:
	parts.append({"size": size, "center": Vector3(offset.x, bottom + size.y * 0.5, offset.y)})
	footprint.x = maxf(footprint.x, (absf(offset.x) + size.x * 0.5) * 2.0)
	footprint.y = maxf(footprint.y, (absf(offset.y) + size.z * 0.5) * 2.0)
	height = maxf(height, bottom + size.y)


# --- Facade -------------------------------------------------------------------

func _pick_window_style() -> WindowStyle:
	if shape == Shape.WAREHOUSE:
		return WindowStyle.RIBBON if _rng.randf() < 0.7 else WindowStyle.NARROW
	if finish == Finish.GLASS:
		return WindowStyle.CURTAIN if _rng.randf() < 0.8 else WindowStyle.RIBBON
	if finish == Finish.BRICK:
		return WindowStyle.PUNCHED if _rng.randf() < 0.7 else WindowStyle.NARROW
	return _rng.randi_range(0, WindowStyle.size() - 1) as WindowStyle


func _pick_style() -> Dictionary:
	var colors: Array
	match finish:
		Finish.BRICK:
			colors = BRICK_COLORS
		Finish.PANELS:
			colors = PANEL_COLORS
		Finish.GLASS:
			colors = GLASS_COLORS
		_:
			colors = FLAT_COLORS
	var facade: Color = colors[_rng.randi() % colors.size()]
	facade = facade.lightened(_rng.randf_range(-0.08, 0.08))
	var pitch_by_style := [2.6, 2.2, 1.8, 1.6]
	return {
		"facade": facade,
		"accent": facade.darkened(0.55),
		"tint": WINDOW_TINTS[_rng.randi() % WINDOW_TINTS.size()],
		"lit": LIT_COLORS[_rng.randi() % LIT_COLORS.size()],
		"lit_ratio": _rng.randf_range(lit_ratio_range.x, lit_ratio_range.y),
		"pitch": pitch_by_style[window_style],
		"floor": _rng.randf_range(3.1, 4.0),
	}


func _build_part(part: Dictionary, style: Dictionary) -> void:
	var size: Vector3 = part.size
	var center: Vector3 = part.center
	var bottom := center.y - size.y * 0.5
	var on_ground := bottom < 0.01
	var storefront := storefront_height if allow_storefront and shape != Shape.WAREHOUSE and on_ground and size.y > storefront_height + 3.0 else 0.0
	var usable := size.y - storefront
	var rows := maxi(1, roundi(usable / style.floor))
	var floor_h := usable / rows
	var cols_x := maxi(1, roundi(size.x / style.pitch))
	var cols_z := maxi(1, roundi(size.z / style.pitch))

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("facade_color", style.facade)
	mat.set_shader_parameter("accent_color", style.accent)
	mat.set_shader_parameter("facade_finish", finish)
	mat.set_shader_parameter("window_style", window_style)
	mat.set_shader_parameter("window_tint", style.tint)
	mat.set_shader_parameter("lit_color", style.lit)
	mat.set_shader_parameter("lit_ratio", style.lit_ratio)
	mat.set_shader_parameter("window_pitch_x", size.x / cols_x)
	mat.set_shader_parameter("window_pitch_z", size.z / cols_z)
	mat.set_shader_parameter("floor_height", floor_h)
	mat.set_shader_parameter("ground_floor_height", bottom + storefront)
	mat.set_shader_parameter("has_storefront", storefront > 0.0)
	mat.set_shader_parameter("part_size", size)
	mat.set_shader_parameter("seed", float(seed % 1000))
	_apply_wall_texture(mat, finish, shape == Shape.WAREHOUSE)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = center
	add_child(mesh)

	var shape_node := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape_node.shape = box_shape
	shape_node.position = center
	add_child(shape_node)


## Wall texture per finish: brick, concrete, or metal plates for warehouses and glass spandrels.
static func _apply_wall_texture(mat: ShaderMaterial, wall_finish: int, warehouse: bool) -> void:
	var set_key := "concrete"
	var scale := 4.0
	if wall_finish == Finish.BRICK:
		set_key = "brick"
		scale = 3.0
	elif warehouse or wall_finish == Finish.GLASS:
		set_key = "metal"
		scale = 3.0
	var albedo := PropFactory.texture(set_key, "Color")
	if albedo == null:
		return
	mat.set_shader_parameter("wall_albedo", albedo)
	mat.set_shader_parameter("wall_normal", PropFactory.texture(set_key, "NormalGL"))
	mat.set_shader_parameter("wall_roughness", PropFactory.texture(set_key, "Roughness"))
	mat.set_shader_parameter("wall_texture_scale", scale)
	mat.set_shader_parameter("use_wall_texture", true)


# --- Rooftop props ------------------------------------------------------------

func _build_roof_props() -> void:
	for i in parts.size():
		var part: Dictionary = parts[i]
		var size: Vector3 = part.size
		var center: Vector3 = part.center
		var top := center.y + size.y * 0.5
		var is_top := true
		for j in parts.size():
			if j != i and parts[j].center.y + parts[j].size.y * 0.5 > top + 0.01:
				is_top = false
		var inset := 1.2
		var area := Vector2(size.x - inset * 2.0, size.z - inset * 2.0)
		if area.x < 2.0 or area.y < 2.0:
			continue
		var placed: Array[Rect2] = []
		var tries := 0
		var ac_count := _rng.randi_range(1, 4) if is_top else _rng.randi_range(0, 2)
		var wants: Array[String] = []
		for k in ac_count:
			wants.append("ac")
		if is_top and shape == Shape.WAREHOUSE:
			wants.append("vents")
			if _rng.randf() < 0.5:
				wants.append("vents")
		elif is_top:
			if _rng.randf() < 0.6:
				wants.append("bulkhead")
			if _rng.randf() < 0.35 and height > 10.0:
				wants.append("water_tower")
			if _rng.randf() < 0.5 and height > 25.0:
				wants.append("antenna")
			if _rng.randf() < 0.35 and height < 35.0 and area.x > 8.0:
				wants.append("billboard")
		for kind in wants:
			var prop_size := _prop_footprint(kind)
			while tries < 40:
				tries += 1
				var pos := Vector2(
					_rng.randf_range(-area.x * 0.5 + prop_size.x * 0.5, area.x * 0.5 - prop_size.x * 0.5),
					_rng.randf_range(-area.y * 0.5 + prop_size.y * 0.5, area.y * 0.5 - prop_size.y * 0.5))
				var rect := Rect2(pos - prop_size * 0.5, prop_size)
				if _rect_free(rect, placed, i, center):
					placed.append(rect)
					_build_prop(kind, Vector3(center.x + pos.x, top, center.z + pos.y))
					break


func _prop_footprint(kind: String) -> Vector2:
	match kind:
		"ac": return Vector2(1.6, 1.6)
		"bulkhead": return Vector2(3.6, 3.6)
		"water_tower": return Vector2(4.2, 4.2)
		"antenna": return Vector2(1.0, 1.0)
		"billboard": return Vector2(7.0, 1.5)
		"vents": return Vector2(8.0, 1.6)
	return Vector2.ONE


func _rect_free(rect: Rect2, placed: Array[Rect2], part_index: int, part_center: Vector3) -> bool:
	for other in placed:
		if rect.intersects(other.grow(0.4)):
			return false
	# Stay clear of any taller part standing on this roof.
	var top: float = parts[part_index].center.y + parts[part_index].size.y * 0.5
	for j in parts.size():
		if j == part_index or parts[j].center.y + parts[j].size.y * 0.5 <= top:
			continue
		var s: Vector3 = parts[j].size
		var c: Vector3 = parts[j].center
		var footprint_rect := Rect2(Vector2(c.x - s.x * 0.5, c.z - s.z * 0.5) - Vector2(part_center.x, part_center.z), Vector2(s.x, s.z)).grow(0.8)
		if rect.intersects(footprint_rect):
			return false
	return true


func _build_prop(kind: String, at: Vector3) -> void:
	match kind:
		"ac":
			var box := _prop_box(Vector3(1.4, 0.9, 1.4), Color(0.72, 0.72, 0.70), at + Vector3(0.0, 0.45, 0.0))
			_prop_cylinder(0.45, 0.06, Color(0.2, 0.2, 0.22), at + Vector3(0.0, 0.93, 0.0))
			_prop_collision(Vector3(1.4, 0.9, 1.4), at + Vector3(0.0, 0.45, 0.0))
			box.rotation.y = _rng.randf_range(-0.2, 0.2)
		"vents":
			for k in 5:
				_prop_box(Vector3(1.2, 0.8, 1.2), Color(0.6, 0.6, 0.58), at + Vector3(-3.0 + k * 1.5, 0.4, 0.0))
			_prop_collision(Vector3(7.5, 0.8, 1.2), at + Vector3(0.0, 0.4, 0.0))
		"bulkhead":
			_prop_box(Vector3(3.2, 2.6, 3.2), Color(0.55, 0.55, 0.53), at + Vector3(0.0, 1.3, 0.0))
			_prop_box(Vector3(0.9, 2.0, 0.1), Color(0.25, 0.25, 0.28), at + Vector3(0.6, 1.0, 1.62))
			_prop_collision(Vector3(3.2, 2.6, 3.2), at + Vector3(0.0, 1.3, 0.0))
		"water_tower":
			var leg_color := Color(0.3, 0.3, 0.32)
			for dx in [-1.0, 1.0]:
				for dz in [-1.0, 1.0]:
					_prop_cylinder(0.08, 3.0, leg_color, at + Vector3(dx * 1.1, 1.5, dz * 1.1))
			_prop_cylinder(1.6, 3.0, Color(0.55, 0.38, 0.22), at + Vector3(0.0, 4.5, 0.0))
			_prop_cylinder(1.75, 1.2, Color(0.4, 0.28, 0.18), at + Vector3(0.0, 6.6, 0.0), null, 0.0)
			_prop_collision(Vector3(3.2, 7.2, 3.2), at + Vector3(0.0, 3.6, 0.0))
		"antenna":
			var h := _rng.randf_range(6.0, 14.0)
			_prop_cylinder(0.08, h, Color(0.75, 0.75, 0.78), at + Vector3(0.0, h * 0.5, 0.0))
			_prop_box(Vector3(1.6, 0.06, 0.06), Color(0.75, 0.75, 0.78), at + Vector3(0.0, h * 0.7, 0.0))
			_prop_box(Vector3(0.06, 0.06, 1.2), Color(0.75, 0.75, 0.78), at + Vector3(0.0, h * 0.85, 0.0))
			var tip := _prop_box(Vector3(0.25, 0.25, 0.25), Color(1.0, 0.2, 0.15), at + Vector3(0.0, h + 0.1, 0.0))
			tip.material_override = WeaponFX.unshaded(Color(1.0, 0.2, 0.15))
		"billboard":
			var panel_color: Color = FLAT_COLORS[_rng.randi() % FLAT_COLORS.size()]
			var stripe := Color(_rng.randf(), _rng.randf(), _rng.randf()).lightened(0.2)
			var yaw := (PI * 0.5 if _rng.randf() < 0.5 else 0.0) + (PI if _rng.randf() < 0.5 else 0.0)
			var pivot := Node3D.new()
			pivot.position = at
			pivot.rotation.y = yaw
			add_child(pivot)
			_prop_box(Vector3(6.0, 3.0, 0.2), panel_color, Vector3(0.0, 4.0, 0.0), pivot)
			_prop_box(Vector3(5.6, 1.0, 0.24), stripe, Vector3(0.0, 4.3, 0.0), pivot)
			_prop_box(Vector3(2.4, 0.7, 0.24), stripe.darkened(0.4), Vector3(-1.4, 3.2, 0.0), pivot)
			for dx in [-2.3, 2.3]:
				_prop_cylinder(0.1, 2.5, Color(0.3, 0.3, 0.32), Vector3(dx, 1.25, 0.0), pivot)
			var shape_node := CollisionShape3D.new()
			var box_shape := BoxShape3D.new()
			box_shape.size = Vector3(6.0, 5.5, 0.4)
			shape_node.shape = box_shape
			shape_node.position = at + Vector3(0.0, 2.75, 0.0)
			shape_node.rotation.y = yaw
			add_child(shape_node)


static func _prop_material(color: Color) -> StandardMaterial3D:
	var key := color.to_rgba32()
	if _prop_materials.has(key):
		return _prop_materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	_prop_materials[key] = mat
	return mat


func _prop_box(size: Vector3, color: Color, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _prop_material(color)
	mesh.position = pos
	(parent if parent else self).add_child(mesh)
	return mesh


func _prop_cylinder(radius: float, h: float, color: Color, pos: Vector3, parent: Node3D = null, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = radius
	cyl.top_radius = radius if top_radius < 0.0 else top_radius
	cyl.height = h
	cyl.radial_segments = 10
	mesh.mesh = cyl
	mesh.material_override = _prop_material(color)
	mesh.position = pos
	(parent if parent else self).add_child(mesh)
	return mesh


func _prop_collision(size: Vector3, pos: Vector3) -> void:
	var shape_node := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape_node.shape = box_shape
	shape_node.position = pos
	add_child(shape_node)
