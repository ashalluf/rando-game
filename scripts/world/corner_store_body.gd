class_name CornerStoreBody
extends StaticBody3D
## The corner store's collision (walls, roof, floor, the fittings inside; CornerStoreKit builds the
## shapes) and what a round does to the shelves: the products within a hand of where it lands are
## knocked off - the nearest few thrown as real bodies (debris, PhysicsBudget clears them), the rest
## dropped out of sight behind the shelf -, a can or a bottle bursts in a spray of its drink, a box
## or a bag in a puff of paper. The shelving's MultiMesh instances are hidden, never removed, so a
## shot-up shelf keeps its gaps until the chunk is rebuilt. While it is being shot up the store
## shows its real interior from further off (CornerStoreSite.shot_until), so the flying stock is seen
## through the glass from across the street. `STORE_MAYHEM=0` in the environment turns it off.

## How far from the round's point products are knocked off (m), plus `reach_per_damage` a point of
## damage (the rifle's 10 is about 0.27 m, a shotgun pellet a little more).
@export var reach: float = 0.17
@export var reach_per_damage: float = 0.01
## At most this many products leave the shelf a hit, and at most `throw_per_hit` of them fly.
@export var per_hit: int = 5
@export var throw_per_hit: int = 2
## Live thrown products (all stores together); past it the rest only drop out of sight.
const MAX_FLYING := 28
## How long a thrown product lies about (s).
const DEBRIS_LIFE := 25.0

static var enabled: bool = OS.get_environment("STORE_MAYHEM") != "0"
static var _flying: Array = []

var site: CornerStoreSite
## Products knocked off so far (the checks read it).
var knocked: int = 0


## A round from a weapon (Weapon rays call this on anything that is not a rigid body). The ray's
## point is not passed, so it is the player's aim when the aim is on this body (the shooter it
## nearly always is), else nothing happens past the plain impact.
func take_hit(_shape_index: int, damage: float, hit_dir: Vector3 = Vector3.UP) -> void:
	if not enabled or site == null:
		return
	var p := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if p == null or not p.has_method("get_aim"):
		return
	var aim: Dictionary = p.call("get_aim")
	if aim.get("collider") != self:
		return
	hit_at(aim.point, hit_dir, damage)


## Knocks the products round world point `at` off their shelves, thrown along `dir`. Returns how
## many left the shelf.
func hit_at(at: Vector3, dir: Vector3, damage: float) -> int:
	if not enabled or site == null or not is_instance_valid(site):
		return 0
	var lp := site.to_local(at)
	var W: float = site.store.get("W", 10.0)
	var D: float = site.store.get("D", 10.0)
	# Only inside the room (a round on an outside wall chips the stucco and nothing more).
	if lp.z > -CornerStore.WALL or lp.z < -D or absf(lp.x) > W * 0.5 or lp.y < -0.2 or lp.y > CornerStore.ROOF:
		return 0
	var r := reach + reach_per_damage * damage
	var near: Array = [] # [distance, group, index]
	for gi in site.goods.size():
		var g: Dictionary = site.goods[gi]
		var xs: Array = g.xf
		var alive: PackedByteArray = g.alive
		for i in xs.size():
			if alive[i] == 0:
				continue
			var xf: Transform3D = xs[i]
			# The pack's middle, not its base.
			var c: Vector3 = xf.origin + xf.basis.y * 0.5
			var d := c.distance_to(lp)
			if d < r:
				near.append([d, gi, i])
	if near.is_empty():
		return 0
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var ldir := (site.global_basis.inverse() * dir).normalized()
	var n := mini(per_hit, near.size())
	var thrown := 0
	var burst_col := Color.WHITE
	var wet := false
	for k in n:
		var gi: int = near[k][1]
		var i: int = near[k][2]
		var g: Dictionary = site.goods[gi]
		var mm: MultiMesh = g.mm
		var xf: Transform3D = g.xf[i]
		# A packed array in a Dictionary is a copy: change it and put it back.
		var alive: PackedByteArray = g.alive
		alive[i] = 0
		g.alive = alive
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), xf.origin))
		knocked += 1
		var col: Color = g.col[i]
		if k == 0:
			burst_col = col
			wet = int(g.kind) == CornerStoreKit.Goods.CAN or int(g.kind) == CornerStoreKit.Goods.BOTTLE
		if thrown < throw_per_hit and _room():
			_throw(mm.mesh, xf, col, g.custom[i], ldir)
			thrown += 1
	_burst(lp, ldir, burst_col, wet)
	site.shot_until = Time.get_ticks_msec() + 30000
	return n


func _room() -> bool:
	var live: Array = []
	for b: Variant in _flying:
		if is_instance_valid(b) and not (b as Node).is_queued_for_deletion():
			live.append(b)
	_flying = live
	return _flying.size() < MAX_FLYING and PhysicsBudget.make_room(1)


## One product as a real body: the pack's own mesh and look (a one-instance MultiMesh, as
## EncampmentItem.throw() does, so the print and the tint come with it), scaled inside the body.
func _throw(mesh: Mesh, xf: Transform3D, col: Color, custom: Color, ldir: Vector3) -> void:
	var size := xf.basis.get_scale()
	var shape := BoxShape3D.new()
	shape.size = size.max(Vector3(0.03, 0.03, 0.03))
	var body := PhysicsProp.new()
	body.setup(QuadMesh.new(), shape, Vector3(0, size.y * 0.5, 0), clampf(size.x * size.y * size.z * 600.0, 0.08, 3.0))
	var rot := xf.basis.orthonormalized()
	body.transform = Transform3D(site.global_basis * rot, site.to_global(xf.origin))
	site.get_parent().add_child(body)
	for c in body.get_children():
		if c is MeshInstance3D:
			c.queue_free()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis().scaled(size), Vector3.ZERO))
	mm.set_instance_color(0, col)
	mm.set_instance_custom_data(0, custom)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mmi)
	PhysicsBudget.register_debris(body, DEBRIS_LIFE)
	var gdir := site.global_basis * ldir
	body.linear_velocity = gdir * randf_range(3.0, 6.5) + Vector3.UP * randf_range(1.0, 3.0) \
			+ Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2))
	body.angular_velocity = Vector3(randf_range(-14.0, 14.0), randf_range(-10.0, 10.0), randf_range(-14.0, 14.0))
	_flying.append(body)


## A drink bursting (droplets of its colour falling) or a pack tearing (scraps of paper).
func _burst(lp: Vector3, ldir: Vector3, col: Color, wet: bool) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 26 if wet else 14
	p.lifetime = 0.9 if wet else 1.4
	p.explosiveness = 0.92
	p.direction = ldir + Vector3.UP * 0.35
	p.spread = 38.0 if wet else 60.0
	p.initial_velocity_min = 2.0 if wet else 0.8
	p.initial_velocity_max = 5.0 if wet else 2.4
	p.gravity = Vector3(0, -9.8, 0) if wet else Vector3(0, -2.5, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var m := StandardMaterial3D.new()
	var c := col if wet else Color(0.86, 0.83, 0.76)
	if wet:
		# A drink's colour behind clear plastic reads pale; the liquid is the deeper tone of it.
		c = Color(c.r * 0.8, c.g * 0.75, c.b * 0.7, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.08
		m.metallic_specular = 0.7
	else:
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	var mesh: Mesh
	if wet:
		var s := SphereMesh.new()
		s.radius = 0.008
		s.height = 0.016
		s.radial_segments = 6
		s.rings = 3
		mesh = s
	else:
		var q := QuadMesh.new()
		q.size = Vector2(0.03, 0.022)
		p.angle_min = 0.0
		p.angle_max = 360.0
		mesh = q
	mesh.surface_set_material(0, m)
	p.mesh = mesh
	p.custom_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	p.position = lp
	site.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
