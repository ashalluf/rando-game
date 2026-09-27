class_name ArenaGrounds
extends RefCounted
## The ground between the arena district's buildings (owner, 2026-09-25: the civic blocks grew at
## 1:1 and were "mostly bare paved plazas"). The real district is not a paved field: it is a
## multi-storey car park on the west of the arena block, a star plaza of bronze figures on plinths
## under palms at the arena's corner, raised planting beds and tree groves (bosques) between the
## venues, palm rows down Figueroa and the side streets. These are the pieces; the builders in
## LandmarkArenaDistrict lay them out in each block's own frame.
##
## Everything goes into the builder's own LandmarkGeo (one surface per material) and
## MultiMeshBatch, so a block stays a handful of draw calls. Rolls come from a private rng seeded
## per piece, never the chunk rng. Nothing here is named after a real business.

## Height of one car-park storey, floor to floor (metres), and the spandrel on each deck edge.
const GARAGE_STOREY := 3.2
const SPANDREL := 1.1
## Bay spacing of the car park's perimeter columns, and a stall's width and depth.
const GARAGE_BAY := 8.1
const STALL := Vector2(2.7, 5.4)
## Parked cars: fraction of roof stalls taken, cars per interior level (seen through the open sides).
const ROOF_FILL := 0.35
const LEVEL_CARS := 10
## Kinds of static parked car (car_mesh()).
const CAR_KINDS := 4
## The paints a real car park shows, mostly white, black, grey and silver.
const CAR_PAINTS := [Color(0.92, 0.92, 0.9), Color(0.92, 0.92, 0.9), Color(0.08, 0.08, 0.09), Color(0.08, 0.08, 0.09),
	Color(0.42, 0.43, 0.45), Color(0.66, 0.67, 0.69), Color(0.66, 0.67, 0.69), Color(0.35, 0.08, 0.08), Color(0.12, 0.2, 0.36)]

static var _car_cache: Dictionary = {}


## What a bed is planted with under its shrubs: low green ground cover (the lawn shader, drier
## and without mower stripes). Bare dark soil read as empty boxes from across the street.
static func ground_cover() -> Material:
	return PropFactory.lawn(Color(0.36, 0.48, 0.24), 6173, 0.45, 0.0)


static func _concrete(y0: float) -> ShaderMaterial:
	return LandmarkMats.facade("grounds_concrete", "concrete", 3.5,
		{"tint": Color(0.78, 0.77, 0.74), "roughness": 0.88, "joint_spacing": Vector2(GARAGE_BAY, GARAGE_STOREY), "joint_width": 0.025,
		"joint_dark": 0.25, "grime": 0.45, "base_y": y0})


## A multi-storey car park over `r`: `levels` decks above the ground floor on perimeter columns,
## a spandrel on every deck edge (the open horizontal bands a real one has), lift and stair cores
## on two corners, ramp slots, the roof deck with stall lines, light masts and parked cars, and a
## few cars inside each level showing through the openings. `entry_side` (0 N, 1 E, 2 S, 3 W)
## is where the drive-in is. Far builds (`detailed` false) keep only the decks, spandrels and cores.
static func garage(g: LandmarkGeo, batch: MultiMeshBatch, parent: Node3D, statics: StaticBody3D, r: Rect2, levels: int,
		y0: float, detailed: bool, seed_value: int, entry_side: int = 0) -> void:
	g.use("gar_concrete", _concrete(y0))
	g.use("gar_slab", LandmarkMats.plain("gar_slab", Color(0.62, 0.61, 0.59), 0.9))
	g.use("gar_paint", LandmarkMats.plain("gar_paint", Color(0.92, 0.9, 0.84), 0.7))
	g.use("gar_dark", LandmarkMats.plain("gar_dark", Color(0.1, 0.1, 0.11), 0.6))
	g.use("gar_glass", LandmarkMats.glass("gar_core", {"glass_tint": Color(0.18, 0.22, 0.25), "frame_color": Color(0.2, 0.21, 0.23),
		"grid": Vector2(1.5, GARAGE_STOREY), "frame_width": 0.08, "room_depth": 3.0, "storey": GARAGE_STOREY, "floor_y": y0, "interior_night": 1.6}))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bev := 0.04 if detailed else 0.0
	var c := r.get_center()
	var top := y0 + GARAGE_STOREY * float(levels)
	# The decks: a slab per level, its underside a dark ceiling seen through the openings.
	for k in range(1, levels + 1):
		var y := y0 + GARAGE_STOREY * float(k)
		g.box("gar_slab", Vector3(c.x, y - 0.18, c.y), Vector3(r.size.x, 0.36, r.size.y), Color.WHITE, Basis(), 0.0, false, 0.0, true)
		if statics:
			LandmarkGeo.shape_box(statics, Vector3(c.x, y - 0.18, c.y), Vector3(r.size.x, 0.36, r.size.y))
		# The spandrel: a precast band round the edge, proud of the columns. The entry side's
		# ground floor has none (that is the way in).
		for side in 4:
			var along := r.size.x if side % 2 == 0 else r.size.y
			var at := _edge_mid(r, side, 0.15)
			var size := Vector3(along + 0.3, SPANDREL, 0.3) if side % 2 == 0 else Vector3(0.3, SPANDREL, along + 0.3)
			g.box("gar_concrete", Vector3(at.x, y + SPANDREL * 0.5, at.y), size, Color.WHITE, Basis(), bev)
			if statics:
				LandmarkGeo.shape_box(statics, Vector3(at.x, y + SPANDREL * 0.5, at.y), size)
	# Ground-floor spandrels on the three closed sides too (a kerb wall), and the entry canopy.
	for side in 4:
		if side == entry_side:
			continue
		var along := r.size.x if side % 2 == 0 else r.size.y
		var at := _edge_mid(r, side, 0.15)
		var size := Vector3(along, 0.9, 0.3) if side % 2 == 0 else Vector3(0.3, 0.9, along)
		g.box("gar_concrete", Vector3(at.x, y0 + 0.45, at.y), size, Color(0.9, 0.9, 0.9), Basis(), bev)
	# Perimeter columns, set back a little behind the spandrels.
	for side in 4:
		var along := r.size.x if side % 2 == 0 else r.size.y
		var n := maxi(1, int(round(along / GARAGE_BAY)))
		for i in n + 1:
			var f := float(i) / float(n)
			var p := _edge_point(r, side, f, 0.7)
			g.box("gar_concrete", Vector3(p.x, y0 + (top - y0) * 0.5, p.y), Vector3(0.6, top - y0, 0.6), Color(0.94, 0.94, 0.94), Basis(), bev)
	# Cores: lift and stairs on the two corners away from the entry, glass to the street, each
	# with a roof over the top deck.
	var corners := [Vector2(r.position.x + 4.0, r.position.y + 4.0), Vector2(r.end.x - 4.0, r.end.y - 4.0)]
	for q: Vector2 in corners:
		var h := top - y0 + 3.6
		g.box("gar_concrete", Vector3(q.x, y0 + h * 0.5, q.y), Vector3(7.0, h, 7.0), Color(0.86, 0.86, 0.85), Basis(), bev)
		if statics:
			LandmarkGeo.shape_box(statics, Vector3(q.x, y0 + h * 0.5, q.y), Vector3(7.0, h, 7.0))
		var out := Vector2(signf(q.x - c.x), signf(q.y - c.y))
		# The glazed stair face on the street side.
		var gx := q.x + out.x * 3.52
		g.wall("gar_glass", Vector2(gx, q.y + 2.6 * out.x), Vector2(gx, q.y - 2.6 * out.x), y0 + 0.4, top + 2.8)
		g.box("gar_dark", Vector3(q.x, top + 3.8, q.y), Vector3(7.6, 0.4, 7.6), Color.WHITE)
	# The drive-in: a dark opening band with a lit clearance bar and a P sign on the entry side.
	var ent := _edge_point(r, entry_side, 0.5, -0.4)
	var ent_basis := LandmarkGeo.yaw(float(entry_side) * -PI * 0.5)
	g.box("gar_dark", Vector3(ent.x, y0 + 2.55, ent.y), Vector3(9.0, 0.35, 0.3), Color(1.0, 0.82, 0.2), ent_basis)
	if detailed:
		var face_yaw := [0.0, -PI * 0.5, PI, PI * 0.5][entry_side] as float
		batch.add("gar_sign", Signage.text_mesh("P  PARKING", 1.1, Signage.Letters.LIT),
			Transform3D(Basis(Vector3.UP, face_yaw + PI), Vector3(ent.x, y0 + GARAGE_STOREY + 0.6, ent.y) + Vector3(0.0, 0.0, 0.0)), Color(0.55, 0.8, 1.0))
		batch.set_no_shadow("gar_sign")
	if not detailed:
		return
	# The roof deck: stall lines in rows along x either side of drive aisles, light masts, cars.
	var rows := int((r.size.y - 4.0) / (STALL.y * 2.0 + 7.0))
	var mast := PropFactory.cylinder("lm_mast", 0.2, 1.0, LandmarkArenaDistrict.STEEL_DARK, 0.13, 10)
	var span := r.size.x - 18.0
	var stalls := int(span / STALL.x)
	var z := r.position.y + 2.5
	for row in rows:
		for half in 2:
			var zc := z + STALL.y * (0.5 + float(half)) + (7.0 if half == 1 else 0.0)
			var car_yaw := PI if half == 0 else 0.0 # nose to the aisle
			for i in stalls + 1:
				var x := r.position.x + 9.0 + float(i) * STALL.x
				g.box("gar_paint", Vector3(x, top + 0.012, zc), Vector3(0.12, 0.02, STALL.y - 0.4), Color.WHITE)
				if i < stalls and rng.randf() < ROOF_FILL:
					_car(batch, rng, Vector3(x + STALL.x * 0.5, top, zc), car_yaw + rng.randf_range(-0.04, 0.04))
		_mast(batch, parent, mast, Vector3(c.x, top, z + STALL.y + 3.5), row % 2 == 0)
		z += STALL.y * 2.0 + 7.0
	# Cars inside each level near the open sides, so the decks read as a car park at street level.
	for k in levels:
		var y := y0 + GARAGE_STOREY * float(k)
		for i in LEVEL_CARS:
			var side := i % 4
			var f := rng.randf_range(0.12, 0.88)
			var p := _edge_point(r, side, f, 4.2)
			var yaw := 0.0 if side % 2 == 1 else PI * 0.5
			if side == entry_side and k == 0:
				continue
			_car(batch, rng, Vector3(p.x, y + (0.0 if k > 0 else 0.0), p.y), yaw + (PI if rng.randf() < 0.5 else 0.0))
	# A light strip under every deck edge, lit only at night (the pools read as the car park's glow).
	for k in range(0, levels):
		var y := y0 + GARAGE_STOREY * float(k)
		for side in 4:
			var along := r.size.x if side % 2 == 0 else r.size.y
			var n := maxi(1, int(along / 16.0))
			for i in n:
				var p := _edge_point(r, side, (float(i) + 0.5) / float(n), 3.0)
				batch.add("gar_pool", PropFactory.light_pool(Color(0.85, 0.95, 1.0), 0.9), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(7.0, 1.0, 7.0)), Vector3(p.x, y + 0.03, p.y)))
	batch.set_no_shadow("gar_pool")


## A parked car on the static batch: one of the generated bodies, painted per instance.
static func _car(batch: MultiMeshBatch, rng: RandomNumberGenerator, at: Vector3, yaw: float) -> void:
	var v := rng.randi() % CAR_KINDS
	if rng.randf() < 0.55:
		v = 0
	var mesh := car_mesh(v)
	if mesh == null:
		return
	var paint: Color = CAR_PAINTS[rng.randi() % CAR_PAINTS.size()]
	batch.add("gar_car_%d" % v, mesh, Transform3D(Basis(Vector3.UP, yaw), at), paint)


## A parked car for the static batches, nose along -Z, wheels on y 0, about 4.6 m long: a
## chamfered body, a tapered glasshouse with dark glass, wheels, lamps - ~260 triangles, painted
## by the instance colour (the dark parts stay dark under any paint). The generated traffic
## bodies are 8,000+ triangles and their LODs stop at half that, so the first version, with the
## real bodies, cost 3 million triangles for 250 parked cars; a car park seen from the street or
## the air needs the silhouette and the paint, not the panel gaps. `v` stretches it into a
## longer, taller body (0 saloon, 1 pickup-like, 2 van-like, 3 low coupe).
static func car_mesh(v: int) -> Mesh:
	if _car_cache.has(v):
		return _car_cache[v]
	var dims := [Vector4(4.6, 1.8, 0.72, 0.5), Vector4(5.3, 1.9, 0.9, 0.52), Vector4(5.0, 1.95, 0.95, 0.85), Vector4(4.4, 1.85, 0.6, 0.42)][clampi(v, 0, 3)] as Vector4
	var length := dims.x
	var width := dims.y
	var body_h := dims.z
	var cab_h := dims.w
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var paint := Color.WHITE
	var glass := Color(0.05, 0.06, 0.07)
	var dark := Color(0.06, 0.06, 0.06)
	var y0 := 0.32
	var y1 := y0 + body_h
	var hl := length * 0.5
	var hw := width * 0.5
	var ch := 0.12 # chamfer on the body's top edges
	# Body: an octagonal section extruded along z (vertical sides, chamfered shoulders).
	var sec := [Vector2(-hw, y0), Vector2(hw, y0), Vector2(hw, y1 - ch), Vector2(hw - ch, y1), Vector2(-hw + ch, y1), Vector2(-hw, y1 - ch)]
	for i in sec.size():
		var a: Vector2 = sec[i]
		var b: Vector2 = sec[(i + 1) % sec.size()]
		var n := Vector3(b.y - a.y, -(b.x - a.x), 0.0).normalized()
		if n.dot(Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5 - (y0 + y1) * 0.5, 0.0)) < 0.0:
			n = -n
		_quad_c(st, Vector3(a.x, a.y, -hl), Vector3(b.x, b.y, -hl), Vector3(b.x, b.y, hl), Vector3(a.x, a.y, hl), n, paint)
	for zs: float in [-1.0, 1.0]:
		var nose := hl * zs
		var pts: Array[Vector3] = []
		for q: Vector2 in sec:
			pts.append(Vector3(q.x, q.y, nose))
		var c := Vector3(0.0, (y0 + y1) * 0.5, nose)
		for i in pts.size():
			_tri_c(st, c, pts[i], pts[(i + 1) % pts.size()], Vector3(0.0, 0.0, zs), paint)
		# Lamps: a light strip across each end.
		var lamp := Color(1.0, 0.95, 0.85) if zs < 0.0 else Color(0.7, 0.05, 0.04)
		_quad_c(st, Vector3(-hw + 0.1, y1 - 0.3, nose + zs * 0.01), Vector3(hw - 0.1, y1 - 0.3, nose + zs * 0.01),
			Vector3(hw - 0.1, y1 - 0.16, nose + zs * 0.01), Vector3(-hw + 0.1, y1 - 0.16, nose + zs * 0.01), Vector3(0.0, 0.0, zs), lamp)
	# Glasshouse: a tapered box, set back from the nose, glass on every face and a painted roof.
	var cab_len := length * (0.46 if v != 2 else 0.78)
	var cab_z := -length * 0.04 if v != 2 else length * 0.08
	var bot_half := Vector2(hw - 0.08, cab_len * 0.5)
	var top_half := Vector2(hw - 0.22, cab_len * 0.5 - (0.45 if v != 2 else 0.15))
	var yb := y1
	var yt := y1 + cab_h
	var b0 := [Vector3(-bot_half.x, yb, cab_z - bot_half.y), Vector3(bot_half.x, yb, cab_z - bot_half.y), Vector3(bot_half.x, yb, cab_z + bot_half.y), Vector3(-bot_half.x, yb, cab_z + bot_half.y)]
	var t0 := [Vector3(-top_half.x, yt, cab_z - top_half.y), Vector3(top_half.x, yt, cab_z - top_half.y), Vector3(top_half.x, yt, cab_z + top_half.y), Vector3(-top_half.x, yt, cab_z + top_half.y)]
	var outs := [Vector3(0, 0.4, -1), Vector3(1, 0.3, 0), Vector3(0, 0.4, 1), Vector3(-1, 0.3, 0)]
	for i in 4:
		var j := (i + 1) % 4
		_quad_c(st, b0[i], b0[j], t0[j], t0[i], (outs[i] as Vector3).normalized(), glass)
	_quad_c(st, t0[0], t0[1], t0[2], t0[3], Vector3.UP, paint)
	# The bed of a pickup is open: a dark tray behind the cab.
	if v == 1:
		_quad_c(st, Vector3(-hw + 0.1, y1 + 0.005, cab_z + bot_half.y + 0.1), Vector3(hw - 0.1, y1 + 0.005, cab_z + bot_half.y + 0.1),
			Vector3(hw - 0.1, y1 + 0.005, hl - 0.1), Vector3(-hw + 0.1, y1 + 0.005, hl - 0.1), Vector3.UP, dark)
	# Wheels: eight-sided drums at the four corners, their faces just proud of the body side.
	var r := 0.34
	for wz: float in [-hl + 0.85, hl - 0.85]:
		for wx: float in [-1.0, 1.0]:
			var cx := wx * (hw - 0.1)
			for k in 8:
				var a0 := TAU * float(k) / 8.0
				var a1 := TAU * float(k + 1) / 8.0
				var p0 := Vector3(0.0, r + sin(a0) * r, wz + cos(a0) * r)
				var p1 := Vector3(0.0, r + sin(a1) * r, wz + cos(a1) * r)
				var o := Vector3(cx + wx * 0.12, 0.0, 0.0)
				var ii := Vector3(cx - wx * 0.12, 0.0, 0.0)
				_quad_c(st, p0 + o, p1 + o, p1 + ii, p0 + ii, Vector3(0.0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5)), dark)
				_tri_c(st, Vector3(o.x, r, wz), p0 + o, p1 + o, Vector3(wx, 0.0, 0.0), Color(0.16, 0.16, 0.17))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.32
	mat.metallic = 0.25
	st.set_material(mat)
	var mesh := st.commit()
	_car_cache[v] = mesh
	# Its shadow is cast by two boxes (body and glasshouse, 24 triangles): a car park's worth of
	# the full car in every cascade was most of LotFill's shadow cost.
	var sh := SurfaceTool.new()
	sh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	for b: Array in [[Vector3(width, body_h, length), Vector3(0.0, (y0 + y1) * 0.5, 0.0)], [Vector3(width - 0.3, cab_h, cab_len), Vector3(0.0, y1 + cab_h * 0.5, cab_z)]]:
		sh.append_from(unit, 0, Transform3D(Basis().scaled(b[0]), b[1]))
	PropFactory._shadow_proxies[mesh] = sh.commit()
	return mesh


static func _quad_c(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	_tri_c(st, a, b, c, n, col)
	_tri_c(st, a, c, d, n, col)


static func _tri_c(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	# Front faces wind clockwise seen from the front: flip to face `n`.
	var pts := [a, b, c] if (c - a).cross(b - a).dot(n) >= 0.0 else [a, c, b]
	for p: Vector3 in pts:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


static func _mast(batch: MultiMeshBatch, parent: Node3D, mast: Mesh, at: Vector3, light: bool) -> void:
	LandmarkArenaDistrict._mast(batch, at, 9.0, mast)
	if light:
		LandmarkArenaDistrict._add_light(parent, at + Vector3(0.0, 8.5, 0.0), 26.0)


## The middle of rect side `side` (0 north, 1 east, 2 south, 3 west), `inset` metres inside.
static func _edge_mid(r: Rect2, side: int, inset: float) -> Vector2:
	return _edge_point(r, side, 0.5, inset)


## A point `f` of the way along side `side` (west to east / north to south), `inset` inside.
static func _edge_point(r: Rect2, side: int, f: float, inset: float) -> Vector2:
	match side:
		0:
			return Vector2(lerpf(r.position.x, r.end.x, f), r.position.y + inset)
		1:
			return Vector2(r.end.x - inset, lerpf(r.position.y, r.end.y, f))
		2:
			return Vector2(lerpf(r.position.x, r.end.x, f), r.end.y - inset)
	return Vector2(r.position.x + inset, lerpf(r.position.y, r.end.y, f))


## A raised planting bed over `r`: a precast kerb wall, soil, a canopy tree every `tree_every`
## metres down its long axis (0 for none), shrubs and flowering ground cover between them, and a
## bench on the kerb facing out on the long sides.
static func bed(g: LandmarkGeo, batch: MultiMeshBatch, statics: StaticBody3D, r: Rect2, y0: float, seed_value: int,
		tree_every: float = 11.0, palms: bool = false, benches: bool = true) -> void:
	g.use("bed_kerb", _concrete(y0))
	g.use("bed_soil", ground_cover())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var h := 0.5
	var c := r.get_center()
	g.box("bed_kerb", Vector3(c.x, y0 + h * 0.5, c.y), Vector3(r.size.x, h, r.size.y), Color(0.92, 0.91, 0.88), Basis(), 0.05)
	if statics:
		LandmarkGeo.shape_box(statics, Vector3(c.x, y0 + h * 0.5, c.y), Vector3(r.size.x, h, r.size.y))
	var inner := r.grow(-0.35)
	g.cap("bed_soil", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(inner)), y0 + h + 0.01)
	var long_x := r.size.x >= r.size.y
	var length := r.size.x if long_x else r.size.y
	var trees: Array[Vector2] = []
	if tree_every > 0.0:
		var n := maxi(1, int(length / tree_every))
		for i in n:
			var f := (float(i) + 0.5) / float(n)
			var p := Vector2(lerpf(r.position.x, r.end.x, f), c.y) if long_x else Vector2(c.x, lerpf(r.position.y, r.end.y, f))
			trees.append(p)
			if palms:
				var v := (seed_value + i) % PropFactory.PALM_VARIANTS
				batch.add("palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, y0 + h, p.y)), Color.WHITE)
			else:
				var tv := 1 + (seed_value + i) % 3
				var sc := PropFactory.city_tree_scale(tv, rng.randf_range(7.0, 9.5))
				batch.add("tree_%d" % tv, PropFactory.model_tree(tv), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, y0 + h, p.y)),
					Color.WHITE, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.5, 1.0)))
	# Shrubs along the bed, flowers in drifts of one kind between them.
	var area := inner.size.x * inner.size.y
	var lead := rng.randi() % PropFactory.FLOWERS.size()
	var shrub_v := rng.randi() % PropFactory.BUSHES.size()
	for k in int(clampf(area / 2.2, 4.0, 90.0)):
		var p := Vector2(rng.randf_range(inner.position.x + 0.4, inner.end.x - 0.4), rng.randf_range(inner.position.y + 0.4, inner.end.y - 0.4))
		var clear := true
		for t in trees:
			if p.distance_to(t) < 1.2:
				clear = false
		if not clear:
			continue
		var at := Vector3(p.x, y0 + h, p.y)
		var tint := Color(rng.randf_range(0.9, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.9, 1.1))
		if k % 4 == 0:
			var sc := rng.randf_range(0.7, 1.1)
			batch.add("bush_%d" % shrub_v, PropFactory.model_bush(shrub_v), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), at), tint)
		elif k % 4 == 1:
			var sc := rng.randf_range(0.8, 1.3)
			batch.add("gclump_1", PropFactory.model_grass_clump(1), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), at), tint)
		else:
			var sc := rng.randf_range(0.8, 1.4)
			batch.add("flower_%d" % lead, PropFactory.model_flower(lead), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), at), tint)
	for k in ["gclump_1", "flower_%d" % lead]:
		batch.set_no_shadow(k)
		batch.set_draw_distance(k, 140.0)
	batch.set_draw_distance("bush_%d" % shrub_v, 170.0)
	if benches:
		var bench := PropFactory.model_bench()
		var nb := maxi(1, int(length / 9.0))
		for i in nb:
			var f := (float(i) + 0.5) / float(nb)
			for side: float in [-1.0, 1.0]:
				var p: Vector2
				var yaw: float
				if long_x:
					p = Vector2(lerpf(r.position.x, r.end.x, f), c.y + side * (r.size.y * 0.5 + 0.55))
					yaw = 0.0 if side < 0.0 else PI
				else:
					p = Vector2(c.x + side * (r.size.x * 0.5 + 0.55), lerpf(r.position.y, r.end.y, f))
					yaw = PI * 0.5 if side < 0.0 else -PI * 0.5
				batch.add("grounds_bench", bench, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y0 + 0.03, p.y)))


## A bosque: trees on a grid over `r`, each in a dark iron grate with a ring bench on every
## other one - the shaded grove every Los Angeles plaza puts between its venues.
static func bosque(g: LandmarkGeo, batch: MultiMeshBatch, r: Rect2, y0: float, spacing: float, seed_value: int) -> void:
	g.use("grate", LandmarkMats.plain("bosque_grate", Color(0.13, 0.13, 0.14), 0.55, 0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var nx := maxi(1, int(r.size.x / spacing))
	var nz := maxi(1, int(r.size.y / spacing))
	var ring := _ring_bench()
	for j in nz:
		for i in nx:
			var p := r.position + Vector2((float(i) + 0.5) * r.size.x / float(nx), (float(j) + 0.5) * r.size.y / float(nz))
			g.box("grate", Vector3(p.x, y0 + 0.035, p.y), Vector3(1.8, 0.02, 1.8), Color.WHITE)
			var tv := 1 + (i + j + seed_value) % 3
			var sc := PropFactory.city_tree_scale(tv, rng.randf_range(7.5, 9.5))
			batch.add("tree_%d" % tv, PropFactory.model_tree(tv), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, y0 + 0.02, p.y)),
				Color.WHITE, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.5, 1.0)))
			if (i + j) % 2 == 0:
				batch.add("ring_bench", ring, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, y0 + 0.03, p.y)))
	for tv in range(1, 4):
		batch.set_draw_distance("tree_%d" % tv, 280.0)


## A round timber bench round a tree grate, 3.2 m across, seat at 0.45 m.
static func _ring_bench() -> Mesh:
	if _car_cache.has("ring_bench"):
		return _car_cache["ring_bench"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var segs := 12
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		for layer: Array in [[1.1, 1.6, 0.42, 0.48, Color(0.55, 0.38, 0.22)], [1.25, 1.45, 0.0, 0.42, Color(0.18, 0.18, 0.19)]]:
			var ri: float = layer[0]
			var ro: float = layer[1]
			var yb: float = layer[2]
			var yt: float = layer[3]
			st.set_color(layer[4])
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			# top, outer and inner faces
			_quad(st, d0 * ri + Vector3(0, yt, 0), d0 * ro + Vector3(0, yt, 0), d1 * ro + Vector3(0, yt, 0), d1 * ri + Vector3(0, yt, 0), Vector3.UP)
			_quad(st, d0 * ro + Vector3(0, yb, 0), d1 * ro + Vector3(0, yb, 0), d1 * ro + Vector3(0, yt, 0), d0 * ro + Vector3(0, yt, 0), (d0 + d1).normalized())
			_quad(st, d0 * ri + Vector3(0, yb, 0), d0 * ri + Vector3(0, yt, 0), d1 * ri + Vector3(0, yt, 0), d1 * ri + Vector3(0, yb, 0), -(d0 + d1).normalized())
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.75
	st.set_material(mat)
	var mesh := st.commit()
	_car_cache["ring_bench"] = mesh
	return mesh


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var flip := (c - a).cross(b - a).dot(n) < 0.0
	for v: Vector3 in ([a, b, c, a, c, d] if not flip else [a, c, b, a, d, c]):
		st.set_normal(n)
		st.add_vertex(v)


## A bronze figure on a granite plinth: an original abstract athlete (a leaning column of turned
## blocks), the star plaza's statues. `lean` turns the figure's reach.
static func sculpture(g: LandmarkGeo, statics: StaticBody3D, at: Vector2, y0: float, seed_value: int) -> void:
	g.use("plinth", LandmarkMats.plain("sculpt_plinth", Color(0.16, 0.16, 0.17), 0.25))
	g.use("bronze", LandmarkMats.plain("sculpt_bronze", Color(0.36, 0.24, 0.14), 0.38, 0.85))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ph := 1.6
	g.box("plinth", Vector3(at.x, y0 + ph * 0.5, at.y), Vector3(2.2, ph, 2.2), Color.WHITE, Basis(), 0.04)
	if statics:
		LandmarkGeo.shape_box(statics, Vector3(at.x, y0 + ph * 0.5, at.y), Vector3(2.2, ph, 2.2))
	var yaw := rng.randf() * TAU
	var p := Vector3(at.x, y0 + ph, at.y)
	var dir := Vector3(0.0, 1.0, 0.0)
	var lean := rng.randf_range(0.15, 0.4)
	# Legs, torso, a reaching arm: a chain of tapering blocks, each turned a little further.
	var parts := [[0.34, 1.0], [0.3, 0.9], [0.46, 0.9], [0.42, 0.7], [0.24, 0.35], [0.14, 1.1]]
	for i in parts.size():
		var w: float = parts[i][0]
		var l: float = parts[i][1]
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean * float(i) * 0.5 + (0.9 if i == 5 else 0.0))
		dir = b.y
		g.box("bronze", p + dir * l * 0.5, Vector3(w, l, w * 0.7), Color.WHITE, b, 0.05)
		p += dir * l * (0.92 if i < 5 else 1.0)


# ============================================================================================
# The rest of the block
# ============================================================================================
# A civic site takes the footprint its table gives (CivicSites.SITES), centred on the real
# building; at 1:1 the blocks round the arena district are bigger than that (the arena's is
# 240 x 326 m, the convention centre's 240 x 407), and what was left over was bare paving.
# `leftovers()` is the block less every arena-district site in it, handed to the first of them in
# CivicSites.ORDER; `build_leftovers()` fills each rect by where it lies.

const DISTRICT := ["arena", "live_plaza", "live_hotel", "convention_center"]
## Surface lots: at most this many parked cars in one (the rest of the stalls stand empty).
const LOT_MAX_CARS := 60
## Rects thinner than this are left as paving.
const MIN_FILL := 4.0


## World rects of `id`'s block that no arena-district site covers, if `id` is the first site in
## that block; else empty.
static func leftovers(plan: CityPlan, id: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var block := Landmarks.site_rect(plan, CivicSites.anchor(id))
	var sites: Array[Rect2] = []
	for other: String in DISTRICT:
		if Landmarks.site_rect(plan, CivicSites.anchor(other)) != block:
			continue
		if sites.is_empty() and other != id:
			return out
		sites.append((CivicSites.site(plan, other).world as Rect2))
	# Cut the block on every site edge, keep the cells no site covers, merge them into runs along
	# x, then stack runs of the same extent along z.
	var xs := [block.position.x, block.end.x]
	var zs := [block.position.y, block.end.y]
	for r in sites:
		for x: float in [r.position.x, r.end.x]:
			if x > block.position.x + 0.5 and x < block.end.x - 0.5 and not xs.has(x):
				xs.append(x)
		for z: float in [r.position.y, r.end.y]:
			if z > block.position.y + 0.5 and z < block.end.y - 0.5 and not zs.has(z):
				zs.append(z)
	xs.sort()
	zs.sort()
	var runs: Array[Rect2] = []
	for j in zs.size() - 1:
		var run := Rect2()
		var open := false
		for i in xs.size() - 1:
			var cell := Rect2(Vector2(xs[i], zs[j]), Vector2(xs[i + 1] - xs[i], zs[j + 1] - zs[j]))
			var covered := false
			for r in sites:
				if r.has_point(cell.get_center()): # slivers under 0.5 m were not cut off above
					covered = true
			if covered:
				if open:
					runs.append(run)
				open = false
			elif open:
				run = run.merge(cell)
			else:
				run = cell
				open = true
		if open:
			runs.append(run)
	for r in runs:
		var merged := false
		for k in out.size():
			var o := out[k]
			if is_equal_approx(o.position.x, r.position.x) and is_equal_approx(o.size.x, r.size.x) and is_equal_approx(o.end.y, r.position.y):
				out[k] = o.merge(r)
				merged = true
				break
		if not merged:
			out.append(r)
	var kept: Array[Rect2] = []
	for r in out:
		if minf(r.size.x, r.size.y) >= MIN_FILL:
			kept.append(r)
	return kept


## Fills `id`'s leftover rects under `pivot` (the site's frame, yaw 0 for the whole district).
static func build_leftovers(plan: CityPlan, id: String, info: Dictionary, pivot: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	if not DISTRICT.has(id) or absf(float(info.yaw)) > 0.01:
		return
	var rects := leftovers(plan, id)
	if rects.is_empty():
		return
	var centre: Vector2 = info.centre
	var y0: float = info.y0
	var site: Rect2 = info.world
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	g.use("left_paving", LandmarkMats.paving("pavers", 2.5, Color(0.9, 0.88, 0.85), 4417, 3.0, 0.3))
	for k in rects.size():
		var w := rects[k]
		var r := Rect2(w.position - centre, w.size)
		var short := minf(r.size.x, r.size.y)
		g.cap("left_paving", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(r)), y0 + 0.03)
		var seed_value := 9001 + k * 131 + id.hash() % 1000
		var toward_front := w.end.y <= site.position.y + 0.5 # north of the site: its front
		if short < 14.0:
			if detailed:
				bed(g, batch, statics, r.grow(-1.5), y0, seed_value, 11.0, short < 9.0, false)
		elif id == "convention_center" and short >= 80.0:
			_second_hall(g, batch, pivot, statics, r, y0, detailed, seed_value)
		elif id == "arena" and toward_front:
			if detailed:
				_front_grove(g, batch, statics, r, y0, seed_value)
		elif short >= 50.0 and not toward_front and id != "arena": # the arena has its own car park
			var gr := Rect2(r.position + Vector2(4.0, 4.0), Vector2(minf(r.size.x - 8.0, 150.0), minf(r.size.y - 8.0, 100.0)))
			garage(g, batch, pivot, statics, gr, 5, y0, detailed, seed_value, 3 if gr.position.x < 0.0 else 1)
			var rest := Rect2(Vector2(gr.end.x + 6.0, r.position.y + 2.0), Vector2(r.end.x - gr.end.x - 8.0, r.size.y - 4.0))
			if detailed and rest.size.x > 20.0:
				surface_lot(g, batch, pivot, rest, y0, seed_value + 7)
		elif detailed:
			surface_lot(g, batch, pivot, r.grow(-2.0), y0, seed_value)
	g.commit(pivot, "Grounds")
	g.commit_collision(statics)
	batch.build(pivot)


## The front of the arena block toward the plaza: paving, a grove in the west half, raised beds
## with palms along the street edge, bronze figures along the east half.
static func _front_grove(g: LandmarkGeo, batch: MultiMeshBatch, statics: StaticBody3D, r: Rect2, y0: float, seed_value: int) -> void:
	var grove := Rect2(r.position + Vector2(4.0, 6.0), Vector2(r.size.x * 0.34, r.size.y - 12.0))
	bosque(g, batch, grove, y0, 14.0, seed_value)
	# East of the grove: low beds of shrubs and flowers (no trees - they are what a frame pays
	# for) in two rows with walks between, and bronze figures on the walks.
	var east := Rect2(Vector2(grove.end.x + 10.0, r.position.y + 5.0), Vector2(r.end.x - grove.end.x - 16.0, r.size.y - 10.0))
	if east.size.x < 20.0:
		return
	var n := maxi(1, int(east.size.x / 26.0))
	var w := east.size.x / float(n)
	for i in n:
		for row in 2:
			var bz := east.position.y + (2.0 if row == 0 else east.size.y - 7.0)
			bed(g, batch, statics, Rect2(Vector2(east.position.x + float(i) * w + 3.0, bz), Vector2(w - 6.0, 5.0)), y0, seed_value + 3 + i * 2 + row, 0.0, false, row == 0)
		if i < n - 1:
			sculpture(g, statics, Vector2(east.position.x + float(i + 1) * w, east.get_center().y), y0, seed_value + 11 * i)


## A second exhibition hall on the rest of the convention centre's block (the real centre has
## two): long, low and white like the first, a clerestory on its north face, a loading apron and
## palms round it.
static func _second_hall(g: LandmarkGeo, batch: MultiMeshBatch, pivot: Node3D, statics: StaticBody3D, r: Rect2, y0: float, detailed: bool, seed_value: int) -> void:
	var white := LandmarkMats.facade("conv_white", "", 1.0,
		{"tint": LandmarkArenaDistrict.WHITE_PANEL, "roughness": 0.55, "metallic": 0.15, "joint_spacing": Vector2(3.0, 1.2), "joint_width": 0.028, "joint_dark": 0.22, "grime": 0.25, "base_y": y0,
		"flood_strength": 0.35, "flood_base_y": y0, "flood_reach": 7.0, "flood_spacing": 9.0})
	var band := LandmarkMats.glass("conv_band", {"glass_tint": Color(0.18, 0.34, 0.32), "frame_color": Color(0.85, 0.86, 0.86),
		"grid": Vector2(1.5, 4.0), "frame_width": 0.08, "room_depth": 20.0, "storey": 8.0, "floor_y": y0, "interior_night": 1.3})
	g.use("hall2_white", white)
	g.use("hall2_band", band)
	var hall := Rect2(r.position + Vector2(10.0, 22.0), r.size - Vector2(20.0, 36.0))
	var h := 17.0
	var hc := Vector3(hall.get_center().x, y0 + h * 0.5, hall.get_center().y)
	# A cooler grey than the first hall, so the two read as two buildings from the air.
	g.box("hall2_white", hc, Vector3(hall.size.x, h, hall.size.y), Color(0.8, 0.83, 0.86), Basis(), 0.3 if detailed else 0.0)
	if statics:
		LandmarkGeo.shape_box(statics, hc, Vector3(hall.size.x, h, hall.size.y))
	g.wall("hall2_band", Vector2(hall.end.x - 3.0, hall.position.y - 0.03), Vector2(hall.position.x + 3.0, hall.position.y - 0.03), y0 + 10.5, y0 + 15.0)
	# Roof: a row of skylight monitors across it.
	var n := maxi(2, int(hall.size.y / 40.0))
	for i in n:
		var z := hall.position.y + hall.size.y * (float(i) + 0.5) / float(n)
		g.box("hall2_white", Vector3(hc.x, y0 + h + 1.1, z), Vector3(hall.size.x - 12.0, 2.2, 4.0), Color(0.95, 0.95, 0.94), Basis(), 0.1 if detailed else 0.0)
	LandmarkArenaDistrict._occluder(pivot, [[hc, Vector3(hall.size.x, h, hall.size.y)]])
	if not detailed:
		return
	# Loading docks on the south face: dark doors under a canopy.
	g.use("hall2_dark", LandmarkMats.plain("hall2_dark", Color(0.2, 0.21, 0.22), 0.6, 0.3))
	var docks := int(hall.size.x / 9.0)
	for i in docks:
		var x := hall.position.x + (float(i) + 0.5) * hall.size.x / float(docks)
		g.box("hall2_dark", Vector3(x, y0 + 2.4, hall.end.y + 0.08), Vector3(4.2, 4.8, 0.12), Color.WHITE)
	g.box("hall2_white", Vector3(hc.x, y0 + 5.6, hall.end.y + 2.0), Vector3(hall.size.x - 4.0, 0.4, 4.0), Color(0.92, 0.92, 0.9))
	# The forecourt between the halls: beds with trees, and palms down the street sides.
	bed(g, batch, statics, Rect2(Vector2(hall.position.x + 10.0, r.position.y + 8.0), Vector2(hall.size.x * 0.4, 5.0)), y0, seed_value + 1, 11.0)
	bed(g, batch, statics, Rect2(Vector2(hall.end.x - 10.0 - hall.size.x * 0.4, r.position.y + 8.0), Vector2(hall.size.x * 0.4, 5.0)), y0, seed_value + 2, 11.0)
	for side: float in [0.0, 1.0]:
		var x := lerpf(r.position.x + 4.0, r.end.x - 4.0, side)
		for i in 8:
			var z := lerpf(hall.position.y + 6.0, hall.end.y - 6.0, float(i) / 7.0)
			var v := (i + int(side)) % PropFactory.PALM_VARIANTS
			batch.add("palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, float(i) * 1.9), Vector3(x, y0, z)), Color.WHITE)


## A surface car park over `r`: asphalt, double rows of stalls either side of drive aisles along
## x, planted islands at the row ends, light masts, a kerb of beds round it and some parked cars.
static func surface_lot(g: LandmarkGeo, batch: MultiMeshBatch, pivot: Node3D, r: Rect2, y0: float, seed_value: int) -> void:
	if r.size.x < 20.0 or r.size.y < 14.0:
		return
	g.use("lot_asphalt", LandmarkMats.paving("asphalt", 4.0, Color(0.6, 0.6, 0.61), seed_value, 0.0, 0.45))
	g.use("gar_paint", LandmarkMats.plain("gar_paint", Color(0.92, 0.9, 0.84), 0.7))
	g.use("bed_kerb", _concrete(y0))
	g.use("bed_soil", ground_cover())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	g.cap("lot_asphalt", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(r)), y0 + 0.045)
	var mast := PropFactory.cylinder("lm_mast", 0.2, 1.0, LandmarkArenaDistrict.STEEL_DARK, 0.13, 10)
	var pitch := STALL.y * 2.0 + 7.0
	var rows := int((r.size.y - 7.0) / pitch)
	var island := 6.0
	var span := r.size.x - island * 2.0 - 2.0
	var stalls := int(span / STALL.x)
	var x0 := r.position.x + island + 1.0
	var z := r.position.y + 7.0
	var cars := 0
	for row in rows:
		for half in 2:
			var zc := z + STALL.y * (0.5 + float(half))
			for i in stalls + 1:
				var x := x0 + float(i) * STALL.x
				g.box("gar_paint", Vector3(x, y0 + 0.058, zc), Vector3(0.12, 0.02, STALL.y - 0.4), Color.WHITE)
				if i < stalls and cars < LOT_MAX_CARS and rng.randf() < 0.4:
					_car(batch, rng, Vector3(x + STALL.x * 0.5, y0 + 0.045, zc), (0.0 if half == 0 else PI) + rng.randf_range(-0.05, 0.05))
					cars += 1
		# Planted islands with a tree at both ends of the double row.
		for ex: float in [r.position.x + 1.0 + island * 0.5, r.end.x - 1.0 - island * 0.5]:
			var ir := Rect2(Vector2(ex - island * 0.5 + 0.5, z + 0.5), Vector2(island - 1.0, STALL.y * 2.0 - 1.0))
			var ic := ir.get_center()
			g.box("bed_kerb", Vector3(ic.x, y0 + 0.2, ic.y), Vector3(ir.size.x, 0.2, ir.size.y), Color(0.9, 0.9, 0.88), Basis(), 0.03)
			g.cap("bed_soil", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(ir.grow(-0.2))), y0 + 0.31)
			var tv := 1 + (row + int(ex)) % 3
			var sc := PropFactory.city_tree_scale(tv, rng.randf_range(6.5, 8.5))
			batch.add("tree_%d" % tv, PropFactory.model_tree(tv), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(ic.x, y0 + 0.3, ic.y)),
				Color.WHITE, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.5, 1.0)))
		if row % 2 == 0:
			LandmarkArenaDistrict._mast(batch, Vector3(r.get_center().x, y0, z + STALL.y), 10.0, mast)
		z += pitch
