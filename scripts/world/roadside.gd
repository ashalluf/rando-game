class_name Roadside
extends RefCounted
## Los Angeles roadside commerce on the commercial pads (Commercial.build_pad): gas stations,
## car washes, auto repair and tyre shops, the Googie coffee shop, fast food with a drive-thru,
## and the stand with a giant donut or coffee cup on its roof. Real buildings at real size, built
## in code (RoadsideKit) on ONE shader (shaders/roadside.gdshader).
##
## * What a pad is comes from a HASH of seed + lot (`kind_for()`), never the chunk rng: the pad
##   roll and Commercial's own two rolls are still made in the old order (Commercial.build_pad),
##   so nothing after the pad moves. Inside a pad every roll is a private rng seeded the same way.
## * A pad is laid out in its own frame (`Site`): x along the street it faces, -z toward it, y up
##   from the pad's floor, which is the relief at the lot's centre; things standing on the ground
##   (islands, bollards) take the relief under themselves, buildings stand on the one sample with
##   a skirt below it. The lot's asphalt (Commercial._lot) is kept under everything.
## * FULL chunks: every pad of the chunk is ONE casting mesh (`Roadside`) and ONE shadowless
##   ground mesh (`RoadsideGround`: forecourt concrete, paint) on the shader, committed at the
##   finish (`commit()`); the repeated pieces are one MultiMesh a kind (`rs_*`), dispensers as
##   breakable props. Night: the shop_spill batch for the light on the ground, a `lamp_light`
##   OmniLight3D per pad on desktop. LOD chunks and the far city (capture) get `lod_box`es for the
##   buildings and the canopy as a slab.
## All names are invented; prices too.

enum Kind { FAST_FOOD, GAS, CAR_WASH, AUTO, DINER, STAND }
const KIND_NAMES := ["fast_food", "gas", "car_wash", "auto", "diner", "stand"]

## Cumulative odds of each kind on a pad big enough for all of them (the rest falls back: see
## `kind_for()`). Fast food first, then gas, as the old pads were.
const ODDS := [[Kind.FAST_FOOD, 0.27], [Kind.GAS, 0.52], [Kind.CAR_WASH, 0.62], [Kind.AUTO, 0.78], [Kind.DINER, 0.9], [Kind.STAND, 1.0]]
## What a pad too small for its roll becomes instead, and how often (of those that fit).
const FALLBACK := [[Kind.GAS, 0.42], [Kind.AUTO, 0.3], [Kind.DINER, 0.14], [Kind.STAND, 0.14]]
## Smallest pad (along the street, deep) each kind is laid out on.
const MIN_SIZE := {
	Kind.FAST_FOOD: Vector2(22.0, 22.0), Kind.GAS: Vector2(19.0, 20.0), Kind.CAR_WASH: Vector2(30.0, 20.0),
	Kind.AUTO: Vector2(18.0, 18.0), Kind.DINER: Vector2(20.0, 20.0), Kind.STAND: Vector2(18.0, 18.0),
}

const TOP := CityChunk.SIDEWALK_TOP
## How far ground pieces sit over the lot's asphalt (its top is TOP + 0.02), and paint over them.
const GROUND_LIFT := 0.035
const PAINT_LIFT := 0.045
## Buildings stand on the lot centre's relief with walls carried this far under it.
const SKIRT := 0.7

const GAS_BRANDS := [
	["VELA FUEL", Color(0.06, 0.32, 0.68), Color(0.98, 0.76, 0.12)],
	["REDTAIL", Color(0.74, 0.07, 0.06), Color(0.97, 0.97, 0.96)],
	["BLUE MESA", Color(0.1, 0.19, 0.52), Color(0.86, 0.2, 0.14)],
	["SOLANO", Color(0.08, 0.48, 0.28), Color(0.97, 0.86, 0.2)],
	["HALCYON", Color(0.95, 0.48, 0.07), Color(0.12, 0.12, 0.14)],
	["CANYON GAS", Color(0.52, 0.1, 0.38), Color(0.97, 0.97, 0.96)],
]
const STORE_NAMES := ["MINI MART", "FOOD MART", "QUICK MART", "SNACK STOP", "CORNER MART"]
const WASH_NAMES := ["SUDS CITY", "BLUE WAVE", "SPARKLE BROS", "TIDAL", "GLOSS BOSS"]
const AUTO_NAMES := [["LUCKY TIRE & WHEEL", "LLANTAS NUEVAS Y USADAS"], ["MIDWAY BRAKE & MUFFLER", "SMOG CHECK  OIL CHANGE"],
	["SIERRA AUTO CARE", "TUNE UP  BRAKES  A/C"], ["EL TORO TIRES", "LLANTAS  ALINEACION"], ["BIG ROAD TIRE SHOP", "NEW & USED  24 HR"]]
const DINER_NAMES := ["COMET", "SATELLITE", "JETSTREAM", "MOONBEAM", "STARGAZER"]
const STAND_NAMES := [["HALO DONUTS", 0], ["DOUGH RING", 0], ["BIG CUP COFFEE", 1], ["JAVA TOWER", 1]]
const FAST_NAMES := ["BURGER BOX", "CHICKEN SHACK", "TACO DEPOT", "PIZZA BARN", "WAFFLE SPOT", "NOODLE HUT"]
const WALLS := [Color(0.93, 0.9, 0.84), Color(0.88, 0.84, 0.74), Color(0.86, 0.88, 0.86), Color(0.95, 0.93, 0.9), Color(0.82, 0.78, 0.7)]
const SHOP_PAINTS := [Color(0.95, 0.88, 0.62), Color(0.78, 0.88, 0.95), Color(0.95, 0.95, 0.93), Color(0.92, 0.8, 0.7), Color(0.75, 0.9, 0.78)]
const CAR_JUNK := [Color(0.42, 0.28, 0.2), Color(0.5, 0.5, 0.48), Color(0.35, 0.36, 0.3), Color(0.55, 0.42, 0.3)]

## Off in the environment (ROADSIDE=0): the old pads (the A/B).
static var enabled: bool = OS.get_environment("ROADSIDE") != "0"
## Tools and checks: every pad built is appended here while `recording` is on.
static var recording := false
static var record: Array = []
## Tools: the triangles written and the microseconds spent on FULL pads since the last reset.
static var built_tris := 0
static var built_usec := 0


# --- Planning (pure) -------------------------------------------------------------------------

static func _h01(parts: Array) -> float:
	return float(hash(parts) & 0xffffff) / float(0x1000000)


## The pad's frame: which way it faces (the nearest street), its size along and across that
## street, its yaw. Pure.
static func frame_of(plan: CityPlan, ix: int, iz: int, lot: Dictionary) -> Dictionary:
	var inner: Rect2 = (plan.block(ix, iz).rect as Rect2).grow(-plan.sidewalk_width)
	var c: Vector2 = lot.center
	var size: Vector2 = lot.size
	var dist := [inner.end.x - c.x, c.x - inner.position.x, inner.end.y - c.y, c.y - inner.position.y]
	var face := 0
	for i in 4:
		if float(dist[i]) < float(dist[face]):
			face = i
	var dir: Vector2 = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)][face]
	var along := size.y if face <= 1 else size.x
	var deep := size.x if face <= 1 else size.y
	return {"face": face, "dir": dir, "yaw": atan2(-dir.x, -dir.y), "w": along, "d": deep, "centre": c}


## What stands on a pad: a hash of seed + lot, `fast` the old pad roll (kept as a nudge, so a
## pad that was a drive-thru stays a little more likely to be food). Falls back to a kind the pad
## is big enough for. Pure.
static func kind_for(plan: CityPlan, lot: Dictionary, w: float, d: float, fast: bool) -> int:
	var c: Vector2 = lot.center
	var u := _h01([plan.seed, int(c.x * 4.0), int(c.y * 4.0), "roadside"])
	if fast and u > 0.62:
		u = _h01([plan.seed, int(c.x * 4.0), int(c.y * 4.0), "roadside_food"]) * 0.27
	var pick: int = Kind.STAND
	for o: Array in ODDS:
		if u < float(o[1]):
			pick = o[0]
			break
	var m0: Vector2 = MIN_SIZE[pick]
	if w >= m0.x and d >= m0.y:
		return pick
	# Too small for what was rolled: one of the kinds that fit, by a second hash.
	var v := _h01([plan.seed, int(c.x * 4.0), int(c.y * 4.0), "roadside_fit"])
	var acc := 0.0
	var fits: Array = []
	var total := 0.0
	for o: Array in FALLBACK:
		var m: Vector2 = MIN_SIZE[o[0]]
		if w >= m.x and d >= m.y:
			fits.append(o)
			total += float(o[1])
	for o: Array in fits:
		acc += float(o[1]) / total
		if v < acc:
			return o[0]
	return Kind.AUTO


# --- The site --------------------------------------------------------------------------------

class Site:
	var ch: CityChunk
	var lot: Dictionary
	var xf: Transform3D
	var yaw: float
	var w: float
	var d: float
	var g: float
	var kind: int
	var pen: RoadsideKit.Pen
	var ground: RoadsideKit.Pen
	var rng: RandomNumberGenerator
	var full: bool

	## A point of the pad's frame in the chunk.
	func at(p: Vector3) -> Vector3:
		return xf * p

	## The ground's height in the pad's frame under a point of it (0 at the lot centre).
	func dy(x: float, z: float) -> float:
		var p := xf * Vector3(x, 0.0, z)
		return ch._gy(p.x, p.z) - g


static func _state(ch: CityChunk) -> Dictionary:
	if not ch.has_meta("roadside"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var gst := SurfaceTool.new()
		gst.begin(Mesh.PRIMITIVE_TRIANGLES)
		ch.set_meta("roadside", {"st": st, "gst": gst, "tris": 0, "pads": 0})
	return ch.get_meta("roadside")


## Builds a pad (Commercial.build_pad, after its rolls): `fast` is the old pad roll.
static func build_pad(ch: CityChunk, lot: Dictionary, fast: bool) -> void:
	var t0 := Time.get_ticks_usec()
	var f := frame_of(ch.plan, ch.ix, ch.iz, lot)
	var s := Site.new()
	s.ch = ch
	s.lot = lot
	s.yaw = f.yaw
	s.w = f.w
	s.d = f.d
	var c: Vector2 = lot.center
	s.g = ch._gy(c.x, c.y)
	s.xf = Transform3D(Basis(Vector3.UP, s.yaw), Vector3(c.x, TOP + s.g, c.y))
	s.kind = kind_for(ch.plan, lot, s.w, s.d, fast)
	s.rng = RandomNumberGenerator.new()
	s.rng.seed = hash([ch.plan.seed, int(c.x * 4.0), int(c.y * 4.0), "roadside_pad"])
	s.full = ch.level == CityChunk.Level.FULL and not ch.capturing
	if recording:
		record.append({"kind": s.kind, "centre": c, "w": s.w, "d": s.d, "yaw": s.yaw, "dir": f.dir, "g": s.g, "block": Vector2i(ch.ix, ch.iz)})
	if s.full:
		var state := _state(ch)
		s.pen = RoadsideKit.Pen.new(state.st, s.xf)
		s.ground = RoadsideKit.Pen.new(state.gst, Transform3D())
		state.pads += 1
	match s.kind:
		Kind.GAS: _gas(s)
		Kind.CAR_WASH: _car_wash(s)
		Kind.AUTO: _auto(s)
		Kind.DINER: _diner(s)
		Kind.STAND: _stand(s)
		_: _fast_food(s)
	if s.full:
		var state := _state(ch)
		state.tris += s.pen.tris + s.ground.tris
		built_tris += s.pen.tris + s.ground.tris
		built_usec += Time.get_ticks_usec() - t0


## The FULL chunk's roadside meshes, at the finish (after the batches are added, before they build).
static func commit(ch: CityChunk) -> void:
	if not ch.has_meta("roadside"):
		return
	var state: Dictionary = ch.get_meta("roadside")
	ch.remove_meta("roadside")
	for key: String in ["rs_pool"]:
		ch._batch.set_no_shadow(key)
	for spec: Array in [[state.st, "Roadside", true], [state.gst, "RoadsideGround", false]]:
		var st: SurfaceTool = spec[0]
		var mesh := st.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = spec[1]
		mi.mesh = mesh
		mi.material_override = RoadsideKit.material()
		if not spec[2]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)


# --- Shared pieces ---------------------------------------------------------------------------

## A solid box of the frame (written and, with `collide`, a collision box).
static func _solid(s: Site, c: Vector3, size: Vector3, col: Color, rm: Vector2 = RoadsideKit.RM_PAINT, bevel: float = 0.0, collide: bool = true) -> void:
	s.pen.box(c, size, col, rm, bevel)
	if collide:
		s.ch._add_shape(size, s.at(c), s.yaw)


## A MultiMesh piece at a frame transform (the batch adds the relief under it, taken back here so
## it stands where the frame says).
static func _inst(s: Site, key: String, mesh: Mesh, local: Transform3D, custom: Color = Color.BLACK, color: Color = Color.WHITE) -> int:
	var xf := s.xf * local
	xf.origin.y -= s.ch._gy(xf.origin.x, xf.origin.z)
	return s.ch._batch.add(key, mesh, xf, color, custom)


## A breakable piece (a dispenser): its mesh as a batch instance, its collision box with it.
static func _prop(s: Site, kind: String, key: String, mesh: Mesh, local: Transform3D, custom: Color, box: Vector3) -> void:
	var xf := s.xf * local
	var gy := s.ch._gy(xf.origin.x, xf.origin.z)
	var foot := xf.origin - Vector3(0.0, gy, 0.0)
	var shape_c := (s.xf * (local * Vector3(0.0, box.y * 0.5, 0.0))) - Vector3(0.0, gy, 0.0)
	var inst_xf := Transform3D(xf.basis, foot)
	s.ch._add_prop(kind, foot, Color(0.3, 0.3, 0.32), [[key, mesh, inst_xf, Color.WHITE, custom]],
		[[box, shape_c, s.yaw + local.basis.get_euler().y]])


## A ground rect of the frame laid over the relief (4 m cells), `lift` over the pad's floor.
static func _ground(s: Site, r: Rect2, col: Color, lift: float = GROUND_LIFT) -> void:
	var nx := clampi(ceili(r.size.x / 4.0), 1, 24)
	var nz := clampi(ceili(r.size.y / 4.0), 1, 24)
	var pts := []
	for j in nz + 1:
		var row := []
		for i in nx + 1:
			var lx := r.position.x + r.size.x * i / nx
			var lz := r.position.y + r.size.y * j / nz
			var p := s.at(Vector3(lx, 0.0, lz))
			p.y = TOP + s.ch._gy(p.x, p.z) + lift
			row.append([p, Vector2(lx, lz)])
		pts.append(row)
	for j in nz:
		for i in nx:
			var a: Array = pts[j][i]
			var b: Array = pts[j][i + 1]
			var cc: Array = pts[j + 1][i + 1]
			var d: Array = pts[j + 1][i]
			s.ground.face(a[0], b[0], cc[0], d[0], [a[1], b[1], cc[1], d[1]], Vector3.UP, col, Vector2(0.75, 0.0))


## A painted line on the ground from `a` to `b` (frame XZ), `width` wide.
static func _line(s: Site, a: Vector2, b: Vector2, width: float, col: Color = Color(0.92, 0.92, 0.88)) -> void:
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x) * width * 0.5
	var pts := []
	for q: Vector2 in [a - n, b - n, b + n, a + n]:
		var p := s.at(Vector3(q.x, 0.0, q.y))
		p.y = TOP + s.ch._gy(p.x, p.z) + PAINT_LIFT
		pts.append(p)
	s.ground.face(pts[0], pts[1], pts[2], pts[3], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP, RoadsideKit.c(col, RoadsideKit.K_FIXED), Vector2(0.7, 0.0))


## A painted arrow on the ground at `p` pointing along `dir` (frame XZ).
static func _arrow(s: Site, p: Vector2, dir: Vector2) -> void:
	_line(s, p - dir * 1.4, p + dir * 0.4, 0.22)
	var n := Vector2(-dir.y, dir.x)
	_line(s, p + dir * 1.2 - n * 0.02, p + dir * 0.2 + n * 0.7, 0.2)
	_line(s, p + dir * 1.2 + n * 0.02, p + dir * 0.2 - n * 0.7, 0.2)


## Light on the ground after dark (the chunk's shop_spill batch, one draw), a rect of the frame.
static func _pool(s: Site, c: Vector2, size: Vector2, col: Color) -> void:
	var p := s.at(Vector3(c.x, 0.0, c.y))
	var a := s.xf.basis * Vector3(size.x, 0.0, 0.0)
	var n := s.xf.basis * Vector3(0.0, 0.0, size.y)
	# The quad's +Z must come out pointing up (it is culled from below), whichever way the pad
	# is turned; the pool is symmetric, so flipping its depth axis costs nothing.
	var up := a.normalized().cross(n.normalized())
	if up.y < 0.0:
		n = -n
		up = -up
	var xf := Transform3D(Basis(a, n, up), Vector3(p.x, TOP + 0.08 + PAINT_LIFT, p.z))
	s.ch._batch.add("shop_spill", PropFactory.shop_spill(), xf, col)


## A real light after dark (DayNight drives the `lamp_light` group), desktop only.
static func _light(s: Site, c: Vector3, reach: float, col: Color) -> void:
	if OS.has_feature("web"):
		return
	var light := OmniLight3D.new()
	light.position = s.at(c)
	light.omni_range = reach
	light.omni_attenuation = 1.4
	light.light_color = col
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 60.0
	light.distance_fade_length = 20.0
	light.add_to_group("lamp_light")
	s.ch.add_child(light)


## A building box: its occluder, and on LOD / the far city a lod_box with collision.
static func _mass(s: Site, c: Vector3, size: Vector3, col: Color) -> void:
	var w := s.at(c)
	s.ch._occluder_boxes.append([Transform3D(s.xf.basis, Vector3(w.x, 0.0, w.z)), Vector3(0.0, w.y, 0.0), size])
	if s.full:
		return
	var xf := Transform3D(s.xf.basis.scaled_local(size), Vector3(w.x, w.y - s.ch._gy(w.x, w.z), w.z))
	s.ch._batch.add("lod_box", PropFactory.unit_box(), xf, col, Color(0.0, 0.0, 0.0, 1.0))
	s.ch._add_lod_shape(Vector3(size.x if absf(sin(s.yaw)) < 0.5 else size.z, size.y, size.z if absf(sin(s.yaw)) < 0.5 else size.x), w)


## A static parked car (ArenaGrounds' code car, LotFill's batch) at frame XZ, facing `yaw`.
static func _car(s: Site, p: Vector2, yaw: float, paint: Color = Color(-1, 0, 0), y: float = 0.0) -> void:
	var v := 0 if s.rng.randf() < 0.55 else (2 if s.rng.randf() < 0.6 else 1)
	if paint.r < 0.0:
		paint = ArenaGrounds.CAR_PAINTS[s.rng.randi() % ArenaGrounds.CAR_PAINTS.size()]
	var key := "apark_car_%d" % v
	_inst(s, key, ArenaGrounds.car_mesh(v), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, s.dy(p.x, p.y) + y + 0.005, p.y)), Color.BLACK, paint)
	s.ch._batch.set_shadow_distance(key, LotFill.CAR_SHADOW_DISTANCE)


## A shrub in the chunk's shared shrub batch.
static func _shrub(s: Site, p: Vector2, scale: float) -> void:
	var v := s.rng.randi() % 4
	_inst(s, "shrub_%d" % v, PropFactory.model_shrub(v), Transform3D(Basis(Vector3.UP, s.rng.randf() * TAU).scaled(Vector3.ONE * scale), Vector3(p.x, s.dy(p.x, p.y) + 0.3, p.y)), Color.BLACK, Color(0.95, 1.0, 0.9))


## A planter strip along the street edge with shrubs, leaving the drives open (frame x ranges).
static func _frontage(s: Site, drives: Array) -> void:
	var z := -s.d * 0.5 + 0.7
	var x := -s.w * 0.5 + 0.6
	var runs := []
	var cuts := drives.duplicate()
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for cut: Vector2 in cuts:
		if cut.x - x > 2.0:
			runs.append(Vector2(x, cut.x))
		x = cut.y
	if s.w * 0.5 - 0.6 - x > 2.0:
		runs.append(Vector2(x, s.w * 0.5 - 0.6))
	for r: Vector2 in runs:
		var mid := (r.x + r.y) * 0.5
		var len := r.y - r.x
		var y := s.dy(mid, z)
		s.pen.box(Vector3(mid, y + 0.1, z), Vector3(len, 0.32, 1.0), RoadsideKit.c(Color(0.7, 0.69, 0.66), RoadsideKit.K_CONCRETE), RoadsideKit.RM_MATTE, 0.03)
		s.pen.box(Vector3(mid, y + 0.255, z), Vector3(len - 0.2, 0.02, 0.8), RoadsideKit.c(Color(0.22, 0.16, 0.1), RoadsideKit.K_FIXED), RoadsideKit.RM_MATTE)
		var n := int(len / 2.6)
		for k in n:
			_shrub(s, Vector2(r.x + (k + 0.5) * len / n, z), 0.55 + s.rng.randf() * 0.25)
	# The drives: concrete aprons over the pavement to the kerb.
	var sw: float = s.ch.plan.sidewalk_width
	for cut: Vector2 in drives:
		_ground(s, Rect2(cut.x, -s.d * 0.5 - sw + 0.05, cut.y - cut.x, sw + 0.05), RoadsideKit.c(Color(0.6, 0.59, 0.56), RoadsideKit.K_CONCRETE), 0.012)


## A box building of the frame: walls on a skirt, a parapet with coping, roof membrane, rooftop
## units. `front_open` leaves the front wall out (the caller builds it). Returns nothing; adds
## collision, occluder and (LOD) the lod_box.
static func _shell(s: Site, r: Rect2, h: float, wall: Color, front_open: bool, parapet: float = 0.8, code: int = RoadsideKit.K_STUCCO) -> void:
	var c := Vector3(r.get_center().x, h * 0.5, r.get_center().y)
	_mass(s, c, Vector3(r.size.x, h + parapet, r.size.y), wall)
	if not s.full:
		return
	var col := RoadsideKit.c(wall, code)
	var t := 0.3
	var y0 := -SKIRT
	var hh := h + parapet - y0
	var yc := y0 + hh * 0.5
	# Back and side walls; the front only when asked.
	s.pen.box(Vector3(c.x, yc, r.end.y - t * 0.5), Vector3(r.size.x, hh, t), col, RoadsideKit.RM_MATTE)
	for x: float in [r.position.x + t * 0.5, r.end.x - t * 0.5]:
		s.pen.box(Vector3(x, yc, c.z), Vector3(t, hh, r.size.y), col, RoadsideKit.RM_MATTE)
	if not front_open:
		s.pen.box(Vector3(c.x, yc, r.position.y + t * 0.5), Vector3(r.size.x, hh, t), col, RoadsideKit.RM_MATTE)
	s.ch._add_shape(Vector3(r.size.x, h + 0.4, r.size.y), s.at(Vector3(c.x, (h + 0.4) * 0.5, c.z)), s.yaw)
	# Roof: membrane a little under the parapet's top, coping round it, a dark base course.
	s.pen.box(Vector3(c.x, h, c.z), Vector3(r.size.x - 0.1, 0.25, r.size.y - 0.1), RoadsideKit.c(Color(0.62, 0.62, 0.6), RoadsideKit.K_FIXED), RoadsideKit.RM_MATTE)
	for e in 4:
		var cop := Vector3(c.x, h + parapet + 0.04, r.position.y + 0.15) if e == 0 else (Vector3(c.x, h + parapet + 0.04, r.end.y - 0.15) if e == 1 else Vector3(r.position.x + 0.15 if e == 2 else r.end.x - 0.15, h + parapet + 0.04, c.z))
		var sz := Vector3(r.size.x + 0.1, 0.08, 0.42) if e <= 1 else Vector3(0.42, 0.08, r.size.y + 0.1)
		s.pen.box(cop, sz, RoadsideKit.c(Color(0.72, 0.71, 0.68), RoadsideKit.K_FIXED), RoadsideKit.RM_PAINT)
	var base := RoadsideKit.c(wall.darkened(0.45), RoadsideKit.K_FIXED)
	s.pen.box(Vector3(c.x, -0.2, r.end.y + 0.02), Vector3(r.size.x + 0.04, 1.1, 0.06), base, RoadsideKit.RM_MATTE)
	for x: float in [r.position.x - 0.02, r.end.x + 0.02]:
		s.pen.box(Vector3(x, -0.2, c.z), Vector3(0.06, 1.1, r.size.y + 0.04), base, RoadsideKit.RM_MATTE)
	# Packaged rooftop units, a duct and a vent.
	var n := 1 + int(r.size.x * r.size.y > 160.0)
	for k in n:
		var ux := lerpf(r.position.x + 2.5, r.end.x - 2.5, (k + 0.5) / n)
		var uz := c.z + 0.8
		s.pen.box(Vector3(ux, h + 0.62, uz), Vector3(1.9, 1.0, 1.2), RoadsideKit.c(Color(0.78, 0.78, 0.76), RoadsideKit.K_FIXED), RoadsideKit.RM_PAINT, 0.03)
		s.pen.cyl(Vector3(ux - 0.4, h + 1.12, uz), 0.32, 0.32, 0.08, RoadsideKit.c(Color(0.2, 0.2, 0.21), RoadsideKit.K_FIXED), RoadsideKit.RM_PAINT, 12)
		s.pen.box(Vector3(ux, h + 0.35, uz - 1.1), Vector3(0.5, 0.4, 1.0), RoadsideKit.c(Color(0.7, 0.7, 0.7), RoadsideKit.K_STEEL), RoadsideKit.RM_STEEL)
	s.pen.cyl(Vector3(r.end.x - 1.2, h, r.end.y - 1.2), 0.12, 0.12, 0.9, RoadsideKit.c(Color(0.5, 0.5, 0.5), RoadsideKit.K_STEEL), RoadsideKit.RM_STEEL, 8)


## A storefront along the front of `r` (frame), from x0 to x1: glass on a low base, mullions, a
## door pair at `door_x`, the room behind traced `depth` deep. Returns nothing.
static func _storefront(s: Site, z: float, x0: float, x1: float, head: float, depth: float, room: int, door_x: float, frame_col: Color = Color(0.72, 0.73, 0.75)) -> void:
	var fr := RoadsideKit.c(frame_col, RoadsideKit.K_STEEL)
	var out := Vector3(0.0, 0.0, -1.0)
	var span := x1 - x0
	var n := maxi(int(span / 1.6), 1)
	var pitch := span / n
	for i in n:
		var cx := x0 + (i + 0.5) * pitch
		var door := absf(cx - door_x) < pitch * 0.55
		if door:
			# Two glazed leaves with pull bars under a transom.
			for sd: float in [-1.0, 1.0]:
				s.pen.box(Vector3(cx + sd * pitch * 0.25, 1.15, z - 0.02), Vector3(pitch * 0.48, 2.3, 0.05), RoadsideKit.c(Color(0.05, 0.06, 0.07), RoadsideKit.K_GLASS), Vector2(0.1, 0.0))
				s.pen.box(Vector3(cx + sd * 0.12, 1.1, z - 0.08), Vector3(0.03, 0.9, 0.03), fr, RoadsideKit.RM_STEEL)
			s.pen.window(Vector3(cx, 0.0, z - 0.03), out, pitch - 0.06, 0.0, 2.38, head, depth, room)
			s.pen.box(Vector3(cx, 2.34, z - 0.04), Vector3(pitch, 0.08, 0.1), fr, RoadsideKit.RM_STEEL)
		else:
			s.pen.window(Vector3(cx, 0.0, z - 0.03), out, pitch - 0.06, 0.0, 0.5, head, depth, room)
			s.pen.box(Vector3(cx, 0.25, z - 0.05), Vector3(pitch, 0.5, 0.12), fr, RoadsideKit.RM_STEEL)
	for i in n + 1:
		s.pen.box(Vector3(x0 + i * pitch, head * 0.5, z - 0.06), Vector3(0.07, head, 0.14), fr, RoadsideKit.RM_STEEL)
	s.pen.box(Vector3((x0 + x1) * 0.5, head + 0.05, z - 0.06), Vector3(span + 0.07, 0.1, 0.14), fr, RoadsideKit.RM_STEEL)


## Lit channel letters on a raceway (a sign on a fascia): text facing -z at `c` (frame).
static func _letters(s: Site, text: String, c: Vector3, height: float, col: Color, max_w: float, out: Vector3 = Vector3(0, 0, -1)) -> void:
	var along := Vector3.UP.cross(out).normalized()
	s.pen.box(c - out * 0.02 + Vector3(0.0, -height * 0.05, 0.0), along.abs() * max_w * 0.85 + Vector3(0.0, 0.08, 0.0) + out.abs() * 0.06, RoadsideKit.c(Color(0.3, 0.3, 0.31), RoadsideKit.K_FIXED), RoadsideKit.RM_PAINT)
	s.pen.text(text, height, c + out * 0.04, out, RoadsideKit.c(col, RoadsideKit.K_LIGHTBOX), max_w)


# --- Gas station -----------------------------------------------------------------------------

static func _gas(s: Site) -> void:
	var brand: Array = GAS_BRANDS[s.rng.randi() % GAS_BRANDS.size()]
	var bname: String = brand[0]
	var c1: Color = brand[1]
	var c2: Color = brand[2]
	var hw := s.w * 0.5
	var hd := s.d * 0.5
	# The store at the back, to one side; the canopy over the forecourt in front of it.
	var side := 1.0 if s.rng.randf() < 0.5 else -1.0
	var sw := clampf(s.w * 0.5, 10.0, 18.0)
	var sd := clampf(s.d * 0.3, 6.5, 11.0)
	var back := 1.0 if s.d < 26.0 else 1.5
	var store := Rect2(side * (hw - 1.5 - sw * 0.5) - sw * 0.5, hd - back - sd, sw, sd)
	var cw := clampf(s.w - 5.0, 13.0, 27.0)
	var cz0 := -hd + (2.6 if s.d < 26.0 else 3.2)
	var cz1 := store.position.y - (3.6 if s.d < 26.0 else 4.2)
	var cd := clampf(cz1 - cz0, 6.0, 14.0)
	var cc := Vector2(0.0, cz0 + cd * 0.5)
	var under := 4.9
	var fascia := 1.15
	_shell(s, store, 4.4, WALLS[s.rng.randi() % WALLS.size()], true)
	if not s.full:
		# The canopy as one slab (LOD and the far city's capture).
		s.ch._add_slab(Vector3(s.at(Vector3(cc.x, 0.0, cc.y)).x, TOP + under + fascia * 0.5, s.at(Vector3(cc.x, 0.0, cc.y)).z), Vector3(cw if absf(sin(s.yaw)) < 0.5 else cd, fascia, cd if absf(sin(s.yaw)) < 0.5 else cw), Color(0.92, 0.92, 0.92), true, PropFactory.material(Color(0.92, 0.92, 0.92), 0.5))
		return
	var pen := s.pen
	var K := RoadsideKit
	# Forecourt: concrete under the canopy and in front of the store, aprons to the street.
	_ground(s, Rect2(-hw + 1.0, cz0 - 1.5, s.w - 2.0, store.position.y - cz0 + 1.5), K.c(Color(0.74, 0.73, 0.7), K.K_CONCRETE))
	var drive_w := 8.0
	_frontage(s, [Vector2(-hw + 2.0, -hw + 2.0 + drive_w), Vector2(hw - 2.0 - drive_w, hw - 2.0)])
	# --- The canopy: deck, fascia all round (brand stripe under a white lightbox band), the
	# soffit with its recessed LED panels.
	var top_y := under + fascia
	pen.box(Vector3(cc.x, top_y - 0.12, cc.y), Vector3(cw - 0.2, 0.22, cd - 0.2), K.c(Color(0.55, 0.55, 0.55), K.K_FIXED), K.RM_MATTE)
	pen.box(Vector3(cc.x, under + 0.06, cc.y), Vector3(cw - 0.3, 0.12, cd - 0.3), K.c(Color(0.93, 0.93, 0.92), K.K_FIXED), K.RM_PAINT)
	s.ch._add_shape(Vector3(cw, fascia, cd), s.at(Vector3(cc.x, under + fascia * 0.5, cc.y)), s.yaw)
	for e in 4:
		var along_x := e <= 1
		var span := cw if along_x else cd
		var o := Vector3(cc.x, 0.0, cc.y + (-cd * 0.5 if e == 0 else cd * 0.5)) if along_x else Vector3(cc.x + (-cw * 0.5 if e == 2 else cw * 0.5), 0.0, cc.y)
		var out := Vector3(0, 0, -1 if e == 0 else 1) if along_x else Vector3(-1 if e == 2 else 1, 0, 0)
		var sz := Vector3(span + 0.3, 0.0, 0.15) if along_x else Vector3(0.15, 0.0, span + 0.3)
		pen.box(o + Vector3(0.0, under + 0.21, 0.0), sz + Vector3(0.0, 0.42, 0.0), K.c(c1, K.K_LIGHTBOX), K.RM_PLASTIC)
		pen.box(o + Vector3(0.0, under + 0.45, 0.0) + out * 0.005, sz + Vector3(0.0, 0.05, 0.0) + out.abs() * 0.01, K.c(Color(0.2, 0.2, 0.21), K.K_FIXED), K.RM_PAINT)
		pen.box(o + Vector3(0.0, under + 0.8, 0.0), sz + Vector3(0.0, 0.66, 0.0), K.c(Color(0.97, 0.97, 0.96), K.K_LIGHTBOX), K.RM_PLASTIC)
		pen.box(o + Vector3(0.0, top_y + 0.02, 0.0), sz + Vector3(0.1, 0.06, 0.0) + out.abs() * 0.1, K.c(Color(0.75, 0.75, 0.76), K.K_STEEL), K.RM_STEEL)
		# The brand name on the long faces and a short word on the ends.
		var word: String = bname if along_x else bname.split(" ")[0]
		_letters_flat(s, word, o + out * 0.09 + Vector3(0.0, under + 0.8, 0.0), 0.5, c1 if c1.v < 0.8 else c2, minf(span * 0.6, 12.0), out)
	# The soffit's LED panels: square lenses on a 3 m grid, a reveal round each.
	var nx := maxi(int(cw / 3.2), 2)
	var nz := maxi(int(cd / 3.2), 2)
	for i in nx:
		for j in nz:
			var px := cc.x - cw * 0.5 + (i + 0.5) * cw / nx
			var pz := cc.y - cd * 0.5 + (j + 0.5) * cd / nz
			var y := under - 0.005
			pen.box(Vector3(px, y + 0.01, pz), Vector3(0.78, 0.04, 0.78), K.c(Color(0.25, 0.25, 0.26), K.K_FIXED), K.RM_PAINT)
			pen.face(Vector3(px - 0.33, y - 0.012, pz - 0.33), Vector3(px + 0.33, y - 0.012, pz - 0.33), Vector3(px + 0.33, y - 0.012, pz + 0.33), Vector3(px - 0.33, y - 0.012, pz + 0.33),
				[Vector2(0, 0), Vector2(0.66, 0), Vector2(0.66, 0.66), Vector2(0, 0.66)], Vector3.DOWN, K.c(Color(1, 1, 1), K.K_SOFFIT), Vector2(0.25, 0.0))
	# --- Islands, columns, dispensers.
	var n_isl := clampi(int(cw / 6.5), 2, 4)
	var isl_len := clampf(cd - 2.5, 5.0, 8.0)
	var two := isl_len >= 6.8
	for i in n_isl:
		var ix := cc.x - cw * 0.5 + (i + 0.5) * cw / n_isl
		var iy := s.dy(ix, cc.y)
		pen.box(Vector3(ix, iy + 0.09 - 0.25, cc.y), Vector3(1.25, 0.68, isl_len), K.c(Color(0.75, 0.74, 0.71), K.K_CONCRETE), K.RM_MATTE, 0.06)
		s.ch._add_shape(Vector3(1.25, 0.18, isl_len), s.at(Vector3(ix, iy + 0.09, cc.y)), s.yaw)
		# Yellow nosings and bollards at both ends.
		for e: float in [-1.0, 1.0]:
			var ez := cc.y + e * (isl_len * 0.5 - 0.15)
			pen.box(Vector3(ix, iy + 0.19, ez), Vector3(1.26, 0.03, 0.3), K.c(Color(0.92, 0.75, 0.1), K.K_FIXED), K.RM_PAINT)
			for bx: float in [-0.38, 0.38]:
				pen.cyl(Vector3(ix + bx, iy + 0.18, ez + e * 0.05), 0.1, 0.1, 1.0, K.c(Color(0.95, 0.78, 0.1), K.K_FIXED), K.RM_PAINT, 10)
				pen.cyl(Vector3(ix + bx, iy + 1.18, ez + e * 0.05), 0.1, 0.06, 0.06, K.c(Color(0.95, 0.78, 0.1), K.K_FIXED), K.RM_PAINT, 10)
				s.ch._add_shape(Vector3(0.2, 1.0, 0.2), s.at(Vector3(ix + bx, iy + 0.68, ez + e * 0.05)), s.yaw)
		# The column: brand-clad up to the soffit, a steel base.
		var col_h := under - iy
		pen.box(Vector3(ix, iy + 0.18 + col_h * 0.5, cc.y), Vector3(0.46, col_h, 0.46), K.c(c1, K.K_FIXED), K.RM_PAINT, 0.02)
		pen.box(Vector3(ix, iy + 0.5, cc.y), Vector3(0.5, 0.64, 0.5), K.c(Color(0.7, 0.71, 0.72), K.K_STEEL), K.RM_STEEL, 0.01)
		pen.box(Vector3(ix, iy + 3.2, cc.y), Vector3(0.48, 0.12, 0.48), K.c(c2, K.K_FIXED), K.RM_PAINT)
		s.ch._add_shape(Vector3(0.46, col_h, 0.46), s.at(Vector3(ix, iy + col_h * 0.5, cc.y)), s.yaw)
		var pumps: Array = [-isl_len * 0.27, isl_len * 0.27] if two else [-isl_len * 0.22]
		for pz: float in pumps:
			var at := Vector3(ix, iy + 0.18, cc.y + pz)
			_prop(s, "pump", "rs_disp", RoadsideKit.dispenser(), Transform3D(Basis(Vector3.UP, PI * 0.5), at), Color(c1.r, c1.g, c1.b, s.rng.randf()), Vector3(0.6, 2.3, 1.2))
		var stand_z := cc.y + (isl_len * 0.27 if not two else 0.0) + (0.0 if not two else 0.9)
		_inst(s, "rs_stand", RoadsideKit.service_stand(), Transform3D(Basis(Vector3.UP, PI * 0.5 * (1.0 if i % 2 == 0 else -1.0)), Vector3(ix + (0.0 if not two else 0.0), iy + 0.18, stand_z if two else cc.y + isl_len * 0.3)), Color(c1.r, c1.g, c1.b, 0.0))
	# --- The store: storefront under a brand fascia, ice and propane by the door, a side door.
	var front := store.position.y
	var door_x := store.get_center().x - side * sw * 0.18
	pen.box(Vector3(store.get_center().x, 3.85, front + 0.15), Vector3(sw, 1.4, 0.3), K.c(WALLS[0], K.K_STUCCO), K.RM_MATTE)
	_storefront(s, front + 0.05, store.position.x + 0.3, store.end.x - 0.3, 3.1, sd - 1.0, K.Room.STORE, door_x)
	pen.box(Vector3(store.get_center().x, 3.55, front - 0.35), Vector3(sw + 0.4, 1.0, 0.7), K.c(c1, K.K_FIXED), K.RM_PAINT, 0.02)
	pen.box(Vector3(store.get_center().x, 3.12, front - 0.35), Vector3(sw + 0.42, 0.12, 0.72), K.c(c2, K.K_LIGHTBOX), K.RM_PLASTIC)
	var sname: String = STORE_NAMES[s.rng.randi() % STORE_NAMES.size()]
	_letters_flat(s, sname, Vector3(store.get_center().x, 3.62, front - 0.71), 0.55, Color(0.98, 0.98, 0.96), sw * 0.7, Vector3(0, 0, -1))
	# Soffit lights under the store's canopy band.
	for k in int(sw / 2.5):
		var lx := store.position.x + 1.25 + k * 2.5
		pen.box(Vector3(lx, 3.04, front - 0.4), Vector3(0.5, 0.02, 0.18), K.c(Color(1.0, 0.97, 0.9), K.K_NEON), K.RM_PLASTIC)
	var ice_x := store.position.x + 1.3 if side > 0.0 else store.end.x - 1.3
	_inst(s, "rs_ice", RoadsideKit.ice_chest(), Transform3D(Basis(), Vector3(ice_x, s.dy(ice_x, front - 0.7), front - 0.7)))
	var cage_x := store.end.x + 1.0 if side < 0.0 else store.position.x - 1.0
	cage_x = clampf(cage_x, -hw + 1.0, hw - 1.0)
	_inst(s, "rs_propane", RoadsideKit.propane_cage(), Transform3D(Basis(Vector3.UP, PI * 0.5 * side), Vector3(cage_x, s.dy(cage_x, store.get_center().y), store.get_center().y)))
	s.ch._add_shape(Vector3(1.3, 1.6, 0.75), s.at(Vector3(cage_x, 0.8, store.get_center().y)), s.yaw + PI * 0.5)
	# Air and water at the far corner of the forecourt.
	var air := Vector2(-side * (hw - 1.6), store.get_center().y)
	_inst(s, "rs_air", RoadsideKit.air_machine(), Transform3D(Basis(Vector3.UP, -PI * 0.5 * side), Vector3(air.x, s.dy(air.x, air.y), air.y)))
	# Parking stalls along the store front's free side.
	var px0 := -side * (hw - 2.0)
	for k in 3:
		var sx := px0 + side * k * 2.8
		_line(s, Vector2(sx, front - 5.6), Vector2(sx, front - 0.6), 0.1)
	if s.rng.randf() < 0.7:
		_car(s, Vector2(px0 + side * 1.4, front - 3.0), PI)
	# --- The price sign: a pole sign at the street corner, a lit brand head over the LED prices.
	_price_sign(s, Vector2(-side * (hw - 1.6), -hd + 1.8), bname, c1, c2)
	# Night.
	_pool(s, cc, Vector2(cw + 6.0, cd + 6.0), Color(1.0, 1.0, 1.0, 1.4))
	_pool(s, Vector2(store.get_center().x, front - 2.5), Vector2(sw + 2.0, 6.0), Color(1.0, 0.96, 0.88, 0.9))
	_light(s, Vector3(cc.x, under - 0.6, cc.y), 16.0, Color(0.95, 0.97, 1.0))


## Flat lit lettering straight on a face (no raceway): a fascia band's brand name.
static func _letters_flat(s: Site, text: String, c: Vector3, height: float, col: Color, max_w: float, out: Vector3) -> void:
	s.pen.text(text, height, c, out, RoadsideKit.c(col, RoadsideKit.K_LIGHTBOX), max_w)


## The price sign: twin posts, a cabinet with the brand head and three rows of grade and LED price,
## both faces. Prices are invented (seed + place).
static func _price_sign(s: Site, p: Vector2, bname: String, c1: Color, c2: Color) -> void:
	var K := RoadsideKit
	var pen := s.pen
	var y0 := s.dy(p.x, p.y)
	var cw := 2.6
	var bottom := 2.6
	var rows := 3
	var row_h := 0.8
	var head_h := 1.3
	var top := bottom + rows * row_h + head_h
	pen.box(Vector3(p.x, y0 + 0.2, p.y), Vector3(3.0, 0.5, 1.0), K.c(Color(0.7, 0.69, 0.66), K.K_CONCRETE), K.RM_MATTE, 0.04)
	for x: float in [-0.75, 0.75]:
		pen.box(Vector3(p.x + x, y0 + bottom * 0.5 + 0.2, p.y), Vector3(0.28, bottom, 0.28), K.c(c1, K.K_FIXED), K.RM_PAINT, 0.02)
	pen.box(Vector3(p.x, y0 + (bottom + top) * 0.5, p.y), Vector3(cw + 0.12, top - bottom + 0.12, 0.46), K.c(Color(0.18, 0.18, 0.19), K.K_FIXED), K.RM_PAINT, 0.03)
	s.ch._add_shape(Vector3(cw, top, 0.5), s.at(Vector3(p.x, y0 + top * 0.5, p.y)), s.yaw)
	var base := 4.0 + float(hash([s.ch.plan.seed, int(p.x), int(p.y), "price"]) % 120) / 100.0
	var grades := [["REGULAR", 0.0], ["PLUS", 0.1 + float(hash([s.ch.plan.seed, p, "p2"]) % 6) / 100.0], ["PREMIUM", 0.22 + float(hash([s.ch.plan.seed, p, "p3"]) % 10) / 100.0]]
	if _h01([s.ch.plan.seed, p, "diesel"]) < 0.35:
		grades[2] = ["DIESEL", 0.45 + float(hash([s.ch.plan.seed, p, "p4"]) % 30) / 100.0]
	var led := Color(1.0, 0.12, 0.06) if _h01([bname, "led"]) < 0.6 else Color(0.2, 1.0, 0.25)
	for sd: float in [-1.0, 1.0]:
		var out := Vector3(0.0, 0.0, sd)
		var fz := p.y + sd * 0.235
		# The brand head.
		pen.box(Vector3(p.x, y0 + top - head_h * 0.5, fz), Vector3(cw, head_h - 0.08, 0.02), K.c(c1, K.K_LIGHTBOX), K.RM_PLASTIC)
		pen.box(Vector3(p.x, y0 + top - head_h + 0.12, fz + sd * 0.006), Vector3(cw, 0.12, 0.02), K.c(c2, K.K_LIGHTBOX), K.RM_PLASTIC)
		_letters_flat(s, bname, Vector3(p.x, y0 + top - head_h * 0.45, fz + sd * 0.014), 0.42, c2 if c2.v > 0.5 else Color(0.98, 0.98, 0.97), cw * 0.86, out)
		var along := Vector3.UP.cross(out).normalized()
		var pc := Vector3(p.x, 0.0, fz)
		for r in rows:
			var ry := y0 + top - head_h - (r + 0.5) * row_h
			var g: Array = grades[r]
			var lc := pc - along * cw * 0.27 + Vector3(0.0, ry, 0.0)
			var dc := pc + along * cw * 0.22 + Vector3(0.0, ry, 0.0)
			pen.box(lc, Vector3(cw * 0.42, row_h - 0.12, 0.02), K.c(Color(0.97, 0.97, 0.96), K.K_LIGHTBOX), K.RM_PLASTIC)
			_letters_flat(s, g[0], lc + out * 0.014, 0.2, Color(0.1, 0.1, 0.12), cw * 0.38, out)
			pen.box(dc, Vector3(cw * 0.52, row_h - 0.12, 0.02), K.c(Color(0.02, 0.02, 0.02), K.K_FIXED), K.RM_PLASTIC)
			var v := base + float(g[1])
			var digits := "%d.%02d9" % [int(v), int(round((v - floor(v)) * 100.0)) % 100]
			pen.price(digits, dc - along * 0.62, out, 0.44, led, 3)


# --- Car wash --------------------------------------------------------------------------------

static func _car_wash(s: Site) -> void:
	var K := RoadsideKit
	var hw := s.w * 0.5
	var hd := s.d * 0.5
	var bname: String = WASH_NAMES[s.rng.randi() % WASH_NAMES.size()]
	var accent: Color = [Color(0.1, 0.45, 0.85), Color(0.95, 0.25, 0.55), Color(0.1, 0.65, 0.6), Color(0.95, 0.55, 0.1)][s.rng.randi() % 4]
	var L := clampf(s.w - 9.0, 22.0, 34.0)
	var tw := 6.4
	var th := 5.2
	var tunnel := Rect2(hw - 2.0 - L, hd - 1.2 - tw, L, tw)
	var wall: Color = WALLS[s.rng.randi() % WALLS.size()]
	_mass(s, Vector3(tunnel.get_center().x, (th + 1.6) * 0.5, tunnel.get_center().y), Vector3(L, th + 1.6, tw), wall)
	if not s.full:
		return
	var pen := s.pen
	var tc := tunnel.get_center()
	var col := K.c(wall, K.K_STUCCO)
	var t := 0.3
	# The tunnel: two long walls (windows in the front one), the roof, a raised sign parapet in front.
	pen.box(Vector3(tc.x, (th - SKIRT) * 0.5, tunnel.end.y - t * 0.5), Vector3(L, th + SKIRT, t), col, K.RM_MATTE)
	pen.box(Vector3(tc.x, (th - SKIRT) * 0.5, tunnel.position.y + t * 0.5), Vector3(L, th + SKIRT, t), col, K.RM_MATTE)
	pen.box(Vector3(tc.x, th + 0.15, tc.y), Vector3(L + 0.6, 0.3, tw + 0.6), K.c(Color(0.6, 0.6, 0.6), K.K_FIXED), K.RM_MATTE)
	for e in 2:
		s.ch._add_shape(Vector3(L, th, t), s.at(Vector3(tc.x, th * 0.5, tunnel.position.y + t * 0.5 if e == 0 else tunnel.end.y - t * 0.5)), s.yaw)
	s.ch._add_shape(Vector3(L, 0.3, tw), s.at(Vector3(tc.x, th + 0.15, tc.y)), s.yaw)
	# Accent band and the sign parapet with the name and CAR WASH.
	pen.box(Vector3(tc.x, th - 0.4, tunnel.position.y - 0.04), Vector3(L, 0.5, 0.1), K.c(accent, K.K_FIXED), K.RM_PAINT)
	pen.box(Vector3(tc.x, th + 1.0, tunnel.position.y + 0.25), Vector3(L * 0.6, 1.7, 0.4), col, K.RM_MATTE)
	# A dark sign face with lit letters: the name in the brand colour, CAR WASH in white, a lit
	# band in the brand colour along its foot.
	pen.box(Vector3(tc.x, th + 1.0, tunnel.position.y + 0.03), Vector3(L * 0.56, 1.4, 0.04), K.c(Color(0.06, 0.08, 0.14), K.K_FIXED), K.RM_PAINT)
	pen.box(Vector3(tc.x, th + 0.33, tunnel.position.y + 0.0), Vector3(L * 0.56, 0.1, 0.04), K.c(accent, K.K_NEON), K.RM_PLASTIC)
	_letters_flat(s, bname, Vector3(tc.x, th + 1.25, tunnel.position.y - 0.0), 0.75, accent.lightened(0.25), L * 0.5, Vector3(0, 0, -1))
	_letters_flat(s, "CAR WASH", Vector3(tc.x, th + 0.6, tunnel.position.y - 0.0), 0.36, Color(0.98, 0.98, 0.96), L * 0.4, Vector3(0, 0, -1))
	# A band of windows along the front wall onto the tunnel (traced, the brushes' wash of light).
	var nwin := int(L / 3.0)
	for k in nwin:
		var wx := tunnel.position.x + (k + 0.5) * L / nwin
		pen.window(Vector3(wx, 0.0, tunnel.position.y - 0.01), Vector3(0, 0, -1), L / nwin - 0.4, 0.0, 1.4, 3.4, tw - 0.6, K.Room.TUNNEL)
		pen.box(Vector3(wx - L / nwin * 0.5, 2.4, tunnel.position.y - 0.05), Vector3(0.4, 2.2, 0.1), K.c(Color(0.7, 0.71, 0.72), K.K_STEEL), K.RM_STEEL)
		pen.box(Vector3(wx, 1.36, tunnel.position.y - 0.08), Vector3(L / nwin, 0.08, 0.16), K.c(Color(0.7, 0.71, 0.72), K.K_STEEL), K.RM_STEEL)
	# Floor: the conveyor and guide rail, wet concrete.
	_ground(s, Rect2(tunnel.position.x - 6.0, tunnel.position.y + 0.3, L + 10.0, tw - 0.6), K.c(Color(0.55, 0.56, 0.56), K.K_CONCRETE))
	pen.box(Vector3(tc.x, 0.08, tc.y - 1.0), Vector3(L + 4.0, 0.12, 0.35), K.c(Color(0.6, 0.62, 0.64), K.K_STEEL), K.RM_STEEL)
	pen.box(Vector3(tc.x, 0.18, tc.y - 1.3), Vector3(L + 4.0, 0.25, 0.08), K.c(Color(0.85, 0.75, 0.1), K.K_FIXED), K.RM_PAINT)
	# Inside, from the entrance (-x end): an LED arch, the mitter curtain, wraparound brushes, the
	# top brush, a second LED arch, the blowers at the exit.
	var x0 := tunnel.position.x
	var cloth := [Color(0.15, 0.45, 0.95), Color(0.95, 0.3, 0.6), Color(0.98, 0.85, 0.2), Color(0.3, 0.85, 0.5)]
	_wash_arch(s, x0 + 1.0, tc.y, tw, th, accent, true)
	# Mitter curtain: strips of cloth hanging from a frame.
	var mx := x0 + 4.0
	pen.box(Vector3(mx, th - 0.6, tc.y), Vector3(0.12, 0.12, tw - 0.8), K.c(Color(0.65, 0.66, 0.68), K.K_STEEL), K.RM_STEEL)
	for k in 14:
		var z := tunnel.position.y + 0.7 + k * (tw - 1.4) / 13.0
		var cl: Color = cloth[k % cloth.size()]
		pen.box(Vector3(mx + 0.1 * sin(k * 1.7), th - 0.6 - 1.25, z), Vector3(0.02, 2.4, 0.3), K.c(cl, K.K_CLOTH), Vector2(0.5, 0.0))
	# Wraparound brushes: tall cylinders of cloth strips, two at a time.
	for bi in 2:
		var bx := x0 + 7.5 + bi * 4.0
		for sd: float in [-1.0, 1.0]:
			var bz := tc.y + sd * 1.9
			pen.cyl(Vector3(bx, 0.35, bz), 0.62, 0.66, 2.6, K.c(cloth[(bi * 2 + int(sd > 0.0)) % 4], K.K_CLOTH), Vector2(0.5, 0.0), 16)
			pen.cyl(Vector3(bx, 2.95, bz), 0.08, 0.08, th - 3.2, K.c(Color(0.6, 0.62, 0.64), K.K_STEEL), K.RM_STEEL, 8)
			pen.box(Vector3(bx, th - 0.3, bz), Vector3(0.3, 0.3, 0.3), K.c(Color(0.6, 0.62, 0.64), K.K_STEEL), K.RM_STEEL)
	# Top brush across the tunnel.
	var tx := x0 + 16.0
	if tx < tunnel.end.x - 5.0:
		pen.cyl(Vector3(tx, 2.2, tunnel.position.y + 0.5), 0.5, 0.5, tw - 1.0, K.c(cloth[1], K.K_CLOTH), Vector2(0.5, 0.0), 16, Basis(Vector3.RIGHT, PI * 0.5))
		for sd: float in [-1.0, 1.0]:
			pen.box(Vector3(tx, th * 0.5, tc.y + sd * (tw * 0.5 - 0.4)), Vector3(0.25, th, 0.25), K.c(Color(0.6, 0.62, 0.64), K.K_STEEL), K.RM_STEEL)
	_wash_arch(s, tunnel.end.x - 6.0, tc.y, tw, th, accent, false)
	# Blowers: a steel portal with nozzles at the exit.
	var blx := tunnel.end.x - 3.0
	for sd: float in [-1.0, 1.0]:
		pen.box(Vector3(blx, th * 0.5, tc.y + sd * (tw * 0.5 - 0.5)), Vector3(0.6, th - 0.4, 0.6), K.c(Color(0.75, 0.76, 0.78), K.K_STEEL), K.RM_STEEL, 0.03)
	pen.box(Vector3(blx, th - 0.6, tc.y), Vector3(0.7, 0.6, tw - 0.6), K.c(Color(0.75, 0.76, 0.78), K.K_STEEL), K.RM_STEEL, 0.03)
	for k in 4:
		pen.cyl(Vector3(blx, th - 1.1, tc.y - 1.5 + k * 1.0), 0.18, 0.1, 0.4, K.c(Color(0.15, 0.15, 0.16), K.K_FIXED), K.RM_PAINT, 10, Basis(Vector3.RIGHT, PI))
	# Lights down the tunnel's ceiling.
	for k in int(L / 3.0):
		pen.box(Vector3(x0 + 1.5 + k * 3.0, th - 0.05, tc.y), Vector3(1.4, 0.05, 0.25), K.c(Color(0.9, 0.95, 1.0), K.K_NEON), K.RM_PLASTIC)
	# ENTER and EXIT signs over the ends.
	for e in 2:
		var ex := tunnel.position.x - 0.05 if e == 0 else tunnel.end.x + 0.05
		var out := Vector3(-1, 0, 0) if e == 0 else Vector3(1, 0, 0)
		pen.box(Vector3(ex, th - 0.55, tc.y), Vector3(0.1, 0.7, tw * 0.6), K.c(Color(0.05, 0.4 if e == 0 else 0.05, 0.08 if e == 0 else 0.05), K.K_LIGHTBOX), K.RM_PLASTIC)
		_letters_flat(s, "ENTER" if e == 0 else "EXIT", Vector3(ex, th - 0.55, tc.y) + out * 0.06, 0.42, Color(0.95, 1.0, 0.95) if e == 0 else Color(1.0, 0.3, 0.2), tw * 0.5, out)
	# The queue: a lane from the street to the entrance, the pay station under a little canopy.
	var lane_x := tunnel.position.x - 3.0
	var lane_z0 := -hd + 1.5
	_line(s, Vector2(lane_x - 1.8, lane_z0), Vector2(lane_x - 1.8, tc.y), 0.12, Color(0.95, 0.85, 0.2))
	_line(s, Vector2(lane_x + 1.8, lane_z0 + 4.0), Vector2(lane_x + 1.8, tc.y - 4.0), 0.12, Color(0.95, 0.85, 0.2))
	for k in 3:
		_arrow(s, Vector2(lane_x, lane_z0 + 4.0 + k * 5.0), Vector2(0.0, 1.0))
	var pay := Vector2(lane_x - 2.6, tc.y - 6.5)
	_inst(s, "rs_spk", RoadsideKit.speaker_post(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(pay.x, s.dy(pay.x, pay.y), pay.y)), Color(accent.r, accent.g, accent.b, 0.3))
	var cy := s.dy(lane_x, pay.y)
	for k in 2:
		var px := lane_x + (-2.6 if k == 0 else 2.6)
		pen.cyl(Vector3(px, cy, pay.y), 0.1, 0.1, 3.6, K.c(Color(0.7, 0.71, 0.72), K.K_STEEL), K.RM_STEEL, 10)
	pen.box(Vector3(lane_x, cy + 3.7, pay.y), Vector3(6.0, 0.3, 3.2), K.c(accent, K.K_FIXED), K.RM_PAINT)
	pen.face(Vector3(lane_x - 2.6, cy + 3.54, pay.y - 1.2), Vector3(lane_x + 2.6, cy + 3.54, pay.y - 1.2), Vector3(lane_x + 2.6, cy + 3.54, pay.y + 1.2), Vector3(lane_x - 2.6, cy + 3.54, pay.y + 1.2),
		[Vector2(0, 0), Vector2(5.2, 0), Vector2(5.2, 2.4), Vector2(0, 2.4)], Vector3.DOWN, K.c(Color(1, 1, 1), K.K_SOFFIT), Vector2(0.25, 0.0))
	s.ch._add_shape(Vector3(6.0, 0.3, 3.2), s.at(Vector3(lane_x, cy + 3.7, pay.y)), s.yaw)
	# Cars waiting in the lane.
	var nq := 1 + s.rng.randi() % 3
	for k in nq:
		_car(s, Vector2(lane_x, pay.y - 1.0 - k * 6.0), PI)
	# Vacuum stations in a row along the street side, a stall either side of each.
	var vz := -hd + 5.5
	var vx0 := lane_x + 5.5
	var nvac := clampi(int((hw - 1.5 - vx0) / 6.0), 1, 6)
	for k in nvac:
		var vx := vx0 + 3.0 + k * 6.0
		_inst(s, "rs_vac", RoadsideKit.vacuum(), Transform3D(Basis(), Vector3(vx, s.dy(vx, vz), vz)), Color(accent.r, accent.g, accent.b, 0.6))
		s.ch._add_shape(Vector3(0.7, 1.2, 0.7), s.at(Vector3(vx, 0.6, vz)), s.yaw)
		for sd: float in [-1.0, 1.0]:
			_line(s, Vector2(vx + sd * 3.0, vz - 2.0), Vector2(vx + sd * 3.0, vz + 3.0), 0.1)
			if s.rng.randf() < 0.35:
				_car(s, Vector2(vx + sd * 1.5, vz + 0.5), PI if s.rng.randf() < 0.5 else 0.0)
	_frontage(s, [Vector2(lane_x - 2.5, lane_x + 2.5), Vector2(hw - 9.0, hw - 2.0)])
	_pool(s, Vector2(tc.x, tc.y), Vector2(L + 8.0, tw + 6.0), Color(0.85, 0.92, 1.0, 1.0))
	_pool(s, Vector2((vx0 + hw) * 0.5, vz), Vector2(hw - vx0 + 4.0, 8.0), Color(1.0, 0.97, 0.9, 0.8))
	_light(s, Vector3(tc.x, th - 1.0, tc.y), 14.0, Color(0.85, 0.92, 1.0))


## An LED arch across the tunnel (the coloured light show at the entrance and in the middle).
static func _wash_arch(s: Site, x: float, zc: float, tw: float, th: float, accent: Color, entrance: bool) -> void:
	var K := RoadsideKit
	var pen := s.pen
	var seg := 9
	var pts := []
	for k in seg + 1:
		var a := PI * float(k) / seg
		pts.append(Vector3(x, 0.2 + sin(a) * (th - 0.9), zc - cos(a) * (tw * 0.5 - 0.5)))
	pen.tube(pts, 0.12, K.c(Color(0.65, 0.66, 0.68), K.K_STEEL), K.RM_STEEL, 8)
	var lit := [Color(0.95, 0.2, 0.7), Color(0.2, 0.5, 1.0), Color(0.2, 1.0, 0.6), accent]
	for k in seg:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var m := (a + b) * 0.5
		var inward := (Vector3(x, 0.2, zc) - m).normalized()
		pen.tube([a + inward * 0.13, b + inward * 0.13], 0.045, K.c(lit[k % lit.size()] if entrance else lit[(k + 2) % lit.size()], K.K_NEON), K.RM_PLASTIC, 6)


# --- Auto repair and tyre shop ---------------------------------------------------------------

static func _auto(s: Site) -> void:
	var K := RoadsideKit
	var hw := s.w * 0.5
	var hd := s.d * 0.5
	var names: Array = AUTO_NAMES[s.rng.randi() % AUTO_NAMES.size()]
	var tyres_shop: bool = String(names[0]).contains("TIRE")
	var bw := clampf(s.w - 4.0, 13.0, 28.0)
	var bd := clampf(s.d * 0.45, 9.0, 13.0)
	var h := 5.4
	var bld := Rect2(-bw * 0.5, hd - 1.5 - bd, bw, bd)
	var wall: Color = SHOP_PAINTS[s.rng.randi() % SHOP_PAINTS.size()]
	_shell(s, bld, h, wall, true, 1.2)
	if not s.full:
		return
	var pen := s.pen
	var front := bld.position.y
	var col := K.c(wall, K.K_STUCCO)
	# The front: an office at one end, roll-up bays along the rest, piers between them.
	var office_w := 3.6
	var office_left := s.rng.randf() < 0.5
	var bx0 := bld.position.x + (office_w if office_left else 0.0)
	var bx1 := bld.end.x - (0.0 if office_left else office_w)
	var n_bays := clampi(int((bx1 - bx0 - 0.6) / 4.3), 2, 5)
	var pitch := (bx1 - bx0) / n_bays
	var door_w := pitch - 0.9
	var door_h := 4.0
	var open_count := 0
	var paint_cols := [Color(0.72, 0.1, 0.08), Color(0.08, 0.2, 0.55), Color(0.1, 0.1, 0.12)]
	var sign_col: Color = paint_cols[s.rng.randi() % paint_cols.size()]
	pen.box(Vector3(bld.get_center().x, (door_h + h + 1.2) * 0.5, front + 0.15), Vector3(bw, h + 1.2 - door_h, 0.3), col, K.RM_MATTE)
	for i in n_bays + 1:
		var px := bx0 + i * pitch
		pen.box(Vector3(px, (door_h - SKIRT) * 0.5, front + 0.15), Vector3(0.9 if i > 0 and i < n_bays else 0.45, door_h + SKIRT, 0.36), col, K.RM_MATTE)
	# Inside: the floor, the back wall's inner face (the shell's), strip lights, benches, a lift.
	_ground(s, Rect2(bld.position.x + 0.3, front + 0.3, bw - 0.6, bd - 0.6), K.c(Color(0.5, 0.5, 0.49), K.K_CONCRETE))
	for i in n_bays:
		var cx := bx0 + (i + 0.5) * pitch
		var open := s.rng.randf() < 0.55
		if open:
			open_count += 1
			# The door rolled up into its hood; light inside; a car on the lift or on the floor.
			pen.box(Vector3(cx, door_h + 0.25, front + 0.45), Vector3(door_w + 0.2, 0.5, 0.5), K.c(Color(0.6, 0.6, 0.6), K.K_STEEL), K.RM_STEEL, 0.03)
			pen.box(Vector3(cx, h - 0.15, front + bd * 0.5), Vector3(0.25, 0.06, bd - 1.5), K.c(Color(0.95, 0.97, 1.0), K.K_NEON), K.RM_PLASTIC)
			var lifted := s.rng.randf() < 0.6
			var cz := front + bd * 0.5
			if lifted:
				_inst(s, "rs_lift", RoadsideKit.lift(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(cx, 0.0, cz)))
				_car(s, Vector2(cx, cz), PI, Color(-1, 0, 0), 1.55 - s.dy(cx, cz))
			elif s.rng.randf() < 0.7:
				_car(s, Vector2(cx, cz + 0.5), PI)
			# Tool chest and a bench against the back wall.
			pen.box(Vector3(cx - door_w * 0.3, 0.55, bld.end.y - 0.65), Vector3(1.0, 1.1, 0.6), K.c(Color(0.7, 0.06, 0.05), K.K_FIXED), K.RM_PAINT, 0.02)
			pen.box(Vector3(cx + door_w * 0.25, 0.45, bld.end.y - 0.55), Vector3(1.6, 0.9, 0.5), K.c(Color(0.35, 0.36, 0.38), K.K_STEEL), K.RM_STEEL)
			pen.box(Vector3(cx, 1.9, bld.end.y - 0.32), Vector3(door_w - 0.4, 1.2, 0.03), K.c(Color(0.55, 0.47, 0.35), K.K_FIXED), K.RM_MATTE)
			s.ch._add_shape(Vector3(pitch, 0.1, 0.1), s.at(Vector3(cx, door_h + 0.25, front + 0.45)), s.yaw)
		else:
			pen.face(Vector3(cx - door_w * 0.5, 0.0, front + 0.3), Vector3(cx + door_w * 0.5, 0.0, front + 0.3), Vector3(cx + door_w * 0.5, door_h, front + 0.3), Vector3(cx - door_w * 0.5, door_h, front + 0.3),
				[Vector2(0.0, 0.0), Vector2(door_w, 0.0), Vector2(door_w, door_h), Vector2(0.0, door_h)], Vector3(0, 0, -1), K.c(Color(0.78, 0.79, 0.8) if i % 2 == 0 else Color(0.85, 0.85, 0.83), K.K_ROLLUP), Vector2(0.45, 0.5))
			pen.box(Vector3(cx, door_h - 0.05, front + 0.2), Vector3(door_w + 0.1, 0.1, 0.12), K.c(Color(0.4, 0.4, 0.42), K.K_STEEL), K.RM_STEEL)
			s.ch._add_shape(Vector3(pitch, door_h, 0.3), s.at(Vector3(cx, door_h * 0.5, front + 0.3)), s.yaw)
		# Bay numbers and a wall pack over each door.
		pen.box(Vector3(cx, door_h + 0.17, front - 0.05), Vector3(0.3, 0.14, 0.12), K.c(Color(0.95, 0.9, 0.75), K.K_NEON), K.RM_PLASTIC)
		_pool(s, Vector2(cx, front - 3.0), Vector2(door_w + 2.5, 6.0), Color(1.0, 0.86, 0.6, 0.7))
	# The office: a shopfront window and a door.
	var ox0 := bld.position.x + 0.3 if office_left else bx1
	var ox1 := bx0 if office_left else bld.end.x - 0.3
	pen.box(Vector3((ox0 + ox1) * 0.5, (door_h - SKIRT) * 0.5, front + 0.15), Vector3(ox1 - ox0, door_h + SKIRT, 0.3), col, K.RM_MATTE)
	_storefront(s, front - 0.02, ox0 + 0.2, ox1 - 0.2, 2.9, 3.2, K.Room.STORE, ox0 + (ox1 - ox0) * 0.7)
	# The hand-painted sign on the header band, the services under it.
	var band_y := door_h + (h + 1.2 - door_h) * 0.5
	pen.box(Vector3(bld.get_center().x, band_y, front - 0.012), Vector3(bw - 0.6, h + 1.0 - door_h, 0.02), K.c(Color(0.96, 0.94, 0.88), K.K_SIGNPAINT), K.RM_MATTE)
	s.pen.text(names[0], 0.9, Vector3(bld.get_center().x, band_y + 0.32, front - 0.03), Vector3(0, 0, -1), K.c(sign_col, K.K_SIGNPAINT), bw - 1.5)
	s.pen.text(names[1], 0.42, Vector3(bld.get_center().x, band_y - 0.55, front - 0.03), Vector3(0, 0, -1), K.c(Color(0.08, 0.08, 0.1), K.K_SIGNPAINT), bw - 2.5)
	# Painted on the side wall too, big.
	var sx := bld.position.x - 0.03 if office_left else bld.end.x + 0.03
	var sout := Vector3(-1, 0, 0) if office_left else Vector3(1, 0, 0)
	s.pen.text(names[0].split(" ")[0] + (" TIRES" if tyres_shop else " AUTO"), 1.1, Vector3(sx, h * 0.6, bld.get_center().y), sout, K.c(sign_col, K.K_SIGNPAINT), bd - 1.5)
	# Tyres: stacks along the front wall either side of the doors and a rack at the side.
	var stacks := 6 if tyres_shop else 3
	var tyre := RoadsideKit.tyre()
	for k in stacks:
		var tx := lerpf(bld.position.x + 0.6, bld.end.x - 0.6, s.rng.randf())
		if not office_left and tx > bx1 - 0.6:
			tx = bx1 - 0.6
		var dz := front - 0.55 - s.rng.randf() * 0.3
		var nstack := 3 + s.rng.randi() % 6
		var base_y := s.dy(tx, dz)
		for j in nstack:
			_inst(s, "rs_tyre", tyre, Transform3D(Basis(Vector3.UP, s.rng.randf() * TAU), Vector3(tx + s.rng.randf_range(-0.04, 0.04), base_y + 0.11 + j * 0.22, dz)))
	if tyres_shop:
		# Tyres leaning on the wall in a row, and a tall display rack at the side.
		var rx := bld.end.x + 1.0 if office_left else bld.position.x - 1.0
		for j in 10:
			var tz := front + 0.6 + j * 0.42
			if tz > bld.end.y - 0.5:
				break
			var lean := Basis(Vector3.FORWARD, PI * 0.5 - 0.2 * (1.0 if office_left else -1.0))
			_inst(s, "rs_tyre", tyre, Transform3D(Basis(Vector3.UP, PI * 0.5) * lean, Vector3(rx - 0.0, s.dy(rx, tz) + 0.34, tz)))
		for row in 3:
			var ry := 0.4 + row * 0.75
			pen.box(Vector3(rx, ry - 0.05, front + 3.5), Vector3(0.5, 0.05, 6.0), K.c(Color(0.2, 0.3, 0.6), K.K_FIXED), K.RM_PAINT)
	# The junked car on the side, and customers' cars in front.
	var jx := bld.end.x + 2.8 if office_left else bld.position.x - 2.8
	jx = clampf(jx, -hw + 2.4, hw - 2.4)
	if absf(jx) < hw - 1.0:
		_car(s, Vector2(jx, bld.end.y - 3.0), PI * 0.5 + s.rng.randf_range(-0.2, 0.2), CAR_JUNK[s.rng.randi() % CAR_JUNK.size()], -0.12)
	var ncars := 1 + s.rng.randi() % 3
	for k in ncars:
		_car(s, Vector2(lerpf(-hw + 3.0, hw - 3.0, (k + 0.5) / ncars), front - 4.5), PI + s.rng.randf_range(-0.1, 0.1))
	_frontage(s, [Vector2(-hw + 1.0, hw - 1.0)])
	_light(s, Vector3(bld.get_center().x, door_h + 0.6, front - 1.0), 12.0, Color(1.0, 0.85, 0.6))
	if open_count == 0:
		_pool(s, Vector2(bld.get_center().x, front - 2.0), Vector2(bw, 4.0), Color(1.0, 0.86, 0.6, 0.5))


# --- The Googie coffee shop ------------------------------------------------------------------

static func _diner(s: Site) -> void:
	var K := RoadsideKit
	var hw := s.w * 0.5
	var hd := s.d * 0.5
	var bname: String = DINER_NAMES[s.rng.randi() % DINER_NAMES.size()]
	var bw := clampf(s.w * 0.62, 13.0, 22.0)
	var bd := clampf(s.d * 0.42, 9.5, 14.0)
	var bx := (hw - 2.0 - bw * 0.5) * (0.6 if s.rng.randf() < 0.5 else -0.6)
	var bld := Rect2(bx - bw * 0.5, hd - 2.5 - bd, bw, bd)
	var roof_col: Color = [Color(0.95, 0.94, 0.9), Color(0.4, 0.75, 0.72), Color(0.92, 0.55, 0.3)][s.rng.randi() % 3]
	var neon: Color = [Color(1.0, 0.25, 0.55), Color(0.2, 0.9, 1.0), Color(1.0, 0.55, 0.15)][s.rng.randi() % 3]
	_mass(s, Vector3(bld.get_center().x, 2.6, bld.get_center().y), Vector3(bw, 5.2, bd), roof_col)
	if not s.full:
		return
	var pen := s.pen
	var front := bld.position.y
	var stone := K.c(Color(0.62, 0.52, 0.42), 19)
	var stucco := K.c(Color(0.95, 0.93, 0.88), K.K_STUCCO)
	# Back wall (kitchen), a stone side wall, the other side glazed round the corner.
	var hroof := 4.2
	pen.box(Vector3(bld.get_center().x, (hroof - SKIRT) * 0.5, bld.end.y - 0.15), Vector3(bw, hroof + SKIRT, 0.3), stucco, K.RM_MATTE)
	var stone_left := bx > 0.0
	var sx := bld.position.x + 0.25 if stone_left else bld.end.x - 0.25
	pen.box(Vector3(sx, (hroof - SKIRT) * 0.5, bld.get_center().y), Vector3(0.5, hroof + SKIRT, bd), stone, K.RM_MATTE)
	var gx := bld.end.x - 0.05 if stone_left else bld.position.x + 0.05
	var gout := Vector3(1, 0, 0) if stone_left else Vector3(-1, 0, 0)
	var nside := int(bd / 2.2)
	for k in nside:
		var wz := front + 1.0 + (k + 0.5) * (bd - 2.0) / nside
		pen.window(Vector3(gx, 0.0, wz), gout, (bd - 2.0) / nside - 0.08, 0.0, 0.75, 3.4, bw - 2.0, K.Room.DINER)
		pen.box(Vector3(gx, 1.9, front + 1.0 + k * (bd - 2.0) / nside), Vector3(0.12, 3.8, 0.08), K.c(Color(0.8, 0.8, 0.82), K.K_STEEL), K.RM_STEEL)
	pen.box(Vector3(gx, (0.75 - SKIRT) * 0.5, bld.get_center().y), Vector3(0.2, 0.75 + SKIRT, bd), stone, K.RM_MATTE)
	s.ch._add_shape(Vector3(bw, hroof, bd), s.at(Vector3(bld.get_center().x, hroof * 0.5, bld.get_center().y + 0.5)), s.yaw)
	_ground(s, Rect2(bld.position.x, front, bw, bd), K.c(Color(0.6, 0.58, 0.55), K.K_CONCRETE))
	# The front: glass leaning out (the head 1.1 m further out than the sill), on a stone base.
	var lean := 1.1
	var n := maxi(int(bw / 1.9), 3)
	for k in n:
		var x0 := bld.position.x + 0.5 + k * (bw - 1.0) / n
		var x1 := x0 + (bw - 1.0) / n
		var zb := front
		var zt := front - lean
		var yb := 0.75
		var yt := 3.7
		pen.face(Vector3(x0 + 0.04, yb, zb), Vector3(x1 - 0.04, yb, zb), Vector3(x1 - 0.04, yt, zt), Vector3(x0 + 0.04, yt, zt),
			[Vector2(0.0, yb), Vector2(x1 - x0, yb), Vector2(x1 - x0, yt), Vector2(0.0, yt)], Vector3(0.0, 0.35, -1.0), K.c(Color(0.1, 0.12, 0.13), K.K_ROOM), Vector2(bd - 1.5, float(K.Room.DINER)))
		pen.tube([Vector3(x0, yb, zb - 0.03), Vector3(x0, yt, zt - 0.03)], 0.05, K.c(Color(0.82, 0.83, 0.85), K.K_STEEL), K.RM_STEEL, 6)
	pen.tube([Vector3(bld.end.x - 0.5, 0.75, front - 0.03), Vector3(bld.end.x - 0.5, 3.7, front - lean - 0.03)], 0.05, K.c(Color(0.82, 0.83, 0.85), K.K_STEEL), K.RM_STEEL, 6)
	pen.box(Vector3(bld.get_center().x, 0.37 - SKIRT * 0.5, front - 0.1), Vector3(bw, 0.75 + SKIRT, 0.4), stone, K.RM_MATTE)
	pen.box(Vector3(bld.get_center().x, 0.77, front - 0.25), Vector3(bw, 0.06, 0.7), K.c(Color(0.85, 0.85, 0.83), K.K_FIXED), K.RM_PAINT)
	# The roof: a folded plate that sweeps up and out over the glass to a sharp lip, its soffit
	# lit by a cove of neon along the edge. A profile in (z, y), swept across the building.
	var prof := []
	for k in 9:
		var t := float(k) / 8.0
		var z := lerpf(bld.end.y + 0.8, front - lean - 3.2, t)
		var y := hroof + 0.15 + pow(t, 2.4) * 2.6
		prof.append(Vector2(z, y))
	var xl := bld.position.x - 1.2
	var xr := bld.end.x + 1.2
	for k in prof.size() - 1:
		var a: Vector2 = prof[k]
		var b: Vector2 = prof[k + 1]
		# Upper face, soffit, and the ends.
		pen.quad(Vector3(xl, a.y, a.x), Vector3(xr, a.y, a.x), Vector3(xr, b.y, b.x), Vector3(xl, b.y, b.x), Vector3(0.0, 1.0, 0.0), K.c(roof_col, K.K_FIXED), Vector2(0.5, 0.0))
		pen.quad(Vector3(xl, a.y - 0.32, a.x), Vector3(xr, a.y - 0.32, a.x), Vector3(xr, b.y - 0.32, b.x), Vector3(xl, b.y - 0.32, b.x), Vector3(0.0, -1.0, 0.0), K.c(Color(0.92, 0.88, 0.8), K.K_FIXED), Vector2(0.7, 0.0))
		for ex: float in [xl, xr]:
			pen.quad(Vector3(ex, a.y, a.x), Vector3(ex, b.y, b.x), Vector3(ex, b.y - 0.32, b.x), Vector3(ex, a.y - 0.32, a.x), Vector3(signf(ex - bld.get_center().x), 0.0, 0.0), K.c(roof_col.darkened(0.15), K.K_FIXED), Vector2(0.5, 0.0))
	var lip: Vector2 = prof[prof.size() - 1]
	pen.quad(Vector3(xl, lip.y, lip.x), Vector3(xr, lip.y, lip.x), Vector3(xr, lip.y - 0.32, lip.x), Vector3(xl, lip.y - 0.32, lip.x), Vector3(0, 0, -1), K.c(roof_col.darkened(0.2), K.K_FIXED), Vector2(0.5, 0.0))
	pen.tube([Vector3(xl, lip.y - 0.34, lip.x + 0.06), Vector3(xr, lip.y - 0.34, lip.x + 0.06)], 0.035, K.c(neon, K.K_NEON), K.RM_PLASTIC, 6)
	for ex: float in [xl, xr]:
		var path := []
		for p: Vector2 in prof:
			path.append(Vector3(ex, p.y - 0.34, p.x))
		pen.tube(path, 0.03, K.c(neon, K.K_NEON), K.RM_PLASTIC, 6)
	s.ch._add_shape(Vector3(xr - xl, 0.4, bd + lean + 4.0), s.at(Vector3(bld.get_center().x, hroof + 0.6, (bld.end.y + front - lean - 3.2) * 0.5)), s.yaw)
	# Recessed downlights in the soffit over the glass and the walk, following the sweep.
	for k in range(4, prof.size() - 1):
		var a: Vector2 = prof[k]
		var b: Vector2 = prof[k + 1]
		var m := (a + b) * 0.5
		var nl := maxi(int((xr - xl) / 2.4), 2)
		for j in nl:
			var lx2 := xl + (j + 0.5) * (xr - xl) / nl
			var tilt := atan2(b.y - a.y, -(b.x - a.x))
			pen.box(Vector3(lx2, m.y - 0.335, m.x), Vector3(0.32, 0.02, 0.32), K.c(Color(1.0, 0.92, 0.78), K.K_SOFFIT), Vector2(0.25, 0.0), 0.0, Basis(Vector3.RIGHT, tilt))
	# A raked steel post props the lip at each corner; a stone pylon through the roof at the side.
	for ex: float in [xl + 0.6, xr - 0.6]:
		pen.tube([Vector3(ex, s.dy(ex, lip.x + 1.4), lip.x + 1.4), Vector3(ex, lip.y - 0.5, lip.x + 0.6)], 0.09, K.c(Color(0.92, 0.92, 0.9), K.K_FIXED), K.RM_PAINT, 8)
	var py := Vector3(sx, 0.0, front + 1.5)
	pen.box(Vector3(py.x, 3.6, py.z), Vector3(1.2, 7.2 + SKIRT, 1.4), stone, K.RM_MATTE)
	pen.box(Vector3(py.x - gout.x * 0.62, 5.4, py.z), Vector3(0.06, 2.8, 1.0), K.c(neon, K.K_NEON), K.RM_PLASTIC)
	# Inside the glass after dark, the coffee shop's own word in the window.
	pen.text("COFFEE SHOP", 0.32, Vector3(bld.get_center().x, 3.2, front - lean * 0.85 - 0.05), Vector3(0.0, 0.35, -1.0).normalized(), K.c(neon, K.K_NEON), bw * 0.4)
	# --- The starburst pole sign at the street corner.
	_googie_sign(s, Vector2(-signf(bx) * (hw - 2.5) if bx != 0.0 else hw - 2.5, -hd + 2.0), bname, neon, roof_col)
	# Parking in front with a couple of cars, planters with palms by the door.
	for k in int(bw / 2.8):
		var px := bld.position.x + k * 2.8
		_line(s, Vector2(px, front - lean - 9.5), Vector2(px, front - lean - 4.6), 0.1)
	for k in 1 + s.rng.randi() % 3:
		_car(s, Vector2(bld.position.x + 1.4 + (k * 2 + s.rng.randi() % 2) * 2.8, front - lean - 7.0), PI)
	for ex: float in [bld.position.x - 0.5, bld.end.x + 0.5]:
		if absf(ex) < hw - 1.0:
			pen.box(Vector3(ex, s.dy(ex, front - 2.0) + 0.3, front - 2.0), Vector3(1.4, 0.6, 1.4), stone, K.RM_MATTE)
			var pw := s.at(Vector3(ex, 0.0, front - 2.0))
			s.ch._add_palm(Vector3(pw.x, TOP + 0.6, pw.z), s.rng, false)
	_frontage(s, [Vector2(-hw + 1.5, -hw + 8.0), Vector2(hw - 8.0, hw - 1.5)])
	_pool(s, Vector2(bld.get_center().x, front - 3.0), Vector2(bw + 4.0, 8.0), Color(1.0, 0.85, 0.65, 1.0))
	_pool(s, Vector2(bld.get_center().x, front - 3.0), Vector2(bw + 2.0, 5.0), Color(neon.r, neon.g, neon.b, 0.45))
	_light(s, Vector3(bld.get_center().x, 4.0, front - 2.5), 14.0, Color(1.0, 0.82, 0.62))


## The Googie pole sign: two raked steel masts, a boomerang board lit inside with the name, a
## band of chasing bulbs round its edge, and on top an atomic starburst of spikes tipped with bulbs.
static func _googie_sign(s: Site, p: Vector2, bname: String, neon: Color, accent: Color) -> void:
	var K := RoadsideKit
	var pen := s.pen
	var y0 := s.dy(p.x, p.y)
	pen.box(Vector3(p.x, y0 + 0.25, p.y), Vector3(2.4, 0.6, 1.4), K.c(Color(0.62, 0.52, 0.42), 19), K.RM_MATTE)
	for k in 2:
		var bx := p.x + (-0.5 if k == 0 else 0.5)
		pen.tube([Vector3(bx, y0 + 0.4, p.y), Vector3(bx + (0.6 if k == 0 else 0.2), y0 + 12.6, p.y)], 0.16, K.c(Color(0.92, 0.3, 0.12) if k == 0 else Color(0.95, 0.93, 0.88), K.K_FIXED), K.RM_PAINT, 10)
	s.ch._add_shape(Vector3(1.6, 12.0, 0.5), s.at(Vector3(p.x, y0 + 6.0, p.y)), s.yaw)
	# The boomerang: a polygon in the sign's plane, extruded 0.5 m, from 6.5 to 10.5 m up.
	var outline := []
	for k in 17:
		var t := float(k) / 16.0
		outline.append(Vector2(lerpf(-3.2, 3.4, t), 8.7 + sin(t * PI) * 1.3 - t * 0.8))
	for k in 17:
		var t := 1.0 - float(k) / 16.0
		outline.append(Vector2(lerpf(-3.2, 3.4, t), 7.0 + sin(t * PI) * 0.6 - t * 0.5 + 0.2 * (1.0 - t)))
	var cx := p.x
	var half := 0.25
	var faces := [-1.0, 1.0]
	var mid := Vector2(0.0, 8.1)
	for sd: float in faces:
		var z := p.y + sd * half
		for k in outline.size():
			var a: Vector2 = outline[k]
			var b: Vector2 = outline[(k + 1) % outline.size()]
			pen.face(Vector3(cx + mid.x, y0 + mid.y, z), Vector3(cx + a.x, y0 + a.y, z), Vector3(cx + b.x, y0 + b.y, z), Vector3(cx + mid.x, y0 + mid.y, z),
				[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3(0, 0, sd), K.c(accent if accent.v > 0.6 else Color(0.97, 0.95, 0.88), K.K_LIGHTBOX), Vector2(0.3, 0.0))
		_letters_flat(s, bname, Vector3(cx + 0.1, y0 + 8.35, z + sd * 0.02), 0.95, Color(0.85, 0.1, 0.12) if accent.v > 0.6 else Color(0.1, 0.45, 0.5), 5.4, Vector3(0, 0, sd))
		_letters_flat(s, "OPEN 24 HOURS", Vector3(cx + 0.3, y0 + 7.68, z + sd * 0.02), 0.26, Color(0.12, 0.12, 0.14), 3.2, Vector3(0, 0, sd))
	for k in outline.size():
		var a: Vector2 = outline[k]
		var b: Vector2 = outline[(k + 1) % outline.size()]
		var out := Vector3(b.y - a.y, -(b.x - a.x), 0.0).normalized()
		pen.quad(Vector3(cx + a.x, y0 + a.y, p.y - half), Vector3(cx + b.x, y0 + b.y, p.y - half), Vector3(cx + b.x, y0 + b.y, p.y + half), Vector3(cx + a.x, y0 + a.y, p.y + half), -out, K.c(Color(0.9, 0.3, 0.12), K.K_FIXED), K.RM_PAINT)
		# Chasing bulbs round the edge.
		for sd: float in faces:
			var bp := Vector3(cx + a.x, y0 + a.y, p.y + sd * (half + 0.02))
			s.pen.face(bp + Vector3(-0.07, -0.07, 0.0), bp + Vector3(0.07, -0.07, 0.0), bp + Vector3(0.07, 0.07, 0.0), bp + Vector3(-0.07, 0.07, 0.0),
				[Vector2(float(k), 0), Vector2(float(k), 0), Vector2(float(k), 0), Vector2(float(k), 0)], Vector3(0, 0, sd), K.c(Color(1.0, 0.85, 0.55), K.K_BULB), Vector2(0.2, 0.0))
	# The starburst: a ball and a dozen spikes in 3D, a bulb at each tip.
	var star := Vector3(p.x + 0.7, y0 + 13.4, p.y)
	pen.cyl(star + Vector3(0.0, -0.3, 0.0), 0.3, 0.3, 0.6, K.c(neon, K.K_NEON), K.RM_PLASTIC, 12)
	for k in 14:
		var u := float(k) / 14.0
		var a := u * TAU * 2.618
		var yy := 1.0 - 2.0 * (u + 0.5 / 14.0)
		var r := sqrt(1.0 - yy * yy)
		var dir := Vector3(cos(a) * r, yy, sin(a) * r * 0.55).normalized()
		var len := 1.2 + 0.8 * float(k % 3) / 2.0
		pen.cyl(star, 0.07, 0.015, len, K.c(Color(0.95, 0.85, 0.3), K.K_FIXED), K.RM_STEEL, 6, _basis_to(dir))
		var tip := star + dir * len
		pen.box(tip, Vector3(0.18, 0.18, 0.18), K.c(Color(1.0, 0.9, 0.6), K.K_BULB), Vector2(0.2, 0.0), 0.04)
	_pool(s, p, Vector2(9.0, 9.0), Color(neon.r, neon.g, neon.b, 0.5))


## A basis whose y is `dir` (for a cylinder pointing that way).
static func _basis_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# --- Fast food with a drive-thru -------------------------------------------------------------

static func _fast_food(s: Site) -> void:
	var K := RoadsideKit
	var hw := s.w * 0.5
	var hd := s.d * 0.5
	var bname: String = FAST_NAMES[s.rng.randi() % FAST_NAMES.size()]
	var brand: Color = [Color(0.78, 0.1, 0.08), Color(0.95, 0.6, 0.08), Color(0.1, 0.42, 0.25), Color(0.15, 0.25, 0.6)][s.rng.randi() % 4]
	var lane_w := 3.8
	var bw := clampf(s.w - 2.0 * lane_w - 4.0, 9.0, 16.0)
	var bd := clampf(s.d - lane_w - 12.0, 6.5, 12.0)
	var back_lane_z := hd - 1.0 - lane_w * 0.5
	var bld := Rect2(-bw * 0.5, back_lane_z - lane_w * 0.5 - 0.6 - bd, bw, bd)
	var h := 4.6
	var wall: Color = [Color(0.92, 0.88, 0.8), Color(0.75, 0.62, 0.5), Color(0.86, 0.86, 0.84)][s.rng.randi() % 3]
	_shell(s, bld, h, wall, true, 0.9)
	# The entrance tower in the brand colour.
	var tower := Vector3(bld.position.x + bw * 0.3, (h + 2.4) * 0.5, bld.position.y + 1.0)
	_mass(s, tower, Vector3(3.2, h + 2.4, 2.2), brand)
	if not s.full:
		return
	var pen := s.pen
	var front := bld.position.y
	pen.box(Vector3(tower.x, (h + 2.4 - SKIRT) * 0.5, tower.z), Vector3(3.2, h + 2.4 + SKIRT, 2.2), K.c(brand, K.K_FIXED), K.RM_PAINT, 0.03)
	pen.box(Vector3(tower.x, h + 1.4, front - 0.12), Vector3(2.6, 1.2, 0.06), K.c(Color(0.98, 0.96, 0.9), K.K_LIGHTBOX), K.RM_PLASTIC)
	_letters_flat(s, bname.split(" ")[0], Vector3(tower.x, h + 1.4, front - 0.16), 0.5, brand, 2.4, Vector3(0, 0, -1))
	# Front glazing with the dining room traced behind, a brand band round the roof edge.
	pen.box(Vector3(bld.get_center().x, (3.1 + h + 0.9) * 0.5, front + 0.15), Vector3(bw, h + 0.9 - 3.1, 0.3), K.c(wall, K.K_STUCCO), K.RM_MATTE)
	var tx0 := tower.x + 1.6
	_storefront(s, front + 0.05, bld.position.x + 0.3, tower.x - 1.6, 3.1, bd - 1.5, K.Room.DINING, bld.position.x + 1.4)
	_storefront(s, front + 0.05, tx0, bld.end.x - 0.3, 3.1, bd - 1.5, K.Room.DINING, 99.0)
	for e in 3:
		var o := Vector3(bld.get_center().x, h + 0.5, front - 0.08) if e == 0 else Vector3(bld.position.x - 0.08 if e == 1 else bld.end.x + 0.08, h + 0.5, bld.get_center().y)
		var sz := Vector3(bw + 0.2, 0.55, 0.12) if e == 0 else Vector3(0.12, 0.55, bd + 0.2)
		pen.box(o, sz, K.c(brand, K.K_LIGHTBOX), K.RM_PLASTIC)
	_letters_flat(s, bname, Vector3(bld.get_center().x + bw * 0.12, h - 0.15, front - 0.15), 0.42, brand, bw * 0.45, Vector3(0, 0, -1))
	# The drive-thru loop: up the left side, across the back (menu board and speaker on the
	# driver's left, against the pad's back edge), down the right side past the window.
	var lx := bld.position.x - 0.6 - lane_w * 0.5
	var rx := bld.end.x + 0.6 + lane_w * 0.5
	var z_in := -hd + 2.0
	var path := [Vector2(lx, z_in), Vector2(lx, back_lane_z), Vector2(rx, back_lane_z), Vector2(rx, z_in)]
	# Curbed island on the outer edge, painted lane lines, arrows.
	_line(s, Vector2(lx - lane_w * 0.5, front - 2.0), Vector2(lx - lane_w * 0.5, back_lane_z + lane_w * 0.5), 0.12, Color(0.95, 0.85, 0.2))
	_line(s, Vector2(lx - lane_w * 0.5, back_lane_z + lane_w * 0.5), Vector2(rx + lane_w * 0.5, back_lane_z + lane_w * 0.5), 0.12, Color(0.95, 0.85, 0.2))
	_line(s, Vector2(rx + lane_w * 0.5, back_lane_z + lane_w * 0.5), Vector2(rx + lane_w * 0.5, front - 2.0), 0.12, Color(0.95, 0.85, 0.2))
	_arrow(s, Vector2(lx, front + 1.0), Vector2(0, 1))
	_arrow(s, Vector2(0.0, back_lane_z), Vector2(1, 0))
	_arrow(s, Vector2(rx, front + 2.0), Vector2(0, -1))
	# The clearance bar at the lane's mouth with DRIVE THRU on it.
	var gz := front - 1.5
	var gy := s.dy(lx, gz)
	for sd: float in [-1.0, 1.0]:
		pen.cyl(Vector3(lx + sd * (lane_w * 0.5 + 0.2), gy, gz), 0.1, 0.1, 3.0, K.c(Color(0.95, 0.8, 0.1), K.K_FIXED), K.RM_PAINT, 10)
		s.ch._add_shape(Vector3(0.2, 3.0, 0.2), s.at(Vector3(lx + sd * (lane_w * 0.5 + 0.2), gy + 1.5, gz)), s.yaw)
	pen.box(Vector3(lx, gy + 3.05, gz), Vector3(lane_w + 0.7, 0.5, 0.2), K.c(brand, K.K_LIGHTBOX), K.RM_PLASTIC)
	_letters_flat(s, "DRIVE THRU", Vector3(lx, gy + 3.05, gz - 0.11), 0.28, Color(0.98, 0.98, 0.96), lane_w, Vector3(0, 0, -1))
	_letters_flat(s, "CLEARANCE 9 FT 6 IN", Vector3(lx, gy + 2.72, gz - 0.11), 0.1, Color(0.1, 0.1, 0.1), lane_w * 0.6, Vector3(0, 0, -1))
	# Menu board and speaker on the back lane, facing it.
	var mb := Vector2(rx - lane_w * 0.5 - 4.0, back_lane_z + lane_w * 0.5 + 0.9)
	_inst(s, "rs_menu", RoadsideKit.menu_board(), Transform3D(Basis(), Vector3(mb.x, s.dy(mb.x, mb.y), mb.y)), Color(brand.r, brand.g, brand.b, 0.2))
	s.ch._add_shape(Vector3(3.0, 3.0, 0.5), s.at(Vector3(mb.x, 1.5, mb.y)), s.yaw)
	var pre := Vector2(mb.x - 7.0, mb.y)
	if pre.x > lx + 1.0:
		_inst(s, "rs_menu", RoadsideKit.menu_board(), Transform3D(Basis().scaled(Vector3(0.6, 0.8, 1.0)), Vector3(pre.x, s.dy(pre.x, pre.y), pre.y)), Color(brand.r, brand.g, brand.b, 0.7))
	var spk := Vector2(mb.x + 2.4, back_lane_z + lane_w * 0.5 + 0.3)
	_inst(s, "rs_spk", RoadsideKit.speaker_post(), Transform3D(Basis(), Vector3(spk.x, s.dy(spk.x, spk.y), spk.y)), Color(brand.r, brand.g, brand.b, 0.4))
	_pool(s, Vector2(mb.x, back_lane_z), Vector2(6.0, 5.0), Color(1.0, 0.95, 0.85, 0.9))
	# The pickup window on the right wall, under a small canopy, its room lit.
	var wz := front + bd * 0.35
	pen.window(Vector3(bld.end.x + 0.02, 0.0, wz), Vector3(1, 0, 0), 1.6, 0.0, 1.0, 2.2, 3.0, K.Room.DINING)
	pen.box(Vector3(bld.end.x + 0.06, 1.0, wz), Vector3(0.14, 0.08, 1.8), K.c(Color(0.72, 0.73, 0.75), K.K_STEEL), K.RM_STEEL)
	pen.box(Vector3(bld.end.x + 0.6, 2.8, wz), Vector3(1.2, 0.12, 3.0), K.c(brand, K.K_FIXED), K.RM_PAINT)
	pen.box(Vector3(bld.end.x + 0.6, 2.73, wz), Vector3(0.8, 0.02, 2.4), K.c(Color(1.0, 0.97, 0.9), K.K_NEON), K.RM_PLASTIC)
	_pool(s, Vector2(rx, wz), Vector2(5.0, 5.0), Color(1.0, 0.92, 0.75, 0.9))
	# The queue: cars nose to tail back from the window along the loop.
	var stops := []
	var lens := []
	var total := 0.0
	for k in path.size() - 1:
		var l := (path[k + 1] as Vector2).distance_to(path[k])
		lens.append(l)
		total += l
	var at_window := total - ((path[3] as Vector2).distance_to(Vector2(rx, wz)))
	var nq := 2 + s.rng.randi() % 4
	for q in nq:
		var sq := at_window - q * 6.2
		if sq < 2.5:
			break
		var acc := 0.0
		for k in lens.size():
			if sq <= acc + float(lens[k]):
				var a: Vector2 = path[k]
				var b: Vector2 = path[k + 1]
				var dir := (b - a).normalized()
				# Not on a corner: a car there would cut it.
				var into := sq - acc
				if into < 2.6 or float(lens[k]) - into < 2.6:
					break
				var pos := a + dir * into
				_car(s, pos, atan2(-dir.x, -dir.y))
				break
			acc += float(lens[k])
	# Parking in front of the dining room, the pylon sign at the corner.
	for k in int(bw / 2.8) + 1:
		var px := bld.position.x + k * 2.8
		_line(s, Vector2(px, front - 7.5), Vector2(px, front - 2.6), 0.1)
	if s.rng.randf() < 0.75:
		_car(s, Vector2(bld.position.x + 1.4 + 2.8 * (s.rng.randi() % maxi(int(bw / 2.8), 1)), front - 5.0), PI)
	Commercial._pylon(s.ch, _xz(s, Vector2(rx + lane_w * 0.5 + 1.2 if rx + lane_w * 0.5 + 1.2 < hw - 1.0 else hw - 2.0, -hd + 1.8)), [bname], brand, s.rng, 9.0)
	_frontage(s, [Vector2(lx - lane_w * 0.5 - 0.5, lx + lane_w * 0.5 + 0.5), Vector2(rx - lane_w * 0.5 - 0.5, rx + lane_w * 0.5 + 0.5)])
	_pool(s, Vector2(bld.get_center().x, front - 3.0), Vector2(bw + 4.0, 7.0), Color(1.0, 0.92, 0.78, 1.0))
	_light(s, Vector3(bld.get_center().x, 3.5, front - 2.0), 14.0, Color(1.0, 0.9, 0.75))


## A frame point's chunk XZ.
static func _xz(s: Site, p: Vector2) -> Vector2:
	var w := s.at(Vector3(p.x, 0.0, p.y))
	return Vector2(w.x, w.z)


# --- The stand with a giant donut or coffee cup on the roof ----------------------------------

static func _stand(s: Site) -> void:
	var K := RoadsideKit
	var hw := s.w * 0.5
	var hd := s.d * 0.5
	var pick: Array = STAND_NAMES[s.rng.randi() % STAND_NAMES.size()]
	var bname: String = pick[0]
	var cup: bool = int(pick[1]) == 1
	var bw := 9.0
	var bd := 6.5
	var h := 3.4
	var bld := Rect2(-bw * 0.5, hd - 2.0 - bd - minf(s.d * 0.12, 3.0), bw, bd)
	var wall := Color(0.97, 0.96, 0.93)
	_mass(s, Vector3(0.0, (h + 7.5) * 0.5, bld.get_center().y), Vector3(bw, h + 7.5, bd), wall if not cup else Color(0.95, 0.93, 0.9))
	if not s.full:
		return
	var pen := s.pen
	var bc := bld.get_center()
	var stucco := K.c(wall, K.K_STUCCO)
	var trim: Color = [Color(0.85, 0.2, 0.45), Color(0.15, 0.4, 0.75), Color(0.95, 0.55, 0.1)][s.rng.randi() % 3]
	# A walk-up box with service windows on three sides, a deep overhang all round.
	for e in 4:
		var along_x := e <= 1
		var o := Vector3(bc.x, 0.0, bld.position.y + 0.15 if e == 0 else bld.end.y - 0.15) if along_x else Vector3(bld.position.x + 0.15 if e == 2 else bld.end.x - 0.15, 0.0, bc.y)
		var span := bw if along_x else bd
		var out := Vector3(0, 0, -1 if e == 0 else 1) if along_x else Vector3(-1 if e == 2 else 1, 0, 0)
		var sz := Vector3(span, 0.0, 0.3) if along_x else Vector3(0.3, 0.0, span)
		pen.box(o + Vector3(0.0, (1.0 - SKIRT) * 0.5, 0.0), sz + Vector3(0.0, 1.0 + SKIRT, 0.0), stucco, K.RM_MATTE)
		pen.box(o + Vector3(0.0, (2.6 + h) * 0.5, 0.0), sz + Vector3(0.0, h - 2.6, 0.0), stucco, K.RM_MATTE)
		if e == 1:
			pen.box(o + Vector3(0.0, 1.8, 0.0), sz + Vector3(0.0, 1.6, 0.0), stucco, K.RM_MATTE)
			continue
		var nwin := maxi(int(span / 2.2), 1)
		for k in nwin:
			var t := (k + 0.5) / nwin - 0.5
			var wc := o + (Vector3(t * span, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, t * span)) + out * 0.02
			pen.window(wc, out, span / nwin - 0.25, 0.0, 1.0, 2.6, 3.0, K.Room.STAND)
			pen.box(wc + out * 0.2 + Vector3(0.0, 1.02, 0.0), (Vector3(span / nwin - 0.2, 0.06, 0.45) if along_x else Vector3(0.45, 0.06, span / nwin - 0.2)), K.c(Color(0.75, 0.76, 0.78), K.K_STEEL), K.RM_STEEL)
	s.ch._add_shape(Vector3(bw, h, bd), s.at(Vector3(bc.x, h * 0.5, bc.y)), s.yaw)
	pen.box(Vector3(bc.x, h + 0.12, bc.y), Vector3(bw + 2.4, 0.24, bd + 2.4), K.c(Color(0.95, 0.95, 0.93), K.K_FIXED), K.RM_PAINT)
	pen.box(Vector3(bc.x, h + 0.42, bc.y), Vector3(bw + 2.42, 0.4, bd + 2.42), K.c(trim, K.K_FIXED), K.RM_PAINT)
	for e in 4:
		var along_x := e <= 1
		var o := Vector3(bc.x, h - 0.02, bld.position.y - 1.0 if e == 0 else bld.end.y + 1.0) if along_x else Vector3(bld.position.x - 1.0 if e == 2 else bld.end.x + 1.0, h - 0.02, bc.y)
		pen.box(o, Vector3(bw + 1.6, 0.03, 0.12) if along_x else Vector3(0.12, 0.03, bd + 1.6), K.c(Color(1.0, 0.97, 0.88), K.K_NEON), K.RM_PLASTIC)
	_letters_flat(s, bname, Vector3(bc.x, h + 0.42, bld.position.y - 1.23), 0.34, Color(0.98, 0.98, 0.96), bw + 1.4, Vector3(0, 0, -1))
	# The giant object on a short steel stand on the roof.
	var base := Vector3(bc.x, h + 0.6, bc.y)
	pen.box(base + Vector3(0.0, 0.5, 0.0), Vector3(1.4, 1.0, 1.4), K.c(Color(0.35, 0.35, 0.37), K.K_STEEL), K.RM_STEEL)
	if cup:
		_giant_cup(s, base + Vector3(0.0, 1.0, 0.0), trim)
	else:
		_giant_donut(s, base + Vector3(0.0, 1.0 + 3.4, 0.0), trim)
	s.ch._add_shape(Vector3(5.0, 7.0, 3.0), s.at(base + Vector3(0.0, 4.0, 0.0)), s.yaw)
	# Picnic tables under umbrellas-worth of shade, parking at the sides.
	for k in 2:
		var tx := bc.x + (-3.0 if k == 0 else 3.0)
		var tz := bld.position.y - 3.6
		var ty := s.dy(tx, tz)
		pen.box(Vector3(tx, ty + 0.74, tz), Vector3(1.8, 0.06, 0.8), K.c(trim, K.K_FIXED), K.RM_PAINT)
		for sd: float in [-1.0, 1.0]:
			pen.box(Vector3(tx, ty + 0.44, tz + sd * 0.65), Vector3(1.8, 0.05, 0.3), K.c(trim, K.K_FIXED), K.RM_PAINT)
			pen.box(Vector3(tx + sd * 0.7, ty + 0.37, tz), Vector3(0.06, 0.74, 1.5), K.c(Color(0.6, 0.6, 0.62), K.K_STEEL), K.RM_STEEL)
	for sd: float in [-1.0, 1.0]:
		var px := sd * (hw - 3.5)
		if absf(px) > bw * 0.5 + 2.0:
			for k in 3:
				_line(s, Vector2(px - 2.4, bld.position.y + k * 2.8), Vector2(px + 2.4, bld.position.y + k * 2.8), 0.1)
			if s.rng.randf() < 0.7:
				_car(s, Vector2(px, bld.position.y + 1.4), PI * 0.5 * sd)
	_frontage(s, [Vector2(-hw + 1.5, -hw + 7.0), Vector2(hw - 7.0, hw - 1.5)])
	_pool(s, Vector2(bc.x, bc.y), Vector2(bw + 8.0, bd + 8.0), Color(1.0, 0.9, 0.75, 1.0))
	_light(s, Vector3(bc.x, h + 2.5, bld.position.y - 3.0), 14.0, Color(1.0, 0.9, 0.75))
	# Flood fixtures on the roof's corners, aimed up at the giant.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var fp := Vector3(bc.x + sx * (bw * 0.5 - 0.5), h + 0.75, bc.y + sz * (bd * 0.5 - 0.5))
			pen.box(fp, Vector3(0.3, 0.22, 0.3), K.c(Color(0.25, 0.25, 0.27), K.K_FIXED), K.RM_PAINT, 0.03)
			pen.box(fp + Vector3(-sx * 0.1, 0.1, -sz * 0.1), Vector3(0.2, 0.04, 0.2), K.c(Color(1.0, 0.95, 0.85), K.K_SOFFIT), Vector2(0.25, 0.0))


## The giant donut, upright, facing the street: a torus of dough, its front glazed with sprinkles.
static func _giant_donut(s: Site, c: Vector3, glaze: Color) -> void:
	var K := RoadsideKit
	var R := 2.7
	var r := 1.15
	var nu := 32
	var nv := 14
	var dough := K.c(Color(0.78, 0.5, 0.24), K.K_FIXED)
	var gl := K.c(glaze.lightened(0.25), K.K_GLAZE)
	for i in nu:
		for j in nv:
			var pts := []
			var nrm := []
			var glazed := 0
			for q: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
				var u := TAU * q.x / nu
				var v := TAU * q.y / nv
				var ring := Vector3(cos(u), sin(u), 0.0)
				var n := ring * cos(v) + Vector3(0.0, 0.0, -1.0) * sin(v)
				pts.append(c + ring * R + n * r)
				nrm.append(n)
				if sin(v) > -0.1 + 0.18 * sin(u * 5.0):
					glazed += 1
			var want := (nrm[0] + nrm[1] + nrm[2] + nrm[3]) as Vector3
			var col := gl if glazed >= 3 else dough
			s.pen.face(pts[0], pts[1], pts[2], pts[3], [Vector2(float(i) / nu * 6.0, float(j) / nv * 2.0), Vector2(float(i + 1) / nu * 6.0, float(j) / nv * 2.0), Vector2(float(i + 1) / nu * 6.0, float(j + 1) / nv * 2.0), Vector2(float(i) / nu * 6.0, float(j + 1) / nv * 2.0)], want, col, Vector2(0.4 if glazed >= 3 else 0.8, 0.0))
	# Neon round the hole after dark.
	var ring := []
	for k in 25:
		var u := TAU * k / 24.0
		ring.append(c + Vector3(cos(u), sin(u), 0.0) * (R - r - 0.02) + Vector3(0.0, 0.0, -0.3))
	s.pen.tube(ring, 0.04, K.c(Color(1.0, 0.95, 0.85), K.K_NEON), K.RM_PLASTIC, 5)


## The giant coffee cup: a tapered paper cup with a sleeve and a domed lid, the brand on the sleeve.
static func _giant_cup(s: Site, c: Vector3, sleeve: Color) -> void:
	var K := RoadsideKit
	var pen := s.pen
	pen.cyl(c, 1.55, 2.05, 5.2, K.c(Color(0.97, 0.96, 0.93), K.K_FIXED), Vector2(0.55, 0.0), 32)
	pen.cyl(c + Vector3(0.0, 1.6, 0.0), 1.79, 1.94, 1.9, K.c(Color(0.55, 0.36, 0.2), K.K_FIXED), Vector2(0.8, 0.0), 32)
	pen.cyl(c + Vector3(0.0, 5.2, 0.0), 2.15, 2.15, 0.25, K.c(Color(0.95, 0.95, 0.94), K.K_FIXED), Vector2(0.4, 0.0), 32)
	pen.cyl(c + Vector3(0.0, 5.45, 0.0), 2.05, 1.6, 0.35, K.c(sleeve.darkened(0.2), K.K_FIXED), Vector2(0.4, 0.0), 32)
	pen.cyl(c + Vector3(0.0, 5.8, 0.0), 0.5, 0.45, 0.12, K.c(sleeve.darkened(0.3), K.K_FIXED), Vector2(0.4, 0.0), 16)
	pen.text("COFFEE", 0.55, c + Vector3(0.0, 2.55, -1.9), Vector3(0.0, 0.0, -1.0), K.c(Color(0.98, 0.96, 0.9), K.K_LIGHTBOX), 2.8)
	var ring := []
	for k in 33:
		var u := TAU * k / 32.0
		ring.append(c + Vector3(cos(u) * 2.18, 5.2, sin(u) * 2.18))
	pen.tube(ring, 0.04, K.c(Color(1.0, 0.95, 0.85), K.K_NEON), K.RM_PLASTIC, 5)
