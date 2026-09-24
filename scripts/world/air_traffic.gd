class_name AirTraffic
extends Node3D
## The living sky (owner, 2026-09-24: "helicopters, police choppers, news choppers, private jets
## flying thru the sky, commercial jets taking off and landing at LAX"). A child of the city
## root, so it rides the origin re-centering; every aircraft it owns keeps its position in TRUE
## world space and converts through WorldState each tick (AmbientCraft.apply_pose()).
##
## What flies:
##   Arrivals   airliners (and some private jets) down a curved approach that comes up the basin
##              from the south, turns onto a 3 degree final over the city east of the airport and
##              lands westbound on the southern runway (the east range is two kilometres from the
##              fence, so a straight-in approach from the east would run into it). Flare,
##              touchdown on the centre line, rollout, taxi, fade out at the runway end.
##   Departures fade in lined up on the middle runway, roll west, climb out over the ocean and
##              turn north-west or south-west. The same west flow the real field uses.
##   Private    jets crossing the basin high on seeded routes; some of them come in to land.
##   News       a helicopter cruising over downtown; after an explosion near the player (see
##              Explosion.blast_count) it comes and circles the scene at `news_orbit_radius`.
##   Police     a patrol helicopter, and at `police_stars` stars (the group "wanted", read with
##              .get("stars") - the wanted system may not exist) one or two circle the player
##              with the searchlight on him; they fly off when the stars clear.
## Everything can be shot down (AmbientCraft); the schedule fills the gap later.
##
## Routes are AirRoutes, built once at the first tick (CityStreamer builds `plan` in its own
## _ready, which runs after this node's) and lifted clear of the real city: obstacle_top() reads
## the same lots and massing heights the chunks and the skyline build from, the freeway decks,
## the landmarks' actual bounds and the terrain. The cost is a handful of nodes and a few
## lookups a tick; nothing here walks the city.

@export_group("Schedule")
## Most aircraft in the sky at once (the web build is capped lower).
@export var max_aircraft: int = 10
@export var web_max_aircraft: int = 6
## Seconds between arrivals and between departures, give or take `interval_jitter`.
@export var arrival_interval: float = 70.0
@export var departure_interval: float = 76.0
@export var interval_jitter: float = 18.0
## Seconds between private jets, and the share of them that land.
@export var private_interval: float = 55.0
@export_range(0.0, 1.0) var private_landing_share: float = 0.3
@export var max_arrivals: int = 2
@export var max_departures: int = 2
@export var max_private: int = 2
## Share of arrivals and departures flown by private jets rather than airliners.
@export_range(0.0, 1.0) var private_share: float = 0.2
@export_group("Approach")
## Glide slope (degrees), and how far in from the east end of the runway the glide path aims.
@export var glide_slope_deg: float = 3.0
@export var aim_inset: float = 190.0
## The downwind leg runs north up this line (world x) and turns onto final with this radius.
@export var downwind_x: float = 1950.0
@export var final_turn_radius: float = 750.0
## Height kept over the city under the final: near the fence and from 2.5 km out (m).
@export var approach_clearance: Vector2 = Vector2(6.0, 80.0)
## Steepest the approach may descend after an obstacle (degrees).
@export var max_descent_deg: float = 5.0
@export_group("Departure")
## How far in from the east end of the runway a departure lines up (the hangars stand on it).
@export var lineup_inset: float = 135.0
## Climb gradient after lift-off (degrees), and where the climb-out turn starts (world x).
@export var climb_deg: float = 8.0
@export var turn_out_x: float = -1700.0
@export var cruise_altitude: float = 1500.0
@export_group("Private jets")
## Altitude band private jets cross the basin at (m).
@export var crossing_altitude: Vector2 = Vector2(900.0, 1350.0)
@export_group("News")
## Explosions further than this from the player do not make the news (m).
@export var news_interest_radius: float = 1500.0
## The orbit over a scene: radius and height over the ground there (m), and how long it stays
## after the last explosion (s).
@export var news_orbit_radius: float = 170.0
@export var news_orbit_height: float = 140.0
@export var news_linger: float = 90.0
## Cruising over downtown: how far from its centre, and at least how high (m).
@export var news_cruise_radius: float = 650.0
@export var news_cruise_height: float = 260.0
## Stars at which the news covers the player instead of cruising.
@export var news_follow_stars: int = 2
## Seconds before a shot-down news helicopter is replaced.
@export var news_respawn: float = 40.0
@export_group("Police")
## Stars that bring the police helicopters; one more star brings a second.
@export var police_stars: int = 3
## Orbit round the player: radius of the first and the second helicopter, and height over him.
@export var police_orbit_radius: Vector2 = Vector2(80.0, 96.0)
@export var police_orbit_height: float = 62.0
## Leaving helicopters are removed this far from the player (m).
@export var police_leave_distance: float = 1600.0
## Seconds before a downed police helicopter is replaced while the stars last.
@export var police_respawn: float = 25.0
## A police helicopter patrols the city with no stars (searchlight at night).
@export var police_patrol: bool = true
@export var patrol_height: float = 230.0
@export_group("Spawning")
## Helicopters arrive from this far away, behind the camera (m).
@export var spawn_distance: float = 1300.0

## obstacle_top() cell size (m).
const CELL := 50.0
## What stands on a lot above its massing height: water tanks, plant, masts.
const ROOF_ALLOWANCE := 10.0
## Lamp posts, street trees and wires on any city ground, lots or no lots.
const STREET_ALLOWANCE := 10.0
## Trees on the hills, cranes in the port.
const HILL_ALLOWANCE := 20.0
const PORT_ALLOWANCE := 65.0
## Height over the ground above which nothing in the city can reach (the boosted downtown core
## tops out near 370 m with its roof plant).
const HIGH_ENOUGH := 420.0

var plan: CityPlan
var macro: MacroMap
## Routes by name: "arrival_south", "arrival_southwest", "departure_<kind>_<left|right>".
var routes: Dictionary = {}
var runway_top: float = 0.14
var stars: int = 0
var news_heat: float = 0.0
## Where the news is looking, TRUE world.
var news_focus: Vector3 = Vector3.INF
## Debug: stars forced from outside (tests, stills); -1 reads the wanted system.
var forced_stars: int = -1
## Times a police helicopter has reported the player to the wanted system (tests read it).
var sightings: int = 0

var _ready_done: bool = false
var _rng := RandomNumberGenerator.new()
var _crafts: Array[AmbientCraft] = []
var _cells: Dictionary = {}
var _block_lots: Dictionary = {}
var _landmark_boxes: Array = []
var _player: Node3D
var _day: Node
var _env: Environment
var _arrival_timer: float = 8.0
var _departure_timer: float = 30.0
var _private_timer: float = 20.0
var _poll_timer: float = 0.0
var _seen_blasts: int = 0
var _news_respawn_left: float = 0.0
var _police_respawn_left: float = 0.0
var _patrol_left: float = 0.0
var _lamp: float = 0.0
var _volumetric: bool = false
var _look_timer: float = 0.0
var _serial: int = 0


func _ready() -> void:
	add_to_group("air_traffic")
	_rng.seed = 7331
	# The count is static: blasts from before a scene reload are not news in this one.
	_seen_blasts = Explosion.blast_count
	if OS.has_feature("web"):
		max_aircraft = mini(max_aircraft, web_max_aircraft)


func _physics_process(delta: float) -> void:
	if not _ready_done and not _setup():
		return
	advance(delta)


## One tick of the schedule, the chaos and wanted polls, and every helicopter's orders. The
## aircraft move themselves (their own _physics_process); tests call this and
## AmbientCraft.advance() directly to run minutes of traffic in one frame.
func advance(dt: float) -> void:
	if not _ready_done:
		return
	_poll_timer -= dt
	if _poll_timer <= 0.0:
		_poll_timer = 0.25
		_poll()
	news_heat = maxf(news_heat - dt / maxf(news_linger, 1.0), 0.0)
	_news_respawn_left -= dt
	_police_respawn_left -= dt
	_patrol_left -= dt
	_schedule(dt)
	_order_news()
	_order_police(dt)


# --- Setup ------------------------------------------------------------------------------------

func _setup() -> bool:
	var city := get_parent()
	if city == null or not ("plan" in city):
		return false
	plan = city.get("plan") as CityPlan
	if plan == null or plan.macro == null:
		# The plain endless grid has no airport; nothing to fly.
		set_physics_process(plan == null)
		return false
	macro = plan.macro
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_day = city.get_node_or_null("DayNight")
	var we := city.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_env = we.environment if we else null
	runway_top = macro.tarmac_top + 0.04
	_measure_landmarks(city)
	_build_routes()
	_ready_done = true
	_populate()
	return true


## The real bounds of every landmark, from the far copies CityStreamer always keeps, so the
## obstacle field knows the towers and the control tower without a second copy of their sizes.
func _measure_landmarks(city: Node) -> void:
	for holder in city.get_children():
		if not (holder is Node3D) or not String(holder.name).begins_with("FarLandmark_"):
			continue
		var box := AABB()
		var first := true
		for n in (holder as Node3D).find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if first:
			continue
		var p := WorldState.to_world(box.position)
		_landmark_boxes.append([Rect2(p.x, p.z, box.size.x, box.size.z), p.y + box.size.y])


func _build_routes() -> void:
	var rect := macro.airport_rect
	var zs := macro.runway_zs
	var arrive_z: float = zs[clampi(macro.arrival_runway, 0, zs.size() - 1)]
	var depart_z: float = zs[mini(1, zs.size() - 1)]
	var east := rect.end.x
	var west := rect.position.x
	var aim := Vector2(east - aim_inset, arrive_z)
	var stop := Vector2(west + 20.0, arrive_z)
	var corner := Vector2(downwind_x, arrive_z)
	var south := PackedVector2Array([Vector2(downwind_x - 300.0, arrive_z + 7600.0), Vector2(downwind_x, arrive_z + 2600.0), corner, aim, stop])
	routes["arrival_south"] = _arrival_route("arrival_south", south, PackedFloat32Array([0.0, 900.0, final_turn_radius, 0.0, 0.0]), aim)
	var southwest := PackedVector2Array([Vector2(-2600.0, arrive_z + 5300.0), Vector2(downwind_x - 850.0, arrive_z + 3300.0), Vector2(downwind_x, arrive_z + 2000.0), corner, aim, stop])
	routes["arrival_southwest"] = _arrival_route("arrival_southwest", southwest, PackedFloat32Array([0.0, 1500.0, 900.0, final_turn_radius, 0.0, 0.0]), aim)
	for kind in [Aircraft.Kind.AIRLINER, Aircraft.Kind.PRIVATE]:
		for side in ["left", "right"]:
			var name := "departure_%d_%s" % [kind, side]
			routes[name] = _departure_route(name, kind, side == "left", Vector2(east - lineup_inset, depart_z), west)


## Glide slope all the way out, lifted clear of the city, never climbing on the way down.
func _arrival_route(route_name: String, pts: PackedVector2Array, radii: PackedFloat32Array, aim: Vector2) -> AirRoute:
	var r := AirRoute.from_waypoints(pts, radii, route_name)
	var aim_d := r.nearest(aim)
	r.marks["aim"] = aim_d
	r.marks["runway_y"] = runway_top
	r.marks["fade_start"] = r.length - 70.0
	var slope := tan(deg_to_rad(glide_slope_deg))
	var req := PackedFloat32Array()
	req.resize(r.xz.size())
	for i in r.xz.size():
		var s := aim_d - r.dist[i]
		r.y[i] = runway_top + maxf(s, 0.0) * slope
		if s <= 0.0 or macro.zone_at(r.xz[i]) == MacroMap.Zone.AIRPORT:
			req[i] = 0.0
			continue
		var clearance := lerpf(approach_clearance.x, approach_clearance.y, smoothstep(200.0, 2500.0, s))
		req[i] = _swept_top(r, i, 30.0 if s < 3000.0 else 0.0) + clearance
	r.clear(req, 0.0, tan(deg_to_rad(max_descent_deg)))
	return r


## On the runway to lift-off, then the climb gradient eased in, then a turn out over the sea.
func _departure_route(route_name: String, kind: Aircraft.Kind, left: bool, start: Vector2, _west: float) -> AirRoute:
	var probe := AmbientJet.new()
	probe.setup_numbers(kind)
	var lift := probe.liftoff_speed * probe.liftoff_speed / (2.0 * probe.roll_accel)
	probe.free()
	var turn := Vector2(turn_out_x, start.y)
	var heading := deg_to_rad(225.0 if left else 315.0)
	# Compass bearing (0 north = -z, 90 east = +x) to an XZ direction.
	var out := Vector2(sin(heading), -cos(heading))
	var pts := PackedVector2Array([start, turn, turn + out * 9000.0])
	var r := AirRoute.from_waypoints(pts, PackedFloat32Array([0.0, 1500.0, 0.0]), route_name)
	r.marks["runway_start"] = 0.0
	r.marks["liftoff"] = lift
	r.marks["runway_y"] = runway_top
	var grade := tan(deg_to_rad(climb_deg))
	var ease := 350.0
	var req := PackedFloat32Array()
	req.resize(r.xz.size())
	for i in r.xz.size():
		var x := r.dist[i] - lift
		var h := 0.0
		if x > 0.0:
			h = grade * x * x / (2.0 * ease) if x < ease else grade * (x - ease * 0.5)
		r.y[i] = runway_top + minf(h, cruise_altitude)
		req[i] = 0.0 if x < 1000.0 else _swept_top(r, i, 0.0) + 60.0
	r.clear(req, 0.2, 0.0)
	return r


## A private jet across the basin: in from a seeded bearing, out the far side.
func _crossing_route(rng: RandomNumberGenerator) -> AirRoute:
	var centre := Vector2(500.0, 700.0)
	var a := rng.randf() * TAU
	var b := a + PI + rng.randf_range(-0.7, 0.7)
	var p0 := centre + Vector2(cos(a), sin(a)) * 9000.0
	var p2 := centre + Vector2(cos(b), sin(b)) * 9000.0
	var mid := centre + Vector2(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0))
	var r := AirRoute.from_waypoints(PackedVector2Array([p0, mid, p2]), PackedFloat32Array([0.0, 3000.0, 0.0]), "crossing")
	var alt := rng.randf_range(crossing_altitude.x, crossing_altitude.y)
	var req := PackedFloat32Array()
	req.resize(r.xz.size())
	for i in r.xz.size():
		r.y[i] = alt
		req[i] = _swept_top(r, i, 0.0) + 250.0
	r.clear(req, 0.1, 0.06)
	return r


## A private jet coming in to land: from a bearing south of the basin onto the approach.
func _private_arrival_route(rng: RandomNumberGenerator) -> AirRoute:
	var base: AirRoute = routes["arrival_south"]
	var zs := macro.runway_zs
	var arrive_z: float = zs[clampi(macro.arrival_runway, 0, zs.size() - 1)]
	var aim := Vector2(macro.airport_rect.end.x - aim_inset, arrive_z)
	var stop := Vector2(macro.airport_rect.position.x + 20.0, arrive_z)
	var bearing := deg_to_rad(rng.randf_range(160.0, 235.0))
	var join := Vector2(downwind_x, arrive_z + 2600.0)
	var entry := join + Vector2(sin(bearing), -cos(bearing)) * 8000.0
	var pts := PackedVector2Array([entry, join, Vector2(downwind_x, arrive_z), aim, stop])
	var r := _arrival_route("private_arrival", pts, PackedFloat32Array([0.0, 1200.0, final_turn_radius, 0.0, 0.0]), aim)
	r.marks["fade_start"] = base.marks.get("fade_start", r.length - 70.0)
	return r


## The tallest thing under route point `i` (and `side` metres either side of it). A point
## flying higher over the ground than the tallest tower in the city could reach only needs the
## terrain: the lots are the expensive part of obstacle_top(), and a crossing at a kilometre
## would otherwise read every lot under eighteen kilometres of track.
func _swept_top(r: AirRoute, i: int, side: float) -> float:
	var p: Vector2 = r.xz[i]
	var ground := macro.height_at(p)
	if r.y[i] - ground > HIGH_ENOUGH:
		return ground + HILL_ALLOWANCE
	var top := obstacle_top(p)
	if side > 0.0:
		var j := mini(i + 1, r.xz.size() - 1)
		var k := maxi(i - 1, 0)
		var along: Vector2 = (r.xz[j] - r.xz[k]).normalized()
		var across := Vector2(-along.y, along.x) * side
		top = maxf(top, maxf(obstacle_top(p + across), obstacle_top(p - across)))
	return top


# --- The obstacle field -----------------------------------------------------------------------

## Height of the ground (TRUE world XZ): terrain, relief, never below the sea.
func ground_height(p: Vector2) -> float:
	if macro == null:
		return 0.0
	return maxf(macro.height_at(p), 0.0)


## The tallest thing standing in the 50 m cell around TRUE world `p`: terrain, buildings (the
## plan's own lots and massing heights, plus rooftop plant), freeway decks, landmarks, trees,
## port cranes. Cached per cell, computed on first ask.
func obstacle_top(p: Vector2) -> float:
	var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	var cached: Variant = _cells.get(key)
	if cached != null:
		return cached
	var v := _cell_top(key)
	_cells[key] = v
	return v


func _cell_top(key: Vector2i) -> float:
	var c := (Vector2(key) + Vector2(0.5, 0.5)) * CELL
	var cell := Rect2(Vector2(key) * CELL, Vector2(CELL, CELL))
	var top := 0.0
	for o: Vector2 in [Vector2.ZERO, Vector2(-0.45, -0.45), Vector2(0.45, -0.45), Vector2(-0.45, 0.45), Vector2(0.45, 0.45)]:
		top = maxf(top, macro.height_at(c + o * CELL))
	match macro.zone_at(c):
		MacroMap.Zone.HILLS:
			top += HILL_ALLOWANCE
		MacroMap.Zone.PORT:
			top += PORT_ALLOWANCE
		MacroMap.Zone.CITY:
			top = maxf(top + STREET_ALLOWANCE, _lots_top(cell))
	if macro.freeway:
		# segments_in() hands back everything in the freeway's own 160 m index cells; only a
		# deck that actually passes over this cell counts.
		var reach := CELL * 0.71
		for seg in macro.freeway.segments_in(cell):
			var a: Vector2 = seg.a
			var b: Vector2 = seg.b
			var ab := b - a
			var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			if (a + ab * t).distance_to(c) < reach + float(seg.width) * 0.5:
				top = maxf(top, lerpf(float(seg.ha), float(seg.hb), t) + 9.0)
	for lm: Array in _landmark_boxes:
		if (lm[0] as Rect2).intersects(cell):
			top = maxf(top, float(lm[1]))
	return top


func _lots_top(cell: Rect2) -> float:
	var k := plan.block_index_at(cell.get_center())
	var top := 0.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for lot: Array in _lots(k.x + dx, k.y + dz):
				if (lot[0] as Rect2).intersects(cell):
					top = maxf(top, float(lot[1]))
	return top


## Every lot of a block as [rect, roof height], from the plan the chunks build from.
func _lots(ix: int, iz: int) -> Array:
	var key := Vector2i(ix, iz)
	if _block_lots.has(key):
		return _block_lots[key]
	var out: Array = []
	var b := plan.block(ix, iz)
	var rect: Rect2 = b.rect
	if macro.zone_at(rect.get_center()) == MacroMap.Zone.CITY:
		for lot in plan.lots(ix, iz):
			var centre: Vector2 = lot.center
			var size: Vector2 = lot.size
			var h := plan.lot_height(int(lot.seed), int(b.district), macro.skyline_boost(centre))
			out.append([Rect2(centre - size * 0.5, size), macro.height_at(centre) + h + ROOF_ALLOWANCE])
	_block_lots[key] = out
	return out


# --- Environment ------------------------------------------------------------------------------

## 0 by day, 1 at night (and in a storm), as the street lamps see it.
func lamp_level() -> float:
	return _lamp


## Searchlight shafts come from volumetric fog where there is any (Forward+ with fog on).
func volumetric_searchlight() -> bool:
	return _volumetric


func _poll() -> void:
	if _day:
		var nf: float = _day.get("night_factor")
		var wd: float = _day.get("weather_darken")
		_lamp = maxf(nf, wd * 0.85)
	_volumetric = _env != null and _env.volumetric_fog_enabled and RenderingServer.get_rendering_device() != null and not OS.has_feature("web")
	stars = forced_stars if forced_stars >= 0 else _read_stars()
	# Explosions since the last poll (Explosion counts them and remembers the last one).
	var blasts := Explosion.blast_count
	if blasts != _seen_blasts:
		var at := Explosion.last_blast_world
		_seen_blasts = blasts
		if _player and at.distance_to(player_world()) < news_interest_radius:
			news_heat = minf(news_heat + 1.0, 4.0)
			news_focus = at
	if stars >= news_follow_stars and _player:
		news_heat = maxf(news_heat, 0.5)
		news_focus = player_world()
	_report_sightings()


## A police helicopter whose searchlight holds the player (a clear line, the beam on him) is a
## unit that can see him: the wanted system hears it (Police.report_sighting()), so the stars
## do not start to drop while the helicopter has him.
func _report_sightings() -> void:
	if stars <= 0 or _player == null:
		return
	var p := player_world()
	for h in helicopters(Helicopter.Role.POLICE):
		if h.task == "pursuit" and h.has_eyes_on(p + Vector3.UP * 1.2):
			sightings += 1
			for n in get_tree().get_nodes_in_group("wanted"):
				if n.has_method("report_sighting"):
					n.report_sighting(p)
			return


## The most stars any node in the "wanted" group reports, 0 without a wanted system.
func _read_stars() -> int:
	var best := 0
	for n in get_tree().get_nodes_in_group("wanted"):
		var v: Variant = n.get("stars")
		if v is int or v is float:
			best = maxi(best, int(v))
	return best


func player_world() -> Vector3:
	return WorldState.to_world(_player.global_position) if _player else Vector3.ZERO


# --- The schedule -----------------------------------------------------------------------------

func crafts() -> Array[AmbientCraft]:
	var live: Array[AmbientCraft] = []
	for c in _crafts:
		if is_instance_valid(c) and not c.done:
			live.append(c)
	_crafts = live
	return live


func jets(plan_kind: int = -1) -> Array[AmbientJet]:
	var out: Array[AmbientJet] = []
	for c in crafts():
		if c is AmbientJet and (plan_kind < 0 or (c as AmbientJet).plan == plan_kind) and c.life == AmbientCraft.Life.FLYING:
			out.append(c as AmbientJet)
	return out


func helicopters(role: int = -1) -> Array[Helicopter]:
	var out: Array[Helicopter] = []
	for c in crafts():
		if c is Helicopter and (role < 0 or (c as Helicopter).role == role) and c.life == AmbientCraft.Life.FLYING:
			out.append(c as Helicopter)
	return out


func _room() -> bool:
	return crafts().size() < max_aircraft


func _schedule(dt: float) -> void:
	_arrival_timer -= dt
	_departure_timer -= dt
	_private_timer -= dt
	if _arrival_timer <= 0.0:
		_arrival_timer = arrival_interval + _rng.randf_range(-interval_jitter, interval_jitter)
		if _room() and _count_jets(AmbientJet.Plan.ARRIVAL) < max_arrivals:
			var k := Aircraft.Kind.PRIVATE if _rng.randf() < private_share else Aircraft.Kind.AIRLINER
			spawn_arrival(k, -1.0, "arrival_south" if _rng.randf() < 0.6 else "arrival_southwest")
	if _departure_timer <= 0.0:
		if _room() and _count_jets(AmbientJet.Plan.DEPARTURE) < max_departures:
			if _lineup_hidden():
				_departure_timer = departure_interval + _rng.randf_range(-interval_jitter, interval_jitter)
				var k := Aircraft.Kind.PRIVATE if _rng.randf() < private_share else Aircraft.Kind.AIRLINER
				spawn_departure(k, 0.0, _rng.randf() < 0.5)
			else:
				# Someone is watching the runway end: it fades in anyway, just not this second.
				_departure_timer = 3.0
		else:
			_departure_timer = departure_interval
	if _private_timer <= 0.0:
		_private_timer = private_interval + _rng.randf_range(-interval_jitter, interval_jitter)
		if _room() and _count_private() < max_private:
			var rng := RandomNumberGenerator.new()
			rng.seed = _rng.randi()
			if rng.randf() < private_landing_share:
				_add_jet(Aircraft.Kind.PRIVATE, AmbientJet.Plan.ARRIVAL, _private_arrival_route(rng), 0.0)
			else:
				_add_jet(Aircraft.Kind.PRIVATE, AmbientJet.Plan.CROSSING, _crossing_route(rng), 0.0)


func _count_jets(p: int) -> int:
	var n := 0
	for c in crafts():
		if c is AmbientJet and (c as AmbientJet).plan == p:
			n += 1
	return n


func _count_private() -> int:
	var n := 0
	for c in crafts():
		if c is AmbientJet and (c as AmbientJet).kind == Aircraft.Kind.PRIVATE:
			n += 1
	return n


## True when nobody could watch a departure appear at the line-up point (off screen or far).
func _lineup_hidden() -> bool:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return true
	var r: AirRoute = routes["departure_%d_left" % Aircraft.Kind.AIRLINER]
	var at := WorldState.to_local(r.sample(0.0).pos)
	return cam.global_position.distance_to(at) > 1500.0 or not cam.is_position_in_frustum(at)


## The sky at load: something already on final, something already climbing, the news over
## downtown and the police patrol, so the first minute is not empty.
func _populate() -> void:
	spawn_arrival(Aircraft.Kind.AIRLINER, 3200.0, "arrival_south")
	spawn_departure(Aircraft.Kind.AIRLINER, float(routes["departure_%d_right" % Aircraft.Kind.AIRLINER].marks.liftoff) + 1100.0, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var crossing := _crossing_route(rng)
	_add_jet(Aircraft.Kind.PRIVATE, AmbientJet.Plan.CROSSING, crossing, crossing.length * 0.35)
	var dc := macro.downtown_center
	spawn_helicopter(Helicopter.Role.NEWS, Vector3(dc.x + 500.0, 300.0, dc.y + 300.0), "cruise")
	if police_patrol:
		var p := player_world()
		spawn_helicopter(Helicopter.Role.POLICE, p + Vector3(900.0, 0.0, -700.0) + Vector3.UP * (ground_height(Vector2(p.x, p.z)) + patrol_height), "patrol")
	_arrival_timer = arrival_interval * 0.55
	_departure_timer = departure_interval * 0.35
	_private_timer = private_interval * 0.6


## An arrival `s` metres from touchdown (-1: from the start of the route).
func spawn_arrival(kind: Aircraft.Kind, s: float = -1.0, route_name: String = "arrival_south") -> AmbientJet:
	var r: AirRoute = routes[route_name]
	var aim: float = r.marks.aim
	var d := 0.0 if s < 0.0 else clampf(aim - s, 0.0, r.length)
	return _add_jet(kind, AmbientJet.Plan.ARRIVAL, r, d)


## A departure `d` metres along its route (0: lined up, fading in).
func spawn_departure(kind: Aircraft.Kind, d: float = 0.0, left: bool = true) -> AmbientJet:
	return _add_jet(kind, AmbientJet.Plan.DEPARTURE, routes["departure_%d_%s" % [kind, "left" if left else "right"]], d)


func _add_jet(kind: Aircraft.Kind, p: AmbientJet.Plan, r: AirRoute, d: float) -> AmbientJet:
	var jet := AmbientJet.new()
	_serial += 1
	jet.name = "Jet%d" % _serial
	jet.traffic = self
	jet.setup(kind, p, r, d, _rng.randi())
	_place_before_entry(jet)
	add_child(jet)
	_crafts.append(jet)
	return jet


func spawn_helicopter(role: Helicopter.Role, at_world: Vector3, task: String) -> Helicopter:
	var heli := Helicopter.new()
	_serial += 1
	heli.name = ("Police%d" if role == Helicopter.Role.POLICE else "News%d") % _serial
	heli.traffic = self
	heli.setup(role, at_world, _rng.randf() * TAU, _rng.randi())
	heli.task = task
	_place_before_entry(heli)
	add_child(heli)
	_crafts.append(heli)
	return heli


## Puts a new aircraft where it belongs BEFORE it enters the tree. Godot works out a kinematic
## body's velocity from how far it moved in a step, so a body that entered at the origin and
## was then put two kilometres away moved at a hundred kilometres a second for one step - and
## a player standing at the origin inherited that as platform velocity and left the map.
func _place_before_entry(craft: AmbientCraft) -> void:
	craft.transform = Transform3D(Basis.from_euler(Vector3(craft.pitch, craft.yaw, craft.roll)), to_local(WorldState.to_local(craft.world_pos)))


## Somewhere a helicopter can come from without popping into view: `spawn_distance` behind the
## camera, high enough to clear what is there.
func far_spawn_point() -> Vector3:
	var p := player_world()
	var back := Vector3(0.0, 0.0, 1.0)
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam:
		var f := -cam.global_basis.z
		f.y = 0.0
		if f.length() > 0.1:
			back = -f.normalized()
	back = back.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
	var at := p + back * spawn_distance
	var xz := Vector2(at.x, at.z)
	at.y = maxf(obstacle_top(xz) + 80.0, ground_height(xz) + 220.0)
	return at


func on_craft_down(craft: AmbientCraft) -> void:
	if craft is Helicopter:
		if (craft as Helicopter).role == Helicopter.Role.NEWS:
			_news_respawn_left = news_respawn
		else:
			_police_respawn_left = police_respawn
			_patrol_left = maxf(_patrol_left, police_respawn * 2.0)


func on_craft_crashed(_craft: AmbientCraft) -> void:
	pass


# --- Helicopter orders ------------------------------------------------------------------------

func _order_news() -> void:
	var news := helicopters(Helicopter.Role.NEWS)
	var covering := news_heat > 0.0 and news_focus != Vector3.INF
	var want := 2 if covering and news_heat >= 3.0 else 1
	if news.size() < want and _news_respawn_left <= 0.0 and _room():
		news.append(spawn_helicopter(Helicopter.Role.NEWS, far_spawn_point(), "cover" if covering else "cruise"))
		_news_respawn_left = 6.0
	for i in news.size():
		var h: Helicopter = news[i]
		if covering:
			h.task = "cover"
			h.mode = Helicopter.Mode.ORBIT
			h.orbit_centre = Vector3(news_focus.x, ground_height(Vector2(news_focus.x, news_focus.z)), news_focus.z)
			h.orbit_radius = news_orbit_radius * (1.0 + 0.35 * i)
			h.orbit_height = news_orbit_height + 40.0 * i
			h.orbit_dir = 1.0 if i == 0 else -1.0
			h.look_target = news_focus
		else:
			if h.task != "cruise" or h.mode == Helicopter.Mode.HOVER:
				h.task = "cruise"
				h.mode = Helicopter.Mode.GOTO
				h.goal = _cruise_point()
			h.look_target = Vector3.INF


func _cruise_point() -> Vector3:
	var dc := macro.downtown_center
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * news_cruise_radius
	var xz := dc + Vector2(cos(a), sin(a)) * r
	return Vector3(xz.x, maxf(obstacle_top(xz) + 70.0, ground_height(xz) + news_cruise_height), xz.y)


func _order_police(dt: float) -> void:
	var police := helicopters(Helicopter.Role.POLICE)
	var p := player_world()
	var want := 0
	if stars >= police_stars:
		want = 1 if stars == police_stars else 2
	var pursuers: Array[Helicopter] = []
	for h in police:
		if h.task == "pursuit":
			pursuers.append(h)
	if want > 0:
		# The patrol answers first.
		for h in police:
			if pursuers.size() >= want:
				break
			if h.task == "patrol":
				h.task = "pursuit"
				pursuers.append(h)
		if pursuers.size() < want and _police_respawn_left <= 0.0:
			pursuers.append(spawn_helicopter(Helicopter.Role.POLICE, far_spawn_point(), "pursuit"))
			_police_respawn_left = 6.0
	var ground := ground_height(Vector2(p.x, p.z))
	_look_timer += dt
	for i in pursuers.size():
		var h := pursuers[i]
		if want == 0:
			h.task = "leaving"
			continue
		h.mode = Helicopter.Mode.ORBIT
		h.orbit_radius = police_orbit_radius.x if i == 0 else police_orbit_radius.y
		h.orbit_dir = 1.0 if i == 0 else -1.0
		# Over the player even when he is in the air.
		h.orbit_centre = Vector3(p.x, maxf(ground, p.y - police_orbit_height * 0.5), p.z)
		h.orbit_height = police_orbit_height
		# The beam hunts round him a little instead of sitting dead on him.
		var wobble := Vector3(sin(_look_timer * 0.9 + i * 2.0), 0.0, cos(_look_timer * 1.3 + i)) * 2.5
		h.look_target = p + wobble
		h.searchlight_on = true
	for h in police:
		if h.task == "leaving":
			if h.mode != Helicopter.Mode.LEAVE:
				h.mode = Helicopter.Mode.LEAVE
				var away := Vector3(h.world_pos.x - p.x, 0.0, h.world_pos.z - p.z)
				h.leave_dir = away.normalized() if away.length() > 1.0 else Vector3.FORWARD
				h.searchlight_on = false
				h.look_target = Vector3.INF
			if Vector2(h.world_pos.x - p.x, h.world_pos.z - p.z).length() > police_leave_distance:
				h.remove()
		elif h.task == "patrol":
			_order_patrol(h, p)
	# Nobody patrolling (no stars): send one out again after a while.
	if want == 0 and police_patrol and _patrol_left <= 0.0 and _room():
		var patrolling := false
		for h in police:
			if h.task == "patrol":
				patrolling = true
		if not patrolling:
			spawn_helicopter(Helicopter.Role.POLICE, far_spawn_point(), "patrol")
			_patrol_left = 45.0


func _order_patrol(h: Helicopter, p: Vector3) -> void:
	if h.mode != Helicopter.Mode.GOTO or Vector2(h.goal.x - h.world_pos.x, h.goal.z - h.world_pos.z).length() < 40.0:
		var a := _rng.randf() * TAU
		var xz := Vector2(p.x, p.z) + Vector2(cos(a), sin(a)) * _rng.randf_range(450.0, 1100.0)
		h.mode = Helicopter.Mode.GOTO
		h.goal = Vector3(xz.x, maxf(obstacle_top(xz) + 60.0, ground_height(xz) + patrol_height), xz.y)
	# At night the beam sweeps the streets below and ahead.
	h.searchlight_on = true
	var ahead := h.world_pos + AmbientCraft.yaw_dir(h.yaw) * 90.0
	var sweep := Vector3(cos(h.yaw), 0.0, -sin(h.yaw)) * sin(_look_timer * 0.35) * 70.0
	var target := ahead + sweep
	target.y = ground_height(Vector2(target.x, target.z))
	h.look_target = target


# --- Stills and tests -------------------------------------------------------------------------

## Stages an aircraft for a screenshot in front of `cam`: "final" (an airliner on short final,
## the point of the approach nearest `dist` metres ahead of the camera and `side` to its right), "takeoff" (a departure
## `dist` metres past lift-off), "news" (the news helicopter `dist` ahead, filming the camera's
## target) or "police" (police circling the player, searchlight on). Returns what it placed.
func stage(kind: String, cam: Camera3D, dist: float, side: float = 0.0) -> AmbientCraft:
	if not _ready_done and not _setup():
		return null
	var eye := WorldState.to_world(cam.global_position)
	var fwd := -cam.global_basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	# `side` metres to the right of the view, so the player is not standing in front of it.
	var spot := eye + flat * dist + Vector3(-flat.z, 0.0, flat.x) * side
	match kind:
		"final":
			var r: AirRoute = routes["arrival_south"]
			var aim: float = r.marks.aim
			var best := aim - 400.0
			var best_d2 := INF
			var d := aim - 3500.0
			while d < aim:
				var q := r.sample(d).pos as Vector3
				var d2 := Vector2(q.x - spot.x, q.z - spot.z).length_squared()
				if d2 < best_d2:
					best_d2 = d2
					best = d
				d += 10.0
			return spawn_arrival(Aircraft.Kind.AIRLINER, aim - best, "arrival_south")
		"takeoff":
			var name := "departure_%d_left" % Aircraft.Kind.AIRLINER
			return spawn_departure(Aircraft.Kind.AIRLINER, float(routes[name].marks.liftoff) + dist, true)
		"news":
			var at := spot + Vector3.UP * maxf(dist * 0.35, 25.0)
			var h := spawn_helicopter(Helicopter.Role.NEWS, at, "cover")
			h.mode = Helicopter.Mode.HOVER
			h.goal = at
			h.look_target = eye
			h.yaw = AmbientCraft.yaw_of(Vector3(-fwd.z, 0.0, fwd.x))
			h.apply_pose()
			h.snap_gear()
			return h
		"police":
			forced_stars = police_stars
			var at := spot + Vector3.UP * police_orbit_height
			var h := spawn_helicopter(Helicopter.Role.POLICE, at, "pursuit")
			h.yaw = AmbientCraft.yaw_of(Vector3(-fwd.z, 0.0, fwd.x))
			h.searchlight_on = true
			h.look_target = player_world()
			_poll()
			h.apply_pose()
			h.snap_gear()
			return h
	return null


## Clears the sky (tests, stills).
func clear_all() -> void:
	for c in crafts():
		c.remove()
	_crafts.clear()
