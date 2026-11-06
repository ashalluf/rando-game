class_name RcRailCrossing
extends RefCounted
## The Coral Line's level crossing seen from the waiting car (wave 8 refcam `rail_crossing`,
## tools/refcams/cameras_w8.json; docs/HANDOFF.md "The rail crossing from the waiting car").
## What the view gave away, fixed here (each behind `enabled`, RC5_RAIL_CROSSING=0 the A/B):
##  - the overhead wires were 4-6.5 mm tubes: past ten metres they broke into dashes. They are
##    UtilityPoles' camera-facing ribbons now (never under a pixel, the real width as alpha).
##  - the flashers burned WHITE: emission (1, 0.08, 0.03) x 7 is what AgX takes to a white disc
##    with a salmon rim. Held deep red (green at 0.1 of red, energy 2.6 - the emergency lights'
##    rule) with a camera-facing glow round each lit lens (shaders/rc5_flasher_glow.gdshader).
##  - the crossbuck boards were blank: RAILROAD / CROSSING in black on them.
##  - the cars' windows were flat tan panels (the saloon lit by the golden sky's colour, a 4 %
##    mirror): lrv_glass.gdshader's `look5` - tinted laminated glass, the saloon lit neutral by
##    the windows and its strip lights, seated passengers and standees traced inside.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_RAIL_CROSSING") != "0"

## Flasher lens light: red held to green 0.1 (AgX keeps it red), energy as the emergency lenses'.
const LENS_COLOR := Color(1.0, 0.1, 0.02)
const LENS_ENERGY := 2.6
## The glow round a lit flasher (metres across) and round an arm lamp.
const GLOW_SIZE := 1.1
const ARM_GLOW_SIZE := 0.55
## Ribbon kinds (utility_wire.gdshader): the contact wire is weathered dark copper (5), the
## messenger and droppers galvanised strand (4).
const KIND_CONTACT := 5
const KIND_STEEL := 4

static var _lens_on: StandardMaterial3D
static var _glow_mat: ShaderMaterial
static var _glow_meshes: Dictionary = {}


static func lens_material() -> StandardMaterial3D:
	if _lens_on == null:
		_lens_on = StandardMaterial3D.new()
		_lens_on.albedo_color = Color(0.35, 0.02, 0.01)
		_lens_on.roughness = 0.2
		_lens_on.emission_enabled = true
		_lens_on.emission = LENS_COLOR
		_lens_on.emission_energy_multiplier = LENS_ENERGY
	return _lens_on


## A camera-facing quad (the shader turns it) `size` metres across.
static func glow_mesh(size: float) -> QuadMesh:
	var key := snappedf(size, 0.01)
	if not _glow_meshes.has(key):
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		_glow_meshes[key] = q
	return _glow_meshes[key]


static func glow_material() -> ShaderMaterial:
	if _glow_mat == null:
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = load("res://shaders/rc5_flasher_glow.gdshader")
	return _glow_mat


## A glow node at `pos` in `parent`'s space (hidden until its lamp lights).
static func add_glow(parent: Node3D, pos: Vector3, size: float) -> MeshInstance3D:
	var g := MeshInstance3D.new()
	g.name = "FlasherGlow"
	g.mesh = glow_mesh(size)
	g.material_override = glow_material()
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	g.position = pos
	g.visible = false
	parent.add_child(g)
	return g


## The crossbuck's legend: RAILROAD on the board rising to the right, CROSSING on the other.
static func crossbuck_words(sgn: float) -> String:
	return "RAILROAD" if sgn > 0.0 else "CROSSING"
