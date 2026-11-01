class_name AlleyNight
extends RefCounted
## The service alley at night (wave 5, refcam `alley_night`: a downtown alley at 23:00). What read
## as a game there: a clean, evenly lit, bone-dry slab; bulkhead lamps that were a lit box with a
## faint smudge under them; nothing on the plain wall between the back doors; nothing moving.
## Every piece hangs off the existing alley pass (Alleys / AlleyKit) by a hook line:
##   - the lamps (AlleyKit._lamp_at -> lamp()): a NightAtmos halo round each head (its bloom),
##     a stronger, wider pool, and the head recorded for the ground's mirror;
##   - wet patches (shaders/alley_ground.gdshader, `wet_on`): standing water down the V-gutter and
##     in the slab's dips, a darker damp halo round each, the alley's own lamps MIRRORED in them
##     (the reflected ray met where the lamp's mirror image crosses the ground, a streak toward
##     the eye) - the chunk's AlleyGround gets its own material copy with the heads (`ground()`);
##   - steam: a kitchen exhaust on the wall by some back doors (a hood and a louvre, written into
##     the alley's walls mesh) and now and then a drain in the gutter, each breathing
##     StreetClutter2's steam plume (`alley_steam` batch);
##   - tags: the plain stretches of the back walls (between the doors, under the windows) get the
##     street wear atlas' tags, throw-ups and buffs at hand height, through StreetWear._put (one
##     cap with the chunk's other wear).
## Every roll is a hash of the plan seed and the place, never a chunk / block / run rng: nothing
## the alley pass placed moves (AlleyKit's own rngs are untouched).
## Off (the A/B): ALLEY_NIGHT=0 in the environment.

static var enabled: bool = OS.get_environment("ALLEY_NIGHT") != "0"

## Most lamp heads one chunk's ground mirrors (the shader's array).
const MAX_HEADS := 18
## The lamps' pool on the ground: size (metres across) and strength (AlleyKit's was 7.5 / 0.85).
const POOL_SIZE := 9.5
const POOL_STRENGTH := 1.35
## Odds a back door has a kitchen exhaust over it, and a run a steaming drain.
const EXHAUST_ODDS := 0.4
const DRAIN_ODDS := 0.5
## Most steam plumes a chunk's alleys hold.
const MAX_STEAM := 6
const STEAM_KEY := "alley_steam"
const STEAM_DRAW := 110.0
## Tags per metre of plain back wall (on top of what StreetWear finds; the back walls are mostly
## window bays and doors to its spot finder), and the share that are throw-ups.
const TAGS_PER_M := 0.32
const THROWUP_SHARE := 0.35
## Tag heights: from, to (metres over the ground).
const TAG_LO := 0.45
const TAG_HI := 2.5


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _state(ch: CityChunk) -> Dictionary:
	var st := Alleys._state(ch)
	if not st.has("night"):
		st["night"] = {"heads": [], "steam": 0, "walls": []}
	return st.night


## A lamp head at `head` (chunk-local, its true height), tint `warm`: the halo, the mirror.
static func lamp(ch: CityChunk, head: Vector3, warm: bool) -> void:
	if not enabled:
		return
	var n := _state(ch)
	if (n.heads as Array).size() < MAX_HEADS:
		(n.heads as Array).append(Vector4(head.x, head.y, head.z, 1.0 if warm else 0.0))
	var ground := head.y - 2.6
	var w2 := Vector2(head.x, head.z)
	for part: Array in NightAtmos.lamp_parts([head - Vector3(0.0, ch._gy(head.x, head.z), 0.0)], head - Vector3(0.0, ch._gy(head.x, head.z), 0.0), ground - ch._gy(head.x, head.z), 4.0, w2, false):
		ch._batch.add(part[0], part[1], part[2], part[3], part[4])
	NightAtmos.finish_batch(ch._batch)


## The pool AlleyKit lays under a lamp, scaled and brightened.
static func pool_size() -> float:
	return POOL_SIZE if enabled else 7.5


static func pool_strength() -> float:
	return POOL_STRENGTH if enabled else 0.85


## A back door at `s` on a wall: maybe a kitchen exhaust over it. `put` writes a local-frame
## builder into the walls mesh at the wall (x along it, z out), `xf` the wall frame at the door.
static func door(ch: CityChunk, st: SurfaceTool, xf: Transform3D, door_s: float, stoop: bool) -> void:
	if not enabled:
		return
	var n := _state(ch)
	var p := xf.origin
	if _h01([ch.plan.seed, "alley_exhaust", int(p.x * 10.0), int(p.z * 10.0)]) >= EXHAUST_ODDS:
		return
	var side := 1.0 if _h01([ch.plan.seed, "alley_exhaust_side", int(p.x * 10.0)]) < 0.5 else -1.0
	var x := side * 1.15
	var y := 2.55 + (0.17 if stoop else 0.0)
	AlleyKit._put(st, xf, exhaust.bind(x, y))
	if int(n.steam) >= MAX_STEAM:
		return
	n.steam = int(n.steam) + 1
	var at := xf * Vector3(x, y + 0.05, 0.42)
	_steam(ch, at, [ch.plan.seed, "alley_exhaust_steam", int(p.x * 10.0), int(p.z * 10.0)], 0.0, 0.55)


## A steaming drain in the gutter of a run (s at the run's middle third, its centre line).
static func drain(ch: CityChunk, at: Vector3, key: Array) -> void:
	if not enabled:
		return
	var n := _state(ch)
	if int(n.steam) >= MAX_STEAM or _h01(key + ["drain"]) >= DRAIN_ODDS:
		return
	n.steam = int(n.steam) + 1
	_steam(ch, at, key, 1.0, 0.75)


static func _steam(ch: CityChunk, at: Vector3, key: Array, inlet: float, scale: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, _h01(key + ["yaw"]) * TAU).scaled(Vector3.ONE * scale * (0.85 + 0.3 * _h01(key + ["s"]))), at - Vector3(0.0, ch._gy(at.x, at.z), 0.0))
	ch._batch.add(STEAM_KEY, StreetClutter2.steam(), xf, Color.WHITE, Color(_h01(key + ["phase"]), 0.65 + 0.35 * _h01(key + ["k"]), inlet, 0.0))
	ch._batch.set_no_shadow(STEAM_KEY)
	ch._batch.set_draw_distance(STEAM_KEY, STEAM_DRAW)


## The exhaust: a galvanised hood and a louvred face on the wall, a grease stain under it.
static func exhaust(st: SurfaceTool, x: float, y: float) -> void:
	var galv := Color(0.55, 0.56, 0.55)
	AlleyKit._box(st, Vector3(x, y, 0.16), Vector3(0.62, 0.48, 0.32), IndustrialKit.K_GALV, galv)
	AlleyKit._box(st, Vector3(x, y + 0.27, 0.2), Vector3(0.7, 0.06, 0.42), IndustrialKit.K_GALV, galv * 0.9)
	for i in 5:
		AlleyKit._box(st, Vector3(x, y - 0.17 + 0.085 * float(i), 0.33), Vector3(0.54, 0.02, 0.04), IndustrialKit.K_STEEL, Color(0.12, 0.12, 0.12))
	AlleyKit._box(st, Vector3(x, y - 0.48, 0.012), Vector3(0.5, 0.5, 0.02), IndustrialKit.K_STEEL, Color(0.06, 0.055, 0.05))


## A plain stretch of a back wall (between `a` and `b` along it, chunk-local at the ground, `n` its
## outward normal, `ground_y` the ground's true height there, `height` the wall's): tags later.
static func wall(ch: CityChunk, a: Vector3, b: Vector3, n: Vector3, ground_y: float, height: float) -> void:
	if not enabled or a.distance_to(b) < 1.4 or height < 3.0:
		return
	(_state(ch).walls as Array).append([a, b, n, ground_y])


## The tags on the recorded walls, in StreetWear's ctx (AlleyKit.wear()).
static func tags(ch: CityChunk, ctx: Dictionary) -> void:
	if not enabled or not StreetWear.full_detail:
		return
	for w: Array in (_state(ch).walls as Array):
		var a: Vector3 = w[0]
		var b: Vector3 = w[1]
		var n: Vector3 = w[2]
		var gy: float = w[3]
		var L := a.distance_to(b)
		var dir := (b - a) / L
		var right := Vector3.UP.cross(n)
		var key := [ch.plan.seed, "alley_tags", int(a.x * 10.0), int(a.z * 10.0)]
		var rng := StreetWear._rng_for(key)
		var k := int(floor(L * TAGS_PER_M + rng.randf()))
		var used: Array = []
		for i in k:
			var big := rng.randf() < THROWUP_SHARE
			var tw := rng.randf_range(1.2, 2.2) if big else rng.randf_range(0.6, 1.3)
			tw = minf(tw, L - 0.3)
			if tw < 0.5:
				continue
			var s := rng.randf_range(tw * 0.5 + 0.15, L - tw * 0.5 - 0.15)
			var clash := false
			for u: Vector2 in used:
				if absf(u.x - s) < (u.y + tw) * 0.45:
					clash = true
			if clash:
				continue
			used.append(Vector2(s, tw))
			var th := tw * 0.5
			var cy := gy + clampf(rng.randf_range(TAG_LO + th * 0.5, TAG_HI - th * 0.5), TAG_LO + th * 0.5, TAG_HI)
			var c := a + dir * s + n * 0.014
			c.y = cy
			if not StreetWear._ok(ctx, Vector2(c.x, c.z)):
				return
			var age := rng.randf() * rng.randf()
			if big:
				StreetWear._put(ctx, StreetWear.MODE_TAG, rng.randi_range(StreetWear.THROWUPS.x, StreetWear.THROWUPS.y - 1), c, right, n, tw, th,
						StreetWear.FILL_COLORS[rng.randi() % StreetWear.FILL_COLORS.size()], age, StreetWear.OUTLINE_PAL[rng.randi() % StreetWear.OUTLINE_PAL.size()], 0, rng.randf())
			else:
				StreetWear._put(ctx, StreetWear.MODE_TAG, rng.randi() % StreetWear.HANDSTYLES, c, right, n, tw, th,
						StreetWear.TAG_COLORS[rng.randi() % StreetWear.TAG_COLORS.size()], age, 0, 0, rng.randf(), 0.0, rng.randf_range(-0.1, 0.1))
			if rng.randf() < 0.3:
				# A buff patch in a near-wall grey, a new tag on some.
				var bc := c + right * rng.randf_range(-0.2, 0.2) + n * 0.002
				StreetWear._put(ctx, StreetWear.MODE_BUFF, 0, bc, right, n, tw * 1.25, th * 1.4, Color(0.42, 0.33, 0.29).lerp(StreetWear.BUFF_COLORS[rng.randi() % StreetWear.BUFF_COLORS.size()], 0.5), 0.0, 0, 0, rng.randf())


## The chunk's ground material: the shared one, or a copy that mirrors its lamps and holds its
## water (ALLEY_NIGHT on).
static func ground(ch: CityChunk, base: ShaderMaterial) -> ShaderMaterial:
	if not enabled:
		return base
	var heads: Array = (_state(ch).heads as Array) if ch.has_meta("alley") else []
	var mat := base.duplicate() as ShaderMaterial
	var arr: Array[Vector4] = []
	for h: Vector4 in heads:
		arr.append(h)
	while arr.size() < MAX_HEADS:
		arr.append(Vector4(0.0, -1000.0, 0.0, 0.0))
	mat.set_shader_parameter("wet_on", 1.0)
	mat.set_shader_parameter("lamp_heads", arr)
	mat.set_shader_parameter("lamp_count", heads.size())
	return mat
