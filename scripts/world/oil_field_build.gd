class_name OilFieldBuild
extends RefCounted
## Builds the oil field (OilField's data, OilKit's hardware) into the chunks that stand on its site
## (Landmarks.site_steps()), the far city's capture of them, the field's lights (a landmark, near and
## far alike) and the single well sites in the city's lots (CityChunk._build_lot()).
##
## A FULL chunk of the field: the pavement ring along its streets; the hill's ground (one mesh on
## the hills' own terrain material, the gullies in its drainage colour, its own trimesh collision);
## the dirt lease roads and gravel pads (one mesh, shaders/oil_dirt.gdshader, no shadow); the
## pumpjacks (one MultiMesh, animated by shaders/pumpjack.gdshader); everything else - tank
## batteries in their berms with catwalks and stairs, heater-treaters, drilling rigs (substructure,
## mast, doghouse, pipe racks, mud tanks, generator sets), pipe runs on supports, the power line,
## the perimeter fence and its gates, the operator's signs - ONE mesh on IndustrialKit's walls
## material; light pools after dark. A LOD chunk: the pavement, a coarse ground, the dirt, the far
## pumpjacks (still nodding), tanks and rigs as far boxes. The capture: the hill as tilted slabs, the
## pumpjacks, tanks and masts as boxes.

## Ground grid step (m), near and far.
const GROUND_STEP := 2.0
const GROUND_STEP_LOD := 8.0
## Lifts over the ground: the dirt ribbons and pads, so they never z-fight it.
const DIRT_LIFT := 0.06
## Poles along the ring road, metres apart; the pipe rack's offset from the road's centre line.
const POLE_EVERY := 44.0
const PIPE_OFFSET := OilField.ROAD_HALF + 1.0
const POLE_OFFSET := OilField.ROAD_HALF + 3.2
## Signs along the fence, metres apart.
const SIGN_EVERY := 80.0
const FENCE_H := 2.4
const GATE_W := 9.0
## The ground's far colour (display numbers: the straw the terrain draws from the air) and the
## dirt's.
const FAR_STRAW := Color(0.52, 0.46, 0.33)
const FAR_SCRUB := Color(0.33, 0.33, 0.24)
const FAR_DIRT := Color(0.5, 0.43, 0.34)
## Light pools after dark (tank batteries, rigs).
const POOL_TINT := Color(1.0, 0.86, 0.62)

static var _dirt_mat: ShaderMaterial

var ch: CityChunk
var f: OilField
## The part of the site this chunk owns.
var area := Rect2()
var full := false
var walls: SurfaceTool
var dirt: SurfaceTool
var _dirt_n := 0


static func dirt_material() -> ShaderMaterial:
	if _dirt_mat == null:
		_dirt_mat = ShaderMaterial.new()
		_dirt_mat.shader = load("res://shaders/oil_dirt.gdshader")
		_dirt_mat.set_shader_parameter("dirt_tex", PropFactory.texture("hill_dirt", "Color"))
		_dirt_mat.set_shader_parameter("gravel_tex", PropFactory.texture("rock", "Color"))
	return _dirt_mat


static func field_of(ch: CityChunk) -> OilField:
	if ch.plan == null or ch.plan.macro == null:
		return null
	return ch.plan.macro.oil


## The steps a chunk on the field's site runs (Landmarks.site_steps()).
static func site_steps(c: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var fld := field_of(c)
	if fld == null:
		return steps
	var b := OilFieldBuild.new()
	b.ch = c
	b.f = fld
	b.area = c.owned_rect().intersection(fld.rect)
	b.full = c.level == CityChunk.Level.FULL and not c.capturing
	if b.area.size.x < 0.5 or b.area.size.y < 0.5:
		return steps
	# The steps are Callables on `b`, which hold no reference to it: the chunk keeps it alive.
	c.set_meta("oil_build", b)
	b.walls = SurfaceTool.new()
	b.walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	b.walls.set_smooth_group(-1)
	b.dirt = SurfaceTool.new()
	b.dirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	b.dirt.set_smooth_group(-1)
	steps.append(b._pavement)
	steps.append(b._ground)
	steps.append(b._lease_roads)
	steps.append(b._wells)
	for i in fld.pads.size():
		if b.area.has_point(fld.pads[i].c):
			steps.append(b._pad.bind(i))
	if b.full:
		steps.append(b._pipes_and_poles)
		steps.append(b._fence)
	steps.append(b._commit)
	if not b.full:
		steps.append(c._add_relief_floor)
	return steps


## The far city's capture of a field chunk (CityChunk._begin_capture()).
static func capture_steps(c: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var fld := field_of(c)
	if fld == null:
		return steps
	var b := OilFieldBuild.new()
	b.ch = c
	b.f = fld
	b.area = c.owned_rect().intersection(fld.rect)
	if b.area.size.x < 0.5 or b.area.size.y < 0.5:
		return steps
	c.set_meta("oil_build", b)
	steps.append(b._capture)
	return steps


func _ground_y(x: float, z: float) -> float:
	return CityChunk.SIDEWALK_TOP + ch._gy(x, z)


func _at(p: Vector2, up: float = 0.0) -> Vector3:
	return Vector3(p.x, _ground_y(p.x, p.y) + up, p.y)


# --- The pavement ring ---------------------------------------------------------------------------

func _pavement() -> void:
	var r := f.rect
	var inner := r.grow(-OilField.PAVEMENT)
	var strips := [
		Rect2(r.position.x, r.position.y, r.size.x, OilField.PAVEMENT),
		Rect2(r.position.x, inner.end.y, r.size.x, OilField.PAVEMENT),
		Rect2(r.position.x, inner.position.y, OilField.PAVEMENT, inner.size.y),
		Rect2(inner.end.x, inner.position.y, OilField.PAVEMENT, inner.size.y),
	]
	var paving := PropFactory.road("sidewalk", 3.0, Color(1.5, 1.5, 1.48), hash([ch.plan.seed, "oil_paving"]), 1.6, 0.4)
	for s: Rect2 in strips:
		var part := s.intersection(ch.owned_rect())
		if part.size.x > 0.05 and part.size.y > 0.05:
			ch._add_ground_grid(part, CityChunk.SIDEWALK_TOP, CityChunk.SIDEWALK_TOP + 0.5, paving, true, ch.style.sidewalk)


# --- The hill's ground ---------------------------------------------------------------------------------

func _ground() -> void:
	var inner := f.rect.grow(-OilField.PAVEMENT).intersection(area)
	if inner.size.x < 0.5 or inner.size.y < 0.5:
		return
	var step := GROUND_STEP if full else GROUND_STEP_LOD
	var nx := clampi(ceili(inner.size.x / step), 1, 160)
	var nz := clampi(ceili(inner.size.y / step), 1, 160)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for j in nz + 1:
		for i in nx + 1:
			var x := inner.position.x + inner.size.x * float(i) / float(nx)
			var z := inner.position.y + inner.size.y * float(j) / float(nz)
			var y := _ground_y(x, z) - 0.02
			verts.append(Vector3(x, y, z))
			var dx := ch._gy(x + 1.0, z) - ch._gy(x - 1.0, z)
			var dz := ch._gy(x, z + 1.0) - ch._gy(x, z - 1.0)
			norms.append(Vector3(-dx * 0.5, 1.0, -dz * 0.5).normalized())
			# Drainage (terrain.gdshader reads COLOR.g * 2 - 1): the hill's gullies wetter and
			# brushier, the graded roads and pads plain.
			var dr := f.drainage(Vector2(x, z))
			cols.append(Color(0.0, 0.5 + 0.45 * dr, 1.0, 1.0))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, PropFactory.terrain_material())
	var mi := MeshInstance3D.new()
	mi.name = "OilGround"
	mi.mesh = mesh
	ch.add_child(mi)
	if full:
		var body := StaticBody3D.new()
		body.name = "OilGroundBody"
		body.collision_layer = 1 | CityChunk.TERRAIN_LAYER
		body.collision_mask = 0
		body.set_meta("terrain", true)
		var shape := CollisionShape3D.new()
		var faces := PackedVector3Array()
		for k in idx.size():
			faces.append(verts[idx[k]])
		var cps := ConcavePolygonShape3D.new()
		cps.backface_collision = true
		cps.set_faces(faces)
		shape.shape = cps
		body.add_child(shape)
		ch.add_child(body)


# --- Dirt roads and pads -----------------------------------------------------------------------------

func _dv(p: Vector3, uv: Vector2, uv2: Vector2) -> void:
	dirt.set_normal(Vector3.UP)
	dirt.set_uv(uv)
	dirt.set_uv2(uv2)
	dirt.add_vertex(p)
	_dirt_n += 1


## A clockwise-to-the-viewer-from-above quad (Godot's front faces), a b c d counter-clockwise in XZ seen from above.
func _dquad(p: Array, uv: Array, uv2: Vector2) -> void:
	for k: int in [0, 2, 1, 0, 3, 2]:
		_dv(p[k], uv[k], uv2)


func _lease_roads() -> void:
	var half := OilField.ROAD_HALF + 0.5
	for rd: Dictionary in f.roads:
		var pts: PackedVector2Array = rd.pts
		var run := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			var mid := (a + b) * 0.5
			if not area.has_point(mid):
				run += seg
				continue
			var na := _normal_at(pts, i)
			var nb := _normal_at(pts, i + 1)
			# Three across (left edge, crown, right edge), so the ribbon keeps to a cambered bed.
			for side: float in [-1.0, 1.0]:
				var a0 := a
				var b0 := b
				var a1 := a + na * half * side
				var b1 := b + nb * half * side
				var q := [Vector3(a0.x, _ground_y(a0.x, a0.y) + DIRT_LIFT, a0.y), Vector3(b0.x, _ground_y(b0.x, b0.y) + DIRT_LIFT, b0.y),
					Vector3(b1.x, _ground_y(b1.x, b1.y) + DIRT_LIFT, b1.y), Vector3(a1.x, _ground_y(a1.x, a1.y) + DIRT_LIFT, a1.y)]
				var uvs := [Vector2(0.0, run), Vector2(0.0, run + seg), Vector2(side, run + seg), Vector2(side, run)]
				# Seen from above the order must be counter-clockwise for _dquad: flip for one side.
				if side > 0.0:
					q = [q[0], q[3], q[2], q[1]]
					uvs = [uvs[0], uvs[3], uvs[2], uvs[1]]
				if _ccw_from_above(q):
					_dquad(q, uvs, Vector2(0.0, 0.0))
				else:
					_dquad([q[0], q[3], q[2], q[1]], [uvs[0], uvs[3], uvs[2], uvs[1]], Vector2(0.0, 0.0))
			run += seg


static func _normal_at(pts: PackedVector2Array, i: int) -> Vector2:
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var d := (b - a).normalized()
	return Vector2(-d.y, d.x)


## True when quad q (four Vector3) runs counter-clockwise in XZ seen from above (+Y down onto it).
static func _ccw_from_above(q: Array) -> bool:
	var a: Vector3 = q[0]
	var b: Vector3 = q[1]
	var c: Vector3 = q[2]
	# Counter-clockwise seen from above is a normal toward +y by the right-hand rule; _dquad lays
	# such corners 0-2-1, 0-3-2, which is clockwise to a viewer above: Godot's front face.
	return (b - a).cross(c - a).y > 0.0


## A pad's gravel: rings from the centre out past the levelled edge onto the bank.
func _pad_ground(pd: Dictionary) -> void:
	var c: Vector2 = pd.c
	var r: float = pd.r + 1.0
	var segs := 28
	var rings := [0.0, 0.45, 0.8, 1.0, 1.12]
	var oily := 1.0 if int(pd.kind) == OilField.Pad.WELLS else 0.0
	for k in rings.size() - 1:
		for s in segs:
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var r0: float = rings[k] * r
			var r1: float = rings[k + 1] * r
			var p := [c + Vector2(cos(a0), sin(a0)) * r0, c + Vector2(cos(a0), sin(a0)) * r1,
				c + Vector2(cos(a1), sin(a1)) * r1, c + Vector2(cos(a1), sin(a1)) * r0]
			var q: Array = []
			var uvs: Array = []
			for pp: Vector2 in p:
				q.append(Vector3(pp.x, _ground_y(pp.x, pp.y) + DIRT_LIFT + 0.01, pp.y))
				uvs.append(Vector2(pp.distance_to(c) / (r - 1.0), oily))
			if _ccw_from_above(q):
				_dquad(q, uvs, Vector2(1.0, 0.0))
			else:
				_dquad([q[0], q[3], q[2], q[1]], [uvs[0], uvs[3], uvs[2], uvs[1]], Vector2(1.0, 0.0))


# --- Pumpjacks -------------------------------------------------------------------------------------------

## The custom data a pumpjack instance carries (pumpjack.gdshader).
static func well_custom(w: Dictionary, wear: float) -> Color:
	return Color(float(w.phase), float(w.spm) / 20.0, wear, float(int(w.paint)) / 8.0)


static func well_xform(w: Dictionary, y: float) -> Transform3D:
	var p: Vector2 = w.p
	var sc: float = w.scale
	return Transform3D(Basis(Vector3.UP, float(w.yaw)).scaled(Vector3(sc, sc, sc)), Vector3(p.x, y, p.y))


func _wells() -> void:
	var mesh := OilKit.pumpjack(not full)
	for pd: Dictionary in f.pads:
		if not area.has_point(pd.c):
			continue
		for w: Dictionary in pd.wells:
			var wear := OilField._h01([f.seed, "oil_wear", pd.id, (w.p as Vector2).x])
			ch._batch.add("pumpjack", mesh, well_xform(w, CityChunk.SIDEWALK_TOP), Color.WHITE, well_custom(w, wear))
			if full:
				var sc: float = w.scale
				var fwd := Vector2(cos(float(w.yaw)), -sin(float(w.yaw)))
				var base := (w.p as Vector2) + fwd * (-5.6 * sc)
				ch._add_shape(Vector3(9.6 * sc, 2.6 * sc, 2.4 * sc), _at(base, 1.3 * sc), float(w.yaw))
				ch._add_shape(Vector3(0.8 * sc, 6.0 * sc, 1.4 * sc), _at((w.p as Vector2) + fwd * (OilKit.PIVOT.x * sc + 1.0), 3.0 * sc), float(w.yaw))
	if full:
		ch._batch.set_shadow_distance("pumpjack", 160.0)


# --- Pads ------------------------------------------------------------------------------------------------

func _pad(i: int) -> void:
	var pd: Dictionary = f.pads[i]
	_pad_ground(pd)
	match int(pd.kind):
		OilField.Pad.WELLS:
			_well_pad(pd)
		OilField.Pad.BATTERY:
			_battery(pd)
		OilField.Pad.RIG:
			_rig(pd)


func _well_pad(pd: Dictionary) -> void:
	if not full:
		return
	var dir: Vector2 = pd.dir
	var out: Vector2 = pd.out
	var k := 0
	for w: Dictionary in pd.wells:
		var p: Vector2 = w.p
		var sc: float = w.scale
		var fwd := Vector2(cos(float(w.yaw)), -sin(float(w.yaw)))
		# The motor's control panel on a two-post stand off its end, a conduit to it.
		var panel := p + fwd * (-(OilKit.LENGTH + 1.2) * sc) + out * 1.4
		var base := _at(panel)
		var side := Vector3(out.x, 0, out.y)
		for s: float in [-0.35, 0.35]:
			var q := base + Vector3(dir.x, 0, dir.y) * s
			IndustrialKit.cyl(walls, Transform3D(Basis(), q - Vector3(0, 0.2, 0)), 0.04, 1.9, IndustrialKit.K_GALV, OilKit.GALV, 6, false)
		IndustrialKit.box(walls, Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), base + Vector3(0, 1.35, 0)), Vector3(0.9, 0.9, 0.35), IndustrialKit.K_STEEL, Color(0.58, 0.6, 0.58))
		OilKit.pipe(walls, base + Vector3(0, 0.9, 0), base + Vector3(0, 0.12, 0), 0.03, OilKit.GALV, 6, IndustrialKit.K_GALV)
		# The flowline from the wellhead out to the road's pipe rack.
		var fl := p + Vector2(fwd.y, -fwd.x) * (-0.95 * sc) + fwd * 2.2 * sc
		var road_p: Vector2 = (pd.c as Vector2) - out * (float(pd.r) + 1.5 - (OilField.ROAD_HALF + 1.0 - PIPE_OFFSET)) + dir * (float(k) - 0.5) * 1.2
		var y0 := _ground_y(fl.x, fl.y) + 0.25
		OilKit.pipe(walls, Vector3(fl.x, y0, fl.y), Vector3(road_p.x, _ground_y(road_p.x, road_p.y) + 0.25, road_p.y), 0.07, Color(0.32, 0.31, 0.3), 6)
		k += 1
	# The lease sign at the pad's entrance: the lease and the well numbers.
	var first: int = absi(hash([f.seed, "oil_wellno", pd.id])) % 80 + 1
	var label := "%s  %d" % [pd.lease, first] if (pd.wells as Array).size() == 1 else "%s  %d-%d" % [pd.lease, first, first + (pd.wells as Array).size() - 1]
	var sp: Vector2 = (pd.c as Vector2) - out * (float(pd.r) - 0.6) + dir * (float(pd.r) - 1.0)
	OilKit.sign(walls, _at(sp), -out, [label, OilField.OPERATOR], 1.3, 0.8, 0.9)


func _battery(pd: Dictionary) -> void:
	var c: Vector2 = pd.c
	var dir: Vector2 = pd.dir
	var out: Vector2 = pd.out
	var n := 3 + absi(hash([f.seed, "oil_tanks", pd.id])) % 2
	var r := 2.75
	var h := lerpf(6.4, 7.6, OilField._h01([f.seed, "oil_tank_h", pd.id]))
	var paint: Color = OilKit.TANK_PAINTS[absi(hash([f.seed, "oil_tank_paint", pd.id])) % OilKit.TANK_PAINTS.size()]
	var pitch := r * 2.0 + 1.0
	var row_c := c + out * 3.2
	var y := _ground_y(c.x, c.y)
	if not full:
		for k in n:
			var p := row_c + dir * (float(k) - float(n - 1) * 0.5) * pitch
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(r * 1.8, h, r * 1.8)), Vector3(p.x, CityChunk.SIDEWALK_TOP + h * 0.5, p.y)),
				paint, Color(0.0, 0.0, 0.0, 1.0))
		return
	var o3 := Vector3(out.x, 0, out.y)
	var d3 := Vector3(dir.x, 0, dir.y)
	for k in n:
		var p := row_c + dir * (float(k) - float(n - 1) * 0.5) * pitch
		OilKit.tank(walls, Vector3(p.x, y, p.y), r, h, paint * lerpf(0.94, 1.04, OilField._h01([f.seed, "oil_tk", pd.id, k])), o3 if k == 0 else -o3)
		ch._add_shape(Vector3(r * 1.7, h, r * 1.7), Vector3(p.x, y + h * 0.5, p.y))
	# The containment berm round the row: a low concrete wall.
	var hl := float(n) * pitch * 0.5 + 1.6
	var hw := r + 2.0
	var corners := [row_c - dir * hl - out * hw, row_c + dir * hl - out * hw, row_c + dir * hl + out * hw, row_c - dir * hl + out * hw]
	for e in 4:
		var a: Vector2 = corners[e]
		var b: Vector2 = corners[(e + 1) % 4]
		OilKit.strut(walls, Vector3(a.x, y + 0.45, a.y), Vector3(b.x, y + 0.45, b.y), 0.3, 0.9, IndustrialKit.K_CONCRETE, Color(0.72, 0.71, 0.68))
	# The catwalk across the tops, its railings, the stair up the end.
	var cy := y + h + 0.35
	var w0 := row_c - dir * (float(n - 1) * 0.5 * pitch + 0.8)
	var w1 := row_c + dir * (float(n - 1) * 0.5 * pitch + 0.8)
	OilKit.strut(walls, Vector3(w0.x, cy, w0.y), Vector3(w1.x, cy, w1.y), 0.9, 0.08, IndustrialKit.K_GALV, OilKit.GALV)
	for s: float in [-0.45, 0.45]:
		OilKit.railing(walls, Vector3(w0.x, cy, w0.y) + o3 * s, Vector3(w1.x, cy, w1.y) + o3 * s, OilKit.SAFETY)
	var foot := w0 - dir * (h * 0.9) - out * 0.0
	var top := Vector3(w0.x, cy, w0.y)
	var bottom := Vector3(foot.x, _ground_y(foot.x, foot.y), foot.y)
	for s: float in [-0.45, 0.45]:
		OilKit.strut(walls, bottom + o3 * s, top + o3 * s, 0.06, 0.25, IndustrialKit.K_STEEL, OilKit.SAFETY, o3)
	var treads := int(h / 0.22)
	for t in treads:
		var q := bottom.lerp(top, (float(t) + 0.5) / float(treads))
		IndustrialKit.box(walls, Transform3D(Basis(d3, Vector3.UP, d3.cross(Vector3.UP)).orthonormalized(), q), Vector3(0.28, 0.04, 0.88), IndustrialKit.K_GALV, OilKit.GALV, 0.0, 0)
	OilKit.railing(walls, bottom + o3 * 0.5, top + o3 * 0.5, OilKit.SAFETY)
	# Lamps on the catwalk (lit after dark; the field's light mesh carries the glow from afar).
	for k in 3:
		var lp := w0.lerp(w1, float(k) / 2.0) + out * 0.5
		IndustrialKit.box(walls, Transform3D(Basis(), Vector3(lp.x, cy + 1.9, lp.y)), Vector3(0.35, 0.18, 0.35), IndustrialKit.K_LAMP, Color(1.0, 0.85, 0.6))
		OilKit.strut(walls, Vector3(lp.x, cy, lp.y), Vector3(lp.x, cy + 1.8, lp.y), 0.05, 0.05, IndustrialKit.K_GALV, OilKit.GALV)
	# A heater-treater on its saddles on the road side and a vertical separator, piped to the row.
	var ht := c - out * 4.0 + dir * 2.0
	var hy := _ground_y(ht.x, ht.y)
	var hxf := Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x) + PI * 0.5), Vector3(ht.x, hy + 1.6, ht.y))
	IndustrialKit.cyl_z(walls, hxf, 1.05, 7.0, IndustrialKit.K_TANK, paint * 0.95, 16)
	for s: float in [-2.4, 2.4]:
		var q := ht + dir * s
		IndustrialKit.box(walls, Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(q.x, hy + 0.4, q.y)), Vector3(0.3, 0.8, 1.6), IndustrialKit.K_CONCRETE, Color(0.7, 0.69, 0.66))
	IndustrialKit.cyl(walls, Transform3D(Basis(), Vector3(ht.x, hy + 2.7, ht.y) + d3 * 3.1), 0.12, 2.6, IndustrialKit.K_STEEL, OilKit.DARK, 8, true)
	var sep := c - out * 4.5 - dir * 6.0
	var sy := _ground_y(sep.x, sep.y)
	IndustrialKit.cyl(walls, Transform3D(Basis(), Vector3(sep.x, sy, sep.y)), 0.75, 4.2, IndustrialKit.K_TANK, paint, 14, false)
	IndustrialKit.cone(walls, Transform3D(Basis(), Vector3(sep.x, sy + 4.2, sep.y)), 0.75, 0.4, IndustrialKit.K_TANK, paint * 0.9, 14)
	for k in n:
		var p := row_c + dir * (float(k) - float(n - 1) * 0.5) * pitch - out * r
		OilKit.pipe(walls, Vector3(p.x, y + 1.0, p.y), Vector3(p.x, y + 1.0, p.y) - o3 * 2.4, 0.08, Color(0.32, 0.31, 0.3), 6)
	var man0 := row_c - out * (r + 2.4) - dir * (float(n - 1) * 0.5 * pitch)
	var man1 := row_c - out * (r + 2.4) + dir * (float(n - 1) * 0.5 * pitch)
	OilKit.pipe(walls, Vector3(man0.x, y + 1.0, man0.y), Vector3(man1.x, y + 1.0, man1.y), 0.1, Color(0.32, 0.31, 0.3), 8)
	OilKit.pipe(walls, Vector3(man0.x, y + 1.0, man0.y), Vector3(sep.x, sy + 1.0, sep.y), 0.1, Color(0.32, 0.31, 0.3), 8)
	OilKit.pipe(walls, Vector3(sep.x, sy + 2.0, sep.y), Vector3(ht.x, hy + 1.6, ht.y), 0.09, Color(0.32, 0.31, 0.3), 8)
	OilKit.sign(walls, _at(c - out * (float(pd.r) - 0.8) + dir * 5.0), -out, ["NO SMOKING - FLAMMABLE", "H2S GAS MAY BE PRESENT", OilField.OPERATOR], 1.6, 1.1, 0.9)
	_pool(row_c - out * (r + 1.0), 16.0, 1.0)


func _rig(pd: Dictionary) -> void:
	var c: Vector2 = pd.c
	var dir: Vector2 = pd.dir
	var out: Vector2 = pd.out
	var y := _ground_y(c.x, c.y)
	var paint := OilKit.RIG_RED if OilField._h01([f.seed, "oil_rig_paint", pd.id]) < 0.5 else OilKit.RIG_CREAM
	var mast_c := c + out * 2.0
	var deck := 6.2
	var mast_h := 36.0
	if not full:
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(9.0, deck, 9.0)), Vector3(mast_c.x, CityChunk.SIDEWALK_TOP + deck * 0.5, mast_c.y)),
			Color(0.35, 0.33, 0.3), Color(0.0, 0.0, 0.0, 1.0))
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(2.6, mast_h, 2.6)), Vector3(mast_c.x, CityChunk.SIDEWALK_TOP + deck + mast_h * 0.5, mast_c.y)),
			paint, Color(0.0, 0.0, 0.0, 1.0))
		return
	var o3 := Vector3(out.x, 0, out.y)
	var d3 := Vector3(dir.x, 0, dir.y)
	var basis := Basis(d3, Vector3.UP, d3.cross(Vector3.UP)).orthonormalized()
	var at := Vector3(mast_c.x, y, mast_c.y)
	# Substructure: four box legs, cross bracing, the drill floor.
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			IndustrialKit.box(walls, Transform3D(basis, at + d3 * cx * 4.0 + o3 * cz * 4.0 + Vector3(0, deck * 0.5, 0)), Vector3(0.6, deck, 0.6), IndustrialKit.K_STEEL, paint * 0.8, 0.0, 32)
		OilKit.strut(walls, at + d3 * cx * 4.0 - o3 * 4.0 + Vector3(0, 0.5, 0), at + d3 * cx * 4.0 + o3 * 4.0 + Vector3(0, deck - 0.6, 0), 0.18, 0.18, IndustrialKit.K_STEEL, paint * 0.8)
		OilKit.strut(walls, at + d3 * cx * 4.0 + o3 * 4.0 + Vector3(0, 0.5, 0), at + d3 * cx * 4.0 - o3 * 4.0 + Vector3(0, deck - 0.6, 0), 0.18, 0.18, IndustrialKit.K_STEEL, paint * 0.8)
	IndustrialKit.box(walls, Transform3D(basis, at + Vector3(0, deck + 0.2, 0)), Vector3(9.4, 0.4, 9.4), IndustrialKit.K_STEEL, Color(0.4, 0.39, 0.37), 0.0, 0)
	for e: Array in [[-1.0, -1.0, 1.0, -1.0], [1.0, -1.0, 1.0, 1.0], [-1.0, 1.0, -1.0, -1.0]]:
		OilKit.railing(walls, at + d3 * float(e[0]) * 4.6 + o3 * float(e[1]) * 4.6 + Vector3(0, deck + 0.4, 0), at + d3 * float(e[2]) * 4.6 + o3 * float(e[3]) * 4.6 + Vector3(0, deck + 0.4, 0), OilKit.SAFETY)
	ch._add_shape_xf(Vector3(9.4, deck + 0.4, 9.4), Transform3D(basis, at + Vector3(0, (deck + 0.4) * 0.5, 0)))
	# The mast over the rotary, its V-door toward the road.
	OilKit.derrick(walls, at + Vector3(0, deck + 0.4, 0), 6.0, mast_h, paint, -o3)
	ch._add_shape(Vector3(3.0, mast_h, 3.0), at + Vector3(0, deck + mast_h * 0.5, 0))
	# The doghouse on the floor, the drawworks, the V-door ramp down to the pipe racks.
	IndustrialKit.box(walls, Transform3D(basis, at + d3 * 3.0 + o3 * 2.4 + Vector3(0, deck + 1.65, 0)), Vector3(2.8, 2.5, 3.6), IndustrialKit.K_TRAILER, Color(0.85, 0.84, 0.8))
	IndustrialKit.box(walls, Transform3D(basis, at - d3 * 2.6 + o3 * 1.6 + Vector3(0, deck + 1.2, 0)), Vector3(2.4, 1.6, 2.6), IndustrialKit.K_STEEL, paint * 0.7)
	var ramp_top := at - o3 * 4.7 + Vector3(0, deck + 0.4, 0)
	var ramp_foot := at - o3 * 15.0 + Vector3(0, 1.0, 0)
	ramp_foot.y = _ground_y(ramp_foot.x, ramp_foot.z) + 1.0
	OilKit.strut(walls, ramp_foot, ramp_top, 1.6, 0.3, IndustrialKit.K_STEEL, Color(0.42, 0.4, 0.38), d3)
	var catwalk := at - o3 * 21.0
	catwalk.y = _ground_y(catwalk.x, catwalk.z)
	IndustrialKit.box(walls, Transform3D(basis, catwalk + Vector3(0, 0.5, 0)), Vector3(1.4, 1.0, 12.0), IndustrialKit.K_STEEL, Color(0.42, 0.4, 0.38))
	# Pipe racks either side of the catwalk, joints of drill pipe on them.
	for s: float in [-1.0, 1.0]:
		var rack := catwalk + d3 * s * 2.8
		for e: float in [-4.5, 0.0, 4.5]:
			IndustrialKit.box(walls, Transform3D(basis, rack + o3 * e + Vector3(0, 0.45, 0)), Vector3(2.6, 0.9, 0.25), IndustrialKit.K_STEEL, Color(0.3, 0.3, 0.3))
		for j in 6:
			var q := rack + d3 * (float(j) - 2.5) * 0.36 + Vector3(0, 1.0 + 0.11 * float(j % 2), 0)
			OilKit.pipe(walls, q - o3 * 5.8, q + o3 * 5.8, 0.065, Color(0.44, 0.36, 0.3), 6)
	# Mud tanks and the generator sets on the far side, a trailer or two.
	for k in 2:
		var mt := at + o3 * (8.5 + float(k) * 3.4) + d3 * 1.0
		mt.y = _ground_y(mt.x, mt.z)
		IndustrialKit.box(walls, Transform3D(basis, mt + Vector3(0, 1.4, 0)), Vector3(11.0, 2.8, 3.0), IndustrialKit.K_STEEL, Color(0.55, 0.53, 0.48))
		OilKit.railing(walls, mt + Vector3(0, 2.8, 0) - d3 * 5.4 + o3 * 1.4, mt + Vector3(0, 2.8, 0) + d3 * 5.4 + o3 * 1.4, OilKit.SAFETY)
	for k in 2:
		var g := at + d3 * (8.5 + float(k) * 0.0) + o3 * (float(k) * 4.0 - 2.0)
		g.y = _ground_y(g.x, g.z)
		IndustrialKit.box(walls, Transform3D(basis, g + Vector3(0, 1.4, 0)), Vector3(3.0, 2.8, 2.6), IndustrialKit.K_CORRUGATED, Color(0.62, 0.64, 0.6))
		IndustrialKit.cyl(walls, Transform3D(Basis(), g + Vector3(0, 2.8, 0)), 0.18, 1.6, IndustrialKit.K_STEEL, OilKit.DARK, 8, false)
	var tr := at - d3 * 10.0 + o3 * 6.0
	tr.y = _ground_y(tr.x, tr.z)
	IndustrialKit.place(walls, Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x) + PI * 0.5), tr), Color(0.9, 0.9, 0.88), func() -> void: IndustrialKit.trailer(0))
	_pool(mast_c, 26.0, 1.4)
	_pool(c - out * 12.0, 18.0, 0.9)


func _pool(p: Vector2, size: float, strength: float) -> void:
	if not full:
		return
	var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(size, 1.0, size)), Vector3(p.x, CityChunk.SIDEWALK_TOP + 0.12, p.y))
	ch._batch.add("oil_pool", PropFactory.light_pool(POOL_TINT, 0.6 * strength, 1.8), xf)


# --- Pipe runs, the power line ---------------------------------------------------------------------------

func _pipes_and_poles() -> void:
	for ri in f.roads.size():
		var rd: Dictionary = f.roads[ri]
		var pts: PackedVector2Array = rd.pts
		# Pipe rack: supports at every point, two lines along the road's left side.
		var prev_ok := false
		var prev_top := [Vector3.ZERO, Vector3.ZERO]
		for i in pts.size():
			var n := _normal_at(pts, i)
			var p := pts[i] + n * PIPE_OFFSET
			var on_pad := _in_pad(p, 0.5)
			var ok := not on_pad and f.rect.grow(-OilField.FENCE_IN - 1.5).has_point(p)
			var y := _ground_y(p.x, p.y)
			var tops := [Vector3(p.x, y + 0.75, p.y) + Vector3(n.x, 0, n.y) * 0.2, Vector3(p.x, y + 0.75, p.y) - Vector3(n.x, 0, n.y) * 0.2]
			if ok and area.has_point(p) and i % 2 == 0:
				for s: float in [-0.35, 0.35]:
					var q := Vector3(p.x, y, p.y) + Vector3(n.x, 0, n.y) * s
					IndustrialKit.cyl(walls, Transform3D(Basis(), q - Vector3(0, 0.15, 0)), 0.04, 0.8, IndustrialKit.K_GALV, OilKit.GALV, 6, false)
				OilKit.strut(walls, Vector3(p.x, y + 0.66, p.y) + Vector3(n.x, 0, n.y) * 0.4, Vector3(p.x, y + 0.66, p.y) - Vector3(n.x, 0, n.y) * 0.4, 0.06, 0.06, IndustrialKit.K_GALV, OilKit.GALV)
			if ok and prev_ok:
				var mid := (pts[i] + pts[i - 1]) * 0.5
				if area.has_point(mid):
					OilKit.pipe(walls, prev_top[0], tops[0], 0.09, Color(0.3, 0.29, 0.28), 6)
					OilKit.pipe(walls, prev_top[1], tops[1], 0.06, Color(0.5, 0.48, 0.44), 6)
			prev_ok = ok
			prev_top = tops
		# The power line round the ring roads, on the right side.
		if not bool(rd.ring):
			continue
		var run := 0.0
		var next_at := POLE_EVERY * OilField._h01([f.seed, "oil_pole0", ri])
		var last := Vector3.INF
		for i in pts.size() - 1:
			run += pts[i].distance_to(pts[i + 1])
			if run < next_at:
				continue
			next_at += POLE_EVERY
			var n := _normal_at(pts, i)
			var p := pts[i] - n * POLE_OFFSET
			if _in_pad(p, 1.5):
				continue
			var base := _at(p)
			var top := base + Vector3(0, 10.5 - 0.5 + 0.26, 0)
			var mine := area.has_point(p)
			if mine:
				OilKit.pole(walls, base - Vector3(0, 0.3, 0), 10.8, Vector3(n.x, 0, n.y))
				if absi(hash([f.seed, "oil_xfmr", ri, i])) % 4 == 0:
					IndustrialKit.cyl(walls, Transform3D(Basis(), base + Vector3(0, 7.2, 0) - Vector3(n.x, 0, n.y) * 0.0 + Vector3(n.y, 0, -n.x) * 0.4), 0.32, 1.1, IndustrialKit.K_STEEL, Color(0.5, 0.52, 0.5), 10, true)
				if last != Vector3.INF:
					var across := (Vector3(n.x, 0, n.y)).normalized()
					for s: float in [-1.0, 0.0, 1.0]:
						OilKit.wire(walls, last + across * s, top + across * s, 0.5, 6)
			last = top


func _in_pad(p: Vector2, pad: float) -> bool:
	for pd: Dictionary in f.pads:
		if p.distance_to(pd.c) < float(pd.r) + pad:
			return true
	return false


# --- The perimeter fence, its gates and signs ---------------------------------------------------------------

func _fence() -> void:
	var r := f.rect.grow(-OilField.FENCE_IN)
	var edges := [
		[Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), 0],
		[Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), 1],
		[Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y), 2],
		[Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), 3],
	]
	var owned := ch.owned_rect()
	var ground := func(x: float, z: float) -> float: return _ground_y(x, z)
	for e: Array in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var side: int = e[2]
		var dir := (b - a).normalized()
		var len := a.distance_to(b)
		# The edge's own stretch in this chunk.
		var t0 := 0.0
		var t1 := len
		if absf(dir.x) > 0.5:
			if a.y < owned.position.y or a.y >= owned.end.y:
				continue
			t0 = clampf(owned.position.x - a.x, 0.0, len)
			t1 = clampf(owned.end.x - a.x, 0.0, len)
		else:
			if a.x < owned.position.x or a.x >= owned.end.x:
				continue
			t0 = clampf(owned.position.y - a.y, 0.0, len)
			t1 = clampf(owned.end.y - a.y, 0.0, len)
		if t1 - t0 < 0.5:
			continue
		# Cut the gates out.
		var cuts: Array = []
		for g: Dictionary in f.gates:
			if int(g.side) == side:
				var tg := ((g.p as Vector2) - a).dot(dir)
				cuts.append(tg)
		var pieces: Array = [[t0, t1]]
		for tg: float in cuts:
			var next: Array = []
			for pc: Array in pieces:
				var lo: float = pc[0]
				var hi: float = pc[1]
				if tg + GATE_W * 0.5 <= lo or tg - GATE_W * 0.5 >= hi:
					next.append(pc)
					continue
				if tg - GATE_W * 0.5 > lo + 0.3:
					next.append([lo, tg - GATE_W * 0.5])
				if tg + GATE_W * 0.5 < hi - 0.3:
					next.append([tg + GATE_W * 0.5, hi])
			pieces = next
		for pc: Array in pieces:
			OilKit.fence(walls, a + dir * float(pc[0]), a + dir * float(pc[1]), FENCE_H, ground, true)
		# Signs facing the street every SIGN_EVERY metres along the edge.
		var outward := Vector2(0.0, -1.0) if side == 0 else (Vector2(0.0, 1.0) if side == 1 else (Vector2(-1.0, 0.0) if side == 2 else Vector2(1.0, 0.0)))
		var s := fposmod(-(a.x + a.y), SIGN_EVERY) + SIGN_EVERY * 0.5
		while s < len:
			if s >= t0 and s < t1:
				var near_gate := false
				for tg: float in cuts:
					if absf(s - tg) < GATE_W:
						near_gate = true
				if not near_gate:
					var p := a + dir * s + outward * 0.35
					OilKit.sign(walls, _at(p), outward, ["OIL FIELD - NO TRESPASSING", OilField.OPERATOR], 1.5, 1.0, 0.9)
			s += SIGN_EVERY
		# Each gate in this stretch: two leaves swung open against the fence, the operator's board.
		for tg: float in cuts:
			if tg < t0 or tg >= t1:
				continue
			var gp := a + dir * tg
			for sgn: float in [-1.0, 1.0]:
				var hinge := gp + dir * sgn * GATE_W * 0.5
				var leaf := hinge - outward * 4.0
				OilKit.fence(walls, hinge, leaf, FENCE_H - 0.2, ground, false)
			var bp := gp + dir * (GATE_W * 0.5 + 2.2) + outward * 0.35
			OilKit.sign(walls, _at(bp), outward, ["LEASE ROAD - AUTHORIZED VEHICLES", "ONLY  " + OilField.OPERATOR, "EMERGENCY 555-0148"], 1.8, 1.2, 0.9)


# --- Commit ---------------------------------------------------------------------------------------------

func _commit() -> void:
	if _dirt_n > 0:
		dirt.set_material(dirt_material())
		var dm := MeshInstance3D.new()
		dm.name = "OilDirt"
		dm.mesh = dirt.commit()
		dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(dm)
	if full:
		walls.set_material(IndustrialKit.walls_material())
		var arrays := walls.commit_to_arrays()
		if arrays.size() > 0 and arrays[Mesh.ARRAY_VERTEX] != null and (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, IndustrialKit.walls_material())
			var wm := MeshInstance3D.new()
			wm.name = "OilWalls"
			wm.mesh = mesh
			ch.add_child(wm)
	ch.set_meta("oil_field", true)
	ch.remove_meta("oil_build")


# --- Far ----------------------------------------------------------------------------------------------------

## A thin slab lying on its local X face (building_lod.gdshader draws any local +-Y face as a roof
## with plant on it), as RiverBuild's far land.
static func _far_slab(c: Vector3, size: Vector2, slope: Vector2, col: Color) -> Array:
	# Columns: across X (tilted by the slope), the slab's thickness (Y), across Z.
	var bx := Vector3(size.x, slope.x * size.x, 0.0)
	var bz := Vector3(0.0, slope.y * size.y, size.y)
	var by := bz.cross(bx).normalized() * 0.4
	var b := Basis(bx, by, bz)
	return [Transform3D(Basis(b.y, -b.x, b.z), c), col]


func _capture() -> void:
	var cap: Dictionary = ch.captured
	var inner := f.rect.grow(-OilField.PAVEMENT).intersection(area)
	if inner.size.x < 0.5 or inner.size.y < 0.5:
		return
	# The plate under it all in the straw.
	(cap.ground as Array).append([inner, FAR_STRAW, CityChunk.SIDEWALK_TOP, FAR_STRAW.srgb_to_linear()])
	var cell := 24.0
	var nx := maxi(1, ceili(inner.size.x / cell))
	var nz := maxi(1, ceili(inner.size.y / cell))
	for j in nz:
		for i in nx:
			var r := Rect2(inner.position + Vector2(inner.size.x * float(i) / float(nx), inner.size.y * float(j) / float(nz)), Vector2(inner.size.x / float(nx), inner.size.y / float(nz)))
			var c := r.get_center()
			var h00 := ch._gy(r.position.x, r.position.y)
			var h10 := ch._gy(r.end.x, r.position.y)
			var h01 := ch._gy(r.position.x, r.end.y)
			var h11 := ch._gy(r.end.x, r.end.y)
			var sx := ((h10 - h00) + (h11 - h01)) * 0.5 / r.size.x
			var sz := ((h01 - h00) + (h11 - h10)) * 0.5 / r.size.y
			var hc := (h00 + h10 + h01 + h11) * 0.25
			var col := FAR_STRAW
			var dr := f.drainage(c)
			var rd := f.road_distance(c)
			if rd.x < OilField.ROAD_HALF + 2.0:
				col = FAR_DIRT
			elif dr > 0.35 or OilField._h01([f.seed, "oil_far_scrub", i, j, ch.ix, ch.iz]) < 0.18:
				col = FAR_SCRUB
			(cap.boxes as Array).append(_far_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP + hc - 0.1, c.y), r.size + Vector2(0.6, 0.6), Vector2(sx, sz), col))
	# The pumpjacks as a post and a beam, the tanks and masts as boxes.
	for pd: Dictionary in f.pads:
		if not area.has_point(pd.c):
			continue
		var g := CityChunk.SIDEWALK_TOP + ch._gy((pd.c as Vector2).x, (pd.c as Vector2).y)
		for w: Dictionary in pd.wells:
			var sc: float = w.scale
			var p: Vector2 = w.p
			var fwd := Vector2(cos(float(w.yaw)), -sin(float(w.yaw)))
			var yaw := float(w.yaw)
			var post := p + fwd * (OilKit.PIVOT.x * sc)
			(cap.boxes as Array).append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.6 * sc, 6.2 * sc, 1.0 * sc)), Vector3(post.x, g + 3.1 * sc, post.y)), Color(0.42, 0.43, 0.4)])
			var bm := p + fwd * ((OilKit.PIVOT.x - 0.5) * sc)
			(cap.boxes as Array).append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(8.0 * sc, 0.9 * sc, 0.6 * sc)), Vector3(bm.x, g + 6.6 * sc, bm.y)), Color(0.42, 0.43, 0.4)])
			var gb := p + fwd * (OilKit.CRANK.x * sc)
			(cap.boxes as Array).append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(2.4 * sc, 2.6 * sc, 2.0 * sc)), Vector3(gb.x, g + 1.3 * sc, gb.y)), Color(0.36, 0.36, 0.34)])
		if int(pd.kind) == OilField.Pad.BATTERY:
			var dir: Vector2 = pd.dir
			var row := (pd.c as Vector2) + (pd.out as Vector2) * 3.2
			(cap.boxes as Array).append([Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)).scaled(Vector3(24.0, 7.0, 5.4)), Vector3(row.x, g + 3.5, row.y)), Color(0.55, 0.52, 0.44)])
		elif int(pd.kind) == OilField.Pad.RIG:
			var m := (pd.c as Vector2) + (pd.out as Vector2) * 2.0
			(cap.boxes as Array).append([Transform3D(Basis().scaled(Vector3(9.0, 6.2, 9.0)), Vector3(m.x, g + 3.1, m.y)), Color(0.35, 0.33, 0.3)])
			(cap.boxes as Array).append([Transform3D(Basis().scaled(Vector3(2.2, 36.0, 2.2)), Vector3(m.x, g + 6.2 + 18.0, m.y)), Color(0.6, 0.25, 0.18)])


# --- The field's lights (a landmark: near and far alike) --------------------------------------------------

## The lamps on the tank batteries' catwalks, the rigs' mast work lights and their red top lights,
## a lamp at each gate: one billboard mesh on aircraft_lights.gdshader (Airport's light material:
## nothing by day, seen across the basin at night).
static func build_lights(parent: Node3D, plan: CityPlan) -> void:
	if plan == null or plan.macro == null or plan.macro.oil == null:
		return
	var mesh := lights_mesh(plan.macro)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "OilFieldLights"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(mi)


static var _lights: ArrayMesh = null
static var _lights_for: int = 0


static func lights_mesh(macro: MacroMap) -> ArrayMesh:
	if _lights != null and _lights_for == macro.get_instance_id():
		return _lights
	var f: OilField = macro.oil
	var specs: Array = []
	var gy := func(p: Vector2) -> float: return CityChunk.SIDEWALK_TOP + macro.relief_at(p)
	var warm := Color(1.0, 0.82, 0.55, 1.0)
	var white := Color(1.0, 0.95, 0.86, 1.0)
	var red := Color(1.0, 0.12, 0.06, 1.0)
	for pd: Dictionary in f.pads:
		var c: Vector2 = pd.c
		var out: Vector2 = pd.out
		var dir: Vector2 = pd.dir
		var y: float = gy.call(c)
		match int(pd.kind):
			OilField.Pad.BATTERY:
				var row := c + out * 3.2
				for k in 3:
					var n := 3 + absi(hash([f.seed, "oil_tanks", pd.id])) % 2
					var pitch := 2.75 * 2.0 + 1.0
					var w0 := row - dir * (float(n - 1) * 0.5 * pitch + 0.8)
					var w1 := row + dir * (float(n - 1) * 0.5 * pitch + 0.8)
					var lp := w0.lerp(w1, float(k) / 2.0) + out * 0.5
					specs.append([Vector3(lp.x, y + 7.0 + 0.35 + 1.75, lp.y), warm, 0.9, 4])
			OilField.Pad.RIG:
				var m := c + out * 2.0
				var base := y + 6.6
				for l in 5:
					var hh := 6.0 + float(l) * 6.5
					var wdt := lerpf(6.0, 1.44, hh / 36.0) * 0.5
					for corner: Vector2 in [Vector2(-1, -1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1)]:
						if (l + int(corner.x + 2.0)) % 2 == 1:
							continue
						var q := m + (dir * corner.x + out * corner.y) * (wdt + 0.3)
						specs.append([Vector3(q.x, base + hh, q.y), white, 1.4, 4])
				specs.append([Vector3(m.x, base + 37.2, m.y), red, 1.3, 2])
				for k in 4:
					var q := m + Vector2(cos(float(k) * PI * 0.5), sin(float(k) * PI * 0.5)) * 4.8
					specs.append([Vector3(q.x, base + 0.9, q.y), white, 1.0, 4])
	for g: Dictionary in f.gates:
		var p: Vector2 = g.p
		specs.append([Vector3(p.x, gy.call(p) + 4.2, p.y), warm, 0.8, 4])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for i in specs.size():
		var spec: Array = specs[i]
		var phase := float(i % 7) / 7.0
		var code := float(spec[3]) * 10.0 + phase * 9.0
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(spec[1])
			st.set_uv(corners[k])
			st.set_uv2(Vector2(spec[2], code))
			st.set_normal(Vector3.UP)
			st.add_vertex(spec[0])
	if specs.is_empty():
		return null
	_lights = st.commit()
	_lights.surface_set_material(0, Airport.light_material())
	_lights_for = macro.get_instance_id()
	return _lights


# --- A single well on a city lot ---------------------------------------------------------------------------

## Builds the well site OilField.lot_well() claimed (CityChunk._build_lot()): gravel inside a
## chain-link fence, the pumpjack, a small stock tank on some, the sign. Returns the ground rect the
## yards and the industrial ground plan round (the lot's whole fenced area).
static func build_lot(c: CityChunk, lot: Dictionary, w: Dictionary) -> Rect2:
	var pad: Rect2 = w.pad
	var full := c.level == CityChunk.Level.FULL and not c.capturing
	var mesh := OilKit.pumpjack(not full)
	var wear := OilField._h01([c.plan.seed, "oil_lot_wear", lot.seed])
	c._batch.add("pumpjack", mesh, well_xform(w, CityChunk.SIDEWALK_TOP + 0.05), Color.WHITE, well_custom(w, 0.4 + 0.5 * wear))
	if c.capturing:
		var g := CityChunk.SIDEWALK_TOP + c._gy((w.p as Vector2).x, (w.p as Vector2).y)
		var fwd := Vector2(cos(float(w.yaw)), -sin(float(w.yaw)))
		var sc: float = w.scale
		var bm := (w.p as Vector2) + fwd * ((OilKit.PIVOT.x - 0.5) * sc)
		(c.captured.boxes as Array).append([Transform3D(Basis(Vector3.UP, float(w.yaw)).scaled(Vector3(8.0 * sc, 0.9 * sc, 0.6 * sc)), Vector3(bm.x, g + 6.6 * sc, bm.y)), Color(0.42, 0.43, 0.4)])
		return pad
	var b := OilFieldBuild.new()
	b.ch = c
	b.full = full
	b.dirt = SurfaceTool.new()
	b.dirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	b.dirt.set_smooth_group(-1)
	# The gravel, flat on the lot.
	var steps := 4
	for j in steps:
		for i in steps:
			var r := Rect2(pad.position + pad.size * Vector2(float(i), float(j)) / float(steps), pad.size / float(steps))
			var q: Array = []
			var uvs: Array = []
			for pp: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				q.append(Vector3(pp.x, b._ground_y(pp.x, pp.y) + 0.07, pp.y))
				uvs.append(Vector2(0.0, 0.0))
			if _ccw_from_above(q):
				b._dquad(q, uvs, Vector2(2.0, 0.0))
			else:
				b._dquad([q[0], q[3], q[2], q[1]], [uvs[0], uvs[3], uvs[2], uvs[1]], Vector2(2.0, 0.0))
	b.dirt.set_material(dirt_material())
	var dm := MeshInstance3D.new()
	dm.name = "OilLotGravel"
	dm.mesh = b.dirt.commit()
	dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(dm)
	if not full:
		return pad
	var sc: float = w.scale
	var fwd := Vector2(cos(float(w.yaw)), -sin(float(w.yaw)))
	c._add_shape(Vector3(9.6 * sc, 2.6 * sc, 2.4 * sc), b._at((w.p as Vector2) + fwd * (-5.6 * sc), 1.3 * sc), float(w.yaw))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var ground := func(x: float, z: float) -> float: return CityChunk.SIDEWALK_TOP + c._gy(x, z)
	var cs := [pad.position, Vector2(pad.end.x, pad.position.y), pad.end, Vector2(pad.position.x, pad.end.y)]
	# The fence round it, a gate in the side facing the street.
	var dir: Vector2 = w.dir
	for e in 4:
		var a: Vector2 = cs[e]
		var bb: Vector2 = cs[(e + 1) % 4]
		var mid := (a + bb) * 0.5
		var gate := e == (absi(hash([c.plan.seed, "oil_lot_gate", lot.seed])) % 4)
		if gate:
			var dd := (bb - a).normalized()
			var l := a.distance_to(bb)
			OilKit.fence(st, a, a + dd * (l * 0.5 - 2.0), 2.4, ground, true)
			OilKit.fence(st, a + dd * (l * 0.5 + 2.0), bb, 2.4, ground, true)
			var inward := (pad.get_center() - mid).normalized()
			OilKit.sign(st, Vector3(mid.x + dd.x * 3.2, ground.call(mid.x, mid.y), mid.y + dd.y * 3.2) - Vector3(inward.x, 0, inward.y) * 0.35, -inward, ["WELL SITE - NO TRESPASSING", OilField.OPERATOR], 1.3, 0.8, 0.9)
		else:
			OilKit.fence(st, a, bb, 2.4, ground, true)
	if bool(w.tank):
		var side := Vector2(-dir.y, dir.x)
		var tp: Vector2 = pad.get_center() + side * (minf(pad.size.x, pad.size.y) * 0.5 - 2.6) - dir * 2.0
		OilKit.tank(st, Vector3(tp.x, ground.call(tp.x, tp.y), tp.y), 1.6, 4.6, OilKit.TANK_PAINTS[absi(hash([c.plan.seed, "oil_lot_tp", lot.seed])) % OilKit.TANK_PAINTS.size()], Vector3(-side.x, 0, -side.y))
		c._add_shape(Vector3(3.0, 4.6, 3.0), Vector3(tp.x, ground.call(tp.x, tp.y) + 2.3, tp.y))
	st.set_material(IndustrialKit.walls_material())
	var wm := MeshInstance3D.new()
	wm.name = "OilLotWalls"
	wm.mesh = st.commit()
	c.add_child(wm)
	return pad


## CityChunk._build_lot()'s hook: builds the claimed lot's well site and hands its fenced rect to
## the block step that lays the ground round the lots (Industrial's yards, YardFill's gardens), as a
## building's footprint would be.
static func claim_lot(c: CityChunk, lot: Dictionary, w: Dictionary, district: int) -> void:
	var pad := build_lot(c, lot, w)
	if Industrial.wanted(c, district):
		Industrial._state(c)
		(c._ind.entries as Array).append({"lot": lot, "parts": [pad], "plan": {}})
	elif YardFill.wanted(c, district):
		c._yard_lots.append({"lot": lot, "parts": [pad]})
