class_name EmergencyWash
extends RefCounted
## A fire engine's or an ambulance's warning lights at night on the street round it (wave 8,
## rc5-fire-station-night, docs/HANDOFF.md "The fire station at night"). The unit's lenses flashed
## (shaders/emergency_lights.gdshader) and one small OmniLight on the roof (desktop only, off the
## wall clock, 14 m) was all the light they threw: from across the street the engine was a toy
## with lit dots and the road and the walls round it stayed dark. Now each lit unit near the camera
## carries a `Wash` child: a pool on the road and a wash on the facade either side (two rays every
## `WALL_INTERVAL`), all on shaders/engine_wash.gdshader, flashing in step with the lenses because
## it works the flash out the same way (TIME, the unit's rate and phase). Every renderer, the web
## too: it is three additive quads. Called from EmergencyCar._process() (one hook line).
## EMERGENCY_WASH=0 in the environment is the A/B.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("EMERGENCY_WASH") != "0"
## Washes are drawn for units this close to the camera (m).
const REACH := 200.0
## The pool's size (m) and how far a facade may stand from the unit's side and still be washed (m).
const POOL_M := 30.0
const WALL_REACH := 24.0
const WALL_W := 30.0
const WALL_H := 12.0
const WALL_INTERVAL := 0.5

static var _pool_mesh: ArrayMesh = null
static var _wall_mesh: ArrayMesh = null


## Every frame for a unit: shows, places and hides its wash. `lit` its warning lights are running.
static func tick(car: EmergencyCar, lit: bool, delta: float) -> void:
	if not enabled:
		return
	var w := car.get_node_or_null("Wash") as Node3D
	var cam := car.get_viewport().get_camera_3d() if car.is_inside_tree() else null
	var night := clampf(car._night, 0.0, 1.0)
	var near := cam != null and cam.global_position.distance_to(car.global_position) < REACH
	if not (lit and near and night > 0.02):
		if w:
			w.visible = false
		return
	if w == null:
		w = _make(car)
	w.visible = true
	var fwd := car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.BACK
	var right := Vector3.UP.cross(fwd).normalized()
	var ground := car.global_position - car.global_basis.y * car.road_lift()
	var pool := w.get_node("Pool") as MeshInstance3D
	pool.global_transform = Transform3D(Basis(right * POOL_M, Vector3.UP, fwd * POOL_M), ground + Vector3.UP * 0.06)
	var real := 1.0 if car._light and car._light.visible else 0.0
	for k in 3:
		(w.get_meta("mats")[k] as ShaderMaterial).set_shader_parameter("real_light", real)
	var t := float(w.get_meta("wall_t", 0.0)) - delta
	if t <= 0.0:
		t = WALL_INTERVAL
		_place_walls(car, w, ground, right, fwd)
	w.set_meta("wall_t", t)


static func _make(car: EmergencyCar) -> Node3D:
	var w := Node3D.new()
	w.name = "Wash"
	var shader: Shader = load("res://shaders/engine_wash.gdshader")
	var dims: Dictionary = car._dims()
	var mats: Array = []
	for k in 3:
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("kind", 0.0 if k == 0 else 1.0)
		m.set_shader_parameter("rate", car.flash_rate)
		m.set_shader_parameter("phase", car._phase)
		m.set_shader_parameter("src_x", float(dims.get("width", 2.4)) * 0.5)
		m.set_shader_parameter("src_z", float(dims.length) * 0.4)
		m.set_shader_parameter("src_h", (car._model_top_y if car._has_model else 2.8) + 0.2)
		m.set_shader_parameter("quad_m", POOL_M if k == 0 else WALL_W)
		m.set_shader_parameter("wall_h", WALL_H)
		m.set_shader_parameter("wall_side", -1.0 if k == 1 else 1.0)
		if car.kind == EmergencyCar.Kind.AMBULANCE:
			m.set_shader_parameter("white", Vector3(2.4, 2.3, 2.2))
		mats.append(m)
	w.set_meta("mats", mats)
	for k in 3:
		var mi := MeshInstance3D.new()
		mi.name = ["Pool", "WallA", "WallB"][k]
		mi.mesh = _pool() if k == 0 else _wall()
		mi.material_override = mats[k]
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		mi.visible = k == 0
		w.add_child(mi)
	car.add_child(w)
	return w


## The facade either side: one ray out each way at lamp height; a wall found (upright) gets the
## wash quad on it, its middle level with the unit, its x along the unit's back (the shader's frame).
static func _place_walls(car: EmergencyCar, w: Node3D, ground: Vector3, right: Vector3, fwd: Vector3) -> void:
	var space := car.get_world_3d().direct_space_state
	var from := ground + Vector3.UP * 2.0
	var mats: Array = w.get_meta("mats")
	for k in 2:
		var wm := w.get_node("WallA" if k == 0 else "WallB") as MeshInstance3D
		var dir := -right if k == 0 else right
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * WALL_REACH, 1)
		q.exclude = [car.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.4:
			wm.visible = false
			continue
		var n: Vector3 = hit.normal
		n.y = 0.0
		n = n.normalized()
		var d := from.distance_to(hit.position)
		# x along the unit's back projected on the wall, y up, z the wall's normal.
		var t := (fwd - n * fwd.dot(n))
		t = t.normalized() if t.length() > 0.2 else Vector3.UP.cross(n).normalized()
		var at: Vector3 = hit.position + n * 0.06
		at.y = ground.y + WALL_H * 0.5
		wm.global_transform = Transform3D(Basis(t * WALL_W, Vector3.UP * WALL_H, n), at)
		(mats[k + 1] as ShaderMaterial).set_shader_parameter("wall_d", d)
		wm.visible = true


## A 1 x 1 quad in XZ, UV = (x, z) + 0.5 (front faces clockwise seen from above).
static func _pool() -> ArrayMesh:
	if _pool_mesh == null:
		_pool_mesh = _quad(false)
	return _pool_mesh


## A 1 x 1 quad in XY, its bottom at y -0.5 (UV.y 0) and top at 0.5.
static func _wall() -> ArrayMesh:
	if _wall_mesh == null:
		_wall_mesh = _quad(true)
	return _wall_mesh


static func _quad(upright: bool) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for p in [Vector2(-0.5, -0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		verts.append(Vector3(p.x, p.y, 0.0) if upright else Vector3(p.x, 0.0, p.y))
		uvs.append(p + Vector2(0.5, 0.5))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
