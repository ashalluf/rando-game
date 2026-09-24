class_name PoliceOfficer
extends Pedestrian
## A police officer on foot (Police deploys them from a stopped PoliceCar). A Pedestrian, so it
## is shot, knocked, blown apart and ragdolled exactly like anyone on the street, but it walks
## its own brain instead of the pavement ring:
##
##   COVER    the player is near the cruiser: stand at the far corner of it and shoot past it.
##   ENGAGE   no car to hide behind: close to `engage_range`, then hold and shoot.
##   SEARCH   the trail is cold: walk to spots in the search area round the last sighting.
##   REBOARD  called back (the player got away, or the stars are gone): back into the car.
##
## The body is an Avatar (the hero's animated rig class), so the hand IK that holds the hero's
## guns holds the officer's PoliceGun too: carried low while moving, raised to the shoulder to
## aim. The uniform is the character shader recoloured navy (uniform_material), with a peaked
## cap on the head bone. Shots go through the same WeaponFX tracer, muzzle flash and impact as
## the player's, and never count as the player's crimes (Police.innocent).
## Officers are not in the "pedestrian" group - an alarm does not send them running and they
## do not count against the crowd cap - but they are in "police", which LockOn aims at.

enum Task { COVER, ENGAGE, SEARCH, REBOARD }

@export_group("Officer")
## Running pace to cover or after the player, and walking pace while searching (m/s).
@export var officer_run_speed: float = 5.4
@export var officer_walk_speed: float = 2.0
## Rifle rounds that put an officer down (a car, a blast or a heavier hit always does it).
@export var hits_to_down: int = 2
## A knock under this impulse counts as one round rather than as being bowled over.
@export var light_hit_impulse: float = 17.0
## Shots per second inside a burst, rounds per burst, and the pause between bursts (s).
@export var shot_rate: float = 3.2
@export var burst: int = 3
@export var burst_pause: Vector2 = Vector2(0.7, 1.5)
## Damage per round that hits the player.
@export var bullet_damage: float = 8.0
## Chance a round hits a standing player 12 m away; it falls off with range and with how fast
## the player is moving, and rises with the stars (Police.accuracy_scale()).
@export var accuracy: float = 0.5
## Furthest an officer shoots from, and how close it closes in without cover (m).
@export var fire_range: float = 60.0
@export var engage_range: float = 20.0
## Cover: how far behind the cruiser and along it an officer stands (m), and how near the
## player the cruiser must be to be worth hiding behind.
@export var cover_back: float = 1.3
@export var cover_along: float = 3.4
@export var cover_reach: float = 32.0
@export var tracer_color: Color = Color(1.0, 0.82, 0.45)

## Navy uniform and the heavy unit's black one, as the character shader's garment colours.
const UNIFORM_TOP := Color(0.11, 0.14, 0.26)
const UNIFORM_TROUSERS := Color(0.07, 0.085, 0.16)
const HEAVY_TOP := Color(0.07, 0.075, 0.085)
const HEAVY_TROUSERS := Color(0.05, 0.055, 0.065)
const CAP_COLOR := Color(0.07, 0.08, 0.14)

var police: Police
var car: PoliceCar
## Which of the car's crew this is (spreads them round the cover).
var seat: int = 0
var heavy: bool = false
var task: Task = Task.ENGAGE
## Seconds since this officer was on screen (Police recalls ones nobody sees).
var unseen_time: float = 0.0

var _avatar: Avatar
var _mount: Node3D
var _gun: PoliceGun
var _hits_left: int = 2
var _dest: Vector3 = Vector3.INF
var _search_point: Vector3 = Vector3.INF
var _think_t: float = 0.0
var _fire_t: float = 0.0
var _burst_left: int = 0
var _sight: bool = false
var _sight_t: float = 0.0
var _aim_pitch: float = 0.0
var _flinch: float = 0.0
## The line from the gun to the player is open (no wall, no car in the way).
var _clear: bool = false
## Seconds the officer has wanted to shoot with the line blocked, and been trying to move and
## not moving; and seconds left of a step it took to get a clear shot (its own orders wait).
var _blocked_t: float = 0.0
var _stuck_t: float = 0.0
var _hold_t: float = 0.0
var _peek_side: float = 1.0
static var _uniform_mats: Dictionary = {}
static var _cap_mesh: Mesh
## Rounds fired and rounds that reached the player, over the whole session (the smoke test and
## tuning read them).
static var rounds_fired: int = 0
static var rounds_hit: int = 0


func setup_officer(p: Police, c: PoliceCar, index: int, is_heavy: bool, seed_value: int) -> void:
	police = p
	car = c
	seat = index
	heavy = is_heavy
	# A ring of nothing: the pavement walk is never used, but Pedestrian seeds its streams here.
	setup(Rect2(-1.0, -1.0, 2.0, 2.0), 1.0, seed_value)
	_hits_left = hits_to_down + (1 if heavy else 0)
	if heavy:
		shot_rate = 6.0
		burst = 5
		bullet_damage = 7.0
		accuracy = 0.55


func _ready() -> void:
	super._ready()
	remove_from_group("pedestrian")
	add_to_group("police")
	# World and props: an officer walks round a car rather than through it.
	collision_mask = 1 | 4
	_think_t = randf() * 0.3


## The body: an Avatar in the uniform, a cap and the gun in both hands.
func _add_model() -> bool:
	var path := _pick_model()
	if path == "":
		return false
	var body := Avatar.new()
	body.name = "Officer"
	_visual.add_child(body)
	if not body.load_model(path, 1):
		body.queue_free()
		return false
	_avatar = body
	_model_path = path
	_look = 1
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		_meshes.append(mi)
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh else null
		if src and src.albedo_texture:
			mi.material_override = uniform_material(src.albedo_texture, heavy)
	# Pose the rig in its idle before hanging the cap off the head bone (see Pedestrian._add_model:
	# the clips hold the bones off the bind pose, and a cap lined up on the bind pose rides tilted).
	var anim := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		anim.seek(0.0, true)
	_add_cap(body)
	# Everyone is not the same height.
	_visual.scale = Vector3.ONE * _style.randf_range(0.96, 1.05)
	_mount = Node3D.new()
	_mount.name = "GunMount"
	_visual.add_child(_mount)
	_gun = PoliceGun.new()
	_gun.carbine = heavy
	_mount.add_child(_gun)
	body.setup_gun_hands(_mount, _visual, self)
	return true


## The rigs that take the uniform cleanly (judged in a standoff still): not the hero's own (d),
## not e (its sleeves are painted skin from the elbow down), not i (it has a cap of its own) and
## not k (its yellow blazer stays yellow under the recolour, and read as a hi-vis vest).
const OFFICER_MODELS := [
	"res://assets/models/pedestrian_f_anim.glb",
	"res://assets/models/pedestrian_g_anim.glb",
	"res://assets/models/pedestrian_h_anim.glb",
	"res://assets/models/pedestrian_j_anim.glb",
	"res://assets/models/pedestrian_l_anim.glb",
]


## One of OFFICER_MODELS, seeded; any crowd rig but the hero's if none of those exist.
func _pick_model() -> String:
	var hero := "res://assets/models/pedestrian_d_anim.glb"
	var available: Array[String] = []
	for p in OFFICER_MODELS:
		if ResourceLoader.exists(p):
			available.append(p)
	if available.is_empty():
		for p in MODELS:
			if p != hero and ResourceLoader.exists(p):
				available.append(p)
	if available.is_empty():
		return ""
	return available[_style.randi() % available.size()]


## The uniform: the model's own face, skin and hair, with top and trousers repainted navy (black
## for the tactical unit) through the character shader's garment split. Cached per texture.
static func uniform_material(albedo: Texture2D, is_heavy: bool) -> ShaderMaterial:
	var key := "%d_%d" % [albedo.get_instance_id(), int(is_heavy)]
	if _uniform_mats.has(key):
		return _uniform_mats[key]
	var base := character_material(albedo, 1)
	if base == null:
		return null
	var mat := base.duplicate() as ShaderMaterial
	var top: Color = HEAVY_TOP if is_heavy else UNIFORM_TOP
	var low: Color = HEAVY_TROUSERS if is_heavy else UNIFORM_TROUSERS
	mat.set_shader_parameter("cloth_hue", top.h)
	mat.set_shader_parameter("cloth_sat", top.s)
	mat.set_shader_parameter("cloth_value", top.v)
	mat.set_shader_parameter("cloth_strength", 0.96)
	mat.set_shader_parameter("pants_hue", low.h)
	mat.set_shader_parameter("pants_sat", low.s)
	mat.set_shader_parameter("pants_value", low.v)
	mat.set_shader_parameter("pants_strength", 0.96)
	mat.set_shader_parameter("hair_strength", 0.0)
	mat.set_shader_parameter("skin_tint", Color(1, 1, 1))
	mat.set_shader_parameter("cloth_roughness", 0.78)
	# Pressed cloth: less of the source garment's creases and patches.
	mat.set_shader_parameter("cloth_shade_keep", 0.65)
	_uniform_mats[key] = mat
	return mat


## A peaked cap on the head bone, built the way Pedestrian's caps are (one shared mesh, the
## part colours in the vertex colour). The tactical unit goes without (no helmet is built yet).
func _add_cap(inst: Node3D) -> void:
	if heavy:
		return
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var idx := skel.find_bone("Head")
	if idx < 0:
		return
	var unit := 1.0
	var node: Node3D = skel
	while node != null and node != inst:
		unit *= node.transform.basis.get_scale().y
		node = node.get_parent() as Node3D
	unit = 1.0 / maxf(unit, 0.0001)
	var att := BoneAttachment3D.new()
	skel.add_child(att)
	att.bone_name = "Head"
	var mi := MeshInstance3D.new()
	mi.name = "Cap"
	mi.mesh = cap_mesh()
	mi.material_override = PropFactory.material(Color(1, 1, 1), 0.6)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = accessory_distance
	var pose := skel.get_bone_global_pose(idx)
	var at: Vector3 = pose.origin + Vector3(0.0, 0.0, -0.012) * unit
	mi.transform = pose.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * unit), at)
	att.add_child(mi)


## Band, a crown that flares out to a flat top, a black peak and a small gold badge: the
## silhouette that reads as a police cap from across a street.
static func cap_mesh() -> Mesh:
	if _cap_mesh != null:
		return _cap_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	_acc_tube(st, 0.092, 0.140, 0.108, 0.124, CAP_COLOR, 20)
	_flare(st, 0.140, 0.182, Vector2(0.108, 0.124), Vector2(0.132, 0.150), CAP_COLOR.lightened(0.06), 20)
	_acc_dome(st, Vector3(0.0, 0.182, 0.0), Vector3(0.132, 0.012, 0.150), CAP_COLOR.lightened(0.06), 20, 2)
	st.set_smooth_group(0xFFFFFFFF)
	_acc_brim(st, 0.098, 0.182, 0.100, 0.028, 0.010, Color(0.02, 0.02, 0.025), 12)
	_acc_box(st, Vector3(0.0, 0.150, 0.146), Vector3(0.034, 0.036, 0.010), Color(0.80, 0.62, 0.22))
	st.generate_normals()
	_cap_mesh = st.commit()
	return _cap_mesh


## An open band that widens from radii `r0` at `y0` to `r1` at `y1`.
static func _flare(st: SurfaceTool, y0: float, y1: float, r0: Vector2, r1: Vector2, colour: Color, seg: int) -> void:
	for s in seg:
		var u0 := TAU * float(s) / float(seg)
		var u1 := TAU * float(s + 1) / float(seg)
		var a0 := Vector3(sin(u0) * r0.x, y0, cos(u0) * r0.y)
		var b0 := Vector3(sin(u1) * r0.x, y0, cos(u1) * r0.y)
		var a1 := Vector3(sin(u0) * r1.x, y1, cos(u0) * r1.y)
		var b1 := Vector3(sin(u1) * r1.x, y1, cos(u1) * r1.y)
		_acc_quad(st, a0, a1, b1, b0, colour)


## Not frightened by gunfire: an officer is what the gunfire is about.
func _scare(_at: Vector3) -> void:
	pass


## Always simulated with a collision body (there are at most a dozen), with the crowd's draw
## tiers for shadows and mesh LODs.
func _update_lod() -> void:
	super._update_lod()
	_lod_stride = 1
	_kinematic = false
	if not _down:
		collision_mask = 1 | 4
		if _hit_shape:
			_hit_shape.disabled = false


func _physics_process(delta: float) -> void:
	if _down or police == null:
		return
	_lod_timer += delta
	if _lod_timer >= 0.5:
		_lod_timer = 0.0
		_update_lod()
	_think_t -= delta
	_hold_t = maxf(_hold_t - delta, 0.0)
	if _think_t <= 0.0:
		_think_t = 0.4 + randf() * 0.2
		_think()
	var target := police.player_aim_point()
	var known := police.player_known()
	# Where to go.
	var speed := 0.0
	var move := Vector3.ZERO
	if _dest != Vector3.INF:
		move = _dest - global_position
		move.y = 0.0
		if move.length() > 0.7:
			speed = officer_walk_speed if task == Task.SEARCH and not known else officer_run_speed
			move = move.normalized()
		else:
			move = Vector3.ZERO
	if _flinch > 0.0:
		_flinch -= delta
		speed *= 0.3
	velocity.x = move.x * speed
	velocity.z = move.z * speed
	if not is_on_floor():
		velocity.y -= 30.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	# Wanting to move and not moving (pressed against a car, a wall, a kerb it cannot take):
	# stop trying and hold here for a moment.
	var moved := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if speed > 0.0 and moved < 0.4:
		_stuck_t += delta
		if _stuck_t > 0.8:
			_stuck_t = 0.0
			_dest = Vector3.INF
			_hold_t = 1.5
	else:
		_stuck_t = 0.0
	# Line of sight to the player, and a clear line of fire from the gun, a few times a second.
	_sight_t -= delta
	if _sight_t <= 0.0:
		_sight_t = 0.3
		_sight = known and police.can_shoot() and _can_see(target)
		_clear = _sight and _line_of_fire(target)
	var to := target - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var dist := flat.length()
	var aiming := _sight and dist < fire_range and task != Task.REBOARD
	# A car or a corner in the way: step out sideways to get a shot, alternating sides.
	if aiming and not _clear and moved < 0.5:
		_blocked_t += delta
		if _blocked_t > 0.6:
			_blocked_t = 0.0
			_peek_side = -_peek_side
			var side := flat.cross(Vector3.UP).normalized() * _peek_side
			_dest = global_position + side * 2.2 - flat.normalized() * 0.6
			_hold_t = 1.4
	else:
		_blocked_t = 0.0
	var face := flat if aiming else Vector3(velocity.x, 0.0, velocity.z)
	if face.length() > 0.3:
		var yaw := atan2(-face.x, -face.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, yaw, 1.0 - exp(-(10.0 if aiming else 8.0) * delta))
	if aiming:
		var muzzle_y := global_position.y + 1.45
		_aim_pitch = lerpf(_aim_pitch, atan2(target.y - muzzle_y, maxf(dist, 1.0)), 1.0 - exp(-8.0 * delta))
	else:
		_aim_pitch = lerpf(_aim_pitch, 0.0, 1.0 - exp(-6.0 * delta))
	if _mount:
		_mount.rotation.x = _aim_pitch
	# Shooting: in bursts, once facing the player, with the line open, never at a run.
	if aiming and _clear and moved < officer_run_speed * 0.5:
		var facing := -_visual.global_basis.z
		facing.y = 0.0
		var lined_up := facing.normalized().dot(flat / maxf(dist, 0.01)) > 0.93
		_fire_t -= delta
		if _fire_t <= 0.0 and lined_up:
			if _burst_left <= 0:
				_burst_left = burst
			_shoot(target, dist)
			_burst_left -= 1
			_fire_t = 1.0 / shot_rate if _burst_left > 0 else randf_range(burst_pause.x, burst_pause.y)
	else:
		_fire_t = maxf(_fire_t, 0.25)
	if _avatar:
		_avatar.drive(delta, Vector2(velocity.x, velocity.z).length(), is_on_floor(), velocity.y, false)
		_avatar.hold_gun(_gun, aiming, delta)


func _can_see(target: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var from := global_position + Vector3.UP * 1.6
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, target, 1))
	return hit.is_empty() or (hit.position as Vector3).distance_to(target) < 1.2


## The gun has an open line to the player: nothing of the world and no car (their own cruiser
## included) between the muzzle and them, except the car the player is sitting in. Firing into
## the side of the cruiser you are hiding behind is how the first version spent all its rounds.
func _line_of_fire(target: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var from := _gun.muzzle.global_position if _gun and is_instance_valid(_gun.muzzle) else global_position + Vector3.UP * 1.45
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, target, 1 | 4, police.officer_rids()))
	if hit.is_empty():
		return true
	return hit.collider == police.player_vehicle() or (hit.position as Vector3).distance_to(target) < 1.0


## What to do and where to stand, a couple of times a second.
func _think() -> void:
	var car_ok := is_instance_valid(car) and car.driver == null and not car.is_queued_for_deletion()
	if car_ok and (car.recall_crew or police.stars <= 0):
		task = Task.REBOARD
		var door := car.global_position + car.global_basis.x * (1.6 if seat % 2 == 0 else -1.6)
		door.y = global_position.y
		_dest = door
		if global_position.distance_to(door) < 2.4:
			police.board(self, car)
		return
	if police.stars <= 0:
		_dest = Vector3.INF
		return
	var known := police.player_known()
	var pp := police.player_aim_point()
	pp.y = global_position.y
	if _hold_t > 0.0:
		return
	if not known and police.seen_time > 3.0:
		task = Task.SEARCH
		if _search_point == Vector3.INF or global_position.distance_to(_search_point) < 3.0:
			var g := police.random_search_point()
			var local := WorldState.to_local(Vector3(g.x, 0.0, g.y))
			_search_point = Vector3(local.x, global_position.y, local.z)
		_dest = _search_point
		return
	_search_point = Vector3.INF
	var car_d := car.global_position.distance_to(pp) if car_ok else INF
	if car_ok and car.mode == PoliceCar.Mode.PARKED and car_d > 9.0 and car_d < cover_reach and car.global_basis.y.y > 0.6:
		task = Task.COVER
		var away := car.global_position - pp
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.BACK
		# Along the car's length, one officer at each end, so they shoot past it, not over it.
		var along := -car.global_basis.z
		along.y = 0.0
		along = along.normalized() if along.length() > 0.1 else Vector3.FORWARD
		var end := 1.0 if seat % 2 == 0 else -1.0
		var spot := car.global_position + away * cover_back + along * (cover_along * end) + along * (0.9 * float(seat >> 1) * end)
		spot.y = global_position.y
		_dest = spot
		return
	task = Task.ENGAGE
	var d := global_position.distance_to(pp)
	if d > engage_range:
		_dest = pp + (global_position - pp).normalized() * engage_range * 0.85
	elif d < 6.0:
		_dest = global_position + (global_position - pp).normalized() * 3.0
	else:
		_dest = Vector3.INF


## One round at the player: a hit with a chance that falls off with range and with how fast
## they are moving, otherwise a near miss past them. Whatever the round actually meets is hit.
func _shoot(target: Vector3, dist: float) -> void:
	var from := _gun.muzzle.global_position if _gun and is_instance_valid(_gun.muzzle) else global_position + Vector3.UP * 1.45
	var chance := accuracy * clampf(12.0 / maxf(dist, 1.0), 0.2, 1.3) * police.accuracy_scale()
	chance *= clampf(1.0 - police.player_velocity().length() / 45.0, 0.35, 1.0)
	var aim := target
	if randf() > chance:
		var off := Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 0.9), randf_range(-1.0, 1.0)).normalized()
		aim += off * randf_range(0.9, 2.4)
	var dir := (aim - from).normalized()
	var to := from + dir * 170.0
	rounds_fired += 1
	var space := get_world_3d().direct_space_state
	var end := to
	if space:
		var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4 | 8, police.officer_rids())
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			end = hit.position
			var c: Object = hit.collider
			var mine := police.player_vehicle()
			if c is Player:
				rounds_hit += 1
				police.hit_player(bullet_damage, from)
			elif c is RigidBody3D:
				if c == mine:
					rounds_hit += 1
					# The car soaks most of it (PlayerHealth.in_car_factor does the rest).
					police.hit_player(bullet_damage, from)
				(c as RigidBody3D).apply_impulse(dir * 8.0, (hit.position as Vector3) - (c as RigidBody3D).global_position)
			elif c.has_method("take_hit"):
				c.take_hit(hit.get("shape", -1), 8.0, dir)
			elif c.has_method("knock"):
				Police.innocent = true
				c.knock(dir * 12.0 + Vector3.UP * 4.0)
				Police.innocent = false
			if not (c is Player):
				WeaponFX.impact(self, hit.position, Color(1.0, 0.85, 0.5), hit.normal, c)
	WeaponFX.tracer(self, from, end, tracer_color)
	WeaponFX.flash(self, from)
	Sfx.play("shot", from, -7.0, 1.0 if heavy else 1.22)
	if _gun:
		_gun._kick = _gun.kick_distance
	# Bystanders run from police gunfire too; it is not the player's crime.
	Pedestrian.alarm(get_tree(), global_position, 35.0, 1, false, "")


## A round only staggers an officer (they take `hits_to_down`); a car, a blast or anything
## heavier puts them down, into the same ragdoll as anyone else, still in uniform.
func knock(impulse: Vector3, gibs: int = 0) -> void:
	if _down:
		return
	if gibs == 0 and impulse.length() < light_hit_impulse and _hits_left > 1:
		_hits_left -= 1
		_flinch = 0.35
		_think_t = 0.0
		Sfx.play("yelp", global_position + Vector3.UP * 1.5, -6.0, randf_range(0.9, 1.1))
		# Hitting an officer at all is a crime in itself, even if it is not a kill.
		if police:
			police.knocked_down("cop_hit", global_position)
		return
	var parent := get_parent()
	var before := parent.get_child_count() if parent else 0
	if police:
		police.officer_down(self)
	super.knock(impulse, gibs)
	if parent == null:
		return
	for i in range(before, parent.get_child_count()):
		var doll := parent.get_child(i) as Ragdoll
		if doll:
			_dress_ragdoll(doll)


## The ragdoll is built from the plain rig (Ragdoll.build_from_rig); put the uniform and the cap
## back on it.
func _dress_ragdoll(doll: Ragdoll) -> void:
	var rig := doll._rig
	if rig == null:
		return
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh else null
		if src and src.albedo_texture and mi.skin:
			mi.material_override = uniform_material(src.albedo_texture, heavy)
	_add_cap(rig)
