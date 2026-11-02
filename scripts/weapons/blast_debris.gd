class_name BlastDebris
extends Node3D
## Burning debris thrown out of a blast (BlastFX): a handful of dark lumps arcing out, each
## trailing flame and a lit smoke trail, bouncing once where it lands and burning there a few
## seconds before it goes out. Not physics bodies: each piece is a point on a ballistic arc with
## one world ray a physics tick, and every piece of the blast feeds the SAME two emitters (their
## emission points are the pieces' positions, rewritten each tick), so a blast's trails are two
## draws however many pieces it threw. Everything is in this node's own space, which an origin
## re-centre shifts with the scene.

## Gravity on a piece (heavier than a particle's: these are lumps of car and road).
const GRAVITY := 17.0
## Longest a piece flies before it is called landed wherever it is.
const MAX_FLIGHT := 4.5
## Seconds a landed piece keeps burning (random in this range).
const BURN := Vector2(2.5, 6.0)
## A landing faster than this bounces once.
const BOUNCE_SPEED := 6.0

## Every BlastDebris thrown; alive() sums the pieces of those still in the tree. (A counter
## bumped on spawn leaked whenever a blast's debris never entered or left the tree the normal way,
## and once it reached max_debris no blast threw debris again - gate run 303.)
static var _all: Array = []
static var _mesh: Mesh
static var _mat: StandardMaterial3D

var _pieces: Array = [] # {node, pos, vel, spin, axis, landed, burn, t}
var _flames: CPUParticles3D
var _trail: CPUParticles3D
var _done := false
var _age := 0.0
## Pieces flying or burning (not yet out).
var _live := 0
## Blast4 round 7: a smoke ribbon behind each burning piece (Blast4.debris_ribbons).
var _ribbon: MeshInstance3D
var _rib_mesh: ImmediateMesh
var _rib_hist: Array = [] # per piece: Array of [world position, age]
const RIB_LIFE := 1.6


## Throws up to `count` pieces (fewer when `BlastFX.max_debris` are already flying); returns how
## many it threw.
static func spawn(node: Node, parent: Node, at: Vector3, radius: float, push: float, count: int) -> int:
	count = mini(count, BlastFX.max_debris - alive())
	if count <= 0:
		return 0
	var d := BlastDebris.new()
	d.name = "BlastDebris"
	parent.add_child(d)
	d.global_position = at + Vector3.UP * 0.4
	d._throw(radius, push, count)
	return count


func _throw(radius: float, push: float, count: int) -> void:
	if _mesh == null:
		var m := PrismMesh.new()
		m.size = Vector3(1.0, 0.6, 0.8)
		m.left_to_right = 0.3
		_mesh = m
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.06, 0.055, 0.05)
		_mat.roughness = 0.9
		# Glowing hot where the fire has it: a little emission so a lump reads as burning metal,
		# not a black hole, against the night.
		_mat.emission_enabled = true
		_mat.emission = Color(1.0, 0.36, 0.08)
		_mat.emission_energy_multiplier = 0.6
	var start := randf() * TAU
	for i in count:
		var ang := start + TAU * (float(i) + randf_range(-0.3, 0.3)) / float(count)
		var elev := deg_to_rad(randf_range(28.0, 68.0))
		var speed := radius * randf_range(1.1, 2.3) * push
		var vel := Vector3(cos(ang) * cos(elev), sin(elev), sin(ang) * cos(elev)) * speed
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.material_override = _mat
		var own: StandardMaterial3D = null
		if Blast3.enabled:
			# Blast3: charred metal with embers in it that die down, its own material so each
			# piece cools on its own clock (a few dozen at most); bright orange all over, the
			# shared one read as a plastic toy on the road.
			own = _mat.duplicate() as StandardMaterial3D
			own.albedo_color = Color(0.035, 0.032, 0.03)
			own.metallic = 0.4
			own.roughness = 0.75
			own.emission = Color(1.0, 0.28, 0.05)
			own.emission_energy_multiplier = 0.28 if Blast4.enabled and Blast4.debris_chunks else 0.5
			mi.material_override = own
		mi.scale = Vector3(randf_range(0.25, 0.6), randf_range(0.15, 0.4), randf_range(0.25, 0.55)) * clampf(radius / 9.0, 0.6, 1.4)
		if Blast4.enabled and Blast4.debris_chunks:
			# Blast4: real chunks, not dots - a third are torn thin panels (a door skin, a bonnet
			# corner), the rest bigger wedges; each its own size.
			if i % 3 == 0:
				mi.mesh = Blast4.panel_mesh()
				if own == null:
					own = _mat.duplicate() as StandardMaterial3D
					mi.material_override = own
				own.cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.scale = Vector3(randf_range(0.7, 1.3), 1.0, randf_range(0.5, 1.0)) * clampf(radius / 9.0, 0.6, 1.4)
			else:
				mi.scale *= randf_range(0.95, 1.45)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_pieces.append({"node": mi, "pos": Vector3.ZERO, "vel": vel, "landed": false, "t": 0.0,
			"burn": randf_range(BURN.x, BURN.y) * (1.6 if Blast4.enabled and Blast4.debris_ribbons else 1.0), "axis": Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(),
			"spin": randf_range(6.0, 16.0), "out": false})
		if own != null:
			_pieces[-1]["mat"] = own
	_live = count
	_all.append(self)
	var k := clampf(radius / 9.0, 0.6, 1.5)
	# Flame tongues off every piece: short-lived fire puffs, the fireball's material.
	_flames = _emitter(count * 14, 0.38, WeaponFX._fire_material())
	_flames.scale_amount_min = 0.35 * k
	_flames.scale_amount_max = 0.6 * k
	_flames.gravity = Vector3(0.0, 3.0, 0.0)
	_flames.initial_velocity_max = 0.8
	_flames.color_ramp = WeaponFX._ramp([Color(3.2, 2.2, 1.2, 1.0), Color(2.0, 0.75, 0.16, 0.95),
		Color(0.8, 0.22, 0.05, 0.6), Color(0.08, 0.06, 0.05, 0.0)])
	_grow(_flames, 1.6)
	if Blast4.tongues():
		# Tongues licking up off each piece (Blast4 round 6), not round puffs.
		Blast4.tongue_quad(_flames.mesh as QuadMesh, 1.5)
		_flames.spread = 20.0
		_flames.angle_min = 0.0
		_flames.angle_max = 0.0
	# The smoke trail: lit puffs left hanging where the piece was, growing and fading.
	_trail = _emitter(count * (44 if Blast4.enabled and Blast4.debris_chunks else 26), 2.4, BlastFX.smoke_material())
	_trail.scale_amount_min = 0.55 * k
	_trail.scale_amount_max = 0.9 * k
	_trail.gravity = Vector3(0.2, 1.2, 0.1)
	_trail.initial_velocity_max = 0.4
	_trail.color_ramp = WeaponFX._ramp([Color(0.05, 0.045, 0.04, 0.0), Color(0.06, 0.055, 0.05, 0.7),
		Color(0.09, 0.085, 0.08, 0.4), Color(0.11, 0.11, 0.11, 0.0)])
	_grow(_trail, 4.0)
	var reach := radius * 2.6 * push * MAX_FLIGHT + 20.0
	if Blast4.enabled and Blast4.debris_ribbons:
		_rib_mesh = ImmediateMesh.new()
		_ribbon = MeshInstance3D.new()
		_ribbon.name = "DebrisRibbons"
		_ribbon.mesh = _rib_mesh
		_ribbon.top_level = true
		_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ribbon.material_override = Blast4.ribbon_material()
		_ribbon.custom_aabb = AABB(Vector3(-reach, -reach, -reach) * 2.0, Vector3(reach, reach, reach) * 4.0)
		add_child(_ribbon)
		# At the blast (its box is round its node): vertices relative to it.
		_ribbon.global_transform = Transform3D(Basis(), global_position)
		for i in _pieces.size():
			_rib_hist.append([])
	for e: CPUParticles3D in [_flames, _trail]:
		e.custom_aabb = AABB(Vector3(-reach, -reach, -reach), Vector3(reach, reach, reach) * 2.0)
		e.emission_points = PackedVector3Array([Vector3.ZERO])
		e.emitting = true


func _emitter(amount: int, life: float, mat: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(1, WeaponFX._count(amount))
	p.lifetime = life
	p.lifetime_randomness = 0.3
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


static func _grow(p: CPUParticles3D, grow: float) -> void:
	var c := Curve.new()
	c.max_value = maxf(1.0, grow) # the Curve clamps to max_value
	c.add_point(Vector2(0.0, 0.6))
	c.add_point(Vector2(0.2, 1.0))
	c.add_point(Vector2(1.0, grow))
	p.scale_amount_curve = c


func _physics_process(dt: float) -> void:
	if _done:
		return
	_age += dt
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	var points := PackedVector3Array()
	var burning := 0
	for p: Dictionary in _pieces:
		if p.out:
			continue
		p.t += dt
		var mi: MeshInstance3D = p.node
		if not p.landed:
			var from: Vector3 = p.pos
			p.vel += Vector3.DOWN * GRAVITY * dt
			var to: Vector3 = from + p.vel * dt
			var hit := {}
			if space != null:
				var q := PhysicsRayQueryParameters3D.create(to_global(from), to_global(to), 1)
				hit = space.intersect_ray(q)
			if not hit.is_empty():
				var n: Vector3 = hit.normal
				to = to_local(hit.position) + n * 0.12
				var v: Vector3 = p.vel
				if Blast3.enabled:
					# Blast3: it bounces as often as it has the speed to, then skids along the
					# ground and settles flat (`_skid()`), instead of stopping dead where it hit.
					var vn := n * v.dot(n)
					var vt := v - vn
					if vn.length() > BOUNCE_SPEED * 0.5:
						p.vel = vt * 0.55 - vn * 0.32
						p.spin = float(p.spin) * 0.7
						p.bounces = int(p.get("bounces", 0)) + 1
					elif n.y > 0.55:
						p.vel = vt * 0.7
						p.ground = n
						p.skid = true
						p.landed = true
						p.t = 0.0
					else:
						p.vel = vt * 0.5 - n * 0.5
				elif v.length() > BOUNCE_SPEED and not p.get("bounced", false):
					p.vel = v.bounce(n) * 0.3
					p.bounced = true
				else:
					p.landed = true
					p.t = 0.0
			elif p.t > MAX_FLIGHT:
				p.landed = true
				p.t = 0.0
			p.pos = to
			mi.position = to
			mi.rotate(p.axis, p.spin * dt)
		elif p.get("skid", false):
			_skid(p, mi, space, dt)
			if p.t > p.burn:
				p.skid = false
		elif p.t > p.burn:
			p.out = true
			_live -= 1
			var tw := mi.create_tween()
			tw.tween_property(mi, "scale", mi.scale * 0.6, 1.5)
			continue
		points.append(p.pos)
		burning += 1
	if burning == 0:
		_done = true
		if _ribbon != null:
			_ribbon.visible = false
		_flames.emitting = false
		_trail.emitting = false
		var t := create_tween()
		t.tween_interval(_trail.lifetime * 1.4 + 1.6)
		t.tween_callback(queue_free)
		return
	_flames.emission_points = points
	_trail.emission_points = points
	if _ribbon != null:
		_ribbons(dt)


## A landed piece sliding to a stop (Blast3): friction off its speed, held on the ground under
## it by one short ray, turning to lie flat on it.
func _skid(p: Dictionary, mi: MeshInstance3D, space: PhysicsDirectSpaceState3D, dt: float) -> void:
	var v: Vector3 = p.vel
	var sp := v.length()
	var nsp := maxf(sp - 9.0 * dt, 0.0)
	v = v * (nsp / maxf(sp, 1e-4))
	var n: Vector3 = p.get("ground", Vector3.UP)
	var to: Vector3 = p.pos + v * dt
	if space != null and nsp > 0.0:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(to_global(to + n * 0.4), to_global(to - n * 0.6), 1))
		if not hit.is_empty():
			n = hit.normal
			to = to_local(hit.position) + n * 0.1
	p.vel = v
	p.pos = to
	p.ground = n
	mi.position = to
	# Lie flat: its basis turned toward one whose up is the ground's normal, keeping its heading.
	var cur := mi.basis.orthonormalized()
	var flat := WeaponFX._basis_up(n, atan2(cur.z.x, cur.z.z))
	var s := mi.scale
	mi.basis = cur.slerp(flat, clampf(dt * 8.0, 0.0, 1.0))
	mi.scale = s
	# The fire on it dies down.
	if p.has("mat"):
		var m: StandardMaterial3D = p.mat
		m.emission_energy_multiplier = 0.5 * clampf(1.0 - float(p.t) / maxf(float(p.burn), 0.1), 0.0, 1.0)


func _exit_tree() -> void:
	for p: Dictionary in _pieces:
		p.out = true
	_live = 0
	_all.erase(self)


## Pieces flying or burning now (the checks read it).
static func alive() -> int:
	var n := 0
	var keep: Array = []
	for d in _all:
		if is_instance_valid(d) and (d as Node).is_inside_tree() and not (d as Node).is_queued_for_deletion():
			keep.append(d)
			n += (d as BlastDebris)._live
	_all = keep
	return n


## The smoke ribbons: each burning piece leaves its world positions (a point a tick, aging), and
## the strip through them is rebuilt facing the camera, widening and fading as it ages - one
## continuous streak behind a flying piece (dropped puffs beaded), a thin wisp off a landed one.
func _ribbons(dt: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_rib_mesh.clear_surfaces()
	if cam == null:
		return
	var eye := cam.global_position
	var org := _ribbon.global_position
	var any := false
	for k in _pieces.size():
		var p: Dictionary = _pieces[k]
		var h: Array = _rib_hist[k]
		for e: Array in h:
			e[1] = float(e[1]) + dt
		while h.size() > 0 and float(h[0][1]) > RIB_LIFE:
			h.pop_front()
		if not p.out and is_instance_valid(p.node):
			# Thick behind a piece flying fast, a thin wisp off one lying burning.
			var fast := clampf((p.vel as Vector3).length() / 12.0, 0.0, 1.0) if not p.landed else 0.0
			h.append([(p.node as Node3D).global_position, 0.0, 0.25 + 0.75 * fast])
		if h.size() < 2:
			continue
		if not any:
			_rib_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			any = true
		else:
			# A degenerate join between strips.
			_rib_mesh.surface_add_vertex((h[0][0] as Vector3) - org)
			_rib_mesh.surface_add_vertex((h[0][0] as Vector3) - org)
		for j in h.size():
			var pos: Vector3 = h[j][0]
			var age: float = h[j][1]
			var nxt: Vector3 = h[mini(j + 1, h.size() - 1)][0]
			var prv: Vector3 = h[maxi(j - 1, 0)][0]
			var along := (nxt - prv)
			if along.length() < 1e-4:
				along = Vector3.UP
			var side := along.cross(eye - pos).normalized()
			var w := 0.07 + age * 0.45
			var a := pow(clampf(1.0 - age / RIB_LIFE, 0.0, 1.0), 1.4) * 0.42 * clampf(float(j) / 2.0, 0.0, 1.0) * float(h[j][2])
			var c := Color(0.11, 0.1, 0.095, a)
			_rib_mesh.surface_set_normal((eye - pos).normalized())
			_rib_mesh.surface_set_color(c)
			_rib_mesh.surface_add_vertex(pos - side * w - org)
			_rib_mesh.surface_set_normal((eye - pos).normalized())
			_rib_mesh.surface_set_color(c)
			_rib_mesh.surface_add_vertex(pos + side * w - org)
	if any:
		_rib_mesh.surface_end()
