class_name BoatSea
extends RefCounted
## The player's boats (Boat) on the sea's own surface (rc5-speedboat, docs/HANDOFF.md "The
## speedboat at golden hour"): a boat under way hands its wake to the ocean shader the way
## OceanTraffic's vessels do (ocean.gdshader wake_a / wake_b: the prop wash off the transom, the
## Kelvin arms and bow wave, the churn where the hull meets the water, the slick behind it). Before
## this a SALTRUNNER at 60 km/h left nothing on the water but a few particle quads.
##
## OceanTraffic.push_wakes() merges `entries()` into its list (nearest first, boats and vessels
## together); with OceanTraffic off (OCEAN_TRAFFIC=0) the first boat's BoatWake pushes them alone
## (`push_alone()`). BOAT_SEA=0 is the A/B (no boat wakes on the water).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("BOAT_SEA") != "0"
## Boats register here (Boat._ready / _exit_tree): no group walk a tick.
static var boats: Array = []
## Under this horizontal speed (m/s) a boat leaves no wake on the water (a moored boat bobs).
const MIN_SPEED := 0.8
## A boat's wake strength (ocean.gdshader: 0..1, the prop wash and arms scale with it).
const STRENGTH := [1.0, 0.75]
## Trail length: metres per m/s of speed plus hull lengths (OceanTraffic's rule), and its cap.
const TRAIL_PER_SPEED := 22.0
const TRAIL_MAX := 520.0
## ocean.gdshader's wake_glow while BoatSea is on (the wakes' foam lit by the horizon and a low sun).
const GLOW := 1.0
static var _alone_frame: int = -1


## The ocean material's share of BoatSea (OceanTraffic.push_wakes() and push_alone() call it).
static func apply(mat: ShaderMaterial) -> void:
	if mat:
		mat.set_shader_parameter("wake_glow", GLOW if enabled else 0.0)


static func add(b: Node) -> void:
	if not boats.has(b):
		boats.append(b)


static func remove(b: Node) -> void:
	boats.erase(b)


## The wake of each boat under way within `reach` of `cam` (TRUE world): [distance, wake_a, wake_b]
## in ocean.gdshader's packing.
static func entries(cam: Vector3, reach: float) -> Array:
	var out: Array = []
	if not enabled:
		return out
	for b in boats:
		if not is_instance_valid(b) or not (b as Node).is_inside_tree():
			continue
		var e := entry(b)
		if e.is_empty():
			continue
		var w := WorldState.to_world((b as Node3D).global_position)
		var d := cam.distance_to(w)
		if d > reach:
			continue
		out.append([d, e[0], e[1]])
	return out


## One boat's [wake_a, wake_b], or [] when it leaves none (still, out of the water, sinking).
static func entry(b: Node) -> Array:
	var boat := b as Node3D
	if boat == null or bool(b.get("sinking")) or float(b.get("wet")) <= 0.0 or not b.call("on_sea"):
		return []
	var lv: Vector3 = b.get("linear_velocity")
	var sp := Vector2(lv.x, lv.z).length()
	if sp < MIN_SPEED:
		return []
	var kind := int(b.get("kind"))
	var s: Vector2 = BoatKit.SIZE[kind]
	var bz := boat.global_basis.z
	var head := Vector2(-bz.x, -bz.z)
	if head.length() < 0.01:
		return []
	head = head.normalized()
	var w := WorldState.to_world(boat.global_position)
	var bow := Vector2(w.x, w.z) + head * s.x * 0.5
	var trail := clampf(sp * TRAIL_PER_SPEED + s.x * 4.0, 40.0, TRAIL_MAX)
	var strength: float = STRENGTH[clampi(kind, 0, STRENGTH.size() - 1)]
	return [Vector4(bow.x, bow.y, head.x, head.y),
		Vector4(sp, s.y, trail, maxf(floorf(s.x * 0.96), 1.0) + clampf(strength, 0.0, 1.0) * 0.99)]


## OceanTraffic off: the boats' wakes alone, once a frame (any boat's BoatWake may call it).
static func push_alone(tree: SceneTree) -> void:
	if not enabled or tree == null:
		return
	var f := Engine.get_physics_frames()
	if f == _alone_frame:
		return
	_alone_frame = f
	for n in tree.get_nodes_in_group("ocean_traffic"):
		if bool(n.get("enabled")):
			return
	var mat := PropFactory.ocean_material()
	if mat == null:
		return
	var cam_node := tree.root.get_viewport().get_camera_3d()
	var cam := WorldState.to_world(cam_node.global_position) if cam_node else Vector3.ZERO
	var list := entries(cam, 3000.0)
	list.sort_custom(func(a: Array, c: Array) -> bool: return a[0] < c[0])
	var wa := PackedVector4Array()
	var wb := PackedVector4Array()
	wa.resize(16)
	wb.resize(16)
	var n := mini(list.size(), 16)
	for i in n:
		wa[i] = list[i][1]
		wb[i] = list[i][2]
	mat.set_shader_parameter("wake_a", wa)
	mat.set_shader_parameter("wake_b", wb)
	mat.set_shader_parameter("wake_count", n)
	apply(mat)


## The boat's name and home port in vinyl on the SALTRUNNER's transom (NEAR and MID levels):
## the transom was a bare white sheet, the one face a chase camera sees. Names are invented, one
## per hull graphic accent (BoatKit.mesh() is cached per accent).
const NAMES := ["NO WAKE ZONE", "REEL ESTATE", "KNOT ON CALL", "SEAS THE DAY", "SECOND WIND"]
const PORT := "RANDO CITY"


static func transom(acc: BoatMesh.Acc, h: BoatMesh.Hull, accent: int, ac: Color) -> void:
	if not enabled or acc.level == BoatMesh.Level.FAR:
		return
	var tz := BoatMesh._z(h, 0.0) + 0.006
	var top := BoatMesh._sheer(h, 0.0)
	var name: String = NAMES[absi(accent) % NAMES.size()]
	_letters(acc, name, 0.15, Vector3(0.0, top - 0.3, tz), 1.5, ac)
	_letters(acc, PORT, 0.065, Vector3(0.0, top - 0.46, tz), 0.9, BoatKit.DARK)
	# A pinstripe in the accent across the transom under the port, the hull graphic's colour.
	var hw := BoatMesh._half_beam(h, 0.0) * 0.86
	var y := top - 0.56
	acc.quad(Vector3(-hw, y, tz), Vector3(hw, y, tz), Vector3(hw, y + 0.025, tz), Vector3(-hw, y + 0.025, tz),
		ac, BoatMesh.Region.GELCOAT, Vector3(0.0, 0.0, 1.0))


static func _letters(acc: BoatMesh.Acc, text: String, height: float, at: Vector3, max_w: float, col: Color) -> void:
	var geo := FreewayKit.text_geo(text, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var k := minf(1.0, max_w / maxf(float(geo[2]), 0.001))
	for i in range(0, idx.size() - 2, 3):
		var a := verts[idx[i]]
		var b := verts[idx[i + 1]]
		var c := verts[idx[i + 2]]
		acc.tri(at + Vector3(a.x * k, a.y, 0.0), at + Vector3(b.x * k, b.y, 0.0), at + Vector3(c.x * k, c.y, 0.0),
			col, BoatMesh.Region.GELCOAT, Vector3(0.0, 0.0, 1.0))
