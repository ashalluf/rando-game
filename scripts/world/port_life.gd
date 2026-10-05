class_name PortLife
extends Node
## The container terminal at work (roadmap: port life). Everything that moves is WORKED OUT FROM
## THE CLOCK, never simulated, so the same second always shows the same picture:
##   * the ship-to-shore cranes over the moored ship DUAL-CYCLE: a yard tractor pulls in under
##     the crane with an export box, the spreader lifts it off the chassis, the trolley runs out
##     along the boom and sets it into a bay of the ship, picks up an import box from the next
##     slot and runs back to set it on the same chassis, and the tractor drives off round the
##     yard while the crane's second tractor pulls in (crane_plan(), crane_pose());
##   * the yard gantries (RTGs) gantry along their rows and shuffle a box from one stack to
##     another and back (rtg_plan(), rtg_pose()) - the box they lift is taken out of the
##     chunk's container batch while it is away (MultiMeshBatch instance hidden, put back on its
##     return);
##   * straddle carriers drive loops round the yard's blocks on the aisles between the chunks,
##     most of them with a box between their legs (straddle_loops());
##   * at night the moving machines' beacons, head lamps and work lights glow (port_steel.gdshader
##     parts 11-13) and throw pools of light, and the ship's deck is lit; the cranes clank when a
##     spreader locks onto or lets go of a box (Sfx "crane"), and Ambience's crane one-shots come
##     from a working crane when one is in earshot (clank_at()).
## The crane FRAMES stay merged meshes built by their chunks (PortKit.sts_frame_mesh(): the
## working crane without its trolley); a FULL chunk leaves a marker node (group "port_crane" /
## "port_rtg") carrying its crane's or gantry's plan, and this node draws the moving parts of the
## ones that are marked - nothing else. LOD chunks keep the old posed cranes and gantries.
## The moving parts are a handful of MultiMeshes (one per kind) written whole each frame, and the
## machines near the player get a kinematic body (props layer, mask 0) so they can be hit and
## stood on. Off with PORT_LIFE=0 in the environment (the A/B). PORT_T=<seconds> starts the clock
## there (stills), PORT_HOLD=1 holds it.

static var enabled: bool = OS.get_environment("PORT_LIFE") != "0"
static var clock: float = float(OS.get_environment("PORT_T")) if OS.get_environment("PORT_T") != "" else 0.0
static var hold: bool = OS.get_environment("PORT_HOLD") == "1"
static var _live: PortLife = null

## Player within this of the port rect: the terminal runs (metres).
@export var active_range: float = 1100.0
## Vehicles, gantries and boxes within this of the camera are drawn (metres).
@export var draw_range: float = 650.0
## Machines within this of the player carry a collision body (metres).
@export var body_range: float = 140.0
## A spreader locking onto a box clanks within this of the camera (metres).
@export var sound_range: float = 320.0
## Straddle carrier loops and their speed (m/s).
@export var straddle_speed: float = 5.6

# --- The STS cycle (see crane_plan()) ---------------------------------------------------------
## The spreader's underside while it travels, over the crane's base (clears four tiers on deck
## with a box under it).
const STS_TRAVEL := 26.0
## Trolley, empty hoist and loaded hoist speeds (m/s), and the seconds a spreader takes to lock.
const TROLLEY_SPEED := 4.0
const HOIST_EMPTY := 2.4
const HOIST_LOADED := 1.6
const LOCK_SECONDS := 3.0
## The window at the head of each half cycle in which one tractor leaves and the next pulls in.
const SWAP_WINDOW := 24.0
## Tractor acceleration (m/s2) on its loop.
const TRACTOR_ACCEL := 0.8
## The apron lanes (crane frame z) the cranes' tractors stop in, by crane index.
const STS_LANES := [2.54, -2.54, 7.62, -7.62]
## The chassis' centre behind the tractor's (m), along the path.
const HITCH := PortLifeKit.CHASSIS_KINGPIN - PortLifeKit.TT_FIFTH_X

# --- RTG cycle -----------------------------------------------------------------------------
const RTG_TRAVEL := 15.2
const RTG_PARK := PortKit.RTG_H - 5.5
const GANTRY_SPEED := 1.6

# --- The ship (Landmarks._build_cargo_ship's deck boxes, replayed) ----------------------------
const SHIP_BAYS := 10
const SHIP_ROWS := 3

## One kind of moving part: its MultiMesh and the instance buffer written whole each frame.
class Layer:
	var mmi: MultiMeshInstance3D
	var mm: MultiMesh
	var buf := PackedFloat32Array()
	var n := 0
	var cap := 0


var plan: CityPlan
var _player: Node3D
var _layers: Dictionary = {}
var _bodies: Dictionary = {}
var _ship_hidden: Dictionary = {}
var _ship_node: MultiMeshInstance3D = null
var _rtg_hidden: Dictionary = {}
var _last_step: Dictionary = {}
var _loops: Array = []
var _survey_left := 0.0
var _cranes: Array = []
var _rtgs: Array = []
## Spreaders of working cranes in view this frame (local space), for clank_at().
var _clank_spots: Array[Vector3] = []


## Makes the node (once) when the first port chunk is built: a plain Node under the city root,
## so nothing it draws is moved by an origin shift (it writes local positions itself).
static func ensure(chunk: Node) -> void:
	if not enabled or (_live != null and is_instance_valid(_live)):
		return
	var tree := chunk.get_tree()
	if tree == null:
		return
	var root: Node = tree.current_scene
	if root == null or not ("plan" in root):
		root = chunk.get_parent().get_parent() if chunk.get_parent() else null
	if root == null or not ("plan" in root):
		return
	var node := PortLife.new()
	node.name = "PortLife"
	_live = node
	root.add_child.call_deferred(node)


func _enter_tree() -> void:
	_live = self


func _exit_tree() -> void:
	if _live == self:
		_live = null
	_restore_all()


func _physics_process(delta: float) -> void:
	if not hold:
		clock += delta


# --- Pure layout -------------------------------------------------------------------------------

static var _grid_cache: Dictionary = {}


## The port's chunk grid and the aisles between its chunks: "xs" the centre x of each aisle
## between two columns of chunks, "zs" each aisle between two rows, "ix"/"iz" the chunk ranges,
## "gate" the chunk the gate takes (the north-west one, where the 110 comes in).
static func grid(p: CityPlan) -> Dictionary:
	var key := p.seed
	if _grid_cache.has(key):
		return _grid_cache[key]
	var pr: Rect2 = p.macro.port_rect
	var a := p.block_index_at(pr.position + Vector2(1.0, 1.0))
	var b := p.block_index_at(pr.end - Vector2(1.0, 1.0))
	var xs: Array[float] = []
	for ix in range(a.x, b.x):
		var r := p.owned_rect(ix, a.y + 1)
		var r2 := p.owned_rect(ix + 1, a.y + 1)
		var cols := int(r.size.x / 14.0)
		var last := 0
		for k in cols:
			if 8.0 + 14.0 * k + 6.0 <= r.size.x - 4.0:
				last = k
		xs.append((r.position.x + 8.0 + 14.0 * last + PortKit.L40 * 0.5 + r2.position.x + 8.0 - PortKit.L40 * 0.5) * 0.5)
	var zs: Array[float] = []
	var half_row := CityChunk.PORT_ROW_OFFSET + PortKit.W * 0.5
	for iz in range(a.y, b.y):
		var r := p.owned_rect(a.x + 1, iz)
		var r2 := p.owned_rect(a.x + 1, iz + 1)
		var rows := int(r.size.y / 9.0)
		var last := 0
		for k in rows:
			if 6.0 + 9.0 * k + 1.2 <= r.size.y - 4.0:
				last = k
		zs.append((r.position.y + 6.0 + 9.0 * last + half_row + r2.position.y + 6.0 - half_row) * 0.5)
	var out := {"xs": xs, "zs": zs, "ix": Vector2i(a.x, b.x), "iz": Vector2i(a.y, b.y), "gate": Vector2i(a.x, a.y)}
	_grid_cache[key] = out
	return out


## Whether chunk (ix, iz) is the gate's (PortGate builds it; it holds no stacks).
static func is_gate(p: CityPlan, ix: int, iz: int) -> bool:
	if not enabled or p.macro == null:
		return false
	return grid(p).gate == Vector2i(ix, iz)


static var _ship_cache: Array = []


## The detailed ship's deck boxes as Landmarks._build_cargo_ship() lays them (the same rolls in
## the same order: seed 4242 for the heights and lines, 4243 for the looks), one entry per
## instance of its container batch: bay, row, tier, k (abreast), the instance index, the centre
## (ship frame) and the transform, colour and custom it was given.
static func ship_boxes() -> Array:
	if not _ship_cache.is_empty():
		return _ship_cache
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var kit := RandomNumberGenerator.new()
	kit.seed = 4243
	var index := 0
	for i in SHIP_BAYS:
		var x := -70.0 + i * 14.0
		for row in SHIP_ROWS:
			var z := (row - 1) * 8.0
			var height := rng.randi_range(2, 4)
			for h in height:
				var pick: int = rng.randi() % 4
				for k in 3:
					var livery: int = PortKit.COLOR_TO_LIVERY[pick] if kit.randf() < 0.7 else kit.randi() % PortKit.LIVERY_COUNT
					var look := PortKit.container_look(livery, kit)
					var centre := Vector3(x, 9.0 + PortKit.H_STD * (h + 0.5), z + (k - 1) * (PortKit.W + 0.05))
					var flip := kit.randf() < 0.5
					_ship_cache.append({"bay": i, "row": row, "h": h, "height": height, "k": k, "index": index,
						"centre": centre, "flip": flip, "color": look[0], "custom": look[1]})
					index += 1
	return _ship_cache


## The ship's anchor (plan XZ), or INF.
static func ship_anchor() -> Vector2:
	for lm in Landmarks.all():
		if lm.id == "cargo_ship":
			return lm.anchor
	return Vector2(INF, INF)


## The x a working crane stands at: over the ship's bay nearest `x`, if that is within
## BAY_REACH (cranes gantry along the quay to the bay they work). Returns `x` with no ship.
const BAY_REACH := 32.0


static func bay_x(x: float) -> float:
	var s := ship_anchor()
	if s.x == INF:
		return x
	var i := clampi(roundi((x - s.x + 70.0) / 14.0), 0, SHIP_BAYS - 1)
	var bx := s.x - 70.0 + i * 14.0
	return bx if absf(bx - x) <= BAY_REACH else x


static func _top_box(bay: int, row: int, k: int) -> Dictionary:
	var best := {}
	for b: Dictionary in ship_boxes():
		if b.bay == bay and b.row == row and b.k == k and (best.is_empty() or int(b.h) > int(best.h)):
			best = b
	return best


# --- The STS crane's dual cycle ------------------------------------------------------------------

## Everything about one working crane's cycle, from its base (true world, the crane frame's origin)
## and its index (which apron lane its tractors use, its slots, its phase): two ship slots P and Q
## (the top boxes of two rows of its bay, hidden from the ship's batch while it works them), the
## step tables of the two half cycles, the tractors' loop round the yard and their drive times.
static func crane_plan(p: CityPlan, base: Vector3, index: int) -> Dictionary:
	var ship := ship_anchor()
	var bay := clampi(roundi((base.x - ship.x + 70.0) / 14.0), 0, SHIP_BAYS - 1)
	var hsh := absi(hash([p.seed, "sts", index]))
	var row_p := hsh % SHIP_ROWS
	var row_q := (row_p + 1 + (hsh / 7) % 2) % SHIP_ROWS
	var slots: Array = []
	for row: int in [row_p, row_q]:
		var b := _top_box(bay, row, 1)
		var c: Vector3 = b.centre
		var w := Vector3(ship.x + c.x, c.y, ship.y + c.z)
		slots.append({"index": b.index, "centre": w, "top": w.y + PortKit.H_STD * 0.5, "flip": b.flip,
			"color": b.color, "custom": b.custom})
	var lane_z: float = base.z + float(STS_LANES[index % STS_LANES.size()])
	var yc := base.y + PortLifeKit.CHASSIS_BED + PortKit.H_STD
	var plan_d := {"base": base, "index": index, "lane_z": lane_z, "P": slots[0], "Q": slots[1], "yc": yc,
		"ytrav": base.y + STS_TRAVEL, "seed": hsh}
	var even := _sts_half(plan_d, slots[0], slots[1])
	var odd := _sts_half(plan_d, slots[1], slots[0])
	plan_d.halves = [even, odd]
	plan_d.h = [float(even[-1].t1), float(odd[-1].t1)]
	plan_d.period = plan_d.h[0] + plan_d.h[1]
	plan_d.phase = float(hsh % 997) / 997.0 * plan_d.period
	plan_d.loop = _tractor_loop(p, Vector2(base.x, lane_z))
	return plan_d


## One half cycle's steps: [{t0, t1, z0, y0, z1, y1, carry, ev}] - carry 0 nothing, 1 the box
## that came in on the chassis, 2 the box going out; ev "latch" / "drop" at the step's end.
static func _sts_half(c: Dictionary, a: Dictionary, b: Dictionary) -> Array:
	var steps: Array = []
	var zt: float = c.lane_z
	var yc: float = c.yc
	var yt: float = c.ytrav
	var cur := [0.0, zt, yc]
	var add := func(z1: float, y1: float, carry: int, ev: String, hold_until: float = -1.0) -> void:
		var t0: float = cur[0]
		var dz := absf(z1 - float(cur[1]))
		var dy := absf(y1 - float(cur[2]))
		var dur := 0.0
		if ev != "":
			dur = LOCK_SECONDS
		elif dz > 0.01:
			dur = 2.0 + dz / TROLLEY_SPEED
		elif dy > 0.01:
			dur = 2.0 + dy / (HOIST_LOADED if carry > 0 else HOIST_EMPTY)
		var t1 := t0 + dur
		if hold_until > t1:
			t1 = hold_until
		steps.append({"t0": t0, "t1": t1, "z0": cur[1], "y0": cur[2], "z1": z1, "y1": y1, "carry": carry, "ev": ev, "move_t": t0 + dur if hold_until > 0.0 else t1})
		cur[0] = t1
		cur[1] = z1
		cur[2] = y1
	# The swap window: the spreader rises off the last chassis while that tractor leaves and the
	# next pulls in.
	add.call(zt, yt, 0, "", SWAP_WINDOW)
	add.call(zt, yc, 0, "")
	add.call(zt, yc, 0, "latch")
	add.call(zt, yt, 1, "")
	add.call(a.centre.z, yt, 1, "")
	add.call(a.centre.z, float(a.top), 1, "")
	add.call(a.centre.z, float(a.top), 1, "drop")
	add.call(a.centre.z, yt, 0, "")
	add.call(b.centre.z, yt, 0, "")
	add.call(b.centre.z, float(b.top), 0, "")
	add.call(b.centre.z, float(b.top), 0, "latch")
	add.call(b.centre.z, yt, 2, "")
	add.call(zt, yt, 2, "")
	add.call(zt, yc, 2, "")
	add.call(zt, yc, 2, "drop")
	return steps


## The tractors' loop: from the stop under the crane east along the apron lane, north up the
## first aisle 30 m clear of the crane, west along an aisle about 220 m in, south down the aisle
## the other side and east back to the stop. Right-hand running: each leg is offset 2.2 m to the
## right of its direction. Corners are arcs. Returns {pts: PackedVector2Array, cum, length}.
static func _tractor_loop(p: CityPlan, stop: Vector2) -> Dictionary:
	var g := grid(p)
	var xs: Array = g.xs
	var zs: Array = g.zs
	var e := INF
	var w := -INF
	for x: float in xs:
		if x > stop.x + 30.0 and x < e:
			e = x
		if x < stop.x - 30.0 and x > w:
			w = x
	if e == INF:
		e = stop.x + 60.0
	if w == -INF:
		w = stop.x - 60.0
	var n: float = zs[0] if not zs.is_empty() else stop.y - 200.0
	for z: float in zs:
		if absf(z - (stop.y - 220.0)) < absf(n - (stop.y - 220.0)):
			n = z
	e += 2.2
	w -= 2.2
	n -= 2.2
	var corners: Array[Vector2] = [Vector2(e, stop.y), Vector2(e, n), Vector2(w, n), Vector2(w, stop.y)]
	var pts := PackedVector2Array([stop])
	var r := 9.0
	for i in 4:
		var c := corners[i]
		var prev := corners[i - 1] if i > 0 else stop
		var nxt := corners[(i + 1) % 4] if i < 3 else stop + Vector2(1.0, 0.0)
		var d_in := (c - prev).normalized()
		var d_out := (nxt - c).normalized()
		var a0 := c - d_in * r
		var a1 := c + d_out * r
		for k in 7:
			var u := float(k) / 6.0
			# A quadratic Bezier through the corner: close enough to an arc at this size.
			pts.append(a0.lerp(c, u).lerp(c.lerp(a1, u), u))
	pts.append(stop)
	return _path(pts)


static func _path(pts: PackedVector2Array) -> Dictionary:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	return {"pts": pts, "cum": cum, "length": cum[cum.size() - 1]}


## A point and direction `s` metres along a closed path (wrapping).
static func path_at(path: Dictionary, s: float) -> Array:
	var pts: PackedVector2Array = path.pts
	var cum: PackedFloat32Array = path.cum
	var length: float = path.length
	if length <= 0.0:
		return [pts[0], Vector2(1.0, 0.0)]
	s = fposmod(s, length)
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := maxf(cum[hi] - cum[lo], 1e-4)
	var d := (pts[hi] - pts[lo]) / seg
	return [pts[lo] + d * (s - cum[lo]), d]


## Distance covered `tau` seconds into a drive of `length` metres that takes `total` seconds,
## starting and ending at rest: accelerate at TRACTOR_ACCEL, cruise, brake.
static func drive_s(tau: float, total: float, length: float) -> float:
	var a := TRACTOR_ACCEL
	tau = clampf(tau, 0.0, total)
	var disc := a * a * total * total - 4.0 * a * length
	var v := (a * total - sqrt(disc)) * 0.5 if disc > 0.0 else a * total * 0.5
	var ta := v / a
	var s: float
	if tau < ta:
		s = 0.5 * a * tau * tau
	elif tau < total - ta:
		s = 0.5 * a * ta * ta + v * (tau - ta)
	else:
		s = length - 0.5 * a * (total - tau) * (total - tau)
	return clampf(s, 0.0, length)


static func _smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## The look of the box that comes in on the chassis in half cycle `n` of crane `c`.
static func _look(c: Dictionary, n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([c.seed, n])
	var livery := rng.randi() % PortKit.LIVERY_COUNT
	var look := PortKit.container_look(livery, rng)
	look.append(rng.randf() < 0.5)
	return look


## Crane `c` at clock `t`: {trolley_z, spreader_y, step, half, n, u, boxes: [[centre, look]],
## spreader_box (look or []), tractors: [{s, look}]} - all true world.
static func crane_pose(c: Dictionary, t: float) -> Dictionary:
	var period: float = c.period
	var tt: float = t + float(c.phase)
	var cycle := floori(tt / period)
	var tm := tt - cycle * period
	var odd := tm >= float(c.h[0])
	var n := cycle * 2 + (1 if odd else 0)
	var u := tm - (float(c.h[0]) if odd else 0.0)
	var steps: Array = c.halves[1 if odd else 0]
	var si := 0
	while si < steps.size() - 1 and u >= float(steps[si].t1):
		si += 1
	var st: Dictionary = steps[si]
	var mv := maxf(float(st.move_t) - float(st.t0), 1e-3)
	var k := _smooth((u - float(st.t0)) / mv)
	var z := lerpf(st.z0, st.z1, k)
	var y := lerpf(st.y0, st.y1, k)
	var slot_a: Dictionary = c.Q if odd else c.P
	var slot_b: Dictionary = c.P if odd else c.Q
	var look_in := _look(c, n)
	var look_prev := _look(c, n - 1)
	var look_old := _look(c, n - 2)
	var look_next := _look(c, n + 1)
	var out := {"trolley_z": z, "spreader_y": y, "step": si, "n": n, "u": u, "ev": st.ev, "boxes": [], "spreader_box": [], "tractors": []}
	# Steps 3-6 carry the box that came in, 11-14 the one going out (both still on the spreader
	# while it lets go).
	if si >= 3 and si <= 6:
		out.spreader_box = look_in
	elif si >= 11:
		out.spreader_box = look_prev
	# Ship slots: A takes this half's box from its drop (step 6); B holds the last half's box
	# until its latch (step 10) is done.
	if si >= 7:
		out.boxes.append([slot_a.centre, look_in])
	if si <= 10:
		out.boxes.append([slot_b.centre, look_prev])
	# The tractor serving this half: pulling in during the window, then standing at the stop with
	# its box until the spreader has it (step 2).
	var h_prev: float = c.h[1] if not odd else c.h[0]
	var h_this: float = c.h[1] if odd else c.h[0]
	var length: float = c.loop.length
	var s_in := 0.0
	if u < SWAP_WINDOW:
		var total := h_prev + SWAP_WINDOW
		s_in = drive_s(total - (SWAP_WINDOW - u), total, length)
	out.tractors.append({"s": s_in, "look": look_in if si <= 2 else []})
	# The tractor that served the last half drives off with its import box from the start of this
	# one; past the far side of its loop it is carrying the next export box instead.
	var leaving_total := h_this + SWAP_WINDOW
	out.tractors.append({"s": drive_s(u, leaving_total, length), "look": look_old if u < leaving_total * 0.5 else look_next})
	return out


# --- The yard gantry's shuffle -------------------------------------------------------------------

## A gantry's plan from its marker: centre (true world, at column c), flip, the column it shuffles
## to (dx), the source pile (a 40 ft box on top, hidden while it is away) and the target pile.
## Empty when there is no box to move.
static func rtg_plan(spec: Dictionary) -> Dictionary:
	var piles: Array = spec.piles
	var src := {}
	var dst := {}
	var cx: float = spec.centre.x
	var hsh := absi(hash([spec.seed, "rtg"]))
	var sources: Array = []
	for p: Dictionary in piles:
		if absf(float(p.x) - cx) < 1.0 and int(p.index) >= 0:
			sources.append(p)
	if sources.is_empty():
		return {}
	src = sources[hsh % sources.size()]
	for p: Dictionary in piles:
		if absf(float(p.x) - (cx + float(spec.dx))) < 1.0 and float(p.top) + PortKit.H_STD < spec.base.y + 4.0 * PortKit.H_HC:
			if dst.is_empty() or float(p.top) < float(dst.top):
				dst = p
	if dst.is_empty():
		return {}
	var b: Vector3 = spec.base
	var yt := b.y + RTG_TRAVEL
	var ys := float(src.top)
	var yd := float(dst.top) + PortKit.H_STD
	var x0 := cx
	var x1 := cx + float(spec.dx)
	var zc: float = spec.centre.y
	var steps: Array = []
	var cur := [0.0, x0, zc, b.y + RTG_PARK]
	var add := func(x: float, z: float, y: float, carry: bool, ev: String, wait: float = 0.0) -> void:
		var dur := 0.0
		if ev != "":
			dur = LOCK_SECONDS
		elif absf(x - float(cur[1])) > 0.01:
			dur = 2.0 + absf(x - float(cur[1])) / GANTRY_SPEED
		elif absf(z - float(cur[2])) > 0.01:
			dur = 2.0 + absf(z - float(cur[2])) / 1.4
		elif absf(y - float(cur[3])) > 0.01:
			dur = 2.0 + absf(y - float(cur[3])) / 1.0
		steps.append({"t0": cur[0], "t1": float(cur[0]) + dur + wait, "move_t": float(cur[0]) + maxf(dur, 0.001),
			"x0": cur[1], "z0": cur[2], "y0": cur[3], "x1": x, "z1": z, "y1": y, "carry": carry, "ev": ev})
		cur[0] = float(cur[0]) + dur + wait
		cur[1] = x
		cur[2] = z
		cur[3] = y
	add.call(x0, src.z, yt, false, "")
	add.call(x0, src.z, ys, false, "")
	add.call(x0, src.z, ys, false, "latch")
	add.call(x0, src.z, yt, true, "")
	add.call(x1, src.z, yt, true, "")
	add.call(x1, dst.z, yt, true, "")
	add.call(x1, dst.z, yd, true, "")
	add.call(x1, dst.z, yd, true, "drop")
	add.call(x1, dst.z, yt, false, "", 18.0)
	add.call(x1, dst.z, yd, false, "")
	add.call(x1, dst.z, yd, false, "latch")
	add.call(x1, dst.z, yt, true, "")
	add.call(x1, src.z, yt, true, "")
	add.call(x0, src.z, yt, true, "")
	add.call(x0, src.z, ys, true, "")
	add.call(x0, src.z, ys, true, "drop")
	add.call(x0, src.z, yt, false, "")
	add.call(x0, zc, b.y + RTG_PARK, false, "", 22.0)
	var period: float = cur[0]
	return {"steps": steps, "period": period, "phase": float(hsh % 991) / 991.0 * period, "src": src, "dst": dst, "base": b}


## Gantry `r` at clock `t`: x (gantry), trolley z, spreader underside y, step, where the box is
## ("pile" in its own stack, "spreader", or "dst" on the target stack).
static func rtg_pose(r: Dictionary, t: float) -> Dictionary:
	var u := fposmod(t + float(r.phase), float(r.period))
	var steps: Array = r.steps
	var si := 0
	while si < steps.size() - 1 and u >= float(steps[si].t1):
		si += 1
	var st: Dictionary = steps[si]
	var k := _smooth((u - float(st.t0)) / maxf(float(st.move_t) - float(st.t0), 1e-3))
	# 0-2 the box in its pile, 3-7 on the spreader, 8-10 on the target pile, 11-15 on the
	# spreader again, 16-17 back in its pile.
	var where := "pile"
	if r.has("idle"):
		pass
	elif si >= 3 and si <= 7 or si >= 11 and si <= 15:
		where = "spreader"
	elif si >= 8 and si <= 10:
		where = "dst"
	return {"x": lerpf(st.x0, st.x1, k), "z": lerpf(st.z0, st.z1, k), "y": lerpf(st.y0, st.y1, k), "step": si, "where": where, "ev": st.ev}


# --- Straddle carriers ---------------------------------------------------------------------------

## Loops round the yard's interior blocks on the aisles (clockwise on the map, right-hand offset
## so two loops sharing an aisle pass each other), most blocks with one or two carriers, most of
## them carrying a box. [{path, cars: [{offset, look or []}]}]
static func straddle_loops(p: CityPlan) -> Array:
	var g := grid(p)
	var xs: Array = g.xs
	var zs: Array = g.zs
	var out: Array = []
	var off := 3.0
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var h := absi(hash([p.seed, "straddle", i, j]))
			if h % 100 >= 60:
				continue
			var x0: float = xs[i] + off
			var x1: float = xs[i + 1] - off
			var z0: float = zs[j] + off
			var z1: float = zs[j + 1] - off
			# Clockwise on the map (x east, z south): east along the north side, south down the
			# east, west along the south, north up the west. Right-hand: inside the block.
			var corners: Array[Vector2] = [Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1), Vector2(x0, z0)]
			var pts := PackedVector2Array()
			var r := 8.0
			for c in 4:
				var cp := corners[c]
				var prev := corners[(c + 3) % 4]
				var nxt := corners[(c + 1) % 4]
				var a0 := cp + (prev - cp).normalized() * r
				var a1 := cp + (nxt - cp).normalized() * r
				for k in 7:
					var u := float(k) / 6.0
					pts.append(a0.lerp(cp, u).lerp(cp.lerp(a1, u), u))
			pts.append(pts[0])
			var path := _path(pts)
			var cars: Array = []
			var count := 1 + (h / 100) % 2
			for c in count:
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([p.seed, "sc", i, j, c])
				var look: Array = []
				if rng.randf() < 0.72:
					look = PortKit.container_look(rng.randi() % PortKit.LIVERY_COUNT, rng)
					look.append(rng.randf() < 0.5)
				cars.append({"offset": float(path.length) * (float(c) / float(count) + rng.randf() * 0.2), "look": look, "id": "%d_%d_%d" % [i, j, c]})
			out.append({"path": path, "cars": cars})
	return out


# --- Markers (from the chunks) ---------------------------------------------------------------

## A pile's record for the gantries: x, z, its top (true world y), and its top box's batch index
## (-1 when the top is a pair of 20s), transform, colour and custom as the batch holds them.
static func pile(batch: MultiMeshBatch, index: int, x: float, z: float, top: float) -> Dictionary:
	var d := {"x": x, "z": z, "top": top, "index": index}
	if index >= 0:
		var b: Dictionary = batch._batches["container"]
		d.xf = b.xforms[index]
		d.color = b.colors[index]
		d.custom = b.custom[index]
	return d


## A FULL chunk's working crane: a marker child carrying its plan (crane_plan()).
static func mark_crane(chunk: Node3D, base: Vector3, index: int) -> void:
	var m := Node3D.new()
	m.name = "PortCraneMarker%d" % index
	m.set_meta("plan", crane_plan(chunk.get("plan"), base, index))
	m.add_to_group("port_crane")
	chunk.add_child(m)


## A FULL chunk's yard gantry at `base` (true world, column centre on the middle row), shuffling
## a box to the column `dx` along. Its piles are the chunk's (pile()).
static func mark_rtg(chunk: Node3D, base: Vector3, flip: bool, dx: float, piles: Array) -> void:
	var reach := PortKit.RTG_SPAN * 0.5
	var near: Array = []
	for p: Dictionary in piles:
		if absf(float(p.z) - base.z) < reach - 1.5 and (absf(float(p.x) - base.x) < 1.0 or absf(float(p.x) - base.x - dx) < 1.0):
			near.append(p)
	var spec := {"centre": Vector2(base.x, base.z), "base": base, "flip": flip, "dx": dx, "piles": near,
		"seed": hash([base.x, base.z])}
	var r := rtg_plan(spec)
	if not r.is_empty():
		r.flip = flip
		r.chunk = chunk
	var m := Node3D.new()
	m.name = "PortRtgMarker"
	m.set_meta("plan", r)
	m.add_to_group("port_rtg")
	chunk.add_child(m)
	if r.is_empty():
		# Nothing to move: it stands where it is, still a body to bump into.
		r.merge({"steps": [{"t0": 0.0, "t1": 1.0, "move_t": 1.0, "x0": base.x, "z0": base.z, "y0": base.y + RTG_PARK,
			"x1": base.x, "z1": base.z, "y1": base.y + RTG_PARK, "carry": false, "ev": ""}], "period": 1.0, "phase": 0.0,
			"src": {}, "dst": {}, "base": base, "flip": flip, "chunk": chunk, "idle": true})


# --- Runtime -----------------------------------------------------------------------------------

func _setup() -> bool:
	if plan != null and _player != null and is_instance_valid(_player):
		return true
	var city := get_parent()
	if city == null or not ("plan" in city):
		return false
	plan = city.get("plan") as CityPlan
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if plan != null and plan.macro != null:
		_loops = straddle_loops(plan)
	return plan != null and plan.macro != null and _player != null


## Ambience asks: a working crane's spreader in earshot of `eye` (local), or INF.
static func clank_at(eye: Vector3, reach: float) -> Vector3:
	if _live == null or not is_instance_valid(_live):
		return Vector3.INF
	var best := Vector3.INF
	for p: Vector3 in _live._clank_spots:
		if p.distance_to(eye) < reach and (best == Vector3.INF or p.distance_to(eye) < best.distance_to(eye)):
			best = p
	return best


func _process(_delta: float) -> void:
	if not enabled or not _setup():
		return
	var eye_l := _player.global_position
	var eye := WorldState.to_world(eye_l)
	var cam := get_viewport().get_camera_3d()
	var view := WorldState.to_world(cam.global_position) if cam else eye
	var pr: Rect2 = plan.macro.port_rect.grow(active_range)
	var active := pr.has_point(Vector2(eye.x, eye.z)) or pr.has_point(Vector2(view.x, view.z))
	_survey_left -= _delta
	if _survey_left <= 0.0:
		_survey_left = 0.5
		_survey(active)
	for l: Layer in _layers.values():
		l.n = 0
	_clank_spots.clear()
	var used := {}
	if active:
		var night := DayNight.lamp_now > 0.05
		for c: Dictionary in _cranes:
			_draw_crane(c, view, night, used)
		for r: Dictionary in _rtgs:
			_draw_rtg(r, view, used)
		for lp: Dictionary in _loops:
			_draw_straddles(lp, view, eye, night, used)
		if night:
			_draw_ship_lights(view)
	_commit(view)
	for key: String in _bodies.keys():
		if not used.has(key):
			(_bodies[key] as Node).queue_free()
			_bodies.erase(key)


## Every half second: which cranes and gantries are marked (FULL chunks, shown), hide what they
## have taken out of the ship's and the stacks' batches, put back what they no longer hold.
func _survey(active: bool) -> void:
	_cranes.clear()
	_rtgs.clear()
	var want_ship := {}
	var want_rtg := {}
	if active:
		for m: Node in get_tree().get_nodes_in_group("port_crane"):
			if not (m as Node3D).is_visible_in_tree():
				continue
			var c: Dictionary = m.get_meta("plan")
			_cranes.append(c)
			want_ship[int(c.P.index)] = true
			want_ship[int(c.Q.index)] = true
		for m: Node in get_tree().get_nodes_in_group("port_rtg"):
			if not (m as Node3D).is_visible_in_tree():
				continue
			var r: Dictionary = m.get_meta("plan")
			if r.is_empty():
				continue
			r["marker"] = m
			_rtgs.append(r)
	# The ship's boxes.
	var ship: MultiMeshInstance3D = null
	for n: Node in get_tree().get_nodes_in_group("port_ship_boxes"):
		ship = n as MultiMeshInstance3D
	if ship != _ship_node:
		_ship_hidden.clear()
		_ship_node = ship
	if ship != null:
		for idx: int in _ship_hidden.keys():
			if not want_ship.has(idx):
				_show_ship(idx)
				_ship_hidden.erase(idx)
		for idx: int in want_ship.keys():
			if not _ship_hidden.has(idx):
				MultiMeshBatch.hide_instance(ship, idx)
				_ship_hidden[idx] = true
	# Gantries hide their box only while it is away (see _draw_rtg); one that is gone puts its back.
	for key: int in _rtg_hidden.keys():
		var still := false
		for r: Dictionary in _rtgs:
			if is_instance_valid(r.marker) and (r.marker as Node).get_instance_id() == key:
				still = true
		if not still:
			_rtg_put_back(key)


func _show_ship(idx: int) -> void:
	if _ship_node == null or not is_instance_valid(_ship_node):
		return
	for b: Dictionary in ship_boxes():
		if int(b.index) == idx:
			var anchor := ship_anchor()
			var xf := PortKit.container_xform(Vector3(anchor.x, 0.0, anchor.y) + (b.centre as Vector3), true, false, b.flip)
			_set_instance(_ship_node, idx, xf)
			return


static func _set_instance(node: MultiMeshInstance3D, idx: int, xf: Transform3D) -> void:
	if node == null or not is_instance_valid(node) or idx >= node.multimesh.instance_count:
		return
	node.multimesh.set_instance_transform(idx, xf)
	if node.has_meta("shadow_twin"):
		var twin := node.get_meta("shadow_twin") as MultiMeshInstance3D
		if twin and is_instance_valid(twin) and idx < twin.multimesh.instance_count:
			twin.multimesh.set_instance_transform(idx, xf)


func _restore_all() -> void:
	for idx: int in _ship_hidden.keys():
		_show_ship(idx)
	_ship_hidden.clear()
	for key: int in _rtg_hidden.keys():
		_rtg_put_back(key)


func _rtg_put_back(key: int) -> void:
	var h: Dictionary = _rtg_hidden[key]
	var node := h.node as MultiMeshInstance3D if is_instance_valid(h.node) else null
	if node:
		_set_instance(node, int(h.index), h.xf)
	_rtg_hidden.erase(key)


# --- Drawing -----------------------------------------------------------------------------------

func _layer(key: String) -> Layer:
	if _layers.has(key):
		return _layers[key]
	var mesh: Mesh
	var cap := 64
	match key:
		"trolley": mesh = PortKit.sts_trolley_mesh()
		"spreader": mesh = PortKit.sts_spreader_mesh()
		"rope": mesh = PortKit.rope_mesh()
		"rtg": mesh = PortKit.rtg_frame_mesh()
		"rtg_trolley": mesh = PortKit.rtg_trolley_mesh()
		"straddle": mesh = PortLifeKit.straddle_mesh()
		"tractor": mesh = PortLifeKit.tractor_mesh()
		"chassis": mesh = PortLifeKit.chassis_mesh()
		"box":
			mesh = PropFactory.container()
			cap = 128
		"pool":
			mesh = PropFactory.light_pool(Color(1.0, 0.9, 0.74), 0.55, 1.5)
			cap = 128
	var l := Layer.new()
	l.mm = MultiMesh.new()
	l.mm.transform_format = MultiMesh.TRANSFORM_3D
	l.mm.use_colors = true
	l.mm.use_custom_data = true
	l.mm.mesh = mesh
	l.mm.instance_count = cap
	l.mm.visible_instance_count = 0
	l.mmi = MultiMeshInstance3D.new()
	l.mmi.name = "Port_" + key
	l.mmi.multimesh = l.mm
	if key == "pool" or key == "rope":
		l.mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l.mmi)
	l.cap = cap
	l.buf.resize(cap * 20)
	_layers[key] = l
	return l


## One instance of `key` at `xf` (TRUE world; made local here).
func _put(key: String, xf: Transform3D, color: Color = Color.WHITE, custom: Color = Color(0, 0, 0, 0)) -> void:
	var l := _layer(key)
	if l.n >= l.cap:
		return
	xf.origin = WorldState.to_local(xf.origin)
	var o := l.n * 20
	l.buf[o] = xf.basis.x.x
	l.buf[o + 1] = xf.basis.y.x
	l.buf[o + 2] = xf.basis.z.x
	l.buf[o + 3] = xf.origin.x
	l.buf[o + 4] = xf.basis.x.y
	l.buf[o + 5] = xf.basis.y.y
	l.buf[o + 6] = xf.basis.z.y
	l.buf[o + 7] = xf.origin.y
	l.buf[o + 8] = xf.basis.x.z
	l.buf[o + 9] = xf.basis.y.z
	l.buf[o + 10] = xf.basis.z.z
	l.buf[o + 11] = xf.origin.z
	l.buf[o + 12] = color.r
	l.buf[o + 13] = color.g
	l.buf[o + 14] = color.b
	l.buf[o + 15] = color.a
	l.buf[o + 16] = custom.r
	l.buf[o + 17] = custom.g
	l.buf[o + 18] = custom.b
	l.buf[o + 19] = custom.a
	l.n += 1


func _commit(_view: Vector3) -> void:
	var pr: Rect2 = plan.macro.port_rect.grow(120.0)
	var lo := WorldState.to_local(Vector3(pr.position.x, -20.0, pr.position.y))
	var aabb := AABB(lo, Vector3(pr.size.x, 120.0, pr.size.y))
	for l: Layer in _layers.values():
		l.mm.buffer = l.buf
		l.mm.visible_instance_count = l.n
		l.mmi.custom_aabb = aabb
		l.mmi.visible = l.n > 0


func _box(centre: Vector3, look: Array, basis: Basis = Basis()) -> void:
	var flip: bool = look[2] if look.size() > 2 else false
	var xf := Transform3D(basis, centre) * PortKit.container_xform(Vector3.ZERO, true, false, flip)
	_put("box", xf, look[0], look[1])


static func _heading(d: Vector2) -> Basis:
	var x := Vector3(d.x, 0.0, d.y).normalized()
	return Basis(x, Vector3.UP, x.cross(Vector3.UP))


func _pool(at: Vector3, size: float) -> void:
	_put("pool", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(size, 1.0, size)), at + Vector3(0.0, 0.07, 0.0)))


func _draw_crane(c: Dictionary, view: Vector3, night: bool, used: Dictionary) -> void:
	var base: Vector3 = c.base
	var pose := crane_pose(c, clock)
	var key := "sts_%d" % int(c.index)
	var step: int = pose.step
	var prev: int = _last_step.get(key, step)
	if prev != step:
		var steps: Array = c.halves[0]
		var ev: String = steps[prev].ev if prev < steps.size() else ""
		var at_l := WorldState.to_local(Vector3(base.x, pose.spreader_y, pose.trolley_z))
		if ev != "" and at_l.distance_to(WorldState.to_local(view)) < sound_range:
			Sfx.play("crane", at_l, -2.0 if ev == "latch" else 0.0)
	_last_step[key] = step
	var tz: float = pose.trolley_z
	var sy: float = pose.spreader_y
	_put("trolley", Transform3D(Basis(), Vector3(base.x, base.y, tz)))
	var rope_top := base.y + PortKit.STS_PORTAL_Y + PortKit.STS_GIRDER_D + 0.2
	_put("rope", Transform3D(Basis().scaled(Vector3(1.0, maxf(rope_top - (sy + 1.25), 0.1), 1.0)), Vector3(base.x, rope_top, tz)))
	_put("spreader", Transform3D(Basis(), Vector3(base.x, sy, tz)))
	_clank_spots.append(WorldState.to_local(Vector3(base.x, sy, tz)))
	if (pose.spreader_box as Array).size() > 0:
		_box(Vector3(base.x, sy - PortKit.H_STD * 0.5, tz), pose.spreader_box)
	for b: Array in pose.boxes:
		_box(b[0], b[1])
	# The work lights under the trolley light the hatch or the lane it works.
	if night:
		var ground := base.y if tz - base.z < PortKit.STS_GAUGE * 0.5 + 2.0 else (c.P.top as float)
		_pool(Vector3(base.x, ground, tz), 34.0)
	# The tractors.
	for ti in (pose.tractors as Array).size():
		var tr: Dictionary = pose.tractors[ti]
		var at: Array = path_at(c.loop, tr.s)
		var front: Array = path_at(c.loop, float(tr.s) + HITCH)
		var p2: Vector2 = at[0]
		if Vector2(view.x, view.z).distance_to(p2) > draw_range:
			continue
		var cb := _heading(at[1])
		var cpos := Vector3(p2.x, base.y, p2.y)
		var fp: Vector2 = front[0]
		var tpos := Vector3(fp.x, base.y, fp.y)
		# The tractor sits on the line from the chassis' kingpin forward.
		var tdir := (fp - p2)
		var tb := _heading(front[1]) if tdir.length() < 0.5 else _heading(tdir.normalized().lerp(front[1], 0.5))
		_put("chassis", Transform3D(cb, cpos))
		_put("tractor", Transform3D(tb, tpos))
		if (tr.look as Array).size() > 0:
			_box(cpos + Vector3(0.0, PortLifeKit.CHASSIS_BED + PortKit.H_STD * 0.5, 0.0), tr.look, cb)
		if night:
			_pool(tpos + tb.x * 9.0, 11.0)
		_body("%s_t%d" % [key, ti], "tractor", Transform3D(cb, cpos), Transform3D(tb, tpos), used)


func _draw_rtg(r: Dictionary, view: Vector3, used: Dictionary) -> void:
	var b: Vector3 = r.base
	var pose := rtg_pose(r, clock)
	var gx: float = pose.x
	if Vector2(view.x, view.z).distance_to(Vector2(gx, b.z)) > draw_range + 100.0:
		return
	var marker: Variant = r.get("marker")
	if marker == null or not is_instance_valid(marker):
		return
	var flip: bool = r.flip
	var basis := Basis(Vector3.UP, PI) if flip else Basis()
	var frame := Transform3D(basis, Vector3(gx, b.y, b.z))
	_put("rtg", frame)
	var tz: float = pose.z
	_put("rtg_trolley", Transform3D(basis, Vector3(gx, b.y, tz)))
	var sy: float = pose.y
	var rope_top := b.y + PortKit.RTG_H + 1.6
	_put("rope", Transform3D(Basis().scaled(Vector3(1.0, maxf(rope_top - (sy + 1.25), 0.1), 1.0)), Vector3(gx, rope_top, tz)))
	_put("spreader", Transform3D(Basis(), Vector3(gx, sy, tz)))
	# The box: in its pile (the batch draws it), on the spreader, or on the target pile.
	var src: Dictionary = r.src
	var key: int = (marker as Node).get_instance_id()
	if src.is_empty():
		_body("rtg_%d" % key, "rtg", frame, Transform3D(), used)
		return
	var away: bool = pose.where != "pile"
	if away and not _rtg_hidden.has(key):
		var node := _container_node(r)
		if node:
			MultiMeshBatch.hide_instance(node, int(src.index))
			_rtg_hidden[key] = {"node": node, "index": src.index, "xf": src.xf}
	elif not away and _rtg_hidden.has(key):
		_rtg_put_back(key)
	var look := [src.color, src.custom, false]
	var bxf: Transform3D = src.xf
	if pose.where == "spreader":
		_put("box", Transform3D(bxf.basis, Vector3(gx, sy - PortKit.H_STD * 0.5, tz)), look[0], look[1])
	elif pose.where == "dst":
		var d: Dictionary = r.dst
		_put("box", Transform3D(bxf.basis, Vector3(float(d.x), float(d.top) + PortKit.H_STD * 0.5, float(d.z))), look[0], look[1])
	var step: int = pose.step
	var skey := "rtg_%d" % key
	var prev: int = _last_step.get(skey, step)
	if prev != step:
		var ev: String = (r.steps[prev] as Dictionary).ev
		var at_l := WorldState.to_local(Vector3(gx, sy, tz))
		if ev != "" and at_l.distance_to(WorldState.to_local(view)) < sound_range * 0.7:
			Sfx.play("crane", at_l, -6.0, 1.15)
	_last_step[skey] = step
	_body("rtg_%d" % key, "rtg", frame, Transform3D(), used)


func _container_node(r: Dictionary) -> MultiMeshInstance3D:
	var ch: Variant = r.get("chunk")
	if ch == null or not is_instance_valid(ch):
		return null
	var nodes: Dictionary = (ch as Node).get("_mm_nodes")
	return nodes.get("container") as MultiMeshInstance3D if nodes else null


func _draw_straddles(lp: Dictionary, view: Vector3, eye: Vector3, night: bool, used: Dictionary) -> void:
	var path: Dictionary = lp.path
	for car: Dictionary in lp.cars:
		var s := clock * straddle_speed + float(car.offset)
		var at: Array = path_at(path, s)
		var p2: Vector2 = at[0]
		if Vector2(view.x, view.z).distance_to(p2) > draw_range:
			continue
		var basis := _heading(at[1])
		var pos := Vector3(p2.x, CityChunk.PORT_YARD_TOP, p2.y)
		_put("straddle", Transform3D(basis, pos))
		var look: Array = car.look
		var sy := PortLifeKit.SC_CARRY_Y if look.size() > 0 else PortLifeKit.SC_EMPTY_Y
		var top := PortLifeKit.SC_TOP - 0.6
		_put("rope", Transform3D(basis.scaled(Vector3(1.0, maxf(top - (sy + 1.25), 0.1), 1.0)), pos + Vector3(0.0, top, 0.0)))
		_put("spreader", Transform3D(basis, pos + Vector3(0.0, sy, 0.0)))
		if look.size() > 0:
			_box(pos + Vector3(0.0, sy - PortKit.H_STD * 0.5, 0.0), look, basis)
		if night:
			_pool(pos + basis.x * 10.0, 13.0)
		if Vector2(eye.x, eye.z).distance_to(p2) < body_range:
			_body("sc_" + String(car.id), "straddle", Transform3D(basis, pos), Transform3D(), used)


## The ship's deck at night: pools of light on the cargo of every bay and on the hatch ends.
func _draw_ship_lights(view: Vector3) -> void:
	var s := ship_anchor()
	if s.x == INF or Vector2(view.x, view.z).distance_to(s) > draw_range + 300.0:
		return
	for i in SHIP_BAYS:
		var x := s.x - 70.0 + i * 14.0
		var top := 0.0
		for b: Dictionary in ship_boxes():
			if int(b.bay) == i:
				top = maxf(top, (b.centre as Vector3).y + PortKit.H_STD * 0.5)
		_pool(Vector3(x, top, s.y), 20.0)
		if i < SHIP_BAYS - 1:
			_pool(Vector3(x + 7.0, PortKit.SHIP_CARGO_Y, s.y), 14.0)


# --- Bodies ------------------------------------------------------------------------------------

## A kinematic body for a machine near the player (props layer, mask 0, so it is hit and stood
## on but never pairs with anything itself), made on first use and moved each frame.
func _body(key: String, kind: String, xf: Transform3D, xf2: Transform3D, used: Dictionary) -> void:
	var eye := WorldState.to_world(_player.global_position)
	if Vector2(eye.x, eye.z).distance_to(Vector2(xf.origin.x, xf.origin.z)) > body_range:
		return
	used[key] = true
	var body: AnimatableBody3D = _bodies.get(key)
	var local := Transform3D(xf.basis, WorldState.to_local(xf.origin))
	if body == null:
		body = AnimatableBody3D.new()
		body.sync_to_physics = false
		body.collision_layer = 4
		body.collision_mask = 0
		body.name = "PortBody_" + key
		match kind:
			"straddle":
				for side: float in [-1.0, 1.0]:
					_shape(body, Vector3(PortLifeKit.SC_LEN, PortLifeKit.SC_TOP - 0.95, PortLifeKit.SC_HALF_W - PortLifeKit.SC_INNER), Vector3(0.0, 0.95 + (PortLifeKit.SC_TOP - 0.95) * 0.5, side * (PortLifeKit.SC_HALF_W + PortLifeKit.SC_INNER) * 0.5))
				_shape(body, Vector3(PortLifeKit.SC_LEN, 1.2, PortLifeKit.SC_HALF_W * 2.0), Vector3(0.0, PortLifeKit.SC_TOP - 0.6, 0.0))
			"tractor":
				_shape(body, Vector3(PortLifeKit.CHASSIS_LEN, 1.4, 2.5), Vector3(0.0, 0.75, 0.0))
				var tr := CollisionShape3D.new()
				tr.name = "Tractor"
				var bs := BoxShape3D.new()
				bs.size = Vector3(PortLifeKit.TT_LEN, 2.9, 2.6)
				tr.shape = bs
				body.add_child(tr)
			"rtg":
				for s: Array in PortKit.rtg_shapes():
					var cs := CollisionShape3D.new()
					var bx := BoxShape3D.new()
					bx.size = s[0]
					cs.shape = bx
					cs.transform = s[1]
					body.add_child(cs)
		body.transform = local
		add_child(body)
		_bodies[key] = body
	else:
		body.transform = local
	if kind == "tractor":
		var tr := body.get_node_or_null("Tractor") as CollisionShape3D
		if tr:
			var rel := xf.affine_inverse() * xf2
			tr.transform = Transform3D(rel.basis, rel.origin + Vector3(0.0, 1.5, 0.0))


func _shape(body: Node, size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = at
	body.add_child(cs)
