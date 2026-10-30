class_name SkyAds
extends Node3D
## Aerial advertising (docs/HANDOFF.md "Aerial advertising"): the FIZZLY blimp (AdBlimp) looping
## between the ballpark and the beach, its night sign scrolling, and banner tow planes
## (BannerPlane) flying laps off the beach with invented letter banners. A child of AirTraffic,
## made in its _setup() (`SKY_ADS=0` in the environment: none of it, the A/B); it borrows the
## traffic's obstacle field and ground for its routes and the crashes. Like AirTraffic's craft
## nothing here is simulated: each craft is placed on its AirRoute from a distance it advances.
##
## Every roll is a hash of the plan's seed and a key (`roll()`), never an rng: where on its loop
## each craft starts, which banner a plane tows, its daily hours. Who flies is pure
## (`blimp_flies()`, `banner_flies()`: the hour and the weather), checked by
## tests/sky_ads_checks.gd. A craft that is shot down is replaced `respawn_seconds` later.

## The blimp's loop: a circle over the ballpark and one over the beach (radius, m), the beach
## circle's centre (true world XZ; x is taken from the coast), and its least height over what
## is under it and above the sea (m).
@export var stadium_radius: float = 520.0
@export var beach_radius: float = 620.0
@export var beach_z: float = -420.0
@export var beach_inland: float = 120.0
@export var blimp_clearance: float = 170.0
@export var blimp_floor: float = 320.0
## The banner racetrack: from / to (true world z), its two legs' distances out from the
## waterline (m), and the two planes' heights over the sea (m).
@export var banner_z0: float = -2500.0
@export var banner_z1: float = 250.0
@export var banner_inner: float = 230.0
@export var banner_outer: float = 500.0
@export var banner_heights: Vector2 = Vector2(150.0, 175.0)
## Banner planes in the air at once, and the hours they fly (the second number each plane's
## landing time; a hash shifts each by up to `hour_jitter`).
@export var banner_planes: int = 2
@export var banner_hours: Vector2 = Vector2(9.0, 18.5)
@export var hour_jitter: float = 0.75
## Seconds before a shot-down craft is replaced.
@export var respawn_seconds: float = 240.0

## The night sign's lines and their colours (sRGB), LedScreen's 5 x 7 face (capitals, digits,
## ! & - . ').
const LED_LINES := [
	["FIZZLY", Color(1.0, 0.45, 0.1)],
	["TASTE THE LOUD!", Color(1.0, 1.0, 0.95)],
	["ORANGE - CHERRY - LIME", Color(0.95, 0.75, 0.15)],
	["ICE COLD AT THE BALLPARK", Color(0.35, 0.85, 1.0)],
	["FIZZLY", Color(1.0, 0.25, 0.2)],
	["GO RANDO!", Color(0.5, 1.0, 0.4)],
]
## Banners: the text (TextMesh's font, so any case) and the ink (sRGB). Every name is invented:
## the city's own billboard campaigns (tools/make_billboard_art.py) and a proposal.
const BANNERS := [
	["FIZZLY - TASTE THE LOUD", Color(0.85, 0.15, 0.08)],
	["CASA LUNARA TACOS 2 FOR 1", Color(0.10, 0.30, 0.15)],
	["SUNCREST AIR - FLY THE COAST", Color(0.10, 0.18, 0.55)],
	["DRIFT 104.1 FM", Color(0.45, 0.10, 0.50)],
	["MARRY ME DANA? - LUIS", Color(0.80, 0.10, 0.25)],
	["SEE THE LAST ORBIT FRIDAY", Color(0.05, 0.05, 0.08)],
	["RAMIREZ KOLB INJURY LAW", Color(0.10, 0.18, 0.55)],
	["HAPPY HOUR AT HOLLOW HOUSE", Color(0.05, 0.05, 0.08)],
]
## LedScreen glyph rows a text line takes, with a blank row above and below.
const LED_ROWS := 9

var air: Node
var plan: CityPlan
var macro: MacroMap
var blimp_route: AirRoute
var banner_routes: Array[AirRoute] = []
var blimp: AdBlimp
var planes: Array = []
var clock: float = 0.0
## Set by checks and stills: the hour and weather to schedule by (-1: the city's own).
var force_hour: float = -1.0
var force_weather: int = -1
## True while a still has staged the craft (the schedule leaves them alone).
var staged: bool = false
var _seed: int = 0
var _spawns: int = 0
var _blimp_respawn: float = 0.0
var _plane_respawn: PackedFloat32Array = PackedFloat32Array()
var _day: Node
var _weather: Node
var _tick: float = 0.0

static var _led: ImageTexture
static var _led_width: int = 0


## A 0..1 roll from the seed and a key (no rng: CLAUDE.md).
static func roll(seed_value: int, key: Variant) -> float:
	return float(hash([seed_value, "sky_ads", key]) & 0xFFFFFF) / float(0xFFFFFF)


## Whether the blimp flies at `hour` in weather `state` (Weather.State): it does, night and day,
## except in rain or a storm.
static func blimp_flies(_hour: float, state: int) -> bool:
	return state != 2 and state != 3


## Whether banner plane `i` flies at `hour` in `state`: by day, its own hours, not in rain or a
## storm.
func banner_flies(i: int, hour: float, state: int) -> bool:
	if state == 2 or state == 3:
		return false
	var a := banner_hours.x + (roll(_seed, ["up", i]) - 0.5) * hour_jitter
	var b := banner_hours.y + (roll(_seed, ["down", i]) - 0.5) * hour_jitter
	return hour >= a and hour <= b


func setup(traffic: Node) -> void:
	air = traffic
	plan = traffic.get("plan") as CityPlan
	macro = plan.macro
	_seed = plan.seed
	name = "SkyAds"
	var city := traffic.get_parent()
	_day = city.get_node_or_null("DayNight") if city else null
	_weather = city.get_node_or_null("Weather") if city else null
	_build_routes()
	var mat := SkyAdMesh.material()
	mat.set_shader_parameter("led_text", led_texture())
	mat.set_shader_parameter("led_strip", float(_led_width))
	mat.set_shader_parameter("led_size", Vector2(60.0, float(LED_ROWS)))
	_plane_respawn.resize(banner_planes)
	planes.resize(banner_planes)
	_schedule(0.0, true)


func _physics_process(delta: float) -> void:
	advance(delta)


## One tick of the schedule (the craft move themselves).
func advance(dt: float) -> void:
	if air == null:
		return
	clock += dt
	_tick -= dt
	_blimp_respawn -= dt
	for i in _plane_respawn.size():
		_plane_respawn[i] -= dt
	if _tick > 0.0:
		return
	_tick = 1.0
	_schedule(1.0, false)


func hour() -> float:
	if force_hour >= 0.0:
		return force_hour
	return float(_day.get("hour")) if _day else 12.0


func weather_state() -> int:
	if force_weather >= 0:
		return force_weather
	return int(_weather.get("state")) if _weather else 0


func _schedule(_dt: float, at_load: bool) -> void:
	if staged:
		return
	var h := hour()
	var st := weather_state()
	if blimp_flies(h, st):
		if blimp == null and _blimp_respawn <= 0.0:
			blimp = spawn_blimp(-1.0, not at_load)
	elif blimp and blimp.life == AmbientCraft.Life.FLYING:
		blimp.fading_out = true
	for i in planes.size():
		var p: BannerPlane = planes[i]
		if banner_flies(i, h, st):
			if p == null and _plane_respawn[i] <= 0.0:
				planes[i] = spawn_plane(i, -1.0, not at_load)
		elif p and p.life == AmbientCraft.Life.FLYING:
			p.fading_out = true


## The blimp at distance `d` along its loop (-1: where the clock puts it), faded in or not.
func spawn_blimp(d: float = -1.0, fade_in: bool = true) -> AdBlimp:
	var b := AdBlimp.new()
	b.traffic = air
	b.route = blimp_route
	var at := d if d >= 0.0 else roll(_seed, "blimp") * blimp_route.length + clock * b.speed
	b.place_at(at)
	if fade_in:
		b.fade = 1.0
	_enter(b)
	b.finished.connect(_on_blimp_gone)
	return b


## Banner plane `i`, `d` along its racetrack (-1: the clock's place), towing the banner its
## roll picks.
func spawn_plane(i: int, d: float = -1.0, fade_in: bool = true, banner_index: int = -1) -> BannerPlane:
	var p := BannerPlane.new()
	p.traffic = air
	var r: AirRoute = banner_routes[i % banner_routes.size()]
	p.route = r
	var pick := banner_index if banner_index >= 0 else banner_pick(i, _spawns)
	_spawns += 1
	p.text = BANNERS[pick][0]
	p.ink = BANNERS[pick][1]
	var at := d if d >= 0.0 else (roll(_seed, ["plane", i]) + float(i) / maxf(float(banner_planes), 1.0)) * r.length + clock * p.speed
	p.place_at(at)
	if fade_in:
		p.fade = 1.0
	_enter(p)
	p.finished.connect(_on_plane_gone.bind(i))
	return p


## Which banner plane `i` tows on its `n`th flight.
func banner_pick(i: int, n: int) -> int:
	return int(roll(_seed, ["banner", i, n]) * BANNERS.size()) % BANNERS.size()


func _enter(c: AmbientCraft) -> void:
	# Placed BEFORE it enters the tree (AirTraffic._place_before_entry(): a kinematic body that
	# entered at the origin and was moved kilometres in a step lent the player its speed).
	c.transform = Transform3D(Basis.from_euler(Vector3(c.pitch, c.yaw, c.roll)), to_local(WorldState.to_local(c.world_pos)))
	add_child(c)
	c.apply_pose()


func _on_blimp_gone(c: AmbientCraft) -> void:
	if c == blimp:
		blimp = null
		if c.life != AmbientCraft.Life.FLYING:
			_blimp_respawn = respawn_seconds


func _on_plane_gone(c: AmbientCraft, i: int) -> void:
	if i < planes.size() and planes[i] == c:
		planes[i] = null
		if c.life != AmbientCraft.Life.FLYING:
			_plane_respawn[i] = respawn_seconds


func crafts() -> Array:
	var out: Array = []
	if blimp and is_instance_valid(blimp):
		out.append(blimp)
	for p in planes:
		if p and is_instance_valid(p):
			out.append(p)
	return out


func clear_all() -> void:
	for c in crafts():
		c.remove()
	blimp = null
	for i in planes.size():
		planes[i] = null


# --- Routes -----------------------------------------------------------------------------------

## The ballpark's home plate (true world XZ): the blimp's first circle.
func stadium_centre() -> Vector2:
	return Ballpark.world(0.0, 110.0)


func beach_centre() -> Vector2:
	return Vector2(macro.coast_x(beach_z) + beach_inland, beach_z)


func _build_routes() -> void:
	blimp_route = _blimp_loop()
	banner_routes.clear()
	for k in 2:
		banner_routes.append(_banner_loop(banner_heights[k], k))


## A full circle over the ballpark, the run to the beach, a full circle there and back; the
## loop starts and ends half way along the run back, so the seam is straight and level.
func _blimp_loop() -> AirRoute:
	var c1 := stadium_centre()
	var c2 := beach_centre()
	var to2 := (c2 - c1).normalized()
	var pts := PackedVector2Array()
	var radii := PackedFloat32Array()
	var mid := (c1 + c2) * 0.5
	pts.append(mid)
	radii.append(0.0)
	for circle in 2:
		var c := c1 if circle == 0 else c2
		var r := stadium_radius if circle == 0 else beach_radius
		var toward := to2 if circle == 0 else -to2
		var a0 := atan2(-toward.y, -toward.x)
		# Twelve corners round the circle, entered from the run, left back along it.
		for k in 13:
			var a := a0 + TAU * float(k) / 12.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
			radii.append(r * 0.9)
		if circle == 0:
			pts.append(mid + Vector2(-to2.y, to2.x) * 90.0)
			radii.append(600.0)
	pts.append(mid)
	radii.append(0.0)
	var route := AirRoute.from_waypoints(pts, radii, "sky_ads_blimp", 25.0, 0.48)
	var need := PackedFloat32Array()
	need.resize(route.xz.size())
	for i in route.xz.size():
		var p: Vector2 = route.xz[i]
		var top: float = air.call("obstacle_top", p)
		need[i] = maxf(top + blimp_clearance, blimp_floor)
		route.y[i] = need[i]
	# Grade-limited to an airship's gentle climbs; then the seam's two ends agree.
	route.clear(need, 0.035, 0.035)
	var seam := maxf(route.y[0], route.y[route.y.size() - 1])
	need[0] = seam
	need[need.size() - 1] = seam
	route.clear(need, 0.035, 0.035)
	return route


## A racetrack along the waterline: the inner leg `banner_inner` out heading north, the outer
## leg `banner_outer` out heading south, a level `height` over the sea.
func _banner_loop(height: float, k: int) -> AirRoute:
	var pts := PackedVector2Array()
	var radii := PackedFloat32Array()
	var n := maxi(2, ceili((banner_z1 - banner_z0) / 160.0))
	var zs := PackedFloat32Array()
	for i in n + 1:
		zs.append(lerpf(banner_z1, banner_z0, float(i) / n))
	var rt := (banner_outer - banner_inner) * 0.5
	var mid := n / 2
	# Start half way up the inner leg (a straight seam), run north to the end, turn out to sea
	# round a half circle, south down the outer leg, round the other end and back.
	for i in range(mid, n + 1):
		pts.append(Vector2(macro.coast_x(zs[i]) - banner_inner, zs[i]))
		radii.append(260.0)
	for end in 2:
		var ze: float = banner_z0 if end == 0 else banner_z1
		var c := Vector2(macro.coast_x(ze) - (banner_inner + banner_outer) * 0.5, ze)
		var bulge := -1.0 if end == 0 else 1.0
		for q in range(1, 6):
			var a := PI * float(q) / 6.0
			pts.append(c + Vector2(cos(a) * rt * (1.0 if end == 0 else -1.0), sin(a) * rt * bulge))
			radii.append(rt * 0.9)
		if end == 0:
			for i in range(n, -1, -1):
				pts.append(Vector2(macro.coast_x(zs[i]) - banner_outer, zs[i]))
				radii.append(260.0 if i != n and i != 0 else rt * 0.9)
		else:
			for i in range(0, mid + 1):
				pts.append(Vector2(macro.coast_x(zs[i]) - banner_inner, zs[i]))
				radii.append(260.0 if i != 0 else rt * 0.9)
	radii[0] = 0.0
	radii[radii.size() - 1] = 0.0
	var route := AirRoute.from_waypoints(pts, radii, "sky_ads_banner_%d" % k, 20.0, 0.48)
	var need := PackedFloat32Array()
	need.resize(route.xz.size())
	for i in route.xz.size():
		route.y[i] = height
		need[i] = maxf(height, float(air.call("obstacle_top", route.xz[i])) + 80.0)
	route.clear(need, 0.06, 0.06)
	return route


# --- The night sign ---------------------------------------------------------------------------

## The sign's text strip: every line of LED_LINES in its colour on LedScreen's 5 x 7 face, a
## blank gap between, LED_ROWS rows (the shader scrolls it and wraps).
static func led_texture() -> ImageTexture:
	if _led:
		return _led
	var gap := 24
	var width := 0
	for line: Array in LED_LINES:
		width += LedScreen.text_width(line[0]) + gap
	var img := Image.create(width, LED_ROWS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var x := 0
	for line: Array in LED_LINES:
		var t: String = line[0]
		var col: Color = line[1]
		for ch in t:
			var rows: Array = LedScreen.GLYPHS.get(ch, LedScreen.GLYPHS[" "])
			for r in 7:
				var row: String = rows[r]
				for cc in 5:
					if row[cc] == "#":
						img.set_pixel(x + cc, 1 + r, col)
			x += 6
		x += gap - 1
	_led_width = width
	_led = ImageTexture.create_from_image(img)
	return _led


static func led_width() -> int:
	led_texture()
	return _led_width


# --- Stills -----------------------------------------------------------------------------------

## Stages a craft `dist` metres ahead of `cam` (`side` to its right), crossing the view left to
## right, `rise` metres over the eye: "blimp" or "banner" (`pick` the banner). They then fly on
## a straight line through the spot, slowly (`creep` of their speed), so a few frames settle.
func stage(kind: String, cam: Camera3D, dist: float, side: float = 0.0, rise: float = -1.0, pick: int = 0) -> AmbientCraft:
	staged = true
	clear_all()
	var eye := WorldState.to_world(cam.global_position)
	var fwd := -cam.global_basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var right := Vector3(-flat.z, 0.0, flat.x)
	var spot := eye + flat * dist + right * side
	spot.y = eye.y + (rise if rise >= 0.0 else dist * 0.18)
	var a := Vector2(spot.x, spot.z) - Vector2(right.x, right.z) * 3000.0
	var b := Vector2(spot.x, spot.z) + Vector2(right.x, right.z) * 3000.0
	var r := AirRoute.from_waypoints(PackedVector2Array([a, b]), PackedFloat32Array([0.0, 0.0]), "sky_ads_stage")
	for i in r.y.size():
		r.y[i] = spot.y
	if kind == "blimp":
		blimp_route = r
		var bl := spawn_blimp(3000.0, false)
		blimp = bl
		bl.speed = 0.5
		return bl
	banner_routes = [r, r]
	var p := spawn_plane(0, 3000.0, false, pick)
	planes[0] = p
	p.speed = 0.5
	return p
