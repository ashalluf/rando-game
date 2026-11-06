class_name Rc5Buskers
extends RefCounted
## The buskers' plaza at eye level (wave 8 refcam `buskers_plaza`, docs/HANDOFF.md "The buskers'
## plaza at 15:30"): what Buskers' plazas lacked when stood among them.
##
## - A plaza holds THREE acts (`SLOTS`): the third pitch stands beside the first, at the same end
##   of the square (`slot_side()`), rolled like the other two (PLAZA odds, its own hash id), so a
##   big square is a busy square. Slots 0 and 1 are rolled exactly as before.
## - The acts' people are not turned away by a full crowd cap (`RESERVE`): a performer and the ring
##   that came with him are a dozen people at most, and an act on the ground with nobody playing
##   it (the cap was spent by the time the plaza's steps ran) was the plaza's whole failure.
## - The plaza's open ground has its own passers-by (`plaza_walkers()`): the walkers of a PLAZA
##   block with acts cross it point to point (PlazaCrowd's open ground) instead of filing round
##   its pavement ring, so the middle of the square is not an empty field of paving.
## Staging, for the refcam and stills: BUSK_HOUR=h builds every act for that hour (Buskers'
## force_hour), BUSK_PLAZA=break,mariachi,statue forces a plaza's slots 0, 1, 2 to those kinds
## whatever the rolls and hours.
##
## Every roll is a hash of seed + block + slot. RC5_BUSKERS=0 in the environment is the A/B (two
## slots, the cap as before, no open-ground walkers, the looks as before).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_BUSKERS") != "0"

## Pitches on a plaza (Buskers' two, either side of the fountain on its long axis, and one beside
## the first).
const SLOTS := 3
## Extra walkers a PLAZA block with acts puts on its open ground (spawned through the crowd cap,
## after the block's own).
const PLAZA_WALKERS := 36
const KIND_NAMES := ["guitar", "drums", "break", "statue", "mariachi"]

## Staging: the hour every act is built for (-1: the chunk's own), the kinds a plaza's slots are
## forced to (empty: rolled).
static var stage_hour: float = float(OS.get_environment("BUSK_HOUR")) if OS.get_environment("BUSK_HOUR") != "" else -1.0
static var stage_plaza: Array = _kinds(OS.get_environment("BUSK_PLAZA"))
## Staging: the breakdancers' routine held at this second of its 18 s cycle (BUSK_BREAK_T; 13.5 is
## the one-hand freeze), -1 to run.
static var stage_break_t: float = float(OS.get_environment("BUSK_BREAK_T")) if OS.get_environment("BUSK_BREAK_T") != "" else -1.0


static func _kinds(text: String) -> Array:
	var out: Array = []
	var any := false
	for w in text.split(",", false):
		var k := KIND_NAMES.find(w.strip_edges().to_lower())
		out.append(k)
		any = any or k >= 0
	# "none" (or nothing a kind): not staged.
	return out if any else []


static func plaza_slots() -> int:
	return SLOTS if enabled or not stage_plaza.is_empty() else 2


## The forced kind of a plaza slot (-1: rolled).
static func forced_kind(slot: int) -> int:
	return int(stage_plaza[slot]) if slot < stage_plaza.size() else -1


## Whether a performer's own people take room the cap has left (true) or are refused like walkers.
static func reserve_room() -> bool:
	return enabled


## The direction a plaza slot's pitch is from the fountain (and the way its performer faces):
## slots 0 / 1 out along the long axis (+ / -); slot 2 shares slot 0's end of the square.
static func slot_dir(plan_seed: int, ix: int, iz: int, slot: int, long_x: bool) -> Vector2:
	var axis := Vector2(1.0, 0.0) if long_x else Vector2(0.0, 1.0)
	return axis * (-1.0 if slot == 1 else 1.0)


## How far a plaza slot's pitch stands to the side of its axis (m): 0 for slots 0 and 1; slot 2
## stands `SIDE_STEP` to one side of slot 0 (a hash of the block picks which), so two acts share
## the promenade at that end of the square with a gap for people between them.
const SIDE_STEP := 13.5


static func slot_side(plan_seed: int, ix: int, iz: int, slot: int, long_x: bool) -> Vector2:
	if slot < 2:
		return Vector2.ZERO
	var axis := Vector2(1.0, 0.0) if long_x else Vector2(0.0, 1.0)
	var s := 1.0 if (absi(hash([plan_seed, ix, iz, "busk_cross"])) % 2) == 0 else -1.0
	return Vector2(-axis.y, axis.x) * s * SIDE_STEP


## The open-ground passers-by of a PLAZA block whose acts were laid (Buskers.build_block): walkers
## of the block's own on a stream of their own, crossing the square point to point
## (PlazaCrowd's open ground, so the deal of rigs and looks and CrowdFlow's avoidance come with
## it), as many as the hour brings (PlazaCrowd.hour_factor). Spawned as build steps before the
## finish, through the crowd cap, after everything the block rolls.
static func plaza_walkers(chunk: CityChunk, block: Dictionary) -> void:
	if not enabled or not PlazaCrowd.enabled:
		return
	var inner: Rect2 = (block.rect as Rect2).grow(-5.0)
	var hour := Buskers.hour_now(chunk)
	var count := roundi(float(PLAZA_WALKERS) * PlazaCrowd.hour_factor(hour))
	if count <= 0:
		return
	PlazaCrowd.mark(chunk, inner)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([chunk.plan.seed, chunk.ix, chunk.iz, "busk_plaza_walkers"])
	for step in chunk._crowd_steps(inner, 3.0, count, rng):
		chunk._run_or_defer(step)


## How far the gear stands off the ground at its pitch: a plaza's paving is a 4 cm slab over the
## pavement height the gear was laid at (CityChunk._build_plaza), so on a plaza the cardboard,
## the case and the plinth's foot were buried in it (the breakdancer danced on bare setts).
const PLAZA_PAVING := 0.04


static func gear_lift(face: int) -> float:
	return PLAZA_PAVING if enabled and face < 0 else 0.0


## The plaza's fountain, made of water: the pool a disc on the landmarks' fountain water (dark,
## mirroring the sky, rippled round each jet) under the basin's coping, a ring of jets round the
## column and a curtain of streams falling from its bowl, on the landmarks' jet shader. Replaces
## the flat unshaded cylinder (CityChunk._build_plaza asks first; no roll). False when off.
const JETS := 8
const JET_HEIGHT := 2.3
const POOL_Y := 0.82
const BOWL_Y := 3.3
const BOWL_R := 1.3


static func fountain(ch: CityChunk, center: Vector2, basin_r: float) -> bool:
	if not enabled:
		return false
	if ch.capturing:
		return true
	var y0 := CityChunk.SIDEWALK_TOP + ch._gy(center.x, center.y)
	var pool_r := basin_r - 0.45
	# The pool: a fan of 48 with its UV in metres (the shader's ripples and jet rings).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var pts := [Vector2.ZERO, Vector2(cos(a1), sin(a1)) * pool_r, Vector2(cos(a0), sin(a0)) * pool_r]
		for p: Vector2 in pts:
			st.set_normal(Vector3.UP)
			st.set_uv(p + Vector2(0.0, 0.0))
			st.add_vertex(Vector3(p.x, 0.0, p.y))
	var pool := MeshInstance3D.new()
	pool.name = "PlazaPool"
	pool.mesh = st.commit()
	pool.material_override = LandmarkMats.water("plaza_pool", {"jet_spacing": 0.0, "ripple": 0.3})
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.position = Vector3(center.x, y0 + POOL_Y, center.y)
	ch.add_child(pool)
	# The jets and the curtain: crossed quads (UV.y 0 at the top, 1 at the nozzle).
	var jt := SurfaceTool.new()
	jt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var jr := minf(pool_r * 0.55, pool_r - 1.2)
	for i in JETS:
		var a := TAU * (float(i) + 0.5) / float(JETS)
		var base := Vector3(cos(a) * jr, POOL_Y, sin(a) * jr)
		# Leaning in toward the column a little, as a ring of jets is set.
		var top := base + Vector3(-cos(a), 0.0, -sin(a)) * 0.35 + Vector3.UP * JET_HEIGHT
		for k in 2:
			var side := Vector3(cos(a + PI * 0.5 * float(k)), 0.0, sin(a + PI * 0.5 * float(k))) * 0.32
			_quad(jt, top - side, top + side, base + side * 0.4, base - side * 0.4)
	# Streams falling from the bowl's lip into the pool: a ring of panels, UV.x across each.
	var m := 16
	for i in m:
		var a0 := TAU * float(i) / float(m)
		var a1 := TAU * float(i + 1) / float(m)
		var t0 := Vector3(cos(a0) * BOWL_R, BOWL_Y - 0.12, sin(a0) * BOWL_R)
		var t1 := Vector3(cos(a1) * BOWL_R, BOWL_Y - 0.12, sin(a1) * BOWL_R)
		var b0 := Vector3(cos(a0) * (BOWL_R + 0.35), POOL_Y, sin(a0) * (BOWL_R + 0.35))
		var b1 := Vector3(cos(a1) * (BOWL_R + 0.35), POOL_Y, sin(a1) * (BOWL_R + 0.35))
		# Falling: the nozzle end (UV.y 1, narrow) at the lip, the spread at the pool.
		_quad(jt, b0, b1, t1, t0)
	var jets := MeshInstance3D.new()
	jets.name = "PlazaJets"
	jets.mesh = jt.commit()
	jets.material_override = LandmarkMats.jet()
	jets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	jets.visibility_range_end = 180.0
	jets.position = Vector3(center.x, y0, center.y)
	ch.add_child(jets)
	return true


## A quad a -> b along the top (UV.y 0), d -> c along the bottom (UV.y 1), both faces drawn by
## the material (cull_disabled).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var p := [a, b, c, d]
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uv[i])
		st.add_vertex(p[i])


## The fountain's basin: a smooth wall (64 sides, not the primitive's 16 facets 4.7 m wide on a
## 12 m basin) of cast stone with a coping that overhangs it - a seat - and its inside face down to
## the water. One collision cylinder as before. False when off (CityChunk._build_plaza then lays
## the old cylinder).
const BASIN_SIDES := 64
const BASIN_TOP := 0.9
const COPING := 0.5
const COPING_H := 0.12
const COPING_OUT := 0.08


static func basin(ch: CityChunk, center: Vector2, basin_r: float, stone: Color) -> bool:
	if not enabled:
		return false
	if ch.capturing:
		return true
	var y0 := CityChunk.SIDEWALK_TOP + ch._gy(center.x, center.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ro := basin_r
	var rc := basin_r + COPING_OUT
	var ri := basin_r - COPING
	var top := BASIN_TOP
	var cb := top - COPING_H
	# Rings (radius, height, the normal's outward and up shares) in order round the profile: the
	# outer wall, the coping's underside lip, its outer edge, its top, its inner edge, the inside
	# face down to the water.
	var profile := [
		[ro, 0.0, 1.0, 0.0], [ro, cb, 1.0, 0.0],
		[rc, cb, 0.0, -1.0], [rc, cb, 1.0, 0.0], [rc, top, 1.0, 0.0],
		[rc, top, 0.0, 1.0], [ri, top, 0.0, 1.0],
		[ri, top, -1.0, 0.0], [ri, POOL_Y - 0.05, -1.0, 0.0],
	]
	for i in BASIN_SIDES:
		var a0 := TAU * float(i) / float(BASIN_SIDES)
		var a1 := TAU * float(i + 1) / float(BASIN_SIDES)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		for k in range(0, profile.size() - 1):
			var p: Array = profile[k]
			var q: Array = profile[k + 1]
			# Only the pairs that are a face (same normal), not the creases between them.
			if float(p[2]) != float(q[2]) or float(p[3]) != float(q[3]):
				continue
			var n0 := (d0 * float(p[2]) + Vector3.UP * float(p[3])).normalized()
			var n1 := (d1 * float(p[2]) + Vector3.UP * float(p[3])).normalized()
			var v: Array[Vector3] = [d0 * float(p[0]) + Vector3.UP * float(p[1]), d1 * float(p[0]) + Vector3.UP * float(p[1]),
				d1 * float(q[0]) + Vector3.UP * float(q[1]), d0 * float(q[0]) + Vector3.UP * float(q[1])]
			var nn: Array[Vector3] = [n0, n1, n1, n0]
			# Front faces wind clockwise seen from the side they face (Godot).
			var out := n0 + n1
			var cw: bool = (v[1] - v[0]).cross(v[2] - v[0]).dot(out) < 0.0
			var order := [0, 1, 2, 0, 2, 3] if cw else [0, 2, 1, 0, 3, 2]
			for j: int in order:
				st.set_normal(nn[j])
				st.add_vertex(v[j])
	var mi := MeshInstance3D.new()
	mi.name = "PlazaBasin"
	mi.mesh = st.commit()
	mi.material_override = PropFactory.pbr("concrete", 2.5, stone.lightened(0.25))
	mi.position = Vector3(center.x, y0, center.y)
	ch.add_child(mi)
	if ch._statics:
		var shape := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = basin_r
		s.height = BASIN_TOP
		shape.shape = s
		shape.position = Vector3(center.x, y0 + BASIN_TOP * 0.5, center.y)
		ch._statics.add_child(shape)
	return true


## Passers-by who stop at a breakdancer join the ring: spots on an outer row behind and between
## its own watchers, all the way round but the side the dancer's floor runs to (the boombox), so
## a crowd closes round the cardboard. The street vendors' queue mechanism (vendor_queue).
const RING_SPOTS := 7
const RING_OUTER := 1.15


static func ring_spots(chunk: CityChunk, v: Dictionary, at: Vector2, out: Vector2) -> void:
	if not enabled:
		return
	var queue: Array = chunk.get_meta("vendor_queue", [])
	var seed_v := int(v.seed)
	for i in RING_SPOTS:
		# From the dancer's right round the front to the left and on behind (a 300 degree arc).
		var ang := -PI * 0.85 + float(i) * (PI * 1.7 / float(RING_SPOTS - 1)) + (Buskers._h01([seed_v, "ring_out", i]) - 0.5) * 0.25
		var d := out.rotated(ang)
		var p := at + d * (Buskers.RING_RADIUS + RING_OUTER + (Buskers._h01([seed_v, "ring_outd", i]) - 0.5) * 0.6)
		var to := at - p
		queue.append({"p": p, "yaw": atan2(-to.x, -to.y), "taken": null, "record": {"busk": v.id}})
	chunk.set_meta("vendor_queue", queue)


## A trio's rigs: each player a different person (two of the three were often the same rig - the
## same face twice in one charro and sombrero). The rigs the trio has not used yet, while any are
## left; every other act's rigs as they are.
static func trio_rigs(kind: int, rigs: Array, used: Array) -> Array:
	if not enabled or kind != Buskers.Kind.MARIACHI or used.is_empty():
		return rigs
	var left := rigs.filter(func(r: String) -> bool: return not (r in used))
	return left if not left.is_empty() else rigs


## The rig a performer's seed gets (Buskers.seed_for's first roll, as Pedestrian._add_model()).
static func rig_of(s: int) -> String:
	var models: Array = Pedestrian.MODELS
	var r := RandomNumberGenerator.new()
	r.seed = hash([s, "style"])
	return String(models[r.randi() % models.size()]).get_file().get_basename()
