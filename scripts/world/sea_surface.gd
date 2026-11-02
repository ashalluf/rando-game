class_name SeaSurface
extends RefCounted
## The ocean's height in GDScript: shaders/ocean.gdshader's vertex stage (the five Gerstner
## swells in wave groups, the shoaling taper, the tsunami, the surf of surf.gdshaderinc and the
## held-down level near the shore) worked out at one point, so a swimmer floats on the water that
## is drawn (Swim, scripts/player/swim.gd). The same model and the same constants as the shader
## (its uniforms' defaults: nothing sets them at run time), mirrored the way Surf mirrors
## surf.gdshaderinc; change one, change both (tests/swimming_checks.gd compares the swell
## constants with the shader source). The ripple LOD (`fine`) is 1: the swimmer is near the camera.
##
## Time: the shader's TIME, which runs from the engine's start scaled by Engine.time_scale.
## `clock` starts at the engine's ticks and Swim advances it by the scaled process delta.

const MESH_Y := 0.15
## The ocean shader's uniform defaults (base_height ... surf_width): checked against its source.
const BASE_HEIGHT := 1.2
const SWELL_LENGTH := 97.0
const GROUP_LENGTH := 310.0
const GROUP_DEPTH := 0.55
const SPEED := 1.0
const TSUNAMI_HEIGHT := 30.0
const TSUNAMI_LENGTH := 420.0
const TSUNAMI_DIR := Vector2(1.0, 0.15)
const SWASH_WIDTH := 14.0
const SURF_WIDTH := 72.0
## [direction, length divisor, amp share, lean] of the five swells, as the shader's vertex().
const SWELLS := [
	[Vector2(1.00, 0.22), 1.0, 0.34, 0.75],
	[Vector2(0.86, -0.51), 1.59, 0.26, 0.85],
	[Vector2(0.62, 0.78), 2.62, 0.19, 0.95],
	[Vector2(0.97, -0.24), 4.51, 0.13, 1.05],
	[Vector2(0.34, 0.94), 7.89, 0.08, 1.10],
]

static var clock: float = -1.0


## The shader clock now (seconds).
static func now() -> float:
	if clock < 0.0:
		clock = float(Time.get_ticks_msec()) / 1000.0
	return clock


static func advance(dt: float) -> void:
	clock = now() + dt


## The sea state the shaders are drawing: [wave_scale, tsunami_scale, surf_shape, surf_extra].
static func state(tree: SceneTree) -> Array:
	var waves := 1.0
	var tsunami := 0.0
	var gain := 1.0
	var city := tree.get_first_node_in_group("city") if tree else null
	var w: Node = city.get_node_or_null("Weather") if city else null
	if w and w.get("wave_scale") != null:
		waves = float(w.get("wave_scale"))
		gain = float(w.get("surf_gain"))
		var left := float(w.get("_tsunami_left"))
		if left > 0.0:
			tsunami = float(w.get("tsunami_strength")) * sin((1.0 - left / maxf(float(w.get("tsunami_seconds")), 0.01)) * PI)
	var p := Surf.params(waves, gain)
	return [waves, tsunami, p[0], p[1]]


# --- the shader's helpers ---------------------------------------------------------------------

static func _fract(x: float) -> float:
	return x - floorf(x)


static func hash12(p: Vector2) -> float:
	var p3 := Vector3(_fract(p.x * 0.1031), _fract(p.y * 0.1031), _fract(p.x * 0.1031))
	var d := p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3(33.33, 33.33, 33.33))
	p3 += Vector3(d, d, d)
	return _fract((p3.x + p3.y) * p3.z)


static func vnoise(p: Vector2) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := p - i
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := hash12(i)
	var b := hash12(i + Vector2(1.0, 0.0))
	var c := hash12(i + Vector2(0.0, 1.0))
	var d := hash12(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)


## ocean.gdshader shore_distance(): (metres offshore, 0 landward; the signed distance).
static func shore_distance(m: MacroMap, p: Vector2) -> Vector2:
	var cx := minf(m._main_coast_x(p.y), m.headland_west_x(p.y))
	var d := cx - p.x
	var off := d
	if p.y > m.bay_z and p.x < m.bay_east_x and p.x > cx:
		d = minf(m.bay_east_x - p.x, p.y - m.bay_z)
	if d < 0.0:
		d = 0.0 if d > -300.0 else 300.0
	var pen := m.headland_dist(p) - 2.0
	return Vector2(minf(d, maxf(pen, 0.0)), off)


# --- the surf (surf.gdshaderinc) ----------------------------------------------------------------

static func _surf_noise(p: Vector2) -> float:
	return vnoise(p) # surf_hash / surf_noise are hash12 / vnoise line for line


static func _surf_wob(p: Vector2) -> float:
	return 9.0 * (_surf_noise(p / 95.0) - 0.5) + 4.0 * (_surf_noise(p / 33.0 + Vector2(7.3, 7.3)) - 0.5)


static func _wave_gain(n: float, p: Vector2) -> float:
	var sets := 0.5 + 0.5 * sin(n * 0.85 + _surf_noise(p / 400.0) * 3.0)
	var wave := hash12(Vector2(n, 17.0))
	var section := _surf_noise(p / 70.0 + Vector2(n * 0.61, n * 0.23))
	return Surf.H_LO + Surf.H_SPAN * (0.40 * sets + 0.25 * wave + 0.35 * section)


static func _profile(u: float, steep: float) -> float:
	var wf := lerpf(0.40, 0.13, steep)
	if u > 1.0 - wf:
		var v := (u - (1.0 - wf)) / wf
		return pow(v, lerpf(1.6, 2.6, steep))
	var v2 := u / (1.0 - wf)
	return (1.0 - v2) * (1.0 - v2)


## surf_height(): metres over the mean water at p, s metres offshore, time t.
static func surf_height(shape: Vector4, extra: Vector4, p: Vector2, s: float, t: float) -> float:
	var phi := ((s + _surf_wob(p)) / maxf(shape.y, 1.0) + t / maxf(shape.z, 0.5))
	var n := floorf(phi)
	var u := phi - n
	var mean := Surf.envelope(shape, extra, s, 1.0)
	var steep := mean.z
	var wf := lerpf(0.40, 0.13, steep)
	var nw := n + 1.0 if u > 1.0 - wf else n
	var g := _wave_gain(nw, p)
	var env := Surf.envelope(shape, extra, s, g)
	return shape.x * (g * env.x * _profile(u, steep) - 0.22 * mean.x)


# --- the sea ------------------------------------------------------------------------------------

## The displacement of the sea surface built at TRUE world p (x, y up, z), as vertex() adds it.
static func displacement(m: MacroMap, p: Vector2, t: float, st: Array) -> Vector3:
	var waves: float = st[0]
	var tsunami: float = st[1]
	var shape: Vector4 = st[2]
	var extra: Vector4 = st[3]
	var tt := t * SPEED
	var sd := shore_distance(m, p)
	var reach := smoothstep(SWASH_WIDTH * 0.3, SURF_WIDTH, sd.x)
	var shoal := reach * (1.0 + 5.0 * reach * (1.0 - reach))
	var grp := vnoise(p / GROUP_LENGTH + Vector2(tt * 0.006, -tt * 0.004))
	var group := 1.0 - GROUP_DEPTH * (1.0 - grp)
	var open := BASE_HEIGHT * maxf(waves, 0.05)
	var amp := open * shoal * group
	var sy := 0.0
	var zone := maxf(extra.z, 1.0)
	if sd.x > 0.01 and sd.x < zone:
		var gs := Vector2(shore_distance(m, p + Vector2(2.0, 0.0)).x - sd.x, shore_distance(m, p + Vector2(0.0, 2.0)).x - sd.x) * 0.5
		if gs.length() > 0.3:
			sy = surf_height(shape, extra, p, sd.x, t)
			amp *= lerpf(0.3, 1.0, smoothstep(shape.w * 0.8, zone, sd.x))
	var lean_k := clampf(3.6 / maxf(open, 0.1), 0.55, 1.0)
	var disp := Vector3.ZERO
	var l0 := maxf(SWELL_LENGTH, 8.0)
	for w: Array in SWELLS:
		disp += _gerstner(p, (w[0] as Vector2).normalized(), l0 / float(w[1]), amp * float(w[2]), float(w[3]) * lean_k, tt)
	if tsunami > 0.001:
		disp += _gerstner(p, TSUNAMI_DIR.normalized(), TSUNAMI_LENGTH, TSUNAMI_HEIGHT * tsunami, 1.20 * lean_k, tt * 0.9)
	disp.y += sy
	var near_shore := 1.0 - smoothstep(70.0, 110.0, sd.x)
	if near_shore > 0.0:
		var lo := -0.10
		var k := 0.12
		var hk := clampf(0.5 + 0.5 * (disp.y - lo) / k, 0.0, 1.0)
		var held := lerpf(lo, disp.y, hk) + k * hk * (1.0 - hk)
		disp.y = lerpf(disp.y, held, near_shore)
	return disp


static func _gerstner(p: Vector2, dir: Vector2, length: float, amp: float, lean: float, t: float) -> Vector3:
	var k := TAU / length
	var c := sqrt(9.8 / k)
	var f := k * (dir.dot(p) - c * t)
	var sf := sin(f)
	return Vector3(-lean * amp * dir.x * sf, amp * cos(f), -lean * amp * dir.y * sf)


## The height of the drawn sea surface over TRUE world XZ `p` at time t: the Gerstner surface
## moves points sideways as well as up, so the point that lands over p is found by two fixed-point
## steps back along the horizontal displacement.
static func height(m: MacroMap, p: Vector2, t: float, st: Array) -> float:
	var q := p
	var d := Vector3.ZERO
	for i in 3:
		d = displacement(m, q, t, st)
		q = p - Vector2(d.x, d.z)
	return MESH_Y + d.y


## The surface's slope at p (dh/dx, dh/dz), for tilting a floating body: central differences.
static func slope(m: MacroMap, p: Vector2, t: float, st: Array, h: float = 0.8) -> Vector2:
	var hx := height(m, p + Vector2(h, 0.0), t, st) - height(m, p - Vector2(h, 0.0), t, st)
	var hz := height(m, p + Vector2(0.0, h), t, st) - height(m, p - Vector2(0.0, h), t, st)
	return Vector2(hx, hz) / (2.0 * h)


## Depth of the sea floor the swimmer can reach, `s` metres offshore (y, negative): the sand's
## own profile under the water (CityChunk SAND_STEEP_* / SAND_LOW), then shelving down to the
## floor box the water chunks draw at -13.5.
static func seabed(s: float) -> float:
	if s < CityChunk.SAND_STEEP_AT:
		return lerpf(MESH_Y, CityChunk.SAND_STEEP_Y, clampf(s / CityChunk.SAND_STEEP_AT, 0.0, 1.0))
	if s < CityChunk.SAND_WET:
		return lerpf(CityChunk.SAND_STEEP_Y, CityChunk.SAND_LOW, (s - CityChunk.SAND_STEEP_AT) / (CityChunk.SAND_WET - CityChunk.SAND_STEEP_AT))
	return maxf(CityChunk.SAND_LOW - (s - CityChunk.SAND_WET) * 0.09, -13.0)
