class_name Commercial
extends RefCounted
## Commercial blocks and pads: shopping plazas (a strip of shops around a parking lot), big-box
## stores with a huge fascia sign and cart corrals, fast-food drive-thrus with a pylon sign and
## gas stations with a pump canopy. All names are original (no real brands). Everything is
## boxes with PBR sets, glass, painted lots and 3D text, built through the chunk so it follows
## the relief. Static: call with the chunk.

const ANCHORS := ["SUPER MART", "FRESH FOODS", "VALUE GROCER", "MEGA MART", "GREEN GROCER"]
const SHOPS := ["PHARMACY", "NAILS & SPA", "DRY CLEAN", "PHONE FIX", "LIQUOR", "PIZZA", "SUSHI", "TACOS", "COFFEE STOP", "BANK", "DONUT HOLE", "SUB STOP", "PET SHOP", "BARBER", "LAUNDRY", "BOBA", "DENTAL", "TAX PRO", "SMOKE SHOP", "FLOWERS"]
const BIG := ["HOME & TOOL", "MEGA MART", "ELECTRO WORLD", "FURNITURE DEPOT", "SPORTS BARN", "OFFICE STACK"]
const FAST := ["BURGER BOX", "CHICKEN SHACK", "TACO DEPOT", "PIZZA BARN", "DONUT HOLE", "SUB STOP", "WAFFLE SPOT", "NOODLE HUT"]
const GAS := ["GAS & GO", "FUEL STOP", "PUMP N SHOP", "ROADSTAR"]
const FASCIA := [Color(0.75, 0.12, 0.12), Color(0.1, 0.3, 0.6), Color(0.15, 0.45, 0.25), Color(0.85, 0.55, 0.1), Color(0.25, 0.25, 0.3), Color(0.6, 0.1, 0.4)]

const TOP := 0.25   # CityChunk.SIDEWALK_TOP


## Shopping plaza: parking lot in front, an L-shaped strip of shops at the back with an anchor
## grocery, a pylon sign at the corner.
static func build_mall(chunk: CityChunk, rect: Rect2, rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-chunk.plan.sidewalk_width)
	var full := chunk.level == CityChunk.Level.FULL
	_lot(chunk, inner, rng, full)
	# The strip runs along the +Z edge (back) and turns up the +X edge.
	var depth := 14.0
	var h := 5.5
	var back := Rect2(inner.position.x, inner.end.y - depth, inner.size.x, depth)
	var wing := Rect2(inner.end.x - depth, inner.position.y + 6.0, depth, inner.size.y - depth - 6.0)
	var fascia: Color = FASCIA[rng.randi() % FASCIA.size()]
	var wall_set: String = ["plaster_beige", "plaster_painted", "concrete_painted", "plaster_white"][rng.randi() % 4]
	_strip(chunk, back, h, Vector2(0.0, -1.0), fascia, wall_set, rng, full, true)
	_strip(chunk, wing, h, Vector2(-1.0, 0.0), fascia, wall_set, rng, full, false)
	if full:
		var names: Array = [ANCHORS[rng.randi() % ANCHORS.size()], SHOPS[rng.randi() % SHOPS.size()], SHOPS[rng.randi() % SHOPS.size()]]
		_pylon(chunk, Vector2(inner.position.x + 3.0, inner.position.y + 3.0), names, fascia, rng)
		_lot_lamps(chunk, inner, rng)


## Big-box store: one huge box at the back, entrance canopy, garden center, cart corrals.
static func build_bigbox(chunk: CityChunk, rect: Rect2, rng: RandomNumberGenerator) -> void:
	var inner := rect.grow(-chunk.plan.sidewalk_width)
	var full := chunk.level == CityChunk.Level.FULL
	_lot(chunk, inner, rng, full)
	var w := inner.size.x * 0.7
	var d := minf(inner.size.y * 0.42, 60.0)
	var h := 10.0
	var box := Rect2(inner.get_center().x - w * 0.5, inner.end.y - d - 2.0, w, d)
	var fascia: Color = FASCIA[rng.randi() % FASCIA.size()]
	var name: String = BIG[rng.randi() % BIG.size()]
	var big_set: String = ["concrete_painted", "metal_corrugated", "concrete", "plaster_beige"][rng.randi() % 4]
	var wall := PropFactory.pbr(big_set, 4.0, Color(0.85, 0.85, 0.85))
	# No face skipped on a big box: the entrance fascia and canopy sit well proud of the wall,
	# and the long blank stretches either side of the doors are exactly what needs breaking up.
	_box_building(chunk, box, h, wall, full, true)
	var front_z := box.position.y
	var cx := box.get_center().x
	if full:
		# Fascia band with the name, entrance canopy with glass doors, a garden center to one side.
		chunk._add_slab(Vector3(cx, TOP + h - 1.2, front_z - 0.15), Vector3(w * 0.5, 2.4, 0.3), fascia, false, PropFactory.material(fascia, 0.6))
		_sign_text(chunk, name, Vector3(cx, TOP + h - 1.2, front_z - 0.32), 0.0, 1.6, Color.WHITE)
		chunk._add_slab(Vector3(cx, TOP + 4.6, front_z - 4.0), Vector3(14.0, 0.5, 8.0), Color(0.3, 0.3, 0.32), true, PropFactory.material(Color(0.3, 0.3, 0.32), 0.6))
		for sx: float in [-6.5, 6.5]:
			chunk._add_slab(Vector3(cx + sx, TOP + 2.3, front_z - 7.6), Vector3(0.5, 4.6, 0.5), Color(0.3, 0.3, 0.32))
		_glass(chunk, Vector3(cx, TOP + 2.2, front_z - 0.05), Vector3(12.0, 4.0, 0.1))
		# Garden center: low fence posts and planters along the -X side of the front.
		var gx := box.position.x + 8.0
		for i in 6:
			chunk._add_prop("planter", Vector3(gx + i * 2.2, TOP, front_z - 6.0), Color(0.45, 0.32, 0.2), [
				["planter", PropFactory.model_planter(), Transform3D(Basis(), Vector3(gx + i * 2.2, TOP, front_z - 6.0))],
			], [[Vector3(0.95, 0.45, 0.45), Vector3(gx + i * 2.2, TOP + 0.22, front_z - 6.0), 0.0]])
			chunk._batch.add("shrub_%d" % (i % 4), PropFactory.model_shrub(i % 4), Transform3D(Basis(Vector3.UP, float(i)).scaled(Vector3.ONE * 0.6), Vector3(gx + i * 2.2, TOP + 0.35, front_z - 6.0)), Color(0.95, 1.0, 0.9))
		# Cart corrals in the lot and a loading dock behind.
		for k in 3:
			_corral(chunk, Vector2(cx - 20.0 + k * 20.0, front_z - 22.0))
		for k in 4:
			var bp := Vector3(box.position.x + 6.0 + k * 3.0, TOP, box.end.y + 1.5)
			chunk._batch.add("tyre_static", PropFactory.model_tyre(), Transform3D(Basis(Vector3.UP, float(k)), bp))
		_pylon(chunk, Vector2(inner.position.x + 3.0, inner.position.y + 3.0), [name], fascia, rng)
		_lot_lamps(chunk, inner, rng)


## A fast-food restaurant or a gas station on one lot (edge lots of suburbs and midtown blocks).
static func build_pad(chunk: CityChunk, lot: Dictionary, rng: RandomNumberGenerator) -> void:
	var center: Vector2 = lot.center
	var size: Vector2 = lot.size
	var pad := Rect2(center - size * 0.5, size)
	var full := chunk.level == CityChunk.Level.FULL
	_lot(chunk, pad, rng, full, false)
	if rng.randf() < 0.55:
		_fast_food(chunk, pad, rng, full)
	else:
		_gas_station(chunk, pad, rng, full)


static func _fast_food(chunk: CityChunk, pad: Rect2, rng: RandomNumberGenerator, full: bool) -> void:
	var name: String = FAST[rng.randi() % FAST.size()]
	var fascia: Color = FASCIA[rng.randi() % 3]
	var bw := minf(pad.size.x * 0.5, 16.0)
	var bd := minf(pad.size.y * 0.4, 11.0)
	var h := 4.6
	var box := Rect2(pad.get_center().x - bw * 0.5, pad.end.y - bd - 4.0, bw, bd)
	var wall := PropFactory.pbr("plaster_white", 3.0, Color(0.95, 0.93, 0.9))
	_box_building(chunk, box, h, wall, full)
	if not full:
		return
	var c := box.get_center()
	var front_z := box.position.y
	# Red band around the roof edge, glass front, drive-thru window and menu board on the +X side.
	chunk._add_slab(Vector3(c.x, TOP + h - 0.5, front_z - 0.12), Vector3(bw, 1.0, 0.25), fascia, false, PropFactory.material(fascia, 0.6))
	_glass(chunk, Vector3(c.x, TOP + 1.6, front_z - 0.05), Vector3(bw - 2.0, 2.4, 0.1))
	_sign_text(chunk, name, Vector3(c.x, TOP + h - 0.5, front_z - 0.3), 0.0, 0.7, Color.WHITE)
	var dx := box.end.x + 0.05
	_glass(chunk, Vector3(dx, TOP + 1.7, c.y), Vector3(0.1, 1.2, 1.6))
	chunk._add_slab(Vector3(dx + 3.5, TOP + 1.4, c.y + 5.0), Vector3(0.15, 1.8, 2.2), Color(0.2, 0.2, 0.22), true, PropFactory.material(Color(0.2, 0.2, 0.22), 0.6))
	_sign_text(chunk, "MENU", Vector3(dx + 3.4, TOP + 1.9, c.y + 5.0), PI * 0.5, 0.3, Color(0.95, 0.9, 0.5))
	# Drive-thru lane arrows along the +X side.
	for k in 3:
		chunk._batch.add("arrow_straight", PropFactory.arrow_straight(), Transform3D(Basis(Vector3.UP, 0.0), Vector3(dx + 2.0, CityChunk.ROAD_TOP + 0.016 + 0.16, c.y + 8.0 - k * 6.0)))
	_pylon(chunk, Vector2(pad.position.x + 2.5, pad.position.y + 2.5), [name], fascia, rng, 9.0)


static func _gas_station(chunk: CityChunk, pad: Rect2, rng: RandomNumberGenerator, full: bool) -> void:
	var name: String = GAS[rng.randi() % GAS.size()]
	var fascia: Color = [Color(0.8, 0.1, 0.1), Color(0.1, 0.35, 0.65), Color(0.1, 0.5, 0.3)][rng.randi() % 3]
	var c := pad.get_center()
	# Shop at the back, canopy over the pumps in front.
	var sw := minf(pad.size.x * 0.45, 14.0)
	var shop := Rect2(c.x - sw * 0.5, pad.end.y - 9.0 - 3.0, sw, 9.0)
	_box_building(chunk, shop, 4.2, PropFactory.pbr("plaster_white", 3.0, Color(0.95, 0.95, 0.95)), full)
	var cw := minf(pad.size.x * 0.6, 20.0)
	var cd := 12.0
	var canopy_c := Vector2(c.x, shop.position.y - 4.0 - cd * 0.5)
	chunk._add_slab(Vector3(canopy_c.x, TOP + 5.3, canopy_c.y), Vector3(cw, 0.7, cd), Color(0.9, 0.9, 0.9), true, PropFactory.material(Color(0.92, 0.92, 0.92), 0.5))
	if not full:
		return
	chunk._add_slab(Vector3(canopy_c.x, TOP + 5.3, canopy_c.y - cd * 0.5 - 0.1), Vector3(cw, 0.9, 0.2), fascia, false, PropFactory.material(fascia, 0.6))
	for sx: float in [-cw * 0.35, cw * 0.35]:
		for sz: float in [-cd * 0.3, cd * 0.3]:
			chunk._add_slab(Vector3(canopy_c.x + sx, TOP + 2.5, canopy_c.y + sz), Vector3(0.4, 5.0, 0.4), Color(0.85, 0.85, 0.85))
	# Pump islands: a raised curb with two pumps each.
	for k in 2:
		var ix := canopy_c.x + (k - 0.5) * cw * 0.4
		chunk._add_slab(Vector3(ix, TOP + 0.08, canopy_c.y), Vector3(1.2, 0.16, 7.0), Color(0.8, 0.8, 0.8))
		for pz: float in [-1.8, 1.8]:
			chunk._add_prop("pump", Vector3(ix, TOP + 0.16, canopy_c.y + pz), Color(0.2, 0.2, 0.22), [
				["pump", PropFactory.gas_pump(), Transform3D(Basis(), Vector3(ix, TOP + 0.16 + 0.9, canopy_c.y + pz)), fascia],
			], [[Vector3(0.6, 1.8, 0.9), Vector3(ix, TOP + 1.06, canopy_c.y + pz), 0.0]])
	_glass(chunk, Vector3(shop.get_center().x, TOP + 1.7, shop.position.y - 0.05), Vector3(sw - 2.0, 2.4, 0.1))
	_sign_text(chunk, name, Vector3(shop.get_center().x, TOP + 3.6, shop.position.y - 0.2), 0.0, 0.6, fascia)
	_pylon(chunk, Vector2(pad.position.x + 2.5, pad.position.y + 2.5), [name, "4.59  4.79  4.99"], fascia, rng, 8.0)


# --- Pieces ---------------------------------------------------------------------------------

## Parking lot over `area`: asphalt, stall rows with aisles, some parked cars.
static func _lot(chunk: CityChunk, area: Rect2, rng: RandomNumberGenerator, full: bool, cars: bool = true) -> void:
	var c := area.get_center()
	chunk._add_slab(Vector3(c.x, TOP + 0.01, c.y), Vector3(area.size.x, 0.02, area.size.y), Color(0.4, 0.4, 0.42), false, PropFactory.pbr("asphalt", 7.0, Color(0.62, 0.62, 0.64)))
	if not full:
		return
	# Rows of stalls along X, a 7 m aisle between double rows, front half of the lot only.
	var rows := maxi(1, floori((area.size.y * 0.5) / 18.0))
	var y := area.position.y + 4.0
	var count := 0
	for r in rows:
		for side in 2:
			var stall_z := y + side * 5.5
			var x := area.position.x + 3.0
			while x < area.end.x - 3.0:
				chunk._batch.add("pstripe", PropFactory.box("pstripe", Vector3(4.4, 0.01, 0.12), Color(0.95, 0.95, 0.92)), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, TOP + 0.03, stall_z)))
				if cars and rng.randf() < 0.3 and count < 8 and PhysicsBudget.can_spawn():
					var car := Vehicle.random_car(rng)
					var holder: Node = chunk.get_parent() if chunk.get_parent() else chunk
					var pos := Vector3(x + 1.4, TOP + 0.5 + chunk._gy(x + 1.4, stall_z), stall_z)
					car.position = WorldState.to_local(pos) if holder != chunk else pos
					car.rotation.y = (0.0 if side == 0 else PI) + rng.randf_range(-0.05, 0.05)
					holder.add_child(car)
					chunk._cars.append(car)
					count += 1
				x += 2.8
		y += 18.0


static func _lot_lamps(chunk: CityChunk, area: Rect2, rng: RandomNumberGenerator) -> void:
	for i in 3:
		var p := Vector2(area.position.x + area.size.x * (i + 0.5) / 3.0, area.position.y + area.size.y * 0.35)
		chunk._add_lamp(Vector3(p.x, TOP, p.y))
	for i in 2:
		var p := Vector2(area.position.x + 6.0 + i * 3.0, area.end.y - 20.0)
		var can := TrashCan.new()
		can.rusty = rng.randf() < 0.3
		can.position = Vector3(p.x, TOP + 0.02 + chunk._gy(p.x, p.y), p.y)
		chunk.add_child(can)


## A plain box building with collision (LOD too), roof parapet, plinth-free (sits on the lot).
## `ribs`: break the blank faces up with pilasters and a base band. `skip_face` is the outward
## direction of the face that carries the shopfronts, which is left alone.
static func _box_building(chunk: CityChunk, box: Rect2, h: float, wall: Material, full: bool, ribs_on: bool = false, skip_face: Vector2 = Vector2.ZERO) -> void:
	var c := box.get_center()
	chunk._add_slab(Vector3(c.x, TOP + h * 0.5, c.y), Vector3(box.size.x, h, box.size.y), Color(0.8, 0.8, 0.8), true, wall)
	chunk._add_slab(Vector3(c.x, TOP + h + 0.3, c.y), Vector3(box.size.x + 0.4, 0.6, box.size.y + 0.4), Color(0.5, 0.5, 0.5), false, PropFactory.pbr("concrete", 3.0, Color(0.7, 0.7, 0.7)))
	if not ribs_on:
		return
	# A big-box side wall is 60 m of nothing, and from the street opposite it is a grey field
	# filling a third of the screen. Real ones are broken up by structural pilasters every few
	# bays, a painted base band where the trolleys scuff it, and a shadow line under the
	# parapet. All flat slabs proud of the wall, so it stays a handful of draws.
	var band := PropFactory.pbr("concrete", 2.4, Color(0.60, 0.59, 0.57))
	var rib := PropFactory.pbr("concrete", 2.0, Color(0.80, 0.79, 0.77))
	for axis in 2:
		var span: float = box.size.x if axis == 0 else box.size.y
		var ribs := maxi(int(span / (9.0 if full else 14.0)), 2)
		var step := span / float(ribs)
		for side in 2:
			# Which way this face looks: -Z / +Z for the faces spread along X, -X / +X for the others.
			var out := Vector2(0.0, -1.0 if side == 0 else 1.0) if axis == 0 else Vector2(-1.0 if side == 0 else 1.0, 0.0)
			if out.is_equal_approx(skip_face):
				continue
			var off: float = (box.position[1 - axis] - 0.19) if side == 0 else (box.end[1 - axis] + 0.19)
			for i in range(1, ribs):
				var t := box.position[axis] + step * float(i)
				var at := Vector3(t, TOP + h * 0.5, off) if axis == 0 else Vector3(off, TOP + h * 0.5, t)
				# Chunky on purpose: seen along the wall rather than square on, a 28 cm pilaster
				# is edge-on and does nothing. Real big-box piers are about this deep.
				var sz := Vector3(1.15, h - 0.4, 0.42) if axis == 0 else Vector3(0.42, h - 0.4, 1.15)
				chunk._add_slab(at, sz, Color(0.8, 0.8, 0.8), false, rib)
			# The scuffed base band, run along the whole face.
			var mid: float = box.position[axis] + span * 0.5
			var at2 := Vector3(mid, TOP + 0.6, off - 0.02 * signf(off)) if axis == 0 else Vector3(off - 0.02 * signf(off), TOP + 0.6, mid)
			var sz2 := Vector3(span, 1.2, 0.22) if axis == 0 else Vector3(0.22, 1.2, span)
			chunk._add_slab(at2, sz2, Color(0.6, 0.6, 0.6), false, band)


## A strip of shop units along one long side of `strip`; `front` is the outward direction.
static func _strip(chunk: CityChunk, strip: Rect2, h: float, front: Vector2, fascia: Color, wall_set: String, rng: RandomNumberGenerator, full: bool, has_anchor: bool) -> void:
	if strip.size.x < 8.0 or strip.size.y < 8.0:
		return
	# Only skip the shopfront face once the shop units are actually built on it. At LOD level
	# _strip stops after the box, so skipping it there leaves exactly the thing this is meant to
	# fix: a long blank wall with nothing on it.
	_box_building(chunk, strip, h, PropFactory.pbr(wall_set, 3.5, Color(0.9, 0.88, 0.85)), full, true, front if full else Vector2.ZERO)
	if not full:
		return
	var along := Vector2(1.0, 0.0) if absf(front.y) > 0.5 else Vector2(0.0, 1.0)
	var length := strip.size.x if absf(front.y) > 0.5 else strip.size.y
	var start := Vector2(strip.position.x, strip.position.y + (0.0 if front.y < 0.0 else strip.size.y)) if absf(front.y) > 0.5 else Vector2(strip.position.x + (0.0 if front.x < 0.0 else strip.size.x), strip.position.y)
	var yaw := atan2(-front.x, -front.y)
	var f3 := Vector3(front.x, 0.0, front.y)
	var a3 := Vector3(along.x, 0.0, along.y)
	var s3 := Vector3(start.x, 0.0, start.y)
	# Fascia band along the whole front, then units.
	var mid := s3 + a3 * length * 0.5 - f3 * 0.12
	chunk._add_slab(mid + Vector3(0.0, TOP + h - 0.7, 0.0), Vector3(length if absf(front.y) > 0.5 else 0.25, 1.4, 0.25 if absf(front.y) > 0.5 else length), fascia, false, PropFactory.material(fascia, 0.6))
	var t := 0.0
	var first := true
	while t < length - 6.0:
		var unit_w := (minf(28.0, length - t) if (first and has_anchor) else rng.randf_range(8.0, 14.0))
		unit_w = minf(unit_w, length - t)
		var uc := s3 + a3 * (t + unit_w * 0.5)
		var name: String = ANCHORS[rng.randi() % ANCHORS.size()] if (first and has_anchor) else SHOPS[rng.randi() % SHOPS.size()]
		_sign_text(chunk, name, uc + Vector3(0.0, TOP + h - 0.7, 0.0) - f3 * 0.3, yaw, 0.9 if (first and has_anchor) else 0.55, Color.WHITE)
		# Storefront glass with a pillar at each unit edge; an awning on some.
		var gw := unit_w - 1.2
		_glass(chunk, uc + Vector3(0.0, TOP + 1.6, 0.0) - f3 * 0.05, Vector3(gw, 2.6, 0.1) if absf(front.y) > 0.5 else Vector3(0.1, 2.6, gw))
		var pillar := s3 + a3 * t - f3 * 0.2
		chunk._add_slab(pillar + Vector3(0.0, TOP + h * 0.5, 0.0), Vector3(0.6, h, 0.6), Color(0.35, 0.35, 0.37))
		if rng.randf() < 0.5:
			var awn := uc + Vector3(0.0, TOP + 3.3, 0.0) - f3 * 1.1
			chunk._add_slab(awn, Vector3(gw, 0.12, 2.0) if absf(front.y) > 0.5 else Vector3(2.0, 0.12, gw), fascia, false, PropFactory.material(fascia.darkened(0.2), 0.8))
		t += unit_w
		first = false
	# Walkway with bollards in front of the strip.
	for k in int(length / 6.0):
		var bp := s3 + a3 * (3.0 + k * 6.0) - f3 * 3.2
		chunk._add_prop("bollard", bp + Vector3(0.0, TOP, 0.0), Color(0.25, 0.25, 0.27), [
			["bollard", PropFactory.bollard(), Transform3D(Basis(), bp + Vector3(0.0, TOP + 0.45, 0.0))],
		], [[Vector3(0.3, 0.9, 0.3), bp + Vector3(0.0, TOP + 0.45, 0.0), 0.0]])


static func _glass(chunk: CityChunk, center: Vector3, size: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = PropFactory.storefront_glass()
	mesh.position = center + Vector3(0.0, chunk._gy(center.x, center.z), 0.0)
	chunk.add_child(mesh)


## `yaw` is the yaw of the wall's outward normal (atan2(-n.x, -n.z)); TextMesh reads from +Z,
## so the text is turned half a circle from that.
static func _sign_text(chunk: CityChunk, text: String, at: Vector3, yaw: float, height: float, color: Color) -> void:
	chunk._batch.add("text_" + text, PropFactory.text_mesh(text, height), Transform3D(Basis(Vector3.UP, yaw + PI), at), color)


## Tall pylon sign at a lot corner: pole plus a panel per name.
static func _pylon(chunk: CityChunk, at2: Vector2, names: Array, fascia: Color, rng: RandomNumberGenerator, height: float = 11.0) -> void:
	var at := Vector3(at2.x, TOP, at2.y)
	var instances := [
		["pylon_pole", PropFactory.cylinder("pylon_pole", 0.25, 1.0, Color(0.3, 0.3, 0.32), 0.25, 10), Transform3D(Basis().scaled(Vector3(1.0, height, 1.0)), at + Vector3(0.0, height * 0.5, 0.0))],
	]
	var y := height
	for i in names.size():
		var nm: String = names[i]
		var panel_h := 2.2 if i == 0 else 1.2
		instances.append(["pylon_panel", PropFactory.box("pylon_panel", Vector3(6.0, 1.0, 0.4), Color(1.0, 1.0, 1.0)), Transform3D(Basis().scaled(Vector3(1.0, panel_h, 1.0)), at + Vector3(0.0, y - panel_h * 0.5, 0.0)), fascia if i == 0 else Color(0.95, 0.95, 0.95)])
		var text_c := Color.WHITE if i == 0 else Color(0.1, 0.1, 0.12)
		instances.append(["text_" + nm, PropFactory.text_mesh(nm, 0.9 if i == 0 else 0.5), Transform3D(Basis(), at + Vector3(0.0, y - panel_h * 0.5, 0.22)), text_c])
		instances.append(["text_" + nm, PropFactory.text_mesh(nm, 0.9 if i == 0 else 0.5), Transform3D(Basis(Vector3.UP, PI), at + Vector3(0.0, y - panel_h * 0.5, -0.22)), text_c])
		y -= panel_h + 0.2
	chunk._add_prop("pylon", at, Color(0.3, 0.3, 0.32), instances, [[Vector3(0.6, height, 0.6), at + Vector3(0.0, height * 0.5, 0.0), 0.0]])


static func _corral(chunk: CityChunk, at2: Vector2) -> void:
	var at := Vector3(at2.x, TOP, at2.y)
	var instances := []
	for sx: float in [-2.0, 2.0]:
		instances.append(["corral_rail", PropFactory.box("corral_rail", Vector3(0.06, 0.06, 6.0), Color(0.3, 0.3, 0.32)), Transform3D(Basis(), at + Vector3(sx, 1.0, 0.0))])
		instances.append(["corral_rail", PropFactory.box("corral_rail", Vector3(0.06, 0.06, 6.0), Color(0.3, 0.3, 0.32)), Transform3D(Basis(), at + Vector3(sx, 0.5, 0.0))])
		for sz: float in [-3.0, 0.0, 3.0]:
			instances.append(["corral_post", PropFactory.box("corral_post", Vector3(0.08, 1.1, 0.08), Color(0.3, 0.3, 0.32)), Transform3D(Basis(), at + Vector3(sx, 0.55, sz))])
	instances.append(["text_CARTS", PropFactory.text_mesh("CARTS", 0.25), Transform3D(Basis(), at + Vector3(0.0, 1.4, -3.0)), Color(0.1, 0.1, 0.12)])
	instances.append(["corral_sign", PropFactory.box("corral_sign", Vector3(1.4, 0.5, 0.04), Color(0.95, 0.95, 0.9)), Transform3D(Basis(), at + Vector3(0.0, 1.4, -3.02))])
	chunk._add_prop("corral", at, Color(0.3, 0.3, 0.32), instances, [[Vector3(4.2, 1.1, 6.2), at + Vector3(0.0, 0.55, 0.0), 0.0]])
