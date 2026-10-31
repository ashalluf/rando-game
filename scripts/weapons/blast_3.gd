class_name Blast3
extends RefCounted
## The explosion at arm's length, third pass (fleet wave 4, "explosions-3"). WeaponFX.explosion()
## and BlastFX lay the blast as before; with this on they hand four parts over to it:
##  - THE FIREBALL is a volume (`BlastVolume`, shaders/blast_volume.gdshader): the view ray marched
##    through a box round the blast, a growing, rising, rolling density field carved by a tiling 3D
##    noise, every sample both black-body light and lit soot. It replaces WeaponFX's forty fireball
##    cards and BlastFX's rolling cap of cards (`takes_fireball()`), which from any angle were a
##    pile of flat discs. The web keeps the cards (the march costs what the web cannot pay).
##  - DEBRIS, CHIPS AND SPARKS that land (`BlastBits`): the grit and the sparks were particles that
##    fell through the road; now every one is a point on a ballistic arc with one ray a tick, that
##    bounces, skids and comes to rest - chips lie on the road for `chip_rest` s, sparks skitter and
##    die on the ground as embers. BlastDebris's burning lumps bounce, slide and settle flat too.
##  - THE SMOKE AT NIGHT AND AGAINST THE SUN: blast_smoke.gdshader takes the fires' positions
##    (`fire_lights`, up to four, pushed every frame) so smoke is lit from below by the fire that
##    is still burning and dark once it is out, a faint city glow under it after dark, and a
##    forward-scattering rim looking toward the sun.
##  - THE HEAT HAZE over the fire (`BlastHaze`): a column of rising, bent air for as long as the
##    fire burns, which only bends what is BEHIND it (depth-tested in the shader). Desktop only.
## The crater's scorch (BlastAftermath.crater_textures) gets fingered soot rays, a scoured dust
## halo and a pit whose embers glow for its first seconds (`ember_seconds`).
## EXPLOSIONS_3=0 in the environment is the A/B (the second pass as it was).

static var enabled: bool = OS.get_environment("EXPLOSIONS_3") != "0"

## The volume fireball: seconds it burns before it has faded (a fuel fireball longer), how many
## at once (past that a blast gets the cards), and the march's steps.
static var volume_life: float = 2.7
static var fuel_life: float = 3.6
static var max_volumes: int = 4
static var volume_steps: int = 26
## A crater's embers: seconds they glow in the pit.
static var ember_seconds: float = 9.0

## Set by WeaponFX.explosion() for the blast it is laying (BlastFX then leaves its rolling cards out).
static var this_blast_volume: bool = false

static var _volumes: Array = []
static var _noise: ImageTexture3D
static var _vol_shader: Shader
static var _box: BoxMesh


## True when this blast's fireball is the volume (the caller then leaves its fireball cards out).
## Asked by WeaponFX.explosion() before it lays the cards; `spawn_volume()` follows.
static func takes_fireball() -> bool:
	if not enabled or WeaponFX._web():
		return false
	_prune()
	return _volumes.size() < max_volumes


static func _prune() -> void:
	_volumes = _volumes.filter(func(v): return is_instance_valid(v) and not (v as Node).is_queued_for_deletion())


static func volumes_alive() -> int:
	_prune()
	return _volumes.size()


## The tiling noise the volume is carved with: 48^3, fractal simplex, made once (tens of ms, the
## loading screen pays for it through warm()).
static func noise_texture() -> ImageTexture3D:
	if _noise != null:
		return _noise
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.seed = 3301
	fn.frequency = 0.06
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 3
	var n := 48
	var imgs: Array[Image] = fn.get_seamless_image_3d(n, n, n, false, 0.12, true)
	for im in imgs:
		if im.get_format() != Image.FORMAT_L8:
			im.convert(Image.FORMAT_L8)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_L8, n, n, n, false, imgs)
	_noise = tex
	return _noise


static func volume_material() -> ShaderMaterial:
	if _vol_shader == null:
		_vol_shader = preload("res://shaders/blast_volume.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _vol_shader
	m.set_shader_parameter("noise3d", noise_texture())
	return m


## The volume fireball at `at` (global) of `radius`. Returns the node.
static func spawn_volume(parent: Node, at: Vector3, radius: float, fuel: bool) -> MeshInstance3D:
	_prune()
	var big := 1.0 + (0.3 if fuel else 0.0)
	var half := Vector3(1.5, 1.6, 1.5) * big
	var centre := Vector3(0.0, 1.3, 0.0) * big
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3(2.0, 2.0, 2.0)
	var mi := MeshInstance3D.new()
	mi.name = "BlastVolume"
	mi.mesh = _box
	var mat := volume_material()
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("fuel", 1.0 if fuel else 0.0)
	mat.set_shader_parameter("half_r", half)
	mat.set_shader_parameter("centre_r", centre)
	mat.set_shader_parameter("seed", Vector3(randf() * 7.0, randf() * 7.0, randf() * 7.0))
	mat.set_shader_parameter("steps", volume_steps)
	if OS.get_environment("BLAST3_DEBUG") != "":
		mat.set_shader_parameter("debug", int(OS.get_environment("BLAST3_DEBUG")))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = Transform3D(Basis.from_scale(half * radius), at + centre * radius)
	# Its bounds for culling: the box itself (a box mesh's own AABB is right; nothing to add).
	var life := fuel_life if fuel else volume_life
	var tw := mi.create_tween()
	tw.tween_method(func(v: float):
		if is_instance_valid(mat):
			mat.set_shader_parameter("t", v)
			mat.set_shader_parameter("fade", 1.0 - smoothstep(life * 0.55, life, v)),
		0.0, life, life)
	tw.tween_callback(mi.queue_free)
	_volumes.append(mi)
	return mi


## The loading screen's warm-up (the noise, a material).
static func warm() -> Array:
	noise_texture()
	return [volume_material()]
