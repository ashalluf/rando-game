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

# Blood (owner, 2026-09-24: "I want more blood when people get shot"). Everything a wound leaves
# behind is capped here and fades on its own clock; see blood() for what one wound is made of.

## Most ground splats (landed droplets, drag smears) at once; the oldest goes when a new one
## would pass it.
static var blood_splat_max: int = 48
## Seconds a ground splat stays before it fades out.
static var blood_splat_life: float = 40.0
## Most wall splatters at once (a spatter and the runs down the wall under it count as one).
static var blood_wall_max: int = 12
## Seconds a wall splatter stays before it fades out.
static var blood_wall_life: float = 45.0
## Most pools under bodies at once.
static var blood_pool_max: int = 8
## Seconds a pool stays before it fades out. Longer than the body, which is debris.
static var blood_pool_life: float = 40.0
## Seconds a pool takes to spread to its full width, fast at first and slowing as it thins.
static var blood_pool_grow: float = 8.0
## Width of the pool under someone shot once (metres); more wounds widen it, up to twice this.
static var blood_pool_size: float = 1.35
## Most blood particle systems alive at once. Past it a new spray is skipped entirely.
static var blood_system_max: int = 40
## Detailed wounds (rays, splats, wall splatter) allowed in any 0.7 s; past it a hit only sprays.
static var blood_budget: int = 8
## Beyond this distance a wound only sprays: no rays, no splats, no wall.
static var blood_detail_distance: float = 70.0
## Beyond this distance a wound draws nothing at all.
static var blood_far_distance: float = 150.0
## Droplets thrown out of the exit wound by a rifle round (strength 1).
static var blood_drops: int = 44
## Speed range of the exit spray's droplets (m/s).
static var blood_exit_speed: Vector2 = Vector2(2.8, 8.0)
## Half-angle of the exit spray's cone round the bullet's line (degrees).
static var blood_exit_cone: float = 20.0
## How far through the body the exit wound is, along the bullet (metres).
static var blood_exit_depth: float = 0.28
## How far behind the victim a wall still gets painted (metres along the bullet).
static var blood_wall_reach: float = 2.8
## Droplets per rifle wound whose flight is traced to where they come down; each lands as a
## splat there, at the moment it lands.
static var blood_landings: int = 5
## Strongest single wound. A shotgun volley's pellets summed into one call stop here.
static var blood_strength_max: float = 4.0
## Gravity on the droplets (m/s^2). The landing trace uses the same number, which is what puts
## the splats where the drops are seen to come down.
static var blood_gravity: float = 11.0
## Seconds a wound keeps dripping from a body, a stump or a torn-off limb.
static var blood_drip_seconds: float = 2.4
## Metres a sliding body travels between two smears of its trail.
static var blood_trail_step: float = 0.45
## Most trail smears one body (or limb) leaves.
static var blood_trail_max: int = 14
## How hard a limb torn off by a blast bleeds, against a rifle round's 1.
static var blood_gib_strength: float = 2.2


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
static var _mat_fire: Material


## The fireball's puffs: hot in their dense cores and sooty at their thin edges, and soft where
## they meet the road (shaders/fire_puff.gdshader). It reads the depth buffer, so the web keeps
## the plain puff material.
static func _fire_material() -> Material:
	if _web():
		return _puff_material(false)
	if _mat_fire == null:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/fire_puff.gdshader")
		mat.set_shader_parameter("puff_tex", puff_texture())
		_mat_fire = mat
	return _mat_fire


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
		variety: Gradient = null, material: Material = null) -> CPUParticles3D:
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
	quad.material = material if material else _puff_material(additive, behind)
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
	# A lopsided wedge rather than a box: spinning, a cube reads as a cube however small it is,
	# and rubble is never square.
	var box := PrismMesh.new()
	box.size = Vector3(chip_size, chip_size * 0.55, chip_size * 0.8)
	box.left_to_right = 0.25
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
## The particle materials every blast and wound draws with, for the loading screen to compile
## ahead of time (see LoadingScreen._warm_shaders()).
static func warm_materials() -> Array:
	# The blood marks' textures are generated here too (a few tens of milliseconds for all five
	# kinds), so the first wound does not pay for them.
	for kind in [_KIND_DROP, _KIND_SPATTER, _KIND_POOL, _KIND_SMEAR, _KIND_DRIP]:
		blood_textures(kind)
	return [_puff_material(false), _puff_material(true), _puff_material(false, true), _fire_material(),
		_blood_drop_material(), _blood_mist_material()]


## One tiny blood decal of every kind, for the loading screen to hold in front of the camera for a
## few frames: the first decal to use a texture repacks the decal atlas, and the first wound
## should not be the one that does it. Empty on the Compatibility renderer, which has no decals
## (its quads' materials are in warm_mesh_materials()).
static func warm_decals() -> Array:
	var out: Array = []
	if not _decals():
		return out
	for kind in [_KIND_DROP, _KIND_SPATTER, _KIND_POOL, _KIND_SMEAR, _KIND_DRIP]:
		var tex := blood_textures(kind)
		var dec := Decal.new()
		dec.texture_albedo = tex[0]
		dec.texture_normal = tex[1]
		dec.texture_orm = tex[2]
		dec.size = Vector3(0.02, 0.02, 0.02)
		out.append(dec)
	return out


## The same for what draws through plain meshes: the additive billboard flare of a muzzle flash
## and a tracer head, and the additive glow of a tracer beam, a blast core and its ring. The
## first rifle shot compiled these.
static func warm_mesh_materials() -> Array:
	var flare := unshaded(Color(2.0, 1.6, 1.0), 0.9)
	flare.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flare.albedo_texture = flare_texture()
	flare.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flare.billboard_keep_scale = true
	var glow := unshaded(Color(2.0, 1.6, 1.0), 0.9)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var out: Array = [flare, glow]
	# Blood marks are flat quads where there are no decals; one material covers every kind.
	if not _decals():
		out.append(_splat_material(_KIND_DROP))
	return out


# ---------------------------------------------------------------------------------------------
# Blood
# ---------------------------------------------------------------------------------------------

## Fresh blood (sRGB): a deep arterial red, and the near-black red it thickens and dries to. Not
## the pinkish red of paint: real blood is dark, and only a thin film or a lit droplet shows red.
const BLOOD_FRESH := Color(0.42, 0.03, 0.022)
const BLOOD_DARK := Color(0.19, 0.013, 0.01)
## What blood lands on and splatters: the world and the props (cars, crates), not the npc layer.
const BLOOD_MASK := 1 | 4
## The render layer a shot body's own meshes move to (Ragdoll), which blood decals leave out: a
## pool's projection box is half a metre deep and painted the whole top of the body lying in it
## red. The body's blood is its stain (character.gdshader); the decals are for the world.
const NO_BLOOD_LAYER := 1 << 19

## The kinds of mark blood leaves; each has its own generated texture set.
const _KIND_DROP := 0
const _KIND_SPATTER := 1
const _KIND_POOL := 2
const _KIND_SMEAR := 3
const _KIND_DRIP := 4

static var _splats: Array = []
static var _walls: Array = []
static var _pools: Array = []
static var _blood_systems: Array = []
static var _blood_times: Array[float] = []
static var _decal_cache: int = -1
## Running totals since start (for the smoke test and screenshot logs): wounds sprayed, exit
## sprays thrown, splats, wall splatters and pools laid. Live counts are blood_counts().
static var blood_stats := {"wounds": 0, "exit_sprays": 0, "splats": 0, "walls": 0, "pools": 0}


## A gunshot wound (owner, 2026-09-24: "I want more blood when people get shot"). `at` is where
## the round went in and `dir` the way it was going. A little backspatter out of the entry; a
## heavier spray out of the far side, along the bullet, of droplets that fall under gravity and
## leave splats where they come down (a few of them are traced through the air to find where); a
## red mist; and a spatter with runs under it on any wall close behind. `strength` scales all of
## it: 1 is a rifle round, a blast's torn-off limb is `blood_gib_strength`, and a shotgun either
## calls this per pellet (the sprays stack, the caps hold) or once per person with its pellets
## summed, up to `blood_strength_max`. `victim` - the body it came out of - is left out of every
## ray, so the blood does not land on the person it came from.
static func blood(node: Node, at: Vector3, dir: Vector3, strength: float = 1.0, victim: Node = null) -> void:
	_bleed(node, at, dir, strength, victim, true)


## Blood out of an open wound along `dir`, with no entry: a stump where a limb came off.
static func blood_gush(node: Node, at: Vector3, dir: Vector3, strength: float = 1.0, victim: Node = null) -> void:
	_bleed(node, at, dir, strength, victim, false)


## A bullet into flesh, for any gun: hand it the ray hit. A pedestrian bleeds and goes down
## (Pedestrian.shot; `knock` is the shove), a body already down bleeds again where it was hit
## (Ragdoll.shot), a torn-off limb bleeds. Returns false when it was not flesh, so the gun goes on
## to shove or break whatever it was. `strength` as for blood(). Duck-typed, like classify(), so
## this file never names the NPC classes.
static func bullet_wound(node: Node, hit: Dictionary, dir: Vector3, strength: float = 1.0,
		knock: Vector3 = Vector3.ZERO) -> bool:
	var who := hit.get("collider") as Node
	if who == null:
		return false
	var at: Vector3 = hit.get("position", Vector3.ZERO)
	if who.has_method("shot"):
		who.shot(at, dir, knock, strength)
		return true
	var holder := who.get_parent()
	if holder != null and holder.has_method("shot") and holder.has_method("fling"):
		holder.shot(at, dir, Vector3.ZERO, strength)
		return true
	if who.is_in_group("gib"):
		blood_gush(node, at, dir, strength * 0.6, who)
		return true
	if who.has_method("knock"):
		who.knock(knock)
		return true
	return false


## Live counts of what blood is in the world right now: particle systems, ground splats, wall
## splatters and pools. Each stays under its cap.
static func blood_counts() -> Dictionary:
	for list: Array in [_splats, _walls, _pools, _blood_systems]:
		_prune(list)
	return {"systems": _blood_systems.size(), "splats": _splats.size(), "walls": _walls.size(), "pools": _pools.size()}


static func _bleed(node: Node, at: Vector3, dir: Vector3, strength: float, victim: Node, entry: bool) -> void:
	if node == null or not node.is_inside_tree():
		return
	var d := dir.normalized() if not dir.is_zero_approx() else Vector3.UP
	var s := clampf(strength, 0.1, blood_strength_max)
	var dist := _view_distance(node, at)
	if dist > blood_far_distance:
		return
	blood_stats["wounds"] += 1
	var parent := fx_parent(node)
	var exit_at := at + d * (blood_exit_depth if entry else 0.0)
	var grow := sqrt(s)
	# Particles. Hard-capped as a whole: a crowd emptied into at close range is exactly when the
	# frame can least afford a hundred sprays. A wound is up to five systems.
	if _blood_room(5 if entry else 3):
		var cone := blood_exit_cone * (0.9 + 0.1 * s)
		if entry:
			# Backspatter: a few fine drops and a puff thrown back out of the entry, at the shooter.
			_track(_drop_layer(parent, at, _count(int(8 * grow)), 0.55, Vector2(0.8, 2.6), _basis_up(-d), 38.0, 0.6))
			_track(_mist_layer(parent, at, _count(2), 0.16, 0.45, _basis_up(-d), 50.0, 0.6))
		# The exit spray: most of the blood, along the bullet, thrown hard and falling fast - a
		# tight jet of the fastest drops down the bullet's line inside a wider, slower spray. One
		# even cone read as a handful of separate beads; the jet is what reads as blood leaving.
		var drops := clampi(int(float(blood_drops) * (0.6 + 0.4 * s)), 8, 140)
		var speed := blood_exit_speed * (0.9 + 0.1 * s)
		_track(_drop_layer(parent, exit_at, _count(int(drops * 0.6)), 0.85, speed, _basis_up(d), cone, 1.0 + 0.1 * s))
		_track(_drop_layer(parent, exit_at, _count(int(drops * 0.4)), 0.7, Vector2(speed.y * 0.7, speed.y * 1.15),
			_basis_up(d), cone * 0.35, 0.8 + 0.1 * s))
		_track(_mist_layer(parent, exit_at, _count(int(4 + 2 * s)), 0.34 + 0.08 * s, 0.9, _basis_up(d), cone * 2.0, 1.0))
		blood_stats["exit_sprays"] += 1
	if dist > blood_detail_distance or not _blood_budget_ok():
		return
	var space := _space(node)
	if space == null:
		return
	var exclude := _victim_rids(victim)
	_wall_splatter(parent, space, exit_at, d, s, exclude)
	_land_drops(parent, space, exit_at, d, clampi(int(round(float(blood_landings) * (0.7 + 0.3 * s))), 2, 12), s, exclude)


## Counts the detailed wounds started in the last moment, like impact() does, rather than keep a
## live counter through tween callbacks.
static func _blood_budget_ok() -> bool:
	var now := Time.get_ticks_msec() * 0.001
	while not _blood_times.is_empty() and now - _blood_times[0] > 0.7:
		_blood_times.pop_front()
	if _blood_times.size() >= blood_budget:
		return false
	_blood_times.append(now)
	return true


static func _blood_room(need: int = 1) -> bool:
	_prune(_blood_systems)
	return _blood_systems.size() + need <= blood_system_max


static func _track(p: Node) -> void:
	if p != null:
		_blood_systems.append(p)


## Drops freed nodes from one of the capped lists, in place.
static func _prune(list: Array) -> void:
	for i in range(list.size() - 1, -1, -1):
		if not is_instance_valid(list[i]) or (list[i] as Node).is_queued_for_deletion():
			list.remove_at(i)


## Frees the oldest marks of one list until it is back under its cap. Halved on the web, where
## every mark is its own transparent quad rather than a decal in the clustered pass.
static func _trim(list: Array, cap: int) -> void:
	_prune(list)
	var limit := maxi(int(cap * 0.5) if _web() else cap, 0)
	while list.size() > limit:
		var old: Object = list.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()


## The physics bodies of the person blood came out of - a pedestrian's capsule, a ragdoll's
## pieces, a limb - for the rays to skip.
static func _victim_rids(victim: Node) -> Array[RID]:
	var out: Array[RID] = []
	if victim == null or not is_instance_valid(victim):
		return out
	if victim is CollisionObject3D:
		out.append((victim as CollisionObject3D).get_rid())
	for c in victim.find_children("*", "CollisionObject3D", true, false):
		out.append((c as CollisionObject3D).get_rid())
	return out


## Decals need Forward+ or Mobile. The Compatibility renderer - the web build, and the opengl3
## screenshot path - lays flat alpha quads with the same textures instead.
static func _decals() -> bool:
	if _decal_cache < 0:
		_decal_cache = 0 if _web() or RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1
	return _decal_cache == 1


## A direction inside a cone of half-angle `deg` round `axis`, spread evenly over the cone's area.
static func _cone(axis: Vector3, deg: float) -> Vector3:
	var b := _basis_up(axis)
	var cos_max := cos(deg_to_rad(deg))
	var z := lerpf(cos_max, 1.0, randf())
	var r := sqrt(maxf(0.0, 1.0 - z * z))
	var phi := randf() * TAU
	return (b * Vector3(r * cos(phi), z, r * sin(phi))).normalized()


# --- Blood particles --------------------------------------------------------------------------

static var _mat_drop: StandardMaterial3D
static var _mat_mist: Material
static var _drop_mesh: SphereMesh


## Lit, glossy and opaque: a droplet is a bead of liquid that catches the light, not a glowing
## dot, and at night it is as dark as everything else. Opaque, so a spray needs no sorting; it
## shrinks away at the end of its life instead of fading.
static func _blood_drop_material() -> StandardMaterial3D:
	if _mat_drop == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = BLOOD_FRESH
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.12
		m.metallic_specular = 0.7
		# Blood is translucent: a drop with the sun behind it glows red instead of going black.
		m.backlight_enabled = true
		m.backlight = Color(0.45, 0.03, 0.02)
		_mat_drop = m
	return _mat_drop


static func _blood_drop_mesh() -> SphereMesh:
	if _drop_mesh == null:
		var s := SphereMesh.new()
		# Four times as long as it is wide, and every particle's Y follows its velocity, so a drop
		# in flight is a streak that reads from any side instead of a dot.
		s.radius = 0.02
		s.height = 0.085
		s.radial_segments = 6
		s.rings = 3
		s.material = _blood_drop_material()
		_drop_mesh = s
	return _drop_mesh


## The red mist's puffs: unshaded, darkened by the time of day (shaders/blood_mist.gdshader). A
## lit billboard came out as grey-brown dust - a camera-facing card catches almost no sun.
static func _blood_mist_material() -> Material:
	if _mat_mist == null:
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/blood_mist.gdshader")
		m.set_shader_parameter("puff_tex", puff_texture())
		_mat_mist = m
	return _mat_mist


## A burst of droplets thrown along `aim`'s +Y within a cone of `spread` degrees. No damping, so
## each follows the same arc the landing trace in _land_drops() computes.
static func _drop_layer(parent: Node, at: Vector3, count: int, life: float, speed: Vector2,
		aim: Basis, spread: float, size: float = 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "BloodDrops"
	p.add_to_group("blood")
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, count)
	p.lifetime = life
	p.lifetime_randomness = 0.35
	# Out of a wound, not a point: a few centimetres of torn cloth and skin.
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.035
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0.0, -blood_gravity, 0.0)
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.45 * size
	p.scale_amount_max = 1.5 * size
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.7, 0.85))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	# Some drops darker than others: thin ones catch the light red, thick ones stay near black.
	p.color_initial_ramp = _ramp([Color(1.15, 1.1, 1.1), Color(0.8, 0.8, 0.8), Color(0.45, 0.45, 0.45)])
	p.mesh = _blood_drop_mesh()
	parent.add_child(p)
	p.global_transform = Transform3D(aim, at)
	var span := life * 1.35
	var reach := speed.y * span + blood_gravity * span * span + 1.0
	p.custom_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * (reach * 2.0))
	p.restart()
	p.emitting = true
	var tween := p.create_tween()
	tween.tween_interval(span + 0.2)
	tween.tween_callback(p.queue_free)
	return p


static func _mist_layer(parent: Node, at: Vector3, count: int, size: float, life: float,
		aim: Basis, spread: float, alpha: float) -> CPUParticles3D:
	var p := _puff_layer(parent, at, count, size, life, 0.4, 1.8, -1.2,
		_ramp([Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 0.5 * alpha), Color(0.75, 0.75, 0.75, 0.24 * alpha),
			Color(0.6, 0.6, 0.6, 0.0)]), false, spread, 2.4, aim, 0.0, 0.3, 1.0, false, null,
		_blood_mist_material())
	p.name = "BloodMist"
	p.add_to_group("blood")
	return p


## Drops falling off a wound for `seconds` - a body's exit wound, a stump, the end of a torn-off
## limb - left behind in the world as `host` moves, so a tumbling limb or a sliding body draws a
## trail through the air. `local_at` is the wound in the host's own space. `rate` scales how many.
## Returns null when the particle cap is full.
static func blood_drip(host: Node3D, local_at: Vector3, seconds: float, rate: float = 1.0) -> CPUParticles3D:
	# Drips last seconds, sprays under one: leave room under the cap for the next wounds' sprays.
	if host == null or not host.is_inside_tree() or not _blood_room(8):
		return null
	if _view_distance(host, host.global_position) > blood_detail_distance:
		return null
	var p := CPUParticles3D.new()
	p.name = "BloodDrip"
	p.add_to_group("blood")
	p.local_coords = false
	p.amount = maxi(4, int(16.0 * rate))
	p.lifetime = 0.8
	p.direction = Vector3.DOWN
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0.0, -blood_gravity, 0.0)
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = curve
	p.color_initial_ramp = _ramp([Color(1.0, 1.0, 1.0), Color(0.55, 0.55, 0.55)])
	p.mesh = _blood_drop_mesh()
	# The drops live in the world while the emitter rides the host, so the bounds have to cover
	# wherever the host tumbles to in that time as well as the fall.
	p.custom_aabb = AABB(Vector3.ONE * -12.0, Vector3.ONE * 24.0)
	host.add_child(p)
	p.position = local_at
	p.emitting = true
	var tween := p.create_tween()
	tween.tween_interval(maxf(seconds, 0.1))
	tween.tween_callback(p.set.bind("emitting", false))
	tween.tween_interval(p.lifetime + 0.2)
	tween.tween_callback(p.queue_free)
	_track(p)
	return p


# --- Blood on the world -----------------------------------------------------------------------

## Traces `n` droplets of an exit spray from `from` through the air to wherever they come down
## and lays a splat there, shown at the moment it lands. A few short rays along each arc. The
## first is the heavy drop that runs straight out of the wound onto the ground under it, so a
## wound always marks the ground beneath it as well as where the spray carried.
static func _land_drops(parent: Node, space: PhysicsDirectSpaceState3D, from: Vector3, d: Vector3,
		n: int, strength: float, exclude: Array[RID]) -> void:
	var step := 0.07
	for i in n:
		var v: Vector3
		var size: float
		# Sizes are the mark's square; the splash itself is about two fifths of it, the rest is
		# its crown and the satellite drops. At half these, a still at ten metres showed specks.
		if i == 0:
			v = d * randf_range(0.2, 0.9) + Vector3(randf_range(-0.25, 0.25), -0.5, randf_range(-0.25, 0.25))
			size = randf_range(0.75, 1.05) * (0.8 + 0.2 * strength)
		else:
			v = _cone(d, blood_exit_cone * (0.9 + 0.1 * strength)) * randf_range(blood_exit_speed.x, blood_exit_speed.y)
			size = randf_range(0.26, 0.55) * (0.9 + 0.1 * strength)
		var p := from
		var t := 0.0
		while t < 1.4:
			var nv := v + Vector3.DOWN * blood_gravity * step
			var np := p + (v + nv) * 0.5 * step
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, np, BLOOD_MASK, exclude))
			if not hit.is_empty():
				var frac := ((hit.position as Vector3) - p).length() / maxf((np - p).length(), 0.0001)
				_drop_splat(parent, hit, v.lerp(nv, frac), size, t + step * frac)
				break
			p = np
			v = nv
			t += step


## Where a drop came down: a splat on the ground stretched along the way it was going (a drop
## landing at a slant smears), or a smaller spatter where it met a wall.
static func _drop_splat(parent: Node, hit: Dictionary, vel: Vector3, size: float, delay: float) -> void:
	var n: Vector3 = hit.normal
	var host := _host_for(hit.get("collider"), parent)
	var slide := vel - n * vel.dot(n)
	var slant := clampf(slide.length() / maxf(absf(vel.dot(n)), 0.5), 0.0, 1.6)
	var along := slide.normalized() if slide.length() > 0.05 else _any_tangent(n)
	var basis := _basis_on(n, along)
	var wall := absf(n.y) < 0.5
	var sz := Vector3(size * (1.0 + 0.45 * slant), 0.4, size) * (0.7 if wall else 1.0)
	var splat := _splat(host, _KIND_DROP, Transform3D(basis, (hit.position as Vector3) + n * 0.015), sz,
		blood_splat_life, delay, true)
	if splat:
		_splats.append(splat)
		_trim(_splats, blood_splat_max)
		blood_stats["splats"] += 1


## The spray that reaches a wall close behind the victim: a spatter flung out along the bullet's
## line across the wall, and runs of blood creeping down the wall under it. One ray.
static func _wall_splatter(parent: Node, space: PhysicsDirectSpaceState3D, from: Vector3, d: Vector3,
		strength: float, exclude: Array[RID]) -> void:
	var reach := blood_wall_reach * (0.85 + 0.15 * strength)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + d * reach, BLOOD_MASK, exclude))
	if hit.is_empty():
		return
	var n: Vector3 = hit.normal
	if absf(n.y) > 0.7:
		return # a floor: the landings paint those
	var at: Vector3 = hit.position
	var gone := at.distance_to(from)
	# The spray widens the further it flew; a heavier wound throws more of it.
	var w := (0.42 + 0.32 * gone) * (0.8 + 0.2 * sqrt(strength))
	var along := d - n * d.dot(n)
	if along.length() < 0.2:
		along = Vector3.DOWN - n * n.dot(Vector3.DOWN) # square on: it runs down
	if along.length() < 0.05:
		along = _any_tangent(n)
	along = along.normalized()
	var host := _host_for(hit.get("collider"), parent)
	var delay := gone / maxf((blood_exit_speed.x + blood_exit_speed.y) * 0.5, 0.1)
	var size := Vector3(w * 0.85, 0.5, w * 1.35)
	# The texture's dense core sits a fifth of the way along it; put that on the impact.
	var spat := _splat(host, _KIND_SPATTER, Transform3D(_basis_on(n, along, true), at + along * size.z * 0.3 + n * 0.02),
		size, blood_wall_life, delay, true)
	if spat == null:
		return
	_walls.append(spat)
	_trim(_walls, blood_wall_max)
	blood_stats["walls"] += 1
	# Runs: what hit the wall creeps down it for a few seconds. A child of the spatter, so the
	# cap that removes a spatter takes its runs with it.
	var down := Vector3.DOWN - n * n.dot(Vector3.DOWN)
	if down.length() < 0.5:
		return
	down = down.normalized()
	var top := at - down * w * 0.05 + n * 0.021
	var run_len := w * randf_range(0.9, 1.9) * (0.8 + 0.2 * strength)
	var run := _splat(spat, _KIND_DRIP, Transform3D(_basis_on(n, down, true), top + down * w * 0.06),
		Vector3(w * 0.75, 0.5, w * 0.12), blood_wall_life, delay, false)
	if run == null:
		return
	var width := w * 0.75
	var start := w * 0.12
	var creep := func(k: float) -> void:
		var run_now := lerpf(start, run_len, k)
		_set_extent(run, Vector3(width, 0.5, run_now))
		run.global_position = top + down * run_now * 0.5
	var t := run.create_tween()
	t.tween_interval(delay + 0.15)
	t.tween_method(creep, 0.0, 1.0, randf_range(4.0, 7.0)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


## A pool of blood spreading on the ground at `at` (`normal` is the ground's up) under a body
## (Ragdoll) to `blood_pool_size`, wider the worse the wounds (`strength`, their sum), over
## `blood_pool_grow` seconds. Returns the node, which feed_pool() widens if the body is shot again.
static func blood_pool(node: Node, at: Vector3, normal: Vector3, strength: float = 1.0) -> Node3D:
	if node == null or not node.is_inside_tree():
		return null
	var parent := fx_parent(node)
	var basis := _basis_up(normal, randf_range(-PI, PI))
	var pool := _splat(parent, _KIND_POOL, Transform3D(basis, at + normal * 0.018), Vector3(0.22, 0.5, 0.22),
		blood_pool_life, 0.0, false)
	if pool == null:
		return null
	pool.set_meta("aspect", randf_range(0.8, 1.2))
	_pools.append(pool)
	_trim(_pools, blood_pool_max)
	blood_stats["pools"] += 1
	feed_pool(pool, strength)
	return pool


## Retargets a pool to the width `strength` (the body's wounds, summed) calls for, spreading
## there from wherever it has got to.
static func feed_pool(pool: Node3D, strength: float) -> void:
	if pool == null or not is_instance_valid(pool) or not pool.is_inside_tree():
		return
	var target := blood_pool_size * clampf(0.75 + 0.25 * strength, 0.75, 2.0)
	var aspect: float = pool.get_meta("aspect", 1.0)
	if pool.has_meta("grow"):
		var old := pool.get_meta("grow") as Tween
		if old != null and old.is_valid():
			old.kill()
	var from := _extent(pool)
	var to := Vector3(target * aspect, from.y, target)
	var t := pool.create_tween()
	t.tween_method(func(k: float) -> void: _set_extent(pool, from.lerp(to, k)), 0.0, 1.0,
		blood_pool_grow).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	pool.set_meta("grow", t)


## A smear dragged along `along` on the ground at `at`: a body sliding, a limb skidding.
static func blood_smear(node: Node, at: Vector3, normal: Vector3, along: Vector3, length: float, width: float) -> Node3D:
	if node == null or not node.is_inside_tree():
		return null
	var dir := along - normal * along.dot(normal)
	if dir.length() < 0.01:
		dir = _any_tangent(normal)
	var smear := _splat(fx_parent(node), _KIND_SMEAR, Transform3D(_basis_on(normal, dir.normalized()), at + normal * 0.016),
		Vector3(maxf(length, 0.2), 0.4, width), blood_splat_life, 0.0, false)
	if smear:
		_splats.append(smear)
		_trim(_splats, blood_splat_max)
		blood_stats["splats"] += 1
	return smear


## A drop landing where `at` meets the ground under it (a limb hitting the road). Null if there
## is no ground within reach.
static func blood_splat_below(node: Node, at: Vector3, size: float, exclude: Array[RID] = []) -> Node3D:
	var space := _space(node)
	if space == null:
		return null
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.2, at + Vector3.DOWN * 1.5, 1, exclude))
	if hit.is_empty():
		return null
	var n: Vector3 = hit.normal
	var splat := _splat(fx_parent(node), _KIND_DROP, Transform3D(_basis_up(n, randf_range(-PI, PI)), (hit.position as Vector3) + n * 0.015),
		Vector3(size, 0.4, size), blood_splat_life, 0.0, true)
	if splat:
		_splats.append(splat)
		_trim(_splats, blood_splat_max)
		blood_stats["splats"] += 1
	return splat


## Moving things carry their splatter (a car door drives off with it); everything else hangs off
## the scene root, which the streamer shifts with the world and which outlives chunk swaps.
static func _host_for(collider: Variant, fallback: Node) -> Node:
	var body := collider as PhysicsBody3D
	if body != null and body.is_inside_tree() and not (body is StaticBody3D):
		return body
	return fallback


## A basis standing on `normal` (local +Y, the way a decal projects down its -Y) with its local
## +X along `along`, or its +Z when `along_z` - the texture's U or V, respectively.
static func _basis_on(normal: Vector3, along: Vector3, along_z: bool = false) -> Basis:
	var y := normal.normalized()
	var a := (along - y * along.dot(y))
	if a.length() < 0.001:
		a = _any_tangent(y)
	a = a.normalized()
	if along_z:
		var x := y.cross(a).normalized()
		return Basis(x, y, x.cross(y).normalized())
	var z := a.cross(y).normalized()
	return Basis(a, y, z)


static func _any_tangent(n: Vector3) -> Vector3:
	var side := Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD
	return (side - n * side.dot(n)).normalized()


static var _splat_mats: Dictionary = {}


## The flat-quad version of a mark for the Compatibility renderer: the same three maps on a lit,
## alpha-blended material, roughness from the ORM map's green channel.
static func _splat_material(kind: int) -> StandardMaterial3D:
	if _splat_mats.has(kind):
		return _splat_mats[kind]
	var tex := blood_textures(kind)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex[0]
	m.normal_enabled = true
	m.normal_texture = tex[1]
	m.roughness = 1.0
	m.roughness_texture = tex[2]
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	# A dark wet film, but not a mirror for the sky: the quad path has no screen-space
	# reflections to put the street in it, only the sky.
	m.metallic_specular = 0.3
	# Seen at a grazing angle from across the street; plain mipmapping blurs a splat to nothing.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_splat_mats[kind] = m
	return m


## One mark: a Decal on Forward+ (it wraps kerbs and follows the surface), a flat alpha quad on
## the Compatibility renderer. Hidden until `delay` has passed (a drop lands when it lands), with
## a quick spread on arrival when `pop`, then held `life` seconds and faded out.
static func _splat(host: Node, kind: int, xf: Transform3D, size: Vector3, life: float, delay: float, pop: bool) -> Node3D:
	if host == null or not host.is_inside_tree():
		return null
	var tex := blood_textures(kind)
	var n: Node3D
	if _decals():
		var dec := Decal.new()
		dec.texture_albedo = tex[0]
		dec.texture_normal = tex[1]
		dec.texture_orm = tex[2]
		dec.albedo_mix = 1.0
		# Without a normal fade the projection smears down any kerb or wall it grazes.
		dec.normal_fade = 0.3
		dec.upper_fade = 0.3
		dec.lower_fade = 0.3
		dec.distance_fade_enabled = true
		dec.distance_fade_begin = 50.0
		dec.distance_fade_length = 15.0
		dec.cull_mask = 0xFFFFF & ~NO_BLOOD_LAYER
		dec.size = size
		n = dec
	else:
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(size.x, size.z)
		mi.mesh = plane
		# Its own copy, because each one fades on its own clock.
		mi.material_override = _splat_material(kind).duplicate()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 60.0
		n = mi
	n.name = "Blood"
	n.add_to_group("blood")
	host.add_child(n)
	n.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	var t := n.create_tween()
	if delay > 0.0:
		n.visible = false
		t.tween_interval(delay)
		t.tween_callback(n.show)
	if pop:
		t.tween_method(func(k: float) -> void: _set_extent(n, size * lerpf(0.5, 1.0, k)), 0.0, 1.0, 0.09).set_ease(Tween.EASE_OUT)
	t.tween_interval(maxf(life, 0.5))
	t.tween_method(func(a: float) -> void: _set_alpha(n, a), 1.0, 0.0, 3.0)
	t.tween_callback(n.queue_free)
	return n


static func _set_extent(n: Node3D, size: Vector3) -> void:
	if not is_instance_valid(n):
		return
	if n is Decal:
		(n as Decal).size = size
	elif n is MeshInstance3D and (n as MeshInstance3D).mesh is PlaneMesh:
		((n as MeshInstance3D).mesh as PlaneMesh).size = Vector2(size.x, size.z)


static func _extent(n: Node3D) -> Vector3:
	if n is Decal:
		return (n as Decal).size
	if n is MeshInstance3D and (n as MeshInstance3D).mesh is PlaneMesh:
		var s := ((n as MeshInstance3D).mesh as PlaneMesh).size
		return Vector3(s.x, 0.5, s.y)
	return Vector3.ONE


static func _set_alpha(n: Node3D, a: float) -> void:
	if not is_instance_valid(n):
		return
	if n is Decal:
		(n as Decal).modulate.a = a
	elif n is MeshInstance3D and (n as MeshInstance3D).material_override is StandardMaterial3D:
		((n as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = a


# --- Blood textures ---------------------------------------------------------------------------

static var _blood_tex: Dictionary = {}


## The albedo, normal and ORM maps of one kind of blood mark, generated once and cached (the
## loading screen pays for them). Each kind paints a "thickness" field out of soft domes, and
## every kind is then shaded the same way: a thin film is the brighter red, thick blood near-black
## red, and the rim darker again where a drying edge collects - the coffee-ring edge is what tells
## dried blood from red paint. The normal map carries the meniscus at the edge, and the roughness
## runs to a near-mirror where it is thick and wet, so a pool catches the sky.
static func blood_textures(kind: int) -> Array:
	if _blood_tex.has(kind):
		return _blood_tex[kind]
	var w := 128
	var h := 128
	if kind == _KIND_DRIP:
		w = 64
	elif kind == _KIND_SMEAR:
		h = 64
	var f := PackedFloat32Array()
	f.resize(w * h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150 + kind * 31
	match kind:
		_KIND_DROP:
			_paint_drop(f, w, h, rng)
		_KIND_SPATTER:
			_paint_spatter(f, w, h, rng)
		_KIND_POOL:
			_paint_pool(f, w, h, rng)
		_KIND_SMEAR:
			_paint_smear(f, w, h, rng)
		_:
			_paint_drip(f, w, h, rng)
	var maps := _shade_blood(f, w, h, rng)
	_blood_tex[kind] = maps
	return maps


## A soft dome of blood: an ellipse `rx` by `ry` pixels at (cx, cy), its long axis turned to
## `ang`, `amp` thick in the middle. Where two meet they run together instead of overlapping.
static func _blob(f: PackedFloat32Array, w: int, h: int, cx: float, cy: float, rx: float, ry: float,
		ang: float = 0.0, amp: float = 1.0) -> void:
	var r := maxf(rx, ry) + 1.0
	var c := cos(ang)
	var s := sin(ang)
	for y in range(maxi(0, int(cy - r)), mini(h, int(cy + r) + 2)):
		for x in range(maxi(0, int(cx - r)), mini(w, int(cx + r) + 2)):
			var dx := float(x) + 0.5 - cx
			var dy := float(y) + 0.5 - cy
			var lx := (dx * c + dy * s) / maxf(rx, 0.3)
			var ly := (-dx * s + dy * c) / maxf(ry, 0.3)
			var d2 := lx * lx + ly * ly
			if d2 >= 1.0:
				continue
			var v := amp * sqrt(1.0 - d2)
			var i := y * w + x
			var old := f[i]
			f[i] = maxf(old, v) + 0.35 * minf(old, v)


## The main body of a mark: a dome (or, with `flat` above 0, a flat-topped pool whose edge rises
## over that fraction of the radius) whose outline wanders by three sines of random phase.
static func _lobed(f: PackedFloat32Array, w: int, h: int, cx: float, cy: float, radius: float,
		wobble: float, lobes: int, rng: RandomNumberGenerator, amp: float = 1.0, flat: float = 0.0) -> void:
	var p0 := rng.randf() * TAU
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var k0 := float(lobes)
	var k1 := float(lobes * 2 + 1)
	var k2 := float(lobes * 3 + 2)
	var r := radius * (1.0 + wobble) + 1.0
	for y in range(maxi(0, int(cy - r)), mini(h, int(cy + r) + 2)):
		for x in range(maxi(0, int(cx - r)), mini(w, int(cx + r) + 2)):
			var dx := float(x) + 0.5 - cx
			var dy := float(y) + 0.5 - cy
			var rr := sqrt(dx * dx + dy * dy)
			var a := atan2(dy, dx)
			var edge := radius * (1.0 + wobble * (0.55 * sin(k0 * a + p0) + 0.3 * sin(k1 * a + p1) + 0.15 * sin(k2 * a + p2)))
			if rr >= edge:
				continue
			var q := rr / edge
			var v := amp * (smoothstep(0.0, flat, 1.0 - q) if flat > 0.0 else sqrt(1.0 - q * q))
			var i := y * w + x
			var old := f[i]
			f[i] = maxf(old, v) + 0.35 * minf(old, v)


## A drop that hit the ground: a lobed splash with a crown of short spikes round it and satellite
## droplets thrown out past it, most of them forward (+U, the way it was travelling).
static func _paint_drop(f: PackedFloat32Array, w: int, h: int, rng: RandomNumberGenerator) -> void:
	var cx := w * 0.5
	var cy := h * 0.5
	var r := w * 0.23
	_lobed(f, w, h, cx, cy, r, 0.16, 5, rng)
	for i in 16:
		var a := rng.randf() * TAU
		var fwd := 0.5 + 0.5 * cos(a)
		var length := r * rng.randf_range(0.25, 0.55) * (0.7 + 0.8 * fwd)
		var at := Vector2(cx, cy) + Vector2(cos(a), sin(a)) * (r * 0.95 + length * 0.5)
		_blob(f, w, h, at.x, at.y, length * 0.5, r * rng.randf_range(0.06, 0.12), a, 0.8)
	for i in 26:
		var a := rng.randf_range(-1.1, 1.1) if rng.randf() < 0.65 else rng.randf() * TAU
		var at := Vector2(cx, cy) + Vector2(cos(a), sin(a)) * r * rng.randf_range(1.25, 2.0)
		if at.x < 3.0 or at.x > w - 3.0 or at.y < 3.0 or at.y > h - 3.0:
			continue
		var s := r * rng.randf_range(0.03, 0.11)
		_blob(f, w, h, at.x, at.y, s * 1.4, s, a, 0.75)


## An exit wound's spray on a wall: a dense core near V 0.2 and droplets flung out from it toward
## +V inside a cone, smaller, longer and more tailed the further they flew, plus a few streaks.
static func _paint_spatter(f: PackedFloat32Array, w: int, h: int, rng: RandomNumberGenerator) -> void:
	var core := Vector2(w * 0.5, h * 0.2)
	_lobed(f, w, h, core.x, core.y, w * 0.10, 0.2, 4, rng)
	for i in 80:
		var a := PI * 0.5 + rng.randf_range(-0.55, 0.55) * (0.25 + 0.75 * rng.randf())
		var t := pow(rng.randf(), 0.8)
		var at := core + Vector2(cos(a), sin(a)) * lerpf(w * 0.07, h * 0.76, t)
		if at.y > h - 3.0 or at.x < 3.0 or at.x > w - 3.0:
			continue
		var s := lerpf(w * 0.034, w * 0.008, t) * rng.randf_range(0.6, 1.3)
		var stretch := lerpf(1.2, 3.2, t)
		_blob(f, w, h, at.x, at.y, s * stretch, s, a, 0.85)
		if rng.randf() < 0.5:
			var tail := at + Vector2(cos(a), sin(a)) * s * stretch * 1.4
			_blob(f, w, h, tail.x, tail.y, s * stretch * 0.9, s * 0.35, a, 0.5)
	for i in 5:
		var a := PI * 0.5 + rng.randf_range(-0.35, 0.35)
		var length := h * rng.randf_range(0.18, 0.4)
		var at := core + Vector2(cos(a), sin(a)) * (w * 0.1 + length * 0.5)
		_blob(f, w, h, at.x, at.y, length * 0.5, w * rng.randf_range(0.01, 0.022), a, 0.7)


## A pool: flat-topped with a rounded edge (the meniscus), lobed where it ran further on one side,
## and a couple of little pools touching its rim.
static func _paint_pool(f: PackedFloat32Array, w: int, h: int, rng: RandomNumberGenerator) -> void:
	_lobed(f, w, h, w * 0.5, h * 0.5, w * 0.33, 0.10, 3, rng, 1.0, 0.18)
	for i in 4:
		var a := rng.randf() * TAU
		var at := Vector2(w * 0.5, h * 0.5) + Vector2(cos(a), sin(a)) * w * rng.randf_range(0.22, 0.31)
		_lobed(f, w, h, at.x, at.y, w * rng.randf_range(0.07, 0.13), 0.2, 3, rng, 0.95, 0.3)


## A body dragged through blood: parallel streaks running the length of the mark (+U), heavy
## where it started and fraying out toward the end, broken where it lifted.
static func _paint_smear(f: PackedFloat32Array, w: int, h: int, rng: RandomNumberGenerator) -> void:
	var lanes := 9
	for l in lanes:
		var y0 := h * (0.2 + 0.6 * (float(l) + rng.randf_range(-0.3, 0.3)) / float(lanes - 1))
		var width := h * rng.randf_range(0.03, 0.08)
		var reach := w * rng.randf_range(0.55, 0.97)
		var x := w * rng.randf_range(0.02, 0.12)
		while x < reach:
			var seg := w * rng.randf_range(0.08, 0.2)
			var fade := 1.0 - x / float(w)
			_blob(f, w, h, x + seg * 0.5, y0 + rng.randf_range(-1.0, 1.0), seg * 0.6, width * (0.5 + 0.6 * fade), 0.0, 0.5 + 0.5 * fade)
			x += seg * rng.randf_range(0.7, 1.3)
			if rng.randf() < 0.15:
				x += w * 0.06
	_lobed(f, w, h, w * 0.12, h * 0.5, h * 0.3, 0.2, 3, rng, 0.9)


## Runs down a wall (+V is down): the band where the spray hit, then runs of different lengths
## down from it, each ending in a bead.
static func _paint_drip(f: PackedFloat32Array, w: int, h: int, rng: RandomNumberGenerator) -> void:
	for i in 5:
		_blob(f, w, h, w * rng.randf_range(0.15, 0.85), h * rng.randf_range(0.03, 0.09), w * rng.randf_range(0.10, 0.2), h * 0.04, 0.0, 0.8)
	for i in 7:
		var x := w * rng.randf_range(0.1, 0.9)
		var length := h * rng.randf_range(0.25, 0.9)
		var wd := w * rng.randf_range(0.018, 0.04)
		_blob(f, w, h, x, h * 0.04 + length * 0.5, wd, length * 0.5, 0.0, 0.7)
		_blob(f, w, h, x, h * 0.04 + length, wd * 1.8, wd * 2.2, 0.0, 0.9)


## Thickness field -> [albedo, normal, ORM] textures.
static func _shade_blood(f: PackedFloat32Array, w: int, h: int, rng: RandomNumberGenerator) -> Array:
	var alb := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var nrm := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var orm := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.09
	# The surface the normal map is taken from: rises fast at the edge, then flat on top.
	var height := PackedFloat32Array()
	height.resize(w * h)
	for i in w * h:
		height[i] = smoothstep(0.04, 0.35, f[i])
	for y in h:
		for x in w:
			var i := y * w + x
			var t := f[i]
			var a := smoothstep(0.04, 0.12, t)
			# Only the thick middles go near black; droplets, streaks and runs stay a thin-film red.
			var body := smoothstep(0.3, 1.0, t)
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var col := BLOOD_FRESH.lerp(BLOOD_DARK, body * 0.9)
			var rim := 1.0 - smoothstep(0.05, 0.22, t)
			col = col.darkened(0.35 * rim * a + 0.18 * n)
			alb.set_pixel(x, y, Color(col.r, col.g, col.b, a))
			var dx := (height[y * w + mini(x + 1, w - 1)] - height[y * w + maxi(x - 1, 0)]) * 1.6
			var dy := (height[mini(y + 1, h - 1) * w + x] - height[maxi(y - 1, 0) * w + x]) * 1.6
			# OpenGL-style map (green up): the image's rows run down, so the Y slope flips.
			var nv := Vector3(-dx, dy, 1.0).normalized()
			nrm.set_pixel(x, y, Color(nv.x * 0.5 + 0.5, nv.y * 0.5 + 0.5, nv.z * 0.5 + 0.5, 1.0))
			# Satin, not a mirror. A splat on the road is always seen at a grazing angle, where
			# Fresnel takes any glossy surface toward a mirror of the sky whatever its F0: at 0.05,
			# at 0.2 and still at 0.3 the thick middles measured BRIGHTER than the road under them
			# and read as pale pink. Roughness is the only lever; the wet look is the meniscus in
			# the normal map catching the light at the edges.
			var rough := lerpf(0.72, 0.5, body) + 0.06 * n
			orm.set_pixel(x, y, Color(1.0, clampf(rough, 0.03, 1.0), 0.0, 1.0))
	var out: Array = []
	out.append(ImageTexture.create_from_image(_coverage_mips(alb)))
	for img: Image in [nrm, orm]:
		img.generate_mipmaps()
		out.append(ImageTexture.create_from_image(img))
	return out


## Mipmaps that keep a mark's coverage. Plain mips average a small splash's alpha with the
## empty texture round it, so ten metres off - a few mip levels down - a splat was a faint
## translucent smear and the road showed through. Each level is the one above halved (a box
## filter; resizing the full image straight down point-samples it) and stored with its alpha
## lifted the further down it is, the usual fix for cut-out textures.
static func _coverage_mips(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var level := 0
	var prev := img
	while w > 1 or h > 1:
		w = maxi(1, w >> 1)
		h = maxi(1, h >> 1)
		level += 1
		var half := prev.duplicate() as Image
		half.resize(w, h, Image.INTERPOLATE_BILINEAR)
		prev = half
		var m := half.duplicate() as Image
		var lift := 1.0 + 0.45 * float(level)
		for y in h:
			for x in w:
				var c := m.get_pixel(x, y)
				c.a = minf(c.a * lift, 1.0)
				m.set_pixel(x, y, c)
		data.append_array(m.get_data())
	return Image.create_from_data(img.get_width(), img.get_height(), true, Image.FORMAT_RGBA8, data)


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
		_ramp([Color(1.5, 1.35, 1.1), Color(1.0, 1.0, 1.0), Color(0.45, 0.33, 0.28)]), _fire_material())

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

	# 8. Debris: lit chunks, so they sit in the scene's lighting rather than glowing flat. Small,
	# dark and many: at 18 cm and a mid brown, a still showed a dozen cardboard boxes in the air.
	_chip_layer(parent, at, _count(34), 0.11, 1.6, radius * 1.4 * push, radius * 3.0 * push,
		Color(0.16, 0.15, 0.14), Basis(), 170.0, -32.0)

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
