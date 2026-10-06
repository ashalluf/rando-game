class_name WingsuitFx
extends Node3D
## What the wingsuit looks like (scripts/player/wingsuit.gd owns the flying): the fabric and the
## wingtip vapour, built in code.
##
## The fabric is three membranes rebuilt from the hero's live bones every time his skeleton is
## posed (Skeleton3D.skeleton_updated, after HeroMotion's spread and the arm IK): an arm wing
## each side from the wrist along the arm to the shoulder, down the side of the body to the hip
## and the thigh, its trailing edge scalloped in from the wrist to the thigh; and a tail wing
## between the legs from the crotch to the ankles. Each is a grid (`GRID_U` x `GRID_V`) bowed out
## behind him by the air (`billow`), folded onto the body edge as `spread` falls, in one ArrayMesh
## of scene-space vertices (a top-level node), worn by shaders/wingsuit_fabric.gdshader: ripstop
## nylon in panels with stitched seams that billow between them, a signal-orange trailing edge, a
## flutter that grows with the airspeed. Under a quarter spread nothing is drawn.
##
## The vapour is two ribbons torn off the wingtips (the boost's trail, turned into wingtip
## vortices): the hands' positions sampled each physics tick in TRUE world space (origin shifts
## do not move them), drawn each frame as camera-facing strips that widen and fade with age on
## shaders/wingsuit_vapour.gdshader, thicker with speed and with the boost, dimmed at night.
## A skid sprays grit and drags a dust trail (world-space puffs on WeaponFX's smoke material).

## Grid of each membrane (along the edge it hangs from, and across it).
const GRID_U := 9
const GRID_V := 6
## How far each wing bows out behind him (m) at full spread, and how deep the trailing edge's
## scallop is (share of the chord).
@export var billow: float = 0.09
@export var scallop: float = 0.16
## Vapour: speed (m/s) it starts at and is full at, a point's life (s), its width at birth and at
## death (m), and its opacity at full.
@export var vapour_min: float = 32.0
@export var vapour_full: float = 80.0
@export var vapour_life: float = 1.3
@export var vapour_width: Vector2 = Vector2(0.05, 1.1)
@export var vapour_alpha: float = 0.32
## How bright the vapour is at full night (lit by the city).
@export var night_brightness: float = 0.22

## Most points a ribbon keeps (a physics tick each).
const RIBBON_POINTS := 90

var _skeleton: Skeleton3D
var _bones := {}
var _fabric: MeshInstance3D
var _fabric_mesh: ArrayMesh
var _fabric_mat: ShaderMaterial
var _ribbons: MeshInstance3D
var _ribbon_mesh: ImmediateMesh
var _vapour_mat: ShaderMaterial
## Per wingtip: Array of [true world position, age, strength].
var _trails: Array = [[], []]
var _spread := 0.0
var _speed := 0.0
var _dust: CPUParticles3D
var _grit: CPUParticles3D
var _day: Node
var _looked_for_day := false

static var _fabric_shared: ShaderMaterial
static var _vapour_shared: ShaderMaterial


static func fabric_material() -> ShaderMaterial:
	if _fabric_shared == null:
		_fabric_shared = ShaderMaterial.new()
		_fabric_shared.shader = preload("res://shaders/wingsuit_fabric.gdshader")
	return _fabric_shared


static func vapour_material() -> ShaderMaterial:
	if _vapour_shared == null:
		_vapour_shared = ShaderMaterial.new()
		_vapour_shared.shader = preload("res://shaders/wingsuit_vapour.gdshader")
	return _vapour_shared


func _ready() -> void:
	_fabric_mesh = ArrayMesh.new()
	_fabric = MeshInstance3D.new()
	_fabric.name = "Fabric"
	_fabric.top_level = true
	_fabric.mesh = _fabric_mesh
	_fabric_mat = fabric_material().duplicate() as ShaderMaterial
	_fabric.material_override = _fabric_mat
	_fabric.visible = false
	add_child(_fabric)
	_ribbon_mesh = ImmediateMesh.new()
	_ribbons = MeshInstance3D.new()
	_ribbons.name = "Vapour"
	_ribbons.top_level = true
	_ribbons.mesh = _ribbon_mesh
	_ribbons.material_override = vapour_material()
	_ribbons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbons.visible = false
	add_child(_ribbons)
	_dust = _puffs(48, 1.1, 0.9, 3.0, Color(0.42, 0.39, 0.35), 0.35)
	_dust.direction = Vector3.UP
	_dust.spread = 75.0
	_dust.initial_velocity_min = 1.5
	_dust.initial_velocity_max = 4.5
	_dust.gravity = Vector3(0.0, -1.0, 0.0)
	add_child(_dust)
	_grit = _puffs(26, 0.8, 0.5, 2.6, Color(0.4, 0.37, 0.33), 0.45)
	_grit.one_shot = true
	_grit.explosiveness = 0.9
	_grit.spread = 35.0
	_grit.initial_velocity_min = 6.0
	_grit.initial_velocity_max = 13.0
	_grit.damping_min = 6.0
	_grit.damping_max = 10.0
	_grit.gravity = Vector3(0.0, -6.0, 0.0)
	add_child(_grit)


## The spread (0..1), the player's velocity, and whether he is boosting. Every physics tick.
func drive(spread: float, velocity: Vector3, delta: float, boosting := false) -> void:
	_spread = spread
	_speed = velocity.length()
	if _skeleton == null:
		_find_skeleton()
	_fabric.visible = spread > 0.25 and _skeleton != null and is_visible_in_tree()
	if _fabric.visible:
		_fabric_mat.set_shader_parameter("flutter", clampf(_speed / 70.0, 0.0, 1.0) * spread)
	# The wingtips' trails.
	var k := clampf((_speed - vapour_min) / (vapour_full - vapour_min), 0.0, 1.0) * smoothstep(0.6, 1.0, spread)
	if boosting:
		k = minf(1.0, k + 0.35 * spread)
	var tips := _tips()
	for side in 2:
		var trail: Array = _trails[side]
		for p in trail:
			p[1] += delta
		while not trail.is_empty() and float(trail[0][1]) > vapour_life:
			trail.pop_front()
		if k > 0.01 and tips.size() == 2:
			trail.append([WorldState.to_world(tips[side]), 0.0, k])
		elif not trail.is_empty() and float(trail.back()[2]) > 0.0:
			# The ribbon ends: a last point at nothing, so the strip tapers off.
			trail.append([trail.back()[0], 0.0, 0.0])
		while trail.size() > RIBBON_POINTS:
			trail.pop_front()


## True while a ribbon is being laid.
func is_trailing() -> bool:
	for trail: Array in _trails:
		if not trail.is_empty() and float(trail.back()[2]) > 0.0:
			return true
	return false


## True while the fabric is drawn.
func fabric_shown() -> bool:
	return _fabric.visible


## The fabric's current mesh (tests).
func fabric_mesh() -> ArrayMesh:
	return _fabric_mesh


## Grit thrown ahead as a skid starts (`along`: the ground velocity).
func skid_burst(at: Vector3, along: Vector3) -> void:
	var dir := along.normalized() if along.length() > 0.5 else Vector3.FORWARD
	_grit.global_position = at + Vector3.UP * 0.2
	_grit.direction = (dir + Vector3.UP * 0.35).normalized()
	_grit.color = Color(_bright(), _bright(), _bright(), 1.0)
	_grit.restart()
	_grit.emitting = true


## The dust a skid drags (`k` 0 stops it).
func skid_dust(at: Vector3, k: float) -> void:
	_dust.emitting = k > 0.05
	_dust.global_position = at + Vector3.UP * 0.15
	var b := _bright()
	_dust.color = Color(b, b, b, clampf(k, 0.0, 1.0))


func _process(_delta: float) -> void:
	_draw_ribbons()


func _find_skeleton() -> void:
	var player := get_parent().get_parent() as Player if get_parent() else null
	if player == null or player.avatar == null:
		return
	_skeleton = player.avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton == null:
		return
	for b in ["LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
			"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot", "Hips", "Spine01"]:
		_bones[b] = _skeleton.find_bone(b)
	if _bones.values().has(-1):
		_skeleton = null
		return
	_skeleton.skeleton_updated.connect(_rebuild)


func _bone_at(name: String) -> Vector3:
	return _skeleton.to_global(_skeleton.get_bone_global_pose(_bones[name]).origin)


func _tips() -> Array:
	if _skeleton == null:
		return []
	var out := []
	for side in ["Left", "Right"]:
		var hand := _bone_at(side + "Hand")
		var fore := _bone_at(side + "ForeArm")
		# Past the wrist, where the fingertips are.
		out.append(hand + (hand - fore).normalized() * 0.16)
	return out


## The fabric, from the bones as posed this frame.
func _rebuild() -> void:
	if not _fabric.visible or _skeleton == null:
		return
	var front := (_skeleton.global_basis.orthonormalized() * Vector3.BACK).normalized()
	var hips := _bone_at("Hips")
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var s := smoothstep(0.25, 1.0, _spread)
	for side in ["Left", "Right"]:
		var shoulder := _bone_at(side + "Arm")
		var elbow := _bone_at(side + "ForeArm")
		var wrist := _bone_at(side + "Hand")
		var hip := _bone_at(side + "UpLeg")
		var knee := _bone_at(side + "Leg")
		var out := (hip - hips)
		out = (out - front * out.dot(front)).normalized()
		var hip_side := hip + out * 0.08
		var thigh := hip.lerp(knee, 0.5) + out * 0.06
		# Leading edge: shoulder - elbow - wrist (the sleeve); body edge: shoulder - hip - thigh.
		var lead := func(u: float) -> Vector3:
			return shoulder.lerp(elbow, u * 2.0) if u < 0.5 else elbow.lerp(wrist, u * 2.0 - 1.0)
		var body := func(v: float) -> Vector3:
			return shoulder.lerp(hip_side, v / 0.7) if v < 0.7 else hip_side.lerp(thigh, (v - 0.7) / 0.3)
		_grid(verts, normals, tangents, uvs, uv2s, idx, front, s, 0.0,
			func(u: float, v: float) -> Vector3:
				# Bilinear between the sleeve (v 0) and the trailing edge (v 1, from the thigh to
				# just inside the wrist), folded onto the body edge as the spread closes.
				var a: Vector3 = lead.call(u)
				var tail_end: Vector3 = wrist.lerp(thigh, 0.12)
				var tail: Vector3 = thigh.lerp(tail_end, u)
				var b: Vector3 = body.call(v)
				var p := a.lerp(tail, v)
				# Coons blend so the u = 0 edge runs down the body, not straight to the thigh.
				p += (b - shoulder.lerp(thigh, v)) * (1.0 - u)
				# The scallop pulls the trailing edge in toward the shoulder.
				p = p.lerp(shoulder.lerp(wrist, u * 0.7), scallop * sin(PI * u) * v * v)
				return p)
	# The tail wing: crotch to ankles.
	var lh := _bone_at("LeftUpLeg")
	var rh := _bone_at("RightUpLeg")
	var crotch := lh.lerp(rh, 0.5) + (_bone_at("Spine01") - hips).normalized() * -0.08
	var legs := []
	for side in ["Left", "Right"]:
		legs.append([_bone_at(side + "UpLeg").lerp(_bone_at(side + "Leg"), 0.2), _bone_at(side + "Leg"), _bone_at(side + "Foot")])
	_grid(verts, normals, tangents, uvs, uv2s, idx, front, s, 1.0,
		func(u: float, v: float) -> Vector3:
			var lp: Vector3 = legs[0][0].lerp(legs[0][1], v * 2.0) if v < 0.5 else legs[0][1].lerp(legs[0][2], v * 2.0 - 1.0)
			var rp: Vector3 = legs[1][0].lerp(legs[1][1], v * 2.0) if v < 0.5 else legs[1][1].lerp(legs[1][2], v * 2.0 - 1.0)
			var p := lp.lerp(rp, u)
			# Up into the crotch at the top, scalloped in at the ankles.
			p = p.lerp(crotch, (1.0 - v) * (1.0 - v) * 0.6 * sin(PI * u))
			var mid := lp.lerp(rp, 0.5)
			p = p.lerp(crotch.lerp(mid, 0.6), scallop * 1.4 * sin(PI * u) * v * v * v)
			return p)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	_fabric_mesh.clear_surfaces()
	_fabric_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## One membrane: `shape(u, v)` over a GRID_U x GRID_V grid; u 0..1 along it, folded to the u = 0
## edge by the spread `s`; bowed out behind him (-front) by `billow`. UV in metres, UV2 (u, v)
## 0..1 with 2 added to v for the tail wing (`kind` 1).
func _grid(verts: PackedVector3Array, normals: PackedVector3Array, tangents: PackedFloat32Array,
		uvs: PackedVector2Array, uv2s: PackedVector2Array, idx: PackedInt32Array, front: Vector3,
		s: float, kind: float, shape: Callable) -> void:
	var base := verts.size()
	var pts := []
	for j in GRID_V + 1:
		var v := float(j) / GRID_V
		for i in GRID_U + 1:
			var u := float(i) / GRID_U
			var uu := u * s if kind == 0.0 else lerpf(0.5, u, s)
			var p: Vector3 = shape.call(uu, v)
			p -= front * billow * s * sin(PI * minf(uu * 1.2, 1.0)) * sin(PI * v * 0.9 + 0.1)
			pts.append(p)
	for j in GRID_V + 1:
		var acc_u := 0.0
		for i in GRID_U + 1:
			var k := j * (GRID_U + 1) + i
			var p: Vector3 = pts[k]
			var pu: Vector3 = pts[k + 1] - p if i < GRID_U else p - pts[k - 1]
			var pv: Vector3 = pts[k + GRID_U + 1] - p if j < GRID_V else p - pts[k - GRID_U - 1]
			var n := pu.cross(pv)
			n = n.normalized() if n.length_squared() > 1e-12 else -front
			if n.dot(-front) < 0.0:
				n = -n
			var t := pu.normalized() if pu.length_squared() > 1e-12 else Vector3.RIGHT
			if i > 0:
				acc_u += (p - (pts[k - 1] as Vector3)).length()
			var acc_v := 0.0
			if j > 0:
				for jj in j:
					acc_v += ((pts[(jj + 1) * (GRID_U + 1) + i] as Vector3) - (pts[jj * (GRID_U + 1) + i] as Vector3)).length()
			verts.append(p)
			normals.append(n)
			tangents.append_array([t.x, t.y, t.z, 1.0])
			uvs.append(Vector2(acc_u, acc_v))
			uv2s.append(Vector2(float(i) / GRID_U, float(j) / GRID_V + kind * 2.0))
	for j in GRID_V:
		for i in GRID_U:
			var a := base + j * (GRID_U + 1) + i
			var b := a + 1
			var c := a + GRID_U + 1
			var d := c + 1
			idx.append_array([a, b, d, a, d, c])


## The vapour ribbons, camera-facing, from the trails' points.
func _draw_ribbons() -> void:
	_ribbon_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var any := false
	for trail: Array in _trails:
		if trail.size() >= 2:
			any = true
	_ribbons.visible = any and cam != null
	if not _ribbons.visible:
		return
	var eye := cam.global_position
	var b := _bright()
	for trail: Array in _trails:
		var n := trail.size()
		if n < 2:
			continue
		_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var along := 0.0
		for i in n:
			var p := WorldState.to_local(trail[i][0])
			var q := WorldState.to_local(trail[mini(i + 1, n - 1)][0]) if i < n - 1 else p
			var o := WorldState.to_local(trail[maxi(i - 1, 0)][0])
			var tan := (q - o)
			if tan.length_squared() < 1e-8:
				tan = Vector3.FORWARD
			var side := tan.cross(eye - p)
			side = side.normalized() if side.length_squared() > 1e-10 else Vector3.RIGHT
			var age: float = trail[i][1] / vapour_life
			var w := lerpf(vapour_width.x, vapour_width.y, sqrt(age))
			var a: float = float(trail[i][2]) * vapour_alpha * (1.0 - age) * (1.0 - age) * smoothstep(0.0, 0.04, age + 0.01)
			if i == n - 1:
				a = 0.0
			if i > 0:
				along += p.distance_to(WorldState.to_local(trail[i - 1][0]))
			var col := Color(b, b, b, a)
			_ribbon_mesh.surface_set_color(col)
			_ribbon_mesh.surface_set_uv(Vector2(-1.0, along))
			_ribbon_mesh.surface_add_vertex(p - side * w)
			_ribbon_mesh.surface_set_color(col)
			_ribbon_mesh.surface_set_uv(Vector2(1.0, along))
			_ribbon_mesh.surface_add_vertex(p + side * w)
		_ribbon_mesh.surface_end()


func _bright() -> float:
	if not _looked_for_day:
		_looked_for_day = true
		var scene := get_tree().current_scene if is_inside_tree() else null
		_day = scene.get_node_or_null("DayNight") if scene else null
	var night := float(_day.get("night_factor")) if _day != null and is_instance_valid(_day) else 0.0
	return lerpf(1.0, night_brightness, night)


func _puffs(count: int, life: float, size: float, grow: float, color: Color, alpha: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = count
	p.lifetime = life
	p.lifetime_randomness = 0.3
	p.local_coords = false
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	# Curve values are clamped to max_value (1.0 by default): raise it or the puffs never grow.
	var curve := Curve.new()
	curve.max_value = maxf(1.0, grow)
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, grow))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(color.r, color.g, color.b, 0.0))
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	g.add_point(0.08, Color(color.r, color.g, color.b, alpha))
	g.add_point(0.5, Color(color.r, color.g, color.b, alpha * 0.5))
	p.color_ramp = g
	p.angle_min = -180.0
	p.angle_max = 180.0
	var quad := QuadMesh.new()
	quad.material = WeaponFX.smoke_material()
	p.mesh = quad
	p.custom_aabb = AABB(Vector3(-40.0, -10.0, -40.0), Vector3(80.0, 20.0, 80.0))
	return p
