class_name WeaponFX
extends RefCounted
## Code-built visual effects for weapons: tracers, muzzle flashes, surface-aware impacts,
## bullet holes and explosions. Everything is built from primitives, generated textures and
## short tweens, so there is nothing to import and the web build gets the same effects with
## the expensive layers switched off.
##
## Three traps here have each cost a whole session - do not undo them:
##  * billboarded particle materials need `billboard_keep_scale = true`, or every puff renders
##    exactly one metre no matter what `scale_amount` says;
##  * a `Curve` clamps its values to `max_value` (default 1.0), so raise it before using a
##    growth factor above 1;
##  * a particle system's automatic bounds start empty, so `custom_aabb` has to cover how far
##    the particles actually travel or the whole burst vanishes.


# ---------------------------------------------------------------------------------------------
# Tunables. This is a static utility class, never a node, so these are static vars rather than
# @export: set them from anywhere (WeaponFX.tracer_heat = 4.0) and every weapon follows.
# ---------------------------------------------------------------------------------------------

## Brightness multiplier of a tracer's core. Above 1 so it is HDR and the glow pass blooms it -
## that, not the colour, is what makes a streak read as hot metal instead of a painted line.
static var tracer_heat: float = 3.4
## Radius of the soft glow sleeve around a tracer, as a multiple of the core radius.
static var tracer_sleeve: float = 3.8
## Metres per second the bright head travels down the tracer line.
static var tracer_head_speed: float = 1100.0
## Brightness multiplier of the muzzle flash core (HDR, same reason as `tracer_heat`).
static var muzzle_heat: float = 3.2
## Peak energy of the light a muzzle flash throws into the world.
static var muzzle_light_energy: float = 7.0
## Reach of the muzzle flash light in metres (scaled by the flash size).
static var muzzle_light_range: float = 9.0
## Seconds the muzzle flash light lasts.
static var muzzle_light_time: float = 0.07
## Width of the muzzle star flare, as a multiple of the flash size. Third person, so this is
## seen from a few metres away: too big and every shot fills the screen.
static var muzzle_flare_scale: float = 5.0
## One shot in N also gets barrel smoke and ejected sparks (every shot is too busy and too costly).
static var muzzle_smoke_every: int = 3
## Beyond this distance an impact is only its hot flash: no dust, sparks, chips or hole.
static var impact_detail_distance: float = 55.0
## Beyond this distance an impact draws nothing at all.
static var impact_far_distance: float = 160.0
## Most detailed impacts allowed at once. Past this, extra hits fall back to the cheap flash.
static var impact_budget: int = 14
## Impacts closer than this also throw solid chips that bounce in the scene's own lighting.
static var impact_chip_distance: float = 26.0
## How many bullet holes stay in the world. The oldest is removed when a new one goes over.
static var bullet_hole_max: int = 56
## Seconds a bullet hole stays before it fades out.
static var bullet_hole_life: float = 26.0
## Width of a bullet hole in metres.
static var bullet_hole_size: float = 0.17
## Seconds the explosion embers keep glowing after the fireball is gone.
static var ember_life: float = 3.0
## Heat shimmer over an explosion. Reads the screen, so it is off on the web build.
static var shimmer_enabled: bool = true
## How far the heat shimmer bends the picture behind it (screen widths).
static var shimmer_strength: float = 0.05
## Rays fired sideways from a blast to find walls to kick dust off.
static var dust_rays: int = 7
## Most wall-dust puffs one blast spawns, however many walls it finds.
static var dust_puffs_max: int = 4
## Fraction of the particle counts used on the web build (single threaded, Compatibility).
static var web_particle_scale: float = 0.5


## Physics layers an effect may probe: world + props + npc. Mirrors Player.AIM_MASK, kept
## local so weapon effects have no reference back to the player.
const HIT_MASK := 1 | 4 | 8

## What a bullet went into. Decides the dust colour, whether it sparks, and what hole it leaves.
enum Surface { CONCRETE, METAL, GLASS, WOOD, DIRT, FLESH }

## Per-surface impact look. `dust` is the colour ramp of the puff cone, `sparks` how many
## additive sparks fly off, `chips` how many lit solid fragments, `hole` whether it scars.
const SURFACES := {
	Surface.CONCRETE: {
		"dust": [Color(0.86, 0.84, 0.80, 0.95), Color(0.66, 0.64, 0.60, 0.55), Color(0.48, 0.46, 0.43, 0.0)],
		"dust_size": 0.34, "dust_count": 12, "dust_speed": 3.4,
		"sparks": 5, "spark_color": Color(2.4, 1.5, 0.55), "spark_speed": 7.0,
		"chips": 7, "chip_color": Color(0.55, 0.53, 0.50), "chip_size": 0.05,
		"hole": true, "hole_tint": Color(0.07, 0.065, 0.06), "hole_scale": 1.0, "glass": false,
	},
	Surface.METAL: {
		"dust": [Color(1.0, 0.85, 0.55, 0.8), Color(0.55, 0.45, 0.35, 0.35), Color(0.3, 0.28, 0.26, 0.0)],
		"dust_size": 0.20, "dust_count": 6, "dust_speed": 2.6,
		"sparks": 22, "spark_color": Color(3.0, 2.1, 0.8), "spark_speed": 13.0,
		"chips": 4, "chip_color": Color(0.62, 0.60, 0.58), "chip_size": 0.035,
		"hole": true, "hole_tint": Color(0.10, 0.095, 0.09), "hole_scale": 0.75, "glass": false,
	},
	Surface.GLASS: {
		"dust": [Color(1.6, 1.8, 2.0, 0.9), Color(0.75, 0.85, 0.95, 0.45), Color(0.5, 0.6, 0.7, 0.0)],
		"dust_size": 0.16, "dust_count": 9, "dust_speed": 4.2,
		"sparks": 14, "spark_color": Color(1.8, 2.2, 2.6), "spark_speed": 9.0,
		"chips": 10, "chip_color": Color(0.80, 0.88, 0.92), "chip_size": 0.045,
		"hole": true, "hole_tint": Color(0.85, 0.92, 1.0), "hole_scale": 1.6, "glass": true,
	},
	Surface.WOOD: {
		"dust": [Color(0.70, 0.55, 0.36, 0.9), Color(0.48, 0.36, 0.22, 0.5), Color(0.30, 0.23, 0.15, 0.0)],
		"dust_size": 0.26, "dust_count": 9, "dust_speed": 3.0,
		"sparks": 2, "spark_color": Color(2.0, 1.2, 0.4), "spark_speed": 5.0,
		"chips": 8, "chip_color": Color(0.46, 0.34, 0.21), "chip_size": 0.06,
		"hole": true, "hole_tint": Color(0.10, 0.07, 0.04), "hole_scale": 1.05, "glass": false,
	},
	Surface.DIRT: {
		"dust": [Color(0.62, 0.55, 0.44, 0.95), Color(0.46, 0.40, 0.31, 0.55), Color(0.32, 0.28, 0.22, 0.0)],
		"dust_size": 0.40, "dust_count": 14, "dust_speed": 3.2,
		"sparks": 0, "spark_color": Color(1.0, 0.8, 0.4), "spark_speed": 4.0,
		"chips": 5, "chip_color": Color(0.36, 0.31, 0.24), "chip_size": 0.05,
		"hole": true, "hole_tint": Color(0.14, 0.11, 0.08), "hole_scale": 1.3, "glass": false,
	},
	Surface.FLESH: {
		"dust": [Color(0.42, 0.06, 0.05, 0.75), Color(0.28, 0.05, 0.04, 0.35), Color(0.18, 0.04, 0.03, 0.0)],
		"dust_size": 0.18, "dust_count": 7, "dust_speed": 2.4,
		"sparks": 0, "spark_color": Color(1.0, 0.4, 0.3), "spark_speed": 3.0,
		"chips": 0, "chip_color": Color(0.35, 0.08, 0.06), "chip_size": 0.03,
		"hole": false, "hole_tint": Color(0.2, 0.03, 0.03), "hole_scale": 1.0, "glass": false,
	},
}

static var _web_cache: int = -1
static var _impact_times: Array[float] = []
static var _shot_count: int = 0
static var _holes: Array = []


# ---------------------------------------------------------------------------------------------
# Small shared helpers
# ---------------------------------------------------------------------------------------------

static func fx_parent(node: Node) -> Node:
	var scene := node.get_tree().current_scene
	return scene if scene != null else node.get_tree().root


static func unshaded(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## True on the web build, where the Compatibility renderer and one thread mean half the
## particles, no decals and no screen-reading shimmer.
static func _web() -> bool:
	if _web_cache < 0:
		_web_cache = 1 if OS.has_feature("web") else 0
	return _web_cache == 1


static func _count(n: int) -> int:
	return maxi(1, int(round(float(n) * web_particle_scale))) if _web() else n


static func _camera(node: Node) -> Camera3D:
	var tree := node.get_tree()
	return tree.root.get_camera_3d() if tree != null else null


## Distance from the eye to a point. 0 when there is no camera yet, which counts as close so
## effects still play in the headless check.
static func _view_distance(node: Node, at: Vector3) -> float:
	var cam := _camera(node)
	return cam.global_position.distance_to(at) if cam != null else 0.0


static func _space(node: Node) -> PhysicsDirectSpaceState3D:
	var n3 := node as Node3D
	if n3 != null and n3.is_inside_tree():
		return n3.get_world_3d().direct_space_state
	var tree := node.get_tree()
	return tree.root.world_3d.direct_space_state if tree != null else null


## A basis whose local +Y points along `dir`, with an optional roll about it. Used for anything
## that has to stand on a surface: cylinders (their mesh runs up +Y), particle cones and decals
## (they project down their own -Y). Built with `Basis.looking_at` rather than the three-axis
## constructor so there is no doubt about rows versus columns.
static func _basis_up(dir: Vector3, roll: float = 0.0) -> Basis:
	var up := dir.normalized()
	if up.is_zero_approx():
		up = Vector3.UP
	var side := Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP
	var fwd := up.cross(side).normalized()
	var b := Basis.looking_at(fwd, up)
	return b.rotated(up, roll) if roll != 0.0 else b


## Same colour, `f` of the brightness, alpha untouched. Used to build spark ramps that cool
## down without fading out halfway.
static func _dim(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)


static func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, colors[0])
	g.set_color(1, colors[colors.size() - 1])
	for i in range(1, colors.size() - 1):
		g.add_point(float(i) / float(colors.size() - 1), colors[i])
	return g


# ---------------------------------------------------------------------------------------------
# Generated textures. All built once and cached: a sprite sheet would be four files to import
# and these are a few thousand pixels each.
# ---------------------------------------------------------------------------------------------

## A soft round particle sprite: a radial white-to-transparent gradient. Without it every puff
## is a hard square, which is the single most obvious tell of a cheap effect.
static var _puff_cache: Texture2D


static func puff_texture() -> Texture2D:
	if _puff_cache != null:
		return _puff_cache
	# A billow, not a disc. The puffs used to be a smooth radial gradient, so a fireball of forty
	# of them read as one soft blob and smoke as fog: nothing in it caught the eye as fire. Here
	# the edge is pushed in and out by fractal noise and the inside carries lumps and folds, and
	# every particle is spun to its own angle, so a burst is rolling, lumpy and never the same
	# twice. Built once (a few ms) and cached; the loading screen pays for it.
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 71
	noise.frequency = 0.035
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var detail := FastNoiseLite.new()
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.seed = 13
	detail.frequency = 0.11
	for y in size:
		for x in size:
			var dx := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var dy := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			var r := sqrt(dx * dx + dy * dy)
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var d := detail.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var edge := 0.58 + 0.42 * n
			var a := 1.0 - smoothstep(edge * 0.45, edge, r)
			a *= 0.75 + 0.25 * d
			var shade := 0.40 + 0.45 * n + 0.15 * d
			img.set_pixel(x, y, Color(shade, shade, shade, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_puff_cache = tex
	return tex


static var _flare_cache: Texture2D


## A four-point star with a halo, for muzzle flashes and tracer heads. A flash that is only a
## round blob reads as a ball of light; the spikes are what say "gas leaving a barrel".
static func flare_texture() -> Texture2D:
	if _flare_cache != null:
		return _flare_cache
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var halo := pow(clampf(1.0 - r, 0.0, 1.0), 2.6)
			var spoke_h := pow(clampf(1.0 - absf(v) * 16.0, 0.0, 1.0), 1.4) * pow(clampf(1.0 - absf(u), 0.0, 1.0), 2.0)
			var spoke_v := pow(clampf(1.0 - absf(u) * 16.0, 0.0, 1.0), 1.4) * pow(clampf(1.0 - absf(v), 0.0, 1.0), 2.0)
			var a := clampf(halo + (spoke_h + spoke_v) * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_flare_cache = ImageTexture.create_from_image(img)
	return _flare_cache


static var _hole_cache: Texture2D


## A bullet hole: a dark ragged pit with a lighter dust rim. The rim is what stops it reading
## as a sticker - a real hole throws pulverised material out around itself.
static func hole_texture() -> Texture2D:
	if _hole_cache != null:
		return _hole_cache
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var ang := atan2(v, u)
			# A small ragged pit, then a wide soft halo of pulverised material around it. The
			# halo is what stops a hole reading as a sticker; keep the pit edge only slightly
			# irregular, because a strong wobble turns it into a star instead of a hole.
			var wob := 0.014 * sin(ang * 7.0 + 1.3) + 0.009 * sin(ang * 13.0 - 0.7)
			var core := 0.15 + wob
			var pit := 1.0 - smoothstep(core, core + 0.10, r)
			var spall := (1.0 - smoothstep(core + 0.02, 0.46, r)) * 0.40
			var shade := lerpf(0.72, 0.04, pit)
			img.set_pixel(x, y, Color(shade, shade * 0.97, shade * 0.93,
				clampf(pit + spall * (1.0 - pit), 0.0, 1.0)))
	_hole_cache = ImageTexture.create_from_image(img)
	return _hole_cache


static var _crack_cache: Texture2D


## A glass crack star: radial splits plus two concentric rings, bright so it catches the light.
static func crack_texture() -> Texture2D:
	if _crack_cache != null:
		return _crack_cache
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (float(x) + 0.5) / float(size) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(size) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var ang := atan2(v, u)
			# Nine splits, wandering a little so they are not a clean asterisk.
			var spokes := absf(sin(ang * 4.5 + sin(ang * 3.0) * 0.4 + r * 2.0))
			var split := pow(clampf(1.0 - spokes * 6.0, 0.0, 1.0), 0.6)
			var ring_a := clampf(1.0 - absf(r - 0.30) * 26.0, 0.0, 1.0) * 0.40
			var ring_b := clampf(1.0 - absf(r - 0.55) * 30.0, 0.0, 1.0) * 0.26
			var hub := pow(clampf(1.0 - r * 7.0, 0.0, 1.0), 1.5)
			var a := clampf((split + ring_a + ring_b) * (1.0 - smoothstep(0.30, 0.92, r)) + hub, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.92, 0.96, 1.0, a))
	_crack_cache = ImageTexture.create_from_image(img)
	return _crack_cache


# ---------------------------------------------------------------------------------------------
# Particle plumbing
# ---------------------------------------------------------------------------------------------

static var _mat_add: StandardMaterial3D
static var _mat_mix: StandardMaterial3D
static var _mat_behind: StandardMaterial3D


## Material for a billboarded particle sprite. `additive` for fire and sparks (they add light),
## plain alpha for smoke and dust (they block it). Cached: two materials serve every burst in
## the game, so a hundred impacts do not build a hundred shader variants.
static func _puff_material(additive: bool, behind: bool = false) -> StandardMaterial3D:
	if additive and _mat_add != null:
		return _mat_add
	if behind and not additive and _mat_behind != null:
		return _mat_behind
	if not behind and not additive and _mat_mix != null:
		return _mat_mix
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Billboarding normalises the particle's transform, which throws away scale_amount and makes
	# every puff exactly one metre no matter what the emitter asks for. This keeps the size.
	mat.billboard_keep_scale = true
	mat.particles_anim_h_frames = 1
	mat.particles_anim_v_frames = 1
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = puff_texture()
	mat.disable_receive_shadows = true
	# Soft particles: a puff fades out where it meets the road or a wall instead of being cut
	# along it, which drew the fireball with a ruler-straight bottom edge. Reads the depth
	# buffer, so desktop only.
	if not _web():
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 1.2
	if additive:
		_mat_add = mat
	elif behind:
		# Smoke and dust draw before the fire whatever their depth. Sorted puff by puff, the
		# grey smoke rising through the fireball veiled it, and the fire came out a pale beige
		# ball behind a grey one.
		mat.render_priority = -1
		_mat_behind = mat
	else:
		_mat_mix = mat
	return mat


## One layer of billboarded puffs. `aim` turns the emission cone (its local +Y is the axis), so
## an impact throws its dust back along the surface normal instead of straight up; `flatness`
## squashes the cone into the plane across that axis, which is how a blast gets a ground skirt.
## Returns the node so the caller can position it.
static func _puff_layer(parent: Node, at: Vector3, count: int, size: float, life: float,
		speed_min: float, speed_max: float, gravity: float, ramp: Gradient, additive: bool,
		spread: float = 180.0, grow: float = 2.2, aim: Basis = Basis(), flatness: float = 0.0,
		life_rand: float = 0.0, damp: float = 1.0, behind: bool = false,
		variety: Gradient = null) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, count)
	p.lifetime = life
	p.lifetime_randomness = life_rand
	# `flatness` does not squash a cone that is already aimed along the emitter's axis: the
	# engine builds a direction from an azimuth about local Y and an elevation, and flatness
	# only narrows the elevation spread. Aimed up, flatness 1 gives a column, not a skirt. Aimed
	# along local Z it pins the elevation at zero and leaves the azimuth free, which is a flat
	# ring lying in the local XZ plane - the surface plane, since `aim` puts local Y on the normal.
	p.direction = Vector3.BACK if flatness > 0.0 else Vector3.UP
	p.spread = spread
	p.flatness = flatness
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.gravity = Vector3(0.0, gravity, 0.0)
	p.damping_min = speed_max * 0.2 * damp
	p.damping_max = speed_max * 0.45 * damp
	p.scale_amount_min = size * 0.65
	p.scale_amount_max = size
	# Curve values are clamped to max_value, which defaults to 1.0 - without raising it the
	# `grow` factor silently does nothing and puffs never expand as they age.
	var curve := Curve.new()
	curve.max_value = maxf(1.0, grow)
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, grow))
	p.scale_amount_curve = curve
	p.color_ramp = ramp
	# Per-puff tint multiplied into the ramp, so one burst has hotter and cooler lumps in it.
	if variety:
		p.color_initial_ramp = variety
	p.angle_min = -180.0
	p.angle_max = 180.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _puff_material(additive, behind)
	p.mesh = quad
	parent.add_child(p)
	p.global_transform = Transform3D(aim, at)
	# A particle system's automatic bounds start empty, and an empty box means the renderer has
	# nothing to draw against, so the whole burst can vanish. Give it a box big enough for how
	# far the particles will actually travel. (Same trap as the rigged character meshes.)
	var span := life * (1.0 + life_rand)
	var reach := speed_max * span + size * maxf(grow, 1.0) + absf(gravity) * span * span
	p.custom_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * (reach * 2.0))
	p.restart()
	p.emitting = true
	var tween := p.create_tween()
	tween.tween_interval(span + 0.2)
	tween.tween_callback(p.queue_free)
	return p


## Solid lit fragments - chips off a wall, chunks off a blast. They sit in the scene's own
## lighting instead of glowing, which is what tells the eye they are debris and not sparks.
static func _chip_layer(parent: Node, at: Vector3, count: int, chip_size: float, life: float,
		speed_min: float, speed_max: float, color: Color, aim: Basis = Basis(),
		spread: float = 60.0, gravity: float = -28.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, count)
	p.lifetime = life
	p.lifetime_randomness = 0.35
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.gravity = Vector3(0.0, gravity, 0.0)
	p.angular_velocity_min = -900.0
	p.angular_velocity_max = 900.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var box := BoxMesh.new()
	box.size = Vector3(chip_size, chip_size * 0.6, chip_size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	box.material = mat
	p.mesh = box
	parent.add_child(p)
	p.global_transform = Transform3D(aim, at)
	var reach := speed_max * life * 1.35 + absf(gravity) * life * life + 2.0
	p.custom_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * (reach * 2.0))
	p.restart()
	p.emitting = true
	var tween := p.create_tween()
	tween.tween_interval(life * 1.4 + 0.2)
	tween.tween_callback(p.queue_free)
	return p


# ---------------------------------------------------------------------------------------------
# Tracers
# ---------------------------------------------------------------------------------------------

## A hot round streak from `from` to `to`. Three parts, because one flat cylinder always reads
## as a drawn line: an HDR core the glow pass blooms, a wide soft sleeve around it, and a
## bright head that actually travels the distance so the eye follows the shot out.
static func tracer(node: Node, from: Vector3, to: Vector3, color: Color, life: float = 0.06, radius: float = 0.03) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.05:
		return
	dir /= length
	var parent := fx_parent(node)
	var aim := Transform3D(_basis_up(dir), from + dir * length * 0.5)

	var hot := Color(color.r * tracer_heat, color.g * tracer_heat, color.b * tracer_heat)
	var core := _beam(parent, aim, radius, length, hot, 1.0)
	var ct := core.create_tween()
	ct.tween_property(core, "scale", Vector3(0.01, 1.0, 0.01), life)
	ct.parallel().tween_property(core.material_override, "albedo_color:a", 0.0, life)
	ct.tween_callback(core.queue_free)

	if _web():
		return # One cylinder only: the web build draws this ten times a second.

	var sleeve := _beam(parent, aim, radius * tracer_sleeve, length,
		Color(color.r, color.g * 0.8, color.b * 0.55), 0.22)
	var st := sleeve.create_tween()
	st.tween_property(sleeve, "scale", Vector3(0.2, 1.0, 0.2), life * 0.8)
	st.parallel().tween_property(sleeve.material_override, "albedo_color:a", 0.0, life * 0.8)
	st.tween_callback(sleeve.queue_free)

	# The head. Travelling the line takes a few hundredths of a second at rifle ranges, which is
	# exactly long enough for the eye to catch the direction of the shot.
	var travel := clampf(length / maxf(tracer_head_speed, 1.0), 0.02, 0.12)
	var head := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 14.0, radius * 14.0)
	head.mesh = quad
	var head_mat := unshaded(Color(hot.r, hot.g, hot.b), 0.95)
	head_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	head_mat.albedo_texture = flare_texture()
	head_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	head_mat.billboard_keep_scale = true
	head.material_override = head_mat
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(head)
	head.global_position = from
	var ht := head.create_tween()
	ht.tween_property(head, "global_position", to, travel)
	ht.parallel().tween_property(head_mat, "albedo_color:a", 0.0, travel).set_delay(travel * 0.55)
	ht.tween_callback(head.queue_free)


static func _beam(parent: Node, aim: Transform3D, radius: float, length: float, color: Color, alpha: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 6
	cyl.rings = 1
	mesh.mesh = cyl
	var mat := unshaded(color, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_transform = aim
	return mesh


# ---------------------------------------------------------------------------------------------
# Muzzle flash
# ---------------------------------------------------------------------------------------------

## The flash at the muzzle. It lights the world: a real light for a few hundredths of a second
## is what puts the shot in the street with the player instead of on top of the picture.
static func flash(node: Node, at: Vector3, color: Color = Color(1.0, 0.8, 0.3), size: float = 0.25, life: float = 0.05) -> void:
	var parent := fx_parent(node)
	_shot_count += 1
	# Down the weapon's own -Z: the barrel direction, which is where the light and the gas go.
	var n3 := node as Node3D
	var fwd := -n3.global_basis.z if n3 != null and n3.is_inside_tree() else Vector3.FORWARD

	var core := _sphere(node, at, size, Color(color.r * muzzle_heat, color.g * muzzle_heat, color.b * muzzle_heat), 1.0)
	_additive(core)
	var tween := core.create_tween()
	tween.tween_property(core, "scale", Vector3.ONE * size * 0.2, life)
	tween.parallel().tween_property(core.material_override, "albedo_color:a", 0.0, life)
	tween.tween_callback(core.queue_free)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.86, 0.62)
	light.light_energy = muzzle_light_energy * (size / 0.25)
	light.omni_range = muzzle_light_range * clampf(size / 0.25, 0.7, 2.5)
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	parent.add_child(light)
	# In front of the muzzle, not inside it: at the muzzle it mostly lights the gun and the
	# player's own arms, and the point of the flash is that it lights what is being shot at.
	light.global_position = at + fwd * size * 1.5
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, muzzle_light_time).set_ease(Tween.EASE_IN)
	lt.tween_callback(light.queue_free)

	# Star flare, the spikes of gas leaving the barrel.
	var flare := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size * muzzle_flare_scale, size * muzzle_flare_scale)
	flare.mesh = quad
	var flare_mat := unshaded(Color(color.r * 2.2, color.g * 2.2, color.b * 2.0), 0.9)
	flare_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flare_mat.albedo_texture = flare_texture()
	flare_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flare_mat.billboard_keep_scale = true
	flare.material_override = flare_mat
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(flare)
	flare.global_position = at
	# A billboard replaces the model basis with the camera's, so rolling the node does nothing.
	# Scale is what survives (that is what billboard_keep_scale keeps), so vary the shape there.
	flare.scale = Vector3(randf_range(0.8, 1.3), randf_range(0.8, 1.3), 1.0)
	var ft := flare.create_tween()
	ft.tween_property(flare, "scale", flare.scale * 1.6, life * 1.6)
	ft.parallel().tween_property(flare_mat, "albedo_color:a", 0.0, life * 1.6)
	ft.tween_callback(flare.queue_free)

	if _web() or _shot_count % maxi(1, muzzle_smoke_every) != 0:
		return

	# Every few shots, gas and grit leaving the barrel.
	var aim := _basis_up(fwd)
	_puff_layer(parent, at + fwd * size * 0.5, 5, size * 1.6, 0.42, 1.2, 3.2, 0.9,
		_ramp([Color(0.75, 0.72, 0.68, 0.45), Color(0.6, 0.58, 0.55, 0.22), Color(0.5, 0.49, 0.47, 0.0)]),
		false, 26.0, 2.6, aim, 0.0, 0.3)
	_puff_layer(parent, at + fwd * size * 0.3, 7, size * 0.16, 0.34, 4.0, 9.0, -14.0,
		_ramp([Color(2.6, 1.7, 0.6, 1.0), Color(1.6, 0.7, 0.2, 0.8), Color(0.7, 0.2, 0.05, 0.0)]),
		true, 34.0, 0.6, aim, 0.0, 0.4)


# ---------------------------------------------------------------------------------------------
# Impacts
# ---------------------------------------------------------------------------------------------

## Which surface a collider counts as. Groups, meta and duck typing rather than class names:
## buildings, vehicles and the player all call back into this file for materials, so naming
## their classes here would make a reference cycle, and the effects would stop being something
## any script can use without dragging the world in.
static func classify(collider: Object, at: Vector3, normal: Vector3) -> Surface:
	var node := collider as Node
	if node == null:
		return Surface.CONCRETE
	if node.is_in_group("vehicle"):
		return Surface.METAL
	if node.is_in_group("pedestrian") or node is CharacterBody3D or node.has_method("knock"):
		return Surface.FLESH
	var parent := node.get_parent()
	if parent != null and parent.has_method("fling"):
		return Surface.FLESH # a ragdoll: one rigid body under the Ragdoll node
	if node.has_meta("terrain"):
		return Surface.DIRT
	if node.is_in_group("building"):
		return _building_surface(node, at, normal)
	if node.name == "StreetProps":
		# One body per chunk holds BOTH the street props and every road, pavement, plaza and
		# car-park slab (CityChunk._add_shape puts them all on it), so the name alone says
		# nothing. A breakable prop's shape carries a "prop" meta and a ground slab does not -
		# the same test StreetProps.take_hit() uses to decide what breaks.
		return Surface.METAL if _is_street_prop(node, at, normal) else Surface.CONCRETE
	if node is RigidBody3D:
		return Surface.METAL if _script_is(node, "trash_can.gd") or _script_is(node, "physics_prop.gd") else Surface.WOOD
	return Surface.CONCRETE


## True when the point landed on one of the chunk's street props rather than on the ground.
##
## Both live on the chunk's single StreetProps body, so this asks the physics server which of
## its shapes contains the point and looks for the "prop" meta CityChunk._add_prop() puts on
## every breakable prop's shape. Ground slabs carry no meta, and the ground is what a shot in
## the city hits nearly every time, so an inconclusive query answers "ground".
static func _is_street_prop(body: Node, at: Vector3, normal: Vector3) -> bool:
	var co := body as CollisionObject3D
	if co == null or not co.is_inside_tree():
		return false
	var world := co.get_world_3d()
	if world == null or world.direct_space_state == null:
		return false
	var q := PhysicsPointQueryParameters3D.new()
	# A shade inside the surface: exactly on a box face is not reliably inside it.
	q.position = at - normal * 0.05
	q.collision_mask = co.collision_layer
	q.collide_with_areas = false
	for hit in world.direct_space_state.intersect_point(q, 8):
		if hit.get("collider") != body:
			continue
		var cs := co.shape_owner_get_owner(co.shape_find_owner(int(hit.shape))) as CollisionShape3D
		if cs != null and cs.has_meta("prop"):
			return true
	return false


static func _script_is(node: Node, file: String) -> bool:
	var s := node.get_script() as Script
	return s != null and s.resource_path.ends_with(file)


static var _glass_enums: Dictionary = {}


## Where a facade is glass. Curtain-wall towers are glass all over; everything else is glass
## only in the shop windows at street level, because punched windows are a small part of a
## wall's area and the rest of it is concrete.
static func _building_surface(node: Node, at: Vector3, normal: Vector3) -> Surface:
	if absf(normal.y) >= 0.5:
		return Surface.CONCRETE # a roof or a soffit
	if _glass_enums.is_empty():
		# Read the numbers off the building script's own enums instead of hard-coding them,
		# so reordering an enum over there cannot quietly turn every tower to concrete.
		_glass_enums = {"finish": 3, "style": 2, "warehouse": 7}
		var s := node.get_script() as Script
		if s != null:
			var consts := s.get_script_constant_map()
			if consts.has("Finish") and (consts["Finish"] as Dictionary).has("GLASS"):
				_glass_enums["finish"] = int(consts["Finish"]["GLASS"])
			if consts.has("WindowStyle") and (consts["WindowStyle"] as Dictionary).has("CURTAIN"):
				_glass_enums["style"] = int(consts["WindowStyle"]["CURTAIN"])
			if consts.has("Shape") and (consts["Shape"] as Dictionary).has("WAREHOUSE"):
				_glass_enums["warehouse"] = int(consts["Shape"]["WAREHOUSE"])
	var finish: Variant = node.get("finish")
	var style: Variant = node.get("window_style")
	if typeof(finish) == TYPE_INT and int(finish) == int(_glass_enums["finish"]):
		return Surface.GLASS
	if typeof(style) == TYPE_INT and int(style) == int(_glass_enums["style"]):
		return Surface.GLASS
	# A shop window, but only where the building actually built one. Building's own condition
	# (building.gd, where `storefront` is computed) is allow_storefront AND not a warehouse AND
	# the part is on the ground AND the part is taller than storefront_height + 3; testing only
	# allow_storefront called every warehouse wall and every low block glass, so shooting an
	# industrial shed rained glass shards off breeze block.
	var n3 := node as Node3D
	var shopfront: Variant = node.get("storefront_height")
	var shape: Variant = node.get("shape")
	var warehouse := typeof(shape) == TYPE_INT and int(shape) == int(_glass_enums["warehouse"])
	if n3 != null and typeof(shopfront) == TYPE_FLOAT and node.get("allow_storefront") == true and not warehouse:
		var local_y := at.y - n3.global_position.y
		if local_y > 0.6 and local_y < float(shopfront) and _has_tall_ground_part(node, at, float(shopfront)):
			return Surface.GLASS # a shop window
	return Surface.CONCRETE


## True when the part standing at this point reaches the ground and is tall enough to carry a
## shopfront. `parts` is Building's own list of boxes ({size, center}, centre local to the
## building), and the storefront is only built on a ground-floor part taller than
## storefront_height + 3 - a two-metre podium edge gets the stone base instead.
static func _has_tall_ground_part(node: Node, at: Vector3, shopfront: float) -> bool:
	var n3 := node as Node3D
	var parts: Variant = node.get("parts")
	if n3 == null or typeof(parts) != TYPE_ARRAY:
		return true # no parts list to consult: keep the old, permissive answer
	var local := n3.to_local(at)
	for part: Variant in parts:
		if typeof(part) != TYPE_DICTIONARY:
			continue
		var size: Vector3 = (part as Dictionary).get("size", Vector3.ZERO)
		var center: Vector3 = (part as Dictionary).get("center", Vector3.ZERO)
		if center.y - size.y * 0.5 > 0.5:
			continue # not a ground-storey part
		if absf(local.x - center.x) > size.x * 0.5 + 0.35:
			continue
		if absf(local.z - center.z) > size.z * 0.5 + 0.35:
			continue
		return size.y > shopfront + 3.0
	return false


## Finds the surface a shot landed on when the caller only knows the point. One short ray
## through the hit, along the way the bullet was travelling.
static func probe_surface(node: Node, at: Vector3, along: Vector3) -> Dictionary:
	var space := _space(node)
	if space == null or along.is_zero_approx():
		return {}
	var dir := along.normalized()
	var q := PhysicsRayQueryParameters3D.create(at - dir * 0.5, at + dir * 0.5, HIT_MASK)
	return space.intersect_ray(q)


## A bullet landing. Surface aware: the dust, sparks, chips and hole all come from what was
## hit and all fly back along the surface normal. `normal` and `collider` are optional - when
## they are left out the point is probed, so old callers keep working.
static func impact(node: Node, at: Vector3, color: Color = Color(1.0, 0.85, 0.5),
		normal: Vector3 = Vector3.ZERO, collider: Object = null) -> void:
	var dist := _view_distance(node, at)
	if dist > impact_far_distance:
		return
	var parent := fx_parent(node)

	# The hot flash, always. It grows a little with distance so a far hit is still a visible
	# spark rather than a subpixel dot.
	var flash_size := 0.12 * clampf(dist / 35.0, 1.0, 3.0)
	var hot := _sphere(node, at, flash_size, Color(color.r * 2.2, color.g * 2.0, color.b * 1.8), 0.95)
	_additive(hot)
	var tw := hot.create_tween()
	tw.tween_property(hot, "scale", Vector3.ONE * flash_size * 3.5, 0.13)
	tw.parallel().tween_property(hot.material_override, "albedo_color:a", 0.0, 0.13)
	tw.tween_callback(hot.queue_free)

	# Budget: count the detailed impacts started in the last moment rather than bookkeeping a
	# live counter through tween callbacks, which is one more thing to leak.
	var now := Time.get_ticks_msec() * 0.001
	while not _impact_times.is_empty() and now - _impact_times[0] > 0.7:
		_impact_times.pop_front()
	if dist > impact_detail_distance or _impact_times.size() >= impact_budget:
		return

	var cam := _camera(node)
	var along := (at - cam.global_position).normalized() if cam != null else Vector3.DOWN
	var n := normal
	var who := collider
	if n.is_zero_approx() or who == null:
		var probe := probe_surface(node, at, along)
		if not probe.is_empty():
			if n.is_zero_approx():
				n = probe.normal
			if who == null:
				who = probe.collider
	if n.is_zero_approx():
		n = -along
	var surf := classify(who, at, n)
	var look: Dictionary = SURFACES[surf]
	var aim := _basis_up(n)
	var origin := at + n * 0.04

	_impact_times.append(now)
	_puff_layer(parent, origin, _count(int(look["dust_count"])), float(look["dust_size"]),
		0.55, float(look["dust_speed"]) * 0.35, float(look["dust_speed"]), -2.6,
		_ramp(look["dust"]), bool(look["glass"]), 52.0, 2.4, aim, 0.0, 0.3)

	var sparks := int(look["sparks"])
	if sparks > 0:
		var spark: Color = look["spark_color"]
		_puff_layer(parent, origin, _count(sparks), 0.035, 0.55, float(look["spark_speed"]) * 0.4,
			float(look["spark_speed"]), -24.0,
			_ramp([spark, _dim(spark, 0.5), Color(0.4, 0.12, 0.03, 0.0)]),
			true, 62.0, 0.5, aim, 0.0, 0.5)

	if dist < impact_chip_distance and int(look["chips"]) > 0 and not _web():
		var chip: Color = look["chip_color"]
		_chip_layer(parent, origin, _count(int(look["chips"])), float(look["chip_size"]), 0.9,
			1.5, float(look["dust_speed"]) * 1.4, chip, aim, 58.0)

	if bool(look["hole"]):
		bullet_hole(node, at, n, surf, who)


## A hole that stays. Decals need a rendering device, so the Compatibility renderer (the web
## build) skips them. Parented to whatever was hit, so a hole in a car drives away with it and
## a hole in a chunk dies when the chunk unloads. The pool is capped: an unlimited number of
## decals is a frame-rate cliff in a city the player can shoot at for an hour.
static func bullet_hole(node: Node, at: Vector3, normal: Vector3, surf: Surface, collider: Object = null) -> void:
	if RenderingServer.get_rendering_device() == null:
		return
	var look: Dictionary = SURFACES[surf]
	var decal := Decal.new()
	var glass := bool(look["glass"])
	decal.texture_albedo = crack_texture() if glass else hole_texture()
	if glass:
		decal.texture_emission = crack_texture()
		decal.emission_energy = 0.6
	var tint: Color = look["hole_tint"]
	decal.modulate = tint
	decal.albedo_mix = 0.92
	var w := bullet_hole_size * float(look["hole_scale"]) * randf_range(0.85, 1.2)
	decal.size = Vector3(w, maxf(w, 0.35), w)
	decal.upper_fade = 0.6
	decal.lower_fade = 0.6
	# Without a normal fade the projection smears down any wall it grazes, which is the classic
	# stretched-decal look.
	decal.normal_fade = 0.6
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 55.0
	decal.distance_fade_length = 18.0
	var host := collider as Node3D
	if host == null or not host.is_inside_tree():
		host = fx_parent(node) as Node3D
	if host == null:
		return
	host.add_child(decal)
	decal.global_transform = Transform3D(_basis_up(normal, randf_range(-PI, PI)), at + normal * 0.02)

	_holes.append(decal)
	while _holes.size() > bullet_hole_max:
		var old: Object = _holes.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var t := decal.create_tween()
	t.tween_interval(bullet_hole_life)
	t.tween_property(decal, "modulate:a", 0.0, 3.0)
	t.tween_callback(decal.queue_free)


# ---------------------------------------------------------------------------------------------
# Explosions
# ---------------------------------------------------------------------------------------------

## A full explosion: light flash, fireball, rolling smoke, sparks, long-lived embers, heat
## shimmer, a ground dust skirt, dust kicked off the walls around it, a shockwave ring, lit
## debris and a scorch mark, plus a camera shake that falls off with distance.
## `power` scales how hard the fast layers are thrown (1.0 is a rocket).
## Most blood splats on the ground at once; the oldest goes when a new one would pass it.
static var blood_splat_max: int = 24
static var _splats: Array = []


## A wound opening: a spray of droplets thrown along `dir` that falls under gravity, a thin red
## mist, and a dark splat on whatever is below (desktop only; decals are Forward+). `amount`
## scales the spray. Used when a limb comes off (Ragdoll.dismember()).
static func blood(node: Node, at: Vector3, dir: Vector3, amount: float = 1.0) -> void:
	var parent := fx_parent(node)
	var drops := _ramp([Color(0.42, 0.02, 0.02, 1.0), Color(0.30, 0.01, 0.01, 0.95), Color(0.18, 0.0, 0.0, 0.0)])
	_puff_layer(parent, at, _count(int(28 * amount)), 0.07, 0.9, 2.5, 8.0, -18.0, drops, false,
		40.0, 1.3, _basis_up(dir), 0.0, 0.5)
	var mist := _ramp([Color(0.35, 0.02, 0.02, 0.0), Color(0.30, 0.02, 0.02, 0.35), Color(0.22, 0.01, 0.01, 0.0)])
	_puff_layer(parent, at, _count(int(6 * amount)), 0.45, 0.7, 0.6, 2.0, -1.0, mist, false,
		70.0, 2.0, _basis_up(dir))
	if _web():
		return
	var space := _space(node)
	if space == null:
		return
	var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * 4.0, 1)
	var hit := space.intersect_ray(down)
	if hit.is_empty():
		return
	var decal := Decal.new()
	decal.texture_albedo = puff_texture()
	decal.modulate = Color(0.22, 0.01, 0.01)
	decal.albedo_mix = 0.9
	var w := randf_range(1.0, 1.8) * amount
	decal.size = Vector3(w, 1.2, w)
	decal.upper_fade = 0.5
	decal.lower_fade = 0.5
	decal.normal_fade = 0.5
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 45.0
	decal.distance_fade_length = 15.0
	parent.add_child(decal)
	decal.global_position = (hit.position as Vector3) + dir.normalized() * randf_range(0.3, 1.2) * Vector3(1, 0, 1)
	decal.rotation.y = randf_range(0.0, TAU)
	_splats.append(decal)
	while _splats.size() > blood_splat_max:
		var old = _splats.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var t := decal.create_tween()
	t.tween_interval(30.0)
	t.tween_property(decal, "modulate:a", 0.0, 4.0)
	t.tween_callback(decal.queue_free)


static func explosion(node: Node, at: Vector3, radius: float, power: float = 1.0) -> void:
	var parent := fx_parent(node)
	var push := clampf(power, 0.5, 2.0)

	# 1. The flash. A real light is what makes an explosion feel like it happened in the world
	# instead of being painted on top of it: it lights the street, the cars and the people.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.36)
	light.light_energy = 14.0
	light.omni_range = radius * 4.0
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = at + Vector3.UP * radius * 0.3
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 6.0, 0.06)
	lt.tween_property(light, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_IN)
	lt.tween_callback(light.queue_free)

	# 2. White-hot core, very short.
	var core := _sphere(node, at, radius * 0.25, Color(2.6, 2.4, 2.0), 1.0)
	_additive(core)
	var ct := core.create_tween()
	ct.tween_property(core, "scale", Vector3.ONE * radius * 0.7, 0.10).set_ease(Tween.EASE_OUT)
	ct.parallel().tween_property(core.material_override, "albedo_color:a", 0.0, 0.14)
	ct.tween_callback(core.queue_free)

	# 3. Fireball: hot yellow through orange to a dark cooling edge, rising as it goes.
	# Puff sizes are a fraction of the radius, not a multiple: one puff is a piece of the
	# fireball, and sizing them in whole radii makes single quads swallow the camera.
	# Alpha-blended, not additive: burning fuel is opaque. Additive fire only adds brightness,
	# so in daylight it washes out to nothing against a sunlit street.
	# Slow and fat, not fast and small: a fireball is one rolling mass of overlapping puffs.
	# Throwing them outward at the blast speed just scatters them into separate dots.
	_puff_layer(parent, at, _count(38), radius * 0.52, 0.95, radius * 0.18, radius * 0.7, 2.5,
		# HDR on purpose, but only at the very start: a fireball's core is many times brighter
		# than a sunlit street, so the first instant blooms white. After that it has to drop
		# fast to a deep orange, because AgX takes anything bright toward white - held at 3.0
		# for its first third, the whole fireball tonemapped to a pale beige.
		_ramp([Color(5.0, 4.0, 2.6, 1.0), Color(2.4, 0.95, 0.20, 1.0), Color(1.1, 0.32, 0.06, 0.95),
			Color(0.35, 0.10, 0.03, 0.7), Color(0.08, 0.06, 0.05, 0.0)]), false, 180.0, 1.6,
		# Lifetimes spread and a wide per-puff tint, so at any instant some puffs are still
		# white-hot and some have already gone dark red: all the same age, forty overlapping
		# puffs were one flat orange cloud and the billows in the texture vanished.
		Basis(), 0.0, 0.45, 1.0, false,
		_ramp([Color(1.5, 1.35, 1.1), Color(1.0, 1.0, 1.0), Color(0.45, 0.33, 0.28)]))

	# 4. Smoke: slower, bigger, lingers and drifts up after the fire is gone.
	_puff_layer(parent, at + Vector3.UP * radius * 0.3, _count(26), radius * 0.62, 2.8,
		radius * 0.12, radius * 0.42, 1.4,
		# Sooty, and it only thickens once the fire is past its peak: smoke that is already
		# there at the fireball's biggest just greys it over.
		_ramp([Color(0.16, 0.14, 0.13, 0.0), Color(0.15, 0.13, 0.12, 0.06), Color(0.12, 0.11, 0.10, 0.72),
			Color(0.10, 0.09, 0.09, 0.42), Color(0.08, 0.08, 0.08, 0.0)]), false, 180.0, 2.6,
		Basis(), 0.0, 0.0, 1.0, true)

	# 5. Sparks: small, fast, thrown wide, falling under gravity.
	_puff_layer(parent, at, _count(34), radius * 0.038, 1.1, radius * 2.6 * push, radius * 4.4 * push,
		-26.0, _ramp([Color(2.4, 2.1, 1.3, 1.0), Color(1.8, 0.9, 0.25, 1.0), Color(0.8, 0.25, 0.05, 0.0)]),
		true, 180.0, 0.5)

	# 6. Embers. The blast is over in a third of a second; these are still drifting and dying
	# three seconds later, which is most of what makes the aftermath feel real. Slow, heavily
	# damped, with a long random spread of lifetimes so they do not all go out together.
	_puff_layer(parent, at + Vector3.UP * radius * 0.25, _count(20), radius * 0.028, ember_life,
		radius * 0.5, radius * 1.6, -3.0,
		_ramp([Color(2.2, 1.1, 0.3, 1.0), Color(1.4, 0.45, 0.08, 0.9), Color(0.5, 0.10, 0.02, 0.35),
			Color(0.2, 0.03, 0.0, 0.0)]), true, 180.0, 0.6, Basis(), 0.0, 0.55, 2.6)

	# 7. Ground shockwave: a thin ring racing outward and fading.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	# Faint and quick: bright and slow, it was a thin glowing line drawn across the whole street.
	var ring_mat := unshaded(Color(1.2, 0.92, 0.6), 0.42)
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = at + Vector3.UP * 0.25
	ring.scale = Vector3(radius * 0.25, radius * 0.06, radius * 0.25)
	var rt := ring.create_tween()
	rt.tween_property(ring, "scale", Vector3(radius * 1.3, radius * 0.05, radius * 1.3), 0.3).set_ease(Tween.EASE_OUT)
	rt.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.3).set_ease(Tween.EASE_OUT)
	rt.tween_callback(ring.queue_free)

	# 8. Debris: lit chunks, so they sit in the scene's lighting rather than glowing flat.
	_chip_layer(parent, at, _count(26), 0.18, 1.6, radius * 1.4 * push, radius * 3.0 * push,
		Color(0.29, 0.26, 0.24), Basis(), 170.0, -32.0)

	# 9. Dust off the ground and off whatever walls are close enough to be scoured.
	_blast_dust(node, parent, at, radius, push)

	# 10. Heat shimmer over the fireball. Reads the screen, so the web build skips it.
	if shimmer_enabled and not _web():
		_shimmer(parent, at + Vector3.UP * radius * 0.2, radius)

	# 11. Scorch mark on whatever is under the blast. Decals need a rendering device, so the
	# Compatibility renderer (the web build) quietly skips this.
	if RenderingServer.get_rendering_device() != null:
		var decal := Decal.new()
		decal.texture_albedo = puff_texture()
		decal.modulate = Color(0.05, 0.04, 0.035)
		decal.albedo_mix = 0.85
		decal.size = Vector3(radius * 1.8, 6.0, radius * 1.8)
		decal.upper_fade = 2.0
		decal.lower_fade = 2.0
		parent.add_child(decal)
		decal.global_position = at
		var dect := decal.create_tween()
		dect.tween_interval(14.0)
		dect.tween_property(decal, "modulate:a", 0.0, 4.0)
		dect.tween_callback(decal.queue_free)

	shake(node, at, radius)


## Dust the blast tears off the surfaces around it: a flat skirt racing out along the ground,
## and a puff on each wall close enough to be scoured. A fireball with nothing coming off the
## world around it always reads as a sprite hanging in the air.
static func _blast_dust(node: Node, parent: Node, at: Vector3, radius: float, push: float) -> void:
	var space := _space(node)
	if space == null:
		return
	# Street dust, not snow: at 0.6 unshaded the skirt glowed white against a dusk street.
	var dust_ramp := _ramp([Color(0.42, 0.38, 0.33, 0.0), Color(0.36, 0.33, 0.29, 0.58),
		Color(0.30, 0.28, 0.25, 0.32), Color(0.23, 0.22, 0.20, 0.0)])

	# Ground skirt. Only when there is actually ground within reach - an air burst has none.
	var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * radius * 0.4,
		at - Vector3.UP * radius * 1.4, 1)
	var floor_hit := space.intersect_ray(down)
	if not floor_hit.is_empty():
		var ground: Vector3 = floor_hit.position
		# `flatness` 1.0 squashes the emission cone into the plane across the axis, so a
		# 180 degree spread aimed up becomes a flat ring running out along the ground.
		_puff_layer(parent, ground + Vector3.UP * 0.15, _count(22), radius * 0.45, 1.9,
			radius * 1.1 * push, radius * 2.2 * push, 1.2, dust_ramp, false, 180.0, 3.0,
			_basis_up(floor_hit.normal), 1.0, 0.35, 1.6, true)

	if _web():
		return

	# Walls. A handful of rays out from the seat of the blast; every one that lands close
	# enough gets a puff sliding down the surface it hit.
	var rays := maxi(3, dust_rays)
	var made := 0
	var start := randf_range(0.0, TAU)
	for i in rays:
		if made >= dust_puffs_max:
			break
		var ang := start + TAU * float(i) / float(rays)
		var dir := Vector3(cos(ang), randf_range(-0.1, 0.35), sin(ang)).normalized()
		var q := PhysicsRayQueryParameters3D.create(at, at + dir * radius * 1.25, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit.normal
		if absf(n.y) > 0.8:
			continue # floors and ceilings are already covered by the skirt
		made += 1
		var spot: Vector3 = hit.position
		_puff_layer(parent, spot + n * 0.1, _count(8), radius * 0.3, 1.4,
			radius * 0.3, radius * 0.9, -1.6, dust_ramp, false, 70.0, 2.6, _basis_up(n), 0.0, 0.4, 1.0, true)


static var _shimmer_shader: Shader


## Heat haze over the fire. A sphere that bends whatever is behind it with a slow noise, fading
## as the fireball cools. The shader reads the screen texture, which is why the web build skips
## it: on Compatibility that is a full back-buffer copy every draw.
static func _shimmer(parent: Node, at: Vector3, radius: float) -> void:
	if _shimmer_shader == null:
		var sh := Shader.new()
		# Shader code uses // comments. A # line here is a syntax error and Godot falls back to
		# a blank white material, which looks like a missing texture, not a broken shader.
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength = 0.05;
uniform float fade = 1.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Fade out at the silhouette so the sphere has no visible edge, only a soft column of heat.
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float mask = smoothstep(0.0, 0.55, facing);
	float t = TIME * 2.4;
	vec3 p = v_world * 1.7;
	vec2 wob = vec2(
		sin(p.y * 3.1 + t * 2.6) + 0.5 * sin(p.y * 7.7 - t * 1.6 + p.x),
		cos(p.x * 2.7 - t * 2.1) + 0.5 * sin(p.z * 6.3 + t * 1.9));
	vec2 off = wob * strength * 0.02 * mask * fade;
	vec3 col = texture(screen_tex, clamp(SCREEN_UV + off, vec2(0.002), vec2(0.998))).rgb;
	ALBEDO = col * vec3(1.04, 1.0, 0.95);
	ALPHA = mask * fade;
}
"""
		_shimmer_shader = sh
	var mat := ShaderMaterial.new()
	mat.shader = _shimmer_shader
	mat.set_shader_parameter("strength", shimmer_strength)
	mat.set_shader_parameter("fade", 1.0)
	# Drawn FIRST among the transparent things. The screen texture it reads is captured before
	# any of them are drawn, so drawn in its sorted place - in front of the fireball it sits in -
	# it painted the street as it looked without the fire straight over the fireball and the
	# smoke, and every explosion in the game was sparks and a ring around nothing. Drawn first,
	# it bends the street behind the blast and the fire goes on top, which is what heat does.
	mat.render_priority = Material.RENDER_PRIORITY_MIN
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh.mesh = sphere
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_position = at
	mesh.scale = Vector3(radius * 1.2, radius * 1.1, radius * 1.2)
	var t := mesh.create_tween()
	t.tween_property(mesh, "scale", Vector3(radius * 2.4, radius * 3.0, radius * 2.4), 1.5)
	t.parallel().tween_property(mesh, "global_position", at + Vector3.UP * radius * 0.8, 1.5)
	t.parallel().tween_property(mat, "shader_parameter/fade", 0.0, 1.5).set_ease(Tween.EASE_IN)
	t.tween_callback(mesh.queue_free)


## Rattles the player's camera, hard up close and not at all far away.
static func shake(node: Node, at: Vector3, radius: float) -> void:
	var player := node.get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var rig: Node = player.get("camera_rig")
	if rig == null or not rig.has_method("shake"):
		return
	var d := player.global_position.distance_to(at)
	var falloff := clampf(1.0 - d / (radius * 6.0), 0.0, 1.0)
	if falloff > 0.0:
		rig.shake(falloff * falloff)


## Makes a mesh glow additively. Transparency has to be switched on with it: an additive
## material left opaque ignores the alpha, so every fade-out tween silently does nothing.
static func _additive(mesh: MeshInstance3D) -> void:
	var mat := mesh.material_override as StandardMaterial3D
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


static func _sphere(node: Node, at: Vector3, size: float, color: Color, alpha: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	mesh.mesh = sphere
	mesh.material_override = unshaded(color, alpha)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_parent(node).add_child(mesh)
	mesh.global_position = at
	mesh.scale = Vector3.ONE * size
	return mesh
