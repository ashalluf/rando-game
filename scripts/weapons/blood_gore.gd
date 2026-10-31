class_name BloodGore
extends RefCounted
## Blood and gore at arm's length (blood-gore-2, docs/HANDOFF.md "Blood and gore at arm's length";
## owner: more blood). On top of WeaponFX's blood (CLAUDE.md, the Effects note), never instead of
## it, and under the same caps:
##  - wounds that read on the body: a punched entry hole, a bigger torn exit, a dark abraded ring,
##    fresh blood glossy, and a run creeping down the body the way gravity pulls - character.gdshader
##    through shaders/blood_wound.gdshaderinc, set by Ragdoll._update_stains() (ENTRY_HOLE,
##    EXIT_HOLE, run_length(), RUN_SECONDS);
##  - pools that follow the ground (pool_laid(), from WeaponFX.blood_pool()): stretched and slid
##    downhill, and a rivulet that creeps away down the slope or the road's camber to the gutter,
##    where it spreads along the kerb (flow());
##  - a body lying on a car (car_bleed(), from Ragdoll._blood_step()): a smear on the paint under
##    it, a run to the panel's edge, drips off that edge and a trail of drops on the road while
##    the car drives;
##  - the stumps (stump_mesh(), stump_material()): torn skin, muscle, fat and the bone's end with
##    its marrow, in place of the old glossy red ball;
##  - spatter on the hero's clothes when he is close (HeroBlood).
## BLOOD_GORE_2=0 is the A/B: every hook returns at once and the shaders keep their old branch.

## Hole radii (metres, times the wound's sqrt strength): an entry is a punched hole, an exit torn.
const ENTRY_HOLE := 0.017
const EXIT_HOLE := 0.03
## Seconds a run takes to creep to its full length.
const RUN_SECONDS := 9.0
## The road's crossfall toward its kerbs (real streets drain at about 2 %).
const CAMBER := 0.02
## Ground flatter than this lets a pool spread round.
const FLAT_GRADE := 0.006
## Longest rivulet off a pool, and the farthest a pool sends one to a kerb.
const RIVULET_MAX := 3.2
## Seconds the rivulet waits (the pool has to reach its edge first) and takes to creep.
const RIVULET_DELAY := 2.6
const RIVULET_CREEP := 11.0
## The gutter's distance in from the kerb face.
const GUTTER_IN := 0.22
## How many road drops a body on a moving car may leave, and how far apart.
const CAR_TRAIL_MAX := 28
const CAR_TRAIL_STEP := 0.55

static var _enabled: int = -1


static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 0 if OS.get_environment("BLOOD_GORE_2") == "0" else 1
	return _enabled == 1


## For tests: switch the whole pass on or off.
static func force(on: bool) -> void:
	_enabled = 1 if on else 0


## A wound's run length (metres) from its stain radius.
static func run_length(radius: float) -> float:
	return 0.16 + radius * 1.4


## How far along its run a wound `age` seconds old is (0..1).
static func run_share(age: float) -> float:
	return smoothstep(0.3, RUN_SECONDS, age)


# --- Pools ------------------------------------------------------------------------------------

## Which way blood runs on the ground at `at` (local space, `normal` the ground's up): the
## ground's own downhill, plus the road's camber toward its nearer kerb when `at` is on a
## carriageway. Returns {dir: unit horizontal Vector3 or ZERO, grade, kerb: distance to the
## gutter along dir or -1}.
static func flow(node: Node, at: Vector3, normal: Vector3) -> Dictionary:
	var n := normal.normalized() if not normal.is_zero_approx() else Vector3.UP
	var down := Vector3(n.x, 0.0, n.z)
	var g := down.length() / maxf(n.y, 0.2)
	var dir := down.normalized() * g if g > 0.001 else Vector3.ZERO
	var kerb := -1.0
	var road := _road_at(node, at)
	if not road.is_empty():
		var c: Vector3 = road.cross
		dir += c * CAMBER
		kerb = float(road.kerb)
	var grade := dir.length()
	if grade < FLAT_GRADE:
		return {"dir": Vector3.ZERO, "grade": grade, "kerb": -1.0}
	var u := dir / grade
	# The kerb only stops it when it runs that way.
	if not road.is_empty() and u.dot(road.cross as Vector3) < 0.5:
		kerb = -1.0
	return {"dir": u, "grade": grade, "kerb": kerb, "along": road.get("along", Vector3.ZERO)}


## The carriageway under `at` (local space) in the city: {cross: unit vector across the road
## toward the nearer kerb, kerb: metres to that kerb's gutter, along: the road's direction}, or
## empty off the roads, in a junction, or outside the city.
static func _road_at(node: Node, at: Vector3) -> Dictionary:
	if node == null or not node.is_inside_tree():
		return {}
	var scene := node.get_tree().current_scene
	var plan = scene.get("plan") if scene != null else null
	if plan == null or not (plan is Object) or not plan.has_method("block_index_at"):
		return {}
	var ws := node.get_tree().root.get_node_or_null("/root/WorldState")
	var w: Vector3 = ws.to_world(at) if ws != null else at
	var p := Vector2(w.x, w.z)
	var cp = plan
	var bi: Vector2i = cp.block_index_at(p)
	var hit_x := {}
	var hit_z := {}
	for i in [bi.x, bi.x + 1]:
		var c: float = cp.road_pos(AXIS_X, i)
		var hw: float = cp.road_width(AXIS_X, i) * 0.5
		if absf(p.x - c) < hw:
			var side := signf(p.x - c) if absf(p.x - c) > 0.05 else 1.0
			hit_x = {"cross": Vector3(side, 0.0, 0.0), "kerb": hw - absf(p.x - c) - GUTTER_IN, "along": Vector3(0.0, 0.0, 1.0)}
	for i in [bi.y, bi.y + 1]:
		var c: float = cp.road_pos(AXIS_Z, i)
		var hw: float = cp.road_width(AXIS_Z, i) * 0.5
		if absf(p.y - c) < hw:
			var side := signf(p.y - c) if absf(p.y - c) > 0.05 else 1.0
			hit_z = {"cross": Vector3(0.0, 0.0, side), "kerb": hw - absf(p.y - c) - GUTTER_IN, "along": Vector3(1.0, 0.0, 0.0)}
	# On one road, not in the junction square where two meet.
	if hit_x.is_empty() == hit_z.is_empty():
		return {}
	var r: Dictionary = hit_x if not hit_x.is_empty() else hit_z
	r.kerb = maxf(float(r.kerb), 0.0)
	return r


## A pool just laid at `at`: turned and stretched down the flow and slid a little that way, then
## (once it has spread to its edge) a rivulet creeping off downhill; if it reaches the kerb, a
## puddle spreading along the gutter. Called by WeaponFX.blood_pool().
static func pool_laid(node: Node, pool: Node3D, at: Vector3, normal: Vector3) -> void:
	if not enabled() or pool == null or not is_instance_valid(pool):
		return
	var f := flow(node, at, normal)
	var dir: Vector3 = f.dir
	if dir == Vector3.ZERO:
		return
	var n := normal.normalized()
	var grade: float = f.grade
	pool.set_meta("flow", dir)
	pool.set_meta("aspect", clampf(1.15 + grade * 14.0, 1.15, 1.75))
	pool.global_transform = Transform3D(WeaponFX._basis_on(n, dir), at + n * 0.018 + dir * clampf(grade * 9.0, 0.05, 0.3))
	var length := RIVULET_MAX * clampf(0.35 + grade * 22.0, 0.35, 1.0)
	var kerb: float = f.kerb
	var to_gutter := kerb >= 0.0 and kerb < RIVULET_MAX
	if to_gutter:
		length = maxf(kerb - WeaponFX.blood_pool_size * 0.4, 0.3)
	var start := at + dir * WeaponFX.blood_pool_size * 0.35
	var riv := _creep(pool, WeaponFX._KIND_RIVULET, start, n, dir, 0.16, length, RIVULET_DELAY, RIVULET_CREEP)
	if riv != null:
		riv.set_meta("rivulet", true)
		pool.set_meta("rivulet", riv)
	if to_gutter and riv != null:
		# Where it meets the kerb it spreads along the gutter both ways, longer than it is wide.
		var along: Vector3 = f.get("along", Vector3.RIGHT)
		var g_at := start + dir * length
		var gutter := WeaponFX._splat(pool, WeaponFX._KIND_POOL, Transform3D(WeaponFX._basis_on(n, along), g_at + n * 0.016),
			Vector3(0.12, 0.5, 0.08), WeaponFX.blood_pool_life, RIVULET_DELAY + RIVULET_CREEP * 0.8, false)
		if gutter != null:
			gutter.set_meta("gutter", true)
			pool.set_meta("gutter", gutter)
			var target := Vector3(1.4, 0.5, 0.32)
			var t := gutter.create_tween()
			t.tween_interval(RIVULET_DELAY + RIVULET_CREEP * 0.8 + 0.1)
			t.tween_method(func(k: float) -> void: WeaponFX._set_extent(gutter, Vector3(0.12, 0.5, 0.08).lerp(target, k)),
				0.0, 1.0, 9.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## A run of blood (kind `kind`) creeping from `start` along `dir` on a surface facing `n`, `width`
## wide, out to `length` after `delay`, over `seconds`. A child of `host` (its cap takes it too).
static func _creep(host: Node, kind: int, start: Vector3, n: Vector3, dir: Vector3, width: float, length: float,
		delay: float, seconds: float) -> Node3D:
	var basis := WeaponFX._basis_on(n, dir, true)
	var first := 0.08
	var run := WeaponFX._splat(host, kind, Transform3D(basis, start + n * 0.017 + dir * first * 0.5),
		Vector3(width, 0.5, first), WeaponFX.blood_pool_life, delay, false)
	if run == null:
		return null
	var creep := func(k: float) -> void:
		var now := lerpf(first, length, k)
		WeaponFX._set_extent(run, Vector3(width * lerpf(0.8, 1.0, k), 0.5, now))
		if is_instance_valid(run):
			run.global_position = start + n * 0.017 + dir * now * 0.5
	var t := run.create_tween()
	t.tween_interval(delay + 0.1)
	t.tween_method(creep, 0.0, 1.0, seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	return run


## Paints the rivulet's thickness field (WeaponFX.blood_textures, kind _KIND_RIVULET): one
## stream down the length of the mark (+V) that wanders side to side, wide where it leaves the
## pool and narrowing, with a rounded bead at its front and a short branch or two.
static func paint_rivulet(f: PackedFloat32Array, w: int, h: int, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var phase := rng.randf() * TAU
	var y := 0.0
	while y < h * 0.9:
		var t := y / float(h)
		var wob := sin(t * 9.0 + phase) * w * 0.07 + sin(t * 23.0 + phase * 2.0) * w * 0.025
		var r := w * lerpf(0.2, 0.08, t)
		WeaponFX._blob(f, w, h, x + wob, y, r, r * 1.3, 0.0, lerpf(0.95, 0.75, t))
		y += r * 0.6
	# The bead at the front, a little fatter than the stream.
	var tip := sin(0.9 * 9.0 + phase) * w * 0.07
	WeaponFX._blob(f, w, h, x + tip, h * 0.9, w * 0.13, w * 0.15, 0.0, 1.0)
	for i in 2:
		var by := h * rng.randf_range(0.25, 0.6)
		var bt := by / float(h)
		var bx := x + sin(bt * 9.0 + phase) * w * 0.07
		var side := -1.0 if i == 0 else 1.0
		for k in 5:
			WeaponFX._blob(f, w, h, bx + side * k * w * 0.05, by + k * h * 0.025, w * 0.05, w * 0.06, 0.0, 0.7 - k * 0.08)


# --- A body on a car --------------------------------------------------------------------------

## A bleeding body lying on a car (Ragdoll._blood_step, ten times a second): the first time, a
## smear on the paint under it and a run from there to the panel's edge, hosted by the car so it
## drives off with it; then drips off that edge, and drops on the road under it every
## CAR_TRAIL_STEP metres the car moves. `state` is the doll's own dictionary for this.
static func car_bleed(doll: Node3D, car: Node3D, under: Dictionary, bleed: float, state: Dictionary) -> void:
	if not enabled() or car == null or not is_instance_valid(car) or not car.is_inside_tree():
		return
	var at: Vector3 = under.position
	var n: Vector3 = under.normal
	if state.get("car") != car:
		state.clear()
		state["car"] = car
		var rest := WeaponFX._splat(car, WeaponFX._KIND_POOL, Transform3D(WeaponFX._basis_up(n, randf_range(-PI, PI)), at + n * 0.02),
			Vector3(0.25, 0.5, 0.25), WeaponFX.blood_pool_life, 0.0, false)
		if rest != null:
			var t := rest.create_tween()
			var size := WeaponFX.blood_pool_size * clampf(0.45 + 0.15 * bleed, 0.45, 0.9)
			t.tween_method(func(k: float) -> void: WeaponFX._set_extent(rest, Vector3(0.25, 0.5, 0.25).lerp(Vector3(size, 0.5, size * 0.8), k)),
				0.0, 1.0, 5.0).set_ease(Tween.EASE_OUT)
		var edge := _panel_edge(doll, car, at, n)
		if edge.is_empty():
			return
		var e: Vector3 = edge.at
		var out: Vector3 = edge.out
		var span := e - at
		var len := Vector3(span.x, 0.0, span.z).length()
		if len > 0.25:
			_creep(car, WeaponFX._KIND_RIVULET, at + out * 0.2, n, out, 0.12, maxf(len - 0.2, 0.2), 1.2, 6.0)
		# Down the face below the edge (the grille, the door): a run on the vertical panel.
		var face := _face_below(doll, car, e, out)
		if not face.is_empty():
			var fn: Vector3 = face.normal
			var fdown := (Vector3.DOWN - fn * fn.dot(Vector3.DOWN))
			if fdown.length() > 0.3:
				_creep(car, WeaponFX._KIND_DRIP, (face.position as Vector3) - fdown.normalized() * 0.02, fn, fdown.normalized(),
					0.18, 0.45, 5.0, 7.0)
		state["edge"] = car.global_transform.affine_inverse() * (e + out * 0.03)
		state["drip"] = WeaponFX.blood_drip(car, state.edge, 30.0, clampf(0.4 + 0.2 * bleed, 0.4, 1.0))
		state["last"] = e
		state["left"] = CAR_TRAIL_MAX
		return
	if not state.has("edge"):
		return
	# The trail: a drop on the road every CAR_TRAIL_STEP metres the edge has moved.
	var now: Vector3 = car.global_transform * (state.edge as Vector3)
	var last: Vector3 = state.last
	if int(state.left) > 0 and Vector2(now.x - last.x, now.z - last.z).length() > CAR_TRAIL_STEP:
		var skip: Array[RID] = []
		if car is CollisionObject3D:
			skip.append((car as CollisionObject3D).get_rid())
		WeaponFX.blood_splat_below(doll, now + Vector3.DOWN * 0.3, randf_range(0.18, 0.34), skip)
		state.last = now
		state.left = int(state.left) - 1
	# The drips run out with the body's bleeding; start them again while it still bleeds.
	if not is_instance_valid(state.get("drip")) and int(state.left) > 0 and bleed > 0.5:
		state["drip"] = WeaponFX.blood_drip(car, state.edge, 20.0, 0.5)


## The car's panel edge from `at` (on its top surface) the way blood would run off: down the
## surface's slope, or toward the nearest side of the car when it is flat. Marches out in 12 cm
## steps with rays down onto the car; the edge is the last step that still met it.
static func _panel_edge(doll: Node3D, car: Node3D, at: Vector3, n: Vector3) -> Dictionary:
	var space := doll.get_world_3d().direct_space_state
	var out := Vector3(n.x, 0.0, n.z)
	if out.length() < 0.08:
		# Flat (a roof): to the nearest of the car's sides in its own frame.
		var local := car.global_transform.affine_inverse() * at
		var aabb := _car_box(car)
		var dx := minf(absf(local.x - aabb.position.x), absf(aabb.end.x - local.x))
		var dz := minf(absf(local.z - aabb.position.z), absf(aabb.end.z - local.z))
		var ldir := Vector3(signf(local.x - aabb.get_center().x), 0.0, 0.0) if dx < dz else Vector3(0.0, 0.0, signf(local.z - aabb.get_center().z))
		out = car.global_basis * ldir
		out.y = 0.0
	out = out.normalized()
	var mask := (car as CollisionObject3D).collision_layer if car is CollisionObject3D else 4
	var last := at
	for i in 26:
		var p := at + out * 0.12 * float(i + 1)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 0.9, mask, _doll_rids(doll))
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.collider != car or (hit.position as Vector3).y < last.y - 0.35:
			return {"at": last, "out": out}
		last = hit.position
	return {}


## The vertical face of the car just below and in from its edge `e` (a ray in toward the car).
static func _face_below(doll: Node3D, car: Node3D, e: Vector3, out: Vector3) -> Dictionary:
	var space := doll.get_world_3d().direct_space_state
	var from := e + out * 0.4 + Vector3.DOWN * 0.12
	var mask := (car as CollisionObject3D).collision_layer if car is CollisionObject3D else 4
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from - out * 0.6, mask, _doll_rids(doll)))
	if hit.is_empty() or hit.collider != car or absf((hit.normal as Vector3).y) > 0.6:
		return {}
	return hit


static func _car_box(car: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in car.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var b := cs.transform * cs.shape.get_debug_mesh().get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box if not first else AABB(Vector3(-0.9, 0.0, -2.2), Vector3(1.8, 1.4, 4.4))


static func _doll_rids(doll: Node) -> Array[RID]:
	var out: Array[RID] = []
	for c in doll.find_children("*", "CollisionObject3D", true, false):
		out.append((c as CollisionObject3D).get_rid())
	return out


## Under a doll lying on something moving (a car, a van): the ray hit on that body, or empty.
## Props layer only (the cars), skipping the doll's own parts.
static func car_under(doll: Node3D, at: Vector3) -> Dictionary:
	if not enabled() or not doll.is_inside_tree():
		return {}
	var space := doll.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * 0.8, 4, _doll_rids(doll)))
	if hit.is_empty() or not (hit.collider is VehicleBody3D):
		return {}
	return hit


# --- Stumps -----------------------------------------------------------------------------------

## CityPlan's axes (named by number so this file compiles without the city's classes).
const AXIS_X := 0
const AXIS_Z := 1

## Stump radii (metres) by limb.
const STUMP_RADIUS := {"left_arm": 0.052, "right_arm": 0.052, "left_leg": 0.078, "right_leg": 0.078, "head": 0.06}

static var _stumps: Dictionary = {}
static var _stump_mat: Material


## A torn stump, facing +Y, `radius` metres: a ragged lip of skin and cloth turned out round a
## mound of muscle in bundles, a thin ring of yellow fat under the skin, and the bone's end
## standing out of the middle, broken, with dark marrow; strands of tissue hanging off the lip.
## Vertex colour is the tissue (sRGB, read by shaders/gib_stump.gdshader), alpha its kind
## (0 muscle, 0.33 fat, 0.66 bone, 1 skin / cloth lip). Cached per radius; ~600 triangles.
static func stump_mesh(radius: float) -> ArrayMesh:
	var key := snappedf(radius, 0.001)
	if _stumps.has(key):
		return _stumps[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(key * 100000.0) + 77
	const SEG := 20
	var lip := PackedFloat32Array()
	var lip_h := PackedFloat32Array()
	for i in SEG:
		lip.append(radius * rng.randf_range(0.92, 1.18))
		lip_h.append(radius * rng.randf_range(-0.15, 0.35))
	# Rings from the outside in: [radius share, height share, kind, colour]
	var rings := [
		[1.05, -0.45, 1.0, Color(0.36, 0.14, 0.11)],
		[1.0, 0.0, 1.0, Color(0.42, 0.12, 0.09)],
		[0.93, 0.12, 0.33, Color(0.78, 0.6, 0.32)],
		[0.84, 0.16, 0.0, Color(0.5, 0.05, 0.035)],
		[0.62, 0.32, 0.0, Color(0.42, 0.035, 0.025)],
		[0.38, 0.38, 0.0, Color(0.36, 0.025, 0.02)],
	]
	var pts: Array = []
	for r: Array in rings:
		var ring: Array = []
		for i in SEG:
			var a := TAU * float(i) / float(SEG)
			var rr: float = lip[i] * float(r[0]) * (1.0 if r[2] == 1.0 else rng.randf_range(0.93, 1.07))
			var hh: float = radius * float(r[1]) + (lip_h[i] if r[2] == 1.0 else rng.randf_range(-0.04, 0.06) * radius)
			ring.append([Vector3(cos(a) * rr, hh, sin(a) * rr), r[3], float(r[2])])
		pts.append(ring)
	for k in pts.size() - 1:
		for i in SEG:
			var j := (i + 1) % SEG
			_quad(st, pts[k][i], pts[k][j], pts[k + 1][j], pts[k + 1][i])
	# The muscle's middle closes on the bone.
	var bone_r := radius * 0.28
	var bone_top := radius * 0.62
	var inner: Array = pts[pts.size() - 1]
	var bone_ring: Array = []
	var bone_cap: Array = []
	const BSEG := 10
	for i in BSEG:
		var a := TAU * float(i) / float(BSEG)
		var broken := rng.randf_range(-0.18, 0.12) * radius
		bone_ring.append([Vector3(cos(a) * bone_r, radius * 0.36, sin(a) * bone_r), Color(0.86, 0.8, 0.68), 0.66])
		bone_cap.append([Vector3(cos(a) * bone_r * 0.95, bone_top + broken, sin(a) * bone_r * 0.95), Color(0.9, 0.84, 0.72), 0.66])
	for i in SEG:
		var j := (i + 1) % SEG
		var bi := int(float(i) / float(SEG) * BSEG) % BSEG
		var bj := int(float(i + 1) / float(SEG) * BSEG) % BSEG
		_tri(st, inner[i], inner[j], bone_ring[bj])
		if bi != bj:
			_tri(st, inner[i], bone_ring[bj], bone_ring[bi])
	for i in BSEG:
		var j := (i + 1) % BSEG
		_quad(st, bone_ring[i], bone_ring[j], bone_cap[j], bone_cap[i])
	# The broken end: a ring of compact bone round the marrow.
	var marrow: Array = []
	for i in BSEG:
		var p: Vector3 = bone_cap[i][0]
		marrow.append([Vector3(p.x * 0.55, p.y - radius * 0.03, p.z * 0.55), Color(0.3, 0.03, 0.025), 0.66])
	var centre := [Vector3(0.0, bone_top - radius * 0.08, 0.0), Color(0.22, 0.02, 0.02), 0.66]
	for i in BSEG:
		var j := (i + 1) % BSEG
		_quad(st, bone_cap[i], bone_cap[j], marrow[j], marrow[i])
		_tri(st, marrow[i], marrow[j], centre)
	# Strands of tissue hanging off the lip (two-sided ribbons).
	for s in 4:
		var i := rng.randi_range(0, SEG - 1)
		var a := TAU * float(i) / float(SEG)
		var root := Vector3(cos(a), 0.0, sin(a)) * lip[i] * 0.97 + Vector3.UP * lip_h[i]
		var side := Vector3(-sin(a), 0.0, cos(a)) * radius * rng.randf_range(0.12, 0.22)
		var hang := Vector3(cos(a) * radius * 0.25, -radius * rng.randf_range(0.6, 1.3), sin(a) * radius * 0.25)
		var c := Color(0.45, 0.05, 0.035)
		var v0 := [root - side, c, 0.0]
		var v1 := [root + side, c, 0.0]
		var v2 := [root + hang + side * 0.3, c, 0.0]
		var v3 := [root + hang - side * 0.3, c, 0.0]
		_quad(st, v0, v1, v2, v3)
		_quad(st, v1, v0, v3, v2)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, stump_material())
	_stumps[key] = mesh
	return mesh


static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	# Godot's front faces wind clockwise seen from outside: the stump is seen from +Y and outside.
	for v: Array in [a, c, b]:
		var col: Color = v[1]
		st.set_color(Color(col.r, col.g, col.b, float(v[2])))
		st.set_uv(Vector2((v[0] as Vector3).x, (v[0] as Vector3).z) * 20.0)
		st.add_vertex(v[0])


static func _quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


static func stump_material() -> Material:
	if _stump_mat == null:
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/gib_stump.gdshader")
		_stump_mat = m
	return _stump_mat
