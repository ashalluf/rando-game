class_name BeachRider
extends AnimatableBody3D
## Somebody moving along the bike path (BeachActivity): a cyclist on a beach cruiser (a flipbook of
## baked frames, BeachFigure.ride_meshes(), the crank turning with the pace) or a skateboarder
## gliding. Not a rig: one mesh, swapped as the crank turns. This body is on the npc layer, so a
## round, a blast or a car finds it like anyone; then the rider becomes a live BeachGoer that takes
## the hit (and falls), and the bike goes tumbling on as debris.

## The meshes, frame by frame (one for a skater).
var frames: Array = []
## Who it is (BeachFigure / BeachGoer: seed, crowd rig, suit) and the bike's paint.
var seed_value: int = 0
var model: int = 0
var suit: int = 0
var paint: int = 0
var skater: bool = false
## Which way along the shore (+1 / -1 in z), the pace (m/s), and the stretch it rides (world z).
var dir: float = 1.0
var speed: float = 5.0
var z_lo: float = 0.0
var z_hi: float = 0.0
var z: float = 0.0
var chunk: CityChunk
var _mesh: MeshInstance3D
var _crank: float = 0.0
var _boost: float = 0.0
var _sway: float = 0.0
var _gone: bool = false


func _init() -> void:
	collision_layer = 8
	collision_mask = 0
	sync_to_physics = false


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Rider"
	_mesh.visibility_range_end = 180.0
	if not frames.is_empty():
		_mesh.mesh = frames[0]
	add_child(_mesh)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0.0, 0.95, 0.0)
	add_child(cs)
	_crank = fposmod(float(seed_value % 997) * 0.37, 1.0)
	_sway = float(seed_value % 113)
	_place()


## Moves on along the path: `dt` seconds, `scared` if something frightened riders here lately.
func advance(dt: float) -> void:
	if _gone:
		return
	_boost = maxf(_boost - dt, 0.0)
	var v := speed * (1.55 if _boost > 0.0 else 1.0)
	z += dir * v * dt
	if dir > 0.0 and z > z_hi:
		z = z_lo
	elif dir < 0.0 and z < z_lo:
		z = z_hi
	if not skater and frames.size() > 1:
		# A cruiser's gear: about 5 m a turn of the crank.
		_crank = fposmod(_crank + v * dt / 5.0, 1.0)
		var f := mini(int(_crank * frames.size()), frames.size() - 1)
		_mesh.mesh = frames[f]
	_sway += dt
	_place()


func scare() -> void:
	_boost = 9.0


func _place() -> void:
	if chunk == null or chunk.plan == null or chunk.plan.macro == null:
		return
	var plan := chunk.plan
	var x := BeachLife.path_x(plan, z) - dir * 0.85
	var slope := (BeachLife.path_x(plan, z + 1.0) - BeachLife.path_x(plan, z - 1.0)) * 0.5
	var d := Vector2(slope * dir, dir).normalized()
	var yaw := atan2(-d.x, -d.y)
	if skater:
		# Side-on: the board (the figure's x) runs the way they go, carving a little.
		yaw += PI * 0.5 + sin(_sway * 0.9) * 0.18
	var y := BeachLife.sand_y(chunk, x, z) + BeachLife.PATH_LIFT + (0.1 if skater else 0.0)
	transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))


## A round (WeaponFX.bullet_wound()): off the bike, and the round goes into them.
func shot(at: Vector3, hit_dir: Vector3, impulse: Vector3, strength: float = 1.0) -> void:
	var p := _fall(impulse)
	if p:
		p.shot(at, hit_dir, impulse, strength)


func knock(impulse: Vector3, gibs: int = 0) -> void:
	var p := _fall(impulse)
	if p:
		p.knock(impulse, gibs)


func take_hit(_shape_index: int, _damage: float, hit_dir: Vector3 = Vector3.UP) -> void:
	knock(hit_dir.normalized() * 4.0 + Vector3.UP)


## The rider as a live BeachGoer standing where they rode (to take the hit), and the bike thrown on.
func _fall(impulse: Vector3) -> BeachGoer:
	if _gone or chunk == null or not is_instance_valid(chunk):
		return null
	_gone = true
	collision_layer = 0
	var ped := BeachGoer.new()
	var here := Vector2(position.x, position.z)
	ped.setup_sleeper(BeachLife.sand_ring(chunk, z_lo, z_hi), 4.0, seed_value, RoughSleeper.Pose.STAND, here, rotation.y)
	ped.suit = suit
	ped.position = position
	chunk.add_child(ped)
	if not skater:
		var xf := transform
		EncampmentItem.throw(chunk, BeachFigure.lone_bike(paint), Vector3(0.5, 0.8, 1.6), 0.45, 18.0, Color.WHITE, Color(0.0, 0.0, 0.0, 0.0), xf, impulse * 0.5 + Vector3(0.0, 1.5, 0.0) - transform.basis.z * speed * 0.8)
	queue_free()
	return ped
