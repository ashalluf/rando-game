class_name Building
extends StaticBody3D
## One seeded building. Picks a shape style, dimensions, facade finish, window style,
## colors and rooftop props from small option lists. Same seed, same building.

const SHADER: Shader = preload("res://shaders/building.gdshader")

enum Shape { SLAB, TOWER, STEPPED, PODIUM_TOWER, L_SHAPE, SETBACK, CROWN, WAREHOUSE }
enum WindowStyle { PUNCHED, RIBBON, CURTAIN, NARROW }
enum Finish { FLAT, BRICK, PANELS, GLASS }

## Painted and rendered walls, WEIGHTED BY REPETITION - the neutrals appear several times each
## and the colours once, so a street comes out mostly warm off-white and stone with a painted
## block every so often. That weighting is the whole trick and it is easy to undo by accident:
## an earlier list gave a mauve, a salmon and a sage equal billing with the neutrals and a block
## came out looking like a colour picker rather than a city. But going all-neutral is the other
## failure - a real Los Angeles street has mint, peach, terracotta and butter stucco in it, and
## without them the city reads grey (owner, 2026-09-21: "we need this city to have more color").
## Add colours here one entry at a time; add neutrals three or four at a time.
const FLAT_COLORS := [
	# Neutrals, repeated: warm off-white, cream, stone, grey, sand.
	Color(0.80, 0.76, 0.68), Color(0.80, 0.76, 0.68), Color(0.80, 0.76, 0.68),
	Color(0.74, 0.71, 0.64), Color(0.74, 0.71, 0.64), Color(0.74, 0.71, 0.64),
	Color(0.82, 0.80, 0.75), Color(0.82, 0.80, 0.75), Color(0.82, 0.80, 0.75),
	Color(0.68, 0.67, 0.64), Color(0.68, 0.67, 0.64),
	Color(0.72, 0.66, 0.56), Color(0.72, 0.66, 0.56),
	Color(0.78, 0.74, 0.70), Color(0.78, 0.74, 0.70),
	Color(0.66, 0.63, 0.58), Color(0.66, 0.63, 0.58),
	# Painted stucco, one entry each: pale blue, terracotta, sage, mint, peach, butter, coral,
	# dusty rose, seafoam, ochre.
	Color(0.62, 0.66, 0.70), Color(0.76, 0.62, 0.52), Color(0.61, 0.64, 0.58),
	Color(0.63, 0.78, 0.70), Color(0.92, 0.74, 0.58), Color(0.90, 0.84, 0.58),
	Color(0.88, 0.55, 0.44), Color(0.78, 0.62, 0.62), Color(0.58, 0.76, 0.72),
	Color(0.80, 0.62, 0.32),
]
const BRICK_COLORS := [Color(0.62, 0.30, 0.22), Color(0.55, 0.28, 0.20), Color(0.72, 0.44, 0.32),
	Color(0.48, 0.30, 0.28), Color(0.70, 0.36, 0.26), Color(0.58, 0.34, 0.30),
	Color(0.78, 0.52, 0.38)]
const PANEL_COLORS := [Color(0.56, 0.56, 0.54), Color(0.68, 0.64, 0.56), Color(0.46, 0.48, 0.52),
	Color(0.62, 0.60, 0.62), Color(0.74, 0.72, 0.66), Color(0.52, 0.58, 0.60),
	Color(0.66, 0.58, 0.48)]
## Curtain-wall glass. Downtown was a wall of identical navy; real towers are bronze, blue-green,
## silver and near-black as well as blue, and that variety is most of what makes a skyline read.
const GLASS_COLORS := [Color(0.18, 0.28, 0.42), Color(0.16, 0.32, 0.32), Color(0.22, 0.22, 0.26),
	Color(0.30, 0.34, 0.42), Color(0.34, 0.26, 0.16), Color(0.14, 0.34, 0.30),
	Color(0.40, 0.42, 0.44), Color(0.20, 0.36, 0.44), Color(0.28, 0.30, 0.22),
	Color(0.36, 0.34, 0.30)]
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

@export_group("Facade relief")
## Real facade relief (bays, piers, bands, cornices) draws out to this distance (meters).
@export var relief_draw_distance: float = 380.0
## Chance a residential-looking block gets balconies.
@export var balcony_chance: float = 0.55
## Chance a block gets projecting bays (masonry) or mullion fins (glass) up its window columns.
@export var bay_chance: float = 0.40
## Chance a block's corners are cut back instead of square; very visible from the air.
@export var chamfer_chance: float = 0.30
## Chance a shopfront gets one projecting canopy instead of separate awnings.
@export var canopy_chance: float = 0.40
## Where the canopy slab sits up the storefront, as a fraction of it. Must stay under 0.74:
## that is where the shader stops the shop glass and starts the painted sign band.
@export var canopy_height_frac: float = 0.62
## How far the shopfront canopy reaches out over the pavement (meters).
@export var canopy_reach: float = 1.40
## Floors between string courses (belt bands) on masonry walls; 0 turns them off.
@export var string_course_every: int = 4
## How far a roof parapet stands above the roof deck (meters); 0 turns parapets off.
@export var parapet_height: float = 0.85
## How far a cornice stands out of the wall (meters); the smaller bands scale off it.
@export var band_projection: float = 0.30

@export_group("Facade kit")
## The facade detail kit (tools/facade_kit.py): real moulded cornices, copings, window
## surrounds, air conditioners, awnings, balconies, fire escapes and roof plant, one MultiMesh
## per piece per building. Each kind stops drawing at its own distance (metres); past it the
## old box bands and painted frames carry the look, and they are sized to sit inside the kit's
## mouldings so the two never show at once.
@export var kit_surround_distance: float = 130.0
@export var kit_roofline_distance: float = 230.0
@export var kit_hardware_distance: float = 170.0
@export var kit_ac_distance: float = 110.0
@export var kit_roof_distance: float = 320.0
## Share of punched windows on a residential block with an air conditioner in them.
@export var kit_ac_chance: float = 0.07
## Share of the shops on an awning block that hang one.
@export var kit_awning_chance: float = 0.8
## Share of those awnings in striped canvas.
@export var kit_stripe_chance: float = 0.35

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
## True when this building's corners are cut back (see Building._build_part).
var _chamfered: bool = false

## The facade kit is on everywhere but the web build, whose Compatibility renderer in a browser
## has no triangles to spare; there the box bands and painted frames stand in for all of it.
static var kit_enabled: bool = not OS.has_feature("web")
## Window rows per surround batch: a tall block's windows go into bands of this many floors, so
## the street-level ones draw while the ones forty floors up are past their distance.
const KIT_SURROUND_BAND_ROWS := 8
## Stone for the trim on a brick block (limestone, grey stone, brownstone, painted white).
const KIT_STONES := [Color(0.80, 0.77, 0.70), Color(0.72, 0.70, 0.66), Color(0.66, 0.58, 0.47),
	Color(0.86, 0.84, 0.80), Color(0.78, 0.74, 0.66)]
## Dark paints for a bracketed cornice: pressed-metal cornices were painted, and dark.
const KIT_CORNICE_PAINTS := [Color(0.20, 0.21, 0.19), Color(0.29, 0.21, 0.16), Color(0.16, 0.21, 0.19),
	Color(0.34, 0.31, 0.27)]
## Where the far band sits inside each cornice moulding, in the moulding's own units: centre
## below the roof, thickness, projection. Each box lies wholly inside its profile (checked
## against the points in tools/facade_kit.py), so near the camera it is hidden by the kit and
## past the kit's distance it is what is left of the cornice.
## Most a cornice is raised above the roof line to clear the top windows (metres). Past it the
## plainer, shallower cornice goes on instead: a heavy one standing a metre proud of the roof
## would stand over the parapet's coping.
const KIT_CORNICE_MAX_LIFT := 0.45
## How far each cornice moulding hangs below its own top line, in its units (tools/facade_kit.py).
const KIT_CORNICE_DROP := {"cornice_classic": 0.95, "cornice_bracket": 1.05, "cornice_simple": 0.52}
## How far each window surround stands above the opening it frames (keystone, lintel, hood).
const KIT_SURROUND_HEAD := {"surround_brick_a": 0.27, "surround_brick_b": 0.21, "surround_stucco": 0.43}
const KIT_CORNICE_CORE := {
	"cornice_classic": [-0.155, 0.27, 0.45],
	"cornice_bracket": [-0.185, 0.33, 0.60],
	"cornice_simple": [-0.115, 0.23, 0.25],
}
## This building's kit: its batch while generating (null when the kit is off), the pieces it
## picked, its trim colours and the ironwork paint (INSTANCE_CUSTOM.r for kit_iron).
var _kit: MultiMeshBatch = null
var _kit_cornice: String = ""
var _kit_surround: String = ""
var _kit_trim: Color = Color.WHITE
var _kit_cornice_color: Color = Color.WHITE
var _kit_iron: float = 0.125
## Collision for what stands on the kit (balcony slabs, fire-escape landings), as one trimesh.
var _kit_solids := PackedVector3Array()


func _ready() -> void:
	add_to_group("building")
	if not _generated:
		generate()


func generate() -> void:
	var style := plan_only()
	for child in get_children():
		child.queue_free()
	collision_layer = 1
	collision_mask = 0 # static never detects; a mask here only makes useless pairs (CLAUDE.md)
	_kit = MultiMeshBatch.new() if kit_enabled else null
	if _kit:
		_pick_kit(style)
	for part in parts:
		_build_part(part, style)
	_build_plinth()
	_build_roof_props()
	_finish_kit()


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
	# Cut corners, hashed rather than rolled so tuning the odds cannot move the layout. Never on
	# a warehouse or an L, whose corners are where the two wings meet.
	_chamfered = shape != Shape.WAREHOUSE and shape != Shape.L_SHAPE \
		and float(absi(hash([seed, "chamfer"])) % 1000) * 0.001 < chamfer_chance
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
		# Jittered per building: the four style pitches alone put the same column rhythm on two
		# thirds of downtown, and a street of towers sharing a grid reads as one texture
		# stretched over all of them. Hashed rather than rolled off _rng, like every other
		# late addition in this file - a new _rng call shifts every block downstream of it.
		"pitch": pitch_by_style[window_style] * (0.86 + 0.34 * float(absi(hash([seed, "pitch"])) % 1000) * 0.001),
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
	# Cut corners. Exactly one window bay comes off each end of each wall, so the grid the
	# shader draws still lands on whole cells either side of the cut and no half window is left
	# hanging on a corner. Only on a part wide enough to lose a bay and still read as a wall.
	var cut_x := 0.0
	var cut_z := 0.0
	if _chamfered and cols_x >= 6 and cols_z >= 6 and minf(size.x, size.z) > 10.0:
		cut_x = size.x / float(cols_x)
		cut_z = size.z / float(cols_z)

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
	mat.set_shader_parameter("shop_span", _shop_spans())
	# Base, shaft, crown. The shader lays a stone base course over the bottom floors and shifts
	# the tone of the top ones; _add_facade_details caps both with a real band at the same
	# height, so the two have to be asked for from the same place.
	var base_h := _base_course_height(size, style, storefront, on_ground)
	mat.set_shader_parameter("base_height", base_h)
	if base_h > 0.0:
		mat.set_shader_parameter("base_color", (style.facade as Color).lerp(Color(0.62, 0.60, 0.56), 0.6).darkened(0.08))
	if size.y > 22.0 and finish != Finish.GLASS and shape != Shape.WAREHOUSE:
		mat.set_shader_parameter("crown_start", position.y + bottom + size.y - 1.6 * floor_h)
		mat.set_shader_parameter("crown_shade", 1.09 if absi(hash([seed, "crown"])) % 2 == 0 else 0.92)
	_apply_wall_texture(mat, finish, shape == Shape.WAREHOUSE, style.wall_set, style.weathering)

	var mesh := MeshInstance3D.new()
	if cut_x > 0.0:
		mesh.mesh = _prism_mesh(size, cut_x, cut_z)
	else:
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
	mesh.material_override = mat
	mesh.position = center
	add_child(mesh)

	var shape_node := CollisionShape3D.new()
	if cut_x > 0.0:
		var convex := ConvexPolygonShape3D.new()
		convex.points = _prism_points(size, cut_x, cut_z)
		shape_node.shape = convex
	else:
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape_node.shape = box_shape
	shape_node.position = center
	add_child(shape_node)
	_add_facade_details(size, center, bottom, storefront, floor_h, rows, cols_x, cols_z, style, cut_x, cut_z)


## Shop awnings. Kept to the colours canvas actually comes in: deep reds, greens, navies and
## sand. Bright magenta and saturated yellow read as plastic toys on a street.
## Shop awnings are the one place a street is allowed to be loud, and they are small enough that
## a bright one reads as signage rather than as a painted building.
const AWNING_COLORS := [Color(0.42, 0.10, 0.10), Color(0.09, 0.20, 0.34), Color(0.11, 0.26, 0.17),
	Color(0.52, 0.42, 0.24), Color(0.17, 0.17, 0.19), Color(0.33, 0.13, 0.15),
	Color(0.72, 0.16, 0.14), Color(0.86, 0.56, 0.10), Color(0.10, 0.36, 0.52),
	Color(0.14, 0.44, 0.26), Color(0.62, 0.14, 0.38), Color(0.80, 0.70, 0.16)]
## Above this many window cells on a part, frames are left to the shader (supertalls).
const MAX_FRAME_CELLS := 7000
## Each window style's opening in cell units: [centre u, centre v, half width, half height].
## These are the numbers shaders/building.gdshader draws the glass with (its `win_c` / `win_h`
## and the glass tests), and the frames and the kit's surrounds are placed from them, so they
## have to agree with the shader exactly; tests/smoke_test.gd reads the shader's copies out of
## its source and checks.
const WINDOW_RECTS := {
	WindowStyle.PUNCHED: [0.5, 0.52, 0.27, 0.25],
	WindowStyle.RIBBON: [0.5, 0.55, 0.47, 0.27],
	WindowStyle.CURTAIN: [0.525, 0.53, 0.475, 0.47],
	WindowStyle.NARROW: [0.5, 0.5, 0.16, 0.40],
}
## Window frames are drawn out to this distance (meters); cornices and awnings 1.6x that.
const FRAME_DRAW_DISTANCE := 240.0


## Real geometry on the facade so the box stops reading as a box: a window frame (and sill) at
## every window cell the shader draws, a cornice around the roof edge, a string course over the
## storefront and awnings on the ground floor. Two MultiMeshes per part.
## Shop names for the storefront signs. Original, never a real brand. Kept here rather than
## reaching into Commercial, which already depends on this class.
const SHOP_NAMES := ["PHARMACY", "NAILS & SPA", "DRY CLEAN", "PHONE FIX", "LIQUOR", "PIZZA",
	"SUSHI", "TACOS", "COFFEE STOP", "BANK", "DONUT HOLE", "SUB STOP", "PET SHOP", "BARBER",
	"LAUNDRY", "BOBA", "DENTAL", "TAX PRO", "SMOKE SHOP", "FLOWERS", "RECORDS", "HARDWARE",
	"BOOKS", "BAKERY", "DELI", "OPTICAL", "SHOE REPAIR", "TATTOO", "THRIFT", "CAMERA"]
## Cap height of a shop sign, in metres.
const SIGN_HEIGHT := 0.40
## How far out from the wall the sign sits, and how far a sign still draws.
const SIGN_STANDOFF := 0.14
const SIGN_DRAW_DISTANCE := 75.0


## How many bays make one shop on each face, matching shaders/building.gdshader's `shop_span`.
## Hashed from the seed rather than drawn from _rng: any new call on _rng shifts every block's
## layout downstream of it.
func _shop_spans() -> Vector4:
	var v := Vector4()
	for i in 4:
		v[i] = float(2 + absi(hash([seed, "shop_span", i])) % 3)
	return v


func _add_facade_details(size: Vector3, center: Vector3, bottom: float, storefront: float, floor_h: float, rows: int, cols_x: int, cols_z: int, style: Dictionary, cut_x: float = 0.0, cut_z: float = 0.0) -> void:
	# Face normal, along-the-wall axis (UP x normal, so the instance basis stays right-handed
	# and the flat frame quads face out), wall length, columns, and how much a cut corner takes
	# off each end of this wall.
	var spans := _shop_spans()
	# Every face gets its shop names: one face only left three sides of every block blank, and
	# which side of a lot faces the street is not known here. Each name is a MeshInstance, so
	# they stop drawing at SIGN_DRAW_DISTANCE and the web build skips them entirely.
	var signs_on := not OS.has_feature("web")
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), size.z, cols_z, cut_z],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), size.z, cols_z, cut_z],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), size.x, cols_x, cut_x],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), size.x, cols_x, cut_x],
	]
	# Window rect per style in cell units (center, half size), matching shaders/building.gdshader.
	var rect: Array = WINDOW_RECTS[window_style]
	var cx: float = rect[0]
	var cy: float = rect[1]
	var hx: float = rect[2]
	var hy: float = rect[3]
	var sill := window_style == WindowStyle.PUNCHED or window_style == WindowStyle.NARROW
	var frame_color := Color(0.25, 0.25, 0.27)
	match finish:
		Finish.BRICK:
			# Off-white, not paper white: a pure-white surround blew out against brick and
			# read as polystyrene stuck on the wall.
			frame_color = Color(0.80, 0.78, 0.73)
		Finish.PANELS:
			frame_color = Color(0.2, 0.2, 0.22)
		Finish.GLASS:
			# Anodised aluminium, not a dark line. At 0.14 the frames were darker than the
			# panes they surround, so the grid a curtain-wall tower is made of was drawn and
			# then invisible - and a mullion catching the sun is most of what says "glass".
			frame_color = Color(0.58, 0.59, 0.62)
	var cells := (2 * cols_x + 2 * cols_z) * rows
	var frames: Array[Transform3D] = []
	var boxes: Array = []   # [Transform3D, Color]
	var caps: Array = []    # the same, but standing above the roof deck: its own MultiMesh
	var fins: Array = []    # [Transform3D, Color], the cheeks of a projecting bay
	var top := bottom + size.y
	var accent: Color = (style.accent as Color).lightened(0.25)
	var masonry := finish != Finish.GLASS and shape != Shape.WAREHOUSE
	var awning_color: Color = AWNING_COLORS[_rng.randi() % AWNING_COLORS.size()]
	var has_canopy := storefront > 0.0 and shape != Shape.WAREHOUSE and _rng.randf() < canopy_chance
	var has_awnings := storefront > 0.0 and masonry and not has_canopy and _rng.randf() < 0.7
	var has_cornice := masonry

	# --- Horizontal bands ------------------------------------------------------------------
	# One list, emitted on all four walls and across every cut corner, so a cornice or a string
	# course runs right round the part instead of stopping dead at the corners. A band is
	# [centre height, thickness, how far it stands out of the wall, how far it buries into it,
	# colour]. Between them they give a wall a base, a shaft and a crown instead of one
	# uninterrupted run of windows from the pavement to the sky.
	var bands: Array = []
	# The kit's moulded cornice (drawn near the camera, see _kit_runs below) and how big it is.
	var kit_cornice := _kit != null and has_cornice and _kit_cornice != ""
	var cornice_scale := _kit_cornice_scale(size) if kit_cornice else 1.0
	# A real cornice hangs most of a metre down the wall, and the top floor's window heads come
	# to within half a metre of the roof line (a slot window's to within ten centimetres), so
	# the moulding would sit over them. Where there is no room the plainer cornice goes on, and
	# whatever still does not fit is lifted: the cornice caps the wall and stands up in front
	# of the parapet, as a real one does over a tall top floor.
	var cornice_piece := _kit_cornice
	var cornice_lift := 0.0
	if kit_cornice:
		var clear := top - _kit_top_window(bottom, storefront, floor_h, rows, cy, hy, top)
		if _kit_surround != "":
			clear -= float(KIT_SURROUND_HEAD[_kit_surround])
		# The biggest this moulding may be and still clear them within the lift allowed; a rich
		# cornice may come down a quarter to fit, past that the plain one goes on.
		var fit := (clear + KIT_CORNICE_MAX_LIFT - 0.04) / float(KIT_CORNICE_DROP[cornice_piece])
		if fit < 0.75 and cornice_piece != "cornice_simple":
			cornice_piece = "cornice_simple"
			fit = (clear + KIT_CORNICE_MAX_LIFT - 0.04) / float(KIT_CORNICE_DROP[cornice_piece])
		cornice_scale = clampf(fit, 0.6, cornice_scale)
		var drop := float(KIT_CORNICE_DROP[cornice_piece]) * cornice_scale
		cornice_lift = clampf(drop + 0.04 - clear, 0.0, KIT_CORNICE_MAX_LIFT)
	if has_cornice:
		if kit_cornice:
			# The moulding stands for the two bands below near the camera. Past its distance this
			# one band is what is left of it, sized to sit wholly inside the moulding
			# (KIT_CORNICE_CORE), so near the camera it is hidden rather than doubled.
			var core: Array = KIT_CORNICE_CORE[cornice_piece]
			bands.append([top + cornice_lift + float(core[0]) * cornice_scale, float(core[1]) * cornice_scale,
				float(core[2]) * cornice_scale, 0.10, _kit_cornice_color])
		else:
			# A deep cornice with a thinner coping under it. One band on its own reads as a stripe
			# painted round the top; two with a gap between them read as a moulding.
			bands.append([top - 0.30, 0.44, band_projection, 0.12, accent])
			bands.append([top - 0.66, 0.20, band_projection * 0.55, 0.10, accent.darkened(0.15)])
		if size.y > 22.0:
			# The crown band, at exactly the height the shader changes the wall tone at.
			bands.append([top - 1.6 * floor_h, 0.26, band_projection * 0.5, 0.10, accent])
	if storefront > 0.0:
		bands.append([bottom + storefront + 0.05, 0.25, 0.22, 0.10, accent])
	if masonry and string_course_every > 0 and rows >= string_course_every + 3:
		var f := string_course_every
		while f < rows - 1:
			var sy := bottom + storefront + float(f) * floor_h
			if sy > bottom + 1.5 and sy < top - maxf(2.2, floor_h * 1.8):
				bands.append([sy, 0.18, band_projection * 0.42, 0.10, accent])
			f += string_course_every
	if bottom < 0.01 and masonry:
		# A plinth at the pavement, and the cap on top of the stone base course, which runs
		# from the pavement up past the shopfront (see _base_course_height).
		bands.append([bottom + 0.32, 0.64, 0.15, 0.10, accent.lightened(0.10)])
		var base_h := _base_course_height(size, style, storefront, true)
		if base_h > 0.0:
			bands.append([bottom + base_h, 0.24, band_projection * 0.62, 0.10, accent])
	if has_canopy:
		# One flat canopy over the pavement instead of separate awnings, with a fascia lip on
		# its outer edge so it is not a bare slab. Its height has to agree with the shopfront
		# the shader draws: the painted sign band is fv 0.76..0.93 of the storefront and the
		# shop-name meshes sit at 0.845 of it, so a slab at `storefront - 0.55` (3.95 m of a
		# 4.5 m storefront, 1.4 m deep) cut the tops off the letters and split the painted
		# band in two. Hang it off a fraction of the storefront instead, under the glass -
		# which the shader stops at fv 0.74 - which is where a real shop canopy goes anyway.
		var canopy_y := bottom + storefront * canopy_height_frac
		var reach: float = maxf(canopy_reach, 0.30)
		bands.append([canopy_y, 0.16, reach, 0.10, accent.darkened(0.25)])
		bands.append([canopy_y + 0.13, 0.30, reach + 0.04, -(reach - 0.22), awning_color])
	# Parapet: a low wall standing on the roof edge. Nothing changes a roofline as much - a box
	# cut off flat at the top is the oldest tell there is - and it hides the feet of the roof
	# plant from the street. Its own list, because it is the one detail that is meant to stand
	# above the part it belongs to.
	var cap_bands: Array = []
	# Height of the kit's coping stone, when this part has a parapet for it to sit on.
	var coping_y := -1.0
	if parapet_height > 0.02 and _roof_edge_free(center, size):
		var ph := parapet_height * (0.7 if finish == Finish.GLASS else 1.0)
		cap_bands.append([top + ph * 0.5, ph, 0.05, 0.42, (style.facade as Color).lightened(0.06)])
		if _kit != null:
			coping_y = top + ph
		else:
			cap_bands.append([top + ph + 0.05, 0.12, 0.14, 0.52, accent])

	# Balconies belong on residential-looking blocks, never on a glass curtain-wall tower or a
	# warehouse. They are the cheapest way to break the flat rhythm of a facade.
	var residential := masonry and window_style != WindowStyle.CURTAIN
	var has_balconies := residential and rows >= 3 and _rng.randf() < balcony_chance
	var balcony_every := 1 if _rng.randf() < 0.55 else 2
	var balconies: Array[Transform3D] = []
	# Projecting bays on a masonry block, mullion fins on a glass one: a pair of cheeks standing
	# out of the wall up a whole run of floors, closed by a cap and a soffit. One instance per
	# run, so a forty storey tower costs twelve of them, and the silhouette gets a vertical
	# rhythm no window grid can give it. A block gets these or balconies, never both.
	var has_fins := shape != Shape.WAREHOUSE and rows >= 4 and not has_balconies and _rng.randf() < bay_chance
	var fin_every := 3 if _rng.randf() < 0.6 else 4
	var fin_slim := finish == Finish.GLASS or window_style == WindowStyle.CURTAIN
	var fin_depth := _rng.randf_range(0.18, 0.30) if fin_slim else _rng.randf_range(0.38, 0.58)
	var fin_color: Color = Color(0.60, 0.61, 0.64) if fin_slim else accent.lightened(0.10)
	var fin_bottom := bottom + storefront + floor_h * 0.08
	var fin_top := top - (1.05 if has_cornice else 0.35)
	if fin_top - fin_bottom < floor_h * 2.0:
		has_fins = false
	# Fire escapes belong on older brick blocks, on one face only, the way they actually run.
	var has_escape := finish == Finish.BRICK and shape != Shape.WAREHOUSE and rows >= 3 and _rng.randf() < 0.7
	var escape_face := _rng.randi() % 4
	var escapes: Array[Transform3D] = []
	# The kit's window surround for this building ("" for none), and its mesh.
	var kit_surround := _kit_surround if _kit != null else ""
	var surround_mesh: Mesh = PropFactory.facade_kit(kit_surround) if kit_surround != "" else null
	var face_index := -1
	for face in faces:
		face_index += 1
		var n: Vector3 = face[0]
		var a: Vector3 = face[1]
		var size_u: float = face[2]
		var cols: int = face[3]
		var cut: float = face[4]
		var pitch := size_u / cols
		# Columns the cut corners took away, one at each end of the wall.
		var skip := 1 if cut > 0.0 else 0
		# Face center at height 0: the heights below (v, top, storefront) are absolute in building space.
		var fc := Vector3(center.x, 0.0, center.z) + n * (size.x * 0.5 if absf(n.x) > 0.5 else size.z * 0.5)
		# Every band, shortened to the flat part of this wall. A square corner keeps the old
		# overlap so the two walls' bands meet round it; a cut one is bridged by the corner
		# pieces below.
		var band_len := size_u - 2.0 * cut + (0.7 if cut <= 0.0 else 0.12)
		for b: Array in bands:
			boxes.append([_band_xform(a, n, fc, band_len, b), b[4]])
		for b: Array in cap_bands:
			caps.append([_band_xform(a, n, fc, band_len, b), b[4]])
		if cells <= MAX_FRAME_CELLS:
			var w := 2.0 * hx * pitch
			var h := 2.0 * hy * floor_h
			# The kit's surround (sill, head, jambs) at every window the shader draws, three-sliced
			# to this opening by INSTANCE_CUSTOM: b and a are how far the real opening is past
			# the piece's 1 x 1 m on each side.
			var surround := kit_surround != ""
			var slices := Color(0.0, 0.0, (w - 1.0) * 0.5, (h - 1.0) * 0.5)
			var wall := Basis(a, Vector3.UP, n)
			var ac_ok := _kit != null and window_style == WindowStyle.PUNCHED and residential and w >= 0.8
			for col in range(skip, cols - skip):
				var u := -size_u * 0.5 + (col + cx) * pitch
				for row in rows:
					var v := bottom + storefront + (row + cy) * floor_h
					if v + h * 0.5 > top - 0.3:
						continue
					frames.append(Transform3D(Basis(a * w, Vector3.UP * h, n * 0.1), fc + a * u + Vector3(0.0, v, 0.0) + n * 0.02))
					if surround:
						_kit.add("kit_%s_%d" % [kit_surround, row / KIT_SURROUND_BAND_ROWS], surround_mesh,
							Transform3D(wall, fc + a * u + Vector3(0.0, v, 0.0)), _kit_trim, slices)
					if ac_ok and _kit_hash("ac", (face_index * 1009 + col) * 997 + row) < kit_ac_chance:
						# On the sill, pushed to one side of the opening or the other.
						var off := (_kit_hash("ac side", (face_index * 1009 + col) * 997 + row) - 0.5) * (w - 0.72)
						var unit: Color = [Color(0.86, 0.85, 0.80), Color(0.78, 0.76, 0.70), Color(0.70, 0.71, 0.72)][absi(hash([seed, "ac colour", col, row])) % 3]
						_kit.add("kit_ac_window", PropFactory.facade_kit("ac_window"),
							Transform3D(wall, fc + a * (u + off) + Vector3(0.0, v - h * 0.5, 0.0)), unit, Color(_kit_iron, 0.0, 0.0, 0.0))
		if has_escape and face_index == escape_face and cols - 2 * skip >= 2:
			# `bay` is 1-based: bay 1 sits on column 0, because `eu` below offsets by bay - 0.5.
			# A chamfer takes exactly one column off each end of the wall (cut == pitch), so
			# the escape has to land on a column in [skip, cols - 1 - skip], i.e. on a bay in
			# [skip + 1, cols - skip]. The old bounds were a bay short at both ends: they let
			# bay 1 through, which put the whole escape out over the cut corner, standing
			# 1.35 m proud of a face plane that is no longer there.
			var low_bay := skip + 1
			var high_bay := cols - skip
			# One randi() either way, so the seeded rolls after this are untouched.
			var bay := low_bay + (_rng.randi() % maxi(high_bay - low_bay + 1, 1))
			var eu := -size_u * 0.5 + (float(bay) - 0.5) * pitch
			var ew: float = minf(pitch * 0.9, 2.6)
			var lowest := true
			for row in rows:
				var ev := bottom + storefront + float(row) * floor_h
				if ev < bottom + storefront + 0.5 or ev + floor_h > top - 0.5:
					continue
				if _kit != null:
					# The kit's landings: the lowest one hangs its drop ladder over the pavement,
					# every other one has a stair down to the one below, alternating direction so
					# each stair lands where the next one starts (two meshes, not a mirrored one:
					# a mirrored instance winds inside out).
					var piece := "fe_bottom" if lowest else ("fe_stair_r" if row % 2 == 0 else "fe_stair_l")
					lowest = false
					var xf := Transform3D(Basis(a * (ew / 2.4), Vector3.UP * (floor_h / 3.5), n * (1.35 / 1.3)), fc + a * eu + Vector3(0.0, ev, 0.0))
					_kit.add("kit_" + piece, PropFactory.facade_kit(piece), xf, Color.WHITE, Color(_kit_iron, 0.0, 0.0, 0.0))
					_kit_solid_box(xf, Vector3(0.0, -0.04, 0.65), Vector3(2.4, 0.08, 1.3))
					continue
				# Flip the bay on alternate floors so the stair runs zigzag down the wall.
				var flip := 1.0 if row % 2 == 0 else -1.0
				escapes.append(Transform3D(Basis(a * (ew * flip), Vector3.UP * floor_h, n * 1.35), fc + a * eu + Vector3(0.0, ev, 0.0)))
		if storefront > 0.0 and shape != Shape.WAREHOUSE:
			# A pier between shops and one at each end of the wall, running the whole height of
			# the ground floor. The shopfront then reads as glass set back between piers rather
			# than as a strip wrapped round a box. They stand on the shop runs the shader uses,
			# which it measures from the other end of the wall (see the sign code below), so a
			# pier's place along `a` is mirrored the same way.
			var span: float = spans[face_index]
			var runs := int(float(cols) / span)
			var stops: Array[float] = []
			for k in runs + 2:
				var pu: float = size_u * 0.5 - minf(float(k) * span, float(cols)) * pitch
				if absf(pu) > size_u * 0.5 - cut + 0.01:
					continue
				if stops.is_empty() or absf(stops[stops.size() - 1] - pu) > 0.05:
					stops.append(pu)
			for pu in stops:
				boxes.append([Transform3D(Basis(a * 0.5, Vector3.UP * (storefront - 0.10), n * 0.5),
					fc + a * pu + Vector3(0.0, bottom + (storefront - 0.10) * 0.5, 0.0) + n * 0.14), accent.lightened(0.05)])
		# Shop signs. The sign band is drawn by the shader on the storefront; this puts the
		# actual name on it, lined up with the same shop runs (`shop_span`). One per face:
		# every run would be four names on a wall the player can only read one of.
		if storefront > 0.0 and shape != Shape.WAREHOUSE and signs_on:
			var span: float = spans[face_index]
			var runs := int(float(cols) / span)
			var band_y := 0.845 * (position.y + bottom + storefront) - position.y
			var last_name := -1
			for run in runs:
				var name_i := absi(hash([seed, "sign_name", face_index, run * 7919])) % SHOP_NAMES.size()
				# Two of the same shop side by side reads as a bug even though real streets do
				# it; step along the list rather than re-rolling.
				if name_i == last_name:
					name_i = (name_i + 1) % SHOP_NAMES.size()
				last_name = name_i
				var text: String = SHOP_NAMES[name_i]
				# The shader measures `u` the opposite way round the box from `a` on every
				# face, so the run's centre has to be mirrored back.
				var u_s := (float(run) + 0.5) * span * pitch
				var sign_mesh := MeshInstance3D.new()
				sign_mesh.name = "Sign%d" % run
				sign_mesh.mesh = PropFactory.text_mesh(text, SIGN_HEIGHT)
				sign_mesh.material_override = PropFactory.sign_material()
				# Rough advance width for this font, so a long name is shrunk to fit its run
				# instead of running across the shop next door.
				var wide := float(text.length()) * SIGN_HEIGHT * 0.62
				var room := span * pitch * 0.80
				var fit: float = minf(1.0, room / maxf(wide, 0.01))
				# Scale the basis COLUMNS, not Basis.scaled(), which multiplies the rows and so
				# scales in world axes. On the two faces whose `a` runs along world Z that put
				# the horizontal fit on the vertical axis: the name kept its full width and ran
				# into the shop next door, and was squashed vertically for good measure.
				sign_mesh.transform = Transform3D(Basis(a * fit, Vector3.UP * fit, n),
					fc + a * (size_u * 0.5 - u_s) + Vector3(0.0, band_y, 0.0) + n * SIGN_STANDOFF)
				sign_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				sign_mesh.visibility_range_end = SIGN_DRAW_DISTANCE
				add_child(sign_mesh)
		if has_fins:
			var bw: float = minf(pitch * 0.94, 3.2)
			var run_h := fin_top - fin_bottom
			var col := skip + ((cols - 2 * skip) % fin_every) / 2
			while col < cols - skip:
				var u := -size_u * 0.5 + (float(col) + 0.5) * pitch
				fins.append([Transform3D(Basis(a * bw, Vector3.UP * run_h, n * fin_depth), fc + a * u + Vector3(0.0, fin_bottom, 0.0)), fin_color])
				# Cap and soffit, so the run is closed top and bottom instead of two loose fins
				# standing on nothing.
				for fy: float in [fin_bottom - 0.08, fin_top + 0.08]:
					boxes.append([Transform3D(Basis(a * (bw + 0.16), Vector3.UP * 0.16, n * (fin_depth + 0.16)),
						fc + a * u + Vector3(0.0, fy, 0.0) + n * ((fin_depth + 0.16) * 0.5 - 0.08)), fin_color])
				col += fin_every
		if has_balconies:
			var depth := _rng.randf_range(1.0, 1.45)
			var bw: float = minf(pitch * 0.82, 3.0)
			for col in range(skip, cols - skip):
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
					var bxf := Transform3D(Basis(a * bw, Vector3.UP * _rng.randf_range(1.02, 1.18), n * depth), fc + a * u + Vector3(0.0, v, 0.0))
					if _kit != null:
						# The kit's balcony is modelled at 2.2 x 1.1 x 1.2 m; the same box, in its units.
						var kxf := Transform3D(bxf.basis * Basis.from_scale(Vector3(1.0 / 2.2, 1.0 / 1.1, 1.0 / 1.2)), bxf.origin)
						_kit.add("kit_balcony", PropFactory.facade_kit("balcony"), kxf, _kit_trim, Color(_kit_iron, 0.0, 0.0, 0.0))
						_kit_solid_box(kxf, Vector3(0.0, -0.08, 0.585), Vector3(2.24, 0.16, 1.27))
					else:
						balconies.append(bxf)
		if has_awnings:
			if _kit != null:
				_kit_awnings(face_index, fc, a, n, size_u, cols, pitch, cut, bottom, storefront, spans[face_index])
			for col in range(skip, cols - skip):
				if col % 2 == 1 or _rng.randf() < 0.3:
					continue
				# The kit hangs one awning per shop instead (above); the roll stays so every
				# seeded draw after it lands where it always did.
				if _kit != null:
					continue
				var u := -size_u * 0.5 + (col + 0.5) * pitch
				var tilt := Basis(a, -0.35)
				var basis := tilt * Basis(a * (pitch * 0.9), Vector3.UP * 0.08, n * 1.5)
				boxes.append([Transform3D(basis, fc + a * u + Vector3(0.0, bottom + storefront * 0.78, 0.0) + n * 0.75), awning_color])
	if cut_x > 0.0:
		# Carry every band across the cut corners, or a chamfered block gets four gaps in its
		# cornice and the eye goes straight to them.
		for sx: float in [1.0, -1.0]:
			for sz: float in [1.0, -1.0]:
				var p1 := Vector3(sx * (size.x * 0.5 - cut_x), 0.0, sz * size.z * 0.5)
				var p2 := Vector3(sx * size.x * 0.5, 0.0, sz * (size.z * 0.5 - cut_z))
				var dir := p2 - p1
				var clen := dir.length()
				dir /= clen
				var cn := Vector3(sx * cut_z, 0.0, sz * cut_x).normalized()
				# The four flat faces all satisfy `a x UP == n`, which is what keeps
				# Basis(a, UP, n) right-handed. Walking the footprint runs the chamfer the
				# other way round on the two corners where sx * sz < 0, so `dir` came out
				# reversed there and every band instance on them was mirrored - and a
				# mirrored instance winds backwards, so CULL_BACK threw away the faces that
				# should have been outward. Cornices, copings, string courses, the plinth and
				# the parapet were simply missing on two chamfers of every cut block.
				if dir.cross(Vector3.UP).dot(cn) < 0.0:
					dir = -dir
				var mid := (p1 + p2) * 0.5 + Vector3(center.x, 0.0, center.z)
				for b: Array in bands:
					boxes.append([_band_xform(dir, cn, mid, clen + 0.30, b), b[4]])
				for b: Array in cap_bands:
					caps.append([_band_xform(dir, cn, mid, clen + 0.30, b), b[4]])
	# The kit's roofline: the moulded cornice at the top of the wall, the coping stone on the
	# parapet, both run round the whole footprint (cut corners too) and mitred at every corner.
	if kit_cornice:
		_kit_runs(cornice_piece, center, size, cut_x, cut_z, top + cornice_lift, cornice_scale, _kit_cornice_color)
	if coping_y > 0.0:
		_kit_runs("coping", center, size, cut_x, cut_z, coping_y, 1.0,
			_kit_trim if masonry else (style.facade as Color).lightened(0.12))
	if not frames.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		# Where the kit gives the window a real sill, the frame goes without its box one.
		mm.mesh = PropFactory.window_frame(sill and kit_surround == "")
		mm.instance_count = frames.size()
		# Per-window tint. A wall of identical frames is the loudest "these were stamped out"
		# tell on a close facade; real frames differ in how they have weathered, and a few have
		# been repainted. Hashed rather than drawn from _rng so the seeded layout is untouched.
		for i in frames.size():
			mm.set_instance_transform(i, frames[i])
			var h := float(absi(hash(i * 2654435761 + seed)) % 1000) / 1000.0
			var h2 := float(absi(hash(i * 40503 + seed * 7)) % 1000) / 1000.0
			var c := frame_color.lightened(0.16 * (h * 2.0 - 1.0)) if h > 0.5 else frame_color.darkened(0.30 * (1.0 - h * 2.0))
			# A little warm/cool drift, and the odd frame gone grubby.
			c = Color(c.r * (0.97 + 0.06 * h2), c.g, c.b * (1.03 - 0.09 * h2))
			if h2 < 0.08:
				c = c.darkened(0.30)
			mm.set_instance_color(i, c)
		var node := MultiMeshInstance3D.new()
		node.name = "Frames"
		node.multimesh = mm
		# Past this distance the shader's painted frames carry the look on their own.
		node.visibility_range_end = FRAME_DRAW_DISTANCE
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	if not escapes.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = PropFactory.fire_escape()
		mm.instance_count = escapes.size()
		for i in escapes.size():
			mm.set_instance_transform(i, escapes[i])
		var node := MultiMeshInstance3D.new()
		node.name = "FireEscape"
		node.multimesh = mm
		node.visibility_range_end = FRAME_DRAW_DISTANCE * 2.0
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
	if not fins.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _bay_cheeks()
		mm.instance_count = fins.size()
		for i in fins.size():
			mm.set_instance_transform(i, fins[i][0])
			# A touch of drift per run, so a row of bays is not one colour stamped four times.
			var h := float(absi(hash([seed, "fin", i])) % 1000) * 0.001
			mm.set_instance_color(i, (fins[i][1] as Color).lightened(0.10 * (h - 0.5)))
		var node := MultiMeshInstance3D.new()
		node.name = "Bays"
		node.multimesh = mm
		node.visibility_range_end = relief_draw_distance
		add_child(node)
	if not caps.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = PropFactory.unit_box()
		mm.instance_count = caps.size()
		for i in caps.size():
			mm.set_instance_transform(i, caps[i][0])
			mm.set_instance_color(i, caps[i][1])
		var node := MultiMeshInstance3D.new()
		node.name = "Parapet"
		node.multimesh = mm
		# The roofline is silhouette, so it is worth drawing well past the wall detail: it is
		# eight boxes and it is what the skyline is made of.
		node.visibility_range_end = relief_draw_distance * 2.0
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
		node.visibility_range_end = relief_draw_distance
		add_child(node)


# --- Facade kit ----------------------------------------------------------------------------------
# Everything here is placed from hashes of the seed, never from _rng: the building's rolls are
# shared with the far skyline and with every block downstream of it, and one extra draw moves
# them all (CLAUDE.md, City).

## A repeatable 0..1 for this building, `tag` and `i`.
func _kit_hash(tag: String, i: int = 0) -> float:
	return float(absi(hash([seed, tag, i])) % 100003) / 100003.0


## Which cornice and window surround this building wears, and in what colours.
func _pick_kit(style: Dictionary) -> void:
	_kit_solids = PackedVector3Array()
	_kit_cornice = ""
	_kit_surround = ""
	var masonry := finish != Finish.GLASS and shape != Shape.WAREHOUSE
	if masonry:
		var r := _kit_hash("cornice")
		match finish:
			Finish.BRICK:
				_kit_cornice = "cornice_classic" if r < 0.45 else "cornice_bracket"
			Finish.FLAT:
				_kit_cornice = "cornice_classic" if r < 0.35 else "cornice_simple"
			_:
				_kit_cornice = "cornice_simple"
		# A bungalow does not carry an entablature.
		if height < 11.0:
			_kit_cornice = "cornice_simple"
		# Punched and slot windows get a surround; precast panels stay plain, like the real ones.
		if (window_style == WindowStyle.PUNCHED or window_style == WindowStyle.NARROW) and finish != Finish.PANELS:
			if finish == Finish.BRICK:
				_kit_surround = "surround_brick_a" if _kit_hash("surround") < 0.55 else "surround_brick_b"
			else:
				_kit_surround = "surround_stucco"
	var facade: Color = style.facade
	if finish == Finish.BRICK:
		_kit_trim = KIT_STONES[absi(hash([seed, "kit trim"])) % KIT_STONES.size()]
	elif finish == Finish.GLASS:
		_kit_trim = Color(0.60, 0.61, 0.63)
	else:
		# Painted trim: a shade lighter than the wall, or the cream every landlord buys.
		_kit_trim = facade.lightened(0.18) if _kit_hash("trim") < 0.5 else Color(0.88, 0.86, 0.80)
	_kit_cornice_color = _kit_trim
	if _kit_cornice == "cornice_bracket" and _kit_hash("dark cornice") < 0.5:
		_kit_cornice_color = KIT_CORNICE_PAINTS[absi(hash([seed, "cornice paint"])) % KIT_CORNICE_PAINTS.size()]
	# Ironwork paint: mostly black, then green, grey and a rusty red oxide (facade_kit.gdshaderinc).
	var iron := _kit_hash("iron")
	_kit_iron = (0.5 if iron < 0.5 else (1.5 if iron < 0.7 else (2.5 if iron < 0.9 else 3.5))) / 4.0


## Builds the kit batch into this building, with each kind's draw distance and shadows.
func _finish_kit() -> void:
	if _kit == null:
		return
	for key: String in _kit.keys():
		var d := kit_hardware_distance
		if key.begins_with("kit_surround"):
			# Hundreds a building, a few centimetres proud: their shadow is a line the window
			# recess already draws, and it would cost every cascade.
			d = kit_surround_distance
			_kit.set_no_shadow(key)
		elif key.begins_with("kit_cornice") or key == "kit_coping":
			d = kit_roofline_distance
		elif key == "kit_ac_window":
			d = kit_ac_distance
		elif key.begins_with("kit_vent") or key == "kit_water_tank" or key == "kit_hvac":
			d = kit_roof_distance
		_kit.set_draw_distance(key, d)
	_kit.build(self)
	_kit = null
	if not _kit_solids.is_empty():
		var shape_node := CollisionShape3D.new()
		shape_node.name = "KitSolids"
		var concave := ConcavePolygonShape3D.new()
		concave.backface_collision = true
		concave.set_faces(_kit_solids)
		shape_node.shape = concave
		add_child(shape_node)


## A box of collision (in `xform`'s space: centre and size) for something the player can land
## on, into the building's one kit trimesh.
func _kit_solid_box(xform: Transform3D, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var p: Array[Vector3] = []
	for k in 8:
		p.append(xform * (c + Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z)))
	for f: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_kit_solids.append_array([p[f[0]], p[f[1]], p[f[2]], p[f[0]], p[f[2]], p[f[3]]])


## The signed turn at `cur` walking prev -> cur -> nxt round a part's footprint (positive on a
## convex corner in _footprint_polygon's winding).
static func _kit_turn(prev: Vector2, cur: Vector2, nxt: Vector2) -> float:
	var d_in := (cur - prev).normalized()
	var d_out := (nxt - cur).normalized()
	return atan2(d_in.cross(d_out), d_in.dot(d_out))


## True when a point just outside this part's wall is inside another part that stands at least
## as high: that stretch of roofline is inside the building (the notch of an L of one height),
## and a cornice there would lie on the roof.
func _kit_run_hidden(p: Vector3, part_top: float) -> bool:
	for other in parts:
		var oc: Vector3 = other.center
		var os: Vector3 = other.size
		if oc.y + os.y * 0.5 < part_top - 0.05 or oc.y - os.y * 0.5 > part_top:
			continue
		if absf(p.x - oc.x) < os.x * 0.5 - 0.05 and absf(p.z - oc.z) < os.z * 0.5 - 0.05:
			return true
	return false


## A roofline moulding (`piece`: a cornice or the coping) round a part at height `y`, in 2 m
## runs fitted to each wall, mitred at every corner by the kit shader: INSTANCE_CUSTOM.r / .g
## carry each end's tan(half the corner's turn), converted to the run's own model units.
func _kit_runs(piece: String, center: Vector3, size: Vector3, cut_x: float, cut_z: float, y: float, prof_scale: float, color: Color) -> void:
	var raw := _footprint_polygon(size, cut_x, cut_z)
	var poly := PackedVector2Array()
	for q in raw:
		if poly.is_empty() or poly[poly.size() - 1].distance_to(q) > 0.01:
			poly.append(q)
	if poly.size() > 1 and poly[0].distance_to(poly[poly.size() - 1]) < 0.01:
		poly.remove_at(poly.size() - 1)
	var count_pts := poly.size()
	if count_pts < 3:
		return
	var mesh := PropFactory.facade_kit(piece)
	var key := "kit_" + piece
	var top := center.y + size.y * 0.5
	for i in count_pts:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % count_pts]
		var length := p0.distance_to(p1)
		if length < 0.3:
			continue
		var d := Vector3(p1.x - p0.x, 0.0, p1.y - p0.y) / length
		# Walk the edge backwards so Basis(a, UP, n) is right-handed with n outward (a x UP = n).
		var a := -d
		var n := Vector3.UP.cross(d)
		var tan0 := tan(_kit_turn(poly[(i - 1 + count_pts) % count_pts], p0, p1) * 0.5)
		var tan1 := tan(_kit_turn(p0, p1, poly[(i + 2) % count_pts]) * 0.5)
		var runs := maxi(1, roundi(length / 2.0))
		var sx := length / float(runs) * 0.5
		for k in runs:
			# From p1 (the run's -x end) toward p0.
			var mid := p1.lerp(p0, (float(k) + 0.5) / float(runs))
			var at := Vector3(center.x + mid.x, y, center.z + mid.y)
			if _kit_run_hidden(at + n * 0.35, top):
				continue
			var custom := Color(tan1 * prof_scale / sx if k == 0 else 0.0,
				tan0 * prof_scale / sx if k == runs - 1 else 0.0, 0.0, 0.0)
			_kit.add(key, mesh, Transform3D(Basis(a * sx, Vector3.UP * prof_scale, n * prof_scale), at), color, custom)


## Top of the highest window the frames loop draws on a part (the same rows and skip rule).
func _kit_top_window(bottom: float, storefront: float, floor_h: float, rows: int, cy: float, hy: float, top: float) -> float:
	var h := 2.0 * hy * floor_h
	for row in range(rows - 1, -1, -1):
		var v := bottom + storefront + (float(row) + cy) * floor_h
		if v + h * 0.5 <= top - 0.3:
			return v + h * 0.5
	return bottom + storefront


## How big a building's cornice moulding is: a little heavier on a taller block, as they are.
func _kit_cornice_scale(size: Vector3) -> float:
	return clampf(0.78 + size.y / 90.0, 0.85, 1.45)


## One awning per shop along a storefront, on the same runs of bays the shader gives each shop
## (`shop_span`, measured from the far end of the wall - see the sign code), stopping short of
## the piers between them. Colour, stripes and whether a shop has one at all are hashed per shop.
func _kit_awnings(face_index: int, fc: Vector3, a: Vector3, n: Vector3, size_u: float, cols: int, pitch: float, cut: float, bottom: float, storefront: float, span: float) -> void:
	var mesh := PropFactory.facade_kit("awning")
	var runs := ceili(float(cols) / span)
	for run in runs:
		var hi_u := size_u * 0.5 - float(run) * span * pitch
		var lo_u := size_u * 0.5 - minf(float(run + 1) * span, float(cols)) * pitch
		hi_u = minf(hi_u, size_u * 0.5 - cut) - 0.30
		lo_u = maxf(lo_u, -size_u * 0.5 + cut) + 0.30
		var width := hi_u - lo_u
		if width < 1.2:
			continue
		var shop := face_index * 131 + run
		if _kit_hash("awning", shop) > kit_awning_chance:
			continue
		var colour: Color = AWNING_COLORS[absi(hash([seed, "awning colour", shop])) % AWNING_COLORS.size()]
		var striped := 1.0 if _kit_hash("awning stripes", shop) < kit_stripe_chance else 0.0
		var at := fc + a * ((hi_u + lo_u) * 0.5) + Vector3(0.0, bottom + storefront * 0.745, 0.0)
		_kit.add("kit_awning", mesh, Transform3D(Basis(a, Vector3.UP, n), at), colour,
			Color(_kit_iron, striped, (width - 1.0) * 0.5, 0.0))


## One piece of a horizontal band: `a` is the direction along the wall, `n` the wall's outward
## normal, `at` the middle of the wall at height 0, and `b` is
## [centre height, thickness, projection, how far it buries into the wall, colour].
static func _band_xform(a: Vector3, n: Vector3, at: Vector3, length: float, b: Array) -> Transform3D:
	var out_d: float = b[2]
	var in_d: float = b[3]
	return Transform3D(Basis(a * length, Vector3.UP * float(b[1]), n * (out_d + in_d)),
		at + Vector3(0.0, float(b[0]), 0.0) + n * ((out_d - in_d) * 0.5))


## Height of the stone base course on a ground-floor part: the shopfront (whose own wall
## slivers between the shops are part of the base) plus a floor or two of heavier material
## above it. The shader paints the stone and a band caps it, so the two have to agree - always
## ask here rather than working the height out again. `allow_storefront` is off on the suburban
## houses, and a rusticated ashlar base on a bungalow is not a thing.
func _base_course_height(size: Vector3, style: Dictionary, storefront: float, at_ground: bool) -> float:
	if not at_ground or not allow_storefront or finish == Finish.GLASS or shape == Shape.WAREHOUSE:
		return 0.0
	if size.y < 12.0:
		return 0.0
	return minf(storefront + float(style.floor) * (2.0 if size.y > 30.0 else 1.0), size.y * 0.34)


## True when this part's roof edge is clear the whole way round: either nothing on the building
## stands higher, or what does is set in from every edge (a tower on a podium). A parapet along
## an edge another part sits on would be a ridge running up somebody's wall.
func _roof_edge_free(center: Vector3, size: Vector3) -> bool:
	var top := center.y + size.y * 0.5
	for p in parts:
		var pc: Vector3 = p.center
		var ps: Vector3 = p.size
		if pc.y + ps.y * 0.5 <= top + 0.01:
			continue
		if pc.x - ps.x * 0.5 < center.x - size.x * 0.5 + 0.7:
			return false
		if pc.x + ps.x * 0.5 > center.x + size.x * 0.5 - 0.7:
			return false
		if pc.z - ps.z * 0.5 < center.z - size.z * 0.5 + 0.7:
			return false
		if pc.z + ps.z * 0.5 > center.z + size.z * 0.5 - 0.7:
			return false
	return true


## Footprint of a part with its four corners cut back, going round the box. Shared by the prism
## mesh and its collision shape so the two cannot drift apart.
static func _footprint_polygon(size: Vector3, cut_x: float, cut_z: float) -> PackedVector2Array:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	return PackedVector2Array([
		Vector2(hx - cut_x, hz), Vector2(-(hx - cut_x), hz),
		Vector2(-hx, hz - cut_z), Vector2(-hx, -(hz - cut_z)),
		Vector2(-(hx - cut_x), -hz), Vector2(hx - cut_x, -hz),
		Vector2(hx, -(hz - cut_z)), Vector2(hx, hz - cut_z),
	])


## A box with its four corners cut off, centred on the origin: eight walls, a flat roof and a
## flat underside. Built here instead of a BoxMesh so a chamfered part is still one mesh under
## one building shader (which reads the diagonal walls off their normals). Normals are flat per
## face and the UVs run in metres, so the wall normal maps still have tangents to work in.
static func _prism_mesh(size: Vector3, cut_x: float, cut_z: float) -> Mesh:
	var poly := _footprint_polygon(size, cut_x, cut_z)
	var hy := size.y * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var run := 0.0
	for i in poly.size():
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var e := Vector3(p1.x - p0.x, 0.0, p1.y - p0.y)
		var wide := e.length()
		var nrm := Vector3.UP.cross(e).normalized()
		var a := Vector3(p0.x, -hy, p0.y)
		var b := Vector3(p1.x, -hy, p1.y)
		var up := Vector3.UP * size.y
		_prism_quad(st, nrm, a, b, b + up, a + up,
			Vector2(run, 0.0), Vector2(run + wide, 0.0), Vector2(run + wide, size.y), Vector2(run, size.y))
		run += wide
	# Caps. The roof is most of what the player sees while flying, so it is not optional.
	for i in range(1, poly.size() - 1):
		var q0 := poly[0]
		var q1 := poly[i]
		var q2 := poly[i + 1]
		_prism_vertex(st, Vector3.UP, Vector3(q0.x, hy, q0.y), q0)
		_prism_vertex(st, Vector3.UP, Vector3(q1.x, hy, q1.y), q1)
		_prism_vertex(st, Vector3.UP, Vector3(q2.x, hy, q2.y), q2)
		_prism_vertex(st, Vector3.DOWN, Vector3(q0.x, -hy, q0.y), q0)
		_prism_vertex(st, Vector3.DOWN, Vector3(q2.x, -hy, q2.y), q2)
		_prism_vertex(st, Vector3.DOWN, Vector3(q1.x, -hy, q1.y), q1)
	st.generate_tangents()
	return st.commit()


static func _prism_vertex(st: SurfaceTool, n: Vector3, p: Vector3, uv: Vector2) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)


static func _prism_quad(st: SurfaceTool, n: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_prism_vertex(st, n, a, ua)
	_prism_vertex(st, n, b, ub)
	_prism_vertex(st, n, c, uc)
	_prism_vertex(st, n, a, ua)
	_prism_vertex(st, n, c, uc)
	_prism_vertex(st, n, d, ud)


## The eight corner points of a cut-cornered part, for its convex collision shape.
static func _prism_points(size: Vector3, cut_x: float, cut_z: float) -> PackedVector3Array:
	var poly := _footprint_polygon(size, cut_x, cut_z)
	var hy := size.y * 0.5
	var pts := PackedVector3Array()
	for p in poly:
		pts.append(Vector3(p.x, -hy, p.y))
		pts.append(Vector3(p.x, hy, p.y))
	return pts


static var _bay_mesh: Mesh = null


## The two cheeks of a projecting bay, in a unit cube: 1 wide (X), 1 tall (Y), 1 deep (+Z, out
## of the wall). Cheeks only, because they are vertical and survive being stretched over a run
## of floors; the cap and the soffit are horizontal and go in with the bands instead, where
## stretching would have made them thicker on a taller building.
static func _bay_cheeks() -> Mesh:
	if _bay_mesh != null:
		return _bay_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for sx: float in [-0.5, 0.5]:
		_cheek_box(st, Vector3(sx, 0.5, 0.52), Vector3(0.14, 1.0, 0.96))
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, PropFactory.material(Color.WHITE, 0.72))
	_bay_mesh = mesh
	return mesh


## A plain box into a SurfaceTool that is having its normals generated: positions only, wound
## the same way round as every other box in the game.
static func _cheek_box(st: SurfaceTool, centre: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var p := [
		centre + Vector3(-h.x, -h.y, -h.z), centre + Vector3(h.x, -h.y, -h.z),
		centre + Vector3(h.x, h.y, -h.z), centre + Vector3(-h.x, h.y, -h.z),
		centre + Vector3(-h.x, -h.y, h.z), centre + Vector3(h.x, -h.y, h.z),
		centre + Vector3(h.x, h.y, h.z), centre + Vector3(-h.x, h.y, h.z),
	]
	for f: Array in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		for idx: int in [f[0], f[1], f[2], f[0], f[2], f[3]]:
			st.add_vertex(p[idx])


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


## Mean value of each wall texture's Color map: LINEAR first (what Forward+ and Mobile hand the
## shader) and raw sRGB second (what the Compatibility renderer, i.e. the web build, hands it).
## shaders/building.gdshader divides its sample by this, so a photographed wall stops being a
## second albedo multiplied into facade_color and goes back to being detail. Measured off the
## committed 1K JPGs with, in this order,
##   python3 -c "from PIL import Image; import numpy as np; im=np.asarray(Image.open(PATH).convert('RGB')).astype(float)/255; print(np.where(im<=0.04045, im/12.92, ((im+0.055)/1.055)**2.4).reshape(-1,3).mean(0), im.reshape(-1,3).mean(0))"
## and they only change if the asset changes.
const WALL_TEXTURE_MEAN := {
	"brick_red": [Color(0.277, 0.138, 0.086), Color(0.557, 0.403, 0.315)],
	"brick_mossy": [Color(0.319, 0.176, 0.096), Color(0.588, 0.435, 0.314)],
	"brick_factory": [Color(0.155, 0.100, 0.083), Color(0.417, 0.327, 0.295)],
	"brick": [Color(0.406, 0.253, 0.200), Color(0.652, 0.472, 0.391)],
	"plaster_painted": [Color(0.407, 0.366, 0.351), Color(0.670, 0.638, 0.626)],
	"plaster_beige": [Color(0.340, 0.262, 0.188), Color(0.618, 0.549, 0.471)],
	"plaster_white": [Color(0.272, 0.246, 0.199), Color(0.556, 0.531, 0.480)],
	"concrete_painted": [Color(0.634, 0.499, 0.358), Color(0.807, 0.722, 0.616)],
	"concrete_cracked": [Color(0.514, 0.444, 0.347), Color(0.733, 0.684, 0.606)],
	"concrete_layers": [Color(0.207, 0.196, 0.177), Color(0.491, 0.479, 0.456)],
	"concrete": [Color(0.482, 0.482, 0.482), Color(0.723, 0.723, 0.723)],
	"metal": [Color(0.061, 0.068, 0.070), Color(0.271, 0.286, 0.290)],
	"metal_corrugated": [Color(0.403, 0.451, 0.428), Color(0.666, 0.701, 0.684)],
	"metal_factory": [Color(0.124, 0.185, 0.075), Color(0.382, 0.464, 0.293)],
}


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
		# Keep the plant off the cut corners as well as off the parapet.
		var inset := 2.8 if _chamfered else 1.2
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
		if _kit != null:
			_kit_roof_plant(i, center, top, area, roof_area, placed)


## The kit's roof plant on top of what _build_roof_props placed: packaged rooftop units on the
## big roofs and a scatter of vents. Its own random stream, seeded per part, placed after
## everything else and into the same `placed` list, so none of the old props move.
func _kit_roof_plant(part_index: int, center: Vector3, top: float, area: Vector2, roof_area: float, placed: Array[Rect2]) -> void:
	var krng := RandomNumberGenerator.new()
	krng.seed = hash([seed, "kit roof", part_index])
	var extra: Array[String] = []
	if roof_area > 120.0:
		for k in clampi(roundi(roof_area / 450.0), 1, 3):
			extra.append("hvac")
	for k in krng.randi_range(1, 4 if roof_area > 60.0 else 2):
		extra.append("vent")
	for kind in extra:
		# Units stand square to the building (turned 0 or 180 degrees), so their rect holds.
		var fp := Vector2(2.9, 1.8) if kind == "hvac" else Vector2(0.9, 0.9)
		if fp.x > area.x - 0.2 or fp.y > area.y - 0.2:
			continue
		for attempt in 14:
			var pos := Vector2(krng.randf_range(-area.x * 0.5 + fp.x * 0.5, area.x * 0.5 - fp.x * 0.5),
				krng.randf_range(-area.y * 0.5 + fp.y * 0.5, area.y * 0.5 - fp.y * 0.5))
			var rect := Rect2(pos - fp * 0.5, fp)
			if not _rect_free(rect, placed, part_index, center):
				continue
			placed.append(rect)
			var at := Vector3(center.x + pos.x, top, center.z + pos.y)
			if kind == "hvac":
				var turn := Basis(Vector3.UP, PI if krng.randf() < 0.5 else 0.0)
				var body: Color = [Color(0.80, 0.79, 0.74), Color(0.70, 0.71, 0.70), Color(0.84, 0.83, 0.80)][krng.randi() % 3]
				_kit.add("kit_hvac", PropFactory.facade_kit("hvac"), Transform3D(turn, at), body, Color(_kit_iron, 0.0, 0.0, 0.0))
				_prop_collision(Vector3(2.5, 1.35, 1.4), at + Vector3(0.0, 0.68, 0.0))
			else:
				_kit_vent(at, krng.randf() < 0.5, krng.randf() * TAU)
			break


## One kit roof vent: a mushroom cowl or a turbine, galvanised.
func _kit_vent(at: Vector3, turbine: bool, yaw: float) -> void:
	var piece := "vent_turbine" if turbine else "vent_mushroom"
	_kit.add("kit_" + piece, PropFactory.facade_kit(piece), Transform3D(Basis(Vector3.UP, yaw), at),
		Color(0.64, 0.65, 0.66), Color(_kit_iron, 0.0, 0.0, 0.0))


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
				if _kit != null:
					_kit_vent(at + Vector3(-3.0 + k * 1.5, 0.0, 0.0), _kit_hash("vent", roundi(at.x * 7.0) + k) < 0.6, _kit_hash("vent yaw", k) * TAU)
				else:
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
			if _kit != null:
				# The kit's timber tank on its braced steel stand, turned by a hash of where it
				# stands (no _rng: the roll count must not change).
				var yaw := _kit_hash("tank", roundi(at.x * 13.0 + at.z * 7.0)) * TAU
				_kit.add("kit_water_tank", PropFactory.facade_kit("water_tank"), Transform3D(Basis(Vector3.UP, yaw), at),
					Color.WHITE, Color(_kit_iron, 0.0, 0.0, 0.0))
			else:
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
