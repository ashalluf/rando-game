class_name WalkOfFameNight
extends RefCounted
## The walk of fame at night (rc5-walk-of-fame-night, 2026-11-06; refcam `walk_of_fame_night` in
## tools/refcams/cameras_w8.json, docs/HANDOFF.md "The walk of fame at 22:00"). Judged from the
## south pavement at THE GRAND CELESTE's corner at 22:00, the view gave itself away four ways:
##   * the marquee says WORLD PREMIERE / RED CARPET / STARS IN PERSON and nothing was there: the
##     palace now has its premiere every evening (`PREMIERE_HOURS`, NightLife's), laid with
##     NightLife's own kit - the red carpet from its doors over the forecourt to the kerb between
##     brass stanchions and crowd barriers, fans behind them (NightGoer FAN, the first
##     `KEY_FANS` spawned even with the crowd cap full, as NightLife's scene people are), the press
##     lights' pool and light, four searchlights at the kerb (`premiere()`);
##   * of the costumed characters the plan puts on the stars, most were refused by the crowd cap
##     (the walk is in the middle of a busy midtown): they are the scene, so they spawn like the
##     premiere's key fans and are never trimmed (`key_character()`);
##   * the walk had two people on it at 22:00: a tourist strip is busiest after dark. Each walk
##     block face puts down `TOURISTS` x the hour's `TOURIST_KEYS` extra walkers on its own
##     boulevard pavement (ring walkers like ShopCrowd's: they walk on round the block after;
##     the crowd cap spent as any walker spends it) (`tourists()`);
##   * the lamps' star medallions were a thin outline nobody could read: the star is bigger
##     (`MEDALLION_R`), its plate lit from behind like a sign after dark and its neon tube thicker
##     (StarBoulevard.medallion_mesh(), star_neon.gdshader's `plate`).
## Hashes of seed + block only. Off (RC5_WALK_OF_FAME=0): the walk exactly as before, the A/B.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_WALK_OF_FAME") != "0"

## The premiere's hours (NightLife's), every evening at the Celeste: the marquee says so.
const PREMIERE_HOURS := Vector2(19.5, 25.0)
## How many of the premiere's fans spawn even with the crowd cap full (the first of each row).
const KEY_FANS := 10
## Extra walkers a walk block face puts down, at the hour's share (TOURIST_KEYS, a key an hour).
const TOURISTS := 14
## The first of them put down even with the crowd cap full (still counted; never trimmed): the
## walk at night IS its crowd, and the busy midtown round it fills the cap first.
const KEY_TOURISTS := 4
const TOURIST_KEYS: Array[float] = [0.55, 0.35, 0.2, 0.1, 0.05, 0.05, 0.1, 0.2, 0.35, 0.5, 0.6, 0.7,
	0.75, 0.8, 0.8, 0.8, 0.85, 0.9, 0.95, 1.0, 1.0, 1.0, 1.0, 0.9, 0.7]
## The lamps' star medallion: outer radius (was 0.42) and the neon tube's half width (was 0.018).
const MEDALLION_R := 0.52
const NEON_HALF := 0.03

## What the last builds put down (checks): premiere fans, characters, tourists.
static var fans_spawned: int = 0
static var characters_spawned: int = 0
static var tourists_spawned: int = 0


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## The hour to build at (`WOF_HOUR=` for small-scene stills that have no DayNight at the scene's
## root); < 0 reads NightLife's clock.
static var force_hour: float = float(OS.get_environment("WOF_HOUR")) if OS.get_environment("WOF_HOUR") != "" else -1.0


static func hour_now(node: Node) -> float:
	return force_hour if force_hour >= 0.0 else NightLife.hour_now(node)


## Is the premiere on at `hour`?
static func premiere_on(hour: float) -> bool:
	var h := fposmod(hour, 24.0)
	if h < 12.0:
		h += 24.0
	return h >= PREMIERE_HOURS.x and h < PREMIERE_HOURS.y


## The tourists a walk face carries at `hour`.
static func tourist_count(hour: float) -> int:
	var h := fposmod(hour, 24.0)
	var i := floori(h)
	return roundi(float(TOURISTS) * lerpf(TOURIST_KEYS[i], TOURIST_KEYS[i + 1], h - float(i)))


## StarBoulevard.steps(): the premiere (the palace's chunk) and the face's tourists.
static func steps(ch: CityChunk, rect: Rect2, side: int) -> Array[Callable]:
	var out: Array[Callable] = []
	if not enabled:
		return out
	var pal: Dictionary = StarBoulevard.plan_for(ch.plan).get("palace", {})
	if not pal.is_empty() and pal.block == Vector2i(ch.ix, ch.iz):
		var people: Array = []
		out.append(func() -> void: premiere(ch, pal, people))
		for i in NightLife.FANS_PER_SIDE * 2:
			out.append(func() -> void: _spawn_fan(ch, rect, people, i))
	for i in TOURISTS:
		out.append(func() -> void: _tourist(ch, rect, side, i))
	return out


## The premiere: carpet, stanchions and barriers (NightLifeKit.premiere), the press pool and light,
## searchlights at the kerb; fans planned into `people`.
static func premiere(ch: CityChunk, pal: Dictionary, people: Array) -> void:
	if not premiere_on(hour_now(ch)):
		return
	var f := StarBoulevard.palace_frame(ch, pal)
	var pxf: Transform3D = f[0]
	var to_kerb := float(f[3])
	var g := ch._gy(pxf.origin.x, pxf.origin.z)
	var base := Transform3D(pxf.basis, pxf.origin - Vector3(0.0, g, 0.0))
	var length := maxf(2.0, to_kerb - 0.35)
	var seed_value := hash([ch.plan.seed, "sb_premiere"])
	var holder := Node3D.new()
	holder.name = "WalkPremiere"
	ch.add_child(holder)
	var key := "nl_premiere_%d" % int(length * 10.0)
	var red := NightLife.CARPET_RED
	ch._batch.add(key, NightLifeKit.premiere(length, NightLife.CARPET_W), base, Color.WHITE, Color(red.r, red.g, red.b, 0.5))
	ch._batch.set_draw_distance(key, NightLife.ENTRANCE_DRAW)
	ch._batch.set_shadow_distance(key, NightLife.SHADOW_DISTANCE)
	var rows := clampi(int((length - 0.8) / 0.62), 1, NightLife.FANS_PER_SIDE)
	for i in rows:
		for s: float in [-1.0, 1.0]:
			var z := 0.8 + float(i) * 0.62 + (h01([seed_value, s, i, "fz"]) - 0.5) * 0.2
			var x := s * (NightLife.CARPET_W * 0.5 + 1.95 + h01([seed_value, s, i, "fx"]) * 0.35)
			var at := base * Vector3(x, 0.0, z)
			var face := (base.basis * Vector3(-s, 0.0, 0.25)).normalized()
			people.append({"seed": hash([seed_value, s, i, "fan"]), "spot": Vector2(at.x, at.z), "yaw": atan2(-face.x, -face.z)})
	var pool_at := base * Vector3(0.0, 0.0, length * 0.5)
	var pb := Basis(Vector3.RIGHT, -PI * 0.5)
	var pool := Transform3D(Basis(Vector3.UP, atan2(base.basis.z.x, base.basis.z.z)) * pb.scaled(Vector3(5.0, 1.0, length + 1.5)), Vector3(pool_at.x, CityChunk.SIDEWALK_TOP + 0.07, pool_at.z))
	ch._batch.add("nl_pool", PropFactory.shop_spill(), pool, Color(1.0, 0.82, 0.7, 0.42))
	ch._batch.set_no_shadow("nl_pool")
	NightLife._add_light(holder, base * Vector3(0.0, 4.5, length * 0.5) + Vector3(0.0, g, 0.0), 11.0, Color(1.0, 0.9, 0.8))
	for x: float in [-8.4, -5.3, 5.3, 8.4]:
		var at := base * Vector3(x, 0.0, to_kerb - 0.95)
		NightLife._add_searchlight(ch, holder, at, base.basis, hash([seed_value, x, "sl"]), true)
	ch._batch.set_shadow_distance("nl_cart", NightLife.SHADOW_DISTANCE)


static func _spawn_fan(ch: CityChunk, rect: Rect2, people: Array, i: int) -> void:
	if i >= people.size():
		return
	var s: Dictionary = people[i]
	var key_person := i < KEY_FANS
	if not ch._take_crowd_room() and not key_person:
		return
	var ped := NightGoer.new()
	var at: Vector2 = s.spot
	ped.setup_role(NightGoer.Role.FAN, rect, int(s.seed), {}, at, float(s.yaw))
	if key_person:
		ped.set_meta("no_trim", true)
	ped.position = Vector3(at.x, ch.ground_y(at.x, at.y) + 0.05, at.y)
	ch.add_child(ped)
	fans_spawned += 1


## StarBoulevard._spawn_character(): a character is spawned even with the crowd cap full and never
## trimmed (true), or (false, the A/B) only with room as before. Still counted against the cap.
static func key_character(ch: CityChunk) -> bool:
	if not enabled:
		return ch._take_crowd_room()
	ch._take_crowd_room()
	characters_spawned += 1
	return true


## One tourist: a ring walker put down on this face's boulevard pavement, by the band of stars.
static func _tourist(ch: CityChunk, rect: Rect2, side: int, i: int) -> void:
	if i >= tourist_count(hour_now(ch)):
		return
	if not ch.is_inside_tree() or ch.get_tree().root.get_node_or_null("SmokeTest") != null and not force_in_test:
		return
	var key_person := i < KEY_TOURISTS
	if not ch._take_crowd_room(Encampment.walker_reserve(ch.plan, ch.ix, ch.iz)) and not key_person:
		return
	var span := StarBoulevard.band_span(rect)
	if span.y - span.x < 4.0:
		return
	var sw := ch.plan.sidewalk_width
	var seed_value := hash([ch.plan.seed, ch.ix, ch.iz, "sb_tourist", i])
	var x := lerpf(span.x + 1.0, span.y - 1.0, h01([seed_value, "x"]))
	var inz := 1.0 if side > 0 else -1.0
	var z := StarBoulevard.kerb_z(rect, side) + inz * lerpf(1.2, maxf(sw - 1.0, 1.6), h01([seed_value, "z"]))
	var ped := Pedestrian.new()
	ped.setup(rect, sw, seed_value)
	if key_person:
		ped.set_meta("no_trim", true)
	ped.position = Vector3(x, CityChunk.SIDEWALK_TOP + 0.1 + ch._gy(x, z), z)
	ch.add_child(ped)
	CrowdFlow.spawned(ch, ped)
	tourists_spawned += 1


## The smoke test's crowd checks time walkers near home: tourists are only put down there when a
## check asks (ShopCrowd's rule).
static var force_in_test: bool = false


static var _plate: ShaderMaterial


## The medallion's gold star plate: star_neon.gdshader in its `plate` mode (gold metal by day, lit
## from behind like a sign after dark).
static func plate_material() -> ShaderMaterial:
	if _plate == null:
		_plate = ShaderMaterial.new()
		_plate.shader = load("res://shaders/star_neon.gdshader")
		_plate.set_shader_parameter("plate", 1.0)
	return _plate
