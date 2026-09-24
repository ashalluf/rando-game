class_name Shotgun
extends Weapon
## Pump-action 12 gauge: a cone of pellets that throws whatever it hits, then a pump stroke - the
## forend slides back, a spent shell spins out of the port, and it slides home for the next shot.

@export_group("Shotgun")
## Pellets per shot.
@export var pellets: int = 9
## Half-angle of the pellet cone (degrees).
@export var spread_deg: float = 4.5
## Impulse each pellet gives a physics prop.
@export var pellet_force: float = 9.0
## Damage per pellet to breakable street props.
@export var pellet_damage: float = 12.0
## Pellet reach (metres).
@export var pellet_range: float = 120.0
## How hard a person is thrown: `knock_base` plus this much per pellet that hit them (m/s).
@export var knock_per_pellet: float = 5.0
@export var knock_base: float = 12.0
## How much each pellet in a person bleeds (WeaponFX.blood's strength; a rifle round is 1). A
## person's pellets are summed into one wound, so a close blast of nine is a much heavier one
## (WeaponFX.blood_strength_max caps it) and a stray pellet a small one.
@export var blood_per_pellet: float = 0.45
## Seconds between the shot and the pump starting back.
@export var pump_delay: float = 0.14
## Seconds each stroke of the pump takes (back, then home).
@export var pump_stroke: float = 0.13
## Seconds the pump rests fully back while the shell clears.
@export var pump_hold: float = 0.03
## Camera shake per shot (0..1).
@export var shake_amount: float = 0.35
## Muzzle flash size (metres) and life (seconds): about twice the rifle's.
@export var flash_size: float = 0.6
@export var flash_life: float = 0.085
## How fast a spent shell leaves the ejection port (m/s).
@export var eject_speed: float = 3.2
@export var tracer_color: Color = Color(1.0, 0.8, 0.45)

## The gun: an original pump shotgun (walnut, blued steel) modelled and texture-baked in Blender
## by tools/make_weapons.py. Its `Pump` node (forend and action bars) slides back by the gap to
## its `PumpBack` marker, `Shell` is the spent case thrown from `EjectPort`. The box model
## below is only the fallback.
const MODEL_PATH := "res://assets/models/weapon_shotgun.glb"
## Muzzle and pump travel for a model without its own markers.
const MODEL_MUZZLE := Vector3(0.0, 0.0, -0.633)
const MODEL_PUMP_TRAVEL := 0.08
## Colours of the fallback box model.
const WOOD := Color(0.30, 0.17, 0.08)
const STEEL := Color(0.07, 0.075, 0.09)

var _pump: Node3D
var _pump_rest := Vector3.ZERO
var _pump_travel := MODEL_PUMP_TRAVEL
var _shell_mesh: Mesh
var _port := Vector3(0.019, 0.003, -0.06)
var _since_shot := 10.0
var _racked := true
var _ejected := true
var _grip_left_rest: Vector3


func _init() -> void:
	display_name = "Shotgun"
	fire_rate = 1.25
	automatic = false
	kick_distance = 0.14
	kick_recover_speed = 10.0
	camera_kick_deg = 3.2
	alarm_radius = 70.0
	alarm_screams = 5
	lock_on = true
	# The right wrist behind the stock's semi-pistol grip, the left under the forend (it rides
	# the forend back and forth while the pump cycles). The butt sits where the rifle's does.
	# Fitted to the hero by tools/grip_fit.gd.
	grip_right = Vector3(0.014, -0.049, 0.197)
	grip_right_fingers = Vector3(-0.000, -0.475, -1.300)
	grip_right_palm = Vector3(-0.025, 1.650, -0.750)
	grip_left = Vector3(-0.042, -0.070, -0.229)
	grip_left_fingers = Vector3(0.400, 0.350, -0.850)
	grip_left_palm = Vector3(0.450, 2.350, -0.150)
	curl_right = Vector3(70, 62, 93)
	curl_trigger = Vector3(6, 18, 95)
	curl_thumb = Vector3(11, 0, 28)
	curl_left = Vector3(54, 70, 95)
	curl_left_thumb = Vector3(39, 57, 20)
	thumb_wrap = Vector2(-24, 8)
	hold_twist = Vector2(12, 54)
	hold_aim = Vector3(0.022, -0.056, -0.425)
	hold_hip = Vector3(-0.264, -0.150, -0.196)
	hold_hip_rot = Vector3(-16.0, 33.5, 4.0)
	_grip_left_rest = grip_left


func _build_model() -> void:
	var model := _load_model(MODEL_PATH)
	if model == null:
		_build_box_model()
		return
	_pump = model.get_node_or_null("Pump") as Node3D
	if _pump:
		_pump_rest = _pump.position
		var back := model.get_node_or_null("PumpBack") as Node3D
		if back:
			_pump_travel = absf(back.position.z - _pump_rest.z)
	var shell := model.get_node_or_null("Shell") as MeshInstance3D
	if shell:
		_shell_mesh = shell.mesh
		shell.visible = false
	var port := model.get_node_or_null("EjectPort") as Node3D
	if port:
		_port = port.position
	var mark := model.get_node_or_null("Muzzle") as Node3D
	_make_muzzle(mark.position if mark else MODEL_MUZZLE)


## Instances a generated gun model as a child; null when the file is missing.
func _load_model(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	return model


## A box shotgun, the fallback when the model file is missing.
func _build_box_model() -> void:
	_box(Vector3(0.036, 0.13, 0.28), WOOD, Vector3(0.0, -0.05, 0.22), Vector3(-12.0, 0.0, 0.0))
	_box(Vector3(0.03, 0.05, 0.2), STEEL, Vector3(0.0, -0.008, -0.02), Vector3.ZERO, 0.8, 0.35)
	_cylinder(0.011, 0.52, STEEL, Vector3(0.0, 0.0, -0.37), 0.8, -1.0, 0.3)
	_cylinder(0.011, 0.44, STEEL, Vector3(0.0, -0.023, -0.34), 0.8, -1.0, 0.35)
	var fore := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.044, 0.045, 0.225)
	fore.mesh = box
	fore.material_override = _mat(WOOD)
	fore.position = Vector3(0.0, -0.023, -0.3175)
	add_child(fore)
	_pump = fore
	_pump_rest = fore.position
	_make_muzzle(MODEL_MUZZLE)


func _process(delta: float) -> void:
	super(delta)
	_since_shot += delta
	var back := pump_amount()
	if _pump:
		_pump.position = _pump_rest + Vector3(0.0, 0.0, _pump_travel * back)
	# The left hand rides the forend.
	grip_left = _grip_left_rest + Vector3(0.0, 0.0, _pump_travel * back)
	if not _racked and _since_shot >= pump_delay:
		_racked = true
		Sfx.play("pump", global_position, -2.0, randf_range(0.96, 1.04))
	if not _ejected and _since_shot >= pump_delay + pump_stroke:
		_ejected = true
		_eject_shell()


## How far back the pump is right now: 0 home (action closed), 1 fully back.
func pump_amount() -> float:
	var u := _since_shot - pump_delay
	if u <= 0.0:
		return 0.0
	if u < pump_stroke:
		return smoothstep(0.0, 1.0, u / pump_stroke)
	u -= pump_stroke
	if u < pump_hold:
		return 1.0
	u -= pump_hold
	if u < pump_stroke:
		return 1.0 - smoothstep(0.0, 1.0, u / pump_stroke)
	return 0.0


func _fire(aim: Dictionary) -> void:
	_since_shot = 0.0
	_racked = false
	_ejected = false
	var from: Vector3 = aim.origin
	var people := {}
	for i in pellets:
		fire_pellet(from, _spread(aim.direction), people)
	# People take the whole charge at once, as one wound as heavy as the pellets in it: thrown by
	# all of it, bleeding out of the far side, onto the wall behind and the ground, then pooling
	# (WeaponFX.bullet_wound). A body already down just bleeds again (its pellets shoved it).
	for person in people:
		if not is_instance_valid(person):
			continue
		var n: int = people[person][0]
		var dir: Vector3 = people[person][1]
		var down: bool = person.has_method("fling")
		var knock := Vector3.ZERO if down else dir * (knock_base + knock_per_pellet * n) + Vector3.UP * (4.0 + n)
		WeaponFX.bullet_wound(self, {"collider": person, "position": people[person][2]}, dir,
			blood_per_pellet * n, knock)
	WeaponFX.flash(self, muzzle.global_position, Color(1.0, 0.72, 0.35), flash_size, flash_life)
	player.camera_rig.shake(shake_amount)
	Sfx.play("shotgun", muzzle.global_position, 2.0, randf_range(0.95, 1.05))


## A direction inside the pellet cone round `dir`, spread evenly over its area.
func _spread(dir: Vector3) -> Vector3:
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized().rotated(dir, randf() * TAU)
	return dir.rotated(side, deg_to_rad(spread_deg) * sqrt(randf())).normalized()


## Fires one pellet: the rifle's hit path (props shoved, street props damaged, traffic knocked
## loose) with the shotgun's numbers. People hit - and bodies already down, by their Ragdoll -
## are gathered into `people` (who -> [pellets, direction, first hit point]) so _fire() throws
## and bleeds each once with all of it. Public so tests can call it.
func fire_pellet(from: Vector3, dir: Vector3, people: Dictionary = {}) -> Dictionary:
	var to := from + dir * pellet_range
	var query := PhysicsRayQueryParameters3D.create(from, to, Player.AIM_MASK, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end := to
	if hit:
		end = hit.position
		var body := hit.collider as RigidBody3D
		if body:
			body.sleeping = false
			body.apply_impulse(dir * pellet_force, hit.position - body.global_position)
			# A body already down (one rigid body under its Ragdoll): its pellets are summed too.
			var doll := body.get_parent()
			if doll != null and doll.has_method("shot") and doll.has_method("fling"):
				_gather(people, doll, dir, hit.position)
		elif hit.collider.has_method("take_hit"):
			hit.collider.take_hit(hit.get("shape", -1), pellet_damage, dir)
		elif hit.collider.has_method("knock"):
			_gather(people, hit.collider, dir, hit.position)
		if hit.collider is Vehicle:
			(hit.collider as Vehicle).drop_out_of_traffic(dir * pellet_force)
		WeaponFX.impact(self, hit.position, Color(1.0, 0.85, 0.5), hit.normal, hit.collider)
	WeaponFX.tracer(self, muzzle.global_position, end, tracer_color, 0.05, 0.012)
	return hit


## Counts one more pellet into a person (or a body): [pellets, direction, first hit point].
static func _gather(people: Dictionary, who: Object, dir: Vector3, at: Vector3) -> void:
	if people.has(who):
		people[who][0] = int(people[who][0]) + 1
	else:
		people[who] = [1, dir, at]


## Throws a spent shell out of the ejection port: a small rigid body that clatters off the
## ground and is cleaned up with the other debris (PhysicsBudget).
func _eject_shell() -> void:
	if _shell_mesh == null or not is_inside_tree() or not visible:
		return
	if not PhysicsBudget.make_room(1):
		return
	var shell := RigidBody3D.new()
	shell.name = "SpentShell"
	shell.mass = 0.04
	shell.collision_layer = 0 # nothing aims at it
	shell.collision_mask = 1  # it lands on the world
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.011
	cyl.height = 0.07
	shape.shape = cyl
	shape.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	shell.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _shell_mesh
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.add_child(mesh)
	shell.add_to_group("spent_shell")
	WeaponFX.fx_parent(self).add_child(shell)
	shell.global_transform = Transform3D(global_basis, global_transform * _port)
	var out := (global_basis.x * 1.0 + global_basis.y * 0.55 + global_basis.z * 0.2).normalized()
	var carry: Vector3 = player.velocity if player else Vector3.ZERO
	shell.linear_velocity = carry + out * eject_speed * randf_range(0.85, 1.15)
	shell.angular_velocity = global_basis.y * randf_range(9.0, 15.0) + global_basis.x * randf_range(-4.0, 4.0)
	PhysicsBudget.register_debris(shell)
