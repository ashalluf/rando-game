class_name Minimap
extends Control
## Minimap drawn straight from the CityPlan, in a round frame that rotates so you always face up.
## Night-mode street map, drawn by MapPainter (the full-screen map, WorldMap, draws the same thing
## at any scale): the hill-shaded mountains and the sea under it (map_relief.gdshader, a child
## drawn behind), dark blocks by district, bright streets with outlines, rec parks and schools,
## the freeways with their route shields, the Coral Line and its stations, the river, the piers,
## the runways, landmark glyphs with names; then the GPS route and the waypoint (WorldMap), cars as
## heading-aligned chips, police and fire / ambulance blips, a view cone and a glowing player
## arrow. Zooms out while driving. Cheap: ten redraws a second.

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
	"park": Color(0.2, 0.36, 0.22), "school": Color(0.36, 0.33, 0.27), "plaza": Color(0.32, 0.3, 0.26), "commercial": Color(0.36, 0.3, 0.42), "ocean": Color(0.1, 0.22, 0.36),
	"ocean_deep": Color(0.06, 0.14, 0.26), "shore": Color(0.35, 0.55, 0.7), "beach": Color(0.55, 0.5, 0.36),
	"hills": Color(0.2, 0.26, 0.18), "airport": Color(0.24, 0.25, 0.28), "port": Color(0.26, 0.26, 0.27),
	"road": Color(0.82, 0.82, 0.8), "road_edge": Color(0.06, 0.06, 0.07), "avenue": Color(0.95, 0.85, 0.5),
	"avenue_edge": Color(0.3, 0.24, 0.08), "hill_road": Color(0.7, 0.68, 0.62),
	"landmark": Color(1.0, 0.36, 0.3), "landmark_text": Color(1.0, 0.95, 0.9), "player": Color(0.35, 0.75, 1.0),
	"player_glow": Color(0.35, 0.75, 1.0, 0.25), "cone": Color(1.0, 1.0, 1.0, 0.08), "car": Color(0.95, 0.95, 0.95),
	"car_traffic": Color(0.75, 0.75, 0.8), "text": Color(0.9, 0.9, 0.9),
	"river": Color(0.46, 0.46, 0.44), "river_water": Color(0.16, 0.3, 0.32),
}

## The district fill colours, in CityPlan.District order. It was an anonymous literal inline in
## _draw(); a district added to the enum without a seventh entry here reads off the end of it
## and the minimap turns that district black. The smoke test checks the length.
const DISTRICT_COLORS := [COLORS.downtown, COLORS.midtown, COLORS.suburbs, COLORS.industrial,
	COLORS.campus, COLORS.beachtown]

const LANDMARK_NAMES := {
	"sign": "Shalluferwood Sign", "hills_sign": "Shallufer Hills", "pier": "Rando Pier", "observatory": "Observatory",
	"terminal": "Rando International", "hangars": "Hangars", "port": "Port", "campus_hall": "Rando U",
	# The airport (AirportTerminal, Airport): original names.
	"concourse_w": "Gates 11-14", "concourse_e": "Gates 15-19", "control_tower": "Control Tower",
	"skyhook": "Skyhook", "airport_garage": "Airport Parking", "rental_lot": "Rental Cars",
	"airfield_lights": "Runways 27L / 27R",
	"venice_boardwalk": "Venice Boardwalk", "manhattan_pier": "Manhattan Pier",
	"redondo_pier": "Redondo Pier", "south_bay_mall": "South Bay Mall",
	"verde_cafe": "Verde Cafe", "masjid_omar": "Masjid Omar ibn Al-Khattab",
	"cargo_ship": "Container Ship",
	# The downtown skyline (LandmarkDowntown): original names, never the real towers'.
	"dt_sail_tower": "Sail Tower", "dt_crown_cylinder": "Crown Tower", "dt_granite_slab": "White Granite Tower",
	"dt_ellipse_crown": "Blue Flame Tower", "dt_round_crown": "Hilltop Plaza Two", "dt_plaza_one": "Hilltop Plaza One",
	"dt_faceted_twins": "Red Granite Pair", "dt_bronze_slab": "Bronze Tower", "dt_dark_glass": "Smoked Glass Tower",
	"dt_five_drums": "Five Drums Hotel", "dt_black_twins": "Black Twins", "dt_pyramid_crown": "Pyramid Tower",
	"dt_spire_pyramid": "Spire Tower", "dt_curved_white": "Curve Tower", "dt_park_a": "Twist Residences",
	"dt_park_b": "South Park Terraces", "dt_park_c": "South Park Fins", "dt_park_d": "South Park Cubes",
	"dt_unfinished": "Unfinished Towers",
	# Downtown LA civic set (Landmarks.all()); every name invented.
	"ziggurat_hall": "City Hall", "arena": "Rando Arena", "live_plaza": "Starlight Plaza", "live_hotel": "Hotel Altair",
	"convention_center": "Convention Center", "civic_park": "Civic Park",
	"concert_hall": "Symphony Hall", "lattice_museum": "The Lattice", "pueblo_station": "Pueblo Station",
	"macarthur_park": "MacArthur Park",
}

## Pixels a landmark pin needs clear of an already-labelled one to get its own name written.
const LABEL_ROOM := 34.0

var _yaw: float = 0.0
var _timer: float = 0.0
var _player: Node3D
var _city: Node
var _pulse: float = 0.0
var _relief: ColorRect
var _relief_mat: ShaderMaterial
## How long the last redraw took to record (us): the minimap's CPU cost, ten times a second.
var last_draw_usec: int = 0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The ground (sea, beaches, hill-shaded mountains) is a child drawn behind this control.
	_relief = ColorRect.new()
	_relief.name = "Relief"
	_relief.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relief.show_behind_parent = true
	_relief.set_anchors_preset(Control.PRESET_FULL_RECT)
	_relief.color = COLORS.land
	add_child(_relief)


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
	if _player == null or _city == null or not _city.has_method("world_position"):
		return
	var plan: CityPlan = _city.get("plan")
	if plan == null:
		return
	var t0 := Time.get_ticks_usec()
	if _relief_mat == null:
		_relief_mat = MapPainter.relief_material(_city)
		_relief.material = _relief_mat
	var wp3: Vector3 = _city.world_position(_player.global_position)
	var center := Vector2(wp3.x, wp3.z)
	var radius := _radius()
	var scale := size.x / (radius * 2.0)
	var rig: Node3D = _player.get("camera_rig")
	_yaw = rig.global_rotation.y if rig else 0.0
	var yaw := _yaw if rotate_with_player else 0.0
	var base := Transform2D(yaw, size * 0.5) * Transform2D(0.0, -size * 0.5)
	MapPainter.set_relief_view(_relief_mat, center, scale, size, yaw)
	var v := MapPainter.View.new()
	v.xf = Transform2D(Vector2(scale, 0.0), Vector2(0.0, scale), size * 0.5 - center * scale)
	v.k = scale
	v.ppm = scale
	v.area = Rect2(center - Vector2.ONE * radius * 1.5, Vector2.ONE * radius * 3.0)
	v.base = base
	v.yaw = yaw
	v.screen = size
	var data := MapData.of(plan)
	data.ensure_rect(v.area)
	draw_set_transform_matrix(base)
	MapPainter.draw_geo(self, v, plan, data)

	# Shoreline.
	if plan.macro:
		var macro: MacroMap = plan.macro
		var pts := PackedVector2Array()
		var z := center.y - radius * 1.5
		while z <= center.y + radius * 1.5:
			pts.append(world_to_map(Vector2(macro.coast_x(z), z), center))
			z += 20.0
		if pts.size() > 1:
			draw_polyline(pts, COLORS.shore, 2.0, true)

	# The GPS route to the waypoint (WorldMap).
	var gps := get_tree().get_first_node_in_group("world_map")
	if gps and gps.call("has_route"):
		MapPainter.draw_route(self, v, gps.call("route_points"), center, int(gps.call("route_index")))

	# Cars as small chips pointing where they drive.
	var mine: Node = _player.get("vehicle")
	for node in get_tree().get_nodes_in_group("vehicle"):
		var car := node as Node3D
		if car == null or car == mine or car.is_in_group("emergency_unit") or car.is_in_group("police_car"):
			continue
		# Moving traffic only: parked cars lined every kerb with chips and broke the streets up.
		if not car.get("traffic") and car.get("driver") == null:
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

	# Freeway shields, rail stations, landmark glyphs and names (upright).
	MapPainter.draw_marks(self, v, plan, data)

	var mid := size * 0.5
	var limit := size.x * 0.5 - 12.0
	MapPainter.draw_units(self, v, _city, _pulse, func(p: Vector2) -> Vector2: return _clamp_to_rim(p, mid, limit))

	# The waypoint pin, held on the rim while it is off the map.
	if gps and gps.call("has_waypoint"):
		var wpt: Vector2 = gps.call("waypoint_xz")
		var pin := _clamp_to_rim(world_to_map(wpt, center), mid, size.x * 0.5 - 16.0)
		MapPainter.upright(self, v, pin, func(c: CanvasItem) -> void: MapPainter.waypoint_pin(c, _pulse))

	# North marker rides on the rotating rim.
	var n_pos := size * 0.5 + Vector2(0.0, -size.y * 0.5 + 14.0)
	draw_circle(n_pos, 9.0, COLORS.road_edge)
	draw_string(MapPainter.font(true), n_pos + Vector2(-4.5, 4.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLORS.text)

	# Player: view cone, pulsing glow and arrow, drawn unrotated at the center.
	draw_set_transform_matrix(Transform2D())
	var forward := Vector2(0.0, -1.0) if rotate_with_player else Vector2(-sin(_yaw), -cos(_yaw))
	var c := size * 0.5
	var right := Vector2(-forward.y, forward.x)
	var cone := PackedVector2Array([c, c + (forward * 0.85 - right * 0.55).normalized() * size.x * 0.5, c + (forward * 0.85 + right * 0.55).normalized() * size.x * 0.5])
	draw_colored_polygon(cone, COLORS.cone)
	MapPainter.player_arrow(self, c, forward, _pulse)
	# Inner vignette so the edge fades into the frame.
	draw_arc(c, size.x * 0.5 - 6.0, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, 0.35), 12.0, true)
	last_draw_usec = Time.get_ticks_usec() - t0


func _clamp_to_rim(p: Vector2, mid: Vector2, limit: float) -> Vector2:
	var off := p - mid
	if off.length() > limit:
		off = off.normalized() * limit
	return mid + off
