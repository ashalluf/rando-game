class_name Minimap
extends Control
## Minimap drawn straight from the CityPlan, in a round frame that rotates so you always face up.
## Night-mode street map: dark blocks, bright roads with outlines, terrain shading from the
## relief, water with a shoreline, landmark pins with names, cars as heading-aligned chips, a view
## cone and a glowing player arrow. Zooms out while driving. Cheap: ten redraws a second.

## Meters from the player to the edge of the map, on foot and in a car.
@export var radius_m: float = 240.0
@export var radius_driving_m: float = 420.0
@export var refresh_hz: float = 10.0
## Rotate the map with the camera (heading up). Off = north up.
@export var rotate_with_player: bool = true

const COLORS := {
	"land": Color(0.16, 0.17, 0.19), "downtown": Color(0.27, 0.28, 0.31), "midtown": Color(0.24, 0.25, 0.27),
	"suburbs": Color(0.22, 0.24, 0.22), "industrial": Color(0.25, 0.23, 0.21), "campus": Color(0.27, 0.25, 0.2),
	"beachtown": Color(0.29, 0.27, 0.21),
	"park": Color(0.2, 0.36, 0.22), "plaza": Color(0.32, 0.3, 0.26), "commercial": Color(0.36, 0.3, 0.42), "ocean": Color(0.1, 0.22, 0.36),
	"ocean_deep": Color(0.06, 0.14, 0.26), "shore": Color(0.35, 0.55, 0.7), "beach": Color(0.55, 0.5, 0.36),
	"hills": Color(0.2, 0.26, 0.18), "airport": Color(0.24, 0.25, 0.28), "port": Color(0.26, 0.26, 0.27),
	"road": Color(0.82, 0.82, 0.8), "road_edge": Color(0.06, 0.06, 0.07), "avenue": Color(0.95, 0.85, 0.5),
	"avenue_edge": Color(0.3, 0.24, 0.08), "hill_road": Color(0.7, 0.68, 0.62),
	"landmark": Color(1.0, 0.36, 0.3), "landmark_text": Color(1.0, 0.95, 0.9), "player": Color(0.35, 0.75, 1.0),
	"player_glow": Color(0.35, 0.75, 1.0, 0.25), "cone": Color(1.0, 1.0, 1.0, 0.08), "car": Color(0.95, 0.95, 0.95),
	"car_traffic": Color(0.75, 0.75, 0.8), "text": Color(0.9, 0.9, 0.9),
}

## The district fill colours, in CityPlan.District order. It was an anonymous literal inline in
## _draw(); a district added to the enum without a seventh entry here reads off the end of it
## and the minimap turns that district black. The smoke test checks the length.
const DISTRICT_COLORS := [COLORS.downtown, COLORS.midtown, COLORS.suburbs, COLORS.industrial,
	COLORS.campus, COLORS.beachtown]

const LANDMARK_NAMES := {
	"sign": "Shalluferwood Sign", "hills_sign": "Shallufer Hills", "pier": "Rando Pier", "observatory": "Observatory", "crown_tower": "Crown Tower",
	"five_drums": "Five Drums", "ziggurat_hall": "Ziggurat Hall", "stack_tower": "The Stack", "needle": "The Needle",
	"terminal": "Airport", "hangars": "Hangars", "port": "Port", "campus_hall": "Rando U",
	"venice_boardwalk": "Venice Boardwalk", "manhattan_pier": "Manhattan Pier",
	"redondo_pier": "Redondo Pier", "south_bay_mall": "South Bay Mall",
	"verde_cafe": "Verde Cafe", "masjid_al_noor": "Masjid Al Noor",
	"twin_glass": "Twin Towers", "cargo_ship": "Container Ship",
	"macarthur_park": "MacArthur Park",
}

var _yaw: float = 0.0
var _timer: float = 0.0
var _player: Node3D
var _city: Node
var _pulse: float = 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_timer += delta
	_pulse += delta
	if _timer >= 1.0 / refresh_hz:
		_timer = 0.0
		queue_redraw()


func _radius() -> float:
	if _player and _player.has_method("is_driving") and _player.is_driving():
		return radius_driving_m
	return radius_m


## World XZ (true world coordinates) to a point on the map (before rotation).
func world_to_map(wp: Vector2, center_world: Vector2) -> Vector2:
	var scale := size.x / (_radius() * 2.0)
	return size * 0.5 + (wp - center_world) * scale


func _draw() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _city == null:
		_city = get_tree().get_first_node_in_group("city")
	draw_rect(Rect2(Vector2.ZERO, size), COLORS.land)
	if _player == null or _city == null or not _city.has_method("world_position"):
		return
	var plan: CityPlan = _city.get("plan")
	if plan == null:
		return
	var wp3: Vector3 = _city.world_position(_player.global_position)
	var center := Vector2(wp3.x, wp3.z)
	var radius := _radius()
	var scale := size.x / (radius * 2.0)
	var idx := plan.block_index_at(center)
	var reach := int(ceil(radius * 1.5 / plan.block_size_range.x)) + 1
	var rig: Node3D = _player.get("camera_rig")
	_yaw = rig.global_rotation.y if rig else 0.0
	if rotate_with_player:
		draw_set_transform_matrix(Transform2D(_yaw, size * 0.5) * Transform2D(0.0, -size * 0.5))

	# Ground: zones and blocks, shaded by the relief so the hills read on the map.
	for ix in range(idx.x - reach, idx.x + reach + 1):
		for iz in range(idx.y - reach, idx.y + reach + 1):
			var block := plan.block(ix, iz)
			var rect: Rect2 = block.rect
			var bc := rect.get_center()
			var zone := plan.zone_at(bc)
			var owned := _owned_rect(plan, ix, iz)
			var shade := 1.0
			if plan.macro:
				var h: float = plan.macro.relief_at(bc)
				shade = 0.9 + 0.45 * clampf(h / plan.macro.relief_height, 0.0, 1.0)
			match zone:
				MacroMap.Zone.OCEAN:
					_fill(owned, COLORS.ocean_deep.lerp(COLORS.ocean, 0.5 + 0.5 * sin(bc.x * 0.01 + bc.y * 0.013)), center, scale)
					continue
				MacroMap.Zone.HILLS:
					var hh: float = plan.height_at(bc)
					_fill(owned, COLORS.hills.lightened(clampf(hh / 300.0, 0.0, 0.5)), center, scale)
					continue
				MacroMap.Zone.BEACH:
					_fill(owned, COLORS.beach, center, scale)
					_draw_roads(plan, ix, iz, center, scale)
					continue
				MacroMap.Zone.AIRPORT:
					_fill(owned, COLORS.airport, center, scale)
					continue
				MacroMap.Zone.PORT:
					_fill(owned, COLORS.port, center, scale)
					continue
			if block.has("site"):
				# A landmark's own ground (MacArthur Park): parkland, and only the roads it keeps.
				_fill(owned, COLORS.park, center, scale)
				_draw_roads(plan, ix, iz, center, scale, true)
				continue
			_draw_roads(plan, ix, iz, center, scale)
			var color: Color
			match block.kind:
				CityPlan.BlockKind.PARK:
					color = COLORS.park
				CityPlan.BlockKind.PLAZA:
					color = COLORS.plaza
				CityPlan.BlockKind.MALL, CityPlan.BlockKind.BIGBOX:
					color = COLORS.commercial
				_:
					color = DISTRICT_COLORS[block.district % DISTRICT_COLORS.size()]
			_fill(rect.grow(-1.0), color * Color(shade, shade, shade, 1.0), center, scale)

	# MacArthur Park's lake.
	if plan.macro:
		var park := LandmarkMacArthurPark.layout(plan)
		if not park.is_empty() and (park.lake_bounds as Rect2).grow(radius * 1.5).has_point(center):
			var lake := PackedVector2Array()
			for p: Vector2 in park.lake:
				lake.append(world_to_map(p, center))
			draw_colored_polygon(lake, COLORS.ocean)
	# Shoreline and runways.
	if plan.macro:
		var macro: MacroMap = plan.macro
		var pts := PackedVector2Array()
		var z0 := center.y - radius * 1.5
		var z1 := center.y + radius * 1.5
		var z := z0
		while z <= z1:
			pts.append(world_to_map(Vector2(macro.coast_x(z), z), center))
			z += 20.0
		if pts.size() > 1:
			draw_polyline(pts, COLORS.shore, 2.0, true)
		var ar := macro.airport_rect
		if ar.grow(radius).has_point(center):
			for rz in macro.runway_zs:
				var a := world_to_map(Vector2(ar.position.x + 20.0, rz), center)
				var b := world_to_map(Vector2(ar.end.x - 20.0, rz), center)
				draw_line(a, b, COLORS.road_edge, macro.runway_width * scale + 2.0, true)
				draw_line(a, b, COLORS.road, macro.runway_width * scale, true)

	# Hill roads (not on the grid).
	if plan.macro and plan.macro.hill_roads:
		var road_reach := radius * 1.5
		for road in plan.macro.hill_roads.roads:
			var pts: PackedVector2Array = road.points
			var w: float = road.width
			for i in pts.size() - 1:
				if pts[i].distance_to(center) > road_reach and pts[i + 1].distance_to(center) > road_reach:
					continue
				var a := world_to_map(pts[i], center)
				var b := world_to_map(pts[i + 1], center)
				draw_line(a, b, COLORS.road_edge, w * scale + 2.0, true)
				draw_line(a, b, COLORS.hill_road, w * scale, true)

	# Cars as small chips pointing where they drive.
	var mine: Node = _player.get("vehicle")
	for node in get_tree().get_nodes_in_group("vehicle"):
		var car := node as Node3D
		if car == null or car == mine:
			continue
		var cw: Vector3 = _city.world_position(car.global_position)
		var cp := Vector2(cw.x, cw.z)
		if cp.distance_to(center) < radius * 1.3:
			var p := world_to_map(cp, center)
			var heading := car.global_rotation.y
			var f := Vector2(-sin(heading), -cos(heading))
			var r := Vector2(-f.y, f.x)
			var chip := PackedVector2Array([p + f * 3.5 + r * 1.8, p + f * 3.5 - r * 1.8, p - f * 3.5 - r * 1.8, p - f * 3.5 + r * 1.8])
			draw_colored_polygon(chip, COLORS.car_traffic if car.get("traffic") else COLORS.car)

	_draw_police(center, scale)

	# Landmarks: pins with names (names stay upright).
	if plan.macro:
		for lm in Landmarks.all():
			var a: Vector2 = lm.anchor
			if a.distance_to(center) < radius * 1.4:
				var p := world_to_map(a, center)
				draw_circle(p, 6.0, COLORS.road_edge)
				draw_circle(p, 4.5, COLORS.landmark)
				draw_circle(p, 1.6, Color.WHITE)
				var label: String = LANDMARK_NAMES.get(lm.id, lm.id)
				draw_set_transform_matrix(Transform2D(_yaw if rotate_with_player else 0.0, size * 0.5) * Transform2D(0.0, -size * 0.5) * Transform2D(0.0, p) * Transform2D(-_yaw if rotate_with_player else 0.0, Vector2.ZERO))
				draw_string_outline(ThemeDB.fallback_font, Vector2(7.0, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, COLORS.road_edge)
				draw_string(ThemeDB.fallback_font, Vector2(7.0, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLORS.landmark_text)
				if rotate_with_player:
					draw_set_transform_matrix(Transform2D(_yaw, size * 0.5) * Transform2D(0.0, -size * 0.5))
				else:
					draw_set_transform_matrix(Transform2D())

	# North marker rides on the rotating rim.
	var n_pos := size * 0.5 + Vector2(0.0, -size.y * 0.5 + 14.0)
	draw_circle(n_pos, 9.0, COLORS.road_edge)
	draw_string(ThemeDB.fallback_font, n_pos + Vector2(-4.5, 4.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLORS.text)

	# Player: view cone, pulsing glow and arrow, drawn unrotated at the center.
	draw_set_transform_matrix(Transform2D())
	var forward := Vector2(0.0, -1.0) if rotate_with_player else Vector2(-sin(_yaw), -cos(_yaw))
	var c := size * 0.5
	var right := Vector2(-forward.y, forward.x)
	var cone := PackedVector2Array([c, c + (forward * 0.85 - right * 0.55).normalized() * size.x * 0.5, c + (forward * 0.85 + right * 0.55).normalized() * size.x * 0.5])
	draw_colored_polygon(cone, COLORS.cone)
	var glow := 10.0 + 4.0 * sin(_pulse * 4.0)
	draw_circle(c, glow, COLORS.player_glow)
	var tri := PackedVector2Array([c + forward * 12.0, c - forward * 8.0 + right * 8.0, c - forward * 3.5, c - forward * 8.0 - right * 8.0])
	draw_colored_polygon(tri, COLORS.player)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color.WHITE, 1.5, true)
	# Inner vignette so the edge fades into the frame.
	draw_arc(c, size.x * 0.5 - 6.0, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, 0.35), 12.0, true)


## The police (scripts/npc/police.gd): the search area round the last sighting once they have
## lost the player, and every unit as a blip flashing red and blue - cruisers as bigger chips,
## officers on foot as dots. Clamped to the rim when they are off the map, so you can see what
## is coming.
func _draw_police(center: Vector2, scale: float) -> void:
	var police := get_tree().get_first_node_in_group("wanted")
	if police == null or int(police.get("stars")) <= 0 and (police.get("cruisers") as Array).is_empty():
		return
	var red := Color(1.0, 0.18, 0.16)
	var blue := Color(0.22, 0.45, 1.0)
	if police.call("show_search_area"):
		var sc: Vector3 = _city.world_position(police.call("search_center"))
		var sp := world_to_map(Vector2(sc.x, sc.z), center)
		var sr: float = float(police.call("search_radius_now")) * scale
		var breathe := 0.5 + 0.5 * sin(_pulse * 3.0)
		draw_circle(sp, sr, Color(red.r, red.g, red.b, 0.10 + 0.06 * breathe))
		draw_arc(sp, sr, 0.0, TAU, 64, Color(blue.r, blue.g, blue.b, 0.55), 2.0, true)
	var phase := fmod(_pulse * 2.2, 1.0) < 0.5
	var limit := size.x * 0.5 - 12.0
	var mid := size * 0.5
	for car in police.get("cruisers"):
		if is_instance_valid(car):
			var cw: Vector3 = _city.world_position((car as Node3D).global_position)
			var p := _clamp_to_rim(world_to_map(Vector2(cw.x, cw.z), center), mid, limit)
			draw_circle(p, 6.5, COLORS.road_edge)
			draw_circle(p, 5.0, red if phase else blue)
			draw_circle(p, 2.0, Color.WHITE)
	for o in police.get("officers"):
		if is_instance_valid(o):
			var ow: Vector3 = _city.world_position((o as Node3D).global_position)
			var p2 := _clamp_to_rim(world_to_map(Vector2(ow.x, ow.z), center), mid, limit)
			draw_circle(p2, 4.0, COLORS.road_edge)
			draw_circle(p2, 2.8, blue if phase else red)


func _clamp_to_rim(p: Vector2, mid: Vector2, limit: float) -> Vector2:
	var off := p - mid
	if off.length() > limit:
		off = off.normalized() * limit
	return mid + off


func _owned_rect(plan: CityPlan, ix: int, iz: int) -> Rect2:
	var x0 := plan.road_pos(CityPlan.AXIS_X, ix) + plan.road_width(CityPlan.AXIS_X, ix) * 0.5
	var x1 := plan.road_pos(CityPlan.AXIS_X, ix + 1) + plan.road_width(CityPlan.AXIS_X, ix + 1) * 0.5
	var z0 := plan.road_pos(CityPlan.AXIS_Z, iz) + plan.road_width(CityPlan.AXIS_Z, iz) * 0.5
	var z1 := plan.road_pos(CityPlan.AXIS_Z, iz + 1) + plan.road_width(CityPlan.AXIS_Z, iz + 1) * 0.5
	return Rect2(x0, z0, x1 - x0, z1 - z0)


## The two roads on this block's +X and +Z sides, as outlined antialiased lines.
## `open_only` skips a road where it is closed through a landmark's site (CityPlan.road_open).
func _draw_roads(plan: CityPlan, ix: int, iz: int, center: Vector2, scale: float, open_only: bool = false) -> void:
	var rx := plan.road_pos(CityPlan.AXIS_X, ix + 1)
	var wx := plan.road_width(CityPlan.AXIS_X, ix + 1)
	var rz := plan.road_pos(CityPlan.AXIS_Z, iz + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, iz + 1)
	var owned := _owned_rect(plan, ix, iz)
	var ax := wx > plan.street_width + 1.0
	var az := wz > plan.street_width + 1.0
	if not open_only or plan.road_open(CityPlan.AXIS_X, ix + 1, owned.get_center().y):
		var a := world_to_map(Vector2(rx, owned.position.y), center)
		var b := world_to_map(Vector2(rx, owned.end.y), center)
		draw_line(a, b, COLORS.avenue_edge if ax else COLORS.road_edge, wx * scale + 2.0, true)
		draw_line(a, b, COLORS.avenue if ax else COLORS.road, wx * scale, true)
	if not open_only or plan.road_open(CityPlan.AXIS_Z, iz + 1, owned.get_center().x):
		var a := world_to_map(Vector2(owned.position.x, rz), center)
		var b := world_to_map(Vector2(owned.end.x, rz), center)
		draw_line(a, b, COLORS.avenue_edge if az else COLORS.road_edge, wz * scale + 2.0, true)
		draw_line(a, b, COLORS.avenue if az else COLORS.road, wz * scale, true)


func _fill(world_rect: Rect2, color: Color, center: Vector2, scale: float) -> void:
	if color.a <= 0.0:
		return
	var p := world_to_map(world_rect.position, center)
	draw_rect(Rect2(p, world_rect.size * scale), color)
