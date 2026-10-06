class_name NewsCrews
extends Node3D
## TV news at big scenes (fleet wave 2, "news crews"). One node in the city scene, in the group
## "news_crews", dispatched like Emergency: it watches for a STORY, sends a station's live truck
## (NewsVan) through the streets, and the van pulls up double-parked down the street from the
## scene. Its uplink goes up (a satellite dish or a telescoping microwave mast), the crew gets
## out (NewsCrew: a reporter with the station's mic and a camera operator with a shoulder
## camera), a light goes up on a stand, and the reporter talks to camera with the scene behind
## them, behind the caution tape strung across the pavement - outside the onlookers' ring
## (they stand 4-17 m off a scene; the tape is ~`report_distance` - 4 m out). After `air_seconds`
## the crew wraps: back in the van, the uplink down, off; nobody seeing it, it goes back into the
## pool. The news helicopter AirTraffic already sends joins the same story (news_focus).
##
## Stories, looked for every `scan_interval` within `call_radius` of the player:
##   blast     a blast (Explosion.blast_count) - a rocket, a car going up - after `blast_delay`.
##   standoff  the police on the player (`standoff_stars`) for `standoff_seconds` while he stays
##             within `standoff_radius` of one spot: the van keeps its distance, the reporter
##             talks while it lasts.
## Caps `max_vans` (a station each, never the same station twice at once); stories closer than
## `merge_radius` are one story; a new story waits `story_gap` after the last.
##
## Coordinates: story positions are TRUE world (WorldState); vans, crews and props are ordinary
## nodes under this one with scene positions. The layout (`layout()`) is pure: true world XZ in,
## kerb stop, spots and tape out.
## NEWS_CREWS=0 in the environment turns it all off (the A/B).

@export var enabled: bool = true
@export_group("Stories")
@export var scan_interval: float = 1.0
@export var call_radius: float = 420.0
## Seconds from a blast to a van being sent (the assignment desk has to hear of it).
@export var blast_delay: float = 12.0
@export var merge_radius: float = 70.0
@export var story_gap: float = 30.0
## The police standoff that makes the news.
@export var standoff_stars: int = 2
@export var standoff_seconds: float = 40.0
@export var standoff_radius: float = 90.0
## How long the crew stays on air (s, a range), then wraps.
@export var air_seconds: Vector2 = Vector2(80.0, 140.0)
@export_group("Layout")
## The reporter stands about this far from the scene (m), the van further back down the kerb.
@export var report_distance: float = 25.0
@export var standoff_report_distance: float = 62.0
@export var camera_back: float = 3.4
@export var van_back: float = 9.5
@export_group("Response")
@export var max_vans: int = 2
@export var spawn_min: float = 170.0
@export var spawn_max: float = 250.0
@export var despawn_distance: float = 420.0
@export var pool_size: int = 2
@export var web_scale: float = 0.5
## The stand light thrown on the reporter after dark (desktop only).
@export var light_energy: float = 3.2
@export var light_range: float = 14.0

const KIND_BLAST := "blast"
const KIND_STANDOFF := "standoff"
## Where the microwave masts send their pictures (true world XZ offset from downtown's centre):
## a receive site on the towers.
const RECEIVE_OFFSET := Vector2(-120.0, -60.0)

var stories: Array[Dictionary] = []
var vans: Array[NewsVan] = []
var crews: Array[NewsCrew] = []
var plan: CityPlan
var traffic: TrafficManager
## Vans sent since the start (tests read it).
var dispatched: int = 0
## Running back to the van (a wrap under fire).
var hurry: bool = false

var _player: Node3D
var _pool: Array[NewsVan] = []
var _rng := RandomNumberGenerator.new()
var _scan_t: float = 0.0
var _upkeep_t: float = 0.0
var _blasts_seen: int = 0
var _next_id: int = 1
var _last_story_t: float = -1e9
var _standoff_anchor := Vector3.INF
var _standoff_t: float = 0.0
var _day: Node


static func find(tree: SceneTree) -> NewsCrews:
	if tree == null:
		return null
	return tree.get_first_node_in_group("news_crews") as NewsCrews


func _ready() -> void:
	add_to_group("news_crews")
	if OS.get_environment("NEWS_CREWS") == "0":
		enabled = false
	_rng.seed = hash(["news", Time.get_ticks_usec()])
	_blasts_seen = Explosion.blast_count
	if OS.has_feature("web"):
		max_vans = maxi(1, int(round(max_vans * web_scale)))


func _ensure_refs() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var city := get_parent()
	if plan == null and city and city.get("plan") != null:
		plan = city.plan
	if traffic == null and city:
		traffic = city.get_node_or_null("Traffic") as TrafficManager


func _exit_tree() -> void:
	for v in _pool:
		if is_instance_valid(v):
			v.free()
	_pool.clear()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_ensure_refs()
	if _player == null or plan == null:
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = scan_interval
		_scan(scan_interval)
	_upkeep_t -= delta
	if _upkeep_t <= 0.0:
		_upkeep_t = 0.5
		_upkeep(0.5)


# --- Stories ------------------------------------------------------------------------------------

func _scan(step: float) -> void:
	var pp := WorldState.to_world(_player.global_position)
	if Explosion.blast_count != _blasts_seen:
		_blasts_seen = Explosion.blast_count
		var at := Explosion.last_blast_world
		if Vector2(at.x - pp.x, at.z - pp.z).length() < call_radius and _near_story(at) == null:
			var s := _open(KIND_BLAST, at)
			s.send_at = _now() + blast_delay
	# The standoff: stars held round one spot.
	var police := get_tree().get_first_node_in_group("wanted")
	var stars := int(police.get("stars")) if police else 0
	if stars >= standoff_stars:
		if _standoff_anchor == Vector3.INF or Vector2(pp.x - _standoff_anchor.x, pp.z - _standoff_anchor.z).length() > standoff_radius:
			_standoff_anchor = pp
			_standoff_t = 0.0
		_standoff_t += step
		if _standoff_t >= standoff_seconds and _near_story(_standoff_anchor) == null:
			var s2 := _open(KIND_STANDOFF, _standoff_anchor)
			s2.send_at = _now()
	else:
		_standoff_anchor = Vector3.INF
		_standoff_t = 0.0
	_dispatch()


func _open(kind: String, world: Vector3) -> Dictionary:
	var s := {"id": _next_id, "kind": kind, "world": world, "opened": _now(), "send_at": _now(),
		"van": null, "layout": {}, "kerb": {}, "on_air": false, "air_t": 0.0, "air_for": 0.0,
		"wrap": false, "props": []}
	_next_id += 1
	stories.append(s)
	_tell_air(world)
	return s


func _near_story(world: Vector3) -> Variant:
	for s in stories:
		var w: Vector3 = s.world
		if Vector2(w.x - world.x, w.z - world.z).length() < merge_radius:
			return s
	return null


## The news helicopter covers the same story (AirTraffic's own news focus).
func _tell_air(world: Vector3) -> void:
	var air := get_parent().get_node_or_null("AirTraffic") if get_parent() else null
	if air == null or air.get("news_heat") == null:
		return
	air.set("news_heat", maxf(float(air.get("news_heat")), 2.0))
	air.set("news_focus", world)


func _stations_in_use() -> Array:
	var used := []
	for v in vans:
		if is_instance_valid(v):
			used.append(v.station_i)
	return used


func _dispatch() -> void:
	var now := _now()
	for s in stories:
		if s.van != null or bool(s.wrap) or now < float(s.send_at):
			continue
		if now - _last_story_t < story_gap and dispatched > 0:
			continue
		if vans.size() >= max_vans or not PhysicsBudget.make_room(1):
			return
		if send(s) != null:
			_last_story_t = now
			return


## Sends a van to story `s`: lays the scene out, brings it in along a street out of sight.
func send(s: Dictionary) -> NewsVan:
	_ensure_refs()
	var w: Vector3 = s.world
	var lay := layout(plan, Vector2(w.x, w.z), standoff_report_distance if s.kind == KIND_STANDOFF else report_distance)
	if lay.is_empty():
		stories.erase(s)
		return null
	s.layout = lay
	s.kerb = lay.kerb
	var start := _street_start(lay.kerb.stop)
	if start.is_empty():
		return null
	var van := _take()
	van.service = self
	van.story = s
	van.goal = lay.kerb.stop
	van.begin_drive(plan, start[0], start[1], start[2], van.drive_speed * 0.8)
	_aim(van)
	var p: Vector2 = start[3]
	var lane: float = van.traffic.lane
	if int(start[0]) == CityPlan.AXIS_X:
		p.x += lane
	else:
		p.y += lane
	var h := traffic._relief(p) if traffic else (plan.macro.relief_at(p) if plan.macro else 0.0)
	_enter_at(van, Transform3D(Basis(Vector3.UP, NewsVan.heading(start[0], start[2])),
			WorldState.to_local(Vector3(p.x, h + CityChunk.ROAD_TOP + van.road_lift(), p.y))))
	vans.append(van)
	s.van = van
	dispatched += 1
	return van


func _aim(van: NewsVan) -> void:
	if van.uplink() == "mast" and plan.macro:
		var c: Vector2 = plan.macro.downtown_center + RECEIVE_OFFSET
		van.aim_world = Vector3(c.x, 0.0, c.y)
	else:
		van.aim_world = Vector3.INF


## The live shot laid out round scene `scene` (true world XZ), the reporter about `reach` metres
## off it: the nearest street's kerb on the scene's side (StreetRoute.kerb_stop), the reporter on
## its pavement down the street from the scene, the camera `camera_back` further on facing them
## (so the scene is behind the reporter in the shot), the light stand beside the camera, the van
## pulled up `van_back` beyond, and the tape across the pavement between the reporter and the
## scene with a leg along the kerb toward it. Tries both ways along the street; {} when neither
## fits between the crossings. Pure.
func layout(p: CityPlan, scene: Vector2, reach: float) -> Dictionary:
	var k0 := StreetRoute.kerb_stop(p, scene, 0.0)
	if k0.is_empty():
		return {}
	var axis := int(k0.axis)
	var index := int(k0.index)
	var road := p.road_pos(axis, index)
	var width := p.road_width(axis, index)
	var side := signf(float(k0.lateral)) if float(k0.lateral) != 0.0 else 1.0
	var s_along := scene.y if axis == CityPlan.AXIS_X else scene.x
	var s_across := scene.x if axis == CityPlan.AXIS_X else scene.y
	var pav := road + side * (width * 0.5 + 1.7)
	var kerb_line := road + side * (width * 0.5 + 0.35)
	var wall_line := road + side * (width * 0.5 + p.sidewalk_width - 0.45)
	var cross_axis := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var j := p._index_at(cross_axis, s_along)
	var lo := p.road_pos(cross_axis, j) + p.road_width(cross_axis, j) * 0.5 + 3.0
	var hi := p.road_pos(cross_axis, j + 1) - p.road_width(cross_axis, j + 1) * 0.5 - 3.0
	var dc := absf(pav - s_across)
	var to_xz := func(al: float, ac: float) -> Vector2:
		return Vector2(ac, al) if axis == CityPlan.AXIS_X else Vector2(al, ac)
	for attempt in 4:
		var r := reach * (1.0 if attempt < 2 else 0.8)
		var sgn := (-1.0 if attempt % 2 == 0 else 1.0) * float(k0.dir)
		var r_along := sqrt(maxf(r * r - dc * dc, 16.0))
		var a_rep := s_along + sgn * r_along
		var a_cam := a_rep + sgn * camera_back
		var a_van := a_cam + sgn * van_back
		var a_tape := a_rep - sgn * 4.0
		if minf(minf(a_rep, a_cam), a_tape) < lo or maxf(maxf(a_rep, a_cam), a_tape) > hi:
			continue
		# The van may stand past the crossing's clearance: kerb_stop clamps it back.
		var van_goal: Vector2 = to_xz.call(clampf(a_van, lo, hi), road + side * (width * 0.5 - 2.0))
		var kerb := StreetRoute.kerb_stop(p, van_goal, 0.0)
		if kerb.is_empty() or int(kerb.axis) != axis or int(kerb.index) != index:
			continue
		var tape: Array[Vector2] = [to_xz.call(a_tape, wall_line), to_xz.call(a_tape, (wall_line + kerb_line) * 0.5),
			to_xz.call(a_tape, kerb_line), to_xz.call(a_tape - sgn * 3.2, kerb_line), to_xz.call(a_tape - sgn * 6.4, kerb_line)]
		return {"kerb": kerb, "axis": axis, "index": index, "side": side, "sgn": sgn,
			"reporter": to_xz.call(a_rep, pav), "camera": to_xz.call(a_cam, pav + side * 0.25),
			"light": to_xz.call(a_cam - sgn * 0.9, pav + side * 1.35), "tape": tape, "scene": scene}
	return {}


## A street `spawn_min`..`spawn_max` from `goal`, out of the camera's view where it can be:
## [axis, index, dir, point (true world XZ)], or [] (Emergency._street_start()).
func _street_start(goal: Vector2) -> Array:
	if plan.zone_at(goal) != MacroMap.Zone.CITY and plan.zone_at(goal) != MacroMap.Zone.BEACH:
		return []
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var center := plan.block_index_at(goal)
	for attempt in 14:
		var axis := _rng.randi_range(0, 1)
		var index := (center.x if axis == CityPlan.AXIS_X else center.y) + _rng.randi_range(-2, 2)
		var along0 := goal.y if axis == CityPlan.AXIS_X else goal.x
		var along := along0 + (-1.0 if _rng.randf() < 0.5 else 1.0) * _rng.randf_range(spawn_min, spawn_max)
		var road := plan.road_pos(axis, index)
		var p2 := Vector2(road, along) if axis == CityPlan.AXIS_X else Vector2(along, road)
		if plan.zone_at(p2) != MacroMap.Zone.CITY or not plan.road_open(axis, index, along):
			continue
		var local := WorldState.to_local(Vector3(p2.x, 0.0, p2.y))
		if attempt < 9 and cam and cam.is_position_in_frustum(local) and cam.global_position.distance_to(local) < 420.0:
			continue
		return [axis, index, 1 if along0 > along else -1, p2]
	return []


func _take() -> NewsVan:
	var used := _stations_in_use()
	var free_stations: Array = []
	for i in NewsKit.STATIONS.size():
		if not used.has(i):
			free_stations.append(i)
	for i in range(_pool.size() - 1, -1, -1):
		var v: NewsVan = _pool[i]
		if not is_instance_valid(v):
			_pool.remove_at(i)
			continue
		if free_stations.has(v.station_i):
			_pool.remove_at(i)
			return v
	var pick: int = free_stations[_rng.randi() % free_stations.size()] if not free_stations.is_empty() else _rng.randi() % NewsKit.STATIONS.size()
	return NewsVan.make(pick, _rng)


func _enter_at(van: NewsVan, xf: Transform3D) -> void:
	if van.get_parent() == null:
		van.transform = global_transform.affine_inverse() * xf
		add_child(van)
	else:
		van.global_transform = xf


# --- On scene ------------------------------------------------------------------------------------

## The van pulled up: the crew gets out, the light and the tape go up.
func van_arrived(van: NewsVan) -> void:
	var s := van.story
	if s.is_empty() or s.layout.is_empty():
		van.leave(_away_point(van))
		return
	deploy_crew(van)
	_build_props(s, van)


func deploy_crew(van: NewsVan) -> void:
	var lay: Dictionary = van.story.layout
	for i in van.crew_aboard:
		var c := NewsCrew.new()
		var role := NewsCrew.Role.REPORTER if i == 0 else NewsCrew.Role.CAMERA
		c.setup_crew(self, van, role, hash([van.story.id, i, van.station_i]))
		add_child(c)
		c.global_position = _on_surface(_door_spot(van, i))
		var rep := _ground(lay.reporter)
		var cam := _ground(lay.camera)
		if role == NewsCrew.Role.REPORTER:
			c.spot = rep
			c.face_at = cam
		else:
			c.spot = cam
			c.face_at = rep
		crews.append(c)
	van.crew_aboard = 0


func _door_spot(van: NewsVan, i: int) -> Vector3:
	var base := van.global_position - Vector3.UP * van.road_lift()
	var side := van.global_basis.x.slide(Vector3.UP).normalized()
	var fwd := (-van.global_basis.z).slide(Vector3.UP).normalized()
	var half := float(van._dims().width) * 0.5 + 0.6
	var length := float(van._dims().length)
	return base + side * half + fwd * length * (0.25 if i == 0 else -0.05) + Vector3.UP * 0.05


## A true world XZ point on the surface under it, as a scene position.
func _ground(xz: Vector2) -> Vector3:
	var h := plan.height_at(xz) + CityChunk.SIDEWALK_TOP
	return _on_surface(WorldState.to_local(Vector3(xz.x, h, xz.y)))


## `p` brought down (or up) onto the world-layer surface under it (Emergency._on_surface).
func _on_surface(p: Vector3) -> Vector3:
	if not is_inside_tree():
		return p
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p - Vector3.UP * 3.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


## The light on its stand aimed at the reporter, the tape on its posts, the camera's cable back to
## the van: children of a holder node that goes when the story does.
func _build_props(s: Dictionary, van: NewsVan) -> void:
	var lay: Dictionary = s.layout
	var holder := Node3D.new()
	holder.name = "NewsScene%d" % int(s.id)
	add_child(holder)
	s.props = [holder]
	var rep := _ground(lay.reporter)
	var stand_at := _ground(lay.light)
	var stand := MeshInstance3D.new()
	stand.name = "LightStand"
	stand.mesh = NewsKit.light_stand_mesh()
	stand.visibility_range_end = 160.0
	holder.add_child(stand)
	stand.global_position = stand_at
	var to := rep - stand_at
	stand.rotation.y = atan2(-to.x, -to.z)
	if not OS.has_feature("web"):
		var spot := SpotLight3D.new()
		spot.name = "StandLight"
		spot.light_color = Color(1.0, 0.94, 0.86)
		spot.spot_range = light_range
		spot.spot_angle = 32.0
		spot.spot_angle_attenuation = 0.8
		spot.shadow_enabled = false
		spot.distance_fade_enabled = true
		spot.distance_fade_begin = 80.0
		spot.distance_fade_length = 30.0
		spot.position = Vector3(0.0, 2.1, -0.05)
		stand.add_child(spot)
		var head := rep + Vector3.UP * 1.5
		var from := stand_at + Vector3.UP * 2.1
		spot.rotation.x = atan2(head.y - from.y, Vector2(head.x - from.x, head.z - from.z).length())
		s.spot = spot
	# Tape posts and the tape between them.
	var tops: Array[Vector3] = []
	for xz: Vector2 in lay.tape:
		var g := _ground(xz)
		var post := MeshInstance3D.new()
		post.name = "TapePost"
		post.mesh = NewsKit.post_mesh()
		post.visibility_range_end = 140.0
		holder.add_child(post)
		post.global_position = g
		tops.append(g + Vector3.UP * NewsKit.TAPE_Y)
	var tape := MeshInstance3D.new()
	tape.name = "Tape"
	tape.mesh = NewsKit.tape_mesh(tops)
	tape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tape.visibility_range_end = 120.0
	holder.add_child(tape)
	# The camera's cable along the pavement back to the van's side door.
	var cam := _ground(lay.camera)
	var door := _on_surface(_door_spot(van, 1))
	var pts: Array[Vector3] = []
	for k in 6:
		var t := float(k) / 5.0
		var q := door.lerp(cam, t) + (van.global_basis.x.slide(Vector3.UP).normalized() * sin(t * PI) * 0.6)
		pts.append(_on_surface(q) + Vector3.UP * 0.012)
	var cable := MeshInstance3D.new()
	cable.name = "Cable"
	cable.mesh = EmergencyCrew.tube_mesh(pts, 0.009, 5)
	cable.mesh.surface_set_material(0, PropFactory.material(Color(0.03, 0.03, 0.035), 0.6))
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cable.visibility_range_end = 60.0
	holder.add_child(cable)


func _night_level() -> float:
	if _day == null or not is_instance_valid(_day):
		var scene := get_tree().current_scene
		_day = scene.get_node_or_null("DayNight") if scene else null
	if _day == null:
		return 0.0
	return maxf(float(_day.get("night_factor")), float(_day.get("weather_darken")) * 0.85)


## A crew member back in the van. With everyone in, it leaves.
func board(c: NewsCrew, van: NewsVan) -> void:
	crews.erase(c)
	c.queue_free()
	if not is_instance_valid(van):
		return
	van.crew_aboard += 1
	if van.crew_aboard >= van.crew_alive:
		_finish(van)


func crew_down(c: NewsCrew) -> void:
	crews.erase(c)
	if is_instance_valid(c.van):
		c.van.crew_alive = maxi(c.van.crew_alive - 1, 0)
		# The story is over: the rest pack up in a hurry.
		if not c.van.story.is_empty():
			c.van.story.wrap = true
			hurry = true
		if c.van.crew_alive > 0 and c.van.crew_aboard >= c.van.crew_alive:
			_finish(c.van)


func van_stolen(van: NewsVan) -> void:
	vans.erase(van)
	for c in crews:
		if is_instance_valid(c) and c.van == van:
			c.van = null
	if not van.story.is_empty():
		_close(van.story)
	van.story = {}


func _finish(van: NewsVan) -> void:
	if not van.story.is_empty():
		_close(van.story)
	van.story = {}
	van.leave(_away_point(van))


func _close(s: Dictionary) -> void:
	for n in s.get("props", []):
		if is_instance_valid(n):
			(n as Node).queue_free()
	s.props = []
	stories.erase(s)


func _away_point(van: NewsVan) -> Vector2:
	var wp := WorldState.to_world(van.global_position)
	var a := _rng.randf() * TAU
	return Vector2(wp.x, wp.z) + Vector2(cos(a), sin(a)) * 500.0


# --- Upkeep --------------------------------------------------------------------------------------

func _upkeep(step: float) -> void:
	var pp := _player.global_position
	var cam := get_viewport().get_camera_3d()
	var night := _night_level()
	var police := get_tree().get_first_node_in_group("wanted")
	var stars := int(police.get("stars")) if police else 0
	for s in stories.duplicate():
		var w := WorldState.to_local(s.world)
		var van: NewsVan = s.van if is_instance_valid(s.van) else null
		if van == null and s.van != null:
			s.van = null
		if w.distance_to(pp) > despawn_distance and van == null:
			_close(s)
			continue
		if van == null:
			continue
		# On air once both are in place and the uplink is up.
		if not bool(s.on_air) and van.mode == NewsVan.Mode.ON_SCENE and van.gear_up() and _crew_in_place(van):
			s.on_air = true
			s.air_t = 0.0
			s.air_for = _rng.randf_range(air_seconds.x, air_seconds.y)
		if bool(s.on_air):
			s.air_t = float(s.air_t) + step
			var held: bool = s.kind == KIND_STANDOFF and stars >= standoff_stars
			if float(s.air_t) > float(s.air_for) and not held:
				s.wrap = true
		if w.distance_to(pp) > despawn_distance:
			s.wrap = true
		var spot: SpotLight3D = s.get("spot", null)
		if spot and is_instance_valid(spot):
			spot.visible = night > 0.05 and bool(s.on_air)
			spot.light_energy = light_energy * clampf(night * 1.4, 0.0, 1.0)
	NewsKit.lamp_material().emission_energy_multiplier = 1.2 + 5.0 * night
	if crews.is_empty():
		hurry = false
	for v in vans.duplicate():
		if not is_instance_valid(v):
			vans.erase(v)
			continue
		var van: NewsVan = v
		if van.driver != null:
			vans.erase(van)
			continue
		var d := van.global_position.distance_to(pp)
		var on_screen := cam != null and d < 320.0 and cam.is_position_in_frustum(van.global_position)
		van.unseen_time = 0.0 if on_screen else van.unseen_time + step
		var retire := d > despawn_distance
		if not retire and van.mode == NewsVan.Mode.LEAVING and van.unseen_time > 3.0:
			retire = true
		if not retire and van.crew_alive <= 0 and van.unseen_time > 4.0:
			retire = true
		# A van whose story closed under it (the player left, a stolen crew) with nobody out: off.
		if not retire and van.mode == NewsVan.Mode.ON_SCENE and van.story.is_empty() and _crew_of(van).is_empty():
			van.leave(_away_point(van))
		if retire:
			_retire(van)
	for cc in crews.duplicate():
		if not is_instance_valid(cc) or (cc as NewsCrew)._down:
			crews.erase(cc)
			continue
		var c: NewsCrew = cc
		var d := c.global_position.distance_to(pp)
		var on_screen := cam != null and d < 250.0 and cam.is_position_in_frustum(c.global_position)
		c.unseen_time = 0.0 if on_screen else c.unseen_time + step
		var van_gone := c.van == null or not is_instance_valid(c.van) or c.van.driver != null
		if d > despawn_distance or (van_gone and c.unseen_time > 3.0):
			crews.erase(c)
			c.queue_free()


func _crew_in_place(van: NewsVan) -> bool:
	var n := 0
	for c in crews:
		if is_instance_valid(c) and c.van == van and c.task == NewsCrew.Task.WORK:
			n += 1
	return n >= van.crew_alive and van.crew_alive > 0


func _crew_of(van: NewsVan) -> Array:
	var out := []
	for c in crews:
		if is_instance_valid(c) and c.van == van:
			out.append(c)
	return out


func _retire(van: NewsVan) -> void:
	vans.erase(van)
	for c in crews.duplicate():
		if is_instance_valid(c) and c.van == van:
			crews.erase(c)
			c.queue_free()
	if not van.story.is_empty():
		_close(van.story)
	if not is_instance_valid(van) or van.driver != null:
		return
	if van.get_parent() == self and _pool.size() < pool_size and not van.is_queued_for_deletion() and not van.is_wreck():
		van.strip_for_pool()
		remove_child(van)
		_pool.append(van)
	else:
		van.queue_free()


## Everything off the street at once (tests, a rebuild).
func clear() -> void:
	for v in vans.duplicate():
		_retire(v)
	for c in crews:
		if is_instance_valid(c):
			c.queue_free()
	crews.clear()
	for s in stories.duplicate():
		_close(s)
	stories.clear()
	_standoff_anchor = Vector3.INF
	_standoff_t = 0.0
	hurry = false


# --- Staging -------------------------------------------------------------------------------------

## A van already pulled up at story `s` with its uplink up and its crew in place and on air
## (tests and stills: a software frame takes seconds, and a van driving in from 200 m would take
## hundreds of them).
func stage(s: Dictionary, station_index: int = -1) -> NewsVan:
	_ensure_refs()
	var w: Vector3 = s.world
	var lay := layout(plan, Vector2(w.x, w.z), standoff_report_distance if s.kind == KIND_STANDOFF else report_distance)
	if lay.is_empty():
		return null
	s.layout = lay
	s.kerb = lay.kerb
	var van := NewsVan.make(station_index, _rng) if station_index >= 0 else _take()
	van.service = self
	van.story = s
	var kerb: Dictionary = lay.kerb
	van.goal = kerb.stop
	van.begin_drive(plan, int(kerb.axis), int(kerb.index), int(kerb.dir), 0.0)
	_aim(van)
	var p: Vector2 = kerb.stop
	var h := traffic._relief(p) if traffic else 0.0
	_enter_at(van, Transform3D(Basis(Vector3.UP, NewsVan.heading(int(kerb.axis), int(kerb.dir))),
			WorldState.to_local(Vector3(p.x, h + CityChunk.ROAD_TOP + van.road_lift(), p.y))))
	vans.append(van)
	s.van = van
	dispatched += 1
	van._arrive(float(kerb.lateral))
	van.raise = 1.0
	van._pose_gear()
	for c in crews:
		if is_instance_valid(c) and c.van == van:
			c.global_position = c.spot + Vector3.UP * 0.05
			c.task = NewsCrew.Task.WORK
	s.on_air = true
	s.air_t = 0.0
	s.air_for = 1e9
	return van


## Opens a story by hand (tests and stills).
func open_story(kind: String, world: Vector3) -> Dictionary:
	var s := _open(kind, world)
	s.send_at = 1e12
	return s


## A scene for tools/glshot/still_shot.gd (NEWS=blast|wide|crew|van|night): a story staged on the
## street ahead of the camera `cam`, a scorch where it happened, the van pulled up with its
## uplink raised and the crew on air. `wide` frames the whole thing from across the street, `crew`
## the reporter and the camera over the operator's shoulder, `van` the truck and its mast / dish.
## Returns the EYE ("x,y,z,yaw,pitch", true world) that frames it, or "".
func stage_for_shot(scene: String, cam: Camera3D, station_index: int = -1) -> String:
	_ensure_refs()
	enabled = true
	var cw := WorldState.to_world(cam.global_position)
	var fwd := -cam.global_basis.z
	var fwd2 := Vector2(fwd.x, fwd.z).normalized()
	var goal := Vector2(cw.x, cw.z) + fwd2 * 40.0
	var k := StreetRoute.kerb_stop(plan, goal, 0.0)
	if k.is_empty():
		return ""
	var road := plan.road_pos(int(k.axis), int(k.index))
	var width := plan.road_width(int(k.axis), int(k.index))
	var side := signf(float(k.lateral))
	var along := float(k.along)
	# The scene: in the road by the far kerb's side, like a car that went up there.
	var sc := Vector2(road + side * (width * 0.25), along) if int(k.axis) == CityPlan.AXIS_X else Vector2(along, road + side * (width * 0.25))
	var s := open_story(KIND_BLAST, Vector3(sc.x, plan.height_at(sc), sc.y))
	var van := stage(s, station_index)
	if van == null:
		return ""
	_tell_air(s.world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for c in crews:
		if is_instance_valid(c) and c.van == van:
			c.global_position = c.spot + Vector3.UP * 0.05
			c.task = NewsCrew.Task.WORK
			c._think()
	var lay: Dictionary = s.layout
	var rep: Vector2 = lay.reporter
	var camp: Vector2 = lay.camera
	var scn: Vector2 = lay.scene
	var across := Vector2(1.0, 0.0) if int(k.axis) == CityPlan.AXIS_X else Vector2(0.0, 1.0)
	var along_v := Vector2(0.0, 1.0) if int(k.axis) == CityPlan.AXIS_X else Vector2(1.0, 0.0)
	var sgn := float(lay.sgn)
	var gy := plan.height_at(rep)
	match scene:
		"crew":
			# Over the camera operator's shoulder, the reporter and the scene beyond.
			var e := camp + along_v * sgn * 2.6 - across * side * 0.6
			return _eye_at(Vector3(e.x, gy + 1.75, e.y), Vector3(rep.x, gy + 1.45, rep.y))
		"reporter":
			# Close on the reporter from beside the camera.
			var e2 := rep + along_v * sgn * 2.2 - across * side * 0.9
			return _eye_at(Vector3(e2.x, gy + 1.6, e2.y), Vector3(rep.x, gy + 1.35, rep.y))
		"van":
			var vp: Vector2 = lay.kerb.stop
			var e3 := vp - across * side * (width * 0.5 + 6.0) + along_v * sgn * 9.0
			return _eye_at(Vector3(e3.x, gy + 2.0, e3.y), Vector3(vp.x, gy + 4.5, vp.y))
	# The whole scene from across the street.
	var mid := rep.lerp(scn, 0.35)
	var e4 := mid - across * side * (width * 0.5 + 3.5) + along_v * sgn * 16.0
	return _eye_at(Vector3(e4.x, plan.height_at(e4) + 2.4, e4.y), Vector3(mid.x, gy + 1.8, mid.y))


static func _eye_at(e: Vector3, look_at: Vector3) -> String:
	var d := look_at - e
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [e.x, e.y, e.z, yaw, pitch]
