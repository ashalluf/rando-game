class_name Arroyos
extends RefCounted
## Dry creek beds (arroyos) in the canyon floors of the ranges: a sandy, cobbled wash winding down
## every major gully, boulders along it, willows and sycamores on its banks, and a culvert where a
## hill road crosses it.
##
## WHERE is worked out, never placed. The network is the land's own drainage: the natural
## mountains (MacroMap.raw_height_at(), no road carving) sampled on a CELL grid over every range
## (a coarse PRESCAN finds them), D8 flow routing on it, the upstream area summed down the flow
## (Kahn order, no sort), and every cell draining at least MIN_CATCH cells a channel. Channels
## are traced head to junction into polylines, rounded (Chaikin), resampled every STEP metres and,
## a point at a time as chunks ask, SNAPPED across to the lowest ground within SNAP_REACH of the
## coarse line (offsets smoothed along the line), so the wash lies in the real gully floor of the
## 4-6 m terrain tile, not on the 32 m grid. Everything is a pure function of the seed's map: two
## chunks compute the same points along their shared edge, so a wash is continuous chunk to chunk.
##
## The network is built a slice at a time (build_step(), BUILD_BUDGET_US a call) the first time a
## hill chunk asks, and kept in LoadCache across launches. `ARROYOS=0` in the environment turns
## the whole thing off (the A/B).

static var enabled: bool = OS.get_environment("ARROYOS") != "0"

## The flow grid's cell, metres.
const CELL := 32.0
## The prescan's cell (a multiple of CELL): where the ranges are at all.
const PRESCAN := 128.0
## The prescan's extent, world metres (x0, z0, x1, z1): the whole map the streamer can reach.
const EXTENT := Rect2(-8192.0, -8192.0, 16384.0, 16384.0)
## Raw mountain height that counts as a range (MacroMap.zone_at() says HILLS from 3 m).
const HILL_MIN := 3.0
## Cells of catchment that make a wash (32 m cells: 90 is 9.2 hectares).
const MIN_CATCH := 60
## The least fall (metres per metre) a channel cell needs to carry a wash.
const MIN_FALL := 0.025
## Metres a line may stand over the lowest ground it has reached before it stops being a wash.
const RISE := 2.5
## Metres between resampled line points.
const STEP := 4.0
## How far across the coarse line the snap looks for the floor, and its sample spacing.
const SNAP_REACH := 22.0
const SNAP_SAMPLES := 12
## Points either side the snapped offsets are averaged over.
const SNAP_SMOOTH := 3
## Wash width (bed, metres) at MIN_CATCH and how it grows per doubling of catchment, capped.
const WIDTH_MIN := 2.6
const WIDTH_PER_DOUBLING := 1.25
const WIDTH_MAX := 9.0
## Microseconds of network building a call.
const BUILD_BUDGET_US := 4000
## Bucket size of the line index, metres.
const BUCKET := 256.0
## The flood's height bucket, metres.
const FLOOD_BUCKET := 0.25

## Built networks by MacroMap instance id.
static var _nets: Dictionary = {}
## The probe keeps the catchments (Net.acc).
static var keep_debug: bool = false


class Net:
	var seed: int = 0
	var macro: MacroMap
	var phase: int = 0
	var row: int = 0
	## Prescan mask (bytes, 1 where a range is within a prescan cell or its neighbours).
	var pn := Vector2i.ZERO
	var pmask := PackedByteArray()
	## The flow grid.
	var origin := Vector2.ZERO
	var n := Vector2i.ZERO
	var heights := PackedFloat32Array()
	## The lines: each {"pts": PackedVector2Array (unsnapped), "w": PackedFloat32Array (bed
	## width per point), "id": int}.
	var lines: Array = []
	## Bucket -> PackedInt32Array of (line << 16 | point index) for every point.
	var index: Dictionary = {}
	## Snapped offsets: line id -> PackedFloat32Array (NAN until computed).
	var raw_off: Dictionary = {}
	var done: bool = false
	## Range cells in the flow grid (the probe prints it).
	var sampled: int = 0
	## The catchment per flow cell, kept only for the probe (keep_debug).
	var acc := PackedInt32Array()


## The network for `plan`, or null while it is being built (call build_step()) or when off.
static func of(plan: CityPlan) -> Net:
	if not enabled or plan == null or plan.macro == null:
		return null
	var net: Net = _nets.get(plan.macro.get_instance_id())
	return net if net != null and net.done else null


## Builds the network for `plan` a slice at a time; true once it is done (or off).
static func build_step(plan: CityPlan) -> bool:
	if not enabled or plan == null or plan.macro == null:
		return true
	var key := plan.macro.get_instance_id()
	var net: Net = _nets.get(key)
	if net == null:
		net = Net.new()
		net.seed = plan.seed
		net.macro = plan.macro
		_nets[key] = net
		if _load_cached(net):
			return true
	if net.done:
		return true
	var t0 := Time.get_ticks_usec()
	while not net.done and Time.get_ticks_usec() - t0 < BUILD_BUDGET_US:
		_advance(net)
	return net.done


## Builds it whole (tests, probes, the loading screen).
static func build_now(plan: CityPlan) -> Net:
	while not build_step(plan):
		pass
	return of(plan)


static func _cache_inputs(net: Net) -> Array:
	return [net.seed, CELL, PRESCAN, MIN_CATCH, STEP, HILL_MIN, MIN_FALL, RISE, 2]


static func _load_cached(net: Net) -> bool:
	if not LoadCache.enabled():
		return false
	var data: Variant = LoadCache.load_data("arroyos", _cache_inputs(net))
	if not (data is Dictionary) or not data.has("lines"):
		return false
	net.origin = data.origin
	net.n = data.n
	net.heights = data.heights
	for l: Dictionary in data.lines:
		net.lines.append({"pts": l.pts, "w": l.w, "id": net.lines.size()})
	_index(net)
	net.done = true
	return true


static func _save_cached(net: Net) -> void:
	if not LoadCache.enabled():
		return
	var lines: Array = []
	for l: Dictionary in net.lines:
		lines.append({"pts": l.pts, "w": l.w})
	LoadCache.save_data("arroyos", _cache_inputs(net), {"origin": net.origin, "n": net.n, "heights": net.heights, "lines": lines})


static func _advance(net: Net) -> void:
	var m := net.macro
	match net.phase:
		0:
			# The prescan: one raw height a PRESCAN cell, a row a call.
			if net.pn == Vector2i.ZERO:
				net.pn = Vector2i(int(EXTENT.size.x / PRESCAN), int(EXTENT.size.y / PRESCAN))
				net.pmask.resize(net.pn.x * net.pn.y)
				net.pmask.fill(0)
			var j := net.row
			for i in net.pn.x:
				var p := EXTENT.position + Vector2((i + 0.5) * PRESCAN, (j + 0.5) * PRESCAN)
				if m.raw_height_at(p) > HILL_MIN:
					net.pmask[j * net.pn.x + i] = 1
			net.row += 1
			if net.row >= net.pn.y:
				_bound(net)
				net.phase = 1
				net.row = 0
		1:
			# The flow grid, a row a call, only near the ranges (-1 elsewhere: an outlet).
			var j := net.row
			for i in net.n.x:
				var p := net.origin + Vector2((i + 0.5) * CELL, (j + 0.5) * CELL)
				var pi := int((p.x - EXTENT.position.x) / PRESCAN)
				var pj := int((p.y - EXTENT.position.y) / PRESCAN)
				var near := false
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var qi := pi + di
						var qj := pj + dj
						if qi >= 0 and qj >= 0 and qi < net.pn.x and qj < net.pn.y and net.pmask[qj * net.pn.x + qi] == 1:
							near = true
				var h := -1.0
				if near:
					h = m.raw_height_at(p)
					if h <= HILL_MIN:
						h = -1.0
					elif m.reservoir and m.reservoir.wet(p):
						h = -1.0
				net.heights[j * net.n.x + i] = h
			net.row += 1
			if net.row >= net.n.y:
				net.phase = 2
		2:
			_route(net)
			_index(net)
			net.done = true
			net.pmask = PackedByteArray()
			_save_cached(net)


## The flow grid's bounds: the prescan's ranges grown by a prescan cell.
static func _bound(net: Net) -> void:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for j in net.pn.y:
		for i in net.pn.x:
			if net.pmask[j * net.pn.x + i] == 1:
				lo = Vector2i(mini(lo.x, i), mini(lo.y, j))
				hi = Vector2i(maxi(hi.x, i), maxi(hi.y, j))
	if hi.x < 0:
		net.n = Vector2i(1, 1)
		net.origin = EXTENT.position
		net.heights.resize(1)
		net.phase = 2
		return
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	net.origin = EXTENT.position + Vector2(lo) * PRESCAN
	var r := int(PRESCAN / CELL)
	net.n = (hi - lo + Vector2i.ONE) * r
	net.heights.resize(net.n.x * net.n.y)


const _D8 := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]


## Flow, catchments, then the lines. The flow is a priority flood (Barnes et al.) from the
## range's edge inward on a bucket queue (FLOOD_BUCKET metres a bucket, FIFO inside one): each
## cell drains to the neighbour it was reached from, so the eroded ranges' little pits (a 32 m
## grid over 110 m gullies has many) fill and spill instead of swallowing the flow, and every
## cell reaches the foot. Catchments summed down the flow in Kahn order, no sort.
static func _route(net: Net) -> void:
	var nx := net.n.x
	var nz := net.n.y
	var count := nx * nz
	var hs := net.heights
	var down := PackedInt32Array()
	down.resize(count)
	down.fill(-1)
	var seen := PackedByteArray()
	seen.resize(count)
	# Plain Arrays: a PackedInt32Array kept in an Array is a value, so appending to buckets[b]
	# appended to a copy.
	var buckets: Array[Array] = []
	var push := func(k: int, h: float) -> void:
		var b := maxi(int(h / FLOOD_BUCKET), 0)
		while buckets.size() <= b:
			buckets.append([])
		buckets[b].append(k)
	# The edge: every range cell next to a non-range cell (or the grid's edge) drains off it.
	for j in nz:
		for i in nx:
			var k := j * nx + i
			if hs[k] < 0.0:
				continue
			var edge := i == 0 or j == 0 or i == nx - 1 or j == nz - 1
			if not edge:
				for d: Vector2i in _D8:
					if hs[(j + d.y) * nx + i + d.x] < 0.0:
						edge = true
						break
			if edge:
				seen[k] = 1
				down[k] = -2
				push.call(k, hs[k])
	var fill := hs.duplicate()
	var b := 0
	while b < buckets.size():
		var at := 0
		while at < buckets[b].size():
			var c: int = buckets[b][at]
			at += 1
			var ci := c % nx
			var cj := c / nx
			for d: Vector2i in _D8:
				var qi := ci + d.x
				var qj := cj + d.y
				if qi < 0 or qj < 0 or qi >= nx or qj >= nz:
					continue
				var q := qj * nx + qi
				if seen[q] == 1 or hs[q] < 0.0:
					continue
				seen[q] = 1
				down[q] = c
				fill[q] = maxf(hs[q], fill[c])
				push.call(q, fill[q])
		buckets[b] = []
		b += 1
	var indeg := PackedInt32Array()
	indeg.resize(count)
	for k in count:
		if down[k] >= 0:
			indeg[down[k]] += 1
	var acc := PackedInt32Array()
	acc.resize(count)
	var queue := PackedInt32Array()
	for k in count:
		if hs[k] >= 0.0:
			acc[k] = 1
			if indeg[k] == 0:
				queue.append(k)
	var qi2 := 0
	while qi2 < queue.size():
		var k := queue[qi2]
		qi2 += 1
		var t := down[k]
		if t >= 0:
			acc[t] += acc[k]
			indeg[t] -= 1
			if indeg[t] == 0:
				queue.append(t)
	# Channel cells, and how many channel cells drain into each.
	var up_ch := PackedInt32Array()
	up_ch.resize(count)
	for k in count:
		if acc[k] >= MIN_CATCH and down[k] >= 0:
			up_ch[down[k]] += 1
	var traced := PackedByteArray()
	traced.resize(count)
	for k in count:
		if acc[k] < MIN_CATCH or up_ch[k] != 0 or hs[k] < 0.0:
			continue
		# A head: follow it down until it runs off the range or meets a line already traced
		# (whose cell ends this one: the junction).
		var cells := PackedInt32Array()
		var c := k
		while true:
			cells.append(c)
			if traced[c] == 1:
				break
			traced[c] = 1
			var t := down[c]
			if t < 0:
				break
			c = t
		_add_line(net, cells, acc, down, fill)
	if keep_debug:
		net.acc = acc
	net.sampled = 0
	for k in count:
		if hs[k] >= 0.0:
			net.sampled += 1


static func _cell_pos(net: Net, k: int) -> Vector2:
	return net.origin + Vector2((k % net.n.x + 0.5) * CELL, (k / net.n.x + 0.5) * CELL)


static func _add_line(net: Net, cells: PackedInt32Array, acc: PackedInt32Array, down: PackedInt32Array, fill: PackedFloat32Array) -> void:
	if cells.size() < 3:
		return
	var pts := PackedVector2Array()
	var ws := PackedFloat32Array()
	for k in cells:
		pts.append(_cell_pos(net, k))
		# No wash across a filled pit (the flood's own flat) or ground with next to no fall: the
		# flow is the flood's, not a gully's, there. Width 0 marks a gap.
		var h := net.heights[k]
		var t := down[k]
		var fall := 0.0
		if t >= 0:
			fall = (h - net.heights[t]) / _cell_pos(net, k).distance_to(_cell_pos(net, t))
		var ok := fill[k] <= h + 0.3 and (t < 0 or fall > MIN_FALL)
		ws.append(acc[k] if ok else 0.0)
	# A line that ran off the range carries on half a cell to the foot.
	var last := cells[cells.size() - 1]
	if down[last] == -2:
		pts.append(pts[pts.size() - 1] + (pts[pts.size() - 1] - pts[pts.size() - 2]) * 0.5)
		ws.append(ws[ws.size() - 1])
	# Round the 45-degree zig-zags (Chaikin, ends kept), then every STEP metres.
	for it in 3:
		var np := PackedVector2Array([pts[0]])
		var nw := PackedFloat32Array([ws[0]])
		for i in pts.size() - 1:
			np.append(pts[i].lerp(pts[i + 1], 0.25))
			np.append(pts[i].lerp(pts[i + 1], 0.75))
			nw.append(lerpf(ws[i], ws[i + 1], 0.25))
			nw.append(lerpf(ws[i], ws[i + 1], 0.75))
		np.append(pts[pts.size() - 1])
		nw.append(ws[ws.size() - 1])
		pts = np
		ws = nw
	var out := PackedVector2Array()
	var wo := PackedFloat32Array()
	var carry := 0.0
	out.append(pts[0])
	wo.append(_width(ws[0]))
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var l := a.distance_to(b)
		var s := STEP - carry
		while s <= l:
			out.append(a.lerp(b, s / l))
			wo.append(_width(lerpf(ws[i], ws[i + 1], s / l)))
			s += STEP
		carry = l - (s - STEP)
	if out.size() < 3:
		return
	# Never uphill: a point standing RISE metres over the lowest ground the line has reached is no
	# wash (a flood path over a saddle, or onto the grid's edge).
	var low := INF
	for i in out.size():
		var h := _grid_height(net, out[i])
		if h > low + RISE:
			wo[i] = 0.0
		low = minf(low, h)
	net.lines.append({"pts": out, "w": wo, "id": net.lines.size()})


## The flow grid's height at `p`, bilinear (range cells only; others count as the cell's own).
static func _grid_height(net: Net, p: Vector2) -> float:
	var g := (p - net.origin) / CELL - Vector2(0.5, 0.5)
	var i := clampi(floori(g.x), 0, net.n.x - 2)
	var j := clampi(floori(g.y), 0, net.n.y - 2)
	var fx := clampf(g.x - i, 0.0, 1.0)
	var fy := clampf(g.y - j, 0.0, 1.0)
	var k := j * net.n.x + i
	var h00 := net.heights[k]
	var h10 := net.heights[k + 1] if net.heights[k + 1] >= 0.0 else h00
	var h01 := net.heights[k + net.n.x] if net.heights[k + net.n.x] >= 0.0 else h00
	var h11 := net.heights[k + net.n.x + 1] if net.heights[k + net.n.x + 1] >= 0.0 else h00
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)


static func _width(cells: float) -> float:
	if cells < MIN_CATCH * 0.5:
		return 0.0
	return minf(WIDTH_MIN + WIDTH_PER_DOUBLING * log(maxf(cells, 1.0) / MIN_CATCH) / log(2.0), WIDTH_MAX)


static func _index(net: Net) -> void:
	net.index = {}
	for li in net.lines.size():
		var pts: PackedVector2Array = net.lines[li].pts
		for pi in pts.size():
			var key := Vector2i(floori(pts[pi].x / BUCKET), floori(pts[pi].y / BUCKET))
			if not net.index.has(key):
				net.index[key] = PackedInt32Array()
			var arr: PackedInt32Array = net.index[key]
			arr.append((li << 16) | pi)
			net.index[key] = arr


## Line point refs (li << 16 | pi) whose unsnapped point is within `rect` grown by `margin`.
static func refs_in(net: Net, rect: Rect2, margin: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var g := rect.grow(margin)
	for bx in range(floori(g.position.x / BUCKET), floori(g.end.x / BUCKET) + 1):
		for bz in range(floori(g.position.y / BUCKET), floori(g.end.y / BUCKET) + 1):
			var arr: Variant = net.index.get(Vector2i(bx, bz))
			if arr == null:
				continue
			for r: int in arr:
				var p: Vector2 = net.lines[r >> 16].pts[r & 0xffff]
				if g.has_point(p):
					out.append(r)
	return out


## The ground at `p` before any carving (hill roads, pads, the ballpark): the mountains plus the
## city's relief. Where height_at() differs from it the ground has been graded.
static func uncarved(plan: CityPlan, p: Vector2) -> float:
	var raw := plan.macro.raw_height_at(p)
	return raw + plan.macro._relief_at(p, raw)


## Whether `p`'s ground is the land's own (not a road bed, bank, pad or cut), within `tol` metres.
static func natural(plan: CityPlan, p: Vector2, tol: float) -> bool:
	return absf(plan.height_at(p) - uncarved(plan, p)) < tol


# --- Snapping ---------------------------------------------------------------------------------

static func _normal(pts: PackedVector2Array, i: int) -> Vector2:
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var d := (b - a).normalized()
	return Vector2(-d.y, d.x)


## The raw (unsmoothed) snap offset of line `li`'s point `pi`, computing it if needed: the lowest
## natural ground across the line within SNAP_REACH (a parabola through the best three samples).
static func raw_offset(net: Net, li: int, pi: int) -> float:
	var arr: PackedFloat32Array
	if net.raw_off.has(li):
		arr = net.raw_off[li]
	else:
		arr = PackedFloat32Array()
		arr.resize((net.lines[li].pts as PackedVector2Array).size())
		arr.fill(NAN)
	if not is_nan(arr[pi]):
		return arr[pi]
	var pts: PackedVector2Array = net.lines[li].pts
	var p := pts[pi]
	var nrm := _normal(pts, pi)
	var step := 2.0 * SNAP_REACH / SNAP_SAMPLES
	var best := 0
	var hs := PackedFloat32Array()
	for k in SNAP_SAMPLES + 1:
		var o := -SNAP_REACH + k * step
		# A gentle pull to the coarse line, so a flat floor does not wander bank to bank.
		var h := net.macro.raw_height_at(p + nrm * o) + absf(o) * 0.04
		hs.append(h)
		if h < hs[best]:
			best = k
	var off := -SNAP_REACH + best * step
	if best > 0 and best < SNAP_SAMPLES:
		var a := hs[best - 1]
		var b := hs[best]
		var c := hs[best + 1]
		var den := a - 2.0 * b + c
		if den > 0.0001:
			off += clampf(0.5 * (a - c) / den, -0.5, 0.5) * step
	arr[pi] = off
	net.raw_off[li] = arr
	return off


## Whether raw_offset() of a point is already known (for budgeted callers).
static func has_raw(net: Net, li: int, pi: int) -> bool:
	return net.raw_off.has(li) and not is_nan((net.raw_off[li] as PackedFloat32Array)[pi])


## Line `li`'s point `pi` snapped into the floor: the raw offsets averaged over SNAP_SMOOTH
## points either side (computing any missing).
static func snapped(net: Net, li: int, pi: int) -> Vector2:
	var pts: PackedVector2Array = net.lines[li].pts
	var sum := 0.0
	var wsum := 0.0
	for d in range(-SNAP_SMOOTH, SNAP_SMOOTH + 1):
		var q := pi + d
		if q < 0 or q >= pts.size():
			continue
		var w := 1.0 - absf(d) / float(SNAP_SMOOTH + 1)
		sum += raw_offset(net, li, q) * w
		wsum += w
	return pts[pi] + _normal(pts, pi) * (sum / wsum)
