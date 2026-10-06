class_name GolfLife
extends Node3D
## The golf course's life (GolfCourse, GolfBuild):
##   golfers   groups of two to four on some holes - on the tee, down the fairway or on the green -
##             one playing (Golfer DRIVE / IRON / PUTT) while the others stand by (WAIT), their cart
##             parked on the path beside them; a line of golfers down the range's bays, and a couple
##             on the practice green. By day only (the hour the chunk is built at). All placement is
##             PURE (groups(), range_spots()): hashes of the seed and the hole.
##   carts     golf carts driving the cart path's loop at a cart's pace with one or two golfers
##             aboard: worked out from a clock (no physics), AnimatableBody3Ds on the props layer
##             so a round or a blast finds them. Only while the player is within `active_range`.
##   sprinklers  impact sprinklers along the fairways and round the greens, sweeping their arcs at
##             dawn (SPRINKLER_HOURS) and off the rest of the day.
## One GolfLife node lives under the streamer (made by the first FULL course chunk) and keeps the
## carts and the sprinklers; the golfers are their chunks' children like any pedestrian.

const GROUP_ODDS := 0.72
const MAX_GOLFERS := 18
const RANGE_ODDS := 0.62
const CARTS := 4
const CART_SPEED := 4.2
const SPRINKLER_HOURS := Vector2(5.0, 7.5)
const SPRINKLER_SPACING := 26.0
const MAX_SPRINKLERS := 8
## Golfers play from this hour to that one.
const PLAY_HOURS := Vector2(6.4, 19.2)

@export var active_range: float = 900.0

static var force_hour: float = -1.0
static var enabled: bool = OS.get_environment("GOLF_LIFE") != "0"
static var _cart_mesh: ArrayMesh

var plan: CityPlan
var lay: Dictionary = {}
var carts: Array = []
var sprinklers: Array = []
var _path_len := PackedFloat32Array()
var _total: float = 0.0
var _clock: float = 0.0
var _hour_t: float = 0.0
var _spraying := false
var _bridge_decks: Array = []


static func hour_now(node: Node) -> float:
	if force_hour >= 0.0:
		return force_hour
	return StreetVendors.hour_now(node)


# --- Placement (pure) ----------------------------------------------------------------------------

## The groups on the course: [{"hole", "stage" (0 tee, 1 fairway, 2 green), "members": [[position,
## target direction, role, seed]], "cart": [position, yaw]}].
static func groups(l: Dictionary) -> Array:
	var out: Array = []
	var ps: int = l.seed
	for h: Dictionary in l.holes:
		var n: int = h.n
		if GolfCourse.h01([ps, "golf_group", n]) >= GROUP_ODDS:
			continue
		var stage := int(GolfCourse.h01([ps, "golf_stage", n]) * 2.999)
		if int(h.par) == 3 and stage == 1:
			stage = 2
		var count := 2 + int(GolfCourse.h01([ps, "golf_count", n]) * 2.999)
		var pts: PackedVector2Array = h.pts
		var members: Array = []
		var at: Vector2
		var dir: Vector2
		var role: int
		match stage:
			0:
				var t: Dictionary = (h.tees as Array)[int(GolfCourse.h01([ps, "golf_tee", n]) * 2.999)]
				at = t.c
				dir = t.u
				role = Golfer.Role.DRIVE if int(h.par) >= 4 else Golfer.Role.IRON
			1:
				var s := float(h.length) * GolfCourse.hrange(0.45, 0.62, [ps, "golf_fws", n])
				dir = GolfCourse.poly_dir(pts, s)
				at = GolfCourse.poly_at(pts, s) + Vector2(-dir.y, dir.x) * GolfCourse.hrange(-5.0, 5.0, [ps, "golf_fwo", n])
				dir = ((h.green.c as Vector2) - at).normalized()
				role = Golfer.Role.IRON
			_:
				var pin: Vector2 = h.pin
				var a := GolfCourse.hrange(0.0, TAU, [ps, "golf_putt", n])
				at = pin + Vector2(cos(a), sin(a)) * GolfCourse.hrange(2.5, 7.0, [ps, "golf_putd", n])
				if GolfCourse.ellipse_sdf(h.green, at) > -0.5:
					at = pin.lerp(h.green.c, 0.5) + (at - pin).normalized() * 2.0
				dir = (pin - at).normalized()
				role = Golfer.Role.PUTT
		members.append([at, dir, role, hash([ps, "golfer", n, 0])])
		var side := Vector2(-dir.y, dir.x)
		for k in range(1, count):
			var q: Vector2
			if stage == 2:
				# Round the green's edge, watching.
				var a2 := (at - (h.pin as Vector2)).angle() + 1.3 * float(k)
				q = (h.green.c as Vector2) + Vector2(cos(a2) * float(h.green.a), sin(a2) * float(h.green.b)).rotated(float(h.green.ang)) * 1.08
			else:
				# Behind the player and off to the side: out of the way of the swing.
				q = at - dir * GolfCourse.hrange(3.0, 6.0, [ps, "golf_wait", n, k]) - side * (3.2 + 1.6 * float(k))
			members.append([q, (at - q).normalized(), Golfer.Role.WAIT, hash([ps, "golfer", n, k])])
		# Their cart: on the path, at its nearest point to the group.
		var cp := _nearest_on(l.path, at)
		out.append({"hole": n, "stage": stage, "members": members, "cart": cp})
	return out


## The range's tee line: a golfer in some bays, all hitting north up the range.
static func range_spots(l: Dictionary) -> Array:
	var r: Rect2 = l.range
	var out: Array = []
	var ps: int = l.seed
	var ty := r.end.y - 12.0
	var tl := r.position.x + 3.0
	var tr := r.end.x - 3.0
	var bays := int((tr - tl) / 3.2)
	for i in bays:
		if GolfCourse.h01([ps, "golf_bay", i]) >= RANGE_ODDS:
			continue
		var x := tl + (tr - tl) * (float(i) + 0.5) / float(bays)
		# The golfer stands south of the mat's ball, side-on, hitting north (-z): their left is north.
		out.append([Vector2(x + 0.1, ty + 0.4 + 0.72), Vector2(0.0, -1.0), Golfer.Role.IRON, hash([ps, "golf_ranger", i])])
	var g: Dictionary = l.putt
	for k in 2:
		var a := GolfCourse.hrange(0.0, TAU, [ps, "golf_pg", k])
		var c: Vector2 = g.c
		var at := c + Vector2(cos(a) * float(g.a), sin(a) * float(g.b)) * 0.45
		out.append([at, (c - at).normalized(), Golfer.Role.PUTT, hash([ps, "golf_pg_p", k])])
	return out


## The sprinkler heads: along each fairway every SPRINKLER_SPACING metres either side, and four
## round each green.
static func sprinkler_spots(l: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for h: Dictionary in l.holes:
		var pts: PackedVector2Array = h.pts
		var s := float(h.fw_from)
		var k := 0
		while s < float(h.length) - 20.0 and int(h.par) >= 4:
			var at := GolfCourse.poly_at(pts, s)
			var d := GolfCourse.poly_dir(pts, s)
			out.append(at + Vector2(-d.y, d.x) * (float(h.fw_half) * 0.6) * (1.0 if k % 2 == 0 else -1.0))
			s += SPRINKLER_SPACING
			k += 1
		var g: Dictionary = h.green
		for a in 4:
			var dir := Vector2.from_angle(float(g.ang) + PI * 0.5 * float(a) + 0.4)
			out.append((g.c as Vector2) + dir * (GolfCourse.ellipse_radius(g, dir) + 2.0))
	return out


static func _nearest_on(path: PackedVector2Array, p: Vector2) -> Array:
	var best := INF
	var at := p
	var dir := Vector2(1.0, 0.0)
	for k in path.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, path[k], path[k + 1])
		var d := q.distance_to(p)
		if d < best:
			best = d
			at = q
			dir = (path[k + 1] - path[k]).normalized()
	return [at, atan2(-dir.x, -dir.y)]


# --- Chunks ---------------------------------------------------------------------------------------

## A FULL course chunk is built: its golfers (by day) and its sprinklers, and the life node.
static func chunk_built(ch: CityChunk, st: Dictionary) -> void:
	if not enabled or ch.capturing:
		return
	var l: Dictionary = st.lay
	var area: Rect2 = st.area
	var life := _life_for(ch, l)
	var hour := hour_now(ch)
	var spawned := 0
	if hour >= PLAY_HOURS.x and hour <= PLAY_HOURS.y:
		for g: Dictionary in groups(l):
			for m: Array in g.members:
				if spawned >= MAX_GOLFERS:
					break
				if area.has_point(m[0]) and _spawn(ch, st, m):
					spawned += 1
			# The group's cart, parked on the path.
			var cp: Array = g.cart
			if area.has_point(cp[0]):
				_parked_cart(ch, st, cp[0], float(cp[1]))
		for m: Array in range_spots(l):
			if spawned >= MAX_GOLFERS:
				break
			if area.has_point(m[0]) and _spawn(ch, st, m, true):
				spawned += 1
	var n := 0
	for p: Vector2 in sprinkler_spots(l):
		if n >= MAX_SPRINKLERS or not area.has_point(p):
			continue
		var sp := _sprinkler(ch, st, p)
		n += 1
		if life:
			life.sprinklers.append(sp)


static func _spawn(ch: CityChunk, st: Dictionary, m: Array, on_range: bool = false) -> bool:
	if not ch._take_crowd_room():
		return false
	var p: Vector2 = m[0]
	var g := Golfer.new()
	var y := GolfBuild.ground(ch, st, p) + 0.05
	g.setup_golfer(p, y, m[1], int(m[2]), int(m[3]))
	if on_range and int(m[2]) == Golfer.Role.IRON:
		g.range_cycle(int(m[3]))
	ch.add_child(g)
	return true


static func _life_for(ch: CityChunk, l: Dictionary) -> GolfLife:
	var root := ch.get_parent()
	if root == null:
		return null
	var existing := root.get_node_or_null("GolfLife") as GolfLife
	if existing:
		return existing
	var life := GolfLife.new()
	life.name = "GolfLife"
	life.plan = ch.plan
	life.lay = l
	life.position = -WorldState.world_offset
	root.add_child(life)
	return life


static func _sprinkler(ch: CityChunk, st: Dictionary, p: Vector2) -> CPUParticles3D:
	var y := GolfBuild.ground(ch, st, p)
	var sp := CPUParticles3D.new()
	sp.name = "GolfSprinkler"
	sp.amount = 36 if CityChunk._detail() >= 1.0 else 16
	sp.lifetime = 1.5
	sp.emitting = false
	sp.direction = Vector3(1.0, 0.62, 0.0)
	sp.spread = 5.0
	sp.initial_velocity_min = 8.0
	sp.initial_velocity_max = 10.5
	sp.gravity = Vector3(0.0, -9.8, 0.0)
	sp.scale_amount_min = 0.2
	sp.scale_amount_max = 0.45
	sp.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var pm := StandardMaterial3D.new()
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.billboard_keep_scale = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_texture = WeaponFX.puff_texture()
	pm.albedo_color = Color(0.9, 0.94, 0.96, 0.28)
	q.material = pm
	sp.mesh = q
	sp.position = Vector3(p.x, y + 0.15, p.y)
	sp.rotation.y = GolfCourse.hrange(0.0, TAU, [int(p.x), int(p.y), "spr"])
	sp.custom_aabb = AABB(Vector3(-14.0, -1.0, -14.0), Vector3(28.0, 6.0, 28.0))
	sp.visibility_range_end = 260.0
	ch.add_child(sp)
	return sp


## A parked cart at a group's spot on the path (a static prop of the chunk: no body of its own,
## a collision box on the chunk's statics).
static func _parked_cart(ch: CityChunk, st: Dictionary, p: Vector2, yaw: float) -> void:
	var y := GolfBuild.ground(ch, st, p)
	var at := Vector3(p.x, y, p.y)
	var mi := MeshInstance3D.new()
	mi.name = "GolfCartParked"
	mi.mesh = cart_mesh()
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	mi.visibility_range_end = 350.0
	ch.add_child(mi)
	ch._add_shape(Vector3(1.25, 1.9, 2.5), at + Vector3(0.0, 0.95, 0.0), yaw)


# --- The life node --------------------------------------------------------------------------------

func _ready() -> void:
	var path: PackedVector2Array = lay.path
	_path_len.resize(path.size())
	var run := 0.0
	for k in path.size():
		if k > 0:
			run += path[k - 1].distance_to(path[k])
		_path_len[k] = run
	_total = run
	for br: Array in lay.bridges:
		var c: Vector2 = br[0]
		var dir: Vector2 = br[1]
		var span: float = br[2]
		var a := c - dir * span * 0.5
		var b := c + dir * span * 0.5
		var deck := maxf(_ground_at(a), _ground_at(b)) + 0.12
		_bridge_decks.append([c, span * 0.5 + 0.5, deck])
	if enabled:
		for i in CARTS:
			_make_cart(i)


func _ground_at(p: Vector2) -> float:
	var f := GolfCourse.field_all(lay, p)
	return GolfCourse.shape(GolfCourse.gather(lay, Rect2(p, Vector2.ZERO)), p, f, plan.macro.relief_at(p) + CityChunk.SIDEWALK_TOP, -1e6)


func _make_cart(i: int) -> void:
	var body := AnimatableBody3D.new()
	body.name = "GolfCart%d" % i
	body.collision_layer = 4
	body.collision_mask = 0
	body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.25, 1.9, 2.5)
	cs.shape = box
	cs.position = Vector3(0.0, 0.95, 0.0)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = cart_mesh()
	mi.visibility_range_end = 400.0
	body.add_child(mi)
	var s0 := _total * float(i) / float(CARTS) + GolfCourse.hrange(0.0, 30.0, [lay.seed, "cart", i])
	body.set_meta("s0", s0)
	body.transform = _cart_xform(s0)
	add_child(body)
	# One or two aboard (seated golfers; not physics walkers, never spawned into the crowd cap).
	var riders := 1 + int(GolfCourse.h01([lay.seed, "cart_riders", i]) < 0.6)
	for k in riders:
		var g := Golfer.new()
		g.setup_golfer(Vector2.ZERO, 0.0, Vector2(0.0, -1.0), Golfer.Role.RIDE, hash([lay.seed, "cart_rider", i, k]))
		g.position = Vector3(-0.28 if k == 0 else 0.28, 0.32, 0.12)
		body.add_child(g)
		g.collision_layer = 0
		g.collision_mask = 0
		g.rotation = Vector3.ZERO
	carts.append(body)


func _cart_xform(s: float) -> Transform3D:
	var path: PackedVector2Array = lay.path
	s = fposmod(s, maxf(_total, 1.0))
	var k := _path_len.bsearch(s) - 1
	k = clampi(k, 0, path.size() - 2)
	var a := path[k]
	var b := path[k + 1]
	var l := maxf(_path_len[k + 1] - _path_len[k], 0.001)
	var p := a.lerp(b, clampf((s - _path_len[k]) / l, 0.0, 1.0))
	var d := (b - a).normalized()
	var y := plan.macro.relief_at(p) + CityChunk.SIDEWALK_TOP
	for bd: Array in _bridge_decks:
		if p.distance_to(bd[0]) < float(bd[1]):
			y = maxf(y, float(bd[2]))
	return Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.y)), Vector3(p.x, y, p.y))


func _process(delta: float) -> void:
	_clock += delta
	_hour_t -= delta
	if _hour_t <= 0.0:
		_hour_t = 1.0
		var h := hour_now(self)
		var on := h >= SPRINKLER_HOURS.x and h <= SPRINKLER_HOURS.y
		var alive: Array = []
		for sp: Variant in sprinklers:
			if is_instance_valid(sp):
				alive.append(sp)
				if (sp as CPUParticles3D).emitting != on:
					(sp as CPUParticles3D).emitting = on
		sprinklers = alive
		_spraying = on
	if _spraying:
		for sp: Variant in sprinklers:
			# An impact sprinkler sweeps its arc in steps.
			(sp as Node3D).rotation.y += delta * 0.9
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var near := true
	if player:
		var pw := WorldState.to_world(player.global_position)
		near = (lay.rect as Rect2).grow(active_range).has_point(Vector2(pw.x, pw.z))
	for c: Variant in carts:
		var body := c as Node3D
		body.visible = near
		if not near:
			continue
		var s := float(body.get_meta("s0")) + _clock * CART_SPEED
		body.transform = _cart_xform(s)


# --- The cart's model -----------------------------------------------------------------------------

## A golf cart at real size (2.4 m long, 1.2 m wide, roof at 1.85 m), facing -Z: a white body with
## a rounded cowl, a two-seat bench, a black roof on four posts, a bag rack with two bags behind,
## small wheels. One mesh, vertex coloured.
static func cart_mesh() -> ArrayMesh:
	if _cart_mesh != null:
		return _cart_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color(0.92, 0.92, 0.90)
	var dark := Color(0.08, 0.08, 0.09)
	var seat := Color(0.72, 0.64, 0.50)
	var metal := Color(0.62, 0.63, 0.64)
	# Chassis and floor.
	_bx(st, Vector3(0.0, 0.33, 0.05), Vector3(1.12, 0.16, 2.3), dark)
	_bx(st, Vector3(0.0, 0.44, 0.0), Vector3(1.16, 0.06, 2.0), body)
	# The cowl: a box stepped to look rounded.
	_bx(st, Vector3(0.0, 0.62, -0.88), Vector3(1.18, 0.42, 0.55), body)
	_bx(st, Vector3(0.0, 0.86, -0.78), Vector3(1.08, 0.08, 0.42), body)
	_bx(st, Vector3(0.0, 0.52, -1.16), Vector3(1.10, 0.22, 0.08), dark)
	# Dash and wheel.
	_bx(st, Vector3(0.0, 0.88, -0.56), Vector3(1.05, 0.12, 0.14), dark)
	_bx(st, Vector3(-0.28, 1.0, -0.46), Vector3(0.32, 0.04, 0.32), dark)
	# Seat and back.
	_bx(st, Vector3(0.0, 0.68, 0.18), Vector3(1.08, 0.12, 0.52), seat)
	_bx(st, Vector3(0.0, 0.52, 0.18), Vector3(1.0, 0.2, 0.48), body)
	_bx(st, Vector3(0.0, 0.98, 0.44), Vector3(1.08, 0.48, 0.08), seat)
	# Rear body and the bag rack, two bags.
	_bx(st, Vector3(0.0, 0.62, 0.86), Vector3(1.16, 0.38, 0.56), body)
	_bx(st, Vector3(0.0, 0.84, 1.08), Vector3(1.0, 0.06, 0.12), metal)
	for sx: float in [-0.26, 0.26]:
		_bx(st, Vector3(sx, 1.2, 0.95), Vector3(0.24, 0.85, 0.24), Color(0.15, 0.22, 0.38) if sx < 0.0 else Color(0.55, 0.10, 0.10))
		_bx(st, Vector3(sx, 1.68, 0.95), Vector3(0.2, 0.14, 0.2), metal)
	# Roof posts and canopy.
	for p: Vector3 in [Vector3(-0.52, 1.2, -0.62), Vector3(0.52, 1.2, -0.62), Vector3(-0.52, 1.2, 0.52), Vector3(0.52, 1.2, 0.52)]:
		_bx(st, p, Vector3(0.04, 1.36, 0.04), metal)
	_bx(st, Vector3(0.0, 1.9, -0.06), Vector3(1.22, 0.06, 1.62), dark)
	# Windscreen frame.
	_bx(st, Vector3(0.0, 1.38, -0.64), Vector3(1.04, 0.03, 0.03), metal)
	# Wheels.
	for p: Vector3 in [Vector3(-0.56, 0.22, -0.78), Vector3(0.56, 0.22, -0.78), Vector3(-0.56, 0.22, 0.8), Vector3(0.56, 0.22, 0.8)]:
		_wheel(st, p, 0.22, 0.17)
	st.generate_normals()
	_cart_mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.4
	_cart_mesh.surface_set_material(0, m)
	return _cart_mesh


static func _bx(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	Golfer._box(st, c, s, col)


static func _wheel(st: SurfaceTool, c: Vector3, r: float, w: float) -> void:
	var segs := 12
	var dark := Color(0.05, 0.05, 0.05)
	var hub := Color(0.7, 0.7, 0.72)
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var p0 := Vector3(0.0, cos(a0) * r, sin(a0) * r)
		var p1 := Vector3(0.0, cos(a1) * r, sin(a1) * r)
		var hw := Vector3(w * 0.5, 0.0, 0.0)
		var q := [c + p0 - hw, c + p0 + hw, c + p1 + hw, c + p1 - hw]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(dark)
			st.add_vertex(q[k])
		for sgn: float in [-1.0, 1.0]:
			var cc := c + hw * sgn
			var tri := [cc, c + p0 + hw * sgn, c + p1 + hw * sgn] if sgn > 0.0 else [cc, c + p1 + hw * sgn, c + p0 + hw * sgn]
			for v: Vector3 in tri:
				st.set_color(hub if v == cc else dark)
				st.add_vertex(v)
