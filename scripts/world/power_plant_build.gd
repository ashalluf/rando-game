class_name PowerPlantBuild
extends RefCounted
## Builds the power plant (PowerPlant's layout, PowerPlantKit's hardware) into the city's tiers:
##   site_steps()     a site chunk's part: the pavement ring, the yard's ground (gravel, asphalt,
##                    concrete pads), the fence, every piece whose centre is in the chunk (FULL: the
##                    kit at full detail, a step a piece; LOD: the same masses with the small things
##                    left out), flood masts and their pools, parked cars, a few staff.
##   capture_steps()  the far city's record: ground slabs and a box per piece.
##   extras()         any other chunk: the seawall and the intake trestle on the sand in front of
##                    the plant, the line's towers (FULL), its right of way and the receiving station.
##   landmark()       the always-there part (Landmarks.build, near and far alike): every conductor
##                    and earth wire of the line, the strain bus and the towers' lattice as fine lines
##                    (power_wire.gdshader, as the ridges' lines), and the stacks' aviation lights.

const POOL_KEY := "pp_pool"
const MAX_OMNI := 4

## A tower's far lines collapse once a FULL chunk builds it (power_wire.gdshader's `covered`).
static var _cover_img: Image = null
static var _cover_tex: ImageTexture = null
static var _covered: Dictionary = {}
static var _wire_mat: ShaderMaterial = null
static var _walk_mat: Material = null


class Acc:
	var geo: PowerPlantKit.Geo
	var ground: SurfaceTool
	var walk: SurfaceTool


static func _acc(ch: CityChunk) -> Acc:
	if not ch.has_meta("pp_acc"):
		var a := Acc.new()
		a.geo = PowerPlantKit.Geo.new()
		a.geo.full = ch.level == CityChunk.Level.FULL
		a.ground = SurfaceTool.new()
		a.ground.begin(Mesh.PRIMITIVE_TRIANGLES)
		a.walk = SurfaceTool.new()
		a.walk.begin(Mesh.PRIMITIVE_TRIANGLES)
		ch.set_meta("pp_acc", a)
	return ch.get_meta("pp_acc")


static func _full(ch: CityChunk) -> bool:
	return ch.level == CityChunk.Level.FULL and not ch.capturing


static func _parts(rects: Array, area: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r: Rect2 in rects:
		var p := r.intersection(area)
		if p.size.x > 0.05 and p.size.y > 0.05:
			out.append(p)
	return out


# =================================================================================================
# The site's chunks
# =================================================================================================

static func site_steps(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var lay := PowerPlant.layout(ch.plan)
	if lay.is_empty():
		return steps
	var area := ch.owned_rect()
	steps.append(_ground.bind(ch, lay, area))
	if bool(lay.ok):
		steps.append(_fence.bind(ch, lay, area))
		for p: Dictionary in PowerPlant.pieces_in(lay, area):
			steps.append(_piece.bind(ch, p))
		steps.append(_lamps.bind(ch, lay, area))
		if _full(ch):
			steps.append(_cars.bind(ch, lay, area))
			steps.append(_crowd.bind(ch, lay, area))
	steps.append(_commit.bind(ch))
	return steps


static func capture_steps(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var lay := PowerPlant.layout(ch.plan)
	if lay.is_empty():
		return steps
	var area := ch.owned_rect()
	steps.append(_ground.bind(ch, lay, area))
	if bool(lay.ok):
		steps.append(func() -> void:
			for p: Dictionary in PowerPlant.pieces_in(lay, area):
				_far_boxes(ch, p))
	return steps


static func _gy(ch: CityChunk, p: Vector2) -> float:
	return ch._gy(p.x, p.y)


## The pavement ring outside the fence, gravel inside, the roads and pads over it.
static func _ground(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var rect: Rect2 = lay.rect
	var inner: Rect2 = (lay.fence as Rect2).grow(-0.05)
	var ring := Parks.minus(rect, [inner], 0.05)
	var specials: Array = []
	for gr: Array in lay.ground:
		specials.append(gr[0])
	var gravel := Parks.minus(inner, specials, 0.05)
	if not _full(ch):
		for r: Rect2 in _parts(ring, area):
			ch._add_slab(Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP - 0.1, r.get_center().y), Vector3(r.size.x, 0.2, r.size.y), ch.style.sidewalk, true)
		for r: Rect2 in _parts(gravel, area):
			ch._add_slab(Vector3(r.get_center().x, PowerPlant.BASE_Y - 0.1, r.get_center().y), Vector3(r.size.x, 0.2, r.size.y), Color(0.36, 0.36, 0.35), true)
		for gr: Array in lay.ground:
			for r: Rect2 in _parts([gr[0]], area):
				var col := Color(0.3, 0.3, 0.3) if int(gr[1]) == Industrial.G_ASPHALT else (Color(0.48, 0.46, 0.43) if int(gr[1]) == Industrial.G_GRAVEL else Color(0.62, 0.61, 0.58))
				ch._add_slab(Vector3(r.get_center().x, PowerPlant.BASE_Y - 0.09, r.get_center().y), Vector3(r.size.x, 0.2, r.size.y), col, true)
		return
	var acc := _acc(ch)
	for r: Rect2 in _parts(ring, area):
		FilmStudio._flat(ch, acc.walk, r, CityChunk.SIDEWALK_TOP)
		ch._add_shape(Vector3(r.size.x, 0.3, r.size.y), Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP - 0.15 + _gy(ch, r.get_center()), r.get_center().y))
	for r: Rect2 in _parts(gravel, area):
		# The yard is paved (asphalt worn grey); the switchyard and the tank berm are gravel pieces.
		Industrial._ground_rect(acc.ground, ch, r, PowerPlant.BASE_Y, Industrial.G_ASPHALT, 0.75, true)
		ch._add_shape(Vector3(r.size.x, 0.3, r.size.y), Vector3(r.get_center().x, PowerPlant.BASE_Y - 0.15 + _gy(ch, r.get_center()), r.get_center().y))
	for gr: Array in lay.ground:
		for r: Rect2 in _parts([gr[0]], area):
			Industrial._ground_rect(acc.ground, ch, r, PowerPlant.BASE_Y + 0.01, int(gr[1]), 0.3, true)
			ch._add_shape(Vector3(r.size.x, 0.3, r.size.y), Vector3(r.get_center().x, PowerPlant.BASE_Y - 0.14 + _gy(ch, r.get_center()), r.get_center().y))
	# A centre line down the main roads.
	for gr: Array in lay.ground:
		if int(gr[1]) != Industrial.G_ASPHALT:
			continue
		var sr: Rect2 = gr[0]
		var line := Rect2(sr.get_center().x - 0.06, sr.position.y + 2.0, 0.12, sr.size.y - 4.0) if sr.size.y > sr.size.x else Rect2(sr.position.x + 2.0, sr.get_center().y - 0.06, sr.size.x - 4.0, 0.12)
		for p: Rect2 in _parts([line], area):
			Industrial._ground_rect(acc.ground, ch, p, PowerPlant.BASE_Y + 0.022, Industrial.G_PAINT, 0.9, false)


## The fence round the site (on its line, cut for the gate), its corner posts.
static func _fence(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var f: Rect2 = lay.fence
	var gate: Vector2 = lay.gate.at
	var hw := float(lay.gate.w) * 0.5
	var c := [f.position, Vector2(f.end.x, f.position.y), f.end, Vector2(f.position.x, f.end.y)]
	var runs: Array = [[c[0], c[1]], [c[3], c[2]], [c[0], c[3]],
		[c[1], Vector2(f.end.x, gate.y - hw)], [Vector2(f.end.x, gate.y + hw), c[2]]]
	var g: PowerPlantKit.Geo = _acc(ch).geo if not ch.capturing else null
	if g == null:
		return
	for run: Array in runs:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var n := maxi(1, ceili(a.distance_to(b) / 12.0))
		for i in n:
			var p0 := a.lerp(b, float(i) / float(n))
			var p1 := a.lerp(b, float(i + 1) / float(n))
			if not area.has_point((p0 + p1) * 0.5):
				continue
			PowerPlantKit.fence(g, Vector3(p0.x, PowerPlant.BASE_Y + _gy(ch, p0), p0.y), Vector3(p1.x, PowerPlant.BASE_Y + _gy(ch, p1), p1.y))
	# The gate's sliding leaves (open) and the name sign beside it.
	if area.has_point(gate):
		var y := PowerPlant.BASE_Y + _gy(ch, gate)
		for sg: float in [-1.0, 1.0]:
			var p := Vector3(f.end.x + 0.6, y, gate.y + sg * (hw + 5.5))
			g.box(Transform3D(Basis(), p + Vector3(0, 1.3, 0)), Vector3(0.12, 2.6, 10.0), PowerPlantKit.K_CHAIN, Color(0.7, 0.71, 0.72))
			g.box(Transform3D(Basis(), p + Vector3(0, 2.6, 0)), Vector3(0.1, 0.1, 10.0), PowerPlantKit.K_GALV, Color(0.66, 0.67, 0.68))
			g.box(Transform3D(Basis(), Vector3(f.end.x, y + 1.6, gate.y + sg * hw)), Vector3(0.35, 3.2, 0.35), PowerPlantKit.K_STEEL, PowerPlantKit.YELLOW)
		var sp := Vector3(f.end.x + 3.2, y, gate.y - hw - 4.0)
		g.box(Transform3D(Basis(), sp + Vector3(0, 0.4, 0)), Vector3(1.2, 0.8, 7.0), PowerPlantKit.K_CONCRETE, PowerPlantKit.CONCRETE)
		g.box(Transform3D(Basis(), sp + Vector3(0, 1.6, 0)), Vector3(0.4, 1.6, 6.6), PowerPlantKit.K_SIGN, Color(0.12, 0.22, 0.38))
		if g.full:
			PowerPlantKit.letters(g, PowerPlant.NAME, 0.36, Transform3D(Basis(Vector3.UP, PI * 0.5), sp + Vector3(0.22, 1.85, 0)), Color(0.95, 0.95, 0.92), 6.2)
			PowerPlantKit.letters(g, PowerPlant.COMPANY, 0.26, Transform3D(Basis(Vector3.UP, PI * 0.5), sp + Vector3(0.22, 1.3, 0)), Color(0.98, 0.78, 0.2), 6.2)


static func _piece(ch: CityChunk, p: Dictionary) -> void:
	var c: Vector2 = p.c
	var o := Vector3(c.x, PowerPlant.BASE_Y + _gy(ch, c), c.y)
	var g := _acc(ch).geo
	PowerPlantKit.build_piece(g, p, o)
	if _full(ch):
		_collide(ch, p, o)
	else:
		var sz: Vector3 = p.size
		if String(p.kind) in ["turbine_hall", "boiler_house", "st_hall", "hrsg", "admin", "pump_house"]:
			ch._add_lod_shape(sz, o + Vector3(0, sz.y * 0.5, 0))


## Collision and the occluder for a piece (boxes: a tank or a stack as the box inside it).
static func _collide(ch: CityChunk, p: Dictionary, o: Vector3) -> void:
	var sz: Vector3 = p.size
	match String(p.kind):
		"turbine_hall", "boiler_house", "st_hall", "admin", "pump_house", "gas_turbine", "hrsg":
			ch._add_shape(sz, o + Vector3(0, sz.y * 0.5, 0))
			ch._occluder_boxes.append([Transform3D(Basis(), Vector3.ZERO), o + Vector3(0, sz.y * 0.5, 0), sz - Vector3(1.2, 1.2, 1.2)])
		"stack", "hrsg_stack":
			var r: float = float(p.r1) * 1.4
			ch._add_shape(Vector3(r, sz.y, r), o + Vector3(0, sz.y * 0.5, 0))
			ch._add_shape(Vector3(float(p.r0) * 1.4, 10.0, float(p.r0) * 1.4), o + Vector3(0, 5.0, 0))
		"tank":
			var r: float = float(p.r) * 1.41
			ch._add_shape(Vector3(r, sz.y, r), o + Vector3(0, sz.y * 0.5, 0))
			ch._occluder_boxes.append([Transform3D(Basis(), Vector3.ZERO), o + Vector3(0, sz.y * 0.5, 0), Vector3(r - 1.0, sz.y - 1.0, r - 1.0)])
		"filter_house":
			ch._add_shape(Vector3(sz.x, sz.y - 9.0, sz.z), o + Vector3(0, 9.0 + (sz.y - 9.0) * 0.5, 0))
		"flue":
			ch._add_shape(sz, o + Vector3(0, float(p.y), 0))
		"gsu":
			ch._add_shape(Vector3(5.2, 5.0, 6.4), o + Vector3(0, 2.6, 0))
		"berm":
			var hw := sz.x * 0.5
			var hd := sz.z * 0.5
			ch._add_shape(Vector3(sz.x, sz.y, 0.4), o + Vector3(0, sz.y * 0.5, -hd))
			ch._add_shape(Vector3(sz.x, sz.y, 0.4), o + Vector3(0, sz.y * 0.5, hd))
			ch._add_shape(Vector3(0.4, sz.y, sz.z), o + Vector3(-hw, sz.y * 0.5, 0))
			ch._add_shape(Vector3(0.4, sz.y, sz.z), o + Vector3(hw, sz.y * 0.5, 0))


## The far city's boxes for a piece (the old far-box path: colour, window style, plain flag).
static func _far_boxes(ch: CityChunk, p: Dictionary) -> void:
	var c: Vector2 = p.c
	# The batch adds the relief itself.
	var o := Vector3(c.x, PowerPlant.BASE_Y, c.y)
	var sz: Vector3 = p.size
	var plain := Color(0.0, 0.0, float(int(p.seed) % 997) / 997.0, 1.0)
	var col := Color(0.7, 0.7, 0.68)
	match String(p.kind):
		"turbine_hall":
			col = PowerPlantKit.CLAD_HALL
		"boiler_house":
			col = PowerPlantKit.CLAD_BOILER
		"st_hall":
			col = PowerPlantKit.CLAD_ST
		"hrsg":
			col = PowerPlantKit.HRSG_GREY
		"gas_turbine":
			col = PowerPlantKit.GT_GREEN
		"stack":
			col = Color(0.72, 0.7, 0.66)
		"tank":
			col = p.paint
		"switchyard", "pipe_rack", "pipe_bridge", "gsu", "guard", "berm":
			return
	var size := sz
	var y := sz.y * 0.5
	if String(p.kind) in ["stack", "hrsg_stack"]:
		size = Vector3(float(p.r0) * 1.7, sz.y, float(p.r0) * 1.7)
	elif String(p.kind) == "tank":
		size = Vector3(float(p.r) * 1.75, sz.y, float(p.r) * 1.75)
	elif String(p.kind) == "flue":
		y = float(p.y)
	elif String(p.kind) == "filter_house":
		size = Vector3(sz.x, sz.y - 9.0, sz.z)
		y = 9.0 + size.y * 0.5
	var custom := plain
	if String(p.kind) == "admin":
		custom = Color(0.25, 0.55, float(int(p.seed) % 997) / 997.0, 0.0)
	ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(size), o + Vector3(0, y, 0)), col, custom)
	if String(p.kind) == "stack":
		# The red and white top third as its own box.
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(float(p.r1) * 1.75, sz.y * 0.38, float(p.r1) * 1.75)), o + Vector3(0, sz.y * 0.81, 0)), Color(0.78, 0.36, 0.3), plain)


## Flood masts, their pools, a few real lights after dark (desktop).
static func _lamps(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var g := _acc(ch).geo
	var n_omni := 0
	for p: Vector2 in lay.lamps:
		if not area.has_point(p):
			continue
		var y := PowerPlant.BASE_Y + _gy(ch, p)
		PowerPlantKit.flood_mast(g, Vector3(p.x, y, p.y), 18.0)
		if not _full(ch):
			continue
		ch._batch.add(POOL_KEY, PropFactory.light_pool(Color(1.0, 0.86, 0.66), 0.8, 2.0), Transform3D(Basis().scaled(Vector3(30.0, 1.0, 30.0)), Vector3(p.x, PowerPlant.BASE_Y + 0.03, p.y + 6.0)))
		if not OS.has_feature("web") and n_omni < MAX_OMNI:
			var l := OmniLight3D.new()
			l.position = Vector3(p.x, y + 16.0, p.y + 4.0)
			l.light_color = Color(1.0, 0.88, 0.7)
			l.omni_range = 42.0
			l.omni_attenuation = 1.2
			l.light_energy = 0.0
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 260.0
			l.distance_fade_length = 60.0
			l.visible = false
			l.set_meta("dark_hidden", true)
			l.add_to_group("lamp_light")
			ch.add_child(l)
			n_omni += 1
	if _full(ch):
		ch._batch.set_no_shadow(POOL_KEY)


static func _cars(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var paints := [Color(0.85, 0.85, 0.84), Color(0.1, 0.1, 0.11), Color(0.5, 0.52, 0.54), Color(0.66, 0.67, 0.68), Color(0.3, 0.12, 0.1), Color(0.14, 0.2, 0.32)]
	for i in (lay.cars as Array).size():
		var car: Dictionary = lay.cars[i]
		var p: Vector2 = car.at
		if not area.has_point(p):
			continue
		var v := int(car.v)
		var col: Color = paints[absi(hash([ch.plan.seed, "pp_car_paint", i])) % paints.size()]
		ch._batch.add("pp_car_%d" % v, ArenaGrounds.car_mesh(v), Transform3D(Basis(Vector3.UP, float(car.yaw)), Vector3(p.x, PowerPlant.BASE_Y, p.y)), col)


## A few staff walking the plant's roads.
static func _crowd(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	for gr: Array in lay.ground:
		if int(gr[1]) != Industrial.G_ASPHALT:
			continue
		for r: Rect2 in _parts([gr[0]], area):
			var length := maxf(r.size.x, r.size.y)
			if length < 30.0:
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([ch.plan.seed, "pp_staff", int(r.position.x), int(r.position.y)])
			var n := int(length / 70.0 + rng.randf())
			for step: Callable in ch._crowd_steps(r, minf(r.size.x, r.size.y) * 0.5, n, rng):
				step.call()


static func _commit(ch: CityChunk) -> void:
	if not ch.has_meta("pp_acc"):
		return
	var acc: Acc = ch.get_meta("pp_acc")
	ch.remove_meta("pp_acc")
	if _walk_mat == null:
		_walk_mat = PropFactory.road("sidewalk", 3.0, Color(1.45, 1.43, 1.38), 7713, 1.5, 0.35)
	if acc.geo.tris() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "PowerPlant"
		mi.mesh = acc.geo.mesh(PowerPlantKit.material())
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		ch.add_child(mi)
	for part: Array in [["PowerPlantGround", acc.ground, Industrial.ground_material()], ["PowerPlantPavement", acc.walk, _walk_mat]]:
		var st: SurfaceTool = part[1]
		var mesh := st.commit()
		if mesh.get_surface_count() == 0:
			continue
		var gi := MeshInstance3D.new()
		gi.name = part[0]
		gi.mesh = mesh
		gi.material_override = part[2]
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(gi)


# =================================================================================================
# Other chunks: the seawall and intake on the sand, the line's towers, right of way and station
# =================================================================================================

static func extras(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	if not PowerPlant.enabled or ch.capturing or ch.plan.macro == null:
		return steps
	var lay := PowerPlant.layout(ch.plan)
	if lay.is_empty() or not bool(lay.ok):
		return steps
	var area := ch.owned_rect()
	var rect: Rect2 = lay.rect
	# The seawall: along the sand's landward edge in front of the plant (the chunk the edge is in).
	if area.position.y < rect.end.y and area.end.y > rect.position.y and area.position.x < rect.position.x:
		var m := ch.plan.macro
		var zc := clampf((area.position.y + area.end.y) * 0.5, rect.position.y, rect.end.y)
		var edge := m.coast_x(zc) + m.beach_width_at(zc)
		if edge > area.position.x - 10.0 and edge < area.end.x + 10.0:
			steps.append(_seawall.bind(ch, lay, area))
	var ln := PowerPlant.line(ch.plan)
	if not ln.is_empty():
		var any := false
		for t: Dictionary in ln.towers:
			if area.has_point(t.pos):
				any = true
		var st: Rect2 = ln.station.rect
		if any or not PowerPlant.row_rects_in(ch.plan, area).is_empty() or st.intersects(area):
			steps.append(_line_bits.bind(ch, ln, area))
	if not steps.is_empty():
		steps.append(_commit.bind(ch))
	return steps


static func _seawall(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var m := ch.plan.macro
	var rect: Rect2 = lay.rect
	var g := _acc(ch).geo
	var z0 := maxf(rect.position.y - 8.0, area.position.y)
	var z1 := minf(rect.end.y + 8.0, area.end.y)
	if z1 - z0 < 4.0:
		return
	var step := 12.0
	var n := maxi(1, ceili((z1 - z0) / step))
	var top := CityChunk.SIDEWALK_TOP + 0.95 + ch._gy(m.coast_x(z0) + m.beach_width_at(z0), z0)
	var iz: float = lay.intake_z
	for i in n:
		var za := z0 + (z1 - z0) * float(i) / float(n)
		var zb := z0 + (z1 - z0) * float(i + 1) / float(n)
		var zm := (za + zb) * 0.5
		if absf(zm - iz) < 10.0 + step * 0.5:
			continue
		var x := m.coast_x(zm) + m.beach_width_at(zm) - 1.5
		if not area.has_point(Vector2(x, zm)):
			continue
		var sand := BeachLife.sand_y(ch, x - 1.0, zm)
		PowerPlantKit.seawall(g, x, za, zb, sand - 0.3, top, absi(hash([ch.plan.seed, "pp_wall", i, int(z0)])))
		if _full(ch):
			ch._add_shape(Vector3(2.4, top - sand + 0.6, zb - za), Vector3(x + 0.4, (top + sand) * 0.5, zm))
	if area.position.y <= iz and area.end.y > iz:
		var x := m.coast_x(iz) + m.beach_width_at(iz) - 1.5
		if area.has_point(Vector2(x, iz)):
			var sand := BeachLife.sand_y(ch, x - 3.0, iz)
			var out := (x - m.coast_x(iz)) + 40.0
			PowerPlantKit.intake(g, x, iz, sand - 0.2, out, BeachLife.path_x(ch.plan, iz))
			if _full(ch):
				ch._add_shape(Vector3(6.0, 5.4, 20.0), Vector3(x - 3.0, sand + 2.5, iz))
				ch._add_shape(Vector3(out, 0.4, 2.2), Vector3(x - 6.0 - out * 0.5, sand + 5.4, iz))


## The towers in this chunk (FULL), the right of way's ground, the receiving station.
static func _line_bits(ch: CityChunk, ln: Dictionary, area: Rect2) -> void:
	var acc := _acc(ch)
	var g := acc.geo
	var full := _full(ch)
	# The right of way: weeds and dirt where the lots were taken, never on a road or the pavement.
	var k := ch.plan.block_index_at(area.get_center())
	var b := ch.plan.block(k.x, k.y)
	var inner: Rect2 = (b.rect as Rect2).grow(-ch.plan.sidewalk_width)
	for r: Rect2 in PowerPlant.row_rects_in(ch.plan, area):
		var p := r.intersection(inner)
		if p.size.x < 1.0 or p.size.y < 1.0:
			continue
		if full:
			Industrial._ground_rect(acc.ground, ch, p, CityChunk.SIDEWALK_TOP + 0.02, Industrial.G_WEEDS, PowerPlant.h01([ch.plan.seed, int(p.position.x)]), true)
		else:
			ch._add_slab(Vector3(p.get_center().x, CityChunk.SIDEWALK_TOP - 0.08, p.get_center().y), Vector3(p.size.x, 0.2, p.size.y), Color(0.46, 0.44, 0.34), false)
	# The towers.
	if full:
		for t: Dictionary in ln.towers:
			if not area.has_point(t.pos):
				continue
			var xf := Ridges.tower_xform(t)
			var body := MeshInstance3D.new()
			body.name = "PlantLineTower_%d" % int(t.id)
			body.mesh = RidgeKit.tower_body(float(t.h), int(t.kind))
			body.transform = xf
			ch.add_child(body)
			var legs := MeshInstance3D.new()
			legs.mesh = RidgeKit.tower_legs(t)
			legs.transform = xf
			legs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ch.add_child(legs)
			var sp := Ridges.spec(float(t.h))
			for c in 4:
				var s: Vector2 = RidgeKit.CORNER_SIGNS[c]
				var foot := xf * Vector3(s.x * float(sp.base_half), 0.0, s.y * float(sp.base_half))
				ch._add_shape(Vector3(0.6, 8.0, 0.6), foot + Vector3(0, 4.0, 0))
				g.box(Transform3D(Basis(), foot + Vector3(0, -0.2, 0)), Vector3(1.4, 0.7, 1.4), PowerPlantKit.K_CONCRETE, PowerPlantKit.CONCRETE)
			cover(int(t.id) + 1, true)
			body.tree_exiting.connect(cover.bind(int(t.id) + 1, false))
	# The receiving station: gravel inside a fence, a gantry, two transformers, the bays, a house.
	var st: Rect2 = ln.station.rect
	var sc := st.get_center()
	if area.has_point(sc):
		var y := CityChunk.SIDEWALK_TOP + 0.05 + ch._gy(sc.x, sc.y)
		if full:
			Industrial._ground_rect(acc.ground, ch, st, CityChunk.SIDEWALK_TOP + 0.04, Industrial.G_GRAVEL, 0.5, true)
			ch._add_shape(Vector3(st.size.x, 0.3, st.size.y), Vector3(sc.x, y - 0.15, sc.y))
		else:
			ch._add_slab(Vector3(sc.x, CityChunk.SIDEWALK_TOP - 0.07, sc.y), Vector3(st.size.x, 0.2, st.size.y), Color(0.48, 0.46, 0.43), false)
		var sg: Dictionary = ln.station.gantry
		var gxf := Transform3D(Basis(Vector3.UP, float(sg.yaw)), Vector3((sg.pos as Vector2).x, y, (sg.pos as Vector2).y))
		for m: Array in RidgeKit.gantry_members(not full):
			g.angle(gxf * (m[0] as Vector3), gxf * (m[1] as Vector3), float(m[2]), gxf.basis * (m[3] as Vector3), gxf.basis * (m[4] as Vector3), m[5])
		for sx: float in [-0.22, 0.22]:
			PowerPlantKit.transformer(g, Vector3(sc.x + 8.0, y, sc.y + sx * st.size.y), Vector3(1, 0, 0), false)
		PowerPlantKit._bay(g, Vector3(sc.x + 20.0, y, sc.y))
		var house := Vector3(st.end.x - 7.0, y, st.end.y - 6.0)
		g.box(Transform3D(Basis(), house + Vector3(0, 2.0, 0)), Vector3(9.0, 4.0, 6.0), PowerPlantKit.K_CONCRETE, Color(0.8, 0.76, 0.68))
		g.box(Transform3D(Basis(), house + Vector3(0, 4.2, 0)), Vector3(9.4, 0.4, 6.4), PowerPlantKit.K_ROOF, Color(0.52, 0.52, 0.5))
		var c4 := [st.position, Vector2(st.end.x, st.position.y), st.end, Vector2(st.position.x, st.end.y)]
		for i in 4:
			var a: Vector2 = c4[i]
			var bb: Vector2 = c4[(i + 1) % 4]
			PowerPlantKit.fence(g, Vector3(a.x, y, a.y), Vector3(bb.x, y, bb.y))
		if full:
			ch._add_shape(Vector3(9.0, 4.0, 6.0), house + Vector3(0, 2.0, 0))
			var bs := Vector3(st.position.x + 2.0, y, st.position.y - 0.3)
			g.box(Transform3D(Basis(), bs + Vector3(6.0, 1.8, 0)), Vector3(8.0, 1.0, 0.1), PowerPlantKit.K_SIGN, Color(0.12, 0.22, 0.38))
			PowerPlantKit.letters(g, PowerPlant.STATION_NAME, 0.22, Transform3D(Basis(Vector3.UP, PI), bs + Vector3(6.0, 1.82, -0.07)), Color(0.95, 0.95, 0.92), 7.6)


## Collapse (or bring back) tower `id`'s far lines.
static func cover(id: int, on: bool) -> void:
	if on:
		_covered[id] = true
	else:
		_covered.erase(id)
	_apply_cover()


static func _apply_cover() -> void:
	if _cover_img == null:
		return
	_cover_img.fill(Color(0, 0, 0))
	for id: int in _covered:
		var i := id - 1
		if i >= 0 and i < _cover_img.get_width():
			_cover_img.set_pixel(i, 0, Color(1, 0, 0))
	_cover_tex.update(_cover_img)


static func wire_material() -> ShaderMaterial:
	if _wire_mat != null:
		return _wire_mat
	_cover_img = Image.create(32, 1, false, Image.FORMAT_R8)
	_cover_tex = ImageTexture.create_from_image(_cover_img)
	_wire_mat = ShaderMaterial.new()
	_wire_mat.shader = load("res://shaders/power_wire.gdshader")
	_wire_mat.set_shader_parameter("covered", _cover_tex)
	_wire_mat.set_shader_parameter("covered_width", 32)
	_apply_cover()
	return _wire_mat


# =================================================================================================
# The landmark: the wires and the lights, near and far alike
# =================================================================================================

static func landmark(parent: Node3D, plan: CityPlan) -> void:
	var lay := PowerPlant.layout(plan)
	if lay.is_empty() or not bool(lay.ok):
		return
	var w := RidgeSystem.Wires.new()
	var ln := PowerPlant.line(plan)
	var y0 := PowerPlant.BASE_Y + plan.macro.relief_at(lay.gantry.pos)
	var gantry: Dictionary = (lay.gantry as Dictionary).duplicate()
	gantry["base"] = y0
	if not ln.is_empty():
		var towers: Array = ln.towers
		var sg: Dictionary = (ln.station.gantry as Dictionary).duplicate()
		sg["base"] = CityChunk.SIDEWALK_TOP + 0.05 + plan.macro.relief_at(sg.pos)
		for k in towers.size() + 1:
			var a_end: Array[Vector3]
			var b_end: Array[Vector3]
			if k == 0:
				a_end = Ridges.gantry_attach(gantry, towers[0].pos)
				b_end = Ridges.attach(towers[0], gantry.pos)
			elif k == towers.size():
				a_end = Ridges.attach(towers[k - 1], sg.pos)
				b_end = Ridges.gantry_attach(sg, towers[k - 1].pos)
			else:
				a_end = Ridges.attach(towers[k - 1], towers[k].pos)
				b_end = Ridges.attach(towers[k], towers[k - 1].pos)
			var span := Vector2(b_end[0].x - a_end[0].x, b_end[0].z - a_end[0].z)
			var across := Vector3(-span.y, 0.0, span.x).normalized() * Ridges.BUNDLE * 0.5
			var pieces := clampi(int(span.length() / 12.0), 8, 40)
			for ph in 6:
				for s: float in [-1.0, 1.0]:
					w.line(Ridges.wire(a_end[ph] + across * s, b_end[ph] + across * s, pieces), RidgeSystem.CONDUCTOR_R, 1.0, RidgeSystem.CONDUCTOR, 0)
				var ns := int(span.length() / 60.0)
				for j in ns:
					var t := float(j + 1) / float(ns + 1)
					var p: Vector3 = a_end[ph].lerp(b_end[ph], t) - Vector3(0.0, 4.0 * Ridges.sag(span.length()) * t * (1.0 - t), 0.0)
					w.seg(p - across, p + across, 0.02, 0.0, RidgeKit.STEEL_DARK, 0)
			if k > 0 and k < towers.size() or k == 0 or k == towers.size():
				for ew in [6, 7]:
					w.line(Ridges.wire(a_end[ew], b_end[ew], pieces), RidgeSystem.EARTH_R, 1.0, RidgeSystem.EARTH, 0)
		# Jumpers round the angle towers' tension strings.
		for k in towers.size():
			var t: Dictionary = towers[k]
			if int(t.kind) == Ridges.Kind.SUSPENSION:
				continue
			var prev: Vector2 = gantry.pos if k == 0 else towers[k - 1].pos
			var nxt: Vector2 = towers[k + 1].pos if k + 1 < towers.size() else sg.pos
			var pa := Ridges.attach(t, prev)
			var pb := Ridges.attach(t, nxt)
			for ph in 6:
				w.line(Ridges.wire(pa[ph], pb[ph], 8, 1.6), RidgeSystem.CONDUCTOR_R * 1.2, 1.0, RidgeSystem.CONDUCTOR, 0)
		# The towers' lattice as fine lines (collapsed where a FULL chunk built the tower).
		for t: Dictionary in towers:
			var xf := Ridges.tower_xform(t)
			var id := int(t.id) + 1
			for m: Array in RidgeKit.tower_members(float(t.h), RidgeKit._local_feet(t), true):
				w.seg(xf * (m[0] as Vector3), xf * (m[1] as Vector3), float(m[2]) * 0.5, 0.0, RidgeKit.STEEL, id)
			var sp := Ridges.spec(float(t.h))
			for side: float in [-1.0, 1.0]:
				for kk in 3:
					var tip := Vector3(side * float(sp.arm_tip[kk]), float(sp.arm_y[kk]), 0.0)
					if int(t.kind) == Ridges.Kind.SUSPENSION:
						w.seg(xf * tip, xf * (tip - Vector3(0.0, Ridges.STRING, 0.0)), 0.12, 2.0, RidgeKit.PORCELAIN, id)
	# The switchyard: the dead-end gantry (as lines: it is a part of the line) and the strain bus
	# between it and the two rows of strain gantries.
	var gxf := Transform3D(Basis(Vector3.UP, float(gantry.yaw)), Vector3((gantry.pos as Vector2).x, y0, (gantry.pos as Vector2).y))
	for m: Array in RidgeKit.gantry_members(true):
		w.seg(gxf * (m[0] as Vector3), gxf * (m[1] as Vector3), float(m[2]) * 0.6, 0.0, RidgeKit.STEEL, 0)
	var sy: Rect2 = lay.switchyard
	var gz := [(gantry.pos as Vector2).y, sy.position.y + 44.0, sy.position.y + 82.0]
	for i in 2:
		for kk in 6:
			var side := -1.0 if kk < 3 else 1.0
			var x := (gantry.pos as Vector2).x + side * (2.0 + 4.2 * float(kk % 3))
			var a := Vector3(x, y0 + Ridges.GANTRY_BEAM - 0.4, gz[i] + (Ridges.TENSION if i == 0 else 0.6))
			var b := Vector3(x, y0 + Ridges.GANTRY_BEAM - 0.4, gz[i + 1] - 0.6)
			w.line(Ridges.wire(a, b, 10, 0.8), RidgeSystem.CONDUCTOR_R * 1.4, 1.0, RidgeSystem.CONDUCTOR, 0)
			# Droppers from the strain bus down to the bays' disconnects.
			var mid := Vector3(x, y0 + Ridges.GANTRY_BEAM - 1.6, (gz[i] + gz[i + 1]) * 0.5)
			w.seg(mid, Vector3(x, y0 + 6.9, mid.z), RidgeSystem.CONDUCTOR_R * 1.4, 1.0, RidgeSystem.CONDUCTOR, 0)
	if not w.v.is_empty():
		var wires := PowerWires.new()
		wires.name = "PlantWires"
		wires.mesh = w.mesh(wire_material())
		wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wires.custom_aabb = AABB(w.lo - Vector3.ONE * 10.0, (w.hi - w.lo) + Vector3.ONE * 20.0)
		wires.extra_cull_margin = 50.0
		# Thin wires 1.8 km long: not an obstacle for AirTraffic's routes (their box would be).
		wires.set_meta("air_ignore", true)
		parent.add_child(wires)
	# The stacks' aviation lights: three round each top, three round each tall one's middle.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	var red := Color(1.0, 0.05, 0.02, 1.0)
	var n := 0
	for s: Vector3 in lay.stacks:
		var base := PowerPlant.BASE_Y + plan.macro.relief_at(Vector2(s.x, s.z))
		var levels := [s.y + 0.6]
		var r_top := PowerPlant.STACK_R1 if s.y > 60.0 else PowerPlant.HRSG_STACK_R
		if s.y > 60.0:
			levels.append(s.y * 0.52)
		for li in levels.size():
			var yy: float = levels[li]
			var rr := r_top + 0.4 if li == 0 else lerpf(PowerPlant.STACK_R0, PowerPlant.STACK_R1, 0.52) + 0.3
			for k in 3:
				var a := TAU * float(k) / 3.0 + 0.4
				var at := Vector3(s.x + cos(a) * rr, base + yy, s.z + sin(a) * rr)
				# The top ring flashes together (a beacon, one phase a stack), the middle ring burns steady.
				var code := (2.0 if li == 0 else 0.0) * 10.0 + fposmod(float(lay.stacks.find(s)) * 0.37, 1.0) * 9.0
				for kk in [0, 1, 2, 0, 2, 3]:
					st.set_color(red)
					st.set_uv(corners[kk])
					st.set_uv2(Vector2(4.2 if li == 0 else 3.0, code))
					st.set_normal(Vector3.UP)
					st.add_vertex(at)
				n += 1
	# A faint vapour plume over each heat-recovery stack (the gas units' exhaust, visible as it cools).
	if OS.get_environment("PLANT_PLUMES") != "0":
		for sk: Vector3 in lay.stacks:
			if sk.y > 60.0:
				continue
			parent.add_child(_plume(Vector3(sk.x, PowerPlant.BASE_Y + plan.macro.relief_at(Vector2(sk.x, sk.z)) + sk.y + 1.0, sk.z)))
	if n > 0:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/aircraft_lights.gdshader")
		mat.set_shader_parameter("day_level", 0.14)
		var mesh := st.commit()
		mesh.surface_set_material(0, mat)
		var lights := MeshInstance3D.new()
		lights.name = "StackLights"
		lights.mesh = mesh
		lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lights.extra_cull_margin = 16000.0
		lights.set_meta("air_ignore", true)
		parent.add_child(lights)


## A slow white plume: a few big soft puffs rising and spreading off a stack's mouth, leaning
## downwind (the sea breeze, toward +x and inland).
static func _plume(at: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "StackPlume"
	p.position = at
	p.amount = 14
	p.lifetime = 11.0
	p.preprocess = 11.0
	p.local_coords = false
	p.direction = Vector3(0.25, 1.0, 0.1)
	p.spread = 9.0
	p.initial_velocity_min = 2.2
	p.initial_velocity_max = 3.4
	p.gravity = Vector3(0.55, 0.12, 0.08)
	p.damping_min = 0.15
	p.damping_max = 0.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.6
	p.particle_flag_align_y = false
	p.scale_amount_min = 4.0
	p.scale_amount_max = 5.5
	var curve := Curve.new()
	curve.max_value = 6.0
	curve.add_point(Vector2(0.0, 0.8))
	curve.add_point(Vector2(0.4, 2.4))
	curve.add_point(Vector2(1.0, 5.2))
	p.scale_amount_curve = curve
	p.color_ramp = WeaponFX._ramp([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.0)])
	p.color = Color(0.92, 0.93, 0.94, 1.0)
	p.angle_min = -180.0
	p.angle_max = 180.0
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = WeaponFX.smoke_material()
	p.mesh = q
	p.custom_aabb = AABB(Vector3(-40.0, -5.0, -40.0), Vector3(120.0, 70.0, 80.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
