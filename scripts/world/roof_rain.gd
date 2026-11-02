class_name RoofRain
extends MultiMeshInstance3D
## Rain splashing off the roofs of the cars round the player: a pool of short-lived crowns of
## spray in ONE MultiMesh (shaders/roof_splash.gdshader), animated here in GDScript - no particle
## system per car, no physics. Every `scan_interval` the nearest cars within `reach` are listed;
## each frame new splashes are dropped at random on their roofs (the body's measured top,
## `Vehicle._model_top_y`, over its cabin) at a rate that follows the rain, and each one grows and
## fades over `life` seconds. Weather owns it and sets `rain`; at zero it is hidden.

@export var pool: int = 220
@export var reach: float = 26.0
@export var max_cars: int = 10
## Splashes per second per car at full rain.
@export var rate: float = 34.0
@export var life: float = 0.32
@export var scan_interval: float = 0.4

var rain: float = 0.0
var low_detail: bool = false
var _cars: Array = []
var _age: PackedFloat32Array = PackedFloat32Array()
var _xf: Array[Transform3D] = []
var _next: int = 0
var _carry: float = 0.0
var _scan_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "RoofRain"
	_rng.seed = 777
	var n := pool / 2 if OS.has_feature("web") else pool
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/roof_splash.gdshader")
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = n
	multimesh = mm
	_age.resize(n)
	_xf.resize(n)
	for i in n:
		_age[i] = 1.0e9
		_xf[i] = Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0.0, -1.0e4, 0.0))
		mm.set_instance_transform(i, _xf[i])
		mm.set_instance_custom_data(i, Color(1.0, 0.0, 0.0, 0.0))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	custom_aabb = AABB(Vector3(-60, -30, -60), Vector3(120, 60, 120))
	visible = false


func _process(delta: float) -> void:
	var on := rain > 0.05 and not low_detail
	if not on and not visible:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		global_position = player.global_position
	_scan_left -= delta
	if _scan_left <= 0.0 and on:
		_scan_left = scan_interval
		_scan(player)
	var mm := multimesh
	var n := mm.instance_count
	# New splashes, spread over the listed cars.
	if on and not _cars.is_empty():
		_carry += rate * rain * float(_cars.size()) * delta
		while _carry >= 1.0:
			_carry -= 1.0
			var held: Variant = _cars[_rng.randi() % _cars.size()]
			if not is_instance_valid(held) or not (held as Node3D).is_inside_tree():
				continue
			_spawn(held as Node3D)
	var alive := 0
	var origin := global_position
	for i in n:
		if _age[i] > life:
			continue
		_age[i] += delta
		var u := _age[i] / life
		if u > 1.0:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0.0, -1.0e4, 0.0)))
			continue
		alive += 1
		var t := _xf[i]
		mm.set_instance_transform(i, Transform3D(t.basis, t.origin - origin))
		mm.set_instance_custom_data(i, Color(u, t.basis.x.length(), 0.0, 0.0))
	visible = on or alive > 0


func _spawn(car: Node3D) -> void:
	var top := float(car.get("_model_top_y")) if car.get("_model_top_y") != null else 1.5
	var dims: Variant = car.call("_dims") if car.has_method("_dims") else null
	var width := 1.8
	var cabin := Vector2(-1.0, 2.2)
	if dims is Dictionary:
		width = float((dims as Dictionary).get("width", 1.8))
		cabin = (dims as Dictionary).get("cabin", cabin)
	var local := Vector3(_rng.randf_range(-0.36, 0.36) * width, top - 0.03, cabin.x + _rng.randf() * cabin.y)
	var at := car.global_transform * local
	var s := _rng.randf_range(0.10, 0.2)
	_xf[_next] = Transform3D(Basis.from_scale(Vector3(s, s * _rng.randf_range(0.7, 1.3), s)), at)
	_age[_next] = 0.0
	_next = (_next + 1) % _age.size()


func _scan(player: Node3D) -> void:
	_cars.clear()
	if player == null:
		return
	var here := player.global_position
	var ranked: Array = []
	for node in get_tree().get_nodes_in_group("vehicle"):
		var car := node as Node3D
		if car == null or car is Aircraft or not car.is_inside_tree():
			continue
		var d := car.global_position.distance_to(here)
		if d < reach:
			ranked.append([d, car])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	for r in ranked:
		if _cars.size() >= max_cars:
			break
		_cars.append(r[1])
