class_name GolfBuild
extends RefCounted
## Builds the part of the golf course (GolfCourse's layout) that falls in one chunk of its site,
## as that chunk's build steps (Landmarks.site_steps()). FULL chunks:
##
##   pavement   the ring of paving inside the site's kerbs (MacArthur Park's way).
##   turf       ONE mesh over the chunk's part of the course, a 1.6 m grid whose every vertex carries
##              the six distance fields (GolfCourse.field()) and the mowing direction, on
##              shaders/golf_turf.gdshader: fairways, greens with their collars, tees, bunkers, the
##              cart path, rough and native grass, all one draw. The ground is shaped from the same
##              fields (GolfCourse.shape()); a trimesh of it is the collision. Built a few rows a step.
##   water      the pond and the creek (shaders/lake.gdshader), the pond's aerating fountain.
##   props      everything upright in ONE mesh on the rec parks' walls material (ParkKit's writers):
##              flagsticks and cups, tee markers, ball washers, hole signs, yardage posts, bridges,
##              the boundary fence, the range's nets, bays, mats, shelter and target poles; the
##              flags themselves are one batch on shaders/golf_flag.gdshader (cloth in the wind).
##   planting   the trees between the holes, palms by the clubhouse and the entry drive, the hedge
##              along the boundary; a private rng per tree (a hash of its place).
##   buildings  the Spanish revival clubhouse and the pro shop (HouseKit plans built by HouseBuild),
##              the car park (LotFill's).
##   life       golfers (Golfer), sprinklers at dawn (GolfLife), golf carts (GolfLife).
##
## LOD chunks: the pavement, the turf at a 5 m grid (same shader), the water, the trees thinned, the
## buildings as HouseKit's LOD boxes and a relief floor for collision. The far city's capture
## (capture_steps()) records the buildings' boxes; Skyline asks GolfFar for the turf and canopies.

const LIFT := 0.0
## Turf grid (m): FULL and LOD.
const CELL_FULL := 1.6
const CELL_LOD := 2.5
## Rows of the turf grid built per step (FULL).
const ROWS_PER_STEP := 14
## The flag: 20 x 14 inches, on a 7 ft stick (m).
const FLAG_SIZE := Vector2(0.51, 0.36)
const STICK_HEIGHT := 2.13
## Range net height (m) and pole spacing.
const NET_HEIGHT := 16.0
const NET_SPACING := 24.0
## Boundary fence height (m).
const FENCE_HEIGHT := 1.8
## Trees a LOD chunk keeps (one in ...).
const LOD_TREE_EVERY := 2
## Far draw of the small props (m).
const FLAG_DRAW := 420.0

static var _turf_mat: ShaderMaterial
static var _flag_mesh: ArrayMesh
static var _pond_mat: ShaderMaterial
static var _creek_mat: ShaderMaterial
static var _text_mats: Dictionary = {}


static func site_steps(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var lay := GolfCourse.layout(ch.plan)
	if lay.is_empty():
		return steps
	var area := ch.owned_rect().intersection(lay.rect as Rect2)
	if area.size.x < 0.5 or area.size.y < 0.5:
		return steps
	var full := ch.level == CityChunk.Level.FULL
	var st := {"lay": lay, "area": area, "full": full, "row": 0, "tee_levels": {}}
	ch.set_meta("golf", st)
	steps.append(_pavement.bind(ch, st))
	steps.append(_turf_begin.bind(ch, st))
	# Returns false while rows remain (the chunk runs a step again until it returns true).
	steps.append(func() -> bool:
		if not _rows(ch, st):
			return false
		_turf_commit(ch, st)
		return true)
	steps.append(_water.bind(ch, st))
	steps.append(_buildings.bind(ch, st))
	if full:
		steps.append(_props.bind(ch, st))
		steps.append(_planting.bind(ch, st))
		steps.append(_car_park.bind(ch, st))
		steps.append(_life.bind(ch, st))
	else:
		steps.append(_planting.bind(ch, st))
		steps.append(ch._add_relief_floor)
	return steps


## The far city's capture of a site chunk: the buildings' boxes (HouseKit's LOD path records them).
static func capture_steps(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var lay := GolfCourse.layout(ch.plan)
	if lay.is_empty():
		return steps
	var area := ch.owned_rect().intersection(lay.rect as Rect2)
	var st := {"lay": lay, "area": area, "full": false}
	# The plate's colour: the rough's (Skyline averages the ground the capture records).
	steps.append(func() -> void:
		var turf := area.intersection(lay.walk as Rect2)
		if turf.size.x > 1.0 and turf.size.y > 1.0:
			(ch.captured.ground as Array).append([turf, GolfFar.ROUGH_FAR, CityChunk.SIDEWALK_TOP, GolfFar.ROUGH_FAR]))
	steps.append(_buildings.bind(ch, st))
	return steps


# --- Heights --------------------------------------------------------------------------------------

## The ground's height at `p` (chunk space = true world XZ) in a chunk whose state is `st`.
static func ground(ch: CityChunk, st: Dictionary, p: Vector2) -> float:
	var sub: Dictionary = st.sub
	var f := GolfCourse.field(sub, p)
	return GolfCourse.shape(sub, p, f, ch._gy(p.x, p.y) + CityChunk.SIDEWALK_TOP + LIFT, _tee_level(ch, st, p, f))


static func _tee_level(ch: CityChunk, st: Dictionary, p: Vector2, f: PackedFloat32Array) -> float:
	if f[3] >= 3.0:
		return -1e6
	var sub: Dictionary = st.sub
	var best: Variant = null
	var bd := INF
	for t: Dictionary in sub.tees:
		var d := GolfCourse.box_sdf(t, p)
		if d < bd:
			bd = d
			best = t
	var lay: Dictionary = st.lay
	var key: Variant = best
	var c: Vector2
	if best == null or bd > f[3] + 0.01:
		# The range's tee line.
		var rr: Rect2 = lay.range
		c = Vector2(rr.get_center().x, rr.end.y - 12.0)
		key = "range"
	else:
		c = (best as Dictionary).c
	var levels: Dictionary = st.tee_levels
	if levels.has(key):
		return levels[key]
	var fc := GolfCourse.field(sub, c)
	var y := GolfCourse.shape(sub, c, fc, ch._gy(c.x, c.y) + CityChunk.SIDEWALK_TOP + LIFT, -1e6)
	# The pad's top: level, standing a little proud of the ground round it.
	y = maxf(y, ch._gy(c.x, c.y) + CityChunk.SIDEWALK_TOP) + GolfCourse.TEE_LIFT * (0.6 if key is String else 1.0)
	levels[key] = y
	return y


## A batch instance's y for an absolute height (the batch adds the relief to every instance).
static func _rel(ch: CityChunk, p: Vector2, y_abs: float) -> float:
	return y_abs - ch._gy(p.x, p.y)


# --- Pavement -------------------------------------------------------------------------------------

static func _pavement(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var rect: Rect2 = lay.rect
	var walk: Rect2 = lay.walk
	var area: Rect2 = st.area
	var paving := PropFactory.road("sidewalk", 3.0, Color(1.5, 1.5, 1.48), hash([ch.plan.seed, "golf_paving"]), 1.6, 0.4)
	var strips := [
		Rect2(rect.position.x, rect.position.y, rect.size.x, GolfCourse.PAVEMENT),
		Rect2(rect.position.x, walk.end.y, rect.size.x, GolfCourse.PAVEMENT),
		Rect2(rect.position.x, walk.position.y, GolfCourse.PAVEMENT, walk.size.y),
		Rect2(walk.end.x, walk.position.y, GolfCourse.PAVEMENT, walk.size.y),
	]
	for s: Rect2 in strips:
		var part := s.intersection(area)
		if part.size.x > 0.05 and part.size.y > 0.05:
			ch._add_ground_grid(part, CityChunk.SIDEWALK_TOP, CityChunk.SIDEWALK_TOP + 0.5, paving, true, ch.style.sidewalk)


# --- Turf -----------------------------------------------------------------------------------------

static func turf_material() -> ShaderMaterial:
	if _turf_mat != null:
		return _turf_mat
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/golf_turf.gdshader")
	m.set_shader_parameter("grass_tex", PropFactory.texture("grass", "Color"))
	m.set_shader_parameter("grass_nrm", PropFactory.texture("grass", "NormalGL"))
	m.set_shader_parameter("sand_tex", PropFactory.texture("sand", "Color"))
	m.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	m.set_shader_parameter("dirt_tex", PropFactory.texture("hill_dirt", "Color"))
	_turf_mat = m
	return m


static func _turf_begin(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var walk: Rect2 = lay.walk
	var area := (st.area as Rect2).intersection(walk)
	st.turf_area = area
	st.sub = GolfCourse.gather(lay, (st.area as Rect2))
	if area.size.x < 0.5 or area.size.y < 0.5:
		st.nx = 0
		return
	var cell := CELL_FULL if st.full else CELL_LOD
	if CityChunk._detail() < 1.0:
		cell *= 1.6
	st.nx = maxi(1, ceili(area.size.x / cell))
	st.nz = maxi(1, ceili(area.size.y / cell))
	var n: int = (st.nx + 1) * (st.nz + 1)
	var v := PackedVector3Array()
	v.resize(n)
	var c := PackedColorArray()
	c.resize(n)
	var uv := PackedVector2Array()
	uv.resize(n)
	var uv2 := PackedVector2Array()
	uv2.resize(n)
	st.v = v
	st.c = c
	st.uv = uv
	st.uv2 = uv2
	st.row = 0


static func _enc(d: float) -> float:
	return clampf(0.5 + d / (GolfCourse.FIELD_REACH * 2.0), 0.0, 1.0)


## A few rows of the grid: position, fields, mowing direction. True when the grid is complete.
static func _rows(ch: CityChunk, st: Dictionary) -> bool:
	var nx: int = st.nx
	if nx == 0:
		return true
	var nz: int = st.nz
	var area: Rect2 = st.turf_area
	var sub: Dictionary = st.sub
	var v: PackedVector3Array = st.v
	var c: PackedColorArray = st.c
	var uv: PackedVector2Array = st.uv
	var uv2: PackedVector2Array = st.uv2
	var r0: int = st.row
	var r1 := mini(nz + 1, r0 + (ROWS_PER_STEP if st.full else 999))
	for j in range(r0, r1):
		var z := area.position.y + area.size.y * float(j) / float(nz)
		for i in nx + 1:
			var x := area.position.x + area.size.x * float(i) / float(nx)
			var p := Vector2(x, z)
			var f := GolfCourse.field(sub, p)
			var y := GolfCourse.shape(sub, p, f, ch._gy(x, z) + CityChunk.SIDEWALK_TOP + LIFT, _tee_level(ch, st, p, f))
			var k := j * (nx + 1) + i
			v[k] = Vector3(x, y, z)
			c[k] = Color(_enc(f[0]), _enc(f[1]), _enc(f[2]), _enc(f[3]))
			uv[k] = Vector2(clampf(f[4], -16.0, 16.0), clampf(f[5], -16.0, 16.0))
			uv2[k] = Vector2(f[6], f[7])
	st.row = r1
	# Packed arrays are values: write them back.
	st.v = v
	st.c = c
	st.uv = uv
	st.uv2 = uv2
	return r1 >= nz + 1


static func _turf_commit(ch: CityChunk, st: Dictionary) -> void:
	var nx: int = st.nx
	if nx == 0:
		return
	var nz: int = st.nz
	var v: PackedVector3Array = st.v
	var n := PackedVector3Array()
	n.resize(v.size())
	for j in nz + 1:
		for i in nx + 1:
			var k := j * (nx + 1) + i
			var l := v[j * (nx + 1) + maxi(i - 1, 0)]
			var r := v[j * (nx + 1) + mini(i + 1, nx)]
			var d := v[maxi(j - 1, 0) * (nx + 1) + i]
			var u := v[mini(j + 1, nz) * (nx + 1) + i]
			n[k] = (u - d).cross(r - l).normalized()
	var idx := PackedInt32Array()
	idx.resize(nx * nz * 6)
	var faces := PackedVector3Array()
	var collide: bool = st.full
	if collide:
		faces.resize(nx * nz * 6)
	var w := 0
	for j in nz:
		for i in nx:
			var k00 := j * (nx + 1) + i
			var k10 := k00 + 1
			var k01 := k00 + nx + 1
			var k11 := k01 + 1
			for q: int in [k00, k10, k01, k10, k11, k01]:
				idx[w] = q
				if collide:
					faces[w] = v[q]
				w += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = st.c
	arrays[Mesh.ARRAY_TEX_UV] = st.uv
	arrays[Mesh.ARRAY_TEX_UV2] = st.uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "GolfTurf"
	mi.mesh = mesh
	mi.material_override = turf_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ch.add_child(mi)
	if collide and ch._statics:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.name = "GolfTurfShape"
		cs.shape = shape
		ch._statics.add_child(cs)
	st.erase("c")
	st.erase("uv")
	st.erase("uv2")
	st.grid = v


# --- Water ----------------------------------------------------------------------------------------

static func _water_mat(pond: bool, lay: Dictionary) -> ShaderMaterial:
	if pond:
		if _pond_mat == null:
			_pond_mat = ShaderMaterial.new()
			_pond_mat.shader = load("res://shaders/lake.gdshader")
		_pond_mat.set_shader_parameter("fountain_at", lay.fountain)
		_pond_mat.set_shader_parameter("fountain_reach", 16.0)
		_pond_mat.set_shader_parameter("fountain_foam", 3.2)
		return _pond_mat
	if _creek_mat == null:
		_creek_mat = ShaderMaterial.new()
		_creek_mat.shader = load("res://shaders/lake.gdshader")
		_creek_mat.set_shader_parameter("fountain_at", Vector2(1e6, 1e6))
		_creek_mat.set_shader_parameter("ruffle", 0.8)
		_creek_mat.set_shader_parameter("ruffle_scale", 1.4)
	return _creek_mat


static func _water(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var area: Rect2 = st.area
	var level: float = lay.pond_level
	if (lay.pond_bounds as Rect2).grow(1.0).intersects(area):
		var area_poly := PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
		var sw := SurfaceTool.new()
		sw.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any := false
		# The surface reaches a little past the waterline, under the bank (no gap at the shore).
		var poly := Geometry2D.offset_polygon(lay.pond, 0.7)
		for piece: PackedVector2Array in poly:
			for cut: PackedVector2Array in Geometry2D.intersect_polygons(piece, area_poly):
				var tri := Geometry2D.triangulate_polygon(cut)
				for k in range(0, tri.size(), 3):
					for q: int in [tri[k], tri[k + 2], tri[k + 1]]:
						sw.set_normal(Vector3.UP)
						sw.add_vertex(Vector3(cut[q].x, level, cut[q].y))
					any = true
		if any:
			_water_node(ch, sw, true, lay, "GolfPond")
		var f: Vector2 = lay.fountain
		if st.full and area.has_point(f):
			_fountain(ch, Vector3(f.x, level, f.y))
	# The creek: a ribbon down its line at its own (falling) level, a little wider than its bed.
	var creek: PackedVector2Array = lay.creek
	var levels: PackedFloat32Array = lay.creek_levels
	var sc := SurfaceTool.new()
	sc.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_c := false
	var hw := GolfCourse.CREEK_HALF + 0.5
	for k in creek.size() - 1:
		var a := creek[k]
		var b := creek[k + 1]
		if not area.has_point((a + b) * 0.5):
			continue
		var da := (creek[mini(k + 1, creek.size() - 1)] - creek[maxi(k - 1, 0)]).normalized()
		var db := (creek[mini(k + 2, creek.size() - 1)] - creek[k]).normalized()
		var na := Vector2(-da.y, da.x) * hw
		var nb := Vector2(-db.y, db.x) * hw
		var ya := levels[k]
		var yb := levels[k + 1]
		var quad := [Vector3(a.x - na.x, ya, a.y - na.y), Vector3(a.x + na.x, ya, a.y + na.y), Vector3(b.x + nb.x, yb, b.y + nb.y), Vector3(b.x - nb.x, yb, b.y - nb.y)]
		_up_quad(sc, quad[0], quad[1], quad[2], quad[3])
		any_c = true
	if any_c:
		_water_node(ch, sc, false, lay, "GolfCreek")


static func _up_quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var order := [a, b, c, a, c, d]
	if (c - a).cross(b - a).y < 0.0:
		order = [a, c, b, a, d, c]
	for p: Vector3 in order:
		s.set_normal(Vector3.UP)
		s.add_vertex(p)


static func _water_node(ch: CityChunk, s: SurfaceTool, pond: bool, lay: Dictionary, node_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = s.commit()
	mi.material_override = _water_mat(pond, lay)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ch.add_child(mi)


## The pond's aerating fountain: a white column and a plume of spray falling back round it.
static func _fountain(ch: CityChunk, at: Vector3) -> void:
	var h := 4.5
	var column := MeshInstance3D.new()
	column.name = "GolfFountainJet"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.42
	cyl.height = h * 0.9
	cyl.radial_segments = 12
	cyl.rings = 4
	column.mesh = cyl
	var jm := StandardMaterial3D.new()
	jm.albedo_color = Color(0.9, 0.93, 0.94, 0.62)
	jm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jm.roughness = 0.2
	jm.emission_enabled = true
	jm.emission = Color(0.16, 0.17, 0.18)
	jm.cull_mode = BaseMaterial3D.CULL_DISABLED
	column.material_override = jm
	column.position = at + Vector3(0.0, h * 0.45, 0.0)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column.visibility_range_end = 350.0
	ch.add_child(column)
	var plume := CPUParticles3D.new()
	plume.name = "GolfFountainPlume"
	plume.amount = 70 if CityChunk._detail() >= 1.0 else 30
	plume.lifetime = 2.6
	plume.preprocess = 2.6
	plume.direction = Vector3.UP
	plume.spread = 7.0
	var vel := sqrt(2.0 * 9.8 * h)
	plume.initial_velocity_min = vel * 0.8
	plume.initial_velocity_max = vel
	plume.gravity = Vector3(0.0, -9.8, 0.0)
	plume.scale_amount_min = 0.25
	plume.scale_amount_max = 0.6
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var pm := StandardMaterial3D.new()
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.billboard_keep_scale = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_texture = WeaponFX.puff_texture()
	pm.albedo_color = Color(0.92, 0.95, 0.96, 0.32)
	pm.vertex_color_use_as_albedo = true
	q.material = pm
	plume.mesh = q
	plume.position = at
	plume.custom_aabb = AABB(Vector3(-5.0, -1.0, -5.0), Vector3(10.0, h + 3.0, 10.0))
	plume.visibility_range_end = 220.0
	ch.add_child(plume)


# --- Props ----------------------------------------------------------------------------------------

static func flag_mesh() -> ArrayMesh:
	if _flag_mesh != null:
		return _flag_mesh
	# A cloth flag: a grid off the stick along +X (UV.x 0 at the stick, 1 at the fly end), its top
	# at y 0 (the instance sits at the top of the stick). Both faces; the shader waves it.
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 10
	var nv := 6
	for j in nv:
		for i in nu:
			var u0 := float(i) / nu
			var u1 := float(i + 1) / nu
			var v0 := float(j) / nv
			var v1 := float(j + 1) / nv
			var quad := [[u0, v0], [u1, v0], [u1, v1], [u0, v1]]
			for tri: Array in [[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]]:
				var front := tri == [0, 1, 2] or tri == [0, 2, 3]
				for q: int in tri:
					var uvq: Array = quad[q]
					s.set_normal(Vector3(0.0, 0.0, 1.0 if front else -1.0))
					s.set_uv(Vector2(uvq[0], uvq[1]))
					s.add_vertex(Vector3(float(uvq[0]) * FLAG_SIZE.x, -float(uvq[1]) * FLAG_SIZE.y, 0.0))
	_flag_mesh = s.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/golf_flag.gdshader")
	_flag_mesh.surface_set_material(0, m)
	return _flag_mesh


## Hole flags: yellow on the front nine (a course this size has only it), a few clubs use red.
const FLAG_COLORS := [Color(0.95, 0.80, 0.08), Color(0.86, 0.12, 0.08), Color(0.95, 0.95, 0.93)]


static func _props(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var area: Rect2 = st.area
	var ps := ch.plan.seed
	var w := SurfaceTool.new()
	w.begin(Mesh.PRIMITIVE_TRIANGLES)
	w.set_smooth_group(-1)
	var flag_color: Color = FLAG_COLORS[absi(hash([ps, "golf_flag_c"])) % FLAG_COLORS.size()]
	var flag := flag_mesh()
	for h: Dictionary in lay.holes:
		# The pin: the stick, its cup ring, and the flag at the top.
		var pin: Vector2 = h.pin
		if area.has_point(pin):
			var y := ground(ch, st, pin)
			ParkKit.post(w, Vector3(pin.x, y - 0.1, pin.y), 0.0125, STICK_HEIGHT + 0.1, ParkKit.K_PLASTIC, Color(0.95, 0.85, 0.12) if flag_color.b > 0.5 else Color(0.95, 0.95, 0.93), 6)
			ParkKit.post(w, Vector3(pin.x, y - 0.004, pin.y), 0.06, 0.012, ParkKit.K_RUBBER, Color(0.03, 0.03, 0.03), 12)
			var yaw := _wind_yaw(ch, pin)
			ch._batch.add("golf_flag", flag, Transform3D(Basis(Vector3.UP, yaw), Vector3(pin.x, _rel(ch, pin, y + STICK_HEIGHT - 0.02), pin.y)), flag_color, Color(GolfCourse.h01([ps, "flag", h.n]), 0.0, 0.0, 0.0))
		# Tee markers: a pair on the front edge of each box, in its colour.
		for t: Dictionary in h.tees:
			var c: Vector2 = t.c
			if not area.has_point(c):
				continue
			var u: Vector2 = t.u
			var half: Vector2 = t.half
			var side := Vector2(-u.y, u.x)
			for sgn: float in [-1.0, 1.0]:
				var q := c + u * (half.y - 1.2) + side * sgn * 2.6
				var y := ground(ch, st, q)
				ParkKit.post(w, Vector3(q.x, y - 0.02, q.y), 0.06, 0.13, ParkKit.K_PLASTIC, t.color, 8)
	# Signs, washers, benches, yardage posts.
	for b: Array in lay.bins:
		var p: Vector2 = b[1]
		if not area.has_point(p):
			continue
		var y := ground(ch, st, p)
		match String(b[0]):
			"washer":
				ParkKit.post(w, Vector3(p.x, y, p.y), 0.035, 0.92, ParkKit.K_STEEL, Color(0.10, 0.22, 0.14), 8)
				ParkKit.box(w, Transform3D(Basis(Vector3.UP, float(b[2])), Vector3(p.x, y + 1.02, p.y)), Vector3(0.22, 0.26, 0.17), ParkKit.K_PLASTIC, Color(0.12, 0.30, 0.18))
				ParkKit.post(w, Vector3(p.x, y, p.y) + Basis(Vector3.UP, float(b[2])) * Vector3(0.0, 1.15, 0.0), 0.012, 0.18, ParkKit.K_STEEL, Color(0.75, 0.75, 0.72), 6)
				ParkKit.box(w, Transform3D(Basis(Vector3.UP, float(b[2])), Vector3(p.x, y + 0.03, p.y)), Vector3(0.5, 0.06, 0.5), ParkKit.K_CONCRETE, ParkKit.CONCRETE)
			"bench":
				ch._add_bench(Vector3(p.x, _rel(ch, p, y), p.y), float(b[2]))
			"sign":
				_hole_sign(ch, w, p, y, float(b[2]), b[3])
			"yardage":
				var yd := int(b[3])
				var paint := Color(0.75, 0.1, 0.08) if yd == 100 else (Color(0.94, 0.94, 0.92) if yd == 150 else Color(0.12, 0.22, 0.6))
				ParkKit.box(w, Transform3D(Basis(), Vector3(p.x, y + 0.35, p.y)), Vector3(0.1, 0.7, 0.1), ParkKit.K_WOOD, ParkKit.WOOD)
				ParkKit.box(w, Transform3D(Basis(), Vector3(p.x, y + 0.75, p.y)), Vector3(0.12, 0.12, 0.12), ParkKit.K_PLASTIC, paint)
			"plate":
				var yd2 := int(b[3])
				var paint2 := Color(0.75, 0.1, 0.08) if yd2 == 100 else (Color(0.94, 0.94, 0.92) if yd2 == 150 else Color(0.12, 0.22, 0.6))
				ParkKit.post(w, Vector3(p.x, y - 0.03, p.y), 0.14, 0.04, ParkKit.K_PLASTIC, paint2, 10)
	_bridges(ch, st, w)
	_range(ch, st, w)
	_fence(ch, st, w)
	_practice_green(ch, st, w)
	var mesh := w.commit()
	if mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "GolfWalls"
		mi.mesh = mesh
		mi.material_override = Parks.walls_material()
		ch.add_child(mi)
	ch._batch.set_no_shadow("golf_flag")
	ch._batch.set_no_shadow("golf_balls")


## Which way the flags fly: one wind for the whole course (a hash), a little each way per flag.
static func _wind_yaw(ch: CityChunk, p: Vector2) -> float:
	return GolfCourse.hrange(0.0, TAU, [ch.plan.seed, "golf_wind"]) + GolfCourse.hrange(-0.35, 0.35, [int(p.x), int(p.y)])


## A hole's sign by its back tee: a timber board on two posts with the number, par and yardage.
static func _hole_sign(ch: CityChunk, w: SurfaceTool, p: Vector2, y: float, yaw: float, h: Dictionary) -> void:
	var b := Basis(Vector3.UP, yaw)
	for sx: float in [-0.42, 0.42]:
		ParkKit.box(w, Transform3D(b, Vector3(p.x, y + 0.55, p.y) + b * Vector3(sx, 0.0, 0.0)), Vector3(0.1, 1.1, 0.1), ParkKit.K_WOOD, ParkKit.WOOD * 0.8)
	ParkKit.box(w, Transform3D(b, Vector3(p.x, y + 1.05, p.y)), Vector3(1.05, 0.62, 0.08), ParkKit.K_WOOD, Color(0.36, 0.25, 0.16))
	ParkKit.box(w, Transform3D(b, Vector3(p.x, y + 1.05, p.y) + b * Vector3(0.0, 0.0, 0.045)), Vector3(0.94, 0.52, 0.012), ParkKit.K_PLASTIC, Color(0.10, 0.26, 0.17))
	if OS.has_feature("web"):
		return
	var text := "%d\nPAR %d   %d YDS" % [int(h.n), int(h.par), int(h.yards)]
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = 22
	tm.pixel_size = 0.0072
	tm.depth = 0.004
	tm.line_spacing = -4.0
	tm.material = _text_material(Color(0.95, 0.93, 0.86))
	var mi := MeshInstance3D.new()
	mi.name = "GolfSign%d" % int(h.n)
	mi.mesh = tm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 60.0
	mi.transform = Transform3D(b, Vector3(p.x, y + 1.05, p.y) + b * Vector3(0.0, 0.0, 0.054))
	ch.add_child(mi)


static func _text_material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _text_mats.has(key):
		return _text_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	_text_mats[key] = m
	return m


## Timber bridges where the cart path crosses the creek: a deck on two beams, rails each side.
static func _bridges(ch: CityChunk, st: Dictionary, w: SurfaceTool) -> void:
	var lay: Dictionary = st.lay
	for br: Array in lay.bridges:
		var c: Vector2 = br[0]
		if not (st.area as Rect2).has_point(c):
			continue
		var dir: Vector2 = br[1]
		var span: float = br[2]
		var a := c - dir * span * 0.5
		var b := c + dir * span * 0.5
		var ya := ground(ch, st, a)
		var yb := ground(ch, st, b)
		var deck := maxf(ya, yb) + 0.12
		var yaw := atan2(dir.x, dir.y)
		var basis := Basis(Vector3.UP, yaw)
		var mid := Vector3(c.x, deck, c.y)
		ParkKit.box(w, Transform3D(basis, mid - Vector3(0.0, 0.06, 0.0)), Vector3(3.0, 0.12, span + 1.0), ParkKit.K_WOOD, Color(0.50, 0.38, 0.26))
		for sx: float in [-1.35, 1.35]:
			ParkKit.box(w, Transform3D(basis, mid + basis * Vector3(sx, -0.3, 0.0)), Vector3(0.25, 0.4, span + 1.0), ParkKit.K_WOOD, Color(0.36, 0.27, 0.19))
			for k in 5:
				var t := -span * 0.5 + span * float(k) / 4.0
				ParkKit.box(w, Transform3D(basis, mid + basis * Vector3(sx * 1.05, 0.5, t)), Vector3(0.12, 1.0, 0.12), ParkKit.K_WOOD, Color(0.45, 0.34, 0.23))
			ParkKit.box(w, Transform3D(basis, mid + basis * Vector3(sx * 1.05, 1.02, 0.0)), Vector3(0.14, 0.08, span + 0.2), ParkKit.K_WOOD, Color(0.45, 0.34, 0.23))
		ch._add_shape(Vector3(3.0, 0.24, span + 1.0), mid - Vector3(0.0, 0.12, 0.0), yaw)


## The driving range: tall nets on poles down both sides and across the far end, a covered tee
## line of bays with mats and dividers, yardage boards and flags on the target greens, and a
## scatter of balls.
static func _range(ch: CityChunk, st: Dictionary, w: SurfaceTool) -> void:
	var lay: Dictionary = st.lay
	var area: Rect2 = st.area
	var r: Rect2 = lay.range
	if not r.grow(2.0).intersects(area):
		return
	var ps := ch.plan.seed
	var cs := [Vector2(r.position.x, r.end.y - 4.0), r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - 4.0)]
	for e in 3:
		var a: Vector2 = cs[e]
		var b: Vector2 = cs[e + 1]
		var len := a.distance_to(b)
		var n := maxi(1, ceili(len / NET_SPACING))
		for i in n + 1:
			var p := a.lerp(b, float(i) / float(n))
			if not area.has_point(p):
				continue
			var y := ground(ch, st, p)
			ParkKit.post(w, Vector3(p.x, y - 0.3, p.y), 0.16, NET_HEIGHT + 0.3, ParkKit.K_GALV, ParkKit.GALV, 10)
			if i < n:
				var q := a.lerp(b, float(i + 1) / float(n))
				var yq := ground(ch, st, q)
				var mid := (p + q) * 0.5
				var d := (q - p).normalized()
				var basis := Basis(Vector3(d.x, 0.0, d.y), Vector3.UP, Vector3(d.x, 0.0, d.y).cross(Vector3.UP)).orthonormalized()
				var base := minf(y, yq)
				ParkKit.box(w, Transform3D(basis, Vector3(mid.x, base + NET_HEIGHT * 0.5 + 0.2, mid.y)), Vector3(p.distance_to(q), NET_HEIGHT - 0.4, 0.02), ParkKit.K_NET, Color(0.1, 0.1, 0.1), 0.12, 48)
				ParkKit.beam(w, Vector3(p.x, y + NET_HEIGHT - 0.1, p.y), Vector3(q.x, yq + NET_HEIGHT - 0.1, q.y), 0.03, 0.03, ParkKit.K_GALV, ParkKit.GALV)
	# The tee line: bays under a shelter along the south end.
	var ty := r.end.y - 12.0
	var tl := r.position.x + 3.0
	var tr := r.end.x - 3.0
	var tc := Vector2((tl + tr) * 0.5, ty)
	if area.has_point(tc):
		var yb := _tee_level(ch, st, tc, GolfCourse.field(st.sub, tc))
		if yb < -1e5:
			yb = ground(ch, st, tc)
		var bays := int((tr - tl) / 3.2)
		for i in bays + 1:
			var x := tl + (tr - tl) * float(i) / float(bays)
			ParkKit.box(w, Transform3D(Basis(), Vector3(x, yb + 0.6, ty + 1.8)), Vector3(0.06, 1.2, 2.4), ParkKit.K_WOOD, Color(0.30, 0.34, 0.24))
			if i < bays:
				var mx := x + (tr - tl) / float(bays) * 0.5
				ParkKit.box(w, Transform3D(Basis(), Vector3(mx, yb + 0.012, ty + 0.4)), Vector3(1.5, 0.025, 1.5), ParkKit.K_RUBBER, Color(0.10, 0.30, 0.13))
				ParkKit.box(w, Transform3D(Basis(), Vector3(mx + 0.55, yb + 0.15, ty + 1.6)), Vector3(0.36, 0.3, 0.36), ParkKit.K_PLASTIC, Color(0.20, 0.38, 0.62))
		# The shelter: a standing-seam roof on columns over the back of the bays.
		var depth := 7.0
		var roof_y := yb + 3.4
		for i in 5:
			var x := tl + (tr - tl) * float(i) / 4.0
			for zz: float in [ty + 1.2, ty + depth]:
				ParkKit.post(w, Vector3(x, yb, zz), 0.1, 3.4, ParkKit.K_STEEL, Color(0.20, 0.24, 0.20), 8)
		ParkKit.box(w, Transform3D(Basis(Vector3.RIGHT, -0.06), Vector3(tc.x, roof_y + 0.1, ty + depth * 0.55)), Vector3(tr - tl + 1.6, 0.14, depth + 1.6), ParkKit.K_CANOPY, Color(0.24, 0.30, 0.25))
		ch._add_shape(Vector3(tr - tl + 1.6, 0.3, depth + 1.6), Vector3(tc.x, roof_y + 0.1, ty + depth * 0.55))
	# The target greens' flags and yardage boards.
	var flag := flag_mesh()
	for g: Dictionary in lay.range_targets:
		var c: Vector2 = g.c
		if not area.has_point(c):
			continue
		var y := ground(ch, st, c)
		ParkKit.post(w, Vector3(c.x, y - 0.1, c.y), 0.03, 3.2, ParkKit.K_PLASTIC, Color(0.95, 0.95, 0.93), 6)
		ch._batch.add("golf_flag", flag, Transform3D(Basis(Vector3.UP, _wind_yaw(ch, c)).scaled(Vector3(1.6, 1.6, 1.6)), Vector3(c.x, _rel(ch, c, y + 3.05), c.y)), FLAG_COLORS[int(g.yards) / 50 % 3], Color(GolfCourse.h01([ps, "rflag", g.yards]), 0.0, 0.0, 0.0))
		var bp := c + Vector2(float(g.a) + 3.0, 0.0)
		var by := ground(ch, st, bp)
		for sx: float in [-0.9, 0.9]:
			ParkKit.box(w, Transform3D(Basis(), Vector3(bp.x + sx, by + 0.7, bp.y)), Vector3(0.1, 1.4, 0.1), ParkKit.K_WOOD, ParkKit.WOOD)
		ParkKit.box(w, Transform3D(Basis(), Vector3(bp.x, by + 1.3, bp.y)), Vector3(2.1, 0.9, 0.08), ParkKit.K_PLASTIC, Color(0.94, 0.94, 0.92))
		if not OS.has_feature("web"):
			var tm := TextMesh.new()
			tm.text = str(g.yards)
			tm.font_size = 64
			tm.pixel_size = 0.009
			tm.depth = 0.01
			tm.material = _text_material(Color(0.10, 0.12, 0.14))
			var mi := MeshInstance3D.new()
			mi.mesh = tm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 320.0
			mi.position = Vector3(bp.x, by + 1.3, bp.y + 0.05)
			ch.add_child(mi)
	# Range balls: a scatter between the tee line and the far net (one batch, no shadow).
	var ball := PropFactory.cylinder("golf_ball", 0.0214, 0.0428, Color(0.96, 0.96, 0.94), 0.0214, 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ps, "golf_range_balls", ch.ix, ch.iz])
	var inner := r.grow(-2.0).intersection(area)
	if inner.size.x > 1.0 and inner.size.y > 1.0:
		var count := int(inner.get_area() / 14.0)
		for i in mini(count, 700):
			var p := Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
			if p.y > ty - 4.0:
				continue
			# Most balls land between 100 and 220 yards.
			var dist := (ty - p.y) / 0.9144
			if rng.randf() > exp(-pow((dist - 165.0) / 75.0, 2.0)) * 0.9 + 0.08:
				continue
			var y := ground(ch, st, p)
			ch._batch.add("golf_balls", ball, Transform3D(Basis(), Vector3(p.x, _rel(ch, p, y + 0.02), p.y)))


## The boundary fence: chain-link round the course inside the hedge, open at the car park's way in
## and the clubhouse forecourt; the range's nets stand in for it on the range's side.
static func _fence(ch: CityChunk, st: Dictionary, w: SurfaceTool) -> void:
	var lay: Dictionary = st.lay
	var area: Rect2 = st.area
	var walk: Rect2 = lay.walk
	var f := walk.grow(-2.2)
	var park: Rect2 = lay.park
	var fore: Rect2 = lay.forecourt
	var r: Rect2 = lay.range
	var cs := [f.position, Vector2(f.end.x, f.position.y), f.end, Vector2(f.position.x, f.end.y)]
	for e in 4:
		var a: Vector2 = cs[e]
		var b: Vector2 = cs[(e + 1) % 4]
		var len := a.distance_to(b)
		var n := ceili(len / 6.0)
		for i in n:
			var p := a.lerp(b, float(i) / float(n))
			var q := a.lerp(b, float(i + 1) / float(n))
			var mid := (p + q) * 0.5
			if not area.has_point(mid):
				continue
			if park.grow(1.0).has_point(mid) or fore.grow(1.0).has_point(mid) or r.grow(3.0).has_point(mid):
				continue
			ParkKit.fence(w, Vector3(p.x, ground(ch, st, p), p.y), Vector3(q.x, ground(ch, st, q), q.y), FENCE_HEIGHT, false, true)


## The practice putting green's little flags (no sticks of their own colour: short white ones).
static func _practice_green(ch: CityChunk, st: Dictionary, w: SurfaceTool) -> void:
	var lay: Dictionary = st.lay
	var g: Dictionary = lay.putt
	var c: Vector2 = g.c
	if not (st.area as Rect2).has_point(c):
		return
	for k in int(g.pins):
		var a := TAU * float(k) / float(g.pins) + 0.4
		var p := c + Vector2(cos(a) * float(g.a), sin(a) * float(g.b)) * 0.6
		var y := ground(ch, st, p)
		ParkKit.post(w, Vector3(p.x, y - 0.05, p.y), 0.008, 0.6, ParkKit.K_PLASTIC, Color(0.95, 0.95, 0.93), 5)
		ParkKit.box(w, Transform3D(Basis(Vector3.UP, a), Vector3(p.x, y + 0.48, p.y) + Basis(Vector3.UP, a) * Vector3(0.07, 0.0, 0.0)), Vector3(0.14, 0.09, 0.004), ParkKit.K_PLASTIC, Color(0.9, 0.15, 0.1))
		ParkKit.post(w, Vector3(p.x, y - 0.004, p.y), 0.055, 0.01, ParkKit.K_RUBBER, Color(0.03, 0.03, 0.03), 10)


# --- Planting -------------------------------------------------------------------------------------




static func _planting(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var area: Rect2 = st.area
	var full: bool = st.full
	var ps := ch.plan.seed
	var k := 0
	for t: Array in lay.trees:
		var p: Vector2 = t[0]
		if not area.has_point(p):
			continue
		k += 1
		if not full and k % LOD_TREE_EVERY != 0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([ps, "golf_tree", int(p.x * 10.0), int(p.y * 10.0)])
		var y := ground(ch, st, p) if st.has("sub") else ch._gy(p.x, p.y) + CityChunk.SIDEWALK_TOP
		var at := Vector3(p.x, _rel(ch, p, y - 0.05), p.y)
		var yaw := rng.randf_range(0.0, TAU)
		var tint := Color(rng.randf_range(0.86, 1.08), rng.randf_range(0.9, 1.08), rng.randf_range(0.85, 1.02))
		var variety := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.3, 1.0))
		match int(t[1]):
			0:
				var s := PropFactory.city_tree_scale(0, lerpf(7.0, 9.5, float(t[2])))
				ch._batch.add("tree_0", PropFactory.model_tree(0), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint, variety)
			1:
				var s := PropFactory.hill_tree_scale(1, lerpf(15.0, 21.0, float(t[2])))
				ch._batch.add("hill_tree_1", PropFactory.model_hill_tree(1), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint, variety)
			2:
				var s := PropFactory.city_tree_scale(4, lerpf(9.0, 12.0, float(t[2])))
				ch._batch.add("tree_4", PropFactory.model_tree(4), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint, variety)
			4:
				var s := PropFactory.hill_tree_scale(0, lerpf(11.0, 15.0, float(t[2])))
				ch._batch.add("hill_tree_0", PropFactory.model_hill_tree(0), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint, variety)
			_:
				ch._add_palm(at, rng, false)
	if not full:
		return
	# The hedge along the boundary, outside the fence: one species, a shrub every 1.6 m.
	var walk: Rect2 = lay.walk
	var hedge := walk.grow(-0.9)
	var pick := absi(hash([ps, "golf_hedge"])) % 3
	var park: Rect2 = lay.park
	var fore: Rect2 = lay.forecourt
	var cs := [hedge.position, Vector2(hedge.end.x, hedge.position.y), hedge.end, Vector2(hedge.position.x, hedge.end.y)]
	for e in 4:
		var a: Vector2 = cs[e]
		var b: Vector2 = cs[(e + 1) % 4]
		var n := int(a.distance_to(b) / 1.6)
		for i in n:
			var p := a.lerp(b, (float(i) + 0.5) / float(n))
			if not area.has_point(p) or park.grow(1.5).has_point(p) or fore.grow(1.5).has_point(p):
				continue
			var hs := hash([ps, "golf_hedge", int(p.x * 4.0), int(p.y * 4.0)])
			var sc := 1.1 + float(absi(hs) % 100) / 250.0
			var basis := Basis(Vector3.UP, float(absi(hs) % 628) / 100.0).scaled(Vector3(sc, sc * 1.15, sc))
			var y := ch._gy(p.x, p.y) + CityChunk.SIDEWALK_TOP
			ch._batch.add("bush_%d" % pick, PropFactory.model_bush(pick), Transform3D(basis, Vector3(p.x, _rel(ch, p, y), p.y)), Color(0.9, 1.0, 0.92))


# --- Buildings ------------------------------------------------------------------------------------

## The clubhouse (and, in the range's chunk, the pro shop) as HouseKit plans: a Spanish revival
## building of real size, built by HouseBuild into the chunk's house meshes (or LOD boxes).
static func _buildings(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var area := ch.owned_rect()
	var club: Rect2 = lay.club
	if area.has_point(club.get_center()):
		HouseKit.build(ch, clubhouse_plan(ch.plan, lay))
	var shop: Rect2 = lay.shop
	if area.has_point(shop.get_center()):
		HouseKit.build(ch, shop_plan(ch.plan, lay))


## The clubhouse: a two-storey hipped main block, single-storey gabled wings either side (the grill
## and the locker rooms), a front-gabled entrance with the arched door, a three-storey tower, clay
## tile, white stucco and dark timber trim. Its front (low v) faces the street to the south.
static func clubhouse_plan(plan: CityPlan, lay: Dictionary) -> Dictionary:
	var club: Rect2 = lay.club
	var f := YardFill._frame(club, 1)
	var U: float = f.U
	var s := absi(hash([plan.seed, "golf_club"]))
	var h := {"f": f, "side": 1, "yard": club, "walk_front": false, "style": HouseKit.Style.SPANISH, "seed": s,
		"wings": [], "porch": {}, "door": {}, "garage": {}, "drive": Vector2.ZERO, "drive_v": 0.0, "door_u": U * 0.5,
		"door_v": 6.0, "chimney": {}, "solar": false, "vents": 0, "breeze": Rect2(), "roof_mat": "h_roof",
		"shingle_kind": 0, "pitch": 0.3, "eave": 0.45, "beach": false}
	var cu := U * 0.5
	var main := HouseKit._wing(HouseKit._rect(cu - 22.0, 8.0, cu + 22.0, 24.0), 2, "hip", "main")
	main["arch"] = true
	h.wings.append(main)
	var west := HouseKit._wing(HouseKit._rect(cu - 44.0, 10.0, cu - 22.0, 30.0), 1, "gable", "wing", 1)
	west["arch"] = true
	h.wings.append(west)
	var east := HouseKit._wing(HouseKit._rect(cu + 22.0, 10.0, cu + 44.0, 32.0), 1, "gable", "wing", 1)
	h.wings.append(east)
	var entry := HouseKit._wing(HouseKit._rect(cu - 5.0, 3.0, cu + 5.0, 8.01), 1, "gable", "wing", 2)
	entry["arch"] = true
	entry["roof_back"] = 5.0 + 0.45 + 0.4
	h.wings.append(entry)
	var tower := HouseKit._wing(HouseKit._rect(cu + 14.0, 4.0, cu + 20.0, 10.0), 3, "hip", "wing")
	h.wings.append(tower)
	HouseKit._door(h, 3, cu, "arch_door")
	h.porch = {"r": HouseKit._rect(cu - 3.5, 0.6, cu + 3.5, 3.0), "kind": "stoop", "top": HouseKit.FLOOR_LIFT}
	h.door_v = 0.6
	h.chimney = {"wing": 1, "end": 0, "mat": "h_wall"}
	HouseKit._colors(h, plan.seed, s, false)
	h.colors.wall = Color(0.95, 0.93, 0.88)
	h.colors.trim = Color(0.30, 0.20, 0.13)
	h.colors.frame = Color(0.30, 0.20, 0.13)
	h.colors.clay = Color(1.0, 1.0, 1.0)
	h["height"] = 3.0 * HouseKit.STOREY + 3.0
	return h


## The pro shop by the range's tee line: one storey, gabled, its door to the range.
static func shop_plan(plan: CityPlan, lay: Dictionary) -> Dictionary:
	var shop: Rect2 = lay.shop
	var f := YardFill._frame(shop, 0)
	var U: float = f.U
	var V: float = f.V
	var s := absi(hash([plan.seed, "golf_shop"]))
	var h := {"f": f, "side": 0, "yard": shop, "walk_front": false, "style": HouseKit.Style.SPANISH, "seed": s,
		"wings": [], "porch": {}, "door": {}, "garage": {}, "drive": Vector2.ZERO, "drive_v": 0.0, "door_u": U * 0.5,
		"door_v": 1.0, "chimney": {}, "solar": false, "vents": 0, "breeze": Rect2(), "roof_mat": "h_roof",
		"shingle_kind": 0, "pitch": 0.28, "eave": 0.4, "beach": false}
	var main := HouseKit._wing(HouseKit._rect(1.0, 1.0, U - 1.0, V - 1.0), 1, "gable", "main", 1)
	main["arch"] = true
	h.wings.append(main)
	HouseKit._door(h, 0, U * 0.5, "arch_door")
	HouseKit._colors(h, plan.seed, s, false)
	h.colors.wall = Color(0.95, 0.93, 0.88)
	h.colors.trim = Color(0.30, 0.20, 0.13)
	h.colors.frame = Color(0.30, 0.20, 0.13)
	h["height"] = HouseKit.STOREY + 2.0
	return h


static func _car_park(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var park: Rect2 = lay.park
	if ch.owned_rect().has_point(park.get_center()):
		LotFill._car_park(ch, park, absi(hash([ch.plan.seed, "golf_park"])))


# --- Life -----------------------------------------------------------------------------------------

static func _life(ch: CityChunk, st: Dictionary) -> void:
	GolfLife.chunk_built(ch, st)
