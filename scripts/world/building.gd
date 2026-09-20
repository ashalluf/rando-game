class_name Building
extends StaticBody3D
## One seeded building. Picks a shape style, dimensions, facade finish, window style,
## colors and rooftop props from small option lists. Same seed, same building.

const SHADER: Shader = preload("res://shaders/building.gdshader")

enum Shape { SLAB, TOWER, STEPPED, PODIUM_TOWER, L_SHAPE, SETBACK, CROWN, WAREHOUSE }
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
## Grime range (0 clean, 1 filthy); districts set it.
@export var weathering_range: Vector2 = Vector2(0.2, 0.9)
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
## Concrete plinth under the building (meters), covering the slope of the sidewalk beneath it.
var plinth_depth: float = 0.0

static var _prop_materials: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _generated: bool = false
## Roof covering for this building (see shaders/building.gdshader `roof_style`).
var roof_style: int = 0


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
	_build_plinth()
	_build_roof_props()


func _build_plinth() -> void:
	if plinth_depth <= 0.05 or footprint.x <= 0.0:
		return
	var size := Vector3(footprint.x + 0.3, plinth_depth, footprint.y + 0.3)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = PropFactory.pbr("concrete", 3.0, Color(0.72, 0.72, 0.7))
	mesh.position = Vector3(0.0, 0.02 - plinth_depth * 0.5, 0.0)
	add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position = mesh.position
	add_child(shape)


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
	# Roof covering, picked per building: mostly white membrane on modern blocks, gravel on
	# older ones, bitumen on the rest.
	var roof_roll := _rng.randf()
	roof_style = 1 if roof_roll < 0.42 else (0 if roof_roll < 0.76 else 2)
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
		Shape.SETBACK:
			# Classic setback skyscraper: 4-6 centered tiers, each a little narrower.
			var tiers := _rng.randi_range(4, 6)
			var total := _rng.randf_range(maxf(h_lo, 40.0), maxf(h_hi, 42.0))
			var w := lot.x * _rng.randf_range(0.85, 1.0)
			var d := lot.y * _rng.randf_range(0.85, 1.0)
			var bottom := 0.0
			for i in tiers:
				var frac := 0.34 if i == 0 else (0.66 / (tiers - 1))
				var tier_h := maxf(total * frac, 4.0)
				_add_part(Vector3(w, tier_h, d), Vector2.ZERO, bottom)
				bottom += tier_h
				var shrink := _rng.randf_range(0.1, 0.2)
				w *= 1.0 - shrink
				d *= 1.0 - shrink
		Shape.CROWN:
			# Slim glass tower with a crown box and a spire (added as a roof prop).
			var w := minf(lot.x, lot.y) * _rng.randf_range(0.55, 0.75)
			var h := _rng.randf_range(maxf(h_lo, 50.0), maxf(h_hi, 52.0))
			_add_part(Vector3(w, h, w * _rng.randf_range(0.85, 1.15)), Vector2.ZERO, 0.0)
			var cw := w * _rng.randf_range(0.5, 0.7)
			_add_part(Vector3(cw, _rng.randf_range(5.0, 9.0), cw), Vector2.ZERO, h)
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
		"wall_set": _pick_wall_set(),
		"weathering": _rng.randf_range(weathering_range.x, weathering_range.y),
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
	# The shader counts floors from world Y, so the base has to include where this building sits.
	mat.set_shader_parameter("ground_floor_height", position.y + bottom + storefront)
	mat.set_shader_parameter("base_y", position.y + bottom)
	mat.set_shader_parameter("has_storefront", storefront > 0.0)
	mat.set_shader_parameter("part_size", size)
	mat.set_shader_parameter("seed", float(seed % 1000))
	mat.set_shader_parameter("roof_style", roof_style)
	_apply_wall_texture(mat, finish, shape == Shape.WAREHOUSE, style.wall_set, style.weathering)

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
	_add_facade_details(size, center, bottom, storefront, floor_h, rows, cols_x, cols_z, style)


## Shop awnings. Kept to the colours canvas actually comes in: deep reds, greens, navies and
## sand. Bright magenta and saturated yellow read as plastic toys on a street.
const AWNING_COLORS := [Color(0.42, 0.10, 0.10), Color(0.09, 0.20, 0.34), Color(0.11, 0.26, 0.17), Color(0.52, 0.42, 0.24), Color(0.17, 0.17, 0.19), Color(0.33, 0.13, 0.15)]
## Above this many window cells on a part, frames are left to the shader (supertalls).
const MAX_FRAME_CELLS := 7000
## Window frames are drawn out to this distance (meters); cornices and awnings 1.6x that.
const FRAME_DRAW_DISTANCE := 240.0


## Real geometry on the facade so the box stops reading as a box: a window frame (and sill) at
## every window cell the shader draws, a cornice around the roof edge, a string course over the
## storefront and awnings on the ground floor. Two MultiMeshes per part.
func _add_facade_details(size: Vector3, center: Vector3, bottom: float, storefront: float, floor_h: float, rows: int, cols_x: int, cols_z: int, style: Dictionary) -> void:
	# Face normal, along-the-wall axis (UP x normal, so the instance basis stays right-handed
	# and the flat frame quads face out), wall length, columns.
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), size.z, cols_z],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), size.z, cols_z],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), size.x, cols_x],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), size.x, cols_x],
	]
	# Window rect per style in cell units (center, half size), matching shaders/building.gdshader.
	var cx := 0.5
	var cy := 0.52
	var hx := 0.27
	var hy := 0.25
	var sill := true
	match window_style:
		WindowStyle.RIBBON:
			cy = 0.55
			hx = 0.47
			hy = 0.27
			sill = false
		WindowStyle.CURTAIN:
			cx = 0.525
			cy = 0.53
			hx = 0.475
			hy = 0.47
			sill = false
		WindowStyle.NARROW:
			cy = 0.5
			hx = 0.16
			hy = 0.40
	var frame_color := Color(0.25, 0.25, 0.27)
	match finish:
		Finish.BRICK:
			frame_color = Color(0.92, 0.9, 0.86)
		Finish.PANELS:
			frame_color = Color(0.2, 0.2, 0.22)
		Finish.GLASS:
			frame_color = Color(0.14, 0.15, 0.17)
	var cells := (2 * cols_x + 2 * cols_z) * rows
	var frames: Array[Transform3D] = []
	var boxes: Array = []   # [Transform3D, Color]
	var top := bottom + size.y
	var accent: Color = (style.accent as Color).lightened(0.25)
	var awning_color: Color = AWNING_COLORS[_rng.randi() % AWNING_COLORS.size()]
	var has_awnings := storefront > 0.0 and shape != Shape.WAREHOUSE and finish != Finish.GLASS and _rng.randf() < 0.7
	var has_cornice := finish != Finish.GLASS and shape != Shape.WAREHOUSE
	# Balconies belong on residential-looking blocks, never on a glass curtain-wall tower or a
	# warehouse. They are the cheapest way to break the flat rhythm of a facade.
	var residential := finish != Finish.GLASS and shape != Shape.WAREHOUSE and window_style != WindowStyle.CURTAIN
	var has_balconies := residential and rows >= 3 and _rng.randf() < 0.45
	var balcony_every := 1 if _rng.randf() < 0.55 else 2
	var balconies: Array[Transform3D] = []
	for face in faces:
		var n: Vector3 = face[0]
		var a: Vector3 = face[1]
		var size_u: float = face[2]
		var cols: int = face[3]
		var pitch := size_u / cols
		# Face center at height 0: the heights below (v, top, storefront) are absolute in building space.
		var fc := Vector3(center.x, 0.0, center.z) + n * (size.x * 0.5 if absf(n.x) > 0.5 else size.z * 0.5)
		if cells <= MAX_FRAME_CELLS:
			var w := 2.0 * hx * pitch
			var h := 2.0 * hy * floor_h
			for col in cols:
				var u := -size_u * 0.5 + (col + cx) * pitch
				for row in rows:
					var v := bottom + storefront + (row + cy) * floor_h
					if v + h * 0.5 > top - 0.3:
						continue
					frames.append(Transform3D(Basis(a * w, Vector3.UP * h, n * 0.1), fc + a * u + Vector3(0.0, v, 0.0) + n * 0.02))
		if has_cornice:
			boxes.append([Transform3D(Basis(a * (size_u + 0.7), Vector3.UP * 0.45, n * 0.35), fc + Vector3(0.0, top - 0.22, 0.0) + n * 0.17), accent])
		if storefront > 0.0:
			boxes.append([Transform3D(Basis(a * (size_u + 0.4), Vector3.UP * 0.25, n * 0.22), fc + Vector3(0.0, bottom + storefront + 0.05, 0.0) + n * 0.11), accent])
		if has_balconies:
			var depth := _rng.randf_range(1.0, 1.45)
			var bw: float = minf(pitch * 0.82, 3.0)
			for col in cols:
				# Skip some bays so the facade is not a perfect grid of balconies.
				if _rng.randf() < 0.22:
					continue
				var u := -size_u * 0.5 + (col + 0.5) * pitch
				for row in rows:
					if row % balcony_every != 0:
						continue
					var v := bottom + storefront + (row + 0.12) * floor_h
					if v + 1.2 > top - 0.4 or v < bottom + 2.0:
						continue
					# Railing height is about 1.1 m in the real world. Scaling it by a fraction of
					# the floor height made 2 m railings that stacked into a continuous lattice.
					balconies.append(Transform3D(Basis(a * bw, Vector3.UP * _rng.randf_range(1.02, 1.18), n * depth), fc + a * u + Vector3(0.0, v, 0.0)))
		if has_awnings:
			for col in cols:
				if col % 2 == 1 or _rng.randf() < 0.3:
					continue
				var u := -size_u * 0.5 + (col + 0.5) * pitch
				var tilt := Basis(a, -0.35)
				var basis := tilt * Basis(a * (pitch * 0.9), Vector3.UP * 0.08, n * 1.5)
				boxes.append([Transform3D(basis, fc + a * u + Vector3(0.0, bottom + storefront * 0.78, 0.0) + n * 0.75), awning_color])
	if not frames.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = PropFactory.window_frame(sill)
		mm.instance_count = frames.size()
		for i in frames.size():
			mm.set_instance_transform(i, frames[i])
			mm.set_instance_color(i, frame_color)
		var node := MultiMeshInstance3D.new()
		node.name = "Frames"
		node.multimesh = mm
		# Past this distance the shader's painted frames carry the look on their own.
		node.visibility_range_end = FRAME_DRAW_DISTANCE
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	if not balconies.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = PropFactory.balcony()
		mm.instance_count = balconies.size()
		for i in balconies.size():
			mm.set_instance_transform(i, balconies[i])
		var node := MultiMeshInstance3D.new()
		node.name = "Balconies"
		node.multimesh = mm
		node.visibility_range_end = FRAME_DRAW_DISTANCE * 2.0
		add_child(node)
	if not boxes.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = PropFactory.unit_box()
		mm.instance_count = boxes.size()
		for i in boxes.size():
			mm.set_instance_transform(i, boxes[i][0])
			mm.set_instance_color(i, boxes[i][1])
		var node := MultiMeshInstance3D.new()
		node.name = "Details"
		node.multimesh = mm
		node.visibility_range_end = FRAME_DRAW_DISTANCE * 1.6
		add_child(node)


## Texture sets each finish can wear (keys in PropFactory.TEXTURE_SETS) and their meters per tile.
const WALL_SETS := {
	Finish.BRICK: [["brick_red", 2.6], ["brick_mossy", 2.4], ["brick_factory", 3.0], ["brick", 3.0]],
	Finish.FLAT: [["plaster_painted", 4.0], ["plaster_beige", 4.0], ["plaster_white", 4.0], ["concrete_painted", 4.0]],
	Finish.PANELS: [["concrete", 4.0], ["concrete_cracked", 4.0], ["concrete_layers", 3.5]],
	Finish.GLASS: [["metal", 3.0], ["concrete_layers", 3.5]],
}
const WAREHOUSE_SETS := [["metal_corrugated", 2.5], ["metal_factory", 3.0], ["metal", 3.0]]


## Picks one of the finish's wall texture sets with the building's rng: [set_key, scale].
func _pick_wall_set() -> Array:
	var options: Array = WAREHOUSE_SETS if shape == Shape.WAREHOUSE else WALL_SETS.get(finish, WALL_SETS[Finish.FLAT])
	return options[_rng.randi() % options.size()]


## Wall texture for this part: `wall_set` is [set_key, scale] from _pick_wall_set().
static func _apply_wall_texture(mat: ShaderMaterial, wall_finish: int, warehouse: bool, wall_set: Array = [], weathering: float = 0.5) -> void:
	var set_key := "concrete"
	var scale := 4.0
	if wall_set.size() == 2:
		set_key = wall_set[0]
		scale = wall_set[1]
	elif wall_finish == Finish.BRICK:
		set_key = "brick"
		scale = 3.0
	elif warehouse or wall_finish == Finish.GLASS:
		set_key = "metal"
		scale = 3.0
	mat.set_shader_parameter("weathering", weathering)
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
		# Real roofs are crowded. Scale the plant with the roof's area rather than using a flat
		# count, so a big podium does not get the same two units as a narrow tower.
		var roof_area := area.x * area.y
		var ac_count := clampi(roundi(roof_area / 90.0) + _rng.randi_range(1, 3), 1, 9)
		if not is_top:
			ac_count = clampi(ac_count / 2, 0, 4)
		var wants: Array[String] = []
		for k in ac_count:
			wants.append("ac")
		if roof_area > 55.0 and _rng.randf() < 0.55:
			wants.append("ducts")
		if is_top and roof_area > 70.0 and _rng.randf() < 0.45:
			wants.append("solar")
		if is_top and roof_area > 40.0 and _rng.randf() < 0.4:
			wants.append("skylight")
		if is_top and roof_area > 80.0 and _rng.randf() < 0.3:
			wants.append("cooling_tower")
		if is_top and shape == Shape.WAREHOUSE:
			wants.append("vents")
			if _rng.randf() < 0.5:
				wants.append("vents")
		elif is_top:
			if _rng.randf() < 0.6:
				wants.append("bulkhead")
			if _rng.randf() < 0.35 and height > 10.0:
				wants.append("water_tower")
			if shape == Shape.CROWN or (height > 140.0 and _rng.randf() < 0.7):
				wants.append("spire")
			elif _rng.randf() < 0.5 and height > 25.0:
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
		"spire": return Vector2(2.0, 2.0)
		"billboard": return Vector2(7.0, 1.5)
		"vents": return Vector2(8.0, 1.6)
		"ducts": return Vector2(7.0, 1.1)
		"solar": return Vector2(5.4, 3.6)
		"skylight": return Vector2(2.6, 2.6)
		"cooling_tower": return Vector2(3.0, 3.0)
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
			# Real unit (Poly Haven), scaled up to rooftop size, on a concrete pad.
			var unit := MeshInstance3D.new()
			unit.mesh = PropFactory.model_ac(_rng.randf() < 0.35)
			unit.position = at + Vector3(0.0, 0.1, 0.0)
			unit.scale = Vector3.ONE * 1.7
			unit.rotation.y = _rng.randf_range(0.0, TAU)
			add_child(unit)
			_prop_box(Vector3(1.6, 0.1, 1.6), Color(0.6, 0.6, 0.58), at + Vector3(0.0, 0.05, 0.0))
			_prop_collision(Vector3(1.4, 1.6, 1.4), at + Vector3(0.0, 0.8, 0.0))
		"vents":
			for k in 5:
				_prop_box(Vector3(1.2, 0.8, 1.2), Color(0.6, 0.6, 0.58), at + Vector3(-3.0 + k * 1.5, 0.4, 0.0))
		"ducts":
			# A run of insulated duct on short legs, with an elbow turning up at one end.
			var yaw := _rng.randf_range(0.0, TAU)
			var dir := Vector3(cos(yaw), 0.0, sin(yaw))
			var across := Vector3(-dir.z, 0.0, dir.x)
			var metal := Color(0.63, 0.64, 0.66)
			for k in 6:
				var along := dir * (-3.0 + float(k) * 1.2)
				var duct := _prop_box(Vector3(1.2, 0.55, 0.62), metal, at + along + Vector3(0.0, 0.85, 0.0))
				duct.rotation.y = yaw
				# Legs.
				for side: float in [-0.22, 0.22]:
					_prop_box(Vector3(0.08, 0.6, 0.08), Color(0.35, 0.35, 0.37), at + along + across * side + Vector3(0.0, 0.3, 0.0))
			var elbow := _prop_box(Vector3(0.7, 1.4, 0.62), metal, at + dir * 3.5 + Vector3(0.0, 1.2, 0.0))
			elbow.rotation.y = yaw
		"solar":
			# Tilted panel rows on low frames, facing south.
			var tilt := _rng.randf_range(0.30, 0.48)
			for rowi in 2:
				for coli in 3:
					var p := at + Vector3(-1.8 + float(coli) * 1.8, 0.0, -1.1 + float(rowi) * 2.2)
					var panel := _prop_box(Vector3(1.65, 0.06, 1.0), Color(0.07, 0.09, 0.16), p + Vector3(0.0, 0.55, 0.0))
					panel.rotation.x = -tilt
					_prop_box(Vector3(0.06, 0.4, 0.06), Color(0.5, 0.5, 0.52), p + Vector3(-0.7, 0.2, 0.3))
					_prop_box(Vector3(0.06, 0.6, 0.06), Color(0.5, 0.5, 0.52), p + Vector3(0.7, 0.3, -0.3))
		"skylight":
			# A raised kerb with a pale glazed cap.
			_prop_box(Vector3(2.4, 0.35, 2.4), Color(0.55, 0.55, 0.57), at + Vector3(0.0, 0.18, 0.0))
			var glass := _prop_box(Vector3(2.1, 0.12, 2.1), Color(0.62, 0.72, 0.78), at + Vector3(0.0, 0.42, 0.0))
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.62, 0.72, 0.78)
			gm.roughness = 0.12
			gm.metallic = 0.1
			glass.material_override = gm
		"cooling_tower":
			_prop_cylinder(1.25, 1.9, Color(0.58, 0.59, 0.60), at + Vector3(0.0, 0.95, 0.0))
			_prop_cylinder(1.3, 0.18, Color(0.40, 0.41, 0.43), at + Vector3(0.0, 1.95, 0.0))
			_prop_cylinder(0.9, 0.08, Color(0.25, 0.25, 0.27), at + Vector3(0.0, 2.08, 0.0))
			_prop_collision(Vector3(2.5, 2.0, 2.5), at + Vector3(0.0, 1.0, 0.0))
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
		"spire":
			# Skyline spire with a lit tip: base cone, long mast, blinking-red beacon.
			var h := _rng.randf_range(0.18, 0.3) * maxf(height, 60.0)
			_prop_cylinder(1.4, 3.0, Color(0.7, 0.7, 0.74), at + Vector3(0.0, 1.5, 0.0), null, 0.5)
			_prop_cylinder(0.35, h, Color(0.8, 0.8, 0.84), at + Vector3(0.0, 3.0 + h * 0.5, 0.0), null, 0.08)
			var tip := _prop_box(Vector3(0.6, 0.6, 0.6), Color(1.0, 0.2, 0.15), at + Vector3(0.0, 3.0 + h + 0.3, 0.0))
			tip.material_override = WeaponFX.unshaded(Color(1.0, 0.25, 0.2))
			_prop_collision(Vector3(2.8, 3.0, 2.8), at + Vector3(0.0, 1.5, 0.0))
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
