class_name MetroBuild
extends FreewayKit
## Builds MetroStation's plan into the chunk that owns the Coral Line's underground terminus
## (called from LightRailKit._entrances() in its place): the two street kiosks, the stairs and
## escalators down, the concourse (terrazzo, tiled walls, ticket machines, fare gates, maps,
## signs), the bank of a stair and two escalators down to the island platform, the lift, the
## platform (tactile edges, benches, departure screens, the station's name on the track walls),
## the tracks with their rails and overhead wire, the tunnel into the dark at both ends; collision
## for all of it; the zone that lets bodies through the city's ground box; the people waiting.
##
## FreewayKit's helpers (tri, quad, box, prism, letters: winding fixed by the face's direction),
## in MetroStation's frame (u along the line, h from the street, v across): `_w()` takes a frame
## point (u, h, v) to the chunk's (true world) space. Two meshes on two materials
## (metro_station.gdshader for everything opaque, the letters included; metro_glass.gdshader),
## one shadow-only roof, one StaticBody3D, one Area3D. FULL chunks only. No rolls: the station is
## the same on every seed (the line is); the riders are hash-seeded.

const K_TILE := 1
const K_TERRAZZO := 2
const K_CONCRETE := 3
const K_STEEL := 4
const K_LAMP := 5
const K_RUBBER := 6
const K_ENAMEL := 7
const K_TEXT := 8
const K_PAINT := 9
const K_ESC := 10
const K_TRACK := 11
const K_RAIL := 12
const K_SCREEN := 13
const K_TACTILE := 14
const K_DARK := 15
const K_MAP := 16
const K_CEIL := 17

const TILE_WALL := Color(0.90, 0.89, 0.86)
const TILE_PLAT := Color(0.86, 0.87, 0.85)
const CORAL := LightRail.LINE_COLOR
const TERRAZZO := Color(0.78, 0.75, 0.70)
const TERRAZZO_DARK := Color(0.42, 0.41, 0.40)
const STEEL := Color(0.74, 0.75, 0.76)
const ENAMEL := Color(0.10, 0.11, 0.12)
const M_CONCRETE := Color(0.58, 0.57, 0.55)
const CEILING := Color(0.80, 0.80, 0.79)
const LAMP := Color(1.0, 0.96, 0.88)
const TRACK := Color(0.36, 0.35, 0.34)
const RAILC := Color(0.42, 0.38, 0.35)
const M_YELLOW := Color(0.95, 0.78, 0.10)
const M_WHITE := Color(0.96, 0.96, 0.94)

## Riders: on the platform, on the concourse.
const PLATFORM_RIDERS := Vector2i(5, 9)
const CONCOURSE_RIDERS := Vector2i(2, 4)

var line: LightRail
var f: Dictionary
var glass := SurfaceTool.new()
var shadow := SurfaceTool.new()
var _shapes: Array = []
var _lights: Array[Light3D] = []
var _d3 := Vector3.BACK
var _r3 := Vector3.LEFT
var _plat := 0.0
var _rail := 0.0
var _floor := 0.0


func _init(c: CityChunk) -> void:
	super(c)
	line = LightRail.of(plan)
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	shadow.begin(Mesh.PRIMITIVE_TRIANGLES)


## Everything, then commits it. False when there is no station (or the chunk is not FULL).
func build() -> bool:
	f = MetroStation.frame(line)
	if f.is_empty() or not full or chunk.capturing:
		return false
	var d: Vector2 = f.d
	var r: Vector2 = f.r
	_d3 = Vector3(d.x, 0.0, d.y)
	_r3 = Vector3(r.x, 0.0, r.y)
	_rail = float(f.rail)
	_plat = float(f.plat)
	_floor = _rail - 0.25
	_tracks()
	_platform()
	_platform_walls()
	_bank()
	_lift()
	_concourse()
	_gates()
	_machines()
	for k: float in [-1.0, 1.0]:
		_kiosk_stairs(k)
		_kiosk(k)
	_roof()
	_commit()
	return true


# --- Frame helpers ---------------------------------------------------------------------------

## A frame point (u, h, v) in the chunk's space (true world).
func _w(p: Vector3) -> Vector3:
	return MetroStation.to_world(f, p)


## A frame direction (u, h, v) in the chunk's space.
func _n(n: Vector3) -> Vector3:
	return _d3 * n.x + Vector3.UP * n.y + _r3 * n.z


func _kc(col: Color, kind: int) -> Color:
	return kind_color(col, kind)


## A quad of frame points facing frame normal `n`, UV per corner.
func _q(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, kind: int, col: Color,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO, u2 := Vector2.ZERO) -> void:
	quad(st, _w(a), _w(b), _w(c), _w(d), _n(n), _kc(col, kind), ua, ub, uc, ud, u2)


## A horizontal rect at h, facing up (or down).
func _flat(u0: float, u1: float, v0: float, v1: float, h: float, up: bool, kind: int, col: Color) -> void:
	_q(body, Vector3(u0, h, v0), Vector3(u1, h, v0), Vector3(u1, h, v1), Vector3(u0, h, v1),
		Vector3.UP if up else Vector3.DOWN, kind, col)


## A vertical wall along u at v, from h0 to h1, facing `side` (+1: +v, -1: -v).
func _wall_u(u0: float, u1: float, v: float, h0: float, h1: float, side: float, kind: int, col: Color) -> void:
	_q(body, Vector3(u0, h0, v), Vector3(u1, h0, v), Vector3(u1, h1, v), Vector3(u0, h1, v),
		Vector3(0, 0, side), kind, col, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


## A vertical wall across v at u, from h0 to h1, facing `side` along u.
func _wall_v(v0: float, v1: float, u: float, h0: float, h1: float, side: float, kind: int, col: Color) -> void:
	_q(body, Vector3(u, h0, v0), Vector3(u, h0, v1), Vector3(u, h1, v1), Vector3(u, h1, v0),
		Vector3(side, 0, 0), kind, col, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


## An axis-aligned box in the frame (no bottom face unless asked).
func _box(u0: float, u1: float, h0: float, h1: float, v0: float, v1: float, kind: int, col: Color, bottom := false, st: SurfaceTool = null) -> void:
	var c := Vector3((u0 + u1) * 0.5, (h0 + h1) * 0.5, (v0 + v1) * 0.5)
	box(st if st else body, _w(c), _d3 * (u1 - u0) * 0.5, Vector3.UP * (h1 - h0) * 0.5, _r3 * (v1 - v0) * 0.5, _kc(col, kind), 0.0, not bottom)


## A solid for walking on or into (frame box).
func _solid(u0: float, u1: float, h0: float, h1: float, v0: float, v1: float) -> void:
	var c := Vector3((u0 + u1) * 0.5, (h0 + h1) * 0.5, (v0 + v1) * 0.5)
	_shapes.append([Vector3(absf(u1 - u0), absf(h1 - h0), absf(v1 - v0)), Transform3D(Basis(_d3, Vector3.UP, _r3), _w(c))])


## A ramp you walk up and down: its top surface runs from (ua, ha) to (ub, hb), v0..v1 across.
func _ramp(ua: float, ha: float, ub: float, hb: float, v0: float, v1: float) -> void:
	var s3 := (_d3 * (ub - ua) + Vector3.UP * (hb - ha))
	var length_m := s3.length()
	s3 = s3.normalized()
	var y := _r3.cross(s3)
	if y.y < 0.0:
		y = -y
		s3 = -s3
	var thick := 0.4
	var mid := _w(Vector3((ua + ub) * 0.5, (ha + hb) * 0.5, (v0 + v1) * 0.5)) - y * thick * 0.5
	var basis := Basis(s3, y, s3.cross(y))
	_shapes.append([Vector3(length_m, thick, absf(v1 - v0)), Transform3D(basis, mid)])


## Lettering on a vertical face at frame point `at` facing frame normal `out`.
func _text(s: String, height: float, at: Vector3, out: Vector3, col: Color, max_w := 99.0) -> void:
	var o := _n(out).normalized()
	var reading := Vector3.UP.cross(o).normalized()
	var xf := Transform3D(Basis(reading, Vector3.UP, o), _w(at) + o * 0.006)
	letters(s, height, Vector2.ZERO, xf, _kc(col, K_TEXT), Rect2(-1, -1, 2, 2), Vector2(o.x, o.z), max_w)


## A sign board facing `out` (+-u or +-v), readable from both faces: dark enamel, the line's
## band along its foot, the bullet at the start of the text, white letters.
func _sign(at: Vector3, out: Vector3, w: float, hgt: float, text: String, bullet := true) -> void:
	var half_d := 0.05
	var reading0 := Vector3.UP.cross(out)
	box(body, _w(at), _n(reading0 * w * 0.5), Vector3.UP * hgt * 0.5, _n(out * half_d), _kc(ENAMEL, K_ENAMEL), 0.0, false)
	box(body, _w(at + Vector3.UP * (-hgt * 0.5 + 0.035)), _n(reading0 * w * 0.501), Vector3.UP * 0.035, _n(out * half_d * 1.15), _kc(CORAL, K_PAINT), 0.0, false)
	for sgn: float in [-1.0, 1.0]:
		var o := out * sgn
		var reading := Vector3.UP.cross(o)
		var face := at + o * (half_d + 0.002)
		var x0 := 0.0
		if bullet:
			var bc := face - reading * (w * 0.5 - hgt * 0.5) + Vector3.UP * 0.02
			_disc(bc, o, hgt * 0.36, CORAL)
			_text(LightRail.LINE_LETTER, hgt * 0.5, bc + o * 0.003, o, M_WHITE)
			x0 = hgt * 0.9
		_text(text, hgt * 0.5, face + reading * x0 * 0.5 + Vector3.UP * 0.03, o, M_WHITE, w - x0 - 0.25)


## A flat disc on a vertical face (frame point, frame normal).
func _disc(c: Vector3, out: Vector3, radius: float, col: Color) -> void:
	var o := _n(out).normalized()
	var a := Vector3.UP.cross(o).normalized()
	var w := _w(c)
	for i in 16:
		var t0 := TAU * float(i) / 16.0
		var t1 := TAU * float(i + 1) / 16.0
		tri(body, w, w + (a * cos(t0) + Vector3.UP * sin(t0)) * radius, w + (a * cos(t1) + Vector3.UP * sin(t1)) * radius, o, _kc(col, K_PAINT))


## A glass pane in the frame (vertical or not), both faces.
func _pane(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	quad(glass, _w(a), _w(b), _w(c), _w(d), _n(n), Color(1, 1, 1, 1))


# --- The tracks and the tunnel ---------------------------------------------------------------

func _tracks() -> void:
	var s0 := float(f.s)
	var hw := MetroStation.HALF_W
	var tu := MetroStation.TUNNEL_U
	# The trackbed, the tunnel's walls and roof past the station box, the dark at both ends.
	_flat(-tu, tu, -hw, hw, _floor, true, K_TRACK, TRACK)
	_solid(-tu, tu, _floor - 1.0, _floor, -hw - 0.5, hw + 0.5)
	var bu := MetroStation.BOX_U
	for e: float in [-1.0, 1.0]:
		var ua := minf(e * bu, e * tu)
		var ub := maxf(e * bu, e * tu)
		for side: float in [-1.0, 1.0]:
			_wall_u(ua, ub, side * hw, _floor, MetroStation.PLAT_CEIL, -side, K_CONCRETE, M_CONCRETE * 0.8)
			_solid(ua, ub, _floor, MetroStation.PLAT_CEIL, side * (hw + 0.25), side * (hw + 0.25) + side * 0.5)
		_flat(ua, ub, -hw, hw, MetroStation.PLAT_CEIL, false, K_CONCRETE, M_CONCRETE * 0.7)
		_solid(ua, ub, MetroStation.PLAT_CEIL, MetroStation.PLAT_CEIL + 1.0, -hw, hw)
		_wall_v(-hw, hw, e * tu, _floor, MetroStation.PLAT_CEIL, -e, K_DARK, Color(0, 0, 0))
		_solid(e * tu, e * (tu + 0.5), _floor, MetroStation.PLAT_CEIL, -hw, hw)
		# Wall lamps every 15 m down the tunnel (the shader lights from the same spots).
		var u := bu + 7.5
		while u < tu - 2.0:
			for side: float in [-1.0, 1.0]:
				_box(e * u - 0.25, e * u + 0.25, _rail + 3.1, _rail + 3.3, side * (hw - 0.12), side * hw, K_LAMP, LAMP * 0.7)
			u += 15.0
	# Rails, their plinths and the contact wire over each track, following the spread.
	var step := 3.0
	var u := -tu
	while u < tu - 0.01:
		var u1 := minf(u + step, tu)
		var ha := float(line.sample(s0 + u).half)
		var hb := float(line.sample(s0 + u1).half)
		for side: float in [-1.0, 1.0]:
			for g: float in [-1.0, 1.0]:
				var va := side * ha + g * LightRailKit.GAUGE * 0.5
				var vb := side * hb + g * LightRailKit.GAUGE * 0.5
				_beam(u, va, u1, vb, _rail - 0.17, _rail, 0.072, K_RAIL, RAILC)
				_beam(u, va, u1, vb, _floor, _rail - 0.17, 0.42, K_CONCRETE, M_CONCRETE * 0.72)
			# The contact wire and its messenger.
			_beam(u, side * ha, u1, side * hb, _rail + 5.42, _rail + 5.45, 0.016, K_STEEL, Color(0.45, 0.32, 0.2))
		u = u1
	# Hangers to the roof every 9 m.
	var hu := -tu + 4.0
	while hu < tu:
		var hh := float(line.sample(s0 + hu).half)
		for side: float in [-1.0, 1.0]:
			_box(hu - 0.03, hu + 0.03, _rail + 5.45, MetroStation.PLAT_CEIL, side * hh - 0.03, side * hh + 0.03, K_STEEL, STEEL * 0.6)
		hu += 9.0


## A beam between two frame points (u, v) at a height band, `w` wide across.
func _beam(ua: float, va: float, ub: float, vb: float, h0: float, h1: float, w: float, kind: int, col: Color) -> void:
	var a := _w(Vector3(ua, (h0 + h1) * 0.5, va))
	var b := _w(Vector3(ub, (h0 + h1) * 0.5, vb))
	var along := (b - a)
	along.y = 0.0
	var ax := along * 0.5
	var across := Vector3(-along.z, 0.0, along.x).normalized() * w * 0.5
	box(body, (a + b) * 0.5, ax, Vector3.UP * (h1 - h0) * 0.5, across, _kc(col, kind))


# --- The platform ----------------------------------------------------------------------------

func _platform() -> void:
	var hl := LightRail.PLATFORM_LENGTH * 0.5
	var pw := MetroStation.PLATFORM_WIDTH * 0.5
	var p := _plat
	# The island: terrazzo, the yellow tactile strip and white line at each edge, the coping's
	# face down to the trackbed with its dark refuge recess.
	_flat(-hl, hl, -pw + 0.62, pw - 0.62, p, true, K_TERRAZZO, TERRAZZO)
	for side: float in [-1.0, 1.0]:
		var v0 := side * (pw - 0.62)
		var v1 := side * (pw - 0.05)
		_flat(-hl, hl, minf(v0, v1), maxf(v0, v1), p, true, K_TACTILE, M_YELLOW)
		_flat(-hl, hl, minf(v1, side * pw), maxf(v1, side * pw), p + 0.001, true, K_PAINT, M_WHITE)
		_wall_u(-hl, hl, side * pw, p - 0.25, p, side, K_CONCRETE, M_CONCRETE * 0.9)
		_wall_u(-hl, hl, side * (pw - 0.35), _floor, p - 0.25, side, K_DARK, Color(0, 0, 0))
		_flat(-hl, hl, minf(side * (pw - 0.35), side * pw), maxf(side * (pw - 0.35), side * pw), p - 0.25, false, K_CONCRETE, M_CONCRETE * 0.5)
	for e: float in [-1.0, 1.0]:
		_wall_v(-pw, pw, e * hl, _floor, p, e, K_CONCRETE, M_CONCRETE * 0.85)
		# A railing across the end: nobody walks off it into the tunnel.
		for vv in range(-3, 4):
			var vp := float(vv) * (pw - 0.15) / 3.0
			prism(body, _w(Vector3(e * (hl - 0.1), p, vp)), _w(Vector3(e * (hl - 0.1), p + 1.1, vp)), 0.025, 0.025, 6, _kc(STEEL, K_STEEL), false)
		_beam(e * (hl - 0.1), -pw + 0.15, e * (hl - 0.1), pw - 0.15, p + 1.06, p + 1.12, 0.05, K_STEEL, STEEL)
		_solid(e * (hl - 0.25), e * (hl + 0.05), p, p + 1.2, -pw, pw)
	_solid(-hl, hl, _floor, p, -pw, pw)
	# Benches, bins and the help points along the island (clear of the bank and the lift).
	for u: float in [-25.0, -15.0, 15.0, 25.0]:
		_bench(u, 0.0)
	for u: float in [-20.0, 20.0, -29.5, 29.5]:
		_box(u - 0.25, u + 0.25, p, p + 0.95, -0.25, 0.25, K_STEEL, STEEL * 0.8)
		_box(u - 0.27, u + 0.27, p + 0.95, p + 1.0, -0.27, 0.27, K_PAINT, CORAL)
		_solid(u - 0.25, u + 0.25, p, p + 1.0, -0.25, 0.25)
	# Departure screens hanging over the platform, one each way, and the platform signs.
	var dest := str(line.stations[line.stations.size() - 1].name)
	for u: float in [-10.0, 15.5]:
		_screen(u, p + 2.85)
	for u: float in [-28.0, -18.0, 18.0, 28.0]:
		_hang(Vector3(u, MetroStation.PLAT_CEIL, 0.0), MetroStation.PLAT_CEIL - p - 2.75)
		_sign(Vector3(u, p + 2.6, 0.0), Vector3(1, 0, 0) * signf(u), 2.4, 0.38, "TO " + dest)


func _bench(u: float, v: float) -> void:
	var p := _plat
	_box(u - 1.0, u + 1.0, p + 0.42, p + 0.47, v - 0.24, v + 0.24, K_STEEL, STEEL)
	_box(u - 1.0, u + 1.0, p + 0.47, p + 0.85, v - 0.02, v + 0.02, K_STEEL, STEEL * 0.9)
	for e: float in [-0.85, 0.85]:
		_box(u + e - 0.04, u + e + 0.04, p, p + 0.42, v - 0.2, v + 0.2, K_PAINT, ENAMEL)
	_solid(u - 1.0, u + 1.0, p, p + 0.47, v - 0.24, v + 0.24)


func _hang(top: Vector3, drop: float) -> void:
	for dv: float in [-0.9, 0.9]:
		prism(body, _w(top + Vector3(0, 0, dv)), _w(top + Vector3(0, -drop, dv)), 0.012, 0.012, 4, _kc(STEEL, K_STEEL), false)


## A double-sided departure screen hung at (u, centre height h) over the island.
func _screen(u: float, h: float) -> void:
	var hw := 1.0
	var hh := 0.32
	_hang(Vector3(u, MetroStation.PLAT_CEIL, 0.0), MetroStation.PLAT_CEIL - (h + hh))
	_box(u - 0.07, u + 0.07, h - hh - 0.04, h + hh + 0.04, -hw - 0.04, hw + 0.04, K_ENAMEL, ENAMEL)
	for e: float in [-1.0, 1.0]:
		var uu := u + e * 0.072
		_q(body, Vector3(uu, h - hh, -hw), Vector3(uu, h - hh, hw), Vector3(uu, h + hh, hw), Vector3(uu, h + hh, -hw),
			Vector3(e, 0, 0), K_SCREEN, Color(1.0, 0.72, 0.30), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


## The track walls: tile, the line's band, the station's name every 12 m, lit maps between.
func _platform_walls() -> void:
	var hw := MetroStation.HALF_W
	var bu := MetroStation.BOX_U
	var top := MetroStation.PLAT_CEIL
	var p := _plat
	for side: float in [-1.0, 1.0]:
		var v := side * hw
		_wall_u(-bu, bu, v, _floor, p - 0.3, -side, K_CONCRETE, M_CONCRETE * 0.7)
		_wall_u(-bu, bu, v, p - 0.3, p + 2.05, -side, K_TILE, TILE_PLAT)
		_wall_u(-bu, bu, v, p + 2.05, p + 2.45, -side, K_PAINT, CORAL)
		_wall_u(-bu, bu, v, p + 2.45, top, -side, K_TILE, TILE_PLAT)
		_solid(-bu, bu, _floor, top, v + side * 0.25, v + side * 0.75)
		for k in range(-2, 3):
			var u := float(k) * 12.0
			var at := Vector3(u, p + 3.05, v - side * 0.104)
			_box(u - 2.3, u + 2.3, p + 2.65, p + 3.45, v - side * 0.1, v, K_ENAMEL, ENAMEL)
			_text(str(f.name), 0.4, at, Vector3(0, 0, -side), M_WHITE, 4.3)
			if k < 2:
				var mu := u + 6.0
				_box(mu - 1.3, mu + 1.3, p + 0.75, p + 1.95, v - side * 0.08, v, K_STEEL, STEEL * 0.8)
				_q(body, Vector3(mu - 1.2, p + 0.82, v - side * 0.081), Vector3(mu + 1.2, p + 0.82, v - side * 0.081),
					Vector3(mu + 1.2, p + 1.88, v - side * 0.081), Vector3(mu - 1.2, p + 1.88, v - side * 0.081),
					Vector3(0, 0, -side), K_MAP, M_WHITE, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	# The ceiling: panels round the bank's and the lift's openings, the light lines under it.
	var holes := [Rect2(-MetroStation.BANK_U - 0.3, -MetroStation.BANK_HALF - 0.1, MetroStation.BANK_U * 2.0 + 0.3, MetroStation.BANK_HALF * 2.0 + 0.2),
		Rect2(MetroStation.LIFT_U - 1.15, -1.15, 2.3, 2.3)]
	for rr: Rect2 in _minus(Rect2(-bu, -hw, bu * 2.0, hw * 2.0), holes):
		_flat(rr.position.x, rr.end.x, rr.position.y, rr.end.y, top, false, K_CEIL, CEILING * 0.85)
	var pu := bu - 6.0
	for v: float in [-2.7, 2.7]:
		_box(-pu, pu, top - 0.12, top - 0.02, v - 0.09, v + 0.09, K_LAMP, LAMP, true)
	for v: float in [-6.4, 6.4]:
		_box(-pu, pu, top - 0.22, top - 0.02, v - 0.06, v + 0.06, K_LAMP, LAMP * 0.6, true)


# --- The bank down from the concourse --------------------------------------------------------

## The stair and two escalators from the concourse floor (top at u = -BANK_U) down to the island
## (foot at u = +BANK_U), each lane 1.3 m, with the solid block under them.
func _bank() -> void:
	var bu := MetroStation.BANK_U
	var bh := MetroStation.BANK_HALF
	var top_h := MetroStation.CONC_FLOOR
	var foot_h := _plat
	var lanes := [[-2.1, -0.8, "stair"], [-0.65, 0.65, "esc"], [0.8, 2.1, "esc"]]
	var ua := -bu + 0.3
	var ub := bu - 0.3
	for ln: Array in lanes:
		var v0: float = ln[0]
		var v1: float = ln[1]
		if ln[2] == "stair":
			_stair(ua, top_h, ub, foot_h, v0, v1, 1.0)
		else:
			_escalator(ua, top_h, ub, foot_h, v0, v1, 1.0 if v0 < 0.0 else -1.0)
	# The dividers between lanes and the side walls of the block, sloping with it.
	var line_h := func(u: float) -> float: return lerpf(top_h, foot_h, clampf((u - ua) / (ub - ua), 0.0, 1.0))
	for side: float in [-1.0, 1.0]:
		var v := side * bh
		_q(body, Vector3(-bu, foot_h, v), Vector3(ub, foot_h, v), Vector3(ua, top_h, v), Vector3(-bu, top_h, v), Vector3(0, 0, side), K_TILE, TILE_PLAT)
		_box(-bu, ub, foot_h, foot_h + 0.12, v - 0.04 * side, v + 0.04 * side, K_STEEL, STEEL)
		# The glass over the sides, on the platform and on the concourse.
		for i in 6:
			var u0 := lerpf(ua, ub, float(i) / 6.0)
			var u1 := lerpf(ua, ub, float(i + 1) / 6.0)
			var h0: float = line_h.call(u0)
			var h1: float = line_h.call(u1)
			_pane(Vector3(u0, h0 + 0.1, v), Vector3(u1, h1 + 0.1, v), Vector3(u1, h1 + 1.0, v), Vector3(u0, h0 + 1.0, v), Vector3(0, 0, side))
		_beam(ua, v, ub, v, top_h + 1.0, top_h + 1.05, 0.06, K_STEEL, STEEL)
		_ramp_beam(ua, top_h + 1.05, ub, foot_h + 1.05, v, 0.07, K_RUBBER, ENAMEL)
		_solid(-bu, bu, foot_h, top_h - 0.5, v - side * 0.05, v + side * 0.1)
	_wall_v(-bh, bh, -bu, foot_h, top_h - 0.6, -1.0, K_TILE, TILE_PLAT)
	# The block under the bank: steps of solid so nobody walks under it.
	for i in 4:
		var u0 := lerpf(-bu, ub, float(i) / 4.0)
		var u1 := lerpf(-bu, ub, float(i + 1) / 4.0)
		_solid(u0, u1, foot_h, minf(line_h.call(u1), top_h) - 0.45, -bh, bh)
	# The glass round the opening on the concourse, its end and its sides, and the slab's edge.
	for side: float in [-1.0, 1.0]:
		_pane(Vector3(-bu - 0.3, top_h, side * (bh + 0.1)), Vector3(bu, top_h, side * (bh + 0.1)), Vector3(bu, top_h + 1.05, side * (bh + 0.1)), Vector3(-bu - 0.3, top_h + 1.05, side * (bh + 0.1)), Vector3(0, 0, -side))
		_beam(-bu - 0.3, side * (bh + 0.1), bu, side * (bh + 0.1), top_h + 1.05, top_h + 1.1, 0.07, K_STEEL, STEEL)
		_box(-bu - 0.3, bu, top_h, top_h + 0.12, side * (bh + 0.06), side * (bh + 0.14), K_STEEL, STEEL)
		_wall_u(-bu - 0.3, bu, side * (bh + 0.1), MetroStation.PLAT_CEIL, top_h, -side, K_CONCRETE, M_CONCRETE)
		_solid(-bu - 0.3, bu, top_h, top_h + 1.1, side * (bh + 0.04), side * (bh + 0.16))
	_pane(Vector3(bu, top_h, -bh - 0.1), Vector3(bu, top_h, bh + 0.1), Vector3(bu, top_h + 1.05, bh + 0.1), Vector3(bu, top_h + 1.05, -bh - 0.1), Vector3(-1, 0, 0))
	_beam(bu, -bh - 0.1, bu, bh + 0.1, top_h + 1.05, top_h + 1.1, 0.07, K_STEEL, STEEL)
	_wall_v(-bh - 0.1, bh + 0.1, bu, MetroStation.PLAT_CEIL, top_h, -1.0, K_CONCRETE, M_CONCRETE)
	_solid(bu - 0.04, bu + 0.12, top_h, top_h + 1.1, -bh - 0.1, bh + 0.1)
	_sign(Vector3(-bu - 1.6, MetroStation.CONC_CEIL - 0.55, 0.0), Vector3(-1, 0, 0), 4.0, 0.42, "TRAINS")


## A handrail as a sloped bar from (ua, ha) to (ub, hb) at v.
func _ramp_beam(ua: float, ha: float, ub: float, hb: float, v: float, w: float, kind: int, col: Color) -> void:
	prism(body, _w(Vector3(ua, ha, v)), _w(Vector3(ub, hb, v)), w * 0.5, w * 0.5, 6, _kc(col, kind), false)


## A stair from (ua, ha) down to (ub, hb) between v0 and v1: treads and risers, a landing in the
## middle of a long one, nosings; a ramp for walking.
func _stair(ua: float, ha: float, ub: float, hb: float, v0: float, v1: float, _dir: float) -> void:
	var drop := ha - hb
	var risers := maxi(int(ceil(drop / 0.172)), 2)
	var rise := drop / float(risers)
	var span := ub - ua
	var sgn := signf(span)
	var landing := 1.6 if risers > 24 else 0.0
	var tread := (absf(span) - 0.7 - landing) / float(risers - 1)
	var u := ua
	var h := ha
	var flat0 := 0.35
	_flat(minf(u, u + sgn * flat0), maxf(u, u + sgn * flat0), v0, v1, h, true, K_TERRAZZO, TERRAZZO_DARK)
	u += sgn * flat0
	for i in risers:
		var h2 := h - rise
		_q(body, Vector3(u, h2, v0), Vector3(u, h2, v1), Vector3(u, h, v1), Vector3(u, h, v0), Vector3(sgn, 0, 0), K_TERRAZZO, TERRAZZO_DARK * 0.9)
		var t := tread
		if i == risers - 1:
			t = absf(ub - u)
		elif landing > 0.0 and i == int(risers * 0.5) - 1:
			t = landing
		_flat(minf(u, u + sgn * t), maxf(u, u + sgn * t), v0, v1, h2, true, K_TERRAZZO, TERRAZZO_DARK)
		_box(minf(u, u + sgn * 0.06), maxf(u, u + sgn * 0.06), h2, h2 + 0.008, v0, v1, K_TACTILE if i == 0 or i == risers - 1 else K_STEEL, M_YELLOW if i == 0 or i == risers - 1 else STEEL * 0.9)
		u += sgn * t
		h = h2
	_ramp(ua + sgn * flat0, ha, ub - sgn * 0.3, hb, v0, v1)
	_solid(minf(ua, ua + sgn * flat0), maxf(ua, ua + sgn * flat0), ha - 0.6, ha, v0, v1)


## An escalator from (ua, ha) down to (ub, hb) between v0 and v1 (running `dir`: +1 down): the
## step band (cleats creeping in the shader), flats at both ends with comb plates, skirts, a
## ramp for walking.
func _escalator(ua: float, ha: float, ub: float, hb: float, v0: float, v1: float, dir: float) -> void:
	var sgn := signf(ub - ua)
	var flat := 0.85
	var ia := ua + sgn * flat
	var ib := ub - sgn * flat
	var drop := ha - hb
	var n := maxi(int(drop / 0.2), 2)
	var rise := drop / float(n)
	var run := (ib - ia) / float(n)
	var w0 := v0 + 0.08
	var w1 := v1 - 0.08
	_q(body, Vector3(ua, ha, w0), Vector3(ia, ha, w0), Vector3(ia, ha, w1), Vector3(ua, ha, w1), Vector3.UP, K_ESC, STEEL, Vector2(0, 0), Vector2(0, flat), Vector2(1, flat), Vector2(1, 0), Vector2(dir, 0))
	_q(body, Vector3(ib, hb, w0), Vector3(ub, hb, w0), Vector3(ub, hb, w1), Vector3(ib, hb, w1), Vector3.UP, K_ESC, STEEL, Vector2(0, 0), Vector2(0, flat), Vector2(1, flat), Vector2(1, 0), Vector2(dir, 0))
	for k: float in [ia, ib]:
		_box(k - 0.06, k + 0.06, (ha if k == ia else hb), (ha if k == ia else hb) + 0.012, w0, w1, K_PAINT, M_YELLOW)
	for i in n:
		var u := ia + run * float(i)
		var h := ha - rise * float(i)
		_q(body, Vector3(u, h, w0), Vector3(u + run, h, w0), Vector3(u + run, h, w1), Vector3(u, h, w1), Vector3.UP, K_ESC, STEEL * 0.9, Vector2(0, 0), Vector2(0, absf(run)), Vector2(1, absf(run)), Vector2(1, 0), Vector2(dir, 0))
		_q(body, Vector3(u + run, h, w0), Vector3(u + run, h, w1), Vector3(u + run, h - rise, w1), Vector3(u + run, h - rise, w0), Vector3(sgn, 0, 0), K_ESC, STEEL * 0.7, Vector2(0, 0), Vector2(1, 0), Vector2(1, rise), Vector2(0, rise), Vector2(dir, 0))
		# The yellow demarcation down each step's sides.
		_box(u, u + run, h - 0.004, h + 0.002, w0, w0 + 0.04, K_PAINT, M_YELLOW)
		_box(u, u + run, h - 0.004, h + 0.002, w1 - 0.04, w1, K_PAINT, M_YELLOW)
	# Skirts and the inner decking, the balustrade glass and the black handrail on top.
	for side: float in [-1.0, 1.0]:
		var v := w0 - 0.02 if side < 0.0 else w1 + 0.02
		_q(body, Vector3(ua, ha - 0.2, v), Vector3(ia, ha - 0.2, v), Vector3(ia, ha + 0.12, v), Vector3(ua, ha + 0.12, v), Vector3(0, 0, -side), K_STEEL, STEEL)
		_q(body, Vector3(ia, ha - 0.2, v), Vector3(ib, hb - 0.2, v), Vector3(ib, hb + 0.12, v), Vector3(ia, ha + 0.12, v), Vector3(0, 0, -side), K_STEEL, STEEL)
		_q(body, Vector3(ib, hb - 0.2, v), Vector3(ub, hb - 0.2, v), Vector3(ub, hb + 0.12, v), Vector3(ib, hb + 0.12, v), Vector3(0, 0, -side), K_STEEL, STEEL)
		var gv := v + side * 0.03
		_pane(Vector3(ua, ha + 0.12, gv), Vector3(ia, ha + 0.12, gv), Vector3(ia, ha + 0.95, gv), Vector3(ua, ha + 0.95, gv), Vector3(0, 0, side))
		_pane(Vector3(ia, ha + 0.12, gv), Vector3(ib, hb + 0.12, gv), Vector3(ib, hb + 0.95, gv), Vector3(ia, ha + 0.95, gv), Vector3(0, 0, side))
		_pane(Vector3(ib, hb + 0.12, gv), Vector3(ub, hb + 0.12, gv), Vector3(ub, hb + 0.95, gv), Vector3(ib, hb + 0.95, gv), Vector3(0, 0, side))
		prism(body, _w(Vector3(ua - sgn * 0.3, ha + 0.98, gv)), _w(Vector3(ia, ha + 0.98, gv)), 0.04, 0.04, 6, _kc(ENAMEL, K_RUBBER), false)
		prism(body, _w(Vector3(ia, ha + 0.98, gv)), _w(Vector3(ib, hb + 0.98, gv)), 0.04, 0.04, 6, _kc(ENAMEL, K_RUBBER), false)
		prism(body, _w(Vector3(ib, hb + 0.98, gv)), _w(Vector3(ub + sgn * 0.3, hb + 0.98, gv)), 0.04, 0.04, 6, _kc(ENAMEL, K_RUBBER), false)
	_ramp(ia, ha, ib, hb, v0, v1)


# --- The lift --------------------------------------------------------------------------------

func _lift() -> void:
	var u := MetroStation.LIFT_U
	var a := 1.05
	var h0 := _plat
	var h1 := MetroStation.CONC_FLOOR + 2.7
	for cu: float in [-a, a]:
		for cv: float in [-a, a]:
			_box(u + cu - 0.06, u + cu + 0.06, h0, h1, cv - 0.06, cv + 0.06, K_STEEL, STEEL * 0.85)
	for e: float in [-1.0, 1.0]:
		_pane(Vector3(u - a, h0, e * a), Vector3(u + a, h0, e * a), Vector3(u + a, h1, e * a), Vector3(u - a, h1, e * a), Vector3(0, 0, e))
		_pane(Vector3(u + e * a, h0, -a), Vector3(u + e * a, h0, a), Vector3(u + e * a, h1, a), Vector3(u + e * a, h1, -a), Vector3(e, 0, 0))
	_box(u - a - 0.06, u + a + 0.06, h1, h1 + 0.25, -a - 0.06, a + 0.06, K_STEEL, STEEL * 0.85, true)
	# The car, parked at the platform: a steel floor and ceiling and a lit panel.
	_box(u - a + 0.1, u + a - 0.1, h0, h0 + 0.05, -a + 0.1, a - 0.1, K_STEEL, STEEL * 0.6)
	_box(u - a + 0.1, u + a - 0.1, h0 + 2.3, h0 + 2.36, -a + 0.1, a - 0.1, K_LAMP, LAMP, true)
	for rail_h: float in [h0 + 0.95]:
		_beam(u - a + 0.12, -a + 0.15, u + a - 0.12, -a + 0.15, rail_h, rail_h + 0.04, 0.04, K_STEEL, STEEL)
	_solid(u - a - 0.1, u + a + 0.1, h0, h1, -a - 0.1, a + 0.1)


# --- The concourse ---------------------------------------------------------------------------

func _concourse() -> void:
	var cu := MetroStation.CONC_U
	var hw := MetroStation.HALF_W
	var fl := MetroStation.CONC_FLOOR
	var cl := MetroStation.CONC_CEIL
	var bu := MetroStation.BANK_U
	var bh := MetroStation.BANK_HALF
	var lu := MetroStation.LIFT_U
	# The floor round the bank and the lift; the slab's edge round the bank.
	var holes := [Rect2(-bu - 0.3, -bh - 0.1, bu * 2.0 + 0.3, bh * 2.0 + 0.2), Rect2(lu - 1.15, -1.15, 2.3, 2.3)]
	for rr: Rect2 in _minus(Rect2(-cu, -hw, cu * 2.0, hw * 2.0), holes):
		_flat(rr.position.x, rr.end.x, rr.position.y, rr.end.y, fl, true, K_TERRAZZO, TERRAZZO)
		_solid(rr.position.x, rr.end.x, fl - 0.6, fl, rr.position.y, rr.end.y)
	# A darker border band round the floor and a line down the middle of each half.
	for side: float in [-1.0, 1.0]:
		_flat(-cu, cu, minf(side * (hw - 0.45), side * (hw - 0.05)), maxf(side * (hw - 0.45), side * (hw - 0.05)), fl + 0.001, true, K_TERRAZZO, TERRAZZO_DARK)
	# The ceiling round the two shafts, its lights.
	var shafts := []
	for k: float in [-1.0, 1.0]:
		var a := k * MetroStation.SHAFT_IN
		var b := k * cu
		shafts.append(Rect2(minf(a, b), -1.8, absf(b - a), 3.6))
	for rr: Rect2 in _minus(Rect2(-cu, -hw, cu * 2.0, hw * 2.0), shafts):
		_flat(rr.position.x, rr.end.x, rr.position.y, rr.end.y, cl, false, K_CEIL, CEILING)
		_solid(rr.position.x, rr.end.x, cl, cl + 1.2, rr.position.y, rr.end.y)
	for v: float in [-4.4, 4.4]:
		_box(-cu + 0.5, cu - 0.5, cl - 0.1, cl - 0.01, v - 0.11, v + 0.11, K_LAMP, LAMP, true)
	_box(-MetroStation.SHAFT_IN + 0.4, MetroStation.SHAFT_IN - 0.4, cl - 0.1, cl - 0.01, -0.08, 0.08, K_LAMP, LAMP * 0.85, true)
	# Walls: tile, a coral band, a base; the end walls; their collision.
	for side: float in [-1.0, 1.0]:
		var v := side * hw
		_wall_u(-cu, cu, v, fl, fl + 0.15, -side, K_ENAMEL, ENAMEL)
		_wall_u(-cu, cu, v, fl + 0.15, fl + 2.3, -side, K_TILE, TILE_WALL)
		_wall_u(-cu, cu, v, fl + 2.3, fl + 2.6, -side, K_PAINT, CORAL)
		_wall_u(-cu, cu, v, fl + 2.6, cl, -side, K_TILE, TILE_WALL)
		_solid(-cu, cu, fl, cl, v + side * 0.25, v + side * 0.75)
	for e: float in [-1.0, 1.0]:
		var u := e * cu
		for seg: Array in [[-hw, -1.75], [1.75, hw]]:
			_wall_v(seg[0], seg[1], u, fl, cl, -e, K_TILE, TILE_WALL)
		_solid(u + e * 0.25, u + e * 0.75, fl, cl, -hw, hw)
		# A lit system map on each end wall, either side of the stair block.
		for side: float in [-1.0, 1.0]:
			var mv := side * 4.4
			_box(u - e * 0.08, u, fl + 0.9, fl + 2.1, mv - 1.4, mv + 1.4, K_STEEL, STEEL * 0.8)
			_q(body, Vector3(u - e * 0.081, fl + 0.97, mv - 1.3), Vector3(u - e * 0.081, fl + 0.97, mv + 1.3),
				Vector3(u - e * 0.081, fl + 2.03, mv + 1.3), Vector3(u - e * 0.081, fl + 2.03, mv - 1.3), Vector3(-e, 0, 0),
				K_MAP, M_WHITE, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	# Columns down the concourse's middle line either side of the paid zone.
	for u: float in [-26.0, -17.0, 17.0, 26.0]:
		for side: float in [-1.0, 1.0]:
			var v := side * 4.0
			_box(u - 0.35, u + 0.35, fl, cl, v - 0.35, v + 0.35, K_TILE, TILE_WALL)
			_box(u - 0.36, u + 0.36, fl + 2.3, fl + 2.6, v - 0.36, v + 0.36, K_PAINT, CORAL)
			_solid(u - 0.35, u + 0.35, fl, cl, v - 0.35, v + 0.35)
	# The lift's door on the concourse.
	_sign(Vector3(lu, cl - 0.45, 0.0), Vector3(-1, 0, 0), 1.9, 0.32, "LIFT", false)


## Rect `r` less `holes`, as rects.
static func _minus(r: Rect2, holes: Array) -> Array:
	var pieces: Array = [r]
	for hole: Rect2 in holes:
		var next: Array = []
		for q: Rect2 in pieces:
			var h := hole.intersection(q)
			if h.size.x <= 0.0 or h.size.y <= 0.0:
				next.append(q)
				continue
			for p: Rect2 in [Rect2(q.position.x, q.position.y, h.position.x - q.position.x, q.size.y),
					Rect2(h.end.x, q.position.y, q.end.x - h.end.x, q.size.y),
					Rect2(h.position.x, q.position.y, h.size.x, h.position.y - q.position.y),
					Rect2(h.position.x, h.end.y, h.size.x, q.end.y - h.end.y)]:
				if p.size.x > 0.01 and p.size.y > 0.01:
					next.append(p)
		pieces = next
	return pieces


## The fare gate lines across the concourse at -+GATE_U: cabinets 1.3 m apart with glass paddles,
## their lit readers, a sign over each line.
func _gates() -> void:
	var fl := MetroStation.CONC_FLOOR
	var hw := MetroStation.HALF_W
	for e: float in [-1.0, 1.0]:
		var u := e * MetroStation.GATE_U
		for i in 11:
			var v := -6.5 + float(i) * 1.3
			_box(u - 0.7, u + 0.7, fl, fl + 0.98, v - 0.12, v + 0.12, K_STEEL, STEEL)
			_box(u - 0.72, u + 0.72, fl + 0.98, fl + 1.03, v - 0.13, v + 0.13, K_ENAMEL, ENAMEL)
			# The card reader at the unpaid end, lit green.
			_box(u + e * 0.45 - 0.12, u + e * 0.45 + 0.12, fl + 1.03, fl + 1.06, v - 0.08, v + 0.08, K_LAMP, Color(0.3, 1.0, 0.45))
			_box(u + e * 0.68 - 0.02, u + e * 0.68 + 0.02, fl + 0.7, fl + 0.95, v - 0.08, v + 0.08, K_LAMP, CORAL)
			_solid(u - 0.7, u + 0.7, fl, fl + 1.05, v - 0.12, v + 0.12)
			if i < 10:
				for sgn: float in [-1.0, 1.0]:
					var pv := v + 0.13 if sgn < 0.0 else v + 1.3 - 0.13
					var tip := pv + (0.32 if sgn < 0.0 else -0.32)
					_pane(Vector3(u - 0.05, fl + 0.55, pv), Vector3(u - 0.05, fl + 0.55, tip), Vector3(u - 0.05, fl + 1.25, tip), Vector3(u - 0.05, fl + 1.1, pv), Vector3(1, 0, 0))
		_beam(u, -hw, u, hw, MetroStation.CONC_CEIL - 0.05, MetroStation.CONC_CEIL, 0.1, K_STEEL, STEEL)
		for sv: float in [-4.0, 4.0]:
			_hang(Vector3(u, MetroStation.CONC_CEIL, sv), 0.25)
			_sign(Vector3(u, MetroStation.CONC_CEIL - 0.5, sv), Vector3(e, 0, 0), 3.2, 0.42, "TO TRAINS")


## Ticket machines along the walls of the unpaid ends, three a side an end.
func _machines() -> void:
	var fl := MetroStation.CONC_FLOOR
	var hw := MetroStation.HALF_W
	for e: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			for k in 3:
				var u := e * (19.5 + float(k) * 1.15)
				var v := side * (hw - 0.33)
				var back := side * hw
				_box(u - 0.45, u + 0.45, fl, fl + 1.85, minf(v - side * 0.3, back), maxf(v - side * 0.3, back), K_ENAMEL, Color(0.20, 0.21, 0.23))
				_box(u - 0.46, u + 0.46, fl + 1.85, fl + 2.05, minf(v - side * 0.31, back), maxf(v - side * 0.31, back), K_PAINT, CORAL)
				var fv := v - side * 0.302
				_q(body, Vector3(u - 0.3, fl + 1.2, fv), Vector3(u + 0.3, fl + 1.2, fv), Vector3(u + 0.3, fl + 1.62, fv), Vector3(u - 0.3, fl + 1.62, fv),
					Vector3(0, 0, -side), K_SCREEN, Color(0.45, 0.70, 1.0), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
				_box(u - 0.12, u + 0.12, fl + 1.0, fl + 1.08, fv - side * 0.03, fv, K_LAMP, Color(0.3, 1.0, 0.45))
				_box(u - 0.2, u + 0.2, fl + 0.45, fl + 0.6, fv - side * 0.05, fv, K_STEEL, STEEL * 0.6)
				_solid(u - 0.45, u + 0.45, fl, fl + 2.05, minf(v - side * 0.3, back), maxf(v - side * 0.3, back))
			_sign(Vector3(e * 20.65, fl + 2.85, side * (hw - 0.07)), Vector3(0, 0, -side), 3.4, 0.36, "TICKETS", false)


# --- The street stairs -----------------------------------------------------------------------

## Kiosk k's stair and escalator from the street (mouth at k * MOUTH_U) down to the concourse,
## the shaft round them, and the block they stand on in the concourse.
func _kiosk_stairs(k: float) -> void:
	var lh := MetroStation.LANE_HALF
	var fl := MetroStation.CONC_FLOOR
	var cl := MetroStation.CONC_CEIL
	var top_u := k * MetroStation.MOUTH_U
	var foot_u := top_u - k * MetroStation.RUN
	var kerb := 0.16
	_stair(top_u, kerb, foot_u, fl, -lh + 0.03, -0.12, 1.0)
	_escalator(top_u, kerb, foot_u, fl, 0.12, lh - 0.03, 1.0)
	_box(minf(top_u, foot_u), maxf(top_u, foot_u), fl, fl + 0.02, -0.12, 0.12, K_STEEL, STEEL)
	_ramp_beam(top_u, kerb + 0.95, foot_u, fl + 0.95, 0.0, 0.08, K_STEEL, STEEL)
	var shaft_u := k * MetroStation.SHAFT_IN
	var line_h := func(u: float) -> float: return lerpf(kerb, fl, clampf((u - top_u) / (foot_u - top_u), 0.0, 1.0))
	var wv := lh + 0.13
	for side: float in [-1.0, 1.0]:
		var v := side * wv
		# The shaft: tile from the street down past the concourse ceiling to the floor where it is
		# closed off from the concourse, a low wall and glass where it opens into it.
		_wall_u(minf(shaft_u, top_u + k * 0.15), maxf(shaft_u, top_u + k * 0.15), v, fl, 0.0, -side, K_TILE, TILE_WALL)
		_wall_u(minf(shaft_u, k * MetroStation.CONC_U), maxf(shaft_u, k * MetroStation.CONC_U), v + side * 0.25, fl, cl, side, K_TILE, TILE_WALL)
		_solid(minf(shaft_u, k * (MetroStation.CONC_U + 0.2)), maxf(shaft_u, k * (MetroStation.CONC_U + 0.2)), fl, 0.0, v, v + side * 0.25)
		var hs: float = line_h.call(shaft_u)
		_q(body, Vector3(foot_u, fl, v + side * 0.25), Vector3(shaft_u, fl, v + side * 0.25), Vector3(shaft_u, hs + 0.15, v + side * 0.25), Vector3(foot_u, fl + 0.15, v + side * 0.25), Vector3(0, 0, side), K_TILE, TILE_WALL)
		_q(body, Vector3(foot_u, fl, v), Vector3(shaft_u, fl, v), Vector3(shaft_u, hs + 0.15, v), Vector3(foot_u, fl + 0.15, v), Vector3(0, 0, -side), K_TILE, TILE_WALL)
		_q(body, Vector3(foot_u, fl + 0.15, v), Vector3(shaft_u, hs + 0.15, v), Vector3(shaft_u, hs + 0.15, v + side * 0.25), Vector3(foot_u, fl + 0.15, v + side * 0.25), Vector3.UP, K_STEEL, STEEL)
		_pane(Vector3(foot_u, fl + 0.15, v + side * 0.12), Vector3(shaft_u, hs + 0.15, v + side * 0.12), Vector3(shaft_u, hs + 1.1, v + side * 0.12), Vector3(foot_u, fl + 1.1, v + side * 0.12), Vector3(0, 0, side))
		_ramp_beam(foot_u, fl + 1.1, shaft_u, hs + 1.1, v + side * 0.12, 0.06, K_STEEL, STEEL)
		for i in 3:
			var u0 := lerpf(foot_u, shaft_u, float(i) / 3.0)
			var u1 := lerpf(foot_u, shaft_u, float(i + 1) / 3.0)
			_solid(minf(u0, u1), maxf(u0, u1), fl, float(line_h.call(u1 if absf(u1) > absf(u0) else u0)) + 1.1, v, v + side * 0.25)
	# The bulkhead over the stair where it passes under the concourse ceiling, and the shaft's
	# outer end under the mouth.
	_wall_v(-wv, wv, shaft_u, cl, 0.0, k, K_TILE, TILE_WALL)
	_wall_v(-wv - 0.25, wv + 0.25, shaft_u, cl - 0.35, cl, -k, K_PAINT, CEILING)
	_flat(minf(shaft_u, shaft_u - k * 0.25), maxf(shaft_u, shaft_u - k * 0.25), -wv - 0.25, wv + 0.25, cl - 0.35, false, K_PAINT, CEILING)
	_solid(minf(shaft_u, shaft_u + k * 0.3), maxf(shaft_u, shaft_u + k * 0.3), cl, 0.0, -wv, wv)
	_wall_v(-wv, wv, top_u + k * 0.15, fl, kerb, -k, K_TILE, TILE_WALL)
	_solid(minf(top_u + k * 0.15, top_u + k * 0.6), maxf(top_u + k * 0.15, top_u + k * 0.6), fl, kerb, -wv, wv)
	# Lights down the shaft.
	_box(minf(shaft_u, top_u), maxf(shaft_u, top_u), -0.35, -0.25, -wv - 0.0, -wv + 0.08, K_LAMP, LAMP * 0.8)
	_box(minf(shaft_u, top_u), maxf(shaft_u, top_u), -0.35, -0.25, wv - 0.08, wv, K_LAMP, LAMP * 0.8)
	var exits := MetroStation.exit_names(line)
	var street_name := str(exits[0 if k < 0.0 else 1])
	_sign(Vector3(k * (MetroStation.GATE_U + 3.2), cl - 0.5, 0.0), Vector3(-k, 0, 0), 4.2, 0.42, "EXIT  " + LightRail._short(street_name) if street_name != "" else "EXIT", false)


## Kiosk k at the street: the kerb island round the opening, a low wall and glass on three sides,
## the glass canopy on four posts with the line's band and the agency's name, a lit pylon.
func _kiosk(k: float) -> void:
	var lh := MetroStation.LANE_HALF + 0.13
	var a := k * (MetroStation.KIOSK_U - MetroStation.KIOSK_HALF)
	var b := k * (MetroStation.KIOSK_U + MetroStation.KIOSK_HALF)
	var u0 := minf(a, b)
	var u1 := maxf(a, b)
	var o0 := minf(k * MetroStation.SHAFT_IN, k * (MetroStation.MOUTH_U + 0.15))
	var o1 := maxf(k * MetroStation.SHAFT_IN, k * (MetroStation.MOUTH_U + 0.15))
	var hw := lh + 0.6
	var kerb := 0.16
	var island := Color(0.66, 0.65, 0.62)
	for rr: Rect2 in _minus(Rect2(u0, -hw, u1 - u0, hw * 2.0), [Rect2(o0, -lh, o1 - o0, lh * 2.0)]):
		_box(rr.position.x, rr.end.x, 0.0, kerb, rr.position.y, rr.end.y, K_CONCRETE, island)
		_solid(rr.position.x, rr.end.x, -0.2, kerb, rr.position.y, rr.end.y)
	# The walls: both sides and the inner end; the outer end is the way in.
	var inner := k * MetroStation.SHAFT_IN
	for side: float in [-1.0, 1.0]:
		var v := side * (lh + 0.12)
		_box(o0, o1, kerb, kerb + 0.45, v - 0.1, v + 0.1, K_STEEL, STEEL)
		_pane(Vector3(o0, kerb + 0.45, v), Vector3(o1, kerb + 0.45, v), Vector3(o1, kerb + 1.15, v), Vector3(o0, kerb + 1.15, v), Vector3(0, 0, side))
		_beam(o0, v, o1, v, kerb + 1.12, kerb + 1.18, 0.07, K_STEEL, STEEL)
		_solid(o0, o1, kerb, kerb + 1.2, v - 0.1, v + 0.1)
	_box(minf(inner, inner - k * 0.2), maxf(inner, inner - k * 0.2), kerb, kerb + 1.18, -lh - 0.2, lh + 0.2, K_STEEL, STEEL)
	_solid(minf(inner, inner - k * 0.2), maxf(inner, inner - k * 0.2), kerb, kerb + 1.2, -lh - 0.2, lh + 0.2)
	# The canopy: posts, the glass roof sloping to the inner end, beams, the band and its lettering.
	var roof_hi := 3.3
	var roof_lo := 3.0
	var po := lh + 0.25
	for pu: float in [o0 + 0.15, o1 - 0.15]:
		for side: float in [-1.0, 1.0]:
			var hh := roof_hi if absf(pu - k * MetroStation.MOUTH_U) < 1.0 else roof_lo
			_box(pu - 0.07, pu + 0.07, kerb, hh, side * po - 0.07, side * po + 0.07, K_STEEL, Color(0.26, 0.27, 0.29))
			_solid(pu - 0.08, pu + 0.08, kerb, hh, side * po - 0.08, side * po + 0.08)
	var hi_u := o1 if k > 0.0 else o0
	var lo_u := o0 if k > 0.0 else o1
	var rw := po + 0.35
	_pane(Vector3(hi_u + k * 0.4, roof_hi, -rw), Vector3(hi_u + k * 0.4, roof_hi, rw), Vector3(lo_u - k * 0.2, roof_lo, rw), Vector3(lo_u - k * 0.2, roof_lo, -rw), Vector3.UP)
	for side: float in [-1.0, 1.0]:
		_ramp_beam(hi_u + k * 0.4, roof_hi - 0.05, lo_u - k * 0.2, roof_lo - 0.05, side * rw, 0.12, K_STEEL, Color(0.26, 0.27, 0.29))
	# The fascia over the way in: the line's colour, BASIN METRO and the line's bullet.
	var fu := hi_u + k * 0.45
	_box(minf(fu, fu + k * 0.12), maxf(fu, fu + k * 0.12), roof_hi - 0.45, roof_hi + 0.05, -rw, rw, K_PAINT, CORAL)
	_text(LightRail.AGENCY.to_upper(), 0.24, Vector3(fu + k * 0.125, roof_hi - 0.2, 0.25), Vector3(k, 0, 0), M_WHITE, rw * 1.4)
	_disc(Vector3(fu + k * 0.125, roof_hi - 0.2, -rw + 0.35), Vector3(k, 0, 0), 0.19, Color(1, 1, 1))
	_text(LightRail.LINE_LETTER, 0.26, Vector3(fu + k * 0.128, roof_hi - 0.2, -rw + 0.35), Vector3(k, 0, 0), Color(CORAL.r, CORAL.g, CORAL.b))
	# Lights under the canopy's edges.
	for side: float in [-1.0, 1.0]:
		_box(o0 + 0.3, o1 - 0.3, roof_lo - 0.12, roof_lo - 0.05, side * po - 0.05, side * po + 0.05, K_LAMP, LAMP)
	pool(_w(Vector3((o0 + o1) * 0.5, kerb + 0.02, 0.0)), _d3, Vector2(o1 - o0 + 3.0, hw * 2.0 + 2.5), Color(1.0, 0.93, 0.8, 0.45))
	# What casts in the sun: the side walls, the inner wall, the canopy (tinted glass casts a light
	# shadow in life; a full one reads better than none), the fascia, the posts.
	for side: float in [-1.0, 1.0]:
		_box(o0, o1, kerb, kerb + 0.5, side * (lh + 0.12) - 0.1, side * (lh + 0.12) + 0.1, K_CONCRETE, M_CONCRETE, false, shadow)
		for pu: float in [o0 + 0.15, o1 - 0.15]:
			_box(pu - 0.07, pu + 0.07, kerb, roof_lo, side * po - 0.07, side * po + 0.07, K_CONCRETE, M_CONCRETE, false, shadow)
	_box(minf(inner, inner - k * 0.2), maxf(inner, inner - k * 0.2), kerb, kerb + 1.18, -lh - 0.2, lh + 0.2, K_CONCRETE, M_CONCRETE, false, shadow)
	_box(o0, o1, roof_lo - 0.05, roof_lo, -rw, rw, K_CONCRETE, M_CONCRETE, true, shadow)
	_box(minf(fu, fu + k * 0.12), maxf(fu, fu + k * 0.12), roof_hi - 0.45, roof_hi + 0.05, -rw, rw, K_CONCRETE, M_CONCRETE, true, shadow)
	# The pylon on the island's inner end: the bullet, the station's name, BASIN METRO.
	var pu2 := k * (MetroStation.KIOSK_U - MetroStation.KIOSK_HALF + 0.25)
	_box(pu2 - 0.2, pu2 + 0.2, kerb, kerb + 3.4, -0.45, 0.45, K_ENAMEL, ENAMEL)
	_box(pu2 - 0.22, pu2 + 0.22, kerb + 3.4, kerb + 3.95, -0.47, 0.47, K_PAINT, CORAL)
	_solid(pu2 - 0.22, pu2 + 0.22, kerb, kerb + 3.95, -0.47, 0.47)
	_box(pu2 - 0.22, pu2 + 0.22, kerb, kerb + 3.95, -0.47, 0.47, K_CONCRETE, M_CONCRETE, false, shadow)
	for e: float in [-1.0, 1.0]:
		_text(LightRail.LINE_LETTER, 0.42, Vector3(pu2 + e * 0.225, kerb + 3.67, 0.0), Vector3(e, 0, 0), M_WHITE)
		_text(LightRail._short(str(f.name).split(" / ")[0]), 0.16, Vector3(pu2 + e * 0.205, kerb + 2.9, 0.0), Vector3(e, 0, 0), M_WHITE, 0.8)
		_text(LightRail._short(str(f.name).split(" / ")[-1]), 0.16, Vector3(pu2 + e * 0.205, kerb + 2.62, 0.0), Vector3(e, 0, 0), M_WHITE, 0.8)
		_text("METRO", 0.11, Vector3(pu2 + e * 0.205, kerb + 0.6, 0.0), Vector3(e, 0, 0), Color(0.85, 0.85, 0.83), 0.8)


# --- The roof (shadow only) and the commit ---------------------------------------------------

## A slab over the whole station that only casts: the sun does not reach in except down the
## stairs. Round the openings.
func _roof() -> void:
	var tu := MetroStation.TUNNEL_U + 2.0
	var hw := MetroStation.HALF_W + 1.0
	var holes := []
	for o: Array in MetroStation.openings():
		holes.append(Rect2(float(o[0]), float(o[2]), float(o[1]) - float(o[0]), float(o[3]) - float(o[2])))
	for rr: Rect2 in _minus(Rect2(-tu, -hw, tu * 2.0, hw * 2.0), holes):
		_box(rr.position.x, rr.end.x, -1.0, -0.6, rr.position.y, rr.end.y, K_CONCRETE, M_CONCRETE, true, shadow)
	for side: float in [-1.0, 1.0]:
		_box(-tu, tu, _floor - 0.5, -0.6, side * hw - 0.2, side * hw + 0.2, K_CONCRETE, M_CONCRETE, false, shadow)


## The interior material, one per station (its frame in the uniforms).
func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/metro_station.gdshader")
	m.set_shader_parameter("st_origin", f.o)
	m.set_shader_parameter("st_dir", f.d)
	m.set_shader_parameter("st_base", float(f.y0))
	m.set_shader_parameter("plat_h", _plat)
	m.set_shader_parameter("rail_h", _rail)
	m.set_shader_parameter("conc_floor", MetroStation.CONC_FLOOR)
	m.set_shader_parameter("conc_ceil", MetroStation.CONC_CEIL)
	m.set_shader_parameter("plat_ceil", MetroStation.PLAT_CEIL)
	m.set_shader_parameter("box_u", MetroStation.BOX_U)
	m.set_shader_parameter("conc_u", MetroStation.CONC_U)
	return m


func _commit() -> void:
	var mat := _material()
	var mi := MeshInstance3D.new()
	mi.name = "MetroStation"
	mi.mesh = body.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(mi)
	if _paint_any:
		var pm := MeshInstance3D.new()
		pm.name = "MetroSigns"
		pm.mesh = paint.commit()
		pm.material_override = mat
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(pm)
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/metro_glass.gdshader")
	gm.set_shader_parameter("st_base", float(f.y0))
	var gl := MeshInstance3D.new()
	gl.name = "MetroGlass"
	gl.mesh = glass.commit()
	gl.material_override = gm
	gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(gl)
	var sh := MeshInstance3D.new()
	sh.name = "MetroShadow"
	sh.mesh = shadow.commit()
	sh.material_override = mat
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	chunk.add_child(sh)
	if _glow_any:
		var gi := MeshInstance3D.new()
		gi.name = "MetroGlow"
		gi.mesh = glow.commit()
		gi.material_override = pool_material()
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(gi)
	var sb := StaticBody3D.new()
	sb.name = "MetroBody"
	sb.collision_layer = 1
	sb.collision_mask = 0
	for s: Array in _shapes:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = s[0]
		cs.shape = bx
		cs.transform = s[1]
		sb.add_child(cs)
	chunk.add_child(sb)
	_add_occluder()
	_add_lights()
	_add_probe()
	_add_zone()
	_add_riders()


## An occluder shell a little inside the concrete round the station (the concourse's ceiling and
## the slab between the levels, the tunnel's roof, the side and end walls; never over a stair's
## opening): from down here the city above is culled. From the street it hides only what is
## under the street (CLAUDE.md: an occluder lies inside what it stands for).
func _add_occluder() -> void:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var quad_at := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		var i0 := verts.size()
		for p: Vector3 in [a, b, c, d]:
			verts.append(_w(p))
		idx.append_array([i0, i0 + 1, i0 + 2, i0, i0 + 2, i0 + 3])
	var hw := MetroStation.HALF_W
	var cu := MetroStation.CONC_U
	var tu := MetroStation.TUNNEL_U
	var shafts := []
	for k: float in [-1.0, 1.0]:
		var a := k * MetroStation.SHAFT_IN
		var b := k * (cu + 0.5)
		shafts.append(Rect2(minf(a, b), -2.0, absf(b - a), 4.0))
	var ceil_h := MetroStation.CONC_CEIL + 0.3
	for rr: Rect2 in _minus(Rect2(-cu - 0.4, -hw - 0.4, (cu + 0.4) * 2.0, (hw + 0.4) * 2.0), shafts):
		quad_at.call(Vector3(rr.position.x, ceil_h, rr.position.y), Vector3(rr.end.x, ceil_h, rr.position.y), Vector3(rr.end.x, ceil_h, rr.end.y), Vector3(rr.position.x, ceil_h, rr.end.y))
	var mid_h := MetroStation.CONC_FLOOR - 0.3
	var holes := [Rect2(-MetroStation.BANK_U - 0.5, -MetroStation.BANK_HALF - 0.3, MetroStation.BANK_U * 2.0 + 0.8, MetroStation.BANK_HALF * 2.0 + 0.6),
		Rect2(MetroStation.LIFT_U - 1.4, -1.4, 2.8, 2.8)]
	for rr: Rect2 in _minus(Rect2(-cu, -hw, cu * 2.0, hw * 2.0), holes):
		quad_at.call(Vector3(rr.position.x, mid_h, rr.position.y), Vector3(rr.end.x, mid_h, rr.position.y), Vector3(rr.end.x, mid_h, rr.end.y), Vector3(rr.position.x, mid_h, rr.end.y))
	var roof_h := MetroStation.PLAT_CEIL + 0.3
	for e: float in [-1.0, 1.0]:
		var a := e * cu
		var b := e * (tu + 0.3)
		quad_at.call(Vector3(minf(a, b), roof_h, -hw - 0.3), Vector3(maxf(a, b), roof_h, -hw - 0.3), Vector3(maxf(a, b), roof_h, hw + 0.3), Vector3(minf(a, b), roof_h, hw + 0.3))
		quad_at.call(Vector3(e * (tu + 0.3), _floor, -hw - 0.3), Vector3(e * (tu + 0.3), _floor, hw + 0.3), Vector3(e * (tu + 0.3), roof_h, hw + 0.3), Vector3(e * (tu + 0.3), roof_h, -hw - 0.3))
		quad_at.call(Vector3(e * (cu + 0.4), roof_h, -hw - 0.3), Vector3(e * (cu + 0.4), roof_h, hw + 0.3), Vector3(e * (cu + 0.4), ceil_h, hw + 0.3), Vector3(e * (cu + 0.4), ceil_h, -hw - 0.3))
	for side: float in [-1.0, 1.0]:
		var v := side * (hw + 0.3)
		quad_at.call(Vector3(-tu - 0.3, _floor, v), Vector3(tu + 0.3, _floor, v), Vector3(tu + 0.3, roof_h, v), Vector3(-tu - 0.3, roof_h, v))
		quad_at.call(Vector3(-cu - 0.4, roof_h, v), Vector3(cu + 0.4, roof_h, v), Vector3(cu + 0.4, ceil_h, v), Vector3(-cu - 0.4, ceil_h, v))
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, idx)
	var oi := OccluderInstance3D.new()
	oi.name = "MetroOccluder"
	oi.occluder = occ
	chunk.add_child(oi)


## The station's own lights for the trains and the people (Forward+ / desktop; never the web),
## shown only while the player is down here.
func _add_lights() -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	var spots := []
	for u: float in [-24.0, -8.0, 8.0, 24.0]:
		spots.append([Vector3(u, MetroStation.PLAT_CEIL - 0.6, 0.0), 13.0, 1.6])
	for u: float in [-24.0, 0.0, 24.0]:
		spots.append([Vector3(u, MetroStation.CONC_CEIL - 0.4, 0.0), 14.0, 1.2])
	for sp: Array in spots:
		var l := OmniLight3D.new()
		l.omni_range = sp[1]
		l.light_energy = sp[2]
		l.light_color = Color(1.0, 0.93, 0.84)
		l.shadow_enabled = false
		l.position = _w(sp[0])
		l.visible = false
		l.add_to_group("metro_light")
		chunk.add_child(l)
		_lights.append(l)


## An interior reflection probe over both levels: what lit surfaces down here mirror, and the
## ambient they take instead of the sky's (Forward+ desktop).
func _add_probe() -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return
	var p := ReflectionProbe.new()
	p.name = "MetroProbe"
	var h0 := _floor - 0.2
	var h1 := MetroStation.CONC_CEIL + 0.1
	p.size = Vector3(MetroStation.BOX_U * 2.0, h1 - h0, MetroStation.HALF_W * 2.0 + 0.6)
	p.interior = true
	p.box_projection = true
	p.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	p.ambient_color = Color(0.55, 0.52, 0.48)
	p.ambient_color_energy = 0.55
	p.update_mode = ReflectionProbe.UPDATE_ONCE
	p.transform = Transform3D(Basis(_d3, Vector3.UP, _r3), _w(Vector3(0.0, (h0 + h1) * 0.5, 0.0)))
	p.origin_offset = Vector3(0.0, _plat + 1.7 - (h0 + h1) * 0.5, 0.0)
	chunk.add_child(p)


## The zone over every volume of the station: bodies in it pass through the city's ground box,
## the player in it switches the lights on; the station is registered while it is in the tree.
func _add_zone() -> void:
	var zone := Area3D.new()
	zone.name = "MetroZone"
	zone.collision_layer = 0
	zone.collision_mask = 2 | 4 | 8
	zone.monitorable = false
	for b: Array in MetroStation.volumes(f):
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(float(b[1]) - float(b[0]), float(b[3]) - float(b[2]), float(b[5]) - float(b[4]))
		cs.shape = bx
		cs.transform = Transform3D(Basis(_d3, Vector3.UP, _r3), _w(Vector3((float(b[0]) + float(b[1])) * 0.5, (float(b[2]) + float(b[3])) * 0.5, (float(b[4]) + float(b[5])) * 0.5)))
		zone.add_child(cs)
	var inside := {}
	var frame := f
	var lights := _lights
	frame["zone"] = zone
	frame["inside"] = inside
	zone.body_entered.connect(func(body_in: Node3D) -> void:
		MetroStation.sink(zone, body_in, true, inside)
		if body_in.is_in_group("player"):
			for l in lights:
				if is_instance_valid(l):
					l.visible = true)
	zone.body_exited.connect(func(body_out: Node3D) -> void:
		MetroStation.sink(zone, body_out, false, inside)
		if body_out.is_in_group("player"):
			for l in lights:
				if is_instance_valid(l):
					l.visible = false)
	zone.tree_entered.connect(func() -> void: MetroStation.register(frame))
	zone.tree_exiting.connect(func() -> void:
		MetroStation.unregister(frame)
		for body_in: Variant in inside.values():
			if is_instance_valid(body_in):
				MetroStation.sink(zone, body_in, false, inside))
	chunk.add_child(zone)


## People waiting on the platform and about the concourse (MetroRider), in the crowd cap.
func _add_riders() -> void:
	var idx := line.stations.find(f.st)
	var n_p := PLATFORM_RIDERS.x + int(hash01([plan.seed, "metro_riders"]) * float(PLATFORM_RIDERS.y - PLATFORM_RIDERS.x + 1))
	var n_c := CONCOURSE_RIDERS.x + int(hash01([plan.seed, "metro_conc"]) * float(CONCOURSE_RIDERS.y - CONCOURSE_RIDERS.x + 1))
	for k in n_p + n_c:
		if not chunk._take_crowd_room():
			return
		var ped := MetroRider.new()
		ped.line = line
		ped.station = idx
		ped.frame = f
		ped.level = 0 if k < n_p else 1
		ped.setup(Rect2(), 3.0, hash([plan.seed, "metro_rider", k]))
		var p := ped._random_ring_point(3.0)
		ped.position = Vector3(p.x, ped._ground_y(p.x, p.y, 0.0), p.y)
		chunk.add_child(ped)
