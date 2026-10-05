class_name FreewayKit
extends RefCounted
## The freeway decks as a 2026 game shows them (VISUAL_ROADMAP #43): what CityChunk._build_freeway()
## builds for every deck segment a chunk owns, into the same few meshes as before -
##   `top`   the asphalt (PropFactory.road(), unchanged),
##   `body`  everything structural on `shaders/freeway_structure.gdshader`: the box-girder deck
##           with its cantilevers and fascias, New Jersey-profile barriers at both edges and down
##           the median, bents (columns with flared heads, a bent cap, bearing pads, downpipes),
##           truss sign gantries with catwalks and sign lights, median light standards with twin
##           cobra heads, call boxes, CCTV poles, postmile paddles, tyre debris,
##   `paint` everything flat on `shaders/freeway_paint.gdshader`: worn lane paint, Botts' dots and
##           retroreflective raised markers, the carpool lane's double yellow and diamonds,
##           expansion joints, scupper grates, and the overhead guide signs' faces, lettering,
##           shields, arrows and exit tabs,
##   `glow`  the light standards' pools on the deck at night (light_pool.gdshader, additive),
## so a chunk with a deck draws four meshes (it was three). What a vertex IS rides in its colour's
## alpha (`kind / KIND_SCALE`); its colour is sRGB in the rgb, decoded in the shaders; UV is
## (metres along the route, metres up the feature) on the structure and per kind on the paint;
## UV2 carries a flag (structure) or the direction a retroreflector faces (paint).
##
## Everything is hashed from the seed, the route and the segment index: no rng is drawn, so
## nothing else in the chunk moves. Lettering is TextMesh geometry merged into the paint mesh
## (cached per string), at FULL chunks only; an LOD chunk keeps the deck, barriers, bents, the
## gantries' blank boards, the light standards and their pools, and the plain lane lines.
##
## Names on signs are invented or public street names; route numbers are this game's own
## (ROUTE_NUMBERS), never the real routes'.

## Vertex kinds (colour alpha * KIND_SCALE). Structure:
const S_CONCRETE := 1
const S_BARRIER := 2
const S_PILLAR := 3
const S_SOFFIT := 4
const S_STEEL := 5
const S_PAINTED := 6
const S_LENS := 7
const S_RUBBER := 8
const S_FASCIA := 9
## Paint:
const P_LINE := 1
const P_DASH := 2
const P_BOTTS := 3
const P_RPM := 4
const P_DIAMOND := 5
const P_JOINT := 6
const P_SIGN := 8
const P_GRATE := 9
const KIND_SCALE := 32.0

## The deck's cross section: the median barrier's half base, the barriers' height and base.
const MEDIAN_HALF := 0.305
const BARRIER_H := 0.95
const BARRIER_BASE := 0.42
## Box girder under the deck: the fascia's depth, where the cantilever meets the web, the web's
## foot (all metres in from the deck edge / down from the deck top).
const FASCIA_DEPTH := 0.55
const CANTILEVER := 3.2
const WEB_FOOT := 3.8
## Markings (CA practice, rounded): Botts' dot cycle of 4 dots and one marker, the dashed line's
## cycle and dash, the carpool diamond's spacing in segments, an expansion joint every so many
## bents, scupper grates along the edge.
const BOTTS_CYCLE := 7.32
const DIAMOND_EVERY := 8
const JOINT_EVERY_BENTS := 3
const SCUPPER_SPACING := 12.0
## Light standards on the median: every LIGHT_EVERY segments, LIGHT_HEIGHT above the deck, arms
## LIGHT_ARM out each side; the pool each throws on the deck (metres along, across).
const LIGHT_EVERY := 2
const LIGHT_HEIGHT := 12.5
const LIGHT_ARM := 2.8
const POOL_SIZE := Vector2(46.0, 16.0)
## The pool an under-deck light throws on the street below (metres along, across).
const UNDER_POOL := Vector2(22.0, 16.0)
## How strong a pool is (light_pool's COLOR.a): sodium is a warmer wash than LED. The pool
## material's strength and falloff (pool_material()).
const POOL_SODIUM := 0.5
const POOL_LED := 0.42
const POOL_STRENGTH := 1.4
const POOL_FALLOFF := 0.75
## The gantry: posts on the edge barriers, truss chord heights, and its signs.
const GANTRY_LOW := 6.9
const GANTRY_HIGH := 8.5
const GANTRY_DEPTH := 1.1
const SIGN_BOTTOM := 5.6
const SIGN_HEIGHT := 3.6
## Roadside furniture (FULL only), one roll per segment: call box, CCTV pole, postmile paddle.
const CALLBOX_EVERY := 21
const CAMERA_EVERY := 37
const POSTMILE_EVERY := 7

## This game's own route numbers, keyed by a word of Freeway's route names.
const ROUTE_NUMBERS := {"Coast": 47, "Century": 58, "Hollywood": 21, "Harbor": 33, "Santa Monica": 14}
## Routes lit by sodium lamps (is_sodium()); the rest are LED.
const SODIUM_ROUTES := ["Harbor", "Hollywood", "Santa Monica"]
## Invented destinations a guide sign may name (public words, no real places).
const DESTINATIONS := ["Civic Center", "Port Terminal", "North Valley", "Canyon Pass", "Beach Cities",
	"Arts District", "Mesa Flats", "Bay Docks", "Sunset Heights", "Palm Hollow", "Rio Seco",
	"Las Lomas", "Harbor Point", "Airport", "Vista Del Mar", "Rancho Verde"]

const WHITE := Color(0.93, 0.93, 0.90)
const YELLOW := Color(0.96, 0.74, 0.12)
const SIGN_GREEN := Color(0.0, 0.40, 0.24)
const SIGN_WHITE := Color(0.95, 0.95, 0.93)
const SIGN_BLACK := Color(0.05, 0.05, 0.05)
const SIGN_BLUE := Color(0.02, 0.22, 0.55)
const CONCRETE := Color(0.70, 0.69, 0.66)
const GALV := Color(0.62, 0.64, 0.65)
const POLE_GREY := Color(0.55, 0.56, 0.56)

static var _text_cache := {}
static var _structure_mat: ShaderMaterial
static var _paint_mat: ShaderMaterial
static var _pool_mat: ShaderMaterial
static var _traffic_mat: ShaderMaterial

var chunk: CityChunk
var plan: CityPlan
var full := true
var top := SurfaceTool.new()
var body := SurfaceTool.new()
var paint := SurfaceTool.new()
var glow := SurfaceTool.new()
## LOD chunks only: the decks' far traffic lights (far_traffic.gdshader), an additive skin.
var traffic := SurfaceTool.new()
var _traffic_any := false
var _glow_any := false
var _paint_any := false


func _init(c: CityChunk) -> void:
	chunk = c
	plan = c.plan
	full = c.level == CityChunk.Level.FULL
	for st: SurfaceTool in [top, body, paint, glow, traffic]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)


# --- Materials ------------------------------------------------------------------------------

static func structure_material() -> ShaderMaterial:
	if _structure_mat == null:
		_structure_mat = ShaderMaterial.new()
		_structure_mat.shader = load("res://shaders/freeway_structure.gdshader")
		_structure_mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
		_structure_mat.set_shader_parameter("concrete_rough", PropFactory.texture("concrete", "Roughness"))
	return _structure_mat


static func paint_material() -> ShaderMaterial:
	if _paint_mat == null:
		_paint_mat = ShaderMaterial.new()
		_paint_mat.shader = load("res://shaders/freeway_paint.gdshader")
	return _paint_mat


## The LOD decks' traffic lights (far_traffic.gdshader): past TrafficManager.freeway_range the
## decks carry the same moving head and tail lights as the far city's.
static func traffic_material() -> ShaderMaterial:
	if _traffic_mat == null:
		_traffic_mat = ShaderMaterial.new()
		_traffic_mat.shader = load("res://shaders/far_traffic.gdshader")
	return _traffic_mat


## A copy of a deck segment's top a hand over it, for the traffic lights: UV (metres along the
## route in the lights' period, metres across from the median), the route and the half width in
## UV2 and +s in the colour (x, z as 0..1).
func _traffic_skin(l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, dir: Vector2, half: float, run0: float, seg_len: float, ri: int) -> void:
	var s0 := fmod(run0, NightCity.PERIOD)
	var lift := Vector3(0.0, 0.12, 0.0)
	var col := Color(dir.x * 0.5 + 0.5, dir.y * 0.5 + 0.5, 0.0, 1.0)
	var corners := {"l0": [l0, Vector2(s0, -half)], "r0": [r0, Vector2(s0, half)],
		"l1": [l1, Vector2(s0 + seg_len, -half)], "r1": [r1, Vector2(s0 + seg_len, half)]}
	for k: String in ["l0", "r1", "r0", "l0", "l1", "r1"]:
		traffic.set_color(col)
		traffic.set_uv(corners[k][1])
		traffic.set_uv2(Vector2(float(ri) + 1.0, half))
		traffic.add_vertex(corners[k][0] + lift)
	_traffic_any = true


## The light pools' material: light_pool.gdshader with a broad, flat falloff. A road light is
## laid out to light the carriageway evenly; at the city lamps' falloff a 34 m pool was a small
## bright spot in a dark deck that read as a headlight beam.
static func pool_material() -> ShaderMaterial:
	if _pool_mat == null:
		_pool_mat = ShaderMaterial.new()
		_pool_mat.shader = load("res://shaders/light_pool.gdshader")
		_pool_mat.set_shader_parameter("tint", Color(1.0, 1.0, 1.0))
		_pool_mat.set_shader_parameter("strength", POOL_STRENGTH)
		_pool_mat.set_shader_parameter("falloff", POOL_FALLOFF)
	return _pool_mat


static func kind_color(c: Color, kind: int) -> Color:
	return Color(c.r, c.g, c.b, float(kind) / KIND_SCALE)


# --- Geometry helpers -----------------------------------------------------------------------

## One triangle facing `want`; the winding is fixed to match and the normal is set flat, so no
## caller has to think about winding (LandmarkGeo's rule).
func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3, col: Color,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, u2 := Vector2.ZERO) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(want) < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
		n = -n
	n = n.normalized()
	for i in 3:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv([ua, ub, uc][i])
		st.set_uv2(u2)
		st.add_vertex([a, b, c][i])


func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, col: Color,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO, u2 := Vector2.ZERO) -> void:
	tri(st, a, b, c, want, col, ua, ub, uc, u2)
	tri(st, a, c, d, want, col, ua, uc, ud, u2)


## A cross-section `pts` ((across, up) pairs in the deck frame, metres) swept from a3 to b3.
## Each edge faces away from `inside`; `cols[i]` is edge i's kind colour and `flags[i]` its UV2.x.
## UV is (metres along the route, the profile point's height; across the deck on the soffit).
func extrude(st: SurfaceTool, a3: Vector3, b3: Vector3, nrm: Vector2, run0: float, run1: float,
		pts: PackedVector2Array, inside: Vector2, cols: Array, flags: PackedFloat32Array) -> void:
	var n3 := Vector3(nrm.x, 0.0, nrm.y)
	for i in pts.size() - 1:
		var p := pts[i]
		var q := pts[i + 1]
		var e := q - p
		var on := Vector2(e.y, -e.x).normalized()
		if on.dot((p + q) * 0.5 - inside) < 0.0:
			on = -on
		var want := n3 * on.x + Vector3.UP * on.y
		# The soffit's UV.y is metres ACROSS the deck (its formwork pattern), everything else's the height.
		var soffit := int(round((cols[i] as Color).a * KIND_SCALE)) == S_SOFFIT
		var vp := p.x if soffit else p.y
		var vq := q.x if soffit else q.y
		quad(st, a3 + n3 * p.x + Vector3.UP * p.y, a3 + n3 * q.x + Vector3.UP * q.y,
			b3 + n3 * q.x + Vector3.UP * q.y, b3 + n3 * p.x + Vector3.UP * p.y, want, cols[i],
			Vector2(run0, vp), Vector2(run0, vq), Vector2(run1, vq), Vector2(run1, vp), Vector2(flags[i], 0.0))


## An oriented box: centre, three half-extent vectors. UV is (metres along `ax`, metres up from
## the box's bottom); UV2 is (flag, total height).
func box(st: SurfaceTool, c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, col: Color, flag := 0.0, skip_bottom := true) -> void:
	var h := ay.length() * 2.0
	var lx := ax.length()
	var faces := [[ax, ay, az], [-ax, ay, az], [ay, ax, az], [-ay, ax, az], [az, ax, ay], [-az, ax, ay]]
	for f: Array in faces:
		var n: Vector3 = f[0]
		if skip_bottom and n.normalized().dot(Vector3.UP) < -0.9:
			continue
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var corners := [c + n - u - v, c + n + u - v, c + n + u + v, c + n - u + v]
		var uvs := []
		for p: Vector3 in corners:
			var rel: Vector3 = p - c
			uvs.append(Vector2(rel.dot(ax) / maxf(lx, 0.001) + lx, rel.y + h * 0.5))
		quad(st, corners[0], corners[1], corners[2], corners[3], n, col, uvs[0], uvs[1], uvs[2], uvs[3], Vector2(flag, h))


## A tapered prism (pole, pipe) from `a` to `b`, `sides` faces, radii r0 at a and r1 at b.
func prism(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color, cap := true) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var other := axis.cross(side)
	var length_m := a.distance_to(b)
	for i in sides:
		var t0 := TAU * float(i) / sides
		var t1 := TAU * float(i + 1) / sides
		var d0 := side * cos(t0) + other * sin(t0)
		var d1 := side * cos(t1) + other * sin(t1)
		var want := (d0 + d1).normalized()
		var u0 := float(i) / sides * TAU * r0
		var u1 := float(i + 1) / sides * TAU * r0
		quad(st, a + d0 * r0, a + d1 * r0, b + d1 * r1, b + d0 * r1, want, col,
			Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, length_m), Vector2(u0, length_m), Vector2(0.0, length_m))
		if cap:
			tri(st, b, b + d0 * r1, b + d1 * r1, axis, col)


## A flat strip lying on the deck: `u` across (centre), `w` wide, from s0 to s1 of the segment.
## UV = (0..1 across, metres along the route); UV2 = the direction a marker faces (xz).
func strip(a3: Vector3, b3: Vector3, nrm: Vector2, u: float, w: float, s0: float, s1: float,
		run0: float, run1: float, col: Color, face: Vector2, lift := 0.035) -> void:
	var n3 := Vector3(nrm.x, 0.0, nrm.y)
	var up := Vector3(0.0, lift, 0.0)
	var p0 := a3.lerp(b3, s0) + up
	var p1 := a3.lerp(b3, s1) + up
	var r0 := lerpf(run0, run1, s0)
	var r1 := lerpf(run0, run1, s1)
	var lo := n3 * (u - w * 0.5)
	var hi := n3 * (u + w * 0.5)
	var want := (b3 - a3).cross(n3).normalized()
	if want.y < 0.0:
		want = -want
	quad(paint, p0 + lo, p0 + hi, p1 + hi, p1 + lo, want, col,
		Vector2(0.0, r0), Vector2(1.0, r0), Vector2(1.0, r1), Vector2(0.0, r1), face)
	_paint_any = true


## A light pool on the deck (additive, light_pool.gdshader): centre, along direction, size.
func pool(c: Vector3, along: Vector3, size: Vector2, col: Color) -> void:
	var ac := Vector3(-along.z, 0.0, along.x)
	var a := along * size.x * 0.5
	var b := ac * size.y * 0.5
	var corners := [c - a - b, c - a + b, c + a + b, c + a - b]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i: int in [0, 1, 2, 0, 2, 3]:
		glow.set_color(col)
		glow.set_normal(Vector3.UP)
		glow.set_uv(uvs[i])
		glow.add_vertex(corners[i])
	_glow_any = true


## A flat polygon (sign art) in a plane: `pts` in the plane's (right, up) metres, placed by `xf`
## (basis: right, up, out of the face). UV = the point inside the board (0..1, from `board`).
func flat_poly(pts: PackedVector2Array, xf: Transform3D, col: Color, board: Rect2, face: Vector2) -> void:
	var idx := Geometry2D.triangulate_polygon(pts)
	var out := xf.basis.z.normalized()
	for k in range(0, idx.size(), 3):
		var vs := []
		var us := []
		for j in 3:
			var p := pts[idx[k + j]]
			vs.append(xf * Vector3(p.x, p.y, 0.0))
			us.append((p - board.position) / board.size)
		tri(paint, vs[0], vs[1], vs[2], out, col, us[0], us[1], us[2], face)
	_paint_any = true


## A ring between two polygons with the same point count (a sign's border).
func ring(outer: PackedVector2Array, inner: PackedVector2Array, xf: Transform3D, col: Color, board: Rect2, face: Vector2) -> void:
	var out := xf.basis.z.normalized()
	var n := outer.size()
	for i in n:
		var j := (i + 1) % n
		var pts := [outer[i], outer[j], inner[j], inner[i]]
		var vs := []
		var us := []
		for p: Vector2 in pts:
			vs.append(xf * Vector3(p.x, p.y, 0.0))
			us.append((p - board.position) / board.size)
		quad(paint, vs[0], vs[1], vs[2], vs[3], out, col, us[0], us[1], us[2], us[3], face)


static func rounded_rect(r: Rect2, radius: float, per_corner := 4) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var centres := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	for ci in 4:
		for k in per_corner + 1:
			var ang := -PI * 0.5 + PI * 0.5 * (float(ci) + float(k) / per_corner)
			pts.append(centres[ci] + Vector2(cos(ang), sin(ang)) * rad)
	return pts


## Flat lettering geometry for `text` at cap height `height`, centred: [verts, indices, width].
static func text_geo(text: String, height: float) -> Array:
	var key := "%s|%.3f" % [text, height]
	if _text_cache.has(key):
		return _text_cache[key]
	var tm := TextMesh.new()
	tm.text = text
	# Coarse curves: a 40 cm letter on a sign 20 m up needs no more, and lettering is most of a
	# gantry's triangles.
	tm.font_size = 40
	tm.pixel_size = height / 40.0 * 1.4
	tm.depth = 0.0
	tm.curve_step = 4.0
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var arr := tm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX] if arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
	var ids = arr[Mesh.ARRAY_INDEX] if arr.size() > 0 else null
	var idx := PackedInt32Array()
	if ids == null or (ids as PackedInt32Array).is_empty():
		for k in verts.size():
			idx.append(k)
	else:
		idx = ids
	var lo := INF
	var hi := -INF
	for v in verts:
		lo = minf(lo, v.x)
		hi = maxf(hi, v.x)
	var geo := [verts, idx, maxf(hi - lo, 0.0)]
	_text_cache[key] = geo
	return geo


## Lettering into the paint mesh, centred at `at` (plane metres), at most `max_w` wide.
func letters(text: String, height: float, at: Vector2, xf: Transform3D, col: Color, board: Rect2, face: Vector2, max_w := 99.0) -> float:
	if not full or text == "":
		return 0.0
	var geo := text_geo(text, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var width: float = geo[2]
	var squeeze := minf(1.0, max_w / maxf(width, 0.001))
	var out := xf.basis.z.normalized()
	for k in range(0, idx.size() - 2, 3):
		var vs := []
		var us := []
		for j in 3:
			var v := verts[idx[k + j]]
			var p := at + Vector2(v.x * squeeze, v.y)
			vs.append(xf * Vector3(p.x, p.y, 0.0))
			us.append((p - board.position) / board.size)
		tri(paint, vs[0], vs[1], vs[2], out, col, us[0], us[1], us[2], face)
	_paint_any = true
	return width * squeeze


static func hash01(parts: Array) -> float:
	return float(hash(parts) & 0xFFFFFF) / float(0x1000000)


static func route_number(route_name: String) -> int:
	for key: String in ROUTE_NUMBERS:
		if route_name.contains(key):
			return ROUTE_NUMBERS[key]
	return 90


## The older routes keep their high-pressure sodium (the orange glow LA's freeways were known
## by); the newer ones are LED.
static func is_sodium(route_name: String) -> bool:
	for key: String in SODIUM_ROUTES:
		if route_name.contains(key):
			return true
	return false


static func cardinal(d: Vector2) -> String:
	if absf(d.x) > absf(d.y):
		return "EAST" if d.x > 0.0 else "WEST"
	return "SOUTH" if d.y > 0.0 else "NORTH"


## "OLIVE ST" -> "Olive St", "5TH ST" -> "5th St".
static func sign_case(s: String) -> String:
	var words := s.to_lower().split(" ", false)
	var out := PackedStringArray()
	for w in words:
		if w.length() > 0 and w[0] >= "a" and w[0] <= "z":
			w = w[0].to_upper() + w.substr(1)
		out.append(w)
	return " ".join(out)


# --- The build ------------------------------------------------------------------------------

## Builds every deck segment `chunk` owns; returns how many. Collision stays CityChunk's.
func build_segments(segs: Array[Dictionary], area: Rect2) -> int:
	var fw: Freeway = plan.macro.freeway
	var built := 0
	var pillar_every := int(round(Freeway.PILLAR_SPACING / Freeway.STEP))
	var gantry_every := int(round(Freeway.GANTRY_SPACING / Freeway.STEP))
	for seg in segs:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var seg_len := a.distance_to(b)
		if seg_len < 0.5 or not area.has_point(a.lerp(b, 0.5)):
			continue
		built += 1
		var ha: float = seg.ha
		var hb: float = seg.hb
		var dir := (b - a) / seg_len
		var nrm := Vector2(-dir.y, dir.x)
		var width: float = seg.width
		var half := width * 0.5
		var idx: int = seg.index
		var ri: int = seg.route
		var run0 := float(idx) * Freeway.STEP
		var run1 := run0 + seg_len
		var a3 := Vector3(a.x, ha, a.y)
		var b3 := Vector3(b.x, hb, b.y)
		var lay := Freeway.lane_layout(width)

		# Deck top (the road material).
		var e := nrm * half
		var l0 := Vector3(a.x - e.x, ha, a.y - e.y)
		var r0 := Vector3(a.x + e.x, ha, a.y + e.y)
		var l1 := Vector3(b.x - e.x, hb, b.y - e.y)
		var r1 := Vector3(b.x + e.x, hb, b.y + e.y)
		for v: Vector3 in [l0, r1, r0, l0, l1, r1]:
			top.add_vertex(v)
		if not full:
			_traffic_skin(l0, r0, l1, r1, dir, half, run0, seg_len, ri)

		_girder(a3, b3, nrm, half, run0, run1)
		_barriers(a3, b3, nrm, half, run0, run1)
		_markings(a3, b3, nrm, dir, lay, idx, run0, run1, ri)
		if idx % pillar_every == 0:
			var ground := plan.height_at(a)
			# A bent standing in the river's channel goes down to the channel's floor (LaRiver).
			if plan.macro and plan.macro.river:
				for side: float in [-1.0, 1.0]:
					ground = minf(ground, plan.macro.river.channel_floor(a + nrm * (half * 0.26 * side)))
			var cap := ha - Freeway.DECK_THICKNESS - 0.12
			if cap - ground > 1.5:
				_bent(Vector3(a.x, ground, a.y), cap, dir, nrm, half, idx / pillar_every)
		if idx % LIGHT_EVERY == 1:
			_light_standard(a3, dir, nrm, ri)
		if idx % gantry_every == 0:
			_gantry(a3, dir, nrm, half, lay, ri, idx, fw)
		if full:
			_furniture(a3, b3, dir, nrm, lay, idx, ri, run0)
	return built


## The box girder under the deck: fascia, cantilever soffit, inclined web, bottom slab.
func _girder(a3: Vector3, b3: Vector3, nrm: Vector2, half: float, run0: float, run1: float) -> void:
	var t := Freeway.DECK_THICKNESS
	var conc := kind_color(CONCRETE, S_FASCIA)
	var soff := kind_color(CONCRETE * 0.92, S_SOFFIT)
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector2Array([Vector2(half, 0.0), Vector2(half, -FASCIA_DEPTH),
			Vector2(half - CANTILEVER, -t * 0.78), Vector2(half - WEB_FOOT, -t), Vector2(0.0, -t)])
		for i in pts.size():
			pts[i].x *= side
		extrude(body, a3, b3, nrm, run0, run1, pts, Vector2(half * 0.5 * side, -t * 0.5),
			[conc, soff, soff, soff], PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))


## New Jersey-profile barriers: both deck edges (single-sided, the outer face flush with the
## fascia) and the median (double-sided). Flag 1 on the faces the traffic sees (tyre scuffs).
func _barriers(a3: Vector3, b3: Vector3, nrm: Vector2, half: float, run0: float, run1: float) -> void:
	var col := kind_color(CONCRETE, S_BARRIER)
	var h := BARRIER_H
	for side: float in [-1.0, 1.0]:
		var toe := half - BARRIER_BASE
		var pts := PackedVector2Array([Vector2(toe, 0.0), Vector2(toe, 0.075), Vector2(half - 0.24, 0.33),
			Vector2(half - 0.17, h), Vector2(half, h), Vector2(half, 0.0)])
		for i in pts.size():
			pts[i].x *= side
		extrude(body, a3, b3, nrm, run0, run1, pts, Vector2((half - 0.15) * side, 0.4),
			[col, col, col, col, col], PackedFloat32Array([1.0, 1.0, 1.0, 0.0, 0.0]))
	var m := MEDIAN_HALF
	var med := PackedVector2Array([Vector2(-m, 0.0), Vector2(-m, 0.075), Vector2(-0.125, 0.33), Vector2(-0.075, h),
		Vector2(0.075, h), Vector2(0.125, 0.33), Vector2(m, 0.075), Vector2(m, 0.0)])
	extrude(body, a3, b3, nrm, run0, run1, med, Vector2(0.0, 0.4),
		[col, col, col, col, col, col, col], PackedFloat32Array([1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0]))


## Lane markings on both carriageways. The + side (along +nrm) carries traffic heading +dir.
func _markings(a3: Vector3, b3: Vector3, nrm: Vector2, dir: Vector2, lay: Dictionary, idx: int, run0: float, run1: float, ri: int) -> void:
	var inner: float = lay.inner
	var lw: float = lay.lane
	var edge: float = lay.edge
	var white := kind_color(WHITE, P_LINE)
	var yellow := kind_color(YELLOW, P_LINE)
	for side: float in [-1.0, 1.0]:
		var face := -dir * side
		# Left edge: solid yellow; right edge: solid white.
		strip(a3, b3, nrm, inner * side, 0.12, 0.0, 1.0, run0, run1, yellow, face)
		strip(a3, b3, nrm, edge * side, 0.15, 0.0, 1.0, run0, run1, white, face)
		# The carpool lane's buffer: a double yellow between lanes 0 and 1.
		var hov := inner + lw
		for o: float in [-0.12, 0.12]:
			strip(a3, b3, nrm, (hov + o) * side, 0.10, 0.0, 1.0, run0, run1, yellow, face)
		# The other lane lines: Botts' dots with a marker every cycle by the carpool lane, then
		# the newer dashed stripe with a marker in each gap (Caltrans has been replacing the dots).
		for k in range(2, Freeway.LANES):
			var u := (inner + lw * k) * side
			if full and k == 2:
				strip(a3, b3, nrm, u, 0.16, 0.0, 1.0, run0, run1, kind_color(WHITE, P_BOTTS), face, 0.04)
			else:
				strip(a3, b3, nrm, u, 0.14, 0.0, 1.0, run0, run1, kind_color(WHITE, P_DASH), face)
				if full:
					strip(a3, b3, nrm, u, 0.12, 0.0, 1.0, run0, run1, kind_color(WHITE, P_RPM), face, 0.04)
		if not full:
			continue
		# Yellow retroreflective markers along the left edge line, just inside it.
		strip(a3, b3, nrm, (inner + 0.18) * side, 0.12, 0.0, 1.0, run0, run1, kind_color(YELLOW, P_RPM), face, 0.04)
		# The carpool diamond, in the middle of the carpool lane, every DIAMOND_EVERY segments.
		if posmod(idx + ri * 3, DIAMOND_EVERY) == 0:
			var u := (inner + lw * 0.5) * side
			var n3 := Vector3(nrm.x, 0.0, nrm.y)
			var c := a3.lerp(b3, 0.5) + Vector3(0.0, 0.036, 0.0) + n3 * u
			var along := (b3 - a3).normalized() * 2.6
			var across := n3 * 0.75
			quad(paint, c - along - across, c - along + across, c + along + across, c + along - across, Vector3.UP,
				kind_color(WHITE, P_DIAMOND), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), face)
		# Scupper grates at the edge barrier's toe (their rust runs down the fascia below).
		var outer: float = lay.outer
		var seg_len := Vector2(a3.x, a3.z).distance_to(Vector2(b3.x, b3.z))
		var s_run := ceilf(run0 / SCUPPER_SPACING - 0.5) * SCUPPER_SPACING + SCUPPER_SPACING * 0.5
		while s_run < run1:
			var s := (s_run - run0) / maxf(seg_len, 0.001)
			if s > 0.03 and s < 0.97:
				strip(a3, b3, nrm, (outer - 0.28) * side, 0.42, s - 0.35 / seg_len, s + 0.35 / seg_len,
					run0, run1, kind_color(Color(0.16, 0.15, 0.14), P_GRATE), face, 0.03)
			s_run += SCUPPER_SPACING
	# An expansion joint across both carriageways every JOINT_EVERY_BENTS bents.
	var pillar_every := int(round(Freeway.PILLAR_SPACING / Freeway.STEP))
	if full and idx % (pillar_every * JOINT_EVERY_BENTS) == 0:
		var n3 := Vector3(nrm.x, 0.0, nrm.y)
		var along := (b3 - a3).normalized() * 0.16
		var lift := Vector3(0.0, 0.033, 0.0)
		for side: float in [-1.0, 1.0]:
			var u0: float = MEDIAN_HALF * side
			var u1: float = float(lay.outer) * side
			var p := a3 + along * 1.2 + lift
			quad(paint, p + n3 * u0 - along, p + n3 * u1 - along, p + n3 * u1 + along, p + n3 * u0 + along, Vector3.UP,
				kind_color(Color(0.30, 0.29, 0.28), P_JOINT), Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0), Vector2.ZERO)


## A bent: two columns with flared heads, the bent cap, bearing pads, a downpipe.
func _bent(base: Vector3, cap_y: float, dir: Vector2, nrm: Vector2, half: float, bent_no: int) -> void:
	var d3 := Vector3(dir.x, 0.0, dir.y)
	var n3 := Vector3(nrm.x, 0.0, nrm.y)
	var col := kind_color(Color(0.66, 0.65, 0.62), S_PILLAR)
	var cap_h := 1.6
	var cap_bottom := cap_y - cap_h
	var col_top := cap_bottom
	var flare := 1.4 if col_top - base.y > 6.0 else 0.0
	for side: float in [-1.0, 1.0]:
		var c := base + n3 * (half * 0.26 * side)
		var shaft_top := col_top - flare
		var mid := Vector3(c.x, (base.y - 1.0 + shaft_top) * 0.5, c.z)
		box(body, mid, d3 * 0.8, Vector3(0.0, (shaft_top - base.y + 1.0) * 0.5, 0.0), n3 * 0.8, col)
		if flare > 0.0:
			# Flared head: 0.8 -> 1.25 across the deck, 0.8 along it.
			var lo := shaft_top
			var hi := col_top
			for s: float in [-1.0, 1.0]:
				var o0 := n3 * 0.8 * s
				var o1 := n3 * 1.25 * s
				quad(body, c + o0 - d3 * 0.8 + Vector3.UP * (lo - c.y), c + o0 + d3 * 0.8 + Vector3.UP * (lo - c.y),
					c + o1 + d3 * 0.8 + Vector3.UP * (hi - c.y), c + o1 - d3 * 0.8 + Vector3.UP * (hi - c.y), n3 * s, col,
					Vector2(0, 0), Vector2(1.6, 0), Vector2(1.6, -flare), Vector2(0, -flare), Vector2(0.0, hi - base.y))
				var bot := Vector3(c.x, lo, c.z)
				var tp := Vector3(c.x, hi, c.z)
				quad(body, bot - n3 * 0.8 + d3 * 0.8 * s, bot + n3 * 0.8 + d3 * 0.8 * s, tp + n3 * 1.25 + d3 * 0.8 * s,
					tp - n3 * 1.25 + d3 * 0.8 * s, d3 * s, col, Vector2(0, 0), Vector2(1.6, 0), Vector2(2.5, -flare), Vector2(0, -flare), Vector2(0.0, hi - base.y))
	# The bent cap: a deep beam across under the girder, its ends chamfered.
	var cap_half := half - WEB_FOOT - 0.4
	var cc := Vector3(base.x, cap_bottom + cap_h * 0.5, base.z)
	box(body, cc, n3 * cap_half, Vector3(0.0, cap_h * 0.5, 0.0), d3 * 1.0, kind_color(Color(0.68, 0.67, 0.64), S_PILLAR), 0.0, false)
	# Bearing pads between the cap and the girder.
	for k in 5:
		var u := lerpf(-cap_half + 0.8, cap_half - 0.8, float(k) / 4.0)
		var pc := Vector3(base.x, cap_y + 0.06, base.z) + n3 * u
		box(body, pc, n3 * 0.35, Vector3(0.0, 0.06, 0.0), d3 * 0.3, kind_color(Color(0.14, 0.14, 0.15), S_RUBBER))
	# Under-deck lights on the cap, and the pool each throws on the street below at night: the
	# underside of an LA freeway is lit, so the streets under it are never black holes.
	if cap_y - base.y > 4.0:
		for side: float in [-1.0, 1.0]:
			var lu := cap_half * 0.55 * side
			var fx := Vector3(base.x, cap_bottom - 0.12, base.z) + n3 * lu
			box(body, fx, n3 * 0.25, Vector3(0.0, 0.1, 0.0), d3 * 0.2, kind_color(Color(0.35, 0.36, 0.37), S_PAINTED), 0.0, false)
			box(body, fx - Vector3(0.0, 0.13, 0.0), n3 * 0.2, Vector3(0.0, 0.03, 0.0), d3 * 0.15, kind_color(Color(0.9, 0.93, 1.0), S_LENS), 0.8, false)
			pool(Vector3(base.x, base.y + 0.09, base.z) + n3 * lu, d3, UNDER_POOL, Color(0.9, 0.93, 1.0, 0.3))
	# A downpipe from the deck drain down one column, rust-brown cast iron.
	var s := 1.0 if bent_no % 2 == 0 else -1.0
	var pipe_at := base + n3 * (half * 0.26 * s) + d3 * (0.89 * s)
	prism(body, Vector3(pipe_at.x, base.y - 0.2, pipe_at.z), Vector3(pipe_at.x, cap_y, pipe_at.z), 0.09, 0.09, 6,
		kind_color(Color(0.33, 0.24, 0.18), S_PAINTED), false)


## A median light standard: a tapered pole on the median barrier, twin arms, cobra heads; a pool
## of light on each carriageway. Sodium amber on the older routes, LED white on the rest.
func _light_standard(a3: Vector3, dir: Vector2, nrm: Vector2, ri: int) -> void:
	var d3 := Vector3(dir.x, 0.0, dir.y)
	var n3 := Vector3(nrm.x, 0.0, nrm.y)
	var base := a3 + Vector3(0.0, BARRIER_H, 0.0)
	var top_p := a3 + Vector3(0.0, LIGHT_HEIGHT, 0.0)
	var pole := kind_color(POLE_GREY, S_STEEL)
	var sodium := is_sodium(str(plan.macro.freeway.routes[ri].name))
	var lamp_col := Color(1.0, 0.66, 0.30) if sodium else Color(0.86, 0.92, 1.0)
	prism(body, base, top_p, 0.17 if full else 0.2, 0.09, 6 if full else 4, pole)
	if full:
		box(body, base + Vector3(0.0, 0.12, 0.0), d3 * 0.28, Vector3(0.0, 0.12, 0.0), n3 * 0.22, pole)
	for side: float in [-1.0, 1.0]:
		var bend := top_p + n3 * (0.9 * side) + Vector3(0.0, 0.35, 0.0)
		var tip := top_p + n3 * (LIGHT_ARM * side) + Vector3(0.0, 0.45, 0.0)
		prism(body, top_p - Vector3(0.0, 0.2, 0.0), bend, 0.07, 0.06, 4, pole, false)
		prism(body, bend, tip, 0.06, 0.05, 4, pole, false)
		# Cobra head: a housing tilted a few degrees up, its lens under it.
		var hc := tip + n3 * (0.35 * side) - Vector3(0.0, 0.08, 0.0)
		box(body, hc, n3 * (0.42 * side), Vector3(0.0, 0.09, 0.0), d3 * 0.17, kind_color(Color(0.50, 0.51, 0.52), S_PAINTED))
		# The drop lens: a shallow glowing box under the housing, so it reads from the side too.
		box(body, hc - Vector3(0.0, 0.13, 0.0), n3 * (0.32 * side), Vector3(0.0, 0.045, 0.0), d3 * 0.13, kind_color(lamp_col, S_LENS), 1.0, false)
		# The pool it throws, a little out from under the head toward the traffic lanes.
		var pc := a3 + n3 * ((LIGHT_ARM + 3.2) * side) + Vector3(0.0, 0.07, 0.0)
		pool(pc, d3, POOL_SIZE, Color(lamp_col.r, lamp_col.g, lamp_col.b, POOL_SODIUM if sodium else POOL_LED))


## An overhead sign gantry: truss posts on both edge barriers, a box truss across the deck with
## diagonal lacing, and on each carriageway's approach face a catwalk, sign lights and two signs.
func _gantry(a3: Vector3, dir: Vector2, nrm: Vector2, half: float, lay: Dictionary, ri: int, idx: int, fw: Freeway) -> void:
	var d3 := Vector3(dir.x, 0.0, dir.y)
	var n3 := Vector3(nrm.x, 0.0, nrm.y)
	var steel := kind_color(GALV, S_STEEL)
	var reach := half - 0.25
	var gd := GANTRY_DEPTH * 0.5
	# Posts: two legs each side, laced.
	for side: float in [-1.0, 1.0]:
		var foot := a3 + n3 * (reach * side) + Vector3(0.0, BARRIER_H, 0.0)
		for s: float in [-1.0, 1.0]:
			var leg := foot + d3 * (gd * s)
			prism(body, leg, leg + Vector3(0.0, GANTRY_HIGH - BARRIER_H + 0.3, 0.0), 0.11, 0.11, 6 if full else 4, steel)
		box(body, foot + Vector3(0.0, 0.1, 0.0), d3 * (gd + 0.3), Vector3(0.0, 0.1, 0.0), n3 * 0.3, steel)
		if full:
			var y := 0.0
			while y < GANTRY_HIGH - BARRIER_H - 0.6:
				var p0 := foot + d3 * (-gd) + Vector3(0.0, y, 0.0)
				var p1 := foot + d3 * gd + Vector3(0.0, y + 0.9, 0.0)
				prism(body, p0, p1, 0.04, 0.04, 4, steel, false)
				y += 0.9
	# The truss: four chords and lacing on the front, back and top.
	var ys := [GANTRY_LOW, GANTRY_HIGH]
	for y: float in ys:
		for s: float in [-1.0, 1.0]:
			var off := d3 * (gd * s) + Vector3(0.0, y, 0.0)
			prism(body, a3 + off - n3 * (reach + 0.3), a3 + off + n3 * (reach + 0.3), 0.09, 0.09, 4 if not full else 6, steel)
	if full:
		var panel := 1.4
		var count := int(ceil(reach * 2.0 / panel))
		for k in count:
			var u0 := -reach + float(k) * reach * 2.0 / count
			var u1 := -reach + float(k + 1) * reach * 2.0 / count
			var flip := k % 2 == 0
			for s: float in [-1.0, 1.0]:
				var lo := a3 + d3 * (gd * s) + Vector3(0.0, GANTRY_LOW, 0.0)
				var hi := a3 + d3 * (gd * s) + Vector3(0.0, GANTRY_HIGH, 0.0)
				var p0 := (lo if flip else hi) + n3 * u0
				var p1 := (hi if flip else lo) + n3 * u1
				prism(body, p0, p1, 0.035, 0.035, 4, steel, false)
			var t0 := a3 + Vector3(0.0, GANTRY_HIGH, 0.0) + n3 * u0 - d3 * gd
			var t1 := a3 + Vector3(0.0, GANTRY_HIGH, 0.0) + n3 * u1 + d3 * gd
			if flip:
				t0 = a3 + Vector3(0.0, GANTRY_HIGH, 0.0) + n3 * u0 + d3 * gd
				t1 = a3 + Vector3(0.0, GANTRY_HIGH, 0.0) + n3 * u1 - d3 * gd
			prism(body, t0, t1, 0.03, 0.03, 4, steel, false)
	# Signs on each carriageway's approach face.
	for side: float in [-1.0, 1.0]:
		var heading := dir * side
		var face3 := -d3 * side
		var right := n3 * side
		_sign_pair(a3 + face3 * (gd + 0.12), face3, right, lay, ri, idx, side, heading, fw)


## Two signs over one carriageway: a guide sign over the inner lanes (shield, direction,
## destinations, down arrows) and, where an exit is ahead on this side, an exit sign over the
## outer lanes (street, distance, the exit tab); else a second guide sign.
func _sign_pair(face_at: Vector3, out: Vector3, right: Vector3, lay: Dictionary, ri: int, idx: int, side: float, heading: Vector2, fw: Freeway) -> void:
	var inner: float = lay.inner
	var lw: float = lay.lane
	var basis := Basis(right, Vector3.UP, out)
	var face := Vector2(out.x, out.z)
	var route: Dictionary = fw.routes[ri]
	var number := route_number(str(route.name))
	var dests := _destinations(ri, side, heading, idx)
	var exit := _next_exit(fw, ri, idx, side)
	# Board A over lanes 0-1, board B over lanes 2-3 (centres measured from the deck centre).
	var ua := inner + lw * 1.0
	var ub := inner + lw * 3.0
	var wa := minf(lw * 2.0 - 0.3, 7.2)
	var wb := minf(lw * 2.0 - 0.3, 6.4)
	var origin_a := face_at + right * ua + Vector3(0.0, SIGN_BOTTOM, 0.0)
	var origin_b := face_at + right * ub + Vector3(0.0, SIGN_BOTTOM, 0.0)
	_guide_board(Transform3D(basis, origin_a), wa, SIGN_HEIGHT, number, cardinal(heading), dests.slice(0, 2), face)
	if exit.is_empty():
		_guide_board(Transform3D(basis, origin_b), wb, SIGN_HEIGHT - 0.4, number, cardinal(heading), dests.slice(2, 3), face)
	else:
		_exit_board(Transform3D(basis, origin_b), wb, SIGN_HEIGHT - 0.4, exit, face)


## The destinations this carriageway signs: downtown first when it heads toward downtown, then
## invented names hashed from the route and direction.
func _destinations(ri: int, side: float, heading: Vector2, idx: int) -> Array:
	var out := []
	var here := Vector2(chunk.owned_rect().get_center())
	if plan.macro != null:
		var to_dt: Vector2 = plan.macro.downtown_center - here
		if to_dt.length() > 600.0 and to_dt.normalized().dot(heading) > 0.5:
			out.append("Downtown")
	var k := 0
	while out.size() < 3 and k < 12:
		var pick: String = DESTINATIONS[int(hash01([plan.seed, "fw_dest", ri, int(side), k]) * DESTINATIONS.size()) % DESTINATIONS.size()]
		if not out.has(pick):
			out.append(pick)
		k += 1
	return out


## The next off-ramp ahead of this carriageway, if one is within 1.5 km: {num, street, dist}.
## Off-ramps leave the + side heading +dir (Freeway._place_ramps(): a ramp runs along the route).
func _next_exit(fw: Freeway, ri: int, idx: int, side: float) -> Dictionary:
	if side < 0.0:
		return {}
	var best: Dictionary = {}
	for r: Dictionary in fw.ramps:
		if int(r.route) != ri or float(r.side) < 0.0 or int(r.index) <= idx:
			continue
		if best.is_empty() or int(r.index) < int(best.index):
			best = r
	if best.is_empty():
		return {}
	var dist := float(int(best.index) - idx) * Freeway.STEP
	if dist > 1500.0:
		return {}
	var path := Freeway.ramp_path(best)
	var land: Vector2 = path[path.size() - 1]
	var bi := plan.block_index_at(land)
	var dx := absf(plan.road_pos(CityPlan.AXIS_X, bi.x) - land.x)
	var dz := absf(plan.road_pos(CityPlan.AXIS_Z, bi.y) - land.y)
	var street := plan.road_name(CityPlan.AXIS_X, bi.x) if dx < dz else plan.road_name(CityPlan.AXIS_Z, bi.y)
	var miles := float(int(best.index)) * Freeway.STEP / 1609.0
	var letter := "A" if int(best.index) % 2 == 0 else "B"
	var dist_text := "EXIT ONLY"
	if dist > 1100.0:
		dist_text = "1 MILE"
	elif dist > 600.0:
		dist_text = "3/4 MILE"
	elif dist > 300.0:
		dist_text = "1/2 MILE"
	elif dist > 150.0:
		dist_text = "1/4 MILE"
	return {"num": "EXIT %d%s" % [int(miles) + 1, letter], "street": sign_case(street), "dist": dist_text}


## A board's aluminium back (in the structure mesh), the green face and its white border.
func _board(xf: Transform3D, w: float, h: float, face: Vector2) -> Rect2:
	var r := Rect2(-w * 0.5, 0.0, w, h)
	var right := xf.basis.x
	var out := xf.basis.z
	var c := xf.origin + Vector3(0.0, h * 0.5, 0.0) - out * 0.06
	box(body, c, right * (w * 0.5), Vector3(0.0, h * 0.5, 0.0), out * 0.06, kind_color(Color(0.55, 0.56, 0.57), S_STEEL), 0.0, false)
	var face_xf := Transform3D(xf.basis, xf.origin + out * 0.005)
	var outer := rounded_rect(r, 0.22)
	flat_poly(outer, face_xf, kind_color(SIGN_GREEN, P_SIGN), r, face)
	var border := Transform3D(xf.basis, xf.origin + out * 0.025)
	ring(rounded_rect(r.grow(-0.06), 0.18), rounded_rect(r.grow(-0.13), 0.12), border, kind_color(SIGN_WHITE, P_SIGN), r, face)
	# The catwalk below and its sign lights, pointing up at the face.
	if full:
		var cw := xf.origin + out * 0.45 + Vector3(0.0, -0.18, 0.0)
		box(body, cw, right * (w * 0.5), Vector3(0.0, 0.04, 0.0), out * 0.42, kind_color(Color(0.40, 0.41, 0.42), S_STEEL))
		var nl := maxi(2, int(w / 2.2))
		for k in nl:
			var lp := cw + right * lerpf(-w * 0.4, w * 0.4, float(k) / (nl - 1)) + out * 0.25 + Vector3(0.0, 0.12, 0.0)
			box(body, lp, right * 0.18, Vector3(0.0, 0.07, 0.0), out * 0.12, kind_color(Color(0.3, 0.31, 0.32), S_PAINTED))
			var lens := lp + Vector3(0.0, 0.075, 0.0)
			quad(body, lens - right * 0.15 - out * 0.09, lens + right * 0.15 - out * 0.09, lens + right * 0.15 + out * 0.09,
				lens - right * 0.15 + out * 0.09, Vector3.UP, kind_color(Color(1.0, 0.95, 0.85), S_LENS),
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(0.6, 0.0))
	return r


## The route shield: an original crest (flat top with clipped corners, sides tapering to a point),
## black edge, white field, black numerals. `at` is its centre, `h` its height.
func _shield(xf: Transform3D, at: Vector2, h: float, number: int, board: Rect2, face: Vector2) -> void:
	var w := h * 0.86
	var pts := PackedVector2Array()
	var outline := [Vector2(-0.38, 0.5), Vector2(0.38, 0.5), Vector2(0.5, 0.36), Vector2(0.5, 0.0),
		Vector2(0.38, -0.3), Vector2(0.0, -0.5), Vector2(-0.38, -0.3), Vector2(-0.5, 0.0), Vector2(-0.5, 0.36)]
	for p: Vector2 in outline:
		pts.append(at + Vector2(p.x * w, p.y * h))
	var inner := PackedVector2Array()
	for p: Vector2 in outline:
		inner.append(at + Vector2(p.x * (w - 0.1), p.y * (h - 0.1)))
	var lift := Transform3D(xf.basis, xf.origin + xf.basis.z * 0.03)
	flat_poly(inner, lift, kind_color(SIGN_WHITE, P_SIGN), board, face)
	ring(pts, inner, lift, kind_color(SIGN_BLACK, P_SIGN), board, face)
	var txt := Transform3D(xf.basis, xf.origin + xf.basis.z * 0.045)
	letters(str(number), h * 0.42, at + Vector2(0.0, h * 0.04), txt, kind_color(SIGN_BLACK, P_SIGN), board, face, w * 0.8)


## A down arrow (one per lane the sign serves), `h` tall, its point at `tip`.
func _arrow(xf: Transform3D, tip: Vector2, h: float, board: Rect2, face: Vector2) -> void:
	var s := h
	var pts := PackedVector2Array([tip, tip + Vector2(0.36, 0.42) * s, tip + Vector2(0.11, 0.42) * s,
		tip + Vector2(0.11, 1.0) * s, tip + Vector2(-0.11, 1.0) * s, tip + Vector2(-0.11, 0.42) * s, tip + Vector2(-0.36, 0.42) * s])
	flat_poly(pts, Transform3D(xf.basis, xf.origin + xf.basis.z * 0.03), kind_color(SIGN_WHITE, P_SIGN), board, face)


func _guide_board(xf: Transform3D, w: float, h: float, number: int, card: String, dests: Array, face: Vector2) -> void:
	var r := _board(xf, w, h, face)
	if not full:
		return
	var txt := Transform3D(xf.basis, xf.origin + xf.basis.z * 0.03)
	var col := kind_color(SIGN_WHITE, P_SIGN)
	# Shield and direction on the top row.
	var sh := 0.95
	_shield(xf, Vector2(-w * 0.5 + 0.35 + sh * 0.43, h - 0.25 - sh * 0.5), sh, number, r, face)
	letters(card, 0.34, Vector2(-w * 0.5 + 0.55 + sh + 0.75, h - 0.25 - sh * 0.5), txt, col, r, face, w * 0.4)
	# Destinations, mixed case, on the rows under it.
	var y := h - 0.4 - sh - 0.42
	for d in dests:
		letters(str(d), 0.40, Vector2(0.15, y), txt, col, r, face, w - 0.6)
		y -= 0.62
	# Down arrows at the bottom, one per lane.
	for s: float in [-0.25, 0.25]:
		_arrow(xf, Vector2(w * s, 0.18), 0.62, r, face)


func _exit_board(xf: Transform3D, w: float, h: float, exit: Dictionary, face: Vector2) -> void:
	var r := _board(xf, w, h, face)
	# The exit tab on top, at the right.
	var tw := 2.5
	var th := 0.62
	var tab_x := w * 0.5 - tw * 0.5 - 0.05
	var tab := Transform3D(xf.basis, xf.origin + xf.basis.y * h + xf.basis.x * tab_x)
	var tr := _board(tab, tw, th, face)
	if not full:
		return
	var col := kind_color(SIGN_WHITE, P_SIGN)
	letters(str(exit.num), 0.36, Vector2(0.0, th * 0.5), Transform3D(tab.basis, tab.origin + tab.basis.z * 0.03), col, tr, face, tw - 0.3)
	var txt := Transform3D(xf.basis, xf.origin + xf.basis.z * 0.03)
	letters(str(exit.street), 0.44, Vector2(0.0, h - 0.85), txt, col, r, face, w - 0.6)
	var dist: String = exit.dist
	if dist == "EXIT ONLY":
		# The yellow EXIT ONLY panel across the bottom, an arrow either side.
		var band := Rect2(-w * 0.5 + 0.2, 0.15, w - 0.4, 0.75)
		flat_poly(rounded_rect(band, 0.08), Transform3D(xf.basis, xf.origin + xf.basis.z * 0.03), kind_color(YELLOW, P_SIGN), r, face)
		letters("EXIT ONLY", 0.40, band.get_center(), Transform3D(xf.basis, xf.origin + xf.basis.z * 0.045), kind_color(SIGN_BLACK, P_SIGN), r, face, w * 0.55)
		_arrow(xf, Vector2(0.0, 1.0), 0.72, r, face)
	else:
		letters(dist, 0.32, Vector2(-w * 0.12, 0.62), txt, col, r, face, w * 0.6)
		# An up-right arrow toward the exit.
		var tip := Vector2(w * 0.5 - 0.55, 1.15)
		var pts := PackedVector2Array([tip, tip + Vector2(-0.12, -0.5), tip + Vector2(-0.22, -0.39),
			tip + Vector2(-0.62, -0.79), tip + Vector2(-0.79, -0.62), tip + Vector2(-0.39, -0.22), tip + Vector2(-0.5, -0.12)])
		flat_poly(pts, Transform3D(xf.basis, xf.origin + xf.basis.z * 0.03), col, r, face)


## Roadside furniture on the outer shoulder: call boxes, CCTV poles, postmile paddles, and the
## debris every freeway shoulder collects (tyre treads, a bit of wood).
func _furniture(a3: Vector3, b3: Vector3, dir: Vector2, nrm: Vector2, lay: Dictionary, idx: int, ri: int, run0: float) -> void:
	var d3 := Vector3(dir.x, 0.0, dir.y)
	var n3 := Vector3(nrm.x, 0.0, nrm.y)
	var outer: float = lay.outer
	var edge: float = lay.edge
	for side: float in [-1.0, 1.0]:
		var key := [plan.seed, "fw_furn", ri, idx, int(side)]
		var at := a3.lerp(b3, 0.35 + 0.3 * hash01(key + [0]))
		var shoulder := n3 * side
		if posmod(idx * 7 + ri * 5 + int(side), CALLBOX_EVERY) == 0:
			# Call box: a yellow box on a post by the barrier, a blue plate above it.
			var p := at + shoulder * (outer - 0.45)
			prism(body, p, p + Vector3(0.0, 1.6, 0.0), 0.05, 0.05, 4, kind_color(GALV, S_STEEL))
			box(body, p + Vector3(0.0, 1.2, 0.0) - shoulder * 0.12, d3 * 0.2, Vector3(0.0, 0.27, 0.0), shoulder * 0.13,
				kind_color(Color(0.92, 0.70, 0.08), S_PAINTED))
			var plate := Transform3D(Basis(-d3 * side, Vector3.UP, -shoulder), p + Vector3(0.0, 1.62, 0.0) - shoulder * 0.06)
			var pr := Rect2(-0.25, 0.0, 0.5, 0.36)
			flat_poly(rounded_rect(pr, 0.04), plate, kind_color(SIGN_BLUE, P_SIGN), pr, Vector2(-shoulder.x, -shoulder.z))
			letters("SOS", 0.16, Vector2(0.0, 0.18), Transform3D(plate.basis, plate.origin - shoulder * 0.01), kind_color(SIGN_WHITE, P_SIGN), pr, Vector2(-shoulder.x, -shoulder.z))
		if posmod(idx * 3 + ri * 11 + (1 if side > 0.0 else 0), CAMERA_EVERY) == 0:
			# CCTV: a tall pole behind the barrier, an arm, a camera housing, a cabinet at its foot.
			var p := at + shoulder * (outer + 0.2) + Vector3(0.0, BARRIER_H, 0.0)
			var pole := kind_color(GALV, S_STEEL)
			prism(body, p, p + Vector3(0.0, 9.0, 0.0), 0.13, 0.08, 6, pole)
			var arm_end := p + Vector3(0.0, 8.8, 0.0) - shoulder * 1.4
			prism(body, p + Vector3(0.0, 8.8, 0.0), arm_end, 0.05, 0.05, 4, pole, false)
			box(body, arm_end - Vector3(0.0, 0.25, 0.0), d3 * 0.12, Vector3(0.0, 0.14, 0.0), shoulder * 0.3, kind_color(Color(0.85, 0.85, 0.83), S_PAINTED))
			prism(body, arm_end - Vector3(0.0, 0.42, 0.0), arm_end - Vector3(0.0, 0.62, 0.0) - shoulder * 0.05, 0.1, 0.06, 6, kind_color(Color(0.08, 0.08, 0.09), S_PAINTED))
			box(body, p + Vector3(0.0, 0.7, 0.0) + shoulder * 0.05, d3 * 0.35, Vector3(0.0, 0.6, 0.0), shoulder * 0.22, kind_color(Color(0.60, 0.62, 0.60), S_PAINTED))
		if posmod(idx + ri, POSTMILE_EVERY) == 0 and side > 0.0:
			# A postmile paddle: white plate with the miles on a post on the barrier top.
			var p := at + shoulder * (outer + 0.1) + Vector3(0.0, BARRIER_H, 0.0)
			prism(body, p, p + Vector3(0.0, 0.9, 0.0), 0.03, 0.03, 4, kind_color(GALV, S_STEEL))
			var plate := Transform3D(Basis(shoulder, Vector3.UP, -d3), p + Vector3(0.0, 0.55, 0.0) - d3 * 0.04)
			var pr := Rect2(-0.17, 0.0, 0.34, 0.56)
			flat_poly(rounded_rect(pr, 0.03), plate, kind_color(SIGN_WHITE, P_SIGN), pr, Vector2(-d3.x, -d3.z))
			var miles := run0 / 1609.0
			letters("%.1f" % miles, 0.10, Vector2(0.0, 0.3), Transform3D(plate.basis, plate.origin - d3 * 0.01), kind_color(SIGN_BLACK, P_SIGN), pr, Vector2(-d3.x, -d3.z), 0.3)
		# Debris on the shoulder: tread strips and the odd board.
		var bits := int(hash01(key + [1]) * 4.0) - 1
		for k in maxi(bits, 0):
			var hk := key + [10 + k]
			var s := hash01(hk)
			var u := lerpf(edge + 0.4, outer - 0.3, hash01(hk + [1]))
			var p := a3.lerp(b3, s) + n3 * (u * side) + Vector3(0.0, 0.03, 0.0)
			var ang := hash01(hk + [2]) * TAU
			var ax := (d3 * cos(ang) + n3 * sin(ang))
			var az := ax.cross(Vector3.UP)
			if hash01(hk + [3]) < 0.8:
				var l := 0.25 + 0.6 * hash01(hk + [4])
				box(body, p, ax * l, Vector3(0.0, 0.025, 0.0), az * (0.09 + 0.05 * hash01(hk + [5])), kind_color(Color(0.06, 0.06, 0.06), S_RUBBER))
				# Curled up at one end, the way a thrown tread lies.
				box(body, p + ax * (l + 0.08) + Vector3(0.0, 0.07, 0.0), ax * 0.08, Vector3(0.0, 0.08, 0.0), az * 0.1, kind_color(Color(0.07, 0.07, 0.07), S_RUBBER))
			else:
				box(body, p + Vector3(0.0, 0.02, 0.0), ax * 0.45, Vector3(0.0, 0.02, 0.0), az * 0.07, kind_color(Color(0.42, 0.33, 0.22), S_PAINTED))


## One off-ramp piece from p0 to p1 (centre line at the deck top), `width` wide: the deck top, a
## 0.7 m slab, New Jersey barriers along both edges and a white edge line inside each.
func ramp_piece(p0: Vector3, p1: Vector3, nrm: Vector2, width: float, run0: float, run1: float) -> void:
	var half := width * 0.5
	var n3 := Vector3(nrm.x, 0.0, nrm.y)
	for v: Vector3 in [p0 - n3 * half, p1 + n3 * half, p0 + n3 * half, p0 - n3 * half, p1 - n3 * half, p1 + n3 * half]:
		top.add_vertex(v)
	var conc := kind_color(CONCRETE, S_FASCIA)
	var slab := PackedVector2Array([Vector2(half, 0.0), Vector2(half, -0.7), Vector2(-half, -0.7), Vector2(-half, 0.0)])
	extrude(body, p0, p1, nrm, run0, run1, slab, Vector2(0.0, -0.35), [conc, kind_color(CONCRETE * 0.92, S_SOFFIT), conc],
		PackedFloat32Array([0.0, 0.0, 0.0]))
	var col := kind_color(CONCRETE, S_BARRIER)
	var bh := BARRIER_H * 0.95
	for side: float in [-1.0, 1.0]:
		var toe := half - 0.38
		var pts := PackedVector2Array([Vector2(toe, 0.0), Vector2(toe, 0.075), Vector2(half - 0.22, 0.32),
			Vector2(half - 0.15, bh), Vector2(half, bh), Vector2(half, 0.0)])
		for i in pts.size():
			pts[i].x *= side
		extrude(body, p0, p1, nrm, run0, run1, pts, Vector2((half - 0.15) * side, 0.4),
			[col, col, col, col, col], PackedFloat32Array([1.0, 1.0, 1.0, 0.0, 0.0]))
		strip(p0, p1, nrm, (half - 0.75) * side, 0.15, 0.0, 1.0, run0, run1, kind_color(WHITE, P_LINE), Vector2.ZERO)


## Commits the meshes into `chunk`: <prefix>Deck, <prefix>Structure, <prefix>Paint, <prefix>Glow.
func commit(road_mat: Material, prefix := "Freeway") -> void:
	top.generate_normals()
	_add(prefix + "Deck", top.commit(), road_mat)
	_add(prefix + "Structure", body.commit(), structure_material())
	if _paint_any:
		var mi := _add(prefix + "Paint", paint.commit(), paint_material())
		# Flat paint and sign faces: their shadow is the deck's and the boards'.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _glow_any:
		var gi := _add(prefix + "Glow", glow.commit(), pool_material())
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _traffic_any:
		var ti := _add(prefix + "Traffic", traffic.commit(), traffic_material())
		ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	chunk.add_child(mi)
	return mi
