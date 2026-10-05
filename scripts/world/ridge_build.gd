class_name RidgeBuild
extends RefCounted
## The chunk side of the ridges (Ridges, RidgeKit): what a streamed chunk builds of them.
##   FULL, any zone: every tower whose foot is in the chunk (its cached body, its own leg
##     extensions and piers, box collision you can stand on), the antenna farm's masts, the huts,
##     dishes, tanks, domes and the lookout (each a cached mesh), the substation, the gates.
##   FULL and LOD: the fire roads and the pads in dirt (fire_road.gdshader), and in the city the
##     right of way's dry ground over the lots it took (plus its fence at FULL).
## Everything else - every tower, mast and wire seen from afar, the obstruction lights - is
## RidgeSystem's, and a FULL chunk tells it which of its far pieces to hide (RidgeCover) while it
## is drawn. All steps are hash- or data-driven: the chunk's rng is never touched.
## Positions: the chunk's local space is true world space (CityChunk.position = -world_offset).

static func attach(ch: CityChunk) -> Array[Callable]:
	var out: Array[Callable] = []
	if ch.capturing or ch.plan == null:
		return out
	var r := Ridges.of(ch.plan)
	if r == null:
		return out
	var rect := ch.owned_rect()
	out.append(func() -> void: _dirt(ch, r, rect))
	if ch.zone == MacroMap.Zone.CITY:
		out.append(func() -> void: _right_of_way(ch, r, rect))
	if ch.level != CityChunk.Level.FULL:
		return out
	var covers: Array[int] = []
	for t: Dictionary in r.towers_in(rect):
		covers.append(r.far_id("tower", int(t.id)))
		out.append(func() -> void: _tower(ch, r, t))
	for i in r.masts.size():
		var m: Dictionary = r.masts[i]
		if rect.has_point(m.pos):
			covers.append(r.far_id("mast", i))
			out.append(func() -> void: _mast(ch, r, m))
	var mine: Array[Dictionary] = []
	for i in r.sites.size():
		var s: Dictionary = r.sites[i]
		if rect.has_point(s.pos):
			covers.append(r.far_id("site", i))
			mine.append(s)
	if not mine.is_empty():
		out.append(func() -> void: _sites(ch, r, mine))
	if not r.substation.is_empty() and rect.intersects(r.substation.rect):
		covers.append(r.far_id("site", r.sites.size()))
		out.append(func() -> void: _substation(ch, r, rect))
	if not covers.is_empty():
		out.append(func() -> void:
			var cover := RidgeCover.new()
			cover.ids = covers
			ch.add_child(cover))
	return out


static func _body(ch: CityChunk, name: String) -> StaticBody3D:
	var existing := ch.get_node_or_null(name) as StaticBody3D
	if existing:
		return existing
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = 1
	body.collision_mask = 0
	ch.add_child(body)
	return body


static func _shape_box(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = xf
	body.add_child(cs)


static func _beam_shape(body: StaticBody3D, a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.1:
		return
	var z := d / l
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	_shape_box(body, Transform3D(Basis(x, z.cross(x), z), (a + b) * 0.5), Vector3(w, w, l))


static func _mesh(ch: CityChunk, mesh: Mesh, xf: Transform3D, name: String, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ch.add_child(mi)
	return mi


# --- Towers, masts, sites --------------------------------------------------------------------

static func _tower(ch: CityChunk, r: Ridges, t: Dictionary) -> void:
	var xf := Ridges.tower_xform(t)
	_mesh(ch, RidgeKit.tower_body(float(t.h), int(t.kind)), xf, "Tower%d" % int(t.id))
	_mesh(ch, RidgeKit.tower_legs(t), xf, "TowerLegs%d" % int(t.id))
	# Collision: the four legs to the waist, the hamper, each arm as a beam, so a player can land on
	# one and stand on its arms.
	var body := _body(ch, "RidgeBody")
	var sp := Ridges.spec(float(t.h))
	var feet := RidgeKit._local_feet(t)
	for c in 4:
		_beam_shape(body, xf * RidgeKit._corner(sp, c, float(feet[c])), xf * RidgeKit._corner(sp, c, float(sp.waist_y)), 0.5)
	var wh: float = sp.waist_half
	var top := float(sp.arm_y[2]) + float(sp.arm_depth)
	_shape_box(body, xf * Transform3D(Basis(), Vector3(0.0, (float(sp.waist_y) + top) * 0.5, 0.0)), Vector3(wh * 2.0, top - float(sp.waist_y), wh * 2.0))
	for k in 3:
		var tip: float = sp.arm_tip[k]
		_shape_box(body, xf * Transform3D(Basis(), Vector3(0.0, float(sp.arm_y[k]) + 0.2, 0.0)), Vector3(tip * 2.0, 0.5, wh * 1.4))
	_shape_box(body, xf * Transform3D(Basis(), Vector3(0.0, float(sp.h) - 0.3, 0.0)), Vector3(float(sp.peak_tip) * 2.0, 0.4, 0.8))


static func _mast(ch: CityChunk, r: Ridges, m: Dictionary) -> void:
	var p: Vector2 = m.pos
	var base: float = m.base
	_mesh(ch, RidgeKit.mast_mesh(m), Transform3D(Basis(), Vector3(p.x, base, p.y)), "Mast_%s" % m.id)
	var body := _body(ch, "RidgeBody")
	var rad := 1.0 if int(m.kind) == Ridges.Mast.GUYED else RidgeKit._mast_r(m, float(m.h) * 0.3)
	_shape_box(body, Transform3D(Basis(), Vector3(p.x, base + float(m.h) * 0.5, p.y)), Vector3(rad * 1.6, float(m.h), rad * 1.6))
	# The guys' anchors: a concrete deadman block where each lands, its turnbuckles.
	if (m.guys as Array).is_empty():
		return
	var acc := RidgeKit.Acc.new()
	for g: Vector2 in m.guys:
		var y := ch.plan.height_at(g)
		var d := (p - g).normalized()
		acc.box("concrete", Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)).scaled(Vector3(2.4, 1.0, 1.4)), Vector3(g.x, y + 0.1, g.y)), Color.WHITE)
		for k in (m.levels as Array).size():
			var off := Vector3(d.x, 0.0, d.y) * (float(k) - 1.0) * 0.25
			acc.cyl("steel", Vector3(g.x, y + 0.5, g.y) + off, Vector3(g.x, y + 0.5, g.y) + off + (Vector3(p.x, base + float(m.levels[k]), p.y) - Vector3(g.x, y, g.y)).normalized() * 1.6, 0.04, 0.04, 6, RidgeKit.STEEL_DARK)
	_mesh(ch, acc.commit({}), Transform3D(), "Anchors_%s" % m.id)


static func _sites(ch: CityChunk, r: Ridges, list: Array[Dictionary]) -> void:
	var body := _body(ch, "RidgeBody")
	var fence := RidgeKit.Acc.new()
	for s: Dictionary in list:
		var p: Vector2 = s.pos
		var base: float = s.base
		var xf := Transform3D(Basis(Vector3.UP, float(s.yaw)), Vector3(p.x, base, p.y))
		_mesh(ch, RidgeKit.site_mesh(s, r.seed), xf, "Site_%s" % s.id)
		match int(s.kind):
			Ridges.Site.TANK:
				var cs := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cyl.radius = float(s.r)
				cyl.height = float(s.h) + 0.5
				cs.shape = cyl
				cs.position = Vector3(p.x, base + cyl.height * 0.5, p.y)
				body.add_child(cs)
				_ring_fence(ch, fence, p, float(s.r) + 4.5, 16)
			Ridges.Site.DOME:
				var cs := CollisionShape3D.new()
				var sph := SphereShape3D.new()
				sph.radius = float(s.r)
				cs.shape = sph
				cs.position = Vector3(p.x, base + float(s.h) + float(s.r) * 0.62, p.y)
				body.add_child(cs)
				_shape_box(body, Transform3D(Basis(), Vector3(p.x, base + float(s.h) * 0.5, p.y)), Vector3(float(s.r) * 1.24, float(s.h), float(s.r) * 1.24))
				_ring_fence(ch, fence, p, float(s.r) + 5.0, 14)
			Ridges.Site.LOOKOUT:
				_shape_box(body, xf * Transform3D(Basis(), Vector3(0.0, 12.1, 0.0)), Vector3(7.2, 0.25, 7.2))
				_shape_box(body, xf * Transform3D(Basis(), Vector3(0.0, 13.6, 0.0)), Vector3(5.2, 3.0, 5.2))
				_shape_box(body, xf * Transform3D(Basis(), Vector3(0.0, 15.5, 0.0)), Vector3(6.2, 0.4, 6.2))
			Ridges.Site.HUT:
				_shape_box(body, xf * Transform3D(Basis(), Vector3(0.0, (float(s.h) + 0.3) * 0.5, 0.0)), Vector3(float(s.r) * 2.0, float(s.h) + 0.3, float(s.r) * 1.3))
	if not fence.parts.is_empty():
		_mesh(ch, fence.commit({"chain": chain_material()}), Transform3D(), "RidgeFence", false)


## A ring of chain-link round a site, posts on the ground.
static func _ring_fence(ch: CityChunk, acc: RidgeKit.Acc, c: Vector2, r: float, n: int) -> void:
	var pts: Array[Vector3] = []
	for i in n:
		var q := c + Vector2.from_angle(TAU * i / n) * r
		pts.append(Vector3(q.x, ch.plan.height_at(q), q.y))
	for i in n:
		_fence_panel(acc, pts[i], pts[(i + 1) % n], 2.1)


static func _fence_panel(acc: RidgeKit.Acc, a: Vector3, b: Vector3, h: float) -> void:
	var l := Vector2(b.x - a.x, b.z - a.z).length()
	var n := Vector3(-(b.z - a.z), 0.0, b.x - a.x).normalized()
	acc.tri("chain", a, b, b + Vector3(0, h, 0), n, Color.WHITE, [Vector2(0, 0), Vector2(l, 0), Vector2(l, h)])
	acc.tri("chain", a, b + Vector3(0, h, 0), a + Vector3(0, h, 0), n, Color.WHITE, [Vector2(0, 0), Vector2(l, h), Vector2(0, h)])
	acc.cyl("steel", a + Vector3(0, -0.3, 0), a + Vector3(0, h + 0.1, 0), 0.035, 0.035, 6, RidgeKit.STEEL)
	acc.beam("steel", a + Vector3(0, h, 0), b + Vector3(0, h, 0), 0.04, 0.04, RidgeKit.STEEL)


static var _chain: Material = null


static func chain_material() -> Material:
	if _chain == null:
		_chain = LotFill.chain_link_panel().surface_get_material(0)
	return _chain


# --- Dirt: fire roads, pads, gates -----------------------------------------------------------

static func _dirt(ch: CityChunk, r: Ridges, rect: Rect2) -> void:
	var hr := ch.plan.macro.hill_roads
	var dirt := Dirt.new()
	for ri: int in r.fire_roads:
		var road: Dictionary = hr.roads[ri]
		var pts: PackedVector2Array = road.points
		var half: float = float(road.width) * 0.5
		var along := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			if rect.has_point(a.lerp(b, 0.5)):
				var na := HillRoads._mitre(pts, i) * half
				var nb := HillRoads._mitre(pts, i + 1) * half
				var dir := (b - a) / maxf(seg, 0.01)
				var corners := [a + na, a - na, b - nb, b + nb]
				var hts: Array[float] = []
				for q: Vector2 in corners:
					hts.append(ch.plan.height_at(q) + 0.07)
				var p3: Array[Vector3] = []
				for k in 4:
					p3.append(Vector3(corners[k].x, hts[k], corners[k].y))
				var uvs := [Vector2(0.0, along), Vector2(1.0, along), Vector2(1.0, along + seg), Vector2(0.0, along + seg)]
				for tri: Array in [[0, 1, 2], [0, 2, 3]]:
					dirt.up_tri([p3[tri[0]], p3[tri[1]], p3[tri[2]]], [uvs[tri[0]], uvs[tri[1]], uvs[tri[2]]], dir)
			along += seg
	# Pads: the carved benches as a fan of dirt over their stadium outline.
	for road: Dictionary in hr.roads:
		if not road.get("pad", false):
			continue
		var pts: PackedVector2Array = road.points
		var c := (pts[0] + pts[1]) * 0.5
		if not rect.has_point(c):
			continue
		var h: float = road.heights[0]
		var half: float = float(road.width) * 0.5 + 1.5
		var ax := (pts[1] - pts[0]).normalized()
		var hl := pts[0].distance_to(pts[1]) * 0.5
		var ring: Array[Vector3] = []
		var m := 20
		for k in m:
			var d := Vector2.from_angle(TAU * k / m)
			var q := c + ax * clampf(d.dot(ax) * 1e4, -hl, hl) + d * half
			ring.append(Vector3(q.x, ch.plan.height_at(q) + 0.06, q.y))
		var centre := Vector3(c.x, h + 0.06, c.y)
		var pad_uv := Vector2(2.0, 0.0)
		for k in m:
			dirt.up_tri([centre, ring[(k + 1) % m], ring[k]], [pad_uv, pad_uv, pad_uv], Vector2(1.0, 0.0))
	if not dirt.v.is_empty():
		var mesh := dirt.mesh()
		mesh.surface_set_material(0, dirt_material())
		_mesh(ch, mesh, Transform3D(), "FireRoads", false)
	if ch.level != CityChunk.Level.FULL:
		return
	var body: StaticBody3D = null
	for g: Dictionary in r.gates_in(rect):
		var p: Vector2 = g.pos
		var y := ch.plan.height_at(p)
		var xf := Transform3D(Basis(Vector3.UP, float(g.yaw)), Vector3(p.x, y, p.y))
		_mesh(ch, RidgeKit.gate_mesh(float(g.w)), xf, "Gate")
		if body == null:
			body = _body(ch, "RidgeBody")
		_shape_box(body, xf * Transform3D(Basis(), Vector3(0.0, 0.6, 0.0)), Vector3(float(g.w) + 1.2, 1.2, 0.2))


## The dirt's triangles (an object, so its packed arrays are appended in place).
class Dirt:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

	## A triangle wound so its front faces up (Godot's front faces have cross(b - a, c - a)
	## pointing away from the eye: down, for an eye above), its flat normal up.
	func up_tri(p: Array, q: Array, dir: Vector2) -> void:
		var order := [0, 1, 2]
		var cr: Vector3 = ((p[1] as Vector3) - (p[0] as Vector3)).cross((p[2] as Vector3) - (p[0] as Vector3))
		if cr.y > 0.0:
			order = [0, 2, 1]
		var nn: Vector3 = cr.normalized() * (1.0 if cr.y > 0.0 else -1.0)
		for k: int in order:
			v.append(p[k])
			n.append(nn)
			uv.append(q[k])
			uv2.append(Vector2((p[k] as Vector3).x, (p[k] as Vector3).z))
			t.append_array(PackedFloat32Array([dir.x, 0.0, dir.y, 1.0]))

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TANGENT] = t
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		var out := ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return out


static var _dirt_mat: ShaderMaterial = null


static func dirt_material() -> ShaderMaterial:
	if _dirt_mat == null:
		_dirt_mat = ShaderMaterial.new()
		_dirt_mat.shader = load("res://shaders/fire_road.gdshader")
		_dirt_mat.set_shader_parameter("dirt_albedo", PropFactory.texture("hill_dirt", "Color"))
		_dirt_mat.set_shader_parameter("dirt_normal", PropFactory.texture("hill_dirt", "NormalGL"))
		_dirt_mat.set_shader_parameter("width", Ridges.FIRE_WIDTH)
	return _dirt_mat


# --- The city: the right of way and the substation -------------------------------------------

## The lots the right of way took (CityPlan.lots() asked Ridges.claims_lot()) are dry grass and
## dirt with a chain-link fence along the street; under the substation, its yard.
static func _right_of_way(ch: CityChunk, r: Ridges, rect: Rect2) -> void:
	ch.plan.lots(ch.ix, ch.iz)
	var cells: Array = r.claimed_cells.get(Vector2i(ch.ix, ch.iz), [])
	var sub_rect: Rect2 = r.substation.get("rect", Rect2())
	var mat := PropFactory.lawn(ROW_GRASS, hash([r.seed, "row"]), 0.95, 0.0)
	for cell: Rect2 in cells:
		if sub_rect.size.x > 0.0 and sub_rect.grow(2.0).intersects(cell):
			continue
		ch._add_slab(Vector3(cell.get_center().x, CityChunk.SIDEWALK_TOP + 0.03, cell.get_center().y),
			Vector3(maxf(cell.size.x - 0.6, 0.5), 0.04, maxf(cell.size.y - 0.6, 0.5)), ROW_GRASS, false, mat)
	if ch.level != CityChunk.Level.FULL:
		return
	# A fence round the cells' outline (an edge two cells share is left out).
	var block_rect: Rect2 = ch.plan.block(ch.ix, ch.iz).rect
	var inner := block_rect.grow(-ch.plan.sidewalk_width)
	for cell: Rect2 in cells:
		if sub_rect.size.x > 0.0 and sub_rect.grow(2.0).intersects(cell):
			continue
		var c := cell.grow(-0.4)
		var edges := [[Vector2(c.position.x, c.position.y), Vector2(c.end.x, c.position.y), true],
			[Vector2(c.position.x, c.end.y), Vector2(c.end.x, c.end.y), true],
			[Vector2(c.position.x, c.position.y), Vector2(c.position.x, c.end.y), false],
			[Vector2(c.end.x, c.position.y), Vector2(c.end.x, c.end.y), false]]
		for e: Array in edges:
			var mid: Vector2 = ((e[0] as Vector2) + (e[1] as Vector2)) * 0.5
			var shared := false
			for other: Rect2 in cells:
				if other != cell and other.grow(1.5).has_point(mid):
					shared = true
			# Only the edges toward the street: those within a few metres of the block's inner edge.
			var to_street := minf(minf(mid.x - inner.position.x, inner.end.x - mid.x), minf(mid.y - inner.position.y, inner.end.y - mid.y))
			if shared or to_street > 3.0:
				continue
			LotFill._fence(ch, mid, (e[0] as Vector2).distance_to(e[1]), bool(e[2]), CityChunk.SIDEWALK_TOP)
	if sub_rect.size.x <= 0.0 or not sub_rect.intersects(block_rect):
		return
	# The substation's yard: gravel inside a chain-link fence.
	ch._add_slab(Vector3(sub_rect.get_center().x, CityChunk.SIDEWALK_TOP + 0.04, sub_rect.get_center().y),
		Vector3(sub_rect.size.x, 0.06, sub_rect.size.y), Color(0.6, 0.58, 0.55), false, RidgeKit.material("gravel"))
	var g := sub_rect.grow(-0.5)
	LotFill._fence(ch, Vector2(g.get_center().x, g.position.y), g.size.x, true, CityChunk.SIDEWALK_TOP)
	LotFill._fence(ch, Vector2(g.get_center().x, g.end.y), g.size.x, true, CityChunk.SIDEWALK_TOP)
	LotFill._fence(ch, Vector2(g.position.x, g.get_center().y), g.size.y, false, CityChunk.SIDEWALK_TOP)
	LotFill._fence(ch, Vector2(g.end.x, g.get_center().y), g.size.y, false, CityChunk.SIDEWALK_TOP)


const ROW_GRASS := Color(0.47, 0.41, 0.25)


static func _substation(ch: CityChunk, r: Ridges, rect: Rect2) -> void:
	var sub: Dictionary = r.substation
	if not rect.has_point((sub.rect as Rect2).get_center()):
		return
	_mesh(ch, RidgeKit.substation_mesh(sub, Vector3.ZERO, r.seed), Transform3D(), "Substation")
	var body := _body(ch, "RidgeBody")
	var sr: Rect2 = sub.rect
	var y: float = sub.base
	var c := sr.get_center()
	var long_x := sr.size.x >= sr.size.y
	var la := maxf(sr.size.x, sr.size.y)
	var lb := minf(sr.size.x, sr.size.y)
	var ax := Vector3(1, 0, 0) if long_x else Vector3(0, 0, 1)
	var bx := Vector3(0, 0, 1) if long_x else Vector3(1, 0, 0)
	var nt := 3 if la > 150.0 else 2
	for i in nt:
		var along := lerpf(-la * 0.22, la * 0.22, float(i) / maxf(nt - 1, 1))
		var p := Vector3(c.x, y, c.y) + ax * along
		_shape_box(body, Transform3D(Basis(ax, Vector3.UP, bx), p + Vector3(0, 2.6, 0)), Vector3(7.0, 4.4, 5.6))
	var house := Vector3(c.x, y, c.y) + ax * (la * 0.5 - 12.0) + bx * (lb * 0.5 - 9.0)
	_shape_box(body, Transform3D(Basis(ax, Vector3.UP, bx), house + Vector3(0, 2.4, 0)), Vector3(18.6, 4.8, 10.6))
