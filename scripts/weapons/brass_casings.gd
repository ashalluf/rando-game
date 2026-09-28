class_name BrassCasings
extends MultiMeshInstance3D
## Spent brass from the rifle: every round throws a case out of the ejection port to the right,
## tumbling end over end; it bounces once or twice on whatever is under it with a tink, lies
## where it stopped for `rest_seconds` and shrinks away. A 7.62 x 39 case is 39 mm long, so from
## the chase camera it is a glint of gold streaming off the gun - which is exactly the detail a
## sustained burst reads as real by.
##
## One MultiMesh for every case in the scene, simulated here (a gravity arc, one ground height
## ray per case when it is thrown, a bounce, a roll to rest) rather than as rigid bodies: the rifle
## fires ten a second, and ten physics bodies a second is not what a cartridge case is worth.
## The node lives under the scene root, so the origin re-centre shifts it with everything else.

## How many cases can be in the world at once (the oldest is reused past this).
@export var max_cases: int = 48
## Seconds a case lies on the ground before it shrinks away.
@export var rest_seconds: float = 6.0
## Share of its speed a case keeps up off a bounce, and along the ground.
@export var bounce: float = 0.32
@export var ground_friction: float = 0.55

const RADIUS := 0.0056
const LENGTH := 0.039

static var _pool: BrassCasings

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _spin := PackedVector3Array()
var _ground := PackedFloat32Array()
var _age := PackedFloat32Array()
## 0 free, 1 flying, 2 resting.
var _state := PackedInt32Array()
var _next: int = 0
var _live: int = 0
## The instance buffer, written on the CPU and handed over whole each frame (12 floats a case):
## per-instance set_instance_transform() makes the renderer read the buffer back first.
var _buf := PackedFloat32Array()


## Throws one case from `port` (world), `side` the gun's right, `up` its up, `carry` the
## shooter's own velocity (a case thrown while boosting should not hang in the air behind).
static func eject(node: Node, port: Vector3, side: Vector3, up: Vector3, carry: Vector3) -> void:
	if node == null or not node.is_inside_tree():
		return
	if _pool == null or not is_instance_valid(_pool) or not _pool.is_inside_tree():
		_pool = BrassCasings.new()
		_pool.name = "BrassCasings"
		WeaponFX.fx_parent(node).add_child(_pool)
	_pool._throw(port, side, up, carry)


func _ready() -> void:
	if OS.has_feature("web"):
		max_cases = mini(max_cases, 24)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _case_mesh()
	mm.instance_count = max_cases
	_buf.resize(max_cases * 12)
	_buf.fill(0.0)
	mm.buffer = _buf
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cases are spread over wherever the player has been shooting; keep them all drawable.
	custom_aabb = AABB(Vector3(-4000.0, -500.0, -4000.0), Vector3(8000.0, 1000.0, 8000.0))
	for arr in [_pos, _vel, _axis, _spin]:
		arr.resize(max_cases)
	_ground.resize(max_cases)
	_age.resize(max_cases)
	_state.resize(max_cases)


func _throw(port: Vector3, side: Vector3, up: Vector3, carry: Vector3) -> void:
	var i := _next
	_next = (_next + 1) % max_cases
	if _state[i] == 0:
		_live += 1
	var local := to_local(port)
	_pos[i] = local
	# Out to the right and up, a little back; every case a little different.
	_vel[i] = carry + side * randf_range(2.6, 4.2) + up * randf_range(1.2, 2.2) \
		+ side.cross(up) * randf_range(-0.2, 0.6)
	_axis[i] = side.cross(up).normalized()
	_spin[i] = up * randf_range(-6.0, 6.0) + side * randf_range(18.0, 34.0)
	_age[i] = 0.0
	_state[i] = 1
	_ground[i] = local.y - 60.0
	var space := get_world_3d().direct_space_state
	if space:
		# Where it will come down: a metre out to the right, straight down from there.
		var from := port + side * 1.0 + Vector3.UP * 0.5
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0, 1))
		if not hit.is_empty():
			_ground[i] = to_local(hit.position).y + RADIUS
	set_process(true)


func _process(delta: float) -> void:
	if _live == 0:
		set_process(false)
		return
	var dt := minf(delta, 0.05)
	var mm := multimesh
	for i in max_cases:
		var s := _state[i]
		if s == 0:
			continue
		_age[i] += dt
		if s == 1:
			var v := _vel[i]
			v.y -= 9.8 * dt
			var p := _pos[i] + v * dt
			var a := _axis[i]
			var w := _spin[i]
			if w.length_squared() > 1e-6:
				a = a.rotated(w.normalized(), w.length() * dt).normalized()
			if p.y <= _ground[i]:
				p.y = _ground[i]
				if v.y < -0.9:
					# The first hit rings; later ones are softer.
					Sfx.play("casing", to_global(p), -14.0 if absf(v.y) > 2.0 else -20.0, randf_range(0.85, 1.25))
					v.y = -v.y * bounce
					v.x *= ground_friction
					v.z *= ground_friction
					w *= 0.5
				else:
					# Down: lie on its side, rolled a little along the ground.
					v = Vector3.ZERO
					a = Vector3(a.x, 0.0, a.z)
					a = a.normalized() if a.length_squared() > 1e-6 else Vector3.RIGHT
					s = 2
					_age[i] = 0.0
			elif _age[i] > 4.0:
				# Fell off the world or into the sea.
				s = 0
			_pos[i] = p
			_vel[i] = v
			_axis[i] = a
			_spin[i] = w
		var scale := 1.0
		if s == 2 and _age[i] > rest_seconds:
			scale = clampf(1.0 - (_age[i] - rest_seconds) / 0.6, 0.0, 1.0)
			if scale <= 0.0:
				s = 0
		_state[i] = s
		if s == 0:
			_live -= 1
			_write(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		_write(i, Transform3D(_basis_along(_axis[i]).scaled(Vector3.ONE * scale), _pos[i]))
	mm.buffer = _buf


func _write(i: int, t: Transform3D) -> void:
	var o := i * 12
	_buf[o] = t.basis.x.x
	_buf[o + 1] = t.basis.y.x
	_buf[o + 2] = t.basis.z.x
	_buf[o + 3] = t.origin.x
	_buf[o + 4] = t.basis.x.y
	_buf[o + 5] = t.basis.y.y
	_buf[o + 6] = t.basis.z.y
	_buf[o + 7] = t.origin.y
	_buf[o + 8] = t.basis.x.z
	_buf[o + 9] = t.basis.y.z
	_buf[o + 10] = t.basis.z.z
	_buf[o + 11] = t.origin.z


## A basis whose Y (the case's length) runs along `y`.
static func _basis_along(y: Vector3) -> Basis:
	var yy := y.normalized()
	var ref := Vector3.UP if absf(yy.y) < 0.95 else Vector3.RIGHT
	var x := ref.cross(yy).normalized()
	return Basis(x, yy, x.cross(yy))


static var _mesh_cache: Mesh

## A bottlenecked case: the body tapering to the shoulder, the neck, the rim; brass, a little
## worn. Twelve sides is plenty at 11 mm.
static func _case_mesh() -> Mesh:
	if _mesh_cache != null:
		return _mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	# (radius, height) up the case from the base.
	var ring := [Vector2(0.0, 0.0), Vector2(RADIUS, 0.0), Vector2(RADIUS, 0.0012), Vector2(RADIUS * 0.84, 0.0016),
		Vector2(RADIUS * 0.86, 0.0032), Vector2(RADIUS * 0.8, 0.029), Vector2(RADIUS * 0.6, 0.032),
		Vector2(RADIUS * 0.6, LENGTH), Vector2(0.0, LENGTH)]
	var sides := 12
	for k in ring.size() - 1:
		var a: Vector2 = ring[k]
		var b: Vector2 = ring[k + 1]
		for j in sides:
			var t0 := TAU * float(j) / sides
			var t1 := TAU * float(j + 1) / sides
			var p00 := Vector3(cos(t0) * a.x, a.y - LENGTH * 0.5, sin(t0) * a.x)
			var p01 := Vector3(cos(t1) * a.x, a.y - LENGTH * 0.5, sin(t1) * a.x)
			var p10 := Vector3(cos(t0) * b.x, b.y - LENGTH * 0.5, sin(t0) * b.x)
			var p11 := Vector3(cos(t1) * b.x, b.y - LENGTH * 0.5, sin(t1) * b.x)
			st.add_vertex(p00)
			st.add_vertex(p10)
			st.add_vertex(p11)
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p01)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.83, 0.62, 0.3)
	# Brass is a metal, but on the Compatibility renderer a metal has nothing to mirror and draws
	# near black; half metallic keeps the gold there and still glints on Forward+.
	mat.metallic = 0.55 if OS.has_feature("web") else 0.85
	mat.roughness = 0.28
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	_mesh_cache = mesh
	return mesh
