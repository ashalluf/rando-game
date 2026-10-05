class_name LandmarkReservoir
extends RefCounted
## The reservoir in the front range (Reservoir is the data: the carved lake, its level, the dam's
## arc, the spillway and the trail): what stands on it. The FORM of the reservoir behind the famous
## sign in LA's hills - a 1920s concrete arch-gravity dam with a row of arches under its crest road,
## ornamental balustrades and old lanterns, an intake tower with a copper dome on a footbridge,
## a gauge tower, a stepped spillway round the east abutment - with every name invented (there is
## no lettering on any of it).
##
## Built by Landmarks.build() as the "reservoir" landmark: the far copy (CityStreamer) and the
## detailed one (the FULL chunk round Reservoir.ANCHOR) share the same meshes (`_parts()`, cached
## per seed), so nothing changes at the hand-over. The far copy is the water and the structure;
## the detailed one adds collision, the lights, the trail with its fence, the pines.
##
## Geometry is LandmarkGeo on two materials (shaders/reservoir_dam.gdshader, which reads what a
## face is from its vertex colour, and reservoir_railing.gdshader for the pierced balustrade
## panels); the water is its own mesh on shaders/reservoir_water.gdshader. The terrain's bathtub
## ring is the shared terrain material's (apply_ground()). Everything is a pure function of the
## Reservoir: no random numbers, only hashes of the seed and the place.

## Arcade bay along the crest (m of arc at the upstream face), the vertical zone it occupies under
## the crest, and the parapets.
const BAY := 5.6
const CAP := 7.0
const PARAPET_T := 0.5
const PLINTH_H := 0.45
const RAIL_TOP := 1.15
const COPING_H := 0.15
## How far under the toe the faces run (hidden by the ground; shown where the gorge falls away).
const FOUND := 14.0
## Lantern standards: every LAMP_EVERY bays, both parapets, staggered.
const LAMP_EVERY := 2
const LANTERN_Y := 5.1
## Real lights: one OmniLight3D for every LIGHT_EVERY-th lantern (DayNight's lamp group).
const LIGHT_EVERY := 2
## The far copy's railings and lanterns stop drawing past this.
const TRIM_DRAW := 900.0

static var _cache: Dictionary = {}
static var _ground_for: Reservoir = null
static var _dam_mat: ShaderMaterial = null
static var _rail_mat: ShaderMaterial = null
static var _water_mat: ShaderMaterial = null
static var _water_tris: int = 0


static func build(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	if plan == null or plan.macro == null or plan.macro.reservoir == null:
		return
	var res: Reservoir = plan.macro.reservoir
	apply_ground(res)
	var parts := _parts(res)
	var water := MeshInstance3D.new()
	water.name = "ReservoirWater"
	water.mesh = parts.water
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(water)
	var dam := MeshInstance3D.new()
	dam.name = "ReservoirDam"
	dam.mesh = parts.dam
	parent.add_child(dam)
	var trim := MeshInstance3D.new()
	trim.name = "ReservoirTrim"
	trim.mesh = parts.trim
	if not detailed:
		trim.visibility_range_end = TRIM_DRAW
		trim.visibility_range_end_margin = TRIM_DRAW * 0.1
		trim.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(trim)
	if not detailed:
		return
	var detail := MeshInstance3D.new()
	detail.name = "ReservoirTrail"
	detail.mesh = parts.detail
	detail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	detail.visibility_range_end = 450.0
	parent.add_child(detail)
	if statics:
		var faces: PackedVector3Array = parts.collision
		if not faces.is_empty():
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			shape.backface_collision = true
			var cs := CollisionShape3D.new()
			cs.name = "ReservoirShape"
			cs.shape = shape
			statics.add_child(cs)
	var batch := MultiMeshBatch.new()
	_fence(res, batch)
	_pines(res, plan.macro, batch)
	var lamps: Array = parts.lamps
	for k in lamps.size():
		var at: Vector3 = lamps[k]
		batch.add("res_pool", PropFactory.light_pool(Color(1.0, 0.72, 0.42), 0.9), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(11.0, 1.0, 11.0)), Vector3(at.x, res.crest + 0.06, at.z)))
		if k % LIGHT_EVERY != 0:
			continue
		var light := OmniLight3D.new()
		light.position = at
		light.omni_range = 15.0
		light.omni_attenuation = 1.4
		light.light_color = Color(1.0, 0.7, 0.4)
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 90.0
		light.distance_fade_length = 25.0
		light.add_to_group("lamp_light")
		parent.add_child(light)
	batch.set_no_shadow("res_pool")
	batch.set_no_shadow("res_fence_mesh")
	batch.set_shadow_distance("res_fence_post", 40.0)
	batch.build(parent)


## The cached parts (meshes, collision faces, lantern centres, triangle counts, build time) for
## probes and the smoke test.
static func parts(res: Reservoir) -> Dictionary:
	return _parts(res)


## The shared terrain material's bathtub ring (reservoir_shore.gdshaderinc), once per reservoir.
static func apply_ground(res: Reservoir) -> void:
	if _ground_for == res:
		return
	_ground_for = res
	var mat := PropFactory.terrain_material() as ShaderMaterial
	if mat == null:
		return
	var tex := ImageTexture.create_from_image(res.mask_image(256, 34.0))
	mat.set_shader_parameter("lake_mask", tex)
	var box := Reservoir.BOX
	mat.set_shader_parameter("lake_box", Vector4(box.position.x, box.position.y, box.size.x, box.size.y))
	mat.set_shader_parameter("lake_level", res.level)


static func dam_material() -> ShaderMaterial:
	if _dam_mat == null:
		_dam_mat = ShaderMaterial.new()
		_dam_mat.shader = load("res://shaders/reservoir_dam.gdshader")
	return _dam_mat


static func rail_material() -> ShaderMaterial:
	if _rail_mat == null:
		_rail_mat = ShaderMaterial.new()
		_rail_mat.shader = load("res://shaders/reservoir_railing.gdshader")
	return _rail_mat


## Vertex colour for a face of `kind` (reservoir_concrete.gdshaderinc's K_*), `face` 0 upstream,
## 1 downstream, 0.5 anything else.
static func _k(kind: int, face: float = 0.5) -> Color:
	return Color(1.0, face, 1.0, float(kind) / 16.0)


const K_FACE := 0
const K_ROAD := 1
const K_TRIM := 2
const K_DARK := 3
const K_METAL := 4
const K_LAMP := 5
const K_ROOF := 6
const K_GAUGE := 7
const K_TRAIL := 8
const K_CHUTE := 9
const K_GLASS := 10
const K_BRASS := 11


## Every mesh of the reservoir, built once per Reservoir: {"water", "dam", "trim", "detail",
## "collision", "lamps" (lantern centres), "gauge"}.
static func _parts(res: Reservoir) -> Dictionary:
	var key := res.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var t0 := Time.get_ticks_usec()
	_water_tris = 0
	var p := {}
	if _water_mat == null:
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = load("res://shaders/reservoir_water.gdshader")
	p.water = _water(res)
	var dm := dam_material()
	dm.set_shader_parameter("res_level", res.level)
	dm.set_shader_parameter("res_crest", res.crest)
	dm.set_shader_parameter("res_toe", res.toe)
	var rm := rail_material()
	var geo := LandmarkGeo.new()
	geo.use("dam", dm)
	var ctx := {"res": res, "geo": geo, "lamps": [], "bridges": []}
	_dam_body(ctx)
	_intake_tower(ctx)
	# A second, older and smaller tower off the dam's west half.
	_intake_tower(ctx, 0.36, 15.0, 2.7, 3.4)
	_spillway(ctx)
	_apron(ctx)
	var gauge := _gauge_site(res)
	if not gauge.is_empty():
		_gauge_tower(ctx, gauge)
	p.gauge = gauge
	p.dam_tris = geo.triangles
	p.dam = _commit(geo)
	var coll := geo.collision
	# The trim: balustrades, lanterns, the footbridge's truss.
	var tg := LandmarkGeo.new()
	tg.use("dam", dm)
	tg.use("rail", rm)
	ctx.geo = tg
	_parapets(ctx)
	_footbridge_truss(ctx)
	p.trim_tris = tg.triangles
	p.trim = _commit(tg)
	coll.append_array(tg.collision)
	# The trail.
	var dg := LandmarkGeo.new()
	dg.use("dam", dm)
	ctx.geo = dg
	_trail(ctx)
	p.detail_tris = dg.triangles
	p.detail = _commit(dg)
	coll.append_array(dg.collision)
	p.collision = coll
	p.lamps = ctx.lamps
	# What the water mirrors and where the lanterns stand in it.
	var wm := _water_mat
	var prof := res.ridge_profile()
	wm.set_shader_parameter("level", res.level)
	wm.set_shader_parameter("lake_centre", res.lake_centre())
	var dist := PackedFloat32Array()
	var hgt := PackedFloat32Array()
	var tans: PackedFloat32Array = prof[0]
	var dists: PackedFloat32Array = prof[2]
	for k in tans.size():
		dist.append(dists[k])
		hgt.append(tans[k] * dists[k])
	wm.set_shader_parameter("ridge_dist", dist)
	wm.set_shader_parameter("ridge_height", hgt)
	wm.set_shader_parameter("ridge_dam", prof[1])
	wm.set_shader_parameter("dam_centre", res.dam_centre)
	wm.set_shader_parameter("dam_radius", Reservoir.DAM_RADIUS - PARAPET_T * 0.5)
	wm.set_shader_parameter("dam_span", Vector2(res.dam_a0, res.dam_a1))
	wm.set_shader_parameter("lamp_y", res.crest + LANTERN_Y)
	wm.set_shader_parameter("lamp_spacing", BAY * LAMP_EVERY * 0.5)
	# The basin lies south of the dam.
	wm.set_shader_parameter("city_dir", (res.dam_centre - res.lake_centre()).normalized())
	dm.set_shader_parameter("bay_start", 0.0)
	dm.set_shader_parameter("bay_width", ctx.get("bay", BAY))
	dm.set_shader_parameter("lamp_start", 0.0)
	dm.set_shader_parameter("lamp_spacing", float(ctx.get("bay", BAY)) * LAMP_EVERY)
	rm.set_shader_parameter("panel_len", float(ctx.get("panel", 2.4)))
	p.water_tris = _water_tris
	p.build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_cache[key] = p
	return p


static func _commit(geo: LandmarkGeo) -> Mesh:
	var holder := Node3D.new()
	var mi := geo.commit(holder, "tmp")
	var mesh: Mesh = mi.mesh if mi else ArrayMesh.new()
	holder.free()
	return mesh


# --- The water ------------------------------------------------------------------------------------

## One quad a grid cell wherever the flood (or the cell next to it) is, at the level: the ground
## stands over it past the shore, so the waterline is drawn by the depth test exactly where the
## carved ground crosses the level. COLOR.r is the depth / 40 m.
static func _water(res: Reservoir) -> ArrayMesh:
	var n := res.grid_size()
	var wet := res.wet_grid
	var near := res._dilate(wet, 2)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var nrms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var node_index := {}
	var add_node := func(i: int, j: int) -> int:
		var key := j * n.x + i
		if node_index.has(key):
			return node_index[key]
		var p := res.grid_point(i, j)
		verts.append(Vector3(p.x, res.level, p.y))
		cols.append(Color(clampf(res.depth_at_node(i, j) / 40.0, 0.0, 1.0), 0.0, 0.0, 1.0))
		nrms.append(Vector3.UP)
		uvs.append(p)
		node_index[key] = verts.size() - 1
		return verts.size() - 1
	for j in n.y - 1:
		for i in n.x - 1:
			var c := j * n.x + i
			if near[c] == 0 and near[c + 1] == 0 and near[c + n.x] == 0 and near[c + n.x + 1] == 0:
				continue
			var mid := res.grid_point(i, j) + Vector2(Reservoir.CELL, Reservoir.CELL) * 0.5
			# Not past the dam's face (its body hides the cells that straddle it).
			var q := mid - res.dam_centre
			var ang := atan2(q.x, -q.y)
			if q.length() < Reservoir.DAM_RADIUS - 2.0 and ang > res.dam_a0 - 0.15 and ang < res.dam_a1 + 0.15:
				continue
			# Only round the lake: a dry hollow in the box below the level is not the lake.
			if not res.near_lake(mid, 12.0):
				continue
			var a: int = add_node.call(i, j)
			var b: int = add_node.call(i + 1, j)
			var d: int = add_node.call(i + 1, j + 1)
			var e: int = add_node.call(i, j + 1)
			# Clockwise seen from above (Godot's front face).
			idx.append_array(PackedInt32Array([a, b, d, a, d, e]))
	_water_tris = idx.size() / 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if not idx.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _water_mat)
	return mesh


# --- The dam ------------------------------------------------------------------------------------

## A point of the dam's frame: angle `a` round its centre, radius `r`, height `y`.
static func _at(res: Reservoir, a: float, r: float, y: float) -> Vector3:
	var p := res.arc_point(a, r)
	return Vector3(p.x, y, p.y)


## The way out of the dam's frame at angle `a` (upstream, radially outward).
static func _out(res: Reservoir, a: float) -> Vector3:
	var d := res.arc_point(a, 1.0) - res.dam_centre
	return Vector3(d.x, 0.0, d.y)


## The dam: the upstream face, the crest road, the cornice, the arcade of round-headed blind
## arches under it, the string course, the battered downstream face with its buttress ribs, and
## the end walls into the rock.
static func _dam_body(ctx: Dictionary) -> void:
	var res: Reservoir = ctx.res
	var g: LandmarkGeo = ctx.geo
	var R := Reservoir.DAM_RADIUS
	var a0 := res.dam_a0
	var a1 := res.dam_a1
	var span := (a1 - a0) * R
	var nb := maxi(4, int(round(span / BAY)))
	var bay := span / float(nb)
	ctx.bay = bay
	var da := (a1 - a0) / float(nb)
	var crest := res.crest
	var y_f := res.toe - FOUND
	var cw := Reservoir.CREST_WIDTH
	var r_b := R - cw + 0.2
	var r_f := R - cw - 0.8
	var y_lo := crest - CAP
	var y_hi := crest - 1.0
	var steps := nb * 2
	var face_up := _k(K_FACE, 0.0)
	var face_dn := _k(K_FACE, 1.0)
	var trim := _k(K_TRIM)
	for s in steps:
		var aa := lerpf(a0, a1, float(s) / steps)
		var ab := lerpf(a0, a1, float(s + 1) / steps)
		var ua := (aa - a0) * R
		var ub := (ab - a0) * R
		var mid := (aa + ab) * 0.5
		var out := _out(res, mid)
		# Upstream face, from the foundation to the crest (the plinth of the parapet goes on top).
		g.quad("dam", _at(res, aa, R, y_f), _at(res, ab, R, y_f), _at(res, ab, R, crest), _at(res, aa, R, crest), out,
			Vector2(ua, y_f), Vector2(ub, y_f), Vector2(ub, crest), Vector2(ua, crest), face_up, true)
		# The crest road between the parapets.
		g.quad("dam", _at(res, aa, R - cw + PARAPET_T, crest), _at(res, ab, R - cw + PARAPET_T, crest), _at(res, ab, R - PARAPET_T, crest), _at(res, aa, R - PARAPET_T, crest), Vector3.UP,
			Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, cw), Vector2(ua, cw), _k(K_ROAD), true)
		# The cornice: its top under the parapet, its face, its soffit.
		var r_c := r_f - 0.35
		g.quad("dam", _at(res, aa, r_c, crest - 0.12), _at(res, ab, r_c, crest - 0.12), _at(res, ab, R - cw, crest - 0.12), _at(res, aa, R - cw, crest - 0.12), Vector3.UP,
			Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 1.0), Vector2(ua, 1.0), trim, true)
		g.quad("dam", _at(res, aa, R - cw, crest), _at(res, ab, R - cw, crest), _at(res, ab, R - cw, crest - 0.12), _at(res, aa, R - cw, crest - 0.12), -out,
			Vector2(ua, crest), Vector2(ub, crest), Vector2(ub, crest - 0.12), Vector2(ua, crest - 0.12), trim)
		g.quad("dam", _at(res, aa, r_c, crest - 0.12), _at(res, ab, r_c, crest - 0.12), _at(res, ab, r_c, y_hi), _at(res, aa, r_c, y_hi), -out,
			Vector2(ua, crest - 0.12), Vector2(ub, crest - 0.12), Vector2(ub, y_hi), Vector2(ua, y_hi), trim)
		g.quad("dam", _at(res, aa, r_c, y_hi), _at(res, ab, r_c, y_hi), _at(res, ab, r_f, y_hi), _at(res, aa, r_f, y_hi), Vector3.DOWN,
			Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 1.0), Vector2(ua, 1.0), trim)
		# String course under the arcade.
		var r_s := r_f - 0.3
		g.quad("dam", _at(res, aa, r_s, y_lo), _at(res, ab, r_s, y_lo), _at(res, ab, r_f, y_lo), _at(res, aa, r_f, y_lo), Vector3.UP,
			Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 1.0), Vector2(ua, 1.0), trim, true)
		g.quad("dam", _at(res, aa, r_s, y_lo), _at(res, ab, r_s, y_lo), _at(res, ab, r_s, y_lo - 0.55), _at(res, aa, r_s, y_lo - 0.55), -out,
			Vector2(ua, y_lo), Vector2(ub, y_lo), Vector2(ub, y_lo - 0.55), Vector2(ua, y_lo - 0.55), trim)
		# The battered face: from under the string course down past the toe.
		var y_t := y_lo - 0.55
		var r_t := r_s + 0.3
		var r_bot := r_t - Reservoir.BATTER * (y_t - y_f)
		var want := (-out).normalized() + Vector3.UP * Reservoir.BATTER
		g.quad("dam", _at(res, aa, r_t, y_t), _at(res, ab, r_t, y_t), _at(res, ab, r_bot, y_f), _at(res, aa, r_bot, y_f), want,
			Vector2(ua, y_t), Vector2(ub, y_t), Vector2(ub, y_f), Vector2(ua, y_f), face_dn, true)
		g.quad("dam", _at(res, aa, r_s, y_lo - 0.55), _at(res, ab, r_s, y_lo - 0.55), _at(res, ab, r_t, y_t), _at(res, aa, r_t, y_t), Vector3.DOWN,
			Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 1.0), Vector2(ua, 1.0), trim)
	# The arcade: per bay, an arched opening in the outer plane recessed to the back plane.
	for b in nb:
		var ac := a0 + (float(b) + 0.5) * da
		_arch_bay(ctx, ac, bay, r_f, r_b, y_lo, y_hi)
	# Buttress ribs on the battered face at every second pier.
	var y_t2 := y_lo - 0.55
	var r_t2 := r_f
	for b in range(2, nb - 1, 2):
		var ap := a0 + float(b) * da
		_rib(ctx, ap, r_t2, y_t2, y_f)
	# End walls into the rock.
	for side in 2:
		var ae := a0 if side == 0 else a1
		var tang := _at(res, ae + 0.001, R, 0.0) - _at(res, ae, R, 0.0)
		var w := tang.normalized() * (-1.0 if side == 0 else 1.0)
		var r_bot2 := r_f - Reservoir.BATTER * (y_t2 - y_f)
		var poly := [_at(res, ae, R, y_f), _at(res, ae, R, crest), _at(res, ae, r_f - 0.35, crest), _at(res, ae, r_f, y_t2), _at(res, ae, r_bot2, y_f)]
		for k in range(1, poly.size() - 1):
			g.tri("dam", poly[0], poly[k], poly[k + 1], w, Vector2(0.0, (poly[0] as Vector3).y), Vector2(1.0, (poly[k] as Vector3).y), Vector2(2.0, (poly[k + 1] as Vector3).y), face_dn, true)


## One bay of the arcade under the crest: piers either side, the sill under the opening, the arch
## and its spandrels in the outer plane; the jambs, sill, intrados and back wall of the recess.
static func _arch_bay(ctx: Dictionary, ac: float, bay: float, r_f: float, r_b: float, y_lo: float, y_hi: float) -> void:
	var res: Reservoir = ctx.res
	var g: LandmarkGeo = ctx.geo
	var R := Reservoir.DAM_RADIUS
	var u0 := (ac - res.dam_a0) * R
	var wo := bay * 0.34
	var y_s := y_lo + 0.55
	var y_sp := y_hi - 0.45 - wo
	var out := _out(res, ac)
	var at := func(u: float, r: float, y: float) -> Vector3:
		return _at(res, ac + u / R, r, y)
	var c := _k(K_FACE, 1.0)
	var tr := _k(K_TRIM)
	var hb := bay * 0.5
	# Piers.
	for side in [-1.0, 1.0]:
		var ua: float = side * hb
		var ub: float = side * wo
		g.quad("dam", at.call(ua, r_f, y_lo), at.call(ub, r_f, y_lo), at.call(ub, r_f, y_hi), at.call(ua, r_f, y_hi), -out,
			Vector2(u0 + ua, y_lo), Vector2(u0 + ub, y_lo), Vector2(u0 + ub, y_hi), Vector2(u0 + ua, y_hi), c, true)
	# Under the opening.
	g.quad("dam", at.call(-wo, r_f, y_lo), at.call(wo, r_f, y_lo), at.call(wo, r_f, y_s), at.call(-wo, r_f, y_s), -out,
		Vector2(u0 - wo, y_lo), Vector2(u0 + wo, y_lo), Vector2(u0 + wo, y_s), Vector2(u0 - wo, y_s), c, true)
	# The arch: spandrels to the top, the intrados back to the recess.
	var segs := 8
	var prev_u := -wo
	var prev_y := y_sp
	for i in range(1, segs + 1):
		var th := PI - PI * float(i) / segs
		var cu := cos(th) * wo
		var cy := y_sp + sin(th) * wo
		g.quad("dam", at.call(prev_u, r_f, prev_y), at.call(cu, r_f, cy), at.call(cu, r_f, y_hi), at.call(prev_u, r_f, y_hi), -out,
			Vector2(u0 + prev_u, prev_y), Vector2(u0 + cu, cy), Vector2(u0 + cu, y_hi), Vector2(u0 + prev_u, y_hi), c, true)
		var thm := PI - PI * (float(i) - 0.5) / segs
		var tang := (at.call(0.05, r_f, 0.0) - at.call(0.0, r_f, 0.0)).normalized() as Vector3
		var inward := -tang * cos(thm) - Vector3.UP * sin(thm)
		g.quad("dam", at.call(prev_u, r_f, prev_y), at.call(cu, r_f, cy), at.call(cu, r_b, cy), at.call(prev_u, r_b, prev_y), inward,
			Vector2(u0 + prev_u, 0.0), Vector2(u0 + cu, 0.0), Vector2(u0 + cu, 1.0), Vector2(u0 + prev_u, 1.0), tr)
		prev_u = cu
		prev_y = cy
	# Jambs, sill, back.
	for side in [-1.0, 1.0]:
		var uj: float = side * wo
		var into: Vector3 = (at.call(0.0, r_f, 0.0) - at.call(uj, r_f, 0.0)).normalized()
		g.quad("dam", at.call(uj, r_f, y_s), at.call(uj, r_b, y_s), at.call(uj, r_b, y_sp), at.call(uj, r_f, y_sp), into,
			Vector2(0.0, y_s), Vector2(1.0, y_s), Vector2(1.0, y_sp), Vector2(0.0, y_sp), c)
	g.quad("dam", at.call(-wo, r_f, y_s), at.call(wo, r_f, y_s), at.call(wo, r_b, y_s), at.call(-wo, r_b, y_s), Vector3.UP,
		Vector2(u0 - wo, 0.0), Vector2(u0 + wo, 0.0), Vector2(u0 + wo, 1.0), Vector2(u0 - wo, 1.0), tr, true)
	g.quad("dam", at.call(-wo, r_b, y_s), at.call(wo, r_b, y_s), at.call(wo, r_b, y_sp + wo), at.call(-wo, r_b, y_sp + wo), -out,
		Vector2(u0 - wo, y_s), Vector2(u0 + wo, y_s), Vector2(u0 + wo, y_sp + wo), Vector2(u0 - wo, y_sp + wo), _k(K_FACE, 1.0))
	# A drain spout at the foot of each recess, dark: the streaks under it come from here.
	g.box("dam", at.call(0.0, r_f - 0.3, y_lo + 0.2), Vector3(0.35, 0.3, 0.7), _k(K_DARK), Basis(Vector3.UP, atan2(-out.x, -out.z)))


## A buttress rib down the battered face at angle `ap`: 1.6 m wide, standing 1.1 m proud.
static func _rib(ctx: Dictionary, ap: float, r_top: float, y_top: float, y_f: float) -> void:
	var res: Reservoir = ctx.res
	var g: LandmarkGeo = ctx.geo
	var R := Reservoir.DAM_RADIUS
	var hw := 0.8 / R
	var proud := 1.1
	var r_bot := r_top - Reservoir.BATTER * (y_top - y_f)
	var out := _out(res, ap)
	var c := _k(K_FACE, 1.0)
	var u0 := (ap - res.dam_a0) * R
	var want := (-out).normalized() + Vector3.UP * Reservoir.BATTER
	# Front.
	g.quad("dam", _at(res, ap - hw, r_top - proud, y_top - 1.2), _at(res, ap + hw, r_top - proud, y_top - 1.2), _at(res, ap + hw, r_bot - proud, y_f), _at(res, ap - hw, r_bot - proud, y_f), want,
		Vector2(u0 - 0.8, y_top), Vector2(u0 + 0.8, y_top), Vector2(u0 + 0.8, y_f), Vector2(u0 - 0.8, y_f), c, true)
	# The weathered top, sloping back into the face.
	g.quad("dam", _at(res, ap - hw, r_top, y_top), _at(res, ap + hw, r_top, y_top), _at(res, ap + hw, r_top - proud, y_top - 1.2), _at(res, ap - hw, r_top - proud, y_top - 1.2), Vector3.UP - out.normalized(),
		Vector2(u0 - 0.8, 0.0), Vector2(u0 + 0.8, 0.0), Vector2(u0 + 0.8, 1.0), Vector2(u0 - 0.8, 1.0), _k(K_TRIM), true)
	# Sides.
	for side in [-1.0, 1.0]:
		var a: float = ap + side * hw
		var tang := (_at(res, a + 0.001 * side, R, 0.0) - _at(res, a, R, 0.0)).normalized()
		g.quad("dam", _at(res, a, r_top, y_top), _at(res, a, r_top - proud, y_top - 1.2), _at(res, a, r_bot - proud, y_f), _at(res, a, r_bot, y_f), tang,
			Vector2(0.0, y_top), Vector2(proud, y_top - 1.2), Vector2(proud, y_f), Vector2(0.0, y_f), c)


## The parapets along both edges of the crest: a plinth, posts every half bay (a lantern standard
## every LAMP_EVERY bays, staggered between the two sides), the pierced panels between the posts
## and a coping over them.
static func _parapets(ctx: Dictionary) -> void:
	var res: Reservoir = ctx.res
	var g: LandmarkGeo = ctx.geo
	var R := Reservoir.DAM_RADIUS
	var crest := res.crest
	var cw := Reservoir.CREST_WIDTH
	var bay: float = ctx.bay
	var nb := maxi(4, int(round((res.dam_a1 - res.dam_a0) * R / BAY)))
	var posts := nb * 2
	var dpost := (res.dam_a1 - res.dam_a0) / float(posts)
	var lamps: Array = ctx.lamps
	ctx.panel = bay * 0.5 - 0.45
	for side in 2:
		var r_in := R - PARAPET_T if side == 0 else R - cw
		var r_out := R if side == 0 else R - cw + PARAPET_T
		var r_mid := (r_in + r_out) * 0.5
		for s in posts:
			var aa := res.dam_a0 + float(s) * dpost
			var ab := aa + dpost
			var ua := (aa - res.dam_a0) * R
			var ub := (ab - res.dam_a0) * R
			var out := _out(res, (aa + ab) * 0.5)
			# The plinth: both faces and its top (the panels stand on it).
			for face in 2:
				var rr := r_out if face == 0 else r_in
				var w := out if face == 0 else -out
				if side == 1:
					w = -w
				g.quad("dam", _at(res, aa, rr, crest), _at(res, ab, rr, crest), _at(res, ab, rr, crest + PLINTH_H), _at(res, aa, rr, crest + PLINTH_H), w,
					Vector2(ua, crest), Vector2(ub, crest), Vector2(ub, crest + PLINTH_H), Vector2(ua, crest + PLINTH_H), _k(K_TRIM), true)
			g.quad("dam", _at(res, aa, r_in, crest + PLINTH_H), _at(res, ab, r_in, crest + PLINTH_H), _at(res, ab, r_out, crest + PLINTH_H), _at(res, aa, r_out, crest + PLINTH_H), Vector3.UP,
				Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 1.0), Vector2(ua, 1.0), _k(K_TRIM))
			# The coping over the posts and panels.
			var yc := crest + PLINTH_H + RAIL_TOP
			for face in 2:
				var rr2 := (r_out + 0.06) if face == 0 else (r_in - 0.06)
				var w2 := out if face == 0 else -out
				if side == 1:
					w2 = -w2
				g.quad("dam", _at(res, aa, rr2, yc - 0.02), _at(res, ab, rr2, yc - 0.02), _at(res, ab, rr2, yc + COPING_H), _at(res, aa, rr2, yc + COPING_H), w2,
					Vector2(ua, yc), Vector2(ub, yc), Vector2(ub, yc + COPING_H), Vector2(ua, yc + COPING_H), _k(K_TRIM), true)
			g.quad("dam", _at(res, aa, r_in - 0.06, yc + COPING_H), _at(res, ab, r_in - 0.06, yc + COPING_H), _at(res, ab, r_out + 0.06, yc + COPING_H), _at(res, aa, r_out + 0.06, yc + COPING_H), Vector3.UP,
				Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 1.0), Vector2(ua, 1.0), _k(K_TRIM), true)
			g.quad("dam", _at(res, aa, r_in - 0.06, yc - 0.02), _at(res, ab, r_in - 0.06, yc - 0.02), _at(res, ab, r_out + 0.06, yc - 0.02), _at(res, aa, r_out + 0.06, yc - 0.02), Vector3.DOWN,
				Vector2(ua, 0.0), Vector2(ub, 0.0), Vector2(ub, 1.0), Vector2(ua, 1.0), _k(K_TRIM))
			# The post at this end, and the pierced panel to the next one.
			var post_hw := 0.225 / R
			var pc := _at(res, aa, r_mid, crest + PLINTH_H + RAIL_TOP * 0.5)
			var yaw := atan2(-out.x, -out.z)
			var is_lamp := s % (LAMP_EVERY * 2) == (0 if side == 0 else LAMP_EVERY) and s > 0
			if is_lamp:
				_lantern(ctx, _at(res, aa, r_mid, crest + PLINTH_H), yaw)
			else:
				g.box("dam", pc, Vector3(0.45, RAIL_TOP, 0.62), _k(K_TRIM), Basis(Vector3.UP, yaw), 0.0, true)
			var pa := aa + post_hw
			var pb := ab - post_hw
			g.quad("rail", _at(res, pa, r_mid, crest + PLINTH_H), _at(res, pb, r_mid, crest + PLINTH_H), _at(res, pb, r_mid, yc), _at(res, pa, r_mid, yc), out,
				Vector2(0.0, 0.0), Vector2(ctx.panel, 0.0), Vector2(ctx.panel, RAIL_TOP), Vector2(0.0, RAIL_TOP), Color(float(s % 7) * 0.13, 0.5, 0.0, 1.0))
		# The last post.
		var al := res.dam_a1
		var outl := _out(res, al)
		g.box("dam", _at(res, al, (r_in + r_out) * 0.5, crest + PLINTH_H + RAIL_TOP * 0.5), Vector3(0.6, RAIL_TOP + 0.3, 0.7), _k(K_TRIM), Basis(Vector3.UP, atan2(-outl.x, -outl.z)), 0.0, true)


## An old cast-iron lantern standard on a concrete pedestal, its foot at `base`.
static func _lantern(ctx: Dictionary, base: Vector3, yaw: float) -> void:
	var g: LandmarkGeo = ctx.geo
	var b := Basis(Vector3.UP, yaw)
	g.box("dam", base + Vector3(0.0, 0.55, 0.0), Vector3(0.62, 1.1, 0.72), _k(K_TRIM), b, 0.03, true)
	g.box("dam", base + Vector3(0.0, 1.16, 0.0), Vector3(0.74, 0.12, 0.84), _k(K_TRIM), b)
	var foot := base + Vector3(0.0, 1.22, 0.0)
	# Fluted base, column, collar.
	g.cylinder("dam", foot, 0.2, 0.55, 8, _k(K_METAL), 0.13)
	g.cylinder("dam", foot + Vector3(0.0, 0.55, 0.0), 0.1, 2.95, 8, _k(K_METAL), 0.075, true, false)
	g.cylinder("dam", foot + Vector3(0.0, 3.5, 0.0), 0.13, 0.12, 8, _k(K_METAL))
	# The lantern: a glass body between a base ring and a crown, a cap and a finial.
	var ly := LANTERN_Y - 1.22 - 0.35
	g.cylinder("dam", foot + Vector3(0.0, 3.62, 0.0), 0.16, ly - 3.62 + 0.0, 8, _k(K_METAL), 0.24, false, false)
	g.cylinder("dam", foot + Vector3(0.0, ly, 0.0), 0.24, 0.7, 8, _k(K_LAMP), 0.3, false, false)
	g.cylinder("dam", foot + Vector3(0.0, ly + 0.7, 0.0), 0.34, 0.06, 8, _k(K_METAL))
	g.cylinder("dam", foot + Vector3(0.0, ly + 0.76, 0.0), 0.3, 0.3, 8, _k(K_METAL), 0.05)
	g.cylinder("dam", foot + Vector3(0.0, ly + 1.06, 0.0), 0.04, 0.22, 6, _k(K_METAL), 0.01)
	(ctx.lamps as Array).append(foot + Vector3(0.0, ly + 0.35, 0.0))


# --- The towers -----------------------------------------------------------------------------------

## The intake tower: a round shaft standing in the lake off the upstream face, a gallery house with
## a ring of windows, a cornice and a ribbed copper dome with a finial. Its footbridge's deck and
## piers are part of the structure; the truss is trim.
static func _intake_tower(ctx: Dictionary, along: float = 0.62, off: float = 24.0, rs: float = 4.2, hh: float = 4.8) -> void:
	var res: Reservoir = ctx.res
	var g: LandmarkGeo = ctx.geo
	var R := Reservoir.DAM_RADIUS
	var a := lerpf(res.dam_a0, res.dam_a1, along)
	var r_t := R + off
	var c2 := res.arc_point(a, r_t)
	var c := Vector3(c2.x, 0.0, c2.y)
	var crest := res.crest
	var y_f := res.level - 40.0
	g.cylinder("dam", Vector3(c.x, y_f, c.z), rs, crest + 1.0 - y_f, 20, _k(K_FACE, 0.0), -1.0, true, false)
	# Base course, house, cornice, dome.
	var y0 := crest + 1.0
	g.cylinder("dam", Vector3(c.x, y0, c.z), rs + 0.35, 0.6, 20, _k(K_TRIM), -1.0, true)
	var hw := rs
	g.cylinder("dam", Vector3(c.x, y0 + 0.6, c.z), hw, hh, 20, _k(K_TRIM), -1.0, true, false)
	# Windows: tall, round-headed in effect (a dark pane with a glass light over it), every other
	# side of the house, standing a hair proud of the wall.
	var nwin := 10 if rs > 3.5 else 6
	for k in nwin:
		var t := TAU * (float(k) + 0.25) / float(nwin)
		var n := Vector3(cos(t), 0.0, sin(t))
		var side := Vector3(-n.z, 0.0, n.x)
		var wc := c + n * (hw + 0.02)
		var yb := y0 + 1.6
		var yt := y0 + 4.4
		g.quad("dam", wc - side * 0.55 + Vector3(0.0, yb, 0.0), wc + side * 0.55 + Vector3(0.0, yb, 0.0), wc + side * 0.55 + Vector3(0.0, yt, 0.0), wc - side * 0.55 + Vector3(0.0, yt, 0.0), n,
			Vector2(0.0, yb), Vector2(1.1, yb), Vector2(1.1, yt), Vector2(0.0, yt), _k(K_GLASS))
		g.box("dam", wc + n * 0.08 + Vector3(0.0, yb - 0.1, 0.0), Vector3(1.4, 0.18, 0.3), _k(K_TRIM), Basis(Vector3.UP, atan2(-n.x, -n.z)))
	g.cylinder("dam", Vector3(c.x, y0 + 0.6 + hh, c.z), rs + 0.55, 0.55, 20, _k(K_TRIM), rs + 0.7, true)
	var rise := rs * 0.72
	g.dome("dam", Vector2(c.x, c.z), Vector2(rs + 0.45, rs + 0.45), y0 + 0.6 + hh + 0.55, rise, 20, 5, _k(K_ROOF), true)
	g.cylinder("dam", Vector3(c.x, y0 + hh + 1.1 + rise, c.z), 0.45 * rs / 4.2, 0.8, 8, _k(K_ROOF), 0.3 * rs / 4.2)
	g.cylinder("dam", Vector3(c.x, y0 + hh + 1.9 + rise, c.z), 0.1, 1.1, 6, _k(K_BRASS), 0.02)
	# The footbridge from the crest to the house: deck and piers.
	var r_from := R - PARAPET_T
	var r_to := r_t - hw
	var hwb := 1.2 / R
	var yd := crest + PLINTH_H + RAIL_TOP + COPING_H
	(ctx.bridges as Array).append([a, r_from, r_to, yd])
	var ad := a - hwb
	var ae := a + hwb
	var out := _out(res, a)
	g.quad("dam", _at(res, ad, r_from, yd), _at(res, ae, r_from, yd), _at(res, ae, r_to + 0.3, yd), _at(res, ad, r_to + 0.3, yd), Vector3.UP,
		Vector2(0.0, 0.0), Vector2(2.4, 0.0), Vector2(2.4, r_to - r_from), Vector2(0.0, r_to - r_from), _k(K_TRIM), true)
	g.quad("dam", _at(res, ad, r_from, yd - 0.45), _at(res, ae, r_from, yd - 0.45), _at(res, ae, r_to, yd - 0.45), _at(res, ad, r_to, yd - 0.45), Vector3.DOWN,
		Vector2(0.0, 0.0), Vector2(2.4, 0.0), Vector2(2.4, 1.0), Vector2(0.0, 1.0), _k(K_TRIM))
	for side in [ad, ae]:
		var tang := (_at(res, side + 0.001, R, 0.0) - _at(res, side, R, 0.0)).normalized() * (1.0 if side == ae else -1.0)
		g.quad("dam", _at(res, side, r_from, yd - 0.45), _at(res, side, r_to, yd - 0.45), _at(res, side, r_to, yd), _at(res, side, r_from, yd), tang,
			Vector2(0.0, yd - 0.45), Vector2(r_to - r_from, yd - 0.45), Vector2(r_to - r_from, yd), Vector2(0.0, yd), _k(K_TRIM))
	var n_p := 2
	for k in n_p:
		var rp := lerpf(r_from, r_to, float(k + 1) / float(n_p + 1))
		var pp := res.arc_point(a, rp)
		g.cylinder("dam", Vector3(pp.x, res.level - 30.0, pp.y), 0.7, yd - 0.45 - (res.level - 30.0), 10, _k(K_FACE, 0.0), -1.0, true, false)


## The footbridge's railings: a light steel truss either side of the deck.
static func _footbridge_truss(ctx: Dictionary) -> void:
	for br: Array in ctx.bridges:
		_truss(ctx, br)


static func _truss(ctx: Dictionary, br: Array) -> void:
	var res: Reservoir = ctx.res
	var g: LandmarkGeo = ctx.geo
	var R := Reservoir.DAM_RADIUS
	var a: float = br[0]
	var r_from: float = br[1]
	var r_to: float = br[2]
	var yd: float = br[3]
	var out := _out(res, a).normalized()
	var yaw := atan2(-out.x, -out.z)
	var length := r_to - r_from
	for side in [-1.0, 1.0]:
		var lat: float = side * 1.15 / R
		var p0 := _at(res, a + lat, r_from, yd)
		var p1 := _at(res, a + lat, r_to, yd)
		var mid := (p0 + p1) * 0.5
		g.box("dam", mid + Vector3(0.0, 1.1, 0.0), Vector3(0.08, 0.08, length), _k(K_METAL), Basis(Vector3.UP, yaw), 0.0, true)
		g.box("dam", mid + Vector3(0.0, 0.55, 0.0), Vector3(0.05, 0.05, length), _k(K_METAL), Basis(Vector3.UP, yaw))
		var n := int(length / 1.8)
		for k in n + 1:
			var p := p0.lerp(p1, float(k) / float(n))
			g.box("dam", p + Vector3(0.0, 0.55, 0.0), Vector3(0.07, 1.1, 0.07), _k(K_METAL), Basis(Vector3.UP, yaw))


## Where the gauge tower stands: in 3-7 m of water off the trail on the lake's west side, as close
## to the trail as that allows. {"at": Vector2, "trail": Vector2} or empty.
static func _gauge_site(res: Reservoir) -> Dictionary:
	if res.trail.is_empty():
		return {}
	var target := res.lake_centre() + Vector2(-140.0, 10.0)
	var best_t := Vector2.INF
	for line in res.trail:
		for p in line:
			if p.distance_to(target) < best_t.distance_to(target):
				best_t = p
	var n := res.grid_size()
	var best := Vector2.INF
	for j in n.y:
		for i in n.x:
			var d := res.depth_at_node(i, j)
			if d < 3.0 or d > 7.0 or res.wet_grid[j * n.x + i] == 0:
				continue
			var p := res.grid_point(i, j)
			var dd := p.distance_to(best_t)
			if dd > 8.0 and dd < best.distance_to(best_t):
				best = p
	if best == Vector2.INF or best.distance_to(best_t) > 40.0:
		return {}
	return {"at": best, "trail": best_t}


## The gauge tower: a square concrete pier with a staff gauge down its face, a small hipped hut on
## top, and a footbridge to the trail.
static func _gauge_tower(ctx: Dictionary, site: Dictionary) -> void:
	var res: Reservoir = ctx.res
	var g: LandmarkGeo = ctx.geo
	var at: Vector2 = site.at
	var tp: Vector2 = site.trail
	var to := (tp - at).normalized()
	var yaw := atan2(-to.x, -to.y)
	var b := Basis(Vector3.UP, yaw)
	var top := res.level + Reservoir.TRAIL_RISE
	var bed := res.level - 9.0
	g.box("dam", Vector3(at.x, (bed + top) * 0.5, at.y), Vector3(2.6, top - bed, 2.6), _k(K_FACE, 0.0), b, 0.0, true)
	# The hut.
	g.box("dam", Vector3(at.x, top + 1.3, at.y), Vector3(3.0, 2.6, 3.0), _k(K_TRIM), b, 0.02, true)
	g.box("dam", Vector3(at.x, top + 2.75, at.y), Vector3(3.6, 0.3, 3.6), _k(K_TRIM), b)
	var roof := PackedVector2Array()
	for k in 4:
		var t := yaw + PI * 0.25 + PI * 0.5 * float(k)
		roof.append(at + Vector2(cos(t), sin(t)) * 2.6)
	var apex := Vector3(at.x, top + 4.1, at.y)
	for k in 4:
		var p0 := roof[k]
		var p1 := roof[(k + 1) % 4]
		var mid := (p0 + p1) * 0.5 - at
		g.tri("dam", Vector3(p0.x, top + 2.9, p0.y), Vector3(p1.x, top + 2.9, p1.y), apex, Vector3(mid.x, 1.2, mid.y), Vector2(0.0, 0.0), Vector2(3.6, 0.0), Vector2(1.8, 2.0), _k(K_ROOF), true)
	# A window and a door on the hut, the gauge on the lake side of the pier.
	var side := Vector2(-to.y, to.x)
	var face := at - to * 1.32
	var gw := Vector3(side.x, 0.0, side.y) * 0.16
	var fc := Vector3(face.x, 0.0, face.y)
	g.quad("dam", fc - gw + Vector3(0.0, res.level - 3.0, 0.0), fc + gw + Vector3(0.0, res.level - 3.0, 0.0), fc + gw + Vector3(0.0, top - 0.3, 0.0), fc - gw + Vector3(0.0, top - 0.3, 0.0), Vector3(-to.x, 0.0, -to.y),
		Vector2(0.0, res.level - 3.0), Vector2(0.32, res.level - 3.0), Vector2(0.32, top - 0.3), Vector2(0.0, top - 0.3), _k(K_GAUGE))
	for k in 2:
		var wn := (to if k == 0 else side)
		var wc := at + wn * 1.52
		var sw := Vector2(-wn.y, wn.x) * 0.45
		var y0 := top + (0.05 if k == 0 else 1.0)
		var y1 := top + 2.1
		g.quad("dam", Vector3(wc.x - sw.x, y0, wc.y - sw.y), Vector3(wc.x + sw.x, y0, wc.y + sw.y), Vector3(wc.x + sw.x, y1, wc.y + sw.y), Vector3(wc.x - sw.x, y1, wc.y - sw.y), Vector3(wn.x, 0.0, wn.y),
			Vector2(0.0, y0), Vector2(0.9, y0), Vector2(0.9, y1), Vector2(0.0, y1), _k(K_DARK if k == 0 else K_GLASS))
	# The footbridge to the trail: a slab on the pier's shoulder and the trail's edge, pipe rails.
	var p0 := at + to * 1.3
	var p1 := tp - to * 1.0
	var length := p0.distance_to(p1)
	var mid2 := (p0 + p1) * 0.5
	g.box("dam", Vector3(mid2.x, top - 0.15, mid2.y), Vector3(1.6, 0.3, length), _k(K_TRIM), b, 0.0, true)
	for s2 in [-1.0, 1.0]:
		var o: Vector2 = side * 0.75 * s2
		g.box("dam", Vector3(mid2.x + o.x, top + 1.0, mid2.y + o.y), Vector3(0.06, 0.06, length), _k(K_METAL), b)
		var n := int(length / 2.0)
		for k in n + 1:
			var p := p0.lerp(p1, float(k) / float(maxi(n, 1))) + o
			g.box("dam", Vector3(p.x, top + 0.5, p.y), Vector3(0.06, 1.0, 0.06), _k(K_METAL), b)


# --- The spillway and the apron -----------------------------------------------------------------

## The spillway: training walls from the lake to the weir, the weir (an ogee crest between two
## piers, a service bridge over it), then the channel round the dam's end and the stepped chute
## down to the gorge, walled both sides.
static func _spillway(ctx: Dictionary) -> void:
	var res: Reservoir = ctx.res
	var g: LandmarkGeo = ctx.geo
	var pts := res.spill
	var fl := res.spill_floor
	if pts.size() < 3:
		return
	var hw := Reservoir.SPILL_HALF
	var u := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x)
		var length := a.distance_to(b)
		var drop := fl[k] - fl[k + 1]
		# Steps where it is steep: a tread and a riser every ~1.2 m of drop.
		var steps := maxi(1, int(ceil(drop / 1.2))) if drop > length * 0.12 else maxi(1, int(length / 6.0))
		var stepped := drop > length * 0.12
		for s in steps:
			var t0 := float(s) / steps
			var t1 := float(s + 1) / steps
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			var y0 := lerpf(fl[k], fl[k + 1], t0)
			var y1 := lerpf(fl[k], fl[k + 1], t1)
			var yt := y0 if stepped else y0
			var yt1 := y0 if stepped else y1
			var l0 := p0 + nrm * hw
			var r0 := p0 - nrm * hw
			var l1 := p1 + nrm * hw
			var r1 := p1 - nrm * hw
			var seg := p0.distance_to(p1)
			g.quad("dam", Vector3(l0.x, yt, l0.y), Vector3(r0.x, yt, r0.y), Vector3(r1.x, yt1, r1.y), Vector3(l1.x, yt1, l1.y), Vector3.UP,
				Vector2(u, 0.0), Vector2(u, hw * 2.0), Vector2(u + seg, hw * 2.0), Vector2(u + seg, 0.0), _k(K_CHUTE), true)
			if stepped:
				g.quad("dam", Vector3(l1.x, y0, l1.y), Vector3(r1.x, y0, r1.y), Vector3(r1.x, y1, r1.y), Vector3(l1.x, y1, l1.y), Vector3(d.x, 0.0, d.y),
					Vector2(0.0, y0), Vector2(hw * 2.0, y0), Vector2(hw * 2.0, y1), Vector2(0.0, y1), _k(K_CHUTE), true)
			# The walls, 3 m over the floor (higher at the weir), 0.6 thick, both faces and a top.
			var wh0 := y0 + (5.0 if k == 0 else 3.0)
			var wh1 := (y0 if stepped else y1) + (5.0 if k == 0 else 3.0)
			for sd in [1.0, -1.0]:
				var inn0: Vector2 = p0 + nrm * hw * sd
				var inn1: Vector2 = p1 + nrm * hw * sd
				var out0: Vector2 = p0 + nrm * (hw + 0.6) * sd
				var out1: Vector2 = p1 + nrm * (hw + 0.6) * sd
				var w_in: Vector3 = Vector3(-nrm.x, 0.0, -nrm.y) * sd
				var yb := minf(y0, y1) - 2.0
				g.quad("dam", Vector3(inn0.x, yb, inn0.y), Vector3(inn1.x, yb, inn1.y), Vector3(inn1.x, wh1, inn1.y), Vector3(inn0.x, wh0, inn0.y), w_in,
					Vector2(u, yb), Vector2(u + seg, yb), Vector2(u + seg, wh1), Vector2(u, wh0), _k(K_FACE), true)
				g.quad("dam", Vector3(out0.x, yb - 3.0, out0.y), Vector3(out1.x, yb - 3.0, out1.y), Vector3(out1.x, wh1, out1.y), Vector3(out0.x, wh0, out0.y), -w_in,
					Vector2(u, yb), Vector2(u + seg, yb), Vector2(u + seg, wh1), Vector2(u, wh0), _k(K_FACE), true)
				g.quad("dam", Vector3(inn0.x, wh0, inn0.y), Vector3(inn1.x, wh1, inn1.y), Vector3(out1.x, wh1, out1.y), Vector3(out0.x, wh0, out0.y), Vector3.UP,
					Vector2(u, 0.0), Vector2(u + seg, 0.0), Vector2(u + seg, 0.6), Vector2(u, 0.6), _k(K_TRIM), true)
			u += seg
	# The weir at pts[1]: an ogee crest across the channel, two piers, the service bridge.
	var w := pts[1]
	var dw := (pts[2] - pts[0]).normalized()
	var nw := Vector2(-dw.y, dw.x)
	var yaw := atan2(-dw.x, -dw.y)
	var bw := Basis(Vector3.UP, yaw)
	var crest_w := res.level + 0.6
	g.box("dam", Vector3(w.x, crest_w - 2.5, w.y), Vector3(hw * 2.0, 5.0, 2.4), _k(K_TRIM), bw, 0.2, true)
	for s in [-1.0 / 3.0, 1.0 / 3.0]:
		var pp: Vector2 = w + nw * hw * 2.0 * s
		g.box("dam", Vector3(pp.x, crest_w + 1.6, pp.y), Vector3(0.9, 4.4, 3.0), _k(K_TRIM), bw, 0.05, true)
	g.box("dam", Vector3(w.x, crest_w + 3.95, w.y), Vector3(hw * 2.0 + 1.2, 0.4, 2.6), _k(K_TRIM), bw, 0.0, true)
	for s in [-1.0, 1.0]:
		var o: Vector2 = dw * 1.2 * s
		g.box("dam", Vector3(w.x + o.x, crest_w + 4.65, w.y + o.y), Vector3(hw * 2.0 + 1.2, 0.08, 0.08), _k(K_METAL), bw)


## The apron at the dam's toe: a concrete slab across the gorge with a low end sill, the stilling
## basin the face's drains and the outlet works empty into.
static func _apron(ctx: Dictionary) -> void:
	var res: Reservoir = ctx.res
	var g: LandmarkGeo = ctx.geo
	var R := Reservoir.DAM_RADIUS
	var r0 := R - res.dam_base - 1.0
	var r1 := r0 - 16.0
	var y := res.toe - 0.9
	var a0 := res.dam_a0 + 0.12
	var a1 := res.dam_a1 - 0.12
	if a1 <= a0:
		return
	var n := maxi(2, int((a1 - a0) * R / 8.0))
	for s in n:
		var aa := lerpf(a0, a1, float(s) / n)
		var ab := lerpf(a0, a1, float(s + 1) / n)
		var out := _out(res, (aa + ab) * 0.5)
		g.quad("dam", _at(res, aa, r0, y), _at(res, ab, r0, y), _at(res, ab, r1, y), _at(res, aa, r1, y), Vector3.UP,
			Vector2(aa * R, r0), Vector2(ab * R, r0), Vector2(ab * R, r1), Vector2(aa * R, r1), _k(K_CHUTE), true)
		g.quad("dam", _at(res, aa, r1, y + 0.8), _at(res, ab, r1, y + 0.8), _at(res, ab, r1, y - 7.0), _at(res, aa, r1, y - 7.0), -out,
			Vector2(aa * R, y + 0.8), Vector2(ab * R, y + 0.8), Vector2(ab * R, y - 7.0), Vector2(aa * R, y - 7.0), _k(K_FACE, 1.0), true)
		g.quad("dam", _at(res, aa, r1 + 0.7, y + 0.8), _at(res, ab, r1 + 0.7, y + 0.8), _at(res, ab, r1, y + 0.8), _at(res, aa, r1, y + 0.8), Vector3.UP,
			Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0), _k(K_TRIM), true)
		g.quad("dam", _at(res, aa, r1 + 0.7, y), _at(res, ab, r1 + 0.7, y), _at(res, ab, r1 + 0.7, y + 0.8), _at(res, aa, r1 + 0.7, y + 0.8), out,
			Vector2(0.0, y), Vector2(1.0, y), Vector2(1.0, y + 0.8), Vector2(0.0, y + 0.8), _k(K_TRIM))


# --- The trail, its fence and the pines ---------------------------------------------------------

## The trail: a 3 m ribbon of decomposed granite on its bench, round the lake.
static func _trail(ctx: Dictionary) -> void:
	var res: Reservoir = ctx.res
	var g: LandmarkGeo = ctx.geo
	var y := res.level + Reservoir.TRAIL_RISE + 0.07
	for line in res.trail:
		var u := 0.0
		for k in line.size() - 1:
			var a := line[k]
			var b := line[k + 1]
			var da := _dir(line, k)
			var db := _dir(line, k + 1)
			var na := Vector2(-da.y, da.x) * 1.5
			var nb := Vector2(-db.y, db.x) * 1.5
			var seg := a.distance_to(b)
			g.quad("dam", Vector3(a.x + na.x, y, a.y + na.y), Vector3(a.x - na.x, y, a.y - na.y), Vector3(b.x - nb.x, y, b.y - nb.y), Vector3(b.x + nb.x, y, b.y + nb.y), Vector3.UP,
				Vector2(u, 0.0), Vector2(u, 3.0), Vector2(u + seg, 3.0), Vector2(u + seg, 0.0), _k(K_TRAIL), true)
			u += seg


static func _dir(line: PackedVector2Array, k: int) -> Vector2:
	var a := line[maxi(k - 1, 0)]
	var b := line[mini(k + 1, line.size() - 1)]
	return (b - a).normalized()


## Which side of the trail at point k the lake is on: +1 left (the ribbon's +normal), -1 right.
static func _lake_side(res: Reservoir, line: PackedVector2Array, k: int) -> float:
	var d := _dir(line, k)
	var n := Vector2(-d.y, d.x)
	var p := line[k]
	var hl := res.macro.height_at(p + n * 6.0)
	var hr := res.macro.height_at(p - n * 6.0)
	return 1.0 if hl < hr else -1.0


## Chain-link along the lake side of the trail (LotFill's panel and posts).
static func _fence(res: Reservoir, batch: MultiMeshBatch) -> void:
	var y := res.level + Reservoir.TRAIL_RISE + 0.05
	var post := PropFactory.cylinder("fence_post", 0.03, 1.0, Color(0.55, 0.56, 0.57), 0.03, 8)
	var fh := LotFill.FENCE_HEIGHT
	for line in res.trail:
		var side := 0.0
		for k in line.size() - 1:
			if k % 8 == 0:
				side = _lake_side(res, line, k)
			var d := _dir(line, k)
			var n := Vector2(-d.y, d.x) * side * 1.75
			var a := line[k] + n
			var b := line[k + 1] + n
			var mid := (a + b) * 0.5
			var length := a.distance_to(b)
			var yaw := atan2(-(b - a).y, (b - a).x)
			batch.add("res_fence_post", post, Transform3D(Basis().scaled(Vector3(1.0, fh, 1.0)), Vector3(a.x, y + fh * 0.5, a.y)))
			batch.add("res_fence_mesh", LotFill.chain_link_panel(), Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(length, 1.0, 1.0)), Vector3(mid.x, y, mid.y)))
			batch.add("res_fence_post", post, Transform3D((Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI * 0.5)).scaled_local(Vector3(1.0, length, 1.0)), Vector3(mid.x, y + fh, mid.y)))


## Pines along the trail's uphill side and now and then down by the water, hashed per trail point.
static func _pines(res: Reservoir, macro: MacroMap, batch: MultiMeshBatch) -> void:
	var mesh := PropFactory.model_hill_tree(1)
	if mesh == null:
		return
	for li in res.trail.size():
		var line: PackedVector2Array = res.trail[li]
		for k in range(0, line.size(), 2):
			var hs := hash([macro.seed, "res_pine", li, k])
			var roll := float(absi(hs) % 1000) / 1000.0
			var side := -_lake_side(res, line, k)
			var down := roll < 0.035
			if roll > 0.2 and not down:
				continue
			var d := _dir(line, k)
			var n := Vector2(-d.y, d.x)
			var off := (5.0 + float(absi(hs / 1000) % 80) / 10.0) * side
			if down:
				off = -side * 6.5
			var p := line[k] + n * off
			var h := macro.height_at(p)
			if down and h < res.level + 1.2:
				continue
			if res.keep_clear(p, h, 0.0):
				continue
			var s := 0.75 + float(absi(hs / 7) % 100) / 180.0
			var yaw := float(absi(hs / 13) % 628) * 0.01
			batch.add("res_pine", mesh, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(p.x, h - 0.15, p.y)), Color(1.25, 1.3, 1.05))
