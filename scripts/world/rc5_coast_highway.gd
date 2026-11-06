class_name Rc5CoastHighway
extends RefCounted
## The coast highway refcam (wave 8, `coast_highway` in tools/refcams/cameras_w8.json; docs/HANDOFF.md
## "The coast highway at 17:00 from the seawall"). What the view from the apron gave away, fixed in
## order of where the eye lands:
##
## - The bluff was one smooth plane: CoastHighway.profile() cuts it at 1.5:1 and HillRoads' carve
##   holds the lower part to a 1:1 bank, so from the road the cliff was a sculpted wall of sand.
##   Real bluffs over a coast road are FLUTED: rain cuts gullies straight down the face every
##   10-25 m, the spurs between them stand proud and the gullies fan out at the toe. `flute()`
##   (CoastFlutes, applied after the carve in MacroMap.height_at(), so the tiles, collision,
##   planting and far ground all follow) lowers the face along hashed gullies that deepen with
##   height and wander a little sideways as they climb. Pure: hashes of seed + place.
## - The road was empty: CoastTraffic spawned only 160-380 m from the player, six a direction, so
##   the stretch in sight held no moving car. `wanted()` sets the cars a direction by the hour (the
##   evening rush is twice the old count), and `fill_slots()` lays the first fill over the whole
##   reach, the near road included (the loading shade is still up, as FirstFill does for the city).
## - The houses' street side was bare stucco and a cartoon garage door; see CoastStreetDress.
##
## `RC5_COAST=0` in the environment turns all of it off (the A/B: the coast highway as before).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_COAST") != "0"

# --- Traffic ------------------------------------------------------------------------------------

## Cars wanted each way at `hour`: the evening rush about three times the old count, the small hours a few.
static func wanted(base: int, hour: float) -> int:
	if not enabled:
		return base
	return clampi(roundi(float(base) * 3.4 * NightCity.traffic_level(hour)), 2, base * 4)


## The first fill: where each direction's cars go, metres of road from the player's z, spread over
## the whole reach (the near road too: the loading shade is up), at least `gap` apart in a lane.
## Returns [s, lane] pairs; a hash of seed + direction + slot, so a load always starts the same.
static func fill_slots(sd: int, dir: int, n: int, ps: float, reach: float, s_lo: float, s_hi: float, gap: float) -> Array:
	var out := []
	var taken := {0: [], 1: []}
	var k := 0
	while out.size() < n and k < n * 6:
		var r := float(absi(hash([sd, "coast_fill", dir, k])) % 100003) / 100003.0
		var lane := absi(hash([sd, "coast_fill_lane", dir, k])) % 2
		k += 1
		var s := ps + lerpf(-reach, reach, r)
		# Never on the player's own spot (he may stand on the road).
		if s < s_lo or s > s_hi or absf(s - ps) < 12.0:
			continue
		var ok := true
		for o: float in taken[lane]:
			if absf(o - s) < gap:
				ok = false
				break
		if not ok:
			continue
		(taken[lane] as Array).append(s)
		out.append([s, lane])
	return out


# --- The houses' street side --------------------------------------------------------------------

## A garage door as a real door (CoastHighwayBuild._wall_holes()): over a dark backing, either
## horizontal slats with shadow gaps (a timber or dark leaf: the modern beach house's door) or four
## sectional panels, each with a raised inner field. Returns false (the old painted leaf) when off.
static func garage_door(g: CoastHighwayBuild.Geo, P: Callable, b: Basis, x0: float, x1: float, y0: float, y1: float, rz: float, n: Vector3, nsign: float, leaf: Color, sd: int) -> bool:
	if not enabled:
		return false
	var xc := (x0 + x1) * 0.5
	var hw := (x1 - x0) * 0.5
	# The dark recess behind the leaf, seen through the gaps.
	g.quad("h_dark", P.call(x0, y0, rz - 0.03 * nsign), P.call(x1, y0, rz - 0.03 * nsign), P.call(x1, y1, rz - 0.03 * nsign), P.call(x0, y1, rz - 0.03 * nsign), n, Color(0.05, 0.05, 0.05))
	var lum := leaf.r * 0.3 + leaf.g * 0.59 + leaf.b * 0.11
	if lum < 0.7:
		# Slats: 11 cm boards on 13.5 cm centres, each a shade of its own.
		var pitch := 0.135
		var count := maxi(4, int((y1 - y0 - 0.02) / pitch))
		var p2 := (y1 - y0) / float(count)
		for k in count:
			var t := float(absi(hash([sd, "slat", k])) % 1000) / 1000.0
			var col := leaf.lerp(leaf * 1.18, t * 0.6)
			col.a = 1.0
			var yc := y0 + (float(k) + 0.5) * p2
			g.box("h_door", Transform3D(b, P.call(xc, yc, rz + 0.012 * nsign)), Vector3(hw - 0.01, p2 * 0.41, 0.014), col)
	else:
		# Four sections, 1.5 cm joints, a raised field in each.
		var sec := (y1 - y0) / 4.0
		for k in 4:
			var yc := y0 + (float(k) + 0.5) * sec
			g.box("h_door", Transform3D(b, P.call(xc, yc, rz + 0.01 * nsign)), Vector3(hw - 0.01, sec * 0.5 - 0.008, 0.02), leaf)
			var cols := maxi(2, int((x1 - x0) / 1.25))
			for j in cols:
				var cx := lerpf(x0 + 0.12, x1 - 0.12, (float(j) + 0.5) / float(cols))
				var fw := ((x1 - x0) - 0.24) / float(cols) * 0.5 - 0.06
				g.box("h_door", Transform3D(b, P.call(cx, yc, rz + 0.034 * nsign)), Vector3(fw, sec * 0.5 - 0.1, 0.006), leaf * 1.04)
	return true


## The street side of one beach house (CoastHighwayBuild._house()): a stucco planter along the
## wall wherever the garage, the door and the bins leave room, planted with agave and bird of
## paradise; a palm by most houses' corner; a lantern either side of the garage.
static func dress_house(chunk: CityChunk, c: CoastHighway, g: CoastHighwayBuild.Geo, hs: Dictionary, wall_col: Color) -> void:
	if not enabled or chunk.level != CityChunk.Level.FULL or chunk.capturing:
		return
	var xf := CoastHighwayBuild._frame(c, hs)
	var b := xf.basis
	var o := xf.origin
	var P := func(x: float, y: float, z: float) -> Vector3: return o + b.x * x + Vector3.UP * y + b.z * z
	var zc := float(hs.zc)
	var w := float(hs.z1) - float(hs.z0)
	var hw := w * 0.5
	var y := c.road_y(zc) + 0.02
	var street := -b.z
	# What the planter must keep off: the garage, the door, the bins (as CoastHighwayBuild lays them).
	var keep: Array = []
	var gz := 0.0
	if bool(hs.garage) and w > 7.0:
		gz = c.garage_z(hs) - zc
		keep.append([gz - 1.8, gz + 1.8])
		var dx := gz + (2.6 if gz < 0.0 else -2.6)
		keep.append([dx - 0.9, dx + 0.9])
		for sx: float in [-1.0, 1.0]:
			# Lanterns either side of the garage door.
			var lx := gz + sx * 1.85
			g.box("h_metal", Transform3D(b, P.call(lx, y + 2.15, -0.06)), Vector3(0.08, 0.16, 0.06), Color(0.12, 0.12, 0.12))
			g.box("h_trim", Transform3D(b, P.call(lx, y + 2.15, -0.12)), Vector3(0.06, 0.11, 0.005), Color(0.95, 0.90, 0.78))
	else:
		keep.append([-1.0, 1.0])
	# The bins, where CoastHighwayBuild._fences_and_bins() stands them.
	if c.h01(["bins", int(hs.key)]) < 0.6:
		var bg := (c.garage_z(hs) if bool(hs.garage) else zc) - zc
		var bs := 1.0 if bg < 0.0 else -1.0
		keep.append([minf(bg + bs * 1.6, bg + bs * 3.3), maxf(bg + bs * 1.6, bg + bs * 3.3)])
	# The free runs of the wall.
	var runs: Array = [[-hw + 0.25, hw - 0.25]]
	for k: Array in keep:
		var next: Array = []
		for r: Array in runs:
			if float(k[1]) <= float(r[0]) or float(k[0]) >= float(r[1]):
				next.append(r)
				continue
			if float(k[0]) > float(r[0]):
				next.append([r[0], k[0]])
			if float(k[1]) < float(r[1]):
				next.append([k[1], r[1]])
		runs = next
	var planter_col := Color(wall_col.r, wall_col.g, wall_col.b, 1.0) if int(hs.style) in [CoastHighway.Style.WHITE, CoastHighway.Style.STUCCO] else Color(0.74, 0.72, 0.68)
	var depth := 0.62
	var height := 0.5
	var k := 0
	for r: Array in runs:
		var a := float(r[0])
		var e := float(r[1])
		if e - a < 1.1:
			continue
		var mid := (a + e) * 0.5
		var half := (e - a) * 0.5
		g.box("h_wall", Transform3D(b, P.call(mid, y + height * 0.5, -depth * 0.5 - 0.02)), Vector3(half, height * 0.5, depth * 0.5), planter_col, 63 & ~(1 << 3))
		# Soil a little under the rim, mulched dark.
		g.quad("h_dark", P.call(a + 0.06, y + height - 0.06, -0.08), P.call(e - 0.06, y + height - 0.06, -0.08), P.call(e - 0.06, y + height - 0.06, -depth + 0.04), P.call(a + 0.06, y + height - 0.06, -depth + 0.04), Vector3.UP, Color(0.16, 0.12, 0.09))
		g.boxes.append([Transform3D(b, P.call(mid, y + height * 0.5, -depth * 0.5)), Vector3(half, height * 0.5, depth * 0.5)])
		var plants := maxi(1, int((e - a) / 1.15))
		for j in plants:
			var px := lerpf(a, e, (float(j) + 0.5) / float(plants))
			var hsh := float(absi(hash([c.seed, "coast_plant", int(hs.key), k, j])) % 1000) / 1000.0
			var sp := LaTrees.Species.AGAVE if hsh < 0.45 else (LaTrees.Species.BIRD_OF_PARADISE if hsh < 0.85 else LaTrees.Species.YUCCA)
			var tall := LaTrees.height_at(sp, hsh * 2.0 - floorf(hsh * 2.0)) * 0.7
			var s := LaTrees.scale_for(sp, tall)
			var at: Vector3 = P.call(px, y + height - 0.06, -depth * 0.5 - 0.02)
			LaTrees._add(chunk, sp, int(hsh * 7.0) % 2, Transform3D(Basis(Vector3.UP, hsh * TAU).scaled(Vector3(s, s, s)), at), Color(1, 1, 1))
		k += 1
	# A palm at one corner of most houses, on the apron clear of the shoulder.
	var hp := float(absi(hash([c.seed, "coast_palm", int(hs.key)])) % 1000) / 1000.0
	if hp < 0.6:
		var px := (hw - 0.55) * (1.0 if hp < 0.3 else -1.0)
		var clear := true
		for kk: Array in keep:
			if px > float(kk[0]) - 0.6 and px < float(kk[1]) + 0.6:
				clear = false
		if clear:
			var v := int(hp * 1000.0) % PropFactory.PALM_VARIANTS
			var s := 0.85 + 0.3 * hp
			var at: Vector3 = P.call(px, y, -1.15)
			chunk._batch.add("palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, hp * 40.0).scaled(Vector3(s, s, s)), at), Color(1.0, 1.0, 0.96))
			chunk._add_shape(Vector3(0.5, 9.0 * s, 0.5), at + Vector3(0.0, 4.5 * s, 0.0))


## More glass on a house's side wall where it faces open beach or a wide gap (the end of a run):
## a tall corner window at the sea end and a second one by the street, as the real beach houses
## open their ends to the view. Appends to `holes` ([z0, y0, z1, y1, "window"] in the side wall's
## frame: z metres from the street face, out to `fz`, the storey's sea face).
static func side_windows(c: CoastHighway, hs: Dictionary, sx: float, fz: float, y0: float, y1: float, holes: Array) -> void:
	if not enabled:
		return
	var edge := float(hs.z1) if sx > 0.0 else float(hs.z0)
	if not c.house_at(edge + sx * 3.5, 0.0).is_empty():
		return
	if fz < 6.5:
		return
	for h: Array in holes:
		if float(h[2]) > fz - 2.8:
			return
	holes.append([fz - 2.6, y0 + 0.35, fz - 0.45, y1 - 0.45, "window"])
	var mid := fz * 0.22
	var clash := false
	for h: Array in holes:
		if mid + 1.2 > float(h[0]) - 0.3 and mid < float(h[2]) + 0.3:
			clash = true
	if not clash:
		holes.append([mid, y0 + 1.0, mid + 1.2, y0 + 2.3, "window"])


## The apron between the seawall and the road: poured slabs 2 m apart, more weathered (a beach
## road's concrete takes sand and salt), warmer than the old pale-blue tint.
static func apron_material() -> Material:
	return PropFactory.road("sidewalk", 3.0, Color(1.34, 1.29, 1.20), 7336, 2.0, 0.9)


## The seawall parapet's cap: a precast coping 6 cm proud of both faces with a drip under each
## edge and a softened top, instead of the bare slab edge (CoastHighwayBuild._sea_side()).
static func parapet_cap(c: CoastHighway, g: CoastHighwayBuild.Geo, w: float, t: float, z0: float, z1: float, top0: float, top1: float, sea3: Vector3) -> void:
	if not enabled:
		return
	var o := 0.06
	var hgt := 0.09
	var col := Color(0.92, 0.90, 0.86)
	var P := func(d: float, z: float, y: float) -> Vector3:
		var p := c.at(d, z)
		return Vector3(p.x, y, p.y)
	var a := w - o
	var e := w + t + o
	# Top, rounded off by two narrow chamfers at the edges.
	g.quad("wall", P.call(a + 0.04, z0, top0 + hgt), P.call(a + 0.04, z1, top1 + hgt), P.call(e - 0.04, z1, top1 + hgt), P.call(e - 0.04, z0, top0 + hgt), Vector3.UP, col)
	g.quad("wall", P.call(a, z0, top0 + hgt - 0.03), P.call(a, z1, top1 + hgt - 0.03), P.call(a + 0.04, z1, top1 + hgt), P.call(a + 0.04, z0, top0 + hgt), Vector3.UP + sea3, col)
	g.quad("wall", P.call(e - 0.04, z0, top0 + hgt), P.call(e - 0.04, z1, top1 + hgt), P.call(e, z1, top1 + hgt - 0.03), P.call(e, z0, top0 + hgt - 0.03), Vector3.UP - sea3, col)
	# Its two faces and the soffits under the overhang.
	g.quad("wall", P.call(a, z0, top0 - 0.01), P.call(a, z1, top1 - 0.01), P.call(a, z1, top1 + hgt - 0.03), P.call(a, z0, top0 + hgt - 0.03), sea3, col)
	g.quad("wall", P.call(e, z0, top0 - 0.01), P.call(e, z1, top1 - 0.01), P.call(e, z1, top1 + hgt - 0.03), P.call(e, z0, top0 + hgt - 0.03), -sea3, col)
	g.quad("wall", P.call(a, z0, top0 - 0.01), P.call(a, z1, top1 - 0.01), P.call(w, z1, top1 - 0.01), P.call(w, z0, top0 - 0.01), Vector3.DOWN, col.darkened(0.3))
	g.quad("wall", P.call(w + t, z0, top0 - 0.01), P.call(w + t, z1, top1 - 0.01), P.call(e, z1, top1 - 0.01), P.call(e, z0, top0 - 0.01), Vector3.DOWN, col.darkened(0.3))


## A northbound car standing at the head of the queue before the slide turns round and drives back
## south (the road is closed: that is what the cars there really do), when the southbound lane by
## it is clear. True when it turned (CoastTraffic._maintain() then keeps it).
static func u_turn(tr: CoastTraffic, car: Vehicle, close: float) -> bool:
	if not enabled:
		return false
	var t: Dictionary = car.traffic
	if float(t.s) > close + 4.5 or float(t.speed) > 0.5:
		return false
	var lane := 1
	for other: Vehicle in tr.cars:
		if other == car or not is_instance_valid(other) or not other.is_traffic():
			continue
		var ot: Dictionary = other.traffic
		if int(ot.dir) == 1 and int(ot.lane) == lane and absf(float(ot.s) - float(t.s)) < 25.0:
			return false
	t.dir = 1
	t.lane = lane
	t.speed = 0.0
	return true
