class_name CemeteryBuild
extends RefCounted
## Builds a memorial park (Cemetery's plan) into the chunks of its blocks. Each chunk builds what
## falls in its owned rect (CityPlan.owned_rect(): a block plus the streets on its +X / +Z sides,
## so the rects tile the map): the turf clipped to it, every drive segment, wall run, tree, stone
## and lamp by where it stands, the chapel and the mausoleum by their centres. Any level:
##
## FULL   the rise as a lawn mesh (shaders/lawn.gdshader) with its collision, the drive with its
##        concrete edges, the low wall with the iron fence over it (shaders/cemetery_fence.gdshader,
##        pickets cut out), the gate (stone piers, lanterns, open iron leaves, the name in iron
##        letters on an arch), the chapel and the mausoleum (LandmarkGeo on the landmark shaders,
##        the chapel's windows lit after dark, the mausoleum floodlit), the trees (the city's
##        broadleaf species grown mature, stone pines, Italian cypress, a few palms), the stones
##        (CemeteryKit meshes, one batch per kind), lantern posts along the drive with real lights
##        and pools.
## LOD    the lawn as a slab, the buildings as far boxes, the closed streets' pavement caps.
## capture (the far city): the same as LOD (CityChunk records it). Skyline plants the trees.
##
## Every part sits on the pavement top plus the rise (Cemetery.height()) plus the relief (_gy):
## batch instances get the relief from the batch, everything else adds it here. All collision is
## ONE StaticBody3D in the sanctuary group, and the chunk's part of the site carries a sanctuary
## zone at every level (not in capture): see Cemetery's header.

const LAWN_TINT := Color(0.80, 0.98, 0.74)
const LAWN_LIFT := 0.03
## Ground grid step (m), FULL.
const GRID := 2.0
## Draw distances (m): flat markers, upright stones, monuments.
const FLAT_DRAW := 150.0
const UPRIGHT_DRAW := 220.0
const MONUMENT_DRAW := 320.0
## Visitors a chunk may spawn (each by a hash, on a drive point inside the chunk).
const VISITORS := 3
## Lantern posts lit with a real OmniLight3D: every n-th, and the gate's two.
const LIGHT_EVERY := 2


static func wanted(ch: CityChunk, block: Dictionary) -> bool:
	return Cemetery.enabled and ch.zone == MacroMap.Zone.CITY and String(block.get("grounds", "")) == "cemetery"


## The build steps of chunk `ch`'s part of the park (after the block's pavement).
static func steps(ch: CityChunk, block: Dictionary) -> Array[Callable]:
	var out: Array[Callable] = []
	var pl := Cemetery.plan_for(ch.plan, int(block.ix), int(block.iz))
	if pl.is_empty():
		return out
	var own := ch.plan.owned_rect(ch.ix, ch.iz)
	var part := own.intersection(pl.site as Rect2)
	var st := {"pl": pl, "own": own, "part": part, "geo": null, "body": null}
	out.append(func() -> void: _caps(ch, st))
	if ch.level != CityChunk.Level.FULL or ch.capturing:
		out.append(func() -> void: _far(ch, st))
		return out
	out.append(func() -> void: _ground(ch, st))
	out.append(func() -> void: _drive(ch, st))
	out.append(func() -> void: _fence(ch, st))
	out.append(func() -> void: _gate(ch, st))
	out.append(func() -> void: _chapel(ch, st))
	out.append(func() -> void: _mausoleum(ch, st))
	out.append(func() -> void: _trees(ch, st))
	# The stones a slice of rows at a time.
	var slices := 4
	for i in slices:
		out.append(func() -> void: _stones(ch, st, i, slices))
	out.append(func() -> void: _lamps(ch, st))
	out.append(func() -> void: _pavement(ch, st))
	out.append(func() -> void: _commit(ch, st))
	# A few visitors on the drive's verges, one a step, in the crowd cap.
	for i in VISITORS:
		out.append(func() -> void: _visitor(ch, st, i))
	return out


# --- Shared pieces ----------------------------------------------------------------------------

## The ground's height (chunk space, true world y) at world XZ `p`: relief + pavement + the rise.
static func _y(ch: CityChunk, pl: Dictionary, p: Vector2) -> float:
	return ch._gy(p.x, p.y) + CityChunk.SIDEWALK_TOP + LAWN_LIFT + Cemetery.height(pl, p)


static func _body(ch: CityChunk, st: Dictionary) -> StaticBody3D:
	if st.body == null:
		var body := StaticBody3D.new()
		body.name = "CemeteryBody"
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group(Sanctuary.BODY_GROUP)
		ch.add_child(body)
		st.body = body
	return st.body


static func _geo(st: Dictionary) -> LandmarkGeo:
	if st.geo == null:
		var g := LandmarkGeo.new()
		var s: int = (st.pl as Dictionary).seed
		g.use("stone", LandmarkMats.facade("cem_stone", "plaster_beige", 2.4,
			{"tint": Color(0.82, 0.78, 0.70), "roughness": 0.85, "joint_spacing": Vector2(0.9, 0.45), "joint_width": 0.012, "joint_dark": 0.7, "grime": 0.35}))
		g.use("coping", LandmarkMats.facade("cem_coping", "plaster_white", 2.0,
			{"tint": Color(0.86, 0.84, 0.80), "roughness": 0.7, "grime": 0.2}))
		g.use("kit", CemeteryKit.material())
		g.use("fence", fence_material())
		st.geo = g
		st.seed = s
	return st.geo


static var _fence_mat: ShaderMaterial = null


static func fence_material() -> ShaderMaterial:
	if _fence_mat == null:
		_fence_mat = ShaderMaterial.new()
		_fence_mat.shader = load("res://shaders/cemetery_fence.gdshader")
	return _fence_mat


static func _in(st: Dictionary, p: Vector2) -> bool:
	return (st.own as Rect2).has_point(p)


# --- Steps ------------------------------------------------------------------------------------

## The closed streets' ends between the outer pavements: paving, so the pavement ring runs on past
## the park (any level).
static func _caps(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var site: Rect2 = pl.site
	var plan := ch.plan
	var mat := PropFactory.road("sidewalk", 3.0, Color(0.95, 0.94, 0.92), hash([plan.seed, "cem_caps"]), 1.5, 0.45)
	for cl: Array in pl.closed:
		var axis: int = cl[0]
		var idx: int = cl[1]
		var pos := plan.road_pos(axis, idx)
		var w := plan.road_width(axis, idx)
		var rects: Array[Rect2] = []
		if axis == CityPlan.AXIS_X:
			rects.append(Rect2(pos - w * 0.5, float(cl[2]), w, site.position.y - float(cl[2])))
			rects.append(Rect2(pos - w * 0.5, site.end.y, w, float(cl[3]) - site.end.y))
		else:
			rects.append(Rect2(float(cl[2]), pos - w * 0.5, site.position.x - float(cl[2]), w))
			rects.append(Rect2(site.end.x, pos - w * 0.5, float(cl[3]) - site.end.x, w))
		for r in rects:
			if r.size.x < 0.1 or r.size.y < 0.1 or not _in(st, r.get_center()):
				continue
			ch._add_slab(Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP * 0.5, r.get_center().y), Vector3(r.size.x, CityChunk.SIDEWALK_TOP, r.size.y),
				ch.style.sidewalk, true, mat)


## LOD and the far city: the lawn as a slab, the buildings as boxes, the sanctuary zone.
static func _far(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var part: Rect2 = st.part
	if part.size.x > 1.0 and part.size.y > 1.0:
		ch._add_slab(Vector3(part.get_center().x, CityChunk.SIDEWALK_TOP + 0.02, part.get_center().y), Vector3(part.size.x, 0.04, part.size.y),
			ch.style.grass, false, PropFactory.lawn(LAWN_TINT, hash([ch.plan.seed, "cem_lawn"]), 0.1, 3.4))
	for k: String in ["chapel", "mausoleum"]:
		var bd: Dictionary = pl[k]
		var c: Vector2 = bd.c
		if not _in(st, c):
			continue
		var f: Vector2 = bd.f
		var h := 7.0 if k == "chapel" else 6.4
		var y := ch._gy(c.x, c.y) + CityChunk.SIDEWALK_TOP + Cemetery.height(pl, c)
		var basis := Basis(Vector3(-f.y, 0.0, f.x), Vector3.UP, Vector3(f.x, 0.0, f.y))
		var size := Vector3(float(bd.w), h, float(bd.d))
		var col := Color(0.90, 0.88, 0.82) if k == "chapel" else Color(0.66, 0.64, 0.60)
		# Old path far box (no windows): the batch adds the relief, so the centre is off the ground.
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(basis * Basis.from_scale(size), Vector3(c.x, y - ch._gy(c.x, c.y) + h * 0.5, c.y)), col,
			Color(0.0, 0.0, 0.0, 1.0))
		ch._add_lod_shape(Vector3(size.x if absf(f.y) > 0.5 else size.z, h, size.z if absf(f.y) > 0.5 else size.x), Vector3(c.x, y + h * 0.5, c.y))
		if k == "chapel":
			var t: Vector2 = _chapel_tower(bd)
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis.from_scale(Vector3(3.4, 13.0, 3.4)), Vector3(t.x, y - ch._gy(c.x, c.y) + 6.5, t.y)), col,
				Color(0.0, 0.0, 0.0, 1.0))
	if not ch.capturing:
		_zone(ch, st)


static func _zone(ch: CityChunk, st: Dictionary) -> void:
	var part: Rect2 = st.part
	if part.size.x < 1.0 or part.size.y < 1.0:
		return
	var c := part.get_center()
	Sanctuary.add_zone(ch, Vector3(c.x, ch._gy(c.x, c.y) + 20.0, c.y), Vector3(part.size.x * 0.5, 40.0, part.size.y * 0.5))


## The rise: a lawn mesh over the chunk's part of the site, its collision.
static func _ground(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var part: Rect2 = st.part
	if part.size.x < 0.5 or part.size.y < 0.5:
		return
	var nx := maxi(1, ceili(part.size.x / GRID))
	var nz := maxi(1, ceili(part.size.y / GRID))
	var pts := PackedVector3Array()
	pts.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			var p := part.position + Vector2(part.size.x * float(i) / float(nx), part.size.y * float(j) / float(nz))
			pts[j * (nx + 1) + i] = Vector3(p.x, _y(ch, pl, p), p.y)
	var st_mesh := SurfaceTool.new()
	st_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for j in nz + 1:
		for i in nx + 1:
			var v := pts[j * (nx + 1) + i]
			var l := pts[j * (nx + 1) + maxi(i - 1, 0)]
			var r := pts[j * (nx + 1) + mini(i + 1, nx)]
			var u := pts[maxi(j - 1, 0) * (nx + 1) + i]
			var d := pts[mini(j + 1, nz) * (nx + 1) + i]
			var nrm := (d - u).cross(r - l).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			st_mesh.set_normal(nrm)
			st_mesh.set_uv(Vector2(v.x, v.z))
			st_mesh.add_vertex(v)
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			# Clockwise from above (Godot's front faces).
			st_mesh.add_index(a)
			st_mesh.add_index(b)
			st_mesh.add_index(c)
			st_mesh.add_index(b)
			st_mesh.add_index(d)
			st_mesh.add_index(c)
			faces.append_array([pts[a], pts[b], pts[c], pts[b], pts[d], pts[c]])
	st_mesh.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "CemeteryLawn"
	mi.mesh = st_mesh.commit()
	mi.material_override = PropFactory.lawn(LAWN_TINT, hash([ch.plan.seed, "cem_lawn"]), 0.1, 3.4)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ch.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_body(ch, st).add_child(cs)


## The drive: an asphalt ribbon over the turf in three strips across (it follows the rise), with a
## concrete edge either side; built by the chunk each segment's midpoint is in.
static func _drive(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var road: PackedVector2Array = pl.road
	var g := SurfaceTool.new()
	g.begin(Mesh.PRIMITIVE_TRIANGLES)
	var e := SurfaceTool.new()
	e.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var faces := PackedVector3Array()
	var hw := Cemetery.ROAD_W * 0.5
	var run := 0.0
	for i in road.size() - 1:
		var p0 := road[i]
		var p1 := road[i + 1]
		var seg := p0.distance_to(p1)
		var r0 := run
		run += seg
		if seg < 0.01 or not _in(st, (p0 + p1) * 0.5):
			continue
		any = true
		var n0 := _side(road, i)
		var n1 := _side(road, i + 1)
		var across := [-hw - 0.35, -hw, -hw / 3.0, hw / 3.0, hw, hw + 0.35]
		for k in across.size() - 1:
			var o0: float = across[k]
			var o1: float = across[k + 1]
			var a := p0 + n0 * o0
			var b := p0 + n0 * o1
			var c := p1 + n1 * o1
			var d := p1 + n1 * o0
			var lift := 0.06 if (k > 0 and k < across.size() - 2) else 0.07
			var va := Vector3(a.x, _y(ch, pl, a) + lift, a.y)
			var vb := Vector3(b.x, _y(ch, pl, b) + lift, b.y)
			var vc := Vector3(c.x, _y(ch, pl, c) + lift, c.y)
			var vd := Vector3(d.x, _y(ch, pl, d) + lift, d.y)
			var tool := g if (k > 0 and k < across.size() - 2) else e
			var ua := Vector2(a.x, a.y)
			var ub := Vector2(b.x, b.y)
			var uc := Vector2(c.x, c.y)
			var ud := Vector2(d.x, d.y)
			_quad_up(tool, va, vb, vc, vd, ua, ub, uc, ud)
			faces.append_array([va, vb, vc, va, vc, vd])
	if not any:
		return
	g.generate_normals()
	g.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "CemeteryDrive"
	mi.mesh = g.commit()
	mi.material_override = PropFactory.road("asphalt", 5.0, Color(0.92, 0.92, 0.90), hash([ch.plan.seed, "cem_drive"]), 0.0, 0.35)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ch.add_child(mi)
	e.generate_normals()
	var me := MeshInstance3D.new()
	me.name = "CemeteryDriveEdge"
	me.mesh = e.commit()
	me.material_override = PropFactory.pbr("concrete", 2.0, Color(0.92, 0.91, 0.88))
	me.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ch.add_child(me)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_body(ch, st).add_child(cs)


## The unit normal to the drive's left at point i (mitred between its two segments).
static func _side(road: PackedVector2Array, i: int) -> Vector2:
	var d := Vector2.ZERO
	if i > 0:
		d += (road[i] - road[i - 1]).normalized()
	if i < road.size() - 1:
		d += (road[i + 1] - road[i]).normalized()
	d = d.normalized()
	return Vector2(-d.y, d.x)


static func _quad_up(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	for t: Array in [[a, b, c, ua, ub, uc], [a, c, d, ua, uc, ud]]:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		var u0: Vector2 = t[3]
		var u1: Vector2 = t[4]
		var u2: Vector2 = t[5]
		# Facing up, clockwise seen from above.
		if (p2 - p0).cross(p1 - p0).y < 0.0:
			var tp := p1
			p1 = p2
			p2 = tp
			var tu := u1
			u1 = u2
			u2 = tu
		tool.set_uv(u0)
		tool.add_vertex(p0)
		tool.set_uv(u1)
		tool.add_vertex(p1)
		tool.set_uv(u2)
		tool.add_vertex(p2)


## The perimeter: a low stone wall with a coping, iron posts and the cut-out picket fence above,
## in runs of up to 4 m (each standing on the relief at its middle), the gate's opening left.
const RUN := 4.0


static func _fence(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var site: Rect2 = pl.site
	var g := _geo(st)
	var body := _body(ch, st)
	var inset := 0.25
	var r := site.grow(-inset)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var gate: Vector2 = pl.gate
	var gap := Cemetery.GATE_W * 0.5 + 1.0
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var out_n := Vector2(dir.y, -dir.x)
		if out_n.dot(r.get_center() - a) > 0.0:
			out_n = -out_n
		var n := ceili(length / RUN)
		for i in n:
			var t0 := length * float(i) / float(n)
			var t1 := length * float(i + 1) / float(n)
			var p0 := a + dir * t0
			var p1 := a + dir * t1
			var mid := (p0 + p1) * 0.5
			if not _in(st, mid):
				continue
			# The gate's opening.
			var g0 := (gate - a).dot(dir)
			if absf((gate - a).dot(out_n)) < 1.0 and t1 > g0 - gap and t0 < g0 + gap:
				if t0 >= g0 - gap and t1 <= g0 + gap:
					continue
				if t0 < g0 - gap:
					p1 = a + dir * (g0 - gap)
				else:
					p0 = a + dir * (g0 + gap)
				mid = (p0 + p1) * 0.5
			var base := ch._gy(mid.x, mid.y) + CityChunk.SIDEWALK_TOP
			var len := p0.distance_to(p1)
			var basis := Basis(Vector3(dir.x, 0.0, dir.y), Vector3.UP, Vector3(out_n.x, 0.0, out_n.y))
			var wall_h := Cemetery.WALL_H
			g.box("stone", Vector3(mid.x, base + (wall_h - 0.4) * 0.5, mid.y), Vector3(len, wall_h + 0.4, 0.38), Color.WHITE, basis)
			g.box("coping", Vector3(mid.x, base + wall_h + 0.04, mid.y), Vector3(len + 0.02, 0.08, 0.48), Color.WHITE, basis, 0.015)
			# Posts at the run's ends, with a ball finial.
			for q: Vector2 in [p0, p1]:
				g.box("kit", Vector3(q.x, base + wall_h + 0.08 + Cemetery.FENCE_H * 0.5, q.y), Vector3(0.08, Cemetery.FENCE_H, 0.08), CemeteryKit.kc(CemeteryKit.K_IRON), basis)
				g.box("kit", Vector3(q.x, base + wall_h + 0.08 + Cemetery.FENCE_H + 0.05, q.y), Vector3(0.12, 0.1, 0.12), CemeteryKit.kc(CemeteryKit.K_IRON), basis)
			# The pickets: one quad, cut out by the shader (u metres along, v metres up).
			var y0 := base + wall_h + 0.08
			var y1 := y0 + Cemetery.FENCE_H
			var u0 := t0
			g.quad("fence", Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y),
				Vector3(out_n.x, 0.0, out_n.y), Vector2(u0, 0.0), Vector2(u0 + len, 0.0), Vector2(u0 + len, Cemetery.FENCE_H), Vector2(u0, Cemetery.FENCE_H))
			LandmarkGeo.shape_box(body, Vector3(mid.x, base + (wall_h + Cemetery.FENCE_H) * 0.5, mid.y), Vector3(len, wall_h + Cemetery.FENCE_H + 0.1, 0.4), basis)


## The gate: two stone piers with caps and lanterns, two iron leaves standing open, an iron arch
## over the opening with the park's name, the asphalt apron across the pavement to the kerb.
static func _gate(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var gate: Vector2 = pl.gate
	if not _in(st, gate):
		return
	var g := _geo(st)
	var body := _body(ch, st)
	var a: Vector2 = pl.a
	var n: Vector2 = pl.n
	var base := ch._gy(gate.x, gate.y) + CityChunk.SIDEWALK_TOP
	var basis := Basis(Vector3(a.x, 0.0, a.y), Vector3.UP, Vector3(-n.x, 0.0, -n.y))
	var half := Cemetery.GATE_W * 0.5
	var pier_h := 2.9
	for s: float in [-1.0, 1.0]:
		var p := gate + a * s * (half + 0.55)
		g.box("stone", Vector3(p.x, base + pier_h * 0.5 - 0.2, p.y), Vector3(1.1, pier_h + 0.4, 1.1), Color.WHITE, basis, 0.02)
		g.box("coping", Vector3(p.x, base + pier_h + 0.1, p.y), Vector3(1.3, 0.2, 1.3), Color.WHITE, basis, 0.03)
		g.box("coping", Vector3(p.x, base + 0.25, p.y), Vector3(1.24, 0.5, 1.24), Color.WHITE, basis, 0.02)
		_lantern(g, Vector3(p.x, base + pier_h + 0.2, p.y), basis, 1.0)
		LandmarkGeo.shape_box(body, Vector3(p.x, base + pier_h * 0.5, p.y), Vector3(1.1, pier_h, 1.1), basis)
		_light(ch, Vector3(p.x, base + pier_h + 0.6, p.y), 12.0, base)
		# A leaf, hinged on the pier's inner face and swung 70 degrees in.
		var hinge := gate + a * s * half
		var open := deg_to_rad(70.0)
		var leaf_dir := (-a * s) * cos(open) + n * sin(open)
		var tip := hinge + leaf_dir * half
		var y0 := base + 0.08
		var y1 := base + 2.2
		var face := Vector3(-leaf_dir.y, 0.0, leaf_dir.x)
		g.quad("fence", Vector3(hinge.x, y0, hinge.y), Vector3(tip.x, y0, tip.y), Vector3(tip.x, y1, tip.y), Vector3(hinge.x, y1, hinge.y), face,
			Vector2(0.0, 0.0), Vector2(half, 0.0), Vector2(half, 2.12), Vector2(0.0, 2.12))
		g.box("kit", Vector3(tip.x, (y0 + y1) * 0.5, tip.y), Vector3(0.06, y1 - y0 + 0.1, 0.06), CemeteryKit.kc(CemeteryKit.K_IRON), basis)
	# The arch: a flat iron band rising to a crown between the pier tops, the name standing on it.
	var span := half + 0.55
	var segs := 12
	var top_y := base + pier_h + 0.25
	var rise := 1.1
	var arc := func(t: float) -> Vector3:
		var x := lerpf(-span, span, t)
		var p := gate + a * x
		return Vector3(p.x, top_y + rise * (1.0 - pow(2.0 * t - 1.0, 2.0)), p.y)
	for i in segs:
		var p0: Vector3 = arc.call(float(i) / float(segs))
		var p1: Vector3 = arc.call(float(i + 1) / float(segs))
		var mid := (p0 + p1) * 0.5
		var d := p1 - p0
		var bb := Basis(d.normalized(), Vector3(-n.x, 0.0, -n.y).cross(d.normalized()).normalized(), Vector3(-n.x, 0.0, -n.y))
		g.box("kit", mid, Vector3(d.length() + 0.02, 0.16, 0.1), CemeteryKit.kc(CemeteryKit.K_IRON), bb.orthonormalized())
		g.box("kit", mid - Vector3(0, 0.62, 0), Vector3(d.length() + 0.02, 0.1, 0.08), CemeteryKit.kc(CemeteryKit.K_IRON), bb.orthonormalized())
		# Scrolls between the bands at every other joint.
		if i % 2 == 1:
			g.box("kit", mid - Vector3(0, 0.31, 0), Vector3(0.05, 0.5, 0.05), CemeteryKit.kc(CemeteryKit.K_IRON), bb.orthonormalized())
	# Letters between the two bands, on both faces.
	var name: String = pl.name
	g.use("gilt", LandmarkMats.plain("cem_gilt", Color(0.86, 0.66, 0.30), 0.28, 1.0))
	var geo := FreewayKit.text_geo(name, 0.46)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var width: float = geo[2]
	var squeeze := minf(1.0, (span * 2.0 - 0.8) / maxf(width, 0.01))
	var c_y := top_y + 0.85
	for side: float in [1.0, -1.0]:
		var out := Vector3(-n.x, 0.0, -n.y) * side
		var off := Vector3(-n.x, 0.0, -n.y) * 0.035 * side
		for k in range(0, idx.size() - 2, 3):
			var ps: Array[Vector3] = []
			for j in 3:
				var v := verts[idx[k + j]]
				# Seen from the street (side 1) the reader's right is -a; from inside, +a.
				var x := -v.x * squeeze * side
				var w := gate + a * x
				ps.append(Vector3(w.x, c_y + v.y, w.y) + off)
			g.tri("gilt", ps[0], ps[1], ps[2], out, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	# The apron across the pavement to the kerb.
	var sw := ch.plan.sidewalk_width
	var ap := gate - n * sw * 0.5
	ch._add_slab(Vector3(ap.x, CityChunk.SIDEWALK_TOP + 0.01, ap.y), Vector3(Cemetery.GATE_W if absf(a.x) > 0.5 else sw, 0.04, sw if absf(a.x) > 0.5 else Cemetery.GATE_W),
		ch.style.asphalt, false, PropFactory.road("asphalt", 5.0, Color(0.92, 0.92, 0.90), hash([ch.plan.seed, "cem_drive"]), 0.0, 0.35))


## A lantern (iron cage, glowing glass, a cap) standing on `at`, scaled by `s`.
static func _lantern(g: LandmarkGeo, at: Vector3, basis: Basis, s: float) -> void:
	var iron := CemeteryKit.kc(CemeteryKit.K_IRON)
	g.box("kit", at + Vector3(0, 0.06 * s, 0), Vector3(0.3, 0.12, 0.3) * s, iron, basis)
	g.box("kit", at + Vector3(0, 0.37 * s, 0), Vector3(0.28, 0.5, 0.28) * s, CemeteryKit.kc(CemeteryKit.K_GLASS), basis)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			g.box("kit", at + basis * (Vector3(cx * 0.145, 0.37, cz * 0.145) * s), Vector3(0.03, 0.52, 0.03) * s, iron, basis)
	g.box("kit", at + Vector3(0, 0.66 * s, 0), Vector3(0.38, 0.07, 0.38) * s, iron, basis)
	g.box("kit", at + Vector3(0, 0.75 * s, 0), Vector3(0.18, 0.12, 0.18) * s, iron, basis)
	g.box("kit", at + Vector3(0, 0.86 * s, 0), Vector3(0.05, 0.1, 0.05) * s, iron, basis)


## A real light, in DayNight's lamp group (energy set by the hour; hidden while it is zero).
static func _light(ch: CityChunk, at: Vector3, reach: float, ground: float = INF) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.omni_range = reach
	light.omni_attenuation = 1.6
	light.light_color = Color(1.0, 0.78, 0.52)
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 50.0
	light.distance_fade_length = 15.0
	light.add_to_group("lamp_light")
	ch.add_child(light)
	ch._batch.add("lamp_pool", PropFactory.light_pool(), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(9.0, 1.0, 9.0)),
		Vector3(at.x, (ground if ground != INF else at.y - 2.6) - ch._gy(at.x, at.z) + 0.09, at.z)), NightCity.pool_color(Vector2(at.x, at.z)))
	ch._batch.set_no_shadow("lamp_pool")


# --- The chapel ------------------------------------------------------------------------------

static func _chapel_tower(bd: Dictionary) -> Vector2:
	var c: Vector2 = bd.c
	var f: Vector2 = bd.f
	var s := Vector2(-f.y, f.x) * float(bd.side)
	return c + f * (float(bd.d) * 0.5 - 1.7) + s * (float(bd.w) * 0.5 + 1.2)


## A small Mission Revival chapel: whitewashed walls with tall lit windows on a stone base, a clay
## tile gable roof, a curved-parapet front with a round window, an arched door up three steps, and a
## bell tower at the front corner with open arched belfry, a bell, a tiled cap and a cross.
static func _chapel(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var bd: Dictionary = pl.chapel
	var c: Vector2 = bd.c
	if not _in(st, c):
		return
	var g := _geo(st)
	var body := _body(ch, st)
	var f: Vector2 = bd.f
	var s := Vector2(-f.y, f.x)
	var w: float = bd.w
	var d: float = bd.d
	var P := func(x: float, z: float) -> Vector2:
		return c + s * x + f * z
	var lo := INF
	var hi := -INF
	for q: Vector2 in [P.call(-w * 0.5, -d * 0.5), P.call(w * 0.5, -d * 0.5), P.call(w * 0.5, d * 0.5), P.call(-w * 0.5, d * 0.5)]:
		var y := _y(ch, pl, q)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	var floor_y := hi + 0.35
	var eave := floor_y + 6.2
	var ridge := eave + 3.4
	var k := "%d" % int(pl.seed)
	g.use("ch_wall", LandmarkMats.facade("cem_chapel_" + k, "plaster_white", 2.2,
		{"tint": Color(0.93, 0.91, 0.86), "roughness": 0.9, "grime": 0.3, "base_y": floor_y,
		"flood_strength": 0.5, "flood_base_y": floor_y + 0.3, "flood_reach": 9.0, "flood_floor": 0.25, "flood_spacing": 4.0, "seed": 7.0}))
	g.use("ch_win", LandmarkMats.facade("cem_chapel_win_" + k, "plaster_white", 2.2,
		{"tint": Color(0.93, 0.91, 0.86), "roughness": 0.9, "grime": 0.3, "base_y": floor_y,
		"win_pitch": Vector2(3.4, 0.0), "win_size": Vector2(0.95, 3.2), "win_band": Vector2(floor_y + 1.4, floor_y + 4.8),
		"win_sill": 0.3, "win_reveal": 0.25, "glass_color": Color(0.10, 0.08, 0.10), "lit_ratio": 1.0,
		"lit_color": Color(1.0, 0.62, 0.42), "lit_strength": 1.6, "seed": 11.0}))
	g.use("ch_roof", LandmarkMats.clay("cem_chapel"))
	g.use("ch_wood", LandmarkMats.plain("cem_wood", Color(0.30, 0.18, 0.10), 0.7))
	g.use("ch_bronze", LandmarkMats.plain("cem_bronze", Color(0.40, 0.26, 0.12), 0.35, 0.85))
	var foot := PackedVector2Array([P.call(-w * 0.5, -d * 0.5), P.call(w * 0.5, -d * 0.5), P.call(w * 0.5, d * 0.5), P.call(-w * 0.5, d * 0.5)])
	var plinth := PackedVector2Array([P.call(-w * 0.5 - 0.25, -d * 0.5 - 0.25), P.call(w * 0.5 + 0.25, -d * 0.5 - 0.25), P.call(w * 0.5 + 0.25, d * 0.5 + 0.25), P.call(-w * 0.5 - 0.25, d * 0.5 + 0.25)])
	g.prism("stone", plinth, lo - 0.5, floor_y, Color.WHITE, false, true)
	# Side walls carry the windows; the front and back are plain (their gables above).
	var fl := LandmarkGeo.ccw(foot)
	for i in 4:
		var a2 := fl[i]
		var b2 := fl[(i + 1) % 4]
		var along := (b2 - a2).normalized()
		var key := "ch_win" if absf(along.dot(f)) > 0.5 else "ch_wall"
		g.wall(key, a2, b2, floor_y, eave, Color.WHITE)
	# Gables (front: a curved Mission parapet above the roof line; back: plain).
	for zf: float in [1.0, -1.0]:
		var zz := d * 0.5 * zf
		var pts: Array[Vector2] = []
		var n_pts := 32
		for i in n_pts + 1:
			var t := float(i) / float(n_pts)
			var x := lerpf(-w * 0.5, w * 0.5, t)
			var y := eave + (ridge - eave) * (1.0 - absf(2.0 * t - 1.0))
			if zf > 0.0:
				# The Mission front: a parapet rising from low shoulders in an S-curve to a crest
				# with a round cap, always over the roof line behind it.
				var q := absf(2.0 * t - 1.0)
				var crest_h := ridge - eave + 1.2
				var f_q := 0.42 + 0.58 * smoothstep(0.62, 0.16, q)
				if q > 0.62:
					f_q = maxf(0.42 * smoothstep(1.02, 0.8, q), 0.14)
				if q < 0.16:
					f_q += 0.18 * sqrt(maxf(0.0, 1.0 - pow(q / 0.16, 2.0)))
				y = eave + crest_h * f_q
			pts.append(Vector2(x, y))
		var outward := Vector3(f.x, 0.0, f.y) * zf
		for i in n_pts:
			var x0 := pts[i].x
			var x1 := pts[i + 1].x
			var q0: Vector2 = P.call(x0, zz)
			var q1: Vector2 = P.call(x1, zz)
			g.quad("ch_wall", Vector3(q0.x, eave, q0.y), Vector3(q1.x, eave, q1.y), Vector3(q1.x, pts[i + 1].y, q1.y), Vector3(q0.x, pts[i].y, q0.y), outward,
				Vector2(x0, eave), Vector2(x1, eave), Vector2(x1, pts[i + 1].y), Vector2(x0, pts[i].y))
			if zf > 0.0:
				# The parapet's back face and its coping.
				var b0: Vector2 = P.call(x0, zz - 0.3)
				var b1: Vector2 = P.call(x1, zz - 0.3)
				g.quad("ch_wall", Vector3(b0.x, eave, b0.y), Vector3(b1.x, eave, b1.y), Vector3(b1.x, pts[i + 1].y, b1.y), Vector3(b0.x, pts[i].y, b0.y), -outward,
					Vector2(x0, eave), Vector2(x1, eave), Vector2(x1, pts[i + 1].y), Vector2(x0, pts[i].y))
				var mid := (q0 + q1) * 0.5 - f * 0.15
				var dy := pts[i + 1].y - pts[i].y
				var lenq := Vector2(x1 - x0, dy).length()
				var cop_basis := Basis(Vector3(s.x, 0.0, s.y), Vector3.UP, Vector3(f.x, 0.0, f.y))
				cop_basis = cop_basis * Basis(Vector3(0, 0, 1), atan2(dy, x1 - x0))
				g.box("coping", Vector3(mid.x, (pts[i].y + pts[i + 1].y) * 0.5 + 0.06, mid.y), Vector3(lenq + 0.02, 0.12, 0.45), Color.WHITE, cop_basis)
	# The roof: two clay slopes with eaves, a ridge.
	var over := 0.5
	for sx: float in [-1.0, 1.0]:
		var e0: Vector2 = P.call(sx * (w * 0.5 + over), -d * 0.5 - 0.4)
		var e1: Vector2 = P.call(sx * (w * 0.5 + over), d * 0.5 - 0.3)
		var r0: Vector2 = P.call(0.0, -d * 0.5 - 0.4)
		var r1: Vector2 = P.call(0.0, d * 0.5 - 0.3)
		var ey := eave - over * (ridge - eave) / (w * 0.5)
		var slope_len := Vector2(w * 0.5 + over, ridge - ey).length()
		var nrm := Vector3(s.x * sx, (w * 0.5 + over) / (ridge - ey), s.y * sx).normalized()
		g.quad("ch_roof", Vector3(e0.x, ey, e0.y), Vector3(e1.x, ey, e1.y), Vector3(r1.x, ridge, r1.y), Vector3(r0.x, ridge, r0.y), nrm,
			Vector2(0.0, 0.0), Vector2(d + 0.1, 0.0), Vector2(d + 0.1, slope_len), Vector2(0.0, slope_len))
		g.quad("ch_wood", Vector3(e0.x, ey - 0.12, e0.y), Vector3(e1.x, ey - 0.12, e1.y), Vector3(r1.x, ridge - 0.12, r1.y), Vector3(r0.x, ridge - 0.12, r0.y), -nrm,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	# The door: an arched opening in a stone surround, a pair of wooden leaves, three steps.
	var door_w := 2.0
	var door_h := 3.0
	var fz := d * 0.5
	var fb := Basis(Vector3(s.x, 0.0, s.y), Vector3.UP, Vector3(f.x, 0.0, f.y))
	var dc: Vector2 = P.call(0.0, fz + 0.03)
	g.box("ch_wood", Vector3(dc.x, floor_y + door_h * 0.5, dc.y), Vector3(door_w, door_h, 0.08), Color.WHITE, fb)
	var segs := 10
	for i in segs:
		var a0 := PI * float(i) / float(segs)
		var a1 := PI * float(i + 1) / float(segs)
		var r_in := door_w * 0.5
		var pa: Vector2 = P.call(cos(a0) * r_in, fz + 0.04)
		var pb: Vector2 = P.call(cos(a1) * r_in, fz + 0.04)
		g.tri("ch_wood", Vector3(dc.x, floor_y + door_h, dc.y), Vector3(pa.x, floor_y + door_h + sin(a0) * r_in, pa.y), Vector3(pb.x, floor_y + door_h + sin(a1) * r_in, pb.y),
			Vector3(f.x, 0.0, f.y), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		var ang := (a0 + a1) * 0.5
		var cp: Vector2 = P.call(cos(ang) * (r_in + 0.2), fz + 0.12)
		var cb := fb * Basis(Vector3(0, 0, 1), ang + PI * 0.5)
		g.box("coping", Vector3(cp.x, floor_y + door_h + sin(ang) * (r_in + 0.2), cp.y), Vector3(r_in * PI / float(segs) + 0.08, 0.4, 0.22), Color.WHITE, cb)
	for sx: float in [-1.0, 1.0]:
		var jp: Vector2 = P.call(sx * (door_w * 0.5 + 0.2), fz + 0.12)
		g.box("coping", Vector3(jp.x, floor_y + door_h * 0.5, jp.y), Vector3(0.4, door_h, 0.22), Color.WHITE, fb)
	for i in 3:
		var stp: Vector2 = P.call(0.0, fz + 0.45 + float(2 - i) * 0.35 + 0.35)
		var top := floor_y - float(i) * 0.12
		var depth := 0.35 * float(3 - i) + 0.4
		var sp: Vector2 = P.call(0.0, fz + depth * 0.5)
		g.box("coping", Vector3(sp.x, (top + lo - 0.4) * 0.5, sp.y), Vector3(door_w + 1.6 + float(i) * 0.4, top - lo + 0.4, depth), Color.WHITE, fb)
	# The round window in the front gable, glowing after dark.
	var rw: Vector2 = P.call(0.0, fz + 0.03)
	var rc := Vector3(rw.x, eave + 1.5, rw.y)
	var rr := 0.75
	for i in 16:
		var a0 := TAU * float(i) / 16.0
		var a1 := TAU * float(i + 1) / 16.0
		var q0: Vector2 = P.call(cos(a0) * rr, fz + 0.03)
		var q1: Vector2 = P.call(cos(a1) * rr, fz + 0.03)
		g.tri("kit", rc, Vector3(q0.x, rc.y + sin(a0) * rr, q0.y), Vector3(q1.x, rc.y + sin(a1) * rr, q1.y), Vector3(f.x, 0.0, f.y),
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, CemeteryKit.kc(CemeteryKit.K_GLASS))
		var mid_a := (a0 + a1) * 0.5
		var cp: Vector2 = P.call(cos(mid_a) * (rr + 0.12), fz + 0.1)
		g.box("coping", Vector3(cp.x, rc.y + sin(mid_a) * (rr + 0.12), cp.y), Vector3(rr * TAU / 16.0 + 0.06, 0.24, 0.16), Color.WHITE, fb * Basis(Vector3(0, 0, 1), mid_a + PI * 0.5))
	# The bell tower at the front corner.
	var t: Vector2 = _chapel_tower(bd)
	var tw := 3.4
	var t_top := floor_y + 9.6
	var bel0 := t_top
	var bel1 := t_top + 3.0
	var tb := fb
	g.box("stone", Vector3(t.x, (lo - 0.5 + floor_y) * 0.5, t.y), Vector3(tw + 0.4, floor_y - lo + 0.5, tw + 0.4), Color.WHITE, tb)
	g.box("ch_wall", Vector3(t.x, (floor_y + t_top) * 0.5, t.y), Vector3(tw, t_top - floor_y, tw), Color.WHITE, tb)
	g.box("coping", Vector3(t.x, t_top + 0.08, t.y), Vector3(tw + 0.3, 0.16, tw + 0.3), Color.WHITE, tb, 0.02)
	# The belfry: four corner piers with arches between, open to the sky.
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var pp := t + s * cx * (tw * 0.5 - 0.35) + f * cz * (tw * 0.5 - 0.35)
			g.box("ch_wall", Vector3(pp.x, (bel0 + bel1) * 0.5, pp.y), Vector3(0.7, bel1 - bel0, 0.7), Color.WHITE, tb)
	for side4 in 4:
		var dir4 := [f, -f, s, -s][side4] as Vector2
		var perp := Vector2(-dir4.y, dir4.x)
		var face_c := t + dir4 * (tw * 0.5 - 0.15)
		var span := tw - 1.4
		var ab := Basis(Vector3(perp.x, 0.0, perp.y), Vector3.UP, Vector3(dir4.x, 0.0, dir4.y))
		for i in 8:
			var a0 := PI * float(i) / 8.0
			var a1 := PI * float(i + 1) / 8.0
			var am := (a0 + a1) * 0.5
			var ap := face_c + perp * cos(am) * span * 0.5
			var apy := bel1 - 0.75 + sin(am) * 0.55
			g.box("ch_wall", Vector3(ap.x, (apy + bel1) * 0.5 + 0.05, ap.y), Vector3(span * 0.5 * PI / 8.0 + 0.05, bel1 - apy + 0.1, 0.3), Color.WHITE, ab)
	g.box("coping", Vector3(t.x, bel1 + 0.1, t.y), Vector3(tw + 0.2, 0.2, tw + 0.2), Color.WHITE, tb, 0.02)
	# The bell.
	g.use("bell", LandmarkMats.plain("cem_bell", Color(0.45, 0.30, 0.14), 0.35, 0.9))
	g.cylinder("bell", Vector3(t.x, bel0 + 0.9, t.y), 0.55, 0.9, 12, Color.WHITE, 0.25)
	# A tiled pyramid cap and a cross.
	var cap_y := bel1 + 0.2
	var apex := Vector3(t.x, cap_y + 2.0, t.y)
	var cs: Array[Vector2] = [t + (s + f) * (tw * 0.5 + 0.15), t + (s - f) * (tw * 0.5 + 0.15), t + (-s - f) * (tw * 0.5 + 0.15), t + (-s + f) * (tw * 0.5 + 0.15)]
	for i in 4:
		var q0 := cs[i]
		var q1 := cs[(i + 1) % 4]
		var mid := (q0 + q1) * 0.5
		var out := Vector3(mid.x - t.x, 0.9, mid.y - t.y)
		var l := q0.distance_to(q1)
		g.tri("ch_roof", Vector3(q0.x, cap_y, q0.y), Vector3(q1.x, cap_y, q1.y), apex, out, Vector2(0, 0), Vector2(l, 0), Vector2(l * 0.5, 2.2))
	var iron := CemeteryKit.kc(CemeteryKit.K_IRON)
	g.box("kit", apex + Vector3(0, 0.6, 0), Vector3(0.08, 1.2, 0.08), iron, tb)
	g.box("kit", apex + Vector3(0, 0.85, 0), Vector3(0.6, 0.08, 0.08), iron, tb)
	# Collision: the nave, the tower, the steps.
	var nave_c := Vector3(c.x, (lo + ridge) * 0.5, c.y)
	LandmarkGeo.shape_box(body, nave_c, Vector3(w, ridge - lo, d), fb)
	LandmarkGeo.shape_box(body, Vector3(t.x, (lo + bel1) * 0.5, t.y), Vector3(tw, bel1 - lo, tw), fb)
	ch._occluder_boxes.append([Transform3D(fb, Vector3(c.x, 0.0, c.y)), Vector3(0.0, (lo + eave) * 0.5, 0.0), Vector3(w - 0.6, eave - lo - 0.6, d - 0.6)])
	# A lamp over the door.
	var lp: Vector2 = P.call(0.0, fz + 0.6)
	_light(ch, Vector3(lp.x, floor_y + 3.9, lp.y), 10.0, floor_y)
	_lantern(g, Vector3(lp.x, floor_y + 3.6, lp.y) - Vector3(f.x, 0, f.y) * 0.4, fb, 0.8)


# --- The mausoleum ---------------------------------------------------------------------------

## A classical granite mausoleum on the crown: a stepped base, a cella of ashlar with bronze doors,
## a portico of four columns under an entablature and a low pediment, floodlit after dark.
static func _mausoleum(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var bd: Dictionary = pl.mausoleum
	var c: Vector2 = bd.c
	if not _in(st, c):
		return
	var g := _geo(st)
	var body := _body(ch, st)
	var f: Vector2 = bd.f
	var s := Vector2(-f.y, f.x)
	var w: float = bd.w
	var d: float = bd.d
	var P := func(x: float, z: float) -> Vector2:
		return c + s * x + f * z
	var lo := INF
	var hi := -INF
	for q: Vector2 in [P.call(-w * 0.5, -d * 0.5), P.call(w * 0.5, -d * 0.5), P.call(w * 0.5, d * 0.5 + 2.0), P.call(-w * 0.5, d * 0.5 + 2.0)]:
		var y := _y(ch, pl, q)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	var k := "%d" % int(pl.seed)
	var base := hi + 0.1
	var steps := 4
	var step_h := 0.2
	var floor_y := base + float(steps) * step_h
	g.use("m_stone", LandmarkMats.facade("cem_maus_" + k, "plaster_white", 2.0,
		{"tint": Color(0.72, 0.71, 0.68), "roughness": 0.55, "joint_spacing": Vector2(1.4, 0.7), "joint_width": 0.008, "joint_dark": 0.6, "grime": 0.45,
		"base_y": floor_y, "flood_strength": 0.45, "flood_base_y": floor_y + 0.2, "flood_reach": 8.0, "flood_floor": 0.2, "flood_spacing": 3.5, "seed": 5.0}))
	g.use("m_plain", LandmarkMats.facade("cem_maus_plain_" + k, "plaster_white", 2.0,
		{"tint": Color(0.74, 0.73, 0.70), "roughness": 0.5, "grime": 0.3,
		"base_y": floor_y, "flood_strength": 0.45, "flood_base_y": floor_y + 0.2, "flood_reach": 8.0, "flood_floor": 0.2, "flood_spacing": 3.5, "seed": 5.0}))
	g.use("m_bronze", LandmarkMats.plain("cem_door_bronze", Color(0.36, 0.25, 0.13), 0.45, 0.45))
	var fb := Basis(Vector3(s.x, 0.0, s.y), Vector3.UP, Vector3(f.x, 0.0, f.y))
	# The stepped base.
	for i in steps:
		var grow := float(steps - 1 - i) * 0.45
		var top := base + float(i + 1) * step_h
		var bot := lo - 0.4 if i == 0 else base + float(i) * step_h
		var sc: Vector2 = P.call(0.0, 0.0)
		g.box("m_plain", Vector3(sc.x, (top + bot) * 0.5, sc.y), Vector3(w + grow * 2.0, top - bot, d + grow * 2.0), Color.WHITE, fb, 0.015)
	# The cella at the back.
	var cella_d := d - 4.2
	var cella_c: Vector2 = P.call(0.0, -d * 0.5 + cella_d * 0.5)
	var wall_top := floor_y + 5.4
	g.box("m_stone", Vector3(cella_c.x, (floor_y + wall_top) * 0.5, cella_c.y), Vector3(w - 1.6, wall_top - floor_y, cella_d), Color.WHITE, fb)
	# The bronze doors in its front.
	var door_c: Vector2 = P.call(0.0, -d * 0.5 + cella_d + 0.04)
	g.box("m_bronze", Vector3(door_c.x, floor_y + 1.8, door_c.y), Vector3(2.4, 3.6, 0.1), Color.WHITE, fb)
	# Two leaves: raised panels, a meeting stile, pull rings.
	for sx: float in [-1.0, 1.0]:
		for py: float in [0.95, 2.55]:
			var pc: Vector2 = P.call(sx * 0.6, -d * 0.5 + cella_d + 0.1)
			g.box("m_bronze", Vector3(pc.x, floor_y + py, pc.y), Vector3(0.82, 1.25 if py < 2.0 else 1.55, 0.04), Color(0.8, 0.8, 0.8), fb, 0.012)
		var rp: Vector2 = P.call(sx * 0.16, -d * 0.5 + cella_d + 0.13)
		g.box("m_bronze", Vector3(rp.x, floor_y + 1.75, rp.y), Vector3(0.05, 0.22, 0.05), Color(1.3, 1.25, 1.1), fb)
	var ms: Vector2 = P.call(0.0, -d * 0.5 + cella_d + 0.1)
	g.box("m_bronze", Vector3(ms.x, floor_y + 1.8, ms.y), Vector3(0.06, 3.6, 0.05), Color(0.6, 0.6, 0.6), fb)
	var frame_c: Vector2 = P.call(0.0, -d * 0.5 + cella_d + 0.08)
	g.box("m_plain", Vector3(frame_c.x, floor_y + 3.8, frame_c.y), Vector3(3.3, 0.4, 0.18), Color.WHITE, fb)
	for sx: float in [-1.0, 1.0]:
		var jc: Vector2 = P.call(sx * 1.45, -d * 0.5 + cella_d + 0.08)
		g.box("m_plain", Vector3(jc.x, floor_y + 1.8, jc.y), Vector3(0.4, 3.6, 0.18), Color.WHITE, fb)
	# The portico: four columns, bases and capitals.
	var col_z := d * 0.5 - 1.2
	for i in 4:
		var x := lerpf(-w * 0.5 + 1.6, w * 0.5 - 1.6, float(i) / 3.0)
		var cp: Vector2 = P.call(x, col_z)
		g.box("m_plain", Vector3(cp.x, floor_y + 0.15, cp.y), Vector3(1.0, 0.3, 1.0), Color.WHITE, fb, 0.03)
		g.cylinder("m_plain", Vector3(cp.x, floor_y + 0.3, cp.y), 0.4, 4.5, 16, Color.WHITE, 0.34)
		g.box("m_plain", Vector3(cp.x, floor_y + 4.95, cp.y), Vector3(1.0, 0.3, 1.0), Color.WHITE, fb, 0.03)
		LandmarkGeo.shape_box(body, Vector3(cp.x, floor_y + 2.5, cp.y), Vector3(0.8, 5.0, 0.8), fb)
	# The entablature over the whole front and round the cella, then the pediment and roof.
	var ent0 := floor_y + 5.1
	var ent1 := ent0 + 1.0
	var ec: Vector2 = P.call(0.0, 0.0)
	g.box("m_plain", Vector3(ec.x, (ent0 + ent1) * 0.5, ec.y), Vector3(w - 0.6, ent1 - ent0, d - 0.4), Color.WHITE, fb)
	g.box("m_plain", Vector3(ec.x, ent1 + 0.1, ec.y), Vector3(w - 0.2, 0.2, d), Color.WHITE, fb, 0.02)
	var ped_h := 1.4
	var py0 := ent1 + 0.2
	for zf: float in [1.0, -1.0]:
		var zz := d * 0.5 * zf
		var l0: Vector2 = P.call(-w * 0.5 + 0.1, zz)
		var r0: Vector2 = P.call(w * 0.5 - 0.1, zz)
		var tp: Vector2 = P.call(0.0, zz)
		g.tri("m_stone", Vector3(l0.x, py0, l0.y), Vector3(r0.x, py0, r0.y), Vector3(tp.x, py0 + ped_h, tp.y), Vector3(f.x, 0.0, f.y) * zf,
			Vector2(-w * 0.5, py0), Vector2(w * 0.5, py0), Vector2(0.0, py0 + ped_h))
	for sx: float in [-1.0, 1.0]:
		var e0: Vector2 = P.call(sx * (w * 0.5 - 0.1), -d * 0.5)
		var e1: Vector2 = P.call(sx * (w * 0.5 - 0.1), d * 0.5)
		var r0: Vector2 = P.call(0.0, -d * 0.5)
		var r1: Vector2 = P.call(0.0, d * 0.5)
		var nrm := Vector3(s.x * sx, (w * 0.5) / ped_h, s.y * sx).normalized()
		g.quad("m_plain", Vector3(e0.x, py0, e0.y), Vector3(e1.x, py0, e1.y), Vector3(r1.x, py0 + ped_h, r1.y), Vector3(r0.x, py0 + ped_h, r0.y), nrm,
			Vector2(0, 0), Vector2(d, 0), Vector2(d, w * 0.5), Vector2(0, w * 0.5))
	# The name on the frieze, in bronze letters.
	var geo := FreewayKit.text_geo("IN MEMORIAM", 0.42)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var fz: Vector2 = P.call(0.0, d * 0.5 - 0.15)
	for t in range(0, idx.size() - 2, 3):
		var ps: Array[Vector3] = []
		for j in 3:
			var v := verts[idx[t + j]]
			var wp := fz - s * v.x
			ps.append(Vector3(wp.x, (ent0 + ent1) * 0.5 + v.y, wp.y))
		g.tri("m_bronze", ps[0], ps[1], ps[2], Vector3(f.x, 0.0, f.y), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	# Urns on the bottom step's front corners.
	for sx: float in [-1.0, 1.0]:
		var up: Vector2 = P.call(sx * (w * 0.5 + 0.6), d * 0.5 + 0.9)
		var uy := _y(ch, pl, up) - 0.05
		g.box("m_plain", Vector3(up.x, uy + 0.45, up.y), Vector3(0.8, 0.9, 0.8), Color.WHITE, fb, 0.03)
		g.cylinder("m_plain", Vector3(up.x, uy + 0.9, up.y), 0.2, 0.2, 12, Color.WHITE, 0.32)
		g.cylinder("m_plain", Vector3(up.x, uy + 1.1, up.y), 0.32, 0.45, 12, Color.WHITE, 0.22)
	LandmarkGeo.shape_box(body, Vector3(cella_c.x, (lo + py0 + ped_h) * 0.5, cella_c.y), Vector3(w - 1.6, py0 + ped_h - lo, cella_d), fb)
	LandmarkGeo.shape_box(body, Vector3(ec.x, (lo + floor_y) * 0.5, ec.y), Vector3(w, floor_y - lo, d), fb)
	LandmarkGeo.shape_box(body, Vector3(ec.x, (ent0 + py0 + 0.6) * 0.5, ec.y), Vector3(w, py0 + 0.6 - ent0, d), fb)
	ch._occluder_boxes.append([Transform3D(fb, Vector3(cella_c.x, 0.0, cella_c.y)), Vector3(0.0, (floor_y + wall_top) * 0.5, 0.0), Vector3(w - 2.2, wall_top - floor_y - 0.6, cella_d - 0.6)])


# --- Trees, stones, lamps ---------------------------------------------------------------------

static func _trees(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var body := _body(ch, st)
	for t: Array in pl.trees:
		var p: Vector2 = t[0]
		if not _in(st, p):
			continue
		var kind: int = t[1]
		var h: float = t[2]
		var yaw: float = t[3]
		var at := Vector3(p.x, CityChunk.SIDEWALK_TOP + LAWN_LIFT + Cemetery.height(pl, p) - 0.05, p.y)
		var hs := absi(hash([pl.seed, p.x, p.y]))
		var r := func(salt: int) -> float:
			return float(absi(hash([hs, salt])) % 1000) / 1000.0
		var tint := Color(lerpf(0.86, 1.06, r.call(1)), lerpf(0.92, 1.08, r.call(2)), lerpf(0.86, 1.02, r.call(3)))
		var variety := Color(r.call(4), r.call(5), r.call(6), lerpf(0.25, 1.0, r.call(7)))
		var trunk := 0.6
		match kind:
			5:
				var s := PropFactory.hill_tree_scale(1, h)
				ch._batch.add("cem_pine", PropFactory.model_hill_tree(1), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint, variety)
				trunk = 0.8
			6:
				var wide := lerpf(0.85, 1.2, r.call(10))
				ch._batch.add("cem_cypress", CemeteryKit.cypress(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(h * wide, h, h * wide)), at), Color.WHITE)
				trunk = 0.4
			7:
				var v := hs % PropFactory.PALM_VARIANTS
				var s := lerpf(0.95, 1.25, r.call(8))
				ch._batch.add("cem_palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint)
				trunk = 0.5
			_:
				# The city's broadleaf species grown old: the top of their range and a little over.
				var target: Vector2 = PropFactory.CITY_TREE_TARGET[kind]
				var s := PropFactory.city_tree_scale(kind, target.y * lerpf(1.05, 1.3, r.call(9)))
				ch._batch.add("cem_tree_%d" % kind, PropFactory.model_tree(kind), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint, variety)
		var base := ch._gy(p.x, p.y) + at.y
		LandmarkGeo.shape_box(body, Vector3(p.x, base + 3.0, p.y), Vector3(trunk, 6.0, trunk))


## The stones: rows across the lawn (Cemetery.graves() is the layout), a slice of it per step.
static func _stones(ch: CityChunk, st: Dictionary, slice: int, slices: int) -> void:
	var pl: Dictionary = st.pl
	var body := _body(ch, st)
	for gr: Array in Cemetery.graves(pl, st.own as Rect2, slice, slices):
		var key: String = gr[0]
		var p: Vector2 = gr[1]
		var yaw: float = gr[2]
		var col: Color = gr[3]
		var custom: Color = gr[4]
		var lean: float = gr[5]
		var y := CityChunk.SIDEWALK_TOP + LAWN_LIFT + Cemetery.height(pl, p)
		var basis := Basis(Vector3.UP, yaw)
		if key.begins_with("flat"):
			# Flush with the turf: tilted to the rise.
			var e := 0.4
			var gx := Cemetery.height(pl, p + Vector2(e, 0)) - Cemetery.height(pl, p - Vector2(e, 0))
			var gz := Cemetery.height(pl, p + Vector2(0, e)) - Cemetery.height(pl, p - Vector2(0, e))
			var nrm := Vector3(-gx / (2.0 * e), 1.0, -gz / (2.0 * e)).normalized()
			var axis := Vector3.UP.cross(nrm)
			if axis.length_squared() > 1e-8:
				basis = Basis(axis.normalized(), Vector3.UP.angle_to(nrm)) * basis
		else:
			y -= 0.06
			if lean != 0.0:
				basis = basis * Basis(Vector3(1, 0, 0), lean)
		ch._batch.add("cem_" + key, CemeteryKit.mesh(key), Transform3D(basis, Vector3(p.x, y, p.y)), col, custom)
		var box: Variant = COLLIDE.get(key)
		if box != null:
			var b: Vector3 = box
			LandmarkGeo.shape_box(body, Vector3(p.x, ch._gy(p.x, p.y) + y + b.y * 0.5, p.y), b, Basis(Vector3.UP, yaw))


## Collision boxes (size) of the stones that stand up; flat markers have none.
const COLLIDE := {
	"tablet": Vector3(0.95, 1.2, 0.4), "gothic": Vector3(0.85, 1.35, 0.35), "slant": Vector3(0.95, 0.6, 0.55),
	"marble": Vector3(0.6, 1.1, 0.12), "cross": Vector3(0.7, 1.4, 0.5), "obelisk": Vector3(1.3, 3.4, 1.3),
	"column": Vector3(1.0, 2.9, 1.0), "family": Vector3(2.1, 1.5, 0.75),
}


static func _lamps(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var g := _geo(st)
	var lamps: Array = pl.lamps
	for i in lamps.size():
		var p: Vector2 = lamps[i]
		if not _in(st, p):
			continue
		var y := _y(ch, pl, p)
		var iron := CemeteryKit.kc(CemeteryKit.K_IRON)
		g.box("kit", Vector3(p.x, y + 0.15, p.y), Vector3(0.3, 0.3, 0.3), iron)
		g.cylinder("kit", Vector3(p.x, y + 0.3, p.y), 0.06, 2.6, 8, iron, 0.045)
		_lantern(g, Vector3(p.x, y + 2.9, p.y), Basis(), 0.9)
		if i % LIGHT_EVERY == 0:
			_light(ch, Vector3(p.x, y + 3.1, p.y), 10.0, y)


static func _commit(ch: CityChunk, st: Dictionary) -> void:
	_zone(ch, st)
	if st.geo != null:
		var g: LandmarkGeo = st.geo
		g.commit(ch, "CemeteryWorks", true)
	for key: String in CemeteryKit.MESHES:
		var k := "cem_" + key
		if key.begins_with("flat"):
			ch._batch.set_no_shadow(k)
			ch._batch.set_draw_distance(k, FLAT_DRAW)
		elif key in ["obelisk", "column", "family", "coping"]:
			ch._batch.set_draw_distance(k, MONUMENT_DRAW)
			ch._batch.set_shadow_reach(k, 90.0)
		else:
			ch._batch.set_draw_distance(k, UPRIGHT_DRAW)
			ch._batch.set_shadow_reach(k, 55.0)


static func _visitor(ch: CityChunk, st: Dictionary, i: int) -> void:
	var pl: Dictionary = st.pl
	var road: PackedVector2Array = pl.road
	var h := hash([pl.seed, ch.ix, ch.iz, i, "visitor"])
	if float(absi(h) % 1000) / 1000.0 > 0.7:
		return
	var k := 2 + absi(hash([h, "at"])) % maxi(1, road.size() - 4)
	var p := road[k]
	if not _in(st, p):
		return
	if not ch._take_crowd_room():
		return
	var dir := (road[k + 1] - road[k - 1]).normalized()
	var side := 1.0 if (h & 1) == 0 else -1.0
	p += Vector2(-dir.y, dir.x) * side * (Cemetery.ROAD_W * 0.5 + 1.2)
	var ped := CemeteryVisitor.new()
	ped.pl = pl
	ped.setup(Rect2(), 3.0, h)
	ped.position = Vector3(p.x, ch.ground_y(p.x, p.y) + LAWN_LIFT + Cemetery.height(pl, p) + 0.1, p.y)
	ch.add_child(ped)


## The outer pavement round the park (the block's own furniture step does not run here): street
## lamps and kerb trees at the street's usual rhythm, none in front of the gate. A private rng.
const PAVEMENT_LAMP_STEP := 34.0
const PAVEMENT_TREE_STEP := 11.0


static func _pavement(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var site: Rect2 = pl.site
	var sw := ch.plan.sidewalk_width
	var kerb := site.grow(sw - 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([pl.seed, ch.ix, ch.iz, "pavement"])
	var corners := [kerb.position, Vector2(kerb.end.x, kerb.position.y), kerb.end, Vector2(kerb.position.x, kerb.end.y)]
	var gate: Vector2 = pl.gate
	for e in 4:
		var a: Vector2 = corners[e]
		var b: Vector2 = corners[(e + 1) % 4]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var n_l := int(length / PAVEMENT_LAMP_STEP)
		for i in n_l:
			var p := a + dir * (float(i) + 0.5) * length / float(n_l)
			if _in(st, p) and p.distance_to(gate) > 9.0:
				ch._add_lamp(Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y))
		var n_t := int(length / PAVEMENT_TREE_STEP)
		for i in n_t:
			var p := a + dir * (float(i) + 0.5) * length / float(n_t)
			if not _in(st, p) or p.distance_to(gate) < 9.0 or rng.randf() < 0.3:
				continue
			# Clear of the lamps.
			var t := fmod((float(i) + 0.5) * length / float(n_t), length / float(maxi(n_l, 1)))
			if absf(t - length / float(maxi(n_l, 1)) * 0.5) < 3.0:
				continue
			ch._add_tree(Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y), rng)
