class_name RcAutoRow
extends RefCounted
## The auto row refcam (wave 8, `auto_row` in tools/refcams/cameras_w8.json, docs/HANDOFF.md "The
## auto row from the kerb"): what gave a CarDealers lot away as a game at 11:00 from the kerb.
##
## 1. The lot cars were ArenaGrounds' ~400-triangle code boxes all the way to the kerb. Within
##    REAL_NEAR of their cell they are now the real road bodies (CarParkBuild.real_body(): the
##    body type's far twin, ~8k triangles, in the car's own paint), a body type per box kind by a
##    hash of the stall, the box past that (StreetCloseup's way for LotFill's car parks).
## 2. The window cards stood where the BOX's windscreen is: on a real body they would float. Each
##    real body's windscreen is measured once from its own triangles (`screen()`: the top profile
##    down the passenger side, hood to roof) and the card laid on it; the real Vehicles of the
##    front row and the showroom floor get theirs the same way, from their own body meshes.
## 3. Street trees stood in front of the frontage (a dealer keeps its lot in view of the street):
##    `keeps_tree_off()` drops a kerb tree on a site's frontage, asked by CityChunk._add_tree()
##    after every roll it makes (nothing else moves).
##
## Hooks (one line each): CarDealers._static_car() -> note_car(), CarDealers._real_car() ->
## real_vehicle(), CityChunk._add_tree() -> keeps_tree_off(), CityChunk finish -> commit().
## Rolls are hashes of the seed and the stall; nothing a seed builds elsewhere moves.
## RC5_AUTO_ROW=0 in the environment is the A/B (the lot exactly as before).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_AUTO_ROW") != "0"

## How near a lot car's cell is drawn as the real body (m, to the cell's centre).
const REAL_NEAR := 48.0
## Cells the lot cars are grouped in for that range (m).
const CELL := 20.0
## The window cards on the box cars stop at this (CarDealers' own sticker batch range).
const STICKER_FAR := 90.0
## Body types standing in for each box kind (ArenaGrounds.car_mesh: 0 saloon, 1 pickup, 2 SUV,
## 3 coupe); a hash of the stall picks one.
const TYPES := [
	[Vehicle.BodyType.SEDAN, Vehicle.BodyType.LUX_SEDAN, Vehicle.BodyType.HATCHBACK, Vehicle.BodyType.SEDAN],
	[Vehicle.BodyType.PICKUP],
	[Vehicle.BodyType.CROSSOVER, Vehicle.BodyType.SUV, Vehicle.BodyType.COMPACT_SUV, Vehicle.BodyType.CROSSOVER],
	[Vehicle.BodyType.COUPE, Vehicle.BodyType.LUX_SEDAN],
]
## A kerb tree within this of a site's frontage (m, along the street) is left out.
const TREE_CLEAR := 3.0

static var _screens: Dictionary = {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## The body type a box car of kind `v` at `p` is drawn as up close.
static func body_type(seed_v: int, v: int, p: Vector3) -> int:
	var list: Array = TYPES[clampi(v, 0, 3)]
	return int(list[absi(hash([seed_v, snappedf(p.x, 0.1), snappedf(p.z, 0.1), "rc5_body"])) % list.size()])


# --- 3. The frontage ----------------------------------------------------------------------------

## True when a street tree at `at` (chunk space = true world XZ) stands on the pavement in front
## of this chunk's dealership.
## (`band_hits` counts the trees that stood in the band, `dropped` those left out: the checks.)
static var band_hits := 0
static var dropped := 0
static func keeps_tree_off(ch: CityChunk, at: Vector3) -> bool:
	if not CarDealers.enabled or ch.plan == null or ch.plan.macro == null:
		return false
	var s := CarDealers.site(ch.plan, ch.ix, ch.iz)
	if s.is_empty():
		return false
	var f: Dictionary = s.frame
	var a2: Vector2 = f.a
	var n2: Vector2 = f.n
	var o2: Vector2 = f.o
	var p := Vector2(at.x, at.z) - o2
	var along := p.dot(a2)
	# n points into the site: the pavement is on the other side of the street edge.
	var into := p.dot(n2)
	if into > 1.0 or into < -(ch.plan.sidewalk_width + 1.5):
		return false
	if along < -TREE_CLEAR or along > float(f.len) + TREE_CLEAR:
		return false
	band_hits += 1
	if not enabled:
		return false
	dropped += 1
	return true


# --- 4. The stall lines ---------------------------------------------------------------------------

## The lot's stalls painted (LotFill's car park stripe, the road paint batch): a dealer lot was
## one flat black sheet under its rows of cars. A line either side of every car standing in a
## row (the ramp car's stall too), each once. Called by CarDealers._build_detail() on a FULL chunk.
static func stripes(ch: CityChunk, s: Dictionary, L: Dictionary, xf0: Transform3D) -> void:
	if not enabled:
		return
	var pitch := 2.55 if bool(s.used) else CarDealers.STALL_W
	var top := LotFill.ASPHALT_LIFT + 0.005
	var mesh := PropFactory.box("pstripe", Vector3(4.4, 0.01, 0.12), Color(0.95, 0.95, 0.92))
	var basis := xf0.basis * Basis(Vector3.UP, PI * 0.5)
	var done := {}
	for c: Array in L.cars:
		for side: float in [-0.5, 0.5]:
			var x := float(c[0]) + side * pitch
			var z := float(c[1])
			var k := Vector2i(roundi(x * 10.0), roundi(z * 10.0))
			if done.has(k):
				continue
			done[k] = true
			ch._batch.add("pstripe", mesh, Transform3D(basis, xf0 * Vector3(x, top, z)))


# --- 1, 2. The lot cars -------------------------------------------------------------------------

## CarDealers._static_car() hands over each box car it laid in a FULL chunk with its prop record
## (the box instance and the sticker instance, both in the chunk's batches) and its sticker data.
static func note_car(ch: CityChunk, record: Dictionary, v: int, paint: Color, sticker_custom: Color, used: bool) -> void:
	if not enabled or ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	var inst: Array = record.instances
	if inst.size() < 2:
		return
	if not ch.has_meta("rc5_cars"):
		ch.set_meta("rc5_cars", [])
	# [car key, car index, car transform (relief included), sticker key, index, sticker xf, kind, paint, custom, used]
	(ch.get_meta("rc5_cars") as Array).append([inst[0][0], inst[0][1], inst[0][3], inst[1][0], inst[1][1], inst[1][3], v, paint, sticker_custom, used])


## At the chunk's finish (the batches built): every recorded box car and its card leave the
## chunk-wide batches and are drawn again per cell - the real body and its measured card within
## REAL_NEAR, the box and its old card past it.
static func commit(ch: CityChunk, nodes: Dictionary) -> void:
	if not ch.has_meta("rc5_cars"):
		return
	var cars: Array = ch.get_meta("rc5_cars")
	ch.remove_meta("rc5_cars")
	if not CarParkBuild.real_body(Vehicle.BodyType.SEDAN).has("mesh"):
		return
	var seed_v := ch.plan.seed
	var cells: Dictionary = {}
	for c: Array in cars:
		var cn := nodes.get(c[0]) as MultiMeshInstance3D
		var sn := nodes.get(c[3]) as MultiMeshInstance3D
		if cn == null or sn == null:
			continue
		MultiMeshBatch.hide_instance(cn, int(c[1]))
		MultiMeshBatch.hide_instance(sn, int(c[4]))
		var xf: Transform3D = c[2]
		var p := xf.origin
		var ck := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if not cells.has(ck):
			cells[ck] = {"box": AABB(p, Vector3.ZERO), "far": {}, "near": {}, "far_cards": [], "near_cards": []}
		var cell: Dictionary = cells[ck]
		cell.box = (cell.box as AABB).expand(p)
		var v: int = c[6]
		if not (cell.far as Dictionary).has(v):
			cell.far[v] = []
		cell.far[v].append([xf, c[7]])
		cell.far_cards.append([c[5], c[8]])
		var t := body_type(seed_v, v, p)
		var body := CarParkBuild.real_body(t)
		if not body.has("mesh"):
			continue
		if not (cell.near as Dictionary).has(t):
			cell.near[t] = []
		cell.near[t].append([xf, c[7]])
		var sc := screen(t)
		if not sc.is_empty():
			cell.near_cards.append([xf * card_xform(sc, bool(c[9])), c[8]])
	for ck: Vector2i in cells:
		var cell: Dictionary = cells[ck]
		var bounds: AABB = (cell.box as AABB).grow(3.0)
		bounds.size.y += 1.5
		for v: int in cell.far:
			var mmi := CarParkBuild._car_mmi(ArenaGrounds.car_mesh(v), cell.far[v], Vector3.ZERO, false)
			mmi.name = "DealerBoxCars%d_%d_%d" % [v, ck.x, ck.y]
			_seat(ch, mmi, bounds, REAL_NEAR, 0.0)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for t: int in cell.near:
			var body := CarParkBuild.real_body(t)
			var mmi := CarParkBuild._car_mmi(body.mesh, cell.near[t], body.offset, true)
			mmi.name = "DealerRealCars%d_%d_%d" % [t, ck.x, ck.y]
			# The real body casts nothing: the box car of the same stall throws its shadow (a few
			# hundred triangles, the same footprint), so the lot's shadow passes cost what they did.
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_seat(ch, mmi, bounds, 0.0, REAL_NEAR)
		for v: int in cell.far:
			var twin := CarParkBuild._car_mmi(ArenaGrounds.car_mesh(v), cell.far[v], Vector3.ZERO, false)
			twin.name = "DealerCarShadows%d_%d_%d" % [v, ck.x, ck.y]
			twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			_seat(ch, twin, bounds, 0.0, REAL_NEAR)
		for k in 2:
			var list: Array = cell.far_cards if k == 0 else cell.near_cards
			if list.is_empty():
				continue
			var mmi := _card_mmi(list)
			mmi.name = "DealerCards%s_%d_%d" % ["Far" if k == 0 else "Near", ck.x, ck.y]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_seat(ch, mmi, bounds, REAL_NEAR if k == 0 else 0.0, STICKER_FAR if k == 0 else REAL_NEAR)


static func _seat(ch: CityChunk, mmi: MultiMeshInstance3D, bounds: AABB, begin: float, end: float) -> void:
	mmi.custom_aabb = bounds
	mmi.visibility_range_begin = begin
	mmi.visibility_range_end = end
	ch.add_child(mmi)


static func _card_mmi(list: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = CarDealers.sticker_mesh()
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i][0])
		mm.set_instance_color(i, Color.WHITE)
		mm.set_instance_custom_data(i, list[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


## A real body type's windscreen in the frame of a car standing on y 0, nose -Z (the frame the
## real bodies are placed in): {"base": point at the screen's foot on the car's centre line plane
## at x, "up": unit vector up the glass, "n": its outward normal, "len": the glass length}. {}
## without mesh data (the headless dummy renderer keeps none). Measured once a type.
static func screen(t: int) -> Dictionary:
	if _screens.has(t):
		return _screens[t]
	var out := {}
	var body := CarParkBuild.real_body(t)
	if body.has("mesh"):
		var tm := (body.mesh as Mesh).generate_triangle_mesh()
		if tm != null:
			out = _measure([[tm, Transform3D(Basis(), body.offset)]])
	_screens[t] = out
	return out


## The windscreen of whatever `meshes` ([TriangleMesh, the mesh's transform into the car's
## standing frame]) make up: the highest surface down a line 0.42 m right of the centre line,
## every 4 cm from the nose back; the glass is where that profile climbs from the bonnet to the
## roof. {} when nothing is found.
static func _measure(meshes: Array) -> Dictionary:
	var lo := INF
	var hi := -INF
	var boxes: Array = []
	for m: Array in meshes:
		var tm := m[0] as TriangleMesh
		var faces := tm.get_faces()
		if faces.is_empty():
			continue
		var xf: Transform3D = m[1]
		var b := AABB(xf * faces[0], Vector3.ZERO)
		for i in range(0, faces.size(), 7):
			b = b.expand(xf * faces[i])
		boxes.append(b)
		lo = minf(lo, b.position.z)
		hi = maxf(hi, b.end.z)
	if boxes.is_empty():
		return {}
	var x := 0.42
	var prof: Array = [] # [z, y]
	var z := lo + 0.02
	while z < hi:
		var top := -INF
		for m: Array in meshes:
			var xf: Transform3D = m[1]
			var inv := xf.affine_inverse()
			var r: Dictionary = (m[0] as TriangleMesh).intersect_ray(inv * Vector3(x, 6.0, z), inv.basis * Vector3.DOWN)
			if not r.is_empty():
				top = maxf(top, (xf * (r.position as Vector3)).y)
		if top > -INF:
			prof.append([z, top])
		z += 0.04
	if prof.size() < 20:
		return {}
	var roof := -INF
	for p: Array in prof:
		roof = maxf(roof, float(p[1]))
	# The bonnet: the profile's height a quarter of the way from the nose to the roof's peak.
	var peak_i := 0
	for i in prof.size():
		if float(prof[i][1]) >= roof - 0.001:
			peak_i = i
			break
	var hood := float(prof[peak_i / 4][1])
	var rise := roof - hood
	if rise < 0.25:
		return {}
	var y0 := hood + rise * 0.12
	var y1 := hood + rise * 0.88
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var found := 0
	for i in range(peak_i / 4, peak_i + 1):
		var y := float(prof[i][1])
		if found == 0 and y >= y0:
			a = Vector2(float(prof[i][0]), y)
			found = 1
		if found == 1 and y >= y1:
			b = Vector2(float(prof[i][0]), y)
			found = 2
			break
	if found < 2 or b.x - a.x < 0.15:
		return {}
	var d := Vector3(0.0, b.y - a.y, b.x - a.x)
	var up := d.normalized()
	var n := Vector3(0.0, up.z, -up.y)
	return {"base": Vector3(x, a.y, a.x), "up": up, "n": n, "len": d.length()}


## A card on a measured windscreen (the unit quad, facing +Z, onto the glass): a used car's price
## big across the middle, a new car's card low on the passenger side - CarDealers.sticker_xform()'s
## sizes, on the real glass.
static func card_xform(sc: Dictionary, used: bool) -> Transform3D:
	var up: Vector3 = sc.up
	var n: Vector3 = sc.n
	var base: Vector3 = sc.base
	var size := Vector2(0.95, 0.5) if used else Vector2(0.36, 0.27)
	var f := 0.5 if used else 0.3
	var c := Vector3(0.0 if used else base.x, base.y, base.z) + up * float(sc.len) * f + n * 0.015
	return Transform3D(Basis(Vector3(-1.0, 0.0, 0.0) * size.x, up * size.y, n), c)


## A real Vehicle for sale (CarDealers._real_car(), once it is in the tree): its card on its own
## windscreen, measured from its body meshes in its frame. Deferred a frame: the body model is
## built in the car's _ready().
static func real_vehicle(car: Vehicle, used: bool, custom: Color) -> void:
	if not enabled or car == null:
		return
	_card_on_vehicle.call_deferred(car, used, custom)


static func _card_on_vehicle(car: Vehicle, used: bool, custom: Color) -> void:
	if not is_instance_valid(car) or not car.is_inside_tree():
		return
	var key := "veh_%d" % int(car.body_type)
	var sc: Dictionary
	if _screens.has(key):
		sc = _screens[key]
	else:
		var meshes: Array = []
		var inv := car.global_transform.affine_inverse()
		for mi in car.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or String(m.name).ends_with("_far") or not m.is_visible_in_tree():
				continue
			var path := String(car.get_path_to(m))
			if not path.contains("BodyModel"):
				continue
			var tm := m.mesh.generate_triangle_mesh()
			if tm != null:
				meshes.append([tm, inv * m.global_transform])
		sc = _measure(meshes) if not meshes.is_empty() else {}
		_screens[key] = sc
	if sc.is_empty():
		return
	# One instance of the sticker batch's mesh: the card's look rides in INSTANCE_CUSTOM.
	var mmi := _card_mmi([[card_xform(sc, used), custom]])
	mmi.name = "PriceCard"
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = STICKER_FAR
	car.add_child(mmi)
