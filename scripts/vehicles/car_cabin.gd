class_name CarCabin
extends RefCounted
## The cabin behind a car's glass, and who sits in it. Every generated body with a glass slot
## (the road_* bodies, the exotics) wears shaders/car_glass.gdshader on it: dark tinted glass whose
## reflection is the renderer's, over the cabin seen through it - traced in the body model's own
## space, so it has true parallax - with the far windows letting the day in. The trace itself is
## shaders/car_cabin.gdshaderinc, which the damaged glass (car_glass_damage.gdshader, CarDamage)
## shares, so a shot-out frame shows the same cabin the intact glass did.
##
## What the shaders need about a body model is measured here, once per body type: the panes (the
## glass surface's connected pieces: a box, a mean normal, a kind and a tint each), the cabin box,
## the door line and the two rows of seats. Mesh data is not kept by the headless dummy renderer,
## so there (and for a body with no glass slot) four stand-in panes round the glasshouse do.
##
## Who is in it is per car: four occupant uniforms (seat()). A car nobody is in wears its body
## type's ONE shared glass material; an occupied car a copy of it (Vehicle._apply_occupant()), and
## a damaged car CarDamage's own glass, which takes the same uniforms. Not `instance uniform`s:
## each instance using those reserves a 16-item block of the global shader buffer, which the
## Compatibility renderer caps at 4096 items (the web may give a quarter), and the city's ~300
## cars with their shadow twins overflowed it. Traffic has a driver (a passenger now and then), a
## cruiser its crew, the car the player drives the player; parked cars are empty, and a car that
## catches fire is abandoned (Vehicle._cabin_seats()).

const GLASS_SHADER := preload("res://shaders/car_glass.gdshader")
const PANE_CAP := 16
## The pane kinds (pane[3]; the damage shader reads them too): tempered side and rear glass, the
## laminated windscreen, a lamp cover.
const KIND_TEMPERED := 0
const KIND_SCREEN := 1
const KIND_LAMP := 2

## How much of the cabin a pane lets through head on (before Fresnel): the windscreen clearest,
## the front side glass lightly tinted, the rear side glass and the rear screen a little darker,
## privacy glass (the crossover, pickup and van behind the front seats) dark, and a mid-engined
## car's engine cover almost black.
const SCREEN_T := 0.8
const FRONT_SIDE_T := 0.6
const REAR_SIDE_T := 0.48
const REAR_SCREEN_T := 0.42
const PRIVACY_T := 0.17
const ENGINE_T := 0.1
## Side glass carries this in its pane's tint slot: the shader then picks FRONT_SIDE_T or the
## body's rear side tint by where along the car the point is (the pickup's two door windows are
## one connected piece of glass).
const SIDE_BY_SEAT := -1.0
## Bodies with privacy glass behind the front seats.
const PRIVACY_BODIES := [Vehicle.BodyType.CROSSOVER, Vehicle.BodyType.PICKUP, Vehicle.BodyType.VAN]
## The two-seat exotics: no back seats, and the glass behind the cabin is an engine cover.
const TWO_SEATERS := [Vehicle.BodyType.SUPER, Vehicle.BodyType.SPIDER, Vehicle.BodyType.HYPER, Vehicle.BodyType.TRACK]
## A car whose side glass is shorter than this (m) has no back seats either (the panel van's
## cab). The bench is left out of its cabin.
const REAR_SEATS_SPAN := 1.35
## A piece of glass whose box has a diagonal under this (m) is a mirror or a badge, not a window:
## it lets nothing through and does not size the cabin (the exotics' mirror glass is in their
## glass slot, a metre out from the cabin).
const TINY_PANE := 0.3
## The front seat backs stand this far behind the windscreen's foot (m), inside the side glass.
## The old rule - just behind the middle of the side glass - assumed two rows of doors: it sat the
## saloon's driver behind the B-pillar (only his arms showed in the front window) and put the
## van's seat under its dash.
const COWL_TO_SEAT := 0.95
## The dash's face stands at least this far ahead of the front seat backs (m); the dash is
## DASH_DEPTH deep (the trace's own number, car_cabin.gdshaderinc).
const DASH_TO_SEAT := 0.72
const DASH_DEPTH := 0.42

## A bus's cabin (cabin()): the first row of pairs behind the driver's seat (m; the front door is
## between), the row pitch, the share of seats taken, and its lights' strength after dark.
const BUS_FIRST_ROW := 2.7
const BUS_ROW_PITCH := 0.80
const BUS_FILL := 0.42
const BUS_LAMP := 1.0

## One in this many traffic cars carries a front passenger (Los Angeles drives alone).
const PASSENGER_SHARE := 0.22

## Palettes, sRGB (seat() hands them to the shader linear). Skin tones for a Los Angeles street,
## the tops weighted the way people dress (mostly dark and neutral), hair.
const SKINS := [
	Color(0.93, 0.76, 0.64), Color(0.87, 0.68, 0.55), Color(0.78, 0.58, 0.44), Color(0.70, 0.50, 0.36),
	Color(0.58, 0.40, 0.28), Color(0.45, 0.30, 0.21), Color(0.34, 0.22, 0.16), Color(0.26, 0.17, 0.12),
]
const TOPS := [
	Color(0.05, 0.05, 0.055), Color(0.05, 0.05, 0.055), Color(0.86, 0.86, 0.84), Color(0.86, 0.86, 0.84),
	Color(0.46, 0.46, 0.47), Color(0.19, 0.19, 0.2), Color(0.1, 0.13, 0.24), Color(0.28, 0.38, 0.53),
	Color(0.31, 0.33, 0.21), Color(0.43, 0.1, 0.13), Color(0.66, 0.13, 0.1), Color(0.71, 0.63, 0.5),
	Color(0.56, 0.67, 0.81), Color(0.12, 0.27, 0.18), Color(0.73, 0.57, 0.18), Color(0.85, 0.56, 0.63),
]
const HAIRS := [
	Color(0.035, 0.03, 0.025), Color(0.035, 0.03, 0.025), Color(0.09, 0.06, 0.04), Color(0.09, 0.06, 0.04),
	Color(0.2, 0.13, 0.08), Color(0.3, 0.13, 0.06), Color(0.56, 0.43, 0.26), Color(0.5, 0.5, 0.5),
	Color(0.76, 0.75, 0.73),
]
## Hair styles the shader draws (occupant_skin.a): short, long, shaved, a cap.
enum Hair { SHORT, LONG, BALD, CAP }
## The player: the hero's black velour tracksuit, his skin, dark short hair.
const PLAYER_TOP := Color(0.035, 0.035, 0.04)
const PLAYER_SKIN := Color(0.8, 0.6, 0.47)
const PLAYER_HAIR := Color(0.05, 0.04, 0.03)

## Off: every car keeps its model's own opaque glass and nobody sits in it (the A/B of this file;
## CAR_GLASS=0 on tools/glshot/still_shot.gd and car_shot.gd).
static var enabled: bool = true
## Measured bodies: body key -> the data measure() returns.
static var _cache: Dictionary = {}
## Glass materials: body key -> ShaderMaterial (one per body model, shared by every car of it).
static var _materials: Dictionary = {}


# --- Measuring a body ----------------------------------------------------------------------------

## What a body's glass needs, in the mesh's own space: {"panes": [[lo, hi, normal, kind, tint],
## ...] smallest first, "cabin_lo", "cabin_hi", "belt_y", "side_top", "seat_z", "driver_side", "side_t",
## "rear_seats", "real"} ("real" false for the stand-ins). Measured once per `key` (the body type;
## null measures without caching). `ctx` is context().
static func measure(key: Variant, mesh: Mesh, ctx: Dictionary) -> Dictionary:
	if key != null and _cache.has(key):
		return _cache[key]
	var panes: Array = mesh_panes(mesh, ctx) if mesh != null else []
	var real := not panes.is_empty()
	if not real:
		panes = stand_in_panes(ctx)
	var data := cabin(panes, ctx)
	_tint(panes, data, ctx)
	data.panes = panes
	data.real = real
	if key != null:
		_cache[key] = data
	return data


## The frame measure() works in, for `car` and a body mesh `mesh_to_car` from it: the car-to-mesh
## transform, the ride height, the top of the model, the length and width, the mesh's scale, and
## whether the body has privacy glass. `has_model` false: the primitive fallback car's roof.
static func context(car: Vehicle, mesh_to_car: Transform3D, has_model: bool = true) -> Dictionary:
	var d := car._dims()
	return {
		"to_mesh": mesh_to_car.affine_inverse(),
		"ride": float(d.get("ride", car.model_bottom_y)),
		"top": car._model_top_y if has_model else 0.55 + float(d.chassis_h) + float(d.cabin_h),
		"length": float(d.length),
		"width": float(d.width),
		"scale": maxf(mesh_to_car.basis.get_scale().x, 1e-4),
		"privacy": PRIVACY_BODIES.has(car.body_type),
		"two_seat": TWO_SEATERS.has(car.body_type),
		"bus": car.body_type == Vehicle.BodyType.BUS,
	}


## measure() for a car already built (CarDamage), from its first near body mesh: the body type's
## cached measurement, or a fresh stand-in one for a car without a model.
static func for_car(car: Vehicle) -> Dictionary:
	var mesh: MeshInstance3D = null
	for m in car._body_meshes:
		if is_instance_valid(m) and not String(m.name).ends_with("_far"):
			mesh = m
			break
	var to_car := Transform3D.IDENTITY
	if mesh != null:
		to_car = chain(mesh, car)
	var ctx := context(car, to_car, car._has_model)
	return measure(car.body_type if mesh != null else null, mesh.mesh if mesh != null else null, ctx)


## `node`'s transform relative to `top` (one of its ancestors), in the tree or not.
static func chain(node: Node, top: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != top:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## The model's panes: the glass surface's connected pieces (one pass over its triangles), or
## empty with no glass surface or no mesh data.
static func mesh_panes(mesh: Mesh, ctx: Dictionary) -> Array:
	for si in mesh.get_surface_count():
		var src := mesh.surface_get_material(si)
		if src == null or String(src.resource_name) != "glass":
			continue
		var arr := mesh.surface_get_arrays(si)
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
			continue
		return _components(arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(), ctx)
	return []


static func _components(verts: PackedVector3Array, idx: PackedInt32Array, ctx: Dictionary) -> Array:
	var to_mesh: Transform3D = ctx.to_mesh
	var ride: float = ctx.ride
	var top: float = ctx.top
	var scale: float = ctx.scale
	if idx.is_empty():
		idx = PackedInt32Array(range(verts.size()))
	var key_of := {}
	var parent := PackedInt32Array()
	var vid := PackedInt32Array()
	vid.resize(verts.size())
	for i in verts.size():
		var k := Vector3i((verts[i] * 500.0).round())
		if not key_of.has(k):
			key_of[k] = parent.size()
			parent.append(parent.size())
		vid[i] = key_of[k]
	for t in range(0, idx.size() - 2, 3):
		var a := _find(parent, vid[idx[t]])
		var b := _find(parent, vid[idx[t + 1]])
		var c := _find(parent, vid[idx[t + 2]])
		parent[b] = a
		parent[_find(parent, c)] = a
	var center := to_mesh * Vector3(0.0, (ride + top) * 0.5, 0.0)
	var boxes := {}
	var norms := {}
	for t in range(0, idx.size() - 2, 3):
		var p0 := verts[idx[t]]
		var p1 := verts[idx[t + 1]]
		var p2 := verts[idx[t + 2]]
		var r := _find(parent, vid[idx[t]])
		var n := (p1 - p0).cross(p2 - p0)
		var fc := (p0 + p1 + p2) / 3.0
		if n.dot(fc - center) < 0.0:
			n = -n
		norms[r] = (norms.get(r, Vector3.ZERO) as Vector3) + n
		var box: AABB = boxes[r] if boxes.has(r) else AABB(p0, Vector3.ZERO)
		box = box.expand(p0).expand(p1).expand(p2)
		boxes[r] = box
	var list := []
	var fwd := (to_mesh.basis * Vector3.FORWARD).normalized()
	var ends := float(ctx.length) * 0.5 / scale
	var screen := -1
	var screen_score := 0.2
	for r in boxes:
		var box: AABB = boxes[r]
		var n: Vector3 = (norms[r] as Vector3).normalized()
		var c := box.get_center()
		var along := (c - center).dot(fwd)
		var kind := KIND_TEMPERED
		var body_c := to_mesh.affine_inverse() * c
		if absf(along) > ends - 0.45 / scale and body_c.y < ride + (top - ride) * 0.75:
			# Lamp glass, at either end below the glasshouse.
			kind = KIND_LAMP
		elif along > 0.0 and n.y > 0.1:
			# The windscreen: the biggest pane ahead of the middle that faces forward (raked
			# screens face mostly up: the sedan's is 24 degrees off the roof's normal).
			var score := n.dot(fwd) * sqrt(box.size.x * maxf(box.size.y, box.size.z))
			if score > screen_score:
				screen_score = score
				screen = list.size()
		list.append([box.position, box.end, n, kind, box.size.x * box.size.y * box.size.z])
	if screen >= 0:
		list[screen][3] = KIND_SCREEN
		# A windscreen modelled as two shells (the hypercar's) is one windscreen.
		var sc: Vector3 = (list[screen][0] + list[screen][1]) * 0.5
		var ss: Vector3 = list[screen][1] - list[screen][0]
		for e: Array in list:
			var ec: Vector3 = (e[0] + e[1]) * 0.5
			if int(e[3]) == KIND_TEMPERED and ec.distance_to(sc) < 0.04 / scale and ((e[1] - e[0]) as Vector3).distance_to(ss) < 0.06 / scale:
				e[3] = KIND_SCREEN
	# Biggest first to keep, then smallest first so the shader finds a small pane before the big
	# one whose box holds it.
	list.sort_custom(func(a, b): return a[4] > b[4])
	if list.size() > PANE_CAP:
		list.resize(PANE_CAP)
	list.sort_custom(func(a, b): return a[4] < b[4])
	var out := []
	for e: Array in list:
		out.append([e[0], e[1], e[2], e[3], 0.0])
	return out


static func _find(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


## Four stand-ins round the glasshouse (the windscreen, the rear screen and each side), found by
## the shader from their boxes and normals.
static func stand_in_panes(ctx: Dictionary) -> Array:
	var to_mesh: Transform3D = ctx.to_mesh
	var ride: float = ctx.ride
	var top: float = ctx.top
	var belt := ride + (top - ride) * 0.6
	var hw := float(ctx.width) * 0.5
	var hl := float(ctx.length) * 0.5
	var out := []
	for spec: Array in [
		[Vector3(-hw, belt, -hl), Vector3(hw, top, -hl * 0.1), Vector3(0.0, 0.5, -0.87), KIND_SCREEN],
		[Vector3(-hw, belt, hl * 0.1), Vector3(hw, top, hl), Vector3(0.0, 0.5, 0.87), KIND_TEMPERED],
		[Vector3(-hw, belt, -hl), Vector3(0.0, top, hl), Vector3(-1.0, 0.2, 0.0), KIND_TEMPERED],
		[Vector3(0.0, belt, -hl), Vector3(hw, top, hl), Vector3(1.0, 0.2, 0.0), KIND_TEMPERED],
	]:
		var a: Vector3 = to_mesh * (spec[0] as Vector3)
		var b: Vector3 = to_mesh * (spec[1] as Vector3)
		out.append([a.min(b), a.max(b), (to_mesh.basis * (spec[2] as Vector3)).normalized(), spec[3], 0.0])
	return out


## The cabin box the glass traces into: across and along from the side glass (plus the dash under
## the windscreen), up to the roof, down to the floor half a metre under the door line; the door
## line; the two rows of seat backs; which side the driver sits (the car's left: left-hand drive).
static func cabin(panes: Array, ctx: Dictionary) -> Dictionary:
	var to_mesh: Transform3D = ctx.to_mesh
	var scale: float = ctx.scale
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var side_lo := Vector3.INF
	var side_hi := -Vector3.INF
	var cowl := INF
	var fwd := (to_mesh.basis * Vector3.FORWARD).normalized()
	var ahead := fwd.z < 0.0
	for p: Array in panes:
		if int(p[3]) == KIND_LAMP or _tiny(p, scale):
			continue
		lo = lo.min(p[0])
		hi = hi.max(p[1])
		var n: Vector3 = p[2]
		if absf(n.dot(fwd)) < 0.5 and absf(n.y) < 0.8:
			side_lo = side_lo.min(p[0])
			side_hi = side_hi.max(p[1])
		if int(p[3]) == KIND_SCREEN:
			# The windscreen's foot: its front edge along the car.
			cowl = (p[0] as Vector3).z if ahead else (p[1] as Vector3).z
	var out := {
		"cabin_lo": Vector3(-0.75, 0.4, -1.0), "cabin_hi": Vector3(0.75, 1.4, 1.2), "belt_y": 0.95, "side_top": 1.3,
		"seat_z": Vector2(0.0, 1.0), "driver_side": -1.0, "side_t": Vector2(FRONT_SIDE_T, REAR_SIDE_T),
		"rear_seats": true,
	}
	if lo == Vector3.INF:
		return out
	if side_lo == Vector3.INF:
		side_lo = lo
		side_hi = hi
	var belt := side_lo.y
	var floor_y := belt - 0.55 / scale
	var inset := 0.06 / scale
	# Two rows of seat backs: COWL_TO_SEAT behind the windscreen's foot (just behind the middle
	# of the side glass without one), and near the rear end of the side glass.
	var a := side_lo.z if ahead else side_hi.z
	var b := side_hi.z if ahead else side_lo.z
	var back := 1.0 if ahead else -1.0
	var front_row := lerpf(a, b, 0.52)
	if cowl != INF:
		front_row = cowl + back * COWL_TO_SEAT / scale
	front_row = back * clampf(back * front_row, back * a + 0.45 / scale, back * b - 0.05 / scale)
	var rear_seats: bool = absf(b - a) * scale > REAR_SEATS_SPAN and not bool(ctx.get("two_seat", false))
	# No back seats: the bench goes well behind the cabin, where no ray through the glass reaches.
	var rear_row := lerpf(a, b, 0.9) if rear_seats else front_row + back * 3.0 / scale
	out.seat_z = Vector2(front_row, rear_row)
	out.rear_seats = rear_seats
	# Along the car (z): the side glass, a little more under the windscreen for the dash - and far
	# enough forward that the dash's face stands DASH_TO_SEAT ahead of the front seats (the
	# supercars' short side windows sit well back: the wheel was in the driver's chest).
	var z_front := a - back * 0.25 / scale
	z_front = back * minf(back * z_front, back * front_row - (DASH_TO_SEAT + DASH_DEPTH) / scale)
	var z_rear := b + back * 0.1 / scale
	out.cabin_lo = Vector3(side_lo.x + inset, floor_y, minf(z_front, z_rear))
	out.cabin_hi = Vector3(side_hi.x - inset, hi.y, maxf(z_front, z_rear))
	out.belt_y = belt
	out.side_top = side_hi.y
	var left := to_mesh.basis * Vector3.LEFT
	out.driver_side = signf(left.x) if absf(left.x) > 0.5 else -1.0
	var privacy: bool = ctx.get("privacy", false)
	out.side_t = Vector2(FRONT_SIDE_T, (PRIVACY_T if privacy else REAR_SIDE_T) if rear_seats else FRONT_SIDE_T)
	if ctx.get("bus", false):
		# A bus: rows of pairs either side of the aisle from behind the front door back to the
		# bench (the rear seat row), its glass all one tint, and its own lights on after dark.
		var first := front_row + back * BUS_FIRST_ROW / scale
		var pitch := BUS_ROW_PITCH / scale
		var n := floori(absf(rear_row - first) / pitch)
		out.bus_rows = Vector4(first, pitch, float(n), BUS_FILL)
		out.side_t = Vector2(FRONT_SIDE_T, FRONT_SIDE_T)
		out.interior_lamp = BUS_LAMP
	return out


## Each pane's tint (pane[4]): the windscreen, side glass (decided by the shader, SIDE_BY_SEAT),
## the rear screen - or, behind a two-seater's cabin, the engine cover - and nothing for a lamp.
static func _tint(panes: Array, data: Dictionary, ctx: Dictionary) -> void:
	var to_mesh: Transform3D = ctx.to_mesh
	var fwd := (to_mesh.basis * Vector3.FORWARD).normalized()
	var privacy: bool = ctx.get("privacy", false)
	var rear_seats: bool = data.rear_seats
	for p: Array in panes:
		var kind := int(p[3])
		var n: Vector3 = p[2]
		if kind == KIND_LAMP or _tiny(p, float(ctx.scale)):
			p[4] = 0.0
		elif kind == KIND_SCREEN:
			p[4] = SCREEN_T
		elif absf(n.dot(fwd)) < 0.5 and absf(n.y) < 0.8:
			p[4] = SIDE_BY_SEAT
		elif not rear_seats:
			p[4] = ENGINE_T
		else:
			p[4] = PRIVACY_T if privacy else REAR_SCREEN_T


static func _tiny(p: Array, scale: float) -> bool:
	return ((p[1] as Vector3) - (p[0] as Vector3)).length() * scale < TINY_PANE


# --- Materials -----------------------------------------------------------------------------------

## The intact glass for body `key`: one ShaderMaterial per body model, shared by every car of it,
## with the model's own glass colour, roughness and metal carried over (`src`) and `data`'s panes
## and cabin in its uniforms.
static func glass_material(key: Variant, src: StandardMaterial3D, data: Dictionary) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = GLASS_SHADER
	mat.set_shader_parameter("glass_albedo", Color(src.albedo_color.r, src.albedo_color.g, src.albedo_color.b))
	mat.set_shader_parameter("glass_roughness", src.roughness)
	mat.set_shader_parameter("glass_metallic", src.metallic)
	apply(mat, data)
	_materials[key] = mat
	return mat


## `data`'s cabin and panes into a glass material's uniforms (every pane whole; CarDamage pushes
## its own pane states over them).
static func apply(mat: ShaderMaterial, data: Dictionary, states: PackedFloat32Array = PackedFloat32Array()) -> void:
	mat.set_shader_parameter("cabin_lo", data.cabin_lo)
	mat.set_shader_parameter("cabin_hi", data.cabin_hi)
	mat.set_shader_parameter("belt_y", data.belt_y)
	mat.set_shader_parameter("side_top", data.side_top)
	mat.set_shader_parameter("seat_z", data.seat_z)
	mat.set_shader_parameter("driver_side", data.driver_side)
	mat.set_shader_parameter("side_t", data.side_t)
	mat.set_shader_parameter("bus_rows", data.get("bus_rows", Vector4.ZERO))
	mat.set_shader_parameter("interior_lamp", float(data.get("interior_lamp", 0.0)))
	var panes: Array = data.panes
	mat.set_shader_parameter("pane_count", panes.size())
	if panes.is_empty():
		return
	var lo := PackedVector4Array()
	var hi := PackedVector4Array()
	var nn := PackedVector4Array()
	for i in panes.size():
		var p: Array = panes[i]
		var a: Vector3 = p[0]
		var b: Vector3 = p[1]
		var n: Vector3 = p[2]
		lo.append(Vector4(a.x, a.y, a.z, states[i] if i < states.size() else 0.0))
		hi.append(Vector4(b.x, b.y, b.z, float(p[3])))
		nn.append(Vector4(n.x, n.y, n.z, float(p[4])))
	mat.set_shader_parameter("pane_lo", lo)
	mat.set_shader_parameter("pane_hi", hi)
	mat.set_shader_parameter("pane_n", nn)


# --- Occupants ------------------------------------------------------------------------------------

## A traffic driver (and passenger) rolled from `seed`: {"top", "skin", "hair", "style", "mate",
## "mate_skin", "passenger"}.
static func npc_look(seed: int) -> Dictionary:
	var style := Hair.SHORT
	var s := _roll(seed, 4)
	if s < 0.3:
		style = Hair.LONG
	elif s < 0.37:
		style = Hair.BALD
	elif s < 0.45:
		style = Hair.CAP
	var hair: Color = HAIRS[absi(hash([seed, 3])) % HAIRS.size()]
	if style == Hair.CAP:
		# The cap's colour.
		hair = TOPS[absi(hash([seed, 5])) % TOPS.size()]
	return {
		"top": TOPS[absi(hash([seed, 1])) % TOPS.size()],
		"skin": SKINS[absi(hash([seed, 2])) % SKINS.size()],
		"hair": hair,
		"style": style,
		"mate": TOPS[absi(hash([seed, 6])) % TOPS.size()],
		"mate_skin": _roll(seed, 7),
		"passenger": _roll(seed, 8) < PASSENGER_SHARE,
		"seed": _roll(seed, 9),
	}


## A cruiser's crew: the navy uniform (black for the tactical unit) and a peaked cap.
static func police_look(heavy: bool, seed: int) -> Dictionary:
	var top := PoliceOfficer.HEAVY_TOP if heavy else PoliceOfficer.UNIFORM_TOP
	return {
		"top": top,
		"skin": SKINS[absi(hash([seed, 2])) % SKINS.size()],
		"hair": PoliceOfficer.CAP_COLOR if not heavy else Color(0.05, 0.05, 0.055),
		"style": Hair.CAP,
		"uniform": true,
		"mate": top,
		"mate_skin": _roll(seed, 7),
		"passenger": true,
		"seed": _roll(seed, 9),
	}


## The player at the wheel (the hero is hidden while he drives, so this is him).
static func player_look() -> Dictionary:
	return {
		"top": PLAYER_TOP, "skin": PLAYER_SKIN, "hair": PLAYER_HAIR, "style": Hair.SHORT,
		"mate": PLAYER_TOP, "mate_skin": 0.3, "passenger": false, "seed": 0.5,
	}


## Puts `seats` (bit 0 the driver's, bit 1 the front passenger's; 0 nobody) and `look` into a glass
## material's occupant uniforms (the car's own copy, or CarDamage's glass).
static func seat(mat: ShaderMaterial, seats: int, look: Dictionary) -> void:
	if mat == null:
		return
	var top: Color = (look.top as Color).srgb_to_linear()
	var skin: Color = (look.skin as Color).srgb_to_linear()
	var hair: Color = (look.hair as Color).srgb_to_linear()
	var mate: Color = (look.mate as Color).srgb_to_linear()
	mat.set_shader_parameter("occupant_top", Vector4(top.r, top.g, top.b, float(seats)))
	mat.set_shader_parameter("occupant_skin", Vector4(skin.r, skin.g, skin.b, float(look.style)))
	mat.set_shader_parameter("occupant_hair", Vector4(hair.r, hair.g, hair.b, float(look.seed)))
	mat.set_shader_parameter("occupant_mate", Vector4(mate.r, mate.g, mate.b,
			minf(float(look.mate_skin), 0.99) + (2.0 if look.get("uniform", false) else 0.0)))


## The seats a glass material shows (occupant_top.a), for tests and tools.
static func seats_of(mat: Material) -> int:
	var sm := mat as ShaderMaterial
	if sm == null:
		return 0
	var v: Variant = sm.get_shader_parameter("occupant_top")
	return roundi((v as Vector4).w) if v is Vector4 else 0


static func _roll(seed: int, salt: int) -> float:
	return float(absi(hash([seed, salt, 911])) % 100000) / 100000.0
