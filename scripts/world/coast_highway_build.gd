class_name CoastHighwayBuild
extends RefCounted
## Builds the coast highway's stretch (CoastHighway) into the chunks it crosses: every chunk whose
## owned rect reaches the corridor (sand to the bluff's toe) builds its own ground in place of its
## zone's (`attach()`: the sea, the hill terrain under the bluff, the sand, the beach town's
## streets south of the stretch), then the road (four lanes, painted, a concrete apron and the
## seawall on the sea side, a gutter under the bluff), the beach houses on their pilings with
## decks and stairs, the stairs down to the beach, the lifeguard towers, the cars parked along
## both shoulders (surfers' vans with boards on the roof among them) and the slide's closure at
## the north end. A piece is built by the chunk whose owned rect holds its centre. FULL chunks are
## one mesh per material (HouseKit's materials, so the houses are lit like every other house) and
## one static body; LOD chunks the asphalt and the houses as far boxes; the far city the boxes.

const SEG := 4.0
const SEG_LOD := 12.0
## Seawall parapet over the apron where no house stands, and how deep the wall's footing goes.
const PARAPET := 0.95
const FOOT_Y := -0.6
## A house storey, its floor slab, the parapet on its roof.
const STOREY := 3.1
const SLAB := 0.32
const ROOF_PARAPET := 0.55
## How far the pilings go into the sand.
const PILE_FOOT := -0.8
## The concrete skirt under a house's street side, as a share of its depth from the wall.
const SKIRT_AT := 0.36
## Paint widths and the lane line's dash.
const LINE_W := 0.14
const DASH := 3.0
const DASH_GAP := 9.0
const PAINT_LIFT := 0.012

const WHITE_PAINT := Color(0.95, 0.95, 0.92)
const YELLOW_PAINT := Color(0.96, 0.78, 0.18)
## Wall colours per style (sRGB, vertex colour; h_wall multiplies its white plaster by it).
const WHITE_WALLS := [Color(0.96, 0.95, 0.92), Color(0.93, 0.93, 0.91), Color(0.95, 0.93, 0.88)]
const STUCCO_WALLS := [Color(0.93, 0.86, 0.74), Color(0.80, 0.86, 0.88), Color(0.95, 0.90, 0.72), Color(0.93, 0.80, 0.72), Color(0.84, 0.88, 0.80)]
const CEDAR := [Color(0.50, 0.36, 0.25), Color(0.47, 0.42, 0.37), Color(0.58, 0.44, 0.31)]
const BOARD := [Color(0.56, 0.60, 0.62), Color(0.40, 0.44, 0.46), Color(0.70, 0.71, 0.69), Color(0.30, 0.33, 0.35)]
const FRAME_DARK := Color(0.10, 0.10, 0.11)
const FRAME_WHITE := Color(0.92, 0.92, 0.90)
const DECK_WOOD := Color(0.55, 0.40, 0.28)
const PILE_WOOD := Color(0.36, 0.30, 0.24)
const CONCRETE := Color(0.80, 0.78, 0.74)
const BLINDS := [Color(0.92, 0.9, 0.84), Color(0.85, 0.82, 0.75), Color(0.6, 0.58, 0.55), Color(0.93, 0.93, 0.93)]
const GARAGE := [Color(0.94, 0.93, 0.90), Color(0.62, 0.52, 0.40), Color(0.32, 0.31, 0.30), Color(0.78, 0.74, 0.66)]
## Surfers' cars: body types and the muted paints of a beach car park.
const SURF_PAINTS := [Color(0.93, 0.92, 0.88), Color(0.72, 0.66, 0.52), Color(0.42, 0.55, 0.55), Color(0.55, 0.58, 0.60), Color(0.30, 0.36, 0.42), Color(0.62, 0.32, 0.22)]
const BOARD_PAINTS := [Color(0.97, 0.96, 0.92), Color(0.98, 0.84, 0.30), Color(0.30, 0.62, 0.78), Color(0.92, 0.45, 0.30), Color(0.55, 0.80, 0.70), Color(0.96, 0.72, 0.74)]

## Materials used: HouseKit's plus these.
const EXTRA_MATS := ["road", "paint", "apron", "wall", "rail_glass", "kerb"]


static func _ch(chunk: CityChunk) -> CoastHighway:
	if chunk.plan == null or chunk.plan.macro == null:
		return null
	return chunk.plan.macro.coast_highway


## True when this chunk's owned rect reaches the stretch's corridor (sand to the bluff's toe).
static func claims(chunk: CityChunk) -> bool:
	var c := _ch(chunk)
	if c == null:
		return false
	var r := chunk.owned_rect()
	var za := maxf(r.position.y, c.z_north - CoastHighway.NORTH_FADE)
	var zb := minf(r.end.y, c.z_south)
	if zb <= za:
		return false
	for k in 9:
		var z := lerpf(za, zb, float(k) / 8.0)
		var cx := c.macro.coast_x(z)
		if cx + CoastHighway.TOE + 3.0 > r.position.x and cx - 5.0 < r.end.x:
			return true
	return false


## The chunk's build steps in place of its zone's, or [] when the stretch does not reach it.
static func attach(chunk: CityChunk, block: Dictionary) -> Array[Callable]:
	var steps: Array[Callable] = []
	if not claims(chunk) or chunk.zone == MacroMap.Zone.CITY:
		return steps
	var c := _ch(chunk)
	var r := chunk.owned_rect()
	var sea := false
	var land := false
	for j in 5:
		for i in 5:
			var p := r.position + r.size * Vector2(float(i) / 4.0, float(j) / 4.0)
			if p.x < c.macro.coast_x(p.y):
				sea = true
			elif c.macro.raw_height_at(p) > 0.5:
				land = true
	if sea or chunk.zone == MacroMap.Zone.OCEAN:
		steps.append(chunk._build_water)
	if chunk.zone == MacroMap.Zone.BEACH:
		steps.append(_town_roads.bind(chunk, block))
	if land:
		steps.append_array([chunk._sample_terrain, chunk._mark_shell_ground, chunk._build_terrain, chunk._build_hill_shells,
			chunk._build_hill_roads, chunk._on_map_ground(chunk._build_mansions), chunk._on_map_ground(chunk._scatter_hills),
			chunk._on_map_ground(chunk._plant_hills)])
	else:
		steps.append(chunk._build_hill_roads)
	if chunk._owns_shoreline():
		steps.append(_beach.bind(chunk, block))
	steps.append(_road.bind(chunk))
	steps.append(_houses.bind(chunk))
	steps.append(_furniture.bind(chunk))
	if chunk.level == CityChunk.Level.FULL:
		for st: Dictionary in _owned(chunk, c.stalls, CoastHighway.CENTRE):
			steps.append(_park.bind(chunk, st))
	steps.append(_commit.bind(chunk))
	return steps


## The far city's capture: the houses as boxes (the road and the sand are the far ground's).
static func capture_steps(chunk: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	if claims(chunk):
		steps.append(_houses.bind(chunk))
	return steps


## Items of `list` ({"z", ...}) whose point at d `d` lies in this chunk's owned rect.
static func _owned(chunk: CityChunk, list: Array, d: float) -> Array:
	var c := _ch(chunk)
	var r := chunk.owned_rect()
	var out := []
	for it: Dictionary in list:
		var z := float(it.z)
		if z < r.position.y or z >= r.end.y:
			continue
		var p := c.at(float(it.get("d", d)), z)
		if r.has_point(p):
			out.append(it)
	return out


## The coast highway's own strip is drawn here, four lanes wide: its segments in the stretch are
## kept for the keep-offs and the carve but not drawn (CityChunk._hill_segments()).
static func filter_segments(chunk: CityChunk, segs: Array[Dictionary]) -> Array[Dictionary]:
	var c := _ch(chunk)
	if c == null:
		return segs
	var out: Array[Dictionary] = []
	for seg: Dictionary in segs:
		var mid: Vector2 = (seg.a as Vector2).lerp(seg.b, 0.5)
		if seg.get("name", "") == "Pacific Coast Highway" or _on_line(c, mid):
			if mid.y > c.z_north - 1.0 and mid.y < c.z_south:
				var s2 := seg.duplicate()
				s2["draw"] = false
				out.append(s2)
				continue
		out.append(seg)
	return out


static func _on_line(c: CoastHighway, p: Vector2) -> bool:
	return absf(p.x - c.macro.coast_x(p.y) - CoastHighway.CENTRE) < 2.0


## The hill shells keep off the corridor (CityChunk._shell_marks()).
static func shell_marks(chunk: CityChunk, area: Rect2) -> Array:
	var c := _ch(chunk)
	var out := []
	if c == null:
		return out
	var za := maxf(area.position.y - 30.0, c.z_north - CoastHighway.CLOSURE)
	var zb := minf(area.end.y + 30.0, c.z_south)
	var half := (CoastHighway.TOE + 4.0) * 0.5
	var z := za
	while z < zb:
		var z2 := minf(z + 20.0, zb)
		out.append([c.at(half, z), c.at(half, z2), half + 2.0])
		z = z2
	return out


# --- Ground ---------------------------------------------------------------------------------------

## The beach town's streets a BEACH block of the stretch would have built, south of the stretch.
static func _town_roads(chunk: CityChunk, block: Dictionary) -> void:
	var c := _ch(chunk)
	var rect: Rect2 = block.rect
	var params: Dictionary = CityPlan.DISTRICTS[block.district]
	var plan := chunk.plan
	var look_x := chunk._road_look(CityPlan.AXIS_X, chunk.ix + 1, params)
	var rx := plan.road_pos(CityPlan.AXIS_X, chunk.ix + 1)
	var wx := plan.road_width(CityPlan.AXIS_X, chunk.ix + 1)
	var z0 := maxf(rect.position.y, c.z_south)
	if z0 < rect.end.y - 4.0 and plan.road_open(CityPlan.AXIS_X, chunk.ix + 1, (z0 + rect.end.y) * 0.5):
		chunk._road_slab(Rect2(rx - wx * 0.5, z0, wx, rect.end.y - z0), chunk.style.asphalt, look_x.material)
		if chunk.level == CityChunk.Level.FULL:
			chunk._mark_road(true, rx, wx, z0, rect.end.y, look_x)
	var rz := plan.road_pos(CityPlan.AXIS_Z, chunk.iz + 1)
	if rz > c.z_south and plan.road_open(CityPlan.AXIS_Z, chunk.iz + 1, rect.get_center().x):
		var look_z := chunk._road_look(CityPlan.AXIS_Z, chunk.iz + 1, params)
		var wz := plan.road_width(CityPlan.AXIS_Z, chunk.iz + 1)
		chunk._road_slab(Rect2(rect.position.x, rz - wz * 0.5, rect.size.x, wz), chunk.style.asphalt, look_z.material)
		if chunk.level == CityChunk.Level.FULL:
			chunk._mark_road(false, rz, wz, rect.position.x, rect.end.x, look_z)


## The sand along the chunk's stretch of shore, the surf's spray, the lifeguard towers and the
## beach's people (BeachLife), who keep off the houses, their stairs and the towers.
static func _beach(chunk: CityChunk, block: Dictionary) -> void:
	var c := _ch(chunk)
	var r: Rect2 = block.rect
	var own := chunk.owned_rect()
	var sr := Rect2(r.position.x, r.position.y, r.size.x, maxf(own.end.y - r.position.y, r.size.y))
	chunk._build_sand(sr, r.end.y if r.end.y < own.end.y - 0.5 else INF)
	# North of the slide the mountains come down to the water: nobody on the beach there.
	var z0 := maxf(r.position.y, c.z_north - 20.0)
	var z1 := maxf(own.end.y, r.end.y)
	if z1 <= z0:
		if chunk.level == CityChunk.Level.FULL:
			chunk._build_surf_spray(sr)
		return
	if chunk.level != CityChunk.Level.FULL:
		if not chunk.capturing:
			BeachLife.build_lod(chunk, z0, z1)
		return
	chunk._build_surf_spray(sr)
	var obstacles: Array = []
	for hs: Dictionary in c.houses_in(z0 - 20.0, z1 + 20.0):
		# The house, its deck and the stair down from it, as discs along its sea side.
		var depth := float(hs.depth) + float(hs.deck)
		var n := maxi(2, int((float(hs.z1) - float(hs.z0)) / 5.0) + 1)
		for k in n:
			var z := lerpf(float(hs.z0) + 1.5, float(hs.z1) - 1.5, float(k) / float(n - 1))
			obstacles.append([c.at(CoastHighway.WALL - depth * 0.5, z), depth * 0.5 + 1.0])
		if bool(hs.stair):
			obstacles.append([c.at(CoastHighway.WALL - depth - 3.5, _stair_u_z(hs)), 3.5])
	for s: Dictionary in c.items_in(c.stairs, z0 - 10.0, z1 + 10.0):
		obstacles.append([c.at(CoastHighway.WALL - 1.5, float(s.z)), 4.0])
	var tower := {}
	for t: Dictionary in c.items_in(c.towers, z0, z1):
		var tz := float(t.z)
		var d := float(t.d)
		var at := c.at(d, tz)
		var y := BeachLife.sand_y(chunk, at.x, at.y)
		var yaw := c.sea_yaw(tz)
		chunk._batch.add("beach_tower", BeachLife.tower_mesh(), Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y, at.y)))
		chunk._add_shape(Vector3(3.1, 4.8, 3.4), Vector3(at.x, y, at.y) + Basis(Vector3.UP, yaw) * Vector3(0.0, 2.4, 0.4), yaw)
		obstacles.append([at - Vector2(-sin(yaw), -cos(yaw)) * 1.8, 4.6])
		if tower.is_empty():
			tower = {"at": at, "yaw": yaw, "y": y}
	BeachLife.build(chunk, z0, z1, obstacles, tower)


# --- Geometry --------------------------------------------------------------------------------------

## Per-chunk accumulator: arrays by material, collision boxes.
class Geo extends RefCounted:
	var s := {}
	var boxes: Array = []

	func _arr(key: String) -> Dictionary:
		if not s.has(key):
			s[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
				"c": PackedColorArray(), "t": PackedFloat32Array()}
		return s[key]

	## A triangle facing `want` (flipped if wound the other way); UVs per corner.
	func tri(key: String, a: Vector3, b: Vector3, c: Vector3, want: Vector3, col: Color, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, tan := Vector3.ZERO) -> void:
		var flat := (c - a).cross(b - a)
		if flat.length_squared() < 1e-12:
			return
		if flat.dot(want) < 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
		var n := flat.normalized() if flat.dot(want) >= 0.0 else -flat.normalized()
		var d := _arr(key)
		var tg := tan if tan != Vector3.ZERO else (b - a).normalized()
		for p: Vector3 in [a, b, c]:
			d.v.append(p)
			d.n.append(n)
			d.c.append(col)
			d.t.append_array([tg.x, tg.y, tg.z, 1.0])
		d.uv.append_array([ua, ub, uc])

	func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, col: Color, uvs: Array = [], tan := Vector3.ZERO) -> void:
		var u: Array = uvs if uvs.size() == 4 else [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		tri(key, a, b, c, want, col, u[0], u[1], u[2], tan)
		tri(key, a, c, d, want, col, u[0], u[2], u[3], tan)

	## An oriented box: centre, half extents along the basis' columns.
	func box(key: String, xf: Transform3D, half: Vector3, col: Color, faces := 63, metres_uv := false) -> void:
		var b := xf.basis
		var o := xf.origin
		var ax := [b.x.normalized(), b.y.normalized(), b.z.normalized()]
		var hx: Vector3 = ax[0] * half.x
		var hy: Vector3 = ax[1] * half.y
		var hz: Vector3 = ax[2] * half.z
		# +x, -x, +y, -y, +z, -z
		var defs := [[hx, hy, hz, half.y, half.z], [-hx, hy, -hz, half.y, half.z], [hy, hz, hx, half.z, half.x],
			[-hy, hz, -hx, half.z, half.x], [hz, hx, hy, half.x, half.y], [-hz, -hx, hy, half.x, half.y]]
		for f in 6:
			if faces & (1 << f) == 0:
				continue
			var dd: Array = defs[f]
			var cn: Vector3 = o + dd[0]
			var e1: Vector3 = dd[1]
			var e2: Vector3 = dd[2]
			var uvs: Array = []
			if metres_uv:
				var w1: float = float(dd[3]) * 2.0
				var w2: float = float(dd[4]) * 2.0
				uvs = [Vector2(0, 0), Vector2(w2, 0), Vector2(w2, w1), Vector2(0, w1)]
			quad(key, cn - e1 - e2, cn - e1 + e2, cn + e1 + e2, cn + e1 - e2, dd[0], col, uvs, e2.normalized())

	func mesh(key: String) -> ArrayMesh:
		var d: Dictionary = s.get(key, {})
		if d.is_empty() or (d.v as PackedVector3Array).is_empty():
			return null
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = d.v
		arr[Mesh.ARRAY_NORMAL] = d.n
		arr[Mesh.ARRAY_TEX_UV] = d.uv
		arr[Mesh.ARRAY_COLOR] = d.c
		arr[Mesh.ARRAY_TANGENT] = d.t
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func _geo(chunk: CityChunk) -> Geo:
	if not chunk.has_meta("coast_hwy_geo"):
		chunk.set_meta("coast_hwy_geo", Geo.new())
	return chunk.get_meta("coast_hwy_geo")


static func _material(chunk: CityChunk, key: String) -> Material:
	match key:
		"road":
			var m := PropFactory.road("asphalt", 7.0, Color(0.86, 0.86, 0.88), hash([chunk.plan.seed, "coast_hwy"]))
			m.set_shader_parameter("lamp_axis", 1)
			return m
		"paint":
			return PropFactory.road_paint_material()
		"apron":
			return PropFactory.road("sidewalk", 3.0, Color(1.45, 1.44, 1.40), 7335, 1.5, 0.35)
		"wall", "kerb":
			return PropFactory.pbr("concrete", 3.0, Color(0.86, 0.84, 0.80) if key == "wall" else Color(0.95, 0.94, 0.92))
		"rail_glass":
			return ReplicaHouses.material("h_rail")
	return HouseKit.material(key)


# --- The road --------------------------------------------------------------------------------------

## Half the road's width at z: the full four lanes, tapering to the hill strip's at the south end.
static func _half(c: CoastHighway, z: float) -> float:
	return lerpf(CoastHighway.HALF, HillRoads.COAST_WIDTH * 0.5, smoothstep(c.z_south - 70.0, c.z_south, z))


static func _p(c: CoastHighway, d: float, z: float, y: float) -> Vector3:
	var p := c.at(d, z)
	return Vector3(p.x, y, p.y)


## The asphalt, its paint, the apron and the seawall on the sea side, the gutter on the bluff side,
## the closure's barrier and their collision, for the stretch of road whose centre is in this chunk.
static func _road(chunk: CityChunk) -> void:
	var c := _ch(chunk)
	var g := _geo(chunk)
	var r := chunk.owned_rect()
	var full := chunk.level == CityChunk.Level.FULL
	var step := SEG if full else SEG_LOD
	var za := maxf(r.position.y, c.z_north)
	var zb := minf(r.end.y, c.z_south)
	if zb <= za:
		return
	var n := maxi(1, ceili((zb - za) / step))
	for k in n:
		var z0 := lerpf(za, zb, float(k) / n)
		var z1 := lerpf(za, zb, float(k + 1) / n)
		var zm := (z0 + z1) * 0.5
		if not r.has_point(c.at(CoastHighway.CENTRE, zm)):
			continue
		var y0 := c.road_y(z0)
		var y1 := c.road_y(z1)
		var h0 := _half(c, z0)
		var h1 := _half(c, z1)
		var cen := CoastHighway.CENTRE
		var a0 := _p(c, cen - h0, z0, y0)
		var b0 := _p(c, cen + h0, z0, y0)
		var a1 := _p(c, cen - h1, z1, y1)
		var b1 := _p(c, cen + h1, z1, y1)
		# UV: 0..1 across (the road shader finds its kerbs by it), metres along / 1000 (a long slab).
		g.quad("road", a0, b0, b1, a1, Vector3.UP, Color.WHITE, [Vector2(0.0, z0 / 1000.0), Vector2(1.0, z0 / 1000.0), Vector2(1.0, z1 / 1000.0), Vector2(0.0, z1 / 1000.0)])
		# Its collision: a slab under the asphalt, laid along the piece.
		var mid := (a0 + b0 + a1 + b1) * 0.25
		var along := ((a1 + b1) - (a0 + b0)) * 0.5
		var across := (b0 - a0).lerp(b1 - a1, 0.5)
		var yax := along.cross(across).normalized()
		if yax.y < 0.0:
			yax = -yax
		var bas := Basis(across.normalized(), yax, along.normalized())
		g.boxes.append([Transform3D(bas, mid - yax * 0.25), Vector3(across.length() * 0.5 + 0.2, 0.25, along.length() * 0.5 + 0.05)])
		if not full:
			continue
		if h0 > CoastHighway.HALF - 0.5:
			_paint(c, g, z0, z1)
		_sea_side(chunk, c, g, z0, z1)
		_bluff_side(c, g, z0, z1)


## Lane lines: white edge lines inside each shoulder, dashed white between the lanes, a double
## yellow pair at each edge of the painted median.
static func _paint(c: CoastHighway, g: Geo, z0: float, z1: float) -> void:
	var cen := CoastHighway.CENTRE
	var lines := [
		[cen - CoastHighway.HALF + CoastHighway.SHOULDER, WHITE_PAINT, false],
		[cen + CoastHighway.HALF - CoastHighway.SHOULDER, WHITE_PAINT, false],
		[cen - CoastHighway.MEDIAN * 0.5 - CoastHighway.LANE, WHITE_PAINT, true],
		[cen + CoastHighway.MEDIAN * 0.5 + CoastHighway.LANE, WHITE_PAINT, true],
		[cen - CoastHighway.MEDIAN * 0.5, YELLOW_PAINT, false], [cen - CoastHighway.MEDIAN * 0.5 + 0.26, YELLOW_PAINT, false],
		[cen + CoastHighway.MEDIAN * 0.5, YELLOW_PAINT, false], [cen + CoastHighway.MEDIAN * 0.5 - 0.26, YELLOW_PAINT, false],
	]
	for l: Array in lines:
		var d: float = l[0]
		var col: Color = l[1]
		if l[2]:
			# Dashes on a fixed phase of z, so they run on across chunks.
			var p := floorf(z0 / (DASH + DASH_GAP)) * (DASH + DASH_GAP)
			while p < z1:
				var s0 := maxf(p, z0)
				var s1 := minf(p + DASH, z1)
				if s1 > s0 + 0.05:
					_stripe(c, g, d, s0, s1, col)
				p += DASH + DASH_GAP
		else:
			_stripe(c, g, d, z0, z1, col)


static func _stripe(c: CoastHighway, g: Geo, d: float, z0: float, z1: float, col: Color) -> void:
	var y0 := c.road_y(z0) + PAINT_LIFT
	var y1 := c.road_y(z1) + PAINT_LIFT
	g.quad("paint", _p(c, d - LINE_W * 0.5, z0, y0), _p(c, d + LINE_W * 0.5, z0, y0), _p(c, d + LINE_W * 0.5, z1, y1), _p(c, d - LINE_W * 0.5, z1, y1), Vector3.UP, col)


## The apron between the road and the wall (flush with the asphalt) and the seawall: its face down
## to the sand, its cap, and a parapet with a rail where no house stands on it.
static func _sea_side(chunk: CityChunk, c: CoastHighway, g: Geo, z0: float, z1: float) -> void:
	var w := CoastHighway.WALL
	var ri := CoastHighway.ROAD_IN
	var y0 := c.road_y(z0)
	var y1 := c.road_y(z1)
	g.quad("apron", _p(c, w, z0, y0 + 0.02), _p(c, ri, z0, y0 + 0.02), _p(c, ri, z1, y1 + 0.02), _p(c, w, z1, y1 + 0.02), Vector3.UP, Color.WHITE)
	var zm := (z0 + z1) * 0.5
	var house := not c.house_at(zm, 0.3).is_empty()
	var stair := false
	for s: Dictionary in c.stairs:
		if absf(float(s.z) - zm) < 2.4:
			stair = true
	var top0 := y0 + (0.0 if house or stair else PARAPET)
	var top1 := y1 + (0.0 if house or stair else PARAPET)
	var sea: Vector2 = -(c.frame(zm)[0] as Vector2)
	var sea3 := Vector3(sea.x, 0.0, sea.y)
	# The face, from its footing in the sand to the top.
	g.quad("wall", _p(c, w, z0, FOOT_Y), _p(c, w, z1, FOOT_Y), _p(c, w, z1, top1), _p(c, w, z0, top0), sea3, Color.WHITE)
	if not house and not stair:
		var t := 0.3
		g.quad("wall", _p(c, w, z0, top0), _p(c, w, z1, top1), _p(c, w + t, z1, top1), _p(c, w + t, z0, top0), Vector3.UP, Color.WHITE)
		g.quad("wall", _p(c, w + t, z0, y0), _p(c, w + t, z1, y1), _p(c, w + t, z1, top1), _p(c, w + t, z0, top0), -sea3, Color.WHITE)
		g.boxes.append([Transform3D(Basis(Vector3.UP, c.sea_yaw(zm)), _p(c, w + t * 0.5, zm, (y0 + y1) * 0.5 + PARAPET * 0.5)), Vector3((z1 - z0) * 0.5, PARAPET * 0.5, t * 0.5).abs()])
	# The apron's and the wall's collision: a slab from the wall to the road.
	var mid := _p(c, (w + ri) * 0.5, zm, (y0 + y1) * 0.5 - 0.3)
	g.boxes.append([Transform3D(Basis(Vector3.UP, c.sea_yaw(zm)), mid), Vector3((z1 - z0) * 0.5 + 0.05, 0.3, (ri - w) * 0.5 + 0.1)])


## The gutter under the bluff: a concrete V from the road's edge to the toe, and a short kerb face
## down to the ground there.
static func _bluff_side(c: CoastHighway, g: Geo, z0: float, z1: float) -> void:
	var ro := CoastHighway.ROAD_OUT
	var toe := CoastHighway.TOE
	var y0 := c.road_y(z0)
	var y1 := c.road_y(z1)
	var mid := (ro + toe) * 0.5
	g.quad("kerb", _p(c, ro, z0, y0), _p(c, mid, z0, y0 - 0.1), _p(c, mid, z1, y1 - 0.1), _p(c, ro, z1, y1), Vector3.UP, Color.WHITE)
	g.quad("kerb", _p(c, mid, z0, y0 - 0.1), _p(c, toe, z0, y0 + 0.05), _p(c, toe, z1, y1 + 0.05), _p(c, mid, z1, y1 - 0.1), Vector3.UP, Color.WHITE)
	var land: Vector2 = c.frame((z0 + z1) * 0.5)[0]
	g.quad("kerb", _p(c, toe, z0, y0 + 0.05), _p(c, toe, z1, y1 + 0.05), _p(c, toe, z1, c.bench_y(z1) - 0.4), _p(c, toe, z0, c.bench_y(z0) - 0.4), -Vector3(land.x, 0.0, land.y), Color.WHITE)


# --- Houses ---------------------------------------------------------------------------------------

## A house's frame: origin on the seawall's face at its centre, x along the shore (+z), z out to
## sea; y is world height.
static func _frame(c: CoastHighway, hs: Dictionary) -> Transform3D:
	var zc := float(hs.zc)
	var f: Array = c.frame(zc)
	var land: Vector2 = f[0]
	var along: Vector2 = f[1]
	var o := c.at(CoastHighway.WALL, zc)
	return Transform3D(Basis(Vector3(along.x, 0.0, along.y), Vector3.UP, Vector3(-land.x, 0.0, -land.y)), Vector3(o.x, 0.0, o.y))


static func _stair_u_z(hs: Dictionary) -> float:
	var w := float(hs.z1) - float(hs.z0)
	return float(hs.zc) + float(hs.stair_side) * (w * 0.5 - 0.9)


static func _houses(chunk: CityChunk) -> void:
	var c := _ch(chunk)
	var r := chunk.owned_rect()
	var mine := []
	for hs: Dictionary in c.houses_in(r.position.y - 20.0, r.end.y + 20.0):
		if r.has_point(c.at(CoastHighway.WALL - float(hs.depth) * 0.5, float(hs.zc))):
			mine.append(hs)
	if mine.is_empty():
		return
	if chunk.level != CityChunk.Level.FULL or chunk.capturing:
		for hs: Dictionary in mine:
			_house_far(chunk, c, hs)
		return
	var g := _geo(chunk)
	for hs: Dictionary in mine:
		_house(chunk, c, g, hs)


static func _wall_color(hs: Dictionary) -> Color:
	var t := float(hs.tone)
	match int(hs.style):
		CoastHighway.Style.WHITE:
			return WHITE_WALLS[int(t * WHITE_WALLS.size()) % WHITE_WALLS.size()]
		CoastHighway.Style.CEDAR:
			return CEDAR[int(t * CEDAR.size()) % CEDAR.size()]
		CoastHighway.Style.BOARD:
			return BOARD[int(t * BOARD.size()) % BOARD.size()]
	return STUCCO_WALLS[int(t * STUCCO_WALLS.size()) % STUCCO_WALLS.size()]


## LOD and the far city: the house as a box in its wall colour, the deck as a slab.
static func _house_far(chunk: CityChunk, c: CoastHighway, hs: Dictionary) -> void:
	var xf := _frame(c, hs)
	var w := float(hs.z1) - float(hs.z0)
	var depth := float(hs.depth)
	var floor_y := c.road_y(float(hs.zc)) + 0.15
	var h := float(hs.floors) * STOREY + ROOF_PARAPET
	var b := xf.basis
	var centre := xf * Vector3(0.0, floor_y + h * 0.5 - SLAB, depth * 0.5)
	chunk._batch.add("lod_box", PropFactory.unit_box(), Transform3D(b.scaled_local(Vector3(w - 0.2, h + SLAB, depth)), centre), _wall_color(hs))


## One beach house: the body on its floor slab at the road's level, its sea face glazed floor to
## ceiling over a deck on pilings, its street face a garage, a door and high windows, a balcony on
## a two-storey house, a roof terrace on some, the stair from the deck down to the sand.
static func _house(chunk: CityChunk, c: CoastHighway, g: Geo, hs: Dictionary) -> void:
	var xf := _frame(c, hs)
	var w := float(hs.z1) - float(hs.z0)
	var hw := w * 0.5
	var depth := float(hs.depth)
	var deck := float(hs.deck)
	var floors := int(hs.floors)
	var style := int(hs.style)
	var zc := float(hs.zc)
	var fy := c.road_y(zc) + 0.15
	var top := fy + floors * STOREY
	var sand := 0.45
	var wall_col := _wall_color(hs)
	var wall_key := "h_wall" if style == CoastHighway.Style.WHITE or style == CoastHighway.Style.STUCCO else "h_siding"
	# Siding style rides in COLOR.a (house_siding.gdshader): cedar is stained tongue and groove,
	# board is board and batten.
	if wall_key == "h_siding":
		wall_col.a = 0.9 if style == CoastHighway.Style.CEDAR else 0.5
	var frame_col := FRAME_DARK if style == CoastHighway.Style.WHITE or style == CoastHighway.Style.BOARD else FRAME_WHITE
	var blind: Color = BLINDS[int(hs.seed) % BLINDS.size()]
	var b := xf.basis
	var o := xf.origin
	var P := func(x: float, y: float, z: float) -> Vector3: return o + b.x * x + Vector3.UP * y + b.z * z
	var sea := b.z
	var street := -b.z
	var side := b.x
	# The floor slab and the soffit under it.
	g.box("h_flat", Transform3D(b, P.call(0.0, fy - SLAB * 0.5, depth * 0.5)), Vector3(hw, SLAB * 0.5, depth * 0.5), CONCRETE)
	# The skirt under the street side, down into the sand.
	var skirt := depth * SKIRT_AT
	g.quad("h_flat", P.call(-hw, PILE_FOOT, skirt), P.call(hw, PILE_FOOT, skirt), P.call(hw, fy - SLAB, skirt), P.call(-hw, fy - SLAB, skirt), sea, CONCRETE)
	for sx: float in [-1.0, 1.0]:
		g.quad("h_flat", P.call(sx * hw, PILE_FOOT, 0.0), P.call(sx * hw, PILE_FOOT, skirt), P.call(sx * hw, fy - SLAB, skirt), P.call(sx * hw, fy - SLAB, 0.0), side * sx, CONCRETE)
	# Pilings under the sea side and the deck, braced.
	var pile_col := PILE_WOOD if style == CoastHighway.Style.CEDAR or style == CoastHighway.Style.BOARD else CONCRETE
	var pile_key := "h_trim" if pile_col == PILE_WOOD else "h_flat"
	var cols := maxi(2, int(w / 3.4) + 1)
	var rows := [skirt + (depth - skirt) * 0.5, depth - 0.4, depth + deck - 0.3]
	for zi in rows.size():
		var pz: float = rows[zi]
		var top_y := fy - SLAB if zi < 2 else fy - 0.25
		for xi in cols:
			var px := lerpf(-hw + 0.4, hw - 0.4, float(xi) / float(cols - 1))
			g.box(pile_key, Transform3D(b, P.call(px, (PILE_FOOT + top_y) * 0.5, pz)), Vector3(0.16, (top_y - PILE_FOOT) * 0.5, 0.16), pile_col, 63 & ~(1 << 3))
		# X bracing between the outer pilings of the row.
		if zi < 2 and (int(hs.seed) >> zi) % 2 == 0:
			for xi in cols - 1:
				var xa := lerpf(-hw + 0.4, hw - 0.4, float(xi) / float(cols - 1))
				var xb := lerpf(-hw + 0.4, hw - 0.4, float(xi + 1) / float(cols - 1))
				_brace(g, P.call(xa, sand + 0.4, pz), P.call(xb, top_y - 0.3, pz), sea, pile_key, pile_col)
				_brace(g, P.call(xa, top_y - 0.3, pz), P.call(xb, sand + 0.4, pz), sea, pile_key, pile_col)
	g.boxes.append([Transform3D(b, P.call(0.0, fy - SLAB * 0.5, depth * 0.5)), Vector3(hw, SLAB * 0.5, depth * 0.5)])
	# The storeys. Each floor: the sea face glazed, the street face and sides with their openings.
	for f in floors:
		var y0 := fy + f * STOREY
		var y1 := y0 + STOREY
		var inset := 0.0
		if f == 1 and floors == 2 and int(hs.seed) % 3 == 0:
			inset = 1.6 # the upper floor set back over a balcony
		# Sea face: a glass wall in panes between slim mullions.
		var panes := maxi(2, int((w - 0.6) / 1.7))
		var gx0 := -hw + 0.3
		var gx1 := hw - 0.3
		var fz := depth - inset
		g.quad(wall_key, P.call(-hw, y0, fz), P.call(gx0, y0, fz), P.call(gx0, y1, fz), P.call(-hw, y1, fz), sea, wall_col, _muv(0.0, y0, 0.3, y1))
		g.quad(wall_key, P.call(gx1, y0, fz), P.call(hw, y0, fz), P.call(hw, y1, fz), P.call(gx1, y1, fz), sea, wall_col, _muv(0.0, y0, 0.3, y1))
		g.quad(wall_key, P.call(gx0, y1 - 0.35, fz), P.call(gx1, y1 - 0.35, fz), P.call(gx1, y1, fz), P.call(gx0, y1, fz), sea, wall_col, _muv(gx0, y1 - 0.35, gx1, y1))
		for k in panes:
			var x0 := lerpf(gx0, gx1, float(k) / panes)
			var x1 := lerpf(gx0, gx1, float(k + 1) / panes)
			_window(g, P, b, x0, x1, y0 + 0.05, y1 - 0.35, fz, 1.0, frame_col, blind, int(hs.seed) + f * 31 + k, 0.08)
		# Street face (z = inset 0) and the two sides: walls with openings.
		var holes: Array = []
		if f == 0:
			if bool(hs.garage) and w > 7.0:
				var gz := c.garage_z(hs) - zc
				holes.append([gz - 1.5, y0, gz + 1.5, y0 + 2.35, "garage"])
				var dx := gz + (2.6 if gz < 0.0 else -2.6)
				if absf(dx) < hw - 0.8:
					holes.append([dx - 0.5, y0, dx + 0.5, y0 + 2.25, "door"])
			else:
				holes.append([-0.55, y0, 0.55, y0 + 2.25, "door"])
				holes.append([1.4, y0 + 1.6, minf(hw - 0.6, 4.4), y0 + 2.5, "window"])
		else:
			# High windows over the road.
			var nwin := maxi(1, int(w / 4.5))
			for k in nwin:
				var cxw := lerpf(-hw, hw, (float(k) + 0.5) / nwin)
				holes.append([cxw - 0.9, y0 + 1.3, cxw + 0.9, y0 + 2.5, "window"])
		_wall_holes(g, P, b, wall_key, wall_col, -hw, hw, y0, y1, 0.0, street, holes, frame_col, blind, int(hs.seed) + f * 7, GARAGE[int(hs.seed / 7) % GARAGE.size()])
		for sx: float in [-1.0, 1.0]:
			var sh: Array = []
			if f == floors - 1 or floors == 1:
				sh.append([depth * 0.55, y0 + 1.0, depth * 0.55 + 1.2, y0 + 2.3, "window"])
			_side_wall(g, P, b, wall_key, wall_col, sx * hw, 0.0, fz, y0, y1, side * sx, sh, frame_col, blind, int(hs.seed) + f * 13 + int(sx))
		if inset > 0.0:
			# The balcony the upper floor is set back over: its floor is the lower roof.
			_rail(g, P, b, -hw + 0.1, hw - 0.1, y0 + 0.02, depth - 0.1, sea)
			g.quad("h_siding", P.call(-hw, y0 + 0.01, depth - inset), P.call(hw, y0 + 0.01, depth - inset), P.call(hw, y0 + 0.01, depth), P.call(-hw, y0 + 0.01, depth), Vector3.UP, Color(DECK_WOOD.r, DECK_WOOD.g, DECK_WOOD.b, 0.1), _muv(-hw, depth - inset, hw, depth))
		# Floor slab edge between storeys.
		if f > 0:
			g.box("h_trim", Transform3D(b, P.call(0.0, y0, depth - inset + 0.02)), Vector3(hw + 0.02, 0.12, 0.06), frame_col)
		g.boxes.append([Transform3D(b, P.call(0.0, (y0 + y1) * 0.5, (depth - inset) * 0.5)), Vector3(hw, STOREY * 0.5, (depth - inset) * 0.5)])
	# The roof: membrane, the parapet round it, a terrace rail on some.
	var rd := depth - (1.6 if floors == 2 and int(hs.seed) % 3 == 0 else 0.0)
	g.quad("h_flat", P.call(-hw, top, 0.0), P.call(hw, top, 0.0), P.call(hw, top, rd), P.call(-hw, top, rd), Vector3.UP, Color(0.72, 0.71, 0.68))
	if style == CoastHighway.Style.CEDAR or style == CoastHighway.Style.BOARD:
		# A flat roof on deep eaves: a thin slab overhanging every side, its fascia dark.
		var ov := 0.7
		g.box("h_trim", Transform3D(b, P.call(0.0, top + 0.14, rd * 0.5)), Vector3(hw + ov, 0.14, rd * 0.5 + ov), frame_col if style == CoastHighway.Style.CEDAR else Color(0.2, 0.21, 0.22))
		g.quad("h_flat", P.call(-hw - ov, top + 0.285, -ov), P.call(hw + ov, top + 0.285, -ov), P.call(hw + ov, top + 0.285, rd + ov), P.call(-hw - ov, top + 0.285, rd + ov), Vector3.UP, Color(0.72, 0.71, 0.68))
	else:
		for e: Array in [[-hw, 0.0, hw, 0.0, street], [-hw, rd, hw, rd, sea], [-hw, 0.0, -hw, rd, -side], [hw, 0.0, hw, rd, side]]:
			var pa: Vector3 = P.call(e[0], top, e[1])
			var pb: Vector3 = P.call(e[2], top, e[3])
			var up := Vector3.UP * ROOF_PARAPET
			g.quad(wall_key, pa, pb, pb + up, pa + up, e[4], wall_col, _muv(0.0, top, pa.distance_to(pb), top + ROOF_PARAPET))
			g.quad(wall_key, pa + up, pb + up, pb + up - (e[4] as Vector3) * 0.2, pa + up - (e[4] as Vector3) * 0.2, Vector3.UP, wall_col, _muv(0.0, 0.0, pa.distance_to(pb), 0.2))
	if bool(hs.roof_deck):
		var eaves := style == CoastHighway.Style.CEDAR or style == CoastHighway.Style.BOARD
		_rail(g, P, b, -hw + 0.3, hw - 0.3, top + (0.285 if eaves else ROOF_PARAPET), rd - 0.3, sea)
	# A chimney flue or a vent stack, and a rooftop unit.
	g.box("h_metal", Transform3D(b, P.call(hw * 0.4, top + 0.5, rd * 0.3)), Vector3(0.18, 0.5, 0.18), Color(0.5, 0.5, 0.5))
	# The deck: planks on joists past the sea face, a glass balustrade round it, a stair to the sand.
	var dz0 := depth
	var dz1 := depth + deck
	var deck_col := Color(DECK_WOOD.r, DECK_WOOD.g, DECK_WOOD.b, 0.1)
	g.quad("h_siding", P.call(-hw + 0.15, fy, dz0), P.call(hw - 0.15, fy, dz0), P.call(hw - 0.15, fy, dz1), P.call(-hw + 0.15, fy, dz1), Vector3.UP, deck_col, _muv(-hw, dz0, hw, dz1))
	g.box("h_trim", Transform3D(b, P.call(0.0, fy - 0.17, (dz0 + dz1) * 0.5)), Vector3(hw - 0.15, 0.16, deck * 0.5), PILE_WOOD, 63 & ~(1 << 2))
	g.boxes.append([Transform3D(b, P.call(0.0, fy - 0.15, (dz0 + dz1) * 0.5)), Vector3(hw - 0.15, 0.15, deck * 0.5)])
	var stair := bool(hs.stair)
	var sx_side := float(hs.stair_side)
	_rail(g, P, b, -hw + 0.2, hw - 0.2, fy, dz1 - 0.05, sea, stair, sx_side * (hw - 0.9))
	for sx: float in [-1.0, 1.0]:
		_rail_run(g, P.call(sx * (hw - 0.2), fy, dz0), P.call(sx * (hw - 0.2), fy, dz1 - 0.05))
	if stair:
		_stair(g, P, b, sx_side * (hw - 0.9), dz1, fy, sand, sea)
	# Upper-floor balcony on a two-storey house with no set back.
	if floors == 2 and int(hs.seed) % 3 != 0:
		var by := fy + STOREY
		var bz1 := depth + 1.5
		g.quad("h_siding", P.call(-hw + 0.3, by, depth), P.call(hw - 0.3, by, depth), P.call(hw - 0.3, by, bz1), P.call(-hw + 0.3, by, bz1), Vector3.UP, deck_col, _muv(-hw, depth, hw, bz1))
		g.box("h_trim", Transform3D(b, P.call(0.0, by - 0.12, (depth + bz1) * 0.5)), Vector3(hw - 0.3, 0.12, 0.75), frame_col, 63 & ~(1 << 2))
		_rail(g, P, b, -hw + 0.35, hw - 0.35, by, bz1 - 0.05, sea)
	# Street side: a house number plate, an outdoor light, the bins.
	g.box("h_dark", Transform3D(b, P.call(-hw + 0.6, fy + 2.0, -0.04)), Vector3(0.22, 0.12, 0.02), Color(0.1, 0.1, 0.1))


## A UV rect in metres (the siding and stucco want metres along and up the wall).
static func _muv(x0: float, y0: float, x1: float, y1: float) -> Array:
	return [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]


## A diagonal brace between two pilings: a flat board.
static func _brace(g: Geo, a: Vector3, b2: Vector3, n: Vector3, key: String, col: Color) -> void:
	var dir := (b2 - a).normalized()
	var w := dir.cross(n).normalized() * 0.09
	g.quad(key, a - w, a + w, b2 + w, b2 - w, n, col)
	g.quad(key, a - w - n * 0.05, a + w - n * 0.05, b2 + w - n * 0.05, b2 - w - n * 0.05, -n, col)


## A glazed opening: frame, mullion-free pane (house_glass.gdshader: UV 0..1, COLOR.rgb the blind,
## COLOR.a a per-window random), recessed `recess` metres into a wall facing `n`.
static func _window(g: Geo, P: Callable, b: Basis, x0: float, x1: float, y0: float, y1: float, z: float, nsign: float, frame_col: Color, blind: Color, sd: int, recess: float) -> void:
	var n := b.z * nsign
	var fw := 0.06
	var rz := z - recess * nsign
	var rnd := float(absi(hash([sd, "win"])) % 997) / 997.0
	g.quad("glass", P.call(x0 + fw, y0 + fw, rz), P.call(x1 - fw, y0 + fw, rz), P.call(x1 - fw, y1 - fw, rz), P.call(x0 + fw, y1 - fw, rz), n, Color(blind.r, blind.g, blind.b, rnd), [], b.x * nsign)
	# The frame round it, and its reveals back to the wall face.
	for e: Array in [[x0, y0, x1, y0 + fw], [x0, y1 - fw, x1, y1], [x0, y0, x0 + fw, y1], [x1 - fw, y0, x1, y1]]:
		g.quad("h_trim", P.call(e[0], e[1], rz + 0.01 * nsign), P.call(e[2], e[1], rz + 0.01 * nsign), P.call(e[2], e[3], rz + 0.01 * nsign), P.call(e[0], e[3], rz + 0.01 * nsign), n, frame_col)
	g.quad("h_trim", P.call(x0, y0, z), P.call(x1, y0, z), P.call(x1, y0, rz), P.call(x0, y0, rz), Vector3.UP, frame_col)
	g.quad("h_trim", P.call(x0, y1, z), P.call(x1, y1, z), P.call(x1, y1, rz), P.call(x0, y1, rz), Vector3.DOWN, frame_col)
	g.quad("h_trim", P.call(x0, y0, z), P.call(x0, y1, z), P.call(x0, y1, rz), P.call(x0, y0, rz), b.x, frame_col)
	g.quad("h_trim", P.call(x1, y0, z), P.call(x1, y1, z), P.call(x1, y1, rz), P.call(x1, y0, rz), -b.x, frame_col)


## A wall in the plane z = `z` (local), x0..x1 by y0..y1, facing `n`, with rectangular holes
## ([x0, y0, x1, y1, kind]) cut out: bands between the holes' edges, then each hole filled.
static func _wall_holes(g: Geo, P: Callable, b: Basis, key: String, col: Color, x0: float, x1: float, y0: float, y1: float, z: float, n: Vector3, holes: Array, frame_col: Color, blind: Color, sd: int, door_col: Color) -> void:
	var ys := [y0, y1]
	for h: Array in holes:
		ys.append(clampf(float(h[1]), y0, y1))
		ys.append(clampf(float(h[3]), y0, y1))
	ys.sort()
	for i in ys.size() - 1:
		var ya: float = ys[i]
		var yb: float = ys[i + 1]
		if yb - ya < 0.005:
			continue
		var ym := (ya + yb) * 0.5
		var cuts: Array = []
		for h: Array in holes:
			if ym > float(h[1]) and ym < float(h[3]):
				cuts.append([float(h[0]), float(h[2])])
		cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		var xa := x0
		for cut: Array in cuts:
			if float(cut[0]) > xa + 0.005:
				g.quad(key, P.call(xa, ya, z), P.call(cut[0], ya, z), P.call(cut[0], yb, z), P.call(xa, yb, z), n, col, _muv(xa, ya, cut[0], yb))
			xa = maxf(xa, float(cut[1]))
		if x1 > xa + 0.005:
			g.quad(key, P.call(xa, ya, z), P.call(x1, ya, z), P.call(x1, yb, z), P.call(xa, yb, z), n, col, _muv(xa, ya, x1, yb))
	var nsign := 1.0 if n.dot(b.z) > 0.0 else -1.0
	for h: Array in holes:
		var kind := String(h[4])
		var hx0: float = h[0]
		var hx1: float = h[2]
		var hy0: float = h[1]
		var hy1: float = h[3]
		if kind == "window":
			_window(g, P, b, hx0, hx1, hy0, hy1, z, nsign, frame_col, blind, sd + int(hx0 * 10.0), 0.12)
			continue
		# A door or a garage door: the leaf recessed, its panels as dark lines, a frame round it.
		var rz := z - 0.14 * nsign
		var leaf := door_col if kind == "garage" else Color(0.30, 0.22, 0.16)
		g.quad("h_door", P.call(hx0, hy0, rz), P.call(hx1, hy0, rz), P.call(hx1, hy1, rz), P.call(hx0, hy1, rz), n, leaf)
		if kind == "garage":
			for k in range(1, 4):
				var gy := lerpf(hy0, hy1, float(k) / 4.0)
				g.quad("h_dark", P.call(hx0 + 0.05, gy - 0.015, rz + 0.005 * nsign), P.call(hx1 - 0.05, gy - 0.015, rz + 0.005 * nsign), P.call(hx1 - 0.05, gy + 0.015, rz + 0.005 * nsign), P.call(hx0 + 0.05, gy + 0.015, rz + 0.005 * nsign), n, Color(0.15, 0.15, 0.15))
		else:
			# A glass strip beside the handle and the handle itself.
			g.box("h_metal", Transform3D(b, P.call(hx1 - 0.18, hy0 + 1.0, rz + 0.04 * nsign)), Vector3(0.015, 0.2, 0.02), Color(0.7, 0.7, 0.68))
		g.quad("h_trim", P.call(hx0, hy1, z), P.call(hx1, hy1, z), P.call(hx1, hy1, rz), P.call(hx0, hy1, rz), Vector3.DOWN, frame_col)
		g.quad("h_trim", P.call(hx0, hy0, z), P.call(hx0, hy1, z), P.call(hx0, hy1, rz), P.call(hx0, hy0, rz), b.x, frame_col)
		g.quad("h_trim", P.call(hx1, hy0, z), P.call(hx1, hy1, z), P.call(hx1, hy1, rz), P.call(hx1, hy0, rz), -b.x, frame_col)
		if kind == "door":
			# A small flat canopy over the entry and a wall light.
			g.box("h_trim", Transform3D(b, P.call((hx0 + hx1) * 0.5, hy1 + 0.25, z - 0.45 * nsign)), Vector3((hx1 - hx0) * 0.5 + 0.4, 0.06, 0.45), frame_col)


## A side wall in the plane x = `x` (local), z0..z1 by y0..y1, facing `n`, with window holes given
## as [z0, y0, z1, y1].
static func _side_wall(g: Geo, P: Callable, b: Basis, key: String, col: Color, x: float, z0: float, z1: float, y0: float, y1: float, n: Vector3, holes: Array, frame_col: Color, blind: Color, sd: int) -> void:
	# Rotate the problem: in the side wall's own frame its "x" is the house's z.
	var sb := Basis(b.z, Vector3.UP, -b.x) if n.dot(b.x) > 0.0 else Basis(-b.z, Vector3.UP, b.x)
	var o: Vector3 = P.call(x, 0.0, 0.0)
	var flip := n.dot(b.x) <= 0.0
	var Q := func(u: float, y: float, w: float) -> Vector3:
		return o + sb.x * u + Vector3.UP * y + sb.z * w
	var hs: Array = []
	for h: Array in holes:
		var u0: float = float(h[0])
		var u1: float = float(h[2])
		if flip:
			hs.append([-u1, h[1], -u0, h[3], "window"])
		else:
			hs.append([u0, h[1], u1, h[3], "window"])
	var ua := -z1 if flip else z0
	var ub := -z0 if flip else z1
	_wall_holes(g, Q, sb, key, col, ua, ub, y0, y1, 0.0, n, hs, frame_col, blind, sd, Color.WHITE)


## A glass balustrade along the sea edge of a deck (x0..x1 at z), its top rail, posts; an opening
## for the stair at `gap_x` when `gap`.
static func _rail(g: Geo, P: Callable, b: Basis, x0: float, x1: float, y: float, z: float, n: Vector3, gap := false, gap_x := 0.0) -> void:
	var spans: Array = [[x0, x1]]
	if gap:
		spans = [[x0, gap_x - 0.55], [gap_x + 0.55, x1]]
	for s: Array in spans:
		if float(s[1]) - float(s[0]) < 0.2:
			continue
		_rail_run(g, P.call(s[0], y, z), P.call(s[1], y, z))


static func _rail_run(g: Geo, a: Vector3, b2: Vector3) -> void:
	var dir := b2 - a
	var len := dir.length()
	if len < 0.1:
		return
	var n := dir.cross(Vector3.UP).normalized()
	var h := 1.05
	g.quad("rail_glass", a + Vector3.UP * 0.05, b2 + Vector3.UP * 0.05, b2 + Vector3.UP * (h - 0.06), a + Vector3.UP * (h - 0.06), n, Color(0.75, 0.82, 0.84, 0.32))
	g.quad("rail_glass", a + Vector3.UP * 0.05, b2 + Vector3.UP * 0.05, b2 + Vector3.UP * (h - 0.06), a + Vector3.UP * (h - 0.06), -n, Color(0.75, 0.82, 0.84, 0.32))
	# The top rail: a slim metal cap.
	var t := n * 0.03
	var top := Vector3.UP * h
	g.quad("h_metal", a + top - t, b2 + top - t, b2 + top + t, a + top + t, Vector3.UP, Color(0.62, 0.62, 0.60))
	g.quad("h_metal", a + top + t, b2 + top + t, b2 + top + t - Vector3.UP * 0.05, a + top + t - Vector3.UP * 0.05, n, Color(0.62, 0.62, 0.60))
	g.quad("h_metal", a + top - t, b2 + top - t, b2 + top - t - Vector3.UP * 0.05, a + top - t - Vector3.UP * 0.05, -n, Color(0.62, 0.62, 0.60))
	var posts := maxi(1, int(len / 1.6))
	for k in posts + 1:
		var p := a.lerp(b2, float(k) / posts)
		for s: Vector3 in [n, -n, dir.normalized(), -dir.normalized()]:
			var e := s.cross(Vector3.UP).normalized() * 0.025
			g.quad("h_metal", p + s * 0.025 - e, p + s * 0.025 + e, p + s * 0.025 + e + top, p + s * 0.025 - e + top, s, Color(0.62, 0.62, 0.60))


## A timber stair from the deck's sea edge straight down to the sand: stringers, treads, rails.
static func _stair(g: Geo, P: Callable, b: Basis, x: float, z: float, top: float, bottom: float, sea: Vector3) -> void:
	var rise := top - bottom
	var steps := maxi(4, int(rise / 0.19))
	var run := steps * 0.27
	var hw := 0.5
	var wood := DECK_WOOD
	for k in steps:
		var y := top - (k + 1) * rise / steps
		var z0 := z + k * 0.27
		g.box("h_trim", Transform3D(b, P.call(x, y + 0.02, z0 + 0.14)), Vector3(hw, 0.025, 0.15), wood)
	for sx: float in [-1.0, 1.0]:
		var a: Vector3 = P.call(x + sx * (hw + 0.03), top - 0.05, z)
		var e: Vector3 = P.call(x + sx * (hw + 0.03), bottom - 0.1, z + run)
		_brace(g, a + Vector3.DOWN * 0.1, e + Vector3.DOWN * 0.1, b.x * sx, "h_trim", PILE_WOOD)
		_brace(g, a + Vector3.UP * 0.95, e + Vector3.UP * 0.95, b.x * sx, "h_metal", Color(0.62, 0.62, 0.60))
		# Posts at the top and the foot.
		g.box("h_metal", Transform3D(b, a + Vector3.UP * 0.45), Vector3(0.025, 0.5, 0.025), Color(0.62, 0.62, 0.60))
		g.box("h_metal", Transform3D(b, e + Vector3.UP * 0.5), Vector3(0.025, 0.55, 0.025), Color(0.62, 0.62, 0.60))
	# A ramp for the collision.
	var mid: Vector3 = P.call(x, (top + bottom) * 0.5 - 0.15, z + run * 0.5)
	var slope := atan2(rise, run)
	g.boxes.append([Transform3D(b * Basis(Vector3.RIGHT, slope), mid), Vector3(hw, 0.1, sqrt(rise * rise + run * run) * 0.5)])


# --- Furniture -------------------------------------------------------------------------------------

## The public stairs down the seawall to the sand, and the slide's closure at the north end.
static func _furniture(chunk: CityChunk) -> void:
	var c := _ch(chunk)
	if chunk.level != CityChunk.Level.FULL or chunk.capturing:
		return
	var g := _geo(chunk)
	for s: Dictionary in _owned(chunk, c.stairs, CoastHighway.WALL):
		var z := float(s.z)
		var hs := {"zc": z}
		var xf := _frame(c, hs)
		var b := xf.basis
		var o := xf.origin
		var P := func(x: float, y: float, zz: float) -> Vector3: return o + b.x * x + Vector3.UP * y + b.z * zz
		var top := c.road_y(z) + 0.02
		# A concrete flight straight down from the apron to the sand, square to the wall, solid to
		# the footing, with a pipe rail each side.
		var foot := 0.4
		var rise := top - foot
		var steps := int(rise / 0.18)
		var run := steps * 0.3
		var hw := 0.85
		for k in steps:
			var y := top - (k + 1) * rise / steps
			var v0 := k * 0.3
			g.box("wall", Transform3D(b, P.call(0.0, (y + FOOT_Y) * 0.5, v0 + 0.15)), Vector3(hw, (y - FOOT_Y) * 0.5, 0.15), Color.WHITE, 63 & ~(1 << 3))
		for sx: float in [-1.0, 1.0]:
			var a: Vector3 = P.call(sx * (hw - 0.05), top + 0.95, 0.0)
			var e: Vector3 = P.call(sx * (hw - 0.05), foot + 0.95, run)
			_brace(g, a, e, b.x * sx, "h_metal", Color(0.55, 0.57, 0.56))
			g.box("h_metal", Transform3D(b, a + Vector3.DOWN * 0.48), Vector3(0.03, 0.48, 0.03), Color(0.55, 0.57, 0.56))
			g.box("h_metal", Transform3D(b, e + Vector3.DOWN * 0.48), Vector3(0.03, 0.48, 0.03), Color(0.55, 0.57, 0.56))
		var slope := atan2(rise, run)
		g.boxes.append([Transform3D(b * Basis(Vector3.RIGHT, slope), P.call(0.0, (top + foot) * 0.5 - 0.15, run * 0.5)), Vector3(hw, 0.12, sqrt(rise * rise + run * run) * 0.5)])
	_closure(chunk, c, g)
	_fences_and_bins(chunk, c, g)
	_lamps(chunk, c)


## Between two houses of a run a timber fence with a gate closes the gap on the wall line; in front
## of most houses a pair of wheelie bins stands on the apron.
static func _fences_and_bins(chunk: CityChunk, c: CoastHighway, g: Geo) -> void:
	var r := chunk.owned_rect()
	for i in c.houses.size():
		var hs: Dictionary = c.houses[i]
		var zc := float(hs.zc)
		var y := c.road_y(zc) + 0.02
		if i + 1 < c.houses.size():
			var nx: Dictionary = c.houses[i + 1]
			var z0 := float(hs.z1)
			var z1 := float(nx.z0)
			var mid := (z0 + z1) * 0.5
			var access := false
			for s: Dictionary in c.stairs:
				if absf(float(s.z) - mid) < 2.5:
					access = true
			if z1 - z0 < 4.0 and z1 > z0 + 0.3 and not access and r.has_point(c.at(CoastHighway.WALL, mid)):
				var wood := Color(0.50, 0.42, 0.34, 0.5)
				var d := CoastHighway.WALL + 0.12
				var land: Vector2 = c.frame(mid)[0]
				var n3 := Vector3(land.x, 0.0, land.y)
				var a := _p(c, d, z0, y)
				var b := _p(c, d, z1, y)
				var top := Vector3.UP * 1.85
				g.quad("h_siding", a, b, b + top, a + top, n3, wood, _muv(0.0, 1.0, z1 - z0, 2.85))
				g.quad("h_siding", a, b, b + top, a + top, -n3, wood, _muv(0.0, 1.0, z1 - z0, 2.85))
				g.quad("h_trim", a + top, b + top, b + top + n3 * 0.08, a + top + n3 * 0.08, Vector3.UP, Color(0.36, 0.30, 0.24))
				g.boxes.append([Transform3D(Basis(Vector3.UP, c.sea_yaw(mid)), (a + b) * 0.5 + Vector3.UP * 0.92), Vector3(0.06, 0.92, (z1 - z0) * 0.5).abs()])
		# The bins: two by the garage, lids shut.
		if c.h01(["bins", int(hs.key)]) < 0.6 and r.has_point(c.at(CoastHighway.WALL - float(hs.depth) * 0.5, zc)):
			var gz := c.garage_z(hs) if bool(hs.garage) else zc
			var side := 1.0 if gz < zc else -1.0
			for k in 2:
				var bz := gz + side * (2.1 + float(k) * 0.75)
				if bz < float(hs.z0) + 0.4 or bz > float(hs.z1) - 0.4:
					continue
				var col: Color = [Color(0.10, 0.11, 0.12), Color(0.12, 0.30, 0.55), Color(0.18, 0.40, 0.20)][(int(hs.key) + k) % 3]
				var p := c.at(CoastHighway.WALL + 0.55, bz)
				var bb := Basis(Vector3.UP, c.sea_yaw(bz))
				g.box("h_trim", Transform3D(bb, Vector3(p.x, y + 0.5, p.y)), Vector3(0.34, 0.5, 0.3), col)
				g.box("h_trim", Transform3D(bb, Vector3(p.x, y + 1.03, p.y)), Vector3(0.36, 0.03, 0.33), col.darkened(0.2))


## Cobra-head street lamps on the bluff side's gutter, their arms out over the road: the chunk's
## own lamp prop (CityChunk._add_lamp(): the pool, the light at night, breakable).
static func _lamps(chunk: CityChunk, c: CoastHighway) -> void:
	var r := chunk.owned_rect()
	var z := ceilf((c.z_north + CoastHighway.CLOSURE + 8.0) / CoastHighway.LAMP_EVERY) * CoastHighway.LAMP_EVERY
	while z < c.z_full:
		if r.has_point(c.at(CoastHighway.CENTRE, z)):
			var p := c.at(CoastHighway.TOE - 0.4, z)
			var land: Vector2 = c.frame(z)[0]
			chunk._add_lamp(Vector3(p.x, c.road_y(z) + 0.05, p.y), -land)
		z += CoastHighway.LAMP_EVERY


## The north end: the slide's rocks across the road and the k-rails and barricade in front of them.
static func _closure(chunk: CityChunk, c: CoastHighway, g: Geo) -> void:
	var zk := c.z_north + CoastHighway.CLOSURE - 4.0
	var r := chunk.owned_rect()
	if not r.has_point(c.at(CoastHighway.CENTRE, zk)):
		return
	var y := c.road_y(zk)
	var land: Vector2 = c.frame(zk)[0]
	var yaw := atan2(land.x, land.y) + PI * 0.5
	# K-rails: precast barrier sections end to end across all four lanes.
	var d := CoastHighway.ROAD_IN + 0.6
	while d < CoastHighway.ROAD_OUT - 2.0:
		var p := c.at(d + 1.9, zk)
		_k_rail(g, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y)))
		d += 3.9
	# A barricade with its striped rails and a ROAD CLOSED board in front of them.
	var bp := c.at(CoastHighway.CENTRE, zk + 3.0)
	var bb := Basis(Vector3.UP, yaw)
	var bo := Vector3(bp.x, y, bp.y)
	for k in 3:
		var ry := 0.55 + k * 0.42
		for s in 6:
			var x0 := -2.4 + s * 0.8
			var col := Color(0.95, 0.45, 0.08) if s % 2 == 0 else Color(0.95, 0.95, 0.92)
			g.box("h_trim", Transform3D(bb, bo + bb * Vector3(x0 + 0.4, ry, 0.0)), Vector3(0.4, 0.1, 0.02), col)
	for sx: float in [-2.45, 2.45]:
		g.box("h_metal", Transform3D(bb, bo + bb * Vector3(sx, 0.7, 0.0)), Vector3(0.04, 0.7, 0.04), Color(0.7, 0.7, 0.7))
	g.box("h_trim", Transform3D(bb, bo + bb * Vector3(0.0, 1.95, 0.02)), Vector3(1.2, 0.3, 0.02), Color(0.96, 0.96, 0.94))
	if chunk.plan != null:
		var t := TextMesh.new()
		t.text = "ROAD CLOSED"
		t.font_size = 64
		t.pixel_size = 0.0045
		t.depth = 0.005
		var mi := MeshInstance3D.new()
		mi.mesh = t
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(0.05, 0.05, 0.05)
		mi.material_override = tm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(bb * Basis(Vector3.UP, PI), bo + bb * Vector3(0.0, 1.95, -0.01))
		mi.name = "ClosureSign"
		chunk.add_child(mi)
	g.boxes.append([Transform3D(bb, bo + bb * Vector3(0.0, 0.5, -1.5)), Vector3((CoastHighway.ROAD_OUT - CoastHighway.ROAD_IN) * 0.5, 0.5, 0.4)])
	# The slide: boulders strewn over the road beyond, more toward the bluff.
	for k in 26:
		var u := c.h01(["slide", k])
		var v := c.h01(["slide_v", k])
		var dd := lerpf(CoastHighway.ROAD_IN + 2.0, CoastHighway.TOE + 1.0, sqrt(u))
		var zz := lerpf(c.z_north + 1.0, zk - 5.0, v)
		var p := c.at(dd, zz)
		var s := lerpf(0.5, 2.1, c.h01(["slide_s", k])) * lerpf(0.6, 1.0, u)
		var basis := Basis(Vector3.UP, c.h01(["slide_y", k]) * TAU) * Basis(Vector3.RIGHT, c.h01(["slide_r", k]) * 0.6)
		chunk._batch.add("coast_rock_%d" % (k % 2), PropFactory.model_rock(k % 2), Transform3D(basis.scaled(Vector3.ONE * s), Vector3(p.x, c.road_y(zz) - s * 0.15, p.y)) , Color(0.78, 0.72, 0.62))


## A precast concrete k-rail (the New Jersey profile) 3.8 m long, centred, along local x.
static func _k_rail(g: Geo, xf: Transform3D) -> void:
	var prof := [Vector2(-0.30, 0.0), Vector2(-0.28, 0.08), Vector2(-0.20, 0.33), Vector2(-0.08, 0.81), Vector2(0.08, 0.81), Vector2(0.20, 0.33), Vector2(0.28, 0.08), Vector2(0.30, 0.0)]
	var hl := 1.9
	var b := xf.basis
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		var a0 := xf * Vector3(-hl, p0.y, p0.x)
		var a1 := xf * Vector3(-hl, p1.y, p1.x)
		var b0 := xf * Vector3(hl, p0.y, p0.x)
		var b1 := xf * Vector3(hl, p1.y, p1.x)
		var xm := (p0.x + p1.x) * 0.5
		var n := b.y if absf(xm) < 0.01 else (b.z * signf(xm) + b.y * 0.2)
		g.quad("wall", a0, b0, b1, a1, n, Color.WHITE)
	for sx: float in [-1.0, 1.0]:
		var poly := PackedVector3Array()
		for p: Vector2 in prof:
			poly.append(xf * Vector3(sx * hl, p.y, p.x))
		for i in range(1, poly.size() - 1):
			g.tri("wall", poly[0], poly[i], poly[i + 1], b.x * sx, Color.WHITE)


# --- Parked cars ----------------------------------------------------------------------------------

## One parked car on a shoulder stall: a real Vehicle (it sleeps until touched), a surfer's van,
## pickup or SUV with boards on a roof rack on some.
static func _park(chunk: CityChunk, st: Dictionary) -> void:
	var c := _ch(chunk)
	if not PhysicsBudget.can_spawn():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(st.seed)
	var car: Vehicle
	var surf := bool(st.surf)
	if surf:
		car = Vehicle.new()
		var types := [Vehicle.BodyType.VAN, Vehicle.BodyType.VAN, Vehicle.BodyType.PICKUP, Vehicle.BodyType.SUV, Vehicle.BodyType.MINIVAN]
		var paint: Color = SURF_PAINTS[rng.randi() % SURF_PAINTS.size()]
		car.setup(types[rng.randi() % types.size()], paint, Vehicle.Addon.NONE)
		car.setup_look(Vehicle.Finish.GLOSS if rng.randf() < 0.6 else Vehicle.Finish.METALLIC, Vehicle.Livery.NONE, Vehicle._contrast_trim(paint))
		car.look_seed = int(st.seed)
	else:
		car = Vehicle.random_car(rng)
	var z := float(st.z)
	var p := c.at(float(st.d), z)
	var holder: Node = chunk.get_parent() if chunk.get_parent() else chunk
	var pos := Vector3(p.x, c.road_y(z) + 0.45, p.y)
	car.position = WorldState.to_local(pos) if holder != chunk else pos
	car.rotation.y = float(st.yaw)
	holder.add_child(car)
	car.visible = chunk.visible
	chunk._cars.append(car)
	if surf:
		_add_boards(car, rng)


## A roof rack and one to three surfboards on it, in the car's own space (its roof is the model's
## top, Vehicle._model_top_y; a pickup's boards ride over the cab and the bed).
static func _add_boards(car: Vehicle, rng: RandomNumberGenerator) -> void:
	var dims: Dictionary = car._dims()
	var top := float(car._model_top_y)
	var length := float(dims.get("length", 4.8))
	var width := float(dims.get("width", 1.9))
	var g := Geo.new()
	var bar := Color(0.12, 0.12, 0.13)
	for zb: float in [-length * 0.12, length * 0.18]:
		g.box("h_metal", Transform3D(Basis(), Vector3(0.0, top + 0.06, zb)), Vector3(width * 0.42, 0.025, 0.03), bar)
		for sx: float in [-1.0, 1.0]:
			g.box("h_metal", Transform3D(Basis(), Vector3(sx * width * 0.4, top + 0.02, zb)), Vector3(0.03, 0.04, 0.05), bar)
	var n := 1 + rng.randi() % 3
	for k in n:
		var bl := 2.1 + rng.randf() * 0.7
		var col: Color = BOARD_PAINTS[rng.randi() % BOARD_PAINTS.size()]
		var y := top + 0.1 + k * 0.08
		var x := (float(k) - (n - 1) * 0.5) * 0.12
		_surfboard(g, Transform3D(Basis(Vector3.UP, (rng.randf() - 0.5) * 0.05), Vector3(x, y, length * 0.03)), bl, col)
		# The strap over it.
		g.box("h_dark", Transform3D(Basis(), Vector3(x, y + 0.04, -length * 0.12)), Vector3(0.3, 0.005, 0.02), Color(0.05, 0.05, 0.05))
	var mi := MeshInstance3D.new()
	mi.name = "SurfBoards"
	var mesh := ArrayMesh.new()
	for key: String in ["h_metal", "h_trim", "h_dark"]:
		var m := g.mesh(key)
		if m == null:
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(0))
		mesh.surface_set_material(mesh.get_surface_count() - 1, HouseKit.material(key))
	mi.mesh = mesh
	car.add_child(mi)


## A surfboard lying flat along local z (nose -z): a lofted outline, domed deck, a fin under the tail.
static func _surfboard(g: Geo, xf: Transform3D, length: float, col: Color) -> void:
	var n := 9
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_c := Vector3.ZERO
	for i in n + 1:
		var t := float(i) / n
		var z := lerpf(-length * 0.5, length * 0.5, t)
		var hw := 0.27 * (sin(PI * pow(t, 0.85)) * 0.9 + 0.08)
		var rock := 0.08 * pow(absf(t - 0.45) * 2.0, 2.2)
		var l := xf * Vector3(-hw, rock, z)
		var r := xf * Vector3(hw, rock, z)
		var cc := xf * Vector3(0.0, rock + 0.035, z)
		if i > 0:
			g.quad("h_trim", prev_l, prev_c, cc, l, xf.basis.y, col)
			g.quad("h_trim", prev_c, prev_r, r, cc, xf.basis.y, col)
			g.quad("h_trim", prev_l, prev_r, r, l, -xf.basis.y, col.darkened(0.15))
		prev_l = l
		prev_r = r
		prev_c = cc
	var tail := xf * Vector3(0.0, 0.0, length * 0.5 - 0.2)
	g.tri("h_dark", tail, tail + xf.basis.z * 0.12, tail - xf.basis.y * 0.11 + xf.basis.z * 0.02, xf.basis.x, Color(0.1, 0.1, 0.1))
	g.tri("h_dark", tail, tail + xf.basis.z * 0.12, tail - xf.basis.y * 0.11 + xf.basis.z * 0.02, -xf.basis.x, Color(0.1, 0.1, 0.1))


# --- Commit ----------------------------------------------------------------------------------------

## The chunk's meshes (one per material) and its static body.
static func _commit(chunk: CityChunk) -> void:
	if not chunk.has_meta("coast_hwy_geo"):
		return
	var g: Geo = chunk.get_meta("coast_hwy_geo")
	chunk.remove_meta("coast_hwy_geo")
	for key: String in g.s:
		var m := g.mesh(key)
		if m == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Coast_" + key
		mi.mesh = m
		mi.material_override = _material(chunk, key)
		if key in ["paint", "road", "apron", "glass", "rail_glass"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(mi)
	if g.boxes.is_empty() or chunk.capturing or chunk.level != CityChunk.Level.FULL:
		return
	var body := StaticBody3D.new()
	body.name = "CoastBody"
	body.collision_layer = 1
	body.collision_mask = 0
	for bx: Array in g.boxes:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = (bx[1] as Vector3).abs() * 2.0
		cs.shape = shape
		var xf: Transform3D = bx[0]
		cs.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
		body.add_child(cs)
	chunk.add_child(body)
