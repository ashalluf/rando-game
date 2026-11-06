class_name PursuitLook
extends RefCounted
## The police pursuit at night (refcam5 `police_pursuit`, tools/refcams/cameras_w8.json;
## docs/HANDOFF.md "The police pursuit at night"). What the refcam found, fixed here:
##
##   searchlight  the police helicopter's beam drew a flat white disc ~30 m across that swallowed
##                the street, the cars' wheels and the lane paint: the SpotLight3D, an additive pool
##                (strength 1.6 plus a 2.6 core, lifted 25 cm so it painted over every tyre) and the
##                drawn shaft's foot all landed on the same spot, each enough to clip it alone. Seen
##                from a car under it the shaft's cone wall was a pale veil over half the frame. Now
##                the spot does the lighting, the pool is only the hot middle a real lamp throws
##                (`POOL_STRENGTH`, `CORE_STRENGTH`, the beam's own width, `POOL_LIFT` 4 cm), and
##                the shaft fades out at its foot and near the lens (searchlight_beam.gdshader
##                `foot_fade`, `near_from` / `near_to`).
##   flashes     the bar strobed each bank twice in a tenth of its cycle (a bank lit 36 % of the
##               time), so most frames - and every still caught between strobes - showed no red or
##               blue on the street at all. `flash_side()` is a modern LED triple flash: three
##               pulses a side over 0.42 of each half, one bank lit 72 % of the time (the bar's and
##               the washes' shaders carry the same pattern, `pattern` 1; checked).
##   washes      the pool a cruiser throws on the road was a soft dot flat out to 13 m: lit, the
##               road round a cruiser beside the camera went one blue-white sheet. It is the light of
##               a lamp at bar height now (police_wash.gdshader `point_pool`), and the lens glare is
##               smaller up close (`WASH_GLARE`).
##   light bar   six flat unshaded boxes read as two coloured bricks from the chase camera:
##               `light_bar_mesh()` is a low LED bar - a black housing under a clear tinted dome
##               with rows of LED pods in it, red and blue banks and clear takedown lamps in the
##               middle (police_lights.gdshader `led`), the same size and banks as the old one.
##
## Hook lines: PoliceCar._build_light_bar() (`dress_bar()`), PoliceCar.flash_side(),
## PoliceNightLook._make_glow() (`dress_wash()`), Helicopter._build_searchlight() (`dress_searchlight()`) and Helicopter._aim_gear()
## (`pool_dia()`, `POOL_LIFT`). PURSUIT_LOOK=0 in the environment is the A/B (the old look).

static var enabled: bool = OS.get_environment("PURSUIT_LOOK") != "0"

## The pool's light (additive, on top of the spot's) and its white-hot middle.
const POOL_STRENGTH := 0.32
const CORE_STRENGTH := 0.55
## How far over the ground the pool rides (the old 25 cm drew it over the tyres and kerbs).
const POOL_LIFT := 0.04
## The pool's diameter over the beam's own width where it lands.
const POOL_SPREAD := 1.05
## The shaft: the share of its length at the ground end it fades out over, and the distances from
## the camera (m) inside which it fades away (a cone wall a few metres off is not haze).
const SHAFT_FOOT := 0.22
const SHAFT_NEAR_FROM := 6.0
const SHAFT_NEAR_TO := 45.0
## The shaft's strength (the old look 0.22).
const SHAFT_STRENGTH := 0.16


## Called once the searchlight is built: the pool and its core rebuilt soft and faint, the shaft's
## fades set. Returns nothing; the old look is left untouched when off.
static func dress_searchlight(pool: MeshInstance3D, beam_mat: ShaderMaterial, spot: SpotLight3D = null) -> void:
	if not enabled:
		return
	if spot:
		spot.spot_angle_attenuation = SPOT_EDGE
	if pool:
		pool.mesh = PropFactory.light_pool(Color(0.85, 0.92, 1.0), POOL_STRENGTH, 1.7)
		var core := pool.get_node_or_null("PoolCore") as MeshInstance3D
		if core:
			core.mesh = PropFactory.light_pool(Color(0.95, 0.98, 1.0), CORE_STRENGTH, 3.2)
			core.position = Vector3(0.0, 0.0, 0.01)
			core.scale = Vector3(0.38, 0.38, 1.0)
	if beam_mat:
		beam_mat.set_shader_parameter("foot_fade", SHAFT_FOOT)
		beam_mat.set_shader_parameter("near_from", SHAFT_NEAR_FROM)
		beam_mat.set_shader_parameter("near_to", SHAFT_NEAR_TO)
		beam_mat.set_shader_parameter("strength", SHAFT_STRENGTH)


## The pool's diameter for a beam `reach` metres long of half-angle `angle_deg` (the old rule,
## 1.25 x the width plus 2 m, when off).
static func pool_dia(reach: float, angle_deg: float) -> float:
	var w := 2.0 * reach * tan(deg_to_rad(angle_deg))
	return w * POOL_SPREAD if enabled else w * 1.25 + 2.0


## The searchlight's own light (x Helicopter.searchlight_energy): at full strength the road under it
## clipped to flat white at the night exposure and every texture in the beam was gone.
const SPOT_GAIN := 0.6
## The spot's cone falloff (SpotLight3D.spot_angle_attenuation, the old 0.6): lower is a hotter middle
## and a softer rim - the old rim drew a hard circle round the car, the red and blue inside it pink.
const SPOT_EDGE := 0.3


static func spot_gain() -> float:
	return SPOT_GAIN if enabled else 1.0


static func pool_lift() -> float:
	return POOL_LIFT if enabled else 0.25


## Which bank is lit at `f` (0..1 into the flash cycle): 1 red, -1 blue, 0 dark. The shaders'
## `strobe()` with `pattern` 1, bit for bit.
static func flash_side(f: float) -> int:
	if _pulse(f, 0.0):
		return 1
	if _pulse(f, 0.5):
		return -1
	return 0


static func _pulse(f: float, start: float) -> bool:
	var u := f - start
	return u >= 0.0 and u <= 0.42 and fmod(u, 0.15) <= 0.12


## The cruiser's bar: the LED mesh and its shading on (the old bar when off).
static func dress_bar(bar: MeshInstance3D, mat: ShaderMaterial) -> void:
	if not enabled:
		return
	bar.mesh = light_bar_mesh()
	mat.set_shader_parameter("pattern", 1.0)
	mat.set_shader_parameter("led", 1.0)


## A cruiser's wash (PoliceNightLook): the same flash pattern as its bar.
static func dress_wash(mat: ShaderMaterial, pool_metres: float = 30.0) -> void:
	if enabled:
		mat.set_shader_parameter("pattern", 1.0)
		mat.set_shader_parameter("point_pool", 1.0)
		mat.set_shader_parameter("pool_metres", pool_metres)
		mat.set_shader_parameter("glare_size", WASH_GLARE)


## The lit lens's glare (m; police_wash.gdshader's `glare_size`, 0.7): at the chase camera's 5 m the
## old one was a red smear the width of the cruiser's roof. Its `min_px` keeps it from going small.
const WASH_GLARE := 0.3


static var _bar_mesh: ArrayMesh = null

## The bar's extent (m): as long and as wide as PoliceCar's old one, a little lower.
const BAR_HALF_X := 0.61
const BAR_HALF_Z := 0.145
const HOUSING_Y := 0.06
const DOME_Y := 0.148
## Where the clear middle (takedown lamps) ends and the coloured banks begin.
const MID_HALF_X := 0.075


## Housing plus a domed lens over LED pods, one mesh, the banks in the vertex alpha as PoliceCar's
## (0 housing / clear, 0.5 red, 1 blue); UV.x metres along the bar, UV2 (way round the dome's
## profile 0..1, or -1 for the housing).
static func light_bar_mesh() -> ArrayMesh:
	if _bar_mesh != null:
		return _bar_mesh
	_bar_mesh = ArrayMesh.new()
	_bar_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, light_bar_arrays())
	return _bar_mesh


## The bar's surface arrays (the checks read them: the headless renderer keeps no mesh data).
static func light_bar_arrays() -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var black := Color(0.03, 0.03, 0.035, 0.0)
	# The housing: a low box with its top edges chamfered.
	var hx := BAR_HALF_X + 0.01
	var hz := BAR_HALF_Z + 0.012
	var ch := 0.012
	var sec := [Vector2(-hz, 0.0), Vector2(-hz, HOUSING_Y - ch), Vector2(-hz + ch, HOUSING_Y),
		Vector2(hz - ch, HOUSING_Y), Vector2(hz, HOUSING_Y - ch), Vector2(hz, 0.0)]
	_extrude(st, sec, -hx, hx, black, -1.0, true)
	# The dome's profile across the bar (z, y), from the back edge over the top to the front.
	var prof: Array = []
	var n := 10
	for i in n + 1:
		var a := PI * (1.0 - float(i) / float(n))
		var y := HOUSING_Y + (DOME_Y - HOUSING_Y) * pow(sin(a), 0.6)
		prof.append(Vector2(BAR_HALF_Z * cos(a), y))
	var red := Color(1.0, 0.06, 0.04, 0.5)
	var blue := Color(0.10, 0.26, 1.0, 1.0)
	var clear := Color(0.9, 0.92, 0.95, 0.0)
	_extrude(st, prof, -BAR_HALF_X, -MID_HALF_X, red, 0.0, false)
	_extrude(st, prof, -MID_HALF_X, MID_HALF_X, clear, 0.0, false)
	_extrude(st, prof, MID_HALF_X, BAR_HALF_X, blue, 0.0, false)
	# The dome's end caps.
	for sx in [-1.0, 1.0]:
		var x: float = sx * BAR_HALF_X
		var c := Vector3(x, HOUSING_Y, 0.0)
		for i in n:
			var p0: Vector2 = prof[i]
			var p1: Vector2 = prof[i + 1]
			_tri(st, [c, Vector3(x, p0.y, p0.x), Vector3(x, p1.y, p1.x)], Vector3(sx, 0.0, 0.0), red if sx < 0.0 else blue, -1.0)
	return st.commit_to_arrays()


## A section (z, y) swept along x from x0 to x1, its faces facing out from the bar's axis; the ends
## closed when `cap`. `uv2` -1 marks the housing; otherwise UV2.y runs 0..1 round the section.
static func _extrude(st: SurfaceTool, sec: Array, x0: float, x1: float, col: Color, uv2: float, cap: bool) -> void:
	var m := sec.size()
	for i in m - 1:
		var a: Vector2 = sec[i]
		var b: Vector2 = sec[i + 1]
		var mid := (a + b) * 0.5
		# Out from the bar's axis: the housing's middle height, or the dome's foot.
		var out := Vector3(0.0, mid.y - (HOUSING_Y if uv2 >= 0.0 else HOUSING_Y * 0.5), mid.x).normalized()
		var va := [Vector3(x0, a.y, a.x), Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x0, b.y, b.x)]
		var s0 := float(i) / float(m - 1)
		var s1 := float(i + 1) / float(m - 1)
		var w0 := Vector2(-1.0 if uv2 < 0.0 else 0.0, s0)
		var w1 := Vector2(-1.0 if uv2 < 0.0 else 0.0, s1)
		_quad(st, va, [w0, w0, w1, w1], out, col)
	if cap:
		for sx in [-1.0, 1.0]:
			var x: float = x0 if sx < 0.0 else x1
			var c := Vector3(x, HOUSING_Y * 0.5, 0.0)
			for i in m - 1:
				var a: Vector2 = sec[i]
				var b: Vector2 = sec[i + 1]
				_tri(st, [c, Vector3(x, a.y, a.x), Vector3(x, b.y, b.x)], Vector3(sx, 0.0, 0.0), col, -1.0)
			_tri(st, [c, Vector3(x, (sec[m - 1] as Vector2).y, (sec[m - 1] as Vector2).x), Vector3(x, (sec[0] as Vector2).y, (sec[0] as Vector2).x)], Vector3(sx, 0.0, 0.0), col, -1.0)


static func _quad(st: SurfaceTool, v: Array, w: Array, n: Vector3, col: Color) -> void:
	_tri_w(st, [v[0], v[1], v[2]], [w[0], w[1], w[2]], n, col)
	_tri_w(st, [v[0], v[2], v[3]], [w[0], w[2], w[3]], n, col)


static func _tri(st: SurfaceTool, v: Array, n: Vector3, col: Color, uv2x: float) -> void:
	var w := Vector2(uv2x, 0.5)
	_tri_w(st, v, [w, w, w], n, col)


## One triangle wound clockwise as seen from the side `n` faces (the project's front faces).
static func _tri_w(st: SurfaceTool, v: Array, w: Array, n: Vector3, col: Color) -> void:
	var a: Vector3 = v[0]
	var b: Vector3 = v[1]
	var c: Vector3 = v[2]
	var order := [0, 1, 2]
	if (b - a).cross(c - a).dot(n) > 0.0:
		order = [0, 2, 1]
	for k in order:
		var p: Vector3 = v[k]
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(Vector2(p.x, p.y))
		st.set_uv2(w[k])
		st.add_vertex(p)
