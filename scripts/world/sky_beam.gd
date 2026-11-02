class_name SkyBeam
extends Node3D
## One searchlight on a cart at a premiere or a club's opening (NightLife), sweeping the sky.
## The yoke turns on the turntable and the drum tilts in it; the beam goes up out of the lens.
## On Forward+ HIGH (volumetric fog on, desktop) a SpotLight3D's volumetric fog energy draws the
## first `fog_reach` metres of the shaft in the real air; past that, and on every other renderer
## and level, an open cone (shaders/nightlife_beam.gdshader) draws it, the helicopter's way. It
## burns only after dark (DayNight.lamp_now), and moves on the physics clock from a hash of its
## seed, so two lights at one premiere cross and part like a pair of real ones.
##
## The node sits on the cart's turntable (the cart is the chunk's batch instance); identity in
## its parent's space, which is the chunk's. `with_head` false: the beam alone (an LOD chunk).

## How far the drawn beam reaches (m), its half-angle (degrees), how bright it is.
@export var reach: float = 1700.0
@export var half_angle: float = 1.0
@export var strength: float = 0.55
## The real light where volumetric fog draws the shaft: range (m), energy, fog energy.
@export var fog_reach: float = 850.0
@export var spot_energy: float = 30.0
@export var fog_energy: float = 9.0
## The sweep: elevation range (degrees over the horizon), how wide it swings (degrees either side
## of its own heading), and how fast (seconds a swing).
@export var elevation: Vector2 = Vector2(52.0, 84.0)
@export var swing: float = 38.0
@export var swing_seconds: Vector2 = Vector2(7.0, 12.0)

var seed_value: int = 0
var with_head: bool = true

var _yaw_node: Node3D
var _pitch_node: Node3D
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _spot: SpotLight3D
var _env: Environment
var _phase: Vector3
var _period: Vector2
var _home: float = 0.0
var _lit: bool = false
var _env_looked: bool = false
static var _beam_shader: Shader
static var _cone: CylinderMesh


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)


func _ready() -> void:
	_phase = Vector3(_h01([seed_value, "a"]), _h01([seed_value, "b"]), _h01([seed_value, "c"])) * TAU
	_period = Vector2(lerpf(swing_seconds.x, swing_seconds.y, _h01([seed_value, "p"])), lerpf(swing_seconds.x * 1.3, swing_seconds.y * 1.6, _h01([seed_value, "q"])))
	_home = (_h01([seed_value, "home"]) - 0.5) * 1.2
	_yaw_node = Node3D.new()
	_yaw_node.name = "Yoke"
	add_child(_yaw_node)
	_pitch_node = Node3D.new()
	_pitch_node.name = "Drum"
	_pitch_node.position = Vector3(0.0, 0.12 + NightLifeKit.TRUNNION_Y + 0.08, 0.0)
	_yaw_node.add_child(_pitch_node)
	if with_head:
		var yoke := MeshInstance3D.new()
		yoke.mesh = NightLifeKit.searchlight_yoke()
		yoke.material_override = NightLifeKit.solo_material()
		yoke.visibility_range_end = NightLife.CART_DRAW
		_yaw_node.add_child(yoke)
		var drum := MeshInstance3D.new()
		drum.mesh = NightLifeKit.searchlight_drum()
		drum.material_override = NightLifeKit.solo_material()
		drum.visibility_range_end = NightLife.CART_DRAW
		_pitch_node.add_child(drum)
	if _beam_shader == null:
		_beam_shader = load("res://shaders/nightlife_beam.gdshader")
		_cone = CylinderMesh.new()
		_cone.top_radius = 0.004
		_cone.bottom_radius = 1.0
		_cone.height = 1.0
		_cone.cap_top = false
		_cone.cap_bottom = false
		_cone.radial_segments = 18
		_cone.rings = 1
	_beam = MeshInstance3D.new()
	_beam.name = "Shaft"
	_beam.mesh = _cone
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = _beam_shader
	_beam_mat.set_shader_parameter("strength", strength)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The cone's own box is the beam's (1.7 km up): never culled while any of it is in view.
	_beam.extra_cull_margin = 16.0
	var wide := reach * tan(deg_to_rad(half_angle))
	_beam.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled_local(Vector3(wide, reach, wide)), Vector3(0.0, 0.0, -reach * 0.5 - NightLifeKit.DRUM_L * 0.5))
	_beam.visible = false
	_pitch_node.add_child(_beam)
	pose(_clock())


## The physics clock (seconds), so a slow render and the wheel's slow motion move it as they move
## everything else.
static func _clock() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


## Points the yoke and the drum where the sweep is at time `t` (seconds).
func pose(t: float) -> void:
	var yaw := _home + deg_to_rad(swing) * sin(TAU * t / _period.x + _phase.x)
	var e := (sin(TAU * t / _period.y + _phase.y) * 0.5 + 0.5)
	var elev := deg_to_rad(lerpf(elevation.x, elevation.y, e))
	_yaw_node.rotation = Vector3(0.0, yaw, 0.0)
	_pitch_node.rotation = Vector3(elev, 0.0, 0.0)


## The beam's direction now (world): the drum's -z.
func direction() -> Vector3:
	return -_pitch_node.global_basis.z.normalized()


func _volumetric() -> bool:
	if not _env_looked:
		_env_looked = true
		var scene := get_tree().current_scene if is_inside_tree() else null
		var we := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment if scene else null
		_env = we.environment if we else null
	return _env != null and _env.volumetric_fog_enabled and RenderingServer.get_rendering_device() != null and not OS.has_feature("web")


func _process(_delta: float) -> void:
	# After dark only: a rain deck at noon brings the street lamps on, not a premiere's searchlight.
	var lamp := RainDay.after_dark_lamp(DayNight.lamp_now)
	var lit := lamp > 0.08
	if lit != _lit:
		_lit = lit
		_beam.visible = lit
		if _spot:
			_spot.visible = lit
	if not lit:
		return
	pose(_clock())
	var volumetric := _volumetric()
	if volumetric and _spot == null:
		_spot = SpotLight3D.new()
		_spot.name = "Beam"
		_spot.spot_range = fog_reach
		_spot.spot_angle = half_angle * 1.4
		_spot.spot_angle_attenuation = 0.5
		_spot.spot_attenuation = 0.2
		_spot.light_color = Color(0.9, 0.94, 1.0)
		_spot.shadow_enabled = false
		_spot.position = Vector3(0.0, 0.0, -NightLifeKit.DRUM_L * 0.5 - 0.1)
		_pitch_node.add_child(_spot)
	if _spot:
		_spot.visible = volumetric
		_spot.light_energy = spot_energy * lamp
		_spot.light_volumetric_fog_energy = fog_energy if volumetric else 0.0
	_beam_mat.set_shader_parameter("near_start", clampf(fog_reach / reach * 0.85, 0.0, 0.9) if volumetric else 0.0)
