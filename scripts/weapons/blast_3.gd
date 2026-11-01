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


## True when a blast's chips and sparks are BlastBits (that land) rather than particles.
static func bits_on() -> bool:
	return enabled and not WeaponFX._web()


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
static func spawn_volume(parent: Node, at: Vector3, radius: float, fuel: bool, life_override: float = -1.0) -> MeshInstance3D:
	_prune()
	var big := 1.0 + (0.3 if fuel else 0.0)
	var half := Vector3(1.5, 1.6, 1.5) * big
	var centre := Vector3(0.0, 1.3, 0.0) * big
	var v4: Array = []
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
	if Blast4.enabled:
		# The fourth pass: the volume lives on as the mushroom (a taller box, its own life).
		v4 = Blast4.dress_volume(mat, fuel, Blast4.gas_next)
		if life_override > 0.0:
			v4[2] = life_override
			mat.set_shader_parameter("life", life_override)
		half = v4[0]
		centre = v4[1]
		mat.set_shader_parameter("half_r", half)
		mat.set_shader_parameter("centre_r", centre)
	if OS.get_environment("BLAST3_DEBUG") != "":
		mat.set_shader_parameter("debug", int(OS.get_environment("BLAST3_DEBUG")))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = Transform3D(Basis.from_scale(half * radius), at + centre * radius)
	# Its bounds for culling: the box itself (a box mesh's own AABB is right; nothing to add).
	var life := fuel_life if fuel else volume_life
	if not v4.is_empty():
		life = v4[2]
	var tw := mi.create_tween()
	tw.tween_method(func(v: float):
		if is_instance_valid(mat):
			mat.set_shader_parameter("t", v)
			mat.set_shader_parameter("fade", Blast4.fade_at(v, life) if not v4.is_empty() else 1.0 - smoothstep(life * 0.55, life, v)),
		0.0, life, life)
	tw.tween_callback(mi.queue_free)
	_volumes.append(mi)
	return mi


## The fires the smoke is lit by: BlastFX's flash / glow lights (registered as they are made), then
## burning cars. Pushed to blast_smoke.gdshader every frame by `push_fires()` (BlastBits drives it).
static var _fires: Array = []
## The smoke's look with this on (blast_smoke.gdshader): the old young-puff glow kept at this
## share, the street lamps' glow on its underside after dark, light through it toward the sun.
static var smoke_young_glow: float = 0.3
static var smoke_city_glow: Color = Color(0.85, 0.42, 0.16) # linear
static var smoke_city_gain: float = 1.0
static var smoke_forward: float = 1.0


static func add_fire(light: OmniLight3D) -> void:
	if enabled and light != null:
		_fires.append(light)


## The fires as the smoke shader's packed vec4s (xyz world, w = reach + strength / 2).
static func fire_list(tree: SceneTree) -> Array[Vector4]:
	var out: Array[Vector4] = []
	_fires = _fires.filter(func(l): return is_instance_valid(l) and (l as Node).is_inside_tree())
	for l: OmniLight3D in _fires:
		if out.size() >= 4:
			break
		var str_ := clampf(l.light_energy / maxf(BlastFX.glow_energy, 0.01), 0.0, 1.0)
		if str_ > 0.02:
			out.append(Vector4(l.global_position.x, l.global_position.y, l.global_position.z, floorf(maxf(l.omni_range, 1.0)) + str_ * 0.499))
	if tree != null and out.size() < 4:
		for c in CarDamage._burning:
			if out.size() >= 4:
				break
			if c is Node3D and is_instance_valid(c) and (c as Node).is_inside_tree():
				var p: Vector3 = (c as Node3D).global_position + Vector3.UP * 1.2
				out.append(Vector4(p.x, p.y, p.z, 14.0 + 0.6 * 0.499))
	return out


static func push_fires(tree: SceneTree) -> void:
	var m := BlastFX.smoke_material()
	if not enabled:
		m.set_shader_parameter("fire_count", 0)
		m.set_shader_parameter("young_glow", 1.0)
		m.set_shader_parameter("forward_scatter", 0.0)
		m.set_shader_parameter("city_glow", Vector3.ZERO)
		return
	var list := fire_list(tree)
	var arr := PackedVector4Array()
	for v in list:
		arr.append(v)
	while arr.size() < 4:
		arr.append(Vector4.ZERO)
	m.set_shader_parameter("fires", arr)
	m.set_shader_parameter("fire_count", list.size())
	# The young-puff glow only while something is still burning (at its strength): a column fed
	# for ten seconds over a fire that went out at two was lit orange from inside by nothing.
	var hottest := 0.0
	for v in list:
		hottest = maxf(hottest, fmod(v.w, 1.0) * 2.0)
	m.set_shader_parameter("young_glow", smoke_young_glow * hottest)
	m.set_shader_parameter("forward_scatter", smoke_forward)
	m.set_shader_parameter("city_glow", Vector3(smoke_city_glow.r, smoke_city_glow.g, smoke_city_glow.b) * smoke_city_gain)
	# Blast4: the mushroom volumes are lit by the same fires.
	if Blast4.enabled:
		_prune()
		for v in _volumes:
			var vm := (v as MeshInstance3D).material_override as ShaderMaterial
			if vm != null:
				vm.set_shader_parameter("fires", arr)
				vm.set_shader_parameter("fire_count", list.size())
				vm.set_shader_parameter("city_glow", Vector3(smoke_city_glow.r, smoke_city_glow.g, smoke_city_glow.b) * smoke_city_gain)


# --- The flash's light ----------------------------------------------------------------------------

## The flash at HIGH quality on Forward+ casts shadows (one blast at a time): the light then
## falls off round the corner of a car or a pillar instead of lighting the wall behind it.
static var flash_shadows: bool = true
## The white-hot flare's size against BlastFX's (its 38 m quad whited out a night street).
static var flare_scale: float = 0.55
static var _shadow_light: OmniLight3D


## Called by BlastFX._flash() for its light.
static func dress_flash(light: OmniLight3D) -> void:
	if not enabled or not flash_shadows or WeaponFX._web() or RenderingServer.get_rendering_device() == null:
		return
	var env: Environment = light.get_world_3d().environment if light.is_inside_tree() and light.get_world_3d() != null else null
	if env != null and not env.sdfgi_enabled:
		return # below HIGH (Quality turns SDFGI off there)
	if _shadow_light != null and is_instance_valid(_shadow_light) and _shadow_light.is_inside_tree():
		return
	light.shadow_enabled = true
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 1.5
	_shadow_light = light


# --- The heat haze ------------------------------------------------------------------------------

## The haze over the fire: seconds it lasts (a fuel fire longer), its bend at the base.
static var haze_seconds: float = 6.0
static var haze_fuel_seconds: float = 11.0
static var haze_strength: float = 0.012
static var _haze_shader: Shader
static var _haze_quad: QuadMesh


## True when the blast's heat shimmer is BlastHaze (WeaponFX then leaves its old sphere out).
static func haze_on() -> bool:
	return enabled and not WeaponFX._web() and WeaponFX.shimmer_enabled


static func spawn_haze(parent: Node, at: Vector3, radius: float, fuel: bool) -> MeshInstance3D:
	if _haze_shader == null:
		_haze_shader = preload("res://shaders/blast_haze.gdshader")
		_haze_quad = QuadMesh.new()
		_haze_quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _haze_shader
	mat.set_shader_parameter("noise3d", noise_texture())
	mat.set_shader_parameter("strength", haze_strength)
	mat.set_shader_parameter("fade", 0.0)
	mat.render_priority = Material.RENDER_PRIORITY_MIN
	var mi := MeshInstance3D.new()
	mi.name = "BlastHaze"
	mi.mesh = _haze_quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var w := radius * (1.7 if fuel else 1.3)
	var h := radius * (3.6 if fuel else 2.8)
	mi.global_transform = Transform3D(Basis.from_scale(Vector3(w, h, 1.0)), at - Vector3.UP * 0.3)
	# Its bounds: the column whichever way it turns (the vertex shader turns it).
	mi.custom_aabb = AABB(Vector3(-0.6, -0.6, -0.6 * w), Vector3(1.2, 1.8, 1.2 * w))
	var life := haze_fuel_seconds if fuel else haze_seconds
	var tw := mi.create_tween()
	tw.tween_property(mat, "shader_parameter/fade", 1.0, 0.25)
	tw.tween_interval(life * 0.4)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, life * 0.6).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	return mi


# --- The crater's maps -------------------------------------------------------------------------

static var _crater_maps: Array = [null, null]


## The crater's maps with this on: [albedo (alpha the coverage), normal, emission]. Kind 0 the pit
## with its scorch, 1 the scorch alone (a car's own blast). What the old maps lacked, seen from a
## pavement: a soot mark is not a disc - the blast throws it out in FINGERS of different lengths
## from a solid core, specks of soot past them, and beyond the soot the road is scoured and dusted
## PALER; the pit's rim is broken slabs, not a ring; and for its first seconds the pit glows
## (`emission`: hot spots in the pit and along the cracks, faded by BlastAftermath.crater()).
## 384 px, an angle table for the fingers (so it costs a few hundred ms once, on the loading
## screen through BlastAftermath.warm()).
static func crater_maps(kind: int) -> Array:
	if _crater_maps[kind] != null:
		return _crater_maps[kind]
	var n := 384
	var rng := RandomNumberGenerator.new()
	rng.seed = 7301 + kind
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 191 + kind
	noise.frequency = 0.03
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var fine := FastNoiseLite.new()
	fine.noise_type = FastNoiseLite.TYPE_VALUE
	fine.seed = 17
	fine.frequency = 0.35
	var cell := FastNoiseLite.new()
	cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell.seed = 5
	cell.frequency = 0.045
	cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	# The fingers: per angle bin, how far the soot reaches (share of the mark's radius) and how
	# dark it is there; a sum of rays of random width, blurred round the circle.
	var bins := 720
	var reach := PackedFloat32Array()
	reach.resize(bins)
	reach.fill(0.42)
	for i in 46:
		var a := rng.randf() * TAU
		var w := rng.randf_range(0.006, 0.05)
		var l := rng.randf_range(0.5, 0.97)
		for b in bins:
			var ang := TAU * float(b) / float(bins)
			var d := absf(wrapf(ang - a, -PI, PI))
			if d < w * 3.0:
				var k := exp(-d * d / (w * w))
				reach[b] = maxf(reach[b], 0.42 + (l - 0.42) * k)
	var total := BlastAftermath.crater_scale + BlastAftermath.scorch_scale * 0.5
	var pit_r := BlastAftermath.crater_scale * 0.5 / total if kind == 0 else 0.0
	var cracks: Array = []
	for i in 15:
		cracks.append([rng.randf() * TAU, rng.randf_range(0.25, 0.75), rng.randf_range(0.003, 0.009)])
	var height := PackedFloat32Array()
	height.resize(n * n)
	var alb := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var emi := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var ang := atan2(v, u)
			var nz := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var fz := fine.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var bi := int(wrapf(ang, 0.0, TAU) / TAU * float(bins)) % bins
			var fr: float = reach[bi] * (0.9 + 0.2 * nz)
			var col := Color(0.0, 0.0, 0.0)
			var a := 0.0
			var hgt := 0.0
			var glow := 0.0
			# The scoured, dusted ring past the soot: the road paler, in patches.
			var halo := (1.0 - smoothstep(0.78, 1.0, r)) * smoothstep(0.25, 0.6, r) * (0.45 + 0.55 * nz)
			if halo > 0.0:
				col = Color(0.42, 0.40, 0.37)
				a = halo * 0.32
			# Soot: solid in the core, out along the fingers, thinning to their tips.
			var soot := 1.0 - smoothstep(fr * 0.75, fr, r)
			soot *= 0.75 + 0.25 * fz
			# Specks of soot past the fingers.
			if r > fr and r < 0.95 and fz > 0.83 and nz > 0.45:
				soot = maxf(soot, 0.55)
			if soot > 0.0:
				var sc := Color(0.028, 0.026, 0.024).lerp(Color(0.075, 0.068, 0.06), fz * 0.5 + r * 0.4)
				col = col.lerp(sc, clampf(soot * 1.2, 0.0, 1.0)) if a > 0.0 else sc
				a = maxf(a, clampf(soot * 1.05, 0.0, 0.96))
			if pit_r > 0.0:
				var pr := pit_r * (0.88 + 0.24 * nz)
				var cz := cell.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				if r < pr:
					var k := r / pr
					hgt = -(1.0 - k * k) * 1.2 + (cz - 0.5) * 0.25
					var stone := Color(0.30, 0.27, 0.23).lerp(Color(0.18, 0.15, 0.12), fz)
					col = stone.lerp(Color(0.04, 0.035, 0.03), clampf(1.0 - k * 1.5, 0.0, 1.0) * 0.85)
					a = 1.0
					# Embers: hot spots in the blackened middle of the pit.
					glow = clampf((nz - 0.45) * 3.0, 0.0, 1.0) * clampf(1.2 - k * 1.1, 0.0, 1.0) * (0.5 + fz * 0.5)
				elif r < pr * 1.55:
					# The rim: slabs broken along cell edges, tipped up toward the pit.
					var k2 := (r - pr) / (pr * 0.55)
					var slab := smoothstep(0.02, 0.12, cz)
					hgt = sin(k2 * PI) * (0.4 + 0.6 * fz) * slab + (1.0 - slab) * -0.3
					col = Color(0.075, 0.07, 0.065).lerp(Color(0.17, 0.155, 0.14), slab * (1.0 if fz > 0.6 else 0.35))
					if slab < 0.5:
						col = Color(0.26, 0.23, 0.2) # the crushed base course between slabs
					a = 1.0
				for c: Array in cracks:
					var da := absf(wrapf(ang - float(c[0]), -PI, PI))
					var wob := (nz - 0.5) * 0.1
					var cr: float = float(c[1])
					if r > pr and r < pr + cr * (1.0 - pr) and absf(da - wob) * r < float(c[2]) * (1.3 - r):
						col = Color(0.012, 0.011, 0.01)
						hgt -= 0.4
						a = maxf(a, 0.95)
						# Hot only where the crack leaves the pit.
						glow = maxf(glow, 0.45 * clampf(1.0 - (r - pr) / (pr * 0.35), 0.0, 1.0))
			height[y * n + x] = hgt
			alb.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))
			var g := glow * glow
			emi.set_pixel(x, y, Color(g, g * 0.32, g * 0.06))
	var nrm := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var depth := 7.0
	for y in n:
		for x in n:
			var hl := height[y * n + maxi(x - 1, 0)]
			var hr := height[y * n + mini(x + 1, n - 1)]
			var hd := height[maxi(y - 1, 0) * n + x]
			var hu := height[mini(y + 1, n - 1) * n + x]
			# OpenGL-style (green up): the Y slope is the row below minus the row above.
			var nv := Vector3((hl - hr) * depth, (hu - hd) * depth, 1.0).normalized()
			nrm.set_pixel(x, y, Color(nv.x * 0.5 + 0.5, nv.y * 0.5 + 0.5, nv.z * 0.5 + 0.5, 1.0))
	alb.generate_mipmaps()
	nrm.generate_mipmaps()
	emi.generate_mipmaps()
	var out := [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(nrm), ImageTexture.create_from_image(emi)]
	_crater_maps[kind] = out
	return out


## The loading screen's warm-up (the noise, a material).
static func warm() -> Array:
	noise_texture()
	return [volume_material()]
