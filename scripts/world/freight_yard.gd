class_name FreightYard
extends RefCounted
## The Arroyo Pacific's intermodal yard (FreightRail.yard_rect): the avenue's old roadway and the
## block east of it between the yard's two junctions. Planned once per plan, pure (`layout()`), and
## built by whichever chunks' owned rects it falls in (FreightKit.attach() hands each its steps):
##
##   tracks    the two mains up the old roadway (FreightKit's) and, east of them, a ladder off the
##             east main at the south throat into six storage tracks and two loading tracks, each
##             ending at a bumper at the north end: timber ties, real rails;
##   cuts      cars standing on the storage tracks (manifest blocks: tank cars, boxcars, hoppers,
##             autoracks) and stack cars under the cranes, each a FreightStock mesh, the stack cars'
##             containers PortKit's; all hashed from the seed and the track;
##   loading   two rail-mounted gantry cranes (PortKit's yard gantry, turned across the tracks) over
##             the loading tracks and a truck lane, rows of containers waiting under them;
##   storage   the paved yard east of them: blocks of stacked containers, rows of trailers;
##   works     the yard tower by the throat, high-mast floodlights over the yard (lit at night, light
##             pools, a few real lights at FULL), the perimeter fence with the truck gate.
##
## Every roll is a hash of the seed and the yard's own coordinates, never a chunk or block rng.
## FULL: the ground through Industrial's ground mesh, uprights through its walls mesh, cars and
## containers as batches. LOD and the far city: the ground as slabs and everything as far boxes.

const LADDER_SLOPE := 0.21
const STORAGE := 6
const TRACK_STEP := 5.0
const LOADING_GAP := 16.0
const MAST_H := 32.0
const MAST_STEP := Vector2(118.0, 112.0)
const STACK_MAX := 260
const TOWER := Vector2(40.0, -62.0)

var kit: FreightKit
var ch: CityChunk
var fr: FreightRail
var plan: CityPlan
var area := Rect2()
var full := true
var lay: Dictionary = {}

static var _layouts: Dictionary = {}


## Whether chunk (ix, iz)'s block is the yard (CityChunk builds this instead of the seeded block).
static func claims(p: CityPlan, ix: int, iz: int) -> bool:
	var f := FreightRail.of(p)
	return f != null and f.yard_block(ix, iz)


## The yard block's own steps in place of the seeded block's: its pavement ring (the yard proper
## comes with FreightKit's steps, which every chunk the yard reaches runs).
static func attach(c: CityChunk) -> Array[Callable]:
	var out: Array[Callable] = []
	out.append(func() -> void: _ring(c))
	return out


## The far city's record of a yard block (capture mode): its ground slabs and far boxes.
static func capture(c: CityChunk) -> void:
	_ring(c)
	var f := FreightRail.of(c.plan)
	if f == null:
		return
	var y := FreightYard.new()
	y.ch = c
	y.fr = f
	y.plan = c.plan
	y.area = c.owned_rect()
	y.full = false
	y.lay = layout(f)
	y._ground()
	y._far()


## The pavement round the yard's block on its three street sides (N, S, E), as a block's own.
static func _ring(c: CityChunk) -> void:
	var f := FreightRail.of(c.plan)
	if f == null:
		return
	var rect: Rect2 = c.plan.block(c.ix, c.iz).rect
	var sw := c.plan.sidewalk_width
	var mat := PropFactory.road("paving", 3.0, Color(0.95, 0.94, 0.92), hash([c.plan.seed, c.ix, c.iz, "paving"]), 1.5, 0.45)
	var pieces: Array[Rect2] = []
	if c.iz == f.yard_n:
		pieces.append(Rect2(rect.position.x, rect.position.y, rect.size.x, sw))
	if c.iz == f.yard_s - 1:
		pieces.append(Rect2(rect.position.x, rect.end.y - sw, rect.size.x, sw))
	pieces.append(Rect2(rect.end.x - sw, rect.position.y, sw, rect.size.y))
	for r in pieces:
		var cc := r.get_center()
		c._add_slab(Vector3(cc.x, CityChunk.SIDEWALK_TOP * 0.5, cc.y), Vector3(r.size.x, CityChunk.SIDEWALK_TOP, r.size.y), c.style.sidewalk, true, mat)


# --- The plan --------------------------------------------------------------------------------

## The yard's layout, pure and cached: {"ground": [[rect, Industrial.G_*]], "tracks": [{"x", "z0",
## "z1"}], "ladder": [Vector2 a, Vector2 b], "cuts": [{"type", "x", "z", "flip", "look"}],
## "cranes": [Vector2], "stacks": [[pos, yaw, tier, look]], "trailers": [[pos, yaw]], "masts":
## [Vector2], "tower": Vector2, "fence": [[a, b]], "gate": Rect2}.
static func layout(f: FreightRail) -> Dictionary:
	var key := f.get_instance_id()
	if _layouts.has(key):
		return _layouts[key]
	var out := {}
	var Y := f.yard_rect
	var ax := f.avenue_x
	var sw := f.plan.sidewalk_width
	var gz0 := Y.position.y
	var gz1 := Y.end.y
	var gx1 := Y.end.x - sw
	var zn := gz0 + sw
	var zs := gz1 - sw
	# Ground: gravel over the track area, asphalt over the loading and storage yards, the avenue's
	# strip gravel.
	var track_x1 := ax + 2.3 + float(STORAGE) * TRACK_STEP + 4.0
	var load_x0 := track_x1
	var load_x1 := load_x0 + 46.0
	out.ground = [
		[Rect2(ax - 12.0, gz0, 24.0, gz1 - gz0), Industrial.G_GRAVEL],
		[Rect2(ax + 12.0, zn, track_x1 - ax - 12.0, zs - zn), Industrial.G_GRAVEL],
		[Rect2(load_x0, zn, load_x1 - load_x0, zs - zn), Industrial.G_CONCRETE],
		[Rect2(load_x1, zn, gx1 - load_x1, zs - zn), Industrial.G_ASPHALT],
	]
	# The ladder off the east main and the tracks it feeds.
	var z_l0 := gz1 - 22.0
	var x_e := ax + FreightRail.TRACK_HALF
	var tracks: Array = []
	var load_tracks := [load_x0 + 8.0, load_x0 + 13.0]
	var xs: Array = []
	for j in STORAGE:
		xs.append(x_e + float(j + 1) * TRACK_STEP)
	xs.append_array(load_tracks)
	var x_last: float = xs[xs.size() - 1]
	var z_l1 := z_l0 - (x_last - x_e) / LADDER_SLOPE
	out.ladder = [Vector2(x_e, z_l0), Vector2(x_last, z_l1)]
	for j in xs.size():
		var x: float = xs[j]
		var z_start := z_l0 - (x - x_e) / LADDER_SLOPE
		var z_end := zn + 14.0 + float(j % 2) * 5.0
		tracks.append({"x": x, "z0": z_end, "z1": z_start, "loading": j >= STORAGE})
	out.tracks = tracks
	# Cuts on the storage tracks: blocks of a type from the bumper south, gaps between blocks.
	var cuts: Array = []
	for j in tracks.size():
		var t: Dictionary = tracks[j]
		var z: float = float(t.z0) + 4.0
		var k := 0
		var h := absi(hash([f.plan.seed, "yard_track", j]))
		var fill := 0.55 + float(h % 100) / 100.0 * 0.4
		var stop_at: float = float(t.z0) + (float(t.z1) - float(t.z0) - 14.0) * fill
		var typ: int = FreightRail.Car.WELL if bool(t.loading) else [FreightRail.Car.TANK, FreightRail.Car.BOX, FreightRail.Car.HOPPER, FreightRail.Car.AUTORACK, FreightRail.Car.BOX][h % 5]
		while true:
			var hh := absi(hash([f.plan.seed, "yard_car", j, k]))
			if not bool(t.loading) and hh % 7 == 0:
				typ = [FreightRail.Car.TANK, FreightRail.Car.BOX, FreightRail.Car.HOPPER, FreightRail.Car.AUTORACK, FreightRail.Car.BOX][(hh >> 4) % 5]
			var l: float = FreightRail.CAR_LEN[typ]
			if z + l > stop_at:
				break
			cuts.append({"type": typ, "x": float(t.x), "z": z + l * 0.5, "flip": (hh >> 8) % 2 == 0, "look": hh, "track": j})
			z += l
			# Now and then a gap between blocks.
			if not bool(t.loading) and (hh >> 12) % 9 == 0:
				z += 12.0 + float((hh >> 16) % 30)
			k += 1
	out.cuts = cuts
	# The cranes over the loading tracks (span across x), the boxes waiting under them.
	var lz0: float = float(tracks[STORAGE].z0)
	var lz1: float = float(tracks[STORAGE].z1)
	var crane_x := load_x0 + 21.0
	out.cranes = [Vector2(crane_x, lerpf(lz0, lz1, 0.28)), Vector2(crane_x, lerpf(lz0, lz1, 0.72))]
	var stacks: Array = []
	# Rows under the cranes beside the truck lane.
	for row in 2:
		var x := load_x0 + 26.0 + float(row) * 2.9
		var z := lz0 + 6.0
		var n := 0
		while z < lz1 - 8.0:
			var hh := absi(hash([f.plan.seed, "yard_box", row, n]))
			var tiers := 1 + hh % 3
			for tier in tiers:
				stacks.append([Vector2(x, z + 6.2), PI * 0.5, tier, hh + tier * 7919, (hh >> 6) % 3 != 0])
			z += 12.9
			n += 1
	# Storage blocks: rows of stacks along z, east of the loading strip, in a few blocks.
	var bx0 := load_x1 + 10.0
	var blocks := 0
	var bx := bx0
	while bx + 30.0 < gx1 - 40.0 and stacks.size() < STACK_MAX:
		var hb := absi(hash([f.plan.seed, "yard_block", blocks]))
		if hb % 3 != 0:
			var rows := 6
			for r in rows:
				var x := bx + float(r) * 2.9
				var z := zn + 18.0
				var n := 0
				while z < zs - 30.0 and stacks.size() < STACK_MAX:
					var hh := absi(hash([f.plan.seed, "yard_stack", blocks, r, n]))
					if hh % 11 != 0:
						var tiers := 1 + hh % 4
						for tier in tiers:
							stacks.append([Vector2(x, z + 6.2), PI * 0.5, tier, hh + tier * 104729, (hh >> 5) % 4 != 0])
					z += 13.4
					n += 1
			bx += 6.0 * 2.9 + 16.0
		else:
			bx += 34.0
		blocks += 1
	out.stacks = stacks
	# Trailers parked in rows in what is left east of the stacks.
	var trailers: Array = []
	var tx := bx + 6.0
	var trow := 0
	while tx < gx1 - 24.0:
		var z := zn + 12.0
		while z < zs - 14.0:
			var hh := absi(hash([f.plan.seed, "yard_trailer", trow, int(z)]))
			if hh % 5 != 0:
				trailers.append([Vector2(tx, z), 0.0 if (hh >> 3) % 2 == 0 else PI, hh])
			z += 3.6
		tx += 20.0
		trow += 1
	out.trailers = trailers
	# High masts on a grid, kept off the tracks and the ladder.
	var masts: Array = []
	var mx := ax + 37.5
	while mx < gx1 - 10.0:
		var mz := zn + 30.0
		while mz < zs - 10.0:
			var p := Vector2(mx, mz)
			var ok := true
			for t: Dictionary in tracks:
				if absf(p.x - float(t.x)) < 4.0 and p.y > float(t.z0) - 6.0 and p.y < float(t.z1) + 6.0:
					ok = false
			if _ladder_distance(out.ladder, p) < 5.0:
				ok = false
			if ok:
				masts.append(p)
			mz += MAST_STEP.y
		mx += MAST_STEP.x
	out.masts = masts
	out.tower = Vector2(ax + TOWER.x, z_l0 + TOWER.y)
	# The fence round the yard (gaps for the mains at the south, the gate on the east).
	var gate := Rect2(gx1 - 6.0, (zn + zs) * 0.5 - 18.0, 8.0, 36.0)
	out.gate = gate
	out.fence = [
		[Vector2(ax - 11.6, gz0 + 0.6), Vector2(ax - 11.6, gz1 - 0.6)],
		[Vector2(ax - 11.6, gz0 + 0.6), Vector2(ax + 12.0, gz0 + 0.6)],
		[Vector2(ax + 12.0, zn + 0.4), Vector2(gx1 - 0.4, zn + 0.4)],
		[Vector2(gx1 - 0.4, zn + 0.4), Vector2(gx1 - 0.4, gate.position.y)],
		[Vector2(gx1 - 0.4, gate.end.y), Vector2(gx1 - 0.4, zs - 0.4)],
		[Vector2(ax + 12.0, zs - 0.4), Vector2(gx1 - 0.4, zs - 0.4)],
	]
	_layouts[key] = out
	return out


static func _ladder_distance(ladder: Array, p: Vector2) -> float:
	var a: Vector2 = ladder[0]
	var b: Vector2 = ladder[1]
	var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a.lerp(b, t))


# --- The build ---------------------------------------------------------------------------------

func setup(k: FreightKit) -> void:
	kit = k
	ch = k.chunk
	fr = k.fr
	plan = ch.plan
	area = k.area
	full = k.full
	lay = layout(fr)
	Industrial._state(ch)


func steps() -> Array[Callable]:
	var out: Array[Callable] = []
	out.append(_ground)
	out.append(_tracks_step)
	out.append(_cars_step)
	out.append(_works_step)
	return out


func _y(p: Vector2) -> float:
	return ch._gy(p.x, p.y) + CityChunk.SIDEWALK_TOP + Industrial.LIFT


func _clip(r: Rect2) -> Rect2:
	return r.intersection(area)


func _ground() -> void:
	for g: Array in lay.ground:
		var r := _clip(g[0])
		if r.size.x < 0.05 or r.size.y < 0.05:
			continue
		var kind: int = g[1]
		if full:
			ch._ind.ground.append([r, kind, Industrial._h01([plan.seed, r.position, "fy_var"])])
		else:
			var c := r.get_center()
			ch._add_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP + Industrial.LIFT - 0.02, c.y), Vector3(r.size.x, 0.04, r.size.y),
				Industrial._far_ground(kind), not ch.capturing, Industrial._far_material(kind))
	# Collision for the yard floor (FULL: Industrial's ground draws but does not collide).
	if full:
		for g: Array in lay.ground:
			var r := _clip(g[0])
			if r.size.x < 0.05 or r.size.y < 0.05:
				continue
			var c := r.get_center()
			ch._add_shape(Vector3(r.size.x, 0.3, r.size.y), Vector3(c.x, _y(c) - 0.15, c.y))


## The yard's tracks in this chunk: each storage and loading track from its bumper to the ladder,
## and the ladder itself, on gravel beds with timber ties.
func _tracks_step() -> void:
	var st_steps := 8.0
	for t: Dictionary in lay.tracks:
		var x: float = t.x
		var z0: float = t.z0
		var z1: float = t.z1
		var z := z0
		while z < z1:
			var zb := minf(z + st_steps, z1)
			var mid := Vector2(x, (z + zb) * 0.5)
			if area.has_point(mid):
				var ya := _y(Vector2(x, z)) + FreightRail.TRACK_DEPTH
				var yb := _y(Vector2(x, zb)) + FreightRail.TRACK_DEPTH
				if full:
					kit.ballast([x], z, zb, ya, yb, ya - FreightRail.TRACK_DEPTH, yb - FreightRail.TRACK_DEPTH, 0.7)
					kit.rails(x, z, x, zb, ya, yb)
					kit.ties(x, z, x, zb, ya, yb, true)
				else:
					ch._add_slab(Vector3(x, CityChunk.SIDEWALK_TOP + Industrial.LIFT + 0.05, (z + zb) * 0.5), Vector3(3.6, 0.1, zb - z), Color(0.36, 0.33, 0.3), false, Industrial._far_material(Industrial.G_GRAVEL))
			z = zb
		# The bumper at the north end.
		if full and area.has_point(Vector2(x, z0)):
			kit._buffer_stop(Vector3(x, _y(Vector2(x, z0)) + FreightRail.TRACK_DEPTH, z0))
	# The ladder: a diagonal track from the east main to the last track.
	var a: Vector2 = lay.ladder[0]
	var b: Vector2 = lay.ladder[1]
	var n := ceili(a.distance_to(b) / 6.0)
	for i in n:
		var p0 := a.lerp(b, float(i) / float(n))
		var p1 := a.lerp(b, float(i + 1) / float(n))
		if not area.has_point((p0 + p1) * 0.5):
			continue
		var ya := _y(p0) + FreightRail.TRACK_DEPTH
		var yb := _y(p1) + FreightRail.TRACK_DEPTH
		if full:
			kit.rails(p0.x, p0.y, p1.x, p1.y, ya, yb)
			kit.ties(p0.x, p0.y, p1.x, p1.y, ya, yb, true)


## The cars standing on the yard's tracks (their centres in this chunk), the stack cars' boxes.
func _cars_step() -> void:
	for c: Dictionary in lay.cuts:
		var p := Vector2(float(c.x), float(c.z))
		if not area.has_point(p):
			continue
		var t: int = c.type
		var y := _y(p) + FreightRail.TRACK_DEPTH
		var basis := Basis(Vector3.UP, PI if bool(c.flip) else 0.0)
		var look: int = c.look
		if full:
			ch._batch.add("fr_car_%d" % t, FreightStock.mesh(t), Transform3D(basis, Vector3(p.x, y - ch._gy(p.x, p.y), p.y)), Color(1, 1, 1), FreightStock.custom(t, look))
			var env := FreightStock.envelope(t)
			ch._add_shape(Vector3(env.x, env.y - 0.8, env.z), Vector3(p.x, y + 0.8 + (env.y - 0.8) * 0.5, p.y))
			if t == FreightRail.Car.WELL:
				_well_boxes(p, y, look, basis)
		else:
			var env := FreightStock.envelope(t)
			var list: Array = FreightStock.PAINTS.get(t, [FreightStock.LOCO_PAINT])
			var col: Color = FreightStock.PALETTE[int(list[absi(look) % list.size()])]
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(env.x, env.y - 0.7, env.z - 0.6)), Vector3(p.x, y + 0.7 + (env.y - 0.7) * 0.5 - ch._gy(p.x, p.y), p.y)), col, Color(0.0, 0.0, 0.0, 1.0))
	for s: Array in lay.stacks:
		var p: Vector2 = s[0]
		if not area.has_point(p):
			continue
		var tier: int = s[2]
		var look: int = s[3]
		var y := CityChunk.SIDEWALK_TOP + Industrial.LIFT + float(tier) * PortKit.H_HC
		if full:
			_box(Vector3(p.x, y, p.y), float(s[1]), look, bool(s[4]))
		elif tier == 0:
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(2.44, PortKit.H_HC * float(1 + absi(look) % 3), 12.2)), Vector3(p.x, CityChunk.SIDEWALK_TOP + PortKit.H_HC * float(1 + absi(look) % 3) * 0.5, p.y)),
				PortKit.LIVERY_PAINT[absi(look) % PortKit.LIVERY_COUNT], Color(0.0, 0.0, 0.0, 1.0))
	for tr: Array in lay.trailers:
		var p: Vector2 = tr[0]
		if not area.has_point(p):
			continue
		if full:
			var hh: int = tr[2]
			var tint: Color = [Color(0.95, 0.95, 0.93), Color(0.85, 0.86, 0.88), Color(0.62, 0.12, 0.1), Color(0.2, 0.32, 0.55), Color(0.9, 0.9, 0.86)][hh % 5]
			Industrial._prop(ch, Vector3(p.x, CityChunk.SIDEWALK_TOP + Industrial.LIFT, p.y), float(tr[1]) + PI * 0.5, tint, IndustrialKit.trailer.bind(0))
		else:
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(16.0, 3.0, 2.6)), Vector3(p.x, CityChunk.SIDEWALK_TOP + 2.3, p.y)), Color(0.85, 0.85, 0.83), Color(0.0, 0.0, 0.0, 1.0))


## A well car's containers in the car's own frame (origin on the rails at its middle): a 53 ft
## or 40 ft box in the well (now and then two 20s), a 53 ft high-cube on top of most, from the
## car's look. [[Transform3D, paint, custom]] - the yard's standing cars and the trains share it.
static func well_boxes(look: int) -> Array:
	var out: Array = []
	var floor_y := 0.36
	var pick := absi(look) % 7
	var top_y := floor_y
	if pick == 0:
		for e: float in [-1.0, 1.0]:
			out.append(_local_box(Vector3(0.0, floor_y, e * 3.1), look + int(e * 3.0), false, false, false))
		top_y = floor_y + PortKit.H_STD
	else:
		var high := pick < 4
		out.append(_local_box(Vector3(0.0, floor_y, 0.0), look, true, high, pick % 2 == 0))
		top_y = floor_y + (PortKit.H_HC if high else PortKit.H_STD)
	if (absi(look) >> 5) % 6 != 0:
		out.append(_local_box(Vector3(0.0, top_y, 0.0), look * 31 + 7, true, true, true))
	return out


static func _local_box(c: Vector3, look: int, forty: bool, high: bool, long53: bool) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(look)
	var livery := absi(look >> 2) % PortKit.LIVERY_COUNT
	var lk := PortKit.container_look(livery, rng)
	var xf := PortKit.container_xform(c + Vector3(0.0, (PortKit.H_HC if high else PortKit.H_STD) * 0.5, 0.0), forty, high, rng.randf() < 0.5)
	xf.basis = Basis(Vector3.UP, PI * 0.5) * xf.basis
	if long53:
		xf.basis = xf.basis * Basis().scaled(Vector3(16.15 / PortKit.L40, 1.0, 1.0))
	return [xf, lk[0], lk[1]]


func _well_boxes(p: Vector2, rail_y: float, look: int, basis: Basis) -> void:
	var at := Vector3(p.x, rail_y - ch._gy(p.x, p.y), p.y)
	for b: Array in well_boxes(look):
		var xf: Transform3D = b[0]
		ch._batch.add("container", PropFactory.container(), Transform3D(basis * xf.basis, at + basis * xf.origin), b[1], b[2])


## A yard container on the ground (stacks), at `c` (floor), yaw.
func _box(c: Vector3, yaw: float, look: int, forty: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(look)
	var livery := absi(look >> 3) % PortKit.LIVERY_COUNT
	var lk := PortKit.container_look(livery, rng)
	var high := true
	var xf := PortKit.container_xform(Vector3(c.x, c.y + (PortKit.H_HC if high else PortKit.H_STD) * 0.5, c.z), forty, high, rng.randf() < 0.5)
	xf.basis = Basis(Vector3.UP, yaw) * xf.basis
	ch._batch.add("container", PropFactory.container(), xf, lk[0], lk[1])


## The tower, the masts, the cranes, the fence and the gate.
func _works_step() -> void:
	var tw: Vector2 = lay.tower
	if area.has_point(tw):
		_tower(tw)
	for m: Vector2 in lay.masts:
		if area.has_point(m):
			_mast(m)
	for c: Vector2 in lay.cranes:
		if area.has_point(c):
			if full:
				var y := CityChunk.SIDEWALK_TOP + Industrial.LIFT
				ch._batch.add("rtg", PropFactory.rtg(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(c.x, y, c.y)))
				for e: float in [-1.0, 1.0]:
					ch._add_shape(Vector3(1.4, PortKit.RTG_H, 7.6), Vector3(c.x + e * PortKit.RTG_SPAN * 0.5, _y(c) + PortKit.RTG_H * 0.5, c.y))
			else:
				for e: float in [-1.0, 1.0]:
					ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(1.4, PortKit.RTG_H, 7.0)), Vector3(c.x + e * PortKit.RTG_SPAN * 0.5, CityChunk.SIDEWALK_TOP + PortKit.RTG_H * 0.5, c.y)), Color(0.18, 0.45, 0.48), Color(0.0, 0.0, 0.0, 1.0))
				ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(PortKit.RTG_SPAN + 1.4, 1.6, 6.0)), Vector3(c.x, CityChunk.SIDEWALK_TOP + PortKit.RTG_H, c.y)), Color(0.88, 0.88, 0.86), Color(0.0, 0.0, 0.0, 1.0))
	if not full:
		return
	for fe: Array in lay.fence:
		var a: Vector2 = fe[0]
		var b: Vector2 = fe[1]
		# Each chunk builds the stretch of fence in its own rect.
		var seg := _clip_segment(a, b, area)
		if not seg.is_empty():
			Industrial._fence(ch, seg[0], seg[1])
	var gate: Rect2 = lay.gate
	if area.has_point(gate.get_center()):
		_gate(gate)


static func _clip_segment(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		if absf(d[axis]) < 1e-6:
			if a[axis] < r.position[axis] or a[axis] >= r.end[axis]:
				return []
			continue
		var ta := (r.position[axis] - a[axis]) / d[axis]
		var tb := (r.end[axis] - a[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t1 - t0 < 0.01:
		return []
	return [a + d * t0, a + d * t1]


## The yard tower: a concrete shaft four storeys up to a glazed cab with its overhanging roof.
func _tower(p: Vector2) -> void:
	var base := CityChunk.SIDEWALK_TOP + Industrial.LIFT
	var g := ch._gy(p.x, p.y)
	if full:
		var conc := Color(0.78, 0.76, 0.72)
		Industrial._wbox(ch, Transform3D(Basis(), Vector3(p.x, base + g + 6.5, p.y)), Vector3(5.2, 13.0, 5.2), IndustrialKit.K_TILTUP, conc, 13.0)
		Industrial._wbox(ch, Transform3D(Basis(), Vector3(p.x, base + g + 13.2, p.y)), Vector3(7.6, 0.4, 7.6), IndustrialKit.K_STEEL, Color(0.3, 0.3, 0.31))
		Industrial._wbox(ch, Transform3D(Basis(), Vector3(p.x, base + g + 15.0, p.y)), Vector3(7.2, 3.2, 7.2), IndustrialKit.K_GLASS, Color(0.55, 0.6, 0.62))
		Industrial._wbox(ch, Transform3D(Basis(), Vector3(p.x, base + g + 16.8, p.y)), Vector3(8.6, 0.45, 8.6), IndustrialKit.K_STEEL, Color(0.32, 0.32, 0.33))
		# Antennas and the stair up the side.
		Industrial._wbox(ch, Transform3D(Basis(), Vector3(p.x + 2.5, base + g + 19.0, p.y - 2.5)), Vector3(0.1, 4.0, 0.1), IndustrialKit.K_GALV, Color(0.7, 0.7, 0.7))
		Industrial._wbox(ch, Transform3D(Basis(Vector3.RIGHT, -0.75), Vector3(p.x + 3.4, base + g + 6.5, p.y)), Vector3(1.2, 0.2, 16.0), IndustrialKit.K_GALV, Color(0.62, 0.63, 0.64))
		ch._add_shape(Vector3(7.6, 17.2, 7.6), Vector3(p.x, base + g + 8.6, p.y))
		kit.box(kit.body, Vector3(p.x, base + g + 11.0, p.y - 2.62), Vector3(1.6, 0, 0), Vector3.UP * 0.35, Vector3(0, 0, 0.01), FreewayKit.kind_color(Color(0.94, 0.94, 0.92), FreewayKit.S_PAINTED))
		kit._plate_text(FreightRail.MARK + " YARD", Vector3(p.x, base + g + 11.0, p.y - 2.64), Vector3(0, 0, -1), 0.4)
	else:
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(5.2, 13.0, 5.2)), Vector3(p.x, base + 6.5, p.y)), Color(0.78, 0.76, 0.72), Color(0.0, 0.0, 0.0, 1.0))
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(7.2, 3.6, 7.2)), Vector3(p.x, base + 15.0, p.y)), Color(0.4, 0.45, 0.48), Color(0.0, 0.0, 0.0, 1.0))


## A high mast: a tapered pole MAST_H up, a ring with eight floodlights (lit at night), a pool of
## light under it; at FULL a real light on every other one.
func _mast(p: Vector2) -> void:
	var base := CityChunk.SIDEWALK_TOP + Industrial.LIFT
	var g := ch._gy(p.x, p.y)
	if not full:
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(0.7, MAST_H, 0.7)), Vector3(p.x, base + MAST_H * 0.5, p.y)), Color(0.6, 0.62, 0.63), Color(0.0, 0.0, 0.0, 1.0))
		Industrial._pool(ch, Vector3(p.x, 0.0, p.y), 70.0, Color(1.0, 0.85, 0.6), 1.0)
		return
	var top := Vector3(p.x, base + g + MAST_H, p.y)
	kit.prism(kit.body, Vector3(p.x, base + g, p.y), top, 0.42, 0.2, 10, FreewayKit.kind_color(Color(0.62, 0.64, 0.65), FreewayKit.S_STEEL))
	kit.box(kit.body, Vector3(p.x, base + g + 0.4, p.y), Vector3(0.7, 0, 0), Vector3.UP * 0.4, Vector3(0, 0, 0.7), FreewayKit.kind_color(Color(0.7, 0.69, 0.66), FreewayKit.S_CONCRETE))
	kit.prism(kit.body, top - Vector3(0, 0.3, 0), top + Vector3(0, 0.1, 0), 1.6, 1.6, 12, FreewayKit.kind_color(Color(0.5, 0.52, 0.53), FreewayKit.S_STEEL))
	for k in 8:
		var a := TAU * float(k) / 8.0 + 0.2
		var d := Vector3(cos(a), 0.0, sin(a))
		var lc := top + d * 1.45 - Vector3(0, 0.6, 0)
		kit.box(kit.body, lc, d * 0.32, Vector3.UP * 0.25, d.cross(Vector3.UP) * 0.38, FreewayKit.kind_color(Color(0.28, 0.29, 0.3), FreewayKit.S_PAINTED))
		kit.box(kit.body, lc + d * 0.12 - Vector3(0, 0.26, 0), d * 0.22, Vector3.UP * 0.01, d.cross(Vector3.UP) * 0.3, FreewayKit.kind_color(Color(1.0, 0.86, 0.62), FreewayKit.S_LENS), 1.0, false)
	Industrial._pool(ch, Vector3(p.x, 0.0, p.y), 72.0, Color(1.0, 0.85, 0.6), 1.0)
	ch._add_shape(Vector3(0.8, MAST_H, 0.8), Vector3(p.x, base + g + MAST_H * 0.5, p.y))
	if absi(hash([plan.seed, "fy_light", int(p.x), int(p.y)])) % 2 == 0:
		var l := OmniLight3D.new()
		l.name = "YardMast"
		l.position = Vector3(p.x, base + g + MAST_H - 1.0, p.y)
		l.omni_range = 75.0
		l.omni_attenuation = 1.2
		l.light_color = Color(1.0, 0.86, 0.66)
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 260.0
		l.distance_fade_length = 60.0
		l.add_to_group("lamp_light")
		ch.add_child(l)


## The truck gate on the east side: a canopy over the lanes on four columns, booths between.
func _gate(r: Rect2) -> void:
	var base := CityChunk.SIDEWALK_TOP + Industrial.LIFT
	var c := r.get_center()
	var g := ch._gy(c.x, c.y)
	var x0 := r.position.x - 20.0
	for k in 4:
		var z := r.position.y + 2.0 + float(k) * (r.size.y - 4.0) / 3.0
		Industrial._wbox(ch, Transform3D(Basis(), Vector3(x0 + 2.0, base + g + 3.4, z)), Vector3(0.5, 6.8, 0.5), IndustrialKit.K_GALV, Color(0.66, 0.67, 0.68))
		Industrial._wbox(ch, Transform3D(Basis(), Vector3(x0 + 14.0, base + g + 3.4, z)), Vector3(0.5, 6.8, 0.5), IndustrialKit.K_GALV, Color(0.66, 0.67, 0.68))
	Industrial._wbox(ch, Transform3D(Basis(), Vector3(x0 + 8.0, base + g + 7.0, c.y)), Vector3(15.0, 0.6, r.size.y), IndustrialKit.K_STEEL, Color(0.85, 0.85, 0.83))
	for k in 3:
		var z := r.position.y + 7.0 + float(k) * 11.0
		Industrial._wbox(ch, Transform3D(Basis(), Vector3(x0 + 8.0, base + g + 1.3, z)), Vector3(2.0, 2.6, 2.4), IndustrialKit.K_GLASS, Color(0.7, 0.72, 0.72))
		ch._add_shape(Vector3(2.0, 2.6, 2.4), Vector3(x0 + 8.0, base + g + 1.3, z))


## The far city's yard (capture): the cars as long boxes per track, the stacks, the tower.
func _far() -> void:
	_cars_step()
	_works_step()
