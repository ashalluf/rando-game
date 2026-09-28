class_name CarDamage
extends Node3D
## A car's damage (owner ask: the cars took no damage at all). Made by Vehicle the first time the
## car is hit - an undamaged car has none of this: no node, no script ticking, its own shared
## paint shader and the model's own glass and lamp materials.
##
## Everything funnels through Vehicle.take_hit(): rifle rounds and shotgun pellets punch holes in
## the paintwork (bright torn steel, primer and chipped paint round a black hole), craze or shatter
## the windows they hit (side and rear glass is tempered: it crazes into cubes and falls out; the
## windscreen is laminated and only collects spider webs), and break the lamp they hit. Blasts and
## hard crashes dent the body (vertex displacement toward the impact, crumpled, in the damage
## variant of the paint shader), scorch the side facing a blast and break the glass and lamps
## facing it. Health runs down with all of it: smoke from the engine bay past `smoke_at`, fire
## past `fire_at`, and after a burn of `burn_seconds` (a short `quick_fuse` after a rocket) the
## car blows up through Explosion.blast() and is left as a charred wreck - paint burnt to rust and
## ash, glass gone, tyres burnt down to the rims - that smokes for a while and is freed by
## PhysicsBudget like any other debris.
##
## All marks live in the body model's own mesh space (the hole, dent and crack arrays below are
## uniforms), so they ride the car. The paint material is swapped onto
## shaders/car_paint_damage.gdshader (the same shader with the damage compiled in), the glass
## slot onto car_glass_damage.gdshader and the lamp slots onto car_lamp_damage.gdshader, each the
## first time it is needed; the shadow twins follow.

## What kind of hit Vehicle.take_hit() was given (its `kind` argument).
enum Hit { PROP, BULLET, PELLET, BLAST, CRASH }
enum State { DAMAGED, SMOKING, BURNING, WRECK }

@export_group("Health")
## Hit points of a car.
@export var max_health: float = 1000.0
## Below this share of health the engine bay smokes; below `fire_at` it burns.
@export var smoke_at: float = 0.5
@export var fire_at: float = 0.2
## A round's own damage (the weapon's `bullet_damage` / `pellet_damage`) times this. A rifle round
## is 10: 12 hp on the body, so about 65 rounds set a car on fire, ~26 into the engine bay.
@export var bullet_scale: float = 1.2
## Rounds into the engine bay (the front third, or behind the cabin on a mid-engined exotic) do
## this many times the damage.
@export var engine_multiplier: float = 2.5
## Damage of a blast at its centre (Explosion.blast), scaled by its falloff at the car. A rocket
## on the car is ~1,300: straight to fire on the quick fuse.
@export var blast_damage: float = 1450.0
## Damage per m/s of a crash's velocity change over Vehicle.crash_min_dv: a 30 m/s wall is ~440,
## so two hard crashes leave a car smoking and a third sets it on fire. A crash never takes the
## quick fuse.
@export var crash_damage_per_dv: float = 20.0

@export_group("Fire")
## Seconds a car burns before it goes up, and the short fuse after one hit of at least
## `quick_fuse_damage` (a rocket).
@export var burn_seconds: Vector2 = Vector2(6.0, 9.0)
@export var quick_fuse: Vector2 = Vector2(0.9, 1.7)
@export var quick_fuse_damage: float = 600.0
## The car's own blast: radius (m), how hard it throws props and the player (m/s).
@export var blast_radius: float = 7.0
@export var blast_launch: float = 18.0
@export var blast_player_launch: float = 20.0
## How hard the wreck is thrown up by its own blast (m/s, a random share of it sideways).
@export var toss_speed: Vector2 = Vector2(5.5, 8.5)
## Seconds the wreck keeps burning, then smoking, and how long it stays before PhysicsBudget
## frees it.
@export var wreck_fire_seconds: float = 14.0
@export var wreck_smoke_seconds: float = 45.0
@export var wreck_lifetime: float = 150.0

@export_group("Fire look")
## Scale on every flame, lick and smoke puff of a car fire.
@export var flame_size: float = 1.0
## Energy of the flickering light under a fire (desktop; the web has none).
@export var fire_light_energy: float = 3.4
## Share of a burn after which the fire takes the cabin: the side glass pops and flames roll out
## of the empty frames and over the roof.
@export var spread_share: float = 0.45

@export_group("Marks")
## Radius of a rifle round's hole and a pellet's (m); the chipped paint round one runs to twice it.
@export var hole_radius: float = 0.0075
@export var pellet_hole_radius: float = 0.004
## Dents: the radius and depth (m) of a crash dent per m/s over the threshold, and the most a dent
## sinks.
@export var crash_dent_radius: Vector2 = Vector2(0.35, 0.045)
@export var crash_dent_depth: Vector2 = Vector2(0.02, 0.013)
@export var max_dent_depth: float = 0.28
## The dent and scorch a blast leaves at falloff 1.
@export var blast_dent_radius: float = 1.1
@export var blast_dent_depth: float = 0.2
## Tempered glass that crazes on a round falls out after this long this share of the time (the
## rest stays crazed until the next hit).
@export var glass_fall_seconds: Vector2 = Vector2(0.12, 0.45)
@export var glass_fall_share: float = 0.55

## Caps (shared by every car).
## Cars on fire at once: past it a car that should catch fire stays smoking until there is room.
static var max_burning: int = 6
## Smoke columns at once (a smoking car over the cap smokes without particles).
static var max_smoking: int = 10
## Wrecks kept at once: the oldest goes first.
static var max_wrecks: int = 10
## Glass bursts in the air at once.
static var max_glass_bursts: int = 8

const HOLE_CAP := 40
const DENT_CAP := 8
const CRACK_CAP := 12
const SCORCH_CAP := 4
const PAINT_DAMAGE_SHADER := preload("res://shaders/car_paint_damage.gdshader")
const GLASS_DAMAGE_SHADER := preload("res://shaders/car_glass_damage.gdshader")
const LAMP_DAMAGE_SHADER := preload("res://shaders/car_lamp_damage.gdshader")
## Where the engine is, as a share of the length from the middle (negative = toward the nose).
const MID_ENGINE := [Vehicle.BodyType.SUPER, Vehicle.BodyType.SPIDER, Vehicle.BodyType.HYPER, Vehicle.BodyType.TRACK]
## Lamp bits in `lamps_broken`.
const LAMP_HEAD_L := 1
const LAMP_HEAD_R := 2
const LAMP_TAIL_L := 4
const LAMP_TAIL_R := 8

var car: Vehicle
var health: float = 1000.0
var state: State = State.DAMAGED
## The last hit came from the police (Police.innocent was set): their doing, not the player's.
var blame_police: bool = false
var lamps_broken: int = 0
## Per pane: 0 whole, 1 crazed, 2 gone (parallel to _panes).
var pane_state: PackedFloat32Array = PackedFloat32Array()
## Counters for tests and logs.
var hits_taken: int = 0
var holes_made: int = 0

var _holes: PackedVector4Array = PackedVector4Array()
var _hole_next: int = 0
var _dents: PackedVector4Array = PackedVector4Array()
var _dent_push: PackedVector4Array = PackedVector4Array()
var _cracks: PackedVector4Array = PackedVector4Array()
var _crack_n: PackedVector4Array = PackedVector4Array()
var _crack_next: int = 0
var _scorches: PackedVector4Array = PackedVector4Array()
## The body model: its near mesh (the space every mark is in), and car body space -> mesh space.
var _mesh: MeshInstance3D
var _to_mesh: Transform3D = Transform3D.IDENTITY
var _mesh_scale: float = 1.0
## [mesh, surface, original material] for every override this swapped, so restore() can undo it.
var _swapped: Array = []
var _paint: ShaderMaterial
var _glass: ShaderMaterial
var _lamp_mats: Array[ShaderMaterial] = []
## Panes: [lo (mesh), hi (mesh), outward normal (mesh), kind 0 tempered / 1 windscreen / 2 lamp].
var _panes: Array = []
## CarCabin.for_car(): the panes, the cabin box, the seats.
var _cabin: Dictionary = {}
var _pane_fall: PackedFloat32Array = PackedFloat32Array()
var _dirty: bool = false
var _fuse: float = -1.0
var _burn_t: float = 0.0
var _wreck_t: float = 0.0
var _smoke: CPUParticles3D
## The fire: billowing flame over the engine bay, tongues licking off the bonnet's edges and up
## the windscreen, flames out of the cabin's empty frames and over the roof once it has spread,
## and embers. All four exist only while the car burns.
var _flames: CPUParticles3D
var _licks: CPUParticles3D
var _cabin_fire: CPUParticles3D
var _embers: CPUParticles3D
var _fire_light: OmniLight3D
var _fire_sound: AudioStreamPlayer3D
var _fire_size: float = -1.0
var _flick: float = 0.5
var _staged: bool = false
## While a still is staged, hits leave marks but do not move the health.
var _stage_hold: bool = false
## Car body-space box and features (metres).
var _len: float = 4.5
var _width: float = 1.8
var _ride: float = -0.2
var _top: float = 1.3
var _engine_z: float = -1.5

static var _burning: Array = []
static var _smokers: Array = []
static var _wrecks: Array = []
static var _bursts: int = 0
## Per mesh RID: [TriangleMesh or null, face offsets per surface (PackedInt32Array), slot names].
static var _tri_cache: Dictionary = {}
## Per mesh RID: the panes measured off its glass surface.
static var _char_soot: StandardMaterial3D
static var _char_metal: StandardMaterial3D
static var _char_parts: ShaderMaterial
static var _glass_bit_mat: StandardMaterial3D


func attach(to: Vehicle) -> void:
	car = to
	name = "Damage"
	health = max_health
	var d := car._dims()
	_len = float(d.length)
	_width = float(d.width)
	_ride = float(d.get("ride", car.model_bottom_y))
	_top = car._model_top_y if car._has_model else 0.55 + float(d.chassis_h) + float(d.cabin_h)
	_engine_z = _len * (0.22 if MID_ENGINE.has(car.body_type) else -0.34)
	for m in car._body_meshes:
		if is_instance_valid(m) and not String(m.name).ends_with("_far"):
			_mesh = m
			break
	if _mesh != null and _mesh.is_inside_tree() and car.is_inside_tree():
		_to_mesh = _mesh.global_transform.affine_inverse() * car.global_transform
		_mesh_scale = maxf(_mesh.global_transform.basis.get_scale().x / maxf(car.global_transform.basis.get_scale().x, 1e-4), 1e-4)
	# The panes and the cabin behind them, measured once per body model and shared with the
	# intact glass (CarCabin).
	_cabin = CarCabin.for_car(car)
	_panes = _cabin.panes
	pane_state.resize(_panes.size())
	pane_state.fill(0.0)
	_pane_fall.resize(_panes.size())
	_pane_fall.fill(-1.0)
	set_process(false)


func _exit_tree() -> void:
	_burning.erase(self)
	_smokers.erase(self)


# --- Hits --------------------------------------------------------------------------------------

## One hit (Vehicle.take_hit): `at` a true point on or near the car (scene space), `dir` the way
## the round, the blast or the crash was going, `amount` the weapon's damage (BULLET / PELLET /
## PROP), the blast's falloff at the car (BLAST, `at` is then the blast's centre) or the
## velocity change past the threshold in m/s (CRASH, `at` the contact point).
func hit(kind: int, at: Vector3, dir: Vector3, amount: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	hits_taken += 1
	blame_police = Police.innocent
	if dir.length_squared() < 1e-6:
		dir = Vector3.DOWN
	dir = dir.normalized()
	var dmg := 0.0
	match kind:
		Hit.BULLET, Hit.PELLET:
			dmg = _shot(at, dir, amount, kind == Hit.PELLET)
		Hit.BLAST:
			dmg = _blast(at, amount)
		Hit.CRASH:
			dmg = _crash(at, dir, amount)
		_:
			dmg = amount
	_hurt(dmg, kind == Hit.BLAST or kind == Hit.PROP)
	_mark_dirty()


func _hurt(dmg: float, quick_ok: bool = true) -> void:
	if state == State.WRECK or dmg <= 0.0 or _stage_hold:
		return
	health = maxf(health - dmg, 0.0)
	if health <= max_health * fire_at:
		_ignite(quick_ok and dmg >= quick_fuse_damage)
	elif health <= max_health * smoke_at and state == State.DAMAGED:
		state = State.SMOKING
		_start_smoke()
	if _smoke != null:
		_tint_smoke()


## A round: a hole, a crack, a broken lamp, or a shattered pane, wherever it really lands on the
## model. Returns the damage.
func _shot(at: Vector3, dir: Vector3, amount: float, pellet: bool) -> float:
	var hit_info := _trace(at, dir)
	var body_at: Vector3 = car.global_transform.affine_inverse() * at
	var dmg := amount * bullet_scale
	if _in_engine_bay(body_at):
		dmg *= engine_multiplier
	var slot: String = hit_info.get("slot", "paint")
	var p: Vector3 = hit_info.get("pos", _to_mesh * body_at)
	var n: Vector3 = hit_info.get("normal", Vector3.UP)
	match slot:
		"glass":
			_glass_hit(p, n, pellet)
		"light_front", "light_rear":
			_break_lamp_at(p, slot == "light_front")
		"paint":
			_add_hole(p, (pellet_hole_radius if pellet else hole_radius) / _mesh_scale)
		_:
			pass
	return dmg


## The skin under a round: the first triangle of the body model along the round's path, and its
## slot. Falls back to the collision point (and a guess from its height) where the renderer keeps
## no mesh data (the headless check) or the model has none.
func _trace(at: Vector3, dir: Vector3) -> Dictionary:
	var info := {}
	var tri := _tri_for(_mesh)
	var inv := _mesh.global_transform.affine_inverse() if _mesh != null and _mesh.is_inside_tree() else Transform3D.IDENTITY
	if tri.size() > 0 and tri[0] != null:
		var o: Vector3 = inv * (at - dir * 1.2)
		var ld: Vector3 = (inv.basis * dir).normalized()
		var r: Dictionary = (tri[0] as TriangleMesh).intersect_ray(o, ld)
		if not r.is_empty():
			var pos: Vector3 = r.position
			if pos.distance_to(o) < 1.2 + maxf(_len, 3.0) / _mesh_scale:
				info.pos = pos
				info.normal = (r.normal as Vector3).normalized()
				info.slot = _slot_of_face(tri, int(r.get("face_index", -1)))
				if (info.normal as Vector3).dot(ld) > 0.0:
					info.normal = -(info.normal as Vector3)
				if info.slot == "paint" and car.body_type == Vehicle.BodyType.SPORTS:
					info.slot = _guess_slot(car.global_transform.affine_inverse() * (_mesh.global_transform * pos), (inv.basis.inverse() * info.normal).normalized())
				return info
	# No mesh to trace: the point on the collision box, pushed a hand in along the round.
	var body_at: Vector3 = car.global_transform.affine_inverse() * (at + dir * 0.05)
	var body_n: Vector3 = (car.global_basis.inverse() * -dir).normalized()
	info.pos = _to_mesh * body_at
	info.normal = (_to_mesh.basis * body_n).normalized()
	info.slot = _guess_slot(body_at, body_n)
	return info


## Which slot a body-space point probably is when there is no mesh to ask: glass above the belt
## (not the roof), a lamp at the ends at lamp height, paint elsewhere.
func _guess_slot(body_at: Vector3, body_n: Vector3) -> String:
	var h := (body_at.y - _ride) / maxf(_top - _ride, 0.3)
	if absf(body_at.z) > _len * 0.44 and h > 0.3 and h < 0.55 and absf(body_at.x) > _width * 0.22:
		return "light_front" if body_at.z < 0.0 else "light_rear"
	if h > 0.6 and h < 0.95 and body_n.y < 0.9:
		return "glass"
	return "paint"


func _in_engine_bay(body_at: Vector3) -> bool:
	return absf(body_at.z - _engine_z) < _len * 0.2 and body_at.y < _ride + (_top - _ride) * 0.7


func _add_hole(p: Vector3, r: float) -> void:
	var v := Vector4(p.x, p.y, p.z, r)
	if _holes.size() < HOLE_CAP:
		_holes.append(v)
	else:
		_holes[_hole_next] = v
		_hole_next = (_hole_next + 1) % HOLE_CAP
	holes_made += 1
	_ensure_paint()


## A crash or a blast pushes the metal in: `p` the centre (mesh space), `push` which way and how
## far it moved there (mesh units), `r` the radius. A dent next to an old one deepens that one.
func _add_dent(p: Vector3, push: Vector3, r: float) -> void:
	var cap := max_dent_depth / _mesh_scale
	for i in _dents.size():
		var d := _dents[i]
		if Vector3(d.x, d.y, d.z).distance_to(p) < maxf(d.w, r) * 0.5:
			var old := Vector3(_dent_push[i].x, _dent_push[i].y, _dent_push[i].z)
			var sum := old + push * 0.7
			if sum.length() > cap:
				sum = sum.normalized() * cap
			_dent_push[i] = Vector4(sum.x, sum.y, sum.z, _dent_push[i].w)
			_dents[i].w = maxf(d.w, r)
			_ensure_paint()
			return
	if push.length() > cap:
		push = push.normalized() * cap
	var seed := randf()
	if _dents.size() < DENT_CAP:
		_dents.append(Vector4(p.x, p.y, p.z, r))
		_dent_push.append(Vector4(push.x, push.y, push.z, seed))
	else:
		# Replace the shallowest.
		var k := 0
		for i in _dent_push.size():
			if Vector3(_dent_push[i].x, _dent_push[i].y, _dent_push[i].z).length() < Vector3(_dent_push[k].x, _dent_push[k].y, _dent_push[k].z).length():
				k = i
		_dents[k] = Vector4(p.x, p.y, p.z, r)
		_dent_push[k] = Vector4(push.x, push.y, push.z, seed)
	_ensure_paint()


func _add_scorch(p: Vector3, r: float) -> void:
	var v := Vector4(p.x, p.y, p.z, r)
	if _scorches.size() < SCORCH_CAP:
		_scorches.append(v)
	else:
		_scorches[0] = v
	_ensure_paint()


# --- Glass -------------------------------------------------------------------------------------

func _glass_hit(p: Vector3, n: Vector3, pellet: bool) -> void:
	var i := _pane_at(p, n)
	_ensure_glass()
	if i < 0:
		_add_crack(p, n, 0.16)
		return
	var kind: int = _panes[i][3]
	if kind == 2:
		_set_pane(i, 2.0)
		_break_lamp_at(p, _mesh_forward().dot(p - _mesh_center()) > 0.0)
		return
	if kind == 1:
		# Laminated: webs, never falls out to a round.
		_add_crack(p, n, 0.12 if pellet else 0.2)
		return
	if pane_state[i] < 0.5:
		_set_pane(i, 1.0)
		if randf() < glass_fall_share:
			_pane_fall[i] = randf_range(glass_fall_seconds.x, glass_fall_seconds.y)
			set_process(true)
	elif pane_state[i] < 1.5:
		_set_pane(i, 2.0)


func _add_crack(p: Vector3, n: Vector3, world_r: float) -> void:
	var v := Vector4(p.x, p.y, p.z, world_r / _mesh_scale)
	var nv := Vector4(n.x, n.y, n.z, randf() * 7.0)
	if _cracks.size() < CRACK_CAP:
		_cracks.append(v)
		_crack_n.append(nv)
	else:
		_cracks[_crack_next] = v
		_crack_n[_crack_next] = nv
		_crack_next = (_crack_next + 1) % CRACK_CAP
	_glass_sound(_mesh_to_world(p), -12.0, randf_range(1.1, 1.4))


func _set_pane(i: int, s: float) -> void:
	if i < 0 or i >= pane_state.size() or pane_state[i] >= s:
		return
	var was := pane_state[i]
	pane_state[i] = s
	_ensure_glass()
	var pane: Array = _panes[i]
	var c: Vector3 = ((pane[0] as Vector3) + (pane[1] as Vector3)) * 0.5
	if s >= 2.0 and was < 2.0:
		_glass_burst(c, pane[2], pane[1] - pane[0], 1.0 if int(pane[3]) != 2 else 0.3)
		_glass_sound(_mesh_to_world(c), -2.0, randf_range(0.9, 1.1))
	elif s >= 1.0 and was < 1.0:
		_glass_burst(c, pane[2], pane[1] - pane[0], 0.25)
		_glass_sound(_mesh_to_world(c), -8.0, randf_range(1.0, 1.25))
	_mark_dirty()


## Glass breaking, at most one sound a car every 70 ms (nine pellets are one crash of glass).
func _glass_sound(at: Vector3, db: float, pitch: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _glass_ms < 70:
		return
	_glass_ms = now
	Sfx.play("glass", at, db, pitch)


var _glass_ms: int = -1000


func _pane_at(p: Vector3, n: Vector3) -> int:
	for i in _panes.size():
		var pane: Array = _panes[i]
		var lo: Vector3 = pane[0] - Vector3.ONE * 0.02
		var hi: Vector3 = pane[1] + Vector3.ONE * 0.02
		if p.x >= lo.x and p.y >= lo.y and p.z >= lo.z and p.x <= hi.x and p.y <= hi.y and p.z <= hi.z \
				and absf(n.dot(pane[2])) > 0.3:
			return i
	return -1


## Small cubes of glass thrown out of a pane (and down), lit and glinting.
func _glass_burst(c: Vector3, n: Vector3, size: Vector3, amount: float) -> void:
	if _bursts >= max_glass_bursts or not is_inside_tree():
		return
	var world_c := _mesh_to_world(c)
	var world_n: Vector3 = (_mesh.global_basis * n).normalized() if _mesh != null and _mesh.is_inside_tree() else Vector3.UP
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	# Centimetre cubes: a shadow each is four more draws (the cascades) for nothing you can see.
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = WeaponFX._count(maxi(6, int(70.0 * amount)))
	p.lifetime = 1.3
	p.lifetime_randomness = 0.3
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var ext := size * _mesh_scale * 0.5
	p.emission_box_extents = Vector3(maxf(ext.x, 0.05), maxf(ext.y, 0.05), maxf(ext.z, 0.05))
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var cube := BoxMesh.new()
	cube.size = Vector3(0.014, 0.009, 0.012)
	cube.material = _glass_bits_material()
	p.mesh = cube
	WeaponFX.fx_parent(car).add_child(p)
	# Local +Y along the pane's outward normal, so the cubes are thrown out of the car.
	p.global_transform = Transform3D(WeaponFX._basis_up(world_n), world_c)
	p.custom_aabb = AABB(Vector3.ONE * -8.0, Vector3.ONE * 16.0)
	p.restart()
	p.emitting = true
	_bursts += 1
	var tw := p.create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(func() -> void:
		_bursts = maxi(_bursts - 1, 0)
		p.queue_free())


# --- Lamps -------------------------------------------------------------------------------------

## The lamp nearest a mesh-space point on the front (or rear) breaks.
func _break_lamp_at(p: Vector3, front: bool) -> void:
	var body_p := _to_mesh.affine_inverse() * p
	var left := body_p.x < 0.0
	var bit := (LAMP_HEAD_L if left else LAMP_HEAD_R) if front else (LAMP_TAIL_L if left else LAMP_TAIL_R)
	_break_lamps(bit)


func _break_lamps(bits: int) -> void:
	if bits & ~lamps_broken == 0:
		return
	lamps_broken |= bits
	_ensure_lamps()
	car._set_lamps_broken(lamps_broken)
	# The lens covers over the lamps go with them.
	for i in _panes.size():
		if int(_panes[i][3]) != 2:
			continue
		var c: Vector3 = _to_mesh.affine_inverse() * (((_panes[i][0] as Vector3) + (_panes[i][1] as Vector3)) * 0.5)
		var bit := (LAMP_HEAD_L if c.x < 0.0 else LAMP_HEAD_R) if c.z < 0.0 else (LAMP_TAIL_L if c.x < 0.0 else LAMP_TAIL_R)
		if bits & bit:
			_set_pane(i, 2.0)
	_glass_sound(car.global_position, -10.0, 1.5)
	_mark_dirty()


# --- Blasts and crashes --------------------------------------------------------------------------

## A blast centred at `center` reached the car at `falloff` (0..1).
func _blast(center: Vector3, falloff: float) -> float:
	car.hold_crash_watch(3)
	var inv := car.global_transform.affine_inverse()
	var c_body: Vector3 = inv * center
	var near := _box_point_toward(c_body)
	var push_body := (near - c_body).normalized()
	if push_body.length_squared() < 0.5:
		push_body = Vector3.DOWN
	var p := _to_mesh * near
	var push := (_to_mesh.basis * push_body).normalized() * (blast_dent_depth * clampf(falloff, 0.15, 1.0)) / _mesh_scale
	_add_dent(p, push, (blast_dent_radius * (0.55 + 0.45 * falloff)) / _mesh_scale)
	if falloff > 0.2:
		_add_scorch(p, (0.6 + 1.2 * falloff) / _mesh_scale)
	# Glass and lamps facing the blast.
	var toward := (_to_mesh.basis * -push_body).normalized()
	for i in _panes.size():
		var n: Vector3 = _panes[i][2]
		var facing := n.dot(toward)
		var kind: int = _panes[i][3]
		if falloff > 0.75 or (facing > 0.1 and falloff > 0.3):
			_set_pane(i, 2.0 if kind != 1 or falloff > 0.7 else pane_state[i])
			if kind == 1 and falloff <= 0.7:
				var pc: Vector3 = ((_panes[i][0] as Vector3) + (_panes[i][1] as Vector3)) * 0.5
				_add_crack(pc + Vector3(randf_range(-0.3, 0.3), 0.0, 0.0), n, 0.35)
		elif facing > -0.2 and falloff > 0.15:
			_set_pane(i, 1.0 if kind == 0 else pane_state[i])
	if falloff > 0.35:
		_break_lamps(_lamps_near(near, 1.6 + falloff))
	if _panes.is_empty():
		_ensure_glass()
	return blast_damage * falloff


## A crash: `at` the contact point (scene space), `dir` the velocity change, `over` how far past
## the threshold it went (m/s).
func _crash(at: Vector3, dir: Vector3, over: float) -> float:
	var inv := car.global_transform.affine_inverse()
	# `at` is on what the car hit; the dent goes on the car's side of it.
	var body_at: Vector3 = _box_point_toward(inv * at)
	var push_body: Vector3 = (car.global_basis.inverse() * dir).normalized()
	var p := _to_mesh * body_at
	var r := (crash_dent_radius.x + crash_dent_radius.y * over)
	var depth := minf(crash_dent_depth.x + crash_dent_depth.y * over, max_dent_depth)
	_add_dent(p, (_to_mesh.basis * push_body).normalized() * depth / _mesh_scale, r / _mesh_scale)
	if over > 4.0:
		_break_lamps(_lamps_near(body_at, 0.9 + over * 0.05))
	if over > 6.0:
		var toward := (_to_mesh.basis * -push_body).normalized()
		for i in _panes.size():
			var n: Vector3 = _panes[i][2]
			if n.dot(toward) > 0.4:
				var kind: int = _panes[i][3]
				if kind == 1:
					var pc: Vector3 = ((_panes[i][0] as Vector3) + (_panes[i][1] as Vector3)) * 0.5
					_add_crack(pc, n, 0.3)
				elif over > 9.0:
					_set_pane(i, 2.0)
				else:
					_set_pane(i, 1.0)
	if over > 2.0:
		Sfx.play("crash", at, -4.0 + minf(over, 12.0) * 0.5, randf_range(0.9, 1.1))
	return crash_damage_per_dv * over


## Lamp bits within `reach` metres of a body-space point.
func _lamps_near(body_at: Vector3, reach: float) -> int:
	var bits := 0
	var x := _width * 0.5 - 0.3
	var y := _ride + (_top - _ride) * 0.45
	var spots := [[Vector3(-x, y, -_len * 0.5), LAMP_HEAD_L], [Vector3(x, y, -_len * 0.5), LAMP_HEAD_R],
		[Vector3(-x, y, _len * 0.5), LAMP_TAIL_L], [Vector3(x, y, _len * 0.5), LAMP_TAIL_R]]
	for s: Array in spots:
		if (s[0] as Vector3).distance_to(body_at) < reach:
			bits |= int(s[1])
	return bits


## The point of the car's box (body space) nearest `p`.
func _box_point_toward(p: Vector3) -> Vector3:
	var lo := Vector3(-_width * 0.5, _ride + 0.15, -_len * 0.5)
	var hi := Vector3(_width * 0.5, _top, _len * 0.5)
	var q := p.clamp(lo, hi)
	if q == p:
		# Inside the box: out to the nearest face along the way it came.
		var c := (lo + hi) * 0.5
		var d := (p - c)
		if d.length_squared() < 1e-4:
			d = Vector3.UP
		var t := INF
		for a in 3:
			if absf(d[a]) > 1e-4:
				t = minf(t, ((hi[a] if d[a] > 0.0 else lo[a]) - c[a]) / d[a])
		q = c + d * t
	return q


# --- Fire, the blast, the wreck -----------------------------------------------------------------

func _start_smoke() -> void:
	if _smoke != null or not is_inside_tree():
		return
	_prune(_smokers)
	if _smokers.size() >= max_smoking:
		return
	_smokers.append(self)
	if state == State.BURNING or state == State.WRECK:
		_smoke = _fire_smoke()
		return
	# Wisps out of the bonnet's shut lines: grey at first, darker as it gets worse.
	_smoke = CPUParticles3D.new()
	_smoke.name = "EngineSmoke"
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.amount = WeaponFX._count(26)
	_smoke.lifetime = 3.6
	_smoke.lifetime_randomness = 0.3
	_smoke.local_coords = false
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_smoke.emission_box_extents = Vector3(_width * 0.28, 0.05, _len * 0.08)
	_smoke.direction = Vector3.UP
	_smoke.spread = 18.0
	_smoke.initial_velocity_min = 0.8
	_smoke.initial_velocity_max = 1.8
	_smoke.gravity = Vector3(0.35, 1.3, 0.0)
	_smoke.damping_min = 0.3
	_smoke.damping_max = 0.8
	_smoke.scale_amount_min = 0.5
	_smoke.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.max_value = 4.0
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.4, 1.4))
	curve.add_point(Vector2(1.0, 3.6))
	_smoke.scale_amount_curve = curve
	_smoke.color_ramp = WeaponFX._ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.0)])
	_smoke.angle_min = -180.0
	_smoke.angle_max = 180.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = WeaponFX.smoke_material()
	_smoke.mesh = quad
	_smoke.custom_aabb = AABB(Vector3(-12.0, -2.0, -12.0), Vector3(24.0, 24.0, 24.0))
	_smoke.position = _bonnet()
	if _staged:
		_smoke.preprocess = 3.0
	add_child(_smoke)
	_tint_smoke()
	set_process(true)


## Pale grey wisps at first, darker as the car gets closer to catching. (The fire's own smoke is
## another system, _fire_smoke().)
func _tint_smoke() -> void:
	if _smoke == null or state == State.BURNING or state == State.WRECK:
		return
	var k := clampf(1.0 - (health / max_health - fire_at) / maxf(smoke_at - fire_at, 0.01), 0.0, 1.0)
	var grey := lerpf(0.42, 0.12, k)
	_smoke.color = Color(grey, grey * 0.97, grey * 0.94, lerpf(0.35, 0.8, k))
	_smoke.initial_velocity_max = lerpf(1.6, 2.6, k)


## The fire's smoke: dense and black, thickest right where it leaves the tops of the flames, then
## rising, widening and thinning. Drawn behind the fire (WeaponFX.smoke_material(),
## render_priority -1), so the flames stand in front of it wherever they overlap.
func _fire_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "FireSmoke"
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = WeaponFX._count(64)
	p.lifetime = 5.5
	p.lifetime_randomness = 0.12
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.direction = Vector3.UP
	p.spread = 14.0
	p.initial_velocity_min = 1.3
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0.5, 1.5, 0.0)
	p.damping_min = 0.15
	p.damping_max = 0.45
	p.scale_amount_min = 0.95 * flame_size
	p.scale_amount_max = 1.35 * flame_size
	var curve := Curve.new()
	curve.max_value = 4.0
	curve.add_point(Vector2(0.0, 0.8))
	curve.add_point(Vector2(0.25, 1.5))
	curve.add_point(Vector2(1.0, 3.6))
	p.scale_amount_curve = curve
	# Opaque as it leaves the fire, thinning as it rises and spreads. Its first moments glow the
	# fire's colour (the colour times `color` below, ~0.3): the underside of a car fire's smoke is
	# lit by it, which at night is most of what shows of the column.
	p.color_ramp = WeaponFX._ramp([Color(8.0, 3.4, 1.1, 0.6), Color(1.6, 1.15, 1.0, 0.97), Color(1, 1, 1, 0.92),
		Color(1, 1, 1, 0.62), Color(1, 1, 1, 0.26), Color(1, 1, 1, 0.0)])
	p.color = Color(0.035, 0.032, 0.03, 1.0)
	p.angle_min = -180.0
	p.angle_max = 180.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = WeaponFX.smoke_material()
	p.mesh = quad
	p.custom_aabb = AABB(Vector3(-20.0, -2.0, -20.0), Vector3(40.0, 36.0, 40.0))
	if _staged:
		p.preprocess = 5.0
	add_child(p)
	_place_fire_smoke(p)
	set_process(true)
	return p


## Over the bay while only the engine burns; over the bay and the cabin once the fire has spread.
func _place_fire_smoke(p: CPUParticles3D) -> void:
	var b := _bonnet()
	var top := 0.95 * flame_size
	if _cabin_fire != null:
		p.position = Vector3(0.0, maxf(b.y, _top - 0.2) + top * 0.7, lerpf(b.z, 0.0, 0.5))
		p.emission_box_extents = Vector3(_width * 0.34, 0.2, _len * 0.28)
	else:
		p.position = b + Vector3(0.0, top, 0.0)
		p.emission_box_extents = Vector3(_width * 0.28, 0.15, _len * 0.1)


## Where the smoke and fire come out: on the skin over the engine bay (the bonnet, or the engine
## cover behind a mid-engined cabin), found by tracing down onto the model once.
func _bonnet() -> Vector3:
	if _bonnet_at != Vector3.INF:
		return _bonnet_at
	var y := _ride + (_top - _ride) * (0.62 if not MID_ENGINE.has(car.body_type) else 0.55)
	var tri := _tri_for(_mesh)
	if tri.size() > 0 and tri[0] != null:
		var o := _to_mesh * Vector3(0.0, _top + 1.0, _engine_z)
		var r: Dictionary = (tri[0] as TriangleMesh).intersect_ray(o, (_to_mesh.basis * Vector3.DOWN).normalized())
		if not r.is_empty():
			y = (_to_mesh.affine_inverse() * (r.position as Vector3)).y - 0.06
	_bonnet_at = Vector3(0.0, y, _engine_z)
	return _bonnet_at


var _bonnet_at: Vector3 = Vector3.INF


func _ignite(quick: bool) -> void:
	if state == State.BURNING or state == State.WRECK:
		if quick and state == State.BURNING:
			_fuse = minf(_fuse, randf_range(quick_fuse.x, quick_fuse.y))
		return
	_prune(_burning)
	if _burning.size() >= max_burning:
		# No room for another fire: it smokes, just short of catching.
		health = max_health * fire_at + 1.0
		if state == State.DAMAGED:
			state = State.SMOKING
			_start_smoke()
		return
	_burning.append(self)
	state = State.BURNING
	# Whoever was sitting in it gets out (the glass draws the cabin empty from now on).
	car._update_occupant()
	_fuse = randf_range(quick_fuse.x, quick_fuse.y) if quick else randf_range(burn_seconds.x, burn_seconds.y)
	_burn_t = 0.0
	# The grey wisps give way to the fire's own black smoke.
	_retire_particles(_smoke, 4.0)
	_smoke = null
	_smokers.erase(self)
	_start_smoke()
	_start_fire(1.0)
	if not _staged and is_inside_tree():
		# The whoomph as it catches: one rolling puff of flame out of the bay.
		var at: Vector3 = car.global_transform * (_bonnet() + Vector3(0.0, 0.2, 0.0))
		WeaponFX._puff_layer(WeaponFX.fx_parent(car), at, WeaponFX._count(14), 1.0 * flame_size, 0.75,
				1.2, 3.2, 3.0, _flame_ramp(), false, 70.0, 1.5, Basis(), 0.0, 0.35, 1.0, false,
				_flame_variety(), fire_material())
		Sfx.play("explosion", at, -16.0, 1.7)
	_ensure_paint()
	set_process(true)


## Lets a particle system's last particles live out and then frees it.
func _retire_particles(p: CPUParticles3D, after: float) -> void:
	if p == null or not is_instance_valid(p):
		return
	p.emitting = false
	var tw := p.create_tween()
	tw.tween_interval(after)
	tw.tween_callback(p.queue_free)


## The flames' colour over a puff's life, fed to shaders/fire_puff.gdshader, which multiplies it
## by the billow's density (dense middle hot, thin edge cool) - so a puff's core and edge share
## one green-to-red ratio and differ only in level. Measured through AgX (an unshaded colour chart
## in car_shot's environment): a red-heavy colour (green under ~0.35 of red) turns salmon pink
## once it is brighter than ~1, which is what the old flames read as at night, while an orange
## with green at half of red goes cream-yellow when bright and deep orange when dim - how a real
## flame reads. So the young fire is green / red 0.5 (cores ~1.8, cream-yellow; the body ~0.8,
## orange), and only the dim, dying end drops toward red. Blue stays near a twentieth of red.
static func _flame_ramp() -> Gradient:
	# Gone by the end of its rise: a puff still half opaque as it drifts off reads as a loose blob
	# floating beside the car rather than the top of a flame.
	return WeaponFX._ramp([Color(1.25, 0.64, 0.07, 0.0), Color(1.3, 0.66, 0.07, 0.95),
		Color(1.05, 0.48, 0.05, 0.9), Color(0.65, 0.25, 0.03, 0.6), Color(0.3, 0.09, 0.015, 0.22),
		Color(0.06, 0.04, 0.025, 0.0)])


## Hotter and cooler lumps in one fire.
static func _flame_variety() -> Gradient:
	return WeaponFX._ramp([Color(1.2, 1.12, 1.0), Color(1.0, 1.0, 1.0), Color(0.72, 0.6, 0.5)])


## One flame system: puffs of `quad_size` (tall for tongues, square for the body) on the car
## fire's material, spun only within `angle` degrees of upright.
func _flame_system(sys_name: String, amount: int, quad_size: Vector2, angle: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = sys_name
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = WeaponFX._count(amount)
	p.local_coords = false
	p.direction = Vector3.UP
	p.color_ramp = _flame_ramp()
	p.color_initial_ramp = _flame_variety()
	p.angle_min = -angle
	p.angle_max = angle
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.22, 1.0))
	curve.add_point(Vector2(0.6, 0.8))
	curve.add_point(Vector2(1.0, 0.3))
	p.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = quad_size
	# The root of a tongue at the particle, the rest of it above.
	quad.center_offset = Vector3(0.0, (quad_size.y - quad_size.x) * 0.5, 0.0)
	quad.material = fire_material()
	p.mesh = quad
	# The particles are in world space and a fire's box is a car or two across; set it or the
	# whole fire can vanish (CLAUDE.md, effects).
	p.custom_aabb = AABB(Vector3(-10.0, -3.0, -10.0), Vector3(20.0, 16.0, 20.0))
	if _staged:
		p.preprocess = 1.5
	add_child(p)
	return p


## Points (and the way flames leave them) along lines in body space: [from, to, normal, count].
static func _points_on(lines: Array) -> Array:
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	for l: Array in lines:
		var n: int = l[3]
		for i in n:
			var t := (float(i) + 0.5) / float(n)
			pts.append((l[0] as Vector3).lerp(l[1], t))
			nrm.append((l[2] as Vector3).normalized())
	return [pts, nrm]


## The bonnet's edges and the scuttle under the windscreen, where flames lick out of the bay.
func _lick_lines() -> Array:
	var b := _bonnet()
	var hw := _width * 0.36
	var back := 1.0 if not MID_ENGINE.has(car.body_type) else -1.0
	var front_z := b.z - back * _len * 0.13
	var rear_z := b.z + back * _len * 0.15
	var y := b.y + 0.03
	# No front edge: tongues off the nose drifted out past the bumper and hung in the air in
	# front of the car as loose puffs. The body of the fire covers the front of the bay.
	var mid_z := lerpf(front_z, rear_z, 0.35)
	return [
		# The scuttle: up the windscreen (or up the rear screen of a mid-engined car).
		[Vector3(-hw, y, rear_z), Vector3(hw, y, rear_z), Vector3(0.0, 0.75, back * 0.66), 8],
		# The wing seams, straight up, and the shut lines down the middle.
		[Vector3(-hw, y, mid_z), Vector3(-hw, y, rear_z), Vector3(-0.12, 1.0, 0.0), 3],
		[Vector3(hw, y, mid_z), Vector3(hw, y, rear_z), Vector3(0.12, 1.0, 0.0), 3],
		[Vector3(-hw * 0.3, y, mid_z), Vector3(hw * 0.3, y, rear_z), Vector3(0.0, 1.0, 0.0), 4],
	]


## The cabin's empty frames (the side glass's bottom edges, just outside the car), the foot of
## the windscreen and the roof: where a burning cabin's flames show.
func _cabin_lines() -> Array:
	var lines: Array = []
	var inv := _to_mesh.affine_inverse()
	var fwd := Vector3.FORWARD
	for pane: Array in _panes:
		var kind: int = pane[3]
		if kind == 2:
			continue
		var a: Vector3 = inv * (pane[0] as Vector3)
		var c: Vector3 = inv * (pane[1] as Vector3)
		var lo := a.min(c)
		var hi := a.max(c)
		var n: Vector3 = (inv.basis * (pane[2] as Vector3)).normalized()
		# The stand-in panes (no mesh data, or a single-texture body) span the whole car: keep
		# their lines to where a cabin is.
		var stand_in := hi.z - lo.z > _len * 0.8 or (kind == 1 and hi.z - lo.z > _len * 0.35)
		if kind == 1:
			# The windscreen: from its foot up the glass.
			var up := Vector3(0.0, hi.y - lo.y, -fwd.z * (hi.z - lo.z)).normalized()
			var foot_z := lo.z if fwd.z < 0.0 else hi.z
			if stand_in:
				foot_z = -_len * 0.2
				up = Vector3(0.0, 0.75, 0.66)
			lines.append([Vector3(lo.x + 0.1, lo.y + 0.04, foot_z), Vector3(hi.x - 0.1, lo.y + 0.04, foot_z), up, 5])
		elif absf(n.x) > 0.5:
			var side := signf(n.x)
			var x := (hi.x if side > 0.0 else lo.x) + side * 0.14
			var z0 := lo.z + 0.08
			var z1 := hi.z - 0.08
			if stand_in:
				z0 = -_len * 0.2
				z1 = _len * 0.3
			var cnt := clampi(int((z1 - z0) / 0.22), 2, 6)
			lines.append([Vector3(x, lo.y + 0.08, z0), Vector3(x, lo.y + 0.08, z1), Vector3(side * 0.55, 0.85, 0.0), cnt + 1])
	# Over the roof.
	var zc := lerpf(_bonnet().z, 0.0, 0.8)
	lines.append([Vector3(-_width * 0.2, _top - 0.02, zc - 0.5), Vector3(_width * 0.2, _top - 0.02, zc + 0.5), Vector3(0.0, 1.0, 0.0), 3])
	return lines


## Starts or resizes the fire (`size` 0..1). Particle counts are set once, when a system is made:
## setting a CPUParticles3D's amount restarts it, every particle gone (CLAUDE.md, car damage), so
## a fire dies down by its sizes, speeds and alpha instead.
func _start_fire(size: float) -> void:
	if not is_inside_tree():
		return
	var fs := flame_size
	if _flames == null:
		# The body of the fire: billowing flame rolling up out of the engine bay. Emitted just
		# under the skin, so it comes out of the shut lines rather than floating on the paint.
		_flames = _flame_system("EngineFire", 40, Vector2.ONE, 180.0)
		_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_flames.spread = 22.0
		_flames.lifetime = 0.85
		_flames.lifetime_randomness = 0.4
		_flames.damping_min = 0.8
		_flames.damping_max = 1.5
		# Tongues of flame licking off the bonnet's edges and up the windscreen.
		_licks = _flame_system("FireLicks", 20, Vector2(0.55, 1.2), 12.0)
		_licks.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
		var lp := _points_on(_lick_lines())
		_licks.emission_points = lp[0]
		_licks.emission_normals = lp[1]
		_licks.spread = 12.0
		_licks.lifetime = 0.7
		_licks.lifetime_randomness = 0.35
		_licks.damping_min = 0.4
		_licks.damping_max = 0.9
		# Embers and sparks riding the heat up out of it.
		_embers = CPUParticles3D.new()
		_embers.name = "FireEmbers"
		_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_embers.amount = WeaponFX._count(18)
		_embers.lifetime = 2.2
		_embers.lifetime_randomness = 0.5
		_embers.local_coords = false
		_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_embers.direction = Vector3.UP
		_embers.spread = 32.0
		_embers.initial_velocity_min = 1.5
		_embers.initial_velocity_max = 4.2
		_embers.gravity = Vector3(0.6, 0.9, 0.0)
		_embers.damping_min = 0.2
		_embers.damping_max = 0.7
		_embers.scale_amount_min = 0.03
		_embers.scale_amount_max = 0.07
		# Orange, not white: an HDR start bloomed every ember into a star.
		_embers.color_ramp = WeaponFX._ramp([Color(1.4, 0.76, 0.08, 1.0), Color(1.0, 0.44, 0.04, 1.0),
			Color(0.55, 0.17, 0.02, 0.7), Color(0.2, 0.05, 0.01, 0.0)])
		var eq := QuadMesh.new()
		eq.size = Vector2.ONE
		eq.material = WeaponFX._puff_material(true)
		_embers.mesh = eq
		_embers.custom_aabb = AABB(Vector3(-15.0, -2.0, -15.0), Vector3(30.0, 24.0, 30.0))
		if _staged:
			_embers.preprocess = 2.0
		add_child(_embers)
		if not WeaponFX._web():
			_fire_light = OmniLight3D.new()
			_fire_light.light_color = Color(1.0, 0.47, 0.15)
			_fire_light.omni_range = 11.0
			_fire_light.omni_attenuation = 1.4
			_fire_light.shadow_enabled = false
			_fire_light.distance_fade_enabled = true
			_fire_light.distance_fade_begin = 90.0
			_fire_light.distance_fade_length = 30.0
			add_child(_fire_light)
		_fire_sound = Sfx.loop_player("fire_loop", -3.0)
		_fire_sound.unit_size = 6.0
		add_child(_fire_sound)
		_fire_sound.play()
	_fire_size = size
	var b := _bonnet()
	_flames.position = b + Vector3(0.0, -0.06, 0.0)
	_flames.emission_box_extents = Vector3(_width * 0.3, 0.04, _len * 0.12)
	_flames.initial_velocity_min = 0.35 * fs
	_flames.initial_velocity_max = (0.8 + 0.6 * size) * fs
	_flames.gravity = Vector3(0.25, 1.4 + 0.8 * size, 0.0)
	_flames.scale_amount_min = (0.45 + 0.25 * size) * fs
	_flames.scale_amount_max = (0.75 + 0.5 * size) * fs
	_flames.color = Color(1, 1, 1, clampf(0.45 + 0.55 * size, 0.0, 1.0))
	_licks.initial_velocity_min = (0.35 + 0.3 * size) * fs
	_licks.initial_velocity_max = (0.8 + 0.7 * size) * fs
	_licks.gravity = Vector3(0.1, 1.5, 0.0)
	_licks.scale_amount_min = (0.3 + 0.2 * size) * fs
	_licks.scale_amount_max = (0.5 + 0.35 * size) * fs
	_licks.color = Color(1, 1, 1, clampf(0.35 + 0.65 * size, 0.0, 1.0))
	_embers.position = b + Vector3(0.0, 0.3, 0.0)
	_embers.emission_box_extents = Vector3(_width * 0.3, 0.1, _len * 0.14)
	_embers.color = Color(1, 1, 1, clampf(size * 1.2, 0.2, 1.0))
	if _cabin_fire != null:
		_cabin_fire.initial_velocity_min = (0.3 + 0.3 * size) * fs
		_cabin_fire.initial_velocity_max = (0.8 + 0.7 * size) * fs
		_cabin_fire.scale_amount_min = (0.45 + 0.25 * size) * fs
		_cabin_fire.scale_amount_max = (0.75 + 0.5 * size) * fs
		_cabin_fire.color = Color(1, 1, 1, clampf(0.35 + 0.65 * size, 0.0, 1.0))
		if _glass:
			_glass.set_shader_parameter("cabin_fire", size)
	if _fire_light:
		_fire_light.position = b + Vector3(0.0, 0.9, 0.0) if _cabin_fire == null else Vector3(0.0, _top + 0.4, lerpf(b.z, 0.0, 0.5))
	_flames.emitting = true
	_licks.emitting = true
	_embers.emitting = true


## The fire takes the cabin: the side glass pops, flames roll out of the empty frames, up the
## windscreen and over the roof, and the inside glows through the frames (car_glass_damage's
## cabin_fire).
func _spread_to_cabin(size: float) -> void:
	if _cabin_fire != null or not is_inside_tree():
		return
	for i in _panes.size():
		if int(_panes[i][3]) == 0:
			_set_pane(i, 2.0)
	_ensure_glass()
	_cabin_fire = _flame_system("CabinFire", 36, Vector2(0.6, 1.25), 14.0)
	_cabin_fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
	var cp := _points_on(_cabin_lines())
	_cabin_fire.emission_points = cp[0]
	_cabin_fire.emission_normals = cp[1]
	_cabin_fire.spread = 14.0
	# Short and slow, so the flames stay a sheet over the frames and the roof instead of puffs
	# rising off it.
	_cabin_fire.lifetime = 0.65
	_cabin_fire.lifetime_randomness = 0.35
	_cabin_fire.damping_min = 0.6
	_cabin_fire.damping_max = 1.2
	_cabin_fire.gravity = Vector3(0.15, 1.8, 0.0)
	_cabin_fire.emitting = true
	if _smoke != null:
		_place_fire_smoke(_smoke)
	_start_fire(size)


func _process(delta: float) -> void:
	var busy := false
	for i in _pane_fall.size():
		if _pane_fall[i] >= 0.0:
			_pane_fall[i] -= delta
			if _pane_fall[i] < 0.0:
				_pane_fall[i] = -1.0
				_set_pane(i, 2.0)
			else:
				busy = true
	if state == State.BURNING:
		busy = true
		_burn_t += delta
		_fuse -= delta
		# The fire spreads from the bay as it burns, and cooks the paint round it.
		_set_burn(minf(0.3 * _burn_t / maxf(burn_seconds.x, 1.0), 0.3), 0.5 + _burn_t * 0.18)
		if _cabin_fire == null and _burn_t > spread_share * (_burn_t + maxf(_fuse, 0.0)):
			_spread_to_cabin(1.0)
		if _fuse <= 0.0:
			explode()
	elif state == State.WRECK:
		_wreck_t += delta
		if _flames and _wreck_t > wreck_fire_seconds:
			_stop_fire()
		elif _flames:
			busy = true
			# Dying down in steps (each resize is a few property sets, not a restart).
			var want := snappedf(clampf(1.0 - _wreck_t / wreck_fire_seconds, 0.25, 1.0), 0.25)
			if absf(want - _fire_size) > 0.01:
				_start_fire(want)
		if _smoke and _wreck_t > wreck_fire_seconds + wreck_smoke_seconds:
			_smoke.emitting = false
			_smokers.erase(self)
		elif _smoke:
			busy = true
	if _fire_light:
		# Flicker: a fast random walk plus a quicker shimmer, no two frames alike.
		_flick = lerpf(_flick, randf(), 1.0 - exp(-delta * 14.0))
		var t := Time.get_ticks_msec() * 0.001
		var level := 1.0 if state == State.BURNING else clampf(1.0 - _wreck_t / wreck_fire_seconds, 0.2, 1.0)
		_fire_light.light_energy = fire_light_energy * level * (0.62 + 0.5 * _flick + 0.12 * sin(t * 29.0))
	if not busy:
		set_process(false)


func _stop_fire() -> void:
	if _glass:
		_glass.set_shader_parameter("cabin_fire", 0.0)
	for p in [_flames, _licks, _cabin_fire, _embers]:
		_retire_particles(p, 2.5)
	_flames = null
	_licks = null
	_cabin_fire = null
	_embers = null
	if _fire_light:
		_fire_light.queue_free()
		_fire_light = null
	if _fire_sound:
		_fire_sound.queue_free()
		_fire_sound = null
	_burning.erase(self)


## Goes up: the player (if driving) is thrown out first, the blast is the player's crime unless
## the police lit it (Police.innocent), and the car is tossed and left a wreck.
func explode() -> void:
	if state == State.WRECK or car == null:
		return
	var at: Vector3 = car.global_transform * Vector3(0.0, (_ride + _top) * 0.5, _engine_z * 0.5)
	var rider := car.driver
	if rider != null and rider.has_method("exit_vehicle"):
		rider.exit_vehicle()
	_burning.erase(self)
	become_wreck()
	var was := Police.innocent
	Police.innocent = blame_police
	if car.is_inside_tree():
		Explosion.blast(car, at, blast_radius, blast_launch, blast_player_launch, car)
		if not blame_police and car.is_in_group("police_car"):
			Police.car_hit(car)
	Police.innocent = was
	if car.is_inside_tree() and not car.freeze:
		car.hold_crash_watch(4)
		# Up to the toss speed, not on top of it: a car already flying from a rocket keeps its own arc.
		var toss := maxf(randf_range(toss_speed.x, toss_speed.y) - maxf(car.linear_velocity.y, 0.0), 0.0)
		var side := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.25
		car.apply_central_impulse((Vector3.UP + side) * toss * car.mass)
		car.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)) * car.mass * 1.6)


## Charred: every pane gone, the lamps out, the paint burnt, the tyres burnt down to the rims,
## still burning for a while and smoking after. Freed by PhysicsBudget after `wreck_lifetime`.
func become_wreck() -> void:
	if state == State.WRECK:
		return
	state = State.WRECK
	health = 0.0
	_wreck_t = 0.0
	for i in pane_state.size():
		pane_state[i] = 2.0
	lamps_broken = LAMP_HEAD_L | LAMP_HEAD_R | LAMP_TAIL_L | LAMP_TAIL_R
	_ensure_paint()
	_ensure_glass()
	_ensure_lamps()
	_set_burn(1.0, _len * 1.5)
	_char_parts_of_car()
	car._become_wreck()
	if _smoke != null and _smoke.name == "EngineSmoke":
		_retire_particles(_smoke, 4.0)
		_smoke = null
		_smokers.erase(self)
	_start_smoke()
	_start_fire(1.0)
	_spread_to_cabin(1.0)
	_prune(_wrecks)
	_wrecks.append(car)
	while _wrecks.size() > max_wrecks:
		var old: Node = _wrecks.pop_front()
		if is_instance_valid(old) and not old.is_queued_for_deletion():
			old.queue_free()
	PhysicsBudget.register_debris(car, wreck_lifetime)
	set_process(true)
	_mark_dirty()


func _set_burn(amount: float, reach: float) -> void:
	_ensure_paint()
	if _paint:
		_paint.set_shader_parameter("burnt", amount)
		_paint.set_shader_parameter("burn_origin", _to_mesh * Vector3(0.0, (_ride + _top) * 0.5, _engine_z))
		_paint.set_shader_parameter("burn_reach", reach / _mesh_scale)
	if _glass:
		_glass.set_shader_parameter("burnt", amount)
	for m in _lamp_mats:
		m.set_shader_parameter("burnt", amount)


## Trim, chrome, tyres, lamps and the far twin's parts go to shared charred materials.
func _char_parts_of_car() -> void:
	_charred_materials()
	for m in car._body_meshes:
		if not is_instance_valid(m) or m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			var slot := String(src.resource_name) if src else ""
			var mat: Material = null
			match slot:
				"trim", "tyre":
					mat = _char_soot
				"chrome":
					mat = _char_metal
				"parts":
					mat = _char_parts
			if mat != null:
				_swap(m, si, mat)


static func _charred_materials() -> void:
	if _char_soot != null:
		return
	_char_soot = StandardMaterial3D.new()
	_char_soot.albedo_color = Color(0.035, 0.032, 0.03)
	_char_soot.roughness = 0.95
	_char_metal = StandardMaterial3D.new()
	_char_metal.albedo_color = Color(0.20, 0.13, 0.09)
	_char_metal.roughness = 0.85
	_char_metal.metallic = 0.25
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back;
// A wreck's far twin parts: its vertex colours burnt to soot and rust.
void fragment() {
	float l = dot(COLOR.rgb, vec3(0.3, 0.55, 0.15));
	ALBEDO = mix(vec3(0.03, 0.027, 0.025), vec3(0.2, 0.12, 0.07), smoothstep(0.35, 0.8, l));
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
	SPECULAR = 0.3;
}
"""
	_char_parts = ShaderMaterial.new()
	_char_parts.shader = sh


## The charred wheels: rims, sat on the road where the tyres were.
static func wreck_wheel_material() -> StandardMaterial3D:
	_charred_materials()
	return _char_metal


static var _fire_mat: Material


## What the loading screen draws once so the first car fire, glass burst and smoke do not compile
## mid-game (the damage shaders themselves are .gdshader files it compiles anyway).
static func warm_materials() -> Array:
	return [fire_material(), _glass_bits_material(), WeaponFX.smoke_material(), WeaponFX._puff_material(true)]


## The flames' material, shared by every car fire: the explosion's fireball shader
## (shaders/fire_puff.gdshader - the billow's density is its heat, so dense lumps burn yellow and
## thin edges cool to soot) with the car's own numbers: a sustained fire is not a blast's
## white-hot core, and its soft-particle fade is short because it burns ON the car - at the
## blast's 2.6 m the bonnet under it faded every flame out, and at 0.35 m the flames hugging the
## doors out of the empty frames were a tenth of themselves. The web keeps the plain puff (the
## shader reads the depth buffer), as WeaponFX does.
static func fire_material() -> Material:
	if _fire_mat != null:
		return _fire_mat
	if WeaponFX._web():
		_fire_mat = WeaponFX._puff_material(false)
		return _fire_mat
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/fire_puff.gdshader")
	m.set_shader_parameter("puff_tex", WeaponFX.puff_texture())
	# Held well under the blast's 1.9: over ~2 in the dense middle AgX takes the whole fire to
	# pale beige in daylight and peach at night.
	m.set_shader_parameter("core_heat", 1.4)
	m.set_shader_parameter("edge_cool", 0.42)
	m.set_shader_parameter("soot", 0.55)
	m.set_shader_parameter("soft_distance", 0.15)
	_fire_mat = m
	return _fire_mat


static func _glass_bits_material() -> StandardMaterial3D:
	if _glass_bit_mat == null:
		_glass_bit_mat = StandardMaterial3D.new()
		_glass_bit_mat.albedo_color = Color(0.55, 0.62, 0.62)
		_glass_bit_mat.roughness = 0.08
		_glass_bit_mat.metallic = 0.35
		_glass_bit_mat.metallic_specular = 1.0
	return _glass_bit_mat


# --- Materials ---------------------------------------------------------------------------------

## The paint onto the damage shader, the first time it is needed: a copy of the car's own paint
## material (every uniform carried over), put in its place on every body mesh and shadow twin.
func _ensure_paint() -> void:
	if _paint != null or _mesh == null:
		return
	var old: ShaderMaterial = null
	for si in _mesh.mesh.get_surface_count():
		var m := _mesh.get_surface_override_material(si) as ShaderMaterial
		if m != null and m.shader == Vehicle.PAINT_SHADER:
			old = m
			break
	if old == null:
		return
	_paint = ShaderMaterial.new()
	_paint.shader = PAINT_DAMAGE_SHADER
	for u: Dictionary in Vehicle.PAINT_SHADER.get_shader_uniform_list():
		var v: Variant = old.get_shader_parameter(u.name)
		if v != null:
			_paint.set_shader_parameter(u.name, v)
	_paint.set_shader_parameter("glass_front", (_to_mesh.basis * Vector3.FORWARD).normalized())
	_paint.set_shader_parameter("glass_left", (_to_mesh.basis * Vector3.LEFT).normalized())
	for m in car._body_meshes:
		if not is_instance_valid(m) or m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			if m.get_surface_override_material(si) == old:
				_swap(m, si, _paint)
	_mark_dirty()


func _ensure_glass() -> void:
	if _glass != null or _mesh == null:
		return
	for si in _mesh.mesh.get_surface_count():
		var src := _mesh.mesh.surface_get_material(si) as StandardMaterial3D
		if src == null or String(src.resource_name) != "glass":
			continue
		if _glass == null:
			_glass = ShaderMaterial.new()
			_glass.shader = GLASS_DAMAGE_SHADER
			_glass.set_shader_parameter("glass_albedo", Color(src.albedo_color.r, src.albedo_color.g, src.albedo_color.b))
			_glass.set_shader_parameter("glass_roughness", src.roughness)
			_glass.set_shader_parameter("glass_metallic", src.metallic)
			CarCabin.apply(_glass, _cabin, pane_state)
		_swap(_mesh, si, _glass)
	_mark_dirty()


func _ensure_lamps() -> void:
	if not _lamp_mats.is_empty() or _mesh == null:
		return
	for si in _mesh.mesh.get_surface_count():
		var src := _mesh.mesh.surface_get_material(si) as StandardMaterial3D
		if src == null or not String(src.resource_name).begins_with("light_"):
			continue
		var m := ShaderMaterial.new()
		m.shader = LAMP_DAMAGE_SHADER
		m.set_shader_parameter("lamp_albedo", Color(src.albedo_color.r, src.albedo_color.g, src.albedo_color.b))
		m.set_shader_parameter("lamp_roughness", src.roughness)
		if src.emission_enabled:
			m.set_shader_parameter("lamp_emission", Color(src.emission.r, src.emission.g, src.emission.b))
			m.set_shader_parameter("lamp_emission_energy", src.emission_energy_multiplier)
		m.set_meta("front", String(src.resource_name) == "light_front")
		_lamp_mats.append(m)
		_swap(_mesh, si, m)
	_mark_dirty()


## Puts `mat` on surface `si` of `m` and of its shadow twin, remembering what was there.
func _swap(m: MeshInstance3D, si: int, mat: Material) -> void:
	var old := m.get_surface_override_material(si)
	if old == mat:
		return
	_swapped.append([m, si, old])
	m.set_surface_override_material(si, mat)
	for twin in m.get_children():
		var t := twin as MeshInstance3D
		if t != null and t.mesh == m.mesh and si < t.mesh.get_surface_count():
			t.set_surface_override_material(si, mat)


## Undoes every swap (a cruiser going back into the police pool).
func restore() -> void:
	for i in range(_swapped.size() - 1, -1, -1):
		var e: Array = _swapped[i]
		var m := e[0] as MeshInstance3D
		if not is_instance_valid(m):
			continue
		m.set_surface_override_material(e[1], e[2])
		for twin in m.get_children():
			var t := twin as MeshInstance3D
			if t != null and t.mesh == m.mesh:
				t.set_surface_override_material(e[1], e[2])
	_swapped.clear()
	_stop_fire()
	_smokers.erase(self)
	car._set_lamps_broken(0)


func _mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	_push.call_deferred()


## The marks into the uniforms, once a frame however many hits came in (nine pellets).
func _push() -> void:
	_dirty = false
	if _paint:
		_paint.set_shader_parameter("hole_count", _holes.size())
		if not _holes.is_empty():
			_paint.set_shader_parameter("holes", _holes)
		_paint.set_shader_parameter("dent_count", _dents.size())
		if not _dents.is_empty():
			_paint.set_shader_parameter("dents", _dents)
			_paint.set_shader_parameter("dent_push", _dent_push)
		_paint.set_shader_parameter("scorch_count", _scorches.size())
		if not _scorches.is_empty():
			_paint.set_shader_parameter("scorches", _scorches)
		_paint.set_shader_parameter("smoke_stain", 0.0 if state == State.DAMAGED else (0.5 if state == State.SMOKING else 1.0))
		# A single-texture body has its glass in the paint.
		_paint.set_shader_parameter("crack_count", _cracks.size() if _glass == null else 0)
		if _glass == null and not _cracks.is_empty():
			_paint.set_shader_parameter("cracks", _cracks)
		if _glass == null:
			_paint.set_shader_parameter("glass_gone", _side_gone())
	if _glass:
		_glass.set_shader_parameter("pane_count", _panes.size())
		if not _panes.is_empty():
			var lo := PackedVector4Array()
			var hi := PackedVector4Array()
			var nn := PackedVector4Array()
			for i in _panes.size():
				var p: Array = _panes[i]
				var a: Vector3 = p[0]
				var b: Vector3 = p[1]
				var n: Vector3 = p[2]
				lo.append(Vector4(a.x, a.y, a.z, pane_state[i]))
				hi.append(Vector4(b.x, b.y, b.z, float(p[3])))
				nn.append(Vector4(n.x, n.y, n.z, float(p[4])))
			_glass.set_shader_parameter("pane_lo", lo)
			_glass.set_shader_parameter("pane_hi", hi)
			_glass.set_shader_parameter("pane_n", nn)
		_glass.set_shader_parameter("crack_count", _cracks.size())
		if not _cracks.is_empty():
			_glass.set_shader_parameter("cracks", _cracks)
			_glass.set_shader_parameter("crack_n", _crack_n)
	for m in _lamp_mats:
		var front: bool = m.get_meta("front", true)
		var l := LAMP_HEAD_L if front else LAMP_TAIL_L
		var r := LAMP_HEAD_R if front else LAMP_TAIL_R
		# The lamp on the car's left (body -x) is the mesh's -x side for every glass-slot body.
		m.set_shader_parameter("broken", Vector2(1.0 if lamps_broken & l else 0.0, 1.0 if lamps_broken & r else 0.0))


## For a single-texture body: which sides have lost their glass (front, rear, left, right).
func _side_gone() -> Vector4:
	var g := Vector4.ZERO
	for i in _panes.size():
		if pane_state[i] < 1.5:
			continue
		var n: Vector3 = _to_mesh.basis.inverse() * (_panes[i][2] as Vector3)
		if absf(n.z) > absf(n.x):
			if n.z < 0.0:
				g.x = 1.0
			else:
				g.y = 1.0
		elif n.x < 0.0:
			g.z = 1.0
		else:
			g.w = 1.0
	return g


# --- Panes and the cabin ---------------------------------------------------------------------------

func _mesh_forward() -> Vector3:
	return (_to_mesh.basis * Vector3.FORWARD).normalized()


func _mesh_center() -> Vector3:
	return _to_mesh * Vector3(0.0, (_ride + _top) * 0.5, 0.0)


func _mesh_to_world(p: Vector3) -> Vector3:
	if _mesh != null and _mesh.is_inside_tree():
		return _mesh.global_transform * p
	return car.global_position


# --- Tracing the model ---------------------------------------------------------------------------

## The body model's triangles for tracing rounds, built once per mesh: [TriangleMesh, the first
## face of each surface, each surface's slot]. Empty where the renderer keeps no mesh data.
static func _tri_for(m: MeshInstance3D) -> Array:
	if m == null or m.mesh == null:
		return []
	var key := m.mesh.get_rid()
	if _tri_cache.has(key):
		return _tri_cache[key]
	var out := []
	var tm := m.mesh.generate_triangle_mesh()
	if tm != null and not tm.get_faces().is_empty():
		var offsets := PackedInt32Array()
		var slots := PackedStringArray()
		var run := 0
		var am := m.mesh as ArrayMesh
		for si in m.mesh.get_surface_count():
			offsets.append(run)
			var src := m.mesh.surface_get_material(si)
			var slot := String(src.resource_name) if src else "paint"
			if slot.begins_with("paint") or m.mesh.get_surface_count() == 1:
				slot = "paint"
			slots.append(slot)
			var n := 0
			if am != null:
				var il := am.surface_get_array_index_len(si)
				n = (il if il > 0 else am.surface_get_array_len(si)) / 3
			run += n
		out = [tm, offsets, slots]
	_tri_cache[key] = out
	return out


static func _slot_of_face(tri: Array, face: int) -> String:
	var offsets: PackedInt32Array = tri[1]
	var slots: PackedStringArray = tri[2]
	if face < 0 or offsets.is_empty():
		return "paint"
	var s := 0
	for i in offsets.size():
		if face >= offsets[i]:
			s = i
	return slots[s]


static func _prune(list: Array) -> void:
	for i in range(list.size() - 1, -1, -1):
		if not is_instance_valid(list[i]) or (list[i] as Node).is_queued_for_deletion():
			list.remove_at(i)


## Counts for tests: cars burning, smoking and wrecks kept.
static func counts() -> Dictionary:
	_prune(_burning)
	_prune(_smokers)
	_prune(_wrecks)
	return {"burning": _burning.size(), "smoking": _smokers.size(), "wrecks": _wrecks.size()}


# --- Stills -------------------------------------------------------------------------------------

## Stages a look for a screenshot (tools/glshot/car_shot.gd DAMAGE=...): real rounds and blasts
## through the same paths as the game, aimed at fixed spots on the car. `what` is any of holes,
## glass, dents, smoke, burning, wreck (comma separated).
func stage(what: String) -> void:
	_staged = true
	_stage_hold = true
	var parts := what.split(",")
	var xf := car.global_transform
	var hw := _width * 0.5
	var mid := _ride + (_top - _ride) * 0.42
	var win := _ride + (_top - _ride) * 0.78
	if parts.has("holes"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		# A burst across the driver's door and front wing, a few on the bonnet.
		for i in 16:
			var t := Vector3(hw + 0.5, mid + rng.randf_range(-0.18, 0.16), rng.randf_range(-1.4, 0.4))
			var aim := Vector3(-1.0, rng.randf_range(-0.12, 0.05), rng.randf_range(-0.1, 0.1)).normalized()
			car.take_hit(-1, 10.0, xf.basis * aim, xf * t, Vehicle.HIT_BULLET)
		for i in 6:
			var t := Vector3(rng.randf_range(-0.5, 0.5), _top + 0.5, -_len * 0.33 + rng.randf_range(-0.3, 0.3))
			car.take_hit(-1, 10.0, xf.basis * Vector3(0.1, -1.0, 0.25).normalized(), xf * t, Vehicle.HIT_BULLET)
		for i in 9:
			var t := Vector3(hw + 0.5, mid + rng.randf_range(-0.08, 0.08), 0.9 + rng.randf_range(-0.15, 0.15))
			car.take_hit(-1, 12.0, xf.basis * Vector3(-1.0, 0.0, 0.0), xf * t, Vehicle.HIT_PELLET)
	if parts.has("glass"):
		# The front door glass gone, the rear one crazed, three webs in the windscreen, a broken
		# headlamp.
		_hit_glass(Vector3(hw + 0.6, win, -0.45), Vector3(-1.0, 0.0, 0.0), 2)
		_hit_glass(Vector3(hw + 0.6, win, 0.6), Vector3(-1.0, 0.0, 0.0), 1)
		for x in [-0.32, 0.12, 0.38]:
			var from := Vector3(x, _top + 1.2, -_len * 0.5 - 1.2)
			var to := Vector3(x * 0.8, _top - (_top - _ride) * 0.22, -_len * 0.12)
			car.take_hit(-1, 10.0, xf.basis * (to - from).normalized(), xf * from, Vehicle.HIT_BULLET)
		for i in pane_state.size():
			_pane_fall[i] = -1.0
		_break_lamps(LAMP_HEAD_R)
	if parts.has("dents"):
		car.take_hit(-1, 9.0, xf.basis * Vector3(0.35, 0.0, 1.0).normalized(), xf * Vector3(hw - 0.2, mid, -_len * 0.5), Vehicle.HIT_CRASH)
		car.take_hit(-1, 7.0, xf.basis * Vector3(-1.0, 0.0, 0.0), xf * Vector3(hw, mid - 0.05, 0.55), Vehicle.HIT_CRASH)
	_stage_hold = false
	if parts.has("smoke"):
		_hurt(health - max_health * smoke_at + 50.0)
	if parts.has("burning") or parts.has("blaze"):
		_hurt(max_health)
		_fuse = 1e9
		_burn_t = 4.0
		_set_burn(0.3, 1.4)
		if parts.has("blaze"):
			_spread_to_cabin(1.0)
	if parts.has("wreck"):
		become_wreck()
		_wreck_t = 3.0
	_push()


func _hit_glass(body_from: Vector3, body_dir: Vector3, times: int) -> void:
	var xf := car.global_transform
	for i in times:
		car.take_hit(-1, 10.0, xf.basis * body_dir, xf * body_from, Vehicle.HIT_BULLET)
