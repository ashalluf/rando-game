class_name PoolUnder
extends RefCounted
## Under the water of a hill home's pool (wave 8, refcam `pool_underwater`; docs/HANDOFF.md
## "Under the water of a hill home's pool"). The hillside pools were a water sheet painted with a
## make-believe tank (hill_pool.gdshader): from above that reads, but a swimmer who dived in found
## nothing under the sheet - the pad the pool is cut into is a solid box, seen from inside it is
## nothing at all, so the camera looked out at the hillside through the floor. Now:
##   - `build()` (one hook in HillHomeBuild._pool(), FULL chunks) lays the tank as real faces - the
##     floor and four walls facing in, the far wall of an infinity pool stopping under the surface
##     at the weir - on ONE material a pool (shaders/pool_tank.gdshader: glass mosaic, the
##     waterline band, the caustic net and the walls' shadows, lit by hand from the sun; the pad's
##     box would black it out in the shadow map). From above the opaque sheet hides it: the dry
##     view is exactly as before.
##   - the pool is registered (true world frame, rect, surface, floor, the house's boxes), and
##     `apply()` (from Swim._update_view(), while the camera is under) hands it to the underwater
##     pass (the veil stops where the water does) and to the surface's underside, which mirrors
##     the tank and shows the sky and the house through Snell's window (water_underside.gdshader),
##     with pool water's own clarity and colour.
## `POOL_UNDER=0` in the environment is the A/B (no tank, the old underside and veil).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("POOL_UNDER") != "0"

## Pool water seen from inside: its colour (linear), metres to half way into it, absorption per metre.
const WATER := Vector3(0.020, 0.150, 0.180)
const VISIBILITY := 26.0
const ABSORB := Vector3(0.22, 0.04, 0.03)
## The mosaic's colours (linear): light aqua glass chips, and a deep blue waterline band.
const TILES := [Vector3(0.30, 0.56, 0.62), Vector3(0.22, 0.46, 0.58), Vector3(0.34, 0.50, 0.50)]
const BAND := Vector3(0.025, 0.09, 0.16)
## The far wall of an infinity pool stops this far under the surface (pool_tank.gdshaderinc's copy).
const WEIR_DROP := 0.06

## Registered pools: node instance id -> Array of pool dictionaries.
static var _pools: Dictionary = {}
static var _shader: Shader = null


## The tank of the pool HillHomeBuild is building: `r` the pool in its frame, `wv1` where the water
## ends along v (the weir's outer edge on an infinity pool), `wy` the surface (true world).
static func build(b: HillHomeBuild, r: Rect2, inf: bool, wy: float, wv1: float) -> void:
	if not enabled or b == null or b.ch == null:
		return
	var ch: CityChunk = b.ch
	if ch.capturing or ch.level != CityChunk.Level.FULL:
		return
	var fy := wy - SwimWater.POOL_DEPTH
	var u0 := r.position.x
	var u1 := r.end.x
	var v0 := r.position.y
	var v1 := r.end.y
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3.UP
	var fu3 := Vector3(b.fu.x, 0.0, b.fu.y)
	var fv3 := Vector3(b.fv.x, 0.0, b.fv.y)
	var top := wy + 0.02
	# The floor (facing up) and the walls (facing in). The far wall of an infinity pool stops at the
	# weir, whose top runs out to the water's end.
	_quad(st, b.WY(u0, v0, fy), b.WY(u1, v0, fy), b.WY(u1, v1, fy), b.WY(u0, v1, fy), up)
	_quad(st, b.WY(u0, v0, fy), b.WY(u0, v0, top), b.WY(u1, v0, top), b.WY(u1, v0, fy), fv3)
	_quad(st, b.WY(u0, v0, fy), b.WY(u0, v1, fy), b.WY(u0, v1, top), b.WY(u0, v0, top), fu3)
	_quad(st, b.WY(u1, v0, fy), b.WY(u1, v0, top), b.WY(u1, v1, top), b.WY(u1, v1, fy), -fu3)
	if inf:
		var wt := wy - WEIR_DROP
		_quad(st, b.WY(u0, v1, fy), b.WY(u1, v1, fy), b.WY(u1, v1, wt), b.WY(u0, v1, wt), -fv3)
		_quad(st, b.WY(u0, v1, wt), b.WY(u1, v1, wt), b.WY(u1, wv1, wt), b.WY(u0, wv1, wt), up)
		# The side walls run on beside the weir, over it, to the water's end.
		_quad(st, b.WY(u0, v1, wt), b.WY(u0, wv1, wt), b.WY(u0, wv1, top), b.WY(u0, v1, top), fu3)
		_quad(st, b.WY(u1, v1, wt), b.WY(u1, v1, top), b.WY(u1, wv1, top), b.WY(u1, wv1, wt), -fu3)
	else:
		_quad(st, b.WY(u0, v1, fy), b.WY(u1, v1, fy), b.WY(u1, v1, top), b.WY(u0, v1, top), -fv3)
	var mi := MeshInstance3D.new()
	mi.name = "PoolTank"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Only a camera at the pool needs it (it hides under the sheet from anywhere else).
	mi.visibility_range_end = 60.0
	var pool := {
		"o": b.o, "fu": b.fu, "fv": b.fv,
		"rect": Vector4(u0, v0, u1, wv1 if inf else v1), "inner": Rect2(u0, v0, u1 - u0, v1 - v0),
		"surface": wy, "floor": fy, "weir": 1.0 if inf else 0.0,
		"seed": float(absi(hash([b.seed, "pool_under"])) % 997) / 997.0,
		"boxes": _house_boxes(b),
	}
	var mat := ShaderMaterial.new()
	mat.shader = shader()
	set_tank(mat, pool)
	mi.material_override = mat
	ch.add_child(mi)
	register(ch, pool)


## The house beside the pool: the ground-floor wings' boxes in the pool's frame (u, v, true world y),
## the two nearest the pool; glass share in min.w.
static func _house_boxes(b: HillHomeBuild) -> Array:
	var h: Dictionary = b.h
	var r: Rect2 = (h.pool as Dictionary).r
	var c := r.get_center()
	var list := []
	for w: Dictionary in h.wings:
		if absf(float(w.y)) > 0.5:
			continue
		var wr: Rect2 = w.r
		var d := Vector2(maxf(maxf(wr.position.x - c.x, c.x - wr.end.x), 0.0), maxf(maxf(wr.position.y - c.y, c.y - wr.end.y), 0.0)).length()
		var y0: float = b.top
		var y1: float = y0 + HouseKit.FLOOR_LIFT + float(int(w.get("storeys", 1))) * HouseKit.STOREY + 0.6
		var glass := 1.0 if not (w.glass as Array).is_empty() else 0.0
		list.append([d, Vector4(wr.position.x, wr.position.y, y0, glass), Vector4(wr.end.x, wr.end.y, y1, 0.0)])
	list.sort_custom(func(a: Array, bb: Array) -> bool: return float(a[0]) < float(bb[0]))
	var out := []
	for e: Array in list.slice(0, 2):
		out.append([e[1], e[2]])
	return out


static func shader() -> Shader:
	if _shader == null:
		_shader = load("res://shaders/pool_tank.gdshader")
	return _shader


## A quad a, b, c, d facing `n` (the winding turned to face it).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = tri[0]
		var p1: Vector3 = tri[1]
		var p2: Vector3 = tri[2]
		# Godot's front faces wind clockwise seen from the front.
		if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
			var t := p1
			p1 = p2
			p2 = t
		for p: Vector3 in [p0, p1, p2]:
			st.set_normal(n)
			st.add_vertex(p)


## The pool's numbers on a material that includes pool_tank.gdshaderinc.
static func set_tank(mat: ShaderMaterial, pool: Dictionary) -> void:
	mat.set_shader_parameter("pt_o", pool.o)
	mat.set_shader_parameter("pt_fu", pool.fu)
	mat.set_shader_parameter("pt_fv", pool.fv)
	mat.set_shader_parameter("pt_rect", pool.rect)
	mat.set_shader_parameter("pt_y", Vector2(float(pool.surface), float(pool.floor)))
	mat.set_shader_parameter("pt_weir", float(pool.weir))
	mat.set_shader_parameter("pt_absorb", ABSORB)
	var s: float = pool.seed
	mat.set_shader_parameter("pt_seed", s)
	mat.set_shader_parameter("pt_tile", TILES[int(s * 997.0) % TILES.size()])
	mat.set_shader_parameter("pt_band", BAND)


static func register(node: Node, pool: Dictionary) -> void:
	var id := node.get_instance_id()
	if not _pools.has(id):
		_pools[id] = []
		node.tree_exiting.connect(func() -> void: _pools.erase(id))
	(_pools[id] as Array).append(pool)


static func clear() -> void:
	_pools.clear()


static func count() -> int:
	var n := 0
	for k: int in _pools:
		n += (_pools[k] as Array).size()
	return n


## The registered pool whose water holds TRUE world point `p`, or {}.
static func at(p: Vector3) -> Dictionary:
	for k: int in _pools:
		for pool: Dictionary in _pools[k]:
			var d := Vector2(p.x, p.z) - (pool.o as Vector2)
			var u := d.dot(pool.fu)
			var v := d.dot(pool.fv)
			var r: Vector4 = pool.rect
			if u >= r.x - 0.05 and u <= r.z + 0.05 and v >= r.y - 0.05 and v <= r.w + 0.05 \
					and p.y <= float(pool.surface) + 0.05 and p.y >= float(pool.floor) - 0.3:
				return pool
	return {}


## Swim's view hook: the camera (TRUE world `cam_true`) is under water. In a registered pool its
## numbers go to the underside and the underwater pass; elsewhere both are put back to the old look.
## Returns true when the camera is in a pool.
static func apply(cam_true: Vector3, underside: ShaderMaterial, overlay: ShaderMaterial) -> bool:
	var pool := at(cam_true) if enabled else {}
	var on := not pool.is_empty()
	underside.set_shader_parameter("pt_on", 1.0 if on else 0.0)
	overlay.set_shader_parameter("pt_on", 1.0 if on else 0.0)
	if not on:
		overlay.set_shader_parameter("water_color", Vector3(0.010, 0.085, 0.085))
		overlay.set_shader_parameter("visibility", 9.0)
		overlay.set_shader_parameter("absorb", Vector3(0.30, 0.055, 0.045))
		return false
	set_tank(underside, pool)
	set_tank(overlay, pool)
	overlay.set_shader_parameter("pt_camera", cam_true)
	overlay.set_shader_parameter("water_color", WATER)
	overlay.set_shader_parameter("visibility", VISIBILITY)
	overlay.set_shader_parameter("absorb", ABSORB)
	underside.set_shader_parameter("pt_water", WATER)
	underside.set_shader_parameter("pt_visibility", VISIBILITY)
	var boxes: Array = pool.boxes
	for k in 2:
		var mn := Vector4.ZERO
		var mx := Vector4.ZERO
		if k < boxes.size():
			mn = boxes[k][0]
			mx = boxes[k][1]
		underside.set_shader_parameter("pt_box%d_min" % k, mn)
		underside.set_shader_parameter("pt_box%d_max" % k, mx)
	return true
