class_name FreewayStack
extends RefCounted
## The four-level stack where the 110 meets the 101 north-west of downtown (VISUAL_ROADMAP #59):
## the two main lines at levels 1 and 4 and the four directional LEFT-turn connectors at levels 2
## and 3, each a long sweeping curve on tall single columns with hammerheads, banked into the
## turn. This file is the PLAN (pure data, no nodes): Freeway.build() calls prepare() once the
## routes are drawn; StackBuild builds it, StackTraffic drives it.
##
## The heights are the whole problem. The 101 leaves the stack westward on its 2 km climb to the
## pass at the 7 % grade limit, so a connector tied to its west leg cannot get below it near the
## crossing, nor one tied to its east leg above it. So the plan holds both main lines LEVEL
## through a window round the crossing (raise only, the same relaxation as Freeway._clear_ground:
## the 101 at its own height at the window's west end, the 110 three deck separations under it),
## and every connector is then a profile solved between envelopes: tied to its parent and its
## target over the touch runs, over the 110 and under the 101 wherever their footprints overlap,
## over or under each connector it crosses (the two crossing sets are levels 2 and 3), and never
## steeper than GRADE. If that is not feasible (another seed's geometry) there is no stack and
## the two decks cross the old way (Freeway._separate_crossings()).
##
## A connector leaves its parent edge to edge (TOUCH: the parent's outer barrier is open there,
## open_edge(), so you can drive off), pulls away over TAPER, curves left on a circular arc of
## about RADIUS (a cubic Bezier through the tangent points) and comes back to its target the same
## way. Points every LINK_STEP; `pt` is the parent / target run distance in the leads.

const LINK_BASE := 100
const RADIUS := 165.0
const LINK_WIDTH := 11.8
const GAP := 8.0
const TOUCH := 24.0
const TAPER := 90.0
const LINK_STEP := 8.0
const GRADE := 0.07
## The envelopes allow a hair more: a connector touching a parent that climbs at the full 7 %
## runs a slightly shorter or longer path beside it.
const GRADE_SOLVE := 0.0735
const SLACK := 1.5
## Main lines are held level this far past the connectors' touch runs either side of the crossing.
const WINDOW_EXTRA := 40.0
## A leg of the low line shorter than this is a stub: it climbs away past the crossings.
const STUB_LEG := 400.0
const STUB_GRADE := 0.065
## Extra run beside the parent before the curve, on every leg but the 101's climbing one.
const EXT := 110.0
## Superelevation: bank = curvature * BANK_K, at most BANK_MAX.
const BANK_K := 8.0
const BANK_MAX := 0.07
## Single columns under the connectors.
const COLUMN_SPACING := 40.0
const COLUMN_R := 1.15
const MAIN_COLUMN_R := 1.6
## The connector's lanes across it (metres from its centre line, + to the right of travel):
## left edge line, the lane line, right edge line; two lanes.
const LANE_LEFT := -4.28
const LANE_W := 3.6
## Off-ramps and other clutter keep this far from the crossing.
const KEEP := 520.0
## Vertical separation where two connectors cross: their girders are 2 m deep, so this leaves
## 5 m of headroom (Caltrans' 16.5 ft); the main lines keep Freeway.DECK_SEPARATION.
const LINK_SEP := 7.0
## Connector girder depth (deeper than the main decks': longer spans on single columns).
const GIRDER := 2.0

var centre := Vector2.ZERO
var low := -1
var high := -1
var t_low := 0.0
var t_high := 0.0
var levels := PackedFloat32Array()
var links: Array[Dictionary] = []
## Vector2i(route, segment) -> side (+1 / -1) whose outer barrier is open (a connector touches it).
var open_edges := {}
## Vector2i(route, segment) of main-line segments with a deck over them (no light standard / gantry).
var covered := {}

## Which way along the high line (by run) it climbs away from the stack: +1, -1 or 0.
var climb_dir := 0
var _ext := 0.0
var _climb_ext := 0.0
var _fw: Freeway
var _macro: MacroMap
var _cols_done := false
var _columns: Array[Dictionary] = []
var _skip_bents := {}


# --- Planning ---------------------------------------------------------------------------------

## Plans the stack on `fw`'s routes (before _separate_crossings). Returns false (and changes
## nothing) when there is no stack to build.
func prepare(fw: Freeway, macro: MacroMap) -> bool:
	_fw = fw
	_macro = macro
	if OS.get_environment("STACK") == "0":
		return false
	for ri in fw.routes.size():
		var n: String = fw.routes[ri].name
		if n.contains("Harbor"):
			low = ri
		elif n.contains("Hollywood"):
			high = ri
	if low < 0 or high < 0:
		return false
	var want := DowntownReal.point("four_level_interchange")
	var hit := _crossing(fw.routes[low].points, fw.routes[high].points, want)
	if hit.is_empty():
		return false
	centre = hit[0]
	var run_l := _runs(fw.routes[low].points)
	var run_h := _runs(fw.routes[high].points)
	t_low = run_l[hit[1]] + (run_l[hit[1] + 1] - run_l[hit[1]]) * float(hit[2])
	t_high = run_h[hit[3]] + (run_h[hit[3] + 1] - run_h[hit[3]]) * float(hit[4])
	var sep := Freeway.DECK_SEPARATION
	var half_l: float = fw.routes[low].width * 0.5
	var half_h: float = fw.routes[high].width * 0.5
	var lead := RADIUS - (maxf(half_l, half_h) + LINK_WIDTH * 0.5 + GAP)
	# The main lines are held level through a window round the crossing, out past every touch
	# run, so each connector ties on to a level deck. The 101 climbs WEST to the pass at the
	# grade limit, so every metre of window on that side lifts the whole stack 7 cm: its
	# connectors there get as little extra run as solves. On every other leg a connector runs EXT further beside
	# its parent before it curves (and the window goes that much further), which is length it
	# needs to climb the stack's height and still cross its neighbours a deck apart. The first
	# extension and spread of levels that solves is the stack (STACK_DEBUG=1 prints the rest).
	var probe_a := line_at(fw.routes[high].points, fw.routes[high].heights, run_h, t_high + 300.0)[2] as float
	var probe_b := line_at(fw.routes[high].points, fw.routes[high].heights, run_h, t_high - 300.0)[2] as float
	climb_dir = 1 if probe_a > probe_b + 1.0 else (-1 if probe_b > probe_a + 1.0 else 0)
	var made: Array[Dictionary] = []
	var hl := PackedFloat32Array()
	var hh := PackedFloat32Array()
	var mains := {}
	for climb_ext: float in [0.0, 30.0, 60.0, 90.0]:
		for slack: float in [SLACK, SLACK + 1.5, SLACK + 3.0]:
			var ext := EXT
			var base := lead + TOUCH + TAPER + 12.0
			var w_low := Vector2(base + ext, base + ext)
			# A short leg of the low line (the 110's stub north of the stack) is held level only
			# over the crossings and then climbs away: its connectors tie on higher up, which
			# is the height they could not otherwise lose (or gain) on so short a run.
			var len_l: float = run_l[run_l.size() - 1]
			var stub := 0
			if t_low < STUB_LEG and t_low < len_l - t_low:
				stub = -1
				w_low.x = lead + 30.0
			elif len_l - t_low < STUB_LEG:
				stub = 1
				w_low.y = lead + 30.0
			var w_high := Vector2(base + (ext if climb_dir != -1 else climb_ext), base + (ext if climb_dir != 1 else climb_ext))
			hl = fw.routes[low].heights.duplicate()
			hh = fw.routes[high].heights.duplicate()
			var top := -INF
			var bottom := -INF
			for i in hh.size():
				if run_h[i] >= t_high - w_high.x and run_h[i] <= t_high + w_high.y:
					top = maxf(top, hh[i])
			for i in hl.size():
				if run_l[i] >= t_low - w_low.x and run_l[i] <= t_low + w_low.y:
					bottom = maxf(bottom, hl[i])
			var h1 := maxf(bottom, top - 3.0 * sep - slack)
			var h4 := maxf(top, h1 + 3.0 * sep + slack)
			hl = _raise(hl, fw.routes[low].points, run_l, t_low - w_low.x, t_low + w_low.y, h1, stub)
			hh = _raise(hh, fw.routes[high].points, run_h, t_high - w_high.x, t_high + w_high.y, h4)
			var gap := (h4 - h1) / 3.0
			levels = PackedFloat32Array([h1, h1 + gap, h1 + gap * 2.0, h4])
			if OS.get_environment("STACK_DEBUG") == "1":
				print("STACK try climb ext %.0f slack %.1f levels %s climb %d" % [climb_ext, slack, levels, climb_dir])
			# The decks the connectors are solved against: [points, heights, runs, width].
			mains = {low: [fw.routes[low].points, hl, run_l, float(fw.routes[low].width)],
				high: [fw.routes[high].points, hh, run_h, float(fw.routes[high].width)]}
			_ext = ext
			_climb_ext = climb_ext
			made = _make_links(mains, lead)
			if not made.is_empty():
				break
		if not made.is_empty():
			break
	if made.is_empty():
		push_warning("FreewayStack: no feasible connector profiles; the decks cross the old way")
		return false
	fw.routes[low].heights = hl
	fw.routes[high].heights = hh
	links = made
	_mark_mains(mains)
	return true


## The crossing nearest `want`: [point, seg a, frac a, seg b, frac b], or [] if none within 200 m.
static func _crossing(pa: PackedVector2Array, pb: PackedVector2Array, want: Vector2) -> Array:
	var best: Array = []
	var best_d := 200.0
	for i in pa.size() - 1:
		if pa[i].distance_to(want) > 500.0:
			continue
		for j in pb.size() - 1:
			if pb[j].distance_to(want) > 500.0:
				continue
			var u := Freeway._segments_cross(pb[j], pb[j + 1], pa[i], pa[i + 1])
			if u < 0.0:
				continue
			var p := pa[i].lerp(pa[i + 1], u)
			var v := Freeway._segments_cross(pa[i], pa[i + 1], pb[j], pb[j + 1])
			if p.distance_to(want) < best_d:
				best_d = p.distance_to(want)
				best = [p, i, u, j, v]
	return best


static func _runs(pts: PackedVector2Array) -> PackedFloat32Array:
	var run := PackedFloat32Array()
	run.resize(pts.size())
	for i in range(1, pts.size()):
		run[i] = run[i - 1] + pts[i].distance_to(pts[i - 1])
	return run


## Raise-only: at least `h` between runs t0 and t1, easing off at Freeway.MAX_GRADE.
static func _raise(hs: PackedFloat32Array, pts: PackedVector2Array, run: PackedFloat32Array, t0: float, t1: float, h: float, ramp := 0) -> PackedFloat32Array:
	var need := PackedFloat32Array()
	need.resize(hs.size())
	for i in hs.size():
		need[i] = h if run[i] >= t0 and run[i] <= t1 else -1e9
		# `ramp` -1 / +1: past that end of the window it climbs away at STUB_GRADE.
		if ramp < 0 and run[i] < t0:
			need[i] = h + STUB_GRADE * (t0 - run[i])
		elif ramp > 0 and run[i] > t1:
			need[i] = h + STUB_GRADE * (run[i] - t1)
	for i in range(1, need.size()):
		need[i] = maxf(need[i], need[i - 1] - Freeway.MAX_GRADE * pts[i].distance_to(pts[i - 1]))
	for i in range(need.size() - 2, -1, -1):
		need[i] = maxf(need[i], need[i + 1] - Freeway.MAX_GRADE * pts[i].distance_to(pts[i + 1]))
	var out := hs.duplicate()
	for i in out.size():
		out[i] = maxf(out[i], need[i])
	return out


## [pos, dir, height] at run `t` along a line.
static func line_at(pts: PackedVector2Array, hs: PackedFloat32Array, run: PackedFloat32Array, t: float) -> Array:
	var last := pts.size() - 1
	t = clampf(t, 0.0, run[last])
	var lo := 0
	var hi := last
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if run[mid] <= t:
			lo = mid
		else:
			hi = mid
	var seg := run[hi] - run[lo]
	var f: float = 0.0 if seg <= 0.0 else (t - run[lo]) / seg
	var d := pts[hi] - pts[lo]
	return [pts[lo].lerp(pts[hi], f), d / maxf(d.length(), 0.001), lerpf(hs[lo], hs[hi], f)]


## Nearest point on a line to `p`: [run, distance, height]. Only segments whose bounds come
## within `reach` are tested.
static func line_nearest(pts: PackedVector2Array, hs: PackedFloat32Array, run: PackedFloat32Array, p: Vector2, reach := 1e9) -> Array:
	var best := [0.0, INF, 0.0]
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if minf(a.x, b.x) - reach > p.x or maxf(a.x, b.x) + reach < p.x or minf(a.y, b.y) - reach > p.y or maxf(a.y, b.y) + reach < p.y:
			continue
		var ab := b - a
		var f := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * f)
		if d < best[1]:
			best = [run[i] + (run[i + 1] - run[i]) * f, d, lerpf(hs[i], hs[i + 1], f)]
	return best


func _make_links(mains: Dictionary, lead: float) -> Array[Dictionary]:
	# The four left turns: from each main line in each direction onto the other one.
	var cand: Array[Dictionary] = []
	for from: int in [low, high]:
		var to := high if from == low else low
		for sf: int in [1, -1]:
			for st: int in [1, -1]:
				var tcf := t_low if from == low else t_high
				var tct := t_low if to == low else t_high
				var df: Vector2 = line_at(mains[from][0], mains[from][1], mains[from][2], tcf)[1] * sf
				var dt: Vector2 = line_at(mains[to][0], mains[to][1], mains[to][2], tct)[1] * st
				# A left turn in x/z (x east, z south): the cross product is negative.
				if df.cross(dt) >= -0.3:
					continue
				var link := _path(mains, from, sf, to, st, lead)
				if link.is_empty():
					return []
				cand.append(link)
	if OS.get_environment("STACK_DEBUG") == "1":
		print("STACK candidates ", cand.size(), " levels ", levels)
	if cand.size() != 4:
		return []
	# Which connectors cross which: those pairs go on different levels.
	var cross := []
	for i in 4:
		var row := []
		for j in 4:
			row.append(i != j and _lines_cross(cand[i], cand[j]))
		cross.append(row)
	var colour := [-1, -1, -1, -1]
	colour[0] = 0
	for pass_i in 4:
		for i in 4:
			for j in 4:
				if cross[i][j] and colour[i] >= 0 and colour[j] < 0:
					colour[j] = 1 - colour[i]
	if OS.get_environment("STACK_DEBUG") == "1":
		print("STACK crossings ", cross, " colour ", colour)
	for i in 4:
		if colour[i] < 0:
			colour[i] = 0
		for j in 4:
			if cross[i][j] and colour[i] == colour[j]:
				return []
	for flip: int in [0, 1]:
		var out := _solve(mains, cand, colour, flip, true)
		if not out.is_empty():
			return out
	return []


func _solve(mains: Dictionary, cand: Array[Dictionary], colour: Array, flip: int, _unused: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in cand:
		var d: Dictionary = c.duplicate()
		d.level = 1 + ((colour[cand.find(c)] + flip) % 2)
		out.append(d)
	# Every connector first against the main lines alone, then the pairs that cross are pushed
	# apart where they fall short of DECK_SEPARATION, the shortfall split by how much room each
	# has left between its own envelopes, until none falls short (or one has no room).
	var sep := LINK_SEP + 0.06
	for it in 24:
		for l in out:
			if not _profile(mains, l):
				return []
		var short := false
		for a in out:
			if int(a.level) != 1:
				continue
			for b in out:
				if int(b.level) != 2:
					continue
				var pa: PackedVector2Array = a.points
				var ha: PackedFloat32Array = a.heights
				for i in pa.size():
					var near := line_nearest(b.points, b.heights, b.run, pa[i], 30.0)
					if float(near[1]) >= LINK_WIDTH + 1.5:
						continue
					var j := clampi(int(round(float(near[0]) / LINK_STEP)), 0, (b.heights as PackedFloat32Array).size() - 1)
					var hb: float = float(near[2])
					var deficit := sep - (hb - ha[i])
					if deficit <= 0.0:
						continue
					short = true
					var room_a: float = maxf(ha[i] - float(a.dn[i]), 0.0)
					var room_b: float = maxf(float(b.up[j]) - hb, 0.0)
					if room_a + room_b < deficit - 0.01:
						if OS.get_environment("STACK_DEBUG") == "1":
							print("STACK no room at %s: %.1f short, room %.1f + %.1f (link %d s %.0f h %.1f dn %.1f / link %d h %.1f up %.1f)" % [pa[i], deficit, room_a, room_b, out.find(a), float(a.run[i]), ha[i], float(a.dn[i]), out.find(b), hb, float(b.up[j])])
							_dump(mains, out)
						return []
					var share := room_a / maxf(room_a + room_b, 0.001)
					var down := deficit * share
					var lift := deficit - down
					(a.x_hi as PackedFloat32Array)[i] = minf(float(a.x_hi[i]), ha[i] - down - 0.05)
					for jj in [j - 1, j, j + 1]:
						if jj >= 0 and jj < (b.heights as PackedFloat32Array).size():
							(b.x_lo as PackedFloat32Array)[jj] = maxf(float(b.x_lo[jj]), hb + lift + 0.05)
		if not short:
			break
	var bad := verify_all(mains, out)
	if not bad.is_empty():
		if OS.get_environment("STACK_DEBUG") == "1":
			print("STACK verify ", bad)
		return []
	for k in 4:
		for key in ["base_lo", "base_hi", "x_lo", "x_hi", "dn", "up"]:
			out[k].erase(key)
		out[k].name = "Connector %d" % k
		_bank(out[k])
	return out


func _dump(mains: Dictionary, out: Array) -> void:
	var d := {"mains": [], "links": []}
	for ri in mains:
		var m: Array = mains[ri]
		var pts := []
		for i in (m[0] as PackedVector2Array).size():
			if (m[0][i] as Vector2).distance_to(centre) < 700.0:
				pts.append([m[0][i].x, m[0][i].y, m[1][i]])
		d.mains.append(pts)
	for l in out:
		var pts := []
		for i in (l.points as PackedVector2Array).size():
			pts.append([l.points[i].x, l.points[i].y, l.heights[i], l.dn[i], l.up[i], l.run[i], l.kind[i]])
		d.links.append({"level": l.level, "from": l.from, "fs": l.from_sign, "pts": pts})
	var f := FileAccess.open("/tmp/claude-0/stack_dump.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))


## The connector's centre line from its parent (route `from`, travelling `sf`) onto `to` (`st`).
func _path(mains: Dictionary, from: int, sf: int, to: int, st: int, lead: float) -> Dictionary:
	var mf: Array = mains[from]
	var mt: Array = mains[to]
	var tcf := t_low if from == low else t_high
	var tct := t_low if to == low else t_high
	var len_f: float = (mf[2] as PackedFloat32Array)[(mf[2] as PackedFloat32Array).size() - 1]
	var len_t: float = (mt[2] as PackedFloat32Array)[(mt[2] as PackedFloat32Array).size() - 1]
	var o0: float = float(mf[3]) * 0.5 + LINK_WIDTH * 0.5
	var o0t: float = float(mt[3]) * 0.5 + LINK_WIDTH * 0.5
	var d := o0 + GAP
	var dt := o0t + GAP
	var ts := tcf - sf * lead
	var te := tct + st * lead
	# The extra run beside the parent / target, except on the high line's climbing leg.
	var ext_f := _ext
	var ext_t := _ext
	if from == high and climb_dir != 0 and -sf == climb_dir:
		ext_f = _climb_ext
	if to == high and climb_dir != 0 and st == climb_dir:
		ext_t = _climb_ext
	# The run before S on the parent (and after E on the target) the leads may use.
	var room_f := (ts if sf > 0 else len_f - ts)
	var room_t := (len_t - te if st > 0 else te)
	ext_f = clampf(room_f - (TOUCH + TAPER), 0.0, ext_f)
	ext_t = clampf(room_t - (TOUCH + TAPER), 0.0, ext_t)
	room_f -= ext_f
	room_t -= ext_t
	var sc_f := clampf(room_f / (TOUCH + TAPER), 0.0, 1.0)
	var sc_t := clampf(room_t / (TOUCH + TAPER), 0.0, 1.0)
	if sc_f < 0.55 or sc_t < 0.55:
		return {}
	var touch_f := TOUCH * sc_f
	var taper_f := TAPER * sc_f
	var touch_t := TOUCH * sc_t
	var taper_t := TAPER * sc_t
	var fine := PackedVector2Array()
	var kind := PackedInt32Array()
	var par := PackedFloat32Array()
	# Lead in along the parent.
	var span := touch_f + taper_f + ext_f
	var k := 0
	while float(k) * 2.0 < span:
		var u := float(k) * 2.0
		var t := ts - sf * (span - u)
		var at := line_at(mf[0], mf[1], mf[2], t)
		var o := o0 if u < touch_f else lerpf(o0, d, smoothstep(0.0, 1.0, (u - touch_f) / taper_f))
		var dir: Vector2 = at[1] * sf
		fine.append((at[0] as Vector2) + Vector2(-dir.y, dir.x) * o)
		kind.append(0)
		par.append(t)
		k += 1
	var sa := line_at(mf[0], mf[1], mf[2], ts)
	var ea := line_at(mt[0], mt[1], mt[2], te)
	var hs: Vector2 = sa[1] * sf
	var he: Vector2 = ea[1] * st
	var s_pt: Vector2 = (sa[0] as Vector2) + Vector2(-hs.y, hs.x) * d
	var e_pt: Vector2 = (ea[0] as Vector2) + Vector2(-he.y, he.x) * dt
	var theta := absf(hs.angle_to(he))
	var chord := s_pt.distance_to(e_pt)
	var r := chord / maxf(2.0 * sin(theta * 0.5), 0.05)
	var kk := 4.0 / 3.0 * tan(theta * 0.25) * r
	var c1 := s_pt + hs * kk
	var c2 := e_pt - he * kk
	var nb := maxi(24, int(chord / 1.5))
	for i in nb:
		var t := float(i) / nb
		var q := 1.0 - t
		fine.append(s_pt * (q * q * q) + c1 * (3.0 * q * q * t) + c2 * (3.0 * q * t * t) + e_pt * (t * t * t))
		kind.append(1)
		par.append(NAN)
	span = touch_t + taper_t + ext_t
	k = 0
	while float(k) * 2.0 <= span + 0.01:
		var u := minf(float(k) * 2.0, span)
		var t := te + st * u
		var at := line_at(mt[0], mt[1], mt[2], t)
		var o := o0t if u > taper_t + ext_t else lerpf(dt, o0t, smoothstep(0.0, 1.0, (u - ext_t) / taper_t))
		var dir: Vector2 = at[1] * st
		fine.append((at[0] as Vector2) + Vector2(-dir.y, dir.x) * o)
		kind.append(2)
		par.append(t)
		k += 1
	# Resample at LINK_STEP by arc length.
	var cum := PackedFloat32Array([0.0])
	for i in range(1, fine.size()):
		cum.append(cum[i - 1] + fine[i].distance_to(fine[i - 1]))
	var total := cum[cum.size() - 1]
	var n := maxi(2, int(round(total / LINK_STEP)))
	var pts := PackedVector2Array()
	var run := PackedFloat32Array()
	var pk := PackedInt32Array()
	var pp := PackedFloat32Array()
	var j := 0
	for i in n + 1:
		var s := total * float(i) / n
		while j < fine.size() - 2 and cum[j + 1] < s:
			j += 1
		var f := clampf((s - cum[j]) / maxf(cum[j + 1] - cum[j], 0.0001), 0.0, 1.0)
		pts.append(fine[j].lerp(fine[j + 1], f))
		run.append(s)
		var kd := kind[j] if f < 0.5 else kind[j + 1]
		pk.append(kd)
		var a := par[j]
		var b := par[j + 1]
		pp.append(lerpf(a, b, f) if not (is_nan(a) or is_nan(b)) else (a if f < 0.5 else b))
	return {
		"from": from, "from_sign": sf, "to": to, "to_sign": st, "width": LINK_WIDTH,
		"points": pts, "run": run, "kind": pk, "pt": pp, "length": total,
		"touch_a": touch_f, "taper_a": touch_f + taper_f,
		"touch_b": total - touch_t, "taper_b": total - touch_t - taper_t,
	}


static func _lines_cross(a: Dictionary, b: Dictionary) -> bool:
	var pa: PackedVector2Array = a.points
	var pb: PackedVector2Array = b.points
	for i in pa.size() - 1:
		for j in pb.size() - 1:
			if Freeway._segments_cross(pa[i], pa[i + 1], pb[j], pb[j + 1]) >= 0.0:
				return true
	return false


## How a connector at `level` passes a deck of `other_level`: +1 over it, -1 under it.
static func _relation(level: int, other_level: int) -> int:
	return 1 if level > other_level else -1


## Solves one connector's heights: between its ties, over the 110 and under the 101 wherever
## their footprints overlap, the pushes from the connectors it crosses (x_lo / x_hi), never
## steeper than GRADE_SOLVE, as near its level as that allows, with vertical curves.
func _profile(mains: Dictionary, link: Dictionary) -> bool:
	var pts: PackedVector2Array = link.points
	var run: PackedFloat32Array = link.run
	var n := pts.size()
	if not link.has("base_lo"):
		_base_bounds(mains, link)
	var lo: PackedFloat32Array = (link.base_lo as PackedFloat32Array).duplicate()
	var hi: PackedFloat32Array = (link.base_hi as PackedFloat32Array).duplicate()
	for i in n:
		lo[i] = maxf(lo[i], float(link.x_lo[i]))
		hi[i] = minf(hi[i], float(link.x_hi[i]))
	# Envelopes: the lowest and highest a grade-limited profile can be at each point.
	var dn := lo.duplicate()
	var up := hi.duplicate()
	for i in range(1, n):
		var g := GRADE_SOLVE * (run[i] - run[i - 1])
		dn[i] = maxf(dn[i], dn[i - 1] - g)
		up[i] = minf(up[i], up[i - 1] + g)
	for i in range(n - 2, -1, -1):
		var g := GRADE_SOLVE * (run[i + 1] - run[i])
		dn[i] = maxf(dn[i], dn[i + 1] - g)
		up[i] = minf(up[i], up[i + 1] + g)
	for i in n:
		if dn[i] > up[i] + 0.05:
			if OS.get_environment("STACK_DEBUG") == "1":
				print("STACK link from %d(%d) level %d infeasible at s %.0f: lo %.1f hi %.1f dn %.1f up %.1f" % [link.from, link.from_sign, link.level, run[i], lo[i], hi[i], dn[i], up[i]])
			return false
	var want: float = levels[int(link.level)]
	var h := PackedFloat32Array()
	h.resize(n)
	for i in n:
		h[i] = clampf(want, dn[i], up[i])
	# Vertical curves: smooth, then back between the envelopes (both are grade-limited).
	for pass_i in 6:
		var src := h.duplicate()
		for i in range(1, n - 1):
			h[i] = clampf((src[i - 1] + src[i] * 2.0 + src[i + 1]) * 0.25, dn[i], up[i])
	link.heights = h
	link.dn = dn
	link.up = up
	return true


## The bounds that do not change while the connectors are pushed apart: the ties, the main
## lines and the ground.
func _base_bounds(mains: Dictionary, link: Dictionary) -> void:
	var pts: PackedVector2Array = link.points
	var run: PackedFloat32Array = link.run
	var n := pts.size()
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(n)
	hi.resize(n)
	var sep := Freeway.DECK_SEPARATION
	var w := LINK_WIDTH * 0.5
	var mf: Array = mains[link.from]
	var mt: Array = mains[link.to]
	for i in n:
		lo[i] = -1e9
		hi[i] = 1e9
		var s := run[i]
		if s <= float(link.touch_a) + 0.01:
			var hgt: float = line_at(mf[0], mf[1], mf[2], float(link.pt[i]))[2]
			lo[i] = hgt
			hi[i] = hgt
			continue
		if s >= float(link.touch_b) - 0.01:
			var hgt: float = line_at(mt[0], mt[1], mt[2], float(link.pt[i]))[2]
			lo[i] = hgt
			hi[i] = hgt
			continue
		for ri: int in [low, high]:
			var m: Array = mains[ri]
			# Beside its own parent / target in the leads, not over it.
			if ri == int(link.from) and int(link.kind[i]) == 0:
				continue
			if ri == int(link.to) and int(link.kind[i]) == 2:
				continue
			var near := line_nearest(m[0], m[1], m[2], pts[i], float(m[3]) + 40.0)
			if float(near[1]) < float(m[3]) * 0.5 + w + 1.5:
				if ri == low:
					lo[i] = maxf(lo[i], float(near[2]) + sep)
				else:
					hi[i] = minf(hi[i], float(near[2]) - sep)
		# Never down near the street.
		lo[i] = maxf(lo[i], _macro.height_at(pts[i]) + Freeway.MIN_CLEARANCE + GIRDER)
	link.base_lo = lo
	link.base_hi = hi
	var xl := PackedFloat32Array()
	var xh := PackedFloat32Array()
	xl.resize(n)
	xh.resize(n)
	xl.fill(-1e9)
	xh.fill(1e9)
	link.x_lo = xl
	link.x_hi = xh


## Superelevation per point: into the curve (a left turn lifts the right edge), none on the
## touch runs, eased on along the tapers.
static func _bank(link: Dictionary) -> void:
	var pts: PackedVector2Array = link.points
	var run: PackedFloat32Array = link.run
	var n := pts.size()
	var e := PackedFloat32Array()
	e.resize(n)
	for i in n:
		var a := pts[maxi(i - 2, 0)]
		var b := pts[i]
		var c := pts[mini(i + 2, n - 1)]
		var d0 := (b - a).normalized()
		var d1 := (c - b).normalized()
		var ds := maxf(a.distance_to(c) * 0.5, 0.1)
		var kappa := -d0.cross(d1) / ds
		e[i] = clampf(kappa * BANK_K, -BANK_MAX, BANK_MAX)
	for pass_i in 6:
		var src := e.duplicate()
		for i in range(1, n - 1):
			e[i] = (src[i - 1] + src[i] + src[i + 1]) / 3.0
	for i in n:
		var s := run[i]
		var f := smoothstep(float(link.touch_a), float(link.taper_a), s) * (1.0 - smoothstep(float(link.taper_b), float(link.touch_b), s))
		e[i] *= f
	link.bank = e


## Every deck pair that overlaps in plan must be DECK_SEPARATION apart; connectors never steeper
## than GRADE (plus rounding). Returns the problems (empty when sound). The checks call it too.
func verify_all(mains: Dictionary, the_links: Array) -> Array[String]:
	var bad: Array[String] = []
	var sep := Freeway.DECK_SEPARATION - 0.05
	var lines: Array = []
	for ri in mains:
		var m: Array = mains[ri]
		lines.append({"id": "route %d" % ri, "ri": ri, "points": m[0], "heights": m[1], "run": m[2], "width": m[3]})
	for l in the_links:
		lines.append({"id": "link %d" % the_links.find(l), "link": l, "points": l.points, "heights": l.heights, "run": l.run, "width": LINK_WIDTH})
	for a in lines:
		if not a.has("link"):
			continue
		var l: Dictionary = a.link
		var pts: PackedVector2Array = a.points
		var hs: PackedFloat32Array = a.heights
		var run: PackedFloat32Array = a.run
		for i in range(1, pts.size()):
			var g := absf(hs[i] - hs[i - 1]) / maxf(run[i] - run[i - 1], 0.01)
			if g > GRADE_SOLVE + 0.002:
				bad.append("%s grade %.3f at %d" % [a.id, g, i])
				break
		for b in lines:
			if b == a:
				continue
			for i in pts.size():
				var s := run[i]
				if s < float(l.taper_a) or s > float(l.taper_b):
					continue
				var near := line_nearest(b.points, b.heights, b.run, pts[i], float(b.width) + 30.0)
				var need := sep if b.has("ri") else LINK_SEP - 0.05
				if float(near[1]) < (float(b.width) + LINK_WIDTH) * 0.5 - 0.5 and absf(float(near[2]) - hs[i]) < need:
					# A lead beside its own parent / target does not count.
					if b.has("ri") and ((int(b.ri) == int(l.from) and int(l.kind[i]) == 0) or (int(b.ri) == int(l.to) and int(l.kind[i]) == 2)):
						continue
					bad.append("%s and %s %.1f m apart at %s" % [a.id, b.id, absf(float(near[2]) - hs[i]), pts[i]])
					break
	return bad


## Marks the main-line segments a connector touches (open barrier) or a deck passes over.
func _mark_mains(mains: Dictionary) -> void:
	open_edges.clear()
	covered.clear()
	for l in links:
		var pts: PackedVector2Array = l.points
		var run: PackedFloat32Array = l.run
		for i in pts.size():
			var s := run[i]
			var ri := -1
			var sg := 0
			if s <= float(l.touch_a):
				ri = int(l.from)
				sg = int(l.from_sign)
			elif s >= float(l.touch_b):
				ri = int(l.to)
				sg = int(l.to_sign)
			if ri < 0:
				continue
			var m: Array = mains[ri]
			var near := line_nearest(m[0], m[1], m[2], pts[i], 60.0)
			var seg := _seg_of(m[2], float(near[0]))
			open_edges[Vector2i(ri, seg)] = sg
	for ri in mains:
		var m: Array = mains[ri]
		var pts: PackedVector2Array = m[0]
		var hs: PackedFloat32Array = m[1]
		for i in pts.size():
			if pts[i].distance_to(centre) > KEEP:
				continue
			if deck_over(pts[i], hs[i], 14.0, ri):
				covered[Vector2i(ri, i)] = true


static func _seg_of(run: PackedFloat32Array, t: float) -> int:
	var lo := 0
	var hi := run.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if run[mid] <= t:
			lo = mid
		else:
			hi = mid
	return lo


## True if a stack deck (a connector, or the other main line) passes over `p` higher than `h`
## and lower than h + `reach`. `skip` is a route index or LINK_BASE + link to leave out.
func deck_over(p: Vector2, h: float, reach: float, skip: int) -> bool:
	for ri: int in [low, high]:
		if ri == skip or _fw == null:
			continue
		var r: Dictionary = _fw.routes[ri]
		var near := line_nearest(r.points, r.heights, _runs_of(ri), p, float(r.width) + 20.0)
		if float(near[1]) < float(r.width) * 0.5 + 0.5 and float(near[2]) > h + 1.0 and float(near[2]) < h + reach:
			return true
	for k in links.size():
		if LINK_BASE + k == skip:
			continue
		var l: Dictionary = links[k]
		if not l.has("heights"):
			continue
		var near := line_nearest(l.points, l.heights, l.run, p, 30.0)
		if float(near[1]) < LINK_WIDTH * 0.5 + 0.5 and float(near[2]) > h + 1.0 and float(near[2]) < h + reach:
			return true
	return false


var _run_cache := {}


func _runs_of(ri: int) -> PackedFloat32Array:
	if not _run_cache.has(ri):
		_run_cache[ri] = _runs(_fw.routes[ri].points)
	return _run_cache[ri]


## Every deck under `p` lower than `h` (route or link id, its height there): what a column at p
## would have to pass through.
func decks_below(p: Vector2, h: float, margin: float) -> bool:
	for ri: int in [low, high]:
		var r: Dictionary = _fw.routes[ri]
		var near := line_nearest(r.points, r.heights, _runs_of(ri), p, float(r.width) + 20.0)
		if float(near[1]) < float(r.width) * 0.5 + margin and float(near[2]) < h - 0.5:
			return true
	for l in links:
		var near := line_nearest(l.points, l.heights, l.run, p, 30.0)
		if float(near[1]) < LINK_WIDTH * 0.5 + margin and float(near[2]) < h - 0.5:
			return true
	return false


# --- Columns (lazy: they need the street plan) ----------------------------------------------

## Single columns: {pos, base, top, dir, cap_half, r, link (or -1), route, index}. A connector
## gets one every COLUMN_SPACING, slid along it off any deck below and off the carriageways;
## a main-line bent in the stack whose columns would stand on a deck below is skipped and a
## single hammerhead column takes its place under the centre line.
func columns(plan: CityPlan) -> Array[Dictionary]:
	if _cols_done:
		return _columns
	_cols_done = true
	for k in links.size():
		var l: Dictionary = links[k]
		var run: PackedFloat32Array = l.run
		var s := COLUMN_SPACING * 0.5
		while s < float(l.length) - 6.0:
			var spot := _clear_spot_link(plan, l, s)
			if spot >= 0.0:
				var at := line_at(l.points, l.heights, run, spot)
				var e := _bank_at(l, spot)
				_columns.append({"pos": at[0], "top": float(at[2]) - GIRDER, "dir": at[1], "bank": e,
					"cap_half": LINK_WIDTH * 0.5 - 1.6, "r": COLUMN_R, "link": k,
					"base": plan.height_at(at[0])})
			s += COLUMN_SPACING
	var every := int(round(Freeway.PILLAR_SPACING / Freeway.STEP))
	for ri: int in [low, high]:
		var r: Dictionary = _fw.routes[ri]
		var pts: PackedVector2Array = r.points
		var hs: PackedFloat32Array = r.heights
		var half: float = float(r.width) * 0.5
		var run := _runs_of(ri)
		for i in range(0, pts.size() - 1):
			if i % every != 0 or pts[i].distance_to(centre) > KEEP:
				continue
			var dir := (pts[i + 1] - pts[i]).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			var blocked := false
			for side: float in [-1.0, 1.0]:
				if decks_below(pts[i] + nrm * (half * 0.26 * side), hs[i], 1.6):
					blocked = true
			if not blocked:
				continue
			_skip_bents[Vector2i(ri, i)] = true
			for off: float in [0.0, 6.0, -6.0, 12.0, -12.0, 18.0, -18.0, 24.0, -24.0]:
				var t: float = run[i] + off
				var at := line_at(pts, hs, run, t)
				if decks_below(at[0], float(at[2]), MAIN_COLUMN_R + 0.8) or _on_road(plan, at[0], MAIN_COLUMN_R):
					continue
				_columns.append({"pos": at[0], "top": float(at[2]) - Freeway.DECK_THICKNESS, "dir": at[1], "bank": 0.0,
					"cap_half": half - 4.2, "r": MAIN_COLUMN_R, "link": -1, "route": ri,
					"base": plan.height_at(at[0])})
				break
	return _columns


func skips_bent(plan: CityPlan, ri: int, idx: int) -> bool:
	if ri != low and ri != high:
		return false
	columns(plan)
	return _skip_bents.has(Vector2i(ri, idx))


func _clear_spot_link(plan: CityPlan, l: Dictionary, s0: float) -> float:
	for off: float in [0.0, 4.0, -4.0, 8.0, -8.0, 12.0, -12.0, 16.0, -16.0]:
		var s := s0 + off
		if s < 2.0 or s > float(l.length) - 2.0:
			continue
		var at := line_at(l.points, l.heights, l.run, s)
		if decks_below(at[0], float(at[2]), COLUMN_R + 0.8):
			continue
		if _on_road(plan, at[0], COLUMN_R + 0.5):
			continue
		return s
	return -1.0


## True if `p` is on a street's carriageway (or within `margin` of it).
static func _on_road(plan: CityPlan, p: Vector2, margin: float) -> bool:
	if plan == null:
		return false
	var bi := plan.block_index_at(p)
	for i in [bi.x, bi.x + 1]:
		if absf(p.x - plan.road_pos(CityPlan.AXIS_X, i)) < plan.road_width(CityPlan.AXIS_X, i) * 0.5 + margin:
			return true
	for i in [bi.y, bi.y + 1]:
		if absf(p.y - plan.road_pos(CityPlan.AXIS_Z, i)) < plan.road_width(CityPlan.AXIS_Z, i) * 0.5 + margin:
			return true
	return false


static func _bank_at(l: Dictionary, s: float) -> float:
	var run: PackedFloat32Array = l.run
	var e: PackedFloat32Array = l.bank
	var i := _seg_of(run, s)
	var j := mini(i + 1, run.size() - 1)
	var f := clampf((s - run[i]) / maxf(run[j] - run[i], 0.001), 0.0, 1.0)
	return lerpf(e[i], e[j], f)


## A connector's frame at its point i: [position (deck top, centre), right (xz), bank].
static func frame(l: Dictionary, i: int) -> Array:
	var pts: PackedVector2Array = l.points
	var n := pts.size()
	var d := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
	return [Vector3(pts[i].x, (l.heights as PackedFloat32Array)[i], pts[i].y), Vector2(-d.y, d.x), (l.bank as PackedFloat32Array)[i], d]
