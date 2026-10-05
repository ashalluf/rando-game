class_name TowerGondolas
extends RefCounted
## Window-washing gondolas on downtown's glass towers (fleet wave 2, "tower-gondolas"): a
## suspended platform (a cradle) with two workers in hard hats hanging on four wire ropes from a
## roof davit pair or a building maintenance unit's jib, working its way slowly down a face - a
## floor down, a stop to wash, the next floor - with the washed glass running wet behind it; and
## davit arms and parked BMUs on the roofs.
##
## Where (pure, hashes of seed + place, never a chunk / block / Building rng):
##   - the LANDMARK towers (LandmarkDowntown): every flat prism tier's long, straight faces
##     (TowerMesh.tiers, the outlines as built) are candidates: a roof behind the edge, nothing
##     standing on the davit spot, the column outside the face clear of every other tier down to
##     where the drop ends (TowerMesh's collision hulls), the drop carried down through flush tiers
##     below. `landmark_sites()` picks up to MAX_PER_TOWER by hash, a parked BMU on another face of
##     some, and `stowed davits` in a row along a hung face;
##   - the tall core INFILL: Rooftops' window-washing machine on a glass tower with its cradle out
##     on the facade (`"bmu"`, `hang`) hands its jib over (`building_bmu()`): Rooftops then draws
##     the machine without its static cradle and this draws the cradle live under the jib.
## The motion is worked out from the physics clock (`clock()`), never ticked: a drop washed floor
## by floor from the top, the cradle winched back up and moved to the next lane (`pose_at()`).
## Everything moving and the workers are built only near the camera (GondolaRig, the node that
## stands at each site): BUILD_RANGE for the cradle, ropes and streaks, WORKER_RANGE for the
## people; nothing at all past them. The cradle is an AnimatableBody3D on the props layer
## ("rail_vehicle": rounds spark off it): a round or a blast swings it (`GondolaRig.take_hit()`)
## and the workers drop to a crouch and hang on to the rail. GONDOLAS=0 in the environment turns
## it all off (the A/B), and Rooftops draws its static cradle again.

static var enabled: bool = OS.get_environment("GONDOLAS") != "0"

const SALT := "tower gondolas"
## Landmark sites: at most this many hung cradles a tower; the share of towers with one at all;
## the share with a parked BMU on another face.
const MAX_PER_TOWER := 2
const TOWER_SHARE := 0.85
const PARKED_BMU_SHARE := 0.5
## A face must be this long (m) to hang a cradle on, and drop at least this far.
const MIN_FACE := 7.0
const MIN_DROP := 24.0
## The cradle: length (m), its gap off the glass (cradle centre to the wall), its rail height.
const CRADLE_LEN := 4.6
const GAP := 0.62
const RAIL_Y := 1.07
const HALF_DEPTH := 0.36
## Davits: how far the head stands out past the facade line and over the parapet top (m); the
## base sits this far in from the edge.
const DAVIT_OUT := 0.95
const DAVIT_RISE := 2.3
const DAVIT_IN := 1.1
## Lanes along a davit face (m between lanes).
const LANE_PITCH := 5.2
## The descent: a floor at a time (m), its speed (m/s), the stop to wash it (s); the winch back up
## (m/s) and the move to the next lane (s).
const STEP := 3.6
const DOWN_SPEED := 0.22
const WASH_SECONDS := 34.0
const UP_SPEED := 0.9
const MOVE_SECONDS := 90.0
## Near the camera only: the cradle (m), the people on it (m); built at most this many at once.
const BUILD_RANGE := 420.0
const WORKER_RANGE := 160.0
const MAX_LIVE := 6
const MAX_WORKERS := 4
## The invented contractor on the cradle's back panel (never a real company's name).
const COMPANY := "BASIN HEIGHTS WINDOW CO."
## Cradle paints (sRGB as written): safety yellow, bare aluminium, white.
const PAINTS := [Color(0.86, 0.70, 0.18), Color(0.70, 0.71, 0.72), Color(0.88, 0.88, 0.86)]
const DARK := Color(0.16, 0.17, 0.18)
const STEEL := Color(0.46, 0.48, 0.50)
const HOSE := Color(0.10, 0.22, 0.45)
const ROPE_ORANGE := Color(0.95, 0.42, 0.08)
## Hard hats (sRGB): white, yellow, orange.
const HATS := [Color(0.93, 0.93, 0.90), Color(0.90, 0.72, 0.10), Color(0.92, 0.42, 0.10)]
## The workers' rigs: trousers, short hair (the hard hat goes over it). crowd_s already wears a
## hi-vis vest.
const WORKER_MODELS := [
	"res://assets/models/crowd_a.glb",
	"res://assets/models/crowd_d.glb",
	"res://assets/models/crowd_f.glb",
	"res://assets/models/crowd_h.glb",
	"res://assets/models/crowd_j.glb",
	"res://assets/models/crowd_s.glb",
]
## Workwear: a grey-blue work shirt or a hi-vis orange tee over dark work trousers (hsv).
const SHIRTS := [Color(0.38, 0.44, 0.52), Color(0.95, 0.45, 0.10), Color(0.30, 0.32, 0.34)]
const TROUSERS := Color(0.16, 0.17, 0.19)

## The clock override for stills and tests: GONDOLA_T=<seconds>.
static var clock_override: float = float(OS.get_environment("GONDOLA_T")) if OS.get_environment("GONDOLA_T") != "" else -1.0
## Rigs built (cradles live) and workers live right now (GondolaRig counts them).
static var live: int = 0
static var workers_live: int = 0

static var _site_cache: Dictionary = {}
static var _hat_meshes: Dictionary = {}
static var _hat_mats: Dictionary = {}
static var _cradle_meshes: Dictionary = {}
static var _davit_mesh: ArrayMesh = null
static var _unit_cyl: CylinderMesh = null
static var _rope_mats: Dictionary = {}
static var _streak_mat: ShaderMaterial = null
static var _uniform_mats: Dictionary = {}
static var _tool_mesh: ArrayMesh = null


static func _h(seed_value: int, tag: String, i: int = 0) -> float:
	return float(absi(hash([seed_value, SALT, tag, i])) % 100003) / 100003.0


## Seconds on the shared clock (physics time; GONDOLA_T sets it).
static func clock() -> float:
	if clock_override >= 0.0:
		return clock_override
	return float(Engine.get_physics_frames()) / float(maxi(Engine.physics_ticks_per_second, 1))


# --- Sites ---------------------------------------------------------------------------------

## A site, in its parent's local frame (the tower's anchor or the Building):
##   m       Vector3 a point on the facade line at the parapet top (the lanes are offsets along t)
##   n, t    outward normal and along (horizontal, unit)
##   lanes   offsets along t the cradle works in, in a hashed order
##   roof    the roof surface's height behind the edge (davit bases)
##   top     the cradle floor's highest height, bottom its lowest
##   support 0 davits, 1 a BMU jib (head points given)
##   heads   for a BMU: [left, right] head points (parent frame), else []
##   paint   cradle paint index; seed; phase (s)
static func _site(m: Vector3, n: Vector3, lanes: Array, roof: float, top: float, bottom: float, seed_value: int) -> Dictionary:
	return {"m": m, "n": n, "t": Vector3(-n.z, 0.0, n.x), "lanes": lanes, "roof": roof, "top": top, "bottom": bottom,
		"support": 0, "heads": [], "seed": seed_value,
		"paint": int(_h(seed_value, "paint") * PAINTS.size()) % PAINTS.size(),
		"phase": _h(seed_value, "phase") * 86400.0}


## The hung cradles and parked machines of LandmarkDowntown tower `id` (tower-local metres).
## {"hung": [site...], "parked": [{"m", "n", "roof"}...], "stowed": [{"p", "n"}...]}. Pure.
static func landmark_sites(id: String, seed_value: int) -> Dictionary:
	var key := "%s|%d" % [id, seed_value]
	if _site_cache.has(key):
		return _site_cache[key]
	var out := {"hung": [], "parked": [], "stowed": []}
	_site_cache[key] = out
	if not LandmarkDowntown.TOWERS.has(id):
		return out
	var t := LandmarkDowntown.tower(id)
	var tiers: Array = t.get("tiers", [])
	var hulls := _hull_boxes(t.get("hulls", []))
	var cands := faces(tiers, hulls, id)
	if cands.is_empty():
		return out
	var s0 := hash([seed_value, SALT, id])
	if _h(s0, "tower") >= TOWER_SHARE:
		return out
	# A hashed order of the faces; the first MAX_PER_TOWER get a cradle, the next one a parked BMU.
	var order: Array = range(cands.size())
	for i in range(order.size() - 1, 0, -1):
		var j := absi(hash([s0, "order", i])) % (i + 1)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var want := 1 + int(_h(s0, "count") * float(MAX_PER_TOWER))
	var used_n: Array[Vector3] = []
	for k in order:
		var f: Dictionary = cands[k]
		var dup := false
		for un in used_n:
			if un.dot(f.n) > 0.99:
				dup = true
		if dup:
			continue
		if out.hung.size() < want:
			var sd := hash([s0, "site", k])
			var lanes: Array = []
			var room: float = f.half - CRADLE_LEN * 0.5 - 0.9
			var count := maxi(1, int(floorf(room * 2.0 / LANE_PITCH)) + 1)
			for i in count:
				lanes.append(-room + float(i) * LANE_PITCH if count > 1 else 0.0)
			# Drop after drop along the face from a hashed lane, as a crew works a building.
			var start := absi(hash([sd, "lane"])) % lanes.size()
			var ordered: Array = []
			for i in lanes.size():
				ordered.append(lanes[(start + i) % lanes.size()])
			var s := _site(f.m, f.n, ordered, f.roof, f.para - 4.2, f.bottom + 2.0, sd)
			s.mid = f.mid
			out.hung.append(s)
			used_n.append(f.n)
			# Stowed davit bases along the rest of the face (the crew moves the arms lane to lane).
			for i in lanes.size():
				out.stowed.append({"p": f.m + s.t * float(lanes[i]) - f.n * DAVIT_IN + Vector3(0, f.roof - f.m.y, 0), "n": f.n})
		elif out.parked.is_empty() and _h(s0, "parked") < PARKED_BMU_SHARE and f.depth >= 7.0 and (absf(f.n.x) > 0.999 or absf(f.n.z) > 0.999):
			out.parked.append({"m": f.m, "n": f.n, "roof": f.roof, "mid": f.mid})
			used_n.append(f.n)
	return out


## Every face of `tiers` a cradle can hang on: [{"m" (edge midpoint at the parapet top), "n",
## "half" (half its length), "roof", "para", "bottom", "depth" (roof behind the edge), "mid"}].
static func faces(tiers: Array, hulls: Array, id: String = "") -> Array:
	var out: Array = []
	var pad := Rect2()
	if id != "" and LandmarkDowntown.TOWERS[id].has("helipad"):
		var hp: Array = LandmarkDowntown.TOWERS[id].helipad
		var c: Vector3 = hp[0]
		var d: float = float(hp[1]) + 4.0
		pad = Rect2(Vector2(c.x, c.z) - Vector2(d, d) * 0.5, Vector2(d, d))
	for ti in tiers.size():
		var tier: Array = tiers[ti]
		var outline: PackedVector2Array = tier[0]
		var y0: float = tier[1]
		var y1: float = tier[2]
		if not bool(tier[3]) or bool(tier[4]) or y1 - y0 < 8.0:
			continue
		var para := y1 + TowerMesh.PARAPET_HEIGHT
		var nv := outline.size()
		for i in nv:
			var a := outline[i]
			var b := outline[(i + 1) % nv]
			var len := a.distance_to(b)
			if len < MIN_FACE:
				continue
			var t2 := (b - a) / len
			var n2 := Vector2(t2.y, -t2.x)
			var mid := (a + b) * 0.5
			if Geometry2D.is_point_in_polygon(mid + n2 * 0.4, outline):
				n2 = -n2
			if Geometry2D.is_point_in_polygon(mid + n2 * 0.4, outline) or not Geometry2D.is_point_in_polygon(mid - n2 * 0.4, outline):
				continue
			# Roof behind the edge, deep enough for a davit base (and a BMU's rails).
			var depth := 0.0
			while depth < 12.0 and Geometry2D.is_point_in_polygon(mid - n2 * (depth + 1.0), outline):
				depth += 1.0
			if depth < 3.0:
				continue
			# Nothing stands on the davit spots (a crown, the next tier, a lantern).
			var base := mid - n2 * DAVIT_IN
			var ok := true
			for s: float in [-1.0, 0.0, 1.0]:
				var p := base + t2 * s * maxf(len * 0.5 - 1.5, 0.0)
				if _blocked(hulls, p, y1 + 0.3, y1 + 4.5):
					ok = false
			if pad.has_area() and pad.has_point(base):
				ok = false
			if not ok:
				continue
			# The drop: down through flush tiers below, never into anything standing out of the face.
			var bottom := y0
			var carried := true
			while carried:
				carried = false
				for uj in tiers.size():
					var u: Array = tiers[uj]
					if absf(float(u[2]) - bottom) > 0.6 or bool(u[4]):
						continue
					if _flush(u[0], mid, n2, len * 0.5):
						bottom = float(u[1])
						carried = true
						break
			var col_lo := bottom
			for hb: Array in hulls:
				var lo_y: float = hb[1]
				var hi_y: float = hb[2]
				if hi_y <= bottom or lo_y >= y1 - 1.0:
					continue
				for s: float in [-1.0, 0.0, 1.0]:
					var q := mid + n2 * (GAP + 0.3) + t2 * s * (len * 0.5 - 0.5)
					if Geometry2D.is_point_in_polygon(q, hb[0]):
						col_lo = maxf(col_lo, hi_y + 1.0)
			if para - 4.2 - (col_lo + 2.0) < MIN_DROP:
				continue
			out.append({"m": Vector3(mid.x, para, mid.y), "n": Vector3(n2.x, 0.0, n2.y), "half": len * 0.5, "roof": y1,
				"para": para, "bottom": col_lo, "depth": depth, "mid": Vector3(mid.x, y1, mid.y)})
	return out


## [2D convex outline, y low, y high] of each collision hull.
static func _hull_boxes(hulls: Array) -> Array:
	var out: Array = []
	for hull: PackedVector3Array in hulls:
		if hull.is_empty():
			continue
		var pts := PackedVector2Array()
		var lo := INF
		var hi := -INF
		for p in hull:
			pts.append(Vector2(p.x, p.z))
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		var ch := Geometry2D.convex_hull(pts)
		if ch.size() >= 3:
			out.append([ch, lo, hi])
	return out


static func _blocked(hulls: Array, p: Vector2, y_lo: float, y_hi: float) -> bool:
	for hb: Array in hulls:
		if float(hb[2]) <= y_lo or float(hb[1]) >= y_hi:
			continue
		if Geometry2D.is_point_in_polygon(p, hb[0]):
			return true
	return false


## Whether `outline` has an edge on the line through `mid` with normal `n2` covering +-`half`.
static func _flush(outline: PackedVector2Array, mid: Vector2, n2: Vector2, half: float) -> bool:
	var nv := outline.size()
	var t2 := Vector2(-n2.y, n2.x)
	for i in nv:
		var a := outline[i]
		var b := outline[(i + 1) % nv]
		if absf((a - mid).dot(n2)) > 0.3 or absf((b - mid).dot(n2)) > 0.3:
			continue
		var sa := (a - mid).dot(t2)
		var sb := (b - mid).dot(t2)
		if minf(sa, sb) <= -half + 0.5 and maxf(sa, sb) >= half - 0.5:
			return true
	return false


# --- The motion ----------------------------------------------------------------------------

## Where the cradle is at clock `t`: {"lane" (offset along t), "y" (floor height), "moving" (0
## washing, 1 lowering, 2 winching up / moving lanes), "washed" (metres washed above it in this
## drop)}. Pure.
static func pose_at(site: Dictionary, t: float) -> Dictionary:
	var top: float = site.top
	var bottom: float = site.bottom
	var drop := maxf(top - bottom, 0.0)
	var stops := maxi(int(ceilf(drop / STEP)), 1)
	var step := drop / float(stops)
	var per := step / DOWN_SPEED + WASH_SECONDS
	var up := drop / UP_SPEED
	var cycle := float(stops) * per + up + MOVE_SECONDS
	var tt: float = t + float(site.phase)
	var k := int(floorf(tt / cycle))
	var u := tt - float(k) * cycle
	var lanes: Array = site.lanes
	var lane: float = lanes[k % lanes.size()] if not lanes.is_empty() else 0.0
	var out := {"lane": lane, "y": top, "moving": 0, "washed": 0.0, "step": 0.0}
	if u < float(stops) * per:
		var i := int(floorf(u / per))
		var w := u - float(i) * per
		if w < WASH_SECONDS:
			out.y = top - float(i) * step
			out.moving = 0
			out.step = w / WASH_SECONDS
		else:
			out.y = top - float(i) * step - (w - WASH_SECONDS) * DOWN_SPEED
			out.moving = 1
		out.washed = top - float(out.y) + (step * out.step if out.moving == 0 else 0.0)
	elif u < float(stops) * per + up:
		out.y = bottom + (u - float(stops) * per) * UP_SPEED
		out.moving = 2
	else:
		out.y = top
		out.moving = 2
	out.y = clampf(out.y, bottom, top)
	return out


# --- Hooks ---------------------------------------------------------------------------------

## LandmarkDowntown.build() (detailed): the sites of tower `id`, anchored at `at` under `parent`.
static func landmark(parent: Node3D, at: Vector3, id: String) -> void:
	if not enabled:
		return
	var seed_value := _world_seed(parent)
	var sites := landmark_sites(id, seed_value)
	if sites.hung.is_empty() and sites.parked.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Gondolas_" + id
	holder.position = at
	parent.add_child(holder)
	# The davits and the parked machines: static, on the roof, one mesh.
	var g := RooftopGeo.new()
	for s: Dictionary in sites.stowed:
		_davit_base(g, s.p, s.n)
	for p: Dictionary in sites.parked:
		var nrm2 := Vector2(p.n.x, p.n.z)
		var side := 0
		for k in 4:
			if Rooftops._side_normal(k).dot(nrm2) > 0.99:
				side = k
		var f := {"side": side, "reach": DAVIT_IN + 0.9, "hang": false}
		var o: Vector3 = p.mid - p.n * (DAVIT_IN + 0.9)
		Rooftops._bmu(g, f, o, {})
	_commit_static(holder, g, "RoofKit")
	for s: Dictionary in sites.hung:
		var rig := GondolaRig.new()
		rig.name = "GondolaRig"
		rig.site = s
		holder.add_child(rig)


## Rooftops.build(): a window-washing machine whose cradle is out on the facade. Its jib heads
## carry a live cradle instead of the static one. `origin` is the machine's spot (building frame).
static func building_bmu(b: Node3D, f: Dictionary, origin: Vector3, p: Dictionary) -> void:
	if not enabled or not f.get("hang", false):
		return
	var nrm2 := Rooftops._side_normal(int(f.side))
	var n := Vector3(nrm2.x, 0.0, nrm2.y)
	var yaw := atan2(nrm2.x, nrm2.y)
	var xf := Transform3D(Basis(Vector3.UP, yaw), origin)
	var reach: float = f.reach
	var top: float = float(p.top) - 1.0
	# The drop runs down past every part the column outside the face does not meet (a flush or
	# set-back tier below) to the first roof it would land on, or the street.
	var col := xf * Vector3(0.3, 0.0, reach + GAP)
	var along := Vector3(-n.z, 0.0, n.x)
	var bottom := 1.5
	var parts: Array = b.get("parts")
	for i in parts.size():
		if i == int(p.part):
			continue
		var part: Dictionary = parts[i]
		var pc: Vector3 = part.center
		var ps: Vector3 = part.size
		var ptop := pc.y + ps.y * 0.5
		if ptop >= top:
			continue
		var r := Rect2(Vector2(pc.x, pc.z) - Vector2(ps.x, ps.z) * 0.5, Vector2(ps.x, ps.z)).grow(0.4)
		for e: float in [-CRADLE_LEN * 0.5, 0.0, CRADLE_LEN * 0.5]:
			var q := col + along * e
			if r.has_point(Vector2(q.x, q.z)):
				bottom = maxf(bottom, ptop + 1.0)
	if OS.get_environment("GONDOLA_DEBUG") == "1":
		print("GONDOLA bmu top %.1f bottom %.1f" % [top, bottom])
	if top - bottom < 4.0:
		return
	var seed_value := hash([int(b.get("seed")), SALT, "bmu"])
	var m := xf * Vector3(0.3, float(p.top) + float(p.get("rise", 0.0)) - origin.y, reach)
	var s := _site(m, n, [0.0], float(p.top), top, bottom, seed_value)
	s.support = 1
	s.heads = [xf * Vector3(0.3 - 1.2, 2.7, reach + 0.9), xf * Vector3(0.3 + 1.2, 2.7, reach + 0.9)]
	var rig := GondolaRig.new()
	rig.name = "GondolaRig"
	rig.site = s
	b.add_child(rig)


static func _world_seed(node: Node) -> int:
	if node.is_inside_tree():
		var scene := node.get_tree().current_scene
		if scene != null and "world_seed" in scene:
			return int(scene.get("world_seed"))
	return 1337


# --- Geometry ------------------------------------------------------------------------------

static func _commit_static(parent: Node3D, g: RooftopGeo, node_name: String) -> MeshInstance3D:
	var arr := g.arrays()
	if arr.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, Rooftops.material())
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.visibility_range_end = Rooftops.DRAW_DISTANCE
	mi.visibility_range_end_margin = 40.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	return mi


## A davit socket on the roof with its arm stowed flat beside it (the crew carries the arms lane
## to lane): a bolted base plate, a socket, the arm lying along the parapet.
static func _davit_base(g: RooftopGeo, p: Vector3, n: Vector3) -> void:
	g.xf = Transform3D(Basis(Vector3.UP, atan2(n.x, n.z)), p)
	g.box(Vector3(0, 0.03, 0), Vector3(0.7, 0.06, 0.7), STEEL, 1)
	g.cyl(Vector3(0, 0.06, 0), 0.11, 0.11, 0.42, 10, DARK, 1)
	for s in [Vector2(-0.27, -0.27), Vector2(0.27, -0.27), Vector2(0.27, 0.27), Vector2(-0.27, 0.27)]:
		g.cyl(Vector3(s.x, 0.06, s.y), 0.025, 0.025, 0.04, 6, DARK, 1)
	g.xf = Transform3D.IDENTITY


## One working davit, in a frame with +z out over the edge and y up from the roof: base plate,
## mast, the arm reaching out over the parapet, the sheave head and a ratchet winch.
static func davit_mesh() -> ArrayMesh:
	if _davit_mesh != null:
		return _davit_mesh
	var g := RooftopGeo.new()
	var white := Color(0.88, 0.88, 0.86)
	g.box(Vector3(0, 0.03, 0), Vector3(0.7, 0.06, 0.7), STEEL, 1)
	g.cyl(Vector3(0, 0.06, 0), 0.11, 0.11, 0.42, 10, DARK, 1)
	for s in [Vector2(-0.27, -0.27), Vector2(0.27, -0.27), Vector2(0.27, 0.27), Vector2(-0.27, 0.27)]:
		g.cyl(Vector3(s.x, 0.06, s.y), 0.025, 0.025, 0.04, 6, DARK, 1)
	var head_z := DAVIT_IN + DAVIT_OUT
	var top := TowerMesh.PARAPET_HEIGHT + DAVIT_RISE
	g.cyl(Vector3(0, 0.45, 0), 0.085, 0.075, top - 0.25 - 0.45, 12, white, 0)
	# The arm: up and out in a curve over the parapet to the head.
	var prev := Vector3(0, top - 0.25, 0)
	for k in range(1, 7):
		var f := float(k) / 6.0
		var p := Vector3(0, top - 0.25 + sin(f * PI * 0.5) * 0.25, head_z * f)
		g.beam(prev, p, 0.13, 0.15, white, 0)
		prev = p
	g.box(Vector3(0, top - 0.05, head_z), Vector3(0.16, 0.3, 0.3), DARK, 1)
	g.cyl(Vector3(-0.09, top - 0.12, head_z), 0.13, 0.13, 0.04, 12, STEEL, 1)
	# The winch on the mast and its handle.
	g.box(Vector3(0, 1.0, -0.16), Vector3(0.22, 0.3, 0.16), Color(0.86, 0.70, 0.18), 0)
	g.beam(Vector3(0.12, 1.0, -0.2), Vector3(0.32, 1.05, -0.32), 0.03, 0.03, DARK, 1)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g.arrays())
	mesh.surface_set_material(0, Rooftops.material())
	_davit_mesh = mesh
	return mesh


## The cradle (frame: origin at the floor's centre, x along the face, +z away from the glass, y
## up): grating floor and toe boards, a top and mid rail round it, mesh panels on the outer side
## with the contractor's name, an end stirrup at each end carrying its traction hoist and the rope
## entries, rubber rollers against the glass, a bucket, a coiled hose and a spare squeegee.
static func cradle_mesh(paint: int) -> ArrayMesh:
	if _cradle_meshes.has(paint):
		return _cradle_meshes[paint]
	var g := RooftopGeo.new()
	var col: Color = PAINTS[paint]
	var hl := CRADLE_LEN * 0.5
	var hd := HALF_DEPTH
	# Floor: grating on two longitudinal channels; toe boards round it.
	g.box(Vector3(0, 0.02, 0), Vector3(CRADLE_LEN, 0.04, hd * 2.0), Color(0.48, 0.49, 0.50), 16, false)
	for z in [-hd + 0.03, hd - 0.03]:
		g.box(Vector3(0, -0.04, z), Vector3(CRADLE_LEN, 0.08, 0.06), col, 0, false)
		g.box(Vector3(0, 0.1, z), Vector3(CRADLE_LEN, 0.15, 0.02), col, 0)
	for x in [-hl + 0.01, hl - 0.01]:
		g.box(Vector3(x, 0.1, 0), Vector3(0.02, 0.15, hd * 2.0), col, 0)
	# Rails and posts.
	for z in [-hd, hd]:
		g.beam(Vector3(-hl, RAIL_Y, z), Vector3(hl, RAIL_Y, z), 0.045, 0.045, col, 0)
		g.beam(Vector3(-hl, 0.56, z), Vector3(hl, 0.56, z), 0.035, 0.035, col, 0)
		for k in 5:
			var x := -hl + float(k) * CRADLE_LEN / 4.0
			g.box(Vector3(x, RAIL_Y * 0.5 + 0.02, z), Vector3(0.045, RAIL_Y, 0.045), col, 0)
	for x in [-hl, hl]:
		g.beam(Vector3(x, RAIL_Y, -hd), Vector3(x, RAIL_Y, hd), 0.045, 0.045, col, 0)
	# The outer side's mesh panels and the name board.
	g.quad2(Vector3(-hl + 0.04, 0.18, hd + 0.01), Vector3(hl - 0.04, 0.18, hd + 0.01), Vector3(hl - 0.04, RAIL_Y - 0.04, hd + 0.01),
		Vector3(-hl + 0.04, RAIL_Y - 0.04, hd + 0.01), Vector3(0, 0, 1), STEEL, 4,
		Vector2(0, 0), Vector2(CRADLE_LEN, 0), Vector2(CRADLE_LEN, 0.9), Vector2(0, 0.9))
	g.box(Vector3(0, 0.84, hd + 0.03), Vector3(2.9, 0.26, 0.02), Color(0.92, 0.92, 0.90), 0)
	g.text(COMPANY, 0.11, Vector3(-1.36, 0.79, hd + 0.045), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Color(0.08, 0.16, 0.36), 0)
	# The end stirrups: a frame up to the rope entries, the hoist inside, the control box.
	for sx in [-1.0, 1.0]:
		var x: float = sx * (hl + 0.12)
		for z in [-hd, hd]:
			g.beam(Vector3(sx * hl, 0.04, z), Vector3(x, 0.3, z), 0.05, 0.05, col, 0)
			g.beam(Vector3(x, 0.3, z), Vector3(x, 1.85, z * 0.25), 0.05, 0.05, col, 0)
		g.beam(Vector3(x, 1.85, -hd * 0.25), Vector3(x, 1.85, hd * 0.25), 0.06, 0.06, col, 0)
		g.box(Vector3(x, 1.97, 0), Vector3(0.12, 0.18, 0.2), DARK, 1)
		g.box(Vector3(x, 1.25, 0), Vector3(0.3, 0.46, 0.34), Color(0.22, 0.24, 0.26), 1)
		g.cyl(Vector3(x, 1.48, 0.0), 0.12, 0.12, 0.08, 12, Color(0.12, 0.13, 0.14), 1)
		g.box(Vector3(x - sx * 0.02, 0.7, hd - 0.08), Vector3(0.22, 0.28, 0.12), Color(0.80, 0.80, 0.78), 0)
		# Rollers against the glass.
		for y in [0.28, 1.0]:
			g.box(Vector3(sx * (hl - 0.18), y, -hd - 0.08), Vector3(0.05, 0.05, 0.16), DARK, 1)
			g.cyl(Vector3(sx * (hl - 0.18), y - 0.06, -hd - 0.17), 0.06, 0.06, 0.12, 10, Color(0.05, 0.05, 0.05), 1, true)
	# The bucket, the hose coil, a spare squeegee on the floor.
	g.cyl(Vector3(-0.35, 0.04, 0.12), 0.15, 0.17, 0.32, 12, Color(0.92, 0.92, 0.90), 0, true, false)
	g.cyl(Vector3(-0.35, 0.33, 0.12), 0.145, 0.145, 0.0, 12, Color(0.40, 0.55, 0.62), 0)
	for k in 3:
		g.cyl(Vector3(0.75, 0.04 + float(k) * 0.035, 0.1), 0.22 - float(k) * 0.01, 0.22 - float(k) * 0.01, 0.03, 14, HOSE, 0, false, true)
	g.beam(Vector3(1.2, 0.07, -0.2), Vector3(1.75, 0.07, 0.15), 0.03, 0.03, Color(0.75, 0.75, 0.76), 1)
	g.box(Vector3(1.78, 0.07, 0.17), Vector3(0.36, 0.05, 0.05), DARK, 1)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g.arrays())
	mesh.surface_set_material(0, Rooftops.material())
	_cradle_meshes[paint] = mesh
	return mesh


## A squeegee on a short pole: in a frame with the hand at the origin, the pole along +y, the
## blade across x at its end. And the strip washer is the same pole's other half.
static func tool_mesh() -> ArrayMesh:
	if _tool_mesh != null:
		return _tool_mesh
	var g := RooftopGeo.new()
	g.cyl(Vector3(0, -0.12, 0), 0.016, 0.016, 0.75, 8, Color(0.75, 0.76, 0.78), 1, true)
	g.box(Vector3(0, 0.66, 0), Vector3(0.36, 0.05, 0.035), DARK, 1)
	g.box(Vector3(0, 0.69, 0), Vector3(0.35, 0.015, 0.012), Color(0.05, 0.05, 0.05), 1)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g.arrays())
	mesh.surface_set_material(0, Rooftops.material())
	_tool_mesh = mesh
	return mesh


## A unit cylinder (radius 1, height 1, centred) the ropes are drawn with, stretched per frame.
static func unit_cylinder() -> CylinderMesh:
	if _unit_cyl == null:
		_unit_cyl = CylinderMesh.new()
		_unit_cyl.top_radius = 1.0
		_unit_cyl.bottom_radius = 1.0
		_unit_cyl.height = 1.0
		_unit_cyl.radial_segments = 6
		_unit_cyl.rings = 1
		_unit_cyl.cap_top = false
		_unit_cyl.cap_bottom = false
	return _unit_cyl


static func rope_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _rope_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.55
		m.metallic = 0.6 if color.s < 0.2 else 0.0
		_rope_mats[key] = m
	return _rope_mats[key]


static func streak_material() -> ShaderMaterial:
	if _streak_mat == null:
		_streak_mat = ShaderMaterial.new()
		_streak_mat.shader = load("res://shaders/gondola_streaks.gdshader")
	return _streak_mat


# --- The workers ---------------------------------------------------------------------------

## Workwear through the character shader's garment split, cached per texture and shirt.
static func uniform_material(albedo: Texture2D, shirt: int) -> ShaderMaterial:
	var key := "%d_%d" % [albedo.get_instance_id(), shirt]
	if _uniform_mats.has(key):
		return _uniform_mats[key]
	var base := Pedestrian.character_material(albedo, 1)
	if base == null:
		return null
	var mat := base.duplicate() as ShaderMaterial
	var top: Color = SHIRTS[shirt]
	mat.set_shader_parameter("cloth_hue", top.h)
	mat.set_shader_parameter("cloth_sat", top.s)
	mat.set_shader_parameter("cloth_value", top.v)
	mat.set_shader_parameter("cloth_strength", 0.95)
	mat.set_shader_parameter("pants_hue", TROUSERS.h)
	mat.set_shader_parameter("pants_sat", TROUSERS.s)
	mat.set_shader_parameter("pants_value", TROUSERS.v)
	mat.set_shader_parameter("pants_strength", 0.95)
	mat.set_shader_parameter("hair_strength", 0.0)
	mat.set_shader_parameter("skin_tint", Color(1, 1, 1))
	mat.set_shader_parameter("cloth_roughness", 0.85)
	mat.set_shader_parameter("cloth_shade_keep", 0.45)
	_uniform_mats[key] = mat
	return mat


## A hard hat round the rig's own head (CrowdHatTable via CrowdHat.head_for, FireHelmet's shell):
## a smooth shell with a centre ridge and a short peak at the front, a narrow rim round the rest.
static func hat_mesh(rig: String) -> ArrayMesh:
	if _hat_meshes.has(rig):
		return _hat_meshes[rig]
	var h := CrowdHat.head_for(rig)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 32
	var rows := 9
	var grid: Array = []
	var edge: Array[Vector3] = []
	for j in cols + 1:
		var th := TAU * float(j) / float(cols)
		var ph0 := h.phi_at_height(th, FireHelmet.edge_y(h, th) + 0.008)
		var col: Array[Vector3] = []
		for i in rows + 1:
			var f := float(i) / float(rows)
			col.append(FireHelmet.shell_point(h, th, lerpf(ph0, PI * 0.5 - 0.02, f * f * 0.3 + f * 0.7), -0.004))
		grid.append(col)
		edge.append(col[0])
	var center := h.c
	var white := Color(1, 1, 1)
	for j in cols:
		for i in rows:
			FireHelmet._quad(st, grid[j][i], grid[j + 1][i], grid[j + 1][i + 1], grid[j][i + 1], white, center, true)
	var top := FireHelmet.shell_point(h, 0.0, PI * 0.5, -0.004)
	for j in cols:
		FireHelmet._tri(st, grid[j][rows], grid[j + 1][rows], top, white, center, true)
	# The rim: a short peak in front (azimuth 0 is the face), a narrow lip elsewhere.
	var tip: Array[Vector3] = []
	for j in cols + 1:
		var th := TAU * float(j) / float(cols)
		var front := pow(maxf(cos(th), 0.0), 2.0)
		var w := lerpf(0.012, 0.062, front)
		var out := Vector3(sin(th), 0.0, cos(th))
		tip.append(edge[j] + out * w + Vector3.DOWN * (0.004 + 0.012 * front))
	for j in cols:
		FireHelmet._quad(st, edge[j], edge[j + 1], tip[j + 1], tip[j], white, center, true, true)
		var dn := Vector3.DOWN * 0.004
		FireHelmet._quad(st, edge[j] + dn, tip[j] + dn, tip[j + 1] + dn, edge[j + 1] + dn, Color(0.55, 0.55, 0.55), center, false, true)
	var mesh := st.commit()
	_hat_meshes[rig] = mesh
	return mesh


static func hat_material(pick: int) -> StandardMaterial3D:
	if not _hat_mats.has(pick):
		var m := StandardMaterial3D.new()
		m.albedo_color = HATS[pick % HATS.size()]
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.38
		_hat_mats[pick] = m
	return _hat_mats[pick]


## Puts a hard hat on rig instance `inst` (crowd rig at `rig`); the hair is hidden under it.
static func dress_hat(inst: Node3D, rig: String, pick: int) -> void:
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or skel.find_bone("Head") < 0:
		return
	var unit := CrowdHat._unit(inst, skel)
	var rest := skel.get_bone_global_rest(skel.find_bone("Head"))
	var att := BoneAttachment3D.new()
	att.name = "HardHatMount"
	skel.add_child(att)
	att.bone_name = "Head"
	var mi := MeshInstance3D.new()
	mi.name = "HardHat"
	mi.mesh = hat_mesh(rig)
	mi.material_override = hat_material(pick)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE / maxf(unit, 1e-6)), rest.origin)
	att.add_child(mi)
	for node in inst.find_children("Hair*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false
