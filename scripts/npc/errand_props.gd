class_name ErrandProps
extends RefCounted
## The two things StreetErrands puts in people's hands or on cars, built in code at real size:
## a car's driver door that swings open (a panel in the car's own paint with its window frame,
## glass, door card and handle, hinged at its front edge on the driver's side), and a two-wheeled
## hand truck with a stack of cardboard boxes on its nose plate (or empty).
##
## The cars are one welded body model each with no door node, so the open door is a second panel
## swung out of the side: the closed door stays drawn under it, which from the pavement or behind
## the car reads as a door standing open (CLAUDE.md, Street errands). Shared meshes, one per body
## type and per load; one material per paint colour.

## How far a driver's door swings open (radians) and how long it takes (seconds).
const DOOR_SWING := 1.08
const DOOR_TIME := 0.85

static var _door_meshes: Dictionary = {}
static var _paints: Dictionary = {}
static var _trim: StandardMaterial3D
static var _glass: StandardMaterial3D
static var _truck_meshes: Dictionary = {}


## The driver's door of `car` (Vehicle), as a hinge node already placed on the car (a child of
## it, at the front edge of the door on the left, the side a left-hand-drive driver gets in), closed.
## Turn it with swing(node, 0..1).
static func door_node(car: Node3D) -> Node3D:
	var g := door_geometry(car)
	var hinge := Node3D.new()
	hinge.name = "ErrandDoor"
	hinge.position = g.hinge
	var mi := MeshInstance3D.new()
	mi.mesh = _door_mesh(g)
	mi.set_surface_override_material(0, paint_material(car.get("paint") as Color))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = 120.0
	hinge.add_child(mi)
	hinge.visible = false
	car.add_child(hinge)
	return hinge


## Opens the door `t` of the way (0 shut, 1 open), eased; shut, it is hidden (the body's own
## door is the closed door).
static func swing(hinge: Node3D, t: float) -> void:
	if hinge == null or not is_instance_valid(hinge):
		return
	var e := clampf(t, 0.0, 1.0)
	e = e * e * (3.0 - 2.0 * e)
	hinge.visible = e > 0.02
	hinge.basis = Basis(Vector3.UP, -DOOR_SWING * e)


## Where the driver's door is on `car` (car space: hinge point, length, sill, belt and top
## heights), from its body type's dimensions and the model's own bounds.
static func door_geometry(car: Node3D) -> Dictionary:
	var dims: Dictionary = car.call("_dims")
	var length := float(dims.get("length", 4.8))
	var width := float(dims.get("width", 1.84))
	var lo := 0.1
	var hi := 1.45
	var box := _body_bounds(car)
	if box.size.y > 0.5:
		lo = box.position.y
		hi = box.end.y
	var h := hi - lo
	var big := BigVehicles.is_big(int(car.get("body_type")))
	var cabin: Vector2 = dims.get("cabin", Vector2(-1.0, 2.4))
	var front := cabin.x + 0.08
	var door_len := clampf(cabin.y * 0.46, 0.92, 1.18)
	var sill := lo + 0.22 * h
	var belt := lo + 0.57 * h
	var top := lo + 0.9 * h
	if big:
		# A cab door, up behind the front wheel arch.
		front = -length * 0.5 + 0.62
		door_len = 1.0
		sill = lo + 0.62
		belt = lo + 1.55
		top = lo + 2.35
		h = top - lo
	elif int(car.get("body_type")) == Vehicle.BodyType.VAN:
		front = -length * 0.5 + 1.25
		door_len = 1.02
		sill = lo + 0.42
		belt = lo + 1.08
		top = lo + 1.62
	return {"hinge": Vector3(-width * 0.5 + 0.02, 0.0, front), "len": door_len, "sill": sill, "belt": belt,
		"top": top, "rake": 0.28 if not big else 0.08, "key": "%d_%d" % [int(car.get("body_type")), int(top * 100.0)]}


## The point on the road beside the open driver's door (car space), where a driver stands.
static func door_stand(car: Node3D, out: float = 0.75) -> Vector3:
	var g := door_geometry(car)
	return Vector3(g.hinge.x - out, 0.0, g.hinge.z + g.len * 0.62)


static func _body_bounds(car: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := car.global_transform.affine_inverse() if car.is_inside_tree() else Transform3D()
	var metas: Variant = car.get("_body_meshes")
	if not (metas is Array):
		return out
	for mi: MeshInstance3D in metas:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		var xf := (inv * mi.global_transform) if car.is_inside_tree() and mi.is_inside_tree() else mi.transform
		var b := xf * mi.mesh.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


static func paint_material(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html()
	if _paints.has(key):
		return _paints[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.metallic = 0.35
	m.roughness = 0.3
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.08
	_paints[key] = m
	return m


static func trim_material() -> StandardMaterial3D:
	if _trim == null:
		_trim = StandardMaterial3D.new()
		_trim.vertex_color_use_as_albedo = true
		_trim.vertex_color_is_srgb = true
		_trim.roughness = 0.55
	return _trim


static func glass_material() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.albedo_color = Color(0.05, 0.065, 0.075, 0.62)
		_glass.metallic = 0.4
		_glass.roughness = 0.04
		_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass


## The door in its hinge frame: the front edge on the hinge (the origin), running back along +Z,
## its outer skin facing -X. Three surfaces: paint, trim (frame, card, handle, seals), glass.
static func _door_mesh(g: Dictionary) -> ArrayMesh:
	if _door_meshes.has(g.key):
		return _door_meshes[g.key]
	var len: float = g.len
	var sill: float = g.sill
	var belt: float = g.belt
	var top: float = g.top
	var rake: float = g.rake
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := 0.075
	# The skin: below the belt, its lower edge tucked in, a crease along its middle.
	var mid := lerpf(sill, belt, 0.55)
	_box(paint, Vector3(-t * 0.5, (sill + mid) * 0.5, len * 0.5), Vector3(t, mid - sill, len), Color.WHITE)
	_box(paint, Vector3(-t * 0.5 + 0.006, (mid + belt) * 0.5, len * 0.5), Vector3(t - 0.012, belt - mid - 0.012, len - 0.01), Color.WHITE)
	_box(paint, Vector3(-t - 0.004, mid, len * 0.5), Vector3(0.012, 0.018, len - 0.06), Color.WHITE)
	# The window frame: an A-pillar post raked back, the top rail, the rear post (black trim).
	var black := Color(0.025, 0.025, 0.03)
	var a0 := Vector3(-0.03, belt, 0.02)
	var a1 := Vector3(-0.03, top, 0.02 + rake)
	var r1 := Vector3(-0.03, top, len - 0.04)
	var r0 := Vector3(-0.03, belt, len - 0.04)
	_beam(trim, a0, a1, 0.04, 0.05, black)
	_beam(trim, a1, r1, 0.04, 0.05, black)
	_beam(trim, r1, r0, 0.04, 0.05, black)
	_box(trim, Vector3(-0.03, belt + 0.012, len * 0.5), Vector3(0.05, 0.024, len - 0.02), black)
	# The pane, set in the frame.
	_quad(glass, Vector3(-0.03, belt + 0.02, 0.05), Vector3(-0.03, top - 0.025, 0.05 + rake - 0.02),
		Vector3(-0.03, top - 0.025, len - 0.07), Vector3(-0.03, belt + 0.02, len - 0.07), Vector3.LEFT)
	# The door card inside, its armrest and pull, and the handle outside.
	var card := Color(0.09, 0.09, 0.095)
	_box(trim, Vector3(0.008, (sill + belt) * 0.5 + 0.02, len * 0.5), Vector3(0.02, belt - sill - 0.03, len - 0.06), card)
	_box(trim, Vector3(0.04, lerpf(sill, belt, 0.62), len * 0.55), Vector3(0.07, 0.05, len * 0.55), Color(0.13, 0.12, 0.12))
	_box(trim, Vector3(-t - 0.012, belt - 0.07, len * 0.8), Vector3(0.022, 0.03, 0.16), Color(0.55, 0.56, 0.58))
	# A rubber seal along the shut face.
	_box(trim, Vector3(-0.02, (sill + belt) * 0.5, len - 0.004), Vector3(0.05, belt - sill, 0.012), Color(0.02, 0.02, 0.02))
	var mesh := paint.commit()
	trim.commit(mesh)
	glass.commit(mesh)
	mesh.surface_set_material(1, trim_material())
	mesh.surface_set_material(2, glass_material())
	_door_meshes[g.key] = mesh
	return mesh


## A hand truck (a two-wheeled dolly) with `boxes` cardboard boxes on it, in the pusher's frame:
## the wheels on the ground at the origin, the nose plate forward (-Z), leaned back toward the
## pusher (+Z) the way it is wheeled, its handle about a metre up and ~0.7 m back toward them.
static func hand_truck(boxes: int) -> Mesh:
	if _truck_meshes.has(boxes):
		return _truck_meshes[boxes]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Basis(Vector3.RIGHT, deg_to_rad(36.0))
	var steel := Color(0.16, 0.17, 0.18)
	var plate := Color(0.42, 0.43, 0.44)
	var rubber := Color(0.03, 0.03, 0.03)
	var hub := Color(0.62, 0.63, 0.62)
	# Built upright (rails up +Y, the nose plate forward -Z), then leaned back about the axle.
	var parts: Array = []
	for sx: float in [-0.2, 0.2]:
		parts.append(["beam", Vector3(sx, 0.06, 0.02), Vector3(sx, 1.24, 0.02), 0.03, steel])
		# The handle's curve back toward the pusher.
		parts.append(["beam", Vector3(sx, 1.24, 0.02), Vector3(sx * 0.9, 1.34, 0.1), 0.03, steel])
	parts.append(["beam", Vector3(-0.18, 1.34, 0.1), Vector3(0.18, 1.34, 0.1), 0.032, rubber])
	for y: float in [0.38, 0.72, 1.04]:
		parts.append(["beam", Vector3(-0.2, y, 0.02), Vector3(0.2, y, 0.02), 0.022, steel])
	# The nose plate and its gusset.
	parts.append(["box", Vector3(0.0, 0.02, -0.12), Vector3(0.46, 0.012, 0.26), plate])
	parts.append(["box", Vector3(0.0, 0.08, 0.0), Vector3(0.44, 0.12, 0.012), plate])
	# The axle and its wheel brackets.
	parts.append(["beam", Vector3(-0.27, 0.13, 0.12), Vector3(0.27, 0.13, 0.12), 0.016, steel])
	for sx: float in [-0.19, 0.19]:
		parts.append(["beam", Vector3(sx, 0.2, 0.03), Vector3(sx, 0.13, 0.12), 0.025, steel])
	var wheels: Array = []
	for sx: float in [-0.29, 0.29]:
		wheels.append(Vector3(sx, 0.13, 0.12))
	var cardboard := [Color(0.55, 0.42, 0.27), Color(0.6, 0.47, 0.3), Color(0.5, 0.38, 0.24)]
	var sizes := [Vector3(0.48, 0.40, 0.40), Vector3(0.44, 0.36, 0.36), Vector3(0.40, 0.30, 0.32)]
	var y0 := 0.035
	for i in mini(boxes, 3):
		var s: Vector3 = sizes[i]
		var c := Vector3(0.0 if i != 1 else 0.012, y0 + s.y * 0.5, -s.z * 0.5 - 0.01)
		parts.append(["box", c, s, cardboard[i]])
		# Packing tape across the top and down the front.
		parts.append(["box", c + Vector3(0.0, s.y * 0.5 + 0.002, 0.0), Vector3(0.06, 0.004, s.z + 0.004), Color(0.70, 0.60, 0.42)])
		parts.append(["box", c + Vector3(0.0, 0.0, -s.z * 0.5 - 0.002), Vector3(0.06, s.y + 0.004, 0.004), Color(0.70, 0.60, 0.42)])
		# A shipping label on the front face.
		parts.append(["box", c + Vector3(-s.x * 0.22, s.y * 0.12, -s.z * 0.5 - 0.004), Vector3(0.10, 0.07, 0.003), Color(0.9, 0.9, 0.87)])
		y0 += s.y + 0.002
	var lift := Vector3(0.0, 0.0, 0.0)
	for p: Array in parts:
		if p[0] == "beam":
			_beam(st, lean * (p[1] as Vector3) + lift, lean * (p[2] as Vector3) + lift, p[3], p[3], p[4])
		else:
			_obox(st, lean * (p[1] as Vector3) + lift, lean, p[2], p[3])
	for w: Vector3 in wheels:
		var c := lean * w + lift
		# Stand the wheels on the ground whatever the lean did to the axle's height.
		c.y = 0.13
		_wheel(st, c, 0.13, 0.065, rubber, hub)
	var mesh := st.commit()
	mesh.surface_set_material(0, trim_material())
	_truck_meshes[boxes] = mesh
	return mesh


## A wheel turning about X: a 12-sided tyre with a hub disc on each side.
static func _wheel(st: SurfaceTool, c: Vector3, r: float, w: float, tyre: Color, hub: Color) -> void:
	var n := 12
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var p0 := Vector3(0.0, sin(a0), cos(a0))
		var p1 := Vector3(0.0, sin(a1), cos(a1))
		var l := Vector3(-w * 0.5, 0.0, 0.0)
		var rr := Vector3(w * 0.5, 0.0, 0.0)
		_quad(st, c + l + p0 * r, c + l + p1 * r, c + rr + p1 * r, c + rr + p0 * r, (p0 + p1).normalized(), tyre)
		for side: float in [-1.0, 1.0]:
			var o := Vector3(side * w * 0.5, 0.0, 0.0)
			_tri(st, c + o, c + o + p0 * r * 0.98, c + o + p1 * r * 0.98, Vector3(side, 0.0, 0.0), hub)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	# Wound to face `n` whatever order the corners came in (LandmarkGeo's rule).
	var flip := (b - a).cross(c - a).dot(n) > 0.0
	var pts := [a, c, b] if flip else [a, b, c]
	for p: Vector3 in pts:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color = Color.WHITE) -> void:
	_tri(st, a, b, c, n, col)
	_tri(st, a, c, d, n, col)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	_obox(st, c, Basis(), s, col)


## A box of size `s` centred on `c`, turned by `b`.
static func _obox(st: SurfaceTool, c: Vector3, b: Basis, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var ax := [b.x * h.x, b.y * h.y, b.z * h.z]
	for k in 3:
		var u: Vector3 = ax[(k + 1) % 3]
		var v: Vector3 = ax[(k + 2) % 3]
		for sgn: float in [-1.0, 1.0]:
			var o: Vector3 = ax[k] * sgn
			var n := o.normalized()
			_quad(st, c + o - u - v, c + o + u - v, c + o + u + v, c + o - u + v, n, col)


## A square bar from `a` to `b`, `w` wide and `d` deep.
static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float, d: float, col: Color) -> void:
	var axis := b - a
	var len := axis.length()
	if len < 1e-4:
		return
	var z := axis / len
	var x := z.cross(Vector3.UP)
	if x.length() < 0.1:
		x = z.cross(Vector3.RIGHT)
	x = x.normalized()
	var y := x.cross(z).normalized()
	_obox(st, (a + b) * 0.5, Basis(x, y, z), Vector3(w, d, len), col)
