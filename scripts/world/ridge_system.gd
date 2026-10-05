class_name RidgeSystem
extends Node3D
## The ridges' far tier and everything that is never a chunk's (Ridges, RidgeKit, RidgeBuild): a
## node in city.tscn, so origin shifts carry it; its meshes are in true world space.
##   Wires: ONE mesh on shaders/power_wire.gdshader - every conductor (twin bundles, spacers,
##     jumpers), earth wire and guy of the whole basin, and every tower's, mast's and gantry's
##     lattice again as fine lines (RidgeKit's member lists with `far` true). Fine lines with a
##     pixel's coverage are what a lattice tower and a span ARE from a kilometre, and they never
##     shimmer the way thin geometry does.
##   Solids: ONE mesh on shaders/ridge_far_solid.gdshader - the tanks, domes, huts, the lookout's
##     cab and the substation's transformers and control house as low boxes and cylinders.
##   Lights: ONE billboard mesh on aircraft_lights.gdshader - the masts' red obstruction lights
##     (a slow beacon on top, steady reds down the height), visible across the basin at night.
## A FULL chunk that builds a piece in detail (RidgeCover) sets its id in `covered`; the far
## versions of those collapse in the vertex shaders (a texel each in `_cover_tex`), nothing else
## is rebuilt. `RIDGES=0` leaves the whole node empty.

static var covered: Dictionary = {}
static var dirty := true

var ridges: Ridges
var plan: CityPlan
var wires: MeshInstance3D
var solids: MeshInstance3D
var lights: MeshInstance3D
var _cover_img: Image
var _cover_tex: ImageTexture
var _cover_w := 1
var _id_count := 1
var _ready_done := false
var _wire_mat: ShaderMaterial
var _solid_mat: ShaderMaterial
var _vp := Vector2.ZERO

const CONDUCTOR := Color(0.36, 0.37, 0.37)
const EARTH := Color(0.30, 0.31, 0.31)
const CONDUCTOR_R := 0.0145
const SURFACE_VERTS := 60000
const EARTH_R := 0.0085
const GUY_R := 0.012


func _ready() -> void:
	name = "Ridges"


func _process(_delta: float) -> void:
	if not _ready_done:
		if not _setup():
			return
		_ready_done = true
	if dirty:
		dirty = false
		_apply_cover()
	if _wire_mat:
		var vp := get_viewport()
		var size := vp.get_visible_rect().size if vp else Vector2(1920.0, 1080.0)
		# The 3D resolution when Quality scales it (FSR / render scale).
		if vp and vp.scaling_3d_scale > 0.0:
			size *= vp.scaling_3d_scale
		if size.distance_to(_vp) > 0.5:
			_vp = size
			_wire_mat.set_shader_parameter("viewport_px", size)


func _setup() -> bool:
	var city := get_parent()
	if city == null or not ("plan" in city):
		return false
	plan = city.get("plan") as CityPlan
	if plan == null:
		return false
	ridges = Ridges.of(plan)
	if ridges == null:
		set_process(false)
		return false
	position = -WorldState.world_offset
	_id_count = ridges.towers.size() + ridges.masts.size() + ridges.sites.size() + 2
	_cover_w = mini(_id_count, 1024)
	_cover_img = Image.create(_cover_w, maxi(1, ceili(float(_id_count) / _cover_w)), false, Image.FORMAT_R8)
	_cover_tex = ImageTexture.create_from_image(_cover_img)
	_build_wires()
	_build_solids()
	_build_lights()
	# The tower bodies the FULL chunks will want, built now (on the loading screen).
	for t: Dictionary in ridges.towers:
		RidgeKit.tower_body(float(t.h), int(t.kind))
	dirty = true
	return true


func _apply_cover() -> void:
	if _cover_img == null:
		return
	_cover_img.fill(Color(0, 0, 0))
	for id: int in covered:
		if id >= 0 and id < _id_count:
			_cover_img.set_pixel(id % _cover_w, id / _cover_w, Color(1, 0, 0))
	_cover_tex.update(_cover_img)


# --- Wires -----------------------------------------------------------------------------------

class Wires:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)

	## A ribbon along the polyline `pts`.
	func line(pts: PackedVector3Array, r: float, kind: float, col: Color, id: int) -> void:
		var m := pts.size()
		if m < 2:
			return
		var base := v.size()
		for i in m:
			var t := (pts[mini(i + 1, m - 1)] - pts[maxi(i - 1, 0)]).normalized()
			for side: float in [-1.0, 1.0]:
				v.append(pts[i])
				n.append(t)
				c.append(col)
				uv.append(Vector2(side, kind))
				uv2.append(Vector2(r, float(id)))
			lo = lo.min(pts[i])
			hi = hi.max(pts[i])
		for i in m - 1:
			var a := base + i * 2
			idx.append_array(PackedInt32Array([a, a + 1, a + 3, a, a + 3, a + 2]))

	func seg(a: Vector3, b: Vector3, r: float, kind: float, col: Color, id: int) -> void:
		line(PackedVector3Array([a, b]), r, kind, col, id)

	## The mesh, cut into surfaces of under 65,536 vertices each (a wire never spans two): one
	## mesh past that drew nothing at all on the Compatibility renderer.
	func mesh(mat: Material) -> ArrayMesh:
		var out := ArrayMesh.new()
		var start_v := 0
		var start_i := 0
		while start_i < idx.size():
			# Take whole quads (6 indices) until the vertex range would pass the limit.
			var end_i := start_i
			var max_v := start_v
			while end_i < idx.size():
				var q_max := maxi(maxi(idx[end_i], idx[end_i + 1]), maxi(idx[end_i + 4], idx[end_i + 5]))
				if q_max - start_v >= RidgeSystem.SURFACE_VERTS:
					break
				max_v = maxi(max_v, q_max)
				end_i += 6
			var vs := v.slice(start_v, max_v + 1)
			var local := idx.slice(start_i, end_i)
			for k in local.size():
				local[k] -= start_v
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vs
			arrays[Mesh.ARRAY_NORMAL] = n.slice(start_v, max_v + 1)
			arrays[Mesh.ARRAY_COLOR] = c.slice(start_v, max_v + 1)
			arrays[Mesh.ARRAY_TEX_UV] = uv.slice(start_v, max_v + 1)
			arrays[Mesh.ARRAY_TEX_UV2] = uv2.slice(start_v, max_v + 1)
			arrays[Mesh.ARRAY_INDEX] = local
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(out.get_surface_count() - 1, mat)
			start_i = end_i
			if end_i < idx.size():
				# The next quad's lowest vertex starts the next surface.
				start_v = mini(mini(idx[end_i], idx[end_i + 1]), mini(idx[end_i + 2], idx[end_i + 5]))
		return out


func _build_wires() -> void:
	var w := Wires.new()
	var r := ridges
	# Conductors, earth wires, spacers and jumpers.
	for line: Dictionary in r.lines:
		var ids: Array = line.towers
		for k in ids.size():
			var ends: Array = r.span_ends(line, k)
			var a: Array = ends[0]
			var b: Array = ends[1]
			var span := Vector2(b[0].x - a[0].x, b[0].z - a[0].z)
			var across := Vector3(-span.y, 0.0, span.x).normalized() * Ridges.BUNDLE * 0.5
			var pieces := clampi(int(span.length() / 12.0), 8, 44)
			for ph in 6:
				for sg: float in [-1.0, 1.0]:
					w.line(Ridges.wire(a[ph] + across * sg, b[ph] + across * sg, pieces), CONDUCTOR_R, 1.0, CONDUCTOR, 0)
				# Spacers every ~60 m along the bundle.
				var ns := int(span.length() / 60.0)
				for j in ns:
					var t := float(j + 1) / float(ns + 1)
					var p: Vector3 = (a[ph] as Vector3).lerp(b[ph], t) - Vector3(0.0, 4.0 * Ridges.sag(span.length()) * t * (1.0 - t), 0.0)
					w.seg(p - across, p + across, 0.02, 0.0, RidgeKit.STEEL_DARK, 0)
			for ew in [6, 7]:
				w.line(Ridges.wire(a[ew], b[ew], pieces), EARTH_R, 1.0, EARTH, 0)
		# Jumpers round each angle tower's tension strings, under the arm.
		for k in ids.size():
			var t: Dictionary = r.towers[int(ids[k])]
			if int(t.kind) != Ridges.Kind.ANGLE or k + 1 >= ids.size():
				continue
			var prev: Vector2 = (r.towers[int(ids[k - 1])].pos if k > 0 else r.substation.gantries[int(line.gantry)].pos)
			var nxt: Vector2 = r.towers[int(ids[k + 1])].pos
			var pa := Ridges.attach(t, prev)
			var pb := Ridges.attach(t, nxt)
			for ph in 6:
				w.line(Ridges.wire(pa[ph], pb[ph], 8, 1.6), CONDUCTOR_R * 1.2, 1.0, CONDUCTOR, 0)
	# The towers' lattice as fine lines.
	for t: Dictionary in r.towers:
		var xf := Ridges.tower_xform(t)
		var id := r.far_id("tower", int(t.id)) + 1
		for m: Array in RidgeKit.tower_members(float(t.h), RidgeKit._local_feet(t), true):
			w.seg(xf * (m[0] as Vector3), xf * (m[1] as Vector3), float(m[2]) * 0.5, 0.0, RidgeKit.STEEL, id)
		# The insulator strings, as a line each.
		var sp := Ridges.spec(float(t.h))
		for side: float in [-1.0, 1.0]:
			for k in 3:
				var tip := Vector3(side * float(sp.arm_tip[k]), float(sp.arm_y[k]), 0.0)
				if int(t.kind) == Ridges.Kind.SUSPENSION:
					w.seg(xf * tip, xf * (tip - Vector3(0.0, Ridges.STRING, 0.0)), 0.12, 2.0, RidgeKit.PORCELAIN, id)
	# The masts, their guys.
	for i in r.masts.size():
		var m: Dictionary = r.masts[i]
		var p: Vector2 = m.pos
		var o := Vector3(p.x, float(m.base), p.y)
		var id := r.far_id("mast", i) + 1
		for mm: Array in RidgeKit.mast_members(m, true):
			w.seg(o + (mm[0] as Vector3), o + (mm[1] as Vector3), float(mm[2]) * 0.5, 2.0 if int(m.kind) == Ridges.Mast.GUYED else 0.0, mm[5], id)
		for g: Vector2 in m.guys:
			var anchor := Vector3(g.x, plan.height_at(g) + 0.6, g.y)
			for lvl: float in m.levels:
				var top := o + Vector3(0.0, lvl, 0.0) + (anchor - o).normalized() * Vector3(1.0, 0.0, 1.0) * 0.9
				w.line(Ridges.wire(top, anchor, 16, 0.4), GUY_R, 0.0, RidgeKit.STEEL, 0)
	# The substation's gantries, and the lookout's legs.
	if not r.substation.is_empty():
		var id := r.far_id("site", r.sites.size()) + 1
		for g: Dictionary in r.substation.gantries:
			var gp: Vector2 = g.pos
			var xf := Transform3D(Basis(Vector3.UP, float(g.yaw)), Vector3(gp.x, float(g.base), gp.y))
			for m: Array in RidgeKit.gantry_members(true):
				w.seg(xf * (m[0] as Vector3), xf * (m[1] as Vector3), float(m[2]) * 0.5, 0.0, RidgeKit.STEEL, id)
	for i in r.sites.size():
		var s: Dictionary = r.sites[i]
		if int(s.kind) != Ridges.Site.LOOKOUT:
			continue
		var xf := Transform3D(Basis(Vector3.UP, float(s.yaw)), Vector3((s.pos as Vector2).x, float(s.base), (s.pos as Vector2).y))
		for c in 4:
			var sg: Vector2 = RidgeKit.CORNER_SIGNS[c]
			w.seg(xf * Vector3(sg.x * 3.0, 0.0, sg.y * 3.0), xf * Vector3(sg.x * 2.0, 12.0, sg.y * 2.0), 0.08, 0.0, RidgeKit.STEEL, r.far_id("site", i) + 1)
	_wire_mat = ShaderMaterial.new()
	_wire_mat.shader = load("res://shaders/power_wire.gdshader")
	_wire_mat.set_shader_parameter("covered", _cover_tex)
	_wire_mat.set_shader_parameter("covered_width", _cover_w)
	wires = MeshInstance3D.new()
	wires.name = "Wires"
	wires.mesh = w.mesh(_wire_mat)
	wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wires.custom_aabb = AABB(w.lo - Vector3.ONE * 10.0, (w.hi - w.lo) + Vector3.ONE * 20.0)
	wires.extra_cull_margin = 50.0
	add_child(wires)


# --- Far solids and lights -------------------------------------------------------------------

func _build_solids() -> void:
	var acc := RidgeKit.Acc.new()
	var r := ridges
	var ids := PackedFloat32Array()
	for i in r.sites.size():
		var s: Dictionary = r.sites[i]
		var p: Vector2 = s.pos
		var o := Vector3(p.x, float(s.base), p.y)
		var before := acc.tris()
		match int(s.kind):
			Ridges.Site.TANK:
				acc.cyl("solid", o, o + Vector3(0.0, float(s.h) + 0.25, 0.0), float(s.r), float(s.r), 14, RidgeKit.TANK_GREEN)
				acc.cyl("solid", o + Vector3(0.0, float(s.h) + 0.25, 0.0), o + Vector3(0.0, float(s.h) + 0.25 + float(s.r) * 0.18, 0.0), float(s.r) + 0.1, 0.0, 14, RidgeKit.TANK_GREEN)
			Ridges.Site.DOME:
				acc.cyl("solid", o, o + Vector3(0.0, float(s.h), 0.0), float(s.r) * 0.62, float(s.r) * 0.62, 10, Color(0.72, 0.71, 0.68))
				var c := o + Vector3(0.0, float(s.h) + float(s.r) * 0.62, 0.0)
				for tr: Array in RidgeKit._icosphere(1):
					acc.tri("solid", c + (tr[0] as Vector3) * float(s.r), c + (tr[1] as Vector3) * float(s.r), c + (tr[2] as Vector3) * float(s.r),
						(tr[0] as Vector3) + (tr[1] as Vector3) + (tr[2] as Vector3), Color(0.92, 0.92, 0.9))
			Ridges.Site.HUT:
				acc.box("solid", Transform3D(Basis(Vector3.UP, float(s.yaw)).scaled(Vector3(float(s.r) * 2.0, float(s.h), float(s.r) * 1.3)), o + Vector3(0.0, float(s.h) * 0.5 + 0.15, 0.0)), RidgeKit.HUT)
			Ridges.Site.LOOKOUT:
				acc.box("solid", Transform3D(Basis(Vector3.UP, float(s.yaw)).scaled(Vector3(5.2, 2.0, 5.2)), o + Vector3(0.0, 14.1, 0.0)), Color(0.5, 0.46, 0.4))
				acc.box("solid", Transform3D(Basis(Vector3.UP, float(s.yaw)).scaled(Vector3(6.2, 1.2, 6.2)), o + Vector3(0.0, 15.6, 0.0)), Color(0.36, 0.3, 0.26))
		for k in (acc.tris() - before) * 3:
			ids.append(float(r.far_id("site", i) + 1))
	if not r.substation.is_empty():
		var sub: Dictionary = r.substation
		var sr: Rect2 = sub.rect
		var y: float = sub.base
		var c := Vector3(sr.get_center().x, y, sr.get_center().y)
		var long_x := sr.size.x >= sr.size.y
		var ax := Vector3(1, 0, 0) if long_x else Vector3(0, 0, 1)
		var bx := Vector3(0, 0, 1) if long_x else Vector3(1, 0, 0)
		var la := maxf(sr.size.x, sr.size.y)
		var lb := minf(sr.size.x, sr.size.y)
		var before := acc.tris()
		var nt := 3 if la > 150.0 else 2
		for i in nt:
			var along := lerpf(-la * 0.22, la * 0.22, float(i) / maxf(nt - 1, 1))
			acc.box("solid", Transform3D(Basis(ax * 7.0, Vector3(0, 4.6, 0), bx * 5.6), c + ax * along + Vector3(0, 2.6, 0)), Color(0.52, 0.55, 0.52))
		var house := c + ax * (la * 0.5 - 12.0) + bx * (lb * 0.5 - 9.0)
		acc.box("solid", Transform3D(Basis(ax * 18.0, Vector3(0, 4.8, 0), bx * 10.0), house + Vector3(0, 2.4, 0)), Color(0.78, 0.74, 0.66))
		for k in (acc.tris() - before) * 3:
			ids.append(float(r.far_id("site", r.sites.size()) + 1))
	if acc.parts.is_empty():
		return
	_solid_mat = ShaderMaterial.new()
	_solid_mat.shader = load("res://shaders/ridge_far_solid.gdshader")
	_solid_mat.set_shader_parameter("covered", _cover_tex)
	_solid_mat.set_shader_parameter("covered_width", _cover_w)
	var mesh := acc.commit({"solid": _solid_mat})
	# The far id of every vertex, in UV2.y (the shader collapses a covered one).
	var arrays := mesh.surface_get_arrays(0).duplicate()
	var uv2 := PackedVector2Array()
	for k in ids.size():
		uv2.append(Vector2(0.0, ids[k]))
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, _solid_mat)
	solids = MeshInstance3D.new()
	solids.name = "FarSolids"
	solids.mesh = out
	solids.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(solids)


func _build_lights() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	var n := 0
	var red := Color(1.0, 0.05, 0.02, 1.0)
	for i in ridges.masts.size():
		var m: Dictionary = ridges.masts[i]
		var o := Vector3((m.pos as Vector2).x, float(m.base), (m.pos as Vector2).y)
		for spec: Array in RidgeKit.mast_lights(m):
			var kind := int(spec[1])
			var size := 2.4 if kind == 2 else 1.6
			var code := float(kind) * 10.0 + fposmod(float(n) * 0.37, 1.0) * 9.0
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(red)
				st.set_uv(corners[k])
				st.set_uv2(Vector2(size, code))
				st.set_normal(Vector3.UP)
				st.add_vertex(o + (spec[0] as Vector3))
			n += 1
	if n == 0:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/aircraft_lights.gdshader")
	mat.set_shader_parameter("day_level", 0.12)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	lights = MeshInstance3D.new()
	lights.name = "ObstructionLights"
	lights.mesh = mesh
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lights.extra_cull_margin = 16000.0
	add_child(lights)
