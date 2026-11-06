class_name MarinaGolden
extends Node
## The marina at golden hour (wave 6 refcam `marina_golden`, docs/HANDOFF.md "The marina at golden
## hour"). Three things the camera on the east headwalk at 18:00 gave away as a game:
##
##   - the basin mirrored only the sky: a harbour at sunset is mostly the white hulls and the mast
##     forest wobbling in the water. This node picks the MAX_BOATS boats nearest the camera every
##     `interval` seconds (real clock) and hands them to marina_water.gdshader (`mm_a/b/c`, true
##     world: the water mesh's local space), which traces its reflected ray against each hull, its
##     cabin and its mast (shaders/marina_mirror.gdshaderinc) and takes the renderer's own sky
##     reflection away where a boat stands in it (SPECULAR to 0: Godot's f0 then zeroes the
##     ambient and direct specular alike, both renderers);
##   - the rigging drew as dotted lines (1 cm ribbons are a third of a pixel at 20 m): BoatMesh's
##     lines are now their own region with their centre and half width in the mesh, widened in
##     boat_body.gdshaderinc's vertex stage to `wire_px` pixels and faded toward the sky by what
##     they really cover;
##   - the furled jibs read as beige poles: a UV cover strip in the boat's canvas spirals round
##     each (sacrificial strip, region SAIL on the jib's tube).
##
## MARINA_GOLDEN=0 is the A/B: no node, `mm_count` 0, `wire_px` 0, `jib_strip` 0 - the old look.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

const MAX_BOATS := 40
## Boats within this of the camera are candidates; past it nothing is traced.
const REACH := 320.0
## Freeboard over the waterline at reference size (BoatMesh.hull_box's numbers), by Marina.Type.
const FREEBOARD := [1.1, 1.8, 1.7, 0.85]

static var enabled := OS.get_environment("MARINA_GOLDEN") != "0"
static var _inst: MarinaGolden = null

var mr: Marina
var interval := 0.2
var _t := 0.0
## The last picks (true world centres), for the checks.
var picked: Array = []


## Called by MarinaBuild at a FULL marina chunk's finish: one node under the scene root, kept
## for the session (the marina is static data); it sleeps while the camera is far.
static func ensure(from: Node, marina: Marina) -> void:
	if not enabled or marina == null:
		_apply_static(false)
		return
	_apply_static(true)
	if _inst != null and is_instance_valid(_inst):
		_inst.mr = marina
		return
	var tree := from.get_tree()
	if tree == null:
		return
	_inst = MarinaGolden.new()
	_inst.name = "MarinaGolden"
	_inst.mr = marina
	tree.root.add_child.call_deferred(_inst)


static func instance() -> MarinaGolden:
	return _inst if _inst != null and is_instance_valid(_inst) else null


## Off: nothing traced (the boat material's switches are set where it is made, MarinaBuild).
static func _apply_static(on: bool) -> void:
	if not on:
		MarinaBuild.water_material().set_shader_parameter("mm_count", 0)


func _process(delta: float) -> void:
	# The REAL clock: the wheel and photo mode scale the process delta.
	_t -= delta / maxf(Engine.time_scale, 0.001)
	if _t > 0.0:
		return
	_t = interval
	refresh()


## Picks the boats nearest the camera and pushes them to the water. Returns how many.
func refresh() -> int:
	var mat := MarinaBuild.water_material()
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null or mr == null:
		mat.set_shader_parameter("mm_count", 0)
		return 0
	var off := Vector3.ZERO
	var ws := get_node_or_null("/root/WorldState")
	if ws != null:
		off = ws.get("world_offset")
	var c := cam.global_position + off
	return push(mat, mr, Vector2(c.x, c.z))


## The pick and the packing, pure but for the material (the checks call it with any point).
func push(mat: ShaderMaterial, marina: Marina, cam: Vector2) -> int:
	picked = pick(marina, cam)
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	var cc := PackedVector4Array()
	a.resize(MAX_BOATS)
	b.resize(MAX_BOATS)
	cc.resize(MAX_BOATS)
	for i in picked.size():
		var row: Array = pack(picked[i])
		a[i] = row[0]
		b[i] = row[1]
		cc[i] = row[2]
	mat.set_shader_parameter("mm_a", a)
	mat.set_shader_parameter("mm_b", b)
	mat.set_shader_parameter("mm_c", cc)
	mat.set_shader_parameter("mm_count", picked.size())
	return picked.size()


## The MAX_BOATS boats nearest `cam` within REACH (true world xz), nearest first.
static func pick(marina: Marina, cam: Vector2) -> Array:
	var near: Array = []
	if marina == null or marina.site.grow(REACH).has_point(cam) == false:
		return near
	for bt: Dictionary in marina.boats:
		var d := (bt.p as Vector2).distance_squared_to(cam)
		if d < REACH * REACH:
			near.append([d, bt])
	near.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var out: Array = []
	for k in mini(near.size(), MAX_BOATS):
		out.append(near[k][1])
	return out


## One boat as the shader's three vec4s:
##   a: centre x, z (true world), yaw, length;
##   b: beam, hull top over the water, cabin top, mast top (0: no mast);
##   c: hull paint (sRGB), the type.
## The mast stands a tenth of the reference length forward of the centre (BoatMesh's masthead).
static func pack(bt: Dictionary) -> Array:
	var t := int(bt.type)
	var s := float(bt.scale)
	var length := float(bt.len)
	var beam := Marina._beam(t, length)
	var fb := float(FREEBOARD[t]) * s
	var air := BoatMesh.air_draft(t, int(bt.variant)) * s
	var cabin := fb
	var mast := 0.0
	match t:
		Marina.Type.SAIL:
			cabin = fb + 0.5 * s
			mast = air
		Marina.Type.MOTOR:
			cabin = air * 0.82
		Marina.Type.FISHER:
			cabin = minf(air, 3.4 * s)
			mast = air if air > cabin + 0.5 else 0.0
		_:
			cabin = fb + 0.35 * s
	var p: Vector2 = bt.p
	var paint: Color = bt.paint
	return [Vector4(p.x, p.y, float(bt.yaw), length), Vector4(beam, fb, cabin, mast), Vector4(paint.r, paint.g, paint.b, float(t))]
