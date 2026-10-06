class_name WorldMap
extends CanvasLayer
## The full-screen map (the `map` action: M / gamepad Back), the waypoint and the GPS.
##
## Opening it pauses the game (the GTA way) and shows the whole basin in MapPainter's drawing at
## any scale: the hill-shaded mountains and the sea (map_relief.gdshader), the blocks, streets,
## freeways with their shields, the Coral Line, the river, the parks, the piers and the airport,
## landmark glyphs, district names zoomed out and street names zoomed in, the player's arrow and
## the police and fire / ambulance blips, under panels of the HUD's smoked glass
## (glass_hud.gdshader): the title, a legend and the controls. Mouse: drag to pan, wheel to zoom
## about the cursor, click to set (or clear) the waypoint, right click to clear it. Keys: WASD /
## arrows pan, Q / E zoom, Space sets the waypoint at the centre, Backspace clears it. Pad: left
## stick pans a centre cursor, the triggers zoom, A sets the waypoint, X clears it, B or Back
## closes. Esc closes too.
##
## The ground plan is drawn ONCE into a Node2D in world metres, which pan and zoom only move
## (it is redrawn when the zoom has changed enough that its width floors are wrong, or when the
## view leaves what it drew); the marks, the route and the units are a screen-space overlay
## redrawn each frame.
##
## The waypoint lives here whether the map is open or not (group "world_map"): a GPS route along
## the streets (GpsRoute) for the minimap and the map, searched a slice a frame, recomputed when
## the player strays from it, cleared on arrival; and a beacon in the world (a violet beam and a
## ground ring, shaders/waypoint_beacon.gdshader, fog-free and widened with distance so it reads
## from across the basin).

## Zoom range, screen pixels per metre at 1080 lines, and the zoom it opens at.
@export var min_ppm: float = 0.065
@export var max_ppm: float = 4.0
@export var open_ppm: float = 0.45
## Pan speed with keys or the stick (screen heights a second) and zoom speed (doublings a second).
@export var pan_speed: float = 0.9
@export var zoom_speed: float = 1.6
## The route is searched this long a frame (us); the player is off it past `off_route` metres
## (checked every `route_check` seconds) and has arrived within `arrive` metres of the waypoint.
@export var route_budget_us: int = 1500
@export var off_route: float = 38.0
@export var route_check: float = 0.5
@export var arrive: float = 28.0
## MapData is built this long a frame (us) from the moment the city is up.
@export var warm_budget_us: int = 1500
## The beacon: beam height (m) and the screen width it never draws thinner than (fraction of
## the view height per metre of distance).
@export var beam_height: float = 420.0

const FONT_SEMIBOLD := "res://assets/fonts/Inter-SemiBold.woff2"
const FONT_MEDIUM := "res://assets/fonts/Inter-Medium.woff2"
const LEGEND := [
	["road", "Street"], ["avenue", "Avenue"], ["freeway", "Freeway"], ["rail", "Coral Line"],
	["station", "Rail station"], ["river", "LA River"], ["park", "Park"], ["field", "Sports field"],
	["school", "School"], ["commercial", "Shopping"], ["glyph", "Landmark"], ["route", "GPS route"],
	["police", "Police"], ["emergency", "Fire / ambulance"],
]

var _open := false
var _paused_by_us := false
var _mouse_before := Input.MOUSE_MODE_CAPTURED
var _root: Control
var _relief: ColorRect
var _relief_mat: ShaderMaterial
var _geo: Node2D
var _overlay: Control
var _panels: Control
var _ink: Control
var _glass: Array[ColorRect] = []
var _semibold: Font
var _medium: Font
var _city: Node
var _player: Node3D
var _plan: CityPlan
var _data: MapData

var center := Vector2.ZERO
var ppm: float = 0.45
var _geo_ppm: float = -1.0
var _geo_area := Rect2()
var _drag_from := Vector2.ZERO
var _dragging := false
var _drag_moved := false
var _pad_cursor := false
var _pulse: float = 0.0

var _waypoint := Vector2.ZERO
var _has_waypoint := false
var _route: GpsRoute
var _pending: GpsRoute
var _route_index: int = 0
var _route_t: float = 0.0
var _beacon: Node3D
var _beam: MeshInstance3D
var _ring: MeshInstance3D
var _beacon_y: float = 0.0
var _beacon_t: float = 0.0


func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("world_map")
	_semibold = _load_font(FONT_SEMIBOLD)
	_medium = _load_font(FONT_MEDIUM)
	_build()
	_root.visible = false


# --- State other nodes read ---------------------------------------------------------------------

func is_open() -> bool:
	return _open


func has_waypoint() -> bool:
	return _has_waypoint


func waypoint_xz() -> Vector2:
	return _waypoint


func has_route() -> bool:
	return _has_waypoint and _route != null and _route.ok and _route.points.size() >= 2


func route_points() -> PackedVector2Array:
	return _route.points if _route else PackedVector2Array()


func route_index() -> int:
	return _route_index


func route() -> GpsRoute:
	return _route


## Sets the waypoint at world XZ `p` and starts a route to it.
func set_waypoint(p: Vector2) -> void:
	_waypoint = p
	_has_waypoint = true
	_route = null
	_pending = null
	_start_route()
	_place_beacon(true)


func clear_waypoint() -> void:
	_has_waypoint = false
	_route = null
	_pending = null
	if _beacon:
		_beacon.visible = false


## Runs the pending route search to the end at once (tests and stills).
func finish_route() -> void:
	while _pending and not _pending.step(1000000):
		pass
	_adopt_pending()


# --- Open / close -------------------------------------------------------------------------------

func open() -> void:
	if _open or not _find_city():
		return
	_open = true
	_mouse_before = Input.mouse_mode
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_us = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	center = _player_xz()
	ppm = open_ppm * _ui_scale()
	_relief_mat = MapPainter.relief_material(_city)
	_relief.material = _relief_mat
	_geo_ppm = -1.0
	_root.visible = true
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	if _paused_by_us:
		get_tree().paused = false
		_paused_by_us = false
	if not OS.has_feature("web") or _mouse_before == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = _mouse_before


func _find_city() -> bool:
	if _city == null or not is_instance_valid(_city):
		_city = get_tree().get_first_node_in_group("city")
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _city == null or _player == null or not _city.has_method("world_position"):
		return false
	_plan = _city.get("plan")
	if _plan == null:
		return false
	_data = MapData.of(_plan)
	return true


func _player_xz() -> Vector2:
	var w: Vector3 = _city.world_position(_player.global_position)
	return Vector2(w.x, w.z)


func _ui_scale() -> float:
	return clampf(_root.get_viewport_rect().size.y / 1080.0, 0.6, 3.0)


# --- Input --------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _open or not event.is_action_pressed("map"):
		return
	# Something else has the game paused (the pause menu, the downed card).
	if get_tree().paused:
		return
	var wheel := get_parent().get_node_or_null("WeaponWheel") if get_parent() else null
	if wheel and wheel.has_method("is_open") and wheel.call("is_open"):
		return
	open()
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("map") or event.is_action_pressed("toggle_mouse") \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
		close()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_pad_cursor = false
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(mb.position, 1.25)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(mb.position, 0.8)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = true
					_drag_moved = false
					_drag_from = mb.position
				else:
					_dragging = false
					if not _drag_moved:
						_click(mb.position)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					clear_waypoint()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_drag_from) > 4.0:
			_drag_moved = true
		if _drag_moved:
			center -= mm.relative / ppm
			_refresh()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_click(_root.get_viewport_rect().size * 0.5)
			KEY_BACKSPACE, KEY_DELETE:
				clear_waypoint()
	elif event is InputEventJoypadButton and event.pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_A:
				_pad_cursor = true
				_click(_root.get_viewport_rect().size * 0.5)
			JOY_BUTTON_X:
				clear_waypoint()


## A click at screen point `sp`: on the waypoint clears it, anywhere else sets it there.
func _click(sp: Vector2) -> void:
	var wp := screen_to_world(sp)
	if _has_waypoint and world_to_screen(_waypoint).distance_to(sp) < 16.0:
		clear_waypoint()
	else:
		set_waypoint(wp)
	_overlay.queue_redraw()


func _zoom_at(sp: Vector2, factor: float) -> void:
	var before := screen_to_world(sp)
	ppm = clampf(ppm * factor, min_ppm * _ui_scale(), max_ppm * _ui_scale())
	center += before - screen_to_world(sp)
	_refresh()


func screen_to_world(sp: Vector2) -> Vector2:
	return center + (sp - _root.get_viewport_rect().size * 0.5) / ppm


func world_to_screen(wp: Vector2) -> Vector2:
	return _root.get_viewport_rect().size * 0.5 + (wp - center) * ppm


# --- Per frame ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)
	_pulse += dt
	if not _find_city():
		return
	if not _data.ready:
		_data.warm(warm_budget_us if not _open else warm_budget_us * 8)
		if _open and _data.ready:
			_geo_ppm = -1.0
	_update_route(dt)
	_update_beacon(dt)
	if not _open:
		return
	# Keys and the stick pan, Q / E and the triggers zoom (real time: the game is paused).
	var pan := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if pan.length() < 0.2:
		pan = Vector2.ZERO
	else:
		_pad_cursor = true
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		pan.y += 1.0
	var zoom := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_EQUAL):
		zoom += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_MINUS):
		zoom -= 1.0
	var view := _root.get_viewport_rect().size
	if pan != Vector2.ZERO:
		center += pan.limit_length(1.0) * pan_speed * view.y * dt / ppm
	if absf(zoom) > 0.1:
		_zoom_at(view * 0.5, pow(2.0, zoom * zoom_speed * dt))
	_refresh()


## Moves the ground plan and the relief to the current view, redrawing the plan when needed.
func _refresh() -> void:
	if not _open:
		return
	var view := _root.get_viewport_rect().size
	center = center.clamp(-Vector2.ONE * MapData.HALF_SPAN, Vector2.ONE * MapData.HALF_SPAN)
	_geo.position = view * 0.5 - center * ppm
	_geo.scale = Vector2(ppm, ppm)
	var area := Rect2(center - view * 0.5 / ppm, view / ppm)
	var rebuild := _geo_ppm < 0.0 or ppm > _geo_ppm * 1.35 or ppm < _geo_ppm / 1.35
	if not rebuild and not _geo_area.encloses(area):
		rebuild = true
	if rebuild:
		_geo_ppm = ppm
		# Zoomed out the whole basin is cheap enough to hold; zoomed in, a margin round the view.
		_geo_area = Rect2(-Vector2.ONE * MapData.HALF_SPAN, Vector2.ONE * MapData.HALF_SPAN * 2.0) if ppm < 0.3 else area.grow(maxf(area.size.x, area.size.y))
		_data.ensure_rect(_geo_area if ppm >= 0.3 else area.grow(200.0))
		_geo.queue_redraw()
	MapPainter.set_relief_view(_relief_mat, center, ppm, view, 0.0)
	var s := _ui_scale()
	_overlay.position = Vector2.ZERO
	_overlay.scale = Vector2(s, s)
	_overlay.size = view / s
	_overlay.queue_redraw()
	_ink.queue_redraw()


func _draw_geo() -> void:
	if _plan == null:
		return
	var v := MapPainter.View.new()
	# In 1080-line pixels, like the marks: line floors and detail thresholds stay put at 4K.
	v.ppm = _geo_ppm / _ui_scale()
	v.area = _geo_area
	v.aa = _geo_ppm > 0.3
	v.full = true
	MapPainter.draw_geo(_geo, v, _plan, _data)


## The marks' view, in 1080-line pixels: the Marks layer is drawn at that size and scaled with
## the window (`_ui_scale()`), so shields, glyphs, names and the arrow keep their size at 4K.
func _screen_view() -> MapPainter.View:
	var s := _ui_scale()
	var view := _root.get_viewport_rect().size / s
	var k := ppm / s
	var v := MapPainter.View.new()
	v.xf = Transform2D(Vector2(k, 0.0), Vector2(0.0, k), view * 0.5 - center * k)
	v.k = k
	v.ppm = k
	v.area = Rect2(center - view * 0.5 / k, view / k)
	v.screen = view
	v.full = true
	return v


func _draw_overlay() -> void:
	if _plan == null:
		return
	var v := _screen_view()
	var c := _overlay
	if has_route():
		var pp := _player_xz()
		MapPainter.draw_route(c, v, _route.points, pp, _route_index)
	MapPainter.draw_marks(c, v, _plan, _data)
	var view := v.screen
	var inv := 1.0 / _ui_scale()
	var inset := Rect2(Vector2(14, 14), view - Vector2(28, 28))
	var clamp_fn := func(p: Vector2) -> Vector2: return p.clamp(inset.position, inset.end)
	MapPainter.draw_units(c, v, _city, _pulse, clamp_fn)
	if _has_waypoint:
		var wp: Vector2 = clamp_fn.call(world_to_screen(_waypoint) * inv)
		c.draw_set_transform(wp)
		MapPainter.waypoint_pin(c, _pulse)
		c.draw_set_transform(Vector2.ZERO)
	# The player: the arrow points where the camera looks.
	var rig: Node3D = _player.get("camera_rig")
	var yaw := rig.global_rotation.y if rig else 0.0
	var pp2: Vector2 = clamp_fn.call(world_to_screen(_player_xz()) * inv)
	MapPainter.player_arrow(c, pp2, Vector2(-sin(yaw), -cos(yaw)), _pulse, 1.15)
	if _pad_cursor:
		var m := view * 0.5
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			c.draw_line(m + d * 6.0, m + d * 16.0, Color(1, 1, 1, 0.9), 2.0, true)


# --- The waypoint's route ------------------------------------------------------------------------

func _start_route() -> void:
	if _plan == null and not _find_city():
		return
	_pending = GpsRoute.new(_plan, _player_xz(), _waypoint)


func _adopt_pending() -> void:
	if _pending and _pending.done:
		if _pending.ok or _route == null:
			_route = _pending
			_route_index = 0
		_pending = null


func _update_route(dt: float) -> void:
	if not _has_waypoint:
		return
	if _pending:
		_pending.step(route_budget_us)
		_adopt_pending()
	var pp := _player_xz()
	if pp.distance_to(_waypoint) < arrive:
		clear_waypoint()
		return
	_route_t -= dt
	if _route_t > 0.0:
		return
	_route_t = route_check
	if _route == null or not _route.ok:
		if _pending == null and (_route == null or _route.done):
			_start_route()
		return
	var near := _route.nearest(pp)
	_route_index = int(near.y)
	if near.x > off_route and _pending == null:
		_start_route()


# --- The beacon in the world --------------------------------------------------------------------

func _build_beacon() -> void:
	_beacon = Node3D.new()
	_beacon.name = "WaypointBeacon"
	_beacon.visible = false
	add_child(_beacon)
	var shader: Shader = load("res://shaders/waypoint_beacon.gdshader")
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = shader
	beam_mat.set_shader_parameter("kind", 0)
	beam_mat.set_shader_parameter("height", beam_height)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = beam_height
	cyl.radial_segments = 16
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	_beam.mesh = cyl
	_beam.material_override = beam_mat
	_beam.position.y = beam_height * 0.5
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.extra_cull_margin = 400.0
	_beacon.add_child(_beam)
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = shader
	ring_mat.set_shader_parameter("kind", 1)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = quad
	_ring.material_override = ring_mat
	_ring.position.y = 0.25
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.extra_cull_margin = 200.0
	_beacon.add_child(_ring)


func _place_beacon(resample: bool) -> void:
	if _beacon == null or not _has_waypoint or _city == null:
		return
	var local: Vector3 = WorldState.to_local(Vector3(_waypoint.x, 0.0, _waypoint.y))
	if resample and _city.has_method("ground_height_at"):
		_beacon_y = float(_city.call("ground_height_at", local))
	_beacon.position = Vector3(local.x, _beacon_y, local.z)
	_beacon.visible = true


func _update_beacon(dt: float) -> void:
	if not _has_waypoint or _beacon == null:
		return
	_beacon_t -= dt
	_place_beacon(_beacon_t <= 0.0)
	if _beacon_t <= 0.0:
		_beacon_t = 2.0


# --- Building the screen -----------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Map"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_relief = ColorRect.new()
	_relief.name = "Relief"
	_relief.color = Color(0.16, 0.17, 0.19)
	_relief.set_anchors_preset(Control.PRESET_FULL_RECT)
	_relief.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_relief)
	_geo = Node2D.new()
	_geo.name = "Plan"
	_geo.draw.connect(_draw_geo)
	_root.add_child(_geo)
	_overlay = Control.new()
	_overlay.name = "Marks"
	# Sized and scaled in _refresh() (1080-line pixels, scaled with the window).
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_root.add_child(_overlay)
	_panels = Control.new()
	_panels.name = "Panels"
	_panels.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panels)
	var shader: Shader = load("res://shaders/glass_hud.gdshader")
	for i in 3:
		var g := ColorRect.new()
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("mode", 1)
		mat.set_shader_parameter("bar_fill", 0.0)
		mat.set_shader_parameter("bar_corner", 14.0)
		g.material = mat
		_panels.add_child(g)
		_glass.append(g)
	_ink = Control.new()
	_ink.name = "Ink"
	_ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.draw.connect(_draw_ink)
	_root.add_child(_ink)
	_build_beacon()


## The panels: title (top left), legend (right), controls and the scale bar (bottom).
func _panel_rects() -> Array[Rect2]:
	var view := _root.get_viewport_rect().size
	var s := _ui_scale()
	var m := 24.0 * s
	var title := Rect2(Vector2(m, m), Vector2(430.0, 86.0) * s)
	var legend_h := (54.0 + 25.0 * LEGEND.size()) * s
	var legend := Rect2(Vector2(view.x - m - 236.0 * s, m), Vector2(236.0 * s, legend_h))
	var help := Rect2(Vector2(m, view.y - m - 56.0 * s), Vector2(minf(1010.0 * s, view.x - 2.0 * m - 250.0 * s), 56.0 * s))
	return [title, legend, help]


func _draw_ink() -> void:
	var rects := _panel_rects()
	var s := _ui_scale()
	for i in _glass.size():
		var g := _glass[i]
		g.position = rects[i].position
		g.size = rects[i].size
		(g.material as ShaderMaterial).set_shader_parameter("rect_px", g.size)
		(g.material as ShaderMaterial).set_shader_parameter("bar_corner", 14.0 * s)
	var c := _ink
	var white := Color(1, 1, 1, 0.96)
	var dim := Color(1, 1, 1, 0.62)
	# Title: the map, where the player is, the waypoint's distance.
	var t: Rect2 = rects[0]
	c.draw_string(_semibold, t.position + Vector2(20, 36) * s, "RANDO CITY", HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * s), white)
	var where := ""
	if _city and _city.has_method("district_name_at"):
		where = str(_city.call("district_name_at", _player.global_position))
	var sub := where.to_upper()
	if _has_waypoint:
		var d := _route.length if has_route() else _player_xz().distance_to(_waypoint)
		sub += "    WAYPOINT  %s" % _distance_text(d)
		if _pending:
			sub += "  ..."
	c.draw_string(_medium, t.position + Vector2(20, 66) * s, sub, HORIZONTAL_ALIGNMENT_LEFT, t.size.x - 30 * s, int(14 * s), dim)
	# Legend.
	var l: Rect2 = rects[1]
	c.draw_string(_semibold, l.position + Vector2(18, 32) * s, "LEGEND", HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * s), white)
	for k in LEGEND.size():
		var y := l.position.y + (54.0 + 25.0 * k) * s
		var sw := Vector2(l.position.x + 30.0 * s, y)
		_swatch(c, str(LEGEND[k][0]), sw, s)
		c.draw_string(_medium, Vector2(l.position.x + 54.0 * s, y + 5.0 * s), str(LEGEND[k][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s), white)
	# Controls.
	var h: Rect2 = rects[2]
	var help := "DRAG  pan     WHEEL  zoom     CLICK  set / clear waypoint     RIGHT CLICK  clear     M / ESC  close"
	if _pad_cursor:
		help = "L STICK  pan     LT / RT  zoom     A  set waypoint     X  clear     B / BACK  close"
	c.draw_string(_medium, h.position + Vector2(20, 35) * s, help, HORIZONTAL_ALIGNMENT_LEFT, h.size.x - 30 * s, int(14 * s), white)
	# Scale bar, bottom right.
	var view := _root.get_viewport_rect().size
	var metres := _nice_length(140.0 * s / ppm)
	var px := metres * ppm
	var a := Vector2(view.x - 24.0 * s - px, view.y - 40.0 * s)
	c.draw_line(a + Vector2(0, 2), a + Vector2(px, 2), Color(0, 0, 0, 0.6), 6.0 * s)
	c.draw_line(a, a + Vector2(px, 0), white, 3.0 * s)
	c.draw_line(a + Vector2(0, -6 * s), a + Vector2(0, 4 * s), white, 2.0 * s)
	c.draw_line(a + Vector2(px, -6 * s), a + Vector2(px, 4 * s), white, 2.0 * s)
	var label := _distance_text(metres)
	var tw := _medium.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s)).x
	c.draw_string_outline(_medium, a + Vector2(px * 0.5 - tw * 0.5, -10 * s), label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), 4, Color(0, 0, 0, 0.7))
	c.draw_string(_medium, a + Vector2(px * 0.5 - tw * 0.5, -10 * s), label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), white)
	# North.
	var n := Vector2(view.x - 24.0 * s - 18.0 * s, rects[1].end.y + 36.0 * s)
	c.draw_circle(n, 15.0 * s, Color(0.04, 0.045, 0.055, 0.85))
	c.draw_colored_polygon(PackedVector2Array([n + Vector2(0, -11) * s, n + Vector2(6, 5) * s, n + Vector2(0, 2) * s, n + Vector2(-6, 5) * s]), white)
	c.draw_string(_semibold, n + Vector2(-5, 30) * s, "N", HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), white)


func _swatch(c: CanvasItem, key: String, p: Vector2, s: float) -> void:
	var col: Dictionary = Minimap.COLORS
	var w := 26.0 * s
	var a := p - Vector2(w * 0.5, 0)
	var b := p + Vector2(w * 0.5, 0)
	match key:
		"road":
			c.draw_line(a, b, col.road_edge, 7.0 * s)
			c.draw_line(a, b, col.road, 4.5 * s)
		"avenue":
			c.draw_line(a, b, col.avenue_edge, 9.0 * s)
			c.draw_line(a, b, col.avenue, 6.0 * s)
		"freeway":
			c.draw_line(a, b, MapPainter.FREEWAY_EDGE, 11.0 * s)
			c.draw_line(a, b, MapPainter.FREEWAY, 8.0 * s)
		"rail":
			c.draw_line(a, b, MapPainter.INK, 7.0 * s)
			c.draw_line(a, b, MapPainter.RAIL, 4.5 * s)
		"station":
			c.draw_circle(p, 6.5 * s, MapPainter.INK)
			c.draw_circle(p, 5.0 * s, Color.WHITE)
			c.draw_circle(p, 3.0 * s, MapPainter.RAIL)
		"river":
			c.draw_line(a, b, col.river, 9.0 * s)
			c.draw_line(a, b, col.river_water, 3.0 * s)
		"park":
			c.draw_rect(Rect2(p - Vector2(10, 7) * s, Vector2(20, 14) * s), col.park)
		"field":
			c.draw_rect(Rect2(p - Vector2(10, 7) * s, Vector2(20, 14) * s), MapPainter.TRACK)
			c.draw_rect(Rect2(p - Vector2(7, 4) * s, Vector2(14, 8) * s), MapPainter.FIELD)
		"school":
			c.draw_rect(Rect2(p - Vector2(10, 7) * s, Vector2(20, 14) * s), col.school)
		"commercial":
			c.draw_rect(Rect2(p - Vector2(10, 7) * s, Vector2(20, 14) * s), col.commercial)
		"glyph":
			c.draw_set_transform(p, 0.0, Vector2(s, s))
			MapPainter.glyph(c, "civic", 7.5)
			c.draw_set_transform(Vector2.ZERO)
		"route":
			c.draw_line(a, b, MapPainter.ROUTE_EDGE, 8.0 * s)
			c.draw_line(a, b, MapPainter.ROUTE_COLOR, 5.0 * s)
		"police":
			c.draw_circle(p - Vector2(6, 0) * s, 6.0 * s, MapPainter.INK)
			c.draw_circle(p - Vector2(6, 0) * s, 4.5 * s, Color(1.0, 0.18, 0.16))
			c.draw_circle(p + Vector2(6, 0) * s, 6.0 * s, MapPainter.INK)
			c.draw_circle(p + Vector2(6, 0) * s, 4.5 * s, Color(0.22, 0.45, 1.0))
		"emergency":
			c.draw_rect(Rect2(p - Vector2(6, 6) * s, Vector2(12, 12) * s), MapPainter.INK)
			c.draw_rect(Rect2(p - Vector2(4.5, 4.5) * s, Vector2(9, 9) * s), Color.WHITE)
			c.draw_rect(Rect2(p - Vector2(1, 3.5) * s, Vector2(2, 7) * s), Color(0.85, 0.1, 0.1))
			c.draw_rect(Rect2(p - Vector2(3.5, 1) * s, Vector2(7, 2) * s), Color(0.85, 0.1, 0.1))


static func _distance_text(m: float) -> String:
	if m >= 1000.0:
		return "%.1f km" % (m / 1000.0)
	return "%d m" % int(round(m))


static func _nice_length(m: float) -> float:
	var p := pow(10.0, floor(log(m) / log(10.0)))
	for f: float in [1.0, 2.0, 5.0, 10.0]:
		if f * p >= m * 0.7:
			return f * p
	return 10.0 * p


func _load_font(path: String) -> Font:
	var f: Font = load(path) if ResourceLoader.exists(path) else null
	return f if f else ThemeDB.fallback_font
