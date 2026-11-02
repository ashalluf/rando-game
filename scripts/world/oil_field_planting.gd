class_name OilFieldPlanting
extends RefCounted
## The oil field's hill planted like a real Los Angeles hill (refcam3 `oil_field`, docs/HANDOFF.md
## "The oil field from its lease road"): the field's ground was the hills' terrain material on a
## bare grid - from the lease road a flat beige sheet out to the fence, the one thing that gave the
## view away as a game. The real fields (Baldwin Hills, Signal Hill) are tawny wild oats and brome
## knee-high between the pads, grey-green coyote brush and sage in loose stands down the
## drainages, a live oak or a walnut in the gullies. This puts on the oil ground what the hill
## chunks already have, from the field's own plan:
##
##   * the hill SHELLS (HillShells, hill_shells.gdshader) on the field's ground mesh at FULL: the
##     ground's COLOR.b says where they may grow - clear() of the lease roads, the pads and the
##     fence, as a distance so the edge runs straight across a quad (OilFieldBuild._ground);
##   * code-built shrubs (HillShrub) in stands at FULL: a slow cluster noise plus the hill's
##     drainages (OilField.drainage) decide where, nothing within ROAD_KEEP of a road's edge (the
##     pipe rack and the power poles stand there) or PAD_KEEP of a pad;
##   * HillScatter's clumps past them (FULL: faded in from 70 m; LOD chunks: the bigger clumps),
##     so the stands still read from the far end of the field;
##   * live oaks (PropFactory.model_hill_oak) in the deeper gullies, FULL and LOD alike.
##
## Every roll is a hash of seed + world grid cell (no rng; nothing the field planned moves). The
## instances go into the chunk's batch, which lifts them onto the relief (the field is city
## ground), so their y is the pavement's top less a little, like the pumpjacks'. OIL_PLANTING=0 is
## the A/B.

static var enabled: bool = OS.get_environment("OIL_PLANTING") != "0"

## Metres of bare ground kept from a lease road's edge (the pipe rack at 1 m, the poles at 3.2 m),
## from a pad's levelled edge, and inside the fence.
const ROAD_KEEP := 4.5
const PAD_KEEP := 2.5
const FENCE_KEEP := 3.0
## The shells' own margins (hill_shells.gdshader's COLOR.b: 0.5 at the edge), metres: the grass
## runs up to the verge of the dirt and the pad's gravel. SHELL_SPAN is CityChunk.SHELL_CLEAR_SPAN.
const SHELL_ROAD := 0.8
const SHELL_PAD := 0.6
const SHELL_SPAN := 4.0
## World grids (metres) tried for a shrub, a clump (FULL / LOD) and an oak.
const SHRUB_SPACING := 3.2
const CLUMP_SPACING := 4.5
const LOD_CLUMP_SPACING := 7.0
const OAK_SPACING := 11.0
## The stand field (0..1) a shrub / clump needs; drainage weight; the share of the field's open
## flank that is grass (the cluster noise's offset).
const STAND_MIN := 0.5
const DRAIN_GAIN := 0.55
const CLUSTER_BIAS := 0.06
## How hard the cluster noise is stretched about its middle (simplex sits near 0.5).
const CLUSTER_GAIN := 1.7
## Lone sage out on the grass: the odds a grid point outside a stand has one.
const SAGE_ODDS := 0.12
## Oaks: the drainage they need and their odds there; their height range (metres).
const OAK_DRAIN := 0.45
const OAK_ODDS := 0.5
const OAK_HEIGHT := Vector2(6.5, 10.0)
## Shrub height (metres) range.
const SHRUB_HEIGHT := Vector2(0.9, 2.1)
## Service pickups parked on the pads (FULL): the odds a wells pad / tank battery has one, their
## body types (the road cars' far twins, CarParkBuild.real_body()) and work-fleet paints (sRGB).
const TRUCK_ODDS := 0.4
const TRUCK_BATTERY_ODDS := 0.7
const TRUCK_TYPES := [Vehicle.BodyType.WORK_TRUCK, Vehicle.BodyType.PICKUP, Vehicle.BodyType.WORK_TRUCK]
const TRUCK_PAINTS := [Color(0.86, 0.86, 0.84), Color(0.9, 0.9, 0.88), Color(0.62, 0.64, 0.66), Color(0.88, 0.87, 0.84),
	Color(0.18, 0.19, 0.2), Color(0.74, 0.72, 0.66)]
## Microseconds of planting a build step.
const STEP_BUDGET_US := 3500

static var _noise: FastNoiseLite = null


static func _u(h: int, k: int) -> float:
	return float((h >> (k * 10)) & 1023) / 1023.0


static func _cluster(sd: int, p: Vector2) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 1.0 / 46.0
		_noise.fractal_octaves = 3
		_noise.fractal_gain = 0.5
	_noise.seed = sd
	return _noise.get_noise_2dv(p) * 0.5 * CLUSTER_GAIN + 0.5


## Metres from `p` to the nearest lease road's edge and pad's edge ([road, pad]); INF past the
## field's own cell index (12 m round a road, a pad's banks).
static func clear(f: OilField, p: Vector2) -> Vector2:
	var cell := Vector2i(floori(p.x / OilField.CELL), floori(p.y / OilField.CELL))
	var road := INF
	for s: Array in f._seg_cells.get(cell, []):
		var pts: PackedVector2Array = f.roads[s[0]].pts
		var a := pts[int(s[1])]
		var ab := pts[int(s[1]) + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		road = minf(road, p.distance_to(a + ab * t) - OilField.ROAD_HALF)
	var pad := INF
	for k: int in f._pad_cells.get(cell, []):
		pad = minf(pad, OilField.pad_dist(f.pads[k], p))
	return Vector2(road, pad)


## Metres inside the fence (negative outside).
static func fence_in(f: OilField, p: Vector2) -> float:
	var r := f.rect.grow(-OilField.FENCE_IN)
	return minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.y - r.position.y, r.end.y - p.y))


## The ground's COLOR.b for the shells at `p`: 0.5 at the edge of what they keep off, over it
## where they grow.
static func shell_keep(f: OilField, p: Vector2) -> float:
	var c := clear(f, p)
	var d := minf(minf(c.x - SHELL_ROAD, c.y - SHELL_PAD), fence_in(f, p) - 1.0)
	return clampf(0.5 + d / (2.0 * SHELL_SPAN), 0.0, 1.0)


## How much of a stand `p` is in (0..1): the slow cluster noise, the drainages, the flanks over
## the crest (the graded roads' benches are flat and open).
static func stand(f: OilField, p: Vector2) -> float:
	return clampf(_cluster(f.seed, p) + f.drainage(p) * DRAIN_GAIN + CLUSTER_BIAS, 0.0, 1.0)


## Whether a plant may stand at `p` (keep-outs), with `extra` metres more room.
static func room(f: OilField, p: Vector2, extra: float) -> bool:
	if fence_in(f, p) < FENCE_KEEP + extra:
		return false
	var c := clear(f, p)
	return c.x > ROAD_KEEP + extra and c.y > PAD_KEEP + extra


## The hill shells on the field's ground mesh (FULL): the node, or null.
static func shells(mesh: Mesh, area: Rect2, lo: float, hi: float) -> Node:
	if not enabled or not CityChunk.shells_enabled:
		return null
	return HillShells.make(mesh, area, lo, hi)


## The planting step of a field chunk (OilFieldBuild.site_steps()); returns true when done.
static func step(b: OilFieldBuild) -> bool:
	if not enabled:
		return true
	var ch := b.ch
	var f := b.f
	var area := b.area.grow(-OilField.PAVEMENT)
	if area.size.x < 1.0 or area.size.y < 1.0:
		return true
	if not ch.has_meta("oil_planting"):
		ch.set_meta("oil_planting", {"phase": 0, "row": -1, "counts": {"shrub": 0, "sage": 0, "clump": 0, "oak": 0, "points": []}})
	var st: Dictionary = ch.get_meta("oil_planting")
	var t0 := Time.get_ticks_usec()
	# Phases: 0 shrubs (FULL), 1 clumps, 2 oaks.
	while int(st.phase) < 3:
		var ph: int = st.phase
		var spacing := SHRUB_SPACING if ph == 0 else (OAK_SPACING if ph == 2 else (CLUMP_SPACING if b.full else LOD_CLUMP_SPACING))
		if ph == 0 and not b.full:
			st.phase = 1
			continue
		var gz0 := floori(area.position.y / spacing)
		var gz1 := ceili(area.end.y / spacing)
		if int(st.row) < gz0:
			st.row = gz0
		var gx0 := floori(area.position.x / spacing)
		var gx1 := ceili(area.end.x / spacing)
		while int(st.row) < gz1:
			var j: int = st.row
			for i in range(gx0, gx1):
				_plant(b, ph, spacing, i, j, area, st.counts)
			st.row = j + 1
			if Time.get_ticks_usec() - t0 > STEP_BUDGET_US:
				return false
		st.phase = ph + 1
		st.row = -1
	for v in HillShrub.VARIANTS:
		ch._batch.set_no_shadow("oil_shrub_%d" % v)
		ch._batch.set_draw_distance("oil_shrub_%d" % v, HillGround3.SHRUB_DISTANCE)
	for key: String in ["oil_scatter_full", "oil_scatter_lod"]:
		ch._batch.set_no_shadow(key)
	ch._batch.set_draw_distance("oil_scatter_full", HillScatter.FULL_DRAW)
	ch._batch.set_draw_distance("oil_scatter_lod", HillScatter.LOD_DRAW)
	if b.full:
		_trucks(b, st.counts)
	ch.set_meta("oil_planting_done", st.counts)
	ch.remove_meta("oil_planting")
	return true


## Records a planted point for the checks (a MultiMesh reads back identity headless).
static func _note(counts: Dictionary, p: Vector2, kind: String) -> void:
	if (counts.points as Array).size() < 3000:
		(counts.points as Array).append([p, kind])


static func _plant(b: OilFieldBuild, ph: int, spacing: float, i: int, j: int, area: Rect2, counts: Dictionary) -> void:
	var f := b.f
	var ch := b.ch
	var h0 := hash([f.seed, "oil_plant", ph, int(spacing * 10.0), i, j])
	var p := Vector2((float(i) + 0.1 + 0.8 * _u(h0, 0)) * spacing, (float(j) + 0.1 + 0.8 * _u(h0, 1)) * spacing)
	if not area.has_point(p) or not f.rect.has_point(p):
		return
	var s := stand(f, p)
	var y := CityChunk.SIDEWALK_TOP - 0.02
	var grad := Vector2(ch._gy(p.x + 1.0, p.y) - ch._gy(p.x - 1.0, p.y), ch._gy(p.x, p.y + 1.0) - ch._gy(p.x, p.y - 1.0)) * 0.5
	var slope := grad.length()
	var yaw := TAU * _u(h0, 2)
	match ph:
		0:
			var in_stand := s > STAND_MIN + 0.08 * (_u(hash([h0, 1]), 0) - 0.5)
			if not in_stand and _u(hash([h0, 2]), 0) > SAGE_ODDS:
				return
			if not room(f, p, 0.0):
				return
			var tone := _u(hash([h0, 3]), 0)
			var size := _u(hash([h0, 3]), 1)
			var v := int(tone * 30.0) % HillShrub.VARIANTS
			var up := Vector3(-grad.x, 1.0, -grad.y).normalized().lerp(Vector3.UP, 0.6).normalized()
			var tilt := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw)
			var variety := Color(_u(h0, 2) * 0.3, tone, size, 0.0)
			if in_stand:
				var hs := lerpf(SHRUB_HEIGHT.x, SHRUB_HEIGHT.y, size * size * (0.6 + 0.4 * s)) / HillShrub.HEIGHT
				ch._batch.add("oil_shrub_%d" % v, HillShrub.mesh(v), Transform3D(tilt.scaled(Vector3(hs * 1.45, hs, hs * 1.45)), Vector3(p.x, y - 0.1 - slope * 1.2, p.y)),
					Color(1.0, 1.0, 1.0).lerp(Color(1.18, 1.15, 1.08), tone), variety)
				counts.shrub = int(counts.shrub) + 1
				_note(counts, p, "shrub")
			else:
				# A lone sage or buckwheat out on the grass: small and paler.
				var hs := lerpf(0.7, 1.2, size) / HillShrub.HEIGHT
				ch._batch.add("oil_shrub_%d" % v, HillShrub.mesh(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(hs, hs, hs)), Vector3(p.x, y - 0.1, p.y)),
					Color(1.45, 1.45, 1.3), Color(variety.r, variety.g, 0.8, 0.0))
				counts.sage = int(counts.sage) + 1
				_note(counts, p, "sage")
		1:
			if s < STAND_MIN + 0.05 or not room(f, p, 1.0):
				return
			var full := b.full
			var sc := HillScatter.FULL_SCALE if full else HillScatter.LOD_SCALE
			var k := lerpf(sc.x, sc.y, _u(h0, 2)) * lerpf(0.75, 1.15, s)
			var up := Vector3(-grad.x, 1.0, -grad.y).normalized().lerp(Vector3.UP, 0.55).normalized()
			var basis := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw)
			basis = basis.scaled(Vector3(k * 1.1, k * lerpf(0.8, 1.1, _u(h0, 1)), k))
			var key := "oil_scatter_full" if full else "oil_scatter_lod"
			ch._batch.add(key, HillScatter.mesh_for("full" if full else "lod"), Transform3D(basis, Vector3(p.x, y - 0.1 - slope * 1.4 * k, p.y)), Color.WHITE,
				Color(_u(h0, 0), _u(h0, 2), float(full), 0.0))
			counts.clump = int(counts.clump) + 1
			_note(counts, p, "clump")
		2:
			var dr := f.drainage(p)
			if dr < OAK_DRAIN or _u(hash([h0, 4]), 0) > OAK_ODDS * dr or slope > 0.45 or not room(f, p, 4.0):
				return
			var tone := _u(hash([h0, 5]), 0)
			var v := int(tone * 10.0) % PropFactory.HILL_OAKS.size()
			var hs := lerpf(OAK_HEIGHT.x, OAK_HEIGHT.y, _u(hash([h0, 5]), 1)) / PropFactory.hill_oak_height(v)
			var tint := Color(1.35, 1.4, 0.85).lerp(Color(1.6, 1.62, 1.0), tone)
			var variety := Color(_u(h0, 0), _u(h0, 1), _u(h0, 2) * 0.5, 0.0)
			ch._batch.add("hill_oak_%d" % v, PropFactory.model_hill_oak(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(hs, hs, hs)), Vector3(p.x, y - 0.1, p.y)), tint, variety)
			counts.oak = int(counts.oak) + 1
			_note(counts, p, "oak")


## A service pickup on some pads, parked along the road edge of the pad clear of the pumpjacks: a
## real parked Vehicle (it is right beside the lease road, where the far twin's folded wheels read
## as white discs), built as a deferred step; past PhysicsBudget's cap, the far twin in the batch.
static func _trucks(b: OilFieldBuild, counts: Dictionary) -> void:
	var f := b.f
	var ch := b.ch
	for pd: Dictionary in f.pads:
		if not b.area.has_point(pd.c) or int(pd.kind) == OilField.Pad.RIG:
			continue
		var h0 := hash([f.seed, "oil_truck", int(pd.id)])
		var odds := TRUCK_BATTERY_ODDS if int(pd.kind) == OilField.Pad.BATTERY else TRUCK_ODDS
		if _u(h0, 0) > odds:
			continue
		var t: int = TRUCK_TYPES[int(_u(h0, 1) * 2.999)]
		var dir: Vector2 = pd.dir
		var out: Vector2 = pd.out
		var end := 1.0 if _u(h0, 2) < 0.5 else -1.0
		var p: Vector2 = (pd.c as Vector2) + dir * end * (float(pd.hx) - 4.0) - out * (float(pd.hz) - 2.6)
		var face := dir * (1.0 if _u(h0, 3) < 0.5 else -1.0)
		var yaw := atan2(face.x, face.y) + (_u(h0, 4) - 0.5) * 0.25
		var paint: Color = TRUCK_PAINTS[int(_u(hash([h0, 1]), 0) * float(TRUCK_PAINTS.size()) - 0.001)]
		var look := hash([h0, "look"])
		ch._run_or_defer(func() -> bool:
			if not is_instance_valid(ch):
				return true
			if not PhysicsBudget.can_spawn():
				var body := CarParkBuild.real_body(t)
				if body.has("mesh"):
					# The pad is graded level and the batch lifts onto the relief.
					var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, CityChunk.SIDEWALK_TOP + OilFieldBuild.DIRT_LIFT, p.y)) * Transform3D(Basis(), body.offset)
					ch._batch.add("oil_truck_%d" % t, body.mesh, xf, Color.WHITE, Color(paint.r, paint.g, paint.b, 1.0))
					ch._batch.set_draw_distance("oil_truck_%d" % t, 260.0)
				return true
			var car := Vehicle.new()
			car.setup(t, paint, Vehicle.Addon.NONE)
			car.setup_look(Vehicle.Finish.GLOSS)
			car.look_seed = look
			car.set_meta("oil_field", true)
			var holder: Node = ch.get_parent() if ch.get_parent() else ch
			var spot := Vector3(p.x, CityChunk.SIDEWALK_TOP + ch._gy(p.x, p.y) + OilFieldBuild.DIRT_LIFT + 0.4, p.y)
			car.position = WorldState.to_local(spot) if holder != ch else spot
			car.rotation.y = yaw
			holder.add_child(car)
			car.visible = ch.visible
			ch._cars.append(car)
			return true)
		counts.truck = int(counts.get("truck", 0)) + 1
		_note(counts, p, "truck")
