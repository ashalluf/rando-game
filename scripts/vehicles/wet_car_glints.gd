class_name WetCarGlints
extends Node3D
## Cars' head and tail lamps mirrored in the wet road at night (RainStreetNight, the street_night
## refcam review): a rainy night street is mostly the long white streaks of oncoming headlights and
## the red ones of the cars driving away, and nothing drew them - the Compatibility renderer has no
## screen-space reflections, and Forward+'s miss whatever lamp is out of the frame or under a car.
##
## One MultiMesh of NightAtmos' own wet streak (night_wet.gdshader: an instance's origin is the road
## under the light, its basis y the light's height over it, COLOR the light's colour, CUSTOM.r its
## strength; the streak is laid toward the camera in the vertex stage), four instances a car on the
## nearest `max_cars` running cars within `reach` of the camera: a head lamp's strength by how much
## it faces the eye, a tail lamp's by how much it faces away, brighter on the brake. Picked every
## `pick_seconds`, placed every frame from the cars' transforms. Hidden (no draw) by day, on a dry
## road, or with RAIN_STREET_NIGHT=0 (never made).

## Cars carrying a reflection, the nearest first, and how far they may be from the camera.
@export var max_cars: int = 18
@export var reach: float = 75.0
@export var pick_seconds: float = 0.25
## Strengths (x the streak shader's own gain): a head lamp facing the eye, a tail lamp facing away,
## the tail lamp on the brake.
@export var head_strength: float = 0.75
@export var tail_strength: float = 0.42
@export var brake_strength: float = 0.9

const HEAD := Color(1.0, 0.95, 0.82)
const TAIL := Color(1.0, 0.16, 0.10)
const PER_CAR := 4

static var _node_id: int = 0

var _mm: MultiMesh
var _inst: MultiMeshInstance3D
var _cars: Array = []
var _pick_t: float = 0.0


## Makes the node once under `city` (NightAtmos calls it from its own _ready). Safe to call again.
static func ensure(city: Node) -> void:
	if not RainStreetNight.enabled or city == null or not (city is Node3D):
		return
	if _node_id != 0 and is_instance_id_valid(_node_id):
		return
	var n := WetCarGlints.new()
	n.name = "WetCarGlints"
	_node_id = n.get_instance_id()
	city.add_child.call_deferred(n)


## The city's node, or null.
static func node() -> WetCarGlints:
	if _node_id == 0 or not is_instance_id_valid(_node_id):
		return null
	return instance_from_id(_node_id) as WetCarGlints


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = NightAtmos.wet_mesh()
	_mm.instance_count = max_cars * PER_CAR
	_mm.visible_instance_count = 0
	_inst = MultiMeshInstance3D.new()
	_inst.name = "Streaks"
	_inst.multimesh = _mm
	_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The streaks are laid in the vertex stage wherever the camera needs them: never culled by the
	# node's own (empty) bounds.
	_inst.custom_aabb = AABB(Vector3(-1e5, -1e3, -1e5), Vector3(2e5, 2e3, 2e5))
	add_child(_inst)


func _exit_tree() -> void:
	if _node_id == get_instance_id():
		_node_id = 0


## True while the reflections can show at all: lamps on and the road wet.
static func wanted(lamp: float, wetness: float) -> bool:
	return lamp > 0.01 and wetness > 0.04


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not wanted(DayNight.lamp_now, PropFactory._wetness):
		_inst.visible = false
		_cars.clear()
		return
	_inst.visible = true
	_pick_t -= delta
	if _pick_t <= 0.0:
		_pick_t = pick_seconds
		_pick(cam.global_position)
	_place(cam.global_position)


## The nearest running cars within reach (lamps on, not a wreck), nearest first.
func _pick(eye: Vector3) -> void:
	var near: Array = []
	var r2 := reach * reach
	for v in get_tree().get_nodes_in_group("vehicle"):
		var car := v as Vehicle
		if car == null or not car.is_inside_tree() or not car.visible:
			continue
		var d2 := car.global_position.distance_squared_to(eye)
		if d2 > r2 or not car.lights_running():
			continue
		near.append([d2, car])
	near.sort_custom(func(a, b): return a[0] < b[0])
	_cars.clear()
	for i in mini(near.size(), max_cars):
		_cars.append(near[i][1])


## The four lamps of `car` in its body space: [position, height of the lamp over the road, is head].
static func lamps(car: Vehicle) -> Array:
	if car.has_meta("wet_glint_lamps"):
		return car.get_meta("wet_glint_lamps")
	var d: Dictionary = car._dims()
	var lamp_y := float(d.get("lamp_y", 0.55 + float(d.get("chassis_h", 0.6)) * 0.62))
	var tail_y := float(d.get("tail_y", lamp_y))
	var road := float(d.get("road", d.get("ride", -0.24)))
	var length := float(d.get("light_len", d.get("length", 4.4)))
	var z0 := float(d.get("light_z", 0.0))
	var x := float(d.get("width", 1.8)) * 0.5 - 0.26
	var out: Array = []
	for side: float in [-1.0, 1.0]:
		out.append([Vector3(side * x, road, z0 - length * 0.5), lamp_y - road, true])
		out.append([Vector3(side * x, road, z0 + length * 0.5), tail_y - road, false])
	car.set_meta("wet_glint_lamps", out)
	return out


func _place(eye: Vector3) -> void:
	var to_local := global_transform.affine_inverse()
	var n := 0
	for car in _cars:
		if not is_instance_valid(car) or not (car as Vehicle).is_inside_tree():
			continue
		var v := car as Vehicle
		var xf := v.global_transform
		var fwd := -xf.basis.z.normalized()
		var to_eye := eye - xf.origin
		to_eye.y = 0.0
		var facing := fwd.dot(to_eye.normalized()) if to_eye.length_squared() > 0.01 else 0.0
		for l: Array in lamps(v):
			var head: bool = l[2]
			var s: float
			if head:
				s = head_strength * smoothstep(-0.05, 0.55, facing)
			else:
				s = (brake_strength if v.light_brake else tail_strength) * smoothstep(-0.05, 0.55, -facing)
			if s < 0.01:
				continue
			var foot: Vector3 = xf * (l[0] as Vector3)
			var b := Basis.from_scale(Vector3(1.0, maxf(float(l[1]), 0.2), 1.0))
			_mm.set_instance_transform(n, to_local * Transform3D(b, foot))
			_mm.set_instance_color(n, HEAD if head else TAIL)
			_mm.set_instance_custom_data(n, Color(s, 0.0, 0.0, 0.0))
			n += 1
	_mm.visible_instance_count = n
