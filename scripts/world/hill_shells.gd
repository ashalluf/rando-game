class_name HillShells
extends MultiMeshInstance3D
## The near ground of a FULL hill tile as a stack of thin shells (shaders/hill_shells.gdshader):
## the tile's own terrain mesh drawn again LAYERS times, each copy lifted a little further in the
## vertex shader, each fragment kept only where a grass blade or a clump of brush reaches that
## high. It is a MultiMesh of that one mesh with LAYERS identity instances whose custom data
## carries the layer's height (INSTANCE_CUSTOM.r, 0..1 of the canopy), so it costs one draw,
## no vertex or index memory of its own and nothing to build (CityChunk._build_hill_shells).
##
## The layers are stored bit-reversed, so the first 2, 4 or 8 instances are spread evenly from
## the roots to the tips, and `visible_instance_count` is the tile's LOD: all of them with the
## camera close, fewer further out (LAYER_REACH), none once the whole tile is past the shader's
## `fade_end`. Worked out a few times a second from the camera's distance to the tile's box.

## Layers a tile is drawn as. The grass is 0.55 m and the understory a metre, so 16 put a layer
## every 3.5 and 6.5 cm.
const LAYERS := 16
## [metres from the camera to the nearest point of the tile, layers drawn inside that]: past
## the last, none (the shader has them gone by its fade_end, 85 m).
const LAYER_REACH := [[40.0, 16], [65.0, 8], [90.0, 4]]
## Seconds between distance checks.
const CHECK_INTERVAL := 0.2
## Metres the canopy stands over the ground at most (the shader's brush_height, and a margin),
## for the bounds the renderer culls by.
const CANOPY_TOP := 1.4

## The tile in the parent chunk's space (true world XZ) and its height range.
var rect: Rect2
var low: float = 0.0
var high: float = 0.0
var _wait: float = 0.0


## Height of stored layer `k` as a fraction of the canopy: bit-reversed, so any prefix of a
## power of two layers is spread evenly up it.
static func layer_height(k: int) -> float:
	var bits := 0
	var count := LAYERS
	while count > 1:
		bits += 1
		count >>= 1
	var r := 0
	for b in bits:
		if k & (1 << b):
			r |= 1 << (bits - 1 - b)
	return (float(r) + 0.5) / float(LAYERS)


## A tile's shells: `mesh` is its terrain mesh, `area` its rect, `lo` / `hi` its heights.
static func make(mesh: Mesh, area: Rect2, lo: float, hi: float) -> HillShells:
	var node := HillShells.new()
	node.name = "HillShells"
	node.rect = area
	node.low = lo
	node.high = hi
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	# White instance colours: without them the Compatibility renderer hands the shader a COLOR
	# that is not the mesh's vertex colour, and the keep-out and drainage it carries are lost.
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = LAYERS
	for k in LAYERS:
		mm.set_instance_transform(k, Transform3D.IDENTITY)
		mm.set_instance_color(k, Color.WHITE)
		mm.set_instance_custom_data(k, Color(layer_height(k), 0.0, 0.0, 0.0))
	mm.visible_instance_count = 0
	node.multimesh = mm
	node.material_override = PropFactory.hill_shell_material()
	# The shells are lifted in the vertex shader: the bounds must hold the canopy.
	node.custom_aabb = AABB(Vector3(area.position.x, lo - 0.5, area.position.y), Vector3(area.size.x, hi - lo + CANOPY_TOP + 0.5, area.size.y))
	# The painted stands under them are the shade; a shadow from sixteen layers of grass would
	# be every cascade drawing the tile sixteen times.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.add_to_group("hill_shells")
	# Checks spread over the interval, so the tiles do not all look at once.
	node._wait = fposmod(area.position.x * 0.013 + area.position.y * 0.007, CHECK_INTERVAL)
	return node


## Layers to draw with the camera `d` metres from the nearest point of the tile.
static func layers_at(d: float) -> int:
	for reach: Array in LAYER_REACH:
		if d < float(reach[0]):
			return int(reach[1])
	return 0


func _ready() -> void:
	_update()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = CHECK_INTERVAL
	_update()


func _update() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or multimesh == null:
		return
	# The parent chunk's space is true world XZ (the chunk sits at -world_offset).
	var p := (get_parent() as Node3D).to_local(cam.global_position) if get_parent() is Node3D else cam.global_position
	var dx := maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
	var dz := maxf(maxf(rect.position.y - p.z, p.z - rect.end.y), 0.0)
	var dy := maxf(maxf(low - p.y, p.y - (high + CANOPY_TOP)), 0.0)
	var n := layers_at(Vector3(dx, dy, dz).length())
	if multimesh.visible_instance_count != n:
		multimesh.visible_instance_count = n
