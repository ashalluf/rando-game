class_name PoliceNightLook
extends Node
## The police at night (fleet wave 3 "police-night", docs/HANDOFF.md "Red and blue at night"): a
## chase or a roadblock after dark is red and blue strobes washing the street, the facades and the
## wet road, glare on the lens. One node under the tree root, made by the first PoliceCar.
##
##   clock      ONE flash clock (`clock`, advanced here) that the bar's lenses
##              (police_lights.gdshader `clock`), the real lights and the washes all read, so the
##              light on the street is the lens that is lit. Before this the lenses ran off shader
##              TIME and the car's own light off the wall clock: they drifted apart.
##   lights     a budgeted pool of real OmniLight3Ds (`budget`, Quality: 6 / 4 / 2 / 0) on the
##              lit cruisers nearest the camera within `reach`, Forward+ desktop only (`supported()`,
##              CarLights' rule): moved each frame onto the lit bank, red or blue. They light the
##              road, the walls, and every car's paint and glass round it (the strobes in the
##              lacquer). The cruiser's own old BarLight stays dark while this runs.
##   washes     on every renderer, each lit cruiser within `wash_reach` carries a `Glow`
##              (shaders/police_wash.gdshader, ONE ShaderMaterial a car, never instance
##              uniforms): flares and a lens streak on the bar, a pool on the road with the bar
##              mirrored in it when the road is wet, a wash on the facade either side (two rays a
##              car every `wall_interval`).
##   flares     a roadblock cruiser lays a line of burning road flares (FreewayIncidentKit's) on the
##              side the trouble comes from.
## Nothing here rolls a random number: a car's look is its own `_phase`.
## POLICE_NIGHT_LOOK=0 in the environment is the A/B (the old bar, its own BarLight).

## Off with POLICE_NIGHT_LOOK=0.
static var enabled: bool = OS.get_environment("POLICE_NIGHT_LOOK") != "0"
## Real lights anywhere (checks, stills off Forward+).
static var force: bool = false
## Real OmniLight3Ds for cruisers (Quality: 6 / 4 / 2 / 0).
static var budget: int = 6
## The shared flash clock (seconds).
static var clock: float = 0.0
## Stills: the clock is not advanced (tools/police_night/police_shot.gd sets it frame by frame).
static var hold: bool = false
## Real lights in use this frame, for checks and the HUD.
static var active_count: int = 0
static var _inst: PoliceNightLook = null
## The pool rides this far over the road: over the kerb and the pavement too (at 6 cm the
## pavement's 15 cm step cut it off along a ruler-straight line). Additive and soft, it never
## shows the gap.
const POOL_LIFT := 0.22
static var _glow_mesh: ArrayMesh = null
static var _pool_mesh: ArrayMesh = null
static var _wall_mesh: ArrayMesh = null
static var _wall_mesh_b: ArrayMesh = null

## Real lights only within this of the camera (m).
@export var reach: float = 90.0
## A real light's energy and range at full night.
@export var light_energy: float = 4.2
@export var light_range: float = 17.0
## Washes (pool, walls, glare) within this of the camera (m).
@export var wash_reach: float = 220.0
## How often the lights are handed out (s), and the walls looked for (s).
@export var pick_interval: float = 0.15
@export var wall_interval: float = 0.6
## How far to the side a facade can be and still take the wash (m).
@export var wall_reach: float = 16.0
## The pool on the road: its size (m).
@export var pool_size: float = 30.0
## Road flares at a roadblock: how many, and how far out from the car (m).
@export var flare_count: int = 5
@export var flare_out: float = 6.5

var _lights: Array = [] # each [OmniLight3D, PoliceCar or null, weight]
var _pick_t: float = 0.0
var _wall_t: float = 0.0
var _night: float = 0.0
var _night_t: float = 0.0
## POLICE_NIGHT_DEBUG=1 prints every cruiser's state every 2 s.
var _debug: bool = OS.get_environment("POLICE_NIGHT_DEBUG") == "1"
var _debug_t: float = 0.0


static func ensure(from: Node) -> void:
	if not enabled:
		return
	if _inst != null and is_instance_valid(_inst):
		return
	var tree := from.get_tree()
	if tree == null:
		return
	_inst = PoliceNightLook.new()
	_inst.name = "PoliceNightLook"
	tree.root.add_child.call_deferred(_inst)


static func instance() -> PoliceNightLook:
	return _inst if _inst != null and is_instance_valid(_inst) else null


## Real lights: Forward+ desktop only (the Compatibility renderer lights per object and the web
## keeps the washes), unless forced.
static func supported() -> bool:
	if force:
		return true
	if OS.has_feature("web"):
		return false
	return RenderingServer.get_current_rendering_method() == "forward_plus"


func _ready() -> void:
	process_priority = 10
	# Stills: POLICE_NIGHT_T=<s> holds the flash clock there (a frame strip steps it).
	var t := OS.get_environment("POLICE_NIGHT_T")
	if t != "":
		hold = true
		clock = float(t)


func _exit_tree() -> void:
	if _inst == self:
		_inst = null
		active_count = 0


func _process(delta: float) -> void:
	if not hold:
		clock += delta
	_night_t -= delta
	if _night_t <= 0.0:
		_night_t = 0.4
		_night = _lamp_level()
	var cars := get_tree().get_nodes_in_group("police_car")
	var cam := get_viewport().get_camera_3d()
	_wall_t -= delta
	var do_walls := _wall_t <= 0.0
	if do_walls:
		_wall_t = wall_interval
	for c in cars:
		var car := c as PoliceCar
		if car == null or not car.is_inside_tree():
			continue
		_tick_car(car, cam, do_walls)
	_pick_t -= delta
	if _pick_t <= 0.0:
		_pick_t = pick_interval
		_pick(cars, cam)
	_place_lights()
	if _debug:
		_debug_t -= delta
		if _debug_t <= 0.0:
			_debug_t = 2.0
			for c in cars:
				var pc := c as PoliceCar
				if pc == null:
					continue
				var g := pc.get_node_or_null("PoliceGlow") as Node3D
				print("POLICE_NIGHT car %s lit=%s side=%d glow=%s night=%.2f clock=%.2f lights=%d dist=%.0f" % [pc.name, pc.bar_lit(), pc.flash_side(clock), g.visible if g else null, _night, clock, active_count, cam.global_position.distance_to(pc.global_position) if cam else -1.0])


# --- Washes ----------------------------------------------------------------------------------

## A cruiser's glow, made the first time it is lit within reach and kept with the car (pooled
## with it); hidden when its lights are off, it is out of reach, or it is day for the pools.
func _tick_car(car: PoliceCar, cam: Camera3D, do_walls: bool) -> void:
	var lit := car.bar_lit()
	var near := cam != null and cam.global_position.distance_to(car.global_position) < wash_reach
	var glow := car.get_node_or_null("PoliceGlow") as Node3D
	if not (lit and near):
		if glow:
			glow.visible = false
			_show_flares(car, false)
		return
	if glow == null:
		glow = _make_glow(car)
	glow.visible = true
	var mat: ShaderMaterial = glow.get_meta("mat")
	mat.set_shader_parameter("clock", clock)
	mat.set_shader_parameter("real_light", 1.0 if _has_light(car) else 0.0)
	if cam:
		mat.set_shader_parameter("viewport_px", get_viewport().get_visible_rect().size)
	var pool := glow.get_node("Pool") as MeshInstance3D
	var bar := car.get_node_or_null("LightBar") as Node3D
	var bar_y := bar.position.y if bar else 1.5
	# Flat under the car on the road plane, turned with the car's heading only.
	var fwd := car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.BACK
	var right := Vector3.UP.cross(fwd).normalized()
	var ground := car.global_position - car.global_basis.y * car.road_lift()
	var s := pool_size
	pool.global_transform = Transform3D(Basis(right * s, Vector3.UP * s, fwd * s), ground + Vector3.UP * POOL_LIFT)
	mat.set_shader_parameter("bar_height", (bar_y + 0.2 - POOL_LIFT) / s)
	pool.visible = _night > 0.02
	if do_walls:
		_place_walls(car, glow, ground, right)
	for w in ["WallA", "WallB"]:
		var wm := glow.get_node(w) as MeshInstance3D
		wm.visible = wm.get_meta("found", false) and _night > 0.02
	_show_flares(car, car.roadblock)


func _make_glow(car: PoliceCar) -> Node3D:
	var glow := Node3D.new()
	glow.name = "PoliceGlow"
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/police_wash.gdshader")
	mat.set_shader_parameter("rate", car.flash_rate)
	mat.set_shader_parameter("phase", car.flash_phase())
	RcMayhem.dress_police(mat)
	glow.set_meta("mat", mat)
	var bar := car.get_node_or_null("LightBar") as Node3D
	var flare := MeshInstance3D.new()
	flare.name = "Glare"
	flare.mesh = glow_mesh()
	flare.material_override = mat
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flare.extra_cull_margin = 8.0
	flare.custom_aabb = AABB(Vector3(-4.0, -2.0, -4.0), Vector3(8.0, 4.0, 8.0))
	if bar:
		flare.transform = bar.transform
	glow.add_child(flare)
	var pool := MeshInstance3D.new()
	pool.name = "Pool"
	pool.mesh = pool_mesh()
	pool.material_override = mat
	pool.top_level = true
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.add_child(pool)
	for w in ["WallA", "WallB"]:
		var wm := MeshInstance3D.new()
		wm.name = w
		wm.mesh = wall_mesh(w == "WallB")
		wm.material_override = mat
		wm.top_level = true
		wm.visible = false
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.add_child(wm)
	car.add_child(glow)
	return glow


## The facade either side of the car: one ray out each way along the car's right, at bar height.
## A wall found gets a vertical wash quad on it, facing the car.
func _place_walls(car: PoliceCar, glow: Node3D, ground: Vector3, right: Vector3) -> void:
	var space := car.get_world_3d().direct_space_state
	var from := ground + Vector3.UP * 1.6
	for k in 2:
		var wm := glow.get_node("WallA" if k == 0 else "WallB") as MeshInstance3D
		# WallA is on the car's -x (the red bank's side), WallB on +x.
		var dir := -right if k == 0 else right
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * wall_reach, 1)
		q.exclude = [car.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.4:
			wm.set_meta("found", false)
			continue
		var n: Vector3 = hit.normal
		n.y = 0.0
		n = n.normalized()
		var d := from.distance_to(hit.position)
		var w := 14.0 + d * 0.8
		var h := 8.0 + d * 0.3
		var t := Vector3.UP.cross(n).normalized()
		# An additive quad past the end of the wall glows in thin air: find how far the facade
		# really runs each way (rays a quarter of the width apart) and fit the quad to it.
		var plane_d: float = n.dot(hit.position)
		var lo := 0.0
		var hi := 0.0
		for sgn in [-1.0, 1.0]:
			for step in [1, 2]:
				var o: float = sgn * w * 0.25 * float(step)
				var f2 := from + t * o
				var q2 := PhysicsRayQueryParameters3D.create(f2, f2 + dir * (wall_reach + 4.0), 1)
				q2.exclude = [car.get_rid()]
				var h2 := space.intersect_ray(q2)
				if h2.is_empty() or absf(n.dot(h2.position) - plane_d) > 1.0:
					break
				if sgn < 0.0:
					lo = o
				else:
					hi = o
		w = hi - lo
		if w < 4.0:
			wm.set_meta("found", false)
			continue
		var at: Vector3 = hit.position + n * 0.08 + t * ((lo + hi) * 0.5)
		at.y = ground.y + h * 0.5
		wm.global_transform = Transform3D(Basis(t * w, Vector3.UP * h, n), at)
		wm.set_meta("found", true)


## Road flares at a roadblock: a line along the car (so across the road) on the side the player
## is on when it is first laid, burning as long as the car is a roadblock.
func _show_flares(car: PoliceCar, on: bool) -> void:
	var root := car.get_node_or_null("RoadblockFlares") as Node3D
	if not on:
		if root:
			root.queue_free()
		return
	if root != null:
		return
	root = Node3D.new()
	root.name = "RoadblockFlares"
	var side := 1.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		# Across the road: the road runs along the car's x, so that is where traffic comes from.
		var rel := car.global_basis.inverse() * (player.global_position - car.global_position)
		side = signf(rel.x) if absf(rel.x) > 0.1 else 1.0
	var smoke := not OS.has_feature("web") and budget > 0
	var lift := car.road_lift()
	for k in flare_count:
		var f := FreewayIncidentKit.flare_node(hash([car.flash_phase(), k, "rb_flare"]), smoke)
		var along := (float(k) - float(flare_count - 1) * 0.5) * 2.4
		# A shallow vee across the road, its point toward the trouble.
		f.position = Vector3(side * (flare_out + 2.2 - 0.55 * absf(along)), -lift + 0.02, along)
		f.rotation.y = 0.7 * float(k % 2) - 0.35
		root.add_child(f)
	car.add_child(root)


# --- Real lights -----------------------------------------------------------------------------

## Hands the budget's lights to the lit cruisers nearest the camera, keeping a car's light while it
## stays in the wanted set (no flicker from re-picking), fading a dropped one out.
func _pick(cars: Array, cam: Camera3D) -> void:
	var want: Array = []
	if supported() and cam != null and _night > 0.02 and budget > 0:
		var scored: Array = []
		for c in cars:
			var car := c as PoliceCar
			if car == null or not car.is_inside_tree() or not car.bar_lit():
				continue
			var d := cam.global_position.distance_to(car.global_position)
			if d > reach:
				continue
			# In front of the camera first: a light behind it lights little we see.
			var ahead := (-cam.global_basis.z).dot((car.global_position - cam.global_position).normalized())
			scored.append([d * (1.4 - 0.4 * ahead), car])
		scored.sort_custom(func(a, b): return a[0] < b[0])
		for i in mini(scored.size(), budget):
			want.append(scored[i][1])
	for slot in _lights:
		if slot[1] != null and not want.has(slot[1]):
			slot[1] = null
	for car in want:
		var have := false
		for slot in _lights:
			if slot[1] == car:
				have = true
				break
		if have:
			continue
		var free := -1
		for i in _lights.size():
			if _lights[i][1] == null:
				free = i
				break
		if free < 0 and _lights.size() < budget:
			_lights.append([_make_light(), null, 0.0])
			free = _lights.size() - 1
		if free >= 0:
			_lights[free][1] = car
	while _lights.size() > budget and _lights.back()[1] == null:
		(_lights.pop_back()[0] as Node).queue_free()


func _make_light() -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "PoliceStrobe"
	l.omni_range = light_range
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	l.light_specular = 1.0
	l.distance_fade_enabled = true
	l.distance_fade_begin = reach - 20.0
	l.distance_fade_length = 20.0
	l.visible = false
	add_child(l)
	return l


func _has_light(car: PoliceCar) -> bool:
	for slot in _lights:
		if slot[1] == car:
			return true
	return false


func _place_lights() -> void:
	var n := 0
	for slot in _lights:
		var l: OmniLight3D = slot[0]
		var car = slot[1]
		if car != null and (not is_instance_valid(car) or not (car as PoliceCar).is_inside_tree()):
			slot[1] = null
			car = null
		# Fade in on a hand-over, out when dropped (0.15 s), so a re-pick never pops.
		var target := 1.0 if car != null else 0.0
		slot[2] = move_toward(slot[2], target, get_process_delta_time() / 0.15)
		if slot[2] <= 0.001 or car == null:
			l.visible = false
			continue
		var pc := car as PoliceCar
		var side := pc.flash_side(clock)
		var bar := pc.get_node_or_null("LightBar") as Node3D
		var local := (bar.position if bar else Vector3(0.0, 1.5, 0.0)) + Vector3(-0.45 * float(side), 0.45, 0.0)
		l.global_position = pc.global_transform * local
		l.visible = side != 0
		if side == 0:
			continue
		n += 1
		l.light_color = Color(1.0, 0.07, 0.04) if side > 0 else Color(0.12, 0.32, 1.0)
		# Blue reads darker to the eye at the same energy: a little more of it.
		l.light_energy = light_energy * _night * slot[2] * (1.0 if side > 0 else 1.35)
	active_count = n


## Real lights handed to cars right now (checks).
func lit_cars() -> Array:
	var out: Array = []
	for slot in _lights:
		if slot[1] != null:
			out.append(slot[1])
	return out


func _lamp_level() -> float:
	return clampf(DayNight.lamp_now, 0.0, 1.0)


## Overridden by checks: the night level the washes and lights take.
func set_night(v: float) -> void:
	_night = v
	_night_t = 1e9


# --- Meshes ------------------------------------------------------------------------------------

## The bar's flares and streaks, in the bar's own frame: a quad per bank and kind, every vertex at
## the lens centre with the corner in UV (the shader spreads them toward the camera).
static func glow_mesh() -> ArrayMesh:
	if _glow_mesh != null:
		return _glow_mesh
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for bank in [0.5, 1.0]:
		var c := Vector3(-0.31 if bank < 0.75 else 0.31, 0.115, 0.0)
		for kind in [0.0, 3.0]:
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				verts.append(c)
				uvs.append(corner)
				cols.append(Color(bank, 0.0, 0.0, kind / 4.0))
	_glow_mesh = _mesh(verts, cols, uvs)
	return _glow_mesh


## The pool: a 1 x 1 quad in XZ, UV = (x, z) + 0.5, laid on the road and scaled by the node.
static func pool_mesh() -> ArrayMesh:
	if _pool_mesh != null:
		return _pool_mesh
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	# Godot's front faces wind clockwise seen from the front: from above, (0,0)->(1,1)->(1,0).
	for p in [Vector2(-0.5, -0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		verts.append(Vector3(p.x, 0.0, p.y))
		uvs.append(p + Vector2(0.5, 0.5))
		cols.append(Color(0.0, 0.0, 0.0, 1.0 / 4.0))
	_pool_mesh = _mesh(verts, cols, uvs)
	return _pool_mesh


## A wall wash: a 1 x 1 quad in XY facing +Z (the wall's normal), centred; `blue` the car's +x side.
static func wall_mesh(blue: bool) -> ArrayMesh:
	var cached: ArrayMesh = _wall_mesh_b if blue else _wall_mesh
	if cached != null:
		return cached
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for p in [Vector2(-0.5, -0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		verts.append(Vector3(p.x, p.y, 0.0))
		uvs.append(p + Vector2(0.5, 0.5))
		cols.append(Color(1.0 if blue else 0.5, 0.0, 0.0, 2.0 / 4.0))
	var m := _mesh(verts, cols, uvs)
	if blue:
		_wall_mesh_b = m
	else:
		_wall_mesh = m
	return m


static func _mesh(verts: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
