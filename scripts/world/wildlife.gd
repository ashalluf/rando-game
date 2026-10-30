class_name Wildlife
extends Node3D
## The city's urban wildlife (HANDOFF "Urban wildlife"): coyotes trotting across the hill roads and
## the streets at the suburbs' edge at dusk and through the night, mule deer grazing the hills at
## dawn, fox squirrels in the parks and on the lawns by day, cottontails on the hill grass and the
## park lawns morning and evening, raccoons at the kerb carts at night. A Node3D in city.tscn (the
## streamer's origin shifts carry it and the animals under it), like Birds.
##
## Nothing is per chunk. Every `survey_interval` the ground round the player is cut into `CELL`
## squares and each is asked `plan_cell()` (PURE: a hash of seed + cell + the half hour, the map's
## zone, the block's district and kind, the species' `WildSpecies.activity()` at the hour) whether
## something lives there now, and what: so the same canyon has its deer at the same dawn. A spot
## is spawned only out of the player's way (past `min_spawn`, and behind the camera inside
## `hidden_inside`) onto ground a world-layer ray finds where the plan says the ground is (never a
## roof), and dropped past `spawn_radius + despawn_margin`. A WildAnimal that bolts is gone once
## out of sight; its spot does not come back until the next half hour.
##
## Habitat: HILLS - deer (in small groups), rabbits, coyotes (crossing a hill road where the cell
## has one); park, school and cemetery grounds - squirrels, rabbits, coyotes at night; house
## blocks in the suburbs and the beach town - squirrels on the lawns, raccoons at the kerb carts
## (KerbBins: the street's collection day) or by a house, coyotes crossing the street - far more
## where the hills are near (the suburbs' edge).

const CELL := 46.0
## Rolls per cell and species: the most of each that may be out at once and the odds per cell at
## full activity, by habitat.
const HILL_ODDS := {"deer": 0.09, "rabbit": 0.1, "coyote": 0.045}
const PARK_ODDS := {"squirrel": 0.42, "rabbit": 0.07, "coyote": 0.05}
const HOUSE_ODDS := {"squirrel": 0.14, "raccoon": 0.13, "coyote": 0.022}
## How much more often a coyote turns up on a house or park block with the hills within
## `EDGE_REACH` metres (the suburbs' edge).
const EDGE_GAIN := 3.5
const EDGE_REACH := 380.0

## How far round the player animals are planned, the nearest one is put down, inside which it
## must be behind the camera, and how far past the radius they are dropped (m).
@export var spawn_radius: float = 135.0
@export var min_spawn: float = 30.0
@export var hidden_inside: float = 70.0
@export var despawn_margin: float = 60.0
## Animals out at once at most (desktop / web); Quality takes this down at LOW and LOWEST.
@export var max_animals: int = 14
@export var web_max_animals: int = 6
## Seconds between surveys (real clock).
@export var survey_interval: float = 1.0
## Off: no wildlife (the A/B; WILDLIFE=0 in the environment).
@export var enabled: bool = true

## Tests and stills: the hour plan_cell() is asked at (-1: DayNight's).
static var force_hour: float = -1.0
## Counted for the checks.
static var spawned: int = 0

var plan: CityPlan
var _player: Node3D
var _animals: Dictionary = {} # spot id -> WildAnimal
var _gone: Dictionary = {} # spot id -> true (bolted or dropped this half hour)
var _gone_bucket: int = -1
var _survey_left: float = 0.0
var _cap: int = 14
var _web := false


static func on() -> bool:
	return OS.get_environment("WILDLIFE") != "0"


func _ready() -> void:
	_web = OS.has_feature("web")
	if not on():
		enabled = false
	# The smoke test's other checks run without animals walking into them (their own checks call
	# survey() and stage() directly).
	if get_tree().root.get_node_or_null("SmokeTest") != null:
		enabled = false
	_cap = web_max_animals if _web else max_animals


func _setup() -> bool:
	if plan != null and _player != null and is_instance_valid(_player):
		return true
	var city := get_parent()
	if city == null or not ("plan" in city):
		return false
	plan = city.get("plan") as CityPlan
	_player = get_tree().get_first_node_in_group("player") as Node3D
	return plan != null and plan.macro != null and _player != null


func hour() -> float:
	if force_hour >= 0.0:
		return force_hour
	var dn := get_parent().get_node_or_null("DayNight") if get_parent() else null
	if dn and dn.get("hour") != null:
		return float(dn.get("hour"))
	return 12.0


func _process(delta: float) -> void:
	if not enabled or not _setup():
		return
	_survey_left -= delta / maxf(Engine.time_scale, 0.05)
	if _survey_left > 0.0:
		return
	_survey_left = survey_interval
	_cap_from_quality()
	survey()


func _cap_from_quality() -> void:
	var q := get_parent().get_node_or_null("Quality")
	var lv := int(q.get("level")) if q != null and q.get("level") != null else 0
	var base := web_max_animals if _web else max_animals
	_cap = int(base * [1.0, 1.0, 0.6, 0.3][clampi(lv, 0, 3)])


## The animals out now.
func animals() -> Array:
	var out: Array = []
	for a in _animals.values():
		if is_instance_valid(a):
			out.append(a)
	return out


## Drops what the player left behind, then puts down what lives round him now.
func survey() -> void:
	var eye := _player.global_position
	var w := WorldState.to_world(eye)
	var hr := hour()
	var bucket := int(floor(hr * 2.0))
	if bucket != _gone_bucket:
		_gone_bucket = bucket
		_gone.clear()
	var keep := spawn_radius + despawn_margin
	var count := 0
	for id in _animals.keys():
		var a: WildAnimal = _animals[id]
		if not is_instance_valid(a):
			_animals.erase(id)
			_gone[id] = true
			continue
		if Vector2(a.global_position.x - eye.x, a.global_position.z - eye.z).length() > keep:
			a.queue_free()
			_animals.erase(id)
			continue
		count += 1
	if count >= _cap:
		return
	var cam := get_viewport().get_camera_3d()
	var c0 := Vector2i(floori((w.x - spawn_radius) / CELL), floori((w.z - spawn_radius) / CELL))
	var c1 := Vector2i(floori((w.x + spawn_radius) / CELL), floori((w.z + spawn_radius) / CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			if count >= _cap:
				return
			for s: Dictionary in plan_cell(plan, cx, cz, hr):
				var id: int = s.id
				if _animals.has(id) or _gone.has(id):
					continue
				var at: Vector2 = s.at
				var dist := at.distance_to(Vector2(w.x, w.z))
				if dist > spawn_radius or dist < min_spawn:
					continue
				if dist < hidden_inside and cam != null:
					var lp := WorldState.to_local(Vector3(at.x, w.y, at.y))
					var dir := (lp - cam.global_position).normalized()
					if (-cam.global_basis.z).dot(dir) > 0.2:
						continue
				var made := _spawn(s)
				if made > 0:
					count += made


## What lives in cell (cx, cz) at `hr`: [{"id", "species", "at" (world xz), "count", "kind"
## (idle | cross | bins), "route" (world xz points), "radius"}]. Pure.
static func plan_cell(p: CityPlan, cx: int, cz: int, hr: float) -> Array:
	var out: Array = []
	var bucket := int(floor(hr * 2.0))
	var at := Vector2((float(cx) + lerpf(0.15, 0.85, _h01([p.seed, cx, cz, "wx"]))) * CELL,
		(float(cz) + lerpf(0.15, 0.85, _h01([p.seed, cx, cz, "wz"]))) * CELL)
	var r := _h01([p.seed, cx, cz, bucket, "wild"])
	var zone := p.zone_at(at)
	var odds: Dictionary = {}
	var habitat := ""
	var b: Dictionary = {}
	if zone == MacroMap.Zone.HILLS:
		habitat = "hills"
		odds = HILL_ODDS
	elif zone == MacroMap.Zone.CITY:
		var bi := p.block_index_at(at)
		b = p.block(bi.x, bi.y) as Dictionary
		var kind: int = int(b.get("kind", -1))
		var district: int = int(b.get("district", -1))
		if kind == CityPlan.BlockKind.PARK or kind == CityPlan.BlockKind.SCHOOL:
			habitat = "park"
			odds = PARK_ODDS
		elif kind == CityPlan.BlockKind.BUILDINGS and district in [CityPlan.District.SUBURBS, CityPlan.District.BEACHTOWN] \
				and not b.has("site"):
			habitat = "house"
			odds = HOUSE_ODDS
	if odds.is_empty():
		return out
	var edge := 1.0
	if habitat != "hills" and _hills_near(p, at):
		edge = EDGE_GAIN
	# One group a cell: the species' bands laid end to end on the roll.
	var acc := 0.0
	for sp: String in odds:
		var o: float = float(odds[sp]) * WildSpecies.activity(sp, hr)
		if sp == "coyote":
			o *= edge
		if r >= acc and r < acc + o:
			var g := {"id": absi(hash([p.seed, cx, cz, bucket, sp])), "species": sp, "at": at, "count": 1,
				"kind": "idle", "route": [], "radius": 8.0, "habitat": habitat}
			var r2 := _h01([p.seed, cx, cz, bucket, "n"])
			match sp:
				"deer":
					g.count = 1 + int(r2 * 3.0)
					g.radius = 14.0
				"rabbit":
					g.count = 1 + int(r2 * 1.8)
					g.radius = 5.0
				"squirrel":
					g.count = 1 + int(r2 * 1.7) if habitat == "park" else 1
					g.radius = 7.0
				"raccoon":
					g.count = 1 + int(r2 * 2.4)
					g.radius = 3.0
					var bins := _bins_near(p, at, hr)
					if bins != Vector2.INF:
						g.at = bins
						g.kind = "bins"
				"coyote":
					g.count = 1 + int(r2 * 1.5)
					var rt := _crossing(p, at, habitat, b, _h01([p.seed, cx, cz, "side"]))
					if not rt.is_empty():
						g.at = rt[0]
						g.route = rt.slice(1)
						g.kind = "cross"
			out.append(g)
			break
		acc += o
	return out


## The hills within EDGE_REACH of a point (four probes).
static func _hills_near(p: CityPlan, at: Vector2) -> bool:
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		if p.zone_at(at + d * EDGE_REACH) == MacroMap.Zone.HILLS:
			return true
	return false


## The nearest set of kerb carts out on its street today within 40 m (true world xz), or INF.
static func _bins_near(p: CityPlan, at: Vector2, _hr: float) -> Vector2:
	var bi := p.block_index_at(at)
	var day := KerbBins.today(p)
	var best := Vector2.INF
	var best_d := 40.0
	for s: Dictionary in KerbBins.block_sets(p, bi.x, bi.y):
		if not KerbBins.street_out(p, int(s.axis), int(s.index), day):
			continue
		var q := Vector2(float(s.lateral), float(s.along)) if int(s.axis) == CityPlan.AXIS_X else Vector2(float(s.along), float(s.lateral))
		# On the pavement behind the carts, not in the gutter.
		var back := Vector2(-float(s.side), 0.0) if int(s.axis) == CityPlan.AXIS_X else Vector2(0.0, -float(s.side))
		q += back * 1.1
		var d := q.distance_to(at)
		if d < best_d:
			best_d = d
			best = q
	return best


## A coyote's route across the nearest road: start a little short of it, the far side, then on
## (true world xz points), or [] when there is no road in reach.
static func _crossing(p: CityPlan, at: Vector2, habitat: String, b: Dictionary, side_r: float) -> Array:
	if habitat == "hills":
		if p.macro == null or p.macro.hill_roads == null:
			return []
		var segs: Array = p.macro.hill_roads.segments_in(Rect2(at - Vector2(30, 30), Vector2(60, 60)))
		for s: Dictionary in segs:
			if s.get("draw", true) == false and s.get("fire", false) == false:
				continue
			var a2: Vector2 = s.a
			var b2: Vector2 = s.b
			var mid := (a2 + b2) * 0.5
			var dir := (b2 - a2).normalized()
			var n := Vector2(-dir.y, dir.x) * (1.0 if side_r < 0.5 else -1.0)
			return [mid - n * 16.0 - dir * 4.0, mid + n * 14.0, mid + n * 34.0 + dir * 10.0]
		return []
	if b.is_empty() or not b.has("rect"):
		return []
	var rect: Rect2 = b.rect
	# The road on one side of the block (the side the roll picks), crossed square.
	var k := int(side_r * 4.0)
	var c := rect.get_center()
	var along := clampf(at.y if k < 2 else at.x, (rect.position.y if k < 2 else rect.position.x) + 8.0,
		(rect.end.y if k < 2 else rect.end.x) - 8.0)
	var e: Vector2
	var n: Vector2
	match k:
		0:
			e = Vector2(rect.position.x, along); n = Vector2(-1, 0)
		1:
			e = Vector2(rect.end.x, along); n = Vector2(1, 0)
		2:
			e = Vector2(along, rect.position.y); n = Vector2(0, -1)
		_:
			e = Vector2(along, rect.end.y); n = Vector2(0, 1)
	var road := 26.0
	return [e - n * 6.0, e + n * road, e + n * (road + 22.0) + (c - e).orthogonal().normalized() * 6.0]


## Puts down the group of spot `s` on found ground; how many it made.
func _spawn(s: Dictionary) -> int:
	var sp: String = s.species
	var at: Vector2 = s.at
	var n: int = s.count
	var made := 0
	for i in n:
		var off := Vector2.ZERO
		if i > 0:
			var a := _h01([s.id, i, "a"]) * TAU
			off = Vector2(sin(a), cos(a)) * lerpf(1.2, 4.0, _h01([s.id, i, "r"])) * (0.35 if sp in ["squirrel", "rabbit", "raccoon"] else 1.0)
		var wp := at + off
		var y := _ground(wp)
		if is_nan(y):
			continue
		var an := WildAnimal.new()
		an.setup(sp, absi(hash([s.id, i])))
		an.wid = absi(hash([s.id, i]))
		var lp := to_local(WorldState.to_local(Vector3(wp.x, y, wp.y)))
		an.position = lp
		an.home = lp
		an.home_radius = float(s.radius)
		an.at_bins = s.kind == "bins"
		an._yaw = _h01([s.id, i, "yaw"]) * TAU
		for q: Vector2 in s.route:
			var rq := q + off
			an.route.append(to_local(WorldState.to_local(Vector3(rq.x, y, rq.y))))
		if not an.route.is_empty():
			var d: Vector3 = an.route[0] - lp
			an._yaw = atan2(-d.x, -d.z)
		an.name = "Wild_%s_%d" % [sp, an.wid % 100000]
		add_child(an)
		if made == 0:
			_animals[s.id] = an
		else:
			_animals[absi(hash([s.id, i, "m"]))] = an
		made += 1
		spawned += 1
	return made


## The ground at a true world point (a world-layer ray), or NAN where nothing is there yet or the
## first thing hit stands well over the plan's ground (a roof, a car, a bench).
func _ground(wp: Vector2) -> float:
	var gy := plan.height_at(wp)
	var top := WorldState.to_local(Vector3(wp.x, gy + 30.0, wp.y))
	var bot := WorldState.to_local(Vector3(wp.x, gy - 12.0, wp.y))
	var q := PhysicsRayQueryParameters3D.create(top, bot, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return NAN
	var y := WorldState.to_world(hit.position).y
	if absf(y - gy) > 2.2:
		return NAN
	return y


## Puts one animal down at a true world point for stills and checks (calm: only a gun or a hit
## sends it off). `mode` idle | walk | trot | graze | sit.
func stage(species_name: String, wp: Vector2, yaw: float, seed_value: int = 1, calm_on: bool = true) -> WildAnimal:
	var y := _ground(wp)
	if is_nan(y):
		y = plan.height_at(wp) if plan else 0.0
	var an := WildAnimal.new()
	an.setup(species_name, seed_value)
	an.wid = seed_value
	an.calm = calm_on
	var lp := to_local(WorldState.to_local(Vector3(wp.x, y, wp.y)))
	an.position = lp
	an.home = lp
	an._yaw = yaw
	an.name = "Wild_stage_%s_%d" % [species_name, seed_value]
	add_child(an)
	_animals[absi(hash(["stage", species_name, seed_value]))] = an
	return an


static func _h01(key: Array) -> float:
	return float(absi(hash(key)) % 1000003) / 1000003.0
