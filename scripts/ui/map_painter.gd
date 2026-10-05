class_name MapPainter
extends RefCounted
## Draws the city map onto any CanvasItem, for the round minimap (Minimap) and the full-screen
## map (WorldMap): the same drawing at any scale. Static; a View says where.
##
## Two passes. draw_geo() is the ground plan in the canvas's own units through view.xf: blocks
## (MapData) coloured by district and kind, rec-park and school facilities, the streets, the hill
## roads, the Esplanade, MacArthur Park's lake, the LA River, the airport's runways, the piers, the
## freeways and the Coral Line. draw_marks() is what stays upright and a fixed size on screen
## whatever the zoom: freeway shields (FreewayKit's own route numbers), rail stations, landmark
## glyphs and names, and on the full map the district and street names. The mountains and the sea
## under it all are map_relief.gdshader (relief_material()).
##
## Widths are metres with a floor in screen pixels (w()), so a road never thins to nothing when
## the map zooms out and a freeway reads as a freeway at every scale.

## Where and how big. `xf` maps world XZ to canvas units, `k` is canvas units per metre (xf's
## scale), `ppm` screen pixels per metre, `area` the world rect worth drawing, `base` the canvas
## transform the caller has set (the minimap's rotation), `yaw` that rotation (marks are drawn
## counter-rotated so they stay upright), `screen` the canvas size in screen pixels (marks are
## kept inside it), `aa` antialiased lines (the turning minimap; the full map's thousands of rects
## do without).
class View:
	var xf := Transform2D.IDENTITY
	var k: float = 1.0
	var ppm: float = 1.0
	var area := Rect2()
	var base := Transform2D.IDENTITY
	var yaw: float = 0.0
	var screen := Vector2.ZERO
	var aa := true
	## The full map: district and street names, smaller glyphs at the basin scale.
	var full := false

	func to(p: Vector2) -> Vector2:
		return xf * p

	## A width in canvas units: `m` metres, never under `min_px` screen pixels.
	func w(m: float, min_px: float) -> float:
		return maxf(m, min_px / ppm) * k


const ROUTE_COLOR := Color(0.74, 0.46, 1.0)
const ROUTE_EDGE := Color(0.16, 0.06, 0.3)
const FREEWAY := Color(0.95, 0.6, 0.26)
const FREEWAY_EDGE := Color(0.24, 0.11, 0.03)
const FREEWAY_LINE := Color(1.0, 0.86, 0.62)
const SHIELD := Color(0.08, 0.36, 0.42)
const RAIL := LightRail.LINE_COLOR
const PIER := Color(0.55, 0.47, 0.36)
const PIER_EDGE := Color(0.1, 0.09, 0.08)
const FIELD := Color(0.28, 0.46, 0.27)
const COURT := Color(0.26, 0.44, 0.47)
const TRACK := Color(0.6, 0.3, 0.24)
const POOL := Color(0.25, 0.62, 0.82)
const HALL := Color(0.42, 0.39, 0.33)
const LOT := Color(0.3, 0.3, 0.32)
const LABEL := Color(0.96, 0.95, 0.92)
const DISTRICT_TEXT := Color(0.85, 0.86, 0.9, 0.62)
const STREET_TEXT := Color(0.92, 0.92, 0.9)
const INK := Color(0.04, 0.045, 0.055)

## Landmark glyphs: which symbol a landmark gets, by id (prefix "dt_" is a tower).
const GLYPHS := {
	"sign": "star", "hills_sign": "star", "observatory": "dome", "campus_hall": "civic",
	"terminal": "plane", "concourse_w": "plane", "concourse_e": "plane", "control_tower": "plane",
	"skyhook": "plane", "airport_garage": "plane", "rental_lot": "plane", "airfield_lights": "plane",
	"hangars": "plane", "port": "ship", "cargo_ship": "ship", "pier": "pier", "venice_boardwalk": "pier",
	"manhattan_pier": "pier", "redondo_pier": "pier", "south_bay_mall": "bag", "verde_cafe": "cup",
	"masjid_omar": "dome", "ziggurat_hall": "civic", "arena": "venue", "live_plaza": "venue",
	"live_hotel": "tower", "convention_center": "civic", "civic_park": "tree", "concert_hall": "venue",
	"lattice_museum": "civic", "pueblo_station": "rail", "macarthur_park": "tree",
}
## Glyph ring colours by symbol.
const GLYPH_COLORS := {
	"star": Color(1.0, 0.78, 0.3), "dome": Color(0.55, 0.85, 0.7), "civic": Color(0.95, 0.9, 0.75),
	"plane": Color(0.55, 0.75, 1.0), "ship": Color(0.5, 0.8, 0.95), "pier": Color(0.95, 0.75, 0.5),
	"bag": Color(0.82, 0.62, 1.0), "cup": Color(0.95, 0.7, 0.45), "venue": Color(1.0, 0.45, 0.55),
	"tower": Color(0.75, 0.82, 0.95), "tree": Color(0.5, 0.9, 0.5), "rail": RAIL,
}
## The airport's many landmarks are one glyph on the map (the terminal's); the rest only name
## themselves on the full map close in.
const MINOR := ["concourse_w", "concourse_e", "control_tower", "skyhook", "airport_garage",
	"rental_lot", "airfield_lights", "hangars", "venice_boardwalk", "live_plaza", "live_hotel"]

static var _font: Font
static var _font_bold: Font
static var _relief_shader: Shader
static var _hill_bounds: Array[Rect2] = []


static func font(bold: bool = false) -> Font:
	if _font == null:
		_font = _load_font("res://assets/fonts/Inter-Medium.woff2")
		_font_bold = _load_font("res://assets/fonts/Inter-SemiBold.woff2")
	return _font_bold if bold else _font


static func _load_font(path: String) -> Font:
	var f: Font = load(path) if ResourceLoader.exists(path) else null
	return f if f else ThemeDB.fallback_font


## A material for a ColorRect under the map: the sea, beaches and hill-shaded mountains, from the
## city's basin bake (the horizon plane's own textures). Null without a city.
static func relief_material(city: Node) -> ShaderMaterial:
	if city == null:
		return null
	var ground: ShaderMaterial = city.get("_ground_material")
	if ground == null:
		return null
	if _relief_shader == null:
		_relief_shader = load("res://shaders/map_relief.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = _relief_shader
	var ctex: Texture2D = ground.get_shader_parameter("macro_tex")
	mat.set_shader_parameter("color_tex", ctex)
	mat.set_shader_parameter("height_tex", ground.get_shader_parameter("macro_height_tex"))
	mat.set_shader_parameter("macro_span", ground.get_shader_parameter("macro_span"))
	mat.set_shader_parameter("macro_centre", ground.get_shader_parameter("macro_centre"))
	mat.set_shader_parameter("height_scale", MacroMap.BAKE_HEIGHT_SCALE)
	if ctex:
		mat.set_shader_parameter("bake_res", float(ctex.get_width()))
	return mat


static func set_relief_view(mat: ShaderMaterial, center: Vector2, ppm: float, rect_px: Vector2, yaw: float) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("view_center", center)
	mat.set_shader_parameter("ppm", ppm)
	mat.set_shader_parameter("rect_px", rect_px)
	mat.set_shader_parameter("yaw", yaw)


static func block_color(b: Dictionary) -> Color:
	var c: Dictionary = Minimap.COLORS
	match int(b.kind):
		MapData.Kind.PARK, MapData.Kind.SITE:
			return c.park
		MapData.Kind.PLAZA:
			return c.plaza
		MapData.Kind.SCHOOL:
			return c.school
		MapData.Kind.COMMERCIAL:
			return c.commercial
		MapData.Kind.AIRPORT:
			return c.airport
		MapData.Kind.PORT:
			return c.port
		MapData.Kind.BEACH:
			return c.beach
	return Minimap.DISTRICT_COLORS[int(b.district) % Minimap.DISTRICT_COLORS.size()]


# --- The ground plan ----------------------------------------------------------------------------

static func draw_geo(ci: CanvasItem, v: View, plan: CityPlan, data: MapData) -> void:
	var c: Dictionary = Minimap.COLORS
	var detail := v.ppm > 0.3
	# Blocks: the owned rect for ground that has no pavement ring, the inner one for city blocks.
	for i in data.indices_in(v.area):
		var b: Dictionary = data.blocks[i]
		var kind := int(b.kind)
		var r: Rect2 = b.owned if kind in [MapData.Kind.AIRPORT, MapData.Kind.PORT, MapData.Kind.BEACH, MapData.Kind.SITE] else (b.rect as Rect2).grow(-0.5)
		if not r.intersects(v.area):
			continue
		_rect(ci, v, r, block_color(b))
		if detail and str(b.grounds) != "":
			_draw_facilities(ci, v, plan, int(b.ix), int(b.iz))
	# Streets: casing first, then the fill, avenues over streets.
	var roads := data.indices_in(v.area, true)
	var edge_px := 1.0 if v.ppm > 0.12 else 0.0
	if edge_px > 0.0:
		for i in roads:
			var rd: Dictionary = data.roads[i]
			_road_rect(ci, v, rd.rect, rd.axis, c.avenue_edge if rd.avenue else c.road_edge, 1.6 if rd.avenue else 1.0, edge_px)
	# Zoomed out to the basin the streets fade toward the blocks, so the avenues and freeways
	# carry the city's shape instead of a uniform mesh.
	var quiet := 1.0 - smoothstep(0.08, 0.3, v.ppm)
	var street_col: Color = (c.road as Color).lerp(Color(0.32, 0.33, 0.36), quiet * 0.75)
	var avenue_col: Color = (c.avenue as Color).lerp(Color(0.55, 0.5, 0.36), quiet * 0.4)
	for pass_avenue: bool in [false, true]:
		for i in roads:
			var rd: Dictionary = data.roads[i]
			if bool(rd.avenue) != pass_avenue:
				continue
			_road_rect(ci, v, rd.rect, rd.axis, avenue_col if rd.avenue else street_col, 1.6 if rd.avenue else 1.0, 0.0)
	if plan.macro == null:
		return
	var macro: MacroMap = plan.macro
	# MacArthur Park's lake.
	var park := LandmarkMacArthurPark.layout(plan)
	if not park.is_empty() and (park.lake_bounds as Rect2).intersects(v.area):
		var lake := PackedVector2Array()
		for p: Vector2 in park.lake:
			lake.append(v.to(p))
		ci.draw_colored_polygon(lake, c.ocean)
	if macro.river and macro.river.bounds.intersects(v.area):
		_draw_river(ci, v, plan, macro.river)
	_draw_airport(ci, v, macro)
	_draw_piers(ci, v)
	_draw_replica(ci, v, macro)
	if macro.hill_roads:
		_draw_hill_roads(ci, v, macro.hill_roads)
	if macro.freeway:
		_draw_freeways(ci, v, macro.freeway)
	var rail := LightRail.of(plan)
	if rail:
		_draw_rail(ci, v, rail)


## A road's carriageway as a rect, widened to `min_px` (+ `grow_px` each side for the casing).
static func _road_rect(ci: CanvasItem, v: View, r: Rect2, axis: int, col: Color, min_px: float, grow_px: float) -> void:
	var across := r.size.x if axis == CityPlan.AXIS_X else r.size.y
	var want := maxf(across, min_px / v.ppm) + grow_px * 2.0 / v.ppm
	var g := (want - across) * 0.5
	var rr := r.grow_individual(g, 0.0, g, 0.0) if axis == CityPlan.AXIS_X else r.grow_individual(0.0, g, 0.0, g)
	_rect(ci, v, rr, col)


static func _rect(ci: CanvasItem, v: View, r: Rect2, col: Color) -> void:
	var a := v.to(r.position)
	ci.draw_rect(Rect2(a, r.size * v.k), col)


static func _line(ci: CanvasItem, v: View, a: Vector2, b: Vector2, col: Color, width: float) -> void:
	ci.draw_line(v.to(a), v.to(b), col, width, v.aa)


static func _poly(ci: CanvasItem, v: View, pts: PackedVector2Array, col: Color, width: float) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(v.to(p))
	if out.size() >= 2:
		ci.draw_polyline(out, col, width, v.aa)


## Rec parks and schools (Parks): fields, courts, the track, the pool, the buildings.
static func _draw_facilities(ci: CanvasItem, v: View, plan: CityPlan, ix: int, iz: int) -> void:
	var pl := Parks.plan_for(plan, ix, iz)
	for f: Dictionary in pl.get("fac", []):
		var r: Rect2 = f.r
		match str(f.t):
			"soccer":
				_rect(ci, v, r, FIELD)
				if v.ppm > 0.8:
					_line(ci, v, Parks.fp(f, 0.0, -float(f.W) * 0.5), Parks.fp(f, 0.0, float(f.W) * 0.5), Color(1, 1, 1, 0.45), 1.0)
			"diamond":
				_rect(ci, v, r, FIELD)
				var home: Vector2 = f.home
				var u: Vector2 = f.u
				var pv := Parks.perp(u)
				var d := Parks.BASE_PATH * 1.25
				ci.draw_colored_polygon(PackedVector2Array([v.to(home), v.to(home + u * d), v.to(home + (u + pv) * d), v.to(home + pv * d)]), Color(0.55, 0.4, 0.27))
			"track":
				_rect(ci, v, r, TRACK)
				_rect(ci, v, r.grow(-minf(r.size.x, r.size.y) * 0.16), FIELD)
			"basketball", "tennis", "games":
				_rect(ci, v, r, COURT)
			"pool":
				_rect(ci, v, r, Color(0.7, 0.68, 0.62))
				_rect(ci, v, r.grow(-Parks.POOL_DECK), POOL)
			"parking", "dropoff":
				_rect(ci, v, r, LOT)
			"playground":
				_rect(ci, v, r, Color(0.62, 0.42, 0.3))
			_:
				_rect(ci, v, r, HALL)


static func _draw_river(ci: CanvasItem, v: View, plan: CityPlan, rv: LaRiver) -> void:
	var c: Dictionary = Minimap.COLORS
	var ir := rv.index_range(v.area, 60.0)
	if ir.y <= ir.x:
		return
	var stride := maxi(1, int(6.0 / maxf(v.ppm, 0.01) / 4.0))
	var line := PackedVector2Array()
	for i in range(ir.x, ir.y + 1, stride):
		line.append(v.to(rv.pts[i]))
	line.append(v.to(rv.pts[ir.y]))
	if line.size() < 2:
		return
	var s_mid := rv.run[(ir.x + ir.y) / 2]
	ci.draw_polyline(line, c.river, v.w(rv.top_half(s_mid) * 2.0, 2.0), v.aa)
	ci.draw_polyline(line, c.river_water, v.w(LaRiver.lf_half() * 2.0, 1.0), v.aa)
	if v.ppm < 0.15:
		return
	for br: Dictionary in rv.bridges(plan):
		var p: Vector2 = br.p
		if not v.area.has_point(p):
			continue
		var u: Vector2 = br.along
		var o: Vector2 = br.p0
		_line(ci, v, o + u * float(br.t0), o + u * float(br.t1), c.road, v.w(float(br.width), 1.5))


static func _draw_airport(ci: CanvasItem, v: View, macro: MacroMap) -> void:
	var c: Dictionary = Minimap.COLORS
	var ar := macro.airport_rect
	if not ar.intersects(v.area):
		return
	for rz in macro.runway_zs:
		var a := Vector2(ar.position.x + 20.0, rz)
		var b := Vector2(ar.end.x - 20.0, rz)
		_line(ci, v, a, b, c.road_edge, v.w(macro.runway_width + 4.0, 4.0))
		_line(ci, v, a, b, Color(0.62, 0.62, 0.64), v.w(macro.runway_width, 3.0))
		if v.ppm > 0.25:
			_line(ci, v, a + Vector2(30, 0), b - Vector2(30, 0), Color(1, 1, 1, 0.8), v.w(0.9, 1.0))
	_line(ci, v, Vector2(ar.position.x + 20.0, macro.taxiway_z), Vector2(Airport.HANGAR_WEST_X - 10.0, macro.taxiway_z), Color(0.5, 0.5, 0.52), v.w(macro.taxiway_width, 1.5))
	var arc := PackedVector2Array()
	for i in 17:
		var t := lerpf(-Airport.CONCOURSE_ARC, Airport.CONCOURSE_ARC, float(i) / 16.0)
		arc.append(Airport.arc_point(t, Airport.CONCOURSE_RADIUS))
	_poly(ci, v, arc, Color(0.48, 0.47, 0.5), v.w(Airport.CONCOURSE_HALF * 2.0, 2.0))


## The piers: decks out over the surf, from the lamp rows Weather mirrors in the sea.
static func _draw_piers(ci: CanvasItem, v: View) -> void:
	for lm: Dictionary in Landmarks.all():
		var id := str(lm.id)
		if not id.ends_with("pier"):
			continue
		var at: Vector2 = lm.anchor
		if not v.area.grow(400.0).has_point(at):
			continue
		match id:
			"pier":
				_pier_deck(ci, v, Vector2(at.x + 5.0, at.y), Vector2(at.x - 262.0, at.y), 25.0)
			"manhattan_pier":
				var pier_len := LandmarkBeachPiers.MH_LENGTH
				_pier_deck(ci, v, Vector2(at.x, at.y), Vector2(at.x - pier_len, at.y), LandmarkBeachPiers.MH_WIDTH)
				ci.draw_circle(v.to(Vector2(at.x - pier_len + LandmarkBeachPiers.MH_END_RADIUS, at.y)), v.w(LandmarkBeachPiers.MH_END_RADIUS, 2.0) * 0.5 + v.w(2.0, 1.0), PIER_EDGE)
				ci.draw_circle(v.to(Vector2(at.x - pier_len + LandmarkBeachPiers.MH_END_RADIUS, at.y)), v.w(LandmarkBeachPiers.MH_END_RADIUS, 2.0) * 0.5, PIER)
			"redondo_pier":
				var root := at.x - LandmarkBeachPiers.RD_ROOT_X
				var bend := Vector2(root - LandmarkBeachPiers.RD_STRAIGHT, at.y)
				var r := LandmarkBeachPiers.RD_HALF_SPAN
				var dw := LandmarkBeachPiers.RD_DECK_W
				var shoe := PackedVector2Array([Vector2(at.x, at.y - r), Vector2(bend.x, at.y - r)])
				for k in 13:
					var a := -PI * 0.5 - PI * float(k) / 12.0
					shoe.append(bend + Vector2(cos(a), sin(a)) * r)
				shoe.append(Vector2(at.x, at.y + r))
				_poly(ci, v, shoe, PIER_EDGE, v.w(dw + 3.0, 3.0))
				_poly(ci, v, shoe, PIER, v.w(dw, 2.0))


static func _pier_deck(ci: CanvasItem, v: View, a: Vector2, b: Vector2, width: float) -> void:
	_line(ci, v, a, b, PIER_EDGE, v.w(width + 3.0, 3.5))
	_line(ci, v, a, b, PIER, v.w(width, 2.2))


## The Esplanade replica (ReplicaAreas): its road, from kerb to kerb.
static func _draw_replica(ci: CanvasItem, v: View, macro: MacroMap) -> void:
	var rep: ReplicaAreas = macro.replica
	if rep == null or rep.pts.size() < 2:
		return
	var c: Dictionary = Minimap.COLORS
	var stride := maxi(1, int(3.0 / maxf(v.ppm, 0.01) / ReplicaAreas.STEP))
	var line := PackedVector2Array()
	var near := false
	var width := 12.0
	for i in range(0, rep.pts.size(), stride):
		if v.area.grow(60.0).has_point(rep.pts[i]):
			near = true
		line.append(rep.pts[i])
	if not near:
		return
	var mid: Dictionary = rep.sec[rep.sec.size() / 2]
	if mid.has("kerb_e") and mid.has("kerb_w"):
		width = absf(float(mid.kerb_e) - float(mid.kerb_w))
	_poly(ci, v, line, c.road_edge, v.w(width, 1.6) + 2.0 * v.k / v.ppm)
	_poly(ci, v, line, c.road, v.w(width, 1.6))


static func _draw_hill_roads(ci: CanvasItem, v: View, hr: HillRoads) -> void:
	var c: Dictionary = Minimap.COLORS
	var reach := v.area.grow(40.0)
	if _hill_bounds.size() != hr.roads.size():
		_hill_bounds.clear()
		for road: Dictionary in hr.roads:
			_hill_bounds.append(Freeway._bounds(road.points).grow(float(road.width)))
	for k in hr.roads.size():
		if not _hill_bounds[k].intersects(reach):
			continue
		var road: Dictionary = hr.roads[k]
		if bool(road.get("drive", false)) and v.ppm < 0.35:
			continue
		var pts: PackedVector2Array = road.points
		var wd: float = road.width
		var run := PackedVector2Array()
		for i in pts.size():
			var inside := reach.has_point(pts[i]) or (i > 0 and reach.has_point(pts[i - 1])) or (i + 1 < pts.size() and reach.has_point(pts[i + 1]))
			if inside:
				run.append(pts[i])
			elif run.size() > 0:
				_hill_run(ci, v, run, wd, c)
				run = PackedVector2Array()
		_hill_run(ci, v, run, wd, c)


static func _hill_run(ci: CanvasItem, v: View, run: PackedVector2Array, wd: float, c: Dictionary) -> void:
	if run.size() < 2:
		return
	_poly(ci, v, run, c.road_edge, v.w(wd, 1.2) + 2.0 * v.k / v.ppm)
	_poly(ci, v, run, c.hill_road, v.w(wd, 1.2))


static func _draw_freeways(ci: CanvasItem, v: View, fw: Freeway) -> void:
	for pass_k in 3:
		for route: Dictionary in fw.routes:
			var pts: PackedVector2Array = route.points
			if not Freeway._bounds(pts).grow(80.0).intersects(v.area):
				continue
			var wd: float = route.width
			match pass_k:
				0:
					_poly(ci, v, pts, FREEWAY_EDGE, v.w(wd, 3.4) + 3.0 * v.k / v.ppm)
				1:
					_poly(ci, v, pts, FREEWAY, v.w(wd, 3.4))
				2:
					if v.ppm > 0.25:
						_poly(ci, v, pts, FREEWAY_LINE, v.w(1.2, 1.0))
	if v.ppm < 0.2:
		return
	var c: Dictionary = Minimap.COLORS
	for r: Dictionary in fw.ramps:
		var pos: Vector2 = r.pos
		if not v.area.has_point(pos):
			continue
		var path := Freeway.ramp_path(r)
		_poly(ci, v, path, FREEWAY_EDGE, v.w(Freeway.RAMP_WIDTH, 2.0) + 2.0 * v.k / v.ppm)
		_poly(ci, v, path, c.road, v.w(Freeway.RAMP_WIDTH, 2.0))


## The Coral Line: solid where it runs in the open, a dashed pale line where it is underground.
static func _draw_rail(ci: CanvasItem, v: View, rail: LightRail) -> void:
	if rail.pts.size() < 2:
		return
	var stride := maxi(1, int(4.0 / maxf(v.ppm, 0.01) / LightRail.STEP))
	var w := v.w(LightRail.TRACK_HALF * 4.0, 2.6)
	var runs: Array = []
	var cur := PackedVector2Array()
	var cur_tunnel := rail.mode[0] == LightRail.Mode.TUNNEL
	var near := false
	for i in range(0, rail.pts.size(), stride):
		var p := rail.pts[i]
		if v.area.grow(100.0).has_point(p):
			near = true
		var t := rail.mode[i] == LightRail.Mode.TUNNEL
		if t != cur_tunnel and cur.size() > 0:
			cur.append(p)
			runs.append([cur, cur_tunnel])
			cur = PackedVector2Array()
			cur_tunnel = t
		cur.append(p)
	cur.append(rail.pts[rail.pts.size() - 1])
	runs.append([cur, cur_tunnel])
	if not near:
		return
	for r: Array in runs:
		var pts: PackedVector2Array = r[0]
		if bool(r[1]):
			var dash := PackedVector2Array()
			for p in pts:
				dash.append(v.to(p))
			if dash.size() >= 2:
				ci.draw_dashed_line(dash[0], dash[dash.size() - 1], Color(RAIL, 0.85), w * 0.7, 8.0 * v.k / v.ppm, v.aa)
		else:
			_poly(ci, v, pts, INK, w + 2.4 * v.k / v.ppm)
			_poly(ci, v, pts, RAIL, w)


# --- Marks: upright, screen-sized ---------------------------------------------------------------

## Draws `fn` (a Callable taking the CanvasItem) upright at canvas point `p`.
static func upright(ci: CanvasItem, v: View, p: Vector2, fn: Callable) -> void:
	ci.draw_set_transform_matrix(v.base * Transform2D(0.0, p) * Transform2D(-v.yaw, Vector2.ZERO))
	fn.call(ci)
	ci.draw_set_transform_matrix(v.base)


## A screen point of canvas point `p` (canvas -> screen through base).
static func _screen(v: View, p: Vector2) -> Vector2:
	return v.base * p


static func draw_marks(ci: CanvasItem, v: View, plan: CityPlan, data: MapData) -> void:
	var taken: Array[Rect2] = []
	if plan.macro and plan.macro.freeway:
		_draw_shields(ci, v, plan.macro.freeway, taken)
	var rail := LightRail.of(plan)
	if rail:
		_draw_stations(ci, v, rail, taken)
	if v.full:
		_draw_district_names(ci, v, data, taken)
	if plan.macro:
		_draw_landmarks(ci, v, taken)
	if v.full and v.ppm > 0.35:
		_draw_street_names(ci, v, plan, data, taken)


static func _free(taken: Array[Rect2], r: Rect2) -> bool:
	for t in taken:
		if t.intersects(r):
			return false
	return true


static func _on_screen(v: View, sp: Vector2, margin: float) -> bool:
	return sp.x > margin and sp.y > margin and sp.x < v.screen.x - margin and sp.y < v.screen.y - margin


## Freeway shields: the game's own route number on a teal badge, spaced along each route.
static func _draw_shields(ci: CanvasItem, v: View, fw: Freeway, taken: Array[Rect2]) -> void:
	var spacing_px := 260.0 if v.full else 150.0
	for route: Dictionary in fw.routes:
		var pts: PackedVector2Array = route.points
		var number := str(FreewayKit.route_number(str(route.name)))
		var since := spacing_px * 0.5
		for i in range(1, pts.size()):
			var a := _screen(v, v.to(pts[i - 1]))
			var b := _screen(v, v.to(pts[i]))
			since += a.distance_to(b)
			if since < spacing_px or not _on_screen(v, b, 18.0):
				continue
			var box := Rect2(b - Vector2(15, 13), Vector2(30, 26))
			if not _free(taken, box):
				continue
			since = 0.0
			taken.append(box)
			upright(ci, v, v.to(pts[i]), func(c: CanvasItem) -> void: shield(c, number))


## The route badge: a rounded, notched shield in teal with a white rim (original, not any real
## highway marker).
static func shield(ci: CanvasItem, number: String) -> void:
	var w := 11.0 + 3.5 * float(number.length())
	var top := -10.0
	var pts := PackedVector2Array([Vector2(-w, top + 3.0), Vector2(-w + 3.0, top), Vector2(-2.5, top),
		Vector2(0.0, top + 2.5), Vector2(2.5, top), Vector2(w - 3.0, top), Vector2(w, top + 3.0),
		Vector2(w, 4.0), Vector2(0.0, 11.0), Vector2(-w, 4.0)])
	var rim := PackedVector2Array()
	for p in pts:
		rim.append(p * 1.0 + p.normalized() * 1.8)
	ci.draw_colored_polygon(rim, Color(0.0, 0.0, 0.0, 0.55))
	ci.draw_colored_polygon(pts, SHIELD)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(0.95, 0.97, 0.98), 1.5, true)
	var f := font(true)
	var tw := f.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	ci.draw_string(f, Vector2(-tw * 0.5, 3.5), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


static func _draw_stations(ci: CanvasItem, v: View, rail: LightRail, taken: Array[Rect2]) -> void:
	var named := v.full and v.ppm > 0.3 or not v.full and v.ppm > 0.4
	for st: Dictionary in rail.stations:
		var p: Vector2 = st.pos
		var cp := v.to(p)
		var sp := _screen(v, cp)
		if not _on_screen(v, sp, 6.0):
			continue
		var r := 5.5 if bool(st.terminus) else 4.5
		upright(ci, v, cp, func(c: CanvasItem) -> void:
			c.draw_circle(Vector2.ZERO, r + 1.8, INK)
			c.draw_circle(Vector2.ZERO, r, Color.WHITE)
			c.draw_circle(Vector2.ZERO, r - 2.0, RAIL))
		taken.append(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0))
		if named:
			var txt := str(st.name)
			var size := 10
			var tw := font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var box := Rect2(sp + Vector2(r + 3.0, -7.0), Vector2(tw + 4.0, 13.0))
			if _free(taken, box):
				taken.append(box)
				upright(ci, v, cp, func(c: CanvasItem) -> void: _text(c, Vector2(r + 4.0, 4.0), txt, size, Color(1.0, 0.86, 0.82), false))


static func _draw_district_names(ci: CanvasItem, v: View, data: MapData, taken: Array[Rect2]) -> void:
	if v.ppm > 0.6:
		return
	var size := 15 if v.ppm < 0.12 else 18
	for l: Dictionary in data.district_labels:
		var sp := _screen(v, v.to(l.pos))
		if not _on_screen(v, sp, 40.0):
			continue
		var txt := " ".join(str(l.name).split(""))
		var tw := font(true).get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var box := Rect2(sp - Vector2(tw * 0.5, size), Vector2(tw, size * 1.4))
		if not _free(taken, box):
			continue
		taken.append(box)
		_text(ci, sp + Vector2(-tw * 0.5, size * 0.4), txt, size, DISTRICT_TEXT, true)


static func _draw_landmarks(ci: CanvasItem, v: View, taken: Array[Rect2]) -> void:
	var show_minor := v.full and v.ppm > 0.6
	var labels := not v.full or v.ppm > 0.08
	var placed: Array = []
	for lm: Dictionary in Landmarks.all():
		var id := str(lm.id)
		if id in MINOR and not show_minor:
			continue
		# The downtown towers are a cluster of glyphs from the basin; one name stands for them.
		if id.begins_with("dt_") and v.full and v.ppm < 0.22:
			continue
		var a: Vector2 = lm.anchor
		var cp := v.to(a)
		var sp := _screen(v, cp)
		if not _on_screen(v, sp, 8.0):
			continue
		var kind: String = GLYPHS.get(id, "tower" if id.begins_with("dt_") else "star")
		var gr := 7.5
		var gbox := Rect2(sp - Vector2(gr, gr), Vector2(gr, gr) * 2.0)
		var crowded := false
		for q: Vector2 in placed:
			if q.distance_to(sp) < gr * 1.6:
				crowded = true
				break
		if crowded:
			continue
		placed.append(sp)
		upright(ci, v, cp, func(c: CanvasItem) -> void: glyph(c, kind, gr))
		taken.append(gbox)
		if not labels:
			continue
		var label_text: String = Minimap.LANDMARK_NAMES.get(id, id)
		var size := 11
		var tw := font(true).get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var box := Rect2(sp + Vector2(gr + 2.0, -7.0), Vector2(tw + 6.0, 14.0))
		if not _free(taken, box):
			continue
		taken.append(box)
		upright(ci, v, cp, func(c: CanvasItem) -> void: _text(c, Vector2(gr + 4.0, 4.0), label_text, size, LABEL, true))


static func _text(ci: CanvasItem, at: Vector2, txt: String, size: int, col: Color, bold: bool) -> void:
	var f := font(bold)
	ci.draw_string_outline(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0.02, 0.025, 0.035, 0.85))
	ci.draw_string(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## A landmark glyph: a dark disc with a coloured ring and a small white symbol, `r` px.
static func glyph(ci: CanvasItem, kind: String, r: float) -> void:
	var ring: Color = GLYPH_COLORS.get(kind, Color(1.0, 0.45, 0.4))
	ci.draw_circle(Vector2(0.0, 1.0), r + 1.5, Color(0, 0, 0, 0.4))
	ci.draw_circle(Vector2.ZERO, r, INK)
	ci.draw_arc(Vector2.ZERO, r - 0.9, 0.0, TAU, 24, ring, 1.8, true)
	var s := r * 0.55
	var w := Color(1, 1, 1, 0.95)
	match kind:
		"tower":
			ci.draw_rect(Rect2(-s * 0.9, -s * 0.2, s * 0.5, s * 1.2), w)
			ci.draw_rect(Rect2(-s * 0.25, -s, s * 0.5, s * 2.0), w)
			ci.draw_rect(Rect2(s * 0.4, -s * 0.55, s * 0.5, s * 1.55), w)
		"civic":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-s, -s * 0.25), Vector2(0, -s), Vector2(s, -s * 0.25)]), w)
			for x: float in [-0.7, -0.1, 0.5]:
				ci.draw_rect(Rect2(x * s, -s * 0.15, s * 0.22, s * 0.85), w)
			ci.draw_rect(Rect2(-s, s * 0.75, s * 2.0, s * 0.25), w)
		"dome":
			ci.draw_circle(Vector2(0, s * 0.1), s * 0.62, w)
			ci.draw_rect(Rect2(-s * 0.8, s * 0.1, s * 1.6, s * 0.8), w)
			ci.draw_line(Vector2(0, -s * 0.5), Vector2(0, -s), w, 1.2)
		"plane":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(0, -s * 1.1), Vector2(s * 0.18, -s * 0.6), Vector2(s * 0.18, -s * 0.15),
				Vector2(s * 1.05, s * 0.3), Vector2(s * 1.05, s * 0.5), Vector2(s * 0.18, s * 0.3), Vector2(s * 0.15, s * 0.75),
				Vector2(s * 0.45, s * 1.0), Vector2(-s * 0.45, s * 1.0), Vector2(-s * 0.15, s * 0.75), Vector2(-s * 0.18, s * 0.3),
				Vector2(-s * 1.05, s * 0.5), Vector2(-s * 1.05, s * 0.3), Vector2(-s * 0.18, -s * 0.15), Vector2(-s * 0.18, -s * 0.6)]), w)
		"ship":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-s, s * 0.1), Vector2(s, s * 0.1), Vector2(s * 0.7, s * 0.75), Vector2(-s * 0.75, s * 0.75)]), w)
			ci.draw_rect(Rect2(-s * 0.55, -s * 0.5, s * 0.5, s * 0.5), w)
			ci.draw_rect(Rect2(s * 0.05, -s * 0.25, s * 0.5, s * 0.25), w)
		"pier":
			ci.draw_rect(Rect2(-s, -s * 0.2, s * 2.0, s * 0.4), w)
			for x: float in [-0.75, -0.25, 0.25, 0.75]:
				ci.draw_rect(Rect2(x * s - s * 0.08, s * 0.2, s * 0.16, s * 0.75), w)
		"bag":
			ci.draw_rect(Rect2(-s * 0.75, -s * 0.3, s * 1.5, s * 1.25), w)
			ci.draw_arc(Vector2(0, -s * 0.3), s * 0.42, PI, TAU, 10, w, 1.4, true)
		"cup":
			ci.draw_rect(Rect2(-s * 0.7, -s * 0.5, s * 1.1, s * 1.3), w)
			ci.draw_arc(Vector2(s * 0.45, s * 0.1), s * 0.38, -PI * 0.5, PI * 0.5, 10, w, 1.4, true)
		"venue":
			ci.draw_arc(Vector2.ZERO, s * 0.82, 0.0, TAU, 20, w, 1.6, true)
			ci.draw_circle(Vector2.ZERO, s * 0.35, w)
		"tree":
			ci.draw_circle(Vector2(0, -s * 0.25), s * 0.7, w)
			ci.draw_rect(Rect2(-s * 0.12, s * 0.2, s * 0.24, s * 0.8), w)
		"rail":
			ci.draw_rect(Rect2(-s * 0.6, -s * 0.9, s * 1.2, s * 1.4), w)
			ci.draw_line(Vector2(-s * 0.5, s * 1.0), Vector2(-s * 0.2, s * 0.5), w, 1.2)
			ci.draw_line(Vector2(s * 0.5, s * 1.0), Vector2(s * 0.2, s * 0.5), w, 1.2)
		_:
			var star := PackedVector2Array()
			for k in 10:
				var a := -PI * 0.5 + PI * float(k) / 5.0
				star.append(Vector2(cos(a), sin(a)) * (s * 1.05 if k % 2 == 0 else s * 0.45))
			ci.draw_colored_polygon(star, w)


## Street names along the visible roads, each once, avenues first; vertical roads read upward.
## A name goes in the middle of the road's visible run, centred on the block it falls in.
static func _draw_street_names(ci: CanvasItem, v: View, plan: CityPlan, data: MapData, taken: Array[Rect2]) -> void:
	var size := 10 if v.ppm < 0.9 else 12
	var screen_area := Rect2(Vector2.ZERO, v.screen)
	# Each road's visible segments (screen rects), in order along it.
	var runs := {}
	for i in data.indices_in(v.area, true):
		var rd: Dictionary = data.roads[i]
		if not rd.avenue and v.ppm < 0.6:
			continue
		var r: Rect2 = rd.rect
		var sr := Rect2(_screen(v, v.to(r.position)), (_screen(v, v.to(r.end)) - _screen(v, v.to(r.position)))).abs()
		var vis := sr.intersection(screen_area.grow(-24.0))
		if vis.size.x <= 0.0 or vis.size.y <= 0.0:
			continue
		var key := Vector3i(int(rd.axis), int(rd.index), 1 if rd.avenue else 0)
		if not runs.has(key):
			runs[key] = []
		(runs[key] as Array).append(vis)
	for pass_avenue: int in [1, 0]:
		for key: Vector3i in runs:
			if key.z != pass_avenue:
				continue
			var segs: Array = runs[key]
			var vertical := key.x == CityPlan.AXIS_X
			var lo := INF
			var hi := -INF
			for sg: Rect2 in segs:
				lo = minf(lo, sg.position.y if vertical else sg.position.x)
				hi = maxf(hi, sg.end.y if vertical else sg.end.x)
			var mid_along := (lo + hi) * 0.5
			# The block segment the middle falls in (or the longest).
			var best: Rect2 = segs[0]
			for sg: Rect2 in segs:
				var a0 := sg.position.y if vertical else sg.position.x
				var a1 := sg.end.y if vertical else sg.end.x
				if mid_along >= a0 and mid_along <= a1:
					best = sg
					break
			var txt := plan.road_name(key.x, key.y)
			var tw := font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var along := best.size.y if vertical else best.size.x
			if along < tw + 24.0:
				continue
			var mid := best.get_center()
			var box := Rect2(mid - Vector2(size * 0.7, tw * 0.5 + 4.0), Vector2(size * 1.4, tw + 8.0)) if vertical \
				else Rect2(mid - Vector2(tw * 0.5 + 4.0, size * 0.7), Vector2(tw + 8.0, size * 1.4))
			if not _free(taken, box):
				continue
			taken.append(box)
			if vertical:
				ci.draw_set_transform_matrix(Transform2D(-PI * 0.5, mid))
				_text(ci, Vector2(-tw * 0.5, size * 0.38), txt, size, STREET_TEXT, false)
				ci.draw_set_transform_matrix(v.base)
			else:
				_text(ci, mid + Vector2(-tw * 0.5, size * 0.38), txt, size, STREET_TEXT, false)


# --- Route, waypoint, units, player ------------------------------------------------------------

## The GPS route from `from_index` on (the segment the player is on), a violet line with a casing.
static func draw_route(ci: CanvasItem, v: View, pts: PackedVector2Array, from_pt: Vector2, from_index: int) -> void:
	if pts.size() < 2:
		return
	var line := PackedVector2Array([v.to(from_pt)])
	for i in range(from_index + 1, pts.size()):
		line.append(v.to(pts[i]))
	if line.size() < 2:
		return
	var w := v.w(6.0, 4.0)
	ci.draw_polyline(line, ROUTE_EDGE, w + 3.0 * v.k / v.ppm, true)
	ci.draw_polyline(line, ROUTE_COLOR, w, true)


## The waypoint: a violet pin with a white core (upright, screen sized).
static func waypoint_pin(ci: CanvasItem, pulse: float) -> void:
	var r := 8.0
	ci.draw_circle(Vector2.ZERO, r + 5.0 + 2.0 * sin(pulse * 4.0), Color(ROUTE_COLOR, 0.25))
	var pin := PackedVector2Array([Vector2(0, 0)])
	for k in 13:
		var a := PI * 0.15 + PI * 0.7 * float(k) / 12.0 + PI
		pin.append(Vector2(cos(a), sin(a)) * r + Vector2(0, -r * 1.7))
	ci.draw_circle(Vector2(0, -r * 1.7), r + 1.5, ROUTE_EDGE)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 1.5), Vector2(-r * 0.75, -r * 1.2), Vector2(r * 0.75, -r * 1.2)]), ROUTE_EDGE)
	ci.draw_circle(Vector2(0, -r * 1.7), r, ROUTE_COLOR)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(-r * 0.6, -r * 1.25), Vector2(r * 0.6, -r * 1.25)]), ROUTE_COLOR)
	ci.draw_circle(Vector2(0, -r * 1.7), r * 0.38, Color.WHITE)


## Police (group "wanted") and fire / ambulance units (group "emergency_unit") as flashing blips.
static func draw_units(ci: CanvasItem, v: View, city: Node, pulse: float, clamp_to: Callable) -> void:
	var tree := ci.get_tree()
	var phase := fmod(pulse * 2.2, 1.0) < 0.5
	var red := Color(1.0, 0.18, 0.16)
	var blue := Color(0.22, 0.45, 1.0)
	var police := tree.get_first_node_in_group("wanted")
	if police:
		if int(police.get("stars")) > 0 and police.call("show_search_area"):
			var sc: Vector3 = city.world_position(police.call("search_center"))
			var cp := v.to(Vector2(sc.x, sc.z))
			var sr := float(police.call("search_radius_now")) * v.k
			var breathe := 0.5 + 0.5 * sin(pulse * 3.0)
			ci.draw_circle(cp, sr, Color(red.r, red.g, red.b, 0.10 + 0.06 * breathe))
			ci.draw_arc(cp, sr, 0.0, TAU, 64, Color(blue.r, blue.g, blue.b, 0.55), 2.0, true)
		for car in police.get("cruisers"):
			if is_instance_valid(car):
				var p: Vector2 = clamp_to.call(_unit_point(v, city, car))
				ci.draw_circle(p, 6.5, INK)
				ci.draw_circle(p, 5.0, red if phase else blue)
				ci.draw_circle(p, 2.0, Color.WHITE)
		for o in police.get("officers"):
			if is_instance_valid(o):
				var p2: Vector2 = clamp_to.call(_unit_point(v, city, o))
				ci.draw_circle(p2, 4.0, INK)
				ci.draw_circle(p2, 2.8, blue if phase else red)
	for unit in tree.get_nodes_in_group("emergency_unit"):
		var n := unit as Node3D
		if n == null or not n.is_inside_tree():
			continue
		var p3: Vector2 = clamp_to.call(_unit_point(v, city, n))
		var engine := int(n.get("kind")) == 0
		ci.draw_rect(Rect2(p3 - Vector2(6, 6), Vector2(12, 12)), INK)
		ci.draw_rect(Rect2(p3 - Vector2(4.5, 4.5), Vector2(9, 9)), (Color(1.0, 0.3, 0.2) if engine else Color.WHITE) if phase else Color(1.0, 0.55, 0.2))
		ci.draw_rect(Rect2(p3 - Vector2(1, 3.5), Vector2(2, 7)), Color(0.85, 0.1, 0.1) if not engine else Color.WHITE)
		ci.draw_rect(Rect2(p3 - Vector2(3.5, 1), Vector2(7, 2)), Color(0.85, 0.1, 0.1) if not engine else Color.WHITE)


static func _unit_point(v: View, city: Node, n: Node3D) -> Vector2:
	var w: Vector3 = city.world_position(n.global_position)
	return v.to(Vector2(w.x, w.z))


## The player's arrow at canvas point `c`, pointing `forward` (canvas direction).
static func player_arrow(ci: CanvasItem, c: Vector2, forward: Vector2, pulse: float, scale: float = 1.0) -> void:
	var right := Vector2(-forward.y, forward.x)
	var glow := (10.0 + 4.0 * sin(pulse * 4.0)) * scale
	ci.draw_circle(c, glow, Color(0.35, 0.75, 1.0, 0.25))
	var f := forward * scale
	var r := right * scale
	var tri := PackedVector2Array([c + f * 12.0, c - f * 8.0 + r * 8.0, c - f * 3.5, c - f * 8.0 - r * 8.0])
	ci.draw_colored_polygon(tri, Color(0.35, 0.75, 1.0))
	ci.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color.WHITE, 1.5, true)
