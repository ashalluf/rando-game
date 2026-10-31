class_name HouseNightLights
extends Node
## Real lights on the few lit porches nearest the camera (HouseNights): a pool of `budget`
## OmniLight3Ds, Forward+ desktop only (`supported()`), handed every `pick_interval` to the
## nearest porches within `reach` while the lamps are on, faded by distance. Everything else a
## house throws after dark is the additive glow quads. FULL chunks register their porches
## (`add_spot()`, chunk-local, which is true world inside a chunk); a chunk's spots go with it.
## One node under the tree root, made by the first porch registered.

## Lights at each Quality level (Quality._apply_level(): 4, 2, 0, 0).
static var budget: int = 4
## Metres from the camera a porch may be lit from.
static var reach: float = 48.0
static var pick_interval: float = 0.4
static var energy: float = 1.3
static var light_range: float = 6.5

static var _inst: HouseNightLights
## chunk instance id -> [WeakRef to the chunk, PackedVector3Array local spots, PackedColorArray]
static var _spots := {}

var _lights: Array[OmniLight3D] = []
var _t := 0.0


static func supported() -> bool:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return false
	return RenderingServer.get_current_rendering_method() == "forward_plus"


static func add_spot(ch: Node3D, local: Vector3, tint: Color) -> void:
	var id := ch.get_instance_id()
	if not _spots.has(id):
		if _spots.size() > 256:
			prune()
		_spots[id] = [weakref(ch), PackedVector3Array(), PackedColorArray()]
	var e: Array = _spots[id]
	var pts: PackedVector3Array = e[1]
	var cols: PackedColorArray = e[2]
	pts.append(local)
	cols.append(tint)
	e[1] = pts
	e[2] = cols
	if supported() and (_inst == null or not is_instance_valid(_inst)):
		var tree := ch.get_tree() if ch.is_inside_tree() else (Engine.get_main_loop() as SceneTree)
		if tree != null:
			_inst = HouseNightLights.new()
			_inst.name = "HouseNightLights"
			tree.root.add_child.call_deferred(_inst)


## Drops the spots of chunks that are gone.
static func prune() -> void:
	for id: int in _spots.keys():
		if (_spots[id][0] as WeakRef).get_ref() == null:
			_spots.erase(id)


## The number of porches registered (tests).
static func spot_count() -> int:
	var n := 0
	for id: int in _spots:
		n += (_spots[id][1] as PackedVector3Array).size()
	return n


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = pick_interval
	var cam := get_viewport().get_camera_3d()
	var lamp := DayNight.lamp_now
	while _lights.size() < budget:
		var l := OmniLight3D.new()
		l.omni_range = light_range
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.light_specular = 0.25
		l.visible = false
		add_child(l)
		_lights.append(l)
	if cam == null or lamp < 0.05 or budget <= 0:
		for l: OmniLight3D in _lights:
			l.visible = false
		return
	var cp := cam.global_position
	var best: Array = []
	for id: int in _spots.keys():
		var e: Array = _spots[id]
		var ch := (e[0] as WeakRef).get_ref() as Node3D
		if ch == null or not ch.is_inside_tree():
			_spots.erase(id)
			continue
		var pts: PackedVector3Array = e[1]
		var cols: PackedColorArray = e[2]
		var xf := ch.global_transform
		for i in pts.size():
			var p := xf * pts[i]
			var d := p.distance_to(cp)
			if d < reach:
				best.append([d, p, cols[i]])
	best.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in _lights.size():
		var l := _lights[i]
		if i < mini(best.size(), budget):
			var d: float = best[i][0]
			l.global_position = best[i][1]
			var c: Color = best[i][2]
			l.light_color = c
			l.light_energy = energy * lamp * clampf((reach - d) / (reach * 0.3), 0.0, 1.0)
			l.visible = true
		else:
			l.visible = false
