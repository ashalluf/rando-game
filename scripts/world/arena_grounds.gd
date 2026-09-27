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
const ROOF_FILL := 0.55
const LEVEL_CARS := 10
## Triangles a static parked car may have (its generated LODs go lower still).
const CAR_BUDGET := 2500
## Car bodies for the static parked cars (the same generated bodies traffic drives).
const CAR_MODELS := ["res://assets/models/car_sedan.glb", "res://assets/models/car_pickup.glb",
	"res://assets/models/car_van.glb", "res://assets/models/car_sports.glb"]
const CAR_LENGTHS := [4.7, 5.4, 5.2, 4.5]
## The paints a real car park shows, mostly white, black, grey and silver.
const CAR_PAINTS := [Color(0.92, 0.92, 0.9), Color(0.92, 0.92, 0.9), Color(0.08, 0.08, 0.09), Color(0.08, 0.08, 0.09),
	Color(0.42, 0.43, 0.45), Color(0.66, 0.67, 0.69), Color(0.66, 0.67, 0.69), Color(0.35, 0.08, 0.08), Color(0.12, 0.2, 0.36)]

static var _car_cache: Dictionary = {}


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
	var v := rng.randi() % CAR_MODELS.size()
	if rng.randf() < 0.55:
		v = 0
	var mesh := car_mesh(v)
	if mesh == null:
		return
	var paint: Color = CAR_PAINTS[rng.randi() % CAR_PAINTS.size()]
	batch.add("gar_car_%d" % v, mesh, Transform3D(Basis(Vector3.UP, yaw), at), paint)


## A generated car body as one static mesh, nose along -Z, wheels on y 0, `CAR_LENGTHS[v]` long,
## its materials taking the instance colour as paint. Cached. Null when the model is missing.
static func car_mesh(v: int) -> Mesh:
	if _car_cache.has(v):
		return _car_cache[v]
	var path: String = CAR_MODELS[v]
	if not ResourceLoader.exists(path):
		_car_cache[v] = null
		return null
	var raw := PropFactory.model_mesh(path, [], [], Transform3D.IDENTITY, {}, false)
	if raw == null or raw.get_surface_count() == 0:
		_car_cache[v] = null
		return null
	var aabb := raw.get_aabb()
	var along_x := aabb.size.x >= aabb.size.z
	var s: float = CAR_LENGTHS[v] / maxf(aabb.size.x if along_x else aabb.size.z, 0.01)
	var centre := aabb.get_center()
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5 if along_x else 0.0).scaled(Vector3(s, s, s)), Vector3.ZERO) \
		* Transform3D(Basis(), -Vector3(centre.x, aabb.position.y, centre.z))
	# A parked car in a car park is seen from the street or the air: a light copy of the body
	# (CAR_BUDGET triangles, with its own LODs and shadow twin) is all it needs.
	var mesh := PropFactory.model_mesh(path, [], [], xf, {}, true, CAR_BUDGET)
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.vertex_color_use_as_albedo = true
			mesh.surface_set_material(i, m)
	_car_cache[v] = mesh
	return mesh


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
	g.use("bed_soil", LandmarkMats.plain("bed_soil", Color(0.24, 0.19, 0.14), 0.95))
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
