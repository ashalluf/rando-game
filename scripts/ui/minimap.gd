extends Control
## Minimap drawn straight from the CityPlan: roads, blocks colored by district and zone, landmarks,
## and the player's heading. North is up. Cheap enough to redraw ten times a second.

## Meters from the player to the edge of the map.
@export var radius_m: float = 320.0
@export var refresh_hz: float = 10.0

const COLORS := {
	"downtown": Color(0.55, 0.58, 0.66), "midtown": Color(0.60, 0.60, 0.58), "suburbs": Color(0.62, 0.66, 0.54),
	"industrial": Color(0.60, 0.54, 0.48), "park": Color(0.40, 0.65, 0.35), "plaza": Color(0.78, 0.72, 0.60),
	"ocean": Color(0.20, 0.45, 0.72), "beach": Color(0.86, 0.78, 0.55), "hills": Color(0.36, 0.48, 0.28),
	"airport": Color(0.45, 0.45, 0.47), "port": Color(0.52, 0.52, 0.54), "road": Color(0.22, 0.22, 0.25),
	"avenue": Color(0.18, 0.18, 0.2), "landmark": Color(1.0, 0.85, 0.3), "player": Color(1.0, 0.45, 0.12),
	"frame": Color(0.08, 0.08, 0.1, 0.85), "car": Color(0.9, 0.9, 0.95),
}

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


## World XZ (true world coordinates) to a point on the map.
func world_to_map(wp: Vector2, center_world: Vector2) -> Vector2:
	var scale := size.x / (radius_m * 2.0)
	return size * 0.5 + (wp - center_world) * scale


func _draw() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _city == null:
		_city = get_tree().get_first_node_in_group("city")
	draw_rect(Rect2(Vector2.ZERO, size), COLORS.frame)
	if _player == null or _city == null or not _city.has_method("world_position"):
		return
	var plan: CityPlan = _city.get("plan")
	if plan == null:
		return
	var wp3: Vector3 = _city.world_position(_player.global_position)
	var center := Vector2(wp3.x, wp3.z)
	var scale := size.x / (radius_m * 2.0)
	var idx := plan.block_index_at(center)
	var reach := int(ceil(radius_m / plan.block_size_range.x)) + 1

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

	# Landmarks.
	if plan.macro:
		for lm in Landmarks.all():
			var a: Vector2 = lm.anchor
			if a.distance_to(center) < radius_m * 1.4:
				var p := world_to_map(a, center)
				draw_circle(p, 4.0, COLORS.landmark)
				draw_circle(p, 4.0, Color.BLACK, false, 1.0)

	# Cars you can see, as dots.
	for node in get_tree().get_nodes_in_group("vehicle"):
		var car := node as Node3D
		if car == null or car == _player.get("vehicle"):
			continue
		var cw: Vector3 = _city.world_position(car.global_position)
		var cp := Vector2(cw.x, cw.z)
		if cp.distance_to(center) < radius_m:
			draw_circle(world_to_map(cp, center), 2.0, COLORS.car)

	# Player arrow, pointing where the camera looks.
	var rig: Node3D = _player.get("camera_rig")
	var yaw: float = rig.global_rotation.y if rig else 0.0
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var c := size * 0.5
	var right := Vector2(-forward.y, forward.x)
	var tri := PackedVector2Array([c + forward * 9.0, c - forward * 6.0 + right * 6.0, c - forward * 6.0 - right * 6.0])
	draw_colored_polygon(tri, COLORS.player)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color.BLACK, 1.0)
	# North marker and frame.
	draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.5 - 4.0, 14.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.9), false, 2.0)


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
	_fill(Rect2(rx - wx * 0.5, owned.position.y, wx, owned.size.y), COLORS.avenue if wx > plan.street_width + 1.0 else COLORS.road, center, scale)
	_fill(Rect2(owned.position.x, rz - wz * 0.5, owned.size.x, wz), COLORS.avenue if wz > plan.street_width + 1.0 else COLORS.road, center, scale)


func _fill(world_rect: Rect2, color: Color, center: Vector2, scale: float) -> void:
	if color.a <= 0.0:
		return
	var p := world_to_map(world_rect.position, center)
	draw_rect(Rect2(p, world_rect.size * scale), color)
