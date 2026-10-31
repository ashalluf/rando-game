class_name ContactShadows
extends Node
## The occlusion a car or a loose prop leaves on the ground under it (docs/HANDOFF.md, "Grounded
## light"). GTA's cars sit on the street because the ground under them is dark - the sky they
## hide - and darkest under the tyres. Forward+'s SSAO finds some of it at HIGH and MEDIUM, but
## it is a screen-space effect that loses the hidden underside, and the Compatibility renderer
## (the web, every opengl3 still) has no SSAO at all: there a parked car floated on the asphalt.
##
## One MultiMesh of flat quads (shaders/contact_shadow.gdshader: a soft rounded footprint and a
## blob per wheel, drawn as a darkening), one draw for every object near the camera, on BOTH
## renderers. One node under the tree root, made by the first Vehicle like CarLights; it writes
## TRUE global transforms from the objects every frame, so origin shifts do not touch it. Every
## `pick_seconds` it picks the `budget` nearest cars (group "vehicle") and loose props (group
## "physics_prop") within `reach` of the camera. A car's quad lies in its own contact plane
## (_dims() "road"), tilted with it; it fades out when the car leaves the ground (no wheel in
## contact on a physics car), rolls over, or nears `reach`. A prop's is its AABB's footprint at
## its lowest point, faded by how far its up axis leans.
## CONTACT_SHADOWS=0 (or GI_REVIEW=0) is the A/B.

## Grown past the footprint on every side (m), a car's and a prop's (in COLOR.r for the shader).
const MARGIN := 0.45
const PROP_MARGIN := 0.22
## Static street furniture batches that get a quad each (MultiMeshBatch.build() -> batch_contacts(),
## one "BatchContact" MultiMesh a chunk), key -> strength. Trash cans are physics props (the
## dynamic set); poles, lamps and signs stand on too small a foot to show one.
const CONTACT_KEYS := {
	"bench": 0.85, "planter": 0.8, "mailbox": 0.8, "sc_newsbox": 0.75, "cafe_set": 0.7,
	"hydrant": 0.6, "hydrant_aged": 0.6, "meter": 0.4, "rack": 0.45,
}
## How far a chunk's prop quads draw (m, past its bounds' half diagonal).
const PROP_DRAW := 70.0
## Off the ground (m), under the lowest paint (road_paint sits 1.5 cm up).
const LIFT := 0.03

static var enabled: bool = OS.get_environment("CONTACT_SHADOWS") != "0" and OS.get_environment("GI_REVIEW") != "0"
## How many quads at most, and how far from the camera (m).
static var budget: int = 48
static var reach: float = 70.0
## Seconds between re-picking who gets one.
static var pick_seconds: float = 0.25
## Strength where Forward+'s SDFGI and SSAO both occlude the sky under a car (HIGH), where only
## SSAO does (MEDIUM, LOW: the sky fill is otherwise unoccluded, the measured shade under a car
## 42 against HIGH's 18), and where nothing does (Compatibility, LOWEST).
static var gain_with_sdfgi: float = 0.55
static var gain_with_ssao: float = 0.9
static var gain_without_ssao: float = 1.0
static var _inst: ContactShadows
static var _prop_mat: ShaderMaterial

var _mmi: MultiMeshInstance3D
var _mm: MultiMesh
var _picked: Array = [] # each [Node3D, kind: 0 car / 1 prop, info: Vector4]
var _pick_t: float = 0.0
var _gain: float = 1.0


## Makes the one instance, the first time a car or prop enters the tree.
static func ensure(from: Node) -> void:
	if not enabled:
		return
	if _inst != null and is_instance_valid(_inst):
		return
	var tree := from.get_tree()
	if tree == null:
		return
	_inst = ContactShadows.new()
	_inst.name = "ContactShadows"
	tree.root.add_child.call_deferred(_inst)


static func instance() -> ContactShadows:
	return _inst if _inst != null and is_instance_valid(_inst) else null


static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/contact_shadow.gdshader")
	m.render_priority = -2
	return m


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	_mm.mesh = quad
	_mm.instance_count = budget
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "ContactQuads"
	_mmi.multimesh = _mm
	_mmi.material_override = material()
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mmi)


func _exit_tree() -> void:
	if _inst == self:
		_inst = null


## The renderer's own occlusion: SDFGI and SSAO on (Forward+) take the quads down.
func _renderer_gain() -> float:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return gain_without_ssao
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	var env: Environment = cam.environment if cam and cam.environment else null
	if env == null and vp and vp.world_3d:
		env = vp.world_3d.environment if vp.world_3d.environment else vp.world_3d.fallback_environment
	if env == null or not env.ssao_enabled:
		return gain_without_ssao
	return gain_with_sdfgi if env.sdfgi_enabled else gain_with_ssao


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		_mm.visible_instance_count = 0
		return
	var eye := cam.global_position
	_pick_t -= delta
	if _pick_t <= 0.0:
		_pick_t = pick_seconds
		_pick(eye)
		_gain = _renderer_gain()
		prop_material().set_shader_parameter("gain", _gain)
	var n := 0
	for e in _picked:
		# Never cast before checking: a freed object cannot be cast (a car pooled or a prop
		# despawned since the last pick).
		if not is_instance_valid(e[0]):
			continue
		var o := e[0] as Node3D
		if o == null or not o.is_inside_tree():
			continue
		var info: Vector4 = e[2]
		var xf := o.global_transform
		var up := xf.basis.y.normalized()
		var lean := clampf((up.y - 0.55) / 0.35, 0.0, 1.0)
		var s := lean * _gain
		s *= 1.0 - smoothstep(reach * 0.75, reach, eye.distance_to(xf.origin))
		if int(e[1]) == 0:
			s *= _grounded(o)
		if s <= 0.01:
			continue
		var b := xf.basis.orthonormalized()
		var foot := xf.origin + b.y * (float(e[3]) + LIFT)
		var mg := MARGIN if int(e[1]) == 0 else PROP_MARGIN
		var basis := Basis(b.x * (info.y + 2.0 * mg), b.y, b.z * (info.x + 2.0 * mg))
		_mm.set_instance_transform(n, Transform3D(basis, foot))
		_mm.set_instance_custom_data(n, Color(info.x, info.y, info.z, info.w))
		_mm.set_instance_color(n, Color(mg, 1, 1, s))
		n += 1
		if n >= budget:
			break
	_mm.visible_instance_count = n
	# Instances are in global space and the node sits at the origin: the bounds go round the eye.
	_mmi.custom_aabb = AABB(eye - Vector3.ONE * (reach + 10.0), Vector3.ONE * (reach + 10.0) * 2.0)


## 0 while a physics car has no wheel on the ground (a jump, a flight), 1 otherwise. A kinematic
## traffic car has no wheels and is always on the road.
func _grounded(car: Node3D) -> float:
	var any := false
	var touching := false
	for c in car.get_children():
		if c is VehicleWheel3D:
			any = true
			if (c as VehicleWheel3D).is_in_contact():
				touching = true
				break
	if not any:
		# No wheels: a kinematic traffic car (on the road by construction) or something that
		# flies or floats (helicopters, jets, boats), which gets none.
		var t: Variant = car.get("traffic")
		return 1.0 if t is Dictionary and not (t as Dictionary).is_empty() else 0.0
	return 1.0 if touching else 0.0


func _pick(eye: Vector3) -> void:
	var found: Array = []
	var r2 := reach * reach
	for c in get_tree().get_nodes_in_group("vehicle"):
		var v := c as Node3D
		if v == null or not v.is_inside_tree() or not v.visible:
			continue
		var d2 := eye.distance_squared_to(v.global_position)
		if d2 < r2:
			found.append([d2, v, 0])
	for c in get_tree().get_nodes_in_group("physics_prop"):
		var p := c as Node3D
		if p == null or not p.is_inside_tree() or not p.visible or p.is_in_group("vehicle"):
			continue
		var d2 := eye.distance_squared_to(p.global_position)
		if d2 < r2 * 0.36:
			found.append([d2, p, 1])
	found.sort_custom(func(a, b): return a[0] < b[0])
	_picked.clear()
	for f in found:
		if _picked.size() >= budget:
			break
		var info := _info(f[1], int(f[2]))
		if info.is_empty():
			continue
		_picked.append([f[1], f[2], info[0], info[1]])


## [Vector4(length, width, track, axle half spacing), contact height in the object's frame].
## Cached on the object (meta "contact_info"): a body's footprint does not change.
static func _info(o: Node3D, kind: int) -> Array:
	if o.has_meta("contact_info"):
		return o.get_meta("contact_info")
	var out: Array = []
	if kind == 0:
		if not o.has_method("_dims"):
			return out
		var d: Dictionary = o.call("_dims")
		var wz: float = float(d.get("wheel_z", 1.3))
		var axle := (float(d.get("wheel_front", wz)) + float(d.get("wheel_rear", wz))) * 0.5
		out = [Vector4(float(d.get("length", 4.6)), float(d.get("width", 1.9)), float(d.get("track", 1.6)), axle),
			float(d.get("road", d.get("ride", -0.3)))]
	else:
		var box := _local_aabb(o)
		if box.size.x < 0.05 or box.size.z < 0.05 or box.size.x > 6.0 or box.size.z > 6.0:
			o.set_meta("contact_info", [])
			return []
		out = [Vector4(box.size.z * 0.8, box.size.x * 0.8, 0.0, 0.0), box.position.y]
	o.set_meta("contact_info", out)
	return out


## The union of a prop's meshes' boxes in its own frame.
static func _local_aabb(o: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var inv := o.global_transform.affine_inverse()
	for c in o.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		var b := (inv * vi.global_transform) * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## The street furniture's quads share one material, its `gain` set by the instance with the cars'.
static func prop_material() -> ShaderMaterial:
	if _prop_mat == null:
		_prop_mat = material()
	return _prop_mat


## A quad under every instance of the CONTACT_KEYS batches MultiMeshBatch.build() just made, all
## in one MultiMesh under `parent` ("BatchContact"); each batch node remembers where its quads
## start (meta "contact_twin" / "contact_base") so hide_instance() takes a broken prop's quad too.
static func batch_contacts(batches: Dictionary, nodes: Dictionary, parent: Node3D) -> void:
	if not enabled or parent == null:
		return
	var xfs: Array = []
	var cols: Array = []
	var cus: Array = []
	var bases: Array = []
	for key: String in CONTACT_KEYS:
		if not batches.has(key) or not nodes.has(key):
			continue
		var batch: Dictionary = batches[key]
		var box: AABB = (batch.mesh as Mesh).get_aabb()
		if box.size.x <= 0.0 or box.size.z <= 0.0:
			continue
		bases.append([nodes[key], xfs.size()])
		var c := box.get_center()
		for x: Transform3D in batch.xforms:
			var sc := x.basis.get_scale()
			var w := box.size.x * sc.x
			var l := box.size.z * sc.z
			if sc.x < 0.001 or w > 6.0 or l > 6.0:
				xfs.append(Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -10000.0, 0.0)))
			else:
				var b := x.basis.orthonormalized()
				var foot := x * Vector3(c.x, box.position.y, c.z) + b.y * LIFT
				xfs.append(Transform3D(Basis(b.x * (w + 2.0 * PROP_MARGIN), b.y, b.z * (l + 2.0 * PROP_MARGIN)), foot))
			cols.append(Color(PROP_MARGIN, 1.0, 1.0, float(CONTACT_KEYS[key])))
			cus.append(Color(l, w, 0.0, 0.0))
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = xfs.size()
	var bounds := AABB()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
		mm.set_instance_custom_data(i, cus[i])
		var o: Vector3 = (xfs[i] as Transform3D).origin
		if o.y > -9000.0:
			bounds = AABB(o, Vector3.ZERO) if bounds.size == Vector3.ZERO and bounds.position == Vector3.ZERO else bounds.expand(o)
	var node := MultiMeshInstance3D.new()
	node.name = "BatchContact"
	node.multimesh = mm
	node.material_override = prop_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.visibility_range_end = PROP_DRAW + bounds.size.length() * 0.5
	node.visibility_range_end_margin = 10.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(node)
	for e in bases:
		(e[0] as Node).set_meta("contact_twin", node)
		(e[0] as Node).set_meta("contact_base", int(e[1]))


static func hide_contact(node: MultiMeshInstance3D, index: int) -> void:
	if node == null or not node.has_meta("contact_twin"):
		return
	var twin := node.get_meta("contact_twin") as MultiMeshInstance3D
	var i := int(node.get_meta("contact_base")) + index
	if twin and is_instance_valid(twin) and i < twin.multimesh.instance_count:
		twin.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -10000.0, 0.0)))
