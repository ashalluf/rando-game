class_name BlastFX
extends RefCounted
## The second pass on the explosion (fleet wave 3, "explosions-2": "take the rocket / car
## explosion to GTA 6 level, frame by frame"). WeaponFX.explosion() still lays the fireball, the
## sparks, the embers, the ring, the chips, the dust and the scorch; this adds what a big-budget
## blast has on top, frame by frame:
##   0.00 s  a blinding flash: a white-hot flare, a light four times the old one's that reaches
##           the facades across the street, and on the player's screen a flash that fades in a
##           tenth of a second.
##   0.02 s  the pressure wave: a shell of bent air racing out over the street (it reads the
##           screen, so desktop only) and a fast low ring of dust and grit kicked off the ground.
##   0.05 s  the fireball rolls UP: fire puffs thrown upward, slowed by drag, growing and cooling
##           to soot as they climb (fire_puff.gdshader now shades its billows by their own relief).
##   0.1 s   burning debris arcs out, each piece trailing flame and smoke (BlastDebris), and the
##           windows facing the blast across the street blow out (BuildingDamage's own records).
##   0.4 s+  the mushroom: a cap of dark smoke rising off the fire and a column feeding it for
##           `column_emit` seconds, every puff LIT (blast_smoke.gdshader: the sun on its billows,
##           the sky under it, the fire under it while it burns), rising and spreading for 10-20 s.
## A car's own explosion (CarDamage.explode) sets `fuel_next`: a bigger, taller fuel fireball and a
## higher toss (`car_lift_gain`).
## Caps: `max_heavy` blasts in `heavy_window` seconds get the column, debris and glass; past that a
## blast is the old one plus the flash and the wave. `max_columns`, `max_debris` pieces,
## `max_glass_panes` a blast. EXPLOSIONS_2=0 in the environment is the A/B (the old blast alone).

static var enabled: bool = OS.get_environment("EXPLOSIONS_2") != "0"

## The flash: light energy at its peak, its reach in blast radii, how long it holds.
static var flash_energy: float = 60.0
static var flash_reach: float = 7.0
static var flash_time: float = 0.06
## The fire's glow after the flash (a flickering light that dies with the fireball).
static var glow_energy: float = 9.0
static var glow_time: float = 2.4
## The screen flash at the player's eye: its peak (0..1) and how many radii away it is gone.
static var screen_flash: float = 0.55
static var screen_flash_reach: float = 10.0
## The pressure wave: how far (radii) the shell runs and how long it takes.
static var wave_reach: float = 4.5
static var wave_seconds: float = 0.42
static var wave_strength: float = 0.035
## The smoke column: seconds it is fed, each puff's life, how fast it rises.
static var column_emit: float = 10.0
static var column_life: float = 15.0
static var column_rise: float = 4.2
static var max_columns: int = 3
## Burning debris thrown out (pieces a blast, and alive at once).
static var debris_pieces: int = 7
static var max_debris: int = 24
## Windows blown out: how far (radii) and how many panes a blast.
static var glass_reach: float = 2.4
static var max_glass_panes: int = 18
static var glass_bursts: int = 6
## A car's own explosion: the toss is this much higher (CarDamage.explode).
static var car_lift_gain: float = 1.45
## How many blasts in `heavy_window` seconds get the whole thing.
static var max_heavy: int = 3
static var heavy_window: float = 2.5
## Set by CarDamage.explode() just before its blast: that one is a fuel fireball.
static var fuel_next: bool = false

static var _recent: Array[float] = []
static var _columns: Array = []
static var _flash_layer: CanvasLayer
static var _flash_rect: ColorRect
static var _flash_tween: Tween
static var _smoke_mat: ShaderMaterial
static var _wave_mat_shader: Shader
static var _flare_mat: StandardMaterial3D
static var _ground_ramp: Gradient
## What the last blast made (the checks read it): layer name -> count.
static var last: Dictionary = {}


## Everything above, at `at` (global) of `radius`; `power` 1 is a rocket. Called last thing in
## WeaponFX.explosion().
static func explosion(node: Node, at: Vector3, radius: float, power: float = 1.0) -> void:
	var fuel := fuel_next
	fuel_next = false
	if not enabled or node == null or not node.is_inside_tree():
		return
	var parent := WeaponFX.fx_parent(node)
	if parent == null:
		return
	last = {}
	var heavy := _take_heavy(node)
	var push := clampf(power, 0.5, 2.0)
	var big := radius * (1.25 if fuel else 1.0)
	(WeaponFX._fire_material() as Material).set("shader_parameter/relief", 0.75)
	_flash(node, parent, at, big)
	_screen_flash(node, at, big)
	if not WeaponFX._web():
		_pressure_wave(parent, at, big)
	_ground_kick(node, parent, at, big, push)
	_fire_roll(parent, at, big, fuel)
	if heavy:
		_column(parent, at, big, fuel)
		last["debris"] = BlastDebris.spawn(node, parent, at, big, push, mini(debris_pieces + (3 if fuel else 0), max_debris))
		last["glass"] = _glass(node, at, radius)
	last["heavy"] = heavy


## True while fewer than `max_heavy` blasts went off in the last `heavy_window` seconds.
static func _take_heavy(node: Node) -> bool:
	var now := Time.get_ticks_msec() * 0.001
	while not _recent.is_empty() and now - _recent[0] > heavy_window:
		_recent.pop_front()
	if _recent.size() >= max_heavy:
		return false
	_recent.append(now)
	return true


# --- 0.00 s: the flash --------------------------------------------------------------------------

static func _flash(node: Node, parent: Node, at: Vector3, radius: float) -> void:
	var light := OmniLight3D.new()
	light.name = "BlastFlash"
	light.light_color = Color(1.0, 0.86, 0.66)
	light.light_energy = flash_energy
	light.omni_range = radius * flash_reach
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 2.0
	parent.add_child(light)
	light.global_position = at + Vector3.UP * radius * 0.45
	var lt := light.create_tween()
	lt.tween_interval(flash_time * 0.4)
	lt.tween_property(light, "light_energy", glow_energy, flash_time).set_ease(Tween.EASE_OUT)
	lt.parallel().tween_property(light, "light_color", Color(1.0, 0.55, 0.22), flash_time * 3.0)
	lt.parallel().tween_property(light, "omni_range", radius * flash_reach * 0.6, flash_time * 3.0)
	# The fire's own glow: it flickers as the fireball rolls and dies with it.
	lt.tween_method(func(t: float):
		if is_instance_valid(light):
			var f := 0.82 + 0.18 * sin(t * 61.0) * sin(t * 23.0 + 1.3)
			light.light_energy = glow_energy * pow(1.0 - t, 1.6) * f
			light.global_position = at + Vector3.UP * radius * (0.45 + 0.9 * t),
		0.0, 1.0, glow_time)
	lt.tween_callback(light.queue_free)
	# The white-hot flare: one additive billboard several radii across, gone in a tenth of a
	# second. It is what the eye sees as "too bright to look at" before the fireball has a shape.
	var flare := MeshInstance3D.new()
	flare.name = "BlastFlare"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	flare.mesh = quad
	flare.material_override = _flare_material()
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(flare)
	flare.global_position = at + Vector3.UP * radius * 0.3
	flare.scale = Vector3.ONE * radius * 2.2
	var ft := flare.create_tween()
	ft.tween_property(flare, "scale", Vector3.ONE * radius * 4.2, 0.09).set_ease(Tween.EASE_OUT)
	ft.parallel().tween_property(flare, "transparency", 1.0, 0.13).set_ease(Tween.EASE_IN)
	ft.tween_callback(flare.queue_free)
	last["flash"] = 1


static func _flare_material() -> StandardMaterial3D:
	if _flare_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.no_depth_test = false
		m.albedo_texture = WeaponFX.flare_texture()
		# HDR on purpose (the glow pass blooms it), held toward yellow-white: AgX takes a bright
		# red-heavy colour to salmon.
		m.albedo_color = Color(7.0, 6.0, 4.6, 1.0)
		m.disable_receive_shadows = true
		m.render_priority = 2
		_flare_mat = m
	return _flare_mat


## A flash over the whole picture when the blast is near the player's eye and in front of it.
## One ColorRect under the HUD (layer -1, the vignette's), added to the picture.
static func _screen_flash(node: Node, at: Vector3, radius: float) -> void:
	var cam := WeaponFX._camera(node)
	if cam == null:
		return
	var to := at - cam.global_position
	var d := to.length()
	var near := clampf(1.0 - d / (radius * screen_flash_reach), 0.0, 1.0)
	var facing := clampf(to.normalized().dot(-cam.global_basis.z) * 0.5 + 0.5, 0.0, 1.0) if d > 0.01 else 1.0
	var peak := screen_flash * near * near * (0.35 + 0.65 * facing)
	if peak < 0.02:
		return
	var tree := node.get_tree()
	if _flash_layer == null or not is_instance_valid(_flash_layer):
		_flash_layer = CanvasLayer.new()
		_flash_layer.name = "BlastScreenFlash"
		_flash_layer.layer = -1
		_flash_rect = ColorRect.new()
		_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash_rect.color = Color(1.0, 0.9, 0.75, 0.0)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_flash_rect.material = mat
		_flash_layer.add_child(_flash_rect)
		tree.root.add_child(_flash_layer)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color.a = maxf(_flash_rect.color.a, peak)
	_flash_tween = _flash_rect.create_tween()
	_flash_tween.tween_interval(0.03)
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	last["screen_flash"] = peak


# --- 0.02 s: the pressure wave ------------------------------------------------------------------

## A shell of bent air racing out. A sphere whose rim refracts what is behind it, drawn first
## among the transparent things (it reads the screen; see WeaponFX._shimmer's note), gone by
## `wave_seconds`.
static func _pressure_wave(parent: Node, at: Vector3, radius: float) -> void:
	if _wave_mat_shader == null:
		_wave_mat_shader = preload("res://shaders/blast_wave.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = _wave_mat_shader
	mat.set_shader_parameter("strength", wave_strength)
	mat.set_shader_parameter("fade", 1.0)
	mat.render_priority = Material.RENDER_PRIORITY_MIN
	var mesh := MeshInstance3D.new()
	mesh.name = "BlastWave"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	mesh.mesh = sphere
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_position = at
	mesh.scale = Vector3.ONE * radius * 0.4
	var t := mesh.create_tween()
	t.tween_property(mesh, "scale", Vector3(1.0, 0.7, 1.0) * radius * wave_reach, wave_seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.parallel().tween_property(mat, "shader_parameter/fade", 0.0, wave_seconds).set_ease(Tween.EASE_IN)
	t.tween_callback(mesh.queue_free)
	last["wave"] = 1


## The wave on the ground: a fast low ring of dust and a spray of grit, faster and lower than
## WeaponFX's skirt (which is the slow billow after it).
static func _ground_kick(node: Node, parent: Node, at: Vector3, radius: float, push: float) -> void:
	var space := WeaponFX._space(node)
	if space == null:
		return
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * radius * 0.4, at - Vector3.UP * radius * 1.2, 1))
	if hit.is_empty():
		return
	var ground: Vector3 = hit.position
	var gb := WeaponFX._basis_up(hit.normal)
	if _ground_ramp == null:
		# Linear albedo for the lit smoke material: street dust, lit by the sun or left dark at night.
		_ground_ramp = WeaponFX._ramp([Color(0.22, 0.20, 0.17, 0.0), Color(0.20, 0.18, 0.16, 0.55),
			Color(0.17, 0.16, 0.14, 0.25), Color(0.14, 0.13, 0.12, 0.0)])
	WeaponFX._puff_layer(parent, ground + Vector3.UP * 0.25, WeaponFX._count(28), radius * 0.28, 0.9,
		radius * 3.4 * push, radius * 5.0 * push, 0.4, _ground_ramp, false, 180.0, 3.4,
		gb, 1.0, 0.3, 2.2, true, null, smoke_material())
	# Grit: lit dark chips skimming out low along the ground.
	WeaponFX._chip_layer(parent, ground + Vector3.UP * 0.2, WeaponFX._count(26), 0.06, 0.8,
		radius * 2.0 * push, radius * 4.0 * push, Color(0.20, 0.19, 0.17), gb, 80.0, -22.0)
	last["kick"] = 1


# --- 0.05 s: the fireball rolls up --------------------------------------------------------------

## Fire puffs thrown UP out of the fireball, slowed by drag so they bunch into a rolling cap, and
## cooling through orange to soot as they climb: the fire_puff shader turns a spent puff black at
## its thin edges, so the rising mass reads as fire turning into smoke.
static func _fire_roll(parent: Node, at: Vector3, radius: float, fuel: bool) -> void:
	var n := WeaponFX._count(26 if fuel else 18)
	var rise := radius * (1.55 if fuel else 1.2)
	var p := WeaponFX._puff_layer(parent, at + Vector3.UP * radius * 0.25, n, radius * 0.5, 1.7,
		rise * 0.55, rise * 1.1, 4.0,
		WeaponFX._ramp([Color(4.2, 3.2, 2.0, 1.0), Color(2.2, 0.85, 0.18, 1.0), Color(1.0, 0.30, 0.06, 0.95),
			Color(0.30, 0.09, 0.03, 0.8), Color(0.06, 0.05, 0.045, 0.0)]), false, 38.0, 2.4,
		Basis(), 0.0, 0.4, 1.5, false,
		WeaponFX._ramp([Color(1.4, 1.3, 1.1), Color(1.0, 1.0, 1.0), Color(0.5, 0.38, 0.3)]), WeaponFX._fire_material())
	p.name = "BlastFireRoll"
	last["roll"] = n


# --- 0.4 s on: the mushroom -----------------------------------------------------------------------

static func smoke_material() -> ShaderMaterial:
	if _smoke_mat == null:
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/blast_smoke.gdshader")
		m.set_shader_parameter("puff_tex", WeaponFX.puff_texture())
		# Drawn before the fire (the old smoke's rule), so it never veils the fireball.
		m.render_priority = -1
		_smoke_mat = m
	return _smoke_mat


## The cap and the column. Both are lit puffs in the column node's own space (local_coords), so
## an origin re-centre carries them; the column node shifts with the scene like everything else.
static func _column(parent: Node, at: Vector3, radius: float, fuel: bool) -> void:
	_prune_columns()
	while _columns.size() >= max_columns:
		var old: Node = _columns.pop_front()
		if is_instance_valid(old):
			for c in old.get_children():
				if c is CPUParticles3D:
					(c as CPUParticles3D).emitting = false
	var holder := Node3D.new()
	holder.name = "BlastColumn"
	parent.add_child(holder)
	holder.global_position = at
	_columns.append(holder)
	var sc := radius / 9.0 * (1.3 if fuel else 1.0)
	var mat := smoke_material()
	# The cap: one burst of big puffs thrown up hard and braked by drag, so they pile up a couple
	# of radii over the blast and spread there while the column rises into them.
	var cap := _smoke_emitter(holder, WeaponFX._count(24), column_life + 4.0, mat)
	cap.name = "Cap"
	cap.explosiveness = 0.9
	cap.one_shot = true
	cap.position = Vector3.UP * radius * 0.6
	cap.direction = Vector3.UP
	cap.spread = 28.0
	cap.initial_velocity_min = 13.0 * sc
	cap.initial_velocity_max = 22.0 * sc
	cap.damping_min = 4.0 * sc
	cap.damping_max = 6.0 * sc
	cap.gravity = Vector3(0.35, 0.9, 0.15) * sc
	cap.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	cap.emission_sphere_radius = radius * 0.4
	_scale_curve(cap, radius * 0.75, radius * 0.95, 3.4)
	cap.color_ramp = WeaponFX._ramp([Color(0.05, 0.045, 0.04, 0.0), Color(0.06, 0.05, 0.045, 0.9),
		Color(0.07, 0.065, 0.06, 0.85), Color(0.09, 0.085, 0.08, 0.6), Color(0.10, 0.10, 0.10, 0.0)])
	# The column: puffs off the fire, rising at `column_rise` and growing, fed for `column_emit` s.
	var col := _smoke_emitter(holder, WeaponFX._count(int(column_life * 9.0)), column_life, mat)
	col.name = "Stem"
	col.explosiveness = 0.0
	col.one_shot = false
	col.position = Vector3.UP * radius * 0.2
	col.direction = Vector3.UP
	col.spread = 14.0
	col.initial_velocity_min = column_rise * 0.7 * sc
	col.initial_velocity_max = column_rise * 1.2 * sc
	col.damping_min = 0.15
	col.damping_max = 0.35
	col.gravity = Vector3(0.45, 0.55, 0.2) * sc
	col.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	col.emission_sphere_radius = radius * 0.3
	_scale_curve(col, radius * 0.5, radius * 0.7, 4.5)
	# Thick from its first instant (a ramp that fades in over a quarter of the life left the foot
	# of the column bare), thinning as it spreads.
	var stem_ramp := Gradient.new()
	stem_ramp.offsets = PackedFloat32Array([0.0, 0.05, 0.4, 0.75, 1.0])
	stem_ramp.colors = PackedColorArray([Color(0.05, 0.045, 0.04, 0.0), Color(0.055, 0.05, 0.045, 0.85),
		Color(0.065, 0.06, 0.055, 0.8), Color(0.085, 0.08, 0.075, 0.55), Color(0.11, 0.11, 0.11, 0.0)])
	col.color_ramp = stem_ramp
	var reach := column_life * column_rise * 1.6 * sc + radius * 4.0
	for e: CPUParticles3D in [cap, col]:
		e.custom_aabb = AABB(Vector3(-reach, -radius, -reach), Vector3(reach * 2.0, reach + radius, reach * 2.0))
		e.restart()
		e.emitting = true
	var t := holder.create_tween()
	t.tween_interval(column_emit)
	t.tween_callback(func(): if is_instance_valid(col): col.emitting = false)
	t.tween_interval(column_life + 2.5)
	t.tween_callback(holder.queue_free)
	last["column"] = 1


static func _smoke_emitter(holder: Node3D, amount: int, life: float, mat: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.lifetime_randomness = 0.25
	p.local_coords = true
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -8.0
	p.angular_velocity_max = 8.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(p)
	return p


static func _scale_curve(p: CPUParticles3D, lo: float, hi: float, grow: float) -> void:
	p.scale_amount_min = lo
	p.scale_amount_max = hi
	# Raise max_value or the growth is clamped to 1 (the Curve trap).
	var c := Curve.new()
	c.max_value = maxf(1.0, grow)
	c.add_point(Vector2(0.0, 0.7))
	c.add_point(Vector2(0.15, 1.0))
	c.add_point(Vector2(1.0, grow))
	p.scale_amount_curve = c


static func _prune_columns() -> void:
	var keep: Array = []
	for c in _columns:
		if is_instance_valid(c) and not (c as Node).is_queued_for_deletion():
			keep.append(c)
	_columns = keep


static func columns_alive() -> int:
	_prune_columns()
	return _columns.size()


# --- 0.1 s: windows blown out across the street ---------------------------------------------------

## BuildingDamage shatters the panes within 0.7 radii of a blast; a rocket's overpressure takes
## the glass out of every window facing it across the street. Shatter records on the same
## buildings (their facade shader draws the broken panes; WorldState keeps them), shards out of
## the nearest few, delayed by the wave's travel. Returns the panes broken.
static func _glass(node: Node, at: Vector3, radius: float) -> int:
	if not BuildingDamage.enabled or not (node is Node3D):
		return 0
	var space := (node as Node3D).get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius * glass_reach
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 1
	var reach := radius * glass_reach
	var inner := radius * BuildingDamage.BLAST_SHATTER
	var seen := {}
	var broken := 0
	var bursts := 0
	for res: Dictionary in space.intersect_shape(q, 64):
		if broken >= max_glass_panes:
			break
		var t := BuildingDamage.target_of(res.get("collider"), int(res.get("shape", -1)))
		if t.is_empty() or seen.has(t.key) or t.building == null:
			continue
		seen[t.key] = true
		var b: Building = t.building
		var bn: Node3D = t.node
		var mc := bn.to_local(at)
		var entry := BuildingDamage._entry(t.key)
		var changed := false
		for pane: Dictionary in BuildingDamage.panes_near(b, mc, reach):
			if broken >= max_glass_panes:
				break
			var c: Vector3 = pane.centre
			var d := c.distance_to(mc)
			if d < inner:
				continue # BuildingDamage's own blast record already took it
			# Only a pane that faces the blast, and not one hidden behind the building itself.
			if (mc - c).normalized().dot(pane.normal) < 0.25:
				continue
			if BuildingDamage._find_pane(entry, pane, c) >= 0:
				continue
			# Further away the wave is weaker: the far panes break by chance.
			var keep := 1.0 - (d - inner) / maxf(reach - inner, 0.01)
			if randf() > 0.35 + 0.65 * keep:
				continue
			BuildingDamage._add(entry, Vector4(c.x, c.y, c.z, BuildingDamage.K_SHATTER * 100.0), "")
			broken += 1
			changed = true
			if bursts < glass_bursts:
				bursts += 1
				var delay := d / 343.0 + 0.02
				var pn := pane
				node.get_tree().create_timer(delay, false).timeout.connect(func():
					if is_instance_valid(bn):
						BuildingDamage._shards(bn, pn))
		if changed:
			BuildingDamage._push(t, entry, false)
	if broken > 0:
		Sfx.play("glass", at, 4.0, randf_range(0.75, 0.9))
	return broken


## A car's own explosion throws it this much higher (CarDamage.explode() asks).
static func lift_gain() -> float:
	return car_lift_gain if enabled else 1.0
