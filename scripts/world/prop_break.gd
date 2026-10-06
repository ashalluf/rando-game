class_name PropBreak
extends RefCounted
## How the street's props break (GTA-style), by their KIND, never by their mesh: the meshes are
## whatever the prop's batch instances carry (street lamps are StreetLamps' models, the furniture
## is being replaced in parallel), and the broken pieces are copies of those very instances (a
## one-instance MultiMesh each, so their colour and custom data - a newsbox's paint, a lamp's
## type - come along). CityChunk's prop records drive it: `_add_prop()` keeps each instance's
## mesh, final transform, colour and custom data; `damage_prop()` / `break_prop()` hand over here.
##   hydrant      sheared off its flange and thrown up; a geyser (HydrantGeyser) for a while,
##                the pavement soaked round it, the flange left standing
##   bus_stop     the glass bursts into tempered cubes (PropShards) and the frame stays; hit
##                again (or by a fast car) the frame comes down in pieces
##   lamp         a round pops the lamp (the light goes out, glass tinkles); a hard hit (a car, a
##                blast) BENDS it over at the foot, a harder one or a second fells it - it
##                swings down on a hinge at its base, lets go and slams onto the street
##   stop_sign, street_sign, signal   the same lean and fall (a sign shot to bits falls too)
##   mailbox, newsbox   burst open: letters / newspapers thrown up and fluttering down, the box
##                knocked over
##   meter        snapped off at the foot and thrown, coins everywhere, a stub of pipe left
## Cars smash through what they hit fast (`smash_ahead()`, a box query ahead of every physical
## car moving over SMASH_MIN, from Vehicle's step): the prop breaks BEFORE the solver meets it,
## the car loses a share of its speed (SLOW) and takes a crash dent. Anything else breaks as it
## always did (CityChunk._spawn_debris). Debris bodies are PhysicsBudget debris.
## `PROP_BREAK=0` in the environment turns all of it off (the A/B).

static var enabled: bool = OS.get_environment("PROP_BREAK") != "0"

## Damage that fells a pole at once (a hit between LEAN_FROM and this bends it).
const FALL_AT := {"lamp": 60.0, "stop_sign": 30.0, "street_sign": 30.0, "signal": 110.0}
## A hit at least this hard bends a pole; anything less is a round (it pops a lamp, chips a sign).
const LEAN_FROM := 22.0
## Most a pole bends before it goes over (radians), and the bend per damage over LEAN_FROM.
const MAX_LEAN := 0.46
const LEAN_PER_DAMAGE := 0.0085
## Masses of the pieces (kg).
const MASS := {"lamp": 160.0, "stop_sign": 18.0, "street_sign": 22.0, "signal": 260.0,
	"hydrant": 75.0, "mailbox": 45.0, "newsbox": 28.0, "meter": 20.0, "bus_stop": 60.0}
## A bus shelter's frame, once the glass is gone.
const FRAME_HEALTH := 70.0
## A car this fast takes the whole shelter down at once.
const SHELTER_SMASH_SPEED := 12.0
## Cars: the slowest that smashes through (m/s), damage per m/s, the share of speed each kind
## costs, and the crash dent (m/s of the car's speed it is worth).
const SMASH_MIN := 5.0
const SMASH_DAMAGE := 9.0
const SLOW := {"lamp": 0.2, "signal": 0.35, "hydrant": 0.12, "bus_stop": 0.22, "mailbox": 0.08,
	"newsbox": 0.05, "meter": 0.04, "stop_sign": 0.04, "street_sign": 0.05}
const DENT_SHARE := 0.22
## Seconds the broken bodies stay before PhysicsBudget clears them.
const BODY_LIFE := 90.0
## How much of a felled pole's box is cut off its foot (m).
const FOOT_CLEAR := 0.45
## Instance keys that are light, not stuff (a lamp's pool, a shop's spill).
const GLOW_WORDS := ["pool", "glow", "spill", "beam"]


# --- Hooks from CityChunk -------------------------------------------------------------------

## damage_prop()'s hook: true when the hit was dealt with here (no health taken the usual way).
static func damage(ch: CityChunk, record: Dictionary, amount: float, dir: Vector3) -> bool:
	var kind: String = record.kind
	if not FALL_AT.has(kind):
		return false
	if amount < LEAN_FROM:
		if kind == "lamp":
			# Rounds pop the lamp; they never fell the post.
			lamp_out(ch, record)
			return true
		return false
	var lean: float = record.get("lean_angle", 0.0) + (amount - LEAN_FROM) * LEAN_PER_DAMAGE + 0.05
	if amount >= float(FALL_AT[kind]) or lean >= MAX_LEAN:
		record["fall_push"] = amount
		ch.break_prop(record, dir)
		return true
	_lean(ch, record, dir, lean)
	return true


## break_prop()'s first hook: true when the prop survives this break as something less (a bus
## shelter that loses its glass and keeps its frame).
static func survives(ch: CityChunk, record: Dictionary, dir: Vector3) -> bool:
	if record.kind != "bus_stop" or record.get("glass_gone", false):
		return false
	_shatter_glass(ch, record, dir)
	record.health = FRAME_HEALTH
	return float(record.get("smash_speed", 0.0)) < SHELTER_SMASH_SPEED


## break_prop()'s second hook (the instances are hidden, the shapes going): the pieces. False
## for a kind this does not know, which breaks the old way.
static func broke(ch: CityChunk, record: Dictionary, dir: Vector3) -> bool:
	match String(record.kind):
		"hydrant":
			_hydrant(ch, record, dir)
		"lamp", "stop_sign", "street_sign", "signal":
			if record.kind == "lamp":
				lamp_out(ch, record)
			_topple(ch, record, dir)
		"bus_stop":
			_shelter_down(ch, record, dir)
		"mailbox", "newsbox":
			_box_burst(ch, record, dir)
		"meter":
			_meter_snap(ch, record, dir)
		_:
			return false
	return true


## A destroyed prop on a rebuilt chunk: what a broken one leaves standing (a hydrant's flange, a
## meter's stub, a lamp's foot). `at` is the prop's place before the relief.
static func remains(ch: CityChunk, kind: String, at: Vector3) -> void:
	if not enabled or ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	if not STUBS.has(kind):
		return
	_stub(ch, kind, at + Vector3(0.0, ch._gy(at.x, at.z), 0.0))


## A street lamp's OmniLight3D, made after its prop: the lamp's record keeps it, so a lamp that
## goes out or falls takes its light with it (it used to burn on over the empty pavement).
static func own_light(ch: CityChunk, light: OmniLight3D) -> void:
	if ch.prop_records.is_empty():
		return
	var r: Dictionary = ch.prop_records.back()
	if r.kind == "lamp" and not r.has("light") and not r.dead:
		r["light"] = light


# --- Lamps and poles --------------------------------------------------------------------------

## Pops a lamp: its light and pool go, a tinkle of glass from its head.
static func lamp_out(ch: CityChunk, record: Dictionary) -> void:
	if record.get("out", false):
		return
	record["out"] = true
	for e in record.instances:
		if e.size() > 2 and _is_glow(String(e[0])):
			MultiMeshBatch.hide_instance(ch._mm_nodes.get(e[0]), e[1])
	var light: Variant = record.get("light")
	if light is OmniLight3D and is_instance_valid(light):
		(light as OmniLight3D).queue_free()
	record.erase("light")
	var head := _head(record)
	var g := ch.to_global(head)
	Sfx.play("hit_glass", g, 2.0)
	var frame := Transform3D(Basis(), head)
	PropShards.burst(ch, PropShards.Kind.GLASS, frame, AABB(Vector3(-0.25, -0.15, -0.25), Vector3(0.5, 0.3, 0.5)), _n(40), Vector3.ZERO, 1.2, Vector2(-0.5, 1.5), ch.to_global(record.position).y, hash(record.id))


## Bends the pole over at its foot to `angle` (toward `dir`): every instance and its shape turned
## about the base. A bent lamp is a dead lamp.
static func _lean(ch: CityChunk, record: Dictionary, dir: Vector3, angle: float) -> void:
	var axis: Vector3 = record.get("lean_axis", Vector3.ZERO)
	if axis == Vector3.ZERO:
		var h := Vector3(dir.x, 0.0, dir.z)
		if h.length_squared() < 1e-4:
			h = Vector3.FORWARD
		axis = Vector3.UP.cross(h.normalized()).normalized()
		record["lean_axis"] = axis
	record["lean_angle"] = angle
	var turn := _pivot(record.position, Basis(axis, angle))
	for e in record.instances:
		if e.size() < 4:
			continue
		if _is_glow(String(e[0])):
			continue
		var node := ch._mm_nodes.get(e[0]) as MultiMeshInstance3D
		_set_instance(node, e[1], turn * (e[3] as Transform3D))
	var bases: Array = record.get("shape_xf", [])
	if bases.is_empty():
		for s in record.shapes:
			bases.append((s as CollisionShape3D).transform if is_instance_valid(s) else Transform3D())
		record["shape_xf"] = bases
	for i in record.shapes.size():
		var s := record.shapes[i] as CollisionShape3D
		if is_instance_valid(s):
			s.transform = turn * (bases[i] as Transform3D)
	if record.kind == "lamp":
		lamp_out(ch, record)
	var g := ch.to_global(record.position)
	Sfx.play("hit_metal", g + Vector3.UP, 3.0, 0.7)
	WeaponFX.impact(ch, g + Vector3.UP * 0.25, Color(1.0, 0.8, 0.45))


## Fells a pole: one body of every piece of it, hinged at its foot, swung over the way it was hit.
static func _topple(ch: CityChunk, record: Dictionary, dir: Vector3) -> void:
	var parts := _parts(record, false)
	if parts.is_empty() or not PhysicsBudget.make_room(1):
		return
	var h := Vector3(dir.x, 0.0, dir.z)
	if h.length_squared() < 1e-4:
		h = Vector3(sin(float(hash(record.id) % 628) * 0.01), 0.0, cos(float(hash(record.id) % 628) * 0.01))
	h = h.normalized()
	var axis: Vector3 = record.get("lean_axis", Vector3.UP.cross(h).normalized())
	# A post that goes over starts from a kick at its foot, not from dead upright.
	var angle: float = maxf(record.get("lean_angle", 0.0), 0.12)
	var lean := Basis(axis, angle)
	var base: Vector3 = record.position
	var body := FallingPole.new()
	body.mass = MASS.get(record.kind, 40.0)
	body.transform = Transform3D(lean, base)
	var turn := _pivot(base, lean)
	var inv := body.transform.affine_inverse()
	for e in parts:
		var piece := _copy(e, inv * turn * (e[3] as Transform3D))
		if record.kind == "signal":
			# A felled signal is dark (traffic_signal.gdshader reads custom.b).
			var c: Color = e[5]
			piece.multimesh.set_instance_custom_data(0, Color(c.r, c.g, 1.0, c.a))
		body.add_child(piece)
	# The collision: the prop's own boxes, in the pole's upright frame.
	var upright := Transform3D(Basis(), base).affine_inverse()
	var bases: Array = record.get("shape_xf", [])
	for i in record.shapes.size():
		var s := record.shapes[i] as CollisionShape3D
		if not is_instance_valid(s) or not (s.shape is BoxShape3D):
			continue
		var xf: Transform3D = bases[i] if i < bases.size() else s.transform
		var c := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = (s.shape as BoxShape3D).size
		c.shape = b
		c.transform = upright * xf
		# Its foot kept off the pavement: a box swung about its own bottom edge digs its corner
		# into the ground, which stood the pole back up.
		var cut := minf(FOOT_CLEAR, b.size.y * 0.3)
		b.size.y -= cut
		c.position.y += cut * 0.5
		body.add_child(c)
	if body.get_child_count() == parts.size():
		var c := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.3, 4.0, 0.3)
		c.shape = b
		c.position = Vector3(0.0, 2.0, 0.0)
		body.add_child(c)
	ch.add_child(body)
	PhysicsBudget.register_debris(body, BODY_LIFE)
	var push: float = record.get("fall_push", 40.0)
	body.angular_velocity = axis * clampf(0.35 + push * 0.006, 0.4, 1.6)
	body.hinge(ch, axis)
	# The car that felled it drives on through: a hinged pole is pinned to the world, which
	# would stop it dead.
	var car: Variant = record.get("smasher")
	if car is PhysicsBody3D and is_instance_valid(car):
		body.pass_through(car)
	var g := ch.to_global(base)
	Sfx.play("crash", g + Vector3.UP * 0.5, 0.0, 1.25)
	WeaponFX.impact(ch, g + Vector3.UP * 0.3, Color(1.0, 0.75, 0.4))


# --- Hydrant ----------------------------------------------------------------------------------

static func _hydrant(ch: CityChunk, record: Dictionary, dir: Vector3) -> void:
	var base: Vector3 = record.position
	var parts := _parts(record, false)
	if not parts.is_empty() and PhysicsBudget.make_room(1):
		var body := _body_of(parts, MASS.hydrant, base)
		ch.add_child(body)
		PhysicsBudget.register_debris(body, BODY_LIFE)
		var h := Vector3(dir.x, 0.0, dir.z).limit_length(1.0)
		body.linear_velocity = Vector3.UP * 11.0 + h * 2.5
		body.angular_velocity = Vector3(_r(record, 1) * 8.0, _r(record, 2) * 4.0, _r(record, 3) * 8.0)
	_stub(ch, "hydrant", base)
	HydrantGeyser.start(ch, base + Vector3(0.0, 0.08, 0.0))
	var g := ch.to_global(base)
	Sfx.play("break", g, 3.0, 0.8)
	Sfx.play("hit_metal", g + Vector3.UP * 0.5, 4.0, 0.6)


# --- Bus shelter ------------------------------------------------------------------------------

static func _shatter_glass(ch: CityChunk, record: Dictionary, dir: Vector3) -> void:
	record["glass_gone"] = true
	for e in record.instances:
		if e.size() > 2 and String(e[0]).contains("glass"):
			MultiMeshBatch.hide_instance(ch._mm_nodes.get(e[0]), e[1])
	var s := record.shapes[0] as CollisionShape3D if not record.shapes.is_empty() else null
	var frame := Transform3D(Basis(), record.position + Vector3(0.0, 1.3, 0.0))
	var size := Vector3(4.2, 2.6, 1.0)
	if s and is_instance_valid(s) and s.shape is BoxShape3D:
		frame = s.transform
		size = (s.shape as BoxShape3D).size
	var box := AABB(Vector3(-size.x * 0.46, -size.y * 0.44, -0.04), Vector3(size.x * 0.92, size.y * 0.84, 0.08))
	var h := Vector3(dir.x, 0.0, dir.z).limit_length(1.0)
	PropShards.burst(ch, PropShards.Kind.GLASS, frame, box, _n(340), h * 2.6, 1.3, Vector2(0.2, 2.4), ch.to_global(record.position).y, hash(record.id))
	var g := ch.to_global(frame.origin)
	Sfx.play("glass", g, 6.0)
	Sfx.play("hit_glass", g + Vector3.RIGHT, 4.0, 0.8)


static func _shelter_down(ch: CityChunk, record: Dictionary, dir: Vector3) -> void:
	if not record.get("glass_gone", false):
		_shatter_glass(ch, record, dir)
	var parts := _parts(record, true)
	var n := mini(parts.size(), 6)
	if n == 0 or not PhysicsBudget.make_room(n):
		return
	var h := Vector3(dir.x, 0.0, dir.z).limit_length(1.0)
	for i in n:
		var e: Array = parts[i]
		var body := _body_of([e], MASS.bus_stop / float(n), (e[3] as Transform3D).origin)
		ch.add_child(body)
		PhysicsBudget.register_debris(body, BODY_LIFE)
		body.linear_velocity = h * (2.0 + _r(record, 10 + i) * 1.5) + Vector3.UP * (1.5 + absf(_r(record, 20 + i)) * 2.0)
		body.angular_velocity = Vector3(_r(record, 30 + i), _r(record, 40 + i), _r(record, 50 + i)) * 2.5
	Sfx.play("crash", ch.to_global(record.position + Vector3.UP), 3.0, 0.9)


# --- Mailbox, news box, meter -----------------------------------------------------------------

static func _box_burst(ch: CityChunk, record: Dictionary, dir: Vector3) -> void:
	var base: Vector3 = record.position
	var size := _shape_size(record, Vector3(0.6, 1.2, 0.5))
	var h := Vector3(dir.x, 0.0, dir.z).limit_length(1.0)
	var parts := _parts(record, false)
	if not parts.is_empty() and PhysicsBudget.make_room(1):
		var body := _body_of(parts, MASS.get(record.kind, 30.0), base)
		ch.add_child(body)
		PhysicsBudget.register_debris(body, BODY_LIFE)
		body.linear_velocity = h * 3.5 + Vector3.UP * 2.0
		body.angular_velocity = Vector3.UP.cross(h) * 3.0 + Vector3(0.0, _r(record, 4) * 2.0, 0.0)
	var mail: bool = record.kind == "mailbox"
	var frame := Transform3D(Basis(), base + Vector3(0.0, size.y * 0.75, 0.0))
	var box := AABB(Vector3(-size.x * 0.4, -size.y * 0.2, -size.z * 0.4), Vector3(size.x * 0.8, size.y * 0.4, size.z * 0.8))
	PropShards.burst(ch, PropShards.Kind.LETTER if mail else PropShards.Kind.NEWSPAPER, frame, box,
			_n(70 if mail else 36), h * 1.8, 1.6, Vector2(3.0, 7.5), ch.to_global(base).y, hash(record.id))
	var g := ch.to_global(frame.origin)
	Sfx.play("hit_metal", g, 4.0, 0.85)
	Sfx.play("break", g, 0.0, 1.2)


static func _meter_snap(ch: CityChunk, record: Dictionary, dir: Vector3) -> void:
	var base: Vector3 = record.position
	var size := _shape_size(record, Vector3(0.2, 1.4, 0.2))
	var h := Vector3(dir.x, 0.0, dir.z).limit_length(1.0)
	var parts := _parts(record, false)
	if not parts.is_empty() and PhysicsBudget.make_room(1):
		var body := _body_of(parts, MASS.meter, base + Vector3(0.0, 0.05, 0.0))
		body.position += Vector3.UP * 0.06
		ch.add_child(body)
		PhysicsBudget.register_debris(body, BODY_LIFE)
		body.linear_velocity = h * 7.0 + Vector3.UP * 4.0
		body.angular_velocity = Vector3.UP.cross(h) * 7.0 + Vector3(0.0, _r(record, 5) * 5.0, 0.0)
	_stub(ch, "meter", base)
	var frame := Transform3D(Basis(), base + Vector3(0.0, size.y - 0.2, 0.0))
	PropShards.burst(ch, PropShards.Kind.COIN, frame, AABB(Vector3(-0.08, -0.1, -0.08), Vector3(0.16, 0.2, 0.16)),
			_n(34), h * 2.0, 1.4, Vector2(1.0, 3.5), ch.to_global(base).y, hash(record.id))
	var g := ch.to_global(frame.origin)
	Sfx.play("hit_metal", g, 4.0, 1.1)
	Sfx.play("casing", g, 0.0, 0.8)


# --- Cars smash through -----------------------------------------------------------------------

static var _smash_box := BoxShape3D.new()
static var _smash_q: PhysicsShapeQueryParameters3D

## Vehicle's step hook: breaks what the car is about to hit at speed, before the solver stops it.
static func smash_ahead(car: Vehicle, delta: float) -> void:
	if not enabled or car.freeze or not car.is_inside_tree():
		return
	var v := car.linear_velocity
	var speed := v.length()
	if speed < SMASH_MIN:
		return
	var d: Dictionary = car._dims()
	if _smash_q == null:
		_smash_q = PhysicsShapeQueryParameters3D.new()
		_smash_q.shape = _smash_box
		_smash_q.collision_mask = 1
	_smash_box.size = Vector3(float(d.width), 1.3, float(d.length))
	var xf := car.global_transform.orthonormalized()
	xf.origin += xf.basis.y * 0.45 + v * delta * 1.5
	_smash_q.transform = xf
	_smash_q.exclude = [car.get_rid()]
	var hits := car.get_world_3d().direct_space_state.intersect_shape(_smash_q, 6)
	for hit in hits:
		var sp := hit.collider as StreetProps
		if sp == null or sp.chunk == null:
			continue
		var record := record_of(sp, int(hit.shape))
		if record.is_empty() or record.dead:
			continue
		var glass_before: bool = record.get("glass_gone", false)
		record["smash_speed"] = speed
		record["smasher"] = car
		var ch := sp.chunk as CityChunk
		ch.damage_prop(record, speed * SMASH_DAMAGE, v / speed)
		if record.dead or record.get("glass_gone", false) != glass_before:
			car.hold_crash_watch(2)
			car.linear_velocity = v * (1.0 - float(SLOW.get(record.kind, 0.1)))
			var at := ch.to_global(record.position) + Vector3.UP * 0.6
			car.take_hit(-1, speed * DENT_SHARE, v / speed, at, Vehicle.HIT_CRASH)


## The prop record a StreetProps shape belongs to (empty if none).
static func record_of(sp: StreetProps, shape_index: int) -> Dictionary:
	if shape_index < 0:
		return {}
	var owner_id := sp.shape_find_owner(shape_index)
	var node := sp.shape_owner_get_owner(owner_id) as CollisionShape3D
	if node and node.has_meta("prop"):
		return node.get_meta("prop")
	return {}


# --- Pieces -----------------------------------------------------------------------------------

## The instances that are stuff, not light ([key, index, mesh, xform, color, custom]); without
## the glass when `no_glass`.
static func _parts(record: Dictionary, no_glass: bool) -> Array:
	var out: Array = []
	for e in record.instances:
		if e.size() < 6 or _is_glow(String(e[0])):
			continue
		if no_glass and String(e[0]).contains("glass"):
			continue
		out.append(e)
	return out


static func _is_glow(key: String) -> bool:
	for w in GLOW_WORDS:
		if key.contains(w):
			return true
	return false


## One instance as a node of its own: a one-instance MultiMesh, so the batch's colour and custom
## data still reach its shader.
static func _copy(e: Array, xf: Transform3D) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = e[2]
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_color(0, e[4])
	mm.set_instance_custom_data(0, e[5])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


## A rigid body of `parts` with its origin at `origin` (chunk space), a box from their meshes.
static func _body_of(parts: Array, mass: float, origin: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "PropPiece"
	body.collision_layer = 4
	body.collision_mask = 7
	body.mass = maxf(mass, 1.0)
	body.position = origin
	var inv := Transform3D(Basis(), origin).affine_inverse()
	var bounds := AABB()
	var first := true
	for e in parts:
		var xf: Transform3D = inv * (e[3] as Transform3D)
		body.add_child(_copy(e, xf))
		var ab := (e[2] as Mesh).get_aabb() if e[2] is Mesh else AABB()
		if ab.size.length_squared() < 1e-6:
			ab = AABB(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 0.8, 0.4))
		var box := xf * ab
		bounds = box if first else bounds.merge(box)
		first = false
	var c := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = bounds.size.max(Vector3.ONE * 0.08)
	c.shape = b
	c.position = bounds.get_center()
	body.add_child(c)
	return body


## What is left standing where a prop was (one small mesh node in the chunk).
const STUBS := {
	"hydrant": [0.14, 0.12, Color(0.32, 0.12, 0.1)],
	"meter": [0.035, 0.28, Color(0.28, 0.29, 0.3)],
	"lamp": [0.17, 0.32, Color(0.25, 0.26, 0.28)],
	"stop_sign": [0.035, 0.18, Color(0.5, 0.5, 0.52)],
	"street_sign": [0.035, 0.18, Color(0.5, 0.5, 0.52)],
}
static var _stub_mats: Dictionary = {}


static func _stub(ch: CityChunk, kind: String, base: Vector3) -> void:
	if not STUBS.has(kind):
		return
	var spec: Array = STUBS[kind]
	var cyl := CylinderMesh.new()
	cyl.top_radius = float(spec[0]) * (0.8 if kind == "hydrant" else 1.0)
	cyl.bottom_radius = spec[0]
	cyl.height = spec[1]
	cyl.radial_segments = 14
	cyl.rings = 1
	if not _stub_mats.has(kind):
		var m := StandardMaterial3D.new()
		m.albedo_color = spec[2]
		m.metallic = 0.6
		m.roughness = 0.55
		_stub_mats[kind] = m
	cyl.material = _stub_mats[kind]
	var mi := MeshInstance3D.new()
	mi.name = "PropStub"
	mi.mesh = cyl
	mi.position = base + Vector3(0.0, float(spec[1]) * 0.5, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 120.0
	ch.add_child(mi)


static func _set_instance(node: MultiMeshInstance3D, index: int, xf: Transform3D) -> void:
	if node == null or index < 0 or index >= node.multimesh.instance_count:
		return
	node.multimesh.set_instance_transform(index, xf)
	var twin := node.get_meta("shadow_twin") as MultiMeshInstance3D if node.has_meta("shadow_twin") else null
	if twin and is_instance_valid(twin) and index < twin.multimesh.instance_count:
		twin.multimesh.set_instance_transform(index, xf)


## A turn about `base`.
static func _pivot(base: Vector3, b: Basis) -> Transform3D:
	return Transform3D(Basis(), base) * Transform3D(b, Vector3.ZERO) * Transform3D(Basis(), -base)


## The top of a prop's first box (chunk space): a lamp's head.
static func _head(record: Dictionary) -> Vector3:
	var size := _shape_size(record, Vector3(0.3, 4.0, 0.3))
	return (record.position as Vector3) + Vector3(0.0, size.y - 0.2, 0.0)


static func _shape_size(record: Dictionary, fallback: Vector3) -> Vector3:
	for s in record.shapes:
		if is_instance_valid(s) and (s as CollisionShape3D).shape is BoxShape3D:
			return ((s as CollisionShape3D).shape as BoxShape3D).size
	return fallback


## -1..1 from the record and a salt (the same break throws the same way).
static func _r(record: Dictionary, salt: int) -> float:
	return float(absi(hash([record.id, salt])) % 20001) / 10000.0 - 1.0


## Fewer pieces on the web.
static func _n(count: int) -> int:
	return maxi(1, count / 2) if OS.has_feature("web") else count
