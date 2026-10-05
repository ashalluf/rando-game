class_name BlastAftermath
extends RefCounted
## What a big blast leaves behind (Explosion.blast() calls `blast()` once, after the blast
## itself): a CRATER where it hit the ground - a pit with a broken, pushed-up rim and radial
## cracks, scorched out past it (a Decal with generated albedo and normal on Forward+, the same
## maps on a flat quad on the Compatibility renderer, like the blood marks) - a ring of broken
## asphalt slabs heaved up round it, and RUBBLE thrown out that stays: rigid chunks that are
## PhysicsBudget debris for `rubble_seconds`. Then dust: a low wave of it rolling out along the
## ground past the fireball, and sheets shaken off the roofs round it. Leaves torn off the
## nearest trees (TreeFire's registry says where they stand) flutter down. The crowns closest
## catch fire (TreeFire.blast()) and parked cars' alarms go off (CarAlarm.blast()).
## A car's own blast (`exclude` a Vehicle: the wreck sits on the spot) scorches and throws dust,
## but leaves no pit. Every knob is a static var here; `enabled` false (`BLAST_AFTERMATH=0`)
## turns all of it off.

static var enabled: bool = OS.get_environment("BLAST_AFTERMATH") != "0"
## Crater diameter per metre of blast radius (a rocket's 9 m makes a pit about 3.4 m across),
## and the scorch round it.
static var crater_scale: float = 0.38
static var scorch_scale: float = 1.5
## How long a crater stays before it fades (seconds), and how many at once.
static var crater_seconds: float = 300.0
static var max_craters: int = 14
## Broken slabs heaved up round the rim, per crater.
static var slab_count: int = 14
## Rigid rubble thrown out per blast, how long it stays, and the most at once.
static var rubble_count: int = 9
static var rubble_seconds: float = 180.0
static var max_rubble: int = 60
## Ground wave: reach in blast radii.
static var dust_wave_reach: float = 3.2
## Roofs within this many blast radii shed dust (rays from above), at most `roof_puffs`.
static var roof_reach: float = 4.0
static var roof_puffs: int = 5
## Trees within this many blast radii of the centre (crown edge) lose leaves, at most
## `leaf_trees` of them, `leaves_per_tree` leaves at the nearest.
static var leaf_reach: float = 3.2
static var leaf_trees: int = 6
static var leaves_per_tree: int = 46

static var _craters: Array = []
static var _rubble: Array = []
static var _crater_tex: Array = []
static var _mark_mat: StandardMaterial3D
static var _slab_mesh: ArrayMesh
static var _rubble_meshes: Array = []
static var _leaf_mat: StandardMaterial3D
static var _frond_mat: StandardMaterial3D


static func blast(node: Node, at: Vector3, radius: float, launch: float, exclude: Object = null) -> void:
	if not enabled or node == null or not node.is_inside_tree():
		return
	var tree := node.get_tree()
	var sanctuary := Sanctuary.contains(tree, at, radius)
	var own_car := exclude is Vehicle
	if not sanctuary:
		var ground := _ground_under(node, at, radius)
		if not ground.is_empty():
			crater(node, ground.position, ground.normal, radius, not own_car)
			if not own_car:
				_rubble_burst(node, ground.position, ground.normal, radius, launch)
		_dust_wave(node, at, radius, ground)
		_roof_dust(node, at, radius)
		TreeFire.blast(node, at, radius)
	_leaves(node, at, radius)
	CarAlarm.blast(tree, at, radius)


## The ground the blast sat on, if it was close enough to mark it: {position, normal} or {}.
static func _ground_under(node: Node, at: Vector3, radius: float) -> Dictionary:
	var space := WeaponFX._space(node)
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at - Vector3.UP * radius * 0.45, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.55:
		return {}
	return hit


# --- The crater --------------------------------------------------------------------------------

## A crater (and its scorch) at `at` on a surface facing `normal`; `pit` false for the scorch
## alone. Returns the mark node.
static func crater(node: Node, at: Vector3, normal: Vector3, radius: float, pit: bool = true) -> Node3D:
	var parent := WeaponFX.fx_parent(node)
	var size := radius * (crater_scale if pit else 0.0) + radius * scorch_scale * 0.5
	var mark := Node3D.new()
	mark.name = "BlastCrater"
	parent.add_child(mark)
	var basis := WeaponFX._basis_up(normal, randf() * TAU)
	mark.global_transform = Transform3D(basis, at)
	var maps := crater_textures(0 if pit else 1)
	if WeaponFX._decals():
		var d := Decal.new()
		d.texture_albedo = maps[0]
		d.texture_normal = maps[1]
		d.normal_fade = 0.4
		d.size = Vector3(size * 2.0, 2.4, size * 2.0)
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.cull_mask = 1
		mark.add_child(d)
	else:
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(size * 2.0, size * 2.0)
		q.mesh = pm
		q.material_override = mark_material(maps, pit)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.position = Vector3(0.0, 0.025, 0.0)
		mark.add_child(q)
	if pit:
		_heave_slabs(mark, radius * crater_scale * 0.5)
	_craters.append(mark)
	_trim_craters()
	var tw := mark.create_tween()
	tw.tween_interval(crater_seconds)
	tw.tween_callback(mark.queue_free)
	return mark


static func _trim_craters() -> void:
	_craters = _craters.filter(func(c): return is_instance_valid(c) and not c.is_queued_for_deletion())
	while _craters.size() > max_craters:
		var old: Node = _craters.pop_front()
		old.queue_free()


static func crater_count() -> int:
	_craters = _craters.filter(func(c): return is_instance_valid(c) and not c.is_queued_for_deletion())
	return _craters.size()


static func rubble_count_now() -> int:
	_rubble = _rubble.filter(func(c): return is_instance_valid(c) and not c.is_queued_for_deletion())
	return _rubble.size()


## The Compatibility renderer's stand-in for the decal: a lit, cut-out quad with the same maps.
static func mark_material(maps: Array, pit: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = maps[0]
	m.normal_enabled = true
	m.normal_texture = maps[1]
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.93
	m.render_priority = -2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.resource_name = "crater_pit" if pit else "crater_scorch"
	return m


## Broken asphalt heaved up round the pit: wedges of the road's own surface tipped outward and
## half sunk, in one MultiMesh under the mark.
static func _heave_slabs(mark: Node3D, pit_r: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = slab_mesh()
	var n := slab_count
	mm.instance_count = n
	var start := randf() * TAU
	for i in n:
		var a := start + TAU * (float(i) + randf_range(-0.3, 0.3)) / float(n)
		var dist := pit_r * randf_range(0.85, 1.25)
		var out := Vector3(cos(a), 0.0, sin(a))
		var s := randf_range(0.7, 1.35) * clampf(pit_r / 1.7, 0.5, 1.4)
		# Tipped up on the side toward the pit, the outer edge sunk in the road.
		var b := Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, deg_to_rad(randf_range(12.0, 38.0)))
		b = b * Basis(Vector3.UP, randf_range(-0.5, 0.5))
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3(s, s, s)), out * dist + Vector3(0.0, 0.02, 0.0)))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Slabs"
	mi.multimesh = mm
	mi.visibility_range_end = 160.0
	mark.add_child(mi)


## One broken slab of road: an irregular prism, its top the asphalt, its sides the lighter
## crushed base course under it. Unit-ish (about 0.6 m across, 9 cm thick).
static func slab_mesh() -> ArrayMesh:
	if _slab_mesh != null:
		return _slab_mesh
	_slab_mesh = _chunk_mesh(7, Vector3(0.62, 0.09, 0.5), 11, Color(0.11, 0.105, 0.1), Color(0.34, 0.31, 0.27))
	return _slab_mesh


## An irregular polygon of `sides` extruded `size.y` thick: top `top` colour, sides `side`.
static func _chunk_mesh(sides: int, size: Vector3, seed_: int, top: Color, side: Color) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var ring: Array[Vector2] = []
	for i in sides:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(sides)
		var r := rng.randf_range(0.6, 1.0)
		ring.append(Vector2(cos(a) * size.x * 0.5 * r, sin(a) * size.z * 0.5 * r))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var h := size.y
	var top_y: Array[float] = []
	for i in sides:
		top_y.append(h * rng.randf_range(0.75, 1.0))
	# Top fan (facing up).
	for i in sides:
		var j := (i + 1) % sides
		st.set_color(top)
		st.add_vertex(Vector3(0.0, h, 0.0))
		st.set_color(top)
		st.add_vertex(Vector3(ring[j].x, top_y[j], ring[j].y))
		st.set_color(top)
		st.add_vertex(Vector3(ring[i].x, top_y[i], ring[i].y))
	# Sides.
	for i in sides:
		var j := (i + 1) % sides
		var a0 := Vector3(ring[i].x, 0.0, ring[i].y)
		var a1 := Vector3(ring[j].x, 0.0, ring[j].y)
		var b0 := Vector3(ring[i].x, top_y[i], ring[i].y)
		var b1 := Vector3(ring[j].x, top_y[j], ring[j].y)
		for v: Vector3 in [a0, b0, b1, a0, b1, a1]:
			st.set_color(side)
			st.add_vertex(v)
	# Bottom.
	for i in sides:
		var j := (i + 1) % sides
		for v: Vector3 in [Vector3.ZERO, Vector3(ring[i].x, 0.0, ring[i].y), Vector3(ring[j].x, 0.0, ring[j].y)]:
			st.set_color(side)
			st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	mesh.surface_set_material(0, m)
	return mesh


## The crater's maps, made once: [albedo (alpha the coverage), normal]. Kind 0 the pit with its
## scorch, 1 the scorch alone. 256 px, a few tens of ms each, warmed on the loading screen.
static func crater_textures(kind: int = 0) -> Array:
	if _crater_tex.size() > kind and _crater_tex[kind] != null:
		return _crater_tex[kind]
	while _crater_tex.size() <= kind:
		_crater_tex.append(null)
	var n := 256
	var rng := RandomNumberGenerator.new()
	rng.seed = 4011 + kind
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 91 + kind
	noise.frequency = 0.045
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var fine := FastNoiseLite.new()
	fine.noise_type = FastNoiseLite.TYPE_VALUE
	fine.seed = 7
	fine.frequency = 0.5
	# Radial cracks: angles and lengths.
	var cracks: Array = []
	for i in 13:
		cracks.append([rng.randf() * TAU, rng.randf_range(0.45, 0.95), rng.randf_range(0.004, 0.012)])
	# Where the pit's edge sits in the texture's radius (the rest is scorch).
	var total := crater_scale + scorch_scale * 0.5
	var pit_r := crater_scale * 0.5 / total if kind == 0 else 0.0
	var height := PackedFloat32Array()
	height.resize(n * n)
	var alb := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var ang := atan2(v, u)
			var nz := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var fz := fine.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			# Ragged edge of the whole mark.
			var edge := 0.78 + 0.2 * nz
			var cover := 1.0 - smoothstep(edge * 0.7, edge, r)
			var hgt := 0.0
			var col := Color(0.05, 0.045, 0.04)
			# Scorch: soot streaks running out from the centre, thinning outward.
			var streak := 0.55 + 0.45 * sin(ang * 23.0 + nz * 6.0) * sin(ang * 9.0 - nz * 3.0)
			var soot := clampf((1.0 - r / edge) * 1.6, 0.0, 1.0) * (0.55 + 0.45 * streak)
			var a := cover * clampf(soot * 1.3, 0.0, 0.95)
			col = Color(0.035, 0.032, 0.03).lerp(Color(0.09, 0.08, 0.07), fz * 0.6)
			if pit_r > 0.0:
				var pr := pit_r * (0.9 + 0.2 * nz)
				if r < pr:
					# The pit: blown out to the base course, pale crushed stone and dirt,
					# blackened at the very centre.
					var k := r / pr
					hgt = -(1.0 - k * k) * 1.0
					var stone := Color(0.30, 0.27, 0.23).lerp(Color(0.20, 0.17, 0.14), fz)
					col = stone.lerp(Color(0.05, 0.045, 0.04), clampf(1.0 - k * 1.6, 0.0, 1.0) * 0.8)
					a = 1.0
				elif r < pr * 1.45:
					# The rim: broken asphalt pushed up, chunky.
					var k2 := (r - pr) / (pr * 0.45)
					hgt = sin(k2 * PI) * (0.55 + 0.45 * fz)
					col = Color(0.07, 0.066, 0.062).lerp(Color(0.16, 0.15, 0.14), 1.0 if fz > 0.62 else 0.0)
					a = 1.0
				# Cracks running out from the rim.
				for c: Array in cracks:
					var da := absf(wrapf(ang - float(c[0]), -PI, PI))
					var wob := (nz - 0.5) * 0.08
					var reach: float = float(c[1])
					if r > pr and r < pr + reach * (edge - pr) and absf(da - wob) * r < float(c[2]) * (1.4 - r):
						col = Color(0.015, 0.014, 0.013)
						hgt -= 0.35
						a = maxf(a, 0.95 * cover)
			height[y * n + x] = hgt
			alb.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))
	var nrm := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var depth := 6.0
	for y in n:
		for x in n:
			var hl := height[y * n + maxi(x - 1, 0)]
			var hr := height[y * n + mini(x + 1, n - 1)]
			var hd := height[maxi(y - 1, 0) * n + x]
			var hu := height[mini(y + 1, n - 1) * n + x]
			var nv := Vector3((hl - hr) * depth, (hd - hu) * depth, 1.0).normalized()
			nrm.set_pixel(x, y, Color(nv.x * 0.5 + 0.5, nv.y * 0.5 + 0.5, nv.z * 0.5 + 0.5, 1.0))
	alb.generate_mipmaps()
	nrm.generate_mipmaps()
	var out := [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(nrm)]
	_crater_tex[kind] = out
	return out


## The loading screen's warm-up: the maps and meshes, so the first rocket does not build them.
static func warm() -> Array:
	var maps := crater_textures(0)
	crater_textures(1)
	slab_mesh()
	_rubble_mesh(0)
	return [leaf_material(false), leaf_material(true), mark_material(maps, true),
		slab_mesh().surface_get_material(0)]


# --- Rubble ------------------------------------------------------------------------------------

static func _rubble_mesh(i: int) -> ArrayMesh:
	while _rubble_meshes.size() < 3:
		var k := _rubble_meshes.size()
		_rubble_meshes.append(_chunk_mesh(5 + k, Vector3(0.34, 0.11, 0.27), 101 + k,
			Color(0.10, 0.095, 0.09), Color(0.32, 0.29, 0.25)))
	return _rubble_meshes[i % 3]


## Chunks of road and kerb thrown out of the pit; they bounce, settle, and stay for minutes.
static func _rubble_burst(node: Node, at: Vector3, normal: Vector3, radius: float, launch: float) -> void:
	if not PhysicsBudget.make_room(rubble_count):
		return
	_rubble = _rubble.filter(func(c): return is_instance_valid(c) and not c.is_queued_for_deletion())
	var parent := WeaponFX.fx_parent(node)
	var n := rubble_count if not WeaponFX._web() else maxi(3, rubble_count / 2)
	for i in n:
		while _rubble.size() >= max_rubble:
			var old: Node = _rubble.pop_front()
			if is_instance_valid(old):
				old.queue_free()
		var b := RigidBody3D.new()
		b.name = "Rubble"
		b.collision_layer = 1 << 2
		b.collision_mask = 1 | (1 << 2)
		var s := randf_range(0.6, 1.5)
		b.mass = 6.0 * s * s * s
		var mi := MeshInstance3D.new()
		mi.mesh = _rubble_mesh(i)
		mi.scale = Vector3.ONE * s
		mi.visibility_range_end = 120.0
		b.add_child(mi)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.3, 0.1, 0.24) * s
		cs.shape = box
		cs.position = Vector3(0.0, 0.05 * s, 0.0)
		b.add_child(cs)
		parent.add_child(b)
		var a := randf() * TAU
		var out := Vector3(cos(a), 0.0, sin(a))
		b.global_position = at + out * radius * 0.12 + normal * 0.25
		b.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var speed := clampf(launch * 0.35, 6.0, 18.0) * randf_range(0.5, 1.0)
		b.linear_velocity = (out + normal * randf_range(0.8, 1.8)).normalized() * speed
		b.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
		PhysicsBudget.register_debris(b, rubble_seconds)
		_rubble.append(b)


# --- Dust ---------------------------------------------------------------------------------------

## The shock rolling out along the ground past the fireball: a low, wide ring of street dust,
## slower and paler than WeaponFX's skirt, still going after the fire is gone.
static func _dust_wave(node: Node, at: Vector3, radius: float, ground: Dictionary) -> void:
	if ground.is_empty():
		return
	var parent := WeaponFX.fx_parent(node)
	var ramp := WeaponFX._ramp([Color(0.46, 0.42, 0.37, 0.0), Color(0.42, 0.39, 0.35, 0.34),
		Color(0.38, 0.36, 0.32, 0.22), Color(0.33, 0.31, 0.29, 0.0)])
	var reach := radius * dust_wave_reach
	WeaponFX._puff_layer(parent, (ground.position as Vector3) + Vector3.UP * 0.35, WeaponFX._count(30),
			radius * 0.5, 3.4, reach * 0.55, reach * 0.9, 0.4, ramp, false, 180.0, 2.8,
			WeaponFX._basis_up(ground.normal), 1.0, 0.4, 1.6, true)


## Dust shaken off the roofs round the blast: a ray down onto each of a ring of points; where it
## lands on a roof above the blast, a sheet of dust lifts off it and spills over.
static func _roof_dust(node: Node, at: Vector3, radius: float) -> void:
	if WeaponFX._web():
		return
	var space := WeaponFX._space(node)
	if space == null:
		return
	var parent := WeaponFX.fx_parent(node)
	var ramp := WeaponFX._ramp([Color(0.5, 0.47, 0.42, 0.0), Color(0.46, 0.43, 0.39, 0.42),
		Color(0.40, 0.38, 0.35, 0.25), Color(0.36, 0.34, 0.32, 0.0)])
	var made := 0
	var rays := 12
	var start := randf() * TAU
	for i in rays:
		if made >= roof_puffs:
			break
		var a := start + TAU * float(i) / float(rays)
		var d := radius * lerpf(1.0, roof_reach, float(i % 3) / 2.0)
		var p := at + Vector3(cos(a) * d, 0.0, sin(a) * d)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 90.0, p + Vector3.DOWN * 2.0, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit.normal as Vector3).y < 0.8:
			continue
		var top: Vector3 = hit.position
		if top.y < at.y + 3.0:
			continue
		made += 1
		var away := Vector3(cos(a), 0.0, sin(a))
		# Lifted and pushed away from the blast, then sinking over the edge.
		WeaponFX._puff_layer(parent, top + Vector3.UP * 0.3, WeaponFX._count(12), radius * 0.35, 3.0,
				radius * 0.4, radius * 1.1, -1.4, ramp, false, 50.0, 2.6,
				WeaponFX._basis_up((away + Vector3.UP * 0.5).normalized()), 0.0, 0.4, 1.4, true)
		# Grit pattering down off it.
		WeaponFX._chip_layer(parent, top + Vector3.UP * 0.2, WeaponFX._count(10), 0.05, 1.8,
				1.0, 3.5, Color(0.22, 0.2, 0.18), WeaponFX._basis_up(away), 70.0, -18.0)


# --- Leaves -------------------------------------------------------------------------------------

## The nearest trees shed leaves (palms, shreds of frond), thrown away from the blast and
## fluttering down for several seconds.
static func _leaves(node: Node, at: Vector3, radius: float) -> void:
	var parent := WeaponFX.fx_parent(node)
	var hits := TreeFire.trees_near(at, radius * leaf_reach)
	var made := 0
	for hit: Array in hits:
		if made >= leaf_trees:
			break
		var rec: Dictionary = hit[0]
		var t: Dictionary = hit[1]
		if TreeFire.is_charred(rec, t):
			continue
		var crown := WorldState.to_local(t.crown)
		if absf(crown.y - at.y) > float(t.r) + radius * 2.5 + 4.0:
			continue
		var k := 1.0 - clampf(float(hit[2]) / maxf(radius * leaf_reach, 0.01), 0.0, 1.0)
		var count := WeaponFX._count(maxi(6, int(leaves_per_tree * (0.3 + 0.7 * k))))
		var away := crown - at
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
		leaf_burst(parent, crown, float(t.r), away, k, t.palm, count)
		made += 1


## One tree's leaves torn off: from its crown (radius `r`), pushed along `away` by `push` (0..1).
static func leaf_burst(parent: Node, crown: Vector3, r: float, away: Vector3, push: float, palm: bool, count: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Leaves"
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = maxi(1, count)
	p.lifetime = 7.5
	p.lifetime_randomness = 0.35
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = r * 0.8
	p.direction = (away + Vector3.UP * 0.6).normalized()
	p.spread = 55.0
	p.initial_velocity_min = 2.0 + 5.0 * push
	p.initial_velocity_max = 4.0 + 11.0 * push
	# Leaves fall slowly: heavy drag, light gravity, a slow spin.
	p.gravity = Vector3(0.0, -2.4, 0.0)
	p.damping_min = 2.5
	p.damping_max = 4.5
	p.angular_velocity_min = -260.0
	p.angular_velocity_max = 260.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var g := Gradient.new()
	if palm:
		g.set_color(0, Color(0.42, 0.45, 0.24))
		g.set_color(1, Color(0.58, 0.5, 0.32))
	else:
		g.set_color(0, Color(0.26, 0.38, 0.15))
		g.set_color(1, Color(0.55, 0.5, 0.24))
	p.color_initial_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.42) if palm else Vector2(0.11, 0.15)
	q.material = leaf_material(palm)
	p.mesh = q
	p.custom_aabb = AABB(Vector3(-60.0, -40.0, -60.0), Vector3(120.0, 70.0, 120.0))
	parent.add_child(p)
	p.global_position = crown
	p.restart()
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime * 1.4 + 0.5)
	tw.tween_callback(p.queue_free)
	return p


## A leaf (or a shred of palm frond): lit, both sides, cut out of a generated shape, tinted by the
## particle colour.
static func leaf_material(palm: bool) -> StandardMaterial3D:
	if palm and _frond_mat:
		return _frond_mat
	if not palm and _leaf_mat:
		return _leaf_mat
	var w := 32
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (float(x) + 0.5) / float(w) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(h)
			# A leaf: widest a third of the way up, pointed at the tip; a frond shred is a strap.
			var half := (sin(v * PI) * (1.0 - 0.35 * v)) if not palm else (0.55 - 0.2 * absf(v - 0.5))
			var inside := absf(u) < half * 0.92
			var rib := 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.08, absf(u)))
			var vein := 0.92 + 0.08 * sin((v * 9.0 + absf(u) * 4.0) * PI)
			var shade := rib * vein
			img.set_pixel(x, y, Color(shade, shade, shade, 1.0 if inside else 0.0))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.roughness = 0.8
	m.backlight_enabled = true
	m.backlight = Color(0.35, 0.4, 0.15)
	if palm:
		_frond_mat = m
	else:
		_leaf_mat = m
	return m
