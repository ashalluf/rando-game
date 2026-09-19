extends Control
## Minimap drawn straight from the CityPlan, in a round frame that rotates so you always face up
## (the GTA way), with a light street-map palette (the Google Maps way). Cheap: ten redraws a second.

## Meters from the player to the edge of the map.
@export var radius_m: float = 260.0
@export var refresh_hz: float = 10.0
## Rotate the map with the camera (heading up). Off = north up.
@export var rotate_with_player: bool = true

const COLORS := {
	"land": Color(0.93, 0.92, 0.89), "downtown": Color(0.87, 0.86, 0.85), "midtown": Color(0.91, 0.90, 0.87),
	"suburbs": Color(0.92, 0.93, 0.87), "industrial": Color(0.89, 0.87, 0.83), "park": Color(0.76, 0.90, 0.74),
	"plaza": Color(0.96, 0.93, 0.85), "ocean": Color(0.62, 0.79, 0.95), "beach": Color(0.98, 0.94, 0.78),
	"hills": Color(0.83, 0.89, 0.76), "airport": Color(0.87, 0.87, 0.90), "port": Color(0.86, 0.86, 0.87),
	"road": Color(1.0, 1.0, 1.0), "road_edge": Color(0.78, 0.78, 0.78), "avenue": Color(0.99, 0.90, 0.60),
	"avenue_edge": Color(0.90, 0.78, 0.45), "landmark": Color(0.92, 0.25, 0.22), "player": Color(0.25, 0.55, 1.0),
	"car": Color(0.25, 0.25, 0.3), "frame": Color(0.08, 0.08, 0.1, 0.9), "text": Color(0.2, 0.2, 0.25),
}

var _yaw: float = 0.0

var _timer: float = 0.0
var _player: Node3D
var _city: Node


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 1.0 / refresh_hz:
		_timer = 0.0
		queue_redraw()


## World XZ (true world coordinates) to a point on the map (before rotation).
func world_to_map(wp: Vector2, center_world: Vector2) -> Vector2:
	var scale := size.x / (radius_m * 2.0)
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
	var scale := size.x / (radius_m * 2.0)
	var idx := plan.block_index_at(center)
	var reach := int(ceil(radius_m * 1.5 / plan.block_size_range.x)) + 1
	var rig: Node3D = _player.get("camera_rig")
	_yaw = rig.global_rotation.y if rig else 0.0
	# Everything below is drawn rotated about the center so the camera heading points up.
	if rotate_with_player:
		draw_set_transform(size * 0.5, _yaw, Vector2.ONE)
		draw_set_transform_matrix(Transform2D(_yaw, size * 0.5) * Transform2D(0.0, -size * 0.5))

	# Blocks and zones.
	for ix in range(idx.x - reach, idx.x + reach + 1):
		for iz in range(idx.y - reach, idx.y + reach + 1):
			var block := plan.block(ix, iz)
			var rect: Rect2 = block.rect
			var zone := plan.zone_at(rect.get_center())
			var owned := _owned_rect(plan, ix, iz)
			var color: Color
			match zone:
				MacroMap.Zone.OCEAN:
					color = COLORS.ocean
				MacroMap.Zone.HILLS:
					color = COLORS.hills
				MacroMap.Zone.BEACH:
					color = COLORS.beach
				MacroMap.Zone.AIRPORT:
					color = COLORS.airport
				MacroMap.Zone.PORT:
					color = COLORS.port
				_:
					color = Color.TRANSPARENT
			if zone != MacroMap.Zone.CITY:
				_fill(owned, color, center, scale)
				if zone == MacroMap.Zone.BEACH:
					_draw_roads(plan, ix, iz, rect, center, scale)
				continue
			# City block: roads first, then the block itself.
			_draw_roads(plan, ix, iz, rect, center, scale)
			match block.kind:
				CityPlan.BlockKind.PARK:
					color = COLORS.park
				CityPlan.BlockKind.PLAZA:
					color = COLORS.plaza
				_:
					color = [COLORS.downtown, COLORS.midtown, COLORS.suburbs, COLORS.industrial][block.district]
			_fill(rect, color, center, scale)

	# Hill roads (not on the grid) as white lines.
	if plan.macro and plan.macro.hill_roads:
		var road_reach := radius_m * 1.5
		for road in plan.macro.hill_roads.roads:
			var pts: PackedVector2Array = road.points
			var w: float = road.width
			for i in pts.size() - 1:
				if pts[i].distance_to(center) > road_reach and pts[i + 1].distance_to(center) > road_reach:
					continue
				var a := world_to_map(pts[i], center)
				var b := world_to_map(pts[i + 1], center)
				draw_line(a, b, COLORS.road_edge, w * scale + 2.0)
				draw_line(a, b, COLORS.road, w * scale)

	# Landmarks as red pins.
	if plan.macro:
		for lm in Landmarks.all():
			var a: Vector2 = lm.anchor
			if a.distance_to(center) < radius_m * 1.4:
				var p := world_to_map(a, center)
				draw_circle(p, 5.0, COLORS.landmark)
				draw_circle(p, 5.0, Color.WHITE, false, 1.5)

	# Cars you can see, as dots.
	for node in get_tree().get_nodes_in_group("vehicle"):
		var car := node as Node3D
		if car == null or car == _player.get("vehicle"):
			continue
		var cw: Vector3 = _city.world_position(car.global_position)
		var cp := Vector2(cw.x, cw.z)
		if cp.distance_to(center) < radius_m * 1.2:
			draw_circle(world_to_map(cp, center), 2.5, COLORS.car)

	# North letter rides on the rotating map's rim.
	var n_pos := size * 0.5 + Vector2(0.0, -size.y * 0.5 + 16.0)
	draw_string(ThemeDB.fallback_font, n_pos + Vector2(-5.0, 5.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLORS.text)

	# Player arrow: always at the center, always pointing up when rotating.
	draw_set_transform_matrix(Transform2D())
	var forward := Vector2(0.0, -1.0) if rotate_with_player else Vector2(-sin(_yaw), -cos(_yaw))
	var c := size * 0.5
	var right := Vector2(-forward.y, forward.x)
	var tri := PackedVector2Array([c + forward * 11.0, c - forward * 7.0 + right * 7.0, c - forward * 3.0, c - forward * 7.0 - right * 7.0])
	draw_colored_polygon(tri, COLORS.player)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color.WHITE, 1.5)


func _owned_rect(plan: CityPlan, ix: int, iz: int) -> Rect2:
	var x0 := plan.road_pos(CityPlan.AXIS_X, ix) + plan.road_width(CityPlan.AXIS_X, ix) * 0.5
	var x1 := plan.road_pos(CityPlan.AXIS_X, ix + 1) + plan.road_width(CityPlan.AXIS_X, ix + 1) * 0.5
	var z0 := plan.road_pos(CityPlan.AXIS_Z, iz) + plan.road_width(CityPlan.AXIS_Z, iz) * 0.5
	var z1 := plan.road_pos(CityPlan.AXIS_Z, iz + 1) + plan.road_width(CityPlan.AXIS_Z, iz + 1) * 0.5
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func _draw_roads(plan: CityPlan, ix: int, iz: int, rect: Rect2, center: Vector2, scale: float) -> void:
	var rx := plan.road_pos(CityPlan.AXIS_X, ix + 1)
	var wx := plan.road_width(CityPlan.AXIS_X, ix + 1)
	var rz := plan.road_pos(CityPlan.AXIS_Z, iz + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, iz + 1)
	var owned := _owned_rect(plan, ix, iz)
	var ax := wx > plan.street_width + 1.0
	var az := wz > plan.street_width + 1.0
	var edge := 2.0 / scale
	_fill(Rect2(rx - wx * 0.5 - edge, owned.position.y, wx + edge * 2.0, owned.size.y), COLORS.avenue_edge if ax else COLORS.road_edge, center, scale)
	_fill(Rect2(owned.position.x, rz - wz * 0.5 - edge, owned.size.x, wz + edge * 2.0), COLORS.avenue_edge if az else COLORS.road_edge, center, scale)
	_fill(Rect2(rx - wx * 0.5, owned.position.y, wx, owned.size.y), COLORS.avenue if ax else COLORS.road, center, scale)
	_fill(Rect2(owned.position.x, rz - wz * 0.5, owned.size.x, wz), COLORS.avenue if az else COLORS.road, center, scale)


func _fill(world_rect: Rect2, color: Color, center: Vector2, scale: float) -> void:
	if color.a <= 0.0:
		return
	var p := world_to_map(world_rect.position, center)
	draw_rect(Rect2(p, world_rect.size * scale), color)
