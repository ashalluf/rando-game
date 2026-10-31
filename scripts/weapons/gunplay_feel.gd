class_name GunplayFeel
extends RefCounted
## The guns' feedback at arm's length (docs/HANDOFF.md "Gunplay at arm's length"). WeaponFX keeps
## the plumbing (particles, surfaces, impacts); this is what a shot looks like up close, taken
## over by one hook line in each WeaponFX function it replaces:
##  * flash(): the muzzle flash as a VOLUME of burning gas - crossed lances of flame down the bore,
##    a crown at the muzzle, tongues off its sides (shaders/muzzle_flash.gdshader) - and its light
##    in three places: on the hands and the gun, ahead down the barrel, and on whatever wall the
##    barrel points at (one ray);
##  * the barrel heats with every round and SMOKES after the burst (BarrelSmoke, a wisp curling
##    off the muzzle for a second or two; lit, so the street light and the next flash show it);
##  * tracer(): a short hot streak racing out with a faint trail of hot air behind it, turned to
##    the camera and never thinner than a pixel and a half (shaders/tracer_streak.gdshader) - the
##    old full-length cylinder read as a laser line;
##  * hole(): the marks by surface, several of each, with normal maps: a spalled crater in
##    concrete, a punched hole with a ring of bare steel in metal (metallic in the ORM), a
##    splintered tear along the grain in wood, a soft crater in dirt, pellet pits for the
##    shotgun; and on the Compatibility renderer (the web, every opengl3 still), which has no
##    decals, a lit quad with the same maps - before, nothing at all;
##  * spread_mark(): the shotgun's pattern - a ring of grey lead and powder smudge round where the
##    pellets went into one surface, and a ragged rathole at point-blank range;
##  * the recoil is Weapon's spring (Weapon.recoil_*): the gun kicks back, rises and rolls about
##    the butt in the shoulder and springs back past rest; the hands ride it by the IK
##    (Avatar.hold_gun -> Weapon.apply_recoil), and the camera takes a small punch.
## GUNPLAY_FEEL=0 in the environment is the A/B: WeaponFX's old flash, tracer and holes, the old
## straight kick.

static var enabled: bool = OS.get_environment("GUNPLAY_FEEL") != "0"

## Light thrown on the shooter's hands and gun (energy at the rifle's flash size, and reach).
static var hand_light_energy: float = 2.6
static var hand_light_range: float = 2.4
## The light thrown on a wall the barrel points at, from `wall_light_min` to `wall_light_reach`
## metres (closer than that the main light reaches it already).
static var wall_light_energy: float = 1.8
static var wall_light_min: float = 4.0
static var wall_light_reach: float = 22.0
## Seconds the flash's lights last (a real flash is a millisecond; a frame at 60 fps is the
## least the eye gets, and two read as a flash rather than a flicker).
static var light_time: float = 0.06
## Barrel heat a round adds (0..1 is full), and how fast it cools a second.
static var heat_per_round: float = 0.11
static var heat_cool: float = 0.32
## Heat under which the barrel no longer smokes.
static var smoke_from_heat: float = 0.12
## Bullet holes: size by surface is WeaponFX.SURFACES' hole_scale; pellets are this much of a
## round's hole.
static var pellet_hole_scale: float = 0.42
## Set by Shotgun round its pellets, so the holes they make are pellet pits.
static var pellet_mode: bool = false
## How many variants of each surface's hole are generated.
const VARIANTS := 3
## The texture side of a hole set, pixels.
const HOLE_PX := 128
const HOLE_DIR := "res://assets/textures/bullet_holes/"

static var _flash_mesh: ArrayMesh
static var _flash_shader: Shader
static var _tracer_mesh: ArrayMesh
static var _tracer_shader: Shader
static var _holes: Dictionary = {}
static var _quad_mats: Dictionary = {}
static var _smoke_mat: StandardMaterial3D
static var _pattern_tex: Array = []
## For the checks: what the hooks did.
static var stats := {"flashes": 0, "tracers": 0, "holes": 0, "quads": 0, "patterns": 0, "wall_lights": 0}


# ---------------------------------------------------------------------------------------------
# Muzzle flash
# ---------------------------------------------------------------------------------------------

## The flash at `at`, down `node`'s -Z (the weapon). `size` is WeaponFX.flash's: 0.25 the rifle,
## 0.6 the shotgun.
static func flash(node: Node, at: Vector3, color: Color, size: float, life: float) -> void:
	var parent := WeaponFX.fx_parent(node)
	var n3 := node as Node3D
	var fwd := -n3.global_basis.z.normalized() if n3 != null and n3.is_inside_tree() else Vector3.FORWARD
	var k := size / 0.25
	stats["flashes"] = int(stats["flashes"]) + 1

	var mi := MeshInstance3D.new()
	mi.name = "MuzzleFlash"
	mi.mesh = flash_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = _flash_shader_res()
	mat.set_shader_parameter("seed", randf() * 100.0)
	mat.set_shader_parameter("age", 0.0)
	# Warmer for a bigger charge (the shotgun's flash is redder and longer).
	var warm := clampf((k - 1.0) * 0.4, 0.0, 0.5)
	mat.set_shader_parameter("core_color", Vector3(1.0, 0.78 - warm * 0.12, 0.46 - warm * 0.2))
	mat.set_shader_parameter("heat", 7.0 * (0.85 + 0.15 * minf(k, 2.0)) * maxf(color.r, 0.6))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 0.5
	parent.add_child(mi)
	# Down the bore, rolled at random: a flash never comes out the same way up twice.
	var basis := Basis.looking_at(fwd, Vector3.UP if absf(fwd.y) < 0.98 else Vector3.RIGHT)
	basis = basis.rotated(fwd, randf() * TAU)
	# A bigger charge throws a longer flame, but not in proportion (at 2.4x the shotgun's filled
	# the frame).
	mi.global_transform = Transform3D(basis.scaled(Vector3.ONE * pow(k, 0.7) * randf_range(0.85, 1.15)), at)
	var t := mi.create_tween()
	t.tween_method(func(a: float) -> void: mat.set_shader_parameter("age", a), 0.0, 1.0, maxf(life * 1.3, 0.03))
	t.tween_callback(mi.queue_free)

	_lights(node, parent, at, fwd, k)
	if node is Weapon:
		BarrelSmoke.heat_up(node as Weapon)

	# Every few shots the gas and grit WeaponFX always threw (its own cadence and materials).
	WeaponFX.flash_gas(node, parent, at, fwd, size)


## The flash's light: on the hands and the gun (a short light just behind the muzzle), ahead
## (the old light, down the bore), and on the wall the barrel points at.
static func _lights(node: Node, parent: Node, at: Vector3, fwd: Vector3, k: float) -> void:
	var web := OS.has_feature("web")
	# Energy grows less than the flash: at the shotgun's full 2.4x the old light burnt a wall four
	# metres off to white, in daylight too.
	var main := _light(parent, at + fwd * 0.45 * k, WeaponFX.muzzle_light_energy * clampf(k, 0.7, 1.5),
		WeaponFX.muzzle_light_range * clampf(k, 0.7, 1.4), WeaponFX.muzzle_light_time)
	if not web:
		# Volumetric fog takes it too (Forward+ HIGH): a flash in the haze is a puff of light.
		main.light_volumetric_fog_energy = 3.0
	if web:
		return
	# Back at the hands: the flash lights the shooter's own arms and the gun's top for a frame,
	# which a light out ahead of the muzzle mostly missed.
	# A bigger charge is a bigger flash, but the extra lights only grow a little with it: scaled
	# by the shotgun's whole size they burnt the hands and a wall a few metres off to white.
	var kl := clampf(k, 0.7, 1.35)
	_light(parent, at - fwd * 0.18 + Vector3.UP * 0.05, hand_light_energy * kl, hand_light_range * kl, light_time)
	# The wall the barrel points at.
	var space := WeaponFX._space(node)
	if space == null:
		return
	var q := PhysicsRayQueryParameters3D.create(at + fwd * 0.3, at + fwd * wall_light_reach, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var d := at.distance_to(hit.position)
	if d < wall_light_min:
		return
	var n: Vector3 = hit.normal
	# Falls off with distance like a real flash would, eased so a wall down the street still
	# blinks with every round.
	var e := wall_light_energy * kl * clampf(9.0 / d, 0.35, 1.0)
	_light(parent, hit.position + n * 1.3 - fwd * 0.4, e, 2.8 + d * 0.06, light_time)
	stats["wall_lights"] = int(stats["wall_lights"]) + 1


static func _light(parent: Node, at: Vector3, energy: float, reach: float, life: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.84, 0.58)
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = at
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, life).set_ease(Tween.EASE_IN)
	lt.tween_callback(light.queue_free)
	return light


static func _flash_shader_res() -> Shader:
	if _flash_shader == null:
		_flash_shader = load("res://shaders/muzzle_flash.gdshader")
	return _flash_shader


## The flash's mesh in its own frame (-Z down the bore, sized for the rifle; the node scales it):
## four crossed lances, a crown facing down the bore, four tongues off the sides. UV.x along a
## piece, UV.y across it (-1..1), UV2 (piece, index) - the shader's contract.
static func flash_mesh() -> ArrayMesh:
	if _flash_mesh != null:
		return _flash_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lance := 0.34
	var half := 0.07
	for i in 4:
		var a := PI * float(i) / 4.0
		var side := Vector3(cos(a), sin(a), 0.0)
		var nrm := Vector3(-sin(a), cos(a), 0.0)
		# The lance starts a hair inside the muzzle, so no gap shows at its root.
		_card(st, Vector3(0.0, 0.0, 0.02), Vector3(0.0, 0.0, -lance), side * half, nrm, 0.0, float(i))
	# The crown: a disc facing down the bore just past the muzzle.
	var c := 0.085
	_quad(st, [Vector3(-c, -c, -0.03), Vector3(c, -c, -0.03), Vector3(c, c, -0.03), Vector3(-c, c, -0.03)],
		[Vector2(0, -1), Vector2(1, -1), Vector2(1, 1), Vector2(0, 1)], Vector3(0, 0, -1), 1.0, 0.0)
	# Tongues: out sideways and a little forward, like gas leaving a brake's ports.
	for i in 4:
		var a := PI * 0.5 * float(i) + PI * 0.25
		var out := Vector3(cos(a), sin(a), 0.0)
		var along := (out + Vector3(0.0, 0.0, -0.45)).normalized() * 0.13
		var w := out.cross(Vector3(0, 0, -1)).normalized() * 0.03
		_card(st, Vector3(0.0, 0.0, -0.01), along, w, out.cross(along).normalized(), 2.0, float(i))
	_flash_mesh = st.commit()
	return _flash_mesh


## A card from `root` along `along`, `side` half its width, UV.x along, UV.y across.
static func _card(st: SurfaceTool, root: Vector3, along: Vector3, side: Vector3, nrm: Vector3, piece: float, idx: float) -> void:
	var tip := root + along
	_quad(st, [root - side, tip - side, tip + side, root + side],
		[Vector2(0, -1), Vector2(1, -1), Vector2(1, 1), Vector2(0, 1)], nrm, piece, idx)


static func _quad(st: SurfaceTool, p: Array, uv: Array, nrm: Vector3, piece: float, idx: float) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(nrm)
		st.set_uv(uv[i])
		st.set_uv2(Vector2(piece, idx))
		st.add_vertex(p[i])


static var _flare_mat: StandardMaterial3D


## The flash where a round strikes: a small star (WeaponFX's flare) that pops and is gone in
## 0.05 s, grown with distance so a far hit still blinks (`size` is WeaponFX's flash size).
static func impact_flare(parent: Node, at: Vector3, _color: Color, size: float) -> void:
	if _flare_mat == null:
		_flare_mat = WeaponFX.unshaded(Color(2.2, 1.75, 1.15), 1.0)
		_flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flare_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flare_mat.albedo_texture = WeaponFX.flare_texture()
		_flare_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_flare_mat.billboard_keep_scale = true
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mi.mesh = quad
	mi.material_override = _flare_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The fade rides the instance's transparency, so one material serves every hit.
	parent.add_child(mi)
	mi.global_position = at
	var k := size * 1.6
	mi.scale = Vector3(k * randf_range(0.8, 1.2), k * randf_range(0.8, 1.2), 1.0)
	var t := mi.create_tween()
	t.tween_property(mi, "scale", mi.scale * 0.3, 0.05).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(mi, "transparency", 1.0, 0.05)
	t.tween_callback(mi.queue_free)


# ---------------------------------------------------------------------------------------------
# Tracers
# ---------------------------------------------------------------------------------------------

## A round from `from` to `to`. `radius` is the old tracer's (0.03 the rifle, 0.012 a pellet):
## the streak's width and brightness follow it.
static func tracer(node: Node, from: Vector3, to: Vector3, color: Color, life: float, radius: float) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.3:
		return
	dir /= length
	stats["tracers"] = int(stats["tracers"]) + 1
	var parent := WeaponFX.fx_parent(node)
	var mi := MeshInstance3D.new()
	mi.name = "Tracer"
	mi.mesh = tracer_mesh()
	var mat := ShaderMaterial.new()
	if _tracer_shader == null:
		_tracer_shader = load("res://shaders/tracer_streak.gdshader")
	mat.shader = _tracer_shader
	var w := clampf(radius / 0.03, 0.3, 1.5)
	var tail := clampf(length * 0.5, 1.5, 9.0)
	mat.set_shader_parameter("length_m", length)
	mat.set_shader_parameter("tail", tail)
	mat.set_shader_parameter("width_m", 0.022 * w)
	mat.set_shader_parameter("heat", 5.0 * (0.55 + 0.45 * w))
	mat.set_shader_parameter("core_color", Vector3(color.r, color.g * 0.9, color.b * 0.85))
	mat.set_shader_parameter("head", 0.0)
	mat.set_shader_parameter("trail", 1.0)
	var vp := node.get_viewport() if node.is_inside_tree() else null
	if vp != null:
		mat.set_shader_parameter("viewport_px", float(vp.get_visible_rect().size.y))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))
	parent.add_child(mi)
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	mi.global_transform = Transform3D(basis.scaled(Vector3(1.0, 1.0, length)), from)
	# The round's flight (WeaponFX.tracer_head_speed, a few hundredths of a second down a street)
	# and the streak running off the end of the line, then the trail fading.
	var travel := clampf(length / maxf(WeaponFX.tracer_head_speed, 1.0), 0.03, 0.16)
	var t := mi.create_tween()
	t.tween_method(func(h: float) -> void: mat.set_shader_parameter("head", h), 0.0, length + tail, travel * (1.0 + tail / length))
	t.parallel().tween_method(func(a: float) -> void: mat.set_shader_parameter("trail", a), 1.0, 0.0, travel + maxf(life, 0.05) * 2.5)
	t.tween_callback(mi.queue_free)


## Two vertices at the muzzle and two at the end of a unit line down -Z (the node scales it to
## the round's length); the shader spreads them sideways to face the camera.
static func tracer_mesh() -> ArrayMesh:
	if _tracer_mesh != null:
		return _tracer_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := [Vector3(0, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, -1), Vector3(0, 0, 0)]
	var uv := [Vector2(0, -1), Vector2(1, -1), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3(0, 0, -1))
		st.set_uv(uv[i])
		st.add_vertex(p[i])
	_tracer_mesh = st.commit()
	return _tracer_mesh


# ---------------------------------------------------------------------------------------------
# Holes
# ---------------------------------------------------------------------------------------------

## A mark where a round went in. Decals on a RenderingDevice renderer, a lit quad elsewhere.
## Returns the node (null when nothing was made).
static func hole(node: Node, at: Vector3, normal: Vector3, surf: int, collider: Object) -> Node3D:
	if Sanctuary.is_sanctuary(collider):
		return null
	var look: Dictionary = WeaponFX.SURFACES[surf]
	if surf == WeaponFX.Surface.FLESH:
		return null
	var host := collider as Node3D
	if host == null or not host.is_inside_tree():
		host = WeaponFX.fx_parent(node) as Node3D
	if host == null:
		return null
	var variant := randi() % VARIANTS
	var pellet := pellet_mode and surf != WeaponFX.Surface.GLASS
	var maps := hole_textures(WeaponFX.Surface.CONCRETE if pellet and surf == WeaponFX.Surface.CONCRETE else surf, variant)
	var w := WeaponFX.bullet_hole_size * float(look["hole_scale"]) * randf_range(0.85, 1.2)
	if pellet:
		w *= pellet_hole_scale
	stats["holes"] = int(stats["holes"]) + 1
	var mark := _mark(host, maps, at, normal, w, bool(look["glass"]), -1.0, surf == WeaponFX.Surface.WOOD)
	if mark != null:
		WeaponFX.keep_hole(mark)
	return mark


## A mark of `maps` ([albedo, normal, orm]) `w` across at `at` on a surface facing `normal`.
static func _mark(host: Node3D, maps: Array, at: Vector3, normal: Vector3, w: float, glass: bool, life: float = -1.0, grain: bool = false) -> Node3D:
	var n: Node3D
	var roll := randf_range(-PI, PI)
	if grain:
		# Along the grain (taken as vertical on a wall, the slope's fall elsewhere): the mark's
		# split runs down its texture's v, which is the basis' z.
		var up := Vector3.UP - normal * normal.dot(Vector3.UP)
		if up.length_squared() > 1e-4:
			var z0 := WeaponFX._basis_up(normal).z
			roll = z0.signed_angle_to(up.normalized(), normal) + randf_range(-0.12, 0.12)
	if RenderingServer.get_rendering_device() != null:
		var decal := Decal.new()
		decal.texture_albedo = maps[0]
		decal.texture_normal = maps[1]
		decal.texture_orm = maps[2]
		if glass:
			decal.texture_emission = maps[0]
			decal.emission_energy = 0.5
		decal.albedo_mix = 1.0
		decal.size = Vector3(w, maxf(w, 0.3), w)
		decal.upper_fade = 0.5
		decal.lower_fade = 0.5
		# No smear down a wall it grazes.
		decal.normal_fade = 0.55
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = 55.0
		decal.distance_fade_length = 18.0
		host.add_child(decal)
		decal.global_transform = Transform3D(WeaponFX._basis_up(normal, roll), at + normal * 0.02)
		n = decal
	else:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(w, w)
		mi.mesh = quad
		mi.material_override = _quad_material(maps, glass)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 50.0
		host.add_child(mi)
		# A quad faces its +Z: turn that onto the normal, rolled, a few millimetres proud.
		var b := WeaponFX._basis_up(normal, roll)
		mi.global_transform = Transform3D(Basis(b.x, -b.z, b.y), at + normal * 0.006)
		n = mi
		stats["quads"] = int(stats["quads"]) + 1
	n.name = "BulletHole"
	n.add_to_group("bullet_hole")
	var hold := WeaponFX.bullet_hole_life if life < 0.0 else life
	var t := n.create_tween()
	t.tween_interval(hold)
	if n is Decal:
		t.tween_property(n, "modulate:a", 0.0, 3.0)
	else:
		t.tween_property(n, "transparency", 1.0, 3.0)
	t.tween_callback(n.queue_free)
	return n


static func _quad_material(maps: Array, glass: bool) -> StandardMaterial3D:
	var key: int = (maps[0] as Object).get_instance_id()
	if _quad_mats.has(key):
		return _quad_mats[key]
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = maps[0]
	mat.normal_enabled = true
	mat.normal_texture = maps[1]
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	if glass:
		mat.emission_enabled = true
		mat.emission_texture = maps[0]
		mat.emission = Color(0.4, 0.42, 0.45)
	_quad_mats[key] = mat
	return mat


## [albedo, normal, orm] for a surface's hole (WeaponFX.Surface), variant 0..VARIANTS-1: the baked
## files (tools/gunplay/make_holes.gd paints them with HoleArt), or painted here if one is missing.
## Kept for the session: they go in the decal atlas (WarmRehearsal.atlas_textures()).
static func hole_textures(surf: int, variant: int) -> Array:
	var key := surf * 16 + variant
	if _holes.has(key):
		return _holes[key]
	var maps := _load_maps(hole_stem(surf, variant))
	if maps.is_empty():
		maps = HoleArt.build(surf, variant, HOLE_PX)
	_holes[key] = maps
	return maps


## The surfaces that have their own marks (flesh has none).
static func baked_surfaces() -> Array:
	return [WeaponFX.Surface.CONCRETE, WeaponFX.Surface.METAL, WeaponFX.Surface.GLASS,
		WeaponFX.Surface.WOOD, WeaponFX.Surface.DIRT]


static func hole_stem(surf: int, variant: int) -> String:
	return "%s_%d" % [String(WeaponFX.Surface.keys()[surf]).to_lower(), variant]


static func _load_maps(stem: String) -> Array:
	var out: Array = []
	for kind in ["albedo", "normal", "orm"]:
		var path := HOLE_DIR + "%s_%s.png" % [stem, kind]
		if not ResourceLoader.exists(path):
			return []
		out.append(load(path))
	return out


## Every hole set, for the atlas keeper and the loading screen.
static func all_hole_textures() -> Array:
	var out: Array = []
	for s in baked_surfaces():
		for v in VARIANTS:
			out.append(hole_textures(s, v))
	out.append(pattern_textures())
	return out


# ---------------------------------------------------------------------------------------------
# The shotgun's pattern
# ---------------------------------------------------------------------------------------------

## Where a shot's pellets went into surfaces: `hits` is [[collider, point, normal], ...]. Three or
## more in one collider get a ring of grey lead smudge round the group; point-blank (closer than
## `muzzle_at` + 2.5 m), a ragged rathole where the charge went in nearly as one.
static func spread_mark(node: Node, muzzle_at: Vector3, hits: Array) -> void:
	var groups := {}
	for h in hits:
		var c: Object = h[0]
		if c == null or not is_instance_valid(c) or Sanctuary.is_sanctuary(c):
			continue
		var surf := WeaponFX.classify(c, h[1], h[2])
		if surf == WeaponFX.Surface.FLESH or surf == WeaponFX.Surface.GLASS:
			continue
		var id := c.get_instance_id()
		if not groups.has(id):
			groups[id] = [c, [], h[2], surf]
		(groups[id][1] as Array).append(h[1])
	for id in groups:
		var g: Array = groups[id]
		var pts: Array = g[1]
		if pts.size() < 3:
			continue
		var mid := Vector3.ZERO
		for p in pts:
			mid += p
		mid /= float(pts.size())
		var r := 0.0
		for p in pts:
			r = maxf(r, (p as Vector3).distance_to(mid))
		var host := g[0] as Node3D
		if host == null or not host.is_inside_tree():
			host = WeaponFX.fx_parent(node) as Node3D
		var n: Vector3 = g[2]
		var d := muzzle_at.distance_to(mid)
		if r > 1.6:
			continue # spread past a smudge: just the pits
		stats["patterns"] = int(stats["patterns"]) + 1
		_mark(host, pattern_textures(), mid, n, clampf(r * 2.4 + 0.25, 0.3, 3.2), false)
		if d < 2.5:
			var maps := hole_textures(int(g[3]), randi() % VARIANTS)
			_mark(host, maps, mid, n, WeaponFX.bullet_hole_size * 2.4, false)


## The pattern's smudge: a soft ring of grey lead and powder, darker in its middle.
static func pattern_textures() -> Array:
	if _pattern_tex.is_empty():
		_pattern_tex = _load_maps("pattern")
	if _pattern_tex.is_empty():
		_pattern_tex = HoleArt.build_pattern(HOLE_PX)
	return _pattern_tex


# ---------------------------------------------------------------------------------------------
# Barrel smoke
# ---------------------------------------------------------------------------------------------

## A lit smoke wisp material (the street light, the next flash and the sun all show on it).
static func smoke_material() -> StandardMaterial3D:
	if _smoke_mat != null:
		return _smoke_mat
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.particles_anim_h_frames = 1
	mat.particles_anim_v_frames = 1
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = WeaponFX.puff_texture()
	mat.roughness = 1.0
	mat.disable_receive_shadows = true
	mat.render_priority = -1
	if not OS.has_feature("web"):
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 0.25
	_smoke_mat = mat
	return mat


## The wisp off a hot barrel: a child of the muzzle, emitting in world space while the barrel is
## hot and the trigger has been off a moment.
class BarrelSmoke extends CPUParticles3D:
	var weapon: Weapon
	var heat: float = 0.0
	var since: float = 10.0

	static func heat_up(w: Weapon) -> void:
		if w.muzzle == null or not w.muzzle.is_inside_tree():
			return
		var s := w.muzzle.get_node_or_null("BarrelSmoke") as BarrelSmoke
		if s == null:
			s = BarrelSmoke.new()
			s.name = "BarrelSmoke"
			s.weapon = w
			w.muzzle.add_child(s)
		s.heat = minf(s.heat + GunplayFeel.heat_per_round * (2.0 if w.fire_rate < 3.0 else 1.0), 1.0)
		s.since = 0.0
		s.set_process(true)

	func _ready() -> void:
		local_coords = false
		amount = 26 if not OS.has_feature("web") else 10
		lifetime = 2.2
		lifetime_randomness = 0.35
		explosiveness = 0.0
		randomness = 0.6
		direction = Vector3.UP
		spread = 18.0
		initial_velocity_min = 0.05
		initial_velocity_max = 0.22
		gravity = Vector3(0.0, 0.55, 0.0)
		damping_min = 0.15
		damping_max = 0.4
		angle_min = -180.0
		angle_max = 180.0
		angular_velocity_min = -25.0
		angular_velocity_max = 25.0
		scale_amount_min = 0.05
		scale_amount_max = 0.09
		var curve := Curve.new()
		curve.max_value = 6.0
		curve.add_point(Vector2(0.0, 0.6))
		curve.add_point(Vector2(0.35, 2.2))
		curve.add_point(Vector2(1.0, 5.5))
		scale_amount_curve = curve
		color_ramp = WeaponFX._ramp([Color(0.78, 0.77, 0.75, 0.0), Color(0.78, 0.77, 0.75, 0.32),
			Color(0.72, 0.71, 0.70, 0.14), Color(0.7, 0.7, 0.7, 0.0)])
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		quad.material = GunplayFeel.smoke_material()
		mesh = quad
		emitting = false
		custom_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 8, 8))

	func _process(delta: float) -> void:
		since += delta
		heat = maxf(heat - GunplayFeel.heat_cool * delta, 0.0)
		# Smokes once the burst is over (the flashes blow it away while it lasts), while hot.
		var on := heat > GunplayFeel.smoke_from_heat and since > 0.12 and is_visible_in_tree()
		# Thicker off a hotter barrel (the wisp's tint; amount restarts a system when set).
		color = Color(1.0, 1.0, 1.0, clampf(heat * 1.6, 0.25, 1.0))
		if on != emitting:
			emitting = on
		if not on and heat <= 0.0 and since > 4.0:
			set_process(false)
			heat = 0.0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
			set_process(true)
