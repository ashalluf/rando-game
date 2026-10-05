class_name ParkBall
extends MeshInstance3D
## A basketball in a pickup game (Parks.people_steps()): dribbled by one of the court's players,
## put up at the nearer rim on a high arc, dropping through the net, bouncing, picked up by whoever
## is nearest. Scripted, not simulated (no body, no collision): a few vector maths a frame, and
## nothing at all past `active_range` of the camera or once its players are gone (shot, knocked,
## scared off: then it lies on the court).

## Metres from the camera within which the game runs.
@export var active_range: float = 90.0
## Bounces a second while dribbling, and the dribble's height (metres).
@export var dribble_rate: float = 2.1
@export var dribble_height: float = 0.85
## Seconds a player dribbles before shooting (min, max), and a shot's flight time.
@export var dribble_seconds: Vector2 = Vector2(2.0, 5.5)
@export var shot_seconds: float = 1.15

const RADIUS := 0.12
const RIM_Y := 3.05

var players: Array = []
## The two rims (chunk space, the court surface's height included) and the court's centre.
var rims: Array[Vector3] = []
var court_y: float = 0.3
var _carrier: Node3D = null
var _state: int = 0
var _t: float = 0.0
var _hold: float = 3.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _rng := RandomNumberGenerator.new()

static var _mesh: Mesh = null


static func ball_mesh() -> Mesh:
	if _mesh != null:
		return _mesh
	var s := SphereMesh.new()
	s.radius = RADIUS
	s.height = RADIUS * 2.0
	s.radial_segments = 12
	s.rings = 6
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.32, 0.12)
	m.roughness = 0.75
	s.material = m
	_mesh = s
	return s


func _ready() -> void:
	mesh = ball_mesh()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_rng.seed = hash([position, "ball"])
	_hold = _rng.randf_range(dribble_seconds.x, dribble_seconds.y)


func _alive(p: Variant) -> bool:
	return is_instance_valid(p) and not (p as Node).is_queued_for_deletion() and not bool(p.get("_down")) and float(p.get("_panic_left")) <= 0.0


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(global_position) > active_range:
		return
	var live: Array = []
	for p: Variant in players:
		if _alive(p):
			live.append(p)
	if live.is_empty():
		# Nobody playing: it rolls to a stop where it is.
		position.y = court_y + RADIUS
		return
	_t += delta
	match _state:
		0:
			if _carrier == null or not _alive(_carrier):
				_carrier = _nearest(live)
			var c: Node3D = _carrier
			var yaw: float = (c.get("_visual") as Node3D).rotation.y if c.get("_visual") else 0.0
			var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var right := Vector3(-fwd.z, 0.0, fwd.x)
			var bounce := absf(sin(_t * PI * dribble_rate))
			position = c.position + fwd * 0.35 + right * 0.28
			position.y = court_y + RADIUS + bounce * dribble_height
			if _t > _hold:
				_state = 1
				_t = 0.0
				_from = position + Vector3(0.0, 1.4, 0.0)
				_to = _nearest_rim(c.position)
		1:
			var k := clampf(_t / shot_seconds, 0.0, 1.0)
			var arc := 4.0 * k * (1.0 - k) * 1.9
			position = _from.lerp(_to, k) + Vector3(0.0, arc, 0.0)
			if k >= 1.0:
				_state = 2
				_t = 0.0
				_from = _to
				var away := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
				_to = Vector3(_from.x, court_y, _from.z) + away * _rng.randf_range(1.5, 3.5)
		2:
			# Through the net and down, two bounces away from the post.
			var k := clampf(_t / 1.3, 0.0, 1.0)
			var h := (RIM_Y - 0.4) * (1.0 - k) * absf(cos(k * PI * 1.5))
			position = _from.lerp(_to, k)
			position.y = court_y + RADIUS + h
			if k >= 1.0:
				_state = 0
				_t = 0.0
				_carrier = _nearest(live)
				_hold = _rng.randf_range(dribble_seconds.x, dribble_seconds.y)


func _nearest(live: Array) -> Node3D:
	var best: Node3D = live[0]
	for p: Node3D in live:
		if p.position.distance_squared_to(position) < best.position.distance_squared_to(position):
			best = p
	return best


func _nearest_rim(p: Vector3) -> Vector3:
	if rims.is_empty():
		return p + Vector3(0.0, 3.0, 0.0)
	var best := rims[0]
	for r in rims:
		if r.distance_squared_to(p) < best.distance_squared_to(p):
			best = r
	return best
